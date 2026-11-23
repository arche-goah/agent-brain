#!/usr/bin/env node
/**
 * session-scope.cjs - a HELPER session's scope: it works only the orders another session sends it.
 *
 * Why (operator 2026-11-23, translated: "work autonomously, but ONLY what the main session assigns you"; then, via the
 * main session's question tool: "yes, build it"): a helper session that had finished every order was held twice in a
 * row by autonomous-idle-gate - first for the brain's own-items measurement, then for "continuation on own start
 * findings" - work that belongs to the main session and that the operator had excluded. The helper could only break the
 * order or be held at every turn end. With a scope, the gates count that session's ORDERS instead: the cross-session
 * messages from the named session in its transcript, not the brain's start findings, ledger releases or open items.
 *
 * A scope frees a session from duties, so it holds only with the operator's word: the record quotes the operator, and a
 * reader counts it only while those words stand in what the operator said in THIS session's transcript. A session
 * cannot free itself.
 *
 *   node core/helpers/session-scope.cjs set --of <main session name> --words "<the operator's words>" [--session <id>]
 *   node core/helpers/session-scope.cjs clear [--session <id>]
 *   node core/helpers/session-scope.cjs show [--session <id>] [--transcript <path>]
 * The session id defaults to CLAUDE_CODE_SESSION_ID. State: .claude-state/session-scope.json, one entry per session id.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const file = (root) => path.join(root, '.claude-state', 'session-scope.json');
const squash = (s) => String(s || '').toLowerCase().replace(/[\s ]+/g, ' ').trim();

function load(root) {
  try { return JSON.parse(fs.readFileSync(file(root), 'utf8')) || {}; } catch (e) { return {}; }
}

/** The orders the named session sent: one per cross-session message (a message is recorded more than once in a
 *  transcript - counted by its reminder id). */
function ordersFrom(tp, name) {
  let raw = '';
  try { raw = fs.readFileSync(tp, 'utf8'); } catch (e) { return 0; }
  const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const rx = new RegExp(`<system-reminder id=\\\\?"([\\w-]+)\\\\?">(?:(?!</system-reminder)[\\s\\S]){0,200}?from-name=\\\\?"${esc}\\\\?"`, 'g');
  const ids = new Set();
  for (const m of raw.matchAll(rx)) ids.add(m[1]);
  return ids.size;
}

/** The scope of a session, or null: {of, words, orders}. `said` is what the operator said in the transcript (the
 *  caller's reader, so every gate uses its own filters); without it nothing is freed. */
function scopeOf(root, sessionId, tp, said) {
  const r = sessionId && load(root)[sessionId];
  if (!r || !r.helper_of || !r.words || !said) return null;
  if (!squash(said).includes(squash(r.words))) return null;
  return { of: r.helper_of, words: r.words, orders: tp ? ordersFrom(tp, r.helper_of) : 0 };
}

function cli(argv) {
  const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
  const root = opt('--root') || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const id = opt('--session') || process.env.CLAUDE_CODE_SESSION_ID;
  const cmd = argv[0];
  if (!['set', 'clear', 'show'].includes(cmd)) {
    console.error('usage: session-scope.cjs set --of <session name> --words "<operator words>" | clear | show  [--session <id>] [--root <brain>]');
    return 2;
  }
  if (!id) { console.error('session-scope: no session id (CLAUDE_CODE_SESSION_ID unset) - pass --session <id>'); return 2; }
  const all = load(root);
  if (cmd === 'show') { console.log(JSON.stringify(all[id] || null)); return 0; }
  if (cmd === 'clear') delete all[id];
  else {
    const of = opt('--of'); const words = opt('--words');
    if (!of || !words || squash(words).length < 12) {
      console.error('session-scope: set needs --of <session name> and --words "<the operator\'s words, 12 characters or more>"');
      return 2;
    }
    all[id] = { helper_of: of, words, scope: 'orders', since: new Date().toISOString() };
  }
  fs.mkdirSync(path.dirname(file(root)), { recursive: true });
  fs.writeFileSync(file(root), JSON.stringify(all, null, 2) + '\n');
  console.log(cmd === 'clear' ? `session-scope: cleared for ${id}` : `session-scope: ${id} is a helper of ${all[id].helper_of} (orders only, while the quoted words stand in the operator's messages)`);
  return 0;
}

module.exports = { scopeOf, ordersFrom, load };

if (require.main === module) process.exitCode = cli(process.argv.slice(2));
