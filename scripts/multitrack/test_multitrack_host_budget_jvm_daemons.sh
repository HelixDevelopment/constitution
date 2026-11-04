#!/bin/sh
# =============================================================================
# test_multitrack_host_budget_jvm_daemons.sh — RB-FIX3 (I-c) permanent
#     regression guard: multitrack_host_budget.sh's
#     MT_HOST_BUDGET_BUILD_PGREP_PATTERN default gained four JVM-daemon
#     tokens (`gradle-launcher`, `ScalaCompileDaemon`, `GroovyCompileDaemon`,
#     `kotlin-compiler-embeddable` -- the project's own documented §12.8b
#     "complete" JVM-daemon set) but an independent code review found NONE
#     of those four literals appeared anywhere in the guard's existing test
#     (scripts/multitrack/test_multitrack_host_budget.sh) -- the existing
#     GREEN(i)/(ii)/(iii)/(iv) scenarios all still passed, but none of them
#     specifically proved the guard fires when one of the *new* four
#     processes is the one alive (only the six PRE-EXISTING tokens were
#     ever exercised: `m -j`, `gradle`, `build_maxres`, `GradleDaemon`,
#     `GradleWorkerMain`, `KotlinCompileDaemon`).
# -----------------------------------------------------------------------------
# This file closes that gap with one dedicated GREEN case PER new token,
# mirroring the existing test's own fake-`pgrep`-shim convention (a
# realistic SIMULATED live-process cmdline matched via the REAL alternation
# pattern's own regex semantics -- never a real spawned process, §12.6/
# §11.4.133 host-safety).
#
# Honest boundary (§11.4.6 -- no fabricated RED for a token where none is
# possible): `gradle-launcher` is a STRICT SUBSTRING SUPERSET of the
# pre-existing bare `gradle` alternative ("gradle-launcher" contains
# "gradle" as its own literal prefix) -- ANY cmdline matching
# `gradle-launcher` therefore ALREADY matches the pre-fix pattern's bare
# `gradle` token too. A "RED: pattern misses gradle-launcher" scenario is
# therefore mathematically IMPOSSIBLE to construct honestly (constructing
# one would require an unrealistic/dishonest fixture engineered just to
# dodge the redundant match, which this project's own anti-bluff covenant
# forbids). This file states that fact as FACT (verified below by a
# dedicated self-check) and gives `gradle-launcher` a GREEN-only detection
# proof; the other three tokens (`ScalaCompileDaemon`, `GroovyCompileDaemon`,
# `kotlin-compiler-embeddable`) are NOT substrings of any pre-existing
# token and get full RED(missing)+GREEN(detected) pairs, reproduced against
# the pre-fix pattern (the current default with exactly the four new tokens
# deleted, verified to omit them; equal to the default at 55998fb^).
#
# Purpose (§11.4.114/§11.4.115 RED-on-the-broken-artifact + polarity switch):
#   RED_MODE=1 (default) — for each of the 3 non-redundant tokens
#     (ScalaCompileDaemon / GroovyCompileDaemon / kotlin-compiler-embeddable),
#     sources the guard with MT_HOST_BUDGET_BUILD_PGREP_PATTERN forced to
#     the pre-fix default (the current default minus the 4 new tokens,
#     verified to omit them and keep the 6 old ones), simulates a
#     realistic live-process cmdline containing ONLY that token (no overlap
#     with ANY pre-existing alternative, verified below), and asserts
#     `mt_host_budget_can_spawn 0` wrongly ALLOWS (rc=0) -- the coverage gap,
#     reproduced functionally, not merely quoted. A RED-control on the SAME
#     stubbed path with the CURRENT default must REFUSE (rc=2), so the RED
#     cannot pass blind.
#   RED_MODE=0 (GREEN) — sources the CURRENT (fixed) guard and, for ALL 4
#     tokens (including the redundant `gradle-launcher`), proves
#     `mt_host_budget_can_spawn 0` correctly REFUSES (rc=2, the build-guard
#     cause in isolation) when that token's simulated process is alive; a
#     negative control (no simulated process at all) proves the same
#     pattern does NOT false-positive (rc=0/ALLOW) on an idle host.
#     §11.4.120 reconciliation (2026-07-15): after the §11.4.201 vanished-PID
#     liveness fix, an empty-cmdline matched PID is SKIPPED (a fake dead PID no
#     longer conservatively REFUSEs), so the GREEN detection scenarios now stub
#     BOTH the _mt_host_budget_pid_cmdline (return the simulated token cmdline)
#     and _mt_host_budget_pid_alive (return live) seams -- the fake matched PID
#     is now a LIVE, READABLE, non-excluded survivor (a genuine build), asserting
#     the guard's REAL detection mechanism, not the removed empty-REFUSE side
#     effect.
#   Both modes run their battery 3 times (§11.4.50 determinism) and assert
#   the normalized (PID-free) results are byte-identical across all 3
#   iterations.
#
# Usage:
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_host_budget_jvm_daemons.sh   # RED
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_host_budget_jvm_daemons.sh   # GREEN
#   (default RED_MODE=1 if unset)
#
# Inputs: RED_MODE (0|1, default 1); MT_TEST_CONST_ROOT (optional override,
#   else `git rev-parse --show-toplevel` from this file's own directory);
#   optional MT_HBJVM_TEST_EVIDENCE_DIR override.
#
# Outputs: PASS/FAIL/SKIP lines on stdout + $EV/results.log; per-iteration
#   captured decision-line output under $EV. Exit 0 iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir (fake `pgrep` shim +
#   a stub host-safety lib, mirroring scripts/multitrack/
#   test_multitrack_host_budget.sh's own house style); `trap ... EXIT INT
#   TERM` cleanup on every exit path (§11.4.14); NEVER spawns a real
#   process, NEVER runs a real build, NEVER touches a real device.
#
# Dependencies: sh (POSIX), git, date, mktemp, diff, sed, grep.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_host_budget.sh (the guard
#     under test, unmodified by this fix -- I-c is test-coverage-only, the
#     4-token pattern completion itself already landed as an uncommitted
#     working-tree change, confirmed via `git diff HEAD` showing the change
#     is isolated to the MT_HOST_BUDGET_BUILD_PGREP_PATTERN default line +
#     its comment);
#   scripts/multitrack/test_multitrack_host_budget.sh (the PRE-EXISTING RB-02
#     test whose fake-pgrep-shim + HOST_SAFETY_LIB-stub house style this
#     file mirrors exactly, per §11.4.74 extend-not-reinvent);
#   qa-results/multitrack/RB_COMBINED_REVIEW_report.md (the Important
#     finding this closes);
#   §11.4.6 (no-guessing -- the gradle-launcher redundancy is stated as
#     verified FACT, never as an assumption); §11.4.74 (extend-not-reinvent
#     -- the fake-pgrep-shim convention); §11.4.114/§11.4.115 (RED-on-the-
#     real-git-HEAD-artifact + polarity switch); §11.4.50 (determinism);
#     §11.4.67 (sh-parseable); §11.4.135 (permanent regression guard);
#     §12.6/§12.7/§12.8 (the memory-budget + concurrency-hardening
#     mechanisms this guard enforces).
# =============================================================================

