- **root-cause-gate: a cause named only after the cause block still owes its carrier** (test: T1) (level: writer;
  higher: design — one turn-end state machine for all Stop checks instead of a per-gate "fired" flag, not built here
  because it touches every gate; debt: a cause phrased without a cause word ("why X was wrong: …") is still not read as
  a cause, so the turn passes on its re-issue) — the Stop tier let a correction turn pass on its re-issue as soon as it
  had blocked once. When that first block asked for a MISSING cause and the re-issued reply then named one, the carrier
  check (mechanism + register) never ran: the turn ended with the cause named and nothing built, and the operator had
  to ask a second time why the cause found was neither researched further nor fixed. Now a turn may be held twice: once
  for the cause, once more for the carrier of a cause that came after that block; a first block that already was the
  carrier block passes on its re-issue as before. Replay over the macOS instance's 401 transcripts: 103 turns held for
  a missing cause, 34 named the cause afterwards, 28 of those wrote no mechanism in the turn. Fixture
  `scripts/test-root-cause-gate.sh`: four new cases (block, at-most-two, allow with carrier, carrier-block re-issue);
  the block case is red against the gate on main.
