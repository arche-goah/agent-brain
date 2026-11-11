#!/usr/bin/env python3
"""Check catalog: every check the core ships, by level, with its trigger and where its result lands — generated.

WHY (audit-audit run on the Windows instance, 2026-11-10; released by the operator the same day): an inventory
found 173 checks (154 core, 19 instance) while the rules name six, and a fresh AI could not find, from its loaded
context, any level above the full audit. A hand-kept list drifts the day a hook is added; this one is read from the
places that wire the checks: hooks/hooks.json, the stop-check template, the session start script, the workflows,
the check skills and the self-tests. It is printed, never committed: a stored copy would need regenerating in every
PR that adds a hook, skill or test, and those PRs would collide in that one file at every merge train.
`rules/intelligence.md` points here instead of listing the checks.

  check-catalog.py [--root DIR]            print the catalog (Markdown)

What it checks comes from each file's own first header sentence; a file without one shows "(no header)" — that is
a finding about the file, not about the catalog.
"""
import argparse
import json
import os
import re
import sys

LEVELS = [
    ("tool", "Every tool call", "PreToolUse / PostToolUse hook", "blocks the call (exit 2, reason on stderr) or a note"),
    ("prompt", "Every prompt", "UserPromptSubmit hook", "context added to the prompt"),
    ("turn", "Every turn end", "Stop hook through stop-dispatcher.cjs (template rows)", "holds the turn end (block) or a log (record)"),
    ("start", "Session start", "SessionStart hook, sections of session-bootup.sh", "the session start report"),
    ("end", "Session end / compaction", "SessionEnd / PreCompact hook", "memory export, closing report"),
    ("demand", "On the operator's OK (deep checks)", "workflow or skill, proposed by the AI with its price, never started alone", "a report file named by the skill"),
    ("selftest", "Self-tests", "CI (all fixture suites, three OS) and scripts/brain-check.sh", "CI verdict, brain-check line in the session start"),
]
CHECK_SKILL_RX = re.compile(r"\b(audit|scan|review|verif\w*|lint|tidy|dream)\b", re.I)


def first_sentence(path):
    """The first sentence of a file's header: a JS block comment, a Python docstring or a shell comment block."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read(6000)
    except OSError:
        return "(missing file)"
    m = re.search(r"/\*\*(.*?)(?:\*/|\Z)", text, re.S)
    if path.endswith((".cjs", ".js")) and m:
        body = " ".join(l.strip().lstrip("*").strip() for l in m.group(1).splitlines())
    elif path.endswith(".py") and re.search(r'"""', text):
        body = text.split('"""', 2)[1]
    else:
        lines = []
        for l in text.splitlines()[1:]:
            if not l.startswith("#"):
                break
            lines.append(l.lstrip("#").strip())
        body = " ".join(lines)
    body = re.sub(r"\s+", " ", body).strip()
    body = re.sub(r"^(?:\S+\.(?:sh|py|cjs)\s*(?:\[[^\]]*\]\s*)?(?:<[^>]*>\s*)*[—-]\s*)", "", body)
    body = re.sub(r"^(?:(?:PreToolUse|PostToolUse|Stop|SessionStart|UserPromptSubmit)(?:\s*[Hh]ook)?(?:\s*\([^)]*\))?(?:\s*\+[^:]*)?:\s*)", "", body)
    if not body:
        return "(no header)"
    s = re.split(r"(?<=[.!?])\s", body, maxsplit=1)[0]
    return (s[:177] + "...") if len(s) > 180 else s


