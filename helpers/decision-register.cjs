#!/usr/bin/env node
/**
 * Decision register: every answer the operator gives through the question tool is kept in ONE
 * versioned file, and a new question is checked against it before it reaches the operator.
 *
 * The class (operator, 2026-11-11, translated): "either it was documented in a sloppy, nested way,
 * or you read sloppily — either way a defect to be fixed cleanly at the root"; and on the first fix,
 * which only watched purchase questions: "that sounds tailor-made, ONLY for a purchase decision —
 * is that really just the instance, or was there a class fix?". The day's case: two questions the
 * operator had answered one and two days earlier (a tool set "what do you have already", an
 * industrial PoE splitter "order it with the rest") were put to them again, and a 19-inch case they
 * had rejected was proposed again. The answers lived only in the transcripts and in one project
 * ledger the asking session did not read. Nothing kept an answer where the next asker looks.
 * A replay over one instance's 1316 question-tool calls found 44 near-verbatim re-asks; the day's
 * two re-asks were NOT among them — reworded, so a word match alone misses the class.
 *
 * Three entry points, one file:
 *   PostToolUse  (AskUserQuestion) — the hook appends {date, session, cwd, question, answer, notes}
 *                per answered question to the register. The producer writes; no agent step.
 *   PreToolUse   (AskUserQuestion) — each new question is matched against earlier answers: a cheap
 *                word prefilter (shared rare words, weighted by how rare they are in the register)
 *                picks up to three candidates, a small model judges whether the new question asks
 *                the operator to decide a matter an earlier answer already decided. Same matter:
 *                deny ONCE with the earlier answer, its date and session ("act on it, or say what
 *                changed"); the same question re-issued passes. Candidates the model rejects, or
 *                no verdict: allow, candidates added as context. Fails open on every error.
 *   CLI          `--backfill [dir]` fills the register from transcripts; `--replay [dir] [--last N]
 *                [--no-model]` runs the matcher over history (each question against answers of
 *                OTHER sessions before it); `--check "<question>"` matches one question.
 *
 * Instance data `.claude/rules/decision-register.json` (all optional):
 *   {"register": "docs/maintenance/decision-register.jsonl", "model": "opus", "min_score": 0.22,
 *    "enabled": true}
 * Env for fixtures: DECISION_REGISTER_BIN (model binary, default `claude`), DECISION_REGISTER_MODEL.
 * Fixture: scripts/test-decision-register.sh.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const MARKER = 'DECISION-REGISTER';

function config() {
  let d = {};
  try { d = JSON.parse(fs.readFileSync(path.join(ROOT, '.claude', 'rules', 'decision-register.json'), 'utf8')); } catch (e) { /* defaults */ }
  return {
    register: path.resolve(ROOT, d.register || 'docs/maintenance/decision-register.jsonl'),
    // opus, not sonnet (replay 2026-11-11, last 100 answers): sonnet held 13 questions, 7 of them rightly (54 %); with
    // object anchor, options and the main-choice test it still held 11 at 64 %; opus held 5, all rightly
    model: process.env.DECISION_REGISTER_MODEL || d.model || 'opus',
    bin: process.env.DECISION_REGISTER_BIN || d.bin || 'claude',
    minScore: typeof d.min_score === 'number' ? d.min_score : 0.22,
    enabled: d.enabled !== false,
    state: path.join(ROOT, '.claude-state', 'decision-register-denied.json'),
    recurring: [...RECURRING, ...(d.recurring_patterns || [])].map((p) => { try { return new RegExp(p, 'iu'); } catch (e) { return null; } }).filter(Boolean),
  };
}

