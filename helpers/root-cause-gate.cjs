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
const { exit: hookExit } = require('./hook-exit.cjs');   // not process.exit: it hung at Node shutdown (2026-11-23)
const path = require('path');
const { isNotification, isAgentOrigin, isSkillExpansion, isTranscriptRecord, operatorWords, queuedHumanPrompt } = require('./turn-kind.cjs');
const { gateLabel } = require('./gate-label.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');
const { intents, intentFor } = require('./autonomous-mode.cjs');
const { nativePath } = require('./published-text.cjs');
const { repeatIn, namesEarlier, entries: registerEntries } = require('./refusal-register.cjs');

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
// A surprise the AGENT finds is a mishap too (operator 2026-11-18, translated: "check the cause - why do I always
// have to say it extra?"). Measured that day on the macOS instance: the reply wrote "two of the four are long built"
// and went on to the questions with no cause; the gate fired only on the operator's next message. Its own text
// saying an earlier statement or record was wrong opens the same inquiry. Narrow on purpose: a status line
// ("#600 is merged") is no surprise. Replay 2026-11-18 over 40 transcripts of that instance, German instance data:
// 26 hits of "war falsch / veraltet", each a real self-correction ("my claim from before was wrong").
const BUILTIN_SELF_SURPRISE = [
  // "turned out" alone blocked "the oblique one turned out well" (Windows review 2026-11-18): only with a verdict
  '\\bturned out to be (wrong|false|stale|outdated|already (done|built|merged))\\b',
  '\\b(my|the) (earlier|previous) (claim|count|statement|report|measurement|reading) was (wrong|false|stale)\\b',
  '\\bwas (stale|outdated) all along\\b',
];
// A hook refusing the very step the operator's newest prompt asked for is a surprise of its own (operator 2026-11-23,
// translated: "correcting the entry is not enough - find the cause, fix it at the root, and find out why you do not do
// that on your own when such a fault shows"). Measured that day on the macOS instance: the operator typed "questions now",
// the classifier read asks_open, AUTONOMOUS-GATE refused the question tool twice (17:14:12 and 17:16:15 UTC); the agent
// guessed at the word list, fixed one ledger entry and went on - no inquiry opened. Map: the intent the classifier record
// (or the word lists) read for the prompt -> the tools whose refusal is that surprise; `ignore` = gates whose refusal
// only orders the step (they say what to run first) and is no surprise. Instance override: `refused_intent` in
// root-cause-patterns.json.
const BUILTIN_REFUSED_INTENT = {
  asks_open: { tools: ['AskUserQuestion'], ignore: ['MODE-QUESTION-ORDER', 'QUESTION-GATE', 'MODE-OWED', 'DECISION-REGISTER'] },
};
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
const isFolderMechanism = (p) => MECHANISM_PATH.test(p) && !/\.md$/i.test(p);
// A project repo names its own carriers (operator 2026-11-08, question tool: "Ja, als Kern-PR bauen"; measured that day:
// a project kept its gates and generators in docs/bench/layout/*.py and its rules in .claude/skills/*/SKILL.md, none of
// which the folder list above knew). Data: <repo>/.claude/rules/carrier-paths.json {"carrier_paths": ["glob", ...]},
// globs relative to the repo's git top, `**` any depth, `*` within one folder. A listed file counts even as .md.
const carrierCache = new Map();
function repoCarriers(p) {
  let dir = path.dirname(path.resolve(String(p)));
  for (let i = 0; i < 40; i++) {
    if (carrierCache.has(dir)) return carrierCache.get(dir);
    if (fs.existsSync(path.join(dir, '.git'))) {
      let res = null;
      try {
        const d = JSON.parse(fs.readFileSync(path.join(dir, '.claude', 'rules', 'carrier-paths.json'), 'utf8'));
        const globs = Array.isArray(d.carrier_paths) ? d.carrier_paths.filter((g) => typeof g === 'string' && g) : [];
        const rx = globs.map((g) => new RegExp('^' + g.replace(/[.+^${}()|[\]\\]/g, '\\$&')
          .replace(/\*\*\/?/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\?/g, '[^/]').replace(/\u0000/g, '(?:.*/)?') + '$'));
        res = { top: dir, rx };
      } catch (e) { res = { top: dir, rx: [] }; }
      carrierCache.set(dir, res);
      return res;
    }
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return { top: '', rx: [] };
}
function isMechanismWrite(p) {
  if (isFolderMechanism(p)) return true;
  const { top, rx } = repoCarriers(p);
  if (!top || !rx.length) return false;
  const rel = path.relative(top, path.resolve(String(p))).split(path.sep).join('/');
  return rx.some((r) => r.test(rel));
}
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
const INVARIANT = /^[ \t>*_`-]*invariant:[ \t]*(\S[^\n]{11,})/imu;
const REPLAY_LINE = /^[ \t>*_`-]*replay:[ \t]*(?!pending)([^\n]*)/imu;
// A count, not a date (Windows review of #491: "replay: 2026-11-11, not run yet" passed): dates and clock times are
// removed before the digit test.
// Second Windows review: any other digit passed too ("waits for the v2.1.5 pin", "after 3 sessions"), so a count is a
// number with what it counts (hits, cases, turns, sites, flips) or "<n> of <m>".
// Third read, the train-head review (2026-11-11): that list refused real replay lines of a brain's register
// ("4 own drafts, 3 with the id", "12 transcripts read, 4 blocks", "60 echoes, 47 blocks"). The false passes were a
// version ("v2.1.5") and a span ("after 3 sessions"), so those shapes are removed and any other "<n> <word>" counts.
const COUNT = /\b\d+\s*(?:of\s+\d+|[a-zÀ-ɏ]{2,})/i;
const NOT_A_COUNT = /\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?Z?)?|\b\d{1,2}:\d{2}\b|\bv?\d+(?:\.\d+)+\b|\b(?:after|in|for|since|within|every)\s+\d+\s+\w+/gi;
const hasCount = (line) => COUNT.test(line.replace(NOT_A_COUNT, ''));
// A replay that cannot run yet says so with its reason and the day it is re-checked (root-cause review 2026-11-16:
// "pending", "not run", "open" stood in entries for weeks with no day to come back). `none - <why> - recheck <date>`.
// The word `recheck` stands right before the date (Windows review 2026-11-17: "none - looked once on 2025-01-01"
// passed, any date after twelve characters counted).
const NONE_WITH_RECHECK = /^\s*none\b[\s\S]{4,}?\brecheck\s+\d{4}-\d{2}-\d{2}\b/i;
// A replay over the history, not over the incident (2026-11-23, macOS instance; the operator, translated: "when I point at a
// mistake, check by yourself whether a root-cause inquiry is due and test generic fixes"): 26 of 466 register replays
// counted only the incident's own session or the case itself ("this session: 1 hit (this one)") and passed; 4 of them that
// day. A replay whose ONLY scope is the own session, the current transcript, or the case, needs a second count over a wider
// scope (n of m transcripts, sessions, ledgers, entries, files ...) - or the `none - <why> - recheck <date>` form.
// Instance words for "this session" in another language: `self_only_replay_patterns` (root-cause-patterns.json).
const SELF_SCOPE = /\b(?:this|the current|the own|own) (?:session|transcript|turn|run)\b|\((?:this|it|this one|this case|the case)(?: one| case)?\)|\bonly (?:this|the) (?:case|instance|incident)\b/i;
const WIDE_SCOPE = /\b(?:[2-9]|\d{2,})\s*(?:of\s+\d+\s+)?(?:earlier |other |older |more )?(?:sessions?|transcripts?|ledgers?|registers?|entries|files|commits|prs|repos|brains|months|weeks|days|lines|records|runs)\b/i;
let SELF_EXTRA = null;
let WIDE_EXTRA = null;
const selfOnly = (line) => (SELF_SCOPE.test(line) || (SELF_EXTRA && SELF_EXTRA.test(line)))
  && !WIDE_SCOPE.test(line) && !(WIDE_EXTRA && WIDE_EXTRA.test(line));
