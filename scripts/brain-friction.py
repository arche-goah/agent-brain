#!/usr/bin/env python3
"""Where do this brain's mechanisms work AGAINST each other?

The fast self-test (`scripts/brain-selftest.sh`) answers "does each mechanism still
run". This answers the harder one the operator asked for (2026-08-20): contradictions,
friction between mechanisms, and whether the whole still makes sense.

The trigger was a measured case: consolidating seven Stop hooks into one dispatcher
silently turned `hook-coverage.py` into a permanent false alarm, because it matches
helper filenames in settings.json and cannot know a dispatcher runs them. Both parts
worked perfectly on their own. Nothing was broken — they just stopped fitting.

WHAT THIS IS AND IS NOT: it detects friction CANDIDATES mechanically and prints them
with the reason they look suspicious. It does not judge — judging "is this sensible"
needs a reader, and it is cheap once the candidates are on the table. That split is the
point: the expensive multi-agent coherence-scan audits the RULES, this audits the
MACHINERY, and neither guesses what the other measures.

    python3 scripts/brain-friction.py [brain-root]

Exit 0 always: everything here is a candidate for a decision, never a verdict. A tool
that fails on a suspicion trains people to ignore it.
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1
                       else os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
os.chdir(ROOT)
findings = []


def note(kind, text, why):
    findings.append((kind, text, why))


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def walk_files(*dirs, exts=(".sh", ".py", ".cjs", ".js", ".md", ".json")):
    for base in dirs:
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames
                           if d not in (".git", "node_modules", "__pycache__")]
            for fn in filenames:
                if fn.endswith(exts):
                    yield os.path.join(dirpath, fn)


settings = read_json(".claude/settings.json")
hooks = settings.get("hooks", {})
stop_cfg = read_json(".claude/rules/stop-checks.json")
checks = stop_cfg.get("checks", [])
sources = {p: open(p, encoding="utf-8", errors="ignore").read()
           for p in walk_files(".claude", "core", "scripts", "docs", "config")
           if os.path.isfile(p)}

# --- 1. two mechanisms on the same event, one of them a dispatcher ------------
for event, groups in hooks.items():
    cmds = [h.get("command", "") for g in groups for h in g.get("hooks", [])]
    dispatchers = [c for c in cmds if "dispatcher" in c]
    if dispatchers and len(cmds) > 1:
        note("double-fire", f"{event}: dispatcher plus {len(cmds) - 1} more hook(s)",
             "a dispatcher runs its checks itself — anything also wired directly "
             "fires twice per turn")

# --- 2. a check that reads settings.json cannot see indirection ---------------
# This is the exact class that was measured: the subject moved behind a dispatcher and
# the check kept matching on the old shape.
if checks:
    registered = {os.path.basename(c.get("cmd", "")) for c in checks}
    for path, text in sources.items():
        if not path.endswith((".py", ".cjs", ".sh")) or "dispatcher" in path:
            continue
        # A file that DELEGATES to hook-coverage inherits its blindness, it does not
        # add a second one — reporting it separately turns one finding into four.
        if "hook-coverage" in text and "hook-coverage" not in path:
            continue
        if "settings.json" in text and re.search(r'hooks?\b', text):
            hits = [n for n in registered if n and n in text]
            if hits:
                note("blind-to-indirection",
                     f"{path} matches on {', '.join(sorted(hits)[:3])}",
                     "it reads settings.json, but these run via the dispatcher — "
                     "it will report them as missing unless it knows stop-checks.json")

# --- 3. a recorder nobody reads ----------------------------------------------
for c in checks:
    if c.get("mode") != "record":
        continue
    log = f"{c.get('marker', '').lower()}.jsonl"
    readers = [p for p, t in sources.items()
               if log in t and "stop-dispatcher" not in p and "stop-checks" not in p]
    if not readers:
        note("write-only", f"{c.get('label')} records to .claude-state/{log}",
             "nothing reads that log — a recording check without a report is a "
             "measurement series nobody looks at")

# --- 4. blocking check without a cooldown ------------------------------------
for c in checks:
    if c.get("mode") == "record":
        continue
    path = c.get("cmd", "")
    text = sources.get(path, "")
    if text and "COOLDOWN" not in text and "cooldown" not in text:
        note("no-cooldown", f"{c.get('label')} ({os.path.basename(path)})",
             "it blocks on every hit with no quiet period — an unconditional trigger "
             "becomes ritual and takes the working checks down with it")

# --- 5. allowlist drift ------------------------------------------------------
manual = read_json(".claude/rules/manual-tools.json").get("manual", [])
existing = {os.path.basename(p) for p in sources}
for name in manual:
    if name not in existing:
        note("stale-allowlist", name,
             "listed as a hand-run tool but the file does not exist any more")
    else:
        # A MENTION IS NOT A CALL — third instance of that class in one day, this time
        # produced by the tool that looks for it. An invocation has a runner in front
        # of it; a docstring naming a script does not.
        invoke = re.compile(
            r'(?:bash|sh|node|python3?|\$PY|\$PYTHON|\./|exec |subprocess[^\n]*?)'
            r'[^\n]{0,40}' + re.escape(name))
        callers = [p for p, t in sources.items()
                   if p.endswith((".sh", ".py", ".cjs")) and invoke.search(t)
                   and os.path.basename(p) != name]
        if callers:
            note("allowlist-contradiction", f"{name} is invoked by "
                 f"{os.path.basename(callers[0])}",
                 "it is declared hand-run, but a script actually starts it — one of "
                 "the two statements is wrong (being USED by another tool is fine; "
                 "being scheduled behind the operator's back is not)")

# --- 6. dangling references in the rule stack --------------------------------
claude_md = sources.get("CLAUDE.md", "")
for imp in re.findall(r'^@([\w./-]+)', claude_md, re.M):
    if not os.path.exists(imp):
        note("dangling-import", imp, "CLAUDE.md imports a rule file that is not there — "
             "the rule is silently absent from every session")

for path, text in sources.items():
    if not path.endswith(".json") or "settings" not in path and "checks" not in path:
        continue
    for ref in re.findall(r'"((?:core|scripts|helpers)/[\w./-]+\.(?:cjs|py|sh))"', text):
        if not os.path.exists(ref):
            note("dangling-config", f"{path} -> {ref}",
                 "the config points at a file that does not exist")

# --- accepted candidates: judged once, not asked again ------------------------
# A scanner that keeps reporting a decision that was already made becomes noise, and
# noise is how the working checks lose their audience. Accepted entries carry the
# REASON, so disagreeing later is possible against something concrete.
accepted = read_json(".claude/rules/friction-accepted.json").get("accepted", [])
suppressed = 0
kept = []
for kind, text, why in findings:
    if any(a.get("kind") == kind and a.get("match", "") in text for a in accepted):
        suppressed += 1
    else:
        kept.append((kind, text, why))
findings = kept

# --- report ------------------------------------------------------------------
print(f"brain friction scan — {ROOT}")
if suppressed:
    print(f"({suppressed} candidate(s) accepted earlier — "
          f".claude/rules/friction-accepted.json carries the reasons)")
print()
if not findings:
    print("no friction candidates found.")
    print("\nThat is not a clean bill of health: this checks the shapes it knows "
          "(double firing, blind checks, write-only recorders, missing cooldowns, "
          "allowlist contradictions, dangling references). Whether the whole still "
          "makes SENSE is a reading job, and the candidates above are what makes it "
          "cheap.")
    sys.exit(0)

by_kind = {}
for kind, text, why in findings:
    by_kind.setdefault(kind, []).append((text, why))
for kind, items in by_kind.items():
    print(f"{kind} ({len(items)}):")
    for text, why in items:
        print(f"  ?? {text}")
        print(f"     {why}")
    print()
print(f"{len(findings)} friction candidate(s) — decide each, none of them is a verdict.")
sys.exit(0)
