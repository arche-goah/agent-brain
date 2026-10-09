#!/usr/bin/env python3
"""commitments.py — which promises about future behaviour did the AI make in chat without
writing them down where rules live?

WHY (measured on the proving brain 2026-10-09): in the middle of a session the AI wrote
"from now on I start the CI watch for every new PR in the same turn" — a commitment about
future behaviour, made only in chat. Nothing carried it: no rule file was written, so no
later session, no other brain and no check could see it, let alone decide whether it is a
local habit or a rule for every brain. The operator: "that has to be avoided — it needs
binding, standardised, mechanical procedures, for us and for everyone else".

The invariant (core rule, working-rules "a commitment about future behaviour becomes rule
text in the same turn"): every such sentence has a CARRIER — a write to a rule location in
the same session that shares its load-bearing words. This script finds the ones without.
It is a REPORT, not a gate: it runs at session close (this session) and in the brain-scan
(every session since the last scan), so it never fires in the middle of a conversation.

Commitment phrasing: English built in; other languages as instance data
`.claude/rules/commitments.json` {"patterns": [...], "first_person": [...], "stopwords": [...]}.
Only first-person sentences count: "the detector will report it from now on" is a statement
about a tool, "from now on I say X" is a commitment.
Rule locations: CLAUDE.md, AGENTS.md, CONVENTIONS.md, any path with /rules/ or /skills/,
memory files, feedback files.

Usage: commitments.py [--dir TRANSCRIPTS] [--session ID] [--days N] [--repo DIR] [--json]
Output: one line per loose commitment, then `commitments summary: found=N carried=N loose=N`.
Exit 0 always.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

BUILTIN = [r"\bfrom now on\b", r"\bgoing forward\b", r"\bin future,? i(?:'ll| will)\b",
           r"\bi(?:'ll| will) always\b", r"\bfrom here on\b", r"\bhenceforth\b"]
FIRST_PERSON = [r"\b(i|we)\b", r"\bi'(ll|m)\b"]  # a commitment is made BY the speaker, not about a tool
RULE_PATH = re.compile(r"(^|/)(CLAUDE\.md|AGENTS\.md|CONVENTIONS\.md)$|/rules/|/skills/|/memory/|feedback", re.I)
STOP = {"which", "every", "their", "there", "these", "those", "about", "after", "before", "where",
        "would", "should", "could", "other", "being", "doing", "start", "starts", "always", "future",
        "going", "forward"}


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def default_dir(repo):
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    key = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(repo))
    return os.path.join(cfg, "projects", key)


FOLD = str.maketrans({"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss"})


def words(text, stop):
    # umlauts folded: chat writes "ändere", repo files often carry "aendere"
    low = text.lower().translate(FOLD)
    return {w for w in re.findall(r"[a-z]{5,}", low) if w not in stop}


def rule_paragraphs(repo, stop):
    """Word sets of every paragraph in today's rule text and docs — a commitment carried in a
    LATER session (or written into a doc) counts too, but only on a strong match."""
    import pathlib
    root = pathlib.Path(repo)
    files = [root / n for n in ("CLAUDE.md", "AGENTS.md", "CONVENTIONS.md")]
    for pat in (".claude/rules/*.md", "rules/*.md", "skills/*/SKILL.md", ".claude/skills/*/SKILL.md", "docs/**/*.md"):
        files += list(root.glob(pat))
    out = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        out += [words(p, stop) for p in re.split(r"\n\s*\n|\n- ", text) if len(p) > 40]
    return out


def scan_session(path, patterns, stop, first):
    """(commitments, rule_writes) — commitments as (timestamp, sentence), writes as (timestamp, words)."""
    found, writes = [], []
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return found, writes
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") != "assistant":
            continue
        ts = rec.get("timestamp", "")
        for block in (rec.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                for sent in re.split(r"(?<=[.!?])\s+|\n+", block.get("text") or ""):
                    # quoted text is mention, not commitment ("words like 'from now on'")
                    bare = re.sub(r"„[^“”]*[“”]|\"[^\"]*\"|`[^`]*`|'[^']{3,}'", " ", sent)
                    if any(re.search(p, bare, re.I) for p in patterns) and any(re.search(p, bare, re.I) for p in first):
                        found.append((ts, sent.strip()))
            elif block.get("type") == "tool_use" and block.get("name") in ("Edit", "Write", "MultiEdit"):
                inp = block.get("input") or {}
                fp = str(inp.get("file_path") or "").replace("\\", "/")
                if RULE_PATH.search(fp):
                    body = " ".join(str(inp.get(k) or "") for k in ("content", "new_string"))
                    for e in inp.get("edits") or []:
                        body += " " + str(e.get("new_string") or "")
                    writes.append((ts, words(body, stop)))
    return found, writes


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    ap.add_argument("--dir")
    ap.add_argument("--session")
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    data = load(os.path.join(a.repo, ".claude", "rules", "commitments.json"))
    patterns = BUILTIN + list(data.get("patterns") or [])
    stop = STOP | {s.lower() for s in data.get("stopwords") or []}
    first = FIRST_PERSON + list(data.get("first_person") or [])
    d = a.dir or default_dir(a.repo)
    if a.session:
        files = [os.path.join(d, a.session + ".jsonl")]
    else:
        cutoff = datetime.datetime.now().timestamp() - a.days * 86400
        files = [f for f in glob.glob(os.path.join(d, "*.jsonl")) if os.path.getmtime(f) >= cutoff]
    loose, carried, total = [], 0, 0
    paras = None
    for f in sorted(files):
        found, writes = scan_session(f, patterns, stop, first)
        for ts, sent in found:
            total += 1
            need = words(sent, stop)
            # carried (a): a rule write in the same session that shares at least two
            # load-bearing words (or all of them, for a very short sentence)
            same = any(len(need & w) >= min(2, len(need)) for _, w in writes) and need
            # carried (b): today's rule text or docs hold it — one paragraph with at least 60 %
            # of the words (minimum three), so a later session's carrier counts too
            if not same and len(need) >= 3:
                if paras is None:
                    paras = rule_paragraphs(a.repo, stop)
                same = any(len(need & p) >= max(3, int(0.6 * len(need) + 0.999)) for p in paras)
            if same:
                carried += 1
            else:
                loose.append({"session": os.path.basename(f)[:8], "at": ts[:16], "sentence": sent[:200]})
    if a.json:
        print(json.dumps({"found": total, "carried": carried, "loose": loose}, ensure_ascii=False))
        return 0
    for l in loose:
        print(f"loose commitment: {l['at']} session {l['session']}: {l['sentence']}")
    print(f"commitments summary: found={total} carried={carried} loose={len(loose)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
