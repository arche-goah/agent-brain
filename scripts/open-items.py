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
  * `standing` — an `ai` (or unclassified) item of a CLASS the operator approved once for
              good (full-audit 2026-10-15 on the Windows instance: an instance carried "requests
              addressed to this machine are handled without asking", and the first reply asked
              anyway, because the core knew no such class). The class and the operator's words
              live in instance data `.claude/rules/open-items-standing.json`; the reply handles
              these and reports what was done, no question. An entry without the operator's
              quoted words and a date is refused with a line — the agent cannot grant itself one.

This script is the ONE list of open points at session start:
  * open shared-memory requests addressed to this instance (shared-memory-inbox --open,
    no cursor, no age window) — in the default shared memory and in every further channel the
    instance is a member of (scripts/shared_channels.py; such an item's id and ref start with
    `<label>:`) — and every open PR under the ecosystem owner;
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
    we reviewed or commented on after its last commit (or checked at its current head and
    answered in the shared memory, shared_answers.py), a PR in a repo that instance data
    (`owners`: repo -> login) gives to someone else when no review was asked of us, our own
    PR in such a repo unless someone else spoke after its last commit, and any
    item with a dated wait (`waiting`: id -> {until, why} in instance data, or a line
    `waiting-until: YYYY-MM-DD: <why>` in a PR body). On its date it is due, after it louder;
  * a REQUEST from another side in a parked domain is not parked away — parked means not
    worked on, never unanswered; it is listed with how to answer (receipt, state, when);
  * a source that could not be read says so — it never reads as "nothing open";
  * "nothing open" is said explicitly when both sources were read and nothing is open.
helpers/open-items-gate.cjs (Stop) then checks the first reply against this list.

Items that vanish (answered, merged, closed) take their counter and class with them.
Instance data `.claude/rules/open-items.json`: "parked" (regexes on request topic / PR
repo — parked domains stay on one line, never dropped; an entry may instead be
{"match", "wake_on", "since"}: when a wake_on party — GitHub login or shared-memory `von`
id — moves in that domain after `since`, one operator item asks whether to unpark) and
"humans" (names a request can address the operator by, e.g. "an <name>"), and "pr_owners"
(further GitHub accounts or orgs whose open PRs are listed next to --owner's, e.g. the
operator's personal account when --owner is the org; PR ids stay `<repo>#<n>`, so two
listed owners with a repo of the same name share one id).

Usage:
  open-items.py --owner <org> [--hook-input '<SessionStart JSON>'] [--repo <shared-memory>]
  open-items.py --classify '<id>=ai|human[:why]' [...]      (id: as in the hint line, or its file name)
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
sys.path.insert(0, str(HERE))
from instance_key import is_self, self_key  # noqa: E402
from project_dir import resolve_project_dir  # noqa: E402
from shared_answers import checked_head, default_repo, own_shared_shas  # noqa: E402
import shared_channels  # noqa: E402
OPTIONAL = re.compile(r"^optional: (.+?); unclaimed - (take it if you can and want)\s+—")
LINE = re.compile(r"^\s*-\s+(\d{4}-\d{2}-\d{2})\s+\[([^\]]+)\]\s+([^:]+):\s+(.*?)\s*"
                  r"\(([^()]+\.md|(?:[\w.-]+/)?LOG@\d{4}-\d{2}-\d{2}#\d+)\)\s*$")
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


def requests(repo, label=""):
    """[] = read and empty, None = could not read. Not cloned = not taking part = [] — for the
    default shared memory. A further channel (`label`, scripts/shared_channels.py) was declared
    by the instance, so its missing clone is a failed read; its ids carry `<label>:` so the
    same area and LOG position in two repos never share a class or a counter."""
    if not (Path(repo) / ".git").is_dir():
        return None if label else []
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
        # A LOG-only request has no file; the inbox prints its derived id (`<area>/LOG@<date>#<n>`),
        # which is its key for the class and the counter. It used to be date + sender + the first
        # 40 characters of its words — the root of 15 fixes in 7 days (collisions, cuts at a
        # blank, a second entry inheriting the first one's class).
        is_log = "LOG@" in rel
        key = f"{label}:{rel}" if label else rel
        items.append({"id": key, "kind": "request",
                      "date": date, "who": von.strip(), "text": text[:100], "scope": topic,
                      "ref": key, "file": "" if is_log else rel, "repo": repo})
        # A request we are not asked first for, or one to everyone (shared-memory-parties.py
        # priority): listed, but as a hint — information, not a duty (operator 2026-10-13).
        q = OPTIONAL.match(text)
        if q:
            items[-1]["waiting_on"] = (q.group(1), q.group(2))
    # An inbox line this parser cannot read must not vanish — the exact defect this list
    # exists to stop. It reports itself as a failed read instead.
    return None if unparsed or len(items) != expected else items


