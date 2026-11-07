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
 *   - with a line `BLOCKED: <item> — <what restores it, who>` (every item left is blocked), or
 *   - with a line `POOL EMPTY: <how it was measured>` (nothing left to do).
 * The tokens are fixed and language-neutral; the text around them is the instance's language.
 * Neither a ScheduleWakeup nor a running waiter counts (since 2026-10-29, see judge()): a wakeup while own
 * work is doable now is the same idle stop under another name, and a waiter wakes the session for its own
 * event only. The skill still sets the wakeup before every turn end - it keeps the run alive, it does not
 * end the turn. (This list named the wakeup as a third end form until 2026-11-02; measured that day on the
 * Windows instance: a turn ended on a wakeup alone, trusting this header, and was blocked.)
 * A BLOCKED or POOL EMPTY line is a claim about the list, so the same turn must have MEASURED the list:
 * a call of `core/scripts/open-items.py`, or of an instance command named as data
 * (`own_items_commands`, regexes, in .claude/rules/autonomous-patterns.json). Measured 2026-10-28 on the
 * macOS instance: a turn ended on "BLOCKED: waiting on the CI watchers, the peer, the operator" while the
 * session start listed 16 own items; the line was the AI's recollection that "its strand was empty",
 * never read against the list — the operator: "so everything is done on your side? or why did you stop?"
 * Fails open on unreadable input.
 *
 * INTERACTIVE, for released work (operator decision 2026-11-02 on the macOS instance, question tool): the same
 * state check holds outside the autonomous mode, but only for own work the operator RELEASED in this session.
 * Measured the same day: an interactive turn closed on "Next: package A …" while the operator had released that
 * plan in the session; the word-pattern gates missed the sentence, and the operator is against more word lists.
 * Released = an OPEN entry of a registered ledger (.claude/rules/ledgers.json) whose last exit is `ai-does-it`
 * and which carries `released: "<the operator's words>"` — and those words stand in one of the operator's own
 * messages of THIS transcript (a prompt, a message typed mid-turn, a question-tool answer). A quote the agent
 * invents releases nothing. With such an entry open, the turn may end only:
 *   - with an AskUserQuestion call in this turn, or a line `HAND STEP: <what the operator does>`, or
 *   - when every released entry is named by its id in a `BLOCKED: <id> — <what restores it>` line, after
 *     measuring the list (as above). A running waiter is no end, even with its condition named (operator,
 *     2026-11-02: while a waiter waits 15 minutes there is always something to work on): it explains why ONE
 *     item waits, and that item then stands in its own BLOCKED line.
 * It holds once per turn: the re-issue after its block (stop_hook_active) passes. Autonomous behaviour unchanged.
 * Fixture: scripts/test-autonomous-idle-gate.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { autonomousMode, answers, promptText, HOOK_ECHO: PROMPT_ECHO } = require('./autonomous-mode.cjs');
const { isTranscriptRecord, isNotification, isSkillExpansion, isAgentOrigin, queuedHumanPrompt, operatorWords, FRAMES, LOCAL } = require('./turn-kind.cjs');
const { closeOpenEnds } = require('./close-stamp.cjs');
const { newestExitKind } = require('./ledger-exit.cjs');

// LIST EMPTY (2026-11-02, coherence register P0-1): a list run ends when the ORDERED list is done -
// Order Fidelity #3, an empty list is a success, not a reason to take the rest of the ledger as the pool.
const END_LINE = /^[ \t>*_-]*(BLOCKED|POOL EMPTY|LIST EMPTY):\s*\S/m;
const HOOK_ECHO = /^Stop hook feedback:/;

/** The running turn: its final assistant text and whether it called ScheduleWakeup. */
function turnOf(tp) {
  let lines;
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return null; }
  let text = ''; let wake = false; let asked = false; let ans = ''; let cmds = []; let prev = null; let lastUserIsNotification = false; let since = '';
  let opener = '';   // the user record that opened the turn (see ownEventsOnly)
  const askIds = new Set();
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
        if (text) prev = { text, wake, asked, answers: ans, cmds, since, opener };
        text = ''; wake = false; asked = false; ans = ''; cmds = []; since = d.timestamp || ''; opener = t;
      } else if (t === null) {
        for (const [, a] of answers(msg, askIds)) ans += '\n' + squash(a); // the operator's answers in this turn
      }
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b && b.type === 'text' && b.text) text = b.text;
        if (b && b.type === 'tool_use' && b.name === 'ScheduleWakeup') wake = true;
        if (b && b.type === 'tool_use' && b.name === 'AskUserQuestion') { asked = true; askIds.add(b.id); }
        if (b && b.type === 'tool_use' && (b.name === 'Monitor'
          || ((b.name === 'Bash' || b.name === 'Agent') && b.input && b.input.run_in_background === true))) armed.add(b.id);
        if (b && b.type === 'tool_use' && b.input && typeof b.input.command === 'string') cmds.push(b.input.command);
        if (b && b.type === 'tool_use') all.push({ name: b.name, cmd: (b.input && typeof b.input.command === 'string') ? b.input.command : '', ts: Date.parse(d.timestamp || '') || 0 });
      }
    }
  }
  const waiting = [...armed].some((id) => !ended.has(id));
  if (!text && prev && lastUserIsNotification) return { ...prev, waiting, all };
  return { text, wake, asked, answers: ans, cmds, since, waiting, all, opener };
}

