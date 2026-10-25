#!/usr/bin/env python3
"""Live-doc lint: every documented live-behaviour row carries its measurement state.

WHY (measured 2026-10-24, retroactive review run over 188 merged collaborator PRs): 21 of
35 desk-behaviour rows were merged without a counter-measurement, three of them refuted
later by their own author. A row that documents how a live tool (a desk, TouchDesigner, a
network device) behaves carried no hint of HOW it came about — observed once, measured with
a negative control, or taken from docs or a forum. The reviewer could not see what to
re-measure and merged on plausibility. No test covers it: live documentation has no test.

THE FIELD (rules/thinking-protocol.md, evidence chain): the evidence cell of a table row
reads like the claim block — date · source · method:

    2026-10-24 · macOS onPC 2.5 · measured A/B/A
    2026-10-24 · Windows onPC 2.5 · measured once
    2026-09-03 · vendor manual 2.5 · derived
    2026-08-17 · forum thread · assumed

  date    YYYY-MM-DD, the day of the measurement or the reading
  source  the machine or tool, so that the row can be repeated (free text, no separator)
  method  measured A/B/A (cause removed, effect gone, cause back) · measured once ·
          derived (from docs, code, a vendor manual) · assumed
Separator: ` · ` (middle dot) or ` ; `. A row without the field reads as `assumed` for the
reader of the rule — the lint names it so the author writes what the reader would otherwise
guess (identity is written, state is read: the producer writes it, the reader never rebuilds it).

OPT-IN per suite, in the existing contract file: `dependencies.json` key `live_docs` — a list
of repo-relative paths or globs (core-contract.json `dependencies_optional_fields`). A repo
without the key is silent (exit 0, one line). Only the EVIDENCE column is checked — the table
header names it (`Beleg`, `Evidence`, `Measured`, `Source`; case-insensitive). A table in a
live doc without such a column cannot carry the field at all: its changed rows are findings.

MODES
  live-doc-lint.py [--repo DIR]              report every file: rows total · with field ·
                                             without; exit 0 (the backlog number, never red)
  live-doc-lint.py --changed <base-ref>      rows the diff against <base-ref> ADDS or CHANGES
                                             must carry the field; old rows are counted only.
                                             Exit 1 on a changed row without it. Built for CI
                                             (`--changed origin/<base>` in a pull request).
  --json                                     machine-readable report (fixtures)

Backlog is counted, not failed: the first consumer brings 181 old rows, and a lint that
turns a repo red for its history gets disabled within the hour. The ratchet is the diff.
Python 3.9 floor (OS-13); stdlib only; paths leave as posix (OS-1); stdout pinned (OS-9).
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

EVIDENCE_HEADERS = re.compile(r"^\s*(beleg|evidence|measured|measurement|source)\b", re.I)
SEP = r"\s*[·;]\s*"
FIELD = re.compile(
    r"(?P<date>\d{4}-\d{2}-\d{2})" + SEP
    + r"(?P<source>[^·;|]+?)" + SEP
    + r"(?P<method>measured\s+(A/B/A|once)|derived|assumed)\b",
    re.I,
)
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def split_row(line):
    """Cells of a markdown table row; escaped pipes (`\\|`) stay inside their cell."""
    body = line.strip()
    if body.startswith("|"):
        body = body[1:]
    if body.endswith("|") and not body.endswith("\\|"):
        body = body[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", body)]


def is_separator(cells):
    return all(re.fullmatch(r":?-{3,}:?", c) for c in cells if c) and any(cells)


def tables(lines):
    """Yield (header_cells, evidence_col or None, [(lineno, cells), ...]) per table."""
    i, n = 0, len(lines)
    while i < n:
        if not lines[i].lstrip().startswith("|"):
            i += 1
            continue
        start = i
        while i < n and lines[i].lstrip().startswith("|"):
            i += 1
        block = lines[start:i]
        if len(block) < 2:
            continue
        header = split_row(block[0])
        if not is_separator(split_row(block[1])):
            continue
        col = next((k for k, h in enumerate(header) if EVIDENCE_HEADERS.search(h)), None)
        rows = [(start + 1 + k, split_row(ln)) for k, ln in enumerate(block[2:], start=2)]
        yield header, col, rows


def has_field(cell):
    return bool(FIELD.search(cell))


def changed_lines(repo, base, rel):
    """New-file line numbers the diff base..worktree adds or changes; None = file not in base."""
    try:
        in_base = subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{base}:{rel}"],
                                 capture_output=True).returncode == 0
    except OSError:
        return None
    if not in_base:
        return None
    out = subprocess.run(["git", "-C", repo, "diff", "--no-color", "-U0", base, "--", rel],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    lines = set()
    for ln in out.splitlines():
        m = HUNK.match(ln)
        if m:
            at = int(m.group(1))
            cnt = int(m.group(2)) if m.group(2) is not None else 1
            lines.update(range(at, at + cnt))
    return lines


def live_docs(repo):
    try:
        with open(os.path.join(repo, "dependencies.json"), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None, "dependencies.json missing or unreadable"
    spec = data.get("live_docs")
    if spec is None:
        return None, "no live_docs declared"
    if not isinstance(spec, list) or not all(isinstance(s, str) for s in spec):
        return None, "live_docs must be a list of paths or globs"
    files = []
    for pat in spec:
        hits = sorted(glob.glob(os.path.join(repo, pat), recursive=True))
        files.extend(h for h in hits if os.path.isfile(h))
    rel = sorted({os.path.relpath(f, repo).replace(os.sep, "/") for f in files})
    return rel, None


def lint_file(repo, rel, changed):
    """changed: None = every row counts as old (report mode); set() of line numbers otherwise;
    the string 'all' = file is new in the diff, every row is changed."""
    with open(os.path.join(repo, rel), encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    rep = {"file": rel, "rows": 0, "with_field": 0, "without_field": 0,
           "tables_without_evidence_column": 0, "findings": []}
    for header, col, rows in tables(lines):
        if col is None:
            rep["tables_without_evidence_column"] += 1
        for lineno, cells in rows:
            rep["rows"] += 1
            ok = col is not None and col < len(cells) and has_field(cells[col])
            if ok:
                rep["with_field"] += 1
                continue
            rep["without_field"] += 1
            is_changed = changed == "all" or (isinstance(changed, set) and lineno in changed)
            if is_changed:
                why = ("table has no evidence column (Beleg/Evidence/Measured/Source)"
                       if col is None else "evidence cell without measurement state")
                rep["findings"].append({"line": lineno, "why": why,
                                        "row": cells[0][:60] if cells else ""})
    return rep


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", default=".", help="repo root (default: cwd)")
    ap.add_argument("--changed", metavar="BASE_REF",
                    help="only rows the diff against BASE_REF adds or changes must carry the field")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)

    files, why = live_docs(repo)
    if files is None:
        out = {"live_docs": False, "why": why, "files": []}
        print(json.dumps(out) if a.json else f"live-doc-lint: {why} — nothing to check")
        return 0

    reports = []
    for rel in files:
        changed = None
        if a.changed:
            ch = changed_lines(repo, a.changed, rel)
            changed = "all" if ch is None else ch
        reports.append(lint_file(repo, rel, changed))

    findings = sum(len(r["findings"]) for r in reports)
    if a.json:
        print(json.dumps({"live_docs": True, "mode": "changed" if a.changed else "report",
                          "base": a.changed, "files": reports, "findings": findings}))
    else:
        for r in reports:
            print(f"{r['file']}: {r['rows']} rows, {r['with_field']} with measurement state, "
                  f"{r['without_field']} without"
                  + (f", {r['tables_without_evidence_column']} table(s) without evidence column"
                     if r["tables_without_evidence_column"] else ""))
            for f in r["findings"]:
                print(f"  !! {r['file']}:{f['line']} — {f['why']}: {f['row']}")
        if a.changed:
            print(f"live-doc-lint: {findings} changed row(s) without measurement state"
                  + (" — write `<YYYY-MM-DD> · <machine or tool> · measured A/B/A|measured once|"
                     "derived|assumed` into the evidence cell" if findings else ""))
        else:
            print("live-doc-lint: report only (backlog); use --changed <base-ref> to gate a diff")
    return 1 if (a.changed and findings) else 0


if __name__ == "__main__":
    sys.exit(main())
