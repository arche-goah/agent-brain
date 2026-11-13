#!/usr/bin/env node
/**
 * The ONE reader of an OS hand review in a PR thread: does this text say OK for macOS / Windows /
 * Linux, and is it a hand review at all? Library of merge-request-gate.cjs (line level, `saysOk`)
 * and CLI of release-preflight.sh check 8 (text level, `handReview`).
 *
 * WHY one reader (measured 2026-11-06 on the macOS instance, release v2.1.3): two readers judged the
 * same threads and disagreed. Preflight check 8 (this file's `saysOk`, then in merge-request-gate)
 * was too strict: it rejected real macOS OKs on agent-brain #414 ("red-free" hit the fail word
 * `red`), #332 ("read the open entries first" in the evidence after the verdict) and #382 (a first
 * line that says "macOS OK at head" was skipped as a CI note because it also said "CI at this
 * head"). An instance-side report was too loose: it counted #342 and #386 as macOS-checked from a PR
 * body that carried an instance key, the word "macOS" and a "pass" somewhere in the text.
 *
 * LINE LEVEL — `saysOk(line, os)`:
 * - a STATEMENT: the OS name followed directly by the verdict ("macOS OK at head", "Windows: OK",
 *   "Windows check OK", "**macOS OK, by hand**"). Its scope is the clause it opens, up to the first
 *   " — ", " – ", "(", ";" or the next OS name: what follows a dash or a bracket is the evidence
 *   (what was run, what was read), not the verdict. A fail word in that clause still cancels it
 *   ("macOS OK at `abc`, but lint red against main").
 * - otherwise the OS name with a pass word AFTER it, in the part that belongs to that OS (up to the
 *   next OS name), and no fail word in that part ("**Test (Windows, Git Bash):** all cases pass").
 *   A pass word only BEFORE the OS name is no OK for it ("16 checks OK including macOS and Windows").
 *   Nor is an OS named inside ANOTHER system's statement ("Windows OK at head … the same totals as macOS",
 *   2026-11-13, grandma3-suite #253): this branch counts only where no other system's statement opened earlier.
 * - an OK named as a thing or promised is no verdict and blanked first: "No Windows OK yet", "the / your
 *   macOS OK", "Windows OK once / when / if …", "… OK stays with you" (2026-11-12, #473).
 * - fail words are whole words; a hyphen joins a compound ("red-free", "fail-fast" are no verdict).
 *   Code spans, bare file names and the fixture phrase "red against the old code" are no verdict
 *   (2026-10-28 #164, 2026-11-02 mikrotik-suite #44); "red against main" still is. A fail word of
 *   ANOTHER system's clause never cancels this one's OK (2026-10-28, #156-#159).
 *
 * TEXT LEVEL — `handReview(text, os, {head})` returns the instance key or null:
 * - the text carries the instance-key COMMENT marker `<!-- instance-key: <hex> -->` (posted through
 *   the instance-key gate); a bare "instance-key:" in prose is no marker;
 * - a text whose first line reads as a CI note (`CI_NOTE`) is skipped, unless that first line holds
 *   an OS statement — a CI job is no hand review (operator 2026-11-02, 2026-11-04), a reviewer who
 *   also names the CI is still a reviewer;
 * - judged per sentence; a bracket that says "against …" is a negative control, not a verdict;
 * - `head`: the text must name that short sha (a review on a merge train counts only at its head).
 *
 * CLI: `node helpers/os-review.cjs <macOS|Windows|Linux> [--head <sha>]` reads ONE text on stdin;
 * prints the key and exits 0 when it is a hand review for that OS, exits 1 otherwise.
 * Stdlib only.
 */
