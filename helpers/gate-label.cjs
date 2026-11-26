/**
 * gate-label.cjs - ONE reader for the name of the gate behind a hook refusal.
 *
 * Why (2026-11-23): the label was parsed in four places with four regexes - root-cause-gate's malfunction path, its
 * anomaly path, gate-health.py and the refusal register - and they disagreed. A label with spaces ("SHARED WORKING
 * COPY") was cut to its first word in one, an unlabelled refusal became "a hook" in another (the Windows review of
 * the strand counted 6). One reader, used by every caller in node; gate-health.py carries the same two rules in
 * Python and points here.
 *
 *   gateLabel(rawText) -> string
 *   1. a refusal's own label, up to the first `:` or ` (`:  `MECHANISM CHECK (agent-brain): …` -> "MECHANISM CHECK",
 *      `BLOCKED (content-review-gate): …` -> "content-review-gate"
 *   2. else the hook the harness names: `[node "…/x-gate.cjs"]` -> "x-gate", `[command hook 29]` -> "command hook 29"
 *      (the form in gate-malfunction.json, the one source of the malfunction shape)
 *   3. else "a hook"
 */
'use strict';
const fs = require('fs');
const path = require('path');

const HEAD = /^(?:PreToolUse|PostToolUse):\S+ hook error:\s*/;
// `BLOCKED (instance-key-gate, change level)` names its gate before the comma; a bare `BLOCKED:` (file-guard) names
// none - it is a verdict word, not a gate, and fell through to step 2 (Windows review of #643, 2026-11-24: the bare
// word lumped two gates and matched any register entry holding "blocked").
const LABEL = /^(?:\[[^\]]*\]:\s*)?(?:BLOCKED \(([\w-]+)[,)]|(?!BLOCKED\b)([A-Z][A-Z0-9 _-]{2,40}?)\s*(?::| \())/;
let hookForm = null;
function hookRx() {
  if (hookForm) return hookForm;
  try {
    hookForm = new RegExp(JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'gate-malfunction.json'), 'utf8')).gate);
  } catch (e) {
    hookForm = /\[node "[^"]*?([\w.-]+)\.(?:cjs|js)"[^\]]*\]|\[command hook (\d+)\]/;
  }
  return hookForm;
}

function gateLabel(rawText) {
  const t = String(rawText || '').trim().replace(HEAD, '');
  const m = LABEL.exec(t);
  const own = m && (m[1] || m[2]);
  if (own && own.trim()) return own.trim();
  const h = hookRx().exec(t);
  if (h) return h[1] || `command hook ${h[2]}`;
  return 'a hook';
}

module.exports = { gateLabel };
