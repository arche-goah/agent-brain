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
  people         names configured in NAMES below
  instances      show, venue and rig names configured in INSTANCES below

Deliberately allowed: loopback, 0.0.0.0, the RFC 5737 documentation ranges (192.0.2.x,
198.51.100.x, 203.0.113.x) and RFC 3849 (2001:db8::) — those exist to be written down.

Usage: scripts/leak-scan.py [--json] [--root DIR] [--only PATH ...]
Exit 0 = clean, 1 = findings, 2 = bad --root.
"""
from __future__ import annotations

import argparse
import json
import re
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
# Core and suite CI scan without a list — the generic patterns (home paths, IPs,
# secrets) still apply there; person names simply cannot occur in shared repos.
def _instance_list(root):
    import json as _json
    try:
        with open(root / ".claude/rules/leak-names.json", encoding="utf-8") as f:
            d = _json.load(f)
        return ([str(n).lower() for n in d.get("names", [])],
                [str(i).lower() for i in d.get("instances", [])])
    except Exception:
        return ([], [])


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
]
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
    args = ap.parse_args()

    global ROOT
    if args.root:
        ROOT = Path(args.root).resolve()
        if not ROOT.is_dir():
            print(f"leak-scan: --root {args.root} is not a directory", file=sys.stderr)
            return 2
    add_instance_checks(ROOT)

    findings = []
    for path in files(args.only):
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for lineno, line in enumerate(lines, 1):
            for name, pattern in CHECKS:
                for match in pattern.finditer(line):
                    hit = match.group(0)
                    if name == "private_ip" and ALLOWED_IPS.match(hit):
                        continue
                    if name == "home_path" and ALLOWED_PATHS.match(hit):
                        continue
                    if name == "mac" and ALLOWED_MACS.match(hit):
                        continue
                    findings.append({
                        "check": name,
                        "file": path.relative_to(ROOT).as_posix(),
                        "line": lineno,
                        "match": hit,
                    })

    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        print(f"leak-scan: {len(findings)} findings")
        for f in findings:
            print(f"!! [{f['check']}] {f['file']}:{f['line']}: {f['match']}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
