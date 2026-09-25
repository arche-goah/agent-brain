#!/usr/bin/env python3
"""Fixtures for shared-memory-log-rotate.py — the LOG rotation and the entry cap.

The operator's ruling (2026-09-25) has three load-bearing words, and each is a property:
  nothing lost   every block of the LOG exists exactly once afterwards, byte for byte;
  clean pointers the LOG names every archive month, every archive points back;
  short entries  an own entry over the cap is reported, an older or foreign one is not.
Both directions where one exists: the check must speak when a month is due and stay
silent when it is not; a rerun must move nothing.

Usage: python3 scripts/shared-memory-log-rotate-test.py   (exit 0 = all fixtures pass)
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "shared-memory-log-rotate.py"
fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def run(repo, *args, self_=""):
    env = dict(os.environ, SHARED_MEMORY_SELF=self_)
    r = subprocess.run([sys.executable, str(SCRIPT), "--repo", str(repo), *args],
                       capture_output=True, text=True, encoding="utf-8", env=env)
    return r.returncode, r.stdout


def blocks(text):
    return [b.rstrip("\n") for b in re.split(r"(?m)^(?=## \d{4}-\d{2}-\d{2})", text)[1:]]


LOG = (
    "# ops — Log\n\nPreamble line.\n\n"
    "## 2026-08-30 · peer — AN me-mac: august entry\n\nbody a\n\n"
    "## Sub-heading without date\n\nbelongs to the august entry\n\n"
    "## 2026-09-02 me-mac - AN peer: september entry\n\nbody b\n\n"
    "## 2026-10-01 · peer — AN alle: october entry\n\nbody c\n"
)

with tempfile.TemporaryDirectory() as tmp:
    repo = Path(tmp)
    (repo / "ops").mkdir()
    log = repo / "ops" / "LOG.md"
    log.write_text(LOG, encoding="utf-8", newline="\n")
    original = blocks(LOG)

    print("check before rotation")
    rc, out = run(repo, "--check", "--today", "2026-10-05")
    ok("due line names the topic and count", "rotation due before 2026-10 - ops (2)" in out, out)
    rc, out = run(repo, "--check", "--today", "2026-08-31")
    ok("negative: nothing closed yet -> silent", out.strip() == "", out)

    print("rotation")
    rc, out = run(repo, "--write", "--today", "2026-10-05")
    ok("write exits 0", rc == 0, out)
    aug = repo / "ops" / "archive" / "LOG-2026-08.md"
    sep = repo / "ops" / "archive" / "LOG-2026-09.md"
    ok("august archive created", aug.is_file())
    ok("september archive created", sep.is_file())
    after = blocks(log.read_text(encoding="utf-8")) + blocks(aug.read_text(encoding="utf-8")) \
        + blocks(sep.read_text(encoding="utf-8"))
    ok("nothing lost: every block exactly once, byte for byte", sorted(after) == sorted(original),
       f"{len(after)} vs {len(original)}")
    ok("undated sub-heading travelled with its entry",
       "belongs to the august entry" in aug.read_text(encoding="utf-8"))
    new_log = log.read_text(encoding="utf-8")
    ok("october entry stayed", "october entry" in new_log and "september entry" not in new_log)
    ok("preamble kept", "Preamble line." in new_log)
    ok("pointer names both months",
       "Earlier months: [2026-08](archive/LOG-2026-08.md), [2026-09](archive/LOG-2026-09.md)" in new_log,
       new_log)
    ok("archive points back", "(../LOG.md)" in sep.read_text(encoding="utf-8"))
    ok("LF only", b"\r" not in log.read_bytes() + sep.read_bytes())

    print("rerun")
    snap = {p: p.read_bytes() for p in repo.rglob("*.md")}
    rc, out = run(repo, "--write", "--today", "2026-10-05")
    ok("rerun moves nothing", out.strip() == "" and snap == {p: p.read_bytes() for p in repo.rglob("*.md")}, out)
    rc, out = run(repo, "--check", "--today", "2026-10-05")
    ok("check silent after rotation", out.strip() == "", out)

    print("next month appends, pointer grows, no duplicate pointer line")
    rc, out = run(repo, "--write", "--today", "2026-11-02")
    new_log = log.read_text(encoding="utf-8")
    ok("october archived", (repo / "ops" / "archive" / "LOG-2026-10.md").is_file())
    ok("one pointer line only", new_log.count("Earlier months:") == 1, new_log)
    ok("pointer lists three months", "[2026-10](archive/LOG-2026-10.md)" in new_log
       and "[2026-08]" in new_log)

    print("entry cap")
    long_body = "x" * 400
    log.write_text(
        log.read_text(encoding="utf-8")
        + f"\n## 2026-09-20 · me-mac — old long entry\n\n{long_body}\n"
        + f"\n## 2026-11-03 · me-mac — AN peer: new long entry\n\n{long_body}\n"
        + f"\n## 2026-11-03 · peer — AN me-mac: foreign long entry\n\n{long_body}\n"
        + f"\n## 2026-11-04 me-mac - AN peer: ascii hyphen shape\n\n{long_body}\n"
        + "\n## 2026-11-03 · me-mac — AN peer: short\n\nDatei: `ops/x.md`.\n",
        encoding="utf-8", newline="\n")
    rc, out = run(repo, "--check", "--today", "2026-11-05", self_="me-mac")
    ok("own new long entry reported", "2 own LOG entries over 300 B" in out and "2026-11-03 me-mac" in out, out)
    ok("ascii-hyphen heading shape recognised as own", "2026-11-04 me-mac" in out, out)
    ok("foreign long entry not reported", "peer (" not in out, out)
    ok("entry before the cap date not reported", "2026-09-20" not in out.split("over 300 B")[-1], out)

if fails:
    print(f"\nshared-memory-log-rotate-test: {len(fails)} FAILED")
    sys.exit(1)
print("\nshared-memory-log-rotate-test: all fixtures pass")
