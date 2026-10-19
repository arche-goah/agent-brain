/**
 * Own echo: which replayed Stop hook feedback came from THIS check.
 *
 * WHY (operator, 2026-10-10: "no codes"): the stop dispatcher used to end every line it
 * showed with the check's marker in brackets (`[CLASS-GATE]`), because each gate finds
 * its own earlier block in the transcript by that token and counts its cooldown from it.
 * The operator reads those lines; the token is machine vocabulary. A check run by the
 * dispatcher now gets its own label in the payload (`stop_check: {label, marker}`) and
 * recognises its echo by the label the dispatcher prints at the start of its line —
 * single finding `LABEL — …`, several findings `· LABEL …`. The old token still counts,
 * so echoes written before the switch keep their cooldown.
 *
 * A gate that recognises its echo this way says so in its block (`echo: "label"`); only
 * then does the dispatcher leave the bracket out. A gate that does not say it keeps the
 * bracket — an instance gate or a gate not converted yet loses nothing.
 */
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function labelOf(input) {
  const c = input && input.stop_check;
  return c && typeof c.label === 'string' ? c.label.trim() : '';
}

/** A tester with the shape of the old OWN_ECHO regex: legacy token OR own label line. */
function ownEcho(input, legacy) {
  const label = labelOf(input);
  const line = label ? new RegExp(`(?:^|\\n)(?:· )?${esc(label)}(?: —|\\s)`, 'u') : null;
  return { test: (t) => legacy.test(t) || (line !== null && line.test(t)) };
}

/** Mark a block as label-echo aware — only when a dispatcher handed a label over. */
function declare(out, input) {
  return labelOf(input) ? { ...out, echo: 'label' } : out;
}

module.exports = { ownEcho, declare };
