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
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import git_sandbox  # noqa: E402,F401 - the host git config never reaches a fixture repo
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
        # 17a. a NEW LOG entry over the entry cap is the writer's finding; an old one is protocol (ratchet)
        long_body = "x" * 400
        (repo / "ops" / "LOG.md").write_text(
            f"## {sml.LOG_CAP_SINCE} · sam-laptop — AN kim-win (status: info): new and long\n{long_body}\n", encoding="utf-8")
        check("17a new LOG entry over the cap flagged", run(repo), "limits", 1)
        (repo / "ops" / "LOG.md").write_text(
            f"## 2026-10-01 · sam-laptop — AN kim-win (status: info): old and long\n{long_body}\n", encoding="utf-8")
        check("17a an entry before the ratchet date is not judged", run(repo), "limits", 0)
        (repo / "ops" / "LOG.md").write_text(
            f"## {sml.LOG_CAP_SINCE} · sam-laptop — AN kim-win (status: info): new and short\nops/fact.md\n", encoding="utf-8")
        check("17a a new short entry is silent", run(repo), "limits", 0)
        # 17b. a dated LOG heading no shape recognises is a finding (reader drops nothing, the
        #      writer hears it); a session after the sender is a KNOWN shape. Negative control
        #      is the pre-fix pattern: it would call the second heading unknown too.
        (repo / "ops" / "LOG.md").write_text(
            "## 2026-10-11 · sam-laptop (docs-session) — AN kim-win: known shape\nBody.\n"
            "\n## 2026-10-11 sam-laptop: [colon form nobody supports]\nBody.\n", encoding="utf-8")
        check("17b unknown LOG heading flagged, qualified sender accepted", run(repo), "audience", 1)
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

        # 31b. a question/answer THREAD on one subject is one conversation, not a project:
        #      proposal, follow-up and answer leave the same words once kind-words, ids and
        #      dates are gone, so they count once (measured on the real repo 2026-10-10).
        put("proposal-lamp-rig-2026-09-01")
        put("followup-lamp-rig")
        put("answer-lamp-rig-2026-09-03")
        check("31b a three-file Q/A thread on one subject stays silent",
              {"project_without_area": len(areas())}, "project_without_area", 0)

        put("request-kiosk-display-2026-09-01")
        put("kiosk-cabling-2026-09-02")
        put("kiosk-power-plan")
        res = areas()
        if len(res) == 1 and "kiosk" in res[0]["signal"] and res[0]["threads"] == 3:
            ok("32 three different subjects sharing a project word -> one advisory")
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

        # 41-49. ROUTING FIELDS (check 10, 2026-10-14). Own sandbox with parties.json and two
        #     areas (folders with a LOG.md). Every finding is planted once and has its silent
        #     control: the same shape written correctly.
        repo = build(tmp / "fields")
        idx = repo / "INDEX.md"
        base = idx.read_text(encoding="utf-8")
        (repo / "ops" / "LOG.md").write_text("log\n", encoding="utf-8")
        (repo / "grandma3" / "LOG.md").write_text("log\n", encoding="utf-8")
        (repo / "parties.json").write_text(
            '{"people": {"kim": {"github": "k", "devices": {"kim-pc": {"os": "windows"}}}}}',
            encoding="utf-8")
        bl = tmp / "fields-baseline.txt"
        bl.write_text("# empty\n", encoding="utf-8")

        def put_fields(stem: str, extra: str, date: str = "2026-10-14") -> None:
            text = fm(stem, date=date, von="kim-pc", audience="kim-pc").replace(
                f"  date: {date}\n", f"  date: {date}\n{extra}")
            (repo / "ops" / f"{stem}.md").write_text(text, encoding="utf-8")
            idx.write_text(base + f"- [{stem}](ops/{stem}.md) — x\n", encoding="utf-8")

        def fields() -> list:
            return sml.lint(repo, bl)["findings"]["fields"]

        put_fields("f1", "  status: open\n  next: kim-pc\n  related: [ops/alpha.md, beta]\n"
                         "  topics: [grandma3]\n  supersedes: ops/alpha.md\n")
        check("41 control: every field used correctly is silent",
              {"fields": len(fields())}, "fields", 0)
        put_fields("f1", "  status: pending\n")
        res = fields()
        check("42 a status outside the vocabulary", {"fields": len(res)}, "fields", 1)
        put_fields("f1", "  status: open\n")
        res = fields()
        if len(res) == 1 and res[0]["issue"] == "status open without next":
            ok("43 open without next (entry dated on/after the rule)")
        else:
            bad(f"43 open without next: {res}")
        put_fields("f1", "  status: open\n", date="2026-10-01")
        check("44 control: an older open entry without next is not re-judged",
              {"fields": len(fields())}, "fields", 0)
        put_fields("f1", "  status: open\n  next: nobody-box\n")
        res = fields()
        if len(res) == 1 and res[0]["issue"].startswith("next names no device"):
            ok("45 next outside parties.json")
        else:
            bad(f"45 next outside parties.json: {res}")
        put_fields("f1", "  related:\n    - ops/alpha.md\n    - ops/vanished.md\n")
        res = fields()
        if len(res) == 1 and res[0].get("target") == "ops/vanished.md":
            ok("46 a dead related path in a block list is named, the live one is not")
        else:
            bad(f"46 dead related: {res}")
        put_fields("f1", "  supersedes: ops/vanished.md\n")
        check("47 a dead supersedes path", {"fields": len(fields())}, "fields", 1)
        put_fields("f1", "  topics: [grandma3, nowhere]\n")
        res = fields()
        if len(res) == 1 and res[0].get("topic") == "nowhere":
            ok("48 topics naming no area is named, the real area is not")
        else:
            bad(f"48 topics: {res}")
        # 49. no parties.json: `next` is not resolved (nothing to resolve against), the
        #     other field checks still run
        (repo / "parties.json").unlink()
        put_fields("f1", "  status: open\n  next: nobody-box\n  supersedes: ops/vanished.md\n")
        res = fields()
        if len(res) == 1 and res[0]["issue"] == "supersedes points at no file":
            ok("49 without parties.json next is not judged, dead paths still are")
        else:
            bad(f"49 without parties.json: {res}")
        # 49b. the generated OPEN.md is an index, not an entry: no frontmatter finding, no
        #      index line demanded
        (repo / "ops" / "f1.md").unlink()
        idx.write_text(base, encoding="utf-8")
        (repo / "ops" / sml.OPEN_NAME).write_text("# ops — open\n\nnothing open.\n", encoding="utf-8")
        c = sml.lint(repo, bl)["counts"]
        if c["frontmatter"] == 0 and c["index_drift"] == 0:
            ok("49b OPEN.md is an index, not an entry")
        else:
            bad(f"49b OPEN.md linted as an entry: {c}")

        # 50-54. AI HANDOVER (check 9b, 2026-10-18). lee handed the AI side of lee's brain to
        #     sam's AIs; a message from sam's AI that sends an AI question back to lee is named.
        repo = build(tmp / "handover")
        (repo / "parties.json").write_text(json.dumps({
            "people": {"sam": {"github": "s", "devices": {"sam-mac": {"os": "macos"}}},
                       "lee": {"github": "l", "devices": {"lee-win": {"os": "windows"}},
                               "ai_handover": {"to": "sam"}}},
            "handover_referral_patterns": ["\\bauf das wort deines menschen\\b"]}), encoding="utf-8")
        bl = tmp / "handover-baseline.txt"
        bl.write_text("# empty\n", encoding="utf-8")

        def handover(log: str) -> list:
            (repo / "ops" / "LOG.md").write_text("# Log\n\n" + log, encoding="utf-8")
            return [i for i in sml.lint(repo, bl)["findings"]["audience"]
                    if i["issue"].startswith("an AI question sent back")]

        res = handover("## 2026-10-18 · sam-mac — AN lee-win: old branches\nDelete them on your human's word.\n")
        ok("50 an AI question sent back to the human who handed it over is named") if len(res) == 1 \
            else bad(f"50 referral missed: {res}")
        res = handover("## 2026-10-18 · sam-mac — AN lee-win: Branches\nLoeschen auf das Wort deines Menschen.\n")
        ok("51 referral wording from parties.json is matched") if len(res) == 1 else bad(f"51 data pattern: {res}")
        res = handover("## 2026-10-18 · sam-mac — AN lee-win: desk\nhandover-keeps: a desk write. "
                       "Only on your human's word.\n")
        ok("52 handover-keeps marks what the handover keeps") if not res else bad(f"52 escape ignored: {res}")
        res = handover("## 2026-10-18 · sam-mac — AN lee-win: old branches\nDecided: delete them.\n")
        ok("53 NEGATIVE: a decision without referral is silent") if not res else bad(f"53 false positive: {res}")
        res = handover("## 2026-10-18 · lee-win — AN sam-mac: question\nShould I wait on your human's word?\n")
        ok("54 NEGATIVE: the other direction is not judged") if not res else bad(f"54 wrong direction: {res}")

        # 55-62. RELATIONS (check 11, written request state). A relation value names a file stem
        #     or a LOG id; from STATE_SINCE on a request to a party is a file, not a bare heading.
        repo = build(tmp / "relations")
        idx = repo / "INDEX.md"
        base = idx.read_text(encoding="utf-8")
        bl = tmp / "relations-baseline.txt"
        bl.write_text("# empty\n", encoding="utf-8")
        new = sml._parties.STATE_SINCE
        (repo / "ops" / "LOG.md").write_text(
            f"# Log\n\n## {new} · kim-pc — AN alex-macos (status: info): ping\nx\n\n"
            f"## {new} · kim-pc — AN alex-macos: see the file\nops/alpha.md\n", encoding="utf-8")
        (repo / "ops" / "archive").mkdir()
        (repo / "ops" / "archive" / "LOG-2026-09.md").write_text(
            "# Log archive\n\n## 2026-09-03 · kim-pc — AN alex-macos: old question\nx\n", encoding="utf-8")

        def put_rel(extra: str, date: str = new) -> list:
            text = fm("r1", date=date).replace(f"  date: {date}\n", f"  date: {date}\n{extra}")
            (repo / "ops" / "r1.md").write_text(text, encoding="utf-8")
            idx.write_text(base + "- [r1](ops/r1.md) — x\n", encoding="utf-8")
            return sml.lint(repo, bl)["findings"]["relations"]

        res = put_rel(f"  answers: ops/LOG@{new}#2\n  closes: alpha\n  claims: ops/LOG@2026-09-03#1\n")
        ok("55 control: a LOG id, a file stem and an archived LOG id resolve") if not res \
            else bad(f"55 valid relations flagged: {res}")
        res = put_rel(f"  answers: ops/LOG@{new}#9\n")
        ok("56 a LOG id that names no heading is named") if len(res) == 1 and res[0]["target"] == f"ops/LOG@{new}#9" \
            else bad(f"56 dead LOG id: {res}")
        res = put_rel("  answers: LOG 2026-10-15 kim-pc — a question in prose\n")
        ok("57 a request named in prose is named") if len(res) == 1 else bad(f"57 prose answer: {res}")
        res = put_rel("  answers: LOG 2026-10-15 kim-pc — a question in prose\n", date="2026-10-15")
        ok("58 control: an entry dated before STATE_SINCE is not re-judged") if not res else bad(f"58 ratchet: {res}")
        (repo / "ops" / "r1.md").unlink()
        idx.write_text(base, encoding="utf-8")

        def heads(log: str) -> list:
            (repo / "ops" / "LOG.md").write_text("# Log\n\n" + log, encoding="utf-8")
            return [i for i in sml.lint(repo, bl)["findings"]["relations"]
                    if i["issue"].startswith("a request to a party")]

        res = heads(f"## {new} · kim-pc — AN alex-macos: please check X\nno file\n")
        ok("59 a request that lives only as a LOG heading is named") if len(res) == 1 else bad(f"59 LOG request: {res}")
        res = heads(f"## {new} · kim-pc — AN alex-macos (status: done): X checked\nok\n")
        ok("60 control: a report heading is silent") if not res else bad(f"60 report flagged: {res}")
        res = heads(f"## {new} · kim-pc — AN alex-macos: please check X\nops/alpha.md\n")
        ok("61 control: a heading that points at its file is silent") if not res else bad(f"61 pointer flagged: {res}")
        res = heads("## 2026-10-15 · kim-pc — AN alex-macos: please check X\nno file\n")
        ok("62 control: a heading before STATE_SINCE is not re-judged") if not res else bad(f"62 ratchet: {res}")

        # 63-67. A LOG id is the heading's place that day: at commit (--staged) the committed
        #     headings of a day must stay that day's start. Insert/edit = shifted ids; append,
        #     a whole day rotated out, or a new heading for a day that had none shift nothing.
        repo = build(tmp / "inserts")
        log = repo / "ops" / "LOG.md"
        base_log = ("# Log\n\n## 2026-09-03 · kim-pc — AN alex-macos (status: info): sept\nx\n\n"
                    "## 2026-10-20 · kim-pc — AN alex-macos (status: info): first\nx\n\n"
                    "## 2026-10-20 · alex-macos — AN kim-pc (status: info): second\nx\n")

        def git(*args: str) -> None:
            subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)

        def staged(text: str) -> list:
            log.write_text(base_log, encoding="utf-8")
            git("add", "-A")
            git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "base")
            log.write_text(text, encoding="utf-8")
            git("add", "-A")
            return [i for i in sml.staged_log_inserts(repo) if "inserted, edited or removed" in i["issue"]]

        res = staged(base_log + "\n## 2026-10-20 · kim-pc — AN alex-macos (status: info): third\nx\n")
        ok("63 control: an appended heading shifts nothing") if not res else bad(f"63 append flagged: {res}")
        res = staged(base_log.replace("## 2026-10-20 · kim-pc", "## 2026-10-20 · kim-pc — AN alex-macos "
                                      "(status: info): inserted\nx\n\n## 2026-10-20 · kim-pc", 1))
        ok("64 a heading inserted above the day's first entry is named") if len(res) == 1 else bad(f"64 insert: {res}")
        res = staged(base_log.replace(": second", ": second, reworded"))
        ok("65 an edited old heading is named") if len(res) == 1 else bad(f"65 edit: {res}")
        res = staged(base_log.replace("## 2026-09-03 · kim-pc — AN alex-macos (status: info): sept\nx\n\n", ""))
        ok("66 control: a whole day rotated out shifts nothing") if not res else bad(f"66 rotation flagged: {res}")
        res = staged(base_log.replace("## 2026-10-20 · kim-pc", "## 2026-09-05 · kim-pc — AN alex-macos "
                                      "(status: info): late\nx\n\n## 2026-10-20 · kim-pc", 1))
        ok("67 control: a new heading for a day that had none shifts nothing") if not res \
            else bad(f"67 new day flagged: {res}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
