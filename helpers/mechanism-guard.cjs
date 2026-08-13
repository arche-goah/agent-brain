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

function loadRules() {
  const p = `${process.env.CLAUDE_PROJECT_DIR || '.'}/.claude/rules/mechanism-rules.json`;
  try {
    const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (!Array.isArray(raw)) return [];
    return raw
      .filter((r) => r && r.pattern && r.was && r.stattdessen)
      .map((r) => ({ re: new RegExp(r.pattern), was: r.was, stattdessen: r.stattdessen }));
  } catch (_) {
    return [];
  }
}

let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  let cmd = '';
  try {
    cmd = (JSON.parse(input).tool_input || {}).command || '';
  } catch (_) {
    process.exit(0);
  }
  if (/MECHANISM-OK:/.test(cmd)) process.exit(0); // deliberate, justified deviation

  for (const r of loadRules()) {
    if (r.re.test(cmd)) {
      const msg =
        `MECHANISM CHECK: ${r.was}\n\n` +
        `The setup has a documented path for this:\n  ${r.stattdessen}\n\n` +
        `If the documented path really doesn't fit: repeat the command with a comment\n` +
        `"# MECHANISM-OK: <justification>" — the justification then belongs in the\n` +
        `change log. A silent deviation is not intended.`;
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
