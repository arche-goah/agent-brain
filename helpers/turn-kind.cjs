/**
 * Turn kind: did the operator open this turn, or a harness notification?
 *
 * WHY (2026-10-07): a finished background task, a watcher event or a CI verdict reaches
 * the transcript as a plain user string, framed in `<system-reminder>` /
 * `<task-notification>` and nothing else. Every Stop check that counts turns treated it
 * as an operator turn — 11 gates on the proving brain counted such a record as a turn
 * boundary, so their cooldowns ran out on turns no operator had written, and 39 of 164
 * real firings in a month landed on such turns. One definition, used by the dispatcher
 * (which hands `turn_kind` to every check) and by every gate's boundary count.
 *
 * A record that carries a frame AND words of the operator is an operator record: only
 * a record that is nothing but frames is a notification.
 *
 * A LOCAL command is not a prompt either (measured 2026-10-11, Windows instance): `/mcp` or
 * `/model` typed in Claude Code runs without the model and leaves three user records —
 * `<local-command-caveat>`, `<command-name>…<command-args>`, `<local-command-stdout>` — each
 * nothing but its frames. watch-gate counted the `/mcp` echo as the turn's start, so the
 * reconnect waiter armed just before it fell out of the turn and the gate reported "no
 * watcher". A user-typed skill (`/name`) carries the same command frames, but its skill text
 * follows as a record of its own — that one is plain text and stays the boundary.
 */
const FRAMES = /<system-reminder>[\s\S]*?<\/system-reminder>|<task-notification>[\s\S]*?<\/task-notification>/g;
const LOCAL = /<local-command-caveat>[\s\S]*?<\/local-command-caveat>|<local-command-std(?:out|err)>[\s\S]*?<\/local-command-std(?:out|err)>|<command-(?:name|message|args)>[\s\S]*?<\/command-(?:name|message|args)>/g;
const LOCAL_MARK = /<local-command-(?:caveat|stdout|stderr)>|<command-name>/;

function isNotification(text) {
  if (typeof text !== 'string') return false;
  if (/<task-notification>/.test(text) && !text.replace(FRAMES, '').trim()) return true;
  return LOCAL_MARK.test(text) && !text.replace(FRAMES, '').replace(LOCAL, '').trim();
}

/**
 * A skill loaded through the Skill tool arrives as a user record with isMeta AND
 * sourceToolUseID (measured, Claude Code 2.1.303, 61 of 61 such records in 40 transcripts):
 * the skill author's words, not the operator's - no prompt, no new turn. isMeta alone is NOT
 * enough: a message the operator sends mid-turn carries it too, without sourceToolUseID.
 * Takes the whole transcript record (the flags sit beside `message`, not in it).
 */
function isSkillExpansion(d) {
  return Boolean(d && d.isMeta === true && d.sourceToolUseID);
}

/**
 * A message from another agent: a subagent's hand-back or a peer session's message arrives as a
 * user record with `origin.kind === "peer"` (measured 2026-10-22, macOS instance: a subagent report
 * containing "once 1 and 2 are in" became the operator's last message for the conditional-order
 * gate, and every push of the turn was refused; the operator's own words carry `origin.kind
 * "human"`). Model output, not the operator - no prompt, no new turn.
 */
function isPeerMessage(d) {
  return Boolean(d && d.origin && d.origin.kind === 'peer');
}

/** A conversation record: Claude Code also writes `api-request-blob` lines (a snapshot of the request,
 * carrying the instruction dump as a user message and thinking as assistant text). Measured 2026-10-21
 * on a macOS instance: the conditional-order gate took a CLAUDE.md heading inside such a blob for the
 * operator's last message and refused every externally effective call of the turn. Only `user` and
 * `assistant` records are the conversation; a record without a type (older transcripts) counts too. */
function isTranscriptRecord(d) {
  // The summary a compaction writes is a user record with isCompactSummary (measured 2026-10-26,
  // macOS instance): the harness's retelling of the session, not the operator's words. The
  // conditional-order gate took a sentence of it ("only allowed after the operator grants it") for
  // the operator's last message and held every push of the turn.
  if (d && d.isCompactSummary === true) return false;
  const t = d && d.type;
  return t === undefined || t === null || t === 'user' || t === 'assistant';
}

/**
 * A message the operator types while the agent works never becomes a user record: it lands as
 * `{"type":"attachment","attachment":{"type":"queued_command","prompt":…,"origin":{"kind":"human"}}}`
 * (measured 2026-10-26, macOS instance, three such records in one turn). A gate that looks for the
 * operator's LAST words misses all of them. Returns the operator's text, or null for every other
 * record (peer messages and task notifications ride the same attachment type with another origin).
 */
function queuedHumanPrompt(d) {
  const a = d && d.type === 'attachment' && d.attachment;
  if (!a || a.type !== 'queued_command' || !a.origin || a.origin.kind !== 'human') return null;
  return typeof a.prompt === 'string' && a.prompt.trim() ? a.prompt : null;
}

module.exports = { isNotification, isSkillExpansion, isPeerMessage, isTranscriptRecord, queuedHumanPrompt, FRAMES, LOCAL };