const replayOk = (line) => NONE_WITH_RECHECK.test(line) || (hasCount(line) && !selfOnly(line));
// A replay that RAN, not one that is claimed (independent review of the strand, 2026-11-23: "the gate accepts the agent's
// claim that a replay ran" - every check above reads only the wording of a line the agent writes itself). Every number of
// the replay: line must stand in the output of a shell command or an agent that ran in this session; a command that only
// prints text (echo, printf, a heredoc) produces no measurement. The `none - <why> - recheck <date>` form stays the way out.
// PowerShell is the primary shell on Windows (Windows review of #641, 2026-11-24: a replay run there was held as
// "written, not measured"); Write-Output / Write-Host only print, like echo.
const PRINT_ONLY = /^\s*(?:echo|printf|cat\s*<<|true\b|:|write-output|write-host)(?:\s|$)/i;
const SHELL_TOOLS = new Set(['Bash', 'PowerShell']);
function sessionRuns(transcriptPath) {
  const cmds = new Map();
  const outs = [];
  let text = '';
  try { text = fs.readFileSync(transcriptPath, 'utf8'); } catch (e) { return outs; }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const content = d.message && Array.isArray(d.message.content) ? d.message.content : [];
    for (const b of content) {
      if (b.type === 'tool_use' && b.id) {
        const inp = b.input || {};
        if (SHELL_TOOLS.has(b.name) && typeof inp.command === 'string') cmds.set(b.id, PRINT_ONLY.test(inp.command) ? null : inp.command);
        else if (b.name === 'Agent' || b.name === 'Task') cmds.set(b.id, 'agent');
      }
      if (b.type === 'tool_result' && b.tool_use_id && cmds.get(b.tool_use_id)) {
        const c = b.content;
        outs.push(typeof c === 'string' ? c : Array.isArray(c) ? c.map((x) => (x && x.text) || '').join('\n') : '');
      }
    }
  }
  return outs;
}
function replayRan(line, outs) {
  if (NONE_WITH_RECHECK.test(line)) return true;
  const nums = String(line).replace(NOT_A_COUNT, ' ').match(/\d+(?:[.,]\d+)?/g) || [];
  if (!nums.length) return false;
  // all numbers of the line in ONE output: one run measured them together (a lone "1" stands in almost any output -
  // measured 2026-11-23: per-number matching let 278 of 292 historic replay lines pass)
  const has = (o, n) => new RegExp(`(^|[^\\d.,])${n.replace(/[.,]/g, '[.,]')}(?![\\d])`).test(o);
  return outs.some((o) => nums.every((n) => has(o, n)));
}
// A PR or issue number names the instance; a core rule number ("Working Rule #10") is the rule itself (same review).
const INSTANCE_WORD = /[\\/][\w.-]+\.\w{1,5}\b|\b(?:PR|issue|pull)s?\s*#?\d+\b|\b[\w.-]+#\d+\b|(?:^|[\s(])#\d{3,}\b|\b\w+\.(cjs|js|py|sh|json|md)\b/iu;
function newestEntry(all) {
  const h = all.lastIndexOf('\n## ');
  if (h >= 0) return all.slice(h + 1);
  // no `## ` headings (same review, finding 3): the last blank-line-separated block, never the whole file
  const blocks = all.trim().split(/\n[ \t]*\n/);
  return blocks[blocks.length - 1] || '';
}
/** The `## ` entry on disk that holds an edit's text, or '' (no heading above it, or the text is not on disk). */
function entryAround(file, piece) {
  const all = '\n' + file; // a heading on the first line counts
  const t = String(piece || '').trim();
  const i = t ? all.indexOf(t) : -1;
  const start = i < 0 ? -1 : all.lastIndexOf('\n## ', i);
  if (start < 0) return '';
  const end = all.indexOf('\n## ', i + t.length);
  return all.slice(start + 1, end < 0 ? undefined : end);
}
function entryGaps(writeTexts, rel, forbidden, cwd, transcriptPath) {
  const mine = writeTexts.filter((w) => writesTo([w.p], rel));
  let text = mine.map((w) => w.t).join('\n');
  let disk = null;
  try { disk = fs.readFileSync(path.join(cwd, rel), 'utf8'); } catch (e) { /* unreadable: the edit text alone */ }
  // Written without a text in the transcript (a shell append): judge the newest entry on disk.
  if (!text.trim()) text = disk ? newestEntry(disk) : '';
  // An edit that completes an entry of an earlier turn (only its `replay:` line, say) is judged with the entry it
  // lands in (Windows review of #491, finding 4).
  else if (disk) text += '\n' + mine.map((w) => entryAround(disk, w.t)).join('\n');
  const inv = INVARIANT.exec(text);
  const gaps = [];
  if (!inv) gaps.push('the register entry names no invariant:');
  else if (INSTANCE_WORD.test(inv[1]) || forbidden.test(inv[1])) gaps.push('the invariant: names the instance (a path, a number, a proper noun) - say the rule, not the case');
  const rep = REPLAY_LINE.exec(text);
  try { SELF_EXTRA = loadPatterns(cwd, 'self_only_replay_patterns', ['(?!)'], 'iu'); } catch (e) { SELF_EXTRA = null; }
  try { WIDE_EXTRA = loadPatterns(cwd, 'wide_scope_replay_patterns', ['(?!)'], 'iu'); } catch (e) { WIDE_EXTRA = null; }
  if (rep && hasCount(rep[1]) && selfOnly(rep[1])) gaps.push('the replay: counts only the incident\'s own session or the case '
    + 'itself - replay the detector over the history (a count over n transcripts, sessions, ledgers ...), or '
    + '"none - <why> - recheck <YYYY-MM-DD>" when it cannot run yet');
  else if (!rep || !replayOk(rep[1])) gaps.push('the register entry has no replay: count (a date is no count; '
    + '"none - <why> - recheck <YYYY-MM-DD>" when it cannot run yet)');
  else if (transcriptPath && !replayRan(rep[1], sessionRuns(transcriptPath))) gaps.push('the replay: count was written, not '
    + 'measured - no command or agent of this session printed it; run the detector over the history (a script, the gate\'s '
    + '--review, a search) and copy its count, or write "none - <why> - recheck <YYYY-MM-DD>"');
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
        if (b.type === 'tool_use') (cur.calls = cur.calls || []).push({ id: b.id, name: b.name, input: b.input || {} });
        if (b.type === 'tool_use' && b.input && typeof b.input.file_path === 'string') {
          cur.writes.push(b.input.file_path);
          (cur.writeTexts = cur.writeTexts || []).push({ p: b.input.file_path, t: String(b.input.new_string || b.input.content || '') });
        }
        // A file written by a shell command (`cat x >> register.md`, a script) carries no file_path: keep the command, the
        // judge reads the paths it names and checks they changed in this turn (shellWrites below).
        if (b.type === 'tool_use' && b.input && typeof b.input.command === 'string') (cur.shell = cur.shell || []).push(b.input.command);
      }
      continue;
    }
    if (msg.role !== 'user') continue;
    // A hook's refusal of a tool call (PreToolUse deny): kept with the tool and the refusing text, so a refusal of the
    // very step the operator's newest prompt asked for opens the inquiry (refusedAsk below).
    if (cur && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (!b || b.type !== 'tool_result') continue;
        const txt = Array.isArray(b.content) ? b.content.map((x) => (x && x.text) || '').join(' ') : String(b.content || '');
        (cur.results = cur.results || {})[b.tool_use_id] = { err: Boolean(b.is_error), text: txt.slice(0, 4000) };
        if (!b.is_error) continue;
        const m = /^(?:PreToolUse|PostToolUse):(\S+) hook error:\s*(?:\[[^\]]*\]:\s*)?([\s\S]*)$/.exec(txt.trim());
        if (m) (cur.refusals = cur.refusals || []).push({ tool: m[1], text: m[2], raw: txt.trim(), at: d.timestamp || '' });
      }
    }
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
    shell: group.flatMap((t) => t.shell || []), since: Date.parse((group[0] && group[0].when) || '') || 0,
  };
}

