#!/usr/bin/env python3
"""Hook coverage: which hooks the core template wires that this brain does not.

WHY: templates/settings.json only reaches a brain ONCE, at bootstrap. A hook added
to the template later (v1.3.12: the class-gate Stop hook) reaches existing brains
solely as a CHANGELOG sentence — and a brain that misses that sentence stays
silently half-functional: the helper ships, updates, passes every smoke check, and
never runs. Measured 2026-08-19 on the Windows instance: class-gate.cjs consumed
with v1.3.12, wired nowhere. This script makes the gap loud; it NEVER edits —
settings.json is operator territory (an agent cannot extend its own wiring).

WHAT COUNTS AS MISSING: a template hook command that points at core/helpers/<file>,
where <file> exists in the consumed core state, and no hook command under the SAME
event in the brain's settings (project, project-local or user scope) references
that helper file. Matching is by helper filename, so path notation (slashes,
$CLAUDE_PROJECT_DIR vs absolute) never causes a false alarm.

ALSO REPORTED: a gate the template sets to `"onFailure": "block"` (fail closed when the
hook cannot start, crashes or times out; Claude Code >= 2.1.295) that this brain wires
without it - "fails open".

ALSO REPORTED: a core hook wired with a shorter `timeout` than the template gives it.

ALSO REPORTED: a `permissions.allow` entry of the template that points into the core
(`Bash(node core/helpers/*)`, `Bash(python3 core/scripts/*)`, ...) which no settings scope
of this brain grants, verbatim or by a broader glob. Same class as an unwired hook: the
template reaches a brain once, so a core tool the harness must let the agent run by itself
(`question-gate.cjs resolve`, `ci-watch.sh`, ...) ends in a permission prompt — or, in auto
mode, in the classifier refusing it as a workaround. Measured 2026-10-11 on a Windows brain:
the agent could not close its own answered question, the operator had to run the command by
hand; the macOS brain, which carries the entry, ran the same command three times that day.
The same holds for the template's core UPDATE path (`claude plugin update|enable|...`, the
push block on `core/`): those entries name no core path, but without them the AI cannot
update its own core. Measured 2026-10-18 on a macOS brain: the move to 2.0.0 stopped at the
channel switch and the push block, both refused by the classifier.

ALSO REPORTED: a wired gate whose instance data is missing or empty, so it checks nothing
(`INERT-WITHOUT:` line in the helper's header names the file and keys; `"inert_ok": "<reason>"`
in the file declares the empty state deliberate). Matchers narrower than the template's are
reported per hook above.

Usage: hook-coverage.py [brain-root]           (default: cwd)
Output: one line per missing hook — "<event>: <template command>".
Exit 0 and silent when covered; exit 1 when something is missing.
Callers: helpers/session-bootup.sh (!! line each session) and
scripts/brain-update.sh (WARN in the release catch-up).
"""
import json
import os
import re
import sys

# The session start parses this output; left to the platform, Windows' console code page
# mangles the dashes in these lines (os-traps OS-9).
try:
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
except (AttributeError, ValueError):  # a stream that cannot be reconfigured
    pass


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def commands_by_event(settings):
    """event -> [(matcher, command)]. The MATCHER is carried on purpose: a hook can be
    wired and still not run, because its matcher names fewer tools than the template
    does. Measured 2026-09-02: mechanism-guard was wired everywhere with matcher
    \"Bash\", the template had widened to \"Bash|Monitor\", and a hand-built watcher —
    a Monitor command — passed every brain untouched while this check reported full
    coverage. Comparing commands alone cannot see that state."""
    out = {}
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups or []:
            if not isinstance(group, dict):
                continue
            matcher = group.get("matcher") or ""
            for h in group.get("hooks") or []:
                cmd = h.get("command") if isinstance(h, dict) else None
                if cmd:
                    out.setdefault(event, []).append((matcher, cmd, h.get("onFailure") or "continue"))
    return out


