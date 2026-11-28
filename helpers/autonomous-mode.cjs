#!/usr/bin/env node
/**
 * Autonomous mode: did the operator order this run to go on without them?
 *
 * WHY (2026-10-21): the rule exists (skill autonomous-run, hard gate 7; operator decision
 * 2026-10-19): while the operator's autonomous order runs, a question for them is filed in
 * the instance's ledger and reported in prose — never asked through the question tool. But no
 * gate knew the mode: stoppen-gate demanded the question tool for a closing decision question,
 * open-items-gate demanded the "shall I?" offer in the first reply — both pushing the agent
 * toward the interactive stop the rule forbids. One reader, used by every gate that asks for
 * a question.
 *
 * Autonomous = a latch over the operator's words:
 *   - an ON word sets it ("work through everything autonomously");
 *   - an OFF word clears it ("normal mode", "stop autonomous");
 *   - ASKING what is open clears it: the operator who asks is here, the open decisions go through
 *     the question tool, and the last of them is "continue autonomously?" (operator, Windows
 *     instance, 2026-10-26, translated: "as soon as I ask whether anything is open for me, I am
 *     obviously here ... that ends the autonomous mode. The last question is always: continue
 *     autonomously?");
 *   - a YES to a question-tool question that carries an ON word sets it again — that answer arrives
 *     as a tool result, not as a prompt.
 * A status question or a remark in between ("status?", "the desk is running, if you need it", "do
 * not stop everything interactively") ends nothing: re-deciding the mode at every prompt made those
 * stop the run (macOS findings on #143 and #142, 2026-10-26).
 * No transcript or no ON prompt: interactive.
 * Operator words only: no notification, hook echo, loaded skill text, request blob, peer message,
 * or the harness's instruction frames (a CLAUDE.md that mentions "autonomous" must not switch anything),
 * and no text the operator PASTED (turn-kind.cjs operatorWords, 2026-10-28): a pasted article that says
 * "autonomously" or "anything open" switches nothing; the prompt still counts as a prompt.
 *
 * Words: English built-ins below; the operator's language is instance data —
 * `.claude/rules/autonomous-patterns.json` {"on_patterns", "off_patterns", "yes_patterns"} and the
 * `ask_patterns` of `.claude/rules/open-items.json` (the key open-items-gate reads) — regexes,
 * case-insensitive, merged in.
 *
 * CLI: node autonomous-mode.cjs <transcript> [cwd]  -> prints "autonomous" or "interactive".
 * For the operator (what the modes mean, what they do not, how to switch): docs/run-modes.md.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { isNotification, isSkillExpansion, isAgentOrigin, isTranscriptRecord, queuedHumanPrompt, operatorWords, FRAMES, LOCAL } = require('./turn-kind.cjs');

// The short mode words, the same in every language (operator 2026-11-02, question tool: "auto mode" / "ask mode").
// "auto mode" counts only at the start of a sentence that is no question - Claude Code calls its own permission
// mode "auto mode" too, and "is auto mode on?" or "the auto mode classifier refused" must not start a run.
// "ask mode" ends the run wherever it stands: a false end is the safe direction.
const BUILTIN_ON = [
  '^\\s*auto[- ]?mod(?:e|us)\\b',
  '\\bautonomous(ly)?\\b',
  '\\bwork (the list|through (it|them|everything)) (alone|on your own)\\b',
  "\\bi'?m away\\b",
];
const BUILTIN_OFF = [
  '\\bask[- ]?mod(?:e|us)\\b',
  '\\bnormal mode\\b',
  '\\b(stop|end) (the )?autonomous\\b',
  '\\bno longer autonomous\\b',
];
const BUILTIN_ASK = [
  '\\banything (still |else )?(open|left|pending)\\b',
  '\\bwhat is (still )?open\\b',
  '\\bopen (for|to) me\\b',
  '\\bdo you need (anything|something)\\b',
  '\\bput (the |your )?(open )?(decisions|questions) to me\\b',
];
const BUILTIN_YES = ['^\\s*yes\\b'];
// A session close word is NO mode switch: it ends the autonomous mode at once, without the mode-confirm question, in
// every brain (operator 2026-11-25, question tool, translated: "closing the session is a point of its own that behaves
// differently. what I said concerns recognising a mode switch between autonomous and interactive. closing always
// closes" - agreeing with the decision of another brain's operator on #672: "a close word ends the autonomous mode at
// once, with no mode question"). English built in (the session-close skill's triggers); other languages
// `close_patterns` in autonomous-patterns.json. A sentence that is a question ("can I end the session?") closes too:
// the skill fires on it, and ending the mode is the safe direction.
const BUILTIN_CLOSE = [
  '\\b(close|end) the session\\b',
  "\\bwe'?re done for today\\b",
  '\\bwrap it up\\b',
  "\\bi'?m shutting (everything )?down\\b",
];
// An order that pre-authorizes a LATER question ("once you are ready for X, switch to interactive and ask me the X
// question"): it opens a DEFERRED window that outlives the turns the operator did not open (operator 2026-11-23, after
// the gate refused exactly that question: "I told you word for word to switch to interactive as soon as you want to
// put the train question to me ... a bug"). English built in; other languages `defer_ask_patterns` in
// autonomous-patterns.json. A sentence that is a question ("shall I ask later?") opens nothing.
const BUILTIN_DEFER = [
  '\\b(?:once|when|as soon as)\\b[^.?!]{0,100}\\b(?:ask me|put (?:the |your )?[\\w -]{0,30}question(?:s)? to me|switch (?:back )?to interactive)\\b',
];
// The mode-confirm question (operator order 2026-11-25, translated: a recognised mode word never switches by itself; it
// opens a question, and only the answer switches). A mode word - from the word lists or from the intent classifier - no
// longer moves the latch: it leaves a PENDING confirmation, and the latch moves only when the operator answers a
// question-tool question whose header is exactly this word (the chip, at most 12 characters, the same in every
// language). Measured cause (macOS instance, .claude-state/intent-classifier.jsonl 2026-11-25T12:46:20Z): the classifier
// set mode_on on "ask his AI now anyway to pull everything to 2.1.7 on its own" (translated) - the sentence was about
// another party's AI - and the run switched. Replay over the 5562 classifier records of that brain: 47 switched to
// autonomous against the word lists, several of them complaints or questions ABOUT the mode.
// The answer: the option the operator's words name comes FIRST (operator 2026-11-26, translated: "continue
// interactively, and that should be the first choice when I say so"). Towards interactive the FIRST option is the
// interactive one ("continue interactively"); towards autonomous - and with no mode word waiting - the LAST one is
// ("stay interactive"); any other listed option is autonomous (its label names what the run takes on); a free-text answer is
// read by the words (an off-word = interactive, an order or a yes = autonomous), anything else stays interactive - a
// false "autonomous" is the dangerous direction. A mode-confirm question rejected or interrupted switches nothing.
// MODE_READING=words gives the reading BEFORE the confirmation (the old latch): scripts/pattern-cases.py tests how the
// WORDS are read, and every instance's case data was written against that reading.
const CONFIRM_HEADER = 'mode-confirm';
const wordsOnly = () => String(process.env.MODE_READING || '').toLowerCase() === 'words';
// A leading no to the mode question (an instance adds its language: `no_patterns` in autonomous-patterns.json).
const BUILTIN_NO = ['^\\s*no\\b'];
const HOOK_ECHO = /^\s*Stop hook feedback:/;
// The tool result of an answered AskUserQuestion: `"<question>"="<answer>"` pairs.
// Two wordings in the wild (measured 2026-10-30, macOS instance: "Your questions have been answered: …" and
// "The user answered: …", the second in 58 of 514 transcripts) — the first answer of that evening carried the
// second and set nothing.
const ANSWERED = /questions have been answered|The user answered:/;
const PAIR = /"([^"]*)"="([^"]*)"/g;

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; } }

/** Does the prompt pre-authorize a later question? The match must not sit in a sentence that is itself a question. */
function deferAsk(rxDefer, text) {
  const t = String(text || '');
  const m = rxDefer.exec(t);
  if (!m) return false;
  const end = t.slice(m.index).search(/[.!?]/);
  return !(end >= 0 && t.slice(m.index)[end] === '?');
}
function rx(builtins, extra) {
  const list = [...builtins];
  for (const s of extra || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ } }
  return new RegExp(list.join('|'), 'iu');
}

