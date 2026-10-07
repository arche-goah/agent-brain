#!/usr/bin/env node
/**
 * Stop hook: the first reply of a session relays EVERY open point the bootup listed.
 *
 * WHY (operator correction 2026-10-07, proving brain): the bootup named nine open
 * shared-memory requests and six open PRs; the first reply said "nine older requests,
 * nothing new since the last start" and named none. The data side was already fixed
 * (open requests ignore the cursor); the relay side had no carrier at all — a rule in
 * prose ("relevance beats completeness") even covered the omission. The operator's rule:
 * every unhandled point that concerns us MUST be reported, and attention rises with every
 * repeat, never falls. And: it has to hold on Windows and macOS for everyone, or it goes
 * under again.
 *
 * What it reads — the TRANSCRIPT, not a state file, so it also sees a bootup that never
 * arrived: the latest SessionStart record of `core/helpers/session-bootup.sh`.
 *   - startup/resume bootup present: parse the `open for us:` block written by
 *     scripts/open-items.py. Every item must be named in the first reply — a request by
 *     its date (YYYY-MM-DD, MM-DD or DD.MM.), a PR by `#<number>`. Zero items: the reply
 *     must say so (nothing-pattern). A source that was NOT checked: the reply must say so
 *     (failed-pattern). Parked items: the reply must name the parked line (parked-pattern).
 *   - bootup cancelled (hook timeout) or missing: block — the list did not arrive and has
 *     to be fetched by hand (`core/scripts/open-items.py`). Measured on one macOS brain: 38 of these
 *     cancellations, the last on 2026-09-23; a Windows brain reported the same.
 *   - bootup present but without the block (older core, or the block crashed): block.
 *   - compaction (SessionStart:compact): never fires — that is the same session.
 * Only the FIRST turn after the bootup is checked: one real operator prompt since then.
 * Re-issued answers (stop_hook_active) pass, as with every gate.
 *
 * Language: the item references are language-free. The three patterns are English
 * built-ins; an instance adds its own language as DATA in .claude/rules/open-items.json
 * ("nothing_patterns", "failed_patterns", "parked_patterns" — lists of regexes).
 *
 * Output: {"decision":"block","reason":"... Missing: <refs>"} — the dispatcher compresses
 * on "Missing:". Fails open on unreadable input: a crashed gate must not stop a session.
 */
const fs = require('fs');
const path = require('path');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

const MAX_BYTES = 16 * 1024 * 1024; // the first turn sits at the top; a huge file is past it
const BOOTUP = /session-bootup\.sh/;
const NOT_A_PROMPT = /^\s*(Stop hook feedback|<task-notification|<system-reminder)/;
const BUILTIN = {
  nothing: ['\\bnothing (is )?open\\b', '\\bno open (items|points|requests)\\b'],
  failed: ['\\bnot checked\\b', '\\bfailed\\b'],
  parked: ['\\bparked\\b'],
};

function allow() { process.exit(0); }
function block(reason) {
  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
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
    let m;
    if ((m = /^- \[PR\] \S+ (\S+?)#(\d+) /.exec(l))) items.push({ ref: `${m[1]}#${m[2]}`, num: m[2] });
    else if ((m = /^- \[request\] (\d{4})-(\d{2})-(\d{2}) (\S+)/.exec(l))) items.push({ ref: `${m[1]}-${m[2]}-${m[3]} ${m[4].split('/').pop()}`, date: [m[1], m[2], m[3]] });
    else if (/^- \[parked\]/.test(l)) parked = true;
    else if (/^- nothing open/.test(l)) nothing = true;
  }
  return { items, failed, parked, nothing };
}

function named(item, reply) {
  if (item.num) return new RegExp(`#${item.num}(?!\\d)`).test(reply);
  const [y, mo, d] = item.date;
  return reply.includes(`${y}-${mo}-${d}`) || new RegExp(`(?<!\\d)${mo}-${d}(?!\\d)`).test(reply)
    || new RegExp(`(?<!\\d)${Number(d)}\\.\\s?${Number(mo)}\\.|(?<!\\d)${d}\\.${mo}\\.`).test(reply);
}

process.stdin.on('end', () => {
  let input;
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  if (input.stop_hook_active) return allow();
  const tp = input.transcript_path;
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let raw;
  try {
    if (!tp || fs.statSync(tp).size > MAX_BYTES) return allow();
    raw = fs.readFileSync(tp, 'utf8');
  } catch (e) { return allow(); }

  // Walk once: the last bootup record, then prompts and assistant text after it.
  let boot = null; // { kind: 'ok'|'cancelled', source, text }
  let prompts = 0;
  let firstPromptsTotal = 0;
  let reply = [];
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const att = d.attachment;
    if (att && att.hookEvent === 'SessionStart' && BOOTUP.test(att.command || '')) {
      const source = String(att.hookName || '').split(':')[1] || '';
      if (att.type === 'hook_cancelled') boot = { kind: 'cancelled', source, ms: att.durationMs };
      else if (att.type === 'hook_success') boot = { kind: 'ok', source, text: String(att.content || att.stdout || '') };
      else continue;
      prompts = 0; reply = [];
      continue;
    }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user') {
      const t = promptText(msg);
      if (t !== null && !NOT_A_PROMPT.test(t)) { prompts++; firstPromptsTotal++; }
      continue;
    }
    if (msg.role === 'assistant' && prompts === 1 && Array.isArray(msg.content)) {
      for (const b of msg.content) if (b.type === 'text' && b.text) reply.push(b.text);
    }
  }

  if (!boot) {
    // No bootup record at all: only the very first turn of a session is ours to judge.
    if (firstPromptsTotal !== 1) return allow();
    return block('The session-start output never arrived in this session, so the open points were not shown. Run `python3 core/scripts/open-items.py --owner <org>` (or `python`) and report every item. Missing: bootup');
  }
  if (boot.source === 'compact' || prompts !== 1) return allow();
  if (boot.kind === 'cancelled') {
    return block(`The session-start hook was cancelled after ${Math.round((boot.ms || 0) / 1000)} s — the open points never arrived. Run \`python3 core/scripts/open-items.py --owner <org>\` (or \`python\`) and report every item. Missing: bootup (cancelled)`);
  }
  const blk = parseBlock(boot.text);
  if (!blk) {
    return block('The session-start output carries no "open for us:" block (older core, or the block failed) — the open points are unknown. Run `python3 core/scripts/open-items.py --owner <org>` and report every item. Missing: open-items block');
  }

  const text = reply.join('\n');
  const missing = blk.items.filter((it) => !named(it, text)).map((it) => it.ref);
  if (blk.failed && !patterns(cwd, 'failed').test(text)) missing.push('failed source');
  if (blk.parked && !patterns(cwd, 'parked').test(text)) missing.push('parked line');
  if (blk.nothing && !patterns(cwd, 'nothing').test(text)) missing.push('"nothing open"');
  if (missing.length === 0) return allow();
  const shown = missing.length > 6 ? `${missing.slice(0, 6).join(', ')} +${missing.length - 6} more` : missing.join(', ');
  return block(`First reply leaves out open points from the session start — every one goes in, with its age; repeats louder. Missing: ${shown}`);
});
