#!/usr/bin/env node
/**
 * Stop check: a live peer session in the same working copy has heard nothing from this session.
 *
 * Incident 2026-11-09 (the macOS instance): a second session joined the brain's working copy. The signals reached
 * this session twice - the collision line of the session start and the session-areas OVERLAP line "Coordinate now:
 * SendMessage to ..." - and the session only committed and pushed. Both are prose that nothing holds; the operator
 * found it by asking. Ported from an instance alpha (2026-11-09 to 2026-11-23): 70 decisions recorded, 58 blocks
 * and 12 re-issues after a block, the most for one session 4.
 *
 * Rule: at a turn end, every live session in the same project root (session-areas registry) that this session's
 * transcript never sent a SendMessage to (by ListAgents name or by its reply address) holds the turn. The block
 * names the peers and the one step: SendMessage what you work on and which area you take, then claim it.
 * Frequency design: once per turn (the re-issue passes, stop_hook_active), and a cooldown of COOLDOWN_MIN per
 * peer after a block - a session that read the block and decided the peer only reads is not held again on every
 * turn. One SendMessage to the peer ends it for the session for good.
 *
 * Measurement: every decision -> .claude-state/peer-talk-gate.jsonl {at, session, decision, peers}; the last block
 * per session and peer in .claude-state/peer-talk-gate-last.json (the cooldown). Fails open.
 * Test: scripts/test-peer-talk-gate.sh
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { sessions, talkedTo, talkedWith, claimCmd } = require('./session-areas.cjs');

const COOLDOWN_MIN = 30;

function readJson(p, d) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return d; } }

function log(root, rec) {
  try {
    const dir = path.join(root, '.claude-state');
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, 'peer-talk-gate.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...rec }) + '\n');
  } catch (e) { /* measurement is best effort */ }
}

function decide(input, now) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  let peers = [];
  try { peers = sessions(root, now).filter((s) => s.id !== input.session_id); } catch (e) { return null; }
  if (!peers.length) return null;
  const talked = talkedTo(input.transcript_path);
  const silent = peers.filter((p) => !talkedWith(talked, p));
  if (!silent.length) return null;
  const names = silent.map((p) => p.name);
  if (input.stop_hook_active) { log(root, { session: input.session_id, decision: 'pass-after-block', peers: names }); return null; }
  const lastFile = path.join(root, '.claude-state', 'peer-talk-gate-last.json');
  const last = readJson(lastFile, {});
  const mine = last[input.session_id] || {};
  const due = silent.filter((p) => !mine[p.id] || (now - Date.parse(mine[p.id])) / 6e4 >= COOLDOWN_MIN);
  if (!due.length) { log(root, { session: input.session_id, decision: 'pass-cooldown', peers: names }); return null; }
  for (const p of due) mine[p.id] = new Date(now).toISOString();
  last[input.session_id] = mine;
  try { fs.mkdirSync(path.dirname(lastFile), { recursive: true }); fs.writeFileSync(lastFile, JSON.stringify(last) + '\n'); } catch (e) { /* fail open */ }
  const dueNames = due.map((p) => p.name);
  log(root, { session: input.session_id, decision: 'block', peers: dueNames });
  return {
    decision: 'block',
    reason: 'PEER-TALK-GATE: another session works in this working copy and has heard nothing from you.\n'
      + `Peers not messaged: ${dueNames.join(', ')}\n`
      + 'SendMessage each (its ListAgents name): what you work on and which files or folders you take; then record it '
      + `with \`${claimCmd()}\`. Committing and pushing is no agreement. If nothing is to be agreed (the peer only `
      + `reads), say so in one line and re-issue - the re-issue passes, and this peer is not raised again for ${COOLDOWN_MIN} min.`,
  };
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let out = null;
    try {
      const now = process.env.SESSION_AREAS_NOW ? Date.parse(process.env.SESSION_AREAS_NOW) : Date.now();
      out = decide(JSON.parse(raw), now);
    } catch (e) { out = null; }
    if (out) console.log(JSON.stringify(out));
    process.exitCode = 0;   // no forced exit: it hung at Node shutdown after a transcript read (2026-11-23)
  });
}

module.exports = { decide, COOLDOWN_MIN };
