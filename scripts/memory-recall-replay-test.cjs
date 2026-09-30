#!/usr/bin/env node
// Fixtures for memory-recall-replay.cjs. Both directions: a real prompt names its file and
// says which words did it; meta, slash-command and notification lines are not prompts; a
// stopword passed with --stop takes the naming away; fidelity is counted against a live log.
// Usage: node scripts/memory-recall-replay-test.cjs   (exit 0 = all pass)
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const SCRIPT = path.join(__dirname, 'memory-recall-replay.cjs');
let fail = 0;
const ok = (n, c, d) => { console.log(`  ${c ? 'OK  ' : 'FAIL'} ${n}${c ? '' : ': ' + d}`); if (!c) fail++; };

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'replay-'));
const mem = path.join(tmp, 'memory'); const tdir = path.join(tmp, 'transcripts');
fs.mkdirSync(mem); fs.mkdirSync(tdir); fs.mkdirSync(path.join(tmp, '.claude-state'));
const note = (f, name, desc) => fs.writeFileSync(path.join(mem, f), `---\nname: ${name}\ndescription: "${desc}"\n---\nbody\n`);
note('fader-mapping.md', 'fader-mapping', 'Fader mapping for the lighting console executor page');
note('network-vlan.md', 'network-vlan', 'Switch vlan trunk layout for the event network');

const user = (content, extra = {}) => JSON.stringify(Object.assign({ type: 'user', message: { role: 'user', content } }, extra));
fs.writeFileSync(path.join(tdir, 's1.jsonl'), [
  user('fix the fader mapping on the executor page'),
  user('fader mapping executor from a hook', { isMeta: true }),
  user('<command-name>/fader mapping executor</command-name>'),
  user([{ type: 'tool_result', content: 'fader mapping executor' }]),
  user('nothing relevant here at all'),
].join('\n') + '\n');
fs.writeFileSync(path.join(tmp, '.claude-state', 'memory-recall.jsonl'),
  JSON.stringify({ session: 's1', trigger: 'prompt', files: [{ file: 'fader-mapping.md' }, { file: 'network-vlan.md' }], topics: [] }) + '\n');

const run = (...extra) => {
  const out = path.join(tmp, `out-${extra.length}.jsonl`);
  const r = spawnSync(process.execPath, [SCRIPT, '--root', tmp, '--transcripts', tdir, '--out', out, ...extra],
    { encoding: 'utf8', env: Object.assign({}, process.env, { CLAUDE_MEMORY_DIR: mem }) });
  const recs = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];
  return { rc: r.status, stdout: r.stdout, recs };
};

let r = run();
ok('exit 0', r.rc === 0, r.stdout);
ok('only genuine prompts counted (2 of 5 lines)', /replay: 2 prompts/.test(r.stdout), r.stdout);
const named = r.recs.flatMap((x) => x.files);
ok('real prompt names its file', named.some((d) => d.file === 'fader-mapping.md'), JSON.stringify(r.recs));
ok('negative: unrelated file not named', !named.some((d) => d.file === 'network-vlan.md'), JSON.stringify(named));
const w = (named.find((d) => d.file === 'fader-mapping.md') || {}).words || [];
ok('words say what matched', w.includes('fader') && w.includes('mapping'), JSON.stringify(w));
ok('fidelity counted against the live log', /fidelity: 1 of 2/.test(r.stdout), r.stdout);

// the prompt matches four words: fader, mapping, executor, page
r = run('--stop', 'fader,mapping');
const left = (r.recs.flatMap((x) => x.files).find((d) => d.file === 'fader-mapping.md') || {}).words || [];
ok('--stop removes exactly those words', !left.includes('fader') && left.includes('page'), JSON.stringify(left));
r = run('--stop', 'fader,mapping,executor,page');
ok('--stop on every matched word takes the naming away', r.recs.length === 0, JSON.stringify(r.recs));

r = run('--set', 'minHits=5');
ok('--set minHits=5 names nothing on a 4-word match', r.recs.length === 0, JSON.stringify(r.recs));
r = run('--set', 'minHits=4');
ok('--set minHits=4 still names it (boundary)', r.recs.length === 1, JSON.stringify(r.recs));

fs.rmSync(tmp, { recursive: true, force: true });
console.log(fail ? `memory-recall-replay-test: ${fail} FAILED` : 'memory-recall-replay-test: all green');
process.exitCode = fail ? 1 : 0;
