- **root-cause-gate: "Carrier: none" releases only with the operator's own words** (test: T1) (level: reader;
  higher: writer — a check that a register "none" entry carries the quote too, not built: the Stop check is where the
  escape was taken; debt: register entries written before this change keep their bare "none" until re-checked) — the
  check accepted a reply line "Carrier: none - <reason>" as equal to a mechanism written, so the agent could always
  leave a named cause unfixed on its own say-so. Measured on the macOS instance 2026-11-02: 41 register entries
  "carrier: none", three written in one session to pass this check; the operator: a cause's fix at the root is built
  and secured mechanically, and that itself must be secured. Now the line counts only with `operator-ok: "<words>"`
  and those words must stand in one of the operator's messages of the transcript. Fixture
  `scripts/test-root-cause-gate.sh`: none without words blocks, an invented quote blocks, the real words allow.