# One GraphQL search instead of `gh search prs`: the list needs to know whose move it is,
# and only reviews, review requests, comments and the last commit date say that.
PR_QUERY = """query($q: String!) { viewer { login }
  search(query: $q, type: ISSUE, first: 50) { issueCount nodes { ... on PullRequest {
    number title isDraft createdAt body author { login } repository { name }
    reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } } } }
    latestReviews(first: 20) { nodes { author { login } submittedAt body } }
    commits(last: 1) { nodes { commit { oid committedDate } } }
    comments(last: 20) { nodes { author { login } createdAt body } } } } } }"""
WAIT_MARK = re.compile(r"^\s*waiting-until:\s*(\d{4}-\d{2}-\d{2})\s*:?\s*(.*)$", re.M | re.I)

def ball(p, me, owners, shared_shas=frozenset()):
    """Whose move a PR is. None = ours. Otherwise (party, reason): for another's PR we wait on
    its author — we reviewed or commented after its last commit, or the repo belongs to
    someone else (instance data `owners`) and nobody asked us for a review; for our own PR in
    such a repo we wait on the owner. Measured 2026-10-09: two PRs we had approved were
    printed as "nothing done yet" in every session after."""
    author = (p.get("author") or {}).get("login", "")
    if not me:
        return None
    # One login can carry several instances (instance_key.py): a text is ours only with our
    # login AND no foreign instance key. A sibling instance's PR is a hand-over to us.
    my_key = self_key()

    def ours(node):
        return is_self((node.get("author") or {}).get("login", ""), me, node.get("body"), my_key)

    head = ((p.get("commits") or {}).get("nodes") or [{}])[-1].get("commit", {})
    last, oid = head.get("committedDate", ""), (head.get("oid") or "").lower()
    # Our answer in the shared memory naming THIS head counts like a comment after the last
    # commit (see own_shared_shas). A sha of an older head does not: a new commit is new work.
    checked = checked_head(oid, shared_shas)
    owner = owners.get(p["repository"]["name"])
    reviews = (p.get("latestReviews") or {}).get("nodes", [])
    comments = (p.get("comments") or {}).get("nodes", [])
    touched = [r.get("submittedAt") or "" for r in reviews if ours(r)]
    touched += [c.get("createdAt") or "" for c in comments if ours(c)]
    if author == me and not ours(p):
        # A sibling instance's PR (same login, another key): ours to look at, whatever repo
        # it sits in — the sibling asked us, not the repo's owner. Our own look after its
        # last commit hands the move back to the sibling.
        if last and any(t > last for t in touched):
            return author, "we reviewed or commented after the sibling instance's last commit"
        if checked:
            return author, "our check of this head is in the shared memory"
        return None
    if author == me:
        # Our own PR in a repo someone else merges waits on that owner — unless someone else
        # reviewed or commented after our last commit and our last comment: that is ours to
        # answer. Measured
        # 2026-10-10: two green own PRs in a suite owned by another party were printed as
        # "nothing done yet" in three sessions, because this check ran only for others' PRs.
        if owner and owner != me:
            theirs = [r.get("submittedAt") or "" for r in reviews if not ours(r)]
            theirs += [c.get("createdAt") or "" for c in comments if not ours(c)]
            # Same rule as pr-ball.py: our own reply after theirs hands the move back.
            seen = [last] + [c.get("createdAt") or "" for c in comments if ours(c)]
            if not (theirs and max(theirs) > max(seen)):
                return owner, f"{p['repository']['name']} is {owner}'s to merge, our own PR waits on that"
        return None
    if last and any(t > last for t in touched):
        return author, "we reviewed or commented after the last commit"
    if checked:
        return author, "our check of this head is in the shared memory"
    asked = any(((n.get("requestedReviewer") or {}).get("login")) == me
                for n in (p.get("reviewRequests") or {}).get("nodes", []))
    if owner and owner != me and not asked:
        return author, f"{p['repository']['name']} is {owner}'s to merge and no review was asked of us"
    return None


def pr_search(owner, extra=()):
    """One search over every owner: GitHub ORs repeated `user:` qualifiers (measured
    2026-10-14: `user:a` 10 + `user:b` 2 = `user:a user:b` 12). `extra` is instance data
    (`pr_owners`): an operator whose repos sit under a second account (a personal one next
    to the org) never saw a PR there at session start (measured the same day). `archived:false`: a PR in an
    archived repo is read-only - nobody can comment, move or close it, so it stood in every start report for good
    (measured 2026-10-24: 10 open PRs, one in an archive; with the qualifier 9)."""
    names = [owner] + [o for o in extra if o and o.lower() != owner.lower()]
    return " ".join(f"user:{o}" for o in names) + " is:pr is:open archived:false"


