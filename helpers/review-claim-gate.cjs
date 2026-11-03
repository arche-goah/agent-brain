#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash): a review comment that says it READ THE DIFF is posted only after a diff
 * was read — since the session's previous post.
 *
 * WHY (operator decision 2026-11-03, the macOS instance; asked through the question tool: "Ja, als
 * Kern-PR"): a review comment on a collaborator's PR said "read the diff of scripts/open-items.py";
 * the diff was read only AFTER the comment was posted. The claim turned out true, but it was written
 * as a reading it was not. A reviewer's "read the diff" is what the merging side relies on — a claim
 * of a measurement, and a measurement claim needs its measurement first (evidence chain, rule 0).
 *
 * WHAT COUNTS AS A CLAIM: `gh pr comment|review` and `gh issue comment` whose text (inline or the
 * handed file) says "read the diff", "read its diff", "reviewed the diff" or "reviewed the code".
 * WHAT COUNTS AS READING: a Bash command running `gh pr diff`, `git diff` or `git show` that names THIS
 * PR (`gh pr diff <n>`, `pr-<n>`, `pull/<n>`) or the head the comment names (`head <sha>`), anywhere
 * before the post in the transcript - so a review read in one wakeup and posted in the next stays
 * free. A diff of another PR does not count (the incident: the diff read before was another PR's, on
 * the same file). A post without a PR number falls back to: any diff or Read since the previous post.
 * ESCAPE: `# DIFF-READ: <where it was read>` in the command (a diff read outside this transcript,
 * e.g. in a subagent or on the web).
 *
 * Exit 0 = allow, 2 = block. Fails open on unreadable input or transcript.
 */
const fs = require('fs');
const path = require('path');
const { invocations, publishedText } = require('./published-text.cjs');
const { isTranscriptRecord } = require('./turn-kind.cjs');

const CLAIM = /\b(?:read|reviewed)\s+(?:the|its|this PR'?s?)\s+diffs?\b|\breviewed\s+the\s+code\b/i;
const POST_RX = /(^|[;&|(]\s*|\s)gh\s+(pr\s+(create|comment|review)|issue\s+(create|comment))\b/;
const READ_RX = /(^|[;&|(]\s*|\s)(gh\s+pr\s+diff\b|git\b(?:\s+-C\s+\S+)?\s+(?:diff|show)\b)/;
const ESCAPE = /#\s*DIFF-READ:\s*\S/;

function isPost(cmd, ps) {
  const hit = invocations(cmd, ps, 'gh', ['pr'], ['comment', 'review', 'create']);
  const issue = invocations(cmd, ps, 'gh', ['issue'], ['comment', 'create']);
  if (hit === null || issue === null) return POST_RX.test(cmd);
  return hit.length > 0 || issue.length > 0;
}
const isReview = (cmd, ps) => {
  const hit = invocations(cmd, ps, 'gh', ['pr'], ['comment', 'review']);
  const issue = invocations(cmd, ps, 'gh', ['issue'], ['comment']);
  if (hit === null || issue === null) return /\bgh\s+(pr\s+(comment|review)|issue\s+comment)\b/.test(cmd);
  return hit.length > 0 || issue.length > 0;
};

function postedText(cmd, ps, cwd) {
  const pub = publishedText(cmd, ps);
  if (!pub) return cmd;
  let text = pub.texts.join('\n');
  for (const f of pub.files) {
    const p = String(f).replace(/^~(?=$|[\\/])/, require('os').homedir());
    try { text += '\n' + fs.readFileSync(path.resolve(cwd, require('./public-text-guard.cjs').nativePath(p)), 'utf8'); }
    catch (e) { /* unreadable: the post fails on it too */ }
  }
  return text;
}

function readTail(p) {
  const st = fs.statSync(p);
  const n = Math.min(st.size, 8 * 1024 * 1024);
  const fd = fs.openSync(p, 'r');
  const buf = Buffer.alloc(n);
  fs.readSync(fd, buf, 0, n, st.size - n);
  fs.closeSync(fd);
  const lines = buf.toString('utf8').split('\n');
  if (n < st.size) lines.shift();
  return lines;
}

/** Was THIS PR's diff read before the post? A diff command counts when it names the PR (`gh pr diff <n>`,
 * `pr-<n>`, `pull/<n>`) or the head the comment names (`head <sha>`). Measured in the replay 2026-11-03:
 * "any diff since the previous post" let the incident pass - the diff read before it was another PR's,
 * on the same file. Without a PR number in the command, any diff since the previous post counts. */
// A second form, measured in the same replay: `git diff origin/main...HEAD -- <file>` in a checkout of the
// PR names neither number nor head, but the comment names the file. Such a diff counts when it ran after
// the previous post (the incident's earlier diff of the same file was read for the PR posted before).
function readForPr(lines, current, pr, sha, files) {
  if (!pr && !sha) return readSincePost(lines, current);
  const names = [];
  if (pr) names.push(new RegExp(`\\bgh\\s+pr\\s+diff\\s+${pr}\\b|\\bpr-${pr}\\b|\\bpull/${pr}\\b`));
  if (sha && sha.length >= 7) names.push(new RegExp(`\\b${sha.slice(0, 7)}`));
  let sincePost = false;
  for (const u of toolUses(lines, current)) {
    const cmd = u.name === 'Bash' ? String((u.input && u.input.command) || '') : '';
    if (!cmd) continue;
    if (isPost(cmd, false)) { sincePost = false; continue; }
    if (!READ_RX.test(cmd)) continue;
    if (names.some((rx) => rx.test(cmd))) return true;
    if ((files || []).some((f) => cmd.includes(f))) sincePost = true;
  }
  return sincePost;
}

// Paths the comment names in backticks (`scripts/x.py`), the files a review says it read.
function namedFiles(text) {
  return [...text.matchAll(/`([\w.-]+(?:\/[\w.-]+)+)`/g)].map((m) => m[1]);
}

function toolUses(lines, current) {
  const uses = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    let d;
    try { d = JSON.parse(line); } catch (e) { continue; }
    // An `api-request-blob` replays earlier tool uses after the post; read as calls, it puts an
    // old post after the diff read (measured in the replay 2026-11-03: four false holds).
    if (!isTranscriptRecord(d)) continue;
    const c = d && d.message && d.message.role === 'assistant' && d.message.content;
    if (!Array.isArray(c)) continue;
    for (const b of c) if (b && b.type === 'tool_use') uses.push(b);
  }
  for (let i = uses.length - 1; i >= 0; i--) {
    const u = uses[i];
    if (u.name === 'Bash' && String((u.input && u.input.command) || '') === current) { uses.splice(i, 1); break; }
  }
  return uses;
}

/** Was a diff read since the previous post? `current` is the command now asking (not yet run). */
function readSincePost(lines, current) {
  let read = false;
  for (const u of toolUses(lines, current)) {
    const cmd = u.name === 'Bash' ? String((u.input && u.input.command) || '') : '';
    if (cmd && isPost(cmd, false)) { read = false; continue; }
    if (u.name === 'Read' || (cmd && READ_RX.test(cmd))) read = true;
  }
  return read;
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  const ps = input.tool_name === 'PowerShell';
  if (!isReview(cmd, ps) || ESCAPE.test(cmd)) return 0;
  const text = postedText(cmd, ps, input.cwd || process.cwd());
  const m = CLAIM.exec(text);
  if (!m || !input.transcript_path) return 0;
  let read;
  const pr = (/\bgh\s+(?:pr|issue)\s+(?:comment|review)\s+(\d+)\b/.exec(cmd) || [])[1] || '';
  const sha = (/\bhead\s+`?([0-9a-f]{7,40})\b/i.exec(text) || [])[1] || '';
  try { read = readForPr(readTail(input.transcript_path), cmd, pr, sha, namedFiles(text)); } catch (e) { return 0; }
  if (read) return 0;
  console.error(
    `BLOCKED (review-claim-gate): this comment says "${m[0]}", but no diff was read since this session's previous post.\n` +
    'Read it first (gh pr diff <n>, git diff <base>...<head>, or Read the changed file), then post.\n' +
    'Read elsewhere (a subagent, the web)? Repeat with `# DIFF-READ: <where>`.\n' +
    'Why: a reviewer\'s "read the diff" is what the merging side relies on; it is a measurement claim (operator 2026-11-03).');
  return 2;
}

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let rc = 0;
    try { rc = gate(JSON.parse(data)); } catch (e) { rc = 0; }
    process.exit(rc);
  });
  process.stdin.resume();
}

module.exports = { gate, readForPr, readSincePost, namedFiles, CLAIM };
