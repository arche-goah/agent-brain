/**
 * ensure-link.cjs — the ONE writer of the mcp/node_modules link of a suite plugin.
 *
 * CORE TEMPLATE (templates/suite/hooks/): copied unchanged next to ensure-deps.cjs. Two callers:
 *  1. the MCP server start, as a preload: `node --require ${CLAUDE_PLUGIN_ROOT}/hooks/ensure-link.cjs
 *     ${CLAUDE_PLUGIN_ROOT}/mcp/src/index.ts` — the link exists before the ESM resolver runs;
 *  2. ensure-deps.cjs (SessionStart), which reads `result` and calls `ensureLink()` after an install.
 *
 * Why the preload: `claude plugin update` writes a fresh cache dir WITHOUT the link; the next
 * session's MCP connect ran before the SessionStart hook recreated it, failed, and the harness
 * cached the failure ("Skipping connection (recent failure cached ...)") — measured 2026-11-13 on
 * the Windows instance (grandma3-next 1.2.0). CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA are both in
 * the MCP server's environment (measured 2026-11-25, Claude Code 2.1.332, Windows, probe plugin).
 *
 * As a preload it must stay silent and never exit: stdout is the server's MCP stdio channel.
 */
const fs = require("node:fs");
const path = require("node:path");

// Returns "present" | "made" | "no-deps" | "no-plugin" | "failed: <reason>". Never throws, never prints.
function ensureLink() {
  const root = process.env.CLAUDE_PLUGIN_ROOT;
  const data = process.env.CLAUDE_PLUGIN_DATA;
  if (!root || !data) return "no-plugin"; // dev checkout — nothing to do
  const linkPath = path.join(root, "mcp", "node_modules");
  const target = path.join(data, "node_modules");
  if (!fs.existsSync(target)) return "no-deps"; // first install: ensure-deps installs, then links
  try {
    const st = fs.lstatSync(linkPath);
    if (st.isSymbolicLink() || st.isDirectory()) return "present"; // link or real dir
  } catch (_) { /* missing — create below */ }
  try {
    // Windows: junction (no elevated rights needed).
    fs.symlinkSync(target, linkPath, process.platform === "win32" ? "junction" : "dir");
    return "made";
  } catch (e) {
    return `failed: ${String(e).slice(0, 100)}`;
  }
}

const result = ensureLink();
module.exports = { ensureLink, result };
