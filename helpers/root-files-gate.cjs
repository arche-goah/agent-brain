#!/usr/bin/env node
/**
 * Stop check: no stray file in the repo root.
 *
 * WHY (operator decision 2026-11-18, question dialog, translated: "a check at the turn end"): the
 * File Rules (`rules/working-rules.md`) name the files that may live in a brain's root and say
 * "never place other files in root". That line was prose. Measured that day: a browser tool wrote
 * two captures into a brain's root because it resolved a relative file name against the project
 * directory, and nothing held the turn; no running check read the root at all.
 *
 * The check does not care WHICH tool wrote the file — it reads the state: an untracked, not
 * ignored file directly in the root whose name is not on the list. Tracked files are the repo's
 * history and a scan's matter, ignored files are declared, folders are not this rule.
 *
 * The list: the core's root files below, plus what the instance declares in
 * `.claude/rules/root-files.json` (`{"allowed": ["name", …]}`) — an instance may extend the
 * whitelist, never silently.
 *
 * Exit 0 always; a block is `{decision: "block"}` on stdout. Fails open where it cannot measure
 * (no project directory, not a git repo, git missing).
 *
 * Frequency design: no cooldown on purpose. The trigger is a state, not a turn: it holds only
 * while a stray file exists, names each one, and moving or deleting it ends it for good. It holds
 * a turn at most once (`stop_hook_active` lets the re-issue through).
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { declare } = require('./stop-echo.cjs');

const CORE = ['README.md', 'CLAUDE.md', 'LICENSE', '.gitignore', '.gitattributes', '.gitmodules', '.mcp.json',
  '.env', '.env.example'];

function allowed(root) {
  let own = [];
  try {
    own = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'root-files.json'), 'utf8')).allowed || [];
  } catch (e) { /* no instance list */ }
  return new Set([...CORE, ...own]);
}

/** Untracked, not ignored files directly in `root` that are not on the list. */
function stray(root) {
  const out = execFileSync('git', ['-C', root, 'status', '--porcelain', '-z', '--untracked-files=normal'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const ok = allowed(root);
  return out.split('\0')
    .filter((e) => e.startsWith('?? '))
    .map((e) => e.slice(3))
    .filter((p) => !p.includes('/') && !ok.has(p)); // an untracked folder ends in "/"
}

module.exports = { stray, CORE };

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input = {};
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    const root = process.env.CLAUDE_PROJECT_DIR || input.cwd;
    if (input.stop_hook_active || !root) process.exit(0);
    let files = [];
    try { files = stray(root); } catch (e) { process.exit(0); }
    if (!files.length) process.exit(0);
    console.log(JSON.stringify(declare({
      decision: 'block',
      reason: `ROOT-FILES — stray in the repo root: ${files.join(', ')}. Only the listed root files live ` +
        'there (working-rules.md, File Rules). Move each to its folder or delete it; a file that belongs in ' +
        'the root is declared in .claude/rules/root-files.json ("allowed"), with the operator\'s word.',
    }, input)));
    process.exit(0);
  });
}
