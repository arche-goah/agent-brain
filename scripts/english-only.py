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
SKIP_NAMES = {"english-legacy.txt", "english-legacy-names.txt", "english-only.py",
              "skill-lint.py", "test-premise-gate.sh", "test-stop-checks.sh"}

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


def untracked_candidates():
    """New files this check CANNOT see yet — the blind spot that makes a local run lie.

    Measured twice in one session: a new script was written, the local run reported
    clean, and CI went red the moment the file was staged. Both times the file simply
    was not in .claude-plugin/plugin.json
.gitattributes
.github/workflows/ci.yml
.gitignore
AGENTS.md
CHANGELOG.md
CLAUDE.md
CONVENTIONS.md
LICENSE
NOTICE
ONBOARDING.md
README.md
core-contract.json
dependencies.json
docs/onboarding-contract.md
helpers/README.md
helpers/class-gate.cjs
helpers/file-guard.cjs
helpers/freshness-gate.cjs
helpers/junk-cleaner.cjs
helpers/mechanism-guard.cjs
helpers/memory-sync.cjs
helpers/notify.cjs
helpers/premise-gate.cjs
helpers/recall-gate.cjs
helpers/run-record.sh
helpers/secret-guard.cjs
helpers/session-bootup.sh
helpers/session-closing.sh
helpers/shared-memory-check.sh
helpers/statusline.cjs
helpers/stop-dispatcher.cjs
helpers/stop-verifier.cjs
output-styles/caveman.md
rules/arbeitsregeln.md
rules/intelligence.md
rules/techniques.md
rules/thinking-protocol.md
rules/working-rules.md
scripts/bootstrap-brain.sh
scripts/brain-check.sh
scripts/brain-friction.py
scripts/brain-scan.sh
scripts/brain-selftest.sh
scripts/brain-update.sh
scripts/ci-watch-test.sh
scripts/ci-watch.sh
scripts/dep-install.py
scripts/dep-lint.py
scripts/ecosystem-sync.py
scripts/effect-check.sh
scripts/english-legacy-names.txt
scripts/english-legacy.txt
scripts/english-only.py
scripts/freshness-gate-test.py
scripts/gate-precision.py
scripts/handover-gate.sh
scripts/hook-coverage.py
scripts/install-statusline.sh
scripts/invariant-check-test.py
scripts/invariant-check.py
scripts/leak-scan.py
scripts/lint-placeholders.sh
scripts/loop-watchdog.sh
scripts/memory-lint-test.py
scripts/memory-lint.py
scripts/onboarding-verify.sh
scripts/parallel-sessions.sh
scripts/portability-smoke.sh
scripts/preflight.ps1
scripts/preflight.sh
scripts/regen-skill-registry.py
scripts/release-preflight-test.sh
scripts/release-preflight.sh
scripts/setup-shell-start.sh
scripts/shared-memory-index.py
scripts/shared-memory-lint-test.py
scripts/shared-memory-lint.py
scripts/shared-memory-watch-test.sh
scripts/shared-memory-watch.sh
scripts/skill-lint.py
scripts/suite-check.py
scripts/suite-install.sh
scripts/test-guards.sh
scripts/test-premise-gate.sh
scripts/test-recall-gate.sh
scripts/test-session-helpers.sh
scripts/test-stop-checks.sh
scripts/test-stop-dispatcher.sh
scripts/test-suite-plugin-linkage.sh
scripts/transcript-recall-test.py
scripts/transcript-recall.py
scripts/wait-mcp-reconnect.sh
scripts/workflow-parse-check.sh
skills/REGISTRY.md
skills/autonomer-lauf/SKILL.md
skills/autonomous-run/SKILL.md
skills/caveman/SKILL.md
skills/code-audit/SKILL.md
skills/code-audit/audit-report-template.md
skills/code-audit/findings-schema.json
skills/codex-review/SKILL.md
skills/coherence-scan/SKILL.md
skills/defuddle/SKILL.md
skills/dependency-audit/SKILL.md
skills/dependency-audit/dep_audit.py
skills/firecrawl-web/.skill_id
skills/firecrawl-web/SKILL.md
skills/firecrawl-web/fc.py
skills/firecrawl-web/requirements.txt
skills/full-audit/SKILL.md
skills/json-canvas/SKILL.md
skills/json-canvas/references/EXAMPLES.md
skills/kohaerenz-scan/SKILL.md
skills/last30days/SKILL.md
skills/last30days/agents/openai.yaml
skills/last30days/references/save-html-brief.md
skills/last30days/scripts/briefing.py
skills/last30days/scripts/build-skill.sh
skills/last30days/scripts/compare.sh
skills/last30days/scripts/evaluate_search_quality.py
skills/last30days/scripts/last30days.py
skills/last30days/scripts/lib/__init__.py
skills/last30days/scripts/lib/bird_x.py
skills/last30days/scripts/lib/bluesky.py
skills/last30days/scripts/lib/categories.py
skills/last30days/scripts/lib/chrome_cookies.py
skills/last30days/scripts/lib/cluster.py
skills/last30days/scripts/lib/competitors.py
skills/last30days/scripts/lib/cookie_extract.py
skills/last30days/scripts/lib/dates.py
skills/last30days/scripts/lib/dedupe.py
skills/last30days/scripts/lib/digg.py
skills/last30days/scripts/lib/entity_extract.py
skills/last30days/scripts/lib/env.py
skills/last30days/scripts/lib/fanout.py
skills/last30days/scripts/lib/fusion.py
skills/last30days/scripts/lib/github.py
skills/last30days/scripts/lib/grounding.py
skills/last30days/scripts/lib/hackernews.py
skills/last30days/scripts/lib/html_render.py
skills/last30days/scripts/lib/http.py
skills/last30days/scripts/lib/instagram.py
skills/last30days/scripts/lib/log.py
skills/last30days/scripts/lib/normalize.py
skills/last30days/scripts/lib/perplexity.py
skills/last30days/scripts/lib/pinterest.py
skills/last30days/scripts/lib/pipeline.py
skills/last30days/scripts/lib/planner.py
skills/last30days/scripts/lib/polymarket.py
skills/last30days/scripts/lib/preflight.py
skills/last30days/scripts/lib/providers.py
skills/last30days/scripts/lib/quality_nudge.py
skills/last30days/scripts/lib/query.py
skills/last30days/scripts/lib/reddit.py
skills/last30days/scripts/lib/reddit_enrich.py
skills/last30days/scripts/lib/reddit_public.py
skills/last30days/scripts/lib/relevance.py
skills/last30days/scripts/lib/render.py
skills/last30days/scripts/lib/rerank.py
skills/last30days/scripts/lib/resolve.py
skills/last30days/scripts/lib/safari_cookies.py
skills/last30days/scripts/lib/schema.py
skills/last30days/scripts/lib/setup_wizard.py
skills/last30days/scripts/lib/signals.py
skills/last30days/scripts/lib/snippet.py
skills/last30days/scripts/lib/subproc.py
skills/last30days/scripts/lib/threads.py
skills/last30days/scripts/lib/tiktok.py
skills/last30days/scripts/lib/truthsocial.py
skills/last30days/scripts/lib/ui.py
skills/last30days/scripts/lib/vendor/bird-search/LICENSE
skills/last30days/scripts/lib/vendor/bird-search/bird-search.mjs
skills/last30days/scripts/lib/vendor/bird-search/lib/cookies.js
skills/last30days/scripts/lib/vendor/bird-search/lib/features.json
skills/last30days/scripts/lib/vendor/bird-search/lib/paginate-cursor.js
skills/last30days/scripts/lib/vendor/bird-search/lib/query-ids.json
skills/last30days/scripts/lib/vendor/bird-search/lib/runtime-features.js
skills/last30days/scripts/lib/vendor/bird-search/lib/runtime-query-ids.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-base.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-constants.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-features.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-search.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-types.js
skills/last30days/scripts/lib/vendor/bird-search/lib/twitter-client-utils.js
skills/last30days/scripts/lib/vendor/bird-search/package.json
skills/last30days/scripts/lib/xai_x.py
skills/last30days/scripts/lib/xiaohongshu_api.py
skills/last30days/scripts/lib/xquik.py
skills/last30days/scripts/lib/xurl_x.py
skills/last30days/scripts/lib/youtube_yt.py
skills/last30days/scripts/store.py
skills/last30days/scripts/sync.sh
skills/last30days/scripts/test_device_auth.py
skills/last30days/scripts/verify_v3.py
skills/last30days/scripts/watchlist.py
skills/memory-dream/.skill_id
skills/memory-dream/SKILL.md
skills/ollama-fallback/SKILL.md
skills/parallel-research-agent/SKILL.md
skills/playwright-skill/.skill_id
skills/playwright-skill/0)
skills/playwright-skill/API_REFERENCE.md
skills/playwright-skill/SKILL.md
skills/playwright-skill/lib/helpers.js
skills/playwright-skill/package.json
skills/playwright-skill/run.js
skills/ponytail/SKILL.md
skills/repo-recon/SKILL.md
skills/repo-recon/recon.py
skills/session-close/SKILL.md
skills/session-insights/SKILL.md
skills/shared-memory-tidy/SKILL.md
skills/shared-memory-watch/SKILL.md
skills/skill-builder/.skill_id
skills/skill-builder/SKILL.md
skills/skill-builder/references/frontmatter-spec.md
skills/skill-builder/references/structure-and-disclosure.md
skills/skill-builder/references/templates-and-examples.md
skills/test-survey/SKILL.md
skills/test-survey/test_survey.py
skills/verification-before-completion/.skill_id
skills/verification-before-completion/SKILL.md
templates/CLAUDE.md
templates/MEMORY.md
templates/feedback.md
templates/invariants.md
templates/leak-names.json
templates/rules-instance/intelligence-instance.md
templates/rules-instance/mechanism-rules.json
templates/rules-instance/recall-tools.json
templates/rules-instance/working-rules-instance.md
templates/settings.json
workflows/brain-scan.js
workflows/coherence-scan.js
workflows/full-audit-synthesis.js
workflows/memory-dream.js
workflows/shared-memory-dream.js yet, so the ratchet had nothing to look at. A checker that
    is silent about what it could not examine reports "clean" and "not looked" with the
    same word — the same conflation that makes a held-back pin read as a stale one.
    """
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--others",
                          "--exclude-standard"],
                         capture_output=True, text=True, timeout=30)
    return [ROOT / p for p in out.stdout.split("\0")
            if p and Path(p).suffix.lower() in TEXT_SUFFIX
            and Path(p).name not in SKIP_NAMES]


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
    unseen = [p.relative_to(ROOT).as_posix() for p in untracked_candidates()]
    print(f"english-only: clean — {len(baseline)} legacy files awaiting sweep, 0 drift")
    if unseen:
        # Say what was NOT looked at. Clean-and-complete and clean-but-blind print the
        # same word otherwise, and the difference only shows up in CI after staging.
        print(f"   note: {len(unseen)} untracked file(s) NOT checked — stage them and "
              f"re-run before trusting this: {', '.join(unseen[:5])}"
              + (" …" if len(unseen) > 5 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
