#!/usr/bin/env node
/**
 * Stop check: the reply to the operator is in the instance's declared chat language.
 *
 * Why: a Windows instance (alpha since 2026-11-09) answered its German-speaking operator in English several replies in a
 * row - the language rule stood in CLAUDE.md, the feedback rules and the harness language setting, and nothing caught
 * an English reply before the turn ended. Replay over that instance's November transcripts (2026-11-25): 492 replies,
 * 2 flagged, both truly English, 0 false alarms.
 *
 * Data: `.claude/rules/reply-language.json` `{"language": "<ISO 639-1>", "words": [...]}` - `words` are unambiguous
 * function words of the declared language (none that also exist in English). The core ships the English list only
 * (public repos are English-only); the instance brings its own words, like every other gate's language data.
 * Missing file, missing field, "en" or no `words`: the check does nothing.
 *
 * Read: the text of every reply part since the operator's last real message (a Stop feedback starts a new count),
 * without code blocks, inline code, links, paths, quoted strings, blockquote lines and command output
 * (`<bash-stdout>`, `<bash-stderr>`). Counted: unambiguous English function words against unambiguous function words
 * of the declared language. English = at least 12 English ones and more English than declared ones.
 *
 * Modes: Stop hook (stdin = hook input) · `--record` (writes the verdict to .claude-state/reply-language.jsonl, never
 * blocks) · `--replay <transcript dir>` (judges every main-thread reply, prints count and the flagged ones, so a
 * brain measures its false alarms before it switches the check on) · `--selftest`.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { exit } = require('./hook-exit.cjs');   // not process.exit: it hung at Node shutdown (2026-11-23)

const EN = ('the and with from this that which is are were be been have has would should could not but you your ' +
  "it's i'll i'm they their there here what when where how why of to for on at by or if then than into only just about " +
  'after before because all any each every these those my we our now still already').split(' ');
const MIN_EN = 12;

function config(root) {
  try {
    const d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'reply-language.json'), 'utf8'));
    const lang = String(d.language || '').toLowerCase();
    if (!lang || lang === 'en' || !Array.isArray(d.words) || !d.words.length) return null;
    return { lang, words: new Set(d.words.map((w) => String(w).toLowerCase())) };
  } catch (e) { return null; }
}

function textOf(entry) {
  const c = entry && entry.message && entry.message.content;
  if (typeof c === 'string') return [c];
  return Array.isArray(c) ? c.filter((b) => b && b.type === 'text').map((b) => b.text) : [];
}

function operatorPrompt(entry) {
  if (!entry || entry.type !== 'user' || entry.isSidechain) return false;
  const t = textOf(entry);
  if (!t.length) return false; // a tool result
  return !/<task-notification>|SYSTEM NOTIFICATION|^Stop hook feedback|^\s*<system-reminder>/.test(t.join('\n'));
}

function stopFeedback(entry) {
  return !!entry && entry.type === 'user' && /^Stop hook feedback/.test(textOf(entry).join('\n'));
}

function replyText(lines) {
  const parts = [];
  for (let i = lines.length - 1; i >= 0; i--) {
    let e;
    try { e = JSON.parse(lines[i]); } catch (err) { continue; }
    if (operatorPrompt(e) || stopFeedback(e)) break;
    if (e.type === 'assistant' && !e.isSidechain) parts.unshift(...textOf(e));
  }
  return parts.join('\n');
}

function count(text, declared) {
  const clean = String(text)
    .replace(/<bash-(stdout|stderr)>[\s\S]*?<\/bash-\1>/g, ' ')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/^\s*>.*$/gm, ' ')
    .replace(/\]\([^)]*\)/g, ']')
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/[A-Za-z]:[\\/][^\s]*/g, ' ')
    .replace(/(?:^|\s)\/[\w.-]+(?:\/[\w.-]+)+/g, ' ')
    .replace(/"[^"\n]{0,200}"/g, ' ');
  const en = new Set(EN);
  let e = 0;
  let d = 0;
  for (const w of clean.toLowerCase().match(/[\p{L}']+/gu) || []) {
    if (declared.has(w)) d++;
    else if (en.has(w)) e++;
  }
  return { en: e, declared: d };
}

function judge(text, cfg) {
  const r = count(text, cfg.words);
  return { ...r, english: r.en >= MIN_EN && r.en > r.declared };
}

function replay(dir, cfg) {
  let replies = 0;
  const hits = [];
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.jsonl'))) {
    let cur = [];
    const flush = () => {
      if (cur.length) { replies++; const t = cur.join('\n'); if (judge(t, cfg).english) hits.push(`${f.slice(0, 8)} | ${t.slice(0, 140).replace(/\s+/g, ' ')}`); }
      cur = [];
    };
    for (const line of fs.readFileSync(path.join(dir, f), 'utf8').split('\n')) {
      let e;
      try { e = JSON.parse(line); } catch (err) { continue; }
      if (operatorPrompt(e) || stopFeedback(e)) flush();
      else if (e.type === 'assistant' && !e.isSidechain) cur.push(...textOf(e));
    }
    flush();
  }
  console.log(`reply-language replay (${cfg.lang}): ${replies} replies, ${hits.length} flagged`);
  for (const h of hits) console.log('  ' + h);
}

