/**
 * Done claim: a reply that declares the work finished ("nothing open", "all done", "the session
 * can be closed"). One definition for every gate that reacts to it — watch-gate (h) and
 * verification-gate. English built-ins; other languages are instance data, one place:
 * `done_claim_patterns` in `.claude/rules/watch-gate.json`.
 */
const fs = require('fs');
const path = require('path');

const DONE_CLAIM_BUILTIN = [
  '\\bnothing\\s+(?:is\\s+)?(?:left\\s+|still\\s+)?open\\b',
  '\\b(?:all|everything)\\s+(?:is\\s+)?(?:done|finished|through)\\b',
  '\\b(?:the\\s+)?session\\s+can\\s+(?:be\\s+)?(?:closed|ended)\\b',
  '\\bwe\\s+are\\s+done\\b',
];

function doneClaimRegex(root) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'watch-gate.json'), 'utf8')); } catch (e) { /* built-ins only */ }
  const out = [...DONE_CLAIM_BUILTIN];
  if (Array.isArray(cfg.done_claim_patterns)) {
    for (const p of cfg.done_claim_patterns) { try { new RegExp(p); out.push(p); } catch (e) { /* skip */ } }
  }
  return new RegExp(out.join('|'), 'iu');
}

module.exports = { DONE_CLAIM_BUILTIN, doneClaimRegex };
