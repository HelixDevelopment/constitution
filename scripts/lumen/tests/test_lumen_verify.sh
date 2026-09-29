#!/usr/bin/env bash
# test_lumen_verify.sh — hermetic tests for ../lumen_verify.sh using a stub `lumen` binary.
# Purpose: prove lumen_verify.sh (a) passes when every gold file is in top-k, (b) fails when a gold
#   file ranks below k, (c) refuses (exit 2) on an empty/erroring search instead of reporting absence,
#   (d) passes an 'unsupported' query only when its gold is ABSENT, (e) is deterministic.
# Usage: bash test_lumen_verify.sh   (exit 0 = all pass). No network, no real index.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); V="$HERE/../lumen_verify.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=1; }
# stub: result order keyed by query word; emits the <result:file ...> + score format of lumen --summary
cat > "$T/lumen" <<'STUB'
#!/usr/bin/env bash
q="${@: -1}"
emit(){ i=0; for f in "$@"; do i=$((i+1)); printf '<result:file filename="%s">\n  <result:chunk score="%s"/>\n' "$f" "0.$((99-i))"; done; }
case "$q" in
  *alpha*) emit a.c b.c c.c ;;
  *beta*)  emit x1 x2 x3 x4 x5 target.py ;;
  *empty*) : ;;
  *boom*)  echo "error: ollama down" >&2; exit 3 ;;
  *kotlinfound*) emit Svc.kt ;;
  *kotlin*) emit other.java ;;
esac
STUB
chmod +x "$T/lumen"
mk(){ printf '%s' "$1" > "$T/g.json"; }
run(){ bash "$V" --golden "$T/g.json" --project "$T" --lumen "$T/lumen" --k 5 --out "$T/o" >"$T/log" 2>&1; echo $?; }
mk '[{"id":"a","type":"conceptual","q":"alpha","gold":["b.c"]}]'; [ "$(run)" = 0 ] && ok t1_top_k_hit || bad t1_top_k_hit
mk '[{"id":"b","type":"conceptual","q":"beta","gold":["target.py"]}]'; [ "$(run)" = 1 ] && ok t2_rank6_fails_at_k5 || bad t2_rank6_fails_at_k5
mk '[{"id":"e","type":"conceptual","q":"empty","gold":["a.c"]}]'; [ "$(run)" = 2 ] && ok t3_empty_is_error_not_absence || bad t3_empty_is_error_not_absence
mk '[{"id":"x","type":"conceptual","q":"boom","gold":["a.c"]}]'; [ "$(run)" = 2 ] && ok t4_tool_error_is_error || bad t4_tool_error_is_error
mk '[{"id":"u","type":"unsupported","q":"kotlin","gold":["Svc.kt"]}]'; [ "$(run)" = 0 ] && ok t5_unsupported_absent_passes || bad t5_unsupported_absent_passes
mk '[{"id":"u","type":"unsupported","q":"kotlinfound","gold":["Svc.kt"]}]'; [ "$(run)" = 1 ] && ok t6_unsupported_present_fails || bad t6_unsupported_present_fails
mk '[{"id":"s","type":"conceptual","q":"alpha","gold":["b.c"],"in_tierA":false},{"id":"a","type":"conceptual","q":"alpha","gold":["a.c"]}]'
r=$(run); c1=$(cat "$T/o/results.tsv"); run >/dev/null; c2=$(cat "$T/o/results.tsv")
[ "$r" = 0 ] && [ "$c1" = "$c2" ] && grep -q '^s	SKIP' "$T/o/results.tsv" && ok t7_deterministic_and_scope_skip || bad t7_deterministic_and_scope_skip
mk '[{"id":"a","type":"conceptual","q":"alpha","gold":["b.c"]}]'; bash "$V" --golden "$T/g.json" --project "$T" --lumen "$T/lumen" --k 1 --out "$T/o" >/dev/null 2>&1; [ $? = 1 ] && ok t8_k_is_honoured || bad t8_k_is_honoured
# --- threshold + baseline ratchet (t9..t14) ---
G2='[{"id":"a","type":"conceptual","q":"alpha","gold":["a.c"]},{"id":"b","type":"conceptual","q":"beta","gold":["target.py"]}]'
BL='{"known_misses":{"b":{"reason":"rank 6 at k=5","observed_rank":6}}}'
runb(){ bash "$V" --golden "$T/g.json" --project "$T" --lumen "$T/lumen" --k 5 --out "$T/o" "$@" >"$T/log" 2>&1; echo $?; }
mk "$G2"; printf '%s' "$BL" > "$T/bl.json"; [ "$(runb --baseline "$T/bl.json" --min-recall 0.9)" = 1 ] && ok t9_recall_below_threshold_fails || bad t9_recall_below_threshold_fails
mk "$G2"; printf '%s' "$BL" > "$T/bl.json"; [ "$(runb --baseline "$T/bl.json" --min-recall 0.5)" = 0 ] && ok t10_known_miss_tolerated || bad t10_known_miss_tolerated
mk "$G2"; printf '%s' '{"known_misses":{}}' > "$T/bl.json"; [ "$(runb --baseline "$T/bl.json" --min-recall 0.5)" = 1 ] && grep -q 'NEW_MISS' "$T/log" && ok t11_new_miss_fails || bad t11_new_miss_fails
mk '[{"id":"a","type":"conceptual","q":"alpha","gold":["a.c"]}]'; printf '%s' '{"known_misses":{"a":{"reason":"was rank 11","observed_rank":11}}}' > "$T/bl.json"
[ "$(runb --baseline "$T/bl.json")" = 0 ] && python3 -c "import json,sys;sys.exit(0 if json.load(open('$T/bl.json'))['known_misses']=={} else 1)" && ok t12_fixed_known_miss_tightens_baseline || bad t12_fixed_known_miss_tightens_baseline
printf '%s' '{"known_misses":{"a":{"reason":"was rank 11","observed_rank":11}}}' > "$T/bl.json"; cp "$T/bl.json" "$T/bl0.json"
[ "$(runb --baseline "$T/bl.json" --no-update-baseline)" = 0 ] && cmp -s "$T/bl.json" "$T/bl0.json" && grep -q 'TIGHTEN' "$T/log" && ok t13_read_only_mode_reports_tighten || bad t13_read_only_mode_reports_tighten
mk "$G2"; printf '%s' "$BL" > "$T/bl.json"; [ "$(runb --baseline "$T/bl.json")" = 1 ] && ok t14_default_threshold_0_85 || bad t14_default_threshold_0_85
exit $fail
