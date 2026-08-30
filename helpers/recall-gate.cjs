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
 * SECOND TRIGGER — the verification CLAIM (added 2026-08-30, operator order "T5+T6 ok";
 * proposed by the Windows instance as a separate gate, built here as one mechanism
 * because it is the same class): tool counting misses the cheapest way to lose
 * knowledge. A single command can establish a mechanism ("the two-level nesting syntax
 * works — verified live"), which is one tool call, far under any research threshold,
 * and worth more than fifty listings. That instance verified exactly such a syntax,
 * called it a breakthrough, persisted nothing, and two days later had to dig it back
 * out of a transcript — with one failed live session in between.
 *
 * So the gate also counts what the agent CLAIMS in its own text. A claim counts only
 * when a verification verb and a discovery object meet in the same text block
 * ("verified" AND "mechanism/syntax/root cause/live") — the AND is what keeps a routine
 * "CI green, verified" from tripping it, and it is why the two lists are separate data.
 *
 * WHICH tools count as research, WHICH words count as a verification claim, and WHICH
 * writes count as persistence is INSTANCE DATA: `.claude/rules/recall-tools.json`
 * (regexes on tool names, assistant text, file paths and Bash commands). A brain
 * without that file gets conservative defaults; a brain without MCP research tools
 * never trips the first trigger. The word lists are DATA in both directions — a brain
 * working in another language replaces them without touching this file.
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
  // A verification CLAIM needs BOTH halves in the same text block. Either list alone is
  // far too common in ordinary reporting; their conjunction is what marks "something was
  // just established as true and nobody has written it down".
  // English only HERE, on purpose: this repo is English-only, and a word list is data,
  // not code. A brain that answers in another language ships its own lists in
  // `.claude/rules/recall-tools.json` — and because config REPLACES rather than extends,
  // such a brain lists both languages there. An instance that never sets them keeps
  // these defaults and simply never trips on non-English text.
  verifyThreshold: 2,
  verifyVerbs: ['\\b(verified|confirmed|reproduced|measured|proven|proved)\\b'],
  verifyObjects: [
    '\\b(mechanism|syntax|root cause|behaviou?r|live|end-to-end|works now|it works)\\b',
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
    verifyThreshold: Number.isFinite(cfg.verifyThreshold)
      ? cfg.verifyThreshold : DEFAULTS.verifyThreshold,
    verifyVerbs: rx(cfg.verifyVerbs, DEFAULTS.verifyVerbs),
    verifyObjects: rx(cfg.verifyObjects, DEFAULTS.verifyObjects),
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
      if (b.type === 'text' && typeof b.text === 'string') {
        // Both halves must meet in the same block — see the header note on the AND.
        if (cfg.verifyVerbs.some((r) => r.test(b.text))
            && cfg.verifyObjects.some((r) => r.test(b.text))) {
          events.push({ claim: b.text.slice(0, 90).replace(/\s+/g, ' ').trim() });
        }
        continue;
      }
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

  let research = 0, claims = 0, persisted = 0, firstSignal = -1, lastGate = -1;
  const tools = new Map();
  const claimTexts = [];
  events.forEach((e, i) => {
    if (e.research) {
      research += 1;
      if (firstSignal < 0) firstSignal = i;
      tools.set(e.research, (tools.get(e.research) || 0) + 1);
    }
    if (e.claim) {
      claims += 1;
      if (firstSignal < 0) firstSignal = i;
      claimTexts.push(e.claim);
    }
    if (e.gate) lastGate = i;
  });
  // Persistence only counts AFTER the first signal — a memory note written before the
  // reading (or the claim) is not a carrier for what came after it.
  if (firstSignal >= 0) {
    for (let i = firstSignal + 1; i < events.length; i++) if (events[i].persist) persisted += 1;
  }
  let turnsSinceGate = Infinity, signalsSinceGate = research + claims;
  if (lastGate >= 0) {
    turnsSinceGate = 0; signalsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) {
      if (events[i].boundary) turnsSinceGate += 1;
      if (events[i].research || events[i].claim) signalsSinceGate += 1;
    }
  }
  const top = [...tools.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4)
    .map(([n, c]) => `${n.replace(/^mcp__[^_]+__/, '')}×${c}`);
  return {
    research, claims, persisted, top, claimTexts: claimTexts.slice(-2),
    quiet: turnsSinceGate < COOLDOWN_TURNS, signalsSinceGate,
  };
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

  const byResearch = seen.research >= cfg.threshold;
  const byClaim = seen.claims >= cfg.verifyThreshold;
  const due = (byResearch || byClaim) && seen.persisted === 0 && seen.signalsSinceGate > 0;
  if (RECORD) {
    if (seen.research > 0 || seen.claims > 0) {
      console.log(JSON.stringify({ record: [{
        research: seen.research, claims: seen.claims, persisted: seen.persisted,
        threshold: cfg.threshold, verifyThreshold: cfg.verifyThreshold,
        trigger: byClaim ? (byResearch ? 'both' : 'claim') : (byResearch ? 'research' : 'none'),
        would_block: due && !seen.quiet, tools: seen.top, claims_seen: seen.claimTexts,
      }] }));
    }
    return allow();
  }
  if (!due || seen.quiet) return allow();

  // Name the trigger that actually fired — a gate that reports the wrong reason gets
  // dismissed as noise even when it is right.
  const what = byClaim
    ? `established ${seen.claims} verified finding(s) — last: "${seen.claimTexts.slice(-1)[0] || ''}"`
      + (byResearch ? ` and read a live system ${seen.research}×` : '')
    : `read a live system ${seen.research}× (${seen.top.join(', ')})`;
  console.log(JSON.stringify({
    decision: 'block',
    reason:
      `RECALL-GATE — routine, not an error. This session ${what} and persisted nothing since. ` +
      'What of it must nobody work out again tomorrow? Give it a carrier now — memory file, ' +
      'ledger entry, suite reference, shared-memory — or answer "⚙ nothing reusable". ' +
      '(Before the NEXT live read: scripts/transcript-recall.py <keyword> finds what earlier ' +
      'sessions already read.)',
  }));
  process.exit(0);
});

process.stdin.resume();
