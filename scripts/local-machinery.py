#!/usr/bin/env python3
"""local-machinery.py — where does this brain carry behaviour the shared core does not, and why?

WHY (measured 2026-10-08 on the proving brain): of 31 hook and stop-check entries, 12 ran from
the released core, 13 from three unmerged development checkouts (the whole session start and
the whole stop dispatcher among them), and 8 from the instance's own scripts — at least four of
them general mechanisms (a read gate before live systems, a time-word gate, a reconnect gate)
that no other brain had. Every brain then behaves differently, a measurement on one says nothing
about the others, and a fix made locally is a fix nobody else gets. Nothing showed it: every
hook worked, so nothing failed.

WHY THE INVENTORY (measured 2026-10-09, same brain): the first version scanned hooks, then
scripts — the search space followed each incident, not the invariant. Instance skills, rule
text, workflows, extra plugins, git hooks and scheduled jobs were never looked at, and the
deviations in them were found only when the operator asked. Three items declared "instance
only" were general (nobody checked the reason), and a near-copy of a core tool under another
name was invisible. So: one INVENTORY over every carrier type (CARRIERS below, each with a
planted case and a negative control in the fixture), declarations that must name the
instance token they rely on, a name-similarity check against the core, and one summary line.

The invariant: one system. Every item that carries behaviour runs from the core, OR it is
declared as instance machinery with the reason AND the instance-specific token it relies on,
OR it is an alpha with an expiry date. Anything else is a finding at every session start.

Declarations: `.claude/rules/local-machinery.json`
  {"identity_tokens": ["<host>", "<ip>", "<person>", "<device>", ...]   (or {"hosts": [...], ...}),
   "instance": {"<id or prefix>": {"why": "...", "evidence": "<token the item contains>",
                                   "distinct_from": "<core name it only resembles>"}},
   "alpha":    {"<id or prefix>": {"until": "YYYY-MM-DD", "why": "<what is being measured>"}}}
An item id is its repo-relative path (`~/` for the user's Claude dir, `<file>#<heading>` for a
rule section, `plugin:<id>`, `mcp:<server>`, `launchd:<file>`, `schtasks:<task>`). A key
matches when the id starts with it or a hook command contains it. The old string form
`"<path>": "<why>"` still counts as a declaration but is reported as a reason without evidence.

Usage: local-machinery.py [--repo DIR] [--home DIR] [--decl FILE] [--today YYYY-MM-DD]
                          [--list] [--carriers]
Output: nothing when every item is core or declared with evidence; otherwise one plain line per
kind of finding (`!! ` when loud; also: hook/stop-check targets that do not exist, same-named
thin wrappers of core items, carriers declared in two contradicting places) and a last line `local machinery summary: key=value ...`.
--list prints every item with its class and carrier. Exit 0 always — never blocks a start.
"""
import argparse
import csv
import datetime
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys

# The session start reads this output through a pipe; unpinned, Windows Python emits the
# em dashes in the cp1252 codepage and ends lines CRLF (core register docs/os-traps.md OS-9).
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass

SCRIPT_EXT = (".sh", ".py", ".cjs", ".js", ".mjs", ".ps1")
TEXT_EXT = SCRIPT_EXT + (".md", ".json", ".txt", ".toml", ".yaml", ".yml", ".plist", ".xml", ".ts")
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", "site-packages", ".claude-state"}
CORE_PLUGIN_PREFIXES = ("brain-core@", "brain-core-next@")  # same as plugin-scope-check.py
LOUD = ("missing", "shadow", "wrapper", "contradiction", "outside", "expired", "offmain", "edited", "general", "noevidence", "badevidence")
CLASSES = LOUD + ("duplicate", "undeclared")


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def read(path, cap=262144):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read(cap)
    except OSError:
        return ""


def read_tree(d, cap=1 << 20):
    out, total = [], 0
    for p in sorted(pathlib.Path(d).rglob("*")):
        if total > cap:
            break
        if p.is_file() and not SKIP_DIRS & set(p.parts) and (p.suffix in TEXT_EXT or not p.suffix):
            t = read(p)
            out.append(t)
            total += len(t)
    return "\n".join(out)


def git(*args):
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


