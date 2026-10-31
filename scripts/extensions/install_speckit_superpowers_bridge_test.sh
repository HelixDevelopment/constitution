#!/usr/bin/env bash
# install_speckit_superpowers_bridge_test.sh — HXC-159 T-B2.02 test suite for
# install_speckit_superpowers_bridge.sh (unit + integration + full-automation +
# chaos, per the task's mandated test-type set; §11.4.169/§11.4.224/§11.4.85).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the installer's decision logic AND its interrupted-install resilience
# through a REAL invocation of the installer script — never a re-implementation
# of its logic in the test (§1.1 requires testing the actual artifact). Cases:
#
#   UNIT-1        L1 not WIRED → installer refuses (rc!=0), no mutation.
#   UNIT-2        L2 not WIRED → installer refuses (rc!=0), no mutation,
#                 NEVER calls the fake `specify init`-equivalent.
#   UNIT-3        --superb-from given without --superb-vetted-by (partial
#                 override) → installer refuses (rc!=0).
#   UNIT-4        default state (L3 WIRED + pin verified, L4 DESIGNED-ONLY,
#                 no operator vetting supplied) → installer PASSES (rc=0),
#                 L4 is reported "skipped-not-vetted", NOT installed.
#   INTEGRATION-1 a real end-to-end run against the REAL repo root (no
#                 sandboxing) — proves the script genuinely drives the real
#                 `specify` CLI and the real probe, not a mock of either.
#   FULL-AUTO-1   the installer is re-run twice in a row against the real repo
#                 root and BOTH runs PASS with byte-for-byte-equivalent
#                 install_report.json content (idempotency, §11.4.50) —
#                 no manual step, fully autonomous per §11.4.98.
#   CHAOS-1       an operator-vetted L4 install is started against a fake
#                 `specify` binary configured to hang mid-write; the test
#                 harness SIGKILLs the whole process tree while the fake
#                 binary has already created a PARTIAL, unregistered
#                 .specify/extensions/superb/ directory (simulating a real
#                 interrupted install per §11.4.85); the installer is then
#                 RE-RUN with the same flags against the same sandbox and MUST
#                 detect + clean the stale partial state and complete
#                 successfully — proving no broken/partial state survives an
#                 interruption.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/install_speckit_superpowers_bridge_test.sh [--quiet]
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case + a verdict. Exit 0 — every case held.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   UNIT/CHAOS cases run entirely inside `mktemp -d` sandboxes removed by the
#   EXIT trap (§11.4.14/§11.4.84) — they NEVER touch the real .specify/ tree.
#   INTEGRATION-1 and FULL-AUTO-1 run the REAL installer against the REAL repo
#   root; on THIS measured host both are no-ops for L3 (already WIRED) and
#   skip L4 (not vetted) — i.e. still read-only against .specify/, evidence
#   only written under qa-results/hxc159/bridge_install/. If a future host has
#   L3 genuinely absent, these cases would perform a real pinned install; that
#   risk is accepted because it is the documented, intended behaviour under
#   test, not a side-effect of the TEST harness itself.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3, mktemp, git (for the sandbox git-repo fixtures), the real
#   `specify` CLI (integration/full-auto cases only). Parses clean under
#   `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   installer: install_speckit_superpowers_bridge.sh · §1.1 · §11.4.50 · §11.4.85
#   · §11.4.98 · §11.4.169 · §11.4.224 · §11.4.84 (sandbox-only mutation)
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

NAME="install_speckit_superpowers_bridge tests"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
INSTALLER="$SELF_DIR/install_speckit_superpowers_bridge.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { say "  PASS  [$NAME] $*"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

if [ ! -f "$INSTALLER" ]; then
	bad "installer script missing: $INSTALLER"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

TMP=$(mktemp -d) || { bad "mktemp -d failed"; exit 1; }

