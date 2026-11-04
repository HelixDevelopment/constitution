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
#   INTEGRATION-1 (LIVE class) a real end-to-end run against the REAL repo
#                 root (no sandboxing) — the ONLY case that drives the real
#                 `specify` CLI and the real probe, not a mock of either.
#                 Needs a spec-kit-initialised root: when "$ROOT/.specify" is
#                 absent it reports SKIP, reason `topology_unsupported`
#                 (§11.4.3/§11.4.69; a SKIP is never counted as a PASS).
#   GATELOGIC-1F  (UNIT / gate-logic class, §11.4.289) the installer decision
#                 logic run against a spec-kit-shaped consumer FIXTURE built in
#                 mktemp. `specify`/`claude` are PATH STUBS (test doubles), so
#                 this is NOT live integration evidence and never counted as
#                 such: it proves the installer+probe decide correctly given
#                 stub-reported inputs, nothing about the real CLI.
#   GATELOGIC-1M  (stub class) mutation: a fixture with a carrier removed MUST make the
#                 same verdict function FAIL (not skip, not pass).
#   GATELOGIC-2F  (stub class) the idempotent double run against the stub
#                 fixture root; FULL-AUTOMATION-1 (LIVE, real root) SKIPs the
#                 same way as INTEGRATION-1 when no .specify/ exists.
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
#   REL-2         (stub class, N1) relative local SUPERSPEC_FROM=./localsrc reaches the
#                 L3 install as <absolute path>@<pin>, called inside --root.
#   WARN-1        (stub class, N4) a relative --superb-from that does not exist, or an
#                 existing local path shaped like user@host:path, is warned on stderr.
#   PROBE-1       (stub class, F8/N2) L2 names EXACTLY the absolutised SPECIFY_BIN.
#   META-1/META-2 (N3) the reduced fixture-only seam BRIDGE_TEST_LIVE_FIXTURE_ONLY is
#                 honoured only with a parent nonce (run_reduced_child); a leaked
#                 value FAILs loudly (SEAM-GUARD); a reduced child prints
#                 "REDUCED MODE" on stderr and in its verdict line.
#   NET-CLASS     (stub class, N5) a live-fixture build failure is a network-absent
#                 SKIP only with a network-error signature AND a down network probe.
#   NET-LIVE      (LIVE, N5) the real fixture build in a child run inside
#                 `bwrap --unshare-net` (no network, control-checked) must build or
#                 SKIP as network-absent, never report LIVE-FIXTURE-BUILD.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/install_speckit_superpowers_bridge_test.sh [--quiet]
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One PASS/FAIL line per case + a verdict. Exit 0 — every case held. The
#   verdict reports THREE separate tallies: live PASS (real specify/real root),
#   stub-class PASS (unit/gate-logic/chaos with test doubles; never live
#   evidence) and SKIP (honest, not a pass).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   UNIT/CHAOS cases run entirely inside `mktemp -d` sandboxes removed by the
#   EXIT trap (§11.4.14/§11.4.84) — they NEVER touch the real .specify/ tree.
#   INTEGRATION-1 and FULL-AUTOMATION-1 run the REAL installer against the REAL repo
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
# Last verified: 2026-11-04 (N1-N5 review follow-ups; earlier: 2026-11-03 stub-class relabelling per §11.4.289)
set -u

NAME="install_speckit_superpowers_bridge tests"
SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
# ROOT = the consumer project root when this canon is vendored as a submodule (superproject of this checkout),
# else the canon checkout itself. Never a blind 3-levels-up: in standalone canon that is OUTSIDE the repo and the
# real-root cases would write qa-results/ there.
ROOT=$(git -C "$SELF_DIR" rev-parse --show-superproject-working-tree 2>/dev/null)
[ -n "$ROOT" ] || ROOT=$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || ROOT=$(cd "$SELF_DIR/../.." >/dev/null 2>&1 && pwd)
INSTALLER="$SELF_DIR/install_speckit_superpowers_bridge.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

FAILS=0
SKIPS=0
TOTAL_PASS=0      # live-class PASS (real specify / real root)
STUB_PASS=0       # unit / gate-logic / chaos PASS using test doubles: NEVER live integration evidence (§11.4.289)
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { STUB_PASS=$((STUB_PASS + 1)); say "  PASS  [$NAME] (unit/stub-class) $*"; }
okl()  { TOTAL_PASS=$((TOTAL_PASS + 1)); say "  PASS  [$NAME] (LIVE) $* [answered by ${LIVE_ID:-unrecorded}; ambient SPECIFY_BIN/SUPERSPEC_SHA_OVERRIDE/PATH-stubs scrubbed]"; }
skip() { SKIPS=$((SKIPS + 1)); say "  SKIP  [$NAME] $* (not counted as PASS)"; }
bad()  { printf '  FAIL  [%s] %s\n' "$NAME" "$*" >&2; FAILS=$((FAILS + 1)); }

finish() {
	if [ "$FAILS" -eq 0 ]; then
		_mode="full suite"; [ "${REDUCED:-0}" -eq 0 ] || _mode="REDUCED fixture-only mode, NOT the full suite"
		say "== $NAME: PASS (live=$((TOTAL_PASS)) stub-class=$STUB_PASS skipped=$SKIPS [skips are not passes; stub-class is not live evidence]; $_mode) =="
		exit 0
	fi
	printf '== %s: FAIL (%s failing case(s)) ==\n' "$NAME" "$FAILS" >&2
	exit 1
}

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

if [ ! -f "$INSTALLER" ]; then
	bad "installer script missing: $INSTALLER"
	echo "== $NAME: FAIL ==" >&2
	exit 1
fi

TMP=$(mktemp -d) || { bad "mktemp -d failed"; exit 1; }

