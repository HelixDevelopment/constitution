#!/usr/bin/env bash
# covenant_propagation_engine_compact_mutation_test.sh — §1.1 paired-mutation test for the COMPACT-INDEX
# equivalence and H2 block-boundary branches of lib/covenant_propagation_engine.sh.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The engine change of 2026-10-14 added a PASS path (a one-line compact index entry `- §N … [full → <path>]`
# stands in for the full block) and a new block boundary (`## `). A new PASS path in a gate is a relaxation, so
# it needs a test that FAILS when the relaxation is widened. The round-2 independent review of the remedy batch
# of 2026-10-14 (pre-build remedies) wrote five engine mutants (ME1-ME5) that ALL survived the committed fixtures; the
# fix added fixtures 9-18 to lib/covenant_propagation_mutation_engine.sh plus a sixth guard (ME6). This test
# applies each mutant VERBATIM (exact old -> new text) to an OUT-OF-REPO copy of the engine and requires the
# NAMED fixture(s) to flip from "META OK" to "META FAIL".
#
#   ME1 duplicated target accepted   (`-eq 1` -> `-ge 1`)              must flip COMPACT-DUP-TARGET
#   ME2 `..` / absolute pointer allowed                                 must flip COMPACT-DOTDOT
#   ME3 mirror trailer dropped from the compared text                   must flip COMPACT-TRAILER-BAD + -OK
#   ME4 H2 block boundary reverted                                      must flip H2-BOUNDARY
#   ME5 `[full → …]` honoured on ANY first line, not only `- §N`        must flip COMPACT-NOT-BULLET
#   ME6 carrier-basename target restriction removed                     must flip COMPACT-AT-CARRIER
#
# Steps: BASELINE (every fixture META OK, rc 0) · each mutant (named flip + rc != 0, and the mutant text was
# applied exactly once and still parses) · NEGATIVE CONTROL (a comment-only edit flips nothing) · RESTORED
# (baseline again) · UNTOUCHED (the tracked engine is byte-identical before and after).
#
# Usage: covenant_propagation_engine_compact_mutation_test.sh
# Exit: 0 every pair demonstrated · 1 a pair not demonstrated · 2 environment error.
# Wired: covenant_propagation_suite.sh `gates` mode runs it as the ENGINE-SELFTEST entry.
# Side-effects: a mktemp sandbox under $TMPDIR, removed on exit. The real tree is never edited.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENGINE="$HERE/lib/covenant_propagation_engine.sh"
PACK="$HERE/covenant_propagation_anchors.tsv"
for f in "$ENGINE" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh" "$PACK"; do
    [ -f "$f" ] || { echo "ENV: missing $f"; exit 2; }
done
GATE_NAME="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1; exit}' "$PACK")"
ANCHOR="$(awk -F'\t' -v g="$GATE_NAME" '/^#/{next} $1==g {print $2; exit}' "$PACK")"
SLUG="${ANCHOR#11.4.}"
WRAP="$HERE/cm_covenant_114_${SLUG}_propagation.sh"
MWRAP="$HERE/cm_covenant_114_${SLUG}_propagation_mutation_test.sh"
[ -n "$GATE_NAME" ] && [ -f "$WRAP" ] && [ -f "$MWRAP" ] || { echo "ENV: no usable gate row/wrappers for '$GATE_NAME'"; exit 2; }

SUM_BEFORE="$(sha256sum "$ENGINE" | cut -d' ' -f1)"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cpe_compact_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT INT TERM
SB="$TMPD/gates"
mkdir -p "$SB/lib"
cp "$ENGINE" "$HERE/lib/pointer_carrier.sh" "$HERE/lib/covenant_propagation_mutation_engine.sh" "$SB/lib/"
cp "$PACK" "$WRAP" "$MWRAP" "$SB/"

fails=0
ok()  { echo "  [ok]   $*"; }
bad() { fails=$((fails + 1)); echo "  [FAIL] $*"; }
run_meta() { env -u COVENANT_PROPAGATION_CARRIERS -u COVENANT_PROPAGATION_ANCHORS bash "$SB/$(basename "$MWRAP")" 2>&1; }
line_state() { # $1 output  $2 fixture-name prefix -> OK | FAIL | ABSENT
    if grep -q "^✅ META OK:   $2 " <<<"$1"; then echo OK
    elif grep -q "^❌ META FAIL: $2 " <<<"$1"; then echo FAIL
    else echo ABSENT; fi
}
FIXTURES="COMPACT-OK COMPACT-MISSING-TARGET COMPACT-DUP-TARGET COMPACT-TAMPERED COMPACT-DOTDOT COMPACT-TRAILER-BAD COMPACT-TRAILER-OK H2-BOUNDARY COMPACT-NOT-BULLET COMPACT-AT-CARRIER"

echo "=== §1.1 engine-mutant pairs for the compact-index / H2 branches (gate ${GATE_NAME}, anchor §${ANCHOR}) ==="
base="$(run_meta)"; base_rc=$?
all_ok=1
for fx in $FIXTURES; do [ "$(line_state "$base" "$fx")" = OK ] || { all_ok=0; echo "    baseline fixture not OK: $fx"; }; done
if [ "$base_rc" -eq 0 ] && [ "$all_ok" -eq 1 ]; then ok "BASELINE: rc=0 and all 10 compact/H2 fixtures META OK"
else bad "BASELINE broken (rc=$base_rc) — no flip below would mean anything"; echo "$base" | tail -5; echo "MUTATION PAIR NOT DEMONSTRATED"; exit 1; fi

