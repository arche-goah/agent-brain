#!/usr/bin/env python3
"""Repo setup check — does a repo carry the setup contract of its kind? (CONVENTIONS §14)

WHY: a repo set up by hand gets whatever its first session remembered. Measured
2026-10-10 on one account: of 18 private repos, 7 had no workflow at all, and branch
protection was unavailable on every one of them (free plan, HTTP 403) — the "PR only"
rule of two project repos lived in a local hook nobody could see from outside. This
script names, per kind, what is there and what is missing.

Read-only. Local checks always; the protection check asks GitHub through `gh` when it
is installed and logged in, and says so when it could not ask (never "pass").

Kinds (auto-detected, override with --kind):
  core           a contract repo (core-contract.json in the root)
  suite          a plugin repo (.claude-plugin/plugin.json)
  brain          a private brain (core/ submodule + .claude/)
  shared-memory  INDEX.md in the root + LOG.md per area
  project        everything else

Usage: scripts/repo-check.py [--repo DIR] [--kind KIND] [--github OWNER/NAME]
                             [--offline] [--json]
Exit 0 = nothing missing, 1 = something missing, 2 = bad --repo.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

KINDS = ("core", "suite", "project", "brain", "shared-memory")
# What each kind must carry. Brain and shared memory take direct pushes to main by
# design (one writer per brain; an append-only log several parties write to), so they
# need neither the pre-push fence nor a PR template — and they carry instance data by
# design, so the leak scan is not their baseline either.
NEEDS = {
    "core":          {"workflow", "leak_scan", "pr_flow", "protection"},
    "suite":         {"workflow", "leak_scan", "pr_flow", "pre_push", "protection"},
    "project":       {"workflow", "leak_scan", "pr_flow", "pre_push", "pr_template",
                      "gitattributes", "protection"},
    "brain":         {"gitattributes"},
    "shared-memory": {"gitattributes"},
}


def detect_kind(repo: Path) -> str:
    if (repo / "core-contract.json").is_file():
        return "core"
    if (repo / ".claude-plugin" / "plugin.json").is_file():
        return "suite"
    if (repo / "core").is_dir() and (repo / ".claude").is_dir():
        return "brain"
    if (repo / "INDEX.md").is_file() and any(repo.glob("*/LOG.md")):
        return "shared-memory"
    return "project"


def git(repo: Path, *args: str) -> str:
    try:
        out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                             text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def workflows(repo: Path) -> list[Path]:
    d = repo / ".github" / "workflows"
    return sorted(p for p in d.glob("*.y*ml")) if d.is_dir() else []


def github_slug(repo: Path) -> str:
    url = git(repo, "remote", "get-url", "origin")
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url)
    return m.group(1) if m else ""


def classify_protection(rc: int, out: str, err: str) -> str:
    """One `gh api repos/<slug>/branches/main/protection` answer -> a state word."""
    text = out + err
    if rc == 0:
        return "enforced"
    if "Upgrade to GitHub Pro" in text or "make this repository public" in text:
        return "not-enforceable"
    if "Branch not protected" in text:
        return "missing"
    return "unknown"


def protection_state(slug: str) -> tuple[str, str]:
    if not slug:
        return "unknown", "no github.com origin"
    gh = shutil.which("gh")
    if not gh:
        return "unknown", "gh not installed"
    try:
        r = subprocess.run([gh, "api", f"repos/{slug}/branches/main/protection"],
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        return "unknown", str(e)
    state = classify_protection(r.returncode, r.stdout, r.stderr)
    if state != "missing":
        return state, ""
    # A ruleset protects too, without showing up as branch protection.
    try:
        r = subprocess.run([gh, "api", f"repos/{slug}/rules/branches/main"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and any(x.get("type") == "pull_request"
                                     for x in json.loads(r.stdout or "[]")):
            return "enforced", "ruleset"
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    return "missing", ""


def check(repo: Path, kind: str, slug: str, offline: bool) -> list[tuple[str, str, str]]:
    """-> [(status, item, detail)], status OK | MISSING | INFO."""
    need = NEEDS[kind]
    res: list[tuple[str, str, str]] = []

    def put(item: str, ok: bool, detail: str):
        if item in need:
            res.append(("OK" if ok else "MISSING", item, detail))

    wf = workflows(repo)
    texts = {p: p.read_text(encoding="utf-8", errors="replace") for p in wf}
    put("workflow", bool(wf), ", ".join(p.name for p in wf) or "no .github/workflows/*.yml")
    put("leak_scan", any("leak-scan" in t for t in texts.values()),
        "a workflow runs leak-scan.py" if any("leak-scan" in t for t in texts.values())
        else "no workflow runs leak-scan.py")
    put("pr_flow", any(re.search(r"^\s*pull_request\s*:", t, re.M) for t in texts.values()),
        "workflow triggers on pull_request")

    hook = repo / ".githooks" / "pre-push"
    hook_ok = hook.is_file() and "refs/heads/main" in hook.read_text(encoding="utf-8",
                                                                     errors="replace")
    put("pre_push", hook_ok, ".githooks/pre-push refuses main" if hook_ok
        else ".githooks/pre-push missing or does not refuse main")
    if "pre_push" in need and hook_ok:
        hp = git(repo, "config", "--get", "core.hooksPath")
        put_ok = hp.rstrip("/") == ".githooks"
        res.append(("OK" if put_ok else "MISSING", "hooks_path",
                    "core.hooksPath = .githooks in this clone" if put_ok else
                    "this clone does not run the hook: git config core.hooksPath .githooks"))

    tpl = [repo / ".github" / "pull_request_template.md",
           repo / ".github" / "PULL_REQUEST_TEMPLATE.md"]
    put("pr_template", any(p.is_file() for p in tpl), ".github/pull_request_template.md")

    ga = repo / ".gitattributes"
    ga_ok = ga.is_file() and re.search(r"eol\s*=\s*lf", ga.read_text(encoding="utf-8",
                                                                     errors="replace"))
    put("gitattributes", bool(ga_ok), ".gitattributes pins eol=lf" if ga_ok
        else ".gitattributes missing or without eol=lf")

    if "protection" in need:
        if offline:
            res.append(("INFO", "protection", "not asked (--offline)"))
        else:
            state, why = protection_state(slug)
            if state == "enforced":
                res.append(("OK", "protection", f"main is protected on the server ({why or 'branch protection'})"))
            elif state == "not-enforceable":
                res.append(("INFO", "protection",
                            "not enforceable on this plan - checks run but cannot be required; "
                            "the pre-push hook and the reviewer reading the checks carry the rule"))
            elif state == "missing":
                res.append(("MISSING", "protection",
                            "main is not protected although the plan allows it"))
            else:
                res.append(("INFO", "protection", f"could not ask GitHub ({why or 'unknown answer'})"))
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", default=".", metavar="DIR")
    ap.add_argument("--kind", choices=KINDS)
    ap.add_argument("--github", metavar="OWNER/NAME")
    ap.add_argument("--offline", action="store_true", help="skip the GitHub question")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    repo = Path(a.repo).resolve()
    if not repo.is_dir():
        print(f"repo-check: no directory {repo}", file=sys.stderr)
        return 2
    kind = a.kind or detect_kind(repo)
    slug = a.github or github_slug(repo)
    res = check(repo, kind, slug, a.offline)
    missing = sum(1 for s, _, _ in res if s == "MISSING")

    if a.json:
        print(json.dumps({"repo": str(repo), "kind": kind, "github": slug,
                          "missing": missing,
                          "items": [{"status": s, "item": i, "detail": d} for s, i, d in res]},
                         indent=2))
    else:
        print(f"repo-check: {repo.name} ({kind}{', ' + slug if slug else ''})")
        for s, i, d in res:
            print(f"  {s:<8}{i:<14}{d}")
        print(f"repo-check: {missing} missing" if missing else "repo-check: setup complete for its kind")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