# ── shared fixture helpers ───────────────────────────────────────────────────
make_report() {
	# make_report <path> <l1> <l2> <l3> <l4>
	python3 - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import json, sys
path, l1, l2, l3, l4 = sys.argv[1:6]
doc = {
    "schema_version": "1.0",
    "layers": [
        {"id": "L1", "verdict": l1},
        {"id": "L2", "verdict": l2},
        {"id": "L3", "verdict": l3},
        {"id": "L4", "verdict": l4},
    ],
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
}

make_fake_specify() {
	# make_fake_specify <path-to-script> <state-file>
	cat > "$1" <<'FAKESPEC'
#!/usr/bin/env bash
# Minimal fake `specify` CLI for install_speckit_superpowers_bridge_test.sh
# sandboxed cases. NEVER used against the real repo.
set -u
STATE_FILE="${FAKE_SPECIFY_STATE:?FAKE_SPECIFY_STATE must be set}"
EXT_ROOT="$(dirname "$STATE_FILE")/.specify/extensions"

if [ "${1:-}" = "extension" ] && [ "${2:-}" = "list" ]; then
	if [ -f "$STATE_FILE" ]; then cat "$STATE_FILE"; else echo "[]"; fi
	exit 0
fi

if [ "${1:-}" = "extension" ] && [ "${2:-}" = "add" ]; then
	id="${3:-}"
	from=""
	shift 3 2>/dev/null || true
	while [ $# -gt 0 ]; do
		case "$1" in
			--from) shift; from="$1" ;;
		esac
		shift || true
	done
	mkdir -p "$EXT_ROOT/$id"
	echo "partial" > "$EXT_ROOT/$id/.install-in-progress"
	if [ "${FAKE_SPECIFY_HANG:-0}" = "1" ]; then
		sleep 60
	fi
	python3 - "$STATE_FILE" "$id" <<PYEOF
import json, os
state_file = "$STATE_FILE"
eid = "$id"
try:
    with open(state_file, encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception:
    doc = []
doc = [e for e in doc if e.get("id") != eid]
doc.append({"id": eid, "name": eid, "version": "1.0.0", "enabled": True})
with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(doc, fh)
PYEOF
	rm -f "$EXT_ROOT/$id/.install-in-progress"
	echo "installed $id from $from"
	exit 0
fi

echo "fake_specify: unsupported invocation: $*" >&2
exit 2
FAKESPEC
	chmod +x "$1"
}

run_installer() {
	# run_installer <sandbox-root> <report-file> [extra installer args...]
	local sandbox="$1" report="$2"
	shift 2
	mkdir -p "$sandbox/qa-results"
	( cd "$sandbox" && bash "$INSTALLER" --root "$sandbox" --report-file "$report" --quiet "$@" >"$sandbox/last_run.out" 2>&1 )
	echo $?
}

latest_install_report() {
	# latest_install_report <sandbox-root> — prints the path to the most
	# recent install_report.json this run produced under that sandbox
	# (--quiet suppresses `say`-level narration on stdout, so assertions
	# about non-warning outcomes MUST read the JSON evidence file, never
	# grep last_run.out for anything other than a `warn`-level FATAL line).
	local dir
	dir=$(ls -1 "$1/qa-results/hxc159/bridge_install" 2>/dev/null | sort | tail -1)
	[ -n "$dir" ] && echo "$1/qa-results/hxc159/bridge_install/$dir/install_report.json"
}

# ── UNIT-1 — L1 not WIRED → refuse ───────────────────────────────────────────
S1="$TMP/u1"; mkdir -p "$S1"
make_report "$S1/report.json" "PARTIAL" "WIRED" "WIRED" "DESIGNED-ONLY"
rc=$(run_installer "$S1" "$S1/report.json")
if [ "$rc" -ne 0 ] && grep -q "L1 (developer workstation)" "$S1/last_run.out"; then
	ok "UNIT-1: L1 not WIRED → installer refuses (rc=$rc), naming L1"
else
	bad "UNIT-1: L1 not WIRED did not refuse correctly (rc=$rc); output:"; sed 's/^/         /' "$S1/last_run.out" >&2
fi

# ── UNIT-2 — L2 not WIRED → refuse, never attempts an init-equivalent ───────
S2="$TMP/u2"; mkdir -p "$S2"
make_report "$S2/report.json" "WIRED" "DESIGNED-ONLY" "WIRED" "DESIGNED-ONLY"
rc=$(run_installer "$S2" "$S2/report.json")
if [ "$rc" -ne 0 ] && grep -q "NEVER runs 'specify init'" "$S2/last_run.out"; then
	ok "UNIT-2: L2 not WIRED → installer refuses (rc=$rc), explicitly never calling init"
else
	bad "UNIT-2: L2 not WIRED did not refuse correctly (rc=$rc); output:"; sed 's/^/         /' "$S2/last_run.out" >&2
fi

# ── UNIT-3 — partial superb override (--superb-from without --superb-vetted-by) ──
S3="$TMP/u3"; mkdir -p "$S3"
make_report "$S3/report.json" "WIRED" "WIRED" "WIRED" "DESIGNED-ONLY"
export SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81"
rc=$(run_installer "$S3" "$S3/report.json" --superb-from "https://example.invalid/superpowers-bridge.zip")
unset SUPERSPEC_SHA_OVERRIDE
if [ "$rc" -ne 0 ] && grep -q "must both be supplied together" "$S3/last_run.out"; then
	ok "UNIT-3: --superb-from without --superb-vetted-by → installer refuses (rc=$rc)"
else
	bad "UNIT-3: partial superb override did not refuse correctly (rc=$rc); output:"; sed 's/^/         /' "$S3/last_run.out" >&2
fi

# ── UNIT-4 — default state: L3 WIRED+pin verified, L4 not vetted → PASS,
#    L4 explicitly skipped not installed ────────────────────────────────────
S4="$TMP/u4"; mkdir -p "$S4"
make_report "$S4/report.json" "WIRED" "WIRED" "WIRED" "DESIGNED-ONLY"
FAKE_SPEC="$S4/fake_specify.sh"
make_fake_specify "$FAKE_SPEC" "$S4/state.json"
mkdir -p "$S4/.specify"
# seed state.json with the already-registered L3 entry a real host would
# show (superspec is measured WIRED per the synthetic report above) — proves
# RS-19 passes on the pre-existing L3 registration, never on a phantom L4
# entry this test must show was NEVER written.
echo '[{"id": "superspec", "name": "Superpowers Bridge", "version": "1.0.2", "enabled": true}]' > "$S4/state.json"
STATE_BEFORE=$(cat "$S4/state.json")
export SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81"
export SPECIFY_BIN="$FAKE_SPEC"
export FAKE_SPECIFY_STATE="$S4/state.json"
rc=$(run_installer "$S4" "$S4/report.json")
unset SUPERSPEC_SHA_OVERRIDE SPECIFY_BIN FAKE_SPECIFY_STATE
STATE_AFTER=$(cat "$S4/state.json")
S4_REPORT=$(latest_install_report "$S4")
S4_L4_STATUS=""
[ -n "$S4_REPORT" ] && [ -f "$S4_REPORT" ] && S4_L4_STATUS=$(python3 -c "import json; print(json.load(open('$S4_REPORT')).get('L4_status',''))" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$S4_L4_STATUS" = "skipped-not-vetted" ] && [ "$STATE_AFTER" = "$STATE_BEFORE" ] && ! grep -q '"id": "superb"' "$S4/state.json"; then
	ok "UNIT-4: default (un-vetted) state → installer PASSes, L4 reported skipped ('$S4_L4_STATUS'), no state mutation (superb never registered)"
else
	bad "UNIT-4: default state did not behave correctly (rc=$rc); output:"; sed 's/^/         /' "$S4/last_run.out" >&2
fi

# ── INTEGRATION-1 — real end-to-end run against the REAL repo root ─────────
REAL_OUT="$TMP/integration1.out"
bash "$INSTALLER" --quiet >"$REAL_OUT" 2>&1
rc=$?
LATEST_INSTALL_RUN=$(ls -1 "$ROOT/qa-results/hxc159/bridge_install" 2>/dev/null | sort | tail -1)
if [ "$rc" -eq 0 ] && [ -n "$LATEST_INSTALL_RUN" ] && [ -f "$ROOT/qa-results/hxc159/bridge_install/$LATEST_INSTALL_RUN/install_report.json" ]; then
	ok "INTEGRATION-1: real run against the real repo root PASSes (rc=$rc), evidence written at $LATEST_INSTALL_RUN"
else
	bad "INTEGRATION-1: real run did not PASS correctly (rc=$rc); output:"; sed 's/^/         /' "$REAL_OUT" >&2
fi

# ── FULL-AUTOMATION-1 — two consecutive real runs, fully autonomous, both
#    PASS with equivalent (idempotent) per-layer status fields ─────────────
RUN_A_DIR=$(ls -1 "$ROOT/qa-results/hxc159/bridge_install" 2>/dev/null | sort | tail -1)
bash "$INSTALLER" --quiet >"$TMP/fa2.out" 2>&1
rc2=$?
RUN_B_DIR=$(ls -1 "$ROOT/qa-results/hxc159/bridge_install" 2>/dev/null | sort | tail -1)
if [ "$rc2" -eq 0 ] && [ -n "$RUN_A_DIR" ] && [ -n "$RUN_B_DIR" ] && [ "$RUN_A_DIR" != "$RUN_B_DIR" ]; then
	A_JSON=$(python3 -c "import json; d=json.load(open('$ROOT/qa-results/hxc159/bridge_install/$RUN_A_DIR/install_report.json')); print(d['L3_status'], d['L4_status'], d['overall_status'])")
	B_JSON=$(python3 -c "import json; d=json.load(open('$ROOT/qa-results/hxc159/bridge_install/$RUN_B_DIR/install_report.json')); print(d['L3_status'], d['L4_status'], d['overall_status'])")
	if [ "$A_JSON" = "$B_JSON" ]; then
		ok "FULL-AUTOMATION-1: two consecutive fully-autonomous real runs both PASS with identical per-layer status ('$A_JSON') — idempotent re-run proven"
	else
		bad "FULL-AUTOMATION-1: two consecutive runs produced DIFFERENT status ('$A_JSON' vs '$B_JSON') — not idempotent"
	fi
else
	bad "FULL-AUTOMATION-1: second autonomous run did not PASS correctly (rc=$rc2)"
fi

# ── CHAOS-1 — interrupted operator-vetted L4 install, then clean re-run ────
SC="$TMP/chaos1"; mkdir -p "$SC"
make_report "$SC/report.json" "WIRED" "WIRED" "WIRED" "DESIGNED-ONLY"
FAKE_SPEC_C="$SC/fake_specify.sh"
make_fake_specify "$FAKE_SPEC_C" "$SC/state.json"
mkdir -p "$SC/.specify"
echo "[]" > "$SC/state.json"
mkdir -p "$SC/qa-results"

export SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81"
export SPECIFY_BIN="$FAKE_SPEC_C"
export FAKE_SPECIFY_STATE="$SC/state.json"
export FAKE_SPECIFY_HANG=1

( cd "$SC" && bash "$INSTALLER" --root "$SC" --report-file "$SC/report.json" --quiet \
	--superb-from "https://example.invalid/releases/download/v1.9.0/superpowers-bridge.zip" \
	--superb-vetted-by "operator:test-harness — HXC-159 T-B2.02 chaos case" \
	>"$SC/interrupted_run.out" 2>&1 ) &
INSTALLER_PID=$!

# wait for the fake specify to actually start writing the partial extension
# dir (proves we killed it MID-install, not before or after) — poll instead
# of a fixed sleep (§11.4.6 no-guessing about timing).
WAITED=0
while [ ! -d "$SC/.specify/extensions/superb" ] && [ "$WAITED" -lt 100 ]; do
	sleep 0.1
	WAITED=$((WAITED + 1))
done
PARTIAL_DIR_APPEARED=0
[ -d "$SC/.specify/extensions/superb" ] && PARTIAL_DIR_APPEARED=1

# SIGKILL the whole process group so the fake specify's `sleep 60` dies too,
# simulating a genuine interrupted install (not a graceful shutdown).
case "$INSTALLER_PID" in ''|*[!0-9]*) ;; *) [ "$INSTALLER_PID" -gt 1 ] && kill -9 -- -"$INSTALLER_PID" 2>/dev/null ;; esac   # 11.4.263: integer > 1 only
kill -9 "$INSTALLER_PID" 2>/dev/null
wait "$INSTALLER_PID" 2>/dev/null

STALE_MARKER_PRESENT=0
[ -f "$SC/.specify/extensions/superb/.install-in-progress" ] && STALE_MARKER_PRESENT=1
NOT_YET_REGISTERED=1
grep -q '"id": "superb"' "$SC/state.json" 2>/dev/null && NOT_YET_REGISTERED=0

if [ "$PARTIAL_DIR_APPEARED" -eq 1 ] && [ "$STALE_MARKER_PRESENT" -eq 1 ] && [ "$NOT_YET_REGISTERED" -eq 1 ]; then
	ok "CHAOS-1 setup: interruption genuinely captured mid-install (partial dir present, in-progress marker present, NOT registered in state)"
else
	bad "CHAOS-1 setup: could not reliably capture a genuine mid-install interruption (partial_dir=$PARTIAL_DIR_APPEARED marker=$STALE_MARKER_PRESENT unregistered=$NOT_YET_REGISTERED) — case inconclusive"
fi

# now disable the hang and re-run the SAME installer invocation against the
# SAME sandbox — it must detect + clean the stale partial state and complete.
unset FAKE_SPECIFY_HANG
bash "$INSTALLER" --root "$SC" --report-file "$SC/report.json" --quiet \
	--superb-from "https://example.invalid/releases/download/v1.9.0/superpowers-bridge.zip" \
	--superb-vetted-by "operator:test-harness — HXC-159 T-B2.02 chaos case" \
	>"$SC/recovery_run.out" 2>&1
rc=$?
unset SUPERSPEC_SHA_OVERRIDE SPECIFY_BIN FAKE_SPECIFY_STATE

REGISTERED_AFTER_RECOVERY=0
grep -q '"id": "superb"' "$SC/state.json" 2>/dev/null && REGISTERED_AFTER_RECOVERY=1
STALE_MARKER_GONE=1
[ -f "$SC/.specify/extensions/superb/.install-in-progress" ] && STALE_MARKER_GONE=0

if [ "$rc" -eq 0 ] && [ "$REGISTERED_AFTER_RECOVERY" -eq 1 ] && [ "$STALE_MARKER_GONE" -eq 1 ]; then
	ok "CHAOS-1 recovery: re-run after a SIGKILL-interrupted install cleans stale state and completes successfully (rc=$rc, superb registered, no stale in-progress marker)"
else
	bad "CHAOS-1 recovery: re-run after interruption did NOT cleanly recover (rc=$rc registered=$REGISTERED_AFTER_RECOVERY marker_gone=$STALE_MARKER_GONE); output:"
	sed 's/^/         /' "$SC/recovery_run.out" >&2
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$FAILS" -eq 0 ]; then
	say "== $NAME: PASS (8/8 cases) =="
	exit 0
fi
printf '== %s: FAIL (%s failing case(s)) ==\n' "$NAME" "$FAILS" >&2
exit 1
