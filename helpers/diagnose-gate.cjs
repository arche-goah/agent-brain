#!/usr/bin/env node
/**
 * Stop hook: the trigger for CAUSAL claims — carrier of "evidence chain or silence"
 * (rules/thinking-protocol.md, Anti-Hallucination rule 0), sister of class-gate.
 *
 * Origin (operator, 2026-08-07, translated: "what do you learn from this? consequences? or do we
 * stay in this pattern of concessions made after the fact?") — on a day with five misdiagnoses
 * on the proving instance, each recognised as one only after the operator pointed at it.
 *
 * WHY a hook and not another register line: the rules were written down already and were broken
 * again the same day — one of them in the very turn that wrote it. A register is read when one
 * SEARCHES for it; nobody searches while formulating an explanation. The only carrier that
 * demonstrably worked that day was class-gate.
 *
 * The root the operator named: rules hung on WORDS instead of EFFECTS. A rule tied to the word
 * "reset" did not fire on a "test"; the negative control tied to "measurement" did not fire on
 * an "explanation". This gate therefore hangs on the EFFECT: a tool reported a failure.
 *
 * The blind spot it asks about explicitly: the agent models a system as one only it works on.
 * The operator is a second actor — the "inexplicable" link loss of 2026-08-07 was the operator
 * re-plugging a cable, announced three messages earlier. A human in the time window is the most
 * often missed cause.
 *
 * TRIGGER (narrow on purpose, so it does not become wallpaper):
 *   a tool_result in the turn reports a STATE failure (unreachable, packet loss, auth broken,
 *   timeout) AND no log or journal was read in the same turn.
 * Whoever read the log ran the counter-check — then the gate is silent. Refused actions
 * (REFUSED, PREVIEW, permission denied) are no failure: those are guards doing their job.
 *
 * Version 2 (2026-08-07, the first firing was a FALSE POSITIVE): the gate matched "timeout" and
 * "unreachable" in SOURCE CODE the agent had shown with grep/sed in the same turn. A tool_result
 * can be a STATE REPORT or a DISPLAY OF TEXT, and the pattern alone cannot tell them apart. So
 * only results of tools that query a DEVICE count — not those of file and text tools.
 *
 * Language and site data (instance file `.claude/rules/diagnose-patterns.json`, template
 * `templates/rules-instance/diagnose-patterns.json`): `failure_patterns`, `not_failure_patterns`
 * and `log_read_patterns` EXTEND the built-ins below — a brain adds the log tools of its own
 * systems (an MCP log tool, a device's log command) and the failure wording of its tools.
 *
 * Wiring: row DIAGNOSE-GATE in `templates/rules-instance/stop-checks.json`, mode record (the
 * block is recorded as would_block); blocking is the operator's decision per brain.
 * Fixture: `scripts/test-diagnose-gate.sh`. Ported from the macOS instance's alpha
 * (2026-08-07 to 2026-11-07, Working Rule #11).
 */

const fs = require('fs');
const path = require('path');
// A harness notification (task done, watcher event) is not an operator turn — it must not
// count down this gate's cooldown (2026-10-07; one definition: turn-kind.cjs).
const { isNotification } = require('./turn-kind.cjs');
// Own echo: legacy token or, behind the dispatcher, the label line (stop-echo.cjs).
const { ownEcho, declare } = require('./stop-echo.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
let OWN_ECHO = /DIAGNOSE-GATE/;
const COOLDOWN_TURNS = 3;
const TAIL_BYTES = 4 * 1024 * 1024;

// State failures: a symptom that raises a cause question.
const BUILTIN_FAILURE = [
  '\\b[1-9][0-9.]*% packet loss', // 0.0% is healthy and must not trigger
  '\\bstill failing\\b',
  '\\bunreachable\\b',
  '\\bURLError\\b',
  '\\btimed? ?out\\b',
  '\\bERROR (HTTPError|ConnectionError|OSError)',
  '\\blink (down|lost)\\b',
  '\\bnot responding\\b',
  '\\bconnection refused\\b',
];
// Guards and previews are intent, not a defect — they must never trigger.
const BUILTIN_NOT_FAILURE = ['REFUSED', 'PREVIEW', 'Permission (for this action )?was denied', 'permission denied'];
// Whoever read the log asked the origin question. Generic log readers; a brain adds its own.
const BUILTIN_LOG_READ = [
  '\\bjournalctl\\b', '\\blog show\\b', '\\bGet-WinEvent\\b', '\\bGet-EventLog\\b',
  'journal\\.jsonl', '\\.log\\b', '_logs?\\b', '/log\\b', '\\blog print\\b',
];

const READS_TEXT = /^(Read|Grep|Glob|NotebookRead)$/;
const SHOWS_CODE = /\b(grep|sed|awk|cat|head|tail|rg|ugrep|less|more|type|Get-Content|Select-String)\b/;
const SOURCEY = /\.(py|cjs|js|ts|sh|ps1|json|md)\b|def \w+\(|function \w+\(|=>|^\s*#/m;

function loadPatterns(cwd) {
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'diagnose-patterns.json'), 'utf8')); }
  catch (e) { /* built-ins only */ }
  const list = (builtins, extra) => {
    const out = [...builtins];
    if (Array.isArray(extra)) for (const p of extra) { try { new RegExp(p); out.push(p); } catch (e) { /* skip */ } }
    return out;
  };
  return {
    failure: list(BUILTIN_FAILURE, cfg.failure_patterns).map((p) => new RegExp(p, 'iu')),
    notFailure: new RegExp(list(BUILTIN_NOT_FAILURE, cfg.not_failure_patterns).join('|'), 'iu'),
    logRead: new RegExp(list(BUILTIN_LOG_READ, cfg.log_read_patterns).join('|'), 'iu'),
  };
}

