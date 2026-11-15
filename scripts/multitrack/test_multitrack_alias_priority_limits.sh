#!/bin/sh
# =============================================================================
# test_multitrack_alias_priority_limits.sh
#   — PROVABLY: (item 1) native-first priority rank, (item 2) per-alias
#     reason-CLASS limit + operational-again tracking (session/weekly/
#     subscription have DIFFERENT windows), and (item 3) auto-rebind-on-recovery
#     (`promote` returns a track to a recovered higher-priority native).
#     Anti-bluff: §11.4.115 RED-polarity + §1.1 paired mutation on the native-
#     first rank + §11.4.50 determinism + §11.4.69 captured evidence.
# -----------------------------------------------------------------------------
# Operator mandate 2026-07-14: native Claude aliases FIRST (as long as ≥1 is
#   operational — not session-429 / weekly-limited / subscription-expired) before
#   ANY provider; per-alias limit + subscription-expiry tracking from REAL signals
#   (never faked, §11.4.6 — the CLASS is supplied, the `until` epoch IS the
#   operational-again time); auto-use-on-recovery (rebind tracks UPWARD the moment
#   a higher-priority native recovers).
#
# Hermetic (§11.4.98): isolated MT_ALIAS_DIR per scenario, a temp tracks-only
#   config, MT_ALIAS_ROSTER injected — NO live registry, NO network, NO device.
#   Deterministic (§11.4.50): the battery runs 3x, normalized results byte-identical.
#
# Anti-bluff polarity (§11.4.115 one-source-two-roles via RED_MODE, default 1):
#   RED_MODE=1 (RED — defect on the BROKEN artifact): run the promote-on-recovery
#       scenario against a MUTATED copy of the orchestrator whose _alias_rank
#       native/provider bases are swapped (>>MT_ALIAS_MUT_RANK_NATIVE_FIRST). Assert
#       promote does NOT return the track to the recovered native (a provider
#       outranks it) — the native-first-in-promote defect PRESENT. A RED that does
#       not reproduce is a blind test -> FAIL.
#   RED_MODE=0 (GREEN — defect ABSENT on the REAL/fixed orchestrator): assert all
#       three items' correct behaviour AND re-run the §1.1 mutation self-check.
#
# Usage:  RED_MODE=1 sh test_multitrack_alias_priority_limits.sh   # RED
#         RED_MODE=0 sh test_multitrack_alias_priority_limits.sh   # GREEN
# Exit:   0 iff FAIL==0.
# Evidence: qa-results/multitrack_alias_priority_limits/<UTC>/
# Deps: POSIX sh, bash (orchestrator shebang), sed, awk, date, mktemp, diff.
# Cross-refs: multitrack_alias_orchestrator.sh (mark-limited / mark-operational /
#   promote / _alias_rank / _cooldown_until_for_class / >>MT_ALIAS_MUT_RANK_NATIVE_FIRST).
# =============================================================================

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF=$0; case "$SELF" in */*) DIR=${SELF%/*} ;; *) DIR=. ;; esac
DIR=$(cd "$DIR" 2>/dev/null && pwd)
[ -n "$DIR" ] || { echo "FATAL: cannot resolve self dir" >&2; exit 2; }
ORCH="$DIR/multitrack_alias_orchestrator.sh"
[ -r "$ORCH" ] || { echo "FATAL: orchestrator not found: $ORCH" >&2; exit 2; }
bash -n "$ORCH" 2>/dev/null || { echo "FATAL: orchestrator fails bash -n" >&2; exit 2; }

ROOT=$(cd "$DIR/../../.." 2>/dev/null && pwd)
[ -n "$ROOT" ] || ROOT=$(cd "$DIR" && git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT="$DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%s)
EV="$ROOT/qa-results/multitrack_alias_priority_limits/$TS"; mkdir -p "$EV" || { echo "FATAL: mkdir $EV" >&2; exit 2; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/apl.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM
RED_MODE="${RED_MODE:-1}"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" | tee -a "$EV/results.log"; }

CFG="$WORK/cfg.yaml"
cat > "$CFG" <<'YAML'
schema_version: 1
host:
  hostname: apl-host
tracks:
  - id: track-1
    role: main
    branch: main
    mount: /tmp/apl/track1
device_pool:
  - id: D1
    adb_serial: "0000000000000000"
    capabilities: ["x"]
YAML
ROSTER="claude1:native claude2:native claude3:native claude4:native deepseek:provider xiaomi:provider"

# mutated orchestrator: swap the _alias_rank native/provider bases (provider now
# outranks native — the native-first-in-promote defect class).
MUT="$WORK/orch_mut.sh"
sed 's/native) _base=0 ;; \*) _base=100000 ;;/native) _base=100000 ;; *) _base=0 ;;/' "$ORCH" > "$MUT"
grep -q 'native) _base=100000 ;; \*) _base=0 ;;' "$MUT" || { echo "FATAL: rank mutation did not apply" >&2; exit 2; }
chmod +x "$MUT" 2>/dev/null || true

# run the orchestrator (real or mutated) in an isolated alias dir.
_orch() { _o="$1"; _ad="$2"; shift 2
    MT_SCRIPTS_DIR="$DIR" MT_CONFIG="$CFG" MT_ALIAS_DIR="$_ad" MT_ALIAS_ROSTER="$ROSTER" \
        MT_COOLDOWN_SESSION=100 MT_COOLDOWN_WEEKLY=1000000 \
        bash "$_o" "$@"; }
# alias bound to track-1 (from the isolated bindings snapshot).
_track1_alias() { awk -F'|' '$2=="track-1"{print $1; exit}' "$1/bindings.snapshot" 2>/dev/null; }
# cooldown fields for an alias: prints "until|class" (empty if not cooled).
_cool_fields() { awk -F'|' -v a="$1" '$1==a{printf "%s|%s",$2,($4==""?"session":$4); exit}' "$2/cooldowns.snapshot" 2>/dev/null; }

run_battery() {  # $1 iter ; writes normalized lines to $2
    _it=$1; _norm=$2; : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # RED: promote-on-recovery MUST FAIL to prefer the native on the MUTATED rank.
        AD="$WORK/ad_red_$_it"; mkdir -p "$AD"
        _orch "$MUT" "$AD" bind --alias deepseek --track track-1 >/dev/null 2>&1
        _orch "$MUT" "$AD" promote >/dev/null 2>&1
        got=$(_track1_alias "$AD")
        printf 'RED_promote_result=%s\n' "$got" >> "$_norm"
        if [ "$got" = "deepseek" ]; then
            pass "RED[it$_it]: mutated-rank promote LEFT track-1 on provider 'deepseek' (native NOT preferred) — defect reproduced"
        else
            fail "RED[it$_it]: mutated-rank promote moved track-1 to '$got' — defect did NOT reproduce (blind test §11.4.115)"
        fi
        return 0
    fi

    # ------- GREEN -----------------------------------------------------------
    # item 1: native-first — auto-assign under a native-inclusive roster picks a native.
    AD="$WORK/ad_g1_$_it"; mkdir -p "$AD"
    _orch "$ORCH" "$AD" auto-assign >/dev/null 2>&1
    a1=$(_track1_alias "$AD"); printf 'g1_autoassign=%s\n' "$a1" >> "$_norm"
    case "$a1" in claude[0-9]*) pass "GREEN[it$_it] item1: auto-assign bound track-1 to NATIVE '$a1' (native-first)";;
        *) fail "GREEN[it$_it] item1: auto-assign bound track-1 to '$a1' (not native)";; esac

    # item 2: per-CLASS limit windows + operational-again + class recorded.
    AD="$WORK/ad_g2_$_it"; mkdir -p "$AD"
    now=$(date +%s)
    _orch "$ORCH" "$AD" mark-limited --alias claude1 --class session >/dev/null 2>&1
    _orch "$ORCH" "$AD" mark-limited --alias claude2 --class weekly >/dev/null 2>&1
    _orch "$ORCH" "$AD" mark-limited --alias claude3 --class subscription >/dev/null 2>&1
    sf=$(_cool_fields claude1 "$AD"); wf=$(_cool_fields claude2 "$AD"); bf=$(_cool_fields claude3 "$AD")
    su=${sf%%|*}; sc=${sf##*|}; wu=${wf%%|*}; wc=${wf##*|}; bu=${bf%%|*}; bc=${bf##*|}
    printf 'g2_session=%s g2_weekly=%s g2_subscription=%s\n' "$sc" "$wc" "$bc" >> "$_norm"
    # class recorded correctly
    { [ "$sc" = session ] && [ "$wc" = weekly ] && [ "$bc" = subscription ]; } \
        && pass "GREEN[it$_it] item2: cooldown snapshot records class session/weekly/subscription" \
        || fail "GREEN[it$_it] item2: class mis-recorded (session=$sc weekly=$wc subscription=$bc)"
    # windows DIFFER by class: session ~ now+100, weekly ~ now+1000000, subscription = far-future sentinel
    { [ "$su" -ge "$now" ] && [ "$su" -le "$((now+300))" ]; } \
        && pass "GREEN[it$_it] item2: session operational-again ~ now+100s ($su)" \
        || fail "GREEN[it$_it] item2: session window wrong ($su vs now=$now)"
    { [ "$wu" -ge "$((now+900000))" ]; } \
        && pass "GREEN[it$_it] item2: weekly operational-again ~ now+1000000s ($wu) — distinct long window" \
        || fail "GREEN[it$_it] item2: weekly window wrong ($wu vs now=$now)"
    { [ "$bu" -ge 4102444800 ]; } \
        && pass "GREEN[it$_it] item2: subscription operational-again = far-future sentinel ($bu) — indefinite until renewal" \
        || fail "GREEN[it$_it] item2: subscription sentinel wrong ($bu)"

    # item 3a: promote returns a provider-bound track UP to the best native.
    AD="$WORK/ad_g3a_$_it"; mkdir -p "$AD"
    _orch "$ORCH" "$AD" bind --alias deepseek --track track-1 >/dev/null 2>&1
    _orch "$ORCH" "$AD" promote >/dev/null 2>&1
    p1=$(_track1_alias "$AD"); printf 'g3a_promote=%s\n' "$p1" >> "$_norm"
    [ "$p1" = "claude1" ] \
        && pass "GREEN[it$_it] item3: promote returned provider-bound track-1 UP to best native 'claude1'" \
        || fail "GREEN[it$_it] item3: promote left track-1 on '$p1' (expected claude1)"

    # item 3b: recovery — all natives limited -> promote is a no-op; recover claude2 -> promote rebinds to it.
    AD="$WORK/ad_g3b_$_it"; mkdir -p "$AD"
    _orch "$ORCH" "$AD" bind --alias deepseek --track track-1 >/dev/null 2>&1
    for a in claude1 claude2 claude3 claude4; do _orch "$ORCH" "$AD" mark-limited --alias "$a" --class session >/dev/null 2>&1; done
    _orch "$ORCH" "$AD" promote >/dev/null 2>&1
    r0=$(_track1_alias "$AD"); printf 'g3b_before=%s\n' "$r0" >> "$_norm"
    [ "$r0" = "deepseek" ] \
        && pass "GREEN[it$_it] item3: all natives limited -> promote is a no-op (track-1 stays deepseek)" \
        || fail "GREEN[it$_it] item3: promote wrongly moved track-1 to '$r0' while all natives limited"
    _orch "$ORCH" "$AD" mark-operational --alias claude2 >/dev/null 2>&1
    _orch "$ORCH" "$AD" promote >/dev/null 2>&1
    r1=$(_track1_alias "$AD"); printf 'g3b_after=%s\n' "$r1" >> "$_norm"
    [ "$r1" = "claude2" ] \
        && pass "GREEN[it$_it] item3: recovered native 'claude2' -> promote auto-rebound track-1 to it" \
        || fail "GREEN[it$_it] item3: after claude2 recovered, track-1 on '$r1' (expected claude2)"

    # §1.1 self-check: mutated rank -> promote does NOT prefer the native.
    AD="$WORK/ad_mut_$_it"; mkdir -p "$AD"
    _orch "$MUT" "$AD" bind --alias deepseek --track track-1 >/dev/null 2>&1
    _orch "$MUT" "$AD" promote >/dev/null 2>&1
    m1=$(_track1_alias "$AD"); printf 'mut_selfcheck=%s\n' "$m1" >> "$_norm"
    [ "$m1" = "deepseek" ] \
        && pass "GREEN[it$_it] §1.1 self-check: mutated rank leaves track-1 on provider (fix provably catches the negation)" \
        || fail "GREEN[it$_it] §1.1 self-check: mutated rank moved track-1 to '$m1' — bluff-capable"
}

for _i in 1 2 3; do run_battery "$_i" "$EV/normalized_iter${_i}.txt"; done
if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
   && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
    pass "determinism: 3/3 iterations byte-identical (RED_MODE=$RED_MODE)"
else
    fail "determinism: iterations diverged (RED_MODE=$RED_MODE)"
fi
{ printf 'test=alias_priority_limits RED_MODE=%s\nPASS=%s FAIL=%s\nresult=%s\n' \
    "$RED_MODE" "$PASS" "$FAIL" "$( [ "$FAIL" -eq 0 ] && echo PASS || echo FAIL )"; } > "$EV/SUMMARY.txt"
printf '\n== alias-priority+limits test (RED_MODE=%s): %s == PASS=%s FAIL=%s\nEvidence: %s\n' \
    "$RED_MODE" "$( [ "$FAIL" -eq 0 ] && echo PASS || echo FAIL )" "$PASS" "$FAIL" "$EV"
[ "$FAIL" -eq 0 ]