def prs(owner, owners, repos=(None,), extra=()):
    # No owner = the source was never asked. Measured 2026-10-09: a run without --owner said
    # "nothing open (requests and PRs both read)" while twelve PRs were open.
    if not owner:
        return None
    q = pr_search(owner, extra)
    if os.environ.get("OPEN_ITEMS_SHOW_PR_SEARCH"):  # fixture hook: which search was asked
        print(f"pr-search: {q}", file=sys.stderr)
    fixture = os.environ.get("OPEN_ITEMS_PR_FIXTURE")  # fixture hook: a saved GraphQL answer
    if fixture:
        rc, out = (0, Path(fixture).read_text(encoding="utf-8")) if Path(fixture).is_file() else (1, "")
    else:
        rc, out = run(["gh", "api", "graphql", "-f", f"query={PR_QUERY}", "-F", f"q={q}"])
    if rc != 0:
        return None
    try:
        data = json.loads(out or "{}")["data"]
        me, rows = (data.get("viewer") or {}).get("login", ""), data["search"]["nodes"]
    except (ValueError, KeyError, TypeError):
        return None
    items = []
    # A check answered in any channel we read counts (a device channel carries such answers too).
    shas = set().union(*(own_shared_shas(r) for r in repos))
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
                      "waiting_on": ball(p, me, owners, shas),
                      "until": (m.group(1), m.group(2).strip()) if m else None,
                      "events": pr_events(p),
                      # Our own last move (commit, comment, review) — "nothing done yet" is a claim
                      # and needs it. Measured 2026-10-12: an own alpha PR with commits and comments
                      # on the same day was printed as "nothing done yet" in 17 sessions.
                      "ours": max((w for who, w in pr_events(p) if who == me and w != p.get("createdAt")),
                                  default="")})
    return items


def pr_events(p):
    """(login, ISO date) of every move the PR data shows: opened, last commit (by its author),
    comments, reviews. Only the wake-up check reads it."""
    author = (p.get("author") or {}).get("login", "")
    last = ((p.get("commits") or {}).get("nodes") or [{}])[-1].get("commit", {}).get("committedDate", "")
    ev = [(author, p.get("createdAt", "")), (author, last)]
    for c in (p.get("comments") or {}).get("nodes") or []:
        ev.append(((c.get("author") or {}).get("login", ""), c.get("createdAt", "")))
    for r in (p.get("latestReviews") or {}).get("nodes") or []:
        ev.append(((r.get("author") or {}).get("login", ""), r.get("submittedAt", "")))
    return [(who, when) for who, when in ev if who and when]


# Parked domains (operator order 2026-10-11). A domain is often parked because ANOTHER party
# paused it; when that party moves again, nothing said so — its new PRs were filed on the
# parked line like every other. An entry in `parked` may therefore be an object:
#   {"match": "<regex>", "wake_on": ["<login or von id>", ...], "since": "YYYY-MM-DD"}
# and a plain string stays a plain parked regex. New activity of a wake_on party AFTER `since`
# in the parked domain becomes one operator item. Keeping it parked = move `since` forward.
def parked_rules(cfg):
    rules = []
    for e in cfg.get("parked", []):
        if isinstance(e, str):
            rules.append((re.compile(e, re.I), None, e))
        elif isinstance(e, dict) and e.get("match"):
            wake = None
            if e.get("wake_on") and e.get("since"):
                wake = {"who": {str(w).lower() for w in e["wake_on"]}, "since": str(e["since"])}
            rules.append((re.compile(e["match"], re.I), wake, str(e.get("name") or e["match"])))
    return rules


FM_FIELD = re.compile(r"^[^:]+:([^:]+):\s+(von|date):\s*(.+?)\s*$")
LOG_HEAD = re.compile(r"^[^:]+:[^:]+:## (\d{4}-\d{2}-\d{2}) · ([^\s—]+)")


