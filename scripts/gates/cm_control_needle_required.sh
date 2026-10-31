#!/bin/sh
# =============================================================================
# cm_control_needle_required.sh — CM-CONTROL-NEEDLE-REQUIRED gate (T227).
#
# ── What this gate asserts (FR-005, FR-006) ─────────────────────────────────
#   CNR-A0  the E4 control-needle evaluator is present            (structural)
#   CNR-A1  GOLDEN-GOOD    : a needled zero is ACCEPTED              (RUNTIME)
#   CNR-A2  GOLDEN-BAD     : an UNNEEDLED zero is REFUSED            (RUNTIME)
#   CNR-A3  GOLDEN-BAD     : a BLIND needle is REFUSED with a reason
#                            DISTINCT from the absent-needle one     (RUNTIME)
#   CNR-A4  NEGATIVE CONTROL: a same-path needle certifies, a
#                            different-path needle does not          (RUNTIME)
#   CNR-A5  the rule is WIRED at the acceptance seam               (structural)
#
# ── Why A1 and A4's positive leg exist ──────────────────────────────────────
# A gate that refused every zero would satisfy A2 and A3 while being a
# false-refusal engine, and per §11.4.201(1) a false refusal is a FAIL-bluff
# exactly as serious as a false pass: it condemns correct behaviour and teaches
# people to route around the verifier. A1/A4 are the guard in that direction.
#
# ── Why A3 requires the reasons to be DISTINCT ──────────────────────────────
# `control_needle_ABSENT` and `control_needle_BLIND` name two different
# defects. ABSENT means nobody certified the instrument; BLIND means somebody
# did and it could not see. Collapsing them hides which of the two occurred and
# therefore hides who has to fix what.
#
# ── Why A5 is a hard assertion and MAY FAIL ─────────────────────────────────
# §11.4.108: source-present is not runtime-active. A rule implemented in a
# library that no acceptance seam consults refuses nothing. If A5 FAILs the
# gate is WORKING; the honest reading is that the reader seam has not been
# wired yet (feature task T224), NOT that this gate is broken.
#
# ── Absence discipline ──────────────────────────────────────────────────────
# A5's absence is certified by a class-matched control needle through the SAME
# tool and flags (§11.4.201(7)(b)). An uncertified zero is reported BLIND and
# fails the gate — undecided reported as intact is the bluff §11.4.201(6)
# forbids.
#
# Usage : cm_control_needle_required.sh [--reader <path>] [--selftest]
# Output: CN-VERDICT<TAB><ID><TAB><PASS|FAIL|BLIND|SKIP><TAB><msg>, then CN-SUMMARY.
#         Exit 0 only when nothing FAILed and nothing was BLIND.
# Deps  : POSIX sh, grep, mktemp. Read-only w.r.t. the repository.
# Xref  : FR-005 · FR-006 · data-model.md E4 · contracts/gate-verdict.md
# =============================================================================

set -u

GATE_ID=CM-CONTROL-NEEDLE-REQUIRED
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# Default root = where the gate LIVES (the superproject when vendored as a submodule, else the canon itself), never the
# directory above the canon: "../../.." from a standalone canon is a foreign directory outside the repository.
# shellcheck disable=SC1091
[ -r "$SELF_DIR/../lib/default_scan_root.sh" ] && . "$SELF_DIR/../lib/default_scan_root.sh" && REPO=$(cm_default_scan_root "$SELF_DIR") || REPO=""
# A copy of the gate staged somewhere without scripts/lib (a paired-mutation sandbox) falls back to the legacy
# consumer-layout depth it was staged at.
[ -n "$REPO" ] || REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer (only way to get the honest SKIP)

READER="$REPO/scripts/lib/critical_blocker_gate.sh"
DO_SELFTEST=0
while [ $# -gt 0 ]; do
    case $1 in
        --reader) READER=$2; shift 2 ;;
        --standalone-canon) STANDALONE=1; shift ;;
        --selftest) DO_SELFTEST=1; shift ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# Source order matters: clear the positional parameters first so neither
# library's `--selftest` tail sees our own arguments.
_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
CN_LIB="$SELF_DIR/lib/control_needle.sh"
[ -f "$CN_LIB" ] && { CN_E4_SELF_DIR="$SELF_DIR/lib"; export CN_E4_SELF_DIR; . "$CN_LIB"; }
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

cn_reset
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_cnr.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

QCMD="grep -Ec 'control_needle_ABSENT|control_needle_BLIND' evidence.txt"

# --- A0 -----------------------------------------------------------------------
if [ -f "$CN_LIB" ] && command -v cn_evaluate >/dev/null 2>&1; then
    cn_pass CNR-A0-EVALUATOR-PRESENT "the E4 control-needle evaluator is present and its API loaded: $CN_LIB"
else
    cn_fail CNR-A0-EVALUATOR-PRESENT "the E4 control-needle evaluator is absent or did not load: $CN_LIB — every assertion below is undecidable without it"
    cn_summary "$GATE_ID"; exit $?
fi

# --- A1 GOLDEN-GOOD: a needled zero is accepted --------------------------------
cn_record "$TMP/good.json" 'control_needle_ABSENT|known-present' 4 true "$QCMD"
_out=$(cn_evaluate "$TMP/good.json" 2>&1); _rc=$?
if [ "$_rc" -eq 0 ]; then
    cn_pass CNR-A1-NEEDLED-ZERO-ACCEPTED "a zero certified by a hitting, class-matched needle is ACCEPTED as a real absence: $_out"
else
    cn_fail CNR-A1-NEEDLED-ZERO-ACCEPTED "a properly needled zero was REFUSED (rc=$_rc): $_out — this is a false-refusal engine, forbidden as strongly as a false pass (§11.4.201(1))"
