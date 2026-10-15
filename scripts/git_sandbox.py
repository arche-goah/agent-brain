#!/usr/bin/env python3
"""A test's throwaway git repo obeys no git config of the host machine.

Importing this module is the whole call: it points GIT_CONFIG_GLOBAL at a temp file that
holds only a neutral identity and sets GIT_CONFIG_NOSYSTEM, so the host's ~/.gitconfig and
/etc/gitconfig never reach a fixture repo. Local (per-repo) config is untouched — a test
that sets its own core.hooksPath keeps working.

WHY (measured 2026-10-14 on an instance whose global `core.hooksPath` carries its brain's
pre-commit): the hook ran INSIDE shared-memory-audience-test's fixture repo, its
shared-memory step saw the fixture's parties.json, refused the "old findings" commit, and
the test died with CalledProcessError — green in CI, red on that machine, for a month.
The brain's own self-test reported the failure; nothing said why. Same shape as
test-local-machinery.sh, which already isolates its global config by hand.

Idempotent across imports (GIT_SANDBOX marks the isolated process); the temp file is
removed at exit. Fixture: scripts/test-git-sandbox.sh (both directions).
"""
import atexit
import os
import tempfile


def isolate() -> str:
    if os.environ.get("GIT_SANDBOX"):
        return os.environ["GIT_CONFIG_GLOBAL"]
    fd, path = tempfile.mkstemp(prefix="git-sandbox-", suffix=".gitconfig")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("[user]\n\tname = sandbox\n\temail = sandbox@example.invalid\n")
    os.environ.update(GIT_CONFIG_GLOBAL=path, GIT_CONFIG_NOSYSTEM="1", GIT_SANDBOX="1")
    atexit.register(lambda: os.path.exists(path) and os.remove(path))
    return path


isolate()
