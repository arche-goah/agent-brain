#!/usr/bin/env node
/**
 * skill-gate.cjs — PreToolUse: a tool whose skill says "load me first" is not called before
 * that skill has been loaded IN THIS SESSION.
 *
 * WHY (operator order on a proving instance, 2026-10-10): 21 sessions built TouchDesigner
 * networks through the TD MCP server and not one of them loaded a TD skill — the node
 * placement grid the operator had asked for lived in a skill nobody read. Measured cause,
 * three layers deep:
 *  1. Claude Code keeps only ~1 % of the context window for the skill LISTING. On overflow it
 *     drops descriptions, least-invoked first (code.claude.com/docs/en/skills, "Skill
 *     descriptions are cut short"). A skill never invoked loses its description first, so
 *     the model never sees its triggers, so it is never invoked: a closed loop.
 *  2. A SKILL.md whose frontmatter is not valid YAML loads with NO description at all
 *     (same page, troubleshooting). Four suite skills had a plain scalar with ": " in it.
 *  3. Nothing outside the skill enforced it. The docs say it in one line: "a rule that must
 *     hold every time — move it into a hook".
 * Matching a description is judgement and stays with the model. Which TOOL needs which
 * skill is a fact, and a fact gets a gate.
 *
 * WHO DECLARES, two sources, read on every call (new skills need no registration):
 *  (a) the skill itself, in its frontmatter under `metadata` (the one block every skill host
 *      accepts; unknown top-level keys are ignored by Claude Code and rejected elsewhere):
 *        metadata:
 *          load-before-tools: "^mcp__touchdesigner(-\\d+)?__"   # regex on the tool name
 *          load-before-paths: "\\.(py|js)$"                      # optional: regex on the file path
 *  (b) the instance, for skills it does not own (core or third-party plugins):
 *        <project>/.claude/rules/skill-gate.json
 *        { "rules": [ { "skills": ["brain-core:ponytail"], "tools": "^(Edit|Write|MultiEdit)$",
 *                       "paths": "\\.(py|cjs|js|ts|sh)$" } ] }
 *      Template: templates/rules-instance/skill-gate.json (ships with no rules).
 * Skills are found where Claude Code finds them: <project>/.claude/skills, ~/.claude/skills,
 * and every plugin in ~/.claude/plugins/installed_plugins.json that is installed for this
 * project (or user scope) and enabled in a settings layer. Plugin skills are named
 * `<plugin>:<skill>`, exactly as the Skill tool takes them.
 *
 * WHAT COUNTS AS LOADED: in this session's transcript, a Skill tool call with that name
 * (qualified or bare), a `/<name>` slash command, or a Read of that SKILL.md (a subagent
 * without the Skill tool can still satisfy the gate). Per transcript, so a subagent loads
 * for itself.
 *
 * Fail-open on everything that is not a declared rule (no transcript, unreadable files,
 * broken config — logged to .claude-state/skill-gate.log): a gate must never take the
 * session hostage over its own plumbing. No bypass marker: loading a skill is one call.
 * The settings matcher must cover every declared tool; the template wires `.*`.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const HOME = process.env.SKILL_GATE_HOME || os.homedir();
const LOG = path.join(ROOT, '.claude-state', 'skill-gate.log');

function log(line) {
  try { fs.appendFileSync(LOG, `${new Date().toISOString()} ${line}\n`); } catch (_) {}
}
function readJson(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; } }
function rx(s) { try { return s ? new RegExp(String(s), 'i') : null; } catch (_) { log(`BAD-REGEX ${s}`); return null; } }
function same(a, b) {
  const r = (p) => path.resolve(String(p));
  return process.platform === 'win32' ? r(a).toLowerCase() === r(b).toLowerCase() : r(a) === r(b);
}

/** The two metadata keys, read from the frontmatter without a YAML library. */
function declared(text) {
  if (!text.startsWith('---')) return null;
  const end = text.indexOf('\n---', 3);
  if (end === -1) return null;
  const out = {};
  let inMeta = false;
  for (const line of text.slice(3, end).split(/\r?\n/)) {
    if (/^\S/.test(line)) { inMeta = /^metadata:\s*$/.test(line); continue; }
    if (!inMeta) continue;
    const m = line.match(/^\s+(load-before-tools|load-before-paths):\s*(.+?)\s*$/);
    if (!m) continue;
    let v = m[2];
    if (/^".*"$/.test(v)) { try { v = JSON.parse(v); } catch (_) { v = v.slice(1, -1); } }
    else if (/^'.*'$/.test(v)) v = v.slice(1, -1).replace(/''/g, "'");
    out[m[1]] = v;
  }
  return out['load-before-tools'] ? out : null;
}

function enabledPlugins() {
  // Lowest layer first, so a higher layer's false wins.
  const layers = [path.join(HOME, '.claude', 'settings.json'),
    path.join(ROOT, '.claude', 'settings.json'), path.join(ROOT, '.claude', 'settings.local.json')];
  const on = {};
  for (const p of layers) Object.assign(on, (readJson(p) || {}).enabledPlugins || {});
  return on;
}

