#!/usr/bin/env node
/**
 * Stop hook: an own act that EXPECTS a reaction must not end the turn without a LIVE
 * watcher. Watching is the carrier; remembering to look is not.
 *
 * The class (measured 2026-10-09 on the Windows instance, transcript scan over every
 * retained session): 63 pushes into the shared-memory repo, 30 covered by a live watcher,
 * 33 not; at least 7 of the uncovered ones were answers that drew a follow-up request
 * (two of them a re-check that only surfaced when the operator asked "are your watches
 * running?"). 7 `gh pr create`, none with a watch armed before. The PR side of the same
 * class was filed as a prose rule on 2026-08-20 ("wait for X, then finish" = arm the
 * watchdog). The only carrier was prose — `skills/shared-memory-watch` "arm in the SAME
 * turn" — and prose has no failure signal: the omission leaves no artifact, nothing
 * breaks, the missing reply is invisible until somebody asks.
 *
 * Why a Stop hook and not a text gate: the other Stop gates match PHRASES in the reply.
 * This class has no phrase — it is an action (a push, a PR) plus a process that is NOT
 * running. So the gate reads the turn's tool calls and asks the watcher scripts' own
 * lock files whether something lives. A watcher that ended (killed, crashed, or a Monitor
 * that expired — the harness announced "expires in 30m" on 2026-10-09 even with
 * `persistent: true` set) leaves a dead pid and counts as not armed — the same definition
 * the scripts' own `status` uses.
 *
 * Fires when, in the running turn (since the operator's last prompt; harness
 * notifications are not a boundary, turn-kind.cjs):
 *   (a) a `git push` touched the shared-memory repo AND a fact file committed since the
 *       turn began is from this instance (`von` = SHARED_MEMORY_SELF, if set), names an
 *       `audience` other than this instance, and is not closed (`status:` answered|done|
 *       decided|info|closed — the inbox reader's closed set, so `status: info` is the
 *       declared "no answer expected"), and no shared-memory watcher lives
 *       (plain `shared-memory-watch.sh` or the one inside `collab-watch.sh`);
 *   (b) `gh pr create` ran AND no PR-side watcher lives (a `repo-activity-watch` lock of
 *       collab-watch, or a Monitor/background call in this turn on watch-pr.sh,
 *       ci-watch.sh or collab-watch.sh).
 * Blocks once per turn; a re-issue (stop_hook_active) or a second stop in the same turn
 * passes — the agent may have a reason not to watch, and says it.
 *
 * Fails open (no transcript, no bash, no repo): a gate that cannot measure must not
 * block — its fixture (`scripts/test-watch-gate.sh`) is the proof it still fires.
 *
 * HANDOVER (alpha 2026-10-09, coherence register finding P1-11): a CLOSING session cannot
 * keep a watcher — the Monitor dies with it — yet session-close itself pushes the answers
 * that expect a reaction. So the closing turn writes the expectation down instead:
 *   node watch-gate.cjs handover "<what is expected, from whom>"
 * An entry written in the running turn counts as covered (the gate lets the close end).
 * The NEXT session inherits it: at a stop with an entry from an earlier turn and no live
 * watcher, the gate blocks once per turn — "arm a watcher". A live watcher at a stop takes
 * the entries over and they are cleared (the watcher reports what arrives). `list` shows
 * them, `drop <id>|all` ends one no longer awaited. File: .claude-state/expected-reactions.json.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { isNotification } = require('./turn-kind.cjs');

const OWN_ECHO = /WATCH-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const CLOSED = new Set(['answered', 'done', 'decided', 'info', 'closed']);
const PR_WATCH = /\b(watch-pr|ci-watch|collab-watch)\.sh\b/;

function rootDir(input) { return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd(); }
function handoverFile(root) { return path.join(root, '.claude-state', 'expected-reactions.json'); }
function loadHandovers(root) {
  try { const a = JSON.parse(fs.readFileSync(handoverFile(root), 'utf8')); return Array.isArray(a) ? a : []; } catch (e) { return []; }
}
function saveHandovers(root, list) {
  try {
    fs.mkdirSync(path.dirname(handoverFile(root)), { recursive: true });
    fs.writeFileSync(handoverFile(root), JSON.stringify(list, null, 2) + '\n');
    return true;
  } catch (e) { return false; }
}

function cli(args) {
  const root = rootDir();
  const list = loadHandovers(root);
  const [cmd, ...rest] = args;
  if (cmd === 'handover') {
    const what = rest.join(' ').trim();
    if (!what) { process.stdout.write('usage: watch-gate.cjs handover "<what is expected, from whom>"\n'); return 2; }
    const id = require('crypto').createHash('sha1').update(what + Date.now()).digest('hex').slice(0, 8);
    list.push({ id, what, at: new Date().toISOString(), by: process.env.SHARED_MEMORY_SELF || '' });
    if (!saveHandovers(root, list)) { process.stdout.write(`!! handover NOT saved (${handoverFile(root)})\n`); return 1; }
    process.stdout.write(`handover ${id}: ${what}\n`);
    return 0;
  }
  if (cmd === 'list') {
    for (const h of list) process.stdout.write(`${h.id}  ${String(h.at).slice(0, 16)}  ${h.what}\n`);
    return 0;
  }
  if (cmd === 'drop') {
    const keep = rest[0] === 'all' ? [] : list.filter((h) => !rest.includes(h.id));
    if (!saveHandovers(root, keep)) return 1;
    process.stdout.write(`dropped ${list.length - keep.length}\n`);
    return 0;
  }
  process.stdout.write('usage: watch-gate.cjs handover "<what>" | list | drop <id>|all\n');
  return 2;
}

if (process.argv.length > 2) {
  process.exit(cli(process.argv.slice(2)));
} else {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    try { main(JSON.parse(data || '{}')); } catch (e) { process.exit(0); }
  });
}

function readTail(p) {
  const size = fs.statSync(p).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(p, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally { fs.closeSync(fd); }
}

function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b.type === 'tool_result')) return null;
  return msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n') || null;
}

/** Tool calls of the running turn, its start time, and whether this gate already fired in it. */
function turn(tp) {
  let calls = []; let since = ''; let fired = false;
  for (const line of readTail(tp)) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg) continue;
    if (msg.role === 'user') {
      const t = promptText(msg);
      if (t === null) continue;
      if (HOOK_ECHO.test(t)) { if (OWN_ECHO.test(t)) fired = true; continue; }
      if (isNotification(t)) continue;
      calls = []; since = d.timestamp || ''; fired = false;
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type !== 'tool_use') continue;
        const inp = b.input || {};
        calls.push({ name: b.name, cmd: String(inp.command || ''), bg: !!inp.run_in_background });
      }
    }
  }
  return { calls, since, fired };
}

