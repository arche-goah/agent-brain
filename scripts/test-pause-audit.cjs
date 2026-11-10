#!/usr/bin/env node
// covers: pause-audit
// Fixture for scripts/pause-audit.cjs: a synthetic transcript with one pause per sort; the mode comes only from the
// written mode log (no recomputation). Exit 1 on a failed case.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { audit } = require('./pause-audit.cjs');

let n = 0;
const at = (min) => new Date(Date.UTC(2026, 9, 29, 8, min)).toISOString();
const user = (min, t) => ({ type: 'user', timestamp: at(min), message: { role: 'user', content: t } });
const said = (min, t, tool) => ({ type: 'assistant', timestamp: at(min), message: { role: 'assistant',
  content: [{ type: 'text', text: t }, ...(tool ? [{ type: 'tool_use', id: `t${++n}`, name: tool, input: {} }] : [])] } });
const stop = (min, prevented) => ({ type: 'system', subtype: 'stop_hook_summary', timestamp: at(min), preventedContinuation: !!prevented });

const recs = [
  user(0, 'hello'), said(1, 'Here is the state.'), stop(1),                                     // 1 interactive, 4 min
  user(5, 'work autonomously'), said(6, 'The watcher runs.', 'Monitor'), stop(6),               // 2 suspect, 10 min
  user(16, '<task-notification> x </task-notification>'), said(17, '- **BLOCKED:** Windows check missing, list measured'), stop(17), // 3 stated-block
  user(27, '<task-notification> y </task-notification>'), said(28, 'I am waiting.'), stop(28),  // 4 confirmed by the operator
  user(38, 'why did you stop?'), said(38, 'Going on.'), stop(38, true),                          // a held stop is no pause
  user(39, 'Stop hook feedback: keep going'), said(39, 'ok'), stop(39),                          // a hook echo starts no turn
  user(39, 'normal mode'), said(40, 'fine'), stop(40),                                           // 5 no written mode: unknown
  user(45, 'next'), said(45, 'x'), stop(45),
  user(45, 'again'),                                                                              // 0 min: under the floor
];
const f = path.join(os.tmpdir(), `pause-audit-fixture-${process.pid}.jsonl`);
fs.writeFileSync(f, recs.map((r) => JSON.stringify(r)).join('\n'));
const sid = path.basename(f, '.jsonl');
const log = new Map([[sid, [1, 6, 17, 28].map((m, i) => ({ ms: Date.parse(at(m)), auto: i > 0 }))]]);
const rows = audit(f, 60, log);
const bare = audit(f, 60, new Map());
fs.unlinkSync(f);

const want = [['interactive', 240], ['suspect', 600], ['stated-block', 600], ['confirmed-unnecessary', 600], ['unknown', 300]];
let bad = 0;
const check = (ok, name) => { console.log(`${ok ? '  OK  ' : '  FAIL'} ${name}`); bad += ok ? 0 : 1; };
check(rows.length === want.length, `${want.length} pauses found (got ${rows.length}: ${rows.map((r) => r.sort).join(', ')})`);
want.forEach(([sort, s], i) => {
  const r = rows[i] || {};
  check(r.sort === sort && r.seconds === s, `pause ${i + 1}: ${sort}, ${s} s (got ${r.sort}, ${r.seconds})`);
});
check(rows[2] && rows[2].sort === 'stated-block', 'a listed bold BLOCKED line is a stated block (the alpha missed this form)');
check(rows[1] && rows[1].closing_tools.includes('Monitor'), 'the closing turn names its tools');
check(rows[3] && rows[3].restart_kind === 'operator', 'the restart kind of an operator prompt is operator');
check(rows[2] && rows[2].restart_kind === 'notification', 'the restart kind of a notification is notification');
check(bare.length === want.length && bare.every((r) => r.sort === 'unknown'), 'without a mode log every pause is unknown, never recomputed');
// the rotated generation is read too (2026-11-10: after a rotation 846 of 847 pauses lost their written mode)
{
  const { execFileSync } = require('child_process');
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'pause-audit-log-'));
  fs.writeFileSync(path.join(d, 'mode-log.1.jsonl'), JSON.stringify({ at: at(1), session: 'old', mode: 'autonomous' }) + '\n');
  fs.writeFileSync(path.join(d, 'mode-log.jsonl'), JSON.stringify({ at: at(2), session: 'new', mode: 'interactive' }) + '\n');
  const out = execFileSync(process.execPath, ['-e', `const m=require(${JSON.stringify(path.join(__dirname, 'pause-audit.cjs'))}).loadModeLog();process.stdout.write([...m.keys()].sort().join(','))`],
    { env: { ...process.env, PAUSE_AUDIT_MODE_LOG: path.join(d, 'mode-log.jsonl') }, encoding: 'utf8' });
  fs.rmSync(d, { recursive: true, force: true });
  check(out === 'new,old', `the rotated generation is read with the current one (got ${out})`);
}
console.log(bad ? `test-pause-audit: ${bad} FAILURE(S)` : 'test-pause-audit: all checks passed');
process.exit(bad ? 1 : 0);
