#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash): `gh pr merge` waits while the PR's body asks THIS machine for a check
 * that no comment of this instance has answered.
 *
 * WHY (measured 2026-10-24, retroactive review run on the macOS instance): three PR bodies asked
 * "please counter-check on macOS" (agent-brain #67, #68, #23); all three were merged under this
 * login with no answer in the thread. The request was in plain sight; nothing made the merging
 * AI read it. Operator decision the same day: read the request before the merge.
 *
 * A REQUEST: one line of the body that names this machine's OS (macOS / Windows / Linux) and
 * asks (counter-check, please, run, check, test, verify, "bitte", "pruef"). Not a request when
 * the body carries this instance's key — the PR is our own and the request goes to the others.
 * ANSWERED: a comment that carries this instance's key and names the same OS.
 * Override, said in the call: `# REQUEST-ANSWERED: <where it was answered>`.
 *
 * Unreadable PR (no repo or number in the command, gh fails) = allow, said on stderr — the
 * merge itself fails on the same cause. No instance key = allow, said on stderr.
 * MERGE_REQUEST_GATE_GH / MERGE_REQUEST_GATE_OS are fixture seams only. Exit 2 = block.
 * INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs for the measured reason).
 */
const { execFileSync } = require('child_process');
const { invocations } = require('./published-text.cjs');
const { keyFor, selfId } = require('./instance-key-gate.cjs');

const OS_RX = { darwin: /\bmac\s?os\b|\bmac\b/i, win32: /\bwindows\b|\bwin\b/i, linux: /\blinux\b/i };
const ASK_RX = /counter-?check|\bplease\b|\bbitte\b|pr(?:ue|ü)f|\b(run|check|test|verify)\b/i;
const MERGE_RX = /(^|[;&|(]\s*|\s)gh\s+pr\s+merge\b/;

function merges(cmd, ps) {
  const hit = invocations(cmd, ps, 'gh', ['pr'], ['merge']);
  return hit === null ? MERGE_RX.test(cmd) : hit.length > 0;
}

function target(cmd) {
  const url = /github\.com\/([\w.-]+\/[\w.-]+)\/pull\/(\d+)/.exec(cmd);
  if (url) return { repo: url[1], nr: url[2] };
  const repo = /(?:-R|--repo)[=\s]+["']?([\w.-]+\/[\w.-]+)/.exec(cmd);
  const nr = /\bgh\s+pr\s+merge\s+(?:(?:-R|--repo)[=\s]+\S+\s+)?["']?(\d+)\b/.exec(cmd);
  return repo && nr ? { repo: repo[1], nr: nr[1] } : null;
}

function readPr(t) {
  const fake = process.env.MERGE_REQUEST_GATE_GH;
  const args = ['pr', 'view', t.nr, '-R', t.repo, '--json', 'body,comments'];
  const out = execFileSync(fake ? process.execPath : 'gh', fake ? [fake, ...args] : args,
    { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
  return JSON.parse(out);
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (!merges(cmd, input.tool_name === 'PowerShell')) return 0;
  if (/#\s*REQUEST-ANSWERED:\s*\S/.test(cmd)) return 0;
  const key = keyFor(selfId(process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd()));
  if (!key) { console.error('merge-request-gate: no instance key, nothing checked'); return 0; }
  const t = target(cmd);
  if (!t) { console.error('merge-request-gate: no repo and number in the command, nothing checked'); return 0; }
  let pr;
  try { pr = readPr(t); } catch (e) { console.error('merge-request-gate: PR unreadable, nothing checked'); return 0; }
  const mine = new RegExp(`<!--\\s*instance-key:\\s*${key}\\s*-->`, 'i');
  const body = String(pr.body || '');
  if (mine.test(body)) return 0;
  const os = OS_RX[process.env.MERGE_REQUEST_GATE_OS || process.platform];
  if (!os) return 0;
  const asks = body.split(/\r?\n/).filter((l) => os.test(l) && ASK_RX.test(l));
  if (!asks.length) return 0;
  const answered = (pr.comments || []).some((c) => mine.test(String(c.body || '')) && os.test(String(c.body || '')));
  if (answered) return 0;
  console.error(
    `BLOCKED (merge-request-gate): ${t.repo}#${t.nr} asks this machine for a check, and no comment of this instance answers it:\n` +
    asks.slice(0, 3).map((l) => '  > ' + l.trim().slice(0, 200)).join('\n') + '\n' +
    'Run the check at the head, post the result as a comment (with the instance key, naming the OS), then merge.\n' +
    'Answered elsewhere: add `# REQUEST-ANSWERED: <where>` to the merge call.\n' +
    'Why: 2026-10-24, three such requests were merged unanswered (retroactive review run).');
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