class Ctx:
    def __init__(self, repo, home):
        self.repo_abs = os.path.abspath(repo).replace("\\", "/")
        self.root = pathlib.Path(repo).resolve()
        self.home = pathlib.Path(home).resolve()
        self.unchecked = []
        self.core_hooks = []
        self.missing = []

    def under(self, p, base):
        try:
            pathlib.Path(p).resolve().relative_to(base)
            return True
        except (ValueError, OSError):
            return False

    def rel_id(self, p):
        p = pathlib.Path(p)
        for base, pre in ((self.root, ""), (self.home, "~/")):
            try:
                return pre + p.resolve().relative_to(base).as_posix()
            except (ValueError, OSError):
                pass
        return str(p).replace("\\", "/")

    def in_core(self, p):
        return self.under(p, self.root / "core")


def item(carrier, id_, content, file=None, kind="instance", cmd=None, name=None):
    return {"carrier": carrier, "id": id_, "content": content or "", "file": file,
            "kind": kind, "cmd": cmd, "name": name}


# ---------------------------------------------------------------- hooks and stop checks

def tokens(cmd):
    norm = cmd.replace("\\", "/")
    try:
        return shlex.split(norm)
    except ValueError:
        return norm.replace('"', " ").split()


def classify(cmd, C):
    norm = cmd.replace("\\", "/")
    if "CLAUDE_PLUGIN_ROOT" in norm or "/core/" in norm:
        return "core"
    toks = tokens(cmd)
    if any(t.startswith("core/") for t in toks):
        return "core"
    if "$CLAUDE_PROJECT_DIR" in norm or "%CLAUDE_PROJECT_DIR%" in norm or "${CLAUDE_PROJECT_DIR}" in norm:
        return "instance"
    for tok in toks:
        if tok.startswith("~/"):
            tok = C.home.as_posix() + tok[1:]
        if tok.startswith("/") or (len(tok) > 2 and tok[1] == ":"):
            if tok.startswith(C.repo_abs + "/") or tok.startswith(C.root.as_posix() + "/"):
                return "instance"
            if tok.endswith(SCRIPT_EXT):
                return "outside"
    return "instance"


def cmd_target(cmd, C):
    """The script a hook command runs, as a path (it may not exist)."""
    best = None
    for tok in tokens(cmd):
        for var in ("${CLAUDE_PROJECT_DIR}", "$CLAUDE_PROJECT_DIR", "%CLAUDE_PROJECT_DIR%"):
            tok = tok.replace(var, C.repo_abs)
        if tok.startswith("~/"):
            tok = C.home.as_posix() + tok[1:]
        p = pathlib.Path(tok)
        if not p.is_absolute():
            p = C.root / tok
        if tok.endswith(SCRIPT_EXT) or p.is_file():
            best = p
    return best


def settings_files(C):
    return [C.root / ".claude" / "settings.json", C.root / ".claude" / "settings.local.json",
            C.home / ".claude" / "settings.json"]


def hook_item(carrier, cmd, C):
    kind = classify(cmd, C)
    t = cmd_target(cmd, C)
    # A target that is gone fails silently: a stop check with an absolute path into a removed
    # dev checkout just stops running (measured 2026-10-09: 8 of 11 stop checks on the proving
    # brain pointed into dev checkouts by absolute path, and no other check would notice).
    if t and not t.exists() and "CLAUDE_PLUGIN_ROOT" not in cmd:
        C.missing.append(f"{carrier}: {C.rel_id(t)}")
    if kind == "core":
        C.core_hooks.append((carrier, cmd))
        return None
    content = read(t) if t and t.is_file() else cmd
    return item(carrier, C.rel_id(t) if t else cmd, content, file=t if t and t.is_file() else None,
                kind=kind, cmd=cmd, name=t.name if t else None)


def scan_hooks(C):
    out = []
    for f in settings_files(C):
        for matchers in ((load(f) or {}).get("hooks") or {}).values():
            for m in matchers or []:
                for h in (m.get("hooks") or []) if isinstance(m, dict) else []:
                    if isinstance(h, dict) and h.get("command"):
                        out.append(hook_item("hook", h["command"], C))
    return out


