#!/usr/bin/env python3
"""hook-exit-lint: a hook in helpers/ that reads a session transcript must not end with process.exit().

WHY (measured 2026-11-23 on the macOS instance, Node 25.9): after a large transcript read, `process.exit()` hung in
Node's platform shutdown in 21 of 40 runs of content-review-gate, and the harness blocked the call ("timed out;
blocking"). Such a hook ends through helpers/hook-exit.cjs `exit()` or a natural end (`process.exitCode`).

A transcript reader = the code (comments stripped) names `transcript_path`, `transcriptPath` or a `.jsonl` file.
Usage: python3 scripts/hook-exit-lint.py [--root <dir>]   exit 0 = clean, 1 = a hook calls process.exit()
"""
import pathlib
import re
import sys

COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)
READS = re.compile(r"transcript_path|transcriptPath|\.jsonl")
EXIT = re.compile(r"\bprocess\.exit\s*\(")
SELF = "hook-exit.cjs"


def findings(root):
    out = []
    for f in sorted((root / "helpers").glob("*.cjs")):
        if f.name == SELF:
            continue
        code = COMMENT.sub("", f.read_text(encoding="utf-8"))
        if READS.search(code) and EXIT.search(code):
            out.append(f"{f.relative_to(root).as_posix()}: {len(EXIT.findall(code))} process.exit() call(s)")
    return out


def main(argv):
    root = pathlib.Path(argv[argv.index("--root") + 1]) if "--root" in argv else pathlib.Path(__file__).resolve().parent.parent
    bad = findings(root)
    for b in bad:
        print(f"HOOK-EXIT: {b} - a transcript-reading hook ends through helpers/hook-exit.cjs exit() "
              "(process.exit hung at Node shutdown, 2026-11-23)")
    print(f"hook-exit-lint: {len(bad)} finding(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
