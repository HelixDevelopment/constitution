#!/usr/bin/env bash
# =============================================================================
# multitrack_checkout_owner_lock.sh — §11.4.119 SINGLE-RESOURCE-OWNER lock for a
#                                     TRACK CHECKOUT (the third resource class).
# -----------------------------------------------------------------------------
# Purpose:
#   Guarantee that AT MOST ONE writing agent owns a given track checkout (git
#   worktree / working directory) at a time, ACROSS EVERY launch path — the
#   headless per-track supervisor, the interactive toolkit-alias/cwd-hook
#   session, an operator shell, or any future launcher.
#
#   The project already had exactly-once locks for the OTHER two resource
#   classes — `multitrack_claim.sh` (§11.4.176-A work ITEM) and
#   `multitrack_device_lock.sh` (§11.4.119 DEVICE) — but NOT for the CHECKOUT.
#   The supervisor's private `flock` guarded only its own launch path, so a
#   second agent arriving by a DIFFERENT path (the cwd-hook) shared one git
#   index/worktree with it (two writers => lost work / torn commit, §9.2).
#
# Forensic anchor (FACT, captured 2026-07-22, the-factory):
#   `fuser qa-results/multitrack/logs/track3.lock` listed ONLY the supervisor
#   and its descendants; the tmux/cwd-hook worker in the SAME checkout
#   (/mnt/track3/<project>-t3) held NO fd on it. Two live `claude` writers,
#   one checkout, zero shared lock. Same on track4.
#   Full diagnosis: docs/research/multitrack_duplicate_supervisors_20260722/
#                   DIAGNOSIS.md
#
# §11.4.111 RESOLVE-BY-STABLE-NAME (load-bearing):
#   The lock is keyed on the CANONICAL REAL PATH of the checkout, not on the
#   caller-supplied string and not on a track ORDINAL. On this host
#   `/mnt/track3/<project>` is a SYMLINK to `/mnt/track3/<project>-t3`; the
#   supervisor is launched with the former and the cwd-hook resolves to the
#   latter. A key derived from the raw string would mint TWO locks for ONE
#   checkout and refuse nothing — which is exactly the bug. `readlink -f`
#   collapses every alias onto one key. (The pre-existing supervisor lock was
#   keyed on the TRACK NUMBER, which is an ordinal — §11.4.111 forbids it.)
#
# §11.4.180 PROVABLY-STALE REAP (load-bearing):
#   The kernel releases a `flock` on holder death, so the LOCK itself never goes
#   stale. The holder METADATA file can, so `check` treats a recorded holder
#   whose PID is DEAD (`kill -0` fails) as STALE and reports the checkout FREE.
#   A LIVE holder is NEVER stolen, NEVER force-removed — liveness is PROVEN via
#   `kill -0`, never assumed (§11.4.6).
#
# §11.4.201 GUARD ASSERTS THE REAL CONDITION:
#   `check` reports BUSY only when the real `flock` cannot be taken. It never
#   infers ownership from a substring/process-name match (the §11.4.196(D) /
#   §12.12 carrier footgun that made a bare `pgrep` guard refuse every spawn).
#   Every refusal prints its resolved evidence (holder pid + label + realpath).
#
# Usage:
#   multitrack_checkout_owner_lock.sh lockfile <checkout>
#   multitrack_checkout_owner_lock.sh check    <checkout>
#   multitrack_checkout_owner_lock.sh run      <checkout> <owner-label> -- <cmd...>
#   multitrack_checkout_owner_lock.sh reap     <checkout>
#   multitrack_checkout_owner_lock.sh selfcheck
#   multitrack_checkout_owner_lock.sh -h|--help
#
# Inputs (env):
#   MT_CHECKOUT_LOCK_DIR   Lock directory (default:
#                          ${XDG_RUNTIME_DIR:-/tmp}/multitrack_checkout_locks).
#                          Overridable for testability ONLY.
#
# Outputs / exit codes:
#   lockfile -> stdout: absolute lock path.                       exit 0
#   check    -> stdout: "FREE <realpath>"                          exit 0
#                       "BUSY <realpath> pid=<p> label=<l> since=<t>"  exit 3
#   run      -> runs <cmd...> holding the lock.  exit = cmd's exit
#                       refused (another live owner)                exit 3
#   reap     -> stdout: "REAPED <realpath> dead_pid=<p>" | "KEPT ..."  exit 0
#   selfcheck-> golden-good / golden-bad / negative-control oracle.  exit 0|1
#   usage error                                                     exit 2
#
# Side-effects: creates/updates the lock file + its `.holder` sidecar. NEVER
#   removes a lock held by a LIVE process. NEVER touches the checkout itself.
#
# Dependencies: bash, flock (util-linux), readlink, sha256sum (coreutils).
#
# Cross-references:
#   scripts/multitrack/multitrack_claim.sh        (§11.4.176-A work-ITEM claim)
#   scripts/multitrack/multitrack_device_lock.sh  (§11.4.119 DEVICE lock)
#   qa-results/multitrack/track_dev_supervisor.sh (consumer: supervisor path)
#   constitution/scripts/multitrack/multitrack_cwd_hook.sh (consumer: alias path)
#   docs/research/multitrack_duplicate_supervisors_20260722/DIAGNOSIS.md
#
# §11.4.177 PROMOTION CANDIDATE: this file carries NO project literal (no
#   /mnt/trackN, no device serial, no package name) and is a generic multi-track
#   mechanism. It is a promotion candidate for
#   constitution/scripts/multitrack/. Landing it project-side first avoids a
#   cross-repo submodule push while three supervisors are live; the promotion is
#   a tracked follow-up, NOT a silent omission (§11.4.6).
#
# Constitution: §11.4.119 §11.4.111 §11.4.180 §11.4.201 §11.4.6 §11.4.67
#               §11.4.176 §11.4.178 §11.4.187 §9.2 §12.12
# =============================================================================
set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
MCOL_LOCK_DIR="${MT_CHECKOUT_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/multitrack_checkout_locks}"

