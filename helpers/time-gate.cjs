#!/usr/bin/env node
/**
 * Stop hook: relative time references are measurement claims.
 *
 * A past-relative time reference in a reply ("yesterday", "last week",
 * "n days ago") asserts a measured timestamp. The contract is binary: either the
 * reference was verified against a source timestamp, or it is omitted — a
 * plausible-sounding guess is worse than no time reference at all.
 *
 * Mechanics: reads the assistant TEXT blocks of the running turn (since the last
 * real operator message) from the transcript and searches for past-relative time
 * expressions. On a hit => ONE block asking to verify each expression against a
 * source timestamp (git log, mtime, install record, log stamp) or drop it, then
 * re-issue the corrected reply.
 *
 * Frequency design (a trigger that always fires becomes ritual):
 *  - fires ONLY on a hit — silent in the normal case;
 *  - stop_hook_active => silent (max one block per turn, no loop);
 *  - cooldown of 2 operator turns after its own block — a conversation ABOUT
 *    time references does not become wallpaper.
 *
 * False-positive design (a text pattern hits the DESCRIPTION of a thing like the
 * thing itself): quotes and code are stripped before matching — common quote
 * pairs, backtick spans, blockquote lines, fenced blocks. Whoever discusses the
 * rule quotes the word; whoever violates it writes it bare. Tested in both
 * directions (fixtures in the commit).
 *
 * Deliberately NOT matched: "today" (checkable against the current date, almost
 * never wrong), future references ("tomorrow", "in n days" — plans, not
 * measurement claims), absolute dates.
 *
 * Language-agnostic by construction — and that is a CONTRACT, not a habit
 * (operator order 2026-08-19): the engine carries only built-in ENGLISH
 * patterns; every further language is DATA, not code — optional instance file
 * `.claude/rules/time-patterns.json` (template `templates/rules-instance/time-patterns.json`):
 * {"patterns": [...], "duration_patterns": [...], "dayparts": [...], "past_markers": [...],
 * "future_markers": [...], "other_day": [...]}, merged in. Any language lands in the same
 * keys and works identically. A class fix always lands in the English built-ins FIRST; a
 * language file only ever adds a language (measured violation on the proving instance: a
 * daytime-attribution fix landed in one language only and left the class open for every
 * other locale).
 *
 * Three modes, one file (wiring: `templates/rules-instance/stop-checks.json`):
 *   (none)     blocking mode — one question per hit, cooldown 2 operator turns;
 *   --record   recorder — every hit with its sentence, never blocks; read back by
 *              `scripts/time-references.py` (and counted by `scripts/recorder-report.py`
 *              through `would_block`);
 *   --clock    what the clock PROVES false (a daytime slot not reached yet, claimed in the
 *              past tense for today); with `"local_time_only": true` in time-patterns.json
 *              also a clock time tagged UTC/Z in prose (an instance whose operator wants
 *              local time only).
 * Carried from the macOS instance's alpha (scripts/hooks/time-gate.cjs there, 2026-08-19 to
 * 2026-11-07), ported as running instance machinery (Working Rule #11).
 */
