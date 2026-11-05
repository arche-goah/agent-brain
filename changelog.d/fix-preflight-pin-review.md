- **The pin review reads the members of a merge train: two instances, by hand** (test: T1) (level: writer; higher:
  design - one shared reader for the merge-request gate and the preflight, not built here because the gate judges one
  head sha while the preflight judges a whole thread; debt: the OK/NOT word lists stay in `saysOk`, the preflight adds
  its sentence split on top). Check 8 of `release-preflight.sh` took the train PRs as the PRs to judge and read any
  keyed line with an OK word and the word Windows as the Windows proof. On the macOS instance 2026-11-04 it said OK for
  eleven trains while 62 of 83 member PRs merged since v2.1.2 carried no Windows hand review, and the one text it took
  was that instance's own macOS comment naming the Windows CI job (a CI job is no review, operator 2026-11-02 and
  2026-11-04). Now a train's manifest is expanded to its members (the `- #n` lines above "Left out"), a text whose
  first line reads as a CI note is skipped, the macOS and Windows proofs must come from two different instance keys,
  and a line is judged per sentence with a bracket that says "against main" read as a negative control - four
  Windows-instance PRs (#376 #377 #379 #385) had read as "no Windows" on their own test line. Fixture: four new cases,
  each red against the old script; live at v2.1.3 the check now names 42 PRs without a second-instance hand review.
