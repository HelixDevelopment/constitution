#!/bin/sh
# cm_escape_ratchet.sh — CM-ESCAPE-RATCHET gate (FR-043, FR-044, SC-008;
# quickstart S22; feature 002-anti-slop-enforcement, task T405c).
#
# ── Purpose ─────────────────────────────────────────────────────────────────
# Reads the discovery-channel ledger and answers ONE question per cycle: did
# the automated regime DISCOVER the defects, or did a human/operator/end-user/
# code-reading agent find them first? Everything in the second group is an
# ESCAPE (§11.4.238 — automated QA is the DISCOVERER; manual QA is meant to
# find NOTHING NEW). The escape count is ratcheted against a checked-in
# baseline: an increase REFUSES.
#
# ── The three ways this measurement can be gamed, and what stops each ───────
#   (1) DON'T LOOK.  A cycle where the manual pass never ran would otherwise
#       record zero escapes and quietly RATCHET THE BASELINE DOWN — rewarding
#       not looking. FR-044's false-null guard: `manual_qa_ran: false` is NO
#       DATA POINT. It never lowers the baseline, not even under --ratchet.
#       A zero from a cycle nobody inspected is not a measurement.
#   (2) NARROW THE DEFINITION.  Classifying escapes as
#       `should_have_been_caught_by: none` would deflate the count invisibly.
#       So `none` rows are tallied SEPARATELY and always printed, and `none`
#       without a written justification is REFUSED outright.
#   (3) WRITE YOUR OWN RECORD.  A producer grading its own escape is
#       self-attestation. A row whose `authored_by` equals its `produced_by`
#       is REFUSED — the ledger is the verifier seam's to write (FR-043).
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   cm_escape_ratchet.sh [--ledger <p>] [--baseline <p>] [--cycle <id>]
#                        [--ratchet] [--quiet]
#   cm_escape_ratchet.sh --selftest
#
#     --ledger <p>   discovery-channel JSONL (default:
#                    <repo>/docs/requests/discovery_channel.jsonl)
#     --baseline <p> baseline file (default: alongside this script)
#     --cycle <id>   evaluate this cycle (default: the LAST `cycle` row)
#     --ratchet      lower the baseline when the measured count is lower.
#                    NEVER lowers on a no-data-point cycle (guard 1).
#     --quiet        suppress the per-row dump; verdict lines always print.
#     --selftest     run the golden-TRUE / golden-FALSE / negative-control
#                    fixtures in a mktemp dir and remove it on exit.
#
# ── Exit codes ──────────────────────────────────────────────────────────────
#   0  PASS (count within baseline) or honest SKIP (baseline unset / no cycle
#      recorded / no data point)
#   1  FAIL (a malformed or producer-authored row, or an escape increase)
#   2  usage / unreadable input
#
# ── Side-effects ────────────────────────────────────────────────────────────
#   Read-only, EXCEPT `--ratchet`, which rewrites the baseline's value line,
#   and `--selftest`, which writes only inside a mktemp -d it removes on exit.
#
# ── Dependencies ────────────────────────────────────────────────────────────
#   POSIX sh, awk, mktemp. No jq: the ledger is parsed by an in-file scanner
#   so the gate has no dependency a host might lack (jq IS installed here, but
#   a gate that silently needs it would fail closed on a host that does not).
#
# ── Honest boundary (§11.4.6) ───────────────────────────────────────────────
#   This gate measures WHAT WAS RECORDED. It cannot see a defect nobody wrote
#   down. It therefore proves the ratchet was respected — never that the
#   escape set is complete (§11.4.118 discovery pressure is a separate job).
#   Portability: this file is written to POSIX sh and parses clean under
#   `sh -n` and `bash -n`; NO dash/busybox/ksh/mksh/posh exists on this host
#   (measured), so dash-portability is ASSERTED BY CONSTRUCTION, not proven.

set -u

PROG=$(basename "$0")
SELF_DIR=$(cd "$(dirname "$0")" && pwd)

LEDGER=""
BASELINE="$SELF_DIR/escape_ratchet_baseline.txt"
WANT_CYCLE=""
DO_RATCHET=0
QUIET=0
SELFTEST=0
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer ledger (only way to get the honest SKIP)

CHANNELS_ESCAPE_EXEMPT="automated_seam"
CHANNELS_ALL="automated_seam manual_qa operator end_user agent_inspection"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

verdict() { printf 'ESC-VERDICT\t%s\t%s\t%s\n' "$1" "$2" "$3"; }

