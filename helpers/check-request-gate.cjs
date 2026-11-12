#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash, PowerShell): a PR comment or review that asks ANOTHER instance to act
 * ("please run the Windows hand check at <sha>", "please re-run your probe", "needed: content
 * reviews for ...") is posted only when the request stands in the shared memory - an open
 * `request-*.md` there names this PR, or the text carries `request: <shared-memory id>`.
 *
 * WHY (operator order 2026-11-12, translated: "of course she does not read a request in a PR
 * automatically ... that has to be prevented mechanically. Check requests cleanly into the shared
 * memory."): measured the same day on the macOS instance, three comments on a train PR asked the
 * Windows instance for its hand check at a new head. That instance does not read PR threads by
 * itself; its inbox is the shared-memory repo, where `scripts/shared-memory-post.py request` writes
 * a request with `status: open`. A PR comment is a pointer to the request, never the request.
 *
 * WHAT COUNTS AS ASKING: a phrase of `check-request-words.json` (data beside this gate) in the
 * posted text (inline or the handed file), after quoted text is removed - backticks, double quotes,
 * `>` lines - so a comment that quotes an earlier request is no request. A review finding for the
 * PR's author ("please add `Risk: high`", "please declare high") is no check request and stays free.
 * WHAT LETS IT THROUGH: an open request in the LOCAL shared-memory clone (`$SHARED_MEMORY_REPO`,
 * default ~/Projects/brain-shared-memory) naming `#<n>` or `pull/<n>` of this PR - and, when the
 * comment names a head ("at `<sha>`", "head <sha>"), that head too, so an old request for an earlier
 * head does not carry a new ask; or
 * `request: <id>` in the text naming an existing file (`<area>/<id>` or a bare file stem).
 * Named limits: the clone is read as it is, never fetched - a request another device wrote and
 * this clone has not pulled is not seen (the gate then holds, which is the safe side). The PR
 * number alone is matched, so an open request for the same number in another repo counts.
 *
 * Exit 0 = allow, 2 = block. Fails open, with one stderr line, when the shared memory cannot be read.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { invocations } = require('./published-text.cjs');
const { postedText } = require('./review-claim-gate.cjs');

const POST_RX = /(^|[;&|(]\s*|\s)gh\s+pr\s+(comment|review)\b/;

let WORDS = null;
function words() {
  if (WORDS) return WORDS;
  const d = JSON.parse(fs.readFileSync(path.join(__dirname, 'check-request-words.json'), 'utf8'));
  WORDS = (d.request_patterns || []).map((p) => new RegExp(p, 'i'));
  return WORDS;
}

/** Text with quoted parts removed: fenced and inline code, double quotes, `>` quote lines. */
function unquoted(text) {
  return String(text)
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`\n]*`/g, ' ')
    .replace(/"[^"\n]{0,300}"/g, ' ')
    .replace(/“[^”\n]{0,300}”/g, ' ')
    .replace(/^\s*>.*$/gm, ' ');
}

/** The phrase that asks another instance to act, or ''. */
function asks(text) {
  const t = unquoted(text);
  for (const rx of words()) {
    const m = rx.exec(t);
    if (m) return m[0];
  }
  return '';
}

function postSegment(cmd, ps) {
  const hit = invocations(cmd, ps, 'gh', ['pr'], ['comment', 'review']);
  if (hit === null) return POST_RX.test(cmd) ? [] : null;
  return hit.length ? hit[0] : null;
}

function prNumber(seg, cmd) {
  const a = seg && seg[3] && !seg[3].startsWith('-') ? seg[3] : '';
  const m = /^#?(\d+)$/.exec(a) || /\/pull\/(\d+)\b/.exec(a) || /\bgh\s+pr\s+(?:comment|review)\s+#?(\d+)\b/.exec(cmd);
  return m ? m[1] : '';
}

// The heads a request names ("at `f24270f`", "head 3f87f46"), first 7 digits. Measured 2026-11-12: the
// incident asked three times, each at a NEW head of the same PR - an open request for the first head
// would have let the later asks through; and 263 of 340 request files in the clone still say `status: open`.
function heads(text) {
  return [...new Set([...String(text).matchAll(/\b(?:at|head)\s+\**`?([0-9a-f]{7,40})\b/gi)]
    .map((m) => m[1].slice(0, 7).toLowerCase()))];
}

function sharedRepo() {
  return process.env.SHARED_MEMORY_REPO || path.join(os.homedir(), 'Projects', 'brain-shared-memory');
}

/** Every `<area>/request-*.md` of the clone: { id, open, text }. Throws when the clone is unreadable. */
function requests(repo) {
  const out = [];
  for (const area of fs.readdirSync(repo, { withFileTypes: true })) {
    if (!area.isDirectory() || area.name.startsWith('.')) continue;
    let names;
    try { names = fs.readdirSync(path.join(repo, area.name)); } catch (e) { continue; }
    for (const n of names) {
      if (!/^request-.*\.md$/.test(n)) continue;
      let text = '';
      try { text = fs.readFileSync(path.join(repo, area.name, n), 'utf8'); } catch (e) { continue; }
      const head = (/^---\r?\n([\s\S]*?)\r?\n---/.exec(text) || [])[1] || '';
      out.push({ id: `${area.name}/${n.slice(0, -3)}`, open: /^\s*status:\s*open\b/m.test(head), text });
    }
  }
  return out;
}

/** Does `request: <id>` in the text name a file of the clone? */
function namedRequest(repo, text) {
  for (const m of String(text).matchAll(/\brequest:\s*`?([\w./-]+?)`?(?=[\s,;)]|$)/gim)) {
    const id = m[1].replace(/\.md$/, '');
    if (id.includes('/')) { if (fs.existsSync(path.join(repo, id + '.md'))) return id; continue; }
    try {
      for (const area of fs.readdirSync(repo)) {
        if (fs.existsSync(path.join(repo, area, id + '.md'))) return `${area}/${id}`;
      }
    } catch (e) { /* unreadable: no match */ }
  }
  return '';
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  const ps = input.tool_name === 'PowerShell';
  const seg = postSegment(cmd, ps);
  if (seg === null) return 0;
  const text = postedText(cmd, ps, input.cwd || process.cwd());
  const phrase = asks(text);
  if (!phrase) return 0;
  const repo = sharedRepo();
  let reqs;
  try { reqs = requests(repo); } catch (e) {
    console.error(`check-request-gate: shared memory not readable at ${repo} - the request "${phrase}" is not checked`);
    return 0;
  }
  if (namedRequest(repo, text)) return 0;
  const pr = prNumber(seg, cmd);
  const name = pr ? new RegExp(`(?:#|/pull/)${pr}(?!\\d)`) : null;
  const shas = heads(text);
  const fits = (r) => r.open && name.test(r.text) && (!shas.length || shas.some((s) => r.text.includes(s)));
  if (name && reqs.some(fits)) return 0;
  console.error(
    `BLOCKED (check-request-gate): this comment asks another instance to act ("${phrase}"), but no open\n` +
    `shared-memory request names ${pr ? 'PR #' + pr : 'this PR (no PR number in the command)'}` +
    `${shas.length ? ' and the head it names (' + shas.join(', ') + ')' : ''}.\n` +
    'Write the request first, then post:\n' +
    '  python3 scripts/shared-memory-post.py request --to os:<os> --area <topic> --title "<what, PR #n, head>" --body-file <file>\n' +
    'commit and push it, then post the comment - with `request: <id>` (the file stem) in it, or naming the PR so the\n' +
    'open request is found. A PR comment is a pointer, not the request: the other instance reads its shared-memory\n' +
    'inbox, not PR threads (operator 2026-11-12). The local clone is read; pull it if the request came from elsewhere.');
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

module.exports = { gate, asks, unquoted, requests, namedRequest, prNumber, heads };
