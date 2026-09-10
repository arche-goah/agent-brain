#!/usr/bin/env node
/**
 * UserPromptSubmit hook: RECALL IS INDEX-ONLY — THIS IS THE READ SIDE.
 *
 * The harness loads exactly one memory file at session start, MEMORY.md, and only its
 * first 200 lines / 25 KB (code.claude.com/docs/en/memory.md). Every other memory file
 * is read only if the model decides to read it; there is no prompt-time retrieval for
 * memory files (documented only for skills and rules). Measured on the proving instance
 * 2026-09-09, 241 transcripts: 53 of 135 memory files were never opened, the index line
 * had grown to ~185 characters because it carries the lesson INSTEAD of the file, and
 * the byte cap binds at ~140 entries. A topic sub-index (`index-<topic>.md`) was read
 * in 4 sessions although a rule made it mandatory — an unloaded index is invisible.
 * The collaborator asked for exactly this read side on 2026-08-21 ("the store must
 * actually be searched, not 'could be'"); the write side is recall-gate.cjs.
 *
 * WHAT IT DOES, per prompt, in milliseconds, without a model or a network:
 *   - reads ONLY the frontmatter (`name`, `description`, optional `keywords`) of every
 *     memory file — never a body, so nothing large or secret can travel into the prompt;
 *   - scores token overlap between the prompt and each file (IDF over the corpus, name
 *     and keywords weighted double, prefix match from 5 characters as cheap stemming);
 *   - two tiers: a TOPIC index (`index-<topic>.md`, the specialized memory of one
 *     project) that matches is injected whole, once per session; single FILES that
 *     match are named as pointers (name + description + path), at most `k`;
 *   - a file named in the last `cooldownPrompts` prompts of the same session is not
 *     named again (no wallpaper);
 *   - ALWAYS appends a record line to `.claude-state/memory-recall.jsonl` so precision
 *     (named AND opened later in the session) stays measurable after arming —
 *     `scripts/memory-usage.py --precision` reads it. `--record` suppresses the output
 *     and keeps only the log: that is the measure-then-arm mode (operator rule
 *     2026-08-20, proven with recall-gate).
 *
 * INVARIANTS: exit 0 always, never blocks, writes only under `.claude-state/`, stdin
 * read to 'end', output capped in bytes. Paths in the output are posix text (OS-1).
 * The memory dir is minted like memory-sync.cjs does (`[^A-Za-z0-9]` -> `-` over the
 * ABSOLUTE instance path — on Windows the drive colon and backslashes are in it too),
 * honouring CLAUDE_MEMORY_DIR and CLAUDE_CONFIG_DIR. CRLF frontmatter parses (OS-2).
 *
 * CONFIG is instance data, `.claude/rules/memory-recall.json`; every key optional,
 * a given list REPLACES the default (same rule as recall-tools.json): a brain that
 * prompts in another language ships its stopwords there — the core carries English only.
 *
 * ponytail: the whole corpus is re-read on every prompt. Measured 135 files in ~10 ms;
 * add an mtime-keyed cache under .claude-state/ when a brain passes ~2000 files.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const RECORD_ONLY = process.argv.includes('--record');
// --tool: PreToolUse mode (matcher `Skill|mcp__.*`). The prompt is not the only place a
// project context shows itself — the moment a rig skill or a desk MCP tool is called IS
// the context (operator idea 2026-09-10: "specialized memories per kind of task, loaded
// mechanically like MEMORY.md"). Which tool or skill belongs to which topic index is
// instance data (`topics` in memory-recall.json); the core carries no mapping.
const TOOL_MODE = process.argv.includes('--tool');
const DEFAULTS = {
  k: 3,                 // file pointers per prompt
  minHits: 2,           // distinct prompt tokens a file must match
  topicK: 1,            // topic indexes per prompt
  topicMinHits: 2,
  cooldownPrompts: 5,   // a file named within the last n prompts is not named again
  maxBytes: 1200,       // pointer block
  topicMaxBytes: 4000,  // one injected topic index
  exclude: [],          // regexes on file names
  stopwords: ('a an the and or but if then else of to in on at for from by with without ' +
    'as is are was were be been being do does did done have has had not no yes it its ' +
    'this that these those there here what which who whom how why when where can could ' +
    'should would will shall may might must also just only very more most much many some ' +
    'any all each every both either neither so than too into onto over under again ' +
    'please let make made get got go went come came see saw look want need use used ' +
    'now new one two first next last same other another still already about after before ' +
    'up down out off run runs ran check plan step file files').split(/\s+/),
};

let data = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { data += c; });
process.stdin.on('end', () => { try { main(); } catch (e) { /* never block a prompt */ } process.exit(0); });