// Files a shell command of the turn names that exist and changed since the turn began. Measured 2026-11-08 on the macOS
// instance: a register entry appended with `cat … >> docs/maintenance/carrier-register.md` and a generator rewritten by a
// python script were both invisible - the gate read only Write/Edit file paths and reported "no entry" three times.
function shellWrites(shell, cwd, since) {
  if (!since) return [];
  const out = [];
  // A path starts with ~, /, ./, ../ or a drive (C:/, C:\ - Windows review 2026-11-12); a quoted one may hold spaces.
  // nativePath: a Git Bash `/c/...` is no path node can stat on Windows (docs/os-traps.md OS-19).
  const lead = '(?:~|[A-Za-z]:[\\\\/]|\\/|\\.{0,2}\\/)?';
  // `~` inside a segment too: Windows writes the user folder as its 8.3 name (`RUNNER~1`, docs/os-traps.md OS-8) -
  // without it the match ended before the `~` of `<home>` (portability windows-latest, train #510, 2026-11-12)
  const bare = new RegExp(`(?:^|[\\s"'=<>|;&(])(${lead}[\\w.~@+-]+(?:[\\\\/][\\w.~@+-]+)+)`, 'g');
  const quoted = new RegExp(`(["'])(${lead}[^"'\\n]*?[\\\\/][^"'\\n]*?)\\1`, 'g');
  for (const cmd of shell) {
    const found = [...String(cmd).matchAll(bare)].map((m) => m[1]).concat([...String(cmd).matchAll(quoted)].map((m) => m[2]));
    for (const raw of found) {
      const p = nativePath(raw.replace(/^~(?=[\\/])/, process.env.HOME || process.env.USERPROFILE || '~'));
      const abs = path.isAbsolute(p) ? p : path.join(cwd, p);
      try { if (fs.statSync(abs).mtimeMs >= since - 1000) out.push(abs); } catch (e) { /* not a file */ }
    }
  }
  return out;
}

// The first correction in the turn that no later text answers with a cause line; with causeRx null, the first
// correction regardless (the --pre check wants the class before the instance even when a cause is already named).
// A prompt classifier's record of the prompt DECIDES, both ways; without one the word list does (operator decision
// 2026-11-18, question tool, superseding "safe direction only" of 2026-10-30: in a hand-judged sample of 40
// disagreements the model was right in 30, the words in 7 - every word hit there was a false alarm).
function firstCorrection(group, cwd, transcriptPath, rx, causeRx) {
  let known = null;
  for (let i = 0; i < group.length; i += 1) {
    const seg = group[i];
    let hit = correctionIn(seg.prompt, rx);
    if (!known) known = intents(transcriptPath, cwd);
    const intent = intentFor(known, seg.when, seg.prompt);
    if (intent && typeof intent.correction === 'boolean') {
      hit = intent.correction ? hit || sentenceAt(stripQuoted(seg.prompt), 0) : null;
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

/** The malfunction data (gate-malfunction.json at the core root, shared with scripts/gate-health.py). */
let MALF = null;
function malfData() {
  if (MALF) return MALF;
  try {
    const d = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'gate-malfunction.json'), 'utf8'));
    MALF = { refusal: new RegExp(d.refusal), malf: new RegExp((d.malfunction || []).join('|')), gate: new RegExp(d.gate) };
  } catch (e) { MALF = { refusal: /(?!)/, malf: /(?!)/, gate: /(?!)/ }; }
  return MALF;
}
/** A gate malfunction in the turn - a refusal that is no decision (timed out, crashed): "<gate> <what> at <time>" or null.
 *  2026-11-23 (operator, translated: "the fixes must make further cases visible on historic data, else they are micro
 *  solutions"): over the 60 newest transcripts of the macOS instance, 45 such refusals and no reply named a cause. */
function malfunctionIn(group) {
  const m = malfData();
  for (const seg of group) {
    for (const r of seg.refusals || []) {
      const full = r.raw || `PreToolUse:${r.tool} hook error: ${r.text}`;
      if (!m.refusal.test(full) || !m.malf.test(full)) continue;
      const gate = gateLabel(r.raw || r.text);
      const what = (m.malf.exec(r.raw || r.text) || [''])[0];
      return `${gate} ${what} on ${r.tool} at ${r.at || '?'}`;
    }
  }
  return null;
}

/**
 * ANOMALY SIGNALS of a turn, read from its tool results (operator 2026-11-23, translated: "the deeper level is that once
 * a not-optimal behaviour shows, you recognise and improve it on your own ... today it happened neither by itself nor on
 * my hint"). Each signal the turn's text must CLASSIFY in one line - `Anomaly: <what> - intended | gate false positive
 * (then a register entry or a fix) | own mistake (then a Cause line)`:
 *   own-fail   the agent's own command failed in a way no plan intends (a Traceback, "command not found", exit 127, a
 *              JSON parse error) - blocks
 *   repeat     the same gate refused twice in the turn - counted by the replay (--anomalies), no hold
 *   bypass     a refusal, then the same intent passing in another form within 8 calls, with no marker (same tool; Bash:
 *              Jaccard >= 0.5 of the command's words; files: the same path) - counted by the replay, no hold
 *   marker-pass a refusal, then the same intent passing by a `# MARKER` - holds until classified with its backing
 * A gate malfunction is the fourth signal; it opens the cause path above (malfunctionIn).
 */