def timeouts(settings):
    """(event, core file) -> the largest `timeout` any wiring of it carries. Hooks without the
    field are left out: the harness default applies there, and this check does not guess it."""
    out = {}
    for event, groups in (settings.get("hooks") or {}).items():
        for group in groups or []:
            for h in (group.get("hooks") or []) if isinstance(group, dict) else []:
                m = re.search(r"core/(?:helpers|scripts)/([\w.-]+)", h.get("command") or "") if isinstance(h, dict) else None
                t = h.get("timeout") if m else None
                if isinstance(t, (int, float)):
                    key = (event, m.group(1))
                    out[key] = max(out.get(key, 0), t)
    return out


def matcher_tools(matcher):
    """The tool names a matcher covers. An empty matcher means every tool, which can
    never be narrower than the template — so it is returned as None, not as an empty
    set, to keep \"matches everything\" apart from \"matches nothing\"."""
    if not matcher or matcher == "*":
        return None
    return {tok.strip() for tok in matcher.split("|") if tok.strip()}


def registered_via_dispatcher(root, wired):
    """Helpers a wired dispatcher runs on the brain's behalf.

    The claim is only accepted when BOTH halves hold: a dispatcher is actually wired in
    settings, AND the helper is registered in its config. Either half alone would turn
    this into a way to silence the check by writing a file.
    """
    if not any("dispatcher" in c for pairs in wired.values() for _, c, _f in pairs):
        return set()
    cfg = load(os.path.join(root, ".claude", "rules", "stop-checks.json"))
    out = set()
    for check in cfg.get("checks") or []:
        cmd = check.get("cmd") if isinstance(check, dict) else None
        if cmd:
            out.add(os.path.basename(cmd))
    return out


INERT_RX = re.compile(r"^\s*\*?\s*INERT-WITHOUT:\s*(\S+)(?:\s+(\S+))?", re.M)


def inert_without(helper_path):
    """(data file, [keys]) a helper declares it needs, or None. The gate is inert when the file
    is missing, or every named key is empty and the file carries no `inert_ok` reason."""
    try:
        with open(helper_path, encoding="utf-8", errors="replace") as f:
            m = INERT_RX.search(f.read(8000))
    except OSError:
        return None
    if not m:
        return None
    return m.group(1), [k for k in (m.group(2) or "").split("|") if k]


def wired_helpers(root, wired):
    """(event, helper file) for every core helper that runs here: wired directly, or
    registered behind a wired dispatcher (those run on the Stop event)."""
    out = set()
    for event, pairs in wired.items():
        for _m, cmd, _f in pairs:
            m = re.search(r"core/helpers/([\w.-]+)", cmd)
            if m:
                out.add((event, m.group(1)))
    for helper in registered_via_dispatcher(root, wired):
        out.add(("Stop", helper))
    return out


# Template permissions a brain must carry: entries into the core, and the core update path.
CORE_PERMISSION = re.compile(r"core/(helpers|scripts)|^Bash\(claude plugin (update|marketplace update|enable|disable|install)\b"
                             r"|remote set-url --push origin DISABLED")


def allow_entries(settings):
    return [e for e in ((settings.get("permissions") or {}).get("allow") or []) if isinstance(e, str)]


