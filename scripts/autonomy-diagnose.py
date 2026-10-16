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

Usage: autonomy-diagnose.py [--repo DIR] [--home DIR] [--topic REGEX] [--out FILE] [--memory-dir]
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
import traceback

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


# What the brain itself got wrong while being read: a messy brain must not stop the report, and
# its mess must not vanish either — every unreadable or invalid file becomes a line in section 0.
PROBLEMS = []


def problem(text):
    if text not in PROBLEMS:
        PROBLEMS.append(text)


def load(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f)
    except FileNotFoundError:
        return default
    except ValueError as e:
        problem(f"`{path}` is not valid JSON ({e}) — Claude Code cannot read it either; its settings do not apply")
        return default
    except OSError as e:
        problem(f"`{path}` cannot be read ({e.__class__.__name__}: {e})")
        return default
    if default is not None and not isinstance(data, type(default)):
        problem(f"`{path}` holds a {type(data).__name__}, expected a {type(default).__name__} — ignored")
        return default
    return data


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def read_lines(path):
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        return []
    except OSError as e:
        problem(f"`{path}` cannot be read ({e.__class__.__name__}: {e})")
        return []
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        problem(f"`{path}` is not UTF-8 — read with replacement characters; Claude Code may show garbled text")
        text = raw.decode("utf-8", errors="replace")
    return text.splitlines()


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


def imports(path, seen=None, depth=0):
    """Files a CLAUDE.md pulls in with `@path` lines (Claude Code memory imports), recursively.
    A rule file that sits on disk but is not imported here is never loaded."""
    seen = seen if seen is not None else []
    base = os.path.dirname(path)
    for line in read_lines(path):
        m = re.match(r"^@(\S+)\s*$", line.strip())
        if not m:
            continue
        target = os.path.expanduser(m.group(1))
        target = target if os.path.isabs(target) else os.path.normpath(os.path.join(base, target))
        if not os.path.isfile(target):
            problem(f"`{path}` imports `@{m.group(1)}`, which does not exist — that part of the rules is never loaded")
        if target not in seen:
            seen.append(target)
            if depth < 4 and os.path.isfile(target):
                imports(target, seen, depth + 1)
    return seen


