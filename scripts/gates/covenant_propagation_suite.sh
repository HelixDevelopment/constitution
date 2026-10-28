#!/usr/bin/env bash
# covenant_propagation_suite.sh — batch runner for the data-pack-driven
# CM-COVENANT-114-<N>-PROPAGATION gate family and its §1.1 mutation pairs.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Runs every gate named in `covenant_propagation_anchors.tsv` (mode `gates`)
# or every paired §1.1 mutation test (mode `mutations`) and prints one
# `<gate> <exit-code> <verdict>` line per entry plus a summary. Exists so the
# family can be exercised and evidenced in one shot (§11.4.262 machine-created
# evidence) without hand-listing 29 script names anywhere. In `gates` mode it
# also runs the shared engine's own self-test
# (covenant_propagation_engine_compact_mutation_test.sh) as one extra entry,
# CM-COVENANT-PROPAGATION-ENGINE-SELFTEST, the paired mutation test of this
# suite's own failure accounting as another, CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING,
# and the paired test of the consumer-side verdict-set checker
# (suite_verdict_set_check.sh) as a third, CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK.
# Consumers should read this suite's output through that checker (profile
# covenant-gates), not through the exit code and summary tally alone.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   covenant_propagation_suite.sh gates [--root <consumer-root>]
#   covenant_propagation_suite.sh mutations
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   `gates` is read-only. `mutations` delegates to the per-gate mutation
#   wrappers, which build + remove their own mktemp fixtures (the real tree is
#   never mutated).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, the sibling wrappers + data pack. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.227(A)/(B), §11.4.251 (data-pack-driven, no hand-maintained list),
#   §1.1, §11.4.262.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every entry exited 0.  1 — at least one entry exited non-zero.
#   2 — environment error (bad mode / data pack missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# F5: default-root helper (defined in the shared engine; sourcing only defines functions)
. "${HERE}/lib/covenant_propagation_engine.sh"
PACK="${COVENANT_PROPAGATION_ANCHORS:-${HERE}/covenant_propagation_anchors.tsv}"
MODE="${1:-}"; shift || true

[ -r "$PACK" ] || { echo "suite: data pack not readable: $PACK" >&2; exit 2; }
case "$MODE" in gates|mutations) ;; *) sed -n '1,32p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;; esac

rows="$(awk -F'\t' '/^#/{next} NF>=2 && $1!="" {print $1"\t"$2}' "$PACK")"
[ -n "$rows" ] || { echo "suite: zero rows in $PACK" >&2; exit 2; }

# ── Carrier-set reuse (§11.4.201-safe optimization) ─────────────────────────
# Carrier discovery is ANCHOR-INDEPENDENT: every gate audits the identical file
# set. Walking the tree once here and handing the result to all N gates removes
# N-1 redundant traversals (measured on a 1.13M-directory consumer: 9.3 s each,
# 30 gates -> 279 s of pure duplication). The engine re-validates every listed
# path and FAILS CLOSED on a stale entry, so this can never silently narrow the
# audited set.
# MODE GUARD (§11.4.201(1) false-positive fix, 2026-08-26): this reuse is an
# optimization for `gates` ONLY. In `mutations` mode every wrapper builds its own
# mktemp fixture and runs the gate with --root <fixture>; exporting the REAL fleet
# carrier list makes the engine audit the real tree instead of the fixture, so 3 of
# the 8 §1.1 fixtures misclassify and EVERY mutation test reports 5/8 + rc=1.
# Measured 2026-08-26: standalone mutation test = 8/8 rc=0; with the export in
# force = 5/8 rc=1 (causality proven by the presence/absence of this one variable).
if [ "$MODE" = "gates" ] && [ -z "${COVENANT_PROPAGATION_CARRIERS:-}" ]; then
    _suite_root=""; _prev=""
    for _a in "$@"; do
        [ "$_prev" = "--root" ] && _suite_root="$_a"
        _prev="$_a"
    done
    _suite_root="${_suite_root:-${CONSUMER_ROOT:-$(covenant_propagation_default_root)}}"
    if [ -d "$_suite_root" ]; then
        _suite_cl="$(mktemp -t covenant_carriers.XXXXXX)"
        trap 'rm -f "$_suite_cl"' EXIT INT TERM
        # Mirror the engine's own prune set + the consumer exclusion file.
        _suite_excl=()
        _suite_ef="${COVENANT_PROPAGATION_EXCLUSIONS:-${_suite_root}/config/covenant_propagation_exclusions.tsv}"
        if [ -r "$_suite_ef" ]; then
            while IFS=$'\t' read -r _g _c _j; do
                case "${_g:-}" in ''|'#'*) continue ;; esac
                _suite_excl+=( -o -path "$_g" )
            done < "$_suite_ef"
        fi
        find "$_suite_root" \
            \( -path '*/node_modules' -o -path '*/.git' -o -path '*/out' \
               -o -path '*/build' -o -path '*/dist' -o -path '*/prebuilts' \
               -o -path '*/external' -o -path '*/vendor' -o -path '*/target' \
               ${_suite_excl[@]+"${_suite_excl[@]}"} \) -prune \
            -o \( -type f \( -name 'CLAUDE.md' -o -name 'AGENTS.md' \
               -o -name 'QWEN.md' -o -name 'GEMINI.md' \) -print \) 2>/dev/null | sort > "$_suite_cl"
        if [ -s "$_suite_cl" ]; then
            export COVENANT_PROPAGATION_CARRIERS="$_suite_cl"
            echo "suite: carrier set computed once ($(wc -l < "$_suite_cl") carriers) — reused across all gates"
        fi
    fi
