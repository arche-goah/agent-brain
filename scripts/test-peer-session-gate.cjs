// covers: peer-session-gate
// Fixture for helpers/peer-session-gate.cjs - both directions, no live process list.
// The must-block case is the incident (2026-11-17): the closing reply named a peer session's claim as
// holding while only this session ran. Session count through parallel-sessions.sh's own seam
// PARALLEL_SESSIONS_CMDLINES (one line = this session only, two = a peer runs).
// Usage: node scripts/test-peer-session-gate.cjs   (exit 0 = pass)
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const GATE = path.join(__dirname, '..', 'helpers', 'peer-session-gate.cjs');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'peer-session-gate-'));
const root = path.join(tmp, 'my-brain');
fs.mkdirSync(path.join(root, '.claude', 'rules'), { recursive: true });
const one = path.join(tmp, 'one.txt');
const two = path.join(tmp, 'two.txt');
fs.writeFileSync(one, 'claude\n');
fs.writeFileSync(two, 'claude\nclaude --resume\n');

let fail = 0;
const ok = (m) => console.log(`  OK  ${m}`);
const bad = (m) => { console.log(`  FAIL ${m}`); fail = 1; };

function transcript(reply) {
  const f = path.join(tmp, `t-${Math.random().toString(16).slice(2)}.jsonl`);
  const lines = [
    { type: 'user', message: { role: 'user', content: 'what is open?' } },
    { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: reply }] } },
  ];
  fs.writeFileSync(f, lines.map((l) => JSON.stringify(l)).join('\n') + '\n');
  return f;
}

function run(reply, cmdlines, extra) {
  const input = { transcript_path: transcript(reply), cwd: root, ...(extra || {}) };
  const r = spawnSync('node', [GATE], { input: JSON.stringify(input), encoding: 'utf8',
    env: { ...process.env, PARALLEL_SESSIONS_CMDLINES: cmdlines } });
  return r.stdout || '';
}

function check(label, reply, cmdlines, want, extra) {
  const out = run(reply, cmdlines, extra);
  const blocked = out.includes('"decision":"block"');
  if (blocked === (want === 'block')) ok(`${label} ${want}s`);
  else bad(`${label}: wanted ${want}, got ${out.slice(0, 200) || '(nothing)'}`);
  return out;
}

const INCIDENT = 'Also, session my-brain-2b still holds its claim on docs/maintenance/.';
const out = check('the incident: a closed peer named as holding a claim, only this session runs', INCIDENT, one, 'block');
if (out.includes('measures only this one') && out.includes('my-brain-2b')) ok('the block names the sentence');
else bad(`the block does not name the sentence: ${out.slice(0, 200)}`);
check('present form "is running", only this session', 'A second session (my-brain-ff) is running in this brain.', one, 'block');
check('a peer really runs (two sessions measured)', INCIDENT, two, 'allow');
check('past form: the peer ran', 'Session my-brain-2b ran from 06:14 to 06:19.', one, 'allow');
check('past form: the peer was closed', 'A second session existed, it was closed at 06:19 (my-brain-2b).', one, 'allow');
check('a name without a present claim', 'The lines were written by my-brain-ff.', one, 'allow');
check('another repo folder is no peer of this brain', 'Session other-repo-2b still holds its claim.', one, 'allow');
check('the re-issue pass stays silent', INCIDENT, one, 'allow', { stop_hook_active: true });
check('no transcript fails open', INCIDENT, one, 'allow', { transcript_path: path.join(tmp, 'missing.jsonl') });

// instance words extend the built-ins (the operator's language; stand-in words here, the repo is English-only)
fs.writeFileSync(path.join(root, '.claude', 'rules', 'peer-session.json'),
  JSON.stringify({ now_patterns: ['\\bis humming\\b'], past_patterns: ['\\bwent quiet\\b'] }));
check('an instance present word blocks', 'Over there my-brain-2b is humming along.', one, 'block');
check('an instance past word passes', 'Session my-brain-2b is humming no more, it went quiet at 06:19.', one, 'allow');
fs.writeFileSync(path.join(root, '.claude', 'rules', 'peer-session.json'), JSON.stringify({ now_patterns: ['(unclosed'] }));
check('a broken instance regex is skipped, built-ins stay', INCIDENT, one, 'block');

fs.rmSync(tmp, { recursive: true, force: true });
console.log(fail ? '\npeer-session-gate: FAILURE' : '\npeer-session-gate: all cases pass');
process.exit(fail);
