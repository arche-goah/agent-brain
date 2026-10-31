#!/usr/bin/env node
/**
 * Stop hook: the first reply of a session relays the open points the bootup listed —
 * split by WHO has to act, with one OK for what the agent can do itself.
 *
 * WHY (operator correction 2026-10-07, proving brain): the bootup named nine open
 * shared-memory requests and six open PRs; the first reply said "nine older requests,
 * nothing new since the last start" and named none. The data side was already fixed
 * (open requests ignore the cursor); the relay side had no carrier at all — a rule in
 * prose ("relevance beats completeness") even covered the omission. The operator's rule:
 * every unhandled point that concerns us MUST be reported, and attention rises with every
 * repeat, never falls. And: it has to hold on Windows and macOS for everyone.
 * Refined the same day — a wall of items intimidates, and a session usually starts for
 * another reason. The first reply therefore carries:
 *   - the number of items the agent can answer or handle itself (class `ai`), and ONE
 *     question whether to go ahead — the agent starts none of them without that OK;
 *   - the number of items that need the operator (class `human`): up to three, each one
 *     named (a short bullet: what, who needs what); more than three, the offer to list them;
 *   - the number of items of a class the operator approved once for good (class `standing`,
 *     instance data .claude/rules/open-items-standing.json, full-audit 2026-10-15 on the
 *     Windows instance) and that they are handled or under way — no question needed; asking
 *     anyway is not wrong and passes here too. An `ai` item without such a class still needs
 *     the question;
 *   - that items reported before are STILL open (repeat wording), when any are;
 *   - "nothing open", a NOT-checked source, and the parked line, when the bootup has them.
 *
 * What it reads — the TRANSCRIPT, not a state file, so it also sees a bootup that never
 * arrived: the latest SessionStart record of `core/helpers/session-bootup.sh`.
 *   - startup/resume bootup present: parse the `open for us:` block written by
 *     scripts/open-items.py. Classes come from the block; an item printed `?` counts as
 *     classified once `.claude-state/open-items-class.json` holds it (the agent runs
 *     `open-items.py --classify` in the same turn). Anything still unclassified blocks.
 *   - bootup cancelled (hook timeout) or missing: block — the list did not arrive and has
 *     to be fetched by hand. Measured on one macOS brain: 38 of these cancellations, the
 *     last on 2026-09-23; a Windows brain reported the same.
 *   - bootup present but without the block (older core, or the block crashed): block.
 *   - compaction (SessionStart:compact): never fires — that is the same session.
 * Only the FIRST turn after the bootup is checked: one real operator prompt since then.
 * Re-issued answers (stop_hook_active) pass, as with every gate.
 * Frequency design: at most once per session start or resume, no turn cooldown — the
 * whole gate is one turn wide, a cooldown would only switch it off.
 *
 * The opening question is WANTED here, so `firstTurnOwnsQuestion()` is exported for
 * stoppen-gate: on exactly this turn the closing question belongs to this gate.
 *
 * Language: a PR is named by `#<n>`, a count as digits; a request by its date, its topic
 * words (file slug), or its age in days. The phrase patterns are English built-ins; an
 * instance adds its own language as DATA in .claude/rules/open-items.json (`<key>_patterns`,
 * lists of regexes; keys: nothing, failed, parked, offer, repeat, age_unit, goahead, handled,
 * ask, wait, ours).
 * Items printed `[...|wait]` (the move is someone else's, or a dated wait) need no relay.
 *
 * Output: {"decision":"block","reason":"... Missing: <what>"} — the dispatcher compresses
 * on "Missing:". Fails open on unreadable input: a crashed gate must not stop a session.
 */
const fs = require('fs');
const path = require('path');
const { isSkillExpansion, isAgentOrigin, isTranscriptRecord, queuedHumanPrompt } = require('./turn-kind.cjs');
const { autonomousMode } = require('./autonomous-mode.cjs');
const { PRE_COMMIT, closeOpenEnds } = require('./close-stamp.cjs');