def wake_items(rules, prs_list, repo):
    """One operator item per parked domain whose wake_on party moved after `since`.
    Sources: the PR events already fetched, plus two git calls on the shared-memory repo
    (fact-file frontmatter `von:`/`date:` and LOG headings in the parked topic folders)."""
    rules = [r for r in rules if r[1]]
    if not rules:
        return []
    dirs, fm, heads = [], {}, []
    if (Path(repo) / ".git").exists():
        rc, out = run(["git", "-C", repo, "ls-tree", "-d", "--name-only", "origin/main"])
        dirs = out.split() if rc == 0 else []
        hit = [d for d in dirs if any(rx.search(d) for rx, _, _ in rules)]
        if hit:
            rc, out = run(["git", "-C", repo, "grep", "-E", "-e", r"^[[:space:]]+(von|date):",
                           "origin/main", "--", *[f"{d}/*.md" for d in hit]])
            for line in (out.splitlines() if rc == 0 else []):
                m = FM_FIELD.match(line)
                if m:
                    fm.setdefault(m.group(1), {}).setdefault(m.group(2), m.group(3).strip("\"'"))
            rc, out = run(["git", "-C", repo, "grep", "-E", r"^## [0-9]{4}-[0-9]{2}-[0-9]{2} · ",
                           "origin/main", "--", *[f"{d}/LOG.md" for d in hit]])
            heads = [(line.split(":")[1], *LOG_HEAD.match(line).groups())
                     for line in (out.splitlines() if rc == 0 else []) if LOG_HEAD.match(line)]
    items = []
    for rx, wake, label in rules:
        seen = []  # (date, party, what)
        for it in prs_list or []:
            if rx.search(it["scope"]):
                for who, when in it.get("events", []):
                    if who.lower() in wake["who"] and when[:10] > wake["since"]:
                        seen.append((when[:10], who, f"PR {it['ref']}"))
        for path, f in fm.items():
            if rx.search(path.split("/")[0]) and f.get("von", "").lower() in wake["who"] \
                    and f.get("date", "")[:10] > wake["since"]:
                seen.append((f["date"][:10], f["von"], f"shared memory {path}"))
        for path, date, sender in heads:
            if rx.search(path.split("/")[0]) and sender.lower() in wake["who"] and date > wake["since"]:
                seen.append((date, sender, f"LOG heading in {path}"))
        if seen:
            date, who, what = max(seen)
            items.append({"id": f"wake:{label}", "kind": "wake", "date": date, "who": who,
                          "text": f"parked domain {label}: {who} is active again ({what}, {len(seen)} move(s) "
                                  f"since {wake['since']}) - ask the operator whether to unpark",
                          "scope": "", "ref": label, "file": ""})
    return items


# The `why` reaches a human through the first reply, so it says what the circle MEANS, not
# its letter (operator 2026-10-08/09: no priority, ledger or circle codes towards humans).
CIRCLE_WORDS = {"A": "the AI handles it alone", "B": "needs the operator's own decision",
                "C": "the AIs settle it among themselves", "D": "needs one person's word",
                "E": "needs several people", "F": "a matter between people"}


def front(it, repo):
    """The frontmatter of a request's file at origin/main ('' without a file), read once — in the
    repo of the channel the item came from."""
    if "front" not in it:
        repo = it.get("repo") or repo
        rc, blob = run(["git", "-C", repo, "show", f"origin/main:{it['file']}"]) if it.get("file") else (1, "")
        it["front"] = blob.split("\n---", 1)[0] if rc == 0 else ""
    return it["front"]


def auto_class(it, repo, human_rx):
    """(class, why) from the data alone, or (None, '') when the data does not say."""
    if it["kind"] == "PR":
        return "ai", "pull request: review or merge is agent work"
    if it["kind"] == "session":
        return "ai", "the transcript holds the cause; the agent reads it and says it, the operator knows no more"
    if it["kind"] == "ledger":
        if it.get("lclass") == "decision":
            return "human", "a decision in the ledger"
        return "ai", "ledger work item"
    if it.get("file"):
        m = CIRCLE.search(front(it, repo))
        if m:
            c = m.group(1).upper()
            return ("ai" if c in AI_CIRCLES else "human"), CIRCLE_WORDS[c]
    if human_rx and human_rx.search(it["text"]):
        return "human", "addressed to a person"
    return None, ""


# Standing approvals (full-audit 2026-10-15, Windows instance): a class of items the operator
# approved once for good. Instance data `.claude/rules/open-items-standing.json`, "classes":
#   {"name", "kind": "request"|"PR", "scope": regex on topic folder / repo, "audience": [tokens,
#    one of which the request's audience must name], "title": regex on the item text,
#    "excludes": [regexes on the item text that keep an item out], "granted": "\"<words>\" <date>"}
# `granted` must quote the operator and carry the date — the shapes mechanism-guard.cjs accepts
# for needs_operator_word. Without them the entry is refused, never silently applied.
QUOTE = re.compile(r'"[^"\n]{3,}"|„[^“”"\n]{3,}[“”"]|“[^”\n]{3,}”')
DAY = re.compile(r"\b20\d{2}-\d{2}-\d{2}\b")
AUDIENCE = re.compile(r"^\s+audience:\s*(.+?)\s*$", re.M)
TOKEN = re.compile(r"(?:(?:os|person):)?[\w-]+")  # shared-memory-parties.py's audience tokens
ADDRESSEES = re.compile(r"^(?:AN|An|an|TO|To)\s+([^:]+):")


