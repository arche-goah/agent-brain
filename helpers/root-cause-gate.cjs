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
 *     notification turn is not an operator turn, quotes and code stripped. One exception
 *     (2026-11-11): a turn held for a MISSING cause whose re-issued reply names the cause is
 *     held once more for that cause's carrier - at most two blocks per turn.
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
const { isNotification, isAgentOrigin, isSkillExpansion, isTranscriptRecord, operatorWords, queuedHumanPrompt } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');
const { intents, intentFor } = require('./autonomous-mode.cjs');

let OWN_ECHO = /ROOT-CAUSE-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
// `tools/` is a mechanism folder too (2026-11-03, macOS instance: a 3D-print repo keeps its build kit and print gates there).
const MECHANISM_PATH = /(^|[\\/])(helpers|scripts|hooks|rules|skills|workflows|tools)[\\/]|[\\/]\.claude[\\/]rules[\\/]|[\\/]\.claude[\\/]settings/;
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

// A register entry is a CLASS entry, not a note on the instance (2026-11-11, macOS instance: the gate took any
// mechanism write - an instance-tailored gate passed, and the entry was never written; the operator had to ask why the
// cause found was not fixed at the root). The text written to the register this turn carries
//   invariant: <the rule that was broken, said without the instance's names - no path, no PR/issue number>
//   replay:    <the detector over the history with its count> (a digit; "pending" is no replay)
// Instance data `invariant_forbidden` (root-cause-patterns.json) adds its own proper nouns the invariant must not use.
const INVARIANT = /^[ \t>*_-]*invariant:[ \t]*(\S[^\n]{11,})/imu;
const REPLAY = /^[ \t>*_-]*replay:[ \t]*(?!pending)[^\n]*\d/imu;
const INSTANCE_WORD = /[\\/][\w.-]+\.\w{1,5}\b|#\d+\b|\b\w+\.(cjs|js|py|sh|json|md)\b/u;
function entryGaps(writeTexts, rel, forbidden) {
  const text = writeTexts.filter((w) => writesTo([w.p], rel)).map((w) => w.t).join('\n');
  const inv = INVARIANT.exec(text);
  const gaps = [];
  if (!inv) gaps.push('the register entry names no invariant:');
  else if (INSTANCE_WORD.test(inv[1]) || forbidden.test(inv[1])) gaps.push('the invariant: names the instance (a path, a number, a proper noun) - say the rule, not the case');
  if (!REPLAY.test(text)) gaps.push('the register entry has no replay: count');
  return gaps;
}

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
    // A message the operator types while the agent works lands as a queued_command attachment, not a user
    // record; it opens its own segment (measured on the macOS instance 2026-10-29: in one long turn every
    // correction arrived this way and none was judged; the instance copy carried this until the pin removed it).
    const queued = queuedHumanPrompt(d);
    if (queued) {
      cur = { prompt: queued, when: d.timestamp || '', texts: [], writes: [], fired: false, queued: true };
      turns.push(cur);
      continue;
    }
    const msg = d.message; if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      if (!cur) continue;
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) cur.texts.push(b.text);
        if (b.type === 'tool_use' && b.input && typeof b.input.file_path === 'string') {
          cur.writes.push(b.input.file_path);
          (cur.writeTexts = cur.writeTexts || []).push({ p: b.input.file_path, t: String(b.input.new_string || b.input.content || '') });
        }
      }
      continue;
    }
    if (msg.role !== 'user') continue;
    const t = promptText(msg);
    if (t === null) continue;
    if (HOOK_ECHO.test(t)) {
      if (OWN_ECHO.test(t) && cur) {
        cur.fired = true;
        cur.fires = (cur.fires || 0) + 1;
        if (cur.echoAt === undefined) cur.echoAt = cur.texts.length;   // texts written before the first own block
      }
      continue;
    }
    if (isNotification(t) || isAgentOrigin(d) || isSkillExpansion(d) || HARNESS_NOTICE.test(t)) continue;
    cur = { prompt: t, when: d.timestamp || '', texts: [], writes: [], fired: false, queued: false };
    turns.push(cur);
  }
  return turns;
}