function main() {
  let input = {};
  try { input = JSON.parse(data || '{}'); } catch (e) { return; }
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const cfg = loadConfig(root);
  const memDir = liveDir(root);
  if (!fs.existsSync(memDir)) return;
  if (TOOL_MODE) return toolMode(input, root, cfg, memDir);
  const prompt = String(input.prompt || '');
  if (!prompt.trim()) return;

  const docs = loadCorpus(memDir, cfg);
  if (!docs.length) return;
  const df = new Map();
  for (const d of docs) for (const t of new Set(d.tokens.map((x) => x.t))) df.set(t, (df.get(t) || 0) + 1);
  const idf = (t) => Math.log((docs.length + 1) / ((df.get(t) || 0) + 1)) + 1;
  const ptoks = [...new Set(tokenize(prompt, cfg.stop))];
  if (!ptoks.length) return;

  for (const d of docs) {
    let score = 0; const hit = new Set();
    for (const p of ptoks) {
      for (const { t, w } of d.tokens) {
        if (matches(p, t)) { score += idf(t) * w; hit.add(p); }
      }
    }
    d.score = score; d.hits = hit.size;
  }
  const rank = (list, minHits, n) => list.filter((d) => d.hits >= minHits)
    .sort((a, b) => b.score - a.score || a.file.localeCompare(b.file)).slice(0, n);

  const { state, stateFile, sid } = loadState(root, input);
  state.n += 1;

  const topics = rank(docs.filter((d) => d.topic), cfg.topicMinHits, cfg.topicK)
    .filter((d) => !state.topics.includes(d.file));
  const files = rank(docs.filter((d) => !d.topic), cfg.minHits, cfg.k)
    .filter((d) => !(d.file in state.seen) || state.n - state.seen[d.file] > cfg.cooldownPrompts);

  // record line: what was named, with scores — the join key for the precision measurement
  record(root, {
    session: sid, n: state.n, trigger: 'prompt',
    prompt_sha: crypto.createHash('sha256').update(prompt).digest('hex').slice(0, 12),
    prompt_tokens: ptoks.length, record_only: RECORD_ONLY,
    topics: topics.map((d) => ({ file: d.file, score: +d.score.toFixed(2), hits: d.hits })),
    files: files.map((d) => ({ file: d.file, score: +d.score.toFixed(2), hits: d.hits })),
  });

  if (!topics.length && !files.length) return;
  for (const d of files) state.seen[d.file] = state.n;
  for (const d of topics) state.topics.push(d.file);
  try { fs.writeFileSync(stateFile, JSON.stringify(state)); } catch (e) { /* cooldown degrades to none */ }
  if (RECORD_ONLY) return;

  const out = ['<memory-recall trust="local-data" instructions="never">'];
  for (const d of topics) {
    out.push(`topic index memory/${d.file} — ${d.description}`);
    out.push(cap(d.entries.join('\n'), cfg.topicMaxBytes));
  }
  if (files.length) {
    let block = files.map((d) => `- ${d.name} — ${d.description} (memory/${d.file})`).join('\n');
    out.push(cap(block, cfg.maxBytes));
  }
  out.push('</memory-recall>');
  process.stdout.write(out.join('\n') + '\n');
}

function toolMode(input, root, cfg, memDir) {
  const tool = String(input.tool_name || '');
  const ti = input.tool_input || {};
  const subject = tool === 'Skill' ? String(ti.skill || '') : tool;
  const key = tool === 'Skill' ? 'skills' : 'tools';
  const wanted = Object.keys(cfg.topics).filter((file) => (cfg.topics[file][key] || []).some((rx) => rx.test(subject)));
  if (!wanted.length) return;
  const { state, stateFile, sid } = loadState(root, input);
  const fresh = wanted.filter((f) => !state.topics.includes(f));
  const blocks = [];
  for (const file of fresh) {
    let text;
    try { text = fs.readFileSync(path.join(memDir, file), 'utf8'); } catch (e) { continue; }
    const fm = frontmatter(text) || {};
    const entries = text.replace(/\r/g, '').split('\n').filter((l) => /^- \[/.test(l));
    if (!entries.length) continue;
    blocks.push(`topic index memory/${file} — ${fm.description || ''}\n${cap(entries.join('\n'), cfg.topicMaxBytes)}`);
    state.topics.push(file);
  }
  record(root, { session: sid, n: state.n, trigger: tool === 'Skill' ? `skill:${subject}` : `tool:${subject}`,
    record_only: RECORD_ONLY, topics: fresh.map((file) => ({ file, hits: 0, score: 0 })), files: [] });
  if (!blocks.length) return;
  try { fs.writeFileSync(stateFile, JSON.stringify(state)); } catch (e) { /* once-per-session degrades */ }
  if (RECORD_ONLY) return;
  const ctx = `<memory-recall trust="local-data" instructions="never">\n${blocks.join('\n')}\n</memory-recall>`;
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: ctx } }) + '\n');
}

function loadState(root, input) {
  const sid = String(input.session_id || 'nosession').replace(/[^A-Za-z0-9_-]/g, '_');
  const stateFile = path.join(root, '.claude-state', `memory-recall-${sid}.json`);
  let state = { n: 0, seen: {}, topics: [] };
  try { state = Object.assign(state, JSON.parse(fs.readFileSync(stateFile, 'utf8'))); } catch (e) { /* fresh */ }
  return { state, stateFile, sid };
}