function selftest() {
  const assert = require('assert');
  // A made-up declared language "zz" with its own function words - the core ships no other language's words.
  const zzWords = ['kaz', 'lom', 'miv', 'nup', 'pek', 'riv', 'tov', 'wex', 'yul', 'zon'];
  const zz = { lang: 'zz', words: new Set(zzWords) };
  const zzText = 'Build kaz green lom tests miv nup pek, riv tov wex yul zon kaz lom miv, nup pek riv tov.';
  const en = 'I checked the build and it is green. The tests pass, but there are still two things that we should look at ' +
    'before we merge, because the lint step was not run on this machine and the docs are out of date now.';
  assert(judge(en, zz).english, 'an English reply is flagged');
  assert(!judge(zzText, zz).english, 'a reply in the declared language passes');
  assert(!judge('kaz lom:\n```\n' + en + '\n```\nmiv nup pek.', zz).english, 'code block excluded');
  assert(!judge('kaz:\n<bash-stdout>' + en + '</bash-stdout>\nlom miv.', zz).english, 'command output excluded');
  assert(!judge('kaz lom:\n> ' + en + '\nmiv nup.', zz).english, 'blockquote excluded');
  assert(!judge('Build green, tests green, two points open.', zz).english, 'a terse reply below the threshold passes');
  const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'rlg-'));
  assert.strictEqual(config(tmp), null, 'no file: off');
  fs.mkdirSync(path.join(tmp, '.claude', 'rules'), { recursive: true });
  fs.writeFileSync(path.join(tmp, '.claude', 'rules', 'reply-language.json'), '{"language": "en"}');
  assert.strictEqual(config(tmp), null, 'English declared: off');
  fs.writeFileSync(path.join(tmp, '.claude', 'rules', 'reply-language.json'), '{"language": "zz"}');
  assert.strictEqual(config(tmp), null, 'a language without its words: off');
  fs.writeFileSync(path.join(tmp, '.claude', 'rules', 'reply-language.json'), JSON.stringify({ language: 'zz', words: zzWords }));
  assert(config(tmp) && config(tmp).lang === 'zz', 'a language with its words: on');
  const lines = [JSON.stringify({ type: 'user', message: { content: 'question' } }),
    JSON.stringify({ type: 'assistant', message: { content: [{ type: 'text', text: en }] } }),
    JSON.stringify({ type: 'user', message: { content: 'Stop hook feedback: LANGUAGE' } }),
    JSON.stringify({ type: 'assistant', message: { content: [{ type: 'text', text: zzText }] } })];
  assert(!judge(replyText(lines), zz).english, 'a Stop feedback starts a new count');
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log('reply-language-gate selftest: 11 ok');
}

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.includes('--selftest')) { selftest(); exit(0); }
  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const cfg = config(root);
  if (args[0] === '--replay') {
    if (!cfg) { console.log('reply-language: no declared language with words in .claude/rules/reply-language.json - nothing to judge'); exit(0); }
    replay(args[1], cfg);
    exit(0);
  }
  let raw = '';
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    if (!cfg) exit(0);
    let input = {};
    try { input = JSON.parse(raw || '{}'); } catch (e) { exit(0); }
    if (!input.transcript_path || !fs.existsSync(input.transcript_path)) exit(0);
    const r = judge(replyText(fs.readFileSync(input.transcript_path, 'utf8').split('\n').filter(Boolean)), cfg);
    if (args.includes('--record')) {
      try {
        const dir = path.join(root, '.claude-state');
        fs.mkdirSync(dir, { recursive: true });
        fs.appendFileSync(path.join(dir, 'reply-language.jsonl'), JSON.stringify({ at: new Date().toISOString(), lang: cfg.lang, ...r }) + '\n');
      } catch (e) { /* a recorder never fails the turn */ }
      exit(0);
    }
    if (r.english) {
      console.log(JSON.stringify({ decision: 'block', reason: `REPLY-LANGUAGE-GATE: the reply is English (${r.en} English, ` +
        `${r.declared} ${cfg.lang} function words); this instance declares "${cfg.lang}" (.claude/rules/reply-language.json). ` +
        'Write the reply again in that language.' }));
    }
    exit(0);
  });
}

module.exports = { judge, replyText, count, config };
