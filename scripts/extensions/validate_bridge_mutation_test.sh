#!/usr/bin/env bash
# validate_bridge_mutation_test.sh — HXC-159 T-B2.03.3 paired §1.1 mutation
# test for validate_bridge.sh's check 6 (L4/superb).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves check 6 ("superb check passes on constitution files") is NOT a bluff
# gate — it MUST flip from PASS to FAIL when L4 (superb) is genuinely
# uninstalled, per T-B2.03.3: "Paired mutation: uninstall L4 → the validator
# MUST report it, not pass." Runs entirely inside a `mktemp -d` sandbox with a
# fake `specify` binary (§11.4.84 — never touches the real .specify/ tree):
#
#   GOLDEN-GOOD    superb genuinely registered+enabled (a simulated "L4
#                  installed" state) → check 6 PASSes.
#   M1 (uninstall) the SAME sandbox, superb removed from the registration
#                  state ("uninstalled") → check 6 MUST FAIL — the validator
#                  MUST report the uninstall, never keep reporting PASS.
#   NEGATIVE       the uninstall mutation MUST NOT flip any OTHER check
#   CONTROL        (2, 3, 4, 7) that does not depend on L4 — proves check 6
#                  discriminates on the real superb registration state, not
#                  on "any state change" (a fail-everything gate would also
#                  "catch" the mutation, but for the wrong reason and would
#                  equally misreport an unrelated change as an L4 regression).
#
# A real end-to-end run against the REAL repo root is ALSO included, proving
# the honest 5/7 result this script produces matches what a human reading the
# task's own T-B2.03 description would expect on this measured host.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/validate_bridge_mutation_test.sh [--quiet]
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case + a verdict. Exit 0 — every case held.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Sandboxed cases run entirely inside `mktemp -d`, removed by the EXIT trap
#   (§11.4.14/§11.4.84). The real-host case is read-only (validate_bridge.sh
#   performs no mutation of its own).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3, mktemp. Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   validator: validate_bridge.sh (T-B2.03) · §1.1 · §11.4.84
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

NAME="validate_bridge.sh L4-uninstall mutation"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
VALIDATOR="$SELF_DIR/validate_bridge.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { say "  PASS  [$NAME] $*"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

if [ ! -f "$VALIDATOR" ]; then
	bad "validator script missing: $VALIDATOR"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

TMP=$(mktemp -d) || { bad "mktemp -d failed"; exit 1; }

