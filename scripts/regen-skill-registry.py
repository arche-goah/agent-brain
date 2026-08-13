#!/usr/bin/env python3
"""Regenerate .claude/skills/REGISTRY.md deterministically from the SKILL.md files.

stdlib-only. Scans every .claude/skills/*/SKILL.md, extracts a name and a short
description (first sentence, capped to ~15 words), groups skills thematically via
an INSTANCE config file (which skills exist and how they group is instance
knowledge, not core mechanics), and writes REGISTRY.md.

Instance config (optional): .claude/skills/registry-groups.json
  { "<GroupName>": ["skill-folder", ...], ... }   — order = output order.
Skills not listed there fall back to the group "Other". No config file =
every skill lands in "Other".

Run from anywhere:  python3 core/scripts/regen-skill-registry.py
"""
from __future__ import annotations

import argparse
import datetime
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
_ap = argparse.ArgumentParser()
_ap.add_argument("--skills", type=Path, default=None,
                 help="skills dir (default: <cwd>/.claude/skills, else the core repo's skills/)")
_args = _ap.parse_args()
if _args.skills:
    SKILLS_DIR = _args.skills.resolve()
elif (Path.cwd() / ".claude" / "skills").is_dir():
    SKILLS_DIR = Path.cwd() / ".claude" / "skills"
else:
    SKILLS_DIR = REPO / "skills"
REGISTRY = SKILLS_DIR / "REGISTRY.md"
GROUPS_FILE = SKILLS_DIR / "registry-groups.json"


def load_groups() -> dict[str, list[str]]:
    if GROUPS_FILE.exists():
        data = json.loads(GROUPS_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return {str(g): [str(s) for s in members] for g, members in data.items()}
    return {}


GROUPS: dict[str, list[str]] = load_groups()

FALLBACK_GROUP = "Other"


def parse_frontmatter(text: str) -> dict[str, str]:
    """Return a flat dict of top-level frontmatter scalars, incl. block scalars."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    block = text[3:end].strip("\n").splitlines()
    fm: dict[str, str] = {}
    i = 0
    key_re = re.compile(r"^([A-Za-z0-9_-]+):(.*)$")
    while i < len(block):
        line = block[i]
        m = key_re.match(line)
        if not m:
            i += 1
            continue
        key, rest = m.group(1), m.group(2).strip()
        if rest in (">", "|", ">-", "|-", ">+", "|+"):
            # block scalar: collect following indented lines
            parts: list[str] = []
            i += 1
            while i < len(block) and (block[i].startswith((" ", "\t")) or block[i] == ""):
                parts.append(block[i].strip())
                i += 1
            fm[key] = " ".join(p for p in parts if p).strip()
            continue
        fm[key] = rest
        i += 1
    return fm


def clean(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return " ".join(value.split())


def first_sentence(desc: str, max_words: int = 15) -> str:
    desc = clean(desc)
    # split off the first sentence on ". " (avoid common abbreviations)
    m = re.search(r"\.(\s|$)", desc)
    sentence = desc[: m.start()] if m else desc
    words = sentence.split()
    if len(words) > max_words:
        return " ".join(words[:max_words]) + " …"
    return sentence


def fallback_description(text: str) -> str:
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#"):
            return first_sentence(line.lstrip("# ").strip())
    return ""


def load_skill(skill_md: Path) -> tuple[str, str, bool]:
    text = skill_md.read_text(encoding="utf-8")
    fm = parse_frontmatter(text)
    name = clean(fm.get("name", "")) or skill_md.parent.name
    desc_raw = fm.get("description", "").strip()
    if desc_raw:
        return name, first_sentence(desc_raw), True
    return name, fallback_description(text), False


def main() -> None:
    skills: dict[str, tuple[str, str, bool]] = {}
    for skill_md in SKILLS_DIR.glob("*/SKILL.md"):
        folder = skill_md.parent.name
        skills[folder] = load_skill(skill_md)

    total = len(skills)
    grouped: dict[str, list[str]] = {g: [] for g in GROUPS}
    grouped[FALLBACK_GROUP] = []
    assigned: set[str] = set()
    for group, members in GROUPS.items():
        for folder in members:
            if folder in skills:
                grouped[group].append(folder)
                assigned.add(folder)
    for folder in skills:
        if folder not in assigned:
            grouped[FALLBACK_GROUP].append(folder)

    today = datetime.date.today().isoformat()
    no_desc = sorted(f for f, (_, d, _) in skills.items() if not d)

    lines: list[str] = []
    lines.append("# Skill Registry")
    lines.append("")
    lines.append(f"**Total skills:** {total}")
    lines.append(f"**Generated:** {today}")
    lines.append("")
    lines.append(
        "> Auto-generated from the `.claude/skills/*/SKILL.md` files via "
        "`core/scripts/regen-skill-registry.py` — **do not maintain by hand**. "
        "Re-run the script after changing a skill."
    )
    lines.append("")
    lines.append(
        "Claude Code discovers skills automatically from `.claude/skills/*/SKILL.md` "
        "(each with YAML frontmatter `name` + `description`). This registry is the "
        "human-readable overview."
    )
    lines.append("")

    order = list(GROUPS.keys())
    if grouped[FALLBACK_GROUP]:
        order.append(FALLBACK_GROUP)

    for group in order:
        members = sorted(grouped[group])
        if not members:
            continue
        lines.append(f"## {group} ({len(members)})")
        lines.append("")
        lines.append("| Skill | Short description |")
        lines.append("|-------|--------------------|")
        for folder in members:
            name, desc, _ = skills[folder]
            desc = desc.replace("|", "\\|") or "—"
            lines.append(f"| {name} | {desc} |")
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append(f"**{total} skills** across {len([g for g in order if grouped[g]])} groups.")
    if no_desc:
        lines.append("")
        lines.append(
            "Skills without a frontmatter `description` (fallback = H1 title): "
            + ", ".join(f"`{s}`" for s in no_desc)
        )
    lines.append("")

    # newline is not optional: text mode translates "\n" to the platform separator, so
    # the same command wrote CRLF on Windows and LF on macOS (measured 2026-08-10:
    # 12 CR lines in a freshly generated REGISTRY.md).
    REGISTRY.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"Wrote {REGISTRY} — {total} skills across {len([g for g in order if grouped[g]])} groups.")
    if no_desc:
        print("No description (H1 fallback):", ", ".join(no_desc))


if __name__ == "__main__":
    main()
