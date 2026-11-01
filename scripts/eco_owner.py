#!/usr/bin/env python3
"""eco_owner.py — the ONE GitHub owner a session start treats as "ours".

Every GitHub question the session start asks names one owner: its open PRs (open-items.py,
pr-ball.py), the code-scanning alerts of its repos (code-scanning-alerts.sh) and whether its
shared-memory repo exists (shared-memory-check.sh). They all take the owner from here.

WHY (fresh-brain trial 2026-10-31, measured with a logging gh stand-in): the owner was the org
of the FIRST marketplace in the settings. A stranger who copied a setup naming someone else's
marketplace made every session start query THAT organisation's PRs and repos; a stranger with
only the template placeholder got a red "PRs NOT checked" line that no action could clear.

ORDER (the first answer wins):
  1. "owner" in the brain's config/ecosystem.json — the operator's word. No network.
  2. The org of the first marketplace (.claude/settings.json, then the user settings) — only
     when the gh login can see that repo AND it is private or the login may write to it. A
     marketplace the login cannot see is someone else's; a public one anyone can read (a
     vendor's, the one a template names) says nothing about whose brain this is.
  3. The gh login itself — the user's own PRs.
  4. None: prints nothing; open-items.py then names how to set the owner, in one neutral line.
A template placeholder (`<...>`, `your-org`) is never an owner at any step, and a placeholder
marketplace never falls through to the next one (a vendor's is no owner either).

Steps 2 and 3 are ONE GraphQL call (about 0.4 s). gh missing, not logged in or offline: silent,
no wait beyond the timeout; the last answer gh gave for the same marketplace stands in
(.claude-state/eco-owner.json), so an offline start still searches the known owner and says
NOT checked when that search fails — a real failure keeps its loud line. A resume or
compaction of the same session reuses the answer without a call.

Usage: eco_owner.py [--root <brain>] [--hook-input '<SessionStart JSON>']
Prints the owner (or nothing); exit 0. Stdlib only; python3 or python.
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# One call answers step 2 and step 3: the repo's visibility and our permission, and the login.
QUERY = ("query($o: String!, $n: String!) { viewer { login } "
         "repository(owner: $o, name: $n) { isPrivate viewerPermission } }")
VIEWER = "query { viewer { login } }"
WRITE = ("WRITE", "MAINTAIN", "ADMIN")


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def real(o):
    """An owner name, or "" for a template placeholder (`your-org` is a real GitHub org: on
    2026-10-21 a fresh brain listed 41 PRs of strangers as its own work)."""
    o = str(o or "").strip()
    return "" if not o or any(c in o for c in "<>/ ") or o.lower() == "your-org" else o


def marketplace(root):
    """(owner, name) of the FIRST marketplace, or None — also for a placeholder there."""
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    for s in (load(Path(root) / ".claude" / "settings.json"), load(Path(cfg) / "settings.json")):
        for m in (s.get("extraKnownMarketplaces") or {}).values():
            r = ((m or {}).get("source") or {}).get("repo", "") if isinstance(m, dict) else ""
            if "/" not in r:
                continue
            o, n = r.split("/", 1)
            return (o, n) if real(o) else None
    return None


def ask_gh(mk):
    """(login, marketplace_is_ours) from one call, or None when gh gave no answer."""
    args = ["gh", "api", "graphql", "-f", f"query={QUERY if mk else VIEWER}"]
    if mk:
        args += ["-f", f"o={mk[0]}", "-f", f"n={mk[1]}"]
    try:
        r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=5, stdin=subprocess.DEVNULL,
                           env={**os.environ, "GH_PROMPT_DISABLED": "1"})
    except (OSError, subprocess.SubprocessError):
        return None
    # A repo the login cannot see is a GraphQL error: gh exits 1 but still prints the data.
    try:
        data = json.loads(r.stdout or "{}").get("data") or {}
    except (ValueError, AttributeError):
        return None
    login = real((data.get("viewer") or {}).get("login"))
    if not login:
        return None
    repo = data.get("repository") or {}
    return login, bool(repo) and (repo.get("isPrivate") is True or repo.get("viewerPermission") in WRITE)


def resolve(root, session=""):
    """(owner, source); source is ecosystem | marketplace | login | cache | ""."""
    root = Path(root)
    own = real(load(root / "config" / "ecosystem.json").get("owner"))
    if own:
        return own, "ecosystem"
    mk = marketplace(root)
    key = "/".join(mk) if mk else ""
    store = root / ".claude-state" / "eco-owner.json"
    last = load(store)
    last = last if last.get("marketplace") == key and real(last.get("owner")) else {}
    if session and last.get("session") == session:
        return last["owner"], "cache"
    ans = ask_gh(mk)
    if ans is None:
        return (last["owner"], "cache") if last else ("", "")
    login, ours = ans
    owner, source = (mk[0], "marketplace") if ours else (login, "login")
    try:
        store.parent.mkdir(parents=True, exist_ok=True)
        with open(store, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"marketplace": key, "session": session, "owner": owner, "source": source}, f)
    except OSError:
        pass
    return owner, source


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root")
    ap.add_argument("--hook-input", default="")
    a = ap.parse_args()
    if a.root is None:
        sys.path.insert(0, str(HERE))
        from project_dir import resolve_project_dir
        a.root = resolve_project_dir(HERE)
    try:
        session = str((json.loads(a.hook_input) if a.hook_input.strip() else {}).get("session_id") or "")
    except (ValueError, AttributeError):
        session = ""
    owner, _ = resolve(a.root, session)
    if owner:
        print(owner)
    return 0


if __name__ == "__main__":
    sys.exit(main())
