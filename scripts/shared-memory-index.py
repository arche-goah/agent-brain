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
                      discriminator cut from the file's own description — plus, since
                      2026-10-14, what the entry's ROUTING FIELDS say (status when it is
                      not plain info, who is on the move, what it is related to and what is
                      related to IT, what it supersedes), and the entries other areas file
                      here through `topics`.
  <topic>/OPEN.md     the area's `status: open` entries, one line each: who is on the move,
                      the age, the title, the path. Written when an area has open entries,
                      and rewritten (as "nothing open") only where it already exists — so a
                      stale list never stands and no area gets an empty page it never asked for.
  the file            the full text, where it always was.

Each level has one job, and a reader looking for a fact in one area never pays for the
62 entries of another. Measured on the real repo: a lookup costs 19,115 characters (~4.8k
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
from datetime import date as _date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module  # noqa: E402

# ONE frontmatter parser for the repo: the lint's. The routing fields are lists, and a
# second regex parser here would read them differently on the first edge case.
_lint = import_module("shared-memory-lint")

REPO_DEFAULT = Path(os.environ.get("SHARED_MEMORY_REPO",
                                   Path.home() / "Projects/brain-shared-memory"))
INDEX_NAME = "INDEX.md"
ROOT_EXEMPT = {INDEX_NAME, "README.md", "PEOPLE.md"}
LOG_NAME = "LOG.md"
OPEN_NAME = _lint.OPEN_NAME
OPEN_STATUS = "open"
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
# There was no field in this repo that reliably said "still needs someone", and the two ways
# forward were both decisions rather than code. The first one was taken on 2026-10-14, by
# both parties that write the repo: a `status` field (with `next`, `related`, `topics`,
# `supersedes` — the ROUTING FIELDS, docs/shared-memory-fields.md). What is open is still
# NOT listed in the root — a root list would grow with the corpus and be read whole every
# time; the root pointer line carries the COUNT (`· 3 open`), and the list lives per area in
# `<area>/OPEN.md`, generated from the files, so it cannot drift.

FM_DESC = re.compile(r'^description:\s*"?(.*?)"?\s*$', re.M)
FM_NAME = re.compile(r"^name:\s*(.+?)\s*$", re.M)
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# `<topic>/INDEX.md` and `<topic>/OPEN.md` — pages this generator writes itself (see the
# carry rule in build()).
TOPIC_INDEX = re.compile(r"^[^/]+/(" + re.escape(INDEX_NAME) + "|" + re.escape(OPEN_NAME) + r")$")


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
def git_dates(repo: Path, ref: str | None = None) -> dict[str, str]:
    """One pass, newest first, so the FIRST time a path appears is its latest commit."""
    import subprocess
    out: dict[str, str] = {}
    try:
        log = subprocess.run(
            ["git", "-C", str(repo), "log", "--format=%cs", "--name-only", *([ref] if ref else []), "--", "*.md"],
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


def blobs_at(repo: Path, ref: str) -> dict[str, str]:
    """rel path -> content of every .md at `ref`, in ONE git process. A caller that only
    FETCHED (the session-start check) has the new state in refs, not in the working tree:
    reading the disk there missed new entries and read changed ones in their old form
    (measured on the workstation 2026-09-30)."""
    import subprocess
    names = subprocess.run(["git", "-C", str(repo), "-c", "core.quotepath=off", "ls-tree", "-r",
                            "--name-only", ref], capture_output=True, text=True,
                           encoding="utf-8").stdout.splitlines()
    names = [n for n in names if n.endswith(".md")]
    raw = subprocess.run(["git", "-C", str(repo), "cat-file", "--batch"],
                         input="".join(f"{ref}:{n}\n" for n in names).encode("utf-8"),
                         capture_output=True).stdout
    out, pos = {}, 0
    for n in names:
        nl = raw.index(b"\n", pos)
        header = raw[pos:nl].split()
        pos = nl + 1
        if len(header) < 3 or header[1] != b"blob":
            continue
        size = int(header[2])
        out[n] = raw[pos:pos + size].decode("utf-8", errors="replace")
        pos += size + 1
    return out


def fact_files(repo: Path, rels: list[str] | None = None) -> list[Path]:
    out = []
    for p in sorted(repo / r for r in rels) if rels is not None else sorted(repo.rglob("*.md")):
        rel = p.relative_to(repo)
        if ".git" in rel.parts or "archive" in rel.parts:
            continue
        # A per-topic INDEX.md is an index, not an entry — the lint already knows that,
        # the generator did not: it listed its own output as a dated fact ("INDEX —
        # ~2026-09-13") the first time dates made the line visible.
        if len(rel.parts) != 2 or rel.name in (LOG_NAME, INDEX_NAME, OPEN_NAME):
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


def read_entry(p: Path, repo: Path, gitdates: dict[str, str] | None = None,
               text: str | None = None) -> dict:
    # `text` given: the content comes from git (a fetched, not yet pulled commit), not disk.
    if text is None:
        text = p.read_text(encoding="utf-8", errors="replace")
    head = text.split("\n---", 1)[0] if text.startswith("---") else ""
    desc_m = FM_DESC.search(head)
    name_m = FM_NAME.search(head)
    fm = _lint.frontmatter(text) or {}
    fields = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
    desc = desc_m.group(1) if desc_m else ""
    rel_posix = p.relative_to(repo).as_posix()
    fm_date = str(fields.get("date", "") or "")
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
        "audience": str(fields.get("audience", "") or ""),
        "von": str(fields.get("von", "") or ""),
        # the routing fields — absent reads as plain info, unlinked, filed only at home
        "status": (str(fields.get("status", "") or "").strip().lower() or "info"),
        "next": _lint.listify(fields.get("next")),
        "related": _lint.listify(fields.get("related")),
        "topics": _lint.listify(fields.get("topics")),
        "supersedes": (_lint.listify(fields.get("supersedes")) or [""])[0],
        # what this entry settles (docs/shared-memory-audience.md, "Settling a request")
        "settles": _lint.listify(fields.get("answers")) + _lint.listify(fields.get("closes")),
    }


# `answers: <id>` / `closes: <id>` in a LOG entry settles a request like the field in a file.
LOG_SETTLES = re.compile(r"\b(?:answers|closes):\s*([^\s,;)]+(?:\s*,\s*[^\s,;)]+)*)")


def settled_stems(entries: list[dict], log_texts: list[str]) -> set[str]:
    """Stems of requests something settled. Without it OPEN.md listed every answered request as
    open - measured 2026-10-21: 25 lines naming the Windows machine in core/OPEN.md, most of them
    answered days before, while the inbox (which follows `answers:`) showed 3."""
    out = set()
    for t in [x for e in entries for x in e["settles"]] + [
            x.strip() for text in log_texts for m in LOG_SETTLES.findall(text) for x in m.split(",")]:
        if "@" not in t:  # a LOG id settles a LOG-only request, never a file
            out.add(t.rsplit("/", 1)[-1].removesuffix(".md"))
    return out


def age_days(e: dict, today: str | None = None) -> str:
    """`12 d` from the entry's resolved date, "" when it has none."""
    if not e.get("date"):
        return ""
    try:
        today_d = _date.fromisoformat(today) if today else _date.today()
        return f"{(today_d - _date.fromisoformat(e['date'])).days} d"
    except ValueError:
        return ""


def link(e: dict) -> str:
    """A markdown link to an entry from one level down (`<area>/INDEX.md`)."""
    return f"[{title_of(e)}](../{e['path']})"


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


def build(repo: Path, ref: str | None = None, today: str | None = None
          ) -> tuple[str, dict[str, str], list[dict], dict[str, str]]:
    """Returns (root page, {area: index page}, entries, {area: OPEN page}). The OPEN dict
    holds every area with open entries, plus the areas whose OPEN.md already exists on disk
    (rewritten as "nothing open" so a stale list never stands)."""
    gitdates = git_dates(repo, ref)
    if ref:
        blobs = blobs_at(repo, ref)
        entries = [read_entry(p, repo, gitdates, text=blobs[p.relative_to(repo).as_posix()])
                   for p in fact_files(repo, list(blobs))]
    else:
        entries = [read_entry(p, repo, gitdates) for p in fact_files(repo)]
    logs = ([t for n, t in blobs.items() if n.endswith("/" + LOG_NAME)] if ref else
            [p.read_text(encoding="utf-8", errors="replace") for p in repo.glob(f"*/{LOG_NAME}")])
    settled = settled_stems(entries, logs)
    by_path = {e["path"]: e for e in entries}
    by_topic: dict[str, list[dict]] = {}
    for e in entries:
        by_topic.setdefault(e["topic"], []).append(e)
    # a target written as a bare slug resolves like a wikilink (lint, resolve_target)
    stems = {e["name"]: e["path"] for e in entries}
    for e in entries:
        e["related"] = [r for r in (_lint.resolve_target(t, repo, stems) for t in e["related"]) if r]
        e["supersedes"] = _lint.resolve_target(e["supersedes"], repo, stems) or "" if e["supersedes"] else ""
    # ── the routing fields, resolved once ──────────────────────────────────
    # topics: an entry is FILED into further areas, never copied or moved. Only areas that
    # exist as folders get a page (the lint names a `topics` value with no area).
    filed: dict[str, list[dict]] = {}
    for e in entries:
        for t in e["topics"]:
            if t != e["topic"] and (t in by_topic or (repo / t).is_dir()):
                filed.setdefault(t, []).append(e)
    # related: the writer links one direction; the generator writes the other one into the
    # target's index line, so nobody maintains the reverse by hand.
    linked_from: dict[str, list[dict]] = {}
    for e in entries:
        for r in e["related"]:
            if r in by_path and r != e["path"]:
                linked_from.setdefault(r, []).append(e)
    # supersedes: the superseded entry's line points at its successor.
    successor: dict[str, dict] = {}
    for e in entries:
        if e["supersedes"] in by_path and e["supersedes"] != e["path"]:
            successor[e["supersedes"]] = e

    def tail_of(e: dict) -> str:
        """What the routing fields add to an entry's index line — nothing for an entry that
        uses none of them, so the lines of 2026-08-30 are unchanged."""
        parts = []
        if e["path"] in successor:
            parts.append(f"superseded by {link(successor[e['path']])}")
        elif e["status"] != "info":
            parts.append(e["status"])
        if e["next"] and e["status"] == OPEN_STATUS:
            parts.append("next: " + ", ".join(e["next"]))
        rel = [link(by_path[r]) for r in e["related"] if r in by_path and r != e["path"]]
        if rel:
            parts.append("related: " + ", ".join(rel))
        back = [link(x) for x in linked_from.get(e["path"], [])]
        if back:
            parts.append("linked from: " + ", ".join(back))
        if e["supersedes"] in by_path:
            parts.append(f"supersedes {link(by_path[e['supersedes']])}")
        return "".join(f" · {x}" for x in parts)

    # ── per-area index: one routing line per entry, filed entries after the home ones ──
    topic_files = {}
    open_files: dict[str, str] = {}
    open_count: dict[str, int] = {}
    areas = sorted(set(by_topic) | set(filed))
    for topic in areas:
        es = by_topic.get(topic, [])
        more = filed.get(topic, [])
        lines = [f"# {topic} — index", "",
                 f"{len(es)} entries. Routing only: title, path, and enough of the entry's "
                 f"own description to rule it out. The full text is in the file; this list "
                 f"is GENERATED (scripts/shared-memory-index.py), do not hand-edit.", ""]
        for e in sorted(es, key=lambda x: x["name"]):
            disc = first_sentence(e["desc"], DISCRIMINATOR_CHARS)
            addr = f" · for: {e['audience']}" if e["audience"] else ""
            dm = date_mark(e)
            when = f" · {dm}" if dm else ""
            lines.append(f"- {link(e)} — {disc}{addr}{when}{tail_of(e)}")
        if more:
            lines += ["", f"## Filed here from other areas ({len(more)})", "",
                      "Entries that name this area in `topics`. They live in their home "
                      "folder; nothing is copied.", ""]
            for e in sorted(more, key=lambda x: (x["topic"], x["name"])):
                disc = first_sentence(e["desc"], DISCRIMINATOR_CHARS)
                dm = date_mark(e)
                when = f" · {dm}" if dm else ""
                lines.append(f"- {link(e)} — {disc}{when}{tail_of(e)} · filed from {e['topic']}")
        topic_files[topic] = "\n".join(lines) + "\n"
        # ── OPEN.md: the area's open entries, generated, so the list cannot drift ──
        opens = sorted((x for x in es + more if x["status"] == OPEN_STATUS
                        and Path(x["path"]).stem not in settled),
                       key=lambda x: (x["date"] or "9999", x["name"]))
        open_count[topic] = len(opens)
        if opens or (repo / topic / OPEN_NAME).is_file():
            page = [f"# {topic} — open", "",
                    f"{len(opens)} open entr{'y' if len(opens) == 1 else 'ies'}: every file "
                    f"with `status: open` that lives here or is filed here via `topics`, and that "
                    f"no `answers:`/`closes:` (file or LOG) has settled. "
                    f"GENERATED (scripts/shared-memory-index.py), do not hand-edit — change "
                    f"the entry's `status`/`next` instead.", ""]
            for e in opens:
                who = ", ".join(e["next"]) or "nobody named"
                age = age_days(e, today)
                home = f" · filed from {e['topic']}" if e["topic"] != topic else ""
                page.append(f"- next: {who}{' · ' + age if age else ''} — {link(e)}{home}")
            if not opens:
                page.append("nothing open.")
            open_files[topic] = "\n".join(page) + "\n"

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
    # it; reported by sam-main, who had removed the newest set by hand). Matched by
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
            "What is still OPEN is listed per area in `<area>/OPEN.md`, generated from "
            "the entries' `status: open`; this page carries only the count.",
            "", "## Topics", ""]
    for topic in areas:
        es = by_topic.get(topic, [])
        newest = max((e["date"] for e in es if e.get("date")), default="")
        tail = f" · newest {newest}" if newest else ""
        n_open = open_count.get(topic, 0)
        tail += f" · {n_open} open" if n_open else ""
        root.append(f"- [{topic}]({topic}/INDEX.md) — {len(es)} entries{tail}")
    if carried:
        root += ["", "## Not one-fact entries", "",
                 "Linked from the old index, outside the `<topic>/<slug>.md` shape this "
                 "generator manages (attachments, delivery copies). Carried through "
                 "unchanged — edit these lines by hand, they survive regeneration.", ""]
        root += carried
    return "\n".join(root) + "\n", topic_files, entries, open_files


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
    ap.add_argument("--ref", help="with --since: read the entries at this git ref (e.g. a "
                                  "fetched origin/main) instead of the working tree")
    a = ap.parse_args()
    if a.ref and a.write:
        print("ERROR: --ref is read-only; it does not combine with --write", file=sys.stderr)
        return 2
    if not a.repo.is_dir():
        print(f"ERROR: repo not found: {a.repo}", file=sys.stderr)
        return 2

    root, topics, entries, opens = build(a.repo, a.ref)
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
    for t, v in sorted(opens.items()):
        print(f"  {t + '/' + OPEN_NAME:<24} {v.count(chr(10) + '- ')} open")
    print()
    print(f"one lookup TODAY:  {old_size:>7} chars  (~{old_size//4} tokens) — the whole index")
    print(f"one lookup AFTER:  {lookup_new:>7} chars  (~{lookup_new//4} tokens) — root + the "
          f"largest topic")
    # A repo without INDEX.md (a new channel's first run) has nothing to compare: old_size 0
    # made the ratio 0 and `1 / ratio` raised before --write, so the first index was never
    # written (measured on the Windows instance 2026-10-24, a new private shared-memory repo).
    if not old_size:
        print("factor:            no INDEX.md yet, nothing to compare (first run)")
    elif lookup_new:
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
    with open(a.repo / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(root)
    for t, v in topics.items():
        (a.repo / t).mkdir(exist_ok=True)
        with open(a.repo / t / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(v)
    for t, v in opens.items():
        with open(a.repo / t / OPEN_NAME, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(v)
    print(f"\nwritten: INDEX.md + {len(topics)} topic index files + {len(opens)} {OPEN_NAME}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
