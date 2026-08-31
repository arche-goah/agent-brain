#!/usr/bin/env node
/**
 * Stop hook: stopping is the exception, not the rhythm (T1 item 3).
 *
 * The anti-pattern (operator order 2026-08-08): a reply that ENDS by handing
 * the next step back as a question ("Soll ich ...?", "Womit weitermachen?")
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
 * merged in. The German block below is the operator-language EXAMPLE pack of the
 * mechanism, not a special case — Czech, French, Spanish work identically via the
 * instance file. It ships inline ONLY until this hook moves to the core (T3): a
 * CLASS fix (a new question shape) lands in the English built-ins first, a
 * language pack only ever adds a language.
 */
const fs = require('fs');
const path = require('path');

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
// gate), option questions without "ich" ("welcher Kanal?"), AskUserQuestion.
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

// Operator-language EXAMPLE pack (German). Belongs in
// .claude/rules/stop-patterns.json as instance data; inline only until the hook
// moves to the core — then this block becomes the shipped example file.
const LANGUAGE_PACK_DE = [
  '\\bsoll ich\\b[^?\\n]{0,140}\\?',
  '\\bsollen wir\\b[^?\\n]{0,140}\\?',
  '\\bm(ö|oe)chtest du,? dass ich\\b[^?\\n]{0,140}\\?',
  '\\bwillst du,? dass ich\\b[^?\\n]{0,140}\\?',
  '\\bdarf ich\\b[^?\\n]{0,140}\\?',
  '\\bwomit (soll ich )?(weitermachen|starten|anfangen|beginnen)\\b[^?\\n]{0,60}\\?',
  '\\b(weitermachen|fortfahren)\\?',
  // Shape 2 in this language. Same function, no question mark.
  '\\bsag (mir )?(bitte )?bescheid\\b[^.\\n]{0,80}[.!]',
  '\\bgib (mir )?(bitte )?bescheid\\b[^.\\n]{0,80}[.!]',
  '\\bmelde dich\\b[^.\\n]{0,80}[.!]',
  '\\b(liegt|liegen) (jetzt |damit |weiterhin )?(bei|beim) (dir|euch|ihm|ihr|kollegen|dem kollegen|der workstation|workstation)\\b',
  '\\bwenn du (willst|magst|moechtest|möchtest),? (dann )?(mache|baue|nehme|schreibe) ich\\b',
  '\\bzwei wege\\b[^.\\n]{0,120}\\boder\\b[^.\\n]{0,120}[.!]',
];

function loadPatterns(cwd) {
  const patterns = [...BUILTIN_PATTERNS, ...LANGUAGE_PACK_DE];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'stop-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra.patterns)) {
      for (const s of extra.patterns) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(patterns.join('|'), 'giu');
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
  for (const line of lines) {
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
  return { finalText, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let hits = [];
  try {
    const seen = analyze(input.transcriptPath || input.transcript_path);
    if (seen.quiet) return allow();
    if (!seen.finalText) return allow();
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const tail = stripQuoted(seen.finalText).slice(-TAIL_CHARS);
    const found = tail.match(loadPatterns(cwd)) || [];
    for (const h of found) {
      const norm = h.trim().replace(/\s+/g, ' ');
      if (!hits.includes(norm)) hits.push(norm);
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (hits.length === 0) return allow();

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
