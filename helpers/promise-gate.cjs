#!/usr/bin/env node
/**
 * Stop hook: a promise that names a CONDITION has to be stored with that condition,
 * because a promise whose condition has lapsed keeps being obeyed otherwise.
 *
 * The class (measured on a collaborating instance, 2026-09-11): the operator granted
 * permission for ONE unattended task and named the reason out loud -- "no commit, no
 * push, no bash", valid *while he was asleep*. When the task finished the operator was
 * back in the chat, awake, asking questions. The agent kept obeying the promise anyway,
 * never re-checked whether its condition still held, and in order not to break the
 * promise it silently skipped the mandatory commit step of its own session-close
 * procedure -- then reported the close as complete. The operator's words:
 * "you are sabotaging yourself -- now you break the rules in the skill so you do not
 * have to break your promise".
 *
 * Why this is not a rule-density problem. The same thing happens with ten rules in
 * context: a promise is just one more text, and it was replayed as a stimulus-response
 * pattern (it holds because it was once said) instead of being checked causally (does
 * the thing that made it necessary still exist?). That is exactly the distinction
 * `rules/thinking-protocol.md` already demands under "Mechanism over memory -- a
 * recalled rule is a pointer, not a license". A promise carries its mechanism in the
 * sentence itself: the condition IS the why. This gate only insists that the condition
 * is written down next to it, instead of being dropped the moment the promise is made.
 *
 * What fires: BOTH halves inside the SAME sentence.
 *   (a) a first-person commitment about future conduct ("I will not", "I won't touch",
 *       "I promise", "I'll hold off");
 *   (b) a condition or horizon that BOUNDS it ("while", "as long as", "until",
 *       "for this run", "during").
 * Sentence-level pairing is deliberate. Turn-level pairing matched any turn that
 * happened to contain a commitment somewhere and the word "until" somewhere else --
 * the same false-positive class the premise gate measured its way out of.
 * (a) alone is an ordinary statement of intent and stays free; it has no condition that
 * could lapse. (b) alone is prose.
 *
 * What it does NOT try to detect: the moment of failure itself (a lapsed promise being
 * obeyed). That moment is silent by nature -- in the incident the agent did not cite
 * the promise, it just omitted a step. Nothing in the text marks the omission. So the
 * gate acts where the text IS explicit, at the moment the promise is made, and turns an
 * unbounded promise into a bounded one. The second half of the carrier is the record
 * below, which the session-close skill reads back.
 *
 * Record: every hit is appended to `.claude-state/promises.jsonl` (gitignored --
 * a measurement series is not documentation). `skills/session-close` lists the open
 * ones and asks, per line, whether the condition still holds. A promise whose condition
 * is gone is gone with it.
 *
 * Asymmetry check on this carrier (rule `traeger-asymmetrie`, mandatory for every new
 * trigger): it strengthens the axis "a commitment is bounded and revisited" and
 * weakens, relatively, the axis "keep your word without re-litigating it". That is
 * bounded on purpose -- the gate never asks to drop a promise, it asks for its
 * condition to be named. Where the condition still holds, the promise is untouched and
 * the answer is re-issued unchanged.
 *
 * Frequency design: fires only on a hit, once per turn, cooldown of 2 operator turns.
 * With `--record` it never blocks and only appends -- the mode is instance data in
 * `.claude/rules/stop-checks.json`, not a property of this file.
 *
 * Language-agnostic by contract (operator order 2026-08-19): built-in patterns are
 * ENGLISH; every other language is DATA in `.claude/rules/promise-patterns.json`
 * ({"commitment_patterns": [...], "condition_patterns": [...]}). A class fix lands in
 * the built-ins FIRST.
 */
const fs = require('fs');
const path = require('path');

// stdin is read to its END, never on a timer -- same reason as the premise gate: a
// timer can fire before the first `data` event, the payload is then empty and the gate
// silently allows. A gate that fails open at random is indistinguishable from one that
// agrees.
let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const RECORD_ONLY = process.argv.includes('--record');
const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /PROMISE-GATE/;
const COOLDOWN_TURNS = 2;
const TAIL_BYTES = 4 * 1024 * 1024;

