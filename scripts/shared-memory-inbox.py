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
of the instance's settings.json): comma-separated tokens such as `alex-macos,alex`. An
entry is dropped when its sender is one of them; it is kept when its addressees name one
of them or everyone (`alle`, `all`, `everyone`, …), or when it names no addressee at all.
Unset: nothing is filtered and the header says so — a filter that silently guesses
"who am I" would drop exactly the entry it guessed wrong about.

Never summarises: every printed text is the author's own heading or description, cut at a
sentence boundary. Read-only. Exit 0 always (an advisory reader, not a gate).

Usage: shared-memory-inbox.py --from SHA [--to SHA] [--repo DIR] [--self a,b] [--max N]
       shared-memory-inbox.py --from SHA [--to SHA] [--repo DIR] --senders
--senders prints every sender in the range, one per line, UNFILTERED — the live watcher
names the party of a find with it, including LOG entries addressed to someone else.
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
# Measured 2026-09-25 across all LOGs: `## <date> · <von> — <title>` is one of FOUR live
# shapes. Half of the September headings use an ASCII hyphen (`## <date> <von> - <title>`),
# older ones carry a time note and no title (`## <date> (Abend) — <von>`). A pattern for
# the first shape alone dropped every message of the second — silently.
HEADING = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})(?:\s*\([^)]*\))?\s*(?:[·—-]\s*)?"
                     r"([\w-]+)(?:\s+[—-]\s+(.*?))?\s*$")
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
        title = title or ""
        if for_us(sender, addressees(title), me):
            items.append((date, topic, sender, first_sentence(title or "(no title)", TEXT_CAP)))
    return items, "\n".join(added)


def file_items(repo: Path, a: str, b: str, me: set[str], log_text: str) -> list[tuple]:
    items = []
    for line in git(repo, "diff", "--name-status", "--diff-filter=AM", a, b).splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        rel = parts[-1]
        p = repo / rel
        if not rel.endswith(".md") or "/" not in rel or p.name in SKIP_FILES:
            continue
        if rel in log_text or p.name in log_text:
            continue
        # The blob at `b`, not the file on disk: the caller only FETCHES, so a new file is
        # not in the working tree yet and a changed one is still the old version there
        # (measured on the workstation 2026-09-30: 9 lines instead of 10).
        blob = git(repo, "show", f"{b}:{rel}")
        if not blob:
            continue
        e = read_entry(p, repo, text=blob)
        if not for_us(e["von"], e["audience"] or None, me):
            continue
        text = first_sentence(e["desc"] or e["name"], TEXT_CAP)
        # Older files carry no frontmatter date; the commit that brought them is the date.
        date = e["date"] or git(repo, "log", "-1", "--format=%as", b, "--", rel).strip() or "?"
        items.append((date, e["topic"], e["von"] or "?", f"{text} ({rel})"))
    return items


def log_section_senders(text: str) -> list[tuple[str, str]]:
    """A LOG.md split into (sender, section text) by its headings."""
    out, sender, buf = [], "", []
    for line in text.splitlines():
        m = HEADING.match(line)
        if m:
            if buf:
                out.append((sender, "\n".join(buf)))
            sender, buf = m.group(2), [line]
        else:
            buf.append(line)
    if buf:
        out.append((sender, "\n".join(buf)))
    return out


# Which files are REQUESTS (as opposed to reports addressed to us): a file name that starts
# with one of these words, or frontmatter `status: open`. Words are data — the instance adds
# its own languages via SHARED_MEMORY_REQUEST_PREFIXES (comma-separated), same convention
# as SHARED_MEMORY_SELF. `status:` answered/done/decided/info always wins over the name.
REQUEST_PREFIXES = ("request", "question")
CLOSED_STATUS = {"answered", "done", "decided", "info", "closed"}
FM_STATUS = re.compile(r"^\s+status:\s*([\w-]+)", re.M)


