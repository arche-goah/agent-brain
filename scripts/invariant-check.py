#!/usr/bin/env python3
"""Check an invariant register: is a closed class still closed?

A fix hits the instance the incident names. The class stays open and comes back
(measured on a proving instance 2026-08-06: five classes, up to 15 single fixes of
the same root). A register therefore stores the INVARIANT together with the search
command that spans its space — and this script runs that search again.

  invariant-check.py <register.md> [<register.md> ...]

Exit 0 = every baseline matches, 1 = drift (new/changed/vanished hits) or a failed
search. Open classes above the build threshold are REPORTED, never failed: an open
invariant is the register's normal state, and a gate that fires on it permanently
would get disabled within the hour and take the working gates with it (measured;
this script is a REPORT — bind drift-only gates to CI, not this exit code).

Register format (Markdown, blocks starting at '## '):

    root: .                       # once at the top, relative to the register file

    ## C-1 — short title
    invariant: the sentence that spans the search space (never an anecdote)
    pattern:   ERE for grep -rnE           | OR
    check:     <external, e.g. a tool>     | when no grep covers the space
    paths:     grep arguments after the pattern (--include=/--exclude= plus paths)
    mechanizable: no|tool — <reason>       # DELIBERATELY not a grep, see below
    known:     path=N path=N               # baseline: hits per file
    instances: 3                           # REAL sites of the class (human count)
    repeat:    yes|no                      # did it come back after a fix?
    status:    open|closed                 # German offen|geschlossen also accepted
    note:      free text

`known` catches newcomers (drift); `instances` decides the build threshold:
1 site = done · 2 = fix both, no mechanism · >=3 or repeat = build a mechanism.

WHAT "closed" IS ALLOWED TO MEAN (added 2026-08-31): a register's own definition is that
closed means the search runs and finds nothing unknown — not that the matter feels
settled. So an entry that says `status: closed` while carrying neither a `pattern` nor a
`mechanizable: tool` has nothing left that could ever contradict the word: no search
re-runs, no tool re-checks. Those are listed at the end, as a report, never as a failure.
The measurement behind it: a class was closed on the strength of its CARRIER having been
built, and three prose copies of the value that carrier now owned stayed behind — going
stale the moment the carrier's value changed. A carrier does not delete the copies, it
only makes them redundant; enumerating them is a separate act, and this list is where
skipping it becomes visible.

WHY `mechanizable` exists (measured on a real register 2026-08-30): of 43 entries, 8
carried a pattern and 35 did not — and the report printed all 35 identically, as
`--  external: <check text>`. That collapses two different states into one symbol:

  * an invariant that CANNOT be mechanized, because the search term is different every
    time (B-1: "grep the load-bearing nouns of whatever rule just changed" — the word is
    in the change, not in the register), and
  * an invariant that simply has not been mechanized YET.

The first is a finished decision; the second is a backlog item. Printed the same way,
the backlog is invisible, and a register whose whole purpose is that "a class needs a
place where it stays open" quietly stops holding half its classes open. So: state the
reason: `mechanizable: no — …` for a judgement only a human can make, or
`mechanizable: tool — …` when a NAMED TOOL re-checks it instead of a grep (measured on
the same register: several entries name a bundled effect probe, a state-file report or an MCP
verb in their `check` field — those are mechanized, just not by a pattern). Both report
as deliberate. Leave the field off and the entry reports as `??` and is counted in a
closing summary: held by prose alone.
"""
import fnmatch
import os
import re
import shlex
import sys
from pathlib import Path

FIELDS = ("invariant", "pattern", "check", "paths", "known", "instances", "repeat",
          "status", "note", "mechanizable")

OPEN_STATES = ("offen", "open")