/**
 * The four word sets of a brain (on, off, ask, yes) and its start state. `initial_mode` in the
 * instance data is the mode a session has before the operator's first word: "autonomous" or the
 * default "interactive". Measured 2026-11-01 on the macOS instance: the operator's standing word
 * ("run fully autonomously until I ask what is pending for me", translated, 2026-10-26) stood only
 * in prose; every session began interactive, a start prompt with no on-word left it there, and a
 * mid-run question reached the operator who believed the run autonomous. The words still switch:
 * an off-word or a question for what is open ends the mode, an on-word or a yes to the mode
 * question sets it again.
 */
function words(cwd) {
  const dir = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const ap = readJson(path.join(dir, '.claude', 'rules', 'autonomous-patterns.json')) || {};
  const oi = readJson(path.join(dir, '.claude', 'rules', 'open-items.json')) || {};
  return {
    on: rx(BUILTIN_ON, ap.on_patterns),
    off: rx(BUILTIN_OFF, ap.off_patterns),
    ask: rx(BUILTIN_ASK, oi.ask_patterns),
    yes: rx(BUILTIN_YES, ap.yes_patterns),
    close: rx(BUILTIN_CLOSE, ap.close_patterns),
    defer: rx(BUILTIN_DEFER, ap.defer_ask_patterns),
    no: rx(BUILTIN_NO, ap.no_patterns),
    initial: initialState(dir, ap, oi).granted,
    // `mode_confirm: true` turns the mode-confirm question on; missing or false keeps the direct switch (a mode word
    // switches at once), so a brain that sets nothing sees no change (operator 2026-11-25: "provide both options").
    // The close words and the ask window hold in both settings.
    confirm: ap.mode_confirm === true,
  };
}

/**
 * The start state with its guard (operator 2026-11-02, question tool: "Ja, Kern-PR bauen"): `initial_mode:
 * autonomous` holds only when the brain can recognise the operator ending the run in the operator's own
 * language - its own off or ask words, or a semantic intent classifier that has written records. The
 * built-in words are English (plus the short "ask mode"); a brain that starts autonomous and hears only
 * "weiter interaktiv" would run on. Without a way out the session starts interactive and the session start
 * says why. Returns { wanted, granted, why }.
 */
function initialState(cwd, ap, oi) {
  const dir = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  ap = ap || readJson(path.join(dir, '.claude', 'rules', 'autonomous-patterns.json')) || {};
  oi = oi || readJson(path.join(dir, '.claude', 'rules', 'open-items.json')) || {};
  const wanted = String(ap.initial_mode || '').toLowerCase() === 'autonomous';
  if (!wanted) return { wanted, granted: false, why: '' };
  const own = (ap.off_patterns || []).length + (oi.ask_patterns || []).length;
  let classifier = false;
  try { classifier = fs.statSync(path.join(dir, '.claude-state', 'intent-classifier.jsonl')).size > 0; } catch (e) { /* none */ }
  if (own || classifier) return { wanted, granted: true, why: '' };
  return { wanted, granted: false,
    why: 'initial_mode is "autonomous" but this brain has no own off_patterns/ask_patterns and no intent classifier records - the session starts interactive (only the English built-ins and "ask mode" would end a run)' };
}

