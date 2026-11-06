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
HANDOVER_AREAS = ("core", "ops")   # core and AI mechanics, what touches several brains


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


def resolve_next(to: list[str], parties: dict, text: str = "") -> list[str]:
    """The devices an addressee list reaches — what `next:` names. A category address leaves out the
    devices of a person who cannot see a repo the text names; a device named by itself stays."""
    devs = _parties.devices(parties)
    out = []
    for t in to:
        hit = sorted(d for d in devs if (t in _parties.EVERYONE or t in _parties.categories(d, parties))
                     and not _parties.without_access(d, text, parties))
        out += [d for d in (hit or [t]) if d not in out]
    return out


# A check request goes to every machine of that OS (`os:<os>`), never to one device, unless exactly
# one machine can do it (README of the shared memory; docs/shared-memory-audience.md). Measured
# 2026-10-28 on the macOS instance: Windows checks for six core PRs went to one Windows device as
# part of replies; the other Windows instances never saw them and the PRs waited. Check words are
# English here; an instance adds its language in .claude/rules/shared-memory-post.json
# {"check_words": [regex, ...]}.
OS_NAMES = {"windows": r"\bwindows\b|\bwin(?:10|11)?\b", "macos": r"\bmac\s?os\b", "linux": r"\blinux\b"}
CHECK_WORDS = [r"\bcounter-?check", r"\bchecks? (?:it |them )?(?:on|at)\b", r"\bplease (?:run|check|verify|test)\b",
               r"\bverify (?:on|at)\b"]

# The unit a check word rules is its SENTENCE, not the whole text (2026-11-04, four refusals of correct requests
# on the macOS instance in one day): "checked on macOS: 7/7" in the evidence was read as a macOS request, "#402
# fixes the red CI" bound the CI check to a PR nobody asked for, and "#233, #234" next to a grandma3-suite URL
# were read as core PRs. Now an OS counts as asked only in the sentence with the check word, a PR number binds the
# CI check only there, a bare #n in a sentence that names ONE repo (owner/repo#n or a PR URL) belongs to that
# repo, and "checked" (a report) is no check word.
SENTENCE = re.compile(r"(?<=[.!?])\s+|\n+")
PR_URL = re.compile(r"https?://github\.com/([\w.-]+/[\w.-]+)/pull/(\d+)\b")


def check_sentences(text):
    """The sentences of `text` that carry a check word."""
    words = check_words()
    return [s for s in SENTENCE.split(text) if s and any(w.search(s) for w in words)]


def asked_os(sentences):
    """The OS names the check sentences mention."""
    return [o for o, rx in OS_NAMES.items() if any(re.search(rx, s, re.I) for s in sentences)]


def asked_prs(sentences, default):
    """(repo, number) pairs the check sentences name: owner/repo#n, a PR URL, or a bare #n bound to the one repo
    the sentence names, else to `default`."""
    out = []
    for s in sentences:
        urls = PR_URL.findall(s)
        refs = PR_REF.findall(s)
        named = {r for r, _ in urls} | {r for r, _ in refs if r}
        bind = next(iter(named)) if len(named) == 1 else default
        # `<repo> #n` - the repo's short name, a space, the number - binds to THAT repo when the name is one of
        # the repos in play (a named slug, or the default). Measured 2026-11-06 on the macOS instance: "agent-brain
        # #407" next to a chataigne-suite PR URL was read as chataigne-suite#407 and the request refused.
        short = {slug.rsplit("/", 1)[-1].lower(): slug for slug in named | ({default} if default else set())}
        for m in re.finditer(r"(?<![\w/.-])([\w.-]+)\s+#(\d+)\b", s):
            if m.group(1).lower() in short:
                out.append((short[m.group(1).lower()], m.group(2)))
                refs = [(r, n) for r, n in refs if r or n != m.group(2)]
        out += urls + [(r or bind, n) for r, n in refs]
    return [p for p in dict.fromkeys(out) if p[0]]


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


# A --one-machine reason that only names the OS ("the Windows instance is the machine that does it", "a Windows
# check at the PR head; ...") is the os:<os> case in other words, not a reason. Measured 2026-11-03 on the macOS
# instance: five requests in the shared memory carried such a reason, the last two went to a Windows device that
# was not running while the other Windows machines never saw them.
HOLLOW_ONE_MACHINE = re.compile(
    r"\b(?:the|a|an)\s+(?:windows|macos|mac|linux)\s+(?:instance|machine|device|computer|box)\b"
    r"|^\s*an?\s+(?:windows|macos|mac|linux)\s+check\b", re.I)


