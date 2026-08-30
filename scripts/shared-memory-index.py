#!/usr/bin/env python3
"""GENERATE the shared-memory index from the files themselves — three levels, routing-first.

WHY this exists, measured on the real repo 2026-08-30: the hand-written INDEX.md was
91,029 characters across 142 entries (median 563). Only 16 % of that — 14k — was title
and path, the part that actually routes. The other 84 % was descriptive prose, and every
one of those 142 files ALREADY carries a `description` in its frontmatter. So the index
was a hand-maintained second copy of data that exists in the files.

That is exactly what the project-ledger rule forbids: "Every overview above the detail
lists is GENERATED, never hand-maintained. A second hand-kept list drifts." It had
drifted — ten substantive files were reachable only by walking the folders, because a
hand-kept list forgets and a generator does not.

The shape this produces:

  INDEX.md            one pointer line per topic. 577 characters — nothing else, see the
                      note at DISCRIMINATOR_CHARS for why no "open" section.
  <topic>/INDEX.md    one routing line per entry in that topic: title, path, and a
                      discriminator cut from the file's own description.
  the file            the full text, where it always was.

Each level has one job, and a reader looking for a show-tools fact never pays for 62
grandMA3 entries. Measured on the real repo: a lookup costs 19,115 characters (~4.8k
tokens) against 91,185 (~22.8k) today — 4.8x cheaper.

WHAT IT NEVER DOES: invent, summarise or shorten a file's content. The discriminator is
the file's own `description`, cut at a sentence boundary. Nothing is deleted, nothing is
moved — this writes index files only.

Usage: shared-memory-index.py [--repo DIR] [--write]
       Without --write it prints what it WOULD produce, plus the size comparison.
Exit 0 always (this is a generator, not a check).
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

REPO_DEFAULT = Path(os.environ.get("SHARED_MEMORY_REPO",
                                   Path.home() / "Projects/brain-shared-memory"))
INDEX_NAME = "INDEX.md"
ROOT_EXEMPT = {INDEX_NAME, "README.md", "PEOPLE.md"}
LOG_NAME = "LOG.md"
# A routing line has to let a reader say "not that one" without opening the file. Measured
# against the real corpus, the first sentence of a description does that in almost every
# case; the cap is a backstop for descriptions written as one long clause.
DISCRIMINATOR_CHARS = 220
# NO "still open" section in the root, and that is a measured decision, not an omission.
# The first draft carried one, keyed on the repo's own priority markers. Measured: 71 of
# 142 files carry a star or a warning sign, so the marker flags half the corpus and
# discriminates nothing. The `audience` field does not carry it either — 18 files write a
# TOPIC there instead of an addressee, next to four spellings of "everyone".
#
# There is simply no field in this repo that reliably says "still needs someone". Two ways
# forward, and both are decisions rather than code: add a status field to the frontmatter
# convention (agree it with the other party first), or leave "what is open" where it is
# already tracked — the instances' own ledgers. The second is preferable: a third open
# list is exactly the drift this generator exists to remove.

FM_DESC = re.compile(r'^description:\s*"?(.*?)"?\s*$', re.M)
FM_NAME = re.compile(r"^name:\s*(.+?)\s*$", re.M)
FM_FIELD = re.compile(r"^\s+(von|audience|topic):\s*(.+?)\s*$", re.M)


def fact_files(repo: Path) -> list[Path]:
    out = []
    for p in sorted(repo.rglob("*.md")):
        rel = p.relative_to(repo)
        if ".git" in rel.parts or "archive" in rel.parts:
            continue
        if len(rel.parts) != 2 or rel.name == LOG_NAME:
            continue
        out.append(p)
    return out


def first_sentence(text: str, cap: int) -> str:
    """The discriminator: enough to rule an entry out, never a summary of the file."""
    text = " ".join(text.split())
    if len(text) <= cap:
        return text
    cut = text[:cap]
    for sep in (". ", " — ", "; ", ": "):
        i = cut.rfind(sep)
        if i > cap // 3:
            return cut[:i + 1].rstrip()
    return cut.rstrip() + "…"


def read_entry(p: Path, repo: Path) -> dict:
    text = p.read_text(encoding="utf-8", errors="replace")
    head = text.split("\n---", 1)[0] if text.startswith("---") else ""
    desc_m = FM_DESC.search(head)
    name_m = FM_NAME.search(head)
    fields = dict(FM_FIELD.findall(head))
    desc = desc_m.group(1) if desc_m else ""
    return {
        "path": str(p.relative_to(repo)),
        "topic": p.relative_to(repo).parts[0],
        "name": name_m.group(1) if name_m else p.stem,
        "desc": desc,
        "audience": fields.get("audience", ""),
        "von": fields.get("von", ""),
    }


def title_of(e: dict) -> str:
    """Human title from the slug — the slug IS the title in this repo's convention."""
    return e["name"].replace("-", " ")


