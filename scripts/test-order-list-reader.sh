#!/usr/bin/env bash
# covers: session-bootup order-list reader
#
# The bootup counts open orders from docs/maintenance/brain-scan-auftraege.md by section
# heading. Measured by a collaborator 2026-09-13: the English core template and the German
# reader named different strings, so a freshly bootstrapped brain showed no `task OPEN:`
# line while an open order sat in the list — invisible, not wrong. Both directions:
# German and English lists produce the line; a list with only done items produces none.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTUP="$ROOT/helpers/session-bootup.sh"
[ -f "$BOOTUP" ] || { echo "  --  session-bootup not in this layout"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# A minimal brain: git repo (the bootup reads branch/status), the order list, nothing else.
B="$T/brain"; mkdir -p "$B/docs/maintenance"
git -C "$B" init -q; git -C "$B" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
# -a: this count IS the verdict, and Git Bash may call the bootup's stream binary (OS-5).
run() { (cd "$B" && CLAUDE_PROJECT_DIR="$B" BRAIN_SELFTEST_BG=1 bash "$BOOTUP" 2>/dev/null | grep -ac '^task OPEN:'); }

printf '# Orders\n\n## Offen (bestellt)\n\n- [ ] **deutsche Bestellung** — von: Emil\n  id: a\n\n## Vorgeschlagen (abgeleitet)\n\n- [ ] **Vorschlag** — abgeleitet\n  id: b\n\n## Erledigt\n\n- [x] **fertig**\n' > "$B/docs/maintenance/brain-scan-auftraege.md"
[ "$(run)" = 1 ] && ok "1 German headings: one open order counted, the proposal not" || bad "1 German list: got $(run) task OPEN lines"

cp "$ROOT/templates/brain-scan-orders.md" "$B/docs/maintenance/brain-scan-auftraege.md"
[ "$(run)" = 1 ] && ok "2 English template (verbatim): its skeleton order is counted" || bad "2 English template: got $(run) task OPEN lines"

printf '# Orders\n\n## Open (ordered)\n\n## Proposed (derived)\n\n- [ ] **only a proposal**\n\n## Done\n\n- [x] **done**\n' > "$B/docs/maintenance/brain-scan-auftraege.md"
[ "$(run)" = 0 ] && ok "3 NEGATIVE: no open order -> no line, and the proposal does not count" || bad "3 negative: got $(run) task OPEN lines"

[ $fail = 0 ] && echo "test-order-list-reader: all green" || echo "test-order-list-reader: FAILURES"
exit $fail
