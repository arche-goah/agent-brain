#!/usr/bin/env python3
"""GENERATE the shared-memory pointer entry for the platform-trap register.

The register itself lives in this repo (`docs/os-traps.md`) — a platform is not a
property of one brain, and the searches have to run in CI. But a tool repo is pulled
when somebody pulls it: an instance that never checks out the core sees a finding
days late, or not at all. The shared-memory repo is the channel both instances DO read
(the session bootup reports new commits there), so the register needs a reachable
pointer in it.

A hand-written pointer would drift by the next entry — six were added in one day. So it
is generated: the shapes and the per-entry line come from the register file, the entry
carries no text of its own that could go stale, and regenerating after every change is
one command.

  os-traps-export.py [--register docs/os-traps.md] [--out <file>] [--write]

Without --write it prints what it would write. The output path is INSTANCE data (where
that repo is cloned): pass --out, or set SHARED_MEMORY_REPO and the file lands at
<repo>/core/os-trap-register.md.
"""
import argparse
import os
import re
import sys
from pathlib import Path

SHAPES = {
    "A": "the platform reshapes a string in transit",
    "B": "the same command name is a different program",
    "C": "the gate does not run where the defect lives",
}


def parse(register: Path) -> list[dict]:
    out = []
    cur = None
    for line in register.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^## (OS-\d+) — (.+)$", line)
        if m:
            cur = {"id": m.group(1), "title": m.group(2), "shape": "", "status": "",
                   "instances": "", "repeat": ""}
            out.append(cur)
            continue
        if cur is None:
            continue
        for field in ("shape", "status", "instances", "repeat"):
            fm = re.match(rf"^{field}:\s*(\S.*)$", line)
            if fm:
                cur[field] = fm.group(1).strip()
    return out


def render(entries: list[dict], register_rel: str) -> str:
    by_shape: dict[str, list[dict]] = {}
    for e in entries:
        by_shape.setdefault(e["shape"] or "?", []).append(e)

    lines = [
        "---",
        "name: os-trap-register",
        'description: "GENERATED from the core register core/docs/os-traps.md — which '
        "macOS/Windows traps are known, the three shapes they fall into, and where their "
        "searches run. Do not hand-maintain: the core is the source, this entry is the "
        'signpost for the other instance."',
        "metadata:",
        "  type: reference",
        "  von: emil-workstation",
        "  audience: alle",
        "  topic: core",
        "---",
        "",
        "# Platform traps — signpost into the core register",
        "",
        f"**Source: `{register_rel}` in the `agent-brain` repo.** This entry is GENERATED "
        "(`scripts/os-traps-export.py`) and carries no text of its own that could go "
        "stale. The searches run in CI **and** in `portability-smoke.sh`, so they execute "
        "on every system — including the one where the defect itself is invisible.",
        "",
        "Why it lives here and not only in the core: a tool repo is read when somebody "
        "checks it out. Every instance reads the shared memory at session start.",
        "",
        "## The three shapes",
        "",
        "New platform, unfamiliar behaviour: look in this order.",
        "",
    ]
    for key in ("A", "B", "C"):
        members = ", ".join(e["id"] for e in by_shape.get(key, [])) or "—"
        lines.append(f"- **{key} · {SHAPES[key]}** — {members}")
    lines += ["", "## Entries", "",
              "| ID | shape | trap | status | sites | came back |",
              "|---|---|---|---|---|---|"]
    for e in entries:
        lines.append(f"| {e['id']} | {e['shape'] or '?'} | {e['title']} | "
                     f"{e['status'] or '?'} | {e['instances'] or '?'} | "
                     f"{e['repeat'] or '?'} |")
    lines += [
        "",
        "`status: closed` means **no known open site**, not \"class over\": the register's "
        "baseline holds the sites that are CORRECT today, so that a new one stands out and "
        "gets read.",
        "",
        "## The rule",
        "",
        "A macOS/Windows divergence that cost a debugging session goes into the core "
        "register **at instance 1** — as an invariant plus its search, not as an anecdote, "
        "and with its shape. If it fits none of the three, that is the interesting case: "
        "name the fourth shape there rather than filing it as a one-off. Then regenerate "
        "this entry; adding a line by hand drifts.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--register", type=Path, default=Path("docs/os-traps.md"))
    ap.add_argument("--out", type=Path)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    if not a.register.is_file():
        print(f"ERROR: register not found: {a.register}", file=sys.stderr)
        return 2
    entries = parse(a.register)
    if not entries:
        print("ERROR: no entries parsed — the register format changed", file=sys.stderr)
        return 2

    out = a.out
    if out is None:
        repo = os.environ.get("SHARED_MEMORY_REPO")
        if not repo:
            print("ERROR: no --out and no SHARED_MEMORY_REPO — where the shared repo is "
                  "cloned is instance data, this tool does not guess", file=sys.stderr)
            return 2
        out = Path(repo) / "core" / "os-trap-register.md"

    text = render(entries, f"docs/{a.register.name}")
    missing = [e["id"] for e in entries if not e["shape"]]
    if missing:
        print(f"WARNING: no shape stated for {', '.join(missing)} — they land under '?'",
              file=sys.stderr)
    if not a.write:
        print(text)
        print(f"--- dry run: would write {out} ({len(entries)} entries)", file=sys.stderr)
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    # newline="\n": OS-2, in the tool that documents OS-2.
    out.write_text(text, encoding="utf-8", newline="\n")
    print(f"written: {out} ({len(entries)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
