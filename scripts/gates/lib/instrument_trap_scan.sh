#!/bin/sh
# =============================================================================
# instrument_trap_scan.sh — matchers for the five MEASURED instrument-trap
# classes (T220, §11.4.201(7)(c) "the path is part of the instrument").
#
# ── Why this exists ──────────────────────────────────────────────────────────
# Each class below returns a CLEAN, CONFIDENT, WRONG answer without crashing.
# That is what makes them invisible to every other layer: §11.4.1's script-bug
# clause only catches a crash, and §11.4.67's parse check only reads the file at
# parse time. Nothing in the toolchain notices an instrument that silently could
# not see, so it has to be matched for by name.
#
# ── The five classes, each MEASURED on this host ─────────────────────────────
#   trap_pipeline_exit_status     `( exit 1 ) | cat; echo $?` -> 0. The rc
#                                 belongs to the LAST stage, so a probe piped
#                                 into a pager reports the PAGER's success.
#                                 Countermeasure: capture the rc from the
#                                 command itself, or read PIPESTATUS.
#   trap_relative_date_predicate  /usr/bin/find is bfs 4.1.1 here:
#                                 `-newermt '-1 day'` -> rc=1 "Invalid
#                                 timestamp"; behind `2>/dev/null | wc -l` that
#                                 reads as 0 and "nothing changed" is believed.
#                                 Countermeasure: an ABSOLUTE timestamp.
#   trap_inverted_match           `grep -qv alpha f` -> rc=1 on a file that DOES
#                                 hold a non-matching line. -q + -v reports the
#                                 wrong status whenever any line matches.
#                                 Countermeasure: `grep -cv` + a COUNT compare.
#   trap_query_class_mismatch     a bare-literal needle crosses fewer layers
#                                 than an ERE query, so it certifies a zero the
#                                 query never really searched for
#                                 (§11.4.201(7)(b)). Countermeasure: a needle
#                                 carrying the query's load-bearing features.
#   trap_greedy_display_transform a `sed` capture that is a bare `.*` spans past
#                                 the next literal, merging two tokens on one
#                                 line into one. Countermeasure: a character
#                                 class that cannot cross the delimiter.
#
# ── Output contract (T220) ───────────────────────────────────────────────────
# Every finding carries the CLASS ID and the OFFENDING LINE, never a bare
# boolean, so a finding is diagnosable in one step:
#     FINDING <class_id> <file>:<lineno> <line text>
#
# ── False positives are refusals (§11.4.201(1)) ──────────────────────────────
# The GOOD half of the fixture set is not decoration. A scanner that fires on
# the countermeasure is a false-refusal engine, and the first thing a team does
# with a scanner that cries wolf is switch it off. Every matcher below is
# therefore paired with the countermeasure it must NOT fire on, and comment
# lines are skipped: a comment that DESCRIBES a trap is a CARRIER, not the trap
# (§11.4.201(7)(a)) — this very file would otherwise flag itself.
#
# ── This scanner obeys its own rules ─────────────────────────────────────────
# It uses index()/substr() rather than a greedy `sub(/^.*-newermt.*/, ...)` to
# read the -newermt argument, because using a greedy transform inside the
# matcher for greedy transforms would reproduce class 5 in the code meant to
# detect it.
#
# Usage : . constitution/scripts/gates/lib/instrument_trap_scan.sh
#         its_scan_file <file>          -> prints FINDING lines; rc 0 clean, 1 findings
#         its_class_ids                 -> the closed class-id set, one per line
#         sh instrument_trap_scan.sh --selftest
# Deps  : POSIX sh, awk, grep.
# Xref  : §11.4.201(6)(7) · docs/guides/shell_instrument_footguns.md · T215 · T231
# =============================================================================

set -u

ITS_CLASS_IDS='trap_pipeline_exit_status
trap_relative_date_predicate
trap_inverted_match
trap_query_class_mismatch
trap_greedy_display_transform'

its_class_ids() { printf '%s\n' "$ITS_CLASS_IDS"; }

