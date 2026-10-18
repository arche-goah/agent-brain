#!/usr/bin/env python3
"""Fixture for plugin_records.own_record: the record that applies to THIS brain.

The measured case (2026-10-18, a Mac mini): the first record was another project's 1.3.41,
the user record was 2.0.0 — device-status read the first one and reported the wrong version.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plugin_records import own_record  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    print(("  ok    " if cond else "  FAIL  ") + msg)
    fails += 0 if cond else 1


with tempfile.TemporaryDirectory() as t:
    this, other = os.path.join(t, "this-brain"), os.path.join(t, "other-project")
    os.makedirs(this); os.makedirs(other)
    measured = [{"scope": "project", "projectPath": other, "version": "1.3.41"},
                {"scope": "user", "version": "2.0.0"}]
    check(own_record(measured, this)["version"] == "2.0.0",
          "another project's record first: the user record is this brain's")
    mine = measured + [{"scope": "local", "projectPath": this, "version": "2.0.1"}]
    check(own_record(mine, this)["version"] == "2.0.1", "this brain's own project record wins over the user record")
    check(own_record([{"scope": "project", "projectPath": other, "version": "1.3.41"}], this) is None,
          "only another project's record: nothing applies here")
    check(own_record([], this) is None, "no record: None")
    # NEGATIVE CONTROL: what the old reader did with the measured list.
    check(measured[0]["version"] == "1.3.41", "control: rec[0] of the measured list is the stranger's 1.3.41")

print(f"plugin-records-test: {'all passed' if not fails else str(fails) + ' FAILED'}")
sys.exit(1 if fails else 0)