const MAX_BYTES = 16 * 1024 * 1024; // the first turn sits at the top; a huge file is past it
const BOOTUP = /session-bootup\.sh/;
const NOT_A_PROMPT = /^\s*(Stop hook feedback|<task-notification|<system-reminder)/;
const HUMAN_LIST_MAX = 3;
const BUILTIN = {
  nothing: ['\\bnothing (is )?open\\b', '\\bno open (items|points|requests)\\b'],
  failed: ['\\bnot checked\\b', '\\bfailed\\b'],
  parked: ['\\bparked\\b'],
  offer: ['\\b(shall|should) i\\b[^?\\n]{0,160}\\?', '\\bdo you want me to\\b[^?\\n]{0,160}\\?',
    '\\bwant (me to|them|it) [^?\\n]{0,160}\\?'],
  repeat: ['\\balready reported\\b', '\\breported (before|in \\d+|\\d+ times)\\b', '\\bstill open\\b'],
  // the unit after a number that makes it an age ("32 days")
  age_unit: ['days?\\b', 'd\\b'],
  // an operator prompt that already orders the work: no shall-I question needed
  goahead: ['\\bgo ahead\\b', '\\b(handle|do|finish|work through) (it all|them all|all of (it|them)|everything)\\b'],
  // items under a standing approval: reported as done or under way
  handled: ['\\b(handled|handling|answered|answering|done|in progress|under ?way|working on|taken care of|taking care of)\\b'],
  // an item said to be someone else's move (the relabel check below)
  // an operator prompt that asks whether anything is still open — the answer names what is ours
  ask: ['\\banything (still |else )?(open|left|pending)\\b', '\\b(are we|is everything|all) (done|finished|closed)\\b'],
  // (not "the other side": that also describes a peer's own activity — fixture 19a)
  wait: ['\\bwait(s|ing)? (on|for)\\b', '\\bwith (the )?others\\b', '\\btheir (move|turn)\\b'],
  // a wait line that keeps the item ours or hands it to the operator, not to someone else
  // ("still ours - waiting for CI, then I merge it", "waits for your decision")
  ours: ['\\bstill ours\\b', '\\bours\\b', "\\bI(?: will|'ll)? (merge|handle|do|finish|answer)\\b",
    '\\bwait(s|ing)? (on|for) (you|your)\\b'],
};

/** n -> RegExp matching "<n> <day unit>"; units are built-ins plus instance `age_unit_patterns`. */
function ageMatcher(cwd) {
  const units = patterns(cwd, 'age_unit').source;
  return (n) => new RegExp(`(?<!\\d)${n}\\s*(?:${units})`, 'iu');
}

function patterns(cwd, key) {
  const list = [...BUILTIN[key]];
  try {
    const extra = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'open-items.json'), 'utf8'));
    for (const s of extra[`${key}_patterns`] || []) {
      try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(list.join('|'), 'iu');
}

function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content)) return null;
  if (msg.content.some((b) => b.type === 'tool_result')) return null;
  const t = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
  return t || null;
}

