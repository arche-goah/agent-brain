#!/usr/bin/env node
/**
 * Stop check: a closing reply that says another session of this brain is running (or holds a claim)
 * while the live measurement finds no other session here is held once.
 *
 * WHY (operator correction 2026-11-17, macOS instance; ran as an instance alpha the same day): a peer
 * session of the same brain ran from 06:14 to 06:19 and acknowledged a path claim; the watcher reported
 * at about 06:22 that only one session was left, and at about 06:40 the closing reply still named the
 * peer's claim as holding. A peer's state was used without a freshness proof. The live measurement
 * exists: scripts/parallel-sessions.sh (one line per Claude process working in this repo).
 *
 * Mechanics: the turn's closing reply (close-loss-gate's replyText) is split into sentences; a sentence
 * that names a peer session — the harness's session name `<repo-folder>-<2 hex>`, the folder taken from
 * the project dir — in a PRESENT form ("is running", "holds", "claims", ...) and without a PAST form
 * ("ran", "closed", ...) is a claim. Then parallel-sessions.sh measures: exit 0 (at most this session)
 * blocks; exit 1 (another session runs) or 2 (cannot be measured) lets the claim stand.
 * Instance data: .claude/rules/peer-session.json {"now_patterns", "past_patterns", "name_patterns"} —
 * regexes in the operator's language, extending the English built-ins (template in
 * templates/rules-instance/).
 * Frequency: once per turn — the check does not run on the re-issue pass (no onReissue in its row), so
 * a corrected reply or a reasoned keep passes.
 * Output: {"decision":"block","reason":"PEER-SESSION-GATE: ... measures only this one: <sentence>"}.
 * Fails open: no transcript, unreadable input, unmeasurable session count.
 * Fixture: scripts/test-peer-session-gate.cjs (seam: PARALLEL_SESSIONS_CMDLINES of parallel-sessions.sh).
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
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

/** 0 = at most this session, 1 = another runs, 2 = unmeasurable (parallel-sessions.sh exit codes). */
function sessionsRc(root) {
  try {
    execFileSync('bash', [path.join(__dirname, '..', 'scripts', 'parallel-sessions.sh'), root],
      { encoding: 'utf8', timeout: 8000, stdio: ['ignore', 'pipe', 'ignore'] });
    return 0;
  } catch (e) { return typeof e.status === 'number' ? e.status : 2; }
}

function judge(input) {
  if (!input || !input.transcript_path || input.stop_hook_active) return null;
  const root = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let inst = {};
  try { inst = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'peer-session.json'), 'utf8')); } catch (e) { /* built-ins */ }
  const hits = claims(replyText(input.transcript_path), patterns(root, inst));
  if (!hits.length) return null;
  if (sessionsRc(root) !== 0) return null; // another session runs, or unmeasurable: the claim may hold
  return `${MARKER}: the reply says another session runs or holds a claim, but parallel-sessions.sh measures ` +
    `only this one: ${hits[0].trim().slice(0, 120)}`;
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
