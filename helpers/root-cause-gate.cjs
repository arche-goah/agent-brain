#!/usr/bin/env node
/**
 * Stop hook + review tool: a mishap or an operator correction opens a root-cause inquiry by
 * itself — the reply names the cause, or the turn does not end.
 *
 * The class (operator, 2026-10-26, translated): "I want you to do root-cause research on your
 * own, always, and fix at the root, up to a core PR when needed — that is the standing order";
 * "this is a failure class: problems get fixed on the spot without going deep, and it keeps
 * going on, although the instance-and-class question has been there for exactly that";
 * "even when it looks like 'only' an instance and no class can be seen, the question for
 * the cause is essential". The day's case: a question postponed ten days earlier was put to
 * him again from a stale record; the fix on the spot would have been to close the question.
 * The rules had the step for years (thinking-protocol: "after an error: cause before fix",
 * "after a user correction: is the user right?"; Class Discipline) — as prose. Every carrier
 * built so far starts one step LATER: the class gate fires on a file written, the lesson
 * carriers on a protocol entry written, the commitment gate on a promise written. Nothing
 * fires on the correction itself. This gate does.
 *
 * What fires: BOTH in the same turn.
 *   (a) the operator's message that opened the turn reads as a correction or a mishap —
 *       "something went wrong", "why did you", "that was already done", "the same again",
 *       "failure class" (English built-ins; other languages as instance data
 *       `.claude/rules/root-cause-patterns.json` {"correction_patterns": [...]});
 *   (b) no assistant text of the turn carries a CAUSE line: `Cause: …` / `Root cause: …` /
 *       "the cause is/was …" / "cause unknown" (`cause_patterns` for other languages).
 * The cause line says what was READ and where (a log line, a file:line, a counter, a record),
 * or that the cause is unknown and what is missing — a hedge word is no cause
 * (thinking-protocol, evidence chain). The class question and the carrier come after it;
 * the gate asks for the cause first because a single instance gets its cause too.
 *
 * Two tiers (operator 2026-10-26: "a lighter variant that runs along, and a heavy workload
 * that runs regularly and targeted, like the coherence scan"):
 *   - Stop (this file through stop-dispatcher.cjs): once per turn, re-issue passes, a
 *     notification turn is not an operator turn, quotes and code stripped.
 *   - `--review [N] [--since YYYY-MM-DD]`: the same detector replayed over this project's
 *     transcripts (newest N, default 40) — every correction turn, whether its reply named a
 *     cause, whether a mechanism file (helpers/, scripts/, hooks/, rules/, skills/,
 *     .claude/rules/) was written within the next five turns — as a Markdown report for the
 *     skill `root-cause-review`, which judges and groups; this tool only counts.
 * The review is also the root test the operator named the same day: a root-cause fix is
 * replayed over the history, and the further instances it would have caught ARE its class.
 *
 * Measured before arming (2026-10-26, macOS instance, the replay below over its history):
 * see the changelog fragment of this change for the numbers that set the pattern lists.
 * Frequency design: fires only on a hit, once per turn; a conversation ABOUT corrections
 * (quoted words) stays silent.
 *
 * Fixture: scripts/test-root-cause-gate.sh.
 */
const fs = require('fs');
const path = require('path');
const { isNotification, isAgentOrigin, isSkillExpansion, isTranscriptRecord } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');
const { intents, intentFor } = require('./autonomous-mode.cjs');

let OWN_ECHO = /ROOT-CAUSE-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const MECHANISM_PATH = /(^|[\\/])(helpers|scripts|hooks|rules|skills|workflows)[\\/]|[\\/]\.claude[\\/]rules[\\/]|[\\/]\.claude[\\/]settings/;
const CARRIER_TURNS = 5;

