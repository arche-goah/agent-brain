#!/usr/bin/env python3
"""device-status.py — which device runs which core (and which suites).

Operator order 2026-10-11: "a clear function to see which device runs which core version" and "look up exactly
which versions a person's devices have". Measured motivation: a brain's core/ submodule sat on one tag while the
enabled plugin channel already pinned the next; nothing showed it, and other devices' versions lived only as prose
in the shared-memory repo.

  device-status.py report [--dry-run]       record THIS device into <shared-memory>/devices/<device>.json
  device-status.py [table] [filters]        one row per device: person, device, OS, core, channel, pin, behind, age
        --person <p> --device <id> --os <macos|windows|linux>   same categories as the audience syntax; combinable
        --suites                            add the suite and plugin versions each device recorded
        --brief                             one line with only what is off; nothing when all is fine

THIS device = first token of SHARED_MEMORY_SELF (the instance's settings `env`). Shared-memory repo =
SHARED_MEMORY_REPO, default ~/Projects/brain-shared-memory. People and devices come from `parties.json` at the
repo root: {"people": {"<person>": {"github": "...", "devices": {"<device>": {"os": "macos"|"windows"|"linux"|null}}}}}.

`report` writes only when something but the date changed, or when the last report is older than REFRESH_DAYS —
no commit noise, but a device that runs unchanged still shows it is alive. The file carries versions, commits, ids
and dates only: never a path (the repo is shared; leak discipline). Commit + push of that one file; a failed push
leaves the commit local and says so.
"""
import argparse, datetime, json, os, re, subprocess, sys

REFRESH_DAYS = 7          # rewrite an unchanged report after this long, so "age" stays meaningful
STALE_DAYS = 14           # --brief names a device whose last report is older
OS_VALUES = ("macos", "windows", "linux")


