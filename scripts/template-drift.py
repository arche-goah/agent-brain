#!/usr/bin/env python3
"""template-drift.py — which rules of the core templates does this brain NOT carry?

WHY (measured 2026-10-26 on the Windows instance): in an autonomous run the auto-mode classifier
refused `gh pr ready` ("Unrequested Commit in a Connected App"), so the operator had to click it
by hand. The brain's `.claude/settings.json` carried 22 of the template's 83 allow rules —
`gh pr ready`, `gh pr create`, `gh pr comment`, `gh pr review`, `gh pr edit` and more were
missing, and every one of them left the step to the classifier. The core template had gained
those rules from exactly such incidents, but a template is copied once, when a brain is
bootstrapped: no improvement to it ever reaches an existing brain. `autonomy-diagnose.py` could
show the gap (section 4, the template column) — on demand only; nothing ran it, so the gap
stayed silent for weeks.

The same day, the second half: the classifier also refused taking over template rules
("Self-Modification") and counter-checks of the organisation's own PRs ("Code from External",
on the macOS instance). Its trust lives in `autoMode`, which Claude Code reads ONLY from the
user's `~/.claude/settings.json` (and managed settings), never from a project's settings — so
no repo template could carry it. `templates/user-settings.json` now does, and this script
checks it too.

The invariants:
  1. every allow, ask and deny rule of `core/templates/settings.json` is in the brain's project
     settings, OR the brain declares why not in `permissions._template_deviations`
     ({"<rule>": "<why>"}, a blank reason does not count);
  2. every `autoMode` entry of `core/templates/user-settings.json` is in the user's
     `~/.claude/settings.json`, with `<org>` filled from the marketplace repo the settings name.
Anything else is named at every session start, loudly, as long as it stands.

Usage:
  template-drift.py [--repo DIR]           report (silent when nothing is missing; exit 0)
  template-drift.py --apply-user [--org O] merge the missing autoMode entries into
                                           ~/.claude/settings.json, after a dated copy of it.
                                           Run by the PERSON at the machine (`! <command>`):
                                           widening the classifier's trust is their step.
"""
import argparse
import datetime
import json
import os
import pathlib
import shutil
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except Exception:
    pass

KINDS = ("allow", "ask", "deny")
AUTO_KINDS = ("environment", "allow", "soft_deny", "hard_deny")
SHOWN = 5
TEMPLATES = pathlib.Path(__file__).resolve().parent.parent / "templates"


def load(path):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def user_settings_path():
    cfg = os.environ.get("CLAUDE_CONFIG_DIR")
    return (pathlib.Path(cfg) if cfg else pathlib.Path.home() / ".claude") / "settings.json"


def org_of(*settings):
    """The org of the marketplace repo the settings name (same derivation as session-bootup.sh)."""
    for s in settings:
        for m in ((s or {}).get("extraKnownMarketplaces") or {}).values():
            repo = ((m or {}).get("source") or {}).get("repo", "")
            if "/" in repo and not repo.startswith("<"):
                return repo.split("/")[0]
    return None


def shown(kind, gone):
    return f"{kind} {len(gone)}: " + ", ".join(gone[:SHOWN]) + (f" (+{len(gone) - SHOWN} more)" if len(gone) > SHOWN else "")


def project_drift(repo, template):
    tpl = load(template)
    tpl = (tpl or {}).get("permissions")
    if tpl is None:
        return None  # a core without the template has nothing to compare against
    here = load(pathlib.Path(repo) / ".claude" / "settings.json")
    if here is None:
        return ("!! settings: .claude/settings.json missing or not valid JSON - the core template's "
                "permission rules cannot be compared")
    here = here.get("permissions") or {}
    declared = here.get("_template_deviations") or {}
    parts, total = [], 0
    for kind in KINDS:
        have = set(here.get(kind) or [])
        gone = [r for r in tpl.get(kind) or [] if r not in have and not str(declared.get(r, "")).strip()]
        if gone:
            parts.append(shown(kind, gone))
            total += len(gone)
    if not parts:
        return None
    return (f"!! settings: {total} permission rule(s) of the core template are not in this brain's "
            f".claude/settings.json - {'; '.join(parts)}. A missing allow leaves the step to the "
            f"harness (in auto mode the classifier may refuse it), a missing deny or ask drops a "
            f"limit. Take them over, or declare why in permissions._template_deviations "
            f"(full list: python3 core/scripts/autonomy-diagnose.py, section 4)")


