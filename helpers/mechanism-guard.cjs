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
 * Format: [{ "pattern": "<JS regex>", "was": "...", "stattdessen": "...",
 *           "needs_operator_word": true|false, "foreground_only": true|false }, ...]
 * `foreground_only: true` = the rule fires only for a command that would hold the session
 * (Bash without run_in_background); the same command detached is the defined path.
 * `monitor_only: true` = the rule fires only for a Monitor command — a stream whose buffering decides
 * whether its events arrive at all (a background Bash reports once at its end; buffering is moot there).
 * If the file is missing or broken, the guard blocks nothing (fail-open, read-only hook).
 * Every newly discovered shortcut gets added there as a rule — the system learns.
 *
 * OPERATOR'S WORD (added 2026-10-12): a rule whose documented path is "agree it with the
 * operator first" may set `needs_operator_word: true`. Then the marker alone does not open
 * it — its justification has to carry the operator's word in a CHECKABLE form: a quotation
 * ("…", „…", “…”) plus the date it was said (YYYY-MM-DD), or a pointer to a decision file
 * (path[:line]) that exists. Incident (2026-09-12): two merges in a shared repo carried the
 * marker with a verbatim operator quote that stands in no transcript of that day — a real
 * but unspecific order had been smoothed into a crisp permission while writing the marker.
 * The guard cannot read the transcript, but it can refuse the shape that lets a paraphrase
 * pass as a quote: no quote, no date, no file = nothing anyone can check afterwards. Rules
 * without the flag keep the old behaviour; a brain that never sets it changes nothing.
 */
const fs = require('fs');
const { withoutPublished } = require('./published-text.cjs');

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

// A MESSAGE argument (git commit -m "…", gh … --body/--title "…") MENTIONS a command, it does not
// run it. Measured 2026-10-16: an instance rule refused a commit whose message had a line starting
// with a guarded command; most instance rules anchor at line starts, so every multi-line message
// that names one of them tripped. Only the quoted message text is cut out, and only when it cannot
// execute: a double-quoted message holding $( … ) or backticks runs that code and stays scanned
// (its heredoc prose is already handled by stripHeredocs above). Same cut as the network-drive gate.
const MESSAGE_ARG = /(^|\s)(?:-m|--message|--body|--title|--subject)(?:\s+|=)("(?:[^"\\]|\\.)*"|'[^']*')/g;

