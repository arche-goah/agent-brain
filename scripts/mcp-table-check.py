#!/usr/bin/env python3
"""Every server in .mcp.json has a row in the instance's MCP table, and every row a server.

A server added to .mcp.json while its table row is forgotten (or a row left for a server
that was removed) is a recurring brain-scan finding: measured on the Windows workstation
instance 2026-09-13 and 2026-09-23. Runs at session start (helpers/session-bootup.sh):
silent when both lists match, otherwise one line naming both directions, exit 1.

Where the table lives is instance data, `.claude/rules/mcp-table.json` (template in
templates/rules-instance/): {"table": "<repo-relative file>", "heading": "<heading text>"}.
Default = the core template's place: `.claude/rules/intelligence-instance.md`, section
"## MCP Servers". A row names its servers in its first cell, up to its first "(": every backticked name there
(`a` / `b`), else one bare name - a note in parentheses names no server; the header row "MCP" / "Server"
and separator rows are skipped; the section ends at the next heading of the same or a higher level.
A row may also name a server of an ENABLED plugin (enabledPlugins in ~/.claude/settings.json,
.claude/settings.json or settings.local.json, the later layer winning; the server read from the plugin's .mcp.json in the plugin cache,
~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/, or $MCP_TABLE_PLUGIN_CACHE): such a row is no finding;
a plugin server needs no row. A row may name a server the harness brings itself when the instance file
lists it in "builtin_servers" (e.g. claude-in-chrome): no .mcp.json and no plugin names those.

  python3 scripts/mcp-table-check.py [--repo <brain root>]
"""
import argparse
import json
import os
import pathlib
import re
import sys

DEFAULT = {"table": ".claude/rules/intelligence-instance.md", "heading": "## MCP Servers"}
HEADER_CELLS = {"mcp", "server", "servers"}


def table_rows(text, heading):
    level = len(heading) - len(heading.lstrip("#"))
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip().startswith(heading)), None)
    if start is None:
        return None
    rows = set()
    for line in lines[start + 1:]:
        m = re.match(r"^(#+)\s", line)
        if m and len(m.group(1)) <= level:
            break
        if not line.startswith("|"):
            continue
        first = line.split("|")[1] if line.count("|") >= 2 else ""
        # every backticked name in the first cell up to its first "(" (a row may serve `a` / `b`; a note in
        # parentheses names no server - measured on the macOS instance 2026-10-26), else one bare name
        first = first.split("(")[0]
        names = re.findall(r"`([A-Za-z0-9_][A-Za-z0-9_.-]*)`", first) \
            or re.findall(r"^\s*([A-Za-z0-9_][A-Za-z0-9_.-]*)\s*$", first)
        rows.update(n for n in names if n.lower() not in HEADER_CELLS)
    return rows


def user_settings():
    cfg = os.environ.get("CLAUDE_CONFIG_DIR")
    return (pathlib.Path(cfg) if cfg else pathlib.Path.home() / ".claude") / "settings.json"


def plugin_servers(root):
    """Server names of the plugins this brain enables (any cached version), from their .mcp.json.
    enabledPlugins is read on every layer that carries it, user first, then project and local - a later
    layer's value wins, as in Claude Code. Measured 2026-11-05 on the Windows instance: grandma3-next is
    enabled in ~/.claude/settings.json only, and its row was reported as "row without server"."""
    state = {}
    for f in (user_settings(), root / ".claude" / "settings.json", root / ".claude" / "settings.local.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8")) if f.is_file() else {}
        except (ValueError, OSError):
            continue
        state.update((data.get("enabledPlugins") or {}) if isinstance(data, dict) else {})
    enabled = {k for k, v in state.items() if v}
    cache = pathlib.Path(os.environ.get("MCP_TABLE_PLUGIN_CACHE") or pathlib.Path.home() / ".claude" / "plugins" / "cache")
    names = set()
    for key in enabled:
        plugin, _, market = key.partition("@")
        # A plugin declares its servers in .mcp.json or inline under `mcpServers` in its plugin.json
        # (measured on the macOS instance 2026-11-03: chataigne-next and touchosc-next do the latter,
        # and their rows were reported as "row without server").
        for f in [*(cache / market / plugin).glob("*/.mcp.json"),
                  *(cache / market / plugin).glob("*/.claude-plugin/plugin.json")]:
            try:
                servers = json.loads(f.read_text(encoding="utf-8")).get("mcpServers") or {}
            except (ValueError, AttributeError):
                continue
            if isinstance(servers, dict):  # plugin.json may name a file path instead
                names.update(servers)
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    root = pathlib.Path(ap.parse_args().repo)
    mcp = root / ".mcp.json"
    if not mcp.is_file():
        return 0
    try:
        servers = set((json.loads(mcp.read_text(encoding="utf-8")).get("mcpServers") or {}))
    except (ValueError, AttributeError) as e:
        print(f"!! mcp-table: .mcp.json unreadable ({e})")
        return 1
    if not servers:
        return 0
    cfg = dict(DEFAULT)
    builtin = set()
    inst = root / ".claude" / "rules" / "mcp-table.json"
    if inst.is_file():
        try:
            data = json.loads(inst.read_text(encoding="utf-8"))
            cfg.update({k: v for k, v in data.items()
                        if k in DEFAULT and isinstance(v, str) and v.strip()})
            # Servers the harness brings itself (claude-in-chrome on the Windows instance, 2026-11-05):
            # no .mcp.json and no plugin names them, the table documents them on purpose.
            builtin = {s for s in data.get("builtin_servers") or [] if isinstance(s, str) and s.strip()}
        except (ValueError, AttributeError) as e:
            print(f"!! mcp-table: {inst.relative_to(root).as_posix()} unreadable ({e})")
            return 1
    table = root / cfg["table"]
    rows = table_rows(table.read_text(encoding="utf-8"), cfg["heading"]) if table.is_file() else None
    if rows is None:
        print(f"!! mcp-table: no table '{cfg['heading']}' in {cfg['table']} for the {len(servers)} "
              f"server(s) of .mcp.json - write it, or point .claude/rules/mcp-table.json at it")
        return 1
    missing, stale = sorted(servers - rows), sorted(rows - servers - plugin_servers(root) - builtin)
    if missing or stale:
        print(f"!! mcp-table: .mcp.json and the MCP table in {cfg['table']} differ - "
              f"no row: {', '.join(missing) or '-'}; row without server: {', '.join(stale) or '-'}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
