#!/usr/bin/env node
/**
 * PreToolUse Hook: Blocks edits to sensitive files, and edits to a brain-core
 * checkout that sits on the consumed state (detached HEAD pin or main) instead
 * of a feature branch.
 * Exit code 2 = block the tool call.

 * INPUT IS READ TO ITS END, never on a timer. Until 2026-08-20 this ran in a
 * setTimeout(..., 400): if the timer fires before the first data event the buffer is
 * empty, JSON.parse throws, and the hook silently allows. Measured on a sibling hook
 * with 0 ms — same input, same file, once blocking and once completely silent. 400 ms
 * mitigates that, it does not promise it, and a gate that fails open at random is
 * indistinguishable from one that agrees.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

/**
 * Walk up from the edited file to the first git repo root. If that repo is a
 * brain-core checkout (identified by its own plugin manifest, not by directory
 * name — the checkout may be an instance's core/ submodule, a standalone
 * clone, or a worktree), return the root, else null.
 */
function brainCoreRoot(fp) {
  if (!fp) return null;
  let dir = path.dirname(path.resolve(fp));
  for (let i = 0; i < 40; i++) {
    if (fs.existsSync(path.join(dir, '.git'))) { // submodule .git is a file — existsSync covers both
      try {
        const pj = JSON.parse(fs.readFileSync(path.join(dir, '.claude-plugin', 'plugin.json'), 'utf8'));
        if (pj && pj.name === 'brain-core') return dir;
      } catch (e) { /* no manifest or unreadable -> not brain-core */ }
      return null;
    }
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
  return null;
}

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

process.stdin.on('end', () => {
  try {
    const input = JSON.parse(data);
    const fp = (input.tool_input && input.tool_input.file_path) || '';
    const base = require('path').basename(fp).toLowerCase();
    const dir = fp.replace(/\\/g, '/').toLowerCase();

    const blocked = [
      '.env', '.env.local', '.env.production', '.env.development',
      'cookies.txt', 'credentials.json', '.npmrc',
      'id_rsa', 'id_ed25519', '.pem', '.key', '.secret'
    ];

    let isBlocked = false;
    for (const pattern of blocked) {
      if (base === pattern || base.endsWith(pattern) ||
          dir.includes('/secrets/') || dir.includes('/.ssh/')) {
        isBlocked = true;
        break;
      }
    }

    if (isBlocked) {
      console.error('BLOCKED: Editing ' + base + ' is forbidden. Ask the project owner to edit manually.');
      process.exit(2);
    }

    // Branch gate for brain-core checkouts (decision 2026-08-10, full-audit E1).
    // "Never edit core directly" means the CONSUMED state — the detached-HEAD pin
    // an instance runs on, or main. Core work itself is legal right here, on a
    // feature branch riding into a PR (CONVENTIONS 13.3). This is the mechanical
    // half the 2026-08-03 decision log demanded ("file-guard to be synced along —
    // not standalone") and never got.
    const root = brainCoreRoot(fp);
    if (root) {
      let branch = null;
      try {
        branch = execSync('git branch --show-current', {
          cwd: root, stdio: ['ignore', 'pipe', 'ignore'], timeout: 5000
        }).toString().trim();
      } catch (e) { /* no git verdict -> no block; the prose rule still applies */ }
      if (branch !== null && (branch === '' || branch === 'main' || branch === 'master')) {
        const state = branch === '' ? 'a detached HEAD (the consumed pin)' : "branch '" + branch + "'";
        console.error('BLOCKED: ' + fp + ' lies in a brain-core checkout sitting on ' + state + '.\n' +
          'Core changes ride a feature branch into a PR (CONVENTIONS 13.3), never the consumed state:\n' +
          '  git -C "' + root + '" checkout -b <type>/<topic> origin/main');
        process.exit(2);
      }
    }
  } catch (e) { /* allow on parse error */ }
  process.exit(0);
});

process.stdin.resume();
