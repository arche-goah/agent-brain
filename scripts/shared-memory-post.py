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
  claim     a file `<area>/claim-<slug>-<date>.md` with `claims: <id>` (passed as --answers),
            written BEFORE the work and after a pull: the request leaves everyone else's list
            and stays on yours until you answer or close it. Refused when someone else
            already claimed it.

Every message carries `os:` and `core:` — the writing device's system and core version
(`core: unknown` when no core checkout is found, never left out).

Every message also gets one LOG line in the area (`## <date> · <von> — AN <to> (status: s):
<title>` plus the file path), so the conversation stream stays readable; the file carries the
state. Addressees are checked against parties.json, an `answers:` target against the repo;
a refusal writes nothing. It writes files and regenerates the index — committing and pushing
stay the caller's step.

Usage: shared-memory-post.py request|reply|note|claim --area AREA --to A[,B] --title TEXT
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
_device = import_module("device-status")

STATUS = {"request": "open", "reply": "answered", "note": "info", "claim": "info"}


def foreign_claims(repo: Path, target: str, me: set[str]) -> list[str]:
    """Who else already claimed `target` (a file stem or a LOG id) in the working tree."""
    out = []
    for p in repo.rglob("*.md"):
        if ".git" in p.parts:
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        if not text.startswith("---") or target not in text:
            continue
        head = text.split("\n---", 1)[0]
        von = (re.search(r"^\s+von:\s*(\S+)", head, re.M) or [None, "?"])[1]
        row = re.search(r"^\s+claims:(.*)$", head, re.M)
        if row and target in row.group(1) and von.lower() not in me:
            out.append(f"{von} ({p.relative_to(repo).as_posix()})")
    return out


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


# A check request goes to every machine of that OS (`os:<os>`), never to one device, unless exactly
# one machine can do it (README of the shared memory; docs/shared-memory-audience.md). Measured
# 2026-10-28 on the macOS instance: Windows checks for six core PRs went to one Windows device as
# part of replies; the other Windows instances never saw them and the PRs waited. Check words are
# English here; an instance adds its language in .claude/rules/shared-memory-post.json
# {"check_words": [regex, ...]}.
OS_NAMES = {"windows": r"\bwindows\b|\bwin(?:10|11)?\b", "macos": r"\bmac\s?os\b", "linux": r"\blinux\b"}
CHECK_WORDS = [r"\bcounter-?check", r"\bcheck(?:s|ed)? (?:it |them )?(?:on|at)\b", r"\bplease (?:run|check|verify|test)\b",
               r"\bverify (?:on|at)\b"]


def check_words():
    words = list(CHECK_WORDS)
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        import json
        words += (json.loads((Path(root) / ".claude" / "rules" / "shared-memory-post.json").read_text(encoding="utf-8"))
                  .get("check_words") or [])
    except (OSError, ValueError):
        pass
    return [re.compile(w, re.I) for w in words]


def os_check_misaddressed(text, to, one_machine):
    """The refusal text when `text` asks for a check on an OS whose `os:` category is not addressed."""
    if one_machine or not any(w.search(text) for w in check_words()):
        return ""
    wanted = [o for o, rx in OS_NAMES.items() if re.search(rx, text, re.I)]
    missing = [o for o in wanted if f"os:{o}" not in to and not any(t.startswith("all") for t in to)]
    if not missing:
        return ""
    return (f"this asks for a check on {', '.join(missing)} but is addressed to {', '.join(to)} - a check request "
            f"goes to {', '.join('os:' + o for o in missing)} (whoever comes first takes it); a check only one "
            "machine can do: --one-machine <reason>")


