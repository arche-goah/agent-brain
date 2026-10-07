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
 */
const FRAMES = /<system-reminder>[\s\S]*?<\/system-reminder>|<task-notification>[\s\S]*?<\/task-notification>/g;

function isNotification(text) {
  return typeof text === 'string' && /<task-notification>/.test(text) && !text.replace(FRAMES, '').trim();
}

module.exports = { isNotification, FRAMES };