def rows_hooks(root):
    data = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))
    out = {"tool": [], "prompt": [], "start": [], "end": [], "turn": []}
    lvl = {"PreToolUse": "tool", "PostToolUse": "tool", "UserPromptSubmit": "prompt", "SessionStart": "start",
           "SessionEnd": "end", "PreCompact": "end", "Notification": "end", "Stop": "turn"}
    seen = set()
    for event, groups in data.get("hooks", {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                m = re.search(r"core/((?:helpers|scripts)/[\w.-]+)", h.get("command", ""))
                if not m:
                    continue
                key = (event, m.group(1))
                if key in seen:
                    continue
                seen.add(key)
                trig = event + (f" `{g['matcher']}`" if g.get("matcher") else "")
                out[lvl.get(event, "end")].append((m.group(1), trig, first_sentence(os.path.join(root, m.group(1)))))
    return out


def rows_stop(root):
    p = os.path.join(root, "templates", "rules-instance", "stop-checks.json")
    data = json.load(open(p, encoding="utf-8"))
    out = []
    for c in data.get("checks", []):
        cmd = str(c.get("cmd", "")).replace("core/", "", 1)
        mode = c.get("mode", "block") + (", required" if c.get("required") else "")
        out.append((f"{c.get('marker')} ({cmd})", mode, first_sentence(os.path.join(root, cmd))))
    return out


def rows_bootup(root):
    p = os.path.join(root, "helpers", "session-bootup.sh")
    text = open(p, encoding="utf-8").read()
    names = sorted(set(re.findall(r"(?:core/)?((?:scripts|helpers)/[a-z0-9_.-]+\.(?:py|sh|cjs))", text)) - {"helpers/session-bootup.sh"})
    return [(n, "section of session-bootup.sh", first_sentence(os.path.join(root, n))) for n in names]


def rows_demand(root):
    out = []
    wf = os.path.join(root, "workflows")
    for f in sorted(os.listdir(wf)) if os.path.isdir(wf) else []:
        if f.endswith(".js"):
            m = re.search(r"description:\s*'((?:[^'\\]|\\.)*)'", open(os.path.join(wf, f), encoding="utf-8").read())
            out.append((f"workflow {f[:-3]}", "Workflow tool", (m.group(1) if m else "(no description)")[:180]))
    sk = os.path.join(root, "skills")
    for d in sorted(os.listdir(sk)) if os.path.isdir(sk) else []:
        p = os.path.join(sk, d, "SKILL.md")
        if not os.path.isfile(p):
            continue
        m = re.search(r"^description:\s*(.+)$", open(p, encoding="utf-8").read(), re.M)
        desc = m.group(1).strip() if m else ""
        if CHECK_SKILL_RX.search(desc.split(".")[0]):
            s = re.split(r"(?<=[.!?])\s", desc, maxsplit=1)[0]
            out.append((f"skill {d}", "Skill tool", (s[:177] + "...") if len(s) > 180 else s))
    return out


def rows_selftests(root):
    sc = os.path.join(root, "scripts")
    names = sorted(f for f in os.listdir(sc) if re.match(r"^(test-.+\.(sh|cjs|py)|.+-test\.(py|sh|cjs))$", f))
    return names


def render(root):
    h = rows_hooks(root)
    rows = {"tool": h["tool"], "prompt": h["prompt"], "turn": h["turn"] + rows_stop(root),
            "start": h["start"] + rows_bootup(root), "end": h["end"], "demand": rows_demand(root)}
    tests = rows_selftests(root)
    total = sum(len(v) for v in rows.values()) + len(tests)
    out = ["# Check catalog", "",
           "Generated now by `scripts/check-catalog.py` from the files that wire the checks.", "",
           f"Every check the core ships, by the moment it runs: {total} in all. A brain adds its own in its instance "
           "files (`.claude/settings.json`, `.claude/rules/stop-checks.json`); those are not listed here.", ""]
    for key, title, trigger, result in LEVELS:
        if key == "selftest":
            out += [f"## {title} ({len(tests)})", "", f"Trigger: {trigger}. Result: {result}.", "",
                    ", ".join(f"`{t}`" for t in tests), ""]
            continue
        items = rows.get(key, [])
        out += [f"## {title} ({len(items)})", "", f"Trigger: {trigger}. Result: {result}.", "",
                "| Check | Trigger | What it checks |", "|---|---|---|"]
        for name, trig, what in items:
            out.append(f"| `{name}` | {trig} | {what.replace('|', '/')} |")
        out.append("")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sys.stdout.reconfigure(encoding="utf-8")  # OS-9: headers carry dashes; cp1252 on Windows would fail on them
    sys.stdout.write(render(ap.parse_args(argv).root) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
