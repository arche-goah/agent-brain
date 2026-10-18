#!/usr/bin/env python3
"""Instance-data leak scan — blocking, deterministic, stdlib, no network.

WHY this exists as a script and not as a habit: this repository was cut fresh out of a
private working repo precisely because a history cannot be cleaned (see the public-repo
guide). The cut was verified once by hand — 281 replacements, then 0 hits. A one-time
verification protects commit 1 and nothing after it. This runs on every push.

Classes it refuses:
  private IPv4   RFC1918 and CGNAT — a real address from someone's network
  MAC            hardware identity
  home paths     /Users/<name>, /home/<name> — leaks a person and a machine layout
  email          any address outside the GitHub noreply forms and the reserved example
                 domains — a private address is an identity that cannot be rotated
  people         names from the watch list (see _instance_list)
  instances      show, venue and rig names from the watch list

Three surfaces, because a file scan alone let a cut repo fill up again (measured 2026-10-18
before the second cut: 84 commits with a private author address, 22 messages and 164 file
versions naming people — none of it in a working-tree file the scan would have seen):
  the tree         every file (default)
  --commits RANGE  author and committer address of every commit in RANGE, and its message
  --text FILE      free text — a pull request's title and body, a comment

Watch list in CI: a shared repo cannot carry the names in clear text (a guard that ships
its list tells the world whom it protects), so CI hands it in through the secret
LEAK_NAMES_JSON (same shape as the file). Matches from that source are printed redacted —
CI logs of a public repo are public. LEAK_NAMES_REQUIRED=1 makes a missing list a failure
(exit 2) instead of a silent pass: the first cut lived for weeks with CI green because the
names check had no list there.

Deliberately allowed: loopback, 0.0.0.0, the RFC 5737 documentation ranges (192.0.2.x,
198.51.100.x, 203.0.113.x) and RFC 3849 (2001:db8::) — those exist to be written down.

Usage: scripts/leak-scan.py [--json] [--root DIR] [--only PATH ...] [--commits RANGE] [--text FILE ...]
Exit 0 = clean, 1 = findings, 2 = bad --root, or no watch list while LEAK_NAMES_REQUIRED=1.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv"}
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".ico", ".woff",
               ".woff2", ".ttf", ".mp4", ".mov", ".wav"}

# Names that must never appear — loaded from the INSTANCE, never carried here
# (public-readiness sweep 2026-08-13: a guard that ships its own watch list in
# clear text tells the world exactly whom it protects). Each brain keeps its list
# in .claude/rules/leak-names.json at the scan root:
#   {"names": ["..."], "instances": ["..."]}
# Core and suite CI get the list from the secret LEAK_NAMES_JSON (docstring). The old note
# here said person names "simply cannot occur in shared repos" — refuted by the history of
# this very repo.
REDACT = False  # set when the list came from the environment: never echo it into a log


def _instance_list(root):
    import json as _json
    import os as _os
    global REDACT
    names, instances = [], []
    sources = []
    try:
        with open(root / ".claude/rules/leak-names.json", encoding="utf-8") as f:
            sources.append(_json.load(f))
    except Exception:
        pass
    env = _os.environ.get("LEAK_NAMES_JSON", "").strip()
    if env:
        try:
            sources.append(_json.loads(env))
            REDACT = True
        except ValueError:
            print("leak-scan: LEAK_NAMES_JSON is not valid JSON", file=sys.stderr)
    for d in sources:
        names += [str(n).lower() for n in d.get("names", []) if str(n).strip()]
        instances += [str(i).lower() for i in d.get("instances", []) if str(i).strip()]
        ACCOUNTS.extend(str(a) for a in d.get("accounts", []) if str(a).strip())
    return (names, instances)


# GitHub logins of the collaborators (`accounts` in the list). A login is the public account
# every PR and comment already shows, and the noreply address carries it; a person name that
# is part of a login ("<name>-lights") is not a leak of the name. Masked before matching.
ACCOUNTS: list[str] = []


def _mask_accounts(line: str) -> str:
    for a in ACCOUNTS:
        line = re.sub(rf"(?<![\w-]){re.escape(a)}(?![\w-])", "<account>", line, flags=re.I)
    return line


# /Users/Shared is a real macOS system path used for IPC with the console, not a
# person's home directory.
ALLOWED_PATHS = re.compile(r"^/Users/Shared\b")

# RFC 7042 reserves 00:00:5E:00:53:xx for documentation. An example MAC has to be
# written down somewhere, and this is the range that exists for it.
ALLOWED_MACS = re.compile(r"^00:00:5[eE]:00:53:", re.I)

# Two RFC1918 addresses stay allowed here because they are technical CONSTANTS, not
# somebody's network: 172.17.0.1 is Docker's default bridge gateway, and 192.168.88.1 is
# MikroTik's factory default address — the address a fresh board answers on, which is
# the entire point of the bootstrap example. Rewriting them to a documentation range
# would make the documentation wrong.
ALLOWED_IPS = re.compile(
    r"^(127\.|0\.0\.0\.0|255\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|"
    r"224\.|239\.|2\.4\.|1\.0\.0\.0|1\.1\.1\.1|172\.17\.0\.1$|192\.168\.88\.1$)"
)

CHECKS = [
    # 10/8 needs THREE more octets. The first version of this line wrote \d.\d and
    # matched the version string "10.2.0" in package-lock.json — a scanner that cries
    # wolf on a lockfile is a scanner nobody runs.
    ("private_ip", re.compile(
        r"\b(?:10(?:\.\d{1,3}){3}"
        r"|192\.168(?:\.\d{1,3}){2}"
        r"|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2}"
        r"|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])(?:\.\d{1,3}){2})\b")),
    ("mac", re.compile(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b")),
    ("home_path", re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")),
    ("email", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")),
]
# Addresses that identify nobody: GitHub's noreply forms (the account id is public anyway),
# the git SSH user, bots, and the RFC 2606 / RFC 6761 reserved names.
ALLOWED_EMAILS = re.compile(
    r"^(?:\d+\+[\w.-]+@users\.noreply\.github\.com|[\w.-]+@users\.noreply\.github\.com"
    r"|(?:noreply|support|git)@github\.com|noreply@anthropic\.com"
    r"|.*@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|invalid|test|localhost))$", re.I)
# Empty lists must contribute NO pattern — "|".join([]) compiles to "" and an
# empty regex matches every line (measured while building this: full-tree false red).
def add_instance_checks(root):
    """Person and instance patterns come from the SCAN ROOT's watch list — the tree being
    scanned, not the cwd and not the scanner's own checkout (the two used to disagree:
    files from the scanner's checkout, names from the cwd)."""
    names, instances = _instance_list(root)
    if names:
        CHECKS.append(("person",
                       re.compile("|".join(rf"\b{re.escape(n)}\b" for n in names), re.I)))
    if instances:
        CHECKS.append(("instance",
                       re.compile("|".join(re.escape(i) for i in instances), re.I)))


