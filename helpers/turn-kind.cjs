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

module.exports = { isNotification, FRAMES, LOCAL };