const NAME_RX = { macOS: /\bmac\s?os\b/i, Windows: /\bwindows\b/i, Linux: /\blinux\b/i };
const OK_RX = /\b(ok|pass(?:es|ed)?|green|rc 0|all \d+ step\(s\) passed)\b/i;
// whole words: a hyphen or a word character on either side makes a compound, not a verdict
const NOT_RX = /(?<![\w-])(unchecked|not checked|wanted|open|fail(?:s|ed)?|red|missing|pending)(?![\w-])/i;
const KEY_RX = /<!--\s*instance-key:\s*([0-9a-f]+)\s*-->/i;
const CI_NOTE = /from ci|windows-latest|macos-latest|portability \(|ci job|windows job|ci at|checks? none failing|\bci (?:is |was )?green\b/i;
// a dash (not a hyphen) or a bracket starts the evidence; "OK - the fixture is red" stays one clause
const CLAUSE_END = /\s[—–]\s|\(|;/;
// A statement that names an OK as a thing ("the / no / your Windows OK": asked for, missing, owed) or promises one
// ("Windows OK once / when / if …") is no verdict (see saysOk).
const DETERMINER_BEFORE = /\b(?:the|a|an|no|your|my|our|their|its|this|that|his|her)\s+[*_]*$/i;
const CONDITION_AFTER = /^[\s*_]*(?:once|when|if|after|as soon as|until|stays|is (?:yours|wanted|owed)|from you)\b/i;

// Only the known systems: a pattern is never built from the caller's text (code scanning js/regex-injection,
// 2026-11-06 on this PR — the CLI's OS argument reached `new RegExp`). An unknown OS matches nothing.
const NEVER = /(?!)/;
function osRx(os) { return Object.prototype.hasOwnProperty.call(NAME_RX, os) ? NAME_RX[os] : NEVER; }

/** The OS name at the start of `rest`, then (optionally a version, "check"/"review") the verdict. */
function statementAt(rest, os) { return statementLength(rest, os) >= 0; }

/** Length of the statement at the start of `rest` (OS name up to the verdict word), or -1. */
function statementLength(rest, os) {
  const name = osRx(os).source.replace(/^\\b/, '');
  const m = new RegExp(`^(?:${name})(?:\\s+\\d+)?[\\s*:_,-]*(?:(?:hand\\s+)?(?:check|review|test)s?[\\s*:_-]*)?(?:ok|pass(?:es|ed)?|green)\\b`, 'i').exec(rest);
  return m ? m[0].length : -1;
}

/** Does any OS name in `line` open a statement ("macOS OK at head …")? */
function hasStatement(line) {
  const s = String(line).replace(/`[^`]*`/g, '``');
  return Object.keys(NAME_RX).some((o) => {
    const rx = new RegExp(osRx(o).source, 'gi');
    let m;
    while ((m = rx.exec(s))) if (statementAt(s.slice(m.index), o)) return true;
    return false;
  });
}

/**
 * Blank every statement that is no verdict: an OK named as a thing ("No Windows OK yet", "The Windows OK stays with
 * you") or promised ("Windows OK once …"). Blanked BEFORE both branches of saysOk, because the pass-word branch would
 * otherwise find its "OK" from an earlier mention of the OS ("Windows finding fixed … The Windows OK stays with you").
 * Measured 2026-11-12 on agent-brain #473: both sentences read as a Windows hand review at the head.
 */
function blankNonVerdicts(s) {
  let out = s;
  for (const o of Object.keys(NAME_RX)) {
    const rx = new RegExp(osRx(o).source, 'gi');
    let m;
    while ((m = rx.exec(out))) {
      const len = statementLength(out.slice(m.index), o);
      if (len < 0) continue;
      const after = CONDITION_AFTER.exec(out.slice(m.index + len));
      if (!after && !DETERMINER_BEFORE.test(out.slice(0, m.index))) continue;
      const span = len + (after ? after[0].length : 0);
      out = out.slice(0, m.index) + '``' + out.slice(m.index + span);
      rx.lastIndex = m.index + 2;
    }
  }
  return out;
}

/** Does `text` say NO for `os` in so many words — "no / not <OS> OK", "<OS> FAIL", "<OS> check: not OK"? */
function saysNo(text, os) {
  const name = osRx(os).source.replace(/^\\b/, '');
  const clean = String(text).replace(/`[^`]*`/g, '``');
  return new RegExp(`\\b(?:no|not)\\s+[*_]*(?:${name})[*_]*\\s+(?:hand\\s+)?(?:ok|pass)\\b`, 'i').test(clean)
    || new RegExp(`\\b(?:${name})(?:\\s+(?:hand\\s+)?(?:check|review|test)s?)?[\\s*:_-]*(?:fail(?:ed|s)?|not ok)\\b`, 'i').test(clean);
}

/** Does this line say OK for `os`? */
function saysOk(line, os) {
  const clean = blankNonVerdicts(String(line).replace(/`[^`]*`/g, '``').replace(/[\w./-]+\.[a-z]{1,4}\b/gi, '``')
    .replace(/\bred (?:against|with) the old (?:code|state)\b/gi, '``'));
  const others = Object.entries(NAME_RX).filter(([k]) => k !== os).map(([, r]) => r.source).join('|');
  const rx = new RegExp(osRx(os).source, 'gi');
  let m;
  while ((m = rx.exec(clean))) {
    const rest = clean.slice(m.index);
    const nextOs = others ? rest.slice(1).search(new RegExp(others, 'i')) : -1;
    const part = nextOs < 0 ? rest : rest.slice(0, nextOs + 1);
    if (statementAt(rest, os)) {
      const end = part.search(CLAUSE_END);
      if (!NOT_RX.test(end < 0 ? part : part.slice(0, end))) return true;
    } else if (OK_RX.test(part) && !NOT_RX.test(part) && !otherStatementBefore(clean, os, m.index)) return true;
  }
  return false;
}

/** Does another system's statement ("Windows OK at head …") open before `idx` in `s`? Then a mention of `os` after it
 * is evidence inside that verdict ("… the same totals as macOS"), not a verdict for `os`. Measured 2026-11-13 on
 * grandma3-suite #253: a Windows OK line naming macOS in its evidence was read as the macOS OK, and the merge passed. */
function otherStatementBefore(s, os, idx) {
  return Object.keys(NAME_RX).filter((o) => o !== os).some((o) => {
    const rx = new RegExp(osRx(o).source, 'gi');
    let m;
    while ((m = rx.exec(s)) && m.index < idx) if (statementAt(s.slice(m.index), o)) return true;
    return false;
  });
}

/** Sentences of a text; a bracket naming "against …" (a negative control) is blanked first. */
function sentences(text) {
  return String(text).split(/\r?\n/)
    .flatMap((l) => l.replace(/\([^()]*\bagainst\b[^()]*\)/gi, '``').split(/[;.]\s+/));
}

/** Is `text` a hand review for `os`? Returns the instance key, or null. */
function handReview(text, os, opts = {}) {
  const t = String(text || '');
  const key = KEY_RX.exec(t);
  if (!key) return null;
  if (opts.head && !t.includes(String(opts.head).slice(0, 7))) return null;
  const first = t.trim().split(/\r?\n/)[0] || '';
  if (CI_NOTE.test(first) && !hasStatement(first)) return null;
  // An explicit no for this OS ("No Windows OK yet: 1 finding", "Windows FAIL") is the verdict of the whole text: the
  // pass words of its evidence ("Windows, measured: … 17/17 passed") must not turn a finding into an OK (measured
  // 2026-11-12 on 13 finding drafts for core PRs: every one read as a Windows hand review before this line).
  if (saysNo(t, os)) return null;
  return sentences(t).some((s) => saysOk(s, os)) ? key[1].toLowerCase() : null;
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const os = args[0];
  if (!Object.prototype.hasOwnProperty.call(NAME_RX, os || '')) {
    process.stderr.write(`os-review: unknown OS '${os || ''}' - one of ${Object.keys(NAME_RX).join(', ')}\n`);
    process.exit(2);
  }
  const h = args.indexOf('--head');
  const head = h >= 0 ? args[h + 1] : '';
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    const key = os ? handReview(data, os, { head }) : null;
    if (key) process.stdout.write(key + '\n');
    process.exit(key ? 0 : 1);
  });
  process.stdin.resume();
}

module.exports = { saysOk, saysNo, handReview, statementAt, NAME_RX, OK_RX, NOT_RX, KEY_RX, CI_NOTE };
