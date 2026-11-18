#!/usr/bin/env node
/**
 * Prompt classifier (OPT-IN hook): the operator's intent per prompt, read by a model, written as a record that
 * the gates read. Hook: async UserPromptSubmit, and PostToolUse on AskUserQuestion (an answer in the question
 * tool reaches no UserPromptSubmit hook).
 *
 * WHY: the gates that decide "the operator asks what is open", "this is a correction", "the first message orders
 * work" read word lists, and word lists miss paraphrase, word order and every language the brain has no data for.
 * Ported from an instance alpha (2026-10-28 .. 2026-11-18). Hand-judged sample of 40 disagreements per field on the
 * macOS instance, 2026-11-18 (model right / decided): asks_open 32/35, correction 30/37, orders_task 32/33; mode_on
 * gave no gain (all eight model errors were false trues) - the prompt below names those cases instead. Operator decision 2026-11-18 (question tool): a record of
 * THIS prompt decides those three fields (autonomous-mode.cjs `modelSays` / `intentFor`), no record = the words;
 * mode_on, mode_off and condition keep the reading they had (autonomous-mode.cjs, conditional-order-gate.cjs).
 *
 * One `claude -p` call per operator prompt with all hooks off (no recursion; INTENT_CLASSIFIER_CHILD as a second
 * guard), cwd outside the brain (the nested call writes a transcript of its own, which history readers would take
 * for an operator prompt). Appends {at, mode, session, words, model, differ, prompt} to
 * .claude-state/intent-classifier.jsonl. `model: null` = the call failed; a reader then falls back to the words.
 * Fails open, never blocks. Background notices, hook echoes and peer or agent messages are not classified.
 *
 * Opt-in, not in hooks/hooks.json: every prompt costs a model call. Wire it in the brain's .claude/settings.json:
 *   UserPromptSubmit: {"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/core/helpers/intent-classifier.cjs\"","async":true}
 *   PostToolUse, matcher AskUserQuestion: the same command.
 * Env: INTENT_CLASSIFIER_MODEL (default sonnet - the small model flipped between runs on the mode cases),
 * INTENT_CLASSIFIER_BIN (default claude), INTENT_CLASSIFIER_LOG.
 * Replay: `node intent-classifier.cjs --replay [N]` - the newest N operator prompts of this brain's transcripts
 * through both readers; prints every disagreement and a count.
 * Fixture: scripts/test-intent-classifier.sh.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { isNotification, projectTranscriptDir } = require('./turn-kind.cjs');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const LOG = process.env.INTENT_CLASSIFIER_LOG || path.join(ROOT, '.claude-state', 'intent-classifier.jsonl');
const MODEL = process.env.INTENT_CLASSIFIER_MODEL || 'sonnet';
const BIN = process.env.INTENT_CLASSIFIER_BIN || 'claude';
const KEYS = ['asks_open', 'mode_on', 'mode_off', 'correction', 'condition', 'orders_task'];

const INSTRUCTION = `Classify the operator's message to an AI assistant. Answer with ONE line of JSON and nothing else:
{"asks_open": bool, "mode_on": bool, "mode_off": bool, "correction": bool, "condition": bool, "orders_task": bool}
asks_open: the operator asks what is open, pending or needed from them, or asks for the open questions or decisions to be put
  to them now ("any other open questions to me now", "what do you need from me") (any wording, any language).
  TRUE also when an order to go on working asks in the same message for the questions that block the work ("go on with the
  open points; questions to me that block your work, please") - asks_open true, mode_on false.
  FALSE when the message orders the assistant to work through open points itself ("work through all open points autonomously"),
  and FALSE for a complaint or correction about an answer ("I asked you, that is no answer") - that is no ask.
  FALSE when the operator challenges whether a question to them was needed at all ("why do you really need my word for that?")
  - a correction about asking, it wants FEWER questions.
  FALSE for a factual question about a NAMED thing - what is not yet ordered, which deadline falls on a date, what a file says
  ("what is not ordered yet? and which deadline is on the 18th?") - it wants information, not the questions or decisions
  for the operator; "not yet" or "open" inside such a question does not make it one.
mode_on: the operator ORDERS the assistant to work on its own without asking, now (not a mention, not a question about it).
  The short word "auto mode" at the start of the message is such an order; "ask mode" is never one.
  FALSE when "autonomous" only settles the default or start setting ("keep the default autonomous", "start sessions
  autonomous"), and FALSE whenever the same message asks for the open questions to be put to them now.
  FALSE when the operator only leaves HOW a task is solved to the assistant ("do it the way it makes sense, I don't care how").
  FALSE when the operator says that no OK of a THIRD party is needed ("we own this, so we need not wait for an OK").
  FALSE when the message is a complaint, finding or demand about the WORK itself and says nothing about working without asking.
  FALSE when the operator approves or orders a set of WORK - a yes to "shall I handle these items?", "work through all of
  it", "really everything that can be done, please", "explore the failure class at the root and fix it if possible" - that
  releases tasks, it does not order working without asking; the operator stays reachable for questions (2026-11-18: read
  as mode_on, the session went autonomous and the question tool was refused).
  FALSE when the operator complains that the assistant stood still, stopped, or asked too much ("standstill again, for no
  reason", "why do you do all this only after being asked several times?") - a correction about the work, not the mode.
  FALSE for a report that something asked interactively during auto mode, and for a question about what a go would do
  ("the settings change came up interactively in auto mode", "if I give the go, will there be interactive prompts again?").
  FALSE when the operator explains or checks what the INTERACTIVE mode means while staying in it.
  TRUE when the operator complains that the assistant switched to interactive by itself, or is NOT working autonomously
  although autonomy was ordered - such a message is a correction AND mode_on, both true.
  TRUE when the order is limited to a scope or a role ("work only these tasks on your own").
mode_off: the operator ends that autonomous mode - the short word "ask mode" always does; or orders interactive or normal work
  again ("continue interactively", "normal mode", "not autonomous anymore"), or says they are back.
  TRUE when the operator says the switch to autonomous was wrong or not wanted, or asks to be set back to interactive
  ("you switched to autonomous mode, that was not the goal", "set it back to interactive now", "autonomous is not wanted
  right now") - 2026-11-18.
  FALSE when the message reports or complains that the assistant switched to interactive by itself.
correction: the operator says the ASSISTANT did something wrong, missed something, or repeats a complaint about the assistant's
  work. FALSE when something else went wrong (a supplier, a device, a print, the operator's own mistake), FALSE for a plain order,
  a question, or an answer chosen in the question tool.
condition: the operator ties a step to an event that must come first ("merge it once CI is green", "clear it with X, then ...") -
  not a word order ("first A, then B" describing a layout), not a reason, not a description of the past.
orders_task: the operator orders work to be done now (build, fix, check, merge, write ...) - not a greeting, not a status question.

Message:
`;

// Not the operator's words; isNotification covers the frames, these cover the rest the hook sees.
const NOT_OPERATOR = /^\s*(<task-notification|<system-reminder|<agent-message|Stop hook feedback|\[SYSTEM NOTIFICATION|# Autonomous loop|<command-|Another Claude session|<cross-session-message|\[Cross-session )/;

function rxOf(file, key, flags) {
  try {
    const list = JSON.parse(fs.readFileSync(path.join(ROOT, '.claude', 'rules', file), 'utf8'))[key] || [];
    return list.length ? new RegExp(list.join('|'), flags) : null;
  } catch (e) { return null; }
}

/** The words' verdict, for the measurement only (the gates compute their own). correction, condition and orders_task
 *  from the brain's data files; their English built-ins live in the gates that run on stdin and export nothing. */
