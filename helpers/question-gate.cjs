#!/usr/bin/env node
/**
 * Stop hook + small CLI: a question to the operator stays open until it is RESOLVED by an
 * act, not until the chat scrolls past it.
 *
 * The class (operator, 2026-10-09: "das geht oft unter bei multiplen tasks, wenn du einen
 * vorschlag machst"): in one session two proposals ended as questions ("shall I build the
 * clock check as a PR?", "run the overdue brain-scan now or later?"). Background events
 * arrived, other work followed, the operator's next prompts were about something else —
 * and both questions were gone. Nobody had declined them; they had simply scrolled away.
 * Same shape as the unwatched reaction (watch-gate.cjs): an omission leaves no artifact.
 * The core had a carrier for the agent's PROMISES (commitments.py) and for requests from
 * OTHER instances (open-items.py), none for the agent's own open QUESTIONS.
 *
 * Detection: every reply the operator saw (an assistant text right before a user record —
 * operator prompt, notification or hook echo — or the reply this Stop ends) is split into
 * sentences; a sentence that ends in "?" outside code and quotes AND matches a question
 * pattern (English built-ins; other languages as instance data
 * `.claude/rules/open-questions.json` {"question_patterns": [...]}) is a question to the
 * operator. Id = hash of the normalised sentence.
 *
 * Gate: block when a question asked BEFORE the operator's latest prompt is still `open` in
 * `.claude-state/open-questions.json` — the operator has had the chance to answer, so this
 * reply is where it gets settled. Settled means one call:
 *   node core/helpers/question-gate.cjs resolve <id>=answered|dropped|unanswered|deferred:<words>
 * Two kinds of "not decided", never one word for both (operator decision 2026-10-10):
 * - `deferred` = the OPERATOR postponed it in their own words ("later", "not now", a date).
 *   The note must quote those words - without them the status is refused. Listed at every
 *   session start, not raised again inside the session (a postponed point is said once).
 * - `unanswered` = the operator replied without addressing it. That is not a postponement:
 *   listed at every session start AND asked again where it matters, louder each time.
 *   Measured 2026-10-10 (Windows instance): questions the operator had simply not answered
 *   were filed as `deferred` - the gate itself offered no other word for "still open".
 * Who closes (operator decision 2026-10-11): the AGENT resolves its own question as
 * `answered` once its work has answered it (measured, built, read instead of waited); the
 * operator's words are needed only for `deferred`. The call needs the template permission
 * `Bash(node core/helpers/*)` — without it the harness prompts, or its classifier refuses the
 * call as a workaround (measured 2026-10-11, Windows); hook-coverage.py reports a brain that
 * lacks it.
 * Questions of the reply being ended are recorded, never blocked — the operator has not
 * seen them yet. Once per turn; a re-issue passes. Fails open without a transcript.
 *
 * Orphans and evidence (issue #269, operator 2026-10-11: "there is no active session any more
 * for 'which way do you want' — nobody feels responsible, that is a core bug"): a record keeps
 * the TRANSCRIPT it came from, so any later session can read what the operator said after the
 * question. `deferred:<words>` is accepted only when those words stand verbatim in an operator
 * prompt after the question in that transcript — a note in the agent's own words is refused,
 * and so is a deferral nobody can check (transcript gone). `adopt <id>` prints the operator's
 * prompts after the question (bounded) and marks the record adopted, so the session that
 * starts next settles it from evidence instead of leaving it to the session that no longer
 * exists; `list` names that call for every record not settled by its own session.
 *
 * The close turn (coherence scan 2026-10-15, P1-2): skill `session-close` carries an open
 * question to the next session instead of asking it again while the operator leaves. A close
 * stamp of this session and turn (close-stamp.cjs) passes exactly the questions the close's
 * session-log entry lists as an open end, by id or by sentence; an unlisted one still blocks.
 * The record stays `open`, so the next session start lists it.
 *
 * Fixture: scripts/test-question-gate.sh.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { isNotification, isTranscriptRecord } = require('./turn-kind.cjs');
const { closeOpenEnds, listed } = require('./close-stamp.cjs');

// Own echo: legacy token or, behind the dispatcher, the label line (stop-echo.cjs).
const { ownEcho, declare } = require('./stop-echo.cjs');
let OWN_ECHO = /QUESTION-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const STATUSES = new Set(['open', 'answered', 'dropped', 'deferred', 'unanswered']);
const BUILTIN = [
  '\\bshall I\\b', '\\bshould I\\b', '\\bdo you want\\b', '\\bwant me to\\b',
  '\\bwould you like\\b', '\\b(ok|okay) (to|if I)\\b', '\\bgo ahead\\b', '\\bnow or later\\b',
  '\\bor (rather|later|not)\\b', '\\bwhich (one|option|do you)\\b',
];

function root(cwd) { return process.env.CLAUDE_PROJECT_DIR || cwd || process.cwd(); }
function statePath(r) { return path.join(r, '.claude-state', 'open-questions.json'); }
function load(r) { try { return JSON.parse(fs.readFileSync(statePath(r), 'utf8')); } catch (e) { return {}; } }
function save(r, s) {
  fs.mkdirSync(path.dirname(statePath(r)), { recursive: true });
  fs.writeFileSync(statePath(r), JSON.stringify(s, null, 2) + '\n');
}

function questionRegex(r) {
  const list = [...BUILTIN];
  try {
    const extra = JSON.parse(fs.readFileSync(path.join(r, '.claude', 'rules', 'open-questions.json'), 'utf8'));
    for (const s of extra.question_patterns || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip */ } }
  } catch (e) { /* no instance file — English only */ }
  return new RegExp(list.join('|'), 'iu');
}

