#!/usr/bin/env node
'use strict';
/**
 * mode-owed.cjs - once the operator opened a question dialog in an autonomous run and a question round was answered,
 * the mode question ("continue autonomously?") is OWED until it is asked; work does not run on past it.
 *
 * WHY (measured 2026-11-23 on the macOS instance, from a session transcript): the run was autonomous; the operator
 * asked what was open for them. The agent asked round 1 (4 questions), did measuring calls, asked round 2 (4), then ran
 * about 40 work calls (PR creates, task messages, a shared-memory post, edits, a build), asked round 3 (2) in the
 * middle of the work, and never asked the mode question. The operator (translated): "the mode question never came ...
 * I want the questions always collected as well as possible, then continue working." mode-question-order-gate
 * (question-gate.cjs `modeAlone`) holds a mode question that comes too EARLY; nothing held work while it was owed, and
 * nothing held a turn end with it owed. Questions known at round 1 came only in rounds 2 and 3.
 *
 * Three entries:
 *   post   PostToolUse on the question tool: the answered call asked the mode question -> nothing owed; otherwise, when
 *          the operator's newest prompt asked what is open in a run that was autonomous before it, the mode question is
 *          owed from this answer round on (state .claude-state/mode-owed.json, per session).
 *   pre    called by autonomous-gate.cjs on every tool call (no extra process): while owed, the question tool and
 *          reading tools pass uncounted; after BUDGET other calls (recording the answers, the steps they set off)
 *          the next one is held ONCE per answer round: ask the remaining collected questions now, all at once, the
 *          mode question last.
 *   stop   Stop check (stop-dispatcher row MODE-OWED): a turn end with the mode question owed is held once; a newer
 *          operator prompt that did not ask what is open ends the debt instead.
 * Frequency design: one hold per answer round in `pre`, one per round at the turn end; a re-issued call or turn end
 * passes. BUDGET = 3: the incident needed 3 calls after an answer round (recording the answers and the dialog
 * steps) before work started. Fails open on every read error. Replay: node mode-owed.cjs --replay <transcript>
 * Fixture: scripts/test-mode-owed.sh
 */
const fs = require('fs');
const path = require('path');

const BUDGET = 3;
const READS = new Set(['Read', 'Grep', 'Glob', 'LS', 'NotebookRead', 'ToolSearch', 'ListAgents', 'TaskOutput', 'TaskGet', 'TaskList']);

function root(input) { return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd(); }
function stateFile(r) { return path.join(r, '.claude-state', 'mode-owed.json'); }
function load(r) { try { return JSON.parse(fs.readFileSync(stateFile(r), 'utf8')) || {}; } catch (e) { return {}; } }
function save(r, st) {
  try { fs.mkdirSync(path.dirname(stateFile(r)), { recursive: true }); fs.writeFileSync(stateFile(r), JSON.stringify(st) + '\n'); } catch (e) { /* fail open */ }
}
const sid = (input) => String((input && input.session_id) || 'no-session');

function asksModeQ(r, qs) {
  try {
    const am = require('./autonomous-mode.cjs');
    const on = am.words(r).on;
    return (qs || []).some((q) => am.asksMode(on, String((q && q.question) || '')));
  } catch (e) { return false; }
}

/** Did the operator's newest prompt ask what is open, in a run that was autonomous before it? */
function dialogOpened(transcript, r) {
  let rows = [];
  try { rows = require('./autonomous-mode.cjs').promptModes(transcript, r); } catch (e) { return null; }
  let i = rows.length - 1;
  while (i >= 0 && rows[i].answer) i -= 1;
  if (i < 0 || !rows[i].asks) return false;
  for (let j = i - 1; j >= 0; j -= 1) if (!rows[j].answer || rows[j].autonomous) return Boolean(rows[j].autonomous);
  return false;
}

function post(input) {
  const r = root(input);
  const st = load(r);
  const qs = (input.tool_input && input.tool_input.questions) || [];
  if (asksModeQ(r, qs)) { delete st[sid(input)]; save(r, st); return; }
  const prev = st[sid(input)];
  if (!prev && !dialogOpened(input.transcript_path || '', r)) return;
  st[sid(input)] = { owed: true, round: String(input.tool_use_id || Date.now()), calls: 0, held: false, stopHeld: false,
    at: new Date().toISOString() };
  save(r, st);
}