const OWN_FAIL = /Traceback \(most recent call last\)|: command not found\b|is not recognized as (?:an internal or external command|the name of a cmdlet)|\bExit code 127\b|JSONDecodeError|Unexpected token [^\n]{0,40} in JSON|is not valid JSON|Unexpected end of JSON input/;
// A marker the gate asks for: `# WORD-OK: …` or `# WORD-WORD: …` (CONDITION-NONE, PRS-READ, OVERLAP-OK), in the call.
const MARKER = /#\s*[A-Z][A-Z]+(?:-[A-Z]+)*(?:-OK\b|:)/;
const BUILTIN_ANOMALY = ['^[ \\t>*_-]*(anomaly|signal)\\b[^\\n]{0,80}:[^\\n]*\\b(intended|false positive|own mistake)\\b'];
const WINDOW = 8;
// A refusal that names its own way on: the form that passes, a repeat, a skill to load, a marker, a step first.
// The built-ins and the gate-to-marker map live in ONE data file at the core root, gate-markers.json, read here and by
// scripts/gate-health.py (main session decision 2026-11-23: one reader, not a second list). Other languages as
// instance data (`way_on_patterns` in root-cause-patterns.json).
let MARKER_DATA = null;
function markerData() {
  if (MARKER_DATA) return MARKER_DATA;
  try { MARKER_DATA = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'gate-markers.json'), 'utf8')); } catch (e) { MARKER_DATA = {}; }
  return MARKER_DATA;
}
const WAY_ON_BUILTIN = (markerData().way_on || []).filter((x) => { try { new RegExp(x); return true; } catch (e) { return false; } });
/** Is a marker one a gate names as its RULE PATH (a step done, a fact checked)? Then passing by it is the gate followed
 *  and owes no classification; an exception marker (rule_path false) or one no gate entry names does. */
