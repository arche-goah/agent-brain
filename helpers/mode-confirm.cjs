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
 *         mode-confirm question needs at least two options; the mode the operator's words name comes first (towards
 *         interactive the interactive option first, towards autonomous the scope options first, "stay interactive" last).
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

/** The byte after the last newline at or before `size` (a half-written last line is not yet read). */
function completeEnd(tp, size) {
  try {
    const n = Math.min(size, 1 << 20);
    const fd = fs.openSync(tp, 'r');
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, size - n);
    fs.closeSync(fd);
    const i = buf.lastIndexOf(0x0a);
    return i < 0 ? size - n : size - n + i + 1;
  } catch (e) { return 0; }
}

/** The pending mode word {direction, text, at} or null, re-read only when the transcript moved. */
function pending(input, r) {
  const tp = input.transcript_path || '';
  let size;
  try { size = fs.statSync(tp).size; } catch (e) { return null; }
  const st = load(r);
  const s = st[sid(input)];
  // The cache advances only to the end of the last COMPLETE line: a record half written at call time is read again,
  // whole, next time (Windows review of #672, 2026-11-25: with the size moved to the file's end, a half-written answer
  // line left the hold standing until the next prompt).
  if (s && s.size <= size) {
    let buf = null;
    try {
      const fd = fs.openSync(tp, 'r');
      buf = Buffer.alloc(size - s.size);
      fs.readSync(fd, buf, 0, buf.length, s.size);
      fs.closeSync(fd);
    } catch (e) { buf = null; }
    if (buf) {
      const end = buf.lastIndexOf(0x0a) + 1; // bytes of complete lines in the delta
      if (!moves(buf.subarray(0, end).toString('utf8'))) { s.size += end; save(r, st); return s.pending || null; }
    }
  }
  let p = null;
  try { p = require('./autonomous-mode.cjs').confirmPending(tp, r); } catch (e) { return null; }
  st[sid(input)] = { size: completeEnd(tp, size), pending: p, stopHeld: s && p && s.pending && s.pending.at === p.at ? s.stopHeld : false };
  save(r, st);
  return p;
}

function ask(p) {
  return p.direction === 'autonomous'
    ? 'ask ONE question-tool question with header "mode-confirm": what is to be handled autonomously - the options name '
      + 'the scope (the work of this prompt, the open list, ...), and the LAST option is always "stay interactive"'
    : 'ask ONE question-tool question with header "mode-confirm": "continue interactively?" - the FIRST option is the '
      + 'interactive one ("continue interactively", the recommended one: the operator\'s words named it), the other one '
      + '"stay autonomous"';
}

function pre(input, r) {
  const tool = (input && input.tool_name) || '';
  if (READS.has(tool)) return null;
  const rt = r || root(input);
  // the instance switch (autonomous-patterns.json `mode_confirm`): off = the direct switch, nothing to check here
  if (!require('./autonomous-mode.cjs').words(rt).confirm) return null;
  if (tool === 'AskUserQuestion') {
    const am = require('./autonomous-mode.cjs');
    const qs = (input.tool_input && input.tool_input.questions) || [];
    const w = am.words(rt);
    const on = w.on;
    // Where the interactive option stands: first when the waiting mode word asks for interactive (the named mode comes
    // first, operator 2026-11-26), else last (towards autonomous, or no mode word waiting).
    const p = pending(input, rt);
    const dir = p && p.direction;
    const where = dir === 'interactive' ? 'FIRST' : 'LAST';
    const bad = qs.filter((q) => am.isConfirm(q) && ((q.options || []).length < 2));
    if (bad.length) {
      return `MODE-CONFIRM: a mode-confirm question needs at least two options - the ${where.toLowerCase()} one is the interactive one `
        + '("stay interactive" / "continue interactively"). Not issued; ask it again with the options.';
    }
    // The answer is read by position (interactiveAt), so a misordered list is held here, at ask time (Windows review of
    // #672: "Stay interactive" written first switched ON). Not language-complete: it catches the likely slip - an
    // on-word in the interactive slot, an off-word or "interactive" in any other. The rule lives in ONE place
    // (autonomous-mode.cjs `misordered`): the reader uses the same one for a question asked under the old order.
    const misordered = qs.filter((q) => {
      if (!am.isConfirm(q)) return false;
      const ls = (q.options || []).map((o) => String((o && o.label) || ''));
      return am.misordered(w, ls, am.interactiveAt(ls.length, dir));
    });
    if (misordered.length) {
      return `MODE-CONFIRM: in this mode-confirm question the interactive option must be the ${where} one, and only that one - `
        + `the answer is read by position. Not issued; reorder the options (the interactive option ${where.toLowerCase()}).`;
    }
    // EVERY mode switch goes through the mode-confirm question, also the mode question at the end of a question dialog
    // ("continue autonomously?") - operator 2026-11-25, translated: "for a mode switch ALWAYS an interactive question",
    // "with a mode switch there shall ALWAYS be a short explanation". A mode question in the old form is held once more.
    if (qs.some((q) => !am.isConfirm(q) && am.asksMode(on, String((q && q.question) || '')))) {
      return 'MODE-CONFIRM: this question asks about the run mode but is no mode-confirm question. Not issued. Ask it with '
        + `header "mode-confirm", the interactive option ${where} ("stay interactive" / "continue interactively"), and the short `
        + `explanation in the question text, in the operator's language: ${EXPLAIN}`;
    }
    return null;
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
