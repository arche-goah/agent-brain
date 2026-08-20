#!/usr/bin/env python3
"""Hook coverage: which hooks the core template wires that this brain does not.

WHY: templates/settings.json only reaches a brain ONCE, at bootstrap. A hook added
to the template later (v1.3.12: the class-gate Stop hook) reaches existing brains
solely as a CHANGELOG sentence — and a brain that misses that sentence stays
silently half-functional: the helper ships, updates, passes every smoke check, and
never runs. Measured 2026-08-19 on the Windows instance: class-gate.cjs consumed
with v1.3.12, wired nowhere. This script makes the gap loud; it NEVER edits —
settings.json is operator territory (an agent cannot extend its own wiring).

WHAT COUNTS AS MISSING: a template hook command that points at core/helpers/<file>,
where <file> exists in the consumed core state, and no hook command under the SAME
event in the brain's settings (project, project-local or user scope) references
that helper file. Matching is by helper filename, so path notation (slashes,
$CLAUDE_PROJECT_DIR vs absolute) never causes a false alarm.

Usage: hook-coverage.py [brain-root]           (default: cwd)
Output: one line per missing hook — "<event>: <template command>".
Exit 0 and silent when covered; exit 1 when something is missing.
Callers: helpers/session-bootup.sh (!! line each session) and
scripts/brain-update.sh (WARN in the release catch-up).
"""
import json
import os
import re
import sys


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def commands_by_event(settings):
    out = {}
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups or []:
            if not isinstance(group, dict):
                continue
            for h in group.get("hooks") or []:
                cmd = h.get("command") if isinstance(h, dict) else None
                if cmd:
                    out.setdefault(event, []).append(cmd)
    return out


def registered_via_dispatcher(root, wired):
    """Helpers a wired dispatcher runs on the brain's behalf.

    The claim is only accepted when BOTH halves hold: a dispatcher is actually wired in
    settings, AND the helper is registered in its config. Either half alone would turn
    this into a way to silence the check by writing a file.
    """
    if not any("dispatcher" in c for cmds in wired.values() for c in cmds):
        return set()
    cfg = load(os.path.join(root, ".claude", "rules", "stop-checks.json"))
    out = set()
    for check in cfg.get("checks") or []:
        cmd = check.get("cmd") if isinstance(check, dict) else None
        if cmd:
            out.add(os.path.basename(cmd))
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    template = load(os.path.join(root, "core", "templates", "settings.json"))
    if not template:
        return 0  # no consumed template (not a brain, or pre-template core): nothing to demand

    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    wired = {}
    for p in (
        os.path.join(root, ".claude", "settings.json"),
        os.path.join(root, ".claude", "settings.local.json"),
        os.path.join(cfg, "settings.json"),
    ):
        for event, cmds in commands_by_event(load(p)).items():
            wired.setdefault(event, []).extend(cmds)

    # A helper can be wired INDIRECTLY: a dispatcher hook runs several checks itself
    # and the settings then name only the dispatcher. Matching on filenames alone
    # reports those as missing — measured 2026-08-20 on an instance that consolidated
    # seven Stop hooks into one: two live helpers were reported missing every session,
    # and a warning that is always there stops being a signal.
    dispatched = registered_via_dispatcher(root, wired)

    missing = []
    for event, cmds in commands_by_event(template).items():
        for cmd in cmds:
            m = re.search(r"core/helpers/([\w.-]+)", cmd)
            if not m:
                continue  # template command outside core/helpers: not this check's contract
            helper = m.group(1)
            if not os.path.isfile(os.path.join(root, "core", "helpers", helper)):
                continue  # helper not in the consumed core yet: nothing to wire
            if any(helper in c for c in wired.get(event, [])):
                continue
            if helper in dispatched:
                continue  # runs behind a dispatcher, see registered_via_dispatcher()
            missing.append("%s: %s" % (event, cmd))

    for line in missing:
        print(line)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