/** A watcher event that reports only this instance's own doing, or the watcher's own state - nothing to act on.
 *  Operator decision 2026-11-05 (question tool, "Beides"), after measuring this gate's holds by the kind of turn
 *  (one brain, 150 transcripts since 2026-10-27): notification turns were held 277 times, 160 of them as idle, while
 *  the long hold chains came after the operator's own prompts. A turn opened by such an event acknowledges and ends;
 *  every other event (a peer's PR, a red CI, a comment without this instance's key) still needs its continuation.
 *  Own = a line naming a branch made on this machine, a comment carrying this instance's key, or the watcher's own
 *  state lines (armed, already armed, skipped, expired). Every <event> line must be one of these. */
const OWN_STATE = /^(NOTE: collaboration watch armed|already armed\b|WATCHER-SKIPPED:|SESSIONS:|\[Monitor expired after\b)/;
function ownEventsOnly(opener, key) {
  const m = String(opener || '').match(/<event>([\s\S]*?)<\/event>/);
  if (!/<task-notification>/.test(opener || '') || !m) return false;
  const lines = m[1].split('\n').map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return false;
  const keyRx = key ? new RegExp(`instance-key:\\s*${key}\\b`) : null;
  return lines.every((l) => OWN_STATE.test(l)
    || /branch is LOCAL in this machine's clone/.test(l)
    || (keyRx && /^COMMENT\b/.test(l) && keyRx.test(l)));
}

/** Everything the operator wrote in this transcript, squashed: prompts, messages typed mid-turn and question-tool
 *  answers — never a notification, a hook echo, a loaded skill, a peer's or the harness's text, frames or pasted
 *  blocks. The same filters as autonomous-mode.cjs promptModes. */
const squash = (s) => String(s || '').toLowerCase().replace(/[\s ]+/g, ' ').trim();
function operatorSaid(tp) {
  let lines;
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return ''; }
  const out = []; const askIds = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const queued = queuedHumanPrompt(d);
    if (queued) { out.push(operatorWords(queued.replace(FRAMES, ' ').replace(LOCAL, ' '))); continue; }
    if (!isTranscriptRecord(d) || isSkillExpansion(d) || isAgentOrigin(d) || !d.message) continue;
    const msg = d.message;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) if (b && b.type === 'tool_use' && b.name === 'AskUserQuestion') askIds.add(b.id);
      continue;
    }
    if (msg.role !== 'user') continue;
    for (const [, a] of answers(msg, askIds)) out.push(a);
    const t = promptText(msg);
    if (!t || PROMPT_ECHO.test(t) || isNotification(t)) continue;
    out.push(operatorWords(t.replace(FRAMES, ' ').replace(LOCAL, ' ')));
  }
  return squash(out.join('\n'));
}

/** Open entries of the registered ledgers that the operator released in this session (see the header):
 *  last exit `ai-does-it`, a `released: "<words>"` clause, the words found in what the operator said.
 *  Returns their ids; [] on any unreadable part (fail open). The entry shape is the one open-items.py and
 *  decision-presentation-gate.cjs read: a `- [ ]` line and its indented lines. */