# ── N3: the reduced fixture-only seam (BRIDGE_TEST_LIVE_FIXTURE_ONLY) is honoured ONLY together with a nonce that a
#    parent run of this suite wrote into its own mktemp dir (BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE, see
#    run_reduced_child). A seam value leaked into the ambient environment (no nonce file, a stale one of a finished
#    parent, or a mismatching value) makes the suite FAIL loudly instead of silently running a shrunken suite that
#    still reports PASS. Residual risk (stated, not closed): a leak WHILE the parent still runs and its nonce file
#    still exists is honoured, and then the child announces REDUCED MODE on stderr and in its verdict line.
REDUCED=0
if [ -n "${BRIDGE_TEST_LIVE_FIXTURE_ONLY:-}" ]; then
	_nf="${BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE:-}"
	if [ "${#BRIDGE_TEST_LIVE_FIXTURE_ONLY}" -ge 32 ] && [ -n "$_nf" ] && [ -f "$_nf" ] \
		&& [ "$(cat -- "$_nf" 2>/dev/null)" = "$BRIDGE_TEST_LIVE_FIXTURE_ONLY" ]; then
		REDUCED=1
		printf '== %s: REDUCED MODE (fixture-only seam authorised by a parent run; only the live-fixture cases run, this is NOT the full suite) ==\n' "$NAME" >&2
	else
		bad "SEAM-GUARD: BRIDGE_TEST_LIVE_FIXTURE_ONLY is set without a valid parent nonce (nonce file '${_nf:-unset}'); refusing to run a silently reduced suite (ambient leak?). Unset BRIDGE_TEST_LIVE_FIXTURE_ONLY and BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE."
		printf '== %s: FAIL (seam guard) ==\n' "$NAME" >&2
		exit 1
	fi
	unset _nf
fi

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

# ── consumer-root fixtures (INTEGRATION-1 / FULL-AUTOMATION-1) ───────────────
# These two cases need a spec-kit-initialised consumer root. Honest handling
# (§11.4.3/§11.4.69, closed reason `topology_unsupported`):
#   * REAL root  : only exercised when "$ROOT/.specify" exists; otherwise SKIP
#     (a SKIP is reported separately, never counted as a PASS).
#   * FIXTURE root: ALWAYS exercised too, against a real spec-kit-shaped tree
#     built in mktemp (the minimal shape the probe reads: the five carriers,
#     `claude` + `specify` on PATH, .specify/, a speckit-* skill, the superspec
#     git submodule + extension.yml + extensions.yml `installed:` entry, and
#     `specify extension list` naming the enabled "Superpowers Bridge"). The
#     `specify`/`claude` binaries are stubs placed first on PATH for the
#     fixture runs only; the installer + probe scripts are the REAL ones.
make_consumer_fixture() {
	# make_consumer_fixture <root>
	local r="$1" src="$1.superspec_src"
	mkdir -p "$r/.specify/extensions/superspec" "$r/.claude/skills/speckit-plan" "$r/fakebin" "$src"
	local f; for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md CRUSH.md; do echo "# $f" > "$r/$f"; done
	printf 'id: superspec\n' > "$r/.specify/extensions/superspec/extension.yml"
	printf 'installed:\n  - superspec\n' > "$r/.specify/extensions.yml"
	printf '# skill\n' > "$r/.claude/skills/speckit-plan/SKILL.md"
	printf '#!/usr/bin/env bash\nexit 0\n' > "$r/fakebin/claude"; chmod +x "$r/fakebin/claude"
	echo '[{"id": "superspec", "name": "Superpowers Bridge", "version": "1.0.2", "enabled": true}]' > "$r/state.json"
	make_fake_specify "$r/fakebin/specify" "$r/state.json"
	( cd "$src" && git init -q -b main && echo x > f && git add f \
		&& git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1
	( cd "$r" && git init -q -b main && mkdir -p submodules \
		&& git -c protocol.file.allow=always submodule add -q "$src" submodules/superspec \
		&& git add -A && git -c user.email=t@t -c user.name=t commit -q -m fixture ) >/dev/null 2>&1
}

run_real_installer() {
	# run_real_installer <root> <out-file> — the REAL installer, REAL probe, no --report-file.
	local root="$1" out="$2" fk
	fk=""; [ -d "$root/fakebin" ] && fk="$root/fakebin:"
	if [ -n "$fk" ]; then
		( cd "$root" && PATH="$fk$PATH" SPECIFY_BIN="$root/fakebin/specify" FAKE_SPECIFY_STATE="$root/state.json" \
			bash "$INSTALLER" --root "$root" --quiet >"$out" 2>&1 )
	else
		# LIVE: never inherit ambient test seams (override binary / sha override / stub state / PATH stubs).
		env -u SPECIFY_BIN -u SUPERSPEC_SHA_OVERRIDE -u FAKE_SPECIFY_STATE PATH="$LIVE_PATH" \
			bash "$INSTALLER" --root "$root" --quiet >"$out" 2>&1
	fi
}

# ── LIVE identity (C1): scrubbed PATH + the resolved specify binary that answers LIVE runs ──
LIVE_PATH=""; _ifs="$IFS"; IFS=:
for _d in $PATH; do
	case "$_d" in "$TMP"*|*fakebin*|*/fake_*|*/stub*) continue ;; esac
	LIVE_PATH="${LIVE_PATH:+$LIVE_PATH:}$_d"
done
IFS="$_ifs"; unset _d _ifs
LIVE_SPECIFY="$(PATH="$LIVE_PATH" command -v specify 2>/dev/null || true)"
LIVE_ID="specify=unresolved"
if [ -n "$LIVE_SPECIFY" ]; then
	LIVE_SPECIFY="$(readlink -f -- "$LIVE_SPECIFY" 2>/dev/null || printf '%s' "$LIVE_SPECIFY")"
	LIVE_ID="specify=$LIVE_SPECIFY sha256=$(sha256sum -- "$LIVE_SPECIFY" 2>/dev/null | cut -d' ' -f1)"
fi

latest_run_dir() { ls -1 "$1/qa-results/hxc159/bridge_install" 2>/dev/null | sort | tail -1; }

