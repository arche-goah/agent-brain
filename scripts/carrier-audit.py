#!/usr/bin/env python3
"""carrier-audit.py — does each lesson in the feedback protocol BIND, or is it prose?

WHY (operator, 2026-10-26, after two corrections in one afternoon were "carried" by a sentence in the
feedback protocol): "a rule in the protocol is no binding mechanic, we have known that for months …
a rule entered in the feedback amounts to an empty promise in the long run". Measured the same day:
lesson-carriers.py accepted `Carrier: prose, because …` and exits 0; commitments.py counted a write
to a memory or feedback file as the carrier of a promise. Both measure that something was WRITTEN,
not that something BINDS.

THE INVARIANT: a lesson about what the AI does is carried by a mechanism that runs without being
remembered — a wired gate that refuses, a data row such a gate reads, or a CI step. Everything else
is prose, however carefully worded.

Classes per entry (strongest carrier named on its `Carrier:` lines wins):
  GATE     a named file is a hook command wired in the plugin's hooks/hooks.json or the brain's
           settings, or a .json data file whose name a wired helper reads, or a .github/workflows file;
           or a backticked id that is a rule id in a mechanism-rules.json. Untested gates are flagged.
  REPORT   a named script exists but only reports (not wired as a hook) — it informs, it does not bind.
  PENDING  only a PR reference (#123) — binds once merged and consumed; re-run then.
  PROSE    the carrier names only text: protocol, feedback.md, rules/*.md, memory, ledger, "prose".
  NONE     no carrier line at all.
An entry carrying `operator-ok: "<quote>"` on its carrier lines counts as an accepted prose decision.

Usage: carrier-audit.py [--repo DIR] [--protocol FILE] [--since YYYY-MM-DD] [--gate] [--json]
  report mode (default): every entry with its class, then a summary; exit 0.
  --gate: exit 1 when an entry dated on/after --since is not GATE/PENDING and has no operator-ok —
          the blocking form for a hook or CI.
Instance data: .claude/rules/lesson-carriers.json (protocol, carrier_keys, entry_heading) — shared with
lesson-carriers.py.
"""
import argparse
import glob
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

DEFAULTS = {
    "protocol": "docs/maintenance/feedback-protocol.md",
    "carrier_keys": ["Carrier"],
    "entry_heading": r"^## (\d{4}-\d{2}-\d{2})",
}
MECH_EXT = re.compile(r"[\w./-]+\.(?:cjs|mjs|js|py|sh|ps1|json|ya?ml)\b")
PR_REF = re.compile(r"(?:#|PR\s*#?)(\d{1,5})\b")
BACKTICK = re.compile(r"`([^`\s]{2,80})`")
OPERATOR_OK = re.compile(r"operator-ok\s*:\s*[\"“„].{6,}[\"”“]", re.I)
OTHER_KEY = re.compile(r"^\s*\**(Reach|Reichweite|Anlass|Occasion|Regel|Rule|Korrektur)\**\s*:", re.I)


def load_config(repo):
    cfg = dict(DEFAULTS)
    try:
        with open(os.path.join(repo, ".claude", "rules", "lesson-carriers.json"), encoding="utf-8") as f:
            d = json.load(f)
        for k in DEFAULTS:
            if d.get(k):
                cfg[k] = d[k]
    except (OSError, ValueError):
        pass
    return cfg


def entries(text, heading_rx):
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


def carrier_text(body, keys):
    """The text of every carrier line plus its continuation lines (until a blank or another key)."""
    rx = re.compile(r"^\s*\**(?:%s)\**\s*:" % "|".join(re.escape(k) for k in keys), re.I)
    out, on = [], False
    for ln in body:
        if rx.match(ln):
            on = True
            out.append(ln)
        elif on and ln.strip() and not OTHER_KEY.match(ln) and not ln.startswith("**"):
            out.append(ln)
        else:
            on = False
    return "\n".join(out) if out else None


def hook_commands(repo, core):
    """Every command string wired as a hook: plugin hooks.json + the brain's settings files."""
    cmds = []
    files = ([os.path.join(core, "hooks", "hooks.json")]
             + [os.path.join(repo, ".claude", n) for n in ("settings.json", "settings.local.json")]
             + [os.path.join(os.path.expanduser("~"), ".claude", "settings.json")])   # user scope wires gates too
    for fp in files:
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        for ev in (d.get("hooks") or {}).values():
            for m in ev:
                for h in m.get("hooks", []):
                    if h.get("command"):
                        cmds.append(h["command"])
    return cmds


def wired_basenames(cmds):
    names = set()
    for c in cmds:
        for tok in re.findall(r"[\w./${}-]+\.(?:cjs|mjs|js|py|sh|ps1)", c):
            names.add(os.path.basename(tok))
    return names


def helper_sources(repo, core, wired):
    """Source text of every wired helper — to see which data files they read."""
    src = []
    for root in (core, repo):
        for fp in walk_files(root):
            if os.path.basename(fp) in wired:
                try:
                    with open(fp, encoding="utf-8", errors="replace") as f:
                        src.append(f.read())
                except OSError:
                    pass
    return "\n".join(src)


def mechanism_rule_ids(repo, core):
    ids = set()
    for fp in (os.path.join(repo, ".claude", "rules", "mechanism-rules.json"), os.path.join(core, "mechanism-rules.json")):
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError):
            continue
        rules = d.get("rules", d) if isinstance(d, dict) else d
        for r in rules if isinstance(rules, list) else []:
            if isinstance(r, dict) and r.get("id"):
                ids.add(str(r["id"]))
    return ids


def walk_files(root):
    """Every file under root, hidden folders included (.claude/rules holds the gate data), no node_modules/.git."""
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in ("node_modules", ".git")]
        for fn in fns:
            yield os.path.join(dp, fn)


