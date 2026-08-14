# Changelog — agent-brain

All notable changes to this repo. Versions are graded by content (AGENTS.md #5):
patch is the default (unproven capability included), minor = a proven-feature
re-release with clear notes, major = a big, thoroughly tested step.
The marketplace pins tags, never `main`.

## 1.3.4 — 2026-08-14

- **ci-watch.sh — robust CI waiter for PRs and refs, tags included** (PR #34,
  operator order after two ad-hoc watchers broke in one session): `gh run list
  --branch <tag>` never matches a tag run (a loop compared an empty field against
  "completed" forever — silence looked like still-running), and zsh's no-split on
  unquoted variables 404'd every call with the error swallowed. The tool matches
  refs via the headBranch JSON field, enumerates every terminal state, and cannot
  end silently: exit 0 green, 1 red, 2 UNKNOWN (loud, never reads as green).
  9 stubbed fixtures both directions wired into CI; proven live on its own PR.

## 1.3.3 — 2026-08-14

- **preflight.ps1 parses on Windows PowerShell 5.1 and measures the right thing**
  (PR #31, found and fixed by the workstation brain, proven ALL GREEN on real
  Win 11/PS 5.1): the file now carries a UTF-8 BOM (BOM-less .ps1 is read as ANSI
  by PS 5.1 — an em-dash byte became a string terminator and zero checks ran) and
  the SSH check proves GitHub ACCESS via `ssh -T` output like the bash edition,
  demoting the ssh-agent service to a WARN.
- **Node install advice satisfies the script's own gate** (PR #32): the bash
  preflight recommended `OpenJS.NodeJS.LTS` while gating on Node >= 23.6 —
  current LTS is 22, so the printed fix failed the very check that printed it.

## 1.3.2 — 2026-08-14

- **LA1 language audit, names** (PR #23) — every German-named artifact renamed with
  a one-major deprecation path: `rules/arbeitsregeln.md` -> `rules/working-rules.md`
  (stub keeps old imports loading via a relative `@working-rules.md` chain), skills
  `autonomer-lauf` -> `autonomous-run` and `kohaerenz-scan` -> `coherence-scan`
  (pointer stubs remain), workflows `coherence-scan.js` / `full-audit-synthesis.js`,
  templates `rules-instance/` with `working-rules-instance.md` +
  `intelligence-instance.md`, interface key `reports.kohaerenz` -> `reports.coherence`.
  session-bootup warns on legacy imports/skill names until the instance migrates.
- **LA1 language audit, ratchet** (PR #26) — `english-only.py` now token-checks every
  tracked PATH against a German name dictionary (all suffixes; shrink-only baseline
  `english-legacy-names.txt` carries only the deprecation stubs) and the content word
  list grows by 19 unambiguous words. Negative controls in both directions.
- **Spec Gate** (PR #24) — `verification-before-completion` gains the order-fidelity #4
  carrier: every completion claim answers the spec-deviation question explicitly; a
  deviation becomes a debt entry and is reported first.
- **Version grading** (PR #27, operator order 2026-08-14) — patch is the release
  default; minor is a deliberate re-release once features are proven in real runs.
- **Project Lifecycle rule** (PR #28) — `working-rules.md` defines what gets CREATED
  when a new project domain starts: tool/instance cut, ledger birth, domain-keyed
  history, memory placement, aggregator registration, suite wiring.
- **Self-contained onboarding** (PR #29) — `ONBOARDING.md` plus ported English
  scripts (`preflight.sh`/`.ps1`, `setup-shell-start.sh`, `onboarding-verify.sh`)
  and `docs/onboarding-contract.md` (11 checks, suite checks SKIP when absent);
  replaces the separate onboarding kit for the generic path. `preflight.ps1` is
  not yet exercised on a real Windows machine.

## 1.3.1 — 2026-08-13

- **Rules: Project Work Ledgers** (PR #21, operator decision 2026-08-13) — uniform
  project tracking across instances in `rules/arbeitsregeln.md`: one hand-maintained
  detail list per project domain in the PRIVATE instance repo (never the project/tool
  repo), entries carry `id`/`class`/`reach`/`origin` as the English cross-instance
  interface; overviews are generated, never hand-kept; `reach: shared` marks entries
  for the org shared-memory export (one-file-one-fact, deliberate act at close);
  decisions are pointers into the change/decision logs; brain maintenance lists carry
  brain-function work only. Patch: rule addition, no new mechanics.

## 1.3.0 — 2026-08-13

- **Bootup: suite clones are covered by the released-state check.** The existing
  check reads marketplace pins, so it sees plugins and the core submodule — but
  suites are consumed as git clones, and a new suite release tag reaches no pin:
  it slipped past every session start. The bootup now compares, for every
  `kind=suite` entry in the brain's ecosystem record, the newest remote `v*` tag
  against the newest tag reachable from the local checkout (parallel
  `ls-remote`, offline-silent). Only a genuinely newer remote tag is reported —
  a developer checkout sitting ahead stays silent; consumer checkouts get the
  `suite-install.sh` one-liner. Minor: new check.

## 1.2.1 — 2026-08-13

- **New capability: `helpers/freshness-gate.cjs` — the repeat-run rule gets a
  mechanical carrier (PR #15; ships first in 1.2.1 because v1.2.0 was tagged
  without it).** PreToolUse(Workflow) hook: relaunching a workflow whose last
  completed run is younger than the freshness threshold and cost real tokens is
  denied, pointing to the run record + journal instead. Explicit escapes only:
  `resumeFromRunId`, `// FRESHNESS-OK: <the unanswered question>`, failed or
  cheap prior runs. Thresholds are instance data
  (`.claude/rules/freshness-gate.json`) so a scheduled cadence lowers its
  per-workflow threshold instead of carrying a permanent marker. 12 fixtures in
  both directions wired into CI; template settings, helpers README (drift:
  mechanism/secret-guard rows were missing) and the rule pointer in
  `rules/intelligence.md` updated. Minor grade inside a patch-numbered release:
  the 1.2.x line was already assigned when the batch closed — content noted
  here, counter not reshuffled.

- **Fix: the v1.2.0 release shipped with `plugin.json` still saying 1.1.2** —
  the release checklist (AGENTS.md #5) bumps it every time, and the version
  string is exactly what the plugin cache collides on (the measured crossover
  class): same string + different content = a stale cache that looks current.
  No content change beyond the manifest version.

## 1.2.0 — 2026-08-13

- **New capability: `scripts/suite-install.sh` — one command fetches a released
  tool suite.** Colleagues consume the suites (mikrotik, grandma3, chataigne,
  show-tools) as git clones, and until now "get the release" was tribal
  knowledge (clone, fetch, find the right tag). The script resolves path +
  remote from the brain's ecosystem record (defaults for a fresh brain), clones
  or fetches, and checks out the newest `v*` tag — never `main`: an untagged
  state is not released. Local changes and developer checkouts (anything
  sitting on a branch it did not just clone) are a hard stop, so it can never
  eat a working copy. `--all` updates every suite the brain records; the
  ecosystem record is refreshed afterwards. Wiring (.mcp.json entry, skill
  symlinks) stays a documented hand step on purpose — launchers carry
  operator-specific addresses and credential names.

## 1.1.2 — 2026-08-13

- **Rules: the session-start summary is written in human language (PR #12).**
  The rule ordered a mini-summary but said nothing about its language, so raw
  hook vocabulary (`!!` markers, return codes) leaked into chat and pending
  decisions ended as a generic "what's next?" instead of a direct question
  ("update available — shall I run it?"). The Session Start section of
  `rules/intelligence.md` now requires translating machine artifacts into
  operator-facing language — in every chat output, not just the session start.
  Patch: docs only.

## 1.1.1 — 2026-08-13

- **brain-update: cache provenance checks EVERY install scope, not entry zero
  (PR #9).** With a project-scope duplicate next to the user-scope install, the
  records masked each other and a FAIL could hide behind a healthy first entry
  (measured on both brains during the repo-move migration). Each scope is now
  verified on its own; the FAIL text names the scope so the printed
  uninstall/reinstall heals the right record.
- **Docs: the canonical core update path is `brain-update.sh` (PR #10).**
  templates/CLAUDE.md, README and CONVENTIONS still recommended
  `git submodule update --remote core` + `claude plugin update` — `--remote`
  tracks `main`, not the released pin, and after the brain-core → agent-brain
  repo move it resolves the OLD repo's main (now an archive notice). All three
  spots name the one command and say why `--remote` is not the path. Patch:
  fix + docs, no new capability.

## 1.1.0 — 2026-08-13

- **brain-scan: CVE identifiers require an official source (PR #2).** Both SOTA
  scan agents carry a shared CVE rule: an identifier counts as fact only when read
  in the same run from an official source (the repo's GitHub Security Advisories,
  NVD/MITRE by ID, vendor advisory). Web-search-only numbers are titled
  UNCONFIRMED, state `configured`, never `verified`. Incident: a scan reported
  five CVE numbers as P0/verified that exist in no official source.
- **brain-update: plugin cache provenance is verified against the pinned source
  (PR #3, message wording PR #7).** The cache is keyed by name+version, not by
  source — after a repo move, foreign content can survive under the right version
  name. Step 2b compares each installed `gitCommitSha` against the pin's remote
  tag SHA; a mismatch FAILs loudly (foreign content OR stale install record —
  indistinguishable from the SHA; the printed reinstall heals both) and FAIL
  lines now reach the exit code instead of printing DONE over them. Minor: new
  verification capability.
- **brain-scan launcher: headless background-wait ceiling raised to 90 min
  (PR #4).** Headless `claude -p` kills background work after 600 s by default
  (documented: `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`, default 600000, since
  CLI v2.1.182) — the scheduled scan died report-less at rc=0. 90 min instead of
  infinite so a hung run cannot pile up; an outer value wins.
- **thinking-protocol #0: relative time references are measurement claims
  (PR #5).** "Yesterday"/"last week" assert a measured timestamp — read the
  source's timestamp and compute, or omit the time reference entirely.
- **Language scope: native orthography belongs to chat, ASCII transliteration to
  artifacts (PR #6).** AGENTS.md #7 states the artifact scope explicitly;
  the caveman style carries the chat-side rule to every consuming brain.

## 1.0.1 — 2026-08-13

- **brain-update: the core/ submodule follows the MARKETPLACE PIN on every layer
  that names the repo.** Ported from the predecessor's final release and extended:
  step 3 reads the pinned `source.repo`/`source.ref` for the core plugin from the
  refreshed marketplace cache, aligns the submodule origin when the pin names a
  different repo (ssh/https forms compare equal), and now ALSO rewrites the
  `.gitmodules` declaration (+ `git submodule sync`). A fresh clone reads only
  the declaration — the live-only fix left every future clone of a migrated
  brain resolving the old repo, where the pinned commit does not exist (found by
  a second instance right after the cut, 2026-08-13). Step 5 commits
  `.gitmodules` along with the pin. Patch: fix of the cutover mechanism.

## 1.0.0 — 2026-08-13

Initial public cut. This repo is a fresh cut of a privately grown core: the full
released state of its predecessor, with a fresh history, fully translated to
English, and with maintainer-internal tooling removed. The version counter starts
at 1.0.0 — the predecessor's counter does not carry over.

Content at the cut:

- **Plugin channel** (`.claude-plugin/plugin.json`, plugin name `brain-core`):
  22 general-purpose skills under `skills/`, the caveman output style under
  `output-styles/` (active via `force-for-plugin`).
- **Submodule channel**: working rules (`rules/`), session hooks and guards
  (`helpers/`), contract and audit scripts (`scripts/`), audit workflows
  (`workflows/`), instance templates (`templates/`), the ecosystem contract
  (`CONVENTIONS.md` + `core-contract.json`).
- **CI**: leak scan, skill lint, english-only ratchet, helper/workflow parse
  checks, 3-OS portability smoke (scripts are executed, not only linted),
  contract checks.

The plugin keeps the name `brain-core` so existing `brain-core:<skill>` references
in consuming brains stay valid; only the repo is new.
