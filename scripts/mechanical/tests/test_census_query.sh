#!/usr/bin/env bash
# test_census_query.sh — the control-needle census helper (§11.4.273).
#
# WHY THIS EXISTS
#   §11.4.273 was minted from fifteen measured instrument errors in one session,
#   every one of which produced a confident, plausible, actionable result that
#   was a property of the INSTRUMENT rather than of the system. The anchor's
#   remedy is mechanical: a census that will drive a decision must prove, in the
#   same command and through the same path, that it can tell PRESENT from
#   ABSENT — a positive needle it MUST find and a negative needle it MUST NOT.
#
#   The library already carried needle discipline in two SPECIFIC tools
#   (`residue_scan.sh --control-needle`, `anchor_census.sh --control-needle`).
#   Neither is a general census, and NEITHER TAKES A NEGATIVE NEEDLE — so the
#   too-broad half of the anchor (a pattern that matches things it should not,
#   the `grep -w zai` matching `zai-coding-plan` case) had no mechanical guard
#   anywhere. That is the gap this suite specifies.
#
# THE TWO TRAPS THIS SUITE PINS (both measured, neither hypothetical)
#   1. An out-of-scope positive control. A needle that is present in the TREE
#      but outside the query's own --include scope fails, and reads as a broken
#      instrument when the instrument is fine. The refusal must SAY which of the
#      two it is, or it sends the reader hunting a defect that does not exist.
#   2. A single needle for a multi-member criterion (§11.4.273(f)). Searching a
#      two-literal denylist with ONE literal passes both controls while the
#      answer is wrong; the controls must be repeatable and ALL must hold.
#
# HERMETIC (§11.4.98): builds its own fixture tree per case, touches no
# consuming project, needs no network and no credentials.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$TESTS_DIR/../census_query.sh"
# shellcheck source=lib/assert.sh
source "$TESTS_DIR/lib/assert.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mech-census-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# fixture DIR — a small tree with known contents. Every needle used below is
# either planted here on purpose or deliberately absent; nothing is assumed.
fixture() {
  local d="$1"
  mkdir -p "$d/src" "$d/docs"
  printf 'alpha_token\nshared_marker\n'        > "$d/src/a.sh"
  printf 'beta_token\nshared_marker\n'         > "$d/src/b.sh"
  printf 'docs_only_needle\nshared_marker\n'   > "$d/docs/readme.md"
}

echo "== census_query.sh (§11.4.273 control-needled census) =="

# ---------------------------------------------------------------------------
it "the tool exists and is executable"
# ---------------------------------------------------------------------------
if [ -x "$TOOL" ]; then _pass "census_query.sh present and executable"
else _fail "census_query.sh missing or not executable" "expected at $TOOL"; fi

# ---------------------------------------------------------------------------
it "a query with both controls satisfied emits its result and exits 0"
# ---------------------------------------------------------------------------
T="$WORK/happy"; fixture "$T"
assert_rc 0 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --negative 'zzz_fabricated_needle' --label happy
assert_contains "$LAST_OUT" "CENSUS happy:" "verdict line is emitted"
assert_contains "$LAST_OUT" "matches=3"     "counts all three planted matches"

# ---------------------------------------------------------------------------
it "an ABSENT positive needle REFUSES the result and exits CANNOT_RUN (2)"
#   The load-bearing case. An instrument that cannot see must not be allowed to
#   report a clean bill of health, so the count must NOT appear in the output.
# ---------------------------------------------------------------------------
T="$WORK/blindpos"; fixture "$T"
assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'needle_that_is_not_there' --negative 'zzz_fabricated_needle' --label blindpos
assert_not_contains "$LAST_OUT" "matches=" "result is REFUSED, not merely annotated"
assert_contains "$LAST_OUT" "POSITIVE CONTROL" "names which control failed"

# ---------------------------------------------------------------------------
it "a FOUND negative needle REFUSES the result and exits CANNOT_RUN (2)"
#   The too-broad half. residue_scan/anchor_census have no equivalent.
# ---------------------------------------------------------------------------
T="$WORK/broad"; fixture "$T"
assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --negative 'beta_token' --label broad
assert_not_contains "$LAST_OUT" "matches=" "result is REFUSED"
assert_contains "$LAST_OUT" "NEGATIVE CONTROL" "names which control failed"

