#!/usr/bin/env python3
"""Rotate the shared memory's LOGs by month, and keep new LOG entries short enough to fit.

WHY (operator decision 2026-09-25): `ops/LOG.md` reached 146,019 bytes thirteen days after
it was started — 98 entries averaging ~1.5 KB, most of them prose that lived nowhere else.
The lint flagged "LOG over rotation size" with a fix TEXT that nobody ran, because nothing
ran the lint. A file that size no longer fits one read, so a reader sees part of the
protocol and cannot tell. The operator's ruling: a LOG may rotate, with clean pointers
both ways and nothing lost, and entries are kept as short as possible so a month fits the
limit.

TWO HALVES, one file:
  rotation   every `## <YYYY-MM-DD> …` block of a CLOSED month moves verbatim, in order,
             to `<topic>/archive/LOG-<YYYY-MM>.md` (created with a pointer back); the LOG
             keeps its preamble plus one `Earlier months:` line pointing at every archive.
             `archive/` is already outside the fact-file set of the lint and the index
             generator, so the moved months are neither linted as entries nor indexed.
  entry cap  an entry is a heading plus one line — the substance belongs in a fact file,
             which is indexed and linted. Budget from the measurement: ~225 entries a month
             in `ops` at the September rate, 60,000 bytes / 225 = ~265 bytes each.
             ENTRY_CAP is set to 300 and applies to entries dated from ENTRY_CAP_SINCE on —
             older entries are protocol and are never rewritten.

NOTHING IS LOST, and that is checked, not assumed: the rotation is computed in memory, and
it writes only if every original block appears exactly once in the result (LOG + archives).
A rerun moves nothing (idempotent).

--check is what the session start runs: read-only, silent when nothing is due. It reports
a due rotation, and entries over the cap written by THIS instance (SHARED_MEMORY_SELF, same
tokens as the inbox) — the author is the one who can shorten them.

Usage: shared-memory-log-rotate.py [--repo DIR] [--check | --write] [--today YYYY-MM-DD]
Exit 0 always for --check; --write exits 1 if the balance check fails (nothing written).
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
from pathlib import Path

REPO_DEFAULT = Path(os.environ.get("SHARED_MEMORY_REPO",
                                   Path.home() / "Projects/brain-shared-memory"))
LOG_NAME = "LOG.md"
ARCHIVE_DIR = "archive"
ENTRY_CAP = 300
ENTRY_CAP_SINCE = "2026-09-26"
POINTER_PREFIX = "Earlier months:"
BLOCK_DATE = re.compile(r"^## (\d{4}-\d{2})-\d{2}\b")
# Four heading shapes are live (`· von —`, `von -`, `(note) — von`, …); the sender is
# the first name-like token after the date and an optional time note.
BLOCK_SENDER = re.compile(r"^## \d{4}-\d{2}-\d{2}(?:\s*\([^)]*\))?\s*(?:[·—-]\s*)?([\w-]+)")


def split_log(text: str) -> tuple[str, list[str]]:
    """Preamble and blocks; a block starts at a DATED `## ` heading and keeps its text
    exactly. An undated `## ` inside an entry is a sub-heading and travels with it."""
    parts = re.split(r"(?m)^(?=## \d{4}-\d{2}-\d{2})", text)
    return parts[0], parts[1:]


def month_of(block: str) -> str | None:
    m = BLOCK_DATE.match(block)
    return m.group(1) if m else None


def with_pointer(preamble: str, months: list[str]) -> str:
    links = ", ".join(f"[{m}]({ARCHIVE_DIR}/LOG-{m}.md)" for m in months)
    line = f"{POINTER_PREFIX} {links}\n"
    lines = [ln for ln in preamble.splitlines(keepends=True) if not ln.startswith(POINTER_PREFIX)]
    body = "".join(lines).rstrip("\n")
    return (body + "\n\n" if body else "") + line + "\n"


def archive_head(topic: str, month: str) -> str:
    return (f"# {topic} LOG — {month} (rotated)\n\n"
            f"Moved verbatim from [`{topic}/LOG.md`](../LOG.md) by "
            f"`shared-memory-log-rotate.py`. Newer entries live there.\n\n")


def plan(log: Path, current: str) -> dict:
    text = log.read_text(encoding="utf-8")
    preamble, blocks = split_log(text)
    keep, move = [], {}
    for b in blocks:
        m = month_of(b)
        if m and m < current:
            move.setdefault(m, []).append(b)
        else:
            keep.append(b)
    return {"log": log, "text": text, "preamble": preamble, "blocks": blocks,
            "keep": keep, "move": move}


def rotate(p: dict) -> dict[Path, str]:
    """New file contents, or raises if the balance does not hold."""
    log, topic = p["log"], p["log"].parent.name
    arch_dir = log.parent / ARCHIVE_DIR
    out: dict[Path, str] = {}
    appended: list[str] = []
    for month in sorted(p["move"]):
        target = arch_dir / f"LOG-{month}.md"
        old = target.read_text(encoding="utf-8") if target.is_file() else archive_head(topic, month)
        if not old.endswith("\n"):
            old += "\n"
        blocks = p["move"][month]
        blocks[-1] = blocks[-1] if blocks[-1].endswith("\n") else blocks[-1] + "\n"
        out[target] = old + "".join(blocks)
        appended += blocks
    months = sorted({f.stem[4:] for f in arch_dir.glob("LOG-*.md")} | set(p["move"]))
    keep = p["keep"]
    new_log = with_pointer(p["preamble"], months) + "".join(keep)
    out[log] = new_log
    # Balance: every original block exactly once, in LOG or in what was appended.
    before = sorted(b.rstrip("\n") for b in p["blocks"])
    after = sorted([b.rstrip("\n") for b in keep] + [b.rstrip("\n") for b in appended])
    if before != after:
        raise RuntimeError(f"balance check failed for {log}: {len(before)} blocks before, "
                           f"{len(after)} after — nothing written")
    return out


def logs(repo: Path) -> list[Path]:
    return sorted(p for p in repo.glob(f"*/{LOG_NAME}") if ".git" not in p.parts)


def over_cap(p: dict, me: set[str]) -> list[str]:
    hits = []
    for b in p["blocks"]:
        m = re.match(r"^## (\d{4}-\d{2}-\d{2})", b)
        if not m or m.group(1) < ENTRY_CAP_SINCE:
            continue
        size = len(b.rstrip("\n").encode("utf-8"))
        if size <= ENTRY_CAP:
            continue
        s = BLOCK_SENDER.match(b)
        sender = s.group(1).strip() if s else "?"
        if me and not (set(re.split(r"[^\w-]+", sender.lower())) & me):
            continue
        hits.append(f"{p['log'].parent.name} {m.group(1)} {sender} ({size} B)")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=REPO_DEFAULT)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    ap.add_argument("--today", default=dt.date.today().isoformat())
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    current = args.today[:7]
    me = {t for t in re.split(r"[^\w-]+", os.environ.get("SHARED_MEMORY_SELF", "").lower()) if t}
    plans = [plan(log, current) for log in logs(args.repo)]

    if args.write:
        for p in plans:
            if not p["move"]:
                continue
            try:
                files = rotate(p)
            except RuntimeError as e:
                print(f"shared-memory-log-rotate: {e}")
                return 1
            for path, text in files.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8", newline="\n")
            moved = sum(len(v) for v in p["move"].values())
            print(f"rotated {p['log'].parent.name}: {moved} entries -> "
                  f"{', '.join(f'{ARCHIVE_DIR}/LOG-{m}.md' for m in sorted(p['move']))}")
        return 0

    due = [f"{p['log'].parent.name} ({sum(len(v) for v in p['move'].values())})"
           for p in plans if p["move"]]
    if due:
        # Pull first: two instances rotating from stale checkouts would move the same
        # blocks twice and meet in a merge conflict on LOG.md.
        print(f"shared-memory: LOG rotation due before {current} - {', '.join(due)} - pull, run "
              f"core/scripts/shared-memory-log-rotate.py --write, commit, push")
    long_ = [h for p in plans for h in over_cap(p, me)]
    if long_:
        print(f"shared-memory: {len(long_)} own LOG entr{'y' if len(long_) == 1 else 'ies'} over "
              f"{ENTRY_CAP} B (heading + one line, substance in a fact file) - {'; '.join(long_[:5])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
