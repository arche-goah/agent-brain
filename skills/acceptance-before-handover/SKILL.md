---
name: acceptance-before-handover
description: "Acceptance before every handover to the operator, for every tool (3D, node tools, web, images, documents): check the WHOLE result with the operator's eyes instead of only the agent's own task list - follow the operator's words literally, record the operator's facts about reality and let them beat the files, inventory everything visible (helpers out), test against reality, test a proposal against the named problem, get fresh eyes from an agent without context. Use before showing any render, preview, screenshot, interface or draft; scripts/acceptance.py open shows an image only with a fresh acceptance."
---

# Acceptance before handover

Operator order 2026-11-23: the behaviour that led to half-finished results "should work for everything" and "be in the
core brain"; and: "find out why you do not really follow my word".

## Why it happens (the causes, not the symptoms)

1. **The agent checks against its picture of the task, not against the result.** "Did I do X?" asks the agent's own
   list. The operator sees the whole result, including everything the agent never touched.
2. **What the agent adds on the side belongs to nobody.** Labels, helper lights, markers, candidates are made for the
   agent's thinking, inside the very artefact the operator receives. Workspace and handover are one file, so the
   helpers stay.
3. **The operator's statements about reality do not become constraints.** "The wall goes up to the ceiling" stayed a
   sentence in the chat; the model file was measurable, so the file won.
4. **The quickest solution, not the real one.** A round spot where a projector throws a rectangle - nobody asked "would
   it look like this in reality?".
5. **The builder sees the intent.** A look at the result searches for the change, not for foreign bodies. That is
   why it needs eyes from outside.
6. **A proposal is not tested against the problem.** A proposal can sound helpful and change nothing about what the
   operator named.
7. **The operator's word is translated, then the translation is served.** The agent turns the words into its own task
   model, picks the path in reach (local instead of core, a question instead of the build), and reports the
   translation as done. The rule stack in context is many times louder than the operator's one sentence; the agent
   resolves conflicts by a compromise that satisfies the rules, not the word. Core rule: order fidelity #4a - a
   substitution is said BEFORE it happens.

## Procedure (before every handover, every tool)

1. **Word first.** Quote the operator's load-bearing words of the order (nouns, places, "everything", "in the core").
   Each one is a deliverable. A step that does something else is a substitution: say it before, with the reason the
   original is not reachable.
2. **Facts.** Every statement of the operator about reality (room, device, material, what an image should show) goes
   at once as one line into the instance's facts file of the project (date, verbatim, consequence). From then on the
   list wins over any file: where the model disagrees, the model is changed, not the operator asked again.
3. **Inventory.** List everything visible in the result. Each item the agent added on the side is removed or kept with
   a reason. Every light has a real source.
4. **Reality.** One sentence per element: would it look, stand, behave like this in reality?
5. **Problem test** for proposals: one sentence "what does this change about what the operator named?". Nothing ->
   no proposal.
6. **Fresh eyes.** An agent gets ONLY the result and the operator's words, no plan: "what does not belong, what looks
   wrong, unrealistic or unclean?" Each finding is fixed or rejected with a reason. Price: one agent per handover
   (measured in one instance session 2026-11-23 on the smallest model: 140-165k tokens and 30-100 s for 2-12 images);
   pick the smallest model that can read images.
7. **Write the acceptance.** `python3 scripts/acceptance.py write <result> --inventory ... --facts ... --fresh-eyes ...`,
   then `python3 scripts/acceptance.py open <result>` (opens only when accepted; browser, not the OS image viewer).
8. **Report in the operator's words and order:** each quoted word from step 1 -> done / not done / substituted, and
   where it can be seen.

## Carrier and limit

- Mechanical: `scripts/acceptance.py open` shows an image only with a full acceptance bound to its bytes (sha256 and
  size); an instance wires its
  own opener through it and blocks the bypass (an instance `mechanism-rules.json` rule on opening images directly).
  Self-test: `python3 scripts/acceptance.py selftest`.
- Limit: results that are no file (text in the chat, a live interface) are seen by no gate; there this procedure
  carries as text. Whether the fields are honest is not checked, only that they exist and are fresh.