def scan_stop_checks(C):
    checks = load(C.root / ".claude" / "rules" / "stop-checks.json")
    if isinstance(checks, dict):
        checks = checks.get("checks")
    out = []
    for c in checks or []:
        cmd = (c.get("cmd") or c.get("command")) if isinstance(c, dict) else None
        if cmd:
            out.append(hook_item("stop-check", cmd, C))
    return out


# ---------------------------------------------------------------- other carriers

def scan_mcp(C):
    """MCP servers that run a file inside this brain (servers from suite checkouts are covered
    by the off-main check, package-manager servers are not local machinery)."""
    out = []
    for name, srv in ((load(C.root / ".mcp.json") or {}).get("mcpServers") or {}).items():
        for tok in [srv.get("command") or ""] + [str(x) for x in srv.get("args") or []]:
            p = pathlib.Path(tok) if os.path.isabs(tok) else C.root / tok
            if tok and p.is_file() and C.under(p, C.root) and not C.in_core(p):
                out.append(item("mcp", f"mcp:{name}", read(p), file=p, name=p.name))
                break
    return out


def scan_git_hooks(C):
    """Effective git hooks of this brain: local core.hooksPath, else global, else .git/hooks.
    Only names without a dot run as hooks (pre-commit, pre-push, ...)."""
    if not (C.root / ".git").exists():
        return []
    local = git("-C", str(C.root), "config", "--local", "core.hooksPath")
    glob_ = git("config", "--global", "core.hooksPath")
    if local or glob_:
        raw = os.path.expanduser(local or glob_)
        d = pathlib.Path(raw) if os.path.isabs(raw) else (C.root / raw if local else pathlib.Path(raw))
    else:
        gp = git("-C", str(C.root), "rev-parse", "--git-path", "hooks")
        d = pathlib.Path(gp) if os.path.isabs(gp) else C.root / gp
    out = []
    if d.is_dir():
        for p in sorted(d.iterdir()):
            if p.is_file() and "." not in p.name and not C.in_core(p):
                kind = "instance" if C.under(p, C.root) else "outside"
                out.append(item("git-hook", C.rel_id(p), read(p), file=p, kind=kind, name=p.name))
    return out


def scan_scheduled(C):
    """Scheduled jobs that run something in this brain. macOS: per-user LaunchAgents;
    Windows: schtasks. Anywhere else the carrier is reported as not checked."""
    needles = {C.repo_abs.lower(), C.root.as_posix().lower()}
    needles |= {n.replace("/", "\\") for n in needles}
    la = C.home / "Library" / "LaunchAgents"
    out = []
    if la.is_dir():
        for p in sorted(la.glob("*.plist")):
            t = read(p)
            if any(n in t.lower() for n in needles):
                out.append(item("scheduled", f"launchd:{p.name}", t, file=p, name=p.stem))
        return out
    if shutil.which("schtasks"):
        try:
            r = subprocess.run(["schtasks", "/query", "/fo", "csv", "/v"], capture_output=True,
                               text=True, errors="replace", timeout=60)
            rows = list(csv.reader(io.StringIO(r.stdout)))
        except (OSError, subprocess.SubprocessError, csv.Error):
            rows = []
        for row in rows[1:]:
            line = ",".join(row)
            if row and row != rows[0] and len(row) > 1 and any(n in line.lower() for n in needles):
                out.append(item("scheduled", f"schtasks:{row[1]}", line, name=row[1].strip("\\")))
        return out
    C.unchecked.append("scheduled")
    return out


def scan_plugins(C):
    """Enabled plugins that are neither the core plugin nor a suite listed in
    config/ecosystem.json (kind suite/core, field consumer_plugin)."""
    eco = (load(C.root / "config" / "ecosystem.json") or {}).get("repos") or {}
    known = {r.get("consumer_plugin") for r in eco.values()
             if isinstance(r, dict) and r.get("kind") in ("suite", "core")}
    installed = (load(C.home / ".claude" / "plugins" / "installed_plugins.json") or {}).get("plugins") or {}
    enabled = {}
    user, project, local = settings_files(C)[2], settings_files(C)[0], settings_files(C)[1]
    for f in (user, project, local):  # Claude Code precedence: local over project over user
        for pid, on in ((load(f) or {}).get("enabledPlugins") or {}).items():
            enabled[pid] = on
    out = []
    for pid, on in sorted(enabled.items()):
        if on is not True or pid in known or pid.startswith(CORE_PLUGIN_PREFIXES):
            continue
        inst = installed.get(pid) or []
        path = inst[0].get("installPath") if inst and isinstance(inst[0], dict) else None
        content = read_tree(path) if path and os.path.isdir(path) else pid
        out.append(item("plugin", f"plugin:{pid}", content, name=pid.split("@")[0]))
    return out


