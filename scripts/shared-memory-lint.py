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
  7. archive         files whose own body marks them settled (UEBERHOLT / ERLEDIGT /
                     SUPERSEDED / RESOLVED) and that have not been touched in a while

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

The archive check NEVER proposes a deletion. It lists candidates for moving to
`archive/<year>/` with the index line kept as a one-liner — the operator's rule is that
protocols are append-only and nothing here is a fact base to be trimmed on a machine's
say-so.

Usage: shared-memory-lint.py [--repo DIR] [--json] [--write-baseline]
       (--repo defaults to $SHARED_MEMORY_REPO, else ~/Projects/brain-shared-memory)
Exit 0 = clean, 1 = findings, 2 = unreadable.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
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
# The index itself is the "keep it compact" signal the operator actually asked for. It is
# NOT a harness limit — this index is read on demand, nothing truncates it — so exceeding
# it is a cost finding, and the fix is archiving settled entries, never trimming the text
# of live ones.
MAX_INDEX_BYTES = 60_000
LOG_ROTATE_BYTES = 60_000
ARCHIVE_STALE_DAYS = 120

WIKILINK = re.compile(r"\[\[([^\]|#]+)")
INDEX_LINK = re.compile(r"\[[^\]]*\]\(([^)]+\.md)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
# A wikilink target is a slug, optionally prefixed with its topic folder. Anything with
# whitespace, quotes or shell metacharacters is not a link — measured: `[[ "$(cat …)" ]]`
# in a bash snippet parsed as a wikilink and was reported as a dead one.
SLUGISH = re.compile(r"^[A-Za-z0-9._/-]+$")
SETTLED = re.compile(
    r"\b(UEBERHOLT|ÜBERHOLT|SUPERSEDED|ERLEDIGT|RESOLVED|ABGESCHLOSSEN|OBSOLET)\b")


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


def last_touched_days(repo: Path, rel: str) -> int | None:
    """Days since the file's last commit. git is the only honest source here — a
    working-tree mtime says when the file was CHECKED OUT, not when it was written,
    and on a fresh clone that is today for every file in the repo."""
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", "-1", "--format=%ct", "--", rel],
            capture_output=True, text=True, timeout=20)
        stamp = out.stdout.strip()
        if not stamp:
            return None
        import time
        return int((time.time() - int(stamp)) / 86400)
    except Exception:
        return None


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
        if rel.name == LOG_NAME:
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

    # 1. index drift — both directions. Index links are repo-relative paths here,
    # not bare stems: the repo is nested, and two topics may hold the same slug.
    linked = {m for m in INDEX_LINK.findall(index_text)}
    linked_files = {ln for ln in linked if not ln.endswith("/")}
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
        f["limits"].append({"issue": "INDEX.md over the compactness budget",
                            "bytes": idx_bytes, "max": MAX_INDEX_BYTES,
                            "fix": "archive settled entries (see the archive findings); "
                                   "do not trim live entries"})
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

        # 7. archive candidates — settled AND cold. Either alone is not enough: a
        # finding closed yesterday is still what everyone is reading this week.
        if SETTLED.search(text):
            age = last_touched_days(repo, rel)
            if age is not None and age >= ARCHIVE_STALE_DAYS:
                f["archive"].append({"file": rel, "days_since_last_commit": age,
                                     "fix": f"move to archive/<year>/, keep a one-line "
                                            f"index entry pointing at the new path"})

    for miss in sorted(baseline - rels):
        f["baseline"].append({"file": miss, "issue": "baseline entry has no file",
                              "fix": "remove the stale line from .shared-memory-legacy.txt"})

    return {"findings": f, "counts": {k: len(v) for k, v in f.items()}, "scanned": len(files)}


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
    ap.add_argument("--baseline", type=Path, default=None,
                    help=f"ratchet baseline (default: <repo>/{BASELINE_NAME})")
    a = ap.parse_args()

    if not a.repo.is_dir():
        print(f"ERROR: shared-memory repo not found: {a.repo}", file=sys.stderr)
        return 2
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
