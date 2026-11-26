'use strict';
/**
 * operator-lead.cjs - preloaded into every hook (`node -r .../operator-lead.cjs <hook>`): a hold text gets ONE line
 * for the human in front, in the operator's language; the text for the agent follows unchanged.
 *
 * WHY (measured 2026-11-26 on the macOS instance): the harness shows a PreToolUse deny and a Stop block to the
 * operator as "hook error: <reason>", cut to about two lines. Those two lines were marker, rule names, paths, in
 * English - written for the agent. The operator asked for one short sentence first, in their own language, and in
 * another brain in that brain's operator's language (question tool, translated). 57 helpers write their hold
 * through process.stdout.write / console.log, none to the file descriptor directly, so one preload reaches all of
 * them without touching a gate.
 *
 * Data: the brain's `.claude/rules/operator-lines.json` {"lines": {"<MARKER>": "<one sentence>"}}; a marker is the
 * text the reason starts with (or holds in its first 120 characters). No file, no match: the reason stays as it is.
 * Only whole JSON writes are touched (permissionDecisionReason of a deny, reason of a block); anything else passes
 * byte for byte. Fails open: an error here never changes or drops a hook's output.
 * Fixture: scripts/test-operator-lead.sh. Lives in hooks/, not helpers/: readers of hooks.json take the first core/helpers/ path of a command as the hook (check-catalog.py, hook-coverage.py; CI python-floor 2026-11-26)
 */
const fs = require('fs');
const path = require('path');

let lines = null;
function table() {
  if (lines) return lines;
  lines = {};
  try {
    const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'operator-lines.json'), 'utf8'));
    if (d && d.lines && typeof d.lines === 'object') lines = d.lines;
  } catch (e) { /* no data: nothing to add */ }
  return lines;
}

function lead(reason) {
  if (typeof reason !== 'string' || !reason) return reason;
  const head = reason.slice(0, 120);
  // The marker named FIRST wins (a Stop dispatcher's reason can carry several).
  let best = null;
  for (const [marker, sentence] of Object.entries(table())) {
    const at = marker && typeof sentence === 'string' ? head.indexOf(marker) : -1;
    if (at >= 0 && (!best || at < best.at)) best = { at, sentence };
  }
  if (!best || reason.startsWith(best.sentence)) return reason;
  return `${best.sentence}\n${reason}`;
}

function rewrite(chunk) {
  if (typeof chunk !== 'string' || chunk.trimStart()[0] !== '{') return chunk;
  let o;
  try { o = JSON.parse(chunk); } catch (e) { return chunk; }
  const h = o && o.hookSpecificOutput;
  let changed = false;
  if (h && typeof h.permissionDecisionReason === 'string') {
    const r = lead(h.permissionDecisionReason);
    if (r !== h.permissionDecisionReason) { h.permissionDecisionReason = r; changed = true; }
  }
  if (o && o.decision === 'block' && typeof o.reason === 'string') {
    const r = lead(o.reason);
    if (r !== o.reason) { o.reason = r; changed = true; }
  }
  return changed ? JSON.stringify(o) + (chunk.endsWith('\n') ? '\n' : '') : chunk;
}

if (process.stdout && typeof process.stdout.write === 'function') {
  const orig = process.stdout.write.bind(process.stdout);
  process.stdout.write = function write(chunk, ...rest) {
    let out = chunk;
    try { out = rewrite(typeof chunk === 'string' ? chunk : Buffer.isBuffer(chunk) ? chunk.toString('utf8') : chunk); } catch (e) { out = chunk; }
    if (out === (Buffer.isBuffer(chunk) ? chunk.toString('utf8') : chunk)) out = chunk;
    return orig(out, ...rest);
  };
}

module.exports = { lead, rewrite };
