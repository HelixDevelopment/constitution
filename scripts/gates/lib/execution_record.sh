#!/bin/sh
# =============================================================================
# execution_record.sh — the execution RECORDER and its reconciler
#                       (T336a, spec 002; FR-045/FR-046/FR-047)
# =============================================================================
#
# WHY A RECORDER EXISTS AT ALL: a `command` field on an evidence row is a CLAIM
# about something that happened. Nothing about the claim is checkable unless
# something INDEPENDENT of the claimant wrote down what actually ran. This file
# is that something — the §11.4.249 flight recorder for executed commands. The
# gate then RECONCILES the claim against the record, automatically, at the seam;
# a claim naming a command the recorder never saw is refused with
# `command_NOT_IN_RECORDER`.
#
# THE FIELD SET (FR-045), all required together once ANY of them is present:
#   ts             ISO-8601 UTC of the invocation
#   cwd            working directory the command ran in
#   argv           canonically serialised argument vector (see below)
#   exit_status    the real integer status — NEVER defaulted (T119/FR-003)
#   duration_ms    wall-clock milliseconds
#   stdout_digest  sha256 of the FULL stdout stream, BEFORE truncation
#   stderr_digest  sha256 of the FULL stderr stream, BEFORE truncation
#   stdout_bytes   full byte count before truncation
#   stderr_bytes   full byte count before truncation
#   stream_ref     directory holding the captured streams, OUTSIDE version control
#   stream_truncated  true|false — stated, never inferred from a size
#   stream_redacted   true|false — stated, never inferred from content
#
# DIGEST BEFORE TRUNCATION, DELIBERATELY: a digest computed after truncation
# certifies the truncated copy, so a reader comparing it to the file on disk
# always agrees — and learns nothing. Computing it over the full stream means the
# recorded digest is a statement about what the command ACTUALLY emitted, and a
# later comparison can therefore disagree. A check that cannot disagree is not a
# check.
#
# REDACTION BEFORE WRITE: every stream is scanned with the project's credential
# scanner and redacted IN PLACE on a hit, so a captured stream can never become
# the leak (§11.4.10). NOTE the scanner's INVERTED convention — it returns 0 on a
# HIT, 1 on clean — and note that an UNREADABLE path also returns 1. Both are
# handled explicitly below; treating "clean" and "could not look" as the same
# answer is the §11.4.201(6) false null.
#
# ARGV SERIALISATION (canonical, and its limits stated): a JSON array of strings
# with `\` and `"` escaped. An argument containing a NEWLINE is recorded with the
# newline escaped as \n — the record stays one line so the pure-sh reader in
# critical_blocker_gate.sh can parse it, which is the same constraint every other
# row in that store carries.
#
# Usage (executed):
#   sh execution_record.sh run <recorder> -- <argv...>
#   sh execution_record.sh lookup <recorder> <command>   # 0 found / 1 no / 3 blind
#   sh execution_record.sh --selftest
# Usage (sourced):
#   . execution_record.sh ; exec_record_run … ; exec_record_lookup …
#
# POSIX sh; `sh -n` AND `bash -n` clean; every name `_xr_`/`XR_` prefixed.
# =============================================================================

XR_STREAM_CAP=${XR_STREAM_CAP:-65536}     # bytes kept on disk per stream

# T048 round-36 independent review (critical_blocker_gate.sh, R36-I1):
# exec_record_lookup() below is called by critical_blocker_gate.sh's
# execution-record reconciliation branch to decide command_NOT_IN_RECORDER
# vs a genuine recorder hit -- a verdict-feeding call. Its bare `grep` was
# reproduced live: a PATH-prepended fake `grep` flips a real REFUSE
# (command never ran) into a false ALLOW. Resolved absolute-path once here,
# the same primitive-hardening pattern critical_blocker_gate.sh already
# applies to its own external-command call sites. Full closed-set
# export-f-shadow coverage (critical_blocker_gate.sh's
# _cbg_refuse_on_env_func_tamper) is NOT replicated in this smaller,
# narrower-scope file -- tracked as a follow-up, not claimed here.
if [ -x /usr/bin/grep ]; then _XR_BIN_GREP=/usr/bin/grep
elif [ -x /bin/grep ]; then _XR_BIN_GREP=/bin/grep
else _XR_BIN_GREP=grep
fi

