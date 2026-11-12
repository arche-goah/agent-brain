#!/usr/bin/env node
/**
 * PreToolUse Hook (Bash, PowerShell): a PR is built and reviewed at the intelligence its risk needs, and
 * approved and merged only on a CONTENT review — how the change is built and how it fits the whole —
 * not on a function or OS check alone.
 *
 * WHY (operator orders 2026-11-10, the macOS instance; wording translated in docs/rule-history.md,
 * "Model Routing"). First, after three collaborator PRs were approved on green fixtures and an OS run:
 * review PRs for content, not only OS compatibility — how things are built and how they fit the big
 * picture — so the coherence scan and the full audit have less to find; anchored in a mechanism. Measured
 * the same day: review-claim-gate asks whether the diff was read, merge-request-gate whether each OS said
 * OK; nothing asked for a verdict on the design, and one of the three approved PRs re-implemented a
 * dispatcher rule in a second language. Second: judge a PR by reach, complexity and risk, and set the model
 * that builds and reviews it — nothing critical built with a smaller model, at the build and at the review.
 *
 * RISK: the higher of the body's `Risk: low|medium|high — <why>` line and the FLOOR the changed files
 * give (`pr-risk.json` at the core root, `floors`). The author cannot declare below the floor.
 * MODEL: measured, never claimed — the last assistant record's `message.model` of a known family (`pr-risk.json`
 * tiers) in the caller's transcript (`transcript_path`, a sub-agent's own file when `agent_id` is set), read only
 * when a check needs it; `<synthetic>` or an unknown family = not measured.
 *
 * CHECK 1 — `gh pr create`: the body carries a `Risk:` line at or above the floor of the branch's files
 *   (`git diff --name-only origin/main...HEAD` in the call's directory: `env -C <dir>`, `cd <dir>`, else the
 *   hook's cwd, resolved by helpers/pr-repo.cjs `prCalls`), and the session's model is at
 *   least `minimum.<risk>.build`.
 * CHECK 2 — `gh pr review --approve` (or `-a`): the text carries `Fit:`, `Design:`, `Cost:` (each a real
 *   answer, MIN_ANSWER characters, not "ok"/"n/a") and a `Model:` line naming the measured model, which is
 *   at least `minimum.<risk>.review` of the PR (risk from its body and its files).
 * CHECK 3 — any `gh pr comment|review` with a `Model:` line: the line names the measured model (a review
 *   cannot claim a stronger model than it ran on).
 * CHECK 3b — `gh pr comment|review` (not an approval) whose text is an OS hand review (`os-review.cjs`
 *   `handReview`) by an instance other than the PR author's: it carries `Fit:` / `Design:` / `Cost:` / `Model:`
 *   in the form CHECK 4 counts, held when posted — not first at the merge.
 * CHECK 4 — `gh pr merge`: the thread (comments and review bodies) holds a content review by an instance
 *   OTHER than the author's (key in the body; a body without a key accepts any keyed review) whose `Model:`
 *   is at least the review minimum. A merge train PR (body opens with `## Merge train`) is checked per
 *   member listed as `- #<n>`.
 * Override, said in the call: `# CONTENT-REVIEW-OK: <why>` (a repo with no second reviewer, a pure data
 * PR) — it goes to the change log like every marker.
 *
 * Unreadable PR, transcript or diff = that part is not checked, said on stderr. Fixture seams only:
 * CONTENT_REVIEW_GATE_GH (a node script standing in for gh), CONTENT_REVIEW_GATE_FILES (newline list of
 * the branch's files). Exit 2 = block. INPUT IS READ TO ITS END, never on a timer (see file-guard.cjs).
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { invocations, publishedText, nativePath } = require('./published-text.cjs');

const LABELS = ['Fit', 'Design', 'Cost'];
const MIN_ANSWER = 25;
const EMPTY_RX = /^(?:n\/?a|none|ok(?:ay)?|fine|lgtm|looks good|-+|—|yes|no)\.?$/i;
const KEY_RX = /<!--\s*instance-key:\s*([0-9a-f]{6,})\s*-->/i;
const ESCAPE = /#\s*CONTENT-REVIEW-OK:\s*\S/;
const DOC = 'docs/content-review.md';
const RISKS = ['low', 'medium', 'high'];

function config() {
  try { return JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'pr-risk.json'), 'utf8')); }
  catch (e) { return { tiers: ['haiku', 'sonnet', 'opus', 'fable'], floors: [], minimum: {} }; }
}
const CFG = config();

/** Tier index of a model name ("claude-opus-5-5" -> opus), -1 when unknown. */
function tier(name) {
  const s = String(name || '').toLowerCase();
  return CFG.tiers.findIndex((t) => s.includes(t));
}
const need = (risk, step) => tier(((CFG.minimum || {})[risk] || {})[step]);

