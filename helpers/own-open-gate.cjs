#!/usr/bin/env node
/**
 * Stop hook: a reply that ends on the AI's OWN open items is not a turn end — in the INTERACTIVE mode.
 *
 * Incident (operator, 2026-10-25, the macOS instance): a closing message ended with "Still open from me: reset
 * Art-Net, remove the TD helper entry, a correction PR. I need nothing from you for it." — and the turn ended. No
 * question, no hand step, no waiter, every item reversible own terrain. The operator: "why do you stop when things
 * are still open on your own side?" The core stoppen-gate knows three shapes (closing question, handoff,
 * announcement); a bare LIST of own open items is none of them. This gate is that fourth shape.
 *
 * Instance alpha 2026-10-25 .. 2026-11-10, evaluated over 44 real blocks in 28 sessions (operator decision
 * 2026-11-10, question tool: port it changed): 17 right, 25 noise, 2 unclear. The port carries the three changes
 * the noise asked for:
 *   - INTERACTIVE only: in the autonomous mode autonomous-idle-gate judges the state (a turn ends only on a
 *     measured BLOCKED / POOL EMPTY / LIST EMPTY line); 15 noise blocks were replies carrying exactly that form.
 *   - a named end line (`BLOCKED:`, `POOL EMPTY:`, `LIST EMPTY:`, `HAND STEP:`) ends the turn, the same lines the
 *     idle gate reads; 7 noise blocks were hand steps for the operator in free words.
 *   - a negated hit ("my open items: none") is no hit (2 noise blocks).
 *
 * Mechanics (same transcript reading as stoppen-gate.cjs): the final assistant text of the running turn, quotes
 * and code stripped. Block ONCE per turn, with a cooldown of three operator turns, when an own-open phrase matches
 * (English built-ins here; other languages are data: `.claude/rules/stop-patterns.json` key `own_open_patterns`,
 * negations `own_open_negation_patterns`, hand steps `hand_step_patterns`), the turn asked nothing through the
 * question tool, no waiter covers the item's own sentence, and the reply hands the operator no step.
 * Fixture: scripts/test-own-open-gate.sh.
 */
