#!/usr/bin/env node
// covers: hand-step-gate
// Fixtures for helpers/hand-step-gate.cjs: tiny transcripts through check() (both directions) and the hook end to end
// (block once, pass after its own echo, device absent, no data = inert). Run: node scripts/test-hand-step-gate.cjs
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');
const GATE = path.join(__dirname, '..', 'helpers', 'hand-step-gate.cjs');
const { turns, check, loadData } = require(GATE);

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hsg-'));
const tpl = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'templates', 'rules-instance', 'hand-steps.json'), 'utf8'));
tpl.self_run.commands.push('\\bflash\\.py\\b');
tpl.not_at_hand.items = [{ words: ['\\bmultimeter', '\\bsoldering iron'], since: '2026-10-27', until: '2026-11-01', why: 'away from the lab' }];
const brain = path.join(tmp, 'brain');
fs.mkdirSync(path.join(brain, '.claude', 'rules'), { recursive: true });
fs.writeFileSync(path.join(brain, '.claude', 'rules', 'hand-steps.json'), JSON.stringify(tpl));
const D = loadData(brain);

const op = (t, ts = '2026-10-28T12:00:00Z') => ({ type: 'user', message: { role: 'user', content: t }, timestamp: ts });
const say = (t) => ({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: t }] } });
const BLOCK = 'Please run:\n```\npython3 tools/flash.py /dev/cu.usbmodemX\n```';

const cases = [
  ['command block for a self-run tool (incident 2026-10-28)', [op('x'), say(BLOCK)], ['self_run_handed_over']],
  ['a template command (esptool) in a block', [op('x'), say('```\nesptool.py --port /dev/ttyUSB0 flash_id\n```')], ['self_run_handed_over']],
  ['command block held by another stop check, then a clean reply', [op('x'), say(BLOCK), op('Stop hook feedback:\nOPEN'), say('The open points: ...')], ['self_run_handed_over']],
  ['tool named in prose only, no block', [op('x'), say('I run flash.py myself now.')], []],
  ['new operator message ends the old turn', [op('x'), say(BLOCK), op('another question'), say('Answer')], []],
  ['hand step needs a multimeter while away (incident 2026-10-28)', [op('x'), say('From you:\n3. Measure 3V3 against GND with the multimeter and tell me the value.')], ['not_at_hand']],
  ['an addressed sentence needs the soldering iron', [op('x'), say('Could you take the soldering iron and fix pin 5?')], ['not_at_hand']],
  ['multimeter only mentioned in quotes, not asked', [op('x'), say('The controller answers, so no "multimeter" step is needed.')], []],
  ['the step says it waits', [op('x'), say('- The multimeter check waits until 2026-11-01 when you are back.')], []],
  ['multimeter asked after the away window', [op('x', '2026-11-03T10:00:00Z'), say('3. Measure it with the multimeter.')], []],
  ['multimeter asked before the window', [op('x', '2026-10-20T10:00:00Z'), say('3. Measure it with the multimeter.')], []],
];

let fail = 0;
const result = (name, ok, extra) => { if (!ok) fail++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `  ${extra}`}`); };
cases.forEach(([name, recs, want], i) => {
  const f = path.join(tmp, i + '.jsonl');
  fs.writeFileSync(f, recs.map((r) => JSON.stringify(r)).join('\n') + '\n');
  const ts = turns(f);
  const got = check(ts[ts.length - 1], D, false).map((h) => h.check).sort();
  result(name, JSON.stringify(got) === JSON.stringify([...want].sort()), `want ${JSON.stringify(want)} got ${JSON.stringify(got)}`);
});

// The hook end to end.
function hook(recs, env) {
  const f = path.join(tmp, 'hook.jsonl');
  fs.writeFileSync(f, recs.map((r) => JSON.stringify(r)).join('\n') + '\n');
  const out = execFileSync(process.execPath, [GATE], {
    input: JSON.stringify({ transcript_path: f, session_id: 't' }), encoding: 'utf8',
    env: { ...process.env, CLAUDE_PROJECT_DIR: brain, ...env },
  });
  return /"decision":"block"/.test(out);
}
result('hook: block with the device attached', hook([op('x'), say(BLOCK)], { HAND_STEP_DEVICE: '1' }) === true, 'did not block');
result('hook: pass with no device attached', hook([op('x'), say(BLOCK)], { HAND_STEP_DEVICE: '0' }) === false, 'blocked');
result('hook: pass after its own block (once)', hook([op('x'), say(BLOCK), op('Stop hook feedback:\nHAND-STEP-GATE: ...'), say(BLOCK)], { HAND_STEP_DEVICE: '1' }) === false, 'blocked again');
result('hook: no data file = inert', hook([op('x'), say(BLOCK)], { HAND_STEP_DEVICE: '1', HAND_STEP_DATA: path.join(tmp, 'none.json') }) === false, 'blocked without data');
result('hook: a not-at-hand step blocks without a device', hook([op('x'), say('3. Use the multimeter on pin 5.')], { HAND_STEP_DEVICE: '0' }) === true, 'did not block');

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`${cases.length + 5 - fail}/${cases.length + 5} pass`);
process.exit(fail ? 1 : 0);
