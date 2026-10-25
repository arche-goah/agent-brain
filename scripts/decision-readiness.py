#!/usr/bin/env python3
"""decision-readiness.py — does this brain decide on its own what it may decide, and ask only what needs the operator?

Operator decision 2026-10-16 on a proving brain (translated): only what really needs the operator goes to the
operator; what can be settled cleanly alone or between the AIs, is reversible and documented, is decided without
asking — and this must be assured in every core. The rule exists (rules/working-rules.md "ASK OR ACT",
rules/intelligence.md "comparative test"), but measured the same day on a collaborator's brain:
  - its core predated the rule (0 hits for "ASK OR ACT"), so nothing told the AI when NOT to ask;
  - three core rules point at "the instance's operator-only list", and the template shipped none;
  - `git commit*` / `git push*` stood under `ask`, so every commit raised a dialog the human did not understand,
    and the AI read push as "needs the operator";
  - the human's answer to that was `Bash(*)` in `allow` — no dialog, but no check either.

Prints one line per finding, nothing when the brain is fine. Read-only, no network.

  decision-readiness.py [--root <brain>]
"""
import argparse, fnmatch, json, os, re, sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

RULE_FILES = ("core/rules/working-rules.md", "core/rules/intelligence.md")
# Everyday commands that must not raise a dialog. An `ask` rule is a finding only when it catches one of these —
# a targeted rule (`git push * main*`) does not.
EVERYDAY = ("git commit -m x", "git push", "git push origin feat/x", "git -C /repo push", "git -C /repo commit -m x",
            "gh pr comment 1 --body x", "gh pr create --title x")


def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def imported(claude_md):
    """The @-imports of CLAUDE.md, one level, outside fenced code."""
    out, fence = set(), False
    for ln in claude_md.splitlines():
        if ln.lstrip().startswith("```"):
            fence = not fence
            continue
        m = None if fence else re.match(r"^\s*@(\S+)\s*$", ln)
        if m:
            out.add(m.group(1))
    return out


def rule_body(rule):
    m = re.fullmatch(r"Bash(?:\((.*)\))?", str(rule).strip(), re.S)
    return None if not m else (m.group(1) if m.group(1) is not None else "")


def catches(body, cmd):
    """Claude Code's Bash rule semantics as far as they matter here: a trailing `:*` is the legacy prefix form,
    otherwise `*` is a glob over the whole command."""
    if body in ("", "*"):
        return True
    if body.endswith(":*"):
        return cmd.startswith(body[:-2])
    return fnmatch.fnmatchcase(cmd, body.replace("[", "[[]"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    brain = Path(ap.parse_args().root)
    if not (brain / "core").is_dir():
        return 0  # not a brain
    lines = []

    claude_md = text(brain / "CLAUDE.md")
    imports = imported(claude_md)
    missing = [f for f in RULE_FILES if f not in imports]
    if missing:
        lines.append(f"CLAUDE.md does not import {', '.join(missing)} — the rule for when to ask and when to decide "
                     "(ASK OR ACT, comparative test) is not loaded")
    elif "ASK OR ACT" not in text(brain / "core/rules/working-rules.md"):
        lines.append("the core in use predates ASK OR ACT — nothing tells the AI when NOT to ask; update the core "
                     "(bash core/scripts/brain-update.sh)")

    oo = brain / ".claude/rules/operator-only.json"
    data = load(oo) if oo.is_file() else None
    if not oo.is_file():
        lines.append("no .claude/rules/operator-only.json — the core's rules point at this one list of matters that "
                     "need the operator; copy core/templates/rules-instance/operator-only.json and adjust the labels")
    elif not isinstance(data, dict) or not data.get("matters"):
        lines.append(".claude/rules/operator-only.json is broken or empty — the AI cannot tell what needs the operator")
    else:
        # Existence is not content (operator 2026-10-18): a list that drops a core matter passes the check above.
        tpl = load(Path(__file__).resolve().parent.parent / "templates/rules-instance/operator-only.json") or {}
        have = {m.get("id") for m in data["matters"] if isinstance(m, dict)}
        gone = [m["id"] for m in tpl.get("matters") or [] if m.get("id") not in have]
        if gone:
            lines.append(f".claude/rules/operator-only.json does not name {', '.join(gone)} from the core template — "
                         "a matter missing there never reaches the operator; add it, or keep its id with the "
                         "operator's own label")

    asked, star = [], False
    for name in ("settings.json", "settings.local.json"):
        perm = (load(brain / ".claude" / name) or {}).get("permissions") or {}
        for r in perm.get("ask") or []:
            body = rule_body(r)
            if body and any(catches(body, e) for e in EVERYDAY):
                asked.append(r)
        for r in perm.get("allow") or []:
            if rule_body(r) in ("", "*"):
                star = True
    if asked:
        lines.append(f"everyday git/gh steps raise a permission dialog ({', '.join(sorted(set(asked))[:4])}) — the "
                     "human sees a question for every commit; move them to allow (template: "
                     "core/templates/settings.json; a human edits settings)")
    if star:
        lines.append("`Bash(*)` is allowed — no dialog, but also no check of any command (force push as +ref, "
                     "settings edits via sed); use the template's targeted list instead")

    for ln in lines:
        print(f"!! decision readiness: {ln}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