const fs = require('fs');
const path = require('path');
// A harness notification (task done, watcher event) is not an operator turn — it must not
// count down this gate's cooldown (2026-10-07; one definition: turn-kind.cjs).
const { isNotification } = require('./turn-kind.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
// Both of this gate's markers: the dispatcher echoes the clock block as TIME-CLOCK. Measured
// 2026-10-25: with TIME-GATE alone the clock mode never saw its own block, read the whole turn
// again at every stop and blocked three corrections in a row for a word in an earlier,
// unchangeable message.
let OWN_ECHO = /TIME-GATE|TIME-CLOCK/;
// Echo by label (stop-echo.cjs, 2026-10-31): the dispatcher leaves the bracket token out of the
// operator's line once the gate declares it finds its echo by the label.
const { ownEcho, declare } = require('./stop-echo.cjs');
const COOLDOWN_TURNS = 2;
const TAIL_BYTES = 4 * 1024 * 1024;

// Built-in patterns: English, past-relative only. Word boundaries throughout.
const BUILTIN_PATTERNS = [
  '\\byesterday\\b',
  '\\bthe day before yesterday\\b',
  '\\blast\\s+(week|month|year|night)\\b',
  '\\b\\d+\\s+(minutes?|hours?|days?|weeks?|months?|years?)\\s+ago\\b',
  '\\b(a|a few|some|several|couple of)\\s+(minutes?|hours?|days?|weeks?|months?|years?)\\s+ago\\b',
  '\\b\\d+\\s*[dhm]\\s+ago\\b',
  '\\b\\d+\\s+(minutes?|hours?|days?|weeks?|months?|years?)\\s+old\\b',
  '\\brecently\\b',
  // Daytime attributions are finer-grained same-day claims and need a timestamp
  // just like "yesterday" (measured miss 2026-08-19: an unmeasured "this morning"
  // slipped through — bare "today" stays deliberately unmatched, a sub-day slot
  // does not). Future forms ("tomorrow morning") stay unmatched: plans, not claims.
  '\\bthis\\s+(morning|afternoon|evening)\\b',
  '\\bearlier\\s+today\\b',
];

// Second category (TEST since 2026-08-19, carrier for "no estimated durations"):
// an estimated duration is a measurement claim about the FUTURE — the rule is
// measure or omit, never guess. Present/future estimate forms only; past-tense
// measured statements ("took 34 s") deliberately do not match.
const BUILTIN_DURATION_PATTERNS = [
  '\\b(will|should|might)\\s+take\\s+(about|around|roughly|approximately|~)?\\s*\\d+\\s*(seconds?|minutes?|hours?|days?)\\b',
  '\\btakes\\s+(about|around|roughly|approximately|~)\\s*\\d+\\s*(seconds?|minutes?|hours?|days?)\\b',
  '\\b(approximately|roughly|about|around|~)\\s*\\d+\\s*(seconds?|minutes?|hours?|days?)\\s+(to|until|for)\\b',
];

function buildRegex(builtins, extraKey, cwd) {
  const patterns = [...builtins];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'time-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra[extraKey])) {
      for (const s of extra[extraKey]) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(patterns.join('|'), 'giu');
}

// Third category (operator 2026-10-16, after "the finding of the afternoon" was written at 10:05): a
// daytime slot claimed for TODAY that the clock has not reached yet is not "unverified",
// it is FALSE — and a falsehood the machine can prove needs no judgment call, so it may
// block even while the recorder mode (2026-08-20) keeps every other time word unblocked.
// Only slots that can still be ahead of the clock are listed (a "morning" claim is never
// provably false by the clock alone). A sentence that carries a future marker is a plan,
// not a claim, and a sentence that names another day ("yesterday", a date) is
// not about today. Safe direction: the block needs a PAST marker in the sentence (was,
// found, ran …) — a present-tense plan ("tonight I start …") carries none and
// passes. English built-ins first, other languages as data (time-patterns.json:
// `dayparts` [{"pattern", "start"}], `past_markers`, `future_markers`, `other_day`).
const BUILTIN_DAYPARTS = [
  { pattern: '\\bthis\\s+afternoon\\b', start: 12 },
  { pattern: '\\bthis\\s+evening\\b', start: 17 },
  { pattern: '\\btonight\\b', start: 20 },
];
const BUILTIN_PAST = ['\\b(was|were|did|had|found|measured|ran|went|came|landed|happened|finished|failed|finding)\\b'];
const BUILTIN_FUTURE = ['\\b(will|shall|going to|plan to|later|tomorrow)\\b'];
const BUILTIN_OTHER_DAY = ['\\b(yesterday|tomorrow|\\d{4}-\\d{2}-\\d{2})\\b'];

function loadDayparts(cwd) {
  const parts = [...BUILTIN_DAYPARTS];
  const lists = { past_markers: [...BUILTIN_PAST], future_markers: [...BUILTIN_FUTURE], other_day: [...BUILTIN_OTHER_DAY] };
  try {
    const p = path.join(cwd, '.claude', 'rules', 'time-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    for (const d of extra.dayparts || []) {
      try { new RegExp(d.pattern); if (Number.isFinite(d.start)) parts.push(d); } catch (e) { /* skip */ }
    }
    for (const key of Object.keys(lists)) {
      for (const s of extra[key] || []) { try { new RegExp(s); lists[key].push(s); } catch (e) { /* skip */ } }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  const rx = (a) => new RegExp(a.join('|'), 'iu');
  return { parts, past: rx(lists.past_markers), future: rx(lists.future_markers), otherDay: rx(lists.other_day) };
}

/** Daytime claims the clock contradicts: [{phrase, sentence, start, hour}]. */
function clockContradictions(clean, cwd, now) {
  const { parts, past, future, otherDay } = loadDayparts(cwd);
  const hour = now.getHours() + now.getMinutes() / 60;
  const out = [];
  for (const d of parts) {
    const rx = new RegExp(d.pattern, 'giu');
    let m;
    while ((m = rx.exec(clean)) !== null) {
      const sentence = sentenceAround(clean, m.index, m.index + m[0].length);
      if (hour < d.start && past.test(sentence) && !future.test(sentence) && !otherDay.test(sentence)) {
        out.push({ phrase: m[0], sentence, start: d.start, hour: Math.floor(hour) });
      }
      if (m.index === rx.lastIndex) rx.lastIndex++;
    }
  }
  return out;
}

function localTimeOnly(cwd) {
  try {
    return JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'time-patterns.json'), 'utf8'))
      .local_time_only === true;
  } catch (e) { return false; }
}

