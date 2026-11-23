#!/usr/bin/env node
/**
 * Stop check + history replay: a hand step the reply gives the operator must be one only their hand can take, with
 * what they have at hand.
 *
 * Two checks, every word, command, path and window as instance data (`.claude/rules/hand-steps.json`, template in
 * `templates/rules-instance/hand-steps.json`; no file = inert):
 *   self_run_handed_over  a code block in a reply of the turn runs a command the AI runs itself (`self_run.commands`),
 *                         while its target is attached (`self_run.device_globs`; the replay reports every case).
 *                         Measured 2026-10-28 on the macOS instance: the operator, translated, "you flash, why should
 *                         I?" — the reply had handed over a flash command block for a board on the AI's own USB port.
 *   not_at_hand           an instruction line of a reply (a list item, or a sentence with an `addressed_words` word)
 *                         names something the operator does not have right now (`not_at_hand.items`: words, a
 *                         since/until window of days, why). A line that says the step waits (`not_at_hand.waits`) passes.
 *                         Measured the same day: "measure 3V3 against GND with the multimeter" while the operator had
 *                         said twice that he was away from the lab without one; the state stood in memory, nothing
 *                         compared an instruction against it.
 * Ported 2026-11-17 from an instance alpha (in use since 2026-10-28; its rule-in-prose check is carried by
 * commitment-carrier-gate.cjs `proseRules` since core #173, and is not ported). Replay 2026-10-28 over 393 transcripts:
 * self_run_handed_over 6 hits.
 *
 * Hook: holds the turn end ONCE (a re-issue after its own block passes). Replay:
 * `node hand-step-gate.cjs --replay [transcript dir] [--since YYYY-MM-DD]` — every past turn through the same checks,
 * one line per hit; rc 1 when anything was found. Log: `.claude-state/hand-step-gate.jsonl`.
 * Fixture: scripts/test-hand-step-gate.cjs.
 */
'use strict';
const fs = require('fs');
const { exit: hookExit } = require('./hook-exit.cjs');   // not process.exit: it hung at Node shutdown (2026-11-23)
const os = require('os');
const path = require('path');
const { isNotification, isPeerMessage, isTranscriptRecord, isSkillExpansion, operatorPrompt, projectTranscriptDir } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');

const MARKER = 'HAND-STEP-GATE';
const HOOK_ECHO = /^Stop hook feedback:/;
const rx = (list) => (Array.isArray(list) ? list : []).filter((p) => typeof p === 'string' && p).map((p) => new RegExp(p, 'iu'));
const home = (p) => String(p).replace(/^~(?=[/\\])/, os.homedir());

function root(input) { return process.env.CLAUDE_PROJECT_DIR || (input && input.cwd) || process.cwd(); }

/** The brain's data, or null when it has none. */
function loadData(dir) {
  const file = process.env.HAND_STEP_DATA || path.join(dir, '.claude', 'rules', 'hand-steps.json');
  let d;
  try { d = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return null; }
  const s = d.self_run || {}, n = d.not_at_hand || {};
  return {
    commands: rx(s.commands), globs: Array.isArray(s.device_globs) ? s.device_globs : [], procedure: s.procedure || '',
    addressed: rx(d.addressed_words && d.addressed_words.length ? d.addressed_words : ['\\b(you|your|please)\\b']),
    away: (Array.isArray(n.items) ? n.items : []).map((it) => ({ words: rx(it.words), since: it.since || '0000', until: it.until || '9999', why: it.why || '' })),
    waits: rx(n.waits),
  };
}

/** Split a transcript into turns: [{start, texts:[], echoes:[]}]. */
function turns(file) {
  const out = [];
  let cur = null;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    if (!isTranscriptRecord(d) && d.type !== 'attachment') continue;
    const op = isSkillExpansion(d) || isPeerMessage(d) ? null : operatorPrompt(d);
    // a Stop hook's echo is a notification to turn-kind (no new turn) - read it as the echo first
    if (op !== null && HOOK_ECHO.test(op)) { if (cur) cur.echoes.push(op); continue; }
    if (op !== null && !isNotification(op)) {
      cur = { start: d.timestamp || '', texts: [], echoes: [] };
      out.push(cur);
      continue;
    }
    const m = d.message;
    if (!cur || !m || m.role !== 'assistant' || !Array.isArray(m.content)) continue;
    for (const b of m.content) if (b && b.type === 'text' && b.text) cur.texts.push(b.text);
  }
  return out;
}

/** Instruction lines: a list item, or a sentence addressed to the operator. Quoted or code text is a mention. */
function instructionLines(text, D) {
  const bare = String(text).replace(/```[\s\S]*?```/g, ' ').replace(/„[^“”]*[“”]|“[^”]*”|"[^"]*"|`[^`]*`/g, ' ');
  const out = [];
  for (const line of bare.split('\n')) {
    if (/^\s*(\d+[.)]|[-*•])\s+/.test(line)) { out.push(line); continue; }
    for (const s of line.split(/(?<=[.!?])\s+/)) if (D.addressed.some((w) => w.test(s))) out.push(s);
  }
  return out;
}

