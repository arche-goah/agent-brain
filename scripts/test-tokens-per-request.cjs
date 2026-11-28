#!/usr/bin/env node
// Fixture for scripts/tokens-per-request.cjs: a transcript folder built in a temp dir, every number known.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const { measure, isoWeek } = require('./tokens-per-request.cjs');
const tk = require('../helpers/turn-kind.cjs');

const T = fs.mkdtempSync(path.join(os.tmpdir(), 'tpr-'));
const w = (file, recs) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, recs.map((r) => JSON.stringify(r)).join('\n') + '\n'); };
const user = (ts, text, extra) => ({ type: 'user', timestamp: ts, message: { role: 'user', content: text }, ...(extra || {}) });
const call = (ts, id, i, cw, cr, o) => ({ type: 'assistant', timestamp: ts, message: { id, role: 'assistant', content: [], usage: { input_tokens: i, cache_creation_input_tokens: cw, cache_read_input_tokens: cr, output_tokens: o } } });
const result = (ts) => ({ type: 'user', timestamp: ts, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'x', content: 'ok' }] } });
let pass = 0;
const ok = (name, fn) => { fn(); pass++; console.log('  OK   ' + name); };

try {
  // Session A, Monday 2026-11-16: two requests.
  w(path.join(T, 'a.jsonl'), [
    user('2026-11-16T10:00:00.000Z', 'first request'),
    call('2026-11-16T10:00:05.000Z', 'm1', 10, 100, 1000, 5),      // the same call written twice (streaming):
    call('2026-11-16T10:00:06.000Z', 'm1', 10, 100, 1000, 50),     // the record with the most output counts, once
    result('2026-11-16T10:00:07.000Z'),                            // a tool result opens no request
    call('2026-11-16T10:00:08.000Z', 'm2', 20, 0, 1200, 30),
    user('2026-11-16T10:00:09.000Z', '<task-notification>\n<status>completed</status>\n</task-notification>'),   // no request
    call('2026-11-16T10:00:10.000Z', 'm3', 1, 0, 1300, 9),
    user('2026-11-16T10:05:00.000Z', 'peer says hi', { origin: { kind: 'peer' } }),                              // no request
    user('2026-11-16T11:00:00.000Z', 'second request'),
    call('2026-11-16T11:00:05.000Z', 'm4', 7, 3, 0, 2),
  ]);
  // Its sub-agent: one call inside the first request, one inside the second.
  w(path.join(T, 'a', 'subagents', 'agent-1.jsonl'), [
    call('2026-11-16T10:00:30.000Z', 's1', 1000, 2000, 3000, 400),
    call('2026-11-16T11:30:00.000Z', 's2', 1, 1, 1, 1),
  ]);
  // Session B, the week after; a sub-agent call BEFORE its first typed prompt belongs to no request.
  w(path.join(T, 'b.jsonl'), [
    call('2026-11-23T08:00:00.000Z', 'x0', 5, 5, 5, 5),            // before any typed prompt: counted to nothing
    user('2026-11-23T09:00:00.000Z', 'third request'),
    call('2026-11-23T09:00:01.000Z', 'x1', 100, 0, 0, 100),
  ]);
  w(path.join(T, 'b', 'subagents', 'agent-2.jsonl'), [call('2026-11-23T08:30:00.000Z', 't1', 11, 22, 33, 44)]);
  // A headless model call: no session, its prompt opens no request.
  w(path.join(T, 'h.jsonl'), [
    { type: 'user', entrypoint: 'sdk-cli', timestamp: '2026-11-16T12:00:00.000Z', message: { role: 'user', content: 'classify this' } },
    call('2026-11-16T12:00:01.000Z', 'h1', 9999, 9999, 9999, 9999),
  ]);

  const rep = measure(T, '0000-00-00', '9999-99-99', 'week');
  ok('two sessions, the headless call is none', () => assert.strictEqual(rep.sessions, 2));
  ok('week keys', () => assert.deepStrictEqual(Object.keys(rep.rows), ['2026-W47', '2026-W48']));
  const a = rep.rows['2026-W47'];
  ok('two requests in the first week (notification and peer message open none)', () => assert.strictEqual(a.requests, 2));
  // request 1: own m1 (10+100+1000+50) + m2 (20+0+1200+30) + m3 (1+0+1300+9) = 3720 total, spent 10+100+50+20+30+1+9 = 220
  //            agent s1: total 6400, spent 3400            -> total 10120, spent 3620
  // request 2: own m4 total 12, spent 12; agent s2 total 4, spent 3 -> total 16, spent 15
  ok('a call written twice counts once, with its final output', () => assert.strictEqual(a.sum_own, 3720 + 12));
  ok('sub-agent calls land in the request they ran in', () => assert.strictEqual(a.sum_agents, 6400 + 4));
  ok('spent leaves the cache reads out', () => assert.strictEqual(a.sum_spent, 3620 + 15));
  ok('median and p90 of two requests', () => { assert.strictEqual(a.med_total, 10120); assert.strictEqual(a.p90_total, 10120); assert.strictEqual(a.med_spent, 3620); });
  ok('requests with agents', () => assert.strictEqual(a.with_agents, 2));
  ok('calls per request', () => assert.strictEqual(a.med_calls, 3));
  const b = rep.rows['2026-W48'];
  ok('a call before the first typed prompt belongs to no request', () => { assert.strictEqual(b.requests, 1); assert.strictEqual(b.sum_own, 200); });
  ok('a sub-agent call outside every request span is reported, not lost', () => assert.strictEqual(rep.unassigned_agent_tokens, 110));
  ok('since/until cut by the request start', () => assert.deepStrictEqual(Object.keys(measure(T, '2026-11-20', '9999-99-99', 'week').rows), ['2026-W48']));
  ok('by day', () => assert.deepStrictEqual(Object.keys(measure(T, '0000-00-00', '9999-99-99', 'day').rows), ['2026-11-16', '2026-11-23']));
  ok('iso week at a year boundary', () => { assert.strictEqual(isoWeek('2026-12-31'), '2026-W53'); assert.strictEqual(isoWeek('2027-01-04'), '2027-W01'); assert.strictEqual(isoWeek('2026-01-01'), '2026-W01'); });
  ok('the headless reader: first entrypoint decides', () => { assert.strictEqual(tk.isHeadlessTranscript(path.join(T, 'h.jsonl')), true); assert.strictEqual(tk.isHeadlessTranscript(path.join(T, 'a.jsonl')), false); });

  // The question tool: an answer and a refusal with the operator's own message stay inside the request that asked.
  const Q = path.join(T, 'q');
  const ask = (ts, id, qid) => ({ type: 'assistant', timestamp: ts, message: { id, role: 'assistant', content: [{ type: 'tool_use', id: qid, name: 'AskUserQuestion', input: {} }], usage: { input_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1 } } });
  const answer = (ts, qid, text, isError) => ({ type: 'user', timestamp: ts, message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: qid, content: text, ...(isError ? { is_error: true } : {}) }] } });
  const qrecs = [
    user('2026-11-24T09:00:00.000Z', 'request with questions'),
    ask('2026-11-24T09:00:01.000Z', 'q1', 'toolu_q1'),
    answer('2026-11-24T09:01:00.000Z', 'toolu_q1', 'User has answered your questions: "Go?"="Yes (Recommended)"'),
    call('2026-11-24T09:01:01.000Z', 'q2', 10, 0, 0, 10),
    ask('2026-11-24T09:02:00.000Z', 'q3', 'toolu_q3'),
    answer('2026-11-24T09:03:00.000Z', 'toolu_q3', "The user doesn't want to proceed with this tool use. The user said: do the other one first", true),
    call('2026-11-24T09:03:01.000Z', 'q4', 100, 0, 0, 100),
    user('2026-11-24T10:00:00.000Z', 'next typed request'),
    call('2026-11-24T10:00:01.000Z', 'q5', 5, 0, 0, 5),
  ];
  w(path.join(Q, 'q.jsonl'), qrecs);
  const qr = measure(Q, '0000-00-00', '9999-99-99', 'day').rows['2026-11-24'];
  ok('question tool: an answer and a refusal with a message open no request', () => assert.strictEqual(qr.requests, 2));
  ok('question tool: the calls after them belong to the request that asked', () => assert.strictEqual(qr.sum_own, 2 + 20 + 2 + 200 + 10));
  ok('question tool: the gates read the same answer as an operator word (questionAnswers), on purpose', () => {
    const isAnswer = tk.questionAnswers();
    assert.deepStrictEqual(qrecs.map((d) => isAnswer(d)), [false, false, true, false, false, false, false, false, false]);
  });
  console.log(`test-tokens-per-request: ${pass} passed`);
} finally {
  fs.rmSync(T, { recursive: true, force: true });
}
