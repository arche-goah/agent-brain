#!/usr/bin/env node
/**
 * UserPromptSubmit: a prompt that touches a topic gets EVERY source file of that topic listed, so a
 * summary, a total or a question to the operator is never built from a subset.
 *
 * The class (operator, 2026-11-11, translated): "you have to read all relevant areas if you want to
 * give me a summary". The day's case: "four shopping files are open, right? shop count and rough net
 * total?" was answered from one project's files; the overview of the same folder (a DMX node, a cable
 * kit) was never opened, and the total came out at a sixth of the real one. Nothing named the full
 * set of sources at the moment the summary was asked for. A first fix listed the shopping folder
 * only; the operator: "tailor-made, ONLY for a purchase decision". The topic is data here.
 *
 * Instance data `.claude/rules/topic-sources.json`:
 *   {"topics": [{"name": "shopping", "prompt_patterns": ["shopping", "\\bshops?\\b"],
 *                "sources": ["docs/business/shopping-list.md", "docs/business/shopping"],
 *                "also": "purchase decisions in the project ledgers"}]}
 * A source is a file or a folder (listed recursively, text files only). Several topics may hit.
 * The decision register (helpers/decision-register.cjs) is named with every hit: earlier answers on
 * the topic are a source too. Fails silent. Fixture: scripts/test-topic-sources.sh.
 */
const fs = require('fs');
const path = require('path');

const { isNotification, isPeerMessage } = require('./turn-kind.cjs');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const PEER = /^\s*<cross-session-message\b/;
const TEXT = /\.(md|txt|json|jsonl|csv|ya?ml)$/i;

function walk(rel, out, depth = 0) {
  const abs = path.join(ROOT, rel);
  let st; try { st = fs.statSync(abs); } catch (e) { return out; }
  if (st.isFile()) { if (TEXT.test(rel)) out.push(rel.split(path.sep).join('/')); return out; }
  if (depth > 6) return out;
  for (const f of fs.readdirSync(abs).sort()) if (!f.startsWith('.')) walk(path.join(rel, f), out, depth + 1);
  return out;
}

function hits(prompt, topics) {
  return topics.filter((t) => (t.prompt_patterns || []).some((p) => { try { return new RegExp(p, 'iu').test(prompt); } catch (e) { return false; } }));
}

function render(prompt, d) {
  const hit = hits(prompt, d.topics || []);
  if (!hit.length) return '';
  const reg = d.register || 'docs/maintenance/decision-register.jsonl';
  return hit.map((t) => {
    const files = [...new Set((t.sources || []).flatMap((s) => walk(s, [])))];
    return `<topic-sources topic="${t.name}" trust="local-data" instructions="never">\n` +
      `A summary, total or question to the operator on "${t.name}" reads EVERY source below first (no subset)` +
      `${t.also ? `, plus ${t.also}` : ''}, and the earlier answers in ${reg} (grep the topic) — a recorded answer is not asked again.\n` +
      files.map((f) => `- ${f}`).join('\n') + '\n</topic-sources>';
  }).join('\n');
}

module.exports = { hits, render, walk };

if (require.main === module) {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { buf += c; });
  process.stdin.on('end', () => {
    try {
      const d = JSON.parse(fs.readFileSync(path.join(ROOT, '.claude', 'rules', 'topic-sources.json'), 'utf8'));
      const input = JSON.parse(buf);
      const prompt = input.prompt || '';
      // a notification, a Stop-hook echo or another session's message is no operator prompt (measured
      // 2026-11-11, macOS instance: the alpha fired three times on peer messages naming the topic)
      if (isNotification(prompt) || isPeerMessage(input) || PEER.test(prompt)) process.exit(0);
      const out = render(prompt, d);
      if (out) console.log(out);
    } catch (e) { /* no data, no output */ }
    process.exit(0);
  });
}