// Recurring check-ins are asked every session BY DESIGN — their answer holds for that moment only, so they are
// neither matched nor matchable (replay 2026-11-11: 4 of 6 false hits were such shapes). English built in; the
// operator's language as instance data `recurring_patterns`.
const RECURRING = [
  '\\bcontinue autonomous|\\bstay (in )?autonomous|\\bkeep working (on my own|autonomously)|\\bback to interactive\\b',
  '\\b\\d+\\s+(open\\s+)?(items?|points?|tasks?)\\b[^?]*\\b(shall|should|may) i\\b|\\b(shall|should|may) i\\b[^?]*\\b\\d+\\s+(open\\s+)?(items?|points?|tasks?)\\b',
  '^\\s*what (comes )?next\\??\\s*$|\\bwhere do (we|i) (go|start) (from here|next)\\b',
];
const recurring = (q, cfg) => cfg.recurring.some((r) => r.test(q));

// ---- register -------------------------------------------------------------------------------
function load(file) {
  try {
    return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean)
      .map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
  } catch (e) { return []; }
}
function append(file, entries) {
  if (!entries.length) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(file, entries.map((e) => JSON.stringify(e)).join('\n') + '\n');
}

// Answers come as an object {question: answer} (tool input/response) or as the result text
// `"<question>"="<answer>"` — both read here. Only a real answer is a decision.
// The options travel with the answer: "Step drill" alone means nothing without the list it was picked from
// (replay 2026-11-11: without them the judge could not tell that a tool question was settled).
const optionsOf = (qobjs) => Object.fromEntries((qobjs || []).filter((q) => q && q.question)
  .map((q) => [q.question, (q.options || []).map((o) => o.label).filter(Boolean)]));
function answerPairs(questions, response, opts = {}) {
  const out = [];
  const obj = response && typeof response === 'object' && !Array.isArray(response) ? (response.answers || null) : null;
  const notes = response && typeof response === 'object' ? (response.annotations || {}) : {};
  const text = typeof response === 'string' ? response : JSON.stringify(response || '');
  for (const q of questions) {
    let a = obj && typeof obj[q] === 'string' ? obj[q] : '';
    if (!a) {
      const at = text.indexOf(`"${q}"="`);
      if (at >= 0) {
        const rest = text.slice(at + q.length + 4);
        const end = rest.search(/"(?=, "|\.\s|\.?\s*$)/);
        a = rest.slice(0, end < 0 ? undefined : end);
      }
    }
    if (a && a.trim()) out.push({ question: q, options: opts[q] || [], answer: a.trim(), notes: (notes[q] && notes[q].notes) || '' });
  }
  return out;
}

// ---- matching -------------------------------------------------------------------------------
// English built in; other languages as instance data `stop_words` (decision-register.json)
const STOP = new Set(('the a an to of for and or is are be it this that with on in at by from as not now what which when should ' +
  'shall can will have has your you our we they them their there here into than then does still also only just').split(' '));
for (const w of (() => { try { return JSON.parse(fs.readFileSync(path.join(ROOT, '.claude', 'rules', 'decision-register.json'), 'utf8')).stop_words || []; } catch (e) { return []; } })()) STOP.add(String(w).toLowerCase());
function words(t) {
  // compounds split at hyphens ("19-inch-case"), a crude stem (first 7 letters) so plural and
  // case endings meet ("enclosure"/"enclosures") — the model, not the prefilter, judges meaning
  const all = String(t).toLowerCase().normalize('NFKC').match(/[\p{L}\p{N}]+/gu) || [];
  return [...new Set(all.filter((w) => w.length >= 4 && !STOP.has(w)).map((w) => (w.length > 7 ? w.slice(0, 7) : w)))];
}
function candidates(question, entries, minScore, limit = 3) {
  const docs = entries.map((e) => new Set(words(e.question + ' ' + e.answer)));
  const n = docs.length || 1;
  const df = new Map();
  for (const d of docs) for (const w of d) df.set(w, (df.get(w) || 0) + 1);
  const idf = (w) => Math.log(1 + n / (df.get(w) || 0.5));
  const q = words(question);
  const total = q.reduce((s, w) => s + idf(w), 0) || 1;
  const scored = [];
  docs.forEach((d, i) => {
    const shared = q.filter((w) => d.has(w));
    if (shared.length < 2) return;
    const score = shared.reduce((s, w) => s + idf(w), 0) / total;
    if (score >= minScore) scored.push({ i, score, shared });
  });
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((s) => ({ ...entries[s.i], score: Math.round(s.score * 100) / 100, shared: s.shared }));
}

