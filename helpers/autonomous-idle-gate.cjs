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
  let text = ''; let wake = false; let cmds = []; let prev = null; let lastUserIsNotification = false;
  // Every command of the session in order, with its time: an earlier measurement can still stand (see judge).
  const all = [];
  // Background waiters still running at the turn's end (armed, no end reported yet).
  const armed = new Set(); const ended = new Set();
  for (const line of lines) {
    const m = line.match(/<tool-use-id>(toolu_[A-Za-z0-9]+)<\/tool-use-id>[\s\S]{0,800}?<status>(completed|failed|killed|cancelled|stopped|expired|timeout)/);
    if (m) ended.add(m[1]);
  }
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
      // A notification that lands AFTER the turn's closing text (a watcher's event between the reply and the Stop
      // check, measured 2026-10-31 on the macOS instance: four loops in one evening, each reset the BLOCKED line
      // and the measurement away) starts a turn with nothing in it yet - the turn being judged is the one before.
      if (t !== null && !HOOK_ECHO.test(t)) {
        lastUserIsNotification = /<task-notification>|<cross-session-message\b/.test(t);
        if (text) prev = { text, wake, cmds };
        text = ''; wake = false; cmds = [];
      }
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b && b.type === 'text' && b.text) text = b.text;
        if (b && b.type === 'tool_use' && b.name === 'ScheduleWakeup') wake = true;
        if (b && b.type === 'tool_use' && (b.name === 'Monitor'
          || ((b.name === 'Bash' || b.name === 'Agent') && b.input && b.input.run_in_background === true))) armed.add(b.id);
        if (b && b.type === 'tool_use' && b.input && typeof b.input.command === 'string') cmds.push(b.input.command);
        if (b && b.type === 'tool_use') all.push({ name: b.name, cmd: (b.input && typeof b.input.command === 'string') ? b.input.command : '', ts: Date.parse(d.timestamp || '') || 0 });
      }
    }
  }
  const waiting = [...armed].some((id) => !ended.has(id));
  if (!text && prev && lastUserIsNotification) return { ...prev, waiting, all };
  return { text, wake, cmds, waiting, all };
}

/** A measurement from an EARLIER turn still stands when nothing was done since and it is fresh.
 *  Measured 2026-10-31 on the macOS instance over 80 sessions: 31 of 86 idle blocks were answered by re-running the
 *  same measurement and re-sending the same text - each watcher notification starts a turn, and the turn before had
 *  measured already. "Nothing done" = no tool call that changes state (an edit, a commit, a push, a merge, a post) after
 *  the measurement; "fresh" = at most STANDING_MIN minutes old. */
const STANDING_MIN = 30;
const CHANGES = /\bgit\b[^\n|;&]*\b(commit|push|merge|rebase|tag)\b|\bgh\s+(pr|issue)\s+(create|merge|comment|edit|close)\b|shared-memory-post|\bgh\s+api\s+-X/;
const CHANGE_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit', 'MultiEdit']);
function standingMeasurement(all, measurers, now) {
  if (!Array.isArray(all)) return false;
  let at = -1;
  all.forEach((c, i) => { if (c.cmd && measurers.some((r) => r.test(c.cmd))) at = i; });
  if (at < 0) return false;
  const ts = all[at].ts;
  if (!ts || (now || Date.now()) - ts > STANDING_MIN * 60000) return false;
  return !all.slice(at + 1).some((c) => CHANGE_TOOLS.has(c.name) || (c.cmd && CHANGES.test(c.cmd)));
}

/** The commands that measure the brain's own open items: the core's, plus the instance's (data). */
function measurers(root) {
  // Nothing may follow the view: measured on an instance, the list piped into a filter kept the counts and
  // dropped every item (and its open exit).
  const out = [/open-items\.py\b[^\n|;&]*$/];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    for (const s of (d && d.own_items_commands) || []) { try { out.push(new RegExp(s)); } catch (e) { /* skip */ } }
  } catch (e) { /* no data: the core's command only */ }
  return out;
}

/** Words that let a beta-tag / pin / Windows BLOCKED line stand: the operator's order, or the work already merged.
 *  English built in; other languages as data (`blocked_exempt_patterns`). */
