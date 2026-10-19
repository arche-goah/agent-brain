#!/usr/bin/env python3
"""Who is who in the shared-memory repo: people, their devices, each device's OS — and what
an `audience` value addresses.

WHY (operator order 2026-10-11): `audience` named single machines only. A request for a
Windows check went to one Windows machine that was switched off, while another party's
Windows machines could have run it — the writer had to know every machine id by heart, and
picked one. The operator's cut: address by OS, by person (every device of theirs), or by a
specific device. The writer states the intent; this module turns it into who it reaches.

DATA lives in the shared-memory repo, not here (this repo is public; the list of people and
machines is not): `parties.json` at the repo root, one file every party reads.
  {"people": {"<person>": {"github": "<login>",
                           "devices": {"<device-id>": {"os": "macos" | "windows" | "linux" | null}},
                           "legacy_ids": ["<old id>", ...]}}}
`os: null` = not known; such a device is reached by its id and its person, never by an
`os:` category (an unknown OS is not guessed into one).

AUDIENCE SYNTAX (comma-separated, any mix):
  <device-id>          exactly that device (as before)
  person:<person>      every device of that person
  os:<macos|windows|linux>   every device with that OS
  alle-collaborator | alle | all | everyone   everyone

Stdlib only; no repo, no file, broken JSON -> empty parties (callers then behave as before
this module existed: plain device tokens only).
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

PARTIES_FILE = "parties.json"
OS_VALUES = ("macos", "windows", "linux")
EVERYONE = {"alle", "all", "everyone", "alle-collaborator"}
# A category token keeps its prefix; everything else splits on what is not a word or a hyphen,
# exactly as the readers did before (`alex-laptop:` in a heading still reads `alex-laptop`).
TOKEN = re.compile(r"(?:(?:os|person):)?[\w-]+")


def tokens(s: str) -> set[str]:
    return {t for t in TOKEN.findall((s or "").lower()) if t}


def load(repo: Path, ref: str | None = None) -> dict:
    """parties.json at `ref` (what a fetching reader sees) or, without a ref, on disk."""
    raw = ""
    if ref:
        r = subprocess.run(["git", "-C", str(repo), "show", f"{ref}:{PARTIES_FILE}"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        raw = r.stdout if r.returncode == 0 else ""
    if not raw:
        p = Path(repo) / PARTIES_FILE
        raw = p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""
    try:
        data = json.loads(raw) if raw else {}
    except ValueError:
        return {}
    return data if isinstance(data.get("people"), dict) else {}


def devices(parties: dict) -> dict[str, tuple[str, str | None]]:
    """{device-id: (person, os)} — legacy ids count as devices of their person, OS unknown."""
    out = {}
    for person, p in (parties.get("people") or {}).items():
        if not isinstance(p, dict):
            continue
        for dev, d in (p.get("devices") or {}).items():
            os_ = (d or {}).get("os") if isinstance(d, dict) else None
            out[dev.lower()] = (person.lower(), os_.lower() if isinstance(os_, str) else None)
        for dev in p.get("legacy_ids") or []:
            out.setdefault(str(dev).lower(), (person.lower(), None))
    return out


def categories(device: str, parties: dict) -> set[str]:
    """Every audience token that reaches `device`: its id, `person:<p>`, `os:<o>`."""
    dev = devices(parties).get(device.lower())
    if not dev:
        return {device.lower()}
    person, os_ = dev
    out = {device.lower(), f"person:{person}"}
    if os_ in OS_VALUES:
        out.add(f"os:{os_}")
    return out


def expand_self(me: set[str], parties: dict) -> set[str]:
    """SELF tokens plus the categories of every known device among them; a token that is a
    person's name adds `person:<name>`. Old SELF lists keep working unchanged."""
    out = set(me)
    people = {p.lower() for p in (parties.get("people") or {})}
    for t in me:
        out |= categories(t, parties) if t in devices(parties) else set()
        if t in people:
            out.add(f"person:{t}")
    return out


def known(parties: dict) -> set[str]:
    """Every token an `audience` may use."""
    devs = devices(parties)
    return (set(devs) | {f"person:{p}" for p, _ in devs.values()}
            | {f"person:{p.lower()}" for p in (parties.get("people") or {})}
            | {f"os:{o}" for o in OS_VALUES} | EVERYONE)