def files(only=None):
    """All tracked-ish files under ROOT, or only those under the given subpaths.

    The subpath filter exists for the PRIVATE brain: scanning it whole is meaningless
    (it is full of real rig data by design — that is the point of the private layer).
    What matters is the subset that is a candidate for the shared core. U-01.
    """
    roots = [ROOT / p for p in only] if only else [ROOT]
    seen = set()
    for base in roots:
        if base.is_file():
            candidates = [base]
        else:
            candidates = sorted(base.rglob("*"))
        for path in candidates:
            if not path.is_file() or path.suffix.lower() in SKIP_SUFFIX:
                continue
            try:
                rel = path.relative_to(ROOT)
            except ValueError:
                continue
            if any(part in SKIP_DIRS for part in rel.parts):
                continue
            if path.resolve() == Path(__file__).resolve():
                continue  # the scanner names what it looks for
            if path in seen:
                continue
            seen.add(path)
            yield path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--only", nargs="*", metavar="PATH",
                    help="restrict the scan to these subpaths (relative to the scan root)")
    ap.add_argument("--root", metavar="DIR",
                    help="tree to scan (default: the checkout this script lives in). A brain "
                         "scanning ITSELF through its core/ submodule must pass --root . — "
                         "without it the scan measures the submodule (measured 2026-09-23)")
    ap.add_argument("--commits", metavar="RANGE",
                    help="also scan author/committer address and message of every commit in "
                         "RANGE (git rev-list syntax, e.g. origin/main..HEAD)")
    ap.add_argument("--text", nargs="*", metavar="FILE", default=[],
                    help="also scan these free-text files (PR title and body, a comment)")
    ap.add_argument("--no-tree", action="store_true",
                    help="skip the file tree (only --commits / --text)")
    args = ap.parse_args()

    global ROOT
    if args.root:
        ROOT = Path(args.root).resolve()
        if not ROOT.is_dir():
            print(f"leak-scan: --root {args.root} is not a directory", file=sys.stderr)
            return 2
    names, _ = _instance_list(ROOT)
    global REDACT
    # A public CI log is a publication: the finding must not repeat what it found.
    REDACT = REDACT or os.environ.get("GITHUB_ACTIONS") == "true"
    if os.environ.get("LEAK_NAMES_REQUIRED") == "1" and not names:
        print("leak-scan: LEAK_NAMES_REQUIRED=1 but no watch list (LEAK_NAMES_JSON secret or "
              ".claude/rules/leak-names.json) — the names check would pass by not looking",
              file=sys.stderr)
        return 2
    add_instance_checks(ROOT)

    findings = []

    def scan(lines, where):
        for lineno, line in enumerate(lines, 1):
            for name, pattern in CHECKS:
                text = _mask_accounts(line) if name in ("person", "instance") else line
                for match in pattern.finditer(text):
                    hit = match.group(0)
                    if name == "private_ip" and ALLOWED_IPS.match(hit):
                        continue
                    if name == "home_path" and ALLOWED_PATHS.match(hit):
                        continue
                    if name == "mac" and ALLOWED_MACS.match(hit):
                        continue
                    if name == "email" and ALLOWED_EMAILS.match(hit):
                        continue
                    if REDACT and name in ("person", "instance", "email"):
                        hit = f"<redacted {len(hit)} chars>"
                    findings.append({"check": name, "file": where, "line": lineno, "match": hit})

    if not args.no_tree:
        for path in files(args.only):
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeDecodeError):
                continue
            scan(lines, path.relative_to(ROOT).as_posix())
    for t in args.text:
        try:
            scan(Path(t).read_text(encoding="utf-8").splitlines(), f"text:{Path(t).name}")
        except (OSError, UnicodeDecodeError) as e:
            print(f"leak-scan: cannot read --text {t}: {e}", file=sys.stderr)
            return 2
    if args.commits:
        r = subprocess.run(["git", "-C", str(ROOT), "log", "--format=%H%x00%an <%ae>%x00%cn <%ce>%x00%B%x1e",
                            args.commits], capture_output=True, text=True, encoding="utf-8",
                           errors="replace")
        if r.returncode != 0:
            print(f"leak-scan: git log {args.commits} failed: {r.stderr.strip()}", file=sys.stderr)
            return 2
        for rec in r.stdout.split("\x1e"):
            parts = rec.strip("\n").split("\x00")
            if len(parts) < 4:
                continue
            sha, author, committer, msg = parts[0][:12], parts[1], parts[2], parts[3]
            scan([author], f"commit:{sha}:author")
            scan([committer], f"commit:{sha}:committer")
            scan(msg.splitlines(), f"commit:{sha}:message")

    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        print(f"leak-scan: {len(findings)} findings")
        for f in findings:
            print(f"!! [{f['check']}] {f['file']}:{f['line']}: {f['match']}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
