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
    compaction of the same session never counts twice. A session counts only once its
    transcript shows the list reached a human (bootup block, then a real prompt); a hand
    run never counts;
  * items whose move is NOT ours print as `[...|wait]`, quietly, and do not count up: a PR
    we reviewed or commented on after its last commit, a PR in a repo that instance data
    (`owners`: repo -> login) gives to someone else when no review was asked of us, our own
    PR in such a repo unless someone else spoke after its last commit, and any
    item with a dated wait (`waiting`: id -> {until, why} in instance data, or a line
    `waiting-until: YYYY-MM-DD: <why>` in a PR body). After the date it is louder again;
  * a REQUEST from another side in a parked domain is not parked away — parked means not
    worked on, never unanswered; it is listed with how to answer (receipt, state, when);
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


# One GraphQL search instead of `gh search prs`: the list needs to know whose move it is,
# and only reviews, review requests, comments and the last commit date say that.
PR_QUERY = """query($q: String!) { viewer { login }
  search(query: $q, type: ISSUE, first: 50) { issueCount nodes { ... on PullRequest {
    number title isDraft createdAt body author { login } repository { name }
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } } } }
    latestReviews(first: 20) { nodes { author { login } submittedAt } }
    commits(last: 1) { nodes { commit { committedDate } } }
    comments(last: 20) { nodes { author { login } createdAt } } } } } }"""
WAIT_MARK = re.compile(r"^\s*waiting-until:\s*(\d{4}-\d{2}-\d{2})\s*:?\s*(.*)$", re.M | re.I)


def ball(p, me, owners):
    """Whose move a PR is. None = ours. Otherwise (party, reason): for another's PR we wait on
    its author — we reviewed or commented after its last commit, or the repo belongs to
    someone else (instance data `owners`) and nobody asked us for a review; for our own PR in
    such a repo we wait on the owner. Measured 2026-10-09: two PRs we had approved were
    printed as "nothing done yet" in every session after."""
    author = (p.get("author") or {}).get("login", "")
    if not me:
        return None
    last = ((p.get("commits") or {}).get("nodes") or [{}])[-1].get("commit", {}).get("committedDate", "")
    owner = owners.get(p["repository"]["name"])
    if author == me:
        # Our own PR in a repo someone else merges waits on that owner — unless someone else
        # reviewed or commented after our last commit and our last comment: that is ours to
        # answer. Measured
        # 2026-10-10: two green own PRs in a suite owned by another party were printed as
        # "nothing done yet" in three sessions, because this check ran only for others' PRs.
        if owner and owner != me:
            theirs = [r.get("submittedAt") or "" for r in (p.get("latestReviews") or {}).get("nodes", [])
                      if (r.get("author") or {}).get("login") != me]
            theirs += [c.get("createdAt") or "" for c in (p.get("comments") or {}).get("nodes", [])
                       if (c.get("author") or {}).get("login") != me]
            # Same rule as pr-ball.py: our own reply after theirs hands the move back.
            seen = [last] + [c.get("createdAt") or "" for c in (p.get("comments") or {}).get("nodes", [])
                             if (c.get("author") or {}).get("login") == me]
            if not (theirs and max(theirs) > max(seen)):
                return owner, f"{p['repository']['name']} is {owner}'s to merge, our own PR waits on that"
        return None
    ours = [r.get("submittedAt") or "" for r in (p.get("latestReviews") or {}).get("nodes", [])
            if (r.get("author") or {}).get("login") == me]
    ours += [c.get("createdAt") or "" for c in (p.get("comments") or {}).get("nodes", [])
             if (c.get("author") or {}).get("login") == me]
    if last and any(t > last for t in ours):
        return author, "we reviewed or commented after the last commit"
    asked = any(((n.get("requestedReviewer") or {}).get("login")) == me
                for n in (p.get("reviewRequests") or {}).get("nodes", []))
    if owner and owner != me and not asked:
        return author, f"{p['repository']['name']} is {owner}'s to merge and no review was asked of us"
    return None


def prs(owner, owners):
    # No owner = the source was never asked. Measured 2026-10-09: a run without --owner said
    # "nothing open (requests and PRs both read)" while twelve PRs were open.
    if not owner:
        return None
    fixture = os.environ.get("OPEN_ITEMS_PR_FIXTURE")  # fixture hook: a saved GraphQL answer
    if fixture:
        rc, out = (0, Path(fixture).read_text(encoding="utf-8")) if Path(fixture).is_file() else (1, "")
    else:
        rc, out = run(["gh", "api", "graphql", "-f", f"query={PR_QUERY}",
                       "-F", f"q=user:{owner} is:pr is:open"])
    if rc != 0:
        return None
    try:
        data = json.loads(out or "{}")["data"]
        me, rows = (data.get("viewer") or {}).get("login", ""), data["search"]["nodes"]
    except (ValueError, KeyError, TypeError):
        return None
    items = []
    for p in rows:
        if not p.get("number"):
            continue
        ref = f"{p['repository']['name']}#{p['number']}"
        m = WAIT_MARK.search(p.get("body") or "")
        author = (p.get("author") or {}).get("login", "?")
        # The shown date is when the PR was OPENED — last activity would reset its age.
        items.append({"id": ref, "kind": "PR", "date": p["createdAt"][:10], "who": author,
                      "text": p["title"][:100] + (" (draft)" if p.get("isDraft") else ""),
                      "scope": p["repository"]["name"], "ref": ref,
                      "waiting_on": ball(p, me, owners),
                      "until": (m.group(1), m.group(2).strip()) if m else None})
    return items


