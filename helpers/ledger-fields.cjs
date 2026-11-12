'use strict';
/**
 * The ONE reader of ledger fields in JavaScript; the Python twin is scripts/ledger_fields.py. Both build their
 * patterns from ledger-fields.json at the core root, so the two languages cannot read a field differently.
 *
 * WHY (content review of agent-brain #475, 2026-11-10): four readers of `id:` used four patterns; one read only
 * line starts and called mid-line ids (`... | id: x | class: todo`) absent.
 *
 *   fieldValues(text, name)  every value of the field in the text, in order
 *   firstValue(text, name)   the first one, or null
 */
const fs = require('fs');
const path = require('path');

const SPEC = path.join(__dirname, '..', 'ledger-fields.json');
const cache = {};

function pattern(name) {
  if (!cache[name]) {
    const f = JSON.parse(fs.readFileSync(SPEC, 'utf8')).fields[name];
    const esc = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    cache[name] = new RegExp(`${f.lead}${esc}:\\s*\`?${f.value}${f.end}`, 'gm');
  }
  return cache[name];
}

const fieldValues = (text, name) => [...String(text || '').matchAll(pattern(name))].map((m) => m[1]);
const firstValue = (text, name) => fieldValues(text, name)[0] || null;

module.exports = { fieldValues, firstValue };
