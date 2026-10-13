#!/usr/bin/env node
/**
 * Stop hook: stopping is the exception, not the rhythm (T1 item 3).
 *
 * The anti-pattern (operator order 2026-08-08): a reply that ENDS by handing
 * the next step back as a question ("Shall I ...?", "What should I continue with?")
 * when the three-condition test does not hold. Stopping is right ONLY when all
 * three hold, AND-linked: (1) it is a DECISION, not a work step; (2) it blocks
 * the work NOW; (3) only the operator can make it (goal/money/hardware/risk).
 * Everything answerable by measurement, docs or rules is not an operator
 * decision — do the work, report after.
 *
 * Mechanics: looks ONLY at the tail of the LAST assistant text of the turn —
 * a closing question is the anti-pattern, a rhetorical question mid-text is
 * not. On a match => ONE block asking to apply the three-condition test: if it
 * genuinely holds, re-issue unchanged (stop_hook_active silences the second
 * pass); otherwise do the work now.
 *
 * Frequency design: fires only on a hit; cooldown of 3 operator turns (higher
 * than time-gate — real operator decisions are WANTED, a gate that fires on
 * every legitimate question becomes wallpaper, G-1). Quotes/code stripped, so
 * discussing the rule does not trigger it.
 *
 * Language layering (language-agnostic contract, operator order 2026-08-19):
 * the engine's built-ins are ENGLISH; every further language is DATA, not code —
 * instance file .claude/rules/stop-patterns.json: {"patterns": ["<regex>", ...]},
 * merged in. German, Czech, French, Spanish all work the same way through that
 * file; no language is a special case in this engine. A CLASS fix (a new question
 * or handoff shape) lands in the English built-ins first, a language pack only ever
 * adds a language. The German pack that used to ship inline here moved out (T3);
 * scripts/test-stoppen-gate.sh writes it as an instance file and is the reference
 * copy. scripts/english-only.py holds the layering: this file is no longer exempt,
 * so German that creeps back into the engine fails CI.
 */
