- **hook-coverage: whether a wired copy is a declared deviation is asked of local-machinery.py, not read a second time** (test: T2) (level: reader; higher: writer — one key style for every declaration would make both brains rewrite their files, and the key rule (path prefix or command text) is local-machinery's own and stays; debt: none)
  Follow-up named in the content review of the declared-copy fix (2026-11-10): `hook-coverage.py` read
  `.claude/rules/local-machinery.json` itself and compared whole commands with the keys. One brain keys its
  declarations by command, the other by the script's path — the same declaration held on one and was
  unknown on the other. `local-machinery.py` gets `declared_live(decl, cmd, C, today)`: a key covers the id
  of the script the command runs or stands in the command text (the rule `judge()` uses), an alpha that
  matches decides and declares nothing past its date, every declaration needs a reason. `hook-coverage.py`
  loads that function and asks it; without the script nothing counts as declared. Fixture:
  `scripts/test-hook-coverage.sh` (four new cases: an undeclared copy at another path is named, a
  path-keyed declaration silences it, an expired path-keyed alpha and a declaration without a reason do
  not; the path-keyed case fails against the state before).
