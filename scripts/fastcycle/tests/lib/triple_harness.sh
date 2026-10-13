#!/bin/sh
# triple_harness.sh - self-validation triple runner (spec 004, C-005, FR-022, SC-003).
# Purpose : run <tool> over golden-good / golden-bad(+classes) / negative-control fixtures.
# Usage   : triple_harness.sh --tool <exe> --fixtures <dir>
# Inputs  : <dir>/{golden-good,golden-bad,negative-control}/input, plus optional extra
#           golden-bad classes <dir>/golden-bad-*/input (C-005: one golden-bad per failure class).
#           <dir>/golden-bad/expected and <dir>/golden-bad-*/expected: strings the tool's stdout
#           MUST contain on that fixture (the tool must NAME the offending record; required file).
#           <dir>/golden-good/expected (optional): the EXACT stdout body the tool must print on
#           golden-good (C-005 "a specified body"; trailing newlines ignored; present-but-empty
#           means the body must be empty). Absent => rc-only check.
# Outputs : stdout, one JSON verdict line per fixture (fields below); NOT a C-002 "canonical
#           JSON" document -- see the C-002-exemption note below for why.
#           {"actual":N,"class":"..","expected":"0|1","fixture":"..","ok":bool}
# C-002 exemption (why this line has no "schema"/"body_hash" and does not harmonise the JSON
#   type of "actual" (bare int) with "expected" (quoted string)): common-conventions.md opens
#   with "Every contract in this directory inherits the clauses below [C-001..C-007]" -- i.e.
#   C-002's canonical-JSON-with-schema-and-body_hash requirement binds the *tools that
#   implement one of the 12 named contracts* under specs/004-fast-dev-cycles/contracts/. This
#   harness is not one of them: it is absent from both the contract "Tool map" table AND the
#   "no contract yet" list in common-conventions.md, and tasks.md (T007/T008/T010) instead
#   groups it with lib/fc_common.{py,sh} as "shared C-001..C-007 machinery" -- code that
#   EXERCISES and CHECKS other tools' C-001..C-007 compliance, not a contract tool whose own
#   primary output C-002 governs. Its per-fixture line is an ephemeral, in-process self-test
#   verdict (never a persisted qa-results/ document, never cited by an EvidencePath, never
#   given a "schema: <tool>/vN" of its own), and the RED test that defines T010's acceptance
#   criterion (tests/test_triple_harness_red.sh, "Exact JSON contract") locks in exactly the
#   shape above -- bare-int "actual", quoted-string "expected", no schema/body_hash -- as
#   BYTE-FOR-BYTE correct output, confirming this shape (not a C-002 document) is what T010 is
#   required to produce. Widening it to full C-002 shape would break that RED test's exact
#   match without adding any real evidentiary value (nothing here is ever a cited EvidencePath).
# Env     : FASTCYCLE_TOOL_TIMEOUT seconds per tool call (default 60; positive integer of at most
#           6 characters, else exit 2). At the bound the tool gets TERM, KILL 2 s later. The tool's
#           stdout goes to a temp FILE (never a pipe a descendant could hold open), and once the
#           tool call returns, for any reason, KILL is sent to its whole process group, so a
#           background descendant can neither delay the verdict nor outlive the call. A descendant
#           that escapes the group (its own setsid) is out of scope and not reaped. A HUP/INT/TERM
#           exits 2 and kills the tool group even when it lands between the fork of the tool and the
#           shell recording its pid (the running background job is found through `jobs`; bare-pid
#           lines and zsh's whole-line `[N] [+-] PID ...` lines are both understood).
# Exit    : 0 all as expected; 1 any mismatch; 2 cannot run / tool ERROR.
# Expected rc: good=0, bad==1 (the tool contract's "finding" code), negative-control=0.
# Naming rule (C-005): each golden-bad expected file must hold >=1 non-blank line (blank /
# whitespace-only lines are ignored; none left => exit 2). EVERY non-blank line (trimmed of
# leading/trailing space and tab) must appear in that fixture's stdout (stdout ONLY: the
# tool's stderr is discarded and is never evidence) as a WHOLE TOKEN: the character before and
# after the match must be the line start/end or one of the explicit delimiters listed on the
# next line (SPACE = 0x20, TAB = 0x09, BACKTICK = 0x60):
# Boundary set (exact): SPACE TAB , ; ( ) [ ] { } " ' = < > | BACKTICK
# Every other character (letters, digits, _ - . / : and every non-ASCII byte) can extend a
# record id, so it is NOT a boundary:
# rec-1 does not match rec-10, rec-1.5, rec-1/x, rec-1:0, rec-1<e-acute> or xrec-1, but matches
# "rec-1," "(rec-1)" "id=rec-1". A record id therefore cannot be followed by '.' or ':' in tool
# output; tools print ids delimited. Any line missing => mismatch (exit 1).
# Dangling flag (no value) or unknown argument => exit 2.
# Class directory names (golden-bad-*) must consist of [A-Za-z0-9._-] only, else exit 2 before
# anything runs: the name is emitted into the JSON line and split by the shell, so a quote,
# backslash, space or control character would corrupt both.
# Tool ERROR (harness exit 2, never a detection): any tool exit code other than 0 or 1
# (2 usage, 3 self-test failed, 4 BLIND, 124/137 timeout, 126/127, >=128 signal ...): the
# rule is "anything other than 0 or 1", so no specific code list can go stale (F16).
# "Could not look" is never "detected". A golden-bad that exits 1 but does not print the
# expected record name is a mismatch (exit 1).
tool=""; fx=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tool|--fixtures)
      [ $# -ge 2 ] || { echo "triple_harness: flag $1 requires a value" >&2; exit 2; }
      if [ "$1" = --tool ]; then tool=$2; else fx=$2; fi; shift 2 ;;
    *) echo "triple_harness: unknown arg $1" >&2; exit 2 ;;
  esac
