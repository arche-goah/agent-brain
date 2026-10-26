#!/usr/bin/env python3
"""Every server in .mcp.json has a row in the instance's MCP table, and every row a server.

A server added to .mcp.json while its table row is forgotten (or a row left for a server
that was removed) is a recurring brain-scan finding: measured on the Windows workstation
instance 2026-09-13 and 2026-09-23. Runs at session start (helpers/session-bootup.sh):
silent when both lists match, otherwise one line naming both directions, exit 1.

Where the table lives is instance data, `.claude/rules/mcp-table.json` (template in
templates/rules-instance/): {"table": "<repo-relative file>", "heading": "<heading text>"}.
Default = the core template's place: `.claude/rules/intelligence-instance.md`, section
"## MCP Servers". A row names its servers in its first cell: every backticked name there (`a` / `b`), else one bare name; the header
row "MCP" / "Server" and separator rows are skipped; the section ends at the next heading
of the same or a higher level.

  python3 scripts/mcp-table-check.py [--repo <brain root>]
"""
import argparse
import json
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
        # every backticked name in the first cell (a row may serve `a` / `b`), else one bare name
        names = re.findall(r"`([A-Za-z0-9_][A-Za-z0-9_.-]*)`", first) \
            or re.findall(r"^\s*([A-Za-z0-9_][A-Za-z0-9_.-]*)\s*$", first)
        rows.update(n for n in names if n.lower() not in HEADER_CELLS)
    return rows


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
    inst = root / ".claude" / "rules" / "mcp-table.json"
    if inst.is_file():
        try:
            cfg.update({k: v for k, v in json.loads(inst.read_text(encoding="utf-8")).items()
                        if k in DEFAULT and isinstance(v, str) and v.strip()})
        except ValueError as e:
            print(f"!! mcp-table: {inst.relative_to(root).as_posix()} unreadable ({e})")
            return 1
    table = root / cfg["table"]
    rows = table_rows(table.read_text(encoding="utf-8"), cfg["heading"]) if table.is_file() else None
    if rows is None:
        print(f"!! mcp-table: no table '{cfg['heading']}' in {cfg['table']} for the {len(servers)} "
              f"server(s) of .mcp.json - write it, or point .claude/rules/mcp-table.json at it")
        return 1
    missing, stale = sorted(servers - rows), sorted(rows - servers)
    if missing or stale:
        print(f"!! mcp-table: .mcp.json and the MCP table in {cfg['table']} differ - "
              f"no row: {', '.join(missing) or '-'}; row without server: {', '.join(stale) or '-'}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