def scan_skills(C):
    out = []
    for base in (C.root / ".claude" / "skills", C.home / ".claude" / "skills"):
        if base.is_dir():
            for d in sorted(base.iterdir()):
                if d.is_dir() and not d.is_symlink():
                    out.append(item("skill", C.rel_id(d), read_tree(d), file=d, name=d.name))
    return out


def scan_workflows(C):
    base = C.root / ".claude" / "workflows"
    out = []
    if base.is_dir():
        for p in sorted(base.iterdir()):
            if p.is_file() and not p.is_symlink():
                out.append(item("workflow", C.rel_id(p), read(p), file=p, name=p.stem))
    return out


def md_carrier(sub, carrier):
    def scan(C):
        out = []
        for base in (C.root / ".claude" / sub, C.home / ".claude" / sub):
            if base.is_dir():
                for p in sorted(base.rglob("*.md")):
                    if p.is_file() and not p.is_symlink():
                        out.append(item(carrier, C.rel_id(p), read(p), file=p, name=p.stem))
        return out
    return scan


def sections(text):
    cur, buf, out = "(top)", [], []
    for ln in text.splitlines():
        m = re.match(r"#{2,3} +(.+?)\s*$", ln)
        if m:
            out.append((cur, buf))
            cur, buf = m.group(1), []
        buf.append(ln)
    out.append((cur, buf))
    return [(h, "\n".join(b)) for h, b in out if "\n".join(b).strip()]


def scan_rules(C):
    """Rule text, one item per ## / ### section: a whole file always contains some instance
    token, a general rule added to it would hide behind the others."""
    files = [C.root / "CLAUDE.md", C.root / "CLAUDE.local.md", C.home / ".claude" / "CLAUDE.md"]
    for base in (C.root / ".claude" / "rules", C.home / ".claude" / "rules"):
        if base.is_dir():
            files += sorted(base.glob("*.md"))
    out = []
    for f in files:
        if not f.is_file():
            continue
        rel, seen = C.rel_id(f), {}
        for head, body in sections(read(f, cap=1 << 21)):
            seen[head] = seen.get(head, 0) + 1
            sid = f"{rel}#{head}" + (f" ({seen[head]})" if seen[head] > 1 else "")
            out.append(item("rule", sid, body))
    return out


def scan_scripts(C):
    """Every script in the brain outside the core and the other carriers. Fixtures (test-*,
    *-test.*, test_*.py, *_test.py) belong to the script they test."""
    out = []
    prune = {C.root / "core", C.root / ".claude" / "skills", C.root / ".claude" / "workflows"}
    for dirpath, dirnames, filenames in os.walk(C.root):
        dp = pathlib.Path(dirpath)
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and dp / d not in prune
                             and not (dp / d / ".git").exists() and not (dp / d).is_symlink())
        for fn in sorted(filenames):
            p = dp / fn
            if p.suffix not in SCRIPT_EXT or p.is_symlink():
                continue
            if fn.startswith(("test-", "test_")) or "-test." in fn or p.stem.endswith("_test"):
                continue
            out.append(item("script", C.rel_id(p), read(p), file=p, name=fn))
    return out


# Order matters: the first carrier that claims a file owns it (a hook's script is a hook, not
# also a loose script). The fixture removes one line at a time — keep one carrier per line.
CARRIERS = {
    "hook": scan_hooks,
    "stop-check": scan_stop_checks,
    "mcp": scan_mcp,
    "git-hook": scan_git_hooks,
    "scheduled": scan_scheduled,
    "plugin": scan_plugins,
    "skill": scan_skills,
    "workflow": scan_workflows,
    "output-style": md_carrier("output-styles", "output-style"),
    "agent": md_carrier("agents", "agent"),
    "command": md_carrier("commands", "command"),
    "rule": scan_rules,
    "script": scan_scripts,
}


