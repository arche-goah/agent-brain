# Carrier register

One entry per named cause: what happened, why, what carries it now — or why nothing can, with a
date to look again. Written in the SAME turn as the cause (helpers/root-cause-gate.cjs checks the
write); re-read by `node helpers/root-cause-gate.cjs --review` (due rechecks, entries without a
replay) and the skill `root-cause-review`. Newest at the bottom; an entry is never deleted — a
carrier that is replaced gets a new entry that names the old one under `related`.

Copy this file to the path the instance names as `carrier_register` in
`.claude/rules/root-cause-patterns.json` (default `docs/maintenance/carrier-register.md`).

## YYYY-MM-DD — <the incident in one line>
id: <stable slug>
incident: <what happened, where (session, PR, file:line)>
cause: <what was read, where — A produced B>
invariant: <the rule that was broken, without the instance's names: no path, no PR number, no proper noun — checked>
effect: <what it cost or would have cost>
refusal: <GATE> <Tool> — only when the incident is a hook refusing a tool call (e.g. `refusal: AUTONOMOUS-GATE AskUserQuestion`):
  the key the lookup matches when that gate refuses that tool again (helpers/refusal-register.cjs) - a repeat is then
  no first case
carrier: <path of the gate/script/data, or the PR> | none — <why no mechanism can carry it>
effective: yes — <how it was measured that the carrier is in force here, date> | no — <why: the PR is open, merged but
  not pinned, the gate not wired> — a pull request is a carrier only once it runs; `--review` lists a PR carrier without it
recheck: <YYYY-MM-DD, only with carrier: none — when to look again whether it is still impossible>
related: <ids of earlier entries, ledger ids, PRs of the same class>
replay: <the invariant run over the history: command, count, newest examples> — a count is required in the turn
  that names the cause (the gate refuses "pending"; a fix that was not replayed has not found its class)
