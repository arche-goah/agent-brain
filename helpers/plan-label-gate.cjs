#!/usr/bin/env node
/**
 * plan-label-gate.cjs — a plan an earlier session wrote is a claim: when such a plan is read, every line that carries
 * its own uncertainty ("search hit", "page not read", "part number open", "not found") is named before anything is
 * done on it. PostToolUse on Read; adds context, never blocks; fails open.
 *
 * Why (measured 2026-11-11 on the macOS instance): order lists of earlier sessions carried their doubt in the text -
 * search hits, pages not read, part numbers open, "not found, search the shop" - and a later session executed them as
 * facts (tabs opened, items ordered); three re-orders followed. The core rule said another instance's report is a claim
 * (thinking-protocol rule 0), but nothing treated the brain's OWN earlier sessions that way, and nothing read a plan's
 * evidence labels before it ran.
 *
 * Which files are plans: a file name with plan/list/order/todo/checklist/shopping (built-in) or a path regex from the
 * instance data `.claude/rules/plan-labels.json` {"plan_paths": [...], "labels": [...], "enabled": true}. The labels
 * there extend the English built-ins with the instance's own language.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const PLAN_NAME = /(?:^|[-_./])(?:plan|plans|list|lists|order|orders|todo|checklist|shopping)(?:[-_./]|$)/i;
const LABELS = [
  'search hit', 'search result', 'not read', 'page not read', 'unverified', 'not verified', 'not checked', 'to be checked',
  'unknown', 'not found', 'tbd', 'todo', 'open question', 'assumed', 'assumption', 'guess', 'estimate', 'part number open',
  'needs check', 'check later', '\\?\\?',
];
const MAX_LINES = 12;

function config(root = ROOT) {
  let d = {};
  try { d = JSON.parse(fs.readFileSync(path.join(root, '.claude', 'rules', 'plan-labels.json'), 'utf8')); } catch (e) { /* built-ins */ }
  const labels = LABELS.concat(Array.isArray(d.labels) ? d.labels : []);
  return {
    enabled: d.enabled !== false,
    paths: (Array.isArray(d.plan_paths) ? d.plan_paths : []).map((p) => new RegExp(p, 'i')),
    labels: new RegExp(`(?:^|[^\\p{L}])(?:${labels.join('|')})(?:[^\\p{L}]|$)`, 'iu'),
  };
}

function isPlan(file, cfg) {
  const norm = String(file || '').split(path.sep).join('/');
  if (!/\.(?:md|csv|txt|ya?ml|json)$/i.test(norm)) return false;
  return PLAN_NAME.test(path.basename(norm)) || cfg.paths.some((r) => r.test(norm));
}

/** The labelled lines of a plan's text: [{n, line}], 1-based. */
function labelled(text, cfg) {
  const out = [];
  String(text || '').split(/\r?\n/).forEach((line, i) => {
    if (cfg.labels.test(line)) out.push({ n: i + 1, line: line.trim().slice(0, 160) });
  });
  return out;
}

function judge(input, cfg) {
  if (!cfg.enabled || input.tool_name !== 'Read') return null;
  const file = (input.tool_input || {}).file_path;
  if (!isPlan(file, cfg)) return null;
  let text = '';
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { return null; }
  const hits = labelled(text, cfg);
  if (!hits.length) return null;
  const shown = hits.slice(0, MAX_LINES).map((h) => `  L${h.n}: ${h.line}`).join('\n');
  const more = hits.length > MAX_LINES ? `\n  (+${hits.length - MAX_LINES} more)` : '';
  return {
    hookSpecificOutput: {
      hookEventName: 'PostToolUse',
      additionalContext: `plan-label-gate: ${path.basename(file)} carries ${hits.length} line(s) its writer marked as uncertain:\n${shown}${more}\n` +
        'A plan an earlier session wrote is a claim (thinking-protocol rule 0): before acting on one of these lines - ' +
        'opening, ordering, building, sending - read its source now, or say that it stays unverified.',
    },
  };
}

module.exports = { config, isPlan, labelled, judge };

if (require.main === module) {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (c) => { buf += c; });
  process.stdin.on('end', () => {
    try {
      const out = judge(JSON.parse(buf), config());
      if (out) console.log(JSON.stringify(out));
    } catch (e) { /* fails open */ }
    process.exit(0);
  });
}
