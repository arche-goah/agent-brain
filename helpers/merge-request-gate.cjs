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
 * asks (counter-check, please, run, check, test, verify). Not a request when
 * the body carries this instance's key — the PR is our own and the request goes to the others.
 * ANSWERED: a comment that carries this instance's key and names the same OS.
 * Override, said in the call: `# REQUEST-ANSWERED: <where it was answered>`.
 *
 *
 * SECOND CHECK — every required OS at the head (CONVENTIONS §11: "A merge checked on ONE system
 * only is allowed solely as a beta, labelled with that system"). Measured 2026-10-26: two
 * content-toolsuite PRs were merged with author and reviewer both on Windows; the rule stood in
 * CONVENTIONS and in the instance's merge table, nothing read it at the merge. For a repo that
 * carries `dependencies.json` (a suite, or the core), the thread needs, per required OS, a line
 * that names the OS and says OK / pass / green / rc 0, in a text that names the head's short
 * sha. Required OS: `required_os` in that file, default macOS + Windows. Otherwise the merge
 * names itself a beta: `# BETA-MERGE: <system checked>, <other> open` in the call.
 *
 * THIRD CHECK — CI green at the head (`# CI-RED-OK: <why>` overrides); FOURTH CHECK — no own
 * finding left open in the thread (`# FINDING-CLOSED: <where>` overrides). Both read merge-table
 * conditions that stood in prose only (2026-10-26); see ciNotGreen / findingOpen below.
 *
 * Unreadable PR (no repo or number in the command, gh fails) = allow, said on stderr — the
 * merge itself fails on the same cause. No instance key = allow, said on stderr.
 * MERGE_REQUEST_GATE_GH / MERGE_REQUEST_GATE_OS / MERGE_REQUEST_GATE_DEPS are fixture seams
 * only. Exit 2 = block.
 * INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs for the measured reason).
 */
const { execFileSync } = require('child_process');
const { invocations } = require('./published-text.cjs');
const { keyFor, selfId } = require('./instance-key-gate.cjs');

