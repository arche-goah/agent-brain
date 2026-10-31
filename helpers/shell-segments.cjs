/**
 * Shell command segments: a command line split at newline ; && || | & $( ( — only OUTSIDE quotes.
 *
 * WHY (measured 2026-10-28 on the macOS instance): shared-working-copy-guard split `git commit -m
 * "gate (alpha, …)" -- <paths>` at the "(" inside the message, the pathspec landed in another
 * segment, and a path-scoped commit was refused as "no pathspec" (twice in a row; `-F <file>` passed).
 * absence-gate split `grep -E "a|b" dir` at the "|" inside the pattern the same way. One splitter for
 * every helper that cuts a command into its parts.
 */
'use strict';

function segments(cmd) {
  const s = String(cmd || '');
  const out = [];
  let cur = '';
  let q = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) {
      if (c === '\\' && q === '"' && i + 1 < s.length) { cur += c + s[++i]; continue; }
      if (c === q) q = null;
      cur += c;
      continue;
    }
    if (c === '"' || c === "'") { q = c; cur += c; continue; }
    const two = s.slice(i, i + 2);
    if (two === '&&' || two === '||' || two === '$(') { out.push(cur); cur = ''; i++; continue; }
    if (c === '\n' || c === ';' || c === '|' || c === '&' || c === '(') { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out;
}

module.exports = { segments };
