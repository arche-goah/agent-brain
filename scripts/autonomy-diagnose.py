#!/usr/bin/env python3
"""autonomy-diagnose.py — why does this brain's AI ask before every step? A read-only report.

WHY (2026-10-16, observed on a collaborator's Windows brain on core v1.3.41): the AI asked a
question for every one of about fifteen points, said it "cannot comment or push on its own,
that must always be user input", re-asked things it had tested in an earlier session, and put
questions to its human that it had been told to settle with another AI. Two candidate causes
cannot be told apart from the outside: the brain runs a core release that does not carry the
rules that reduce questions yet, or a LOCAL rule (instance rules, feedback, memory, an instance
skill) says "always ask" more widely than it was meant. A third looks the same from the
outside: a missing permission pattern makes the harness ask, and the AI reports that prompt as
"I am not allowed".

This script separates them without a model and without writing anything. It reads the brain
and the user's Claude config and prints a Markdown report to paste into a PR or the shared
memory. It does not depend on the core version: run it from any checkout of the core repo
against any brain.

Sections:
  1 core state      submodule commit/tag, edits inside core/, enabled core plugin, its pin, and
                    which question-reducing rules the loaded core rules carry
  2 loaded context  bytes of everything loaded at every start, against the harness limit (above
                    it the loader cuts silently — rules then go missing without a word), and the
                    memory index against its own limit
  3 brake phrases   sentences in LOCAL carriers that tell the AI to ask, wait or never act alone,
                    with file:line and what they are about (push, comment, merge, ... or nothing
                    named, which reads as "everything")
  4 permissions     how the settings answer the commands an autonomous AI needs (push, PR
                    comment/review/create/merge, the core's own helpers): allow, ask, deny, or
                    none (= the harness asks)
  5 hooks           every hook wired in the settings layers and enabled plugins, plus the core
                    stop-checks list
  6 recall          where a topic the AI should already know lives (memory, rules), and whether
                    any hook hands memory to the AI before it acts

Usage: autonomy-diagnose.py [--repo DIR] [--home DIR] [--topic REGEX] [--out FILE]
  --repo   the brain (default: current directory)
  --home   the user's home (default: ~); the Claude config is <home>/.claude unless
           CLAUDE_CONFIG_DIR is set
  --topic  regex for section 6 (default: the desk example of 2026-10-16, Message Center)
The report quotes rule lines of the brain. Anything that looks like a token, key or password is
replaced by [REDACTED]; the report is still meant for a private channel.

Runs WITHOUT Claude, in a plain terminal, in seconds, on any core version — download and run:
  curl -fsSL https://raw.githubusercontent.com/arche-goah/agent-brain/main/scripts/autonomy-diagnose.py -o autonomy-diagnose.py
  python3 autonomy-diagnose.py --repo <path to the brain> --out autonomy-report.md
(Windows PowerShell: `python` instead of `python3`; the same two lines work in Git Bash.)
Exit 0 always (a report, not a gate).
"""
import argparse
import fnmatch
import glob
import json
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):
    pass

LIMIT = 150000          # always-loaded bytes the harness loads (always-loaded.py, measured 2026-10-11)
MEMORY_LINES = 200      # MEMORY.md index: lines and bytes Claude Code loads
MEMORY_BYTES = 25600

# Rules that reduce questions, as they are worded in the core (2026-10-16: 0 hits in v1.3.41,
# 10 in v1.4.4). A missing marker means the loaded core does not carry that rule.
CORE_MARKERS = [
    ("ASK OR ACT", "one ordered procedure: when a question may end the turn"),
    ("comparative test", "only what the operator decides better goes to the operator"),
    ("Presenting to the Operator", "what reaches the operator, sorted first"),
    ("closes its own question", "the AI closes a question its own work answered"),
]

