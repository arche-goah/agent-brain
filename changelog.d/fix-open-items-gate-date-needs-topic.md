- **open-items-gate: the relabel check judges the newest reply only, and a date alone is no mention** (test: `scripts/test-open-items-gate.sh` +4, both allow cases red against the v2.1.4 gate) (level: reader; higher: writer - give every item an id the reply must quote, not done: replies name requests by date and topic in prose, an id would be a second vocabulary; debt: the other checks of this gate still read `last` (every reply since the newest operator prompt) — right for the first-reply and close checks, not re-measured for the "nothing open" branch)
  Measured on the Windows instance 2026-11-11, an autonomous run, five blocks in a row the agent could not end:
  1. The relabel check read `last` — every reply since the newest OPERATOR prompt. In the run that prompt was hours
     old (watcher events, ticks and hook echoes are no prompts), so one early line ("#453 and #454 … with the macOS
     side") held every later reply, however it was worded. Now the check reads `newest`: the text since the newest
     user record of any kind (prompt, event, echo). Live A/B on that transcript: v2.1.4 blocks, this head allows.
  2. `strict()` took any line holding an open item's date as a mention: a BLOCKED line with the ledger id
     `…-2026-11-11` was read as a request of that day. The date now counts only with one of the item's own topic
     words (`topicWords`, generic words left out) in the same line; `#n` and the exact file stem are unchanged.