integration_verdict() {
	# integration_verdict <root> <out-file> -> PASS|FAIL (SKIP is decided by the caller from topology)
	local root="$1" out="$2" rc d
	run_real_installer "$root" "$out"; rc=$?
	d=$(latest_run_dir "$root")
	if [ "$rc" -eq 0 ] && [ -n "$d" ] && [ -f "$root/qa-results/hxc159/bridge_install/$d/install_report.json" ]; then echo PASS; else echo FAIL; fi
}

full_auto_verdict() {
	# full_auto_verdict <root> <tag> -> PASS|FAIL : two consecutive real runs, identical per-layer status.
	local root="$1" tag="$2" a b rc2 sa sb
	a=$(latest_run_dir "$root")
	sleep 1.1   # run ids are second-resolution timestamps
	run_real_installer "$root" "$TMP/fa_$tag.out"; rc2=$?
	b=$(latest_run_dir "$root")
	if [ "$rc2" -eq 0 ] && [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then
		sa=$(python3 -c "import json; d=json.load(open('$root/qa-results/hxc159/bridge_install/$a/install_report.json')); print(d['L3_status'], d['L4_status'], d['overall_status'])" 2>/dev/null)
		sb=$(python3 -c "import json; d=json.load(open('$root/qa-results/hxc159/bridge_install/$b/install_report.json')); print(d['L3_status'], d['L4_status'], d['overall_status'])" 2>/dev/null)
		if [ -n "$sa" ] && [ "$sa" = "$sb" ]; then echo "PASS:$sa"; else echo "FAIL:'$sa' vs '$sb'"; fi
	else echo "FAIL:rc2=$rc2"; fi
}

# ── INTEGRATION-1 (real root: SKIP when no .specify/) ───────────────────────
REAL_HAS_SPECIFY=0; [ -d "$ROOT/.specify" ] && [ "$REDUCED" -eq 0 ] && REAL_HAS_SPECIFY=1
if [ "$REAL_HAS_SPECIFY" -eq 1 ]; then
	v=$(integration_verdict "$ROOT" "$TMP/integration1.out")
	if [ "$v" = PASS ]; then okl "INTEGRATION-1: real run against the real repo root PASSes, evidence written under $(latest_run_dir "$ROOT")"
	else bad "INTEGRATION-1: real run did not PASS correctly; output:"; sed 's/^/         /' "$TMP/integration1.out" >&2; fi
elif [ "$REDUCED" -eq 1 ]; then
	skip "INTEGRATION-1 (real root): not run in the REDUCED fixture-only mode (only the live-fixture cases run here)"
else
	skip "INTEGRATION-1 (real root): reason=topology_unsupported (no .specify/ under $ROOT)"
fi

# ── LIVE fixture: a REAL spec-kit project made by the REAL `specify init` (offline: templates are bundled in the
#    CLI) + the REAL `specify extension add --dev <local superspec checkout>` (offline) + a real git submodule of that
#    checkout. Nothing here is a stub: the answering binary is LIVE_SPECIFY (recorded in LIVE_ID). When any real
#    prerequisite is absent the LIVE cases SKIP honestly (topology_unsupported), never fall back to a stub.
find_superspec_src() {
	local c
	for c in "${SUPERSPEC_SRC:-}" "$ROOT/submodules/superspec" "$ROOT/constitution/submodules/superspec" "$SELF_DIR/../../submodules/superspec"; do
		[ -n "$c" ] && [ -f "$c/extension.yml" ] && { ( cd "$c" && pwd ); return 0; }
	done
	return 1
}
make_live_fixture() {
	# make_live_fixture <root> <superspec-src> -> 0 only when every real step succeeded
	local r="$1" s="$2" f
	mkdir -p "$r" || return 1
	( cd "$r" && git init -q -b main \
		&& PATH="$LIVE_PATH" timeout 180 specify init . --here --force --non-interactive --integration claude --ignore-agent-tools >"$r.init.out" 2>&1 \
		&& for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md CRUSH.md; do echo "# $f" > "$f"; done \
		&& PATH="$LIVE_PATH" timeout 120 specify extension add --dev "$s" >"$r.ext.out" 2>&1 \
		&& mkdir -p submodules && git -c protocol.file.allow=always submodule add -q "$s" submodules/superspec >/dev/null 2>&1 \
		&& git add -A && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.email=t@t -c user.name=t commit -q -m live-fixture ) >/dev/null 2>&1 || return 1
	[ -d "$r/.specify" ] && [ -f "$r/.specify/extensions/superspec/extension.yml" ] && [ -f "$r/submodules/superspec/extension.yml" ]
}
# N5: classify a failed live-fixture build. Prints "network" ONLY when the build output carries a network-error
# signature AND the independently measured network state ($3) is "down"; otherwise "other" (a FAIL). A signature alone,
# or a down network alone, is a proxy signal and never turns a failure into a SKIP (§11.4.201, §11.4.289(E)).
fixture_failure_class() {
	local init_out="$1" ext_out="$2" net="$3" f
	if [ "$net" = down ]; then
		for f in "$init_out" "$ext_out"; do
			[ -f "$f" ] && grep -qiE 'Temporary failure in name resolution|Name or service not known|nodename nor servname|getaddrinfo failed|Could not resolve host|Network is unreachable|No route to host|ConnectError|ConnectTimeout|Max retries exceeded|Failed to establish a new connection' "$f" && { echo network; return 0; }
		done
	fi
	echo other
}
# N5: measured network state, "down" only when a DNS lookup of a well-known host fails within 10 s.
net_probe_state() { if timeout 10 getent ahosts "${BRIDGE_NET_PROBE_HOST:-github.com}" >/dev/null 2>&1; then echo up; else echo down; fi; }
LIVE_FX_OK=0; LIVE_SKIP_WHY=""; LIVE_FX_BUILD_FAILED=0
SSRC=$(find_superspec_src) || SSRC=""
if [ -z "$LIVE_SPECIFY" ]; then LIVE_SKIP_WHY="missing dependency: no real specify CLI on PATH (no closed-set dependency-absent code exists, so topology_unsupported is used)"
elif [ -z "$SSRC" ]; then LIVE_SKIP_WHY="missing dependency: no local superspec checkout (extension.yml) found; set SUPERSPEC_SRC (no dependency-absent code in the closed set, so topology_unsupported)"
elif make_live_fixture "$TMP/live_fixture" "$SSRC"; then LIVE_FX_OK=1; LIVE_ID="$LIVE_ID superspec_src=$SSRC"
else LIVE_FX_BUILD_FAILED=1; fi

if [ "$LIVE_FX_OK" -eq 1 ]; then
	v=$(integration_verdict "$TMP/live_fixture" "$TMP/integration1l.out")
	if [ "$v" = PASS ]; then okl "INTEGRATION-1L: real installer + real probe + REAL specify against a REAL 'specify init' project (superspec via real 'extension add --dev') PASSes, evidence written"
	else bad "INTEGRATION-1L: live fixture run did not PASS; output:"; sed 's/^/         /' "$TMP/integration1l.out" >&2; fi
	r=$(full_auto_verdict "$TMP/live_fixture" livefx)
	case "$r" in
		PASS:*) okl "FULL-AUTOMATION-1L: two consecutive real runs on the real specify project PASS with identical per-layer status ('${r#PASS:}')" ;;
		*) bad "FULL-AUTOMATION-1L: ${r#FAIL:}" ;;
	esac
	# paired mutation: break the REAL project (drop a carrier -> L1 PARTIAL); the same verdict function MUST FAIL
	rm -f "$TMP/live_fixture/AGENTS.md"
	v=$(integration_verdict "$TMP/live_fixture" "$TMP/integration1lm.out")
	if [ "$v" = FAIL ] && grep -q "L1 (developer workstation)" "$TMP/integration1lm.out"; then
		okl "INTEGRATION-1L-MUT: real specify project with a carrier removed -> verdict FAIL naming L1 (live verdict is falsifiable)"
	else bad "INTEGRATION-1L-MUT: mutated live project did not FAIL as required (verdict=$v)"; fi