const RELEASED = /\breleased:\s*["„“”]([^"„“”\n]{4,})["“”]/gu;
function releasedOpen(root, tp) {
  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'ledgers.json'), 'utf8')); } catch (e) { return []; }
  const out = []; let said = null;
  for (const rel of (cfg && cfg.ledgers) || []) {
    let text;
    try { text = fs.readFileSync(path.join(root, rel), 'utf8'); } catch (e) { continue; }
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const m = /^- \[ \] (.*)$/.exec(lines[i]);
      if (!m) continue;
      const block = [lines[i]];
      for (let j = i + 1; j < lines.length && lines[j].startsWith(' '); j++) block.push(lines[j]);
      const body = block.join('\n');
      if (!body.includes('released:')) continue;
      const exit = newestExitKind(body);
      if (exit && exit !== 'ai-does-it') continue;
      const quotes = [...body.matchAll(RELEASED)].map((q) => squash(q[1]));
      if (!quotes.length) continue;
      if (said === null) said = operatorSaid(tp);
      const found = quotes.filter((q) => said.includes(q));
      if (!found.length) continue;
      const id = /\bid:\s*`?([\w.:/-]+)/.exec(body);
      out.push({ id: id ? id[1].replace(/[.:]+$/, '') : m[1].replace(/[*`]/g, '').slice(0, 60), quotes: found });
    }
  }
  return out;
}

const HAND_STEP_LINE = /^[ \t>*_-]*HAND STEP:\s*\S/m;