# A status line is prose, not an enum: registers in the wild carry "open (R-14)",
# "closed for the process case, the class stays open", "OPEN AGAIN since ...", and the
# same shapes in the register's own language. Matching the field
# EXACTLY against OPEN_STATES therefore recognised only the handful of entries whose
# status is the bare word — measured on a real register: 9 of 45. The other 36 silently
# lost their build-threshold verdict, which is the one line that says whether a mechanism
# is due. Match the WORD anywhere in the status instead, and read the two states
# separately: a status can say both ("closed for X, the class stays open").
_OPEN_RE = re.compile(r"\b(offen|open)\b", re.I)
_CLOSED_RE = re.compile(r"\b(geschlossen|closed)\b", re.I)


def says_open(status):
    return bool(_OPEN_RE.search(status or ""))


def says_closed(status):
    return bool(_CLOSED_RE.search(status or ""))


SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv"}


def parse(path):
    text = path.read_text(encoding="utf-8")
    m = re.search(r"^root:\s*(.*)$", text, re.M)
    root = m.group(1).strip() if m else "."
    blocks, cur = [], None
    for line in text.splitlines():
        if line.startswith("## "):
            cur = {"id": line[3:].strip()}
            blocks.append(cur)
            continue
        m = re.match(r"^(%s):\s*(.*)$" % "|".join(FIELDS), line.strip())
        if m and cur is not None:
            cur[m.group(1)] = m.group(2).strip()
    return root, blocks


def counts(root, pattern, paths):
    """Matching LINES per file (grep -c semantics), pure Python.

    The first version shelled out to `grep -rcE` — a Windows mine: the tool name
    in PATH is an assumption, not a promise, and core scripts run on three OSes.
    `paths` keeps the grep argument shape (`--include=GLOB` and `--exclude=GLOB`
    filters, everything
    else is a path) so existing registers stay valid unchanged.
    """
    rx = re.compile(pattern)
    includes, excludes, targets = [], [], []
    for tok in shlex.split(paths or "."):
        if tok.startswith("--include="):
            includes.append(tok[len("--include="):])
        elif tok.startswith("--exclude="):
            excludes.append(tok[len("--exclude="):])
        else:
            targets.append(tok)

    def wanted(name):
        # --exclude belongs to the documented grep argument shape; without it a class
        # whose space is production code ONLY cannot be stated at all, because the
        # fixtures exercising the same pattern drown the baseline. Unsupported, the
        # token fell through to targets and the search died with "path not found".
        if any(fnmatch.fnmatch(name, g) for g in excludes):
            return False
        return not includes or any(fnmatch.fnmatch(name, g) for g in includes)

    def count_file(p):
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return 0
        return sum(1 for line in text.splitlines() if rx.search(line))

    out = {}
    rootp = Path(root)
    for target in targets or ["."]:
        tp = (rootp / target).resolve()
        files = []
        if tp.is_file():
            files = [tp]
        elif tp.is_dir():
            for dirpath, dirnames, filenames in os.walk(tp):
                dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
                files.extend(Path(dirpath) / f for f in filenames if wanted(f))
        else:
            raise RuntimeError(f"path not found: {target}")
        for p in files:
            n = count_file(p)
            if n > 0:
                out[p.relative_to(rootp.resolve()).as_posix()] = n
    return out


def baseline(spec):
    out = {}
    for tok in (spec or "").split():
        f, _, n = tok.rpartition("=")
        if f and n.isdigit():
            out[f] = int(n)
    return out


def verdict(b):
    """Build threshold — the search is mandatory, the build is not.

    `instances` is written by hand and is prose as often as it is a number
    ("2 checked, 1 turned out to be miswired"). Read the FIRST integer in it rather than
    the whole field: int() on the whole thing raised ValueError, and the crash stayed
    invisible for as long as the status match was exact — those entries never reached
    this line. Two defects that hid each other; the wider status match uncovered this one.
    """
    m = re.search(r"\d+", b.get("instances", "") or "")
    n = int(m.group()) if m else 1
    if b.get("repeat", "no") == "yes" or n >= 3:
        return "MECHANISM due (>=3 sites or repeat after a fix)"
    if n == 2:
        return "fix both sites, no shared mechanism"
    return "single case — no build"


