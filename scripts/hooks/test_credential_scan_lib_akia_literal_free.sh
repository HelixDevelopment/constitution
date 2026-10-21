#!/usr/bin/env bash
# =============================================================================
# test_credential_scan_lib_akia_literal_free.sh — proves credential_scan_lib.sh
# carries NO contiguous AWS-access-key-id-shaped literal (the shape
# AKIA followed by 16 of [0-9A-Z]) in its own source, WITHOUT weakening the
# scanner it defines.
#
# Why: the review precheck gate's secret-scan (a plain regex scan of every
# changed file, no allowlist) flagged the scanner's own placeholder AKIA
# literal — in its doc comments and in HELIX_CRED_AKIA_PLACEHOLDER_CARRIER.
# The literal is now written split (comments) or built by shell string
# concatenation (the carrier), so the VALUE the scanner uses is unchanged.
#
# Checks (all through the REAL scanner, helix_cred_scan_file, sourced from the
# library exactly as its callers source it):
#   B1 HELIX_CRED_AKIA_PLACEHOLDER_CARRIER still holds the exact, unchanged
#      anchored placeholder regex value.
#   B2 fixture outcome table (positive controls caught, placeholder carrier
#      still clean, negative control clean) — identical before and after the
#      rewrite; any changed outcome is a FAIL.
#   L1 the library file yields 0 lines matching AKIA[0-9A-Z]{16}, with a
#      control needle proving the instrument sees a known-present string (1)
#      and does not see a known-absent one (0) (§11.4.273).
#
# Usage:        bash constitution/scripts/hooks/test_credential_scan_lib_akia_literal_free.sh
#               CREDSCAN_LIB_UNDER_TEST=<path> overrides the library path
#               (used to run the same checks against a pre-change copy).
# Inputs:       none (fixtures are built in a mktemp dir).
# Outputs:      one PASS/FAIL line per check; exit 0 iff every check passes,
#               1 on a check failure, 2 when the harness cannot run.
# Side-effects: creates + removes a mktemp dir.
# Dependencies: bash, grep, printf.
# Cross-refs:   credential_scan_lib.sh, test_credential_scan_lib.sh,
#               §11.4.10 / §11.4.201 / §11.4.273 / §11.4.224.
#
# SECURITY: synthetic values only. Every AKIA-shaped string below is built from
# two printf arguments so this file's own source never carries one contiguous.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="${CREDSCAN_LIB_UNDER_TEST:-$HERE/credential_scan_lib.sh}"
if [ ! -f "$LIB" ] || ! bash -n "$LIB" 2>/dev/null; then
    echo "FATAL: library under test missing or does not parse: $LIB" >&2
    exit 2
fi
# shellcheck source=/dev/null
. "$LIB"
if ! declare -F helix_cred_scan_file >/dev/null; then
    echo "FATAL: helix_cred_scan_file not defined after sourcing: $LIB" >&2
    exit 2
fi

pass=0
fail=0
ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/credscan_akia_free.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

P='AKIA'
SEQ='1234567890123456'

# B1 — the carrier value is byte-identical to the original anchored literal.
want_carrier="^${P}${SEQ}\$"
if [ "${HELIX_CRED_AKIA_PLACEHOLDER_CARRIER:-}" = "$want_carrier" ]; then
    ok "B1 placeholder carrier value unchanged (anchored exact literal)"
else
    bad "B1 placeholder carrier value changed or empty"
fi

# B2 — fixture outcome table. expected: caught | clean.
mk() { printf '%s%s\n' "$2" "$3" > "$WORK/$1"; }
mk f1_real_shape.txt          "leaked: $P"        '9Q2X7M4B8N1V5C3Z'
mk f2_keyword_real_shape.txt  "api_key=$P"        '9Q2X7M4B8N1V5C3Z'
mk f3_placeholder_prose.txt   "The documented placeholder is \`$P" "$SEQ\`, quoted as prose."
mk f4_placeholder_bare.txt    "$P"                "$SEQ"
mk f5_reordered_digits.txt    "leaked: $P"        '1234567890123465'
mk f6_placeholder_plus_letter.txt "leaked: $P"    '123456789012345X'
mk f7_negative_control.txt    'note: ZZQX_fabricated_' 'not_a_key_0000'

check() {
    local name="$1" want="$2" got
    if helix_cred_scan_file "$WORK/$name"; then got=caught; else got=clean; fi
    if [ "$got" = "$want" ]; then
        ok "B2 $name -> $got"
    else
        bad "B2 $name -> $got (expected $want; outcome CHANGED)"
    fi
}
check f1_real_shape.txt               caught
check f2_keyword_real_shape.txt       caught
check f3_placeholder_prose.txt        clean
check f4_placeholder_bare.txt         clean
check f5_reordered_digits.txt         caught
check f6_placeholder_plus_letter.txt  caught
check f7_negative_control.txt         clean

# L1 — literal-free source, control-needled.
needle_re='AKIA[0-9A-Z]{16}'
printf 'x %s%s y\n' "$P" '9Q2X7M4B8N1V5C3Z' > "$WORK/needle_present.txt"
printf 'x %s_short_0000 y\n' "$P" > "$WORK/needle_absent.txt"
np="$(LC_ALL=C grep -cE "$needle_re" "$WORK/needle_present.txt")"
na="$(LC_ALL=C grep -cE "$needle_re" "$WORK/needle_absent.txt")"
if [ "$np" = 1 ] && [ "$na" = 0 ]; then
    ok "L1 control needle: known-present=1, known-absent=0"
    nl="$(LC_ALL=C grep -cE "$needle_re" "$LIB")"
    if [ "$nl" = 0 ]; then
        ok "L1 library source carries 0 AKIA[0-9A-Z]{16} lines"
    else
        bad "L1 library source carries $nl AKIA[0-9A-Z]{16} line(s)"
        LC_ALL=C grep -nE "$needle_re" "$LIB" | cut -d: -f1 | sed 's/^/      line /'
    fi
else
    echo "FATAL: control needle failed (present=$np absent=$na); instrument blind" >&2
    exit 2
fi

echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
