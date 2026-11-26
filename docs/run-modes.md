# Run modes: INTERACTIVE and AUTONOMOUS

The one place that explains what the two modes of a brain's AI mean, what they do NOT mean, and how the operator
switches. When an operator asks their AI "what does autonomous / interactive mean?" or "how do I switch?", the answer
is this page plus the instance's own word lists (below).

## Where the mode comes from

`helpers/autonomous-mode.cjs` reads the operator's words in the session's transcript and keeps a latch. Every gate
that behaves differently per mode reads this one function — there is no second copy, no setting, no file. Each session
has its own mode (its own transcript); five parallel sessions can show five different modes. A fresh session is
INTERACTIVE — unless the brain's `.claude/rules/autonomous-patterns.json` sets `"initial_mode": "autonomous"` (the
operator's standing word that every session runs autonomously until they ask what is open); the words below switch
it either way. The status line shows the mode of its session at the right end (`helpers/statusline.cjs`).

## The one difference

The two modes behave alike except in ONE thing: interactive asks a question for the operator AT ONCE (question tool),
autonomous COLLECTS it in the instance's ledger and goes on. Everything else is one law for both (2026-11-18), above
all the turn end: while own work is open — the autonomous run itself, entries the operator released in the session,
the AI's own open session-start findings — a turn ends only on a question (interactive only), a `HAND STEP:` line, or a
measured `BLOCKED:` / `POOL EMPTY:` / `LIST EMPTY:` line (idle Stop check, `helpers/autonomous-idle-gate.cjs`). The
mode question: optional in interactive whenever useful (a plan, then "work it through autonomously or stay
interactive?"); due only after a switch from autonomous to interactive, as the last question.

## INTERACTIVE (the default)

- The AI asks the operator AT ONCE when a decision belongs to the operator — through the question tool, with a
  recommendation (`rules/intelligence.md`, "Presenting to the Operator").
- A turn may end on a question; with own work open, otherwise only in the end forms above.

## AUTONOMOUS

- **No additional rights.** The same permissions, refusals and gates apply as in interactive mode. Nothing that is
  irreversible or externally effective (deploy, publish, release, money, hardware, a live write outside its agreed
  frame) becomes allowed — it waits for the operator's word as a collected point.
- **Questions are collected, not asked.** No question-tool call, and no call that a permission `ask` rule would turn
  into a dialog: `helpers/autonomous-gate.cjs` refuses both before the harness shows anything; the step goes into the
  instance's ledger as a point for the operator, and the AI goes on with what is safely doable.
- **The AI keeps working** — as in interactive mode (the one law above); the run itself counts as open own work, and a
  question is no end because it is collected.
- **When the operator asks what is open**, the operator is here for that turn: the question tool and the dialogs
  pass in it, whatever is or is not filed as open. ALL collected points come as question-tool questions, and the
  other interactive dialogs with them; the mode stays as it is meanwhile. AFTER them comes, as the last call, the mode
  question "continue autonomously?" — asked as the mode-confirm question (below, "Switching") — and only its answer
  switches (operator 2026-11-25; until then the core's implementation of 2026-11-23 ended the run at the first answered
  question). A turn that has nothing to ask says so in one line and the run stays AUTONOMOUS; a later turn the operator
  did not open (a timer, a finished background task) is outside that window again.

What autonomous mode is NOT: not a permission level, not a way past an `ask` rule, not a licence for irreversible
steps, not a time-boxed run. A run over a stated DURATION ("work through the next 2 h") is the skill
`autonomous-run` (reserve pool, watchdog, deadline) — it runs in autonomous mode, but the mode alone has no deadline.

## Switching

The operator switches with words in the session — a click cannot (a status-line link only opens a URL):

| To | Built-in English words | Also |
|---|---|---|
| AUTONOMOUS | "autonomous(ly)", "work through it alone / on your own", "I'm away" | "continue autonomously?" answered as the mode-confirm question |
| INTERACTIVE | "normal mode", "stop autonomous", "no longer autonomous" | asking what is open ("anything open for me?", "what is open?") |

**Two settings, chosen per instance** (operator 2026-11-25, "provide both options"): `"mode_confirm": true` in
`.claude/rules/autonomous-patterns.json` turns on the mode-confirm question described next; missing or `false` (the
default) keeps the direct switch - a mode word switches at once, as before, and nothing is held. The close words and the
ask window (all questions and dialogs, then the closing mode question) hold in both settings.

**With `mode_confirm: true` the words never switch by themselves** (operator order 2026-11-25): a word above that would CHANGE the mode - read
by the word lists or by the intent classifier - opens the mode-confirm question, and only its answer switches. Towards
autonomous the question offers what is to be handled autonomously, with "stay interactive" always as the last option;
towards interactive it asks "continue interactively?", the interactive option FIRST - the mode the operator's words name
comes first (operator 2026-11-26). The question carries the header
`mode-confirm` and a short explanation from this page (no extra rights; questions collected or asked at once). Until it
is answered the mode stays as it is, and the autonomous gate holds every call but reads and the question itself
(`helpers/mode-confirm.cjs`). A rejected question switches nothing; a word naming the mode already in force asks nothing. The mode question at the
end of a question dialog ("continue autonomously?") takes the same form: a mode question without the header is held.
**Closing the session is no mode switch** (operator 2026-11-25: "closing always closes"): a close word ("close the
session", "we're done for today"; the operator's language: `close_patterns`) ends the autonomous mode at once, with no
question.
A remark in between ("status?", "the desk is running") keeps the mode. The operator's own language is instance data:
`.claude/rules/autonomous-patterns.json` (`on_patterns`, `off_patterns`, `yes_patterns`, test cases in `_cases`) and the
`ask_patterns` of `.claude/rules/open-items.json`; template `templates/rules-instance/autonomous-patterns.json`. An AI
asked "which words switch the mode here?" reads those two files of its own brain.

## Carriers (what enforces each part)

| Part | Carrier |
|---|---|
| the latch | `helpers/autonomous-mode.cjs` (`promptModes`, `autonomousMode`) |
| a mode word only opens the mode-confirm question | `helpers/autonomous-mode.cjs` (`confirmPending`), `helpers/mode-confirm.cjs` (hold + Stop row MODE-CONFIRM) |
| no question tool, no ask dialog | `helpers/autonomous-gate.cjs` (PreToolUse) |
| no closing question in prose; questions only when asked | `helpers/stoppen-gate.cjs`, `helpers/decision-presentation-gate.cjs`, `helpers/question-gate.cjs` |
| open items in the first reply / no "shall I?" in the mode | `helpers/open-items-gate.cjs` |
| no idle turn end | idle Stop check (core #195) |
| the display | `helpers/statusline.cjs`, labels `statusline_labels` in the instance's `autonomous-patterns.json` |