function loadPatterns(cwd) { return buildRegex(BUILTIN_PATTERNS, 'patterns', cwd); }
function loadDurationPatterns(cwd) {
  return buildRegex(BUILTIN_DURATION_PATTERNS, 'duration_patterns', cwd);
}

// A reply that is visibly working FROM timestamps does not need to be asked whether
// it looked at one. Measured 2026-08-20 over 10 transcripts (`scripts/gate-precision.py`):
// this gate blocked 7 times and 4 of those answers were re-issued verbatim — the
// wording had been true, the round cost tokens, latency and the operator's attention
// for nothing. Those cases all carried a hard time anchor in the same message: an ISO
// date, a commit hash, a clock time. So the anchor suppresses the block; a relative
// word standing alone, with nothing dated anywhere near it, still gets asked — that is
// where every real violation came from (a time word derived from a memory note).
const ANCHOR = /\b\d{4}-\d{2}-\d{2}\b|\b[0-9a-f]{7,40}\b|\b\d{1,2}:\d{2}\b/;

/** The sentence a hit sits in — what makes a recorded reference checkable later. */
function sentenceAround(text, start, end) {
  const left = Math.max(text.lastIndexOf('.', start), text.lastIndexOf('\n', start)) + 1;
  const candidates = [text.indexOf('.', end), text.indexOf('\n', end)]
    .filter((i) => i !== -1);
  const right = candidates.length ? Math.min(...candidates) : text.length;
  return text.slice(left, right + 1).split(/\s+/).join(' ').trim().slice(0, 240);
}

