#!/usr/bin/env python3
"""Fixture tests for scripts/live-doc-lint.py — both directions per detector discipline.

A row WITH the measurement state must stay silent (else every suite that adopts the field
goes red on its own compliance), a changed row WITHOUT it must be named (else the lint is
decoration), the backlog must be counted and never red (else the first consumer disables
it), and a repo without the opt-in must be silent. Builds a throwaway git repo per case.
"""
import json
import os
import subprocess
import sys
import tempfile

LINT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "live-doc-lint.py")
GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid",
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")

HEADER = "| Gotcha | Symptom | Fix | Beleg |\n|---|---|---|---|\n"
OK_ROW = "| store collapses | one colour | build fresh | 2026-10-24 · macOS onPC 2.5 · measured A/B/A |\n"
OLD_ROW = "| thru delete | illegal object | delete singly | showplan v3 |\n"
NEW_BARE = "| fader via cli | no move | use OSC | forum thread |\n"
NEW_ONCE = "| fader via cli | no move | use OSC | 2026-10-25 ; Windows onPC 2.5 ; measured once |\n"
NEW_DERIVED = "| at is physical | 75 means 75 deg | define percent | 2026-10-25 · vendor manual 2.5 · derived |\n"
NO_COL = "| # | Gotcha | Fix |\n|---|---|---|\n| L1 | clones render invisible | reimport |\n"


def git(d, *args):
    subprocess.run(["git", "-C", d, *args], check=True, capture_output=True, env=GIT_ENV)


