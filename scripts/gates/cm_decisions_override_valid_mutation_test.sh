#!/usr/bin/env bash
# cm_decisions_override_valid_mutation_test.sh — paired §1.1 mutation test for CM-DECISIONS-OVERRIDE-VALID.
# Baseline: golden-good project PASS (0), weakening project FAIL (1), hand-edited project FAIL (1), no file SKIP (3),
# stale managed block with no file FAIL (1).
# Each mutant copies the REAL wizard into a mktemp dir, breaks one rule, and the gate MUST NOT PASS a bad project.
# Exit 0 = every mutant killed and baseline correct; 1 otherwise. Classification: universal (§11.4.17).
set -uo pipefail
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
gate="$const/scripts/gates/cm_decisions_override_valid.sh"
. "$const/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_dec_valid_mut.XXXXXX")" || exit 1
trap 'safe_rm_rf "${tmp:?}"' EXIT
export CONSTITUTION_DECISIONS_USER_FILE="$tmp/user.yml"
mk() { local p="$tmp/$1"; mkdir -p "$p/.constitution"; printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  %s\n' "$2" >"$p/.constitution/decisions.yml"
  [ "$3" = sha ] && sha256sum "$p/.constitution/decisions.yml" | cut -d' ' -f1 >"$p/.constitution/decisions.sha256"; printf '%s' "$p"; }
good="$(mk good 'calibration.floor: 0.95' sha)"; weak="$(mk weak 'calibration.floor: 0.5' sha)"
locked="$(mk locked 'hosted.enforce: true' sha)"; edited="$(mk edited 'calibration.floor: 0.96' none)"
unknown="$(mk unknown 'bogus.key: 1' sha)"; secret="$(mk secret "llmctl.download_profile: sk-$(printf 'W%.0s' $(seq 1 30))" sha)"
mkdir -p "$tmp/empty" "$tmp/orphan"
printf '# O\n<!-- BEGIN constitution-decisions -->\nstale\n<!-- END constitution-decisions -->\n' >"$tmp/orphan/AGENTS.md"
pass=0; fail=0
want() { local name="$1" w="$2"; shift 2; "$@" >/dev/null 2>&1; local rc=$?; if [ "$rc" = "$w" ]; then pass=$((pass+1)); echo "  ok   $name rc=$rc"; else fail=$((fail+1)); echo "  BAD  $name rc=$rc want $w"; fi; }
echo "baseline:"
want good 0 bash "$gate" --root "$good"; want weak 1 bash "$gate" --root "$weak"; want locked 1 bash "$gate" --root "$locked"
want edited 1 bash "$gate" --root "$edited"; want unknown 1 bash "$gate" --root "$unknown"; want secret 1 bash "$gate" --root "$secret"
want empty 3 bash "$gate" --root "$tmp/empty"; want orphan 1 bash "$gate" --root "$tmp/orphan"
mutant() { # name, old, new, bad-project
  local m="$tmp/mut_$1"; mkdir -p "$m"; cp "$const/scripts/decisions/constitution_decisions.sh" "$const/scripts/decisions/decisions_engine.py" "$m/"
  python3 -I - "$m/decisions_engine.py" "$2" "$3" <<'PY' || { echo "  BAD  mutant $1 did not apply"; fail=$((fail+1)); return; }
import sys; p, old, new = sys.argv[1:]; s = open(p).read()
if old not in s: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  DECISIONS_CLI="$m/constitution_decisions.sh" bash "$gate" --root "$4" >"$m/out" 2>&1; local rc=$?
  if [ "$rc" != 0 ]; then pass=$((pass+1)); echo "  killed  $1 (gate rc=$rc: $(head -c 120 "$m/out"))"; else fail=$((fail+1)); echo "  SURVIVED $1"; fi
}
echo "mutants:"
mutant MV1_floor_unbounded '"min": 0.90, "max": 1.0' '"min": 0.0, "max": 1.0' "$weak"
mutant MV2_locked_ignored 'if "locked" in extra and v != extra["locked"]:' 'if False:' "$locked"
mutant MV3_unknown_key_accepted 'raise Refused("unknown decision key %s" % key_label(key))' 'return ("nint", None, {"min": 0, "max": 10, "anchor": "x"})' "$unknown"
mutant MV4_secret_ignored 'return any(r.search(s) for r in SECRET_RES)' 'return False' "$secret"
mutant MV5_tamper_ignored 'self.external_edit = sha_text(self.ptext) not in (side, intent)' 'self.external_edit = False' "$edited"
mutant MV6_refusal_exit_0 '        emit_err("constitution_decisions: refused: %s" % redact(exc))
        return 4' '        emit_err("constitution_decisions: refused: %s" % redact(exc))
        return 0' "$weak"
mutant MV7_drift_ignored '        if drift:' '        if False:' "$weak"
mutant MV8_orphan_ignored '        if orphan:' '        if False:' "$tmp/orphan"
echo "cm_decisions_override_valid mutation test: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