const fs = require('fs');
const path = require('path');
const { isNotification, isPeerMessage, isTranscriptRecord } = require('./turn-kind.cjs');
const { ownEcho, declare } = require('./stop-echo.cjs');
const { closeOpenEnds } = require('./close-stamp.cjs');
const { autonomousMode } = require('./autonomous-mode.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
let OWN_ECHO = /OWN-OPEN-GATE/;
// Cooldown of 3 operator turns after a block (same as the core stoppen-gate): an unconditional
// trigger becomes ritual and takes the working checks down with it (brain-check friction rule).
const COOLDOWN_TURNS = 3;
const TAIL_BYTES = 4 * 1024 * 1024;
const QUESTION_TOOL = 'AskUserQuestion';
const NO_TOOL_LINE = /^[ \t>*_-]*⚙️?\s*no question tool:/imu;

// ENGINE built-ins — English only; every other language is data (stop-patterns.json).
const BUILTIN_OWN_OPEN = [
  '\\b(still |yet )?open (on|from) my (side|end)\\b',
  '\\bmy (own )?open (items|points|ends|list)\\b',
  '\\b(on|from) my side,? (still )?(open|to do|pending)\\b',
  '\\bi still (have|need) to\\b',
  '\\bleft (for|with) me\\b',
  '\\bnext (up )?for me\\b',
  '\\bi (still )?owe\\b',
  '\\bopen for me\\b',
  // self-deferral of an own item to the next train/pin (operator 2026-11-05: "nothing comes too late")
  '\\b(is|comes|would be) too late for (the|this) (train|release|pin|tag|beta)\\b',
  '\\b(goes|ships|lands) (only )?(with|in) the next (pin|train|release|tag|beta)\\b',
];
// A reply that hands the OPERATOR a step is a named turn end (core ASK OR ACT, named cases).
const BUILTIN_HAND_STEP = [
  '\\b(your|operator\'?s) hand\\b',
  '\\bhand step\\b',
  '\\b(for|with) you:',
  '\\byou (need|have) to\\b',
  '\\bnext step for you\\b',
  '\\bneeded from you\\b',
];
// The named turn ends the idle gate reads (a measured BLOCKED / POOL EMPTY / LIST EMPTY line, a hand step).
const NAMED_END = /^[ \t>*_-]*(?:\*\*)?(BLOCKED|POOL EMPTY|LIST EMPTY|HAND STEP)(?:\*\*)?:\s*\S/m;
// A hit followed by a negation ("my open items: none") is no hit.
const BUILTIN_NEGATION = ['^\\W{0,4}(none|nothing|no more|no open)\\b'];

function loadPatterns(cwd, key, builtins) {
  const patterns = [...builtins];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'stop-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra[key])) {
      for (const s of extra[key]) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(patterns.join('|'), 'giu');
}

const WAITER_END = /<tool-use-id>(toolu_[A-Za-z0-9]+)<\/tool-use-id>[\s\S]{0,800}?<status>(completed|failed|killed|cancelled|stopped|expired|timeout)/g;
const ASYNC_LAUNCH = /\bAsync agent launched\b|\bworking in the background\b/;

function isWaiter(b) {
  if (b.type !== 'tool_use') return false;
  if (b.name === 'Monitor' || b.name === 'Workflow') return true;
  const bg = b.input && b.input.run_in_background;
  return (b.name === 'Bash' || b.name === 'Agent') && (bg === true || bg === 'true');
}

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((b) => (typeof b.text === 'string' ? b.text
    : typeof b.content === 'string' ? b.content
    : Array.isArray(b.content) ? textOf(b.content) : '')).join('\n');
}

function asyncLaunches(content) {
  if (!Array.isArray(content)) return [];
  return content
    .filter((b) => b.type === 'tool_result' && b.tool_use_id && ASYNC_LAUNCH.test(textOf([b])))
    .map((b) => b.tool_use_id);
}

function stripQuoted(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”]*[“”]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/‹[^›]*›|«[^»]*»/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

