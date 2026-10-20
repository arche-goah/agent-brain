#!/usr/bin/env node
/**
 * live-watchdog.cjs — PostToolUse + PreToolUse: after every N write calls to a live system's
 * MCP tools, that system's own check runs; while the check is red, further writes to that
 * system are refused until it is green again.
 *
 * WHY (agreed by the operator 2026-09-24 and a collaborator 2026-10-20, from a collaborator's
 * draft of a session watcher): in a long session on a live tool, the agent kept writing while
 * the system had already drifted from its target state — and nothing between the writes
 * measured the system. Measured gap at the time: no PostToolUse hook on any live MCP server
 * in any brain. The operator's limit when agreeing it: the core heals nothing; how good the
 * check is depends on the mechanisms the SUITES ship — the core only makes them fire the same
 * way in every suite. So this helper owns the trigger and the block; the check script and the
 * target state it checks against live in each suite.
 *
 * ONE FILE, TWO EVENTS (hook_event_name decides):
 *  - PostToolUse on a write tool of a suite: count it. At the N-th, run the suite's check.
 *    exit 0 = green (counter resets) · exit 1 = red (the suite is marked red, the agent is told
 *    at once) · any other exit, a timeout or a check that cannot start = NOT MEASURABLE: not
 *    red (a hung tool must not read as a broken show), the agent is told, and the check runs
 *    again after the next write.
 *  - PreToolUse on a write tool of a RED suite: run the check again. Green clears the mark and
 *    lets the call through; anything else refuses it. Only a green run clears red. A tool named
 *    in the suite's `repair` list (an undo, a restore) is let through while red.
 * Reads are never counted and never blocked: the gate measures the system, it does not ration
 * looking at it.
 *
 * State is per PROJECT, not per session (`.claude-state/live-watchdog.json`): a live system that
 * went red in one session is red for the next one too, until a check says otherwise.
 *
 * WHICH tools write to WHICH system, how often to check and WHAT to run is INSTANCE DATA:
 *   <project>/.claude/rules/live-watchdog.json
 *   { "suites": [ { "name": "<same name as its domain in live-read.json>",
 *       "writes": [regex on tool name], "every": N (default 5),
 *       "check": ["<program>", "<arg>", ...]  (argv, no shell; cwd = project; ~/ expanded),
 *       "timeout_s": 60, "repair": [regex on tool name] } ],
 *     "no_check": { "<live-read domain>": "<why this live system has no check>" } }
 * Template: templates/rules-instance/live-watchdog.json (ships with no suites).
 * No file → silent no-op. Broken file → no-op, logged to .claude-state/live-watchdog.log
 * (fail-open on its own config, like live-read-gate).
 * INERT-WITHOUT: .claude/rules/live-watchdog.json suites
 *   (read by scripts/hook-coverage.py: wired with no file or no suites = reported, unless the
 *   file says why in `"inert_ok": "<reason>"`; a live-read.json domain with no suite of the same
 *   name and no `no_check` reason is reported too — a live system nobody checks is visible)
 * The settings matcher must cover every tool a suite names; the template wires `mcp__.*` on
 * both events.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const STATE_DIR = path.join(ROOT, '.claude-state');
const STATE = path.join(STATE_DIR, 'live-watchdog.json');
const LOG = path.join(STATE_DIR, 'live-watchdog.log');
const TAIL = 1500; // characters of check output handed to the agent

function log(line) {
  try { fs.mkdirSync(STATE_DIR, { recursive: true }); fs.appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`); } catch (_) {}
}

function rx(list) {
  return (Array.isArray(list) ? list : [])
    .map((s) => { try { return new RegExp(s, 'i'); } catch (_) { return null; } })
    .filter(Boolean);
}

function loadSuites() {
  const p = path.join(ROOT, '.claude', 'rules', 'live-watchdog.json');
  let text;
  try { text = fs.readFileSync(p, 'utf8'); } catch (_) { return []; } // no file: inert, silent
  let raw;
  try { raw = JSON.parse(text); } catch (e) { log(`BAD-CONFIG ${p}: ${e.message}`); return []; }
  return (Array.isArray(raw.suites) ? raw.suites : [])
    .filter((s) => s && s.name && Array.isArray(s.check) && s.check.length)
    .map((s) => ({
      name: String(s.name),
      writes: rx(s.writes),
      repair: rx(s.repair),
      every: Math.max(1, parseInt(s.every, 10) || 5),
      check: s.check.map((a) => (String(a).startsWith('~/') ? path.join(os.homedir(), String(a).slice(2)) : String(a))),
      timeout: Math.max(1, Number(s.timeout_s) || 60) * 1000,
    }));
}

function loadState() {
  try { return JSON.parse(fs.readFileSync(STATE, 'utf8')) || {}; } catch (_) { return {}; }
}

function saveState(st) {
  try { fs.mkdirSync(STATE_DIR, { recursive: true }); fs.writeFileSync(STATE, JSON.stringify(st, null, 2) + '\n'); } catch (e) { log(`STATE-WRITE ${e.message}`); }
}

/** 'green' | 'red' | 'unmeasured', plus the output the agent sees. */
function runCheck(s) {
  const r = spawnSync(s.check[0], s.check.slice(1), { cwd: ROOT, timeout: s.timeout, encoding: 'utf8', windowsHide: true });
  const out = `${r.stdout || ''}${r.stderr || ''}`.trim();
  const tail = out.length > TAIL ? '…' + out.slice(-TAIL) : out;
  if (r.error) return { verdict: 'unmeasured', text: `${r.error.code || r.error.message}${tail ? '\n' + tail : ''}` };
  if (r.status === 0) return { verdict: 'green', text: tail };
  if (r.status === 1) return { verdict: 'red', text: tail };
  return { verdict: 'unmeasured', text: `exit ${r.status === null ? 'signal ' + r.signal : r.status}${tail ? '\n' + tail : ''}` };
}

