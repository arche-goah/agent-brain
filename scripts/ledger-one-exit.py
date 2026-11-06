#!/usr/bin/env python3
"""ledger-one-exit — migrate a brain's ledgers to one current `exit:` line per open entry; older exits become `was-exit:`.

The convention (operator decision 2026-11-06, CONVENTIONS via skill backlog-catch-up step 4) and its lint
(`ledger-reconcile.py`, finding `multi_exit`) name entries with more than one current exit; this script is the one-time
migration. Measured on the macOS instance the same day: 84 of 282 open entries carried 2-10 `exit:` lines (178 lines in
86 entries renamed); after the migration the pinned reader classified exactly like the fixed one.

The newest exit by date stays `exit:` (same date: the later line in the text); every other exit line of the entry is
renamed to `was-exit:` - text, order and indentation unchanged, so the history stays readable and no reader counts it.
Ticked entries are left as they are. Ledgers come from the brain's `.claude/rules/ledgers.json`.

    python3 core/scripts/ledger-one-exit.py [--root <brain>] [--write]

Default is a preview. Exit 0 = nothing to change (or written), 1 = the preview found entries to change, 2 = no registry.
"""
import argparse
import json
import re
import sys
from pathlib import Path

EXIT = re.compile(r"^([\s>*-]*`?)exit:(\s*`?[\w-]+(?:\s+(\d{4}-\d{2}-\d{2}))?)")
ENTRY = re.compile(r"^- \[[ xX]\] ")


def entries(lines):
    """(start, end) line ranges of open `- [ ]` entries."""
    i = 0
    while i < len(lines):
        if lines[i].startswith("- [ ]"):
            j = i + 1
            while j < len(lines) and not ENTRY.match(lines[j]) and not lines[j].startswith("#"):
                j += 1
            yield i, j
            i = j
        else:
            i += 1


def migrate(lines):
    """Rewrite in place; return (entries changed, lines renamed)."""
    n_entries = n_lines = 0
    for a, b in entries(lines):
        ex = [(k, m.group(3) or "") for k in range(a, b) for m in [EXIT.match(lines[k])] if m]
        if len(ex) < 2:
            continue
        keep = max(enumerate(ex), key=lambda ie: (ie[1][1], ie[0]))[1][0]
        for k, _ in ex:
            if k != keep:
                lines[k] = EXIT.sub(lambda m: m.group(1) + "was-exit:" + m.group(2), lines[k], count=1)
                n_lines += 1
        n_entries += 1
    return n_entries, n_lines


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".", help="the brain's root (default: the current directory)")
    ap.add_argument("--write", action="store_true", help="rewrite the ledgers (default: preview)")
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    reg = root / ".claude" / "rules" / "ledgers.json"
    try:
        ledgers = json.loads(reg.read_text(encoding="utf-8")).get("ledgers") or []
    except (OSError, ValueError) as e:
        print(f"ledger-one-exit: cannot read {reg.as_posix()}: {e}", file=sys.stderr)
        return 2
    total_entries = total_lines = 0
    for rel in ledgers:
        p = root / rel
        if not p.is_file():
            continue
        lines = p.read_text(encoding="utf-8").split("\n")
        n_entries, n_lines = migrate(lines)
        if n_lines:
            total_entries += n_entries
            total_lines += n_lines
            print(f"{rel}: {n_lines} exit line(s) in {n_entries} entr(y/ies) -> was-exit:")
            if a.write:
                # newline="\n": the lines were split on \n, so a CRLF file keeps its \r and an LF file stays LF -
                # Windows text mode would otherwise turn every \n into \r\n (docs/os-traps.md OS-2).
                with open(p, "w", encoding="utf-8", newline="\n") as f:
                    f.write("\n".join(lines))
    print(f"ledger-one-exit: {total_entries} entr(y/ies), {total_lines} line(s) {'rewritten' if a.write else 'to rewrite'}")
    return 0 if (a.write or not total_lines) else 1


if __name__ == "__main__":
    sys.exit(main())
