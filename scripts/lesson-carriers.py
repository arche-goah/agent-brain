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

SECOND SOURCE, the memory (2026-10-26, from the Windows workstation instance): a memory of type
`feedback` is evidence of a lesson, so it names what carries the lesson in its frontmatter,
in the field format of memory-lint's `rule_home` (#123):
    metadata.carrier: <repo-relative file> :: <phrase that file holds>   — or —
    metadata.carrier: prose, because <why no mechanism fits>
Missing field, missing file, missing phrase = loose. The memory folder is Claude Code's
auto-memory of the repo (~/.claude/projects/<minted repo path>/memory), `--memory` or
`memory_dir` override it; a folder that does not exist is skipped. `--since` reads the
memory's `metadata.modified` (else the file's mtime). MEMORY.md and topic indexes are skipped.

Instance data: `.claude/rules/lesson-carriers.json`
    {"protocol": "docs/maintenance/feedback-protocol.md",
     "carrier_keys": ["Carrier"],
     "entry_heading": "^## (\\d{4}-\\d{2}-\\d{2})",
     "memory_dir": "<optional override>", "memory_types": ["feedback"]}
Usage: lesson-carriers.py [--repo DIR] [--protocol FILE] [--memory DIR] [--since YYYY-MM-DD] [--json]
Output: one line per entry without a carrier, then
`lesson-carriers summary: entries=N carried=N loose=N`; with a memory folder also one line per
loose memory and `lesson-carriers memory: memories=N carried=N loose=N`. Exit 0 always (report).
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
    "memory_dir": "",
    "memory_types": ["feedback"],
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
    rx = re.compile(r"^\s*\**(?:%s)\**\s*:" % "|".join(re.escape(k) for k in keys), re.I)
    return any(rx.match(ln) for ln in body)


def _frontmatter():
    """memory-lint's parser, so both read a memory the same way (no second YAML subset)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "memory_lint", os.path.join(os.path.dirname(os.path.abspath(__file__)), "memory-lint.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.frontmatter


def memory_carriers(repo: str, mem_dir: str, types: list[str], since: str | None):
    """(checked, carried, loose) over the memories of the given types; loose = [{file, issue}]."""
    import datetime
    fm_of = _frontmatter()
    checked, carried, loose = 0, 0, []
    for name in sorted(os.listdir(mem_dir)):
        if not name.endswith(".md") or name == "MEMORY.md" or name.startswith("index-"):
            continue
        path = os.path.join(mem_dir, name)
        with open(path, encoding="utf-8", errors="replace") as f:
            fm = fm_of(f.read()) or {}
        meta = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
        if meta.get("type") not in types:
            continue
        stamp = (meta.get("modified") or "")[:10] or datetime.date.fromtimestamp(
            os.path.getmtime(path)).isoformat()
        if since and stamp < since:
            continue
        checked += 1
        val = (meta.get("carrier") or "").strip()
        if re.match(r"(?i)prose,\s*because\s+\S", val):
            carried += 1
            continue
        target, sep, anchor = val.partition("::")
        target, anchor = target.strip(), anchor.strip()
        if not val:
            issue = "no metadata.carrier"
        elif not sep or not target or not anchor:
            issue = f"carrier '{val}' is not '<file> :: <phrase>' or 'prose, because ...'"
        elif not os.path.isfile(os.path.join(repo, target)):
            issue = f"carrier file {target} missing"
        else:
            with open(os.path.join(repo, target), encoding="utf-8", errors="replace") as f:
                issue = None if anchor in f.read() else f"phrase not in {target}: {anchor}"
        if issue:
            loose.append({"file": name, "issue": issue})
        else:
            carried += 1
    return checked, carried, loose


def default_memory_dir(repo: str) -> str:
    # Claude Code mints the project path: every character except [A-Za-z0-9] becomes '-'
    # (same minting as memory-lint.py and helpers/session-bootup.sh).
    minted = re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(repo))
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", minted, "memory")


def main() -> int:
    ap = argparse.ArgumentParser(description="lessons in the feedback protocol without a carrier line")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--protocol")
    ap.add_argument("--memory", help="memory folder (default: the repo's auto-memory)")
    ap.add_argument("--since", help="only entries dated on/after YYYY-MM-DD")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.repo)
    mem_dir = a.memory or cfg.get("memory_dir") or default_memory_dir(a.repo)
    mem = memory_carriers(a.repo, mem_dir, list(cfg.get("memory_types") or []), a.since) \
        if os.path.isdir(mem_dir) else None
    proto = a.protocol or os.path.join(a.repo, cfg["protocol"])
    try:
        with open(proto, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"lesson-carriers: cannot read {proto}: {e}")
        print("lesson-carriers summary: entries=0 carried=0 loose=0 (protocol unreadable — NOT checked)")
        print_memory(mem, a.json)
        return 0
    found, carried, loose = 0, 0, []
    for date, title, body in entries(text, cfg["entry_heading"]):
        if a.since and date < a.since:
            continue
        found += 1
        if has_carrier(body, cfg["carrier_keys"]):
            carried += 1
        else:
            loose.append({"date": date, "title": title})
    if a.json:
        out = {"entries": found, "carried": carried, "loose": loose}
        if mem is not None:
            out["memory"] = {"memories": mem[0], "carried": mem[1], "loose": mem[2]}
        print(json.dumps(out, ensure_ascii=False, indent=1))
    else:
        for l in loose:
            print(f"lesson without carrier: {l['date']} — {l['title']}")
        print(f"lesson-carriers summary: entries={found} carried={carried} loose={len(loose)}")
        print_memory(mem, False)
    return 0


def print_memory(mem, as_json: bool) -> None:
    if mem is None or as_json:
        return
    for l in mem[2]:
        print(f"memory without carrier: {l['file']} — {l['issue']}")
    print(f"lesson-carriers memory: memories={mem[0]} carried={mem[1]} loose={len(mem[2])}")


if __name__ == "__main__":
    sys.exit(main())