BRAKES = [
    r"immer (?:den |dem |der )?(?:Nutzer|User|Benutzer|Operator|Menschen)",
    r"\bnie (?:selbst|alleine?|eigenm(?:ae|ä)chtig|selbstst(?:ae|ä)ndig|ohne (?:Frage|Nachfrage|Freigabe|OK))",
    r"nicht selbst(?:st(?:ae|ä)ndig)?\b",
    r"(?:vorher|zuerst|immer) (?:fragen|nachfragen|r(?:ue|ü)ckfragen)",
    r"\berst (?:nach (?:dem |einem )?)?(?:OK|Okay|Freigabe|Zustimmung|Best(?:ae|ä)tigung)",
    r"explizit(?:e|es|en|em|er)? (?:OK|Freigabe|Zustimmung|Erlaubnis)",
    r"(?:Nutzer|User|Benutzer)-?Eingabe",
    r"Text (?:vorher )?(?:zur Verf(?:ue|ü)gung stellen|vorlegen|zeigen)",
    r"\balways ask\b",
    r"\bask (?:the (?:user|operator|human) )?(?:first|before)\b",
    r"\bnever (?:on (?:its|your) own|without (?:asking|approval|permission|confirmation))",
    r"\bexplicit (?:approval|permission|OK|consent|confirmation)\b",
    r"\bwait for (?:the )?(?:user|operator|human)(?:'s)? (?:OK|approval|confirmation|go)",
    r"\brequires? (?:user|operator|human) (?:approval|confirmation|input)",
    r"\buser input\b",
]
BRAKE = re.compile("|".join(BRAKES), re.I)
SCOPES = [
    ("push", r"\bpush"), ("comment", r"comment|kommentar"), ("merge", r"\bmerge"),
    ("release/tag/pin", r"\brelease|\btag\b|\bpin\b"), ("publish", r"publi|ver(?:oe|ö)ffentlich|\bposten\b|\bpost\b"),
    ("delete", r"\bdelet|l(?:oe|ö)sch"), ("hardware/live", r"hardware|\bpult\b|\bdesk\b|\blive\b|\brig\b"),
    ("money", r"\bgeld\b|money|\bkauf|\bbuy"),
    ("permissions", r"\brecht|permission|settings"),
]

PROBES = [
    ("push (plain)", 'git push'),
    ("push (git -C)", 'git -C "<brain>" push'),
    ("PR comment", 'gh pr comment 1 -R owner/repo --body-file note.md'),
    ("PR review", 'gh pr review 1 -R owner/repo --comment --body-file note.md'),
    ("PR create", 'gh pr create -R owner/repo --title t --body-file note.md'),
    ("PR merge", 'gh pr merge 1 -R owner/repo --merge'),
    ("core helper (close own question)", 'node core/helpers/question-gate.cjs resolve x=answered'),
    ("core script", 'python3 core/scripts/open-items.py'),
]


SECRET = re.compile(
    r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}"
    r"|xox[abpr]-[A-Za-z0-9-]{10,}|(?i:(?:password|passwort|token|secret|api[_-]?key)\s*[:=]\s*)\S+"
    r"|(?=[A-Za-z0-9+]*[0-9])(?=[A-Za-z0-9+]*[a-z])(?=[A-Za-z0-9+]*[A-Z])[A-Za-z0-9+]{40,}={0,2})")


def redact(text):
    """The report leaves the machine: anything that looks like a credential is blacked out."""
    return SECRET.sub("[REDACTED]", text)


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def read_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return []


def size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def rel(path, repo, home):
    p = os.path.normpath(path)
    for base, label in ((os.path.normpath(repo), ""), (os.path.normpath(home), "~")):
        if p.lower().startswith(base.lower() + os.sep):
            tail = p[len(base) + 1:].replace(os.sep, "/")
            return f"{label}/{tail}" if label else tail
    return p.replace(os.sep, "/")


def memory_dir(repo, cfg):
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(repo))
    return os.path.join(cfg, "projects", slug, "memory")


def settings_layers(repo, cfg):
    return [(os.path.join(cfg, "settings.json"), "user"),
            (os.path.join(repo, ".claude", "settings.json"), "project"),
            (os.path.join(repo, ".claude", "settings.local.json"), "local")]


