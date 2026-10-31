#!/bin/sh
# =============================================================================
# cm_instrument_trap_scan.sh — CM-INSTRUMENT-TRAP-SCAN gate (T231).
#
# ── What this gate does ─────────────────────────────────────────────────────
# Scans shell sources for the five MEASURED instrument-trap classes using
# constitution/scripts/gates/lib/instrument_trap_scan.sh (T220), and reports
# per-class counts.
#
# ── The rule this gate applies to ITSELF ────────────────────────────────────
# Before reporting a corpus clean it runs a CONTROL NEEDLE: it scans a
# known-trapped fixture and requires a finding. If the needle returns zero the
# gate reports SCANNER-BLIND, never "corpus clean" — a scanner that cannot see
# and a clean corpus produce the identical quiet zero (§11.4.201(6)(7)(b)), and
# a trap scanner that reported a clean corpus because it was broken would be
# the exact defect it exists to catch.
#
# ── Two modes ───────────────────────────────────────────────────────────────
#   <file>...   FILE mode. Prints one `FINDING <class> <file>:<line> <text>` per
#               hit and nothing else. rc 0 = clean, 1 = findings, 3 = scanner
#               blind. Deliberately quiet on a clean file: a banner containing
#               the word FINDING would make "no findings" unreadable.
#   (no args)   CORPUS mode. CN-VERDICT / CN-SUMMARY over the configured corpus
#               with per-class counts.
#
# ── Findings are advisory-by-count, not a hard corpus FAIL ──────────────────
# CORPUS mode records the per-class census and FAILs only on a scanner that
# cannot see or a corpus it could not read. The traps it finds are reported for
# triage: converting a pre-existing corpus census into a hard build refusal on
# day one would be a false-refusal engine against code that predates the rule
# (§11.4.201(1)), and the monotone-ratchet mechanism for that is §11.4.227's,
# not this gate's to invent.
#
# Usage : cm_instrument_trap_scan.sh [--corpus-root <dir>] [--fixtures <dir>] [<file>...]
# Deps  : POSIX sh, awk, grep, find. Read-only w.r.t. the repository.
# Xref  : §11.4.201 · T215 · T220 · docs/guides/shell_instrument_footguns.md
# =============================================================================

set -u

GATE_ID=CM-INSTRUMENT-TRAP-SCAN
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# The trap fixtures (the control needle included) are canon-owned test data shipped next to the gate, so the gate can
# prove it SEES in a standalone canon checkout as well as inside a consumer (it used to read them from a consumer
# path two levels above the canon, which does not exist standalone: a permanent BLIND). --fixtures still overrides.
FIXTURES="$SELF_DIR/fixtures/instrument_trap_scan/traps"
CORPUS_ROOT="$SELF_DIR"
FILES=""
while [ $# -gt 0 ]; do
    case $1 in
        --corpus-root) CORPUS_ROOT=$2; shift 2 ;;
        --fixtures)    FIXTURES=$2;    shift 2 ;;
        -h|--help)     sed -n '2,36p' "$0"; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do FILES="$FILES $1"; shift; done ;;
        -*) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
        *)  FILES="$FILES $1"; shift ;;
    esac
done

_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
LIBSCAN="$SELF_DIR/lib/instrument_trap_scan.sh"
if [ -f "$LIBSCAN" ]; then
    # shellcheck disable=SC1091
    . "$LIBSCAN"
fi
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

if ! command -v its_scan_file >/dev/null 2>&1; then
    printf 'SCANNER-ABSENT the trap-matcher library did not load from %s — every zero below would be meaningless, so nothing is reported clean\n' "$LIBSCAN" >&2
    exit 2
fi

# --- the control needle: can this scanner see a KNOWN trap? -------------------
# Returns 0 = sighted, 1 = blind (including "fixture unavailable": an unrunnable
# needle certifies nothing, so it is treated as blindness, not as compliance).
NEEDLE_FIXTURE="$FIXTURES/bad_03_inverted_match.sh"
NEEDLE_HITS=0
trap_scan_needle() {
    [ -r "$NEEDLE_FIXTURE" ] || return 1
    _tn_out=$(its_scan_file "$NEEDLE_FIXTURE" 2>/dev/null)
    NEEDLE_HITS=$(printf '%s\n' "$_tn_out" | grep -Ec '^FINDING trap_inverted_match ' || true)
    [ "${NEEDLE_HITS:-0}" -gt 0 ]
}

