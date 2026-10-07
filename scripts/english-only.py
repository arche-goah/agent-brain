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

DETECTION BOUNDARY, deliberate and stated (T3, 2026-09-30): this ratchet recognises
GERMAN drift only. French, Czech or Spanish text would pass unseen. That is a choice,
not an oversight: German is the one measured drift source of the fleet that writes
here, and a detector for languages nobody writes in would carry unmeasured word lists
— the false reds this file warns about. The day a second working language writes to
this repo, its detector belongs here the same way: umlaut-class + transliteration-class
grep for THAT language, measured on real drift before it can fail a build.

Since 2026-08-14 (LA1 audit) the ratchet also checks NAMES: a German token in a
tracked file's PATH fails, regardless of content — the audit's trigger was that
`rules/arbeitsregeln.md` sat invisible in a content-only check. Known legacy paths
(the LA1 deprecation stubs) live in scripts/english-legacy-names.txt and may only
ever disappear from it, same one-way semantics as the content baseline.

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
NAME_BASELINE = ROOT / "scripts" / "english-legacy-names.txt"

TEXT_SUFFIX = {".md", ".py", ".sh", ".cjs", ".js", ".json", ".yml", ".yaml",
               ".lua", ".html", ".txt"}
# The baseline lists German-named entries, this script carries the German word
# list as detection data, and skill-lint.py carries German stopwords as similarity
# data — none of that is German CONTENT.
# test-premise-gate.sh and test-stop-checks.sh carry German SAMPLES: the premise
# fixture ships a second language to prove that a language is data, and the stop
# fixture feeds transliterated German to the orthography check. In both the German
# IS the subject under test — translating it would delete the test.
# test-stoppen-gate.sh joins them on the same terms: it writes the German stop-pattern
# pack as an instance file and feeds the sentences that pack must match. The HOOK itself
# (stoppen-gate.cjs) left this set when its inline German pack moved out to instance data
# (T3) — keeping an engine OUT of the skip set is what holds the layering "engine
# built-ins English, every language is data": German creeping back into it fails here.
# test-promise-gate.sh enters on exactly those terms (2026-09-12): its prose is English,
# its German is the instance pattern file it writes and the sentences that file must
# match — and its discriminator DEPENDS on German, because it proves the hit comes from
# the data by running the same German sentence without that file and requiring silence.
# test-open-items-gate.sh enters on the same terms (2026-10-07): its German is the
# instance pattern file it writes ("nichts offen", "geparkt") and the reply that file must
# accept, and one case runs that German reply WITHOUT the file and requires a block.
SKIP_NAMES = {"english-legacy.txt", "english-legacy-names.txt", "english-only.py",
              "skill-lint.py", "test-premise-gate.sh", "test-promise-gate.sh",
              "test-open-items-gate.sh", "test-stop-checks.sh",
              "test-stoppen-gate.sh"}

UMLAUT = re.compile(r"[äöüßÄÖÜ]")
# Transliterated / bare German that does not occur in technical English. Extend only
# with words you have never seen in an English sentence.
GERMAN_WORDS = re.compile(
    r"\b(fuer|ueber|gehoert|traegt|unabhaengig|ausloesen|zuerst|nicht|wird|keine|"
    r"jede[rn]?|Pflicht|Werkzeug|Geraet|Ansage|Regel|Vorfall|gemessen|Auftrag|"
    r"und|wurde|koennen|muessen|sollen|waehrend|bereits|zwingend|heisst|bleibt|"
    r"deshalb|jedoch|sowie|gemaess|dafuer|dazu|beim|ausserdem|trotzdem)\b")
# German tokens that must not appear in a tracked file PATH. Matched against path
# components split on -_./ so compound names (autonomer-lauf) hit token-wise. Same
# conservatism as above: only tokens with no English reading.
GERMAN_NAME_TOKENS = {
    "arbeitsregeln", "instanz", "kohaerenz", "koharenz", "synthese", "autonomer",
    "auftrag", "auftraege", "pruefung", "pruef", "messung", "werkzeug", "geraet",
    "geraete", "uebersicht", "vorlage", "beispiel", "hinweis", "regeln", "punkte",
    "traeger", "sprache", "woerterbuch", "anleitung", "uebergabe", "lauf",
}


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


def german_named(rel_posix: str) -> bool:
    tokens = re.split(r"[-_./]", rel_posix.lower())
    return any(t in GERMAN_NAME_TOKENS for t in tokens)


def main() -> int:
    # as_posix: git ls-files and the baseline speak forward slashes; bare
    # relative_to() yields backslashes on Windows and every comparison misses
    # (measured 2026-08-13: 100 findings on a clean tree).
    german = sorted(p.relative_to(ROOT).as_posix() for p in tracked_files()
                    if p.suffix.lower() in TEXT_SUFFIX
                    and p.name not in SKIP_NAMES
                    and has_german(p))

    if "--write-baseline" in sys.argv:
        BASELINE.write_text("\n".join(german) + "\n", encoding="utf-8", newline="\n")
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

    # NAME ratchet: German tokens in tracked paths, every suffix — a rename is a
    # rename regardless of file type. Legacy = the LA1 deprecation stubs only.
    name_baseline = set()
    if NAME_BASELINE.exists():
        name_baseline = {l.strip() for l in NAME_BASELINE.read_text(encoding="utf-8").splitlines()
                         if l.strip() and not l.startswith("#")}
    for f in sorted(tracked):
        if german_named(f) and f not in name_baseline:
            findings.append(f"GERMAN NAME: {f} — file/dir names in public-bound repos "
                            "are English (AGENTS.md rule 7); rename with a deprecation path")
    for entry in sorted(name_baseline):
        if entry not in tracked:
            findings.append(f"STALE NAME ENTRY: {entry} — path gone, remove from "
                            "english-legacy-names.txt")

    if findings:
        for f in findings:
            print(f"!! {f}")
        return 1
    print(f"english-only: clean — {len(baseline)} legacy files awaiting sweep, 0 drift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
