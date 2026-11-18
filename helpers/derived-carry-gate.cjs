#!/usr/bin/env node
/**
 * Stop hook: a claim once marked as derived stays marked until a measurement replaces it.
 *
 * The class (measured 2026-11-17 on the macOS instance, three cases in one day, one session): a sentence the AI
 * itself had marked as a conclusion ("I only infer that from ...") came back two replies later as a plain fact
 * ("the node ran on PoE at that port"); the operator corrected it, and the PoE state had never been read. The
 * other two cases of the day were the same shape one step earlier - a summary or a lab snapshot taken over without
 * its source. The evidence rule (thinking-protocol rule 0: report measured / derived / assumed apart) was prose;
 * nothing held a label across replies.
 *
 * What fires: in the running turn, a sentence WITHOUT a derived marker that repeats an earlier sentence of the
 * session WITH one - same anchor (a token with a digit or an inner capital: ether7, PoE, LumiNode, sw-foh) and at
 * least MIN_SHARED significant words in common - while no tool call since that earlier sentence carried the anchor
 * in its input (a read of the thing would have replaced the conclusion with a measurement).
 * What stays silent: the repeat keeps a marker; a tool call touched the anchor in between; no shared anchor.
 *
 * Markers: English built-ins; every other language is DATA in `.claude/rules/derived-patterns.json`
 * ({"derived_markers": ["..."]}), missing file = English only.
 * Mode: shipped as a recorder in the stop-checks template (a brain turns it to block on its operator's word, like
 * the time gate). Frequency design: one hit per turn; the reason names both sentences.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { isNotification, isAgentOrigin, isTranscriptRecord } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');

const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 16 * 1024 * 1024;   // a derived claim can sit hours back: measured 2026-11-17, a 10.9 MB session, the source 6 MB before the end
const MIN_SHARED = 2;
const MAX_EARLIER = 400;   // newest marked sentences with an anchor that a repeat is held against
const BUDGET_MS = 3000;    // the stop hook limit is far above; past this the gate allows
const WRITES = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'SendMessage', 'AskUserQuestion', 'TodoWrite']);
const BUILTIN_MARKERS = [
  'derived', 'i infer', 'inferred', 'i conclude', 'concluded from', 'assumed', 'assumption', 'not measured',
  'unmeasured', 'presumably', 'probably', 'likely', 'not read', 'i guess', 'my guess',
];
const STOP = new Set(('that this with from have were they them then than there their which while where when what '
  + 'into onto over under also only just very more most some such each other about after before again does done '
  + 'here your yours ours will would could should been being')
  .split(' '));   // the instance's language adds `stop_words` in derived-patterns.json

function markers(cwd) {
  const list = [...BUILTIN_MARKERS];
  try {
    const d = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'derived-patterns.json'), 'utf8'));
    if (Array.isArray(d.derived_markers)) for (const m of d.derived_markers) if (typeof m === 'string' && m.trim()) list.push(m);
    if (Array.isArray(d.stop_words)) for (const w of d.stop_words) if (typeof w === 'string') STOP.add(w.toLowerCase());
  } catch (e) { /* English only */ }
  const esc = list.map((m) => m.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return new RegExp(`(?:^|[^\\p{L}])(?:${esc.join('|')})(?:[^\\p{L}]|$)`, 'iu');
}

/** Sentences of a text, code blocks and quotes removed (a quoted sentence is talk about it, not a claim). */
function sentences(text) {
  const clean = String(text || '')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/^\s*>.*$/gm, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/"[^"\n]*"/g, ' ');
  return clean.split(/(?<=[.!?])\s+|\n+/).map((s) => s.trim()).filter((s) => s.length >= 12);
}