def enabled_plugins(layers):
    out = {}
    for path, _ in layers:
        for k, v in ((load(path, {}) or {}).get("enabledPlugins") or {}).items():
            out[k] = bool(v)  # later layers win
    return [k for k, v in out.items() if v]


# ---------- 1 core state
def core_state(repo, cfg, layers):
    out = ["## 1 Core state", ""]
    core = os.path.join(repo, "core")
    if not os.path.isdir(core):
        out += ["- no `core/` directory in the brain — core rules can only come from a plugin", ""]
    else:
        _, desc = run(["git", "-C", core, "describe", "--tags", "--always"])
        _, commit = run(["git", "-C", core, "rev-parse", "--short=12", "HEAD"])
        _, dirty = run(["git", "-C", core, "status", "--porcelain"])
        _, url = run(["git", "-C", core, "remote", "get-url", "origin"])
        out.append(f"- submodule `core/`: {desc or '?'} ({commit or '?'}), origin {url or '?'}")
        n = len([x for x in dirty.splitlines() if x.strip()])
        out.append(f"- edits inside `core/`: {n}" + (" — local changes to the core, the brain does not run the released state" if n else ""))
    installed = (load(os.path.join(cfg, "plugins", "installed_plugins.json"), {}) or {}).get("plugins") or {}
    found = False
    for pid in enabled_plugins(layers):
        name, _, mkt = pid.partition("@")
        if "core" not in name:
            continue
        found = True
        rec = installed.get(pid) or []
        ver = rec[0].get("version", "?") if rec else "not installed"
        pin = "?"
        mp = load(os.path.join(cfg, "plugins", "marketplaces", mkt, ".claude-plugin", "marketplace.json"), {}) or {}
        for e in mp.get("plugins") or []:
            if e.get("name") == name and isinstance(e.get("source"), dict):
                pin = e["source"].get("ref", "?")
        out.append(f"- enabled core plugin `{pid}`: installed {ver}, marketplace pin {pin}")
    if not found:
        out.append("- no enabled plugin with 'core' in its name")
    rules = sorted(glob.glob(os.path.join(core, "rules", "*.md")))
    text = "\n".join("\n".join(read_lines(r)) for r in rules)
    out += ["", "Question-reducing rules in the loaded core rules (`core/rules/*.md`):", ""]
    if not rules:
        out.append("- no `core/rules/*.md` found — nothing to check")
    for marker, meaning in CORE_MARKERS:
        out.append(f"- {'present' if marker in text else 'MISSING'}: \"{marker}\" — {meaning}")
    out.append("")
    return out


# ---------- 2 loaded context
def loaded_context(repo, home, cfg):
    out = ["## 2 Context loaded at every start", ""]
    files = [os.path.join(cfg, "CLAUDE.md"), os.path.join(repo, "CLAUDE.md"), os.path.join(repo, "CLAUDE.local.md")]
    files += sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md")))
    files += sorted(glob.glob(os.path.join(repo, "core", "rules", "*.md")))
    mem = os.path.join(memory_dir(repo, cfg), "MEMORY.md")
    files.append(mem)
    total = 0
    rows = []
    for f in files:
        b = size(f)
        if b:
            total += b
            rows.append((b, rel(f, repo, home)))
    pct = total * 100 // LIMIT
    verdict = "OVER — the loader cuts the rest without a word" if total >= LIMIT else ("close to the limit" if pct >= 90 else "within the limit")
    out.append(f"- total {total} bytes of about {LIMIT} the harness loads ({pct} %): {verdict}")
    for b, name in sorted(rows, reverse=True)[:8]:
        out.append(f"  - {b:>7}  {name}")
    lines = read_lines(mem)
    if lines:
        mb = size(mem)
        over = len(lines) > MEMORY_LINES or mb > MEMORY_BYTES
        out.append(f"- memory index: {len(lines)} lines, {mb} bytes (loaded: {MEMORY_LINES} lines / {MEMORY_BYTES} bytes)"
                   + (" — OVER, entries past the cut are never seen" if over else ""))
    else:
        out.append(f"- memory index: none at `{rel(mem, repo, home)}`")
    out.append("")
    return out


