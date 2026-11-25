#!/usr/bin/env node
// covers: agent-model-gate
// Fixture for helpers/agent-model-gate.cjs: both directions, plus the record a passing spawn leaves.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const { execFileSync } = require('child_process');
const GATE = path.join(__dirname, '..', 'helpers', 'agent-model-gate.cjs');
const { judge } = require(GATE);

let pass = 0;
const ok = (name, fn) => { fn(); pass++; console.log('  OK   ' + name); };
const call = (prompt, model, type) => ({ tool_name: 'Agent', tool_input: { prompt, ...(model ? { model } : {}), ...(type ? { subagent_type: type } : {}) } });
const denied = (inp, needle) => { const d = judge(inp); assert.ok(d, 'expected a denial'); if (needle) assert.ok(d.includes(needle), `"${needle}" not in: ${d}`); };
const passes = (inp) => assert.strictEqual(judge(inp), null);

ok('no model line -> denied, with the form and the call\'s model', () => denied(call('Read the six files and list the open points.', 'sonnet'), 'This call: model sonnet'));
ok('line and call agree -> passes', () => passes(call('Read the six files.\nModel: sonnet — reading and tagging every line, no judgment needed', 'sonnet')));
ok('inherit named, call sets no model -> passes', () => passes(call('Model: inherit - weighing evidence for and against, the session model\nJudge the findings.')));
ok('line names a class, call inherits -> denied', () => denied(call('Model: sonnet — reading only\nRead.'), 'sets no model'));
ok('line says inherit, call sets a model -> denied', () => denied(call('Model: inherit — the session model judges\nJudge.', 'haiku'), 'sets model haiku'));
ok('line and call name different classes -> denied', () => denied(call('Model: haiku — collecting file names\nCollect.', 'opus'), 'says haiku'));
ok('a word that is no class -> denied', () => denied(call('Model: fast — whatever\nDo it.', 'sonnet'), 'no model class'));
ok('no reason -> denied', () => denied(call('Model: sonnet — ok\nRead.', 'sonnet'), 'no reason'));
ok('the line may stand anywhere in the prompt, as a list item, with "choice"', () => passes(call('Task: read.\n- Model choice: haiku (copying paths from one listing into a file)\nGo.', 'haiku')));
ok('a fork is not asked: it always runs on the parent\'s model', () => passes(call('Continue with the review.', undefined, 'fork')));
ok('another tool is not asked', () => assert.strictEqual(judge({ tool_name: 'Bash', tool_input: { command: 'ls' } }), null));
ok('unreadable input fails open', () => {
  assert.strictEqual(judge(null), null);
  for (const ti of [undefined, null, 'a string']) assert.strictEqual(judge({ tool_name: 'Agent', tool_input: ti }), null, `tool_input ${ti}`);
});
// review findings on #653 (Windows instance, fable family, 2026-11-25), each in the direction it failed
const REVIEW_FORM = 'Return your review with the lines Fit: / Design: / Cost: / Gaps: /\nModel: fable (the family that judged)\n';
ok('a quoted review-form Model line BEFORE the own line -> the own line counts', () => passes(call(REVIEW_FORM + 'Model: sonnet — reading and tagging every changed file\nReview.', 'sonnet')));
ok('a quoted line naming no class before the own line -> passes', () => passes(call('Model: Claude Fable 5.2 (claude-fable-5-2)\nModel: haiku — copying paths from one listing\nGo.', 'haiku')));
ok('only a quoted line of ANOTHER class -> denied, the text says every line is read', () => denied(call(REVIEW_FORM + 'Review.', 'sonnet'), 'every Model line is read'));
ok('a full model id counts by its family', () => passes(call('Model: sonnet — reading and tagging every line\nRead.', 'claude-sonnet-4-5')));
ok('a variant counts by its family', () => passes(call('Model: sonnet — reading and tagging every line\nRead.', 'sonnet[1m]')));
ok('a capitalised class counts', () => passes(call('Model: Sonnet — reading and tagging every line\nRead.', 'Sonnet')));
ok('a model parameter that names no class -> denied, said so', () => denied(call('Model: sonnet — reading and tagging every line\nRead.', 'mythos'), 'names no model class'));
ok('"Fork" (any case) is a fork', () => passes(call('Continue.', undefined, 'Fork')));

// the hook as a process: the deny shape, and the record of a passing spawn (only with a session id)
const T = fs.mkdtempSync(path.join(os.tmpdir(), 'amg-'));
try {
  const run = (inp) => execFileSync(process.execPath, [GATE], { input: JSON.stringify(inp), encoding: 'utf8', env: { ...process.env, CLAUDE_PROJECT_DIR: T } });
  ok('a UTF-8 BOM before a deny-worthy call still denies', () => {
    const o = execFileSync(process.execPath, [GATE], { input: String.fromCharCode(0xFEFF) + JSON.stringify(call('Read.', 'sonnet')), encoding: 'utf8', env: { ...process.env, CLAUDE_PROJECT_DIR: T } });
    assert.strictEqual(JSON.parse(o).hookSpecificOutput.permissionDecision, 'deny');
  });
  ok('a denial is a PreToolUse deny decision', () => { const o = JSON.parse(run(call('Read.', 'sonnet'))); assert.strictEqual(o.hookSpecificOutput.permissionDecision, 'deny'); assert.ok(o.hookSpecificOutput.permissionDecisionReason.startsWith('AGENT-MODEL:')); });
  const good = call('Model: sonnet — reading and tagging, no judgment\nRead.', 'sonnet', 'general-purpose');
  ok('a passing spawn without a session id writes no record', () => { assert.strictEqual(run(good), ''); assert.ok(!fs.existsSync(path.join(T, '.claude-state', 'agent-spawns.jsonl'))); });
  ok('a passing spawn of a session leaves one record line', () => {
    assert.strictEqual(run({ ...good, session_id: 's1' }), '');
    const lines = fs.readFileSync(path.join(T, '.claude-state', 'agent-spawns.jsonl'), 'utf8').trim().split('\n');
    assert.strictEqual(lines.length, 1);
    const r = JSON.parse(lines[0]);
    assert.strictEqual(r.model, 'sonnet'); assert.strictEqual(r.type, 'general-purpose'); assert.ok(r.why.includes('reading and tagging'));
  });
  ok('a denied spawn leaves no record line', () => { run({ ...call('Read.', 'sonnet'), session_id: 's1' }); assert.strictEqual(fs.readFileSync(path.join(T, '.claude-state', 'agent-spawns.jsonl'), 'utf8').trim().split('\n').length, 1); });
  console.log(`test-agent-model-gate: ${pass} passed`);
} finally {
  fs.rmSync(T, { recursive: true, force: true });
}