/**
 * An on-word orders the run only outside a question. Measured 2026-10-27 on the macOS instance: the
 * operator asked (translated) "got no continue-autonomously question, did I? why?" - the word in that
 * question set the latch, and the gate then held the very mode question the operator was missing.
 * A sentence ending in "?" mentions the mode; it does not order it.
 */
function ordersOn(on, text) {
  return (text.match(/[^.!?\n]+[.!?]*/g) || []).some((s) => !/\?\s*$/.test(s) && on.test(s));
}

/**
 * The mirror of ordersOn: a question-tool question is the MODE question only when the on-word stands in its
 * question sentence itself. Measured 2026-10-31 on the macOS instance: "… The autonomous gate held the edit
 * back; the patch is in <file>. Shall I apply it now?" was read as the mode question, the operator's "yes,
 * apply it" switched the moment back to autonomous, and the gate then held the very edit the operator had
 * just agreed to.
 */
function asksMode(on, question) {
  return (question.match(/[^.!?\n]+[.!?]*/g) || []).some((s) => /\?\s*$/.test(s) && on.test(s));
}

/** Is this question-tool question a mode-confirm question? By its header alone - language-independent. */
function isConfirm(q) { return Boolean(q) && String(q.header || '').trim().toLowerCase() === CONFIRM_HEADER; }

/** Index of the interactive option: first when the waiting mode word asks for interactive, else last. */
function interactiveAt(n, direction) { return direction === 'interactive' ? 0 : n - 1; }

/** Do these option labels stand misordered for interactive slot `i`? The one rule both sides use: mode-confirm.cjs `pre`
 *  holds such a question at ask time, `confirmChoice` reads one already on disk by the other slot (below). Not
 *  language-complete: it catches the likely slip - an on-word in the interactive slot, an off-word or "interactive" in any
 *  other. */
const INTER = /interakti|interacti/i;
function misordered(w, labels, i) {
  const ls = (labels || []).map((l) => String(l || ''));
  return w.on.test(ls[i] || '') && !INTER.test(ls[i] || '') || ls.some((l, k) => k !== i && (w.off.test(l) || INTER.test(l)));
}

/** The answer to a mode-confirm question: true = autonomous, false = interactive (CONFIRM_HEADER above).
 *  `direction` is the mode word's that was waiting when the question was ASKED ('interactive' | 'autonomous' | none) -
 *  the same one `pre` checked the order against (Windows review of #672, round two: taken at answer time, an off-word in
 *  an earlier answer of the same call moved the slot). It says where the interactive option stands. A question whose
 *  labels are misordered for that slot but in order for the other one was asked under the other order - before the
 *  2026-11-26 update, since `pre` holds it now - and is read by the slot it was asked with: a run kept by "Stay
 *  autonomous" under the old order is not re-read as interactive after the update (round two, second finding). */
function confirmChoice(w, labels, answer, direction) {
  const a = String(answer || '').trim();
  const ls = (labels || []).map((l) => String(l || '').trim());
  let i = interactiveAt(ls.length, direction);
  const alt = i === 0 ? ls.length - 1 : 0;
  if (ls.length >= 2 && misordered(w, ls, i) && !misordered(w, ls, alt)) i = alt;
  if (ls.length >= 2) {
    if (a === ls[i]) return false;
    if (ls.some((l, k) => k !== i && l === a)) return !(w.off.test(a) || INTER.test(a));   // a label that names interactive never switches on
  }
  // Free text: the interactive option's label, or an off-word, anywhere in it = interactive; only an order switches on -
  // a yes-word alone does not (Windows review of #672: "yes, stay interactive" read autonomous by its yes).
  const inter = ls.length ? ls[i].toLowerCase() : '';
  if (w.off.test(a) || (inter && a.toLowerCase().includes(inter))) return false;
  return ordersOn(w.on, a);
}

/**
 * The answer to the MODE question: true = on, false = off, null = it says neither. Before 2026-11-24 only a
 * yes-word switched on. Measured that night on a macOS instance: the agent asked "work through it autonomously
 * or stay interactive?" with the options named after the modes; the operator chose the option that NAMES the
 * autonomous mode, it carried no yes-word, and the run was read as interactive. The autonomous gate therefore let
 * an edit behind an ask rule through to the harness dialog, and the run stood 376 minutes at it. An answer that
 * names the mode is that mode; an off-word or a leading no wins over everything.
 */
function modeAnswer(w, answer) {
  const a = String(answer || '');
  if (w.off.test(a) || (w.no && w.no.test(a))) return false;
  // The on-word counts only as the answer's HEAD - the option is named after the mode ("Autonomous, go on"). An
  // on-word further in ("only autonomous or released") is an answer ABOUT autonomy: replayed over 119 answered mode
  // questions of the proving instance, the head rule reads two missed switches right and adds no false one; an
  // on-word anywhere would have switched a run on at a design question (2026-11-18).
  if (w.yes.test(a) || w.on.test(a.trim().split(/\s+/)[0] || '')) return true;
  return null;
}

function promptText(msg) {
  const c = msg && msg.content;
  if (typeof c === 'string') return c;
  if (!Array.isArray(c) || c.some((b) => b && b.type === 'tool_result')) return null;
  return c.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') || null;
}

