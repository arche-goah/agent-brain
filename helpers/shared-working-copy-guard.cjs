#!/usr/bin/env node
/**
 * shared-working-copy-guard.cjs — PreToolUse(Bash|Monitor): two sessions, one working
 * copy — git writes that act on the WHOLE index or HEAD are refused while another session
 * works in the same checkout, and a merge/rebase another session started is not touched.
 *
 * WHY (three incidents in three days on the proving brain, 2026-10-11..13; the ledger
 * entry had the invariant each time and no carrier): (1) `git add -A <paths>` staged into
 * a rebase the other session had open; (2) `git commit --amend` rewrote the other
 * session's commit that had landed between two own commits; (3) `git commit -m` took the
 * whole index — the other session's staged files went out under the wrong message. All
 * three share one root: a working copy has ONE index and ONE HEAD, and git cannot tell
 * two sessions apart. Separate worktrees do not fit a brain: both sessions append to the
 * same protocol, log and ledger files, so a branch per session only moves the collision
 * into the merge. The operator's direction (2026-10-13): "the agreement between local
 * parallel sessions needs extended mechanics that ensures clean parallel work without
 * conflicts".
 *
 * WHAT IT DOES. Only when the target checkout is SHARED (see below):
 *   - `git commit` without a pathspec, `commit -a/--all`, `commit --amend`  → deny
 *     (commit BY PATH: `git commit <paths> -m …` takes only those files)
 *   - `git add -A/--all/-u/--update/.`                                        → deny
 *   - `git stash …`, `git reset --hard/--merge/--keep`, `git checkout <branch>`,
 *     `git switch …`                                                           → deny
 *   - `git rebase`, `git merge` (not --ff-only), `git pull` (not --ff-only),
 *     `git cherry-pick`, `git revert`                                          → deny
 *   - `git push --force/-f/--force-with-lease`                                 → deny
 *   Every refusal names the by-path form that passes. The marker `# MECHANISM-OK: <why>`
 *   opens a rule, as with mechanism-guard — a deviation is possible, never silent.
 * And in every checkout, shared or not, when `.git/rebase-merge`, `rebase-apply`,
 * `MERGE_HEAD` or `CHERRY_PICK_HEAD` exists: the operation belongs to the session that
 * started it. The guard writes `.git/claude-op-owner` (the session id from the hook input)
 * when it lets a rebase/merge/pull/cherry-pick start; while the operation is open, a git
 * write from a session that is not the owner is refused — WHEN a second session runs.
 * With one session on the machine the owner file is ignored: a leftover operation of a
 * dead session is the live session's to finish.
 *
 * SHARED means: a second claude session exists on this machine (process list, CLI calls
 * such as `claude plugin list` filtered out as in scripts/parallel-sessions.sh), AND the
 * target checkout is not private to this session. Private: a path under the harness's
 * scratchpad tree (`…/claude-<uid>/<project>/<session>/…`, e.g. a `git worktree` a
 * session made for one PR). Repo-exact detection (lsof: another session's cwd IS this
 * checkout) marks shared for sure; without lsof the count alone decides — a checkout
 * both sessions reach via `git -C <path>` (the shared-memory repo) is shared although it
 * is nobody's cwd, and that is exactly incident (2) and (3).
 *
 * Fail-open on every error (read-only hook, no decision on a broken probe). Log:
 * <project>/.claude-state/shared-working-copy-guard.log.
 * Fixture seam: SHARED_COPY_FIXTURE_SESSIONS="<cwd1>;<cwd2>" stands in for the process
 * list (one entry per session), so the logic is testable on every platform.
 */
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const OP_STATES = ['rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD'];
const OWNER_FILE = 'claude-op-owner';
const SCRATCHPAD_RE = /[\\/]claude-\d+[\\/][^\\/]+[\\/][0-9a-f-]{36}[\\/]/;

function isCliCall(args) {
  const first = (args || '').trim().split(/\s+/)[1] || '';
  return /^(plugin|mcp|config|update|doctor|install|setup-token|migrate-installer|--version|-v|--help|-h)$/.test(first);
}

