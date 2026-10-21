#!/usr/bin/env python3
"""backprop-report.py — a new dated rule is written; which OLD places say something about the same thing?

WHY (Windows coherence register 2026-10-19): six of its 23 findings were repeats of the register
four days earlier. Every time the shape was the same: a new dated rule went into the instance's
feedback file, and the older places that said the opposite were not marked superseded — the
rule-conflict protocol step 2 ("grep the old spots and mark them superseded in the same pass")
was followed from memory, and memory searched too narrowly. Agreed with the macOS instance as a
REPORT, not a gate: a gate would fire on synonyms and prose, and judging an old place takes a
look, not a block. Built on the operator's word 2026-10-21.

What it does: reads the ADDED lines of the rule files in `git diff <since>` (default: everything
not yet committed, staged or not), keeps the ones that carry a date (YYYY-MM-DD) — a dated rule —
and takes their marked terms: `backticked`, **bold**, and quoted ("…", „…“). Each term is searched,
case-insensitive and literal, over the search paths; every hit outside the new lines themselves is
listed with file:line, at most --max per term. The writer reads the list and marks what the new
rule supersedes (rule-conflict protocol step 2) — this script decides nothing.

Instance data `.claude/rules/backprop.json` {"rule_files": [...], "search": [...]} — paths relative
to the repo; defaults below fit a brain (instance feedback file, its rules, the core's rules and
skills, CLAUDE.md). Inside the core repo pass the files and paths on the command line.

Usage: backprop-report.py [--root DIR] [--since REV] [--max N] [--search PATH ...] [rule_file ...]
Exit 0 always (a report).
"""
import argparse
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

DEFAULT_RULE_FILES = [".claude/rules/feedback.md"]
DEFAULT_SEARCH = ["CLAUDE.md", ".claude/rules", "core/rules", "core/skills", "core/docs"]
DATE = re.compile(r"\b20\d\d-\d\d-\d\d\b")
TERMS = re.compile(r"`([^`\n]{3,80})`|\*\*([^*\n]{3,80})\*\*|\"([^\"\n]{3,80})\"|„([^“”\"\n]{3,80})[“”\"]")
EXTS = (".md", ".json", ".cjs", ".js", ".py", ".sh")


def git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, encoding="utf-8")
    return r.stdout if r.returncode == 0 else ""


def added_dated_lines(root, since, files):
    """[(file, line text)] for added lines that carry a date."""
    out = []
    for f in files:
        diff = git(root, "diff", "--unified=0", since, "--", f)
        if not diff and since == "HEAD":  # a file not yet tracked at all
            if f in git(root, "ls-files", "--others", "--exclude-standard", "--", f).split():
                diff = "".join("+" + ln + "\n" for ln in open(os.path.join(root, f), encoding="utf-8"))
        for ln in diff.splitlines():
            if ln.startswith("+") and not ln.startswith("+++") and DATE.search(ln):
                out.append((f, ln[1:].strip()))
    return out


def terms_of(line):
    seen = []
    for m in TERMS.finditer(line):
        t = next(g for g in m.groups() if g).strip()
        if len(t) >= 3 and not DATE.fullmatch(t) and t.lower() not in (x.lower() for x in seen):
            seen.append(t)
    return seen


def walk(root, paths):
    for p in paths:
        full = os.path.join(root, p)
        if os.path.isfile(full):
            yield p
        elif os.path.isdir(full):
            for d, dirs, files in os.walk(full):
                dirs[:] = [x for x in dirs if not x.startswith(".git") and x != "node_modules"]
                for name in files:
                    if name.endswith(EXTS):
                        yield os.path.relpath(os.path.join(d, name), root).replace(os.sep, "/")


def search(root, paths, term, skip, cap):
    hits, low = [], term.lower()
    for rel in walk(root, paths):
        try:
            with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
                for n, text in enumerate(fh, 1):
                    if low in text.lower() and text.strip() not in skip:
                        hits.append(f"{rel}:{n}")
                        if len(hits) >= cap:
                            return hits
        except OSError:
            continue
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--since", default="HEAD")
    ap.add_argument("--max", type=int, default=8)
    ap.add_argument("--search", action="append", help="a path to search (repeatable)")
    ap.add_argument("rule_files", nargs="*")
    a = ap.parse_args()
    cfg = {}
    try:
        with open(os.path.join(a.root, ".claude", "rules", "backprop.json"), encoding="utf-8") as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        pass
    files = a.rule_files or cfg.get("rule_files") or DEFAULT_RULE_FILES
    paths = a.search or cfg.get("search") or DEFAULT_SEARCH
    lines = added_dated_lines(a.root, a.since, files)
    if not lines:
        print(f"backprop: no new dated rule line in {', '.join(files)} since {a.since}")
        return 0
    skip = {t for _, t in lines}
    total = 0
    for f, text in lines:
        terms = terms_of(text)
        print(f"NEW {f}: {text[:140]}")
        if not terms:
            print("  (no marked term — mark the load-bearing words with `…`, **…** or quotes, or search by hand)")
            continue
        for t in terms:
            hits = search(a.root, paths, t, skip, a.max)
            total += len(hits)
            print(f"  {t!r}: " + (", ".join(hits) + (" …" if len(hits) >= a.max else "") if hits else "no other place"))
    print(f"backprop summary: new={len(lines)} places={total} — read each, mark what the new rule supersedes "
          "(rule-conflict protocol step 2)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
