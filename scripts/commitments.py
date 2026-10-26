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
# Since 2026-10-26 (operator: "a rule entered in the feedback amounts to an empty promise in the long run")
# only a write to a MECHANISM carries a commitment: a helper or script, hook/settings data, a rules .json
# a gate reads, mechanism rules, a CI workflow. A write to rule text, memory or feedback is PROSE — the
# commitment is reported as not carried, with that reason.
MECH_PATH = re.compile(r"/helpers/[^/]+\.(?:c?js|mjs|sh)$|/scripts/[^/]+\.(?:py|sh|c?js|mjs|ps1)$|/hooks/|"
                       r"/\.claude/(?:settings(?:\.local)?\.json|rules/[^/]+\.json)$|mechanism-rules\.json$|"
                       r"/\.github/workflows/", re.I)
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


FOLD = str.maketrans({"\u00e4": "ae", "\u00f6": "oe", "\u00fc": "ue", "\u00df": "ss"})


def words(text, stop):
    # umlauts folded: chat writes the umlaut, repo files often carry the ae/oe/ue spelling
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
                if RULE_PATH.search(fp) or MECH_PATH.search(fp):
                    body = " ".join(str(inp.get(k) or "") for k in ("content", "new_string"))
                    for e in inp.get("edits") or []:
                        body += " " + str(e.get("new_string") or "")
                    # the file name speaks too: a gate called no-window-from-bridge carries "window"
                    body += " " + re.sub(r"[^A-Za-z]+", " ", os.path.basename(fp))
                    writes.append((ts, words(body, stop), bool(MECH_PATH.search(fp))))
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
    loose, carried, total, prose = [], 0, 0, 0
    paras = None
    for f in sorted(files):
        found, writes = scan_session(f, patterns, stop, first)
        for ts, sent in found:
            total += 1
            need = words(sent, stop)
            match = lambda w: need and len(need & w) >= min(2, len(need))
            # carried: a MECHANISM write in the same session that shares at least two load-bearing words
            if any(mech and match(w) for _, w, mech in writes):
                carried += 1
                continue
            # prose: only rule text / memory / feedback holds it (same session, or today's rule text/docs)
            in_text = any((not mech) and match(w) for _, w, mech in writes)
            if not in_text and len(need) >= 3:
                if paras is None:
                    paras = rule_paragraphs(a.repo, stop)
                in_text = any(len(need & p) >= max(3, int(0.6 * len(need) + 0.999)) for p in paras)
            prose += 1 if in_text else 0
            loose.append({"session": os.path.basename(f)[:8], "at": ts[:16], "sentence": sent[:200],
                          "why": "prose only — rule text, memory or feedback, no mechanism" if in_text else "nothing written"})
    # Without instance phrasing only English is matched — in a brain that speaks another
    # language "found=0" is a coverage gap, not a result (Windows check 2026-10-09).
    scope = "all" if data.get("patterns") else "english-only"
    if a.json:
        print(json.dumps({"found": total, "carried": carried, "prose": prose, "loose": loose, "phrasing": scope}, ensure_ascii=False))
        return 0
    for l in loose:
        print(f"loose commitment ({l['why']}): {l['at']} session {l['session']}: {l['sentence']}")
    if scope == "english-only":
        print("commitments: only English phrasing checked — add this brain's language in .claude/rules/commitments.json (template in core templates/rules-instance/)")
    print(f"commitments summary: found={total} carried={carried} prose={prose} loose={len(loose)} phrasing={scope}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