def granted(entry, have):
    """A template entry is granted when a brain scope carries it verbatim, or a broader glob
    whose fixed prefix the entry starts with (`Bash(node core/*)` covers `Bash(node core/helpers/*)`)."""
    for h in have:
        if h == entry:
            return True
        if h.endswith("*)") and entry.startswith(h[:-2]):
            return True
    return False


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    template = load(os.path.join(root, "core", "templates", "settings.json"))
    if not template:
        return 0  # no consumed template (not a brain, or pre-template core): nothing to demand

    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    wired = {}
    have_allow = []
    have_timeout = {}
    for p in (
        os.path.join(root, ".claude", "settings.json"),
        os.path.join(root, ".claude", "settings.local.json"),
        os.path.join(cfg, "settings.json"),
    ):
        s = load(p)
        for event, pairs in commands_by_event(s).items():
            wired.setdefault(event, []).extend(pairs)
        have_allow.extend(allow_entries(s))
        for key, t in timeouts(s).items():
            have_timeout[key] = max(have_timeout.get(key, 0), t)

    # A hook wired with a SHORTER timeout than the template is killed before the core expects
    # it to be done, and a killed SessionStart hook reports nothing. The field reaches a brain
    # only at bootstrap, like the hooks themselves. Measured 2026-10-19 on a Windows brain: the
    # start report took 18-28 s against 30 s, one start was killed after 31 s and its report
    # never arrived; the template went to 60 s, and without this line no existing brain hears it.
    shorter = []
    for (event, helper), want in sorted(timeouts(template).items()):
        have = have_timeout.get((event, helper))
        if have is not None and have < want:
            shorter.append("%s: %s has timeout %s s - the template gives it %s s; raise it in .claude/settings.json"
                           % (event, helper, have, want))

    not_granted = []
    for entry in allow_entries(template):
        if CORE_PERMISSION.search(entry) and not granted(entry, have_allow):
            not_granted.append('permissions: "%s" from the core template is not granted here - every run of a core '
                               'tool it covers ends in a prompt, or in auto mode in the classifier refusing it; add it '
                               'to .claude/settings.json permissions.allow' % entry)

    # A helper can be wired INDIRECTLY: a dispatcher hook runs several checks itself
    # and the settings then name only the dispatcher. Matching on filenames alone
    # reports those as missing — measured 2026-08-20 on an instance that consolidated
    # seven Stop hooks into one: two live helpers were reported missing every session,
    # and a warning that is always there stops being a signal.
    dispatched = registered_via_dispatcher(root, wired)

    missing = []
    narrower = []
    fail_open = []
    for event, pairs in commands_by_event(template).items():
        for matcher, cmd, on_failure in pairs:
            # Any template hook pointing INTO the consumed core counts, not just
            # helpers/. Measured 2026-08-20: brain-check.sh lives in core/scripts, so a
            # brain that never wired it was reported as fully covered — the check that
            # exists to catch "shipped but not wired" had a blind spot of exactly that
            # shape.
            m = re.search(r"core/(helpers|scripts)/([\w.-]+)", cmd)
            if not m:
                continue  # template command outside the core: not this check's contract
            sub, helper = m.group(1), m.group(2)
            if not os.path.isfile(os.path.join(root, "core", sub, helper)):
                continue  # not in the consumed core yet: nothing to wire
            hits = [(m, c) for m, c, _f in wired.get(event, []) if helper in c]
            # A gate the template makes fail CLOSED (onFailure: block, Claude Code >= 2.1.295)
            # but this brain wires with the default "continue": a crash, a timeout or a
            # missing script then lets every action through. Field only reaches a brain at
            # bootstrap, like the hooks themselves, so it is checked the same way.
            if on_failure == "block" and hits and not any(
                    f == "block" for _m, c, f in wired.get(event, []) if helper in c):
                fail_open.append("%s: %s fails open - the template sets \"onFailure\": \"block\"" % (event, helper))
            if hits:
                # Wired — but a matcher that names fewer tools than the template means
                # the hook does not run where the template says it must.
                want = matcher_tools(matcher)
                if want:
                    for m, _c in hits:
                        have = matcher_tools(m)
                        if have is None:
                            continue  # matches everything, never narrower
                        gap = want - have
                        if gap:
                            narrower.append(
                                "%s: %s runs only on %s — the template also wires %s"
                                % (event, helper, m or "(none)", "|".join(sorted(gap)))
                            )
                continue
            if helper in dispatched:
                continue  # runs behind a dispatcher, see registered_via_dispatcher()
            missing.append("%s: %s" % (event, cmd))

    # A wired gate whose INSTANCE DATA is missing checks nothing and says so nowhere, or only on
    # stderr, where nobody reads it. Measured twice: 2026-10-10 on a Windows instance
    # (public-text-guard wired, leak-names.json missing) and 2026-10-12 on the same instance
    # (live-read-gate wired, live-read.json missing — a silent no-op in a brain with three live
    # systems, found only by a coherence scan). Each helper declares its data file in its own
    # header (`INERT-WITHOUT: <file> <key>[|<key>]`), so this check needs no hand list: a new
    # data-only gate is covered by the line it ships with. A brain for which "nothing to check"
    # IS the right state (no live systems) says so in the file — `"inert_ok": "<reason>"` — the
    # same declared-with-a-reason move as local-machinery.json; an empty list copied from the
    # template is not a decision.
    inert = []
    for event, helper in sorted(wired_helpers(root, wired)):
        need = inert_without(os.path.join(root, "core", "helpers", helper))
        if not need:
            continue
        rel, keys = need
        data_path = os.path.join(root, *rel.split("/"))
        if not os.path.isfile(data_path):
            inert.append("%s: %s is wired but %s does not exist - it checks nothing; fill it (template: "
                         "core/templates/rules-instance/) or say why in \"inert_ok\"" % (event, helper, rel))
            continue
        data = load(data_path) or {}
        ok = data.get("inert_ok")
        if keys and not any(data.get(k) for k in keys) and not (isinstance(ok, str) and ok.strip()):
            inert.append("%s: %s is wired but %s has no %s - it checks nothing; fill it or say why in \"inert_ok\""
                         % (event, helper, rel, " or ".join(keys)))

    # The reverse gap: a hook wired HERE whose helper the consumed core does not ship. With
    # "onFailure": "block" it refuses every call it matches — measured 2026-10-11 on a Windows
    # instance: instance-key-gate.cjs was wired from the template of an off-pin core checkout;
    # once core/ went back to its pin the file was gone and every Bash call in two sessions was
    # refused ("Cannot find module …"), while this check reported nothing. Wiring must follow
    # the template of the core that is actually consumed.
    broken = []
    for event, pairs in wired.items():
        for _m, cmd, on_failure in pairs:
            m = re.search(r"core/(helpers|scripts)/([\w.-]+)", cmd)
            if m and not os.path.isfile(os.path.join(root, "core", m.group(1), m.group(2))):
                broken.append("%s: %s is wired but the consumed core does not ship it - %s"
                              % (event, m.group(2), "every call it matches is refused (onFailure: block); unwire it "
                                 "or update the core" if on_failure == "block" else "the hook errors on every call; unwire it "
                                 "or update the core"))
    # Same class behind the dispatcher, with the opposite effect: stop-dispatcher.cjs SKIPS a
    # registered check whose file is missing (`if (!fs.existsSync(cmd)) return resolve(null)`),
    # so that gate falls away without a word while the selftest counts it as covered.
    if any("dispatcher" in c for pairs in wired.values() for _, c, _f in pairs):
        stop_cfg = load(os.path.join(root, ".claude", "rules", "stop-checks.json"))
        for check in stop_cfg.get("checks") or []:
            cmd = check.get("cmd") if isinstance(check, dict) else None
            if cmd and re.match(r"core/(helpers|scripts)/", cmd) and not os.path.isfile(os.path.join(root, cmd)):
                broken.append("Stop: %s is registered in .claude/rules/stop-checks.json but the consumed core does not "
                              "ship it - the dispatcher skips it without a word, so that check never runs"
                              % os.path.basename(cmd))

    for line in broken + missing + narrower + fail_open + shorter + inert + not_granted:
        print(line)
    return 1 if (broken or missing or narrower or fail_open or shorter or inert or not_granted) else 0


if __name__ == "__main__":
    sys.exit(main())
