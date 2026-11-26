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
// An order that pre-authorizes a LATER question ("once you are ready for X, switch to interactive and ask me the X
// question"): it opens a DEFERRED window that outlives the turns the operator did not open (operator 2026-11-23, after
// the gate refused exactly that question: "I told you word for word to switch to interactive as soon as you want to
// put the train question to me ... a bug"). English built in; other languages `defer_ask_patterns` in
// autonomous-patterns.json. A sentence that is a question ("shall I ask later?") opens nothing.
const BUILTIN_DEFER = [
  '\\b(?:once|when|as soon as)\\b[^.?!]{0,100}\\b(?:ask me|put (?:the |your )?[\\w -]{0,30}question(?:s)? to me|switch (?:back )?to interactive)\\b',
];
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
    defer: rx(BUILTIN_DEFER, ap.defer_ask_patterns),
    initial: initialState(dir, ap, oi).granted,
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
function answers(msg, askIds) {
  const c = msg && msg.content;
  if (!Array.isArray(c)) return [];
  const out = [];
  for (const b of c) {
    if (!b || b.type !== 'tool_result') continue;
    if (askIds && !askIds.has(b.tool_use_id)) continue;
    const s = typeof b.content === 'string' ? b.content
      : Array.isArray(b.content) ? b.content.map((x) => (x && x.text) || '').join('\n') : '';
    if (!ANSWERED.test(s)) continue;
    for (const m of s.matchAll(PAIR)) out.push([m[1], m[2]]);
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
function intents(transcriptPath, cwd) {
  const session = path.basename(transcriptPath || '', '.jsonl');
  const file = process.env.INTENT_CLASSIFIER_LOG || path.join(cwd || '.', '.claude-state', 'intent-classifier.jsonl');
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return []; }
  const out = [];
  for (const line of text.split('\n')) {
    let r; try { r = JSON.parse(line); } catch (e) { continue; }
    if (!r || r.session !== session || r.mode !== 'hook' || !r.model) continue;
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
function intentExact(list, ts, text) {
  const t = Date.parse(ts || '');
  const full = (x) => String(x || '').replace(/\s+/g, ' ').trim().slice(0, 160);
  const want = full(text);
  if (Number.isNaN(t) || !want) return null;
  const hit = list.find((r) => r.prompt !== null && r.at >= t - INTENT_BEFORE_MS && r.at - t <= INTENT_WINDOW_MS
    && full(r.prompt) === want && r.model);
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
  const known = intents(transcriptPath, cwd);
  // The asking prompt whose turn is still running with no question answered yet (its `window` is open).
  let pending = null;
  // all = a new operator prompt; a turn the operator did not open closes only a same-turn window, never a DEFERRED one
  const closeWindow = (all) => { if (pending && (all || !pending.deferred)) { pending.window = false; pending = null; } };
  for (const line of lines) {
    if (line.includes('"AskUserQuestion"')) {
      try {
        const c = (JSON.parse(line).message || {}).content;
        for (const b of Array.isArray(c) ? c : []) if (b && b.type === 'tool_use' && b.name === 'AskUserQuestion') askIds.add(b.id);
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
      for (const [q, a] of answers(d.message, askIds)) {
        // A question answered in the asking prompt's turn: the questions came, the run is interactive from here
        // (the mode question below may switch it on again).
        if (pending) { pending.autonomous = false; pending = null; state = false; }
        // A yes/no to the mode question decides by yes; an answer to any other question is read
        // like a prompt, since the operator may order the run inside it (2026-10-30, macOS instance:
        // "yes, work through them autonomously" to "shall I handle them?" set nothing). The mode
        // question is read from its question sentence (asksMode), not from any on-word in the text.
        if (asksMode(w.on, q)) state = w.yes.test(a) && !w.off.test(a);
        else if (w.off.test(a)) state = false;
        else if (ordersOn(w.on, a)) state = true;
        else continue;
        out.push({ text: a, autonomous: state, queued: false, asks: false, answer: true, ordered: state,
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
    if (intent && typeof intent.asks_open === 'boolean') {
      asks = intent.asks_open && !intent.mode_on;
      off = intent.mode_off;
      if (!off && !asks && intent.mode_on) state = ordered = true;
    } else {
      asks = w.ask.test(own);
      off = w.off.test(own);
      if (!off && !asks && ordersOn(w.on, own)) state = ordered = true;
    }
    // "What is open for me?" leaves the run when the questions COME (operator 2026-11-03, translated: "why did you
    // just switch to interactive? no questions came. either the questions, or stay autonomous"). That rule is the
    // OUTCOME of the turn, not a condition before it: the asking prompt opens a `window` - in its turn the question
    // tool and the dialogs pass (autonomous-gate.cjs) -, a question answered there ends the run (above), and a turn
    // that asks nothing leaves it autonomous. Until 2026-11-23 the run ended only when a derived count of open
    // operator decisions was above 0; the count read what the agent itself had filed, and three incidents on the
    // macOS instance (2026-11-05, -18, -23) each failed on one more form it did not read - the question tool was
    // refused on the operator's own request. Replay over that instance's history: 14 such prompts refused, in 6 the
    // count was 0, and the widened count would have caught 2 of them. What is filed as open stays a DUTY: the
    // presentation gate holds a turn that asked nothing while a decision is open.
    let window = false;
    if (off) state = false;
    else if (asks && state) window = true;
    // An order that pre-authorizes a later question opens the window now and keeps it open across the turns that
    // follow (timers, peers, background tasks) until a question is answered or the operator writes again.
    const deferred = !off && state && deferAsk(w.defer, own);
    if (pending && pending.deferred && (off || asks || ordered || deferred)) closeWindow(true);
    if (deferred) window = true;
    const row = { text, autonomous: state, queued: Boolean(queued), asks, answer: false, by: intent ? 'model' : 'words',
      ordered, window, deferred, at: Date.parse(d.timestamp) || null };
    out.push(row);
    if (window) pending = row;
  }
  // a deferred window still open at the end, though later prompts came (they add to the work, they do not re-order it)
  out.deferredOpen = Boolean(pending && pending.deferred && pending.window);
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

module.exports = { autonomousMode, promptModes, words, initialState, asksMode, intents, intentFor, intentExact, modelSays, answers, promptText, HOOK_ECHO, askWindow, modeReason };


if (require.main === module) {
  const [tp, cwd, flag] = process.argv.slice(2);
  // `--window`: the third verdict - `window` while the run is autonomous and the asking prompt's turn is open.
  if (flag === '--window' && autonomousMode(tp || '', cwd) && askWindow(tp || '', cwd)) { console.log('window'); return; }
  // scripts/pattern-cases.py runs this on a transcript that ENDS at the prompt under test and names its own open count
  // (AUTONOMOUS_OPEN_FOR_OPERATOR, default 1): a case tests how the WORDS are read. A prompt read as asking what is
  // open shows there as `interactive` when something is open (the turn must ask), as `autonomous` with 0 - the
  // verdicts every instance's case data was written against.
  const caseOpen = /^\d+$/.test(process.env.AUTONOMOUS_OPEN_FOR_OPERATOR || '') && Number(process.env.AUTONOMOUS_OPEN_FOR_OPERATOR) > 0;
  console.log(autonomousMode(tp || '', cwd) && !(caseOpen && askWindow(tp || '', cwd)) ? 'autonomous' : 'interactive');
}
