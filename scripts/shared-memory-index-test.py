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
        with open(root / "ops" / f"e{i}.md", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(entry(f"e{i}", f"Description number {i}."))
    with open(root / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(index_text)


def run_main_args(repo, extra):
    argv = ["shared-memory-index.py", "--repo", str(repo)] + list(extra)
    old = sys.argv
    sys.argv = argv
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            smi.main()
    finally:
        sys.argv = old
    return buf.getvalue()


def run_main(repo, write=False):
    return run_main_args(repo, ["--write"] if write else [])


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

with tempfile.TemporaryDirectory() as td:
    # 7-11. FRESHNESS (2026-09-13). The operator's order: the register must be filterable
    # by date. Two sources, told apart in the index; the git date is pinned in the fixture
    # so the assertions do not drift with the calendar.
    import os, subprocess
    repo = Path(td) / "repo"
    (repo / "ops").mkdir(parents=True)
    with open(repo / "ops" / "dated.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(entry("dated", "Has a date.").replace("  topic: ops\n", "  topic: ops\n  date: 2026-09-01\n"))
    with open(repo / "ops" / "undated.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write(entry("undated", "No date."))
    with open(repo / "ops" / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# ops\n")
    with open(repo / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Index\n")
    env = dict(os.environ, GIT_AUTHOR_DATE="2026-08-20T12:00:00", GIT_COMMITTER_DATE="2026-08-20T12:00:00")
    for cmd in (["init", "-q"], ["add", "-A"],
                ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "fixture"]):
        subprocess.run(["git", "-C", str(repo)] + cmd, env=env, check=False, capture_output=True)
    root, topics, entries, _ = smi.build(repo)
    by = {e["name"]: e for e in entries}
    ok("7 a frontmatter date is shown as the author's",
       smi.date_mark(by["dated"]) == "2026-09-01", smi.date_mark(by.get("dated", {})))
    ok("8 a file without the field gets its git date, marked ~",
       smi.date_mark(by["undated"]) == "~2026-08-20", smi.date_mark(by.get("undated", {})))
    ok("9 the topic INDEX.md is not an entry", "INDEX" not in by, str(sorted(by)))
    ok("10 root names the newest date per topic", "newest 2026-09-01" in root, root)
    s1 = [e["name"] for e in smi.since(entries, "2026-08-21")]
    s2 = [e["name"] for e in smi.since(entries, "2026-08-01")]
    ok("11 since() filters by the resolved date and sorts newest first",
       s1 == ["dated"] and s2 == ["dated", "undated"], f"{s1} / {s2}")
    # 12. the CLI's count line is the measurement, and it always states the undated count
    out = run_main_args(repo, ["--since", "2026-08-21"])
    ok("12 --since prints the count line with the undated count",
       "since 2026-08-21: 1 entry, 0 undated" in out, out.strip()[-160:])

with tempfile.TemporaryDirectory() as td:
    # 13-15. SELF-INGEST (2026-09-21, reported by the other instance). The root page the
    # generator writes carries topic pointers `- [ops](ops/INDEX.md) — n entries`. They are
    # `- [` lines pointing at real files that are not fact files, so the carry rule read
    # them as foreign and copied them into "Not one-fact entries" — one more generation per
    # run, three standing in the shared repo when it was found. A genuine unmanaged line
    # must still survive, otherwise the fix trades one silent loss for another.
    repo = Path(td) / "repo"
    build_repo(repo, 2, "# Index\n\n- [ops](ops/INDEX.md) — 2 entries\n"
                        "- [tools](ops/tools/README.md) — delivery copy\n")
    (repo / "ops" / "tools").mkdir(parents=True, exist_ok=True)
    with open(repo / "ops" / "tools" / "README.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# tools\n")
    run_main(repo, write=True)
    first = (repo / "INDEX.md").read_text(encoding="utf-8")
    run_main(repo, write=True)
    second = (repo / "INDEX.md").read_text(encoding="utf-8")
    # Asserted on the SECOND page on purpose: on a fresh repo `ops/INDEX.md` does not exist
    # yet while the old root is read, so the first run carries nothing and a first-page
    # assertion passes even with the defect in place. The generation starts at run two.
    ok("13 the generator does not carry its own topic pointers",
       second.count("- [ops](ops/INDEX.md)") == 1, second)
    ok("14 a genuine unmanaged line is still carried",
       "ops/tools/README.md" in first and "ops/tools/README.md" in second, second)
    ok("15 a second run reproduces the same page (no generations)",
       first == second, second)

with tempfile.TemporaryDirectory() as td:
    # 16-23. ROUTING FIELDS (2026-10-14). Entries that use none of the fields keep the line
    # shape of 2026-08-30 (control); an entry that uses them gets exactly what it wrote, plus
    # the direction the generator owns: the back-reference, the "superseded by", the filing
    # into another area, and the per-area OPEN page.
    repo = Path(td) / "repo"
    (repo / "ops").mkdir(parents=True)
    (repo / "show").mkdir(parents=True)

    def put(area, name, extra="", desc="Plain description."):
        text = entry(name, desc).replace("  topic: ops\n", f"  topic: {area}\n  date: 2026-10-10\n{extra}")
        with open(repo / area / f"{name}.md", "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    put("ops", "plain")
    put("ops", "opened", "  status: open\n  next: kim-pc, sam-laptop\n  related: [show/target.md]\n"
                         "  topics: [show]\n")
    put("show", "target", "  status: decided\n  supersedes: show/oldplan.md\n")
    put("show", "oldplan")
    with open(repo / "INDEX.md", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# Index\n")
    root, topics, entries, opens = smi.build(repo, today="2026-10-14")
    ops_ix, show_ix = topics["ops"], topics["show"]
    line = next(ln for ln in ops_ix.splitlines() if "(../ops/plain.md)" in ln)
    ok("16 control: an entry without fields keeps the old line shape",
       line == "- [plain](../ops/plain.md) — Plain description. · for: y · 2026-10-10", line)
    line = next(ln for ln in ops_ix.splitlines() if "(../ops/opened.md)" in ln)
    ok("17 status, next and related appear on the entry's own line",
       " · open · next: kim-pc, sam-laptop · related: [target](../show/target.md)" in line, line)
    line = next(ln for ln in show_ix.splitlines() if ln.startswith("- [target](../show/target.md)"))
    ok("18 the back-reference is written into the OTHER entry's line",
       "linked from: [opened](../ops/opened.md)" in line and "decided" in line
       and "supersedes [oldplan](../show/oldplan.md)" in line, line)
    line = next(ln for ln in show_ix.splitlines() if "(../show/oldplan.md)" in ln)
    ok("19 a superseded entry points at its successor",
       "superseded by [target](../show/target.md)" in line, line)
    ok("20 an entry is filed into a further area through topics, marked with its home",
       "## Filed here from other areas (1)" in show_ix
       and "[opened](../ops/opened.md)" in show_ix and "filed from ops" in show_ix, show_ix)
    ok("21 OPEN.md lists the open entry with next and age; a closed area gets none",
       set(opens) == {"ops", "show"} and "- next: kim-pc, sam-laptop · 4 d — [opened](../ops/opened.md)" in opens["ops"]
       and "filed from ops" in opens["show"], str(opens))
    ok("22 the root pointer line carries the open count and nothing else new",
       "- [ops](ops/INDEX.md) — 2 entries · newest 2026-10-10 · 1 open" in root
       and "- [show](show/INDEX.md) — 2 entries · newest 2026-10-10 · 1 open" in root, root)
    # 23. a stale OPEN.md is rewritten as "nothing open", a never-written one is not created,
    #     and the page is not re-ingested as an entry
    run_main(repo, write=True)
    put("ops", "opened", "  status: done\n")
    run_main(repo, write=True)
    ops_open = (repo / "ops" / "OPEN.md").read_text(encoding="utf-8")
    _, _, entries2, opens2 = smi.build(repo)
    ok("23 a stale OPEN.md says nothing open; OPEN.md is not an entry",
       "nothing open." in ops_open and "OPEN" not in {e["name"] for e in entries2}
       and "show" in opens2 and "ops" in opens2, ops_open)

print()
if fails:
    print(f"shared-memory-index: {len(fails)} fixture(s) FAILED")
    sys.exit(1)
print("shared-memory-index: all fixtures pass")
