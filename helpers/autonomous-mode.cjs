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
 * Autonomous = a latch over the operator's words:
 *   - an ON word sets it ("work through everything autonomously");
 *   - an OFF word clears it ("normal mode", "stop autonomous");
 *   - ASKING what is open clears it: the operator who asks is here, the open decisions go through
 *     the question tool, and the last of them is "continue autonomously?" (operator, Windows
 *     instance, 2026-10-26, translated: "as soon as I ask whether anything is open for me, I am
 *     obviously here ... that ends the autonomous mode. The last question is always: continue
 *     autonomously?");
 *   - a YES to a question-tool question that carries an ON word sets it again — that answer arrives
 *     as a tool result, not as a prompt.
 * A status question or a remark in between ("status?", "the desk is running, if you need it", "do
 * not stop everything interactively") ends nothing: re-deciding the mode at every prompt made those
 * stop the run (macOS findings on #143 and #142, 2026-10-26).
 * No transcript or no ON prompt: interactive.
 * Operator words only: no notification, hook echo, loaded skill text, request blob, peer message,
 * or the harness's instruction frames (a CLAUDE.md that mentions "autonomous" must not switch anything).
 *
 * Words: English built-ins below; the operator's language is instance data —
 * `.claude/rules/autonomous-patterns.json` {"on_patterns", "off_patterns", "yes_patterns"} and the
 * `ask_patterns` of `.claude/rules/open-items.json` (the key open-items-gate reads) — regexes,
 * case-insensitive, merged in.
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
const BUILTIN_ASK = [
  '\\banything (still |else )?(open|left|pending)\\b',
  '\\bwhat is (still )?open\\b',
  '\\bopen (for|to) me\\b',
  '\\bdo you need (anything|something)\\b',
  '\\bput (the |your )?(open )?(decisions|questions) to me\\b',
];
const BUILTIN_YES = ['^\\s*yes\\b'];
const HOOK_ECHO = /^\s*Stop hook feedback:/;
// The tool result of an answered AskUserQuestion: `"<question>"="<answer>"` pairs.
const ANSWERED = 'questions have been answered';
const PAIR = /"([^"]*)"="([^"]*)"/g;

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; } }

function rx(builtins, extra) {
  const list = [...builtins];
  for (const s of extra || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ } }
  return new RegExp(list.join('|'), 'iu');
}

/** The four word sets of a brain: on, off, ask, yes. */
function words(cwd) {
  const dir = cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const ap = readJson(path.join(dir, '.claude', 'rules', 'autonomous-patterns.json')) || {};
  const oi = readJson(path.join(dir, '.claude', 'rules', 'open-items.json')) || {};
  return {
    on: rx(BUILTIN_ON, ap.on_patterns),
    off: rx(BUILTIN_OFF, ap.off_patterns),
    ask: rx(BUILTIN_ASK, oi.ask_patterns),
    yes: rx(BUILTIN_YES, ap.yes_patterns),
  };
}

/**
 * An on-word orders the run only outside a question. Measured 2026-10-27 on the macOS instance: the
 * operator asked (translated) "got no continue-autonomously question, did I? why?" - the word in that
 * question set the latch, and the gate then held the very mode question the operator was missing.
 * A sentence ending in "?" mentions the mode; it does not order it.
 */
function ordersOn(on, text) {
  return (text.match(/[^.!?\n]+[.!?]*/g) || []).some((s) => !/\?\s*$/.test(s) && on.test(s));
}

function promptText(msg) {
  const c = msg && msg.content;
  if (typeof c === 'string') return c;
  if (!Array.isArray(c) || c.some((b) => b && b.type === 'tool_result')) return null;
  return c.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') || null;
}

/** [question, answer] pairs of an answered question tool in this record. */
function answers(msg) {
  const c = msg && msg.content;
  if (!Array.isArray(c)) return [];
  const out = [];
  for (const b of c) {
    if (!b || b.type !== 'tool_result') continue;
    const s = typeof b.content === 'string' ? b.content
      : Array.isArray(b.content) ? b.content.map((x) => (x && x.text) || '').join('\n') : '';
    if (!s.includes(ANSWERED)) continue;
    for (const m of s.matchAll(PAIR)) out.push([m[1], m[2]]);
  }
  return out;
}

/**
 * Every operator word of the transcript in order, each with the latch AFTER it:
 * [{text, autonomous, queued, asks, answer}]. `asks`: the prompt asks what is open. `answer`: the
 * entry is a yes/no to an autonomy question, not a prompt. The last entry is the mode now.
 */
function promptModes(transcriptPath, cwd) {
  const w = words(cwd);
  let lines;
  try { lines = fs.readFileSync(transcriptPath, 'utf8').split('\n'); } catch (e) { return []; }
  const out = [];
  let state = false;
  for (const line of lines) {
    if (!line.includes('"user"') && !line.includes('queued_command')) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    // A message the operator types mid-turn arrives as a queued_command attachment, not a user
    // record (turn-kind.cjs, #139): it sets or clears the mode like any prompt. `queued` marks it,
    // so a reader that counts turn BOUNDARIES can leave it out.
    const queued = queuedHumanPrompt(d);
    if (!queued && (!isTranscriptRecord(d) || isSkillExpansion(d) || isPeerMessage(d) || !d.message || d.message.role !== 'user')) continue;
    if (!queued) {
      for (const [q, a] of answers(d.message)) {
        if (!w.on.test(q)) continue;
        state = w.yes.test(a) && !w.off.test(a);
        out.push({ text: a, autonomous: state, queued: false, asks: false, answer: true });
      }
    }
    const t = queued || promptText(d.message);
    if (!t || HOOK_ECHO.test(t) || isNotification(t)) continue;
    const text = t.replace(FRAMES, ' ').replace(LOCAL, ' ');
    if (!text.trim()) continue;
    const asks = w.ask.test(text);
    if (w.off.test(text) || asks) state = false;
    else if (ordersOn(w.on, text)) state = true;
    out.push({ text, autonomous: state, queued: Boolean(queued), asks, answer: false });
  }
  return out;
}

/** true when the operator's autonomous order is in force at the end of the transcript. */
function autonomousMode(transcriptPath, cwd) {
  const modes = promptModes(transcriptPath, cwd);
  return modes.length ? modes[modes.length - 1].autonomous : false;
}

module.exports = { autonomousMode, promptModes, words };

if (require.main === module) {
  const [tp, cwd] = process.argv.slice(2);
  console.log(autonomousMode(tp || '', cwd) ? 'autonomous' : 'interactive');
}