// The harness stores a hook output over its limit (about 10 KB) in a file and keeps only a
// preview in the transcript: "<persisted-output> Output too large (10.3KB). Full output saved
// to: <path> Preview (first 2KB): …". The "open for us:" block lies past that cut, so the gate
// read "no open-items block" at EVERY turn end of such a session, with no reply that could
// satisfy it (measured 2026-10-22 on the second macOS instance, bootup 10.3 KB). The file the
// preview names is the whole output — read it; an unreadable file leaves the preview as is.
// The path runs to the end of its line or to the " Preview (first" that may follow on the same
// line — NOT to the next space: a Windows profile name carries one (`C:\Users\First Last\…`),
// and `\S+` cut it there (measured 2026-10-25 by the Windows instance on its real transcript;
// trap class OS-10).
const PERSISTED = /Full output saved to:\s*([^\r\n]+?)\s*(?:$|\sPreview \(first)/m;
function persistedText(text) {
  const m = PERSISTED.exec(text);
  if (!m) return text;
  try { return fs.readFileSync(m[1], 'utf8'); } catch (e) { return text; }
}

/** One pass over the transcript: the last bootup record, prompts and reply after it. */
function readTurn(tp) {
  if (!tp || fs.statSync(tp).size > MAX_BYTES) return null;
  const raw = fs.readFileSync(tp, 'utf8');
  let boot = null; // { kind: 'ok'|'cancelled', source, text, ms }
  let prompts = 0;
  let first = '';
  let total = 0;
  let reply = [];
  let last = []; // the running turn: every reply since the newest operator prompt
  let lastCmds = []; // ...and its shell commands (is it the session-close turn?)
  let lastPrompt = '';
  let since = ''; // when the running turn began (the close stamp must be no older)
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const att = d.attachment;
    if (att && att.hookEvent === 'SessionStart' && BOOTUP.test(att.command || '')) {
      const source = String(att.hookName || '').split(':')[1] || '';
      if (att.type === 'hook_cancelled') boot = { kind: 'cancelled', source, ms: att.durationMs };
      else if (att.type === 'hook_success') boot = { kind: 'ok', source, text: persistedText(String(att.content || att.stdout || '')) };
      else continue;
      prompts = 0; reply = []; first = ''; last = []; lastCmds = [];
      continue;
    }
    // A message typed mid-turn (queued_command, turn-kind #139) is the operator's WORD - it can be
    // the "is anything open?" this gate answers - but no turn BOUNDARY: the reply buffer stays.
    const queued = queuedHumanPrompt(d);
    if (queued) { lastPrompt = queued; continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      if (isSkillExpansion(d) || isAgentOrigin(d)) continue;   // a loaded skill's text or another agent's report is no second prompt
      const t = promptText(msg);
      if (t !== null && !NOT_A_PROMPT.test(t)) { prompts++; total++; last = []; lastCmds = []; lastPrompt = t; since = d.timestamp || ''; if (prompts === 1) first = t; }
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) last.push(b.text);
        else if (b.type === 'tool_use' && b.input && typeof b.input.command === 'string') lastCmds.push(b.input.command);
      }
    }
    if (msg.role === 'assistant' && prompts === 1 && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) reply.push(b.text);
        // A question through the question tool reaches the operator just like text, and the
        // operator rule of 2026-10-15 asks for exactly that tool — its questions count.
        else if (b.type === 'tool_use' && b.name === 'AskUserQuestion' && b.input && Array.isArray(b.input.questions)) {
          for (const q of b.input.questions) if (q && typeof q.question === 'string') reply.push(q.question);
        }
      }
    }
  }
  return { boot, prompts, total, first, reply: reply.join('\n'), last: last.join('\n'), lastCmds, lastPrompt, since };
}

/**
 * True only on the turn where the opening question is REQUIRED: the first reply after a
 * startup/resume bootup whose list has items the agent can handle, or more operator items
 * than get listed. Anywhere else stoppen-gate judges a closing question as always —
 * measured: a wider version (any first turn) silenced every stoppen-gate fixture.
 */
function firstTurnOwnsQuestion(tp) {
  try {
    const t = readTurn(tp);
    if (!t || !t.boot || t.boot.kind !== 'ok' || t.boot.source === 'compact' || t.prompts !== 1) return false;
    const blk = parseBlock(t.boot.text);
    if (!blk) return false;
    const human = blk.items.filter((it) => it.cls === 'human').length;
    return blk.items.some((it) => it.cls === 'ai' || it.cls === '?') || human > HUMAN_LIST_MAX;
  } catch (e) { return false; }
}

/**
 * Topics on which a rule ORDERS a question to the operator: every bootup line that says
 * "ask the operator" (e.g. "!! brain-scan DUE: ... — ask the operator, then run it").
 * Returned as lowercase topic keys (the line's label before ':', a trailing ALL-CAPS status
 * word dropped — "brain-scan", "update available"), for stoppen-gate: a closing
 * question about such a topic is the rule being followed, not a disguised stop. Measured
 * 2026-10-09: stoppen-gate blocked exactly that brain-scan question on a proving brain.
 * Any turn of the session, not only the first — the question may come after other work.
 */
function mandatedTopics(tp) {
  try {
    const t = readTurn(tp);
    if (!t || !t.boot || t.boot.kind !== 'ok') return [];
    const out = [];
    for (const l of t.boot.text.split('\n')) {
      if (!/\bask the operator\b/i.test(l)) continue;
      const m = /^(?:!!\s*)?([^:]+):/.exec(l.trim());
      const topic = m ? m[1].replace(/\s+[A-Z]{2,}$/, '').trim() : '';
      if (topic) out.push(topic.toLowerCase());
    }
    return out;
  } catch (e) { return []; }
}

