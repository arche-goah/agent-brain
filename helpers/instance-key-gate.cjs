#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash): a PR, comment or review an AI posts to GitHub carries its INSTANCE
 * KEY — one line `<!-- instance-key: <key> -->` — or it is not sent.
 *
 * WHY (measured 2026-10-11, and 2026-09-24 before it): one GitHub login can carry several
 * instances — an operator's two machines, a collaborator's three. Every check that decides
 * "is this mine?" by login (scripts/pr-ball.py, scripts/open-items.py) read the other
 * machine's PR and its "OK to merge" as its own and stayed silent; a test fix waited for a
 * second OK nobody was shown until the operator asked on every side. The git author name is
 * configuration, not proof. A key in the posted text is the one mark the readers can rely on
 * (scripts/instance_key.py, which defines the key and the decision rule).
 *
 * THE KEY: first 10 hex digits of sha256("instance-key:" + <instance id>), the id being the
 * first token of SHARED_MEMORY_SELF (process env, else the brain's .claude/settings*.json
 * env block). Opaque: public repos carry no machine id, and this names nobody — so it never
 * collides with helpers/public-text-guard.cjs, which only looks for names.
 *
 * WHAT COUNTS: `gh pr create|comment|review` and `gh issue create|comment`. The key may stand
 * in the command text or in a file it hands over (`--body-file`, `-F`). A review without a
 * body (`gh pr review --approve`) has no place for it — the gate asks for `--body`.
 * Not covered (named limit): `gh api` writes and the web UI; the operator's own hand-written
 * comments carry no key, and the readers count an unkeyed text under our login as ours.
 *
 * No instance id configured = allow, said on stderr: a brain that has not named itself has
 * no key to give (and its readers keep the old login-only rule). Exit 2 = block.
 * INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs for the measured reason).
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const WRITE_RX = /(^|[;&|(]\s*|\s)gh\s+(pr\s+(create|comment|review)|issue\s+(create|comment))\b/;

function unquote(s) {
  return s.replace(/^(['"])(.*)\1$/, '$2');
}

function selfId(root) {
  let raw = process.env.SHARED_MEMORY_SELF || '';
  if (!raw) {
    for (const name of ['settings.local.json', 'settings.json']) {
      try {
        const env = (JSON.parse(fs.readFileSync(path.join(root, '.claude', name), 'utf8')).env) || {};
        if (env.SHARED_MEMORY_SELF) { raw = String(env.SHARED_MEMORY_SELF); break; }
      } catch (e) { /* not there */ }
    }
  }
  return (raw.trim().toLowerCase().split(/[,\s]+/).filter(Boolean)[0]) || '';
}

function keyFor(id) {
  return id ? crypto.createHash('sha256').update('instance-key:' + id, 'utf8').digest('hex').slice(0, 10) : '';
}

function handedFiles(cmd) {
  const out = [];
  for (const rx of [/--body-file[=\s]+("[^"]+"|'[^']+'|\S+)/g, /\s-F\s+("[^"]+"|'[^']+'|[^\s=]+)(?=\s|$)/g]) {
    for (const m of cmd.matchAll(rx)) out.push(unquote(m[1]));
  }
  return out.filter((f) => f !== '-');
}

function gate(input) {
  if (!input || input.tool_name !== 'Bash') return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!WRITE_RX.test(cmd)) return 0;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const key = keyFor(selfId(root));
  if (!key) {
    console.error('instance-key-gate: SHARED_MEMORY_SELF unset - this instance has no key, nothing checked');
    return 0;
  }
  const mark = `<!-- instance-key: ${key} -->`;
  const cwd = input.cwd || process.cwd();
  let text = cmd;
  for (const f of handedFiles(cmd)) {
    try { text += '\n' + fs.readFileSync(path.resolve(cwd, f), 'utf8'); } catch (e) { /* the write fails on it too */ }
  }
  if (new RegExp(`<!--\\s*instance-key:\\s*${key}\\s*-->`, 'i').test(text)) return 0;
  const noBody = /\bgh\s+pr\s+review\b/.test(cmd) && !/--body(-file)?\b|\s-b\s|\s-F\s/.test(cmd);
  console.error(
    `BLOCKED (instance-key-gate): this GitHub text carries no instance key. Add this line to its body:\n  ${mark}\n` +
    (noBody ? 'A review without a body has no place for it - add --body "<one line> ' + mark + '".\n' : '') +
    'Why: several instances can post under one GitHub login; the readers that decide whose move a PR\n' +
    'is (pr-ball.py, open-items.py) tell them apart only by this key. It is a hash and names nobody.');
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

module.exports = { gate, keyFor, selfId, handedFiles };
