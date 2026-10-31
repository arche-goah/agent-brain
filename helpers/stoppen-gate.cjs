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
 * genuinely holds, the decision goes to the operator through the question tool
 * (next paragraph); otherwise do the work now.
 *
 * A real operator decision is ASKED THROUGH THE QUESTION TOOL, not as closing prose
 * (operator order 2026-10-15 on the Windows instance, after a report had ended on a prose
 * list of things that needed his word and he answered "ask me a clean question, I do not
 * know what to tell you"; once the same session put three decisions to him through
 * AskUserQuestion he ordered it for every operator decision, anchored mechanically).
 * So: a turn that called AskUserQuestion passes this check whatever its closing prose
 * says, and so does a reply carrying a line that starts `⚙ no question tool:` (the harness
 * has no such tool — headless, a scheduled run). Without either, the re-issue of a closing
 * decision question NO LONGER passes by repetition: the second pass in the same turn blocks
 * again and names the tool. After two blocks in one turn the third pass is let through with
 * a loud systemMessage, so a genuinely stuck session is never locked. Until 2026-10-15
 * stop_hook_active silenced every re-issue here; it now silences only re-issues after
 * ANOTHER gate's block (this gate did not fire in the turn) and announcement re-issues.
 * Behind the stop dispatcher the re-issue reaches this gate only when its stop-checks.json
 * entry carries `"onReissue": "run"` (template default since the same change).
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
const { isNotification, isAgentOrigin, isTranscriptRecord } = require('./turn-kind.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
// Own echo: legacy token or, behind the dispatcher, the label line (stop-echo.cjs).
const { ownEcho, declare } = require('./stop-echo.cjs');
let OWN_ECHO = /STOPPEN-GATE/;
const COOLDOWN_TURNS = 3;
const TAIL_BYTES = 4 * 1024 * 1024;
const TAIL_CHARS = 400; // only the closing stretch of the final text counts
// The interactive question tool, and the one line that says it is missing here.
const QUESTION_TOOL = 'AskUserQuestion';
const NO_TOOL_LINE = /^[ \t>*_-]*⚙️?\s*no question tool:/imu;
// In the operator's autonomous run the question tool is the wrong way (skill autonomous-run,
// hard gate 7): the question goes into the instance's ledger and the prose report says where.
// The reply says so in one line; autonomous-mode.cjs tells the gate which way to demand.
const AUTONOMOUS_LINE = /^[ \t>*_-]*⚙️?\s*autonomous:/imu;
const { autonomousMode } = require('./autonomous-mode.cjs');
const MAX_TOOL_BLOCKS = 2; // blocks per turn before a prose decision question is let through

// Permission-handback questions. Deliberately NOT matched: bare "GO?" (release
// gate), option questions without a first-person handback ("which channel?"). A turn
// that called AskUserQuestion is not judged on its closing prose at all (header).
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
  // "I will build it next" — the verb before "next" (measured 2026-10-26, the class above missed it)
  "\\bi(?:'ll| will) [a-z]+(?: (?:it|this|that|them|the [a-z-]+))? (?:next|right away)\\b",
  "\\bi(?:'ll| will) (continue|keep going|move on)\\b",
  '\\b(continuing|moving on) (with|to)\\b',
  '\\b(doing|on) (it|that|this) now\\b',
];
// The waiter exemption holds only for an announcement that SAYS it waits ("once CI is green,
// I merge"). Measured 2026-10-18 on the macOS instance: "the review of #6 — I do that next"
// ended a turn; a CI watch and a shared-memory watch were running, so the gate let it pass —
// but the review depended on neither. Operator, translated: "do not say 'I'll do it' and then
// stop — just do it. failure class!!" Any running waiter excused any announcement. Now the
// sentence that carries the announcement must name its condition. Data key:
// `announce_condition_patterns` (an instance adds its language).
const BUILTIN_CONDITION = [
  '\\b(once|when|after|as soon as|until|if)\\b',
];