const fs = require('fs');
const path = require('path');
// A harness notification (task done, watcher event) is not an operator turn — it must not
// count down this gate's cooldown (2026-10-07; one definition: turn-kind.cjs).
const { isNotification } = require('./turn-kind.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /STOPPEN-GATE/;
const COOLDOWN_TURNS = 3;
const TAIL_BYTES = 4 * 1024 * 1024;
const TAIL_CHARS = 400; // only the closing stretch of the final text counts

// Permission-handback questions. Deliberately NOT matched: bare "GO?" (release
// gate), option questions without a first-person handback ("which channel?"), AskUserQuestion.
// ENGINE built-ins — English only (language-agnostic contract, header above).
const BUILTIN_PATTERNS = [
  // Shape 1: the closing QUESTION. The obvious form, and the only one this gate saw
  // for its first three weeks.
  '\\bshall i\\b[^?\\n]{0,140}\\?',
  '\\bdo you want me to\\b[^?\\n]{0,140}\\?',
  '\\bwant me to (proceed|continue|go ahead)\\b[^?\\n]{0,80}\\?',
  '\\bshould i (proceed|continue|go ahead|start)\\b[^?\\n]{0,80}\\?',

  // Shape 2: the HANDOFF, which asks nothing and stops just as hard. Measured on a
  // live instance 2026-08-31 — four deferrals in one day, none of them a question,
  // so every pattern above missed all four while the three-condition test said the
  // work belonged to the agent: "yours to merge or to shred", "tell me which side
  // takes it", "let me know if you want the fixture first", "the fix sits with the
  // other instance". A question mark is a FORM; parking work on someone else is the
  // FUNCTION, and only the function is the anti-pattern. Deliberately no '?' here.
  '\\byours to (merge|shred|take|decide|do)\\b',
  '\\btell me (which|if|whether)\\b[^.\\n]{0,80}[.!]',
  '\\blet me know\\b[^.\\n]{0,80}[.!]',
  '\\byour call\\b[^.\\n]{0,40}[.!]',
  '\\bsay the word\\b[^.\\n]{0,40}[.!]',
  '\\b(sits|rests|is) with (you|them|the other (instance|session))\\b',
  '\\bwaiting (on|for) (you|your (word|answer|reply|go-ahead))\\b',
];

// Shape 3: the ANNOUNCEMENT. The reply says the work goes on ("doing that now", "next I
// will …") and the turn ends — nothing runs, nobody is waited for. Measured 2026-10-11 on a
// live instance, four times in one session, the operator: "you work on your own, or did you
// stop again?" and "you always stop. the same failure class again". Neither a question nor
// a handoff, so shapes 1 and 2 missed every one. Exempt: a background waiter that has not
// reported its end yet (Bash or Agent run_in_background, Monitor, Workflow, ScheduleWakeup) — then the
// announcement waits for something real. Data key: `announce_patterns`.
const BUILTIN_ANNOUNCE = [
  "\\b(now|next),? i(?:'ll| will)\\b",
  "\\bi(?:'ll| will) (now|next)\\b",
  "\\bi(?:'ll| will) (continue|keep going|move on)\\b",
  '\\b(continuing|moving on) (with|to)\\b',
  '\\b(doing|on) (it|that|this) now\\b',
];

function loadPatterns(cwd, key = 'patterns', builtins = BUILTIN_PATTERNS) {
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

function isWaiter(b) {
  if (b.type !== 'tool_use') return false;
  // A Workflow always runs in the background; an Agent only when started so.
  if (b.name === 'Monitor' || b.name === 'Workflow') return true;
  // The flag arrives as boolean true (Bash) or as the STRING "true" (Agent — measured on
  // Claude Code 2.1.295 transcripts, 5 of 6 calls); a strict === true missed every one.
  const bg = b.input && b.input.run_in_background;
  return (b.name === 'Bash' || b.name === 'Agent') && (bg === true || bg === 'true');
}

// Since Claude Code 2.1.296 the Agent tool carries no run_in_background flag and ALWAYS runs
// async (measured 2026-10-12: the launch result says so, and a task notification with the
// tool-use id follows). The harness's own launch text is the proof — an older sync Agent
// returns its report as the tool result instead and stays a foreground call.
const ASYNC_LAUNCH = /\bAsync agent launched\b|\bworking in the background\b/;

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

/** Last assistant text of the running turn + cooldown state. */
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
    if (!msg) continue;
    if (msg.role === 'user') {
      for (const m of textOf(msg.content).matchAll(WAITER_END)) ended.add(m[1]);
      for (const id of asyncLaunches(msg.content)) armed.add(id);
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (isWaiter(b)) armed.add(b.id);
        // A wakeup never reports an end; it counts only inside the turn that set it.
        if (b.type === 'tool_use' && b.name === 'ScheduleWakeup') events.push({ wake: true });
      }
    }
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      if (!isNotification(msg.content)) events.push({ boundary: true });
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (b.type === 'text' && b.text) events.push({ text: b.text });
      }
    }
  }

  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  let finalText = '';
  for (let i = last; i < events.length; i++) if (events[i].text) finalText = events[i].text;

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  const waiting = [...armed].some((id) => !ended.has(id))
    || events.slice(last).some((e) => e.wake);
  return { finalText, quiet: turnsSinceGate < COOLDOWN_TURNS, waiting };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let hits = [];
  let announced = [];
  const uniq = (found, into) => {
    for (const h of found || []) {
      const norm = h.trim().replace(/\s+/g, ' ');
      if (!into.includes(norm)) into.push(norm);
    }
  };
  try {
    const seen = analyze(input.transcriptPath || input.transcript_path);
    if (seen.quiet) return allow();
    if (!seen.finalText) return allow();
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const tail = stripQuoted(seen.finalText).slice(-TAIL_CHARS);
    uniq(tail.match(loadPatterns(cwd)), hits);
    if (!hits.length && !seen.waiting) {
      uniq(tail.match(loadPatterns(cwd, 'announce_patterns', BUILTIN_ANNOUNCE)), announced);
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (announced.length) {
    console.log(JSON.stringify({
      decision: 'block',
      reason:
        'STOPPEN-GATE (an announcement is not an action — the turn ends and nothing runs).\n' +
        `Announced in this reply: ${announced.slice(0, 3).join(' · ')}\n` +
        'No background waiter is running. Either DO the announced step now (tool call in this ' +
        'turn), or arm the waiter it depends on, or state plainly who or what you wait for. ' +
        'If that is already true, re-issue the reply unchanged — it will pass.',
    }));
    process.exit(0);
  }
  if (hits.length === 0) return allow();
  // The first reply after a session start ASKS on purpose (operator order 2026-10-07):
  // "n items I can handle — shall I?" is the one OK the agent must get before it starts on
  // something the session was not opened for. That turn belongs to open-items-gate.
  // Same class, wider: a question a RULE orders ("brain-scan DUE — ask the operator") is the
  // rule being followed. Measured 2026-10-09: this gate blocked exactly that question.
  try {
    const oi = require('./open-items-gate.cjs');
    if (oi.firstTurnOwnsQuestion(input.transcript_path)) return allow();
    const norm = (s) => s.toLowerCase().replace(/[-_]+/g, ' ');
    const tailText = norm(stripQuoted(analyze(input.transcript_path).finalText).slice(-TAIL_CHARS));
    if (oi.mandatedTopics(input.transcript_path).some((t) => tailText.includes(norm(t)))) return allow();
  } catch (e) { /* no sibling gate — judge as before */ }

  console.log(JSON.stringify({
    decision: 'block',
    reason:
      'STOPPEN-GATE (stopping is the exception — a closing permission question is a disguised stop).\n' +
      `Closing question in this reply: ${hits.slice(0, 3).join(' · ')}\n` +
      'Apply the three-condition test, AND-linked: (1) DECISION, not a work step · ' +
      '(2) blocks the work NOW · (3) only the operator can make it (his goal, money, ' +
      'hardware, risk). All three hold => re-issue the reply unchanged — it will pass. ' +
      'Otherwise: the question is answerable by measurement, docs or rules — do the ' +
      'work now and report the result instead of asking.',
  }));
  process.exit(0);
});

process.stdin.resume();
