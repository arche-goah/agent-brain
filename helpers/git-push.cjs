'use strict';
/**
 * Does a shell command line run `git push`? `push` must be git's SUBCOMMAND: `git [-C <dir>]
 * [-c k=v] [--opt…] push`. Reading "git … push" anywhere in the line also took a
 * `git commit -m "… push …"` for a push (measured 2026-10-25 on a macOS instance: a watch-gate
 * demand for a CI run that did not exist). A token walk, not one regex: the regex form with
 * optional option groups backtracks exponentially on a crafted line (CodeQL, 2026-10-26).
 * Shared by watch-gate.cjs and conditional-order-gate.cjs.
 */
const SEP = /&&|\|\||[;|\n&]/;

function words(segment) {
  const out = [];
  const re = /"([^"]*)"|'([^']*)'|(\S+)/g;
  let m;
  while ((m = re.exec(segment)) !== null) out.push(m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3]);
  return out;
}

function isGitPush(cmd) {
  for (const segment of String(cmd || '').split(SEP)) {
    const w = words(segment);
    for (let i = 0; i < w.length; i++) {
      if (!/(^|[\\/])git(\.exe)?$/i.test(w[i])) continue;
      let j = i + 1;
      while (j < w.length && w[j].startsWith('-')) j += (w[j] === '-C' || w[j] === '-c') ? 2 : 1;
      if (w[j] === 'push') return true;
    }
  }
  return false;
}

module.exports = { isGitPush };
