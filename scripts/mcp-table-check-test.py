#!/usr/bin/env python3
"""Fixtures for mcp-table-check.py - both directions for every case."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = os.environ.get("MCP_TABLE_CHECK_SCRIPT") or str(HERE / "mcp-table-check.py")
fails = 0


def check(name, cond, out):
    global fails
    print(("ok    " if cond else "FAIL  ") + name + ("" if cond else f"\n      {out!r}"))
    fails += 0 if cond else 1


def run(root):
    p = subprocess.run([sys.executable, SCRIPT, "--repo", str(root)], capture_output=True, text=True)
    return p.returncode, p.stdout.strip()


def brain(servers, table_text, where=".claude/rules/intelligence-instance.md", cfg=None):
    root = pathlib.Path(tempfile.mkdtemp())
    if servers is not None:
        (root / ".mcp.json").write_text(json.dumps({"mcpServers": {s: {} for s in servers}}), encoding="utf-8")
    if table_text is not None:
        (root / where).parent.mkdir(parents=True, exist_ok=True)
        (root / where).write_text(table_text, encoding="utf-8")
    if cfg is not None:
        (root / ".claude/rules").mkdir(parents=True, exist_ok=True)
        (root / ".claude/rules/mcp-table.json").write_text(json.dumps(cfg), encoding="utf-8")
    return root


TABLE = "# Intelligence\n\n## MCP Servers (real, = .mcp.json)\n\n| MCP | Use case |\n|-----|-----|\n| alpha | a |\n| `beta` | b |\n\n## Next\n\n| gamma | not a server row |\n"

rc, out = run(brain(["alpha", "beta"], TABLE))
check("equal lists are silent", rc == 0 and out == "", out)

rc, out = run(brain(["alpha", "beta", "delta"], TABLE))
check("a server without a row is named", rc == 1 and "no row: delta" in out and "row without server: -" in out, out)

rc, out = run(brain(["alpha"], TABLE))
check("a row without a server is named", rc == 1 and "row without server: beta" in out and "no row: -" in out, out)

rc, out = run(brain(["alpha", "beta", "gamma"], TABLE))
check("the section ends at the next heading (gamma below it is no row)", rc == 1 and "no row: gamma" in out, out)

rc, out = run(brain(None, TABLE))
check("no .mcp.json is silent", rc == 0 and out == "", out)

rc, out = run(brain(["alpha"], "# Intelligence\n\nno table here\n"))
check("servers but no table section is loud", rc == 1 and "no table '## MCP Servers'" in out, out)

ELSEWHERE = "# Servers\n\n## Registered servers\n\n| Server | Machine |\n|---|---|\n| alpha | all |\n| beta | mac |\n"
cfg = {"table": "docs/maintenance/mcp-server.md", "heading": "## Registered servers"}
rc, out = run(brain(["alpha", "beta"], ELSEWHERE, where="docs/maintenance/mcp-server.md", cfg=cfg))
check("the instance file moves the table (silent when equal)", rc == 0 and out == "", out)

rc, out = run(brain(["alpha", "beta"], ELSEWHERE, where="docs/maintenance/mcp-server.md"))
check("without the instance file the default place is read (loud)", rc == 1 and "no table" in out, out)

rc, out = run(brain(["alpha", "beta", "delta"], ELSEWHERE, where="docs/maintenance/mcp-server.md", cfg=cfg))
check("the moved table is compared too", rc == 1 and "no row: delta" in out and "docs/maintenance/mcp-server.md" in out, out)

COMBINED = "## MCP Servers\n\n| MCP | Use |\n|---|---|\n| `arena` / `wire` | one row, two servers |\n| `gma` (beta) | a name plus a note |\n"
rc, out = run(brain(["arena", "wire", "gma"], COMBINED))
check("every backticked name in the first cell counts (combined row, name plus note)", rc == 0 and out == "", out)
rc, out = run(brain(["arena", "gma"], COMBINED))
check("a combined row still names its extra server when that server is gone", rc == 1 and "row without server: wire" in out, out)

print("mcp-table-check-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