function stripQuoted(t) {
  return t.replace(/```[\s\S]*?```/g, ' ').replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ').replace(/“[^”]*”/g, ' ').replace(/"[^"\n]*"/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

function sentences(text) {
  // Emphasis markers around a question ("**shall I?**") would hide the final "?".
  return stripQuoted(text).replace(/\*\*|__/g, '').split(/(?<=[.!?])\s+|\n+/).map((s) => s.replace(/^[\s*\-\d.)]+/, '').trim())
    .filter(Boolean);
}

function questions(text, rx) {
  return sentences(text).filter((s) => s.endsWith('?') && rx.test(s));
}

/**
 * The text right before a question, so a later session knows what it is about. Measured
 * 2026-10-12 (Windows instance): "Do you want it, and when?" stood at three session starts
 * with nothing else; the operator had decided it the same day it was asked (the ledger held
 * the order), but no session could tell which topic the bare sentence meant, so none closed it.
 */
function contextOf(text, q) {
  const all = sentences(text);
  const i = all.indexOf(q);
  return i > 0 ? all.slice(0, i).join(' ').slice(-160).trim() : '';
}

function qid(q) { return crypto.createHash('sha1').update(q.toLowerCase().replace(/\s+/g, ' ')).digest('hex').slice(0, 8); }

function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b.type === 'tool_result')) return null;
  return msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n') || null;
}

/** Shown replies in order, each tagged with how many operator prompts came after it. */
function scan(tp) {
  const size = fs.statSync(tp).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(tp, 'r');
  const buf = Buffer.alloc(size - start);
  try { fs.readSync(fd, buf, 0, buf.length, start); } finally { fs.closeSync(fd); }
  const lines = buf.toString('utf8').split('\n');
  if (start > 0) lines.shift();
  const replies = []; // { text, prompt: index of the operator prompt it belongs to }
  let operator = 0; let last = null; let fired = false;
  let calls = []; let since = ''; // the running turn's shell calls and start (close stamp)
  for (const line of lines) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) last = b.text;
        if (b.type === 'tool_use') calls.push({ cmd: String((b.input || {}).command || '') });
      }
      continue;
    }
    if (msg.role !== 'user') continue;
    const t = promptText(msg);
    if (t === null) continue;
    if (last !== null) { replies.push({ text: last, prompt: operator }); last = null; }
    if (HOOK_ECHO.test(t)) { if (OWN_ECHO.test(t)) fired = true; continue; }
    if (isNotification(t)) continue;
    operator++; fired = false; calls = []; since = d.timestamp || '';
  }
  if (last !== null) replies.push({ text: last, prompt: operator });
  return { replies, operator, fired, calls, since };
}

