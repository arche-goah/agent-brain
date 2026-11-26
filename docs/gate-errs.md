# A gate that errs is a finding

> Full text of the short rule in `rules/working-rules.md`, Mechanism Discipline, right after "A refusal is a decision".
> Operator decision 2026-11-23 (translated: "build the core functions that are needed, or hand them to helper
> sessions"); the gap it closes was measured the same day.

## The gap

`rules/working-rules.md` knew two answers to a hook refusal: follow it, or pass it by its marker. "The gate was wrong"
did not occur. A search over `rules/*.md` for false positive, malfunction or wrong found nothing. A marker cost the gate
that made it necessary nothing, and no count reached anyone.

Measured over 605 transcripts of the macOS instance:
- 4048 decision refusals, 994 of them passed by a marker;
- CONDITIONAL-ORDER-GATE: 224 of 375 passed by its own `# CONDITION-NONE`, and that marker stands in 3352 calls. Most
  of those were written before any refusal, which shows the gate was expected to misfire.

## The rule

1. **A refusal decides the STEP, never whether the GATE was right.**
2. **Classify in the same turn.** Three refusals are classified in the turn they happen:
   - a refusal passed by its override marker;
   - a refusal of the step the operator asked for;
   - a refusal the carrier register already holds for the same gate and tool.

   The classes are *intended*, *gate false positive* and *own mistake*. A false positive gets its cause and its
   register entry like any other mishap (`rules/thinking-protocol.md`, root-cause inquiry). An earlier entry's fix
   counts only once it is in force; an open pull request is no fix.
3. **Every override marker counts against its gate.** A gate whose refusals are mostly passed by its override marker is
   named at the session start with its rate. Its repair is a follow-up (Working Rule #11).
4. **No licence either way.** A marker without the classification is the refusal re-issued, and unwiring a gate stays
   the operator's word.

## Override marker or rule path

A rate alone cannot tell "the gate errs" from "the marker is the intended way":

- **Read-then-confirm.** For a gate like PRS-FIRST (`# PRS-READ: <which one is closest>`), the marker records the
  reading the gate asks for. A high rate there is the rule working.
- **Override.** A marker like `# CONDITION-NONE`, `# MECHANISM-OK: <why>` or `# OVERLAP-OK: <why>` says the gate's
  judgement does not apply.

Which kind a marker is, and which marker belongs to which gate, is data: `gate-markers.json` at the core root, with
`markers` and `rule_path` per gate label and the gate's own words as `why`. It is not read from source text: a mapping
read that way miscounted markers like BETA-MERGE and PR-CLASS-OK. A gate without an entry is listed with `--rates` and
judged by nobody until it has one.

## Carriers

- `core/scripts/gate-health.py`
  - **At the session start:** it names a gate whose decision refusals in the last 14 days number 20 or more, with more
    than half passed by its override marker.
  - **How a pass is counted:** the next call of the same tool with the same intent carries the gate's marker, either in
    the call or as a line in the answer before it.
  - **Without a marker:** a gate whose refusals mostly pass in **another form** is named too ("is bypassed often").
    Every gate is rated that way, and the incident's gate has no marker at all.
  - **`--rates`** prints gate · refusals · by own marker · rate · rule path · calls carrying its marker · other form ·
    never passed. An identical retry is the gate's way on, not another form.
  - **Cache:** counts are cached per transcript.
- `core/helpers/root-cause-gate.cjs` (same train, #640): the turn-time carrier of rule 2. A refusal passed by a
  marker is the blocking signal `marker-pass`; the turn holds until its line is classified **with its backing**:
  *intended* quotes the marker or plan line that stands in the turn, *gate false positive* writes its register entry in
  the turn, *own mistake* opens the cause path.
- The refusal register lookup (same train, #643): a refusal the register already holds for the same gate and tool.
