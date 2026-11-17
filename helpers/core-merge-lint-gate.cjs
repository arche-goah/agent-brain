#!/usr/bin/env node
/**
 * PreToolUse hook (Bash): two calls on the CORE repo run only on a green local lint stamp.
 *
 * 1. MERGE — `gh pr merge <n> -R <core>` runs only when scripts/core-merge-lint.sh stamped green for exactly
 *    this PR head merged with today's main (<brain>/.claude-state/core-merge-lint/<head>-<main>.ok). The core
 *    ruleset does not demand "branch up to date"; this gate carries what that rule caught (2026-10-27: CI green
 *    against an old main, red against today's). Head and main are read live with `git ls-remote`, never from the
 *    API (measured 2026-10-28: `gh pr view` reported a head one update behind); the head is the PR's BRANCH, not
 *    refs/pull/N/head (measured 2026-10-31: the pull ref stood one push behind the branch).
 * 2. PUSH — `git -C <worktree> push …` to the core (by URL, or by a remote name resolved in that worktree —
 *    2026-11-01 a push by remote name from a fresh clone went out unlinted) runs only when scripts/core-push-lint.sh
 *    stamped the pushed commit (<sha>.ok or <sha>.fast.ok in .claude-state/core-push-lint/). The pushed commit is the
 *    source of the first refspec, else HEAD (2026-11-02: a clone standing on main pushed another branch on main's
 *    stamp). Measured class: pushed on fixtures alone, the CI lint went red minutes later — 2026-10-21 twice,
 *    2026-10-26 three times, 2026-10-30.
 *
 * Ported 2026-11-17 from an instance alpha (in use since 2026-10-28, 129 sessions). THE CORE REPO is data, never a
 * name in this file: CORE_LINT_REPO=<owner/name>, else the origin of the core checkout this helper lives in (in a
 * brain: its core/ submodule). No readable repo = inert. A network read that fails = allow (the merge itself and
 * merge-request-gate still hold). Seams for the fixture: CORE_MERGE_LINT_REFS (JSON ref -> sha), CORE_MERGE_LINT_STAMPS,
 * CORE_PUSH_LINT_STAMPS, CORE_PUSH_LINT_HEAD, CORE_PUSH_REMOTE_URL, CORE_LINT_CHECKOUT.
 * Fixture: scripts/test-core-merge-lint-gate.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function git(args, timeout = 5000) {
  return execFileSync('git', args, { encoding: 'utf8', timeout, stdio: ['ignore', 'pipe', 'ignore'] });
}

/** owner/name of a GitHub URL, or null. */
function slug(url) {
  const m = /github\.com[:/]+([\w.-]+\/[\w.-]+?)(?:\.git)?\/?\s*$/.exec(String(url || '').trim());
  return m ? m[1] : null;
}