const INSTRUCTION = `An AI assistant is about to ask its operator a NEW question. Below are EARLIER questions the operator already
answered. For each earlier one decide: does the NEW question ask the operator to decide the SAME matter that the earlier answer
already decided (same thing, same choice - even in other words, other language, or as a "does this still hold?" check)?
NOT the same: a different item or a different choice about a related topic; a follow-up step the earlier answer opened;
an earlier answer that POSTPONED the decision ("later", "remind me", "keep reminding me", "not now", a date) - asking again
is the follow-up the operator asked for;
a recurring check-in whose answer holds only for that moment ("continue autonomously?", "shall I go ahead with the n open
items?", "what next?", "commit this?" for a NEW piece of work) - the same wording is no decided matter;
another item of the same kind (a different fix, PR, part, file) - same only if it is the very same item;
an earlier ANSWER that is no decision (a counter-question, "what do you want to know?", "you decide", a complaint).
An answer picked from OPTIONS also decides the options NOT picked (in a "which do you have / which apply?" question, an
unpicked option is a no). A free-text answer that rejects an option ("too big", "not that") decides against it.
SAME requires all three: (1) the same OBJECT - the very thing the choice is about (a named part, product, file, rule, test);
(2) the earlier answer is a DECISION on that object (a choice, a yes/no, a stated fact about it); (3) THE TEST: the earlier
answer already settles the MAIN choice the NEW question puts to the operator - it picks, rules out or states the option the
NEW question offers again (an option the operator already rejected counts). If the NEW question asks for a further step, an
amount, a variant, a purchase or a timing the earlier answer did not settle, it is NOT the same, however close the topic.
Answer with ONE line of JSON and nothing else: {"same": [{"n": <number>, "object": "<the shared object in 1-4 words, as written in the NEW question>", "choice": "<what the earlier answer decided>", "answers_new": "<the answer to the NEW question that follows from it>"}]}
`;
function ask(body, cfg, model = cfg.model) {
  // a .cjs/.js bin runs under this node (fixtures on every OS; a shell script would not start on Windows)
  const js = /\.c?js$/.test(cfg.bin);
  const r = spawnSync(js ? process.execPath : cfg.bin, [...(js ? [cfg.bin] : []), '-p', '--model', model, '--settings', '{"disableAllHooks": true}'], {
    input: body, encoding: 'utf8', timeout: 45000, cwd: os.tmpdir(),
    env: { ...process.env, DECISION_REGISTER_CHILD: '1' },
  });
  if (process.env.DECISION_REGISTER_TRACE) process.stderr.write(`[model] ${String(r.stdout || '').trim().slice(0, 400)}\n`);
  return r.status === 0 ? r.stdout || '' : null;
}

const optText = (o) => (o && o.length ? `\nOPTIONS: ${o.join(' | ')}` : '');
function judge(question, cands, cfg) {
  const body = `${INSTRUCTION}\nNEW: ${question.slice(0, 1200)}\n\n` +
    cands.map((c, k) => `EARLIER ${k + 1} (${c.date}): ${String(c.question).slice(0, 700)}${optText(c.options)}\nANSWER ${k + 1}: ${String(c.answer).slice(0, 400)}`).join('\n\n');
  const stdout = ask(body, cfg);
  if (stdout === null) return null;
  const m = /\{[\s\S]*\}/.exec(stdout);
  if (!m) return null;
  let same;
  try { same = JSON.parse(m[0]).same; } catch (e) { return null; }
  if (!Array.isArray(same)) return null;
  // the model names the object; it counts only when a word of it stands in BOTH questions (a checkable
  // anchor — an object the model invents for a vague match fails here)
  const out = [];
  for (const s of same) {
    const k = Number(typeof s === 'object' && s ? s.n : s);
    if (!(k >= 1 && k <= cands.length)) continue;
    const obj = words(typeof s === 'object' && s ? s.object || '' : '');
    const c = cands[k - 1];
    const inNew = new Set(words(question)), inOld = new Set(words(c.question + ' ' + c.answer));
    if (obj.some((w) => inNew.has(w) && inOld.has(w))) out.push({ ...c, object: s.object, choice: s.choice || '' });
  }
  return out;
}

