#!/usr/bin/env python3
"""Write a message to another party into the shared memory — ONE way, with its state written.

WHY: a request that lived only as a LOG heading had no name an answer could carry, so every
reader rebuilt its state from words — whether a reply repeated the title, a `re <x>`, the
numbers (`shared-memory-inbox.py`, five fixes in nine days) — and keyed it by its first 40
characters (`open-items.py`, fifteen fixes in seven). Measured 2026-10-19: 21 of 23 requests
the start report listed as open were long answered; the answers just did not repeat the
words. The answerer KNOWS what it answers; this tool makes it write that down.

  request   a file `<area>/request-<slug>-<date>.md`, `status: open`, `next:` = the devices
            the addressees resolve to (parties.json). Its file stem is its id.
  reply     a file `<area>/reply-<slug>-<date>.md` with `answers: <id>` — a file stem, or a
            LOG id `<area>/LOG@<date>#<n>` as the inbox prints it. `status: answered`, or
            `--status open` for a counter-question (then `next:` goes back to the asker).
  note      a file `<area>/note-<slug>-<date>.md`, `status: info` — nothing is asked.

Every message also gets one LOG line in the area (`## <date> · <von> — AN <to> (status: s):
<title>` plus the file path), so the conversation stream stays readable; the file carries the
state. Addressees are checked against parties.json, an `answers:` target against the repo;
a refusal writes nothing. It writes files and regenerates the index — committing and pushing
stay the caller's step.

Usage: shared-memory-post.py request|reply|note --area AREA --to A[,B] --title TEXT
         [--body TEXT | --body-file PATH] [--answers ID[,ID]] [--status S] [--repo DIR]
         [--date YYYY-MM-DD]
Exit 0 = written, 2 = refused (nothing written).
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from importlib import import_module  # noqa: E402

_parties = import_module("shared-memory-parties")
_lint = import_module("shared-memory-lint")

STATUS = {"request": "open", "reply": "answered", "note": "info"}


def refuse(msg: str) -> int:
    print(f"shared-memory-post: REFUSED - {msg} (nothing written)")
    return 2


def slug(title: str) -> str:
    t = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:50].rstrip("-") or "message"


def resolve_next(to: list[str], parties: dict) -> list[str]:
    """The devices an addressee list reaches — what `next:` names."""
    devs = _parties.devices(parties)
    out = []
    for t in to:
        hit = sorted(d for d in devs if t in _parties.EVERYONE or t in _parties.categories(d, parties))
        out += [d for d in (hit or [t]) if d not in out]
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("kind", choices=sorted(STATUS))
    ap.add_argument("--area", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--body", default="")
    ap.add_argument("--body-file")
    ap.add_argument("--answers", default="")
    ap.add_argument("--status")
    ap.add_argument("--repo", type=Path, default=_lint.REPO_DEFAULT)
    ap.add_argument("--date", default=dt.date.today().isoformat())
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")

    me = [t for t in os.environ.get("SHARED_MEMORY_SELF", "").replace(",", " ").split() if t]
    if not me:
        return refuse("SHARED_MEMORY_SELF is not set - the sender must be this instance's device id")
    von = me[0]
    area_dir = a.repo / a.area
    if not (area_dir / "LOG.md").is_file():
        return refuse(f"'{a.area}' is not an area (a folder with a LOG.md)")
    parties = _parties.load(a.repo)
    to = [t.strip().lower() for t in a.to.split(",") if t.strip()]
    if parties:
        unknown = [t for t in to if t not in _parties.known(parties)]
        if unknown:
            return refuse(f"addressee(s) not in parties.json: {', '.join(unknown)}")
    answers = [x.strip() for x in a.answers.split(",") if x.strip()]
    if a.kind == "reply" and not answers:
        return refuse("a reply names what it answers: --answers <file stem or LOG id>")
    targets = _lint.known_targets(a.repo) if answers else set()
    for x in answers:
        key = x if _parties.LOG_ID.fullmatch(x) else x.removesuffix(".md").rsplit("/", 1)[-1]
        if key not in targets:
            return refuse(f"--answers '{x}' names nothing in the repo")
    status = (a.status or STATUS[a.kind]).lower()
    if status not in _lint.VALID_STATUS:
        return refuse(f"status '{status}' is not in {sorted(_lint.VALID_STATUS)}")
    body = Path(a.body_file).read_text(encoding="utf-8") if a.body_file else a.body
    stem = f"{a.kind}-{slug(a.title)}-{a.date}"
    path = area_dir / f"{stem}.md"
    if path.exists():
        return refuse(f"{path.relative_to(a.repo).as_posix()} exists - change the title")

    q = '"' + a.title.replace("\\", "\\\\").replace('"', '\\"') + '"'
    meta = ["  type: project", f"  von: {von}", f"  audience: {', '.join(to)}", f"  topic: {a.area}",
            f"  date: {a.date}", f"  status: {status}"]
    if status == "open":
        nxt = [d for d in (resolve_next(to, parties) if parties else to) if d != von.lower()]
        meta.append(f"  next: {', '.join(nxt)}")
    if answers:
        meta.append(f"  answers: {', '.join(answers)}")
    text = "---\n" + f"name: {stem}\ndescription: {q}\nmetadata:\n" + "\n".join(meta) + "\n---\n\n" + body.strip() + "\n"
    rel = path.relative_to(a.repo).as_posix()
    log = area_dir / "LOG.md"
    old = log.read_text(encoding="utf-8")
    line = f"## {a.date} · {von} — AN {', '.join(to)} (status: {status}): {a.title}\n{rel}\n"
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    with open(log, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(old.rstrip("\n") + "\n\n" + line)
    r = subprocess.run([sys.executable, str(HERE / "shared-memory-index.py"), "--repo", str(a.repo), "--write"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(f"written: {rel} (id: {stem})")
    print(f"LOG line: {log.relative_to(a.repo).as_posix()}")
    if r.returncode != 0:
        print(f"!! index NOT regenerated (rc={r.returncode}) - run scripts/shared-memory-index.py --write")
    print("next: commit and push the shared-memory repo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