/**
 * [question, answer] pairs of an answered question tool in this record. Only the result of an
 * AskUserQuestion call counts (`askIds`): measured 2026-10-28 on the macOS instance, a Read of a
 * fixture that carries the answer marker ("Continue autonomously?"="No, interactive") ended the
 * operator's autonomous run, and the next call that an ask rule turns into a dialog stopped on the
 * operator. A replay over one brain's transcripts found 11 such results (Read and Bash) in 5 sessions.
 */
// `qsById` (call id -> the question texts it asked): the pair is found by the question as asked, not by a quote
// pattern - the harness does not escape a `"` inside the question, and PAIR then read nothing (measured 2026-11-25,
// macOS instance: a mode-confirm question quoting the operator's `"was soll das?"` was answered "continue
// interactively", read as REJECTED, and the run stayed autonomous; decision-register.cjs reads it this way already).
function answers(msg, askIds, qsById) {
  const c = msg && msg.content;
  if (!Array.isArray(c)) return [];
  const out = [];
  for (const b of c) {
    if (!b || b.type !== 'tool_result') continue;
    if (askIds && !askIds.has(b.tool_use_id)) continue;
    const s = typeof b.content === 'string' ? b.content
      : Array.isArray(b.content) ? b.content.map((x) => (x && x.text) || '').join('\n') : '';
    if (!ANSWERED.test(s)) continue;
    const known = [];
    for (const q of (qsById && qsById.get(b.tool_use_id)) || []) {
      const k = `"${q}"="`;
      const i = s.indexOf(k);
      if (i < 0) continue;
      const rest = s.slice(i + k.length);
      const end = /"(?=, "|\.(?:\s|$)|\s*$)/.exec(rest);
      known.push([q, end ? rest.slice(0, end.index) : rest]);
    }
    if (known.length) out.push(...known);
    else for (const m of s.matchAll(PAIR)) out.push([m[1], m[2]]);
  }
  return out;
}

/**
 * A brain's prompt classifier, if it has one, appends one record per operator prompt to
 * .claude-state/intent-classifier.jsonl: {at, session, mode: "hook", model: {asks_open, mode_off, …}}.
 * Measured 2026-10-28 on the macOS instance (classifier as instance alpha, read by no gate): the
 * word lists missed "you need something?" and "give me interactive questions …" (the operator's
 * language, translated) — both asks for what is
 * open — and the model read both right; the run kept refusing the question tool the operator had
 * asked for. The model is read in the SAFE direction only (asks what is open, ends the mode): a
 * false yes there costs one question, a false "autonomous" would silence the operator's questions.
 * Matched by session and time: the first record within 90 s after the prompt. No file = words only.
 */
const INTENT_WINDOW_MS = 90 * 1000;
function intents(transcriptPath, cwd, kind) {
  const session = path.basename(transcriptPath || '', '.jsonl');
  const file = process.env.INTENT_CLASSIFIER_LOG || path.join(cwd || '.', '.claude-state', 'intent-classifier.jsonl');
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return []; }
  const out = [];
  for (const line of text.split('\n')) {
    let r; try { r = JSON.parse(line); } catch (e) { continue; }
    if (!r || r.session !== session || r.mode !== (kind || 'hook') || !r.model) continue;
    const at = Date.parse(r.at);
    if (!Number.isNaN(at)) out.push({ at, model: r.model, prompt: typeof r.prompt === 'string' ? r.prompt : null });
  }
  return out;
}
/**
 * The record of THIS prompt: inside the window and, when the record carries its prompt, the same
 * text. Measured 2026-11-01 on the macOS instance: an operator message typed mid-turn ("lay the open
 * questions before me", translated) was read by the model as asks_open, but a task notification's
 * record 1.6 s earlier was the first one in the window - the operator's ask was read as "nothing", the
 * run stayed autonomous and the question tool was refused. A record without a prompt field (an older
 * classifier) still matches by time alone.
 */
function norm(s) { return String(s || '').replace(/\s+/g, ' ').trim().slice(0, 40); }
/** A record written BEFORE the transcript holds the prompt still belongs to it when its text matches: a message typed
 *  while the agent works is classified at submit, but the transcript writes it as a user record only when the next
 *  turn starts. Measured 2026-11-18 on the macOS instance: record 06:39:22 (mode_off), user record 06:39:31 - the
 *  forward-only window missed it, the words read "autonom" as an order, the operator's off-word did nothing. */
const INTENT_BEFORE_MS = 30 * 60 * 1000;
function intentFor(list, ts, text) {
  const t = Date.parse(ts || '');
  if (Number.isNaN(t)) return null;
  const want = norm(text);
  const same = (r) => r.prompt === null || !want || norm(r.prompt).slice(0, want.length) === want.slice(0, norm(r.prompt).length);
  const hit = list.find((r) => r.at >= t && r.at - t <= INTENT_WINDOW_MS && same(r))
    || list.filter((r) => r.prompt !== null && want && r.at < t && t - r.at <= INTENT_BEFORE_MS && same(r)).pop();
  return hit ? hit.model : null;
}

/**
 * One field of the classifier's record for one prompt: true or false when a record of THIS prompt (intentFor: same
 * session, inside the window, same text) carries the field, else null - no record, a failed call, or an older record
 * without the field - and the caller's words decide. Read for asks_open, correction and orders_task (operator decision
 * 2026-11-18, question tool: "gates read the model for asks-open / correction / orders-task; mode-on stays with the
 * words"). Hand-judged sample the same day on the macOS instance, 40 disagreements per field: the model was right in
 * 91 % (asks_open), 81 % (correction) and 97 % (orders_task) of the decided cases.
 */
/**
 * The record whose prompt IS this prompt (whitespace folded, the 160 characters a record keeps) - for a reading that
 * WAIVES a check. intentFor matches on a 40-character prefix and reaches 30 min back, right for adding a check, wrong for
 * removing one: measured 2026-11-26 by the Windows review of #682, an earlier "ok" or a prompt with the same first
 * 40 characters waived a hold main kept, and a failed call of the prompt itself fell back to an older record.
 */
