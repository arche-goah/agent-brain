#!/usr/bin/env python3
"""What the others pushed to the shared memory FOR THIS INSTANCE, as readable lines.

WHY (operator order 2026-09-25): the session-start check said "17 new commits" plus a
tally per topic, and stopped there. That is "there is something new, I have not looked"
— and unless the operator then says "yes, read it", what was addressed to this side
sinks. The main information has to be IN the startup message already, so the session's
first answer can carry it without anyone asking.

TWO SOURCES, because the repo carries messages in two places:
  <topic>/LOG.md headings   `## <date> · <von> — AN <addressees>: <title>` — the
                            conversation stream. Some messages live ONLY here (a question,
                            a receipt), so the fact files alone would miss them.
  fact files (added/changed) frontmatter `von` / `audience` / `description` — lint-enforced
                            since 2026-08-21, the description is the file's own main info.
A fact file whose path the new LOG text already names is not printed twice.

WHO "THIS INSTANCE" IS comes from SHARED_MEMORY_SELF (instance data, e.g. the `env` block
of the instance's settings.json): comma-separated tokens such as `emil-macos,emil`. An
entry is dropped when its sender is one of them; it is kept when its addressees name one
of them or everyone (`alle`, `all`, `everyone`, …), or when it names no addressee at all.
Unset: nothing is filtered and the header says so — a filter that silently guesses
"who am I" would drop exactly the entry it guessed wrong about.

Never summarises: every printed text is the author's own heading or description, cut at a
sentence boundary. Read-only. Exit 0 always (an advisory reader, not a gate).

Usage: shared-memory-inbox.py --from SHA [--to SHA] [--repo DIR] [--self a,b] [--max N]
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module  # noqa: E402

_idx = import_module("shared-memory-index")
first_sentence = _idx.first_sentence
read_entry = _idx.read_entry
REPO_DEFAULT = _idx.REPO_DEFAULT

# Spellings of "everyone" measured in the repo's headings and `audience` fields.
EVERYONE = {"alle", "all", "everyone", "alle-collaborator"}
SKIP_FILES = {"INDEX.md", "LOG.md", "README.md", "PEOPLE.md"}
HEADING = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})\s*·\s*(.+?)\s+—\s+(.+)$")
TEXT_CAP = 200


def git(repo: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(repo), "-c", "core.quotepath=off", *args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def tokens(s: str) -> set[str]:
    return {t for t in re.split(r"[^\w-]+", s.lower()) if t}


def addressees(title: str) -> str | None:
    """`AN x + y: title` -> `x + y`; None when the heading names nobody."""
    m = re.match(r"^(?:AN|An|an|TO|To)\s+([^:]+):", title)
    return m.group(1) if m else None


def for_us(sender: str, to: str | None, me: set[str]) -> bool:
    if not me:
        return True
    if tokens(sender) & me:
        return False
    if to is None:
        return True
    words = tokens(to)
    return bool(words & (me | EVERYONE))


def log_items(repo: Path, a: str, b: str, me: set[str]) -> tuple[list[tuple], str]:
    diff = git(repo, "diff", "-U0", a, b, "--", "LOG.md", "*/LOG.md")
    items, added, topic = [], [], ""
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            topic = path.split("/")[0] if "/" in path else "root"
            continue
        if not line.startswith("+") or line.startswith("+++"):
            continue
        text = line[1:]
        added.append(text)
        m = HEADING.match(text)
        if not m:
            continue
        date, sender, title = m.groups()
        if for_us(sender, addressees(title), me):
            items.append((date, topic, sender.strip(), first_sentence(title, TEXT_CAP)))
    return items, "\n".join(added)


def file_items(repo: Path, a: str, b: str, me: set[str], log_text: str) -> list[tuple]:
    items = []
    for line in git(repo, "diff", "--name-status", "--diff-filter=AM", a, b).splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        rel = parts[-1]
        p = repo / rel
        if not rel.endswith(".md") or "/" not in rel or p.name in SKIP_FILES or not p.is_file():
            continue
        if rel in log_text or p.name in log_text:
            continue
        e = read_entry(p, repo)
        if not for_us(e["von"], e["audience"] or None, me):
            continue
        text = first_sentence(e["desc"] or e["name"], TEXT_CAP)
        # Older files carry no frontmatter date; the commit that brought them is the date.
        date = e["date"] or git(repo, "log", "-1", "--format=%as", b, "--", rel).strip() or "?"
        items.append((date, e["topic"], e["von"] or "?", f"{text} ({rel})"))
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=REPO_DEFAULT)
    ap.add_argument("--from", dest="a", required=True, help="last seen commit")
    ap.add_argument("--to", dest="b", default="origin/main")
    ap.add_argument("--self", dest="me", default=os.environ.get("SHARED_MEMORY_SELF", ""))
    ap.add_argument("--max", type=int, default=12)
    args = ap.parse_args()
    # OS-9: the text is the authors' own (umlauts, dashes) and a hook reads it. Unpinned,
    # Windows writes the ANSI codepage and dies on the first unencodable character.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    me = tokens(args.me.replace(",", " "))

    logs, log_text = log_items(args.repo, args.a, args.b, me)
    items = logs + file_items(args.repo, args.a, args.b, me, log_text)
    if not items:
        return 0
    items.sort(key=lambda i: i[0], reverse=True)
    scope = "for this instance" if me else "unfiltered - set SHARED_MEMORY_SELF to filter"
    print(f"shared-memory inbox ({scope}), {len(items)} since last start:")
    for date, topic, sender, text in items[:args.max]:
        print(f"  - {date} [{topic}] {sender}: {text}")
    rest = len(items) - args.max
    if rest > 0:
        print(f"  + {rest} more: core/scripts/shared-memory-inbox.py --from {args.a[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
