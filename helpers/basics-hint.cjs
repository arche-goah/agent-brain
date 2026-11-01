#!/usr/bin/env node
/**
 * UserPromptSubmit hook: teach a basic of working with a brain at the moment it is needed.
 *
 * WHY (operator, 2026-10-31, translated): "how do we teach basics like 'session close' to someone
 * new — it should be learned and confirmed in the first sessions". A list in a README is read once
 * and forgotten; a sentence at the moment the operator is about to need it is not. So: when the
 * operator's prompt matches a basic's trigger and the basic is not learned yet, the AI is asked to
 * say its one sentence. At most ONE new basic per session. "Learned" = the transcript shows the
 * operator used it once (its proof); from then on it is silent for good.
 *
 * Data: `basics.json` at the core root (English triggers); the instance adds triggers in its own
 * language and basics of its own in `.claude/rules/basics.json` ({"triggers": {"<id>": [...]},
 * "basics": [...]}). State per brain: `.claude-state/basics.json` ({learned: {id: date},
 * shown: {session: id}}). A brain that already has history (EXISTING_MIN past transcripts) starts
 * with every basic learned — its operator knows them. Fails open: any error = no output.
 * Fixture: scripts/test-basics-hint.sh.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const EXISTING_MIN = 5;
const NOT_A_PROMPT = /^\s*(<task-notification|<system-reminder|<cross-session-message|<local-command|Stop hook feedback|\[Request interrupted)/;

function readJson(p, d) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return d; } }

function regexes(list) {
  const out = [];
  for (const s of list || []) { try { out.push(new RegExp(s, 'i')); } catch (e) { /* skip */ } }
  return out;
}

/** The basics: core list, instance triggers merged in, instance basics appended. */
function loadBasics(root) {
  const core = readJson(path.join(__dirname, '..', 'basics.json'), {}).basics || [];
  const inst = readJson(path.join(root, '.claude', 'rules', 'basics.json'), {});
  const extra = (inst && inst.triggers) || {};
  return core.concat((inst && inst.basics) || []).filter((b) => b && b.id && b.say).map((b) => ({
    ...b, trig: regexes([].concat(b.trigger || [], extra[b.id] || [])),
  }));
}

/** The operator's prompts and the session's tool calls (proofs count only there — a start report
 *  or a skill text that NAMES a command is no use of it). */
function transcript(tp) {
  let lines = [];
  try { lines = fs.readFileSync(tp, 'utf8').split('\n'); } catch (e) { return { prompts: [], tools: '' }; }
  const prompts = []; const tools = [];
  for (const l of lines) {
    if (!l.includes('"user"') && !l.includes('tool_use')) continue;
    let d; try { d = JSON.parse(l); } catch (e) { continue; }
    const m = d && d.message;
    if (m && m.role === 'assistant' && Array.isArray(m.content)) {
      for (const b of m.content) if (b && b.type === 'tool_use') tools.push(JSON.stringify(b.input || {}));
      continue;
    }
    if (!m || m.role !== 'user' || d.isMeta) continue;
    const c = m.content;
    const t = typeof c === 'string' ? c
      : Array.isArray(c) && !c.some((b) => b && b.type === 'tool_result') ? c.map((b) => (b && b.text) || '').join('\n') : '';
    if (t && !NOT_A_PROMPT.test(t)) prompts.push(t);
  }
  return { prompts, tools: tools.join('\n') };
}

function judge(input, now) {
  const root = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
  const sid = input.session_id || '';
  const prompt = String(input.prompt || '');
  const basics = loadBasics(root);
  if (!basics.length) return null;
  const sp = path.join(root, '.claude-state', 'basics.json');
  let st = readJson(sp, null);
  const day = (now || new Date()).toISOString().slice(0, 10);
  if (!st || typeof st !== 'object') {
    st = { learned: {}, shown: {} };
    // A brain with history: its operator already works with it — every basic counts as learned.
    let past = 0;
    try {
      if (input.transcript_path) {
        const dir = path.dirname(input.transcript_path);
        past = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl') && f !== path.basename(input.transcript_path)).length;
      }
    } catch (e) { past = 0; }
    if (past >= EXISTING_MIN) for (const b of basics) st.learned[b.id] = `existing brain (${day})`;
  }
  st.learned = st.learned || {}; st.shown = st.shown || {};
  // Proofs: a basic the operator has used is learned, for good.
  const open = basics.filter((b) => !st.learned[b.id]);
  if (open.length && input.transcript_path) {
    const t = transcript(input.transcript_path);
    const prompts = t.prompts.concat(prompt).join('\n');
    for (const b of open) {
      let re; try { re = new RegExp(b.proof || '(?!)', 'i'); } catch (e) { continue; }
      // "both" (Windows review of #257, 2026-11-01): a skill can be used as a tool call OR typed as a slash
      // command, which the transcript records as a prompt `<command-name>/<plugin>:<skill></command-name>`.
      const hay = b.proof_in === 'prompt' ? prompts : b.proof_in === 'both' ? `${t.tools}\n${prompts}` : t.tools;
      if (re.test(hay)) st.learned[b.id] = day;
    }
  }
  let out = null;
  if (!st.shown[sid]) {
    const b = basics.find((x) => !st.learned[x.id] && x.trig.some((r) => r.test(prompt)));
    if (b) {
      st.shown[sid] = b.id;
      out = `<basics-hint id="${b.id}">The operator's message touches a basic of working with this brain they have not used yet. `
        + 'At the end of your reply, tell them in ONE sentence, in their language, without a heading: '
        + `${b.say}</basics-hint>`;
    }
  }
  try { fs.mkdirSync(path.dirname(sp), { recursive: true }); fs.writeFileSync(sp, JSON.stringify(st, null, 1) + '\n'); } catch (e) { /* read-only: still answer */ }
  return out;
}

if (require.main === module) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { raw += c; });
  process.stdin.on('end', () => {
    let out = null;
    try { out = judge(JSON.parse(raw)); } catch (e) { out = null; }
    if (out) process.stdout.write(out + '\n');
    process.exit(0);
  });
}

module.exports = { judge };
