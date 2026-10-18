"""plugin_records.py — which install record of a plugin applies to THIS brain.

WHY (measured 2026-10-18): `installed_plugins.json` keeps one record per scope, and project-scope
records of OTHER projects on the same machine sit in the same list. Three readers took the first
record blindly (`rec[0]`): device-status reported a Mac mini's core plugin as 1.3.41 — the record of
a second project — while its own install was 2.0.0; brain-update had the same defect and was fixed in
#8. One function for every reader, so the next one cannot pick a stranger's record again.

Precedence follows Claude Code's own: a record for this brain's project (local or project scope)
over the user record. A record of another project is never this brain's.
"""
import os


def own_record(records, brain):
    """The record that applies to `brain`, or None. `records` = the list under a plugin id."""
    if not records:
        return None
    try:
        here = os.path.realpath(brain) if brain else ""
    except (OSError, ValueError):
        here = ""
    mine = [r for r in records if isinstance(r, dict) and r.get("projectPath")
            and here and os.path.realpath(r["projectPath"]) == here]
    if mine:
        return mine[0]
    user = [r for r in records if isinstance(r, dict) and not r.get("projectPath")]
    return user[0] if user else None
