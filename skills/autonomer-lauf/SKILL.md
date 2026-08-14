---
name: autonomer-lauf
description: DEPRECATED pointer (LA1 rename 2026-08-14) — the time-boxed autonomous work run now lives in the skill "autonomous-run"; load that one for reserve pool, watchdog and ScheduleWakeup mechanics.
---

# Renamed: autonomous-run

The time-boxed autonomous work run moved to `autonomous-run`
(plugin: `brain-core:autonomous-run`). Load and follow that skill; nothing of the
run mechanics is documented here anymore. Auto-fire tables still matching on
`autonomer-lauf` should switch their target — this pointer disappears with the
next major version.
