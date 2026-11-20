#!/usr/bin/env node
/**
 * foreign-entry-gate.cjs — PreToolUse(Bash): a path commit of a shared append file does not carry
 * another session's entries along.
 *
 * WHY (measured 2026-11-05 on the macOS instance): every session appends to the same protocol and
 * register files. `git commit -- <file>` commits the WHOLE working file, so one session's commit
 * carried another session's uncommitted register entry along, and a close commit carried the main
 * session's session-log lines. Working rule #12 says a session commits only its own paths; here the
 * path was shared and the entry was not - shared-working-copy-guard works on whole files and cannot
 * see it. Test phase in that brain 2026-11-05..19: refusals in 26 sessions, about eight distinct real
 * foreign entries (another session's, the owner asked, written on a peer's request).
 *
 * WHAT: on a Bash `git ... commit` that names a watched file, every id the file ADDS against HEAD must
 * appear in THIS session's transcript (the session wrote or read it). An id the transcript never saw
 * is another session's entry: deny, naming it. Escape `# FOREIGN-ENTRY-OK: <why>` in the command.
 * Data: <project>/.claude/rules/foreign-entry.json (template: templates/rules-instance/foreign-entry.json)
 *   files          watched paths, repo-relative, forward slashes
 *   id_pattern     regex, first group = the id (default `^id:\s*(\S+)`)
 *   file_patterns  per-file regex for files whose entries carry another id (e.g. a session id)
 * No data file or an empty `files` list: inert. Fails open on unreadable input.
 * Known limit: an entry written in the SAME reply as the commit is not in the transcript yet - the
 * refusal says to commit it in the next call.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function cfg(project) {
  try {
    return JSON.parse(fs.readFileSync(path.join(project, '.claude', 'rules', 'foreign-entry.json'), 'utf8'));
  } catch (e) { return null; }
}

// A command typed in Git Bash carries MSYS paths (`git -C /c/work/repo`); node would resolve `/c/...` against
// the cwd's drive. Same translation as shared-working-copy-guard.cjs (fromShellPath).
function fromShellPath(p) {
  if (process.platform !== 'win32') return p;
  const m = /^\/([a-zA-Z])(\/.*)?$/.exec(p);
  return m ? `${m[1].toUpperCase()}:${m[2] || '/'}` : p;
}

// The repo the commit acts on: `git -C <path>` (quoted or not) when the command names one, else the cwd.
// Windows review of #620 (2026-11-20): with the cwd outside the repo, the diff threw and the commit passed silently.
function commitRepo(cmd, cwd) {
  const c = /\bgit\s+-C\s*("[^"]+"|'[^']+'|\S+)[^\n]*\bcommit\b/.exec(cmd);
  if (!c) return cwd;
  const raw = c[1].replace(/^(["'])(.*)\1$/, '$2');
  return path.resolve(cwd, fromShellPath(raw));
}

function addedIds(cwd, file, rx) {
  let diff = '';
  try {
    // `:/<file>`: the watched path is repo-relative, whichever folder of the repo `-C` names
    diff = execFileSync('git', ['-C', cwd, 'diff', 'HEAD', '--', ':/' + file], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch (e) { return []; }
  const out = [];
  for (const line of diff.split('\n')) {
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    const m = rx.exec(line.slice(1));
    if (m) out.push(m[1]);
  }
  return out;
}

function main(raw) {
  let input;
  try { input = JSON.parse(raw); } catch (e) { return ''; }
  if (input.tool_name !== 'Bash') return '';
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!/\bgit\b[^\n]*\bcommit\b/.test(cmd) || /#\s*FOREIGN-ENTRY-OK:\s*\S/.test(cmd)) return '';
  const cwd = commitRepo(cmd, input.cwd || process.env.CLAUDE_PROJECT_DIR || '.');
  const c = cfg(process.env.CLAUDE_PROJECT_DIR || cwd);
  if (!c || !Array.isArray(c.files) || !c.files.length) return '';
  let idRx;
  try { idRx = new RegExp(c.id_pattern || '^id:\\s*(\\S+)'); } catch (e) { return ''; }
  let transcript = '';
  try { transcript = fs.readFileSync(input.transcript_path, 'utf8'); } catch (e) { return ''; }
  const patterns = c.file_patterns || {};
  const foreign = [];
  for (const file of c.files) {
    if (!cmd.includes(file)) continue;
    let rx = idRx;
    if (patterns[file]) { try { rx = new RegExp(patterns[file]); } catch (e) { rx = idRx; } }
    for (const id of addedIds(cwd, file, rx)) {
      if (!transcript.includes(id)) foreign.push(`${file}: ${id}`);
    }
  }
  if (!foreign.length) return '';
  const reason = 'FOREIGN-ENTRY: this commit would carry entries this session never wrote or read: '
    + foreign.join(', ') + '. Another session appended them and has not committed yet - commit only your own '
    + 'entries (leave the file to the last committer, or ask that session), or add "# FOREIGN-ENTRY-OK: <why>". '
    + 'An entry written in the SAME reply as this commit is not in the transcript yet - commit it in the next call.';
  return JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } });
}

if (require.main === module) {
  let raw = '';
  process.stdin.on('data', (d) => { raw += d; });
  process.stdin.on('end', () => { const out = main(raw); if (out) process.stdout.write(out); });
}
module.exports = { main };