function readTail(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally {
    fs.closeSync(fd);
  }
}

function textOf(block) {
  if (typeof block === 'string') return block;
  if (!block || typeof block !== 'object') return '';
  if (typeof block.content === 'string') return block.content;
  if (Array.isArray(block.content)) return block.content.map(textOf).join('\n');
  if (typeof block.text === 'string') return block.text;
  return '';
}

function analyze(transcriptPath, pats) {
  const lines = readTail(transcriptPath);
  const events = [];
  // tool_use_id -> which tool produced the result. Without it, a hit in a result cannot be
  // told apart from a hit in displayed source text.
  const origin = new Map();
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;

    if (msg.role === 'user') {
      if (typeof msg.content === 'string') {
        if (HOOK_ECHO.test(msg.content)) {
          if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
          continue;
        }
        if (!isNotification(msg.content)) events.push({ boundary: true });
        continue;
      }
      if (Array.isArray(msg.content)) {
        for (const b of msg.content) {
          if (b.type !== 'tool_result') continue;
          const t = textOf(b);
          if (!t) continue;
          // A file or text tool SHOWS content; it reports nothing about a device.
          const src = origin.get(b.tool_use_id) || {};
          if (READS_TEXT.test(src.name || '')) continue;
          if (/^(Bash|PowerShell)$/.test(src.name || '') && SHOWS_CODE.test(src.cmd || '')) continue;
          if (SOURCEY.test(t)) continue;
          for (const pat of pats.failure) {
            const m = t.match(pat);
            if (m && !pats.notFailure.test(t.slice(Math.max(0, m.index - 120), m.index + 120))) {
              events.push({ failure: m[0].trim().slice(0, 60) });
              break;
            }
          }
        }
      }
      continue;
    }

    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type !== 'tool_use') continue;
        if (b.id) origin.set(b.id, { name: b.name || '', cmd: (b.input && b.input.command) || '' });
        const probe = JSON.stringify(b.input || {}) + ' ' + (b.name || '');
        if (pats.logRead.test(probe)) events.push({ logread: true });
      }
    }
  }

  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const turn = events.slice(last);

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }

  return {
    failures: [...new Set(turn.filter((e) => e.failure).map((e) => e.failure))],
    logread: turn.some((e) => e.logread),
    quiet: turnsSinceGate < COOLDOWN_TURNS,
  };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let seen;
  try {
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    seen = analyze(input.transcript_path, loadPatterns(cwd));
  } catch (e) {
    return allow(); // no readable transcript — never block because of that
  }
  if (seen.quiet) return allow();
  if (seen.failures.length === 0) return allow();
  if (seen.logread) return allow(); // the counter-check demonstrably ran

  const shown = seen.failures.slice(0, 3).map((f) => `"${f}"`).join(', ');

  console.log(JSON.stringify(declare({
    decision: 'block',
    reason:
      'DIAGNOSE-GATE (fires because a tool reported a FAILURE and no log or journal was read in this turn).\n' +
      `Reported: ${shown}\n` +
      'Answer briefly, then stop — no new round of work:\n' +
      '1. ORIGIN FIRST: did a HUMAN act in the time window (re-plugged, restarted, rebuilt, an admin tool open)? ' +
      'That is the most often missed cause — the operator works on the same system in parallel. Announced ' +
      'actions count: does it stand further up in the conversation?\n' +
      '2. SYMPTOM OR CAUSE: did the reply claim a "because"? Then which measurement connects A with B? ' +
      '"No ping" proves "unreachable", not "the import aborted". "It arrives" proves "ONE path carries", not ' +
      '"THIS path carries". Without a nameable measurement the answer is "cause unknown" — a hedge word ' +
      'replaces no evidence.\n' +
      '3. SECOND PATH: which OTHER cause would have produced the same symptom, and what excluded it? An ' +
      'explanation that FITS the expectation is the reason for the counter-check, not against it.\n' +
      '4. Not explained yet, only observed? Then say "only observed, no cause claimed" and stop. That is a ' +
      'valid answer.',
  }, input)));
  process.exit(0);
});

process.stdin.resume();
