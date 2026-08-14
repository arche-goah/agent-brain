---
name: autonomous-run
description: Time-boxed autonomous work run ("arbeite die naechsten 2 h selbstaendig durch" / "work through the next 2 h on your own") — fix the reserve pool up front, arm the watchdog WITH a deadline, set ScheduleWakeup after every step, finish only at REMAINING 0 and report the measured time evidence. Use when the operator orders a run over a DURATION ("zieh das 2h durch" / "push it through for 2h", "arbeite n minuten/stunden autonom" / "work n minutes/hours autonomously", "/loop <auftrag>"). NOT for normal orders — there the rule is order done, then check-in.
---

# Autonomous Run (time-boxed)

> **Why this skill exists (incident 2026-08-02):** The operator ordered "komplett autonom
> durchziehen fuer 2h" ("push through completely autonomously for 2h"). What actually ran
> was **54 minutes** (08:49–09:43, proven by commit timestamps) — then the phase list was
> done, I disarmed the watchdog and reported, although the reserve pool still carried
> four items.
> **Three causes, all mechanical:** (1) `ScheduleWakeup` was never set, although it was
> in my own plan — so there was no continuation mechanism at all; (2) the watchdog is a
> **reporter, not a motor** and was wrongly treated as the safety net; (3) nobody knew
> the deadline — neither script nor loop knew when the "2h" would be up. The times in
> the report were **estimated, not read off**.

## Distinction — which mode applies?

| | **Normal operation (default)** | **Autonomous run** |
|---|---|---|
| Trigger | any normal request | the operator names a **DURATION** ("2h autonom" / "2h autonomously", "arbeite n min durch" / "work through n min") or calls `/loop <auftrag>` |
| End | **order done → check-in with the operator** | **only when the time is up** (`remaining` = 0) |
| Tasks | exactly the order | the order **+ the reserve pool agreed up front** |
| Deriving own follow-up tasks | **no** | yes, but ONLY from the pool |

⚠ **Without a stated duration it is NOT an autonomous run.** When in doubt, ask — do not assume.

## The mechanisms (and what each one CANNOT do)

| Mechanism | What it does | Limit |
|---|---|---|
| **`/loop <auftrag>` without interval** | self-paced mode: I schedule myself again after every turn | knows **no total duration** — only intervals |
| **`ScheduleWakeup`** (tool) | **THE continuation mechanism.** Wakes me up again with the same `/loop` prompt; `stop:true` ends it | lives IN the session — if the session dies, the alarm dies |
| **`scripts/loop-watchdog.sh`** | external launchd guard: reports silence **and** an exceeded deadline; tracks start/deadline; `disarm` prints the **measured time evidence** | **reporter, not a motor** — restarts nothing |
| **`/schedule`** (built-in) | cloud routine at a fixed time / once at a later time | different use case: "start at X", not "run for n hours" |
| **`/loop 20m <cmd>`** | fixed interval | ⚠ **`2h` here would be the INTERVAL, not the runtime** — the most common mix-up |

**Mnemonic:** `ScheduleWakeup` keeps me running, the watchdog notices when I no longer
do, and the deadline lives in the watchdog state. None of them replaces the others.

## ⭐ The duration is a MINIMUM limit, not a cap (operator directive 2026-08-02)

**The core order beats the clock — in both directions.**

| Situation | Behavior |
|---|---|
| Core done **before** expiry (40 of 60 min) | work the **reserve pool** for the remaining 20 min |
| Time up, core **still open** (30-min order, core needs 45) | **push through until the core stands.** The reserve-pool question never arises. Effectively like a normal order that takes longer |
| Core done **exactly** at expiry | end |
| **No reserve pool agreed**, core done early | report and stop — invent nothing ([[auftragstreue-vor-aktivitaet]]) |
| **No duration named**, only tasks ("push R3-R6 through") | `arm <name> 30` **without** the third number. End = tasks done, not the clock |

⚠ **Never stop just because the minimum time is reached.** The number says "autonomous
for at least this long", not "stop then".

**Mechanically secured:** `core-done` marks in the watchdog state that the core order
stands. The deadline alarm fires **only** on *time up AND core done AND still running* —
with the core still open it stays silent on purpose, because overrunning is correct
there. `remaining` in that case explicitly says "CORE STILL OPEN: KEEP WORKING
(duration is a floor, not a ceiling)".

## Procedure

### 1. Before the start (with the operator, once)
- Record **order + duration**.
- **Discuss the reserve pool** and write it down (pattern: `testbench-v4-plan.md` §4b).
  Admission only if ALL four hold: documented as open · doable without operator/hardware ·
  no pending operator decision (there: only measure/prepare) · same order space.
- Clarify the **approval frame**: what I may write/change, what stops the run.

### 2. Start
```
scripts/loop-watchdog.sh arm <name> 30 <runtime-minutes>
```
The third number is new and is the core: **without it, nobody knows when the time is up.**

### 3. After EVERY work step (phase, task, tool)
```
scripts/loop-watchdog.sh beat        # prints REMAINING automatically
```
- **Persist** the result (runlog/plan status), so that an abort costs at most one step.
- **Set `ScheduleWakeup`** when the turn ends — with the same `/loop` prompt verbatim.
  Without the wakeup the run ends silently, exactly like on 2026-08-02.

### 4. Keep working while REMAINING > 0
Order: **main order → reserve pool (ordered before derived)**.
⚠ **An empty task list is NO reason to stop while time is left** — go through the pool
first. If that too is empty: report and stop (order fidelity, Auftragstreue #3), but
then **explicitly as "pool empty, time was still left"**, not as "done".

### 5. Finish — only when the core stands AND (minimum time up OR no pool left)
```
scripts/loop-watchdog.sh core-done   # as soon as the CORE ORDER stands
scripts/loop-watchdog.sh disarm      # PRINTS THE TIME EVIDENCE
ScheduleWakeup(stop: true)
```
The `disarm` output is the evidence that belongs in the report:
`disarmed: '<name>' ran 08:49 -> 10:49 = 120 min`.

## Hard gates

1. **No duration named → no autonomous run** (normal mode, check-in at the end).
2. **No reserve pool discussed → do not start** (otherwise the run drifts).
3. **Turn ends without `ScheduleWakeup` → the run is dead.** Set it before every turn end.
4. **Times in the report ALWAYS from `disarm`/`remaining`**, never estimated.
   (On 2026-08-02, "10:15/10:45" was reported; reality was 09:15/09:43.)
5. **Do not finish because the work feels done** — only `remaining` = 0 ends the run.

## Read time, do not compute it

Times come from `date`, `git log --date=format:'%H:%M:%S'` or the watchdog —
**not** from debug output of other machines (the TD Windows timestamps led to a
self-assessment that was off by one hour on 2026-08-02).
