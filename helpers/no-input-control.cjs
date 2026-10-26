#!/usr/bin/env node
/**
 * no-input-control — the AI never drives the human's mouse or keyboard.
 *
 * WHY (operator decision 2026-10-12, point 10 of a collaborator's coherence scan; alpha on a Windows
 * workstation since 2026-09-26, measured 6/6 on 2026-10-26; the operator's word for the core the same day):
 * a tool call that moves the pointer, clicks or types on the machine a person is sitting at acts on THEIR
 * session — the focused window may be a show desk, a chat or a password field. Reading the screen stays
 * allowed; operating it is the person's.
 *
 * PreToolUse. DENIES, with the pattern's reason:
 *   - a tool whose name says it controls the computer (computer-use, remote computer control);
 *   - a command, written file content, edit, workflow script — or the content of a script file a command
 *     runs — that names an input-injection API or library (OS input calls, GUI-automation libraries for
 *     Python and Node, key/mouse automation tools, window messages for keys and mouse buttons).
 * The default patterns are assembled from parts at load time, so that this file, its fixture and its data
 * file do not trip the hook on a machine that runs it (measured 2026-10-26: the alpha blocked edits to its
 * own pattern list and every search for the words).
 *
 * Instance data (optional): <project>/.claude/rules/no-input-control.json
 *   { "patterns": [{"id": "...", "regex": "...", "reason": "..."}],   // additions
 *     "allow":    {"<pattern id>": "<why this brain needs it — a non-empty reason, else ignored>"} }
 * The hook's own files (this helper, its fixture, the instance data file) are never checked as targets.
 */
const fs = require('fs');
const path = require('path');

const j = (...p) => p.join('');
// [id, regex source, reason]; regexes are case-insensitive.
const DEFAULTS = [
  ['py-gui-automation', `\\b(?:${j('py', 'auto', 'gui')}|${j('py', 'nput')}|${j('auto', 'py')})\\b`,
    'a Python library that moves the pointer or types keys'],
  ['py-input-module', `(?:^|[\\s;])(?:import|from)\\s+(?:${j('key', 'board')}|${j('mo', 'use')})\\b`,
    'a Python module that injects key or mouse events'],
  ['node-gui-automation', `\\b(?:${j('robot', 'js')}|${j('nut', '-js')}|@${j('nut', '-tree')})\\b`,
    'a Node library that moves the pointer or types keys'],
  ['macos-events', `\\b(?:${j('CGEvent', 'Post')}|${j('CGEvent', 'Create')}(?:Mouse|Keyboard)Event|${j('cli', 'click')})\\b`,
    'a macOS call or tool that posts mouse or keyboard events'],
  ['applescript-keys', `${j('System ', 'Events')}[\\s\\S]{0,300}\\b(?:${j('key', 'stroke')}|key code|click)\\b`,
    'AppleScript that types or clicks through System Events'],
  ['x11-wayland-tools', `\\b(?:${j('xdo', 'tool')}|${j('ydo', 'tool')}|${j('wty', 'pe')})\\b`,
    'a Linux tool that injects key or mouse events'],
  ['windows-input', `\\b(?:${j('Send', 'Input')}|${j('keybd', '_event')}|${j('mouse', '_event')}|${j('SetCursor', 'Pos')}|${j('Send', 'Keys')}|${j('Auto', 'Hotkey')})\\b|\\b${j('WM', '_')}(?:KEY(?:DOWN|UP)|[LRM]BUTTON(?:DOWN|UP))\\b`,
    'a Windows call or tool that injects key or mouse input'],
];
const TOOL_NAME = /(?:^|__)computer[-_]?use(?:__|$)|(?:^|__)computer_(?:click|type|key|move|drag|scroll|mouse)|remote-devices__computer/i;
const OWN_FILES = /(?:^|[\\/])(?:no-input-control\.cjs|test-no-input-control\.sh|no-input-control\.json)$/;
const SCRIPT_EXT = /\.(?:py|js|cjs|mjs|sh|ps1|ahk|applescript|scpt)$/i;

function loadInstance(projectDir) {
  const fp = projectDir && path.join(projectDir, '.claude', 'rules', 'no-input-control.json');
  if (!fp || !fs.existsSync(fp)) return { patterns: [], allow: {} };
  try {
    const d = JSON.parse(fs.readFileSync(fp, 'utf8'));
    const allow = {};
    for (const [id, why] of Object.entries(d.allow || {})) if (String(why || '').trim()) allow[id] = String(why);
    const patterns = [];
    for (const p of d.patterns || []) {
      try { patterns.push([String(p.id), new RegExp(p.regex, 'i'), String(p.reason || 'instance pattern')]); } catch (e) {
        process.stderr.write(`no-input-control: unreadable instance pattern ${p.id}: ${e.message}\n`);
      }
    }
    return { patterns, allow };
  } catch (e) {
    process.stderr.write('no-input-control: unreadable no-input-control.json: ' + e.message + '\n');
    return { patterns: [], allow: {} };
  }
}

function texts(toolName, ti, cwd) {
  const out = [];
  if (!ti || typeof ti !== 'object') return out;
  const target = ti.file_path || ti.notebook_path || '';
  if (target && OWN_FILES.test(target)) return out;
  // Not an agent's prompt: a brief that NAMES an API is text about it, not a call (the alpha checked
  // command, content, new_string and script).
  for (const k of ['command', 'content', 'new_string', 'new_source', 'script']) {
    if (typeof ti[k] === 'string') out.push(ti[k]);
  }
  for (const e of Array.isArray(ti.edits) ? ti.edits : []) if (e && typeof e.new_string === 'string') out.push(e.new_string);
  // A command that runs a script file: the file's content counts as if it were typed here.
  if (typeof ti.command === 'string') {
    for (const tok of ti.command.split(/[\s;&|()<>"'`]+/)) {
      if (!SCRIPT_EXT.test(tok) || OWN_FILES.test(tok)) continue;
      const fp = path.isAbsolute(tok) ? tok : path.join(cwd || process.cwd(), tok);
      try { if (fs.statSync(fp).size < 2_000_000) out.push(fs.readFileSync(fp, 'utf8')); } catch (e) { /* not a file */ }
    }
  }
  return out;
}

function check(toolName, toolInput, cwd, instance) {
  const inst = instance || { patterns: [], allow: {} };
  if (TOOL_NAME.test(toolName || '') && !inst.allow['computer-control-tool']) {
    return { id: 'computer-control-tool', reason: 'a tool that controls the computer the person is sitting at' };
  }
  const pats = DEFAULTS.map(([id, src, reason]) => [id, new RegExp(src, 'i'), reason]).concat(inst.patterns);
  for (const text of texts(toolName, toolInput, cwd)) {
    for (const [id, re, reason] of pats) {
      if (!inst.allow[id] && re.test(text)) return { id, reason };
    }
  }
  return null;
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  let data;
  try { data = JSON.parse(input); } catch (e) { return console.log('{}'); }
  const cwd = data.cwd || process.env.CLAUDE_PROJECT_DIR;
  const hit = check(data.tool_name, data.tool_input, cwd, loadInstance(process.env.CLAUDE_PROJECT_DIR || cwd));
  if (!hit) return console.log('{}');
  console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: `no-input-control [${hit.id}]: ${hit.reason} — the AI never operates the person's mouse `
      + 'or keyboard; reading the screen is fine. A brain that needs this declares it in .claude/rules/no-input-control.json '
      + '("allow": {"<id>": "<why>"}).' } }));
}

if (require.main === module) main();
else module.exports = { check, loadInstance, DEFAULTS };
