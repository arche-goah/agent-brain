#!/usr/bin/env python3
"""Move settled messages of the shared memory into `<area>/archive/<yyyy-mm>/` — relevance, never a
deletion; the index keeps one line per month, every reader still resolves the moved file by its stem.

WHY (agreed by both sides 2026-11-04, shared memory core/reply-shared-memory-tidy-up…): core/INDEX.md
held ~650 entries, ~200 KB, and the settled requests, replies and notes buried the durable facts. The
condition the collaborator's AI set: the tools find a moved file by its file name — 66 ledger pointers
in one brain name shared-memory paths, and a move without a resolver breaks each of them. The
resolver shipped first (index, lint, inbox, the answers reader); this mover runs only on top of it.

What moves: a MESSAGE (request-, reply-, note-, claim- by file name) that is settled — its
`status:` is not open, or an `answers:`/`closes:` (file or LOG) settled it — and whose date is
older than --days (default 14). Durable entries (decisions, references, conventions) never move.
How: `git mv <area>/<slug>.md <area>/archive/<yyyy-mm>/<slug>.md` (yyyy-mm from the entry's date),
so the inbox reads a rename, not a deletion; the file's text is untouched, its stem is unchanged,
`answers:` pointing at it keep settling. Then the index is regenerated (--write only).

Usage: shared-memory-archive.py [--repo DIR] [--days N] [--today YYYY-MM-DD] [--write]
Dry run by default: prints what would move. Exit 0; 2 = could not run.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import subprocess
import sys
from importlib import import_module
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
smi = import_module("shared-memory-index")


def candidates(repo: Path, days: int, today: str | None = None) -> list[dict]:
    """Settled messages older than `days`, oldest first."""
    _root, _topics, entries, _opens = smi.build(repo, today=today)
    logs = [p.read_text(encoding="utf-8", errors="replace") for p in repo.glob(f"*/{smi.LOG_NAME}")]
    settled = smi.settled_stems(entries, logs)
    cutoff = ((_dt.date.fromisoformat(today) if today else _dt.date.today()) - _dt.timedelta(days=days)).isoformat()
    out = []
    for e in entries:
        if e.get("archived") or not smi.is_message(e) or not e.get("date") or e["date"] >= cutoff:
            continue
        if e["status"] == smi.OPEN_STATUS and Path(e["path"]).stem not in settled:
            continue  # still open: stays where a reader looks for it
        out.append(e)
    return sorted(out, key=lambda x: (x["date"], x["path"]))


def target_of(e: dict) -> str:
    return f"{e['topic']}/archive/{e['date'][:7]}/{Path(e['path']).name}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=smi.REPO_DEFAULT)
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--today", help="YYYY-MM-DD (fixtures); default: today")
    ap.add_argument("--write", action="store_true", help="move the files with git mv and regenerate the index")
    a = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):  # entry titles can carry characters cp1252 cannot encode
        sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    repo = a.repo.resolve()
    if not (repo / ".git").exists():
        print(f"ERROR: {repo} is no git checkout - the move has to be a git rename", file=sys.stderr)
        return 2
    moves = candidates(repo, a.days, a.today)
    if not moves:
        print(f"shared-memory-archive: nothing to move (settled messages older than {a.days} days: 0)")
        return 0
    for e in moves:
        print(f"  {e['path']}  ->  {target_of(e)}")
    if not a.write:
        print(f"shared-memory-archive: {len(moves)} settled message(s) older than {a.days} days would move - "
              "dry run, nothing moved; re-run with --write")
        return 0
    for e in moves:
        dst = repo / target_of(e)
        dst.parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(["git", "-C", str(repo), "mv", e["path"], target_of(e)], capture_output=True, text=True)
        if r.returncode:
            print(f"ERROR: git mv {e['path']}: {r.stderr.strip()[:160]}", file=sys.stderr)
            return 2
    r = subprocess.run([sys.executable, str(HERE / "shared-memory-index.py"), "--repo", str(repo), "--write"],
                       capture_output=True, text=True)
    if r.returncode:
        print(f"ERROR: index regeneration failed: {(r.stderr or r.stdout).strip()[:200]}", file=sys.stderr)
        return 2
    print(f"shared-memory-archive: {len(moves)} message(s) moved (git mv), index regenerated - "
          "commit the moves and the index pages together")
    return 0


if __name__ == "__main__":
    sys.exit(main())
