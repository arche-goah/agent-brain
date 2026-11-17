- **hand-step-gate: a hand step the reply gives the operator must be theirs to take, with what they have at hand — ported from an instance alpha** (test: T1) (level: writer; higher: design — the device state and the operator's whereabouts as live sources the reply is built from, instead of a check after the reply; no such source exists in the harness; debt: a Windows COM port is not globbed, `device_globs` covers macOS and Linux device nodes only)
  Measured 2026-10-28 on the macOS instance: the operator, translated, "you flash, why should I?" — the reply had
  handed over a flash command block for a board on the AI's own USB port; the same day a reply asked for a multimeter
  measurement while the operator had said twice that he was away from the lab without one. New Stop check
  `helpers/hand-step-gate.cjs` (required row HAND-STEP-GATE in the stop-checks template, inert without data):
  `self_run_handed_over` (a code block with a `self_run.commands` command while a `device_globs` device is attached)
  and `not_at_hand` (an instruction line naming a `not_at_hand.items` thing inside its dated window; a line that says
  it waits passes); holds once; `--replay` over the transcripts. Every word is data
  (`templates/rules-instance/hand-steps.json`, English); the alpha's German "addressed" words were code and are now
  `addressed_words`. The alpha's rule-in-prose check is not ported — `commitment-carrier-gate.cjs` `proseRules`
  carries it since #173. Fixture `scripts/test-hand-step-gate.cjs` (16, both directions, the hook end to end).
