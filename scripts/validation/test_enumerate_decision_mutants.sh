#!/bin/bash
# Purpose : fast guard for scripts/validation/enumerate_decision_mutants.py (CON-158 /
#           CON-147 round 6, section 11.4.274). The census itself runs every
#           mutant against its regression test and takes hours, so it is not run
#           here. This test checks the parts that need no mutant run: the
#           operator self-test passes; --list enumerates mutants for every
#           target (control needle: a known decision point of each target is
#           listed); every key in the equivalence ledger is still generated (a
#           ledger entry for a decision point that no longer exists is STALE);
#           and every ledger entry carries a proof.
# Usage   : bash scripts/validation/test_enumerate_decision_mutants.sh
#           Exit 0 when every check passes, 1 otherwise; the last line is the
#           summary line.
# Inputs  : none (reads this checkout's scripts; writes only under a mktemp dir).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ENUM="$HERE/enumerate_decision_mutants.py"
LEDGER="$HERE/decision_mutants_equivalent.tsv"
pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT

if python3 -I "$ENUM" --selftest > "$TMP/self.out" 2>&1; then ok "operator self-test: $(tail -1 "$TMP/self.out")"
else notok "operator self-test failed: $(grep -m3 'NOT ok' "$TMP/self.out" | tr '\n' '|')"; fi

if python3 -I "$ENUM" --list > "$TMP/list.out" 2>&1; then ok "--list exits 0: $(tail -1 "$TMP/list.out")"
else notok "--list failed: $(tail -2 "$TMP/list.out" | tr '\n' '|')"; fi
# Control needles: one decision point per target that must be listed.
for needle in 'meta:[0-9]*	drop_or_return	cp -- ' 'host_guard:[0-9]*	num_bound_shift	_v=$(awk' 'host_report:[0-9]*	num_bound_shift	if len(parts) >= 4:'; do
  if grep -q -- "$needle" "$TMP/list.out"; then ok "control needle listed: $(printf '%s' "$needle" | tr '\t' ' ')"
  else notok "control needle NOT listed: $(printf '%s' "$needle" | tr '\t' ' ')"; fi
done
# Negative control: a key that cannot exist is not listed.
grep -q '^zzzzzzzzzzzz	' "$TMP/list.out" && notok "negative control: a fabricated key is listed" || ok "negative control: a fabricated key is not listed"

n=0
while IFS=$'\t' read -r key target rule old proof || [ -n "$key" ]; do
  case $key in ''|'#'*) continue ;; esac
  n=$((n + 1))
  if [ -z "${proof// /}" ]; then notok "ledger $key ($target): no proof"; continue; fi
  if grep -q "^$key	$target:" "$TMP/list.out"; then ok "ledger $key ($target $rule) is still generated, with a proof"
  else notok "ledger $key ($target $rule) is STALE: no such mutant is generated"; fi
done < "$LEDGER"
[ "$n" -gt 0 ] && ok "ledger has $n entries (read)" || notok "ledger read no entries (blind)"

echo "=== enumerate_decision_mutants guard: pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
