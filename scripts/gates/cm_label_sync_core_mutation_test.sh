#!/usr/bin/env bash
# cm_label_sync_core_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LABEL-SYNC-CORE.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a CLEAN disposable fixture root (all structural artefacts) that MUST
# PASS (--structural-only), then applies six independent mutations on fresh
# copies, each of which MUST make the gate FAIL:
#   (1) go.mod missing   (2) cmd/label-busd/main.go missing
#   (3) internal/bus has no Go source   (4) labelctl.sh not executable
#   (5) CONTRACT.md missing the `follow_active` token   (6) CONTRACT.md absent
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_core_mutation_test.sh
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temp fixture under $TMPDIR, removed on EXIT. No network, no real-tree edit.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash + the sibling gate script.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 gate FAILs on every mutation AND PASSes on the clean fixture | 1 an
#   expectation was violated | 2 gate script missing.
# Cross-refs: §1.1, §11.4.182, §11.4.201. Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/cm_label_sync_core.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_mut.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
rc=0
build() { # $1 root
  local r="$1" s="$1/scripts/label-sync" d="$1/docs/label-sync" p
  mkdir -p "$s/cmd/labelctl" "$s/cmd/label-busd" "$d"
  echo 'module example.test/label-sync' >"$s/go.mod"
  echo 'package main' >"$s/cmd/labelctl/main.go"; echo 'package main' >"$s/cmd/label-busd/main.go"
  for p in state bus label model; do mkdir -p "$s/internal/$p"; echo "package $p" >"$s/internal/$p/x.go"; done
  printf '#!/usr/bin/env bash\n# Purpose : x\n# Usage   : x\n# Exit    : x\n' >"$s/labelctl.sh"; chmod +x "$s/labelctl.sh"
  echo '#!/usr/bin/env bash' >"$s/prove_mutations.sh"
  echo '# readme' >"$d/README.md"
  echo 'events.jsonl snapshot.json active.json seq follow_active alias_switch 11.4.182' >"$d/CONTRACT.md"
}
expect() { # want(pass|fail) desc root
  if bash "$GATE" --root "$3" --structural-only --quiet >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "✅ META OK:   $2 — gate ${got}ed as required"
  else echo "❌ META FAIL: $2 — gate ${got}ed, wanted $1"; rc=1; fi
}
build "$TMP/clean"; expect pass "clean fixture" "$TMP/clean"
r="$TMP/m1"; build "$r"; rm "$r/scripts/label-sync/go.mod"; expect fail "go.mod missing" "$r"
r="$TMP/m2"; build "$r"; rm "$r/scripts/label-sync/cmd/label-busd/main.go"; expect fail "label-busd main missing" "$r"
r="$TMP/m3"; build "$r"; rm "$r/scripts/label-sync/internal/bus/x.go"; expect fail "internal/bus empty" "$r"
r="$TMP/m4"; build "$r"; chmod -x "$r/scripts/label-sync/labelctl.sh"; expect fail "labelctl.sh not executable" "$r"
r="$TMP/m5"; build "$r"; sed -i 's/follow_active//' "$r/docs/label-sync/CONTRACT.md"; expect fail "CONTRACT lacks follow_active" "$r"
r="$TMP/m6"; build "$r"; rm "$r/docs/label-sync/CONTRACT.md"; expect fail "CONTRACT absent" "$r"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
