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
 *
 * Build threshold (operator decision 2026-08-06): search always · 1 site = done ·
 * 2 = fix both, no mechanism · >=3 or repeat after a fix = build a mechanism.
 * "Outside the order: list, don't fix" guards scope, NOT finishing — what is in
 * reach and belongs to the same matter gets done, not tabled.
 */
const fs = require('fs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

// The harness replays a blocked turn's feedback as an operator message. It must not
// end the turn window — after the first block the window would be empty otherwise.
const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /CLASS-GATE|KLASSEN-GATE/; // legacy marker kept: old echoes still count

// After a block the gate stays quiet for this many real operator turns. 3 instead of
// "every time": often enough that a fix chain cannot slip through, rare enough that
// it never becomes wallpaper.
const COOLDOWN_TURNS = 3;

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
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      // Own feedback does not end the turn window, but marks the last block.
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      events.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
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
  for (let i = last; i < events.length; i++) {
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
  return { files, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

setTimeout(() => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  // Prevent infinite loop — one block per turn is the whole point.
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let touched = [];
  try {
    const seen = analyze(input.transcript_path);
    if (seen.quiet) return allow(); // cooldown
    touched = seen.files;
  } catch (e) {
    return allow(); // transcript unreadable — never block for that
  }

  const docExt = /\.(md|markdown|mdx|txt|rst|json)$/i;
  // Throwaway places: scratchpad and system temp. An analysis aid that does not
  // survive the turn is not work on the system — otherwise the gate fires on its
  // own tooling.
  const scratch = /^(\/private)?\/(tmp|var\/folders)\/|[\\/]Temp[\\/]/;
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const substantive = touched
    .filter((f) => !docExt.test(f) && !scratch.test(f))
    .map((f) => (f.startsWith(cwd + '/') ? f.slice(cwd.length + 1) : f));
  if (substantive.length === 0) return allow();

  const shown = substantive.slice(0, 6).join(', ') +
                (substantive.length > 6 ? ` (+${substantive.length - 6})` : '');

  // Terse on purpose (operator finding 2026-08-19: a ~20-line block plus a long
  // reflective answer buried the actual reply in the terminal). The block SHOWS,
  // the rule EXPLAINS — the full mechanics live in rules/thinking-protocol.md,
  // section "Class Discipline". The demanded answer is ONE compact line for the
  // operator's scrollback, not an essay for the agent's own reflection.
  console.log(JSON.stringify({
    decision: 'block',
    reason:
      `CLASS-GATE (success trigger) — touched this turn: ${shown}\n` +
      'Reply with ONE compact line prefixed "⚙" (do NOT repeat your answer, no ' +
      'essay): larger goal & object level ok? · invariant behind the work + site ' +
      'count (searched, not recalled) · register state (>=3 sites or repeat => ' +
      'mechanism). Pure refactor/new build without defect: reply exactly "⚙ no ' +
      'class". Mechanics: rules/thinking-protocol.md → Class Discipline.',
  }));
  process.exit(0);
}, 400);

process.stdin.resume();
