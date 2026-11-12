#!/usr/bin/env python3
"""claim-lint.py — check ```claim blocks against the claim schema. Deterministic, stdlib, no judgment.

The core rule (rules/thinking-protocol.md, Anti-Hallucination rule 0, "Checkable form"): a
load-bearing claim is written as a `claim` block — assessment x risk x evidence[] x freshness
(`retrieved_at` <= `reviewed_at`) x independence. The schema was built parse-ready on purpose,
so that a linter is cheap; this is that linter. Ported from the macOS instance (2026-08-02 to
2026-11-07), where the schema and its first runlogs live.

Form of a block (YAML subset, one per fence):

    ```claim
    id: <short unique id>
    statement: <the claim in ONE sentence>
    assessment: accepted | provisional | contested | unsupported
    risk: low | medium | high
    evidence:
      - source: <instrument + measuring point, repeatable>
        method: measured | derived | assumed
        retrieved_at: <YYYY-MM-DD HH:MM>
        value: <number with unit, or the observed state>
    reviewed_at: <YYYY-MM-DD HH:MM>
    independence: <where the evidence does NOT overlap - or "none">
    ```

Checked — the three rules that need NO judgment:
  1. `assumed` evidence never carries `accepted` — a hedge word replaces no evidence.
  2. `retrieved_at` <= `reviewed_at` — evidence that came into being after its review is a typo
     or an invented freshness.
  3. `risk: high` + `accepted` needs two pieces of evidence AND a filled `independence` — two
     readings from the same instrument are ONE piece of evidence.
Plus the form: required fields, known assessment/risk/method values. `unsupported` without
evidence is the CORRECT form ("cause unknown" written down), never a finding — a linter that
flags it pushes towards inventing a piece of evidence.

NOT checked, on purpose: whether `source` really names the entity (a judgment) and whether a
refutation was attached (needs history). A linter that pretends to check those reports green
for a question it never asked.

Instance data (`.claude/rules/claim-schema.json`, template
`templates/rules-instance/claim-schema.json`) — the core hardcodes no schema location and no
vocabulary of an operator's language:
  schema          path of the brain's human-readable schema document (relative to the root);
                  named in the report, skipped as a source of blocks; a declared path that does
                  not exist is a finding (a pointer into nothing)
  paths           where to look for blocks when no path is given (default ["docs"])
  method_aliases  {"<word in the brain's language>": "measured|derived|assumed"}
  none_words      words that mean "none" in `independence`, besides "none"

Usage: claim-lint.py [--root DIR] [path ...]   (root: $CLAUDE_PROJECT_DIR, else cwd)
Exit 0 = clean (or no block found), 1 = findings.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys

# OS-9: brain-selftest.sh reads this stdout (`!!` lines); pin UTF-8 and LF on every platform.
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

ASSESSMENTS = {"accepted", "provisional", "contested", "unsupported"}
RISKS = {"low", "medium", "high"}
METHODS = {"measured", "derived", "assumed"}
REQUIRED = ("id", "statement", "assessment", "risk", "evidence", "reviewed_at")
CONFIG = pathlib.Path(".claude") / "rules" / "claim-schema.json"

FENCE = re.compile(r"^```claim\s*$(.*?)^```\s*$", re.M | re.S)


def load_config(root: pathlib.Path) -> dict:
    try:
        cfg = json.loads((root / CONFIG).read_text(encoding="utf-8"))
        return cfg if isinstance(cfg, dict) else {}
    except (OSError, ValueError):
        return {}


def parse_block(text: str) -> dict:
    """Minimal parser for exactly this YAML subset. No PyYAML: the format is controlled, and a
    dependency for six keys would be absurd."""
    data: dict = {}
    evidence: list[dict] = []
    current = None
    in_evidence = False
    for raw in text.splitlines():
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        z = raw.strip()
        if indent == 0 and z.startswith("evidence:"):
            in_evidence = True
            continue
        if indent == 0 and ":" in z:
            in_evidence = False
            current = None
            k, _, v = z.partition(":")
            data[k.strip()] = v.strip()
            continue
        if in_evidence:
            if z.startswith("- "):
                current = {}
                evidence.append(current)
                z = z[2:].strip()
            if current is not None and ":" in z:
                k, _, v = z.partition(":")
                current[k.strip()] = v.strip()
    data["evidence"] = evidence
    return data


def method_of(raw: str, aliases: dict) -> str:
    m = raw.strip().lower()
    m = str(aliases.get(m, m)).lower()
    # the core's live-doc vocabulary ("measured A/B/A", "measured once") is a measured method
    return "measured" if m.startswith("measured") else m


def check(c: dict, where: str, aliases: dict, none_words: set) -> list[str]:
    f = []
    a = c.get("assessment", "")
    required = [k for k in REQUIRED if not (k == "evidence" and a == "unsupported")]
    missing = [k for k in required if not c.get(k)]
    if missing:
        f.append(f"required field missing: {', '.join(missing)}")
    r = c.get("risk", "")
    if a and a not in ASSESSMENTS:
        f.append(f"assessment '{a}' unknown (allowed: {', '.join(sorted(ASSESSMENTS))})")
    if r and r not in RISKS:
        f.append(f"risk '{r}' unknown (allowed: {', '.join(sorted(RISKS))})")

    ev = c.get("evidence") or []
    for i, e in enumerate(ev, 1):
        raw = e.get("method", "")
        m = method_of(raw, aliases) if raw else ""
        if m and m not in METHODS:
            f.append(f"evidence[{i}].method '{raw}' unknown (allowed: {', '.join(sorted(METHODS))}, "
                     "or an alias in claim-schema.json)")
        if m == "assumed" and a == "accepted":
            f.append(f"RULE 1: evidence[{i}] is '{raw}' (assumed), the claim 'accepted' "
                     "- a hedge word replaces no evidence")
        rt, rv = e.get("retrieved_at", ""), c.get("reviewed_at", "")
        if rt and rv and rt > rv:
            f.append(f"RULE 2: evidence[{i}].retrieved_at ({rt}) is AFTER reviewed_at ({rv}) "
                     "- the evidence cannot support the review")
    if r == "high" and a == "accepted":
        ind = (c.get("independence") or "").strip().lower()
        if len(ev) < 2 or not ind or ind in none_words:
            f.append("RULE 3: risk=high + accepted needs TWO pieces of evidence and a filled "
                     "'independence' - two readings from the same instrument are ONE piece of evidence")
    return [f"{where}: {x}" for x in f]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    ap.add_argument("paths", nargs="*")
    args = ap.parse_args(argv)
    root = pathlib.Path(args.root)
    cfg = load_config(root)
    aliases = {str(k).lower(): v for k, v in (cfg.get("method_aliases") or {}).items()}
    none_words = {"none"} | {str(w).lower() for w in (cfg.get("none_words") or [])}
    schema = cfg.get("schema")

    findings: list[str] = []
    schema_path = None
    if schema:
        schema_path = (root / schema).resolve()
        if not schema_path.is_file():
            findings.append(f"{CONFIG.as_posix()}: schema '{schema}' does not exist - the pointer leads nowhere")

    targets = [pathlib.Path(p) for p in args.paths] or [root / p for p in (cfg.get("paths") or ["docs"])]
    files: list[pathlib.Path] = []
    for t in targets:
        if not t.is_absolute() and not t.exists():
            t = root / t
        files += sorted(t.rglob("*.md")) if t.is_dir() else ([t] if t.is_file() else [])

    n = 0
    for p in files:
        if schema_path is not None and p.resolve() == schema_path:
            continue  # the schema carries the FORM with placeholders - a template, not a claim
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in FENCE.finditer(text):
            c = parse_block(m.group(1))
            # a placeholder block (`id: <short unique id>`) is a template, not a claim
            if str(c.get("id", "")).startswith("<"):
                continue
            n += 1
            line = text[:m.start()].count("\n") + 1
            try:
                shown = p.resolve().relative_to(root.resolve()).as_posix()
            except ValueError:
                shown = p.as_posix()
            findings += check(c, f"{shown}:{line} [{c.get('id', '?')}]", aliases, none_words)

    form = f"form: {schema}" if schema else f"form: the core rule (no schema declared in {CONFIG.as_posix()})"
    for b in findings:
        print(f"!! {b}")
    if not n:
        print(f"claim-lint: no claim block found - nothing to check ({form})")
    else:
        print(f"claim-lint: {n} claim block(s), {len(findings)} finding(s) ({form})")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
