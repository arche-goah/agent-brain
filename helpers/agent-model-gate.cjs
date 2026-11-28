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
 * Every such line is read and the one naming the call's class counts: a brief may quote another (the review form
 * asks the agent to return `Model: <family>`). The `model` parameter counts by family (`claude-sonnet-4-5` = sonnet).
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
// a brief that only quotes the review's return form (`Model: <id>`) has no line of its own (review of #653, round two)
const QUOTED = 'A quoted return-form line without a reason does not count - add your own line:';

function tiers() {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'pr-risk.json'), 'utf8')).tiers || []; } catch (e) { return ['haiku', 'sonnet', 'opus', 'fable']; }
}

/** The class a model word or a `model` parameter names: a full id or a variant counts by its family
 * (`claude-sonnet-4-5`, `sonnet[1m]`, `Sonnet` -> sonnet), empty or "inherit" -> inherit, anything else -> null.
 * Same matching by family as content-review-gate. */
function classOf(word, classes) {
  const w = String(word || '').toLowerCase().trim();
  if (!w || w === 'inherit') return 'inherit';
  return classes.find((c) => w.includes(c)) || null;
}

/** Every Model line of the prompt as { cls, why, word }. A brief may QUOTE another Model line before its own one
 * (the review form of docs/content-review.md asks the agent to return `Model: <family>`), so no single line is
 * "the" line: judge() takes the one that names the call's class. */
function modelLines(prompt, classes) {
  // a list item (`-`, `*`, `1.`), a quote (`>`) and markdown bold (`**Model:**`) are the same line (review of #653, round two)
  const re = /^[ \t>*-]*(?:\d+[.)][ \t]+)?[ \t>*-]*Model(?:[ \t]+choice)?\**:\**[ \t]*([A-Za-z][\w.\-[\]]*)[ \t]*(?:[-—–:,(][ \t]*)?(.*)$/gim;
  const out = [];
  for (let m; (m = re.exec(String(prompt || ''))) !== null;) {
    out.push({ cls: classOf(m[1], classes), why: m[2].replace(/[)\s]+$/, '').trim(), word: m[1] });
  }
  return out;
}

/** null = nothing to say; else the denial text. `out` gets the record of a passing spawn. */
function judge(input, out) {
  if (!input || input.tool_name !== 'Agent') return null;
  const ti = input.tool_input;
  if (!ti || typeof ti !== 'object') return null; // unreadable input fails open, as the header says
  if (String(ti.subagent_type || '').toLowerCase() === 'fork') return null;
  const classes = tiers();
  const called = classOf(ti.model, classes);
  const callWord = ti.model ? String(ti.model) : 'inherit';
  const lines = modelLines(ti.prompt, classes);
  const form = `Model: <${classes.join('|')}|inherit> — <why this class for this task>`;
  if (!lines.length) return `the agent's prompt carries no model line. Every spawn names its model class and why (rules/intelligence.md, Model Routing: "inheriting counts as a choice") - add one line to the prompt:\n  ${form}\nThis call: model ${callWord}.`;
  if (!called) return `the call's model "${callWord}" names no model class (${classes.join(', ')}, inherit) - set the model parameter to a class.`;
  // among the lines of the call's class, the first with a reason: a high-risk review brief quotes a bare
  // `Model: fable` of the SAME class ahead of its own line (re-review of #653, 2026-11-25)
  const line = lines.find((l) => l.cls === called && l.why.length >= MIN_WHY) || lines.find((l) => l.cls === called);
  if (!line) {
    const named = lines.filter((l) => l.cls);
    if (!named.length) return `the model line names "${lines[0].word}", which is no model class (${classes.join(', ')}, inherit).\n  ${form}`;
    const quoted = named.every((l) => l.why.length < MIN_WHY) ? `\n${QUOTED}\n  ${form}` : '';
    return `the model line says ${named.map((l) => l.cls).join(', ')}, the call ${called === 'inherit' ? 'sets no model (it inherits the session\'s)' : 'sets model ' + called}. Reason and call say the same thing - change one of them (every Model line is read; the one naming the call's class counts).${quoted}`;
  }
  // the quoted-line hint only for a bare line (no reason at all); a reason that is merely too short gets the form alone
  // (review of #653, Windows instance 2026-11-28: "Model: opus - judging" was told it was a quoted line)
  if (line.why.length < MIN_WHY) return `the model line gives no reason ("${line.why}"). Say why ${line.cls} fits THIS task: reading and collecting, or judging, verifying, writing.\n${line.why ? '' : `${QUOTED}\n`}  ${form}`;
  if (out) Object.assign(out, { model: line.cls, called: callWord, type: String(ti.subagent_type || 'general-purpose'), why: line.why.slice(0, 300) });
  return null;
}

function main(raw) {
  let input;
  try { input = JSON.parse(String(raw).replace(new RegExp('^' + String.fromCharCode(0xFEFF)), '')); } catch (e) { return ''; } // a BOM must not make a deny-worthy call pass
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
module.exports = { judge, modelLines, classOf };
