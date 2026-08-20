#!/usr/bin/env node
/**
 * Stop hook: a generalisation that CARRIES an action is a premise, and a premise
 * is checked against the single observations before it carries anything.
 *
 * The class (measured 2026-08-20, four instances in four days): a premise that is
 * NEEDED for the next step gets treated like one that was MEASURED. Once a
 * construct stands on it — a test design, a decision menu, five layouts — the
 * construct protects the premise: questioning it then reads as friction against
 * progress. Instances: manufacturer-type XML recommendation generalised from the
 * generic type (2026-08-17) · "page-relative addressing does not carry", never
 * measured, five layouts built on it (2026-08-19) · "in a conflict the one who
 * lets go last wins", contradicted by the operator's own second observation in
 * the same message, used as the premise of a decision menu (2026-08-20).
 *
 * What fires: BOTH conditions in the same turn.
 *   (a) a rule-shaped sentence in the assistant's own prose ("always", "never",
 *       "in every case", "the rule is") — the linguistic form of a claim about
 *       ALL cases, derived from a handful;
 *   (b) something in the same turn that BUILDS on it: files written, or a
 *       decision put to the operator, or a numbered instruction to go and do
 *       something.
 * (a) alone is analysis and stays free — naming a class is wanted, that is the
 * whole point of the class discipline. Only the combination is the defect.
 *
 * Asymmetry check on this carrier itself (rule `traeger-asymmetrie`, mandatory
 * for every new trigger): it strengthens the GROUNDING axis (stay with the single
 * case and its qualifiers) and thereby weakens, relatively, the ABSTRACTION axis
 * that five carriers strengthened on 2026-08-19 (class question, invariant,
 * skill-first). That is deliberate and bounded: the gate never asks to drop a
 * generalisation, it asks for the check against each observation — and it stays
 * silent when no action rests on the sentence.
 *
 * Frequency design: fires only on a hit, once per turn, cooldown of 2 operator
 * turns — a conversation ABOUT generalisations must not become wallpaper.
 *
 * Language-agnostic by contract (operator order 2026-08-19): built-in patterns
 * are ENGLISH; every other language is DATA in
 * `.claude/rules/premise-patterns.json` ({"generalisation_patterns": [...],
 * "instruction_patterns": [...]}). A class fix lands in the built-ins FIRST.
 */
const fs = require('fs');
const path = require('path');

// stdin is read to its END, never on a timer. Measured 2026-08-20 while building
// this gate: with `setTimeout(..., 0)` the same input on the same file blocked once
// and stayed silent the next run — the timer can fire before the first `data`
// event, the payload is then empty, JSON.parse fails and the gate silently allows.
// A gate that fails open at random is indistinguishable from a gate that agrees.
let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
const OWN_ECHO = /PREMISE-GATE/;
const COOLDOWN_TURNS = 2;
const TAIL_BYTES = 4 * 1024 * 1024;

// (a) rule-shaped sentences. The FORM matters, not the word: a rule is a claim in
// the generalised present, anchored by a modal or copula or by explicit
// quantification. Version 1 matched the bare words (always/never + anything) and
// therefore caught NARRATION in the perfect tense — "never measured", "was never
// armed", "was never passed through" are statements about one past thing, not
// claims about all cases. Measured over 12 real transcripts, 275 turns: version 1
// blocked 48 turns (17 %) of which exactly ONE was a real premise; this set blocks
// 7 turns (3 %) and still catches that one. A trigger that fires every sixth turn
// becomes ritual — the failure mode `traeger-asymmetrie` names.
const BUILTIN_GENERALISATION = [
  '\\b(must|should|will|is|are|stays|remains|means)\\s+(always|never)\\b',
  '\\b(always|never)\\s+\\w+s\\b',                 // present tense: "always wins"
  '\\b\\w+s\\s+(always|never)\\s+(the|a|an|every|each)\\b',
  '\\b(always|never)\\s+(when|if)\\b',
  '\\bin\\s+(every|each|all)\\s+(case|cases|situation|situations)\\b',
  '\\bevery\\s+time\\b',
  '\\bwithout\\s+exception\\b',
  '\\bthe\\s+rule\\s+is\\b',
  '\\bas\\s+a\\s+rule\\b',
  '\\bwhoever\\s+\\w+\\s+(wins|loses)\\b',
];

