#!/usr/bin/env bash
# test_anchor_census.sh — tests for anchor_census.sh.
#
# The census is a MEASURING instrument, so it carries both control needles
# (§11.4.273): a known-present anchor must be counted, and a fabricated one must
# not appear in the set. The false-null case has its own test, because "0 anchors
# in every carrier, all identical" is the most convincing wrong answer this tool
# could ever give.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
CENSUS="$TESTS_DIR/../anchor_census.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mk_carrier() { # mk_carrier FILE ID...
  local f="$1"; shift
  : > "$f"
  local id
  for id in "$@"; do printf '### §%s — a rule about something\n\nbody text\n\n' "$id" >> "$f"; done
}

mk_carrier "$TMP/a.md" 11.4.1 11.4.2 11.4.3
mk_carrier "$TMP/b.md" 11.4.1 11.4.2 11.4.3

it "positive control: identical carriers are in lockstep and exit 0"
assert_rc 0 "$CENSUS" "$TMP/a.md" "$TMP/b.md"
assert_contains "$LAST_OUT" "findings=0" "no findings"

it "positive control: the anchor COUNT is the number of block openers"
assert_contains "$LAST_OUT" "3" "three anchors counted"

it "negative control: a fabricated anchor is not in the set"
assert_rc 2 "$CENSUS" --control-needle 11.4.9999 "$TMP/a.md"
assert_contains "$LAST_OUT" "control needle" "a needle that is not there fails loudly"

it "positive control: a known-present anchor passes the needle check"
assert_rc 0 "$CENSUS" --control-needle 11.4.2 "$TMP/a.md" "$TMP/b.md"

it "DRIFT is a finding, and the tool prints WHICH ids differ"
mk_carrier "$TMP/c.md" 11.4.1 11.4.3 11.4.7
assert_rc 1 "$CENSUS" "$TMP/a.md" "$TMP/c.md"
assert_contains "$LAST_OUT" "SET-DRIFT" "drift reported"
assert_contains "$LAST_OUT" "only-in a.md: 11.4.2" "missing from the second carrier"
assert_contains "$LAST_OUT" "only-in c.md: 11.4.7" "extra in the second carrier"

it "an id that opens TWO blocks in one carrier is a finding (§11.4.227(B))"
mk_carrier "$TMP/dup.md" 11.4.1 11.4.2 11.4.2
assert_rc 1 "$CENSUS" "$TMP/dup.md"
assert_contains "$LAST_OUT" "DUPLICATE-OPENER" "duplicate reported"
assert_contains "$LAST_OUT" "11.4.2" "the duplicated id is named"

it "MENTIONS are not counted as declarations"
{ printf '### §11.4.1 — the only block here\n\n'
  printf 'This paragraph cites §11.4.2 and §11.4.3 without declaring them.\n'
  printf 'Composes §11.4.50 / §11.4.69.\n'; } > "$TMP/mentions.md"
assert_rc 1 "$CENSUS" "$TMP/a.md" "$TMP/mentions.md"
assert_contains "$LAST_OUT" "only-in a.md: 11.4.2" "a cited-but-not-declared id is absent from the set"

it "the second live opener form (bolded consumer carrier) is matched too"
{ printf '**§11.4.1 — short cascade reference.** text\n'
  printf '**§11.4.2 — short cascade reference.** text\n'
  printf '**§11.4.3 — short cascade reference.** text\n'; } > "$TMP/bold.md"
assert_rc 0 "$CENSUS" "$TMP/a.md" "$TMP/bold.md"
assert_contains "$LAST_OUT" "findings=0" "both opener shapes yield the same set"

it "THE FALSE-NULL GUARD: zero anchors is CANNOT_RUN, never a clean lockstep"
printf 'a document with no anchors at all\n' > "$TMP/empty.md"
assert_rc 2 "$CENSUS" "$TMP/a.md" "$TMP/empty.md"
assert_contains "$LAST_OUT" "ZERO-ANCHORS" "the empty carrier is named"
assert_not_contains "$LAST_OUT" "findings=0" "no reassuring summary is printed"

it "a wrong --opener-re shows up as CANNOT_RUN rather than a false green"
assert_rc 2 "$CENSUS" --opener-re '^NEVER-MATCHES' "$TMP/a.md" "$TMP/b.md"

it "--quiet suppresses the table but not the findings"
assert_rc 1 "$CENSUS" --quiet "$TMP/a.md" "$TMP/c.md"
assert_contains "$LAST_OUT" "SET-DRIFT" "findings still printed"
assert_not_contains "$LAST_OUT" "SET_HASH" "table header suppressed"

it "the id is taken from the OPENER, not from citations elsewhere on the line"
{ printf '### §11.4.1 — a rule (composes §11.4.50 / §11.4.69 / §11.4.107)\n\n'
  printf '### §11.4.2 — another rule (composes §11.4.99)\n\n'; } > "$TMP/citing.md"
LAST_OUT="$("$CENSUS" "$TMP/citing.md" 2>&1)"
assert_contains "$LAST_OUT" "findings=0" "cited ids are not counted as declarations"
n="$(printf '%s\n' "$LAST_OUT" | sed -n 's/^citing.md *\([0-9]*\).*/\1/p')"
assert_eq "2" "${n:-0}" "exactly two openers, not five"

it "KNOWN LIMITATION, made explicit: a sub-anchor needs a widened --id-re"
{ printf '### §11.4.10 — base rule\n\n'
  printf '### §11.4.10.A — a sub-anchor of it\n\n'; } > "$TMP/sub.md"
assert_rc 1 "$CENSUS" "$TMP/sub.md"
assert_contains "$LAST_OUT" "DUPLICATE-OPENER" "the default id regex truncates 11.4.10.A to 11.4.10"
assert_rc 0 "$CENSUS" --opener-re '^### §11\.4\.[0-9]+(\.[A-Z])?' --id-re '11\.4\.[0-9]+(\.[A-Z])?' "$TMP/sub.md"

it "argument validation is CANNOT_RUN"
assert_rc 2 "$CENSUS"
assert_rc 2 "$CENSUS" "$TMP/no-such-file.md"
assert_rc 2 "$CENSUS" --bogus "$TMP/a.md"

summary
