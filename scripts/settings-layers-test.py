#!/usr/bin/env python3
"""Fixtures for scripts/settings_layers.py, plus the shrink-only list of readers that still carry their own copy.
rc 0 = all pass."""
import json
import os
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import settings_layers as sl  # noqa: E402

fail = 0


def check(name, ok):
    global fail
    fail |= not ok
    print(("ok   " if ok else "FAIL ") + name)


T = Path(tempfile.mkdtemp())
home, root = T / "home", T / "brain"
(home / ".claude").mkdir(parents=True)
(root / ".claude").mkdir(parents=True)
os.environ.pop("CLAUDE_CONFIG_DIR", None)
names = [n for _, n in sl.layers(root, home)]
check("three layers, lowest first: user, project, local", names == ["user", "project", "local"])
check("the user layer is <home>/.claude without CLAUDE_CONFIG_DIR", sl.layers(root, home)[0][0] == home / ".claude" / "settings.json")
os.environ["CLAUDE_CONFIG_DIR"] = str(T / "cfg")
check("CLAUDE_CONFIG_DIR names the user layer", sl.layers(root, home)[0][0] == T / "cfg" / "settings.json")
check("an explicit user folder wins over both", sl.layers(root, home, user=T / "other")[0][0] == T / "other" / "settings.json")
os.environ.pop("CLAUDE_CONFIG_DIR")
(home / ".claude" / "settings.json").write_text(json.dumps({"enabledPlugins": {"a@m": True, "b@m": True}}), encoding="utf-8")
(root / ".claude" / "settings.json").write_text(json.dumps({"enabledPlugins": {"b@m": False}}), encoding="utf-8")
(root / ".claude" / "settings.local.json").write_text(json.dumps({"enabledPlugins": {"c@m": True}}), encoding="utf-8")
check("a later layer wins a key", sl.enabled_plugins(root, home) == {"a@m": True, "b@m": False, "c@m": True})
(root / ".claude" / "settings.local.json").write_text(json.dumps({"enabledPlugins": ["c@m"]}), encoding="utf-8")
bad = []
got = sl.enabled_plugins(root, home, on_bad=lambda p, why: bad.append(why))
check("a list instead of an object is named and skipped", got == {"a@m": True, "b@m": False} and "list" in (bad or [""])[0])
(root / ".claude" / "settings.local.json").write_text("not json", encoding="utf-8")
check("an unreadable layer counts as empty", sl.enabled_plugins(root, home) == {"a@m": True, "b@m": False})

# Shrink-only (2026-11-17): readers of enabledPlugins that still list the layers themselves. A file may leave the list
# (it moved to settings_layers), never join it - a new reader uses the module.
KNOWN = {
    "helpers/mechanism-guard.cjs", "helpers/session-bootup.sh", "helpers/skill-gate.cjs",
    "scripts/auto-fire-coverage.py", "scripts/device-status.py", "scripts/hook-coverage.py",
    "scripts/local-machinery.py", "scripts/mcp-table-check.py",
}
core = HERE.parent
found = set()
for sub in ("helpers", "scripts"):
    for p in (core / sub).iterdir():
        if not p.is_file() or p.name == "settings_layers.py" or p.name.startswith("test-") or "-test." in p.name:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "settings.local.json" in text and "enabledPlugins" in text:
            found.add(f"{sub}/{p.name}")
new = sorted(found - KNOWN)
check("no new reader carries its own layer list" + (f" (new: {', '.join(new)})" if new else ""), not new)
gone = sorted(KNOWN - found)
if gone:
    print("note: moved to settings_layers - drop from KNOWN: " + ", ".join(gone))
sys.exit(fail)
