#!/usr/bin/env python3
"""Open items: every unhandled point that concerns this instance, LOUDER with every repeat.

WHY (operator correction 2026-10-07, proving brain): the session start listed nine open
shared-memory requests to this instance and six open PRs — and the first reply of the
session relayed none of them ("nine older requests, nothing new since the last start").
The data side had been fixed two days earlier (the open-request list ignores the cursor,
"seen is not done"); the relay side never was. Operator, verbatim: "IMMER wenn es
unbehandelte punkte die uns betreffen gibt, MUSST du das berichten ... wenn es eine
session davor schon berichtet hat und wir haben nicht darauf eingegangen ... muss das
weiterhin berichtet werden ... aufmerksamkeit muss sich erhöhen, nicht verringern."

So this script is the ONE list of open points at session start:
  * open shared-memory requests addressed to this instance (shared-memory-inbox --open,
    no cursor), and every open PR under the ecosystem owner;
  * per item, how many sessions already reported it and since when — a per-machine
    counter in .claude-state/open-items-seen.json (gitignored), keyed by session id, so
    a resume or a compaction of the same session never counts twice;
  * a source that could not be read says so — it never reads as "nothing open";
  * "nothing open" is said explicitly when both sources were read and nothing is open.
helpers/open-items-gate.cjs (Stop) then blocks a first reply that leaves an item out.

Items that vanish (answered, merged, closed) take their counter with them. Parked
domains stay on one line, never dropped: instance data `.claude/rules/open-items.json`,
key "parked" = list of regexes matched against request topic / PR repo.

Usage (from helpers/session-bootup.sh):
  open-items.py --owner <org> [--hook-input '<SessionStart JSON>'] [--repo <shared-memory>]
Stdlib only; runs under `python3` or `python` (Windows python.org installer).
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LINE = re.compile(r"^\s*-\s+(\d{4}-\d{2}-\d{2})\s+\[([^\]]+)\]\s+([^:]+):\s+(.*?)\s*\(([^()]+\.md|LOG)\)\s*$")
# The inbox defaults to a 30-day window. An open request does not stop being open because
# it is old — measured 2026-10-07: a 32-day-old request to this instance fell out of the
# start list silently. Age is what the counter shows, not a reason to drop the item.
NO_WINDOW = "36500"


def run(cmd, cwd=None, timeout=25):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout, cwd=cwd)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, str(e)


def requests(repo):
    """[] = read and empty, None = could not read. Not cloned = not taking part = []."""
    if not (Path(repo) / ".git").is_dir():
        return []
    rc, out = run([sys.executable, str(HERE / "shared-memory-inbox.py"), "--open", "--repo", repo,
                   "--days", NO_WINDOW, "--max", "100000"])
    if rc != 0:
        return None
    # The inbox's own count is the measurement; the parsed lines must match it. "not checked"
    # (no SHARED_MEMORY_SELF), a capped list, or a line the parser misses all end here as a
    # failed read — never as "nothing open".
    m = re.search(r"open requests to this instance: (\d+)", out)
    if not m:
        return None
    expected = int(m.group(1))
    items, unparsed = [], 0
    for line in out.splitlines():
        if not line.lstrip().startswith("- "):
            continue
        m = LINE.match(line)
        if not m:
            unparsed += 1
            continue
        date, topic, von, text, rel = m.groups()
        # A LOG-only request has no file; its identity is date + sender + its own words.
        ref = rel if rel != "LOG" else f"{topic}/LOG {date} {von.strip()}"
        items.append({"id": ref if rel != "LOG" else f"{ref}: {text[:40]}", "kind": "request",
                      "date": date, "who": von.strip(), "text": text[:100], "scope": topic, "ref": ref})
    # An inbox line this parser cannot read must not vanish — the exact defect this list
    # exists to stop. It reports itself as a failed read instead.
    return None if unparsed or len(items) != expected else items


def prs(owner):
    if not owner:
        return []
    rc, out = run(["gh", "search", "prs", "--owner", owner, "--state", "open", "--limit", "50",
                   "--json", "repository,number,title,author,updatedAt,isDraft"])
    if rc != 0:
        return None
    try:
        rows = json.loads(out or "[]")
    except ValueError:
        return None
    return [{"id": f"{p['repository']['name']}#{p['number']}", "kind": "PR",
             "date": p["updatedAt"][:10], "updated": p["updatedAt"],
             "who": (p.get("author") or {}).get("login", "?"),
             "text": p["title"][:100] + (" (draft)" if p.get("isDraft") else ""),
             "scope": p["repository"]["name"], "ref": f"{p['repository']['name']}#{p['number']}"}
            for p in rows]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default="")
    ap.add_argument("--hook-input", default="")
    ap.add_argument("--repo", default=os.environ.get(
        "SHARED_MEMORY_REPO", str(Path.home() / "Projects" / "brain-shared-memory")))
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR", "."))
    a = ap.parse_args()

    root = Path(a.root)
    try:
        hook = json.loads(a.hook_input) if a.hook_input.strip() else {}
    except ValueError:
        hook = {}
    now = datetime.datetime.now()
    # No session id (run by hand): one bucket per hour, so a hand run does not inflate
    # the counter session after session.
    sid = hook.get("session_id") or now.strftime("hand-%Y%m%d%H")
    try:
        parked_rx = [re.compile(p, re.I) for p in json.loads(
            (root / ".claude" / "rules" / "open-items.json").read_text(encoding="utf-8")).get("parked", [])]
    except (OSError, ValueError, re.error):
        parked_rx = []

    state_dir = root / ".claude-state"
    seen_file = state_dir / "open-items-seen.json"
    try:
        seen = json.loads(seen_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        seen = {}
    old, last_run = seen.get("items", {}), seen.get("last_run", "")

    req, pr = requests(a.repo), prs(a.owner)
    failed = [name for name, v in (("shared-memory requests", req), ("PR search", pr)) if v is None]
    items = (req or []) + (pr or [])

    today = now.date().isoformat()
    keep = {}
    for it in items:
        rec = old.get(it["id"]) or {"first": today, "sessions": []}
        if sid not in rec["sessions"]:
            rec["sessions"] = (rec["sessions"] + [sid])[-50:]
        keep[it["id"]] = rec
        it["first"], it["n"] = rec["first"], len(rec["sessions"])
        it["parked"] = any(r.search(it["scope"]) for r in parked_rx)
    # A source that failed keeps its old counters — a failed read is not "handled".
    for k, v in old.items():
        if k not in keep and ((req is None and "#" not in k) or (pr is None and "#" in k)):
            keep[k] = v
    saved = True
    try:
        state_dir.mkdir(parents=True, exist_ok=True)
        seen_file.write_text(json.dumps({"items": keep, "last_run": now.isoformat(timespec="seconds")},
                                        indent=1), encoding="utf-8")
    except OSError:
        saved = False  # the list still prints; the lost escalation is said out loud below

    active = sorted((i for i in items if not i["parked"]), key=lambda i: (-i["n"], i["date"]))
    parked = [i for i in items if i["parked"]]
    head = f"open for us: {len(active)}" + (f" (+{len(parked)} parked)" if parked else "")
    print(f"{head} — EVERY item goes into the first reply, with its age; a repeat is louder, never quieter")
    if not saved:
        print(f"!! open for us: repeat counter NOT saved ({seen_file}) — repeats will not get louder")
    for name in failed:
        print(f"!! open for us: {name} NOT checked — this is not 'nothing open'; re-run core/scripts/open-items.py")
    if not items and not failed:
        print("- nothing open (requests and PRs both read)")
    for i in active:
        age = (f"!! reported in {i['n']} sessions since {i['first']}, nothing done yet"
               if i["n"] > 1 else "first report")
        moved = " · updated since last start" if i["kind"] == "PR" and last_run and i["updated"] > last_run else ""
        print(f"- [{i['kind']}] {i['date']} {i['ref']} — {i['who']}: {i['text']} — {age}{moved}")
    if parked:
        print(f"- [parked] {', '.join(i['ref'].rsplit('/', 1)[-1] for i in parked)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
