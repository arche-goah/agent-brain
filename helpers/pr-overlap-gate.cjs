#!/usr/bin/env node
/**
 * PreToolUse hook (operator decision 2026-10-28, ran as an instance alpha until this port): before
 * `gh pr create`, the open PRs of the target repo that change the same files are named — once.
 *
 * WHY (measured 2026-10-28 on the macOS instance): core PR #210 duplicated the parallel session's #194
 * (the same three files, #194 covering more); the open PRs touching those files were never read before
 * building. Second case of the class: 2026-10-11, #297 duplicated #294.
 * The lesson lived as prose for 17 days — core working rule #10: a promise without a mechanism does
 * not carry.
 *
 * Mechanics: on `gh pr create … --head <branch> -R|--repo <owner/repo>`, read the branch's changed files
 * (`gh api repos/<r>/compare/<base>...<head>`) and the open PRs with their files (`gh pr list --limit 100
 * --json number,title,headRefName,files`). An overlap with another PR's files = deny ONCE, naming the PRs and
 * files. Pass: the same command with `# OVERLAP-OK: <why>` (read the other PR first), or no overlap.
 * Fails open: no repo/head in the command, network or parse error, no gh. Test fixture via
 * PR_OVERLAP_FIXTURE (JSON {files:[…], prs:[{number,title,headRefName,files:[{path}]}]}).
 * Test: scripts/test-pr-overlap-gate.sh. Sibling of merge-request-gate.cjs; ran as an instance alpha
 * 2026-10-28 to 2026-11-17 (in use in 27 sessions) before this port.
 */
'use strict';
const { execFileSync } = require('child_process');

function target(cmd) {
  if (!/(?:^|[\n;&|(]\s*)gh\s+pr\s+create\b/.test(cmd)) return null;
  const repo = /(?:-R|--repo)[=\s]+(\S+)/.exec(cmd);
  const head = /--head[=\s]+(\S+)/.exec(cmd);
  const base = /(?:-B|--base)[=\s]+(\S+)/.exec(cmd);
  if (!repo || !head) return null;
  return { repo: repo[1].replace(/^https:\/\/github\.com\//, ''), head: head[1], base: base ? base[1] : 'main' };
}

// Second hook point (2026-10-29, third case of the class): a branch START — `git [-C <dir>] worktree add
// … -b <branch>` or `git [-C <dir>] checkout|switch -b|-c <branch>` — names the repo's open PRs before
// anything is built. Measured: a translation for grandma3-suite was built from a ledger line ("next:
// mcp/REFERENCE.md") while the same AI's #232 of the evening before already carried it; the create-time
// check came after the work. Pass: `# PRS-READ: <which one is closest, or none>`.
function branchStart(cmd) {
  const m = /(?:^|[\n;&|(]\s*)git\s+(?:-C\s+("[^"]+"|\S+)\s+)?(?:worktree\s+add\b[^\n;&|]*?\s-[bB]\s+(\S+)|(?:checkout|switch)\s+-[bcBC]\s+(\S+))/.exec(cmd);
  if (!m) return null;
  return { dir: m[1] ? m[1].replace(/^"|"$/g, '') : process.cwd(), branch: m[2] || m[3] };
}

function repoOf(dir) {
  const url = execFileSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const m = /github\.com[:/]([^/]+\/[^/.\s]+?)(?:\.git)?$/.exec(url);
  return m ? m[1] : null;
}

function judgeStart(cmd) {
  if (/#\s*PRS-READ:\s*\S/.test(cmd)) return null;
  const s = branchStart(cmd);
  if (!s) return null;
  let repo, prs;
  try {
    if (process.env.PR_OVERLAP_FIXTURE) ({ repo, prs } = JSON.parse(process.env.PR_OVERLAP_FIXTURE));
    else {
      repo = repoOf(s.dir);
      if (!repo) return null;
      prs = JSON.parse(gh(['pr', 'list', '-R', repo, '--state', 'open', '--limit', '30', '--json', 'number,title,headRefName']));
    }
  } catch (e) { return null; }
  if (!Array.isArray(prs) || !prs.length) return null;
  const same = prs.filter((p) => p.headRefName === s.branch);
  const list = prs.slice(0, 8).map((p) => `#${p.number} ${String(p.title).slice(0, 60)}`).join(' · ');
  return `PRS-FIRST: ${repo} has ${prs.length} open PR(s) — read them before building on a new branch: ${list}` +
    (prs.length > 8 ? ` · (+${prs.length - 8})` : '') +
    (same.length ? `. An open PR already uses the branch name ${s.branch}: #${same[0].number}.` : '.') +
    ' Third case of the class 2026-10-29 (#210/#194, #297/#294, grandma3 #232 rebuilt). Pass: the same command with ' +
    '`# PRS-READ: <the closest PR, or none>`.';
}

function gh(args) {
  return execFileSync('gh', args, { encoding: 'utf8', timeout: 20000, stdio: ['ignore', 'pipe', 'ignore'] });
}

function read(t) {
  if (process.env.PR_OVERLAP_FIXTURE) return JSON.parse(process.env.PR_OVERLAP_FIXTURE);
  const files = gh(['api', `repos/${t.repo}/compare/${t.base}...${t.head}`, '--jq', '[.files[].filename]']);
  const prs = gh(['pr', 'list', '-R', t.repo, '--state', 'open', '--limit', '100',
    '--json', 'number,title,headRefName,files']);
  return { files: JSON.parse(files), prs: JSON.parse(prs) };
}

function judge(input) {
  if (!input || input.tool_name !== 'Bash') return null;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  const start = judgeStart(cmd);
  if (start) return start;
  if (/#\s*OVERLAP-OK:\s*\S/.test(cmd)) return null;
  const t = target(cmd);
  if (!t) return null;
  let data;
  try { data = read(t); } catch (e) { return null; }
  const mine = new Set(data.files || []);
  if (!mine.size) return null;
  // Short (operator 2026-10-31: as short and informative as possible): the PRs with the most shared files first,
  // at most 5, at most 3 files each - a stacked branch listed ~45 PRs with every file (~5000 characters).
  const found = [];
  for (const pr of data.prs || []) {
    if (pr.headRefName === t.head) continue;
    const shared = (pr.files || []).map((f) => f.path).filter((p) => mine.has(p));
    if (shared.length) found.push({ pr, shared });
  }
  if (!found.length) return null;
  found.sort((a, b) => b.shared.length - a.shared.length || a.pr.number - b.pr.number);
  const hits = found.slice(0, 5).map(({ pr, shared }) => `#${pr.number} "${String(pr.title).slice(0, 60)}" (${shared.slice(0, 3).join(', ')}`
    + (shared.length > 3 ? ` +${shared.length - 3}` : '') + ')');
  const more = found.length > 5 ? `; +${found.length - 5} more PR(s)` : '';
  return `PR-OVERLAP: ${found.length} open PR(s) in ${t.repo} change files of this branch: ${hits.join('; ')}${more}. ` +
    'Read them first (diff, comments) — a duplicate costs a round and a cut comparison (2026-10-28: #210 duplicated #194). ' +
    'If yours is still needed, say why on the command: `# OVERLAP-OK: <why>`.';
}

module.exports = { judge, target, branchStart };

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
