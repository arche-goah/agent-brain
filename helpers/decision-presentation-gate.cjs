#!/usr/bin/env node
/**
 * Stop hook: at the right moment, the operator's open decisions go through the question tool.
 *
 * WHY (measured 2026-10-26 on the Windows instance): asked "is anything open for me?", the reply
 * listed four real operator decisions in prose, each with "recommendation: yes" and no question
 * mark, so stoppen-gate (which looks for a closing question) let it pass. The operator had to ask
 * again (translated): "then put the decisions to me clearly, interactively", and then ordered: the
 * core must make sure that real operator decisions are put as interactive questions, at the right
 * moment only, and never during an autonomous run. The same evening (translated): "as soon as I ask
 * whether anything is open for me, I am obviously here ... that ends the autonomous mode. The last
 * question is always: continue autonomously?" On the macOS instance the same day, clarified through the
 * question tool (translated): collect during the run; at its end every HAND STEP and decision goes
 * through the tool, never prose, and the last question is "continue autonomously?".
 *
 * The right moment (autonomous-mode.cjs, a latch):
 *   - the operator's newest prompt asks what is open (built-ins plus the instance's `ask_patterns`
 *     in .claude/rules/open-items.json) - that also ends a running autonomous mode, or
 *   - the newest prompt ended the autonomous mode (an off-word). A status question or a remark
 *     mid-run ends nothing, so it is no such moment; nor is a turn after "yes, continue".
 * What is demanded, once the moment has come and the mode is not on again by the end of the turn:
 *   - open OPERATOR decisions go through AskUserQuestion. Counted: entries `- [ ]` with
 *     `class: decision` or `class: hand-step` (a step only the operator's hand can take) in the registered ledgers (.claude/rules/ledgers.json) whose `circle:` is
 *     the operator's (B own decision, E several people, F between people - open-items.py); A (the AI
 *     alone), C (the AIs among themselves) and D (another person's word) never reach the operator's
 *     question tool (macOS finding on #143: 27 "decisions" on one brain, a collaborator's among
 *     them). An entry without `circle:` counts, named apart so it gets one. Plus questions in the
 *     question-gate register (.claude-state/open-questions.json), status deferred or unanswered.
 *   - when the autonomous mode was on before this prompt, the LAST question of the turn's last
 *     AskUserQuestion carries an on-word ("continue autonomously?") - with or without open decisions.
 * This hook demands the tool and that last question, never the other wording, and does NOT check
 * that a question was re-measured before it is put - that is not carried here.
 * Output: {"decision":"block","reason":"..."}. Fails open on unreadable input.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { promptModes, words } = require('./autonomous-mode.cjs');
const ITEM_CLASS = /\bclass:\s*`?(decision|hand-step)\b/i;
const { queuedHumanPrompt } = require('./turn-kind.cjs');

// Decision circles that need the operator (open-items.py CIRCLE_WORDS: B, E, F = human).
const OPERATOR_CIRCLES = new Set(['B', 'E', 'F']);

function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; } }

/** Open `class: decision` and `class: hand-step` entries of the registered ledgers, as short titles. */
function ledgerDecisions(root) {
  const cfg = readJson(path.join(root, '.claude', 'rules', 'ledgers.json')) || {};
  const out = [];
  for (const rel of cfg.ledgers || []) {
    let text;
    try { text = fs.readFileSync(path.join(root, rel), 'utf8'); } catch (e) { continue; }
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const m = /^- \[ \] (.*)$/.exec(lines[i]);
      if (!m) continue;
      let j = i + 1;
      const block = [lines[i]];
      while (j < lines.length && lines[j].startsWith(' ')) block.push(lines[j++]);
      const body = block.join('\n');
      if (!ITEM_CLASS.test(body)) continue;
      const circle = /^\s+(?:-\s*)?circle:\s*`?([A-Fa-f])\b/m.exec(body);
      if (circle && !OPERATOR_CIRCLES.has(circle[1].toUpperCase())) continue;
      // The entry's LAST exit line (skill backlog-catch-up) says who moves now; only
      // `operator-decision` (or no exit yet) is the operator's. Measured 2026-10-28 on the macOS
      // instance: 22 entries counted, by their exits 12 later-at-system, 5 parked, 4 other-side,
      // 1 ai-does-it — none an operator decision.
      const exits = [...body.matchAll(/^\s*exit:\s*([\w-]+)/gm)];
      if (exits.length && exits[exits.length - 1][1] !== 'operator-decision') continue;
      out.push((circle ? '' : '(no circle) ') + m[1].replace(/\*\*/g, '').slice(0, 80));
    }
  }
  return out;
}

function registerDecisions(root) {
  const reg = readJson(path.join(root, '.claude-state', 'open-questions.json')) || {};
  return Object.values(reg).filter((q) => q && ['deferred', 'unanswered'].includes(q.status))
    .map((q) => String(q.q || '').slice(0, 80));
}

/** The question lists of every AskUserQuestion the running turn (after the newest prompt) called, in order. */
function questionsThisTurn(transcriptPath, lastPrompt) {
  let lines;
  try { lines = fs.readFileSync(transcriptPath, 'utf8').split('\n'); } catch (e) { return []; }
  const calls = [];
  const key = (lastPrompt || '').trim().slice(0, 60);
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i];
    if (!l.trim()) continue;
    let d;
    try { d = JSON.parse(l); } catch (e) { continue; }
    const queued = queuedHumanPrompt(d); // the newest prompt may have been typed mid-turn
    if (queued && key && queued.includes(key)) break;
    const msg = d.message;
    if (!msg) continue;
    if (msg.role === 'user' && key) {
      const c = msg.content;
      const t = typeof c === 'string' ? c : Array.isArray(c) ? c.filter((b) => b && b.type === 'text').map((b) => b.text).join('\n') : '';
      if (t && t.includes(key)) break;
    }
    if (msg.role === 'assistant' && Array.isArray(msg.content)) {
      for (const b of msg.content) {
        if (!b || b.type !== 'tool_use' || b.name !== 'AskUserQuestion') continue;
        const qs = (b.input && Array.isArray(b.input.questions)) ? b.input.questions : [];
        calls.unshift(qs.map((q) => String((q && q.question) || '')));
      }
    }
  }
  return calls;
}

function judge(input) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const modes = promptModes(input.transcript_path || '', root);
  if (!modes.length || modes[modes.length - 1].autonomous) return null; // in the run, or "yes, continue"
  let n = modes.length - 1;
  while (n >= 0 && modes[n].answer) n--; // the newest operator PROMPT, not an answer to a question
  if (n < 0) return null;
  const now = modes[n];
  const wasOn = n > 0 && modes[n - 1].autonomous;
  if (!now.asks && !wasOn) return null;
  const open = [...ledgerDecisions(root), ...registerDecisions(root)];
  const calls = questionsThisTurn(input.transcript_path, now.text);
  const missing = [];
  if (open.length && !calls.length) {
    missing.push(`${open.length} operator hand step(s) and decision(s) through the question tool (one question each, recommended option first; ` +
      `an entry marked (no circle) gets its circle: in the ledger if it is not the operator's) - ` +
      `${open.slice(0, 4).join(' | ')}${open.length > 4 ? ` (+${open.length - 4} more)` : ''}`);
  }
  if (wasOn) {
    const on = words(root).on;
    const last = calls.length ? calls[calls.length - 1] : [];
    if (!last.length || !on.test(last[last.length - 1])) missing.push('the last question "continue autonomously?"');
  }
  if (!missing.length) return null;
  const why = now.asks ? 'the operator asked what is open' : 'the autonomous run has ended';
  // The seam to question-gate (macOS instance, branch feat/question-recheck-before-reask): that hook
  // checks freshness when a register question is put again; this one only says so.
  return `DECISION-PRESENTATION: ${why}${wasOn ? ' (the autonomous mode was on)' : ''} - prose is not the way. ` +
    'Before putting a register question again, re-measure it (question-gate recheck) or close it (resolve). ' +
    `Missing: ${missing.join('; ')}`;
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    if (input.stop_hook_active) process.exit(0);
    let reason = null;
    try { reason = judge(input); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify({ decision: 'block', reason }));
    process.exit(0);
  });
}

module.exports = { judge, ledgerDecisions, registerDecisions };