// Round two of that review (2026-11-27): the prompt's OWN record - the forward window, the classifier runs on submit - is
// taken before any older one (an older record of the same text overruled it), and an older record counts only for a
// prompt under 160 characters, whose stored text is then complete (two prompts sharing their first 160 characters were
// one prompt to it).
const KEPT = 160;
function intentExact(list, ts, text) {
  const t = Date.parse(ts || '');
  const fold = (x) => String(x || '').replace(/\s+/g, ' ').trim();
  const whole = fold(text);
  const want = whole.slice(0, KEPT);
  if (Number.isNaN(t) || !want) return null;
  const same = (r) => r.prompt !== null && r.model && fold(r.prompt).slice(0, KEPT) === want;
  const hit = list.find((r) => r.at >= t && r.at - t <= INTENT_WINDOW_MS && same(r))
    || (whole.length < KEPT ? list.filter((r) => r.at < t && t - r.at <= INTENT_BEFORE_MS && same(r)).pop() : null);
  return hit ? hit.model : null;
}

function modelSays(key, transcriptPath, cwd, ts, text) {
  const hit = intentFor(intents(transcriptPath, cwd), ts, text);
  return hit && typeof hit[key] === 'boolean' ? hit[key] : null;
}

/**
 * Every operator word of the transcript in order, each with the latch AFTER it:
 * [{text, autonomous, queued, asks, answer}]. `asks`: the prompt asks what is open. `answer`: the
 * entry is a yes/no to an autonomy question, not a prompt. The last entry is the mode now.
 */