def main(argv):
    bad = 0
    unmechanized = []
    asserted_closed = []
    for reg in argv or ["docs/maintenance/invariants.md"]:
        regp = Path(reg).resolve()
        root, blocks = parse(regp)
        rootp = (regp.parent / root).resolve()
        print(f"\n=== {regp.name}  (root: {rootp}) ===")
        for b in blocks:
            head = f"{b['id']}  [{b.get('status', '?')}]"
            if not b.get("pattern"):
                why = b.get("mechanizable", "").strip()
                kind = why.split(None, 1)[0].lower().rstrip(":—-") if why else ""
                if kind in ("no", "tool"):
                    label = ("external by decision" if kind == "no"
                             else "mechanized by a tool")
                    print(f"  --  {head}\n      {label}: {why}")
                else:
                    # No pattern AND no stated reason: a backlog item, not a decision.
                    unmechanized.append(b["id"])
                    print(f"  ??  {head}\n      no pattern and no reason — mechanize it, "
                          f"or record `mechanizable: no — <why>`")
                print(f"      check: {b.get('check', '(no check on file)')}")
                if says_open(b.get("status", "")):
                    print(f"      -> {verdict(b)}")
                if says_closed(b.get("status", "")) and kind != "tool":
                    # Closed, and nothing here could ever re-open it: no pattern to re-run
                    # and no tool named. That is a verdict, not a measurement.
                    asserted_closed.append((b["id"], says_open(b.get("status", ""))))
                continue
            try:
                now = counts(rootp, b["pattern"], b.get("paths"))
            except (RuntimeError, FileNotFoundError) as e:
                print(f"  !!  {head}\n      search failed: {e}")
                bad = 1
                continue
            was = baseline(b.get("known"))
            new = {f: n for f, n in now.items() if f not in was}
            grew = {f: (was[f], n) for f, n in now.items() if f in was and n != was[f]}
            gone = [f for f in was if f not in now]
            if new or grew or gone:
                bad = 1
                print(f"  !!  {head}")
                for f, n in new.items():
                    print(f"      NEW site: {f} ({n} hits) — the class is growing")
                for f, (o, n) in grew.items():
                    print(f"      drift: {f} {o} -> {n} hits")
                for f in gone:
                    print(f"      vanished: {f} — update the baseline")
            else:
                print(f"  ok  {head}  ({sum(now.values())} hits in {len(now)} files)")
            if says_open(b.get("status", "")):
                print(f"      -> {verdict(b)}")

    if unmechanized:
        # Printed as a count, because a backlog buried in per-entry lines is a backlog
        # nobody reads — the same reason this distinction was introduced at all.
        print(f"\n  {len(unmechanized)} invariant(s) with neither a pattern nor a stated "
              f"reason — they are held by prose alone:")
        for i in unmechanized:
            print(f"    ?? {i}")

    if asserted_closed:
        # The register's own definition: "closed" means the search runs and finds nothing
        # unknown — not that it feels settled. An entry that is closed while carrying
        # neither a pattern nor a named tool has no instrument that could ever re-open it,
        # so nothing will contradict the word "closed" again. Measured on a real register
        # 2026-08-31: a class was closed on the strength of its CARRIER being built, while
        # three prose copies of the value the carrier now owned stayed behind and went
        # stale the moment the carrier's value changed. The carrier does not delete the
        # copies; it only makes them redundant. Enumerating them is a separate act, and
        # this list is where the omission becomes visible.
        full = [i for i, also_open in asserted_closed if not also_open]
        print(f"\n  {len(asserted_closed)} closed invariant(s) with no instrument that "
              f"could re-open them ({len(full)} closed outright):")
        for i, also_open in asserted_closed:
            print(f"    -- {i}{'' if not also_open else '  (partly still open)'}")
        print("     Either give them a `pattern`/tool, or say in `status` that the close "
              "is a judgement with no instrument — so the next reader knows which it is.")
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
