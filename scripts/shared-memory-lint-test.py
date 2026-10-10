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


def fm(name: str, *, typ="reference", von="alex-macos", audience="alle-collaborator",
       topic="ops", date="2026-09-13", body="body") -> str:
    # `date` is part of the convention since 2026-09-13, so a VALID fixture entry
    # carries one; pass date="" to build the legacy shape on purpose.
    meta = "\n".join(
        f"  {k}: {v}" for k, v in
        (("type", typ), ("von", von), ("audience", audience), ("topic", topic),
         ("date", date)) if v)
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
        if row and row["von"] == "alex-macos" and row["topic"] == "ops" and row["indexed"]:
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


        # 28. the drift finding must NAME its remedy. That sentence is the generator's
        #     trigger: the tool is hand-run, so the only thing that can send someone to it
        #     is the finding itself. Without this the generator is a carrier with no
        #     trigger — the class the register calls exactly that.
        (repo / "ops" / "INDEX.md").unlink(missing_ok=True)
        idx.write_text(keep, encoding="utf-8")
        (repo / "ops" / "nudge.md").write_text(fm("nudge"), encoding="utf-8")
        b2 = tmp / "empty-baseline.txt"
        res = sml.lint(repo, b2)["findings"]["index_drift"]
        if res and any("shared-memory-index.py" in (f.get("fix") or "") for f in res):
            ok("28 drift finding names the generator as its remedy")
        else:
            bad(f"28 remedy not named: {res[:1]}")
        (repo / "ops" / "nudge.md").unlink()

        # 29-31. `date` joined the convention on 2026-09-13 — same ratchet as the other
        #     three fields, so both directions get a case, plus the shape check.
        (repo / "ops" / "INDEX.md").unlink(missing_ok=True)
        idx.write_text(keep + "- [Old](ops/old.md) — o\n", encoding="utf-8")
        (repo / "ops" / "old.md").write_text(fm("old", date=""), encoding="utf-8")
        check("29 a new file without `date` is a convention finding",
              run(repo), "frontmatter", 1)
        b3 = tmp / "date-baseline.txt"
        b3.write_text("ops/old.md\n", encoding="utf-8")
        check("30 NEGATIVE: the same file in the baseline is exempt",
              run(repo, b3), "frontmatter", 0)
        (repo / "ops" / "old.md").write_text(fm("old", date="13.09.2026"), encoding="utf-8")
        res = sml.lint(repo, b3)["findings"]["frontmatter"]
        if any(f.get("issue") == "metadata.date not YYYY-MM-DD" for f in res):
            ok("31 a date in the wrong shape is named, not silently unfilterable")
        else:
            bad(f"31 wrong-shape date not flagged: {res}")
        (repo / "ops" / "old.md").unlink()
        idx.write_text(keep, encoding="utf-8")

        # 32-40. PROJECT WITHOUT AN AREA (measured 2026-10-10: whole projects filed in the
        #     catch-all because no rule said when an area is due). Own sandbox, so the cases
        #     above stay independent of it.
        repo = build(tmp / "areas")
        idx = repo / "INDEX.md"
        base = idx.read_text(encoding="utf-8")

        def put(stem: str, body: str = "body", topic: str = "ops") -> None:
            (repo / topic).mkdir(exist_ok=True)
            (repo / topic / f"{stem}.md").write_text(
                fm(stem, topic=topic, von="kim-win", audience="sam-laptop", body=body),
                encoding="utf-8")
            with open(idx, "a", encoding="utf-8", newline="\n") as fh:
                fh.write(f"- [{stem}]({topic}/{stem}.md) — x\n")

        def areas(**kw) -> list:
            return sml.lint(repo, tmp / "empty-baseline.txt", **kw)["findings"][
                "project_without_area"]

        put("request-kiosk-display-2026-09-01")
        put("answer-kiosk-display-2026-09-02")
        put("kiosk-power-plan")
        res = areas()
        if len(res) == 1 and "kiosk" in res[0]["signal"] and res[0]["count"] == 3:
            ok("32 three catch-all entries sharing a project word -> one advisory")
        else:
            bad(f"32 planted slug cluster: {res}")

        # 33. NEGATIVE CONTROL: the check switched off misses the planted case — so 32 is
        #     the check's doing, not a side effect of another category.
        check("33 control: check disabled misses the planted cluster",
              {"project_without_area": len(areas(area_min=0))}, "project_without_area", 0)

        # 34. below the threshold (two files) and generic words stay silent; so does a party
        #     name taken from von/audience (`kim`) and a request word (`request`)
        (repo / "ops" / "kiosk-power-plan.md").unlink()
        put("request-to-kim-alpha")
        put("request-to-kim-beta")
        put("lighting-cue-list")
        check("34 two files, generic words, party names: silent",
              {"project_without_area": len(areas())}, "project_without_area", 0)

        # 35. the same project repo named in three bodies — URL, issue reference, bare
        #     owner/repo — is one advisory even with three unrelated slugs
        put("north-stage-cabling", body="Repo: https://github.com/acme/widget-rig")
        put("rental-quote", body="See acme/widget-rig#4 for the list.")
        put("power-budget", body="Numbers live in acme/widget-rig, file docs/power.md.")
        res = areas()
        if [r["signal"] for r in res] == ["acme/widget-rig"]:
            ok("35 three entries naming the same repo -> one advisory")
        else:
            bad(f"35 repo cluster: {res}")

        # 36. a path `<topic>/<slug>` is not a repo: the owner must be one the repo writes as
        #     a URL or an issue reference somewhere
        for s in ("north-stage-cabling", "rental-quote", "power-budget"):
            (repo / "ops" / f"{s}.md").unlink()
        put("north-look", body="see ops/lighting-cue-list.md, https://github.com/acme/widget-rig")
        put("south-pass", body="see ops/lighting-cue-list.md")
        put("east-try", body="see ops/lighting-cue-list.md")
        check("36 topic paths in bodies are not repo references",
              {"project_without_area": len(areas())}, "project_without_area", 0)

        # 37. the repo's own word list EXTENDS the generic defaults (language data, like the
        #     supersession markers)
        put("kiosk-power-plan")
        (repo / sml.GENERIC_NAME).write_text("# words\nkiosk\n", encoding="utf-8")
        check("37 a word in the repo's generic list is silent",
              {"project_without_area": len(areas())}, "project_without_area", 0)
        (repo / sml.GENERIC_NAME).unlink()

        # 38. the shared word IS an existing area: the advice is to move, not to create
        put("kiosk-history", topic="kiosk")
        res = areas()
        if res and "exists" in res[0]["fix"]:
            ok("38 existing area named in the advice")
        else:
            bad(f"38 existing-area advice missing: {res}")

        # 39. entries already in their area do not count toward a catch-all cluster
        (repo / "ops" / "kiosk-power-plan.md").unlink()
        put("kiosk-power-plan", topic="kiosk")
        check("39 entries in their own area are not clustered",
              {"project_without_area": len(areas())}, "project_without_area", 0)

        # 40. ADVISORY: the planted cluster prints but does not set the exit code
        put("kiosk-spare-parts")
        put("kiosk-transport")
        put("kiosk-insurance")
        # the unlinks above left stale index lines; an exact index keeps the run otherwise clean
        with open(idx, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# Index\n\n" + "".join(
                f"- [{p.stem}]({p.relative_to(repo).as_posix()}) — x\n"
                for p in sml.fact_files(repo)))
        r = subprocess.run([sys.executable, str(ROOT / "scripts" / "shared-memory-lint.py"),
                            "--repo", str(repo), "--baseline", str(tmp / "empty-baseline.txt")],
                           capture_output=True, text=True, encoding="utf-8")
        if r.returncode == 0 and "project_without_area [advisory]" in r.stdout:
            ok("40 advisory printed, exit code 0")
        else:
            bad(f"40 advisory exit/print wrong: rc={r.returncode} {r.stdout[-400:]}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