def run(cmd, cwd=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        return p.returncode, p.stdout.strip()
    except OSError:
        return 1, ""


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def shared_repo():
    return os.environ.get("SHARED_MEMORY_REPO") or os.path.join(os.path.expanduser("~"), "Projects", "brain-shared-memory")


def self_device(brain):
    """The env var when the harness set it (hooks, sessions); else the brain's own settings `env` — brain-update.sh
    runs from a plain shell where the harness env is absent."""
    raw = os.environ.get("SHARED_MEMORY_SELF", "")
    for name in ("settings.local.json", "settings.json"):
        if raw:
            break
        raw = ((load(os.path.join(brain, ".claude", name), {}) or {}).get("env") or {}).get("SHARED_MEMORY_SELF", "")
    toks = [t.strip() for t in raw.split(",") if t.strip()]
    return toks[0] if toks else ""


def strip_v(s):
    return (s or "")[1:] if (s or "").startswith("v") else (s or "")


# ---------- report ----------------------------------------------------------------------------------------------

def gather(brain, cfg):
    """This device's state, as data without paths."""
    core = os.path.join(brain, "core")
    _, tag = run(["git", "-C", core, "describe", "--tags", "--always"])
    _, commit = run(["git", "-C", core, "rev-parse", "--short=12", "HEAD"])
    rc, dirty = run(["git", "-C", core, "status", "--porcelain"])
    # All three layers Claude Code reads: a plugin enabled only in settings.local.json (a beta
    # channel switched on for one machine) was invisible here (measured 2026-10-11, macOS).
    settings = [load(os.path.join(brain, ".claude", "settings.local.json"), {}),
                load(os.path.join(brain, ".claude", "settings.json"), {}), load(os.path.join(cfg, "settings.json"), {})]
    enabled = []
    for s in settings:
        for k, v in (s.get("enabledPlugins") or {}).items():
            if v and k not in enabled:
                enabled.append(k)
    installed = (load(os.path.join(cfg, "plugins", "installed_plugins.json"), {}) or {}).get("plugins") or {}
    plugins = []
    live = {}  # suite repo name -> version of its enabled plugin on this device
    for pid in enabled:
        rec = installed.get(pid) or []
        name, _, mkt = pid.partition("@")
        pin = ""
        mp = load(os.path.join(cfg, "plugins", "marketplaces", mkt, ".claude-plugin", "marketplace.json"), {}) or {}
        for e in mp.get("plugins") or []:
            if e.get("name") == name:
                pin = (e.get("source") or {}).get("ref", "") if isinstance(e.get("source"), dict) else ""
                break
        installed_v = rec[0].get("version", "") if rec else ""
        plugins.append({"plugin": pid, "installed": installed_v, "pin": pin})
        # The suite this plugin ships: the marketplace names its repo. Its installed version is the
        # suite's LIVE version on this device (measured 2026-10-11 on a Windows brain: the record said
        # v1.1.20 while v1.1.29 ran — a record is written, a state is read).
        repo = ""
        for e in mp.get("plugins") or []:
            if e.get("name") == name and isinstance(e.get("source"), dict):
                repo = str(e["source"].get("repo") or "").rsplit("/", 1)[-1]
        if repo and installed_v:
            live[repo] = {"version": "v" + installed_v.lstrip("v"), "commit": "", "source": "plugin " + pid}
    eco = load(os.path.join(brain, "config", "ecosystem.json"), {}) or {}
    suites = {}
    # Shared tools only (kind suite/plugin): an instance or project repo is this operator's own work, not a version
    # the other devices need to match. A commit field that is not a sha (free text in the record) is dropped.
    # An enabled plugin of the suite wins over the record; a suite known only by its plugin is listed too.
    for name, r in sorted((eco.get("repos") or {}).items()):
        if isinstance(r, dict) and r.get("kind") in ("suite", "plugin"):
            sha = r.get("commit") or ""
            suites[name] = live.get(name) or {"version": r.get("version") or "",
                                               "commit": sha[:12] if re.fullmatch(r"[0-9a-f]{7,40}", sha) else "",
                                               "source": "record"}
    for name, v in live.items():
        suites.setdefault(name, v)
    return {
        "core": {"tag": tag, "commit": commit, "local_edits": bool(rc == 0 and dirty)},
        "plugins": plugins,
        "suites": suites,
    }


def report(args):
    brain = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    dev = self_device(brain)
    if not dev:
        print("device-status: not reported - SHARED_MEMORY_SELF unset (the instance's settings env names this device)")
        return 0
    repo = shared_repo()
    if not os.path.isdir(os.path.join(repo, ".git")):
        print("device-status: not reported - no shared-memory clone (" + os.path.basename(repo) + ")")
        return 0
    # A brain whose core/ is not a git checkout of its own has nothing to report — and a fixture
    # brain (copied helpers under a temp dir, run with the real session env) must never write the
    # operator's device file with its empty state (guard measured against portability-smoke).
    core = os.path.join(brain, "core")
    rc, top = run(["git", "-C", core, "rev-parse", "--show-toplevel"])
    if rc != 0 or os.path.realpath(top) != os.path.realpath(core):
        print("device-status: not reported - " + os.path.basename(brain) + "/core is not a git checkout (nothing to measure)")
        return 0
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    state = gather(brain, cfg)
    today = datetime.date.today().isoformat()
    path = os.path.join(repo, "devices", dev + ".json")
    old = load(path, {}) or {}
    old_state = {k: v for k, v in old.items() if k not in ("device", "reported")}
    age = days_since(old.get("reported"))
    if old_state == state and age is not None and age < REFRESH_DAYS:
        print(f"device-status: {dev} unchanged (reported {age} d ago) - nothing written")
        return 0
    doc = {"device": dev, "reported": today, **state}
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if args.dry_run:
        print(f"device-status: DRY RUN - would write devices/{dev}.json:")
        print(text, end="")
        return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    rel = "devices/" + dev + ".json"
    run(["git", "-C", repo, "add", "--", rel])
    rc, _ = run(["git", "-C", repo, "commit", "-q", "-m", f"devices: {dev} core {state['core']['tag']} ({dev})", "--", rel])
    if rc != 0:
        print(f"device-status: WARN wrote {rel} but could not commit it")
        return 0
    rc, _ = run(["git", "-C", repo, "pull", "-q", "--rebase"])
    rc2, _ = run(["git", "-C", repo, "push", "-q"]) if rc == 0 else (1, "")
    print(f"device-status: {dev} reported (core {state['core']['tag']})"
          + ("" if rc2 == 0 else " - WARN push failed, commit is local; push later"))
    return 0


# ---------- table -----------------------------------------------------------------------------------------------

def days_since(d):
    try:
        return (datetime.date.today() - datetime.date.fromisoformat(d)).days
    except (TypeError, ValueError):
        return None


def parties(repo):
    """device -> (person, os). Tiny local loader on purpose (the inbox carries its own resolver)."""
    out = {}
    for person, p in ((load(os.path.join(repo, "parties.json"), {}) or {}).get("people") or {}).items():
        for dev, d in (p.get("devices") or {}).items():
            out[dev] = (person, (d or {}).get("os"))
    return out


def rows(repo):
    devs = parties(repo)
    reports = {}
    ddir = os.path.join(repo, "devices")
    if os.path.isdir(ddir):
        for fn in sorted(os.listdir(ddir)):
            if fn.endswith(".json"):
                r = load(os.path.join(ddir, fn))
                if isinstance(r, dict) and r.get("device"):
                    reports[r["device"]] = r
    out = []
    for dev in sorted(set(devs) | set(reports)):
        person, osname = devs.get(dev, ("?", None))
        out.append({"device": dev, "person": person, "os": osname, "report": reports.get(dev)})
    return out


def problems(row):
    r = row["report"]
    if not r:
        return ["never reported"]
    out = []
    core = r.get("core") or {}
    tag = core.get("tag", "")
    for p in r.get("plugins") or []:
        if not p["plugin"].startswith("brain-core"):
            continue
        if p.get("pin") and strip_v(tag) != strip_v(p["pin"]):
            out.append(f"core {tag} behind/off pin {p['pin']}")
        if p.get("installed") and strip_v(p["installed"]) != strip_v(tag):
            out.append(f"core {tag} vs plugin {p['installed']}")
    if core.get("local_edits"):
        out.append("core has local edits")
    age = days_since(r.get("reported"))
    if age is not None and age > STALE_DAYS:
        out.append(f"last report {age} d ago")
    return out


def select(all_rows, args):
    known_people = sorted({r["person"] for r in all_rows if r["person"] != "?"})
    known_devs = sorted(r["device"] for r in all_rows)
    if args.person and args.person not in known_people:
        sys.exit(f"device-status: unknown person '{args.person}' - known: {', '.join(known_people) or 'none'}")
    if args.device and args.device not in known_devs:
        sys.exit(f"device-status: unknown device '{args.device}' - known: {', '.join(known_devs) or 'none'}")
    if args.os and args.os not in OS_VALUES:
        sys.exit(f"device-status: unknown os '{args.os}' - one of: {', '.join(OS_VALUES)}")
    return [r for r in all_rows
            if (not args.person or r["person"] == args.person)
            and (not args.device or r["device"] == args.device)
            and (not args.os or r["os"] == args.os)]


def table(args):
    repo = shared_repo()
    if not os.path.isdir(repo):
        if not args.brief:
            print("device-status: no shared-memory clone - nothing to show")
        return 0
    sel = select(rows(repo), args)
    if args.brief:
        never = [r["device"] for r in sel if not r["report"]]
        off = [f"{r['device']}: {'; '.join(problems(r))}" for r in sel if r["report"] and problems(r)]
        if never:
            off.append("never reported: " + ", ".join(never))
        if off:
            print("devices off the released state: " + " | ".join(off) + " - core/scripts/device-status.py")
        return 0
    head = ("person", "device", "os", "core", "channel", "plugin", "pin", "behind", "reported")
    lines = [head]
    for r in sel:
        rep = r["report"] or {}
        ch = next((p for p in rep.get("plugins") or [] if p["plugin"].startswith("brain-core")), {})
        age = days_since(rep.get("reported"))
        lines.append((r["person"], r["device"], r["os"] or "?", (rep.get("core") or {}).get("tag", "-"),
                      ch.get("plugin", "-").split("@")[0], ch.get("installed", "-") or "-", ch.get("pin", "-") or "-",
                      ("yes" if problems(r) else "no") if rep else "-",
                      f"{age} d ago" if age is not None else "never reported"))
    w = [max(len(str(l[i])) for l in lines) for i in range(len(head))]
    for l in lines:
        print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(l)).rstrip())
    if args.suites or args.device:
        for r in sel:
            rep = r["report"] or {}
            print(f"\n{r['device']}:")
            for p in rep.get("plugins") or []:
                print(f"  plugin {p['plugin']}: {p.get('installed') or '-'} (pin {p.get('pin') or '-'})")
            for name, s in sorted((rep.get("suites") or {}).items()):
                tag = " (from the record, not measured)" if s.get("source") == "record" else ""
                print(f"  suite  {name}: {s.get('version') or '-'} {s.get('commit') or ''}".rstrip() + tag)
            for prob in problems(r):
                print(f"  off: {prob}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", nargs="?", default="table", choices=("table", "report"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--brief", action="store_true")
    ap.add_argument("--suites", action="store_true")
    ap.add_argument("--person"); ap.add_argument("--device"); ap.add_argument("--os")
    args = ap.parse_args()
    return report(args) if args.cmd == "report" else table(args)


if __name__ == "__main__":
    sys.exit(main())
