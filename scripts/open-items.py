#!/usr/bin/env python3
"""Open items: every unhandled point that concerns this instance — sorted by WHO must act,
LOUDER with every repeat.

WHY (operator correction 2026-10-07, proving brain): the session start listed nine open
shared-memory requests to this instance and six open PRs — and the first reply of the
session relayed none of them ("nine older requests, nothing new since the last start").
The data side had been fixed two days earlier (the open-request list ignores the cursor,
"seen is not done"); the relay side never was. The operator's rule, in English: every
unhandled point that concerns us MUST be reported; if there is truly nothing, say so; a
point an earlier session already reported that is still open keeps being reported —
attention has to rise with every repeat, not fall.

Refined the same day: a wall of open points at session start intimidates, and a session
usually starts for another reason. So the first reply SPLITS them by who has to act:
  * `ai`    — the agent can answer or handle it itself (its own circle: one AI alone, or
              the AIs of several sides). The reply gives the count and asks ONCE whether to
              go ahead — without that OK the agent starts none of it.
  * `human` — it needs the operator directly. Up to three: one short bullet each (what it
              is about, who needs what). More than three: the count, and an offer to list.

This script is the ONE list of open points at session start:
  * open shared-memory requests addressed to this instance (shared-memory-inbox --open,
    no cursor, no age window), and every open PR under the ecosystem owner;
  * per item a class — automatic where the data says it (`circle:` A/C = ai, B/D/E/F =
    human; a request addressed to a human by name = human; a PR = ai), otherwise the
    agent classifies it ONCE (`--classify`), kept per machine in
    .claude-state/open-items-class.json; an item nobody classified is printed as `?` and
    the Stop gate blocks the first reply until it is classified;
  * per item, how many sessions already reported it and since when — a per-machine
    counter in .claude-state/open-items-seen.json, keyed by session id, so a resume or a
    compaction of the same session never counts twice;
  * a source that could not be read says so — it never reads as "nothing open";
  * "nothing open" is said explicitly when both sources were read and nothing is open.
helpers/open-items-gate.cjs (Stop) then checks the first reply against this list.

Items that vanish (answered, merged, closed) take their counter and class with them.
Instance data `.claude/rules/open-items.json`: "parked" (regexes on request topic / PR
repo — parked domains stay on one line, never dropped) and "humans" (names a request can
address the operator by, e.g. "an <name>").

Usage:
  open-items.py --owner <org> [--hook-input '<SessionStart JSON>'] [--repo <shared-memory>]
  open-items.py --classify '<id>=ai|human[:why]' [...]      (id: as printed, or its file name)
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
CIRCLE = re.compile(r"^\s+circle:\s*([A-Fa-f])\b", re.M)
AI_CIRCLES = {"A", "C"}  # one AI alone · the AIs of several sides — everything else has a human in it


def run(cmd, cwd=None, timeout=25):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout, cwd=cwd)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, str(e)


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def save_json(path, data):
    """True on success. OS-2: pinned line ending, so the file reads the same everywhere."""
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
        return True
    except OSError:
        return False


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
                      "date": date, "who": von.strip(), "text": text[:100], "scope": topic,
                      "ref": ref, "file": rel if rel != "LOG" else ""})
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


def auto_class(it, repo, human_rx):
    """(class, why) from the data alone, or (None, '') when the data does not say."""
    if it["kind"] == "PR":
        return "ai", "PR: review/merge is agent work"
    if it.get("file"):
        rc, blob = run(["git", "-C", repo, "show", f"origin/main:{it['file']}"])
        m = CIRCLE.search(blob.split("\n---", 1)[0]) if rc == 0 else None
        if m:
            c = m.group(1).upper()
            return ("ai" if c in AI_CIRCLES else "human"), f"circle {c}"
    if human_rx and human_rx.search(it["text"]):
        return "human", "addressed to a person"
    return None, ""


def lookup(store, it):
    """The agent's own class wins; it is keyed by the printed id or by the file name."""
    return store.get(it["id"]) or store.get(it["ref"].rsplit("/", 1)[-1])


