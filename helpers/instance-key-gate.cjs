#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash): a PR, comment or review an AI posts to GitHub carries its INSTANCE
 * KEY — one line `<!-- instance-key: <key> -->` — or it is not sent.
 *
 * WHY (measured 2026-10-11, and 2026-09-24 before it): one GitHub login can carry several
 * instances — an operator's two machines, a collaborator's three. Every check that decides
 * "is this mine?" by login (scripts/pr-ball.py, scripts/open-items.py) read the other
 * machine's PR and its "OK to merge" as its own and stayed silent; a test fix waited for a
 * second OK nobody was shown until the operator asked on every side. The git author name is
 * configuration, not proof. A key in the posted text is the one mark the readers can rely on
 * (scripts/instance_key.py, which defines the key and the decision rule).
 *
 * THE KEY: first 10 hex digits of sha256("instance-key:" + <instance id>), the id being the
 * first token of SHARED_MEMORY_SELF (process env, else the brain's .claude/settings*.json
 * env block). Opaque: public repos carry no machine id, and this names nobody — so it never
 * collides with helpers/public-text-guard.cjs, which only looks for names.
 *
 * WHAT COUNTS: `gh pr create|comment|review` and `gh issue create|comment`. The key may stand
 * in the command text or in a file it hands over (`--body-file`, `-F`). A review without a
 * body (`gh pr review --approve`) has no place for it — the gate asks for `--body`.
 * Not covered (named limit): `gh api` writes and the web UI; the operator's own hand-written
 * comments carry no key, and the readers count an unkeyed text under our login as ours.
 *
 * No instance id configured = allow, said on stderr: a brain that has not named itself has
 * no key to give (and its readers keep the old login-only rule). Exit 2 = block.
 * INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs for the measured reason).
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const { invocations } = require('./published-text.cjs');