elif [ "$LIVE_FX_BUILD_FAILED" -eq 1 ] && [ "$(fixture_failure_class "$TMP/live_fixture.init.out" "$TMP/live_fixture.ext.out" "$(net_probe_state)")" = network ]; then
	skip "INTEGRATION-1L / FULL-AUTOMATION-1L / INTEGRATION-1L-MUT (live specify-init fixture): reason=topology_unsupported (network-absent: the real fixture build failed with a network-error signature and the network probe found no network; §11.4.289(E))"
elif [ "$LIVE_FX_BUILD_FAILED" -eq 1 ]; then
	# Both real prerequisites ARE present, so the topology is supported: a fixture that cannot be built means the real
	# dependency (or the fixture recipe) is broken, which is a finding, never a skip (§11.4.289(J), §11.4.3).
	bad "LIVE-FIXTURE-BUILD: real specify ($LIVE_SPECIFY) and a superspec checkout ($SSRC) are present but the real fixture build (specify init / extension add --dev / submodule add) failed; see $TMP/live_fixture.init.out and $TMP/live_fixture.ext.out"
	for _f in "$TMP/live_fixture.init.out" "$TMP/live_fixture.ext.out"; do [ -f "$_f" ] && sed 's/^/         /' "$_f" >&2; done
else
	skip "INTEGRATION-1L / FULL-AUTOMATION-1L / INTEGRATION-1L-MUT (live specify-init fixture): reason=topology_unsupported ($LIVE_SKIP_WHY)"
fi

# run_reduced_child <home> <out-file> [VAR=value ...] [-- prefix-command ...]
#   Runs THIS suite as a child in the reduced fixture-only mode, authorised by a fresh random nonce written into this
#   run's own mktemp dir (gone when this run exits, so a leaked seam value can never be honoured later; N3).
run_reduced_child() {
	local home="$1" out="$2" nonce nf
	shift 2
	local envs=() pre=()
	while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
	[ "${1:-}" = "--" ] && { shift; pre=("$@"); }
	nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n') || return 1
	[ "${#nonce}" -eq 32 ] || return 1
	nf="$TMP/reduced_nonce.$$.$RANDOM"
	( umask 077; printf '%s' "$nonce" > "$nf" ) || return 1
	"${pre[@]}" env HOME="$home" BRIDGE_TEST_LIVE_FIXTURE_ONLY="$nonce" BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE="$nf" "${envs[@]}" \
		bash "$0" >"$out" 2>&1
}

# ── META-1 (F6 guard): a superspec checkout that exists but cannot be used for the real fixture (no .git) must make the
#    suite FAIL, not SKIP. Runs the suite in the fixture-only mode against such a source (needs the real specify).
if [ "$REDUCED" -eq 0 ] && [ -n "$LIVE_SPECIFY" ]; then
	mkdir -p "$TMP/badsrc" && echo "id: badsrc" > "$TMP/badsrc/extension.yml"
	run_reduced_child "$TMP/meta_home" "$TMP/meta1.out" SUPERSPEC_SRC="$TMP/badsrc"; rc=$?
	if [ "$rc" -ne 0 ] && grep -q "LIVE-FIXTURE-BUILD" "$TMP/meta1.out" && grep -q "REDUCED MODE" "$TMP/meta1.out"; then
		ok "META-1: real specify + an unusable superspec checkout -> the suite FAILs (LIVE-FIXTURE-BUILD), it does not SKIP, and the child announced REDUCED MODE (rc=$rc)"
	else
		bad "META-1: an unusable superspec checkout did not fail the suite with a REDUCED MODE banner (rc=$rc); output:"; sed 's/^/         /' "$TMP/meta1.out" >&2
	fi
fi

