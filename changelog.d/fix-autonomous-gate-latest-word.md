- **autonomous-gate: no dialog in an autonomous run - an operator message in the turn does not mean the operator is
  there** (test: T1) (level: reader; higher: design — a third mode "reachable on the phone" was named by the operator
  as a possible later mode; not built; debt: an approved held edit waits until the mode ends). The operator,
  2026-11-03 (translated): "I am not automatically always there. Today I get this on my phone [...] Asking
  interactively is not auto mode - then we could abolish the modes right away" and "only when I write 'questions to me
  now' etc. shall the mode change. In auto mode no interactive prompts". This removes the exception of 2026-11-02
  (`operatorInTurn`: a held call went to the harness dialog when the operator had spoken in the turn). Measured the
  same day on the macOS instance: two dialogs in one autonomous run through that exception - an edit of
  `.claude/settings.json` 13 minutes after the operator's last answer ("continue autonomously"), and a `feedback.md`
  edit after a mid-turn remark sent from a phone. The mode still ends on the operator's ask for what is open or an
  off-word (unchanged). Fixture `scripts/test-autonomous-gate.sh`: two cases flipped to "held", +2 (a switch-on answer
  holds; an "interactive" answer ends the mode).