// The turn the Stop sees as a whole: the last message the operator SENT (a user record) and every message typed
// while the agent worked (queued segments). Measured 2026-11-04 on the macOS instance (80 transcripts): 33 correction
// segments, 18 of them NOT the last segment of their assistant turn - the gate judged turns[last] only, so a
// correction followed by another typed message was never judged; 4 of the 18 got no cause line at all, two of them
// that day, with the operator asking the third time in a week why no cause followed.
function currentTurn(turns) {
  let k = turns.length - 1;
  while (k > 0 && turns[k].queued) k -= 1;
  const group = turns.slice(Math.max(0, k));
  // The texts written before the first own block of the turn: did that block ask for the cause, or for the carrier?
  const preEcho = [];
  for (const t of group) {
    if (t.echoAt !== undefined) { preEcho.push(...t.texts.slice(0, t.echoAt)); break; }
    preEcho.push(...t.texts);
  }
  return {
    group, texts: group.flatMap((t) => t.texts), writes: group.flatMap((t) => t.writes),
    fired: group.some((t) => t.fired), fires: group.reduce((n, t) => n + (t.fires || 0), 0), preEcho,
    writeTexts: group.flatMap((t) => t.writeTexts || []),
  };
}

// The first correction in the turn (word list, else the prompt classifier's record) that no later text answers with
// a cause line; with causeRx null, the first correction regardless (the --pre check wants the class before the
// instance even when a cause is already named).
function firstCorrection(group, cwd, transcriptPath, rx, causeRx) {
  let known = null;
  for (let i = 0; i < group.length; i += 1) {
    const seg = group[i];
    let hit = correctionIn(seg.prompt, rx);
    if (!hit) {
      if (!known) known = intents(transcriptPath, cwd);
      const intent = intentFor(known, seg.when);
      if (intent && intent.correction) hit = sentenceAt(stripQuoted(seg.prompt), 0);
    }
    if (!hit) continue;
    if (causeRx && causeIn(group.slice(i).flatMap((t) => t.texts), causeRx)) continue;
    return hit;
  }
  return null;
}

// The gate and `--review` both judge here: a pasted e-mail or log is not the operator's correction
// (turn-kind.cjs operatorWords, 2026-10-28).
function correctionIn(prompt, rx) {
  const clean = stripQuoted(operatorWords(prompt));
  const m = rx.exec(clean);
  return m ? sentenceAt(clean, m.index) : null;
}

function causeIn(texts, rx) {
  return texts.some((t) => rx.test(stripQuoted(t)));
}