# ── META-2 (N3): a seam value leaked into the ambient environment (no nonce, a stale nonce file of a finished parent,
#    or a wrong value) MUST make the suite FAIL loudly; before N3 it silently shrank to a few cases and exited 0.
if [ "$REDUCED" -eq 0 ]; then
	_m2fail=""
	env HOME="$TMP/meta2_home" BRIDGE_TEST_LIVE_FIXTURE_ONLY=1 bash "$0" --quiet >"$TMP/meta2a.out" 2>&1; rc=$?
	{ [ "$rc" -ne 0 ] && grep -q "SEAM-GUARD" "$TMP/meta2a.out"; } || _m2fail="$_m2fail no-nonce(rc=$rc)"
	_stale="0123456789abcdef0123456789abcdef"
	env HOME="$TMP/meta2_home" BRIDGE_TEST_LIVE_FIXTURE_ONLY="$_stale" BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE="$TMP/gone/nonce" bash "$0" --quiet >"$TMP/meta2b.out" 2>&1; rc=$?
	{ [ "$rc" -ne 0 ] && grep -q "SEAM-GUARD" "$TMP/meta2b.out"; } || _m2fail="$_m2fail stale-nonce-file(rc=$rc)"
	printf '%s' "fedcba9876543210fedcba9876543210" > "$TMP/meta2_nonce"
	env HOME="$TMP/meta2_home" BRIDGE_TEST_LIVE_FIXTURE_ONLY="$_stale" BRIDGE_TEST_LIVE_FIXTURE_NONCE_FILE="$TMP/meta2_nonce" bash "$0" --quiet >"$TMP/meta2c.out" 2>&1; rc=$?
	{ [ "$rc" -ne 0 ] && grep -q "SEAM-GUARD" "$TMP/meta2c.out"; } || _m2fail="$_m2fail wrong-value(rc=$rc)"
	if [ -z "$_m2fail" ]; then
		ok "META-2: a leaked BRIDGE_TEST_LIVE_FIXTURE_ONLY (no nonce / stale nonce file / wrong value) makes the suite FAIL loudly (SEAM-GUARD), never a silent reduced PASS"
	else
		bad "META-2: a leaked seam did not fail loudly:$_m2fail; outputs:"; sed 's/^/         /' "$TMP/meta2a.out" "$TMP/meta2b.out" "$TMP/meta2c.out" >&2
	fi
	unset _m2fail _stale
fi

# ── NET-CLASS (N5, gate-logic / stub-class): the LIVE-FIXTURE-BUILD failure classifier. A build failure is a
#    network-absent SKIP (§11.4.289(E)) ONLY when BOTH the build output carries a network-error signature AND an
#    independent probe found the network down; any other combination is a FAIL (a finding, §11.4.201: no proxy signal).
if [ "$REDUCED" -eq 0 ]; then
	NC="$TMP/netclass"; mkdir -p "$NC"
	printf 'Error: httpx.ConnectError: [Errno -3] Temporary failure in name resolution\n' > "$NC/net.out"
	printf 'Error: template directory not found\n' > "$NC/other.out"
	: > "$NC/empty.out"
	_ncfail=""
	[ "$(fixture_failure_class "$NC/net.out" "$NC/empty.out" down)" = network ] || _ncfail="$_ncfail sig+down!=network"
	[ "$(fixture_failure_class "$NC/empty.out" "$NC/net.out" down)" = network ] || _ncfail="$_ncfail ext-sig+down!=network"
	[ "$(fixture_failure_class "$NC/net.out" "$NC/empty.out" up)" = other ] || _ncfail="$_ncfail sig+up!=other"
	[ "$(fixture_failure_class "$NC/other.out" "$NC/empty.out" down)" = other ] || _ncfail="$_ncfail nosig+down!=other"
	[ "$(fixture_failure_class "$NC/missing.out" "$NC/also_missing.out" down)" = other ] || _ncfail="$_ncfail no-output+down!=other"
	if [ -z "$_ncfail" ]; then
		ok "NET-CLASS: fixture-build failure is classified network-absent only with a network signature AND a down network probe; every other case is a FAIL"
	else
		bad "NET-CLASS: classifier wrong:$_ncfail"
	fi
	unset _ncfail
fi

# ── NET-LIVE (N5, LIVE): the REAL fixture build (real specify init + real extension add --dev + real submodule add)
#    run in a child suite inside a network namespace with NO network (bwrap --unshare-net). Measures, rather than
#    assumes, whether a network-absent host can build the live fixture: the child MUST NOT report LIVE-FIXTURE-BUILD;
#    it either builds and PASSes the live cases, or SKIPs them as network-absent.
if [ "$REDUCED" -eq 0 ]; then
	if [ -z "$LIVE_SPECIFY" ] || [ -z "$SSRC" ]; then
		skip "NET-LIVE: reason=topology_unsupported (needs the real specify and a superspec checkout: ${LIVE_SKIP_WHY:-fixture prerequisites absent})"
	elif ! command -v bwrap >/dev/null 2>&1 || ! bwrap --dev-bind / / --unshare-net true >/dev/null 2>&1; then
		skip "NET-LIVE: reason=topology_unsupported (no usable bwrap --unshare-net on this host to remove the network)"
	elif [ "$(bwrap --dev-bind / / --unshare-net bash -c "$(declare -f net_probe_state); net_probe_state")" != down ]; then
		bad "NET-LIVE: control failed: inside bwrap --unshare-net the network probe did NOT report down, so the namespace cannot be trusted to remove the network"
	else
		run_reduced_child "$TMP/netlive_home" "$TMP/netlive.out" SUPERSPEC_SRC="$SSRC" -- bwrap --dev-bind / / --unshare-net; rc=$?
		if [ "$rc" -eq 0 ] && ! grep -q "LIVE-FIXTURE-BUILD" "$TMP/netlive.out" \
			&& { grep -q "PASS .*INTEGRATION-1L:" "$TMP/netlive.out" || grep -q "network-absent" "$TMP/netlive.out"; }; then
			if grep -q "PASS .*INTEGRATION-1L:" "$TMP/netlive.out"; then
				okl "NET-LIVE: with NO network (bwrap --unshare-net; probe inside=down, outside=$(net_probe_state)) the real specify init + extension add --dev fixture still BUILDS and the live cases PASS (so a fixture-build failure is never a network-absent case for this specify)"
			else
				okl "NET-LIVE: with NO network the real fixture build failed with a network signature and the child SKIPped it as network-absent (not a LIVE-FIXTURE-BUILD FAIL)"
			fi
		else
			bad "NET-LIVE: network-isolated child did not build-or-skip cleanly (rc=$rc); output:"; sed 's/^/         /' "$TMP/netlive.out" >&2
		fi
	fi
