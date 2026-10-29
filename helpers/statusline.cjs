#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');

// Run mode at the right end (operator 2026-10-29: "status-line ... interaktiv / autonom mit klarer signalfarbe"):
// the latch every gate reads, helpers/autonomous-mode.cjs of the session's brain (<project>/core/helpers/ in an
// instance, <project>/helpers/ in the core repo itself). A project without it shows nothing. Labels are instance
// data (`statusline_labels` in .claude/rules/autonomous-patterns.json), English by default. The copy under
// ~/.claude/helpers is refreshed from here by the session start, so a change belongs here, never in the copy.
function runMode(d) {
  try {
    const dir = d.workspace?.project_dir || d.cwd;
    const tp = d.transcript_path;
    if (!dir || !tp) return null;
    const helper = [path.join(dir, 'core', 'helpers', 'autonomous-mode.cjs'), path.join(dir, 'helpers', 'autonomous-mode.cjs')]
      .find((p) => fs.existsSync(p));
    if (!helper) return null;
    let labels = {};
    try { labels = JSON.parse(fs.readFileSync(path.join(dir, '.claude', 'rules', 'autonomous-patterns.json'), 'utf8')).statusline_labels || {}; } catch {}
    // the transcript grows with every message: cache the verdict per size, the full read costs ~0.15 s on 30 MB
    // per session: every session hands its OWN transcript, the cache is keyed by it — five parallel sessions show
    // five modes. A fresh session has no transcript file yet: no on word was said, so it is interactive.
    let size = -1;
    try { size = fs.statSync(tp).size; } catch {}
    const cache = path.join(os.tmpdir(), 'statusline-mode-' + path.basename(tp) + '.json');
    let auto = size < 0 ? false : undefined;
    if (auto === undefined) try { const c = JSON.parse(fs.readFileSync(cache, 'utf8')); if (c.size === size) auto = c.auto; } catch {}
    if (auto === undefined) {
      auto = require(helper).autonomousMode(tp, dir);
      try { fs.writeFileSync(cache, JSON.stringify({ size, auto })); } catch {}
    }
    // 24-bit colours, not the 16-colour palette: the theme's "bright magenta" rendered as a soft red (operator 2026-10-29)
    return auto ? `\x1b[1;38;2;199;125;255m${labels.autonomous || 'AUTONOMOUS'}\x1b[0m`      // neon violet
      : `\x1b[1;38;2;150;255;190m${labels.interactive || 'INTERACTIVE'}\x1b[0m`;           // sage neon
  } catch { return null; }
}

let raw = '';
process.stdin.on('data', c => raw += c);
process.stdin.on('end', () => {
  let d = {};
  try { d = JSON.parse(raw); } catch {}

  const model = d.model?.display_name || '?';
  const parts = [`\x1b[36m${model}\x1b[0m`];

  const fmtReset = (epoch) => {
    if (!epoch) return '';
    let s = Math.max(0, epoch - Math.floor(Date.now() / 1000));
    const dDays = Math.floor(s / 86400); s %= 86400;
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (dDays > 0) return `${dDays}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  };

  const color = (rem) => rem <= 10 ? '\x1b[31m' : rem <= 30 ? '\x1b[33m' : '\x1b[32m';

  const win = (label, w) => {
    if (!w || w.used_percentage == null) return;
    const rem = Math.max(0, 100 - w.used_percentage);
    parts.push(`${label}: ${color(rem)}${rem.toFixed(0)}% left\x1b[0m (reset ${fmtReset(w.resets_at)})`);
  };

  win('5h', d.rate_limits?.five_hour);
  win('7d', d.rate_limits?.seven_day);

  const ctx = d.context_window?.used_percentage;
  if (ctx != null) parts.push(`Ctx ${Math.floor(ctx)}%`);

  const mode = runMode(d);
  if (mode) parts.push(mode);

  process.stdout.write(parts.join(' \x1b[90m|\x1b[0m '));
});
