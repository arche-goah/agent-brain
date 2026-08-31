#!/usr/bin/env python3
"""Fixtures for shared-memory-index.py — the generator's first.

It writes into a repo two instances share, so its output is not a report but an artifact
somebody else reads. Three properties are load-bearing and each has bitten once:

  1. Link targets are forward-slashed. On Windows a bare `str(...)` around `relative_to()` produced
     backslashes; nothing matched the old index, so every entry was carried into the root
     page and every link it wrote was unfollowable (2026-08-31, OS-1).
  2. Generated files carry LF. Python text mode wrote CRLF into a repo whose
     .gitattributes says LF — 17 of 17 lines (2026-08-31, OS-2).
  3. The factor line names the DIRECTION it measured. "cheaper" was a fixed word beside a
     ratio that falls below 1 as soon as the index is already split — the run reported
     "0.1x cheaper" for a lookup ten times dearer (reported by the other instance).

Both directions where a direction exists: case 3 asserts the cheaper wording too, so a
fix that simply hard-codes the other word fails.

Usage: python3 scripts/shared-memory-index-test.py   (exit 0 = all fixtures pass)
"""
import importlib.util
import io
import contextlib
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("smi", HERE / "shared-memory-index.py")
smi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smi)

fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def entry(name, desc, body="text"):
    return (f"---\nname: {name}\ndescription: \"{desc}\"\nmetadata:\n"
            f"  type: reference\n  von: x\n  audience: y\n  topic: ops\n---\n\n{body}\n")


def build_repo(root, n_entries, index_text):
    (root / "ops").mkdir(parents=True, exist_ok=True)
    for i in range(n_entries):
        (root / "ops" / f"e{i}.md").write_text(
            entry(f"e{i}", f"Description number {i}."), encoding="utf-8", newline="\n")
    (root / "INDEX.md").write_text(index_text, encoding="utf-8", newline="\n")


def run_main(repo, write=False):
    argv = ["shared-memory-index.py", "--repo", str(repo)] + (["--write"] if write else [])
    old = sys.argv
    sys.argv = argv
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            smi.main()
    finally:
        sys.argv = old
    return buf.getvalue()


print("shared-memory-index:")

with tempfile.TemporaryDirectory() as td:
    repo = Path(td) / "repo"
    build_repo(repo, 3, "# Index\n\n- [E0](ops/e0.md) — d\n")
    run_main(repo, write=True)

    root_text = (repo / "INDEX.md").read_text(encoding="utf-8")
    topic_text = (repo / "ops" / "INDEX.md").read_text(encoding="utf-8")

    # 1. separators
    ok("1 root links use forward slashes",
       "ops/INDEX.md" in root_text and "\\" not in root_text,
       root_text[:120])
    ok("2 topic links use forward slashes",
       "../ops/e0.md" in topic_text and "\\" not in topic_text,
       topic_text[:120])

    # A carried-through line is the case the separator bug turned into "carry everything":
    # with matching paths, a managed entry must NOT reappear as an unmanaged one.
    ok("3 managed entries are not carried into the root page",
       "ops/e0.md" not in root_text, root_text[:160])

    # 2. line endings
    for rel in ("INDEX.md", "ops/INDEX.md"):
        raw = (repo / rel).read_bytes()
        ok(f"4 {rel} written with LF", b"\r" not in raw,
           f"{raw.count(bytes([13]))} CR byte(s) in the generated file")

with tempfile.TemporaryDirectory() as td:
    # 3a. old index far bigger than root+topic -> genuinely cheaper
    repo = Path(td) / "repo"
    build_repo(repo, 2, "# Index\n\n" + ("- [E0](ops/e0.md) — " + "x" * 200 + "\n") * 60)
    out = run_main(repo)
    ok("5 a smaller lookup reports CHEAPER",
       "CHEAPER" in out and "MORE EXPENSIVE" not in out, out.strip()[-160:])

with tempfile.TemporaryDirectory() as td:
    # 3b. old index tiny (already split) -> the new shape costs MORE, and must say so
    repo = Path(td) / "repo"
    build_repo(repo, 40, "# Index\n\n- [ops](ops/INDEX.md) — 40 entries\n")
    out = run_main(repo)
    ok("6 a larger lookup reports MORE EXPENSIVE, never 'cheaper'",
       "MORE EXPENSIVE" in out and "x CHEAPER" not in out, out.strip()[-160:])

print()
if fails:
    print(f"shared-memory-index: {len(fails)} fixture(s) FAILED")
    sys.exit(1)
print("shared-memory-index: all fixtures pass")
