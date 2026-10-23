#!/usr/bin/env bash
# tests/jev/test_gate_pairs.sh (design §7.4)
# Asserts the four CM-JEV-* gate pairs exist, are executable, are registered in
# the data pack (no ledger file), each gate is GREEN on genuine fixture state,
# and each paired mutation test passes (the mutation tests self-assert the RED
# flip). Deterministic, fixtures only, no network.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
GATES="$REPO/scripts/gates"
FIX="$GATES/fixtures/jev"
PACK="$GATES/covenant_propagation_anchors.tsv"
GEN="$GATES/covenant_propagation_wrappers_generate.sh"

fails=0
say() { printf '[test_gate_pairs] %s\n' "$*"; }
assert_skip() { say "SKIP: $*"; }

GATE_CODES="CM-JEV-DETECTION CM-JEV-WIRING CM-JEV-TOKEN-REDUCTION CM-JEV-BOOTSTRAP-IDEMPOTENT"
declare -A PAIRS=(
  [CM-JEV-DETECTION]=cm_jev_detection
  [CM-JEV-WIRING]=cm_jev_wiring
  [CM-JEV-TOKEN-REDUCTION]=cm_jev_token_reduction
  [CM-JEV-BOOTSTRAP-IDEMPOTENT]=cm_jev_bootstrap_idempotent
)

for code in "${!PAIRS[@]}"; do
  base="${PAIRS[$code]}"
  g="$GATES/$base.sh"; m="$GATES/${base}_mutation_test.sh"
  # existence + executable
  [ -f "$g" ] && [ -x "$g" ] || { say "FAIL: gate $g missing or not executable"; fails=$((fails+1)); continue; }
  [ -f "$m" ] && [ -x "$m" ] || { say "FAIL: mutation test $m missing or not executable"; fails=$((fails+1)); continue; }
  # GREEN on genuine fixture state
  case "$code" in
    CM-JEV-DETECTION)
      JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" JEV_EVIDENCE_WINDOW_START=1759999000 \
      JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX" bash "$g" >/dev/null 2>&1;;
    CM-JEV-WIRING)
      JEV_HOME="$FIX/home" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json" bash "$g" >/dev/null 2>&1;;
    CM-JEV-TOKEN-REDUCTION)
      JEV_BEFORE="$FIX/evidence/before.jsonl" JEV_AFTER="$FIX/evidence/after.jsonl" \
      JEV_DECISIONS="$FIX/evidence/decisions.jsonl" JEV_STATS_REPORT="$FIX/evidence/jev-stats-report.txt" \
      bash "$g" >/dev/null 2>&1;;
    CM-JEV-BOOTSTRAP-IDEMPOTENT)
      bash "$g" >/dev/null 2>&1;;
  esac
  if [ $? -eq 0 ]; then say "GREEN: $code on genuine fixture state"; else say "FAIL: $code not GREEN on genuine fixture state"; fails=$((fails+1)); fi
  # RED via paired mutation test (self-asserting)
  if bash "$m" >/dev/null 2>&1; then say "RED-PAIR OK: ${base}_mutation_test.sh asserts the mutation flip"; else say "FAIL: mutation test for $code failed"; fails=$((fails+1)); fi
done

# negative controls: every gate MUST be able to go RED on missing/broken evidence.
# (A gate that is green on garbage is the bluff the mutation pairs exist to catch;
# this asserts the same from the outside, independent of the mutation scripts.)
NOPE="$(mktemp -d)/does-not-exist"
neg() { # neg <label> <env assignments...> -- runs the gate, expects rc != 0
  local label="$1" gate="$2"; shift 2
  if env "$@" bash "$gate" >/dev/null 2>&1; then
    say "FAIL: $label gate exited 0 against absent/broken evidence (always-green gate)"; fails=$((fails+1))
  else
    say "NEG OK: $label gate is RED against absent/broken evidence"
  fi
}
neg CM-JEV-DETECTION "$GATES/cm_jev_detection.sh" JEV_DETECTION_FILE="$NOPE" \
    JEV_PROBE_CMD="$FIX/bin/jev-probe-ok.sh" JEV_FIXTURE_ROOT="$FIX"
neg CM-JEV-WIRING "$GATES/cm_jev_wiring.sh" JEV_HOME="$NOPE" JEV_DETECTION_FILE="$FIX/evidence/jev-detection.json"
neg CM-JEV-TOKEN-REDUCTION "$GATES/cm_jev_token_reduction.sh" JEV_BEFORE="$NOPE" JEV_AFTER="$NOPE" \
    JEV_DECISIONS="$NOPE" JEV_STATS_REPORT="$NOPE"
