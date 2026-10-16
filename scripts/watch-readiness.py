#!/usr/bin/env python3
"""watch-readiness.py — is this instance ready to watch, so that it hears and answers on its own?

Operator order 2026-10-16 (translated): some core functions do not run cleanly by default; the second macOS
machine had no automatic PR and shared-memory watch and would not have answered on its own; core checks are needed
that verify this on every collaborator's instance. Measured the same day on three instances (survey
in the shared-memory `core/` folder): nothing in the core checked whether a watch COULD run. A freshly bootstrapped
brain had no `.claude/rules/collab-watch.json` (the template is not copied at bootstrap), no `SHARED_MEMORY_SELF`
(open-items then cannot tell requests to this instance apart), and the repos where PRs to the instance arrived
were missing from the watch list on all three machines — a PR of one own machine was seen only at the next session
start.

Prints one line per finding, nothing when the instance is ready or does not take part in shared memory at all.
Read-only, no network: it reads the instance's files and the list of PR items open-items.py stored this start.

  watch-readiness.py [--root <brain>] [--days N]

Takes part = the shared-memory clone exists, or SHARED_MEMORY_SELF is set, or collab-watch.json exists.
"""
import argparse, datetime, json, os, re, sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

TEMPLATE = "core/templates/rules-instance/collab-watch.json"


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def shared_repo():
    return Path(os.environ.get("SHARED_MEMORY_REPO") or Path.home() / "Projects" / "brain-shared-memory")


def self_ids(brain):
    """SHARED_MEMORY_SELF from the harness env, else from the brain's settings `env` (same order as device-status)."""
    raw = os.environ.get("SHARED_MEMORY_SELF", "")
    for name in ("settings.local.json", "settings.json"):
        if raw:
            break
        raw = ((load(brain / ".claude" / name, {}) or {}).get("env") or {}).get("SHARED_MEMORY_SELF", "")
    return [t.strip() for t in raw.split(",") if t.strip()]


def watched_repos(cfg):
    """Basenames of every repo in repo_watches (open-items keys PRs by `<repo>#<n>`, without the owner)."""
    out = set()
    for w in (cfg or {}).get("repo_watches") or []:
        for r in w.get("repos") or []:
            out.add(str(r).rsplit("/", 1)[-1].lower())
    return out


def recent_pr_repos(brain, days):
    """Repos that carried an open PR item for this instance within `days` (open-items-seen.json, written this start)."""
    seen = load(brain / ".claude-state" / "open-items-seen.json", {}) or {}
    cutoff = (datetime.date.today() - datetime.timedelta(days=days)).isoformat()
    out = {}
    for key, it in (seen.get("items") or {}).items():
        m = re.match(r"^([\w.-]+)#(\d+)$", key)
        if not m or str((it or {}).get("first", "")) < cutoff:
            continue
        out.setdefault(m.group(1).lower(), []).append(key)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ap.add_argument("--days", type=int, default=7)
    a = ap.parse_args()
    brain = Path(a.root)
    cfg_path = brain / ".claude" / "rules" / "collab-watch.json"
    clone = (shared_repo() / ".git").is_dir()
    ids = self_ids(brain)
    has_cfg = cfg_path.is_file()
    if not (clone or ids or has_cfg):
        return 0  # not part of shared memory: nothing to watch, no nagging

    lines = []
    cfg = None
    if not has_cfg:
        lines.append("no .claude/rules/collab-watch.json — nothing can arm the standing watch; copy "
                     f"{TEMPLATE}, fill every placeholder, then arm it (skill collab-watch)")
    else:
        cfg = load(cfg_path)
        if not isinstance(cfg, dict):
            lines.append(".claude/rules/collab-watch.json is not valid JSON — the watch cannot start")
            cfg = None
        elif re.search(r"<[a-z][\w -]*>", json.dumps({k: v for k, v in cfg.items() if k != "_comment"})):
            lines.append(".claude/rules/collab-watch.json still carries template placeholders (<…>) — fill them, "
                         "the watch refuses to arm on them")
    if clone and not ids:
        lines.append("SHARED_MEMORY_SELF is not set (settings `env`) — requests addressed to this instance are not "
                     "recognised as ours, and the watch gate cannot tell own entries from others'")
    if cfg:
        watched = watched_repos(cfg)
        missing = {r: k for r, k in recent_pr_repos(brain, a.days).items() if r not in watched}
        if missing:
            names = ", ".join(sorted(missing))
            lines.append(f"PRs for this instance arrived in repos the standing watch does not poll: {names} — "
                         "add them to repo_watches in .claude/rules/collab-watch.json")
    for ln in lines:
        print(f"!! watch readiness: {ln}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
