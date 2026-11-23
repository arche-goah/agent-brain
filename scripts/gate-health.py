#!/usr/bin/env python3
"""gate-health: two health readings of the brain's gates over its recent session transcripts.

1. MALFUNCTIONS - a hook refusal that is no decision (it timed out or crashed). A gate that malfunctions in two or more
   sessions is named. Measured 2026-11-23 on the macOS instance (60 newest transcripts): content-review-gate timed out 37
   times in 15 sessions; no reply named a cause, and nothing outside the turn noticed - each session saw one retry that
   passed. The operator (translated): "detecting faults on your own ... is the goal". The form of a malfunction lives in
   ONE file, gate-malfunction.json at the core root (also read by helpers/root-cause-gate.cjs).
2. ERRS OFTEN - a gate whose decision refusals are mostly passed by its own OVERRIDE marker (operator 2026-11-23, rule
   "a gate that errs is a finding"; measured that day over 605 transcripts: CONDITIONAL-ORDER-GATE 224 of 375 refusals
   passed by `# CONDITION-NONE`). Which marker belongs to which gate, and whether passing by it is the gate's own rule
   path (a step done: never "errs") or an override, is data: gate-markers.json at the core root. A pass counts when the
   next call of the same tool with the same intent (the same path; Bash: half the command's words shared) carries the
   gate's marker, in the call or as a line in the answer before it. Also counted: calls carrying a marker at all (a
   marker written before any refusal shows a gate expected to misfire).

The session start runs it; per transcript the counts are cached (.claude-state/gate-health-cache.json, keyed by path,
size and mtime, voided when either data file changes), so only new or growing transcripts are read.

Usage: gate-health.py [--root <brain>] [--days 14] [--min-sessions 2] [--min-refusals 20] [--dir <transcript folder>]
                      [--markers <gate-markers.json>] [--all] [--rates] [--no-cache]
  prints one line per finding, nothing when all is quiet; --all lists every malfunctioning gate; --rates prints the table
  gate | refusals | by own marker | rate | rule path | calls carrying its marker. Exit 0 always (a report, not a gate).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LABEL = re.compile(r'^(?:PreToolUse|PostToolUse):\S+ hook error:\s*(?:\[node "[^"]*?([\w.-]+)\.cjs"\]:\s*)?'
                   r'(?:BLOCKED \(([\w-]+)\)|([A-Z][A-Z0-9 _-]{2,40}?)\s*(?::| \())?')
MARKER_USE = re.compile(r"#\s*([A-Z][A-Z]+(?:-[A-Z]+)+)\b")
WINDOW = 8
CACHE_V = "3"


def data():
    d = json.loads((HERE.parent / "gate-malfunction.json").read_text(encoding="utf-8"))
    return re.compile(d["refusal"]), re.compile("|".join(d["malfunction"])), re.compile(d["gate"])


def transcript_dir(root: str) -> Path:
    cfg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
    return cfg / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(root).resolve()))


def label_of(t: str, gate=None) -> str:
    """The refusal's label; without one, the hook's file name or number the malfunction form names (Windows review of
    #646: 6 refusals landed as 'a hook')."""
    m = LABEL.search(t)
    lab = (next((g for g in m.groups() if g), "") if m else "").strip()
    if not lab and gate is not None:
        g = gate.search(t)
        lab = (g.group(1) or f"command hook {g.group(2)}") if g else ""
    return lab or "a hook"


def intent(inp: str):
    """A call's intent: its file path, else the words of its command without comments (the form of root-cause-gate's
    anomaly check: the same path, or at least half the command's words shared)."""
    try:
        d = json.loads(inp)
    except ValueError:
        return ("raw", inp)
    if isinstance(d.get("file_path"), str):
        return ("file", d["file_path"])
    if isinstance(d.get("command"), str):
        cmd = re.sub(r"#.*$", "", d["command"], flags=re.M)
        return ("words", frozenset(re.findall(r"[\w./-]{3,}", cmd)) or frozenset([cmd.strip()]))
    return ("raw", inp[:200])


def same_intent(a, b) -> bool:
    if a[0] != b[0]:
        return False
    if a[0] == "words":
        u = a[1] | b[1]
        return bool(u) and len(a[1] & b[1]) / len(u) >= 0.5
    return a[1] == b[1]


def read_calls(f: Path):
    """The transcript as an ordered list of (id, tool, input json) - assistant text kept as (None, "_text", text) -
    and the results by call id: (is_error, text)."""
    calls, res, allres = [], {}, []
    with f.open(encoding="utf-8", errors="replace") as lines:
        for line in lines:
            if '"tool_use"' not in line and '"tool_result"' not in line and '"text"' not in line:
                continue
            try:
                msg = json.loads(line).get("message") or {}
            except ValueError:
                continue
            content = msg.get("content") if isinstance(msg, dict) else None
            for b in content if isinstance(content, list) else []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    calls.append((b.get("id"), b.get("name"), json.dumps(b.get("input") or {})))
                elif b.get("type") == "text" and b.get("text") and calls and msg.get("role") == "assistant":
                    calls.append((None, "_text", b["text"]))
                elif b.get("type") == "tool_result":
                    c = b.get("content")
                    txt = c if isinstance(c, str) else " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict))
                    res[b.get("tool_use_id")] = (bool(b.get("is_error")), txt.strip())
                    allres.append(res[b.get("tool_use_id")])
    return calls, res, allres


def scan_file(f: Path, rx, gmap):
    """One transcript: {"malf": {gate: [n, what]}, "rates": {gate: [refusals, passed by own marker]}, "carry": {marker: n}}."""
    refusal, malf, gate = rx
    calls, res, allres = read_calls(f)
    out = {"malf": {}, "rates": {}, "carry": {}}
    for _cid, name, inp in calls:
        if name != "_text":
            for mk in set(MARKER_USE.findall(inp)):
                out["carry"][mk] = out["carry"].get(mk, 0) + 1
    for err, t in allres:               # every error result, with or without its call in the transcript
        if err and refusal.search(t) and malf.search(t):
            g = gate.search(t)
            nm = (g.group(1) or f"command hook {g.group(2)}") if g else "a hook"
            e = out["malf"].setdefault(nm, [0, malf.search(t).group(0).split(";")[0]])
            e[0] += 1
    for i, (cid, name, inp) in enumerate(calls):
        if name == "_text":
            continue
        err, t = res.get(cid, (False, ""))
        if not err or not refusal.search(t) or malf.search(t):
            continue
        lab = label_of(t, gate)
        # [refusals, passed by its own marker, passed in another form, never passed within the window] - the last two
        # rate a gate without a marker too (strand review 2026-11-23: AUTONOMOUS-GATE, the incident's gate, has none)
        r = out["rates"].setdefault(lab, [0, 0, 0, 0])
        r[0] += 1
        own = (gmap.get(lab) or {}).get("markers") or []
        said, key, passed = "", intent(inp), False
        for cid2, name2, inp2 in calls[i + 1:i + 1 + WINDOW]:
            if name2 == "_text":
                said += "\n" + inp2
                continue
            # the pass of the SAME intent decides (measured: the next same-tool call was often another command)
            if name2 != name or res.get(cid2, (True, ""))[0] or not same_intent(key, intent(inp2)):
                continue
            passed = True
            if any(re.search(r"#\s*" + re.escape(n) + r"\b", inp2)
                   or re.search(r"(?m)^[ \t>*_`-]*" + re.escape(n) + r":", said) for n in own):
                r[1] += 1
            elif inp2 != inp:          # an identical retry is the gate's way on (a step done), not another form
                r[2] += 1
            break
        if not passed:
            r[3] += 1
    return out


def opt(argv, k, d):
    return argv[argv.index(k) + 1] if k in argv and argv.index(k) + 1 < len(argv) else d


def main(argv):
    root = opt(argv, "--root", os.environ.get("CLAUDE_PROJECT_DIR", "."))
    days = float(opt(argv, "--days", "14"))
    least = int(opt(argv, "--min-sessions", "2"))
    least_n = int(opt(argv, "--min-refusals", "20"))
    folder = Path(opt(argv, "--dir", "")) if "--dir" in argv else transcript_dir(root)
    mpath = Path(opt(argv, "--markers", str(HERE.parent / "gate-markers.json")))
    try:
        rx = data()
    except (OSError, ValueError, KeyError) as e:
        print(f"gate-health: gate-malfunction.json unreadable ({e}) - NOT checked")
        return 0
    try:
        mraw = mpath.read_text(encoding="utf-8")
        gmap = json.loads(mraw).get("gates") or {}
    except (OSError, ValueError) as e:
        print(f"gate-health: {mpath.name} unreadable ({e}) - marker rates NOT checked")
        mraw, gmap = "", {}
    version = CACHE_V + hashlib.sha1((HERE.parent / "gate-malfunction.json").read_bytes() + mraw.encode()).hexdigest()[:12]
    cpath = Path(root) / ".claude-state" / "gate-health-cache.json"
    cache = {}
    if "--no-cache" not in argv:
        try:
            cache = json.loads(cpath.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            cache = {}
    since = time.time() - days * 86400
    malf, rates, carry, fresh = {}, {}, {}, {}
    for f in sorted(folder.glob("*.jsonl")):
        try:
            st = f.stat()
        except OSError:
            continue
        if st.st_mtime < since:
            continue
        k = str(f)
        c = cache.get(k)
        if c and c.get("v") == version and c.get("size") == st.st_size and c.get("mtime") == st.st_mtime:
            got = c["data"]
        else:
            try:
                got = scan_file(f, rx, gmap)
            except OSError:
                continue
        fresh[k] = {"v": version, "size": st.st_size, "mtime": st.st_mtime, "data": got}
        for nm, (n, what) in got["malf"].items():
            e = malf.setdefault(nm, {"n": 0, "sessions": set(), "what": what})
            e["n"] += n
            e["sessions"].add(f.stem)
        for lab, vals in got["rates"].items():
            r = rates.setdefault(lab, [0, 0, 0, 0])
            for idx, v in enumerate(vals):
                r[idx] += v
        for mk, n in got["carry"].items():
            carry[mk] = carry.get(mk, 0) + n
    if "--no-cache" not in argv:
        try:
            cpath.parent.mkdir(parents=True, exist_ok=True)
            with cpath.open("w", encoding="utf-8", newline="\n") as fh:
                fh.write(json.dumps(fresh))
        except OSError:
            pass   # the cache is a speed-up, never a reason to fail
    for nm, e in sorted(malf.items(), key=lambda kv: -kv[1]["n"]):
        if "--all" in argv or len(e["sessions"]) >= least:
            print(f"gate-health: {nm} {e['what']} {e['n']}x in {len(e['sessions'])} session(s) (last {days:g} days) - "
                  "a malfunction is no decision: measure why (its run time, what it read), fix it at the gate")
    if "--rates" in argv:
        print("gate | refusals | by own marker | rate | rule path | calls carrying its marker | other form | never passed")
        for lab, (n, m, o, nv) in sorted(rates.items(), key=lambda kv: -kv[1][0]):
            g = gmap.get(lab) or {}
            rp = "-" if "rule_path" not in g else ("yes" if g["rule_path"] else "no")
            # a marker two gates share counts its calls for both - said, so the column is not read as this gate's alone
            shared = lambda mk: [o for o, og in gmap.items() if o != lab and mk in (og.get("markers") or [])]
            ca = " + ".join(f"{mk} {carry.get(mk, 0)}" + (f" (shared with {', '.join(shared(mk))})" if shared(mk) else "")
                            for mk in g.get("markers") or []) or "-"
            print(f"{lab} | {n} | {m} | {round(100 * m / n)} % | {rp} | {ca} | {o} | {nv}")
        return 0
    for lab, (n, m, o, _nv) in sorted(rates.items(), key=lambda kv: -kv[1][0]):
        g = gmap.get(lab) or {}
        if g.get("rule_path") is False and n >= least_n and m * 2 > n:
            print(f"gate-health: {lab} errs often - {m} of {n} refusals ({round(100 * m / n)} %) passed by its override "
                  f"marker (last {days:g} days) - a gate that errs is a finding: find what it misreads, fix the trigger")
        elif n >= least_n and o * 2 > n:
            print(f"gate-health: {lab} is bypassed often - {o} of {n} refusals ({round(100 * o / n)} %) passed in another "
                  f"form (last {days:g} days) - a gate that errs, or a way around it: either is a finding")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
