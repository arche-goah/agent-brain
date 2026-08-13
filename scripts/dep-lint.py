#!/usr/bin/env python3
"""Deterministic dependency-manifest linter — read-only, stdlib, reproducible.

WHY (measured 2026-08-03): eight skills executed commands against a `tools/` directory
that does not exist in this repo. They were already broken here; on a second machine
they would break on day one, silently, in the middle of a workflow. Nothing detected it,
because an undeclared dependency is invisible by definition.

This closes that class: a `tools/`-style path referenced in a skill must be declared in
the manifest. Whether it is currently INSTALLED is a fact about the machine, not about
the repo — so a missing checkout is reported as info, never as a build failure. The
build only fails on what the repo itself got wrong.

CHECKS (error = exit 1):
  E1 undeclared   a tools/<x> path referenced in a SKILL.md has no manifest entry
  E2 fields       manifest entry missing a required field for its kind
  E3 duplicate    two entries claim the same name or the same target path
  E4 ghost        a vendored entry names a target path that does not exist on disk
  E5 unusable     kind=tool entry with an empty install list

INFO (exit 0, but printed):
  I1 not_installed  declared kind=tool target absent on disk — run the install commands
  I2 unverified     license or url still "unverified" — must be resolved before sharing
  I3 unused         manifest entry nothing refers to
  I4 dead_path      repo-relative path in a SKILL.md that resolves nowhere

I4 is deliberately NOT blocking. It is the same defect class as E1 (a skill pointing at
something that is not there — the handoff of 2026-08-03 asked for it, having found four
suite files pointing into the private brain). But it cannot be gated honestly: measured
on this repo it produces 34 hits, of which roughly two thirds are illustrative examples
in documentation ("src/components/MyComponent.tsx") and directories a skill creates at
runtime. Gating that would require 34 curated exceptions and would train everyone to
rubber-stamp the list. Visible and counted beats gated and ignored.
Paths are resolved against the skill directory first, then the repo root.

Usage: dep-lint.py [--manifest config/dependencies.json] [--json] [--strict]
       --strict also fails on I2 (use before making a repo public/shared)
Exit 0 = clean, 1 = errors, 2 = manifest unreadable.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Lints the INSTANCE repo (its dependencies.json + skills). Run from the instance root,
# or set BRAIN_DIR. The core checkout only carries the tool.
import os
ROOT = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()

# Same word-boundary lesson as skill-lint: without the lookbehind this matches the tail
# of unrelated paths (".../whisper-cut-ffmpeg/tools/x") and invents dependencies.
TOOLS_RE = re.compile(r"(?<![\w/.-])tools/[A-Za-z0-9._-]+")

# Repo-relative paths for the I4 sweep. Backticks are NOT excluded: real references are
# written as inline code, so filtering them out would drop most true positives and keep
# the prose. Noise is acceptable here because I4 does not gate the build.
REPO_PATH_RE = re.compile(r"(?<![\w/.-])(?:docs|config|scripts|src)/[A-Za-z0-9._/-]*[A-Za-z0-9_-]")

REQUIRED = {
    # fetched from outside
    "tool": ("name", "kind", "url", "pin", "license", "target", "install"),
    # third-party content sitting in this repo
    "vendored": ("name", "kind", "url", "pin", "license", "target", "distribution"),
    # local working directory a skill creates itself — no source, no install, may be
    # absent. Declared anyway, otherwise E1 cannot tell "cache dir" from "missing
    # dependency" and the check trains people to ignore it.
    "workdir": ("name", "kind", "target", "created_by", "note"),
}


def targets(entry: dict) -> list[str]:
    """target is a string for tools, a list for vendored packs."""
    t = entry.get("target", [])
    return [t] if isinstance(t, str) else list(t)


def owning_repo(skill_dir: Path) -> Path | None:
    """Repo root a symlinked skill really belongs to.

    Ten MA3 skills and one MikroTik skill are symlinks into their suite repos. Their
    paths (docs/shows/…, src/grandma3-mcp/…) resolve THERE and are correct. Checking
    them against this repo root produced ~30 false findings — enough noise to bury the
    real ones.
    """
    if not skill_dir.is_symlink():
        return None
    for parent in skill_dir.resolve().parents:
        if (parent / ".git").exists():
            return parent
    return None


def scan_dead_paths(skills_dir: Path) -> dict[str, set[str]]:
    """repo-relative path that resolves in no plausible root."""
    dead: dict[str, set[str]] = {}
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        skill_dir = skill_md.parent
        try:
            body = skill_md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        roots = [skill_dir.resolve(), ROOT]
        home = owning_repo(skill_dir)
        if home:
            roots.append(home)
        for hit in {m.group(0) for m in REPO_PATH_RE.finditer(body)}:
            if any((root / hit).exists() for root in roots):
                continue
            dead.setdefault(hit, set()).add(skill_dir.name)
    return dead


def scan_refs(skills_dir: Path) -> dict[str, set[str]]:
    """tools/<x> path -> set of skills referencing it."""
    refs: dict[str, set[str]] = {}
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        try:
            body = skill_md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for hit in TOOLS_RE.findall(body):
            refs.setdefault(hit, set()).add(skill_md.parent.name)
    return refs


def lint(manifest_path: Path, skills_dir: Path) -> tuple[list, list]:
    errors: list[dict] = []
    infos: list[dict] = []

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"dep-lint: manifest not readable: {exc}", file=sys.stderr)
        sys.exit(2)

    entries = manifest.get("dependencies", [])
    seen_names: dict[str, int] = {}
    seen_targets: dict[str, str] = {}
    declared: dict[str, dict] = {}  # target path -> entry

    for i, entry in enumerate(entries):
        name = entry.get("name", f"<entry {i}>")
        kind = entry.get("kind")

        if kind not in REQUIRED:
            errors.append({"check": "E2", "entry": name, "detail": f"unknown kind: {kind!r}"})
            continue

        missing = [f for f in REQUIRED[kind] if not entry.get(f)]
        if missing:
            errors.append({"check": "E2", "entry": name, "detail": f"missing fields: {', '.join(missing)}"})

        if name in seen_names:
            errors.append({"check": "E3", "entry": name, "detail": "name used twice"})
        seen_names[name] = i

        if kind == "tool" and not entry.get("install"):
            errors.append({"check": "E5", "entry": name, "detail": "kind=tool without install steps"})

        for tgt in targets(entry):
            if tgt in seen_targets:
                errors.append({"check": "E3", "entry": name,
                               "detail": f"target {tgt} already claimed by {seen_targets[tgt]}"})
            seen_targets[tgt] = name
            declared[tgt] = entry

            exists = (ROOT / tgt).exists()
            if kind == "vendored" and not exists:
                errors.append({"check": "E4", "entry": name,
                               "detail": f"vendored target does not exist: {tgt}"})
            elif kind == "tool" and not exists:
                infos.append({"check": "I1", "entry": name,
                              "detail": f"not installed: {tgt} — see install steps in the manifest"})

        for field in ("url", "license"):
            if entry.get(field) == "unverified":
                infos.append({"check": "I2", "entry": name, "detail": f"{field} unverified"})

    refs = scan_refs(skills_dir)
    for path, users in sorted(refs.items()):
        if path not in declared:
            errors.append({"check": "E1", "entry": path,
                           "detail": f"not in the manifest, referenced by: {', '.join(sorted(users))}"})

    referenced = set(refs)
    for tgt, entry in declared.items():
        if entry.get("kind") == "tool" and tgt not in referenced:
            infos.append({"check": "I3", "entry": entry["name"], "detail": f"no skill references {tgt}"})

    for path, users in sorted(scan_dead_paths(skills_dir).items()):
        infos.append({"check": "I4", "entry": path,
                      "detail": f"resolves nowhere, referenced by: {', '.join(sorted(users))}"})

    return errors, infos


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="config/dependencies.json")
    ap.add_argument("--skills", default=".claude/skills")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true", help="also fail on I2 (unverified)")
    args = ap.parse_args()

    errors, infos = lint(ROOT / args.manifest, ROOT / args.skills)

    if args.json:
        print(json.dumps({"errors": errors, "infos": infos}, indent=2))
    else:
        print(f"dep-lint: {len(errors)} error(s), {len(infos)} note(s)")
        for group, items in (("!! ERROR", errors), ("   note", infos)):
            for item in items:
                print(f"{group} [{item['check']}] {item['entry']}: {item['detail']}")

    if errors:
        return 1
    if args.strict and any(i["check"] == "I2" for i in infos):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
