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
const { autonomousMode } = require('./autonomous-mode.cjs');

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);

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
  if (!isQuestion && !rule) return null;
  if (!autonomousMode(input.transcript_path || '', root)) return null;
  const what = isQuestion
    ? 'a question through the question tool'
    : `a call that the permission rule \`${rule}\` (ask) turns into a dialog`;
  return `AUTONOMOUS-GATE: the operator ordered this run autonomous, and this is ${what} - it would stop the run on the operator. ` +
    'Not issued. File it with a recommendation in the instance\'s operator-question ledger (the open questions file the ' +
    'session start lists), name it in the next prose report, and go on with everything safely doable. The operator ends ' +
    'the mode by writing without the autonomous word.';
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