def loaded_files(repo, cfg):
    files = []
    for top in (os.path.join(cfg, "CLAUDE.md"), os.path.join(repo, "CLAUDE.md"), os.path.join(repo, "CLAUDE.local.md")):
        if os.path.isfile(top):
            files.append(top)
            files += [f for f in imports(top) if f not in files]
    files += [f for f in sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md"))) if f not in files]
    files.append(os.path.join(memory_dir(repo, cfg), "MEMORY.md"))
    return files


def hook_entries(path):
    """(event, matcher, command) for every hook in a settings-shaped file; malformed parts are named."""
    out = []
    hk = (load(path, {}) or {}).get("hooks") or {}
    if not isinstance(hk, dict):
        problem(f"`{path}`: `hooks` is a {type(hk).__name__}, not an object — no hook in it runs")
        return out
    for event, groups in hk.items():
        if not isinstance(groups, list):
            problem(f"`{path}`: hooks.{event} is a {type(groups).__name__}, not a list — ignored")
            continue
        for g in groups:
            if not isinstance(g, dict):
                problem(f"`{path}`: an entry under hooks.{event} is a {type(g).__name__} ({str(g)[:40]}), not an object — ignored")
                continue
            for h in g.get("hooks") or []:
                if isinstance(h, dict):
                    out.append((event, g.get("matcher", "") or "*", str(h.get("command", ""))))
    return out


def settings_layers(repo, cfg):
    return [(os.path.join(cfg, "settings.json"), "user"),
            (os.path.join(repo, ".claude", "settings.json"), "project"),
            (os.path.join(repo, ".claude", "settings.local.json"), "local")]


def enabled_plugins(layers):
    out = {}
    for path, _ in layers:
        ep = (load(path, {}) or {}).get("enabledPlugins") or {}
        if not isinstance(ep, dict):
            problem(f"`{path}`: `enabledPlugins` is a {type(ep).__name__}, not an object — Claude Code ignores it")
            continue
        for k, v in ep.items():
            out[k] = bool(v)  # later layers win
    return [k for k, v in out.items() if v]


# ---------- 1 core state
def core_state(repo, cfg, layers):
    out = ["## 1 Core state", ""]
    core = os.path.join(repo, "core")
    if not os.path.isdir(core):
        out += ["- no `core/` directory in the brain — core rules can only come from a plugin", ""]
    elif not os.listdir(core):
        problem("`core/` exists but is EMPTY — the core submodule was never initialised (`git submodule update --init`); "
                "no core rule, helper or hook from it can run")
        out += ["- `core/` is empty (submodule not initialised)", ""]
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
    loaded = [os.path.normcase(os.path.normpath(f)) for f in loaded_files(repo, cfg)]
    # A moved-file stub ("# MOVED: …", "DEPRECATED PATH") only redirects old imports; not loading it is right.
    rules = [r for r in rules if not re.search(r"^# MOVED:|DEPRECATED PATH", "\n".join(read_lines(r)[:6]), re.M)]
    on_disk_not_loaded = [r for r in rules if os.path.normcase(os.path.normpath(r)) not in loaded]
    loaded_rules = [r for r in rules if r not in on_disk_not_loaded]
    out.append(f"- core rule files: {len(rules)} on disk, {len(loaded_rules)} imported by CLAUDE.md")
    for r in on_disk_not_loaded:
        out.append(f"  - NOT LOADED: `{rel(r, repo, repo)}` — on disk, but no `@` import pulls it in; its rules never reach the AI")
    text = "\n".join("\n".join(read_lines(r)) for r in loaded_rules)
    disk = "\n".join("\n".join(read_lines(r)) for r in rules)
    out += ["", "Question-reducing rules in the LOADED core rules:", ""]
    if not rules:
        out.append("- no `core/rules/*.md` found — nothing to check")
    for marker, meaning in CORE_MARKERS:
        state = "present" if marker in text else ("on disk but NOT LOADED" if marker in disk else "MISSING")
        out.append(f"- {state}: \"{marker}\" — {meaning}")
    out.append("")
    return out


# ---------- 2 loaded context
def loaded_context(repo, home, cfg):
    out = ["## 2 Context loaded at every start", ""]
    files = loaded_files(repo, cfg)
    mem = files[-1]
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
        if not isinstance(perms, dict):
            problem(f"`{path}`: `permissions` is a {type(perms).__name__}, not an object — none of its rules apply")
            continue
        for k in rules:
            lst = perms.get(k) or []
            if not isinstance(lst, list):
                problem(f"`{path}`: `permissions.{k}` is a {type(lst).__name__}, not a list — its rules do not apply")
                continue
            rules[k] += [(r, label) for r in lst if isinstance(r, str)]
        if perms.get("defaultMode"):
            mode.append(f"{perms['defaultMode']} ({label})")
    out.append(f"- defaultMode: {', '.join(mode) if mode else 'not set (default: ask for anything not allowed)'}")
    out.append(f"- rules: {len(rules['allow'])} allow, {len(rules['ask'])} ask, {len(rules['deny'])} deny")
    # The brain was bootstrapped from the core's settings template: the same probes against the
    # template tell "the template asks" apart from "this brain added the brake" (2026-10-16, macOS:
    # v1.3.41's template put `git push*` under ask and had no rule for `gh pr *`).
    tpl = (load(os.path.join(repo, "core", "templates", "settings.json"), {}) or {}).get("permissions") or {}
    trules = {k: [(r, "core template") for r in tpl.get(k) or [] if isinstance(r, str)] for k in ("allow", "ask", "deny")}
    if tpl:
        out.append(f"- core template `core/templates/settings.json`: {len(trules['allow'])} allow, "
                   f"{len(trules['ask'])} ask, {len(trules['deny'])} deny — shown after each verdict as [template: …]")
    out.append("")

    def verdict_of(rs, cmd):
        for kind in ("deny", "ask", "allow"):
            hit = next(((r, lab) for r, lab in rs[kind] if rule_matches(r, cmd)), None)
            if hit:
                return kind, hit
        return None, None

    for label, cmd in PROBES:
        cmd = cmd.replace("<brain>", os.path.abspath(repo).replace(os.sep, "/"))
        kind, hit = verdict_of(rules, cmd)
        verdict = (f"{kind.upper()} by `{hit[0]}` ({hit[1]})" if kind else
                   "no rule — the harness asks the human (in auto mode its classifier decides); "
                   "the AI may report that prompt as 'not allowed'")
        if tpl:
            tk, th = verdict_of(trules, cmd)
            verdict += f" [template: {tk.upper() + ' `' + th[0] + '`' if tk else 'no rule'}]"
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
        for event, matcher, cmd in hook_entries(path):
            where = "core" if re.search(r"core[/\\]helpers|CLAUDE_PLUGIN_ROOT", cmd) else "instance"
            n += 1
            out.append(f"- {event} [{matcher}] ({label}, {where}): `{cmd[:140]}`")
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
    wired_live_read = False
    for path, label in layers:
        for event, _, cmd in hook_entries(path):
            if event in ("UserPromptSubmit", "PreToolUse") and re.search(r"recall|memory", cmd, re.I):
                rec.append(f"{event} `{cmd[:100]}` ({label})")
            if event == "PreToolUse" and "live-read-gate" in cmd:
                wired_live_read = True
    # live-read-gate hands memory to the AI too: before a live tool runs, the files its domain lists
    # must have been read in the session. Measured 2026-10-16: a brain with five desk memories as
    # mandatory reading was reported "none" here — the hook had been looked for by name only.
    lr = load(os.path.join(repo, ".claude", "rules", "live-read.json"), {}) or {}
    for d in [d for d in (lr.get("domains") or []) if isinstance(d, dict)]:
        req = [str(r.get("path", "")) for r in (d.get("required") or []) if isinstance(r, dict) and r.get("path")]
        mem = [p for p in req if "memory" in p.replace("\\", "/")]
        hit = 0
        for p in req:
            fp = os.path.expanduser(p)
            fp = fp if os.path.isabs(fp) else os.path.join(repo, fp)
            hit += any(rx.search(line) for line in read_lines(fp))
        state = "wired" if wired_live_read else "NOT wired — the list exists, nothing enforces it"
        tools = ", ".join(f"`{t}`" for t in (d.get("tools") or [])[:2]) or "its tools"
        rec.append(f"live-read-gate domain `{d.get('name', '?')}` ({state}): {len(req)} mandatory read(s) before {tools}"
                   + (f", {len(mem)} of them memory" if mem else "")
                   + (f", {hit} mention `{topic}`" if hit else f", none mentions `{topic}`"))
    out.append("- what hands memory to the AI before it acts: "
               + ("; ".join(rec) if rec else "none — memory reaches the AI only through the index loaded at start"))
    out.append("")
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--home", default=os.path.expanduser("~"))
    ap.add_argument("--topic", default=r"message.?center")
    ap.add_argument("--out", default="")
    ap.add_argument("--memory-dir", action="store_true",
                    help="print the brain's auto-memory folder and exit (for a follow-up agent's --add-dir, "
                         "so it reads memory without reaching the session transcripts beside it)")
    a = ap.parse_args(argv)
    repo = os.path.abspath(a.repo)
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(a.home, ".claude")
    if a.memory_dir:
        print(memory_dir(repo, cfg).replace(os.sep, "/"))
        return 0
    layers = settings_layers(repo, cfg)
    if not os.path.isfile(os.path.join(repo, "CLAUDE.md")):
        problem(f"no `CLAUDE.md` in `{repo}` — is this the brain folder? Nothing of the brain's rules loads without it")
    sections = [
        ("1 Core state", lambda: core_state(repo, cfg, layers)),
        ("2 Context loaded at every start", lambda: loaded_context(repo, a.home, cfg)),
        ("3 Brake phrases in local carriers", lambda: brakes(repo, a.home, cfg)),
        ("4 Permissions", lambda: permissions(repo, cfg, layers)),
        ("5 Hooks", lambda: hooks(repo, cfg, layers)),
        ("6 Recall", lambda: recall(repo, a.home, cfg, layers, a.topic)),
    ]
    body = []
    for name, fn in sections:
        # One section's crash must not cost the others: it becomes a named line instead.
        try:
            body += fn()
        except Exception as e:  # noqa: BLE001 — a report, every failure is data
            tb = traceback.extract_tb(e.__traceback__)[-1]
            body += [f"## {name}", "", f"- SECTION FAILED: {e.__class__.__name__}: {e} (line {tb.lineno})", ""]
            problem(f"section '{name}' crashed: {e.__class__.__name__}: {e} — the rest of the report is complete")
    head = ["# Autonomy diagnose", "",
            f"Brain `{os.path.basename(repo)}`, read-only, no model. Python {sys.version.split()[0]} on {sys.platform}.", "",
            "## 0 Problems found while reading", ""]
    head += [f"- {p}" for p in PROBLEMS] or ["- none"]
    text = redact("\n".join(head + [""] + body).rstrip() + "\n")
    if a.out:
        with open(a.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print(f"autonomy-diagnose: report written to {a.out}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