const OS_RX = { darwin: /\bmac\s?os\b|\bmac\b/i, win32: /\bwindows\b|\bwin\b/i, linux: /\blinux\b/i };
const ASK_RX = /counter-?check|\bplease\b|\b(run|check|test|verify)\b/i;
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
  const args = ['pr', 'view', t.nr, '-R', t.repo, '--json', 'body,comments,headRefOid,commits,statusCheckRollup'];
  const out = execFileSync(fake ? process.execPath : 'gh', fake ? [fake, ...args] : args,
    { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
  return JSON.parse(out);
}

// The OS verdict of a line is read by the ONE reader of OS reviews, shared with release-preflight check 8
// (two readers disagreed on the same threads, measured 2026-11-06 - see helpers/os-review.cjs).
const { saysOk, OK_RX } = require('./os-review.cjs');

/** The repo's `dependencies.json` as an object, null when it has none (not a suite). */
function readDeps(t) {
  const seam = process.env.MERGE_REQUEST_GATE_DEPS;
  if (seam !== undefined) return seam === 'none' ? null : JSON.parse(require('fs').readFileSync(seam, 'utf8'));
  if (process.env.MERGE_REQUEST_GATE_GH) return null; // fixture without the seam: not a suite
  try {
    const b64 = execFileSync('gh', ['api', `repos/${t.repo}/contents/dependencies.json`, '--jq', '.content'],
      { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
    return JSON.parse(Buffer.from(b64.replace(/\s/g, ''), 'base64').toString('utf8'));
  } catch (e) { return null; }
}

const BASE_MERGE_RX = /^Merge branch '[^']+' into /;

/**
 * Short shas that count as "the head": the head itself, plus every earlier head that only a
 * base-branch merge separates from it (GitHub's "update branch" writes `Merge branch 'main' into
 * <branch>` and changes no line of the PR's own diff). Measured 2026-10-28, agent-brain #157: the
 * ruleset "branches up to date" forces that update after every merge on main, which moved the
 * head away from both OS checks and blocked a PR whose content had not changed.
 */
function headShas(pr) {
  const out = [String(pr.headRefOid || '').slice(0, 7)];
  const commits = Array.isArray(pr.commits) ? pr.commits : [];
  for (let i = commits.length - 1; i > 0 && BASE_MERGE_RX.test(String(commits[i].messageHeadline || '')); i--) {
    out.push(String(commits[i - 1].oid || '').slice(0, 7));
  }
  return out.filter(Boolean);
}

/** Required systems without an OK line at the head: [] when covered or not a suite. */
function uncovered(pr, deps) {
  if (!deps) return [];
  const want = Array.isArray(deps.required_os) && deps.required_os.length ? deps.required_os : ['macOS', 'Windows'];
  const shas = headShas(pr);
  if (!shas.length) return [];
  const texts = [String(pr.body || ''), ...(pr.comments || []).map((c) => String(c.body || ''))]
    .filter((x) => shas.some((s) => x.includes(s)));
  return want.filter((os) => !texts.some((x) => x.split(/\r?\n/).some((l) => saysOk(l, os))));
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
  const blocked = requestOpen(pr, key, t) || ciNotGreen(pr, t, cmd) || findingOpen(pr, key, t, cmd);
  if (blocked) return blocked;
  if (/#\s*BETA-MERGE:\s*\S/.test(cmd)) {
    console.error('merge-request-gate: merged as a beta (BETA-MERGE) - say in the PR which system was checked and which is open');
    return 0;
  }
  let gone;
  try { gone = uncovered(pr, readDeps(t)); } catch (e) { console.error('merge-request-gate: dependencies.json unreadable, OS coverage not checked'); return 0; }
  if (!gone.length) return 0;
  console.error(
    `BLOCKED (merge-request-gate): ${t.repo}#${t.nr} is a suite or core PR, and no comment says OK at the head ` +
    `\`${String(pr.headRefOid).slice(0, 7)}\` on: ${gone.join(', ')}.\n` +
    'CONVENTIONS §11: a merge checked on one system only is a beta, labelled with that system. Either get the check on ' +
    'the missing system at this head (a PR comment naming the OS, "OK" and the short sha - an OK only in the shared ' +
    'memory is not read here, so the checker posts it on the PR too), or merge it as a beta: add ' +
    '`# BETA-MERGE: <system checked>, <other> open` to the call and say the same in the PR.\n' +
    'Why: 2026-10-26, two suite PRs were merged checked on Windows only; the rule stood in prose, nothing read it.');
  return 2;
}

/** The first check: a request in the body to THIS machine that no comment of this instance answered. */
function requestOpen(pr, key, t) {
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

/**
 * Third check — CI green at the head (merge table condition 3). Measured 2026-10-26: in a repo
 * without branch protection `gh pr merge` goes through on red CI; nothing read the condition.
 * Red = a check run that concluded failure/cancelled/timed out/action required, or a status
 * that failed; pending = a check run not completed, a status pending. No checks at all = the repo
 * has no CI, nothing to wait for. Override, said in the call: `# CI-RED-OK: <why>`.
 */
const RED = new Set(['FAILURE', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE', 'ERROR']);
function ciNotGreen(pr, t, cmd) {
  if (/#\s*CI-RED-OK:\s*\S/.test(cmd)) return 0;
  const checks = Array.isArray(pr.statusCheckRollup) ? pr.statusCheckRollup : [];
  const bad = checks.filter((c) => RED.has(String(c.conclusion || c.state || '').toUpperCase()) ||
    (c.status ? String(c.status).toUpperCase() !== 'COMPLETED' : ['PENDING', 'EXPECTED'].includes(String(c.state || '').toUpperCase())));
  if (!bad.length) return 0;
  console.error(
    `BLOCKED (merge-request-gate): ${t.repo}#${t.nr} - CI is not green at the head: ` +
    bad.slice(0, 5).map((c) => `${c.name || c.context || '?'}=${c.conclusion || c.state || c.status}`).join(', ') + '.\n' +
    'Wait for the run (scripts/ci-watch.sh pr <repo> <nr>) and merge on green. A red check that does not ' +
    'concern this PR: add `# CI-RED-OK: <why>` to the call and say it in the PR.\n' +
    'Why: 2026-10-26, the merge table names "CI green", and gh merges on red CI where no branch protection asks.');
  return 2;
}

/**
 * Fourth check — an own finding still open (merge table: "open own findings hold the merge").
 * A FINDING: an own comment (this instance's key) with a line that starts with "finding" or
 * "FAIL". Closed by a LATER own comment that says OK and is no finding itself.
 * Override, said in the call: `# FINDING-CLOSED: <where>`.
 */
const FINDING_RX = /^\s*(?:[-*>]\s*)*(?:\*\*)?(?:finding|FAIL)\b/im;
function findingOpen(pr, key, t, cmd) {
  if (/#\s*FINDING-CLOSED:\s*\S/.test(cmd)) return 0;
  const mine = new RegExp(`<!--\\s*instance-key:\\s*${key}\\s*-->`, 'i');
  let open = null;
  for (const c of pr.comments || []) {
    const b = String(c.body || '');
    if (!mine.test(b)) continue;
    if (FINDING_RX.test(b)) open = b;
    else if (OK_RX.test(b)) open = null;
  }
  if (!open) return 0;
  console.error(
    `BLOCKED (merge-request-gate): ${t.repo}#${t.nr} - an own finding is still open:\n` +
    '  > ' + (open.split(/\r?\n/).find((l) => FINDING_RX.test(l)) || '').trim().slice(0, 200) + '\n' +
    'Close it with a later comment of this instance that says OK at the head, or, settled elsewhere: ' +
    'add `# FINDING-CLOSED: <where>` to the call.\n' +
    'Why: 2026-10-26, the merge table says open own findings hold the merge; nothing read it.');
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

module.exports = { gate, target, saysOk, ciNotGreen, findingOpen };
