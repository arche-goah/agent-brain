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
 *   node core/helpers/question-gate.cjs resolve <id>=answered|dropped|deferred[:note]
 * `deferred` keeps it listed at every session start (`list`), so it cannot scroll away, but
 * it is not raised again inside the session (operator rule: a postponed point is said once).
 * Questions of the reply being ended are recorded, never blocked — the operator has not
 * seen them yet. Once per turn; a re-issue passes. Fails open without a transcript.
 *
 * Fixture: scripts/test-question-gate.sh.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { isNotification } = require('./turn-kind.cjs');

const OWN_ECHO = /QUESTION-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const STATUSES = new Set(['open', 'answered', 'dropped', 'deferred']);
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

function questions(text, rx) {
  // Emphasis markers around a question ("**shall I?**") would hide the final "?".
  return stripQuoted(text).replace(/\*\*|__/g, '').split(/(?<=[.!?])\s+|\n+/).map((s) => s.replace(/^[\s*\-\d.)]+/, '').trim())
    .filter((s) => s.endsWith('?') && rx.test(s));
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
  for (const line of lines) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg) continue;
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) if (b.type === 'text' && b.text) last = b.text;
      continue;
    }
    if (msg.role !== 'user') continue;
    const t = promptText(msg);
    if (t === null) continue;
    if (last !== null) { replies.push({ text: last, prompt: operator }); last = null; }
    if (HOOK_ECHO.test(t)) { if (OWN_ECHO.test(t)) fired = true; continue; }
    if (isNotification(t)) continue;
    operator++; fired = false;
  }
  if (last !== null) replies.push({ text: last, prompt: operator });
  return { replies, operator, fired };
}

function gate(input) {
  if (input.stop_hook_active || !input.transcript_path) return;
  const r = root(input.cwd);
  const rx = questionRegex(r);
  const { replies, operator, fired } = scan(input.transcript_path);
  const state = load(r);
  const pending = [];
  let changed = false;
  for (const rep of replies) {
    for (const q of questions(rep.text, rx)) {
      const id = qid(q);
      if (!state[id]) {
        state[id] = { q: q.slice(0, 240), asked: new Date().toISOString(), session: input.session_id || '', status: 'open' };
        changed = true;
      }
      if (rep.prompt < operator && state[id].status === 'open' && !pending.includes(id)) pending.push(id);
    }
  }
  if (changed) { try { save(r, state); } catch (e) { /* state is best effort */ } }
  if (!pending.length || fired) return;
  const list = pending.slice(0, 5).map((id) => `${id} "${state[id].q}"`).join(' · ');
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: `QUESTION-GATE: ${pending.length} question(s) to the operator are still open after their reply: ${list}`
      + (pending.length > 5 ? ` (+${pending.length - 5})` : '')
      + '. Settle each: node core/helpers/question-gate.cjs resolve <id>=answered|dropped|deferred[:note]'
      + ' — answered = the operator decided it; deferred = still open, listed at every session start.',
  }));
}

function cli(args) {
  const r = root();
  const state = load(r);
  if (args[0] === 'resolve') {
    let bad = 0;
    for (const a of args.slice(1)) {
      const m = /^([0-9a-f]{8})=(\w+)(?::(.*))?$/.exec(a);
      if (!m || !state[m[1]] || !STATUSES.has(m[2])) { console.log(`unknown id or status: ${a}`); bad = 1; continue; }
      Object.assign(state[m[1]], { status: m[2], note: m[3] || '', resolved: new Date().toISOString() });
      console.log(`${m[1]} -> ${m[2]}`);
    }
    save(r, state);
    return bad;
  }
  if (args[0] === 'list') {
    const open = Object.entries(state).filter(([, v]) => v.status === 'open' || v.status === 'deferred');
    if (!open.length) return 0;
    console.log(`open questions to the operator: ${open.length}`);
    for (const [id, v] of open) console.log(`- [${v.status}] ${(v.asked || '').slice(0, 10)} ${id} ${v.q}`);
    return 0;
  }
  console.log('usage: question-gate.cjs resolve <id>=answered|dropped|deferred[:note] ... | list');
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
