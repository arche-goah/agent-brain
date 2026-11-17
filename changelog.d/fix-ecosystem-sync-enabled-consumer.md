- **`ecosystem-sync.py`: the consumer plugin of a repo is the enabled one, not the first one installed**
  (test: `scripts/test-ecosystem-sync.sh`, two new cases: the switched-off channel listed first loses to the
  enabled one; the brain's local settings layer overrides the user layer) (level: writer; higher: design - not
  taken, the install registry has no notion of "current channel", the settings layers do; debt: a repo two
  enabled plugins deliver still takes the first of them). Measured on the macOS instance (coherence register
  2026-11-16): three installed plugins came from the core repo (old stable channel, old beta channel, the core's
  own marketplace); the first in the install registry won, so `--write` kept recording the switched-off old
  channel as the core's consumer. The enabled state is read from the user, project and local settings, a later
  layer overriding an earlier one.
