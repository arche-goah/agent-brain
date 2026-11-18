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


def judge(value, today=None, since_core=None):
    """(counts, why_not) for one declaration value; since_core = the day of the last core update (None: unknown)."""
    today = today or datetime.date.today()
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
        if (today - rev).days > REVIEW_DAYS:
            return False, f"unlimited, last reviewed {rev} - recertify it (judge again, set \"reviewed\" to today)"
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
    print("template_deviation: self-check ok")