def one_machine_unproven(one_machine, evidence, repo):
    """The refusal text when a --one-machine request carries no evidence a reader can open. The operator (2026-11-03,
    translated): "an explicit request to one instance must be clearly reasoned and evidenced, otherwise it must not go
    through". Evidence is a URL, a file that exists (path[:line], relative to the shared memory or the working
    directory), or the operator's quoted words with their date."""
    if not one_machine:
        return ""
    e = (evidence or "").strip()
    if not e:
        return ("--one-machine needs --one-machine-evidence: a URL, a file path[:line] that exists, or the operator's "
                "quoted words with their date - a reason without evidence does not address one machine")
    if re.match(r"https?://\S+$", e):
        return ""
    p = re.sub(r":\d+$", "", e)
    if (Path(repo) / p).is_file() or Path(p).is_file():
        return ""
    if re.search(r"[\"„“'«].{3,}[\"“”'»]", e) and re.search(r"\b20\d\d-\d\d-\d\d\b", e):
        return ""
    return (f"--one-machine-evidence \"{e}\" is no evidence a reader can open: give a URL, an existing file "
            "path[:line], or the operator's quoted words with their date")


def os_check_misaddressed(text, to, one_machine):
    """The refusal text when `text` asks for a check on an OS whose `os:` category is not addressed."""
    if one_machine and HOLLOW_ONE_MACHINE.search(one_machine):
        return (f"--one-machine \"{one_machine}\" names only the OS - any machine of that OS fits it, so the request "
                "goes to os:<os>; a one-machine reason names what only that machine has (a desk, a device, a file)")
    if one_machine:
        return ""
    wanted = asked_os(check_sentences(text))
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


def ci_proof_repos() -> set:
    """Repos whose single PRs need no OS hand check: a green CI job is the OS proof for their merge, and a hand check
    happens at most once per OS at a merge train's head. Instance data `ci_counts_as_os_check` in
    .claude/rules/os-proof.json ({"<owner/repo>": [<OS>, ...]}) — the same file merge-request-gate reads, one place."""
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        import json
        d = json.loads((Path(root) / ".claude" / "rules" / "os-proof.json").read_text(encoding="utf-8"))
        m = d.get("ci_counts_as_os_check") or {}
        return {str(r).lower() for r, oses in m.items() if oses} if isinstance(m, dict) else set()
    except (OSError, ValueError, AttributeError):
        return set()