/** The risk floor the files give: the highest `floors` entry one of them matches. */
function floor(files) {
  const rx = (g) => new RegExp('^' + g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
  let best = 0, why = '';
  for (const f of CFG.floors || []) {
    const r = RISKS.indexOf(f.risk);
    const hit = files.find((x) => (f.paths || []).some((g) => rx(g).test(x)));
    if (hit && r > best) { best = r; why = hit; }
  }
  return { risk: best, why };
}

/** Declared risk index from a body's `Risk:` line, -1 when there is none with a reason. */
function declared(body) {
  const m = /^\s*(?:[-*>]\s*)*(?:\*\*)?risk(?:\*\*)?\s*:\s*(?:\*\*)?\s*(low|medium|high)\b\W*(.*)$/im.exec(String(body || ''));
  return m && m[2].trim().length >= 10 ? RISKS.indexOf(m[1].toLowerCase()) : -1;
}

/** The labels of the block that are missing or carry no real answer in `text`. [] = a content review. */
function missing(text) {
  const got = {};
  for (const line of String(text || '').split(/\r?\n/)) {
    const m = /^\s*(?:[-*>]\s*)*(?:\*\*)?(fit|design|cost)(?:\*\*)?\s*:\s*(?:\*\*)?\s*(.*)$/i.exec(line);
    if (!m) continue;
    const label = m[1][0].toUpperCase() + m[1].slice(1).toLowerCase();
    const answer = m[2].replace(/\*\*/g, '').trim();
    if (answer.length >= MIN_ANSWER && !EMPTY_RX.test(answer)) got[label] = true;
  }
  return LABELS.filter((l) => !got[l]);
}
/** The model a `Model:` line names: the first word of a known family on the line ("Model: reviewed by Opus 5.5" names
 * opus - Windows review of #478 read "reviewed"), else its first word (an unknown name stays unknown, tier -1). */
function modelLine(text) {
  const rest = (/^\s*(?:[-*>]\s*)*(?:\*\*)?model(?:\*\*)?\s*:\s*(?:\*\*)?([^\n]*)/im.exec(String(text || '')) || [])[1];
  if (rest === undefined) return undefined;
  const words = rest.replace(/<!--[\s\S]*?-->/g, ' ').replace(/[*`]/g, ' ').split(/\s+/).filter(Boolean);
  return words.find((w) => tier(w) >= 0) || words[0];
}

/** Risk index of a PR: its declaration and its files' floor, the higher. */
function prRisk(pr) {
  const files = (pr.files || []).map((f) => f.path);
  return Math.max(declared(pr.body), floor(files).risk, 0);
}

/** Does the PR thread hold a content review by another instance, on a model the risk allows? */
function reviewed(pr) {
  const author = (KEY_RX.exec(String(pr.body || '')) || [])[1];
  const least = need(RISKS[prRisk(pr)], 'review');
  const texts = [...(pr.comments || []), ...(pr.reviews || [])].map((c) => String((c && c.body) || ''));
  return texts.some((t) => {
    const k = (KEY_RX.exec(t) || [])[1];
    return k && (!author || k.toLowerCase() !== author.toLowerCase()) && missing(t).length === 0
      && tier(modelLine(t)) >= least;
  });
}

/** The caller's model, measured: the last assistant record's `message.model` of a known family. null when unreadable. */
function sessionModel(p) {
  try {
    const st = fs.statSync(p);
    const n = Math.min(st.size, 4 * 1024 * 1024);
    const fd = fs.openSync(p, 'r');
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, st.size - n);
    fs.closeSync(fd);
    // the last model of a KNOWN family: Claude Code writes `"model":"<synthetic>"` for synthetic assistant
    // entries (measured on the Windows instance 2026-11-10, a resumed session), and a new family is not yet in
    // `tiers` - neither is the smallest model, both are "not measured" (review of #478). Only the model of an
    // ASSISTANT record counts: the same key stands in an Agent call's override and in printed JSON (counter-check
    // of #478, macOS instance); the first line of the tail may be cut and is skipped by the parse.
    const all = [];
    for (const line of buf.toString('utf8').split('\n')) {
      let r; try { r = JSON.parse(line); } catch (e) { continue; }
      const m = r && r.type === 'assistant' && r.message && r.message.model;
      if (m && tier(m) >= 0) all.push(m);
    }
    if (!all.length) { console.error('content-review-gate: no model of a known family in the transcript (pr-risk.json tiers), model not checked'); return null; }
    return all[all.length - 1];
  } catch (e) { return null; }
}

/** The transcript of the CALLER: a sub-agent's call carries `agent_id`, and its model is the one in
 * `<session>/subagents/agent-<id>.jsonl` (same path rule as skill-gate.cjs `transcripts()`; a shared helper is
 * the open debt), never the parent's - Windows review of #478: a Haiku agent built high risk under an Opus
 * parent, an Opus agent under a Sonnet parent was refused. No such file = not measured, never the parent's. */
function callerTranscript(input) {
  const tp = input && input.transcript_path;
  if (!tp) return null;
  const id = String(input.agent_id || '');
  if (!id) return String(tp);
  if (!/^[\w-]+$/.test(id)) return null;
  const sub = path.join(path.dirname(String(tp)), path.basename(String(tp), '.jsonl'), 'subagents', `agent-${id}.jsonl`);
  if (fs.existsSync(sub)) return sub;
  console.error(`content-review-gate: no transcript for sub-agent ${id}, model not checked`);
  return null;
}

/** The model read once, only when a check needs it (review of #478: `git status` should cost no transcript read). */
function lazyModel(input) {
  let done = false, value = null;
  return () => { if (!done) { done = true; const p = callerTranscript(input); value = p ? sessionModel(p) : null; } return value; };
}

function gh(args) {
  const fake = process.env.CONTENT_REVIEW_GATE_GH;
  return execFileSync(fake ? process.execPath : 'gh', fake ? [fake, ...args] : args,
    { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
}
const readPr = (repo, nr) => JSON.parse(gh(['pr', 'view', String(nr), '-R', repo, '--json', 'body,comments,reviews,files']));
/** `-R OWNER/REPO` or gh's long form `-R HOST/OWNER/REPO`, as OWNER/REPO (Windows review of #504). */
function repoArg(cmd) {
  const m = /(?:-R|--repo)[=\s]+["']?([\w.-]+(?:\/[\w.-]+){1,2})/.exec(cmd);
  return m ? m[1].split('/').slice(-2).join('/') : null;
}
/** A remote URL's OWNER/REPO, case-folded: https, ssh:// and scp-like `git@host:owner/repo.git` alike. */
const remoteSlug = (url) => ((/[:/]([\w.-]+\/[\w.-]+?)(?:\.git)?\/?$/.exec(url) || [])[1] || '').toLowerCase();

function target(cmd, verb) {
  const url = /github\.com\/([\w.-]+\/[\w.-]+)\/pull\/(\d+)/.exec(cmd);
  if (url) return { repo: url[1], nr: url[2] };
  const repo = repoArg(cmd);
  const nr = new RegExp(`\\bgh\\s+pr\\s+${verb}\\s+(?:(?:-R|--repo)[=\\s]+\\S+\\s+)?["']?(\\d+)\\b`).exec(cmd);
  return repo && nr ? { repo, nr: nr[1] } : null;
}

function postedText(cmd, ps, cwd) {
  const pub = publishedText(cmd, ps);
  if (!pub) return cmd;
  let text = pub.texts.join('\n');
  for (const f of pub.files) {
    const p = String(f).replace(/^~(?=$|[\\/])/, require('os').homedir());
    // nativePath: a Git Bash `/c/...` path node on Windows cannot open (OS-19, same reader as review-claim-gate)
    try { text += '\n' + fs.readFileSync(path.resolve(cwd, nativePath(p)), 'utf8'); }
    catch (e) { /* the post fails on it too */ }
  }
  return text;
}

function branchFiles(cwd) {
  const seam = process.env.CONTENT_REVIEW_GATE_FILES;
  if (seam !== undefined) return seam.split('\n').filter(Boolean);
  const git = (args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] });
  // the remote's default branch, not a fixed `main` (review of #478)
  let base = 'origin/main';
  try { base = git(['rev-parse', '--abbrev-ref', 'origin/HEAD']).trim() || base; } catch (e) { /* no origin/HEAD set: main */ }
  try { return git(['diff', '--name-only', `${base}...HEAD`]).split('\n').filter(Boolean); } catch (e) { return null; }
}

/** The PR's files for `gh pr create`. With `-R <repo>` naming another repo than the checkout the call runs in, the
 * checkout's branch says nothing about the PR (2026-11-12: a core PR opened from the brain's working copy was scored
 * by a brain script and forced to "medium"): the files come from the repo's compare view of `--head` instead, and
 * without `--head` they are unreadable (not checked, said on stderr). */
function createFiles(cmd, cwd) {
  if (process.env.CONTENT_REVIEW_GATE_FILES !== undefined) return branchFiles(cwd);
  const repo = repoArg(cmd);
  if (!repo) return branchFiles(cwd);
  let origin = '';
  try { origin = execFileSync('git', ['-C', cwd, 'remote', 'get-url', 'origin'], { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch (e) { /* no checkout here */ }
  // the normalised OWNER/REPO, not a '/'-suffix: an SSH origin (git@github.com:owner/repo) has a ':' there
  if (remoteSlug(origin) === repo.toLowerCase()) return branchFiles(cwd);
  const head = (/--head[=\s]+["']?([^\s"']+)/.exec(cmd) || [])[1];
  const base = (/--base[=\s]+["']?([^\s"']+)/.exec(cmd) || [])[1] || 'main';
  if (!head) { console.error(`content-review-gate: ${repo} is not this checkout and no --head given - risk floor not checked`); return null; }
  try { return gh(['api', `repos/${repo}/compare/${base}...${head}`, '--jq', '.files[].filename']).split('\n').filter(Boolean); }
  catch (e) { console.error(`content-review-gate: compare ${base}...${head} in ${repo} unreadable - risk floor not checked`); return null; }
}

const QUESTIONS =
  `  Fit:    what already does this or part of it (rule, gate, script, skill)? duplicate, extension or contradiction? right place (core / suite / instance)?\n` +
  `  Design: right object and level? a second copy of a rule? a simpler way? what does it couple?\n` +
  `  Cost:   how often does it run, what does it add to always-loaded context or a run, what does it weaken?\n` +
  `  Model:  <the model this review ran on, as the transcript records it>\n` +
  `  (the questions and the risk criteria: ${DOC}; model minimums: pr-risk.json)`;
const block = (msg) => { console.error(`BLOCKED (content-review-gate): ${msg}`); return 2; };

const HANDOFF =
  'Hand the build to the right model, chosen by the work, not asked of the operator:\n' +
  '  - an AGENT on that model (Agent tool, `model: "<tier>"`) when the build is self-contained: one PR, a brief that\n' +
  '    states goal, files and the fixture - the agent builds and commits, this session reviews and opens the PR;\n' +
  '  - a SESSION on that model when it needs the operator (questions, decisions), a live system, or many steps over\n' +
  '    time: if one runs in parallel (`ListAgents`, the session map), hand it over by SendMessage with the brief;\n' +
  '    otherwise say so in the closing message and ask the operator to start one.\n' +
  'A model family is matched by name (`pr-risk.json` tiers), so a newer version of the same family counts at once.';

/** CHECK 0 — `git commit` in the core repo (its root carries pr-risk.json): the staged files' floor against the
 * session's model, at the first build step instead of after the build (operator 2026-11-10: the session must
 * report a risky build its model is too small for and hand it to a session or an agent on the right one). */
function checkCommit(cmd, ps, cwd, getModel) {
  const sub = (w) => { let i = 1; while (['-C', '-c'].includes(w[i])) i += 2; return w[i]; };
  const hits = invocations(cmd, ps, 'git', null, null);
  const commits = hits === null ? /\bgit\b[^\n;&|]*\scommit\b/.test(cmd) : hits.some((w) => sub(w) === 'commit');
  if (!commits) return 0;
  const dir = (/\bgit\s+-C\s+("[^"]+"|'[^']+'|\S+)/.exec(cmd) || [])[1];
  const repo = dir ? path.resolve(cwd, nativePath(dir.replace(/^["']|["']$/g, ''))) : cwd;   // OS-19
  let root;
  try { root = execFileSync('git', ['-C', repo, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); }
  catch (e) { return 0; }
  if (!fs.existsSync(path.join(root, 'pr-risk.json'))) return 0;
  let files = process.env.CONTENT_REVIEW_GATE_FILES;
  if (files === undefined) {
    try { files = execFileSync('git', ['-C', root, 'diff', '--cached', '--name-only'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
    catch (e) { return 0; }
  }
  const fl = floor(String(files).split('\n').filter(Boolean));
  const least = need(RISKS[fl.risk], 'build');
  const model = getModel();
  if (model === null || tier(model) >= least) return 0;
  return block(`this commit carries ${fl.why} - risk ${RISKS[fl.risk]}, built with at least ${CFG.tiers[least]}; this session runs on ${model}.\n` +
    HANDOFF.replace('<tier>', CFG.tiers[least]));
}

/** The directory a `gh pr <verb>` runs in (`env -C`, `cd`, else the hook's cwd; helpers/pr-repo.cjs), the first
 * invocation's. 2026-11-12: `env -C <clone> gh pr create` was scored by the hook cwd's branch (the brain's working
 * copy) - a brain-only script raised two core PRs (#524, #525) to medium. */
function callDir(cmd, ps, cwd, verbs) {
  let calls = null;
  try { calls = require('./pr-repo.cjs').prCalls(cmd, cwd, ps, verbs); } catch (e) { /* unreadable: the hook cwd */ }
  return (calls && calls[0] && calls[0].dir) || cwd;
}

function checkCreate(cmd, ps, cwd, getModel) {
  const hits = invocations(cmd, ps, 'gh', ['pr'], ['create']);
  if (hits === null ? !/\bgh\s+pr\s+create\b/.test(cmd) : !hits.length) return 0;
  const dir = callDir(cmd, ps, cwd, ['create']);
  const body = postedText(cmd, ps, dir);
  const files = createFiles(cmd, dir);
  if (!files) console.error('content-review-gate: branch files unreadable, risk floor not checked');
  const fl = floor(files || []);
  const d = declared(body);
  if (d < 0) return block('a PR body needs a line `Risk: low|medium|high — <why: reach, complexity, what breaks if it is wrong>`.\n' +
    `The changed files give at least: ${RISKS[fl.risk]}${fl.why ? ` (${fl.why})` : ''}. Criteria: ${DOC}.`);
  if (d < fl.risk) return block(`the body declares risk ${RISKS[d]}, but ${fl.why} sets the floor at ${RISKS[fl.risk]} (pr-risk.json). Declare ${RISKS[fl.risk]} or higher.`);
  const model = getModel();
  if (model === null) { console.error('content-review-gate: build model not measured, not checked'); return 0; }
  const least = need(RISKS[d], 'build');
  if (tier(model) < least) return block(`risk ${RISKS[d]} is built with at least ${CFG.tiers[least]}; this session runs on ${model}.\n` +
    HANDOFF.replace('<tier>', CFG.tiers[least]) + '\nWhy: operator order 2026-11-10 - nothing critical is built with a smaller model.');
  return 0;
}

function checkReviewPost(cmd, ps, cwd, getModel) {
  const hits = invocations(cmd, ps, 'gh', ['pr'], ['review', 'comment']);
  const isPost = hits === null ? /\bgh\s+pr\s+(?:review|comment)\b/.test(cmd) : hits.length > 0;
  if (!isPost) return 0;
  const model = getModel();
  const text = postedText(cmd, ps, callDir(cmd, ps, cwd, ['review', 'comment']));
  const claimed = modelLine(text);
  if (claimed && model !== null && tier(claimed) !== tier(model)) {
    return block(`the text says \`Model: ${claimed}\`, the transcript says this session runs on ${model}. Write the model it ran on.`);
  }
  const approves = hits === null ? /\bgh\s+pr\s+review\b[^\n]*\s(?:--approve|-a)\b/.test(cmd)
    : hits.some((w) => w[2] === 'review' && (w.includes('--approve') || w.includes('-a')));
  if (!approves) return checkReviewComment(cmd, text);
  const gone = missing(text);
  if (!claimed) gone.push('Model');
  if (gone.length) return block(`an approval needs a content review, not only a function or OS check - missing: ${gone.join(', ')}.\n` +
    `Each a real answer (at least ${MIN_ANSWER} characters):\n${QUESTIONS}\n` +
    'Why: operator order 2026-11-10 - review how a change is built and how it fits the whole, in small portions on ' +
    'every side, so the coherence scan and the full audit do not have to find it later.');
  const t = target(cmd, 'review');
  let pr = null;
  if (t) { try { pr = readPr(t.repo, t.nr); } catch (e) { /* below */ } }
  if (!pr) { console.error('content-review-gate: PR unreadable, review model not checked against its risk'); return 0; }
  const risk = RISKS[prRisk(pr)];
  const least = need(risk, 'review');
  if (tier(model || claimed) < least) return block(`${t.repo}#${t.nr} has risk ${risk}; it is reviewed with at least ${CFG.tiers[least]}, ` +
    `this review runs on ${model || claimed}.\n` + HANDOFF.replace('<tier>', CFG.tiers[least]).replace(/build/g, 'review'));
  return 0;
}

/**
 * CHECK 3b — a review posted as a COMMENT (an OS hand review on a PR another instance wrote) carries the content lines
 * in the form `missing()` reads, held at posting time. Measured 2026-11-12 on agent-brain #473: the Windows review held
 * fit, design and cost in one heading line ("fit: yes, design: partly, cost: low"); `missing()` read Fit and Design
 * as absent, and nothing said so until the train merge would block - 30 of 33 PRs of that train had no counted review.
 */
function checkReviewComment(cmd, text) {
  const { handReview } = require('./os-review.cjs');
  const reviewer = ['macOS', 'Windows', 'Linux'].map((os) => handReview(text, os)).find(Boolean);
  if (!reviewer) return 0;
  const t = target(cmd, 'comment') || target(cmd, 'review');
  let pr = null;
  if (t) { try { pr = readPr(t.repo, t.nr); } catch (e) { /* below */ } }
  if (!pr) { console.error('content-review-gate: PR unreadable, review form not checked'); return 0; }
  // A merge train's OS check is the one hand check at its head; the content reviews belong to its members (CHECK 4
  // reads them there). Windows review of #508, 2026-11-12: without this the train's OS OK would be held.
  if (/^\s*##\s*Merge train\b/.test(String(pr.body || ''))) return 0;
  const author = (KEY_RX.exec(String(pr.body || '')) || [])[1];
  if (author && author.toLowerCase() === String(reviewer).toLowerCase()) return 0;   // the author's own OS check
  const gone = missing(text);
  if (!modelLine(text)) gone.push('Model');
  if (!gone.length) return 0;
  return block(`this comment is an OS review of ${t.repo}#${t.nr} by another instance, but the content review the merge counts is missing: `
    + `${gone.join(', ')}.\nEach on a line of its own, at least ${MIN_ANSWER} characters (a heading like "fit: yes, design: partly" is not read):\n`
    + QUESTIONS + '\nWhy: 2026-11-12 - a review in another form was posted, counted nowhere, and found only at the train merge.');
}

function checkMerge(cmd, ps) {
  const hits = invocations(cmd, ps, 'gh', ['pr'], ['merge']);
  if (hits === null ? !/\bgh\s+pr\s+merge\b/.test(cmd) : !hits.length) return 0;
  const t = target(cmd, 'merge');
  if (!t) { console.error('content-review-gate: no repo and number in the command, nothing checked'); return 0; }
  let pr;
  try { pr = readPr(t.repo, t.nr); } catch (e) { console.error('content-review-gate: PR unreadable, nothing checked'); return 0; }
  const train = /^\s*##\s*Merge train\b/.test(String(pr.body || ''));
  const members = train ? [...String(pr.body).matchAll(/^\s*-\s*#(\d+)\b/gm)].map((m) => m[1]) : [t.nr];
  const open = [];
  for (const n of members) {
    let p = pr;
    if (train) { try { p = readPr(t.repo, n); } catch (e) { open.push(`#${n} (unreadable)`); continue; } }
    if (!reviewed(p)) open.push(`#${n} (risk ${RISKS[prRisk(p)]}, review on ${CFG.tiers[need(RISKS[prRisk(p)], 'review')]} or above)`);
  }
  if (!open.length) return 0;
  return block(`${t.repo}#${t.nr} - no content review by another instance on: ${open.join(', ')}.\n` +
    `A merge needs, besides the OS and CI checks, a review (with its instance key, not the author's) carrying:\n${QUESTIONS}\n` +
    'A repo with no second reviewer or a pure data PR: add `# CONTENT-REVIEW-OK: <why>` to the call.\n' +
    'Why: operator order 2026-11-10 - three PRs were approved on green fixtures; one carried a second copy of a rule.');
}

function gate(input) {
  if (!input || !['Bash', 'PowerShell'].includes(input.tool_name)) return 0;
  const cmd = String((input.tool_input && input.tool_input.command) || '');
  if (ESCAPE.test(cmd) || !/\b(?:gh|git)\b/.test(cmd)) return 0;
  const ps = input.tool_name === 'PowerShell';
  const cwd = input.cwd || process.cwd();
  const model = lazyModel(input);
  return checkCommit(cmd, ps, cwd, model) || checkCreate(cmd, ps, cwd, model)
    || checkReviewPost(cmd, ps, cwd, model) || checkMerge(cmd, ps);
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

module.exports = { gate, missing, reviewed, floor, declared, tier };
