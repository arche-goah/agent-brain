"""settings_layers.py - the ONE reader of the Claude Code settings layers a brain's scripts look at.

Layers, lowest first (a later layer wins a key): user (`$CLAUDE_CONFIG_DIR/settings.json`, default
`~/.claude/settings.json`), project (`<root>/.claude/settings.json`), local (`<root>/.claude/settings.local.json`).

WHY (review of #554, follow-up item 4, measured 2026-11-17): ten scripts and helpers each carried their own list of
these files, and they had drifted - ecosystem-sync.py honoured CLAUDE_CONFIG_DIR for the user layer, local-machinery.py
read a fixed `~/.claude`, and the order differed between them. A copy per reader answers one question several ways.
The copies not yet moved here (Node gates, shell scripts, more Python) stand in a shrink-only list in
scripts/settings-layers-test.py - a new copy fails it.
"""
import json
import os
from pathlib import Path


def user_dir(home=None):
    """The user's Claude config folder: CLAUDE_CONFIG_DIR, else <home>/.claude."""
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    if env:
        return Path(env)
    return Path(home or Path.home()) / ".claude"


def layers(root, home=None, user=None):
    """[(path, name)] lowest first: user, project, local. `user` names the user folder outright (a reader that
    diagnoses another machine's copy)."""
    root = Path(root)
    return [((Path(user) if user else user_dir(home)) / "settings.json", "user"),
            (root / ".claude" / "settings.json", "project"),
            (root / ".claude" / "settings.local.json", "local")]


def read(path):
    """The JSON object of one layer, {} when it is missing or unreadable, None when it is not an object."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else None


def enabled_plugins(root, home=None, on_bad=None):
    """{plugin_id: bool} merged over the layers (a later layer wins). `on_bad(path, why)` hears a layer whose
    enabledPlugins is no object - Claude Code ignores it."""
    out = {}
    for path, _ in layers(root, home):
        data = read(path)
        if data is None:
            if on_bad:
                on_bad(path, "the file is no JSON object")
            continue
        ep = data.get("enabledPlugins") or {}
        if not isinstance(ep, dict):
            if on_bad:
                on_bad(path, f"`enabledPlugins` is a {type(ep).__name__}, not an object")
            continue
        for k, v in ep.items():
            out[k] = bool(v)
    return out
