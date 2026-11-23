#!/usr/bin/env node
/**
 * agent-model-gate — a spawned agent names its model class and why (PreToolUse on Agent).
 *
 * WHY: `rules/intelligence.md`, Model Routing, says "Before EVERY agent spawn … evaluate the model class …
 * inheriting counts as a choice". Nothing carried it: measured 2026-11-23 on a macOS instance, the only hook on an
 * Agent call was the conditional-order gate, which reads the operator's condition words, not the model. A session
 * had just started ten agents with a deliberate split (six readers on a small model, four judging ones on the
 * session model) and the operator asked whether that deliberation is anchored anywhere - it stood in the session's
 * reasoning and nowhere a reader could find it. Ordered by that operator as a normal core change.
 *
 * What it asks of an Agent call: one line in the prompt
 *     Model: <haiku|sonnet|opus|fable|inherit> — <why this class for this task>
 * - no such line: denied, with the rule in one sentence;
 * - the line names another class than the call's `model` parameter (or names a class while the call inherits, or
 *   says inherit while the call sets one): denied - the reason and the call say the same thing;
 * - a reason shorter than MIN_WHY characters ("ok", "n/a"): denied.
 * Not asked: `subagent_type: "fork"` (a fork always runs on the parent's model, the parameter is ignored).
 * What it records: one line per spawn that passes, in <project>/.claude-state/agent-spawns.jsonl (model class,
 * agent type, the reason) - calls without a session id (fixtures) write nothing.
 *
 * It checks that a choice was written down and agrees with the call. Whether the choice is RIGHT is a judgment;
 * the record is what a review reads for that. Class names come from pr-risk.json `tiers` (one list with the
 * content-review gate). Fails open on unreadable input.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const MIN_WHY = 12;

function tiers() {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'pr-risk.json'), 'utf8')).tiers || []; } catch (e) { return ['haiku', 'sonnet', 'opus', 'fable']; }
}

/** { cls, why } of the prompt's Model line, or null. */
function modelLine(prompt, classes) {
  const m = /^[ \t>*-]*Model(?:[ \t]+choice)?:[ \t]*([A-Za-z]+)\b[ \t]*(?:[-—–:,(][ \t]*)?(.*)$/im.exec(String(prompt || ''));
  if (!m) return null;
  const cls = m[1].toLowerCase();
  return classes.includes(cls) || cls === 'inherit' ? { cls, why: m[2].replace(/[)\s]+$/, '').trim() } : { cls: null, why: m[2].trim(), word: m[1] };
}

/** null = nothing to say; else the denial text. `out` gets the record of a passing spawn. */
function judge(input, out) {
  if (!input || input.tool_name !== 'Agent') return null;
  const ti = input.tool_input || {};
  if (String(ti.subagent_type || '') === 'fork') return null;
  const classes = tiers();
  const called = ti.model ? String(ti.model).toLowerCase() : 'inherit';
  const line = modelLine(ti.prompt, classes);
  const form = `Model: <${classes.join('|')}|inherit> — <why this class for this task>`;
  if (!line) return `the agent's prompt carries no model line. Every spawn names its model class and why (rules/intelligence.md, Model Routing: "inheriting counts as a choice") - add one line to the prompt:\n  ${form}\nThis call: model ${called}.`;
  if (!line.cls) return `the model line names "${line.word}", which is no model class (${classes.join(', ')}, inherit).\n  ${form}`;
  if (line.cls !== called) return `the model line says ${line.cls}, the call ${called === 'inherit' ? 'sets no model (it inherits the session\'s)' : 'sets model ' + called}. Reason and call say the same thing - change one of them.`;
  if (line.why.length < MIN_WHY) return `the model line gives no reason ("${line.why}"). Say why ${line.cls} fits THIS task: reading and collecting, or judging, verifying, writing.`;
  if (out) Object.assign(out, { model: line.cls, type: String(ti.subagent_type || 'general-purpose'), why: line.why.slice(0, 300) });
  return null;
}

function main(raw) {
  let input;
  try { input = JSON.parse(raw); } catch (e) { return ''; }
  const rec = {};
  let deny;
  try { deny = judge(input, rec); } catch (e) { return ''; }
  if (deny) return JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: 'AGENT-MODEL: ' + deny } });
  if (rec.model && input.session_id) {
    try {
      const dir = path.join(process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd(), '.claude-state');
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, 'agent-spawns.jsonl'), JSON.stringify({ at: new Date().toISOString(), session: input.session_id, agent: input.agent_id || null, ...rec }) + '\n');
    } catch (e) { /* the record is no reason to hold a spawn */ }
  }
  return '';
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => { const o = main(raw); if (o) process.stdout.write(o); });
}
module.exports = { judge, modelLine };
