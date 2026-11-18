#!/usr/bin/env node
/**
 * PreToolUse on AskUserQuestion (hooks/hooks.json): the mode question ("continue autonomously?") comes LAST, after the steps the
 * operator's answers set off — above all the ones that raise a dialog (an edit under an ask rule, a call the
 * classifier holds, a hand step).
 *
 * WHY (operator 2026-10-26, again 2026-11-18): "you put the mode question before the interactive things were done".
 * 2026-10-26 the decisions and the mode question shared one call; 2026-11-18 the mode question was its own call,
 * but issued right after the answers, with no step run in between — the settings.json edit the operator had just
 * allowed then hit the autonomous gate and stayed undone. The rule stood as prose only (ledger,
 * no check).
 *
 * Holds the call ONCE when
 *   (a) it asks the mode question together with any other question, or
 *   (b) it asks the mode question and the last AskUserQuestion answer in the transcript has no tool call after it.
 * A re-issue of the same call passes (the answers may have needed no step). Frequency design: once per distinct
 * call, state in .claude-state/mode-question-order.json.
 * ponytail: (b) counts any tool call as "the steps ran"; an unrelated call between answers and mode question
 * passes. Upgrade: match the answered options to the calls they need.
 * Mode words: English + German built in; more in .claude/rules/mode-question.json {"patterns": ["<regex>"]}.
 * Fails open on unreadable input or transcript.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const BUILTIN = ['\\bweiter autonom', '\\bcontinue autonomous', '\\bautonom weiter'];
const TAIL = 4 * 1024 * 1024;

function patterns(root) {
  let extra = [];
  try { extra = JSON.parse(fs.readFileSync(path.join(root, '.claude/rules/mode-question.json'), 'utf8')).patterns || []; } catch (e) { /* none */ }
  return [...BUILTIN, ...extra].map((p) => { try { return new RegExp(p, 'i'); } catch (e) { return null; } }).filter(Boolean);
}

function isMode(q, pats) {
  const t = `${q.question || ''} ${q.header || ''}`;
  return pats.some((r) => r.test(t));
}

function callsSinceLastAnswer(tp) {
  let buf;
  try {
    const st = fs.statSync(tp);
    const fd = fs.openSync(tp, 'r');
    const len = Math.min(st.size, TAIL);
    buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, st.size - len);
    fs.closeSync(fd);
  } catch (e) { return null; }
  const askIds = new Set();
  let answered = false;
  let calls = 0;
  for (const line of buf.toString('utf8').split('\n')) {
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const content = d && d.message && Array.isArray(d.message.content) ? d.message.content : [];
    for (const b of content) {
      if (b.type === 'tool_use') {
        if (b.name === 'AskUserQuestion') askIds.add(b.id);
        else if (answered) calls += 1;
      } else if (b.type === 'tool_result' && askIds.has(b.tool_use_id) && !b.is_error) {
        answered = true;
        calls = 0;
      }
    }
  }
  return answered ? calls : null;
}

function decide(input, root) {
  if (!input || input.tool_name !== 'AskUserQuestion') return null;
  const qs = (input.tool_input && input.tool_input.questions) || [];
  const pats = patterns(root);
  if (!qs.some((q) => isMode(q, pats))) return null;
  let why = '';
  if (qs.length > 1) why = 'the mode question shares this call with other questions — ask the decisions first, run the steps they set off (an edit under an ask rule, a call the classifier holds, a hand step), THEN ask the mode question as its own last call';
  else if (callsSinceLastAnswer(input.transcript_path || '') === 0) why = 'the mode question comes right after answered decisions with no step run since — run what the answers set off first, above all the dialog steps, then ask it; if no answer needs a step, ask it again unchanged';
  if (!why) return null;
  const key = crypto.createHash('sha1').update(JSON.stringify(qs)).digest('hex');
  const sp = path.join(root, '.claude-state', 'mode-question-order.json');
  let st = {};
  try { st = JSON.parse(fs.readFileSync(sp, 'utf8')); } catch (e) { /* first */ }
  if (st.held === key) { try { fs.writeFileSync(sp, JSON.stringify({ passed: key })); } catch (e) { /* ignore */ } return null; }
  try { fs.mkdirSync(path.dirname(sp), { recursive: true }); fs.writeFileSync(sp, JSON.stringify({ held: key })); } catch (e) { /* ignore */ }
  return `MODE-QUESTION-ORDER: ${why}.`;
}

if (require.main === module) {
  let raw = '';
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
    const reason = decide(input, root);
    if (reason) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
    process.exit(0);
  });
}
module.exports = { decide, callsSinceLastAnswer };