neg CM-JEV-BOOTSTRAP-IDEMPOTENT "$GATES/cm_jev_bootstrap_idempotent.sh" JEV_HOOK_FILE="$NOPE"

# --- propagation gates for the renumbered Jev anchors 279..286 ------------------
# The live repo has no per-feature ledger file (and none is invented here): the
# registration of these gates is the data pack
# scripts/gates/covenant_propagation_anchors.tsv plus the generated wrappers,
# whose drift is checked by covenant_propagation_wrappers_generate.sh --check.
pack_rows() { # pack_rows <file> <n> -> number of rows binding gate N to anchor 11.4.N
  grep -cE "^CM-COVENANT-114-$2-PROPAGATION	11\.4\.$2\$" "$1" || true
}
[ -f "$PACK" ] || { say "FAIL: data pack $PACK missing"; fails=$((fails+1)); }
for n in 279 280 281 282 283 284 285 286; do
  g="$GATES/cm_covenant_114_${n}_propagation.sh"; m="${g%.sh}_mutation_test.sh"
  { [ -f "$g" ] && [ -x "$g" ]; } || { say "FAIL: propagation gate $n missing or not executable"; fails=$((fails+1)); }
  { [ -f "$m" ] && [ -x "$m" ]; } || { say "FAIL: propagation gate $n mutation test missing or not executable"; fails=$((fails+1)); }
  c="$(pack_rows "$PACK" "$n")"
  [ "$c" = "1" ] || { say "FAIL: data pack has $c rows for CM-COVENANT-114-$n-PROPAGATION (want exactly 1)"; fails=$((fails+1)); }
done
# the old numbers must not be bound to Jev: 277/278 rows (if any) map to their own anchor only
for n in 277 278; do
  bad="$(grep -E "^CM-COVENANT-114-$n-PROPAGATION" "$PACK" | grep -vE "	11\.4\.$n\$" || true)"
  [ -z "$bad" ] || { say "FAIL: data pack row $n bound to a different anchor: $bad"; fails=$((fails+1)); }
done
# wrappers match the generator (no drift)
if [ -f "$GEN" ]; then
  if timeout 300 bash "$GEN" --check >/dev/null 2>&1; then say "GEN OK: covenant_propagation_wrappers_generate.sh --check rc 0 (no wrapper drift)"
  else say "FAIL: covenant_propagation_wrappers_generate.sh --check nonzero"; fails=$((fails+1)); fi
else say "FAIL: $GEN missing"; fails=$((fails+1)); fi
# negative controls on the checker itself: a pack with a row removed / mis-bound is rejected
TMPP="$(mktemp -d)"
grep -v "^CM-COVENANT-114-283-PROPAGATION" "$PACK" > "$TMPP/missing.tsv"
[ "$(pack_rows "$TMPP/missing.tsv" 283)" != "1" ] && say "NEG OK: removed 283 row is detected" || { say "FAIL: removed row NOT detected"; fails=$((fails+1)); }
sed 's/^\(CM-COVENANT-114-284-PROPAGATION\t\)11\.4\.284$/\111.4.999/' "$PACK" > "$TMPP/misbound.tsv"
[ "$(pack_rows "$TMPP/misbound.tsv" 284)" != "1" ] && say "NEG OK: mis-bound 284 row is detected" || { say "FAIL: mis-bound row NOT detected"; fails=$((fails+1)); }
# generator --check must be able to FAIL: tamper a copied wrapper
cp -r "$GATES" "$TMPP/gates" 2>/dev/null
if [ -f "$TMPP/gates/covenant_propagation_wrappers_generate.sh" ]; then
  printf '\n# tamper\n' >> "$TMPP/gates/cm_covenant_114_281_propagation.sh"
  if timeout 300 bash "$TMPP/gates/covenant_propagation_wrappers_generate.sh" --check >/dev/null 2>&1; then
    say "FAIL: generator --check accepted a tampered wrapper (cannot fail)"; fails=$((fails+1))
  else say "NEG OK: generator --check rejects a tampered wrapper"; fi
fi
rm -rf "$TMPP"

if [ "$fails" -eq 0 ]; then say "PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent)"; exit 0; fi
say "FAIL ($fails failures)"; exit 1