// "Carrier: none" is an escape the agent can always write, so on its own it releases nothing (operator decision
// 2026-11-02 on the macOS instance, translated: "a cause does not only belong in the register, the fix at the root
// is built and secured mechanically ... that in itself should be secured mechanically" - measured the same day: 41
// register entries "carrier: none", three written in one session to pass this very check). It counts only with the
// operator's agreement quoted on the same line, `operator-ok: "<words>"`, and those words must stand in one of the
// operator's own messages of the transcript - an invented quote releases nothing.
const OK_QUOTE = /operator-ok:\s*["„“]([^"„“”\n]{4,})["“”]/iu;
function noCarrierAgreed(texts, rxNone, turns) {
  const said = turns.map((t) => operatorWords(t.prompt || '')).join('\n').toLowerCase();
  return texts.some((t) => t.split('\n').some((line) => {
    if (!rxNone.test(stripQuoted(line))) return false;
    const q = OK_QUOTE.exec(line);
    return !!q && said.includes(q[1].trim().toLowerCase());
  }));
}

/**
 * PreToolUse (`--pre`): in a correction turn the CLASS comes before the instance.
 * The class (operator 2026-11-03, translated): "cause only found, or fixed at the root? or once again only the
 * instance fixed afterwards instead of the class?" and "why do you do all this only after being asked several
 * times?". Measured the same evening on the macOS instance: after a correction the first edits went into the one
 * model script (the instance); the build kit, the print gates and the rule data followed only after two more
 * corrections. The Stop check above asks for a cause and a carrier at the END of the turn - by then the instance fix
 * is written and the carrier reads as an afterthought. This check holds the first instance edit of a correction turn
 * until the turn has touched a mechanism file (helpers/, scripts/, hooks/, rules/, skills/, workflows/, tools/,
 * .claude/rules) or says `Carrier: none - <why>`. Free: every mechanism write itself, documentation (.md) - ledgers
 * and the carrier register are written in the same turn.
 */
function preGate(input) {
  const tool = input.tool_name || '';
  if (!/^(Write|Edit|MultiEdit|NotebookEdit)$/.test(tool) || !input.transcript_path) return;
  const target = String((input.tool_input || {}).file_path || (input.tool_input || {}).notebook_path || '');
  if (!target || isMechanismWrite(target) || /\.(md|markdown|txt)$/i.test(target)) return;
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let turns;
  try { turns = readTurns(input.transcript_path, true); } catch (e) { return; }
  const { group, texts, writes } = currentTurn(turns);
  if (!group.length) return;
  const hit = firstCorrection(group, cwd, input.transcript_path,
    loadPatterns(cwd, 'correction_patterns', BUILTIN_CORRECTION, 'iu'), null);
  if (!hit) return;
  if (writes.some(isMechanismWrite)) return;
  if (causeIn(texts, loadPatterns(cwd, 'nocarrier_patterns', BUILTIN_NOCARRIER, 'imu'))) return;
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: `CLASS-FIRST: this turn answers a correction ("${hit.slice(0, 120)}") and its first edit `
        + `goes to an instance file (${path.basename(target)}) before any carrier. Class before instance: first change the `
        + 'tool, gate or rule data that let it happen (helpers/, scripts/, hooks/, rules/, skills/, tools/ - a core or suite '
        + 'PR where it lives) with its negative control, or write one line Carrier: none - <why no mechanism can carry it>. '
        + 'Then the instance edit passes.',
    },
  }));
}

