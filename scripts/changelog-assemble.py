#!/usr/bin/env python3
"""Assemble the CHANGELOG at the release cut: fragments in, a version header over them.

WHY: every parallel PR wrote into the one `## Unreleased` section of CHANGELOG.md, so every
second PR collided at the same line (five times in one day, measured 2026-10-11 on the core;
a resolution once produced a doubled header, and a collision cost a PR its CI visibility).
Agreed with every collaborator (shared memory, ops, 2026-09-02 / 2026-10-10): each PR writes
its entry as its OWN file `changelog.d/<slug>.md` — no shared anchor, no collision — and the
release cut moves them under the new version header in one commit by one session.

What it does: takes every `changelog.d/*.md` except README.md, sorted by name, plus whatever
still stands under `## Unreleased` (entries written before the switch), writes them as
`## <version> — <date>` in place of `## Unreleased` (or above the newest released section),
and deletes the fragments. Refuses when the version section exists already or when
there is nothing to release.

Usage: changelog-assemble.py X.Y.Z [--root DIR] [--date YYYY-MM-DD] [--dry-run]
Exit 0 written (or dry-run), 1 refused, 2 usage.
"""
import argparse
import datetime
import pathlib
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

UNRELEASED = re.compile(r"^## Unreleased[ \t]*\n(.*?)(?=^## |\Z)", re.S | re.M)


def fragments(root):
    d = root / "changelog.d"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("*.md") if p.name.lower() != "readme.md")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", a.version):
        print("usage: changelog-assemble.py X.Y.Z (no leading v)", file=sys.stderr)
        return 2
    root = pathlib.Path(a.root)
    cl = root / "CHANGELOG.md"
    text = cl.read_text(encoding="utf-8")
    if re.search(rf"^## {re.escape(a.version)}( |$)", text, re.M):
        print(f"refused: CHANGELOG.md already has a '## {a.version}' section")
        return 1

    frags = fragments(root)
    # The slug stays as an invisible marker: a debt named in a fragment and the later change that
    # settles it (`settles-debt: <slug>`, helpers/change-level.cjs) must survive the cut.
    parts = [(p.read_text(encoding="utf-8").strip() + f" <!-- fragment: {p.stem} -->")
             if p.read_text(encoding="utf-8").strip() else "" for p in frags]
    m = UNRELEASED.search(text)
    legacy = m.group(1).strip() if m else ""
    if legacy:
        parts.append(legacy)
    parts = [p for p in parts if p]
    if not parts:
        print("refused: nothing to release — no fragment in changelog.d/ and nothing under ## Unreleased")
        return 1

    section = f"## {a.version} — {a.date}\n\n" + "\n\n".join(parts) + "\n\n"
    if m:
        text = text[:m.start()] + section + text[m.end():]
    else:
        first = re.search(r"^## ", text, re.M)
        at = first.start() if first else len(text)
        text = text[:at] + section + text[at:]

    print(f"{'would write' if a.dry_run else 'wrote'} ## {a.version}: {len(frags)} fragment(s)"
          f"{' + the old ## Unreleased entries' if legacy else ''}")
    if a.dry_run:
        return 0
    with open(cl, "w", encoding="utf-8", newline="\n") as f:  # LF pinned, works on 3.9 (OS-2, OS-13)
        f.write(text)
    for p in frags:
        p.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
