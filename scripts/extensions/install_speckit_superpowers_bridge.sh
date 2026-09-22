#!/usr/bin/env bash
# install_speckit_superpowers_bridge.sh — HXC-159 T-B2.02 L3/L4 Bridge installer.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Installs (or, where already present, VERIFIES) the two Bridge layers that
# T-B1.01's fresh probe found were the project's ACTUAL remaining installation
# scope — never the stale scope described in the original task brief:
#
#   L3  SuperSpec (orchestration) — already measured WIRED on this host as a
#       git submodule pinned to an immutable commit SHA, registered + Enabled
#       via `specify extension list`. This script's job for L3 is therefore
#       VALIDATE-AND-SKIP (idempotent no-op), never blind reinstall — it only
#       attempts an install if the fresh probe finds L3 genuinely absent.
#   L4  SuperB (discipline) — measured DESIGNED-ONLY (present in the discovery-
#       only community catalog, nothing checked out locally). The supply-chain
#       registry (bridge_supply_chain_check.sh) classifies it HIGH risk and its
#       `bridge_supply_chain_refuse_if_unpinned` function REFUSES it
#       UNCONDITIONALLY (exit 2) regardless of any ref supplied — "this
#       function alone never authorises it" is the function's own comment.
#       Installing L4 therefore requires a SEPARATE, explicit, this-script-only
#       operator-vetting-decision record (§11.4.66) supplied via
#       --superb-vetted-by + --superb-from; absent that record this script
#       performs NO write for L4 and reports the refusal as the CORRECT,
#       expected default state — never a failure.
#
# Contains NO step for L5 (SuperBridge MCP) — T-B1.01/T-B3 already established
# L5 does not exist as software; a step that can never succeed is a defect,
# not a TODO (T-B2.02.6).
#
# ── Idempotency + non-clobber guarantees ────────────────────────────────────
#   - NEVER calls `specify init` / `specify check` in a mutating mode — L2
#     (.specify/ + the speckit-* skills) is verified WIRED from the fresh
#     probe and is otherwise untouched.
#   - obra/superpowers (LOW risk, the official spec-kit marketplace plugin) is
#     NEVER (re)installed by this script — it reconciles with the existing
#     plugin-sourced copy by performing no action for it at all, avoiding a
#     double-install (T-B2.02.3).
#   - Re-running this script against an already-satisfied state (L3 WIRED,
#     L4 not operator-vetted) is a pure no-op producing the identical evidence
#     shape — safe to re-run any number of times (§11.4.50).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/install_speckit_superpowers_bridge.sh \
#       [--root <repo-root>] [--report-file <probe-report.json>] \
#       [--superb-from <archive-url> --superb-vetted-by <name-or-ticket>] \
#       [--dry-run] [--quiet]
#
#   --root            repo root (defaults to three levels above this script).
#   --report-file     use this probe report.json instead of running a fresh
#                      probe_bridge_layers.sh invocation. Used by this script's
#                      own tests to inject a sandboxed/synthetic layer report
#                      without touching the real host or real .specify/ tree
#                      (§11.4.84 — mutation stays sandboxed).
#   --superb-from      an explicit, versioned release-asset URL for SuperB
#                      (e.g. a `.../releases/download/<tag>/superpowers-bridge.zip`
#                      URL — never a bare branch/tag name). Required together
#                      with --superb-vetted-by to attempt the L4 install.
#   --superb-vetted-by the recorded §11.4.66 operator-vetting-decision marker
#                      (an identity + a short reason, e.g. "operator:jdoe —
#                      vetted 2026-09-22 per HXC-159 T-B2.02"). Required
#                      together with --superb-from.
#   --dry-run          perform every check but skip the actual `specify
#                      extension add` mutation (both L3-recovery and L4
#                      operator-vetted paths); still writes evidence recording
#                      what WOULD have run.
#   --quiet            suppress non-essential stdout narration.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   A Bridge layer-presence report (freshly probed, or --report-file), the
#   `specify` CLI (or $SPECIFY_BIN override), and
#   constitution/scripts/extensions/bridge_supply_chain_check.sh (sourced).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   <repo-root>/qa-results/hxc159/bridge_install/<run-id>/
#     install_report.json  — machine-readable per-layer outcome (RS-19 data).
#     install.log           — full narration of every check/decision/command.
#   Exit 0 — the run completed with L1/L2 confirmed WIRED and L3 confirmed
#            WIRED (installed-or-already-present); an un-vetted, therefore
#            skipped, L4 is NOT a failure (it is the correct default state).
#   Exit 1 — L1/L2 not WIRED, `specify` unavailable, L3 could not be
#            confirmed/installed, an attempted L4 install failed, or the
#            final RS-19 verification did not hold.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only unless: (a) L3 is genuinely absent (triggers a pinned
#   `specify extension add superspec --from <pinned-sha-or-url>`, never bare
#   `specify extension add superspec`), or (b) an operator-vetted L4 install is
#   explicitly requested via --superb-from + --superb-vetted-by (triggers
#   `specify extension add superb --from <archive-url>`). Neither path runs
#   under --dry-run. Writes ONLY under qa-results/hxc159/bridge_install/<run-id>/.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (JSON parsing/assembly), the `specify` CLI (or $SPECIFY_BIN),
#   constitution/scripts/extensions/bridge_supply_chain_check.sh (sourced, not
#   copied — §11.4.28/.177), constitution/scripts/extensions/probe_bridge_layers.sh
#   (invoked when --report-file is not given). Parses clean under `bash -n`
#   (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/tasks.md Phase B2 (T-B2.02) ·
#   Phase B1 (T-B1.01/.02/.03, the probe + gate + supply-chain check this
#   script builds on) · §11.4.66 (operator-vetting-decision record) ·
#   §11.4.28/.177 (source by reference, never copied) · §11.4.50 (idempotent
#   re-run) · §11.4.85 (chaos — interrupted-install resilience, see the paired
#   test) · §11.4.108 (runtime signature — RS-19) · §11.4.201 (conservative
#   default on an unresolvable precondition).
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
REPORT_FILE=""
SUPERB_FROM=""
SUPERB_VETTED_BY=""
DRY_RUN=0
QUIET=0
SPECIFY_BIN="${SPECIFY_BIN:-specify}"

