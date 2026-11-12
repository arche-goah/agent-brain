#!/usr/bin/env node
/**
 * claim-write-gate.cjs — PreToolUse (Write|Edit|MultiEdit|NotebookEdit): a claim is exclusive. A session does not write
 * into a path that another LIVE session of the same brain has claimed (`session-areas.cjs claim`).
 *
 * WHY (operator order 2026-11-09, translated): coordinating between sessions means splitting areas and responsibility —
 * one does this, the other does something else; never both working on the same topic. This is a general rule and
 * belongs into the core as a mechanism. Measured that day on the macOS instance: one session had claimed the shopping
 * list, a second session "coordinated" by relaying its own shopping decisions to the first one to write them down — two
 * sessions on one topic. session-areas.cjs only TOLD about a write into a peer's claim; nothing held it, so a claim
 * meant nothing.
 *
 * Rule: a write into a file inside a path that a live peer claimed (same project root) is denied, naming the owner and
 * the way on: send the need to the owner, or the owner releases, or the operator reassigns the area. An own claim that is
 * deeper than the peer's (a sub-area handed over) wins. A peer whose process is gone does not count (sessions() deletes
 * its record). Fails open: a hook error is silence.
 *
 * Measurement: `.claude-state/claim-write-gate.jsonl` {at, session, decision, file, owner}.
 * Test: scripts/test-claim-write-gate.sh
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { sessions } = require('./session-areas.cjs');

const norm = (p) => path.resolve(String(p)).replace(/\\/g, '/').replace(/\/+$/, '');
const inside = (a, b) => a === b || a.startsWith(b + '/');

function log(root, rec) {
  try {
    const dir = path.join(root, '.claude-state');
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, 'claim-write-gate.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...rec }) + '\n');
  } catch (e) { /* best effort */ }
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(raw);
    const ti = input.tool_input || {};
    const file = ti.file_path || ti.notebook_path;
    if (!file) process.exit(0);
    const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
    const me = input.session_id || process.env.CLAUDE_CODE_SESSION_ID || '';
    const f = norm(file);
    const now = process.env.SESSION_AREAS_NOW ? Date.parse(process.env.SESSION_AREAS_NOW) : Date.now();
    const all = sessions(root, now);
    const mine = (all.find((s) => s.id === me) || { claims: [] }).claims || [];
    const ownDepth = Math.max(-1, ...mine.filter((c) => inside(f, norm(c.path))).map((c) => norm(c.path).length));
    for (const p of all) {
      if (p.id === me) continue;
      for (const c of p.claims || []) {
        const cp = norm(c.path);
        if (!inside(f, cp) || ownDepth > cp.length) continue;
        log(root, { session: me, decision: 'deny', file: f, owner: p.name });
        const reason = `CLAIM: ${f} lies in ${cp}, claimed by the live session ${p.name}${c.note ? ` ("${c.note}")` : ''}. `
          + 'One topic, one owner: do not write there. Send the need to the owner (SendMessage: what, why, deadline) — '
          + 'or the owner releases (`session-areas.cjs release <path>`) / the operator reassigns the area.';
        process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
        process.exit(0);
      }
    }
  } catch (e) { /* fail open */ }
  process.exit(0);
});
