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
            "alex": {"github": "a", "devices": {"alex-mac": {"os": "macos"}, "alex-win": {"os": "windows"}}},
            # sam handed core and AI mechanics to kim's AIs: a Windows fan-out from kim skips sam-win
            "sam": {"github": "s", "devices": {"sam-win": {"os": "windows"}}, "ai_handover": {"to": "kim"}}}}),
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
        # The commit list names every path this run changed — entry, LOG and the generated index
        # pages — so a by-path commit cannot leave INDEX.md/OPEN.md behind (measured 2026-10-22:
        # three blocked `pull --ff-only` on one day from exactly that).
        listed = [l.strip() for l in r.stdout.splitlines() if l.startswith("  ")]
        check("the output lists the paths to commit: entry, LOG and the regenerated index pages",
              f"core/{req.name}" in listed and "core/LOG.md" in listed and "INDEX.md" in listed
              and "core/OPEN.md" in listed, r.stdout)
        check("the next line is one git add over exactly those paths",
              any(l.startswith("next: git -C ") and "core/OPEN.md" in l and "core/LOG.md" in l for l in r.stdout.splitlines()),
              r.stdout)
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
        # Claims: taken before the work; settled for the others, open for the claimer until answered.
        r = post(repo, "request", "--area", "core", "--to", "alex-mac,alex-win", "--title", "Measure the pin list")
        req2 = f"request-measure-the-pin-list-{STATE}"
        r = post(repo, "claim", "--area", "core", "--to", "kim-pc", "--title", "taking the pin list",
                 "--answers", req2, me="alex-win")
        check("a claim is written", r.returncode == 0, r.stdout + r.stderr)
        mine = inbox(repo, "alex-win")
        check("the claimer keeps it: 'claimed by you'", req2 in mine and "claimed by you" in mine, mine)
        check("the other addressee no longer sees it", req2 not in inbox(repo, "alex-mac"))
        r = post(repo, "claim", "--area", "core", "--to", "kim-pc", "--title", "me too",
                 "--answers", req2, me="alex-mac")
        check("refused: a second claim on a claimed request", r.returncode == 2 and "already claimed" in r.stdout,
              r.stdout + r.stderr)
        (repo / "core" / "claim-crossed.md").write_text(
            f"---\nname: claim-crossed\ndescription: \"crossed\"\nmetadata:\n  type: project\n  von: alex-mac\n"
            f"  audience: kim-pc\n  topic: core\n  date: {STATE}\n  claims: {req2}\n---\n\nx\n", encoding="utf-8")
        check("two crossed claims show on the claimer's list", "ALSO claimed by alex-mac" in inbox(repo, "alex-win"))
        (repo / "core" / "claim-crossed.md").unlink()
        r = post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "pin list measured",
                 "--answers", req2, me="alex-win")
        check("the claimer's answer settles it for the claimer too", req2 not in inbox(repo, "alex-win"))

        ids = import_module("shared-memory-parties").log_ids_in(
            (repo / "core" / "LOG.md").read_text(encoding="utf-8"), "core")
        check("several senders on one day: every LOG id is unique", len(ids) == len(set(ids)) > 3, str(ids))

        before = files(repo)
        log_before = (repo / "core" / "LOG.md").read_text(encoding="utf-8")
        cases = [
            ("unknown addressee", post(repo, "request", "--area", "core", "--to", "nobody-box", "--title", "x")),
            ("reply without --answers", post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "y")),
            ("--answers naming nothing", post(repo, "reply", "--area", "core", "--to", "kim-pc", "--title", "z",
                                              "--answers", "core/LOG@2026-01-01#7")),
            ("SELF unset", post(repo, "request", "--area", "core", "--to", "kim-pc", "--title", "w", me="")),
            ("a folder that is not an area", post(repo, "note", "--area", "nowhere", "--to", "kim-pc", "--title", "v")),
            # 2026-10-28: a Windows check sent to one device never reached the other Windows instances
            ("a Windows check addressed to one device",
             post(repo, "request", "--area", "core", "--to", "alex-win", "--title", "u",
                  "--body", "Please counter-check #7 on Windows at the head.", me="alex-mac")),
            # 2026-10-29: a core check went by name to a party that handed core mechanics to the sender's side
            ("a core request to a party that handed core mechanics over",
             post(repo, "request", "--area", "core", "--to", "sam-win", "--title", "t")),
            ("the same by person", post(repo, "request", "--area", "core", "--to", "person:sam", "--title", "s")),
        ]
        for name, r in cases:
            check(f"refused: {name}", r.returncode == 2 and "REFUSED" in r.stdout, r.stdout + r.stderr)
        check("a refusal writes nothing",
              files(repo) == before and (repo / "core" / "LOG.md").read_text(encoding="utf-8") == log_before)
        r = post(repo, "request", "--area", "core", "--to", "alex-win", "--title", "One machine check",
                 "--body", "Please counter-check on Windows: only this box has the device.",
                 "--one-machine", "the USB device sits at this box", me="alex-mac")
        one = repo / "core" / f"request-one-machine-check-{STATE}.md"
        check("a check for exactly one machine passes with --one-machine, and the reason is written",
              r.returncode == 0 and one.is_file() and "one-machine: the USB device" in one.read_text(encoding="utf-8"),
              r.stdout + r.stderr)
        r = post(repo, "note", "--area", "core", "--to", "alex-win", "--title", "Windows box moved",
                 "--body", "The Windows box now stands in room 2.", me="alex-mac")
        check("control: a note that only names Windows (no check asked) passes", r.returncode == 0, r.stdout + r.stderr)
        r = post(repo, "note", "--area", "core", "--to", "sam-win", "--title", "Core 2.1 is out")
        check("control: a note to the handing-over party passes", r.returncode == 0, r.stdout + r.stderr)
        r = post(repo, "request", "--area", "core", "--to", "sam-win", "--title", "Confirm the USB prompt",
                 "--body", "handover-keeps: a dialog only the person at that box can confirm")
        check("control: a request the handover keeps passes with handover-keeps", r.returncode == 0, r.stdout + r.stderr)
        r = post(repo, "request", "--area", "core", "--to", "os:windows", "--title", "Run lint at head", me="alex-mac")
        nxt = (repo / "core" / f"request-run-lint-at-head-{STATE}.md").read_text(encoding="utf-8")
        check("control: from a sender the handover does not name, the fan-out still reaches sam-win",
              "sam-win" in nxt and "kim-pc" in nxt, nxt)
    print("shared-memory-post: all cases pass" if not fails else f"shared-memory-post: {fails} FAILURES")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
