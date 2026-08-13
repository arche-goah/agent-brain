#!/usr/bin/env python3
"""Suite contract check — does this repo still fit the core it claims to fit?

WHY this exists: the conventions document has said since 2026-08-03 that every suite
carries semver, a changelog and a declared core version. Measured the same day across
four suites: zero tags, zero changelogs, zero declarations. A rule nobody can run is a
rule that has already drifted — especially with two people working in parallel.

Two ways to run it, deliberately the same code:
  scripts/suite-check.py <path>...     from the brain, over the suites it mounts
  python3 suite-check.py .             inside a suite's own CI, before anything merges

Read-only, stdlib, no network. Exit 0 = every suite passes, 1 = at least one error.

Findings are graded:
  ERROR   breaks compatibility with this core — blocks
  WARN    contract asks for it, absence is survivable for now
  INFO    observation, no obligation
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent
# Contract lives at the core repo root; config/ is the pre-split brain layout (fallback).
_candidates = [CORE / "core-contract.json", CORE / "config" / "core-contract.json"]
CONTRACT_PATH = next((p for p in _candidates if p.exists()), _candidates[0])

HOME_PATH = re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")
ALLOWED_HOME = re.compile(r"^/Users/Shared\b")
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv"}
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".ico", ".lock",
               ".woff", ".woff2", ".ttf", ".mp4", ".mov", ".wav"}


def parse_version(text):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", str(text).strip())
    return tuple(int(g) for g in m.groups()) if m else None


def satisfies(core, spec):
    """Minimal range check: '>=1.2.0', '1.2.0', or '*'. Anything else is a finding."""
    spec = str(spec).strip()
    if spec == "*":
        return True, None
    m = re.match(r"^(>=|==|=)?\s*(\d+\.\d+\.\d+)$", spec)
    if not m:
        return False, f"cannot read requires_core {spec!r} — use '>=X.Y.Z', 'X.Y.Z' or '*'"
    op, want = m.group(1) or "==", parse_version(m.group(2))
    if op == ">=":
        # A major bump is breaking by definition, so >= does not cross it.
        ok = core >= want and core[0] == want[0]
        return ok, None if ok else (
            f"needs core {spec}, this core is {'.'.join(map(str, core))}"
            + (" (major differs — breaking by definition)" if core[0] != want[0] else ""))
    ok = core == want
    return ok, None if ok else f"pinned to core {spec}, this core is {'.'.join(map(str, core))}"


def tracked_files(repo: Path):
    """git ls-files, so untracked scratch and ignored instance data are out of scope."""
    try:
        out = subprocess.run(["git", "-C", str(repo), "ls-files", "-z"],
                             capture_output=True, text=True, timeout=30)
        if out.returncode == 0:
            return [repo / p for p in out.stdout.split("\0") if p]
    except (OSError, subprocess.SubprocessError):
        pass
    return [p for p in repo.rglob("*")
            if p.is_file() and not any(d in p.parts for d in SKIP_DIRS)]


def workflow_trigger_findings(text):
    """Findings for one workflow file: unfiltered push triggers, expensive runners.

    Text heuristics on purpose — stdlib has no YAML parser, and a linter that needs
    pip install would not run in the places this script runs (bare suite CI, brain).
    """
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        # flow style: `on: push` / `on: [push, pull_request]`
        m = re.match(r"^on:\s*(\S.*)$", line)
        if m and re.search(r"\bpush\b", m.group(1)):
            if not re.search(r"branches|tags|paths", m.group(1)):
                out.append(("ERROR", "unfiltered `push` trigger (flow style) — every PR "
                                     "branch runs twice; filter to branches/tags like "
                                     "`push: {branches: [main], tags: ['v*']}`"))
            continue
        # block style: a `push:` mapping key — filtered iff its indented block
        # (or the same line, inline mapping) names branches/tags/paths
        m = re.match(r"^(\s+)push:\s*(.*)$", line)
        if m is None:
            continue
        indent, inline = len(m.group(1)), m.group(2)
        if re.search(r"branches|tags|paths", inline):
            continue
        filtered = False
        for nxt in lines[i + 1:]:
            if not nxt.strip() or nxt.lstrip().startswith("#"):
                continue
            if len(nxt) - len(nxt.lstrip()) <= indent:
                break
            if re.match(r"^\s*(branches|tags|paths)(-ignore)?:", nxt):
                filtered = True
                break
        if not filtered:
            out.append(("ERROR", "unfiltered `push` trigger — every PR branch runs "
                                 "twice; add `branches: [main]` (+ tags for releases)"))
    if re.search(r"runs-on:.*macos|matrix:[\s\S]*macos", text):
        out.append(("INFO", "macOS runner in use — bills 10x; keep it behind filtered "
                            "triggers only"))
    return out


def check(repo: Path, contract: dict):
    """Return a list of (level, message)."""
    out = []
    add = lambda lvl, msg: out.append((lvl, msg))
    core = parse_version(contract["contract_version"])

    if not (repo / ".git").exists():
        add("WARN", "not a git repository — no history, nothing to pin")

    for rel in contract["required_files"]:
        if not (repo / rel).exists():
            add("ERROR", f"missing required file: {rel}")

    # plugin manifest
    pj = repo / ".claude-plugin" / "plugin.json"
    if pj.exists():
        try:
            data = json.loads(pj.read_text(encoding="utf-8"))
            for field in contract["plugin_required_fields"]:
                if not data.get(field):
                    add("ERROR", f".claude-plugin/plugin.json: missing {field!r}")
        except json.JSONDecodeError as e:
            add("ERROR", f".claude-plugin/plugin.json does not parse: {e}")

    # dependency manifest + the core declaration
    dj = repo / "dependencies.json"
    if dj.exists():
        try:
            data = json.loads(dj.read_text(encoding="utf-8"))
            for field in contract["dependencies_required_fields"]:
                if field not in data:
                    lvl = "ERROR" if field == "requires_core" else "WARN"
                    add(lvl, f"dependencies.json: missing {field!r}")
            if "requires_core" in data:
                ok, why = satisfies(core, data["requires_core"])
                if not ok:
                    add("ERROR", f"core mismatch: {why}")
        except json.JSONDecodeError as e:
            add("ERROR", f"dependencies.json does not parse: {e}")

    # the leak scan has to actually run, not just exist
    ci = repo / ".github" / "workflows"
    if ci.is_dir():
        text = "\n".join(f.read_text(encoding="utf-8", errors="replace") for f in ci.glob("*.yml"))
        for step in contract["required_ci_steps"]:
            if step not in text:
                add("ERROR", f"no CI step runs {step}")
        # Actions minutes are a shared account budget: an unfiltered `push` trigger runs
        # every PR branch twice (push event + pull_request event). That pattern exhausted
        # the account's 2000-min free quota mid-month on 2026-08-13 and killed CI
        # account-wide. macOS bills 10x, Windows 2x.
        for f in sorted(ci.glob("*.yml")):
            for lvl, msg in workflow_trigger_findings(
                    f.read_text(encoding="utf-8", errors="replace")):
                add(lvl, f"{f.relative_to(repo)}: {msg}")
    # absolute home paths in anything tracked
    hits = 0
    for f in tracked_files(repo):
        if f.suffix.lower() in SKIP_SUFFIX or not f.is_file():
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for m in HOME_PATH.finditer(text):
            if not ALLOWED_HOME.match(m.group(0)):
                hits += 1
                if hits <= 3:
                    add("ERROR", f"absolute home path in {f.relative_to(repo)}: {m.group(0)}")
    if hits > 3:
        add("ERROR", f"...and {hits - 3} more absolute home paths")

    # versioning: asked for by CONVENTIONS section 6, not yet blocking
    if not (repo / "CHANGELOG.md").exists():
        add("WARN", "no CHANGELOG.md — CONVENTIONS section 6 asks for one")
    try:
        tags = subprocess.run(["git", "-C", str(repo), "tag"],
                              capture_output=True, text=True, timeout=15).stdout.split()
        if not tags:
            add("WARN", "no tags — a suite without a version cannot be pinned")
        else:
            add("INFO", f"latest tag: {sorted(tags)[-1]}")
    except (OSError, subprocess.SubprocessError):
        pass
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="suite repo paths")
    ap.add_argument("--contract", default=str(CONTRACT_PATH))
    ap.add_argument("--strict", action="store_true", help="warnings block too")
    args = ap.parse_args()

    contract = json.loads(Path(args.contract).read_text(encoding="utf-8"))
    core = contract["contract_version"]
    print(f"suite-check: core contract {core}\n")

    worst = 0
    for raw in args.paths:
        repo = Path(raw).expanduser().resolve()
        if not repo.is_dir():
            print(f"!! {raw}: not a directory")
            worst = 1
            continue
        findings = check(repo, contract)
        errors = [f for f in findings if f[0] == "ERROR"]
        warns = [f for f in findings if f[0] == "WARN"]
        verdict = "FAIL" if errors else ("WARN" if warns else "OK")
        print(f"{verdict:5s} {repo.name}  ({len(errors)} error, {len(warns)} warn)")
        for lvl, msg in findings:
            print(f"        [{lvl}] {msg}")
        if errors or (args.strict and warns):
            worst = 1
        print()
    return worst


if __name__ == "__main__":
    sys.exit(main())
