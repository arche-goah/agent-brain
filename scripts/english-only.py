#!/usr/bin/env python3
"""English-only ratchet — new content must be English, legacy shrinks monotonically.

WHY a ratchet and not a plain grep: the operator ordered English for everything
public-bound (2026-08-13) while 52 tracked files still carry German from the working
setup. A plain grep would be permanently red and train everyone to ignore it; a
baseline that only ever SHRINKS blocks exactly the drift — new German — while the
legacy waits for its translation sweep.

Rules enforced, both directions:
  1. A file NOT in scripts/english-legacy.txt that contains German  -> FAIL (drift)
  2. A file IN the list that no longer contains German              -> FAIL
     (translated: remove the entry, the ratchet must click)
  3. An entry whose file no longer exists                           -> FAIL (stale)

Detection is the dual grep from the 2026-08-13 language invariant: umlauts alone are
blind to ASCII-transliterated German ("fuer", "gehoert"), so both classes count.
Word list is deliberately conservative — a false red teaches ignoring.

Usage: scripts/english-only.py [--write-baseline]   (run from anywhere; repo = script's repo)
Exit 0 = clean, 1 = findings.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "scripts" / "english-legacy.txt"

TEXT_SUFFIX = {".md", ".py", ".sh", ".cjs", ".js", ".json", ".yml", ".yaml",
               ".lua", ".html", ".txt"}
# The baseline lists German-named entries, this script carries the German word
# list as detection data, and skill-lint.py carries German stopwords as similarity
# data — none of that is German CONTENT.
SKIP_NAMES = {"english-legacy.txt", "english-only.py", "skill-lint.py"}

UMLAUT = re.compile(r"[äöüßÄÖÜ]")
# Transliterated / bare German that does not occur in technical English. Extend only
# with words you have never seen in an English sentence.
GERMAN_WORDS = re.compile(
    r"\b(fuer|ueber|gehoert|traegt|unabhaengig|ausloesen|zuerst|nicht|wird|keine|"
    r"jede[rn]?|Pflicht|Werkzeug|Geraet|Ansage|Regel|Vorfall|gemessen|Auftrag)\b")


def tracked_files():
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                         capture_output=True, text=True, timeout=30)
    return [ROOT / p for p in out.stdout.split("\0") if p]


def has_german(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False
    return bool(UMLAUT.search(text) or GERMAN_WORDS.search(text))


def main() -> int:
    # as_posix: git ls-files and the baseline speak forward slashes; bare
    # relative_to() yields backslashes on Windows and every comparison misses
    # (measured 2026-08-13: 100 findings on a clean tree).
    german = sorted(p.relative_to(ROOT).as_posix() for p in tracked_files()
                    if p.suffix.lower() in TEXT_SUFFIX
                    and p.name not in SKIP_NAMES
                    and has_german(p))

    if "--write-baseline" in sys.argv:
        BASELINE.write_text("\n".join(german) + "\n", encoding="utf-8")
        print(f"english-only: baseline written, {len(german)} legacy files")
        return 0

    baseline = set()
    if BASELINE.exists():
        baseline = {l.strip() for l in BASELINE.read_text(encoding="utf-8").splitlines()
                    if l.strip() and not l.startswith("#")}

    findings = []
    for f in german:
        if f not in baseline:
            findings.append(f"NEW GERMAN: {f} — public-bound repos are English-only "
                            "(AGENTS.md rule 7); translate before merging")
    tracked = {p.relative_to(ROOT).as_posix() for p in tracked_files()}
    for entry in sorted(baseline):
        if entry not in tracked:
            findings.append(f"STALE ENTRY: {entry} — file gone, remove from english-legacy.txt")
        elif entry not in german:
            findings.append(f"TRANSLATED: {entry} — remove from english-legacy.txt "
                            "(the ratchet only turns one way)")

    if findings:
        for f in findings:
            print(f"!! {f}")
        return 1
    print(f"english-only: clean — {len(baseline)} legacy files awaiting sweep, 0 drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
