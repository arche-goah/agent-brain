#!/usr/bin/env node
/**
 * live-read-gate.cjs — PreToolUse: a LIVE system is not touched before its mandatory
 * reading has been read IN THIS SESSION — completely, not in part.
 *
 * WHY (operator order on the proving instance, 2026-09-02, after an incident the same
 * day): the agent probed a live network with ad-hoc pings and MCP calls, diagnosed
 * "device down" and asked the operator to restart it — without having read the domain
 * ledger whose first section exists exactly to prevent false "unreachable" diagnoses.
 * The prose rule "read the ledger before any work on this system" had stood in the
 * instance's CLAUDE.md for weeks. Prose is a resolution; this hook is the carrier.
 *
 * WHAT COUNTS AS READ: the DELIVERED line windows of `Read` results on the required file,
 * taken together, cover the whole file as it is now. The harness records for every Read
 * what it actually delivered (`toolUseResult.file`: startLine, numLines, totalLines), and
 * that record is the measurement — never the call. Two gaps were closed on the proving
 * instance before this port:
 *  1. The first version looked at the CALL ("Read without offset/limit = complete"), while
 *     the harness caps a single read by tokens: on a 1468-line ledger it delivered lines
 *     1-426 and the gate opened at 29 % (coherence scan 2026-09-18). The same fix ends the
 *     opposite failure — a session paging through with offset/limit counted as "partial"
 *     forever.
 *  2. The first version scanned only the last 16 MB of the transcript; a session with
 *     many image captures pushed its own reads out of that window and the gate blocked
 *     work whose reading had happened (2026-09-02). The whole transcript is walked now.
 * A Bash `cat` counts only for a file small enough that Bash output is not truncated.
 * grep/head/sed/tail never count. The transcript is the source — per session, so an
 * earlier session's read does not carry, and a forked subagent has its own transcript
 * and must read for itself.
 *
 * KNOWN LIMITS, stated rather than hidden:
 *  - Coverage is measured in LINE NUMBERS against the file's current length. Lines
 *    appended after the read are caught (they were never delivered); a file REWRITTEN in
 *    place to the same or a shorter length is not. Invalidating every window on any
 *    change would punish the session's own small edits to the ledger with a full re-read
 *    each time, so the lenient side was chosen on purpose.
 *  - Paths are compared after `path.resolve` (case-folded on Windows). A Git Bash form
 *    (`cat /c/...`) does not resolve to the native path and simply does not count — the
 *    gate fails CLOSED there, and a Read satisfies it.
 *
 * WHICH tools are live and WHICH files they require is INSTANCE DATA:
 *   <project>/.claude/rules/live-read.json
 *   { "domains": [ { "name", "tools": [regex on tool name], "bash": [regex on the Bash
 *     command], "required": [ { "path": "<project-relative | absolute | ~/...>",
 *     "label" } ] } ] }
 * Template: templates/rules-instance/live-read.json (ships with no domains).
 * No file → silent no-op. Broken file → no-op, logged to .claude-state/live-read-gate.log
 * (fail-open: a read-only hook must never take the session hostage over its own config).
 * The settings matcher must cover every tool a domain names; the template wires
 * `Bash|mcp__.*`, an instance gating other tools widens it.
 *
 * No bypass marker on purpose. Reading the file is ONE tool call; an emergency that
 * cannot afford it does not exist — the incident that motivated this gate was itself a
 * "quick look".
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const LOG = path.join(ROOT, '.claude-state', 'live-read-gate.log');
// Bash output is truncated around 30k characters; a `cat` of anything bigger proves nothing.
const CAT_MAX_BYTES = 24 * 1024;

function log(line) {
  try { fs.appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`); } catch (_) {}
}

function expand(p) {
  if (p.startsWith('~/')) return path.join(os.homedir(), p.slice(2));
  return path.isAbsolute(p) ? p : path.join(ROOT, p);
}

/** Comparable form of a path: resolved, and case-folded where the filesystem is. */
function key(p) {
  const r = path.resolve(expand(String(p)));
  return process.platform === 'win32' ? r.toLowerCase() : r;
}

function rx(list) {
  return (Array.isArray(list) ? list : [])
    .map((s) => { try { return new RegExp(s, 'i'); } catch (_) { return null; } })
    .filter(Boolean);
}

function loadDomains() {
  const p = path.join(ROOT, '.claude', 'rules', 'live-read.json');
  let text;
  try { text = fs.readFileSync(p, 'utf8'); } catch (_) { return []; } // no file: inert, silent
  let raw;
  try { raw = JSON.parse(text); } catch (e) { log(`BAD-CONFIG ${p}: ${e.message}`); return []; }
  return (Array.isArray(raw.domains) ? raw.domains : [])
    .filter((d) => d && d.name && Array.isArray(d.required) && d.required.length)
    .map((d) => ({
      name: d.name,
      tools: rx(d.tools),
      bash: rx(d.bash),
      required: d.required
        .filter((r) => r && r.path)
        .map((r) => ({ path: path.resolve(expand(r.path)), key: key(r.path), shown: r.path, label: r.label || '' })),
    }));
}

/**
 * Walk the WHOLE transcript line by line in fixed chunks. Lines are pre-filtered by a
 * cheap substring test before any JSON.parse, so a large transcript costs a scan, not a
 * parse.
 */
function eachLine(file, wanted, fn) {
  const fd = fs.openSync(file, 'r');
  const buf = Buffer.alloc(4 * 1024 * 1024);
  let carry = '';
  try {
    for (;;) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (!n) break;
      const parts = (carry + buf.toString('utf8', 0, n)).split('\n');
      carry = parts.pop();
      for (const l of parts) if (l && wanted(l)) fn(l);
    }
    if (carry && wanted(carry)) fn(carry);
  } finally { fs.closeSync(fd); }
}

