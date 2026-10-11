#!/usr/bin/env python3
"""instance_key.py — which INSTANCE wrote a GitHub text, when several share one account.

WHY (measured 2026-10-11, and before that 2026-09-24): an operator's two machines — and a
collaborator's three — post under ONE GitHub login with one noreply address. Every check that
asks "is this mine?" by login (whose move a PR is, which reply is new) took a PR or an OK
from the operator's other machine for its own, and stayed silent: a test fix waited for a
second OK that nobody was shown, until the operator asked on every side. The git author name
differs per machine but is configuration, not proof; only the shared-memory `von:` field ever
told the machines apart.

THE KEY: every text an AI posts to GitHub (PR body, comment, review) carries one line
    <!-- instance-key: <key> -->
— an HTML comment, invisible when rendered. `<key>` is the first 10 hex digits of
sha256("instance-key:" + <this instance's id>), the id being the first token of
SHARED_MEMORY_SELF. Opaque on purpose: public repos must not carry machine ids, and a hash
names nobody. helpers/instance-key-gate.cjs computes the same value and refuses a post without
it; this module is the reading side.

DECISION RULE (`is_self`): a node is this instance's only if the login is the viewer's AND its
key is absent or equal to this instance's key. A different key under the same login is
ANOTHER instance — a move for us, not our own. No key under our login stays ours: older posts
and the operator's own hand-written comments carry none (named limitation, not a guess). No
SHARED_MEMORY_SELF = no own key = the old login-only rule, unchanged.
"""
import hashlib
import os
import re

MARK = re.compile(r"<!--\s*instance-key:\s*([0-9a-f]{6,40})\s*-->", re.I)


def self_id(env=None):
    raw = (env if env is not None else os.environ).get("SHARED_MEMORY_SELF", "")
    tokens = [t for t in re.split(r"[,\s]+", raw.strip().lower()) if t]
    return tokens[0] if tokens else ""


def key_for(instance_id):
    return hashlib.sha256(("instance-key:" + instance_id).encode("utf-8")).hexdigest()[:10] if instance_id else ""


def self_key(env=None):
    return key_for(self_id(env))


def key_in(text):
    m = MARK.search(text or "")
    return m.group(1).lower() if m else None


def is_self(login, me, text, my_key):
    if not me or (login or "").lower() != me.lower():
        return False
    if not my_key:
        return True
    k = key_in(text)
    return k is None or k == my_key


if __name__ == "__main__":
    # `python3 instance_key.py` prints the marker line this instance must post.
    k = self_key()
    print(f"<!-- instance-key: {k} -->" if k else "instance-key: SHARED_MEMORY_SELF unset - no key")