def write(d, rel, text):
    p = os.path.join(d, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def repo(d, deps, files):
    git(d, "init", "-q", "-b", "main")
    write(d, "dependencies.json", json.dumps(deps))
    for rel, text in files.items():
        write(d, rel, text)
    git(d, "add", "-A")
    git(d, "commit", "-q", "-m", "base")


def run(d, *args):
    p = subprocess.run([sys.executable, LINT, "--repo", d, "--json", *args],
                       capture_output=True, text=True, encoding="utf-8")
    return p.returncode, json.loads(p.stdout)


DEPS = {"manifest_version": 1, "requires_core": ">=1.0.0", "dependencies": [],
        "live_docs": ["references/*.md"]}


def t_row_with_field_is_silent(d):
    repo(d, DEPS, {"references/g.md": HEADER + OK_ROW})
    write(d, "references/g.md", HEADER + OK_ROW + NEW_DERIVED)
    rc, r = run(d, "--changed", "HEAD")
    return rc == 0 and r["findings"] == 0 and r["files"][0]["with_field"] == 2, r


def t_new_row_without_field_is_named(d):
    repo(d, DEPS, {"references/g.md": HEADER + OK_ROW})
    write(d, "references/g.md", HEADER + OK_ROW + NEW_BARE)
    rc, r = run(d, "--changed", "HEAD")
    f = r["files"][0]["findings"]
    return (rc == 1 and len(f) == 1 and f[0]["line"] == 4
            and "measurement state" in f[0]["why"]), r


def t_old_row_without_field_is_counted_only(d):
    repo(d, DEPS, {"references/g.md": HEADER + OLD_ROW})
    write(d, "references/g.md", HEADER + OLD_ROW + NEW_ONCE)
    rc, r = run(d, "--changed", "HEAD")
    fr = r["files"][0]
    return rc == 0 and fr["without_field"] == 1 and fr["with_field"] == 1 and r["findings"] == 0, r


def t_edited_old_row_must_carry_field(d):
    repo(d, DEPS, {"references/g.md": HEADER + OLD_ROW})
    write(d, "references/g.md", HEADER + OLD_ROW.replace("delete singly", "delete one by one"))
    rc, r = run(d, "--changed", "HEAD")
    return rc == 1 and r["findings"] == 1, r


def t_new_file_every_row_changed(d):
    repo(d, DEPS, {"references/a.md": HEADER + OK_ROW})
    write(d, "references/b.md", HEADER + OLD_ROW + NEW_BARE)
    rc, r = run(d, "--changed", "HEAD")
    b = [f for f in r["files"] if f["file"] == "references/b.md"][0]
    return rc == 1 and len(b["findings"]) == 2, r


def t_table_without_evidence_column(d):
    repo(d, DEPS, {"references/g.md": HEADER + OK_ROW})
    write(d, "references/g.md", HEADER + OK_ROW + "\n" + NO_COL)
    rc, r = run(d, "--changed", "HEAD")
    fr = r["files"][0]
    return (rc == 1 and fr["tables_without_evidence_column"] == 1
            and "no evidence column" in fr["findings"][0]["why"]), r


def t_report_mode_never_red(d):
    repo(d, DEPS, {"references/g.md": HEADER + OLD_ROW + NEW_BARE})
    rc, r = run(d)
    fr = r["files"][0]
    return rc == 0 and r["mode"] == "report" and fr["without_field"] == 2 and r["findings"] == 0, r


def t_no_opt_in_is_silent(d):
    repo(d, {k: v for k, v in DEPS.items() if k != "live_docs"},
         {"references/g.md": HEADER + NEW_BARE})
    rc, r = run(d, "--changed", "HEAD")
    return rc == 0 and r["live_docs"] is False and "no live_docs" in r["why"], r


def t_bad_opt_in_is_named(d):
    repo(d, dict(DEPS, live_docs="references/g.md"), {"references/g.md": HEADER + NEW_BARE})
    rc, r = run(d, "--changed", "HEAD")
    return rc == 0 and r["live_docs"] is False and "list" in r["why"], r


def t_field_vocabulary_is_strict(d):
    # a date and a source alone are no method; a method alone is no date — both stay findings
    repo(d, DEPS, {"references/g.md": HEADER + OK_ROW})
    write(d, "references/g.md", HEADER + OK_ROW
          + "| a | b | c | 2026-10-25 · macOS onPC |\n"
          + "| d | e | f | measured A/B/A |\n"
          + "| g | h | i | 2026-10-25 · macOS onPC · verified |\n")
    rc, r = run(d, "--changed", "HEAD")
    return rc == 1 and r["findings"] == 3, r


def t_escaped_pipe_stays_in_cell(d):
    repo(d, DEPS, {"references/g.md": HEADER + OK_ROW})
    write(d, "references/g.md", HEADER + OK_ROW
          + "| `addfix:6\\|\\|101` | crash | loop it | 2026-08-17 · Windows onPC 2.0 · measured once |\n")
    rc, r = run(d, "--changed", "HEAD")
    return rc == 0 and r["files"][0]["with_field"] == 2, r


CASES = [
    ("row with the field stays silent", t_row_with_field_is_silent),
    ("new row without the field is named, exit 1", t_new_row_without_field_is_named),
    ("old row without the field is counted, not red", t_old_row_without_field_is_counted_only),
    ("an edited old row must carry the field", t_edited_old_row_must_carry_field),
    ("a new file: every row is a changed row", t_new_file_every_row_changed),
    ("a table without an evidence column is a finding on its changed rows", t_table_without_evidence_column),
    ("report mode counts the backlog and is never red", t_report_mode_never_red),
    ("no live_docs opt-in: silent", t_no_opt_in_is_silent),
    ("live_docs that is not a list: named, not crashed", t_bad_opt_in_is_named),
    ("field vocabulary is strict: partial fields are findings", t_field_vocabulary_is_strict),
    ("escaped pipe inside a cell does not split the row", t_escaped_pipe_stays_in_cell),
]


def main():
    bad = 0
    for title, fn in CASES:
        with tempfile.TemporaryDirectory() as d:
            try:
                ok, detail = fn(d)
            except Exception as e:  # a crash is a failure with its reason, not a traceback
                ok, detail = False, repr(e)
        print(("ok    " if ok else "FAIL  ") + title + ("" if ok else f" -- {detail}"))
        bad += 0 if ok else 1
    print(f"live-doc-lint-test: {len(CASES) - bad}/{len(CASES)} ok")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
