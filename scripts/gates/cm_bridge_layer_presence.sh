#!/usr/bin/env bash
# cm_bridge_layer_presence.sh — CM-BRIDGE-LAYER-PRESENCE gate (HXC-159 T-B1.02).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Any project phase that declares a dependency on a Bridge layer (per
# constitution/scripts/extensions/probe_bridge_layers.sh's L1..L7 vocabulary)
# MUST FAIL LOUDLY, at this gate, if that layer's LIVE measured verdict is not
# WIRED — instead of silently proceeding against an absent/partial/designed-only
# layer and discovering the gap deep inside the phase's own work (§11.4.108
# SOURCE-vs-RUNTIME gap; §11.4.201 — a false-positive PASS here is exactly the
# class of guard bluff that anchor forbids).
#
# Per-phase dependencies are declared as DATA (never hardcoded in this script),
# in constitution/scripts/extensions/bridge_phase_layer_deps.json (T-B1.02.1).
# This gate reads that file, reads the MOST RECENT
# qa-results/hxc159/bridge_layers/<run-id>/report.json produced by the probe
# (T-B1.02.2 cross-check against the live report — never a cached assumption),
# and FAILs on any declared-layer verdict that is not exactly "WIRED".
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/gates/cm_bridge_layer_presence.sh \
#       [--root <repo-root>] [--deps-file <path>] [--report-file <path>] [--quiet]
#
#   --root         repo root to resolve default deps-file/report-file paths
#                   against (defaults to two levels above this script).
#   --deps-file    override the phase→layer dependency data file (used by the
#                   paired §1.1 mutation test to point at a sandboxed, mutated
#                   copy — the REAL tree is never mutated, §11.4.84).
#   --report-file  override which probe report.json to check against (defaults
#                   to the lexicographically-latest run under
#                   qa-results/hxc159/bridge_layers/, since run-ids are UTC
#                   timestamps and therefore sort chronologically).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   constitution/scripts/extensions/bridge_phase_layer_deps.json (or --deps-file)
#   qa-results/hxc159/bridge_layers/<run-id>/report.json (or --report-file)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per declared phase→layer dependency + a verdict line.
#   Exit 0 — every declared dependency resolves to WIRED. Exit 1 — one or more
#   does not (or the deps-file / report-file is missing/unreadable — CONSERVATIVE
#   DEFAULT per §11.4.201: an unresolvable precondition REFUSES, it never
#   silently PASSes).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   NONE. Read-only against both input files.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (JSON parsing). Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/tasks.md Phase B1 (T-B1.02) ·
#   probe_bridge_layers.sh (T-B1.01, the report producer) · §11.4.108 ·
#   §11.4.110 (change-impact clash detection — this is the layer-dependency
#   instance) · §11.4.201 (guard asserts the REAL condition; conservative
#   default on an unresolvable signal) · §1.1 (paired mutation:
#   cm_bridge_layer_presence_mutation_test.sh)
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

GATE="CM-BRIDGE-LAYER-PRESENCE"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
# SELF_DIR = <repo-root>/constitution/scripts/gates — three levels up is the
# OUTER repo root (qa-results/ lives there, NOT inside the constitution
# submodule), distinct from other gates in this dir whose ROOT means the
# constitution submodule root. This gate's inputs cross that boundary
# deliberately: the deps-file is constitution-owned, the report-file is
# repo-root-owned (qa-results/hxc159/...).
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
DEPS_FILE=""
REPORT_FILE=""
QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--root)        shift; ROOT="$1" ;;
		--deps-file)   shift; DEPS_FILE="$1" ;;
		--report-file) shift; REPORT_FILE="$1" ;;
		--quiet)       QUIET=1 ;;
		-h|--help)     sed -n '3,50p' "$0"; exit 0 ;;
		*) echo "$GATE: unknown arg: $1" >&2; exit 2 ;;
	esac
	shift || true
done

[ -n "$DEPS_FILE" ] || DEPS_FILE="$ROOT/constitution/scripts/extensions/bridge_phase_layer_deps.json"

