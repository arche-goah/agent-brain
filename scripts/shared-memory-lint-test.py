#!/usr/bin/env python3
"""covers: shared-memory-lint

Both directions, and the negative half carries the weight. Every "must stay silent"
case below is one the instrument ACTUALLY got wrong during development, measured
against the real repo before this test existed:

  - a bash `[[ "$(cat …)" ]]` snippet parsed as a wikilink and was reported dead;
  - the collaborator's verbatim skill copies under `ops/skills-<x>/<name>/SKILL.md`
    were linted as one-fact files and produced a name-mismatch plus an index-drift
    finding each, for files that are correct exactly as copied;
  - `metadata.type: decision` was reported invalid because the schema had been copied
    from the brain's auto-memory instead of read from this repo's own README;
  - an entry-length cap picked by feel flagged a fifth of all index entries.

Run: scripts/shared-memory-lint-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("sml", ROOT / "scripts" / "shared-memory-lint.py")
sml = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sml)

fails = 0


def ok(msg: str) -> None:
    print(f"  ok    {msg}")


def bad(msg: str) -> None:
    global fails
    fails += 1
    print(f"  FAIL  {msg}")


def check(name: str, counts: dict, category: str, want: int) -> None:
    got = counts.get(category, 0)
    if got == want:
        ok(f"{name} ({category}={got})")
    else:
        bad(f"{name}: {category}={got}, expected {want}")


def fm(name: str, *, typ="reference", von="emil-macos", audience="alle-collaborator",
       topic="ops", body="body") -> str:
    meta = "\n".join(
        f"  {k}: {v}" for k, v in
        (("type", typ), ("von", von), ("audience", audience), ("topic", topic)) if v)
    return f'---\nname: {name}\ndescription: "d"\nmetadata:\n{meta}\n---\n\n{body}\n'


def build(tmp: Path) -> Path:
    """A minimal but VALID repo: two topics, one indexed fact file each."""
    repo = tmp / "repo"
    (repo / "ops").mkdir(parents=True)
    (repo / "grandma3").mkdir(parents=True)
    (repo / "ops" / "alpha.md").write_text(fm("alpha"), encoding="utf-8")
    (repo / "grandma3" / "beta.md").write_text(
        fm("beta", topic="grandma3"), encoding="utf-8")
    (repo / "README.md").write_text("readme\n", encoding="utf-8")
    (repo / "PEOPLE.md").write_text("people\n", encoding="utf-8")
    (repo / "INDEX.md").write_text(
        "# Index\n\n- [Alpha](ops/alpha.md) — a\n- [Beta](grandma3/beta.md) — b\n",
        encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "init", "-q"], check=False)
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=False)
    subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-qm", "fixture"], check=False)
    return repo


def run(repo: Path, baseline: Path | None = None) -> dict:
    b = baseline or (repo.parent / "empty-baseline.txt")
    if not b.exists():
        b.write_text("# empty\n", encoding="utf-8")
    return sml.lint(repo, b)["counts"]


def main() -> int:
    print("shared-memory-lint:")
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        # 1. a clean repo is silent — the baseline every other case is measured against
        repo = build(tmp)
        c = run(repo)
        if sum(c.values()) == 0:
            ok("1 clean repo: no findings")
        else:
            bad(f"1 clean repo reported {c}")

        # 2. file present, not in the index
        (repo / "ops" / "orphan.md").write_text(fm("orphan"), encoding="utf-8")
        check("2 file missing from the index", run(repo), "index_drift", 1)
        (repo / "ops" / "orphan.md").unlink()

        # 3. index points at a file that does not exist
        idx = repo / "INDEX.md"
        keep = idx.read_text(encoding="utf-8")
        idx.write_text(keep + "- [Ghost](ops/ghost.md) — g\n", encoding="utf-8")
        check("3 index points at a missing file", run(repo), "index_drift", 1)
        idx.write_text(keep, encoding="utf-8")

        # 4. convention fields missing and NOT in the baseline -> finding
        (repo / "ops" / "nofields.md").write_text(
            fm("nofields", von="", audience="", topic=""), encoding="utf-8")
        idx.write_text(keep + "- [NoFields](ops/nofields.md) — n\n", encoding="utf-8")
        check("4 convention fields missing, not in baseline", run(repo), "frontmatter", 1)

        # 5. same file, now IN the baseline -> silent (legacy is not a violation)
        bl = tmp / "bl.txt"
        bl.write_text("ops/nofields.md\n", encoding="utf-8")
        check("5 same file listed as legacy", run(repo, bl), "frontmatter", 0)

        # 6. RATCHET: a baseline file that HAS the fields must leave the baseline
        (repo / "ops" / "nofields.md").write_text(fm("nofields"), encoding="utf-8")
        check("6 baseline file now carries the fields", run(repo, bl), "baseline", 1)

        # 7. a baseline line whose file is gone is stale
        bl.write_text("ops/nofields.md\nops/vanished.md\n", encoding="utf-8")
        check("7 baseline entry without a file", run(repo, bl), "baseline", 2)
        (repo / "ops" / "nofields.md").unlink()
        idx.write_text(keep, encoding="utf-8")

        # 8. topic field disagreeing with the folder
        (repo / "grandma3" / "wrongtopic.md").write_text(
            fm("wrongtopic", topic="ops"), encoding="utf-8")
        idx.write_text(keep + "- [W](grandma3/wrongtopic.md) — w\n", encoding="utf-8")
        check("8 topic != folder", run(repo), "topic_mismatch", 1)
        (repo / "grandma3" / "wrongtopic.md").unlink()

        # 9. frontmatter name disagreeing with the filename
        (repo / "ops" / "slug.md").write_text(fm("different-name"), encoding="utf-8")
        idx.write_text(keep + "- [S](ops/slug.md) — s\n", encoding="utf-8")
        check("9 name != filename stem", run(repo), "name_mismatch", 1)
        (repo / "ops" / "slug.md").unlink()
        idx.write_text(keep, encoding="utf-8")

        # 10. NEGATIVE: a wikilink to an existing file, and one written topic/slug —
        #     both resolve, neither is a finding
        (repo / "ops" / "alpha.md").write_text(
            fm("alpha", body="see [[beta]] and [[grandma3/beta]]"), encoding="utf-8")
        check("10 resolvable wikilinks, bare and topic-prefixed", run(repo),
              "unresolved_links", 0)

        # 11. NEGATIVE: `[[ … ]]` inside code is shell, not a link (measured false positive)
        (repo / "ops" / "alpha.md").write_text(
            fm("alpha", body='```bash\nif [[ "$(cat "$LOCK")" == "$$" ]]; then :; fi\n```\n'
                             'and inline `[[ -f x ]]` too'), encoding="utf-8")
        check("11 shell test syntax in code is not a wikilink", run(repo),
              "unresolved_links", 0)

        # 12. a genuinely unresolvable link IS reported
        (repo / "ops" / "alpha.md").write_text(
            fm("alpha", body="see [[does-not-exist]]"), encoding="utf-8")
        check("12 unresolvable wikilink", run(repo), "unresolved_links", 1)
        (repo / "ops" / "alpha.md").write_text(fm("alpha"), encoding="utf-8")

        # 13. NEGATIVE: nested attachments are not one-fact files (measured false positive)
        nested = repo / "ops" / "skills-somewhere" / "a-skill"
        nested.mkdir(parents=True)
        (nested / "SKILL.md").write_text("---\nname: a-skill\n---\nno schema here\n",
                                         encoding="utf-8")
        c = run(repo)
        if c["index_drift"] == 0 and c["frontmatter"] == 0 and c["name_mismatch"] == 0:
            ok("13 nested attachment ignored (index/frontmatter/name all silent)")
        else:
            bad(f"13 nested attachment produced findings: {c}")
        shutil.rmtree(repo / "ops" / "skills-somewhere")

        # 14. NEGATIVE: `decision` is a valid type in THIS repo (README, not the brain schema)
        (repo / "ops" / "alpha.md").write_text(fm("alpha", typ="decision"), encoding="utf-8")
        check("14 metadata.type decision accepted", run(repo), "frontmatter", 0)
        # ... and a domain name in the type field is not
        (repo / "ops" / "alpha.md").write_text(fm("alpha", typ="grandma3"), encoding="utf-8")
        check("15 metadata.type with a domain name rejected", run(repo), "frontmatter", 1)
        (repo / "ops" / "alpha.md").write_text(fm("alpha"), encoding="utf-8")

        # 16. a LOG is not linted as a fact file, but its SIZE is checked
        (repo / "ops" / "LOG.md").write_text("x" * (sml.LOG_ROTATE_BYTES + 10),
                                             encoding="utf-8")
        c = run(repo)
        if c["index_drift"] == 0 and c["frontmatter"] == 0 and c["limits"] == 1:
            ok("16 oversized LOG: size flagged, schema not")
        else:
            bad(f"16 LOG handling wrong: {c}")
        (repo / "ops" / "LOG.md").write_text("short\n", encoding="utf-8")
        check("17 small LOG is silent", run(repo), "limits", 0)
        (repo / "ops" / "LOG.md").unlink()

        # 18. archive: a NAMED SUCCESSOR supersedes an entry -> candidate. Age plays no
        #     part; the fixture does not touch a single timestamp.
        old = repo / "ops" / "settled.md"
        old.write_text(fm("settled", body="The original decision."), encoding="utf-8")
        succ = repo / "ops" / "successor.md"
        succ.write_text(fm("successor", body="SUPERSEDES: [[settled]] — this replaces it."),
                        encoding="utf-8")
        idx.write_text(keep + "- [S](ops/settled.md) — s\n- [N](ops/successor.md) — n\n",
                       encoding="utf-8")
        check("18 successor names the superseded entry -> relation reported",
              run(repo), "archive", 1)


        # 19b. the OTHER direction: the superseded file marks ITSELF and names the
        #      successor. This repo writes it that way, so a check that only understood
        #      "successor announces" would have been blind to its actual convention.
        old.write_text(fm("settled", body="SUPERSEDED BY [[successor]] instead."),
                       encoding="utf-8")
        succ.write_text(fm("successor", body="The new decision."), encoding="utf-8")
        idx.write_text(keep + "- [S](ops/settled.md) — s\n- [N](ops/successor.md) — n\n",
                       encoding="utf-8")
        check("19b self-marked supersession is found too", run(repo), "archive", 1)
        succ.unlink()

        # 19. NEGATIVE — the case that carries the operator's rule: an entry that says
        #     it is DONE, with nothing superseding it, is NOT a candidate — at any age.
        #     A settled decision is exactly what has to stay traceable years later.
        old.write_text(fm("settled", body="ERLEDIGT 2019 — decided, and nothing replaced it."),
                       encoding="utf-8")
        idx.write_text(keep + "- [S](ops/settled.md) — s\n", encoding="utf-8")
        check("19 settled but unsuperseded stays, whatever its age", run(repo), "archive", 0)

        # 20. NEGATIVE: a supersession sentence that names nothing resolvable is not a
        #     candidate either — the successor must SAY which entry it replaces.
        old.write_text(fm("settled", body="SUPERSEDES something, somewhere."),
                       encoding="utf-8")
        check("20 supersession without a named target", run(repo), "archive", 0)

        # 21. NEGATIVE: a file may not supersede itself (a self-link in its own body)
        old.write_text(fm("settled", body="SUPERSEDES: [[settled]] — see above."),
                       encoding="utf-8")
        check("21 self-supersession ignored", run(repo), "archive", 0)

        # 22. the marker list is DATA: a repo naming its own tokens gets those and only
        #     those. Same lesson as the recall-gate word lists.
        old.write_text(fm("settled", body="The original decision."), encoding="utf-8")
        succ.write_text(fm("successor", body="SUPERSEDES: [[settled]] — this replaces it."),
                        encoding="utf-8")
        idx.write_text(keep + "- [S](ops/settled.md) — s\n- [N](ops/successor.md) — n\n",
                       encoding="utf-8")
        (repo / sml.MARKERS_NAME).write_text("ZZZ-NO-SUCH-MARKER\n", encoding="utf-8")
        check("22 repo replaces the marker list", run(repo), "archive", 0)
        (repo / sml.MARKERS_NAME).unlink()
        check("23 default markers back in force", run(repo), "archive", 1)

        # 24. --inventory is a TABLE, one row per fact file. This exists because the
        #     judging workflow had an agent produce it and got back a single summary row
        #     for the whole repo — schema satisfied, four lenses left with nothing.
        inv = sml.inventory(repo)
        facts = sml.fact_files(repo)
        if inv["count"] == len(facts) == len(inv["files"]) and len(facts) > 1:
            ok(f"24 inventory has one row per fact file ({inv['count']})")
        else:
            bad(f"24 inventory row count {inv['count']} vs {len(facts)} fact files")

        # 25. and the rows carry the fields the lenses target their reads with
        row = next((r for r in inv["files"] if r["path"] == "ops/alpha.md"), None)
        if row and row["von"] == "emil-macos" and row["topic"] == "ops" and row["indexed"]:
            ok("25 inventory row carries von / topic / indexed")
        else:
            bad(f"25 inventory row incomplete: {row}")


        # 26. SUB-INDEX: a topic INDEX.md the root links is itself an index, and what it
        #     lists counts as indexed. Same rule memory-lint carries for index-<topic>.md.
        #     Without it, splitting the index by topic reads as 'every entry is missing'.
        for leftover in ("settled.md", "successor.md"):
            (repo / "ops" / leftover).unlink(missing_ok=True)
        (repo / "ops" / "INDEX.md").write_text(
            "# ops\n\n- [Alpha](../ops/alpha.md) — a\n", encoding="utf-8")
        idx.write_text("# Index\n\n- [ops](ops/INDEX.md) — 1\n"
                       "- [Beta](grandma3/beta.md) — b\n", encoding="utf-8")
        check("26 entries listed in a topic sub-index count as indexed",
              run(repo), "index_drift", 0)

        # 27. NEGATIVE: the topic index file itself is not a fact file — no frontmatter
        #     finding, no name mismatch, no index line demanded for it
        c = run(repo)
        if c["frontmatter"] == 0 and c["name_mismatch"] == 0:
            ok("27 topic index is an index, not an entry")
        else:
            bad(f"27 topic index treated as a fact file: {c}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
