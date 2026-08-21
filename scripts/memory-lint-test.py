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


def run(d):
    p = subprocess.run([sys.executable, LINT, "--memory", d, "--json"],
                       capture_output=True, text=True)
    return json.loads(p.stdout)["findings"]


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


if __name__ == "__main__":
    results = [
        case("sub-index entries count as indexed", t_subindex_counts),
        case("orphan outside any index still reported", t_orphan_still_found),
        case("unlinked index-*.md is an orphan, not followed", t_unlinked_subindex_is_not_followed),
        case("missing target inside sub-index reported", t_missing_target_in_subindex),
        case("overlong entry inside sub-index reported", t_long_line_in_subindex),
        case("no recursion beyond one level", t_no_recursion),
        case("plain index without sub-index unchanged", t_plain_index_unchanged),
    ]
    sys.exit(0 if all(results) else 1)