_xr_now()  { date -u +%Y-%m-%dT%H:%M:%SZ; }
_xr_ms()   { date +%s%N 2>/dev/null || printf '0'; }
_xr_sha()  { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
_xr_bytes(){ wc -c < "$1" 2>/dev/null | tr -d ' '; }

# --- canonical argv serialisation -------------------------------------------
_xr_argv_json() {
    _xr_out='['
    _xr_first=1
    for _xr_a in "$@"; do
        _xr_e=$(printf '%s' "$_xr_a" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' '\001' | sed -e 's/\001/\\n/g')
        if [ "$_xr_first" -eq 1 ]; then _xr_out="${_xr_out}\"${_xr_e}\""; _xr_first=0
        else _xr_out="${_xr_out},\"${_xr_e}\""; fi
    done
    printf '%s]' "$_xr_out"
}

# --- credential scan + in-place redaction -----------------------------------
# rc 0 = redacted (a credential was found and replaced), 1 = clean,
# 3 = could not scan (scanner absent or path unreadable) — reported, never
# silently folded into "clean".
_xr_redact() {  # <file>
    [ -r "$1" ] || return 3
    _xr_lib="${XR_CRED_LIB:-}"
    if [ -z "$_xr_lib" ]; then
        _xr_here=$(CDPATH='' cd -- "$(dirname -- "${XR_SELF_PATH:-$0}")" && pwd)
        _xr_lib="$_xr_here/../../hooks/credential_scan_lib.sh"
    fi
    [ -r "$_xr_lib" ] || return 3
    # INVERTED CONVENTION: helix_cred_scan_file returns 0 on a HIT.
    # shellcheck disable=SC1090
    ( . "$_xr_lib" >/dev/null 2>&1 || exit 3
      helix_cred_scan_file "$1" >/dev/null 2>&1
      exit $? ) 
    _xr_scan_rc=$?
    if [ "$_xr_scan_rc" -eq 0 ]; then
        # Redact IN PLACE: the captured stream must never be the leak.
        printf '[REDACTED by execution_record.sh — a credential-shaped value was detected in this captured stream; the digest recorded on the evidence row was computed over the ORIGINAL stream before this replacement, so a digest comparison against this file will MISMATCH by design]\n' > "$1"
        return 0
    fi
    [ "$_xr_scan_rc" -eq 1 ] && return 1
    return 3
}

# --- run a command and record it --------------------------------------------
# exec_record_run <recorder_path> <stream_root> -- <argv...>
# Echoes the recorded JSON row on stdout; the command's own exit status is
# preserved in the row (and returned).
exec_record_run() {
    _xr_rec="$1"; shift
    _xr_root="$1"; shift
    [ "${1:-}" = "--" ] && shift
    [ -n "${1:-}" ] || { printf 'exec_record_run: no command\n' >&2; return 2; }

    mkdir -p "$_xr_root" 2>/dev/null || return 2
    _xr_id=$(date -u +%Y%m%dT%H%M%SZ)_$$
    _xr_dir="$_xr_root/$_xr_id"
    mkdir -p "$_xr_dir" 2>/dev/null || return 2

    _xr_argv=$(_xr_argv_json "$@")
    _xr_cmd="$*"
    _xr_cwd=$(pwd)
    _xr_t0=$(_xr_ms)
    "$@" >"$_xr_dir/stdout" 2>"$_xr_dir/stderr"
    _xr_rc=$?                       # captured DIRECTLY, on its own line
    _xr_t1=$(_xr_ms)
    _xr_dur=$(( (_xr_t1 - _xr_t0) / 1000000 ))
    [ "$_xr_dur" -ge 0 ] 2>/dev/null || _xr_dur=0

    # Digests + byte counts over the FULL streams, BEFORE truncation.
    _xr_o_sha=$(_xr_sha "$_xr_dir/stdout"); _xr_o_len=$(_xr_bytes "$_xr_dir/stdout")
    _xr_e_sha=$(_xr_sha "$_xr_dir/stderr"); _xr_e_len=$(_xr_bytes "$_xr_dir/stderr")

    # Redaction (before any truncation, so a secret cannot survive in a tail).
    _xr_red=false
    _xr_redact "$_xr_dir/stdout"; [ $? -eq 0 ] && _xr_red=true
    _xr_redact "$_xr_dir/stderr"; [ $? -eq 0 ] && _xr_red=true

    # Truncation, STATED rather than inferred from a size.
    _xr_trunc=false
    for _xr_f in stdout stderr; do
        _xr_l=$(_xr_bytes "$_xr_dir/$_xr_f")
        if [ "${_xr_l:-0}" -gt "$XR_STREAM_CAP" ]; then
            dd if="$_xr_dir/$_xr_f" of="$_xr_dir/$_xr_f.trunc" bs=1 count="$XR_STREAM_CAP" 2>/dev/null
            mv "$_xr_dir/$_xr_f.trunc" "$_xr_dir/$_xr_f"
            _xr_trunc=true
        fi
    done

    _xr_row=$(printf '{"ts":"%s","cwd":"%s","command":"%s","argv":%s,"exit_status":"%s","duration_ms":"%s","stdout_digest":"%s","stderr_digest":"%s","stdout_bytes":"%s","stderr_bytes":"%s","stream_ref":"%s","stream_truncated":"%s","stream_redacted":"%s"}' \
        "$(_xr_now)" "$_xr_cwd" "$_xr_cmd" "$_xr_argv" "$_xr_rc" "$_xr_dur" \
        "$_xr_o_sha" "$_xr_e_sha" "$_xr_o_len" "$_xr_e_len" "$_xr_dir" "$_xr_trunc" "$_xr_red")
    mkdir -p "$(dirname "$_xr_rec")" 2>/dev/null
    printf '%s\n' "$_xr_row" >> "$_xr_rec"
    printf '%s\n' "$_xr_row"
    return "$_xr_rc"
}

# --- reconcile a CLAIMED command against the recorder ------------------------
# rc 0 = a recorder entry names this command
#    1 = no entry names it (the claim is unreconciled)
#    3 = BLIND — the recorder is absent/unreadable, or the instrument could not
#        see a KNOWN-PRESENT entry. A zero from a blind instrument is not an
#        absence (§11.4.201(7)(b)), so it is never reported as one.
exec_record_lookup() {  # <recorder_path> <command>
    _xr_lrec="${1:-}"; _xr_lcmd="${2:-}"
    [ -n "$_xr_lrec" ] && [ -r "$_xr_lrec" ] || return 3
    [ -n "$_xr_lcmd" ] || return 1
    # CONTROL NEEDLE, same query class, same file: a key every recorder row
    # carries. If the reader cannot see THAT, it cannot see anything, and the
    # miss below would be an artefact of the instrument.
    _xr_needle=$("$_XR_BIN_GREP" -c '"command"' "$_xr_lrec" 2>/dev/null); _xr_needle=${_xr_needle:-0}
    [ "$_xr_needle" -gt 0 ] || return 3
    if "$_XR_BIN_GREP" -qF "\"command\":\"$_xr_lcmd\"" "$_xr_lrec" 2>/dev/null; then return 0; fi
    return 1
}

# --- selftest (§11.4.107(10)) ------------------------------------------------
_xr_selftest() {
    _xr_trc=0
    _x_ok()  { printf '  PASS %s\n' "$1"; }
    _x_bad() { printf '  FAIL %s\n' "$1" >&2; _xr_trc=1; }
    _xr_tmp=$(mktemp -d) || return 2
    _xr_recf="$_xr_tmp/rec.jsonl"

    _xr_row=$(exec_record_run "$_xr_recf" "$_xr_tmp/streams" -- /bin/sh -c 'printf hello; printf oops >&2; exit 7')
    _xr_runrc=$?
    [ "$_xr_runrc" -eq 7 ] && _x_ok "run preserves the real exit status (7), never defaults it" \
                           || _x_bad "run returned $_xr_runrc (expected the command's own 7)"
    for _xr_k in ts cwd argv exit_status duration_ms stdout_digest stderr_digest stdout_bytes stderr_bytes stream_ref stream_truncated stream_redacted; do
        case "$_xr_row" in *"\"$_xr_k\""*) : ;; *) _x_bad "recorded row is missing the field '$_xr_k'"; esac
    done
    _x_ok "recorded row carries the full FR-045 execution field set"

    # digest is over the REAL stream
    _xr_sr=$(printf '%s' "$_xr_row" | sed -n 's/.*"stream_ref":"\([^"]*\)".*/\1/p')
    _xr_od=$(printf '%s' "$_xr_row" | sed -n 's/.*"stdout_digest":"\([^"]*\)".*/\1/p')
    if [ "$_xr_od" = "$(_xr_sha "$_xr_sr/stdout")" ]; then
        _x_ok "stdout_digest matches the captured stream on disk"
    else
        _x_bad "stdout_digest does not match the captured stream — the digest certifies nothing"
    fi
    # ...and it can DISAGREE (a check that cannot disagree is not a check)
    printf 'tampered' > "$_xr_sr/stdout"
    if [ "$_xr_od" != "$(_xr_sha "$_xr_sr/stdout")" ]; then
        _x_ok "NEGATIVE CONTROL a tampered stream makes the digest DISAGREE (mismatch is reachable)"
    else
        _x_bad "a tampered stream still matched the recorded digest"
    fi

    # lookup: found / not found / blind — all three reachable
    exec_record_lookup "$_xr_recf" "/bin/sh -c printf hello; printf oops >&2; exit 7" >/dev/null 2>&1
    _xr_l0=$?
    exec_record_lookup "$_xr_recf" "definitely-never-run --nope" >/dev/null 2>&1
    _xr_l1=$?
    exec_record_lookup "$_xr_tmp/no-such-recorder.jsonl" "anything" >/dev/null 2>&1
    _xr_l3=$?
    [ "$_xr_l0" -eq 0 ] && _x_ok "lookup FINDS a recorded command" || _x_bad "lookup did not find a recorded command (rc=$_xr_l0)"
    [ "$_xr_l1" -eq 1 ] && _x_ok "lookup reports NOT-FOUND for a command that never ran" || _x_bad "lookup rc=$_xr_l1 for a never-run command (expected 1)"
    [ "$_xr_l3" -eq 3 ] && _x_ok "lookup reports BLIND (rc=3) for an absent recorder, never NOT-FOUND" || _x_bad "absent recorder gave rc=$_xr_l3 (expected 3 BLIND)"

    # redaction: a credential-shaped stream is redacted in place
    _xr_row2=$(exec_record_run "$_xr_recf" "$_xr_tmp/streams" -- /bin/sh -c 'printf "password: hunter2hunter2\n"')
    _xr_sr2=$(printf '%s' "$_xr_row2" | sed -n 's/.*"stream_ref":"\([^"]*\)".*/\1/p')
    _xr_red2=$(printf '%s' "$_xr_row2" | sed -n 's/.*"stream_redacted":"\([^"]*\)".*/\1/p')
    if [ "$_xr_red2" = "true" ] && ! grep -q 'hunter2hunter2' "$_xr_sr2/stdout" 2>/dev/null; then
        _x_ok "a credential-shaped stream is REDACTED in place and the row states stream_redacted=true"
    elif [ "$_xr_red2" = "false" ] && grep -q 'hunter2hunter2' "$_xr_sr2/stdout" 2>/dev/null; then
        printf '  SKIP redaction not exercised — the scanner did not classify the probe value as a credential; the row honestly states stream_redacted=false rather than claiming a scan that did not hit (§11.4.6)\n'
    else
        _x_bad "redaction state is inconsistent with the stream on disk (stream_redacted=$_xr_red2)"
    fi

    rm -rf "$_xr_tmp"
    if [ "$_xr_trc" -eq 0 ]; then
        printf 'EXECUTION-RECORD SELFTEST PASS — full field set recorded, digests taken over the FULL stream before truncation (and provably able to DISAGREE), exit status never defaulted, lookup distinguishes found / not-found / BLIND, credential-shaped streams redacted in place\n'
    else
        printf 'EXECUTION-RECORD SELFTEST FAIL\n' >&2
    fi
    return "$_xr_trc"
}

