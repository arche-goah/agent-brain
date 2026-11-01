#!/usr/bin/env node
/**
 * Stop Hook: the one trigger in the system that fires on SUCCESS, not on friction.
 *
 * Measured 2026-08-06 on the proving instance: every existing trigger fired on risk
 * (sensitive file, known shortcut, unfinished marker) — none fired BECAUSE work
 * succeeded. A solution that works produces no signal, so the class question
 * ("where does the SAME defect live elsewhere?") never arose by itself: across eight
 * timestamped cases, a class sweep only ran when the instance fix FAILED or the
 * operator pushed. This gate closes that: after a turn that changed code, it asks
 * for goal & level, the invariant behind the work, and the register state.
 *
 * Proven mechanics, kept exactly (14 days of live operation, 37 firing sessions,
 * measured 2026-08-19 before this moved into the core):
 *
 * - TURN WINDOW from the transcript, never the git working tree. Version 1 read
 *   `git diff HEAD` and measured HISTORY: it flagged a stale artifact from five
 *   days earlier and stayed blind to work committed within the turn. The window is
 *   everything since the last real operator message; counted are the file_path
 *   arguments of Edit/Write/MultiEdit/NotebookEdit. Known limit, deliberate: files
 *   written via Bash are invisible — the alternative would be the working tree again.
 * - COOLDOWN of 3 operator turns after each block, read from the gate's own
 *   feedback echo in the transcript (stateless, survives restarts). An unconditional
 *   trigger becomes wallpaper: measured after THREE turns, not four weeks.
 * - ORDER: goal & level first, class second. Classes are countable, and countable
 *   feels like progress — asked first, the gate rewarded breadth over height
 *   (operator finding 2026-08-06: "I want the big picture, not the microscopic end").
 * - Doc-only and scratch-only turns pass silently; blocks at most once per turn.
 * - ANSWERED IN ADVANCE passes (2026-10-12): a ⚙ line in the agent's text after the turn's
 *   last edit IS the answer this gate asks for. Before, the gate blocked every code turn
 *   regardless - the harness shows every Stop block to the operator as "Stop hook error",
 *   so even a turn that already carried its ⚙ line put an error line in the operator's
 *   terminal (operator, same day: "please solve this globally for all my machines").
 *   The block now only fires when the line is missing.
 *
 * Build threshold (operator decision 2026-08-06): search always · 1 site = done ·
 * 2 = fix both, no mechanism · >=3 or repeat after a fix = build a mechanism.
 * "Outside the order: list, don't fix" guards scope, NOT finishing — what is in
 * reach and belongs to the same matter gets done, not tabled.

 * INPUT IS READ TO ITS END, never on a timer. Until 2026-08-20 this ran in a
 * setTimeout(..., 400): if the timer fires before the first data event the buffer is
 * empty, JSON.parse throws, and the hook silently allows. Measured on a sibling hook
 * with 0 ms — same input, same file, once blocking and once completely silent. 400 ms
 * mitigates that, it does not promise it, and a gate that fails open at random is
 * indistinguishable from one that agrees.
 */
const fs = require('fs');
const path = require('path');
// A harness notification (task done, watcher event) is not an operator turn — it must not
// count down this gate's cooldown (2026-10-07; one definition: turn-kind.cjs).
const { isNotification, isAgentOrigin, isTranscriptRecord, questionAnswers } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

// The harness replays a blocked turn's feedback as an operator message. It must not
// end the turn window — after the first block the window would be empty otherwise.
const HOOK_ECHO = /^Stop hook feedback:/;
let OWN_ECHO = /CLASS-GATE|KLASSEN-GATE/; // legacy marker kept: old echoes still count

// After a block the gate stays quiet for this many real operator turns. 3 instead of
// "every time": often enough that a fix chain cannot slip through, rare enough that
// it never becomes wallpaper.
const COOLDOWN_TURNS = 3;
// The answer this gate asks for: a line that starts with the gear (optionally after spaces / a
// list dash) and NAMES THE LEVEL of the change (operator decision 2026-10-19: every change, fix
// or feature, says which level of the base model it was built on — symptom, reader, writer,
// design — in words the operator reads, not as a code). Built-in words are English; the
// operator's language is instance data `.claude/rules/class-gate.json` {"level_patterns": [...]}.
const GEAR = /^[ \t>*-]*⚙(.*)$/gm;
const LEVEL_WORDS = ['symptom', 'reader', 'writer', 'producer', 'design', 'base model'];
function levelRx(root) {
  let extra = [];
  try {
    extra = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'class-gate.json'), 'utf8')).level_patterns || [];
  } catch (e) { /* no instance data: built-ins only */ }
  const src = LEVEL_WORDS.map((w) => `\\b${w}\\b`).concat(extra.map(String)).join('|');
  return new RegExp(src, 'i');
}
let LEVEL = levelRx(process.env.CLAUDE_PROJECT_DIR || process.cwd());
function answers(text) {
  for (const m of String(text || '').matchAll(GEAR)) if (LEVEL.test(m[1])) return true;
  return false;
}

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const TAIL_BYTES = 4 * 1024 * 1024; // a turn fits in this by orders of magnitude

function readTail(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift(); // drop the cut-off first line
    return lines;
  } finally {
    fs.closeSync(fd);
  }
}

/**
 * One pass over the transcript yields both:
 *   files — files edited in the running turn (since the last real operator message)
 *   quiet — whether the gate is cooling down (fewer than COOLDOWN_TURNS operator
 *           turns since its own last block, read from its replayed feedback).
 */