# ATM-841: absolute self-path, resolved ONCE. Re-invoking via "$0" is a
# §11.4.201(1) FAIL-bluff generator: under bare-name invocation
# (`bash multitrack_checkout_owner_lock.sh selfcheck` with the dir NOT on
# PATH) "$0" carries no slash, the re-invocation does a PATH lookup, gets
# `command not found`, and the selfcheck reports golden-good FAIL +
# negative-control FAIL + reap-live FAIL against a COMPLETELY HEALTHY tool
# (and leaks a `.holder` into the cwd because the empty lockfile path
# degenerates to ".holder"). Captured RED:
# docs/research/multitrack_fixes/evidence/ATM-841_RED_selfcheck_barename.log
# (consumer-side path; §11.4.35). Every self-reinvocation below goes through
# `bash "$MCOL_SELF"` — location-independent AND exec-bit-independent.
MCOL_SELF="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"

_mcol_usage() {
    sed -n '/^# Usage:/,/^#   multitrack_checkout_owner_lock.sh -h/p' "$MCOL_SELF" | sed 's/^# \{0,1\}//'
}

# --- §11.4.111: canonical, alias-collapsing key -------------------------------
# readlink -f resolves EVERY symlink component, so /mnt/trackN/<project> and
# /mnt/trackN/<project>-tN produce the SAME realpath => the SAME lock.
# MUTATION TARGET (§1.1): dropping the canonicalisation here makes the two
# aliases mint two locks and the golden-bad selfcheck case FAILS.
_mcol_realpath() {
    local p="${1:-}"
    [ -n "$p" ] || return 2
    readlink -f -- "$p" 2>/dev/null || return 3
}

_mcol_key() {
    local rp
    rp="$(_mcol_realpath "${1:-}")" || return $?
    [ -n "$rp" ] || return 3
    printf '%s' "$rp" | sha256sum | cut -c1-32
}

_mcol_lockfile() {
    local key
    key="$(_mcol_key "${1:-}")" || return $?
    mkdir -p "$MCOL_LOCK_DIR" 2>/dev/null || return 1
    printf '%s/checkout-%s.lock\n' "$MCOL_LOCK_DIR" "$key"
}

# --- §11.4.180: holder metadata, provably-stale only --------------------------
_mcol_holder_file() { printf '%s.holder\n' "$1"; }