// Which posts the line RUNS — found among its commands, never in its message text: a commit
// message that quotes the PR command is no post (measured 2026-10-19: such a `git commit` was
// held for a missing key). The regexes stay only for a line the shell parser cannot read to
// the end (heredoc, unbalanced quote): unsure means stricter.
const WRITE_RX = /(^|[;&|(]\s*|\s)gh\s+(pr\s+(create|comment|review)|issue\s+(create|comment))\b/;
const CREATE_RX = /(^|[;&|(]\s*|\s)gh\s+pr\s+create\b/;
function runs(cmd, ps, subs, verbs, rx) {
  const hit = invocations(cmd, ps, 'gh', subs, verbs);
  return hit === null ? rx.test(cmd) : hit.length > 0;
}
const posts = (cmd, ps) => runs(cmd, ps, ['pr'], ['create', 'comment', 'review'], WRITE_RX)
  || runs(cmd, ps, ['issue'], ['create', 'comment'], WRITE_RX);
const creates = (cmd, ps) => runs(cmd, ps, ['pr'], ['create'], CREATE_RX);

function unquote(s) {
  return s.replace(/^(['"])(.*)\1$/, '$2');
}

function selfId(root) {
  let raw = process.env.SHARED_MEMORY_SELF || '';
  if (!raw) {
    for (const name of ['settings.local.json', 'settings.json']) {
      try {
        const env = (JSON.parse(fs.readFileSync(path.join(root, '.claude', name), 'utf8')).env) || {};
        if (env.SHARED_MEMORY_SELF) { raw = String(env.SHARED_MEMORY_SELF); break; }
      } catch (e) { /* not there */ }
    }
  }
  return (raw.trim().toLowerCase().split(/[,\s]+/).filter(Boolean)[0]) || '';
}

function keyFor(id) {
  return id ? crypto.createHash('sha256').update('instance-key:' + id, 'utf8').digest('hex').slice(0, 10) : '';
}

function handedFiles(cmd) {
  const out = [];
  for (const rx of [/--body-file[=\s]+("[^"]+"|'[^']+'|\S+)/g, /\s-F\s+("[^"]+"|'[^']+'|[^\s=]+)(?=\s|$)/g]) {
    for (const m of cmd.matchAll(rx)) out.push(unquote(m[1]));
  }
  return out.filter((f) => f !== '-');
}

// The checkout a `gh pr create` opens its PR from: the nearest folder upward with a `.git`.
function checkoutOf(dir) {
  for (let d = path.resolve(dir); ; d = path.dirname(d)) {
    if (fs.existsSync(path.join(d, '.git'))) return d;
    if (path.dirname(d) === d) return null;
  }
}

// Every change declares its level (helpers/change-level.cjs): checked here BEFORE the PR exists,
// not first in CI - a red check found after the post is a PR that already asked for review.
// The PR's checkout is the session folder, or the one an `env -C <dir>` prefix runs gh in. A
// `--repo <owner/name>` that this checkout's origin is not leaves the fragments out of sight:
// measured 2026-11-03 (Windows instance), `gh pr create -R <core> --head <branch>` ran from the
// brain folder, whose checkout has no changelog.d - nothing was found, the PR opened, and the
// CI lint went red on the undeclared level a minute later. Such a create is held, not passed.
function levelFindings(cmd, cwd, ps) {
  if (!creates(cmd, ps)) return [];
  const seg = (invocations(cmd, ps) || []).find((t) => t.join(' ').includes('gh pr create')) || [];
  const at = seg[0] === 'env' ? seg.indexOf('-C') : -1;
  // A hook reads the command TEXT, never the shell's expansion (measured 2026-11-06, Windows
  // instance): `env -C "$W/core-post" gh pr create` handed this gate the literal `$W/core-post`,
  // which resolved under the session folder, found the brain's origin and blocked with a level
  // finding although the fragment was fine. Say so instead of judging the wrong checkout.
  if (at >= 0 && /[$%]/.test(seg[at + 1] || '')) {
    return [`the env -C path "${seg[at + 1]}" is a shell variable - a hook reads the command text, ` +
      `not its expansion, so the PR's checkout cannot be found. Write the path literally: env -C <absolute path> gh pr create ...`];
  }
  const repo = checkoutOf(at >= 0 && seg[at + 1] ? require('./public-text-guard.cjs').nativePath(seg[at + 1]) : cwd);
  const r = seg.findIndex((t) => t === '-R' || t === '--repo' || /^--repo=/.test(t));
  const slug = r < 0 ? '' : (seg[r].startsWith('--repo=') ? seg[r].slice(7) : seg[r + 1] || '');
  if (slug) {
    let origin = '';
    try {
      origin = require('child_process').execFileSync('git', ['-C', repo || cwd, 'remote', 'get-url', 'origin'],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    } catch (e) { /* no checkout, no origin */ }
    if (!origin.toLowerCase().replace(/\.git\s*$/, '').trim().endsWith(slug.toLowerCase())) {
      return [`gh pr create names --repo ${slug}, but the checkout it runs in (${repo || cwd}) is not that repo - ` +
        `its changelog fragments are out of sight. Run it in the PR's checkout: env -C <that checkout> gh pr create ...`];
    }
  }
  if (!repo) return [];
  // The PR's own fragments only (changedFragments, change-level.cjs); a repo whose base cannot be
  // named keeps the whole-folder check. `--base <branch>` names the base when the PR gives one.
  const lv = require('./change-level.cjs');
  const b = seg.findIndex((t) => t === '-B' || t === '--base' || /^--base=/.test(t));
  const base = b < 0 ? '' : `origin/${seg[b].startsWith('--base=') ? seg[b].slice(7) : seg[b + 1] || ''}`;
  const only = lv.changedFragments(repo, base === 'origin/' ? '' : base);
  return lv.check(repo, only === null ? undefined : only).findings;
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  const ps = input.tool_name === 'PowerShell';
  if (!posts(cmd, ps)) return 0;
  const lv = levelFindings(cmd, input.cwd || process.cwd(), ps);
  if (lv.length) {
    console.error('BLOCKED (instance-key-gate, change level): a changelog fragment of this PR does not declare its level.\n' +
      lv.map((f) => '  ' + f).join('\n') + '\n' +
      'Write in the fragment, next to (test: …): (level: <symptom|reader|writer|design>; higher: <level> — <why not> | none;\n' +
      'debt: <what stays open> | none). Four questions: which levels did you see, which did you build, why not the\n' +
      'higher one, what stays open? Check: node helpers/change-level.cjs check');
    return 2;
  }
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const key = keyFor(selfId(root));
  if (!key) {
    console.error('instance-key-gate: SHARED_MEMORY_SELF unset - this instance has no key, nothing checked');
    return 0;
  }
  const mark = `<!-- instance-key: ${key} -->`;
  const cwd = input.cwd || process.cwd();
  let text = cmd;
  const unread = [];
  const pub = require('./published-text.cjs').publishedText(cmd, ps);
  for (const f of pub ? pub.files : handedFiles(cmd)) {
    // `~` expands as the shell does it: a `--body-file ~/<file>` that stays unread hides its key (2026-10-18).
    // A Git Bash path (`/c/...`, `/tmp/...`) is what the shell sees; node on Windows cannot open it, so
    // the key in it went unseen and the post was blocked (measured 2026-10-14, Windows instance) - the
    // same translation public-text-guard.cjs uses.
    const v = require('./published-text.cjs').expandVars(f, cmd);
    if (v === null) { unread.push(f); continue; }
    const p = require('./public-text-guard.cjs').nativePath(v.replace(/^~(?=$|[\\/])/, require('os').homedir()));
    try { text += '\n' + fs.readFileSync(path.resolve(cwd, p), 'utf8'); } catch (e) { /* the write fails on it too */ }
  }
  if (new RegExp(`<!--\\s*instance-key:\\s*${key}\\s*-->`, 'i').test(text)) return 0;
  const noBody = /\bgh\s+pr\s+review\b/.test(cmd) && !/--body(-file)?\b|\s-b\s|\s-F\s/.test(cmd);
  console.error(
    `BLOCKED (instance-key-gate): this GitHub text carries no instance key. Add this line to its body:\n  ${mark}\n` +
    (unread.length ? `A handed file names a variable this gate cannot resolve (${unread.join(', ')}) - write the path out.\n` : '') +
    (noBody ? 'A review without a body has no place for it - add --body "<one line> ' + mark + '".\n' : '') +
    'Why: several instances can post under one GitHub login; the readers that decide whose move a PR\n' +
    'is (pr-ball.py, open-items.py) tell them apart only by this key. It is a hash and names nobody.');
  return 2;
}

if (require.main === module) {
  let data = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { data += c; });
  process.stdin.on('end', () => {
    let rc = 0;
    try { rc = gate(JSON.parse(data)); } catch (e) { rc = 0; /* unparsable input: nothing to check */ }
    process.exit(rc);
  });
  process.stdin.resume();
}

module.exports = { gate, keyFor, selfId, handedFiles };
