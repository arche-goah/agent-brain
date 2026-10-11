#!/usr/bin/env node
/**
 * mechanism-guard.cjs — PreToolUse(Bash): blocks local ad-hoc workarounds for which
 * the setup has a documented, persistent mechanism.
 *
 * WHY (incident 2026-07-31): instead of a static DHCP reservation on the router,
 * `networksetup -setmanual` on the end device was suggested. The local hack works
 * immediately but leaves NOTHING in the system: it doesn't survive a reset, isn't
 * recorded in any role, isn't visible to any operator. Operator directive: "we want
 * to build a clean, reliable show system ... there must be no ignoring that."
 *
 * The guard doesn't force a detour — it forces an EXPLICIT decision: either the
 * documented path, or a deliberate justification in the command (marker `MECHANISM-OK:`).
 * That way a deviation can no longer happen silently.
 *
 * CORE/INSTANCE SPLIT: this guard is the mechanism (core). The rules themselves are
 * instance knowledge (which rig, which doc paths) and are loaded at runtime from
 *   <project>/.claude/rules/mechanism-rules.json
 * Format: [{ "pattern": "<JS regex>", "was": "...", "stattdessen": "..." }, ...]
 * If the file is missing or broken, the guard blocks nothing (fail-open, read-only hook).
 * Every newly discovered shortcut gets added there as a rule — the system learns.
 */
const fs = require('fs');

