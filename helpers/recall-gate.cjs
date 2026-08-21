#!/usr/bin/env node
/**
 * Stop Hook: RESEARCH THAT LEAVES NO CARRIER IS RESEARCH SOMEONE PAYS FOR TWICE.
 *
 * Measured on the Windows instance 2026-08-21 (shared memory,
 * grandma3/zentrale-erkenntnisablage-gegen-doppelrecherche-2026-08-21.md): one session
 * burned ~60 % of its limit reading a reference showfile live, wrote ONE summary line
 * into the session log and no memory file; the next session re-read the same
 * structures live until the operator stopped it. The findings were not lost — they sat
 * in the transcript — but nothing had given them a carrier, and nothing had forced the
 * next session to look. Write side and read side failed together.
 *
 * This gate is the WRITE side. It counts, over the whole session, how often the agent
 * read a live system through research tools (MCP reads, exports, bulk listings) and
 * whether anything was persisted since the first of those reads — a memory file, a
 * ledger entry, a suite reference, a shared-memory push. Research above the threshold
 * with nothing persisted ends the turn with one plain question: what of this must
 * nobody read again tomorrow? The read side (look before you read live) is a tool,
 * `scripts/transcript-recall.py`, named in the block text.
 *
 * WHICH tools count as research and WHICH writes count as persistence is INSTANCE
 * DATA: `.claude/rules/recall-tools.json` (regexes on tool names, file paths and Bash
 * commands). A brain without that file gets conservative defaults; a brain without MCP
 * research tools never trips it.
 *
 * Mechanics kept from class-gate (proven there):
 * - transcript is the source, never the working tree;
 * - cooldown of 3 operator turns, read from the gate's own replayed echo;
 * - after a block it fires again only if NEW research happened since — it must not
 *   become wallpaper on a session that simply keeps working on something else;
 * - stdin read to 'end', never on a timer;
 * - `--record` mode: never blocks, prints {record:[...]} for the stop-dispatcher, so
 *   precision can be measured before the gate is allowed to interrupt anyone
 *   (operator rule 2026-08-20: measure, then arm — a block that changes nothing costs
 *   a whole re-issue for nothing).
 */
const fs = require('fs');
const path = require('path');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

const RECORD = process.argv.includes('--record');
function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /RECALL-GATE/;
const COOLDOWN_TURNS = 3;
const TAIL_BYTES = 16 * 1024 * 1024;

const DEFAULTS = {
  threshold: 8,
  research: [
    // MCP tools that READ a live system in bulk. Tool names are the only stable handle.
    '^mcp__.*(children|search|export|overview|xml_get|xml_summary|object_props|contents|' +
      'readout|leases|ports_all|full_readout|scan|probe|inspect|dmx_read|get_td_nodes)',
  ],
  persistTools: ['Write', 'Edit', 'MultiEdit', 'NotebookEdit'],
  persistPaths: [
    '[\\\\/]memory[\\\\/][^\\\\/]+\\.md$',        // auto-memory file
    'offene-punkte\\.md$',                        // instance ledger
    '[\\\\/]references[\\\\/]',                   // suite references
    'shared-memory',                              // shared-memory repo
    '[\\\\/]docs[\\\\/][^\\\\/]+[\\\\/].*\\.md$', // domain docs (runlogs, findings)
  ],
  persistBash: ['memory-sync', 'shared-memory.*(commit|push)', 'git .*commit.*(memory|ledger|befund|finding|runlog)'],
};

function loadConfig(root) {
  const p = path.join(root, '.claude', 'rules', 'recall-tools.json');
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { /* defaults */ }
  const rx = (arr, dflt) => (Array.isArray(arr) && arr.length ? arr : dflt)
    .map((s) => { try { return new RegExp(s, 'i'); } catch (e) { return null; } })
    .filter(Boolean);
  return {
    threshold: Number.isFinite(cfg.threshold) ? cfg.threshold : DEFAULTS.threshold,
    research: rx(cfg.research, DEFAULTS.research),
    persistTools: new Set(Array.isArray(cfg.persistTools) && cfg.persistTools.length
      ? cfg.persistTools : DEFAULTS.persistTools),
    persistPaths: rx(cfg.persistPaths, DEFAULTS.persistPaths),
    persistBash: rx(cfg.persistBash, DEFAULTS.persistBash),
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

/**
 * One pass: research calls, persistence events, operator boundaries, own echoes.
 * Returns counts over the session plus what happened since the last own block.
 */
function analyze(transcriptPath, cfg) {
  const events = [];
  for (const line of readTail(transcriptPath)) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      events.push({ boundary: true });
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    for (const b of msg.content) {
      if (b.type !== 'tool_use' || !b.name) continue;
      if (cfg.research.some((r) => r.test(b.name))) {
        events.push({ research: b.name });
        continue;
      }
      if (cfg.persistTools.has(b.name)) {
        const p = b.input && b.input.file_path;
        if (p && cfg.persistPaths.some((r) => r.test(String(p)))) events.push({ persist: p });
        continue;
      }
      if (b.name === 'Bash') {
        const c = b.input && b.input.command;
        if (c && cfg.persistBash.some((r) => r.test(String(c)))) events.push({ persist: 'bash' });
      }
    }
  }

  let research = 0, persisted = 0, firstResearch = -1, lastGate = -1;
  const tools = new Map();
  events.forEach((e, i) => {
    if (e.research) {
      research += 1;
      if (firstResearch < 0) firstResearch = i;
      tools.set(e.research, (tools.get(e.research) || 0) + 1);
    }
    if (e.gate) lastGate = i;
  });
  // Persistence only counts AFTER the first research call — a memory note written
  // before the reading started is not a carrier for what was read.
  if (firstResearch >= 0) {
    for (let i = firstResearch + 1; i < events.length; i++) if (events[i].persist) persisted += 1;
  }
  let turnsSinceGate = Infinity, researchSinceGate = research;
  if (lastGate >= 0) {
    turnsSinceGate = 0; researchSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) {
      if (events[i].boundary) turnsSinceGate += 1;
      if (events[i].research) researchSinceGate += 1;
    }
  }
  const top = [...tools.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4)
    .map(([n, c]) => `${n.replace(/^mcp__[^_]+__/, '')}×${c}`);
  return { research, persisted, top, quiet: turnsSinceGate < COOLDOWN_TURNS, researchSinceGate };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  const root = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const cfg = loadConfig(root);
  let seen;
  try { seen = analyze(input.transcript_path, cfg); } catch (e) { return allow(); }

  const due = seen.research >= cfg.threshold && seen.persisted === 0 && seen.researchSinceGate > 0;
  if (RECORD) {
    if (seen.research > 0) {
      console.log(JSON.stringify({ record: [{
        research: seen.research, persisted: seen.persisted, threshold: cfg.threshold,
        would_block: due && !seen.quiet, tools: seen.top,
      }] }));
    }
    return allow();
  }
  if (!due || seen.quiet) return allow();

  console.log(JSON.stringify({
    decision: 'block',
    reason:
      `RECALL-GATE — routine, not an error. This session read a live system ${seen.research}× ` +
      `(${seen.top.join(', ')}) and persisted nothing since. ` +
      'What of it must nobody read again tomorrow? Give it a carrier now — memory file, ' +
      'ledger entry, suite reference, shared-memory — or answer "⚙ nothing reusable". ' +
      '(Before the NEXT live read: scripts/transcript-recall.py <keyword> finds what earlier ' +
      'sessions already read.)',
  }));
  process.exit(0);
});

process.stdin.resume();