// ENGINE built-ins — English only (language-agnostic contract, operator order 2026-08-19).
// The FORM of a correction: a thing went wrong, a why-did-you, an "already", a repeat, a
// failure class. Not matched on purpose: a bare "again" or "wrong" (narration), questions
// about the work ("why is the fan loud?") — the subject must be the agent or its result.
// Replayed over 384 transcripts before arming (2026-10-26): "you asked" hit the harness's
// idle notices and a pasted e-mail, a bare "fatal" hit pasted git errors ("fatal: not a git
// repository"), a subject-less "is already running" hit a skill's own text — each tightened
// to the form a correction takes.
const BUILTIN_CORRECTION = [
  '\\b(something|what|that|this|it) (went|has gone) wrong\\b',
  "\\bthat(?:'s| is| was) (wrong|not right|not what i|not it)\\b",
  "\\bwhy (did|didn't|do|don't|have|haven't|are|aren't|were|weren't) you\\b",
  "\\byou (forgot|missed|skipped|ignored|broke|overwrote|deleted|stopped) \\b",
  '\\b(it|that|this|which) (is|was) already (done|active|there|fixed|running|merged|built|answered|set)\\b',
  '\\b(the )?same (mistake|error|failure|thing|problem) (again|as before)\\b',
  '\\b(not )?(this|that) again\\b',
  '\\bfailure class\\b',
  '\\bfatal\\b(?!:)',
  '\\b(this|that|it) (keeps|still) (happening|going on)\\b',
  '\\bstop (doing|asking|saying) (that|this|it)\\b',
];
// A harness notice about another session arrives as a user record without the frames
// turn-kind.cjs knows (measured in the same replay: seven of them matched "you asked").
const HARNESS_NOTICE = /^\s*\[Cross-session [^\]]*\]/;
// A cause named: a `Cause:` line, "the cause is/was", "cause unknown".
const BUILTIN_CAUSE = [
  '^[ \\t>*_-]*(root )?cause\\b[^\\n]{0,24}:',
  '\\b(the |its |my )?(root )?cause (is|was|lies|lay|sits|sat)\\b',
  '\\bcause unknown\\b',
  '\\bcaused by\\b',
];

// A cause named is half the step: the same turn writes the mechanism that keeps it from coming back, or
// says why none can (operator 2026-10-28, translated: "how do you get to anchor it mechanically by
// yourself in that moment, without my hint? — exactly that is what we worked on today"). Measured the
// same day on the macOS instance, one session: a misaddressed check request was re-posted correctly, a
// misclassed PR was merged by hand — each time the cause was named and only the instance fixed; the
// tool that let it through stayed as it was until the operator said so. Rule prose (.md) is no
// mechanism here — that is the class the commitment gate holds.
const BUILTIN_NOCARRIER = [
  '^[ \\t>*_-]*(carrier|mechanism)\\b[^\\n]{0,24}:\\s*(none|not possible|n/a)\\b[^\\n]{8,}',
];
const isMechanismWrite = (p) => MECHANISM_PATH.test(p) && !/\.md$/i.test(p);
// Every cause with its carrier — or the reason none can carry it — goes into ONE register the review
// re-reads (operator 2026-10-28, translated: "if none is possible, that reason belongs in a clean register
// of its own, so we can check again and again whether it really is impossible; the mechanisms found too,
// indexed, with incident, cause, effect, related cases, new historical cases the new detector finds").
// Path: instance data `carrier_register` in root-cause-patterns.json; template templates/carrier-register.md.
const DEFAULT_REGISTER = 'docs/maintenance/carrier-register.md';
function registerPath(cwd) {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'root-cause-patterns.json'), 'utf8'));
    if (typeof d.carrier_register === 'string' && d.carrier_register) return d.carrier_register;
  } catch (e) { /* default */ }
  return DEFAULT_REGISTER;
}
const writesTo = (writes, rel) => writes.some((w) => String(w).replace(/\\/g, '/').endsWith('/' + rel.replace(/\\/g, '/')));

function loadPatterns(cwd, key, builtins, flags) {
  const patterns = [...builtins];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'root-cause-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra[key])) {
      for (const s of extra[key]) { try { new RegExp(s, 'u'); patterns.push(s); } catch (e) { /* skip broken regex */ } }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(patterns.join('|'), flags);
}