function stripMessages(cmd) {
  return cmd.replace(MESSAGE_ARG, (match, lead, text) =>
    text[0] === '"' && /\$\(|`/.test(text) ? match : `${lead}<MESSAGE-STRIPPED>`);
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
                 // 'raw': the command with its message text left in — for a rule about the FORM of
                 // that text (multi-line text belongs in a file), which the cut below would hide.
                 target: r.target === 'path' ? 'path' : r.target === 'raw' ? 'raw' : 'command', source,
                 needsOperatorWord: r.needs_operator_word === true,
                 foregroundOnly: r.foreground_only === true, monitorOnly: r.monitor_only === true };
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
  // 3. the core submodule itself, when no enabled plugin ships the same tool's rules — a brain
  // without the plugin had the core's own rules inert (measured 2026-10-21, raw-API merge passed).
  // With both present the PLUGIN wins on purpose, even if older: it is the released state the brain consumes.
  const sub = path.join(project, 'core', 'mechanism-rules.json');
  const subTool = fs.existsSync(sub) && (readJson(sub) || {}).tool;
  if (subTool && ![...found].some((f) => (readJson(f) || {}).tool === subTool)) found.add(sub);
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

// The operator's word behind the marker, in the three shapes the guard can check without a
// transcript. Quote shapes are the ones question-gate.cjs accepts for a deferred question;
// three characters minimum so an empty pair ("") does not count as a quotation.
const QUOTE_RE = /"[^"\n]{3,}"|„[^“”"\n]{3,}[“”"]|“[^”\n]{3,}”/;
const DATE_RE = /\b20\d{2}-\d{2}-\d{2}\b/;

// A pointer is a path-like token (contains a slash) after the marker, optionally with
// `:line` or `#anchor`; it counts only if the file exists — relative paths resolve against
// the project. Only record files count (.md/.txt/.json/.jsonl/.yaml): a script or a binary
// records no decision. A `:line` beyond the file's end is a pointer into nothing.
const RECORD_FILE_RE = /\.(md|txt|json|jsonl|ya?ml)$/i;
function pointerExists(text, project) {
  const tokens = text.match(/(?:~|[A-Za-z]:)?[\w.~-]*[\\/][\w.\\/~-]*(?::\d+)?/g) || [];
  for (const raw of tokens) {
    const t = raw.replace(/[),.;:]+$/, '');
    const m = /^(.*?)(?::(\d+))?$/.exec(t);
    let p = m[1].replace(/#.*$/, '');
    if (!RECORD_FILE_RE.test(p)) continue;
    if (p.startsWith('~')) p = path.join(os.homedir(), p.slice(1));
    if (!path.isAbsolute(p)) p = path.join(project, p);
    let st = null;
    try { st = fs.statSync(p); } catch (_) { continue; }
    if (!st.isFile()) continue;
    if (m[2]) {
      let lines = 0;
      try { lines = fs.readFileSync(p, 'utf8').split('\n').length; } catch (_) { continue; }
      if (Number(m[2]) > lines) continue;
    }
    return true;
  }
  return false;
}

// What the marker's justification is missing for a rule that needs the operator's word;
// an empty list means it carries one.
function operatorWordMissing(justification, project) {
  const quote = QUOTE_RE.test(justification);
  const date = DATE_RE.test(justification);
  if (quote && date) return [];
  if (pointerExists(justification, project)) return [];
  const missing = [];
  if (!quote) missing.push('a quotation of the operator in "…" or „…"');
  if (!date) missing.push('the date it was said (YYYY-MM-DD)');
  missing.push('or instead a pointer to a decision file that exists (path[:line])');
  return missing;
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let cmd = '';
  let filePath = '';
  let background = false;
  let hinTool = '';
  let transcript = '';
  let hinCwd = '';
  let monitor = false;
  try {
    const hin = JSON.parse(input);
    hinTool = hin.tool_name || '';
    transcript = hin.transcript_path || '';
    hinCwd = hin.cwd || '';
    const ti = hin.tool_input || {};
    cmd = ti.command || '';
    // Monitor always runs detached; Bash only with run_in_background.
    monitor = hin.tool_name === 'Monitor';
    background = monitor || ti.run_in_background === true;
    filePath = (ti.file_path || ti.notebook_path || '').replace(/\\/g, '/');
  } catch (_) {
    process.exit(0);
  }
  // A marker is a deliberate, justified deviation. It opens every rule as before — except a
  // rule that needs the operator's word, which reads the justification before it opens.
  const marker = /MECHANISM-OK:([\s\S]*)$/.exec(cmd);
  const project = process.env.CLAUDE_PROJECT_DIR || '.';
  const rules = loadRules();
  if (marker && !rules.some((r) => r.needsOperatorWord)) process.exit(0);

  // The published text of gh/git (messages, titles, bodies, fields) is data, not a command: the
  // shared extraction blanks exactly those values and leaves every other byte for the rules
  // (published-text.cjs). A line it cannot read to the end keeps the two older cuts.
  const stripped = (cmd && withoutPublished(cmd, false)) || stripMessages(stripHeredocs(cmd));
  for (const r of rules) {
    const hit = r.target === 'path' ? (filePath && r.re.test(filePath))
      : r.target === 'raw' ? (cmd && r.re.test(cmd)) : (cmd && r.re.test(stripped));
    if (!hit || (r.foregroundOnly && background) || (r.monitorOnly && !monitor)) continue;
    let missing = [];
    if (marker) {
      if (!r.needsOperatorWord) continue;
      missing = operatorWordMissing(marker[1], project);
      if (missing.length === 0) continue;
    }
    const how = marker
      ? `This rule needs the OPERATOR'S WORD behind the marker, and the justification does not carry\n` +
        `one that can be checked. Missing:\n  - ${missing.join('\n  - ')}\n` +
        `A paraphrase is not a quotation: write only what the operator actually said, with its date,\n` +
        `or point at the file where the decision is recorded. If there is no such word, that is the\n` +
        `finding — report it, do not run the command.`
      : r.target === 'path'
      ? `A file write cannot carry the marker. If the documented path really doesn't fit, do it as a\n` +
        `shell command that ends with "# MECHANISM-OK: <justification>" — visible and justified.`
      : `Only if that path does not fit: the same command with "# MECHANISM-OK: <why>" (goes in the change log).` +
        (r.needsOperatorWord
          ? `\nThis rule needs the operator's word: the justification must quote it ("…" plus the\n` +
            `date YYYY-MM-DD) or point at a decision file that exists (path[:line]).`
          : '');
    // Short (operator 2026-10-31: hook output "as short and informative as possible"): measured
    // 238 refusals in two weeks on the macOS instance, median 923 characters - mostly the rule's
    // incident story and a three-line marker boilerplate. The first clause of `was` says what is
    // refused; the incident stays in the rule file it came from.
    const what = String(r.was).split(/\s(?:—|-)\s|:\s\S+\s20\d\d-\d\d-\d\d|\.\s/)[0].slice(0, 200);
    const msg =
      `MECHANISM CHECK (${r.source}): ${what}\n` +
      `Documented path: ${r.instead}\n` + how;
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
  // A long run no rule names (2026-10-31, helpers/long-runs.cjs): a script that declares itself
  // `long-run: detached`, or one the operator once had to background by hand. A marker opens it.
  if (!background && !marker && hinTool === 'Bash') {
    let lr = null;
    try { lr = require('./long-runs.cjs').longRunScript(stripped, project, transcript, hinCwd); } catch (_) {}
    if (lr) {
      console.log(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason:
            `MECHANISM CHECK (agent-brain): ${lr.script} runs long in the foreground (${lr.why}).\n\n` +
            'The setup has a documented path for this:\n  Start the same command with Bash run_in_background ' +
            'and keep working; read its result line before claiming anything (Working Rule #13).',
        },
      }));
      process.exit(0);
    }
  }
  process.exit(0);
});
