#!/usr/bin/env node
/**
 * Stop hook: a shared-memory fact file that the inbox or a watcher DELIVERED in this turn was
 * read in this turn — shown is not read.
 *
 * WHY (operator decision 2026-10-18, translated: "that must not count as read! it is a core
 * matter"): the inbox line of a fact file is its description, written by the sender as a
 * pointer; the content is the file. Measured that day: a session acted on an inbox line —
 * worse, on a line cut in the middle — and handed the operator a needless command; the file
 * said the opposite. `shared-memory-inbox.py` now prints LOG entries whole, so a LOG line IS the
 * message. A fact file stays a pointer, and this gate makes sure the pointer is followed.
 *
 * WHAT COUNTS AS DELIVERED: an inbox line in a user record of the running turn (a watcher
 * event, a notification, hook output relayed as text) — `- <date> [<topic>] <von>: … (<path>.md)`.
 * WHAT COUNTS AS READ: in the same turn, after the delivery, a Read of that file, or a Bash
 * command naming its file name (cat, sed, grep, head …).
 * ESCAPE: an assistant text in the turn that says `unread-ok: <why>` — for a delivery the
 * session deliberately does not act on (e.g. an entry to someone else). One block per turn.
 *
 * Exit 0 always; a block is `{decision: "block"}` on stdout. Fails open on unreadable input.
 */
const fs = require('fs');
const { isNotification } = require('./turn-kind.cjs');

// Own echo: legacy token or, behind the dispatcher, the label line (stop-echo.cjs).
const { ownEcho, declare } = require('./stop-echo.cjs');
let OWN_ECHO = /DELIVERED-READ/;
const HOOK_ECHO = /^Stop hook feedback:|Stop hook blocking error/;
const LINE = /^\s*-\s+\d{4}-\d{2}-\d{2}\s+\[[^\]]+\]\s+[^:\n]+:.*\(([\w./-]+\.md)\)\s*(?:<\/[\w-]+>\s*)*$/gm;
const ESCAPE = /\bunread-ok:\s*\S/i;

function allow() { process.exit(0); }

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((b) => {
    if (typeof b === 'string') return b;
    if (b && b.type === 'text') return b.text || '';
    if (b && b.type === 'tool_result') return textOf(b.content);
    return '';
  }).join('\n');
}

function readTail(p) {
  const st = fs.statSync(p);
  const n = Math.min(st.size, 4 * 1024 * 1024);
  const fd = fs.openSync(p, 'r');
  const buf = Buffer.alloc(n);
  fs.readSync(fd, buf, 0, n, st.size - n);
  fs.closeSync(fd);
  const lines = buf.toString('utf8').split('\n');
  if (n < st.size) lines.shift();
  return lines;
}

function baseName(p) { return String(p).split(/[\\/]/).pop(); }

/** Delivered-but-unread fact files of the running turn, in delivery order. */
function analyze(lines) {
  let turn = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user') {
      const t = textOf(msg.content);
      if (typeof msg.content === 'string' && !HOOK_ECHO.test(t) && !isNotification(t)) turn = [];
      turn.push({ user: t });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) turn.push({ assistant: msg.content });
  }
  const pending = new Map();
  let escaped = false, echoed = false;
  for (const e of turn) {
    if (e.user !== undefined) {
      if (OWN_ECHO.test(e.user) && HOOK_ECHO.test(e.user)) echoed = true;
      for (const m of e.user.matchAll(LINE)) pending.set(baseName(m[1]), m[1]);
      continue;
    }
    for (const b of e.assistant) {
      if (b.type === 'text' && ESCAPE.test(b.text || '')) escaped = true;
      if (b.type !== 'tool_use' || !b.input) continue;
      const hay = b.name === 'Read' ? String(b.input.file_path || '')
        : b.name === 'Bash' ? String(b.input.command || '') : '';
      if (!hay) continue;
      for (const k of [...pending.keys()]) if (hay.includes(k)) pending.delete(k);
    }
  }
  return { unread: [...pending.values()], escaped, echoed };
}

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (input.stop_hook_active || !input.transcript_path) return allow();
  let seen;
  try { seen = analyze(readTail(input.transcript_path)); } catch (e) { return allow(); }
  if (!seen.unread.length || seen.escaped || seen.echoed) return allow();
  console.log(JSON.stringify(declare({
    decision: 'block',
    reason: `DELIVERED-READ — shown, not read: ${seen.unread.join(', ')}. An inbox line of a fact file ` +
      'is its description, not the message. Read the file before acting on it, or say ' +
      '`unread-ok: <why>` if you are deliberately not acting on it.',
  }, input)));
  process.exit(0);
});
process.stdin.resume();