fi
[ "$REDUCED" -eq 0 ] || finish

# ── CWD-1 (stub-class) — L4 path run from a FOREIGN cwd: specify reads the project from its cwd, so every
#    specify call must run IN --root. The fake specify below FAILS ("Not a Spec Kit project") outside a .specify dir
#    (like the real CLI) and logs the cwd of each call. The registered superb dir MUST survive (no rm -rf on a failed
#    or mis-rooted probe) and every call must have run inside the root.
CW="$TMP/cwd1"; mkdir -p "$CW/.specify/extensions/superb" "$CW/foreign" "$CW/qa-results"
cat > "$CW/specify" <<'FEOF'
#!/usr/bin/env bash
[ -d .specify ] || { echo '{"error": "Not a Spec Kit project (no .specify/ directory)"}'; echo "FOREIGN $*" >> "${CWD_LOG:?}"; exit 1; }
echo "ROOTED $*" >> "${CWD_LOG:?}"
case "$1 $2" in
	"extension list") echo '[{"id": "superb", "name": "SuperB", "version": "1.9.0", "enabled": true}]' ;;
	"extension add") echo ok ;;
esac
exit 0
FEOF
chmod +x "$CW/specify"; make_report "$CW/report.json" WIRED WIRED WIRED DESIGNED-ONLY
( cd "$CW/foreign" && SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81" SPECIFY_BIN="$CW/specify" CWD_LOG="$CW/calls.log" \
	bash "$INSTALLER" --root "$CW" --report-file "$CW/report.json" --quiet \
	--superb-from "https://example.invalid/releases/download/v1.9.0/superpowers-bridge.zip" \
	--superb-vetted-by "operator:test-harness — cwd case" >"$CW/run.out" 2>&1 ); rc=$?
if [ -d "$CW/.specify/extensions/superb" ] && ! grep -q '^FOREIGN' "$CW/calls.log" 2>/dev/null && grep -q '^ROOTED extension add superb' "$CW/calls.log" 2>/dev/null; then
	ok "CWD-1: L4 run from a foreign cwd — every specify call ran inside --root, registered superb dir NOT deleted (rc=$rc)"
else
	bad "CWD-1: foreign-cwd L4 run mis-rooted a specify call or deleted registered data (rc=$rc; calls: $(tr '\n' ';' < "$CW/calls.log" 2>/dev/null); superb_dir_present=$([ -d "$CW/.specify/extensions/superb" ] && echo 1 || echo 0))"
fi