def inventory(C):
    items, claimed = [], set()
    for scan in CARRIERS.values():
        for it in scan(C):
            if not it:
                continue
            if it["file"]:
                key = os.path.normcase(os.path.realpath(it["file"]))
                if key in claimed:
                    continue
                claimed.add(key)
            items.append(it)
    return items


# ---------------------------------------------------------------- core names

def core_names(C):
    """name -> core path, over scripts, helpers, workflows and skills of the core checkout."""
    names = {}
    core = C.root / "core"
    for sub in ("scripts", "helpers", "workflows"):
        d = core / sub
        if d.is_dir():
            for p in d.rglob("*"):
                if p.is_file() and "__pycache__" not in p.parts:
                    names.setdefault(p.name, f"{sub}/{p.name}")
                    names.setdefault(p.stem, f"{sub}/{p.name}")
    if (core / "skills").is_dir():
        for d in (core / "skills").iterdir():
            if d.is_dir():
                names.setdefault(d.name, f"skills/{d.name}")
    return names


def stem_tokens(name):
    return [t for t in re.split(r"[-_.]+", pathlib.Path(name).stem.lower()) if t]


def shared_run(a, b):
    best = 0
    for i in range(len(a)):
        for j in range(len(b)):
            k = 0
            while i + k < len(a) and j + k < len(b) and a[i + k] == b[j + k]:
                k += 1
            best = max(best, k)
    return best


def near_duplicate(name, core):
    """A core name that shares a run of at least two name tokens (wait-mcp-restart vs
    wait-mcp-reconnect). Fixtures on the core side are not tools."""
    mine = stem_tokens(name)
    if len(mine) < 2:
        return None
    for cname, cpath in sorted(core.items()):
        if cname.startswith(("test-", "test_")) or "-test" in cname or "." in cname:
            continue
        if shared_run(mine, stem_tokens(cname)) >= 2:
            return cpath
    return None


# ---------------------------------------------------------------- judging

def match(decl, it):
    keys = [k for k in decl if it["id"].startswith(k) or (it["cmd"] and k in it["cmd"])]
    return max(keys, key=len) if keys else None


def identity_matcher(tokens_):
    if isinstance(tokens_, dict):
        tokens_ = [t for v in tokens_.values() for t in (v if isinstance(v, list) else [v])]
    tokens_ = [str(t) for t in tokens_ or [] if str(t).strip()]
    if not tokens_:
        return None
    alt = "|".join(re.escape(t) for t in sorted(tokens_, key=len, reverse=True))
    return re.compile(rf"(?<![A-Za-z0-9])(?:{alt})(?![A-Za-z0-9])", re.IGNORECASE)


def judge(items, decl, C, today):
    inst, alpha = decl.get("instance") or {}, decl.get("alpha") or {}
    ident = identity_matcher(decl.get("identity_tokens"))
    core = core_names(C)
    found = {c: [] for c in CLASSES}
    # A carrier listed in two contradicting places: declared "run by hand" in the core's
    # manual-tools list (read by brain-selftest.sh) yet wired to run by itself.
    manual = set((load(C.root / ".claude" / "rules" / "manual-tools.json") or {}).get("manual") or [])
    for it in items:
        it["class"] = "ok"
        name = it["name"]
        if name and name in core and it["carrier"] in ("script", "skill", "workflow"):
            # Same name: a thin wrapper that only calls the core one looks like a copy from
            # outside (measured 2026-10-09) — say which, the fix differs.
            cls = "wrapper" if ("core/" + core[name]) in it["content"].replace("\\", "/") else "shadow"
            it["class"] = cls
            found[cls].append(it["id"])
            continue
        ka, ki = match(alpha, it), match(inst, it)
        if name in manual and it["carrier"] in ("hook", "stop-check", "git-hook", "scheduled", "mcp"):
            found["contradiction"].append(f"{it['id']} (manual-tools.json, yet wired as {it['carrier']})")
        if ka and ki:
            found["contradiction"].append(f"{it['id']} (declared both instance '{ki}' and alpha '{ka}')")
        if ka:
            until = str((alpha[ka] or {}).get("until", "")) if isinstance(alpha[ka], dict) else ""
            if not until or until < today:
                it["class"] = "expired"
                found["expired"].append(f"{ka} (until {until or '?'})")
            continue
        d = inst.get(ki) if ki else None
        if ki:
            ev = d.get("evidence") if isinstance(d, dict) else None
            evs = [ev] if isinstance(ev, str) else [e for e in ev or [] if isinstance(e, str)]
            evs = [e for e in evs if len(e.strip()) >= 3]
            if not evs:
                it["class"] = "noevidence"
                found["noevidence"].append(it["id"])
            elif not any(e.lower() in it["content"].lower() for e in evs):
                it["class"] = "badevidence"
                found["badevidence"].append(f"{it['id']} ({'|'.join(evs)})")
        elif it["kind"] == "outside":
            it["class"] = "outside"
            found["outside"].append(it["cmd"] or it["id"])
        elif ident and not ident.search(it["content"]):
            it["class"] = "general"
            found["general"].append(it["id"])
        else:
            it["class"] = "undeclared"
            found["undeclared"].append(it["id"])
        dup = near_duplicate(name, core) if name else None
        distinct = d.get("distinct_from") if isinstance(d, dict) else None
        if dup and not (distinct and distinct in dup):
            found["duplicate"].append(f"{it['id']} (core {dup})")
    return found