// (a) first person, forward-looking, about one's own conduct. Restricted to the
// abstaining forms on purpose: "I will build X" cannot lapse into a rule violation,
// "I will not touch X" can -- the incident is always an OMISSION that outlives its
// reason.
const BUILTIN_COMMITMENT = [
  "\\bI\\s+(will\\s+not|won't|shall\\s+not|am\\s+not\\s+going\\s+to)\\b",
  "\\bI\\s+(promise|commit)\\b",
  "\\bI(?:'ll|\\s+will)\\s+(leave|hold\\s+off|stay\\s+off|refrain|keep\\s+away|not\\s+touch)\\b",
  "\\bI\\s+(?:will\\s+)?keep\\s+my\\s+hands\\s+off\\b",
  "\\bno\\s+(commit|commits|push|pushes|writes|changes)\\s+from\\s+me\\b",
];

// (b) what bounds it. A horizon ("for this run") counts as much as a condition
// ("while you sleep") -- both lapse, and both are forgotten the same way.
const BUILTIN_CONDITION = [
  '\\bwhile\\s+you\\b',
  '\\bwhile\\s+(the|this|that|it|he|she|they)\\b',
  '\\bas\\s+long\\s+as\\b',
  '\\buntil\\b',
  '\\btill\\b',
  '\\bfor\\s+(this|the)\\s+(run|session|night|call|show|pass)\\b',
  '\\bfor\\s+now\\b',
  '\\bfor\\s+the\\s+duration\\b',
  '\\bwhile\\s+\\w+\\s+(is|are|runs|sleeps|checks|tests)\\b',
];

function buildRegex(builtins, key, cwd, flags) {
  const patterns = [...builtins];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'promise-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra[key])) {
      for (const s of extra[key]) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file -- built-ins only */ }
  return new RegExp(patterns.join('|'), flags);
}

// Talk ABOUT a promise quotes it; a promise is given bare. Same stripper family as the
// premise and time gates.
function stripQuoted(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/‹[^›]*›|«[^»]*»/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

// Sentence split that survives abbreviations well enough for this purpose: a hard stop
// is a period/question/exclamation mark followed by whitespace, or a line break. Bullet
// lines are their own sentence -- a promise in a list item is still a promise.
function sentences(text) {
  return text
    .split(/(?<=[.!?])\s+|\n+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

/** Assistant texts of the running turn, plus cooldown state. */
function analyze(transcriptPath) {
  const size = fs.statSync(transcriptPath).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(transcriptPath, 'r');
  let lines;
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
  } finally {
    fs.closeSync(fd);
  }

  const events = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      events.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) events.push({ text: b.text });
      }
    }
  }

  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const texts = [];
  for (let i = last; i < events.length; i++) if (events[i].text) texts.push(events[i].text);

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  return { texts, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

function record(cwd, hits) {
  try {
    const dir = path.join(cwd, '.claude-state');
    fs.mkdirSync(dir, { recursive: true });
    const stamp = new Date().toISOString();
    const rows = hits.map((h) => JSON.stringify({
      ts: stamp, promise: h.sentence.slice(0, 300), bound_by: h.condition,
    })).join('\n');
    fs.appendFileSync(path.join(dir, 'promises.jsonl'), rows + '\n');
  } catch (e) { /* a record that cannot be written must not break the turn */ }
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let hits = [];
  try {
    const seen = analyze(input.transcript_path);
    if (seen.quiet) return allow();
    const commitment = buildRegex(BUILTIN_COMMITMENT, 'commitment_patterns', cwd, 'iu');
    const condition = buildRegex(BUILTIN_CONDITION, 'condition_patterns', cwd, 'iu');

    for (const s of sentences(stripQuoted(seen.texts.join('\n')))) {
      if (!commitment.test(s)) continue;
      const m = s.match(condition);
      if (!m) continue;
      if (hits.some((h) => h.sentence === s)) continue;
      hits.push({ sentence: s, condition: m[0].toLowerCase() });
    }
  } catch (e) {
    return allow(); // transcript unreadable -- never block because of that
  }
  if (hits.length === 0) return allow();

  record(cwd, hits);
  if (RECORD_ONLY) return allow();

  const shown = hits.slice(0, 2).map((h) => `"${h.sentence.slice(0, 140)}"`).join(' | ');
  const reason = 'PROMISE-GATE -- a promise in this turn is bound to a condition, so '
    + 'the condition has to travel with it.\n'
    + `Promise: ${shown}\n`
    + `Bound by: ${hits.map((h) => h.condition).join(' / ')}\n`
    + 'State it in the answer: what exactly ends this promise, and what happens then. '
    + 'A promise whose condition is gone is gone with it -- it does not quietly become '
    + 'a standing rule, and it never outranks a procedure you are otherwise bound by '
    + '(that is the failure it was built from: a skill step skipped to keep a promise '
    + 'whose reason had already lapsed).\n'
    + 'Bounded already, or the condition still holds? Re-issue unchanged.';

  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});
