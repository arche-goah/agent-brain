/**
 * branch-start.cjs - the ONE reader of "this command starts a new branch", for every gate that holds a branch start
 * (release-freeze-gate, pr-overlap-gate). Reads the command's real git invocations (published-text.cjs
 * `invocations`: quotes, PowerShell, `& "...\git.exe"`), not a regex over the text:
 *   git [-C <dir>] [-c k=v] worktree add ... -b|-B <branch>
 *   git [-C <dir>] checkout -b|-B <branch>
 *   git [-C <dir>] switch -c|-C|--create|--force-create <branch>
 * WHY (Windows review of #563, 2026-11-17): pr-overlap-gate carried a second copy as a regex that missed
 * `switch --create`, a `-c` option before the subcommand, and a quoted -C path with a space; the two readers of one
 * question gave two answers.
 */
'use strict';
const path = require('path');
const { invocations } = require('./published-text.cjs');

// OS-19: a Git Bash path (`/c/x`) as the shell sees it is `C:/x` for node on Windows.
function nativeDir(p) {
  const m = process.platform === 'win32' && /^\/([a-zA-Z])(\/|$)(.*)$/.exec(p);
  return m ? `${m[1].toUpperCase()}:/${m[3]}` : p;
}

function value(w, i, flags) {   // `--flag v` or `--flag=v`
  const t = w[i];
  for (const f of flags) {
    if (t === f) return w[i + 1] || '';
    if (f.startsWith('--') && t.startsWith(f + '=')) return t.slice(f.length + 1);
  }
  return null;
}

/** Every new branch the command's git calls start: [{ branch, dir }], or null when the command cannot be read. */
function gitStarts(cmd, ps, cwd) {
  const gits = invocations(cmd, ps, 'git');
  if (gits === null) return null;
  const out = [];
  for (const w of gits) {
    let i = 1;
    let dir = cwd;
    while (i < w.length && w[i].startsWith('-')) {
      if (w[i] === '-C') { dir = path.resolve(dir, nativeDir(w[i + 1] || '')); i += 2; } else if (w[i] === '-c') i += 2; else i++;
    }
    const sub = w[i];
    const rest = w.slice(i + 1);
    let flags = null;
    if (sub === 'worktree' && rest[0] === 'add') flags = ['-b', '-B'];
    else if (sub === 'checkout') flags = ['-b', '-B'];
    else if (sub === 'switch') flags = ['-c', '-C', '--create', '--force-create'];
    if (!flags) continue;
    for (let j = 0; j < rest.length; j++) {
      const b = value(rest, j, flags);
      if (b) { out.push({ branch: b, dir }); break; }
    }
  }
  return out;
}

module.exports = { gitStarts, value, nativeDir };
