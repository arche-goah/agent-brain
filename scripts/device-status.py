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
  device-status.py trailer [--topic <t>]    git trailer lines (Device-State, Suite-State) for a shared-memory
                                            commit — written by helpers/git-hooks/prepare-commit-msg

THIS device = first token of SHARED_MEMORY_SELF (the instance's settings `env`). Shared-memory repo =
SHARED_MEMORY_REPO, default ~/Projects/brain-shared-memory. People and devices come from `parties.json` at the
repo root: {"people": {"<person>": {"github": "...", "devices": {"<device>": {"os": "macos"|"windows"|"linux"|null}}}}}.

`report` writes only when something but the date changed, or when the last report is older than REFRESH_DAYS —
no commit noise, but a device that runs unchanged still shows it is alive. The file carries versions, commits, ids
and dates only: never a path (the repo is shared; leak discipline). Commit + push of that one file; a failed push
leaves the commit local and says so.
"""
import argparse, datetime, json, os, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plugin_records import own_record  # noqa: E402

# The session start parses this output; left to the platform, Windows' console code page
# mangles the dashes in these lines (os-traps OS-9).
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass

REFRESH_DAYS = 7          # rewrite an unchanged report after this long, so "age" stays meaningful
STALE_DAYS = 14           # --brief names a device whose last report is older
SILENT_DAYS = 7           # --brief names a device that works but posted nothing to shared memory for this long
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
    _, core_url = run(["git", "-C", core, "remote", "get-url", "origin"])
    core_repo = re.sub(r"\.git$", "", core_url.rstrip("/")).rsplit("/", 1)[-1]
    for pid in enabled:
        rec = installed.get(pid) or []
        name, _, mkt = pid.partition("@")
        pin = ""
        mp = load(os.path.join(cfg, "plugins", "marketplaces", mkt, ".claude-plugin", "marketplace.json"), {}) or {}
        for e in mp.get("plugins") or []:
            if e.get("name") == name:
                pin = (e.get("source") or {}).get("ref", "") if isinstance(e.get("source"), dict) else ""
                break
        own = own_record(rec, brain)
        installed_v = own.get("version", "") if own else ""
        plugins.append({"plugin": pid, "installed": installed_v, "pin": pin})
        # The suite this plugin ships: the marketplace names its repo. Its installed version is the
        # suite's LIVE version on this device (measured 2026-10-11 on a Windows brain: the record said
        # v1.1.20 while v1.1.29 ran — a record is written, a state is read).
        repo = ""
        for e in mp.get("plugins") or []:
            if e.get("name") == name and isinstance(e.get("source"), dict):
                repo = str(e["source"].get("repo") or "").rsplit("/", 1)[-1]
        # The core's own plugin is not a suite: the core has its block above (measured on the
        # Windows run: the core channel showed up under "suites").
        if repo and installed_v and repo != core_repo:
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
        "watch": {"standing": standing_watch(brain)},
    }


def last_post(repo, dev):
    """Date of the newest shared-memory entry this device wrote (`von: <dev>` in its frontmatter), or "".
    Operator order 2026-10-16: every AI reports findings on every level. Measured 2026-10-23: a device had posted
    nothing for a week, and from outside "no sessions ran" and "findings stayed unreported" looked the same —
    the report's own date says a session ran, this date says whether anything was reported."""
    best = ""
    for p in Path(repo).glob("*/*.md"):
        if p.name in ("INDEX.md", "OPEN.md", "LOG.md"):
            continue
        try:
            head = p.read_text(encoding="utf-8", errors="replace")[:1500]
        except OSError:
            continue
        von = re.search(r"^\s*von:\s*(\S+)", head, re.M)
        date = re.search(r"^\s*date:\s*(\d{4}-\d\d-\d\d)", head, re.M)
        if von and date and von.group(1) == dev and date.group(1) > best:
            best = date.group(1)
    return best


def standing_watch(brain):
    """Can this device keep the standing watch (watch-gate case (g))? Read from its collab-watch.json only — the
    report runs at session start, before any watch is armed, so "is one alive" is not measurable here.
    on | off: <why> | template (placeholders left) | not set up. Operator order 2026-10-16: every instance's watch
    state visible to the others (a machine without one answered nothing all day and nobody saw it)."""
    try:
        raw = Path(brain, ".claude", "rules", "collab-watch.json").read_text(encoding="utf-8")
    except OSError:
        return "not set up"
    if re.search(r"<[a-z][\w-]*>", re.sub(r'"_comment"\s*:\s*\[.*?\]\s*,?', "", raw, flags=re.S), re.I):
        return "template"
    try:
        v = json.loads(raw).get("standing_watch")
    except ValueError:
        return "not set up"
    v = v.strip() if isinstance(v, str) else ""
    if re.match(r"off\b", v, re.I):
        why = re.sub(r"^off\s*:?\s*", "", v, flags=re.I)
        return "off: " + why if why else "off (no reason)"
    return "on"


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
    state["activity"] = {"last_post": last_post(repo, dev)}
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


CORE_ROOT = os.environ.get("DEVICE_STATUS_CORE") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_TAG_COMMITS = {}


def tag_commit(tag):
    """The commit a tag names in THIS core checkout (short), or "" when unknown.

    WHY (measured 2026-10-18, after the history cut): two devices reported "v1.4.4" — one from the
    old history (7a801ae), one from the new (f713888). The table compared tag names only, so a brain
    still on the archived history looked current. A tag name is not an identity; its commit is."""
    if tag not in _TAG_COMMITS:
        ok = re.fullmatch(r"v\d+\.\d+\.\d+", tag or "")
        rc, sha = run(["git", "-C", CORE_ROOT, "rev-parse", "--short=12", f"refs/tags/{tag}^{{commit}}"]) if ok else (1, "")
        _TAG_COMMITS[tag] = sha if rc == 0 else ""
    return _TAG_COMMITS[tag]


def problems(row):
    r = row["report"]
    if not r:
        return ["never reported"]
    out = []
    core = r.get("core") or {}
    tag = core.get("tag", "")
    have, want = (core.get("commit") or "")[:12], tag_commit(tag)
    if have and want and not (have.startswith(want) or want.startswith(have)):
        out.append(f"core {tag} is commit {have[:7]}, not this core's {tag} ({want[:7]}) - old history or a local build")
    for p in r.get("plugins") or []:
        if not p["plugin"].startswith("brain-core"):
            continue
        if p.get("pin") and strip_v(tag) != strip_v(p["pin"]):
            out.append(f"core {tag} behind/off pin {p['pin']}")
        if p.get("installed") and strip_v(p["installed"]) != strip_v(tag):
            out.append(f"core {tag} vs plugin {p['installed']}")
    if core.get("local_edits"):
        out.append("core has local edits")
    sw = (r.get("watch") or {}).get("standing")
    if sw and sw != "on" and not sw.startswith("off: "):
        out.append(f"standing watch {sw}")
    age = days_since(r.get("reported"))
    if age is not None and age > STALE_DAYS:
        out.append(f"last report {age} d ago")
    act = r.get("activity")
    if isinstance(act, dict):  # older reports carry no activity block: nothing to judge
        lp, quiet = act.get("last_post") or "", None
        try:
            quiet = (datetime.date.fromisoformat(r["reported"]) - datetime.date.fromisoformat(lp)).days if lp else None
        except (KeyError, TypeError, ValueError):
            pass
        if not lp or (quiet is not None and quiet >= SILENT_DAYS):
            out.append(f"session on {r.get('reported')}, but no shared-memory entry " + (f"since {lp}" if lp else "ever"))
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


def trailer(args):
    """Git trailer lines that stamp a shared-memory commit with the sender's state.

    WHY (operator decision 2026-10-18): which core, channel and tool version a message was
    written on is what troubleshooting needs later — and after the history cut a tag name alone
    no longer tells two states apart. In the commit, not in the text: every AI would phrase a
    hand-written line differently, and the LOG lines are meant to stay short. Ids, versions and
    commits only — never a path, host name or address (the repo is shared)."""
    brain = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    dev = self_device(brain) or "?"
    try:
        st = gather(brain, cfg)
    except Exception:
        return 0
    repo = os.environ.get("SHARED_MEMORY_REPO") or shared_repo()
    osname = (parties(repo).get(dev) or (None, None))[1] or {"darwin": "macos", "win32": "windows"}.get(
        sys.platform, "linux")
    core = st["core"]
    chan = next((p["plugin"].split("@")[0] for p in st["plugins"] if p["plugin"].startswith("brain-core")), "-")
    _, ccv = run(["claude", "--version"])
    ccv = (ccv.split() or ["?"])[0]
    print(f"Device-State: device={dev} os={osname} core={core['tag']}@{core['commit'][:7]} channel={chan} cc={ccv}"
          + (" core-edits=yes" if core.get("local_edits") else ""))
    topic = (args.topic or "").strip().lower()
    if topic and topic != "core":
        hits = [f"{n}={s.get('version') or '?'}" + (f"@{s['commit'][:7]}" if s.get("commit") else "")
                for n, s in sorted(st["suites"].items()) if n == topic or n.startswith(topic + "-")]
        if hits:
            print("Suite-State: " + " ".join(hits))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", nargs="?", default="table", choices=("table", "report", "trailer"))
    ap.add_argument("--topic", help="trailer: the shared-memory topic (folder) of the commit; adds that suite's state")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--brief", action="store_true")
    ap.add_argument("--suites", action="store_true")
    ap.add_argument("--person"); ap.add_argument("--device"); ap.add_argument("--os")
    args = ap.parse_args()
    if args.cmd == "trailer":
        return trailer(args)
    return report(args) if args.cmd == "report" else table(args)


if __name__ == "__main__":
    sys.exit(main())