# The `why` reaches a human through the first reply, so it says what the circle MEANS, not
# its letter (operator 2026-10-08/09: no priority, ledger or circle codes towards humans).
CIRCLE_WORDS = {"A": "the AI handles it alone", "B": "needs the operator's own decision",
                "C": "the AIs settle it among themselves", "D": "needs one person's word",
                "E": "needs several people", "F": "a matter between people"}


def auto_class(it, repo, human_rx):
    """(class, why) from the data alone, or (None, '') when the data does not say."""
    if it["kind"] == "PR":
        return "ai", "pull request: review or merge is agent work"
    if it.get("file"):
        rc, blob = run(["git", "-C", repo, "show", f"origin/main:{it['file']}"])
        m = CIRCLE.search(blob.split("\n---", 1)[0]) if rc == 0 else None
        if m:
            c = m.group(1).upper()
            return ("ai" if c in AI_CIRCLES else "human"), CIRCLE_WORDS[c]
    if human_rx and human_rx.search(it["text"]):
        return "human", "addressed to a person"
    return None, ""


NOT_A_PROMPT = re.compile(r"^\s*(Stop hook feedback|<task-notification|<system-reminder|<local-command|<command-)")


def reached_a_human(transcript):
    """True when this session's transcript shows the open-items block at its start AND a
    human prompt after it — i.e. the list was really put in front of someone. Measured
    2026-10-09: a session without any transcript and hand runs of the bootup inside a
    development session had inflated every counter by two."""
    try:
        if not transcript.is_file():
            return False
        shown = False
        with open(transcript, encoding="utf-8", errors="replace") as f:
            for line in f:
                if not shown:
                    shown = '"SessionStart' in line and "open for us:" in line
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                msg = d.get("message") or {}
                if msg.get("role") != "user" or d.get("isMeta"):
                    continue
                c = msg.get("content")
                if isinstance(c, list):
                    if any(b.get("type") == "tool_result" for b in c if isinstance(b, dict)):
                        continue
                    c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                if isinstance(c, str) and c.strip() and not NOT_A_PROMPT.match(c):
                    return True
    except OSError:
        return False
    return False


