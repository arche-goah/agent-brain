#!/usr/bin/env python3
"""Auto-fire coverage: which enabled plugin skills the instance's auto-fire table omits.

WHY: `.claude/rules/intelligence-instance.md` is the ONLY pattern -> skill source of a
brain (core/rules/intelligence.md), and it is hand-maintained. A skill that ships with
a plugin update reaches the table only if someone remembers to add a row — and nobody
does: measured on the Windows instance, brain-scans of 2026-08-04, 2026-08-13 and
2026-09-24 each found the table short (the last one: `shared-memory-tidy`,
`shared-memory-watch`, `pr-live-verify`). Three recurrences after a fix is the build
threshold. The scan caught it every time, but only every few weeks; this check runs
at every session start. It NEVER edits — which pattern fires a skill is a judgement
the table's author makes, not something a script can derive.

WHAT COUNTS AS MISSING: every `skills/<name>/SKILL.md` of an installed AND enabled
plugin (enabledPlugins in project or user settings — same rule as the bootup's
output-style check), addressed as `<plugin.json name>:<skill>`, that does not occur
verbatim in the table file. Skipped: skills whose description starts with
`DEPRECATED` (rename pointers — their successor is the one to list), and ids named
in an `<!-- auto-fire-ignore: id id ... -->` comment in the table file (a skill the
brain deliberately does not auto-fire; a plugin name alone ignores all its skills).

Usage: auto-fire-coverage.py [brain-root]     (default: cwd)
Output: one line per missing skill id. Exit 0 and silent when covered or when the
brain has no table file; exit 1 when something is missing.
Caller: helpers/session-bootup.sh (!! line each session).
"""
import json
import os
import re
import sys
from pathlib import Path


def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return {}


def description(skill_md):
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError:
        return ""
    m = re.search(r"^description:\s*[\"']?(.*)$", text, re.M)
    return m.group(1) if m else ""


def missing(root):
    table_file = root / ".claude" / "rules" / "intelligence-instance.md"
    if not table_file.is_file():
        return []
    table = table_file.read_text(encoding="utf-8")
    ignored = set()
    for m in re.finditer(r"<!--\s*auto-fire-ignore:(.*?)-->", table, re.S):
        ignored.update(m.group(1).split())

    cfg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    enabled = {k for s in (load(root / ".claude" / "settings.json"), load(cfg / "settings.json"))
               for k, v in (s.get("enabledPlugins") or {}).items() if v}
    out = []
    for pid, entries in (load(cfg / "plugins" / "installed_plugins.json").get("plugins") or {}).items():
        if pid not in enabled or not entries:
            continue
        path = Path((entries[0].get("installPath") or "").replace("\\", "/"))
        name = load(path / ".claude-plugin" / "plugin.json").get("name")
        if not name or name in ignored:
            continue
        for skill_md in sorted(path.glob("skills/*/SKILL.md")):
            sid = f"{name}:{skill_md.parent.name}"
            if sid in ignored or sid in table or description(skill_md).startswith("DEPRECATED"):
                continue
            out.append(sid)
    return out


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    gaps = missing(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve())
    for sid in gaps:
        print(sid)
    sys.exit(1 if gaps else 0)
