#!/usr/bin/env python3
"""Commit shas this instance named in its OWN shared-memory texts.

WHY (measured 2026-10-11, Windows instance): a check requested through the shared memory is
answered there ("Antwort: core/antwort-...md"), naming the head it measured — and the PR
thread stays silent. The two scripts that decide whose move a PR is (open-items.py,
pr-ball.py) read only PR comments and reviews, so two sibling PRs the Windows side had
checked at their heads were printed as our move in every session ("review - asked, not
looked at yet"), and a session papered over it with hand-dated waits. Our answer naming the
CURRENT head counts like a comment after the last commit; a sha of an older head does not,
because a new commit is new work. Only OWN texts count: the request that asks for the check
names the same head.

Own = fact files whose front matter says `von: <self>`, and LOG sections headed
`## <date> · <self>`; self = SHARED_MEMORY_SELF. Unset self or no clone = empty set (the old
reading holds). Stdlib only.
"""
import json
import os
import re
from pathlib import Path

SHA = re.compile(r"\b[0-9a-f]{7,40}\b")


def default_repo():
    return os.environ.get("SHARED_MEMORY_REPO", str(Path.home() / "Projects" / "brain-shared-memory"))


def own_shared_shas(repo=None):
    # The setting is a comma list, "<device>,<alias>,…": the device is the first token (the one
    # `von:` and LOG headings carry; device-status.py and the inbox read it the same way).
    # Measured on the macOS instance 2026-10-11: the whole string matched 0 shas, the first token 125.
    me = os.environ.get("SHARED_MEMORY_SELF", "").split(",")[0].strip()
    root = Path(repo or default_repo())
    if not me or not (root / ".git").is_dir():
        return set()
    von = re.compile(r"^\s*von:\s*" + re.escape(me) + r"\s*$", re.M)
    head = re.compile(r"^## \S+ · " + re.escape(me) + r"\b")
    found = set()
    for f in list(root.glob("*/*.md")) + list(root.glob("*/archive/*/*.md")):  # moved messages included
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if f.name == "LOG.md":
            mine = False
            for line in text.splitlines():
                if line.startswith("## "):
                    mine = bool(head.match(line))
                if mine:
                    found.update(SHA.findall(line))
        elif text.startswith("---") and von.search(text.split("\n---", 2)[0]):
            found.update(SHA.findall(text))
    return found


def answers(stem, path, text, me):
    """True when another party's text names the request: a LOG section under a heading that is
    not ours, or a fact file whose `von:` is not us. Our own mentions (a LOG line "asked X")
    answer nothing."""
    if stem not in text:
        return False
    if path.name == "LOG.md":
        for sec in re.split(r"(?m)^(?=## )", text):
            m = re.match(r"## \S+ · (\S+)", sec)
            if m and m.group(1) != me and stem in sec:
                return True
        return False
    von = re.search(r"^\s*von:\s*(\S+)", text.split("\n---", 2)[0] if text.startswith("---") else "", re.M)
    return bool(von) and von.group(1) != me


REQ_PR = re.compile(r"([A-Za-z][\w.-]*)\s?#(\d+)((?:,?\s#\d+)*)")


def own_open_requests(repo=None):
    """{"<repo>#N": (next, date)} for our own open requests (frontmatter `von:` = this device,
    `status: open`) whose description names PRs as `<repo>#N` (more numbers may follow: `#N #M`).
    Measured on the macOS instance 2026-11-03: own PRs waiting on a Windows check we had asked
    for printed as our move; the request said who moves, the PR list never read it."""
    me = os.environ.get("SHARED_MEMORY_SELF", "").split(",")[0].strip()
    root = Path(repo or default_repo())
    if not me or not (root / ".git").is_dir():
        return {}
    texts = {}
    for f in list(root.glob("*/*.md")) + list(root.glob("*/archive/*/*.md")):  # moved messages included
        try:
            texts[f] = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
    out = {}
    for f, text in texts.items():
        if not text.startswith("---"):
            continue
        front = text.split("\n---", 2)[0]
        field = lambda k: (re.search(rf"^\s*{k}:\s*(.*?)\s*$", front, re.M) or [None, ""])[1].strip("\"'")
        if field("von") != me or field("status") != "open":
            continue
        # Answered the way the addressee's inbox reads it (shared-memory-inbox.py open_items): any
        # other file naming the request. A status left on `open` after the answer is common
        # (measured 2026-11-03: ~180 own requests on `open`, most answered or merged long ago).
        # Wrong only in the safe direction: a mention that is no answer hands the PR back to us.
        if any(answers(f.stem, g, t, me) for g, t in texts.items() if g != f and g.name != "INDEX.md"):
            continue
        for name, first, more in REQ_PR.findall(field("description")):
            for n in [first] + re.findall(r"\d+", more):
                out[f"{name.rsplit('/', 1)[-1]}#{n}"] = (field("next") or "?", field("date"))
    return out


def checked_head(oid, shas):
    """True when one of our shas is a prefix of this head's full oid."""
    oid = (oid or "").lower()
    return bool(oid) and any(oid.startswith(s) for s in shas)


def sibling_keys_same_os(me_id="", repo=None):
    """Instance keys of the OTHER devices of our person that run our OS (parties.json in the
    shared memory). A look by one of them at a PR's head is a look for all of that OS: the
    check a PR asks for is per OS, not per machine — measured 2026-10-22 on the operator's
    second macOS instance, which listed every PR of the first one as "asked, not looked at
    yet" (13 at once) although that machine had reviewed them at the head. Empty set without
    SHARED_MEMORY_SELF, without parties.json, or when our device is not listed. Shared by
    pr-ball.py and open-items.py, which must agree on whose move a PR is."""
    from instance_key import key_for
    me_id = (me_id or os.environ.get("SHARED_MEMORY_SELF", "")).split(",")[0].strip()
    if not me_id:
        return set()
    try:
        parties = json.loads((Path(repo or default_repo()) / "parties.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    for person in (parties.get("people") or {}).values():
        devices = (person or {}).get("devices") or {}
        if me_id in devices:
            my_os = (devices.get(me_id) or {}).get("os")
            return {key_for(d) for d, v in devices.items()
                    if d != me_id and my_os and (v or {}).get("os") == my_os}
    return set()
