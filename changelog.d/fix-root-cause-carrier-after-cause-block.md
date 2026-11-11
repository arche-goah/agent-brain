- **root-cause-gate: the carrier is a CLASS carrier - invariant without the instance's names, replay with a count, and
  no release by the cause block's re-issue** (test: T1) (level: writer; higher: design — whether the mechanism written
  actually enforces the invariant is not machine-checkable here (an instance-tailored gate still counts as a mechanism
  write), a review stage would judge it; debt: a cause phrased without a cause word ("why X was wrong: …") is still not
  read as a cause, and a correction worded outside the pattern lists opens no inquiry) — measured on the macOS instance
  2026-11-11: (1) the Stop tier passed every re-issue after one block; a turn held for a MISSING cause whose re-issued
  reply named the cause ended without the carrier check — replay over 401 transcripts: 103 turns held for a missing
  cause, 34 named it afterwards, 28 of those wrote no mechanism in the turn. Now at most two blocks per turn, the second
  only for the carrier of a cause named after the first. (2) the register check took any write to the register file;
  of the instance's 330 register entries none names an invariant and 76 carry no replay count. Now the text written to
  the register in that turn needs `invariant:` (no path, no PR number, no instance proper noun from the new instance
  data `invariant_forbidden`) and `replay:` with a count (`pending` refused). Template `templates/carrier-register.md`
  gains the field. Fixture `scripts/test-root-cause-gate.sh`: ten new cases; the six blocking ones are red against main.
  After the Windows content review: a date or clock time is no replay count (`replay: 2026-11-11, not run yet` passed),
  a core rule number ("Working Rule #10") is no instance name (only a PR/issue number or a bare 3-digit `#nnn` is), and a
  register without `## ` headings is judged by its last blank-line block, not the whole file. Three more fixture cases;
  the date and rule-number ones were red against the previous head.
  Finding 4 of the same review: an edit that completes an entry of an earlier turn (only its `replay:` line) is judged
  with the `## ` entry on disk it lands in, not on its own text (fixture +2, the allow case red on the old head).
  Second Windows review: a `replay:` count is a number with what it counts (hits, cases, turns, sites, flips) or
  "<n> of <m>" - "waits for the v2.1.5 pin" and "after 3 sessions" no longer pass (fixture +3, two red on the old head).
  Debt: `\b\w+\.(js|...)\b` in INSTANCE_WORD still reads a product name like "Node.js" as an instance word.