function gate(input) {
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (input.stop_hook_active || !input.transcript_path) return;
  const r = root(input.cwd);
  const rx = questionRegex(r);
  const { replies, operator, fired, calls, since } = scan(input.transcript_path);
  const state = load(r);
  let pending = [];
  let changed = false;
  for (const rep of replies) {
    for (const q of questions(rep.text, rx)) {
      const id = qid(q);
      if (!state[id]) {
        state[id] = { q: q.slice(0, 240), about: contextOf(rep.text, q), asked: new Date().toISOString(),
          session: input.session_id || '', status: 'open', transcript: input.transcript_path };
        changed = true;
      }
      if (rep.prompt < operator && state[id].status === 'open' && !pending.includes(id)) pending.push(id);
    }
  }
  if (changed) { try { save(r, state); } catch (e) { /* state is best effort */ } }
  if (!pending.length || fired) return;
  // The close turn (close-stamp.cjs): a question its session-log entry lists as an open end —
  // by id or by its sentence — passes; it stays open in the state and reaches the next start.
  const ends = closeOpenEnds(r, { sessionId: input.session_id, since, calls });
  if (ends) pending = pending.filter((id) => !(listed(ends, [id]) || listed(ends, [squash(state[id].q)])));
  if (!pending.length) return;
  const list = pending.slice(0, 5).map((id) => `${id} "${state[id].q}"`).join(' · ');
  process.stdout.write(JSON.stringify(declare({
    decision: 'block',
    reason: `QUESTION-GATE: ${pending.length} question(s) to the operator are still open after their reply: ${list}`
      + (pending.length > 5 ? ` (+${pending.length - 5})` : '')
      + '. Settle each: node core/helpers/question-gate.cjs resolve <id>=answered|dropped|unanswered|deferred:<their words>'
      + ' - answered = the operator decided it (also EARLIER: an order already in the ledger or a prior prompt); unanswered = they replied without addressing it (ask again where it'
      + ' matters); deferred = THEY postponed it, quote their words in the note (an overlooked question is not deferred).'
      + (ends ? ' Closing: the close stamp passes a question its session-log entry lists as "open end: question <id> …".' : ''),
  }, input)));
}

/**
 * The operator's prompts AFTER the reply that asked `q`, read from the record's transcript.
 * Returns null when the transcript cannot be read or the question is not found in it.
 */
function operatorAfter(tp, q, rx) {
  let lines;
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return null; }
  const want = qid(q);
  let seen = false; const out = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      if (!seen) {
        for (const b of msg.content) {
          if (b.type === 'text' && b.text && questions(b.text, rx).some((x) => qid(x) === want)) seen = true;
        }
      }
      continue;
    }
    if (!seen || msg.role !== 'user') continue;
    const t = promptText(msg);
    if (t === null || HOOK_ECHO.test(t) || isNotification(t)) continue;
    out.push(t.trim());
  }
  return seen ? out : null;
}

const squash = (t) => String(t || '').toLowerCase().replace(/\s+/g, ' ').trim();