# ── CWD-2 (stub-class) — a FAILED probe must never fall through to rm -rf: specify always errors -> dir kept
CX="$TMP/cwd2"; mkdir -p "$CX/.specify/extensions/superb" "$CX/qa-results"
printf '#!/usr/bin/env bash\nexit 1\n' > "$CX/specify"; chmod +x "$CX/specify"; make_report "$CX/report.json" WIRED WIRED WIRED DESIGNED-ONLY
( cd "$CX" && SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81" SPECIFY_BIN="$CX/specify" bash "$INSTALLER" --root "$CX" --report-file "$CX/report.json" --quiet \
	--superb-from "https://example.invalid/releases/download/v1.9.0/superpowers-bridge.zip" --superb-vetted-by "operator:test-harness — failed-probe case" >"$CX/run.out" 2>&1 )
if [ -d "$CX/.specify/extensions/superb" ]; then ok "CWD-2: failed registration probe did NOT trigger rm -rf of .specify/extensions/superb"
else bad "CWD-2: a failed probe fell through to rm -rf of the superb dir"; fi

# ── CWD-3 (F2) — a probe that FAILS (rc 1) but still prints a parseable "[]": the stale dir must NOT be deleted
C3="$TMP/cwd3"; mkdir -p "$C3/.specify/extensions/superb" "$C3/qa-results"
printf '#!/usr/bin/env bash\nif [ "$1 $2" = "extension list" ]; then echo "[]"; exit 1; fi\nexit 0\n' > "$C3/specify"; chmod +x "$C3/specify"; make_report "$C3/report.json" WIRED WIRED WIRED DESIGNED-ONLY
( cd "$C3" && SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81" SPECIFY_BIN="$C3/specify" bash "$INSTALLER" --root "$C3" --report-file "$C3/report.json" --quiet \
	--superb-from "https://example.invalid/releases/download/v1.9.0/superpowers-bridge.zip" --superb-vetted-by "operator:test-harness — rc1-with-empty-list case" >"$C3/run.out" 2>&1 )
if [ -d "$C3/.specify/extensions/superb" ]; then ok "CWD-3: probe rc=1 printing a parseable '[]' did NOT trigger rm -rf of .specify/extensions/superb"
else bad "CWD-3: a failing probe that still printed '[]' fell through to rm -rf of the superb dir"; fi

# ── REL-1 (F3/F4/F5) — relative SPECIFY_BIN, relative --report-file and a relative LOCAL --superb-from, all given
#    relative to the CALLER's cwd (not --root): the installer must resolve them before it cds into --root.
RL="$TMP/rel1"; mkdir -p "$RL/root/.specify" "$RL/caller/pkg" "$RL/root/qa-results"
cat > "$RL/caller/specify" <<'FEOF'
#!/usr/bin/env bash
echo "CALL cwd=$(pwd) args=$*" >> "${REL_LOG:?}"
if [ "$1 $2" = "extension list" ]; then echo '[{"id": "superb", "name": "SuperB", "version": "1.9.0", "enabled": true}]'; fi
exit 0
FEOF
chmod +x "$RL/caller/specify"; : > "$RL/caller/pkg/superb.zip"; make_report "$RL/caller/report.json" WIRED WIRED WIRED DESIGNED-ONLY
( cd "$RL/caller" && SUPERSPEC_SHA_OVERRIDE="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81" SPECIFY_BIN="./specify" REL_LOG="$RL/calls.log" \
	bash "$INSTALLER" --root "$RL/root" --report-file report.json --quiet --superb-from pkg/superb.zip --superb-vetted-by "operator:test-harness — relative-input case" >"$RL/run.out" 2>&1 ); rc=$?
RL_RC=$rc
if [ "$RL_RC" -eq 0 ] && grep -q "cwd=$RL/root args=extension add superb --from $RL/caller/pkg/superb.zip" "$RL/calls.log" 2>/dev/null; then
	ok "REL-1: relative SPECIFY_BIN + relative --report-file + relative local --superb-from were resolved against the caller's cwd; every specify call ran in --root with the absolute archive path (rc=$RL_RC)"
else
	bad "REL-1: relative inputs mishandled (rc=$RL_RC; calls: $(tr '\n' ';' < "$RL/calls.log" 2>/dev/null)); output:"; sed 's/^/         /' "$RL/run.out" >&2
fi

# ── REL-2 (N1) — a relative LOCAL SUPERSPEC_FROM (./localsrc, relative to the CALLER's cwd) on the L3 install path:
#    specify must be called in --root with the ABSOLUTE source path plus @<pin>.
R2="$TMP/rel2"; mkdir -p "$R2/root/.specify" "$R2/caller/localsrc" "$R2/root/qa-results"
cp "$RL/caller/specify" "$R2/caller/specify"
R2PIN="c20ac6c1ba069cc9a72dacb8044b7b193d3dde81"
make_report "$R2/caller/report.json" WIRED WIRED DESIGNED-ONLY DESIGNED-ONLY
( cd "$R2/caller" && SUPERSPEC_PIN="$R2PIN" SUPERSPEC_FROM="./localsrc" SPECIFY_BIN="$R2/caller/specify" REL_LOG="$R2/calls.log" \
	bash "$INSTALLER" --root "$R2/root" --report-file report.json --quiet >"$R2/run.out" 2>&1 ); R2_RC=$?
if [ "$R2_RC" -eq 0 ] && grep -qxF "CALL cwd=$R2/root args=extension add superspec --from $R2/caller/localsrc@$R2PIN" "$R2/calls.log" 2>/dev/null; then
	ok "REL-2: relative local SUPERSPEC_FROM=./localsrc reached the L3 install as the absolute path @pin, called inside --root (rc=$R2_RC)"
else
	bad "REL-2: relative SUPERSPEC_FROM mishandled on the L3 install path (rc=$R2_RC; calls: $(tr '\n' ';' < "$R2/calls.log" 2>/dev/null)); output:"; sed 's/^/         /' "$R2/run.out" >&2
fi

# ── WARN-1 (N4) — abs_local_source must WARN (stderr) when it leaves a relative value unresolved: a relative path that
#    does not exist, and an existing local path shaped like scp-style user@host:path. Golden-FALSE: an existing relative
#    path and a URL produce no such warning.
W1="$TMP/warn1"; mkdir -p "$W1/root/.specify" "$W1/caller/pkg" "$W1/caller/u@h:p" "$W1/root/qa-results"
cp "$RL/caller/specify" "$W1/caller/specify"; : > "$W1/caller/pkg/superb.zip"
make_report "$W1/caller/report.json" WIRED WIRED WIRED DESIGNED-ONLY
w1run() { ( cd "$W1/caller" && SUPERSPEC_SHA_OVERRIDE="$R2PIN" SPECIFY_BIN="$W1/caller/specify" REL_LOG="$W1/calls.log" \
	bash "$INSTALLER" --root "$W1/root" --report-file report.json --quiet --dry-run --superb-from "$1" --superb-vetted-by "operator:test-harness — warn case" >"$W1/$2.out" 2>&1 ); }
_w1fail=""
w1run "nothere/superb.zip" missing; grep -q "abs_local_source: WARNING.*nothere/superb.zip.*does not exist" "$W1/missing.out" || _w1fail="$_w1fail missing-relative-not-warned"
w1run "u@h:p" scp; grep -q "abs_local_source: WARNING.*u@h:p.*scp-style" "$W1/scp.out" || _w1fail="$_w1fail existing-scp-shaped-not-warned"
w1run "pkg/superb.zip" exists; ! grep -q "abs_local_source: WARNING" "$W1/exists.out" || _w1fail="$_w1fail existing-relative-falsely-warned"
w1run "https://example.invalid/superb.zip" url; ! grep -q "abs_local_source: WARNING" "$W1/url.out" || _w1fail="$_w1fail url-falsely-warned"
if [ -z "$_w1fail" ]; then
	ok "WARN-1: unresolved relative --superb-from values (missing path, existing scp-shaped path) are warned on stderr; an existing relative path and a URL are not"
else
	bad "WARN-1:$_w1fail; outputs:"; sed 's/^/         /' "$W1"/*.out >&2
fi
unset _w1fail

# ── PROBE-1 (F8) — probe_bridge_layers.sh must honour SPECIFY_BIN (incl. a relative one) for every specify call
PB="$TMP/probe1"; mkdir -p "$PB/root/.specify" "$PB/caller"
cat > "$PB/caller/specify" <<'FEOF'
#!/usr/bin/env bash
echo "PROBE_FAKE_SPECIFY $*"
exit 0
FEOF
chmod +x "$PB/caller/specify"
( cd "$PB/caller" && SPECIFY_BIN="./specify" bash "$SELF_DIR/probe_bridge_layers.sh" --root "$PB/root" --quiet >"$PB/run.out" 2>&1 )
PBRAW=$(ls -d "$PB"/root/qa-results/hxc159/bridge_layers/*/raw 2>/dev/null | tail -1)
if [ -n "$PBRAW" ] && grep -q "PROBE_FAKE_SPECIFY extension list" "$PBRAW/L3_extension_list.out" 2>/dev/null \
	&& grep -q "PROBE_FAKE_SPECIFY extension search superb" "$PBRAW/L4_catalog_search.out" 2>/dev/null \
	&& [ "$(cat "$PBRAW/L2_specify_cli.out" 2>/dev/null)" = "$PB/caller/specify" ]; then
	# N2: L2 must name EXACTLY the absolutised SPECIFY_BIN; a bare `command -v specify` would pass a looser check on
	# any host that has some specify on PATH.
	ok "PROBE-1: probe_bridge_layers.sh used SPECIFY_BIN for L2 cli presence (exactly $PB/caller/specify), L3 extension list and L4 catalog search"
else
	bad "PROBE-1: the probe ignored SPECIFY_BIN (raw dir: ${PBRAW:-none}); output:"; sed 's/^/         /' "$PB/run.out" >&2
fi

# ── GATELOGIC-1F — gate-logic (stub-class) against a spec-kit-shaped fixture root; NOT live evidence ─
CF="$TMP/consumer_fixture"; mkdir -p "$CF"
make_consumer_fixture "$CF"
v=$(integration_verdict "$CF" "$TMP/integration1f.out")
if [ "$v" = PASS ]; then
	ok "GATELOGIC-1F: real installer + real probe, STUB specify/claude, against a spec-kit-shaped fixture consumer root PASSes, evidence written"
else
	bad "GATELOGIC-1F: fixture consumer run did not PASS; output:"; sed 's/^/         /' "$TMP/integration1f.out" >&2
fi

# ── GATELOGIC-1M — mutation: break the fixture (drop a carrier -> L1 PARTIAL);
#    the same verdict function MUST report FAIL (and not SKIP) ──────────────────
CM="$TMP/consumer_fixture_mut"; mkdir -p "$CM"
make_consumer_fixture "$CM"
rm -f "$CM/AGENTS.md"
v=$(integration_verdict "$CM" "$TMP/integration1m.out")
if [ "$v" = FAIL ] && grep -q "L1 (developer workstation)" "$TMP/integration1m.out"; then
	ok "GATELOGIC-1M: mutated fixture (carrier removed) → verdict FAIL (not skipped), naming L1"
else
	bad "GATELOGIC-1M: mutated fixture did not FAIL as required (verdict=$v)"
fi

# ── FULL-AUTOMATION-1 (real root: SKIP when no .specify/) ───────────────────
if [ "$REAL_HAS_SPECIFY" -eq 1 ]; then
	r=$(full_auto_verdict "$ROOT" real)
	case "$r" in
		PASS:*) okl "FULL-AUTOMATION-1: two consecutive fully-autonomous real runs both PASS with identical per-layer status ('${r#PASS:}') — idempotent re-run proven" ;;
		*) bad "FULL-AUTOMATION-1: ${r#FAIL:}" ;;
	esac