# --- FILE mode ----------------------------------------------------------------
if [ -n "$FILES" ]; then
    if ! trap_scan_needle; then
        printf 'SCANNER-BLIND the control needle over %s produced no hit, so this scanner cannot see a trap it is KNOWN to contain. Any zero it reports for your files says NOTHING (SS11.4.201(7)(b)). Reporting blindness, not a clean result.\n' "$NEEDLE_FIXTURE" >&2
        exit 3
    fi
    rc_any=0
    # shellcheck disable=SC2086
    for f in $FILES; do
        out=$(its_scan_file "$f" 2>&1); rc=$?
        [ -n "$out" ] && printf '%s\n' "$out"
        [ "$rc" -ne 0 ] && rc_any=1
    done
    exit "$rc_any"
fi

# --- CORPUS mode --------------------------------------------------------------
cn_reset

if trap_scan_needle; then
    cn_pass ITS-A0-SCANNER-SIGHTED "control needle over $NEEDLE_FIXTURE returned $NEEDLE_HITS hit(s) — the scanner can see a known trap, so a zero elsewhere is evidence"
else
    cn_blind ITS-A0-SCANNER-SIGHTED "control needle over $NEEDLE_FIXTURE returned 0 hits (or the fixture is unreadable) — this scanner cannot be shown to see anything, so no corpus result below can be believed"
    cn_summary "$GATE_ID"
    exit $?
fi

# The golden-GOOD half: the countermeasures must NOT be flagged, or the scanner
# is a false-refusal engine (§11.4.201(1)).
gg_bad=0
for g in good_01_pipeline_exit_status.sh good_02_relative_date_predicate.sh \
         good_03_inverted_match.sh good_04_query_class_mismatch.sh \
         good_05_greedy_display_transform.sh; do
    [ -r "$FIXTURES/$g" ] || continue
    o=$(its_scan_file "$FIXTURES/$g" 2>&1); r=$?
    if [ "$r" -ne 0 ] || [ -n "$o" ]; then
        gg_bad=$((gg_bad + 1))
        cn_fail ITS-A1-NO-FALSE-REFUSAL "the countermeasure fixture $g was FLAGGED ($o) — a scanner that fires on the fix is a false-refusal engine, and the first thing a team does with one is switch it off"
    fi
done
[ "$gg_bad" -eq 0 ] && cn_pass ITS-A1-NO-FALSE-REFUSAL "all five countermeasure fixtures scan clean — the scanner does not fire on the fix"

# Per-class census over the corpus.
if [ ! -d "$CORPUS_ROOT" ]; then
    cn_fail ITS-A2-CORPUS-READABLE "corpus root unreadable: $CORPUS_ROOT"
else
    CENSUS=$(mktemp) || exit 2
    # shellcheck disable=SC2064
    trap "rm -f '$CENSUS'" EXIT INT TERM
    nfiles=0
    for f in "$CORPUS_ROOT"/*.sh "$CORPUS_ROOT"/lib/*.sh; do
        [ -f "$f" ] || continue
        case $f in
            *"$FIXTURES"*) continue ;;
        esac
        nfiles=$((nfiles + 1))
        its_scan_file "$f" 2>/dev/null >> "$CENSUS"
    done
    if [ "$nfiles" -eq 0 ]; then
        cn_blind ITS-A2-CORPUS-READABLE "zero files were scanned under $CORPUS_ROOT — an empty scan is not a clean scan"
    else
        cn_pass ITS-A2-CORPUS-READABLE "$nfiles file(s) scanned under $CORPUS_ROOT"
        total=0
        for cls in $(its_class_ids); do
            n=$(grep -Ec "^FINDING ${cls} " "$CENSUS" || true)
            total=$((total + ${n:-0}))
            printf 'ITS-CENSUS\t%s\t%s\n' "$cls" "${n:-0}"
        done
        cn_pass ITS-A3-CENSUS-RECORDED "per-class trap census recorded: $total finding(s) across $nfiles file(s) — reported for triage, not as a build refusal (see the header)"
        [ "$total" -gt 0 ] && grep -E '^FINDING ' "$CENSUS"
    fi
fi

cn_summary "$GATE_ID"
exit $?
