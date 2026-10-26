#!/usr/bin/env python3
"""template-drift.py — which permission rules of the core template does this brain NOT carry?

WHY (measured 2026-10-26 on the Windows instance): in an autonomous run the auto-mode classifier
refused `gh pr ready` ("Unrequested Commit in a Connected App"), so the operator had to click it
by hand. The brain's `.claude/settings.json` carried 22 of the template's 83 allow rules —
`gh pr ready`, `gh pr create`, `gh pr comment`, `gh pr review`, `gh pr edit` and more were
missing, and every one of them left the step to the classifier. The core template had gained
those rules from exactly such incidents, but a template is copied once, when a brain is
bootstrapped: no improvement to it ever reaches an existing brain. `autonomy-diagnose.py` could
show the gap (section 4, the template column) — on demand only; nothing ran it, so the gap
stayed silent for weeks.

The invariant: every allow, ask and deny rule of `core/templates/settings.json` is in the
brain's project settings, OR the brain declares why not, with a reason, in
`permissions._template_deviations` of the same file: {"<rule>": "<why>"}. Anything else is
named at every session start, loudly, as long as it stands.

Usage: template-drift.py [--repo DIR] [--template FILE]   (default: the brain in the cwd,
the template next to this script). Prints nothing when nothing is missing; exit 0 always —
it is a report, never a gate.
"""
import argparse
import json
import pathlib
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except Exception:
    pass

KINDS = ("allow", "ask", "deny")
SHOWN = 5


def rules(path):
    try:
        perm = json.loads(pathlib.Path(path).read_text(encoding="utf-8")).get("permissions") or {}
    except (OSError, ValueError):
        return None
    return perm


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--repo", default=".")
    a.add_argument("--template", default=str(pathlib.Path(__file__).resolve().parent.parent
                                              / "templates" / "settings.json"))
    args = a.parse_args()
    tpl = rules(args.template)
    if tpl is None:
        return 0  # a core without the template has nothing to compare against
    here = rules(pathlib.Path(args.repo) / ".claude" / "settings.json")
    if here is None:
        print("!! settings: .claude/settings.json missing or not valid JSON - the core template's "
              "permission rules cannot be compared")
        return 0
    declared = here.get("_template_deviations") or {}
    missing = {}
    for kind in KINDS:
        have = set(here.get(kind) or [])
        gone = [r for r in tpl.get(kind) or [] if r not in have and not str(declared.get(r, "")).strip()]
        if gone:
            missing[kind] = gone
    if not missing:
        return 0
    total = sum(len(v) for v in missing.values())
    parts = []
    for kind, gone in missing.items():
        shown = ", ".join(gone[:SHOWN]) + (f" (+{len(gone) - SHOWN} more)" if len(gone) > SHOWN else "")
        parts.append(f"{kind} {len(gone)}: {shown}")
    print(f"!! settings: {total} permission rule(s) of the core template are not in this brain's "
          f".claude/settings.json - {'; '.join(parts)}. A missing allow leaves the step to the "
          f"harness (in auto mode the classifier may refuse it), a missing deny or ask drops a "
          f"limit. Take them over, or declare why in permissions._template_deviations "
          f"(full list: python3 core/scripts/autonomy-diagnose.py, section 4)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