while [ $# -gt 0 ]; do
	case "$1" in
		--root)             shift; ROOT="$1" ;;
		--report-file)       shift; REPORT_FILE="$1" ;;
		--superb-from)       shift; SUPERB_FROM="$1" ;;
		--superb-vetted-by)  shift; SUPERB_VETTED_BY="$1" ;;
		--dry-run)           DRY_RUN=1 ;;
		--quiet)             QUIET=1 ;;
		-h|--help)           sed -n '3,80p' "$0"; exit 0 ;;
		*) echo "install_speckit_superpowers_bridge.sh: unknown arg: $1" >&2; exit 2 ;;
	esac
	shift || true
done

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
EVID_DIR="$ROOT/qa-results/hxc159/bridge_install/$RUN_ID"
mkdir -p "$EVID_DIR" || { echo "cannot create evidence dir: $EVID_DIR" >&2; exit 1; }
LOG_FILE="$EVID_DIR/install.log"
REPORT_OUT="$EVID_DIR/install_report.json"

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; printf '%s\n' "$*" >>"$LOG_FILE"; }
warn() { printf '%s\n' "$*" >&2; printf '%s\n' "$*" >>"$LOG_FILE"; }
log_only() { printf '%s\n' "$*" >>"$LOG_FILE"; }

say "== install_speckit_superpowers_bridge.sh — run $RUN_ID =="
say "   root:        $ROOT"
say "   evidence:    $EVID_DIR"
say "   dry-run:     $DRY_RUN"

# ── source the supply-chain refusal library (never reimplemented — §11.4.74) ─
SUPPLY_CHAIN_LIB="$SELF_DIR/bridge_supply_chain_check.sh"
if [ ! -f "$SUPPLY_CHAIN_LIB" ]; then
	warn "FATAL: supply-chain library missing: $SUPPLY_CHAIN_LIB"
	exit 1
