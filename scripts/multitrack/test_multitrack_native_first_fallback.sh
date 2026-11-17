#!/bin/sh
# =============================================================================
# test_multitrack_native_first_fallback.sh
#     — PROVABLY native-first alias selection + provider-fallback, anti-bluff.
#       (§11.4.115 RED-polarity + §1.1 paired mutation; operator mandate
#        2026-07-10: fallback MUST switch to the first WORKING NATIVE Claude
#        alias FIRST, providers ONLY when NO native works.)
# -----------------------------------------------------------------------------
# Purpose:
#   Prove that multitrack_alias_orchestrator.sh:_next_available_alias selects a
#   NATIVE alias whenever ANY non-cooled native exists — REGARDLESS of the roster
#   file order (the config-drift the fix must be robust to) — and falls to a
#   provider ONLY when every native is cooled/excluded. The load-bearing
#   invariant is the CLASS partition (`for class in native provider`), NOT
#   roster file position.
#
# Anti-bluff design (§11.4.115 one-source-two-roles polarity + §1.1 mutation):
#   The SAME test source runs two roles via RED_MODE (default 1):
#     RED_MODE=1 (RED — reproduce the defect on the BROKEN artifact): run the
#         native-first scenario against a MUTATED copy of the orchestrator whose
#         class order is flipped (`provider native`) — the exact pre-fix defect
#         class. Assert a PROVIDER wins while a native is healthy (defect PRESENT).
#         A RED that does NOT reproduce is a blind test (§11.4.115) -> FAIL.
#     RED_MODE=0 (GREEN — the ruler-suite polarity, defect ABSENT): run the same
#         scenario against the REAL (fixed) orchestrator -> a NATIVE must win; AND
#         run the provider-fallback scenario (all natives cooled + limiter
#         excluded) -> deepseek (first provider) must win; AND re-run the §1.1
#         mutation self-check (mutated copy -> provider wins) so the GREEN run
#         itself proves the guard catches the negation.
#
#   Fully hermetic (§11.4.98): isolated MT_ALIAS_DIR per scenario, a temp
#   tracks-only config, MT_ALIAS_ROSTER injected — NO live registry touched, NO
#   live rebind side-effect, no network. Deterministic (§11.4.50).
#
# Usage:  sh test_multitrack_native_first_fallback.sh   (RED_MODE=0|1 env)
# Exit:   0 = role satisfied; 1 = FAIL; 2 = harness setup error.
# Evidence: qa-results/multitrack_native_first_resume/<UTC-ts>/  (exit codes +
#           captured orchestrator output per scenario).
# Deps: POSIX sh, bash (the orchestrator's shebang), sed, awk, mkdir, date.
# Cross-refs: multitrack_alias_orchestrator.sh (_next_available_alias, native-
#   first partition + >>MT_ALIAS_MUT_NATIVE_FIRST marker); §11.4.111 / §11.4.6.
# =============================================================================

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
_self="$0"
case "$_self" in */*) _dir=${_self%/*} ;; *) _dir=. ;; esac
_dir=$(cd "$_dir" 2>/dev/null && pwd)
[ -n "$_dir" ] || { echo "FATAL: cannot resolve self dir" >&2; exit 2; }

ORCH="$_dir/multitrack_alias_orchestrator.sh"
[ -r "$ORCH" ] || { echo "FATAL: orchestrator not found at $ORCH" >&2; exit 2; }

# repo root = constitution/scripts/multitrack -> ../../..
ROOT=$(cd "$_dir/../../.." 2>/dev/null && pwd)
[ -n "$ROOT" ] || ROOT=$(cd "$_dir" && git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT="$_dir"

TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%SZ)
EVDIR="$ROOT/qa-results/multitrack_native_first_resume/$TS"
mkdir -p "$EVDIR" 2>/dev/null || { echo "FATAL: cannot create $EVDIR" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/nff.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM

RED_MODE="${RED_MODE:-1}"

# --- minimal tracks-only config (project-agnostic; single track) -------------
CFG="$WORK/cfg.yaml"
cat > "$CFG" <<'YAML'
schema_version: 1
host:
  hostname: nff-host
tracks:
  - id: track-1
    role: main
    branch: main
    mount: /tmp/nff/track1
device_pool:
  - id: D1
    adb_serial: "0000000000000000"
    capabilities: ["x"]
YAML

# mutated orchestrator: flip the class-iteration order (the §1.1 mutation — the
# pre-fix defect class). The >>MT_ALIAS_MUT_NATIVE_FIRST marker documents this.
MUT="$WORK/orch_mutated.sh"
sed 's/for class in native provider/for class in provider native/' "$ORCH" > "$MUT" \
    || { echo "FATAL: could not build mutated orchestrator" >&2; exit 2; }
chmod +x "$MUT" 2>/dev/null || true
if ! grep -q 'for class in provider native' "$MUT"; then
    echo "FATAL: mutation did not apply (marker/line changed?) — cannot prove native-first" >&2
    exit 2
fi

# run auto-assign in an isolated dir; echo the alias bound to track-1.
# args: <orch-path> <roster> <run-tag>
_pick_autoassign() {
    _o="$1"; _roster="$2"; _tag="$3"
    _ad="$WORK/ad_$_tag"; mkdir -p "$_ad"
    _out="$EVDIR/${_tag}.out"
    MT_SCRIPTS_DIR="$_dir" MT_CONFIG="$CFG" MT_ALIAS_DIR="$_ad" \
        MT_ALIAS_ROSTER="$_roster" \
        bash "$_o" auto-assign > "$_out" 2>&1
    _rc=$?
    printf 'exit=%s\n' "$_rc" >> "$_out"
    sed -n 's/.*alias=\([^ ]*\) -> track=track-1.*/\1/p' "$_out" | head -n1
}

