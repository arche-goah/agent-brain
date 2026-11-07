#!/usr/bin/env node
/**
 * PreToolUse hook: the AI's own browser checks never open a window on the operator's screen.
 *
 * WHY (operator decision 2026-10-28 on the macOS instance, after a Playwright check opened Chrome unasked: "invisible,
 * unless it is explicitly about me seeing it"). Measured cause there: .mcp.json started @playwright/mcp and
 * chrome-devtools-mcp without --headless, and visible is their default. Ran as instance machinery since 2026-10-28;
 * ported because it holds for every brain with a browser server.
 *
 * A call of a playwright or chrome-devtools MCP tool is denied while that server's args in the brain's .mcp.json lack
 * "--headless" (a config can lose the flag in an update or a copy; this catches it before a window opens). When the
 * operator is meant to see a page, it is opened in their own browser (`open <url>` / `start <url>`), not through the
 * check tool. A server the brain's .mcp.json does not define (plugin-provided, or none) is not judged.
 * Fails open on unreadable input or config. Fixture: scripts/test-headless-browser-gate.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const SERVERS = {
  playwright: /^mcp__(?:plugin_[\w-]+_)?playwright__/,
  'chrome-devtools': /^mcp__(?:plugin_[\w-]+_)?chrome-devtools__/,
};

function judge(input, mcp) {
  const tool = (input && input.tool_name) || '';
  const name = Object.keys(SERVERS).find((s) => SERVERS[s].test(tool));
  if (!name) return null;
  const srv = mcp && mcp.mcpServers && mcp.mcpServers[name];
  if (!srv || (srv.args || []).includes('--headless')) return null;
  return 'HEADLESS-BROWSER: ' + tool + ' would open a visible browser window on the operator\'s screen - the "' + name +
    '" server in .mcp.json has no --headless. Add "--headless" to its args and reload it (/mcp). If the operator is meant ' +
    'to see the page, open it in their own browser (`open <url>`, Windows `start <url>`) instead.';
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let reason = null;
    try {
      const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
      reason = judge(JSON.parse(raw), JSON.parse(fs.readFileSync(path.join(root, '.mcp.json'), 'utf8')));
    } catch (e) { reason = null; }
    if (reason) {
      process.stdout.write(JSON.stringify({ hookSpecificOutput: {
        hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason } }));
    }
    process.exit(0);
  });
}

module.exports = { judge };
