#!/usr/bin/env node
/**
 * PreToolUse hook: while the operator's autonomous order runs, no call may stop on the operator —
 * neither a question through the question tool nor a call that a permission `ask` rule turns into a
 * dialog. Both are refused here, before the harness can show anything, with the instruction to file
 * the step in the instance's operator-question ledger and go on with what is safely doable.
 *
 * WHY (measured 2026-10-26 on the Windows instance, in an autonomous run the operator had ordered in
 * words): an edit of `.claude/settings.json` (ask rule of the core template) raised a dialog, and the
 * operator answered (translated) "got an interactive question again ... it should have been collected".
 * The rule existed as prose only (an instance rule of 2026-10-18 and skill collab-watch: "an action
 * that may raise a prompt is not issued"); the operator then asked whether that was a loose promise or
 * anchored, and ordered (translated): "mechanical and reliable - no feedback entry somewhere and hoping
 * it holds". The question-tool half was an instance alpha (autonomous-question-gate, 2026-10-19) that
 * no other brain had.
 *
 * Mode: `autonomous-mode.cjs` (a latch: an on-word sets it; an off-word or asking what is open clears it;
 * instance words in `.claude/rules/autonomous-patterns.json`). Outside that mode this hook is silent.
 * Ask rules: `permissions.ask` of the project's `.claude/settings.json`, `.claude/settings.local.json`
 * and the user's settings, matched the way the harness reads them: `Tool` alone matches the tool;
 * `Bash(…)` / `PowerShell(…)` a glob over the whole command (`*` any text, a trailing `:*` = ` *`);
 * `Edit(…)` / `Write(…)` / `Read(…)` a path glob (`**` any depth, `*` one segment) against the path
 * relative to the project, or absolute. The cheap rule match runs first; the transcript is read only
 * when a rule or the question tool is hit.
 * Output: {"hookSpecificOutput": {"permissionDecision": "deny", ...}}. Fails open on unreadable input.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { autonomousMode, promptModes } = require('./autonomous-mode.cjs');

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
// Hook and permission data: the auto-mode classifier holds an edit of these for the operator even
// where no ask rule names it (macOS instance, 2026-10-26: two edits of stop-checks.json waited 2728 s
// and 4233 s on the operator under an `Edit(.claude/rules/**)` allow rule; local-machinery.json and a
// new file under scripts/hooks/ in the same turn went through).
const CLASSIFIER_HELD = ['Edit(.claude/settings.json)', 'Edit(.claude/settings.local.json)', 'Edit(.mcp.json)',
  'Edit(.claude/rules/stop-checks.json)', 'Edit(.claude/rules/mechanism-rules.json)', 'Edit(**/hooks/hooks.json)'];

// The words this gate decides by. A run must not change them: measured 2026-10-28 on the macOS
// instance, after this gate refused a question the AI widened the instance's ask patterns until
// the refused question passed (taken back the same turn) - a refusal undone through the gate's own
// data. Ordered by the operator the same day: inside the run these files are locked; they change
// in the conversation with the operator.
const OWN_WORDS = ['Edit(.claude/rules/autonomous-patterns.json)', 'Edit(.claude/rules/open-items.json)'];

// The way out stays open (measured 2026-11-01 on the macOS instance): the operator wrote "continue
// interactively" (translated) twice, no off-pattern matched that word order, the run stayed autonomous,
// and the lock refused the edit that would have taught the list those words - the operator could not
// leave the mode in their own words. An edit passes the lock only when it ADDS off-patterns
// (autonomous-patterns.json) or ask-patterns (open-items.json), each new pattern matches the operator's
// LATEST prompt and none of the prompts that switched the run on, and nothing else changes but
// `_`-prefixed notes and cases. The 2026-10-28 incident (patterns widened until a refused question
// passed) matched no operator prompt and stays held.
const WAY_OUT_KEY = { 'autonomous-patterns.json': 'off_patterns', 'open-items.json': 'ask_patterns' };

function applyEdit(before, tool, input) {
  if (tool === 'Write') return typeof input.content === 'string' ? input.content : null;
  const edits = tool === 'MultiEdit' ? input.edits : [input];
  let s = before;
  for (const e of Array.isArray(edits) ? edits : []) {
    if (!e || typeof e.old_string !== 'string' || typeof e.new_string !== 'string' || !s.includes(e.old_string)) return null;
    s = e.replace_all ? s.split(e.old_string).join(e.new_string) : s.replace(e.old_string, () => e.new_string);
  }
  return s;
}

function stripNotes(o) {
  const out = {};
  for (const k of Object.keys(o || {})) if (!k.startsWith('_')) out[k] = o[k];
  return out;
}