def standing_classes(root):
    """(classes, refusal lines) from the instance file; no file = no standing classes."""
    data = load_json(root / ".claude" / "rules" / "open-items-standing.json", {})
    classes, refused = [], []
    for e in (data.get("classes") or []) if isinstance(data, dict) else []:
        if not isinstance(e, dict):
            continue
        name, granted = str(e.get("name") or "unnamed"), str(e.get("granted") or "")
        if not (QUOTE.search(granted) and DAY.search(granted)):
            refused.append(f"standing approval '{name}' refused — \"granted\" must quote the operator's "
                           "words and the date they were said (\"...\" YYYY-MM-DD); its items are asked as before")
            continue
        if e.get("kind") not in ("request", "PR"):
            refused.append(f"standing approval '{name}' refused — \"kind\" must be request or PR")
            continue
        try:
            scope, title = (re.compile(e[k], re.I) if e.get(k) else None for k in ("scope", "title"))
            excludes = [re.compile(x, re.I) for x in e.get("excludes") or []]
        except re.error as err:
            refused.append(f"standing approval '{name}' refused — broken regex ({err})")
            continue
        classes.append({"name": name, "kind": e["kind"], "scope": scope, "title": title, "excludes": excludes,
                        "audience": {str(t).lower() for t in e.get("audience") or []},
                        "granted": DAY.search(granted).group(0)})
    return classes, refused


def audience(it, repo):
    """Audience tokens of a request: its file's `audience:` field, or the `AN <who>:` of a LOG
    heading. A PR has none."""
    if it["kind"] != "request":
        return set()
    if it.get("file"):
        m = AUDIENCE.search(front(it, repo))
        return set(TOKEN.findall(m.group(1).lower())) if m else set()
    text = re.sub(r"^optional: .*?—\s*", "", it["text"])
    m = ADDRESSEES.match(re.sub(r"\b(os|person):(?=[\w-])", "\\1\x00", text))
    return set(TOKEN.findall(m.group(1).replace("\x00", ":").lower())) if m else set()


def standing_match(it, classes, repo):
    for c in classes:
        if c["kind"] != it["kind"] or (c["scope"] and not c["scope"].search(it["scope"])):
            continue
        if (c["title"] and not c["title"].search(it["text"])) or any(x.search(it["text"]) for x in c["excludes"]):
            continue
        if c["audience"] and not (audience(it, repo) & c["audience"]):
            continue
        return c
    return None


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


def sessions(root, hook_input):
    """Past sessions that ended without session-close, and failed session starts
    (scripts/session-audit.py — operator order 2026-10-11: loud, for everyone). Always class
    `human`; they leave the list only by `session-audit.py --ack`. None = could not read."""
    script = HERE / "session-audit.py"
    if not script.is_file():
        return []
    rc, out = run([sys.executable, str(script), "--json", "--root", str(root), "--hook-input", hook_input])
    if rc != 0:
        return None
    try:
        found = json.loads(out.strip().splitlines()[-1] if out.strip() else "[]")
    except (ValueError, IndexError):
        return None
    return [{"id": f["id"], "kind": "session", "date": f["when"][:10], "who": "this machine",
             "text": f["text"][:100], "scope": "session", "ref": f"session/{f['sid'][:8]}"} for f in found]


# Work ledgers (rules/working-rules.md "Project Work Ledgers"): the open entries of the files the
# instance registered in .claude/rules/ledgers.json — the registry ledger-reconcile.py reads, with
# its entry parser. Measured 2026-10-25 on a Windows brain: the list said "open for us: 3" (PRs and
# requests), the first reply said nothing else was open, and ordered points sat in the brain's own
# ledgers — a list that calls itself THE list had read two of its three sources.
LEDGER_FIELD = re.compile(r"\b(id|class|origin):\s*`?([\w.:/-]+)")
LEDGER_EXIT = re.compile(r"\bexit:\s*(other-side|parked|later-at-system)\s+(\d{4}-\d{2}-\d{2})")


