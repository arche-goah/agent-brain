#!/usr/bin/env node
/**
 * memory-recall-replay — run the recall hook's PROMPT side over the user prompts already in
 * the transcripts, and say WHICH WORDS made it name each file.
 *
 * WHY (first precision evaluation, 2026-09-30, 25 sessions): precision 0.063 against a
 * target of 0.3. The live log stores only a prompt hash and a hit COUNT, so no one could
 * tell which words fire a wrong naming — tuning stopwords or minHits from it would be a
 * guess. The transcripts hold the prompts; replaying them turns each tuning idea into a
 * measurement in seconds instead of another week of record mode.
 *
 * WHAT: for every transcript (session id = file stem, the same join key as the live log),
 * every genuine user prompt in order — a string message that is not `isMeta` and does not
 * start with `<` (slash commands, local-command caveats, task notifications, hook
 * feedback) — is scored with the hook's own functions (helpers/memory-recall.cjs, same
 * corpus, same config) and the same per-session state (a topic once, file cooldown).
 * Writes one record per prompt that names something, in the live log's shape plus
 * `words` per named file, to --out. Judge it with the existing tool:
 *   memory-usage.py --precision --state <out>
 *
 * FIDELITY is printed, not assumed: for sessions that also have live records, the share of
 * live-named files the replay names too. The replay scores against TODAY's memory, and the
 * live hook saw the memory of its day — a gap there is expected and shows up in this number.
 *
 * The TOOL side is replayed too, in order: every Skill / mcp__ call in the transcript
 * runs the hook's topic mapping (`topics` in the config), a topic once per session.
 *
 * Overrides: --set key=value (numbers: k, minHits, topicK, topicMinHits, cooldownPrompts),
 * --stop word[,word] (added to the stopwords), --no-tool — one run per tuning idea.
 * --truth FILE=REGEX judges a topic index against the sessions that WORKED on the topic
 * (a tool call matching REGEX), for the replay and the live log (see the comment there).
 *
 * Usage: memory-recall-replay.cjs [--root DIR] [--transcripts DIR] [--state LIVE.jsonl]
 *          [--out FILE] [--set k=v]... [--stop w,w] [--no-tool] [--truth F=RX]... [--top N]
 * Read-only on everything but --out. Exit 0; 2 when the transcript dir is missing.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const hook = require('../helpers/memory-recall.cjs');

function args(argv) {
  const a = { set: {}, stop: [], top: 15 };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--root') { a.root = v; i++; } else if (k === '--transcripts') { a.transcripts = v; i++; }
    else if (k === '--state') { a.state = v; i++; } else if (k === '--out') { a.out = v; i++; }
    else if (k === '--top') { a.top = Number(v); i++; }
    else if (k === '--no-tool') { a.noTool = true; }
    else if (k === '--truth') {
      const at = String(v).indexOf('=');
      try { (a.truth = a.truth || []).push({ file: String(v).slice(0, at), rx: new RegExp(String(v).slice(at + 1), 'i') }); } catch (e) { /* bad regex: skipped */ }
      i++;
    }
    else if (k === '--stop') { a.stop.push(...String(v).split(',').filter(Boolean)); i++; }
    else if (k === '--set') { const [key, val] = String(v).split('='); a.set[key] = Number(val); i++; }
  }
  return a;
}

// The session in order: genuine user prompts, and the tool calls the PreToolUse side sees
// (matcher `Skill|mcp__.*`) — a Skill by its skill name, an MCP tool by its tool name.
function events(file) {
  const out = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (!line.includes('"user"') && !line.includes('"tool_use"')) continue;
    let o; try { o = JSON.parse(line); } catch (e) { continue; }
    const c = o.message && o.message.content;
    if (o.type === 'user' && !o.isMeta) {
      if (typeof c === 'string' && c.trim() && !c.trimStart().startsWith('<')) out.push({ prompt: c });
    } else if (o.type === 'assistant' && Array.isArray(c)) {
      for (const b of c) {
        if (!b || b.type !== 'tool_use') continue;
        if (b.name === 'Skill') out.push({ key: 'skills', subject: String((b.input || {}).skill || '') });
        else if (String(b.name).startsWith('mcp__')) out.push({ key: 'tools', subject: String(b.name) });
      }
    }
  }
  return out;
}

