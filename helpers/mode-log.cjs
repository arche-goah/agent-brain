#!/usr/bin/env node
/**
 * Stop recorder: the run mode at the end of every turn, written as a fact of that moment.
 *
 * WHY (operator order 2026-11-01, measured the same day on the macOS instance): every reader that asks
 * "was the session autonomous then?" recomputed the mode from the whole transcript with the word lists
 * and reader of TODAY. A changed word list rewrote the past - the pause audit counted 102 autonomous
 * pauses for 2026-10-28 one day and 19 for the same day the next, and a word-list fix flipped a running
 * session from autonomous to interactive mid-run. The mode a turn ended in is now written when it ends;
 * readers of the past read this log instead of recomputing it.
 *
 * Wired as a `mode: record` check in stop-checks.json: never blocks; the dispatcher appends
 * {at, session, check, mode, prompt} to .claude-state/mode-log.jsonl. `prompt` is the first 60
 * characters of the operator word the mode was read from (for the reader to match its own turn).
 * Fails silent: no transcript, no reader = no record.
 */
'use strict';
const path = require('path');

function judge(input) {
  const tp = input && input.transcript_path;
  if (!tp) return null;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  let modes;
  try { modes = require(path.join(__dirname, 'autonomous-mode.cjs')).promptModes(tp, root); } catch (e) { return null; }
  const last = modes.length ? modes[modes.length - 1] : null;
  let autonomous = last ? last.autonomous : false;
  if (!last) {
    try { autonomous = require(path.join(__dirname, 'autonomous-mode.cjs')).autonomousMode(tp, root); } catch (e) { /* default */ }
  }
  const rec = { mode: autonomous ? 'autonomous' : 'interactive' };
  if (last) rec.prompt = String(last.text || '').replace(/\s+/g, ' ').trim().slice(0, 60);
  if (last && last.by) rec.by = last.by;
  return { record: [rec] };
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let out = null;
    try { out = judge(JSON.parse(raw)); } catch (e) { out = null; }
    if (out) process.stdout.write(JSON.stringify(out));
    process.exit(0);
  });
}

module.exports = { judge };
