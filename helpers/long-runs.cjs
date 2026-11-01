/**
 * Long runs the guard's name list cannot know (2026-10-31). Working Rule #13 says a run that holds
 * the session longer than about half a minute runs detached; mechanism-guard enforced it only for
 * commands its rules NAME (ci-watch.sh, ci-lint-local.sh, wait loops). Measured on the macOS
 * instance: six runs the operator had to push to the background by hand since 2026-10-11, each a
 * name the guard did not know yet - the last one a wrapper (`core-merge-lint.sh` runs ci-lint-local.sh
 * inside), so even a listed name hid behind it. Two ways in, no name list:
 *
 *   declared - a script says it of itself: a comment line `# long-run: detached` (or `// long-run:
 *              detached`) in its first 4 KB. The producer knows its duration; the reader never guesses.
 *   learned  - the harness marks a run the operator backgrounded by hand (`backgroundedByUser: true`
 *              on the Bash result in the transcript). The guard reads the transcript's tail on every
 *              foreground Bash call and records the script that run executed in
 *              <project>/.claude-state/long-runs.json; from then on, in every session, it is held.
 *
 * Only a script in COMMAND position counts (`bash x.sh`, `./x.sh`, `python3 x.py`), so a grep or a
 * commit message that merely names it passes.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const EXEC_RE = /(?:^|[\n;&|(]|\$\()\s*(?:(?:env|command|exec|nohup|time)\s+|[A-Za-z_]\w*=\S*\s+)*(?:(?:bash|sh|zsh|python3?|node)(?:\s+-\S+)*\s+)?("[^"\n]+\.(?:sh|py|cjs|mjs|js)"|'[^'\n]+\.(?:sh|py|cjs|mjs|js)'|[^\s;&|()'"]+\.(?:sh|py|cjs|mjs|js))(?=$|[\s;&|)])/g;
const DECLARED_RE = /^\s*(?:#|\/\/)\s*long-run:\s*detached\b/m;
const TAIL_BYTES = 512 * 1024;

function storeFile(project) { return path.join(project, '.claude-state', 'long-runs.json'); }

/** Every script a command line executes, as written (quotes removed). */
function executedScripts(cmd) {
  const out = [];
  for (const m of String(cmd || '').matchAll(EXEC_RE)) out.push(m[1].replace(/^["']|["']$/g, ''));
  return out;
}

function readStore(project) {
  try { return JSON.parse(fs.readFileSync(storeFile(project), 'utf8')); } catch (_) { return {}; }
}

function declared(script, dirs) {
  const p = path.isAbsolute(script) ? script
    : dirs.map((d) => path.join(d, script)).find((x) => fs.existsSync(x));
  if (!p) return false;
  let fd;
  try {
    fd = fs.openSync(p, 'r');
    const buf = Buffer.alloc(4096);
    const n = fs.readSync(fd, buf, 0, 4096, 0);
    return DECLARED_RE.test(buf.toString('utf8', 0, n));
  } catch (_) { return false; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch (_) {} }
}

/** Record the scripts of the hand-backgrounded runs in the transcript's tail; returns the store. */
function learn(transcriptPath, project, now) {
  const data = readStore(project);
  if (!transcriptPath) return data;
  let text = '';
  try {
    const st = fs.statSync(transcriptPath);
    const fd = fs.openSync(transcriptPath, 'r');
    const len = Math.min(st.size, TAIL_BYTES);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, st.size - len);
    fs.closeSync(fd);
    text = buf.toString('utf8');
  } catch (_) { return data; }
  if (!text.includes('"backgroundedByUser":true')) return data;
  const cmds = {};
  const hits = [];
  for (const line of text.split('\n')) {
    let d; try { d = JSON.parse(line); } catch (_) { continue; }
    const c = d && d.message && d.message.content;
    for (const b of Array.isArray(c) ? c : []) {
      if (b && b.type === 'tool_use' && b.name === 'Bash') cmds[b.id] = (b.input || {}).command || '';
      if (b && b.type === 'tool_result' && d.toolUseResult && d.toolUseResult.backgroundedByUser === true) hits.push(b.tool_use_id);
    }
  }
  data.seen = data.seen || [];
  data.scripts = data.scripts || {};
  let changed = false;
  const day = (now || new Date()).toISOString().slice(0, 10);
  for (const id of hits) {
    if (data.seen.includes(id) || !(id in cmds)) continue;
    data.seen.push(id);
    changed = true;
    for (const s of executedScripts(cmds[id]).map((x) => path.basename(x))) {
      const e = data.scripts[s] || { first: day, count: 0 };
      e.count += 1; e.last = day; e.cmd = cmds[id].slice(0, 200);
      data.scripts[s] = e;
    }
  }
  if (changed) {
    data.seen = data.seen.slice(-200);
    try {
      fs.mkdirSync(path.dirname(storeFile(project)), { recursive: true });
      fs.writeFileSync(storeFile(project), JSON.stringify(data, null, 2) + '\n');
    } catch (_) {}
  }
  return data;
}

/** The first executed script of `cmd` known to run long, with the reason, or null. */
function longRunScript(cmd, project, transcriptPath, cwd) {
  const scripts = executedScripts(cmd);
  if (!scripts.length) return null;
  const known = learn(transcriptPath, project).scripts || {};
  for (const s of scripts) {
    const base = path.basename(s);
    if (known[base]) return { script: base, why: `learned: the operator had to background it by hand on ${known[base].last}; give the script a \`# long-run: detached\` line so every brain knows it` };
    // relative to the call's working directory first (a core worktree), then to the project
    if (declared(s, [cwd, project].filter(Boolean))) return { script: base, why: 'declared: the script says `long-run: detached` of itself' };
  }
  return null;
}

module.exports = { executedScripts, longRunScript, learn };
