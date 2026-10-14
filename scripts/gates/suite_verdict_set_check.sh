#!/usr/bin/env bash
# suite_verdict_set_check.sh — reads the OUTPUT of a self-reporting test suite and accepts it only when the
# suite's closed set of named verdict lines is present and agrees with its own tally.
#
# ── Why it exists ───────────────────────────────────────────────────────────
# Round-4 review N6/N7 of the 2026-10-14 pre-build remedy batch: a consumer gate that reads only a suite's
# exit code and its summary tally can be silenced through the suite's own reporting channel. Reviewer mutant
# RX1 inverted the guard of covenant_propagation_suite.sh's SUITE-ACCOUNTING entry (the entry just vanished);
# with one more accounting edit and an engine defect the suite printed a failing ENGINE-SELFTEST entry yet
# "0 non-zero", rc 0, and the consumer read PASS. Reviewer mutant RX3 did the same to the credential-scan
# suite's (z) sub-case: it printed "PASS: (z) … PAIR NOT DEMONSTRATED" and scored 95/0. Both shapes are
# visible in the printed lines; this checker reads them, so the consumer seam reads a closed, named verdict
# set instead of rc plus a tally.
#
# ── Profiles ────────────────────────────────────────────────────────────────
#   covenant-gates   output of `covenant_propagation_suite.sh gates`.
#     - the suite exited 0 (--rc);
#     - exactly one `suite(gates): N entries, E exit-0, B non-zero` line, with B = 0 and E = N - B;
#     - the entry table (rows between the header underline and the footer rule, each `<name> <rc> …`) has
#       exactly N rows, no duplicate name, an integer rc in every row, and exactly B rows with a non-zero rc
#       (the cross-check of printed entries against the tally);
#     - the named self-test entries CM-COVENANT-PROPAGATION-ENGINE-SELFTEST,
#       CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING and CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK are each
#       present exactly once with rc 0. They are required whenever the suite directory (--suite-dir, default:
#       this script's directory) holds lib/covenant_propagation_engine.sh, which is the suite's own condition
#       for running them; this checker tests that file itself, so editing the suite's guard does not move it.
#   credscan-suite   output of `test_credential_scan_lib.sh`.
#     - the suite exited 0 (--rc);
#     - exactly one `== RESULT: P passed, F failed ==` line with F = 0;
#     - the printed `PASS: ` lines number exactly P and the printed `FAIL: ` lines exactly F;
#     - exactly one `PASS: (x) … (rc=0, <n≥1> sub-checks passed, 0 failed)` line, the same for (y), and
#       exactly one `PASS: (z) …` line that says `PAIR VALID` and not `NOT DEMONSTRATED`;
#     - no `INFO: (z) … not re-entered` line (that is the sandbox-inner mode, never a consumer run).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   <suite> … > out; rc=$?
#   suite_verdict_set_check.sh --profile covenant-gates|credscan-suite --rc "$rc" [--suite-dir DIR] [--file out]
#   (reads standard input when --file is not given)
#
# ── Output / exit codes ──────────────────────────────────────────────────────
#   One `VERDICT-SET: INVALID — <reason>` line per broken rule, or one `VERDICT-SET: VALID — <summary>` line.
#   0 VALID · 1 INVALID · 2 usage / unreadable input.
#
# Honest boundary (§11.4.6): the checker proves the printed verdict set is complete and self-consistent; it
# cannot prove the suite PRINTED the truth. A suite edited to print a forged consistent set (every line, the
# tally and the exit code together) passes it; that is a multi-line diff in a reviewed file (§11.4.142).
# Paired test: suite_verdict_set_check_mutation_test.sh (synthetic fixtures + the reviewer mutants RX1 and RX3
# applied verbatim to real suite copies). Wired: covenant_propagation_suite.sh `gates` runs that test as the
# entry CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK; consumers call this checker from their gates.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROFILE=""; RC=""; SUITE_DIR="$HERE"; FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --profile)   PROFILE="${2:-}"; shift 2 ;;
        --rc)        RC="${2:-}"; shift 2 ;;
        --suite-dir) SUITE_DIR="${2:-}"; shift 2 ;;
        --file)      FILE="${2:-}"; shift 2 ;;
        *) echo "usage: $0 --profile covenant-gates|credscan-suite --rc N [--suite-dir DIR] [--file F]" >&2; exit 2 ;;
    esac
done
case "$PROFILE" in covenant-gates|credscan-suite) ;; *) echo "suite_verdict_set_check: unknown profile '$PROFILE'" >&2; exit 2 ;; esac
case "$RC" in ''|*[!0-9-]*) echo "suite_verdict_set_check: --rc <integer> is required" >&2; exit 2 ;; esac
if [ -n "$FILE" ]; then
    [ -r "$FILE" ] || { echo "suite_verdict_set_check: cannot read $FILE" >&2; exit 2; }
    OUT="$(cat "$FILE")"
else
    OUT="$(cat)"
fi
nbad=0
invalid() { nbad=$((nbad + 1)); echo "VERDICT-SET: INVALID — $*"; }
count() { printf '%s\n' "$OUT" | grep -cE -- "$1"; }

[ "$RC" = 0 ] || invalid "the suite exited $RC"