else
	skip "FULL-AUTOMATION-1 (real root): reason=topology_unsupported (no .specify/ under $ROOT)"
fi

# ── GATELOGIC-2F — idempotent double run against the fixture root ──────
r=$(full_auto_verdict "$CF" fixture)
case "$r" in
	PASS:*) ok "GATELOGIC-2F: two consecutive autonomous runs on the fixture consumer both PASS with identical per-layer status ('${r#PASS:}')" ;;
	*) bad "GATELOGIC-2F: ${r#FAIL:}" ;;
esac

# ── CHAOS-1 — interrupted operator-vetted L4 install, then clean re-run ────
SC="$TMP/chaos1"; mkdir -p "$SC"
make_report "$SC/report.json" "WIRED" "WIRED" "WIRED" "DESIGNED-ONLY"
FAKE_SPEC_C="$SC/fake_specify.sh"
make_fake_specify "$FAKE_SPEC_C" "$SC/state.json"
mkdir -p "$SC/.specify"
echo "[]" > "$SC/state.json"
mkdir -p "$SC/qa-results" "$SC/.specify/extensions/superspec"
echo keep > "$SC/.specify/extensions/superspec/keep.txt"   # F1: a registered sibling extension must survive the stale-superb cleanup

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

SIBLING_KEPT=0
[ -f "$SC/.specify/extensions/superspec/keep.txt" ] && SIBLING_KEPT=1
if [ "$SIBLING_KEPT" -ne 1 ]; then
	bad "CHAOS-1 scope: the stale-superb cleanup deleted a sibling extension directory (.specify/extensions/superspec)"
else
	ok "CHAOS-1 scope: the stale-superb cleanup left the sibling extension directory (.specify/extensions/superspec) intact"
fi
if [ "$rc" -eq 0 ] && [ "$REGISTERED_AFTER_RECOVERY" -eq 1 ] && [ "$STALE_MARKER_GONE" -eq 1 ]; then
	ok "CHAOS-1 recovery: re-run after a SIGKILL-interrupted install cleans stale state and completes successfully (rc=$rc, superb registered, no stale in-progress marker)"
else
	bad "CHAOS-1 recovery: re-run after interruption did NOT cleanly recover (rc=$rc registered=$REGISTERED_AFTER_RECOVERY marker_gone=$STALE_MARKER_GONE); output:"
	sed 's/^/         /' "$SC/recovery_run.out" >&2
fi

# ── ROOT-1 — the resolved ROOT must contain this script (no write outside the repo) ──
# ROOT must be a git work tree root (own .git) that contains this script: a bare ancestor directory
# (e.g. the Projects dir above a standalone canon) contains the script too but is OUTSIDE any repo.
case "$SELF_DIR/" in
	"$ROOT"/*) if [ -e "$ROOT/.git" ]; then ok "ROOT-1: resolved ROOT ($ROOT) is a repo root containing this script; real-root evidence is written inside the repo only"
		else bad "ROOT-1: ROOT ($ROOT) is not a git work tree root — real-root cases would write outside any repo"; fi ;;
	*) bad "ROOT-1: ROOT ($ROOT) does not contain $SELF_DIR — real-root cases would write outside the repo" ;;
esac

# ── verdict ──────────────────────────────────────────────────────────────────
finish
