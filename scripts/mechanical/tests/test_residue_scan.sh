#!/usr/bin/env bash
# test_residue_scan.sh — tests for residue_scan.sh.
#
# CONTROL NEEDLES (§11.4.273) are the point of this file. A residue scan that
# finds nothing is worthless unless the same scan, unchanged, provably finds a
# marker that IS there — and provably does not report one that is not. Both
# directions are asserted here, and the self-reference case (the scanner's own
# directory, which must contain every marker string in order to search for them)
# is exercised against the real tool directory rather than a fixture.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
SCAN="$TESTS_DIR/../residue_scan.sh"
TOOLDIR="$(cd "$TESTS_DIR/.." && pwd)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TREE="$TMP/tree"; mkdir -p "$TREE/src" "$TREE/docs"
printf 'int main(void){return 0;}\n'            > "$TREE/src/clean.c"
printf 'ordinary prose about the system\n'      > "$TREE/docs/guide.md"

it "negative control: a clean tree reports no residue and exits 0"
assert_rc 0 "$SCAN" --tree "$TREE"
assert_contains "$LAST_OUT" "residue=0" "nothing found"

it "negative control: a FABRICATED marker is not reported by a scan looking for it"
assert_rc 0 "$SCAN" --tree "$TREE" --no-default-markers --marker 'ZZQX-NOT-A-REAL-MARKER-9f3a'
assert_contains "$LAST_OUT" "residue=0" "a string that is not there is not found"

it "positive control: a planted marker IS found, and located"
printf 'x = 1;  // always pass\n' > "$TREE/src/dirty.c"
assert_rc 1 "$SCAN" --tree "$TREE"
assert_contains "$LAST_OUT" "RESIDUE src/dirty.c:1:" "file and line reported"
assert_contains "$LAST_OUT" "residue=1" "one hit"

it "each default marker is individually findable (the scan is not one-marker-wide)"
for m in "MUTATED for paired" "// always pass" "MUTATION-MARKER" "_mutated_" "XXX-MUTATION"; do
  printf 'noise %s noise\n' "$m" > "$TREE/src/probe.c"
  LAST_OUT="$("$SCAN" --tree "$TREE/src" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ]; then _pass "marker found: $m"; else _fail "marker not found: $m" "rc=$rc out=$LAST_OUT"; fi
done
rm -f "$TREE/src/probe.c"

it "an allowlisted path is exempt while a non-allowlisted one is still caught"
printf 'doc defines the marker: // always pass\n' > "$TREE/docs/rule.md"
assert_rc 1 "$SCAN" --tree "$TREE" --allow 'docs/*'
assert_contains "$LAST_OUT" "src/dirty.c" "the real residue still reported"
assert_not_contains "$LAST_OUT" "RESIDUE docs/rule.md" "the allowlisted definition is not"

it "the in-tree .mech-residue-allow file is honoured"
printf 'docs/*\nsrc/dirty.c\n' > "$TREE/.mech-residue-allow"
assert_rc 0 "$SCAN" --tree "$TREE"
assert_contains "$LAST_OUT" "residue=0" "allowlist applied from the tree"
rm -f "$TREE/.mech-residue-allow"

it "a STALE allow pattern is reported, so an allowlist cannot quietly disable the scan"
assert_rc 1 "$SCAN" --tree "$TREE" --allow 'docs/*' --allow 'never/matches/anything/*'
assert_contains "$LAST_OUT" "STALE-ALLOW never/matches/anything/*" "stale pattern named"

it "--strict-allow turns a stale pattern into a finding even with no residue"
rm -f "$TREE/src/dirty.c" "$TREE/docs/rule.md"
assert_rc 0 "$SCAN" --tree "$TREE" --allow 'never/matches/*'
assert_rc 1 "$SCAN" --tree "$TREE" --allow 'never/matches/*' --strict-allow
assert_contains "$LAST_OUT" "STALE-ALLOW" "stale pattern is the finding"

it "THE FALSE-NULL GUARD: a control needle the scan cannot find is CANNOT_RUN"
assert_rc 2 "$SCAN" --tree "$TREE" --control-needle 'ABSENT-NEEDLE-c41d'
assert_contains "$LAST_OUT" "CONTROL-NEEDLE NOT FOUND" "the scan refuses to report a clean result it cannot back"

it "a control needle that IS present lets the clean result stand"
assert_rc 0 "$SCAN" --tree "$TREE" --control-needle 'ordinary prose'
assert_contains "$LAST_OUT" "control=found" "needle found"

it "binary files are skipped rather than mis-reported as source residue"
printf 'prefix // always pass suffix\n' > "$TMP/bin.dat"
printf '\000\001\002' >> "$TMP/bin.dat"
cp "$TMP/bin.dat" "$TREE/src/blob.bin"
assert_rc 0 "$SCAN" --tree "$TREE"
rm -f "$TREE/src/blob.bin"

it "SELF-REFERENCE: the tool's own files are excluded when the tree contains them"
PARENT="$(cd "$TOOLDIR/.." && pwd)"
SELF_NAME="$(basename "$TOOLDIR")"
"$SCAN" --tree "$PARENT" > "$TMP/parent.out" 2>&1 || true
if grep -q "RESIDUE $SELF_NAME/" "$TMP/parent.out"; then
  _fail "the scanner flagged its own source" "$(grep "RESIDUE $SELF_NAME/" "$TMP/parent.out" | head -3)"
else
  _pass "no hit inside $SELF_NAME/ — the definitions that make the scan possible are not reported as residue"
fi
assert_contains "$(cat "$TMP/parent.out")" "self_excluded=" "the exclusion count is published, not hidden"
excluded="$(sed -n 's/.*self_excluded=\([0-9]*\).*/\1/p' "$TMP/parent.out")"
if [ "${excluded:-0}" -gt 0 ]; then _pass "self_excluded=$excluded files"; else _fail "nothing was self-excluded" "out=$(tail -1 "$TMP/parent.out")"; fi

it "THE OTHER FALSE NULL: a scan that examined nothing is CANNOT_RUN, not clean"
assert_rc 2 "$SCAN" --tree "$TOOLDIR"
assert_contains "$LAST_OUT" "examined nothing" "a fully-excluded scan refuses to report residue=0"

it "a scan that examined files reports how many, so an empty result is auditable"
assert_rc 0 "$SCAN" --tree "$TREE"
assert_contains "$LAST_OUT" "examined=" "examined count published"

it "argument validation is CANNOT_RUN"
assert_rc 2 "$SCAN"
assert_rc 2 "$SCAN" --tree "$TMP/no-such-tree"
assert_rc 2 "$SCAN" --tree "$TREE" --no-default-markers
assert_rc 2 "$SCAN" --tree "$TREE" --allow-from "$TMP/no-such-list"
assert_rc 2 "$SCAN" --tree "$TREE" --bogus

summary
