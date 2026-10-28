#!/usr/bin/env python3
"""Fixture test for skill-lint.py check 8 (evidence): a dated incident story belongs in the
closing `## Evidence` section of a SKILL.md, never inside an instruction step.

Both directions: every planted story form must be flagged in a step, and the same lines must
stay silent under `## Evidence`, inside fenced code, in the frontmatter, and as short
lowercase origin stamps ("(measured 2026-10-11)", "(since 2026-08-10)"). An Evidence section
followed by another `## ` section is flagged as not last.
Usage: python3 scripts/skill-lint-evidence-test.py   (exit 0 = all pass)
"""
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("skill_lint", Path(__file__).with_name("skill-lint.py"))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)

FM = "---\nname: x\ndescription: Measured 2026-08-17 in the description is not a step.\n---\n\n# X\n\n## Steps\n\n"

STORIES = [
    "1. Do A. Measured 2026-08-17: three merged PRs corrected a claim.",
    "> a document every instance follows. Measured on 2026-08-17 against two PRs:",
    "visible from the diff. Measured again 2026-10-24 over 188 PRs.",
    "**The incident that forced this (collaborating instance, 2026-09-11):** permission",
    "⚠ **INCIDENT 2026-08-01 that forced this gate:** The session changed a port.",
    "> **Why this skill exists (incident 2026-08-02):** The operator ordered a run.",
    "\"Forgot\" is not a reason — the 2026-08-01 incident (70 files uncommitted)",
    "checked\". On 2026-08-01 the full audit ran on the same day.",
]
SILENT_IN_STEPS = [
    "2. Do B (operator order 2026-08-17).",
    "3. Do C (since 2026-08-10).",
    "worktree under the scratchpad (measured 2026-10-11 on a Windows instance).",
    "Price (measured 2026-10-26, macOS instance): a node run.",
    "the self-assessment was off by one hour on 2026-08-02).",
    "Measured on the proving brain: 13 of 68 were already done.",
    "An incident report goes to the ledger.",
]


def evidence_tail(lines):
    return "\n## Evidence\n\n" + "".join(f"- {l}\n" for l in lines)


fail = 0


def check(label, got, want):
    global fail
    ok = got == want
    print(f"  {'OK  ' if ok else 'FAIL'} {label}" + ("" if ok else f" -> got {got}, want {want}"))
    fail |= not ok


for s in STORIES:
    hits, not_last = lint.story_lines(FM + s + "\n")
    check(f"flags in a step: {s[:60]}", (len(hits), not_last), (1, False))
for s in SILENT_IN_STEPS:
    hits, _ = lint.story_lines(FM + s + "\n")
    check(f"silent in a step: {s[:60]}", len(hits), 0)

hits, not_last = lint.story_lines(FM + "1. Do A (why: Evidence, 2026-08-17).\n" + evidence_tail(STORIES))
check("silent: every story under a closing '## Evidence'", (hits, not_last), ([], False))

hits, _ = lint.story_lines(FM + "```\nMeasured 2026-08-17: example output\n```\n")
check("silent: a story form inside fenced code", hits, [])

hits, not_last = lint.story_lines(FM + evidence_tail(STORIES[:1]) + "\n## Later\n\n" + STORIES[0] + "\n")
check("flags: '## Evidence' not last, and the story after it", (len(hits), not_last), (1, True))

hits, _ = lint.story_lines(FM + "### Evidence\n\n" + STORIES[0] + "\n")
check("flags: a level-3 'Evidence' heading is not the section", len(hits), 1)

hits, _ = lint.story_lines(FM + STORIES[0] + "\n")
check("reports the file line number", hits[0][0] if hits else None, 10)

print("skill-lint evidence: all fixtures pass" if not fail else "skill-lint evidence: FAILURES")
raise SystemExit(1 if fail else 0)