/** Anchors: tokens with a digit or an inner capital (ether7, PoE, LumiNode, sw-foh2). Words: 5+ letters, no stopword. */
function tokens(s) {
  const raw = s.replace(/[`*_()[\]{},;:!?"'„“”]/g, ' ').split(/\s+/).map((t) => t.replace(/^[-.]+|[-.]+$/g, '')).filter(Boolean);
  const anchors = new Set();
  const words = new Set();
  for (const t of raw) {
    if (/\d/.test(t) && /\p{L}/u.test(t)) anchors.add(t.toLowerCase());
    else if (/^\p{L}+\p{Lu}\p{L}*$/u.test(t)) anchors.add(t.toLowerCase());   // inner capital: PoE, LumiNode
    const w = t.toLowerCase();
    if (/^\p{L}{5,}$/u.test(w) && !STOP.has(w)) words.add(w);
  }
  for (const a of anchors) words.add(a);
  return { anchors, words };
}

function readLines(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally { fs.closeSync(fd); }
}

/** Events in order: {text} of the assistant, {tool: lowercased input JSON}, {boundary} at an operator prompt. */
function events(file, ownRx) {
  const out = [];
  for (const line of readLines(file)) {
    if (!line.trim()) continue;
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) { if (ownRx.test(msg.content)) out.push({ echo: true }); continue; }
      if (!isNotification(msg.content) && !isAgentOrigin(d)) out.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) out.push({ text: b.text });
        // Name and input: a read of the port's PoE state names "poe" in the tool, the port in the input.
        // A write is no measurement (measured 2026-11-17: an Edit of a doc naming both anchors let the case pass).
        if (b.type === 'tool_use' && !WRITES.has(b.name)) out.push({ tool: `${b.name || ''} ${JSON.stringify(b.input || {})}`.toLowerCase() });
      }
    }
  }
  return out;
}

/** The first unmarked repeat in the running turn of an earlier derived sentence, or null. */
function judge(evs, markRx) {
  let last = -1;
  for (let i = evs.length - 1; i >= 0; i--) if (evs[i].boundary) { last = i; break; }
  if (last < 0) return null;
  for (let i = last + 1; i < evs.length; i++) if (evs[i].echo) return null;   // already said once this turn
  // Bounded (measured 2026-11-17: with the English markers alone a brain whose ledgers say "origin: derived" gave
  // thousands of marked sentences, and the read check per pair ran over every event - the gate hung past 120 s).
  // The newest MAX_EARLIER marked sentences, each once, with an anchor; tool indices once; a time budget, then allow.
  const started = Date.now();
  const seen = new Set();
  const earlier = [];   // {s, tok, at}, newest first
  for (let i = last - 1; i >= 0 && earlier.length < MAX_EARLIER; i--) {
    if (!evs[i].text) continue;
    for (const s of sentences(evs[i].text)) {
      if (!markRx.test(s) || seen.has(s)) continue;
      const tok = tokens(s);
      if (!tok.anchors.size) continue;
      seen.add(s);
      earlier.push({ s, tok, at: i });
    }
  }
  if (!earlier.length) return null;
  const tools = [];
  evs.forEach((x, i) => { if (x.tool) tools.push(i); });
  const readCache = new Map();
  const readBetween = (from, to, anchors) => {
    const key = `${from}|${to}|${anchors.join(',')}`;
    if (!readCache.has(key)) {
      // A read counts when ONE call carries EVERY shared anchor (measured 2026-11-17: port reads named ether7 but
      // never PoE; "any anchor" let the measured case pass).
      readCache.set(key, tools.some((k) => k > from && k < to && anchors.every((a) => evs[k].tool.includes(a))));
    }
    return readCache.get(key);
  };
  for (let i = last + 1; i < evs.length; i++) {
    if (!evs[i].text) continue;
    for (const s of sentences(evs[i].text)) {
      if (markRx.test(s)) continue;
      const t = tokens(s);
      if (!t.anchors.size) continue;
      for (const e of earlier) {
        if (Date.now() - started > BUDGET_MS) return null;   // fails open
        const anchors = [...e.tok.anchors].filter((a) => t.anchors.has(a));
        if (!anchors.length) continue;
        const shared = [...e.tok.words].filter((w) => t.words.has(w));
        // The repeat is mostly the earlier claim: at least MIN_SHARED words, and half of what the new sentence says.
        if (shared.length < MIN_SHARED || shared.length * 2 < t.words.size) continue;
        if (!readBetween(e.at, i, anchors)) return { earlier: e.s, now: s, anchors };
      }
    }
  }
  return null;
}

module.exports = { judge, tokens, sentences, markers, events };
if (require.main !== module) return;

// stdin is read to its END, never on a timer (premise-gate, measured 2026-08-20: a timer can fire before the data).
let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });
process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { process.exit(0); }
  if (input.stop_hook_active || !input.transcript_path) process.exit(0);
  const ownRx = ownEcho(input, /DERIVED-CARRY/);
  let hit = null;
  try {
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    hit = judge(events(input.transcript_path, ownRx), markers(cwd));
  } catch (e) { process.exit(0); }   // transcript unreadable - never block because of that
  if (!hit) process.exit(0);
  const cut = (x) => (x.length > 160 ? `${x.slice(0, 157)}...` : x);
  const reason = 'DERIVED-CARRY — a claim marked as derived comes back as a fact.\n'
    + `Earlier (marked): ${cut(hit.earlier)}\n`
    + `Now (unmarked):   ${cut(hit.now)}\n`
    + `No tool call since touched ${hit.anchors.join(', ')}. Measure it now, or keep the label in this reply `
    + '(thinking-protocol rule 0: measured / derived / assumed apart).';
  console.log(JSON.stringify(declare({ decision: 'block', reason }, input)));
  process.exit(0);
});
