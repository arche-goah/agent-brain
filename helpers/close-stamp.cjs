/**
 * The close stamp — what lets the session-close turn end while a Stop gate would block it.
 *
 * The contradiction (coherence scan of a Windows instance, 2026-10-15, P1-2): skill
 * `session-close` step 4 says a closing session arms no watcher and waits on no CI it will not
 * be alive to read — it names every such item as an open end in the session-log entry instead.
 * But watch-gate.cjs blocks a turn end after a push, a PR or a ticket without a watcher, and
 * question-gate.cjs blocks it while a question the operator has seen is open. So the close turn
 * could not end cleanly: either a watcher that dies with the session (against the skill) or a
 * marker that leaves nothing behind.
 *
 * The exception is bound to a checkable carrier, not to a phrase: `session-closing.sh
 * --pre-commit` (skill step 2) leaves `.claude-state/session-close.stamp` — line 1 the session
 * id it was given, line 2 the session-log line it wrote. A gate accepts the stamp for an item
 * ONLY when the entry below that line lists the item as an open end (`open end: …` — the repo
 * and number of a PR, the repo of a push, the fact file of a shared-memory request, the id or
 * sentence of a question). A stamp without the listing passes nothing: the omission must leave
 * an artifact, which is the point of both gates.
 *
 * The stamp counts only when (1) the running turn itself called `session-closing.sh
 * --pre-commit` (the transcript is this session's, so the close ran here), (2) the stamp file
 * was written no earlier than the turn began (a stamp left by an earlier close does not cover a
 * later turn's push), and (3) the stamp names this session, or no session (an older harness
 * leaves the id empty; (1) then carries the attribution).
 *
 * Fixtures: scripts/test-watch-gate.sh and scripts/test-question-gate.sh.
 */
const fs = require('fs');
const path = require('path');

const PRE_COMMIT = /\bsession-closing\.sh\b[^\n]*--pre-commit\b/;
const OPEN_END = /\bopen end\b/i;
const MTIME_SLACK_MS = 2000; // coarse file-system clocks (FAT: 2 s)

/**
 * The open-end lines of this session's close entry, or null when no valid stamp covers the
 * running turn. `calls` are the turn's tool calls ({cmd}), `since` the ISO time the turn began.
 */
function closeOpenEnds(root, { sessionId, since, calls }) {
  if (!(calls || []).some((c) => PRE_COMMIT.test(String(c.cmd || '')))) return null;
  const stamp = path.join(root, '.claude-state', 'session-close.stamp');
  let st; let lines;
  try { st = fs.statSync(stamp); lines = fs.readFileSync(stamp, 'utf8').split(/\r?\n/); } catch (e) { return null; }
  const t = Date.parse(since || '');
  if (!Number.isNaN(t) && st.mtimeMs < t - MTIME_SLACK_MS) return null;
  const sid = (lines[0] || '').trim();
  if (sid && sessionId && sid !== sessionId) return null;
  const head = (lines[1] || '').trim();
  if (!head) return null; // a stamp without its log line cannot point at an entry
  let log;
  try { log = fs.readFileSync(path.join(root, 'docs', 'maintenance', 'session-log.md'), 'utf8').split(/\r?\n/); } catch (e) { return null; }
  let i = -1;
  for (let k = log.length - 1; k >= 0; k--) if (log[k].trim() === head) { i = k; break; }
  if (i < 0) return null;
  const out = [];
  for (const l of log.slice(i + 1)) {
    if (/^- /.test(l)) break; // the next entry
    if (OPEN_END.test(l)) out.push(l.toLowerCase());
  }
  return out;
}

/** One open-end line names every needle (strings, case-insensitive; a PR number as `#n`). */
function listed(ends, needles) {
  const want = needles.filter((n) => n !== '' && n != null).map((n) => (typeof n === 'number'
    ? new RegExp(`#${n}(?!\\d)`) : String(n).toLowerCase()));
  if (!want.length) return false;
  return ends.some((l) => want.every((w) => (w instanceof RegExp ? w.test(l) : l.includes(w))));
}

module.exports = { closeOpenEnds, listed, PRE_COMMIT };