/** Parse the open-items block out of the bootup text. */
function parseBlock(text) {
  const lines = text.split('\n');
  const head = lines.findIndex((l) => /^open for us: \d+/.test(l));
  if (head < 0) return null;
  const items = [];
  let failed = false;
  let parked = false;
  let nothing = false;
  for (const l of lines.slice(head + 1)) {
    if (/^!! open for us: .* NOT checked/.test(l)) { failed = true; continue; }
    if (/^!! open for us:/.test(l)) continue;
    if (!l.startsWith('- ')) break;
    const repeat = /!! reported in \d+ sessions/.test(l);
    let m;
    if ((m = /^- \[PR\|(\w+|\?)\] \S+ (\S+?)#(\d+) /.exec(l))) {
      items.push({ cls: m[1], ref: `${m[2]}#${m[3]}`, key: `${m[2]}#${m[3]}`, num: m[3], repeat });
    } else if ((m = /^- \[request\|(\w+|\?)\] (\d{4})-(\d{2})-(\d{2}) (.+?) — (?:[^:]+: (.+?) — )?/.exec(l))) {
      const ref = m[5];
      const base = ref.split('/').pop();
      // A LOG entry has no file name to classify by: its ref IS the id --classify takes
      // (`<area>/LOG@<date>#<n>`), so the gate names it whole.
      const shown = /^LOG@/.test(base) ? ref : `${m[2]}-${m[3]}-${m[4]} ${base}`;
      // `id` is the key --classify stores under; the class file is read by it too, or a LOG
      // entry classified mid-session stayed `?` for the gate (measured 2026-10-12).
      items.push({ cls: m[1], ref: shown, key: ref, id: shown,
        base, date: [m[2], m[3], m[4]], words: topicWords(/\.md$/.test(base) ? base : (m[6] || '')), repeat });
    } else if ((m = /^- \[session\|(\w+|\?)\] (\d{4})-(\d{2})-(\d{2}) (session\/\S+) — (?:[^:]+: (.+?) — )?/.exec(l))) {
      // A past session that ended without session-close, or a failed session start
      // (scripts/session-audit.py). Named by its DATE (or age): every such line shares the
      // same words ("session", "close"), so words would let one sentence pass for all.
      items.push({ cls: m[1], ref: `${m[2]}-${m[3]}-${m[4]} ${m[5]}`, key: m[5], base: m[5],
        date: [m[2], m[3], m[4]], words: [], repeat });
    } else if ((m = /^- \[wake\|(\w+|\?)\] (\d{4})-(\d{2})-(\d{2}) (.+?) — /.exec(l))) {
      // A parked domain whose pausing party moved again: an operator item, named by the
      // domain or the date like a request.
      items.push({ cls: m[1], ref: `parked domain ${m[5]}`, key: `wake:${m[5]}`, base: `wake:${m[5]}`,
        date: [m[2], m[3], m[4]], words: topicWords(m[5]), repeat });
    } else if ((m = /^- \[ledger\|(\w+|\?)\] (?:(\d{4})-(\d{2})-(\d{2}))? ?(\S+) — (?:[^:]+: (.+?) — )?/.exec(l))) {
      // An open entry of a registered work ledger (open-items.py ledgers()): named by its date,
      // its id or its title words. Undated entries are named by words alone.
      items.push({ cls: m[1], ref: m[5], key: `ledger:${m[5]}`, id: `ledger:${m[5]}`, base: m[5],
        date: m[2] ? [m[2], m[3], m[4]] : null, words: topicWords(`${m[5]} ${m[6] || ''}`), repeat });
    } else if (/^- \[parked\]/.test(l)) parked = true;
    else if (/^- nothing open/.test(l)) nothing = true;
  }
  return { items, failed, parked, nothing };
}

// Words that name a request's KIND, not its topic — every request carries them. English
// built-ins; an instance adds its language as DATA (`generic_words` in open-items.json).
const GENERIC = ['request', 'question', 'answer', 'reply', 'receipt', 'from', 'with'];

/** Topic words of a request: its file slug (or, for a LOG-only request, its own words). */
function topicWords(s) {
  return String(s).toLowerCase().replace(/\.md$/, '').replace(/\d{4}-\d{2}-\d{2}/g, ' ')
    .split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 4 && !/^\d+$/.test(w));
}

