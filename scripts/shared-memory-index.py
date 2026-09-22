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
FM_FIELD = re.compile(r"^\s+(von|audience|topic|date):\s*(.+?)\s*$", re.M)
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# `<topic>/INDEX.md` — a page this generator writes itself (see the carry rule in build()).
TOPIC_INDEX = re.compile(r"^[^/]+/" + re.escape(INDEX_NAME) + r"$")


# FRESHNESS. The operator's order (2026-09-13): a session must be able to ask "what is
# NEW in the shared record since I last looked, in the topic I am working on" — at
# bootup and mid-session — and that needs a date per entry that the register can filter
# on. Measured that day: 0 of 240 entries carried one. Every filename with a date in it
# and every "measured on 2026-…" in the prose is a date for a human, not for a filter.
#
# Two sources, and the index says which one it used:
#   frontmatter `date:`  — the author's claim, the convention going forward (README);
#   git                  — the last commit that touched the file, for everything older.
# git is exact and needs no back-fill, so no legacy file is left undated. It is also the
# WRONG date for a file that was edited later (a later addendum moves it), which is
# precisely why the field exists: the author says what the entry is dated, git only says
# when it last changed. Marked `~` in the index line so a reader can tell the two apart.
def git_dates(repo: Path) -> dict[str, str]:
    """One pass, newest first, so the FIRST time a path appears is its latest commit."""
    import subprocess
    out: dict[str, str] = {}
    try:
        log = subprocess.run(
            ["git", "-C", str(repo), "log", "--format=%cs", "--name-only", "--", "*.md"],
            capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return out
    date = ""
    for line in log.splitlines():
        if ISO_DATE.match(line):
            date = line
        elif line and date and line not in out:
            out[line] = date
    return out


def fact_files(repo: Path) -> list[Path]:
    out = []
    for p in sorted(repo.rglob("*.md")):
        rel = p.relative_to(repo)
        if ".git" in rel.parts or "archive" in rel.parts:
            continue
        # A per-topic INDEX.md is an index, not an entry — the lint already knows that,
        # the generator did not: it listed its own output as a dated fact ("INDEX —
        # ~2026-09-13") the first time dates made the line visible.
        if len(rel.parts) != 2 or rel.name in (LOG_NAME, INDEX_NAME):
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


def read_entry(p: Path, repo: Path, gitdates: dict[str, str] | None = None) -> dict:
    text = p.read_text(encoding="utf-8", errors="replace")
    head = text.split("\n---", 1)[0] if text.startswith("---") else ""
    desc_m = FM_DESC.search(head)
    name_m = FM_NAME.search(head)
    fields = dict(FM_FIELD.findall(head))
    desc = desc_m.group(1) if desc_m else ""
    rel_posix = p.relative_to(repo).as_posix()
    fm_date = fields.get("date", "")
    if ISO_DATE.match(fm_date):
        date, date_src = fm_date, "frontmatter"
    elif gitdates and rel_posix in gitdates:
        date, date_src = gitdates[rel_posix], "git"
    else:
        date, date_src = "", ""
    return {
        "date": date,
        "date_src": date_src,
        # as_posix: this string becomes a markdown link target AND is matched against
        # the old index to decide what is carried through verbatim. With backslashes
        # (Windows) nothing matches, so the generator carried EVERY existing entry into
        # the root index — measured 2026-08-31: root 83,205 chars instead of the routing
        # page, and every link it wrote was unfollowable.
        "path": p.relative_to(repo).as_posix(),
        "topic": p.relative_to(repo).parts[0],
        "name": name_m.group(1) if name_m else p.stem,
        "desc": desc,
        "audience": fields.get("audience", ""),
        "von": fields.get("von", ""),
    }


def title_of(e: dict) -> str:
    """Human title from the slug — the slug IS the title in this repo's convention."""
    return e["name"].replace("-", " ")


def date_mark(e: dict) -> str:
    """`2026-09-13` from the author, `~2026-09-13` when only git could say."""
    if not e.get("date"):
        return ""
    return e["date"] if e.get("date_src") == "frontmatter" else "~" + e["date"]


def since(entries: list[dict], day: str) -> list[dict]:
    """Entries dated on or after `day`, newest first — the freshness filter a bootup or
    a topic-time recall asks. ISO dates compare as strings, so no parsing is needed and
    no locale can get in the way."""
    hits = [e for e in entries if e.get("date") and e["date"] >= day]
    return sorted(hits, key=lambda e: (e["date"], e["name"]), reverse=True)


def build(repo: Path) -> tuple[str, dict[str, str], list[dict]]:
    gitdates = git_dates(repo)
    entries = [read_entry(p, repo, gitdates) for p in fact_files(repo)]
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
            dm = date_mark(e)
            when = f" · {dm}" if dm else ""
            lines.append(f"- [{title_of(e)}](../{e['path']}) — {disc}{addr}{when}")
        topic_files[topic] = "\n".join(lines) + "\n"

    # Lines the OLD index carried that this generator does not manage — anything linked
    # from the root that is not a <topic>/<slug>.md fact file. Measured before the first
    # write: one such line existed (a nested README), and regenerating without it would
    # have silently dropped a real entry. They are carried through VERBATIM: this
    # generator may not own them, but it must not lose them either.
    # A generator may not re-ingest its own output. The topic pointers it writes into the
    # root (`- [ops](ops/INDEX.md) — 98 entries`) are `- [` lines pointing at real files
    # that are not fact files, so the rule below read them as foreign and copied them down
    # into "Not one-fact entries" — one more generation on every run (measured 2026-09-21
    # in the shared repo: three generations standing, a fourth added by the run that found
    # it; reported by bojan-main, who had removed the newest set by hand). Matched by
    # PATTERN, not against the current topic list, so a pointer of a topic that no longer
    # exists is dropped as well. The `seen` guard closes the same class one level up: a
    # duplicate line already in the old index is carried once, not twice.
    managed = {e["path"] for e in entries}
    carried = []
    seen = set()
    old_index = repo / INDEX_NAME
    if old_index.is_file():
        for line in old_index.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.startswith("- ["):
                continue
            targets = re.findall(r"\]\(([^)]+\.md)\)", line)
            if targets and not any(t in managed or TOPIC_INDEX.match(t) for t in targets) \
                    and all((repo / t).is_file() for t in targets) \
                    and line not in seen:
                seen.add(line)
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
        newest = max((e["date"] for e in es if e.get("date")), default="")
        tail = f" · newest {newest}" if newest else ""
        root.append(f"- [{topic}]({topic}/INDEX.md) — {len(es)} entries{tail}")
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
    ap.add_argument("--since", metavar="YYYY-MM-DD",
                    help="print entries dated on/after this day, newest first, and exit "
                         "— the freshness filter for a bootup or a topic-time recall; "
                         "writes nothing")
    ap.add_argument("--topic", help="with --since: restrict to one topic folder")
    a = ap.parse_args()
    if not a.repo.is_dir():
        print(f"ERROR: repo not found: {a.repo}", file=sys.stderr)
        return 2

    root, topics, entries = build(a.repo)
    if a.since:
        if not ISO_DATE.match(a.since):
            print(f"ERROR: --since wants YYYY-MM-DD, got {a.since!r}", file=sys.stderr)
            return 2
        hits = since(entries, a.since)
        if a.topic:
            hits = [e for e in hits if e["topic"] == a.topic]
        undated = sum(1 for e in entries if not e.get("date"))
        for e in hits:
            addr = f" · for: {e['audience']}" if e["audience"] else ""
            print(f"- {date_mark(e)} [{e['topic']}] {title_of(e)} — "
                  f"{first_sentence(e['desc'], DISCRIMINATOR_CHARS)}{addr} ({e['path']})")
        # The count line is the measurement; the list above is the evidence. The undated
        # count is printed even at zero — "nothing undated" and "did not look" must not
        # read the same.
        print(f"since {a.since}: {len(hits)} entr{'y' if len(hits) == 1 else 'ies'}"
              f"{' in ' + a.topic if a.topic else ''}, {undated} undated (not filterable)")
        return 0
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
        # The direction is COMPUTED, never assumed. "cheaper" was a fixed word next to a
        # ratio that can fall below 1 — and it now does routinely: once the split this
        # figure argued for has happened, the comparison is "already split against split",
        # and the run reported "0.1x cheaper per lookup" for a lookup ten times dearer.
        # Reported by the other instance from a real run; the arithmetic was never wrong,
        # only the one word quitting two opposite cases.
        ratio = old_size / lookup_new
        if ratio >= 1:
            print(f"factor:            {ratio:>7.1f}x CHEAPER per lookup")
        else:
            print(f"factor:            {1 / ratio:>7.1f}x MORE EXPENSIVE per lookup "
                  f"— the index is already split; this compares split against split")

    if not a.write:
        print("\ndry run — nothing written. Re-run with --write to produce the files.")
        return 0
    # newline="\n": write_text translates \n to the platform separator, so on Windows
    # this generator produced CRLF in a repo whose .gitattributes says LF — every line of
    # the generated index shows as changed, or git rewrites the file behind the run.
    # Measured 2026-08-31: 17 of 17 lines CRLF in the root index. Same class as the
    # generators fixed in #34.
    (a.repo / "INDEX.md").write_text(root, encoding="utf-8", newline="\n")
    for t, v in topics.items():
        (a.repo / t / "INDEX.md").write_text(v, encoding="utf-8", newline="\n")
    print(f"\nwritten: INDEX.md + {len(topics)} topic index files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