HANDOVER_KEEPS = re.compile(r"\bhandover-keeps:\s*\S", re.I)
REFERRAL_BUILTIN = [r"\b(?:on|with) your (?:human|operator)'?s? (?:word|ok|yes)\b",
                    r"\bask your (?:human|operator)\b", r"\byour (?:human|operator) (?:decides|has to decide)\b"]


def handed_over_to(person: str, parties: dict) -> str:
    """The person whose AIs decide `person`'s AI questions (`people.<p>.ai_handover.to`), or ""."""
    p = (parties.get("people") or {}).get(person) or {}
    h = p.get("ai_handover") if isinstance(p, dict) else None
    return str((h or {}).get("to") or "").lower() if isinstance(h, dict) else ""


def handover_referral(sender: str, audience: str, text: str, parties: dict) -> str | None:
    """The person a message sends an AI question BACK to although they handed it over, or None.

    WHY (operator decision 2026-10-18): a collaborator's operator handed every AI question of
    their brain to another party's AIs (recorded as `ai_handover` in parties.json). Measured
    that day: two receiving AIs still answered two such questions with "on your human's word" —
    the question went back to exactly the person who had handed it over. A message from a
    receiving AI to a device of the handing-over person that refers the decision to that person
    is named; `handover-keeps: <why>` marks the cases the handover keeps (their domain, money,
    hardware, hand-only steps). Referral wording beyond the English built-ins is data:
    `handover_referral_patterns` at the root of parties.json."""
    devs = devices(parties)
    me = devs.get((sender or "").strip().lower())
    if not me or HANDOVER_KEEPS.search(text or ""):
        return None
    pats = REFERRAL_BUILTIN + [str(x) for x in parties.get("handover_referral_patterns") or []]
    try:
        rx = re.compile("|".join(pats), re.I)
    except re.error:
        rx = re.compile("|".join(REFERRAL_BUILTIN), re.I)
    # Quoted wording is talk ABOUT a referral (a correction that cites the old answer), not one.
    plain = re.sub(r"„[^“”\"\n]*[“”\"]|\"[^\"\n]*\"|`[^`\n]*`|«[^»\n]*»", " ", text or "")
    if not rx.search(plain):
        return None
    for t in tokens(audience):
        person = t.split(":", 1)[1] if t.startswith("person:") else (devs.get(t) or (None,))[0]
        if person and handed_over_to(person, parties) == me[0]:
            return person
    return None


def is_category(token: str) -> bool:
    return token.startswith(("os:", "person:")) or token in EVERYONE


# Who is asked first for a request that several parties can take (operator order 2026-10-13):
# `priority:` is an ordered list of any audience tokens (device, person:, os:, everyone). It is
# INFORMATION, not a sequence — no timers, no escalation; anyone reached may claim the task at
# any time, and decides themselves whether they can and want to take a lower-priority one.
#   entry frontmatter  priority: <token>, <token>, ...
#   parties.json       "priority": {"os:windows": [...]}   (default for an entry addressed to
#                      exactly that one category)
# Taken: an entry naming the request in `claims:` (or `answers:`) closes it for everyone.
PRIORITY = re.compile(r"^\s+priority:\s*(.+?)\s*$", re.M)


def priority(head: str, audience: str, parties: dict) -> list[str]:
    """The entry's own `priority:`, else the parties.json default for its single category."""
    m = PRIORITY.search(head or "")
    if m:
        return [c.strip().lower() for c in m.group(1).split(",") if c.strip()]
    cats = [t for t in tokens(audience) if is_category(t)]
    dflt = parties.get("priority") if isinstance(parties.get("priority"), dict) else {}
    return [str(c).lower() for c in dflt.get(cats[0], [])] if len(cats) == 1 else []


def rank(prio: list[str], me: set[str]) -> int:
    """0-based position of the first priority token that reaches us; not listed = after all.
    `me` must include the everyone spellings for an `alle` entry to match."""
    return next((i for i, c in enumerate(prio) if tokens(c) & me), len(prio))