/**
 * What this session has read of the required files:
 *   windows: Map<key, [first, last][]>  — line windows the harness DELIVERED
 *   cats:    Set<key>                   — files dumped via Bash `cat`
 */
function readEvidence(transcriptPath, requiredPaths) {
  const names = [...new Set(requiredPaths.map((p) => path.basename(p)))];
  const windows = new Map();
  const cats = new Set();
  const wanted = (l) => names.some((n) => l.includes(n));
  eachLine(transcriptPath, wanted, (line) => {
    let d;
    try { d = JSON.parse(line); } catch (_) { return; }
    // (a) the harness's own record of a Read result: what was actually delivered
    const f = d.toolUseResult && d.toolUseResult.file;
    if (f && f.filePath && Number(f.numLines) > 0) {
      const k = key(f.filePath);
      const first = Number(f.startLine || 1);
      const w = windows.get(k) || [];
      w.push([first, first + Number(f.numLines) - 1]);
      windows.set(k, w);
    }
    // (b) a Bash `cat <file>` call; sed -n, head, grep are partial by construction
    const msg = d.message;
    if (!msg || msg.role !== 'assistant' || !Array.isArray(msg.content)) return;
    for (const b of msg.content) {
      if (b.type !== 'tool_use' || b.name !== 'Bash' || !b.input || typeof b.input.command !== 'string') continue;
      const m = b.input.command.match(/(?:^|[;&|]\s*)cat\s+(?:-[A-Za-z]+\s+)*("[^"]+"|'[^']+'|\S+)/g);
      for (const hit of m || []) {
        const file = hit.replace(/^.*?cat\s+(?:-[A-Za-z]+\s+)*/, '').replace(/^["']|["']$/g, '');
        cats.add(key(file));
      }
    }
  });
  return { windows, cats };
}

/** Line count the way the harness counts it (a trailing newline does not open a new line). */
function lineCount(file) {
  const t = fs.readFileSync(file, 'utf8');
  if (!t) return 0;
  const n = t.split('\n').length;
  return t.endsWith('\n') ? n - 1 : n;
}

/** First line (1-based) not covered by the union of windows, or 0 when 1..total is covered. */
function firstGap(wins, total) {
  let next = 1;
  for (const [a, b] of [...wins].sort((x, y) => x[0] - y[0])) {
    if (a > next) break;
    if (b >= next) next = b + 1;
  }
  return next > total ? 0 : next;
}

/** '' when the required file counts as read, otherwise the reason (shown to the agent). */
function unreadReason(req, ev) {
  let total, size;
  try { total = lineCount(req.path); size = fs.statSync(req.path).size; } catch (_) {
    return 'file does not exist — fix .claude/rules/live-read.json, the gate cannot be satisfied';
  }
  if (ev.cats.has(req.key) && size <= CAT_MAX_BYTES) return '';
  const wins = ev.windows.get(req.key) || [];
  if (!wins.length) {
    return ev.cats.has(req.key)
      ? `cat does not count here: ${size} bytes exceed what Bash returns untruncated — use Read`
      : `not read yet (${total} lines)`;
  }
  const gap = firstGap(wins, total);
  if (!gap) return '';
  const got = [...wins].sort((x, y) => x[0] - y[0]).map(([a, b]) => `${a}-${b}`).join(', ');
  return `only lines ${got} of ${total} were delivered — continue with Read offset=${gap}`;
}

function deny(reason) {
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  }));
  process.exit(0);
}

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { input += c; });
process.stdin.on('end', () => {
  let hook;
  try { hook = JSON.parse(input); } catch (_) { process.exit(0); }
  const tool = String(hook.tool_name || '');
  const cmd = tool === 'Bash' ? String((hook.tool_input || {}).command || '') : '';

  const hits = loadDomains().filter((d) =>
    d.tools.some((r) => r.test(tool)) || (cmd && d.bash.some((r) => r.test(cmd))));
  if (!hits.length) process.exit(0);
  if (!hook.transcript_path || !fs.existsSync(hook.transcript_path)) {
    log(`NO-TRANSCRIPT tool=${tool}`); process.exit(0);
  }

  let ev;
  try {
    ev = readEvidence(hook.transcript_path, hits.flatMap((d) => d.required.map((r) => r.path)));
  } catch (e) { log(`ERR ${e.message}`); process.exit(0); }

  const missing = [];
  for (const d of hits) {
    for (const r of d.required) {
      const why = unreadReason(r, ev);
      if (why) missing.push({ domain: d.name, why, ...r });
    }
  }
  if (!missing.length) process.exit(0);

  const list = missing.map((m) =>
    `  - [${m.domain}] ${m.path}${m.label ? `   (${m.label})` : ''}\n      → ${m.why}`).join('\n');
  log(`BLOCKED tool=${tool} ${cmd ? 'cmd=' + cmd.slice(0, 120) : ''} missing=${missing.map((m) => `${m.shown} [${m.why}]`).join(',')}`);
  deny(
    `LIVE-READ-GATE: "${tool}" touches a live system whose mandatory reading has not been ` +
    `read in this session.\n\nRead COMPLETELY first — what counts is what the Read tool DELIVERED, ` +
    `so a long file needs several Reads with offset/limit until every line is covered:\n${list}\n\n` +
    'grep/head/sed never count. ' +
    'Then repeat the call unchanged. This gate has no bypass marker on purpose — reading ' +
    'the file is one tool call (instance data: .claude/rules/live-read.json).'
  );
});