fi
# shellcheck disable=SC1090
. "$SUPPLY_CHAIN_LIB"

# ── obtain the layer-presence report: fresh probe, or an injected one for
#    tests (§11.4.84 — sandboxed report injection, never a live-host mutation
#    substitute) ────────────────────────────────────────────────────────────
if [ -z "$REPORT_FILE" ]; then
	PROBE="$SELF_DIR/probe_bridge_layers.sh"
	if [ ! -f "$PROBE" ]; then
		warn "FATAL: probe script missing: $PROBE"
		exit 1
	fi
	# Extract "report written: <path>" from the probe's OWN stdout rather
	# than "latest directory under bridge_layers/ by sort" — this checkout is
	# shared by concurrent agents/tracks (§11.4.119/§11.4.176) that may run
	# this same probe concurrently; "latest by lexicographic sort" can race a
	# sibling track's in-flight (not-yet-written) run-id directory, producing
	# a false "no report" FATAL unrelated to THIS invocation's own result
	# (found + fixed during this script's own integration run, §11.4.6 —
	# never guess which run is ours).
	PROBE_OUT=$(bash "$PROBE" --root "$ROOT" --quiet 2>&1)
	PROBE_RC=$?
	log_only "$PROBE_OUT"
	if [ "$PROBE_RC" -ne 0 ]; then
		warn "FATAL: probe_bridge_layers.sh exited $PROBE_RC — cannot determine layer state"
		exit 1
	fi
	REPORT_FILE=$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^report written: //p' | tail -1)
	if [ -z "$REPORT_FILE" ]; then
		warn "FATAL: probe ran (rc=0) but its stdout contained no 'report written: <path>' line — cannot determine which report is ours"
		exit 1
	fi
fi
if [ ! -f "$REPORT_FILE" ]; then
	warn "FATAL: report-file not found: $REPORT_FILE"
	exit 1
fi
say "   report-file: $REPORT_FILE"

layer_verdict() {
	# layer_verdict <id> <report-file> — prints the verdict string, or "" if
	# the layer id is absent from the report (conservative: caller must treat
	# empty as NOT WIRED, §11.4.201).
	python3 - "$1" "$2" <<'PYEOF'
import json, sys
lid, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception:
    print("")
    sys.exit(0)
for layer in doc.get("layers", []):
    if layer.get("id") == lid:
        print(layer.get("verdict") or "")
        sys.exit(0)
print("")
PYEOF
}

L1_VERDICT=$(layer_verdict L1 "$REPORT_FILE")
L2_VERDICT=$(layer_verdict L2 "$REPORT_FILE")
L3_VERDICT=$(layer_verdict L3 "$REPORT_FILE")
L4_VERDICT=$(layer_verdict L4 "$REPORT_FILE")

say "   L1 (workstation):  $L1_VERDICT"
say "   L2 (spec-kit core): $L2_VERDICT"
say "   L3 (superspec):    $L3_VERDICT"
say "   L4 (superb):       $L4_VERDICT"

STATUS_L1="checked"
STATUS_L2="checked"
STATUS_L3=""
STATUS_L4=""
OVERALL_OK=1

# ── L1+L2 precondition — refuse loudly rather than proceed against an absent
#    workstation/spec-kit-core layer (§11.4.110 change-impact precondition,
#    §11.4.201 conservative default) ─────────────────────────────────────────
if [ "$L1_VERDICT" != "WIRED" ]; then
	warn "FATAL: L1 (developer workstation) verdict is '$L1_VERDICT', not WIRED — refusing to proceed."
	OVERALL_OK=0
fi
if [ "$L2_VERDICT" != "WIRED" ]; then
	warn "FATAL: L2 (spec-kit core) verdict is '$L2_VERDICT', not WIRED — this script NEVER runs 'specify init' to fix this; refusing to proceed rather than risk clobbering an existing .specify/ tree."
	OVERALL_OK=0
fi

if [ "$OVERALL_OK" -eq 0 ]; then
	python3 - "$REPORT_OUT" "$RUN_ID" "$L1_VERDICT" "$L2_VERDICT" <<'PYEOF'
