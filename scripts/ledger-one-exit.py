#!/usr/bin/env python3
"""ledger-one-exit — migrate a brain's ledgers to one current `exit:` line per open entry; older exits become `was-exit:`.

The convention (operator decision 2026-11-06, CONVENTIONS via skill backlog-catch-up step 4) and its lint
(`ledger-reconcile.py`, finding `multi_exit`) name entries with more than one current exit; this script is the one-time
migration. Measured on the macOS instance the same day: 84 of 282 open entries carried 2-10 `exit:` lines (178 lines in
86 entries renamed); after the migration the pinned reader classified exactly like the fixed one.

The newest exit by date stays `exit:` (same date: the later line in the text); every other exit line of the entry is
renamed to `was-exit:` - text, order and indentation unchanged, so the history stays readable and no reader counts it.
Ticked entries are left as they are. Ledgers come from the brain's `.claude/rules/ledgers.json`.

    python3 core/scripts/ledger-one-exit.py [--root <brain>] [--write | --staged]

`--staged` is the pre-commit step (helpers/git-hooks/pre-commit): it judges only the registered ledgers the commit
stages, by their STAGED content, and never writes. Measured 2026-11-08 on the macOS instance: three entries with two
`exit:` lines went through three path commits on one ledger, because only ledger-reconcile.py (session start) knew the
convention; the operator the same day, translated: "exit vs was-exit apparently needs a mechanical safeguard".

Default is a preview. Exit 0 = nothing to change (or written), 1 = the preview found entries to change, 2 = no registry.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

EXIT = re.compile(r"^([\s>*-]*`?)exit:(\s*`?[\w-]+(?:\s+(\d{4}-\d{2}-\d{2}))?)")
# A prose line wrapped so that it starts with the field name in a code span ("  `exit: ask-operator` went through ...") is no
# field: in the field's code-span form the span runs to the end of the line. Measured 2026-11-08 on the macOS instance:
# two such prose lines were read as exits (one counted as a second exit, one as an unknown exit kind).
PROSE_SPAN = re.compile(r"^[\s>*-]*`exit:[^`\n]*`\s*\S")


def exit_match(line):
    return None if PROSE_SPAN.match(line) else EXIT.match(line)
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
        ex = [(k, m.group(3) or "") for k in range(a, b) for m in [exit_match(lines[k])] if m]
        if len(ex) < 2:
            continue
        keep = max(enumerate(ex), key=lambda ie: (ie[1][1], ie[0]))[1][0]
        for k, _ in ex:
            if k != keep:
                lines[k] = EXIT.sub(lambda m: m.group(1) + "was-exit:" + m.group(2), lines[k], count=1)
                n_lines += 1
        n_entries += 1
    return n_entries, n_lines


def known_exits():
    """The exit kinds the aggregator reads - its own set (open-items.py EXITS), never a second list here. None if unreadable."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("open_items", Path(__file__).resolve().parent / "open-items.py")
    try:
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return set(mod.EXITS)
    except Exception:  # noqa: BLE001 - a broken aggregator must not block every commit; the exit-kind check then stays off
        return None


def unknown_kinds(lines, kinds):
    """[(line number, kind)] of open entries whose current exit kind the aggregator does not know."""
    out = []
    for a, b in entries(lines):
        for k in range(a, b):
            m = exit_match(lines[k])
            if m:
                kind = m.group(2).strip().strip("`").split()[0]
                if kind not in kinds:
                    out.append((k + 1, kind))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".", help="the brain's root (default: the current directory)")
    ap.add_argument("--write", action="store_true", help="rewrite the ledgers (default: preview)")
    ap.add_argument("--staged", action="store_true",
                    help="pre-commit mode: judge only the registered ledgers this commit stages, by their staged content")
    a = ap.parse_args(argv)
    if a.staged and a.write:
        ap.error("--staged judges the index; it never writes")
    root = Path(a.root).resolve()
    reg = root / ".claude" / "rules" / "ledgers.json"
    try:
        ledgers = json.loads(reg.read_text(encoding="utf-8")).get("ledgers") or []
    except (OSError, ValueError) as e:
        print(f"ledger-one-exit: cannot read {reg.as_posix()}: {e}", file=sys.stderr)
        return 2
    staged = None
    if a.staged:
        r = subprocess.run(["git", "-C", str(root), "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
                           capture_output=True, text=True, encoding="utf-8")
        staged = set(r.stdout.splitlines()) if r.returncode == 0 else set()
    total_entries = total_lines = 0
    kinds = known_exits() if a.staged else None
    bad_kinds = []
    for rel in ledgers:
        p = root / rel
        if staged is not None:
            if rel not in staged:
                continue
            r = subprocess.run(["git", "-C", str(root), "show", f":{rel}"], capture_output=True, text=True, encoding="utf-8")
            if r.returncode != 0:
                continue
            lines = r.stdout.split("\n")
        elif not p.is_file():
            continue
        else:
            lines = p.read_text(encoding="utf-8").split("\n")
        if kinds:
            # Measured 2026-11-08 (macOS instance): `exit: ask-operator` went through a commit; only the session-start
            # aggregator said "unknown exit" a session later.
            bad_kinds += [(rel, n, k) for n, k in unknown_kinds(lines, kinds)]
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
    if a.staged and total_lines:
        print("An open entry carries ONE current exit: line; older ones are was-exit: (convention 2026-11-06). Fix and stage again:\n"
              f"  python3 {Path(__file__).resolve().as_posix()} --root {root.as_posix()} --write")
    for rel, n, k in bad_kinds:
        print(f"{rel}:{n}: unknown exit kind '{k}' - write one of {', '.join(sorted(kinds))} (skill backlog-catch-up)")
    if bad_kinds:
        return 1
    return 0 if (a.write or not total_lines) else 1


if __name__ == "__main__":
    sys.exit(main())
