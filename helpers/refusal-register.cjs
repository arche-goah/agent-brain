/**
 * refusal-register.cjs - the register lookup per refusal: has this gate refused this tool BEFORE, by the carrier
 * register's own entries? Then the refusal in front of the agent is a REPEAT, and the fix the earlier entry names did
 * not hold (or is not in force: an open PR is no fix).
 *
 * WHY (operator 2026-11-23, translated: "why do you not question a fault on your own, and why do you only correct the
 * surface even when it is pointed out to you?"): measured that day on the macOS instance - "the operator asks for the
 * questions, the autonomous gate refuses the question tool" stood in the carrier register for 2026-11-05 and
 * 2026-11-18 already; the third time the agent treated it as a first case, guessed at a word list, and the entry of
 * 2026-11-18 said `related: none` while its fix was a pull request open for five days. Nothing looked the symptom up.
 *
 * An entry matches a refusal by its `refusal:` field - `refusal: <GATE> <Tool>`, written by whoever writes the entry -
 * or, for entries older than the field, by its heading / incident / cause text naming the gate AND the tool (names
 * compared without case and separators; an instance adds its own words for a gate or tool as `refusal_aliases` in
 * .claude/rules/root-cause-patterns.json, e.g. {"AskUserQuestion": ["question tool"]}).
 * `effective:` on an entry says whether its carrier is in force (`yes - <how measured>` | `no - <why>`); without it
 * the state is "not stated", and a repeat says so.
 *
 * Read-only; used by helpers/root-cause-gate.cjs (Stop check and `--register-repeats` replay).
 */
'use strict';

const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const GATE_RX = /^(?:PreToolUse|PostToolUse):\S+ hook error:\s*(?:\[node "[^"]*?([\w.-]+)\.cjs"\]:\s*)?(?:BLOCKED \(([\w-]+)\)|([A-Z][A-Z0-9 _-]{2,40}?)[:(])?/;

/** The refusing gate's name from a refusal's raw tool-result text (the form root-cause-gate's anomalies() reads). */
function gateOf(raw) {
  return (GATE_RX.exec(String(raw || '').trim()) || []).slice(1).find(Boolean) || '';
}

/** The register's entries: {date, title, id, key (refusal: field), about (heading + incident + cause), carrier, effective}. */
function entries(text) {
  return String(text || '').split(/^## /m).slice(1).map((e) => {
    const head = e.split('\n')[0];
    // a field runs to the next `name:` line at column 0 (entries wrap their lines)
    const field = (name) => ((new RegExp(`^${name}:[ \\t]*([\\s\\S]*?)(?=^[a-z][a-z-]*:|(?![\\s\\S]))`, 'im').exec(e) || [])[1] || '').trim();
    return {
      date: (/^(\d{4}-\d{2}-\d{2})/.exec(head) || [])[1] || '',
      title: head.replace(/^\d{4}-\d{2}-\d{2}\s*[—-]\s*/, '').trim(),
      id: field('id').split(/\s/)[0] || '',
      key: field('refusal'),
      about: `${head}\n${field('incident')}\n${field('cause')}`,
      carrier: field('carrier').replace(/\s+/g, ' '),
      effective: field('effective').replace(/\s+/g, ' '),
    };
  });
}

function names(word, aliases) {
  const extra = aliases && Array.isArray(aliases[word]) ? aliases[word] : [];
  return [word, ...extra].map(norm).filter((w) => w.length >= 3);
}

/**
 * Earlier register entries for a refusal of `tool` by `gate`, oldest first. `before`: ISO day or timestamp of the
 * refusal - an entry of the same day or later is the present case, not an earlier one.
 */
function earlier(gate, tool, regEntries, before, aliases) {
  if (!gate || !tool) return [];
  const g = names(gate, aliases); const t = names(tool, aliases);
  const day = String(before || '').slice(0, 10);
  return regEntries.filter((e) => {
    if (day && (!e.date || e.date >= day)) return false;
    if (e.key) {
      const k = e.key.split(/\s+/);
      return g.includes(norm(k[0])) && t.includes(norm(k[1]));
    }
    const about = norm(e.about);
    return g.some((w) => about.includes(w)) && t.some((w) => about.includes(w));
  });
}

/**
 * The first refusal of the turn that the register already knows: {gate, tool, at, hits, what} or null.
 * `refusals`: [{tool, raw|text, at}] as root-cause-gate's readTurns keeps them.
 */
function repeatIn(refusals, regText, aliases) {
  const reg = entries(regText);
  if (!reg.length) return null;
  for (const r of refusals || []) {
    const gate = gateOf(r.raw || `PreToolUse:${r.tool} hook error: ${r.text}`);
    const hits = earlier(gate, r.tool, reg, r.at, aliases);
    if (!hits.length) continue;
    const last = hits[hits.length - 1];
    return {
      gate, tool: r.tool, at: r.at || '', hits,
      what: `${gate} refused ${r.tool} - the carrier register already holds ${hits.length} earlier entr${hits.length === 1 ? 'y' : 'ies'} `
        + `for this gate and tool (${hits.slice(-3).map((h) => `${h.date} ${h.id || h.title.slice(0, 40)}`).join('; ')}). `
        + `Newest: carrier "${last.carrier.slice(0, 140) || 'none named'}", effective: ${last.effective || 'not stated'}`,
    };
  }
  return null;
}

module.exports = { gateOf, entries, earlier, repeatIn };