function genericWords(cwd) {
  const set = new Set(GENERIC);
  try {
    const extra = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'open-items.json'), 'utf8'));
    for (const w of extra.generic_words || []) set.add(String(w).toLowerCase());
  } catch (e) { /* built-ins only */ }
  return set;
}

/**
 * A request counts as named by its date, by its topic words, or by its age. Measured
 * 2026-10-09: a first reply named all eleven items in plain words with their AGE
 * ("open for 32 days") and was blocked, because only a date counted — the gate pushed
 * replies toward file names and dates, against the plain-words rule.
 */
function named(item, reply, ageRx, generic) {
  if (item.num) return new RegExp(`#${item.num}(?!\\d)`).test(reply);
  if (!item.date) {
    const low = reply.toLowerCase();
    const words = (item.words || []).filter((w) => !generic.has(w));
    return reply.includes(item.base) || (words.length > 0 && words.filter((w) => low.includes(w)).length >= Math.min(2, words.length));
  }
  const [y, mo, d] = item.date;
  if (reply.includes(`${y}-${mo}-${d}`) || new RegExp(`(?<!\\d)${mo}-${d}(?!\\d)`).test(reply)
    || new RegExp(`(?<!\\d)${Number(d)}\\.\\s?${Number(mo)}\\.|(?<!\\d)${d}\\.${mo}\\.`).test(reply)) return true;
  const low = reply.toLowerCase();
  const words = (item.words || []).filter((w) => !generic.has(w));
  const hit = words.filter((w) => low.includes(w)).length;
  if (words.length && hit >= Math.min(2, words.length)) return true;
  // Age in days, local calendar, one day of slack either way (time zones, midnight).
  const age = Math.round((Date.now() - new Date(`${y}-${mo}-${d}T12:00:00`).getTime()) / 86400000);
  return [age - 1, age, age + 1].some((n) => n >= 0 && ageRx(n).test(reply));
}

const hasNumber = (n, text) => new RegExp(`(?<!\\d)${n}(?!\\d)`).test(text);

/**
 * Any turn, not only the first: a reply may not move an item the list prints as OURS onto
 * someone else's plate in prose. Measured 2026-10-26 (Windows instance): one own PR stood as
 * "[PR|ai] … still ours" at three session starts; at each close, and in answers to the
 * operator's "is anything still open?", the reply put it under "open (with others) — waits on
 * the collaborator's read", following a superseded line of that repo's own rules. The operator
 * closed on that answer each time. The list was right; the prose overrode it with nothing on
 * record. A wait counts only as data: the PR's `waiting-until:` line, the instance's `waiting`
 * map in open-items.json, or a fresh open-items.py run that now prints the item as waiting
 * (its record in .claude-state/open-items-seen.json). A bullet under a heading that says
 * "with others" says it too.
 */
