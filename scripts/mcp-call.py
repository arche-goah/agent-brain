#!/usr/bin/env python3
"""mcp-call — call ONE tool of an MCP server over stdio, the way the client does.

WHY: an MCP server is a stdio CHILD of the client, so it runs the code it was started
with. Whoever changes a tool cannot try it without a client reconnect — and "it
compiles" is no proof that it works. This speaks the protocol directly (initialize,
initialized, tools/call), so every tool change is testable the moment it is saved,
with no reconnect and no client. Secrets stay in the child process: only the tool's
answer is printed.

Usage:
  mcp-call.py <server|launcher> <tool> ['<json-args>'] [--timeout S]

  <server>    a server name from the instance's .mcp.json (BRAIN_DIR or cwd); its
              command, args and env are used, with ${VAR} / ${VAR:-default} expanded
              the way the client expands them
  <launcher>  otherwise: an executable started without arguments

Exit: 0 = the tool answered · 1 = the tool or the server reported an error ·
2 = no answer (server did not start, died, or timed out) · 3 = usage error.

The stdio client below is shared with mcp-toolcount.py (loaded from this file, so the
protocol lives in one place).
"""
from __future__ import annotations

import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

PROTOCOL = "2025-06-18"
_VAR = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")


def instance_root() -> Path:
    return Path(os.environ.get("BRAIN_DIR") or os.getcwd()).resolve()


def expand(value: str, env: dict) -> str:
    """${VAR} and ${VAR:-default}, as the client expands .mcp.json values."""
    return _VAR.sub(lambda m: env.get(m.group(1)) or (m.group(2) or ""), value)


def load_servers(root: Path) -> dict | None:
    f = root / ".mcp.json"
    if not f.is_file():
        return None
    return json.loads(f.read_text(encoding="utf-8")).get("mcpServers", {})


def resolve(spec: dict, root: Path):
    """(argv, env) for a .mcp.json server entry, or (None, reason) for a non-stdio one."""
    if spec.get("type", "stdio") != "stdio" or "command" not in spec:
        return None, f"not a stdio server (type={spec.get('type', '?')})"
    env = {**os.environ}
    env.setdefault("CLAUDE_PROJECT_DIR", str(root))
    env.update({k: expand(str(v), env) for k, v in (spec.get("env") or {}).items()})
    cmd = expand(spec["command"], env)
    # shutil.which resolves PATHEXT on Windows (npx -> npx.cmd); a relative command is
    # resolved against the instance root, which is the client's working directory.
    exe = shutil.which(cmd) or shutil.which(str(root / cmd)) or cmd
    return [exe, *(expand(str(a), env) for a in spec.get("args", []))], env


class Session:
    """One stdio MCP session. Lines are read on a thread so a silent server cannot
    block the caller past its deadline (select() does not work on pipes on Windows)."""

    def __init__(self, argv, env=None, cwd=None):
        self.proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, encoding="utf-8", errors="replace")
        self.lines: queue.Queue = queue.Queue()
        self.err: list[str] = []
        threading.Thread(target=self._pump, args=(self.proc.stdout, self.lines), daemon=True).start()
        threading.Thread(target=self._drain, daemon=True).start()

    @staticmethod
    def _pump(stream, q):
        for line in stream:
            q.put(line)
        q.put(None)

    def _drain(self):
        for line in self.proc.stderr:
            self.err.append(line)
            del self.err[:-40]

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def reply(self, want_id, deadline):
        """The message with our id, or None on EOF/timeout. Servers may log to stdout
        before answering; non-JSON lines are skipped."""
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            try:
                line = self.lines.get(timeout=left)
            except queue.Empty:
                return None
            if line is None:
                return None
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == want_id:
                return msg

    def initialize(self, deadline, name="mcp-call"):
        self.send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                   "params": {"protocolVersion": PROTOCOL, "capabilities": {},
                              "clientInfo": {"name": name, "version": "1"}}})
        if self.reply(1, deadline) is None:
            return False
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return True

    def close(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def stderr_tail(self, n=1500):
        return "".join(self.err)[-n:]


def start(target: str, root: Path):
    """Session for a server name from .mcp.json or a bare launcher; (None, reason) if not."""
    servers = load_servers(root) or {}
    if target in servers:
        argv, env = resolve(servers[target], root)
        if argv is None:
            return None, env
    else:
        argv, env = [target], None
    try:
        return Session(argv, env=env, cwd=str(root)), None
    except OSError as e:
        return None, f"start failed: {e}"


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: callers parse this
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("target", help="server name from .mcp.json, or a launcher executable")
    ap.add_argument("tool")
    ap.add_argument("args", nargs="?", default="{}", help="tool arguments as JSON")
    ap.add_argument("--timeout", type=float, default=180)
    a = ap.parse_args()
    try:
        arguments = json.loads(a.args)
    except json.JSONDecodeError as e:
        print(f"arguments are not JSON: {e}", file=sys.stderr)
        return 3

    sess, why = start(a.target, instance_root())
    if sess is None:
        print(f"NO ANSWER: {why}", file=sys.stderr)
        return 2
    deadline = time.monotonic() + a.timeout
    try:
        if not sess.initialize(deadline):
            print("NO ANSWER to initialize", file=sys.stderr)
            print(sess.stderr_tail(), file=sys.stderr)
            return 2
        sess.send({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                   "params": {"name": a.tool, "arguments": arguments}})
        msg = sess.reply(2, deadline)
        if msg is None:
            print("NO ANSWER to tools/call", file=sys.stderr)
            print(sess.stderr_tail(), file=sys.stderr)
            return 2
    finally:
        sess.close()

    if "error" in msg:
        print(json.dumps(msg["error"]))
        return 1
    result = msg.get("result") or {}
    for c in result.get("content") or [{"text": json.dumps(result)}]:
        print(c.get("text", json.dumps(c)))
    return 1 if result.get("isError") else 0


if __name__ == "__main__":
    sys.exit(main())
