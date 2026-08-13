#!/usr/bin/env python3
"""DETERMINISTIC memory linter — the machine, not the interpreter.

WHY (finding 2026-08-02): our audit suite (brain-scan, memory-dream,
kohaerenz-scan) is purely LLM-based and therefore NOT reproducible — two runs
on the same state can produce different findings, and an overlooked dead link
is indistinguishable from "there wasn't one". This script checks the
mechanically checkable part FIRST and always delivers the same result for the
same input. The LLM skills should afterwards only judge what actually needs
judgment.

Idea borrowed from AgriciDaniel/claude-obsidian (MIT) — but its `lint_engine.py`
itself does not fit: it expects a `wiki/` structure, a different frontmatter
schema (title/type/status/created/updated/tags), and knows nothing about our
actual drift class, namely MEMORY.md index <-> files.
Run against our memory it found 0 real findings out of 55 false positives.

CHECKS (all read-only, no writes, stdlib only):
  1. index-drift    MEMORY.md line without a file / file without an index line
  2. frontmatter    name + description + metadata.type present and valid
  3. name-mismatch  frontmatter `name` != filename (slug)
  4. dead-links     [[wikilink]] without a target file
  5. limits         MEMORY.md max 200 lines / 25600 bytes (enforced by harness)
                    + index ENTRY max 400 characters (checklist §5)
  6. snapshot-drift Auto-Memory <-> docs/memory-snapshot/ (our DOUBLE STRUCTURE)

Usage: memory-lint.py [--memory DIR] [--snapshot DIR] [--json]
Exit 0 = clean, 1 = findings, 2 = unreadable.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Auto-Memory path: Claude Code mints the project path into a folder name (/ -> -).
# Core rule: never hardcode an instance path — it is derived from the INSTANCE root
# (cwd or BRAIN_DIR), NOT from this script's own checkout: that sits as a submodule
# under <instance>/core and would mint the wrong folder. --mem overrides.
import os
_INSTANCE = Path(os.environ.get("BRAIN_DIR", Path.cwd())).resolve()
# Claude Code replaces EVERY character except [A-Za-z0-9] with '-', not just '/'. On
# POSIX the difference does not show; on Windows the path is `C:\Users\...\brain`, `/`
# does not appear in it, and the unchanged absolute path resets the whole prefix at
# pathlib's `/` join — the linter then searched `<instance>\memory` and aborted with
# exit 2. A brain that follows the rule "memory lives in Auto-Memory" never has this
# folder. The same minting has lived in helpers/session-bootup.sh since 2026-08-04,
# verified there against real folders on both platforms.
MEM_DEFAULT = (
    Path.home() / ".claude/projects"
    / re.sub(r"[^A-Za-z0-9]", "-", str(_INSTANCE))
    / "memory"
)
SNAP_DEFAULT = _INSTANCE / "docs/memory-snapshot"
INDEX = "MEMORY.md"
VALID_TYPES = {"user", "feedback", "project", "reference"}
MAX_LINES, MAX_BYTES = 200, 25600
MAX_INDEX_LINE = 400   # checklist §5; applies ONLY to entry lines ("- [Title](file.md) — …"),
                       # not to the explanatory header block (otherwise false alarm on prose)

WIKILINK = re.compile(r"\[\[([^\]|#]+)")
INDEX_LINK = re.compile(r"\[[^\]]*\]\(([^)]+\.md)\)")


def frontmatter(text: str) -> dict | None:
    """Minimal YAML frontmatter parser — only what our schema needs.
    Deliberately NO yaml import: the script should run without pip (like the rest)."""
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


def lint(mem: Path, snap: Path | None) -> dict:
    f: dict[str, list] = {k: [] for k in (
        "index_drift", "frontmatter", "name_mismatch",
        "dead_links", "limits", "snapshot_drift")}

    index_path = mem / INDEX
    if not index_path.is_file():
        f["index_drift"].append({"issue": "MEMORY.md missing", "path": str(index_path)})
        return {"findings": f, "counts": {k: len(v) for k, v in f.items()}, "scanned": 0}

    index_text = index_path.read_text(encoding="utf-8", errors="replace")
    files = sorted(p for p in mem.glob("*.md") if p.name != INDEX)
    stems = {p.stem for p in files}

    # 1. index drift — both directions
    linked = {Path(m).stem for m in INDEX_LINK.findall(index_text)}
    for miss in sorted(linked - stems):
        f["index_drift"].append({"issue": "index points to a missing file", "target": miss})
    for miss in sorted(stems - linked):
        f["index_drift"].append({"issue": "file not in the index", "file": miss + ".md"})

    # 5. limits (harness-enforced -> exceeding them means a silent loss)
    n_lines = len(index_text.splitlines())
    n_bytes = len(index_text.encode("utf-8"))
    if n_lines > MAX_LINES:
        f["limits"].append({"issue": "MEMORY.md too long", "lines": n_lines, "max": MAX_LINES})
    if n_bytes > MAX_BYTES:
        f["limits"].append({"issue": "MEMORY.md too large", "bytes": n_bytes, "max": MAX_BYTES})
    # index entries individually: one overlong line eats the budget of all the others
    for i, raw in enumerate(index_text.splitlines(), 1):
        if raw.startswith("- [") and len(raw) > MAX_INDEX_LINE:
            f["limits"].append({"issue": "index entry too long", "line": i,
                                "chars": len(raw), "max": MAX_INDEX_LINE,
                                "entry": raw[:60] + "…"})

    for p in files:
        text = p.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter(text)
        # 2. frontmatter against OUR schema
        if fm is None:
            f["frontmatter"].append({"file": p.name, "issue": "no frontmatter"})
        else:
            for req in ("name", "description"):
                if not fm.get(req):
                    f["frontmatter"].append({"file": p.name, "issue": f"'{req}' missing/empty"})
            meta = fm.get("metadata")
            t = meta.get("type") if isinstance(meta, dict) else None
            if not t:
                f["frontmatter"].append({"file": p.name, "issue": "metadata.type missing"})
            elif t not in VALID_TYPES:
                f["frontmatter"].append({"file": p.name, "issue": f"metadata.type '{t}' invalid",
                                         "allowed": sorted(VALID_TYPES)})
            # 3. name == filename
            if fm.get("name") and fm["name"] != p.stem:
                f["name_mismatch"].append({"file": p.name, "frontmatter_name": fm["name"]})
        # 4. dead wikilinks
        body = text.split("\n---", 1)[-1] if fm is not None else text
        for target in WIKILINK.findall(body):
            t = target.strip()
            if t and t not in stems:
                f["dead_links"].append({"file": p.name, "target": t})

    # 6. snapshot drift — our double structure (auto-memory + repo snapshot)
    # NOTE: the MANIFEST is the truth about WHAT gets mirrored — not the mere
    # presence of a .md. The snapshot legitimately carries its own files
    # (README.md explains the snapshot itself). The first run 2026-08-02 flagged
    # exactly those as false drift; the instrument was sharpened instead of
    # trusting the finding.
    if snap and snap.is_dir():
        try:
            mirrored = set(json.loads(
                (snap / ".sync-manifest.json").read_text(encoding="utf-8")).get("files", {}))
        except Exception:
            mirrored = {p.name for p in snap.glob("*.md")}   # no manifest -> evaluate everything
        snap_files = {p.name for p in snap.glob("*.md")} & mirrored
        for miss in sorted({s + ".md" for s in stems} - snap_files):
            f["snapshot_drift"].append({"issue": "missing from the repo snapshot", "file": miss,
                                        "fix": "node core/helpers/memory-sync.cjs export"})
        for extra in sorted(snap_files - {s + ".md" for s in stems} - {INDEX}):
            f["snapshot_drift"].append({"issue": "in the snapshot, but no longer in memory",
                                        "file": extra,
                                        "fix": "memory-sync.cjs prune (after memory delete)"})
        for p in files:                       # drifted apart in content?
            sp = snap / p.name
            if sp.is_file() and sp.read_bytes() != p.read_bytes():
                f["snapshot_drift"].append({"issue": "content differs", "file": p.name})

    return {"findings": f, "counts": {k: len(v) for k, v in f.items()}, "scanned": len(files)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--memory", type=Path, default=MEM_DEFAULT)
    ap.add_argument("--snapshot", type=Path, default=SNAP_DEFAULT)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if not a.memory.is_dir():
        print(f"ERROR: memory directory not found: {a.memory}", file=sys.stderr)
        return 2

    rep = lint(a.memory, a.snapshot)
    if a.json:
        print(json.dumps(rep, indent=2, ensure_ascii=False))
    else:
        total = sum(rep["counts"].values())
        print(f"memory-lint: {rep['scanned']} file(s) checked, {total} finding(s)")
        for cat, items in rep["findings"].items():
            if not items:
                continue
            print(f"\n!! {cat} ({len(items)}):")
            for it in items[:20]:
                print("   " + json.dumps(it, ensure_ascii=False))
            if len(items) > 20:
                print(f"   ... and {len(items) - 20} more")
        if total == 0:
            print("all clean (index, frontmatter, links, limits, snapshot).")
    return 1 if sum(rep["counts"].values()) else 0


if __name__ == "__main__":
    sys.exit(main())