def build(repo: Path) -> tuple[str, dict[str, str], list[dict]]:
    entries = [read_entry(p, repo) for p in fact_files(repo)]
    by_topic: dict[str, list[dict]] = {}
    for e in entries:
        by_topic.setdefault(e["topic"], []).append(e)

    # ── per-topic index: one routing line per entry ────────────────────────
    topic_files = {}
    for topic, es in sorted(by_topic.items()):
        lines = [f"# {topic} — index", "",
                 f"{len(es)} entries. Routing only: title, path, and enough of the entry's "
                 f"own description to rule it out. The full text is in the file; this list "
                 f"is GENERATED (scripts/shared-memory-index.py), do not hand-edit.", ""]
        for e in sorted(es, key=lambda x: x["name"]):
            disc = first_sentence(e["desc"], DISCRIMINATOR_CHARS)
            addr = f" · for: {e['audience']}" if e["audience"] else ""
            lines.append(f"- [{title_of(e)}](../{e['path']}) — {disc}{addr}")
        topic_files[topic] = "\n".join(lines) + "\n"

    # Lines the OLD index carried that this generator does not manage — anything linked
    # from the root that is not a <topic>/<slug>.md fact file. Measured before the first
    # write: one such line existed (a nested README), and regenerating without it would
    # have silently dropped a real entry. They are carried through VERBATIM: this
    # generator may not own them, but it must not lose them either.
    managed = {e["path"] for e in entries}
    carried = []
    old_index = repo / INDEX_NAME
    if old_index.is_file():
        for line in old_index.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.startswith("- ["):
                continue
            targets = re.findall(r"\]\(([^)]+\.md)\)", line)
            if targets and not any(t in managed for t in targets) \
                    and all((repo / t).is_file() for t in targets):
                carried.append(line)

    # ── root: topic pointers, and nothing else (see the note at DISCRIMINATOR_CHARS) ──
    root = ["# Index", "",
            "GENERATED by `scripts/shared-memory-index.py` — do not hand-edit; add a file "
            "with proper frontmatter and regenerate. Three levels on purpose: this page "
            "routes by TOPIC, the topic index routes by ENTRY, the file holds the text. "
            "What is still OPEN is not tracked here — it lives in the instances' ledgers, "
            "where it is already maintained.",
            "", "## Topics", ""]
    for topic, es in sorted(by_topic.items()):
        root.append(f"- [{topic}]({topic}/INDEX.md) — {len(es)} entries")
    if carried:
        root += ["", "## Not one-fact entries", "",
                 "Linked from the old index, outside the `<topic>/<slug>.md` shape this "
                 "generator manages (attachments, delivery copies). Carried through "
                 "unchanged — edit these lines by hand, they survive regeneration.", ""]
        root += carried
    return "\n".join(root) + "\n", topic_files, entries


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=REPO_DEFAULT)
    ap.add_argument("--write", action="store_true",
                    help="write INDEX.md and <topic>/INDEX.md (default: dry run)")
    a = ap.parse_args()
    if not a.repo.is_dir():
        print(f"ERROR: repo not found: {a.repo}", file=sys.stderr)
        return 2

    root, topics, entries = build(a.repo)
    old = (a.repo / "INDEX.md")
    old_size = len(old.read_text(encoding="utf-8")) if old.is_file() else 0

    biggest = max((len(v) for v in topics.values()), default=0)
    lookup_new = len(root) + biggest
    print(f"entries: {len(entries)} across {len(topics)} topics")
    print(f"root index:        {len(root):>7} chars")
    for t, v in sorted(topics.items()):
        print(f"  {t:<16} {len(v):>7} chars")
    print()
    print(f"one lookup TODAY:  {old_size:>7} chars  (~{old_size//4} tokens) — the whole index")
    print(f"one lookup AFTER:  {lookup_new:>7} chars  (~{lookup_new//4} tokens) — root + the "
          f"largest topic")
    if lookup_new:
        print(f"factor:            {old_size/lookup_new:>7.1f}x cheaper per lookup")

    if not a.write:
        print("\ndry run — nothing written. Re-run with --write to produce the files.")
        return 0
    (a.repo / "INDEX.md").write_text(root, encoding="utf-8")
    for t, v in topics.items():
        (a.repo / t / "INDEX.md").write_text(v, encoding="utf-8")
    print(f"\nwritten: INDEX.md + {len(topics)} topic index files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
