---
name: kohaerenz-scan
description: DEPRECATED pointer (LA1 rename 2026-08-14) — the norm-stack coherence audit now lives in the skill "coherence-scan"; use that for contradiction registers and rule audits.
---

# Renamed: coherence-scan

The coherence audit of the norm stack moved to `coherence-scan`
(plugin: `brain-core:coherence-scan`), together with its workflow
`workflows/coherence-scan.js`. Use the new name in Workflow calls and auto-fire
tables; this pointer disappears with the next major version.