function main() {
  const a = args(process.argv.slice(2));
  const root = path.resolve(a.root || process.env.CLAUDE_PROJECT_DIR || process.cwd());
  const memDir = hook.liveDir(root);
  const tdir = a.transcripts || path.dirname(memDir);
  if (!fs.existsSync(tdir)) { console.error(`no transcript directory: ${tdir}`); return 2; }
  const cfg = hook.loadConfig(root);
  for (const [k, v] of Object.entries(a.set)) if (k in cfg && Number.isFinite(v)) cfg[k] = v;
  for (const w of a.stop) cfg.stop.add(w.toLowerCase());
  const docs = hook.loadCorpus(memDir, cfg);
  const out = a.out || path.join(os.tmpdir(), 'memory-recall-replay.jsonl');

  const named = new Map();            // session -> Set(file)
  const words = new Map();            // file -> Map(word -> count)
  const lines = [];
  const topicDocs = new Set(docs.filter((d) => d.topic).map((d) => d.file));
  let nPrompts = 0; let nTools = 0;
  for (const f of fs.readdirSync(tdir).filter((x) => x.endsWith('.jsonl')).sort()) {
    const sid = f.slice(0, -6);
    const state = { n: 0, seen: {}, topics: [] };
    for (const ev of events(path.join(tdir, f))) {
      let topics = []; let files = []; let trigger = 'replay';
      if (ev.prompt !== undefined) {
        nPrompts++;
        if (!hook.scorePrompt(docs, ev.prompt, cfg).length) continue;
        state.n += 1;
        ({ topics, files } = hook.pick(docs, state, cfg));
      } else {
        // tool side, as toolMode: a mapped topic index, once per session
        nTools++;
        if (a.noTool) continue;
        trigger = `replay-${ev.key === 'skills' ? 'skill' : 'tool'}:${ev.subject}`;
        topics = Object.keys(cfg.topics)
          .filter((file) => topicDocs.has(file) && !state.topics.includes(file))
          .filter((file) => (cfg.topics[file][ev.key] || []).some((rx) => rx.test(ev.subject)))
          .map((file) => ({ file, score: 0, hits: 0, words: [trigger.replace(/^replay-/, '')] }));
      }
      if (!topics.length && !files.length) continue;
      for (const d of files) state.seen[d.file] = state.n;
      for (const d of topics) state.topics.push(d.file);
      const rec = (d) => ({ file: d.file, score: +d.score.toFixed(2), hits: d.hits, words: d.words });
      lines.push(JSON.stringify({ session: sid, n: state.n, trigger,
        topics: topics.map(rec), files: files.map(rec) }));
      for (const d of [...topics, ...files]) {
        if (!named.has(sid)) named.set(sid, new Set());
        named.get(sid).add(d.file);
        if (!words.has(d.file)) words.set(d.file, new Map());
        for (const w of d.words) words.get(d.file).set(w, (words.get(d.file).get(w) || 0) + 1);
      }
    }
  }
  fs.writeFileSync(out, lines.join('\n') + (lines.length ? '\n' : ''));

  // fidelity against the live log, where both exist
  const live = new Map();
  const statePath = a.state || path.join(root, '.claude-state', 'memory-recall.jsonl');
  try {
    for (const l of fs.readFileSync(statePath, 'utf8').split('\n')) {
      let r; try { r = JSON.parse(l); } catch (e) { continue; }
      if (r.trigger !== 'prompt') continue;
      for (const it of [...(r.files || []), ...(r.topics || [])]) {
        if (!live.has(r.session)) live.set(r.session, new Set());
        live.get(r.session).add(it.file);
      }
    }
  } catch (e) { /* no live log: fidelity not measurable */ }
  let both = 0; let liveN = 0;
  for (const [sid, set] of live) {
    if (!named.has(sid) && !fs.existsSync(path.join(tdir, `${sid}.jsonl`))) continue;
    for (const f of set) { liveN++; if (named.get(sid) && named.get(sid).has(f)) both++; }
  }

  console.log(`replay: ${nPrompts} prompts, ${nTools} tool calls${a.noTool ? ' (tool side off)' : ''}, ${lines.length} naming records, ${named.size} sessions -> ${out}`);
  console.log(liveN ? `fidelity: ${both} of ${liveN} live namings reproduced (${(both / liveN).toFixed(2)})`
    : 'fidelity: no live records to compare');
  // --truth FILE=REGEX: an injected topic index is never OPENED — being injected is its
  // point — so "named and opened" cannot judge it (measured 2026-09-30: 0.04 under that
  // measure, 0.72 under this one). The truth is whether the session WORKED on the topic:
  // any tool call whose name or input matches REGEX. Judges the replay and the live log.
  for (const t of a.truth || []) {
    const work = new Set(); const all = new Set();
    for (const f of fs.readdirSync(tdir).filter((x) => x.endsWith('.jsonl'))) {
      const sid = f.slice(0, -6); all.add(sid);
      for (const line of fs.readFileSync(path.join(tdir, f), 'utf8').split('\n')) {
        if (!line.includes('"tool_use"')) continue;
        let o; try { o = JSON.parse(line); } catch (e) { continue; }
        const c = (o.message && o.message.content) || [];
        if (Array.isArray(c) && c.some((b) => b && b.type === 'tool_use' && t.rx.test(`${b.name} ${JSON.stringify(b.input || {})}`))) { work.add(sid); break; }
      }
    }
    // scope: sessions the record covers (the live log starts later than the transcripts)
    const judge = (recs, scope) => {
      const s = new Set(recs.filter((r) => scope.has(r.session) && (r.topics || []).some((x) => x.file === t.file)).map((r) => r.session));
      const w = [...work].filter((x) => scope.has(x));
      const tp = [...s].filter((x) => work.has(x)).length;
      return `named ${s.size}, precision ${s.size ? (tp / s.size).toFixed(2) : '-'}, recall ${w.length ? (tp / w.length).toFixed(2) : '-'} (${scope.size} sessions)`;
    };
    const liveRecs = [];
    try { for (const l of fs.readFileSync(statePath, 'utf8').split('\n')) { try { liveRecs.push(JSON.parse(l)); } catch (e) { /* skip */ } } } catch (e) { /* none */ }
    const liveScope = new Set(liveRecs.map((r) => r.session).filter((x) => all.has(x)));
    console.log(`truth ${t.file}: ${work.size} of ${all.size} sessions worked on it`);
    console.log(`  replay ${judge(lines.map((l) => JSON.parse(l)), all)}`);
    console.log(`  live   ${judge(liveRecs, liveScope)}`);
  }
  const byCount = [...words].map(([f, m]) => [f, [...m.values()].reduce((x, y) => x + y, 0), m])
    .sort((x, y) => y[1] - x[1]).slice(0, a.top);
  for (const [f, n, m] of byCount) {
    const top = [...m].sort((x, y) => y[1] - x[1]).slice(0, 6).map(([w, c]) => `${w} ${c}`).join(', ');
    console.log(`  ${String(n).padStart(4)}  ${f}  <- ${top}`);
  }
  return 0;
}

process.exitCode = main();
