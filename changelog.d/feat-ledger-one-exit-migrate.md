- **New `scripts/ledger-one-exit.py`: the one-time migration to one current `exit:` per open ledger entry** (test:
  `scripts/ledger-one-exit-test.py`, ten cases) (level: writer; higher: design - not taken here, the convention and its lint
  are that level and stand in their own PR of the same strand; debt: none). Ported from the macOS instance, where it rewrote 178 lines in 86
  entries on 2026-11-06. The newest exit by date stays (same date: the later line), the others become `was-exit:` with
  text and order unchanged; ticked entries are left alone; ledgers from the brain's `.claude/rules/ledgers.json`,
  `--root` names the brain (a core script's own folder is not the brain), preview by default, `--write` rewrites. The
  fixture checks that the lint's `MULTI_EXIT` finds one exit per open entry after the run. Real-data replay on the
  migrated brain: 0 lines left to rewrite.