function promptModes(transcriptPath, cwd) {
  const w = words(cwd);
  let lines;
  try { lines = fs.readFileSync(transcriptPath, 'utf8').split('\n'); } catch (e) { return []; }
  const out = [];
  let state = w.initial;
  const askIds = new Set();
  const qsById = new Map(); // call id -> its question texts (answers() finds a pair by them)
  const known = intents(transcriptPath, cwd);
  // The asking prompt whose turn is still running with no question answered yet (its `window` is open).
  let pending = null;
  // all = a new operator prompt; a turn the operator did not open closes only a same-turn window, never a DEFERRED one
  const closeWindow = (all) => { if (pending && (all || !pending.deferred)) { pending.window = false; pending = null; } };
  // A mode word waiting for its mode-confirm answer: {direction: 'autonomous'|'interactive', text, at}.
  const confirming = w.confirm && !wordsOnly();
  let confirm = null;
  const confirmIds = new Set();
  // "<tool_use id>\n<question text>" -> {labels, direction} of the mode-confirm questions asked; `direction` is the mode
  // word waiting at ASK time, the one `pre` checked the order against (an answer in the same call cannot move it)
  const confirmQs = new Map();
  let lastOn = null;           // when the run in force was ordered or confirmed (a close stamp after it ends it)
  // The classifier also reads every question-tool ANSWER (records with mode "answer", prompt "Question: <q> …").
  // Until 2026-11-24 the answers were decided by the word lists alone. Measured on a macOS instance in one
  // session: an answer about how the AI may open pull requests on its own carried an on-word and switched the run
  // to autonomous (words on, model not) - nobody had ordered it; the next evening the answer that named the
  // autonomous mode was read as a no (words: no yes-word) while the model read mode_on. Both records were on disk.
  const knownAnswers = intents(transcriptPath, cwd, 'answer');
  for (const line of lines) {
    if (line.includes('"AskUserQuestion"')) {
      try {
        const c = (JSON.parse(line).message || {}).content;
        for (const b of Array.isArray(c) ? c : []) {
          if (!b || b.type !== 'tool_use' || b.name !== 'AskUserQuestion') continue;
          askIds.add(b.id);
          qsById.set(b.id, ((b.input && b.input.questions) || []).map((q) => String((q && q.question) || '')));
          for (const q of (b.input && b.input.questions) || []) {
            if (!isConfirm(q)) continue;
            confirmIds.add(b.id);
            confirmQs.set(`${b.id}\n${String(q.question || '')}`, {
              labels: (q.options || []).map((o) => (o && o.label) || ''), direction: confirm ? confirm.direction : null });
          }
        }
      } catch (e) { /* not a record */ }
    }
    if (!line.includes('"user"') && !line.includes('queued_command')) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    // A message the operator types mid-turn arrives as a queued_command attachment, not a user
    // record (turn-kind.cjs, #139): it sets or clears the mode like any prompt. `queued` marks it,
    // so a reader that counts turn BOUNDARIES can leave it out.
    const queued = queuedHumanPrompt(d);
    // A timer-fired prompt is the agent's or the harness's text: its "Autonomous loop check"
    // switched the mode back on after the operator had said "interactive" (measured 2026-10-27).
    // A turn the operator did not open (a timer, a peer's message) ends the asking prompt's window: the operator who
    // asked 20 minutes ago is not thereby present now (operator 2026-11-03, quoted in autonomous-gate.cjs).
    if (!queued && isAgentOrigin(d)) closeWindow(false);
    if (!queued && (!isTranscriptRecord(d) || isSkillExpansion(d) || isAgentOrigin(d)
        || !d.message || d.message.role !== 'user')) continue;
    if (!queued) {
      // A mode-confirm question that came back without an answer (rejected, interrupted) ends the wait, switches nothing.
      const c = Array.isArray(d.message.content) ? d.message.content : [];
      if (c.some((b) => b && b.type === 'tool_result' && confirmIds.has(b.tool_use_id) && answers({ content: [b] }, null, qsById).length === 0)) confirm = null;
      // pairs with their call id: a mode-confirm answer is matched by the call that asked it, never by its text alone
      // (a later question with the same text is another question)
      const pairs = c.filter((b) => b && b.type === 'tool_result')
        .flatMap((b) => answers({ content: [b] }, askIds, qsById).map(([q, a]) => [q, a, b.tool_use_id]));
      for (const [q, a, id] of pairs) {
        const key = `${id}\n${q}`;
        if (confirmQs.has(key)) {
          // The mode-confirm answer: the one place a mode word's switch takes effect.
          if (pending) { pending.window = false; pending = null; }
          const asked = confirmQs.get(key);
          state = confirmChoice(w, asked.labels, a, asked.direction);
          if (state) lastOn = Date.parse(d.timestamp) || null;
          confirm = null;
          out.push({ text: a, autonomous: state, queued: false, asks: false, answer: true, ordered: state, confirmed: true,
            at: Date.parse(d.timestamp) || null });
          continue;
        }
        // A question answered in the asking prompt's turn leaves the mode AND the window standing: all the collected
        // questions and the other dialogs come in it, and only then the mode question decides (operator 2026-11-25,
        // question tool: "not after the first answered question, the logic is different ... when I ask for
        // interactive questions, all questions come + other interactive dialogs if any, AFTER THAT comes the final
        // question 'continue autonomously'"). This replaces the core's implementation of the ask window of 2026-11-23
        // (changelog feat-ask-window), under which the first answered question ended the run - an AI's reading, not the
        // operator's word: on 2026-11-03 the operator said only that the mode changes when they ask for the questions,
        // and "either the questions come, or stay autonomous".
        // A yes/no to the mode question decides by yes; an answer to any other question is read
        // like a prompt, since the operator may order the run inside it (2026-10-30, macOS instance:
        // "yes, work through them autonomously" to "shall I handle them?" set nothing). The mode
        // question is read from its question sentence (asksMode), not from any on-word in the text.
        // A matched classifier record of the answer DECIDES, as for a prompt; the words are the fallback (#654).
        // The model alone never switches ON (operator decision 2026-11-17 on the proving instance: on a disagreement
        // between classifier and words, never toward autonomous): for an answer it can end the mode, and it can veto an
        // on-word the words would take for an order; switching on needs the words too.
        const ia = intentFor(knownAnswers, d.timestamp, `Question: ${q}`);
        const byModel = Boolean(ia && typeof ia.mode_on === 'boolean');
        const wants = byModel && ia.mode_change !== false;
        const wordsOn = asksMode(w.on, q) ? modeAnswer(w, a) === true : ordersOn(w.on, a);
        if (asksMode(w.on, q)) {
          // The mode question itself ("continue autonomously?") is a question: its answer switches (#672).
          if (pending) { pending.window = false; pending = null; } // the dialog's last question: the window ends here
          if (wants && ia.mode_off) state = false;
          else if (wants && ia.mode_on && wordsOn) state = true;
          else if (byModel && ia.mode_on && !wordsOn) continue;   // model on, words not: no switch
          // an answer that NAMES the mode is that mode (#654); null (it names neither) stays interactive
          else state = modeAnswer(w, a) === true;
        } else {
          // A mode word in the answer to ANY OTHER question is a mode word like one in a prompt: with mode_confirm on
          // it waits for the mode-confirm answer (#672). The model reads it first; without a record the words decide.
          let aOff;
          let aOn;
          if (byModel) {
            if (!wants || (ia.mode_on && !wordsOn)) continue;   // no mode order in it, or model on and words not
            aOff = Boolean(ia.mode_off);
            aOn = !aOff && Boolean(ia.mode_on);
          } else {
            aOff = w.off.test(a);
            aOn = !aOff && ordersOn(w.on, a);
          }
          if (aOff) {
            if (confirming && state) { confirm = { direction: 'interactive', text: a, at: Date.parse(d.timestamp) || null }; continue; }
            state = false;
          } else if (aOn) {
            if (confirming && !state) { confirm = { direction: 'autonomous', text: a, at: Date.parse(d.timestamp) || null }; continue; }
            state = true;
          } else continue;
        }
        if (state) lastOn = Date.parse(d.timestamp) || null;
        out.push({ text: a, autonomous: state, queued: false, asks: false, answer: true, ordered: state, by: byModel ? 'model' : 'words',
          at: Date.parse(d.timestamp) || null });
      }
    }
    const t = queued || promptText(d.message);
    if (t && /<task-notification>/.test(t) && isNotification(t)) closeWindow(false); // a background task's turn, not the operator's
    if (!t || HOOK_ECHO.test(t) || isNotification(t)) continue;
    const text = t.replace(FRAMES, ' ').replace(LOCAL, ' ');
    if (!text.trim()) continue;
    // a new operator prompt ends a same-turn window; a DEFERRED one only when this prompt ends or re-orders the run
    // (below) - the operator adding to the work ("and also ...") leaves the pre-authorized question standing
    // (measured on the incident: three such prompts followed the order and closed the window before the question came)
    closeWindow(false);
    // The words are matched without pasted blocks; `text` keeps them, so a reader that finds this
    // prompt again in the transcript by its text (decision-presentation-gate) still finds it.
    const own = operatorWords(text);
    const intent = intentFor(known, d.timestamp, t);
    // A matched classifier record DECIDES; the word lists are the fallback when there is none (operator order
    // 2026-10-28, "this detection must be semantic, not word logic"; sharpened 2026-11-01 when the words were
    // patched again). Measured the same day on the macOS instance, three prompts where the words were wrong
    // and the model right: "thought it was autonomous" (words mode_on, model not), "lay the open questions
    // before me" (model asks_open, words not), and the start "status?" (both none).
    // The model's asks_open yields to its own mode_on in the SAME prompt (2026-10-31: "work through all open
    // points, handle them autonomously" carried both; the run the operator had just ordered must start).
    let asks;
    let off;
    let ordered = false; // this prompt itself ordered the run (the close stamp is compared against the newest order)
    let on;
    // The classifier decides FIRST whether the message intends a mode change at all (`mode_change`), and only then
    // which (operator 2026-11-24, translated: "the classifier must recognise whether there is an intention to switch
    // the mode at all, and if so which. We are talking about the modes themselves and you keep switching, although
    // that is not my intention"). Measured that morning on a macOS instance: five operator messages ABOUT the mode
    // (a question since when, a report that it had been wrong, the analysis of the misread) flipped it four times
    // in ten minutes, and the agent read the last value back as "it never changed". A record without the field
    // (an older classifier) is read as before (#654). A mode word that does intend a change then waits for the
    // mode-confirm answer below (#672).
    const intends = !(intent && intent.mode_change === false);
    if (intent && typeof intent.asks_open === 'boolean') {
      asks = intent.asks_open && !(intent.mode_on && intends);
      off = intent.mode_off && intends;
      on = !off && !asks && intent.mode_on && intends;
    } else {
      asks = w.ask.test(own);
      off = w.off.test(own);
      on = !off && !asks && ordersOn(w.on, own);
    }
    // A mode word that would CHANGE the mode waits for the mode-confirm answer; one that names the mode already in force
    // changes nothing and asks nothing (an order after this session's close counts as a change).
    const at = Date.parse(d.timestamp) || null;
    const running = state && !closedAfter(transcriptPath, cwd, lastOn);
    // a session close word ends the mode at once and asks nothing (BUILTIN_CLOSE above)
    if (w.close.test(own)) { on = false; off = true; asks = false; confirm = null; }
    else if (confirming && on && !running) { confirm = { direction: 'autonomous', text: own, at }; on = false; }
    else if (confirming && off && state) { confirm = { direction: 'interactive', text: own, at }; off = false; }
    else if (confirming && (on || off)) confirm = null; // the operator named the mode in force: nothing left to confirm
    if (on) { state = ordered = true; lastOn = at; }
    // "What is open for me?" brings the questions (operator 2026-11-03, translated: "why did you just switch to
    // interactive? no questions came. either the questions, or stay autonomous"): the asking prompt opens a `window` -
    // in its turn the question tool and the dialogs pass (autonomous-gate.cjs) -, ALL questions and dialogs come in it
    // and the mode stays as it is, and the closing mode-confirm question decides (operator 2026-11-25, above); a turn
    // that asks nothing leaves it autonomous. (Until 2026-11-25 the core's implementation of 2026-11-23 ended the run
    // at the first answered question.) Until 2026-11-23 the run ended only when a derived count of open
    // operator decisions was above 0; the count read what the agent itself had filed, and three incidents on the
    // macOS instance (2026-11-05, -18, -23) each failed on one more form it did not read - the question tool was
    // refused on the operator's own request. Replay over that instance's history: 14 such prompts refused, in 6 the
    // count was 0, and the widened count would have caught 2 of them. What is filed as open stays a DUTY: the
    // presentation gate holds a turn that asked nothing while a decision is open.
    let window = false;
    if (off) state = false;
    else if (asks && state) window = true;
    // An order that pre-authorizes a later question opens the window now and keeps it open across the turns that
    // follow (timers, peers, background tasks) until the closing mode question is answered or the operator writes again.
    const deferred = !off && state && deferAsk(w.defer, own);
    if (pending && pending.deferred && (off || asks || ordered || deferred)) closeWindow(true);
    if (deferred) window = true;
    const row = { text, autonomous: state, queued: Boolean(queued), asks, answer: false, by: intent ? 'model' : 'words',
      ordered, window, deferred, confirm: confirm && confirm.at === at && confirm.text === own ? confirm.direction : null,
      at: Date.parse(d.timestamp) || null };
    out.push(row);
    if (window) pending = row;
  }
  // a deferred window still open at the end, though later prompts came (they add to the work, they do not re-order it)
  out.deferredOpen = Boolean(pending && pending.deferred && pending.window);
  // a mode word still waiting for its mode-confirm answer at the end of the transcript
  out.confirmPending = confirm;
  return out;
}

