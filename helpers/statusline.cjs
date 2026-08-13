#!/usr/bin/env node
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

  process.stdout.write(parts.join(' \x1b[90m|\x1b[0m '));
});