fi

# --- A2 GOLDEN-BAD: an unneedled zero is refused -------------------------------
printf '{"needle":"none"}\n' > "$TMP/absent.json"
_out=$(cn_evaluate "$TMP/absent.json" 2>&1); _rc=$?
_abs_reason=$_out
if [ "$_rc" -ne 0 ]; then
    cn_pass CNR-A2-UNNEEDLED-ZERO-REFUSED "a zero with no recorded hit count is REFUSED: $_out"
else
    cn_fail CNR-A2-UNNEEDLED-ZERO-REFUSED "an UNCERTIFIED zero was accepted — a blind instrument and a clean artifact return the identical quiet zero"
fi

# --- A3 GOLDEN-BAD: a blind needle is refused, with a DISTINCT reason ----------
cn_record "$TMP/blind.json" 'known-present' 0 true "$QCMD"
_out=$(cn_evaluate "$TMP/blind.json" 2>&1); _rc=$?
if [ "$_rc" -ne 0 ]; then
    if [ "$_out" = "$_abs_reason" ]; then
        cn_fail CNR-A3-BLIND-NEEDLE-DISTINCT "a BLIND needle was refused, but with the SAME message as an ABSENT one — the two defects are no longer distinguishable, so nobody can tell whether to certify the instrument or fix it"
    else
        cn_pass CNR-A3-BLIND-NEEDLE-DISTINCT "a needle that found nothing is REFUSED with a reason distinct from the absent-needle one: $_out"
    fi
else
    cn_fail CNR-A3-BLIND-NEEDLE-DISTINCT "a needle with needle_hits=0 was accepted as certification — the instrument proved it CANNOT see and its zero was still believed"
fi

# --- A4 NEGATIVE CONTROL: same path certifies, different path does not ---------
_same=$(cn_assert_same_path "$TMP/good.json" "$QCMD" 2>&1); _same_rc=$?
_diff=$(cn_assert_same_path "$TMP/good.json" 'grep -c control_needle_ABSENT evidence.txt' 2>&1); _diff_rc=$?
if [ "$_same_rc" -eq 0 ] && [ "$_diff_rc" -ne 0 ]; then
    cn_pass CNR-A4-SAME-PATH-CLAUSE "FR-005's same-path clause holds in both directions: identical command certifies, different command does not"
elif [ "$_same_rc" -ne 0 ]; then
    cn_fail CNR-A4-SAME-PATH-CLAUSE "the IDENTICAL command was rejected as a different path ($_same) — a false refusal (§11.4.201(1))"
else
    cn_fail CNR-A4-SAME-PATH-CLAUSE "a needle run through a DIFFERENT command was accepted as certification ($_diff) — FR-005's load-bearing clause is not enforced"
fi

# --- A5 the rule is wired at the acceptance seam -------------------------------
# Certify the grep can see this file at all before reporting any absence.
cn_count '-E' 'open_blocker_gate' "$READER"
_needle_hits=$CN_COUNT
if [ ! -r "$READER" ] && [ "$STANDALONE" -eq 1 ]; then
    cn_skip CNR-A5-WIRED-AT-SEAM "standalone canon DECLARED (--standalone-canon): the acceptance seam $READER belongs to a consumer and does not exist here, so the wiring question is not applicable (honest SKIP, not a PASS; A1-A4 above still ran)"
elif [ ! -r "$READER" ]; then
    cn_blind CNR-A5-WIRED-AT-SEAM "the acceptance seam is unreadable at $READER — the wiring question is UNDECIDED, and undecided is never reported as wired"
elif [ "${_needle_hits:-0}" -eq 0 ]; then
    cn_blind CNR-A5-WIRED-AT-SEAM "control needle 'open_blocker_gate' returned 0 hits in $READER through the same grep and flags — the instrument cannot see, so any zero it reports for the rule says NOTHING (§11.4.201(7)(b))"
else
    cn_count '-E' 'control_needle_(ABSENT|BLIND)' "$READER"
    if [ "${CN_COUNT:-0}" -gt 0 ]; then
        cn_pass CNR-A5-WIRED-AT-SEAM "the acceptance seam emits the FR-005/FR-006 refusal reasons (${CN_COUNT} reference(s) in $READER)"
    else
        cn_fail CNR-A5-WIRED-AT-SEAM "the control-needle rule is implemented in the library but the acceptance seam $READER never emits control_needle_ABSENT or control_needle_BLIND (needle saw the file ${_needle_hits}x, so this absence is REAL, not blind). §11.4.108: source-present is not runtime-active — a rule no seam consults refuses nothing. HONEST READING: the reader-seam wiring (feature task T224) has not landed; this gate is working."
    fi
fi

cn_summary "$GATE_ID"
_summary_rc=$?

if [ "$DO_SELFTEST" -eq 1 ]; then
    printf '\n--- --selftest: the golden triple, re-stated explicitly ---\n'
    printf 'golden-GOOD     needled zero          -> %s\n' "$(cn_verdict_of /dev/null CNR-A1-NEEDLED-ZERO-ACCEPTED 2>/dev/null || echo 'see CNR-A1 above')"
    printf 'golden-BAD      unneedled zero        -> must REFUSE (CNR-A2)\n'
    printf 'golden-BAD      blind needle          -> must REFUSE with a DISTINCT reason (CNR-A3)\n'
    printf 'negative-control same/different path  -> must certify / must not (CNR-A4)\n'
    printf 'A gate passing CNR-A2 and CNR-A3 while failing CNR-A1 would be a false-refusal engine.\n'
fi

exit "$_summary_rc"