function rulePathMarker(name) {
  return Object.values(markerData().gates || {}).some((g) => g && g.rule_path === true && (g.markers || []).includes(name));
}
const STEP_TOOLS = new Set(['Skill', 'Read', 'ToolSearch']);
function callKey(c) {
  const inp = c.input || {};
  if (typeof inp.file_path === 'string') return { file: inp.file_path };
  if (typeof inp.command === 'string') return { words: new Set(inp.command.replace(/#.*$/gm, '').match(/[\w./-]{3,}/g) || []) };
  return { raw: JSON.stringify(inp).slice(0, 200) };
}
function sameIntent(a, b) {
  if (a.file !== undefined || b.file !== undefined) return a.file === b.file && Boolean(a.file);
  if (a.words && b.words) {
    let n = 0; for (const w of a.words) if (b.words.has(w)) n += 1;
    const u = new Set([...a.words, ...b.words]).size;
    return u > 0 && n / u >= 0.5;
  }
  return a.raw === b.raw;
}
function anomalies(group, cwd) {
  const out = [];
  const m = malfData();
  const WAY_ON = loadPatterns(cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd(), 'way_on_patterns', WAY_ON_BUILTIN, 'iu');
  for (let si = 0; si < group.length; si += 1) {
    const seg = group[si];
    const calls = seg.calls || []; const res = seg.results || {};
    const gatesSeen = {};
    for (let i = 0; i < calls.length; i += 1) {
      const c = calls[i]; const r = res[c.id];
      const at = { seg: si, call: i };   // where the signal starts: what may back its classification lies before it
      if (!r || !r.err) continue;
      const refusal = m.refusal.test(r.text.trim());
      if (!refusal) {
        const f = OWN_FAIL.exec(r.text);
        if (f && c.name === 'Bash') out.push({ kind: 'own-fail', block: true, at, what: `${f[0]} in: ${String(c.input.command || '').slice(0, 80)}` });
        continue;
      }
      if (m.malf.test(r.text)) continue;   // malfunctions go the cause path
      const gate = gateLabel(r.text);   // one reader for the label (helpers/gate-label.cjs)
      gatesSeen[gate] = (gatesSeen[gate] || 0) + 1;
      if (gatesSeen[gate] === 2) out.push({ kind: 'repeat', block: false, gate, what: `${gate} refused twice in the turn` });
      const k = callKey(c);
      const named = WAY_ON.test(r.text);
      for (let j = i + 1; j < Math.min(calls.length, i + 1 + WINDOW); j += 1) {
        const c2 = calls[j]; const r2 = res[c2.id];
        if (c2.name !== c.name || !r2 || r2.err) continue;
        if (!sameIntent(k, callKey(c2))) continue;
        // A refusal passed by a marker is classified like any anomaly (rule "a gate that errs is a finding": a marker is
        // a judgement against the gate or a step the gate asked for - the line says which, and what backs it).
        const mk = MARKER.exec(JSON.stringify(c2.input));
        if (mk) {
          const name = mk[0].replace(/^#\s*/, '').replace(/:$/, '');
          // a rule-path marker (PRS-READ: the reading the gate asks for) is the gate followed; an exception marker
          // (MECHANISM-OK, CONDITION-NONE) or one no gate names holds until classified (main session 2026-11-23)
          if (rulePathMarker(name)) {
            out.push({ kind: 'followed', block: false, gate, what: `${gate} refused ${c.name}, its rule-path marker ${name} was given` });
          } else {
            out.push({ kind: 'marker-pass', block: true, gate, marker: name, at, what: `${gate} refused ${c.name}, passed by its marker # ${name}` });
          }
          break;
        }
        // The gate's own way on is no bypass (Windows review of #640: most of 84 bypass signals were a skill load and the
        // repeat, or the form the refusal named): the refusal names a way on, the same call repeats unchanged, or a
        // step the gate asks for (a skill load, a read) came in between.
        const between = calls.slice(i + 1, j);
        const followed = named || JSON.stringify(c2.input) === JSON.stringify(c.input) || between.some((b) => STEP_TOOLS.has(b.name));
        out.push({ kind: followed ? 'followed' : 'bypass', block: false, gate, what: followed
          ? `${gate} refused ${c.name}, its way on was taken` : `${gate} refused ${c.name}, the same intent passed in another form` });
        break;
      }
    }
  }
  return out;
}
/**
 * The turn's classification of its anomalies - and whether it is BACKED (independent review of the strand,
 * 2026-11-23: a bare "Anomaly: x - intended" released the hold with nothing behind it, the "Carrier: none" escape of
 * 2026-11-02 again). `group` = the turn's segments (readTurns), `ctx` = {texts, writes} of the combined turn.
 *   intended        backed by what it quotes, found where the agent cannot write it after the fact (second review of
 *                   the strand, 2026-11-23: quoting the failed command itself, an own "Plan:" line, the marker just
 *                   used or a word of the refused call all passed): in the operator's prompt of the turn, or in the
 *                   input of a call made BEFORE the signal's call. Never the signal's own call, a later call, or the
 *                   agent's own text; a marker pass is never backed by its own marker.
 *   false-positive  backed by an entry written to the carrier register in the same turn
 *   own-mistake     backed by a cause line (that line opens the cause path, which owes the carrier and the entry)
 * `signal` = the anomaly ({kind, at: {seg, call}, marker}); without it no earlier call is known and only the
 * operator's prompt can back an "intended".
 * Returns {kind, backed, missing, line}; kind null when no classification line stands.
 */
function classification(group, cwd, ctx, signal) {
  const texts = (ctx && ctx.texts) || group.flatMap((s) => s.texts || []);
  const writes = (ctx && ctx.writes) || group.flatMap((s) => s.writes || []);
  const rx = loadPatterns(cwd, 'anomaly_patterns', BUILTIN_ANOMALY, 'imu');
  let line = '';
  for (const t of texts) {
    const m = new RegExp(rx.source, 'imu').exec(stripQuoted(t));
    if (m) { line = (t.split('\n').find((l) => new RegExp(rx.source, 'iu').test(l)) || m[0]).trim(); break; }
  }
  if (!line) return { kind: null, backed: false, missing: 'a classification line', line: '' };
  const kind = /own mistake/i.test(line) ? 'own-mistake' : /false positive/i.test(line) ? 'false-positive' : 'intended';
  if (kind === 'false-positive') {
    const reg = registerPath(cwd);
    return writesTo(writes, reg) ? { kind, backed: true, missing: '', line }
      : { kind, backed: false, missing: `an entry in ${reg} written in this turn (the false positive's cause and fix)`, line };
  }
  if (kind === 'own-mistake') {
    return causeIn(texts, loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu')) ? { kind, backed: true, missing: '', line }
      : { kind, backed: false, missing: 'a Cause line (what was read, what produced it)', line };
  }
  const quoted = [...line.matchAll(/`([^`]{3,})`|"([^"]{8,})"|“([^”]{8,})”|#\s*([A-Z][A-Z]+(?:-[A-Z]+)+)/g)]
    .map((q) => (q[1] || q[2] || q[3] || q[4] || '').trim()).filter(Boolean);
  const at = signal && signal.at;
  // a call a hook refused carried nothing out - its words back nothing (second review, P2: a repeat classified by
  // quoting the refused question itself passed)
  const refusedForm = malfData().refusal;
  const refusedCall = (s, c) => { const r = (s.results || {})[c.id]; return Boolean(r && r.err && refusedForm.test(String(r.text || '').trim())); };
  const earlier = at ? group.flatMap((s, si) => (s.calls || []).filter((c, ci) => (si < at.seg || (si === at.seg && ci < at.call)) && !refusedCall(s, c))
    .map((c) => JSON.stringify(c.input || {}))) : [];
  const prompts = group.map((s) => String(s.prompt || '')).filter(Boolean);
  const own = signal && signal.kind === 'marker-pass' && signal.marker ? signal.marker : null;
  const found = quoted.find((q) => q !== own && (prompts.some((p) => p.includes(q)) || earlier.some((i) => i.includes(q))));
  return found ? { kind, backed: true, missing: '', line }
    : { kind, backed: false, missing: 'what the "intended" refers to, quoted from the operator\'s prompt or a call made before it (not the failing call, a later call or your own text; a marker never backs itself)', line };
}

/** A refusal of this turn that the carrier register already knows for the same gate and tool (refusal-register.cjs):
 *  a REPEAT - the earlier entry's fix did not hold, or is not in force. null when the register has no earlier entry. */
function registerRepeat(group, cwd) {
  let aliases = null;
  try { aliases = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'root-cause-patterns.json'), 'utf8')).refusal_aliases || null; } catch (e) { aliases = null; }
  let reg = '';
  try { reg = fs.readFileSync(path.join(cwd, registerPath(cwd)), 'utf8'); } catch (e) { return null; }
  const refusals = [];
  group.forEach((seg, si) => { for (const r of seg.refusals || []) refusals.push({ ...r, at: r.at || seg.when || '', seg: si }); });
  const rep = repeatIn(refusals, reg, aliases);
  if (!rep) return null;
  // Where the refused call stands in the turn (segment, call index): the classification's judge takes it as the
  // signal's place, so that nothing of the refused call itself - or of a later one - can back an "intended".
  const seg = group[rep.refusal.seg] || {};
  const raw = String(rep.refusal.raw || '').slice(0, 200);
  const call = (seg.calls || []).findIndex((c) => c.name === rep.tool && (seg.results || {})[c.id]
    && seg.results[c.id].err && String(seg.results[c.id].text || '').trim().startsWith(raw));
  rep.pos = { seg: rep.refusal.seg, call: call < 0 ? 0 : call };
  return rep;
}

/** Records a register repeat (.claude-state/register-repeats.jsonl: at, session, gate, tool, the earlier entries) and
 *  says whether this session was already held for that gate and tool. The record is the measurement behind an entry's
 *  `effective:` - a fix whose refusal keeps coming back is not in force. Best effort: unwritable = not seen. */
function recordRepeat(cwd, input, rep) {
  const f = path.join(cwd, '.claude-state', 'register-repeats.jsonl');
  const sid = String(input.session_id || '');
  let seen = false;
  try {
    seen = Boolean(sid) && fs.readFileSync(f, 'utf8').split('\n').some((l) => {
      try { const d = JSON.parse(l); return d.session === sid && d.gate === rep.gate && d.tool === rep.tool; } catch (e) { return false; }
    });
  } catch (e) { seen = false; }
  try {
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.appendFileSync(f, JSON.stringify({ at: new Date().toISOString(), session: sid, gate: rep.gate, tool: rep.tool,
      earlier: rep.hits.map((h) => h.id || h.date), held: !seen }) + '\n');
  } catch (e) { /* recording is best effort */ }
  return seen;
}

/** A refusal in the turn of the step the operator's prompt asked for: "<GATE> refused <tool> ..." or null. The prompt's
 *  intent comes from the classifier record, else from the word lists of autonomous-mode.cjs (asks_open only). */
function refusedAsk(group, cwd, transcriptPath) {
  let map = BUILTIN_REFUSED_INTENT;
  try {
    const inst = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'root-cause-patterns.json'), 'utf8')).refused_intent;
    if (inst && typeof inst === 'object') map = Object.assign({}, map, inst);
  } catch (e) { /* built-ins */ }
  let known = null; let am = null;
  try { am = require('./autonomous-mode.cjs'); } catch (e) { am = null; }
  for (const seg of group) {
    if (!seg.refusals || !seg.refusals.length) continue;
    if (!known) known = intents(transcriptPath, cwd);
    const intent = intentFor(known, seg.when) || {};
    for (const [name, rule] of Object.entries(map)) {
      let read = intent[name] === true ? 'the intent classifier record' : null;
      if (!read && name === 'asks_open' && am) { try { if (am.words(cwd).ask.test(seg.prompt)) read = 'the word lists'; } catch (e) { /* none */ } }
      if (!read) continue;
      for (const r of seg.refusals) {
        if (!(rule.tools || []).includes(r.tool)) continue;
        const gateName = gateLabel(r.raw || r.text);
        if ((rule.ignore || []).includes(gateName)) continue;
        return `${gateName} refused ${r.tool} at ${r.at || '?'}, the step the operator's prompt asked for ("${seg.prompt.slice(0, 60)}", ${name} read by ${read})`;
      }
    }
  }
  return null;
}

/** A sentence of the agent's own text that says an earlier statement or record was wrong; quotes and code stripped. */
function selfSurprise(texts, rx) {
  for (const t of texts || []) {
    const clean = stripQuoted(String(t || ''));
    const m = rx.exec(clean);
    if (m) return sentenceAt(clean, m.index);
  }
  return null;
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
  const { group, texts, writes: direct, fired, fires, preEcho, writeTexts, shell, since } = currentTurn(turns);
  if (!group.length) return;
  const writes = direct.concat(shellWrites(shell, cwd, since));
  // The prompt classifier's record decides too (2026-10-30, macOS instance: "find the cause and fix it at the root",
  // in the operator's language, passed the word list; the classifier read correction=true). Since 2026-11-18 a record of
  // the prompt decides both ways (firstCorrection); no record = the words. Every message of the turn is judged (currentTurn), a
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
  // A register entry is judged whenever it is written, not only in the turn that names the cause (root-cause review
  // 2026-11-16, class "instance fixed, class never searched": entries written in a later turn or taken over from a
  // delegated agent kept "replay: pending" for weeks - the check ran only behind `if (cause)`). One block per turn.
  if (!cause && !fired) {
    const reg = registerPath(cwd);
    const gaps = writesTo(writes, reg)
      ? entryGaps(writeTexts, reg, loadPatterns(cwd, 'invariant_forbidden', ['(?!)'], 'iu'), cwd, input.transcript_path) : [];
    if (gaps.length) {
      process.stdout.write(JSON.stringify(declare({
        decision: 'block',
        reason: `ROOT-CAUSE-GATE: this turn writes ${reg} - ${gaps.join(', ')}. An entry is a class entry: invariant `
          + '(the broken rule without the instance\'s names) and replay (the invariant run over the history, with its '
          + 'count; when it cannot run yet: "none - <why> - recheck <YYYY-MM-DD>"). Complete the entry, then end the turn.',
      }, input)));
      return;
    }
  }
  if (cause) {
    const reg = registerPath(cwd);
    const mech = writes.some(isMechanismWrite)
      || noCarrierAgreed(texts, loadPatterns(cwd, 'nocarrier_patterns', BUILTIN_NOCARRIER, 'imu'), turns);
    const registered = writesTo(writes, reg);
    const gaps = registered ? entryGaps(writeTexts, reg, loadPatterns(cwd, 'invariant_forbidden', ['(?!)'], 'iu'), cwd, input.transcript_path) : [];
    if (mech && registered && !gaps.length) return;
    const missing = [!mech && 'no mechanism written', !registered && `no entry in ${reg}`, ...gaps].filter(Boolean).join(', ');
    process.stdout.write(JSON.stringify(declare({
      decision: 'block',
      reason: `ROOT-CAUSE-GATE: this turn names a cause - ${missing}${fired ? ' (the cause came after the first block; naming it does not release the carrier)' : ''}. Fixing the instance (a re-post, a manual merge, a `
        + 'ledger or memory note) leaves the tool that let it happen as it was. Before this turn ends: change the '
        + 'producing tool or gate data (helpers/, scripts/, hooks/, rule JSON - a core or suite PR where the tool '
        + 'lives, or a path the repo lists in .claude/rules/carrier-paths.json) with a fixture. "Carrier: none" releases only with the operator\'s words on the same line, '
        + 'operator-ok: "<their words>", found in their own messages - never on the agent\'s say-so; AND write the entry in '
        + `${reg}: incident, cause, invariant (the broken rule without the instance's names), effect, carrier (or none + `
        + 'reason + recheck date), related cases, replay (the invariant run over the history, with its count), '
        + 'found-by (operator | work | ci | <the check that found it>; when not a check: should-have: <the check that should have>).',
    }, input)));
    return;
  }
  const self = hit || fired ? null : selfSurprise(texts, loadPatterns(cwd, 'self_surprise_patterns', BUILTIN_SELF_SURPRISE, 'iu'));
  let refused = null; let malf = null;
  if (!hit && !self && !fired) { try { refused = refusedAsk(group, cwd, input.transcript_path); } catch (e) { refused = null; } }
  if (!hit && !self && !refused && !fired) { try { malf = malfunctionIn(group); } catch (e) { malf = null; } }
  if (!hit && !self && !refused && !malf) {
    if (fired) return;
    let list = [];
    try { list = anomalies(group, cwd); } catch (e) { list = []; }
    // A refusal the carrier register already holds for the same gate and tool is a REPEAT (2026-11-23: the third
    // "the operator asks for the questions, the question tool is refused" was handled as a first case). Every repeat
    // is recorded; it holds the turn ONCE per session for a gate and tool (the replay: 178 such turns in 605
    // transcripts, 62 of them one ordering gate - asked at every hit the line becomes ritual), until the turn's
    // classification is BACKED (classification above - the one judge; independent review 2026-11-23: a bare
    // "intended" released the hold).
    let rep = null;
    try { rep = registerRepeat(group, cwd); } catch (e) { rep = null; }
    if (rep && !recordRepeat(cwd, input, rep)) list.unshift({ kind: 'register-repeat', block: true, what: rep.what, hits: rep.hits, at: rep.pos });
    const own = list.find((a) => a.block);
    if (!own) return;
    const cls = classification(group, cwd, { texts, writes }, own);   // the signal: its kind and the place of its call
    let missing = cls.backed ? '' : (cls.kind ? cls.missing : 'a classification line');
    if (!missing && own.kind === 'register-repeat' && cls.kind === 'false-positive') {
      // the new entry ties the case to the earlier one: `related: none` on a third case was the 2026-11-18 defect
      const reg = registerPath(cwd);
      let written = writeTexts.filter((w) => writesTo([w.p], reg)).map((w) => w.t).join('\n');
      if (!written.trim()) { try { written = newestEntry(fs.readFileSync(path.join(cwd, reg), 'utf8')); } catch (e) { written = ''; } }
      if (!namesEarlier(written, own.hits)) {
        missing = `the new register entry names the earlier one under related: (${own.hits.slice(-3).map((h) => h.id || h.date).join(', ')})`;
      }
    }
    if (!missing) return;
    if (own.kind === 'register-repeat') {
      process.stdout.write(JSON.stringify(declare({
        decision: 'block',
        reason: `ROOT-CAUSE-GATE: a REPEAT - ${own.what.slice(0, 520)}. A refusal the register already knows is no first case`
          + (cls.kind ? ` - your line "${cls.line.slice(0, 100)}" reads as ${cls.kind}, missing: ${missing}. ` : '. ')
          + 'Classify it in ONE line, with its backing - Anomaly: <gate> refused <tool> again - intended (quote the '
          + '`# MARKER` or the plan line the call followed, standing in this turn) | gate false positive (and write its '
          + 'entry in the carrier register in this turn: `refusal: <GATE> <Tool>`, `related:` naming the earlier entry, '
          + 'and `effective: no - <why>` on that earlier entry - read whether its carrier is IN FORCE here; a pull request '
          + 'that is open, or merged but not pinned, is no fix) | own mistake (and a Cause line: why the refused step was '
          + 'tried again). A bare word releases nothing.',
      }, input)));
      return;
    }
    process.stdout.write(JSON.stringify(declare({
      decision: 'block',
      reason: `ROOT-CAUSE-GATE: an anomaly in this turn's tool results is not classified with its backing: ${own.kind} - "${own.what.slice(0, 160)}"`
        + (cls.kind ? ` - your line "${cls.line.slice(0, 100)}" reads as ${cls.kind}, missing: ${cls.missing}. ` : '. ')
        + 'Classify it in ONE line - Anomaly: <what> - intended (quote the `# MARKER` or the plan line it follows, standing in this turn) | '
        + 'gate false positive (and write its entry in the carrier register in this turn) | own mistake (and a Cause line: '
        + 'what was read, what produced it). A bare word releases nothing (operator 2026-11-23: "recognise and improve it on your own").',
    }, input)));
    return;
  }
  const what = hit ? 'an operator message in this turn reads as a correction or a mishap'
    : self ? 'your own text in this turn finds a mishap'
      : refused ? 'a hook refused the very step the operator asked for (name the refusing gate, the reader and the measured value that decided)'
        : 'a hook MALFUNCTIONED in this turn - a refusal that is no decision (name the gate and what was measured: its run time, its exit, what it read)';
  let known = '';
  if (refused || malf) {
    try { const rep = registerRepeat(group, cwd); if (rep) known = `A REPEAT - ${rep.what.slice(0, 420)}; say why that fix did not hold (an open pull request is no fix). `; } catch (e) { known = ''; }
  }
  process.stdout.write(JSON.stringify(declare({
    decision: 'block',
    reason: `ROOT-CAUSE-GATE: ${what}: "${(hit || self || refused || malf).slice(0, 200)}". ${known}`
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
  // A fix that is a pull request or a branch is a fix only once it runs (2026-11-23, macOS instance: an entry's carrier
  // was a pull request open for five days; the incident came back on the unfixed state and nothing said so).
  const parsed = registerEntries(regText);
  const unstated = parsed.filter((e) => !e.effective && /\bpull request\b|\bPRs?\b|#\d{2,}|\b(?:fix|feat|chore)\/[\w.-]+/i.test(e.carrier));
  const notInForce = parsed.filter((e) => /^no\b/i.test(e.effective));
  console.log(`\n## Carriers that are a pull request or a branch: effect not stated ${unstated.length} · stated not in force ${notInForce.length}\n`);
  for (const e of notInForce) console.log(`- not in force: ${e.date} ${e.id || e.title.slice(0, 60)} - ${e.effective.slice(0, 100)}`);
  for (const e of unstated.slice(-20)) console.log(`- effect not stated: ${e.date} ${e.id || e.title.slice(0, 60)}`);
  console.log('\n## Turns that named a cause and wrote no mechanism (newest 40)\n');
  for (const x of causeNoMechList.sort().slice(-40)) console.log(`- ${x}`);
  console.log('\n## Corrections whose reply named a cause\n');
  for (const x of found.filter((y) => y.cause)) {
    console.log(`- ${x.when} ${x.session} ${x.carrier ? '(mechanism written later)' : ''}: "${x.hit.replace(/\s+/g, ' ').slice(0, 140)}"`);
  }
  return 0;
}

// --claimed-replays <dir|transcript...>: every register `replay:` line a session wrote, and whether a command or an agent of
// that session printed its count (the replay of the 2026-11-23 "measured, not claimed" rule; prints its counts).
function claimedReplays(args) {
  const files = [];
  for (const a of args) {
    try {
      if (fs.statSync(a).isDirectory()) for (const f of fs.readdirSync(a)) { if (f.endsWith('.jsonl')) files.push(path.join(a, f)); }
      else files.push(a);
    } catch (e) { /* skip */ }
  }
  let lines = 0; let ran = 0; let none = 0; const sessions = new Set(); const claimed = []; const seen = new Set();
  for (const f of files) {
    let text = ''; try { text = fs.readFileSync(f, 'utf8'); } catch (e) { continue; }
    if (!text.includes('carrier-register')) continue;
    let outs = null;
    for (const l of text.split('\n')) {
      if (!l.includes('carrier-register') || !l.includes('replay:')) continue;
      let d; try { d = JSON.parse(l); } catch (e) { continue; }
      for (const b of (d.message && Array.isArray(d.message.content) ? d.message.content : [])) {
        if (b.type !== 'tool_use' || !b.input) continue;
        const target = String(b.input.file_path || b.input.command || '');
        if (!/carrier-register/.test(target)) continue;
        const body = String(b.input.new_string || b.input.content || b.input.command || '');
        const m = REPLAY_LINE.exec(body);
        if (!m || !hasCount(m[1]) && !NONE_WITH_RECHECK.test(m[1])) continue;
        const key = path.basename(f) + m[1];
        if (seen.has(key)) continue;
        seen.add(key);
        lines += 1;
        if (NONE_WITH_RECHECK.test(m[1])) { none += 1; continue; }
        if (!outs) outs = sessionRuns(f);
        if (replayRan(m[1], outs)) ran += 1;
        else { sessions.add(path.basename(f)); claimed.push(`${path.basename(f).slice(0, 8)} ${d.timestamp || ''}: ${m[1].slice(0, 110)}`); }
      }
    }
  }
  console.log(`claimed-replays: ${files.length} transcripts · ${lines} replay lines with a count · ${ran} printed by a run of the session · ${none} none-with-recheck · ${claimed.length} claimed only, in ${sessions.size} sessions`);
  for (const c of claimed.slice(0, 40)) console.log(`- ${c}`);
  return 0;
}

// Required as a library (the refusal register calls classification on its own repeat signal - one judge of a
// classification, not two): export, and run neither a CLI branch nor the stdin hook.
module.exports = { classification, anomalies, readTurns };

// `--register-repeats <folder> [N] [--gate <NAME>]`: replay of the register lookup - every turn of the newest N
// transcripts (default: all) with a refusal the carrier register held an EARLIER entry for (same gate, same tool), per
// gate and tool, and whether the turn named a cause or classified it. `--gate` lists the turns of one gate.
if (require.main !== module) {
  /* library use: nothing runs */
} else if (process.argv[2] === '--register-repeats') {
  const dir = process.argv[3];
  const cwd = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const only = process.argv.includes('--gate') ? process.argv[process.argv.indexOf('--gate') + 1] : '';
  let files = [];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(dir, f))
      .sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs);
    if (/^\d+$/.test(process.argv[4] || '')) files = files.slice(-Number(process.argv[4]));
  } catch (e) { files = []; }
  const causeRx = loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu');
  const per = {}; const rows = []; let total = 0; const tot = { released: 0, cause: 0, bare: 0 };
  for (const tp of files) {
    let turns = [];
    try { turns = readTurns(tp, false); } catch (e) { turns = []; }
    for (const t of turns) {
      const r = registerRepeat([t], cwd);
      if (!r) continue;
      total += 1;
      const k = `${r.gate} ${r.tool}`;
      const p = per[k] = per[k] || { turns: 0, released: 0, cause: 0, bare: 0, days: new Set(), first: r.hits[0] };
      p.turns += 1; p.days.add(String(r.at).slice(0, 10));
      // what the turn's own text would do at the hold: released by a BACKED classification, sent the cause path by a
      // cause line, or a bare classification line that releases nothing
      const cls = classification([t], cwd, { texts: t.texts, writes: t.writes },
        { kind: 'register-repeat', block: true, what: r.what, hits: r.hits, at: r.pos });   // as the live hook
      if (causeIn(t.texts, causeRx)) { p.cause += 1; tot.cause += 1; }
      else if (cls.backed && (cls.kind !== 'false-positive' || namesEarlier((t.writeTexts || []).map((w) => w.t).join('\n'), r.hits))) { p.released += 1; tot.released += 1; }
      else if (cls.kind) { p.bare += 1; tot.bare += 1; }
      if (only && r.gate === only) rows.push(`${String(r.at).slice(0, 16)} ${path.basename(tp).slice(0, 8)} ${r.tool}: ${r.hits.length} earlier (${r.hits.map((h) => h.date).join(', ')}) | "${String(t.prompt || '').replace(/\s+/g, ' ').slice(0, 70)}"`);
    }
  }
  let reg = [];
  try { reg = registerEntries(fs.readFileSync(path.join(cwd, registerPath(cwd)), 'utf8')); } catch (e) { reg = []; }
  console.log(`${files.length} transcript(s) · ${reg.length} register entr(y/ies), ${reg.filter((e) => e.key).length} with a refusal: field · ${total} turn(s) with a refusal the register already held`);
  for (const [k, p] of Object.entries(per).sort((a, b) => b[1].turns - a[1].turns)) {
    console.log(`  ${k}: ${p.turns} turn(s) on ${p.days.size} day(s) - released by a backed classification ${p.released}, cause path ${p.cause}, a bare line (still held) ${p.bare}; first entry ${p.first.date} ${p.first.id || p.first.title.slice(0, 50)}`);
  }
  console.log(`  all: released by a backed classification ${tot.released}, cause path ${tot.cause}, a bare line (still held) ${tot.bare}, no line (held) ${total - tot.released - tot.cause - tot.bare}`);
  for (const r of rows.sort()) console.log(`  | ${r}`);
  process.exitCode = 0;
} else
// `--anomalies <folder> [N] [--samples K]`: replay of the anomaly signals over the newest N transcripts - per kind, per
// gate, how many own-fail turns carried a classification or cause line, and K samples of repeat/bypass to judge by hand.
if (process.argv[2] === '--anomalies') {
  const dir = process.argv[3];
  const cwd = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const k = process.argv.includes('--samples') ? Number(process.argv[process.argv.indexOf('--samples') + 1]) : 0;
  let files = [];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(dir, f))
      .sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs).slice(-Number(process.argv[4] || 60));
  } catch (e) { files = []; }
  const classRx = loadPatterns(cwd, 'anomaly_patterns', BUILTIN_ANOMALY, 'imu');
  const causeRx = loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu');
  const kinds = {}; const gates = {}; const samples = [];
  for (const tp of files) {
    let turns = [];
    try { turns = readTurns(tp, false); } catch (e) { turns = []; }
    for (const t of turns) {
      for (const a of anomalies([t], cwd)) {
        const s = kinds[a.kind] = kinds[a.kind] || { n: 0, classified: 0, backed: 0 };
        s.n += 1;
        if (causeIn(t.texts, classRx) || causeIn(t.texts, causeRx)) s.classified += 1;
        if (a.block && (causeIn(t.texts, causeRx) || classification([t], cwd, null, a).backed)) s.backed += 1;
        const own = process.argv.includes('--own');
        if (a.kind === 'repeat' || a.kind === 'bypass') gates[a.gate] = (gates[a.gate] || 0) + 1;
        if ((a.kind === 'own-fail') === own && samples.length < k) {
          const next = (t.texts.find((x) => x.length > 20) || '').replace(/\s+/g, ' ').slice(0, 160);
          samples.push(`${path.basename(tp).slice(0, 8)} ${a.kind}: ${a.what}${own ? `\n    turn text: ${next}` : ''}`);
        }
      }
    }
  }
  console.log(`${files.length} transcript(s)`);
  for (const [kd, s] of Object.entries(kinds)) console.log(`${kd}: ${s.n} signal(s), a classification or cause line in the turn: ${s.classified}` + (s.backed || kd === "own-fail" || kd === "marker-pass" ? `, backed or on the cause path: ${s.backed}` : ""));
  for (const [g, n] of Object.entries(gates).sort((a, b) => b[1] - a[1]).slice(0, 12)) console.log(`  repeat/bypass by ${g}: ${n}`);
  for (const s of samples) console.log(`sample ${s}`);
  process.exitCode = 0;
} else
// `--refused <transcript | folder> [N]`: replay of the two refusal triggers (a refused asked-for step, a gate malfunction)
// over one transcript or the newest N of a folder; per turn it would open, and per gate whether the turn named a cause.
if (process.argv[2] === '--refused') {
  const arg = process.argv[3];
  const cwd = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let files = [arg];
  try {
    if (fs.statSync(arg).isDirectory()) {
      files = fs.readdirSync(arg).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(arg, f))
        .sort((a, b) => fs.statSync(a).mtimeMs - fs.statSync(b).mtimeMs).slice(-Number(process.argv[4] || 60));
    }
  } catch (e) { files = []; }
  const causeRx = loadPatterns(cwd, 'cause_patterns', BUILTIN_CAUSE, 'imu');
  let asked = 0; const perGate = {}; const sessions = {};
  for (const tp of files) {
    let turns = [];
    try { turns = readTurns(tp, false); } catch (e) { turns = []; }
    for (let i = 0; i < turns.length; i += 1) {
      const r = refusedAsk([turns[i]], cwd, tp);
      if (r) { asked += 1; console.log(`${path.basename(tp).slice(0, 8)} turn ${i + 1}: ${r}`); }
      const m = malfunctionIn([turns[i]]);
      if (!m) continue;
      const gate = /^(command hook \d+|a hook|\S+)/.exec(m)[1];
      const p = perGate[gate] = perGate[gate] || { turns: 0, cause: 0 };
      p.turns += 1; if (causeIn(turns[i].texts, causeRx)) p.cause += 1;
      (sessions[gate] = sessions[gate] || new Set()).add(tp);
    }
  }
  console.log(`${files.length} transcript(s) · refused asked-for step: ${asked} turn(s)`);
  for (const [g, p] of Object.entries(perGate).sort((a, b) => b[1].turns - a[1].turns)) {
    console.log(`malfunction ${g}: ${p.turns} turn(s) in ${sessions[g].size} session(s), a cause named in ${p.cause}`);
  }
  process.exitCode = 0;
} else if (process.argv[2] === '--review') {
  hookExit(review(process.argv.slice(3)));
} else if (process.argv[2] === '--claimed-replays') {
  hookExit(claimedReplays(process.argv.slice(3)));
} else {
  const pre = process.argv[2] === '--pre';
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    try { (pre ? preGate : gate)(JSON.parse(data || '{}')); } catch (e) { /* fail open */ }
    hookExit(0);
  });
}
