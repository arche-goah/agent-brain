#!/usr/bin/env python3
"""covers: shared-memory-parties shared-memory-inbox shared-memory-lint

Audience categories (operator order 2026-10-11): `audience` addresses a device, every device
of a person (`person:<p>`), or every device with an OS (`os:<os>`). Both directions per
category — who it reaches AND who it must not reach — plus the two lint findings and their
silent cases. Invented parties only:
  kim: kim-mac (macos), kim-pc (windows) · sam: sam-laptop (windows), sam-box (os unknown)
  lee: lee-tower (linux)

Run: scripts/shared-memory-audience-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))


def load(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


parties_mod = load("shared-memory-parties")
lint_mod = load("shared-memory-lint")
INBOX = ROOT / "scripts" / "shared-memory-inbox.py"

PARTIES = {"people": {
    "kim": {"github": "kim-gh", "devices": {"kim-mac": {"os": "macos"}, "kim-pc": {"os": "windows"}}},
    "sam": {"github": "sam-gh", "devices": {"sam-laptop": {"os": "windows"}, "sam-box": {"os": None}},
            "legacy_ids": ["sam-old"]},
    "lee": {"github": "lee-gh", "devices": {"lee-tower": {"os": "linux"}}},
}}
NEW, OLD = "2026-10-12", "2026-10-01"

fails = 0


def check(name: str, cond: bool) -> None:
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def entry(repo: Path, rel: str, von: str, audience: str, desc: str, date: str = NEW,
          body: str = "body") -> None:
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    # Bytes, not write_text(newline=): that argument is 3.10+, stock macOS python3 is 3.9 (OS-13).
    p.write_bytes((f'---\nname: {p.stem}\ndescription: "{desc}"\nmetadata:\n  type: project\n'
                   f"  von: {von}\n  audience: {audience}\n  topic: {rel.split('/')[0]}\n"
                   f"  date: {date}\n---\n\n{body}\n").encode("utf-8"))


def make_repo(tmp: Path, with_parties: bool = True) -> Path:
    repo = tmp / ("repo" if with_parties else "repo-plain")
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@local")
    git(repo, "config", "user.name", "T")
    git(repo, "config", "core.autocrlf", "false")
    if with_parties:
        (repo / "parties.json").write_text(json.dumps(PARTIES, indent=1), encoding="utf-8")
    (repo / "INDEX.md").write_text("# Index\n", encoding="utf-8")
    entry(repo, "core/request-os-win.md", "lee-tower", "os:windows", "OSWIN please run this")
    entry(repo, "core/request-person-kim.md", "lee-tower", "person:kim", "PERSONKIM a question")
    entry(repo, "core/request-device.md", "lee-tower", "kim-pc", "DEVICEONLY a question")
    (repo / "core" / "LOG.md").write_bytes(
        f"# Log\n\n## {NEW} · lee-tower — AN os:windows: LOGWIN a question\n\nno file\n".encode("utf-8"))
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "seed")
    return repo


def inbox(repo: Path, self_: str) -> str:
    r = subprocess.run([sys.executable, str(INBOX), "--open", "--repo", str(repo), "--to", "HEAD",
                        "--days", "100000", "--max", "100", "--self", self_],
                       capture_output=True, text=True, encoding="utf-8")
    return r.stdout


def main() -> int:
    P = PARTIES
    print("resolver")
    check("device -> id, person, os", parties_mod.categories("kim-pc", P) == {"kim-pc", "person:kim", "os:windows"})
    check("unknown os -> no os: category", parties_mod.categories("sam-box", P) == {"sam-box", "person:sam"})
    check("legacy id -> its person", "person:sam" in parties_mod.categories("sam-old", P))
    check("old SELF list expands", {"person:kim", "os:macos"} <= parties_mod.expand_self({"kim-mac", "kim", "kims"}, P))
    check("tokens keep categories whole", parties_mod.tokens("os:windows, person:kim, kim-pc") == {"os:windows", "person:kim", "kim-pc"})
    check("heading colon after a category", parties_mod.addressees("AN os:windows, kim-mac: title") == "os:windows, kim-mac")
    check("plain heading unchanged", parties_mod.addressees("AN kim-mac: title") == "kim-mac")

    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        repo = make_repo(tmp)
        print("inbox --open")
        pc, mac, laptop, box = (inbox(repo, s) for s in ("kim-pc,kim", "kim-mac,kim", "sam-laptop,sam", "sam-box,sam"))
        check("os:windows reaches a windows device of one person", "OSWIN" in pc)
        check("os:windows reaches a windows device of another person", "OSWIN" in laptop)
        check("os:windows does not reach a mac", "OSWIN" not in mac)
        check("os:windows does not reach an unknown-os device", "OSWIN" not in box)
        check("person:kim reaches both of kim's devices", "PERSONKIM" in pc and "PERSONKIM" in mac)
        check("person:kim does not reach sam", "PERSONKIM" not in laptop)
        check("a device id reaches only that device", "DEVICEONLY" in pc and "DEVICEONLY" not in mac)
        check("LOG heading to os:windows reaches windows", "LOGWIN" in pc and "LOGWIN" in laptop)
        check("LOG heading to os:windows skips the mac", "LOGWIN" not in mac)
        plain = make_repo(tmp, with_parties=False)
        check("negative control: without parties.json no category is resolved",
              "OSWIN" not in inbox(plain, "kim-pc,kim") and "DEVICEONLY" in inbox(plain, "kim-pc,kim"))

        print("lint")
        entry(repo, "core/fine-categories.md", "kim-mac", "os:windows, person:sam, kim-pc", "a note")
        entry(repo, "core/unknown-token.md", "kim-mac", "nobody-x", "a note")
        entry(repo, "core/old-unknown.md", "kim-mac", "nobody-y", "a note", date=OLD)
        entry(repo, "core/win-one.md", "kim-mac", "kim-pc", "please run the Windows check on PR 7")
        entry(repo, "core/win-os.md", "kim-mac", "os:windows", "please run the Windows check on PR 8")
        entry(repo, "core/win-why.md", "kim-mac", "sam-laptop", "Windows-Lauf bitte",
              body="one-machine: only this one has the dongle")
        entry(repo, "core/win-two.md", "kim-mac", "kim-pc, sam-laptop", "Windows test please")
        with (repo / "core" / "LOG.md").open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(f"\n## {NEW} · kim-mac — AN sam-laptop: Windows-Lauf bitte, PR 9\n\nx\n"
                     f"\n## {NEW} · kim-mac — AN os:windows: Windows run please\n\nx\n"
                     f"\n## {NEW} · kim-mac — AN Sam plus Kims AI: hello there\n\nx\n"
                     f"\n## {OLD} · kim-mac — AN kim-pc: Windows check old\n\nx\n")
        found = lint_mod.lint(repo)["findings"]["audience"]
        where = lambda s: [x for x in found if s in x["where"]]  # noqa: E731
        check("valid categories and devices: silent", not where("fine-categories"))
        check("unknown token: finding", any(x["issue"] == "audience token unknown" for x in where("unknown-token")))
        check("unknown token before the cut-off date: silent", not where("old-unknown"))
        check("Windows check to one windows device: finding", any("one machine" in x["issue"] for x in where("win-one")))
        check("Windows check to os:windows: silent", not where("win-os"))
        check("Windows check with one-machine reason: silent", not where("win-why"))
        check("Windows check to two windows devices: silent", not where("win-two"))
        check("LOG heading Windows check to one device: finding", any("PR 9" in x["where"] for x in found))
        check("LOG heading to os:windows: silent", not [x for x in found if "Windows run please" in x["where"]])
        check("LOG prose addressees: no token finding", not [x for x in found if "hello there" in x["where"]])
        check("LOG heading before the cut-off: silent", not [x for x in found if "check old" in x["where"]])
        check("negative control: no parties.json, no audience findings",
              not lint_mod.lint(plain)["findings"]["audience"])

    print(f"{'all green' if not fails else f'{fails} failing'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
