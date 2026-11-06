#!/usr/bin/env python3
"""Fixtures for real-data-replay.py — a tiny fake core with tagged reader versions over a fake brain.

Both directions per case: a reader whose classification changed between base and HEAD -> 1 with
the diff; the same output -> 0; a volatile counter that only the normaliser removes -> 0, and 1
without that regex (negative control); a symptom line that fails -> 1, one that holds -> 0;
no brain or a bad ref -> 2. The real brain copy rule: the fake brain is never written.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401  the fixture repo obeys no host git config or hooks

SCRIPT = os.environ.get("REAL_DATA_REPLAY_SCRIPT") or str(HERE / "real-data-replay.py")

# The fake reader: one line per ledger entry of the brain, its class decided by the version's rule,
# plus a volatile counter; it also writes a state file into the brain it reads (as open-items does).
READER = """import pathlib, sys
brain = pathlib.Path(sys.argv[1])
for line in (brain / "ledger.txt").read_text(encoding="utf-8").splitlines():
    exits = line.split("|")
    pick = exits[{pick}]
    print(f"- [ledger|{{'human' if pick == 'operator' else 'ai'}}] {{exits[0]}} (reported in {count} sessions)")
(brain / "state.json").write_text("{{}}", encoding="utf-8")
"""

pass_n = fail_n = 0


def check(name, ok, out=""):
    global pass_n, fail_n
    if ok:
        pass_n += 1
        print(f"PASS {name}")
    else:
        fail_n += 1
        print(f"FAIL {name}")
        for line in out.splitlines()[-20:]:
            print(f"      | {line}")


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def commit(repo, msg, tag=None):
    git(repo, "add", "-A")
    git(repo, "commit", "--quiet", "-m", msg)
    if tag:
        git(repo, "tag", tag)


def run(core, brain, readers, *extra):
    argv = [sys.executable, SCRIPT, "--core", str(core), "--readers", str(readers)]
    if brain is not None:
        argv += ["--brain", str(brain)]
    env = dict(os.environ)
    env.pop("RELEASE_REPLAY_BRAIN", None)
    p = subprocess.run(argv + list(extra), capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env)
    return p.returncode, p.stdout + p.stderr


def main():
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="rdr-test-")).resolve()
    core, brain = tmp / "core", tmp / "brain"
    core.mkdir()
    brain.mkdir()
    # entry: id | first exit | newest exit — the 2026-11-06 shape: several exits, the reader must pick one
    (brain / "ledger.txt").write_text("alpha|operator|ai-does-it\nbeta|ai-does-it|ai-does-it\n", encoding="utf-8")
    git(core, "init", "--quiet", "-b", "main")
    write = lambda pick, count: (core / "reader.py").write_text(READER.format(pick=pick, count=count), encoding="utf-8")
    write(1, 3)
    commit(core, "reader takes the first exit", "v1.0.0")      # the old, wrong reader
    write(-1, 3)
    commit(core, "reader takes the newest exit", "v1.1.0")     # the fix
    write(-1, 4)
    commit(core, "only the counter moved")                     # HEAD: volatile change only

    data = {"normalise": [r"\s*\(reported in \d+ sessions?\)"], "brain_copy_ignore": [".git"],
            "readers": [{"name": "fake-open-items", "argv": ["python3", "{core}/reader.py", "{brain}"]}]}
    readers = tmp / "readers.json"
    readers.write_text(json.dumps(data), encoding="utf-8")
    bare = dict(data, normalise=[])
    readers_bare = tmp / "readers-bare.json"
    readers_bare.write_text(json.dumps(bare), encoding="utf-8")

    # 1. classification changed between base and HEAD -> 1, the diff names both sides
    rc, out = run(core, brain, readers, "--base", "v1.0.0")
    check("changed classification -> rc 1 with the diff", rc == 1 and "-- [ledger|human] alpha" in out
          and "+- [ledger|ai] alpha" in out and "DIFFERS" in out, out)
    # 2. the same output -> 0 (base = the fix, HEAD only moved the counter, normalised away)
    rc, out = run(core, brain, readers, "--base", "v1.1.0")
    check("same classification, counter normalised -> rc 0", rc == 0 and "SAME" in out, out)
    # 3. negative control: without the normaliser the counter alone is a difference
    rc, out = run(core, brain, readers_bare, "--base", "v1.1.0")
    check("control: without the normaliser the volatile line differs -> rc 1", rc == 1 and "reported in 4" in out, out)
    # 4. the real brain is never written: the reader's state went into the copies only
    check("the brain itself stays untouched", not (brain / "state.json").exists())
    # 5. the base worktree is removed after the run
    wt = subprocess.run(["git", "-C", str(core), "worktree", "list"], capture_output=True, text=True).stdout
    check("the base worktree is removed after", len(wt.strip().splitlines()) == 1, wt)
    # 6. --head names a ref instead of the checkout: v1.0.0 vs v1.1.0 shows the fix
    rc, out = run(core, brain, readers, "--base", "v1.0.0", "--head", "v1.1.0")
    check("--head ref replays that ref", rc == 1 and "+- [ledger|ai] alpha" in out, out)

    # 7. symptom lines: a failing one is a finding, a holding one is not (no --base: symptoms only)
    (core / "changelog.d").mkdir()
    (core / "changelog.d" / "README.md").write_text("symptom: false-in-readme-is-no-fragment\n", encoding="utf-8")
    (core / "check.py").write_text("import pathlib,sys\nsys.exit(0 if 'beta' in pathlib.Path(sys.argv[1], 'ledger.txt').read_text() else 3)\n",
                                   encoding="utf-8")
    (core / "changelog.d" / "fix-a.md").write_text(
        "- **fix a.** (test: T1)\n  symptom: python3 {core}/check.py {brain}\n", encoding="utf-8")
    rc, out = run(core, brain, readers)
    check("a holding symptom -> rc 0, README not read", rc == 0 and "HOLDS" in out and "symptoms: 1 line" in out, out)
    (brain / "ledger.txt").write_text("alpha|operator|ai-does-it\n", encoding="utf-8")
    rc, out = run(core, brain, readers)
    check("a failing symptom is a finding -> rc 1", rc == 1 and "FAILS" in out and "rc=3" in out, out)
    # 8. after the release cut the fragment stands in the CHANGELOG section: --changelog-section reads it
    (core / "changelog.d" / "fix-a.md").unlink()
    (core / "CHANGELOG.md").write_text("# Changelog\n\n## 1.2.0 — 2026-11-06\n\n- **fix a.** (test: T1)\n"
                                       "  symptom: python3 {core}/check.py {brain} <!-- fragment: fix-a -->\n\n"
                                       "## 1.1.0\n\n- symptom: python3 -c \"import sys; sys.exit(9)\"\n", encoding="utf-8")
    # changelog-assemble.py appends the fragment marker to the fragment's LAST line: not part of the command
    rc, out = run(core, brain, readers, "--changelog-section", "1.2.0")
    check("--changelog-section reads only that section's symptoms", rc == 1 and "FAILS" in out
          and "symptoms: 1 line" in out and "sys.exit(9)" not in out, out)

    # 9. could not run -> 2
    rc, out = run(core, tmp / "no-such-brain", readers, "--base", "v1.0.0")
    check("missing brain -> rc 2", rc == 2 and "NOT run" in out, out)
    rc, out = run(core, None, readers, "--base", "v1.0.0")
    check("no brain given -> rc 2", rc == 2 and "NOT run" in out, out)
    rc, out = run(core, brain, readers, "--base", "v9.9.9")
    check("unknown base ref -> rc 2", rc == 2 and "NOT run" in out, out)

    subprocess.run(["git", "-C", str(core), "worktree", "prune"], capture_output=True)
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{pass_n}/{pass_n + fail_n} passed")
    return 0 if fail_n == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
