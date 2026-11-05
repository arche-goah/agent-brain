#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash/PowerShell): `gh pr close` runs without a dialog only on a PR THIS instance opened.
 *
 * WHY (operator decision 2026-11-04, question tool, translated: "allow it only for own PRs"): a merge train closes its
 * member PRs, and every close asked a dialog (`gh pr close` stood under ask in templates/settings.json) - while a
 * merge ran without one. Closing is reversible (reopen), but closing ANOTHER party's PR is an outward act. So the
 * template allows `gh pr close`, and this gate holds it unless the PR body carries this instance's key
 * (helpers/instance-key-gate.cjs writes it into every PR this instance opens; scripts/instance_key.py reads it).
 *
 * Other PRs: hold, unless the command carries `# PR-CLOSE-OK: <the operator's words + date, or the train PR that
 * merged it>`. Unsure = hold: the PR body cannot be read (no gh, no network), or this brain has no instance id.
 * The body is read with `gh pr view <n> [-R <repo>] --json body` ($PR_CLOSE_GATE_GH replaces `gh` in the fixture).
 * Exit 2 = block. Input is read to its end.
 */
const { execFileSync } = require('child_process');
const { keyFor, selfId } = require('./instance-key-gate.cjs');
const { invocations } = require('./published-text.cjs');

const RX = /(^|[;&|(]\s*|\s)gh\s+pr\s+close\b/;

function closes(cmd, ps) {
  const hit = invocations(cmd, ps, 'gh', ['pr'], ['close']);
  return hit === null ? RX.test(cmd) : hit.length > 0;
}

function target(cmd) {
  const seg = cmd.slice(cmd.search(/gh\s+pr\s+close\b/)).split(/[;&|\n]/)[0];
  const tok = seg.trim().split(/\s+/).slice(3);
  let repo = '';
  let num = '';
  for (let i = 0; i < tok.length; i++) {
    const t = tok[i];
    if (t === '-R' || t === '--repo') { repo = tok[++i] || ''; continue; }
    if (t.startsWith('--repo=')) { repo = t.slice(7); continue; }
    if (t === '#') break;
    if (!num && /^(#?\d+|https:\/\/\S+\/pull\/\d+)$/.test(t)) num = t.replace(/^#/, '');
  }
  return { repo, num };
}

function body(repo, num) {
  const stub = process.env.PR_CLOSE_GATE_GH;            // fixture: a .js stub, run by this node (no shell script: OS-3)
  const args = ['pr', 'view', num, '--json', 'body', '--jq', '.body'];
  if (repo) args.push('-R', repo);
  const [bin, argv] = stub ? [process.execPath, [stub, ...args]] : ['gh', args];
  return execFileSync(bin, argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 12000 });
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!closes(cmd, input.tool_name === 'PowerShell')) return 0;
  if (/#\s*PR-CLOSE-OK:\s*\S/.test(cmd)) return 0;
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const key = keyFor(selfId(root));
  const { repo, num } = target(cmd);
  let why = '';
  if (!key) why = 'this brain has no instance id (SHARED_MEMORY_SELF), so no PR can be shown to be its own';
  else if (!num) why = 'the command names no PR number';
  else {
    let text = null;
    try { text = body(repo, num); } catch (e) { why = `the body of PR ${num} could not be read (${e.code || 'gh failed'})`; }
    if (text !== null) {
      if (new RegExp(`<!--\\s*instance-key:\\s*${key}\\s*-->`, 'i').test(text)) return 0;
      why = `PR ${num}${repo ? ' in ' + repo : ''} does not carry this instance's key - another party's or another machine's PR`;
    }
  }
  console.error(`BLOCKED (pr-close-gate): ${why}.\n` +
    'gh pr close runs without a dialog only on a PR this instance opened (operator decision 2026-11-04).\n' +
    'Closing another party\'s PR is their call or the operator\'s: ask, then repeat with\n' +
    '  # PR-CLOSE-OK: "<the operator\'s words>" <date>   (or: member of merged train PR <n>)');
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

module.exports = { gate, target };
