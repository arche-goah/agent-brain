#!/usr/bin/env python3
"""Replay the core's readers on REAL brain data: old version against new, before a release.

WHY (operator decision 2026-11-06): fixes kept "not holding" after a release because every
reader was verified against synthetic fixtures only. Measured: open-items.py took a ledger
entry's LAST exit line; on the operator's real ledgers 4 of 7 "needs you" items were false,
and no fixture had an entry with several exit lines. A replay of the old and the new reader
over the real ledgers showed it in seconds (7 -> 1). Nothing in the release preflight ran
anything on real data.

What it does:
  * for every reader in real-data-readers.json (name, argv with {core} and {brain}, optional
    normalise regexes): run it once from a checkout of --base (a git worktree in a temp dir,
    removed after) and once from HEAD (this checkout, or --head <ref>), each over a FRESH copy
    of the real brain (a reader may write its state into the brain; the real one is never
    touched, and the second run never sees the first run's state). The outputs are
    normalised (volatile parts: the copy paths, counters, timestamps - regexes in the data
    file) and diffed. A difference is printed as a unified diff, capped.
  * every changelog fragment (changelog.d/*.md, and with --changelog-section X.Y.Z that
    section of CHANGELOG.md, where the fragments stand after the release cut) may carry a
    line `symptom: <command>` - a command that reproduced the bug on real data and must now
    exit 0. It runs at HEAD with {brain}/{core} substituted; a failing symptom is a finding.

Exit 0 = no difference, every symptom holds; 1 = differences or a failing symptom (printed);
2 = could not run (no brain, bad ref, unreadable data, a reader that timed out).

Usage: real-data-replay.py --brain DIR [--base REF] [--head REF] [--core DIR]
                           [--readers FILE] [--changelog-section X.Y.Z] [--max-diff N]
--brain defaults to $RELEASE_REPLAY_BRAIN. Without --base only the symptoms run.
Stdlib only; Python 3.9+.
"""
import argparse
import difflib
import fnmatch
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SYMPTOM = re.compile(r"^\s*(?:[-*]\s+)?symptom:\s*(.+?)\s*$", re.M)
# changelog-assemble.py appends `<!-- fragment: <slug> -->` to a fragment's last line: never part of the command
MARKER = re.compile(r"\s*<!-- fragment: [\w.-]+ -->\s*$")  # exactly the marker, no general comment filter