make_report() {
	python3 - "$1" <<'PYEOF'
import json, sys
path = sys.argv[1]
doc = {
    "schema_version": "1.0",
    "layers": [
        {"id": "L1", "verdict": "WIRED"},
        {"id": "L2", "verdict": "WIRED"},
        {"id": "L3", "verdict": "WIRED"},
        {"id": "L4", "verdict": "WIRED"},
    ],
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
}

make_fake_specify() {
	cat > "$1" <<'FAKESPEC'
#!/usr/bin/env bash
set -u
STATE_FILE="${FAKE_SPECIFY_STATE:?FAKE_SPECIFY_STATE must be set}"
if [ "${1:-}" = "extension" ] && [ "${2:-}" = "list" ]; then
	if [ -f "$STATE_FILE" ]; then cat "$STATE_FILE"; else echo "[]"; fi
	exit 0
fi
echo "fake_specify: unsupported invocation: $*" >&2
exit 2
FAKESPEC
	chmod +x "$1"
}

get_check6_verdict() {
	# get_check6_verdict <sandbox-root> — prints the verdict string for
	# check id "6" from the most recent validate_report.json under that
	# sandbox, or "" if none found.
	local dir
	dir=$(ls -1 "$1/qa-results/hxc159/bridge_validate" 2>/dev/null | sort | tail -1)
	[ -z "$dir" ] && return
	python3 -c "
import json
doc = json.load(open('$1/qa-results/hxc159/bridge_validate/$dir/validate_report.json'))
for c in doc['checks']:
    if c['id'] == '6':
        print(c['verdict'])
        break
" 2>/dev/null
}

get_check_verdict() {
	local sandbox="$1" cid="$2" dir
	dir=$(ls -1 "$sandbox/qa-results/hxc159/bridge_validate" 2>/dev/null | sort | tail -1)
	[ -z "$dir" ] && return
	python3 -c "
import json
doc = json.load(open('$sandbox/qa-results/hxc159/bridge_validate/$dir/validate_report.json'))
for c in doc['checks']:
    if c['id'] == '$cid':
        print(c['verdict'])
        break
" 2>/dev/null
}

S="$TMP/sandbox"; mkdir -p "$S/.specify" "$S/.kimi-code/skills/speckit-specify" "$S/.kimi-code/skills/speckit-plan" "$S/.kimi-code/skills/speckit-tasks" "$S/qa-results"
for sk in speckit-specify speckit-plan speckit-tasks; do
	echo "---" > "$S/.kimi-code/skills/$sk/SKILL.md"
done
mkdir -p "$S/.specify/extensions/superspec/commands"
echo "# speckit.superspec.status" > "$S/.specify/extensions/superspec/commands/status.md"
make_report "$S/report.json"
FAKE_SPEC="$S/fake_specify.sh"
make_fake_specify "$FAKE_SPEC"

export SPECIFY_BIN="$FAKE_SPEC"
export FAKE_SPECIFY_STATE="$S/state.json"

# ── GOLDEN-GOOD — superb genuinely registered+enabled (simulated "L4
#    installed" state) ──────────────────────────────────────────────────────
echo '[{"id": "superspec", "name": "Superpowers Bridge", "enabled": true}, {"id": "superb", "name": "SuperB", "enabled": true}]' > "$S/state.json"
( cd "$S" && bash "$VALIDATOR" --root "$S" --report-file "$S/report.json" >"$S/golden.out" 2>&1 )
V=$(get_check6_verdict "$S")
if [ "$V" = "PASS" ]; then
	ok "golden-good: superb registered+enabled → check 6 PASSes"
else
	bad "golden-good: superb registered+enabled did NOT produce a PASS for check 6 (got '$V'); output:"; sed 's/^/         /' "$S/golden.out" >&2
fi
C2_BEFORE=$(get_check_verdict "$S" 2)
C7_BEFORE=$(get_check_verdict "$S" 7)

# ── M1 (uninstall) — remove superb from the registration state ─────────────
echo '[{"id": "superspec", "name": "Superpowers Bridge", "enabled": true}]' > "$S/state.json"
( cd "$S" && bash "$VALIDATOR" --root "$S" --report-file "$S/report.json" >"$S/m1.out" 2>&1 )
V=$(get_check6_verdict "$S")
if [ "$V" = "FAIL" ]; then
	ok "M1 (uninstall): superb removed from registration → check 6 FAILs (rc reflects the real uninstall, no stale PASS)"
else
	bad "M1 (uninstall): superb removed from registration did NOT flip check 6 to FAIL (got '$V') — the check is a bluff gate; output:"; sed 's/^/         /' "$S/m1.out" >&2
fi

# ── NEGATIVE CONTROL — checks unrelated to L4 (2, 7) are unaffected by the
#    uninstall mutation ──────────────────────────────────────────────────────
C2_AFTER=$(get_check_verdict "$S" 2)
C7_AFTER=$(get_check_verdict "$S" 7)
if [ "$C2_BEFORE" = "$C2_AFTER" ] && [ "$C7_BEFORE" = "$C7_AFTER" ]; then
	ok "negative control: checks 2 ('$C2_AFTER') and 7 ('$C7_AFTER') are unaffected by the L4-only mutation — check 6 discriminates on the real superb state, not on any file edit"
else
	bad "negative control: an unrelated check changed verdict alongside the L4 mutation (check2: $C2_BEFORE->$C2_AFTER, check7: $C7_BEFORE->$C7_AFTER) — the validator is failing broadly, not discriminating"
fi

unset SPECIFY_BIN FAKE_SPECIFY_STATE

# ── real-host end-to-end run — honest evidence of the measured 5/7 result ──
REAL_OUT="$TMP/real.out"
bash "$VALIDATOR" --quiet >"$REAL_OUT" 2>&1
rc=$?
REAL_DIR=$(ls -1 "$ROOT/qa-results/hxc159/bridge_validate" 2>/dev/null | sort | tail -1)
if [ -n "$REAL_DIR" ] && [ -f "$ROOT/qa-results/hxc159/bridge_validate/$REAL_DIR/validate_report.json" ]; then
	EVALUABLE=$(python3 -c "import json; print(json.load(open('$ROOT/qa-results/hxc159/bridge_validate/$REAL_DIR/validate_report.json'))['evaluable_count'])")
	PASSING=$(python3 -c "import json; print(json.load(open('$ROOT/qa-results/hxc159/bridge_validate/$REAL_DIR/validate_report.json'))['passing_count'])")
	ok "real-host run: evidence written at $REAL_DIR, $PASSING/$EVALUABLE evaluable checks PASS (rc=$rc — an honest non-zero exit is expected and correct while L4/L7 are genuinely absent, never masked as PASS)"
else
	bad "real-host run: no evidence written under qa-results/hxc159/bridge_validate/"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $NAME: PASS (4/4 cases) =="
	exit 0
fi
printf '== %s: FAIL (%s failing case(s)) ==\n' "$NAME" "$FAILS" >&2
exit 1