def is_train(repo: str, n: str) -> bool:
    """True when the PR's head branch is a merge train (train/...); False when not or unreadable."""
    import json
    gh = os.environ.get("SHARED_MEMORY_POST_GH", "gh")
    try:
        r = subprocess.run([gh, "pr", "view", n, "-R", repo, "--json", "headRefName"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        return r.returncode == 0 and str(json.loads(r.stdout).get("headRefName") or "").startswith("train/")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return False


def os_check_not_needed(text: str) -> str:
    """The refusal text when `text` asks an OS hand check of a single PR in a repo whose merge takes the CI as OS proof.
    Measured 2026-11-06 on the macOS instance: three per-PR Windows checks went out for core PRs that a merge train
    covers by its CI; the operator's rule (one check per OS at the train head, nothing twice) lived in prose only."""
    repos = ci_proof_repos()
    asked = check_sentences(text)
    if not repos or not asked or not asked_os(asked):
        return ""
    single = [f"{repo}#{n}" for repo, n in asked_prs(asked, pr_repo_default())
              if repo.lower() in repos and not is_train(repo, n)]
    if not single:
        return ""
    return ("an OS hand check is asked for single PR(s) " + ", ".join(single) + " - in this repo a green CI job is the OS "
            "proof for a merge, and a hand check happens at most once per OS at a merge train's head (build the train, ask "
            "for its PR), or say why this single PR needs a hand check: --hand-check-ok <reason>")


def os_check_not_ready(text: str) -> str:
    """The refusal text when `text` asks an OS check of a PR whose CI at the head is not green."""
    asked = check_sentences(text)
    if not asked or not asked_os(asked):
        return ""
    bad = []
    for repo, n in asked_prs(asked, pr_repo_default()):
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
    ap.add_argument("--one-machine-evidence", default="",
                    help="evidence for --one-machine: URL, existing file path[:line], or the operator's quoted words with date")
    ap.add_argument("--ci-not-green-ok", default="", help="an OS check request although the PR's CI is not green: why")
    ap.add_argument("--hand-check-ok", default="",
                    help="an OS hand check for a single PR in a repo whose merge takes the CI as OS proof: why")
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
    miss = os_check_misaddressed(a.title + "\n" + body, to, a.one_machine) \
        or (a.kind == "request" and one_machine_unproven(a.one_machine, a.one_machine_evidence, a.repo))
    if miss:
        return refuse(miss)
    if a.kind == "request" and not a.hand_check_ok:
        needless = os_check_not_needed(a.title + "\n" + body)
        if needless:
            return refuse(needless)
    if a.kind == "request" and not a.ci_not_green_ok:
        early = os_check_not_ready(a.title + "\n" + body)
        if early:
            return refuse(early)
    # A request about core or AI mechanics never goes to a party that handed those questions to the
    # sender's AIs (parties.json `ai_handover`; Working Across Parties #6 (c)). Measured 2026-10-29 on
    # the macOS instance: a Windows check of a core CI change went by name to such a device; nothing
    # here read the handover. `handover-keeps: <why>` in the text marks what the handover keeps.
    handed = _parties.handed_to_me(von, parties) if parties and a.kind == "request" and a.area in HANDOVER_AREAS else set()
    if handed and not _parties.HANDOVER_KEEPS.search(a.title + "\n" + body):
        named = [t for t in to if t in handed or (t.startswith("person:") and
                 any(_parties.devices(parties)[d][0] == t[7:] for d in handed))]
        if named:
            return refuse(f"{', '.join(named)} handed core and AI mechanics to your side (ai_handover) - "
                          f"decide it yourselves, or mark what the handover keeps: handover-keeps: <why>")
    stem = f"{a.kind}-{slug(a.title)}-{a.date}"
    path = area_dir / f"{stem}.md"
    if path.exists():
        return refuse(f"{path.relative_to(a.repo).as_posix()} exists - change the title")
    rel = path.relative_to(a.repo).as_posix()
    # The lint reads the LOG line too: without the reason there it refused the commit of an entry whose file
    # carried --one-machine (measured three times on 2026-10-31, each LOG line fixed by hand).
    reason = f" · one-machine: {a.one_machine}" if a.one_machine else ""
    line = f"## {a.date} · {von} — AN {', '.join(to)} (status: {status}): {a.title}\n{rel}{reason}\n"
    # This tool writes the LOG line, so this tool keeps it under the entry cap the lint judges (6c, from
    # LOG_CAP_SINCE). Measured 2026-11-03: 17 entries over the cap since 2026-10-31, every one written here -
    # title, recipients, path and reason added up, and nothing ran the lint before the commit.
    over = len(line.rstrip("\n").encode("utf-8")) - _lint._rotate.ENTRY_CAP
    if over > 0 and a.date >= _lint.LOG_CAP_SINCE:
        return refuse(f"the LOG line is {over} B over the entry cap of {_lint._rotate.ENTRY_CAP} B - shorten "
                      "--title (the file name follows it) or --one-machine; the substance belongs in the body")

    q = '"' + a.title.replace("\\", "\\\\").replace('"', '\\"') + '"'
    # The writer's system and core version, written by the producer at write time (operator order
    # 2026-10-28; first asked 2026-10-18 and built then only as a commit trailer): activity per core
    # version is read from the entries (`device-status.py entries`). Same source as that trailer.
    os_name, core = _device.entry_origin()
    meta = ["  type: project", f"  von: {von}", f"  audience: {', '.join(to)}", f"  topic: {a.area}",
            f"  date: {a.date}", f"  os: {os_name}", f"  core: {core}", f"  status: {status}"]
    if status == "open":
        nxt = [d for d in (resolve_next(to, parties, a.title + "\n" + body) if parties else to)
               if d != von.lower() and d not in handed]
        meta.append(f"  next: {', '.join(nxt)}")
    if answers:
        meta.append(f"  {'claims' if a.kind == 'claim' else 'answers'}: {', '.join(answers)}")
    if a.one_machine:
        meta.append(f"  one-machine: {a.one_machine}")
        meta.append(f"  one-machine-evidence: {a.one_machine_evidence}")
    if a.ci_not_green_ok:
        meta.append(f"  ci-not-green-ok: {a.ci_not_green_ok}")
    if a.hand_check_ok:
        meta.append(f"  hand-check-ok: {a.hand_check_ok}")
    text = "---\n" + f"name: {stem}\ndescription: {q}\nmetadata:\n" + "\n".join(meta) + "\n---\n\n" + body.strip() + "\n"
    log = area_dir / "LOG.md"
    old = log.read_text(encoding="utf-8")
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
