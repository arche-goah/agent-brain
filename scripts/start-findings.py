#!/usr/bin/env python3
"""start-findings.py — the session start's own findings as tracked entries (writer level).

WHY (operator order 2026-11-12, translated, question tool "Yes, like this"): the session-start findings move to the
writer level so the operator is not flooded and nothing is lost — each finding gets a stable id, an owner and a
counter in a file; the first reply shows ONE count line plus at most three items that need the operator; a finding
that keeps coming back goes loudly to the operator after n sessions. Before (agent-brain #502) every top-level `!!`
line reached the first reply, counted and "handled" in words only: a finding said handled but back at the next start
looked new.

State: <brain>/.claude-state/start-findings.json (instance state, never committed). Per finding:
  id             8 hex of the line with dates, shas and numbers normalised — the same finding keeps its id when
                 a count or an age in it changes; a line ending in a list (`…: a, b`) is keyed by its head
  text, detail   the latest line (without `!!`) and its indented sub-lines
  first_seen, last_seen, sessions_seen (one per distinct session id that saw it, information),
  days_seen, last_day (one per distinct local date that saw it)
  owner          "ai", or "operator" when the line matches an operator pattern (built-ins below, plus the
                 instance's `operator_patterns` in .claude/rules/start-findings.json)
  handled_at, handled_by, handled_how, handled_session   set by `handled`; cleared (and `reopened` counted) when
                 the finding is back at a later session start — a fix that did not hold is not a fix
  closed_at      set when a session start no longer prints it; cleared if it returns
Loud = days_seen >= loud_after_days (data, default 3) and not handled.

Usage:
  start-findings.py record [--root R] [--hook-input JSON] [--full]   bootup body on stdin; with a session id it writes
                     the state and prints the body with the tracked `!!` lines replaced by the brief view; a hand run
                     (no session id), --full or BOOTUP_FULL_FINDINGS=1 print the body unchanged and a hand run writes nothing
  start-findings.py list [--root R] [--owner ai|operator] [--all]   every open finding in full (--all: closed ones too)
  start-findings.py handled <id> --how "<text>" [--by ai|operator] [--root R]
  start-findings.py --brief | brief [--root R]                       the brief view of the current state
Stdlib only; python3 or python. Exit 0 except on a usage error or an unknown id.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

try:  # OS-9: the bootup and open-items-gate.cjs parse this output
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8", newline="\n")  # error lines carry an em dash; cp1252 CI run, 2026-11-12
    sys.stdin.reconfigure(encoding="utf-8")
except Exception:
    pass

# Loud counts DAYS, not sessions: several sessions start on one day, and a session counter made 17 items a start loud
# in the 2026-11-12 replay - the flood the order forbids.
LOUD_AFTER_DAYS = 3
BRIEF_MAX = 3
# A line that names the operator's move. English built-ins; an instance adds its language as data.
OPERATOR = [r"\bask the operator\b", r"\bthe operator'?s (edit|word|call|decision)\b", r"\bneeds? the operator\b"]
# Lines session-audit.py reads back from the transcript as proof of a finished or broken start: printed as they are.
KEEP = re.compile(r"^!! (session-bootup aborted early|session start took)")
FINDING = re.compile(r"^!!\s")
OWN_BLOCK = re.compile(r"^!! open for us:")


def norm(line):
    """The line with every moving part replaced: same finding, same id, whatever count or age it prints today."""
    s = re.sub(r"^!!\s*", "", line.strip())
    s = re.sub(r"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?Z?)?", "<date>", s)
    s = re.sub(r"\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b", "<sha>", s)
    s = re.sub(r"\d+(?:[.,]\d+)?", "<n>", s)
    return re.sub(r"\s+", " ", s).strip().lower()


def key_text(line):
    """What the id is made of. A line whose part after its LAST ": " is a list (holds "," or " | ", or is one
    item without a space) is keyed by its head only: `ledger: 2 open entries …: a, b` and `…: a, c` are one finding
    whose list changed (replay 2026-11-12: one such line split into 21 variants). The list stays in the stored text."""
    s = re.sub(r"^!!\s*", "", line.strip())
    i = s.rfind(": ")
    if i > 0:
        tail = s[i + 2:].strip()
        if tail and ("," in tail or " | " in tail or not re.search(r"\s", tail)):
            s = s[:i]
    return norm(s)


def fid(line):
    return hashlib.sha1(key_text(line).encode("utf-8")).hexdigest()[:8]


def load(p):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def config(root):
    d = load(root / ".claude" / "rules" / "start-findings.json")
    pats = list(OPERATOR)
    for s in d.get("operator_patterns") or []:
        try:
            re.compile(s)
            pats.append(s)
        except re.error:
            pass
    try:
        loud = max(1, int(d.get("loud_after_days", LOUD_AFTER_DAYS)))
    except (TypeError, ValueError):
        loud = LOUD_AFTER_DAYS
    return re.compile("|".join(pats), re.I), loud


def state_path(root):
    return root / ".claude-state" / "start-findings.json"


def save(root, st):
    p = state_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:  # OS-2 / OS-13: pinned, 3.9-safe
        f.write(json.dumps(st, indent=1, ensure_ascii=False) + "\n")
    os.replace(tmp, p)


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def today():
    """The local calendar date; START_FINDINGS_TODAY sets it for fixtures."""
    return os.environ.get("START_FINDINGS_TODAY") or datetime.now().date().isoformat()


def parse(body):
    """[(index, line, [sub-lines])] for every top-level finding outside the open-items block."""
    lines = body.split("\n")
    out = []
    i = 0
    while i < len(lines):
        l = lines[i]
        if FINDING.match(l) and not OWN_BLOCK.match(l):
            j = i + 1
            while j < len(lines) and lines[j][:1] in (" ", "\t") and lines[j].strip():
                j += 1
            out.append((i, j, l, lines[i + 1:j]))
            i = j
            continue
        i += 1
    return lines, out


def session_of(hook_input):
    try:
        return str(json.loads(hook_input or "{}").get("session_id") or "")
    except Exception:
        return ""


def update(st, found, session, op_rx, day=None):
    """Fold this start's findings into the state. A new session counts once, a new local date once; one not seen
    is closed."""
    fs = st.setdefault("findings", {})
    new_session = not session or session != st.get("last_session")
    t = now()
    day = day or today()
    seen = set()
    for _, _, line, sub in found:
        k = fid(line)
        if k in seen:
            continue
        seen.add(k)
        e = fs.get(k)
        fresh = e is None
        if fresh:
            e = fs[k] = {"id": k, "first_seen": t, "sessions_seen": 0}
        e["text"] = re.sub(r"^!!\s*", "", line.strip())
        e["detail"] = [s.strip() for s in sub]
        e["owner"] = "operator" if op_rx.search(line) else "ai"
        if fresh or new_session:
            e["sessions_seen"] = int(e.get("sessions_seen", 0)) + 1
            if e.get("handled_at") and e.get("handled_session") != session:
                e["reopened"] = int(e.get("reopened", 0)) + 1
                e["last_handled"] = {x: e.pop(x) for x in ("handled_at", "handled_by", "handled_how", "handled_session") if x in e}
        if e.get("last_day") != day:
            e["days_seen"] = int(e.get("days_seen", 0)) + 1
            e["last_day"] = day
        e["last_seen"] = t
        e.pop("closed_at", None)
    if new_session:
        for k, e in fs.items():
            if k not in seen and not e.get("closed_at"):
                e["closed_at"] = t
    if session:
        st["last_session"] = session
    return seen


def open_items(st):
    return [e for e in st.get("findings", {}).values() if not e.get("closed_at")]


def brief(st, loud_after, current=None):
    """The count line, up to three operator items, and every loud one."""
    items = [e for e in open_items(st) if current is None or e["id"] in current]
    if not items:
        return []
    loud = [e for e in items if not e.get("handled_at") and int(e.get("days_seen", 0)) >= loud_after]
    oper = [e for e in items if e.get("owner") == "operator" and not e.get("handled_at")]
    key = lambda e: (-int(e.get("days_seen", 0)), -int(e.get("sessions_seen", 0)), e["id"])
    oper.sort(key=key)
    loud.sort(key=key)
    shown_op = oper[:BRIEF_MAX]
    n = len(items)
    head = (f"!! session-start findings: {n} — {len(oper)} need the operator, {len(loud)} back on {loud_after}+ days"
            f" unhandled; the rest are tracked in .claude-state/start-findings.json (say \"{n} session-start findings\";"
            f" all of them: python3 core/scripts/start-findings.py list; mark one: python3 core/scripts/start-findings.py"
            f" handled <id> --how \"...\")")
    out = [head]
    shown = set()
    for e in shown_op + loud:
        if e["id"] in shown:
            continue
        shown.add(e["id"])
        tags = "+".join(t for t, on in (("operator", e in shown_op), ("loud", e in loud)) if on)
        rep = (f"seen on {e.get('days_seen', 0)} days ({e.get('sessions_seen', 0)} sessions), not handled: "
               if e in loud else "")
        out.append(f"!! [finding|{tags}] {e['id']} {rep}{e['text']}")
    if len(oper) > BRIEF_MAX:
        out.append(f"!! [finding|operator] {len(oper) - BRIEF_MAX} more need the operator: python3 core/scripts/start-findings.py list --owner operator")
    return out


def cmd_record(a, root):
    body = sys.stdin.read()
    op_rx, loud_after = config(root)
    lines, found = parse(body)
    session = session_of(a.hook_input)
    st = load(state_path(root))
    current = update(st, found, session, op_rx)
    if session:
        try:
            save(root, st)
        except Exception:
            pass  # an unwritable state must not cost the start its lines
    # A hand run (no session id) is a person at the terminal who wants every line, as brain-check gives it.
    if a.full or os.environ.get("BOOTUP_FULL_FINDINGS") == "1" or not found or not session:
        sys.stdout.write(body)
        return 0
    drop = set()
    for i, j, line, _ in found:
        if not KEEP.match(line):
            drop.update(range(i, j))
    out = []
    first = found[0][0]
    for i, l in enumerate(lines):
        if i == first:
            out.extend(brief(st, loud_after, current))
        if i not in drop:
            out.append(l)
    sys.stdout.write("\n".join(out))
    return 0


def cmd_list(a, root):
    st = load(state_path(root))
    items = list(st.get("findings", {}).values()) if a.all else open_items(st)
    if a.owner:
        items = [e for e in items if e.get("owner") == a.owner]
    for e in sorted(items, key=lambda e: (-int(e.get("sessions_seen", 0)), e["id"])):
        flags = [e.get("owner", "ai"), f"seen on {e.get('days_seen', 0)} days, {e.get('sessions_seen', 0)} sessions"]
        if e.get("handled_at"):
            flags.append(f"handled {e['handled_at'][:10]} by {e.get('handled_by', '?')}: {e.get('handled_how', '')}")
        if e.get("reopened"):
            flags.append(f"back {e['reopened']}x after handled")
        if e.get("closed_at"):
            flags.append(f"closed {e['closed_at'][:10]}")
        print(f"{e['id']} [{' · '.join(flags)}] {e.get('text', '')}")
        for s in e.get("detail") or []:
            print(f"    {s}")
    if not items:
        print("no session-start findings open")
    return 0


def cmd_handled(a, root):
    st = load(state_path(root))
    e = st.get("findings", {}).get(a.id)
    if not e:
        print(f"unknown finding id {a.id} — see: start-findings.py list", file=sys.stderr)
        return 1
    e.update(handled_at=now(), handled_by=a.by, handled_how=a.how, handled_session=st.get("last_session", ""))
    save(root, st)
    print(f"{a.id} handled: {a.how}")
    return 0


def cmd_brief(a, root):
    _, loud_after = config(root)
    for l in brief(load(state_path(root)), loud_after):
        print(l)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    p.add_argument("--brief", action="store_true", help="the brief view (same as the brief command)")
    sub = p.add_subparsers(dest="cmd")
    r = sub.add_parser("record")
    r.add_argument("--hook-input", default="")
    r.add_argument("--full", action="store_true")
    l = sub.add_parser("list")
    l.add_argument("--owner", choices=["ai", "operator"])
    l.add_argument("--all", action="store_true")
    h = sub.add_parser("handled")
    h.add_argument("id")
    h.add_argument("--how", required=True)
    h.add_argument("--by", default="ai", choices=["ai", "operator"])
    b = sub.add_parser("brief")
    for s in (r, l, h, b):
        s.add_argument("--root", default=argparse.SUPPRESS)
    a = p.parse_args(argv)
    root = Path(a.root)
    if a.brief or not a.cmd:
        return cmd_brief(a, root)
    return {"record": cmd_record, "list": cmd_list, "handled": cmd_handled, "brief": cmd_brief}[a.cmd](a, root)


if __name__ == "__main__":
    sys.exit(main())