while [ $# -gt 0 ]; do
    case $1 in
        --ledger)   shift; [ $# -gt 0 ] || die "--ledger needs a value"; LEDGER=$1 ;;
        --baseline) shift; [ $# -gt 0 ] || die "--baseline needs a value"; BASELINE=$1 ;;
        --cycle)    shift; [ $# -gt 0 ] || die "--cycle needs a value"; WANT_CYCLE=$1 ;;
        --ratchet)  DO_RATCHET=1 ;;
        --quiet)    QUIET=1 ;;
        --standalone-canon) STANDALONE=1 ;;
        --selftest) SELFTEST=1 ;;
        -h|--help)  sed -n '2,60p' "$0"; exit 0 ;;
        *)          die "unknown argument: $1" ;;
    esac
    shift
done

if [ -z "$LEDGER" ]; then
    # Default = where the gate LIVES (superproject when vendored, else the canon), never the directory above the canon.
    # shellcheck disable=SC1091
    [ -r "$SELF_DIR/../lib/default_scan_root.sh" ] && . "$SELF_DIR/../lib/default_scan_root.sh" && _er_root=$(cm_default_scan_root "$SELF_DIR") || _er_root=""
    [ -n "$_er_root" ] || _er_root="$SELF_DIR/../../.."   # staged copy without scripts/lib: legacy consumer depth
    LEDGER="$_er_root/docs/requests/discovery_channel.jsonl"
fi

# ---------------------------------------------------------------------------
# baseline_value <file>  — prints the single non-comment, non-blank line.
# Prints nothing when the file is absent.
# ---------------------------------------------------------------------------
baseline_value() {
    [ -f "$1" ] || return 0
    awk '
        /^[ \t]*#/ { next }
        /^[ \t]*$/ { next }
        { gsub(/^[ \t]+|[ \t]+$/, "", $0); print; exit }
    ' "$1"
}

# ---------------------------------------------------------------------------
# The single-pass ledger scanner. Emits, on stdout:
#   ROW<TAB>lineno<TAB>event<TAB>cycle<TAB>detail
#   BAD<TAB>lineno<TAB>reason
#   LASTCYCLE<TAB>cycle
# ---------------------------------------------------------------------------
scan_ledger() {
    awk -v want_cycle="$1" -v chan_all="$CHANNELS_ALL" '
        function jhas(s, key,   r) {
            r = "\"" key "\"[ \t]*:[ \t]*"
            return match(s, r) ? 1 : 0
        }
        function jval(s, key,   r, rest, out, i, c, esc) {
            r = "\"" key "\"[ \t]*:[ \t]*"
            if (!match(s, r)) return ""
            rest = substr(s, RSTART + RLENGTH)
            if (substr(rest, 1, 1) == "\"") {
                rest = substr(rest, 2); out = ""; esc = 0
                for (i = 1; i <= length(rest); i++) {
                    c = substr(rest, i, 1)
                    if (esc) { out = out c; esc = 0; continue }
                    if (c == "\\") { esc = 1; continue }
                    if (c == "\"") break
                    out = out c
                }
                return out
            }
            out = ""
            for (i = 1; i <= length(rest); i++) {
                c = substr(rest, i, 1)
                if (c == "," || c == "}" || c == " " || c == "\t") break
                out = out c
            }
            return out
        }
        function in_set(v, set,   n, a, i) {
            n = split(set, a, " ")
            for (i = 1; i <= n; i++) if (a[i] == v) return 1
            return 0
        }
        function bad(reason) { printf "BAD\t%d\t%s\n", NR, reason }

        /^[ \t]*#/ { next }
        /^[ \t]*$/ { next }
        {
            ev = jval($0, "event")
            if (ev == "") { bad("event_ABSENT"); next }
            if (ev != "defect" && ev != "cycle") { bad("event_NOT_IN_SET:" ev); next }

            cyc = jval($0, "cycle")
            if (cyc == "") { bad("cycle_ABSENT"); next }
            auth = jval($0, "authored_by")
            if (auth == "") { bad("authored_by_ABSENT"); next }
            if (jval($0, "ts") == "") { bad("ts_ABSENT"); next }

            if (ev == "defect") {
                did = jval($0, "defect_id")
                if (did == "") { bad("defect_id_ABSENT"); next }
                if (!jhas($0, "channel")) { bad("channel_ABSENT"); next }
                ch = jval($0, "channel")
                if (ch == "") { bad("channel_ABSENT"); next }
                if (!in_set(ch, chan_all)) { bad("channel_NOT_IN_SET:" ch); next }
                if (!jhas($0, "should_have_been_caught_by")) {
                    bad("should_have_been_caught_by_ABSENT"); next
                }
                shb = jval($0, "should_have_been_caught_by")
                if (shb == "") { bad("should_have_been_caught_by_ABSENT"); next }
                if (shb == "none" && jval($0, "justification") == "") {
                    bad("none_justification_ABSENT:" did); next
                }
                prod = jval($0, "produced_by")
                if (prod != "" && prod == auth) {
                    bad("producer_authored_record:" did); next
                }
                printf "ROW\t%d\tdefect\t%s\t%s\t%s\t%s\n", NR, cyc, ch, shb, did
                next
            }

            if (!jhas($0, "manual_qa_ran")) { bad("manual_qa_ran_ABSENT"); next }
            mq = jval($0, "manual_qa_ran")
            if (mq != "true" && mq != "false") { bad("manual_qa_ran_NOT_BOOLEAN:" mq); next }
            if (jval($0, "artifact_fingerprint") == "") { bad("artifact_fingerprint_ABSENT"); next }
            printf "ROW\t%d\tcycle\t%s\t%s\n", NR, cyc, mq
            last_cycle = cyc
        }
        END { if (last_cycle != "") printf "LASTCYCLE\t%s\n", last_cycle }
    ' "$2"
}