function exemptWords(root) {
  const list = ['\\boperator\\b', '\\border\\b', '\\bmerged\\b', '\\bis built\\b', '\\balready built\\b'];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    for (const x of (d && d.blocked_exempt_patterns) || []) { try { new RegExp(x); list.push(x); } catch (e) { /* skip */ } }
  } catch (e) { /* no data: English only */ }
  return new RegExp(list.join('|'), 'i');
}

function judge(input, now) {
  // The retry after a block is judged too (measured on an instance, 2026-10-29): the second attempt ended on a
  // BLOCKED line over a sliced list and passed unread, because stop_hook_active skipped the whole judgement.
  // The demand is cheap to meet (one reading command), so no loop. Pair it with `onReissue: run` in the
  // brain's stop-checks.json row: without it the dispatcher never calls this gate after ANOTHER gate's block
  // (2026-10-30: a 15-min wakeup after two other blocks passed with 67 own items open).
  if (!input.transcript_path) return null;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  if (!autonomousMode(input.transcript_path, root)) return null;
  const t = turnOf(input.transcript_path);
  if (!t || !t.text) return null;
  // A wakeup alone is no continuation (measured on an instance, 2026-10-29, the operator asking why it stopped
  // again): a 15-min wakeup while own work was doable now was the same idle stop under another name — and a
  // waiter was running too, so "wakeup + waiter" would have let it pass as well. Only the end lines below end
  // a turn: BLOCKED (every item left waits on something named) or POOL EMPTY — both measured against the list.
  void t.wake; void t.waiting;
  if (END_LINE.test(t.text)) {
    const m = measurers(root);
    if (t.cmds.some((c) => m.some((r) => r.test(c))) || standingMeasurement(t.all, m, now)) {
      const exempt = exemptWords(root);
      // A BLOCKED line whose reason is a pin / beta tag / Windows check blocks the MERGE or the release, never the
      // building (third case on an instance, 2026-10-30: follow-up PRs held "until the next beta tag" while they
      // could be built stacked). Another party's merge may block (a peer's work comes first) and stays free.
      // It passes when it cites the operator's order for that sequence, or when the work is already merged;
      // other languages' words for both come from autonomous-patterns.json `blocked_exempt_patterns`.
      const mergeOnly = t.text.split('\n').filter((l) => /^[ \t>*_-]*BLOCKED:/.test(l)
        && /(beta-tag|beta tag|\bpin\b|windows)/i.test(l)
        && !exempt.test(l));
      if (!mergeOnly.length) return null;
      return 'AUTONOMOUS-IDLE: a BLOCKED line waits on a merge, pin, beta tag or Windows check — that blocks the merge, '
        + `not the building: "${mergeOnly[0].trim().slice(0, 140)}". Build it now (stacked on the open PR if needed), `
        + 'or name the operator\'s order that sets this sequence. Missing: build or the order behind the wait';
      // Its own last words (2026-10-31): with "Missing: continuation" the dispatcher's LEERLAUF row turned this
      // specific reason into the generic idle sentence, and the real cause (a Windows word in the BLOCKED line)
      // stayed hidden through four retries.
    }
    return 'AUTONOMOUS-IDLE: this turn ends on a BLOCKED / POOL EMPTY line, but the list behind it was not measured ' +
      'in this turn — the line is a recollection, not a reading. Run the brain\'s own-items measurement now ' +
      '(core/scripts/open-items.py, or the instance command in .claude/rules/autonomous-patterns.json ' +
      '`own_items_commands`), do what it lists as yours, and end only when every item left is named as blocked. ' +
      'Missing: own-items measurement';
  }
  return 'AUTONOMOUS-IDLE: the run is autonomous and this turn ends without its continuation. ' +
    'Do the next item now (tool calls in this turn), or end the turn in one of the run\'s end forms: ' +
    'a line `BLOCKED: <item> — <what restores it, who>` or a line ' +
    '`POOL EMPTY: <how measured>`, both after measuring the list in this turn. A wakeup alone is no continuation, and a running watcher (CI, a peer) continues only its own event, not your items. ' +
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