_mcol_write_holder() {
    local lf="$1" label="$2" rp="$3" hf
    hf="$(_mcol_holder_file "$lf")"
    # write-temp-then-rename => a reader never sees a torn holder record
    printf 'pid=%s\nlabel=%s\nrealpath=%s\nsince=%s\n' \
        "$$" "$label" "$rp" "$(date -u +%FT%TZ)" > "$hf.tmp.$$" 2>/dev/null || return 0
    mv -f "$hf.tmp.$$" "$hf" 2>/dev/null || rm -f "$hf.tmp.$$" 2>/dev/null
    return 0
}

_mcol_read_holder_field() {
    local hf="$1" field="$2"
    [ -f "$hf" ] || return 1
    sed -n "s/^${field}=//p" "$hf" 2>/dev/null | head -1
}

# PROVES liveness; NEVER assumes (§11.4.6). A dead recorded holder is stale
# metadata only — the kernel already released the flock itself.
#
# §11.4.201 FALSE-DEAD IS THE DANGEROUS DIRECTION: reading a LIVE holder as dead
# would REAP a live owner's record — the exact "never steal a live lock"
# violation (§11.4.180). `kill -0` alone is NOT a liveness oracle: for a process
# owned by ANOTHER user it fails with EPERM (exists but not signallable) and is
# indistinguishable from ESRCH (does not exist). This guard's own selfcheck
# CAUGHT that (reap-live FAILed on pid 2 / kthreadd) — the golden-fixture pair
# working as designed. `/proc/<pid>` existence is ownership-independent on
# Linux, so it is the primary probe; `kill -0` remains the portable fallback.
_mcol_holder_alive() {
    local pid="${1:-}"
    [ -n "$pid" ] || return 1
    case "$pid" in (*[!0-9]*) return 1 ;; esac
    [ -d "/proc/$pid" ] && return 0
    # Non-Linux / no procfs: fall back. EPERM still counts as ALIVE (treating an
    # unsignallable-but-existing process as dead is the unsafe direction).
    if kill -0 "$pid" 2>/dev/null; then return 0; fi
    [ "$(kill -0 "$pid" 2>&1 | grep -c 'ermitted')" -gt 0 ] && return 0
    return 1
}

# --- verbs --------------------------------------------------------------------
_mcol_cmd_lockfile() {
    local lf
    lf="$(_mcol_lockfile "${1:-}")" || { echo "usage: lockfile <checkout>" >&2; return 2; }
    printf '%s\n' "$lf"
}

# check: NON-BLOCKING ownership probe. Safe to call from a shell startup hook
# (never blocks, never writes holder metadata). HONEST BOUNDARY (§11.4.6): at
# the flock layer the probe is NOT purely passive — `flock -n <lf> true`
# transiently ACQUIRES the exclusive lock for the fork+exec window of `true`.
# That is why `run` acquires with a bounded wait (see _mcol_cmd_run): a real
# owner must never be refused because its acquire landed inside a probe window.
_mcol_cmd_check() {
    local co="${1:-}" lf rp hf pid label since
    [ -n "$co" ] || { echo "usage: check <checkout>" >&2; return 2; }
    rp="$(_mcol_realpath "$co")" || { echo "usage: check <checkout> (unresolvable path)" >&2; return 2; }
    lf="$(_mcol_lockfile "$co")" || return 2
    hf="$(_mcol_holder_file "$lf")"
    # The REAL condition (§11.4.201): can the advisory lock be taken right now?
    if flock -n "$lf" true 2>/dev/null; then
        printf 'FREE %s\n' "$rp"
        return 0
    fi
    pid="$(_mcol_read_holder_field "$hf" pid)"
    label="$(_mcol_read_holder_field "$hf" label)"
    since="$(_mcol_read_holder_field "$hf" since)"
    # A held flock with DEAD recorded metadata cannot happen (kernel releases on
    # death) — but if the metadata is missing, say so honestly, never invent it.
    printf 'BUSY %s pid=%s label=%s since=%s\n' \
        "$rp" "${pid:-UNKNOWN}" "${label:-UNKNOWN}" "${since:-UNKNOWN}"
    return 3
}