def classify(args, cls_file):
    store = load_json(cls_file, {})
    today = datetime.date.today().isoformat()
    for spec in args:
        key, _, rest = spec.partition("=")
        cls, _, why = rest.partition(":")
        if not key or cls not in ("ai", "human"):
            print(f"!! bad --classify '{spec}' — expected '<id>=ai|human[:why]'")
            return 2
        store[key.strip()] = {"class": cls, "why": why.strip() or "agent's judgement", "at": today}
        print(f"classified: {key.strip()} = {cls}")
    if not save_json(cls_file, store):
        print(f"!! class NOT saved ({cls_file})")
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default="")
    ap.add_argument("--hook-input", default="")
    ap.add_argument("--repo", default=os.environ.get(
        "SHARED_MEMORY_REPO", str(Path.home() / "Projects" / "brain-shared-memory")))
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR", "."))
    ap.add_argument("--classify", nargs="+", metavar="ID=ai|human[:why]")
    a = ap.parse_args()
    # OS-9: the bootup and the Stop gate parse this output, and the item texts carry the
    # authors' umlauts and dashes. Unpinned, Windows writes the ANSI codepage.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")

    root = Path(a.root)
    state_dir = root / ".claude-state"
    seen_file, cls_file = state_dir / "open-items-seen.json", state_dir / "open-items-class.json"
    if a.classify:
        return classify(a.classify, cls_file)

    hook = {}
    if a.hook_input.strip():
        try:
            hook = json.loads(a.hook_input)
        except ValueError:
            pass
    now = datetime.datetime.now()
    # No session id (run by hand): one bucket per hour, so a hand run does not inflate
    # the counter session after session.
    sid = hook.get("session_id") or now.strftime("hand-%Y%m%d%H")
    cfg = load_json(root / ".claude" / "rules" / "open-items.json", {})
    try:
        parked_rx = [re.compile(p, re.I) for p in cfg.get("parked", [])]
        names = [re.escape(n) for n in cfg.get("humans", [])]
        # "an <name>" / "to <name>", but not a machine id built from the name (name-macos).
        human_rx = re.compile(r"\b(an|to|for)\s+(" + "|".join(names) + r")\b(?![-\w])") if names else None
    except re.error:
        parked_rx, human_rx = [], None

    seen = load_json(seen_file, {})
    old, last_run = seen.get("items", {}), seen.get("last_run", "")
    store = load_json(cls_file, {})

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
        own = lookup(store, it)
        it["cls"], it["why"] = (own["class"], own.get("why", "")) if own else auto_class(it, a.repo, human_rx)
        it["cls"] = it["cls"] or "?"
    # A source that failed keeps its old counters — a failed read is not "handled".
    for k, v in old.items():
        if k not in keep and ((req is None and "#" not in k) or (pr is None and "#" in k)):
            keep[k] = v
    saved = save_json(seen_file, {"items": keep, "last_run": now.isoformat(timespec="seconds")})

    active = sorted((i for i in items if not i["parked"]), key=lambda i: (-i["n"], i["date"]))
    parked = [i for i in items if i["parked"]]
    count = {c: sum(1 for i in active if i["cls"] == c) for c in ("ai", "human", "?")}
    rep = {c: sum(1 for i in active if i["cls"] == c and i["n"] > 1) for c in ("ai", "human")}
    print(f"open for us: {len(active)} — ai {count['ai']} · human {count['human']} · unclassified {count['?']}"
          + (f" (+{len(parked)} parked)" if parked else "")
          + (f" — already reported before and still open: ai {rep['ai']} · human {rep['human']}"
             if rep["ai"] or rep["human"] else ""))
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
        why = f" ({i['why']})" if i["why"] else ""
        print(f"- [{i['kind']}|{i['cls']}] {i['date']} {i['ref']} — {i['who']}: {i['text']} — {age}{moved}{why}")
    if parked:
        print(f"- [parked] {', '.join(i['ref'].rsplit('/', 1)[-1] for i in parked)}")
    if count["?"]:
        print("!! open for us: classify every '?' item once — core/scripts/open-items.py --classify '<id>=ai|human:<why>'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