function relabelled(t, cwd, sessionId) {
  if (!t.boot || t.boot.kind !== 'ok' || !t.last) return null;
  const blk = parseBlock(t.boot.text);
  if (!blk) return null;
  let waits = {};
  let seen = {};
  try { waits = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'open-items.json'), 'utf8')).waiting || {}; } catch (e) { /* none */ }
  try { seen = JSON.parse(fs.readFileSync(path.join(cwd, '.claude-state', 'open-items-seen.json'), 'utf8')).items || {}; } catch (e) { /* none */ }
  const keys = (it) => [it.id, it.key, it.base].filter(Boolean);
  const recorded = (it) => keys(it).some((k) => waits[k] || (seen[k] && seen[k].wait));
  // A later open-items.py run that no longer lists the item: closed meanwhile (a merged PR).
  const gone = (it) => Object.keys(seen).length > 0 && !keys(it).some((k) => seen[k]);
  const ours = blk.items.filter((it) => ['ai', 'human', 'standing'].includes(it.cls) && !recorded(it) && !gone(it));
  if (!ours.length) return null;
  const ageRx = ageMatcher(cwd);
  const generic = genericWords(cwd);
  // `human` items are the operator's move already: "waits for your decision" is the truth, not a
  // relabel (false block measured 2026-10-26 on the Windows instance, agent-brain#120). They stay
  // in `ours` for the close check below — the operator must still hear them.
  const movable = ours.filter((it) => it.cls !== 'human');
  const waitRx = patterns(cwd, 'wait');
  const oursRx = patterns(cwd, 'ours');
  // Blocking direction: named only by `#n`, a date or the exact file — the lenient first-reply
  // matcher read "2D" in "the worlds 2D, 3D" as a request two days old (same measurement).
  const strict = (it, l) => (it.num ? new RegExp(`#${it.num}(?!\\d)`).test(l)
    : (it.date && l.includes(it.date.join('-'))) || (it.base && l.includes(it.base)));
  const bad = [];
  let head = false;
  for (const l of t.last.split('\n')) {
    const under = /^\s+[-*\d]/.test(l);
    if (!under) head = waitRx.test(l) && !oursRx.test(l) && /:[*_]*\s*$/.test(l);
    if ((!waitRx.test(l) || oursRx.test(l)) && !(under && head)) continue;
    for (const it of movable) if (!bad.includes(it) && strict(it, l)) bad.push(it);
  }
  if (bad.length) {
    return `This reply puts ${bad.map((it) => it.ref).join(', ')} with someone else, but the session start lists it as ours and no wait is on record. Say it as ours (do it, or ask), or record the wait as data first: a \`waiting-until: <date>: <why>\` line in the PR body, the \`waiting\` map in .claude/rules/open-items.json, or a rerun of open-items.py when the other side's move is on record. Missing: wait record for ${bad.map((it) => it.ref).join(', ')}`;
  }
  // The close report, the answer to "is anything still open?", and every "nothing open" name
  // what is still ours — the operator shuts down on that answer (measured 2026-10-25: asked
  // "surely all closed, final?", the reply said "persisted, you can shut down" and named none).
  // The first turn has its own check below.
  if (t.prompts === 1) return null;
  const closing = (t.lastCmds || []).some((c) => PRE_COMMIT.test(c));
  const asked = patterns(cwd, 'ask').test(t.lastPrompt || '');
  if (!closing && !asked && !patterns(cwd, 'nothing').test(t.last)) return null;
  // An item this close already carries as an `open end:` line of its session-log entry
  // (close-stamp.cjs, skill session-close step 4) is named — on record, where the next session
  // takes it over. Measured 2026-10-28: a close listed its own items as open ends and the gate
  // still blocked the close report for them.
  const ends = closing ? closeOpenEnds(cwd, { sessionId, since: t.since,
    calls: (t.lastCmds || []).map((cmd) => ({ cmd })) }) : null;
  const endText = (ends || []).join('\n');
  const left = ours.filter((it) => !named(it, t.last, ageRx, generic)
    && !(endText && named(it, endText, ageRx, generic)));
  if (!left.length) return null;
  return `${closing ? 'The close report' : asked ? 'The answer to "is anything open?"' : 'This reply says nothing is open, but it'} leaves out what the session start lists as ours and is still open — the operator shuts down on this answer. Name each as ours (with where it stands), or record its wait as data first. Missing: ${left.map((it) => it.ref).join(', ')}`;
}

