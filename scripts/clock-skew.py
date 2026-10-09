#!/usr/bin/env python3
"""Clock skew: is this machine's clock right, measured against the outside?

WHY (2026-10-09, Windows instance): the system clock ran two hours behind real UTC for
days and nothing said so. Internally consistent (zone and DST correct), so every local
look agreed with itself. What it broke silently: every commit timestamp of that machine
(a timeline between two instances under one GitHub account put an answer BEFORE the
request it answered), and every time-based cursor — a PR watcher built `since=` from
`date -u` and replayed one old comment on every poll. It surfaced by accident. The time
service had been fixed once (2026-09-24) and fell back after a reboot without a sign.

One HEAD request to a reference server, its `Date` header against `time.time()`. Silent
when within the threshold, and silent when the reference cannot be reached (offline is
not a finding; a bootup must not get noisy or slow on a train) — the timeout is short.

Usage: clock-skew.py [--threshold SECONDS] [--url URL]
  CLOCK_SKEW_REFERENCE=<HTTP date>  use this instead of the network (fixtures)
Output: one `!! clock:` line when off; exit 0 always (a bootup line, not a gate).
"""
import argparse
import email.utils
import os
import sys
import time
import urllib.request

# The session start parses this output; Windows' default console code page would mangle
# the dash (os-traps OS-9).
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass


def reference(url, timeout):
    fixed = os.environ.get("CLOCK_SKEW_REFERENCE")
    if fixed:
        return email.utils.parsedate_to_datetime(fixed).timestamp(), "CLOCK_SKEW_REFERENCE"
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        date = r.headers.get("Date")
    return email.utils.parsedate_to_datetime(date).timestamp(), url.split("/")[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=120.0)
    ap.add_argument("--url", default="https://api.github.com")
    ap.add_argument("--timeout", type=float, default=3.0)
    a = ap.parse_args()
    try:
        ref, src = reference(a.url, a.timeout)
    except Exception:
        return 0
    skew = time.time() - ref
    if abs(skew) <= a.threshold:
        return 0
    m = round(abs(skew) / 60)
    way = "behind" if skew < 0 else "ahead of"
    print(f"!! clock: system time is {m} min {way} {src} — commit timestamps and every "
          f"time-based cursor (watchers' since=) are wrong until the time service syncs "
          f"(Windows: w32tm /resync elevated; check `w32tm /query /status` Source)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
