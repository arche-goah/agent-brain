#!/usr/bin/env python3
"""covers: device-status

Both directions. The silent cases carry the weight: an unchanged report must not commit (the device file would
otherwise churn every session), and --brief must say nothing when every device is on its pin (a line every start
is a line nobody reads). Invented devices only; a temp git repo stands in for the shared memory.

Run: scripts/device-status-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "device-status.py"
fails = 0
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}


def check(cond: bool, msg: str) -> None:
    global fails
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        fails += 1


def git(*a: str, cwd: Path) -> str:
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True,
                          env={**os.environ, **GIT_ENV}).stdout.strip()


def write(p: Path, data) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(data if isinstance(data, str) else json.dumps(data), encoding="utf-8")


tmp = Path(tempfile.mkdtemp(prefix="device-status-"))
try:
    # shared memory: bare remote + clone, parties.json with one person on two devices (one os unknown) + one more
    bare = tmp / "remote.git"
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
    shared = tmp / "shared"
    subprocess.run(["git", "clone", "-q", str(bare), str(shared)], check=True, capture_output=True)
    write(shared / "parties.json", {"people": {
        "alpha": {"github": "alpha-gh", "devices": {"alpha-mac": {"os": "macos"}, "alpha-box": {"os": None}}},
        "beta": {"github": "beta-gh", "devices": {"beta-win": {"os": "windows"}}}}})
    git("add", "-A", cwd=shared); git("commit", "-q", "-m", "init", cwd=shared); git("push", "-q", cwd=shared)

    # brain with a core/ checkout on a tag, plugin config with an enabled channel, its install record and its pin
    brain = tmp / "brain"
    core = brain / "core"
    core.mkdir(parents=True)
    git("init", "-q", cwd=core)
    write(core / "f.txt", "x")
    git("add", "-A", cwd=core); git("commit", "-q", "-m", "c", cwd=core); git("tag", "v1.0.0", cwd=core)
    write(brain / ".claude" / "settings.json", {"enabledPlugins": {"brain-core@mkt": True, "other@mkt": False}})
    # the suite plugin is enabled only in the LOCAL layer (a beta channel on one machine)
    write(brain / ".claude" / "settings.local.json", {"enabledPlugins": {"a-plugin@mkt": True}})
    write(brain / "config" / "ecosystem.json", {"repos": {
        "a-suite": {"kind": "suite", "version": "v0.2.0", "commit": "abcdef1234567890", "path": "/secret/place"},
        "b-suite": {"kind": "suite", "version": "v0.9.0", "commit": "fedcba0987654321"},
        "own-project": {"kind": "project", "commit": "1234567"}}})
    cfg = tmp / "cfg"

    def channel(installed: str, pin: str) -> None:
        write(cfg / "plugins" / "installed_plugins.json",
              {"plugins": {"brain-core@mkt": [{"scope": "user", "version": installed, "installPath": str(tmp)}],
                           "a-plugin@mkt": [{"scope": "local", "version": "0.3.0", "installPath": str(tmp)}]}})
        write(cfg / "plugins" / "marketplaces" / "mkt" / ".claude-plugin" / "marketplace.json",
              {"plugins": [{"name": "brain-core", "source": {"source": "github", "repo": "o/r", "ref": pin}},
                           {"name": "a-plugin", "source": {"source": "github", "repo": "o/a-suite", "ref": "v0.3.0"}}]})

    env = {**os.environ, **GIT_ENV, "SHARED_MEMORY_REPO": str(shared), "SHARED_MEMORY_SELF": "alpha-mac,alpha",
           "CLAUDE_PROJECT_DIR": str(brain), "CLAUDE_CONFIG_DIR": str(cfg)}

    def ds(*a: str):
        p = subprocess.run([sys.executable, str(SCRIPT), *a], capture_output=True, text=True, env=env)
        return p.returncode, (p.stdout + p.stderr).strip()

    def commits() -> int:
        return int(git("rev-list", "--count", "HEAD", cwd=shared) or 0)

    print("report")
    channel("1.0.0", "v1.0.0")
    n0 = commits()
    rc, out = ds("report")
    devfile = shared / "devices" / "alpha-mac.json"
    check(rc == 0 and devfile.is_file() and commits() == n0 + 1, "first report writes and commits devices/alpha-mac.json")
    doc = json.loads(devfile.read_text(encoding="utf-8"))
    core_rec = next((p for p in doc["plugins"] if p["plugin"] == "brain-core@mkt"), {})
    check(doc["core"]["tag"] == "v1.0.0" and core_rec.get("pin") == "v1.0.0", "report carries core tag and pin")
    check("a-suite" in doc["suites"] and "own-project" not in doc["suites"], "suites recorded, own projects left out")
    check(doc["suites"]["a-suite"]["version"] == "v0.3.0" and doc["suites"]["a-suite"]["source"] == "plugin a-plugin@mkt",
          "a suite with an enabled plugin (settings.local.json layer) reports the plugin's installed version, not the record's")
    check(doc["suites"]["b-suite"]["version"] == "v0.9.0" and doc["suites"]["b-suite"]["source"] == "record",
          "NEGATIVE: a suite without a plugin keeps the record's version, marked as record")
    check(str(tmp) not in devfile.read_text(encoding="utf-8") and "/secret" not in devfile.read_text(encoding="utf-8"),
          "no path in the device file")
    check(git("rev-list", "--count", "HEAD", cwd=bare) == str(commits()), "report pushed")
    rc, out = ds("report")
    check(rc == 0 and commits() == n0 + 1 and "unchanged" in out, "NEGATIVE: unchanged state does not commit again")
    rc, out = ds("report", "--dry-run")
    check(commits() == n0 + 1, "NEGATIVE: --dry-run writes nothing")
    # a brain whose core/ is a copied folder, not a checkout of its own (a fixture brain run with the real
    # session env), has nothing to measure and must not overwrite the device file — two shapes: no repo
    # at all, and a folder inside some other repo
    before = devfile.read_text(encoding="utf-8")
    for fake in (tmp / "fakebrain", shared / "fakebrain"):
        write(fake / "core" / "x.txt", "x")
        p = subprocess.run([sys.executable, str(SCRIPT), "report"], capture_output=True, text=True,
                           env={**env, "CLAUDE_PROJECT_DIR": str(fake)})
        check(p.returncode == 0 and "not a git checkout" in p.stdout and commits() == n0 + 1
              and devfile.read_text(encoding="utf-8") == before,
              f"NEGATIVE: core/ without its own checkout ({fake.parent.name}) reports nothing, writes nothing")
    env.pop("SHARED_MEMORY_SELF")
    write(brain / ".claude" / "settings.json", {"enabledPlugins": {"brain-core@mkt": True, "other@mkt": False},
                                               "env": {"SHARED_MEMORY_SELF": "alpha-mac,alpha"}})
    rc, out = ds("report", "--dry-run")
    check("alpha-mac" in out and "not reported" not in out,
          "device id read from the brain's settings env when the env var is unset")

    print("brief")
    write(shared / "devices" / "alpha-box.json", {**doc, "device": "alpha-box"})
    write(shared / "devices" / "beta-win.json", {**doc, "device": "beta-win"})
    rc, out = ds("table", "--brief")
    check(rc == 0 and out == "", "NEGATIVE: every device on its pin -> --brief prints nothing")
    (shared / "devices" / "beta-win.json").unlink()
    rc, out = ds("--brief")
    check("never reported: beta-win" in out, "a device in parties.json without a report is named")
    channel("1.1.0", "v1.1.0")
    ds("report")
    rc, out = ds("--brief")
    check("alpha-mac" in out and "pin v1.1.0" in out, "core behind the pin is flagged")
    check("vs plugin 1.1.0" in out, "core vs plugin mismatch on the same device is flagged")
    write(core / "f.txt", "edited")
    ds("report")
    rc, out = ds("--brief")
    check("local edits" in out, "local edits in core/ are flagged")

    print("filters")
    rc, out = ds("--person", "alpha")
    check(rc == 0 and "alpha-mac" in out and "alpha-box" in out and "beta-win" not in out,
          "--person lists every device of that person, only those")
    rc, out = ds("--os", "macos")
    check("alpha-mac" in out and "alpha-box" not in out, "NEGATIVE: --os excludes a device whose os is unknown")
    rc, out = ds("--person", "gamma")
    check(rc != 0 and "unknown person" in out and "alpha" in out and "beta" in out,
          "unknown person errors and lists the known ones")
    rc, out = ds("--device", "nope")
    check(rc != 0 and "unknown device" in out, "unknown device errors")
    rc, out = ds("--device", "alpha-mac")
    check("suite  a-suite: v0.3.0" in out and "plugin brain-core@mkt" in out, "--device shows plugins and suites")
    check("suite  b-suite: v0.9.0" in out and "from the record, not measured" in out,
          "--device marks a suite version that comes from the record")
    rc, out = ds("--person", "alpha", "--os", "windows")
    check(rc == 0 and "alpha-mac" not in out, "filters combine")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print(f"device-status-test: {'all passed' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
