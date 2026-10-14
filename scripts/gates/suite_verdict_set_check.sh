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
# Every rule below has a rule id; suite_verdict_set_check_mutation_test.sh holds, per id, one fixture that only
# that rule rejects and one checker mutant that switches that rule off (the fixture must then read VALID); the
# table of ids and their pinning fixtures / mutants is that test's header.
#   both profiles
#     R-RC     the suite exited 0 (--rc);
#     R-INNER  no `INNER-MODE: <FLAG> …` line. A suite or sub-suite prints that line when an inner-mode flag
#              (COVENANT_PROPAGATION_SUITE_INNER, CREDSCAN_SUBSUITE_META_INNER, CORE_LITERAL_CD_INNER) is set;
#              those flags shorten a run for its own paired tests and are never set by a consumer, so a
#              consumer run that inherited one from its environment is refused, not silently shortened.
#   covenant-gates   output of `covenant_propagation_suite.sh gates`.
#     C-SUM    exactly one `suite(gates): N entries, E exit-0, B non-zero` line;
#     C-B0     B = 0;
#     C-ENB    E = N - B;
#     C-RULES  exactly one entry-table header rule and one footer rule;
#     C-INT    an integer rc in every entry row (rows between the header underline and the footer rule);
#     C-ROWS   exactly N entry rows;
#     C-NZ     exactly B rows with a non-zero rc (the cross-check of printed entries against the tally);
#     C-DUP    no entry name printed twice;
#     C-NAMED  CM-COVENANT-PROPAGATION-ENGINE-SELFTEST, CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING and
#              CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK each present. Always required (round-5 review N14: the
#              rule used to be keyed to a --suite-dir argument, which a one-edit consumer change could point
#              away). A present entry with a non-zero rc is already refused by C-B0 / C-NZ.
#   credscan-suite   output of `test_credential_scan_lib.sh`.
#     S-RES    exactly one `== RESULT: P passed, F failed ==` line;
#     S-F0     F = 0;
#     S-NP     exactly P printed `PASS: ` lines;
#     S-NF     exactly F printed `FAIL: ` lines;
#     S-X, S-Y exactly one `PASS: (x) … (rc=0, <n≥1> sub-checks passed, 0 failed)` line, the same for (y);
#     S-ZV     exactly one `PASS: (z) …` line that says `PAIR VALID`;
#     S-ZN     no `PASS: (z) …` line saying `NOT DEMONSTRATED`.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   <suite> … > out; rc=$?
#   suite_verdict_set_check.sh --profile covenant-gates|credscan-suite --rc "$rc" [--file out]
#   (reads standard input when --file is not given; any other argument is a usage error)
#
# ── Output / exit codes ──────────────────────────────────────────────────────
#   One `VERDICT-SET: INVALID [<rule id>] — <reason>` line per broken rule, or one `VERDICT-SET: VALID — …` line.
#   0 VALID · 1 INVALID · 2 usage / unreadable input.
#
# Honest boundary (§11.4.6): the checker proves the printed verdict set is complete and self-consistent; it
# cannot prove the suite PRINTED the truth. A suite edited to print a forged consistent set (every line, the
# tally and the exit code together) passes it; that is a multi-line diff in a reviewed file (§11.4.142).
# Paired test: suite_verdict_set_check_mutation_test.sh (one isolating fixture + one switch-off mutant per rule
# id, the reviewer mutants RX1, RX3, RV2 and RV5 applied verbatim, and an inherited-flag run per inner flag). Wired: covenant_propagation_suite.sh `gates` runs that test as the
# entry CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK; consumers call this checker from their gates.
# Classification: universal (§11.4.17).
set -uo pipefail
PROFILE=""; RC=""; FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --profile)   PROFILE="${2:-}"; shift 2 ;;
        --rc)        RC="${2:-}"; shift 2 ;;
        --file)      FILE="${2:-}"; shift 2 ;;
        *) echo "usage: $0 --profile covenant-gates|credscan-suite --rc N [--file F]" >&2; exit 2 ;;
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
invalid() { nbad=$((nbad + 1)); echo "VERDICT-SET: INVALID [$1] — $2"; }
count() { printf '%s\n' "$OUT" | grep -cE -- "$1"; }

[ "$RC" = 0 ] || invalid R-RC "the suite exited $RC"
n_inner="$(count '^INNER-MODE: ')"
[ "$n_inner" = 0 ] || invalid R-INNER "the run is in an inner mode ($(printf '%s\n' "$OUT" | grep -m1 -E '^INNER-MODE: ' | cut -c1-120)); a consumer run must be the outer run"