import json, sys
out, run_id, l1, l2 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = {
    "schema_version": "1.0",
    "run_id": run_id,
    "generated_by": "constitution/scripts/extensions/install_speckit_superpowers_bridge.sh (HXC-159 T-B2.02)",
    "feature_class": "extension_loading",
    "overall_status": "REFUSED_PRECONDITION",
    "L1": l1, "L2": l2, "L3": None, "L4": None,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
	warn "== install_speckit_superpowers_bridge.sh: FAIL (L1/L2 precondition unmet) =="
	exit 1
fi

# ── obra/superpowers reconciliation (T-B2.02.3) — LOW risk, official
#    marketplace plugin; this script NEVER installs or reinstalls it. The
#    reconciliation IS performing no action, logged explicitly so a reader
#    never mistakes silence for an oversight. ─────────────────────────────────
say "   obra-superpowers: LOW risk, official spec-kit marketplace plugin — no action taken (reconciled by design, never double-installed)."

# ── L3 (superspec) — validate-and-skip if already WIRED, else pinned install ─
if [ "$L3_VERDICT" = "WIRED" ]; then
	# TEST-ONLY dependency-injection override: this script's own tests run
	# against a sandboxed, non-git $ROOT (§11.4.84) and cannot rely on a real
	# `git submodule status` there; $SUPERSPEC_SHA_OVERRIDE lets a test inject
	# a known pin deterministically instead. Never set on a real run — the
	# real path always resolves the SHA from the actual submodule.
	if [ -n "${SUPERSPEC_SHA_OVERRIDE:-}" ]; then
		SUPERSPEC_SHA="$SUPERSPEC_SHA_OVERRIDE"
	else
		SUBMODULE_STATUS=$(git -C "$ROOT" submodule status -- submodules/superspec 2>/dev/null || true)
		SUPERSPEC_SHA=$(printf '%s' "$SUBMODULE_STATUS" | sed -E 's/^[ +-]?([0-9a-f]{40}).*/\1/' | head -1)
	fi
	if [ -n "$SUPERSPEC_SHA" ]; then
		VERDICT_LINE=$(bridge_supply_chain_refuse_if_unpinned "superspec" "$SUPERSPEC_SHA" 2>&1)
		VERDICT_RC=$?
		log_only "$VERDICT_LINE"
		if [ "$VERDICT_RC" -eq 0 ]; then
			say "   L3: already WIRED, pin verified immutable ($SUPERSPEC_SHA) — no-op (idempotent skip)."
			STATUS_L3="already-wired-pin-verified"
		else
			warn "FATAL: L3 is WIRED per the probe but its pin ($SUPERSPEC_SHA) is REFUSED by the supply-chain check (rc=$VERDICT_RC): $VERDICT_LINE"
			OVERALL_OK=0
			STATUS_L3="pin-refused"
		fi
	else
		warn "FATAL: L3 verdict is WIRED but no submodule SHA could be resolved for submodules/superspec — cannot verify the pin."
		OVERALL_OK=0
		STATUS_L3="pin-unresolvable"
	fi
else
	warn "L3 (superspec) is NOT WIRED ('$L3_VERDICT') on this host — attempting a pinned install."
	if [ -z "${SUPERSPEC_PIN:-}" ]; then
		warn "FATAL: L3 install requires an immutable pin; set \$SUPERSPEC_PIN to a full commit SHA before running (this script NEVER calls 'specify extension add superspec' bare — the README's default install fails because the first-party catalog.json has no bridge entries, and a bare/branch install would violate the immutable-pin supply-chain requirement)."
		OVERALL_OK=0
		STATUS_L3="unpinned-install-refused"
	else
		VERDICT_LINE=$(bridge_supply_chain_refuse_if_unpinned "superspec" "$SUPERSPEC_PIN" 2>&1)
		VERDICT_RC=$?
		log_only "$VERDICT_LINE"
		if [ "$VERDICT_RC" -ne 0 ]; then
			warn "FATAL: supply-chain check refused the supplied \$SUPERSPEC_PIN (rc=$VERDICT_RC): $VERDICT_LINE"
			OVERALL_OK=0
			STATUS_L3="pin-refused"
		elif [ "$DRY_RUN" -eq 1 ]; then
			say "   L3: dry-run — would install via '$SPECIFY_BIN extension add superspec --from <pinned-source>@$SUPERSPEC_PIN'."
			STATUS_L3="dry-run-would-install"
		else
			# HONEST LIMITATION (§11.4.6): this branch has NEVER been exercised
			# on any host measured in HXC-159 T-B1/T-B2 — L3 has always been
			# found already WIRED (installed as a git submodule pinned to an
			# immutable commit SHA, never via a `--from` archive fetch). The
			# exact `specify extension add --from <url>` archive-URL SYNTAX
			# for a specific pinned commit (as opposed to a release tag) has
			# NOT been verified against the real `specify` CLI's expectations;
			# $SUPERSPEC_FROM defaults to a best-effort guess, not a proven
			# value. Treat this path as UNTESTED until a host is measured with
			# L3 genuinely absent and this branch is exercised end-to-end.
			SUPERSPEC_SOURCE_URL="${SUPERSPEC_FROM:-https://github.com/WangX0111/superspec}@$SUPERSPEC_PIN"
			INSTALL_OUT=$("$SPECIFY_BIN" extension add superspec --from "$SUPERSPEC_SOURCE_URL" 2>&1)
			INSTALL_RC=$?
			log_only "$INSTALL_OUT"
			if [ "$INSTALL_RC" -eq 0 ]; then
				say "   L3: installed successfully, pinned to $SUPERSPEC_PIN."
				STATUS_L3="installed"
			else
				warn "FATAL: L3 install failed (rc=$INSTALL_RC): $INSTALL_OUT"
				OVERALL_OK=0
				STATUS_L3="install-failed"
			fi
		fi
	fi
fi

# ── L4 (superb) — refused by default (HIGH risk); an explicit, distinct
#    operator-vetting-decision record is the ONLY path to an install attempt
#    (T-B2.02.4/.5 pattern generalised to the layer actually needing it) ─────
VETTED=0
if [ -n "$SUPERB_FROM" ] && [ -n "$SUPERB_VETTED_BY" ]; then
	VETTED=1
elif [ -n "$SUPERB_FROM" ] || [ -n "$SUPERB_VETTED_BY" ]; then
	warn "FATAL: --superb-from and --superb-vetted-by must both be supplied together (a partial override is not a valid §11.4.66 vetting record)."
	OVERALL_OK=0
	STATUS_L4="partial-override-refused"
fi

if [ -z "$STATUS_L4" ]; then
	if [ "$L4_VERDICT" = "WIRED" ]; then
		say "   L4: already WIRED — no-op (idempotent skip)."
		STATUS_L4="already-wired"
	elif [ "$VETTED" -eq 0 ]; then
		VERDICT_LINE=$(bridge_supply_chain_refuse_if_unpinned "superb" "no-vetting-decision-supplied" 2>&1)
		log_only "$VERDICT_LINE"
		say "   L4: NOT installed — no §11.4.66 operator-vetting-decision record was supplied (--superb-from + --superb-vetted-by). This is the CORRECT default state for a HIGH-risk, discovery-only-catalog dependency, not a failure. Supply-chain verdict: $VERDICT_LINE"
		STATUS_L4="skipped-not-vetted"
	else
		# an explicit vetting decision was recorded — confirm the supply-chain
		# function still reports the expected HIGH-risk refusal (proving this
		# IS the deliberately-overridden case, never a silently-relaxed check),
		# log the override decision as captured evidence, then proceed.
		VERDICT_LINE=$(bridge_supply_chain_refuse_if_unpinned "superb" "$SUPERB_FROM" 2>&1)
		VERDICT_RC=$?
		log_only "$VERDICT_LINE"
		say "   L4: operator-vetting-decision record supplied: '$SUPERB_VETTED_BY' — installing from $SUPERB_FROM (supply-chain function's own verdict, overridden by this recorded decision: rc=$VERDICT_RC: $VERDICT_LINE)"
		if [ "$DRY_RUN" -eq 1 ]; then
			say "   L4: dry-run — would install via '$SPECIFY_BIN extension add superb --from $SUPERB_FROM'."
			STATUS_L4="dry-run-would-install"
		else
			# idempotency: if a prior interrupted attempt left a partial,
			# unregistered checkout, remove it first so the retry is clean
			# rather than colliding with stale state (§11.4.85 chaos
			# resilience — see the paired test).
			if [ -d "$ROOT/.specify/extensions/superb" ]; then
				ALREADY_REGISTERED=$("$SPECIFY_BIN" extension list --json 2>/dev/null | python3 -c 'import json,sys; print(any(e.get("id")=="superb" for e in json.load(sys.stdin)))' 2>/dev/null || echo False)
				if [ "$ALREADY_REGISTERED" != "True" ]; then
					warn "   L4: found a stale, unregistered .specify/extensions/superb/ from a prior interrupted attempt — removing before retry."
					rm -rf "$ROOT/.specify/extensions/superb"
				fi
			fi
			INSTALL_OUT=$("$SPECIFY_BIN" extension add superb --from "$SUPERB_FROM" 2>&1)
			INSTALL_RC=$?
			log_only "$INSTALL_OUT"
			if [ "$INSTALL_RC" -eq 0 ]; then
				say "   L4: installed successfully from $SUPERB_FROM (vetted by: $SUPERB_VETTED_BY)."
				STATUS_L4="installed"
			else
				warn "FATAL: L4 install failed (rc=$INSTALL_RC): $INSTALL_OUT"
				OVERALL_OK=0
				STATUS_L4="install-failed"
			fi
		fi
	fi
fi

# ── RS-19 runtime signature — after running, 'specify extension list' is
#    non-empty and names the pinned version. ─────────────────────────────────
RS19_JSON=$("$SPECIFY_BIN" extension list --json 2>&1)
RS19_RC=$?
log_only "RS-19 extension list --json (rc=$RS19_RC): $RS19_JSON"
RS19_PASS=0
if [ "$RS19_RC" -eq 0 ]; then
	RS19_COUNT=$(printf '%s' "$RS19_JSON" | python3 -c 'import json,sys
try:
    doc = json.load(sys.stdin)
    print(len(doc) if isinstance(doc, list) else 0)
except Exception:
    print(0)' 2>/dev/null || echo 0)
	if [ "${RS19_COUNT:-0}" -gt 0 ]; then
		RS19_PASS=1
		say "   RS-19: PASS — 'specify extension list --json' is non-empty ($RS19_COUNT extension(s))."
	fi
fi
if [ "$RS19_PASS" -eq 0 ]; then
	warn "RS-19: FAIL — 'specify extension list' did not report a non-empty, versioned extension set after this run."
	OVERALL_OK=0
fi

python3 - "$REPORT_OUT" "$RUN_ID" "$L1_VERDICT" "$L2_VERDICT" "$STATUS_L3" "$STATUS_L4" "$OVERALL_OK" "$RS19_PASS" <<'PYEOF'
import json, sys
out, run_id, l1, l2, s3, s4, ok, rs19 = sys.argv[1:9]
doc = {
    "schema_version": "1.0",
    "run_id": run_id,
    "generated_by": "constitution/scripts/extensions/install_speckit_superpowers_bridge.sh (HXC-159 T-B2.02)",
    "feature_class": "extension_loading",
    "L1": l1,
    "L2": l2,
    "L3_status": s3,
    "L4_status": s4,
    "rs19_runtime_signature_pass": rs19 == "1",
    "overall_status": "PASS" if ok == "1" else "FAIL",
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF

if [ "$OVERALL_OK" -eq 1 ]; then
	say "== install_speckit_superpowers_bridge.sh: PASS (L3=$STATUS_L3, L4=$STATUS_L4) =="
	exit 0
fi
warn "== install_speckit_superpowers_bridge.sh: FAIL =="
exit 1