# ---------- 3 brake phrases
def local_carriers(repo, cfg):
    files = [os.path.join(cfg, "CLAUDE.md"), os.path.join(repo, "CLAUDE.md"), os.path.join(repo, "CLAUDE.local.md")]
    files += sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md")))
    files += sorted(glob.glob(os.path.join(repo, ".claude", "skills", "*", "SKILL.md")))
    files += sorted(glob.glob(os.path.join(memory_dir(repo, cfg), "*.md")))
    files += sorted(glob.glob(os.path.join(cfg, "output-styles", "*.md")))
    return [f for f in files if os.path.isfile(f)]


def scope_of(line):
    hits = [name for name, rx in SCOPES if re.search(rx, line, re.I)]
    return ", ".join(hits) if hits else "nothing named — reads as EVERYTHING"


def brakes(repo, home, cfg):
    out = ["## 3 Brake phrases in local carriers", "",
           "Local = the brain's CLAUDE.md, instance rules, instance skills, memory, user CLAUDE.md and output styles; "
           "the core's own text is not listed. A line is a candidate, not a verdict: read it and decide what it was meant for.", ""]
    found = 0
    per_file = {}
    for f in local_carriers(repo, cfg):
        for i, line in enumerate(read_lines(f), 1):
            m = BRAKE.search(line)
            if not m:
                continue
            found += 1
            name = rel(f, repo, home)
            per_file[name] = per_file.get(name, 0) + 1
            snippet = line.strip()
            if len(snippet) > 160:
                start = max(0, m.start() - 60)
                snippet = ("…" if start else "") + snippet[start:start + 160] + "…"
            out.append(f"- `{name}:{i}` [{scope_of(line)}] {snippet}")
    if not found:
        out.append("- none found")
    else:
        out.insert(4, f"{found} candidate line(s) in {len(per_file)} file(s); most: "
                   + ", ".join(f"{k} ({v})" for k, v in sorted(per_file.items(), key=lambda kv: -kv[1])[:3]) + "\n")
    out.append("")
    return out


# ---------- 4 permissions
def rule_matches(rule, cmd):
    m = re.fullmatch(r"Bash(?:\((.*)\))?", rule.strip(), re.S)
    if not m:
        return False
    body = m.group(1)
    if body is None or body in ("", "*"):
        return True
    if body.endswith(":*"):
        return cmd.startswith(body[:-2])
    pat = body.replace("[", "[[]")
    return fnmatch.fnmatchcase(cmd, pat)


def permissions(repo, cfg, layers):
    out = ["## 4 Permissions for the commands an autonomous AI needs", ""]
    rules = {"allow": [], "ask": [], "deny": []}
    mode = []
    for path, label in layers:
        perms = (load(path, {}) or {}).get("permissions") or {}
        for k in rules:
            rules[k] += [(r, label) for r in perms.get(k) or [] if isinstance(r, str)]
        if perms.get("defaultMode"):
            mode.append(f"{perms['defaultMode']} ({label})")
    out.append(f"- defaultMode: {', '.join(mode) if mode else 'not set (default: ask for anything not allowed)'}")
    out.append(f"- rules: {len(rules['allow'])} allow, {len(rules['ask'])} ask, {len(rules['deny'])} deny")
    out.append("")
    for label, cmd in PROBES:
        cmd = cmd.replace("<brain>", os.path.abspath(repo).replace(os.sep, "/"))
        verdict = ("no rule — the harness asks the human (in auto mode its classifier decides); "
                   "the AI may report that prompt as 'not allowed'")
        for kind in ("deny", "ask", "allow"):
            hit = next(((r, lab) for r, lab in rules[kind] if rule_matches(r, cmd)), None)
            if hit:
                verdict = f"{kind.upper()} by `{hit[0]}` ({hit[1]})"
                break
        out.append(f"- {label}: `{cmd}` → {verdict}")
    out.append("")
    return out


