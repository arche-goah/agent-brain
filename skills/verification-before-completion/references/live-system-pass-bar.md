# The PASS bar for live systems

Loaded by SKILL.md before any done/passed claim about a live-operable artifact — a
show file, a rig, a control surface, a running installation, anything a person
operates rather than reads. Generic on purpose: this is the part of the bar that
holds on every rig. Device-specific procedures (which readback a console offers,
which channels prove a fixture) belong to the tool suite of that device, and an
instance may carry its own memory on top (see the pointer in SKILL.md).

## Why a separate bar

A code change is verified by a command whose output differs between "works" and
"does not". A live system has no such command: it is verified by OPERATING it, and
every partial way of operating it can come back green while the whole is broken.
The failure this bar exists for (operator incident 2026-07-12): a diagnostic edit
fixed the one path under test, the test passed, and the artifact that was handed
over no longer worked as a whole.

## "Passed" means all five, together

1. **End to end, in the CURRENT state.** The check runs against the artifact as it
   is NOW — after the last edit, not before it. Any edit, including a diagnostic
   one, invalidates every earlier green: restore the artifact first, then re-verify
   the whole.
2. **Every operation, not the test path.** The check drives the artifact the way an
   operator will: each control element, each entry point, each mode — individually.
   The path that was convenient to build with is one path among them.
3. **Several objects, not the one example.** The proof runs on multiple instances
   of the thing (fixtures, channels, pages, slots, inputs) — the one example used
   during construction is exactly the one most likely to be special-cased.
4. **Two independent read paths.** The result is confirmed through a second channel
   that does not share the mechanism that produced it — a readback, a capture, a
   measurement from the other side. The path that generated the result is not
   evidence for it; it only proves the command was sent.
5. **The whole, after the parts.** After the parts pass, the whole function is
   exercised once more in the final state. A green partial test on a broken whole
   is a false pass.

## What does NOT count as passed

- Syntax or load green: the file parses, the show opens, the patch compiles.
- One object exercised: the example fixture, the one channel, the test slot.
- One read path: the tool that sent the value reports the value it sent.
- A state before the last edit: a green run that predates any later change.
- A partial path green: the test route works, the operator route is unverified.
- A report of success from an agent or a tool that was not confirmed by a second
  path.

## Reporting

Name what was operated, on which objects, through which two read paths, and in
which state (after which edit). A claim without those four is not a pass — it is
the report of an intention.