# ---------------------------------------------------------------------------
run_gate() {
    _lg=$1
    _bl=$2
    _want=$3
    _ratchet=$4

    [ -f "$_lg" ] || { verdict "LEDGER" "FAIL" "ledger not readable: $_lg"; return 2; }

    _bv=$(baseline_value "$_bl")
    if [ -z "$_bv" ]; then
        verdict "BASELINE" "SKIP" "baseline file absent or empty: $_bl"
        return 0
    fi
    if [ "$_bv" = "OPERATOR_DECISION_PENDING" ]; then
        verdict "BASELINE" "SKIP" "operator_decision_pending (§11.4.66) — the initial baseline value is the operator's to set; the gate refuses to invent a gating metric (§11.4.201(8))"
        return 0
    fi
    case $_bv in
        ''|*[!0-9]*) verdict "BASELINE" "FAIL" "baseline is not a non-negative integer: '$_bv'"; return 1 ;;
    esac

    _scan=$(scan_ledger "$_want" "$_lg")
    _rc=$?
    [ "$_rc" -eq 0 ] || { verdict "SCAN" "FAIL" "ledger scan failed rc=$_rc"; return 2; }

    _bad=$(printf '%s\n' "$_scan" | awk -F'\t' '$1=="BAD"{c++} END{printf "%d", c+0}')
    if [ "$_bad" -gt 0 ]; then
        printf '%s\n' "$_scan" | awk -F'\t' '$1=="BAD"{printf "  malformed row line %s: %s\n", $2, $3}'
        verdict "ROWS" "FAIL" "$_bad malformed or producer-authored row(s) — FR-043 refuses each"
        return 1
    fi

    _cycle=$_want
    if [ -z "$_cycle" ]; then
        _cycle=$(printf '%s\n' "$_scan" | awk -F'\t' '$1=="LASTCYCLE"{v=$2} END{print v}')
    fi
    if [ -z "$_cycle" ]; then
        verdict "CYCLE" "SKIP" "no cycle row recorded yet — nothing to ratchet"
        return 0
    fi

    _mq=$(printf '%s\n' "$_scan" | awk -F'\t' -v c="$_cycle" '$1=="ROW" && $3=="cycle" && $4==c {v=$5} END{print v}')
    if [ -z "$_mq" ]; then
        verdict "CYCLE" "FAIL" "cycle '$_cycle' has defect rows but no closing cycle row"
        return 1
    fi

    _esc=$(printf '%s\n' "$_scan" | awk -F'\t' -v c="$_cycle" -v ex="$CHANNELS_ESCAPE_EXEMPT" '
        $1=="ROW" && $3=="defect" && $4==c && $5!=ex {n++} END{printf "%d", n+0}')
    _caught=$(printf '%s\n' "$_scan" | awk -F'\t' -v c="$_cycle" -v ex="$CHANNELS_ESCAPE_EXEMPT" '
        $1=="ROW" && $3=="defect" && $4==c && $5==ex {n++} END{printf "%d", n+0}')
    _none=$(printf '%s\n' "$_scan" | awk -F'\t' -v c="$_cycle" '
        $1=="ROW" && $3=="defect" && $4==c && $6=="none" {n++} END{printf "%d", n+0}')

    [ "$QUIET" -eq 1 ] || printf '%s\n' "$_scan" | awk -F'\t' -v c="$_cycle" '
        $1=="ROW" && $3=="defect" && $4==c {printf "  defect %s  channel=%s  should_have_been_caught_by=%s\n", $7, $5, ($6==""?"?":$6)}'

    printf 'REPORT\tcycle=%s\tbaseline=%s\tescapes=%s\tcaught_by_automated_seam=%s\tclassified_none=%s\n' \
        "$_cycle" "$_bv" "$_esc" "$_caught" "$_none"

    if [ "$_mq" = "false" ]; then
        verdict "NODATA" "SKIP" "cycle '$_cycle' recorded manual_qa_ran=false — NO DATA POINT (FR-044). Baseline unchanged at $_bv; a zero from a cycle nobody inspected is not a measurement."
        return 0
    fi

    if [ "$_esc" -gt "$_bv" ]; then
        verdict "RATCHET" "FAIL" "escape count $_esc EXCEEDS baseline $_bv for cycle '$_cycle'"
        return 1
    fi

    if [ "$_esc" -lt "$_bv" ]; then
        if [ "$_ratchet" -eq 1 ]; then
            _tmp="${_bl}.tmp.$$"
            awk -v nv="$_esc" '
                BEGIN { done = 0 }
                /^[ \t]*#/ { print; next }
                /^[ \t]*$/ { print; next }
                { if (!done) { print nv; done = 1 } }
                END { if (!done) print nv }
            ' "$_bl" > "$_tmp" || { rm -f "$_tmp"; verdict "RATCHET" "FAIL" "could not write baseline"; return 1; }
            mv "$_tmp" "$_bl" || { rm -f "$_tmp"; verdict "RATCHET" "FAIL" "could not replace baseline"; return 1; }
            verdict "RATCHET" "PASS" "escape count $_esc < baseline $_bv — baseline LOWERED to $_esc"
            return 0
        fi
        verdict "RATCHET" "PASS" "escape count $_esc < baseline $_bv — baseline lowerable to $_esc (re-run with --ratchet)"
        return 0
    fi

    verdict "RATCHET" "PASS" "escape count $_esc == baseline $_bv for cycle '$_cycle'"
    return 0
}

# ---------------------------------------------------------------------------
selftest() {
    _d=$(mktemp -d) || die "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -rf '$_d'" EXIT INT TERM
    _pass=0
    _fail=0

    _st_case() {
        _name=$1; _want_rc=$2; _lg=$3; _bl=$4; _extra=$5
        _r=0
        [ "$_extra" = "--ratchet" ] && _r=1
        run_gate "$_lg" "$_bl" "" "$_r" > "$_d/out.$$" 2>&1
        _got=$?
        if [ "$_got" -eq "$_want_rc" ]; then
            printf 'SELFTEST\tPASS\t%s (rc=%s)\n' "$_name" "$_got"
            _pass=$((_pass + 1))
        else
            printf 'SELFTEST\tFAIL\t%s (want rc=%s got rc=%s)\n' "$_name" "$_want_rc" "$_got"
            sed 's/^/      | /' "$_d/out.$$"
            _fail=$((_fail + 1))
        fi
    }

    printf '3\n' > "$_d/base3.txt"
    printf '1\n' > "$_d/base1.txt"
    printf 'OPERATOR_DECISION_PENDING\n' > "$_d/base_pending.txt"

    # GOLDEN-FALSE (clean) — one escape, baseline 3 → must NOT fire.
    cat > "$_d/clean.jsonl" <<'EOJ'
# comment line is ignored
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"pre-build","authored_by":"verifier","produced_by":"producer","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "golden-FALSE clean cycle within baseline must ALLOW" 0 "$_d/clean.jsonl" "$_d/base3.txt" ""

    # GOLDEN-TRUE (violation) — two escapes over baseline 1 → must FAIL.
    cat > "$_d/over.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"pre-build","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"defect","cycle":"c1","defect_id":"ATM-2","channel":"operator","should_have_been_caught_by":"release-tag","authored_by":"verifier","ts":"2026-08-21T00:10:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "golden-TRUE escape increase must REFUSE" 1 "$_d/over.jsonl" "$_d/base1.txt" ""

    # NEGATIVE CONTROL — a defect found BY an automated seam is not an escape.
    cat > "$_d/autoseam.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-9","channel":"automated_seam","should_have_been_caught_by":"pre-build","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"defect","cycle":"c1","defect_id":"ATM-8","channel":"automated_seam","should_have_been_caught_by":"commit","authored_by":"verifier","ts":"2026-08-21T00:01:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "negative control: automated_seam discoveries are not escapes" 0 "$_d/autoseam.jsonl" "$_d/base1.txt" ""

    # FR-043 refusals.
    cat > "$_d/nochan.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","should_have_been_caught_by":"pre-build","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "FR-043 missing channel must REFUSE" 1 "$_d/nochan.jsonl" "$_d/base3.txt" ""

    cat > "$_d/badchan.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"telepathy","should_have_been_caught_by":"pre-build","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "FR-043 off-closed-set channel must REFUSE" 1 "$_d/badchan.jsonl" "$_d/base3.txt" ""

    cat > "$_d/nonenojust.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"none","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "FR-043 'none' without justification must REFUSE" 1 "$_d/nonenojust.jsonl" "$_d/base3.txt" ""

    cat > "$_d/nonejust.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"none","justification":"no seam observes AVR sink labels; tracked as ATM-1023","authored_by":"verifier","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "false-positive guard: 'none' WITH justification must ALLOW" 0 "$_d/nonejust.jsonl" "$_d/base3.txt" ""

    cat > "$_d/selfauth.jsonl" <<'EOJ'
{"event":"defect","cycle":"c1","defect_id":"ATM-1","channel":"manual_qa","should_have_been_caught_by":"pre-build","authored_by":"producer-x","produced_by":"producer-x","ts":"2026-08-21T00:00:00Z"}
{"event":"cycle","cycle":"c1","manual_qa_ran":true,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    _st_case "FR-043 producer-authored record must REFUSE" 1 "$_d/selfauth.jsonl" "$_d/base3.txt" ""

    # FR-044 false-null guard: manual_qa_ran=false, zero escapes.
    cat > "$_d/nodata.jsonl" <<'EOJ'
{"event":"cycle","cycle":"c1","manual_qa_ran":false,"artifact_fingerprint":"fp-1","authored_by":"verifier","ts":"2026-08-21T01:00:00Z"}
EOJ
    printf '3\n' > "$_d/base_nd.txt"
    _st_case "FR-044 no-data-point cycle must ALLOW without lowering" 0 "$_d/nodata.jsonl" "$_d/base_nd.txt" "--ratchet"
    _bv_after=$(baseline_value "$_d/base_nd.txt")
    if [ "$_bv_after" = "3" ]; then
        printf 'SELFTEST\tPASS\tFR-044 baseline UNCHANGED at 3 after no-data-point --ratchet\n'
        _pass=$((_pass + 1))
    else
        printf 'SELFTEST\tFAIL\tFR-044 baseline moved to %s on a no-data-point cycle\n' "$_bv_after"
        _fail=$((_fail + 1))
    fi

    # --ratchet lowers on a real measurement.
    printf '3\n' > "$_d/base_low.txt"
    _st_case "--ratchet lowers baseline on a measured cycle" 0 "$_d/clean.jsonl" "$_d/base_low.txt" "--ratchet"
    _bv_low=$(baseline_value "$_d/base_low.txt")
    if [ "$_bv_low" = "1" ]; then
        printf 'SELFTEST\tPASS\tbaseline lowered 3 -> 1 on a measured cycle\n'
        _pass=$((_pass + 1))
    else
        printf 'SELFTEST\tFAIL\tbaseline should be 1, is %s\n' "$_bv_low"
        _fail=$((_fail + 1))
    fi

    # Operator-decision-pending baseline SKIPs rather than refusing.
    _st_case "unset baseline SKIPs (never a false-positive refusal)" 0 "$_d/over.jsonl" "$_d/base_pending.txt" ""

    printf 'SELFTEST\tSUMMARY\tpass=%d fail=%d\n' "$_pass" "$_fail"
    [ "$_fail" -eq 0 ] || return 1
    return 0
}

if [ "$SELFTEST" -eq 1 ]; then
    selftest
    rc=$?
    exit "$rc"
fi

if [ "$STANDALONE" -eq 1 ] && [ ! -f "$LEDGER" ]; then
    verdict "LEDGER" "SKIP" "standalone canon DECLARED (--standalone-canon): the discovery-channel ledger $LEDGER is consumer data and does not exist here (honest SKIP, not a PASS)"
    exit 3
fi
run_gate "$LEDGER" "$BASELINE" "$WANT_CYCLE" "$DO_RATCHET"
rc=$?
exit "$rc"