function emit(obj) { console.log(JSON.stringify(obj)); process.exit(0); }

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { input += c; });
process.stdin.on('end', () => {
  let hook;
  try { hook = JSON.parse(input); } catch (_) { process.exit(0); }
  const tool = String(hook.tool_name || '');
  const event = String(hook.hook_event_name || '');
  const suites = loadSuites().filter((s) => s.writes.some((r) => r.test(tool)));
  if (!suites.length) process.exit(0);
  const st = loadState();
  const cmd = (s) => s.check.join(' ');

  if (event === 'PreToolUse') {
    for (const s of suites) {
      const cur = st[s.name] || {};
      if (!cur.red) continue;
      if (s.repair.some((r) => r.test(tool))) { log(`REPAIR-PASS suite=${s.name} tool=${tool}`); continue; }
      const res = runCheck(s);
      if (res.verdict === 'green') {
        st[s.name] = { count: 0, red: null };
        saveState(st);
        log(`GREEN-AGAIN suite=${s.name}`);
        continue;
      }
      st[s.name] = { ...cur, red: { since: cur.red.since, output: res.text } };
      saveState(st);
      log(`BLOCKED suite=${s.name} tool=${tool} verdict=${res.verdict}`);
      emit({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason:
            `LIVE-WATCHDOG: "${s.name}" is red since ${cur.red.since} — its check (\`${cmd(s)}\`) ` +
            `${res.verdict === 'red' ? 'still fails' : 'could not measure, and only a green run clears red'}:\n` +
            `${res.text || '(no output)'}\n\nWrites to this system stay refused until the check passes. ` +
            'Read the system, find what broke, and restore it' +
            (s.repair.length ? ' (the suite\'s repair tools pass)' : '') +
            ' — or report it to the operator. Every write attempt re-runs the check. ' +
            '(instance data: .claude/rules/live-watchdog.json)',
        },
      });
    }
    process.exit(0);
  }

  if (event !== 'PostToolUse') process.exit(0);
  const notes = [];
  let red = null;
  for (const s of suites) {
    const cur = st[s.name] || { count: 0, red: null };
    const count = (cur.count || 0) + 1;
    if (count < s.every || cur.red) { st[s.name] = { ...cur, count }; continue; }
    const res = runCheck(s);
    log(`CHECK suite=${s.name} after=${count} verdict=${res.verdict}`);
    if (res.verdict === 'green') st[s.name] = { count: 0, red: null };
    else if (res.verdict === 'red') {
      st[s.name] = { count: 0, red: { since: new Date().toISOString(), output: res.text } };
      red = red || { s, res, count };
    } else {
      st[s.name] = { count, red: null }; // retried after the next write
      notes.push(`LIVE-WATCHDOG: the check of "${s.name}" (\`${cmd(s)}\`) could not measure after ${count} writes ` +
        `(${res.text.split('\n')[0]}). Not treated as red; it runs again after the next write.`);
    }
  }
  saveState(st);
  if (red) {
    emit({
      decision: 'block',
      reason: `LIVE-WATCHDOG: the check of "${red.s.name}" (\`${cmd(red.s)}\`) is RED after ${red.count} writes:\n` +
        `${red.res.text || '(no output)'}\n\nFurther writes to this system are refused until the check passes. ` +
        'Stop building on top: read the system, find what the last writes broke, restore it, or report it to the operator.' +
        (notes.length ? '\n\n' + notes.join('\n') : ''),
    });
  }
  if (notes.length) emit({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: notes.join('\n') } });
  process.exit(0);
});
