- **templates/suite/hooks: the npm-dependency hook of a plugin server ships as a core template; suite-check warns on a copy that drifted** (test: T1)
  (level: design; higher: none - the hook has one home, every suite consumes it unchanged and the check reads the
  drift; debt: the two suites that carry a copy today (grandma3-suite, chataigne-suite) still take the template in a
  small PR each, and a suite that deviates on purpose has no field yet to write its reason into - suite-check's WARN is
  the reminder until then).
  Measured 2026-11-03 on the macOS instance (plugin cache grandma3-next 1.1.31, chataigne-next 1.0.4):
  `hooks/ensure-deps.cjs` lay in both suites with the same logic, 105 lines, differing only in the five lines that name
  the suite; `hooks/hooks.json` byte-identical. Every further suite with an npm server (touchosc, content-toolsuite,
  resolume) would copy it again, and a fix in one copy reaches no other. Agreed with the collaborator's AI 2026-11-04
  (shared memory core/reply-ensure-deps-as-a-core-template… — none of their suites ships a plugin server today) and
  ordered by the operator the same day. The template reads the plugin's name from `.claude-plugin/plugin.json` (no
  per-suite edit); `scripts/suite-check.py` compares a suite's `hooks/ensure-deps.cjs` and `hooks/hooks.json` with the
  pinned core's template (CRLF-insensitive): equal = INFO, different = WARN (a suite may deviate with a reason), absent =
  nothing. Fixture `scripts/suite-check-test.py`: five cases.
