#!/usr/bin/env node
// Fixture for templates/suite/hooks/ensure-link.cjs: a fresh plugin cache WITHOUT the mcp/node_modules link
// (the state `claude plugin update` leaves, measured 2026-11-13) must start its ESM server green when the
// server is preloaded with ensure-link.cjs; the negative control (the start without the preload, the
// template before 2026-11-25) fails on the same cache. The preload prints nothing (stdout is MCP stdio).
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const TPL = path.join(__dirname, "..", "templates", "suite", "hooks");
let fails = 0;
const ok = (cond, what) => { console.log((cond ? "PASS " : "FAIL ") + what); if (!cond) fails++; };

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ensure-link-"));
const root = path.join(tmp, "cache", "suite", "1.0.1");
const data = path.join(tmp, "data", "suite");
fs.mkdirSync(path.join(root, "hooks"), { recursive: true });
fs.mkdirSync(path.join(root, "mcp", "src"), { recursive: true });
fs.mkdirSync(path.join(root, ".claude-plugin"), { recursive: true });
for (const f of ["ensure-link.cjs", "ensure-deps.cjs"]) fs.copyFileSync(path.join(TPL, f), path.join(root, "hooks", f));
fs.writeFileSync(path.join(root, ".claude-plugin", "plugin.json"), '{"name":"suite"}');
const pkg = '{"name":"srv","version":"1.0.0","type":"module","dependencies":{"dep":"1.0.0"}}';
fs.writeFileSync(path.join(root, "mcp", "package.json"), pkg);
fs.writeFileSync(path.join(root, "mcp", "src", "index.mjs"), 'import { v } from "dep";\nprocess.stderr.write("dep=" + v);\n');
// The installed deps from an earlier version live on in CLAUDE_PLUGIN_DATA (the stamp says: up to date).
fs.mkdirSync(path.join(data, "node_modules", "dep"), { recursive: true });
fs.writeFileSync(path.join(data, "node_modules", "dep", "package.json"), '{"name":"dep","version":"1.0.0","type":"module","exports":"./index.js"}');
fs.writeFileSync(path.join(data, "node_modules", "dep", "index.js"), "export const v = 42;\n");
fs.writeFileSync(path.join(data, "package.json.installed"), pkg);

const env = { ...process.env, CLAUDE_PLUGIN_ROOT: root, CLAUDE_PLUGIN_DATA: data };
const server = path.join(root, "mcp", "src", "index.mjs");
const link = path.join(root, "mcp", "node_modules");
const start = (args) => spawnSync(process.execPath, [...args, server], { env, encoding: "utf8" });
const exists = (p) => { try { fs.lstatSync(p); return true; } catch { return false; } };

try {
  const bare = start([]);
  ok(bare.status !== 0 && /ERR_MODULE_NOT_FOUND|Cannot find package/.test(bare.stderr),
     "negative control: fresh cache, start WITHOUT the preload fails on the missing dependency");
  ok(!exists(link), "negative control leaves no link behind");

  const pre = start(["--require", path.join(root, "hooks", "ensure-link.cjs")]);
  ok(pre.status === 0 && pre.stderr.includes("dep=42"), "fresh cache, start WITH the preload: server resolves its dependency");
  ok(pre.stdout === "", "the preload writes nothing to stdout (the MCP stdio channel)");
  ok(exists(link), "the preload left the link in the cache");
  ok(start(["--require", path.join(root, "hooks", "ensure-link.cjs")]).status === 0, "second start with the link present: green");

  const hook = () => spawnSync(process.execPath, [path.join(root, "hooks", "ensure-deps.cjs")], { env, encoding: "utf8" });
  let h = hook();
  ok(h.status === 0 && h.stdout === "", "SessionStart hook with the link present: silent");
  fs.rmSync(link, { recursive: false, force: true });
  ok(!exists(link) && exists(path.join(data, "node_modules", "dep")), "link removed, installed deps untouched");
  h = hook();
  ok(h.status === 0 && h.stdout.includes("suite: node_modules link restored") && exists(link),
     "SessionStart hook relinks through ensure-link.cjs and reports it once");

  // Two writers at the same instant (preload and hook): the loser's symlinkSync throws EEXIST, the link exists.
  fs.rmSync(link, { force: true });
  process.env.CLAUDE_PLUGIN_ROOT = root; process.env.CLAUDE_PLUGIN_DATA = data;
  const mod = require(path.join(root, "hooks", "ensure-link.cjs")); // its load-time run makes the link
  const orig = fs.symlinkSync;
  fs.rmSync(link, { force: true });
  fs.symlinkSync = (t, l, ty) => { orig(t, l, ty); const e = new Error("EEXIST: file already exists"); e.code = "EEXIST"; throw e; };
  let race;
  try { race = mod.ensureLink(); } finally { fs.symlinkSync = orig; }
  ok(race === "present" && exists(link), "the other writer won the race (EEXIST, link there): reported as present, not failed");

  const dev = spawnSync(process.execPath, ["--require", path.join(root, "hooks", "ensure-link.cjs"), "-e", ""],
                        { env: { ...process.env, CLAUDE_PLUGIN_ROOT: "", CLAUDE_PLUGIN_DATA: "" }, encoding: "utf8" });
  ok(dev.status === 0 && dev.stdout === "", "outside a plugin (no CLAUDE_PLUGIN_* vars): the preload is a silent no-op");
} finally {
  try { fs.rmSync(link, { force: true }); } catch {}
  fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(fails ? `${fails} FAILED` : "all passed");
process.exit(fails ? 1 : 0);