function gate(input) {
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (input.stop_hook_active || !input.transcript_path) return;
  if (input.turn_kind === 'notification') return;
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let turns;
  try { turns = readTurns(input.transcript_path, true); } catch (e) { return; }
  const { group, texts, writes, fired, fires, preEcho, writeTexts } = currentTurn(turns);
  if (!group.length) return;
  // The prompt classifier's record decides too (2026-10-30, macOS instance: "find the cause and fix it at the root",
  // in the operator's language, passed the word list; the classifier read correction=true). Safe direction only: it can open the inquiry (one
  // cause line owed), never close one the words opened. Every message of the turn is judged (currentTurn), a
  // cause line from that message on answers it.
  const causeRx = loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu');
  const cause = causeIn(texts, causeRx);
  // A block passes on its re-issue (frequency design) - but a block for a MISSING cause is no release of the carrier
  // owed once the cause is named after it (2026-11-11, macOS instance: a correction turn was held for its cause, the
  // re-issued reply named the cause, the turn ended without a mechanism; the operator had to ask a second time why the
  // cause found was neither researched further nor fixed). So: at most two blocks per turn, the second only for the
  // carrier of a cause that came after the first block.
  if (fired && (fires >= 2 || causeIn(preEcho, causeRx) || !cause)) return;
  const hit = fired ? null : firstCorrection(group, cwd, input.transcript_path,
    loadPatterns(cwd, 'correction_patterns', BUILTIN_CORRECTION, 'iu'), causeRx);
  if (cause) {
    const reg = registerPath(cwd);
    const mech = writes.some(isMechanismWrite)
      || noCarrierAgreed(texts, loadPatterns(cwd, 'nocarrier_patterns', BUILTIN_NOCARRIER, 'imu'), turns);
    const registered = writesTo(writes, reg);
    const gaps = registered ? entryGaps(writeTexts, reg, loadPatterns(cwd, 'invariant_forbidden', ['(?!)'], 'iu')) : [];
    if (mech && registered && !gaps.length) return;
    const missing = [!mech && 'no mechanism written', !registered && `no entry in ${reg}`, ...gaps].filter(Boolean).join(', ');
    process.stdout.write(JSON.stringify(declare({
      decision: 'block',
      reason: `ROOT-CAUSE-GATE: this turn names a cause - ${missing}${fired ? ' (the cause came after the first block; naming it does not release the carrier)' : ''}. Fixing the instance (a re-post, a manual merge, a `
        + 'ledger or memory note) leaves the tool that let it happen as it was. Before this turn ends: change the '
        + 'producing tool or gate data (helpers/, scripts/, hooks/, rule JSON - a core or suite PR where the tool '
        + 'lives) with a fixture. "Carrier: none" releases only with the operator\'s words on the same line, '
        + 'operator-ok: "<their words>", found in their own messages - never on the agent\'s say-so; AND write the entry in '
        + `${reg}: incident, cause, invariant (the broken rule without the instance's names), effect, carrier (or none + `
        + 'reason + recheck date), related cases, replay (the invariant run over the history, with its count), '
        + 'found-by (operator | work | ci | <the check that found it>; when not a check: should-have: <the check that should have>).',
    }, input)));
    return;
  }
  if (!hit) return;
  process.stdout.write(JSON.stringify(declare({
    decision: 'block',
    reason: `ROOT-CAUSE-GATE: an operator message in this turn reads as a correction or a mishap: "${hit.slice(0, 160)}". `
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
    // A headless model call (the prompt classifier, `claude -p`) leaves a transcript of its own whose records carry
    // `entrypoint: "sdk-cli"`; its prompt quotes the operator and matches the correction words. Measured 2026-11-02 on
    // the macOS instance: 116 such transcripts in a week, 63 "corrections" instead of 16, and as the newest files they
    // pushed the real sessions out of the newest-N window. They are no session — left out before the window is cut.
    const headless = (p) => {
      try {
        // 256 KB: the first record of such a call is its whole prompt, the field can stand after it (measured: not
        // within the first 4 KB). The FIRST entrypoint value decides, so a quoted field later in a session does not.
        const fd = fs.openSync(p, 'r'); const buf = Buffer.alloc(256 * 1024);
        const len = fs.readSync(fd, buf, 0, buf.length, 0); fs.closeSync(fd);
        const m = /"entrypoint"\s*:\s*"([^"]+)"/.exec(buf.toString('utf8', 0, len));
        return !!m && m[1] === 'sdk-cli';
      } catch (e) { return false; }
    };
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(dir, f))
      .filter((f) => !headless(f))
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
  // Who found it (audit-audit 2026-11-02, macOS instance: of 144 register entries the operator found 54 %, a check
  // 6 % — counted by keyword, because no entry said it). The field makes the checks' hit rate a reading, not a guess.
  const finder = (e) => ((/^\s*found-by:\s*([^\n]+)/im.exec(e) || [])[1] || '').trim().toLowerCase();
  const withFinder = entries.filter((e) => finder(e));
  const byCheck = withFinder.filter((e) => !/^(operator|work|ci)\b/.test(finder(e)));
  console.log(`\n## Carrier register (${registerPath(cwd)}): ${entries.length} entries · "none" due for recheck ${due.length}`
    + ` · without a replay ${noReplay.length} · found-by named ${withFinder.length}, of them by a check ${byCheck.length}\n`);
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
  const pre = process.argv[2] === '--pre';
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    try { (pre ? preGate : gate)(JSON.parse(data || '{}')); } catch (e) { /* fail open */ }
    process.exit(0);
  });
}
