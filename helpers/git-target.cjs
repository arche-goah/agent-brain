'use strict';
/**
 * git-target.cjs - the ONE reader of which directory a shell command's `git` invocations act on.
 *
 * WHY (measured 2026-11-20 on the macOS instance, class search after a Windows review of #620): seven gates kept
 * their own reader of the `git -C <dir>` target, and the forms they understood differed - quoted or not, `-C<dir>`
 * without a space, the Git Bash drive form `/c/...`, a leading `~`, a `cd <dir> &&` before the call. A gate that
 * read the hook's cwd instead of the target judged the wrong repo. Measured again 2026-11-23: a regex reader took
 * `-C reader` INSIDE a quoted commit message for `git -C <repo>` and blocked the commit. This reader works on the
 * shell's own words (published-text.cjs `shellSegments`), so a quoted argument is one word and never an option.
 *
 * gitCalls(cmd, cwd, ps) -> [{ dir, sub, args, words }] for every `git` invocation at command position
 * (`git`, a path to it, `git.exe`, after `env`/`sudo`/`VAR=x` prefixes); null when the command cannot be read.
 *   dir   the directory git runs in: the last `cd/pushd <dir>` earlier in the same command (PowerShell: cd, chdir,
 *         sl, Set-Location, Push-Location), then `env -C <dir>`, then each `git -C <dir>` in turn (git applies them
 *         relative to each other); `~` and `$HOME` are the home folder, a Git Bash drive path is made native (OS-19)
 *   sub   the subcommand (first word after git's own options), args = the words after it, words = the whole call
 * gitTarget(cmd, cwd, ps, subs) -> dir of the first call whose `sub` is in `subs` (any call when omitted), else null.
 * Fixture: scripts/test-git-target.sh
 */
const path = require('path');
const os = require('os');
const { shellSegments, nativePath } = require('./published-text.cjs');

const DIR_SH = /^(?:cd|pushd)$/;
const DIR_PS = /^(?:cd|chdir|sl|set-location|push-location|pushd)$/i;
// git's global options that take the next word as their value
const WITH_VALUE = new Set(['-c', '--git-dir', '--work-tree', '--namespace', '--exec-path', '--config-env']);

function home() { return process.env.HOME || process.env.USERPROFILE || os.homedir(); }

function abs(base, d) {
  const h = home();
  const s = String(d).replace(/^~(?=$|[\\/])/, h).replace(/^\$HOME(?=$|[\\/])/, h).replace(/^\$\{HOME\}(?=$|[\\/])/, h);
  return path.resolve(base, nativePath(s));
}

const isGit = (w) => String(w).replace(/\\/g, '/').replace(/^.*\//, '').replace(/\.exe$/i, '') === 'git';

function gitCalls(cmd, cwd, ps) {
  const segs = shellSegments(String(cmd || ''), ps);
  if (!segs) return null;
  let dir = path.resolve(cwd || process.cwd());
  const out = [];
  for (const w of segs) {
    if (!w.length) continue;
    if (ps ? DIR_PS.test(w[0]) : DIR_SH.test(w[0])) {
      const to = w.slice(1).find((x) => !/^-(?:-|P|L|Path|LiteralPath)$/i.test(x));
      if (to && to !== '-') dir = abs(dir, to);
      continue;
    }
    // prefixes before git: env [-C dir] [-u x] [VAR=x]..., sudo, VAR=x
    let i = 0; let here = dir;
    while (i < w.length && !isGit(w[i])) {
      const t = w[i];
      if (t === 'env' || /(^|\/)env$/.test(t)) {
        i += 1;
        while (i < w.length && !isGit(w[i])) {
          if ((w[i] === '-C' || w[i] === '--chdir') && w[i + 1]) { here = abs(here, w[i + 1]); i += 2; continue; }
          if (/^--chdir=/.test(w[i])) { here = abs(here, w[i].slice(8)); i += 1; continue; }
          if (w[i] === '-u' || w[i] === '--unset') { i += 2; continue; }
          i += 1;
        }
        break;
      }
      if (t === 'sudo' || /^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { i += 1; continue; }
      break;
    }
    if (i >= w.length || !isGit(w[i])) continue;
    const words = w.slice(i);
    let j = 1;
    while (j < words.length && String(words[j]).startsWith('-')) {
      const t = words[j];
      if (t === '-C' && words[j + 1] !== undefined) { here = abs(here, words[j + 1]); j += 2; continue; }
      if (/^-C./.test(t)) { here = abs(here, t.slice(2)); j += 1; continue; }
      if (WITH_VALUE.has(t)) { j += 2; continue; }
      j += 1;
    }
    if (j >= words.length) continue;
    out.push({ dir: here, sub: words[j], args: words.slice(j + 1), words });
  }
  return out;
}

function gitTarget(cmd, cwd, ps, subs) {
  const calls = gitCalls(cmd, cwd, ps) || [];
  const c = calls.find((x) => !subs || subs.includes(x.sub));
  return c ? c.dir : null;
}

module.exports = { gitCalls, gitTarget };
