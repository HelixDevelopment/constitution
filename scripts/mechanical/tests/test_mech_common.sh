#!/usr/bin/env bash
# test_mech_common.sh — tests for lib/mech_common.sh.
#
# CONTROL NEEDLES (§11.4.273). Two of these tests exist because both defects
# they guard were REAL and were caught on 2026-09-08 while building the library:
#   1. GNU sed 4.9 did not interpret \x1b, so the ANSI strip was a silent no-op.
#   2. Under a UTF-8 locale the [@-~] bracket range did not match what it looks
#      like it matches, so the strip under-removed.
# Both left every downstream parse running against coloured text. The positive
# needle proves the strip removes a KNOWN-PRESENT escape; the negative needle
# proves the parser does NOT invent counts from text that has none.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
source "$TESTS_DIR/../lib/mech_common.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

it "positive control: ANSI escapes are actually removed"
printf '\033[32m\xe2\x9c\x93 58 passed, 0 failed\033[0m\n' > "$TMP/green.txt"
stripped="$(mech_strip_ansi < "$TMP/green.txt")"
esc_count="$(printf '%s' "$stripped" | od -An -c | grep -c '033' || true)"
assert_eq "0" "$esc_count" "no ESC byte survives the strip"
assert_not_contains "$stripped" "[32m" "no CSI parameter text survives"
assert_contains "$stripped" "58 passed, 0 failed" "the payload text survives"

it "positive control: a success summary parses to the right counts"
assert_eq "58 0" "$(mech_parse_summary "$TMP/green.txt")" "58 passed / 0 failed"

it "the field ORDER trap: a failing summary swaps the labels"
printf '\033[31m\xe2\x9c\x97 23 failed, 35 passed\033[0m\n' > "$TMP/red.txt"
assert_eq "35 23" "$(mech_parse_summary "$TMP/red.txt")" "35 passed / 23 failed, not 23 passed"

it "negative control: fabricated counts are NOT produced from text that has none"
printf 'this run said nothing about counts at all\n' > "$TMP/none.txt"
mech_parse_summary "$TMP/none.txt" >/dev/null 2>&1
assert_eq "2" "$?" "unparseable output is CANNOT_RUN, not a pass"

it "negative control: a half-summary is not enough"
printf 'ok: 12 passed\n' > "$TMP/half.txt"
mech_parse_summary "$TMP/half.txt" >/dev/null 2>&1
assert_eq "2" "$?" "a line naming only passes does not parse"

it "the LAST qualifying line wins, so a prose mention early on does not"
{ printf 'note: last time this was 380 passed / 0 failed\n'
  printf '7 passed, 2 failed\n'; } > "$TMP/two.txt"
assert_eq "7 2" "$(mech_parse_summary "$TMP/two.txt")" "final summary line is the one parsed"

it "mech_parse_summary on a missing file is CANNOT_RUN"
mech_parse_summary "$TMP/does-not-exist" >/dev/null 2>&1
assert_eq "2" "$?" "missing file cannot be parsed"

it "mech_summary_line shows what was parsed, with colour removed"
assert_eq "23 failed, 35 passed" "$(mech_summary_line "$TMP/red.txt" | sed 's/^[^0-9]*//')" "audit line"

it "tree fingerprint is stable, and moves when content moves"
mkdir -p "$TMP/t/sub"; printf 'a\n' > "$TMP/t/one"; printf 'b\n' > "$TMP/t/sub/two"
fp1="$(mech_fingerprint_tree "$TMP/t")"
fp2="$(mech_fingerprint_tree "$TMP/t")"
assert_eq "$fp1" "$fp2" "same tree, same fingerprint"
printf 'b-changed\n' > "$TMP/t/sub/two"
fp3="$(mech_fingerprint_tree "$TMP/t")"
if [ "$fp1" != "$fp3" ]; then _pass "a one-byte change moves the fingerprint"; else _fail "fingerprint did not move" "fp1=$fp1 fp3=$fp3"; fi

it "fingerprinting a missing dir is CANNOT_RUN"
mech_fingerprint_tree "$TMP/nope" >/dev/null 2>&1
assert_eq "2" "$?" "missing dir"

it "exit-code vocabulary is defined and distinct (§11.4.201)"
assert_eq "0" "$MECH_EXIT_OK" "OK"
assert_eq "1" "$MECH_EXIT_FINDING" "FINDING"
assert_eq "2" "$MECH_EXIT_CANNOT_RUN" "CANNOT_RUN"
assert_eq "3" "$MECH_EXIT_TIMEOUT" "TIMEOUT"

summary