/** The interactive variant: one block per turn while released work is open and the turn has no allowed end. */
function judgeInteractive(input, root, now) {
  if (input.stop_hook_active) return null; // holds once: the re-issue after its own block passes
  const rel = releasedOpen(root, input.transcript_path);
  if (!rel.length) return null;
  const ids = rel.map((r) => r.id);
  const t = turnOf(input.transcript_path);
  if (!t || !t.text) return null;
  // A question asked in this turn ends it — unless its own answer released the work: then the turn goes on with it.
  const releasedNow = rel.some((r) => r.quotes.some((q) => t.answers.includes(q)));
  if ((t.asked && !releasedNow) || HAND_STEP_LINE.test(t.text)) return null;
  if (closeOpenEnds(root, { sessionId: input.session_id, since: t.since, calls: t.cmds.map((cmd) => ({ cmd })) }) !== null) return null;
  const m = measurers(root);
  const measured = t.cmds.some((c) => m.some((r) => r.test(c))) || standingMeasurement(t.all, m, now);
  const blockedLines = t.text.split('\n').filter((l) => /^[ \t>*_-]*BLOCKED:\s*\S/.test(l));
  const unnamed = ids.filter((id) => !blockedLines.some((l) => l.includes(id)));
  if (measured && !unnamed.length) return null;
  const list = (unnamed.length ? unnamed : ids).slice(0, 5).join(', ');
  return `IDLE (interactive, released work): the operator released ${list} in this session and this turn ends without `
    + 'working on it. Do the next step now (tool calls in this turn), or end in one of the allowed forms: a question '
    + 'through the question tool, a line `HAND STEP: <what the operator does>`, or every released entry named in a '
    + 'line `BLOCKED: <id> — <what restores it, who>` after measuring the list in this turn '
    + '(core/scripts/open-items.py or the instance command). A running waiter is no end, even with its condition: '
    + 'it explains why one item waits — name that one as BLOCKED and work on the others. This check holds once per turn. '
    + `Missing: ${!measured && !unnamed.length ? 'own-items measurement' : 'continuation on released work'}`;
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

// The loop watchdog follows the mode, not the agent's memory (coherence register 2026-11-02 P1-12: "watchdog arming
// in prose only"; measured 2026-11-03 on the macOS instance: a list run ordered autonomous worked for over an hour with
// no watchdog armed). Every turn end of an autonomous run is a life sign: armed when nothing is armed, a beat otherwise.
// Back in interactive mode a watchdog this gate armed itself (name `auto-…`) is disarmed; one the agent armed by hand
// (a time-boxed run with its deadline) is left alone. No turn is held for it. LOOP_WATCHDOG_AUTO=0 switches it off.
const AUTO_PREFIX = 'auto-';
function keepWatchdog(root, autonomous) {
  if (process.env.LOOP_WATCHDOG_AUTO === '0') return;
  const script = require('path').join(__dirname, '..', 'scripts', 'loop-watchdog.sh');
  const state = require('path').join(root, '.claude-state', 'loop-watchdog.state');
  if (!fs.existsSync(script)) return;
  let name = '';
  try { name = fs.readFileSync(state, 'utf8').split('\n')[0].trim(); } catch (_) {}
  const run = (...args) => require('child_process').spawnSync('bash', [script, ...args],
    { env: { ...process.env, CLAUDE_PROJECT_DIR: root }, stdio: 'ignore', timeout: 5000 });
  try {
    if (autonomous && !name) run('arm', AUTO_PREFIX + 'autonomous-run', process.env.LOOP_WATCHDOG_AUTO_MINUTES || '45');
    else if (autonomous) run('beat');
    else if (name.startsWith(AUTO_PREFIX)) run('disarm');
  } catch (_) { /* fail open: the watchdog never holds a turn */ }
}

function judge(input, now) {
  // The retry after a block is judged too (measured on an instance, 2026-10-29): the second attempt ended on a
  // BLOCKED line over a sliced list and passed unread, because stop_hook_active skipped the whole judgement.
  // The demand is cheap to meet (one reading command), so no loop. Pair it with `onReissue: run` in the
  // brain's stop-checks.json row: without it the dispatcher never calls this gate after ANOTHER gate's block
  // (2026-10-30: a 15-min wakeup after two other blocks passed with 67 own items open).
  if (!input.transcript_path) return null;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const autonomous = autonomousMode(input.transcript_path, root);
  keepWatchdog(root, autonomous);
  if (!autonomous) return judgeInteractive(input, root, now);
  const t = turnOf(input.transcript_path);
  if (!t || !t.text) return null;
  // The session close ends the run (measured 2026-10-31 and again 2026-11-01 on the macOS instance: after a
  // successful `session-close`, this gate blocked the closing report with "Missing: continuation" - a closed
  // session continues nothing, and its open ends stand in the session log). The same checkable carrier the
  // watch and question gates accept: a close stamp written in THIS turn by `session-closing.sh --pre-commit`.
  if (closeOpenEnds(root, { sessionId: input.session_id, since: t.since, calls: t.cmds.map((cmd) => ({ cmd })) }) !== null) return null;
  {
    const { keyFor, selfId } = require('./instance-key-gate.cjs');
    if (ownEventsOnly(t.opener, keyFor(selfId(root)))) return null;
  }
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
      // The operator's order is also named when the line QUOTES it and the quote stands in what the operator said
      // in this transcript (2026-11-06, operator: "the core should deliver this end to end, without extra tinkering"):
      // a line in the operator's language that cited the order by the operator's exact words was held twice, because
      // the instance's name pattern missed a genitive. A checked quote needs no word list, no name and no language.
      let said = null;
      const quotesOperator = (l) => {
        for (const m of l.matchAll(/["„“”«»]([^"„“”«»\n]{12,})["“”«»]/gu)) {
          if (said === null) said = operatorSaid(input.transcript_path);
          if (said.includes(squash(m[1]))) return true;
        }
        return false;
      };
      const mergeOnly = t.text.split('\n').filter((l) => /^[ \t>*_-]*BLOCKED:/.test(l)
        && /(beta-tag|beta tag|\bpin\b|windows)/i.test(l)
        && !exempt.test(l) && !quotesOperator(l));
      if (!mergeOnly.length) return null;
      return 'AUTONOMOUS-IDLE: a BLOCKED line waits on a merge, pin, beta tag or Windows check — that blocks the merge, '
        + `not the building: "${mergeOnly[0].trim().slice(0, 140)}". Build it now (stacked on the open PR if needed), `
        + 'or name the operator\'s order that sets this sequence. Missing: build or the order behind the wait';
      // Its own last words (2026-10-31): with "Missing: continuation" the dispatcher's LEERLAUF row turned this
      // specific reason into the generic idle sentence, and the real cause (a Windows word in the BLOCKED line)
      // stayed hidden through four retries.
    }
    return 'AUTONOMOUS-IDLE: this turn ends on a BLOCKED / POOL EMPTY / LIST EMPTY line, but the list behind it was not measured ' +
      'in this turn — the line is a recollection, not a reading. Run the brain\'s own-items measurement now ' +
      '(core/scripts/open-items.py, or the instance command in .claude/rules/autonomous-patterns.json ' +
      '`own_items_commands`), do what it lists as yours, and end only when every item left is named as blocked. ' +
      'Missing: own-items measurement';
  }
  return 'AUTONOMOUS-IDLE: the run is autonomous and this turn ends without its continuation. ' +
    'Do the next item now (tool calls in this turn), or end the turn in one of the run\'s end forms: ' +
    'a line `BLOCKED: <item> — <what restores it, who>`, a line `POOL EMPTY: <how measured>`, or for a run over an ' +
    'ordered list `LIST EMPTY: <the order, how measured>` — the pool is what the operator ordered plus an agreed ' +
    'reserve, not the whole ledger (Order Fidelity #3). All after measuring the list in this turn. A wakeup alone is no continuation, and a running watcher (CI, a peer) continues only its own event, not your items. ' +
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
