#!/usr/bin/env python3
"""Ecosystem lockfile — one file that says what this brain is currently made of.

WHY: with two people building suites in parallel, "something changed somewhere" is the
normal state. Per-repo changelogs record what changed INSIDE a repo; nothing recorded
which versions this brain is actually running. That is the gap this closes: one file,
one diff, every change at any end visible in the brain's own history.

  ecosystem-sync.py            report drift against config/ecosystem.json
  ecosystem-sync.py --write    record the current state as the new pinned state

Read-only by default, stdlib, no network — it reads local clones, not GitHub.
Exit 0 = in sync, 1 = drift (so it can gate a handover).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Two roots since the core/instance split: the CORE checkout carries this script and the
# contract; the INSTANCE (a private brain) carries the lockfile. Run from the instance
# root, or set BRAIN_DIR.
# Windows consoles default to cp1252; the em dash in the messages below lands there
# as "?" or throws UnicodeEncodeError. The files themselves are not affected (they
# write explicit utf-8), only the display — measured 2026-08-04.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

CORE = Path(__file__).resolve().parent.parent
BRAIN = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
LOCK = BRAIN / "config" / "ecosystem.json"
_contract_candidates = [CORE / "core-contract.json", BRAIN / "config" / "core-contract.json"]
CONTRACT = next((p for p in _contract_candidates if p.exists()), _contract_candidates[0])


def git(repo: Path, *args, default=""):
    try:
        r = subprocess.run(["git", "-C", str(repo), *args],
                           capture_output=True, text=True, timeout=30)
        return r.stdout.strip() if r.returncode == 0 else default
    except (OSError, subprocess.SubprocessError):
        return default


def observe(path: Path):
    """What is true about this repo right now."""
    # Only release tags count as a version. The brain also carries attic/* retrieval
    # points, and reporting one of those as "the version" is worse than reporting none.
    #
    # --merged HEAD is load-bearing (added 2026-08-04): without it the newest tag that
    # merely EXISTS locally is reported as the version, even when HEAD does not contain
    # it. Measured: a checkout at v1.1.3-8-g2f761c2 was recorded as "v1.1.5" because
    # v1.1.5 had been fetched. A version lie the drift check could never see, since it
    # compares its own wrong answer against itself.
    tags = [t for t in git(path, "tag", "--sort=-creatordate", "--merged", "HEAD").split()
            if re.match(r"^v\d", t)]
    # A brain keeps its manifest in config/ (CONVENTIONS section 9), a suite in the root.
    # Reading only the root made requires_core silently null for every brain.
    dj = next((p for p in (path / "dependencies.json", path / "config" / "dependencies.json")
               if p.exists()), path / "dependencies.json")
    requires = None
    if dj.exists():
        try:
            requires = json.loads(dj.read_text(encoding="utf-8")).get("requires_core")
        except json.JSONDecodeError:
            requires = "UNPARSEABLE"
    unpushed = git(path, "rev-list", "--count", "@{u}..HEAD", default="?")
    dirty = bool(git(path, "status", "--porcelain"))
    return {
        "commit": git(path, "rev-parse", "HEAD")[:12],
        "version": tags[0] if tags else None,
        "requires_core": requires,
        "remote": git(path, "remote", "get-url", "origin") or None,
        "unpushed": int(unpushed) if unpushed.isdigit() else unpushed,
        "dirty": dirty,
    }


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))


def observe_plugins():
    """Which plugins are installed for this user, at which version and commit.

    WHY (2026-08-04): plugins deliver skills, hooks and MCP servers — they are part of
    what this brain is made of, and until now the lockfile could not express that at all.
    They are not git checkouts (the cache holds no .git), so observe() cannot see them;
    the install registry is the only source of truth. A brain that records its core to
    the commit while saying nothing about a plugin that ships an MCP server has an
    inventory with a hole in it.
    """
    reg = config_dir() / "plugins" / "installed_plugins.json"
    if not reg.exists():
        return {}
    try:
        data = json.loads(reg.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    out = {}
    for name, installs in (data.get("plugins") or {}).items():
        if not installs:
            continue
        i = installs[0]
        out[name] = {"version": i.get("version"), "commit": (i.get("gitCommitSha") or "")[:12] or None}
    return out


def repo_slug(remote):
    """'git@github.com:owner/repo.git' / 'https://github.com/owner/repo' -> 'owner/repo'."""
    if not remote:
        return None
    m = re.search(r"github\.com[:/]+(.+?)(?:\.git)?/?$", remote)
    return m.group(1).lower() if m else None


def observe_marketplace_sources():
    """plugin-id -> 'owner/repo' for every plugin any locally cached marketplace lists.

    WHY (incident 2026-08-20, agent-brain PR #75 review): a bootup check needs to know
    WHICH suite repo a given installed plugin is delivered from, to tell a developer/PR
    checkout (legitimately behind) apart from the operator-facing consumer path (the
    plugin). A first attempt hand-wrote that link as a `plugin_name` annotation in the
    lockfile's plugins block — but nothing ever GENERATED it, so on every brain except
    the one it was typed into by hand, the link was silently absent and the check it
    was meant to feed never fired (presence without effect). The marketplace cache each
    installed marketplace already writes locally (`~/.claude/plugins/marketplaces/*/
    .claude-plugin/marketplace.json`) carries this link natively — plugin name to its
    source repo — so reading it here needs no network call and nothing new to maintain.
    """
    out = {}
    mdir = config_dir() / "plugins" / "marketplaces"
    if not mdir.is_dir():
        return out
    for mp in mdir.glob("*/.claude-plugin/marketplace.json"):
        try:
            data = json.loads(mp.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for p in data.get("plugins") or []:
            if not isinstance(p, dict):
                continue
            name, src = p.get("name"), p.get("source")
            # "source" varies across real marketplaces: a plain string (local plugin
            # path, no repo), {"source":"github","repo":"owner/repo"} (this brain's own
            # marketplace), or {"source":"url"/"git-subdir","url":"https://.../repo.git"}
            # (the official marketplace, no "repo" key at all) — only a dict can carry
            # repo identity, and it may need the same URL-to-slug parse as observe()'s
            # local `remote` reads.
            if not name or not isinstance(src, dict):
                continue
            slug = src.get("repo") or repo_slug(src.get("url"))
            if slug:
                out[name] = slug.lower()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="record current state as pinned")
    args = ap.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    core_now = json.loads(CONTRACT.read_text(encoding="utf-8"))["contract_version"]
    drift = []

    if lock.get("core_contract") != core_now:
        drift.append(f"core contract: pinned {lock.get('core_contract')} -> now {core_now}")
    lock["core_contract"] = core_now

    # Computed once, used below to stamp each repo entry with WHICH installed plugin (if
    # any) delivers it to the operator — see observe_marketplace_sources() docstring.
    now_plugins = observe_plugins()
    plugin_sources = observe_marketplace_sources()

    for name, entry in lock["repos"].items():
        path = Path(entry["path"]).expanduser()
        if not path.is_dir():
            drift.append(f"{name}: path missing ({entry['path']})")
            continue
        now = observe(path)
        # The lockfile lives inside the brain, so it can never contain the commit that
        # records it — writing it always produces a new one. Git history already tracks
        # this repo; comparing it here would report drift forever.
        keys = ("version", "requires_core") if path == BRAIN else ("commit", "version", "requires_core")
        if path == BRAIN:
            now["commit"] = "(this repo — see its own git history)"
        for key in keys:
            was = entry.get(key)
            if was != now[key]:
                drift.append(f"{name}: {key} {was} -> {now[key]}")
        if now["dirty"]:
            drift.append(f"{name}: uncommitted changes in the working tree")
        if isinstance(now["unpushed"], int) and now["unpushed"] > 0:
            drift.append(f"{name}: {now['unpushed']} commit(s) not pushed")
        entry.update({k: now[k] for k in ("commit", "version", "requires_core", "remote")})

        # consumer_plugin: identity data, not a version measurement (agrees with the
        # PR #75 review — it doesn't go stale the way a tag/commit does, so it is safe
        # to key a "skip this dev checkout" decision on). Matched by normalized github
        # remote, never by repo/plugin NAME (those legitimately differ, e.g.
        # "grandma3-suite" the repo vs "grandma3" the plugin id).
        slug = repo_slug(entry.get("remote"))
        match = next((pid for pid in now_plugins
                      if plugin_sources.get(pid.split("@", 1)[0]) == slug), None) if slug else None
        if match:
            entry["consumer_plugin"] = match
        else:
            entry.pop("consumer_plugin", None)

    # Plugins: same contract as repos — the script owns "version" and "commit", every
    # other key in an entry (notes, what it delivers) belongs to the instance and is
    # left alone.
    pinned_plugins = lock.setdefault("plugins", {})
    for name, now in now_plugins.items():
        entry = pinned_plugins.setdefault(name, {})
        for key in ("version", "commit"):
            if entry.get(key) != now[key]:
                drift.append(f"plugin {name}: {key} {entry.get(key)} -> {now[key]}")
        entry.update(now)
    for name in list(pinned_plugins):
        # Keys starting with "_" are instance annotations (notes, measurement dates),
        # not plugins — same convention as _comment/_role in the repos section.
        if not name.startswith("_") and name not in now_plugins:
            drift.append(f"plugin {name}: pinned but not installed")
    # Counted after the merge, so a first run reports what it recorded, not what it found.
    n_plugins = sum(1 for k in pinned_plugins if not k.startswith("_"))

    if args.write:
        # encoding is not optional here: without it Python uses the platform codepage,
        # and on Windows that writes cp1252 — the em dash below lands as 0x97 and the
        # lockfile stops being valid UTF-8 for every other reader (measured 2026-08-04).
        # newline is the same class, second instance: text mode translates "\n" to the
        # platform separator, so the same command produced CRLF on Windows and LF on
        # macOS (measured 2026-08-10: 65 CR lines in a freshly written ecosystem.json).
        LOCK.write_text(json.dumps(lock, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8", newline="\n")
        print(f"ecosystem: recorded {len(lock['repos'])} repos and "
              f"{n_plugins} plugins at core contract {core_now}")
        for name, e in lock["repos"].items():
            print(f"  {name:22s} {e.get('version') or '(untagged)':10s} {e.get('commit')}")
        for name, e in ((k, v) for k, v in (lock.get("plugins") or {}).items() if not k.startswith("_")):
            print(f"  {name:22s} {e.get('version') or '(none)':10s} {e.get('commit')}")
        return 0

    print(f"ecosystem: core contract {core_now}, {len(lock['repos'])} repos, "
          f"{n_plugins} plugins")
    if not drift:
        print("in sync — pinned state matches what is on disk")
        return 0
    print(f"\n{len(drift)} drift item(s):")
    for d in drift:
        print(f"  !! {d}")
    print("\nrecord it with --write once the state is intended.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