/** true while the operator's newest prompt asked what is open and its turn still runs with no question answered:
 *  the question tool and the dialogs pass, though the run is (still) autonomous. */
function askWindow(transcriptPath, cwd) {
  const rows = promptModes(transcriptPath, cwd);
  const last = rows[rows.length - 1];
  // 'turn' = an asking prompt's own turn (questions and dialogs pass); 'deferred' = a pre-authorized later question
  // (only the question tool passes - it stays open across turns, so it must not open every dialog too)
  if (last && last.window) return last.deferred ? 'deferred' : 'turn';
  return rows.deferredOpen ? 'deferred' : false;
}

/** true when the operator's autonomous order is in force at the end of the transcript. A session close of THIS
 *  session after the order ends it (2026-11-06, operator: "session beenden ist sehr wohl modus wechsel auch, das
 *  thema mit der endlos loop am ende hatten wir schon mehrfach"): with the mode still on after `session-close`, the
 *  autonomous gate refused the question tool while the stoppen gate demanded it, and the idle and close gates held
 *  the release - the close looped. The carrier is the close stamp `session-closing.sh --pre-commit` writes (line 1:
 *  the session id), language-independent; a new autonomous order after the close switches the mode on again. */
function autonomousMode(transcriptPath, cwd) {
  const modes = promptModes(transcriptPath, cwd);
  if (!modes.length) return words(cwd).initial && !closedAfter(transcriptPath, cwd, null);
  if (!modes[modes.length - 1].autonomous) return false;
  // when the run in force was ordered: the newest entry of the trailing autonomous stretch that ordered it itself
  // (a re-order after a close counts from then), else the stretch's first entry
  let onAt = null;
  for (let i = modes.length - 1; i >= 0 && modes[i].autonomous; i--) {
    onAt = modes[i].at;
    if (modes[i].ordered) break;
  }
  return !closedAfter(transcriptPath, cwd, onAt);
}

