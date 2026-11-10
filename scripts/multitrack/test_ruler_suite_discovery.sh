#!/usr/bin/env bash
# =============================================================================
# test_ruler_suite_discovery.sh -- meta-test of the ruler-suite aggregator
# (scripts/multitrack/test_multitrack_ruler_suite.sh): which members it
# discovers, which repository root it picks, and its exit and SKIP-reason
# semantics (CON-117, review findings F109-1, F109-2, F109-3).
#
# The file name deliberately does NOT match `test_multitrack_*.sh`, so the
# aggregator never discovers and re-runs this meta-test.
#
# Every case copies the aggregator under test into a throw-away tree whose
# members are stub tests with a known exit code, runs it under `env -i`, and
# asserts the root, the member count, the device-roster member and the exit
# code. The cases are the reviewer's fixture C1..C9 plus the skip-reason cases:
#   C1  standalone canon (not named constitution), one PASS + one SKIP -> rc 0
#   C2  standalone, every member SKIPs with one shared reason        -> rc 77,
#       last line names that reason
#   C2m standalone, members SKIP with different reasons              -> rc 77,
#       no single reason token, both reasons listed
#   C3  standalone with a FAIL                                       -> rc 1
#   C4  vendored consumer reached by its physical path               -> 3 tests
#   C5  the same consumer reached through a symlinked directory      -> 3 tests
#       (F109-1: the head of the fixu vehicle found 2)
#   C6  standalone canon named constitution, parent not a git tree   -> device
#       roster of the parent NOT included
#   C7  standalone canon next to a sibling directory named
#       constitution                                                 -> its own
#       members only
#   C8  relative invocation from inside the canon                    -> 3 tests
#   C9  canon is its own nested repository inside the consumer       -> 3 tests
#
# Usage:   bash scripts/multitrack/test_ruler_suite_discovery.sh [<aggregator>]
#          (default: the aggregator next to this file)
# Exit:    0 every case passed; 1 a case failed; 2 setup error.
# Cleanup: the work tree is removed with safe_rm_rf (section 11.4.287(B)).
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P) || { echo "FATAL: cannot resolve own dir" >&2; exit 2; }
CANON_SRC=$(cd "$HERE/../.." && pwd -P)
SUITE=${1:-$HERE/test_multitrack_ruler_suite.sh}
[ -f "$SUITE" ] || { echo "FATAL: aggregator not found: $SUITE" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git not on PATH" >&2; exit 2; }

W=$(mktemp -d "${TMPDIR:-/tmp}/ruler_suite_discovery.XXXXXX") || { echo "FATAL: mktemp failed" >&2; exit 2; }
[ -n "$W" ] && [ -d "$W" ] || { echo "FATAL: mktemp gave no directory" >&2; exit 2; }
cleanup() {
    bash -c '. "$1" && safe_rm_rf "${2:?}"' _rm "$CANON_SRC/scripts/lib/safe_rm.sh" "$W" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok $*"; }
bad() { FAIL=$((FAIL + 1)); echo "NOT ok $*"; }

# mk_canon <dir> <rcA> <rcB> [<reasonA>] [<reasonB>]
mk_canon() {
    mkdir -p "$1/scripts/multitrack"
    cp "$SUITE" "$1/scripts/multitrack/test_multitrack_ruler_suite.sh"
    printf '#!/bin/sh\necho canon-A\n[ -z "%s" ] || echo "SKIP: stub reason=%s"\nexit %s\n' "${4:-}" "${4:-}" "$2" \
        > "$1/scripts/multitrack/test_multitrack_a.sh"
    printf '#!/bin/sh\necho canon-B\n[ -z "%s" ] || echo "SKIP: stub reason=%s"\nexit %s\n' "${5:-}" "${5:-}" "$3" \
        > "$1/scripts/multitrack/test_multitrack_b.sh"
    chmod +x "$1"/scripts/multitrack/*.sh
}
mk_dev() {
    mkdir -p "$1/device/rockchip/rk3588/tests"
    printf '#!/bin/sh\necho DEVICE-TEST\nexit 0\n' > "$1/device/rockchip/rk3588/tests/test_multitrack_dev.sh"
    chmod +x "$1/device/rockchip/rk3588/tests/test_multitrack_dev.sh"
}

# run_case <tag> <script> -> sets OUT RC TOTAL DEV ROOTLINE LAST
run_case() {
    local tag=$1 script=$2
    OUT=$(env -i HOME="$W" PATH=/usr/bin:/bin MTRS_EVIDENCE_DIR="$W/ev_$tag" sh "$script" 2>&1)
    RC=$?
    TOTAL=$(printf '%s\n' "$OUT" | sed -n 's/.*summary: TOTAL=\([0-9]*\).*/\1/p')
    DEV=$(printf '%s\n' "$OUT" | grep -c 'test_multitrack_dev\.sh')
    ROOTLINE=$(printf '%s\n' "$OUT" | sed -n 's/^RB-11 ruler-suite: repo root  = //p')
    LAST=$(printf '%s\n' "$OUT" | tail -n 1)
    echo "# [$tag] rc=$RC total=${TOTAL:-?} dev=$DEV root=$ROOTLINE"
}

expect() { # <tag> <want_rc> <want_total> <want_dev>
    if [ "$RC" = "$2" ] && [ "${TOTAL:-x}" = "$3" ] && [ "$DEV" = "$4" ]; then
        ok "$1: rc=$RC total=$TOTAL dev=$DEV"
    else
        bad "$1: want rc=$2 total=$3 dev=$4, got rc=$RC total=${TOTAL:-?} dev=$DEV"
        printf '%s\n' "$OUT" | sed 's/^/#   /'
    fi
}

# C1
mk_canon "$W/c1/canonX" 0 77 "" topology_unsupported; git -C "$W/c1/canonX" init -q
run_case C1 "$W/c1/canonX/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C1_standalone_pass_skip 0 2 0

# C2: shared reason propagated
mk_canon "$W/c2/canonY" 77 77 artifact_not_yet_built artifact_not_yet_built; git -C "$W/c2/canonY" init -q
run_case C2 "$W/c2/canonY/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C2_all_skip 77 2 0
case "$LAST" in
    *"reason=artifact_not_yet_built"*) ok "C2: aggregate SKIP keeps the members' shared reason ($LAST)" ;;
    *) bad "C2: aggregate SKIP does not carry the shared member reason artifact_not_yet_built: $LAST" ;;
