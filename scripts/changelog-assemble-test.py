#!/usr/bin/env python3
"""Fixture for scripts/changelog-assemble.py — both directions, in throwaway repos.

Must: fragments land sorted under the new version header, old ## Unreleased entries come
along and the header goes, fragments are deleted, README.md stays, release-preflight's
leftover check is green afterwards. Must refuse: an existing version section, nothing to
release, a version with a leading v. Negative control: a no-op stub leaves the fragments.
Usage: python3 scripts/changelog-assemble-test.py (exit 0 = pass)
"""
import os
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
S = HERE / "changelog-assemble.py"
fails = 0
HEAD = "# Changelog\n\nintro\n\n"


def check(name, cond, detail=""):
    global fails
    print(f"  {'OK  ' if cond else 'FAIL'} {name}" + ("" if cond else f": {detail}"))
    if not cond:
        fails += 1


def repo(changelog, frags=None):
    d = pathlib.Path(tempfile.mkdtemp())
    (d / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
    (d / "changelog.d").mkdir()
    (d / "changelog.d" / "README.md").write_text("how to\n", encoding="utf-8")
    for name, body in (frags or {}).items():
        (d / "changelog.d" / name).write_text(body, encoding="utf-8")
    return d


def run(d, *args, script=S):
    r = subprocess.run([sys.executable, str(script), *args, "--root", str(d), "--date", "2026-10-12"],
                       capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout + r.stderr, (d / "CHANGELOG.md").read_text(encoding="utf-8")


old = "## 1.0.0 — 2026-01-01\n\n- old entry\n"
d = repo(HEAD + "## Unreleased\n\n- legacy entry\n\n" + old,
         {"b-second.md": "- **second.** (test: T1)\n", "a-first.md": "- **first.** (test: T0)\n"})
rc, out, text = run(d, "1.1.0")
check("exit 0 on a normal cut", rc == 0, out)
check("the new section has the version and date", "## 1.1.0 — 2026-10-12" in text, text)
i1, i2, il = text.find("**first.**"), text.find("**second.**"), text.find("legacy entry")
check("fragments sorted by name, then the old Unreleased entries", 0 < i1 < i2 < il, text)
check("## Unreleased is gone", "## Unreleased" not in text, text)
check("the released sections stay below", text.find("## 1.1.0") < text.find("## 1.0.0"), text)
left = sorted(p.name for p in (d / "changelog.d").iterdir())
check("fragments deleted, README kept", left == ["README.md"], left)

pre = HERE / "release-preflight.sh"
(d / ".claude-plugin").mkdir()
(d / ".claude-plugin" / "plugin.json").write_text('{"version":"1.1.0"}\n', encoding="utf-8")
r = subprocess.run(["bash", str(pre), "--ci-tag", "v1.1.0"], capture_output=True, text=True,
                   env={**os.environ, "RELEASE_PREFLIGHT_ROOT": d.as_posix()})
check("release-preflight is green after the cut", r.returncode == 0, r.stdout)

d = repo(HEAD + old, {"x.md": "- **x.** (test: T0)\n"})
rc, out, text = run(d, "1.1.0")
check("without ## Unreleased the section goes above the newest release",
      rc == 0 and text.find("## 1.1.0") < text.find("## 1.0.0") and text.startswith(HEAD), text)

d = repo(HEAD + old, {"x.md": "- x\n"})
rc, out, _ = run(d, "1.0.0")
check("refuses an existing version section", rc == 1 and "already" in out, out)
check("a refused cut keeps the fragment", (d / "changelog.d" / "x.md").exists())

d = repo(HEAD + "## Unreleased\n\n" + old)
rc, out, _ = run(d, "1.1.0")
check("refuses when there is nothing to release", rc == 1 and "nothing" in out, out)

rc, out, _ = run(d, "v1.1.0")
check("a leading v is a usage error", rc == 2, out)

d = repo(HEAD + old, {"x.md": "- x\n"})
rc, out, text = run(d, "1.1.0", "--dry-run")
check("--dry-run writes nothing", rc == 0 and "## 1.1.0" not in text and (d / "changelog.d" / "x.md").exists(), out)

stub = pathlib.Path(tempfile.mkdtemp()) / "stub.py"
stub.write_text("import sys\nsys.exit(0)\n", encoding="utf-8")
d = repo(HEAD + old, {"x.md": "- x\n"})
run(d, "1.1.0", script=stub)
check("a no-op stub leaves the fragment (control)", (d / "changelog.d" / "x.md").exists())

print("changelog-assemble: all checks passed" if not fails else f"changelog-assemble: {fails} FAILED")
sys.exit(1 if fails else 0)