done
TOOL_TIMEOUT_S=${FASTCYCLE_TOOL_TIMEOUT-60}
KILL_AFTER_S=2
# Positive decimal integer of at most 6 characters: GNU `timeout 0` DISABLES the bound (R3-F6).
case $TOOL_TIMEOUT_S in ''|*[!0-9]*|???????*) echo "triple_harness: FASTCYCLE_TOOL_TIMEOUT must be a positive integer of at most 6 digits: '$TOOL_TIMEOUT_S'" >&2; exit 2 ;; esac
[ "$TOOL_TIMEOUT_S" -ge 1 ] || { echo "triple_harness: FASTCYCLE_TOOL_TIMEOUT must be a positive integer of at most 6 digits (>= 1): '$TOOL_TIMEOUT_S'" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { echo "triple_harness: timeout(1) not found; cannot bound the tool" >&2; exit 2; }
# --tool must be a regular file (an executable directory such as /usr/bin is not a tool; -f is false for "").
[ -f "$tool" ] || { echo "triple_harness: bad --tool" >&2; exit 2; }
[ -d "$fx" ] || { echo "triple_harness: bad --fixtures" >&2; exit 2; }
# Classes: golden-bad first (required), then every golden-bad-* dir, then golden-good, negative-control.
bads="golden-bad"
for d in "$fx"/golden-bad-*; do
  [ -d "$d" ] || continue
  case ${d##*/} in *[!A-Za-z0-9._-]*) echo "triple_harness: class name outside [A-Za-z0-9._-] refused (exit 2): a directory under $fx" >&2; exit 2 ;; esac
  bads="$bads ${d##*/}"
done
wantdir=$(mktemp -d) || { echo "triple_harness: cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$wantdir"' EXIT
for c in $bads; do
  [ -s "$fx/$c/expected" ] || { echo "triple_harness: missing/empty $fx/$c/expected (C-005)" >&2; exit 2; }
  [ -f "$fx/$c/input" ] || { echo "triple_harness: missing $fx/$c/input" >&2; exit 2; }
  # Non-blank expected lines, trimmed. Blank-only file => refuse (an empty needle matches anything).
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$fx/$c/expected" | sed '/^$/d' >"$wantdir/$c"
  [ -s "$wantdir/$c" ] || { echo "triple_harness: $fx/$c/expected has no non-blank line (C-005)" >&2; exit 2; }
done
for c in golden-good negative-control; do
  [ -f "$fx/$c/input" ] || { echo "triple_harness: missing $fx/$c/input" >&2; exit 2; }
done
DELIMS=$(printf ' \t,;()[]{}"'"'"'=<>|`')
# names_all <wantfile> <output>: every line of <wantfile> appears in <output> as a whole token.
# awk assumption: verified on GNU Awk 5.1 only (index(x,"")==1, substr(s,0,1) semantics); other awks UNCONFIRMED.
names_all() {
  printf '%s\n' "$2" | LC_ALL=C awk -v wf="$1" -v d="$DELIMS" '
    function isb(c) { return c != "" && index(d, c) > 0 }
    BEGIN { n = 0; while ((getline l < wf) > 0) { want[++n] = l; hit[n] = 0 } }
    { line = " " $0 " "
      for (i = 1; i <= n; i++) {
        w = want[i]; pos = 1
        while ((k = index(substr(line, pos), w)) > 0) {
          st = pos + k - 1; b = substr(line, st - 1, 1); a = substr(line, st + length(w), 1)
          if (isb(b) && isb(a)) { hit[i] = 1; break }
          pos = st + 1
        }
      } }
    END { for (i = 1; i <= n; i++) if (!hit[i]) exit 1; exit 0 }'
}
# run_tool <input> : runs the tool with stdout to $wantdir/out (a FILE), stderr discarded, bounded.
# timeout(1) leads its own process group (pgid == its pid); once it returns, KILL the whole group so
# a background descendant cannot outlive the call (a pipe such a descendant holds open used to block
# the verdict, R5-F1). Sets $a to the exit status; the tool's stdout is left in $wantdir/out.
tpid=""
kill_group() {
  case $tpid in
    ''|*[!0-9]*) ;;
    *) if [ "$tpid" -gt 1 ]; then kill -s KILL -- "-$tpid" 2>/dev/null; fi ;;
  esac
  tpid=""
}
# Kill every still-running background job (pid, then its process group): covers the fork -> `tpid=$!`
# window where tpid is not recorded yet. `jobs -rp` lists RUNNING jobs only, so a reaped child's
# reusable pid is never signalled; the second form is a fallback for a shell without -r.
# shellcheck disable=SC2329 # invoked from the trap string `trap 'kill_group; reap_jobs; exit 2' HUP
# INT TERM` below; a bareword call that appears only inside a quoted trap-action string is not
# recognised by shellcheck's usage scan as invoking the function (verified false positive).
reap_jobs() {
  # shellcheck disable=SC3045 # -r is not POSIX; the fallback form covers shells without it
  { jobs -rp || jobs -p; } >"$wantdir/jobs" 2>/dev/null
  while read -r j; do
    # zsh (also as `sh`) prints whole job lines `[1]  + 237188 running  cmd`, not bare pids: take the pid
    # of a `[N] [+-] PID ...` line ONLY; any other non-numeric line is skipped (R7-F1).
    case $j in ''|*[!0-9]*) j=$(printf '%s\n' "$j" | sed -n 's/^\[[0-9][0-9]*\][ +-]*\([0-9][0-9]*\) .*$/\1/p') ;; esac
    case $j in ''|*[!0-9]*) continue ;; esac
    if [ "$j" -gt 1 ]; then kill -s KILL "$j" 2>/dev/null; kill -s KILL -- "-$j" 2>/dev/null; fi
  done <"$wantdir/jobs"
}
# A signal while a tool runs: kill its group, then exit 2 (the EXIT trap above removes the temp dir).
trap 'kill_group; reap_jobs; exit 2' HUP INT TERM
run_tool() {
  if [ -x "$tool" ]; then timeout -k "$KILL_AFTER_S" "$TOOL_TIMEOUT_S" "$tool" "$1" >"$wantdir/out" 2>/dev/null </dev/null &
  else timeout -k "$KILL_AFTER_S" "$TOOL_TIMEOUT_S" sh "$tool" "$1" >"$wantdir/out" 2>/dev/null </dev/null & fi
  tpid=$!
  wait "$tpid"; a=$?
  kill_group
}
rc_all=0; err=0
for c in $bads golden-good negative-control; do
  run_tool "$fx/$c/input"
  out=$(cat "$wantdir/out")
  case "$a" in 0|1) ;; 124|137) echo "triple_harness: tool timed out after ${TOOL_TIMEOUT_S}s on $c (exit $a)" >&2; err=1 ;; *) err=1 ;; esac
  case "$c" in
    golden-bad*)
      exp=1
      [ "$a" -eq 1 ] && ok=true || ok=false
      # C-005: an rc-1 golden-bad that does not name the expected record is not a detection.
      if [ "$a" -eq 1 ] && ! names_all "$wantdir/$c" "$out"; then ok=false; fi ;;
    *)
      exp=0; [ "$a" -eq 0 ] && ok=true || ok=false
      # C-005: golden-good MUST also return its specified body when an expected file is present.
      if [ "$c" = golden-good ] && [ "$a" -eq 0 ] && [ -f "$fx/golden-good/expected" ]; then
        want=$(cat "$fx/golden-good/expected")
        [ "$out" = "$want" ] || ok=false
      fi ;;
  esac
  [ "$ok" = true ] || rc_all=1
  printf '{"actual":%s,"class":"%s","expected":"%s","fixture":"%s","ok":%s}\n' "$a" "$c" "$exp" "$c" "$ok"
done
[ "$err" -eq 1 ] && { echo "triple_harness: tool error (exit code other than 0 or 1)" >&2; exit 2; }
exit "$rc_all"
