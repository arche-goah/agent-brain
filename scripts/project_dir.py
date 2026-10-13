"""Where does THIS brain keep its runtime state (`.claude-state/`)? — the Python twin of
scripts/project-dir.sh, same order, same reason (see there): `CLAUDE_PROJECT_DIR` is set for
hooks, not for a Bash/Monitor call, and a fallback to the caller's cwd is a different path per
caller. Order: the env var; the superproject this script is mounted in (the brain); the
repo top the script lives in (a standalone core checkout); `.`.
"""
from __future__ import annotations

import os
import subprocess
from pathlib import Path


def _git(here: Path, *args: str) -> str:
    try:
        r = subprocess.run(["git", "-C", str(here), *args], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout.strip() if r.returncode == 0 else ""


def resolve_project_dir(here: str | Path | None = None) -> str:
    env = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if env:
        return env
    here = Path(here) if here else Path(__file__).resolve().parent
    return (_git(here, "rev-parse", "--show-superproject-working-tree")
            or _git(here, "rev-parse", "--show-toplevel") or ".")
