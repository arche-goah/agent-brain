#!/usr/bin/env python3
"""Does a report cover every part of its source, or name what it left out?

A summary or a total built from part of its source reads exactly like one built from all of it.
This counts the parts of the source (one regex match = one part; group 1, if any, is its key) and
checks the report: every key appears in the report text, or stands in a `left out:` line.

Usage:
  report-coverage.py --source FILE --parts REGEX --report FILE
Exit 0 = every part covered or named as left out; 1 = parts missing (listed); 2 = usage error.
"""
from __future__ import annotations

import argparse
import re
import sys

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

LEFT_OUT = re.compile(r"^\s*[-*]?\s*(?:left out|ausgelassen)\s*:\s*(.+)$", re.I | re.M)


def parts(source: str, pattern: str) -> list[str]:
    keys = []
    for m in re.finditer(pattern, source, re.M):
        key = (m.group(1) if m.groups() else m.group(0)).strip()
        if key and key not in keys:
            keys.append(key)
    return keys


def missing(keys: list[str], report: str) -> list[str]:
    named = " ".join(LEFT_OUT.findall(report)).lower()
    body = LEFT_OUT.sub("", report).lower()
    return [k for k in keys if k.lower() not in body and k.lower() not in named]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", required=True)
    ap.add_argument("--parts", required=True, help="regex; one match = one part, group 1 = its key")
    ap.add_argument("--report", required=True)
    a = ap.parse_args(argv)
    try:
        src = open(a.source, encoding="utf-8").read()
        rep = open(a.report, encoding="utf-8").read()
        keys = parts(src, a.parts)
    except (OSError, re.error) as e:
        print(f"report-coverage: {e}", file=sys.stderr)
        return 2
    if not keys:
        print(f"report-coverage: the pattern finds no part in {a.source} - nothing to check is no check", file=sys.stderr)
        return 2
    miss = missing(keys, rep)
    print(f"report-coverage: {len(keys)} part(s) in the source, {len(keys) - len(miss)} covered or named left out")
    for k in miss:
        print(f"  MISSING {k}")
    return 1 if miss else 0


if __name__ == "__main__":
    sys.exit(main())
