#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash/PowerShell): while a release scope is open, new work on the release's repo starts only
 * inside the scope.
 *
 * WHY (operator 2026-11-06, translated: "the trains do not solve it ... you do not wait with pins and releases until
 * everything is together"; the operator agreed to this gate in the question tool the same day). Measured on the
 * macOS instance for beta 2.1.4: the train was closed and the Windows hand check requested while the same instance
 * still started and carried new core branches; each new branch moved the release again. A release scope
 * (scripts/release-scope.py, state `<brain>/.claude-state/release-scope.json`) names what the release holds;
 * while it is open, a command that starts NEW work on that repo -
 *   git worktree add ... -b|-B <branch>   git checkout -b|-B <branch>   git switch -c|-C|--create <branch>
 *   gh pr create [--head <branch>]        (no --head: the current branch of the working directory)
 * - for a branch the scope does not list is held. Ways out: `release-scope.py add <branch>` (it belongs to this
 * release) or `# SCOPE-OK: "<the operator's words>" <YYYY-MM-DD>` in the command (the operator's quoted word).
 *
 * The target repo is the origin URL's last path part of the directory the command works in (`git -C <dir>`, else the
 * hook's cwd) or the `--repo` of gh; it must equal the scope's `repo`. A scope whose tag `v<version>` already stands
 * in that directory counts as closed (the release shipped; closing it by hand was a forgotten step). No scope is the
 * NORMAL state: until a pin is due the train collects everything (operator 2026-11-12). Fails open: no scope, a
 * closed scope, a scope without the operator's word (`operator_word`, written by `open --operator-word`), an
 * unreadable state file, a command it cannot read to the end, or a target repo it cannot name.
 * Exit 2 = block. Input is read to its end.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { invocations } = require('./published-text.cjs');

const QUOTE_RE = /"[^"\n]{3,}"|„[^“”"\n]{3,}[“”"]|“[^”\n]{3,}”/;   // as mechanism-guard reads the operator's word
const DATE_RE = /\b20\d{2}-\d{2}-\d{2}\b/;

function git(dir, args) {
  try {
    return execFileSync('git', ['-C', dir, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000 }).trim();
  } catch (e) { return ''; }
}

// OS-19: a Git Bash path (`/c/x`) as the shell sees it is `C:/x` for node on Windows.
function nativeDir(p) {
  const m = process.platform === 'win32' && /^\/([a-zA-Z])(\/|$)(.*)$/.exec(p);
  return m ? `${m[1].toUpperCase()}:/${m[3]}` : p;
}

function repoName(s) {
  return String(s || '').replace(/\/+$/, '').split(/[/:]/).pop().replace(/\.git$/, '');
}

function value(w, i, flags) {   // `--flag v` or `--flag=v`
  const t = w[i];
  for (const f of flags) {
    if (t === f) return w[i + 1] || '';
    if (f.startsWith('--') && t.startsWith(f + '=')) return t.slice(f.length + 1);
  }
  return null;
}

// Every new branch the command starts: [{ branch, dir, repo }] (dir: where it works; repo: gh --repo, if named).
function starts(cmd, ps, cwd) {
  const out = [];
  const gits = invocations(cmd, ps, 'git');
  const ghs = invocations(cmd, ps, 'gh', ['pr'], ['create']);
  if (gits === null || ghs === null) return null;
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
      if (b) { out.push({ branch: b, dir, repo: '' }); break; }
    }
  }
  for (const w of ghs) {
    let head = '';
    let repo = '';
    for (let j = 3; j < w.length; j++) {
      head = value(w, j, ['--head', '-H']) || head;
      repo = value(w, j, ['--repo', '-R']) || repo;
    }
    head = head.replace(/^[^:]+:/, '') || git(cwd, ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (head) out.push({ branch: head, dir: cwd, repo: repo ? repoName(repo) : '' });
  }
  return out;
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!/\b(git|gh)\b/.test(cmd)) return 0;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const file = path.join(root, '.claude-state', 'release-scope.json');
  let scope = null;
  try { scope = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return 0; }
  if (!scope || scope.status !== 'open') return 0;
  // No scope before a pin is due (operator 2026-11-12): a scope opens only with the operator's word naming the release
  // (release-scope.py open --operator-word). One without it was opened while the train was still collecting - it holds
  // nothing (measured 2026-11-12 on the macOS instance: scope 2.1.6, opened right after a train merge, closed the train).
  if (!String(scope.operator_word || '').trim()) return 0;
  const want = String(scope.repo || 'agent-brain');
  const listed = new Set([...(scope.items || []), ...Object.keys(scope.excluded || {})].map(String));
  const found = starts(cmd, input.tool_name === 'PowerShell', input.cwd || process.cwd());
  if (!found) return 0;
  // A scope whose version tag already stands is a release that has shipped: read it as closed (measured 2026-11-08 on
  // the macOS instance: scope 2.1.4 stayed `open` after tag v2.1.4 and held every new core branch for a day).
  const tagged = (dir) => !!scope.version && !!git(dir, ['rev-parse', '-q', '--verify', `refs/tags/v${scope.version}`]);
  const held = found.filter((s) => {
    const repo = s.repo || repoName(git(s.dir, ['config', '--get', 'remote.origin.url']));
    return repo === want && !listed.has(s.branch) && !tagged(s.dir);
  });
  if (!held.length) return 0;
  const marker = /#\s*SCOPE-OK:([^\n]*)/.exec(cmd);
  if (marker && QUOTE_RE.test(marker[1]) && DATE_RE.test(marker[1])) return 0;
  const names = held.map((s) => s.branch).join(', ');
  console.error(`BLOCKED (release-freeze-gate): release scope ${scope.version} of ${want} is open ` +
    `(.claude-state/release-scope.json), and ${names} is not in it.\n` +
    'While a release is being collected, new work on its repo starts only inside its scope (operator 2026-11-06).\n' +
    (marker ? 'The SCOPE-OK marker carries no quotation of the operator with its date - a paraphrase is not the word.\n' : '') +
    'Two ways out:\n' +
    `  python3 core/scripts/release-scope.py add ${held[0].branch}      (it belongs to this release)\n` +
    '  # SCOPE-OK: "<the operator\'s words>" <YYYY-MM-DD>              (the operator said to start it now)');
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

module.exports = { gate, starts };
