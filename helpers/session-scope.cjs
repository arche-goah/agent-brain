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
 * A scope frees a session from duties, so only the OPERATOR sets it, by hand, in that session: `! node ... set` (measured
 * 2026-11-23: the helper's own call was refused by the auto-mode classifier as undermining oversight). A reader counts
 * it only while that `!` command stands in the session's transcript - a record the session wrote itself, a peer's
 * message or a quoted command frees nothing - and `set` refuses when the newest record is the agent's own call.
 * The helper itself may only `show` and `clear`.
 *
 *   ! node core/helpers/session-scope.cjs set --of <main session name> --words "<the operator's words>" [--session <id>]
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

/** The operator's OWN `!` command records of the transcript: a user record whose whole content is `<bash-input>…`.
 *  Only the harness writes these when the operator types `! <command>`; a tool result, a peer's message or a
 *  quoted text is never such a record. */
function bashInputs(tp) {
  let lines = [];
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return []; }
  const out = [];
  for (const l of lines) {
    if (!l.includes('bash-input')) continue;
    let d; try { d = JSON.parse(l); } catch (e) { continue; }
    const c = d && d.type === 'user' && d.message && d.message.content;
    if (typeof c === 'string' && /^\s*<bash-input>/.test(c)) out.push(c);
  }
  return out;
}
const esc = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** Did the operator set this scope by hand, and not clear it since? The newest operator `!` command that names
 *  session-scope.cjs decides. */
function operatorSet(tp, of) {
  const mine = bashInputs(tp).filter((c) => /session-scope\.cjs\s+(?:set|clear)\b/.test(c));
  const last = mine[mine.length - 1];
  return Boolean(last) && new RegExp(`session-scope\\.cjs\\s+set\\b[^<]*--of\\s+["']?${esc(of)}(?:["'\\s]|$)`).test(last);
}

/** The scope of a session, or null: {of, words, orders}. A scope frees a session from duties, so it holds only when
 *  the OPERATOR set it by hand in this session: their `!` command in the transcript (measured 2026-11-23: the helper's
 *  own `set` call was refused by the auto-mode classifier as undermining oversight - a session must not free itself,
 *  and a record file it could write would free it anyway). The quoted words must stand in that command or in what
 *  the operator said (`said`, the caller's reader). */
function scopeOf(root, sessionId, tp, said) {
  const r = sessionId && load(root)[sessionId];
  if (!r || !r.helper_of || !r.words || !tp) return null;
  if (!operatorSet(tp, r.helper_of)) return null;
  const typed = bashInputs(tp).join('\n');
  if (!squash(typed).includes(squash(r.words)) && !squash(said || '').includes(squash(r.words))) return null;
  return { of: r.helper_of, words: r.words, orders: ordersFrom(tp, r.helper_of) };
}

/** The session's own transcript, for the CLI: <config>/projects/<root as slug>/<session id>.jsonl. */
function transcriptOf(root, id) {
  const cfg = process.env.CLAUDE_CONFIG_DIR || path.join(require('os').homedir(), '.claude');
  return path.join(cfg, 'projects', path.resolve(root).replace(/[^A-Za-z0-9]/g, '-'), `${id}.jsonl`);
}
/** Is the newest record of the transcript the AGENT calling `set` (a tool call)? Then the call is its own. */
function agentCalledSet(tp) {
  let lines = [];
  try { lines = fs.readFileSync(tp, 'utf8').trim().split('\n'); } catch (e) { return false; }
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    let d; try { d = JSON.parse(lines[i]); } catch (e) { continue; }
    const c = d && d.message && d.message.content;
    if (d.type === 'user' && typeof c === 'string') return false;          // the operator spoke last
    if (d.type === 'assistant' && Array.isArray(c)) {
      return c.some((b) => b && b.type === 'tool_use' && /session-scope\.cjs\s+set\b/.test(JSON.stringify(b.input || {})));
    }
  }
  return false;
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
    const tp = opt('--transcript') || transcriptOf(root, id);
    if (agentCalledSet(tp)) {
      console.error('session-scope: REFUSED - a session does not set its own scope (it frees the session from duties). '
        + 'The operator sets it by hand: `! node <this file> set --of <session> --words "<their words>"` in that session.');
      return 3;
    }
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

module.exports = { scopeOf, ordersFrom, load, operatorSet, agentCalledSet };

if (require.main === module) process.exitCode = cli(process.argv.slice(2));