def ledgers(root):
    """(items, unread lines); items None when the registry is missing or unreadable."""
    cfg = load_json(root / ".claude" / "rules" / "ledgers.json", None)
    if not isinstance(cfg, dict):
        return None, []
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("ledger_reconcile", HERE / "ledger-reconcile.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except (OSError, ImportError, AttributeError):
        return None, []
    items, unread = [], []
    for rel in cfg.get("ledgers") or []:
        try:
            text = (root / rel).read_text(encoding="utf-8")
        except OSError:
            unread.append(f"{rel} (file not found)")
            continue
        found = list(mod.entries(text))
        # Entries that are not `- [ ]` / `- [x]` lines read as an empty ledger — the same silence.
        if not found and re.search(r"^[\s>*-]*`?id:", text, re.M):
            unread.append(f"{rel} (id: fields but no '- [ ]' entries, so the reader sees none)")
            continue
        for e in found:
            f = {}
            for k, v in LEDGER_FIELD.findall(e["text"]):
                f.setdefault(k, v.rstrip(".:"))
            if e["done"] or f.get("class") == "lesson":
                continue
            ident = f.get("id") or f"{rel}:{e['line']}"
            d, m = mod.DATE.search(e["text"]), WAIT_MARK.search(e["text"])
            # The backlog-catch-up exits that put the move elsewhere (skill backlog-catch-up, step 4):
            # listed quietly as waiting, never as the agent's open work.
            x = LEDGER_EXIT.search(e["text"])
            items.append({"id": f"ledger:{ident}", "kind": "ledger", "date": d.group(1) if d else "",
                          "who": f.get("origin", "ledger"), "text": re.sub(r"[*`]", "", e["title"])[:100],
                          "scope": rel, "ref": ident, "lclass": f.get("class", ""),
                          "until": (m.group(1), m.group(2).strip()) if m else None,
                          "waiting_on": (f"the ledger exit {x.group(1)}", f"since {x.group(2)}") if x else None})
    return items, unread


def lookup(store, it):
    """The agent's own class wins; it is keyed by the printed id, or — for an entry with its
    own FILE — by the file name. A LOG entry matches by its full id (`<area>/LOG@<date>#<n>`):
    one id names one entry for good, so a class never passes to another entry."""
    if it.get("file"):
        return store.get(it["id"]) or store.get(it["ref"].rsplit("/", 1)[-1])
    return store.get(it["id"])


PR_ID = re.compile(r"^[\w.-]+#\d+$")


def channel_requests(chans):
    """(channel, requests) per channel; the default shared memory carries no label."""
    return [(c, requests(c["repo"], "" if c["default"] else c["label"])) for c in chans]


def classify(args, cls_file, chans, seen_file=None):
    """Store the agent's class per id. A request id that matches no open request is refused:
    measured 2026-10-10, two calls with the printed short ref of a LOG entry said
    "classified" and the item stayed '?'. PR ids are not checked (that needs the PR search).
    An id the session start LISTED is accepted although it closed since: the Stop gate judges the
    first reply against that start block, so a `?` item answered mid-session could never be
    classified and the first reply stayed blocked (measured twice 2026-10-12, Windows instance;
    the only way out was a hand edit of the class file). The start's list is the counter file."""
    store = load_json(cls_file, {})
    today = datetime.date.today().isoformat()
    reads = [r for _, r in channel_requests(chans)]
    req = None if any(r is None for r in reads) else [i for r in reads for i in r]
    listed = set((load_json(seen_file, {}).get("items") or {}).keys()) if seen_file else set()
    known = None if req is None else ({i["id"] for i in req} | listed
                                      | {i["ref"].rsplit("/", 1)[-1] for i in req if i.get("file")})
    specs = []
    for spec in args:
        key, _, rest = spec.partition("=")
        cls, _, why = rest.partition(":")
        key = key.strip()
        if not key or cls not in ("ai", "human"):
            print(f"!! bad --classify '{spec}' — expected '<id>=ai|human[:why]'")
            return 2
        if not PR_ID.match(key) and not key.startswith("ledger:"):
            if known is None:
                print(f"!! requests NOT readable - '{key}' saved unchecked")
            elif key not in known:
                near = [i["id"] for i in req if key in i["id"]] or [i["id"] for i in req]
                print(f"!! --classify '{key}' matches no open request - nothing saved. Exact ids:")
                for n in near[:10]:
                    print(f"   {n}")
                return 2
        specs.append((key, cls, why))
    for key, cls, why in specs:
        store[key] = {"class": cls, "why": why.strip() or "agent's judgement", "at": today}
        print(f"classified: {key} = {cls}")
    if not save_json(cls_file, store):
        print(f"!! class NOT saved ({cls_file})")
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default="")
    ap.add_argument("--hook-input", default="")
    ap.add_argument("--repo", default=default_repo())
    ap.add_argument("--root", default=resolve_project_dir(HERE))
    # extend: the hint prints one --classify per item; with the default action only the last one counted.
    ap.add_argument("--classify", nargs="+", action="extend", metavar="ID=ai|human[:why]")
    a = ap.parse_args()
    # OS-9: the bootup and the Stop gate parse this output, and the item texts carry the
    # authors' umlauts and dashes. Unpinned, Windows writes the ANSI codepage.
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")

    root = Path(a.root)
    state_dir = root / ".claude-state"
    seen_file, cls_file = state_dir / "open-items-seen.json", state_dir / "open-items-class.json"
    # The default shared memory, then every further channel this instance is a member of
    # (scripts/shared_channels.py). A broken channel file reads the default alone and says so.
    try:
        chans, chan_error = shared_channels.member_channels(root, a.repo), ""
    except ValueError as e:
        chans, chan_error = [shared_channels.default_channel(a.repo)], str(e)
    if a.classify:
        return classify(a.classify, cls_file, chans, seen_file)

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
        rules = parked_rules(cfg)
        parked_rx = [rx for rx, _, _ in rules]
        names = [re.escape(n) for n in cfg.get("humans", [])]
        # "an <name>" / "to <name>", but not a machine id built from the name (name-macos).
        human_rx = re.compile(r"\b(an|to|for)\s+(" + "|".join(names) + r")\b(?![-\w])") if names else None
    except re.error:
        rules, parked_rx, human_rx = [], [], None

    seen = load_json(seen_file, {})
    old = seen.get("items", {})
    confirmed = set(seen.get("confirmed", []))
    store = load_json(cls_file, {})
    waits = cfg.get("waiting") or {}  # instance data: {"<id>": {"until": "YYYY-MM-DD", "why": "..."}}
    standing, refused = standing_classes(root)

    def counts(s):
        """A session counts as a report only once its transcript shows the list reached a human.
        The running session counts now — it is the one reporting."""
        if s == sid or s in confirmed:
            return True
        if tdir is not None and reached_a_human(tdir / f"{s}.jsonl"):
            confirmed.add(s)
            return True
        return False

    reads = channel_requests(chans)
    req = reads[0][1]
    pr = prs(a.owner, cfg.get("owners") or {}, [c["repo"] for c in chans], cfg.get("pr_owners") or [])
    ses = sessions(root, a.hook_input)
    led, led_unread = ledgers(root)
    failed = [name for name, v in ([("shared-memory requests" + ("" if c["default"] else f" [{c['label']}]"), r)
                                    for c, r in reads]
                                   + [("PR search" if a.owner else "PRs (no owner given)", pr),
                                      ("session audit", ses),
                                      ("work ledgers (no readable .claude/rules/ledgers.json)", led)]) if v is None]
    if chan_error:
        failed.append(f"shared-memory channels ({chan_error})")
    failed += [f"ledger {u}" for u in led_unread]
    items = ([i for _, r in reads for i in r or []] + (pr or []) + (ses or []) + (led or [])
             + wake_items(rules, pr, a.repo))

    today = now.date().isoformat()
    keep = {}
    for it in items:
        rec = old.get(it["id"]) or {"first": today, "sessions": []}
        rec.pop("text", None)  # a text fingerprint guarded reused LOG ids; the ids are stable now
        w = lookup(waits, it)  # same rule as the class: a LOG entry matches by its full id only
        until = (str(w.get("until", "")), str(w.get("why", ""))) if isinstance(w, dict) else it.get("until")
        it["wait"] = None
        if it.get("waiting_on"):
            it["wait"] = "waiting on {}: {}".format(*it["waiting_on"])
        # The marker's date is the day the work is DUE, so on that day the item is ours again.
        # Quiet through its own date, it surfaced only the morning after, when the sessions of
        # the due day had already done the work and closed without moving the marker (measured
        # 2026-10-15: a measurement done on its date read as missing the next morning).
        elif until and until[0] > today:
            it["wait"] = f"waiting until {until[0]}" + (f": {until[1]}" if until[1] else "")
        why_w = f" ({until[1]})" if until and until[1] else ""
        it["overdue"] = ("" if not until or until[0] > today else
                         f"due today{why_w}" if until[0] == today else f"waited until {until[0]}{why_w}")
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
        if it["kind"] == "wake":   # unparking is the operator's call, never the agent's
            it["parked"], it["cls"], it["why"] = False, "human", "the party that paused it moved again"
        # A standing approval covers what the agent may do anyway (ai) or what nobody classified
        # yet — never an item the data gives to a person (circle, addressee, the agent's own class).
        c = standing_match(it, standing, a.repo) if it["cls"] in ("ai", "?") and not it["parked"] else None
        if c:
            it["cls"], it["why"] = "standing", f"standing approval '{c['name']}', granted {c['granted']}"
        if it["wait"]:
            it["cls"] = "wait"
    # A source that failed keeps its old counters — a failed read is not "handled". A further
    # channel's ids carry `<label>:`; with the channel file unreadable, every such id is kept.
    labels = tuple(f"{c['label']}:" for c in chans[1:])
    lost = tuple(f"{c['label']}:" for c, r in reads[1:] if r is None)
    for k, v in old.items():
        is_ses = k.startswith(("start:", "end:"))
        chan = ":" in k and not k.startswith(("start:", "end:", "wake:"))
        if k not in keep and ((req is None and "#" not in k and not is_ses and not k.startswith(labels))
                              or k.startswith(lost) or (chan_error and chan)
                              or (pr is None and "#" in k) or (ses is None and is_ses)
                              or ((led is None or led_unread) and k.startswith("ledger:"))):
            keep[k] = v
    # Only the bootup (a real session id) writes the counter. Measured 2026-10-09: a hand run
    # with a skipped PR source rewrote the file and dropped every item's history.
    saved = save_json(seen_file, {"items": keep, "confirmed": sorted(confirmed)[-300:],
                                  "last_run": now.isoformat(timespec="seconds")}) if sid else True

    # Standing items form their own group at the end of the active list.
    active = sorted((i for i in items if not i["parked"] and i["cls"] != "wait"),
                    key=lambda i: (i["cls"] == "standing", -i["n"], i["date"]))
    waiting = [i for i in items if not i["parked"] and i["cls"] == "wait"]
    parked = [i for i in items if i["parked"]]
    count = {c: sum(1 for i in active if i["cls"] == c) for c in ("ai", "human", "?", "standing")}
    rep = {c: sum(1 for i in active if i["cls"] == c and i["n"] > 1) for c in ("ai", "human", "standing")}
    print(f"open for us: {len(active)} — ai {count['ai']} · human {count['human']} · unclassified {count['?']}"
          + (f" · standing {count['standing']}" if count["standing"] else "")
          + (f" (+{len(waiting)} waiting on others or a date)" if waiting else "")
          + (f" (+{len(parked)} parked)" if parked else "")
          + (f" — already reported before and still open: ai {rep['ai']} · human {rep['human']}"
             + (f" · standing {rep['standing']}" if rep["standing"] else "")
             if rep["ai"] or rep["human"] or rep["standing"] else ""))
    for line in refused:
        print(f"!! open for us: {line}")
    if not saved:
        print(f"!! open for us: repeat counter NOT saved ({seen_file}) — repeats will not get louder")
    for name in failed:
        print(f"!! open for us: {name} NOT checked — this is not 'nothing open'; re-run core/scripts/open-items.py")
    if ses:
        n_end = sum(1 for i in ses if i["id"].startswith("end:"))
        n_start = len(ses) - n_end
        print("!! open for us: "
              + " · ".join(([f"{n_end} past session(s) ended without session-close"] if n_end else [])
                           + ([f"{n_start} session start(s) failed"] if n_start else []))
              + " — clear each before the first reply: read its transcript (session-audit.py --details),"
              + " say the cause and whether work was lost as measured, never ask the operator;"
              + " then core/scripts/session-audit.py --ack <id>")
    if not items and not failed:
        print("- nothing open (requests, PRs and work ledgers read)")
    group = False
    for i in active:
        if i["cls"] == "standing" and not group:
            group = True
            print("- standing approval — handle these, then report what was done (no question needed):")
        if i["n"] > 1 and i.get("ours", "")[:10] >= i["first"]:
            age = f"!! reported in {i['n']} sessions since {i['first']}, last own move {i['ours'][:10]} — still ours"
        elif i["n"] > 1:
            age = f"!! reported in {i['n']} sessions since {i['first']}, nothing done yet"
        else:
            age = "first report"
        # A date marker is a claim about the work, the work's record is the measurement: a
        # passed date says the marker went stale OR the work is missing, never which one.
        if i["overdue"].startswith("due today"):
            age = f"!! {i['overdue']} — do it, then move or drop the waiting-until line; " + age
        elif i["overdue"]:
            age = (f"!! {i['overdue']} — that date has passed: read the work's own record before calling it "
                   "undone, then move or drop the waiting-until line; " + age)
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
        # No angle brackets in these hints: the session start escapes < and > to protect its
        # own wrapper, so '<id>' reached the operator as '&lt;id&gt;' (measured 2026-10-11).
        print("!! open for us: classify every '?' item once — core/scripts/open-items.py --classify 'ID=ai|human:WHY'")
        # The exact id --classify takes (a file request also answers to its file name).
        for i in active:
            if i["cls"] == "?":
                print(f"   --classify '{i['id']}=ai|human:WHY'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