// Every other claude session on this machine, as {pid, cwd|null}.
function sessions() {
  const fx = process.env.SHARED_COPY_FIXTURE_SESSIONS;
  if (fx !== undefined) {
    return fx.split(';').filter((s) => s !== '').map((cwd, i) => ({ pid: 1000 + i, cwd: cwd === '-' ? null : cwd }));
  }
  const out = [];
  if (process.platform === 'win32') {
    const r = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
      "Get-CimInstance Win32_Process -Filter \"Name='claude.exe'\" | ForEach-Object { $_.ProcessId.ToString() + ' ' + $_.CommandLine }"],
      { encoding: 'utf8', timeout: 5000 });
    if (r.status !== 0) return null;
    for (const line of (r.stdout || '').split(/\r?\n/)) {
      const m = /^(\d+)\s+(.*)$/.exec(line.trim());
      if (!m || isCliCall(m[2])) continue;
      out.push({ pid: Number(m[1]), cwd: null });
    }
    return out;
  }
  const ps = spawnSync('ps', ['-axo', 'pid=,comm=,args='], { encoding: 'utf8', timeout: 5000 });
  if (ps.status !== 0) return null;
  for (const line of (ps.stdout || '').split('\n')) {
    const m = /^\s*(\d+)\s+(\S+)\s+(.*)$/.exec(line);
    if (!m || !/(^|\/)claude$/.test(m[2]) || isCliCall(m[3])) continue;
    let cwd = null;
    const lsof = spawnSync('lsof', ['-a', '-p', m[1], '-d', 'cwd', '-Fn'], { encoding: 'utf8', timeout: 5000 });
    if (lsof.status === 0) {
      const n = /^n(.*)$/m.exec(lsof.stdout || '');
      if (n) cwd = n[1];
    }
    out.push({ pid: Number(m[1]), cwd });
  }
  return out;
}

function gitDir(repo) {
  const r = spawnSync('git', ['-C', repo, 'rev-parse', '--git-dir'], { encoding: 'utf8', timeout: 5000 });
  if (r.status !== 0) return null;
  const d = (r.stdout || '').trim();
  return path.isAbsolute(d) ? d : path.join(repo, d);
}

