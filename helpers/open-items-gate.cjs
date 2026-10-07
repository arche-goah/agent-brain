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
 *
 * The opening question is WANTED here, so `firstTurnOwnsQuestion()` is exported for
 * stoppen-gate: on exactly this turn the closing question belongs to this gate.
 *
 * Language: item references are language-free (a request by its date, a PR by `#<n>`, a
 * count as digits). The phrase patterns are English built-ins; an instance adds its own
 * language as DATA in .claude/rules/open-items.json (`<key>_patterns`, lists of regexes;
 * keys: nothing, failed, parked, offer, repeat).
 *
 * Output: {"decision":"block","reason":"... Missing: <what>"} — the dispatcher compresses
 * on "Missing:". Fails open on unreadable input: a crashed gate must not stop a session.
 */
const fs = require('fs');
const path = require('path');

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
};

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

/** One pass over the transcript: the last bootup record, prompts and reply after it. */
function readTurn(tp) {
  if (!tp || fs.statSync(tp).size > MAX_BYTES) return null;
  const raw = fs.readFileSync(tp, 'utf8');
  let boot = null; // { kind: 'ok'|'cancelled', source, text, ms }
  let prompts = 0;
  let total = 0;
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
      if (t !== null && !NOT_A_PROMPT.test(t)) { prompts++; total++; }
      continue;
    }
    if (msg.role === 'assistant' && prompts === 1 && Array.isArray(msg.content)) {
      for (const b of msg.content) if (b.type === 'text' && b.text) reply.push(b.text);
    }
  }
  return { boot, prompts, total, reply: reply.join('\n') };
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
    return blk.items.some((it) => it.cls !== 'human') || human > HUMAN_LIST_MAX;
  } catch (e) { return false; }
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
    } else if ((m = /^- \[request\|(\w+|\?)\] (\d{4})-(\d{2})-(\d{2}) (.+?) — /.exec(l))) {
      const ref = m[5];
      items.push({ cls: m[1], ref: `${m[2]}-${m[3]}-${m[4]} ${ref.split('/').pop()}`, key: ref,
        base: ref.split('/').pop(), date: [m[2], m[3], m[4]], repeat });
    } else if (/^- \[parked\]/.test(l)) parked = true;
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

const hasNumber = (n, text) => new RegExp(`(?<!\\d)${n}(?!\\d)`).test(text);

function judge(input) {
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const t = readTurn(input.transcript_path);
  if (!t) return null;
  if (!t.boot) {
    // No bootup record at all: only the very first turn of a session is ours to judge.
    if (t.total !== 1) return null;
    return 'The session-start output never arrived in this session, so the open points were not shown. Run `python3 core/scripts/open-items.py --owner <org>` (or `python`) and report them. Missing: bootup';
  }
  if (t.boot.source === 'compact' || t.prompts !== 1) return null;
  if (t.boot.kind === 'cancelled') {
    return `The session-start hook was cancelled after ${Math.round((t.boot.ms || 0) / 1000)} s — the open points never arrived. Run \`python3 core/scripts/open-items.py --owner <org>\` (or \`python\`) and report them. Missing: bootup (cancelled)`;
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
    const own = store[it.key] || (it.base && store[it.base]);
    if (own && (own.class === 'ai' || own.class === 'human')) it.cls = own.class;
  }
  const unclassified = blk.items.filter((it) => it.cls === '?');
  if (unclassified.length) {
    return `Classify every open item once — can the agent answer/handle it (ai), or does it need the operator (human)? Run \`python3 core/scripts/open-items.py --classify '<id>=ai|human:<why>'\`, then report. Missing: class for ${unclassified.map((it) => it.ref).join(', ')}`;
  }

  const text = t.reply;
  const ai = blk.items.filter((it) => it.cls === 'ai');
  const human = blk.items.filter((it) => it.cls === 'human');
  const missing = [];
  if (ai.length) {
    if (!hasNumber(ai.length, text)) missing.push(`count of items you can handle (${ai.length})`);
    if (!patterns(cwd, 'offer').test(text)) missing.push('one question whether to handle them');
  }
  if (human.length) {
    if (!hasNumber(human.length, text)) missing.push(`count of items that need the operator (${human.length})`);
    if (human.length <= HUMAN_LIST_MAX) {
      for (const it of human) if (!named(it, text)) missing.push(it.ref);
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
  return `First reply leaves out the open points from the session start — split by who acts: "n I can handle, shall I?" + "n need you" (up to ${HUMAN_LIST_MAX} named, more offered); repeats said. Missing: ${shown}`;
}

module.exports = { firstTurnOwnsQuestion };

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