// Talk ABOUT a correction quotes it; the correction itself is bare.
function stripQuoted(text) {
  return String(text || '')
    .replace(/```[\s\S]*?```/g, ' ').replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ').replace(/“[^”]*”/g, ' ').replace(/"[^"\n]*"/g, ' ')
    .replace(/‹[^›]*›|«[^»]*»/g, ' ').replace(/^\s*>.*$/gm, ' ');
}

function sentenceAt(text, index) {
  const start = Math.max(text.lastIndexOf('. ', index), text.lastIndexOf('\n', index), -1) + 1;
  const ends = ['. ', '\n', '? ', '! '].map((s) => text.indexOf(s, index)).filter((i) => i >= 0);
  return text.slice(start, ends.length ? Math.min(...ends) : text.length).trim();
}

function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b.type === 'tool_result')) return null;
  return msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n') || null;
}

/**
 * The transcript as turns: each opened by an operator prompt, carrying the assistant texts
 * and the file paths written until the next prompt. Hook echoes, notifications, peer
 * messages and skill expansions open no turn (one definition: turn-kind.cjs).
 */
function readTurns(tp, tail) {
  let text;
  if (tail) {
    const size = fs.statSync(tp).size;
    const start = Math.max(0, size - TAIL_BYTES);
    const fd = fs.openSync(tp, 'r');
    const buf = Buffer.alloc(size - start);
    try { fs.readSync(fd, buf, 0, buf.length, start); } finally { fs.closeSync(fd); }
    text = buf.toString('utf8');
    if (start > 0) text = text.slice(text.indexOf('\n') + 1);
  } else {
    text = fs.readFileSync(tp, 'utf8');
  }
  const turns = [];
  let cur = null;
  let fired = false;
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      if (!cur) continue;
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) cur.texts.push(b.text);
        if (b.type === 'tool_use' && b.input && typeof b.input.file_path === 'string') cur.writes.push(b.input.file_path);
      }
      continue;
    }
    if (msg.role !== 'user') continue;
    const t = promptText(msg);
    if (t === null) continue;
    if (HOOK_ECHO.test(t)) { if (OWN_ECHO.test(t) && cur) cur.fired = true; continue; }
    if (isNotification(t) || isAgentOrigin(d) || isSkillExpansion(d) || HARNESS_NOTICE.test(t)) continue;
    cur = { prompt: t, when: d.timestamp || '', texts: [], writes: [], fired: false };
    turns.push(cur);
  }
  return turns;
}

function correctionIn(prompt, rx) {
  const clean = stripQuoted(prompt);
  const m = rx.exec(clean);
  return m ? sentenceAt(clean, m.index) : null;
}

function causeIn(texts, rx) {
  return texts.some((t) => rx.test(stripQuoted(t)));
}