function topLevel(repo) {
  const r = spawnSync('git', ['-C', repo, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', timeout: 5000 });
  return r.status === 0 ? (r.stdout || '').trim() : null;
}

// Split a shell line into the git invocations at command position: start of line or after
// ; & | ( — with an optional sudo/env/VAR= prefix. Returns [{repo, sub, args[]}].
function gitCalls(cmd, project) {
  const calls = [];
  for (const seg of cmd.split(/\n|;|&&|\|\||\||&|\$\(|\(/)) {
    const m = /^\s*(?:(?:sudo|env)\s+)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*[\\/])?git\s+(.*)$/.exec(seg);
    if (!m) continue;
    const toks = tokens(m[1]);
    let repo = project;
    let i = 0;
    while (i < toks.length && toks[i].startsWith('-')) {
      if (toks[i] === '-C' && toks[i + 1]) { repo = path.resolve(project, toks[i + 1]); i += 2; continue; }
      if (toks[i].startsWith('-C') && toks[i].length > 2) { repo = path.resolve(project, toks[i].slice(2)); i += 1; continue; }
      if (toks[i] === '-c' && toks[i + 1]) { i += 2; continue; }
      i += 1;
    }
    if (i >= toks.length) continue;
    calls.push({ repo, sub: toks[i], args: toks.slice(i + 1) });
  }
  return calls;
}

function tokens(s) {
  const out = [];
  const re = /"((?:[^"\\]|\\.)*)"|'([^']*)'|(\S+)/g;
  let m;
  while ((m = re.exec(s))) out.push(m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3]);
  return out.map((t) => t.replace(/^#.*$/, '')).filter((t) => t !== '');
}

// Options of `git commit` that take a value, so the value is not mistaken for a pathspec.
const COMMIT_VALUE_OPTS = new Set(['-m', '-F', '--file', '--message', '--author', '--date', '-C', '-c',
  '--reuse-message', '--reedit-message', '--fixup', '--squash', '--cleanup', '--template', '-t', '--trailer']);

function commitHasPathspec(args) {
  let i = 0;
  while (i < args.length) {
    const a = args[i];
    if (a === '--') return args.length > i + 1;
    if (a.startsWith('-')) {
      if (COMMIT_VALUE_OPTS.has(a) && !a.includes('=')) i += 2; else i += 1;
      continue;
    }
    return true;
  }
  return false;
}

function hasOpt(args, ...names) {
  return args.some((a) => names.includes(a) || names.some((n) => n.startsWith('--') && a.startsWith(n + '=')));
}

// What a git call does to a shared checkout. Returns null (fine), or {was, instead, starts}.
function judge(call) {
  const { sub, args } = call;
  const pos = args.filter((a) => !a.startsWith('-'));
  switch (sub) {
    case 'commit':
      if (hasOpt(args, '--amend')) return { was: '`git commit --amend` rewrites HEAD — in a shared working copy HEAD may be the other session\'s commit (measured 2026-10-12: four files landed in a foreign commit)',
        instead: 'a new commit by path: `git commit <paths> -m "…"`; what is wrong in an old commit gets a follow-up commit' };
      if (hasOpt(args, '-a', '--all')) return { was: '`git commit -a` commits every modified file — including the other session\'s',
        instead: 'commit by path: `git commit <paths> -m "…"`' };
      if (!commitHasPathspec(args)) return { was: '`git commit` without a pathspec takes the WHOLE index — the other session\'s staged files go out under your message (measured 2026-10-13)',
        instead: 'commit by path: `git commit <paths> -m "…"` — only those files, whatever else is staged' };
      return null;
    case 'add':
      if (hasOpt(args, '-A', '--all', '-u', '--update', '--no-ignore-removal') || pos.includes('.') || pos.includes(':/'))
        return { was: '`git add -A/-u/.` stages the other session\'s edits too', instead: 'stage by path: `git add <paths>`' };
      return null;
    case 'stash':
      return { was: '`git stash` removes the other session\'s uncommitted work from the tree', instead: 'commit your own files by path instead of stashing; the tree is shared' };
    case 'reset':
      if (hasOpt(args, '--hard', '--merge', '--keep')) return { was: '`git reset --hard/--merge/--keep` discards the other session\'s uncommitted work',
        instead: '`git restore <paths>` for your own files; `git reset --soft <commit>` only for a commit that is yours' };
      return null;
    case 'checkout':
      if (pos.length && !args.includes('--') && !hasOpt(args, '-b', '-B')) {
        // `git checkout <branch>` moves HEAD for both; `git checkout -- <paths>` / `checkout <ref> -- <paths>` is file-level
        const ref = pos[0];
        const r = spawnSync('git', ['-C', call.repo, 'rev-parse', '--verify', '--quiet', ref + '^{commit}'], { encoding: 'utf8', timeout: 5000 });
        if (r.status === 0 && pos.length === 1) return { was: '`git checkout <branch>` moves HEAD for every session in this working copy', instead: 'a `git worktree add` under your scratchpad for branch work; the shared checkout stays on its branch' };
      }
      if (hasOpt(args, '-b', '-B')) return { was: 'a new branch in a shared working copy moves HEAD for the other session too', instead: '`git worktree add -b <branch> <scratchpad-dir> origin/main` — your own index and HEAD' };
      return null;
    case 'switch':
      return { was: '`git switch` moves HEAD for every session in this working copy', instead: '`git worktree add` under your scratchpad for branch work' };
    case 'rebase':
      if (hasOpt(args, '--continue', '--abort', '--skip', '--quit')) return null; // owner check below
      return { was: '`git rebase` rewrites commits that may be the other session\'s and leaves a state the other session walks into (measured 2026-10-11)', instead: '`git pull --ff-only`; if main diverged: commit your paths, then `git pull --rebase` with the marker, and finish it in the same turn', starts: true };
    case 'merge':
      if (hasOpt(args, '--continue', '--abort', '--quit')) return null;
      if (hasOpt(args, '--ff-only')) return null;
      return { was: '`git merge` can leave a conflict state the other session walks into', instead: '`git merge --ff-only`, or the merge with the marker, finished in the same turn', starts: true };
    case 'pull':
      if (hasOpt(args, '--ff-only')) return null;
      return { was: '`git pull` (merge or rebase) can leave a conflict state the other session walks into', instead: '`git pull --ff-only`; if that fails, commit your paths first, then pull with the marker and finish in the same turn', starts: true };
    case 'cherry-pick':
    case 'revert':
      if (hasOpt(args, '--continue', '--abort', '--skip', '--quit')) return null;
      return { was: `\`git ${sub}\` can leave a conflict state the other session walks into`, instead: 'run it with the marker and finish it in the same turn', starts: true };
    case 'push':
      if (hasOpt(args, '-f', '--force', '--force-with-lease', '--force-if-includes')) return { was: 'a force-push in a shared working copy throws away commits that may be the other session\'s', instead: '`git push` (fast-forward); a wrong commit gets a follow-up commit, never a rewrite' };
      return null;
    default:
      return null;
  }
}

const WRITES = new Set(['add', 'commit', 'rebase', 'merge', 'pull', 'cherry-pick', 'revert', 'reset', 'checkout', 'switch', 'stash', 'am', 'apply', 'rm', 'mv', 'restore']);

function openOperation(gd) {
  return OP_STATES.find((s) => fs.existsSync(path.join(gd, s))) || null;
}

function deny(reason, project, cmd) {
  try {
    fs.appendFileSync(path.join(project, '.claude-state', 'shared-working-copy-guard.log'),
      `${new Date().toISOString()} BLOCKED: ${cmd.slice(0, 200)}\n`);
  } catch (_) {}
  console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
  process.exit(0);
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let data;
  try { data = JSON.parse(input); } catch (_) { process.exit(0); }
  const cmd = (data.tool_input && data.tool_input.command) || '';
  if (!/\bgit\b/.test(cmd)) process.exit(0);
  const project = process.env.CLAUDE_PROJECT_DIR || data.cwd || '.';
  const sid = String(data.session_id || '');
  const marker = /MECHANISM-OK:/.test(cmd);
  let calls;
  try { calls = gitCalls(cmd, project); } catch (_) { process.exit(0); }
  if (!calls.length) process.exit(0);

  // Sessions on this machine, this one included — counted once, only when a call needs it.
  // The hook cannot tell its own session apart by pid (it runs under a shell the session
  // spawned), so the count is the measure: two or more means the copy may be shared.
  let count = null;
  const sessionCount = () => {
    if (count === null) { const s = sessions(); count = s === null ? 0 : s.length; }
    return count;
  };

  for (const call of calls) {
    const top = topLevel(call.repo);
    if (!top) continue;
    const gd = gitDir(top);
    if (!gd) continue;
    const isPrivate = SCRATCHPAD_RE.test(top + path.sep);
    const second = sessionCount() >= 2;
    const shared = !isPrivate && second;
    const op = openOperation(gd);
    const ownerPath = path.join(gd, OWNER_FILE);

    if (op && second && WRITES.has(call.sub)) {
      let owner = '';
      try { owner = fs.readFileSync(ownerPath, 'utf8').trim(); } catch (_) {}
      if (owner !== sid && !marker) {
        deny(`SHARED WORKING COPY (${top}): a ${op.replace(/_HEAD$/, '').toLowerCase()} is in progress that THIS session did not start` +
          (owner ? ` (owner session ${owner.slice(0, 8)}…)` : ' (no owner recorded — started outside a guarded session)') +
          `.\n\nLeave it: do not stage, commit, continue or abort it. Message the other session (SendMessage / ListAgents) or wait\n` +
          `until \`${op}\` is gone from the git dir. Your own files are safe in the tree; commit them by path once the\n` +
          `operation is finished. If the operation is yours after all: repeat with "# MECHANISM-OK: <why it is mine>".`, project, cmd);
      }
    }

    const verdict = judge(call);
    if (verdict && shared && !marker) {
      deny(`SHARED WORKING COPY (${top}): another claude session works on this machine, and this checkout is not private to\n` +
        `this session (one index, one HEAD for both).\n\n  ${verdict.was}\n\nThe form that passes:\n  ${verdict.instead}\n\n` +
        `If this really has to run as written: repeat with "# MECHANISM-OK: <justification>" — then finish what it starts in the\n` +
        `same turn, so the other session never meets a half-done state.`, project, cmd);
    }
    if (verdict && verdict.starts && sid) {
      // An operation that is allowed to start (marker, or no second session) belongs to this session.
      try { fs.writeFileSync(ownerPath, sid + '\n'); } catch (_) {}
    } else if (!op) {
      try { fs.unlinkSync(ownerPath); } catch (_) {}
    }
  }
  process.exit(0);
});
