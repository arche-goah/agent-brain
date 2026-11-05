- **Three checks stop costing attention or tokens for nothing** (test: T1) (level: reader; higher: writer — the
  brain-scan stage that re-reads machine checks and the start ballast per agent need a measured A/B first; debt: those two).
  - `workflows/coherence-scan.js` verifies in batches of 12 instead of 6: with the merge cap of 24 that is two skeptics
    instead of four, each ~100k start context; two runs in a row confirmed 24/24 (0.68 + 0.80 M verify tokens). Measured on the macOS instance 2026-11-02 (audit-audit):
  - `scripts/local-machinery.py` listed measurement scripts beside a report under `docs/research/` as undeclared
    machinery — 28 of 32 "general/undeclared" items of one day. That folder is evidence, not machinery; a research
    script a hook or a schedule runs is still found by that carrier. Fixture case `research-scripts-are-no-machinery`.
  - `helpers/session-bootup.sh` measured its time budget against 30 s because no settings file names the hook since
    the core hooks ride the plugin; it now reads the plugin's own `hooks/hooks.json` (120 s) after the settings.
