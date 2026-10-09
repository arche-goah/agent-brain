#!/usr/bin/env python3
"""mcp-toolcount — start each MCP server the way the client does and count the tools it offers.

WHY: a server that starts is not a server that works. After a repo split, a move or an
update the failure is silent — a moved file, a stale path, a half-registered tool — and
the client shows it hours later as "the tool is missing". This speaks MCP over stdio
(initialize, tools/list), so it needs no client and no hardware, and compares the count
against the number the instance wrote down. A deviation in EITHER direction is a
finding: a tool that vanished, or one that was added without being written down.

Usage:
  mcp-toolcount.py [server ...] [--expected FILE] [--timeout S] [--json]

  no names     every stdio server in the instance's .mcp.json that has an expected
               count (or every stdio server, when the instance keeps no expectations)
  --expected   default <instance>/.claude/rules/mcp-expected.json — {"<server>": N};
               template in core templates/mcp-expected.json. List only servers that
               start without hardware or a running application.

The instance is BRAIN_DIR or the cwd. Exit 0 = every checked server answered and
matched · 1 = a deviation or a server that did not answer · 2 = no .mcp.json.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import time
from pathlib import Path

_spec = importlib.util.spec_from_file_location("mcp_call", Path(__file__).with_name("mcp-call.py"))
mcp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mcp)


def count_tools(name, root, timeout):
    sess, why = mcp.start(name, root)
    if sess is None:
        return None, why
    deadline = time.monotonic() + timeout
    try:
        if not sess.initialize(deadline, name="mcp-toolcount"):
            return None, "no initialize reply"
        sess.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        msg = sess.reply(2, deadline)
        if msg is None:
            return None, "no tools/list reply"
        if "error" in msg:
            return None, f"tools/list error: {msg['error']}"
        # tools/list may page; follow nextCursor so a long tool list is counted whole
        tools = list(msg.get("result", {}).get("tools", []))
        cursor, rid = msg.get("result", {}).get("nextCursor"), 3
        while cursor:
            sess.send({"jsonrpc": "2.0", "id": rid, "method": "tools/list",
                       "params": {"cursor": cursor}})
            page = sess.reply(rid, deadline)
            if page is None or "error" in page:
                return None, "tools/list page missing"
            tools += page.get("result", {}).get("tools", [])
            cursor, rid = page.get("result", {}).get("nextCursor"), rid + 1
        return [t.get("name", "?") for t in tools], None
    finally:
        sess.close()


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: --json is parsed
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("servers", nargs="*", help="limit to these server names")
    ap.add_argument("--expected", help="expected counts (JSON object server -> N)")
    ap.add_argument("--timeout", type=float, default=45)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = mcp.instance_root()
    cfg = mcp.load_servers(root)
    if cfg is None:
        print(f"no .mcp.json in {root.as_posix()}")
        return 2
    exp_file = Path(args.expected) if args.expected else root / ".claude/rules/mcp-expected.json"
    expected = {}
    if exp_file.is_file():
        expected = {k: v for k, v in json.loads(exp_file.read_text(encoding="utf-8")).items()
                    if not k.startswith("_")}
    else:
        print(f"note: no expected counts at {exp_file.as_posix()} - counting only")
    targets = args.servers or [n for n in cfg if n in expected] or list(cfg)

    results, worst = {}, 0
    for name in targets:
        spec = cfg.get(name)
        if spec is None:
            print(f"FAIL  {name:16s} not in .mcp.json")
            results[name], worst = {"error": "not in .mcp.json"}, 1
            continue
        if spec.get("type", "stdio") != "stdio":
            print(f"skip  {name:16s} not a stdio server")
            continue
        names, err = count_tools(name, root, args.timeout)
        want = expected.get(name)
        if err:
            print(f"FAIL  {name:16s} {err}")
            results[name], worst = {"error": err}, 1
            continue
        ok = want is None or len(names) == want
        print(f"{'ok  ' if ok else 'DIFF'}  {name:16s} {len(names):3d} tools"
              + ("" if want is None else f"  (expected {want})"))
        worst = worst if ok else 1
        results[name] = {"count": len(names), "expected": want, "tools": names}

    if args.json:
        print(json.dumps(results, indent=2))
    return worst


if __name__ == "__main__":
    sys.exit(main())
