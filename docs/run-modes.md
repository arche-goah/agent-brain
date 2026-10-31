# Run modes: INTERACTIVE and AUTONOMOUS

The one place that explains what the two modes of a brain's AI mean, what they do NOT mean, and how the operator
switches. When an operator asks their AI "what does autonomous / interactive mean?" or "how do I switch?", the answer
is this page plus the instance's own word lists (below).

## Where the mode comes from

`helpers/autonomous-mode.cjs` reads the operator's words in the session's transcript and keeps a latch. Every gate
that behaves differently per mode reads this one function — there is no second copy, no setting, no file. Each session
has its own mode (its own transcript); five parallel sessions can show five different modes. A fresh session is
INTERACTIVE. The status line shows the mode of its session at the right end (`helpers/statusline.cjs`).

## INTERACTIVE (the default)

- The AI asks the operator AT ONCE when a decision belongs to the operator — through the question tool, with a
  recommendation (`rules/intelligence.md`, "Presenting to the Operator").
- A turn may end on a report or a question.

## AUTONOMOUS

- **No additional rights.** The same permissions, refusals and gates apply as in interactive mode. Nothing that is
  irreversible or externally effective (deploy, publish, release, money, hardware, a live write outside its agreed
  frame) becomes allowed — it waits for the operator's word as a collected point.
- **Questions are collected, not asked.** No question-tool call, and no call that a permission `ask` rule would turn
  into a dialog: `helpers/autonomous-gate.cjs` refuses both before the harness shows anything; the step goes into the
  instance's ledger as a point for the operator, and the AI goes on with what is safely doable.
- **The AI keeps working.** A turn does not end on a status report; it ends only with a measured end line —
  `BLOCKED: …` (every item left waits on something named) or `POOL EMPTY: …` — read against the brain's own-items
  list in that turn (the idle Stop check, core #195).
- **When the operator asks what is open**, the mode switches to INTERACTIVE (the operator is here): all collected
  points come as question-tool questions, and the last one is "continue autonomously?" — a yes switches back.

What autonomous mode is NOT: not a permission level, not a way past an `ask` rule, not a licence for irreversible
steps, not a time-boxed run. A run over a stated DURATION ("work through the next 2 h") is the skill
`autonomous-run` (reserve pool, watchdog, deadline) — it runs in autonomous mode, but the mode alone has no deadline.

## Switching

The operator switches with words in the session — a click cannot (a status-line link only opens a URL):

| To | Built-in English words | Also |
|---|---|---|
| AUTONOMOUS | "autonomous(ly)", "work through it alone / on your own", "I'm away" | yes to "continue autonomously?" |
| INTERACTIVE | "normal mode", "stop autonomous", "no longer autonomous" | asking what is open ("anything open for me?", "what is open?") |

A remark in between ("status?", "the desk is running") keeps the mode. The operator's own language is instance data:
`.claude/rules/autonomous-patterns.json` (`on_patterns`, `off_patterns`, `yes_patterns`, test cases in `_cases`) and the
`ask_patterns` of `.claude/rules/open-items.json`; template `templates/rules-instance/autonomous-patterns.json`. An AI
asked "which words switch the mode here?" reads those two files of its own brain.

## Carriers (what enforces each part)

| Part | Carrier |
|---|---|
| the latch | `helpers/autonomous-mode.cjs` (`promptModes`, `autonomousMode`) |
| no question tool, no ask dialog | `helpers/autonomous-gate.cjs` (PreToolUse) |
| no closing question in prose; questions only when asked | `helpers/stoppen-gate.cjs`, `helpers/decision-presentation-gate.cjs`, `helpers/question-gate.cjs` |
| open items in the first reply / no "shall I?" in the mode | `helpers/open-items-gate.cjs` |
| no idle turn end | idle Stop check (core #195) |
| the display | `helpers/statusline.cjs`, labels `statusline_labels` in the instance's `autonomous-patterns.json` |
