#!/usr/bin/env python3
"""lesson-carriers.py — which lessons in the feedback protocol have no carrier?

WHY (operator, 2026-10-25, after the macOS instance cut a second beta tag on one day although
the rule "one tag per strand, no tag because it is green" had stood since 2026-08-30): "was that
only prose so far? then I ask one level deeper why you never anchored these clear instructions
mechanically." Measured on that brain: 114 protocol entries, 11 with a carrier line — every
operator correction became a sharper rule sentence, almost none a check, a gate, a tool or a
documented mechanism. A prose lesson is recalled as stimulus→response and loses against the
moment (core rule, Knowledge Carriers: lesson → invariant → carrier).

THE INVARIANT: every entry of the feedback protocol names its carrier on a line of its own:
    Carrier: <check/gate/script/skill/doc> — or —  Carrier: prose, because <why no mechanism fits>
(key words per instance: `carrier_keys`; a brain that writes its protocol in another language
adds that language's word). "Prose, because …" is a decision, not a gap; a missing line is the gap.

WHERE IT RUNS: at session close (skill session-close, next to commitments.py) over the entries
dated in this session, and in the brain-scan over everything since the last scan. A REPORT,
not a gate: it never fires in the middle of a conversation (operator 2026-10-25: "weigh running
stop checks against a check at session close, like the empty-promises check" — the entries are
written one to three times a session and the carrier question needs thought, not a block).

Instance data: `.claude/rules/lesson-carriers.json`
    {"protocol": "docs/maintenance/feedback-protocol.md",
     "carrier_keys": ["Carrier"],
     "entry_heading": "^## (\\d{4}-\\d{2}-\\d{2})"}
     optional for --resolve/--prs: "carrier_roots", "pr_repos", "pr_aliases" (see DEFAULTS)
Usage: lesson-carriers.py [--repo DIR] [--protocol FILE] [--since YYYY-MM-DD] [--json] [--resolve [--prs]]
Output: one line per entry without a carrier, then
`lesson-carriers summary: entries=N carried=N loose=N`. Exit 0 always (report).
--resolve (2026-10-30, operator: check every named carrier against the file): a carrier line naming a
path that does not exist prints `carrier missing:`; with --prs a named PR that is not merged prints
`carrier open:` — measured that evening: 5 of 116 named paths gone or never merged, 5 of 27 PRs open.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys

# OS-9: the session-close step and brain-scan-prep.py parse this output — pin the bytes
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

DEFAULTS = {
    "protocol": "docs/maintenance/feedback-protocol.md",
    "carrier_keys": ["Carrier"],
    "entry_heading": r"^## (\d{4}-\d{2}-\d{2})",
    # --resolve: where a named carrier may live, relative to the brain (`~` expands); the core submodule by default
    "carrier_roots": [".", "core"],
    # --prs: the repo a bare `#N` / `core #N` means, newest first, each valid from its `since` date on;
    # `pr_aliases` maps a name before `#N` ("grandma3-suite #186") to its repo
    "pr_repos": [],
    "pr_aliases": {},
}


def load_config(repo: str) -> dict:
    cfg = dict(DEFAULTS)
    path = os.path.join(repo, ".claude", "rules", "lesson-carriers.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for k in DEFAULTS:
            if k in data:
                cfg[k] = data[k]
    except (OSError, ValueError):
        pass
    return cfg


def entries(text: str, heading_rx: str):
    """Yield (date, title, body) per protocol entry whose heading carries a date."""
    rx = re.compile(heading_rx)
    cur = None
    for line in text.splitlines():
        m = rx.match(line)
        if m:
            if cur:
                yield cur
            cur = [m.group(1), line[m.end():].strip(" —-:·"), []]
        elif line.startswith("## ") and cur:
            yield cur
            cur = None
        elif cur is not None:
            cur[2].append(line)
    if cur:
        yield cur


def has_carrier(body: list[str], keys: list[str]) -> bool:
    return carrier_text(body, keys) is not None


def carrier_text(body: list[str], keys: list[str]):
    """The carrier line and its continuation lines (up to the next blank or `Key:` line), or None."""
    rx = re.compile(r"^\s*\**(?:%s)\**\s*:" % "|".join(re.escape(k) for k in keys), re.I)
    out = None
    for ln in body:
        if out is None:
            if rx.match(ln):
                out = [ln]
        elif not ln.strip() or re.match(r"^\s*\**[A-Z][\w-]*\**\s*:", ln):
            break
        else:
            out.append(ln)
    return None if out is None else " ".join(out)


# --- does the named carrier exist? (operator 2026-10-30: "check every named carrier against the file") ---
# A line can name a file that was moved or never merged, or a PR that is still open: it then reads as
# carried while nothing binds. --resolve checks backtick paths against the instance's roots; --prs adds
# the state of every named PR (network, slow). Report only — carrier-audit stays the gate for NEW entries.
PATH_RX = re.compile(r"`([^`\s]*?(?:/[^`\s]*|\.(?:py|sh|cjs|mjs|js|json|md|ya?ml|ps1)))(?::\d+)?`")
BRANCH_RX = re.compile(r"^(?:feat|fix|docs|chore|ci|refactor|test|alpha|release)/")
PR_RX = re.compile(r"(?:\b([A-Za-z][\w.-]*)[ -](?:PR )?)?#(\d+)\b")


class Roots:
    """Path lookup over the configured roots: exact relative path first, then a unique basename."""

    def __init__(self, roots):
        self.roots = roots
        self._names = None

    def _index(self):
        if self._names is None:
            self._names = {}
            for root in self.roots:
                for dp, dns, fns in os.walk(root):
                    dns[:] = [d for d in dns if d not in ("node_modules", ".git", "__pycache__")]
                    for fn in fns:
                        self._names.setdefault(fn, os.path.join(dp, fn))
        return self._names

    def exists(self, token: str) -> bool:
        token = token.strip("`'\"(),; ").rstrip(".")
        for root in self.roots:
            if os.path.exists(os.path.join(root, token)):
                return True
        return os.path.basename(token) in self._index()


def named_prs(text: str, cfg: dict, date: str):
    """(repo, number) for every PR the carrier line names; a bare or core-aliased #N goes to the core
    repo of its date (`pr_repos`: newest first, each with an optional `since`)."""
    aliases = {k.lower(): v for k, v in (cfg.get("pr_aliases") or {}).items()}
    out = []
    for m in PR_RX.finditer(text):
        name = (m.group(1) or "").lower()
        repo = aliases.get(name)
        if repo is None:
            if name and name not in ("pr", "kern", "core", "kern-pr", "core-pr"):
                continue                        # "issue #3", "step #2": not a PR of a known repo
            repo = next((r["repo"] for r in cfg.get("pr_repos") or [] if date >= r.get("since", "")), None)
        if repo:
            out.append((repo, int(m.group(2))))
    return out


def pr_state(repo: str, n: int, cache: dict) -> str:
    key = (repo, n)
    if key not in cache:
        import subprocess
        try:
            r = subprocess.run(["gh", "pr", "view", str(n), "-R", repo, "--json", "state", "-q", ".state"],
                               capture_output=True, text=True, timeout=30)
            cache[key] = r.stdout.strip() or "UNKNOWN"
        except (OSError, subprocess.SubprocessError):
            cache[key] = "UNKNOWN"
    return cache[key]


def main() -> int:
    ap = argparse.ArgumentParser(description="lessons in the feedback protocol without a carrier line")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--protocol")
    ap.add_argument("--since", help="only entries dated on/after YYYY-MM-DD")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--resolve", action="store_true", help="check that every backtick path a carrier names exists")
    ap.add_argument("--prs", action="store_true", help="with --resolve: also read the state of every named PR (gh, network)")
    a = ap.parse_args()
    cfg = load_config(a.repo)
    roots = Roots([os.path.normpath(os.path.join(a.repo, os.path.expanduser(r))) for r in cfg["carrier_roots"]])
    prs_cache: dict = {}
    missing, open_prs, paths_ok, prs_seen = [], [], 0, 0
    proto = a.protocol or os.path.join(a.repo, cfg["protocol"])
    try:
        with open(proto, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"lesson-carriers: cannot read {proto}: {e}")
        print("lesson-carriers summary: entries=0 carried=0 loose=0 (protocol unreadable — NOT checked)")
        return 0
    found, carried, loose = 0, 0, []
    for date, title, body in entries(text, cfg["entry_heading"]):
        if a.since and date < a.since:
            continue
        found += 1
        ctext = carrier_text(body, cfg["carrier_keys"])
        if ctext is None:
            loose.append({"date": date, "title": title})
            continue
        carried += 1
        if not a.resolve:
            continue
        for tok in dict.fromkeys(PATH_RX.findall(ctext)):
            if BRANCH_RX.match(tok) or "…" in tok:
                continue                        # a branch name or a shortened path names no file
            if roots.exists(tok):
                paths_ok += 1
            else:
                missing.append({"date": date, "title": title, "carrier": tok})
        if a.prs:
            for repo, n in dict.fromkeys(named_prs(ctext, cfg, date)):
                prs_seen += 1
                st = pr_state(repo, n, prs_cache)
                if st != "MERGED":
                    open_prs.append({"date": date, "title": title, "carrier": f"{repo}#{n}", "state": st})
    if a.json:
        print(json.dumps({"entries": found, "carried": carried, "loose": loose, "missing": missing,
                          "open": open_prs}, ensure_ascii=False, indent=1))
    else:
        for l in loose:
            print(f"lesson without carrier: {l['date']} — {l['title']}")
        for m in missing:
            print(f"carrier missing: {m['date']} — {m['title']} — `{m['carrier']}` not found")
        for o in open_prs:
            print(f"carrier open: {o['date']} — {o['title']} — {o['carrier']} is {o['state']}")
        extra = ""
        if a.resolve:
            extra = f" paths_ok={paths_ok} missing={len(missing)}"
            if a.prs:
                extra += f" prs={prs_seen} open={len(open_prs)}"
        print(f"lesson-carriers summary: entries={found} carried={carried} loose={len(loose)}{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
