- **Settings template: the AI updates its own core — `claude plugin update`, `marketplace update`, `enable|disable|install brain-core*` and the push block on `core/` are allowed; `hook-coverage.py` reports a brain that lacks them.** (test: T1)

  **Why (measured 2026-10-18 on a macOS brain, core v1.4.4 old history, moving to 2.0.0):** in auto mode the classifier refused the switch from the beta to the stable channel (`enabledPlugins` edit, "Self-Modification") and `git -C core remote set-url --push origin DISABLED` ("Remote Repoint") — twice, the second time after the operator's word in chat. Operator order 2026-10-18 (in German, paraphrased): long-term independent work, and sensible permissions by default in every brain. `brain-update.sh` itself was already covered by `Bash(bash core/scripts/*)`; the channel switch and the push block were not.

  **allow (new):** `claude plugin update *`, `claude plugin marketplace update*`, `claude plugin enable|disable|install brain-core*`, `git -C core remote set-url --push origin DISABLED`. The channel switch goes through the CLI; a hand edit of `enabledPlugins` stays ask with every other settings edit. Other suites keep needing the operator's word (prefix `brain-core`).

  **Existing brains:** `hook-coverage.py` now counts the core update path like a permission into `core/` — the session start names each missing entry, so a brain learns it without reading this entry. A human adds them; the AI may not grant itself permissions.

  **Fixture:** `portability-smoke.sh` — an empty allow list names `Bash(claude plugin enable brain-core*)`; broader globs (`Bash(claude plugin *)`) stay silent.
