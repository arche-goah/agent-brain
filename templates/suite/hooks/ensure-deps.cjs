#!/usr/bin/env node
/**
 * ensure-deps.cjs — SessionStart hook of a suite plugin that ships an npm MCP server.
 *
 * CORE TEMPLATE (templates/suite/hooks/): a suite copies this file and hooks.json UNCHANGED
 * into its own hooks/ folder. The plugin's name is read from .claude-plugin/plugin.json, so
 * no line is edited per suite; `scripts/suite-check.py` warns when a suite's copy differs
 * from the pinned core's template (a suite may deviate with a reason it writes down).
 * Measured 2026-11-03 on the macOS instance: two suites carried the same 105 lines, differing
 * only in the five lines naming the suite, and every further suite with a server would copy
 * it again — a fix in one copy reached no other.
 *
 * The plugin cache is read-only delivery; node_modules must not live there (they'd be
 * wiped on every update and bloat git). This installs the MCP server's npm deps ONCE
 * into CLAUDE_PLUGIN_DATA and re-installs only when mcp/package.json changed.
 * The .mcp.json points NODE_PATH at the same place.
 *
 * Fails soft: a broken npm install prints a warning; the session still starts —
 * the MCP server will then fail loudly with a missing-module error, which names
 * this hook in its stack.
 */
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = process.env.CLAUDE_PLUGIN_ROOT;
const data = process.env.CLAUDE_PLUGIN_DATA;
if (!root || !data) process.exit(0); // not running as a plugin (dev checkout) — nothing to do

// The plugin's own name, for every message; falls back to the folder name.
let name = path.basename(root);
try {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, ".claude-plugin", "plugin.json"), "utf8"));
  if (manifest && typeof manifest.name === "string" && manifest.name) name = manifest.name;
} catch (_) { /* no manifest, no name — the folder name stands */ }

const pkgSrc = path.join(root, "mcp", "package.json");
if (!fs.existsSync(pkgSrc)) process.exit(0);

// The lockfile ships with the plugin and must travel WITH the manifest. Until 2026-08-04
// only package.json was copied, so npm resolved the ranges fresh on every install and the
// pinned tree was silently discarded — measured on a Windows brain: lock pins
// @modelcontextprotocol/sdk 1.29.0, installed was 1.30.0.
const lockSrc = path.join(root, "mcp", "package-lock.json");
const hasLock = fs.existsSync(lockSrc);

const stamp = path.join(data, "package.json.installed");
// The stamp covers manifest AND lock: a lock-only change (the usual security bump) has to
// trigger a reinstall, otherwise the pin exists on disk and never reaches node_modules.
const want = fs.readFileSync(pkgSrc, "utf8") + (hasLock ? fs.readFileSync(lockSrc, "utf8") : "");
let have = null;
try { have = fs.readFileSync(stamp, "utf8"); } catch (_) {}

// The server is ESM — NODE_PATH is invisible to it (CJS-only). ESM resolves by walking
// node_modules directories next to the code, so the cache needs a LINK to the installed
// deps: mcp/node_modules -> CLAUDE_PLUGIN_DATA/node_modules. A plugin update replaces
// the cache dir and silently removes the link, so its existence is checked EVERY start,
// independent of the package.json stamp. Windows: junction (no elevated rights needed).
function ensureLink() {
  const linkPath = path.join(root, "mcp", "node_modules");
  const target = path.join(data, "node_modules");
  if (!fs.existsSync(target)) return false;
  try {
    const st = fs.lstatSync(linkPath);
    if (st.isSymbolicLink() || st.isDirectory()) return true; // present (link or real dir)
  } catch (_) { /* missing — create below */ }
  try {
    fs.symlinkSync(target, linkPath, process.platform === "win32" ? "junction" : "dir");
    console.log(`${name}: node_modules link restored in plugin cache`);
    return true;
  } catch (e) {
    console.log(`${name}: could not link node_modules into the cache (${String(e).slice(0, 100)})`);
    return false;
  }
}

if (have === want && fs.existsSync(path.join(data, "node_modules"))) {
  ensureLink();
  process.exit(0);
}

try {
  fs.mkdirSync(data, { recursive: true });
  fs.copyFileSync(pkgSrc, path.join(data, "package.json"));
  if (hasLock) fs.copyFileSync(lockSrc, path.join(data, "package-lock.json"));
  // Windows has no file literally named `npm` — only npm.cmd/npm.ps1. execFileSync
  // spawns via CreateProcess without PATHEXT resolution, so plain "npm" is ENOENT
  // (measured, B3 of the Windows onboarding run). And node refuses to spawn a .cmd
  // without a shell (CVE-2024-27980), so on win32 both the name AND shell change.
  const isWin = process.platform === "win32";
  // `npm ci` when a lock is present: it installs the pinned tree exactly and fails instead
  // of silently resolving something newer. Without a lock there is nothing to be exact
  // about, so `install` stays the fallback.
  //
  // --ignore-scripts is the actual hardening: this runs UNATTENDED at SessionStart. Without
  // it every install/postinstall in the whole tree executes with the user's rights before
  // anyone has looked at what was pulled — the 2026 npm attack class (Shai-Hulud and the
  // SAP-CAP compromise both shipped their payload in lifecycle scripts). Measured on this
  // tree: no installed package declares install/postinstall today, so nothing legitimate
  // is lost by refusing them.
  //
  // --no-audit was dropped: it switched off npm's vulnerability check on every unattended
  // reinstall. It costs one registry roundtrip and buys the only warning anyone would ever
  // see here.
  const args = hasLock
    ? ["ci", "--omit=dev", "--ignore-scripts", "--no-fund"]
    : ["install", "--omit=dev", "--ignore-scripts", "--no-fund"];
  execFileSync(isWin ? "npm.cmd" : "npm", args, {
    cwd: data,
    stdio: "pipe",
    timeout: 110_000,
    shell: isWin,
  });
  fs.writeFileSync(stamp, want);
  ensureLink();
  console.log(`${name}: npm deps installed/refreshed in CLAUDE_PLUGIN_DATA`);
} catch (e) {
  console.log(`${name}: npm dep install FAILED (${String(e).slice(0, 120)}) — the plugin's MCP server will not start until this is fixed (run npm install in ${data})`);
}
process.exit(0);