function judge(input) {
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const t = readTurn(input.transcript_path);
  if (!t) return null;
  if (!t.boot) {
    // No bootup record at all: only the very first turn of a session is ours to judge.
    if (t.total !== 1) return null;
    return 'The session-start output never arrived in this session, so the open points were not shown. Run `python3 core/scripts/open-items.py --owner <org>` (or `python`) and report them. Missing: bootup';
  }
  const moved = relabelled(t, cwd, input.session_id);
  if (moved) return moved;
  if (t.boot.source === 'compact' || t.prompts !== 1) return null;
  if (t.boot.kind === 'cancelled') {
    return `The session-start hook was cancelled after ${Math.round((t.boot.ms || 0) / 1000)} s — the open points never arrived. Run \`python3 core/scripts/open-items.py --owner <org>\` (or \`python\`) and report them. Clear why in THIS session too: time \`bash core/helpers/session-bootup.sh\`, name the slow part, fix or report it, then \`session-audit.py --ack start:<this session id>\`. Missing: bootup (cancelled)`;
  }
  const blk = parseBlock(t.boot.text);
  if (!blk) {
    return 'The session-start output carries no "open for us:" block (older core, or the block failed) — the open points are unknown. Run `python3 core/scripts/open-items.py --owner <org>` and report them. Missing: open-items block';
  }

  // An item printed `?` is classified once the agent's class file holds it.
  let store = {};
  try { store = JSON.parse(fs.readFileSync(path.join(cwd, '.claude-state', 'open-items-class.json'), 'utf8')); } catch (e) { /* none yet */ }
  for (const it of blk.items) {
    if (it.cls !== '?') continue;
    const own = (it.id && store[it.id]) || store[it.key] || (it.base && store[it.base]);
    if (own && (own.class === 'ai' || own.class === 'human')) it.cls = own.class;
  }
  const unclassified = blk.items.filter((it) => it.cls === '?');
  if (unclassified.length) {
    return `Classify every open item once — can the agent answer/handle it (ai), or does it need the operator (human)? Run \`python3 core/scripts/open-items.py --classify '<id>=ai|human:<why>'\`, then report. Missing: class for ${unclassified.map((it) => it.ref).join(', ')}`;
  }

  const text = t.reply;
  // A failed start or an unclosed session is cleared by reading its transcript — no OK asked,
  // no question to the operator (operator 2026-10-15); the reply names each with its cause.
  const cleared = blk.items.filter((it) => it.cls === 'ai' && /^session\//.test(it.key));
  const ai = blk.items.filter((it) => it.cls === 'ai' && !cleared.includes(it));
  const human = blk.items.filter((it) => it.cls === 'human');
  const missing = [];
  if (cleared.length) {
    const ageRx = ageMatcher(cwd);
    const generic = genericWords(cwd);
    for (const it of cleared) if (!named(it, text, ageRx, generic)) missing.push(it.ref);
  }
  if (ai.length) {
    if (!hasNumber(ai.length, text)) missing.push(`count of items you can handle (${ai.length})`);
    // The operator's prompt may already be the go-ahead ("work through everything") — then
    // asking again is a disguised stop; the count still has to be said.
    // An autonomous order is a go-ahead too, and there the question would be the very stop the
    // rule forbids (autonomous-mode.cjs; this gate judges the first turn only, so the newest
    // prompt is the first one).
    if (!patterns(cwd, 'offer').test(text) && !patterns(cwd, 'goahead').test(t.first)
      && !autonomousMode(input.transcript_path, cwd)) missing.push('one question whether to handle them');
  }
  // A standing approval replaces the question with a report; asking anyway is not wrong.
  const standing = blk.items.filter((it) => it.cls === 'standing');
  if (standing.length) {
    if (!hasNumber(standing.length, text)) missing.push(`count of items handled under a standing approval (${standing.length})`);
    if (!patterns(cwd, 'handled').test(text) && !patterns(cwd, 'offer').test(text)) {
      missing.push('that the standing-approval items are handled or under way');
    }
  }
  if (human.length) {
    if (!hasNumber(human.length, text)) missing.push(`count of items that need the operator (${human.length})`);
    if (human.length <= HUMAN_LIST_MAX) {
      const ageRx = ageMatcher(cwd);
      const generic = genericWords(cwd);
      for (const it of human) if (!named(it, text, ageRx, generic)) missing.push(it.ref);
    } else if (!patterns(cwd, 'offer').test(text)) {
      missing.push('the offer to list the operator items');
    }
  }
  if (blk.items.some((it) => it.repeat) && !patterns(cwd, 'repeat').test(text)) {
    missing.push('that some were reported before and are still open');
  }
  if (blk.failed && !patterns(cwd, 'failed').test(text)) missing.push('failed source');
  if (blk.parked && !patterns(cwd, 'parked').test(text)) missing.push('parked line');
  if (blk.nothing && !patterns(cwd, 'nothing').test(text)) missing.push('"nothing open"');
  if (missing.length === 0) return null;
  const shown = missing.length > 6 ? `${missing.slice(0, 6).join(', ')} +${missing.length - 6} more` : missing.join(', ');
  return `First reply leaves out the open points from the session start — split by who acts: "n I can handle, shall I?" + "n need you" (up to ${HUMAN_LIST_MAX} named, more offered) + "n handled under a standing approval" when the list has such items; repeats said. Missing: ${shown}`;
}

module.exports = { firstTurnOwnsQuestion, mandatedTopics };

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(data); } catch (e) { process.exit(0); }
    if (input.stop_hook_active) process.exit(0);
    let reason = null;
    try { reason = judge(input); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify({ decision: 'block', reason }));
    process.exit(0);
  });
}