def open_items(repo: Path, ref: str, me: set[str], days: int,
               prefixes: tuple[str, ...] = REQUEST_PREFIXES) -> list[tuple]:
    """Requests addressed to this instance BY NAME that nothing of ours answers yet.

    WHY (2026-10-05): the range inbox above only shows what arrived since the cursor. A
    session that sees it and does not relay it moves the cursor anyway — measured: three
    requests from a collaborator were shown once at a start, never answered, and the next
    start said nothing at all. Seen is not done. This list does not use the cursor.

    Addressed by name: `audience` names one of SELF (a broadcast to everyone is not a
    request waiting on this side). Answered: any of our own fact files, or a LOG section
    under one of our headings, names the request's file stem. Cheap, explicit, and wrong
    only in the safe direction — an answer that never names the request keeps it listed.
    """
    if not me:
        return []
    today = git(repo, "log", "-1", "--format=%as", ref).strip()
    try:
        from datetime import date, timedelta
        floor = (date.fromisoformat(today) - timedelta(days=days)).isoformat()
    except ValueError:
        floor = ""
    # Prefilter in ONE git call: only files whose frontmatter names us at all. Reading every
    # blob of the repo one `git show` at a time took ~10 s (measured 2026-10-05, ~600 files).
    rx = r"^[[:space:]]+audience:.*(" + "|".join(re.escape(t) for t in sorted(me)) + r")"
    cand = {h.split(":", 1)[1] for h in
            git(repo, "grep", "-l", "-i", "-E", rx, ref, "--", "*.md").splitlines() if ":" in h}
    items = []
    for rel in sorted(cand):
        p = repo / rel
        if "/" not in rel or p.name in SKIP_FILES:
            continue
        blob = git(repo, "show", f"{ref}:{rel}")
        e = read_entry(p, repo, text=blob)
        if not e["audience"] or not (tokens(e["audience"]) & me) or tokens(e["von"]) & me:
            continue
        head = blob.split("\n---", 1)[0] if blob.startswith("---") else ""
        st = FM_STATUS.search(head)
        status = st.group(1).lower() if st else ""
        if status in CLOSED_STATUS:
            continue
        # `status: open` marks a request only when it is addressed to us ALONE — a status
        # broadcast to three parties carries the same field (Windows check on #193, finding 2).
        only_us = not (tokens(e["audience"]) - me)
        if not p.stem.lower().startswith(prefixes) and not (status == "open" and only_us):
            continue
        when = e["date"] or git(repo, "log", "-1", "--format=%as", ref, "--", rel).strip()
        if floor and when and when < floor:
            continue
        stem = p.stem
        answered = False
        for hit in git(repo, "grep", "-l", "-F", stem, ref, "--", "*.md").splitlines():
            hrel = hit.split(":", 1)[1] if ":" in hit else hit
            if hrel == rel or hrel.endswith("INDEX.md"):
                continue
            htext = git(repo, "show", f"{ref}:{hrel}")
            if hrel.endswith("LOG.md"):
                answered = any(tokens(s) & me and stem in body
                               for s, body in log_section_senders(htext))
            else:
                # Ours, or anyone's file that declares itself the answer (`answers: <stem>`) —
                # a request to "either of two machines" is closed by the one that answered
                # (Windows check on #193, finding 1).
                hhead = htext.split("\n---", 1)[0] if htext.startswith("---") else ""
                answered = (bool(tokens(read_entry(repo / hrel, repo, text=htext)["von"]) & me)
                            or bool(re.search(r"^\s+answers:.*" + re.escape(stem), hhead, re.M)))
            if answered:
                break
        if not answered:
            text = first_sentence(e["desc"] or e["name"], TEXT_CAP)
            items.append((when or "?", e["topic"], e["von"] or "?", f"{text} ({rel})"))
    return items + log_only_items(repo, ref, me, floor)