const HOLD = 'MODE-OWED: the operator opened a question dialog and a question round is answered - the mode question ("continue '
  + 'autonomously?") is owed, and work has started past it. Not issued, once per answer round. Ask the REMAINING collected '
  + 'questions now, all of them in one question-tool call (every operator-only item you know of, not one more round later), '
  + 'carry out what their answers set off, then ask the mode question alone, last. Re-issue this call only if nothing is '
  + 'left to ask - it passes. (Measured 2026-11-23: three question rounds, about 40 work calls between them, no mode question.)';

function pre(input, r) {
  const tool = (input && input.tool_name) || '';
  if (tool === 'AskUserQuestion' || READS.has(tool)) return null;
  const rt = r || root(input);
  const st = load(rt);
  const s = st[sid(input)];
  if (!s || !s.owed) return null;
  s.calls += 1;
  if (s.calls <= BUDGET || s.held) { save(rt, st); return null; }
  s.held = true;
  save(rt, st);
  return HOLD;
}

function stop(input) {
  const r = root(input);
  const st = load(r);
  const s = st[sid(input)];
  if (!s || !s.owed || input.stop_hook_active || s.stopHeld) return null;
  // a newer operator prompt that did not ask what is open ends the dialog the debt belonged to
  if (dialogOpened(input.transcript_path || '', r) === false && s.calls > 0) {
    let rows = []; try { rows = require('./autonomous-mode.cjs').promptModes(input.transcript_path || '', r); } catch (e) { rows = []; }
    const last = rows.filter((x) => !x.answer).pop();
    if (last && last.at && Date.parse(s.at) < last.at) { delete st[sid(input)]; save(r, st); return null; }
  }
  s.stopHeld = true;
  save(r, st);
  return 'MODE-OWED: this turn ends with the mode question owed - the operator opened a question dialog and answered a round, '
    + 'and "continue autonomously?" was never asked. Ask the remaining collected questions (all at once), then the mode '
    + 'question alone, last. Re-issue to pass.';
}

/** Replay over a transcript: where would `pre` have held? Prints one line per answer round and hold. It assumes every
 *  answered round belongs to a dialog the operator opened (the live `post` checks that with promptModes). */
function replay(tp) {
  const lines = fs.readFileSync(tp, 'utf8').split('\n');
  const seen = new Set();
  const askIds = new Map(); let owed = false; let calls = 0; let held = false; let n = 0; const out = [];
  const r = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let on = null; let asksMode = null;
  try { const am = require('./autonomous-mode.cjs'); on = am.words(r).on; asksMode = am.asksMode; } catch (e) { /* none */ }
  for (const l of lines) {
    n += 1;
    let d; try { d = JSON.parse(l); } catch (e) { continue; }
    const c = d && d.message && Array.isArray(d.message.content) ? d.message.content : [];
    for (const b of c) {
      if (b && b.type === 'tool_use') {
        if (b.name === 'AskUserQuestion') {
          const mode = asksMode && ((b.input && b.input.questions) || []).some((q) => asksMode(on, String(q.question || '')));
          askIds.set(b.id, mode); continue;
        }
        if (!owed || READS.has(b.name)) continue;
        calls += 1;
        if (calls > BUDGET && !held) { held = true; out.push(`line ${n}: hold before ${b.name} (${calls} calls after the answers) at ${d.timestamp || '?'}`); }
      } else if (b && b.type === 'tool_result' && askIds.has(b.tool_use_id) && !b.is_error) {
        if (seen.has(b.tool_use_id)) continue;   // a result can stand twice in a transcript
        seen.add(b.tool_use_id);
        if (askIds.get(b.tool_use_id)) { owed = false; continue; }
        owed = true; calls = 0; held = false;
        out.push(`line ${n}: answer round ${b.tool_use_id} at ${d.timestamp || '?'} - mode question owed`);
      }
    }
  }
  return out;
}

// Ends naturally (process.exitCode), never with a forced exit: that hung at Node shutdown after a transcript read
// (2026-11-23, agent-brain #632/#633).
if (require.main === module) {
  const cmd = process.argv[2];
  process.exitCode = 0;
  if (cmd === '--replay') {
    console.log(replay(process.argv[3]).join('\n'));
  } else {
    let raw = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { raw += c; });
    process.stdin.on('end', () => {
      let input = null;
      try { input = JSON.parse(raw); } catch (e) { input = null; }
      if (!input) return;
      try {
        if (cmd === 'post') post(input);
        else if (cmd === 'stop') { const why = stop(input); if (why) console.log(JSON.stringify({ decision: 'block', reason: why })); }
      } catch (e) { /* fail open */ }
    });
  }
}

module.exports = { pre, post, stop, replay, BUDGET };
