- **The python3 run-probe check sees an env prefix inside a command; the deadline fixture probes its interpreter** (test: T1)
  (level: writer; higher: design - one shared interpreter resolver every shell file sources; not built, the probe line
  is one line per file today; debt: a choice spelled another way, such as `exec python3`, is still not counted).
  Measured 2026-11-04 on the Windows instance during the hand review of the merged PRs: `scripts/test-bootup-deadlines.sh`
  (from #397) failed 6 of 7 cases on Windows, every output "deadlines: docs/business/deadlines.md present - check it".
  Cause: the fixture runs the bootup's deadline block with `PY=python3` as an env prefix; on Windows `python3` is the
  Microsoft Store stub, and the bootup's own probe (`helpers/session-bootup.sh` line 20) is not part of the block.
  A/B: the same fixture with `python` passes 7/7. `scripts/test-python-probe.sh` (OS-17) did not flag it, because
  its pattern only counted a choice at the start of a line. Now it also counts an env prefix after whitespace, with a
  new negative control (`bad-inline.sh`); the old fixture is flagged, the fixed tree passes.
