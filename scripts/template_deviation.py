"""One reader of `permissions._template_deviations` (a brain's declared departures from the core settings template).

Operator rule 2026-11-18 (macOS instance, translated): "avoid core drift as far as possible; declared deviations are, as
a rule, time-limited alphas; an unlimited deviation must be explained especially well and be re-checked at intervals -
'recertified' as a local deviation". So a declaration counts only in one of two forms:
  {"until": "YYYY-MM-DD", "why": "..."}                       time-limited (the default): counts until that day
  {"reviewed": "YYYY-MM-DD", "why": "<at least 80 chars>"}    unlimited: counts while the review is at most 90 days old
A bare string (the older form) or a dict without a valid date counts as NOT declared - the reader names it, so the
brain gives it a date. Used by template-drift.py and hook-coverage.py; the same 90 days as local-machinery.py."""
import datetime
import re

REVIEW_DAYS = 90
MIN_WHY = 80
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _day(s):
    s = str(s or "").strip()
    if not DATE.match(s):
        return None
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        return None


def core_updated(brain):
    """The day the brain's core pin last moved (`git log` of the `core` submodule pointer), None when unknown.
    Operator rule 2026-11-18 (translated): "90 days, plus at every core update check local deviations without an expiry"."""
    import subprocess
    try:
        out = subprocess.run(["git", "-C", str(brain), "log", "-1", "--format=%cs", "--", "core"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return None
    return _day(out)


def core_touched(brain):
    """The core paths the brain's last pin move changed (`git diff --name-only` between the two submodule pointers), None
    when unknown. Agreed between the instances 2026-11-18 (drift scan): after a core update only what the pin diff touches
    becomes due, the rest keeps its own cadence - "all due after every update" never emptied a queue of 115."""
    import subprocess
    run = lambda *a: subprocess.run(["git", *a], capture_output=True, text=True, timeout=15).stdout.strip()  # noqa: E731
    try:
        commits = run("-C", str(brain), "log", "-2", "--format=%H", "--", "core").split()
        if len(commits) < 2:
            return None
        new, old = (run("-C", str(brain), "rev-parse", f"{c}:core") for c in commits)
        out = run("-C", f"{brain}/core", "diff", "--name-only", old, new)
    except Exception:
        return None
    return set(out.split()) if out else None


# Operator 2026-11-18 (translated): "how often should a re-review per deviation take place". The writer proposes
# `review_every_days`; a rule by path sets the ceiling it cannot exceed (agreed with the other instance the same day):
# what touches a hook, a gate, permissions or a live path at most 30 days, docs and data at most 180, the rest 90.
LIVE = re.compile(r"hooks?/|gate|helpers/|settings|permission|mcp|Bash\(|PowerShell\(", re.I)
DOCS = re.compile(r"(^|/)docs?/|\.md$|(^|/)data/", re.I)


def ceiling(key):
    return 30 if LIVE.search(str(key)) else 180 if DOCS.search(str(key)) else REVIEW_DAYS


def cadence(key, value):
    """Days between two reviews of THIS deviation: its own `review_every_days`, never above the path's ceiling."""
    try:
        own = int((value or {}).get("review_every_days") or 0) if isinstance(value, dict) else 0
    except (TypeError, ValueError):
        own = 0
    cap = ceiling(key)
    return min(own, cap) if own > 0 else min(REVIEW_DAYS, cap)


def touches(key, touched):
    """Whether a pin diff touches this deviation: a path-like key whose file name the diff changes. A key that is no path
    (`~/...`, a `plugin:` id, a permission rule) keeps its own cadence - the diff says nothing about it."""
    k = str(key)
    if touched is None or k.startswith(("~", "plugin:")) or "(" in k or ("/" not in k and "." not in k):
        return False
    base = k.rstrip("/").rsplit("/", 1)[-1]
    return any(t.rsplit("/", 1)[-1] == base for t in touched)


def judge(value, today=None, since_core=None, key="Bash(", touched=None):
    """(counts, why_not) for one declaration value; since_core = the day of the last core update (None: unknown).
    A template deviation is a permission rule; it becomes due with a core update only when the pin diff touches the
    settings template (touched = core_touched(); None = unknown, then every update counts, as before)."""
    today = today or datetime.date.today()
    if since_core is not None and touched is not None and "templates/settings.json" not in touched:
        since_core = None
    if not isinstance(value, dict):
        return False, "no date (a bare text): give it \"until\" (time-limited) or \"reviewed\" with a full \"why\""
    why = str(value.get("why") or "").strip()
    until = _day(value.get("until"))
    if until is not None:
        return (True, "") if until >= today else (False, f"expired {until} - merge into the core, extend with a reason, or drop it")
    rev = _day(value.get("reviewed"))
    if rev is not None:
        if len(why) < MIN_WHY:
            return False, f"unlimited, but its \"why\" has {len(why)} characters - an unlimited deviation is explained in full"
        days = cadence(key, value)
        if (today - rev).days > days:
            return False, f"unlimited, last reviewed {rev}, its cadence is {days} days - recertify it (judge again, set \"reviewed\" to today)"
        if since_core is not None and rev < since_core:
            return False, f"unlimited, reviewed {rev} before the core update of {since_core} - recertify it against the new core"
        return True, ""
    return False, "neither \"until\" nor \"reviewed\" holds a date"


def declared(permissions, today=None, since_core=None):
    """{rule: (counts, why_not)} for every key of permissions._template_deviations (keys starting with _ are notes)."""
    dev = (permissions or {}).get("_template_deviations") or {}
    return {k: judge(v, today, since_core) for k, v in dev.items() if isinstance(dev, dict) and not str(k).startswith("_")}


def counts(permissions, today=None, since_core=None):
    """The set of rules whose declaration counts today."""
    return {k for k, (ok, _w) in declared(permissions, today, since_core).items() if ok}


if __name__ == "__main__":
    d = datetime.date(2026, 11, 18)
    assert judge("a reason", d)[0] is False
    assert judge({"until": "2026-12-01", "why": "x"}, d)[0] is True
    assert judge({"until": "2026-11-01", "why": "x"}, d)[0] is False
    assert judge({"reviewed": "2026-11-01", "why": "y" * 80}, d)[0] is True
    assert judge({"reviewed": "2026-11-01", "why": "short"}, d)[0] is False
    assert judge({"reviewed": "2026-07-01", "why": "y" * 80}, d)[0] is False
    assert judge({"why": "y" * 80}, d)[0] is False
    assert judge({"reviewed": "2026-11-01", "why": "y" * 80}, d, datetime.date(2026, 11, 10))[0] is False  # core moved since
    assert judge({"reviewed": "2026-11-12", "why": "y" * 80}, d, datetime.date(2026, 11, 10))[0] is True
    assert judge({"until": "2026-12-01", "why": "x"}, d, datetime.date(2026, 11, 17))[0] is True  # alphas keep their date
    # cadence per deviation, capped by the path rule (2026-11-18)
    assert cadence("scripts/hooks/x.cjs", {}) == 30 and cadence("docs/x.md", {}) == 90 and cadence("docs/x.md", {"review_every_days": 400}) == 180
    assert cadence("scripts/x.py", {"review_every_days": 14}) == 14 and cadence("Bash(git push *)", {"review_every_days": 90}) == 30
    assert judge({"reviewed": "2026-10-01", "why": "y" * 80}, d)[0] is False  # a permission rule: 48 days > 30
    assert judge({"reviewed": "2026-10-01", "why": "y" * 80}, d, key="docs/notes.md")[0] is True  # docs: 48 days <= 90
    # after a core update only a touched deviation is due
    assert touches("scripts/hooks/watch-gate.cjs", {"helpers/watch-gate.cjs"}) and not touches("scripts/hooks/watch-gate.cjs", {"helpers/x.cjs"})
    assert not touches("~/Projects/x", {"x"}) and not touches("plugin:show-tools", {"show-tools"})
    assert judge({"reviewed": "2026-11-12", "why": "y" * 80}, d, datetime.date(2026, 11, 15), touched={"helpers/x.cjs"})[0] is True
    assert judge({"reviewed": "2026-11-12", "why": "y" * 80}, d, datetime.date(2026, 11, 15), touched={"templates/settings.json"})[0] is False
    print("template_deviation: self-check ok")
