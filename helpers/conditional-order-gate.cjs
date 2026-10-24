#!/usr/bin/env node
/**
 * PreToolUse hook: an order that names a CONDITION is not acted on before the condition
 * is checked — the mirror of promise-gate.cjs, on the operator's side of the sentence.
 *
 * The class (measured on a collaborating instance, 2026-10-16): the operator wrote
 * "dann coherence scan" — "then", meaning AFTER the answer the two other instances had
 * been asked for, and after the core update they had recommended first. The agent read
 * "then" as "now", started nine analysis agents, and mentioned the recommendation in its
 * text without waiting for it. The operator stopped the run ("why do you work AGAINST
 * the recommendation?"); the tokens were spent. Nothing in the core carried the case:
 * promise-gate stores the agent's OWN conditional commitments, premise-gate checks
 * generalisations, "a question is not an approval" (order fidelity #7) names no
 * sequencing word. The same class covers a delegated decision ("clear it with X",
 * "X decides"): that too is a condition — X's answer — that has to arrive first.
 *
 * What it does: when the operator's LAST message (not a harness notification, not a hook
 * echo) carries a condition word — then / after / once / when … has answered / wait for /
 * clear it with … — the first EXPENSIVE or EXTERNALLY EFFECTIVE call of the turn is held:
 *   - `Workflow` always;
 *   - `Agent` from the third call in the turn (one or two agents are a lookup, nine are a
 *     scan — the collaborator's threshold);
 *   - a shell command that leaves the machine or starts a model: `claude -p`, `git push`,
 *     `gh pr create|comment|review|merge`, `gh api … -X`, `gh issue create|comment`.
 * It passes once the agent has written, in this turn, either
 *   CONDITION-MET: <the condition, in the operator's words> — <evidence: where/when it was met>
 * or
 *   CONDITION-NONE: <why this word is no condition here>
 * The gate does not judge the condition; it forces the check that was skipped. A false
 * positive costs one line. Everything else — a read, an edit, a commit, a single agent —
 * stays free: those are the steps that establish whether the condition holds.
 *
 * Fail-open where it cannot measure: no transcript, unreadable transcript, no operator
 * message in the turn — the gate allows and says nothing (same contract as promise-gate).
 *
 * Language-agnostic by contract (operator order 2026-08-19): built-in patterns are
 * ENGLISH; every other language is DATA in `.claude/rules/condition-patterns.json`
 * ({"condition_patterns": [...]}, regex strings; template in templates/rules-instance/).
 * A class fix lands in the built-ins FIRST.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { isNotification, isSkillExpansion, isPeerMessage, isTranscriptRecord } = require('./turn-kind.cjs');

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });

function allow() { process.exit(0); }

const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const AGENT_THRESHOLD = 3;   // the call that trips the gate: this many Agent calls in one turn
const EXTERNAL = /(?:^|[\s;&|(`])(?:claude\s+-p\b|git\b[^\n|;&]*\bpush\b|gh\s+pr\s+(?:create|comment|review|merge)\b|gh\s+issue\s+(?:create|comment)\b|gh\s+api\b[^\n|;&]*\s-X\s)/i;
const MET = /CONDITION-MET:\s*(\S[^\n]{19,})/;
const NONE = /CONDITION-NONE:\s*(\S[^\n]{14,})/;

// English built-ins. Sequencing words that bind an order to an event, and the delegated
// decision. "then" alone is in: it is the word of the incident, and the price of a hit is
// one marker line.
const BUILTIN_CONDITION = [
  '\\bthen\\b',
  '\\bafter\\s+(?:the|your|his|her|their|that|this|my|our|[A-Z]\\w+(?:\'s)?)\\b',
  '\\bafterwards\\b',
  '\\bonce\\s+\\w+',
  '\\bwhen\\s+(?:\\w+\\s+){0,3}(?:has\\s+|have\\s+|is\\s+|are\\s+)?(?:answered|replied|responded|done|finished|merged|green|back|through|ready)\\b',
  '\\bwait\\s+(?:for|until|till)\\b',
  '\\bnot\\s+before\\b',
  '\\bonly\\s+(?:after|once|when)\\b',
  '\\bas\\s+soon\\s+as\\b',
  '\\b(?:clear|sort|settle|check)\\s+(?:it|that|this)\\s+(?:out\\s+)?with\\b',
  '\\b(?:ask|consult)\\s+\\w+\\s+first\\b',
  '\\b\\w+\\s+decides\\b',
  '\\bup\\s+to\\s+\\w+\\s+to\\s+decide\\b',
];

function buildRegex(cwd) {
  const patterns = [...BUILTIN_CONDITION];
  try {
    const p = path.join(cwd, '.claude', 'rules', 'condition-patterns.json');
    const extra = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (Array.isArray(extra.condition_patterns)) {
      for (const s of extra.condition_patterns) {
        try { new RegExp(s); patterns.push(s); } catch (e) { /* skip broken regex */ }
      }
    }
  } catch (e) { /* no instance file -- built-ins only */ }
  return new RegExp(patterns.join('|'), 'iu');
}

