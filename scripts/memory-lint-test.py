#!/usr/bin/env python3
"""Fixture tests for scripts/memory-lint.py — the sub-index contract.

Both directions per detector discipline: a sub-index MUST make its entries count
as indexed (else every brain that splits its index goes red on every bootup),
and it MUST NOT hide a real orphan or an overlong line. Builds a throwaway memory
dir, runs the linter on it, asserts on the JSON report.
"""
import json
import os
import subprocess
import sys
import tempfile

LINT = os.path.join(os.path.dirname(__file__), "memory-lint.py")


def memfile(d, name, body="x"):
    with open(os.path.join(d, name + ".md"), "w", encoding="utf-8") as fh:
        fh.write(f"---\nname: {name}\ndescription: t\nmetadata:\n  type: project\n---\n{body}\n")


def run(d, snap=None):
    cmd = [sys.executable, LINT, "--memory", d, "--json"]
    if snap:
        cmd += ["--snapshot", snap]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(p.stdout)["findings"]


def snapshot(d, mirror, manifest):
    """Snapshot dir next to the memory: copies of `mirror` (byte-identical to the live
    files) plus a manifest listing `manifest`."""
    snap = os.path.join(d, "snap")
    os.makedirs(snap)
    for name in mirror:
        with open(os.path.join(d, name), "rb") as src, open(os.path.join(snap, name), "wb") as dst:
            dst.write(src.read())
    with open(os.path.join(snap, ".sync-manifest.json"), "w", encoding="utf-8") as fh:
        json.dump({"files": {n: {"hash": "x", "updated": "t"} for n in manifest}}, fh)
    return snap


def case(title, fn):
    with tempfile.TemporaryDirectory() as d:
        ok, why = fn(d)
        print(("ok  " if ok else "FAIL") + "  " + title + ("" if ok else f" — {why}"))
        return ok


def idx(d, lines):
    with open(os.path.join(d, "MEMORY.md"), "w", encoding="utf-8") as fh:
        fh.write("# Memory Index\n\n" + "\n".join(lines) + "\n")


def t_subindex_counts(d):
    memfile(d, "rig-a"); memfile(d, "rig-b")
    memfile(d, "index-rig", "- [A](rig-a.md) — a\n- [B](rig-b.md) — b")
    idx(d, ["- [Rig](index-rig.md) — topic index"])
    f = run(d)
    return (not f["index_drift"], f"index_drift={f['index_drift']}")


def t_orphan_still_found(d):
    memfile(d, "rig-a"); memfile(d, "lost")
    memfile(d, "index-rig", "- [A](rig-a.md) — a")
    idx(d, ["- [Rig](index-rig.md) — topic index"])
    f = run(d)
    hit = [x for x in f["index_drift"] if x.get("file") == "lost.md"]
    return (len(hit) == 1 and len(f["index_drift"]) == 1, f"index_drift={f['index_drift']}")


def t_unlinked_subindex_is_not_followed(d):
    # index-x.md exists but MEMORY.md never links it -> it is an orphan like any other,
    # and what it links does NOT count as indexed (otherwise a forgotten pointer line
    # silently detaches a whole topic from the loaded index).
    memfile(d, "rig-a")
    memfile(d, "index-rig", "- [A](rig-a.md) — a")
    idx(d, ["- [Nothing](nothing-here.md) — x"])
    f = run(d)
    files = sorted(x.get("file") for x in f["index_drift"] if x.get("file"))
    return (files == ["index-rig.md", "rig-a.md"], f"index_drift={f['index_drift']}")


def t_missing_target_in_subindex(d):
    memfile(d, "index-rig", "- [Gone](gone.md) — a")
    idx(d, ["- [Rig](index-rig.md) — topic index"])
    f = run(d)
    hit = [x for x in f["index_drift"] if x.get("target") == "gone"]
    return (len(hit) == 1, f"index_drift={f['index_drift']}")


