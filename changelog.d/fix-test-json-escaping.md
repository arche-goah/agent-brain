- **Fixture helpers build their hook input with node, not printf** (test: T1) (level: writer; higher: design - one shared
  hook-input builder for every fixture, not built here because each fixture sets its own fields and env; debt: three printf builders that interpolate only the fixture's own temp
  paths stay, `test-conditional-order-gate.sh` (the no-tool-input case), `test-skill-gate.sh` (missing transcript),
  `test-session-helpers.sh`). Eight helpers in seven fixtures (`test-guards.sh` mg_probe + tr_probe,
  `test-autonomous-gate.sh`, `test-conditional-order-gate.sh`, `test-live-read-gate.sh`, `test-no-input-control.sh`,
  `test-skill-gate.sh`, `test-shared-working-copy-guard.sh`) wrote their values into a `printf` JSON template unescaped:
  a bare double quote in a probe broke the JSON, the guard exited 0 on bad input, and the probe read as "allow" although
  the guard never parsed it (measured on the macOS instance 2026-11-02 with a `commit -m "x"` probe). The input is now
  built by `JSON.stringify` from argv; the call signatures stay, and the probes that write `\n` / `\"` as JSON escapes
  keep working (`unesc()`). One new probe per helper carries a bare double quote and must block; on a file system that
  refuses `"` in a name (Windows) the path-based ones print SKIP.