/**
 * Same liveness test as the watcher scripts' `status` (`kill -0` on the pid in the lock),
 * without a shell. The pid must be digits only. On Windows the lock holds an MSYS pid that
 * node's process.kill cannot see, so Git's `ps -p` answers there (measured 2026-10-09:
 * exit 0 for a live watcher, 1 for a dead pid).
 */
function alive(lock) {
  try {
    const pid = fs.readFileSync(lock, 'utf8').trim();
    if (!/^\d+$/.test(pid)) return false;
    if (process.platform !== 'win32') { process.kill(Number(pid), 0); return true; }
    execFileSync('ps', ['-p', pid], { stdio: 'ignore', timeout: 5000 });
    return true;
  } catch (e) { return false; }
}

function stateDirs(root) {
  const base = path.join(root, '.claude-state');
  const collab = process.env.COLLAB_WATCH_STATE || path.join(base, 'collab-watch');
  return { sm: [process.env.SHARED_MEMORY_LOCK_DIR || base, collab], collab };
}

function smWatched(root) {
  return stateDirs(root).sm.some((d) => alive(path.join(d, 'shared-memory-watch.pid')));
}

function prWatched(root, calls) {
  if (calls.some((c) => (c.name === 'Monitor' || c.bg) && PR_WATCH.test(c.cmd))) return true;
  const dir = stateDirs(root).collab;
  try {
    return fs.readdirSync(dir).some((f) => /^repo-activity.*\.pid$/.test(f) && alive(path.join(dir, f)));
  } catch (e) { return false; }
}

