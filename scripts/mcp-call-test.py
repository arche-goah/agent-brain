#!/usr/bin/env python3
"""Fixture tests for scripts/mcp-call.py and scripts/mcp-toolcount.py.

A fake stdio MCP server (written into a temp dir, started through a temp .mcp.json) plays
every answer the tools have to judge: a normal reply, a tool error, a server that never
answers, one that dies at start, one that logs to stdout before answering, and a paged
tool list. Both directions: an answer must come through, and a missing or wrong one must
NOT read as success — the second is what the tools exist for.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CALL, COUNT = str(HERE / "mcp-call.py"), str(HERE / "mcp-toolcount.py")

FAKE = r'''
import json, os, sys, time
mode = os.environ.get("FAKE_MODE", "normal")
if mode == "die":
    sys.exit(4)
if mode == "logs":
    print("starting up, not json", flush=True)
TOOLS = [{"name": n, "inputSchema": {"type": "object"}} for n in ("alpha", "beta", "gamma")]
for line in sys.stdin:
    m = json.loads(line)
    if mode == "silent" or "id" not in m:
        continue
    meth, mid = m["method"], m["id"]
    if meth == "initialize":
        r = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}}, "serverInfo": {"name": "fake", "version": "0"}}
    elif meth == "tools/list":
        cur = (m.get("params") or {}).get("cursor")
        if mode == "paged" and not cur:
            r = {"tools": TOOLS[:2], "nextCursor": "p2"}
        elif mode == "paged":
            r = {"tools": TOOLS[2:]}
        else:
            r = {"tools": TOOLS}
    elif meth == "tools/call":
        p = m["params"]
        if mode == "iserror":
            r = {"content": [{"type": "text", "text": "boom"}], "isError": True}
        else:
            r = {"content": [{"type": "text", "text": "echo " + p["name"] + " " + json.dumps(p["arguments"], sort_keys=True) + " " + os.environ.get("FAKE_TAG", "-")}]}
    else:
        print(json.dumps({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no"}}), flush=True)
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": mid, "result": r}), flush=True)
'''


def brain(d, mode="normal", expected=None, extra=None):
    root = Path(d)
    with open(root / "fake.py", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(FAKE)
    servers = {"fake": {"command": sys.executable, "args": ["${CLAUDE_PROJECT_DIR}/fake.py"],
                        "env": {"FAKE_MODE": mode, "FAKE_TAG": "${FAKE_TAG_SRC:-dflt}"}},
               "remote": {"type": "http", "url": "https://example.invalid/mcp"}}
    servers.update(extra or {})
    with open(root / ".mcp.json", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps({"mcpServers": servers}))
    if expected is not None:
        (root / ".claude/rules").mkdir(parents=True)
        with open(root / ".claude/rules/mcp-expected.json", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(expected))
    return root


def run(script, root, *args, env=None):
    e = {**os.environ, "BRAIN_DIR": str(root), **(env or {})}
    e.pop("CLAUDE_PROJECT_DIR", None)  # the tool must set it from the instance root
    p = subprocess.run([sys.executable, script, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=e, timeout=60)
    return p.returncode, p.stdout, p.stderr


def case(title, fn):
    with tempfile.TemporaryDirectory() as d:
        ok, why = fn(d)
    print(("ok  " if ok else "FAIL") + "  " + title + ("" if ok else f" - {why}"))
    return ok


def t_call_answers(d):
    rc, out, err = run(CALL, brain(d), "fake", "alpha", '{"x": 1}')
    return rc == 0 and out.strip() == 'echo alpha {"x": 1} dflt', (rc, out, err)


def t_call_env_expansion(d):
    rc, out, _ = run(CALL, brain(d), "fake", "beta", env={"FAKE_TAG_SRC": "fromenv"})
    return rc == 0 and out.strip() == "echo beta {} fromenv", (rc, out)


def t_call_skips_log_lines(d):
    rc, out, _ = run(CALL, brain(d, "logs"), "fake", "alpha")
    return rc == 0 and "echo alpha" in out, (rc, out)


def t_call_tool_error_is_not_success(d):
    rc, out, _ = run(CALL, brain(d, "iserror"), "fake", "alpha")
    return rc == 1 and "boom" in out, (rc, out)


def t_call_silent_server_times_out(d):
    rc, _, err = run(CALL, brain(d, "silent"), "fake", "alpha", "--timeout", "2")
    return rc == 2 and "NO ANSWER" in err, (rc, err)


def t_call_dead_server(d):
    rc, _, err = run(CALL, brain(d, "die"), "fake", "alpha", "--timeout", "10")
    return rc == 2 and "NO ANSWER" in err, (rc, err)


def t_call_bad_json_args(d):
    rc, _, err = run(CALL, brain(d), "fake", "alpha", "{not json")
    return rc == 3, (rc, err)


def t_call_non_stdio_refused(d):
    rc, _, err = run(CALL, brain(d), "remote", "alpha")
    return rc == 2 and "not a stdio server" in err, (rc, err)


def t_count_match(d):
    rc, out, _ = run(COUNT, brain(d, expected={"fake": 3}))
    return rc == 0 and "ok" in out and "3 tools" in out, (rc, out)


def t_count_deviation_is_a_finding(d):
    # negative control: one tool too many in the expectation must fail, not round off
    rc, out, _ = run(COUNT, brain(d, expected={"fake": 4}))
    return rc == 1 and "DIFF" in out and "(expected 4)" in out, (rc, out)


def t_count_paged_list(d):
    rc, out, _ = run(COUNT, brain(d, "paged", expected={"fake": 3}))
    return rc == 0 and "3 tools" in out, (rc, out)


def t_count_dead_server(d):
    rc, out, _ = run(COUNT, brain(d, "die", expected={"fake": 3}), "--timeout", "10")
    return rc == 1 and "FAIL" in out, (rc, out)


def t_count_without_expectations(d):
    rc, out, _ = run(COUNT, brain(d), "--json")
    data = json.loads(out[out.index("{"):])
    return (rc == 0 and "counting only" in out and data["fake"]["count"] == 3
            and "skip" in out and "remote" not in data), (rc, out)


def t_count_no_mcp_json(d):
    rc, out, _ = run(COUNT, Path(d))
    return rc == 2, (rc, out)


if __name__ == "__main__":
    results = [
        case("call: the tool's text comes back", t_call_answers),
        case("call: ${VAR:-default} in .mcp.json env is expanded", t_call_env_expansion),
        case("call: stdout log lines before the reply are skipped", t_call_skips_log_lines),
        case("call: isError is exit 1, not success", t_call_tool_error_is_not_success),
        case("call: a silent server times out with exit 2", t_call_silent_server_times_out),
        case("call: a server that dies at start is exit 2", t_call_dead_server),
        case("call: arguments that are not JSON are a usage error", t_call_bad_json_args),
        case("call: a non-stdio server is refused by name", t_call_non_stdio_refused),
        case("toolcount: matching count passes", t_count_match),
        case("toolcount: a deviation fails (negative control)", t_count_deviation_is_a_finding),
        case("toolcount: a paged tools/list is counted whole", t_count_paged_list),
        case("toolcount: a dead server fails, never counts as 0", t_count_dead_server),
        case("toolcount: no expectations = count every stdio server", t_count_without_expectations),
        case("toolcount: no .mcp.json is exit 2", t_count_no_mcp_json),
    ]
    sys.exit(0 if all(results) else 1)