function wordVerdict(text) {
  let w;
  try { w = require('./autonomous-mode.cjs').words(ROOT); } catch (e) { return null; }
  const t = (rx) => (rx ? rx.test(text) : null);
  return { asks_open: w.ask.test(text), mode_on: w.on.test(text), mode_off: w.off.test(text),
    correction: t(rxOf('root-cause-patterns.json', 'correction_patterns', 'iu')),
    condition: t(rxOf('condition-patterns.json', 'condition_patterns', 'iu')),
    orders_task: t(rxOf('start-report-patterns.json', 'order_patterns', 'i')) };
}

/** The command that starts `bin`, without a shell. A .cjs/.js stub runs through node (the fixture's stand-in for the
 *  model on every OS). On Windows an npm install leaves `claude.cmd`, which spawnSync cannot start without a shell
 *  (Windows review of #594, 2026-11-18: `spawnSync('claude')` returned ENOENT, every record was `model: null`, silently);
 *  so a `claude.exe` on PATH wins, and otherwise the shim's own target runs: node with the cli.js next to the .cmd. */
function resolveBin(bin, platform = process.platform, pathEnv = process.env.PATH || '') {
  if (/\.c?js$/.test(bin)) return [process.execPath, [bin]];
  if (platform !== 'win32' || /[\\/]/.test(bin) || /\.(exe|cmd)$/i.test(bin)) return [bin, []];
  const dirs = pathEnv.split(path.delimiter).filter(Boolean);
  for (const d of dirs) { const exe = path.join(d, `${bin}.exe`); if (fs.existsSync(exe)) return [exe, []]; }
  for (const d of dirs) {
    if (!fs.existsSync(path.join(d, `${bin}.cmd`))) continue;
    const cli = path.join(d, 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
    if (fs.existsSync(cli)) return [process.execPath, [cli]];
  }
  return [bin, []];
}

function modelVerdict(text) {
  const args = ['-p', '--model', MODEL, '--settings', '{"disableAllHooks": true}'];
  // a .cjs/.js stub runs through node - the fixture's stand-in for the model on every OS (no shebang on Windows)
  const [cmd, pre] = resolveBin(BIN);
  const r = spawnSync(cmd, [...pre, ...args], {
    input: INSTRUCTION + text.slice(0, 4000), encoding: 'utf8', timeout: 60000, cwd: os.tmpdir(),
    env: { ...process.env, INTENT_CLASSIFIER_CHILD: '1' },
  });
  if (r.status !== 0) return null;
  const m = /\{[^{}]*\}/.exec(r.stdout || '');
  if (!m) return null;
  try {
    const o = JSON.parse(m[0]);
    return Object.fromEntries(KEYS.map((k) => [k, o[k] === true]));
  } catch (e) { return null; }
}

function differ(a, b) {
  return a && b ? KEYS.filter((k) => a[k] !== null && a[k] !== undefined && a[k] !== b[k]) : [];
}

function log(o) {
  try {
    fs.mkdirSync(path.dirname(LOG), { recursive: true });
    fs.appendFileSync(LOG, JSON.stringify({ at: new Date().toISOString(), ...o }) + '\n');
  } catch (e) { /* logging never blocks */ }
}

/** The operator prompts of one transcript (plain text records only - no tool results, no hook echoes). */
function prompts(file) {
  const out = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    let d; try { d = JSON.parse(line); } catch (e) { continue; }
    const m = d && d.message;
    if (!m || m.role !== 'user' || d.isMeta) continue;
    const t = typeof m.content === 'string' ? m.content
      : Array.isArray(m.content) && m.content.every((b) => b.type === 'text') ? m.content.map((b) => b.text).join('\n') : null;
    if (!t || NOT_OPERATOR.test(t) || isNotification(t)) continue;
    out.push({ when: d.timestamp || '', text: t });
  }
  return out;
}

