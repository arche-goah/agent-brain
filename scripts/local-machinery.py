#!/usr/bin/env python3
"""local-machinery.py — which of this brain's hooks run from the shared core, and which do not?

WHY (measured 2026-10-08 on the proving brain): of 31 hook and stop-check entries, 12 ran from
the released core, 13 from three unmerged development checkouts (the whole session start and
the whole stop dispatcher among them), and 8 from the instance's own scripts — at least four of
them general mechanisms (a read gate before live systems, a time-word gate, a reconnect gate)
that no other brain had. Every brain then behaves differently, a measurement on one says nothing
about the others, and a fix made locally is a fix nobody else gets. Nothing showed it: every
hook worked, so nothing failed.

The invariant: one system. A hook runs from the core, OR it is declared as instance machinery
with the reason it can only live here, OR it is an alpha from a development checkout with an
expiry date. Anything else is a finding at every session start.

Sources: `.claude/settings.json` (hooks) and `.claude/rules/stop-checks.json` (the checks behind
the stop dispatcher). Declarations: `.claude/rules/local-machinery.json`
  {"instance": {"<path as written in the hook>": "<why it can only live in this brain>"},
   "alpha":    {"<path or prefix>": {"until": "YYYY-MM-DD", "why": "<what is being measured>"}}}
A key matches when the hook command contains it.

Usage: local-machinery.py [--repo DIR] [--today YYYY-MM-DD] [--list]
Output: nothing when every entry is core or declared; otherwise one line per kind of finding.
--list prints every entry with its class. Exit 0 always — a bootup line never blocks a start.
"""
import argparse
import datetime
import json
import os
import sys

# The session start reads this output through a pipe; unpinned, Windows Python emits the
# em dashes in the cp1252 codepage and ends lines CRLF (core register docs/os-traps.md OS-9).
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def commands(repo):
    """(origin, command) for every hook and every stop check."""
    out = []
    settings = load(os.path.join(repo, ".claude", "settings.json")) or {}
    for event, matchers in (settings.get("hooks") or {}).items():
        for m in matchers or []:
            for h in m.get("hooks") or []:
                if h.get("command"):
                    out.append((event, h["command"]))
    checks = load(os.path.join(repo, ".claude", "rules", "stop-checks.json"))
    if isinstance(checks, dict):
        checks = checks.get("checks")
    for c in checks or []:
        cmd = c.get("cmd") or c.get("command") if isinstance(c, dict) else None
        if cmd:
            out.append(("stop-check", cmd))
    return out


def classify(cmd, repo):
    norm = cmd.replace("\\", "/")
    if "CLAUDE_PLUGIN_ROOT" in norm or "/core/" in norm:
        return "core"
    for tok in norm.replace('"', " ").split():
        if tok.startswith("core/"):
            return "core"
    if "$CLAUDE_PROJECT_DIR" in norm or "%CLAUDE_PROJECT_DIR%" in norm:
        return "instance"
    root = os.path.abspath(repo).replace("\\", "/")
    for tok in norm.replace('"', " ").split():
        if tok.startswith("/") or (len(tok) > 2 and tok[1] == ":"):
            if tok.startswith(root + "/"):
                return "instance"
            if tok.endswith((".cjs", ".js", ".py", ".sh")):
                return "outside"
    return "instance"


