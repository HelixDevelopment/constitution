#!/usr/bin/env bash
# cm_bridge_layer_presence_mutation_test.sh — paired §1.1 mutation test for the
# CM-BRIDGE-LAYER-PRESENCE gate (HXC-159 T-B1.02.3).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A gate that cannot FAIL is a bluff gate (§11.4 / §1.1). This test PROVES
# cm_bridge_layer_presence.sh genuinely refuses a phase that declares a
# dependency on a non-WIRED Bridge layer, by pointing it at SANDBOXED
# (mktemp -d, never the real tree — §11.4.84) copies of the deps-file and the
# probe report:
#
#   GOLDEN-GOOD  the real, committed deps-file + the real, latest probe
#                report                                          → gate MUST PASS
#   M1           inject a phase declaring a dependency on L5
#                (measured NONEXISTENT)                          → gate MUST FAIL
#   M2           inject a phase declaring a dependency on an
#                UNKNOWN layer id not present in the report      → gate MUST FAIL
#   NEGATIVE     a phase whose declared layers are ALL genuinely
#   CONTROL      WIRED per the report (mirrors the real B2/B3
#                entries) must still PASS even inside the mutated
#                sandbox — proves the gate discriminates per-entry,
#                not "any mutation in the file" → FAIL-everything
#
# Each mutation additionally asserts the gate names the mutated phase id in its
# FAIL line, so a gate failing for an unrelated reason cannot pass this test.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/gates/cm_bridge_layer_presence_mutation_test.sh [--quiet]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   The real deps-file + the latest real probe report.json (read-only, copied
#   into a sandbox before any mutation).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case + a verdict. Exit 0 — the gate is proven
#   non-bluff. Exit 1 — a mutation did NOT make the gate fail (the gate itself
#   is defective) or a golden-good/negative-control case did not pass.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE on the repo. Every mutation happens inside a `mktemp -d` sandbox
#   removed by the EXIT trap (§11.4.14 / §11.4.84).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3, mktemp, cp. Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 · §11.4.84 (sandbox-only mutation) · gate: cm_bridge_layer_presence.sh
#   · probe: probe_bridge_layers.sh
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

NAME="CM-BRIDGE-LAYER-PRESENCE mutation"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
GATE="$SELF_DIR/cm_bridge_layer_presence.sh"
REAL_DEPS="$ROOT/constitution/scripts/extensions/bridge_phase_layer_deps.json"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { say "  PASS  [$NAME] $*"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

if [ ! -f "$GATE" ]; then
	bad "gate script missing: $GATE"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi
if [ ! -f "$REAL_DEPS" ]; then
	bad "real deps-file missing: $REAL_DEPS"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

LAYERS_DIR="$ROOT/qa-results/hxc159/bridge_layers"
LATEST_RUN=$(ls -1 "$LAYERS_DIR" 2>/dev/null | sort | tail -1)
REAL_REPORT="$LAYERS_DIR/$LATEST_RUN/report.json"
if [ -z "$LATEST_RUN" ] || [ ! -f "$REAL_REPORT" ]; then
	bad "no probe report.json found under $LAYERS_DIR — run probe_bridge_layers.sh first"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

TMP=$(mktemp -d) || { bad "mktemp -d failed"; echo "== $NAME: FAIL ==" >&2; exit 1; }
SANDBOX_DEPS="$TMP/deps.json"
SANDBOX_REPORT="$TMP/report.json"
cp "$REAL_DEPS" "$SANDBOX_DEPS"
cp "$REAL_REPORT" "$SANDBOX_REPORT"

run_gate() {
	# runs the gate against the sandbox files, quiet, returns its exit code
	bash "$GATE" --deps-file "$SANDBOX_DEPS" --report-file "$SANDBOX_REPORT" --quiet >"$TMP/last_gate.out" 2>&1
	echo $?
}

# ── GOLDEN-GOOD — pristine sandbox copy of the real, committed files ─────────
rc=$(run_gate)
if [ "$rc" -eq 0 ]; then
	ok "golden-good: pristine deps-file + latest report → gate PASSes (rc=0)"
else
	bad "golden-good: pristine deps-file + latest report → gate FAILed (rc=$rc) — the gate itself, or the checked-in dependency data, is broken; see $TMP/last_gate.out"
fi

# ── M1 — inject a phase declaring a dependency on L5 (measured NONEXISTENT) ──
python3 - "$SANDBOX_DEPS" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    doc = json.load(fh)
doc["phases"]["MUTATION-M1-L5-DEPENDENCY"] = {
    "title": "paired-mutation fixture — MUST fail the gate",
    "layers": ["L5"],
}
with open(p, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
rc=$(run_gate)
if [ "$rc" -ne 0 ] && grep -q "MUTATION-M1-L5-DEPENDENCY" "$TMP/last_gate.out" && grep -q "\bL5\b" "$TMP/last_gate.out"; then
	ok "M1: phase declaring an L5 dependency → gate FAILs (rc=$rc), naming the mutated phase + layer"
else
	bad "M1: phase declaring an L5 dependency did NOT make the gate fail correctly (rc=$rc); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi
# revert M1 for the next case
cp "$REAL_DEPS" "$SANDBOX_DEPS"

# ── M2 — inject a phase declaring a dependency on an UNKNOWN layer id ────────
python3 - "$SANDBOX_DEPS" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    doc = json.load(fh)
doc["phases"]["MUTATION-M2-UNKNOWN-LAYER"] = {
    "title": "paired-mutation fixture — MUST fail the gate",
    "layers": ["L99-DOES-NOT-EXIST"],
}
with open(p, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
rc=$(run_gate)
if [ "$rc" -ne 0 ] && grep -q "MUTATION-M2-UNKNOWN-LAYER" "$TMP/last_gate.out"; then
	ok "M2: phase declaring a dependency on an unknown layer id → gate FAILs (rc=$rc), naming the mutated phase"
else
	bad "M2: phase declaring a dependency on an unknown layer id did NOT make the gate fail correctly (rc=$rc); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi
# revert M2
cp "$REAL_DEPS" "$SANDBOX_DEPS"

# ── NEGATIVE CONTROL — a phase whose layers are ALL genuinely WIRED per the
#    report must still PASS inside the (otherwise pristine) sandbox — proves
#    the gate discriminates per-entry rather than failing on ANY file edit. ───
python3 - "$SANDBOX_DEPS" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    doc = json.load(fh)
doc["phases"]["NEGATIVE-CONTROL-ALL-WIRED"] = {
    "title": "must PASS — mirrors a real, satisfiable dependency",
    "layers": ["L1", "L2"],
}
with open(p, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
rc=$(run_gate)
if [ "$rc" -eq 0 ] && grep -q "NEGATIVE-CONTROL-ALL-WIRED" "$TMP/last_gate.out"; then
	ok "negative control: a phase declaring only genuinely-WIRED layers still PASSes inside a mutated-elsewhere sandbox (rc=$rc)"
else
	bad "negative control: a phase declaring only genuinely-WIRED layers did NOT pass (rc=$rc) — the gate is failing on ANY edit, not on the specific bad dependency (a false-positive refusal, §11.4.201(1)); output:"
	sed 's/^/         /' "$TMP/last_gate.out" >&2
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $NAME: PASS (4/4 cases) =="
	exit 0
fi
printf '== %s: FAIL (%s failing case(s)) ==\n' "$NAME" "$FAILS" >&2
exit 1