def wanted_auto(user_template, org):
    tpl = (load(user_template) or {}).get("autoMode") or {}
    return {k: [e.replace("<org>", org) for e in tpl.get(k) or []] for k in AUTO_KINDS if tpl.get(k)}


def user_drift(user, user_template, org):
    want = wanted_auto(user_template, org)
    if not want:
        return None, {}
    have = (user or {}).get("autoMode") or {}
    missing = {k: [e for e in v if e not in (have.get(k) or [])] for k, v in want.items()}
    missing = {k: v for k, v in missing.items() if v}
    if not missing:
        return None, {}
    total = sum(len(v) for v in missing.values())
    names = "; ".join(f"{k} {len(v)}" for k, v in missing.items())
    return (f"!! settings: {total} autoMode entr(y/ies) of the core template are not in "
            f"~/.claude/settings.json ({names}) - the auto-mode classifier reads its trust only from "
            f"there, so an autonomous run stops on steps it would clear (own PR ready, template "
            f"rules, counter-checks of the org's PRs). The person at this machine runs: "
            f"! python3 core/scripts/template-drift.py --apply-user"), missing


def apply_user(user_template, org_arg, repo):
    path = user_settings_path()
    user = load(path)
    if user is None and path.exists():
        print(f"template-drift: {path.as_posix()} is not valid JSON - nothing written")
        return 1
    user = user or {}
    org = org_arg or org_of(load(pathlib.Path(repo) / ".claude" / "settings.json"), user)
    if not org:
        print("template-drift: no org found (no marketplace repo in the settings) - pass --org <org>")
        return 1
    _, missing = user_drift(user, user_template, org)
    if not missing:
        print(f"template-drift: {path.as_posix()} already carries every autoMode entry of the template - nothing written")
        return 0
    if path.exists():
        stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        shutil.copy2(path, path.with_name(f"settings.{stamp}.json"))
    auto = user.setdefault("autoMode", {})
    for kind, entries in missing.items():
        lst = auto.setdefault(kind, [])
        if "$defaults" in entries and "$defaults" not in lst:
            lst.insert(0, "$defaults")
        lst.extend(e for e in entries if e != "$defaults")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    # open(), not the pathlib writer with newline=: that keyword is Python 3.10+ (OS-13, stock macOS has 3.9)
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(user, indent=2, ensure_ascii=False) + "\n")
    os.replace(tmp, path)
    print(f"template-drift: {sum(len(v) for v in missing.values())} autoMode entr(y/ies) written to {path.as_posix()} "
          f"(org {org}); previous file kept as a dated copy. Check: claude auto-mode config")
    return 0


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--repo", default=".")
    a.add_argument("--template", default=str(TEMPLATES / "settings.json"))
    a.add_argument("--user-template", default=str(TEMPLATES / "user-settings.json"))
    a.add_argument("--apply-user", action="store_true")
    a.add_argument("--org")
    args = a.parse_args()
    if args.apply_user:
        return apply_user(args.user_template, args.org, args.repo)
    line = project_drift(args.repo, args.template)
    if line:
        print(line)
    user = load(user_settings_path())
    org = args.org or org_of(load(pathlib.Path(args.repo) / ".claude" / "settings.json"), user)
    if org:
        uline, _ = user_drift(user, args.user_template, org)
        if uline:
            print(uline)
    return 0


if __name__ == "__main__":
    sys.exit(main())