# ---------------------------------------------------------------- the two checks that are not items

def same_tree(key, top):
    # Text match first; then the real paths, because one directory has two spellings on
    # Windows — the 8.3 short name in a temp path vs git's long name (os-traps OS-8).
    if key.rstrip("/\\").replace("\\", "/") in top.replace("\\", "/"):
        return True
    if not os.path.exists(key):
        return False
    k = os.path.normcase(os.path.realpath(key)).rstrip("/\\")
    t = os.path.normcase(os.path.realpath(top))
    return t == k or t.startswith(k + os.sep)


def tool_sources_off_main(C):
    """MCP servers (`.mcp.json`) and skill symlinks run straight from suite working trees.
    Those are fine on main and unreleased code on any other branch. Returns
    `(<checkout>, <branch>)` for every source checkout outside this brain not on main/master."""
    paths = []
    for srv in ((load(C.root / ".mcp.json") or {}).get("mcpServers") or {}).values():
        for tok in [srv.get("command") or ""] + [str(x) for x in srv.get("args") or []]:
            if os.path.isabs(tok) and os.path.exists(tok):
                paths.append(pathlib.Path(tok))
    skills = C.root / ".claude" / "skills"
    if skills.is_dir():
        paths += [p.resolve() for p in skills.iterdir() if p.is_symlink()]
    found = {}
    for p in paths:
        top = git("-C", str(p if p.is_dir() else p.parent), "rev-parse", "--show-toplevel")
        if not top or pathlib.Path(top).resolve() == C.root or top in found:
            continue
        found[top] = git("-C", top, "rev-parse", "--abbrev-ref", "HEAD")
    return [(t, b) for t, b in found.items() if b and b not in ("main", "master")]