set -u

MT_HBJ_SELF=$0
case "$MT_HBJ_SELF" in
    */*) MT_HBJ_DIR=${MT_HBJ_SELF%/*} ;;
    *)   MT_HBJ_DIR=. ;;
esac

_hbjvm_const_root() {
    if [ -n "${MT_TEST_CONST_ROOT:-}" ]; then printf '%s\n' "$MT_TEST_CONST_ROOT"; return 0; fi
    ( cd "$MT_HBJ_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
CONST_ROOT=$(_hbjvm_const_root)
[ -n "$CONST_ROOT" ] || { echo "FATAL: no constitution submodule root (git toplevel / \$MT_TEST_CONST_ROOT)" >&2; exit 90; }

GUARD_FILE="$CONST_ROOT/scripts/multitrack/multitrack_host_budget.sh"
[ -f "$GUARD_FILE" ] || { echo "FATAL: guard file not found: $GUARD_FILE" >&2; exit 91; }
sh -n "$GUARD_FILE" 2>/dev/null || { echo "FATAL: guard file fails sh -n: $GUARD_FILE" >&2; exit 92; }

RED_MODE="${RED_MODE:-1}"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
_hbjvm_evidence_home() {
    _ph=$(cd "$CONST_ROOT/.." 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$_ph" ] && [ -d "$_ph" ]; then printf '%s/qa-results/multitrack\n' "$_ph"; return 0; fi
    printf '%s/qa-results/multitrack\n' "$CONST_ROOT"
}
EV="${MT_HBJVM_TEST_EVIDENCE_DIR:-$(_hbjvm_evidence_home)/hbjvm_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_hbjvm_test.XXXXXX")
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s (%s) [evidence: %s]\n' "$1" "$2" "$3" | tee -a "$EV/results.log"; }

# --- fake pgrep: evaluates the REAL alternation pattern (as a POSIX ERE,
#     the SAME semantics real `pgrep -f` uses) against ONE simulated live
#     process cmdline this test controls via $SIM_LIVE_PROC_CMDLINE -- never
#     a real process, never touches the real process table. -----------------
cat > "$FAKEBIN/pgrep" <<'PGREPEOF'
#!/bin/sh
# invoked as: pgrep -f "PATTERN"
shift
pattern="$1"
if [ -n "${SIM_LIVE_PROC_CMDLINE:-}" ] && printf '%s' "$SIM_LIVE_PROC_CMDLINE" | grep -Eq -- "$pattern" 2>/dev/null; then
    echo 77777
    exit 0
fi
exit 1
PGREPEOF
chmod +x "$FAKEBIN/pgrep"

HSS="$WORK/hss.sh"
printf 'host_safe_parallel_jobs() { echo 4; }\nHOST_SAFETY_BUDGET_GB=99\n' > "$HSS"
export HOST_SAFETY_LIB="$HSS"

# --- pre-fix pattern -- DERIVED from the CURRENT guard's default by deleting
#     exactly the four RB-FIX3 tokens (a durable mutated copy, the same
#     technique test_multitrack_host_budget_rb02_pgrep.sh uses), then verified
#     to omit all four and to keep every pre-existing token (§11.4.6).
#     History (§11.4.124, 2026-11-04): this block used to read `git show
#     HEAD:` and exit 94 when HEAD already held the tokens. The test and the
#     token fix landed in the SAME commit (55998fb), so from that commit on the
#     default RED mode exited 94 on every clean checkout. The pattern at
#     55998fb^ equals the derived one below (checked by hand 2026-11-04).
CUR_PATTERN=$(sed -n 's/^MT_HOST_BUDGET_BUILD_PGREP_PATTERN="\${MT_HOST_BUDGET_BUILD_PGREP_PATTERN:-\(.*\)}"$/\1/p' "$GUARD_FILE")
if [ -z "$CUR_PATTERN" ]; then
    echo "FATAL: could not extract MT_HOST_BUDGET_BUILD_PGREP_PATTERN's default from $GUARD_FILE" >&2
    exit 93
fi
HEAD_PATTERN=""
if [ "$RED_MODE" = "1" ]; then
    HEAD_PATTERN=$(printf '%s\n' "$CUR_PATTERN" | tr '|' '\n' \
        | grep -vxF -e gradle-launcher -e ScalaCompileDaemon -e GroovyCompileDaemon -e kotlin-compiler-embeddable \
        | paste -sd'|' -)
    for _newtok in gradle-launcher ScalaCompileDaemon GroovyCompileDaemon kotlin-compiler-embeddable; do
        case "$HEAD_PATTERN" in
            *"$_newtok"*)
                echo "FATAL: derived pre-fix pattern still contains '$_newtok' -- cannot honestly claim RED reproduction (§11.4.6)" >&2
                exit 94
                ;;
        esac
    done
    for _oldtok in 'm -j' gradle build_maxres GradleDaemon GradleWorkerMain KotlinCompileDaemon; do
        case "|$HEAD_PATTERN|" in
            *"|$_oldtok|"*) : ;;
            *) echo "FATAL: derived pre-fix pattern lost the pre-existing token '$_oldtok' ($HEAD_PATTERN)" >&2; exit 94 ;;
        esac
    done
fi

# --- self-check (both modes): `gradle-launcher` is PROVABLY a substring
#     superset of the pre-existing bare `gradle` token -- verified
#     mechanically here (never asserted from memory, §11.4.6) so the
#     RED-impossibility claim in this file's own docstring is FACT, not
#     hand-waving.
case "gradle-launcher" in
    *gradle*) : ;;
    *) echo "FATAL: 'gradle-launcher' unexpectedly does NOT contain 'gradle' as a substring -- the RED-impossibility premise in this file's docstring is WRONG, stop and re-investigate" >&2; exit 95 ;;
esac

# --- simulated realistic cmdlines. The 3 non-redundant tokens deliberately
#     avoid Gradle-managed paths (a Maven/.m2 + plain-install + sbt/.ivy2
#     shape instead) so they do NOT incidentally also contain "gradle"
#     (lowercase, the pre-existing bare alternative) or any other
#     pre-existing token -- verified below before trusting them. --------
CMD_GRADLE_LAUNCHER='/usr/bin/java -Dorg.gradle.appname=gradle -classpath /opt/gradle-8.5/lib/gradle-launcher-8.5.jar org.gradle.launcher.GradleMain build'
CMD_SCALA='java -Xmx2g -cp /home/user/.ivy2/cache/org.scala-sbt/compiler-bridge/scala-compiler.jar ScalaCompileDaemon --port=0'
CMD_GROOVY='java -cp /opt/groovy-4.0.15/lib/groovy-4.0.15.jar GroovyCompileDaemon'
CMD_KOTLIN='java -cp /home/user/.m2/repository/org/jetbrains/kotlin/kotlin-compiler-embeddable/1.9.22/kotlin-compiler-embeddable-1.9.22.jar org.jetbrains.kotlin.daemon.CompileDaemon'

PRE_EXISTING_TOKENS='m -j
gradle
build_maxres
GradleDaemon
GradleWorkerMain
KotlinCompileDaemon'

_hbjvm_no_preexisting_overlap() {
    # $1 = simulated cmdline; fails (echoes the offending token) if it
    # contains ANY pre-existing token as a literal substring.
    _cmdline="$1"
    printf '%s\n' "$PRE_EXISTING_TOKENS" | while IFS= read -r _tok; do
        [ -n "$_tok" ] || continue
        case "$_cmdline" in
            *"$_tok"*) printf '%s\n' "$_tok"; return 1 ;;
        esac
    done
    return 0
}

for _pair in "CMD_SCALA:ScalaCompileDaemon" "CMD_GROOVY:GroovyCompileDaemon" "CMD_KOTLIN:kotlin-compiler-embeddable"; do
    _cvar=${_pair%%:*}; _tokname=${_pair##*:}
    eval "_cval=\$$_cvar"
    _overlap=$(_hbjvm_no_preexisting_overlap "$_cval")
    if [ -n "$_overlap" ]; then
        echo "FATAL: simulated cmdline for '$_tokname' unexpectedly ALSO contains the pre-existing token '$_overlap' -- cannot honestly isolate this token's coverage gap (§11.4.6)" >&2
        exit 96
    fi
done

run_iteration() {
    _iter="$1"
    _norm="$EV/normalized_iter${_iter}.txt"
    : > "$_norm"

    if [ "$RED_MODE" = "1" ]; then
        # Both seams are stubbed exactly as in GREEN, so the fake matched PID is a
        # LIVE readable build. Without the stubs the PID is a vanished one, which
        # the guard skips since c3cd967 (§11.4.201), and rc=0 would come from the
        # liveness skip, not from the pattern: a blind RED (measured 2026-11-04,
        # rc=0 with the FIXED pattern). The control below proves the path is
        # not blind: the same stubbed path with the CURRENT pattern must REFUSE.
        for _pair in "CMD_SCALA:ScalaCompileDaemon" "CMD_GROOVY:GroovyCompileDaemon" "CMD_KOTLIN:kotlin-compiler-embeddable"; do
            _cvar=${_pair%%:*}; _tokname=${_pair##*:}
            eval "_cval=\$$_cvar"
            for _which in prefix control; do
                if [ "$_which" = prefix ]; then _pat="$HEAD_PATTERN"; else _pat="$CUR_PATTERN"; fi
                _out=$(PATH="$FAKEBIN:$PATH" GUARD_FILE="$GUARD_FILE" \
                    MT_HOST_BUDGET_BUILD_PGREP_PATTERN="$_pat" \
                    SIM_LIVE_PROC_CMDLINE="$_cval" \
                    sh -c '. "$GUARD_FILE"
                           _mt_host_budget_pid_cmdline() { printf %s "${SIM_LIVE_PROC_CMDLINE:-}"; }
                           _mt_host_budget_pid_alive() { return 0; }
                           mt_host_budget_can_spawn 0; echo "RC=$?"')
                _rc=$(printf '%s\n' "$_out" | sed -n 's/^RC=//p')
                if [ "$_which" = prefix ]; then
                    if [ "$_rc" = "0" ]; then
                        pass "RED($_tokname): pre-fix pattern (genuinely omits this token) wrongly ALLOWS (rc=0) while a live $_tokname process is alive -- the coverage gap, reproduced" "$EV"
                        echo "RED_${_tokname}=gap_reproduced rc=$_rc" >> "$_norm"
                    else
                        fail "RED($_tokname): expected rc=0 (ALLOW, the gap) on the pre-fix pattern, got rc=$_rc" "$EV"
                        echo "RED_${_tokname}=UNEXPECTED rc=$_rc" >> "$_norm"
                    fi
                else
                    if [ "$_rc" = "2" ]; then
                        pass "RED-control($_tokname): the same stubbed path with the CURRENT pattern REFUSES (rc=2) -- the RED is not blind" "$EV"
                        echo "REDCTL_${_tokname}=refused rc=$_rc" >> "$_norm"
                    else
                        fail "RED-control($_tokname): expected rc=2 with the CURRENT pattern on the same path, got rc=$_rc -- the RED is blind (§11.4.115)" "$EV"
                        echo "REDCTL_${_tokname}=UNEXPECTED rc=$_rc" >> "$_norm"
                    fi
                fi
            done
        done
        return 0
    fi

    # =========================================================== GREEN =====
    for _pair in "CMD_GRADLE_LAUNCHER:gradle-launcher" "CMD_SCALA:ScalaCompileDaemon" "CMD_GROOVY:GroovyCompileDaemon" "CMD_KOTLIN:kotlin-compiler-embeddable"; do
        _cvar=${_pair%%:*}; _tokname=${_pair##*:}
        eval "_cval=\$$_cvar"
        _out=$(PATH="$FAKEBIN:$PATH" GUARD_FILE="$GUARD_FILE" \
            SIM_LIVE_PROC_CMDLINE="$_cval" \
            sh -c '. "$GUARD_FILE"
                   # §11.4.120 reconciliation for the §11.4.201 liveness fix: the
                   # matched PID (fake 77777) is a LIVE process whose cmdline is the
                   # simulated token cmdline. Stub BOTH seams so the guard evaluates
                   # it as a live, readable, NON-EXCLUDED survivor (a genuine build)
                   # -- NOT via the now-removed empty-cmdline-conservative-REFUSE
                   # side effect (a fake dead PID with an empty /proc cmdline is now
                   # correctly SKIPPED, so the detection MUST come from a live
                   # readable matching cmdline).
                   _mt_host_budget_pid_cmdline() { printf %s "${SIM_LIVE_PROC_CMDLINE:-}"; }
                   _mt_host_budget_pid_alive() { return 0; }
                   mt_host_budget_can_spawn 0; echo "RC=$?"')
        _rc=$(printf '%s\n' "$_out" | sed -n 's/^RC=//p')
        if [ "$_rc" = "2" ]; then
            pass "GREEN($_tokname): CURRENT pattern REFUSES (rc=2, build-guard cause isolated) while a $_tokname process is alive" "$EV"
            echo "GREEN_${_tokname}=detected rc=$_rc" >> "$_norm"
        else
            fail "GREEN($_tokname): expected rc=2 (REFUSE) with a $_tokname process alive, got rc=$_rc" "$EV"
            echo "GREEN_${_tokname}=UNEXPECTED rc=$_rc" >> "$_norm"
        fi
    done

    # negative control: no simulated process at all -> ALLOW (no false-positive).
    _negout=$(PATH="$FAKEBIN:$PATH" GUARD_FILE="$GUARD_FILE" \
        sh -c '. "$GUARD_FILE"; mt_host_budget_can_spawn 0; echo "RC=$?"')
    _negrc=$(printf '%s\n' "$_negout" | sed -n 's/^RC=//p')
    if [ "$_negrc" = "0" ]; then
        pass "GREEN(negative-control): no simulated process alive -> ALLOW (rc=0, no false-positive)" "$EV"
        echo "GREEN_negctl=allow rc=$_negrc" >> "$_norm"
    else
        fail "GREEN(negative-control): expected rc=0 (ALLOW) with nothing simulated alive, got rc=$_negrc" "$EV"
        echo "GREEN_negctl=UNEXPECTED rc=$_negrc" >> "$_norm"
    fi
}

for _i in 1 2 3; do run_iteration "$_i"; done

echo "=== §11.4.50 determinism check: normalized_iter1/2/3 byte-identical? ===" | tee -a "$EV/results.log"
if diff -q "$EV/normalized_iter1.txt" "$EV/normalized_iter2.txt" >/dev/null 2>&1 \
   && diff -q "$EV/normalized_iter2.txt" "$EV/normalized_iter3.txt" >/dev/null 2>&1; then
    pass "determinism: 3/3 iterations byte-identical (normalized, RED_MODE=$RED_MODE)" "$EV/normalized_iter1.txt"
else
    fail "determinism: iterations diverged (RED_MODE=$RED_MODE)" "$EV"
fi

echo "" | tee -a "$EV/results.log"
echo "RED_MODE=$RED_MODE  PASS=$PASS FAIL=$FAIL SKIP=$SKIP" | tee -a "$EV/results.log"
echo "Evidence: $EV"

[ "$FAIL" -eq 0 ]
