#!/usr/bin/env python3
"""Fixture for scripts/shared-memory-post.py — both directions, sandbox only.
covers: scripts/shared-memory-post.py

Proves: a request becomes a file with its state written, the lint finds nothing in it and the
addressee's inbox lists it; a reply that names it (file stem or LOG id) settles it for the
inbox; every refusal writes nothing (unknown addressee, reply without --answers, an --answers
target that names nothing, SELF unset, a folder that is not an area).
Exit 0 = all pass.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
POST = HERE / "shared-memory-post.py"
INBOX = HERE / "shared-memory-inbox.py"
sys.path.insert(0, str(HERE))
from importlib import import_module  # noqa: E402
import git_sandbox  # noqa: E402,F401 - the host git config never reaches a fixture repo

sml = import_module("shared-memory-lint")
STATE = import_module("shared-memory-parties").STATE_SINCE
fails = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}" + ("" if cond else f": {detail}"))
    fails += 0 if cond else 1


def post(repo: Path, *args: str, me: str = "kim-pc") -> subprocess.CompletedProcess:
    env = {**os.environ, "SHARED_MEMORY_SELF": me}
    return subprocess.run([sys.executable, str(POST), *args, "--repo", str(repo), "--date", STATE],
                          capture_output=True, text=True, encoding="utf-8", env=env)


def inbox(repo: Path, me: str) -> str:
    for c in (["add", "-A"], ["commit", "-qm", "x"]):
        subprocess.run(["git", "-C", str(repo), *c], capture_output=True)
    return subprocess.run([sys.executable, str(INBOX), "--open", "--repo", str(repo), "--to", "HEAD",
                           "--days", "100000", "--self", me],
                          capture_output=True, text=True, encoding="utf-8").stdout


def files(repo: Path) -> set[str]:
    return {p.relative_to(repo).as_posix() for p in repo.rglob("*.md") if ".git" not in p.parts}


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        for c in (["init", "-q"], ["config", "user.email", "t@t"], ["config", "user.name", "t"],
                  ["config", "core.autocrlf", "false"]):
            subprocess.run(["git", "-C", str(repo), *c], capture_output=True)
        (repo / "core").mkdir()
        (repo / "core" / "LOG.md").write_text(
            f"# Log\n\n## {STATE} · kim-pc — AN alex-mac: a question in the stream\nno file\n", encoding="utf-8")
        (repo / "INDEX.md").write_text("# Index\n", encoding="utf-8")
        (repo / "parties.json").write_text(json.dumps({"people": {
            "kim": {"github": "k", "devices": {"kim-pc": {"os": "windows"}}},
            "alex": {"github": "a", "devices": {"alex-mac": {"os": "macos"}, "alex-win": {"os": "windows"}}}}}),
            encoding="utf-8")

        r = post(repo, "request", "--area", "core", "--to", "os:windows", "--title", "Check core #42 on Windows",
                 "--body", "Run the fixture at the head.")
        req = repo / "core" / f"request-check-core-42-on-windows-{STATE}.md"
        check("a request is written as a file", r.returncode == 0 and req.is_file(), r.stdout + r.stderr)
        text = req.read_text(encoding="utf-8") if req.is_file() else ""
        check("its state is written: status open, next = the Windows devices but the sender",
              "  status: open\n" in text and "  next: alex-win\n" in text, text)
        log = (repo / "core" / "LOG.md").read_text(encoding="utf-8")
        check("one LOG line points at the file",
              f"## {STATE} · kim-pc — AN os:windows (status: open): Check core #42 on Windows\ncore/{req.name}" in log, log)
        found = sml.lint(repo)["findings"]
        bad = [i for k in ("frontmatter", "fields", "relations", "audience", "name_mismatch", "topic_mismatch")
               for i in found[k] if req.name in json.dumps(i) or "Check core #42" in json.dumps(i)]
        check("the lint finds nothing in what the tool wrote", not bad, json.dumps(bad))
        check("the addressee's inbox lists the request", req.stem in inbox(repo, "alex-win"))

        r = post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "core 42 OK on Windows",
                 "--answers", req.stem, me="alex-win")
        check("a reply naming the file stem is written", r.returncode == 0, r.stdout + r.stderr)
        check("the reply settles the request for the inbox", req.stem not in inbox(repo, "alex-win"))

        lid = f"core/LOG@{STATE}#1"
        check("control: the LOG-only question is open with its id", lid in inbox(repo, "alex-mac"))
        r = post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "answer to the stream question",
                 "--answers", lid, me="alex-mac")
        check("a reply may name a LOG id", r.returncode == 0, r.stdout + r.stderr)
        check("the reply settles the LOG request", lid not in inbox(repo, "alex-mac"))
        ids = import_module("shared-memory-parties").log_ids_in(
            (repo / "core" / "LOG.md").read_text(encoding="utf-8"), "core")
        check("three senders on one day: every LOG id is unique", len(ids) == len(set(ids)) == 4, str(ids))

        before = files(repo)
        log_before = (repo / "core" / "LOG.md").read_text(encoding="utf-8")
        cases = [
            ("unknown addressee", post(repo, "request", "--area", "core", "--to", "nobody-box", "--title", "x")),
            ("reply without --answers", post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "y")),
            ("--answers naming nothing", post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "z",
                                              "--answers", "core/LOG@2026-01-01#7")),
            ("SELF unset", post(repo, "request", "--area", "core", "--to", "kim-pc", "--title", "w", me="")),
            ("a folder that is not an area", post(repo, "note", "--area", "nowhere", "--to", "kim-pc", "--title", "v")),
        ]
        for name, r in cases:
            check(f"refused: {name}", r.returncode == 2 and "REFUSED" in r.stdout, r.stdout + r.stderr)
        check("a refusal writes nothing",
              files(repo) == before and (repo / "core" / "LOG.md").read_text(encoding="utf-8") == log_before)
    print("shared-memory-post: all cases pass" if not fails else f"shared-memory-post: {fails} FAILURES")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