if [ "$PROFILE" = covenant-gates ]; then
    n_sum="$(count '^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, [0-9]+ non-zero')"
    N=-1; E=-1; B=-1
    [ "$n_sum" = 1 ] || invalid C-SUM "expected exactly one 'suite(gates): N entries, E exit-0, B non-zero' line, found $n_sum"
    if [ "$n_sum" = 1 ]; then
        sum="$(printf '%s\n' "$OUT" | grep -E '^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, [0-9]+ non-zero')"
        N="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): ([0-9]+) entries.*/\1/')"
        E="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): [0-9]+ entries, ([0-9]+) exit-0.*/\1/')"
        B="$(printf '%s\n' "$sum" | sed -E 's/^suite\(gates\): [0-9]+ entries, [0-9]+ exit-0, ([0-9]+) non-zero.*/\1/')"
        [ "$B" -eq 0 ] || invalid C-B0 "the summary counts $B non-zero entr(y/ies)"
        [ "$E" -eq $((N - B)) ] || invalid C-ENB "the summary is inconsistent: $E exit-0 != $N entries - $B non-zero"
    fi
    # the entry table: the rows between the header underline (`----… ----- ----…`) and the footer rule
    # (one long `----…` line); each row is `<name> <rc> <verdict…>`
    n_head="$(count '^-{20,} -{5} -{10,}$')"; n_foot="$(count '^-{60,}$')"
    [ "$n_head" = 1 ] && [ "$n_foot" = 1 ] || invalid C-RULES "expected one entry-table header rule and one footer rule, found $n_head / $n_foot"
    entries="$(printf '%s\n' "$OUT" | awk '/^-{20,} -{5} -{10,}$/ {t = 1; next} /^-{60,}$/ {t = 0} t && NF >= 2 {print $1"\t"$2}')"
    badrow="$(printf '%s\n' "$entries" | awk -F'\t' 'NF && $2 !~ /^-?[0-9]+$/ {print $1; exit}')"
    [ -z "$badrow" ] || invalid C-INT "entry row without an integer exit code: $badrow"
    n_lines=0; n_nonzero=0
    [ -n "$entries" ] && n_lines="$(printf '%s\n' "$entries" | wc -l)" \
                      && n_nonzero="$(printf '%s\n' "$entries" | awk -F'\t' '$2 != 0' | wc -l)"
    if [ "$N" -ge 0 ]; then
        [ "$n_lines" -eq "$N" ] || invalid C-ROWS "the suite printed $n_lines entry line(s) but its summary counts $N entries"
        [ "$n_nonzero" -eq "$B" ] || invalid C-NZ "the suite printed $n_nonzero entry line(s) with a non-zero exit code but its summary counts $B non-zero"
    fi
    dup="$(printf '%s\n' "$entries" | cut -f1 | sort | uniq -d | head -1)"
    [ -z "$dup" ] || invalid C-DUP "entry printed more than once: $dup"
    n_named=0
    for name in CM-COVENANT-PROPAGATION-ENGINE-SELFTEST CM-COVENANT-PROPAGATION-SUITE-ACCOUNTING CM-COVENANT-PROPAGATION-VERDICT-SET-CHECK; do
        if printf '%s\n' "$entries" | awk -F'\t' -v n="$name" '$1 == n {f = 1} END {exit !f}'; then n_named=$((n_named + 1))
        else invalid C-NAMED "named entry missing: $name"; fi
    done
    [ "$nbad" -eq 0 ] && { echo "VERDICT-SET: VALID — rc 0, $N entries printed and counted, 0 non-zero, $n_named of 3 named self-test entries present, no inner mode"; exit 0; }
    exit 1
fi

# credscan-suite
n_res="$(count '^== RESULT: [0-9]+ passed, [0-9]+ failed ==$')"
P=-1; F=-1
[ "$n_res" = 1 ] || invalid S-RES "expected exactly one '== RESULT: P passed, F failed ==' line, found $n_res"
if [ "$n_res" = 1 ]; then
    res="$(printf '%s\n' "$OUT" | grep -E '^== RESULT: [0-9]+ passed, [0-9]+ failed ==$')"
    P="$(printf '%s\n' "$res" | sed -E 's/^== RESULT: ([0-9]+) passed.*/\1/')"
    F="$(printf '%s\n' "$res" | sed -E 's/^== RESULT: [0-9]+ passed, ([0-9]+) failed.*/\1/')"
    [ "$F" -eq 0 ] || invalid S-F0 "the suite counts $F failed case(s)"
fi
n_pass="$(count '^PASS: ')"; n_fail="$(count '^FAIL: ')"
if [ "$P" -ge 0 ]; then
    [ "$n_pass" -eq "$P" ] || invalid S-NP "the suite printed $n_pass PASS line(s) but its RESULT counts $P passed"
    [ "$n_fail" -eq "$F" ] || invalid S-NF "the suite printed $n_fail FAIL line(s) but its RESULT counts $F failed"
fi
cx="$(count '^PASS: \(x\) .*\(rc=0, [1-9][0-9]* sub-checks passed, 0 failed\)$')"
[ "$cx" = 1 ] || invalid S-X "expected exactly one 'PASS: (x) … (rc=0, n sub-checks passed, 0 failed)' line, found $cx"
cy="$(count '^PASS: \(y\) .*\(rc=0, [1-9][0-9]* sub-checks passed, 0 failed\)$')"
[ "$cy" = 1 ] || invalid S-Y "expected exactly one 'PASS: (y) … (rc=0, n sub-checks passed, 0 failed)' line, found $cy"
zv="$(count '^PASS: \(z\) .*PAIR VALID')"; zn="$(count '^PASS: \(z\) .*NOT DEMONSTRATED')"
[ "$zv" = 1 ] || invalid S-ZV "expected exactly one 'PASS: (z) … PAIR VALID' line, found $zv"
[ "$zn" = 0 ] || invalid S-ZN "a (z) PASS line says NOT DEMONSTRATED ($zn line(s))"
[ "$nbad" -eq 0 ] && { echo "VERDICT-SET: VALID — rc 0, $P PASS lines printed and counted, 0 failed, (x) (y) (z) verdicts present, no inner mode"; exit 0; }
exit 1