def run_git(core, *args):
    return subprocess.run(["git", "-C", str(core), *args], capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def copy_brain(src, dst, ignore):
    def skip(_dir, names):
        return {n for n in names if any(fnmatch.fnmatch(n, pat) for pat in ignore)}
    # symlinks stay links: a brain links into suites; following them would copy the suites
    shutil.copytree(src, dst, symlinks=True, ignore=skip)


def argv_for(argv, core, brain):
    out = [a.replace("{core}", str(core)).replace("{brain}", str(brain)) for a in argv]
    if out and out[0] in ("python3", "python"):
        out[0] = sys.executable  # OS-17: python3 may be the Store stub on Windows
    return out


def run_reader(argv, core, brain, timeout):
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(brain), PYTHONIOENCODING="utf-8")
    try:
        p = subprocess.run(argv_for(argv, core, brain), cwd=str(brain), capture_output=True,
                           text=True, encoding="utf-8", errors="replace", env=env, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    except OSError as e:
        return f"[could not start: {e}]\n"
    return p.stdout + (f"[stderr]\n{p.stderr}" if p.stderr.strip() else "") + f"[exit {p.returncode}]\n"


def normalise(text, core, brain, regexes):
    text = text.replace(str(brain), "{brain}").replace(str(core), "{core}")
    lines = []
    for line in text.splitlines():
        for rx in regexes:
            line = rx.sub("", line)
        lines.append(line.rstrip())
    return lines


def symptoms(core, section):
    found = []
    d = core / "changelog.d"
    for p in sorted(d.glob("*.md")) if d.is_dir() else []:
        if p.name.lower() != "readme.md":
            found += [(p.stem, MARKER.sub("", c)) for c in SYMPTOM.findall(p.read_text(encoding="utf-8"))]
    if section:
        try:
            text = (core / "CHANGELOG.md").read_text(encoding="utf-8")
        except OSError:
            text = ""
        m = re.search(rf"^## {re.escape(section)}( [^\n]*)?\n(.*?)(?=^## |\Z)", text, re.M | re.S)
        if m:
            found += [(f"CHANGELOG {section}", MARKER.sub("", c)) for c in SYMPTOM.findall(m.group(2))]
    return found


def main():
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: the preflight reads this
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--brain", default=os.environ.get("RELEASE_REPLAY_BRAIN", ""))
    ap.add_argument("--base", default="")
    ap.add_argument("--head", default="", help="a ref instead of the --core checkout itself")
    ap.add_argument("--core", default=str(HERE.parent))
    ap.add_argument("--readers", default=str(HERE / "real-data-readers.json"))
    ap.add_argument("--changelog-section", default="")
    ap.add_argument("--max-diff", type=int, default=80, help="diff lines shown per reader")
    ap.add_argument("--timeout", type=float, default=300)
    a = ap.parse_args()

    brain = pathlib.Path(a.brain) if a.brain else None
    if not brain or not brain.is_dir():
        print(f"real-data-replay: NOT run - no real brain ({a.brain or 'none given'}; set --brain or RELEASE_REPLAY_BRAIN)")
        return 2
    core = pathlib.Path(a.core).resolve()
    try:
        data = json.loads(pathlib.Path(a.readers).read_text(encoding="utf-8"))
        readers = data["readers"]
        glob_rx = [re.compile(r) for r in data.get("normalise", [])]
        per_rx = {r["name"]: [re.compile(x) for x in r.get("normalise", [])] for r in readers}
        ignore = data.get("brain_copy_ignore", [".git"])
    except (OSError, ValueError, KeyError, TypeError, re.error) as e:
        print(f"real-data-replay: NOT run - reader list {a.readers} unreadable: {e}")
        return 2

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="real-data-replay-")).resolve()
    worktrees = []
    findings, broken = 0, 0
    try:
        def checkout(ref, name):
            wt = tmp / name
            r = run_git(core, "worktree", "add", "--quiet", "--detach", str(wt), ref)
            if r.returncode != 0:
                return None, r.stderr.strip()
            worktrees.append(wt)
            return wt, ""

        head_core = core
        if a.head:
            head_core, err = checkout(a.head, "head")
            if head_core is None:
                print(f"real-data-replay: NOT run - head ref {a.head} not checked out: {err}")
                return 2
        if a.base:
            base_core, err = checkout(a.base, "base")
            if base_core is None:
                print(f"real-data-replay: NOT run - base ref {a.base} not checked out: {err}")
                return 2
            print(f"replay: {len(readers)} reader(s), base {a.base} vs {a.head or 'HEAD'}, real brain {brain.name}")
            for i, rd in enumerate(readers):
                outs = []
                for side, c in (("base", base_core), ("head", head_core)):
                    copy = tmp / f"brain-{i}-{side}"
                    copy_brain(brain, copy, ignore)
                    out = run_reader(rd["argv"], c, copy, a.timeout)
                    outs.append(None if out is None else normalise(out, c, copy, glob_rx + per_rx[rd["name"]]))
                    shutil.rmtree(copy, ignore_errors=True)
                if None in outs:
                    broken += 1
                    print(f"NOT RUN  {rd['name']}: timed out after {a.timeout:g} s")
                    continue
                diff = list(difflib.unified_diff(outs[0], outs[1], f"{rd['name']}@{a.base}",
                                                 f"{rd['name']}@{a.head or 'HEAD'}", lineterm="", n=1))
                if not diff:
                    print(f"SAME     {rd['name']} ({len(outs[1])} lines)")
                    continue
                findings += 1
                changed = sum(1 for l in diff if l[:1] in "+-" and l[:3] not in ("+++", "---"))
                print(f"DIFFERS  {rd['name']}: {changed} changed line(s)")
                for line in diff[:a.max_diff]:
                    print(f"  {line}")
                if len(diff) > a.max_diff:
                    print(f"  ... {len(diff) - a.max_diff} more diff line(s) (--max-diff)")
        else:
            print("replay: no --base given - readers not replayed, symptoms only")

        sy = symptoms(head_core, a.changelog_section)
        for src, cmd in sy:
            copy = tmp / "brain-symptom"
            copy_brain(brain, copy, ignore)
            try:
                argv = shlex.split(cmd)
            except ValueError as e:
                argv = None
                out, rc = str(e), -1
            if argv:
                p = run_reader(argv, head_core, copy, a.timeout)
                m = re.search(r"\[exit (-?\d+)\]\n$", p or "")
                rc = int(m.group(1)) if m else -1
                out = p or "timed out"
            shutil.rmtree(copy, ignore_errors=True)
            if rc == 0:
                print(f"HOLDS    symptom of {src}: {cmd}")
            else:
                findings += 1
                print(f"FAILS    symptom of {src} (rc={rc}): {cmd}")
                for line in out.splitlines()[-10:]:
                    print(f"  | {line}")
        if sy or a.changelog_section or not a.base:
            print(f"symptoms: {len(sy)} line(s) found")
    finally:
        for wt in worktrees:
            run_git(core, "worktree", "remove", "--force", str(wt))
        run_git(core, "worktree", "prune")
        shutil.rmtree(tmp, ignore_errors=True)

    if broken:
        print(f"real-data-replay: {broken} reader(s) could not run")
        return 2
    print(f"real-data-replay: {'no difference' if not findings else f'{findings} finding(s)'}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
