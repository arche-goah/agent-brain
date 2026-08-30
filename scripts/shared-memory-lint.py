#!/usr/bin/env python3
"""DETERMINISTIC linter for the shared-memory repo — the machine part of the tidy-up.

WHY a second linter instead of pointing memory-lint at it: the two repos have
different shapes and different failure modes. A brain's auto-memory is FLAT, private,
one index, one schema. The shared-memory repo is nested by topic folder, written by
several instances and an external collaborator, and carries LOG protocols alongside
one-fact files. Pointing the flat linter at it reports the folder structure itself as
drift — measured before this script existed.

The operator ordered the tidy-up as a repeatable procedure, not a one-off cleanup
(2026-08-21: keep the shared memory compact, archive stale entries and logs, make hits
efficient, keep what matters prominent). This script is its deterministic half: it
answers what a machine can decide. Duplicates and contradictions stay a judgment call
and belong to the read-only LLM pass, the same split memory-lint and memory-dream use.

CHECKS (all read-only, no writes, stdlib only):
  1. index-drift     INDEX.md line without a file / file without an index line
  2. frontmatter     name + description + metadata.type present and valid;
                     metadata.von / audience / topic required for NEW files —
                     see the RATCHET note below
  3. name-mismatch   frontmatter `name` != filename stem
  4. topic-mismatch  frontmatter `topic` != the folder the file sits in (the field is
                     deliberately redundant with the path so a file carries its domain
                     out of the tree — a copy, a search hit, an index line)
  5. unresolved-links [[wikilink]] with no target file in THIS repo — a typo, or a
                     pointer into a private instance memory that a collaborator cannot
                     follow. Both are worth seeing; only the author can tell them apart.
  6. limits          INDEX entry line longer than the cap; a LOG over the rotation size
  7. archive         entries a NAMED SUCCESSOR supersedes — relevance, never age (see
                     the note at SUPERSESSION_DEFAULT). Age is not in this check at all.

RATCHET (same shape as english-only.py, and for the same reason): the audience/topic
convention was decided on 2026-08-21 with the explicit note that older files are
LEGACY, not violations, and get carried over during a tidy-up rather than ad hoc. A
plain check would therefore be permanently red and train everyone to ignore it. So the
files that predate the convention live in a frozen baseline (one repo-relative path per
line) and the check enforces two directions: a file NOT in the baseline must carry the
fields, and a file IN the baseline that now carries them must be REMOVED from the
baseline. The baseline only ever shrinks.

The baseline file lives IN the linted repo (`.shared-memory-legacy.txt` at its root),
not next to this script — see the note at BASELINE_NAME. Short version: this repo is
public, that one is not.

The archive check NEVER proposes a deletion, and never fires on age. It lists only
entries a named successor has superseded, for moving to `archive/<year>/` with the index
line kept as a one-liner pointing at both the new path and the successor. The operator's
rule: protocols are append-only, nothing here is a fact base to be trimmed on a machine's
say-so, and a decision must stay traceable years later — so what has no successor stays
where it is, however old.

Usage: shared-memory-lint.py [--repo DIR] [--json] [--write-baseline]
       (--repo defaults to $SHARED_MEMORY_REPO, else ~/Projects/brain-shared-memory)
Exit 0 = clean, 1 = findings, 2 = unreadable.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

REPO_DEFAULT = Path(os.environ.get("SHARED_MEMORY_REPO", Path.home() / "Projects/brain-shared-memory"))

# The ratchet baseline lives IN the repo it describes, never next to this script.
# THIS repo is public; the shared-memory repo is private. A baseline sitting here would
# publish 109 file paths of a private collaboration — its topic slugs, who wrote to whom,
# how the work is cut. It also belongs there for a second reason: every instance and the
# external collaborator lint the same data and must see the same baseline, and a
# per-checkout copy of it would drift instantly.
BASELINE_NAME = ".shared-memory-legacy.txt"


def baseline_for(repo: Path) -> Path:
    return repo / BASELINE_NAME

INDEX = "INDEX.md"
# Root files that are not one-fact entries and are not indexed like one.
ROOT_EXEMPT = {INDEX, "README.md", "PEOPLE.md"}
# A LOG is an append-only protocol, not a fact file: no frontmatter schema, no index
# line required, but it is the thing that grows without bound, so it gets a size check.
LOG_NAME = "LOG.md"

# From the repo's OWN README (section Format), not from the brain's auto-memory schema:
# this repo has `decision` and does not have `user`. Copying the brain's four across
# would have reported three correct files as invalid — checked before, not after.
VALID_TYPES = {"project", "feedback", "reference", "decision"}
# Both caps were MEASURED against the real index (129 entries) rather than guessed: the
# entry length distribution runs median 605, p75 860, p90 1115, max 1677. A cap at 900
# flags a fifth of all entries — a check that red is a check nobody reads. 1200 flags the
# five genuine runaways, which is a list someone can act on.
MAX_INDEX_LINE = 1200
# The index budget, set from MEASUREMENT rather than feel (2026-08-30, on the real repo):
# INDEX.md 91,185 chars, median fact file 4,167 — so reading the index costs about what
# opening 22 files costs, while the whole corpus is 797,000 chars. Two facts decide the
# number, and both are arithmetic on those measured sizes. Disk is free but CONTEXT is
# not: a megabyte-sized index is roughly 270k tokens, which does not fit a 200k-context
# model at all and takes a quarter of a 1M one for a single lookup. And the index is read
# WHOLE — there is no partial read of a lookup table you are scanning for a name — so its
# size is paid in full on every read, unlike the corpus behind it.
#
# NOT claimed here, because it was never measured: how OFTEN the index is read. An earlier
# draft of this comment asserted "the index every time" and multiplied it out over twenty
# sessions. No read was ever counted, and the instance rule that governs this repo says
# the opposite — INDEX.md is read on demand. The threshold does not need the frequency:
# cost-per-read and the hard context ceiling carry it on their own.
#
# 50,000 is therefore not "delete above this", it is "the topic split is now due": a root
# index carrying one pointer line per topic plus what is genuinely open, and per-topic
# index files beneath it. That pattern is already proven in the brain's own auto-memory
# (MEMORY.md + index-<topic>.md). Crossing this line means RESTRUCTURE, never trim the
# text of live entries and never delete.
MAX_INDEX_BYTES = 50_000
LOG_ROTATE_BYTES = 60_000

WIKILINK = re.compile(r"\[\[([^\]|#]+)")
INDEX_LINK = re.compile(r"\[[^\]]*\]\(([^)]+\.md)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
# A wikilink target is a slug, optionally prefixed with its topic folder. Anything with
# whitespace, quotes or shell metacharacters is not a link — measured: `[[ "$(cat …)" ]]`
# in a bash snippet parsed as a wikilink and was reported as a dead one.
SLUGISH = re.compile(r"^[A-Za-z0-9._/-]+$")
# ARCHIVING IS RELEVANCE-BASED, NEVER AGE-BASED (operator instruction 2026-08-30:
# archiving must not be time-based; a relevant decision has to stay traceable years later).
#
# The first version of this check was wrong twice over, and both errors point the same
# way. It keyed on (a) 120 days without a commit and (b) a settled marker in the file's
# own body — so an untouched three-year-old decision scored as archivable, and a row
# saying ERLEDIGT scored HIGHEST, when a settled decision is exactly the one somebody
# has to be able to trace later. Age measures attention, not relevance; "done" marks a
# record, not a leftover.
#
# What actually makes an entry archivable is that its content SURVIVES SOMEWHERE ELSE:
# a named successor exists and points back at it. Then nothing is lost by moving the
# original — the fact lives in the successor, the history lives in archive/<year>/, and
# the index line keeps a one-liner pointing at the new path. An entry that nothing
# supersedes stays where it is, whatever its age.
#
# Supersession phrasing is language DATA, and English-only HERE on purpose: this repo is
# public and a word list is data, not code (the same ratchet rejected an earlier draft of
# this file for exactly that). A repo written in another language ships its own tokens in
# `.shared-memory-markers.txt`, one per line; config REPLACES these defaults rather than
# extending them, so such a repo lists both languages there.
SUPERSESSION_DEFAULT = ["SUPERSEDES", "REPLACES", "SUPERSEDED BY", "REPLACED BY",
                        "OVERTAKEN BY", "RETIRED BY"]
MARKERS_NAME = ".shared-memory-markers.txt"


def supersession_re(repo: Path) -> "re.Pattern[str]":
    try:
        toks = [ln.strip() for ln in (repo / MARKERS_NAME).read_text(encoding="utf-8")
                .splitlines() if ln.strip() and not ln.startswith("#")]
    except FileNotFoundError:
        toks = []
    return re.compile(r"\b(" + "|".join(re.escape(t) for t in (toks or SUPERSESSION_DEFAULT))
                      + r")\b", re.I)


def frontmatter(text: str) -> dict | None:
    """Minimal YAML frontmatter parser — only what this schema needs.
    Deliberately NO yaml import: this runs without pip, like the rest of scripts/."""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    out: dict = {}
    section = None
    for raw in text[3:end].splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indented = raw[:1].isspace()
        line = raw.strip()
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if indented and section:
            out.setdefault(section, {})[k] = v
        elif v == "":
            section = k
            out.setdefault(k, {})
        else:
            section = None
            out[k] = v
    return out


def load_baseline(path: Path) -> set[str]:
    try:
        return {ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
                if ln.strip() and not ln.startswith("#")}
    except FileNotFoundError:
        return set()


def fact_files(repo: Path) -> list[Path]:
    """Every one-fact file: EXACTLY `<topic>/<slug>.md`, nothing else.

    The depth rule is what keeps this honest. A one-fact entry lives directly in its
    topic folder; anything deeper is attached material that happens to be markdown —
    the collaborator's verbatim skill copies under `ops/skills-<instance>/<name>/SKILL.md`
    are the measured case. Linting those as one-fact files produced a name-mismatch and
    an index-drift finding each, for files that are correct exactly as they are (they
    were copied unchanged on purpose). Same for LOGs (append-only protocols), anything
    under archive/, and the root docs."""
    out = []
    for p in sorted(repo.rglob("*.md")):
        rel = p.relative_to(repo)
        if ".git" in rel.parts or "archive" in rel.parts:
            continue
        if len(rel.parts) != 2:            # root docs and nested attachments
            continue
        # A per-topic INDEX.md is an INDEX, not an entry — same shape as memory-lint's
        # index-<topic>.md rule, and the same lesson landing in a third repo: every
        # consumer of the index STRUCTURE has to know that sub-indexes exist. Without
        # this, generating the two-level index made the linter report all 142 entries as
        # missing from the index and the five new topic indexes as schema-less files.
        if rel.name in (LOG_NAME, INDEX):
            continue
        out.append(p)
    return out


def lint(repo: Path, baseline_path: Path | None = None) -> dict:
    f: dict[str, list] = {k: [] for k in (
        "index_drift", "frontmatter", "name_mismatch", "topic_mismatch",
        "unresolved_links", "limits", "archive", "baseline")}

    index_path = repo / INDEX
    if not index_path.is_file():
        f["index_drift"].append({"issue": "INDEX.md missing", "path": str(index_path)})
        return {"findings": f, "counts": {k: len(v) for k, v in f.items()}, "scanned": 0}

    index_text = index_path.read_text(encoding="utf-8", errors="replace")
    files = fact_files(repo)
    rels = {str(p.relative_to(repo)) for p in files}
    stems = {p.stem for p in files}
    baseline = load_baseline(baseline_path or baseline_for(repo))
    supersedes = supersession_re(repo)
    superseded: dict[str, list] = {}

    # 1. index drift — both directions. Index links are repo-relative paths here,
    # not bare stems: the repo is nested, and two topics may hold the same slug.
    linked = {m for m in INDEX_LINK.findall(index_text)}
    # SUB-INDEXES: a `<topic>/INDEX.md` the root links is itself an index, so what IT
    # lists counts as indexed. One level deep, no recursion — the same rule memory-lint
    # already carries for `index-<topic>.md`, and the same lesson arriving in a third
    # place: every consumer of the index STRUCTURE must know sub-indexes exist, not just
    # the one that was fixed first. Without this, splitting the index by topic made all
    # 142 entries read as missing from the index.
    for sub in sorted(ln for ln in linked if ln.endswith(f"/{INDEX}")):
        sub_path = repo / sub
        if not sub_path.is_file():
            continue
        sub_dir = Path(sub).parent
        for m in INDEX_LINK.findall(sub_path.read_text(encoding="utf-8", errors="replace")):
            # topic index lines point back up with `../<topic>/<slug>.md`
            linked.add(os.path.normpath(os.path.join(str(sub_dir), m)).replace("\\", "/"))
    linked_files = {ln for ln in linked if not ln.endswith("/") and not ln.endswith(INDEX)}
    for miss in sorted(linked_files - rels):
        # A link into archive/ or to a root doc is legitimate, just not a fact file.
        if (repo / miss).is_file():
            continue
        f["index_drift"].append({"issue": "index points to a missing file", "target": miss})
    for miss in sorted(rels - linked_files):
        f["index_drift"].append({"issue": "file not in the index", "file": miss})

    # 6a. index size and entry length
    idx_bytes = len(index_text.encode("utf-8"))
    if idx_bytes > MAX_INDEX_BYTES:
        f["limits"].append({"issue": "INDEX.md over budget — the topic split is due",
                            "bytes": idx_bytes, "max": MAX_INDEX_BYTES,
                            "approx_tokens": idx_bytes // 4,
                            "fix": "SPLIT BY TOPIC: a root index with one pointer line per "
                                   "topic plus what is genuinely open, and per-topic index "
                                   "files beneath it (the pattern MEMORY.md + "
                                   "index-<topic>.md already proves). This is a structural "
                                   "change — agree it with the other party. Do NOT trim the "
                                   "text of live entries and do NOT delete: the index is "
                                   "read every time, which is what makes its size cost, not "
                                   "its disk footprint."})
    for i, raw in enumerate(index_text.splitlines(), 1):
        if raw.startswith("- [") and len(raw) > MAX_INDEX_LINE:
            f["limits"].append({"issue": "index entry too long", "line": i,
                                "chars": len(raw), "max": MAX_INDEX_LINE,
                                "entry": raw[:70] + "…"})

    # 6b. LOG rotation candidates
    for log in sorted(repo.rglob(LOG_NAME)):
        if ".git" in log.relative_to(repo).parts:
            continue
        size = log.stat().st_size
        if size > LOG_ROTATE_BYTES:
            f["limits"].append({"issue": "LOG over rotation size",
                                "file": str(log.relative_to(repo)), "bytes": size,
                                "max": LOG_ROTATE_BYTES,
                                "fix": "split into LOG-<month>.md, keep the pointer"})

    for p in files:
        rel = str(p.relative_to(repo))
        text = p.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter(text)
        legacy = rel in baseline

        if fm is None:
            f["frontmatter"].append({"file": rel, "issue": "no frontmatter"})
        else:
            for req in ("name", "description"):
                if not fm.get(req):
                    f["frontmatter"].append({"file": rel, "issue": f"'{req}' missing/empty"})
            meta = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
            t = meta.get("type")
            if not t:
                f["frontmatter"].append({"file": rel, "issue": "metadata.type missing"})
            elif t not in VALID_TYPES:
                f["frontmatter"].append({"file": rel, "issue": f"metadata.type '{t}' invalid",
                                         "allowed": sorted(VALID_TYPES)})
            # The convention fields, ratcheted: required unless the file predates it.
            missing = [k for k in ("von", "audience", "topic") if not meta.get(k)]
            if missing and not legacy:
                f["frontmatter"].append({"file": rel, "issue": "convention fields missing",
                                         "fields": missing,
                                         "note": "since 2026-08-21; add them or, for a "
                                                 "genuinely old file, add it to the baseline"})
            if not missing and legacy:
                f["baseline"].append({"file": rel,
                                      "issue": "carries the fields but is still in the baseline",
                                      "fix": "remove the line from .shared-memory-legacy.txt "
                                             "(the ratchet must click)"})
            # 3. name == filename stem
            if fm.get("name") and fm["name"] != p.stem:
                f["name_mismatch"].append({"file": rel, "frontmatter_name": fm["name"]})
            # 4. topic == folder
            folder = p.relative_to(repo).parts[0] if len(p.relative_to(repo).parts) > 1 else ""
            if meta.get("topic") and folder and meta["topic"] != folder:
                f["topic_mismatch"].append({"file": rel, "topic": meta["topic"],
                                            "folder": folder})

        # 5. dead wikilinks — targets are name slugs, resolved across the whole repo.
        # Code is stripped first (a bash `[[ … ]]` is not a link), and a target may
        # carry its topic folder (`ops/foo`) as well as the bare slug.
        body = text.split("\n---", 1)[-1] if fm is not None else text
        prose = INLINE_CODE.sub("", FENCE.sub("", body))
        for target in WIKILINK.findall(prose):
            t = target.strip()
            if not t or not SLUGISH.match(t):
                continue
            if t in stems or t.split("/")[-1] in stems:
                continue
            f["unresolved_links"].append({"file": rel, "target": t, "note": "not a file in THIS repo — either a typo or a pointer into a private instance memory, which no collaborator can follow"})

        # 7. supersession RELATIONS — pairs, not verdicts. A supersession sentence that
        # also names a resolvable entry links two files; which of the two may move is a
        # judgment this script does not make, for two measured reasons:
        #   - the direction is written both ways in practice. This repo's own convention
        #     is the SUPERSEDED file marking itself (a banner at its own top saying which of
        #     its sections are retired), while a successor announcing "this replaces X" is
#     just as valid;
        #   - real supersession is often PARTIAL — that same line retires two sections of
        #     a file whose remaining sections still hold. Moving the file would take the
        #     survivors with it.
        # So the machine surfaces the relation and the evidence line; the judging pass and
        # the author decide whether the content fully survives elsewhere.
        for line in prose.splitlines():
            if not supersedes.search(line):
                continue
            for t in WIKILINK.findall(line):
                t = t.strip().split("/")[-1]
                if t in stems and t != p.stem:
                    key = tuple(sorted((p.stem, t)))
                    superseded.setdefault(key, []).append({"marker_in": rel, "names": t,
                                                           "line": line.strip()[:180]})

    for (a, b), ev in sorted(superseded.items()):
        f["archive"].append({
            "pair": [a + ".md", b + ".md"],
            "marker_in": ev[0]["marker_in"],
            "evidence": ev[0]["line"],
            "fix": "DECIDE first whether the content of one side survives COMPLETELY in "
                   "the other — partial supersession is not an archive case. If it does: "
                   "move that file to archive/<year>/ and keep a one-line index entry "
                   "pointing at both the new path and the successor. Never delete, and "
                   "never on age: a decision must stay traceable years later.",
        })

    for miss in sorted(baseline - rels):
        f["baseline"].append({"file": miss, "issue": "baseline entry has no file",
                              "fix": "remove the stale line from .shared-memory-legacy.txt"})

    return {"findings": f, "counts": {k: len(v) for k, v in f.items()}, "scanned": len(files)}


def inventory(repo: Path) -> dict:
    """The repo's file table as DATA — path, von, type, audience, topic, description,
    indexed yes/no, plus the LOGs and their sizes.

    Why this lives here and not in a prompt: the judging pass needs this table so its
    lenses can target their reads, and an agent asked to produce it can satisfy the
    schema with a one-row SUMMARY of the repo instead of a row per file. That is not a
    hypothetical — it is what the first real run returned (count: 1, path: the repo
    root), leaving four analysis lenses working from nothing. Enumeration is mechanical,
    so it belongs to the machine; the agent that calls this only has to pass the output
    on unchanged."""
    idx = (repo / INDEX)
    index_text = idx.read_text(encoding="utf-8", errors="replace") if idx.is_file() else ""
    linked = set(INDEX_LINK.findall(index_text))
    rows = []
    for p in fact_files(repo):
        rel = str(p.relative_to(repo))
        fm = frontmatter(p.read_text(encoding="utf-8", errors="replace")) or {}
        meta = fm.get("metadata") if isinstance(fm.get("metadata"), dict) else {}
        rows.append({
            "path": rel,
            "von": meta.get("von") or fm.get("von") or "",
            "type": meta.get("type") or "",
            "audience": meta.get("audience") or fm.get("audience") or "",
            "topic": meta.get("topic") or "",
            "description": (fm.get("description") or "")[:240],
            "indexed": rel in linked,
        })
    logs = []
    for log in sorted(repo.rglob(LOG_NAME)):
        if ".git" in log.relative_to(repo).parts:
            continue
        logs.append({"path": str(log.relative_to(repo)), "bytes": log.stat().st_size})
    return {"count": len(rows), "files": rows, "logs": logs,
            "index_bytes": len(index_text.encode("utf-8"))}


def write_baseline(repo: Path, baseline_path: Path | None = None) -> int:
    """Freeze the CURRENT set of files missing convention fields. Run once, at
    introduction — afterwards the list may only shrink, which is the whole point."""
    rows = []
    for p in fact_files(repo):
        fm = frontmatter(p.read_text(encoding="utf-8", errors="replace"))
        meta = (fm or {}).get("metadata")
        meta = meta if isinstance(meta, dict) else {}
        if any(not meta.get(k) for k in ("von", "audience", "topic")):
            rows.append(str(p.relative_to(repo)))
    baseline_path = baseline_path or baseline_for(repo)
    baseline_path.write_text(
        "# Files predating the audience/topic convention (2026-08-21). This list may\n"
        "# only ever SHRINK: carry a file over, then delete its line here.\n"
        + "\n".join(sorted(rows)) + "\n", encoding="utf-8")
    print(f"baseline written: {len(rows)} legacy file(s) -> {baseline_path}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, default=REPO_DEFAULT)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--inventory", action="store_true",
                    help="emit the file table as JSON and exit (no findings, always 0)")
    ap.add_argument("--baseline", type=Path, default=None,
                    help=f"ratchet baseline (default: <repo>/{BASELINE_NAME})")
    a = ap.parse_args()

    if not a.repo.is_dir():
        print(f"ERROR: shared-memory repo not found: {a.repo}", file=sys.stderr)
        return 2
    if a.inventory:
        print(json.dumps(inventory(a.repo), indent=1, ensure_ascii=False))
        return 0
    if a.write_baseline:
        return write_baseline(a.repo, a.baseline)

    r = lint(a.repo, a.baseline)
    total = sum(r["counts"].values())
    if a.json:
        print(json.dumps(r, indent=2, ensure_ascii=False))
        return 1 if total else 0

    if not total:
        print(f"shared-memory-lint: {r['scanned']} file(s) checked, 0 findings")
        print("all clean (index, frontmatter, topics, links, limits, archive).")
        return 0

    print(f"shared-memory-lint: {r['scanned']} file(s) checked, {total} finding(s)\n")
    for cat, items in r["findings"].items():
        if not items:
            continue
        print(f"  {cat} ({len(items)}):")
        for it in items[:20]:
            print("    - " + ", ".join(f"{k}={v}" for k, v in it.items()))
        if len(items) > 20:
            print(f"    … {len(items) - 20} more")
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