def tool_sources_off_main(repo):
    """Hooks are not the only way local code enters a brain: MCP servers (`.mcp.json`) and skill
    symlinks run straight from suite working trees. Those are fine on main and unreleased code on
    any other branch. Returns `<checkout>@<branch>` for every source checkout outside this brain
    that is not on main/master."""
    import pathlib
    import subprocess
    root = pathlib.Path(repo).resolve()
    paths = []
    mcp = load(str(root / ".mcp.json")) or {}
    for srv in (mcp.get("mcpServers") or {}).values():
        for tok in [srv.get("command") or ""] + [str(x) for x in srv.get("args") or []]:
            if os.path.isabs(tok) and os.path.exists(tok):
                paths.append(pathlib.Path(tok))
    skills = root / ".claude" / "skills"
    if skills.is_dir():
        paths += [p.resolve() for p in skills.iterdir() if p.is_symlink()]
    found = {}
    for p in paths:
        d = p if p.is_dir() else p.parent
        try:
            top = subprocess.run(["git", "-C", str(d), "rev-parse", "--show-toplevel"],
                                 capture_output=True, text=True, timeout=10).stdout.strip()
            if not top or pathlib.Path(top).resolve() == root or top in found:
                continue
            br = subprocess.run(["git", "-C", top, "rev-parse", "--abbrev-ref", "HEAD"],
                                capture_output=True, text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            continue
        found[top] = br
    return [(t, b) for t, b in found.items() if b and b not in ("main", "master")]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args(argv)
    decl = load(os.path.join(a.repo, ".claude", "rules", "local-machinery.json")) or {}
    inst, alpha = decl.get("instance") or {}, decl.get("alpha") or {}

    undeclared, outside, expired = [], [], []
    for origin, cmd in commands(a.repo):
        kind = classify(cmd, a.repo)
        hit_i = next((k for k in inst if k in cmd), None)
        hit_a = next((k for k in alpha if k in cmd), None)
        if a.list:
            print(f"{kind:8} {origin:16} {cmd}")
        if kind == "core":
            continue
        if hit_a:
            until = str((alpha[hit_a] or {}).get("until", ""))
            if not until or until < a.today:
                expired.append(f"{hit_a} (until {until or '?'})")
            continue
        if kind == "instance" and hit_i:
            continue
        (outside if kind == "outside" else undeclared).append(cmd.split()[-1].strip('"') if kind == "instance" else cmd)

    def short(items):
        seen = []
        for i in items:
            if i not in seen:
                seen.append(i)
        return ", ".join(seen[:6]) + (f" (+{len(seen) - 6})" if len(seen) > 6 else "")

    # The other way core behaviour drifts: files edited inside the core checkout itself (the pin
    # check in session-bootup.sh sees a moved commit, not uncommitted edits).
    core_dir = os.path.join(a.repo, "core")
    if os.path.isdir(os.path.join(core_dir, ".git")) or os.path.isfile(os.path.join(core_dir, ".git")):
        try:
            import subprocess
            r = subprocess.run(["git", "-C", core_dir, "status", "--porcelain", "--untracked-files=no"],
                               capture_output=True, text=True, timeout=10)
            edited = [ln[3:] for ln in r.stdout.splitlines() if ln.strip()] if r.returncode == 0 else []
        except (OSError, subprocess.SubprocessError):
            edited = []
        if edited:
            print(f"!! local machinery: {len(edited)} core file(s) edited inside core/: {short(edited)} — core changes go as a PR against the core, never edited in place")

    off_main = []
    for top, br in tool_sources_off_main(a.repo):
        hit_a = next((k for k in alpha if k.rstrip("/\\") in top.replace("\\", "/")), None)
        if hit_a:
            until = str((alpha[hit_a] or {}).get("until", ""))
            if not until or until < a.today:
                expired.append(f"{hit_a} (until {until or '?'})")
            continue
        off_main.append(f"{os.path.basename(top)}@{br}")
    if off_main:
        print(f"!! local machinery: {len(off_main)} tool source checkout(s) not on main feed this brain (MCP server or skill symlink): {short(off_main)} — unreleased code in every session; switch the checkout back to main, or declare it as alpha")

    if expired:
        print(f"!! local machinery: {len(set(expired))} alpha(s) past their date, still wired: {short(expired)} — merge, extend with a reason, or unwire")
    if outside:
        print(f"!! local machinery: {len(set(outside))} hook(s) run from outside this brain and outside the core, undeclared: {short(outside)} — for the AI: classify each (why local, sensible, core-worthy?) and declare it as alpha with a date in .claude/rules/local-machinery.json, or open the core PR")
    if undeclared:
        print(f"local machinery: {len(set(undeclared))} instance hook(s) without a reason to live only here: {short(undeclared)} — for the AI: classify each; general = core PR, instance-only = declare why")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
