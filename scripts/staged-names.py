#!/usr/bin/env python3
"""staged-names — block a commit whose STAGED added lines name someone on a brain's watch list.

WHY: `leak-scan.py` ships without names on purpose — a public guard must not name whom it
protects — so in the core and in suite repos it can never catch a person's name. The
names live in each brain (`.claude/rules/leak-names.json`, template in
templates/leak-names.json). Measured on the proving instance: the core had been cleaned
of names, and a branch cut BEFORE that cleanup brought one back into a fixture; only a
hand-resolved merge conflict showed it. This carries the brain's list to every shareable
repo committed from that machine, at the moment the line is staged, without the list
itself ever leaving the brain.

Checks the `names` and `instances` lists (whole words, case-insensitive) against the
ADDED lines of `git diff --cached` in the current repo; removed lines and unstaged
changes are not its business. The core wires no hook: an instance calls this from its
own pre-commit, only in repos that are meant to be shared (e.g. where a
`scripts/leak-scan.py` exists), never in the brain itself, which carries names legitimately.

Usage: staged-names.py [<brain-root>]      (default: $BRAIN_DIR)
Exit 1 = a staged line names someone · 0 = clean, or no watch list (said on stderr) ·
2 = not inside a git repo.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def watch_list(brain: Path):
    f = brain / ".claude/rules/leak-names.json"
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return [str(n).strip().lower() for key in ("names", "instances")
            for n in d.get(key, []) if str(n).strip()]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    arg = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("BRAIN_DIR", "")
    brain = Path(arg)
    names = watch_list(brain) if arg else None
    if not names:
        # a guard that is not configured says so, instead of looking like a clean pass
        print(f"staged-names: no watch list at {(brain / '.claude/rules/leak-names.json').as_posix()}"
              " - nothing checked", file=sys.stderr)
        return 0
    p = subprocess.run(["git", "diff", "--cached", "-U0", "--no-color", "--no-ext-diff"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0:
        print(f"staged-names: git diff failed: {p.stderr.strip()}", file=sys.stderr)
        return 2
    rx = re.compile(r"\b(" + "|".join(re.escape(n) for n in names) + r")\b", re.I)
    hits, path = [], ""
    for line in p.stdout.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else line[4:]
        elif line.startswith("+") and rx.search(line):
            hits.append(f"{path}: {line[1:].strip()[:120]}")
    if hits:
        print(f"{len(hits)} staged line(s) name someone from the brain's watch list:")
        print("\n".join(hits[:10]))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