function cli(args) {
  const r = root();
  const state = load(r);
  const rx = questionRegex(r);
  if (args[0] === 'resolve') {
    let bad = 0;
    for (const a of args.slice(1)) {
      const m = /^([0-9a-f]{8})=(\w+)(?::(.*))?$/.exec(a);
      if (!m || !state[m[1]] || !STATUSES.has(m[2])) { console.log(`unknown id or status: ${a}`); bad = 1; continue; }
      if (m[2] === 'deferred') {
        const words = (m[3] || '').trim();
        if (!words) {
          console.log(`${m[1]}: deferred needs the operator's own words (deferred:<quote>); an unanswered question is 'unanswered'`);
          bad = 1; continue;
        }
        // The words must be the OPERATOR's, after the question — checkable, so checked (#269 gap 4).
        const after = state[m[1]].transcript ? operatorAfter(state[m[1]].transcript, state[m[1]].q, rx) : undefined;
        if (after === undefined || after === null) {
          console.log(`${m[1]}: deferred cannot be checked — the asking transcript is not readable; `
            + "file it 'unanswered' and ask again, or quote the operator from a prompt of THIS session via adopt");
          bad = 1; continue;
        }
        if (!after.some((p) => squash(p).includes(squash(words)))) {
          console.log(`${m[1]}: "${words}" is not what the operator wrote after the question (${after.length} prompt(s) read) — `
            + "a paraphrase is not a quotation; an overlooked question is 'unanswered'");
          bad = 1; continue;
        }
      }
      Object.assign(state[m[1]], { status: m[2], note: m[3] || '', resolved: new Date().toISOString() });
      console.log(`${m[1]} -> ${m[2]}`);
    }
    save(r, state);
    return bad;
  }
  if (args[0] === 'adopt') {
    // An orphan: the session that asked is gone. The next session takes it WITH the evidence
    // (#269 gaps 2 and 3): what did the operator write after the question?
    const id = args[1] || '';
    const v = state[id];
    if (!v) { console.log(`unknown id: ${id}`); return 1; }
    const after = v.transcript ? operatorAfter(v.transcript, v.q, rx) : null;
    console.log(`${id} [${v.status}] ${v.q}`);
    if (v.about) console.log(`  about: ${v.about}`);
    if (after === null) {
      console.log('  operator prompts after it: transcript not readable or question not found in it — '
        + 'settle from the ledger or ask again');
    } else if (!after.length) {
      console.log('  operator prompts after it: none — the session ended on the question');
    } else {
      console.log(`  operator prompts after it (${after.length}, newest last):`);
      for (const p of after.slice(-5)) console.log(`    > ${p.replace(/\s+/g, ' ').slice(0, 200)}`);
    }
    v.adopted = new Date().toISOString();
    save(r, state);
    console.log(`  settle: node core/helpers/question-gate.cjs resolve ${id}=answered|dropped|unanswered|deferred:<quote from above>`);
    return 0;
  }
  if (args[0] === 'list') {
    const open = Object.entries(state).filter(([, v]) => ['open', 'deferred', 'unanswered'].includes(v.status));
    if (!open.length) return 0;
    console.log(`open questions to the operator: ${open.length}`);
    // The context line is what lets the next session match the question to its topic (ledger,
    // decision log) and close it once settled there; a bare sentence cannot be matched.
    const today = new Date().toISOString().slice(0, 10);
    for (const [id, v] of open) {
      console.log(`- [${v.status}] ${(v.asked || '').slice(0, 10)} ${id} ${v.q}`);
      if (v.about) console.log(`    about: ${v.about}`);
      // Asked by an earlier session and still not settled = an orphan: name the one call that
      // shows what the operator said after it, so this session can settle it from evidence.
      if ((v.asked || '').slice(0, 10) < today && v.status !== 'deferred') {
        console.log(`    orphan — settle from evidence: node core/helpers/question-gate.cjs adopt ${id}`);
      }
    }
    return 0;
  }
  console.log('usage: question-gate.cjs resolve <id>=answered|dropped|unanswered|deferred:<operator words> ... | adopt <id> | list');
  return 2;
}

if (process.argv.length > 2) {
  process.exit(cli(process.argv.slice(2)));
} else {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    try { gate(JSON.parse(data || '{}')); } catch (e) { /* fail open */ }
    process.exit(0);
  });
}