# provider-fallback scenario: bind claude4 -> track-1, cool claude1/2/3, then
# fallback --track track-1 excluding claude4. echo the alias track-1 falls TO.
# args: <orch-path> <roster> <run-tag>
_pick_fallback() {
    _o="$1"; _roster="$2"; _tag="$3"
    _ad="$WORK/ad_$_tag"; mkdir -p "$_ad"
    _out="$EVDIR/${_tag}.out"
    : > "$_out"
    MT_SCRIPTS_DIR="$_dir" MT_CONFIG="$CFG" MT_ALIAS_DIR="$_ad" \
        MT_ALIAS_ROSTER="$_roster" \
        bash "$_o" bind --alias claude4 --track track-1 >> "$_out" 2>&1
    # pre-seed a FAR-FUTURE cooldown for the three other natives (survives _reap).
    _until=$(( $(date +%s) + 100000 ))
    {
        printf 'claude1|%s|test-cooled\n' "$_until"
        printf 'claude2|%s|test-cooled\n' "$_until"
        printf 'claude3|%s|test-cooled\n' "$_until"
    } > "$_ad/cooldowns.snapshot"
    MT_SCRIPTS_DIR="$_dir" MT_CONFIG="$CFG" MT_ALIAS_DIR="$_ad" \
        MT_ALIAS_ROSTER="$_roster" \
        bash "$_o" fallback --track track-1 >> "$_out" 2>&1
    _rc=$?
    printf 'exit=%s\n' "$_rc" >> "$_out"
    sed -n 's/.*claude4->\([A-Za-z0-9_-]*\).*/\1/p' "$_out" | head -n1
}

# is $1 a native alias name? (claude<digits>)
_is_native() { case "$1" in claude[0-9]*) return 0 ;; *) return 1 ;; esac; }

# adversarial roster: a PROVIDER appears FIRST in file order (config-drift the
# fix must survive). A roster-order-only selector would pick deepseek here.
ROSTER_DRIFT="deepseek:provider claude1:native claude2:native claude3:native claude4:native"
# full roster for the fallback scenario (authoritative ordering).
ROSTER_FULL="claude1:native claude2:native claude3:native claude4:native deepseek:provider xiaomi:provider opencode:provider kimi-for-coding:provider"

FAILS=0
_note() { printf '%s\n' "$*"; }

if [ "$RED_MODE" = "1" ]; then
    # ---- RED: reproduce the defect on the BROKEN (mutated) artifact ----------
    picked="$(_pick_autoassign "$MUT" "$ROSTER_DRIFT" red_mut_autoassign)"
    if _is_native "$picked"; then
        _note "RED FAIL: mutated (class-flipped) orchestrator picked NATIVE '$picked' — the defect did NOT reproduce (blind test, §11.4.115)"
        FAILS=$((FAILS + 1))
    else
        _note "RED OK: mutated (class-flipped) orchestrator picked PROVIDER '$picked' while a native was healthy — defect reproduced as expected"
    fi
else
    # ---- GREEN: defect ABSENT on the REAL (fixed) artifact -------------------
    # (1) native-first: adversarial provider-first roster -> a NATIVE must win.
    picked="$(_pick_autoassign "$ORCH" "$ROSTER_DRIFT" green_native_first)"
    if _is_native "$picked"; then
        _note "GREEN OK (native-first): real orchestrator picked NATIVE '$picked' despite a provider-first roster"
    else
        _note "GREEN FAIL (native-first): real orchestrator picked '$picked' (not a native) — native-first violated"
        FAILS=$((FAILS + 1))
    fi

    # (2) provider-fallback: all natives cooled + claude4 excluded -> deepseek.
    fell="$(_pick_fallback "$ORCH" "$ROSTER_FULL" green_provider_fallback)"
    if [ "$fell" = "deepseek" ]; then
        _note "GREEN OK (provider-fallback): claude1/2/3 cooled + claude4 excluded -> fell to first provider 'deepseek'"
    else
        _note "GREEN FAIL (provider-fallback): expected 'deepseek', got '$fell'"
        FAILS=$((FAILS + 1))
    fi

    # (3) §1.1 self-check: the mutation MUST break native-first (provider wins).
    mpicked="$(_pick_autoassign "$MUT" "$ROSTER_DRIFT" green_mutation_selfcheck)"
    if _is_native "$mpicked"; then
        _note "GREEN FAIL (mutation self-check): mutated orchestrator STILL picked native '$mpicked' — the guard does not catch the negation (bluff-capable)"
        FAILS=$((FAILS + 1))
    else
        _note "GREEN OK (mutation self-check): mutated (class-flipped) orchestrator picked provider '$mpicked' — the guard provably catches the negation (§1.1)"
    fi
fi

# --- evidence summary --------------------------------------------------------
{
    printf 'test=test_multitrack_native_first_fallback.sh RED_MODE=%s\n' "$RED_MODE"
    printf 'timestamp=%s\n' "$TS"
    printf 'fails=%s\n' "$FAILS"
    printf 'result=%s\n' "$( [ "$FAILS" -eq 0 ] && echo PASS || echo FAIL )"
} > "$EVDIR/SUMMARY.txt"

printf '\n== native-first test (RED_MODE=%s) : %s == (evidence: %s)\n' \
    "$RED_MODE" "$( [ "$FAILS" -eq 0 ] && echo PASS || echo FAIL )" "$EVDIR"

[ "$FAILS" -eq 0 ]
