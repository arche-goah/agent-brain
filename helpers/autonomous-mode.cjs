#!/usr/bin/env node
/**
 * Autonomous mode: did the operator order this run to go on without them?
 *
 * WHY (2026-10-21): the rule exists (skill autonomous-run, hard gate 7; operator decision
 * 2026-10-19): while the operator's autonomous order runs, a question for them is filed in
 * the instance's ledger and reported in prose — never asked through the question tool. But no
 * gate knew the mode: stoppen-gate demanded the question tool for a closing decision question,
 * open-items-gate demanded the "shall I?" offer in the first reply — both pushing the agent
 * toward the interactive stop the rule forbids. One reader, used by every gate that asks for
 * a question.
 *
 * Autonomous = the operator's NEWEST prompt carries an ON word and no OFF word. The rule ends
 * the mode when the operator ends it, writes to the session interactively again, or closes it —
 * so any later prompt without the word ends it, and the reader fails toward interactive.
 * Operator prompts only: no notification, hook echo, loaded skill text, request blob, or the
 * harness's instruction frames (a CLAUDE.md that mentions "autonomous" must not switch anything).
 *
 * Words: English built-ins below; the operator's language is instance data
 * `.claude/rules/autonomous-patterns.json` {"on_patterns": [...], "off_patterns": [...]}
 * (regexes, case-insensitive), merged in.
 *
 * CLI: node autonomous-mode.cjs <transcript> [cwd]  -> prints "autonomous" or "interactive".
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { isNotification, isSkillExpansion, isPeerMessage, isTranscriptRecord, queuedHumanPrompt, FRAMES, LOCAL } = require('./turn-kind.cjs');

const BUILTIN_ON = [
  '\\bautonomous(ly)?\\b',
  '\\bwork (the list|through (it|them|everything)) (alone|on your own)\\b',
  "\\bi'?m away\\b",
];
const BUILTIN_OFF = [
  '\\bnormal mode\\b',
  '\\b(stop|end) (the )?autonomous\\b',
  '\\bno longer autonomous\\b',
];
const HOOK_ECHO = /^\s*Stop hook feedback:/;

function patterns(cwd, key, builtins) {
  const list = [...builtins];
  try {
    const extra = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8'));
    for (const s of extra[key] || []) {
      try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ }
    }
  } catch (e) { /* built-ins only */ }
  return new RegExp(list.join('|'), 'iu');
}

function promptText(msg) {
  const c = msg && msg.content;
  if (typeof c === 'string') return c;
  if (!Array.isArray(c) || c.some((b) => b && b.type === 'tool_result')) return null;
  return c.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') || null;
}

/** true when the operator's autonomous order is in force at the end of the transcript. */
function autonomousMode(transcriptPath, cwd) {
  const modes = promptModes(transcriptPath, cwd);
  return modes.length ? modes[modes.length - 1].autonomous : false;
}

/**
 * Every operator prompt of the transcript in order, each with the mode it sets:
 * [{text, autonomous}]. The last one is the mode now; the one before tells whether this turn is
 * the first after an autonomous run (decision-presentation-gate).
 */
function promptModes(transcriptPath, cwd) {
  const dir = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const on = patterns(dir, 'on_patterns', BUILTIN_ON);
  const off = patterns(dir, 'off_patterns', BUILTIN_OFF);
  let lines;
  try { lines = fs.readFileSync(transcriptPath, 'utf8').split('\n'); } catch (e) { return []; }
  const out = [];
  for (const line of lines) {
    if (!line.includes('"user"') && !line.includes('queued_command')) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    // A message the operator types mid-turn arrives as a queued_command attachment, not a user
    // record (turn-kind.cjs, #139): it is the operator's word and sets the mode like any prompt
    // (same reading as #142; found 2026-10-26 by the macOS instance on #142). `queued` marks it,
    // so a reader that counts turn BOUNDARIES can leave it out.
    const queued = queuedHumanPrompt(d);
    if (!queued && (!isTranscriptRecord(d) || isSkillExpansion(d) || isPeerMessage(d) || !d.message || d.message.role !== 'user')) continue;
    const t = queued || promptText(d.message);
    if (!t || HOOK_ECHO.test(t) || isNotification(t)) continue;
    const words = t.replace(FRAMES, ' ').replace(LOCAL, ' ');
    if (!words.trim()) continue;
    out.push({ text: words, autonomous: !off.test(words) && on.test(words), queued: Boolean(queued) });
  }
  return out;
}

module.exports = { autonomousMode, promptModes };

if (require.main === module) {
  const [tp, cwd] = process.argv.slice(2);
  console.log(autonomousMode(tp || '', cwd) ? 'autonomous' : 'interactive');
}