# ---------------------------------------------------------------------------
it "a genuine zero is REPORTABLE — 'found nothing' is not 'could not look'"
# ---------------------------------------------------------------------------
T="$WORK/zero"; fixture "$T"
assert_rc 0 "$TOOL" --tree "$T" --pattern 'pattern_matching_nothing_at_all' \
  --positive 'alpha_token' --negative 'zzz_fabricated_needle' --label zero
assert_contains "$LAST_OUT" "matches=0" "an honest zero is emitted, not refused"

# ---------------------------------------------------------------------------
it "BOTH controls are mandatory — omitting either is CANNOT_RUN (2)"
#   T002 requires that EVERY query take a positive AND a negative needle. If
#   they were optional the discipline would decay to a convention.
# ---------------------------------------------------------------------------
T="$WORK/args"; fixture "$T"
assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' --positive 'alpha_token' --label nopos
assert_contains "$LAST_OUT" "--negative" "refusal names the missing flag"
assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' --negative 'zzz_nope' --label noneg
assert_contains "$LAST_OUT" "--positive" "refusal names the missing flag"

# ---------------------------------------------------------------------------
it "controls are REPEATABLE and ALL must hold (§11.4.273(f))"
#   Measured case: a two-literal denylist searched with ONE literal reported a
#   live credential eliminated while it was still present. One needle passing
#   proves one needle, not the criterion.
# ---------------------------------------------------------------------------
T="$WORK/set"; fixture "$T"
assert_rc 0 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --positive 'beta_token' \
  --negative 'zzz_one' --negative 'zzz_two' --label setok
assert_contains "$LAST_OUT" "matches=3" "all-members-present case still reports"

assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --positive 'needle_that_is_not_there' \
  --negative 'zzz_one' --label setbad
assert_not_contains "$LAST_OUT" "matches=" "one absent member REFUSES the whole result"
assert_contains "$LAST_OUT" "needle_that_is_not_there" "names the member that failed"

# ---------------------------------------------------------------------------
it "an OUT-OF-SCOPE positive control is distinguished from a blind instrument"
#   Trap 1. 'docs_only_needle' exists in the tree but not under --include src/**.
#   Refusing is correct; refusing with the SAME message as a genuinely blind
#   instrument sends the reader after a defect that is not there.
# ---------------------------------------------------------------------------
T="$WORK/scope"; fixture "$T"
assert_rc 2 "$TOOL" --tree "$T" --pattern 'shared_marker' --include 'src/*' \
  --positive 'docs_only_needle' --negative 'zzz_fabricated_needle' --label scope
assert_contains "$LAST_OUT" "OUT OF SCOPE" "distinguishes out-of-scope from unseeable"

# ---------------------------------------------------------------------------
it "--expect-count mismatch is a FINDING (1), not a pass and not an error"
#   Three different facts: the count is wrong (1), the count is right (0), the
#   instrument could not measure (2). Collapsing any two is the §11.4.201 defect.
# ---------------------------------------------------------------------------
T="$WORK/expect"; fixture "$T"
assert_rc 1 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --negative 'zzz_fabricated_needle' \
  --expect-count 99 --label expectbad
assert_contains "$LAST_OUT" "matches=3" "the measured count is still reported"
assert_rc 0 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --negative 'zzz_fabricated_needle' \
  --expect-count 3 --label expectok

# ---------------------------------------------------------------------------
it "a missing tree is CANNOT_RUN (2), never an empty result"
# ---------------------------------------------------------------------------
assert_rc 2 "$TOOL" --tree "$WORK/no_such_tree_here" --pattern 'x' \
  --positive 'a' --negative 'b' --label missing
assert_not_contains "$LAST_OUT" "matches=" "no count from a tree that is not there"

# ---------------------------------------------------------------------------
it "the verdict line records that BOTH controls were actually checked"
#   A reader must be able to see the discipline ran, not take it on trust.
# ---------------------------------------------------------------------------
T="$WORK/audit"; fixture "$T"
assert_rc 0 "$TOOL" --tree "$T" --pattern 'shared_marker' \
  --positive 'alpha_token' --negative 'zzz_fabricated_needle' --label audit
assert_contains "$LAST_OUT" "positive=1/1" "positive control count is published"
assert_contains "$LAST_OUT" "negative=0/1" "negative control count is published"

summary
