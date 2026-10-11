#!/usr/bin/env python3
"""check-table.py — the beta check table of a tag: read it, render it, and say whether stable is reachable.

WHY (operator word 2026-10-11): "OS should simply be its own category that every device enters, as generic and
versatile as possible". A grid with one column per system gives a second checker on the same system no place and
shows only the latest result per cell, so a later green hides an earlier red (measured on a repo's generator the day
this was written). AGENTS.md #12 therefore defines the table as a RESULTS LIST: no system appears in its shape.

The form (one file per tag, e.g. releases/<tag>.md):
    required_os: macOS, Windows
    ## Checks            table  id | Check
    ## Results           table  check | device | os | software | commit | date | result | note
    ## ... owner's word  free text — the owner's judgement, in the owner's words
`result` is `pass`, `fail — <what>` or `n/a — <why>`. Entries are appended, never overwritten.

Rules the verdict applies (AGENTS.md #12):
  - per check and device only the LATEST entry counts (date, then file order); a device that failed and later
    passed has resolved its fail, a fail on another device stays open;
  - a check is red while any device's latest entry is a fail;
  - a check is satisfied on a required OS by a `pass` of one device with that OS, or by an `n/a — <reason>` (an
    n/a without a reason does not count: no silent tick);
  - READY for stable = every check satisfied on every required OS, no open fail, owner's word recorded.

Usage:
    check-table.py verdict <file.md>                        exit 0 READY · 1 NOT ready · 2 input unreadable
    check-table.py verdict --results R.jsonl --checks C.json [--owner-file F]
    check-table.py render  --results R.jsonl --checks C.json [--owner-file F] [--title T] > releases/<tag>.md
R.jsonl: one JSON object per line with the eight result fields. C.json: {"required_os": [...], "checks":
[{"id": "...", "check": "..."}]}. Unreadable input is exit 2 and never read as READY.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FIELDS = ("check", "device", "os", "software", "commit", "date", "result", "note")
DATE_RX = re.compile(r"^\d{4}-\d{2}-\d{2}")
SPLIT_RX = re.compile(r"(?<!\\)\|")
PLACEHOLDERS = {"", "-", "—", "tbd", "todo", "pending", "none", "none yet", "not yet recorded", "n/a"}


class InputError(Exception):
    pass


def cells(line: str) -> list[str]:
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|") and not inner.endswith("\\|"):
        inner = inner[:-1]
    return [c.strip().replace("\\|", "|") for c in SPLIT_RX.split(inner)]


def is_separator(line: str) -> bool:
    return bool(re.match(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$", line))


def section(text: str, heading_rx: str) -> list[str]:
    """Lines of the first `## ...` section whose heading matches, up to the next `## `."""
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = bool(re.search(heading_rx, line[3:], re.I))
            continue
        if inside:
            out.append(line)
    return out


def table_rows(lines: list[str], header: tuple[str, ...]) -> list[list[str]]:
    """Data rows of the first table whose header row names `header` (case-insensitive), after its separator."""
    want = [h.lower() for h in header]
    rows, state = [], 0
    for line in lines:
        if not line.strip().startswith("|"):
            if state == 2:
                break
            continue
        c = cells(line)
        if state == 0:
            if [x.lower() for x in c][: len(want)] == want:
                state = 1
        elif state == 1:
            state = 2 if is_separator(line) else 0
        else:
            if [x.lower() for x in c][: len(want)] == want:
                continue            # a repeated header row is never data
            rows.append(c)
    return rows


def parse_markdown(text: str) -> dict:
    m = re.search(r"^\s*required_os\s*:\s*(.+?)\s*$", text, re.I | re.M)
    if not m:
        raise InputError("no `required_os:` line")
    required = [x.strip() for x in m.group(1).split(",") if x.strip()]
    check_rows = table_rows(section(text, r"^checks?\b"), ("id", "check"))
    checks = [(r[0], r[1] if len(r) > 1 else "") for r in check_rows if r and r[0]]
    result_rows = table_rows(section(text, r"^results?\b"), FIELDS)
    results, skipped = [], []
    for i, r in enumerate(result_rows, 1):
        r = (r + [""] * len(FIELDS))[: len(FIELDS)]
        rec = dict(zip(FIELDS, r))
        if not DATE_RX.match(rec["date"]):
            skipped.append("row %d (date %r)" % (i, rec["date"]))
            continue
        results.append(rec)
    owner = "\n".join(section(text, r"owner'?s?\s+word")).strip()
    return {"required_os": required, "checks": checks, "results": results, "owner": owner, "skipped": skipped,
            "has_results_table": bool(table_rows(section(text, r"^results?\b"), FIELDS)) or "## Results" in text}


def load_jsonl(results_path: str, checks_path: str, owner_file: str | None) -> dict:
    try:
        spec = json.loads(Path(checks_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise InputError("checks file: %s" % e)
    required = [str(x) for x in spec.get("required_os", [])]
    if not required:
        raise InputError("checks file has no required_os")
    checks = [(c["id"], c.get("check", "")) for c in spec.get("checks", [])]
    results, skipped = [], []
    try:
        lines = Path(results_path).read_text(encoding="utf-8").splitlines()
    except OSError as e:
        raise InputError("results file: %s" % e)
    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            raise InputError("results line %d is not JSON" % i)
        rec = {k: str(rec.get(k, "")) for k in FIELDS}
        if not DATE_RX.match(rec["date"]):
            skipped.append("line %d (date %r)" % (i, rec["date"]))
            continue
        results.append(rec)
    owner = ""
    if owner_file:
        try:
            owner = Path(owner_file).read_text(encoding="utf-8").strip()
        except OSError as e:
            raise InputError("owner file: %s" % e)
    return {"required_os": required, "checks": checks, "results": results, "owner": owner, "skipped": skipped,
            "has_results_table": True}


def kind(result: str) -> tuple[str, str]:
    """-> (pass|fail|na|other, text after the first dash)."""
    head = result.strip()
    low = head.lower()
    why = re.split(r"\s[—–-]+\s", head, maxsplit=1)
    text = why[1].strip() if len(why) > 1 else ""
    for k, key in (("pass", "pass"), ("fail", "fail"), ("na", "n/a")):
        if low.startswith(key):
            return k, text
    return "other", text


def same_family(os_field: str, required: str) -> bool:
    """The os field names system AND version (`Windows 11 Pro 23H2 (10.0.22631)`, `macOS 26.0`); required_os names
    the family. They match when the field is the family or starts with it as a whole word, case-insensitive."""
    f, r = os_field.strip().lower(), required.strip().lower()
    return bool(r) and (f == r or re.match(re.escape(r) + r"(?![\w])", f) is not None)


def owner_open_questions(owner: str) -> list[str]:
    """Table rows of the owner section (question | answer) whose answer is empty or a placeholder such as `open`.
    A section that exists is not a word that was given: every row must carry an answer."""
    lines = owner.splitlines()
    rows = []
    for i, line in enumerate(lines):
        if not line.strip().startswith("|") or is_separator(line):
            continue
        if i + 1 < len(lines) and is_separator(lines[i + 1]):
            continue                    # the header row
        c = cells(line)
        if c and c[0]:
            rows.append((c[0], c[1] if len(c) > 1 else ""))
    return [q for q, a in rows if a.strip().lower() in PLACEHOLDERS | {"open", "?"}]


def cell_states(model: dict, min_commits: int = 2) -> list[str]:
    """Optional per-cell view (`verdict --cells`): one line per check and required OS.
    RED    an open fail on any device of that OS (the latest entry of a device is a fail)
    STABLE passes on that OS were recorded on at least `min_commits` DIFFERENT commits (same check, any device of
           that OS) and no fail on that OS for that check since its first pass
    BETA   at least one pass, no open fail, not stable — names device, date and commit of the latest pass
    N/A    only `n/a — <reason>` entries      LACKS  nothing recorded
    A cell state, not a release word: whether a tag may go stable stays with the verdict and the owner."""
    out = []
    ordered = [r for _i, r in sorted(enumerate(model["results"]), key=lambda t: (t[1]["date"], t[0]))]
    for cid, _text in model["checks"]:
        for o in model["required_os"]:
            ent = [r for r in ordered if r["check"] == cid and same_family(r["os"], o)]
            latest: dict = {}
            for r in ent:
                latest[r["device"]] = r
            red = [d for d, r in latest.items() if kind(r["result"])[0] == "fail"]
            passes = [r for r in ent if kind(r["result"])[0] == "pass"]
            nas = [r for r in ent if kind(r["result"])[0] == "na" and kind(r["result"])[1]]
            if red:
                state, detail = "RED", "open fail on %s" % ", ".join(red)
            elif passes:
                first = ent.index(passes[0])
                fail_after = any(kind(r["result"])[0] == "fail" for r in ent[first:])
                commits = {r["commit"] for r in passes if r["commit"].strip()}
                last = passes[-1]
                if len(commits) >= min_commits and not fail_after:
                    state, detail = "STABLE", "passes on %d commits" % len(commits)
                else:
                    why = "a fail since the first pass" if fail_after else "passes on %d commit(s)" % len(commits)
                    state, detail = "BETA", "%s; latest pass %s %s %s" % (why, last["device"], last["date"], last["commit"])
            elif nas:
                state, detail = "N/A", nas[-1]["result"]
            else:
                state, detail = "LACKS", "nothing recorded"
            out.append("cell  %s | %s | %s | %s" % (cid, o, state, detail))
    return out


def verdict(model: dict) -> tuple[bool, list[str]]:
    required = model["required_os"]
    # latest entry per (check, device): later date wins, equal dates keep file order
    latest: dict = {}
    for idx, r in sorted(enumerate(model["results"]), key=lambda t: (t[1]["date"], t[0])):
        latest[(r["check"], r["device"])] = r
    lines, lacking_total, red_total = [], 0, 0
    known = {c[0] for c in model["checks"]}
    for cid, text in model["checks"]:
        per_dev = [r for (c, _d), r in latest.items() if c == cid]
        fails = [r for r in per_dev if kind(r["result"])[0] == "fail"]
        covered, lacking = [], []
        for o in required:
            ok = False
            for r in per_dev:
                if not same_family(r["os"], o):
                    continue
                k, why = kind(r["result"])
                if k == "pass" or (k == "na" and why):
                    ok = True
            (covered if ok else lacking).append(o)
        label = "%s%s" % (cid, (" — " + text) if text else "")
        if fails:
            red_total += 1
            what = "; ".join("%s: %s" % (r["device"], kind(r["result"])[1] or "fail") for r in fails)
            lines.append("RED   %s — open fail on %s" % (label, what))
        if lacking:
            lacking_total += 1
            lines.append("LACKS %s — no pass yet on: %s" % (label, ", ".join(lacking)))
        if not fails and not lacking:
            lines.append("ok    %s — pass on %s" % (label, ", ".join(covered)))
    for cid in sorted({r["check"] for r in model["results"]} - known):
        lines.append("note  result for a check that is not in the list: %s" % cid)
    for s in model["skipped"]:
        lines.append("note  skipped %s: not a result line" % s)
    owner = model["owner"].strip()
    open_q = owner_open_questions(owner)
    owner_ok = owner.lower() not in PLACEHOLDERS and not re.fullmatch(r"_.*_", owner) and not open_q
    for q in open_q:
        lines.append("OWNER open question: %s" % q)
    if not owner_ok and not open_q:
        lines.append("OWNER the owner's word is not recorded")
    ready = lacking_total == 0 and red_total == 0 and owner_ok and bool(model["checks"])
    if not model["checks"]:
        lines.append("note  the check list is empty — nothing to pass")
    lines.append("check-table: %s — required_os %s; %d check(s) lack a pass, %d with an open fail, owner's word %s" % (
        "READY for stable" if ready else "NOT ready", ", ".join(required), lacking_total, red_total,
        "recorded" if owner_ok else "missing"))
    return ready, lines


def esc(s: str) -> str:
    return str(s).replace("|", "\\|").replace("\n", " ")


def render(model: dict, title: str) -> str:
    out = ["# %s" % title, "", "<!-- rendered by scripts/check-table.py from the result lines; add lines, never edit one -->", "",
           "required_os: %s" % ", ".join(model["required_os"]), "", "## Checks", "", "| id | Check |", "|---|---|"]
    for cid, text in model["checks"]:
        out.append("| %s | %s |" % (esc(cid), esc(text)))
    out += ["", "## Results", "", "| " + " | ".join(FIELDS) + " |", "|" + "---|" * len(FIELDS)]
    for r in sorted(model["results"], key=lambda r: r["date"]):
        out.append("| " + " | ".join(esc(r[k]) for k in FIELDS) + " |")
    out += ["", "## The owner's word", "", model["owner"] or "_not yet recorded_", ""]
    return "\n".join(out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verdict")
    v.add_argument("file", nargs="?")
    v.add_argument("--cells", action="store_true", help="also print one line per check and required OS (off by default)")
    v.add_argument("--min-commits", type=int, default=2, help="different commits a STABLE cell needs (with --cells)")
    r = sub.add_parser("render")
    for p in (v, r):
        p.add_argument("--results")
        p.add_argument("--checks")
        p.add_argument("--owner-file")
    r.add_argument("--title", default="Check table")
    a = ap.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")   # OS-9: callers parse this output
    try:
        if a.cmd == "verdict" and a.file:
            try:
                text = Path(a.file).read_text(encoding="utf-8")
            except OSError as e:
                raise InputError(str(e))
            model = parse_markdown(text)
            if not model["has_results_table"]:
                raise InputError("no `## Results` table")
        elif a.results and a.checks:
            model = load_jsonl(a.results, a.checks, a.owner_file)
        else:
            raise InputError("give a markdown file, or --results and --checks")
    except InputError as e:
        print("check-table: input not readable — %s (NOT read as ready)" % e)
        return 2
    if a.cmd == "render":
        print(render(model, a.title))
        return 0
    ready, lines = verdict(model)
    if a.cells:
        lines = lines[:-1] + cell_states(model, a.min_commits) + lines[-1:]
    print("\n".join(lines))
    return 0 if ready else 1


if __name__ == "__main__":
    sys.exit(main())
