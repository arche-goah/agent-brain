#!/usr/bin/env python3
"""release-scope.py - what ONE release carries, written down before it is cut, and checked before it closes.

WHY (operator 2026-11-06, translated: "what does it take for this to finally work reliably - the trains do not
solve it; you keep running CI individually and do not wait with pins and releases until everything is together").
Measured the same day on the macOS instance for beta 2.1.4: sixteen PRs each got their own lint and CI, the train
was rebuilt three times, and the train was closed (the Windows hand check requested) while the same instance still
had two own branches in work and two operator-released items unbuilt; the operator found them afterwards. Nothing
said what the release was meant to hold, so nothing could say that something was missing.

The scope is a file in the INSTANCE that cuts the release (a core script's own folder is not the brain):
    <brain>/.claude-state/release-scope.json
    {"version": "2.1.4", "repo": "agent-brain", "status": "open"|"closed", "opened": "YYYY-MM-DD",
     "items": ["agent-brain#433", "feat/x", "<ledger id>"], "excluded": {"<item>": "<reason>"}}
An item is a ledger id, `<repo>#<n>` (or `#<n>`) or a branch name.

    release-scope.py open <version> [--repo NAME]     start the scope (helpers/release-freeze-gate.cjs then holds
                                                     new core branches that are not in it)
    release-scope.py add <item> [<item> ...]          in this release
    release-scope.py exclude <item> <reason ...>      deliberately not in this release, with the reason; needs
                                                     RELEASE_SCOPE_EXCLUDE_OK='"<operator's words>" <YYYY-MM-DD>'
    release-scope.py show
    release-scope.py check --core-clone DIR [--version X.Y.Z]
    release-scope.py close                            after the tag; the freeze ends
Every subcommand takes --root DIR (the brain; default: the working directory).

`check` is the close gate: exit 1 when anything of THIS instance is open but neither in the scope nor excluded -
  (a) an open PR of the core repo whose body carries this instance's key (scripts/instance_key.py; the key comes
      from SHARED_MEMORY_SELF, else from the brain's .claude/settings(.local).json env, as instance-key-gate reads it),
      read with `gh pr list --limit 500` inside the core clone (RELEASE_SCOPE_PR_FIXTURE = a JSON file in that output form);
  (b) a local branch of the core clone with commits not on origin/main;
  (c) an open entry of the brain's registered ledgers (.claude/rules/ledgers.json, read by open-items.py's reader)
      whose newest exit is `ai-does-it` or `in-pr` and whose `reach:` is shared or core.
A PR in the scope covers its branch, and the other way round. A source that cannot be read is a finding, never
silence. Exit: 0 clean, 1 findings, 2 usage.
"""
import argparse
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from instance_key import key_for, key_in, self_id  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: the preflight reads this output
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

STATE = Path(".claude-state") / "release-scope.json"
# `reach:` as a field - its own line (`  - reach: shared`) or inline after a separator (`id: x · reach: shared`);
# the words "reach: shared" inside a sentence are prose, not the entry's field.
REACH = re.compile(r"(?:^\s*(?:[-*]\s+)?|[|·;]\s*)`?reach:\s*`?(shared|core)\b", re.I | re.M)
ACTIVE_EXITS = ("ai-does-it", "in-pr")
# The operator's words in quote marks (straight or typographic), as release-preflight's RELEASE_EARLY_OK takes them.
QUOTED = re.compile(r"[\"“„«][^\"“”„«»]{3,}[\"”“»]")


def state_path(root):
    return Path(root) / STATE