/** true when this edit of the run's own words only teaches them what the operator said in this session. */
function wayOut(tool, input, root, transcriptPath) {
  const file = norm(input.file_path || '');
  const key = WAY_OUT_KEY[path.basename(file)];
  if (!key) return false;
  const abs = path.isAbsolute(file) || /^[A-Za-z]:\//.test(file) ? file : path.join(root, file);
  let raw; let before; let after;
  try { raw = fs.readFileSync(abs, 'utf8'); before = JSON.parse(raw); } catch (e) { return false; }
  try { after = JSON.parse(applyEdit(raw, tool, input)); } catch (e) { return false; }
  const old = Array.isArray(before[key]) ? before[key] : [];
  const neu = Array.isArray(after[key]) ? after[key] : [];
  if (!old.every((p) => neu.includes(p))) return false;
  const added = neu.filter((p) => !old.includes(p));
  if (!added.length) return false;
  const a = stripNotes(after); const b = stripNotes(before);
  delete a[key]; delete b[key];
  if (JSON.stringify(a) !== JSON.stringify(b)) return false;
  // The operator's LATEST prompt is what the list is taught; a pattern that also matches a prompt which
  // switched the run on would end the operator's own order (too broad - "\bthe\b"), so it stays held.
  const said = promptModes(transcriptPath, root).filter((m) => !m.answer);
  if (!said.length) return false;
  const last = said[said.length - 1].text;
  const orders = said.filter((m, i) => m.autonomous && !(i > 0 && said[i - 1].autonomous)).map((m) => m.text);
  return added.every((p) => {
    let rx; try { rx = new RegExp(p, 'iu'); } catch (e) { return false; }
    return rx.test(last) && !orders.some((t) => rx.test(t));
  });
}

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return null; }
}

function askRules(root) {
  const cfg = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  const files = [path.join(root, '.claude', 'settings.json'), path.join(root, '.claude', 'settings.local.json'),
    path.join(cfg, 'settings.json')];
  const out = [];
  for (const f of files) {
    const s = readJson(f);
    for (const r of ((s && s.permissions && s.permissions.ask) || [])) if (typeof r === 'string') out.push(r);
  }
  return out;
}

function globToRegex(glob, pathMode) {
  let g = glob;
  if (!pathMode && g.endsWith(':*')) g = `${g.slice(0, -2)} *`;
  let rx = '';
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '*') {
      if (pathMode && g[i + 1] === '*') { rx += '.*'; i++; if (g[i + 1] === '/') i++; } else rx += pathMode ? '[^/]*' : '[\\s\\S]*';
    } else rx += c.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${rx}$`, pathMode ? 'i' : '');
}

function norm(p) { return String(p || '').replace(/\\/g, '/'); }

/** The first ask rule this call hits, or null. */
function hitRule(rules, tool, input, root) {
  for (const r of rules) {
    const m = /^([A-Za-z_][\w-]*)(?:\((.*)\))?$/s.exec(r.trim());
    if (!m) continue;
    const [, name, arg] = m;
    const edit = EDIT_TOOLS.has(tool) && name === 'Edit';
    if (name !== tool && !edit) continue;
    if (arg === undefined || arg === '*' || arg === '') return r;
    if (tool === 'Bash' || tool === 'PowerShell') {
      if (globToRegex(arg, false).test(String(input.command || '').trim())) return r;
    } else if (EDIT_TOOLS.has(tool) || tool === 'Read') {
      const file = norm(input.file_path || input.notebook_path);
      const rel = path.isAbsolute(file) || /^[A-Za-z]:\//.test(file) ? norm(path.relative(root, file)) : file;
      const pat = norm(arg).replace(/^\.\//, '');
      if (globToRegex(pat, true).test(rel) || globToRegex(pat, true).test(file)) return r;
    }
  }
  return null;
}

function judge(input) {
  const tool = input.tool_name || '';
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const isQuestion = tool === 'AskUserQuestion';
  const rule = isQuestion ? null : hitRule(askRules(root), tool, input.tool_input || {}, root);
  const held = isQuestion || rule ? null : hitRule(CLASSIFIER_HELD, tool, input.tool_input || {}, root);
  const own = isQuestion ? null : hitRule(OWN_WORDS, tool, input.tool_input || {}, root);
  if (!isQuestion && !rule && !held && !own) return null;
  if (!autonomousMode(input.transcript_path || '', root)) return null;
  if (own && wayOut(tool, input.tool_input || {}, root, input.transcript_path || '')) return null;
  if (own) {
    return `AUTONOMOUS-GATE: \`${own}\` holds the words this gate decides by, and the run is autonomous - a run does not change ` +
      'the data of the gate that holds it (a refusal undone through the gate\'s data is a refusal re-issued). Not issued. ' +
      'File the change with its reason in the operator-question ledger (a patch file beside it); it is made in the conversation.';
  }
  const what = isQuestion ? 'a question through the question tool'
    : rule ? `a call that the permission rule \`${rule}\` (ask) turns into a dialog`
      : `an edit of hook or permission data (\`${held}\`) that the auto-mode classifier holds for the operator`;
  return `AUTONOMOUS-GATE: the operator ordered this run autonomous, and this is ${what} - it would stop the run on the operator. ` +
    'Not issued. File it with a recommendation in the instance\'s operator-question ledger (the open questions file the ' +
    'session start lists; an edit as a patch file beside it), name it in the next prose report, and go on with everything ' +
    'safely doable. The mode ends when the operator asks what is open or says an off-word.';
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let reason = null;
    try { reason = judge(JSON.parse(raw)); } catch (e) { reason = null; }
    if (reason) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
    }
    process.exit(0);
  });
}

module.exports = { judge, hitRule, globToRegex };
