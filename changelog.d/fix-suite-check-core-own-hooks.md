- **`suite-check.py` no longer judges the core's own `hooks/hooks.json` against the suite template** (test:
  `scripts/suite-check-test.py`, one new case) (level: reader; higher: writer - not needed, the template is right
  for suites and the core's hooks file is right for the core, only the reader mixed them up; debt: none known).
  Measured on the Windows instance 2026-11-06 at the release head f46f083 (#420): `suite-check.py .` on the core
  gave `WARN hooks/hooks.json: differs from the core template templates/suite/hooks/hooks.json`; the template
  came with 49ee8f4 and is meant for suites with an npm MCP server, the core wires its own gates. A checkout that
  carries `templates/suite/hooks/` is the core itself, and the comparison is skipped; on this branch
  `suite-check.py .` now reads 0 warnings. Agreed on #420 (issuecomment-6683042075, built by the Windows side).
