#!/usr/bin/env python3
"""dead-carriers.py — does every carrier a brain's rules name exist?

WHY (coherence scan on the macOS instance, 2026-10-15, confirmed in a second round): the
instance's rules named carriers that were not there — a disabled plugin, sub-skills of an
uninstalled pack, a script in a repo that never had it, symlinks that had been removed. A rule
that points at a missing carrier reads as carried and is carried by nothing. The operator
ordered a check for it on 2026-10-28 (report only, no fix; it runs in the brain-scan).

What it reads: the brain's CLAUDE.md and every `.claude/rules/*.md`. What it checks:
  * a path in backticks that starts with a brain folder (core/, scripts/, docs/, config/,
    .claude/, src/) or `~/` — the file or folder exists;
  * a core skill named as `brain-core:<name>` — `core/skills/<name>/` exists.
Skipped on purpose: globs and placeholders (`*`, `<`, `{`, `$`), and paths inside a line that
says the thing is gone (removed, deleted, archived; other languages as instance data) — those name
an absence.

Output: one line per missing carrier, `dead carrier: <file>:<line> names <x>`, then
`dead-carriers summary: <n> named, <m> missing`. Exit 0 (a report, not a gate).
"""
import argparse
import os
import pathlib
import re
import sys

PATH_RX = re.compile(r"`((?:core|scripts|docs|config|src|\.claude)/[^`\s]+|~/[^`\s]+)`")
SKILL_RX = re.compile(r"\bbrain-core:([a-z0-9][a-z0-9-]*)")
SKIP = re.compile(r"[*<>{}$|]")
# Absence words: English built-ins; an instance adds its language as data
# (.claude/rules/dead-carriers.json {"absence_patterns": [...]}), the core stays English.
GONE_BUILTIN = [r"\b(removed|deleted|archived|unwired|does not exist|not yet created)\b"]


def gone_rx(repo):
    pats = list(GONE_BUILTIN)
    try:
        import json
        extra = json.loads((repo / ".claude" / "rules" / "dead-carriers.json").read_text(encoding="utf-8"))
        for p in extra.get("absence_patterns") or []:
            try:
                re.compile(p)
                pats.append(p)
            except re.error:
                pass
    except (OSError, ValueError):
        pass
    return re.compile("|".join(pats), re.I)
# A relative path in a line that names another repo (`~/Projects/<repo>`) may live in that repo.
REPO_RX = re.compile(r"~/Projects/([\w.-]+)")


def targets(path, gone):
    for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if gone.search(line):
            continue
        roots = [pathlib.Path(os.path.expanduser(f"~/Projects/{r}")) for r in REPO_RX.findall(line)]
        for m in PATH_RX.finditer(line):
            p = m.group(1).rstrip(".,;:)")
            p = re.sub(r":\d+(-\d+)?$", "", p)  # file:line references
            if not SKIP.search(p):
                yield n, "path", p, roots
        for m in SKILL_RX.finditer(line):
            yield n, "skill", m.group(1), []


def exists(repo, kind, x, roots):
    if kind == "skill":
        return (repo / "core" / "skills" / x).is_dir()
    if x.startswith("~/"):
        return pathlib.Path(os.path.expanduser(x)).exists()
    return any((r / x).exists() for r in [repo, *roots])


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    repo = pathlib.Path(a.repo)
    files = [repo / "CLAUDE.md"] + sorted((repo / ".claude" / "rules").glob("*.md"))
    named = missing = 0
    seen = set()
    gone = gone_rx(repo)
    for f in files:
        if not f.is_file():
            continue
        for n, kind, x, roots in targets(f, gone):
            if (kind, x) in seen:
                continue
            seen.add((kind, x))
            named += 1
            if not exists(repo, kind, x, roots):
                missing += 1
                shown = f"brain-core:{x}" if kind == "skill" else x
                print(f"dead carrier: {f.relative_to(repo).as_posix()}:{n} names {shown}")
    print(f"dead-carriers summary: {named} named, {missing} missing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