if [ -z "$REPORT_FILE" ]; then
	LAYERS_DIR="$ROOT/qa-results/hxc159/bridge_layers"
	if [ -d "$LAYERS_DIR" ]; then
		# run-ids are UTC timestamps (YYYYMMDDTHHMMSSZ) — lexicographic sort IS
		# chronological sort. `ls -1` + tail picks the latest without assuming
		# mtime ordering survives a git checkout/copy (§11.4.6 — mtime is not
		# a trustworthy ordering signal after a tree copy).
		LATEST_RUN=$(ls -1 "$LAYERS_DIR" 2>/dev/null | sort | tail -1)
		[ -n "$LATEST_RUN" ] && REPORT_FILE="$LAYERS_DIR/$LATEST_RUN/report.json"
	fi
fi

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
pass() { say "  PASS  [$GATE] $*"; }
fail() { printf '  FAIL  [%s] %s\n' "$GATE" "$*" >&2; }

say "== $GATE =="
say "   deps-file:   $DEPS_FILE"
say "   report-file: ${REPORT_FILE:-<none found>}"

# ── conservative-default refusals (§11.4.201) — an unresolvable precondition
#    REFUSES the gate, it never silently proceeds as if everything were WIRED. ─
if [ ! -f "$DEPS_FILE" ]; then
	fail "deps-file MISSING: $DEPS_FILE — cannot determine any phase's layer dependencies"
	exit 1
fi
if [ -z "${REPORT_FILE:-}" ] || [ ! -f "$REPORT_FILE" ]; then
	fail "no probe report.json found (looked under qa-results/hxc159/bridge_layers/) — run probe_bridge_layers.sh first; a missing report is NOT evidence every layer is WIRED"
	exit 1
fi

python3 - "$DEPS_FILE" "$REPORT_FILE" <<'PYEOF'
import json, sys

deps_path, report_path = sys.argv[1], sys.argv[2]

try:
    with open(deps_path, encoding="utf-8") as fh:
        deps_doc = json.load(fh)
except Exception as e:
    print(f"  FAIL  [CM-BRIDGE-LAYER-PRESENCE] deps-file is not valid JSON: {deps_path} ({e})", file=sys.stderr)
    sys.exit(1)

try:
    with open(report_path, encoding="utf-8") as fh:
        report_doc = json.load(fh)
except Exception as e:
    print(f"  FAIL  [CM-BRIDGE-LAYER-PRESENCE] report-file is not valid JSON: {report_path} ({e})", file=sys.stderr)
    sys.exit(1)

verdict_by_layer = {}
for layer in report_doc.get("layers", []):
    lid = layer.get("id")
    if lid:
        verdict_by_layer[lid] = layer.get("verdict")

phases = deps_doc.get("phases", {})
if not isinstance(phases, dict):
    print("  FAIL  [CM-BRIDGE-LAYER-PRESENCE] deps-file 'phases' key is not an object", file=sys.stderr)
    sys.exit(1)

fails = 0
checked = 0
for phase_id, phase in sorted(phases.items()):
    layers = phase.get("layers", []) if isinstance(phase, dict) else []
    for lid in layers:
        checked += 1
        verdict = verdict_by_layer.get(lid)
        if verdict is None:
            print(f"  FAIL  [CM-BRIDGE-LAYER-PRESENCE] phase {phase_id} declares dependency on unknown layer '{lid}' — not present in {report_path}", file=sys.stderr)
            fails += 1
        elif verdict != "WIRED":
            print(f"  FAIL  [CM-BRIDGE-LAYER-PRESENCE] phase {phase_id} declares dependency on layer {lid}, whose measured verdict is '{verdict}' (not WIRED) per {report_path}", file=sys.stderr)
            fails += 1
        else:
            print(f"  PASS  [CM-BRIDGE-LAYER-PRESENCE] phase {phase_id} → layer {lid}: WIRED")

if checked == 0:
    print("  PASS  [CM-BRIDGE-LAYER-PRESENCE] no phase declares any Bridge layer dependency (vacuously satisfied)")

if fails == 0:
    print(f"== CM-BRIDGE-LAYER-PRESENCE: PASS ({checked} dependency check(s), 0 failing) ==")
    sys.exit(0)
else:
    print(f"== CM-BRIDGE-LAYER-PRESENCE: FAIL ({fails}/{checked} dependency check(s) failing) ==", file=sys.stderr)
    sys.exit(1)
PYEOF
exit $?