/** Final assistant text of the running turn, waiter state, question-tool use, own blocks this turn. */
function analyze(transcriptPath) {
  const size = fs.statSync(transcriptPath).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(transcriptPath, 'r');
  let lines;
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
  } finally {
    fs.closeSync(fd);
  }
  const events = [];
  const armed = new Set();
  const ended = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      for (const m of textOf(msg.content).matchAll(WAITER_END)) ended.add(m[1]);
      for (const id of asyncLaunches(msg.content)) armed.add(id);
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (isWaiter(b)) armed.add(b.id);
        if (b.type === 'tool_use' && b.name === 'ScheduleWakeup') events.push({ wake: true });
        // The question counts only as the turn's END (no text after it): measured 2026-10-29, a question at the
        // START of the turn ("shall I handle the open items?" -> "yes, all autonomous") exempted the closing
        // report that listed own open items, and the session stopped.
        if (b.type === 'tool_use' && b.name === QUESTION_TOOL) events.push({ ask: true });
        if (b.type === 'text' && b.text) events.push({ said: true });
      }
    }
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      if (!isNotification(msg.content) && !isPeerMessage(d)) events.push({ boundary: true, ts: d.timestamp || '' });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b && b.type === 'tool_use' && b.input && typeof b.input.command === 'string') events.push({ cmd: b.input.command });
      }
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) events.push({ text: b.text });
        if (b.type === 'text' && b.text && /```/.test(b.text)) events.push({ code: true });
      }
    }
  }
  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const turn = events.slice(last);
  let finalText = '';
  for (const e of turn) if (e.text) finalText = e.text;
  const waiting = [...armed].some((id) => !ended.has(id)) || turn.some((e) => e.wake);
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
    finalText,
    waiting,
    asked: turn.findLastIndex((e) => e.ask) > turn.findLastIndex((e) => e.said),
    gatesThisTurn: turn.filter((e) => e.gate).length,
    quiet: turnsSinceGate < COOLDOWN_TURNS,
    since: (turn[0] && turn[0].ts) || '',
    calls: turn.filter((e) => e.cmd).map((e) => ({ cmd: e.cmd })),
  };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);
  if (!input.transcript_path) return allow();
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();

  let seen;
  const hits = [];
  try {
    seen = analyze(input.transcript_path);
    if (!seen.finalText) return allow();
    // A session close ends the turn (2026-11-01, class sweep of the idle gate's fix, core #272): its open
    // items stand as open ends in the session log; the close stamp of THIS turn is the checkable carrier.
    if (closeOpenEnds(cwd, { sessionId: input.session_id, since: seen.since, calls: seen.calls }) !== null) return allow();
    // Held once already in this turn: the re-issue passes, whatever it says (the operator decides the rest).
    if (seen.gatesThisTurn >= 1) {
      return allow();
    }
    if (seen.quiet) return allow(); // blocked within the last three operator turns: cooldown
    if (seen.asked || NO_TOOL_LINE.test(seen.finalText)) return allow();
    if (NAMED_END.test(seen.finalText)) return allow();
    // autonomous: autonomous-idle-gate judges the state; this gate only reads the interactive mode
    try { if (autonomousMode(input.transcript_path, cwd)) return allow(); } catch (e) { /* unreadable: go on */ }
    const plain = stripQuoted(seen.finalText);
    // A hand step for the operator anywhere in the reply, or a command block, is a named turn end.
    const hand = loadPatterns(cwd, 'hand_step_patterns', BUILTIN_HAND_STEP);
    if (hand.test(plain) || /```/.test(seen.finalText)) return allow();
    const rx = loadPatterns(cwd, 'own_open_patterns', BUILTIN_OWN_OPEN);
    // The WHOLE reply, not its tail (2026-10-26, class of core #136: an own item in point 1 of a long
    // status reply stood ~1000 characters before the end; the session stood still 90 minutes). And a
    // running waiter excuses only the item whose own sentence says it waits (sobald/wenn/…), not every
    // item of the reply — the same fix the core stoppen-gate got on 2026-10-18.
    const cond = loadPatterns(cwd, 'announce_condition_patterns', ['\\b(once|when|after|until|as soon as)\\b']);
    const neg = loadPatterns(cwd, 'own_open_negation_patterns', BUILTIN_NEGATION);
    for (const m of plain.matchAll(rx)) {
      if (seen.waiting) {
        const s = plain.slice(Math.max(0, plain.lastIndexOf('.', m.index) + 1), (plain.indexOf('.', m.index + m[0].length) + 1) || plain.length);
        cond.lastIndex = 0;
        if (cond.test(s)) continue;
      }
      neg.lastIndex = 0;
      if (neg.test(plain.slice(m.index + m[0].length, m.index + m[0].length + 24))) continue;
      const norm = m[0].trim().replace(/\s+/g, ' ');
      if (!hits.includes(norm)) hits.push(norm);
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (!hits.length) return allow();
  console.log(JSON.stringify(declare({
    decision: 'block',
    reason:
      'OWN-OPEN-GATE (the reply ends on your own open items while nothing is asked, handed over or armed).\n' +
      `Own items named: ${hits.slice(0, 3).join(' · ')}\n` +
      'Reversible own work does not wait for a turn end: DO the items now (tool calls in this turn), or arm the ' +
      'waiter they depend on, or name the blocker (whose word, which resource) in the reply. If a hand step for ' +
      'the operator or a question through the question tool is what ends this turn, say so and re-issue — ' +
      'the re-issue passes.',
  }, input)));
  process.exit(0);
});
