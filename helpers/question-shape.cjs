/**
 * The SHAPE of a question to the operator - one source for every gate that asks "is this a
 * question to the operator?" (stoppen-gate.cjs at the turn end, question-gate.cjs for the
 * question left open after the operator's reply). Two lists drifted apart (Windows content
 * review 2026-11-26: "Could you live with the old head?" was held at the turn end but never
 * recorded as an open question); both now read these patterns.
 *
 * A sentence that opens with an auxiliary and "you" and ends in "?" ("Would you like the core
 * PR now?"), or the same behind a question word ("Which one do you want?"). Measured
 * 2026-11-26 on the macOS instance: a closing decision question in the operator's language
 * matched none of 16 phrase patterns of its pack; replay over 14 days, 2901 closing texts:
 * 29 newly held, about 27 real questions to the operator.
 *
 * Sentence start: text start, after `.` `!` `?` `:` `)` or a dash and whitespace, after a line
 * break, or after bold markers. No `m` flag is needed: the line break is in the group, so the
 * patterns work in a regex compiled with any flags. English only (engine built-ins); another
 * language is instance data in each gate's own file.
 */
const START = '(?:^|[.!?:)\\u2013\\u2014-]\\s+|\\n\\s*|\\*\\*\\s*)';
const AUX = '(?:do|does|did|would|will|should|shall|can|could|may|are|is|were|have)';
const WH = '(?:what|which|when|where|who|how|why)';

const YOU_QUESTION = [
  `${START}${AUX} you\\b[^?\\n]{0,160}\\?`,
  `${START}${WH}\\b[^?.\\n]{0,60}\\b${AUX} you\\b[^?\\n]{0,160}\\?`,
];

module.exports = { YOU_QUESTION };