// Talk ABOUT a condition quotes it; an order is given bare. Same stripper as promise-gate.
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

function sentences(text) {
  return text.split(/(?<=[.!?])\s+|\n+/).map((s) => s.trim()).filter(Boolean);
}

/** The operator's text of a user record, or null when the record is no operator text. */
function promptText(msg) {
  if (typeof msg.content === 'string') return msg.content;
  if (!Array.isArray(msg.content) || msg.content.some((b) => b && b.type === 'tool_result')) return null;
  const t = msg.content.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n');
  return t || null;
}

/** Last operator message, the assistant texts since it, and the Agent calls since it. */
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
  let operator = null;
  let texts = [];
  let agents = 0;
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user') {
      // A loaded skill's text: no condition, no new turn (2026-10-19, "then" in session-close).
      if (isSkillExpansion(d) || isPeerMessage(d)) continue;
      const t = promptText(msg);
      if (t === null || HOOK_ECHO.test(t) || isNotification(t)) continue;
      operator = t; texts = []; agents = 0;   // a new turn starts here
      continue;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (!b) continue;
        if (b.type === 'text' && b.text) texts.push(b.text);
        if (b.type === 'tool_use' && b.name === 'Agent') agents++;
      }
    }
  }
  return { operator, texts, agents };
}

function deny(hit, why) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        'CONDITIONAL-ORDER-GATE: the operator\'s last message binds the order to a condition, '
        + `and this call is ${why}.\n`
        + `Sentence: "${hit.sentence.slice(0, 160)}" (condition word: ${hit.word})\n`
        + 'Write ONE line, then call again — either as a comment IN the call (`# CONDITION-NONE: …` in the command, a line in the prompt), or in the answer, letting that message end before the next call (its record lands only after it):\n'
        + '  CONDITION-MET: <the condition in the operator\'s words> — <evidence: where and when it was met>\n'
        + '  CONDITION-NONE: <why this word is no condition here>\n'
        + 'Reads, edits, commits and a single agent stay free — they are how the condition gets checked. '
        + '(Measured 2026-10-16: "then the coherence scan" meant "after the answer"; nine agents started before it came.)',
    },
  }));
  process.exit(0);
}

process.stdin.on('end', () => {
  let input = {};
  try { input = JSON.parse(data); } catch (e) { return allow(); }
  const tool = String(input.tool_name || '');
  const ti = input.tool_input || {};
  let why = '';
  if (tool === 'Workflow') why = 'a workflow (an audit-sized run)';
  else if (tool === 'Agent') why = `agent number ${AGENT_THRESHOLD} or more in this turn`;
  else if ((tool === 'Bash' || tool === 'PowerShell') && typeof ti.command === 'string' && EXTERNAL.test(ti.command)) {
    why = 'externally effective (it leaves the machine or starts a model run)';
  } else return allow();
  if (!input.transcript_path) return allow();

  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  let seen;
  try { seen = analyze(input.transcript_path); } catch (e) { return allow(); }
  if (!seen.operator) return allow();
  // The call being judged is not in the transcript yet: it is agents + 1.
  if (tool === 'Agent' && seen.agents + 1 < AGENT_THRESHOLD) return allow();

  const condition = buildRegex(cwd);
  let hit = null;
  for (const s of sentences(stripQuoted(seen.operator))) {
    const m = s.match(condition);
    if (m) { hit = { sentence: s, word: m[0] }; break; }
  }
  if (!hit) return allow();
  // The line may also stand in the call itself (a `# CONDITION-NONE: …` comment in the command,
  // a line in an agent's prompt): the hook always sees its own input, while a text written in
  // the same response as the call reached the transcript as `thinking` (2.1.303, 2026-10-19) or
  // not at all (2026-10-21, both Windows) — the way out could not be taken.
  const call = Object.values(ti).filter((v) => typeof v === 'string').join('\n');
  const turn = seen.texts.join('\n') + '\n' + call;
  if (MET.test(turn) || NONE.test(turn)) return allow();
  deny(hit, why);
});
