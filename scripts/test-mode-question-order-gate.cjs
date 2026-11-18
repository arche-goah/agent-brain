#!/usr/bin/env node
// Fixture for helpers/mode-question-order-gate.cjs. Cases from 2026-10-26 (one call) and 2026-11-18 (no step between).
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { decide } = require('../helpers/mode-question-order-gate.cjs');

let fails = 0, n = 0;
function check(name, ok) { n += 1; if (!ok) fails += 1; console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${name}`); }

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'mqo-'));
const tp = path.join(root, 't.jsonl');
const ask = (id) => JSON.stringify({ type: 'assistant', message: { content: [{ type: 'tool_use', id, name: 'AskUserQuestion', input: {} }] } });
const res = (id) => JSON.stringify({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id, content: 'answered' }] } });
const bash = (id) => JSON.stringify({ type: 'assistant', message: { content: [{ type: 'tool_use', id, name: 'Edit', input: {} }] } });
const mode = { question: 'Weiter autonom?', header: 'Modus', options: [] };
const other = { question: 'Patch anwenden?', header: 'settings', options: [] };
const call = (qs) => ({ tool_name: 'AskUserQuestion', tool_input: { questions: qs }, transcript_path: tp });
const reset = () => { try { fs.unlinkSync(path.join(root, '.claude-state', 'mode-question-order.json')); } catch (e) { /* none */ } };

fs.writeFileSync(tp, [ask('a1'), res('a1')].join('\n'));
reset(); check('held: mode question right after answers, no step between (2026-11-18)', !!decide(call([mode]), root));
check('passes: the same call again (no step was needed)', decide(call([mode]), root) === null);

reset(); fs.writeFileSync(tp, [ask('a1'), res('a1'), bash('b1')].join('\n'));
check('passes: a step ran after the answers', decide(call([mode]), root) === null);

reset(); check('held: mode question in one call with a decision (2026-10-26)', !!decide(call([other, mode]), root));

reset(); check('passes: a call without the mode question', decide(call([other]), root) === null);

reset(); fs.writeFileSync(tp, [bash('b0')].join('\n'));
check('passes: no earlier answer at all', decide(call([mode]), root) === null);

check('passes: another tool', decide({ tool_name: 'Bash', tool_input: {} }, root) === null);
console.log(`\nmode-question-order-gate: ${fails ? `${fails} of ${n} FAILED` : `all ${n} cases pass`}`);
process.exit(fails ? 1 : 0);