# LOG headings — shared by the inbox (who a message is for) and the lint (who a request goes
# to). Measured 2026-09-25 across all LOGs: `## <date> · <von> — <title>` is one of FOUR live
# shapes. Half of the September headings use an ASCII hyphen (`## <date> <von> - <title>`),
# older ones carry a time note and no title (`## <date> (Abend) — <von>`). A pattern for
# the first shape alone dropped every message of the second — silently. A FIFTH shape names
# the session after the sender: `## <date> · <von> (<session>) — AN <x>: <title>` (measured
# 2026-10-11: the reply of a second session of one machine id matched nothing and was
# dropped, even unfiltered — the requester waited for an answer that had already arrived).
HEADING = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})(?:\s*\([^)]*\))?\s*(?:[·—-]\s*)?"
                     r"([\w-]+)(?:\s*\([^)]*\))?(?:\s+[—-]\s+(.*?))?\s*$")


# A LOG entry has no file name, so it gets a derived identity: `<area>/LOG@<date>#<n>`, n = the
# position of its heading among that day's headings (HEADING matches) in that LOG, from 1. Not
# per sender: the id names no sender, and counting per sender gave two parties' entries one id
# (measured on the shared-memory repo: `core/LOG@2026-10-16#13` twice).
# Before it, the readers keyed a LOG request by its first 40 characters and closed it when a
# reply repeated its words — 15 fixes in 7 days to open-items, 5 to the reply match in 9.
# Appending keeps every id; the monthly rotation moves whole months in order to
# `<area>/archive/LOG-<YYYY-MM>.md`, so an id stays the same there. Inserting a heading above
# an older one of the same sender and day shifts it — append, never insert.
LOG_ID = re.compile(r"(?<![\w./-])(?:[\w.-]+/)?LOG@\d{4}-\d{2}-\d{2}#\d+\b")


# From this date on a request's state is WRITTEN (the inbox settles a LOG request only by its
# id; the lint asks a request to a party to be a file). One date for both tools.
STATE_SINCE = "2026-10-20"


def log_ids(area: str, heads: list[tuple[str, str]]) -> list[str]:
    """The id of every heading, given (date, sender) per HEADING match in file order."""
    seen: dict[str, int] = {}
    out = []
    for date, _sender in heads:
        n = seen[date] = seen.get(date, 0) + 1
        out.append(f"{area}/LOG@{date}#{n}" if area and area != "root" else f"LOG@{date}#{n}")
    return out


def log_ids_in(text: str, area: str) -> list[str]:
    """Every id a LOG text carries (a LOG.md or its monthly archive file)."""
    heads = [(m.group(1), m.group(2)) for m in map(HEADING.match, text.splitlines()) if m]
    return log_ids(area, heads)


def addressees(title: str) -> str | None:
    """`AN x + y: title` -> `x + y`; None when the heading names nobody. The colon of an
    audience category (`AN os:windows: title`) is not the end of the addressees."""
    safe = re.sub(r"\b(os|person):(?=[\w-])", "\\1\x00", title or "")
    m = re.match(r"^(?:AN|An|an|TO|To)\s+([^:]+):", safe)
    return m.group(1).replace("\x00", ":") if m else None


# A message that asks for a check on Windows: names Windows AND a check word, in either
# language the repo is written in. Constant on purpose — the lint has no instance-data hook,
# and a request phrased otherwise is a miss in the safe direction (no finding).
WINDOWS_CHECK = re.compile(r"(?=.*\bwin(?:dows)?\b)(?=.*(?:check|run|test|verif|lauf|pr(?:\xfc|ue)f|pruef))",
                           re.I | re.S)
# The writer's way to say one machine IS needed (the finding then stays silent).
ONE_MACHINE = re.compile(r"\bone[- ]machine:|\bnur diese maschine\b", re.I)


def windows_check_to_one_device(text: str, audience: str, parties: dict) -> str | None:
    """The single Windows device a Windows check is sent to, when it should go to
    `os:windows` instead; None when the message is fine (or is no Windows check)."""
    if not parties or not WINDOWS_CHECK.search(text or "") or ONE_MACHINE.search(text or ""):
        return None
    aud = tokens(audience)
    if any(is_category(t) for t in aud):
        return None
    devs = devices(parties)
    win = sorted(t for t in aud if devs.get(t, ("", None))[1] == "windows")
    return win[0] if len(win) == 1 else None
