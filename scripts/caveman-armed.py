#!/usr/bin/env python3
"""caveman-armed.py — does the caveman output style actually reach this brain's sessions?

Prints ONE line naming the carrier when armed, nothing when not. Run from the brain root
(project settings are read from ./.claude/settings.json); user settings and the plugin
registry come from $CLAUDE_CONFIG_DIR or ~/.claude. Exit 0 always — the bootup decides.

Carriers, in the order Claude Code honours them:
1. an ENABLED plugin (value true in project or user `enabledPlugins`) whose recorded
   installPath ships output-styles/caveman.md with `force-for-plugin: true`, and whose
   plugin.json there agrees on the version (an older cache dir resolves nothing);
2. a LOCAL output-styles dir (project or user) that holds the style the `outputStyle`
   setting names.
The bare setting is NOT a carrier — measured 2026-08-04 on macOS and Windows: it arms
nothing on its own. Counting it kept the alarm silent while the plugin had lost the style.
"""
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
proj, user = load(os.path.join(".claude", "settings.json")), load(os.path.join(cfg, "settings.json"))
enabled = {k for s in (proj, user) for k, v in (s.get("enabledPlugins") or {}).items() if v}
for pid, entries in (load(os.path.join(cfg, "plugins", "installed_plugins.json")).get("plugins") or {}).items():
    if pid not in enabled:
        continue
    for e in entries or []:
        path = (e.get("installPath") or "").replace("\\", "/")
        style = os.path.join(path, "output-styles", "caveman.md")
        if not os.path.isfile(style):
            continue
        mver = load(os.path.join(path, ".claude-plugin", "plugin.json")).get("version")
        if mver and e.get("version") and mver != e["version"]:
            continue  # stale cache dir
        try:
            lines = open(style, encoding="utf-8").read().splitlines()
        except OSError:
            continue
        if any(ln.strip() == "force-for-plugin: true" for ln in lines):
            print("plugin %s %s" % (pid, e.get("version") or "?"))
            sys.exit(0)
declared = str(proj.get("outputStyle") or user.get("outputStyle") or "")
if "caveman" in declared:
    for d in (os.path.join(".claude", "output-styles"), os.path.join(cfg, "output-styles")):
        if os.path.isfile(os.path.join(d, declared + ".md")):
            print("local style %s" % declared)
            sys.exit(0)