# its_scan_file <file>
#   stdout : one `FINDING <class> <file>:<line> <text>` per hit
#   rc     : 0 = no findings, 1 = findings, 2 = unreadable target
its_scan_file() {
    _its_f=${1:-}
    if [ -z "$_its_f" ] || [ ! -r "$_its_f" ]; then
        printf 'REFUSE target_UNREADABLE(%s) — an unreadable target is refused, never reported clean\n' "${_its_f:-<none>}" >&2
        return 2
    fi

    # File-level context for the query-class matcher: does this file use an ERE
    # grep anywhere? Read as a COUNT, never through `grep -q` (class 3).
    _its_ere=$(grep -Ec 'grep[[:space:]]+-[A-Za-z]*E' -- "$_its_f" 2>/dev/null || true)
    [ -n "${_its_ere:-}" ] || _its_ere=0

    # NOTE: there is deliberately NO env-var escape that suppresses a class.
    # An earlier draft carried an ITS_SKIP_CLASS knob for the paired mutation to
    # use; it was removed because a scanner that can be silently blinded by an
    # environment variable IS the defect this scanner exists to detect. The
    # paired mutation edits an out-of-repo COPY of this file instead.
    awk -v file="$_its_f" -v has_ere="$_its_ere" '
    function emit(cls,   _) {
        printf "FINDING %s %s:%d %s\n", cls, file, NR, $0
        found++
    }
    function ltrim(s) { while (substr(s,1,1) == " " || substr(s,1,1) == "\t") s = substr(s,2); return s }

    # A comment DESCRIBING a trap is a carrier, not the trap (SS11.4.201(7)(a)).
    /^[[:space:]]*#/ { next }

    {
        # ---- class 1: pipeline exit status -----------------------------------
        # A pipe into a display/consumer stage, then an rc read within the next
        # few lines as if it were the probe s own.
        if ($0 ~ /\|[[:space:]]*(head|tail|cat|less|more|tee|column|wc|sort|uniq)([[:space:]]|$)/) {
            pipe_line = NR; pipe_text = $0
        }
        if (pipe_line > 0 && NR >= pipe_line && NR - pipe_line <= 3 && $0 ~ /=[[:space:]]*\$\?/) {
            emit("trap_pipeline_exit_status"); pipe_line = 0
        }

        # ---- class 2: relative date predicate --------------------------------
        # index()/substr() on purpose: a greedy sub() here would be class 5.
        p = index($0, "-newermt")
        if (p > 0) {
            rest = ltrim(substr($0, p + 8))
            q = substr(rest, 1, 1)
            if (q == "\"" || q == "'"'"'") rest = substr(rest, 2)
            c = substr(rest, 1, 1)
            if (c == "$" || c == "{") {
                # a variable: its value is decided elsewhere, not here
            } else if (c == "-" || c == "+") {
                emit("trap_relative_date_predicate")
            } else if (rest ~ /(ago|yesterday|today|[[:space:]]now)/) {
                emit("trap_relative_date_predicate")
            }
        }

        # ---- class 3: inverted match used for a verdict ----------------------
        # -q and -v in one cluster, or as adjacent separate flags.
        if ($0 ~ /grep[[:space:]]+(-[A-Za-z]*q[A-Za-z]*v|-[A-Za-z]*v[A-Za-z]*q)([[:space:]]|$)/ ||
            $0 ~ /grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-q[[:space:]]+-v([[:space:]]|$)/ ||
            $0 ~ /grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+-v[[:space:]]+-q([[:space:]]|$)/) {
            emit("trap_inverted_match")
        }

        # ---- class 4: query-class mismatch -----------------------------------
        # A needle counted through a NON-ERE grep in a file whose certified
        # query uses ERE: the needle crosses fewer layers than the query.
        # The grep must be EXECUTED here (a command substitution), not merely
        # mentioned. A line that carries a grep command as a STRING — an
        # example, a comparison value, a message — is a CARRIER, and flagging
        # it would be the false refusal SS11.4.201(1) rates as seriously as a
        # false pass. Measured: this exact matcher fired on a line holding a
        # quoted grep -c command as data rather than executing one.
        # (No apostrophe appears in this comment on purpose: the whole awk
        #  program is a single-quoted shell string, so one would end it.)
        if (has_ere + 0 > 0 && $0 ~ /needle/ &&
            ($0 ~ /\$\(grep[[:space:]]+-[A-Za-z]*c/ || $0 ~ /`grep[[:space:]]+-[A-Za-z]*c/) &&
            $0 !~ /grep[[:space:]]+-[A-Za-z]*E/) {
            emit("trap_query_class_mismatch")
        }

        # ---- class 5: greedy display transform -------------------------------
        # A sed capture group that is a bare .* — BRE \(.*\) or ERE (.*).
        if ($0 ~ /sed/ && ($0 ~ /\\\(\.\*\\\)/ || $0 ~ /-E[^|]*\(\.\*\)/)) {
            emit("trap_greedy_display_transform")
        }
    }
    END { exit (found > 0 ? 1 : 0) }
    ' "$_its_f"
    return $?
}

# --- selftest: every class fires on its golden-BAD and stays silent on its
#     golden-GOOD counterpart. Both halves, because a false refusal is rated
#     exactly as seriously as a false pass (§11.4.201(1)).
its_selftest() {
    # ITS_FIXTURES swaps the golden fixtures the selftest proves the detector against (a fixture set the detector
    # trivially passes would certify a blind detector): INLINE-GUARDED (11.4.201(6)-(8), POSIX twin of
    # scripts/lib/gate_env_override.sh) -- honoured only under HELIX_TEST_MODE=1 with a path under the temp root.
    _st_root=""
    if [ -n "${ITS_FIXTURES:-}" ]; then
        _st_tr=$(readlink -m -- "${TMPDIR:-/tmp}" 2>/dev/null); _st_fr=$(readlink -m -- "$ITS_FIXTURES" 2>/dev/null)
        if [ "${HELIX_TEST_MODE:-}" = 1 ] && [ -n "$_st_tr" ] && [ "$_st_tr" != / ] && [ -n "$_st_fr" ] && [ "${_st_fr#"$_st_tr"/}" != "$_st_fr" ]; then
            _st_root=$_st_fr; printf 'gate_env_override: honouring ITS_FIXTURES (HELIX_TEST_MODE=1)\n' >&2
        else
            printf 'gate_env_override: ignoring ITS_FIXTURES (needs HELIX_TEST_MODE=1 and a path under the temp root); using the real fixtures\n' >&2
        fi
    fi
    if [ -z "$_st_root" ]; then
        _st_here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
        _st_root="${_st_here}/../fixtures/instrument_trap_scan/traps"
    fi
    if [ ! -d "$_st_root" ]; then
        printf 'SELFTEST-BLIND fixtures not found at %s — reporting blindness, not compliance\n' "$_st_root"
        return 2
    fi
    _st_bad=0
    for _st_pair in \
        'bad_01_pipeline_exit_status.sh:trap_pipeline_exit_status' \
        'bad_02_relative_date_predicate.sh:trap_relative_date_predicate' \
        'bad_03_inverted_match.sh:trap_inverted_match' \
        'bad_04_query_class_mismatch.sh:trap_query_class_mismatch' \
        'bad_05_greedy_display_transform.sh:trap_greedy_display_transform'
    do
        _st_f=${_st_pair%%:*}; _st_c=${_st_pair#*:}
        _st_out=$(its_scan_file "${_st_root}/${_st_f}" 2>&1); _st_rc=$?
        _st_n=$(printf '%s\n' "$_st_out" | grep -Ec "FINDING ${_st_c} " || true)
        if [ "$_st_rc" -eq 1 ] && [ "${_st_n:-0}" -gt 0 ]; then
            printf 'SELFTEST GB %-34s ok   flagged as %s\n' "$_st_f" "$_st_c"
        else
            printf 'SELFTEST GB %-34s BAD  rc=%s hits=%s expected class %s\n' "$_st_f" "$_st_rc" "${_st_n:-0}" "$_st_c"
            _st_bad=$((_st_bad + 1))
        fi
    done
    for _st_f in good_01_pipeline_exit_status.sh good_02_relative_date_predicate.sh \
                 good_03_inverted_match.sh good_04_query_class_mismatch.sh \
                 good_05_greedy_display_transform.sh
    do
        _st_out=$(its_scan_file "${_st_root}/${_st_f}" 2>&1); _st_rc=$?
        if [ "$_st_rc" -eq 0 ] && [ -z "$_st_out" ]; then
            printf 'SELFTEST GG %-34s ok   not flagged (countermeasure accepted)\n' "$_st_f"
        else
            printf 'SELFTEST GG %-34s BAD  rc=%s out=[%s] — a false refusal is as serious as a false pass\n' "$_st_f" "$_st_rc" "$_st_out"
            _st_bad=$((_st_bad + 1))
        fi
    done
    printf 'SELFTEST-SUMMARY bad=%s\n' "$_st_bad"
    [ "$_st_bad" -eq 0 ] || return 1
    return 0
}

case ${1:-} in
    --selftest) its_selftest; exit $? ;;
    --class-ids) its_class_ids; exit 0 ;;
esac
