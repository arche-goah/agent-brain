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
    for f in root.glob("*/*.md"):
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


def checked_head(oid, shas):
    """True when one of our shas is a prefix of this head's full oid."""
    oid = (oid or "").lower()
    return bool(oid) and any(oid.startswith(s) for s in shas)