def edited_core(C):
    """Files edited inside the core checkout itself (the pin check in session-bootup.sh sees a
    moved commit, not uncommitted edits)."""
    if not (C.root / "core" / ".git").exists():
        return []
    try:
        r = subprocess.run(["git", "-C", str(C.root / "core"), "status", "--porcelain",
                            "--untracked-files=no"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    return [ln[3:] for ln in r.stdout.splitlines() if ln.strip()] if r.returncode == 0 else []


# ---------------------------------------------------------------- output

def short(items, n=6):
    seen = []
    for i in items:
        if i not in seen:
            seen.append(i)
    return ", ".join(seen[:n]) + (f" (+{len(seen) - n})" if len(seen) > n else "")


def uniq(xs):
    return list(dict.fromkeys(xs))


MESSAGES = {
    "edited": "!! local machinery: {n} core file(s) edited inside core/: {x} — core changes go as a PR against the core, never edited in place",
    "offmain": "!! local machinery: {n} tool source checkout(s) not on main feed this brain (MCP server or skill symlink): {x} — unreleased code in every session; switch the checkout back to main, or declare it as alpha",
    "missing": "!! local machinery: {n} hook or stop-check target(s) do not exist: {x} — the check silently stopped running; restore the path, repoint it at the core, or unwire it",
    "wrapper": "!! local machinery: {n} same-named instance wrapper(s) only call the core item: {x} — remove the wrapper and call the core one directly",
    "contradiction": "!! local machinery: {n} item(s) are declared in two contradicting places: {x} — decide which one is true and fix the other",
    "shadow": "!! local machinery: {n} instance item(s) shadow a core item of the same name: {x} — use the core one and remove the copy, or rename it if it is a different tool",
    "expired": "!! local machinery: {n} alpha(s) past their date, still wired: {x} — merge, extend with a reason, or unwire",
    "outside": "!! local machinery: {n} item(s) run from outside this brain and outside the core, undeclared: {x} — for the AI: classify each (why local, sensible, core-worthy?) and declare it as alpha with a date in .claude/rules/local-machinery.json, or open the core PR",
    "general": "!! local machinery: {n} undeclared item(s) contain none of this brain's identity tokens, presumably general: {x} — for the AI: core (or suite) PR, or declare as instance with the token it relies on as evidence",
    "noevidence": "!! local machinery: {n} instance declaration(s) give a reason without evidence: {x} — add \"evidence\": the instance-specific token the item relies on",
    "badevidence": "!! local machinery: {n} item(s) do not contain the evidence their declaration names: {x} — the declaration is wrong or stale; reclassify",
    "duplicate": "local machinery: {n} item(s) look like a near-duplicate of a core item: {x} — for the AI: same purpose = use the core one; different = declare \"distinct_from\"",
    "undeclared": "local machinery: {n} item(s) without a declaration{c}: {x} — for the AI: classify each; general = core PR, instance-only = declare why + evidence",
}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR") or ".")
    ap.add_argument("--home", default=os.path.expanduser("~"))
    ap.add_argument("--decl", help="declarations file (default: <repo>/.claude/rules/local-machinery.json)")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--carriers", action="store_true", help="print the carrier types and exit")
    a = ap.parse_args(argv)
    if a.carriers:
        print("\n".join(CARRIERS))
        return 0
    C = Ctx(a.repo, a.home)
    decl = load(a.decl or os.path.join(a.repo, ".claude", "rules", "local-machinery.json"))
    decl = decl if isinstance(decl, dict) else {}

    items = inventory(C)
    found = judge(items, decl, C, a.today)
    found["edited"] = edited_core(C)
    found["missing"] = C.missing
    alpha = decl.get("alpha") or {}
    for top, br in tool_sources_off_main(C):
        ka = next((k for k in alpha if same_tree(k, top)), None)
        if not ka:
            found["offmain"].append(f"{os.path.basename(top)}@{br}")
            continue
        until = str((alpha[ka] or {}).get("until", "")) if isinstance(alpha[ka], dict) else ""
        if not until or until < a.today:
            found["expired"].append(f"{ka} (until {until or '?'})")

    if a.list:
        for carrier, cmd in C.core_hooks:
            print(f"{'core':11} {carrier:12} {cmd}")
        for it in items:
            print(f"{it['class']:11} {it['carrier']:12} {it['id']}")

    for cls in ("missing", "edited", "offmain", "shadow", "wrapper", "contradiction", "expired", "outside", "general", "noevidence",
                "badevidence", "duplicate", "undeclared"):
        xs = uniq(found[cls])
        if not xs:
            continue
        c = ""
        if cls == "undeclared":
            per = {}
            for it in items:
                if it["class"] == "undeclared":
                    per[it["carrier"]] = per.get(it["carrier"], 0) + 1
            c = " (" + ", ".join(f"{k} {v}" for k, v in per.items()) + ")"
            if not decl.get("identity_tokens"):
                c += " [no identity_tokens declared: general items cannot be told apart]"
        print(MESSAGES[cls].format(n=len(xs), x=short(xs), c=c))
    if any(found[c] for c in CLASSES) or C.unchecked:
        counts = " ".join(f"{c}={len(uniq(found[c]))}" for c in CLASSES)
        un = f" unchecked={','.join(C.unchecked)}" if C.unchecked else ""
        print(f"local machinery summary: items={len(items)} {counts}{un}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
