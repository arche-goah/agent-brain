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
 *       declared "no answer expected") — or a `LOG.md` heading added since the turn began
 *       is such a message (`## <date> · <von> — AN <who> (status: …): …`, awaitingLog) —
 *       and no shared-memory watcher lives
 *       (plain `shared-memory-watch.sh` or the one inside `collab-watch.sh`);
 *   (b) `gh pr create` ran AND no PR-side watcher lives (a `repo-activity-watch` lock of
 *       collab-watch, or a Monitor/background call in this turn on watch-pr.sh,
 *       ci-watch.sh or collab-watch.sh);
 *   (c) the reply asks the human for a reload and no waiter runs (RELOAD_ASK below);
 *   (d) a `git push` went into a checkout that has Actions workflows (`.github/workflows/`),
 *       or `gh pr create` / `gh pr merge` named a repo, AND no `ci-watch.sh pr|ref <that
 *       owner/repo>` was started in this turn (Monitor or run_in_background). Working rule
 *       #9 said "a PR is opened together with its CI watch"; this carrier knew only (b), and
 *       a live collab-watch lock satisfied it although collab-watch never looked at CI.
 *       Measured 2026-10-13 on the macOS instance: five pushes to PR branches in one
 *       session, four with a ci-watch, the fifth without — its macOS job never got a runner,
 *       the run sat red for fifteen minutes and the operator found it. A merge is a push to
 *       the base branch and starts a run there too; six merges that session, none watched.
 *       A collab-watch lock does NOT satisfy (d): the standing watch reports a red run at
 *       its next poll, the rule wants the VERDICT of this push read in this turn.
 *   (e) the reply asks the HUMAN for a hand step — start a program, plug a cable, switch a
 *       device on, click, accept an invitation — and no waiter was armed in this turn (a
 *       Monitor, or a Bash/Agent call with run_in_background). Operator 2026-10-11: "it is a
 *       failure class that watchdogs are not started" — a session asked "onPC must be running"
 *       and the operator had to report the start himself; (a)-(d) are blind to it, because a
 *       request in prose makes no tool call. Core rule "A Needed Reload Is Not a Wait State"
 *       #3: build the measurement, arm the watcher, THEN give the instruction. Where no probe
 *       is possible (a network the AI may not touch), the reply says so in a visible line
 *       `⚙ no watcher: <why no probe is possible>` and passes. English built-ins below; an
 *       instance extends them with its language in `.claude/rules/watch-gate.json`
 *       (`hand_step_patterns`, `no_watcher_markers`). Quoted text and code are stripped
 *       before matching (talk ABOUT a request quotes it).
 *   (f) `gh issue create`, or `gh issue comment` / `gh pr comment` whose body asks something
 *       (a question mark or "please"), ran AND no PR-side watcher lives (same test as (b)):
 *       a ticket or a question in a thread expects an answer in that thread, and only the
 *       standing repo watch reads comments. Measured 2026-10-11: a ticket was opened and was
 *       covered only by chance, by a collab-watch that happened to be running.
 *   (g) the brain's `.claude/rules/collab-watch.json` is filled in AND no standing watch lives
 *       (no live collab-watch lock, no collab-watch armed in this turn) — independent of any
 *       own act; see standingConfig() below. A close stamp passes it (the session ends).
 *   (h) the reply declares the work finished ("nothing open", "all done", "the session can be
 *       closed"; other languages via `done_claim_patterns` in `.claude/rules/watch-gate.json`)
 *       while a CI watch started anywhere in this SESSION has no GREEN/RED verdict read yet —
 *       see pendingCi() below. Not covered by a close stamp: the close names its open ends
 *       instead of declaring nothing open.
 * Blocks once per turn; a re-issue (stop_hook_active) or a second stop in the same turn
 * passes — the agent may have a reason not to watch, and says it.
 *
 * The close turn (coherence scan 2026-10-15, P1-2): skill `session-close` arms no watcher it
 * will not be alive to read — it lists each such item as an open end in the session-log entry.
 * A close stamp of this session and turn (close-stamp.cjs) passes (a), (b), (d) and (f) for
 * exactly the items that entry lists (`open end: <repo> #<n> …`, the fact file's name for (a));
 * an unlisted item still blocks. (c) and (e) are requests to the human and are never covered.
 *
 * Fails open (no transcript, no bash, no repo): a gate that cannot measure must not
 * block — its fixture (`scripts/test-watch-gate.sh`) is the proof it still fires.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { isNotification } = require('./turn-kind.cjs');
const { closeOpenEnds, listed } = require('./close-stamp.cjs');

const OWN_ECHO = /WATCH-GATE/;
const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const CLOSED = new Set(['answered', 'done', 'decided', 'info', 'closed']);
const PR_WATCH = /\b(watch-pr|ci-watch|collab-watch)\.sh\b/;
// A reload the HUMAN has to do (operator order 2026-08-06, sharpened 2026-10-11): the reply names the slash command or says
// reconnect. The waiter is core/scripts/wait-mcp-reconnect.sh, armed in the same turn BEFORE the request.
const RELOAD_ASK = /(?:^|[\s`'"(])\/(?:mcp|reload-plugins)\b|\breconnect\b|\bre-?connecten\b|\bwieder verbinden\b/i;
const RELOAD_WATCH = /\bwait-mcp-reconnect\.sh\b/;
// (d) the CI watch of a push: `ci-watch.sh pr|ref <owner/repo> …`, and the repo a gh call names.
// The script path may be quoted (`bash "C:/…/ci-watch.sh" pr …`): the closing quote sits between `.sh`
// and the blank. Without `["']?` there, a live watch read as none — measured 2026-10-16 on the Windows
// instance, four WATCH-GATE blocks in one day with every watcher alive.
const CI_WATCH = /\bci-watch\.sh["']?\s+(?:pr|ref)\s+["']?([\w.-]+\/[\w.-]+)/i;
const REPO_FLAG = /(?:--repo|-R)[=\s]+["']?([\w.-]+\/[\w.-]+)/;
// (e) a hand step asked of the human. The FORM: an imperative or a necessity aimed at a person
// or a device the AI cannot operate. English built-ins; other languages are instance data.
const HAND_STEP_BUILTIN = [
  '\\b(please|kindly)\\s+(start|launch|open|restart|reboot|plug\\s+in|unplug|re-?plug|switch\\s+on|turn\\s+on|power\\s+on|power\\s+up|connect|press|click|tap|load|install|enable|accept|approve|unlock)\\b',
  '\\b(can|could|would)\\s+you\\s+(please\\s+)?(start|launch|open|restart|reboot|plug|unplug|re-?plug|switch|turn|power|connect|press|click|tap|load|install|enable|accept|approve|unlock)\\b',
  '\\b(onpc|desk|console|app|application|program|machine|workstation|laptop|router|switch|device|plugin|show|window|cable|usb)\\s+(must|needs?\\s+to|has\\s+to|should)\\s+(be\\s+)?(running|open|on|started|loaded|connected|plugged\\s+in|visible|powered)\\b',
  '\\b(start|launch|open|restart|reboot|plug\\s+in|switch\\s+on|turn\\s+on|power\\s+on|connect)\\s+(the\\s+|your\\s+)?(onpc|desk|console|app|application|program|machine|workstation|laptop|router|switch|device|cable|usb|plugin|show)\\b',
  '\\bI\\s+need\\s+you\\s+to\\b',
];
const NO_WATCHER_BUILTIN = ['⚙\\s*no\\s+watcher\\s*:'];
// (f) a ticket, or a comment that asks something.
const ISSUE_CREATE = /\bgh\s+issue\s+create\b/;
const COMMENT = /\bgh\s+(?:issue|pr)\s+comment\b/;
// (h) a reply that declares the work finished. English built-ins; other languages are instance
// data (`done_claim_patterns`). Quoted text is stripped first, as for (e).
const DONE_CLAIM_BUILTIN = [
  '\\bnothing\\s+(?:is\\s+)?(?:left\\s+|still\\s+)?open\\b',
  '\\b(?:all|everything)\\s+(?:is\\s+)?(?:done|finished|through)\\b',
  '\\b(?:the\\s+)?session\\s+can\\s+(?:be\\s+)?(?:closed|ended)\\b',
  '\\bwe\\s+are\\s+done\\b',
];
// A CI watch as started, with its target: `ci-watch.sh pr <owner/repo> <nr>` or `ref <owner/repo> <ref>`.
const CI_WATCH_TARGET = /\bci-watch\.sh["']?\s+(pr|ref)\s+["']?([\w.-]+\/[\w.-]+)["']?\s+["']?([\w./#-]+)/i;
// Its verdict lines (scripts/ci-watch.sh): GREEN and RED are verdicts; UNKNOWN is not. NO-CI (the
// repo has no Actions workflow, exit 3) is a terminal answer for every target in that repo.
const CI_VERDICT = /CI-WATCH (?:GREEN|RED): ([\w.-]+\/[\w.-]+) (PR #\d+|[\w./-]+)/g;
const CI_NO_CI = /CI-WATCH NO-CI: ([\w.-]+\/[\w.-]+)/g;

function loadPatterns(root) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'watch-gate.json'), 'utf8')); } catch (e) { /* built-ins only */ }
  const merge = (builtins, extra) => {
    const out = [...builtins];
    if (Array.isArray(extra)) for (const p of extra) { try { new RegExp(p); out.push(p); } catch (e) { /* skip */ } }
    return new RegExp(out.join('|'), 'iu');
  };
  return { handStep: merge(HAND_STEP_BUILTIN, cfg.hand_step_patterns), noWatcher: merge(NO_WATCHER_BUILTIN, cfg.no_watcher_markers),
    doneClaim: merge(DONE_CLAIM_BUILTIN, cfg.done_claim_patterns) };
}

/**
 * (h) CI watches started in this SESSION whose verdict was never read. A watch counts as started
 * when a Monitor or background call runs `ci-watch.sh pr|ref <owner/repo> <target>`; it counts as
 * read when a later message the agent received (a tool result, a harness notification) carries
 * its `CI-WATCH GREEN|RED` line. `UNKNOWN` (timeout, conflict) is no verdict. A newer watch on the
 * same target replaces the older one. Session-wide on purpose: the claim "nothing open" is made
 * turns after the merge whose CI it forgets (measured 2026-10-18 on the macOS mini instance — a
 * watch on main armed after a merge, then "nothing open, our work is through" twice while that
 * run was still in progress; the operator asked back before closing the session).
 */
function pendingCi(tp) {
  const started = new Map(); // key -> index of the latest start
  const read = new Map();    // key -> index of the latest verdict
  const noCi = new Map();    // repo -> index of the latest NO-CI answer
  let i = 0;
  const seen = (text) => {
    for (const m of String(text || '').matchAll(CI_VERDICT)) read.set(`${m[1].toLowerCase()} ${m[2]}`, i);
    for (const m of String(text || '').matchAll(CI_NO_CI)) noCi.set(m[1].toLowerCase(), i);
  };
  for (const line of readTail(tp)) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg) continue;
    i += 1;
    if (msg.role === 'user') {
      if (typeof msg.content === 'string') { seen(msg.content); continue; }
      for (const b of Array.isArray(msg.content) ? msg.content : []) {
        if (b.type === 'text') seen(b.text);
        if (b.type === 'tool_result') seen(typeof b.content === 'string' ? b.content
          : (Array.isArray(b.content) ? b.content.map((x) => x.text || '').join('\n') : ''));
      }
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    for (const b of msg.content) {
      if (b.type !== 'tool_use') continue;
      const inp = b.input || {};
      if (!(b.name === 'Monitor' || inp.run_in_background)) continue;
      const m = CI_WATCH_TARGET.exec(String(inp.command || ''));
      if (!m) continue;
      const target = m[1].toLowerCase() === 'pr' ? `PR #${m[3].replace(/^#/, '')}` : m[3];
      started.set(`${m[2].toLowerCase()} ${target}`, i);
    }
  }
  return [...started].filter(([k, at]) => !(read.get(k) > at) && !(noCi.get(k.split(' ')[0]) > at)).map(([k]) => k);
}

/** Quoted text and code are talk ABOUT a request, not a request. */
function stripQuoted(text) {
  return String(text || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

/** The body text a gh comment/issue command carries, as far as the command line shows it. */
function ghBody(cmd) {
  const m = /--body[=\s]+(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(cmd) || /-b[=\s]+(?:"([^"]*)"|'([^']*)'|(\S+))/.exec(cmd);
  return m ? (m[1] || m[2] || m[3] || '') : cmd; // $(...) bodies: judge the whole command text
}

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });
process.stdin.on('end', () => {
  try { main(JSON.parse(data || '{}')); } catch (e) { process.exit(0); }
});

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
  let calls = []; let since = ''; let fired = false; let lastText = '';
  for (const line of readTail(tp)) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message; if (!msg) continue;
    if (msg.role === 'user') {
      // A tool's output: keep it on its call (the PR / issue URL a gh call printed).
      if (Array.isArray(msg.content)) {
        for (const b of msg.content) {
          if (b.type !== 'tool_result') continue;
          const c = calls.find((x) => x.id && x.id === b.tool_use_id);
          if (c) c.out = typeof b.content === 'string' ? b.content
            : (Array.isArray(b.content) ? b.content.map((x) => x.text || '').join('\n') : '');
        }
      }
      const t = promptText(msg);
      if (t === null) continue;
      if (HOOK_ECHO.test(t)) { if (OWN_ECHO.test(t)) fired = true; continue; }
      if (isNotification(t)) continue;
      calls = []; since = d.timestamp || ''; fired = false; lastText = '';
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      const text = msg.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
      if (text.trim()) lastText = text;
      for (const b of msg.content) {
        if (b.type !== 'tool_use') continue;
        const inp = b.input || {};
        calls.push({ id: b.id, name: b.name, cmd: String(inp.command || ''), bg: !!inp.run_in_background, out: '' });
      }
    }
  }
  return { calls, since, fired, lastText };
}

/**
 * Same liveness test as the watcher scripts' `status` (`kill -0` on the pid in the lock),
 * without a shell. The pid must be digits only. On Windows the lock holds an MSYS pid that
 * node's process.kill cannot see, so Git's `ps -p` answers there (measured 2026-10-09:
 * exit 0 for a live watcher, 1 for a dead pid).
 *
 * That measurement ran from Git Bash, where `ps` is on PATH. The hook itself does not run
 * there (measured 2026-10-11, Windows instance): the PATH Claude Code hands to its children
 * holds `Git\cmd`, not `Git\usr\bin`, so `ps` was ENOENT, every lock read as dead, and the
 * gate blocked every push of a waiting fact file with the watcher alive. So Git's own
 * `ps.exe` is found next to the `git.exe` on PATH (`<Git>\cmd\git.exe` -> `<Git>\usr\bin`).
 * Returns true / false, or null when no `ps` can be run at all — unknown, not dead.
 */
function psCandidates() {
  const out = ['ps'];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (dir && fs.existsSync(path.join(dir, 'git.exe'))) out.push(path.resolve(dir, '..', 'usr', 'bin', 'ps.exe'));
  }
  if (process.env.ProgramFiles) out.push(path.join(process.env.ProgramFiles, 'Git', 'usr', 'bin', 'ps.exe'));
  return [...new Set(out)];
}