function devicePresent(D) {
  if (process.env.HAND_STEP_DEVICE !== undefined) return process.env.HAND_STEP_DEVICE === '1';
  for (const g of D.globs) {
    const dir = path.dirname(home(g)), pre = path.basename(g).replace(/\*.*$/, '');
    try { if (fs.readdirSync(dir).some((n) => n.startsWith(pre))) return true; } catch (e) { /* no dir */ }
  }
  return false;
}

/** Hits of one turn: [{check, detail}]. `probe` = ask whether a device is attached (hook mode). */
function check(turn, D, probe) {
  const hits = [];
  const day = (turn.start || '').slice(0, 10) || new Date().toISOString().slice(0, 10);
  for (const it of D.away) {
    if (day < it.since || day > it.until) continue;
    for (const l of turn.texts.flatMap((t) => instructionLines(t, D))) {
      if (D.waits.some((w) => w.test(l))) continue;
      if (it.words.some((w) => w.test(l))) { hits.push({ check: 'not_at_hand', detail: `${l.trim().slice(0, 110)} — ${it.why}` }); break; }
    }
  }
  // every text of the turn: a reply held by another Stop check is a closing reply too (measured 2026-10-28)
  const blocks = turn.texts.join('\n').match(/```[\s\S]*?```/g) || [];
  const cmd = blocks.find((b) => D.commands.some((p) => p.test(b)));
  if (cmd && (!probe || devicePresent(D))) {
    const l = cmd.split('\n').find((x) => D.commands.some((p) => p.test(x))) || '';
    hits.push({ check: 'self_run_handed_over', detail: l.trim().slice(0, 110) });
  }
  return hits;
}

function logLine(dir, o) {
  try {
    const st = path.join(dir, '.claude-state');
    fs.mkdirSync(st, { recursive: true });
    fs.appendFileSync(path.join(st, 'hand-step-gate.jsonl'), JSON.stringify({ at: new Date().toISOString(), ...o }) + '\n');
  } catch (e) { /* logging never blocks */ }
}

function replay(args) {
  const dir = root();
  const D = loadData(dir);
  if (!D) { console.log('hand-step-gate: no .claude/rules/hand-steps.json - nothing to replay'); hookExit(0); }
  const i = args.indexOf('--since');
  const since = i >= 0 ? args[i + 1] : '';
  const dirArg = args.find((a, k) => !a.startsWith('--') && args[k - 1] !== '--since');
  const tdir = dirArg ? home(dirArg) : projectTranscriptDir(dir);
  const files = fs.readdirSync(tdir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(tdir, f));
  const count = { self_run_handed_over: 0, not_at_hand: 0 };
  for (const f of files) {
    let ts;
    try { ts = turns(f); } catch (e) { continue; }
    for (const t of ts) {
      if (since && t.start && t.start.slice(0, 10) < since) continue;
      for (const h of check(t, D, false)) {
        count[h.check]++;
        console.log([t.start.slice(0, 16), path.basename(f, '.jsonl').slice(0, 8), h.check, h.detail].join(' | '));
      }
    }
  }
  console.log(`replay: ${files.length} transcripts · self_run_handed_over ${count.self_run_handed_over} · not_at_hand ${count.not_at_hand}`);
  hookExit(count.self_run_handed_over + count.not_at_hand ? 1 : 0);
}

function reason(hits, D) {
  const how = D.procedure ? ` (procedure: ${D.procedure})` : '';
  return `${MARKER}: a hand step for the operator that is not theirs to take:\n` + hits.map((h) => (h.check === 'not_at_hand'
    ? `  - it needs something the operator does not have right now: ${h.detail}\n    find a way with what is at hand, or say the step waits until then`
    : `  - a command block for a command you run yourself: ${h.detail}\n    its target is attached: run it yourself${how}; hand over only what needs the operator's hand`)).join('\n');
}

module.exports = { turns, check, loadData, instructionLines };

if (require.main === module) {
  if (process.argv.includes('--replay')) replay(process.argv.slice(2).filter((a) => a !== '--replay'));
  else {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { data += c; });
    process.stdin.on('end', () => {
      let input = {};
      try { input = JSON.parse(data); } catch (e) { hookExit(0); }
      if (!input.transcript_path) hookExit(0);
      try {
        const dir = root(input);
        const D = loadData(dir);
        if (!D) hookExit(0);
        const ts = turns(input.transcript_path);
        const turn = ts[ts.length - 1];
        if (!turn) hookExit(0);
        const echo = ownEcho(input, new RegExp(MARKER));
        if (turn.echoes.some((e) => echo.test(e))) { logLine(dir, { session: input.session_id, decision: 'pass-after-block' }); hookExit(0); }
        const hits = check(turn, D, true);
        if (!hits.length) hookExit(0);
        logLine(dir, { session: input.session_id, decision: 'block', hits });
        console.log(JSON.stringify(declare({ decision: 'block', reason: reason(hits, D) }, input)));
      } catch (e) { hookExit(0); }   // an unreadable transcript never blocks
    });
  }
}