/** Why the run is (still) autonomous, measured from the operator's newest prompt - for a refusal that names its reason
 *  (2026-11-23, macOS instance: the gate refused the question tool with its generic text after "questions now"; the
 *  agent guessed at the word list, the operator: "what do you keep saying about the word list?"). */
function modeReason(transcriptPath, cwd) {
  const rows = promptModes(transcriptPath, cwd).filter((r) => !r.answer);
  const last = rows[rows.length - 1];
  if (!last) return 'no operator prompt read in this transcript - the start state decides';
  const reader = last.by === 'model' ? 'the intent classifier record' : 'the word lists (no classifier record for this prompt)';
  if (last.asks && !last.window) {
    return `the operator's newest prompt was read as asking what is open (${reader}), but its turn ended without a `
      + 'question and this is a later turn the operator did not open (a timer, a task notification, a peer message) - '
      + 'the window of an asking prompt is its own turn';
  }
  if (!last.asks) return `the operator's newest prompt was not read as asking what is open, nor as an off-word (${reader})`;
  return `the run is autonomous by an order after the operator's newest prompt (${reader})`;
}

/** A close stamp of this session written after `since` (ms; null = any time). */
function closedAfter(transcriptPath, cwd, since) {
  const dir = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const stamp = path.join(dir, '.claude-state', 'session-close.stamp');
  let st;
  let sid;
  try { st = fs.statSync(stamp); sid = (fs.readFileSync(stamp, 'utf8').split(/\r?\n/)[0] || '').trim(); } catch (e) { return false; }
  const session = path.basename(String(transcriptPath || ''), '.jsonl');
  if (sid && session && sid !== session) return false; // another session's close
  return since == null || st.mtimeMs >= since;
}

/** The mode word still waiting for its mode-confirm answer: {direction, text, at}, or null. */
function confirmPending(transcriptPath, cwd) { return promptModes(transcriptPath, cwd).confirmPending || null; }

/**
 * The switches of a session: every entry at which the mode changed, with what changed it. The reader's last value
 * alone says nothing about when and why (2026-11-24: asked "since when, and did I order that?", the agent answered
 * from the last value twice in two days, both times wrong). [{at, autonomous, kind: 'prompt'|'answer', by, text}]
 */
function switches(transcriptPath, cwd) {
  const out = [];
  let prev = words(cwd).initial;
  for (const m of promptModes(transcriptPath, cwd)) {
    if (m.autonomous !== prev) out.push({ at: m.at, autonomous: m.autonomous, kind: m.answer ? 'answer' : 'prompt', by: m.by || 'words', text: String(m.text || '').replace(/\s+/g, ' ').trim().slice(0, 120) });
    prev = m.autonomous;
  }
  return out;
}

module.exports = { autonomousMode, promptModes, words, initialState, asksMode, modeAnswer, switches, intents, intentFor, intentExact, modelSays, answers, promptText, HOOK_ECHO, askWindow, modeReason,
  confirmPending, confirmChoice, interactiveAt, misordered, isConfirm, CONFIRM_HEADER };

if (require.main === module) {
  // The bare call prints ONE word: other scripts and the fixtures compare it. `--why` adds the last switch, `--trace`
  // every switch - to answer "since when, and why", never the bare word (read back to an operator as "it never
  // changed" twice in two days, macOS instance 2026-11-23/24). `--window`: the third verdict, see below.
  const args = process.argv.slice(2);
  const [tp, cwd] = args.filter((a) => !a.startsWith('--'));
  const flag = args.find((a) => a === '--window');
  // `--window`: the third verdict - `window` while the run is autonomous and the asking prompt's turn is open.
  if (flag === '--window' && autonomousMode(tp || '', cwd) && askWindow(tp || '', cwd)) { console.log('window'); return; }
  // scripts/pattern-cases.py runs this on a transcript that ENDS at the prompt under test and names its own open count
  // (AUTONOMOUS_OPEN_FOR_OPERATOR, default 1): a case tests how the WORDS are read. A prompt read as asking what is
  // open shows there as `interactive` when something is open (the turn must ask), as `autonomous` with 0 - the
  // verdicts every instance's case data was written against.
  const caseOpen = /^\d+$/.test(process.env.AUTONOMOUS_OPEN_FOR_OPERATOR || '') && Number(process.env.AUTONOMOUS_OPEN_FOR_OPERATOR) > 0;
  console.log(autonomousMode(tp || '', cwd) && !(caseOpen && askWindow(tp || '', cwd)) ? 'autonomous' : 'interactive');
  const trace = args.includes('--trace');
  if (!trace && !args.includes('--why')) return;
  const sw = switches(tp || '', cwd);
  const line = (x) => `${x.at ? new Date(x.at).toISOString().slice(0, 19) + 'Z' : 'time unknown'} -> ${x.autonomous ? 'autonomous' : 'interactive'} by the operator's ${x.kind} (read by ${x.by}): "${x.text}"`;
  if (!sw.length) console.log('no switch in this session: the start state holds');
  else if (trace) for (const x of sw) console.log(line(x));
  else console.log(`last switch: ${line(sw[sw.length - 1])} (${sw.length} switch(es) in this session; --trace lists them)`);
}
