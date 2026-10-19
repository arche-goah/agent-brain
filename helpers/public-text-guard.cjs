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
 * file or a writing method, and `git commit`/`git tag` with a message. Scanned: exactly the
 * text that reaches GitHub (publishedText below) — the values of `--title/-t`, `--body/-b`,
 * `--notes/-n`, `--subject`, `-f/-F/--field/--raw-field key=value`, the `gh api` endpoint,
 * `git commit|tag -m/--message`, plus every file handed over (`--body-file`, `--notes-file`,
 * `-F <file>`, `--file`, `--input`, `key=@file`, `$(cat <file>)`). Paths, flags, the working
 * directory, shell comments and the environment are never published and never scanned.
 * Until 2026-10-19 the guard scanned the WHOLE command and masked known path forms: every new
 * form was a new false alarm, and a path-shaped word inside a body was masked, i.e. not
 * checked. A command the parser cannot read to the end (a heredoc, an unbalanced quote) is
 * scanned whole, as before: unsure means stricter. Named limit: text that arrives through a
 * shell variable (`--body "$BODY"`) is invisible here. Watch list: `<brain>/.claude/rules/
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
 * INERT-WITHOUT: .claude/rules/leak-names.json names|instances
 *   (read by scripts/hook-coverage.py: no file or an empty watch list = reported)
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

// A path as the shell sees it: `~` and `$HOME` expand, then it resolves against the cwd.
// Measured 2026-10-18 (Windows instance): `git -C ~/Projects/<private clone> commit …` — the
// guard resolved the literal `~`, found no remote, called the repo "unknown" and blocked a
// private commit; the same gap let a `--body-file ~/<file>` go unread, i.e. unscanned.
function resolveFrom(cwd, p) {
  const home = require('os').homedir();
  const s = String(p).replace(/^~(?=$|[\\/])/, home).replace(/^\$HOME(?=$|[\\/])/, home);
  return path.resolve(cwd || '.', s);
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

// The shell's view of a command: words with quotes removed, `;` `&` `|` `(` `)` and newlines
// end a segment, a `#` that opens a word outside quotes is a comment to the end of the line.
// `$(...)` stays one raw piece of its word. Returns null when it cannot be read to the end (a
// heredoc, an unbalanced quote or parenthesis): the caller then scans the whole command.
// PowerShell (`ps`) has no backslash escape: there a `\` is a path separator, as it is inside
// bash double quotes unless it precedes `$`, a backquote, `"`, `\` or a newline.
function shellSegments(cmd, ps) {
  const segs = [[]];
  let word = null; // null = between words
  let q = '';
  const push = () => { if (word !== null) segs[segs.length - 1].push(word); word = null; };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q === "'") { if (c === "'") q = ''; else word += c; continue; }
    if (c === '\\' && !ps && (!q || /[$`"\\\n]/.test(cmd[i + 1] || ''))) {
      word = (word || '') + (cmd[i + 1] || '');
      i++;
      continue;
    }
    if (c === '$' && cmd[i + 1] === '(') {
      let depth = 0;
      let j = i;
      for (; j < cmd.length; j++) {
        if (cmd[j] === '(') depth++;
        else if (cmd[j] === ')' && --depth === 0) break;
      }
      if (j >= cmd.length || /<</.test(cmd.slice(i, j))) return null;
      word = (word || '') + cmd.slice(i, j + 1);
      i = j;
      continue;
    }
    if (q === '"') { if (c === '"') q = ''; else word += c; continue; }
    if (c === "'" || c === '"') { q = c; word = word || ''; continue; }
    if (c === '<' && cmd[i + 1] === '<') return null; // heredoc / here-string
    if (c === '#' && word === null) {
      while (i < cmd.length && cmd[i] !== '\n') i++;
      segs.push([]);
      continue;
    }
    if (c === '\n' || /[;&|()]/.test(c)) { push(); segs.push([]); continue; }
    if (/\s/.test(c)) { push(); continue; }
    word = (word || '') + c;
  }
  if (q) return null;
  push();
  return segs.filter((s) => s.length);
}

// What a write command publishes: { texts, files }, or null = read the command whole.
const GH_TEXT = new Set(['--title', '-t', '--body', '-b', '--notes', '-n', '--subject', '--message', '-m']);
const GH_FIELD = new Set(['-f', '--raw-field', '--field']);
const GH_FILE = new Set(['--body-file', '--notes-file', '--input', '--file']);
function publishedText(cmd, ps) {
  const segs = shellSegments(cmd, ps);
  if (!segs) return null;
  const texts = [];
  const files = [];
  // `$(cat <file>)` hands a file over; any other `$(...)` is unknown and stays text to check
  const value = (v) => texts.push(v.replace(/\$\(\s*cat\s+("[^"]+"|'[^']+'|[^)\s]+)\s*\)/g,
    (m, f) => { files.push(unquote(f)); return ' '; }));
  const field = (kv) => {
    const at = kv.indexOf('=');
    const v = at < 0 ? kv : kv.slice(at + 1);
    if (v.startsWith('@')) { if (v !== '@-') files.push(v.slice(1)); } else value(v);
  };
  for (const w of segs) {
    const gh = w.indexOf('gh');
    const git = w.indexOf('git');
    if (gh >= 0 && (git < 0 || gh < git)) {
      const api = w[gh + 1] === 'api';
      for (let i = gh + 1; i < w.length; i++) {
        const a = w[i];
        const eq = a.startsWith('--') ? a.indexOf('=') : -1;
        const flag = eq > 0 ? a.slice(0, eq) : a;
        const inline = eq > 0 ? a.slice(eq + 1) : null;
        const next = () => (inline !== null ? inline : w[++i]);
        let v;
        if (api && i === gh + 2 && !a.startsWith('-')) texts.push(a); // the endpoint names public paths
        else if (GH_TEXT.has(flag)) { if ((v = next()) !== undefined) value(v); }
        else if (GH_FIELD.has(flag)) { if ((v = next()) !== undefined) field(v); }
        else if (flag === '-F') {
          if ((v = next()) === undefined) continue;
          if (api || v.includes('=')) field(v); else if (v !== '-') files.push(v); // gh pr -F = --body-file
        } else if (GH_FILE.has(flag)) { if ((v = next()) !== undefined && v !== '-') files.push(v); }
      }
    } else if (git >= 0) {
      for (let i = git + 1; i < w.length; i++) {
        const a = w[i];
        let v;
        if (a === '-C' || a === '-c') { i++; continue; }
        if (a === '--message' || /^-[a-zA-Z]*m$/.test(a)) { if ((v = w[++i]) !== undefined) value(v); }
        else if (a.startsWith('--message=')) value(a.slice(10));
        else if (/^-m./.test(a)) value(a.slice(2));
        else if (a === '-F' || a === '--file') { if ((v = w[++i]) !== undefined && v !== '-') files.push(v); }
        else if (a.startsWith('--file=')) files.push(a.slice(7));
      }
    }
  }
  return { texts, files };
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
    const s = dir && slugFromRemote(resolveFrom(cwd, dir));
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
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
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
  const pub = publishedText(cmd, input.tool_name === 'PowerShell');
  const readFiles = (list) => {
    for (const f of list) {
      try { scan(fs.readFileSync(resolveFrom(cwd, f), 'utf8'), f); } catch (e) { /* unreadable: the write fails too */ }
    }
  };
  if (pub) {
    pub.texts.forEach((t) => scan(t, 'the published text'));
    readFiles(pub.files);
  } else {
    // Not readable to the end (heredoc, unbalanced quote): scan it whole. Only the home part of
    // a path is masked - where the command runs is not what it publishes.
    scan(cmd.replace(/(\/Users\/|\/home\/|[A-Za-z]:[\\/]+Users[\\/]+)[^\/\\\s"']+/g, '$1<home>'), 'the command, read whole');
    readFiles(referencedFiles(cmd));
  }
  const a = AUTHOR_RX.exec(cmd);
  if (a) {
    const dir = resolveFrom(cwd, a[3] ? unquote(a[3]) : '.');
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

module.exports = { gate, isWrite, referencedFiles, targetRepos, publishedText, shellSegments };
