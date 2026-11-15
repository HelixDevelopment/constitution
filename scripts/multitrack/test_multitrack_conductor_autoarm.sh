#!/bin/sh
# =============================================================================
# test_multitrack_conductor_autoarm.sh
#     — conductor fallback-monitor auto-arm helper: resolves alias/track/
#       transcript, arms ONE monitor, is IDEMPOTENT (no double-start), and is
#       GRACEFUL (non-silent NOTE) when no transcript exists yet.
#       (§11.4.187 out-of-the-box conductor auto-arm; §11.4.6 never-silent.)
# -----------------------------------------------------------------------------
# Purpose:
#   Hermetic unit/integration test of multitrack_conductor_monitor_autoarm.sh.
#   Uses a STUB fallback-monitor (a long-lived sleeper named exactly
#   `multitrack_fallback_monitor.sh` so the helper's pgrep idempotency guard
#   matches it) + an isolated fake CLAUDE_CONFIG_DIR / projects transcript dir —
#   NO real daemon, NO live registry, NO network (§11.4.98). Unique per-run alias
#   nonce so the pgrep/pkill patterns can never collide with another run
#   (§12.12 self-kill safety).
#
#   Asserts:
#     (A) RESOLVE+START — with a transcript present, the helper emits STARTED with
#         the derived alias + track + transcript, and launches the (stub) monitor
#         exactly ONCE with `--daemon --alias <a> --track <t> --transcript <p>`.
#     (B) IDEMPOTENT — a 2nd call while the monitor is live emits ALREADY and does
#         NOT launch a 2nd monitor (stub invocation count stays 1).
#     (C) GRACEFUL-ABSENT — with no *.jsonl transcript, the helper emits a NOTE
#         (never a silent no-op, §11.4.6) and launches nothing.
#     (D) TRACK-DERIVATION — a project dir under /mnt/track<N> derives track-<N>;
#         any other path derives track-1 (the conductor default).
#
# Usage:  sh test_multitrack_conductor_autoarm.sh
# Exit:   0 = all assertions pass; 1 = FAIL; 2 = harness setup error.
# Evidence: qa-results/multitrack_native_first_resume/<UTC-ts>/autoarm/  (captured
#           helper stdout + stub invocation log per scenario).
# Deps: POSIX sh, pgrep, mkdir, date, tr.
# Cross-refs: multitrack_conductor_monitor_autoarm.sh · multitrack_cwd_hook.sh
#   (_cwh_monitor_async — the track-worker analogue) · §11.4.187 / §11.4.6.
# =============================================================================

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
_self="$0"
case "$_self" in */*) _dir=${_self%/*} ;; *) _dir=. ;; esac
_dir=$(cd "$_dir" 2>/dev/null && pwd)
[ -n "$_dir" ] || { echo "FATAL: cannot resolve self dir" >&2; exit 2; }

HELPER="$_dir/multitrack_conductor_monitor_autoarm.sh"
[ -r "$HELPER" ] || { echo "FATAL: helper not found at $HELPER" >&2; exit 2; }

ROOT=$(cd "$_dir/../../.." 2>/dev/null && pwd)
[ -n "$ROOT" ] || ROOT=$(cd "$_dir" && git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT="$_dir"

TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%SZ)
EVDIR="$ROOT/qa-results/multitrack_native_first_resume/$TS/autoarm"
mkdir -p "$EVDIR" 2>/dev/null || { echo "FATAL: cannot create $EVDIR" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/caa.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }

ALIAS_NONCE="claudeTEST$$"
STUB_TAG="multitrack_fallback_monitor.sh --daemon --alias $ALIAS_NONCE"
cleanup() { pkill -f "$STUB_TAG" 2>/dev/null || true; rm -rf "$WORK" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# --- stub monitor (long-lived sleeper; records each invocation) --------------
STUBDIR="$WORK/stub"; mkdir -p "$STUBDIR"
STUB="$STUBDIR/multitrack_fallback_monitor.sh"
STUB_INVLOG="$WORK/stub_invocations.log"; : > "$STUB_INVLOG"
cat > "$STUB" <<STUBEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$STUB_INVLOG"
sleep 30
STUBEOF
chmod +x "$STUB"
export STUB_INVLOG

# --- fake CLAUDE_CONFIG_DIR + transcript -------------------------------------
CCDIR="$WORK/.claude-$ALIAS_NONCE"
PROJDIR_STR="$WORK/proj"                    # not under /mnt/track -> track-1
ENC=$(printf '%s' "$PROJDIR_STR" | tr '/' '-')
TDIR="$CCDIR/projects/$ENC"
mkdir -p "$TDIR"
TRANSCRIPT="$TDIR/session.jsonl"
printf '{"type":"init"}\n' > "$TRANSCRIPT"

FAILS=0
_ok()   { printf 'OK   %s\n' "$*"; }
_bad()  { printf 'FAIL %s\n' "$*"; FAILS=$((FAILS + 1)); }
_count_invocations() { [ -s "$STUB_INVLOG" ] && wc -l < "$STUB_INVLOG" | tr -d ' ' || echo 0; }

# run the helper with our fixtures; capture stdout to $1.
_run() {
    _capfile="$1"
    CLAUDE_CONFIG_DIR="$CCDIR" \
    MT_CONDUCTOR_DIR="${MT_CONDUCTOR_DIR_OVERRIDE:-$PROJDIR_STR}" \
    MT_CONDUCTOR_MONITOR="$STUB" \
    MT_CONDUCTOR_POLL_TRIES=1 MT_CONDUCTOR_POLL_SLEEP=0 \
    MT_CONDUCTOR_LOG="$EVDIR/$(basename "$_capfile" .out).helperlog" \
        sh "$HELPER" > "$_capfile" 2>&1
}

# ---- (A) RESOLVE + START ----------------------------------------------------
_run "$EVDIR/A_start.out"
if grep -q 'STARTED' "$EVDIR/A_start.out" \
   && grep -q "alias=$ALIAS_NONCE" "$EVDIR/A_start.out" \
   && grep -q 'track=track-1' "$EVDIR/A_start.out" \
   && grep -q "transcript=$TRANSCRIPT" "$EVDIR/A_start.out"; then
    _ok "(A) STARTED with derived alias=$ALIAS_NONCE track=track-1 transcript=$TRANSCRIPT"
else
    _bad "(A) helper did not emit STARTED with the expected alias/track/transcript (see A_start.out)"
fi
# give the stub a moment to record its invocation
_wait=0; while [ "$_wait" -lt 20 ]; do [ -s "$STUB_INVLOG" ] && break; _wait=$((_wait+1)); sleep 0.1 2>/dev/null || sleep 1; done
_n1=$(_count_invocations)
if [ "$_n1" = "1" ] && grep -q -- "--daemon --alias $ALIAS_NONCE --track track-1 --transcript $TRANSCRIPT" "$STUB_INVLOG"; then
    _ok "(A) monitor launched exactly once with correct daemon args"
else
    _bad "(A) expected 1 correct monitor launch; invocation-count=$_n1 (see $STUB_INVLOG)"
fi

# ---- (B) IDEMPOTENT (2nd call while monitor live) ---------------------------
_run "$EVDIR/B_idempotent.out"
if grep -q 'ALREADY' "$EVDIR/B_idempotent.out"; then
    _ok "(B) 2nd call emitted ALREADY (idempotent)"
else
    _bad "(B) 2nd call did not emit ALREADY (see B_idempotent.out)"
fi
_n2=$(_count_invocations)
if [ "$_n2" = "1" ]; then
    _ok "(B) no 2nd monitor started (invocation-count still 1)"
else
    _bad "(B) idempotency violated — invocation-count=$_n2 after 2nd call"
fi

# ---- (C) GRACEFUL-ABSENT (no transcript) ------------------------------------
# fresh alias/config so the (A) live stub does NOT satisfy the pgrep guard.
ALIAS_NONCE2="claudeABSENT$$"
CCDIR2="$WORK/.claude-$ALIAS_NONCE2"
PROJDIR_STR2="$WORK/proj2"
ENC2=$(printf '%s' "$PROJDIR_STR2" | tr '/' '-')
mkdir -p "$CCDIR2/projects/$ENC2"          # dir exists, but NO *.jsonl
_before=$(_count_invocations)
CLAUDE_CONFIG_DIR="$CCDIR2" MT_CONDUCTOR_DIR="$PROJDIR_STR2" \
    MT_CONDUCTOR_MONITOR="$STUB" MT_CONDUCTOR_POLL_TRIES=1 MT_CONDUCTOR_POLL_SLEEP=0 \
    MT_CONDUCTOR_LOG="$EVDIR/C_absent.helperlog" \
    sh "$HELPER" > "$EVDIR/C_absent.out" 2>&1
if grep -q 'NOTE' "$EVDIR/C_absent.out" && grep -q 'no transcript yet' "$EVDIR/C_absent.out"; then
    _ok "(C) no-transcript path emitted a non-silent NOTE (never a silent no-op)"
else
    _bad "(C) no-transcript path did not emit the expected NOTE (see C_absent.out)"
fi
_after=$(_count_invocations)
if [ "$_before" = "$_after" ]; then
    _ok "(C) nothing launched on the graceful-absent path"
else
    _bad "(C) a monitor was launched despite no transcript ($_before -> $_after)"
fi

# ---- (D) TRACK DERIVATION ---------------------------------------------------
# /mnt/track3/... -> track-3 (surface via the graceful-absent NOTE which names
# the derived track); any other path -> track-1.
CLAUDE_CONFIG_DIR="$WORK/.claude-claudeDRV$$" MT_CONDUCTOR_DIR="/mnt/track3/whatever" \
    MT_CONDUCTOR_MONITOR="$STUB" MT_CONDUCTOR_POLL_TRIES=1 MT_CONDUCTOR_POLL_SLEEP=0 \
    MT_CONDUCTOR_LOG="$EVDIR/D_track3.helperlog" \
    sh "$HELPER" > "$EVDIR/D_track3.out" 2>&1
if grep -q 'track=track-3' "$EVDIR/D_track3.out"; then
    _ok "(D) /mnt/track3 -> track-3 derived"
else
    _bad "(D) /mnt/track3 did not derive track-3 (see D_track3.out)"
fi
CLAUDE_CONFIG_DIR="$WORK/.claude-claudeDRV2$$" MT_CONDUCTOR_DIR="/home/x/proj" \
    MT_CONDUCTOR_MONITOR="$STUB" MT_CONDUCTOR_POLL_TRIES=1 MT_CONDUCTOR_POLL_SLEEP=0 \
    MT_CONDUCTOR_LOG="$EVDIR/D_track1.helperlog" \
    sh "$HELPER" > "$EVDIR/D_track1.out" 2>&1
if grep -q 'track=track-1' "$EVDIR/D_track1.out"; then
    _ok "(D) non-/mnt path -> track-1 default derived"
else
    _bad "(D) non-/mnt path did not derive track-1 (see D_track1.out)"
fi

# --- summary -----------------------------------------------------------------
{
    printf 'test=test_multitrack_conductor_autoarm.sh\n'
    printf 'timestamp=%s\n' "$TS"
    printf 'fails=%s\n' "$FAILS"
    printf 'result=%s\n' "$( [ "$FAILS" -eq 0 ] && echo PASS || echo FAIL )"
} > "$EVDIR/SUMMARY.txt"

printf '\n== conductor auto-arm test : %s == (evidence: %s)\n' \
    "$( [ "$FAILS" -eq 0 ] && echo PASS || echo FAIL )" "$EVDIR"

[ "$FAILS" -eq 0 ]