# ---------- 5 hooks
def hooks(repo, cfg, layers):
    out = ["## 5 Hooks", ""]
    n = 0
    sources = [(p, lab) for p, lab in layers]
    installed = (load(os.path.join(cfg, "plugins", "installed_plugins.json"), {}) or {}).get("plugins") or {}
    for pid in enabled_plugins(layers):
        for rec in installed.get(pid) or []:
            ip = rec.get("installPath") or ""
            for hp in (os.path.join(ip, "hooks", "hooks.json"), os.path.join(ip, ".claude-plugin", "plugin.json")):
                if os.path.isfile(hp):
                    sources.append((hp, f"plugin {pid}"))
    for path, label in sources:
        for event, groups in ((load(path, {}) or {}).get("hooks") or {}).items():
            for g in groups if isinstance(groups, list) else []:
                for h in g.get("hooks") or []:
                    cmd = str(h.get("command", ""))
                    where = "core" if re.search(r"core[/\\]helpers|CLAUDE_PLUGIN_ROOT", cmd) else "instance"
                    n += 1
                    out.append(f"- {event} [{g.get('matcher', '') or '*'}] ({label}, {where}): `{cmd[:140]}`")
    if not n:
        out.append("- none wired")
    sc = load(os.path.join(repo, ".claude", "rules", "stop-checks.json"), {}) or {}
    checks = sc.get("checks") if isinstance(sc, dict) else None
    if isinstance(checks, list) and checks:
        names = [str(c.get("marker") or c.get("cmd") or "?") for c in checks if isinstance(c, dict)]
        out.append(f"- stop-checks.json runs {len(names)} check(s): {', '.join(names)}")
    out.append("")
    return out


# ---------- 6 recall
def recall(repo, home, cfg, layers, topic):
    out = [f"## 6 Recall — where `{topic}` lives, and what hands it to the AI", ""]
    rx = re.compile(topic, re.I)
    files = sorted(glob.glob(os.path.join(memory_dir(repo, cfg), "*.md")))
    files += sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md")))
    files += sorted(glob.glob(os.path.join(repo, ".claude", "skills", "*", "SKILL.md")))
    hits = []
    for f in files:
        n = sum(1 for line in read_lines(f) if rx.search(line))
        if n:
            hits.append(f"{rel(f, repo, home)} ({n})")
    out.append(f"- found in: {', '.join(hits) if hits else 'nowhere local — the AI cannot know it was tested'}")
    rec = []
    for path, label in layers:
        for event, groups in ((load(path, {}) or {}).get("hooks") or {}).items():
            for g in groups if isinstance(groups, list) else []:
                for h in g.get("hooks") or []:
                    cmd = str(h.get("command", ""))
                    if event in ("UserPromptSubmit", "PreToolUse") and re.search(r"recall|memory", cmd, re.I):
                        rec.append(f"{event} `{cmd[:100]}` ({label})")
    out.append("- hooks that hand memory to the AI before it acts: "
               + ("; ".join(rec) if rec else "none — memory reaches the AI only through the index loaded at start"))
    out.append("")
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--home", default=os.path.expanduser("~"))
    ap.add_argument("--topic", default=r"message.?center")
    ap.add_argument("--out", default="")
    a = ap.parse_args(argv)
    repo = os.path.abspath(a.repo)
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(a.home, ".claude")
    layers = settings_layers(repo, cfg)
    report = ["# Autonomy diagnose", "",
              f"Brain `{os.path.basename(repo)}`, read-only, no model. Sections: core state, loaded context, "
              "brake phrases, permissions, hooks, recall.", ""]
    report += core_state(repo, cfg, layers)
    report += loaded_context(repo, a.home, cfg)
    report += brakes(repo, a.home, cfg)
    report += permissions(repo, cfg, layers)
    report += hooks(repo, cfg, layers)
    report += recall(repo, a.home, cfg, layers, a.topic)
    text = redact("\n".join(report).rstrip() + "\n")
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"autonomy-diagnose: report written to {a.out}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
