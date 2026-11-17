#!/usr/bin/env bash
# tests/sync/test_determinism.sh -- DETERMINISM / IDEMPOTENCY (§11.4.50) of scripts/sync/sync_all_upstreams.sh:
# N=3 runs of each mode against the same unchanged repository state produce IDENTICAL canonical_sha256
# (the time-free part of the report) and identical TSV; a real state change produces a DIFFERENT hash
# (control needle: the hash is not a constant); three consecutive --apply runs converge after the first.
T_NAME=sync-determinism
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
sx_std_tree
sx_commit "$U_ROOT" "r1"; sx_commit "$U_A" "a1"
sx_run --check --root "$W"   # fetch once so --dry-run and --no-fetch see the same refs
for mode in "--check" "--dry-run" "--check --no-fetch"; do
  hashes=""; tsvs=""
  for i in 1 2 3; do
    # shellcheck disable=SC2086
    sx_run $mode --root "$W"
    hashes="$hashes $(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
    tsvs="$tsvs $(sha256sum <"$SX_TSV" | cut -c1-16)"
  done
  eq "$mode: 3 identical canonical hashes" 1 "$(tr ' ' '\n' <<<"$hashes" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
  eq "$mode: 3 identical TSV files" 1 "$(tr ' ' '\n' <<<"$tsvs" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
  eq "$mode: the JSON hash field equals the printed one" "$(sx_q 'r["canonical_sha256"]')" "$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
done
h_before="$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
sx_commit "$U_ROOT" "r2"; sx_run --check --no-fetch --root "$W"; h_same="$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
eq "an unfetched upstream change does not change the offline hash" "$h_before" "$h_same"
sx_run --check --root "$W"; h_after="$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
[ "$h_after" != "$h_before" ] && ok "control needle: a real state change changes the hash" || nok "hash did not change on a state change"
# apply converges: run 1 moves, runs 2 and 3 are identical and move nothing
sx_run --apply --advance-pins --root "$W"; eq "apply 1: exit 0" 0 "$SX_RC"
eq "apply 1: something moved" "True" "$(sx_q 'any(x["result"]=="updated" for x in r["repos"])')"
sx_run --apply --advance-pins --root "$W"; a2="$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
sx_run --apply --advance-pins --root "$W"; a3="$(sed -n 's/^CANONICAL_SHA256=//p' <<<"$SX_OUT")"
eq "apply 2 and 3: identical hash" "$a2" "$a3"
eq "apply 3: nothing moved" "0" "$(sx_q 'sum(1 for x in r["repos"] if x["result"]=="updated")')"
finish