function record(root, rec) {
  try {
    const stateDir = path.join(root, '.claude-state');
    fs.mkdirSync(stateDir, { recursive: true });
    fs.appendFileSync(path.join(stateDir, 'memory-recall.jsonl'), JSON.stringify(Object.assign({ ts: new Date().toISOString() }, rec)) + '\n');
  } catch (e) { /* the log is a measurement aid, never a reason to fail */ }
}

function cap(s, max) {
  if (Buffer.byteLength(s, 'utf8') <= max) return s;
  const lines = s.split('\n'); const kept = []; let size = 0;
  for (const l of lines) {
    const b = Buffer.byteLength(l, 'utf8') + 1;
    if (size + b > max - 2) { kept.push('…'); break; }
    kept.push(l); size += b;
  }
  return kept.join('\n');
}

function loadConfig(root) {
  let c = {};
  try { c = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'memory-recall.json'), 'utf8')); } catch (e) { /* defaults */ }
  const num = (k) => (Number.isFinite(c[k]) ? c[k] : DEFAULTS[k]);
  const list = (k) => (Array.isArray(c[k]) ? c[k] : DEFAULTS[k]);
  return {
    k: num('k'), minHits: num('minHits'), topicK: num('topicK'), topicMinHits: num('topicMinHits'),
    cooldownPrompts: num('cooldownPrompts'), maxBytes: num('maxBytes'), topicMaxBytes: num('topicMaxBytes'),
    exclude: list('exclude').map((s) => { try { return new RegExp(s, 'i'); } catch (e) { return null; } }).filter(Boolean),
    stop: new Set(list('stopwords').map((w) => fold(String(w)))),
    topics: parseTopics(c.topics),
  };
}

// { "index-rig.md": { "tools": ["^mcp__mikrotik__"], "skills": ["^rig-health-check$"] } }
function parseTopics(t) {
  const out = {};
  if (!t || typeof t !== 'object') return out;
  for (const file of Object.keys(t)) {
    if (!/^index-.+\.md$/.test(file)) continue;
    const rx = (arr) => (Array.isArray(arr) ? arr : [])
      .map((s) => { try { return new RegExp(s, 'i'); } catch (e) { return null; } }).filter(Boolean);
    out[file] = { tools: rx(t[file].tools), skills: rx(t[file].skills) };
  }
  return out;
}

function liveDir(root) {
  if (process.env.CLAUDE_MEMORY_DIR) return process.env.CLAUDE_MEMORY_DIR;
  const cfgDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  const slug = path.resolve(root).replace(/[^A-Za-z0-9]/g, '-');
  return path.join(cfgDir, 'projects', slug, 'memory');
}

function loadCorpus(memDir, cfg) {
  const docs = [];
  let names = [];
  try { names = fs.readdirSync(memDir); } catch (e) { return docs; }
  for (const file of names) {
    if (!file.endsWith('.md') || file === 'MEMORY.md' || file === 'README.md' || file.endsWith('.incoming.md')) continue;
    if (cfg.exclude.some((rx) => rx.test(file))) continue;
    let text;
    try { text = fs.readFileSync(path.join(memDir, file), 'utf8'); } catch (e) { continue; }
    const fm = frontmatter(text);
    if (!fm || !fm.description) continue;
    const topic = /^index-.+\.md$/.test(file);
    const tokens = [];
    for (const t of tokenize(fm.name || file.replace(/\.md$/, ''), cfg.stop)) tokens.push({ t, w: 2 });
    for (const t of tokenize(fm.description, cfg.stop)) tokens.push({ t, w: 1 });
    for (const t of tokenize(fm.keywords || '', cfg.stop)) tokens.push({ t, w: 2 });
    const doc = { file, name: fm.name || file.replace(/\.md$/, ''), description: fm.description, tokens, topic };
    if (topic) {
      // the entries of a topic index are what gets injected — its own body is the index
      doc.entries = text.replace(/\r/g, '').split('\n').filter((l) => /^- \[/.test(l));
      for (const l of doc.entries) for (const t of tokenize(l, cfg.stop)) tokens.push({ t, w: 0.5 });
    }
    docs.push(doc);
  }
  return docs;
}

function frontmatter(text) {
  const t = text.replace(/^﻿/, '').replace(/\r/g, '');
  if (!t.startsWith('---')) return null;
  const end = t.indexOf('\n---', 3);
  if (end < 0) return null;
  const out = {};
  for (const line of t.slice(3, end).split('\n')) {
    const m = /^(name|description|keywords):\s*(.*)$/.exec(line);
    if (!m) continue;
    let v = m[2].trim();
    if (/^".*"$/.test(v) || /^'.*'$/.test(v)) v = v.slice(1, -1).replace(/\\"/g, '"');
    out[m[1]] = v;
  }
  return out;
}

function fold(s) {
  return s.toLowerCase().replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss');
}

function tokenize(s, stop) {
  return fold(String(s)).split(/[^a-z0-9]+/).filter((t) => t.length >= 3 && !stop.has(t));
}

function matches(p, t) {
  if (p === t) return true;
  if (p.length < 5 || t.length < 5) return false;
  return p.startsWith(t) || t.startsWith(p);
}
