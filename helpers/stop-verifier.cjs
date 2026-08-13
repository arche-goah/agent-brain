#!/usr/bin/env node
/**
 * Stop Hook: checks for genuine incomplete-work markers in CHANGED CODE before allowing stop.
 *
 * Scans only the ADDED lines of the git working-tree diff for code-style markers,
 * word-boundary matched. It deliberately:
 *   - ignores the assistant's chat message (the old version scanned that and
 *     false-triggered on any normal conversation that mentioned the words),
 *   - ignores docs (*.md, *.txt, ...) so intentional notes in CLAUDE.md / READMEs
 *     don't block stopping,
 *   - never blocks outside a git repo or if git fails.
 *
 * Marker words are assembled from fragments below so this file never contains
 * the literal tokens itself (otherwise the hook would flag its own source).
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

// For Stop hooks there is no "allow" decision — emitting no decision permits the stop.
function allow() { process.exit(0); }

setTimeout(() => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  // Prevent infinite loop — if already triggered once, allow stop.
  if (input.stop_hook_active) return allow();

  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();

  let diff = '';
  try {
    diff = execSync('git diff HEAD --unified=0', {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch (e) {
    return allow(); // not a git repo, or git failed — don't block
  }

  // Assembled from fragments so the tokens never appear literally in this file.
  const markers = ['TO' + 'DO', 'FIX' + 'ME', 'X' + 'XX', 'HA' + 'CK', 'W' + 'IP'];
  const markerRe = new RegExp('\\b(' + markers.join('|') + ')\\b');
  const docExt = /\.(md|markdown|mdx|txt|rst)$/i;

  let currentFile = '';
  let skipFile = false;
  const hits = [];

  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ ')) {
      currentFile = line.replace(/^\+\+\+ (b\/)?/, '').trim();
      skipFile = docExt.test(currentFile) || currentFile === '/dev/null';
      continue;
    }
    if (skipFile) continue;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      const content = line.slice(1);
      if (markerRe.test(content)) {
        hits.push(`${currentFile}: ${content.trim().slice(0, 80)}`);
      }
    }
  }

  // Also scan untracked (new) files — git diff HEAD doesn't include them,
  // and new code is the most likely place for unfinished markers.
  let untracked = '';
  try {
    untracked = execSync('git ls-files --others --exclude-standard', {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch (e) { /* ignore */ }

  for (const f of untracked.split('\n').filter(Boolean)) {
    if (docExt.test(f)) continue;
    let txt = '';
    try {
      const full = path.join(cwd, f);
      if (fs.statSync(full).size > 200 * 1024) continue; // skip large files
      txt = fs.readFileSync(full, 'utf8');
    } catch (e) { continue; }
    if (txt.indexOf(String.fromCharCode(0)) !== -1) continue; // skip binary
    for (const l of txt.split('\n')) {
      if (markerRe.test(l)) hits.push(`${f}: ${l.trim().slice(0, 80)}`);
    }
  }

  if (hits.length > 0) {
    console.log(JSON.stringify({
      decision: 'block',
      reason: 'INCOMPLETE: Unfinished markers in changed code:\n' +
              hits.slice(0, 10).join('\n') +
              '\nResolve or remove them before stopping.',
    }));
  } else {
    allow();
  }
  process.exit(0);
}, 400);

process.stdin.resume();