function match(question, entries, cfg, useModel = true) {
  if (recurring(question, cfg)) return { cands: [], same: [], recurring: true };
  const cands = candidates(question, entries.filter((e) => !recurring(e.question, cfg)), cfg.minScore);
  if (!cands.length) return { cands: [], same: [] };
  if (!useModel) return { cands, same: [] };
  const same = judge(question, cands, cfg);
  return { cands, same: same || [], unread: same === null };
}

// ---- hooks ----------------------------------------------------------------------------------
const qhash = (s, q) => crypto.createHash('sha256').update(String(s) + '\n' + q).digest('hex').slice(0, 12);
function denied(cfg) { try { return JSON.parse(fs.readFileSync(cfg.state, 'utf8')); } catch (e) { return {}; } }

function post(input, cfg) {
  const qs = (((input.tool_input || {}).questions) || []).map((q) => q.question).filter(Boolean);
  const pairs = answerPairs(qs, input.tool_response, optionsOf((input.tool_input || {}).questions));
  append(cfg.register, pairs.map((p) => ({
    date: new Date().toISOString().slice(0, 10), session: input.session_id || '', cwd: input.cwd || '', ...p,
  })));
}

function pre(input, cfg) {
  if (process.env.DECISION_REGISTER_CHILD) return null;
  const qs = (((input.tool_input || {}).questions) || []).filter((q) => q && q.question)
    .map((q) => q.question + optText((q.options || []).map((o) => o.label).filter(Boolean)));
  const entries = load(cfg.register).filter((e) => e.session !== input.session_id || e.date < new Date().toISOString().slice(0, 10));
  if (!qs.length || !entries.length) return null;
  const seen = denied(cfg);
  const hard = [], soft = [];
  for (const q of qs) {
    const r = match(q, entries, cfg);
    if (r.same.length && !seen[qhash(input.session_id, q)]) hard.push({ q, hits: r.same });
    else if (r.cands.length) soft.push({ q, hits: r.cands });
  }
  const line = (h) => `  - earlier (${h.date}, session ${String(h.session).slice(0, 8)}): "${String(h.question).slice(0, 160)}"\n    answer: "${String(h.answer).slice(0, 200)}"`;
  if (hard.length) {
    for (const h of hard) seen[qhash(input.session_id, h.q)] = new Date().toISOString();
    try { fs.mkdirSync(path.dirname(cfg.state), { recursive: true }); fs.writeFileSync(cfg.state, JSON.stringify(seen)); } catch (e) { /* state never blocks */ }
    const why = hard.map((h) => `"${h.q.slice(0, 140)}"\n${h.hits.map(line).join('\n')}`).join('\n');
    return { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
      permissionDecisionReason: `${MARKER}: the operator already decided this:\n${why}\nAct on the earlier answer, or ask again saying what changed since (the same question re-issued passes).` } };
  }
  if (soft.length) {
    return { hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext:
      `${MARKER}: related earlier answers (not judged the same matter):\n${soft.map((s) => s.hits.map(line).join('\n')).join('\n')}` } };
  }
  return null;
}

