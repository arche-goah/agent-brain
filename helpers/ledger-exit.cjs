'use strict';
/**
 * Which `exit:` line of a ledger entry says who moves now (skill backlog-catch-up).
 *
 * The NEWEST exit by its date; on the same date (or with no date) the later one in the text.
 * Never simply the last one in the text: writers put a new exit at the top of an entry as often
 * as at the bottom. Measured 2026-11-06 on the macOS instance: an entry with nine exits was read
 * by its last line (operator-decision 2026-11-04) in 34 session starts while its newest exit
 * (other-side 2026-11-05) put the move on another side. The Python reader is
 * `newest_exit()` in scripts/open-items.py — same rule, keep both in step.
 */
const EXIT_LINE = /^[\s>*-]*`?exit:\s*`?([\w-]+)`?(?:\s+(\d{4}-\d{2}-\d{2}))?/gm;

function newestExitKind(body) {
  let best = null;
  let idx = 0;
  for (const m of String(body || '').matchAll(EXIT_LINE)) {
    const key = [m[2] || '', idx++];
    if (!best || key[0] > best.key[0] || (key[0] === best.key[0] && key[1] > best.key[1])) best = { kind: m[1], key };
  }
  return best ? best.kind : null;
}

module.exports = { newestExitKind };
