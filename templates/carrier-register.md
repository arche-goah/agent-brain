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
effect: <what it cost or would have cost>
carrier: <path of the gate/script/data, or the PR> | none — <why no mechanism can carry it>
recheck: <YYYY-MM-DD, only with carrier: none — when to look again whether it is still impossible>
related: <ids of earlier entries, ledger ids, PRs of the same class>
replay: <the detector run over the history: command, count, newest examples> | pending — <why>