# A check request for a PR whose CI at the head is not green is a check that will be thrown away: the
# fix for the red CI moves the head, and the merge gate binds an OS OK to the head. Measured 2026-10-31
# on the macOS instance: 50 core PRs were checked on Windows while 23 of them were red at python-floor
# (a CI image, fixed by a PR that sat in the same queue); after the fix 28 heads were new and the
# Windows run was due again. The operator (translated): "the first check was useless from the start,
# and that could have been avoided". A PR labelled `ci-unblock` (it fixes the red CI for the others)
# may be asked for while others are red - its own CI still has to be green.
PR_REF = re.compile(r"(?<![\w/])(?:([\w.-]+/[\w.-]+))?#(\d+)\b")


def pr_repo_default() -> str:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        import json
        return (json.loads((Path(root) / ".claude" / "rules" / "shared-memory-post.json").read_text(encoding="utf-8"))
                .get("pr_repo") or "")
    except (OSError, ValueError):
        return ""


def ci_state(repo: str, n: str) -> str:
    """'green', 'red: <checks>', 'pending: <n>' or 'unread: <why>' for the CI at the PR's head."""
    import json
    gh = os.environ.get("SHARED_MEMORY_POST_GH", "gh")
    try:
        r = subprocess.run([gh, "pr", "view", n, "-R", repo, "--json", "statusCheckRollup"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"unread: {e}"
    if r.returncode != 0:
        return f"unread: {(r.stderr or r.stdout).strip()[:120]}"
    try:
        checks = json.loads(r.stdout).get("statusCheckRollup") or []
    except ValueError:
        return "unread: no JSON"
    if not checks:
        return "pending: no check has run yet"
    red = [c.get("name") or c.get("context") or "?" for c in checks
           if (c.get("conclusion") or c.get("state") or "").upper() in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT")]
    if red:
        return "red: " + ", ".join(red)
    running = [c for c in checks if (c.get("status") or "COMPLETED").upper() != "COMPLETED"
               or (c.get("state") or "").upper() == "PENDING"]
    if running:
        return f"pending: {len(running)} check(s) still running"
    return "green"


def os_check_not_ready(text: str) -> str:
    """The refusal text when `text` asks an OS check of a PR whose CI at the head is not green."""
    if not any(w.search(text) for w in check_words()) or not any(re.search(rx, text, re.I) for rx in OS_NAMES.values()):
        return ""
    default = pr_repo_default()
    bad = []
    for repo, n in dict.fromkeys(PR_REF.findall(text)):
        repo = repo or default
        if not repo:
            continue
        st = ci_state(repo, n)
        if st != "green":
            bad.append(f"{repo}#{n} ({st})")
    if not bad:
        return ""
    return ("the CI at the head is not green for " + "; ".join(bad) + " - a check now is thrown away when the fix moves "
            "the head; ask once the CI is green (a PR that fixes the red CI for the others: label it ci-unblock and "
            "ask for it alone), or say why it has to go now: --ci-not-green-ok <reason>")


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
    ap.add_argument("--one-machine", default="", help="a check that needs exactly this machine: the reason")
    ap.add_argument("--ci-not-green-ok", default="", help="an OS check request although the PR's CI is not green: why")
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
    if a.kind in ("reply", "claim") and not answers:
        return refuse(f"a {a.kind} names what it {'answers' if a.kind == 'reply' else 'takes'}: "
                      "--answers <file stem or LOG id>")
    targets = _lint.known_targets(a.repo) if answers else set()
    for x in answers:
        key = x if _parties.LOG_ID.fullmatch(x) else x.removesuffix(".md").rsplit("/", 1)[-1]
        if key not in targets:
            return refuse(f"--answers '{x}' names nothing in the repo")
        # A claim is taken BEFORE the work and after a pull: someone else's claim means the work
        # is theirs (docs/shared-memory-audience.md, Taking it).
        taken = foreign_claims(a.repo, key, {t.lower() for t in me}) if a.kind == "claim" else []
        if taken:
            return refuse(f"'{x}' is already claimed by {'; '.join(taken)} - the work is theirs")
    status = (a.status or STATUS[a.kind]).lower()
    if status not in _lint.VALID_STATUS:
        return refuse(f"status '{status}' is not in {sorted(_lint.VALID_STATUS)}")
    body = Path(a.body_file).read_text(encoding="utf-8") if a.body_file else a.body
    miss = os_check_misaddressed(a.title + "\n" + body, to, a.one_machine)
    if miss:
        return refuse(miss)
    if a.kind == "request" and not a.ci_not_green_ok:
        early = os_check_not_ready(a.title + "\n" + body)
        if early:
            return refuse(early)
    stem = f"{a.kind}-{slug(a.title)}-{a.date}"
    path = area_dir / f"{stem}.md"
    if path.exists():
        return refuse(f"{path.relative_to(a.repo).as_posix()} exists - change the title")

    q = '"' + a.title.replace("\\", "\\\\").replace('"', '\\"') + '"'
    # The writer's system and core version, written by the producer at write time (operator order
    # 2026-10-28; first asked 2026-10-18 and built then only as a commit trailer): activity per core
    # version is read from the entries (`device-status.py entries`). Same source as that trailer.
    os_name, core = _device.entry_origin()
    meta = ["  type: project", f"  von: {von}", f"  audience: {', '.join(to)}", f"  topic: {a.area}",
            f"  date: {a.date}", f"  os: {os_name}", f"  core: {core}", f"  status: {status}"]
    if status == "open":
        nxt = [d for d in (resolve_next(to, parties) if parties else to) if d != von.lower()]
        meta.append(f"  next: {', '.join(nxt)}")
    if answers:
        meta.append(f"  {'claims' if a.kind == 'claim' else 'answers'}: {', '.join(answers)}")
    if a.one_machine:
        meta.append(f"  one-machine: {a.one_machine}")
    if a.ci_not_green_ok:
        meta.append(f"  ci-not-green-ok: {a.ci_not_green_ok}")
    text = "---\n" + f"name: {stem}\ndescription: {q}\nmetadata:\n" + "\n".join(meta) + "\n---\n\n" + body.strip() + "\n"
    rel = path.relative_to(a.repo).as_posix()
    log = area_dir / "LOG.md"
    old = log.read_text(encoding="utf-8")
    # The lint reads the LOG line too: without the reason there it refused the commit of an entry whose file
    # carried --one-machine (measured three times on 2026-10-31, each LOG line fixed by hand).
    reason = f" · one-machine: {a.one_machine}" if a.one_machine else ""
    line = f"## {a.date} · {von} — AN {', '.join(to)} (status: {status}): {a.title}\n{rel}{reason}\n"
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
    # The exact paths the commit must carry. The index run rewrites `INDEX.md`, `<area>/INDEX.md`
    # and `<area>/OPEN.md` (and other areas' OPEN.md when an answer settles their request); a
    # caller committing by path (working rule #12) took only entry + LOG and left the generated
    # pages behind — three `pull --ff-only` blocked on one day (measured 2026-10-22). The list
    # comes from git, not from a guess about what the index writer touched.
    changed = changed_paths(a.repo)
    if changed:
        print("commit these paths (everything this run changed, index pages included):")
        for p in changed:
            print(f"  {p}")
        print(f"next: git -C {a.repo} add -- {' '.join(changed)} && commit && push")
    else:
        print("next: commit and push the shared-memory repo")
    return 0


def changed_paths(repo: Path) -> list[str]:
    """Paths `git status` reports as modified or untracked under the repo, sorted. Empty when
    the repo is no git checkout or git is missing — then the caller falls back to the old line."""
    try:
        r = subprocess.run(["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=all"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if r.returncode != 0:
        return []
    out = []
    for line in r.stdout.splitlines():
        if len(line) < 4:
            continue
        p = line[3:].strip()
        if " -> " in p:
            p = p.split(" -> ", 1)[1]
        if p.startswith('"') and p.endswith('"'):
            p = p[1:-1]
        out.append(p)
    return sorted(set(out))


if __name__ == "__main__":
    sys.exit(main())