/** The sentence of `text` around the match at `index`. */
function sentenceAt(text, index) {
  const start = Math.max(text.lastIndexOf('. ', index), text.lastIndexOf('\n', index), -1) + 1;
  const ends = ['. ', '\n', '? ', '! '].map((s) => text.indexOf(s, index)).filter((i) => i >= 0);
  return text.slice(start, ends.length ? Math.min(...ends) : text.length);
}

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
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      for (const m of textOf(msg.content).matchAll(WAITER_END)) ended.add(m[1]);
      for (const id of asyncLaunches(msg.content)) armed.add(id);
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (isWaiter(b)) armed.add(b.id);
        // A wakeup never reports an end; it counts only inside the turn that set it.
        if (b.type === 'tool_use' && b.name === 'ScheduleWakeup') events.push({ wake: true });
        if (b.type === 'tool_use' && b.name === QUESTION_TOOL) events.push({ ask: true });
      }
    }
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (HOOK_ECHO.test(msg.content)) {
        if (OWN_ECHO.test(msg.content)) events.push({ gate: true });
        continue;
      }
      if (!isNotification(msg.content) && !isAgentOrigin(d)) events.push({ boundary: true });
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
  // The running turn only: did it call the question tool, and how often did THIS gate block
  // in it (the same echo count the cooldown reads, cut at the turn's start).
  const turn = events.slice(last);
  const asked = turn.some((e) => e.ask);
  const gatesThisTurn = turn.filter((e) => e.gate).length;
  return { finalText, quiet: turnsSinceGate < COOLDOWN_TURNS, waiting, asked, gatesThisTurn };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  OWN_ECHO = ownEcho(input, OWN_ECHO);

  if (!input.transcript_path) return allow();
  const reissue = !!input.stop_hook_active;

  let hits = [];
  let announced = [];
  let seen;
  const uniq = (found, into) => {
    for (const h of found || []) {
      const norm = h.trim().replace(/\s+/g, ' ');
      if (!into.includes(norm)) into.push(norm);
    }
  };
  try {
    seen = analyze(input.transcriptPath || input.transcript_path);
    // A re-issue after ANOTHER gate's block: its closing QUESTION passes as it always did (this gate
    // saw that question at the first stop), but its ANNOUNCEMENTS are judged — the answer to another
    // gate is new text (measured 2026-10-26: the answer to a verification/watcher block carried a new
    // "… I build it next" and passed unseen; the autonomous run stood still for 90 minutes).
    // A re-issue after this gate's OWN block keeps its re-issue rules below; its cooldown does not count.
    const ownBlocked = reissue && seen.gatesThisTurn > 0;
    const afterOther = reissue && !ownBlocked;
    if (!ownBlocked && seen.quiet) return allow();
    if (!seen.finalText) return allow();
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const tail = stripQuoted(seen.finalText).slice(-TAIL_CHARS);
    // Asked through the tool, or the tool is missing here and the reply says so: the closing
    // question is not judged. (An announcement still is — asking is not doing the work.)
    // The autonomous line counts only while the mode really holds — outside it, it is no way out.
    const filed = AUTONOMOUS_LINE.test(seen.finalText) && autonomousMode(input.transcript_path, cwd);
    if (!afterOther && !seen.asked && !NO_TOOL_LINE.test(seen.finalText) && !filed) {
      uniq(tail.match(loadPatterns(cwd)), hits);
    }
    if (!hits.length && !ownBlocked) {
      const rx = loadPatterns(cwd, 'announce_patterns', BUILTIN_ANNOUNCE);
      const cond = loadPatterns(cwd, 'announce_condition_patterns', BUILTIN_CONDITION);
      // The WHOLE final text, not its tail: an announcement in item 1 of a four-item status list
      // ends the turn just the same (measured 2026-10-26, macOS: "… I build it next." stood ~1000
      // characters before the end, the 400-character tail missed it, the session stood still for
      // 90 minutes in an autonomous run — the operator: "a fatal failure class for autonomous work").
      // The closing QUESTION stays a tail check: a question mid-reply that the reply then answers is
      // no turn end.
      const body = stripQuoted(seen.finalText);
      for (const m of body.matchAll(rx)) {
        // A running waiter excuses only the announcement whose sentence names what it waits for.
        cond.lastIndex = 0;
        if (seen.waiting && cond.test(sentenceAt(body, m.index))) continue;
        uniq([m[0]], announced);
      }
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (announced.length) {
    console.log(JSON.stringify(declare({
      decision: 'block',
      reason:
        'STOPPEN-GATE (an announcement is not an action — the turn ends and nothing runs).\n' +
        `Announced in this reply: ${announced.slice(0, 3).join(' · ')}\n` +
        (seen.waiting
          ? 'A waiter is running, but this announcement does not say it waits for it. Either DO the announced step now (tool call in this '
          : 'No background waiter is running. Either DO the announced step now (tool call in this ') +
        'turn), or arm the waiter it depends on, or state plainly who or what you wait for. ' +
        'If that is already true, re-issue the reply unchanged — it will pass.',
    }, input)));
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

  const how = autonomousMode(input.transcript_path, input.cwd || process.env.CLAUDE_PROJECT_DIR)
    ? `file it in the instance's question ledger — the operator ordered this run autonomous, so ` +
      `NOT through ${QUESTION_TOOL} — keep working on what is safely doable, and say it in the ` +
      'prose report with one visible line starting "⚙ autonomous:" that names where the questions ' +
      'are filed.'
    : `put it to the operator through the question tool (${QUESTION_TOOL}): one question ` +
      'per decision, the recommended option first and marked "(Recommended)", options in plain ' +
      'words; several decisions in one call. If this harness has no such tool, say so in one ' +
      'visible line starting "⚙ no question tool:" and keep the prose question.';
  if (reissue) {
    if (seen.gatesThisTurn >= MAX_TOOL_BLOCKS) {
      // Never lock a stuck session: let it through, but loudly — the omission stays visible.
      console.log(JSON.stringify({
        systemMessage:
          `STOPPEN-GATE: let through after ${seen.gatesThisTurn} blocks in this turn — a decision ` +
          `question went to the operator as closing prose, without ${QUESTION_TOOL} and without ` +
          `a "⚙ no question tool:" line. Question: ${hits.slice(0, 3).join(' · ')}`,
      }));
      process.exit(0);
    }
    // Deliberately WITHOUT the "Closing question in this reply:" line: the stop dispatcher
    // compresses on it, and this instruction has to reach the agent in full.
    console.log(JSON.stringify(declare({
      decision: 'block',
      reason:
        'STOPPEN-GATE (a decision for the operator is asked through the question tool, not ' +
        'as a closing prose question — re-issuing it unchanged does not pass).\n' +
        `Still closing on: ${hits.slice(0, 3).join(' · ')}\n` +
        `If only the operator can decide it, ${how} Otherwise do the work now and report.`,
    }, input)));
    process.exit(0);
  }

  console.log(JSON.stringify(declare({
    decision: 'block',
    reason:
      'STOPPEN-GATE (stopping is the exception — a closing permission question is a disguised stop).\n' +
      `Closing question in this reply: ${hits.slice(0, 3).join(' · ')}\n` +
      'Apply the three-condition test, AND-linked: (1) DECISION, not a work step · ' +
      '(2) blocks the work NOW · (3) only the operator can make it (his goal, money, ' +
      `hardware, risk). All three hold => ${how} ` +
      'Otherwise: the question is answerable by measurement, docs or rules — do the ' +
      'work now and report the result instead of asking.',
  }, input)));
  process.exit(0);
});

process.stdin.resume();