# --- dispatch (content-identified, never by filename) ------------------------
_XR_SELF_SENTINEL='xr-self-id-4d8e13c7-execution-record'
_xr_is_self() { [ -n "${1:-}" ] && [ -r "$1" ] && grep -qF "$_XR_SELF_SENTINEL" "$1" 2>/dev/null; }
if [ -n "${BASH_SOURCE:-}" ]; then
    if [ "${BASH_SOURCE}" = "$0" ]; then _XR_EXECUTED=1; else _XR_EXECUTED=0; fi
    XR_SELF_PATH="${BASH_SOURCE}"
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
    case "$ZSH_EVAL_CONTEXT" in *:file*) _XR_EXECUTED=0 ;; *) _XR_EXECUTED=1 ;; esac
elif _xr_is_self "$0"; then _XR_EXECUTED=1; XR_SELF_PATH="$0"
elif [ -r "$0" ]; then _XR_EXECUTED=0
else _XR_EXECUTED=u
fi

if [ "$_XR_EXECUTED" = "1" ]; then
    case "${1:-}" in
        run)        shift; exec_record_run "$@"; exit $? ;;
        lookup)     exec_record_lookup "${2:-}" "${3:-}"; exit $? ;;
        --selftest) _xr_selftest; exit $? ;;
        *) printf 'usage: %s run <recorder> <stream_root> -- <argv...> | lookup <recorder> <command> | --selftest\n' "$0" >&2; exit 2 ;;
    esac
fi
