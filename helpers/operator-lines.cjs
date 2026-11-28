'use strict';
/**
 * operator-lines.cjs - ONE reader of the brain's `.claude/rules/operator-lines.json` (the sentence for the operator in
 * front of a hold). The writer is hooks/operator-lead.cjs (preloaded into every node hook); the refusal readers
 * (gate-label.cjs; scripts/gate-health.py carries the same rule in Python and points here) take the sentence off
 * again before they read the gate's label.
 *
 * WHY a shared reader (Windows review of #683, 2026-11-26): with the sentence in front, gateLabel() named every hold
 * "a hook" and gate-health.py counted every refusal under that name - in every brain that adds the data file.
 * A UTF-8 BOM (PowerShell 5.1 `Set-Content -Encoding utf8`) is stripped before JSON.parse: with it the file failed to
 * parse and the sentence was missing without a word.
 */
const fs = require('fs');
const path = require('path');

const cache = new Map();
function lines(root) {
  const r = root || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (cache.has(r)) return cache.get(r);
  let out = {};
  try {
    const raw = fs.readFileSync(path.join(r, '.claude', 'rules', 'operator-lines.json'), 'utf8').replace(/^\uFEFF/, '');
    const d = JSON.parse(raw);
    if (d && d.lines && typeof d.lines === 'object') out = d.lines;
  } catch (e) { /* no data: no sentences */ }
  cache.set(r, out);
  return out;
}

/** The refusal text without a leading operator sentence (after the harness prefix and a `[node "…"]:` tag). */
function stripLead(text, root) {
  const t = String(text || '');
  const sentences = Object.values(lines(root)).filter((s) => typeof s === 'string' && s);
  if (!sentences.length) return t;
  const m = /^(\s*(?:(?:PreToolUse|PostToolUse|Stop):\S*\s*hook error:\s*)?(?:\[[^\]]*\]:\s*)?)/.exec(t);
  const pre = m ? m[1] : '';
  let rest = t.slice(pre.length);
  for (let again = true; again;) {
    again = false;
    for (const s of sentences) {
      if (rest.startsWith(s + '\n') || rest.startsWith(s + '\r\n')) { rest = rest.slice(rest.indexOf('\n') + 1); again = true; }
    }
  }
  return pre + rest;
}

module.exports = { lines, stripLead };
