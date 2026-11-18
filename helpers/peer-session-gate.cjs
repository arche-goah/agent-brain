#!/usr/bin/env node
/**
 * Stop check: a closing reply that says another session of this brain is running (or holds a claim)
 * while the live measurement finds no other session here is held once.
 *
 * WHY (operator correction 2026-11-17, macOS instance; ran as an instance alpha the same day): a peer
 * session of the same brain ran from 06:14 to 06:19 and acknowledged a path claim; the watcher reported
 * at about 06:22 that only one session was left, and at about 06:40 the closing reply still named the
 * peer's claim as holding. A peer's state was used without a freshness proof. The live measurement
 * exists: the harness session registry, read through helpers/session-areas.cjs (name, pid, repo-exact).
 *
 * Mechanics: the turn's closing reply (close-loss-gate's replyText) is split into sentences; a sentence
 * that names a peer session — the harness's session name `<repo-folder>-<2 hex>`, the folder taken from
 * the project dir — in a PRESENT form ("is running", "holds", "claims", ...) and without a PAST form
 * ("ran", "closed", ...) is a claim. Then the registry decides: a named peer that is not a live session of
 * this brain blocks; a live one, or a registry that does not even list this session (unmeasurable), passes.
 * Instance data: .claude/rules/peer-session.json {"now_patterns", "past_patterns", "name_patterns"} —
 * regexes in the operator's language, extending the English built-ins (template in
 * templates/rules-instance/).
 * Frequency design: once per turn — the check does not run on the re-issue pass (no onReissue in its row), so
 * a corrected reply or a reasoned keep passes.
 * Output: {"decision":"block","reason":"PEER-SESSION-GATE: ... measures only this one: <sentence>"}.
 * Fails open: no transcript, unreadable input, unmeasurable session count.
 * Fixture: scripts/test-peer-session-gate.cjs (seams of session-areas.cjs: CLAUDE_CONFIG_DIR, SESSION_AREAS_ALIVE).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { replyText } = require('./close-loss-gate.cjs');
const { declare } = require('./stop-echo.cjs');

const MARKER = 'PEER-SESSION-GATE';
const NOW = ['\\bis (still )?(running|working|active|open)\\b', '\\bholds\\b', '\\bclaims\\b', '\\bhas claimed\\b',
  '\\bparallel\\b', '\\bsecond session\\b', '\\bstill runs\\b'];
const PAST = ['\\bran\\b', '\\bwas\\b', '\\bclosed\\b', '\\bended\\b', '\\bhad\\b', '\\bstopped\\b', '\\bfinished\\b'];

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function rx(builtins, extra) {
  const list = [...builtins];
  for (const s of extra || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ } }
  return list.length ? new RegExp(list.join('|'), 'iu') : null;
}

function patterns(root, inst) {
  const folder = path.basename(path.resolve(root));
  return {
    name: rx([`\\b${esc(folder)}-[0-9a-f]{2}\\b`], inst.name_patterns),
    now: rx(NOW, inst.now_patterns),
    past: rx(PAST, inst.past_patterns),
  };
}

/** The sentences of `text` that claim a peer session as running or holding something. */
function claims(text, p) {
  return String(text).split(/(?<=[.!?\n])\s+/)
    .filter((s) => p.name.test(s) && p.now.test(s) && !p.past.test(s));
}

/** Names of the live sessions of this brain from the harness registry (session-areas.cjs), or null when this
 *  session itself is not found there (unmeasurable). No shell: the Windows review 2026-11-17 found that a spawn of
 *  `bash` by name gives ENOENT in a hook process whose PATH carries Git\cmd only, and the gate then let every stale
 *  claim stand. The registry also names THE peer, not "any second Claude process on the machine". */
function liveNames(root, selfId) {
  let list;
  try { list = require('./session-areas.cjs').sessions(root, Date.now()); } catch (e) { return null; }
  if (!selfId || !list.some((s) => s.id === selfId)) return null;
  return new Set(list.map((s) => s.name));
}

function judge(input) {
  if (!input || !input.transcript_path || input.stop_hook_active) return null;
  const root = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let inst = {};
  try { inst = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'peer-session.json'), 'utf8')); } catch (e) { /* built-ins */ }
  const p = patterns(root, inst);
  const hits = claims(replyText(input.transcript_path), p);
  if (!hits.length) return null;
  const live = liveNames(root, input.session_id);
  if (!live) return null; // unmeasurable: the claim may hold
  const folder = path.basename(path.resolve(root));
  const named = new RegExp(`\\b${esc(folder)}-[0-9a-f]{2}\\b`, 'giu');
  for (const s of hits) {
    const names = s.match(named) || [];
    // a sentence named only through an instance pattern: it stands while any other session runs
    const stale = names.length ? names.find((n) => !live.has(n)) : (live.size <= 1 ? '(a peer)' : null);
    if (stale) {
      return `${MARKER}: the reply says ${stale} runs or holds a claim, but the session registry has no live ` +
        `session of that name in this brain: ${s.trim().slice(0, 120)}`;
    }
  }
  return null;
}

module.exports = { judge, claims, patterns };

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    let reason = null;
    try { reason = judge(input); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify(declare({ decision: 'block', reason }, input)));
    process.exit(0);
  });
}
