#!/usr/bin/env node
'use strict';
/**
 * mode-confirm.cjs - a recognised mode word opens the mode-confirm question; work does not run on past it.
 *
 * WHY (operator order 2026-11-25, translated): "a recognised mode word - word list OR intent reader - never switches by
 * itself. It opens a question: towards autonomous with options for WHAT is to be handled autonomously, plus always
 * 'stay interactive'; towards interactive explicitly 'continue interactively?'. Only the answer switches." And: "every
 * switch question carries a short explanation of what the mode means - no extended rights, just collecting questions
 * or asking them at once, and whatever else really differs." Measured cause: the intent classifier set mode_on on a
 * sentence about another party's AI (macOS instance, .claude-state/intent-classifier.jsonl 2026-11-25T12:46:20Z), and
 * 47 of that brain's 5562 classifier records switched to autonomous against the word lists.
 *
 * The switch itself is safe by construction: autonomous-mode.cjs moves the latch only on the answer to a question whose
 * header is `mode-confirm` (CONFIRM_HEADER there). This helper makes the question COME:
 *   pre   called by autonomous-gate.cjs on every tool call (no extra process): while a mode word waits for its answer,
 *         every call but a read and the question tool is held, with the question to ask and its explanation. A
 *         mode-confirm question needs at least two options (the last one is the interactive one).
 *   stop  Stop check (stop-dispatcher row MODE-CONFIRM): a turn end with the question not asked is held once per mode word.
 * Cost: the transcript is re-read only when the bytes appended since the last call hold an operator prompt or a
 * question-tool result (state .claude-state/mode-confirm.json, per session) - the reader takes about 1.2 s on a
 * 270 MB transcript. Fails open on every read error. Fixture: scripts/test-mode-confirm.sh
 */
const fs = require('fs');
const path = require('path');

const READS = new Set(['Read', 'Grep', 'Glob', 'LS', 'NotebookRead', 'ToolSearch', 'ListAgents', 'TaskOutput', 'TaskGet', 'TaskList']);

// Every claim below stands in docs/run-modes.md ("The one difference", "AUTONOMOUS"); nothing else is said.
const EXPLAIN = 'What the modes mean (docs/run-modes.md): no extra rights in either mode - the same permissions, refusals '
  + 'and gates, nothing irreversible becomes allowed. The one difference: interactive asks a question for the operator at '
  + 'once (question tool); autonomous collects it in the ledger and works on, and holds back calls an ask rule would turn '
  + 'into a dialog. In both modes the work goes on; a turn does not end idle while own work is open.';

function root(input) { return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd(); }
function stateFile(r) { return path.join(r, '.claude-state', 'mode-confirm.json'); }
function load(r) { try { return JSON.parse(fs.readFileSync(stateFile(r), 'utf8')) || {}; } catch (e) { return {}; } }
function save(r, st) {
  try { fs.mkdirSync(path.dirname(stateFile(r)), { recursive: true }); fs.writeFileSync(stateFile(r), JSON.stringify(st) + '\n'); } catch (e) { /* fail open */ }
}
const sid = (input) => String((input && input.session_id) || 'no-session');

/** Could the bytes appended to the transcript move the pending state? An operator prompt or a question-tool result. */
function moves(delta) {
  for (const l of delta.split('\n')) {
    if (l.includes('queued_command')) return true;
    if (!l.includes('"type":"user"')) continue;
    if (!l.includes('"tool_result"') || /questions have been answered|The user answered:|AskUserQuestion|doesn't want to proceed|rejected/.test(l)) return true;
  }
  return false;
}

/** The pending mode word {direction, text, at} or null, re-read only when the transcript moved. */
function pending(input, r) {
  const tp = input.transcript_path || '';
  let size;
  try { size = fs.statSync(tp).size; } catch (e) { return null; }
  const st = load(r);
  const s = st[sid(input)];
  if (s && s.size <= size) {
    let delta = '';
    try {
      const fd = fs.openSync(tp, 'r');
      const buf = Buffer.alloc(size - s.size);
      fs.readSync(fd, buf, 0, buf.length, s.size);
      fs.closeSync(fd);
      delta = buf.toString('utf8');
    } catch (e) { delta = '\n"type":"user"\n'; }
    if (!moves(delta)) { s.size = size; save(r, st); return s.pending || null; }
  }
  let p = null;
  try { p = require('./autonomous-mode.cjs').confirmPending(tp, r); } catch (e) { return null; }
  st[sid(input)] = { size, pending: p, stopHeld: s && p && s.pending && s.pending.at === p.at ? s.stopHeld : false };
  save(r, st);
  return p;
}

function ask(p) {
  return p.direction === 'autonomous'
    ? 'ask ONE question-tool question with header "mode-confirm": what is to be handled autonomously - the options name '
      + 'the scope (the work of this prompt, the open list, ...), and the LAST option is always "stay interactive"'
    : 'ask ONE question-tool question with header "mode-confirm": "continue interactively?" - the LAST option is the '
      + 'interactive one ("continue interactively"), the other one "stay autonomous"';
}

function pre(input, r) {
  const tool = (input && input.tool_name) || '';
  if (READS.has(tool)) return null;
  const rt = r || root(input);
  if (tool === 'AskUserQuestion') {
    const am = require('./autonomous-mode.cjs');
    const bad = ((input.tool_input && input.tool_input.questions) || []).filter((q) => am.isConfirm(q) && ((q.options || []).length < 2));
    return bad.length ? 'MODE-CONFIRM: a mode-confirm question needs at least two options - the last one is the interactive one '
      + '("stay interactive" / "continue interactively"). Not issued; ask it again with the options.' : null;
  }
  const p = pending(input, rt);
  if (!p) return null;
  return `MODE-CONFIRM: the operator's words "${String(p.text || '').replace(/\s+/g, ' ').slice(0, 80)}" read as a switch to `
    + `${p.direction.toUpperCase()} - a mode word never switches by itself, only the answer to the mode-confirm question does `
    + '(operator order 2026-11-25). Not issued. First ' + ask(p) + '. The question text carries this short explanation, in '
    + `the operator's language: ${EXPLAIN} The mode stays as it is until the answer comes; then repeat this call.`;
}

function stop(input) {
  if (input.stop_hook_active) return null;
  const r = root(input);
  const p = pending(input, r);
  if (!p) return null;
  const st = load(r);
  const s = st[sid(input)];
  if (!s || s.stopHeld) return null;
  s.stopHeld = true;
  save(r, st);
  return `MODE-CONFIRM: this turn ends with a mode word unanswered (read as a switch to ${p.direction}). ${ask(p)}, with the `
    + 'short explanation of what the modes mean (docs/run-modes.md). The mode stays as it is until then. Re-issue to pass.';
}

// Ends naturally (process.exitCode), never with a forced exit (agent-brain #632/#633).
if (require.main === module && process.argv[2] === 'stop') {
  process.exitCode = 0;
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input = null;
    try { input = JSON.parse(raw); } catch (e) { input = null; }
    if (!input) return;
    try { const why = stop(input); if (why) console.log(JSON.stringify({ decision: 'block', reason: why })); } catch (e) { /* fail open */ }
  });
}

module.exports = { pre, stop, moves, EXPLAIN };
