#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash): blocks text that names someone from the brain's watch list
 * BEFORE it reaches a public repository — a PR title or body, a comment, a review, a
 * release note, a field sent through `gh api`, or a commit message.
 *
 * WHY: `scripts/staged-names.py` checks the ADDED LINES of a commit, and nothing checked the
 * text that goes out through `gh` or `git commit -m`. Measured 2026-10-10 on the proving
 * instance: 149 texts in a public core repo named people from the brain's own watch list
 * (77 comments, 65 PR titles/bodies, 7 reviews), plus names in 25 commit messages. One
 * comment was caught by the agent five seconds after posting and EDITED — and the edit
 * history kept the names visible, because an edit is not a removal. Hence a gate in front
 * of the write, not a scan after it.
 *
 * WHAT COUNTS: a write subcommand of `gh pr|issue|release`, `gh api` with a field, input
 * file or a writing method, and `git commit`/`git tag` with a message. Scanned: the whole
 * command text plus every file it hands over (`--body-file`, `--notes-file`, `-F <file>`,
 * `--file`, `--input`, `key=@file`, `$(cat <file>)`). Watch list: `<brain>/.claude/rules/
 * leak-names.json` (`names` + `instances`, whole words, case-insensitive) — the same list
 * staged-names.py reads; the core ships no names.
 *
 * PUBLIC ONLY: names are legitimate in private repos shared by the people they name. The
 * target repo comes from `-R/--repo`, the `repos/<owner>/<repo>` path of `gh api`, or the
 * origin of the repo the command runs in (`git -C <dir>`, else the session cwd). Visibility
 * is read from GitHub once a day per repo and cached in `<brain>/.claude-state/
 * repo-visibility.json`. A repo whose visibility cannot be read is treated as PUBLIC: the
 * gate errs toward silence in public, never toward a leak.
 *
 * INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs for the measured reason).
 * Exit 2 = block. No watch list = allow (nothing to check against), said on stderr.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const WRITE_RX = [
  /(^|[;&|(]\s*|\s)gh\s+(pr|issue)\s+(create|comment|edit|review|close|reopen|merge)\b/,
  /(^|[;&|(]\s*|\s)gh\s+release\s+(create|edit)\b/,
  /(^|[;&|(]\s*|\s)git\s+(-C\s+\S+\s+)?(commit|tag)\b[^;&|]*\s(-[a-zA-Z]*m|--message|-F|--file)\b/,
];
// Any commit or tag carries an AUTHOR identity (git config user.name / user.email), message or
// not. Measured 2026-10-10 in a public core repo: 46 commits carried a full real name and a
// private address as author — the message checks above never looked there.
const AUTHOR_RX = /(^|[;&|(]\s*|\s)git\s+(-C\s+("[^"]+"|'[^']+'|\S+)\s+)?(commit|tag)\b/;
const GH_API_RX = /(^|[;&|(]\s*|\s)gh\s+api\b([^;&|]*)/g;
const TTL_MS = 24 * 3600 * 1000;

function brainRoot(input) {
  return process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
}

function watchList(root) {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'leak-names.json'), 'utf8'));
    return ['names', 'instances'].flatMap((k) => d[k] || []).map((n) => String(n).trim().toLowerCase()).filter(Boolean);
  } catch (e) {
    return null;
  }
}

function isWrite(cmd) {
  if (WRITE_RX.some((rx) => rx.test(cmd)) || AUTHOR_RX.test(cmd)) return true;
  for (const m of cmd.matchAll(GH_API_RX)) {
    const args = m[2];
    if (/\s(-f|-F|--field|--raw-field|--input)\b/.test(args)) return true;
    if (/\s(-X|--method)\s*(POST|PATCH|PUT)\b/i.test(args)) return true;
  }
  return false;
}

function unquote(s) {
  return s.replace(/^(['"])(.*)\1$/, '$2');
}

// Files the command hands over as text. A path that cannot be read is skipped: the write
// itself would fail on it too.
function referencedFiles(cmd) {
  const out = [];
  const rxs = [
    /--(?:body-file|notes-file|file|input)[=\s]+("[^"]+"|'[^']+'|\S+)/g,
    /\s-F\s+("[^"]+"|'[^']+'|[^\s=]+)(?=\s|$)/g, // git commit -F <file>
    /=@("[^"]+"|'[^']+'|\S+)/g, // gh api -F key=@file
    /\$\(\s*cat\s+("[^"]+"|'[^']+'|[^)\s]+)\s*\)/g,
  ];
  for (const rx of rxs) for (const m of cmd.matchAll(rx)) out.push(unquote(m[1]));
  return out.filter((f) => f !== '-');
}

function slugFromRemote(dir) {
  try {
    const url = execFileSync('git', ['-C', dir, 'remote', 'get-url', 'origin'],
      { stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000 }).toString().trim();
    const m = /github\.com[:/]([^/]+\/[^/.\s]+?)(?:\.git)?$/.exec(url);
    return m ? m[1] : null;
  } catch (e) {
    return null;
  }
}

function targetRepos(cmd, cwd) {
  const slugs = new Set();
  for (const m of cmd.matchAll(/(?:-R|--repo)[=\s]+("?)([\w.-]+\/[\w.-]+)\1/g)) slugs.add(m[2]);
  for (const m of cmd.matchAll(/\brepos\/([\w.-]+\/[\w.-]+?)(?=\/|\s|$|["'?])/g)) slugs.add(m[1]);
  if (!slugs.size) {
    const c = /git\s+-C\s+("[^"]+"|'[^']+'|\S+)/.exec(cmd);
    const dir = c ? unquote(c[1]) : cwd;
    const s = dir && slugFromRemote(path.resolve(cwd || '.', dir));
    if (s) slugs.add(s);
    else if (/(^|\s)gh\s/.test(cmd)) slugs.add('?'); // gh without a resolvable repo: unknown
  }
  return [...slugs];
}

function visibility(slug, root) {
  if (slug === '?') return 'unknown';
  const cacheFile = path.join(root, '.claude-state', 'repo-visibility.json');
  let cache = {};
  try { cache = JSON.parse(fs.readFileSync(cacheFile, 'utf8')); } catch (e) { /* first run */ }
  const hit = cache[slug];
  if (hit && Date.now() - hit.at < TTL_MS) return hit.v;
  let v = 'unknown';
  // Fixture seam: a fake gh as a node script. A shell-script `gh` is not executable for
  // node on Windows (no .exe), so the real gh would answer instead (measured in CI).
  const fake = process.env.PUBLIC_TEXT_GUARD_FAKE_GH;
  const [bin, pre] = fake ? [process.execPath, [fake]] : ['gh', []];
  try {
    v = execFileSync(bin, [...pre, 'api', `repos/${slug}`, '--jq', '.visibility'],
      { stdio: ['ignore', 'pipe', 'ignore'], timeout: 6000 }).toString().trim().toLowerCase() || 'unknown';
  } catch (e) { /* offline, no access, no gh: stays unknown */ }
  if (v !== 'unknown') {
    cache[slug] = { v, at: Date.now() };
    try {
      fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
      fs.writeFileSync(cacheFile, JSON.stringify(cache, null, 1) + '\n');
    } catch (e) { /* cache is an optimisation, not a verdict */ }
  }
  return v;
}

function gate(input) {
  if (!input || input.tool_name !== 'Bash') return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!isWrite(cmd)) return 0;
  const root = brainRoot(input);
  const names = watchList(root);
  if (!names || !names.length) {
    console.error('public-text-guard: no watch list in .claude/rules/leak-names.json - nothing checked');
    return 0;
  }
  const rx = new RegExp('\\b(' + names.map((n) => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')\\b', 'gi');
  const cwd = input.cwd || process.cwd();
  const found = new Map(); // word -> where
  const scan = (text, where) => {
    for (const m of String(text).matchAll(rx)) if (!found.has(m[1].toLowerCase())) found.set(m[1].toLowerCase(), where);
  };
  // A home path in the command (`git -C /Users/<name>/…`, a --body-file path) is where the
  // command runs, not text that gets published. Measured 2026-10-10: the guard blocked its own
  // follow-up commit because the worktree path carried the operator's login name.
  scan(cmd.replace(/(\/Users\/|\/home\/|[A-Za-z]:[\\/]+Users[\\/]+)[^\/\\\s"']+/g, '$1<home>'), 'the command');
  for (const f of referencedFiles(cmd)) {
    try { scan(fs.readFileSync(path.resolve(cwd, f), 'utf8'), f); } catch (e) { /* unreadable: the write fails too */ }
  }
  const a = AUTHOR_RX.exec(cmd);
  if (a) {
    const dir = path.resolve(cwd, a[3] ? unquote(a[3]) : '.');
    try {
      const ident = execFileSync('git', ['-C', dir, 'var', 'GIT_AUTHOR_IDENT'],
        { stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000 }).toString().replace(/\s+\d+\s+[+-]\d{4}\s*$/, '');
      scan(ident, 'the commit author - set git config --local user.name/user.email to the account and its noreply address');
    } catch (e) { /* no identity: git refuses the commit itself */ }
  }
  if (!found.size) return 0;
  const repos = targetRepos(cmd, cwd);
  const open = repos.filter((s) => visibility(s, root) !== 'private' && visibility(s, root) !== 'internal');
  if (repos.length && !open.length) return 0;
  const words = [...found].map(([w, where]) => `"${w}" (${where})`).join(', ');
  console.error(
    `BLOCKED (public-text-guard): text for ${open.join(', ') || 'a repo whose visibility is unknown'} names someone from the watch list: ${words}.\n` +
    'Public text names no person and no machine id. Say what the party IS: "the operator", "a collaborator",\n' +
    '"the macOS instance", "the Windows instance". Already posted? Delete and re-post - an EDIT keeps the old\n' +
    'text in the edit history. Watch list: .claude/rules/leak-names.json');
  return 2;
}

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let rc = 0;
    try { rc = gate(JSON.parse(data)); } catch (e) { rc = 0; /* unparsable input: nothing to check */ }
    process.exit(rc);
  });
  process.stdin.resume();
}

module.exports = { gate, isWrite, referencedFiles, targetRepos };