function gate(input) {
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (input.stop_hook_active || !input.transcript_path) return;
  if (input.turn_kind === 'notification') return;
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let turns;
  try { turns = readTurns(input.transcript_path, true); } catch (e) { return; }
  const turn = turns[turns.length - 1];
  if (!turn || turn.fired) return;
  // The prompt classifier's record decides too (2026-10-30, macOS instance: "find the cause and fix it at the root",
  // in the operator's language, passed the word list; the classifier read correction=true). Safe direction only: it can open the inquiry (one
  // cause line owed), never close one the words opened.
  let hit = correctionIn(turn.prompt, loadPatterns(cwd, 'correction_patterns', BUILTIN_CORRECTION, 'iu'));
  if (!hit) {
    const intent = intentFor(intents(input.transcript_path, cwd), turn.when);
    if (intent && intent.correction) hit = sentenceAt(stripQuoted(turn.prompt), 0);
  }
  const cause = causeIn(turn.texts, loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu'));
  if (cause) {
    const reg = registerPath(cwd);
    const mech = turn.writes.some(isMechanismWrite)
      || causeIn(turn.texts, loadPatterns(cwd, 'nocarrier_patterns', BUILTIN_NOCARRIER, 'imu'));
    const registered = writesTo(turn.writes, reg);
    if (mech && registered) return;
    const missing = [!mech && 'no mechanism written', !registered && `no entry in ${reg}`].filter(Boolean).join(', ');
    process.stdout.write(JSON.stringify(declare({
      decision: 'block',
      reason: `ROOT-CAUSE-GATE: this turn names a cause - ${missing}. Fixing the instance (a re-post, a manual merge, a `
        + 'ledger or memory note) leaves the tool that let it happen as it was. Before this turn ends: change the '
        + 'producing tool or gate data (helpers/, scripts/, hooks/, rule JSON - a core or suite PR where the tool '
        + 'lives) with a fixture, or say Carrier: none - <why no mechanism can carry it>; AND write the entry in '
        + `${reg}: incident, cause, effect, carrier (or none + reason + recheck date), related cases, replay hits.`,
    }, input)));
    return;
  }
  if (!hit) return;
  process.stdout.write(JSON.stringify(declare({
    decision: 'block',
    reason: `ROOT-CAUSE-GATE: the operator's message that opened this turn reads as a correction or a mishap: "${hit.slice(0, 160)}". `
      + 'The reply names no cause. Before this turn ends, measure what produced it and write ONE line — '
      + 'Cause: <what was read, where> — <A produced B>, or Cause: unknown — <what is missing to tell>. '
      + 'Then the class (search: where else does the same sit?) and the carrier (where it is fixed for good: gate, script, rule, core PR). '
      + 'A single instance gets its cause too (operator 2026-10-26); the class may show only when the fix is replayed over the history.',
  }, input)));
}

/** Where this project's transcripts live: the folder Claude Code mints from the project path. */
function projectDir(root) {
  // Claude Code mints the folder by replacing every non-alphanumeric character with '-' (memory-sync.cjs, measured on Windows 2026-08-03).
  const slug = path.resolve(root).replace(/[^A-Za-z0-9]/g, '-');
  const home = process.env.HOME || process.env.USERPROFILE || '';
  return path.join(home, '.claude', 'projects', slug);
}

function review(args) {
  const cwd = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let n = 40; let since = ''; let dir = projectDir(cwd);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--since') since = args[++i] || '';
    else if (args[i] === '--dir') dir = args[++i] || dir;
    else if (/^\d+$/.test(args[i])) n = parseInt(args[i], 10);
  }
  const rxC = loadPatterns(cwd, 'correction_patterns', BUILTIN_CORRECTION, 'iu');
  const rxZ = loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu');
  let files;
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(dir, f))
      .map((f) => ({ f, m: fs.statSync(f).mtimeMs })).sort((a, b) => b.m - a.m).slice(0, n).map((x) => x.f);
  } catch (e) { console.log(`root-cause review: no transcripts under ${dir}`); return 1; }
  const rxN = loadPatterns(cwd, 'nocarrier_patterns', BUILTIN_NOCARRIER, 'imu');
  const found = [];
  let turnsTotal = 0, causeTurns = 0, causeNoMech = 0;
  const causeNoMechList = [];
  for (const f of files) {
    let turns;
    try { turns = readTurns(f, false); } catch (e) { continue; }
    turnsTotal += turns.length;
    turns.forEach((t, i) => {
      if (since && t.when.slice(0, 10) < since) return;
      // the cause-needs-a-carrier check (2026-10-28), replayed: every turn that names a cause
      if (causeIn(t.texts, rxZ)) {
        causeTurns++;
        if (!t.writes.some(isMechanismWrite) && !causeIn(t.texts, rxN)) {
          causeNoMech++;
          causeNoMechList.push(`${t.when.slice(0, 10)} ${path.basename(f, '.jsonl').slice(0, 8)}: "${t.prompt.replace(/\s+/g, ' ').slice(0, 100)}"`);
        }
      }
      const hit = correctionIn(t.prompt, rxC);
      if (!hit) return;
      const cause = causeIn(t.texts, rxZ);
      const later = turns.slice(i, i + CARRIER_TURNS + 1);
      const carrier = later.some((u) => u.writes.some((w) => MECHANISM_PATH.test(w)));
      found.push({ when: t.when.slice(0, 10), session: path.basename(f, '.jsonl').slice(0, 8), hit, cause, carrier });
    });
  }
  found.sort((a, b) => (a.when < b.when ? -1 : a.when > b.when ? 1 : 0));
  const withCause = found.filter((x) => x.cause).length;
  const withCarrier = found.filter((x) => x.carrier).length;
  const pct = (a, b) => (b ? `${Math.round((100 * a) / b)} %` : '-');
  console.log(`# Root-cause review — ${new Date().toISOString().slice(0, 10)}\n`);
  console.log(`transcripts ${files.length} · operator turns ${turnsTotal} · corrections ${found.length}`
    + ` · reply named a cause ${withCause} (${pct(withCause, found.length)})`
    + ` · a mechanism file written within ${CARRIER_TURNS} turns ${withCarrier} (${pct(withCarrier, found.length)})`
    + ` · turns naming a cause ${causeTurns}, without a mechanism write in the same turn ${causeNoMech} (${pct(causeNoMech, causeTurns)})\n`);
  const months = {};
  for (const x of found) {
    const k = x.when.slice(0, 7) || '?';
    months[k] = months[k] || { n: 0, cause: 0, carrier: 0 };
    months[k].n++; if (x.cause) months[k].cause++; if (x.carrier) months[k].carrier++;
  }
  console.log('| month | corrections | cause named | carrier within 5 turns |\n|---|---|---|---|');
  for (const k of Object.keys(months).sort()) console.log(`| ${k} | ${months[k].n} | ${months[k].cause} | ${months[k].carrier} |`);
  console.log('\n## Corrections whose reply named no cause\n');
  for (const x of found.filter((y) => !y.cause)) {
    console.log(`- ${x.when} ${x.session} ${x.carrier ? '(mechanism written later)' : '(no mechanism within 5 turns)'}: "${x.hit.replace(/\s+/g, ' ').slice(0, 140)}"`);
  }
  // The register, re-read: a "none" whose recheck date has come, an entry without its replay.
  let regText = '';
  try { regText = fs.readFileSync(path.join(cwd, registerPath(cwd)), 'utf8'); } catch (e) { /* none yet */ }
  const entries = regText.split(/^## /m).slice(1);
  const today = new Date().toISOString().slice(0, 10);
  const due = entries.filter((e) => /^\s*carrier:\s*none\b/im.test(e)
    && (/^\s*recheck:\s*(\d{4}-\d{2}-\d{2})/im.exec(e) || [])[1] <= today);
  const noReplay = entries.filter((e) => !/^\s*replay:\s*\S/im.test(e));
  console.log(`\n## Carrier register (${registerPath(cwd)}): ${entries.length} entries · "none" due for recheck ${due.length}`
    + ` · without a replay ${noReplay.length}\n`);
  for (const e of due) console.log(`- recheck due: ${e.split('\n')[0].trim()}`);
  for (const e of noReplay) console.log(`- no replay yet: ${e.split('\n')[0].trim()}`);
  console.log('\n## Turns that named a cause and wrote no mechanism (newest 40)\n');
  for (const x of causeNoMechList.sort().slice(-40)) console.log(`- ${x}`);
  console.log('\n## Corrections whose reply named a cause\n');
  for (const x of found.filter((y) => y.cause)) {
    console.log(`- ${x.when} ${x.session} ${x.carrier ? '(mechanism written later)' : ''}: "${x.hit.replace(/\s+/g, ' ').slice(0, 140)}"`);
  }
  return 0;
}

if (process.argv[2] === '--review') {
  process.exit(review(process.argv.slice(3)));
} else {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    try { gate(JSON.parse(data || '{}')); } catch (e) { /* fail open */ }
    process.exit(0);
  });
}
