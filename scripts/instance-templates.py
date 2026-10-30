#!/usr/bin/env python3
"""instance-templates.py — every `.claude/rules/<name>.json` the core reads has a template or is declared optional.

WHY (operator approved 2026-10-30, after a measurement on the macOS instance): the core reads 45 instance files;
19 of them had no template in `templates/rules-instance/`. A brain bootstrapped from the templates never learns
those files exist — the reader falls back silently (or reads nothing), and nothing tells the brain. A template is
how a new brain gets the file; an optional declaration says, with its reason, why none is needed.

CHECK: scan helpers/*.cjs and scripts/*.{py,sh} (fixtures excluded) for `.claude/rules/<name>.json`; each name needs
`templates/rules-instance/<name>` or an entry in `templates/instance-files-optional.json` (`{"optional": {name:
reason}}`). A ratchet: names in that file's `unclassified` list are known gaps — they may only leave the list
(template or optional reason added), never join it.

Usage: instance-templates.py [core-root]   exit 0 = every read file is covered, 1 = a new uncovered read
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
PAT = re.compile(r"""\.claude['"]?\s*[,/]\s*['"]?rules['"]?\s*[,/]\s*['"]?([A-Za-z0-9_-]+\.json)|\.claude/rules/([A-Za-z0-9_-]+\.json)""")


def reads(root: Path) -> dict:
    out = {}
    files = list((root / "helpers").glob("*.cjs")) + list((root / "scripts").glob("*.py")) + list((root / "scripts").glob("*.sh"))
    for p in files:
        if re.search(r"(^test-|-test\.)", p.name) or p.name == Path(__file__).name:
            continue
        for m in PAT.finditer(p.read_text(encoding="utf-8", errors="replace")):
            out.setdefault(m.group(1) or m.group(2), set()).add(p.name)
    return out


def main() -> int:
    decl_path = ROOT / "templates" / "instance-files-optional.json"
    decl = json.loads(decl_path.read_text(encoding="utf-8")) if decl_path.is_file() else {}
    optional = decl.get("optional") or {}
    unclassified = set(decl.get("unclassified") or [])
    have = {p.name for p in (ROOT / "templates" / "rules-instance").glob("*")}
    fail = 0
    seen = reads(ROOT)
    for name in sorted(seen):
        if name in have or name in optional:
            continue
        if name in unclassified:
            continue
        fail = 1
        print(f"!! {name}: read by {', '.join(sorted(seen[name]))} — no template in templates/rules-instance/ and no "
              "optional reason in templates/instance-files-optional.json")
    stale = sorted(n for n in unclassified if n in have or n in optional or n not in seen)
    for name in stale:
        print(f"-- {name}: listed as unclassified but covered or no longer read — drop it from the list")
    covered = sum(1 for n in seen if n in have or n in optional)
    print(f"instance-templates: {len(seen)} read, {covered} covered, {len([n for n in seen if n in unclassified])} "
          f"known unclassified, {'FAILED' if fail else 'ok'}")
    return fail


if __name__ == "__main__":
    sys.exit(main())