fi

total=0; bad=0
# Inner mode (round-5 review N17, the inner-flag row of the verdict-set rule table): the accounting sandbox
# sets COVENANT_PROPAGATION_SUITE_INNER, which skips the ACCOUNTING and VERDICT-SET entries. Say so in the
# output, so a consumer run that INHERITED the flag is refused by suite_verdict_set_check.sh (rule R-INNER)
# instead of reading a shortened entry set. Printed before the entry table, never inside it.
if [ -n "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then
    echo "INNER-MODE: COVENANT_PROPAGATION_SUITE_INNER set — the ACCOUNTING and VERDICT-SET self-test entries are skipped"
fi
printf '%-36s %-5s %s\n' "GATE" "EXIT" "VERDICT"
printf '%-36s %-5s %s\n' "------------------------------------" "-----" "----------------------------------"
# ENGINE SELF-TEST (gates mode). The engine's compact-index PASS path and H2 boundary
# are guarded by covenant_propagation_engine_compact_mutation_test.sh (six reviewer-
# authored engine mutants, each must flip a named fixture). Running it HERE puts it on
# the seam the consumer's pre-build already runs (CM-COVENANT-PROPAGATION-SUITE), so the
# guard is executed, not merely present on disk (§11.4.205). It is one extra entry; a
# failure counts as a non-zero entry like any gate. It runs only where the shared engine
# sits beside this suite (a sandbox that stubs the gates without the engine has nothing
# to self-test, and every real gate needs the engine, so its absence already FAILs them).
# A present engine with an ABSENT self-test is a FAIL, never a skip.
if [ "$MODE" = "gates" ] && [ -f "${HERE}/lib/covenant_propagation_engine.sh" ]; then
    _st="${HERE}/covenant_propagation_engine_compact_mutation_test.sh"
    if [ -f "$_st" ]; then
        out="$(env -u COVENANT_PROPAGATION_CARRIERS bash "$_st" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -E '^=== MUTATION PAIR' | tail -1)"
        [ -n "$verdict" ] || verdict="$(printf '%s\n' "$out" | tail -1)"
    else
        rc=2; verdict="engine self-test missing: $_st"
    fi
    total=$((total+1))
    # (written as an if, not the `[ ] || bad=` form the gate loop uses, so a consumer's
    # paired mutation that rewrites the loop's single accounting line still finds it once)
    if [ "$rc" -ne 0 ]; then bad=$((bad+1)); fi
    printf '%-36s %-5s %s\n' "CM-COVENANT-PROPAGATION-ENGINE-SELFTEST" "$rc" "$verdict"
fi
# SUITE ACCOUNTING SELF-TEST (gates mode, round-3 review N1 of the remedy batch). The
# SELFTEST entry above is only worth something if a failing self-test reaches this
# suite's exit code and summary. covenant_propagation_suite_accounting_mutation_test.sh
# copies THIS suite into a sandbox, drives a failing self-test through it (the real
# compact test against a mutated engine, plus stub self-tests), and requires the
# failure to reach the exit code, the "non-zero" tally and the printed entry; it then
# applies seven accounting mutants to the copy and requires each one to be seen. It is
# counted with its own `case` line, not the SELFTEST `if` line or the gate loop's line,
# so one edit cannot silence both the self-test and this check. The sandbox runs set
# COVENANT_PROPAGATION_SUITE_INNER, which skips this entry there (no recursion).
# Same presence rule as the SELFTEST entry: missing is a FAIL, never a skip.
if [ "$MODE" = "gates" ] && [ -f "${HERE}/lib/covenant_propagation_engine.sh" ] \
   && [ -z "${COVENANT_PROPAGATION_SUITE_INNER:-}" ]; then
    _at="${HERE}/covenant_propagation_suite_accounting_mutation_test.sh"
    if [ -f "$_at" ]; then
        out="$(env -u COVENANT_PROPAGATION_CARRIERS bash "$_at" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -E '^=== ' | tail -1)"
        [ -n "$verdict" ] || verdict="$(printf '%s\n' "$out" | tail -1)"
    else
        rc=2; verdict="suite accounting self-test missing: $_at"
    fi
    total=$((total+1))
    case "$rc" in 0) ;; *) bad=$((bad+1)) ;; esac
    printf '%-36s %-5s %s\n' "CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING" "$rc" "$verdict"