def lookup(store, it):
    """The agent's own class wins; it is keyed by the printed id, or — for an entry with its
    own FILE — by the file name. A LOG entry has no file: its short form "LOG <date> <sender>"
    names every entry of that sender that day, so a class given to one silently covered the
    next (measured 2026-10-09, Windows instance: an unread request would have been filed as
    acknowledged). LOG entries match by their full id only."""
    if it.get("file"):
        return store.get(it["id"]) or store.get(it["ref"].rsplit("/", 1)[-1])
    return store.get(it["id"])


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
    # No session id = a hand run: it is shown, but it never counts as a report.
    sid = hook.get("session_id") or ""
    tdir = Path(hook["transcript_path"]).parent if hook.get("transcript_path") else None
    cfg = load_json(root / ".claude" / "rules" / "open-items.json", {})
    try:
        parked_rx = [re.compile(p, re.I) for p in cfg.get("parked", [])]
        names = [re.escape(n) for n in cfg.get("humans", [])]
        # "an <name>" / "to <name>", but not a machine id built from the name (name-macos).
        human_rx = re.compile(r"\b(an|to|for)\s+(" + "|".join(names) + r")\b(?![-\w])") if names else None
    except re.error:
        parked_rx, human_rx = [], None

    seen = load_json(seen_file, {})
    old = seen.get("items", {})
    confirmed = set(seen.get("confirmed", []))
    store = load_json(cls_file, {})
    waits = cfg.get("waiting") or {}  # instance data: {"<id>": {"until": "YYYY-MM-DD", "why": "..."}}

    def counts(s):
        """A session counts as a report only once its transcript shows the list reached a human.
        The running session counts now — it is the one reporting."""
        if s == sid or s in confirmed:
            return True
        if tdir is not None and reached_a_human(tdir / f"{s}.jsonl"):
            confirmed.add(s)
            return True
        return False

    req, pr = requests(a.repo), prs(a.owner, cfg.get("owners") or {})
    failed = [name for name, v in (("shared-memory requests", req),
                                   ("PR search" if a.owner else "PRs (no owner given)", pr)) if v is None]
    items = (req or []) + (pr or [])

    today = now.date().isoformat()
    keep = {}
    for it in items:
        rec = old.get(it["id"]) or {"first": today, "sessions": []}
        w = lookup(waits, it)  # same rule as the class: a LOG entry matches by its full id only
        until = (str(w.get("until", "")), str(w.get("why", ""))) if isinstance(w, dict) else it.get("until")
        it["wait"] = None
        if it.get("waiting_on"):
            it["wait"] = "waiting on {}: {}".format(*it["waiting_on"])
        elif until and until[0] >= today:
            it["wait"] = f"waiting until {until[0]}" + (f": {until[1]}" if until[1] else "")
        it["overdue"] = f"waited until {until[0]}" + (f" ({until[1]})" if until[1] else "") if until and until[0] < today else ""
        # A wait is not a report: the counter only runs while the move is ours.
        if not it["wait"] and sid and sid not in rec["sessions"]:
            rec["sessions"] = (rec["sessions"] + [sid])[-50:]
        keep[it["id"]] = rec
        it["first"], it["n"] = rec["first"], sum(1 for s in rec["sessions"] if counts(s))
        it["parked"] = any(r.search(it["scope"]) for r in parked_rx)
        own = lookup(store, it)
        it["cls"], it["why"] = (own["class"], own.get("why", "")) if own else auto_class(it, a.repo, human_rx)
        it["cls"] = it["cls"] or "?"
        # Parked means not WORKED ON, never unanswered: a request from another side in a parked
        # domain still gets an answer (receipt, state, when it resumes). Measured: one such
        # question lay 30 days on the parked line.
        if it["parked"] and it["kind"] == "request":
            it["parked"] = False
            it["cls"] = "ai" if it["cls"] == "?" else it["cls"]
            it["why"] = "parked domain — answer anyway: receipt, state, when it resumes"
        if it["wait"]:
            it["cls"] = "wait"
    # A source that failed keeps its old counters — a failed read is not "handled".
    for k, v in old.items():
        if k not in keep and ((req is None and "#" not in k) or (pr is None and "#" in k)):
            keep[k] = v
    # Only the bootup (a real session id) writes the counter. Measured 2026-10-09: a hand run
    # with a skipped PR source rewrote the file and dropped every item's history.
    saved = save_json(seen_file, {"items": keep, "confirmed": sorted(confirmed)[-300:],
                                  "last_run": now.isoformat(timespec="seconds")}) if sid else True

    active = sorted((i for i in items if not i["parked"] and i["cls"] != "wait"), key=lambda i: (-i["n"], i["date"]))
    waiting = [i for i in items if not i["parked"] and i["cls"] == "wait"]
    parked = [i for i in items if i["parked"]]
    count = {c: sum(1 for i in active if i["cls"] == c) for c in ("ai", "human", "?")}
    rep = {c: sum(1 for i in active if i["cls"] == c and i["n"] > 1) for c in ("ai", "human")}
    print(f"open for us: {len(active)} — ai {count['ai']} · human {count['human']} · unclassified {count['?']}"
          + (f" (+{len(waiting)} waiting on others or a date)" if waiting else "")
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
        if i["n"] > 1:
            age = f"!! reported in {i['n']} sessions since {i['first']}, nothing done yet"
        else:
            age = "first report"
        if i["overdue"]:
            age = f"!! {i['overdue']} — that date has passed; " + age
        why = f" ({i['why']})" if i["why"] else ""
        print(f"- [{i['kind']}|{i['cls']}] {i['date']} {i['ref']} — {i['who']}: {i['text']} — {age}{why}")
    # Waiting items need no relay; above a handful, one line keeps the start readable
    # (Windows check 2026-10-09: 20 own PRs waiting on that very check filled 20 lines).
    collapse = int(os.environ.get("OPEN_ITEMS_WAIT_COLLAPSE", "5") or 5)
    if len(waiting) > collapse:
        print(f"- [wait] {len(waiting)} waiting on others or a date: "
              + ", ".join(i["ref"].rsplit("/", 1)[-1] for i in waiting[:12])
              + (f" (+{len(waiting) - 12})" if len(waiting) > 12 else ""))
    else:
        for i in waiting:
            print(f"- [{i['kind']}|wait] {i['date']} {i['ref']} — {i['who']}: {i['text']} — {i['wait']}")
    if parked:
        print(f"- [parked] {', '.join(i['ref'].rsplit('/', 1)[-1] for i in parked)}")
    if count["?"]:
        print("!! open for us: classify every '?' item once — core/scripts/open-items.py --classify '<id>=ai|human:<why>'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
