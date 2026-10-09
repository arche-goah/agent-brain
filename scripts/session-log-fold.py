#!/usr/bin/env python3
"""Fold old session-log (or decision-log) entries into immutable fold files.

The session log (`docs/maintenance/session-log.md`) is an append-only protocol: one
line per session plus a few indented index lines. Append-only, but not unbounded — a
file that grows past what one read delivers gets read in part without anyone noticing.
A fold solves that WITHOUT consolidating anything:

- purely extractive: entries are MOVED byte-identically into
  `docs/maintenance/session-log-folds/<id>.md`, never edited; one marker line
  (`- FOLD <id> | entries=N | <first> .. <last> | <path>`) takes their place
- fold id is deterministic: sha256 over the exact child bytes (first 12 hex)
- same id = no-op (re-running with the same input changes nothing)
- marker lines are never folded again (no fold-of-folds)
- proof before and after writing: prefix + children + suffix == original bytes
- line endings are kept as they are (bytes in, bytes out — no platform translation)

`--log decision` runs the same engine with the same guarantees on the decision log
(`docs/maintenance/decision-log.md`, the second protocol of rules/working-rules.md):
entries are `## YYYY-MM-DD ...` sections, the marker is `## FOLD <id> | ...`, folds go
to `docs/maintenance/decision-log-folds/`. Its head carries a format template and code
fences: any other `## ` heading and every ``` line is a GUARD block — never folded, and
an entry range that a guard interrupts is refused as non-contiguous. The decision log is
usually written newest-first; the fold selects by date, not by position, so that works.
One engine for both logs on purpose: a second copy of this code would be a second place
to get the byte-exact proof wrong.

Two modes:
  --before YYYY-MM-DD   fold every entry strictly older than that date (manual run)
  --max-bytes N         the close-time mode: nothing happens while the log is <= N
                        bytes; above it, the oldest whole days are folded until the
                        log is <= N/2 (hysteresis: the next fold is ~N/2 bytes away, not
                        one session away). Entries of --today (default: the local date)
                        are never folded.
Preview by default; --apply writes.

Usage: session-log-fold.py (--before YYYY-MM-DD | --max-bytes N) [--apply]
                           [--log session|decision] [--root DIR] [--today YYYY-MM-DD]
Exit 0 = folded, previewed or nothing to do; 1 = refused (nothing written).
"""
import argparse
import datetime
import hashlib
import os
import re
import sys
from pathlib import Path

# One profile per protocol. HEAD's first group is the entry date, all its groups joined
# are the entry's sort key for the range; a GUARD line starts a block that never folds.
PROFILES = {
    "session": {
        "log": "docs/maintenance/session-log.md",
        "folds": "docs/maintenance/session-log-folds",
        "head": re.compile(r"^- (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) \|"),
        "fold_mark": re.compile(r"^- FOLD "),
        "marker": "- FOLD",
        "guard": None,
    },
    "decision": {
        "log": "docs/maintenance/decision-log.md",
        "folds": "docs/maintenance/decision-log-folds",
        "head": re.compile(r"^## (\d{4}-\d{2}-\d{2})"),
        "fold_mark": re.compile(r"^## FOLD "),
        "marker": "## FOLD",
        "guard": re.compile(r"^(## |```\s*$)"),
    },
}
P = PROFILES["session"]
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")


def parse_blocks(text):
    """Split log text into blocks [kind, date, lines]; lines keep their line ending."""
    blocks = []
    for line in text.splitlines(keepends=True):
        m = P["head"].match(line)
        if P["fold_mark"].match(line):
            blocks.append(["fold", None, [line]])
        elif m:
            blocks.append(["entry", m.group(1), [line]])
        elif P["guard"] is not None and P["guard"].match(line):
            blocks.append(["guard", None, [line]])  # template heading / fence: protected
        elif blocks:
            blocks[-1][2].append(line)  # indented index lines belong to their entry
        else:
            blocks.append(["pre", None, [line]])  # preamble before the first entry
    return blocks


def size(blocks, skip=()):
    return sum(len("".join(b[2]).encode("utf-8")) for i, b in enumerate(blocks) if i not in skip)


def cutoff_for(blocks, max_bytes, today):
    """Smallest date cutoff that brings the log to <= max_bytes // 2 (whole days only,
    never today). None when the log is within max_bytes."""
    if size(blocks) <= max_bytes:
        return None
    dates = sorted({b[1] for b in blocks if b[0] == "entry" and b[1] < today})
    target = max_bytes // 2
    for i, d in enumerate(dates):
        cut = dates[i + 1] if i + 1 < len(dates) else today
        idx = {j for j, b in enumerate(blocks) if b[0] == "entry" and b[1] < cut}
        # the marker line replaces the children; ~130 bytes, counted generously
        if size(blocks, idx) + 200 <= target:
            return cut
    return today if dates else None


