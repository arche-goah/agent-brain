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
A fact file whose path the new LOG text already names is not printed twice. Upkeep is not
an arrival: a moved entry (rename), a frontmatter-only edit and a pointer rewrite to a file
the same range moved are skipped (see maintenance_only); a new file or a body edit counts.

WHO "THIS INSTANCE" IS comes from SHARED_MEMORY_SELF (instance data, e.g. the `env` block
of the instance's settings.json): comma-separated tokens such as `alex-macos,alex`. An
entry is dropped when its sender is one of them; it is kept when its addressees name one
of them or everyone (`alle`, `all`, `everyone`, …), or when it names no addressee at all.
Unset: nothing is filtered and the header says so — a filter that silently guesses
"who am I" would drop exactly the entry it guessed wrong about.
A device id in SELF that the repo's `parties.json` knows also answers to `person:<p>` and
`os:<o>` — the audience categories (scripts/shared-memory-parties.py, operator order
2026-10-11): a request to `os:windows` reaches every Windows device, `person:<p>` every
device of that person.

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
# Audience categories (`os:<os>`, `person:<p>`) and the tokenizer that keeps them whole.
_parties = import_module("shared-memory-parties")

# Spellings of "everyone" measured in the repo's headings and `audience` fields.
EVERYONE = _parties.EVERYONE
# OPEN.md is a GENERATED view (shared-memory-index.py), like INDEX.md: it carries no `von:` and is
# not a message. Measured 2026-10-14: eight "[topic] ?: OPEN" lines in one inbox after an index run.
SKIP_FILES = {"INDEX.md", "OPEN.md", "LOG.md", "README.md", "PEOPLE.md"}
# The four live heading shapes — see the note at shared-memory-parties.HEADING.
HEADING = _parties.HEADING
TEXT_CAP = 200


def git(repo: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(repo), "-c", "core.quotepath=off", *args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout if r.returncode == 0 else ""


def snapshot(repo: Path, ref: str) -> dict[str, str]:
    """Every .md file at `ref` as {path: text}, read with TWO git processes in total.

    WHY: the open-request scan read each candidate, each file naming a request and each LOG
    with its own `git show` — one process per file, so the session start grew with the
    repo (measured on a shared-memory repo with several parties: 264 processes, ~5 s of a
    30 s hook budget, and the budget ran out). `ls-tree` lists the blobs once, one
    `cat-file --batch` streams them all. The text is decoded as the per-file reads did:
    UTF-8 with replacement, universal newlines (what `text=True` did to `git show`)."""
    ls = subprocess.run(["git", "-C", str(repo), "ls-tree", "-r", "-z", ref], capture_output=True)
    if ls.returncode != 0:
        return {}
    blobs = []
    for entry in ls.stdout.split(b"\0"):
        meta, _, path = entry.partition(b"\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == b"blob" and path.endswith(b".md"):
            blobs.append((parts[2], path.decode("utf-8", "replace")))
    if not blobs:
        return {}
    cat = subprocess.run(["git", "-C", str(repo), "cat-file", "--batch"],
                         input=b"".join(sha + b"\n" for sha, _ in blobs), capture_output=True)
    if cat.returncode != 0:
        return {}
    out, data, pos = {}, cat.stdout, 0
    for _, path in blobs:
        nl = data.index(b"\n", pos)
        header = data[pos:nl].split()
        if len(header) != 3:            # "<sha> missing" — never for a blob ls-tree just listed
            pos = nl + 1
            continue
        size = int(header[2])
        raw = data[nl + 1:nl + 1 + size]
        pos = nl + 1 + size + 1         # content plus the trailing newline of the batch format
        out[path] = raw.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "\n")
    return out


def tokens(s: str) -> set[str]:
    return _parties.tokens(s)


def party(sender_id: str) -> set[str]:
    """The words a reply may use for the sender of a request. Machine ids are `<person>-<machine>`,
    but replies name the person in prose ("AN Sams KI") — the wording rule wants names, not ids.
    Measured 2026-10-10: five answered requests stayed open because `sams` never matched
    `sam-laptop`. So the person part and its possessive count too."""
    out = set()
    for t in tokens(sender_id):
        out |= {t, t.split("-")[0], t.split("-")[0] + "s"}
    return out


addressees = _parties.addressees


def for_us(sender: str, to: str | None, me: set[str]) -> bool:
    if not me:
        return True
    if tokens(sender) & me:
        return False
    if to is None:
        return True
    words = tokens(to)
    return bool(words & (me | EVERYONE))


def whole(text: str) -> str:
    """The text as written, whitespace normalised — NEVER cut.

    WHY (operator decision 2026-10-18, translated: "that must not count as read"): this reader used
    to cut every heading at a sentence boundary under 200 characters. A heading "… lock not set
    here — old branches deleted (operator's word), the lock would block the PR path" arrived as
    "… lock not set here"; the reading AI took the stump for the message and handed the operator
    a needless command. What a reader shows of another party's message is what the receiver
    acts on, so it shows all of it: the whole heading and the whole LOG entry below it, and for a
    fact file the whole description plus the path to read before acting."""
    return " ".join(text.split())


def log_items(repo: Path, a: str, b: str, me: set[str]) -> tuple[list[tuple], str]:
    diff = git(repo, "diff", "-U0", a, b, "--", "LOG.md", "*/LOG.md")
    items, added, topic = [], [], ""
    cur = None  # index of the item whose LOG body the following added lines belong to
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            topic = path.split("/")[0] if "/" in path else "root"
            cur = None
            continue
        if not line.startswith("+") or line.startswith("+++"):
            if line.startswith("@@"):
                cur = None
            continue
        text = line[1:]
        added.append(text)
        m = HEADING.match(text)
        if not m:
            # A dated heading that matches no known shape is NEVER dropped: it is printed as
            # unparsed, whoever it is for (we cannot know). Dropping it was the silent failure
            # behind every new heading shape (2026-09-25 two shapes, 2026-10-11 a third): the
            # watcher said "nothing arrived" while the answer sat in the log.
            um = re.match(r"^##\s+(\d{4}-\d{2}-\d{2})\b", text)
            if um:
                items.append((um.group(1), topic, "?", "UNPARSED LOG HEADING — " + whole(text)))
                cur = len(items) - 1
            elif re.match(r"^#{1,2}\s", text):
                cur = None
            elif cur is not None and text.strip():
                d, t, s, msg = items[cur]
                items[cur] = (d, t, s, msg + " ¶ " + whole(text))
            continue
        date, sender, title = m.groups()
        title = title or ""
        if for_us(sender, addressees(title), me):
            items.append((date, topic, sender, whole(title or "(no title)")))
            cur = len(items) - 1
        else:
            cur = None
    return items, "\n".join(added)


def body(text: str) -> str:
    """The entry below its frontmatter, line endings and outer whitespace normalised."""
    t = text.replace("\r\n", "\n")
    if t.startswith("---"):
        end = t.find("\n---", 3)
        if end != -1:
            t = t[end + 4:]
    return t.strip()


def description(text: str) -> str:
    """The frontmatter `description`, or "" when there is none."""
    head = text.split("\n---", 1)[0] if text.startswith("---") else ""
    m = _idx.FM_DESC.search(head)
    return m.group(1) if m else ""


def maintenance_only(old: str, new: str, moves: dict[str, str]) -> bool:
    """True when a MODIFIED entry changed only in ways that are upkeep, not a post.

    Measured 2026-10-10 on a shared-memory repo with several parties: a tidy-up commit moved
    23 entries into topic areas, and lint commits added frontmatter fields to old entries.
    The watcher then reported the touched OLD entries (dated September) as new arrivals from
    other parties, four times in one day. Two kinds of upkeep produce that, and both are
    decided here mechanically:
      - a frontmatter-only edit (a field added, a status corrected, frontmatter given to a
        file that had none): the body is unchanged. The `description` is the exception —
        it is the entry's main information and what this reader prints, so a CHANGED one
        counts as content (a first one, given to a file that had none, is upkeep);
      - a pointer rewrite: the body differs only where it names a file that the same range
        MOVED, old path replaced by new path.
    Anything else in the body is content and still counts — a reply appended to an existing
    request is exactly what the inbox exists to show."""
    was = description(old)
    if was and was != description(new):
        return False
    a, b = body(old), body(new)
    for src, dst in moves.items():
        a = a.replace(src, dst)
    return a == b


def file_items(repo: Path, a: str, b: str, me: set[str], log_text: str) -> list[tuple]:
    items = []
    # `-M` explicitly: a moved entry is a RENAME (R), which `--diff-filter=AM` leaves out.
    # git's default would detect it too, but only while `diff.renames` is not switched off in
    # someone's config — the reader must not depend on that.
    status = git(repo, "diff", "--name-status", "-M", a, b).splitlines()
    moves = {}
    for line in status:
        parts = line.split("\t")
        if len(parts) == 3 and parts[0].startswith("R"):
            moves[parts[1]] = parts[2]
    for line in status:
        parts = line.split("\t")
        if len(parts) < 2 or parts[0][:1] not in ("A", "M"):
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
        if parts[0].startswith("M") and maintenance_only(git(repo, "show", f"{a}:{rel}"),
                                                         blob, moves):
            continue
        e = read_entry(p, repo, text=blob)
        if not for_us(e["von"], e["audience"] or None, me):
            continue
        text = whole(e["desc"] or e["name"])
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
        elif re.match(r"^##\s+\d{4}-\d{2}-\d{2}\b", line):
            # A dated heading no shape recognises still ENDS the previous section. Glued on, its
            # text read as the previous sender's — a reply under an unknown heading looked like
            # a second message of whoever wrote the entry above it (same class as the dropped
            # heading: unknown input must stay visible, never be absorbed).
            if buf:
                out.append((sender, "\n".join(buf)))
            sender, buf = "?", [line]
        else:
            buf.append(line)
    if buf:
        out.append((sender, "\n".join(buf)))
    return out


# Which files are REQUESTS (as opposed to reports addressed to us): a file name that starts
# with one of these words, or frontmatter `status: open` that puts us on the move. Words are
# data — the instance adds its own languages via SHARED_MEMORY_REQUEST_PREFIXES
# (comma-separated), same convention as SHARED_MEMORY_SELF. `status:` answered/done/decided/
# info always wins over the name.
# The German words are defaults because the shared repo is written in German by every party
# (measured 2026-10-18 on a shared-memory repo: anfrage- 26, pruefbitte- 20, frage- 7,
# abstimmung- 7 files against request- 8). Before, only an instance that had set the variable
# saw them — two questions to another party's AI were never shown there.
REQUEST_PREFIXES = ("request", "question", "anfrage", "rueckfrage", "frage", "pruefbitte",
                    "bitte", "abstimmung")
CLOSED_STATUS = {"answered", "done", "decided", "info", "closed"}
FM_STATUS = re.compile(r"^\s+status:\s*([\w-]+)", re.M)


def open_items(repo: Path, ref: str, me: set[str], days: int,
               prefixes: tuple[str, ...] = REQUEST_PREFIXES, parties: dict | None = None) -> list[tuple]:
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
    # All .md texts in two git processes (see snapshot); every search below runs on them in
    # memory. Prefilter: only files with an `audience` line that names us at all.
    texts = snapshot(repo, ref)
    # A request to everyone reaches us too (as optional, see below) — 2026-10-13.
    reach = me | EVERYONE
    rx = re.compile(r"^[^\S\n]+audience:.*(" + "|".join(re.escape(t) for t in sorted(reach)) + r")",
                    re.I | re.M)
    cand = {rel for rel, t in texts.items() if rx.search(t)}
    items = []
    for rel in sorted(cand):
        p = repo / rel
        if "/" not in rel or p.name in SKIP_FILES:
            continue
        blob = texts[rel]
        e = read_entry(p, repo, text=blob)
        if not e["audience"] or not (tokens(e["audience"]) & reach) or tokens(e["von"]) & me:
            continue
        head = blob.split("\n---", 1)[0] if blob.startswith("---") else ""
        st = FM_STATUS.search(head)
        status = st.group(1).lower() if st else ""
        if status in CLOSED_STATUS:
            continue
        # `status: open` marks a request only when it is addressed to us ALONE — a status
        # broadcast to three parties carries the same field (Windows check on #193, finding 2).
        # A category (`os:…`, `person:…`) reaches several devices, so it is never "us alone".
        aud = tokens(e["audience"])
        only_us = not (aud - me) and not any(_parties.is_category(t) for t in aud)
        # `next:` (lint-required next to `status: open`) says who is on the move. Naming us there
        # makes it our request however many parties read along — the field, not the file name's
        # language, decides (measured 2026-10-18: `next: <two devices>` on a question that no
        # inbox showed, because it went to more than one party).
        next_us = any(tokens(n) & me for n in e["next"])
        if not p.stem.lower().startswith(prefixes) and not (status == "open" and (only_us or next_us)):
            continue
        when = e["date"] or git(repo, "log", "-1", "--format=%as", ref, "--", rel).strip()
        if floor and when and when < floor:
            continue
        stem = p.stem
        answered = False
        for hrel, htext in texts.items():
            if stem not in htext or hrel == rel or hrel.endswith("INDEX.md"):
                continue
            if hrel.endswith("LOG.md"):
                answered = any(tokens(s) & me and stem in body
                               for s, body in log_section_senders(htext))
            else:
                # Ours, or anyone's file that declares itself the answer (`answers: <stem>`) —
                # a request to "either of two machines" is closed by the one that answered
                # (Windows check on #193, finding 1).
                hhead = htext.split("\n---", 1)[0] if htext.startswith("---") else ""
                # `claims:` = someone took it; `closes:` = either side says it is settled — the
                # asker ("answer received, enough") or the answerer ("answered, done"). 2026-10-13.
                answered = (bool(tokens(read_entry(repo / hrel, repo, text=htext)["von"]) & me)
                            or bool(re.search(r"^\s+(?:answers|claims|closes):.*" + re.escape(stem),
                                              hhead, re.M)))
            if answered:
                break
        if not answered:
            text = whole(e["desc"] or e["name"])
            # Priority is information, never a sequence (operator 2026-10-13): whoever is not
            # asked first sees the task as optional — anyone may claim it at any time.
            prio = _parties.priority(head, e["audience"], parties or {})
            r = _parties.rank(prio, me | EVERYONE) if prio else 0
            if r:
                text = (f"optional: priority {r + 1}, asked first {', '.join(prio[:r])}; unclaimed"
                        f" - take it if you can and want — {text}")
            elif not prio and not (aud & me):
                text = f"optional: to everyone; unclaimed - take it if you can and want — {text}"
            items.append((when or "?", e["topic"], e["von"] or "?", f"{text} ({rel})"))
    return items + log_only_items(texts, me, floor)


LOG_INFO = re.compile(r"\bstatus:\s*info\b", re.I)
# The close word opens the title proper: "AN <who>: ERLEDIGT — …" (or a title without AN).
LOG_CLOSE = re.compile(r"(?:^|:)\s*(?:ERLEDIGT|GESCHLOSSEN|DONE|CLOSED)\b", re.I)
# "re <what>" — a reply that opens with the request's title, or the start of it.
LOG_RE_REF = re.compile(r"\bre\s+([^\n:—]+)", re.I)
# A numbered reference ("#290"), the way PRs and issues are named in titles and answers.
PR_NUM = re.compile(r"#(\d+)\b")


def names_request(core_title: str, title: str, body: str) -> bool:
    """Does a later heading refer to THIS request? By its title text anywhere in title or body,
    or by `re <x>` where x opens the request's title (at least four characters, so a bare
    `re` or an unrelated short word cannot match by accident)."""
    if not core_title:
        return False
    text = f"{title}\n{body}".lower()
    wants = [core_title.lower()]
    # A request that is itself a reply ("re <earlier> — <what>") is answered as "re <what>":
    # the answer names the request's own matter, not the thread it hangs in (measured
    # 2026-10-15: such an answer of 2026-10-14 matched nothing and sat open into the next start).
    m = re.match(r"re\s+[^\n:—]+[—:]\s*(.+)", wants[0])
    if m and len(m.group(1).strip()) >= 12:
        wants.append(m.group(1).strip())
    if any(w in text for w in wants):
        return True
    # A request about numbered things ("Windows-Pruefung Kern #290 …") is answered by naming those
    # numbers ("Windows #290 OK"), not by repeating its title (measured 2026-10-15 on a Windows
    # instance: answered requests of this shape came back open after the naming rule). ALL of the
    # request's numbers must be named: one answer about #290 does not close a request for #290 + #292.
    nums = set(PR_NUM.findall(core_title))
    if nums and nums <= set(PR_NUM.findall(text)):
        return True
    return any(len(x) >= 4 and w.startswith(x)
               for m in LOG_RE_REF.finditer(text) for x in [m.group(1).strip()] for w in wants)


def log_only_items(texts: dict[str, str], me: set[str], floor: str) -> list[tuple]:
    """Messages to us BY NAME that live only as a LOG heading (no fact file named in the body).

    The shape of the 2026-10-04 incident and of finding 3 of the Windows check on #193: once
    the cursor passes such a heading, nothing else carries it. Open until one of OUR later
    headings (any topic, same day or later) to the sender NAMES it — a reply in the
    conversation stream to THIS request, never to the sender as a whole (measured 2026-10-14
    by a collaborator's instance: our one answer about X silently closed the same sender's
    unanswered Y). Wrong only in the safe direction: an answer given elsewhere, or one that
    does not name what it answers, keeps the request listed.
    """
    heads: list[tuple] = []  # (date, topic, sender, to_tokens, title, body)
    for rel, text in texts.items():
        if not (rel.endswith("/LOG.md") or rel == "LOG.md"):
            continue
        topic = rel.split("/")[0] if "/" in rel else "root"
        for i, (sender, body) in enumerate(log_section_senders(text)):
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
        if LOG_INFO.search(title) or LOG_CLOSE.search(title):
            continue  # a report or a close, not a request (measured 2026-10-13: info headings sat open)
        # The asker may settle it: a later heading of the same party to the same addressee whose
        # title starts with a close word ("AN x: ERLEDIGT — …") and whose text NAMES this
        # request's title. Naming, not "everything before": one close must not sweep away the
        # requests that are still open.
        to_str = addressees(title or "")
        core_full = (title.split(to_str, 1)[1].lstrip(": ") if to_str else title or "").strip()
        core_title = core_full[:60]
        if core_title and any(party(sender) & tokens(s) and t & to and LOG_CLOSE.search(ti or "")
                              and core_title in b and (d > date or (tp == topic and j > idx))
                              for d, tp, j, s, t, ti, b in heads):
            continue
        # A reply comes AFTER the request: a later day, or later in the same LOG. Same day in
        # another LOG cannot be ordered, so it does not count (safe direction). And it NAMES
        # the request, the same way the asker's close above has to — one reply closes one
        # request, not every open one of that sender.
        replied = any(tokens(s) & me and party(sender) & t
                      and (d > date or (tp == topic and j > idx))
                      and (names_request(core_title, ti, b) or names_request(core_full, ti, b))
                      for d, tp, j, s, t, ti, b in heads)
        if not replied:
            items.append((date, topic, sender, whole(title) + " (LOG)"))
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
    # A known device in SELF also answers to its person and OS (`person:<p>`, `os:<o>`),
    # read from the repo's parties.json at the ref this run reads. No file: SELF as given.
    parties = _parties.load(args.repo, args.b)
    if me:
        me = _parties.expand_self(me, parties)

    if args.open:
        if not me:
            print("shared-memory open requests: not checked - SHARED_MEMORY_SELF unset")
            return 0
        extra = os.environ.get("SHARED_MEMORY_REQUEST_PREFIXES", "")
        prefixes = REQUEST_PREFIXES + tuple(w.strip().lower() for w in extra.split(",") if w.strip())
        found = sorted(open_items(args.repo, args.b, me, args.days, prefixes, parties),
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
    # Said once, in the output itself: a LOG line here is the whole entry (heading ¶ body); a
    # fact file shows its description, and the file is what the sender wrote — read it first.
    if any(t.endswith(".md)") for _, _, _, t in items[:args.max]):
        print("  (a path in parentheses is a fact file: the line is its description, read the file before acting on it)")
    for date, topic, sender, text in items[:args.max]:
        print(f"  - {date} [{topic}] {sender}: {text}")
    rest = len(items) - args.max
    if rest > 0:
        print(f"  + {rest} more: core/scripts/shared-memory-inbox.py --from {args.a[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