if [ "$PROFILE" = covenant-gates ]; then
    n_sum="$(count '^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, [0-9]+ non-zero')"
    if [ "$n_sum" != 1 ]; then
        invalid "expected exactly one 'suite(gates): N entries, E exit-0, B non-zero' line, found $n_sum"
        N=-1; E=-1; B=-1
    else
        sum="$(printf '%s\n' "$OUT" | grep -E '^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, [0-9]+ non-zero')"
        N="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): ([0-9]+) entries.*/\1/')"
        E="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): [0-9]+ entries, ([0-9]+) exit-0.*/\1/')"
        B="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, ([0-9]+) non-zero.*/\1/')"
        [ "$B" -eq 0 ] || invalid "the summary counts $B non-zero entr(y/ies)"
        [ "$E" -eq $((N - B)) ] || invalid "the summary is inconsistent: $E exit-0 != $N entries - $B non-zero"
    fi
    # the entry table: the rows between the header underline (`----… ----- ----…`) and the footer rule
    # (one long `----…` line); each row is `<name> <rc> <verdict…>`
    n_head="$(count '^-{20,} -{5} -{10,}$')"; n_foot="$(count '^-{60,}$')"
    [ "$n_head" = 1 ] && [ "$n_foot" = 1 ] || invalid "expected one entry-table header rule and one footer rule, found $n_head / $n_foot"
    entries="$(printf '%s\n' "$OUT" | awk '/^-{20,} -{5} -{10,}$/ {t = 1; next} /^-{60,}$/ {t = 0} t && NF >= 2 {print $1"\t"$2}')"
    badrow="$(printf '%s\n' "$entries" | awk -F'\t' 'NF && $2 !~ /^-?[0-9]+$/ {print $1; exit}')"
    [ -z "$badrow" ] || invalid "entry row without an integer exit code: $badrow"
    n_lines=0; n_nonzero=0
    [ -n "$entries" ] && n_lines="$(printf '%s\n' "$entries" | wc -l)" \
                      && n_nonzero="$(printf '%s\n' "$entries" | awk -F'\t' '$2 != 0' | wc -l)"
    if [ "$N" -ge 0 ]; then
        [ "$n_lines" -eq "$N" ] || invalid "the suite printed $n_lines entry line(s) but its summary counts $N entries"
        [ "$n_nonzero" -eq "$B" ] || invalid "the suite printed $n_nonzero entry line(s) with a non-zero exit code but its summary counts $B non-zero"
    fi
    dup="$(printf '%s\n' "$entries" | cut -f1 | sort | uniq -d | head -1)"
    [ -z "$dup" ] || invalid "entry printed more than once: $dup"
    if [ -f "$SUITE_DIR/lib/covenant_propagation_engine.sh" ]; then
        for name in CM-COVENANT-PROPAGATION-ENGINE-SELFTEST CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING \
                    CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK; do
            got="$(printf '%s\n' "$entries" | awk -F'\t' -v n="$name" '$1 == n {print $2}')"
            if [ -z "$got" ]; then invalid "named entry missing: $name"
            elif [ "$got" != 0 ]; then invalid "named entry $name exited $got"; fi
        done
        req="3 named self-test entries present"
    else
        req="no engine in $SUITE_DIR, so the named self-test entries are not required"
    fi
    [ "$nbad" -eq 0 ] && { echo "VERDICT-SET: VALID — rc 0, $N entries printed and counted, 0 non-zero, $req"; exit 0; }
    exit 1
fi

# credscan-suite
n_res="$(count '^== RESULT: [0-9]+ passed, [0-9]+ failed ==$')"
if [ "$n_res" != 1 ]; then
    invalid "expected exactly one '== RESULT: P passed, F failed ==' line, found $n_res"; P=-1; F=-1
else
    res="$(printf '%s\n' "$OUT" | grep -E '^== RESULT: [0-9]+ passed, [0-9]+ failed ==$')"
    P="$(printf '%s\n' "$res" | sed -E 's/^== RESULT: ([0-9]+) passed.*/\1/')"
    F="$(printf '%s\n' "$res" | sed -E 's/^== RESULT: [0-9]+ passed, ([0-9]+) failed.*/\1/')"
    [ "$F" -eq 0 ] || invalid "the suite counts $F failed case(s)"
fi
n_pass="$(count '^PASS: ')"; n_fail="$(count '^FAIL: ')"
if [ "$P" -ge 0 ]; then
    [ "$n_pass" -eq "$P" ] || invalid "the suite printed $n_pass PASS line(s) but its RESULT counts $P passed"
    [ "$n_fail" -eq "$F" ] || invalid "the suite printed $n_fail FAIL line(s) but its RESULT counts $F failed"
fi
for sub in x y; do
    c="$(count "^PASS: \\($sub\\) .*\\(rc=0, [1-9][0-9]* sub-checks passed, 0 failed\\)\$")"
    [ "$c" = 1 ] || invalid "expected exactly one 'PASS: ($sub) … (rc=0, n sub-checks passed, 0 failed)' line, found $c"
done
zv="$(count '^PASS: \(z\) .*PAIR VALID')"; zn="$(count '^PASS: \(z\) .*NOT DEMONSTRATED')"
[ "$zv" = 1 ] && [ "$zn" = 0 ] || invalid "expected exactly one 'PASS: (z) … PAIR VALID' line and none saying NOT DEMONSTRATED (found $zv / $zn)"
zi="$(count '^INFO: \(z\) .*not re-entered')"
[ "$zi" = 0 ] || invalid "the suite ran in its sandbox-inner mode ((z) not re-entered); a consumer run must be the outer run"
[ "$nbad" -eq 0 ] && { echo "VERDICT-SET: VALID — rc 0, $P PASS lines printed and counted, 0 failed, (x) (y) (z) verdicts present"; exit 0; }
exit 1