// A heredoc body is literal text ONLY when its consumer cannot execute it. Scanning the
// raw command without stripping produces a false positive on any heredoc that merely
// QUOTES the banned mechanism as prose (found live: a commit message documenting a
// "msg.exe via Task Scheduler" finding tripped the msg(\.exe)? rule, though no such
// command ever ran). Same root-cause class as scripts/hooks/cross-instance-push-watch.cjs's
// original bug (an instance-side hook, fixed independently the same day).
//
// BUT stripping EVERY heredoc turns the guard off through one syntax: `bash <<EOF`,
// `ssh host <<EOF`, `python3 - <<EOF`, `eval "$(cat <<EOF …)"` all EXECUTE their body.
// Measured against the fixture rule \bfixture-shortcut\b: 7 of 8 executed shapes went
// from "seen" to "blind" with a blanket strip. So the consumer decides, and the default
// is fail-closed — an unknown consumer keeps its body in the scanned text.
const HEREDOC_EXECUTES = /(^|[|;&]|\$\(|\()\s*(eval|source|\.)\s/;
const HEREDOC_PROSE_CONSUMER = /(?:^|[|;&]|\$\(|\()\s*(?:cat|tee)(?:\s+[^<|;&]*)?$/;

function stripHeredocs(cmd) {
  return cmd.replace(
    /(^|\n)([^\n]*?)(<<-?\s*(['"]?)(\w+)\4[^\n]*\n[\s\S]*?\n\5\b)/g,
    (match, lead, before) => {
      // `before` is everything on the line up to `<<`; its last command is the consumer.
      if (HEREDOC_EXECUTES.test(before)) return match;        // eval/source run the text
      if (!HEREDOC_PROSE_CONSUMER.test(before)) return match; // unknown: keep scanning it
      return `${lead}${before}<<HEREDOC-STRIPPED>>`;
    }
  );
}

// TOOL RULES (added 2026-10-11): a tool environment that is meant to be driven through its MCP
// server — not through its internals (IPC files, the server's source run by hand, GUI drivers) —
// declares those internals ITSELF, in a `mechanism-rules.json` at the tool's root. Incident: a
// session on a second machine could not take the defined path (its MCP came from the released
// plugin, the request assumed a clone) and built its own client, wrote probes straight into the
// server's IPC file and drove the GUI. Nothing stopped it: this guard only knew the instance's
// own rules, and the tool declared nothing. The instance cannot be expected to know every tool's
// internals; the tool can. So the guard finds tool rule files on both ways a tool arrives:
//   - a server script referenced in <project>/.mcp.json (a clone): walk up from the script;
//   - an enabled plugin (installed_plugins.json + enabledPlugins): its install root.
// Tool rule file: {"tool": "<name>", "rules": [{"pattern", "was", "instead", "target"}]}.
// target "command" (default) = the Bash/Monitor command; target "path" = the file a Write/Edit
// touches. Instance rules keep their format and may use "target" too.
const path = require('path');
const os = require('os');

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; }
}

function compile(list, source) {
  if (!Array.isArray(list)) return [];
  return list
    .filter((r) => r && r.pattern && r.was && (r.stattdessen || r.instead))
    .map((r) => {
      try {
        return { re: new RegExp(r.pattern), was: r.was, instead: r.stattdessen || r.instead,
                 target: r.target === 'path' ? 'path' : 'command', source };
      } catch (_) { return null; }
    })
    .filter(Boolean);
}

function walkUpFor(start, name, maxUp) {
  let dir = start;
  for (let i = 0; i <= maxUp; i++) {
    const cand = path.join(dir, name);
    if (fs.existsSync(cand)) return cand;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return null;
}

function toolRuleFiles(project) {
  const found = new Set();
  // 1. clones: every path-like argument of an MCP server in the project's .mcp.json
  const mcp = readJson(path.join(project, '.mcp.json'));
  for (const srv of Object.values((mcp && mcp.mcpServers) || {})) {
    for (const a of [srv && srv.command, ...((srv && srv.args) || [])]) {
      if (typeof a !== 'string' || !/[\\/]/.test(a)) continue;
      const abs = path.isAbsolute(a) ? a : path.join(project, a);
      if (!fs.existsSync(abs)) continue;
      const f = walkUpFor(path.dirname(abs), 'mechanism-rules.json', 6);
      if (f) found.add(f);
    }
  }
  // 2. enabled plugins: project settings decide over user settings
  const home = os.homedir();
  const enabled = Object.assign({},
    ((readJson(path.join(home, '.claude', 'settings.json')) || {}).enabledPlugins) || {},
    ((readJson(path.join(project, '.claude', 'settings.json')) || {}).enabledPlugins) || {},
    ((readJson(path.join(project, '.claude', 'settings.local.json')) || {}).enabledPlugins) || {});
  const installed = (readJson(path.join(home, '.claude', 'plugins', 'installed_plugins.json')) || {}).plugins || {};
  for (const [name, entries] of Object.entries(installed)) {
    if (enabled[name] !== true || !Array.isArray(entries)) continue;
    for (const e of entries) {
      const f = e && e.installPath && path.join(e.installPath, 'mechanism-rules.json');
      if (f && fs.existsSync(f)) found.add(f);
    }
  }
  return [...found];
}

function loadRules() {
  const project = process.env.CLAUDE_PROJECT_DIR || '.';
  const rules = compile(readJson(`${project}/.claude/rules/mechanism-rules.json`), 'this instance');
  let files = [];
  try { files = toolRuleFiles(project); } catch (_) { files = []; }
  for (const f of files) {
    const data = readJson(f);
    if (data && Array.isArray(data.rules)) rules.push(...compile(data.rules, data.tool || path.dirname(f)));
  }
  return rules;
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let cmd = '';
  let filePath = '';
  try {
    const ti = JSON.parse(input).tool_input || {};
    cmd = ti.command || '';
    filePath = (ti.file_path || ti.notebook_path || '').replace(/\\/g, '/');
  } catch (_) {
    process.exit(0);
  }
  if (/MECHANISM-OK:/.test(cmd)) process.exit(0); // deliberate, justified deviation

  const stripped = stripHeredocs(cmd);
  for (const r of loadRules()) {
    const hit = r.target === 'path' ? (filePath && r.re.test(filePath)) : (cmd && r.re.test(stripped));
    if (hit) {
      const how = r.target === 'path'
        ? `A file write cannot carry the marker. If the documented path really doesn't fit, do it as a\n` +
          `shell command that ends with "# MECHANISM-OK: <justification>" — visible and justified.`
        : `If the documented path really doesn't fit: repeat the command with a comment\n` +
          `"# MECHANISM-OK: <justification>" — the justification then belongs in the\n` +
          `change log. A silent deviation is not intended.`;
      const msg =
        `MECHANISM CHECK (${r.source}): ${r.was}\n\n` +
        `The setup has a documented path for this:\n  ${r.instead}\n\n` + how;
      cmd = cmd || `write ${filePath}`;
      try {
        fs.appendFileSync(
          `${process.env.CLAUDE_PROJECT_DIR || '.'}/.claude-state/mechanism-guard.log`,
          `${new Date().toISOString()} BLOCKED: ${cmd.slice(0, 200)}\n`
        );
      } catch (_) {}
      console.log(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: msg,
        },
      }));
      process.exit(0);
    }
  }
  process.exit(0);
});