def t_long_line_in_subindex(d):
    memfile(d, "rig-a")
    memfile(d, "index-rig", "- [A](rig-a.md) — " + "x" * 420)
    idx(d, ["- [Rig](index-rig.md) — topic index"])
    f = run(d)
    hit = [x for x in f["limits"] if x.get("index") == "index-rig.md"]
    return (len(hit) == 1, f"limits={f['limits']}")


def t_no_recursion(d):
    # index-a links index-b; index-b's entries must NOT count (one level only).
    memfile(d, "deep")
    memfile(d, "index-b", "- [Deep](deep.md) — d")
    memfile(d, "index-a", "- [B](index-b.md) — b")
    idx(d, ["- [A](index-a.md) — a"])
    f = run(d)
    files = sorted(x.get("file") for x in f["index_drift"] if x.get("file"))
    return (files == ["deep.md"], f"index_drift={f['index_drift']}")


def t_plain_index_unchanged(d):
    memfile(d, "one")
    idx(d, ["- [One](one.md) — o"])
    f = run(d)
    return (not f["index_drift"] and not f["limits"], f"{f}")


# --- manifest -> file direction (brain-scan 2026-09-07, B-28) -----------------------
# A manifest entry whose file exists neither in the snapshot nor in the live memory is a
# ghost: the manifest claims a mirrored memory that is gone. Measured on a proving brain:
# `traeger-landkarte.md` stood in the manifest for weeks, and the linter said "all clean"
# because it only compared live -> snapshot. "Manifest lies" and "all in sync" got the
# same symbol.

def t_manifest_ghost_reported(d):
    memfile(d, "one")
    idx(d, ["- [One](one.md) — o"])
    snap = snapshot(d, ["one.md", "MEMORY.md"], ["one.md", "MEMORY.md", "ghost.md"])
    f = run(d, snap)
    hit = [x for x in f["snapshot_drift"] if x.get("file") == "ghost.md"]
    return (len(hit) == 1 and len(f["snapshot_drift"]) == 1, f"snapshot_drift={f['snapshot_drift']}")


def t_manifest_in_sync_is_clean(d):
    # negative control: same layout without the ghost -> nothing to report
    memfile(d, "one")
    idx(d, ["- [One](one.md) — o"])
    snap = snapshot(d, ["one.md", "MEMORY.md"], ["one.md", "MEMORY.md"])
    f = run(d, snap)
    return (not f["snapshot_drift"], f"snapshot_drift={f['snapshot_drift']}")


def t_live_only_not_double_reported(d):
    # manifest names a file that is live but missing from the snapshot: that is the
    # existing "missing from the repo snapshot" finding (export restores it) — exactly
    # one finding, not a second one as a ghost.
    memfile(d, "one"); memfile(d, "two")
    idx(d, ["- [One](one.md) — o", "- [Two](two.md) — t"])
    snap = snapshot(d, ["one.md", "MEMORY.md"], ["one.md", "two.md", "MEMORY.md"])
    f = run(d, snap)
    hit = [x for x in f["snapshot_drift"] if x.get("file") == "two.md"]
    return (len(hit) == 1 and len(f["snapshot_drift"]) == 1, f"snapshot_drift={f['snapshot_drift']}")


if __name__ == "__main__":
    results = [
        case("sub-index entries count as indexed", t_subindex_counts),
        case("orphan outside any index still reported", t_orphan_still_found),
        case("unlinked index-*.md is an orphan, not followed", t_unlinked_subindex_is_not_followed),
        case("missing target inside sub-index reported", t_missing_target_in_subindex),
        case("overlong entry inside sub-index reported", t_long_line_in_subindex),
        case("no recursion beyond one level", t_no_recursion),
        case("plain index without sub-index unchanged", t_plain_index_unchanged),
        case("manifest entry without any file reported", t_manifest_ghost_reported),
        case("manifest in sync stays clean", t_manifest_in_sync_is_clean),
        case("live-only manifest entry reported once, not as ghost", t_live_only_not_double_reported),
    ]
    sys.exit(0 if all(results) else 1)
