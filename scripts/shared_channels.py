#!/usr/bin/env python3
"""Shared-memory channels: N shared-memory repos instead of exactly one — the one place the
list is parsed.

WHY (operator decision 2026-10-24, agreed by both core parties): the AI sessions on one
operator's own devices need a private place to coordinate, and groups of parties need channels
of their own with their own members. A private repo in the shared-memory format already worked
with every tool through `--repo` / SHARED_MEMORY_REPO (measured on the Windows instance
2026-10-24: post, inbox and the live watcher against a second repo). What every reader lacked
was a LIST: the session-start check and open-items read exactly one repo, and collab-watch kept
one cursor file for every shared-memory line, so a second channel shared it and was refused.

Instance data `.claude/rules/shared-memory-channels.json` (template:
templates/rules-instance/shared-memory-channels.json); SHARED_MEMORY_CHANNELS_CONFIG names
another file (fixtures, unusual layouts):
  {"channels": [{"label": "devices", "repo": "~/Projects/<repo>", "members": ["person:<p>"]}, ...]}
  label    kebab-case, unique — names the channel in the start report, its cursor and its lock.
  repo     the channel's local clone (may start with ~).
  members  optional: who belongs, as audience tokens (device id, person:<p>, os:<o>, everyone),
           resolved through THAT repo's parties.json. A device that is no member neither reads
           nor watches the channel (one brain repo serves several devices of one operator, each
           in different channels). Absent = everyone who has the clone: the repo's own access is
           the scope. Without SHARED_MEMORY_SELF membership cannot be told; the channel is read
           (loud side) and the inbox says SELF is unset.
  interval optional, seconds (collab-watch), default the `shared_memory.interval` of
           collab-watch.json.
The default shared memory (SHARED_MEMORY_REPO, default ~/Projects/brain-shared-memory) is always
the FIRST channel and is not listed: its place, cursor, lock and ids stay exactly what they were,
so every tool that knows only that repo still agrees. No file = that one channel = the behaviour
before this module, byte for byte.

Usage (for the shell readers): shared_channels.py further
  prints `<label><TAB><repo>` per further channel this instance is a member of; a broken file
  prints `ERROR: <why>` on stderr and exits 1.
Stdlib only; runs under `python3` or `python`.
"""
from __future__ import annotations

import json
import os
import re
import sys
from importlib import import_module
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from project_dir import resolve_project_dir  # noqa: E402
from shared_answers import default_repo  # noqa: E402

LABEL = re.compile(r"^[a-z0-9][a-z0-9-]*$")
# Prefixes the open-items keys already use: a channel of that name would read as a session or a
# wake item there.
RESERVED = {"shared-memory", "start", "end", "wake"}


def config_path(root=None) -> Path:
    env = os.environ.get("SHARED_MEMORY_CHANNELS_CONFIG", "")
    if env:
        return Path(env)
    return Path(root or resolve_project_dir(HERE)) / ".claude" / "rules" / "shared-memory-channels.json"


def default_channel(repo=None) -> dict:
    return {"label": "", "repo": str(repo or default_repo()), "path": "", "members": None,
            "interval": None, "default": True}


def _norm(p: str) -> str:
    return os.path.normcase(os.path.abspath(os.path.expanduser(p)))


def load(root=None, default=None, path=None) -> list[dict]:
    """[default, further...]. Raises ValueError for a file that cannot be used — a list that is
    half read would drop a channel silently."""
    chans = [default_channel(default)]
    p = Path(path) if path else config_path(root)
    if not p.is_file():
        return chans
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise ValueError(f"{p.name} is not valid JSON ({e})")
    entries = data.get("channels") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        raise ValueError(f'{p.name}: "channels" must be a list')
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            raise ValueError(f"{p.name}: channels[{i}] is not an object")
        label, repo, members = e.get("label"), e.get("repo"), e.get("members")
        if not isinstance(label, str) or not LABEL.match(label) or label in RESERVED:
            raise ValueError(f"{p.name}: channels[{i}].label must be kebab-case and not one of "
                             f"{sorted(RESERVED)}, got {label!r}")
        if any(c["label"] == label for c in chans):
            raise ValueError(f"{p.name}: label {label!r} used twice — two channels would share one cursor")
        if not isinstance(repo, str) or not repo.strip() or ("<" in repo and ">" in repo):
            raise ValueError(f"{p.name}: channels[{i}] ({label}): repo is empty or still a template placeholder")
        if members is not None and not (isinstance(members, list) and all(isinstance(m, str) for m in members)):
            raise ValueError(f"{p.name}: channels[{i}] ({label}): members must be a list of audience tokens")
        if any("<" in m and ">" in m for m in members or []):
            raise ValueError(f"{p.name}: channels[{i}] ({label}): members still carry a template placeholder")
        for c in chans:
            if _norm(repo) == _norm(c["repo"]):
                what = "the default shared memory (always the first channel, never listed)" if c["default"] \
                    else f"channel {c['label']!r}"
                raise ValueError(f"{p.name}: channels[{i}] ({label}): {repo} is already {what}")
        chans.append({"label": label, "repo": os.path.expanduser(repo), "path": repo,
                      "members": members or None, "interval": e.get("interval"), "default": False})
    return chans


def is_member(chan: dict, me: set[str] | None = None) -> bool:
    if not chan.get("members"):
        return True
    _parties = import_module("shared-memory-parties")  # only a channel with members needs it
    if me is None:
        me = _parties.tokens(os.environ.get("SHARED_MEMORY_SELF", "").replace(",", " "))
    if not me:
        return True
    parties = _parties.load(Path(chan["repo"]), "origin/main")
    want = set().union(*(_parties.tokens(m) for m in chan["members"]))
    return bool((_parties.expand_self(me, parties) | _parties.EVERYONE) & want)


def member_channels(root=None, default=None, path=None) -> list[dict]:
    """The channels THIS instance reads: the default one, then every further one it belongs to."""
    chans = load(root, default, path)
    return chans[:1] + [c for c in chans[1:] if is_member(c)]


def main(argv: list[str]) -> int:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # parsed by bash (OS-9)
    if argv[1:] != ["further"]:
        print("usage: shared_channels.py further", file=sys.stderr)
        return 64
    try:
        chans = member_channels()
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    for c in chans[1:]:
        print(f"{c['label']}\t{Path(c['repo']).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