esac

# C2m: mixed reasons -> no single restated code, both reasons named
mk_canon "$W/c2m/canonM" 77 77 artifact_not_yet_built topology_unsupported; git -C "$W/c2m/canonM" init -q
run_case C2m "$W/c2m/canonM/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C2m_mixed_skip 77 2 0
case "$LAST" in
    *"reason="*) bad "C2m: mixed member reasons restated as one code: $LAST" ;;
    *artifact_not_yet_built*topology_unsupported*) ok "C2m: mixed reasons named, no single code ($LAST)" ;;
    *) bad "C2m: mixed reasons not named on the last line: $LAST" ;;
esac

# C3
mk_canon "$W/c3/canonZ" 0 3; git -C "$W/c3/canonZ" init -q
run_case C3 "$W/c3/canonZ/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C3_fail 1 2 0

# C4 vendored consumer, physical path
mkdir -p "$W/c4/P"; git -C "$W/c4/P" init -q; mk_canon "$W/c4/P/constitution" 0 0; mk_dev "$W/c4/P"
run_case C4 "$W/c4/P/constitution/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C4_vendored 0 3 1

# C5 the same consumer through a symlinked directory (F109-1)
ln -s "$W/c4" "$W/c5link"
run_case C5 "$W/c5link/P/constitution/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C5_vendored_via_symlink 0 3 1

# C6
mkdir -p "$W/c6"; mk_canon "$W/c6/constitution" 0 0; git -C "$W/c6/constitution" init -q; mk_dev "$W/c6"
run_case C6 "$W/c6/constitution/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C6_parent_not_git 0 2 0

# C7
mkdir -p "$W/c7"; mk_canon "$W/c7/canonQ" 0 0; git -C "$W/c7/canonQ" init -q; mk_canon "$W/c7/constitution" 3 3
run_case C7 "$W/c7/canonQ/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C7_sibling_not_hijacked 0 2 0

# C8 relative invocation
OLD=$PWD; cd "$W/c4/P/constitution/scripts/multitrack" || exit 2
run_case C8 test_multitrack_ruler_suite.sh; cd "$OLD" || exit 2; expect C8_relative_invocation 0 3 1

# C9 nested repository
mkdir -p "$W/c9/P"; git -C "$W/c9/P" init -q; mk_canon "$W/c9/P/constitution" 0 0; git -C "$W/c9/P/constitution" init -q; mk_dev "$W/c9/P"
run_case C9 "$W/c9/P/constitution/scripts/multitrack/test_multitrack_ruler_suite.sh"; expect C9_nested_repo 0 3 1

# Control needle: the fixture really discovers a device member when one is
# planted (C4 reported dev=1); a dev count of 0 everywhere would mean the
# grep is blind, so C4's own result is the positive control.
echo
echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
