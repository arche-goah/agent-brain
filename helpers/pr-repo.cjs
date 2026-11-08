/**
 * pr-repo.cjs — which repo(s) does a `gh pr create` in this command target? ['owner/repo', ...] (lowercase).
 *
 * WHY (measured 2026-11-08 on the macOS instance): two instance rules that hold a PR in a self-run repo matched the
 * repo's NAME in the command text, so `env -C <checkout> gh pr create --fill` (repo only implied by the directory)
 * went through. The operator released a core guard that resolves the repo itself (question tool, 2026-11-08).
 *
 * Order, per `gh pr create` invocation: `--repo/-R <owner/repo>`; else the directory it runs in — `env -C <dir>`
 * before `gh`, else the last `cd <dir>` earlier in the same command, else the hook's cwd — read through
 * `git -C <dir> config --get remote.origin.url`. An unreadable command or a directory without an origin gives no
 * entry for that invocation (the caller decides; mechanism-guard treats "no repo" as "no match").
 */
const path = require('path');
const { execFileSync } = require('child_process');
const { shellSegments } = require('./published-text.cjs');

function slug(url) {
  const m = /[/:]([^/:]+)\/([^/]+?)(?:\.git)?\/?$/.exec(String(url || '').trim());
  return m ? `${m[1]}/${m[2]}`.toLowerCase() : '';
}

function originOf(dir) {
  try {
    return slug(execFileSync('git', ['-C', dir, 'config', '--get', 'remote.origin.url'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000 }));
  } catch (_) { return ''; }
}

function flagValue(w, i, names) {
  const t = w[i];
  for (const f of names) {
    if (t === f) return w[i + 1] || '';
    if (f.startsWith('--') && t.startsWith(f + '=')) return t.slice(f.length + 1);
  }
  return null;
}

function prTargets(cmd, cwd, ps) {
  const segs = shellSegments(String(cmd || ''), ps);
  if (!segs) return [];
  const home = process.env.HOME || process.env.USERPROFILE || '';
  const abs = (base, d) => path.resolve(base, String(d).replace(/^~(?=$|\/)/, home));
  let dir = cwd || process.cwd();
  const out = [];
  for (const w of segs) {
    if (w[0] === 'cd' && w[1]) { dir = abs(dir, w[1]); continue; }
    const g = w.indexOf('gh');
    if (g < 0 || w[g + 1] !== 'pr' || w[g + 2] !== 'create') continue;
    let here = dir;
    for (let i = 0; i < g; i++) {
      if (w[i] === 'env' || /(^|\/)env$/.test(w[i])) {
        for (let j = i + 1; j < g; j++) if (w[j] === '-C' && w[j + 1]) here = abs(here, w[j + 1]);
      }
    }
    let repo = '';
    for (let j = g + 3; j < w.length; j++) repo = flagValue(w, j, ['--repo', '-R']) || repo;
    const r = repo ? (repo.includes('/') ? repo.toLowerCase() : '') : originOf(here);
    if (r) out.push(r);
  }
  return out;
}

module.exports = { prTargets, slug };