def main():
    global P
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: session-closing.sh reads this
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--before", metavar="YYYY-MM-DD",
                      help="fold entries strictly older than this date")
    mode.add_argument("--max-bytes", type=int, metavar="N",
                      help="fold only when the log exceeds N bytes, down to N/2")
    ap.add_argument("--apply", action="store_true", help="write (default: preview only)")
    ap.add_argument("--log", choices=sorted(PROFILES), default="session",
                    help="which protocol to fold (default: session)")
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(),
                    help="brain root (default: $CLAUDE_PROJECT_DIR or cwd)")
    ap.add_argument("--today", default=datetime.date.today().isoformat(), metavar="YYYY-MM-DD")
    args = ap.parse_args()
    P = PROFILES[args.log]
    name = f"{args.log}-log"

    root = Path(args.root)
    log = root / P["log"]
    if not log.is_file():
        print(f"no-op: no {name} at {P['log']}")
        return 0
    original = log.read_bytes().decode("utf-8")
    blocks = parse_blocks(original)

    if args.max_bytes is not None:
        if args.max_bytes <= 0 or not DATE.fullmatch(args.today):
            print("refused: --max-bytes must be > 0 and --today YYYY-MM-DD")
            return 1
        before = cutoff_for(blocks, args.max_bytes, args.today)
        if before is None:
            why = "" if size(blocks) <= args.max_bytes else " (over it, but only today's entries)"
            print(f"no-op: {name} {size(blocks)} bytes, threshold {args.max_bytes}{why}")
            return 0
    else:
        before = args.before
        if not DATE.fullmatch(before):
            print("refused: --before must be YYYY-MM-DD")
            return 1

    idx = [i for i, (kind, date, _) in enumerate(blocks) if kind == "entry" and date < before]
    if not idx:
        print(f"no-op: no foldable entries before {before}")
        return 0
    if idx != list(range(idx[0], idx[0] + len(idx))):
        print(f"refused: entries before {before} are not contiguous (out-of-order entries "
              f"or a guard block between them) - fold by hand with --before, nothing written")
        return 1

    children = "".join(l for i in idx for l in blocks[i][2])
    child_bytes = children.encode("utf-8")
    sha = hashlib.sha256(child_bytes).hexdigest()
    fid = sha[:12]
    keys = sorted(" ".join(P["head"].match(blocks[i][2][0]).groups()) for i in idx)
    ts_first, ts_last = keys[0], keys[-1]
    rel = f"{P['folds']}/{fid}.md"
    fold_file = root / rel
    nl = "\r\n" if children.endswith("\r\n") else "\n"
    fold_line = f"{P['marker']} {fid} | entries={len(idx)} | {ts_first} .. {ts_last} | {rel}{nl}"
    header = (f"# {name} fold {fid}{nl}"
              f"# source: {P['log']} — children moved here byte-identically; NEVER edit{nl}"
              f"# entries: {len(idx)} | range: {ts_first} .. {ts_last} | "
              f"bytes: {len(child_bytes)} | sha256: {sha}{nl}{nl}")
    fold_content = header + children

    prefix = "".join(l for i in range(idx[0]) for l in blocks[i][2])
    suffix = "".join(l for i in range(idx[-1] + 1, len(blocks)) for l in blocks[i][2])
    new_log = prefix + fold_line + suffix

    if fold_file.is_file() and fold_file.read_bytes().decode("utf-8") == fold_content \
            and fold_line in original:
        print(f"no-op: fold {fid} already applied")
        return 0

    print(f"{name} fold {fid}: {len(idx)} entries ({ts_first} .. {ts_last}), "
          f"log {len(original.encode('utf-8'))} -> {len(new_log.encode('utf-8'))} bytes, "
          f"file {rel}")
    if not args.apply:
        print("preview only - re-run with --apply to write")
        return 0

    if prefix + children + suffix != original:
        print("refused: reassembly check failed - nothing written")
        return 1
    fold_file.parent.mkdir(parents=True, exist_ok=True)
    fold_file.write_bytes(fold_content.encode("utf-8"))
    log.write_bytes(new_log.encode("utf-8"))

    extracted = fold_file.read_bytes().decode("utf-8")[len(header):]
    on_disk = log.read_bytes().decode("utf-8")
    ok_sha = hashlib.sha256(extracted.encode("utf-8")).hexdigest() == sha
    ok_asm = on_disk.replace(fold_line, extracted, 1) == original
    if not (ok_sha and ok_asm):
        print(f"VERIFY FAILED (sha={ok_sha}, reassembly={ok_asm}) - restore both files "
              f"from git before using the log")
        return 1
    print("applied + verified: sha256 match, byte-exact reassembly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
