#!/usr/bin/env python3
"""Check of the /onboard project command (.claude/commands/onboard.md), both directions.

WHY: `/onboard` is what a stranger types in a fresh clone of the core, before any plugin
is installed (ONBOARDING.md, "Prefer to be guided?"). Its `allowed-tools` lets the listed
commands run without a prompt in the turn it is typed. It breaks silently in four ways:
the frontmatter does not parse (the host then loads the command without its fields), the
allowlist grows a broad entry (`Bash(*)`, `Bash(git *)`, a push), a script it names is
renamed, or it drifts away from the commands ONBOARDING.md really tells the person to run.

Checks on the real file: it exists; its frontmatter is valid YAML (skill-lint's own
yaml_problem); description present; `disable-model-invocation: true` (onboarding changes
things outside the clone, so it starts only when the person types it); `allowed-tools` is
a YAML list; every entry is Read, Glob, Grep or Bash(<command>) with at most a trailing
wildcard, at least two fixed words, no push / rm / sudo / --force / --global / shell
operator; every scripts/<file> it names exists; the fixed part of every Bash entry appears
verbatim in ONBOARDING.md. Then planted copies of the real file must go red, each for its
own reason.
Usage: python3 scripts/onboard-command-test.py   (exit 0 = the file is clean and every
planted case is caught)
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CMD = REPO / ".claude" / "commands" / "onboard.md"
DOC = REPO / "ONBOARDING.md"

spec = importlib.util.spec_from_file_location("skill_lint", Path(__file__).with_name("skill-lint.py"))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)

READ_ONLY = {"Read", "Glob", "Grep"}
FORBIDDEN = re.compile(r"(^|\s)(push|rm|sudo|--force|--global)(\s|$)|[;&|<>`$]")


def allowed_tools(text: str) -> list[str] | None:
    """The `allowed-tools` YAML list of the frontmatter; None when absent or not a list."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    lines = text[3:end].splitlines()
    for i, raw in enumerate(lines):
        if re.match(r"^allowed-tools:\s*$", raw):
            items = []
            for nxt in lines[i + 1:]:
                m = re.match(r"^\s*-\s+(.+?)\s*$", nxt)
                if not m:
                    break
                items.append(m.group(1))
            return items or None
    return None


def problems(text: str, doc: str, repo: Path) -> list[str]:
    out = []
    bad_yaml = lint.yaml_problem(text)
    if bad_yaml or not text.startswith("---"):
        out.append(f"frontmatter does not parse: {bad_yaml or 'no frontmatter'}")
    fm = lint.frontmatter(text)
    if not fm.get("description"):
        out.append("description missing")
    if fm.get("disable-model-invocation", "").lower() != "true":
        out.append("disable-model-invocation: true missing")
    tools = allowed_tools(text)
    if not tools:
        out.append("allowed-tools missing or not a YAML list")
        return out
    for t in tools:
        if t in READ_ONLY:
            continue
        m = re.fullmatch(r"Bash\((.+)\)", t)
        if not m:
            out.append(f"{t}: only Read, Glob, Grep and Bash(<command>) belong here")
            continue
        fixed = re.sub(r"(\s\*|:\*|\*)$", "", m.group(1)).strip()
        if "*" in fixed:
            out.append(f"{t}: a wildcard only at the end")
        if len(fixed.split()) < 2:
            out.append(f"{t}: broad - fix the program and at least one more word")
            continue
        if FORBIDDEN.search(fixed):
            out.append(f"{t}: names a push, a delete, sudo, a force/global flag or a shell operator")
        for p in re.findall(r"(?<![\w/.-])scripts/[\w.-]+", fixed):
            if not (repo / p).is_file():
                out.append(f"{t}: {p} does not exist in the repo")
        if fixed not in doc:
            out.append(f"{t}: ONBOARDING.md does not name '{fixed}'")
    return out


def plant(text: str, entry: str) -> str:
    return text.replace("allowed-tools:\n", f"allowed-tools:\n  - {entry}\n", 1)


def main() -> int:
    if not CMD.is_file():
        print(f"  FAIL the command file is missing: {CMD.relative_to(REPO).as_posix()}")
        print("onboard-command: FAILURES")
        return 1
    real = CMD.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    fail = 0

    got = problems(real, doc, REPO)
    print(f"  {'OK  ' if not got else 'FAIL'} the real file is clean")
    for p in got:
        print(f"       {p}")
    fail |= bool(got)

    # planted defect -> the fragment the finding must carry (the right rule fired, not a stray one)
    planted = {
        "Bash(*)": (plant(real, "Bash(*)"), "broad"),
        "bare Bash": (plant(real, "Bash"), "only Read, Glob, Grep"),
        "Bash(git *)": (plant(real, "Bash(git *)"), "broad"),
        "Bash(rm:*)": (plant(real, "Bash(rm:*)"), "broad"),
        "a push": (plant(real, "Bash(git push origin main)"), "push"),
        "a wildcard in the middle": (plant(real, "Bash(bash * --yes)"), "wildcard only at the end"),
        "a shell operator": (plant(real, "Bash(bash scripts/preflight.sh && echo ok)"), "shell operator"),
        "a missing script": (plant(real, "Bash(bash scripts/no-such-step.sh *)"), "does not exist"),
        "a command ONBOARDING.md does not name":
            (plant(real, "Bash(bash scripts/brain-update.sh *)"), "does not name"),
        "a write tool": (plant(real, "Write"), "only Read, Glob, Grep"),
        "frontmatter a host rejects":
            (real.replace("description: ", "description: Guided: ", 1), "does not parse"),
        "model may start it on its own":
            (real.replace("disable-model-invocation: true\n", "", 1), "disable-model-invocation"),
        "allowlist not a list":
            (re.sub(r"allowed-tools:\n(\s*-.*\n)+", "allowed-tools: Read Grep\n", real, count=1),
             "not a YAML list"),
    }
    for label, (text, want) in planted.items():
        got = problems(text, doc, REPO)
        hit = any(want in p for p in got)
        print(f"  {'OK  ' if hit else 'FAIL'} catches: {label}" + ("" if hit else f" -> {got}"))
        fail |= not hit

    n = 1 + len(planted)
    print(f"onboard-command: all {n} fixtures pass" if not fail else "onboard-command: FAILURES")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
