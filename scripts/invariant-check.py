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
    paths:     grep arguments after the pattern
    mechanizable: no|tool — <reason>       # DELIBERATELY not a grep, see below
    known:     path=N path=N               # baseline: hits per file
    instances: 3                           # REAL sites of the class (human count)
    repeat:    yes|no                      # did it come back after a fix?
    status:    open|closed                 # German offen|geschlossen also accepted
    note:      free text

`known` catches newcomers (drift); `instances` decides the build threshold:
1 site = done · 2 = fix both, no mechanism · >=3 or repeat = build a mechanism.

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
    `paths` keeps the grep argument shape (`--include=GLOB` filters, everything
    else is a path) so existing registers stay valid unchanged.
    """
    rx = re.compile(pattern)
    includes, targets = [], []
    for tok in shlex.split(paths or "."):
        if tok.startswith("--include="):
            includes.append(tok[len("--include="):])
        else:
            targets.append(tok)

    def wanted(name):
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
    """Build threshold — the search is mandatory, the build is not."""
    n = int(b.get("instances", "1") or 1)
    if b.get("repeat", "no") == "yes" or n >= 3:
        return "MECHANISM due (>=3 sites or repeat after a fix)"
    if n == 2:
        return "fix both sites, no shared mechanism"
    return "single case — no build"


def main(argv):
    bad = 0
    unmechanized = []
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
                if b.get("status") in OPEN_STATES:
                    print(f"      -> {verdict(b)}")
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
            if b.get("status") in OPEN_STATES:
                print(f"      -> {verdict(b)}")

    if unmechanized:
        # Printed as a count, because a backlog buried in per-entry lines is a backlog
        # nobody reads — the same reason this distinction was introduced at all.
        print(f"\n  {len(unmechanized)} invariant(s) with neither a pattern nor a stated "
              f"reason — they are held by prose alone:")
        for i in unmechanized:
            print(f"    ?? {i}")
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
