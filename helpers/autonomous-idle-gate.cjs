#!/usr/bin/env node
/**
 * Stop hook: while the operator's autonomous order runs, a turn ends only in one of the run's own
 * end forms — never idle.
 *
 * WHY (measured 2026-10-28 on the macOS instance): after the order "if anything is left, then
 * autonomously", the session ended 53 turns; 14 of them were followed by more than five idle minutes,
 * 264 minutes in all, the longest 47. Each turn closed on a status report while own items stayed open;
 * only a CI watcher, a peer message or the operator woke it again. The operator: "open with you, but
 * you are not working on it — why exactly?" and "several times, right? you paused long". Skill
 * autonomous-run already says it (list run: a forced turn end arms ScheduleWakeup; the work ends only
 * when the list is empty or BLOCKED) — but nothing carried that rule when the skill was not loaded, and
 * the instance's own-open gate judged WORDING (its phrases missed "still with me, not started") and let
 * any running waiter count as continuation, although a CI watch continues nothing but its PR.
 *
 * So this gate judges STATE, not wording. In autonomous mode (autonomous-mode.cjs) the turn may end only:
 *   - with a ScheduleWakeup called in this turn (the run continues itself), or
 *   - with a line `BLOCKED: <item> — <what restores it, who>` (every item left is blocked), or
 *   - with a line `POOL EMPTY: <how it was measured>` (nothing left to do).
 * The tokens are fixed and language-neutral; the text around them is the instance's language.
 * A running waiter does not count: it wakes the session for its own event only.
 * A BLOCKED or POOL EMPTY line is a claim about the list, so the same turn must have MEASURED the list:
 * a call of `core/scripts/open-items.py`, or of an instance command named as data
 * (`own_items_commands`, regexes, in .claude/rules/autonomous-patterns.json). Measured 2026-10-28 on the
 * macOS instance: a turn ended on "BLOCKED: waiting on the CI watchers, the peer, the operator" while the
 * session start listed 16 own items; the line was the AI's recollection that "its strand was empty",
 * never read against the list — the operator: "so everything is done on your side? or why did you stop?"
 * Outside the mode, and on a re-issue (stop_hook_active), it is silent. Fails open on unreadable input.
 * Fixture: scripts/test-autonomous-idle-gate.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { autonomousMode } = require('./autonomous-mode.cjs');
const { isTranscriptRecord } = require('./turn-kind.cjs');

const END_LINE = /^[ \t>*_-]*(BLOCKED|POOL EMPTY):\s*\S/m;
const HOOK_ECHO = /^Stop hook feedback:/;

/** The running turn: its final assistant text and whether it called ScheduleWakeup. */
function turnOf(tp) {
  let lines;
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return null; }
  let text = ''; let wake = false; let cmds = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      const c = msg.content;
      const t = typeof c === 'string' ? c
        : Array.isArray(c) && !c.some((b) => b && b.type === 'tool_result') ? c.map((b) => (b && b.text) || '').join('\n') : null;
      // Every new user record that is no tool result starts a turn — an operator prompt, a
      // notification or a peer message alike: each of them is a turn that can end idle.
      if (t !== null && !HOOK_ECHO.test(t)) { text = ''; wake = false; cmds = []; }
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b && b.type === 'text' && b.text) text = b.text;
        if (b && b.type === 'tool_use' && b.name === 'ScheduleWakeup') wake = true;
        if (b && b.type === 'tool_use' && b.input && typeof b.input.command === 'string') cmds.push(b.input.command);
      }
    }
  }
  return { text, wake, cmds };
}

/** The commands that measure the brain's own open items: the core's, plus the instance's (data). */
function measurers(root) {
  const out = [/open-items\.py\b/];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    for (const s of (d && d.own_items_commands) || []) { try { out.push(new RegExp(s)); } catch (e) { /* skip */ } }
  } catch (e) { /* no data: the core's command only */ }
  return out;
}

function judge(input) {
  if (input.stop_hook_active || !input.transcript_path) return null;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  if (!autonomousMode(input.transcript_path, root)) return null;
  const t = turnOf(input.transcript_path);
  if (!t || !t.text) return null;
  if (t.wake) return null;
  if (END_LINE.test(t.text)) {
    const m = measurers(root);
    if (t.cmds.some((c) => m.some((r) => r.test(c)))) return null;
    return 'AUTONOMOUS-IDLE: this turn ends on a BLOCKED / POOL EMPTY line, but the list behind it was not measured ' +
      'in this turn — the line is a recollection, not a reading. Run the brain\'s own-items measurement now ' +
      '(core/scripts/open-items.py, or the instance command in .claude/rules/autonomous-patterns.json ' +
      '`own_items_commands`), do what it lists as yours, and end only when every item left is named as blocked. ' +
      'Missing: own-items measurement';
  }
  return 'AUTONOMOUS-IDLE: the run is autonomous and this turn ends without its continuation. ' +
    'Do the next item now (tool calls in this turn), or end the turn in one of the run\'s end forms: ' +
    'ScheduleWakeup (the run continues itself), a line `BLOCKED: <item> — <what restores it, who>`, or a line ' +
    '`POOL EMPTY: <how measured>`. A running watcher (CI, a peer) continues only its own event, not your items. ' +
    'Missing: continuation';
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let reason = null;
    try { reason = judge(JSON.parse(raw)); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify({ decision: 'block', reason }));
    process.exit(0);
  });
}

module.exports = { judge };