# run: acquire with a BOUNDED wait (≤2s), then exec the command under the lock.
#
# WHY bounded-wait and not single-shot `-n` (root cause, captured 2026-07-23 —
# docs/research/multitrack_fixes/evidence/ATM-833_probe_race_stress.log,
# consumer-side path per §11.4.35): `check` probes ownership via
# `flock -n <lf> true`, which transiently ACQUIRES the exclusive flock for the
# fork+exec window of `true`. A REAL would-be owner whose single-shot
# `flock -n` landed inside that window was PERMANENTLY refused — and the
# refusal quoted the STALE .holder metadata (a dead pid) as its "owner",
# because the momentary probe holder writes no holder record. Measured: 2/30
# stress iterations + 1/3 full-suite runs hit the race. That is a
# §11.4.201(1) FALSE-POSITIVE REFUSAL: a probe must never cost a real owner
# its acquisition. Probe hold-windows are microseconds-to-milliseconds; a
# REAL owner holds for the whole supervisor/session lifetime — so a 2s
# bounded wait absorbs every probe collision while a genuine live owner
# still produces the refusal (within the bound). MUTATION TARGET (§1.1):
# reverting `-w 2` to `-n` makes the transient-holder case in
# test_multitrack_owner_lock_probe_race.sh FAIL deterministically.
_mcol_cmd_run() {
    local co="${1:-}" label="${2:-}"
    shift 2 2>/dev/null || { echo "usage: run <checkout> <owner-label> -- <cmd...>" >&2; return 2; }
    [ "${1:-}" = "--" ] || { echo "usage: run <checkout> <owner-label> -- <cmd...>" >&2; return 2; }
    shift
    [ $# -ge 1 ] || { echo "usage: run <checkout> <owner-label> -- <cmd...>" >&2; return 2; }
    [ -n "$co" ] && [ -n "$label" ] || { echo "usage: run <checkout> <owner-label> -- <cmd...>" >&2; return 2; }
    local lf rp
    rp="$(_mcol_realpath "$co")" || { echo "run: unresolvable checkout '$co'" >&2; return 2; }
    lf="$(_mcol_lockfile "$co")" || return 2
    exec 8>"$lf" || return 1
    if ! flock -w 2 8; then
        # §11.4.201: refusal prints its RESOLVED evidence, never a bare "busy".
        local hf pid plabel
        hf="$(_mcol_holder_file "$lf")"
        pid="$(_mcol_read_holder_field "$hf" pid)"
        plabel="$(_mcol_read_holder_field "$hf" label)"
        echo "REFUSED: checkout '$rp' is already owned (pid=${pid:-UNKNOWN} label=${plabel:-UNKNOWN}); §11.4.119 single-resource-owner" >&2
        exec 8>&-
        return 3
    fi
    _mcol_write_holder "$lf" "$label" "$rp"
    "$@"
    local rc=$?
    exec 8>&-
    return $rc
}

# reap: drop PROVABLY-stale holder metadata only. NEVER removes a live holder's
# record and NEVER force-releases a live flock (§11.4.180 / §9.2).
_mcol_cmd_reap() {
    local co="${1:-}" lf rp hf pid
    [ -n "$co" ] || { echo "usage: reap <checkout>" >&2; return 2; }
    rp="$(_mcol_realpath "$co")" || { echo "usage: reap <checkout> (unresolvable path)" >&2; return 2; }
    lf="$(_mcol_lockfile "$co")" || return 2
    hf="$(_mcol_holder_file "$lf")"
    pid="$(_mcol_read_holder_field "$hf" pid)"
    if [ -z "$pid" ]; then
        printf 'KEPT %s (no holder record)\n' "$rp"
        return 0
    fi
    if _mcol_holder_alive "$pid"; then
        printf 'KEPT %s live_pid=%s (never steal a live lock, §11.4.180)\n' "$rp" "$pid"
        return 0
    fi
    rm -f "$hf" 2>/dev/null
    printf 'REAPED %s dead_pid=%s\n' "$rp" "$pid"
    return 0
}

# selfcheck (§11.4.107(10)): golden-good MUST pass, golden-bad MUST be refused,
# negative-control MUST NOT be refused (the false-positive guard). A guard that
# passes its golden-bad — or refuses its negative-control — is itself the defect.
_mcol_cmd_selfcheck() {
    local tmp rc=0
    tmp="$(mktemp -d)" || return 1
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN
    export MT_CHECKOUT_LOCK_DIR="$tmp/locks"
    mkdir -p "$tmp/real_a" "$tmp/real_b"
    ln -s "$tmp/real_a" "$tmp/alias_a"

    # GOLDEN-GOOD: a free checkout is acquirable.
    if bash "$MCOL_SELF" run "$tmp/real_a" gg -- true >/dev/null 2>&1; then
        echo "selfcheck golden-good: PASS (free checkout acquired)"
    else
        echo "selfcheck golden-good: FAIL (free checkout refused)"; rc=1
    fi

    # GOLDEN-BAD: a SECOND owner arriving via the SYMLINK ALIAS of the SAME
    # checkout MUST be refused. This is the exact production shape
    # (/mnt/trackN/<project> -> <project>-tN) and the reason the key must be
    # canonicalised (§11.4.111).
    if bash "$MCOL_SELF" run "$tmp/real_a" outer -- bash "$MCOL_SELF" run "$tmp/alias_a" inner -- true >/dev/null 2>&1; then
        echo "selfcheck golden-bad: FAIL (alias-path second owner was ALLOWED — guard is not load-bearing)"; rc=1
    else
        echo "selfcheck golden-bad: PASS (alias-path second owner refused)"
    fi

    # NEGATIVE-CONTROL: two GENUINELY DIFFERENT checkouts must BOTH succeed.
    # Without this, a guard that refuses everything would look 'correct'
    # (§11.4.201(1) false-positive refusal is a FAIL-bluff).
    if bash "$MCOL_SELF" run "$tmp/real_a" outer -- bash "$MCOL_SELF" run "$tmp/real_b" other -- true >/dev/null 2>&1; then
        echo "selfcheck negative-control: PASS (distinct checkouts both acquired)"
    else
        echo "selfcheck negative-control: FAIL (distinct checkout wrongly refused — false positive)"; rc=1
    fi

    # STALE-REAP: a DEAD recorded holder is reaped; a LIVE one is KEPT.
    local lf hf
    lf="$(bash "$MCOL_SELF" lockfile "$tmp/real_b")"
    hf="${lf}.holder"
    printf 'pid=2\nlabel=dead\nrealpath=%s\nsince=x\n' "$tmp/real_b" > "$hf"
    # PID 2 (kthreadd) is alive on Linux -> MUST be KEPT. Use an impossible pid
    # for the dead case instead of guessing an unused one (§11.4.6).
    case "$(bash "$MCOL_SELF" reap "$tmp/real_b")" in
        KEPT*live_pid=2*) echo "selfcheck reap-live: PASS (live holder never stolen)" ;;
        *) echo "selfcheck reap-live: FAIL (live holder record removed)"; rc=1 ;;
    esac
    local deadpid
    deadpid="$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) - 1 ))"
    printf 'pid=%s\nlabel=dead\nrealpath=%s\nsince=x\n' "$deadpid" "$tmp/real_b" > "$hf"
    if _mcol_holder_alive "$deadpid"; then
        echo "selfcheck reap-dead: SKIP (chosen pid unexpectedly alive — not guessed, reported)"
    else
        case "$(bash "$MCOL_SELF" reap "$tmp/real_b")" in
            REAPED*) echo "selfcheck reap-dead: PASS (dead holder record reaped)" ;;
            *) echo "selfcheck reap-dead: FAIL (dead holder record not reaped)"; rc=1 ;;
        esac
    fi

    [ "$rc" -eq 0 ] && echo "selfcheck: ALL PASS" || echo "selfcheck: FAILURES PRESENT"
    return $rc
}

main() {
    local verb="${1:-}"
    [ $# -ge 1 ] && shift
    case "$verb" in
        lockfile)  _mcol_cmd_lockfile "$@" ;;
        check)     _mcol_cmd_check "$@" ;;
        run)       _mcol_cmd_run "$@" ;;
        reap)      _mcol_cmd_reap "$@" ;;
        selfcheck) _mcol_cmd_selfcheck ;;
        -h|--help|help) _mcol_usage ;;
        *) _mcol_usage >&2; return 2 ;;
    esac
}

main "$@"