// (b) an instruction handed to the operator — the cheap textual half of "an
// action rests on it". The expensive half (files written, decision asked) comes
// from the transcript's tool uses, not from patterns.
const BUILTIN_INSTRUCTION = [
  '^\\s*\\d+\\.\\s+\\*\\*',        // numbered step with a bold lead-in
  '\\bplease\\s+(move|pull|push|touch|hold|press|run|start|open|set)\\b',
];

const ACTION_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit',
  'AskUserQuestion']);

function buildRegex(builtins, key, cwd, flags) {
  const patterns = [...builtins];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'premise-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra[key])) {
      for (const s of extra[key]) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file — built-ins only */ }
  return new RegExp(patterns.join('|'), flags);
}

// Talk ABOUT a rule quotes it; a violation writes it bare. Same stripper family as
// the time gate — quotes, code, blockquotes.
function stripQuoted(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/„[^“”"\n]*[“”"]/g, ' ')
    .replace(/“[^”]*”/g, ' ')
    .replace(/"[^"\n]*"/g, ' ')
    .replace(/‹[^›]*›|«[^»]*»/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

/** Assistant texts + action tool uses of the running turn, plus cooldown state. */
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
        if (b.type === 'tool_use' && ACTION_TOOLS.has(b.name)) events.push({ action: b.name });
      }
    }
  }

  let last = events.length;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].boundary) { last = i; break; }
  }
  const texts = [];
  const actions = [];
  for (let i = last; i < events.length; i++) {
    if (events[i].text) texts.push(events[i].text);
    if (events[i].action) actions.push(events[i].action);
  }

  let lastGate = -1;
  for (let i = events.length - 1; i >= 0; i--) {
    if (events[i].gate) { lastGate = i; break; }
  }
  let turnsSinceGate = Infinity;
  if (lastGate >= 0) {
    turnsSinceGate = 0;
    for (let i = lastGate + 1; i < events.length; i++) if (events[i].boundary) turnsSinceGate++;
  }
  return { texts, actions, quiet: turnsSinceGate < COOLDOWN_TURNS };
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }

  if (input.stop_hook_active) return allow();
  if (!input.transcript_path) return allow();

  let hits = [];
  let carries = null;
  try {
    const seen = analyze(input.transcript_path);
    if (seen.quiet) return allow();
    const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const clean = stripQuoted(seen.texts.join('\n'));

    const found = clean.match(buildRegex(BUILTIN_GENERALISATION,
      'generalisation_patterns', cwd, 'giu')) || [];
    for (const h of found) {
      const norm = h.toLowerCase().replace(/\s+/g, ' ').trim();
      if (!hits.includes(norm)) hits.push(norm);
    }
    if (hits.length === 0) return allow();

    if (seen.actions.length > 0) {
      carries = seen.actions.includes('AskUserQuestion')
        ? 'a decision put to the operator' : 'files written this turn';
    } else if (buildRegex(BUILTIN_INSTRUCTION, 'instruction_patterns', cwd, 'gimu')
      .test(clean)) {
      carries = 'an instruction handed to the operator';
    }
  } catch (e) {
    return allow(); // transcript unreadable — never block because of that
  }
  if (!carries) return allow(); // a generalisation alone is analysis, not a premise

  // Terse on purpose (same trim as the class gate, operator finding 2026-08-19):
  // show the sentence, name the one check, get out of the way.
  const reason = 'PREMISE-GATE — a general sentence is carrying an action ' +
    `(${carries}), so it is a premise now.\n` +
    `Rule-shaped wording: ${hits.slice(0, 4).join(' · ')}\n` +
    'Hold it against EACH single observation, including the operator\'s own ' +
    'qualifiers ("stays where I let go", "even with no finger on it"). One that ' +
    'contradicts kills the sentence — the observations stand, the rule does not.\n' +
    'Then say per premise: measured / derived / assumed. Assumed premises do not ' +
    'carry actions.\n' +
    'Holds up? Re-issue unchanged.';

  console.log(JSON.stringify({ decision: 'block', reason }));
  process.exit(0);
});
