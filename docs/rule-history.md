# Rule History

The incidents, measurements and past states behind the always-loaded rule files in
`rules/`. The rule files carry only the rule, its date and its carrier; what moved
out of them stands here verbatim, under the section it came from. Protocol, not
rule: nothing here changes what an agent must do.

## rules/working-rules.md

### Working Rules

A red check found days
   later is a check nobody watched (measured: a PR sat red while the session reported
   the others green).

(operator 2026-10-13: "that blocks every
   other activity — with several core PRs waiting on CI, hours go by")

Measured the day the
   rule was written: 65 of 263 ci-watch calls in three days ran in the foreground.

Measured that day: five pushes to PR branches, four watched;
   the fifth went red (runner never acquired) and the operator found it; six merges, none
   watched.

The core repo is public, so "push to a public repo" alone
    gated every core branch — and collided with merging core PRs without a word per PR.

, after three incidents in three days

### File Rules

`bootstrap-brain.sh` writes `.gitattributes`
into every new brain (line-ending class), and it MUST live in root so the rule
applies repo-wide; `.gitmodules` is created by git as soon as the same script mounts
`core/` as a submodule (`bootstrap-brain.sh`, `git submodule add`) — the location is
dictated by git and cannot be moved. Both stood in opposition to the rule that
produces them.

### Project Lifecycle (operator order 2026-08-14)

Measured: a catch-all held 150 entries, whole projects among them, because
   nothing said when an area is due.

### Mechanism Discipline (HARD)



The three questions above do NOT catch this: a cleanly
built second path passes all three — and is still wrong, because the question
"should a second path exist here at all?" is never asked.

(Coherence scan of a Windows
instance, 2026-10-12: a loaded skill still called the raw API merge a "second legitimate
form" while `collab-watch` forbade exactly that.)

(coherence finding 2026-09-18: the decision
was spread over a dozen rules on three ranks, and the stop gate and this section gave
opposite answers for the same case)

Split out of the adjacent step on 2026-10-12 (operator decision): the two
   cases shared one step and one outcome — note it and continue — which fits an adjacent
   idea, but turns a NEEDED subtask without a path into exactly the improvisation this
   section names.

Measured on
a collaborating brain the day the rule was written: "dann coherence scan" — then, after the
two instances asked had answered — was read as "now", and nine analysis agents ran before
the answer came.

(Incident 2026-10-11: a defined path was
not available on a second machine; the session built its own client and wrote straight
into the tool's IPC file instead of reporting. Not available = report, THIRD CASE above.)

(incident 2026-09-12: two merges in a shared repo carried the marker with a verbatim quote
that stands in no transcript of that day — the gap it should have shown was papered over by
the invented evidence)

### One System, Not Local Workarounds (HARD, operator order 2026-10-08)

(measured 2026-10-09: three
  items declared instance-only were general)

(operator order 2026-10-11: no
special-purpose tinkering — here, at collaborators, in other instances)

Measured the day the rule was written:
two collaborator forks, their main far behind, about twenty leftover branches of merged
PRs, one fix that had lived only on a fork branch for six weeks, and one open PR still
served from a fork.

(operator, same day: "the human does not
have to be bothered every time something deviates, but there should be a classification and
analysis of what deviates, why, whether that makes sense, and whether something should move
into the core as a PR")

It
inventories EVERY carrier of behaviour — the search space is the invariant, not the last
incident: hooks, stop checks, MCP servers, git hooks, scheduled jobs, extra plugins, skills,
workflows, output styles, agents, commands, rule sections, scripts — and names every item
that is neither core nor declared with evidence, every undeclared item that contains none of
the instance's `identity_tokens` (presumably general), every near-duplicate of a core tool
under another name, every expired alpha, and every file edited inside `core/` (the pin check
sees moved commits, not edits in place); one summary line counts each class.

Measured on
the proving brain the day the rule was written: 12 of 31 hook entries ran from unmerged
checkouts, 8 from instance scripts — at least four of those general mechanisms — and
nothing had reported it, because every one of them worked.

### A Needed Reload Is Not a Wait State (operator order 2026-08-06, sharpened 2026-08-14)

A change to a tool that only takes effect after the server reloads ends many turns with
"this needs a restart" — and then the agent waits for a human reply. That is a wait
state the agent can dissolve itself.

### Working Across Parties

(operator order 2026-10-11, after a hand-over
   between the operator's own machines lay unseen until the operator asked on every side)

(operator correction 2026-10-11: "you crossed each other
   there for nothing — that costs time")

Measured the day the rule was written: one finding,
   two fixes from two machines three minutes apart (one closed), and a merge over the finding
   because a reader showed 200 characters of the comment.

## rules/intelligence.md

### Session Start (mechanical + Claude's part)

(operator order 2026-10-12, after a coherence scan counted more than ten
first-reply requirements spread over this section, each with its own date, and a blocking gate
behind them)

, after an audit of the audit process

(operator, 2026-10-09: "technical terms that mainly serve internal and AI logic —
always weigh whether the human really needs the code, or whether it hinders more than
it helps")

, second pass —
translating everything is not the point either

folding a FAIL/`!!` line into the middle of a
prose summary satisfies the letter of the boundary above but not its point — the
finding reads as one more status clause among several and gets lost exactly the
way the terseness rule was designed to prevent for everything else.

(Incident: a mini-summary listed "brain-check: needs
a look" as one clause among five in a single sentence; the operator had to call it
out explicitly before it got the visibility the boundary rule already entitled it
to.)

(a standing approval, full-audit 2026-10-15 on a Windows instance: its rules said
requests addressed to that machine are handled without asking, and the first reply asked
anyway)

(operator correction
2026-10-10: "I want to hear that question mainly at the session start, not again
and again")

(Incident: the bootup listed nine open requests and six PRs; the first reply said
"nine older requests, nothing new" and named none — two days after the data side had
been fixed, because the relay side had no carrier.)

### Auto-Organization (ALWAYS)

(measured 2026-08-04: one entry flipped one minute after being
   written)

, full-audit E2

; on 2026-08-04 two files had to be renamed because of this

(full-audit M12)

—
   measured 2026-08-04: block 7 entries and "OPEN", file 9 entries and "RESOLVED"

—
   a skill's injected code snippet showed `PR ~ /^PR /` where disk (repo, tag, plugin
   cache) says `$0 ~ /^PR /` everywhere; a defect report or PR derived from injected
   text alone would have "fixed" a bug that does not exist

### Knowledge Carriers (lesson → invariant → carrier)

(self-diagnosed on a
live instance 2026-08-19: domain rules remembered per incident, not derivable
from how the system works — errors repeated despite the notes)

("stays where I let
go", "even when no finger holds it")

(Incident 2026-08-20: the front question
slid from "which procedure do I use" to "what is this case in general" before a
single observation was in; a summary built on that guess was refuted by the
operator's second observation in the same message, and a decision draft had
already been stacked on it.)

(incident 2026-08-19, `macro5001`: written from session memory a day AFTER
   the decision it silently omits, then followed instead of that decision)

Measured gap (operator finding 2026-08-20): a loaded skill answered step 1
   with "yes", step 2 asked only about TOOLS, and step 3 fires only when there
   is NO skill — so a skill that exists and does not describe the procedure
   fell through all three, and the work got improvised next to it for half a
   day.

Measured on a proving brain: a whole suite sat parked
for weeks over one tool boundary, and nothing named which work the boundary actually blocked.

### Presenting to the Operator

 — reading every one costs hours to days

(order of the Windows instance's operator, 2026-10-15, after a report ended on a prose
  list he could not answer — "ask me a clean question" — and three decisions then reached
  him through the tool: "the way you just asked me, cleanly and interactively, I want it
  always for operator decisions"; both translated)

(measured 2026-10-15 on
  a Windows instance: four records for one question, three of them rewordings)

(operator decision
  2026-10-11: "yes, the AI may close its own settled questions — but set it up cleanly,
  document and justify it")

Justification: the gate exists so
  that a question does not scroll away unanswered — a question the work has answered is not
  that case, and a human made to close it by hand is pure friction (measured 2026-10-11 on a
  Windows brain: the agent's `resolve` call was refused by the harness classifier because
  that brain lacked the template's `Bash(node core/helpers/*)` permission, and the operator
  had to run it; the macOS brain, which carries the permission, closed three such questions
  the same day).

### Model Routing

Reference measurement brain-scan (core PR #30,
run 2026-08-10): 9 of 11 agents small, ~778k of 1.02M tokens, all results valid.

(measured 2026-07-10: a
resume of a two-strand run missed the cache for all but six agents, ~8M tokens twice)

, four
failures in one workflow

(measured:
1 of 141 rows survived a "create a table" relay; 22 of 141 survived "return the
JSON UNCHANGED, you are a pipe"; a count field next to the array stayed correct
while the array was cut)

### Repeat Runs (CANONICAL place — skills point here)

(measured 2026-08-04: a register reported
"24 raw → 18 consolidated" and derived a gap from it, while the record said
108 → 19 → 12; the supposedly missing findings had been discarded in verify)

## rules/thinking-protocol.md

### Anti-Hallucination Rules

— two incidents in one day

(Incident: a fact from the visuals box transferred to the MacBook —
     the fact was right, the machine was not.)

(Incident: TD DAT survives inside the .toe → the "measurement" was 1.6 h old
     history.)

(Incident: "completed yesterday" claimed for an event
     whose install record said SAME day — "yesterday" was derived from the phrase
     "next session" in a note, never from a timestamp.)

(Incident 2026-08-04: a
     register counted "24 raw → 18 consolidated" and derived a gap of six findings
     from it; the record said 108 → 19 → 12, the "missing" ones had been discarded in
     verify. The recommendation derived from it would have cost 1.5 million tokens.)

— treating a
   remembered rule as a fixed text to replay is stimulus-response, not
   understanding, and it fails silently in exactly the case where a new
   situation looks similar but differs in the load-bearing detail.

(Incident: an instance held two memory entries from different sessions
   that read as contradictory; both were correct once the actual mechanism
   was traced out — the text-level pattern match had missed the
   distinguishing condition entirely, and no contradiction existed once
   restated causally.)

### Class Discipline (pointer — the mechanism lives elsewhere)

(measured on a proving instance: five classes, up to 15 single fixes of the same
root in 12 days)

### Confidence Assessment

(coherence-scan
K-13, 2026-08-01)

### Priority Hierarchy on Contradictions

Rank 2 added on 2026-08-04 (operator decision, coherence-scan P1-2): the HARD blocks
were not located anywhere in this list at all — neither above nor below feedback.
They asserted their precedence only themselves. The fourth HARD block, "One System, Not
Local Workarounds" (operator order 2026-10-08), joined rank 2 on 2026-10-15 — the same
defect, found by the coherence scan of a Windows instance: a HARD block without a rank.

### Rule-Conflict Protocol (operator instruction 2026-08-01, from coherence-scan K-19 — CANONICAL place)

Measured on a proving brain the same day:
   18 of 24 general-looking operator rules existed only in the instance — written
   down twice (protocol + compact rule), never asked where they belong.

Measured: a rig rule allowed port-dropping writes only during
   load-in, another allowed only port-neutral writes during load-in — read together,
   never; both stood unflagged for weeks.
