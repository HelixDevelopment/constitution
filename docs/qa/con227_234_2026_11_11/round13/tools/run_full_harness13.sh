#!/usr/bin/env bash
# run_full_harness.sh TREE OUTDIR: run the standing mutation harness of TREE (a checkout of the round-13 commit) once,
# write its whole output to OUTDIR/mutations_full_r13.txt, and keep OUTDIR/summary.txt current: "RUNNING" with the
# start time, the head and the number of verdict lines so far (every 60 s), then the final rc, duration, RESULT line
# and every FAIL/SKIP line. The caller provides the hermetic environment (env -i) and the scope (systemd-run).
set -u
tree="${1:?tree}"; out="${2:?outdir}"
mkdir -p "$out"; cd "$tree" || exit 2
head="$(git rev-parse HEAD)"; st=$(date +%s); log="$out/mutations_full_r13.txt"; sum="$out/summary.txt"
mkdir -p "$out/tmp"
: >"$log"
TMPDIR="$out/tmp" bash tests/release/test_release_tooling_mutations.sh >"$log" 2>&1 &
hp=$!
while kill -0 "$hp" 2>/dev/null; do
  printf 'RUNNING head=%s started=%s now=%s verdict_lines=%s killed=%s fail_lines=%s\n' "$head" \
    "$(date -u -d "@$st" +%FT%TZ)" "$(date -u +%FT%TZ)" "$(grep -cE '^(PASS|FAIL|SKIP) ' "$log")" \
    "$(grep -cE '^PASS .* killed' "$log")" "$(grep -c '^FAIL' "$log")" >"$sum.tmp" && mv -f "$sum.tmp" "$sum"
  sleep 60 & wait $!
done
wait "$hp"; rc=$?
{ printf 'DONE head=%s rc=%s seconds=%s\n' "$head" "$rc" "$(( $(date +%s) - st ))"
  grep -E '^RESULT' "$log" | tail -n 1
  printf 'verdict_lines=%s controls_pass=%s killed=%s equivalent=%s\n' "$(grep -cE '^(PASS|FAIL|SKIP) ' "$log")" \
    "$(grep -cE '^PASS control' "$log")" "$(grep -cE '^PASS .* killed' "$log")" "$(grep -cE '^PASS .* equivalent' "$log")"
  echo "FAIL and SKIP lines:"; grep -E '^(FAIL|SKIP)' "$log"
  printf 'sha256 %s\n' "$(sha256sum "$log" | cut -d' ' -f1)"; } >"$sum.tmp" && mv -f "$sum.tmp" "$sum"
