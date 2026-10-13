#!/usr/bin/env python3
"""Fixture test for skill-lint.py yaml_problem(): the frontmatter a host rejects or cuts.

Planted cases are the measured ones (2026-10-10, touchdesigner-suite): a plain description
with ': ' inside (host loads the skill with NO description) and one with ' #' (cut there).
Negative controls: the same text quoted, as a block scalar, and a metadata map — all valid.
Each planted case runs twice: with PyYAML hidden (stdlib rules) and as installed.
Usage: python3 scripts/skill-lint-yaml-test.py   (exit 0 = all pass)
"""
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("skill_lint", Path(__file__).with_name("skill-lint.py"))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)

BAD = {
    "colon in plain value": "---\nname: x\ndescription: Folder layout. The handover test: would a stranger get it?\n---\n",
    "colon on a continuation line": "---\nname: x\ndescription: first line\n  second line: with a colon\n---\n",
    "hash cuts the value": "---\nname: x\ndescription: version pinning via glslversion instead of #version, uniforms\n---\n",
}
GOOD = {
    "double-quoted": "---\nname: x\ndescription: \"The handover test: would a stranger get it? #1\"\n---\n",
    "block scalar": "---\nname: x\ndescription: >-\n  The handover test: would a stranger\n  get it? #version\n---\n",
    "metadata map": "---\nname: x\ndescription: plain text, no traps\nmetadata:\n  load-before-tools: \"^mcp__td__\"\n---\n",
    "url without space": "---\nname: x\ndescription: see https://example.org/a#b for details\n---\n",
}

fail = 0
for hide in (True, False):
    saved = sys.modules.get("yaml")
    if hide:
        sys.modules["yaml"] = None  # import yaml -> ImportError
    try:
        mode = "stdlib" if hide else "with pyyaml (if installed)"
        for label, text in BAD.items():
            got = lint.yaml_problem(text)
            print(f"  {'OK  ' if got else 'FAIL'} [{mode}] flags: {label}" + (f" -> {got}" if got else ""))
            fail |= not got
        for label, text in GOOD.items():
            got = lint.yaml_problem(text)
            print(f"  {'OK  ' if not got else 'FAIL'} [{mode}] silent: {label}" + (f" -> {got}" if got else ""))
            fail |= bool(got)
    finally:
        if hide:
            if saved is None:
                sys.modules.pop("yaml", None)
            else:
                sys.modules["yaml"] = saved
print("skill-lint yaml: all fixtures pass" if not fail else "skill-lint yaml: FAILURES")
sys.exit(1 if fail else 0)