function tokens(s) { return new Set(String(s || '').toLowerCase().split(/[\s,;]+/).filter(Boolean)); }

function field(head, k) {
  const m = new RegExp(`^\\s*${k}:\\s*(.+)$`, 'm').exec(head);
  return m ? m[1].replace(/^["']|["']$/g, '').trim() : '';
}

/** Fact files from this instance, committed since the turn began, that wait on someone else. */
function awaiting(repo, since) {
  const me = tokens(process.env.SHARED_MEMORY_SELF);
  const args = ['-C', repo, 'log', '--name-only', '--format='];
  if (since) args.push(`--since=${since}`); else args.push('-1');
  let names;
  try { names = execFileSync('git', args, { encoding: 'utf8', timeout: 10000 }); } catch (e) { return []; }
  const out = [];
  for (const rel of new Set(names.split('\n').map((s) => s.trim()).filter(Boolean))) {
    if (!/\.md$/.test(rel) || /(^|\/)(INDEX|LOG|README)\.md$/.test(rel) || /(^|\/)archive\//.test(rel)) continue;
    let text; try { text = fs.readFileSync(path.join(repo, rel), 'utf8'); } catch (e) { continue; }
    if (!text.startsWith('---')) continue;
    const head = text.split(/\n---/, 1)[0];
    const aud = tokens(field(head, 'audience'));
    if (!aud.size || CLOSED.has(field(head, 'status').toLowerCase())) continue;
    if (me.size) {
      const von = tokens(field(head, 'von'));
      if (![...von].some((t) => me.has(t))) continue;
      if ([...aud].every((t) => me.has(t))) continue;
    }
    out.push(rel);
  }
  return out;
}

function main(input) {
  if (input.stop_hook_active || !input.transcript_path) process.exit(0);
  const root = rootDir(input);
  const { calls, since, fired } = turn(input.transcript_path);
  if (fired) process.exit(0);
  const shell = calls.filter((c) => c.name === 'Bash' || c.name === 'PowerShell');
  const missing = [];

  // Handover: an entry written in THIS turn covers the act (a closing session); entries from
  // earlier turns wait for a watcher — a live one takes them over, none means block once.
  const handovers = loadHandovers(root);
  const isNew = (h) => !since || String(h.at) >= since;
  const covered = handovers.some(isNew);
  const inherited = handovers.filter((h) => !isNew(h));
  if (inherited.length) {
    if (smWatched(root) || prWatched(root, calls)) {
      saveHandovers(root, handovers.filter(isNew));
    } else {
      missing.push(`a reaction expected since an earlier session: ${inherited.slice(0, 3).map((h) => `${h.id} "${h.what}"`).join(', ')} — `
        + 'arm collab-watch (or shared-memory-watch); `node core/helpers/watch-gate.cjs drop <id>` if no longer awaited');
    }
  }

  const repo = process.env.SHARED_MEMORY_REPO || path.join(require('os').homedir(), 'Projects', 'brain-shared-memory');
  const repoName = path.basename(repo);
  const smPush = shell.some((c) => /\bgit\b[\s\S]*\bpush\b/.test(c.cmd) && c.cmd.includes(repoName));
  if (smPush && fs.existsSync(repo)) {
    const files = awaiting(repo, since);
    if (files.length && !smWatched(root) && !covered) {
      missing.push(`shared-memory: ${files.slice(0, 3).join(', ')} waits on another party — arm `
        + 'Monitor({command: "bash core/scripts/shared-memory-watch.sh watch 300", persistent: true}) '
        + '(or collab-watch); mark a pure report `status: info`');
    }
  }
  if (shell.some((c) => /\bgh\s+pr\s+create\b/.test(c.cmd)) && !prWatched(root, calls) && !covered) {
    missing.push('PR created — arm Monitor on core/scripts/watch-pr.sh <owner>/<repo> <nr> (or collab-watch)');
  }
  if (!missing.length) process.exit(0);
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: `WATCH-GATE: a reaction is expected and no watcher lives. ${missing.join(' · ')}. `
      + 'If nothing is awaited, say why in one line and stop again. A CLOSING session hands it over instead: '
      + '`node core/helpers/watch-gate.cjs handover "<what, from whom>"`.',
  }));
  process.exit(0);
}
