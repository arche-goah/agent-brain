- **commitments: a promise taken back in its turn is no loose one; a promise the loop brake let through is named as such**
  (test: T1) (level: reader; higher: writer — exempting commitment-carrier-gate from the stop dispatcher's loop brake
  would stop such turns from ending uncarried; not built: the brake exists because this very gate once held a turn
  33 times, and the take-back is the way out it already offers; debt: a braked turn still ends uncarried, the
  report only names it at the close) — measured 2026-11-16 on the macOS instance by replaying the 41 promises this
  report listed as loose over 20 days through each turn's transcript: 19 had been held by the gate and then taken
  back in the same turn, 4 were the take-back sentences themselves (the gate clears them, the report never knew the
  take-back), 8 ended because the loop brake released the gate after three blocks, and the rest were reworded or
  carried. `scripts/commitments.py` now mirrors the gate: a text matching a take-back (the gate's built-in
  phrases plus the instance's `retract_patterns`) clears the promises made before it in the same turn and is no
  promise itself, counted as `retracted`; the dispatcher's `.claude-state/stop-loops.jsonl` entries of
  COMMITMENT-CARRIER-GATE in the window are listed as loose with the reason "released by the loop brake". Replay
  after the fix: found 17, retracted 34, loose 18 (11 from transcripts, 7 brake releases). Fixture
  `scripts/commitments-test.py` +5 (take-back clears, a take-back after a new operator message does not, instance
  take-back phrasing, a brake release is loose, another gate's or an old brake entry is not); against main 4 fail.
