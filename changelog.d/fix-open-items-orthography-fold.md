- **open-items-gate: an item's topic words are compared orthography-folded, so a reply in the operator's language names an ASCII slug** (test: T2) (level: reader; higher: writer — a slug is ASCII by the naming convention and a reply follows the operator's orthography by the language rule, so neither writer can change; the compare is where the two meet; debt: none)
  Measured 2026-11-04 on the Windows instance: the first reply named a ledger item in the operator's language
  with the real letters, the item's words came from its ASCII id (`...-staender-...`); `named()` compared
  literally, 1 of 3 words hit, 2 were required, and the reply was blocked — only a date or an age could save
  such a reply. `fold()` lower-cases, writes the four letters a slug spells as a digraph (ae, oe, ue, ss) and
  drops every other accent; `named()` and the strict mention check of a later turn fold both sides, so either
  spelling names the item, in both directions. Fixture: `scripts/test-open-items-gate.sh` (four new cases;
  three of them fail against the state before).