/** The core repo: data first, then the origin of the checkout this helper lives in. */
function coreRepo() {
  if (process.env.CORE_LINT_REPO) return process.env.CORE_LINT_REPO.replace(/^https:\/\/github\.com\//, '').replace(/\.git$/, '');
  const dir = process.env.CORE_LINT_CHECKOUT || path.join(__dirname, '..');
  try { return slug(git(['-C', dir, 'config', '--get', 'remote.origin.url'])); } catch (e) { return null; }
}

function projectDir(input) {
  return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd();
}

/** How the brain calls the core's scripts: core/scripts in a brain, scripts in a core checkout. */
function scriptsRel(root) {
  const rel = path.relative(root, path.join(__dirname, '..', 'scripts')).split(path.sep).join('/');
  return rel && !rel.startsWith('..') ? rel : 'core/scripts';
}

/** The PR number of a core merge call, or null. */
function target(cmd, repo) {
  const m = /(?:^|[\n;&|(]\s*)gh\s+pr\s+merge\s+(\d+)\b([^\n;&|]*)/.exec(cmd);
  if (!m) return null;
  const r = /(?:-R|--repo)[=\s]+["']?(\S+?)["']?(?:\s|$)/.exec(m[2]);
  return r && r[1].replace(/^https:\/\/github\.com\//, '').replace(/\.git$/, '') === repo ? m[1] : null;
}

/** The URL a push names: the URL itself, or the remote it names (first non-option argument, default origin). */
function pushUrl(dir, args) {
  const remote = (args.trim().split(/\s+/).filter((a) => a && !a.startsWith('-'))[0]) || 'origin';
  if (/:\/\/|@[\w.-]+:/.test(remote)) return remote;
  if (process.env.CORE_PUSH_REMOTE_URL !== undefined) return process.env.CORE_PUSH_REMOTE_URL;
  try { return git(['-C', dir, 'remote', 'get-url', '--push', remote]); } catch (e) { return ''; }
}

const PUSH_RX = /(?:^|[\n;&|(]\s*)git\s+-C\s+("[^"]+"|'[^']+'|\S+)\s+push\b([^\n;&|]*)/;

/** The worktree of a core push, or null. */
function pushTarget(cmd, repo) {
  const m = PUSH_RX.exec(cmd);
  if (!m) return null;
  const dir = m[1].replace(/^["']|["']$/g, '');
  return slug(pushUrl(dir, m[2])) === repo ? dir : null;
}

/** The commit a push sends: the source of its first refspec, else HEAD. */
function headOf(dir, args) {
  if (process.env.CORE_PUSH_LINT_HEAD) return process.env.CORE_PUSH_LINT_HEAD;
  const words = String(args || '').trim().split(/\s+/).filter((w) => w && !w.startsWith('-'));
  const src = words.length >= 2 ? words[1].replace(/^\+/, '').split(':')[0] : '';
  const rev = src && src !== 'HEAD' ? `${src}^{commit}` : 'HEAD';
  return git(['-C', dir, 'rev-parse', '--verify', '-q', rev]).trim();
}

function judgePush(cmd, repo, root) {
  const dir = pushTarget(cmd, repo);
  if (!dir) return null;
  let head;
  try { head = headOf(dir, PUSH_RX.exec(cmd)[2]); } catch (e) { return null; }
  const stamps = process.env.CORE_PUSH_LINT_STAMPS || path.join(root, '.claude-state', 'core-push-lint');
  if (fs.existsSync(path.join(stamps, `${head}.ok`)) || fs.existsSync(path.join(stamps, `${head}.fast.ok`))) return null;
  return `CORE-PUSH-LINT: the core branch in ${dir} has no green ci-lint-local stamp for ${head.slice(0, 7)}. ` +
    `Run \`bash ${scriptsRel(root)}/core-push-lint.sh --fast ${dir}\` detached (seconds; the full run belongs to a merge ` +
    'train head only), read its GREEN line, then push. Pushed on fixtures alone, the CI lint went red minutes later ' +
    '(2026-10-21, 2026-10-26 three times, 2026-10-30).';
}

/** refs/heads/<branch> of a same-repo PR, or a ref that resolves to nothing. */
function branchRef(pr, repo) {
  if (process.env.CORE_MERGE_LINT_REFS) return `branch-of-${pr}`;
  try {
    const name = execFileSync('gh', ['pr', 'view', pr, '-R', repo, '--json', 'headRefName,isCrossRepository', '-q',
      'select(.isCrossRepository|not) | .headRefName'], { encoding: 'utf8', timeout: 15000 }).trim();
    return name ? `refs/heads/${name}` : 'refs/heads/-none-';
  } catch (e) { return 'refs/heads/-none-'; }
}

function lsRemote(ref, repo) {
  if (process.env.CORE_MERGE_LINT_REFS) return JSON.parse(process.env.CORE_MERGE_LINT_REFS)[ref] || null;
  const out = git(['ls-remote', `https://github.com/${repo}`, ref], 15000);
  return (out.split(/\s/)[0] || '').trim() || null;
}

function judge(input) {
  if (!input || input.tool_name !== 'Bash') return null;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!/\bgh\s+pr\s+merge\b|\bgit\s+-C\b[^\n]*\bpush\b/.test(cmd)) return null;
  const repo = coreRepo();
  if (!repo) return null;
  const root = projectDir(input);
  const push = judgePush(cmd, repo, root);
  if (push) return push;
  const pr = target(cmd, repo);
  if (!pr) return null;
  let head, main;
  try { head = lsRemote(branchRef(pr, repo), repo) || lsRemote(`refs/pull/${pr}/head`, repo); main = lsRemote('refs/heads/main', repo); } catch (e) { return null; }
  if (!head || !main) return null;
  const stamps = process.env.CORE_MERGE_LINT_STAMPS || path.join(root, '.claude-state', 'core-merge-lint');
  if (fs.existsSync(path.join(stamps, `${head}-${main}.ok`))) return null;
  return `CORE-MERGE-LINT: core PR #${pr} has no green lint stamp for head ${head.slice(0, 7)} merged with main ${main.slice(0, 7)}. ` +
    `Run \`bash ${scriptsRel(root)}/core-merge-lint.sh ${pr}\` detached, read its GREEN line, then merge. ` +
    'The ruleset does not demand an up-to-date branch; this lint on the merged state carries what that rule caught.';
}

module.exports = { judge, target, pushTarget, coreRepo, slug };

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let reason = null;
    try { reason = judge(JSON.parse(raw)); } catch (e) { reason = null; }
    if (reason) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
    }
    process.exit(0);
  });
}