def find_file(token, roots):
    token = token.strip("`'\"(),; ").rstrip(".")   # a leading dot is part of .claude/…
    for root in roots:
        p = os.path.join(root, token)
        if os.path.isfile(p):
            return p
    base = os.path.basename(token)
    for root in roots:
        for fp in walk_files(root):
            if os.path.basename(fp) == base:
                return fp
    return None


def has_test(path, roots):
    stem = os.path.splitext(os.path.basename(path))[0]
    names = (f"test-{stem}.", f"{stem}-test.", f"{stem}.test.", f"test_{stem}.")
    for root in roots:
        for fp in walk_files(root):
            if os.path.basename(fp).startswith(names):
                return True
    return False


def classify(ctext, ctx):
    if ctext is None:
        return "NONE", []
    if OPERATOR_OK.search(ctext):
        return "OPERATOR-OK", []
    found, cls = [], None
    tokens = set(MECH_EXT.findall(ctext))
    for tok in tokens:
        fp = find_file(tok, ctx["roots"])
        if not fp:
            continue
        base = os.path.basename(fp)
        posix = fp.replace(os.sep, "/")   # OS-1: compare forward-slashed text, never the platform separator
        is_gate = (base in ctx["wired"] or "/.github/workflows/" in posix
                   or (fp.endswith(".json") and base in ctx["helper_src"]))
        if is_gate:
            cls = "GATE"
            found.append(base + ("" if fp.endswith(".json") or has_test(fp, ctx["roots"]) else " (untested)"))
        elif cls != "GATE" and not fp.endswith((".md",)):
            cls = cls or "REPORT"
            found.append(base + " (report only)")
    for tok in BACKTICK.findall(ctext):
        if tok in ctx["rule_ids"]:
            cls = "GATE"
            found.append(f"mechanism rule `{tok}`")
    if cls:
        return cls, found
    if PR_REF.search(ctext):
        return "PENDING", ["PR " + ", ".join("#" + n for n in PR_REF.findall(ctext))]
    return "PROSE", []


def main():
    ap = argparse.ArgumentParser(description="does each lesson bind, or is it prose?")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--core", help="core root (default <repo>/core, else the repo itself)")
    ap.add_argument("--protocol")
    ap.add_argument("--since")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--staged", action="store_true",
                    help="judge only entries the staged protocol adds over HEAD (pre-commit); implies --gate")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if a.staged:
        a.gate = True
    repo = os.path.abspath(a.repo)
    core = os.path.abspath(a.core or (os.path.join(repo, "core") if os.path.isdir(os.path.join(repo, "core", "helpers")) else repo))
    cfg = load_config(repo)
    proto = a.protocol or os.path.join(repo, cfg["protocol"])
    known = None
    if a.staged:
        import subprocess
        rel = os.path.relpath(proto, repo).replace(os.sep, "/")
        def show(ref):
            r = subprocess.run(["git", "-C", repo, "show", f"{ref}:{rel}"], capture_output=True, text=True, encoding="utf-8")
            return r.stdout if r.returncode == 0 else None
        staged_text = show("")          # ":path" = the index
        if staged_text is None:
            return 0                    # protocol not in this commit's tree: nothing to judge
        head_text = show("HEAD") or ""
        known = {(d, t) for d, t, _ in entries(head_text, cfg["entry_heading"])}
        text = staged_text
    try:
        if known is None:
            with open(proto, encoding="utf-8") as f:
                text = f.read()
    except OSError as e:
        print(f"carrier-audit: cannot read {proto}: {e}")
        print("carrier-audit summary: NOT checked (protocol unreadable)")
        return 1 if a.gate else 0
    wired = wired_basenames(hook_commands(repo, core))
    ctx = {"roots": [repo, core], "wired": wired, "helper_src": helper_sources(repo, core, wired),
           "rule_ids": mechanism_rule_ids(repo, core)}
    rows = []
    for date, title, body in entries(text, cfg["entry_heading"]):
        if a.since and date < a.since:
            continue
        if known is not None and (date, title) in known:
            continue                    # --staged: only what this commit adds
        ctext = carrier_text(body, cfg["carrier_keys"])
        if ctext is None:
            # Entries older than the carrier-line convention: judge the whole text, say so.
            cls, why = classify("\n".join(body), ctx)
            cls = "NONE" if cls == "PROSE" else cls
            why = why + ["no carrier line — judged from the text"]
        else:
            cls, why = classify(ctext, ctx)
        rows.append({"date": date, "title": title, "class": cls, "evidence": why})
    counts = {}
    for r in rows:
        counts[r["class"]] = counts.get(r["class"], 0) + 1
    bad = [r for r in rows if r["class"] not in ("GATE", "PENDING", "OPERATOR-OK")]
    if a.json:
        print(json.dumps({"entries": rows, "counts": counts}, ensure_ascii=False, indent=1))
    else:
        for r in rows:
            ev = f" — {'; '.join(r['evidence'])}" if r["evidence"] else ""
            print(f"{r['class']:<11} {r['date']} {r['title'][:90]}{ev}")
        print("carrier-audit summary: entries=%d %s not-binding=%d" % (
            len(rows), " ".join(f"{k.lower()}={v}" for k, v in sorted(counts.items())), len(bad)))
        if a.gate and bad:
            print("carrier-audit: a lesson about what the AI does must name a mechanism that BINDS — a wired gate, a data "
                  "row a wired gate reads, a mechanism-rules id or a CI step (build it in this commit). Prose only with the "
                  "operator's quoted word on the carrier line: operator-ok: \"<quote>\" (date).")
    return 1 if (a.gate and bad) else 0


if __name__ == "__main__":
    sys.exit(main())