def log_only_items(repo: Path, ref: str, me: set[str], floor: str) -> list[tuple]:
    """Messages to us BY NAME that live only as a LOG heading (no fact file named in the body).

    The shape of the 2026-10-04 incident and of finding 3 of the Windows check on #193: once
    the cursor passes such a heading, nothing else carries it. Open until one of OUR later
    headings (any topic, same day or later) is addressed to the sender — a reply in the
    conversation stream. Wrong only in the safe direction: an answer given elsewhere keeps
    it listed until we next write to that party.
    """
    heads: list[tuple] = []  # (date, topic, sender, to_tokens, title, body)
    for rel in git(repo, "ls-tree", "-r", "--name-only", ref).splitlines():
        if not (rel.endswith("/LOG.md") or rel == "LOG.md"):
            continue
        topic = rel.split("/")[0] if "/" in rel else "root"
        for i, (sender, body) in enumerate(log_section_senders(git(repo, "show", f"{ref}:{rel}"))):
            m = HEADING.match(body.splitlines()[0]) if body else None
            if not m:
                continue
            date, _, title = m.groups()
            to = addressees(title or "")
            heads.append((date, topic, i, sender, tokens(to) if to else set(), title or "", body))
    items = []
    for date, topic, idx, sender, to, title, body in heads:
        if not (to & me) or tokens(sender) & me or (floor and date < floor):
            continue
        if re.search(r"[\w./-]+\.md\b", "\n".join(body.splitlines()[1:])):
            continue  # points at a fact file — the file path above judges it
        # A reply comes AFTER the request: a later day, or later in the same LOG. Same day in
        # another LOG cannot be ordered, so it does not count (safe direction).
        replied = any(tokens(s) & me and tokens(sender) & t
                      and (d > date or (tp == topic and j > idx))
                      for d, tp, j, s, t, _, _ in heads)
        if not replied:
            items.append((date, topic, sender, first_sentence(title, TEXT_CAP) + " (LOG)"))
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=REPO_DEFAULT)
    ap.add_argument("--from", dest="a", help="last seen commit (range mode)")
    ap.add_argument("--open", action="store_true",
                    help="list requests addressed to SELF that nothing of ours answers yet")
    ap.add_argument("--days", type=int, default=30, help="--open: look back this many days")
    ap.add_argument("--to", dest="b", default="origin/main")
    ap.add_argument("--self", dest="me", default=os.environ.get("SHARED_MEMORY_SELF", ""))
    ap.add_argument("--max", type=int, default=12)
    ap.add_argument("--senders", action="store_true", help="print the senders only, unfiltered")
    args = ap.parse_args()
    # OS-9: the text is the authors' own (umlauts, dashes) and a hook reads it. Unpinned,
    # Windows writes the ANSI codepage and dies on the first unencodable character.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    me = set() if args.senders else tokens(args.me.replace(",", " "))

    if args.open:
        if not me:
            print("shared-memory open requests: not checked - SHARED_MEMORY_SELF unset")
            return 0
        extra = os.environ.get("SHARED_MEMORY_REQUEST_PREFIXES", "")
        prefixes = REQUEST_PREFIXES + tuple(w.strip().lower() for w in extra.split(",") if w.strip())
        found = sorted(open_items(args.repo, args.b, me, args.days, prefixes),
                       key=lambda i: i[0])
        # Always one line, also for zero: a clean check that prints nothing cannot be told
        # apart from a check that did not run (operator order 2026-10-05).
        print(f"shared-memory open requests to this instance: {len(found)}"
              + ("" if found else f" (last {args.days} days)"))
        for date, topic, sender, text in found[:args.max]:
            print(f"  - {date} [{topic}] {sender}: {text}")
        return 0
    if not args.a:
        ap.error("--from is required unless --open")

    if args.senders:
        logs, log_text = log_items(args.repo, args.a, args.b, me)
        found = logs + file_items(args.repo, args.a, args.b, me, log_text)
        for sender in sorted({i[2] for i in found if i[2] and i[2] != "?"}):
            print(sender)
        return 0

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