function alive(lock) {
  let pid;
  try { pid = fs.readFileSync(lock, 'utf8').trim(); } catch (e) { return false; }
  if (!/^\d+$/.test(pid)) return false;
  if (process.platform !== 'win32') {
    try { process.kill(Number(pid), 0); return true; } catch (e) { return false; }
  }
  for (const ps of psCandidates()) {
    try {
      execFileSync(ps, ['-p', pid], { stdio: 'ignore', timeout: 5000 });
      return true;
    } catch (e) {
      if (e.code === 'ENOENT') continue;
      return false;
    }
  }
  return null;
}

/** Any lock alive -> true; none alive but one unknown -> null (cannot measure); else false. */
function anyAlive(locks) {
  const r = locks.map(alive);
  return r.includes(true) ? true : (r.includes(null) ? null : false);
}

// A collab-watch armed with its own COLLAB_WATCH_STATE sets that variable on the Monitor
// command, never in this hook's environment — so the gate looked only at the default
// directory and blocked with the watch alive (measured 2026-10-15 on the Windows instance).
// collab-watch.sh registers every non-default state dir in `collab-watch-states` (one path
// per line); a stale line costs nothing, its locks read as dead.
function stateDirs(root) {
  const base = path.join(root, '.claude-state');
  const collab = [process.env.COLLAB_WATCH_STATE || path.join(base, 'collab-watch')];
  try {
    for (const l of fs.readFileSync(path.join(base, 'collab-watch-states'), 'utf8').split(/\r?\n/)) {
      if (l.trim() && !collab.includes(l.trim())) collab.push(l.trim());
    }
  } catch (e) { /* no registry: only the default dir */ }
  return { sm: [process.env.SHARED_MEMORY_LOCK_DIR || base, ...collab], collab };
}