// ---- history --------------------------------------------------------------------------------
function transcriptAnswers(file) {
  const out = [], pend = new Map();
  const sid = path.basename(file, '.jsonl');
  for (const l of fs.readFileSync(file, 'utf8').split('\n')) {
    let r; try { r = JSON.parse(l); } catch (e) { continue; }
    const c = r && r.message && Array.isArray(r.message.content) ? r.message.content : [];
    for (const b of c) {
      if (b.type === 'tool_use' && b.name === 'AskUserQuestion') {
        const qo = ((b.input || {}).questions) || [];
        pend.set(b.id, { ts: r.timestamp || '', cwd: r.cwd || '', qs: qo.map((q) => q.question).filter(Boolean), opts: optionsOf(qo) });
      } else if (b.type === 'tool_result' && pend.has(b.tool_use_id)) {
        const p = pend.get(b.tool_use_id); pend.delete(b.tool_use_id);
        const txt = typeof b.content === 'string' ? b.content : JSON.stringify(b.content || '');
        for (const a of answerPairs(p.qs, txt, p.opts)) out.push({ date: p.ts.slice(0, 10), ts: p.ts, session: sid, cwd: p.cwd, ...a });
      }
    }
  }
  return out;
}
function transcripts(dir) {
  const d = dir || path.join(os.homedir(), '.claude', 'projects', ROOT.replace(/[\\/:.]/g, '-'));
  return fs.readdirSync(d).filter((f) => f.endsWith('.jsonl')).map((f) => path.join(d, f));
}

function cli(argv) {
  const cfg = config();
  const arg = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
  const dir = argv.find((a, k) => k > 0 && !a.startsWith('--') && !['--last', '--check'].includes(argv[k - 1]));
  if (argv.includes('--backfill')) {
    const have = new Set(load(cfg.register).map((e) => e.session + '\n' + e.question));
    const add = [];
    for (const f of transcripts(dir)) {
      let rows = []; try { rows = transcriptAnswers(f); } catch (e) { continue; }
      for (const r of rows) { const k = r.session + '\n' + r.question; if (!have.has(k)) { have.add(k); const { ts, ...e } = r; add.push(e); } }
    }
    add.sort((a, b) => (a.date < b.date ? -1 : 1));
    append(cfg.register, add);
    console.log(`backfill: ${add.length} answers added to ${path.relative(ROOT, cfg.register)}`);
    return 0;
  }
  if (argv.includes('--check')) {
    const r = match(arg('--check'), load(cfg.register), cfg, !argv.includes('--no-model'));
    console.log(JSON.stringify({ same: r.same.map((h) => h.question), cands: r.cands.map((h) => [h.score, h.question]) }));
    return r.same.length ? 1 : 0;
  }
  if (argv.includes('--replay')) {
    let all = [];
    for (const f of transcripts(dir)) { try { all = all.concat(transcriptAnswers(f)); } catch (e) { /* skip */ } }
    all.sort((a, b) => (a.ts < b.ts ? -1 : 1));
    const last = Number(arg('--last') || all.length);
    let judged = 0, hits = 0, cand = 0;
    all.forEach((q, i) => {
      if (i < all.length - last) return;
      const earlier = all.slice(0, i).filter((e) => e.session !== q.session);
      const r = match(q.question + optText(q.options), earlier, cfg, !argv.includes('--no-model'));
      if (r.cands.length) cand++;
      if (r.cands.length && !argv.includes('--no-model')) judged++;
      if (r.same.length) {
        hits++;
        console.log(`${q.date} ${q.session.slice(0, 8)} | "${q.question.slice(0, 110)}"\n    = ${r.same[0].date} ${r.same[0].session.slice(0, 8)} "${String(r.same[0].question).slice(0, 110)}" -> "${String(r.same[0].answer).slice(0, 80)}"`);
      }
    });
    console.log(`replay: ${Math.min(last, all.length)} answered questions · with candidates ${cand} · judged ${judged} · same matter ${hits}`);
    return hits ? 1 : 0;
  }
  return 0;
}

module.exports = { answerPairs, candidates, match, words, transcriptAnswers };

if (require.main === module) {
  if (process.argv.slice(2).some((a) => a.startsWith('--'))) process.exit(cli(process.argv.slice(1)));
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { buf += c; });
  process.stdin.on('end', () => {
    try {
      const cfg = config();
      if (!cfg.enabled) process.exit(0);
      const input = JSON.parse(buf);
      if (input.tool_name && input.tool_name !== 'AskUserQuestion') process.exit(0);
      if (input.hook_event_name === 'PostToolUse') { post(input, cfg); process.exit(0); }
      const out = pre(input, cfg);
      if (out) console.log(JSON.stringify(out));
    } catch (e) { /* fails open */ }
    process.exit(0);
  });
}
