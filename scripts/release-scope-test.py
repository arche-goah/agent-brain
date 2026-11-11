#!/usr/bin/env python3
"""Fixtures for release-scope.py: the scope file's life (open, add, exclude, show, close) and the close gate `check`.

A temp brain (ledgers registered) and a temp core clone (bare origin + clone, isolated from the host's git config by
git_sandbox); gh is replaced by RELEASE_SCOPE_PR_FIXTURE. Every source of `check` is proven in both directions: an
own PR, an unshipped branch and an active shared ledger entry turn it red until added or excluded; a foreign PR, a
merged branch, a brain-only entry, a waiting entry and a done entry never count; an unreadable PR list, a missing key
and a wrong version are red.

    python3 scripts/release-scope-test.py
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: E402,F401  (importing isolates git config)
from instance_key import key_for  # noqa: E402

TOOL = HERE / "release-scope.py"
fails = 0
total = 0


def run(*args, cwd=None, env=None):
    return subprocess.run([str(a) for a in args], cwd=cwd, capture_output=True, text=True, env=env)


def git(cwd, *args):
    r = run("git", *args, cwd=cwd)
    assert r.returncode == 0, f"git {args}: {r.stderr}"
    return r.stdout


def check(name, cond, detail=""):
    global fails, total
    total += 1
    print(("  OK  " if cond else "  FAIL") + f" {name}" + ("" if cond else f" - {detail}"))
    fails += 0 if cond else 1


with tempfile.TemporaryDirectory() as tmp:
    t = Path(tmp)
    brain, clone, bare = t / "brain", t / "clone", t / "origin.git"
    (brain / ".claude" / "rules").mkdir(parents=True)
    (brain / "docs").mkdir()
    (brain / ".claude" / "rules" / "ledgers.json").write_text(json.dumps({"ledgers": ["docs/orders.md"]}), encoding="utf-8")
    (brain / "docs" / "orders.md").write_text(
        "# Orders\n\n"
        "- [ ] Shared work id: `shared-work`\n  - reach: shared\n  - exit: ai-does-it 2026-11-06\n\n"
        "- [ ] Core work in a PR id: `core-pr`\n  - reach: core\n  - exit: in-pr 2026-11-06 agent-brain#5\n\n"
        "- [ ] Brain only id: `brain-only` · reach: brain\n  - exit: ai-does-it 2026-11-06\n\n"
        "- [ ] Waits elsewhere id: `waits` · reach: shared\n  - exit: other-side 2026-11-06\n\n"
        "- [x] Done id: `done-one`\n  - reach: shared\n  - exit: ai-does-it 2026-11-06\n", encoding="utf-8")
    git(t, "init", "-q", "--bare", "-b", "main", bare)
    git(t, "clone", "-q", bare, clone)
    git(clone, "symbolic-ref", "HEAD", "refs/heads/main")  # an empty clone's branch name is the host's default
    (clone / "README").write_text("x\n", encoding="utf-8")
    git(clone, "add", "README")
    git(clone, "commit", "-q", "-m", "init")
    git(clone, "push", "-q", "origin", "HEAD:main")
    git(clone, "branch", "merged-already")                  # no commit beyond origin/main: shipped
    git(clone, "checkout", "-q", "-b", "feat/open-work")
    git(clone, "commit", "-q", "--allow-empty", "-m", "work")
    git(clone, "checkout", "-q", "main")

    key = key_for("fixture-self")
    prs = t / "prs.json"
    prs.write_text(json.dumps([
        {"number": 7, "headRefName": "feat/own-pr", "title": "own", "body": f"x\n<!-- instance-key: {key} -->"},
        {"number": 8, "headRefName": "feat/foreign", "title": "foreign", "body": "<!-- instance-key: 0123456789 -->"},
        {"number": 9, "headRefName": "feat/nokey", "title": "no key", "body": "written by hand"}]), encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "SHARED_MEMORY_SELF"}
    env.update(SHARED_MEMORY_SELF="fixture-self", RELEASE_SCOPE_PR_FIXTURE=str(prs))

    def scope(*args, e=None):
        return run(sys.executable, TOOL, *args, "--root", brain, env=e or env)

    def gate(*extra, e=None):
        return run(sys.executable, TOOL, "check", "--root", brain, "--core-clone", clone, *extra, env=e or env)

    r = scope("add", "x")
    check("add without an open scope is refused", r.returncode == 1 and "no open release scope" in r.stdout, r.stdout)
    r = gate()
    check("check without a scope is red", r.returncode == 1 and "no release scope" in r.stdout, r.stdout)

    r = scope("open", "2.1.4")
    state = json.loads((brain / ".claude-state" / "release-scope.json").read_text(encoding="utf-8"))
    check("open writes an open scope for the version", r.returncode == 0 and state["status"] == "open"
          and state["version"] == "2.1.4" and state["repo"] == "agent-brain", r.stdout)
    check("the state file is LF only", b"\r" not in (brain / ".claude-state" / "release-scope.json").read_bytes())
    check("open again, same version: no change", scope("open", "2.1.4").returncode == 0)
    r = scope("open", "2.1.5")
    check("open another version while one is open is refused", r.returncode == 1 and "close it first" in r.stdout,
          r.stdout)

    r = gate("--version", "2.1.4")
    out = r.stdout
    check("check is red with open items", r.returncode == 1, out)
    check("own PR named", "OPEN PR agent-brain#7" in out, out)
    check("a foreign or keyless PR is not ours", "#8" not in out and "#9" not in out, out)
    check("the unshipped branch named", "OPEN branch feat/open-work" in out, out)
    check("a branch whose commits are on origin/main is not named", "merged-already" not in out and
          "branch main" not in out, out)
    check("active shared and core ledger entries named", "OPEN ledger shared-work" in out
          and "OPEN ledger core-pr" in out, out)
    check("brain-only, waiting and done entries are not", "brain-only" not in out and "waits" not in out
          and "done-one" not in out, out)
    check("each finding says how to resolve it", "release-scope.py add feat/open-work" in out
          and "release-scope.py exclude feat/open-work" in out, out)

    check("a wrong version is red", "the scope is for 2.1.4, this release is 2.1.5"
          in gate("--version", "2.1.5").stdout)
    r = gate(e={**env, "RELEASE_SCOPE_PR_FIXTURE": str(t / "missing.json")})
    check("an unreadable PR list is red, not silent", r.returncode == 1 and "OPEN source open PRs" in r.stdout,
          r.stdout)
    nokey = {k: v for k, v in env.items() if k != "SHARED_MEMORY_SELF"}
    r = gate(e=nokey)
    check("no instance key is red (own PRs cannot be told apart)", r.returncode == 1
          and "SHARED_MEMORY_SELF unset" in r.stdout, r.stdout)
    (brain / ".claude" / "settings.json").write_text(json.dumps({"env": {"SHARED_MEMORY_SELF": "fixture-self"}}), encoding="utf-8")
    r = gate(e=nokey)
    check("the key from the brain's settings env counts", "SHARED_MEMORY_SELF unset" not in r.stdout
          and "agent-brain#7" in r.stdout, r.stdout)

    scope("add", "agent-brain#7", "shared-work")
    # Leaving an item out is the operator's call (2026-11-11: 21 PRs excluded by a script with a borrowed quote).
    r = scope("exclude", "feat/open-work", "experiment,", "not for this release")
    check("an exclusion without the operator's word is refused", r.returncode == 3
          and "operator's call" in r.stdout and "feat/open-work" not in scope("show").stdout, r.stdout)
    nodate = {**env, "RELEASE_SCOPE_EXCLUDE_OK": '"leave the experiment out"'}
    check("negative control: a quote without its date is refused", scope("exclude", "feat/open-work", "x", e=nodate).returncode == 3)
    ok = {**env, "RELEASE_SCOPE_EXCLUDE_OK": '"leave the experiment out" 2026-11-11'}
    r = scope("exclude", "feat/open-work", "experiment,", "not for this release", e=ok)
    check("exclude records its reason and the operator's word", r.returncode == 0 and "not for this release" in r.stdout
          and "leave the experiment out" in r.stdout, r.stdout)
    check("an exclusion without a reason is refused", scope("exclude", "core-pr", " ", e=ok).returncode == 2)
    r = gate()
    check("only the one item left is named", r.returncode == 1 and "core-pr" in r.stdout
          and "agent-brain#7" not in r.stdout and "feat/open-work" not in r.stdout
          and "shared-work" not in r.stdout, r.stdout)
    scope("add", "core-pr")
    r = gate("--version", "2.1.4")
    check("everything in scope or excluded: green", r.returncode == 0 and r.stdout.startswith("OK"), r.stdout)
    git(clone, "branch", "feat/own-pr")
    git(clone, "checkout", "-q", "feat/own-pr")
    git(clone, "commit", "-q", "--allow-empty", "-m", "pr work")
    git(clone, "checkout", "-q", "main")
    check("a PR in scope covers its branch", gate().returncode == 0)
    r = scope("show")
    check("show lists items and exclusions", "in   core-pr" in r.stdout
          and "out  feat/open-work - experiment, not for this release" in r.stdout, r.stdout)

    r = scope("close")
    state = json.loads((brain / ".claude-state" / "release-scope.json").read_text(encoding="utf-8"))
    check("close ends the scope", r.returncode == 0 and state["status"] == "closed")
    check("add after close is refused", scope("add", "y").returncode == 1)
    check("a new version opens after close", scope("open", "2.1.5").returncode == 0)

print(f"\n{total - fails}/{total} passed")
sys.exit(1 if fails else 0)