// Strip quotes/code so that TALK about a time reference does not count as one.
function stripQuoted(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')                       // fenced code
    .replace(/`[^`\n]*`/g, ' ')                             // inline code
    .replace(/„[^“”"\n]*[“”"]/g, ' ')  // „..." quotes (curly OR straight close — measured false positive 2026-08-19: own reply quoted „dauert ca. 5 Minuten" with a straight close, stripper missed the pair, gate fired on the quote)
    .replace(/“[^”]*”/g, ' ')                // "..." curly quotes
    .replace(/"[^"\n]*"/g, ' ')                             // "..." straight quotes
    .replace(/‹[^›]*›|«[^»]*»/g, ' ') // ‹› «»
    .replace(/^\s*>.*$/gm, ' ');                            // blockquote lines
}

/** Assistant texts of the running turn + cooldown state, one transcript pass. */
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
      if (!isNotification(msg.content)) events.push({ boundary: true });
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
  // Texts since this gate's own last block inside the turn: what the AI wrote AFTER being told.
  // A sent message cannot be edited; the clock mode judges the reply, not the history.
  let ownLast = -1;
  for (let i = events.length - 1; i >= last; i--) if (events[i].gate) { ownLast = i; break; }
  const textsSinceOwnBlock = ownLast < 0 ? texts
    : events.slice(ownLast + 1).filter((e) => e.text).map((e) => e.text);

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  return { texts, textsSinceOwnBlock, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);

  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  // RECORD MODE (operator decision 2026-08-20, translated: "not a stop hook at every relative
  // time word ... rather a clear record of all relative time references, so that we can
  // analyse and check them in hindsight"). If the wording is right anyway, the proof
  // of that is a data set, not an interruption. In this mode the gate prints its
  // findings WITH the surrounding sentence and never blocks; the dispatcher appends
  // them to the log that `scripts/time-references.py` reads back.
  const RECORD = process.argv.includes('--record');
  // CLOCK MODE: block only what the clock proves false (see BUILTIN_DAYPARTS). No cooldown,
  // no anchor suppression — a proven falsehood is not a wording question. The clock can be
  // injected for fixtures (TIME_GATE_NOW, ISO string).
  const CLOCK = process.argv.includes('--clock');
  let hits = [];
  let durHits = [];
  let records = [];
  try {
    const seen = analyze(input.transcript_path);
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    if (CLOCK) {
      const now = process.env.TIME_GATE_NOW ? new Date(process.env.TIME_GATE_NOW) : new Date();
      // Only what was written after this gate's last block in the turn (see analyze): a false
      // daytime word in an earlier, already-blocked message must not block the correction too.
      const prose = stripQuoted(seen.textsSinceOwnBlock.join('\n'));
      // Local time only (instance data `local_time_only: true`; on the proving instance an operator
      // correction of 2026-10-19 after times were given in UTC): a clock time tagged UTC/Z in the prose
      // (code and quotes are stripped) blocks. Off by default: whether UTC is wrong is the operator's taste.
      const utc = localTimeOnly(cwd) && prose.match(/\b\d{1,2}:\d{2}(?::\d{2})?\s?(?:UTC|Z)\b/);
      if (utc) {
        console.log(JSON.stringify(declare({ decision: 'block', reason: `TIME-CLOCK — "${utc[0]}" is a UTC time in the reply; ` +
          'this brain gives times to the operator in local time (local_time_only). Convert it, or put a log line in code quotes.' }, input)));
        return process.exit(0);
      }
      const bad = clockContradictions(prose, cwd, now);
      if (bad.length === 0) return allow();
      const hh = String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0');
      const reason = `TIME-CLOCK — the clock says ${hh}: ` + bad.slice(0, 4).map((b) =>
        `"${b.phrase}" (that slot starts at ${b.start}:00) in: ${b.sentence.slice(0, 120)}`).join(' · ')
        + ' — a daytime the day has not reached is a false claim, not an imprecise one: fix or drop the word.';
      console.log(JSON.stringify(declare({ decision: 'block', reason }, input)));
      return process.exit(0);
    }
    // A recorder has no cooldown — the point is completeness, not restraint.
    if (seen.quiet && !RECORD) return allow();
    const clean = stripQuoted(seen.texts.join('\n'));
    const anchored = ANCHOR.test(clean);
    if (RECORD) {
      // Record EVERY relative reference, anchored or not — the anchor is what the
      // blocking mode used to skip, and skipping it here would hide exactly the
      // cases we now want to check in hindsight.
      // would_block = what the blocking mode would have done with this hit: a relative reference
      // blocks only without an anchor, an estimated duration always (scripts/recorder-report.py counts it).
      for (const [rx, family] of [[loadPatterns(cwd), 'relative'], [loadDurationPatterns(cwd), 'duration']]) {
        let m;
        rx.lastIndex = 0;
        while ((m = rx.exec(clean)) !== null) {
          records.push({
            phrase: m[0].toLowerCase().replace(/\s+/g, ' '),
            sentence: sentenceAround(clean, m.index, m.index + m[0].length),
            anchored,
            family,
            would_block: family === 'duration' || !anchored,
          });
          if (m.index === rx.lastIndex) rx.lastIndex++;
        }
      }
      console.log(JSON.stringify({ record: records }));
      return process.exit(0);
    }
    const found = anchored ? [] : (clean.match(loadPatterns(cwd)) || []);
    for (const h of found) {
      const norm = h.toLowerCase().replace(/\s+/g, ' ');
      if (!hits.includes(norm)) hits.push(norm);
    }
    const foundDur = clean.match(loadDurationPatterns(cwd)) || [];
    for (const h of foundDur) {
      const norm = h.toLowerCase().replace(/\s+/g, ' ');
      if (!durHits.includes(norm)) durHits.push(norm);
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (hits.length === 0 && durHits.length === 0) return allow();

  // Terse on purpose (operator finding 2026-08-19, same class as the class-gate
  // trim): the block SHOWS the hits, the rule explains. Precision update same
  // day (operator): the bar is TRUTH, not precision — relative time words are
  // welcome when they are right; the session's own history counts as a source.
  // Verification is owed when the reference is DERIVED from a source (a memory
  // note, someone's report) — that is where every real violation came from.
  let reason = 'TIME-GATE — routine truth check on time wording, not an error.\n';
  if (hits.length > 0) {
    reason += `Relative time reference(s): ${hits.slice(0, 6).join(' · ')} — ` +
      'confirm each one is TRUE (own session history counts; derived-from-a-source ' +
      'needs a look at that source). Wrong or unsure: fix the wording or drop it — ' +
      'no exact clock time required.\n';
  }
  if (durHits.length > 0) {
    reason += `Estimated duration(s): ${durHits.slice(0, 6).join(' · ')} — ` +
      'durations are never guessed: state a measured value or drop the number.\n';
  }
  reason += 'If everything checks out true, re-issue the reply unchanged.';

  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});

process.stdin.resume();