def load(root):
    try:
        data = json.loads(state_path(root).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def save(root, data):
    p = state_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as f:  # OS-2
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")


def run(cmd, cwd=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=60)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, str(e)


def instance_key(root):
    """This instance's key: SHARED_MEMORY_SELF, else the brain's settings env (the reading of instance-key-gate)."""
    sid = self_id()
    if not sid:
        for name in ("settings.local.json", "settings.json"):
            try:
                env = json.loads((Path(root) / ".claude" / name).read_text(encoding="utf-8")).get("env") or {}
            except (OSError, ValueError, AttributeError):
                continue
            if env.get("SHARED_MEMORY_SELF"):
                sid = self_id({"SHARED_MEMORY_SELF": str(env["SHARED_MEMORY_SELF"])})
                break
    return key_for(sid)


def open_prs(clone):
    """Rows of `gh pr list --limit 500` (number, headRefName, body, title), or None when they cannot be read."""
    fixture = os.environ.get("RELEASE_SCOPE_PR_FIXTURE")
    if fixture:
        try:
            rows = json.loads(Path(fixture).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
    else:
        rc, out = run(["gh", "pr", "list", "--state", "open", "--limit", "500",
                       "--json", "number,headRefName,body,title"], cwd=clone)
        if rc != 0:
            return None
        try:
            rows = json.loads(out)
        except ValueError:
            return None
    return rows if isinstance(rows, list) else None


def unshipped_branches(clone):
    """{branch: commits not on origin/main} for every local branch with at least one, or None (no origin/main)."""
    if run(["git", "-C", str(clone), "rev-parse", "--verify", "-q", "refs/remotes/origin/main"])[0] != 0:
        return None
    rc, out = run(["git", "-C", str(clone), "for-each-ref", "--format=%(refname:short)", "refs/heads/"])
    if rc != 0:
        return None
    found = {}
    for b in out.split():
        rc, n = run(["git", "-C", str(clone), "rev-list", "--count", f"refs/remotes/origin/main..refs/heads/{b}"])
        if rc == 0 and n.strip().isdigit() and int(n) > 0:
            found[b] = int(n)
    return found


def ledger_items(root):
    """(items, unread) from open-items.py's ledger reader - one parser, not a third (items None: no registry)."""
    spec = importlib.util.spec_from_file_location("open_items", HERE / "open-items.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.ledgers(Path(root))


def check(root, clone, version):
    scope = load(root)
    if scope is None:
        print(f"FAIL no release scope at {STATE.as_posix()} - start it: release-scope.py open <version>")
        return 1
    repo = scope.get("repo") or "agent-brain"
    covered = set(scope.get("items") or []) | set((scope.get("excluded") or {}).keys())
    findings, notes = [], []
    if version and scope.get("version") != version:
        findings.append(("scope", scope.get("version") or "?",
                         f"the scope is for {scope.get('version')}, this release is {version} - open the right scope"))

    key = instance_key(root)
    prs = open_prs(clone)
    pr_branch_covered = set()
    if not key:
        findings.append(("source", "instance key", "SHARED_MEMORY_SELF unset - own PRs cannot be told apart (NOT run)"))
    if prs is None:
        findings.append(("source", "open PRs", "could not be read (gh missing, not logged in, or not this repo)"))
    else:
        for p in prs:
            ids = {f"{repo}#{p.get('number')}", f"#{p.get('number')}"}
            if ids & covered:
                pr_branch_covered.add(p.get("headRefName") or "")
        if key:
            for p in prs:
                ids = {f"{repo}#{p.get('number')}", f"#{p.get('number')}", p.get("headRefName") or ""}
                if key_in(p.get("body") or "") == key and not ids & covered:
                    findings.append(("PR", f"{repo}#{p.get('number')}",
                                     f"own open PR ({p.get('headRefName')}): {(p.get('title') or '')[:70]}"))

    branches = unshipped_branches(clone)
    if branches is None:
        findings.append(("source", "branches", f"no origin/main in {Path(clone).as_posix()} (NOT run)"))
    else:
        for b, n in sorted(branches.items()):
            if b not in covered and b not in pr_branch_covered:
                findings.append(("branch", b, f"{n} commit(s) not on origin/main"))

    try:
        items, unread = ledger_items(root)
    except Exception as e:  # the reader failing is a source not read, never "nothing open"
        items, unread = [], [f"the ledger reader (open-items.py: {type(e).__name__})"]
    if items is None:
        notes.append("no ledger registry (.claude/rules/ledgers.json) - no ledger entries to compare")
    for u in unread:
        findings.append(("source", "ledger", f"{u} could not be read"))
    for it in items or []:
        if it.get("exit") in ACTIVE_EXITS and REACH.search(it.get("body") or ""):
            if not {it.get("ref"), it.get("id")} & covered:
                findings.append(("ledger", it.get("ref"), f"exit {it['exit']}: {it.get('text', '')[:70]}"))

    for n in notes:
        print(f"     {n}")
    if not findings:
        print(f"OK   release scope {scope.get('version')}: every open item of this instance is in the scope or excluded")
        return 0
    for kind, ident, why in findings:
        print(f"OPEN {kind} {ident} - {why}")
        if kind not in ("source", "scope"):
            print(f"       in this release:  release-scope.py add {ident}")
            print(f"       not in it:        ask the operator; RELEASE_SCOPE_EXCLUDE_OK='\"<their words>\" <date>' "
                  f"release-scope.py exclude {ident} \"<reason>\"")
    print(f"FAIL {len(findings)} item(s) of this instance are open but not in release scope {scope.get('version')}")
    return 1


def main(argv=None):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--root", default=".", help="the brain (default: working directory)")
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("open", parents=[common])
    o.add_argument("version")
    o.add_argument("--repo", default="agent-brain", help="the repo this release is cut from")
    a = sub.add_parser("add", parents=[common])
    a.add_argument("items", nargs="+")
    e = sub.add_parser("exclude", parents=[common])
    e.add_argument("item")
    e.add_argument("reason", nargs="+")
    sub.add_parser("show", parents=[common])
    c = sub.add_parser("check", parents=[common])
    c.add_argument("--core-clone", required=True, help="the core clone whose branches and PRs are read")
    c.add_argument("--version", default="", help="the version being cut; must be the scope's")
    sub.add_parser("close", parents=[common])
    args = ap.parse_args(argv)
    root = args.root
    today = datetime.date.today().isoformat()
    scope = load(root)
    is_open = bool(scope) and scope.get("status") == "open"

    if args.cmd == "open":
        if is_open and scope.get("version") != args.version:
            print(f"FAIL release scope {scope.get('version')} is open - close it first (release-scope.py close)")
            return 1
        if is_open:
            print(f"release scope {args.version} is already open ({len(scope.get('items') or [])} item(s))")
            return 0
        save(root, {"version": args.version, "repo": args.repo, "status": "open", "opened": today,
                    "items": [], "excluded": {}})
        print(f"release scope {args.version} opened in {STATE.as_posix()}; new {args.repo} branches outside it are held")
        return 0
    if args.cmd == "check":
        return check(root, args.core_clone, args.version)
    if args.cmd == "show":
        if not scope:
            print("no release scope")
            return 1
        print(f"release scope {scope.get('version')} ({scope.get('repo')}) - {scope.get('status')} since "
              f"{scope.get('closed') or scope.get('opened')}")
        for i in scope.get("items") or []:
            print(f"  in   {i}")
        for i, why in sorted((scope.get("excluded") or {}).items()):
            print(f"  out  {i} - {why}")
        return 0
    if not is_open:
        print("FAIL no open release scope - release-scope.py open <version>")
        return 1
    if args.cmd == "add":
        items = scope.setdefault("items", [])
        for i in args.items:
            (scope.get("excluded") or {}).pop(i, None)
            if i not in items:
                items.append(i)
        save(root, scope)
        print(f"in release scope {scope['version']}: {', '.join(args.items)}")
    elif args.cmd == "exclude":
        reason = " ".join(args.reason).strip()
        if not reason:
            print("FAIL an exclusion names its reason")
            return 2
        # What a release leaves out is the operator's call (release is on every operator-only list). Measured
        # 2026-11-11 on the macOS instance: check 11 held tag 2.1.5 because 21 own PRs, older than the train, were
        # neither in it nor excluded; a script excluded all 21 with one reason that quoted the operator about the check
        # procedure, not about leaving them out. The preflight went green, the PRs stood for good.
        word = os.environ.get("RELEASE_SCOPE_EXCLUDE_OK", "")
        if not (QUOTED.search(word) and re.search(r"\b\d{4}-\d{2}-\d{2}\b", word)):
            print(f"FAIL leaving {args.item} out of release {scope.get('version')} is the operator's call: ask with the list, "
                  "then RELEASE_SCOPE_EXCLUDE_OK='\"<their words about these items>\" <YYYY-MM-DD>' release-scope.py exclude ...")
            return 3
        reason = f"{reason} — operator: {word.strip()}"
        scope["items"] = [i for i in scope.get("items") or [] if i != args.item]
        scope.setdefault("excluded", {})[args.item] = reason
        save(root, scope)
        print(f"excluded from release scope {scope['version']}: {args.item} - {reason}")
    elif args.cmd == "close":
        scope["status"], scope["closed"] = "closed", today
        save(root, scope)
        print(f"release scope {scope['version']} closed; the freeze on new branches ends")
    return 0


if __name__ == "__main__":
    sys.exit(main())