function replay(n) {
  const dir = projectTranscriptDir(ROOT);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(dir, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  const all = [];
  for (const f of files) { for (const p of prompts(f)) all.push(p); if (all.length >= n * 3) break; }
  all.sort((a, b) => (a.when < b.when ? 1 : -1));
  let seen = 0, dis = 0, failed = 0;
  for (const p of all.slice(0, n)) {
    const w = wordVerdict(p.text), m = modelVerdict(p.text);
    seen++;
    if (!m) { failed++; continue; }
    const d = differ(w, m);
    if (d.length) {
      dis++;
      console.log(`${p.when.slice(0, 16)} | ${d.map((k) => `${k}: words=${w[k]} model=${m[k]}`).join(', ')} | "${p.text.replace(/\s+/g, ' ').slice(0, 90)}"`);
    }
    log({ mode: 'replay', when: p.when, words: w, model: m, differ: d });
  }
  console.log(`intent replay: ${seen} prompts · model unreadable ${failed} · words and model disagree ${dis}`);
}

/** The operator's answers in the question tool as one text; each answer keeps its question and its note. */
function answerText(inp) {
  const r = (inp && (inp.tool_response || inp.tool_input)) || {};
  const answers = r.answers || (inp && inp.tool_input && inp.tool_input.answers) || {};
  const notes = r.annotations || (inp && inp.tool_input && inp.tool_input.annotations) || {};
  return Object.entries(answers).map(([q, a]) => {
    const n = notes[q] && notes[q].notes ? `\nNote: ${notes[q].notes}` : '';
    return `Question: ${q}\nAnswer: ${a}${n}`;
  }).join('\n\n');
}

module.exports = { resolveBin, wordVerdict, modelVerdict, differ, prompts, answerText };

if (require.main === module) {
  const a = process.argv.slice(2);
  if (a[0] === '--replay') replay(parseInt(a[1] || '40', 10));
  else {
    if (process.env.INTENT_CLASSIFIER_CHILD) process.exit(0);
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { data += c; });
    process.stdin.on('end', () => {
      try {
        const inp = JSON.parse(data || '{}');
        // mode "answer": no gate reads it yet (they read mode "hook")
        const answer = inp.tool_name === 'AskUserQuestion';
        const text = answer ? answerText(inp) : String(inp.prompt || '');
        if (!text.trim()) process.exit(0);
        if (!answer && (NOT_OPERATOR.test(text) || isNotification(text))) process.exit(0);
        const w = wordVerdict(text), m = modelVerdict(text);
        log({ mode: answer ? 'answer' : 'hook', session: inp.session_id, words: w, model: m, differ: differ(w, m), prompt: text.slice(0, 160) });
      } catch (e) { /* never blocks */ }
      process.exit(0);
    });
  }
}
