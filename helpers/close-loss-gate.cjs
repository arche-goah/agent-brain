#!/usr/bin/env node
/**
 * Stop check: a reply that releases the operator ("you can shut down") while something can still be
 * lost does not end the turn.
 *
 * Why (operator, 2026-10-26, through the question tool): "a session must not count as cleanly closed
 * while something that can be lost is still open, something that has to be done in the session".
 * Same day, Windows instance: a close report opened with "Persisted - you can shut down" and carried,
 * in its fourth bullet, a command only the operator could run, pointing into the session's scratchpad
 * that vanishes with it (the operator: "that is fatal"). Skill session-close step 5 (#146) says it in
 * prose; this check makes it bind.
 *
 * Fires only when the turn's closing reply (its last text) contains a RELEASE phrase (English built-ins plus the instance's
 * `release_patterns`). Then it measures, and blocks on any of:
 *   - commits on the current branch that its upstream does not have (`git rev-list @{u}..HEAD`) - in
 *     the working repo, in the shared-memory repo (`$SHARED_MEMORY_REPO`, default
 *     ~/Projects/brain-shared-memory - the path helpers/session-closing.sh reads) and in every repo the
 *     instance lists under `repos` (class search after #149: the close skill only REPORTED the
 *     shared-memory repo, a release outside the skill let its unpushed entries go);
 *   - a hand step left in the reply: a "! <command>" for the operator, or a hand-step word
 *     (built-in "hand step", instance `hand_patterns`);
 *   - a path inside a session scratchpad named in the reply (it ends with the session).
 * Instance data: .claude/rules/close-loss.json {"release_patterns", "hand_patterns"} - regexes;
 * "repos" - more repo paths to measure (a leading ~ is the home directory).
 * Output: {"decision":"block","reason":"CLOSE-LOSS: ... Open: <items>"}. Fails open on unreadable input.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const os = require('os');
const { isNotification, isAgentOrigin, isTranscriptRecord } = require('./turn-kind.cjs');

const HOOK_ECHO = /^Stop hook feedback:/;
const TAIL_BYTES = 4 * 1024 * 1024;
const BUILTIN_RELEASE = ['\\byou can (now )?(shut (it )?down|close (the session|everything)|end the session|turn (it|everything) off)\\b',
  '\\bsafe to (shut down|close the session|end the session)\\b'];
// "no hand step" names none (2026-10-28: a negated hand word blocked a clean close)
const BUILTIN_HAND = ['(?<!\\bno )(?<!\\bwithout )\\bhand step\\b(?!-)', '(^|\\n)\\s*[-*]?\\s*`?!\\s?[a-z]'];
const SCRATCH = /\/(?:private\/)?tmp\/claude-[^\s`'")]*\/scratchpad\b[^\s`'")]*/;

function rx(builtins, extra) {
  const list = [...builtins];
  for (const s of extra || []) { try { new RegExp(s); list.push(s); } catch (e) { /* skip a broken regex */ } }
  return new RegExp(list.join('|'), 'iu');
}

function readTail(file) {
  const size = fs.statSync(file).size;
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    if (start > 0) lines.shift();
    return lines;
  } finally { fs.closeSync(fd); }
}

/** The closing reply of the running turn: the text of the agent's LAST message that has text, after the operator's
 * last message. Not every text of the turn: a corrected close report replaces the one before it, as the operator
 * reads it — measured 2026-10-28 (macOS instance): the first report released and named a reload, the corrected
 * report dropped it, and the check read the first one again on every stop until the operator wrote (a loop). */
function replyText(transcriptPath) {
  let last = '';
  for (const line of readTail(transcriptPath)) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    const msg = d.message;
    if (!msg || !isTranscriptRecord(d)) continue;
    if (msg.role === 'user' && typeof msg.content === 'string') {
      if (!HOOK_ECHO.test(msg.content) && !isNotification(msg.content) && !isAgentOrigin(d)) last = '';
      continue;
    }
    if (msg.role !== 'assistant' || !Array.isArray(msg.content)) continue;
    const text = msg.content.filter((b) => b && b.type === 'text' && b.text).map((b) => b.text).join('\n');
    if (text) last = text;
  }
  return last;
}

function unpushed(cwd) {
  try {
    const n = execFileSync('git', ['-C', cwd, 'rev-list', '--count', '@{u}..HEAD'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return Number(n) || 0;
  } catch (e) { return 0; } // no repo or no upstream: nothing measurable to lose here
}

function judge(input) {
  const cwd = input.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
  if (!input.transcript_path) return null;
  const text = replyText(input.transcript_path);
  let inst = {};
  try { inst = JSON.parse(fs.readFileSync(path.join(cwd, '.claude', 'rules', 'close-loss.json'), 'utf8')); } catch (e) { /* built-ins */ }
  if (!rx(BUILTIN_RELEASE, inst.release_patterns).test(text)) return null;
  const open = [];
  const home = os.homedir();
  const repos = [cwd, process.env.SHARED_MEMORY_REPO || path.join(home, 'Projects', 'brain-shared-memory'),
    ...(inst.repos || []).map((r) => String(r).replace(/^~(?=$|[\\/])/, home))];
  const seen = new Set();
  for (const r of repos) {
    const key = path.resolve(r);
    if (seen.has(key)) continue;
    seen.add(key);
    const n = unpushed(r);
    if (n) open.push(`${n} commit(s) not pushed in ${path.basename(key)}`);
  }
  if (rx(BUILTIN_HAND, inst.hand_patterns).test(text)) open.push('a hand step for the operator in the reply');
  const sp = SCRATCH.exec(text);
  if (sp) open.push(`a path inside the session scratchpad (${sp[0].slice(0, 80)})`);
  if (!open.length) return null;
  return 'CLOSE-LOSS: the reply releases the operator, but something can still be lost - finish it first ' +
    '(push; put the step through the question tool and run it on yes; copy the file to a lasting place), ' +
    `or withhold the release and say what is awaited. Open: ${open.join('; ')}`;
}

module.exports = { judge, replyText };

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let input;
    try { input = JSON.parse(raw); } catch (e) { process.exit(0); }
    let reason = null;
    try { reason = judge(input); } catch (e) { reason = null; }
    if (reason) console.log(JSON.stringify({ decision: 'block', reason }));
    process.exit(0);
  });
}