function analyze(transcriptPath) {
  const lines = readTail(transcriptPath);
  const events = [];
  const questionAnswered = questionAnswers();   // the operator's question-tool answer ends the window too
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (questionAnswered(d)) { events.push({ boundary: true }); continue; }
    if (msg.role === 'user' && typeof msg.content === 'string') {
      // Own feedback does not end the turn window, but marks the last block.
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      if (!isNotification(msg.content) && !isAgentOrigin(d)) events.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && answers(b.text)) events.push({ answer: true });
        if (b.type === 'tool_use' && EDIT_TOOLS.has(b.name)) {
          const p = b.input && b.input.file_path;
          if (p) events.push({ file: p });
        }
      }
    }
  }
  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const files = [];
  let answered = false;   // a ⚙ line after the turn's last edit (an edit after it reopens the question)
  for (let i = last; i < events.length; i++) {
    if (events[i].answer) answered = true;
    if (events[i].file) answered = false;
    if (events[i].file && !files.includes(events[i].file)) files.push(events[i].file);
  }

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  return { files, answered, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);

  // Prevent infinite loop — one block per turn is the whole point.
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  if (input.cwd) LEVEL = levelRx(process.env.CLAUDE_PROJECT_DIR || input.cwd);
  let touched = [];
  try {
    const seen = analyze(input.transcript_path);
    if (seen.quiet) return allow(); // cooldown
    // answered in advance: in the transcript, or in the final message the harness hands over
    if (seen.answered || answers(input.last_assistant_message)) return allow();
    touched = seen.files;
  } catch (e) {
    return allow(); // transcript unreadable — never block for that
  }

  // Docs pass. JSON is docs too — except rule and gate data, which is behaviour
  // (`.claude/rules/*.json`, a tool's `mechanism-rules.json`) and the harness wiring
  // (`.claude/settings.json`, `settings.local.json`, `.mcp.json`): a permission rule
  // dropped there changed what the brain asks before — and the gate stayed silent, so
  // nobody asked whether the core template had the same hole (measured 2026-10-21).
  const docExt = /\.(md|markdown|mdx|txt|rst|json)$/i;
  const ruleData = /(^|[\\/])\.claude[\\/]rules[\\/][^\\/]+\.json$|(^|[\\/])mechanism-rules\.json$|(^|[\\/])\.claude[\\/]settings(\.local)?\.json$|(^|[\\/])\.mcp\.json$/i;
  // Throwaway places: scratchpad and system temp. An analysis aid that does not
  // survive the turn is not work on the system — otherwise the gate fires on its
  // own tooling. BUT a file inside a git checkout there (a worktree carries a `.git`
  // FILE, a clone a `.git` folder) is work: since 2026-10-13 every core PR is built
  // in a worktree under the scratchpad, and the gate was blind to all of it
  // (measured 2026-10-19 on the macOS instance).
  const tmp = /^(\/private)?\/(tmp|var\/folders)\/|[\\/]Temp[\\/]/;
  const inCheckout = (f) => {
    try {
      for (let d = path.dirname(path.resolve(f)); ; d = path.dirname(d)) {
        if (fs.existsSync(path.join(d, '.git'))) return true;
        if (path.dirname(d) === d) return false;
      }
    } catch (e) { return false; }
  };
  const scratch = { test: (f) => tmp.test(f) && !inCheckout(f) };
  const isDoc = (f) => docExt.test(f) && !ruleData.test(f);
  // Separators are normalized before the prefix strip: on Windows the transcript
  // carries backslash paths, so `cwd + '/'` never matched and the gate showed
  // absolute paths (cosmetic — measured 2026-08-19 on the Windows instance).
  const norm = (s) => String(s).replace(/\\/g, '/');
  const cwd = norm(input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd())
    .replace(/\/+$/, '');
  const substantive = touched
    .filter((f) => !isDoc(f) && !scratch.test(f))
    .map((f) => (norm(f).startsWith(cwd + '/') ? norm(f).slice(cwd.length + 1) : f));
  if (substantive.length === 0) return allow();

  const shown = substantive.slice(0, 6).join(', ') +
                (substantive.length > 6 ? ` (+${substantive.length - 6})` : '');

  // Two lines, both written for the OPERATOR's scrollback (findings 2026-08-19,
  // twice in one day: first a ~20-line block buried the reply, then the terse
  // version read as word salad — compressed meta-instructions plus a jargon
  // answer). Terse is not the goal, readable is. The agent's mechanics live in
  // rules/thinking-protocol.md → Class Discipline and need no repetition here;
  // the demanded ⚙ line is addressed to the human, so it must be plain language.
  console.log(JSON.stringify(declare({
    decision: 'block',
    reason:
      `CLASS-GATE — routine success check, not an error. Touched this turn: ${shown}\n` +
      'Answer with ONE ⚙ line in plain operator language: on which level did you build it ' +
      '(symptom, reader, writer or design) and why not the next higher one, is the bigger goal ' +
      'still served, does the same defect exist elsewhere (searched), and does the core (its ' +
      'template, a rule, a helper) or the owning suite carry the same thing — core PR, instance-only ' +
      'with the reason, or already there? Nothing transferable: ' +
      '"⚙ writer level, no class elsewhere, core has it" — the level is always named.',
  }, input)));
  process.exit(0);
});

process.stdin.resume();
