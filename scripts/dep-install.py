#!/usr/bin/env python3
"""Fetch the external dependencies declared in the manifest — dry-run by default.

The manifest without an installer is documentation; this is the part that makes
onboarding one command instead of a manual rebuild (CONVENTIONS.md section 9).

Read-first, like the other tools in this repo: prints what it WOULD run and exits.
Nothing happens without --apply.

  scripts/dep-install.py                 # what is missing, and what would run
  scripts/dep-install.py --apply         # install everything missing
  scripts/dep-install.py --apply buttercut LightRAG   # only these

Only kind=tool entries are installable. kind=vendored is third-party content that
already sits in the repo (or must NOT be redistributed); kind=workdir is a scratch
directory a skill creates itself.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "config" / "dependencies.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*", help="only these dependencies (default: all missing)")
    ap.add_argument("--apply", action="store_true", help="actually run the commands")
    ap.add_argument("--manifest", default=str(MANIFEST))
    args = ap.parse_args()

    try:
        entries = json.loads(Path(args.manifest).read_text(encoding="utf-8"))["dependencies"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"dep-install: manifest not readable: {exc}", file=sys.stderr)
        return 2

    tools = [e for e in entries if e.get("kind") == "tool"]
    if args.names:
        wanted = set(args.names)
        unknown = wanted - {e["name"] for e in tools}
        if unknown:
            print(f"dep-install: unknown (or not kind=tool): {', '.join(sorted(unknown))}",
                  file=sys.stderr)
            return 2
        tools = [e for e in tools if e["name"] in wanted]

    missing = [e for e in tools if not (ROOT / e["target"]).exists()]
    if not missing:
        print("dep-install: all requested dependencies are present.")
        return 0

    print(f"dep-install: {len(missing)} missing" + ("" if args.apply else " — DRY-RUN, nothing will be executed"))
    failed = []
    for entry in missing:
        print(f"\n## {entry['name']}  ->  {entry['target']}")
        print(f"   source: {entry['url']}  pin: {entry['pin']}  license: {entry['license']}")
        for cmd in entry["install"]:
            print(f"   $ {cmd}")
            if not args.apply:
                continue
            result = subprocess.run(cmd, shell=True, cwd=ROOT)
            if result.returncode != 0:
                print(f"   !! failed (exit {result.returncode}) — aborting for {entry['name']}")
                failed.append(entry["name"])
                break

    if not args.apply:
        print("\nto run it: scripts/dep-install.py --apply")
        return 0
    if failed:
        print(f"\n!! failed: {', '.join(failed)}")
        return 1
    print("\ndone. cross-check: python3 scripts/dep-lint.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