apply() { # $1 old  $2 new -> edits $SB/lib engine copy; rc 0 iff exactly one replacement and it parses
    python3 - "$SB/lib/covenant_propagation_engine.sh" "$1" "$2" <<'PY' || return 1
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
if s.count(old) != 1:
    sys.exit(3)
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
    bash -n "$SB/lib/covenant_propagation_engine.sh"
}
restore() { cp "$ENGINE" "$SB/lib/covenant_propagation_engine.sh"; }

pair() { # $1 id  $2 old  $3 new  $4.. fixtures that must flip
    local id="$1" old="$2" new="$3" out rc fx st
    shift 3
    restore
    if ! apply "$old" "$new"; then bad "$id: mutant text not applied exactly once (or the mutant does not parse) — re-anchor it"; return; fi
    out="$(run_meta)"; rc=$?
    for fx in "$@"; do
        st="$(line_state "$out" "$fx")"
        if [ "$st" = FAIL ]; then ok "$id: fixture $fx flipped PASS -> FAIL"
        else bad "$id: fixture $fx is '$st' under the mutant (expected FAIL) — mutant SURVIVES"; fi
    done
    if [ "$rc" -ne 0 ]; then ok "$id: mutated meta-test rc=$rc (non-zero)"; else bad "$id: mutated meta-test rc=0"; fi
}

pair ME1 \
  'if [ "${_cpe_tcount:-0}" -eq 1 ]; then' \
  'if [ "${_cpe_tcount:-0}" -ge 1 ]; then' \
  COMPACT-DUP-TARGET
pair ME2 \
  'case "$_cpe_ptr" in /*|*..*) _cpe_ptr="" ;; esac' \
  'case "$_cpe_ptr" in __never__) _cpe_ptr="" ;; esac' \
  COMPACT-DOTDOT
pair ME3 \
  'h="$(printf '"'"'%s'"'"' "${_cpe_tt}${block_text#"$_cpe_first"}" | _cpe_sha256)"' \
  'h="$(printf '"'"'%s'"'"' "${_cpe_tt}" | _cpe_sha256)"' \
  COMPACT-TRAILER-BAD COMPACT-TRAILER-OK
pair ME4 \
  "local GENERIC_BLOCK_RE='^(\\*\\*|### |- )§11\\.4\\.[0-9]|^## '" \
  "local GENERIC_BLOCK_RE='^(\\*\\*|### |- )§11\\.4\\.[0-9]'" \
  H2-BOUNDARY
pair ME5 \
  'if [[ "$_cpe_first" =~ ^-\ §11\.4\.[0-9.]+.*\[full\ →\ ([^]#]+) ]]; then' \
  'if [[ "$_cpe_first" =~ \[full\ →\ ([^]#]+) ]]; then' \
  COMPACT-NOT-BULLET
pair ME6 \
  'case "${_cpe_ptr##*/}" in CLAUDE.md|AGENTS.md|QWEN.md|GEMINI.md) _cpe_ptr="" ;; esac' \
  'case "${_cpe_ptr##*/}" in __never__) _cpe_ptr="" ;; esac' \
  COMPACT-AT-CARRIER

# NEGATIVE CONTROL: a comment-only edit must flip nothing (the harness is not a rubber stamp for "any change").
restore
if apply 'local GENERIC_BLOCK_RE=' '# negative-control comment
    local GENERIC_BLOCK_RE='; then
    nc="$(run_meta)"; nc_rc=$?
    nc_ok=1; for fx in $FIXTURES; do [ "$(line_state "$nc" "$fx")" = OK ] || nc_ok=0; done
    if [ "$nc_rc" -eq 0 ] && [ "$nc_ok" -eq 1 ]; then ok "NEGATIVE CONTROL: a comment-only edit flips no fixture (rc=0)"
    else bad "NEGATIVE CONTROL: a comment-only edit changed the verdict (rc=$nc_rc) — the harness cannot tell behaviour from text"; fi
else bad "NEGATIVE CONTROL: could not apply the comment-only edit"; fi

restore
rest="$(run_meta)"; rest_rc=$?
[ "$rest_rc" -eq 0 ] && ok "RESTORED: unmutated engine copy is back to rc=0" || bad "RESTORED: rc=$rest_rc after restore"
SUM_AFTER="$(sha256sum "$ENGINE" | cut -d' ' -f1)"
[ "$SUM_BEFORE" = "$SUM_AFTER" ] && ok "tracked library unchanged (sha256 $SUM_AFTER)" || bad "tracked engine changed during the test ($SUM_BEFORE -> $SUM_AFTER)"

if [ "$fails" -eq 0 ]; then echo "=== MUTATION PAIR VALID: 6 engine mutants killed, negative control clean ==="; exit 0; fi
echo "=== MUTATION PAIR NOT DEMONSTRATED: $fails failure(s) ==="; exit 1