// A liveness that cannot be measured counts as watched: the gate fails open (header).
function smWatched(root) {
  return anyAlive(stateDirs(root).sm.map((d) => path.join(d, 'shared-memory-watch.pid'))) !== false;
}

/**
 * (g) The standing watch. A brain whose `.claude/rules/collab-watch.json` is filled in CAN watch; this
 * asks whether it DOES. Cases (a)-(f) demand a watcher only after an own act that expects a reaction,
 * so a session that never pushes never watched — measured 2026-10-16 on the second macOS machine:
 * incoming PRs and requests were seen only at the next session start, and nothing answered them.
 * A Monitor expires after 30 minutes; its locks then read as dead and the next turn end blocks again,
 * so re-arming is mechanical, not memory. A brain without the file, or with template placeholders
 * left in it, is not judged here — `core/scripts/watch-readiness.py` names that state at session start.
 * Declared off: `"standing_watch": "off: <why>"` (an off without a reason blocks).
 */
function standingConfig(root) {
  let raw;
  try { raw = fs.readFileSync(path.join(root, '.claude', 'rules', 'collab-watch.json'), 'utf8'); } catch (e) { return null; }
  if (/<[a-z][\w-]*>/i.test(raw.replace(/"_comment"\s*:\s*\[[\s\S]*?\]\s*,?/, ''))) return null;
  try { const v = JSON.parse(raw).standing_watch; return { setting: typeof v === 'string' ? v.trim() : '' }; } catch (e) { return null; }
}