/** [{ name, file }] for every skill Claude Code would load in this project. */
function skillFiles() {
  const out = [];
  const scan = (dir, prefix) => {
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
    for (const e of entries) {
      const file = path.join(dir, e.name, 'SKILL.md');
      if (fs.existsSync(file)) out.push({ name: prefix + e.name, file });
    }
  };
  scan(path.join(ROOT, '.claude', 'skills'), '');
  scan(path.join(HOME, '.claude', 'skills'), '');
  const on = enabledPlugins();
  const installed = (readJson(path.join(HOME, '.claude', 'plugins', 'installed_plugins.json')) || {}).plugins || {};
  for (const [id, entries] of Object.entries(installed)) {
    if (on[id] !== true) continue;
    const hit = (entries || []).find((e) => e && e.installPath &&
      (e.scope === 'user' || (e.projectPath && same(e.projectPath, ROOT))));
    if (hit) scan(path.join(hit.installPath, 'skills'), id.split('@')[0] + ':');
  }
  return out;
}

/** [{ skills: [name], file?, tools: RegExp, paths: RegExp|null, source }] */
function rules() {
  const out = [];
  for (const s of skillFiles()) {
    let d;
    try { d = declared(fs.readFileSync(s.file, 'utf8')); } catch (_) { continue; }
    if (!d) continue;
    const tools = rx(d['load-before-tools']);
    if (tools) out.push({ skills: [s.name], files: [s.file], tools, paths: rx(d['load-before-paths']), source: 'frontmatter' });
  }
  const cfgPath = path.join(ROOT, '.claude', 'rules', 'skill-gate.json');
  if (fs.existsSync(cfgPath)) {
    const cfg = readJson(cfgPath);
    if (!cfg) log(`BAD-CONFIG ${cfgPath}`);
    for (const r of (cfg && Array.isArray(cfg.rules) ? cfg.rules : [])) {
      const tools = rx(r && r.tools);
      if (tools && Array.isArray(r.skills) && r.skills.length) {
        out.push({ skills: r.skills.map(String), files: [], tools, paths: rx(r.paths), source: 'skill-gate.json' });
      }
    }
  }
  return out;
}

function targetPath(input) {
  const i = input || {};
  return String(i.file_path || i.notebook_path || i.path || '');
}

/** Names and SKILL.md paths this transcript has loaded. */
function loaded(transcript) {
  const names = new Set();
  const files = [];
  const text = fs.readFileSync(transcript, 'utf8');
  for (const line of text.split('\n')) {
    if (!line.includes('"Skill"') && !line.includes('SKILL.md') && !line.includes('<command-name>')) continue;
    for (const m of line.matchAll(/<command-name>\/?([^<\s]+)<\/command-name>/g)) names.add(m[1]);
    let d;
    try { d = JSON.parse(line); } catch (_) { continue; }
    const content = d.message && Array.isArray(d.message.content) ? d.message.content : [];
    for (const b of content) {
      if (b.type !== 'tool_use' || !b.input) continue;
      if (b.name === 'Skill' && b.input.skill) names.add(String(b.input.skill).replace(/^\//, ''));
      if (b.name === 'Read' && b.input.file_path) files.push(String(b.input.file_path));
    }
  }
  return { names, files };
}

function satisfied(skill, file, ev) {
  // Bare and qualified forms both count: `/td-mcp-core` and `touchdesigner:td-mcp-core` load the same skill.
  const bare = (n) => n.split(':').pop();
  for (const n of ev.names) if (n === skill || bare(n) === bare(skill)) return true;
  return Boolean(file) && ev.files.some((f) => same(f, file));
}

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { input += c; });
process.stdin.on('end', () => {
  let hook;
  try { hook = JSON.parse(input); } catch (_) { process.exit(0); }
  const tool = String(hook.tool_name || '');
  if (tool === 'Skill' || tool === 'Read') process.exit(0);
  const target = targetPath(hook.tool_input);

  let hits;
  try {
    hits = rules().filter((r) => r.tools.test(tool) && (!r.paths || (target && r.paths.test(target))));
  } catch (e) { log(`ERR rules ${e.message}`); process.exit(0); }
  if (!hits.length) process.exit(0);
  if (!hook.transcript_path || !fs.existsSync(hook.transcript_path)) {
    log(`NO-TRANSCRIPT tool=${tool}`); process.exit(0);
  }

  let ev;
  try { ev = loaded(hook.transcript_path); } catch (e) { log(`ERR transcript ${e.message}`); process.exit(0); }
  const missing = [];
  for (const r of hits) {
    r.skills.forEach((s, i) => {
      if (!satisfied(s, r.files[i], ev) && !missing.some((m) => m.skill === s)) {
        missing.push({ skill: s, source: r.source });
      }
    });
  }
  if (!missing.length) process.exit(0);

  log(`BLOCKED tool=${tool}${target ? ' path=' + target : ''} missing=${missing.map((m) => m.skill).join(',')}`);
  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        `SKILL-GATE: "${tool}" needs these skills loaded in this session first:\n` +
        missing.map((m) => `  - ${m.skill}   (declared in ${m.source})`).join('\n') +
        '\n\nLoad each with the Skill tool (or Read its SKILL.md if this agent has no Skill tool), ' +
        'follow it, then repeat the call. No bypass marker: loading a skill is one call.',
    },
  }));
  process.exit(0);
});
