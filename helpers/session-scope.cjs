#!/usr/bin/env node
/**
 * session-scope.cjs - a HELPER session's scope: it works only the orders its main session sends it.
 *
 * Why (operator 2026-11-23, translated: "work autonomously, but ONLY what the main session assigns you"; then, via the
 * main session's question tool: "yes, build it"): a helper session that had finished every order was held twice in a
 * row by autonomous-idle-gate - for the brain's own-items measurement, then for "continuation on own start findings" -
 * work that belongs to the main session and that the operator had excluded. With a scope the gates count the helper's
 * ORDERS instead: the cross-session messages from its main session, not the brain's start findings, ledger releases
 * or open items.
 *
 * WHO SETS IT: the operator, by an ordinary typed message (operator 2026-11-23, to "who sets a helper scope": "not by
 * a ! command, but by an ordinary message"). There is no set command and no state file: the reader takes the
 * operator's TYPED prompts of the session's own transcript - never a frame, a peer's message, a tool result or queued
 * AI text (the caller's reader, autonomous-idle-gate's operatorMessages) - and finds the newest helper statement
 * (`helper_scope_patterns`) or clearing statement (`helper_clear_patterns`); the newer one wins. Nothing the AI can
 * write frees it (measured the same day: a helper's own `set` call was refused by the auto-mode classifier as
 * undermining oversight).
 *
 * THE MAIN SESSION: a session name in the statement, when the instance names its form (`helper_main_name`, a regex;
 * no built-in - names are not guessed); without one, the session that sent the most messages after the statement, the
 * earlier on a tie (the operator's own sentence on the macOS instance: "find out yourself who that is").
 *
 *   node core/helpers/session-scope.cjs show --transcript <path> [--root <brain>]     (read-only)
 * Patterns: English built in, other languages in .claude/rules/autonomous-patterns.json.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const SCOPE_BUILTIN = ['\\bonly (?:the )?(?:orders|tasks) (?:of|from) (?:the |my )?main session\\b', '\\byou are (?:a |the )?helper(?: session)?\\b'];
const CLEAR_BUILTIN = ['\\b(?:scope off|no longer (?:a )?helper|normal session again)\\b'];

function patterns(root, key, builtin) {
  const list = [...builtin];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    for (const x of (d && d[key]) || []) { try { new RegExp(x, 'iu'); list.push(x); } catch (e) { /* skip a broken one */ } }
  } catch (e) { /* no data: English only */ }
  return new RegExp(list.join('|'), 'iu');
}
function mainName(root) {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    if (d && typeof d.helper_main_name === 'string') return new RegExp(d.helper_main_name, 'iu');
  } catch (e) { /* none */ }
  return null;
}

/** Cross-session messages of the transcript in order: [{id, from}] - one per message (a message is recorded more than
 *  once, counted by its reminder id), with the record index of its first sighting. */
function peerMessages(tp) {
  let raw = '';
  try { raw = fs.readFileSync(tp, 'utf8'); } catch (e) { return []; }
  const rx = /<system-reminder id=\\?"([\w-]+)\\?">(?:(?!<\/system-reminder)[\s\S]){0,200}?from-name=\\?"([^"\\]+)\\?"/g;
  const seen = new Set(); const out = [];
  for (const m of raw.matchAll(rx)) {
    if (seen.has(m[1])) continue;
    seen.add(m[1]);
    out.push({ id: m[1], from: m[2], at: m.index });
  }
  return out;
}
function ordersFrom(tp, name) { return peerMessages(tp).filter((p) => p.from === name).length; }

/** The position of an operator message in the raw transcript (to order it against the peers' messages). */
function posOf(raw, s) {
  const probe = s.slice(0, 40);
  const i = raw.toLowerCase().indexOf(probe);
  return i < 0 ? 0 : i;
}

/** The scope of a session, or null: {of, said, orders}. `msgs` = the operator's messages as the caller's reader gives
 *  them ([{s, ans}], squashed, in transcript order); question-tool answers do not count - the AI wrote their options. */
function scopeOf(root, tp, msgs) {
  if (!tp || !Array.isArray(msgs) || !msgs.length) return null;
  const on = patterns(root, 'helper_scope_patterns', SCOPE_BUILTIN);
  const off = patterns(root, 'helper_clear_patterns', CLEAR_BUILTIN);
  let last = null;
  for (const m of msgs) {
    if (m.ans) continue;
    if (off.test(m.s)) last = null;
    if (on.test(m.s)) last = m.s;
  }
  if (!last) return null;
  const nameRx = mainName(root);
  const named = nameRx && nameRx.exec(last);
  let of = named ? named[0] : null;
  const peers = peerMessages(tp);
  if (!of) {
    let raw = '';
    try { raw = fs.readFileSync(tp, 'utf8'); } catch (e) { raw = ''; }
    // the session that sent the most messages after the statement, the earlier one on a tie. Not the first sender:
    // replayed on the second helper's transcript, the first message came from a fellow helper coordinating (2), the
    // main session's orders followed (3).
    const at = posOf(raw, last);
    const n = {};
    for (const p of peers) if (p.at > at) n[p.from] = (n[p.from] || 0) + 1;
    of = Object.keys(n).sort((a, b) => n[b] - n[a])[0] || null;
  }
  return { of: of || 'the main session (none has sent an order yet)', said: last, orders: of ? peers.filter((p) => p.from === of).length : 0 };
}

function cli(argv) {
  const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
  if (argv[0] !== 'show' || !opt('--transcript')) {
    console.error('usage: session-scope.cjs show --transcript <path> [--root <brain>]   (the operator sets a scope by an ordinary message)');
    return 2;
  }
  const root = opt('--root') || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const { operatorMessages } = require('./autonomous-idle-gate.cjs');
  console.log(JSON.stringify(scopeOf(root, opt('--transcript'), operatorMessages(opt('--transcript')))));
  return 0;
}

module.exports = { scopeOf, ordersFrom, peerMessages };

if (require.main === module) process.exitCode = cli(process.argv.slice(2));