function standingWatched(root, calls) {
  if (calls.some((c) => (c.name === 'Monitor' || c.bg) && /\bcollab-watch\.sh\b/.test(c.cmd))) return true;
  const locks = [];
  for (const dir of stateDirs(root).collab) {
    try {
      fs.readdirSync(dir).filter((f) => /^(?:repo-activity.*|shared-memory-watch)\.pid$/.test(f))
        .forEach((f) => locks.push(path.join(dir, f)));
    } catch (e) { /* dir absent */ }
  }
  return locks.length > 0 && anyAlive(locks) !== false;
}

function prWatched(root, calls) {
  if (calls.some((c) => (c.name === 'Monitor' || c.bg) && PR_WATCH.test(c.cmd))) return true;
  const locks = [];
  for (const dir of stateDirs(root).collab) {
    try { fs.readdirSync(dir).filter((f) => /^repo-activity.*\.pid$/.test(f)).forEach((f) => locks.push(path.join(dir, f))); } catch (e) { /* dir absent */ }
  }
  return locks.length > 0 && anyAlive(locks) !== false;
}

function expandHome(p) { return p.replace(/^~(?=$|[\\/])/, require('os').homedir()); }
/** The checkout a shell call acts on: `git -C <dir>`, else a leading `cd <dir>`, else the project root. */
function callDir(cmd, root) {
  let m = /\bgit\s+-C\s+(?:"([^"]+)"|'([^']+)'|(\S+))/.exec(cmd);
  if (!m) m = /(?:^|[\n;&|(])\s*cd\s+(?:"([^"]+)"|'([^']+)'|(\S+))/.exec(cmd);
  return m ? expandHome(m[1] || m[2] || m[3]) : root;
}
function hasWorkflows(dir) {
  try { return fs.readdirSync(path.join(dir, '.github', 'workflows')).some((f) => /\.ya?ml$/i.test(f)); } catch (e) { return false; }
}
/** owner/repo of `origin` when it is a GitHub remote, '' otherwise (then nothing is required). */
function originSlug(dir) {
  let url;
  try { url = execFileSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch (e) { return ''; }
  const m = /github\.com[:/]([\w.-]+\/[\w.-]+?)(?:\.git)?\/?$/i.exec(url);
  return m ? m[1].toLowerCase() : '';
}
/** Does the NAMED repo run Actions? A repo without workflows starts no run, so there is nothing
 *  to watch (measured 2026-10-16 on both the macOS and the Windows instance: `gh pr create` /
 *  `gh pr merge -R <private repo without CI>` blocked the turn end, with every watcher alive).
 *  A local checkout of that repo answers first; else one `gh api` call (a 404 = no workflows
 *  folder). Anything unmeasurable counts as "has CI" — the gate errs toward the watch.
 *  WATCH_GATE_GH is only a fixture seam (a fake gh as a node script, run through node: Windows
 *  node cannot exec a shebang file — measured on the Windows instance, ENOENT with empty stderr);
 *  nothing in production sets it. */
function namedRepoHasWorkflows(slug, dirs) {
  for (const d of dirs) if (originSlug(d) === slug) return hasWorkflows(d);
  const fake = process.env.WATCH_GATE_GH;
  const args = ['api', `repos/${slug}/contents/.github/workflows`, '--jq', 'length'];
  try {
    const n = execFileSync(fake ? process.execPath : 'gh', fake ? [fake, ...args] : args,
      { encoding: 'utf8', timeout: 8000, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    return n !== '0';
  } catch (e) {
    return !/\b404\b|Not Found/i.test(String((e.stderr || '') + (e.stdout || '')));
  }
}
/** Repos whose CI this turn's shell calls set running: a push into a checkout with workflows,
 *  a PR opened or merged with the repo named (a merge is a push to the base branch) when that
 *  repo has workflows. */
function ciStarted(shell, root) {
  const out = new Set();
  for (const c of shell) {
    const named = /\bgh\s+pr\s+(?:create|merge)\b/.test(c.cmd);
    if (!named && !/\bgit\b[\s\S]*\bpush\b/.test(c.cmd)) continue;
    const flag = named && REPO_FLAG.exec(c.cmd);
    if (flag) {
      const slug = flag[1].toLowerCase();
      if (namedRepoHasWorkflows(slug, [callDir(c.cmd, root), root])) out.add(slug);
      continue;
    }
    const dir = callDir(c.cmd, root);
    if (!hasWorkflows(dir)) continue;
    const slug = originSlug(dir);
    if (slug) out.add(slug);
  }
  return out;
}
function ciWatched(calls, slug) {
  return calls.some((c) => {
    if (!(c.name === 'Monitor' || c.bg)) return false;
    const m = CI_WATCH.exec(c.cmd);
    return !!m && m[1].toLowerCase() === slug;
  });
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
  return out.concat(awaitingLog(repo, since, me));
}

// A LOG heading, the shapes of shared-memory-parties.py HEADING: `## <date> · <von> — <title>`,
// with an optional `(<session>)` after date or sender. The title of a message starts `AN <who>`;
// its status, when the writer gives one, stands in parentheses before the colon.
const LOG_HEADING = /^##\s+(\d{4}-\d{2}-\d{2})(?:\s*\([^)]*\))?\s*(?:[·—-]\s*)?([\w-]+)(?:\s*\([^)]*\))?(?:\s+[—-]\s+(.*?))?\s*$/;
const LOG_TO = /^(?:AN|An|an|TO|To)\s+([^:(]+)/;
const LOG_STATUS = /\(\s*status:\s*([\w-]+)/i;

/**
 * Messages this instance ADDED to a `LOG.md` since the turn began that wait on someone else.
 * Measured 2026-10-16 on a macOS brain: the cross-instance exchange of a whole topic folder
 * (`ops/`, 96 entries) runs as LOG headings `AN <who> (status: …): …`, while this gate read
 * only fact files and skipped every LOG.md — a request and its answer, both LOG entries, were
 * invisible to it. The inbox reader (shared-memory-inbox.py) already reads these headings;
 * the gate now reads the same shape. Closed = the same set as for fact files; no `AN` = a
 * note, not a message.
 */
function awaitingLog(repo, since, me) {
  const args = ['-C', repo, 'log', '-p', '-U0', '--format=', '--no-renames'];
  if (since) args.push(`--since=${since}`); else args.push('-1');
  args.push('--', 'LOG.md', '*/LOG.md');
  let diff;
  try { diff = execFileSync('git', args, { encoding: 'utf8', timeout: 10000 }); } catch (e) { return []; }
  const out = [];
  let file = '';
  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ b/')) { file = line.slice(6); continue; }
    if (!line.startsWith('+') || line.startsWith('+++')) continue;
    const m = LOG_HEADING.exec(line.slice(1));
    if (!m) continue;
    const [, , von, title = ''] = m;
    const to = LOG_TO.exec(title);
    if (!to) continue;
    const st = LOG_STATUS.exec(title);
    if (st && CLOSED.has(st[1].toLowerCase())) continue;
    const aud = tokens(to[1].replace(/\s\+\s/g, ' '));
    if (me.size) {
      if (!me.has(von.toLowerCase())) continue;
      if ([...aud].every((t) => me.has(t))) continue;
    }
    out.push(`${file} (${title.slice(0, 60)})`);
  }
  return out;
}

/** The repo NAME part of owner/repo — what an open-end line has to name. */
function nameOf(slug) { return String(slug || '').split('/').pop(); }
/** The number a gh call acted on: from the URL it printed, else from its arguments. */
function ghNumber(c) {
  const m = /\/(?:pull|issues)\/(\d+)/.exec(c.out || '') || /\bgh\s+(?:issue|pr)\s+(?:comment|merge)\s+(\d+)/.exec(c.cmd);
  return m ? Number(m[1]) : null;
}
/** The repo a gh call acted on: the --repo flag, the URL it printed, else the checkout it ran in. */
function ghRepo(c, root) {
  const f = REPO_FLAG.exec(c.cmd);
  if (f) return f[1].toLowerCase();
  const u = /github\.com\/([\w.-]+\/[\w.-]+)\/(?:pull|issues)\//.exec(c.out || '');
  return u ? u[1].toLowerCase() : originSlug(callDir(c.cmd, root));
}
/** Every one of these gh calls named as an open end: its repo and, when known, its number. */
function ghListed(ghCalls, root) {
  return (ends) => ghCalls.every((c) => listed(ends, [nameOf(ghRepo(c, root)), ghNumber(c)]));
}

function main(input) {
  if (input.stop_hook_active || !input.transcript_path) process.exit(0);
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const { calls, since, fired, lastText } = turn(input.transcript_path);
  if (fired) process.exit(0);
  const shell = calls.filter((c) => c.name === 'Bash' || c.name === 'PowerShell');
  // Each finding: its text, and whether a close entry's open-end lines cover it (null = never).
  const missing = [];

  const repo = process.env.SHARED_MEMORY_REPO || path.join(require('os').homedir(), 'Projects', 'brain-shared-memory');
  const repoName = path.basename(repo);
  const smPush = shell.some((c) => /\bgit\b[\s\S]*\bpush\b/.test(c.cmd) && c.cmd.includes(repoName));
  if (smPush && fs.existsSync(repo)) {
    const files = awaiting(repo, since);
    if (files.length && !smWatched(root)) {
      missing.push({ text: `shared-memory: ${files.slice(0, 3).join(', ')} waits on another party — arm `
        + 'Monitor({command: "bash core/scripts/shared-memory-watch.sh watch 60", persistent: true}) '
        + '(or collab-watch); mark a pure report `status: info`',
      covered: (ends) => files.every((f) => listed(ends, [path.basename(f).replace(/\.md$/, '')])) });
    }
  }
  const prCreates = shell.filter((c) => /\bgh\s+pr\s+create\b/.test(c.cmd));
  if (prCreates.length && !prWatched(root, calls)) {
    missing.push({ text: 'PR created — arm Monitor on core/scripts/watch-pr.sh <owner>/<repo> <nr> (or collab-watch)',
      covered: ghListed(prCreates, root) });
  }
  // (c) the reply ends by asking the human for a reload, and nothing waits for it to arrive
  if (RELOAD_ASK.test(lastText) && !calls.some((c) => RELOAD_WATCH.test(c.cmd))) {
    missing.push({ text: 'reload requested from the human — arm core/scripts/wait-mcp-reconnect.sh <boot-stamp-file> [timeout_s] '
      + '(Monitor or run_in_background) BEFORE asking, then say which reload you need', covered: null });
  }
  // (d) a push started a CI run and nothing in this turn watches it
  for (const slug of ciStarted(shell, root)) {
    if (ciWatched(calls, slug)) continue;
    missing.push({ text: `CI started on ${slug} (push, PR or merge) and nothing watches the run — arm `
      + `bash core/scripts/ci-watch.sh pr ${slug} <nr> (or ref ${slug} <branch>) via Monitor or run_in_background, in this turn`,
    covered: (ends) => listed(ends, [nameOf(slug)]) });
  }
  // (e) the reply asks the human for a hand step, and nothing in this turn waits for its effect
  const pats = loadPatterns(root);
  const waiter = calls.some((c) => c.name === 'Monitor' || c.name === 'ScheduleWakeup' || c.bg);
  if (!waiter && !pats.noWatcher.test(lastText)) {
    const m = pats.handStep.exec(stripQuoted(lastText));
    if (m) {
      missing.push({ text: `a hand step is asked of the human ("${m[0].trim()}") and no waiter runs — build the measurement `
        + 'and arm it (Monitor / run_in_background) BEFORE the request, say what will not move; '
        + 'where no probe is possible, write "⚙ no watcher: <why>"', covered: null });
    }
  }
  // (f) a ticket or a question posted in a thread, and no standing repo watch reads the answer
  const asks = shell.filter((c) => ISSUE_CREATE.test(c.cmd) || (COMMENT.test(c.cmd) && /[?]|\bplease\b/i.test(ghBody(c.cmd))));
  if (asks.length && !prWatched(root, calls)) {
    missing.push({ text: 'an issue or a question was posted on GitHub and no repo watch lives — arm collab-watch '
      + '(or Monitor on core/scripts/watch-pr.sh <owner>/<repo> <nr>)', covered: ghListed(asks, root) });
  }
  // (g) the brain can watch, and no standing watch lives (never armed, or the Monitor expired)
  const standing = standingConfig(root);
  if (standing) {
    const off = /^off\b/i.test(standing.setting);
    if (off && !standing.setting.replace(/^off\s*:?\s*/i, '')) {
      missing.push({ text: '.claude/rules/collab-watch.json says "standing_watch": "off" without a reason — write '
        + '"off: <why>" (a machine without collaborators, for example), or remove the key', covered: null });
    } else if (!off && !standingWatched(root, calls)) {
      missing.push({ text: 'no standing watch lives (never armed, or its Monitor expired) — arm '
        + 'Monitor({command: "bash core/scripts/collab-watch.sh", timeout_ms: 1800000}) and re-arm at every expiry '
        + 'notice; a brain that must not watch declares "standing_watch": "off: <why>" in .claude/rules/collab-watch.json',
      covered: () => true });
    }
  }
  // (h) the reply declares the work finished while a CI verdict of this session is still unread
  if (pats.doneClaim.test(stripQuoted(lastText))) {
    const pending = pendingCi(input.transcript_path);
    if (pending.length) {
      missing.push({ text: `the reply says the work is finished, but ${pending.length} CI watch(es) of this session have `
        + `no verdict read yet (${pending.slice(0, 4).join(', ')}) — a merge or push is done only with its CI verdict: `
        + 'say it is open and what is awaited, or read the verdict first', covered: null });
    }
  }
  if (!missing.length) process.exit(0);
  // The close turn: a close stamp of this session and turn passes what its entry lists (header).
  let left = missing;
  const ends = missing.some((m) => m.covered) ? closeOpenEnds(root, { sessionId: input.session_id, since, calls }) : null;
  if (ends) left = missing.filter((m) => !(m.covered && m.covered(ends)));
  if (!left.length) process.exit(0);
  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason: `WATCH-GATE: a watcher is missing. ${left.map((m) => m.text).join(' · ')}. `
      + (ends ? 'The close stamp passes only what its session-log entry lists as "open end: <repo> #<n> - what is awaited" '
        + '(a shared-memory request by its file name). ' : '')
      + 'If nothing is awaited, say why in one line and stop again.',
  }));
  process.exit(0);
}