fi
# VERDICT-SET CHECK SELF-TEST (gates mode, round-4 review N6/N7 of the remedy batch). Consumers read this
# suite's output through suite_verdict_set_check.sh (profile covenant-gates): it requires the named entries
# above and cross-checks the printed entry rcs against the summary tally, so a silenced entry (reviewer
# mutant RX1) or an uncounted failing entry cannot read as PASS. Its paired test applies RX1 and RX3
# verbatim to real suite copies; running it here puts it on the seam the consumer's pre-build already runs.
# Same presence rule: missing is a FAIL. Skipped inside the accounting sandbox (COVENANT_PROPAGATION_SUITE_INNER),
# written with a different guard expression from the ACCOUNTING entry's so one edit cannot skip both.
if [ "$MODE" = "gates" ] && [ -f "${HERE}/lib/covenant_propagation_engine.sh" ] \
   && [ "${COVENANT_PROPAGATION_SUITE_INNER:-}" = "" ]; then
    _vt="${HERE}/suite_verdict_set_check_mutation_test.sh"
    if [ -f "$_vt" ]; then
        out="$(env -u COVENANT_PROPAGATION_CARRIERS bash "$_vt" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -E '^=== ' | tail -1)"
        [ -n "$verdict" ] || verdict="$(printf '%s\n' "$out" | tail -1)"
    else
        rc=2; verdict="verdict-set check self-test missing: $_vt"
    fi
    total=$((total+1))
    test "$rc" = 0 || bad=$((bad+1))
    printf '%-36s %-5s %s\n' "CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK" "$rc" "$verdict"
fi
while IFS=$'\t' read -r gate anchor; do
    [ -n "$gate" ] || continue
    slug="${anchor#11.4.}"
    if [ "$MODE" = "gates" ]; then
        script="${HERE}/cm_covenant_114_${slug}_propagation.sh"
        out="$(bash "$script" "$@" 2>&1)"; rc=$?
        verdict="$(printf '%s\n' "$out" | grep -E '^(✅|❌) CM-COVENANT' | tail -1)"
        [ -n "$verdict" ] || verdict="$(printf '%s\n' "$out" | tail -1)"
        stats="$(printf '%s\n' "$out" | grep -E '^CM-COVENANT.*single-block-PRESENT' | tail -1)"
        [ -z "$stats" ] || verdict="${stats#*: }"
    else
        script="${HERE}/cm_covenant_114_${slug}_propagation_mutation_test.sh"
        out="$(bash "$script" 2>&1)"; rc=$?
        _ok_n="$(printf '%s\n' "$out" | grep -cE '^✅ META OK')"
        _fx_n="$(printf '%s\n' "$out" | grep -E '^(✅ META OK|❌ META FAIL):' | grep -vc 'failed the §1.1 discriminator')"
        verdict="${_ok_n} of ${_fx_n} fixtures correct"
    fi
    total=$((total+1))
    [ "$rc" -eq 0 ] || bad=$((bad+1))
    printf '%-36s %-5s %s\n' "$gate" "$rc" "$verdict"
done <<< "$rows"

echo "----------------------------------------------------------------------"
# §11.4.6 SCOPE TRANSPARENCY. A verdict without its audited surface is
# scope-blind: "34 entries, 34 exit-0" reads identically whether the run
# audited 150 carriers or 8. FORENSIC (2026-08-20): a fresh NON-RECURSIVE
# clone of the committed state audits 8 carriers (only the parent tracks
# any; the rest live inside uninitialised submodules) while the developer
# worktree audits 150 — a ~19x difference behind an identical headline.
# Coverage here is a function of submodule init state, so the count MUST
# travel with the verdict, and a suspiciously small set MUST say so.
_suite_ncar="${COVENANT_PROPAGATION_CARRIERS:+$(wc -l < "$COVENANT_PROPAGATION_CARRIERS" 2>/dev/null)}"
_suite_ncar="${_suite_ncar:-unknown}"
echo "suite(${MODE}): ${total} entries, $((total-bad)) exit-0, ${bad} non-zero — over ${_suite_ncar} carrier(s)"
if [ "$_suite_ncar" != "unknown" ] && [ "$_suite_ncar" -lt 20 ] 2>/dev/null; then
    echo "suite(${MODE}): NOTE — only ${_suite_ncar} carrier(s) audited. On a non-recursive clone most"
    echo "suite(${MODE}):        carriers live inside uninitialised submodules and are NOT audited."
    echo "suite(${MODE}):        A GREEN verdict here covers a far smaller surface than a fully"
    echo "suite(${MODE}):        populated checkout (§11.4.6 — the count is part of the claim)."
fi
[ "$bad" -eq 0 ] || exit 1
exit 0
