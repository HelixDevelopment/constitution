#!/usr/bin/env bash
# tests/release/test_release_tooling_mutations.sh — paired mutation test (§1.1, §11.4.194(6)(d)) of the
# three release scripts and their suites in tests/release/.
#
# Each mutant is one exact text replacement in a temp copy of a script (the replacement must match
# exactly once, otherwise the mutant is reported STALE and the test fails); the matching suite is then
# run against the copy (TAR_SCRIPT / DRF_SCRIPT / RRE_SCRIPT) and must FAIL. A control copy without a
# change must PASS, so a broken harness cannot read as "all killed".
#
# Mutants: T2-T4, T6, D1, D5 are the reviewer's mutants of docs/qa/review_rel734c_2026_11_11.md,
# adopted verbatim (the same replaced line, CON-227); T5 is the reviewer's mutant "gitea rc 3 reported
# as OK" re-applied to the rc 3 branch rewritten by CON-233; O1-O7 are the fixer's own; round 2 adds F1, F6 and the adopted reviewer mutants R2, R5, R6;
# round 3 adopts the reviewer's N1 (redaction without the g flag), N2 (400-byte cap removed) and N4 (F6 "names
# CHANGELOG.md" satisfied by git's own text; the script's own message is now the one final line, so the same
# mutant is applied to that line) on the single redact-then-cut helper, and adds the fixer's own P1-P10.
#
# Round 4 (structural, CON-234 class): the helper, the temp-file handling and the captured stderr were
# rewritten, so every earlier mutant whose replaced text no longer exists is re-applied to the line that
# now does the same job (named in the comment beside it); the reviewer's round-3 mutants Q1-Q12 are adopted
# (verbatim where their text still exists: Q4, Q5, Q6, Q10; re-applied to the new construct otherwise), and
# the fixer adds S1-S14. A helper mutant is run against tests/release/test_redact_cut.sh first and, when
# that suite passes, against the tag suite (end to end through the real tag script).
#
# Round 5 (structural, CON-234 class, docs/qa/con227_234_2026_11_11/round5/threat_model.md): network-command
# stderr is classified (rc_err_class) and never printed, caller and server values are validated, the publisher's
# token goes to curl on stdin. Mutants whose replaced text is gone are re-applied to the line that now does the
# same job (named in the comment beside it); the reviewer's surviving round-4 mutants V3, V4, V5, V8, V11, V12
# and V13 are adopted (V13 also on the publisher and the derive script), and the fixer adds U1-U17. Round 4
# recorded Q12 and S11 as EQUIVALENT ("no observable difference"); that was wrong: the exit status differs
# (143/129 through the trap, killed by the signal without it), shown by
# docs/qa/con227_234_2026_11_11/round5/probe_trap_exit_status.py, so they are ordinary m lines now.
#
# Round 7 (structural, CON-234 class, docs/qa/con227_234_2026_11_11/round7/threat_model.md): rc_env_clean
# re-executes each script with an empty environment and rebuilds it from the allow-list, so mutants whose replaced
# text named rc_env_lockdown on a script's first line are re-applied to the rc_env_clean line; the reviewer's
# round-6 mutants Z1-Z14 are adopted (there is no Z10; Z6 is recorded equivalent on its meq line, Z8 and Z9 are
# mp lines killed by C49), and the fixer adds W1-W13. Signals (L5): every suite runs in the background and is
# waited for, so a HUP, INT or TERM to the harness is handled at once: TERM to its own suite, KILL after 20 s,
# then exit 128 + the signal number. A suite that SKIPs a HUP case (SIGHUP ignored when it started, L4) cannot
# kill a HUP mutant: such a survivor is INCONCLUSIVE, never killed.
#
# Round 8 (structural, CON-234 class, docs/qa/con227_234_2026_11_11/round8/threat_model.md): the lockdown keeps the 13
# locale names exactly and checks the value of every allow-listed name, the re-executed process closes inherited
# descriptors, never re-executes again and refuses when sourced. Z2 and Z11 (their LC_* line is gone) are re-applied
# to the lockdown loop; the reviewer's round-7 mutants A1-A14 are adopted (A4 and A5 re-applied, A5b is the round-7
# shape itself, A10 and A14 recorded equivalent on their meq lines), and the fixer adds B1-B12.
#
# Round 9 (CON-234 class, docs/qa/con227_234_2026_11_11/round9/threat_model.md): _rc_env_closefds lists DIR/fd with
# any number of digits and fails closed, the common value checks are split out (_rc_env_common_ok) and also applied to
# RELEASE_ENV_KEEP names, which may no longer name a GIT_*, SSH_*, CURL_*, GH_*, GLAB_*, GITLAB_*, LD_*, *_URL or *_URI
# variable or a reserved name. A4, B1, B11 and B12 (their line changed) are re-applied to the line that now does the
# same job; the reviewer's round-8 mutants R1, R4, R5, R6, R8, R9, R10, D1 and E1 are adopted as RR1, RR4, RR5, RR6,
# RR8, RR9, RR10, RD1 and RE1 (the names R5, R6 and D1 were taken); E1 mutates tests/release/env_allow.sh and is run
# against tests/release/test_channel_census.sh (ENV_ALLOW_LIB); the fixer adds G1-G10 (descriptors, F1) and H1-H4
# (RELEASE_ENV_KEEP, F7).
#
# Round 10 (CON-234 class, docs/qa/con227_234_2026_11_11/round10/threat_model.md): RELEASE_ENV_KEEP also refuses the
# names ssh sends (a static LANG* LC_* COLORTERM NO_COLOR class and the SendEnv patterns _rc_env_sendenv reads at run
# time, failing closed), its words are never glob-expanded, and the locale names follow a locale grammar
# (_rc_env_locale_ok). B5 and RR10 are re-applied to the grammar; A10 is no longer recorded equivalent (the round-9
# review showed it is not) and is a property mutant killed by K10 R9-2; the reviewer's round-9 mutants Q1, Q4, Q5 and
# Q11 are adopted verbatim as QQ1, QQ4, QQ5 and QQ11 (Q1-Q12 were taken); the fixer adds J1-J5 (the other refused
# prefixes), K1-K15 (the SendEnv refusal), L1-L3 (the locale grammar), NG1 (glob) and CW1-CW10 (every other credential
# word). A mutant name used twice is now counted stale (dupname).
#
# Round 11 (structural, R10-1 and R10-2 of the round-10 review, docs/qa/con227_234_2026_11_11/round11/mutants.md):
# every network child is started through rc_net (a fixed, value-checked network allow-list), and the round-10
# SendEnv reader is removed. T3, T4, T6, U7, X8, X9b, Y6, Z6 (their line now says rc_net) are re-applied to the same
# line; Z1 is re-applied to the lockdown list (the network list has its own mutant NN2); B5 and RR10 are re-applied
# to the codeset check of the locale grammar; K7-K15 are retired with the reader they mutated (each is mapped in
# mutants.md to the rc_net mutant that kills the same property). The reviewer's round-10 mutants R01-R22 are adopted
# as RT01-RT22 where their code still exists (RT12 and RT20 recorded equivalent with their probes; R01-R11, R14-R16
# and R22 mutated the removed reader: N/A, mapped in mutants.md); the fixer adds NN1-NN16 (rc_net, its call sites and
# the locale grammar) and GN1-GN6 (the network-spawn gate, channel_census.py netgate, run against
# tests/release/test_channel_census.sh with CEN_PY).
#
# Round 12 (structural, F1 F2 of the round-11 review, docs/qa/con227_234_2026_11_11/round12/mutants.md): the
# network-spawn gate reads the shell syntax and reports every command name it does not classify, with no lookup on
# the host (corrected 2026-11-13, F3 of the round-12 review: this is not a default-deny of the scripts; the parser
# and the per-builtin rules were deny-lists, see round 13). GN1-GN6 are
# re-applied to the round-12 gate; the fixer adds NR1-NR33 (one rule of the gate each, killed by its control needle
# by name); the round-11 reviewer's mutants RM2, RM9, RM10, RM12, RM19, RM20, RM21, RM25-RM28 and the added-line
# mutants RM30, RM30b, RM31-RM34 are adopted verbatim (the added-line mutants die by C53, the gate run by the
# suite of the mutated script; RM20 by the R12 F2 drop list); O4, O7, U3, X11, Y20 and Z7 follow the round-12
# lines (sqlite3 -safe, unset -v).
#
# Round 13 (structural, F1-F3 of the round-12 review, docs/qa/con227_234_2026_11_11/round13/mutants.md): the
# network-spawn gate has two layers. Layer 1, the byte pin (tests/release/netgate_pin.tsv), pins every line, site,
# awk/sed program and written name of the four release files and refuses any difference; it is the only layer that
# denies by default. Layer 2, the analyser, refuses every construct, builtin and option outside a closed positive
# grammar (fail closed). The round-12 mutants whose text is gone (GN5, GN6, NR2-NR5, NR8, NR9, NR12, NR13, NR15,
# NR16, NR18-NR27, NR29, NR32, NR33) are re-applied to the round-13 rule that does the same job; the others keep
# their round-12 text. MR5x-MR10y re-apply the round-12 reviewer's mutants MR5-MR10 (MR1-MR4 and MR9 are NR27,
# NR26, NR23, NR22 and NR8), MS1 is adopted verbatim; the fixer adds PN1-PN19 (the pin, killed by part 2d of the
# channel suite; PN13 is recorded equivalent on its meq line with its probe) and AN1-AN42 (the analyser rules, each
# killed by its control needle; AN40-AN42 by the O2 checks: a finding names its line by key, never by its text;
# AN16 and AN19 are not used). The block is generated by
# docs/qa/con227_234_2026_11_11/round13/tools/mut13.py (one spec, quoted by the tool, never by hand).
#
# Usage: bash tests/release/test_release_tooling_mutations.sh [--only NAME]   (round 8, N5: a NAME that is no mutant
# and not "control" exits 2; the suites run with RELEASE_TESTS_ALLOW_SKIP=1, N6)
# Exit 0 when the control passes and every mutant is killed or (meq lines only) recorded equivalent with its probe;
# exit 1 on a survivor, a stale mutant or a failed control; exit 4 (round 14, F5 of the round-13 review) when no
# such failure exists but a mutant recorded EQUIVALENT (meq line) was killed: the record or the killing property is
# wrong, or the property is nondeterministic (round 13: RT20 was killed once by C43), so the run is never green;
# exit 3 when SIGHUP is ignored or a result is INCONCLUSIVE. Last line "RESULT: killed=N survived=M equivalent=E
# ... inconclusive=I equivalent_killed=K"; killed counts the m and mp kills only, a killed meq mutant counts in
# equivalent_killed (never in killed or equivalent), so the standing run's killed/equivalent totals keep their meaning. Equivalent mutants:
# X12 (round 6; rc_env_lockdown un-exports _rpg_tok; X12b removes the lockdown too and is killed), Z6 (round 7) and
# A14 (round 8), each with its evidence on its meq line (A10 was recorded equivalent until round 10; it is not).
# Round 6 adds mp lines: a mutant counts as killed only when a FAIL line of the suite matches the extended regex
# of the property it targets (a kill by an unrelated FAIL is reported as a failure). STALE_ONLY=1 applies every
# mutant and runs nothing, not even the controls (it checks that each replaced text is still found exactly once).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
ONLY=""; [ "${1:-}" = "--only" ] && ONLY="${2:-}"
W="$(mktemp -d "${TMPDIR:-/tmp}/rtm_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
# round 7 (L5): a signal ends the harness. The suites run in the background and the harness waits for them, so a
# trapped signal interrupts the wait at once (bash runs a trap only after a FOREGROUND child ends); the handler
# sends TERM to the harness's own running suite (its pid, > 1), waits up to 20 s, then KILLs it, and exits
# 129/130/143 (the EXIT trap removes the work directory). A handler that returns would let the harness run on.
RUNPID=""
onsig() { local i=0
  if [ -n "$RUNPID" ] && [ "$RUNPID" -gt 1 ] 2>/dev/null; then
    kill -TERM "$RUNPID" 2>/dev/null
    while kill -0 "$RUNPID" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done
    kill -0 "$RUNPID" 2>/dev/null && kill -KILL "$RUNPID" 2>/dev/null
  fi
  exit "$1"; }
trap cleanup EXIT; trap 'onsig 129' HUP; trap 'onsig 130' INT; trap 'onsig 143' TERM
runbg() { "$@" & RUNPID=$!; wait "$RUNPID"; local r=$?; RUNPID=""; return "$r"; }
killed=0 survived=0 stale=0 ctrl_bad=0 equivalent=0 inconclusive=0 matched=0 eqkilled=0   # matched: mutants --only selected (round 8, N5); eqkilled: meq mutants killed (round 14, exit 4)
# round 7 (L4): under an ignored SIGHUP (nohup) the suites SKIP their SIGHUP cases (bash cannot trap a signal that
# was ignored when it started); a mutant that survives while its suite skipped such a case is INCONCLUSIVE, never
# killed and never "survived", and the harness exits 3. The controls still run.
. "$HERE/env_allow.sh"
HUPIGN=0; if hup_ignored; then HUPIGN=1; echo "SKIP: SIGHUP is ignored in this process (nohup or an ignoring parent): the SIGHUP cases of the suites are skipped, mutants they would kill are INCONCLUSIVE (exit 3)"; fi
# final_exit: the exit status from the counters, in one place (round 14, F5): 1 on a survivor, a stale mutant or a
# failed control; else 4 when a meq mutant was killed; else 3 when SIGHUP is ignored or a result is INCONCLUSIVE; else 0
final_exit() {
  { [ "$survived" -eq 0 ] && [ "$stale" -eq 0 ] && [ "$ctrl_bad" -eq 0 ]; } || exit 1
  [ "$eqkilled" -eq 0 ] || exit 4
  { [ "$HUPIGN" -eq 0 ] && [ "$inconclusive" -eq 0 ]; } || exit 3
  exit 0
}
# RTM_EXIT_SELFTEST="SURVIVED STALE CTRL_BAD EQKILLED HUPIGN INCONCLUSIVE" (six integers): run nothing and exit with
# the status final_exit gives for these counters (test_channel_census.sh N5b); a malformed value is exit 2
if [ -n "${RTM_EXIT_SELFTEST:-}" ]; then
  [[ $RTM_EXIT_SELFTEST =~ ^[0-9]+( [0-9]+){5}$ ]] || { echo "RTM_EXIT_SELFTEST: six integers expected" >&2; exit 2; }
  read -r survived stale ctrl_bad eqkilled HUPIGN inconclusive <<<"$RTM_EXIT_SELFTEST"
  final_exit
fi

TAR="$ROOT/scripts/release/tag_and_release.sh"; DRF="$ROOT/scripts/release/derive_release_facts.sh"
RRE="$ROOT/scripts/release/render_release_entry.py"
TPL="$ROOT/docs/release/helixconstitution-v73.4_entry.template.md"   # CON-423: the v73.4 entry template, mutated in a copy and passed as RRE_TEMPLATE
RFS="$ROOT/scripts/full_suite/run_full_suite.py"   # B-M1: the one source of the verdict words, copied beside every renderer copy
LIB="$ROOT/scripts/release/redact_cut.sh"; PUB="$ROOT/scripts/release_publish_gitea.sh"
CENPY="$HERE/channel_census.py"   # round 11: the network-spawn gate, mutated in a copy and passed as CEN_PY
ECPY="$HERE/env_census.py"   # round 11: the runtime recorder, mutated in a copy and passed as ENV_CENSUS_PY (race check)
EAL="$HERE/env_allow.sh"   # round 9: the suites' helper (suite_exit, E1), mutated in a copy and passed as ENV_ALLOW_LIB
# place SRC (a script, or the helper) into its own directory D, laid out like the repository (B-M2, 2026-11-16):
# D/scripts/release/ holds the helper, the tag script and the other release scripts, D/scripts/ the publisher,
# D/config/forge/hosts.tsv the host table the helper's rc_gitea_binding reads (two directories above the helper),
# D/scripts/full_suite/ the runner the renderer reads its verdict words from (B-M1). The helper copy is the mutated
# one when SRC is the helper.
HOSTS="$ROOT/config/forge/hosts.tsv"
setup_dir() { # setup_dir D SRC -> prints the path of SRC's copy
  local d="$1" src="$2" s="$1/scripts"; mkdir -p "$s/release" "$d/config/forge"; cp -- "$HOSTS" "$d/config/forge/hosts.tsv"
  case "$src" in
    *redact_cut.sh) cp -- "$src" "$s/release/redact_cut.sh"; cp -- "$TAR" "$s/release/tag_and_release.sh"; cp -- "$PUB" "$s/release_publish_gitea.sh"
                    printf '%s' "$s/release/redact_cut.sh" ;;
    *release_publish_gitea.sh) cp -- "$LIB" "$s/release/redact_cut.sh"; cp -- "$src" "$s/release_publish_gitea.sh"; printf '%s' "$s/release_publish_gitea.sh" ;;
    *) cp -- "$LIB" "$s/release/redact_cut.sh"; cp -- "$src" "$s/release/$(basename "$src")"
       case "$src" in *render_release_entry.py) mkdir -p "$s/full_suite"; cp -- "$RFS" "$s/full_suite/run_full_suite.py" ;; esac
       printf '%s' "$s/release/$(basename "$src")" ;;
  esac
}

# mutate NAME SRC OLD NEW [OLD2 NEW2 ...] -> prints the path of the mutated copy, or nothing when any OLD is not
# found exactly once (round 6: a mutant may make several replacements, each checked)
mutate() {
  local d="$W/$1" src="$2" out; shift 2
  out="$(setup_dir "$d" "$src")"
  python3 -I - "$src" "$out" "$@" <<'PY' || return 1
import sys
src, out = sys.argv[1:3]  # out is the copy placed by setup_dir; it is rewritten with the replacements
pairs = sys.argv[3:]
if not pairs or len(pairs) % 2:
    sys.exit(1)
s = open(src, encoding="utf-8").read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if s.count(old) != 1:
        sys.exit(1)
    s = s.replace(old, new)
open(out, "w", encoding="utf-8").write(s)
PY
  printf '%s' "$out"
}
suite_for() { case "$1" in *tag_and_release.sh) echo "TAR_SCRIPT $HERE/test_tag_and_release.sh" ;;
  *redact_cut.sh) echo "TAR_SCRIPT $HERE/test_tag_and_release.sh" ;;
  *release_publish_gitea.sh) echo "PUBLISH_SCRIPT $HERE/test_publish_gitea.sh" ;;
  *derive_release_facts.sh) echo "DRF_SCRIPT $HERE/test_derive_release_facts.sh" ;;
  *render_release_entry.py) echo "RRE_SCRIPT $HERE/test_render_release_entry.sh" ;;
  *_entry.template.md) echo "RRE_TEMPLATE $HERE/test_render_release_entry.sh" ;;
  *env_allow.sh) echo "ENV_ALLOW_LIB $HERE/test_channel_census.sh" ;;
  *channel_census.py) echo "CEN_PY $HERE/test_channel_census.sh" ;;
  *env_census.py) echo "ENV_CENSUS_PY $HERE/test_redact_cut.sh" ;; esac; }
runs() { # runs SCRIPTCOPY ORIGINAL -> rc of the matching suite against the copy
  local v t c="$1" tmp; read -r v t <<<"$(suite_for "$2")"
  # every suite run gets its own TMPDIR inside $W, so files a mutant leaves behind (a kept run directory,
  # persisted stderr) are removed with $W and never pile up in the caller's TMPDIR
  tmp="$(mktemp -d "$W/tmp.XXXXXX")"; : "${tmp:?}"
  # a helper mutant: its own unit suite first, then the tag suite against the tag script beside it
  case "$2" in *redact_cut.sh)
    runbg env TMPDIR="$tmp" RELEASE_TESTS_ALLOW_SKIP=1 RC_LIB="$1" bash "$HERE/test_redact_cut.sh" >"$W/last.out" 2>&1 || return 1
    c="$(dirname "$1")/tag_and_release.sh" ;; esac
  # RELEASE_TESTS_ALLOW_SKIP=1 (round 8, N6): a suite exits 77 on a SKIPPED case; the harness judges skipped cases
  # itself (hupskip), so it asks for the plain pass/fail status
  runbg env TMPDIR="$tmp" RELEASE_TESTS_ALLOW_SKIP=1 "$v=$c" bash "$t" >"$W/last.out" 2>&1
}
# hupskip: the last suite run skipped a SIGHUP case (round 7, L4)
hupskip() { grep -q '^SKIP .*HUP' "$W/last.out"; }

# control: unmodified copies pass their suites
for f in "$TAR" "$DRF" "$RRE" "$TPL" "$PUB" "$LIB" "$EAL" "$CENPY" "$ECPY"; do
  [ -n "$ONLY" ] && [ "$ONLY" != control ] && continue
  [ -n "${STALE_ONLY:-}" ] && continue   # round 7: STALE_ONLY checks the replaced texts only (no suite runs)
  cpy="$(setup_dir "$W/ctrl_$(basename "$f")" "$f")"
  if runs "$cpy" "$f"; then echo "PASS control $(basename "$f") passes its suite"
  else ctrl_bad=$((ctrl_bad+1)); echo "FAIL control $(basename "$f") does not pass its suite: $(tail -n 1 "$W/last.out") [failing checks: $(grep -a '^FAIL' "$W/last.out" | cut -c1-200 | tr '\n' '|')]"; fi
done

# round 10: a mutant name used twice is an error (the round-9 review's Q1, Q4, Q5 and Q11 collided with the round-4
# names Q1-Q12, so --only Q1 ran two different mutants); every m, mp and meq line registers its name here first
NAMES=" "
dupname() { case "$NAMES" in *" $1 "*) stale=$((stale+1)); echo "FAIL $1 DUPLICATE: two mutants have this name"; return 0 ;; esac; NAMES="$NAMES$1 "; return 1; }
m() { # m NAME SRC OLD NEW [OLD2 NEW2 ...]
  dupname "$1" && return 0
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 0
  matched=$((matched+1))
  local p; p="$(mutate "$@")" || { stale=$((stale+1)); echo "FAIL $1 STALE: the replaced text is not found exactly once in $(basename "$2")"; return 0; }
  if [ -n "${STALE_ONLY:-}" ]; then echo "PASS $1 applies"; return 0; fi
  if runs "$p" "$2"; then if hupskip; then inconclusive=$((inconclusive+1)); echo "SKIP $1 INCONCLUSIVE: survived while its suite skipped a SIGHUP case"; else survived=$((survived+1)); echo "FAIL $1 SURVIVED ($(tail -n 1 "$W/last.out"))"; fi
  else killed=$((killed+1)); echo "PASS $1 killed ($(grep -m1 '^FAIL' "$W/last.out" | cut -c1-120))"; fi
}

meq() { # meq NAME SRC OLD NEW EVIDENCE: a mutant recorded as EQUIVALENT (no difference any suite can observe) with the
  # probe that shows why; it must still apply exactly once, and it is re-run every time so a later change
  # that makes it killable is reported (then turn it into an m line with a killing test)
  dupname "$1" && return 0
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 0
  matched=$((matched+1))
  local p; p="$(mutate "$1" "$2" "$3" "$4")" || { stale=$((stale+1)); echo "FAIL $1 STALE: the replaced text is not found exactly once in $(basename "$2")"; return 0; }
  if [ -n "${STALE_ONLY:-}" ]; then echo "PASS $1 applies"; return 0; fi
  if runs "$p" "$2"; then equivalent=$((equivalent+1)); echo "PASS $1 equivalent, survives as recorded (evidence: $5)"
  else eqkilled=$((eqkilled+1)); echo "FAIL $1 EQUIVALENT-KILLED: recorded equivalent but killed; review the record or the killing property (exit 4) ($(grep -m1 '^FAIL' "$W/last.out" | cut -c1-120))"; fi
}

mp() { # mp NAME PATTERN SRC OLD NEW [OLD2 NEW2 ...]: killed only when the suite fails AND one of its FAIL lines
  # matches the extended regex PATTERN, so the mutant is shown killed by the property it targets (round 6)
  dupname "$1" && return 0
  [ -n "$ONLY" ] && [ "$ONLY" != "$1" ] && return 0
  matched=$((matched+1))
  local n="$1" pat="$2" p; shift 2
  p="$(mutate "$n" "$@")" || { stale=$((stale+1)); echo "FAIL $n STALE: the replaced text is not found exactly once in $(basename "$1")"; return 0; }
  if [ -n "${STALE_ONLY:-}" ]; then echo "PASS $n applies"; return 0; fi
  if runs "$p" "$1"; then if hupskip; then inconclusive=$((inconclusive+1)); echo "SKIP $n INCONCLUSIVE: survived while its suite skipped a SIGHUP case"; else survived=$((survived+1)); echo "FAIL $n SURVIVED ($(tail -n 1 "$W/last.out"))"; fi
  elif grep '^FAIL' "$W/last.out" | grep -Eq -- "$pat"; then killed=$((killed+1)); echo "PASS $n killed by its property ($(grep '^FAIL' "$W/last.out" | grep -Em1 -- "$pat" | cut -c1-120))"
  elif hupskip; then inconclusive=$((inconclusive+1)); echo "SKIP $n INCONCLUSIVE: killed, but not by its property /$pat/, while its suite skipped a SIGHUP case"
  else survived=$((survived+1)); echo "FAIL $n killed, but not by its property /$pat/ ($(grep -m1 '^FAIL' "$W/last.out" | cut -c1-120))"; fi
}

# --- reviewer mutants of the v73.4 review, verbatim (T2-T6, D1, D5); T5 re-applied to the CON-233 rc 3 line ---
m T2 "$TAR" 'is_ok() { local s; s="$(remote_state "$1")"; [ "$s" = "$SHA $TAGOBJ $SHA" ]; }' \
            'is_ok() { local s; s="$(remote_state "$1")"; [ "${s%% *}" = "$SHA" ]; }'
m T3 "$TAR" '    [ "$ro" = "$(rc_net git rev-parse "refs/tags/$TAG")" ] || abort "$r has a different $TAG object ($ro); never replaced (§11.4.113)"' \
            '    true'
m T4 "$TAR" '[ -z "$(rc_net git status --porcelain --untracked-files=normal 2>/dev/null)" ] || abort "working tree is not clean"' 'true'
m T6 "$TAR" '[ "$(rc_net git rev-parse HEAD)" = "$SHA" ] || abort "HEAD $(rc_net git rev-parse HEAD) != $SHA"' 'true'
GT='        3) if printf '"'"'%s\n'"'"' "$x_gitea" | grep -q '"'"'^SKIPPED-NO-TOKEN:'"'"'; then gap'
m T5 "$TAR" "$GT" '        3) if true; then printf "OK RELEASE $spec SKIPPED-OR-REFUSED rc=3 (token absent or precondition)"; gap'
m D1 "$DRF" 'closure_day "$vclos" && [ "$CDAY" \> "$PREV_DATE" ]' 'closure_day "$vclos" && ! [ "$CDAY" \< "$PREV_DATE" ]'   # round 3: V is a bash loop over calendar days (N5); the same > to >= boundary mutant
m D5 "$DRF" "(reproduction_state!='UNSET' or investigation_state!='UNSET')" "(reproduction_state!='UNSET' )"
# --- fixer's earlier mutants; O1 and the other fetch-print mutants re-applied to the round-5 fetch line, where
# git's message is classified and never printed (FP); each mutant prints it again in its own way ---
FP='  [ "$frc" -eq 0 ] || abort "fetch of $r main failed $(withheld git "$frc" "$(xcls "$x_fetch" "$frc")")"'
m O1 "$TAR" "$FP" '  [ "$frc" -eq 0 ] || { printf '"'"'%s\n'"'"' "$x_fetch"; abort "fetch of $r main failed"; }'                      # raw message
m O2 "$TAR" "$GT" '        3) if true; then gap'
m O3 "$DRF" 'if [ -e "$QFAIL" ]; then' 'if false; then'
m O4 "$DRF" 'q() { sqlite3 -safe -readonly -batch -noheader "$DB" "$1" || { echo query >>"$QFAIL"; return 1; }; }' 'q() { sqlite3 -safe -readonly -batch -noheader "$DB" "$1"; }'
m O7 "$DRF" 'qa() { sqlite3 -safe -readonly -batch -noheader -ascii "$DB" "$1" || { echo query >>"$QFAIL"; return 1; }; }' 'qa() { sqlite3 -safe -readonly -batch -noheader -ascii "$DB" "$1"; }'
m O5 "$DRF" 'exec 4>&1 >"$DBDIR/out"' 'exec 4>&1'
m O6 "$RRE" '    if unrendered:' '    if False:'
# --- round 2: F1, R2, R5, F6, R6 (re-applied to the round-5 lines) ---
m F1 "$TAR" "$FP" '  [ "$frc" -eq 0 ] || { printf '"'"'%s\n'"'"' "$x_fetch" | rc_redact_cut 400; abort "fetch of $r main failed"; }'   # the round-4 design: redacted message printed
m R2 "$TAR" "grep -q '^SKIPPED-NO-TOKEN:'; then gap" "grep -q 'SKIPPED-NO-TOKEN'; then gap"
m R5 "$DRF" '"$DBDIR/out" "$DBDIR/qfail" "$EXTERR"; do' '"$DBDIR/qfail" "$EXTERR"; do'
m R6 "$TAR" '      x_gitea="$(pub "$gtv" "${args[@]}" 2>&1 >/dev/null)"; rc=$?' \
            '      x_gitea="$(pub "$gtv" "${args[@]}" 2>&1 >/dev/null)"; rc=$?; printf "%s" "$x_gitea" >"$RUNDIR/gitea.err"'   # round 6: re-applied, the publisher runs through pub
m F6 "$DRF" 'git cat-file -e "$B:CHANGELOG.md" 2>/dev/null || echo changelog >>"$QFAIL"' 'git cat-file -e "$B:CHANGELOG.md" 2>/dev/null || :'
# --- round 3: N1, N2, N4, P1-P10, re-applied to the round-5 helper and lines where the old text is gone ---
m N1 "$LIB" 'k = index(w, "="); S = S + k; L = L - k; put("<redacted>"); pos = S + 10; continue }' \
            'k = index(w, "="); S = S + k; L = L - k; put("<redacted>"); break }'          # one parameter per line only
m N2 "$LIB" 'awk -v max="$n"' 'awk -v max=40000'                                            # byte cap removed
m N4 "$DRF" "grep -q '^changelog\$' \"\$QFAIL\" && printf 'derive_release_facts: CHANGELOG.md is missing at the base %s; no facts printed\\n' \"\$B\" >&3" "grep -q '^changelog\$' \"\$QFAIL\" && printf 'derive_release_facts: no facts printed\\n' >&3"
m P1 "$TAR" '| grep -m 1 '"'"'^release_publish_gitea: '"'"' | rc_redact_cut "$2"; }' '| grep -m 1 '"'"'^release_publish_gitea: '"'"' | head -c "$2"; }'   # own line not redacted (oneline is gone)
m P2 "$LIB" '      line = $0
      if (length(line) > lmax) {' '      line = substr($0, 1, max)
      if (length(line) > lmax) {'                                                                   # cut before redacting
m P3 "$LIB" 'match(substr(low, i + 3), /@[^@]*$/)' 'match(substr(low, i + 3), /@/)'                   # stop at the first "@"
m P4 "$PUB" '"$crc" "$cls" >&3' '"$crc" "$x_curl" >&3'                                              # curl's message printed (err.out is gone)
m P5 "$TAR" '  [ -f "$EXTERR" ] && rc_redact_cut 2000 mark <"$EXTERR" >&3' '  [ -f "$EXTERR" ] && cat "$EXTERR" >&3'
m P6 "$TAR" '(configuration or precondition: $gmsg)"; fi ;;' '(configuration or precondition: $(printf '"'"'%s\n'"'"' "$x_gitea" | head -n 1))"; fi ;;'   # rc 3: first raw line
m P7 "$TAR" "$FP" '  [ "$frc" -eq 0 ] || { printf '"'"'%s'"'"' "$x_fetch" | head -c 400; abort "fetch of $r main failed"; }'
m P8 "$TAR" 'if [ -n "${OK[$r]:-}" ]; then printf '"'"'INFO %s: tag pushed only' 'if true; then printf '"'"'INFO %s: tag pushed only'
m P9 "$DRF" '[ -f "$EXTERR" ] && rc_redact_cut 2000 mark <"$EXTERR" >&3;' '[ -f "$EXTERR" ] && cat "$EXTERR" >&3;'
m P10 "$PUB" '[ -f "$W/ext.err" ] && rc_redact_cut 2000 mark <"$W/ext.err" >&3;' '[ -f "$W/ext.err" ] && cat "$W/ext.err" >&3;'

# --- round 4: the reviewer's round-3 mutants Q1-Q12 (verbatim where the text still exists) ---
R3L='      if ((i = index(low, "://")) > 0 && match(substr(low, i + 3), /@[^@]*$/)) {'
m Q1 "$LIB" "$R3L" '      if ((i = index(low, "://")) > 0 && index(substr(low, i + 3), ":") == 0 && match(substr(low, i + 3), /@[^@]*$/)) {'   # a userinfo with ":" escapes
m Q2 "$LIB" "$R3L" '      if ((i = index(low, "://")) > 0 && match(substr(low, i + 3, 65), /@[^@]*$/)) {'      # "@" only within 64 bytes
m Q3 "$TAR" '  rm -f -- "$EXTERR" "$NOTES"' '  rm -f -- "$NOTES"'
m Q4 "$TAR" 'exec 3>&2 2>"$EXTERR"' 'exec 3>&2'
m Q5 "$PUB" 'exec 3>&2 2>"$W/ext.err"; DIE_FD=3' 'exec 3>&2; DIE_FD=3'
m Q6 "$DRF" 'EXTERR="$DBDIR/exterr"; exec 3>&2 2>"$EXTERR"; DIE_FD=3' 'EXTERR="$DBDIR/exterr"; exec 3>&2; DIE_FD=3'
FC='  x_fetch="$(net fetch -q --no-tags "$r" refs/heads/main 2>&1 >/dev/null)"; frc=$?'
m Q7 "$TAR" "$FC" "$FC"'; printf "%s" "$x_fetch" >"$RUNDIR/fetch.err"'                           # raw fetch stderr kept after a success
m Q8 "$TAR" "$FP" '  [ "$frc" -eq 0 ] || { printf "%s" "$x_fetch" >"$RUNDIR/fetch.err"; abort "fetch of $r main failed"; }'   # ... after a failed fetch
PC='  x_push="$(net push --atomic "$r" "$SHA:refs/heads/main" "refs/tags/$TAG:refs/tags/$TAG" 2>&1 >/dev/null)"; prc=$?'
m Q9 "$TAR" "$PC" "$PC"'; printf "%s" "$x_push" >"$RUNDIR/push.err"'                              # raw push stderr kept
m Q10 "$PUB" '"$W/resp.out" "$W/code.out" "$W/ext.err"; rmdir' '"$W/resp.out" "$W/ext.err"; rmdir'   # (err.out is gone; code.out is its successor)
m Q11 "$LIB" "$R3L" '      if ((i = index(low, "://")) > 0 && substr(low, i - 4, 4) ~ /^(http|ttps)$/ && match(substr(low, i + 3), /@[^@]*$/)) {'   # https?:// only
SIGT="trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM"
# round 5 (J6): Q12 and S11 were recorded EQUIVALENT in round 4 ("no observable difference"); the exit status
# DOES differ (143/129 through the trap, killed-by-signal without it; probe:
# docs/qa/con227_234_2026_11_11/round5/probe_trap_exit_status.py), and the suites now read it exactly (C39, case 14)
m Q12 "$PUB" "$SIGT" ':'
m S11 "$TAR" "$SIGT" ':'

# --- round 4: the fixer's own mutants on the round-4 design (re-applied where the text moved) ---
m S1 "$LIB" '      if (match(low, /(^|[^a-z0-9_-])' '      if (0 && match(low, /(^|[^a-z0-9_-])'                     # header rule R1 off
m S2 "$LIB" '      each("bearer[' '      if (0) each("bearer['                                                    # bearer rule R2 off
m S3 "$LIB" '      each("[^ \t' '      if (0) each("[^ \t'                                                      # scheme-less rule R4 off
m S4 "$LIB" '(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)[ \t]*=' '(secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)[ \t]*='   # round 6: re-applied, the rule allows blanks around =   # "token" names dropped
m S5 "$LIB" '        rest = substr(low, pos, lim - pos + 1)' '        rest = substr(line, pos, lim - pos + 1)'   # case-sensitive names
m S6 "$LIB" '      each("(gh[pousr]_' '      if (0) each("(gh[pousr]_'                                                 # token shapes R6 off
m S7 "$LIB" "LC_ALL=C tr -d '\\000' | LC_ALL=C awk -v max" "tr -d '\\000' | awk -v max"                       # caller locale used
m S8 "$LIB" "LC_ALL=C tr -d '\\000' | LC_ALL=C awk -v max" "LC_ALL=C awk -v max"                               # NUL bytes kept
m S9 "$LIB" '    END { if (dropped > 0 && mark != "")' '    END { if (0)'                                         # no truncation line
m S10 "$TAR" '  rmdir -- "$RUNDIR" 2>/dev/null ||' '  false ||'                                                 # run directory kept
m S12 "$TAR" '"$(withheld git "$mrc" "$(xcls "$x_main" "$mrc")")"' '""'                                       # fallback reason dropped (I-1)
m S13 "$LIB" 'export GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0' 'export GIT_TERMINAL_PROMPT=0'                # caller's GIT_TRACE_REDACT=0 kept
m S14 "$PUB" '[[ $NEWID =~ ^[0-9]{1,20}$ ]] || die' 'true || die'   # round 6: re-applied to the regex check;                                  # server id printed unvalidated (I-4)
m S15 "$LIB" '      lim += length(r) - L' '      :'                                                       # stale scan end (found by the two-parameter case)
m S16 "$LIB" 'while (pos <= lim) {' 'while (pos <= lim && pos < 2) {'                                         # only the first match of each rule

# --- round 5: the reviewer's round-4 mutants that survived (V3, V4, V5, V8, V11, V12, V13), adopted ---
m V3 "$LIB" 'api-key|apikey|api_key|cookie|credential)[ \t]*:' 'api-key|apikey|api_key|credential)[ \t]*:'     # Cookie: header not redacted
m V4 "$LIB" '        lim = length(line)   # R2, R5 and R6 scan the whole line' '        lim = (length(line) < max ? length(line) : max)   # scan window capped at N'
m V5 "$LIB" 'each("bearer[ \t]+' 'each("bearer[ ]+'                                                            # Bearer + TAB missed
m V8 "$TAR" '        *) fail "RELEASE $spec failed rc=$rc: $gmsg" ;;' '        *) fail "RELEASE $spec failed rc=$rc: $x_gitea" ;;'   # raw publisher stderr on the failure branch
m V11 "$LIB" '    { t = t " " tolower($0) }' '    NR == 1 { t = tolower($0) }'                                  # classifier reads the first line only (the round-4 V11 was "no line join"; oneline is gone)
meq V12 "$PUB" 'rc_git_env   # no git trace anywhere' ':   # no git trace anywhere' 'round 11: rc_env_clean runs before rc_git_env and its lockdown list holds no GIT_TRACE* or GIT_CURL_VERBOSE name (RELEASE_ENV_KEEP refuses every GIT_* name), so no child inherits a caller trace name; every git call goes through rc_net (netgate: 128 sites, 0 findings), and rc_net exports GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0 GIT_TRACE2*=0 itself; the suites set a caller GIT_TRACE=1 GIT_TRACE_REDACT=0 GIT_TERMINAL_PROMPT=1 (publish 19, tag C26 C34) and git still sees redact=1 prompt=0 trace=unset; rc_git_env is kept as defence in depth (11.4.124); docs/qa/con227_234_2026_11_11/round11/race/v12_x18_equivalence.txt'
m V13 "$TAR" ': "${RUNDIR:?}"; chmod 700 "$RUNDIR"' ': "${RUNDIR:?}"; chmod 755 "$RUNDIR"'                  # run directory readable by others
m V13b "$PUB" 'chmod 700 "$W"' 'chmod 755 "$W"'
m V13c "$DRF" 'DB="${DBDIR:?}/items.db"; chmod 700 "$DBDIR"' 'DB="${DBDIR:?}/items.db"; chmod 755 "$DBDIR"'

# --- round 5: the fixer's own mutants on the structural redesign ---
m U1 "$LIB" '      print "unknown"' '      print t'                                                         # the classifier echoes its input
m U2 "$LIB" 'export GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0' 'export GIT_TRACE_REDACT=1'                       # git may prompt
m U3 "$LIB" 'GIT_TRACE*|GIT_CURL_VERBOSE) unset -v "$v"' 'GIT_NO_SUCH_VARIABLE_) unset -v "$v"'                       # caller trace switches kept
m U4 "$TAR" '[[ $spec =~ $RE_GH || $spec =~ $RE_GL || $spec =~ $RE_GT ]] || die_usage' 'true || die_usage'   # any --release spec accepted
m U5 "$TAR" 'else die_usage "unknown argument (not shown: it is not shaped like an option)"; fi ;;' 'else die_usage "unknown argument: $1"; fi ;;'
m U6 "$TAR" 'timeout -k 10 "$NET_TIMEOUT" "$@"' '"$@"'   # round 6: re-applied, --foreground is gone;                                           # network commands unbounded
m U7 "$PUB" 'x_curl="$(printf '"'"'header = "Authorization: token %s"\n'"'"' "$_rpg_tok" | rc_net curl "${args[@]}"' \
            'printf '"'"'header = "Authorization: token %s"\n'"'"' "$_rpg_tok" >"$W/k.cfg"; x_curl="$(rc_net curl -K "$W/k.cfg" "${args[@]}"'   # token in a file
m U8 "$TAR" "elif [ -z \"\${1:-}\" ]; then printf -- '-'; else printf 'NOT-AN-OBJECT-ID'; fi; }" "else printf '%s' \"\${1:--}\"; fi; }"   # server ids printed unvalidated
m U9 "$TAR" $'\n      [[ $id =~ ^[0-9]{1,20}$ ]] || id=""' $'\n      :'                                              # GitHub id printed unvalidated
m U10 "$LIB" "  else printf '<url not shown>'; fi" "  else printf '%s' \"\$1\"; fi"                         # rc_safe_url passes an unsafe URL through
m U11 "$LIB" '      if (length(line) > lmax) {' '      if (0) {'                                               # very long lines printed
m U12 "$LIB" '        # R3 URL userinfo, whole line' '        if (match(low, /(^|[^a-z0-9_-])[a-z0-9_-]*(authorization|token|secret|password|passwd|api-key|apikey|api_key|cookie|credential)[ \t]*:/)) { line = substr(line, 1, RSTART + RLENGTH - 1) " <redacted>"; low = tolower(line) }
        # R3 URL userinfo, whole line'                                                              # J1: the header rule runs before R3 again
m U13 "$PUB" '_rpg_tok="${!TOKEN_VAR:-}"' 'export _rpg_tok="${!TOKEN_VAR:-}"'                                  # the token is exported to children
m U14 "$TAR" "then printf 'timeout'" "then printf 'unknown'"                                                   # a timeout is not named
m U15 "$TAR" '  [ "$(oid "$ro")" != NOT-AN-OBJECT-ID ] || abort' '  true || abort'                            # a non-object-id tag answer is used
m U16 "$PUB" '[[ $API_CODE =~ ^[0-9]{3}$ ]] ||' 'true ||'                                                      # a non-numeric HTTP status is printed
m U17 "$DRF" '[[ $BASE =~ ^[A-Za-z0-9][A-Za-z0-9._/~^-]{0,199}$ ]] || die' 'true || die'                     # --base echoed unvalidated

# ---- round 6 (structural, docs/qa/con227_234_2026_11_11/round6/threat_model.md) ----
# The reviewer's round-6 mutants that survived round 5 (X6, X7, X10, X12, X13, X14, X15, X17) and X9 reordered (X9b) are
# adopted as mp lines: each is killed only by a FAIL line that names the property it targets. X12 is equivalent under
# rc_env_lockdown (recorded with its reason); X12b removes the lockdown too and is killed. Y1-Y18 are the fixer's own.
mp X6 'X6 ' "$PUB" '[[ $id =~ ^[0-9]{1,20}$ ]] || die "unexpected release id' 'true || die "unexpected release id'   # re-applied: the round-6 check is a bash regex on one line of digits
mp X7 C47 "$TAR" 'net() { nt git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"; }' 'net() { nt git "$@"; }'   # verbatim
mp X9b 'token is in a file under TMPDIR|does not read -K' "$PUB" '-K - -X "$m"' '-K "$W/c.cfg" -X "$m"' '"$_rpg_tok" | rc_net curl "${args[@]}"' '"$_rpg_tok" >"$W/c.cfg"; rc_net curl "${args[@]}" </dev/null'   # X9 reordered so curl keeps -q first: the token in a file, killed by the TMPDIR census of case 17
mp X10 X10 "$DRF" 'trap '"'"'exit 129'"'"' HUP; trap '"'"'exit 130'"'"' INT; trap '"'"'exit 143'"'"' TERM' :   # verbatim
meq X12 "$PUB" 'unset -v _rpg_tok' : 'round 7: no caller _rpg_tok crosses the re-execution of rc_env_clean (it is not on the allow-list, so it is no "e" record) and the re-executed shell never exports it; round 6: rc_env_lockdown un-exports _rpg_tok (not on the allow-list, and RELEASE_ENV_KEEP refuses a name with TOK: redact case K3 _rpg_tok, mutant Y21), so a caller export reaches no child; X12b removes both and is killed by case 25'   # verbatim; equivalent under the lockdown
mp X12b 'K3|29' "$PUB" 'unset -v _rpg_tok' : 'rc_env_clean "$_rpg_tv" "$@"; _rc=$?' '_rc=0'   # X12 with the clean environment (and its lockdown) removed too; round 7: re-applied to the rc_env_clean line
mp X13 X13 "$PUB" 'W="$(mktemp -d "${TMPDIR:-/tmp}/rpg.XXXXXX")"' 'W="${TMPDIR:-/tmp}/rpg.fixed"; mkdir -p "$W"'   # verbatim
mp X14 xtrace "$PUB" 'set +x   # first: an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces this one line only
set -u' 'set -u'   # re-applied: set +x is now the first line
mp X15 C45 "$TAR" 'set +x   # first: an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces this one line only
set -u' 'set -u'   # re-applied: set +x is now the first line
mp X17 C46 "$TAR" 'own1() { printf '"'"'%s\n'"'"' "$1" | grep -m 1 '"'"'^release_publish_gitea: '"'"'' 'own1() { printf '"'"'%s\n'"'"' "$1" | grep -m 1 '"'"'release_publish_gitea: '"'"''   # verbatim
# the reviewer's round-6 mutants killed already on round 5 are adopted verbatim (rev_mutants.sh lines 115-138)
m X1 "$TAR" '"$(withheld git "$trc" "$(xcls "$x_tagpush" "$trc")")"' '"$x_tagpush"'                         # tag-push failure prints git's stderr
m X2 "$TAR" '"$(withheld git "$prc" "$(xcls "$x_push" "$prc")")"' '"$x_push"'                                # atomic push failure prints git's stderr
m X3 "$TAR" "  else printf '%s' \"\$1\" | rc_err_class; fi" "  else printf '%s' \"\$1\" | head -c 60; fi"     # class word bypassed (first bytes of stderr)
m X4 "$PUB" 'cls="$(printf '"'"'%s'"'"' "$x_curl" | rc_err_class)"' 'cls="$(printf '"'"'%s'"'"' "$x_curl" | tr -d '"'"'\n'"'"')"'   # publisher class word bypassed
m X5 "$TAR" "  printf '%s %s %s' \"\$(oid \"\$m\")\" \"\$(oid \"\$o\")\" \"\$(oid \"\$p\")\"" "  printf '%s %s %s' \"\$m\" \"\$o\" \"\$p\""   # ls-remote answer printed unvalidated
m X8 "$PUB" '"$_rpg_tok" | rc_net curl "${args[@]}"' '"$_rpg_tok" >/dev/null; rc_net curl -H "Authorization: token $_rpg_tok" "${args[@]}" </dev/null'   # token back to curl argv
mp X11 'X11' "$PUB" 'unset -v "$TOKEN_VAR" 2>/dev/null || true' ': "$TOKEN_VAR"'   # round 6: killed by case 28 (an allow-listed --token-var)                                          # caller token variable passed to children
m X16 "$DRF" 'die "--base is not a revision name of [A-Za-z0-9._/~^-] (the value is not shown)" 2' 'die "--base is not a revision name: $BASE" 2'   # invalid value echoed
meq X18 "$TAR" 'rc_git_env   # no git trace anywhere, no terminal prompt, GIT_TRACE_REDACT=1' ':' 'round 11: rc_env_clean runs before rc_git_env and its lockdown list holds no GIT_TRACE* or GIT_CURL_VERBOSE name (RELEASE_ENV_KEEP refuses every GIT_* name), so no child inherits a caller trace name; every git call goes through rc_net (netgate: 128 sites, 0 findings), and rc_net exports GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0 GIT_TRACE2*=0 itself; the suites set a caller GIT_TRACE=1 GIT_TRACE_REDACT=0 GIT_TERMINAL_PROMPT=1 (publish 19, tag C26 C34) and git still sees redact=1 prompt=0 trace=unset; rc_git_env is kept as defence in depth (11.4.124); docs/qa/con227_234_2026_11_11/round11/race/v12_x18_equivalence.txt'
m X19 "$LIB" '  LC_ALL=C tr -d '"'"'\000'"'"' | LC_ALL=C awk '"'"'
    { t = t' '  LC_ALL=C tr -d '"'"'\000'"'"' | LC_ALL=C awk '"'"'
    { print; t = t'                                                                                              # classifier also echoes its input
m X20 "$TAR" '      gmsg="$(own1 "$x_gitea" 200)"' '      gmsg="$(printf '"'"'%s\n'"'"' "$x_gitea" | grep -m1 '"'"'^release_publish_gitea: '"'"' | head -c 200)"'   # own line not redacted
mp Y1 C41 "$TAR" 'timeout -k 10 "$NET_TIMEOUT" "$@"' 'timeout --foreground -k 10 "$NET_TIMEOUT" "$@"'   # K2: --foreground back
mp Y2 'C4[348]' "$TAR" 'rc_env_clean "$_tar_reads" "$@"; _rc=$?' '_rc=0'   # K3: tag lockdown removed (round 7: re-applied, the lockdown runs inside rc_env_clean)
mp Y3 'K3|29' "$PUB" 'rc_env_clean "$_rpg_tv" "$@"; _rc=$?' '_rc=0'   # K3: publisher lockdown removed (round 7: re-applied to the rc_env_clean line)
mp Y4 'K3|L2' "$DRF" 'rc_env_clean "" "$@"; _rc=$?' '_rc=0'   # K3: derive lockdown removed (round 7: re-applied to the rc_env_clean line)
mp Y5 'K1|C42' "$LIB" 'rc_url_has_userinfo() {' 'rc_url_has_userinfo() { return 1;'   # K1: userinfo check always allows
mp Y6 'push URL' "$TAR" '; rc_net git remote get-url --push --all "$r" 2>/dev/null)' ')'   # K1: push URLs not checked
mp Y7 'C4[48]' "$TAR" 'rc_env_clean "$_tar_reads" "$@"; _rc=$?' 'rc_env_clean "$_tar_reads" "$@"; _rc=$?; [ -n "${M3W_GITEA_TOKEN+x}" ] && export M3W_GITEA_TOKEN'   # K3: token exported to every child (round 7: re-applied after rc_env_clean)
mp Y8 C44 "$TAR" 'x_gitea="$(pub "$gtv" "${args[@]}" 2>&1 >/dev/null)"' 'x_gitea="$(export "${gtv?}"; nt bash scripts/release_publish_gitea.sh --token-var "$gtv" "${args[@]}" 2>&1 >/dev/null)"'   # K3: publisher run under timeout(1), which then holds the token
mp Y9 K3 "$LIB" '    [[ ${v^^} =~ TOK|SECRET|PASS|PWD|KEY|CRED|AUTH|COOKIE|SESSION|JWT|PROXY ]] && continue' '    :'   # K3: RELEASE_ENV_KEEP may name a credential
mp Y10 'N1c|N1d' "$LIB" '        each("\"[a-z0-9_.-]*(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)\"[ \t]*:[ \t]*\"[^\"]*\"", "json")' '        :'   # N1: JSON rule removed
mp Y11 N1a "$LIB" '        each("[a-z0-9_.-]*(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)%3d[^&#; \t\"'"'"'\'"'"''"'"'<>]*", "param3d")' '        :'   # N1: percent-encoded rule removed
mp Y12 N1b "$LIB" 'jwt)[ \t]*=[ \t]*[^&#' 'jwt)=[^&#'   # N1: spaced = not matched
mp Y13 'base URL accepted|userinfo base URL' "$PUB" 'if [ "$(rc_safe_url "$BASE_URL")" = "${BASE_URL%/}" ]; then' 'if true; then'   # K4: rc_safe_url base check removed
mp Y14 27: "$PUB" '[[ $NEWID =~ ^[0-9]{1,20}$ ]] || die' 'printf '"'"'%s'"'"' "$NEWID" | grep -Eq '"'"'^[0-9]+$'"'"' || die'   # X6 class on the created id: grep accepts a line of digits among others
mp Y15 'exported function' "$LIB" '  for v in $(compgen -A function); do export -n -f "$v" 2>/dev/null; done   # no exported function either' '  :'   # K3: exported functions reach children
mp Y16 'URL is not shown' "$TAR" 'abort "remote $r has a URL with a user name or password in it;' 'abort "remote $r URL $u has a user name or password in it;'   # K1: the refused URL echoed
mp Y17 scp-userpass "$LIB" '  case "$auth" in *@*) ui="${auth%@*}"; case "$ui" in *:*|*%3[Aa]*) return 0 ;; esac ;; esac' '  :'   # K1: scp-like user:password not refused
mp Y18 'base URL accepted' "$PUB" 'http://127.0.0.1:[0-9]*|' 'http://*|'   # plain http allowed to any host

mp Y19 '28 X11' "$PUB" '    -h|--help) HELP=1; shift ;;' '    -h|--help) sed -n '"'"'2,29p'"'"' "$0"; exit 0 ;;'   # X11 class: an external command (the help sed) before the token is dropped
mp Y20 '28 X11' "$PUB" 'unset -v _rpg_tok
_rpg_tok=""
if [ -n "$TOKEN_VAR" ]; then _rpg_tok="${!TOKEN_VAR:-}"; unset -v "$TOKEN_VAR" 2>/dev/null || true; fi
' '' 'case "$REPO" in *..*|./*|*/.) die "repo has dot segments: refusing" 2 ;; esac
' 'case "$REPO" in *..*|./*|*/.) die "repo has dot segments: refusing" 2 ;; esac
unset -v _rpg_tok
_rpg_tok=""
if [ -n "$TOKEN_VAR" ]; then _rpg_tok="${!TOKEN_VAR:-}"; unset -v "$TOKEN_VAR" 2>/dev/null || true; fi
'   # X11 class: the token is read and dropped only after the first grep
mp Y21 'K3 _rpg_tok' "$LIB" '=~ TOK|SECRET' '=~ TOKEN|SECRET'   # X12 class: RELEASE_ENV_KEEP may keep the publisher's holding variable _rpg_tok exported
# K5 class (round 6; round 7: rc_env_clean is the first command): an external command before rc_env_clean gets the caller's whole environment; killed by the L1 case
# of the script's own suite (census lint on the copy) and, for the publisher, by the runtime recorders of test_channel_census.sh
mp Y22 'L1 external command before rc_env_clean' "$PUB" '. "$(cd "$_rc_d" && pwd)/release/redact_cut.sh"' '. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release/redact_cut.sh"'
mp Y23 'L1 external command before rc_env_clean' "$TAR" '. "$(cd "$_rc_d" && pwd)/redact_cut.sh"' '. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/redact_cut.sh"'
mp Y24 'L1 external command before rc_env_clean' "$DRF" '. "$(cd "$_rc_d" && pwd)/redact_cut.sh"' '. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/redact_cut.sh"'
mp Y25 'L1 external command before rc_env_clean' "$DRF" 'rc_env_clean "" "$@"; _rc=$?' $'TODAY="${TODAY:-$(date +%F)}"\nrc_env_clean "" "$@"; _rc=$?'   # the round-6 K5 date fix undone (round 7: before rc_env_clean)
# --- round 7 (structural, L1-L5 of the round-6 review): the reviewer's Z1-Z14 adopted verbatim (Z14: "set -a after
# the lockdown" re-applied after the rc_env_clean block, the lockdown line it named runs inside rc_env_clean now) ---
m Z1 "$LIB" 'GLAB_CONFIG_DIR GITLAB_HOST " extra=""' 'GLAB_CONFIG_DIR GITLAB_HOST M3W_GITEA_TOKEN " extra=""'   # round 11: re-applied to the lockdown list (the network list: NN2)
m Z2 "$LIB" $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported' $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported\n    case "$v" in LC_*|*_TOKEN) continue ;; esac'   # round 8: re-applied (the LC_* line is gone): a name pattern kept by the lockdown
m Z3 "$LIB" '    case "$scheme" in http|https|ftp|ftps) return 0 ;; esac' '    case "$scheme" in ftp|ftps) return 0 ;; esac'
m Z4 "$LIB" '    case "$ui" in *:*|*%3[Aa]*) return 0 ;; esac
    return 1' '    case "$ui" in *:*) return 0 ;; esac
    return 1'
m Z5 "$LIB" 'scheme="${BASH_REMATCH[1],,}"' 'scheme="${BASH_REMATCH[1]}"'
meq Z6 "$TAR" 'urls="$(rc_net git remote get-url --all "$r" 2>/dev/null;' 'urls="$(rc_net git remote get-url "$r" 2>/dev/null;' 'git fetch and ls-remote use only the first URL, and every URL a push uses is in get-url --push --all (round-6 review, measured on a remote with two URLs, with and without pushurl)'
m Z7 "$PUB" 'unset -v "$TOKEN_VAR" 2>/dev/null || true' 'true'
mp Z8 C49 "$TAR" 'timeout -k 10 "$NET_TIMEOUT" "$@"' 'timeout "$NET_TIMEOUT" "$@"'
mp Z9 C49 "$TAR" '[ "$2" -eq 124 ] || [ "$2" -eq 137 ]' '[ "$2" -eq 124 ]'
m Z11 "$LIB" $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported' $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported\n    case "$v" in LC_*|GIT_*) continue ;; esac'   # round 8: re-applied, as Z2
m Z12 "$LIB" '    [[ ${v^^} =~ TOK|SECRET' '    [[ ${v} =~ TOK|SECRET'
m Z13 "$LIB" 'each("bearer[ \t]+' 'each("bearer[ ]+'
m Z14 "$PUB" 'unset -v _rpg_tv _rpg_a _rpg_i' 'unset -v _rpg_tv _rpg_a _rpg_i; set -a'
# --- round 7: the fixer's own mutants on the positive environment (W1-W13) ---
mp W1 'K6|29' "$LIB" '  exec -c -a "$_RC_ENV_MARK" "$BASH" "$0" "$@" 9< <(_rc_env_dump "$reads")' '  return 0'   # no re-execution: the round-6 lockdown only
mp W2 'K6|C44|C48' "$LIB" '9< <(_rc_env_dump "$reads")' '9< <(_rc_env_dump "")'   # READS values not carried (the tag script loses the token)
mp W3 'K6 marker' "$LIB" 'if [ "$a0" = "$_RC_ENV_MARK" ] && [ "$n" -eq 0 ]; then' 'if [ "$a0" = "$_RC_ENV_MARK" ] && [ "$n" -ge 0 ]; then'   # the marker alone counts as clean
mp W4 'K6 s record' "$LIB" '        s) case " $1 RELEASE_ENV_KEEP " in *" $n "*)' '        s) case " $n " in *" $n "*)'   # any s record is set
mp W5 'K6 an injected e record' "$LIB" '    exec 9<&-
  fi
  rc_env_lockdown' '    exec 9<&-
  fi'   # the records are not decided again
mp W6 'K6 blind' "$LIB" '    blind) return 3 ;;' '    blind) return 0 ;;'   # blind state taken as clean
mp W7 'K6 READS|31 --token-var' "$LIB" '    _rc_env_reserved "$v" && return 2
  done' '    :
  done'   # a READS name bash gives a meaning of its own accepted
mp W8 '30 --token-var' "$PUB" '    --token-var) _rpg_tv="${_rpg_a[_rpg_i+1]:-}"; _rpg_i=$((_rpg_i + 2)) ;;' '    --token-var) _rpg_i=$((_rpg_i + 2)) ;;'   # prescan ignores --token-var
mp W9 'C4[48]' "$TAR" 'rc_env_clean "$_tar_reads" "$@"' 'rc_env_clean "RELEASE_NET_TIMEOUT" "$@"'   # the tag script's READS lose the token
mp W10 C49 "$TAR" 'timeout -k 10 "$NET_TIMEOUT" "$@"' 'timeout -k 600 "$NET_TIMEOUT" "$@"'   # the KILL comes too late
mp W11 'fd 9|descriptor 9' "$LIB" '    exec 9<&-
  fi' '  fi'   # the state pipe stays open in every child
mp W12 'K6|29|C4[48]|L2' "$LIB" 'printf '"'"'e\0%s\0%s\0'"'"' "$v" "${!v}"' 'printf '"'"'e\0%s\0%s\0'"'"' "$v" ""'   # the dump carries no values
mp W13 '31 --token-var' "$PUB" '[ "$_rc" -ne 2 ] || die "--token-var names a variable that bash gives a meaning of its own: refusing" 2' 'true'   # status 2 not reported as a usage error
# --- round 8: the reviewer's round-7 mutants A1-A14 (scratchpad rv7 mbatch.py; there is no A3, see the review) ---
m A1 "$LIB" 'if [ "$a0" = "$_RC_ENV_MARK" ] && [ "$n" -eq 0 ]; then' 'if [ "$a0" = "$_RC_ENV_MARK" ]; then'
m A2 "$LIB" $'    exec 9<&-\n' $'\n'
m A4 "$LIB" 'clean) _rc_env_closefds "/proc/$$" || return 3; _rc_env_restore "$reads"; return 0 ;;' 'clean) _rc_env_closefds "/proc/$$" || return 3; rc_env_lockdown; return 0 ;;'   # re-applied (round 9: the clean branch's closefds line changed)
mp A5 'LC_ZZTOKEN|LC_|N1' "$LIB" $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported' $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported\n    case "$v" in LC*) continue ;; esac'   # re-applied: the round-7 LC_* prefix skip, widened to LC* (N1)
mp A5b 'LC_ZZTOKEN|LC_|N1' "$LIB" $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported' $'  for v in $(compgen -e); do\n    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported\n    case "$v" in LC_*) continue ;; esac'   # the round-7 shape itself (an LC_* prefix)
m A6 "$LIB" 'e) printf -v "$n" '"'"'%s'"'"' "$val" 2>/dev/null && export "${n?}" ;;' 'e) printf -v "$n" '"'"'%s'"'"' "$val" 2>/dev/null ;;'
mp A7 'K6 blind|N2' "$LIB" $'    blind) return 3 ;;\n' $'    blind) ;;\n'   # round 7 killed this only by a 900 s hang; the loop guard turns it into a FAIL
m A8 "$TAR" '_tar_reads="RELEASE_NET_TIMEOUT"; _tar_a=' '_tar_reads=""; _tar_a='
m A9 "$LIB" $'    _rc_env_reserved "$v" && return 2\n' $'\n'
mp A10 'K10 R9-2' "$LIB" $'  rc_env_lockdown\n  shopt -s execfail' '  shopt -s execfail'   # round 10 (R9-2): NOT equivalent (the round-8 record was wrong): every caller variable became a shell variable of the re-executed script (HELP=1 printed the publisher's help and exited 0); K10 R9-2 now kills it
m A11 "$LIB" $'    exec 9<&-\n  fi\n  rc_env_lockdown\n' $'    exec 9<&-\n  fi\n'
m A12 "$LIB" '  printf '"'"'s\0RELEASE_ENV_KEEP\0%s\0'"'"' "${RELEASE_ENV_KEEP-}"' '  :'
m A13 "$PUB" $'[ "$_rc" -ne 2 ] || die "--token-var names a variable that bash gives a meaning of its own: refusing" 2\n' $'\n'
meq A14 "$LIB" '  for v in $1; do [ -n "${!v+x}" ] && printf' '  for v in $1; do [ -n "${!v:-}" ] && printf' 'an empty READS variable is then not carried; the only READS values are the token variable and RELEASE_NET_TIMEOUT, and an empty token takes the same SKIPPED-NO-TOKEN path as an unset one, an empty RELEASE_NET_TIMEOUT the same default as an unset one (review_fix227_r7.md A14)'
# --- round 8: the fixer's own mutants B1-B12 (N1-N4) ---
mp B1 'N3|descriptor' "$LIB" 'clean) _rc_env_closefds "/proc/$$" || return 3; _rc_env_restore' 'clean) _rc_env_restore'   # re-applied (round 9); N3: inherited descriptors reach every child
mp B2 'N2' "$LIB" $'  [ "$a0" = "$_RC_ENV_MARK" ] && return 4\n' $'\n'   # N2: no loop guard
mp B3 'N4' "$LIB" $'  { [ "${#BASH_SOURCE[@]}" -ge 2 ] && [ "${BASH_SOURCE[1]}" = "$0" ] && [ "${BASH_SOURCE[-1]}" = "$0" ]; } || return 4\n' $'\n'   # N4: a sourced script re-executes its caller
mp B4 'N1' "$LIB" '  local LC_ALL=C n="$1" x="$2" re' '  local LC_ALL=C n="$1" x="$2" re; return 0'   # N1: no value check at all
mp B5 'N1|R11' "$LIB" '[[ ${cs,,} =~ ^($_RC_LOCALE_CODESET)$ ]]' '[[ ${cs,,} =~ ^($_RC_LOCALE_CODESET)( .*)?$ ]]'   # re-applied (round 11: the closed codeset list); N1: a locale value with a blank (a word after the locale)
mp B6 'class table' "$LIB" '  case "$x" in *[[:cntrl:]]*) return 1 ;; *://*@*) return 1 ;; esac' '  :'   # N1: no control-character or URL user-information check
mp B7 'class table' "$LIB" '  [[ ${x,,} =~ gh[pousr]_[a-z0-9]{20}|github_pat_[a-z0-9_]{20}|glpat-[a-z0-9_-]{20} ]] && return 1' '  :'   # N1: no token-shape check
mp B8 'SSH_AUTH_SOCK|class table' "$LIB" '[[ $x == /* ]] && [ -S "$x" ]; } ;;' '[[ $x == /* ]]; } ;;'   # N1: SSH_AUTH_SOCK need not be a socket
mp B9 'class table' "$LIB" $'      [ -z "$x" ] || [[ $x == /* ]] ;;\n' $'      return 0 ;;\n'   # N1: a path name may hold any value
mp B10 'class table' "$LIB" '    *) return 1 ;;   # a name of the list' '    *) return 0 ;;   # a name of the list'   # N1: not fail closed
m B11 "$LIB" '&& (( (8#$fl) & 8#2000000 )); then continue; fi' '&& ! (( (8#$fl) & 8#2000000 )); then continue; fi'   # re-applied (round 9); N3: closes bash's own descriptors and keeps the inherited ones
m B12 "$LIB" '    case "$n" in 0|1|2|9) continue ;; esac' '    case "$n" in 0|1|2|99) continue ;; esac'   # re-applied (round 9); N3: the state pipe closed before it is read
# --- round 9: the reviewer's round-8 mutants, adopted (review_fix227_r8.md: R1, R4, R5, R6, R8, R9, R10, D1, E1) ---
m RR1 "$LIB" '    [[ $n =~ ^[0-9]+$ ]] || continue' '    [[ $n =~ ^[0-9]{1,2}$ ]] || continue'   # R1 (re-applied to the round-9 regex): fds of 100 and above stay open
m RR4 "$LIB" '  case "$x" in *[[:cntrl:]]*) return 1 ;;' '  case "$x" in *$'"'"'\n'"'"'*) return 1 ;;'   # R4: only a newline counts as a control character
m RR5 "$LIB" '|glpat-[a-z0-9_-]{20} ]] && return 1' ' ]] && return 1'   # R5: no glpat- shape
m RR6 "$LIB" '=~ gh[pousr]_[a-z0-9]{20}|' '=~ gh[p]_[a-z0-9]{20}|'   # R6: only ghp_
m RR8 "$LIB" '[[ $x == /* ]] && [ -S "$x" ]; } ;;' '[[ $x == /* ]] && [ -e "$x" ]; } ;;'   # R8: SSH_AUTH_SOCK any existing path
m RR9 "$LIB" $'  [ "${#x}" -le 4096 ] || return 1\n' $'\n'   # R9: no 4096-byte cap
mp RR10 'R11 not a locale' "$LIB" '[[ ${cs,,} =~ ^($_RC_LOCALE_CODESET)$ ]]' '[[ ${cs,,} =~ ^($_RC_LOCALE_CODESET)([:/].*)?$ ]]'   # re-applied (round 11: the closed codeset list); R10: a locale value may hold : and /
m RD1 "$DRF" 'case "$ref" in ""|"refs/remotes/$r/main"' 'case "$ref" in "refs/remotes/$r/main"'   # D1: an empty ref line counted
m RE1 "$EAL" '[ "${RELEASE_TESTS_ALLOW_SKIP:-}" = 1 ]' '[ -n "${RELEASE_TESTS_ALLOW_SKIP:-}" ]'   # E1: any non-empty value allows skips
# --- round 9: the fixer's own mutants on the descriptor close (F1, G1-G10) and RELEASE_ENV_KEEP (F7, H1-H4) ---
m G1 "$LIB" '    [[ $n =~ ^[0-9]+$ ]] || continue' '    [[ $n =~ ^[0-9]{1,4}$ ]] || continue'   # the round-8 shape: 5-digit fds stay open
m G2 "$LIB" '    [[ $n =~ ^[0-9]+$ ]] || continue' '    [[ $n =~ ^[0-9]{1,5}$ ]] || continue'   # 6-digit fds stay open (100000)
m G3 "$LIB" '    case "$n" in 0|1|2|9) continue ;; esac' '    case "$n" in 0|1|2|9|1*) continue ;; esac'   # fds whose number starts with 1 stay open
m G4 "$LIB" '    case "$n" in 0|1|2|9) continue ;; esac' '    case "$n" in 0|1|2|9|300) continue ;; esac'   # one 3-digit fd kept (an instance hole)
m G5 "$LIB" '  for f in "$1"/fd/*; do' '  for f in "$1"/fd/?; do'   # only one-digit entries listed
m G6 "$LIB" 'clean) _rc_env_closefds "/proc/$$" || return 3;' 'clean) _rc_env_closefds "/proc/$$";'   # an unlistable descriptor directory not refused
m G7 "$LIB" $'  [ "$seen" -eq 1 ]\n}' $'  return 0\n}'   # status 0 when nothing was listed
m G8 "$LIB" 'if [[ $fl =~ ^[0-7]{1,11}$ ]] && ((' 'if ! [[ $fl =~ ^[0-7]{1,11}$ ]] || (('   # a descriptor whose flags cannot be read is kept (fail open)
m G9 "$LIB" $'    eval "exec $n<&-"\n  done' $'    [ "$n" -lt 1000 ] && eval "exec $n<&-"\n  done'   # fds of 1000 and above stay open
m G10 "$LIB" '<"$1/fdinfo/$n"; } 2>/dev/null' '<"/proc/$$/fdinfo/$n"; } 2>/dev/null'   # the flags are read from another directory than the list
m H1 "$LIB" 'in GIT_*|SSH_*|CURL_*|' 'in SSH_*|CURL_*|'   # F7: RELEASE_ENV_KEEP may name GIT_CONFIG_PARAMETERS
m H2 "$LIB" '*" $v "*) _rc_env_common_ok "${!v}" || export -n "$v" 2>/dev/null ;;' '*" $v "*) ;;'   # F7: no value check on a RELEASE_ENV_KEEP name
m H3 "$LIB" $'    _rc_env_reserved "$v" && continue\n    extra=' $'    extra='   # F7: RELEASE_ENV_KEEP may name PS4 or CDPATH
m H4 "$LIB" '|LD_*|*_URL|*_URI) continue' '|LD_*) continue'   # F7: RELEASE_ENV_KEEP may name a *_URL variable
# --- round 10: the reviewer's round-9 mutants Q1, Q4, Q5, Q11 (review_fix227_r9.md section 4), adopted verbatim as QQ1, QQ4, QQ5, QQ11 (the names Q1-Q12 were taken by round 4) ---
mp QQ1 'K10 R9-4' "$LIB" '    case "$n" in 0|1|2|9) continue ;; esac' '    case "$n" in 0|1|2|5|9) continue ;; esac'   # fd 5 kept: a caller's open credential file reaches every child
mp QQ4 'K10 R9-3' "$LIB" 'GIT_*|SSH_*|CURL_*|' 'GIT_*|CURL_*|'   # SSH_* not refused in RELEASE_ENV_KEEP
mp QQ5 'K10 R9-3' "$LIB" '|GITLAB_*|LD_*|' '|GITLAB_*|'   # LD_* not refused
mp QQ11 'K10 R9-4' "$LIB" 'SECRET|PASS|PWD' 'SECRET|PWD'   # PASS not a credential word (DB_PASSWORD kept)
# --- round 10: the fixer's own mutants J1-J5 (each other refused prefix), K1-K15 (R9-1: the SendEnv class and the
# run-time SendEnv patterns), L1-L3 (F8: the locale grammar), NG1 (N2: glob), CW1-CW10 (every other credential word) ---
mp J1 'K10 R9-3' "$LIB" '|CURL_*|GH_*|' '|GH_*|'   # CURL_* not refused
mp J2 'K10 R9-3' "$LIB" '|GH_*|GLAB_*|' '|GLAB_*|'   # GH_* not refused
mp J3 'K10 R9-3' "$LIB" '|GLAB_*|GITLAB_*|' '|GITLAB_*|'   # GLAB_* not refused
mp J4 'K10 R9-3' "$LIB" '|GITLAB_*|LD_*|' '|LD_*|'   # GITLAB_* not refused
mp J5 'K10 R9-3' "$LIB" '|*_URL|*_URI) continue' '|*_URL) continue'   # *_URI not refused (H4 drops both)
mp K1 'K10 R9-1' "$LIB" 'in LANG*|LC_*|COLORTERM|NO_COLOR) continue' 'in LC_*|COLORTERM|NO_COLOR) continue'   # LANG* not refused
mp K2 'K10 R9-1' "$LIB" 'in LANG*|LC_*|COLORTERM|NO_COLOR) continue' 'in LANG*|COLORTERM|NO_COLOR) continue'   # LC_* not refused
mp K3 'K10 R9-1' "$LIB" 'in LANG*|LC_*|COLORTERM|NO_COLOR) continue' 'in LANG*|LC_*|NO_COLOR) continue'   # COLORTERM not refused
mp K4 'K10 R9-1' "$LIB" 'in LANG*|LC_*|COLORTERM|NO_COLOR) continue' 'in LANG*|LC_*|COLORTERM) continue'   # NO_COLOR not refused
mp K5 'K10 R9-1|K10 census' "$LIB" '    case "${v^^}" in LANG*|LC_*|COLORTERM|NO_COLOR) continue ;; esac' '    :'   # the static SendEnv class removed (the run-time patterns of this host's ssh_config still refuse some)
mp K6 'K10 R9-1' "$LIB" '    case "${v^^}" in LANG*|LC_*|COLORTERM|NO_COLOR) continue ;; esac' '    case "$v" in LANG*|LC_*|COLORTERM|NO_COLOR) continue ;; esac'   # case-sensitive: lc_zz10 kept
# K7-K15 (round 10) are retired in round 11: they mutated the SendEnv reader (_rc_env_sendenv, _rc_env_sendenv_read,
# _rc_env_pwhome), which is removed. The property they guarded, that no caller name reaches an ssh child, is held by
# rc_net; mutants.md maps each of them to the NN mutant that kills the same property.
mp L1 'F8' "$LIB" '      [ "${#x}" -le 64 ] && _rc_env_locale_ok "$x" ;;' '      [[ $x =~ ^[A-Za-z0-9_.@-]{0,64}$ ]] ;;'   # the round-9 locale class (a bare token kept)
mp L2 'F8' "$LIB" '_rc_env_locale_ok "$e" || return 1' ':'   # LANGUAGE elements not checked
mp L3 'F8' "$LIB" '        case "$rest" in *:*) rest="${rest#*:}" ;; *) rest="" ;; esac; done ;;' '        rest=""; done ;;'   # only the first LANGUAGE element checked
mp NG1 'K10 N2' "$LIB" $'  set -f\n  for v in ${RELEASE_ENV_KEEP:-}; do' $'  for v in ${RELEASE_ENV_KEEP:-}; do'   # RELEASE_ENV_KEEP glob-expanded against the current directory
mp CW1 'K10 R9-4' "$LIB" '=~ TOK|SECRET|' '=~ SECRET|'   # TOK not a credential word
mp CW2 'K10 R9-4' "$LIB" '|SECRET|PASS|' '|PASS|'   # SECRET
mp CW3 'K10 R9-4' "$LIB" '|PASS|PWD|' '|PASS|'   # PWD
mp CW4 'K10 R9-4' "$LIB" '|PWD|KEY|' '|PWD|'   # KEY
mp CW5 'K10 R9-4' "$LIB" '|KEY|CRED|' '|KEY|'   # CRED
mp CW6 'K10 R9-4' "$LIB" '|CRED|AUTH|' '|CRED|'   # AUTH
mp CW7 'K10 R9-4' "$LIB" '|AUTH|COOKIE|' '|AUTH|'   # COOKIE
mp CW8 'K10 R9-4' "$LIB" '|COOKIE|SESSION|' '|COOKIE|'   # SESSION
mp CW9 'K10 R9-4' "$LIB" '|SESSION|JWT|' '|SESSION|'   # JWT
mp CW10 'K10 R9-4' "$LIB" '|JWT|PROXY ]]' '|JWT ]]'   # PROXY (the first form also removed JWT and was killed by ZW_JWT, not ZW_PROXY)
# --- round 11: the reviewer's round-10 mutants R01-R22 adopted as RT* (see the header); R01-R11, R14-R16, R22: N/A ---
meq RT12 "$PUB" 'HELP=0   # round 10 (R9-2): -h sets it; it is never taken from the caller' '# HELP=0 removed by reviewer mutant' 'rc_env_clean drops a caller HELP (the re-executed script starts from an empty environment and HELP is not in its READS), so HELP is unset and reads as 0 in the test [ "${HELP:-0}" ]; round-10 review probe: with HELP=1 in the caller the mutant prints "--tag is required", not the help'
mp RT13 'R11' "$LIB" "_RC_LOCALE_CODESET='utf-?8|" "_RC_LOCALE_CODESET='[a-z]+:[a-z]+|utf-?8|"   # R13 re-applied to the closed codeset list: a codeset holding ":" (en_US.ab:cd) kept
mp RT17 'descriptor' "$LIB" 'case "$n" in 0|1|2|9) continue ;; esac' 'case "$n" in 0|1|2|9|1[0-9]) continue ;; esac'   # R17 verbatim: descriptors 10-19 not closed
mp RT18 'K10 R9-4' "$LIB" 'COOKIE|SESSION|JWT|PROXY ]]' 'COOKIE|SESSION|JWT ]]'   # R18 verbatim
mp RT19 'F8|N1' "$LIB" '        case "$rest" in *:*) rest="${rest#*:}" ;; *) rest="" ;; esac; done ;;' '        rest=""; done ;;'   # R19 verbatim (the same replacement as L3)
meq RT20 "$LIB" '      [ "${#x}" -le 64 ] && _rc_env_locale_ok "$x" ;;' '      [ "${#x}" -le 4096 ] && _rc_env_locale_ok "$x" ;;' 'round 11: the closed grammar of _rc_env_locale_ok accepts at most 3+1+3 language and territory bytes, a 14-byte codeset (ansi_x3.4-1968) and a 14-byte modifier (ijekavianlatin) with their separators: 37 bytes, so a value longer than 64 bytes is refused by the grammar whatever the cap; K11 R11 shows the reviewer value (69 bytes) refused and the longest kept value (lv11, under 64 bytes) kept'
mp RT21 'K10 R9-1' "$LIB" 'case "${v^^}" in LANG*|LC_*|COLORTERM|NO_COLOR) continue ;; esac' 'case "${v^^}" in LANG*|LC_*) continue ;; esac'   # R21 verbatim
# --- round 11: the fixer's own mutants NN1-NN16 (rc_net, its call sites, the locale grammar) ---
mp NN1 'K11' "$LIB" $'rc_net() {\n  [ "$#" -ge 1 ] || return 125' $'rc_net() {\n  "$@"; return\n  [ "$#" -ge 1 ] || return 125'   # rc_net runs the command with the caller's environment
mp NN2 'K11' "$LIB" '_RC_NET_KEEP=" PATH HOME TMPDIR' '_RC_NET_KEEP=" LANG USER TERM KEEPME PATH HOME TMPDIR'   # the network allow-list widened
mp NN3 'K11 shape' "$LIB" '*" $_rc_v "*) _rc_env_shape_ok "$_rc_v" "${!_rc_v}" && continue ;; esac' '*" $_rc_v "*) continue ;; esac'   # no value check on the network list
mp NN4 'K11 export disabled' "$LIB" "builtin printf 'rc_net: refused: a variable outside the network allow-list is still exported\n' >&2; builtin exit 125 ;;" ': ;;'   # the second census no longer refuses
mp NN5 'K11 (not rebuilt|precondition)' "$LIB" '  [ "$_RC_ENV_STATE" = clean ] || { printf' '  [ "$_RC_ENV_STATE" = clean ] || true || { printf'   # the rc_env_clean precondition dropped
mp NN6 'K11 IFS' "$LIB" "IFS=\$' \\t\\n'; set -f" 'set -f'   # the caller's IFS splits the name lists
mp NN7 'K11 shadow' "$LIB" '      builtin export -n "$_rc_v" 2>/dev/null' '      export -n "$_rc_v" 2>/dev/null'   # a function named export replaces the builtin
mp NN8 'C48 .*net' "$TAR" '  rc_net git tag -a "$TAG"' '  git tag -a "$TAG"'   # a call site outside rc_net (tag)
mp NN9 'C48 .*net' "$TAR" 'then rc_net timeout -k 10 "$NET_TIMEOUT" "$@"; else rc_net "$@"; fi; }' 'then timeout -k 10 "$NET_TIMEOUT" "$@"; else "$@"; fi; }'   # nt without rc_net
mp NN10 '29c' "$PUB" '"$_rpg_tok" | rc_net curl "${args[@]}"' '"$_rpg_tok" | curl "${args[@]}"'   # the publisher's curl outside rc_net
mp NN11 'C52' "$TAR" '  rc_net bash scripts/badges/compute_badges.sh' '  bash scripts/badges/compute_badges.sh'   # the badge computer (it runs git) outside rc_net
mp NN12 'R11|N-1' "$LIB" "_RC_LOCALE_CODESET='utf-?8|" "_RC_LOCALE_CODESET='[0-9a-f]{40}|utf-?8|"   # the closed codeset list widened (N-1: a 40-hex value)
mp NN13 'L2 .*net' "$DRF" 'rc_net git show "$B:docs/workable_items.db"' 'git show "$B:docs/workable_items.db"'   # a derive git outside rc_net
mp NN14 '29c' "$PUB" 'TARGET="$(rc_net git rev-list' 'TARGET="$(git rev-list'   # the publisher's git outside rc_net
mp NN15 'K11 an exported function' "$LIB" '    for _rc_v in $(builtin compgen -A function); do builtin export -n -f "$_rc_v" 2>/dev/null; done' '    :'   # exported functions reach the network child
mp NN16 'K11 .*LC_ALL' "$LIB" '    builtin export LC_ALL=C GIT_TRACE_REDACT=1' '    builtin export GIT_TRACE_REDACT=1'   # the LC_ALL=C constant dropped
# --- round 13: the network-spawn gate (channel_census.py netgate) against tests/release/test_channel_census.sh
# (CEN_PY), MS1 against tests/release/test_derive_release_facts.sh (C53). Generated by
# docs/qa/con227_234_2026_11_11/round13/tools/mut13.py emit (one spec; never edited by hand): GN1-GN4, NR1, NR6,
# NR7, NR10, NR11, NR14, NR17, NR28 and NR30 keep their round-12 text; the other round-12 gate mutants are
# re-applied to the round-13 rule that does the same job; MR5x-MR10y re-apply the round-12 reviewer's MR5-MR10;
# PN1-PN19 mutate the pin (layer 1), AN1-AN42 the analyser (layer 2; AN16 and AN19 not used); PN13 is recorded
# equivalent with its probe (docs/qa/con227_234_2026_11_11/round13/mutants.md). The round-11 reviewer's RM*
# mutants after this block are kept from round 12 ---
mp GN1 'git in backticks|CI79_backtick_nested|O07_backtick_escaped_nested' "$CENPY" $'        c = self.child("".join(buf), start + 1)\n        c.parse_all()' '        pass'   # backticks not read as code (a command in `...` is not seen)
mp GN2 'CTRL_POS_plain_git|a bare git' "$CENPY" 'NETCMDS = {"git", "ssh",' 'NETCMDS = {"ssh",'   # git not a network command
mp GN3 'CI44_nt_twice|CI45_nt_assign|CI46_nt_extra|untrusted nt' "$CENPY" '        self.trusted = {"rc_net"}' '        self.trusted = {"rc_net", "nt", "net"}'   # nt and net trusted without reading their definitions
mp GN4 'G36_var_cmd|G44_dq_var_cmd|CI47_own_rc_net|CI78_bash_word_cmd|a command in a variable' "$CENPY" $'        if w.dyn:\n            why = "expansion in command position"' $'        if w.dyn:\n            return False'   # a command in a variable not reported
mp NR1 'G16_relative_path|G17_abs_path_git|CI26_brace_cmdword|CI27_glob_cmdword|CI28_tilde_cmdword' "$CENPY" $'        if w.lit and CMDNAME_RE.match(w.sval):\n            return True' $'        if w.lit:\n            return True'   # a literal command word with a path, glob, brace or tilde taken as a plain name
mp NR6 'G06_sed_e_cmd' "$CENPY" '        if c in "erRwWv":' '        if c in "rRwWv":'   # the sed e command not named
mp NR7 'G07_sed_s_e_flag|CI34_sed_w_flag' "$CENPY" '            if i < n and sc[i] in "ewW":' '            if i < n and sc[i] in "W":'   # the s///e and s///w flags not named
mp NR10 'G05_awk_multiline_system|G05b_awk|G05c_awk' "$CENPY" $'    if re.search(r\'\\bsystem\\b\', s):' '    if False:'   # awk system() allowed
mp NR11 'CI38_awk_print_pipe|CI39_awk_getline_pipe' "$CENPY" '    if "|" in s.replace("||", "  "):' '    if False:'   # an awk pipe to or from a command allowed
mp NR14 'CI06_path_tempenv|CI09_export_path|CI65_read_path|CI66_getopts_path' "$CENPY" 'DANGER_NAMES = {"PATH", ' 'DANGER_NAMES = {'   # an assignment to PATH allowed
mp NR17 'CI45_nt_assign|CI46_nt_extra' "$CENPY" 'if body and all(self.wrapper_cmd_ok(f, c) for c in body) and any(' 'if body and any('   # the body of a wrapper candidate not checked
mp NR28 'CI23_arith_quoted' "$CENPY" '                if SUBST_RE.search(t[self.i + 1:j]):' '                if False:'   # a single-quoted command substitution in arithmetic allowed
mp NR30 'the parser cannot read' "$CENPY" $'        findings += parse_errors(s)   # round 12: a script the parser cannot read is a finding, never a short census\n' $'        pass\n'   # the lint does not report a parse error (a short census)
mp GN5 'G21_git_via_gitdashcmd|G22_python_via_absent_name|an unknown command' "$CENPY" '            self.find("unclassified command (default deny): %s:%d %s" % (u.name, line, prog), u, line)' '            pass'   # an unknown program name not reported (round 13: re-applied to the site rule)
mp GN6 'G29_xargs_git|G30_env_git|G31_nice_git|G37_bash_c|git under env|git under nice|bash -c' "$CENPY" '            if (u.name, via, tuple(x.raw for x in [w] + list(args))) in ALLOW_EXEC:' '            if True:'   # every interpreter and exec wrapper allowed (round 13: the parsed-word match)
mp NR2 'G13_trap_sq|G14_trap_dq' "$CENPY" $'                if a.sval in ("", "-") or FUNC_RE.match(a.sval):\n                    continue' $'                if True:\n                    continue'   # a trap string not read as code (round 13: load())
mp NR3 'G01_coproc|O56_coproc' "$CENPY" '        if w in ("until", "select", "coproc"):' '        if w in ("until", "select"):'   # coproc allowed (round 13: the parser refusal)
mp NR4 'G15_alias|O46_alias' "$CENPY" 'BUILTIN_ALLOWED = {".", ":", "[",' 'BUILTIN_ALLOWED = {"alias", ".", ":", "[",' $'        else:\n            bad("without a grammar (an internal error of the gate)")' $'        else:\n            pass'   # alias allowed (round 13: on the closed list, and the fail-closed else of the builtin grammar dropped)
mp NR5 'G11_command_p|CI30_command_git|G34_builtin_command_git|O15_command_p|C53 netgate control needle' "$CENPY" '            if not (len(args) == 2 and sv[0] == "-v"):' '            if False:'   # command other than command -v NAME allowed (round 13: the command grammar)
mp NR8 'G08_sort_compress_prog|CI42_sort_long_abbrev|D9_sort_compress_sep|O28_sort_compress_attached|O70_sort_long_option_alone' "$CENPY" '            if any(x != "-V" for x in sv):' '            if any(x != "-V" and not (x or "").startswith("--") for x in sv):'   # a long option of sort allowed (round 13: sort -V only; also covers the reviewer's MR9; killed by O70, the only control with a long option and no other operand)
mp NR9 'G09_sqlite_system|O25_sqlite_safe_not_first' "$CENPY" '            if sv[:1] != ["-safe"]:' '            if False:'   # sqlite3 without -safe first allowed
mp NR12 'CI70_exec_unknown_opt' "$CENPY" $'                else:\n                    bad("with the option %s" % sv[j])\n                    return' $'                else:\n                    j += 1'   # an unknown exec option skipped
mp NR13 'O47_source_other' "$CENPY" '                    not any(x[0] == u.name and x[1] == ws[1].raw for x in SOURCE_OK)):' '                    False):'   # a source command outside SOURCE_OK allowed
mp NR15 'CI19_let_subscript' "$CENPY" 'BUILTIN_ALLOWED = {".", ":", "[",' 'BUILTIN_ALLOWED = {"let", ".", ":", "[",' $'        else:\n            bad("without a grammar (an internal error of the gate)")' $'        else:\n            pass'   # let allowed (round 13: let is off the closed list)
mp NR16 'CI20_cond_subscript|O09_cond_eq_PATH|O10_cond_v_subscript' "$CENPY" '            self.refuse(start, "[[ ]] outside the closed grammar: %s" % why)' '            pass'   # [[ ]] outside its closed grammar allowed (round 13: cond_check)
mp NR18 'CI18_unset_f|O35_unset_f_rc_net' "$CENPY" $'            else:\n                bad("other than unset -v NAME... or unset \'NAME[SUBSCRIPT]\'")' $'            else:\n                pass'   # unset -f allowed (round 13: the unset grammar)
mp NR19 'CI16_set_x' "$CENPY" 'SET_ARGS = {"+x", "-u", "-f", "+f"}' 'SET_ARGS = {"+x", "-x", "-u", "-f", "+f"}'   # set -x allowed
mp NR20 'CI03_prompt_expansion|O12_param_P_transform' "$CENPY" 'PARAM_OPS = {"", ":-",' 'PARAM_OPS = {"@", "", ":-",'   # ${x@P} allowed (round 13: the operator list)
mp NR21 'O68_funsub_unquoted|O69_valuesub_unquoted' "$CENPY" '            self.refuse(start, "${ command; } substitution (bash 5.3): a command list inside a parameter expansion")' '            pass'   # ${ cmd; } and ${| cmd; } allowed (round 13: killed by the unquoted forms O68 O69)
mp NR22 'CI04_dev_tcp|CI05_dev_udp|O45_dev_tcp' "$CENPY" '        elif "/dev/" in target and target != "/dev/null":' '        elif False:'   # a /dev/tcp or /dev/udp redirection allowed (round 13: every device file but /dev/null)
mp NR23 'CI10_declare_n|O36_declare_n|D3_declare_gn_PATH' "$CENPY" $'            else:\n                bad("other than declare -A NAME")' $'            else:\n                pass'   # declare -n allowed (round 13: declare -A NAME only; also covers the reviewer's MR3)
mp NR23b 'CI75_local_n|O37_local_i' "$CENPY" $'                if w.sval == "-":\n                    continue' $'                if w.sval.startswith("-"):\n                    continue'   # local -n allowed (round 13: local takes only - and names)
mp NR24 'CI08_hash_p|O14_hash_p' "$CENPY" 'BUILTIN_ALLOWED = {".", ":", "[",' 'BUILTIN_ALLOWED = {"hash", ".", ":", "[",' $'        else:\n            bad("without a grammar (an internal error of the gate)")' $'        else:\n            pass'   # hash -p allowed
mp NR25 'G35_eval_git|CI31_builtin_eval|O48_eval' "$CENPY" $'        elif s == "eval":\n            bad("outside the exact sites of DYN_SITES")' $'        elif s == "eval":\n            pass'   # eval allowed (round 13: eval only at the exact DYN_SITES)
mp NR26 'CI13_mapfile_callback|D2_mapfile_tC|D2b_mapfile_C_attached' "$CENPY" 'BUILTIN_ALLOWED = {".", ":", "[",' 'BUILTIN_ALLOWED = {"mapfile", ".", ":", "[",' $'        else:\n            bad("without a grammar (an internal error of the gate)")' $'        else:\n            pass'   # mapfile -C allowed (round 13: mapfile is off the closed list; also covers the reviewer's MR2)
mp NR27 'CI14_compgen_c|D1_compgen_W|O13_compgen_V' "$CENPY" '            if sv not in (["-e"], ["-A", "function"]):' '            if False:'   # compgen -C/-W/-V allowed (round 13: the compgen grammar; also covers the reviewer's MR1)
mp NR29 'CI21_assign_subscript|O43_subscript_assigns_PATH' "$CENPY" $'        if why:\n            self.find("a subscript of the indexed array' $'        if False:\n            self.find("a subscript of the indexed array'   # a subscript outside the arithmetic grammar allowed (round 13: subscript())
mp NR32 'lint depends on the host PATH|lint misses|lint rc=|stale row' "$CENPY" '           for n, l, p, via, _cls, norm in g.sites if n == base and not p.startswith(("rc_", "_rc_"))]' '           for n, l, p, via, _cls, norm in g.sites if n == base and not p.startswith(("rc_", "_rc_")) and __import__("shutil").which(p)]'   # the round-11 host lookup put back into the lint census
mp NR33 'G10_absent_netcmd_aria2c|depends on the host PATH|golden-FALSE' "$CENPY" $'        else:\n            self.external(u, c, k, "")\n\n    def builtin' $'        elif __import__("shutil").which(s):\n            self.external(u, c, k, "")\n\n    def builtin'   # the round-11 host lookup put back into the gate
mp MR5x 'MR5a_LD_LIBRARY_PATH_prefix|MR5b_export_LD_AUDIT' "$CENPY" '    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))' '    return name in DANGER_NAMES or name.startswith(("LD_PRELOAD", "GCONV_"))'   # MR5 re-applied: LD_LIBRARY_PATH and LD_AUDIT not dangerous
mp MR6x 'D6_sqlite_nonce' "$CENPY" 'SQLITE_OPTS = {"-readonly",' 'SQLITE_OPTS = {"-nonce", "-readonly",'   # MR6 re-applied: sqlite3 -nonce allowed
mp MR7x 'D7_awk_attached_f' "$CENPY" '                if s.startswith(("-F", "-v")) and len(s) > 2:' '                if s.startswith(("-F", "-v", "-f")) and len(s) > 2:'   # MR7 re-applied: awk -fFILE skipped as an attached option
mp MR8x 'D8_read_r_PATH' "$CENPY" $'                if sv[j] == "-r":\n                    j += 1' $'                if sv[j] == "-r":\n                    j += 2'   # MR8 re-applied: the name after read -r taken as an option value
mp MR10x 'MR10a_shopt_extdebug' "$CENPY" '            if sv != ["-s", "execfail"]:' '            if sv not in (["-s", "execfail"], ["-s", "extdebug"]):'   # MR10 re-applied: shopt -s extdebug allowed
mp MR10y 'MR10b_set_o_extdebug' "$CENPY" 'SET_ARGS = {"+x", "-u", "-f", "+f"}' 'SET_ARGS = {"+x", "-u", "-f", "+f", "-o", "extdebug"}'   # MR10 re-applied: set -o extdebug allowed
mp MS1 'C53 netgate' "$DRF" 'q() { sqlite3 -safe -readonly' 'q() { sqlite3 -separator -safe -readonly'   # the round-12 reviewer's MS1 verbatim: -safe swallowed as the value of -separator (killed by the derive suite's C53)
mp PN1 'netgate pin: a trailing space|netgate pin: an appended comment line' "$CENPY" $'        if sha(u.text) == h and len(u.lines) == nl:\n            continue' $'        if True:\n            continue'   # the byte comparison of a pinned file skipped
mp PN2 'netgate pin: a trailing space' "$CENPY" $'            if new != old:\n                out.append("PIN %s:%d line key' $'            if (new or (None,))[0] != (old or (None,))[0]:\n                out.append("PIN %s:%d line key'   # a line compared by its normalised key only (a trailing space passes the line check)
mp PN3 'netgate pin: a file that is not on the pin' "$CENPY" '        out.append("PIN a file that is not on the pin: %s" % name)' '        pass'   # a file that is not on the pin not reported
mp PN4 'netgate pin: a file of the pin that was not given' "$CENPY" '        out.append("PIN a file of the pin that was not given or loaded: %s" % name)' '        pass'   # a pinned file that was not given not reported
mp PN5 'netgate pin: a site row removed from the pin' "$CENPY" '    for s in sorted(got - pin["S"]):' '    for s in sorted(set()):'   # a site that is not on the pin not reported
mp PN6 'netgate pin: a site row the analyser does not find' "$CENPY" '    for s in sorted(pin["S"] - got):' '    for s in sorted(set()):'   # a pinned site the analyser does not find not reported
mp PN7 $'netgate pin: an unreadable pin|unreadable pin \\(the name' "$CENPY" '        pin["bad"].append("the pin table cannot be read: %s" % e.strerror)' '        pass'   # an unreadable pin not reported
mp PN8 'netgate pin: a pin with no rows' "$CENPY" '    if not pin["F"] or not pin["N"]:' '    if False:'   # a pin with no F or N rows accepted
mp PN9 'netgate pin: a row the gate does not know' "$CENPY" '                pin["bad"].append("pin table line %d: a row the gate does not know" % n)' '                pass'   # an unknown pin row skipped
mp PN10 'netgate pin: a number field that is not a number' "$CENPY" '            pin["bad"].append("pin table line %d: a number field that is not a number" % n)' '            pass'   # a pin row with a bad number skipped
mp PN11 'netgate pin: netgate without --pin' "$CENPY" '        if rest[:1] != ["--pin"] or len(rest) < 2:' '        if len(rest) < 2:'   # netgate without --pin runs (the first script read as the pin)
mp PN12 'pin-regen is refused|pin-regen with a finding' "$CENPY" $'    if bad:\n        for f in bad:\n            print("REFUSED " + f)\n        return 1' $'    if False:\n        for f in bad:\n            print("REFUSED " + f)\n        return 1'   # pin-regen writes the table while the analyser has a finding
mp PN14 $'unreadable pin \\(the name' "$CENPY" '    if analyser_only and pin["bad"]:' '    if False:'   # the analyser alone ignores an unreadable pin (its name and program lists come from the pin)
mp PN15 'committed pin differs|pin-diff of the committed|pin-diff shows a changed file' "$CENPY" '            rows.append(("L", u.name, str(i), k8, s16))' '            rows.append(("L", u.name, str(i), k8, l[:40]))'   # the pin and pin-diff carry script text
mp PN16 'committed pin differs' "$CENPY" '        if name not in first or (u.name, line) < first[name]:' '        if name not in first:'   # the name rows depend on the argument order
mp PN17 'pin-diff of a changed copy' "$CENPY" '    return 1 if (old != new or g.findings) else 0' '    return 1 if g.findings else 0'   # pin-diff exits 0 on a difference
mp PN18 'netgate pin: a site row the analyser does not find|netgate pin: a site row removed' "$CENPY" '    got = {(n, l, p, v or "", c, sha(norm)[:8]) for n, l, p, v, c, norm in g.sites}' '    got = set(pin["S"])'   # the analyser's sites not compared with the pin
mp PN19 'netgate pin: pin-regen BLIND' "$CENPY" $'    if not g.sites:\n        bad.append("BLIND: no invocation found")' $'    if False:\n        bad.append("BLIND: no invocation found")'   # pin-regen writes a table for files with no invocation (BLIND)
mp AN1 'O66_arith_increment' "$CENPY" '        if tok in ("+", "-") and prev == tok:' '        if False:'   # ++ and -- allowed in arithmetic
mp AN2 'O67_indirect_plain|O19_indirect_default_assign' "$CENPY" '        if (script, name) not in INDIRECT_OK or subs:' '        if False:'   # every indirect expansion allowed
mp AN3 'O65_awk_v_escape' "$CENPY" $'        if s is not None and ("inet" in s or "\\\\" in s):' '        if False:'   # an awk -v value with an escape or inet allowed
mp AN4 'O62_awk_pinned_operand_inet' "$CENPY" '                if w.sval is not None and ("inet" in w.sval or re.match(' '                if False and ("inet" in w.sval or re.match('   # an awk operand /inet/... or NAME=VALUE allowed
mp AN5 'O26_unpinned_awk|O27_unpinned_sed' "$CENPY" '        if self.pin is not None and not self.regen and (kind, h) not in self.pin["P"]:' '        if False:'   # an awk or sed program off the pin's whitelist allowed
mp AN6 'O61_name_not_on_pin' "$CENPY" '            if self.pin is not None and not self.regen and name not in self.pin["N"]:' '            if False:'   # a write to a name off the pin's name list allowed
mp AN7 'O23_duplicate_definition' "$CENPY" $'                if rec[0] in defs:\n                    self.find("a function defined twice' $'                if False:\n                    self.find("a function defined twice'   # a function defined twice allowed
mp AN8 'O22_call_before_definition|O60_trap_action_function_late' "$CENPY" '                if g in defs and defs[g] >= k:' '                if False:'   # a call before the definition allowed
mp AN9 'O21_nested_function' "$CENPY" '        if not top:' '        if False:'   # a function defined outside the top level allowed
mp AN10 'O24_function_named_like_builtin' "$CENPY" '        if name in BASH_BUILTINS or name in RESERVED or name in NETCMDS or name in EXECWRAP or name in LOCAL_OK:' '        if False:'   # a function named like a builtin or a program allowed
mp AN11 'O04_background' "$CENPY" '                self.refuse(self.i, "& (a background job runs past the statement that started it)")' '                pass'   # a background job allowed
mp AN12 'O05_pipe_stderr' "$CENPY" '                self.refuse(self.i, "|& (a pipe of standard error)")' '                pass'   # |& allowed
mp AN13 'O03_function_keyword' "$CENPY" '            self.refuse(i, "the function keyword (a definition is NAME() { ... } at the top level)")' '            pass'   # the function keyword allowed
mp AN14 'O42_process_substitution' "$CENPY" '                        self.refuse(start, "a process substitution that is not the target of a redirection")' '                        pass'   # a process substitution as an argument allowed
mp AN15 'O08_locale_string_comsub' "$CENPY" $'            self.refuse(i, \'$"..." (a locale translation of a string)\')' '            pass'   # $"..." allowed
mp AN17 'O01_old_arith_PATH' "$CENPY" '            self.refuse(i, "$[ ... ] (the old arithmetic expansion)")' '            pass'   # $[ ] allowed
mp AN18 'O02_for_arith_PATH' "$CENPY" '            self.refuse(i, "for (( ... )) (an arithmetic loop)")' '            pass'   # for (( )) allowed
mp AN20 'O20_arith_name_holds_assignment' "$CENPY" '                if why and (wu.name, func, name) not in A6_DATA:' '                if False:'   # a non-numeric value of a name read in arithmetic allowed (A6)
mp AN21 'O58_fd_name_written_text' "$CENPY" $'            if name in fdn and (val is None or val.sval is None or not re.match(r\'[0-9]+\\Z\', val.sval)):' '            if False:'   # a file-descriptor name holding text allowed
mp AN22 'O39_redirect_read_write|O40_redirect_both' "$CENPY" '        if op not in REDIR_OK:' '        if False:'   # every redirection operator allowed
mp AN23 'O44_exec_fd5' "$CENPY" '        if fd not in REDIR_FDS:' '        if False:'   # a redirection of any file descriptor allowed
mp AN24 'O41_redirect_fd_variable' "$CENPY" '                    self.refuse(self.i, "a {name} redirection (it assigns the name)")' '                    pass'   # {fd} redirection allowed
mp AN25 'O30_printf_v_PATH|O31_printf_dynamic_format' "$CENPY" '            if not sv or sv[0] is None or (sv[0].startswith("-") and not dd):' '            if not sv:'   # printf -v and a dynamic format allowed
mp AN26 'O32_trap_USR1' "$CENPY" '            if len(args) < 2 or sv[0] is None or any(x not in TRAP_SIGNALS for x in sv[1:]):' '            if len(args) < 2 or sv[0] is None:'   # trap on any signal allowed
mp AN27 'O33_shopt_expand_aliases|MR10a_shopt_extdebug' "$CENPY" '            if sv != ["-s", "execfail"]:' '            if False:'   # every shopt allowed
mp AN28 'O50_IFS_dynamic' "$CENPY" '                      val.sval is not None and val.sval in IFS_VALUES)' '                      True)'   # IFS with any value allowed
mp AN29 'O29_exec_program' "$CENPY" '            if (u.name, "exec", prog) in ALLOW_EXEC:' '            if True:'   # exec of any command allowed
mp AN30 'O64_builtin_builtin' "$CENPY" '            if args and args[0].lit and args[0].sval in BUILTIN_ALLOWED and args[0].sval != "builtin":' '            if args and args[0].lit and args[0].sval in BUILTIN_ALLOWED:'   # builtin builtin allowed
mp AN31 'O38_read_a' "$CENPY" $'                else:\n                    bad("with the option %s (only -r and -d)" % sv[j])\n                    return' $'                else:\n                    j += 1'   # read with any option allowed
mp AN32 'O57_select' "$CENPY" '        if w in ("until", "select", "coproc"):' '        if w in ("until", "coproc"):'   # select allowed
mp AN33 'O16_CDPATH' "$CENPY" '"BASHOPTS", "BASH_LOADABLES_PATH", "BASH_CMDS", "BASH_ALIASES", "GCONV_PATH", "CDPATH",' '"BASHOPTS", "BASH_LOADABLES_PATH", "BASH_CMDS", "BASH_ALIASES", "GCONV_PATH",'   # CDPATH not dangerous
mp AN34 'O72_GCONV_prefix_other' "$CENPY" '    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))' '    return name in DANGER_NAMES or name.startswith(("LD_",))'   # the GCONV_ prefix not dangerous (O59 writes GCONV_PATH, also on DANGER_NAMES; O72 writes GCONV_ZZ)
mp AN35 'O53_ENV|O51_export_BASH_ENV' "$CENPY" 'DANGER_NAMES = {"PATH", "EXECIGNORE", "BASH_ENV", "ENV",' 'DANGER_NAMES = {"PATH", "EXECIGNORE",'   # BASH_ENV and ENV not dangerous
mp AN36 'CI01_funsub|CI02_valuesub|parse error' "$CENPY" $'            self.findings.append("parse error (the gate refuses what it cannot read): %s" % e)\n        # the action' $'            pass\n        # the action'   # a parse error of a script not reported (the gate passes a script it cannot read)
mp AN37 'O73_heredoc_body_read' "$CENPY" $'            if not quoted:\n                c = self.child(text, start)\n                c.read_dq(None)' $'            if False:\n                c = self.child(text, start)\n                c.read_dq(None)'   # an unquoted here-document body not read (the refusal of `<<` stays; the finding for the command substitution in the body is lost; killed by O73)
mp AN38 'O11_param_replace_comsub' "$CENPY" '        return "the operator %s (:= and = assign; @, / and the others are not on the list)" % op, arr, subs, offs' '        return None, arr, subs, offs'   # every parameter operator allowed
mp AN39 'O52_LD_PRELOAD_prefix' "$CENPY" '    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))' '    return name in DANGER_NAMES or name.startswith(("GCONV_",))'   # the LD_ prefix not dangerous
mp AN40 'netgate prints the line text or no key' "$CENPY" '        f = "%s | key=%s" % (msg, key)' '        f = "%s | %s" % (msg, self.norm(u, line)[:100])'   # a finding prints the line text (O2 of the round-12 review)
mp AN41 'lint misses a new token line, printed by its key only' "$CENPY" 'findings.append("secret reference with no secret-ref or allowed row: %s:%d key=%s" % (a, i, k))' 'findings.append("secret reference with no secret-ref or allowed row: %s:%d key=%s | %s" % (a, i, k, _norm))'   # a lint finding on a secret line prints the line text (O2)
mp AN42 'lint misses a new command with no row, printed by its key only' "$CENPY" 'findings.append("no row: %s:%d %s key=%s" % (a, i, c, k))' 'findings.append("no row: %s:%d %s key=%s | %s" % (a, i, c, k, _norm))'   # a lint no-row finding prints the line text (O2)
meq PN13 "$CENPY" '        if is_danger(name) and name != "IFS":' '        if False:' 'pin-regen refuses on every analyser finding first, and the analyser reports every write of a name of DANGER_NAMES (IFS only with a closed value), so the second check in pin_regen cannot change the outcome; probe: round13/mutants.md PN13'
mp RM2 'C53 netgate' "$DRF" $'B="$(rc_net git rev-parse -q --verify "$BASE^{commit}")"' $'B="$("git" rev-parse -q --verify "$BASE^{commit}")"'   # quoted "git" rev-parse in derive
mp RM9 'K11' "$LIB" $'case "$_RC_NET_KEEP" in *" $_rc_v "*) _rc_env_shape_ok "$_rc_v" "${!_rc_v}" && continue ;; esac' $'case "$_RC_NET_KEEP" in *" $_rc_v "*) continue ;; esac'   # rc_net keeps allow-listed names without their shape check
mp RM10 'K11|C48' "$LIB" $'GLAB_CONFIG_DIR GITLAB_HOST "\n_RC_NET_CONST' $'GLAB_CONFIG_DIR GITLAB_HOST TZ SHELL LANGUAGE "\n_RC_NET_CONST'   # TZ SHELL LANGUAGE added to _RC_NET_KEEP
mp RM12 '28 X11' "$PUB" $'unset -v "$TOKEN_VAR" 2>/dev/null || true' $'true'   # publisher keeps the token variable (unset removed) (re-applied to the round-12 line)
mp RM19 'K11' "$LIB" $'builtin export LC_ALL=C GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0 GIT_TRACE2=0' $'builtin export LC_ALL=C GIT_TRACE2=0'   # rc_net constants without GIT_TERMINAL_PROMPT/GIT_TRACE_REDACT
mp RM20 'R12 F2' "$LIB" $'_RC_LOCALE_MOD=\'euro|latin|cyrillic|devanagari|iqtelif|saaho|valencia|abegede|hebrew|ijekavian|ijekavianlatin|shaw|quot|boldquot\'' $'_RC_LOCALE_MOD=\'[a-z0-9]{1,32}\''   # locale modifier widened
mp RM21 'K8|K9' "$LIB" $'re=\'^(C|POSIX|[a-z]{2,3}(_([A-Z]{2}|[0-9]{3}))?)$\'' $'re=\'^(C|POSIX|[a-z0-9]{2,40}(_([A-Z]{2}|[0-9]{3}))?)$\''   # locale language widened
mp RM25 'K11' "$LIB" $'    IFS=$\' \\t\\n\'; set -f\n    for _rc_v in $(builtin compgen -e); do\n      case "$_RC_NET_KEEP" in' $'    for _rc_v in $(builtin compgen -e); do\n      case "$_RC_NET_KEEP" in'   # rc_net without IFS reset / set -f
mp RM26 'K11' "$LIB" $'  [ "$_RC_ENV_STATE" = clean ] || { printf \'rc_net: refused: the environment was not rebuilt by rc_env_clean\\n\' >&2; return 125; }' $'  :'   # rc_net without the clean-state precondition
mp RM27 'token in curl argv|on curl.s stdin|curl without -q' "$PUB" $'x_curl="$(printf \'header = "Authorization: token %s"\\n\' "$_rpg_tok" | rc_net curl "${args[@]}" ' $'x_curl="$(printf \'\' | rc_net curl -H "Authorization: token $_rpg_tok" "${args[@]}" '   # publisher token in curl argv instead of -K - stdin
mp RM28 'K11' "$LIB" $'for _rc_v in $(builtin compgen -A function); do builtin export -n -f "$_rc_v" 2>/dev/null; done' $'true'   # rc_net function un-export skipped
mp RM30 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  command -p git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n'   # NEW line: command -p git fetch (no rc_net)
mp RM30b 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  command -p git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :; hash -r\n'   # NEW line: command -p git fetch, then hash -r (no rc_net, no hash-table side effect)
mp RM31 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  "git" fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n'   # NEW line: "git" fetch with a quoted command word (no rc_net)
mp RM32 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  >/dev/null 2>&1 git fetch -q --no-tags "$r" refs/heads/main || :\n'   # NEW line: redirection before git fetch (no rc_net)
mp RM33 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n'   # NEW line: plain git fetch (no rc_net) - control mutant
mp RM34 'C53 netgate' "$TAR" $'  RMAIN[$r]="$t"\n' $'  RMAIN[$r]="$t"\n  /usr/bin/git fetch -q --no-tags "$r" refs/heads/main >/dev/null 2>&1 || :\n'   # NEW line: /usr/bin/git fetch (absolute path, no rc_net)
# round 11 (the recorder race found by the second suite run): EC1 restores the round-10 recorder (the block appended
# to the shared log in several writes), EC2 writes the header line outside the private file; both must be caught by
# the R11 RACE check of the redact suite (200 concurrent pairs, 0 misattributed records)
mp EC1 'R11 RACE' "$ECPY" $'  done; } >"$t"\n[ -s "$t" ] || { printf \'env_census recorder: cannot write %%s\\\\n\' "$t" >&2; exit 125; }\n\'%(flock)s\' \'%(log)s\' \'%(cat)s\' "$t" >>\'%(log)s\' || { printf \'env_census recorder: append to the log failed\\\\n\' >&2; exit 125; }\n\'%(rm)s\' -f "$t"\n' $'  done; } >>\'%(log)s\'\n'
mp EC2 'R11 RACE' "$ECPY" $'t=\'%(log)s.rec.\'$$\n{ printf \'== %%s\\\\n\' \'%(cmd)s\';' $'t=\'%(log)s.rec.\'$$\nprintf \'== %%s\\\\n\' \'%(cmd)s\' >>\'%(log)s\'\n{ :;'
# CON-416 (2026-11-15): the GitLab pre-release marking and read-back of tag_and_release.sh; each mutant
# must be killed by the GL case that targets it (mp, pattern = the GL case names)
mp GP1 $'GL4 |GL5 ' "$TAR" $'  [ -n "$GL_RELEASED_AT" ] && GL_ARGS+=(--released-at "$GL_RELEASED_AT")' $'  :'   # the upcoming date is not passed to glab
mp GP2 $'GL6 ' "$TAR" $'  [ "$GL_AT" -gt "$(date -u +%s)" ] || die_usage' $'  true || die_usage'   # the future-date check removed
mp GP3 $'GL5 ' "$TAR" $'[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] \\\n' $'[0-9]{2}Z$ ]] \\\n'   # the offset form of the ISO time refused
mp GP4 $'GL6 ' "$TAR" $'  [ "$PRERELEASE" -eq 1 ] || die_usage "--gitlab-released-at is only' $'  true || die_usage "--gitlab-released-at is only'   # an upcoming date allowed on a final release
mp GP5 $'GL3 ' "$TAR" $'if [ "$PRERELEASE" -eq 1 ] && [ "$GL_ANY" -eq 1 ]; then' $'if [ "$GL_ANY" -eq 1 ]; then'   # a final release is marked PROVISIONAL
mp GP6 $'GL2 ' "$TAR" $'*PROVISIONAL*) ;; *) GL_TITLE=' $'*NOT-A-TITLE-WORD*) ;; *) GL_TITLE='   # a title that says PROVISIONAL is prefixed twice
mp GP7 $'GL1 ' "$TAR" $'{ printf \'%s\\n\\n\' "$GL_MARK"; cat -- "$NOTES"; }' $'{ cat -- "$NOTES"; }'   # the description mark line removed
mp GP8 $'GL9b? ' "$TAR" $'    marked) ;;\n    unmarked) fail' $'    marked|unmarked) ;;\n    unmarked) fail'   # an unmarked read-back accepted
mp GP9 $'GL9b? ' "$TAR" $'        and ((((.description' $'        or ((((.description'   # the name OR the description is enough
mp GP10 $'GL10b? ' "$TAR" $'  elif [ "$up" != true ]; then' $'  elif false; then'   # upcoming_release=false accepted
mp GP11 $'GL1 ' "$TAR" $'GL_ARGS=(--no-update)' $'GL_ARGS=()'   # --no-update dropped
mp GP12 $'GL12 ' "$TAR" $'        [ "$PRERELEASE" -eq 1 ] && gl_readback "$spec" "$target"; continue; fi' $'        continue; fi'   # a kept release not read back
mp GP13 $'GL7 ' "$TAR" $'  [ "$arc" -eq 0 ] || { gap "RELEASE $1 PRERELEASE-READBACK UNCONFIRMED (glab api read failed' $'  [ "$arc" -eq 0 ] || true || { gap "RELEASE $1 PRERELEASE-READBACK UNCONFIRMED (glab api read failed'   # a failed read-back not reported as a GAP
mp GP14 $'GL8 ' "$TAR" $'    marked) ;;\n    unmarked) fail' $'    marked|unparsable) ;;\n    unmarked) fail'   # an unparsable read-back accepted as marked
mp GP15 $'GL13 ' "$TAR" $'      gitlab:*:1) printf \'PLAN release' $'      gitlab:*:1) nt glab release create "$TAG" -R x >/dev/null 2>&1; printf \'PLAN release'   # the dry run makes a write call (CON-423: since D3 the dry run reads with auth status, so the mutant is a create call)
mp GP16 $'GL13 ' "$TAR" $'      gitlab:*:1) printf \'PLAN release' $'      *:*:1) printf \'PLAN release'   # the marking plan line on every forge
mp GP17 $'GL14 ' "$TAR" $'gap "RELEASE $spec SKIPPED-NO-TOKEN (glab not authenticated)"; continue; fi' $'printf \'RELEASE %s CREATED\\n\' "$spec"; continue; fi'   # glab not authenticated reported as CREATED
mp GP18 $'GL15 |GL16 ' "$TAR" $'  j="$(nt glab api --hostname' $'  j="$(glab api --hostname'   # the read-back without the timeout wrapper nt
mp GP19 $'GL10b? ' "$TAR" $'  elif [ "$rat" = NOT-AN-ISO-TIME ] || [ "$(date -u -d "$rat" +%s 2>/dev/null)" != "$GL_AT" ]; then' $'  elif false; then'   # a different upcoming date accepted
mp GP20 $'GL11 ' "$TAR" $'|| rat=NOT-AN-ISO-TIME\n' $'|| :\n'   # a server released_at that is not an ISO time printed raw
mp GP21 $'GL1 ' "$TAR" $'nt glab api --hostname "$GL_HOST" "projects/$enc/releases/' $'nt glab api "projects/$enc/releases/'   # the read-back host not pinned with --hostname (landing merge: the dry-run probe also reads projects/$enc, so the release read-back line is named)
# CON-417 (2026-11-15): the retest_statement verdict check of render_release_entry.py; B-M1 (2026-11-16) rewrote the
# check (verdict words from the runner's RETEST_RESULTS), so RV1-RV4 are re-applied to the lines that now do the same job
mp RV1 $'retest value without a leading verdict token refused' "$RRE" $'                rv = retest_value(val, words)\n                if rv is None:' $'                rv = val\n                if False:'   # the verdict check removed
mp RV2 $'retest value without a leading verdict token refused: the retest: PASS-FULL' "$RRE" $'        if v.startswith(w) and not re.match(r"[\\w-]", v[len(w):len(w) + 1]):' $'        if re.search(re.escape(w) + r"(?![\\w-])", v):'   # the verdict word anywhere, not at the start
mp RV3 $'refused: (PASS-FULLY done|FAILED)|not a run verdict refused: (PASS-FULL-WITH|PARTIAL-TOPOLOGYX)' "$RRE" $' and not re.match(r"[\\w-]", v[len(w):len(w) + 1]):' $':'   # a longer word starting with a verdict word accepted
mp RV4 $'retest verdict accepted: NOT' "$RRE" $'    return sorted(words + [("NOT RUN", "not-run")], key=lambda x: -len(x[0]))' $'    return sorted(words, key=lambda x: -len(x[0]))'   # NOT RUN refused (an honest not-run entry cannot be written)
# B-M1 (2026-11-16, fixer's own): the gap notes and the fail-closed read of the runner's table
mp BM1A $'B-M1 runner verdict PARTIAL-DEFAULT-SET rendered as gap|B-M1 PARTIAL-SKIPS never rendered bare' "$RRE" $'         "gap": "[gap: not a section 11.4.40 full retest; (L6) stays open]",' $'         "gap": "",'   # a PARTIAL verdict rendered as if it were a pass
mp BM1B $'B-M1 runner verdict (MANIFEST-MISMATCH|REFUSED-TOPOLOGY) rendered as gap-not-run' "$RRE" $'         "gap-not-run": "[gap: nothing was run; not a section 11.4.40 retest; (L6) stays open]"}' $'         "gap-not-run": "[gap: not a section 11.4.40 full retest; (L6) stays open]"}'   # a run that ran nothing reads as a partial run
mp BM1C $'B-M1 (malformed runner table|absent runner)' "$RRE" $'    except (OSError, SyntaxError, ValueError, TypeError, IndexError):\n' $'    except (OSError, SyntaxError, ValueError, TypeError, IndexError):\n        return [("PASS-FULL", "retest"), ("PARTIAL-TOPOLOGY", "retest"), ("FAIL", "fail"), ("NOT RUN", "not-run")]\n'   # the old fixed list as a silent fallback
mp BM1D $'B-M1 not a run verdict refused: MANIFEST-OK' "$RRE" $'    return sorted(words + [("NOT RUN", "not-run")]' $'    return sorted(words + [("NOT RUN", "not-run"), ("MANIFEST-OK", "retest")]'   # a --verify-manifest result accepted as a retest verdict
# B-M4 (v73.4 dry run): placeholders refused unless --draft; a --draft render carries the marker; tag_and_release.sh refuses it
mp BM4A $'B-M4 placeholder refused without --draft' "$RRE" $'            why = None if draft else placeholder_reason(name, val)' $'            why = None'   # the placeholder check never runs
mp BM4B $'B-M4 placeholder refused without --draft: block' "$RRE" $'        if not (AUTOLINK.fullmatch(t) or HTML_TAG.fullmatch(t)):' $'        if not (AUTOLINK.fullmatch(t) or HTML_TAG.fullmatch(t) or " " in t):'   # an angle placeholder with a space passes
mp BM4C $'B-M4 placeholder refused without --draft: cut_date=(2026-11-31|16.11.2026)' "$RRE" $'    if name == "cut_date":' $'    if False:'   # cut_date not checked as a date
mp BM4D $'B-M4 (the same value renders with --draft|--draft render|--draft without a heading)' "$RRE" $'        lines.insert(at, DRAFT_MARK)' $'        pass'   # a draft render without its marker
mp BM4E $'B-M4 --draft still refuses' "$RRE" $'    if missing:' $'    if missing and not draft:'   # --draft relaxes every refusal, not only the placeholder one
mp BM4F $'C54 draft notes: (exit 1|RESULT FAIL|no local tag|r1)' "$TAR" $'  [ "$DRY" -eq 1 ] || abort "the release notes of $TAG' $'  [ "$DRY" -eq 1 ] || printf \'%s\\n\' "the release notes of $TAG'   # a real run cuts a release from draft notes
mp BM4G $'C54 draft notes, dry run' "$TAR" $'  if [ "$DRAFT_NOTES" -eq 1 ]; then\n    printf \'PLAN refuse' $'  if false; then\n    printf \'PLAN refuse' $'  if [ "$DRAFT_NOTES" -eq 1 ]; then\n    printf \'RESULT: OK dry-run' $'  if false; then\n    printf \'RESULT: OK dry-run'   # the dry run does not say a real run refuses
mp BM4H $'C54 control' "$TAR" $'if grep -qF \'DRAFT RENDER — not a release entry\' "$NOTES"; then' $'if rc_net git show "$SHA:CHANGELOG.md" | grep -qF \'DRAFT RENDER — not a release entry\'; then'   # the marker of an older section refuses the release
# B-M2 (2026-11-16): the gitea token variable is required and bound to the host (config/forge/hosts.tsv)
mp BM2A $'B-M2 (codeberg with M3W_GITEA_TOKEN|unknown host|loopback URL with M3W_GITEA_TOKEN)' "$PUB" $'rc_gitea_binding "$BASE_URL" "$TOKEN_VAR"; _rpg_b=$?' $'_rpg_b=0'   # the publisher skips the binding check
mp BM2B $'B-M2 no --token-var' "$PUB" $'TOKEN_VAR="" GENERIC=0' $'TOKEN_VAR="M3W_GITEA_TOKEN" GENERIC=0'   # the old default variable is back
mp BM2C $'C56 a loopback URL with M3W_GITEA_TOKEN' "$LIB" $'    [ "$tv" = GITEA_LOOPBACK_TEST_TOKEN ] && return 0; return 1 ;;' $'    return 0 ;;'   # a loopback URL takes any token variable
mp BM2D $'C56 no host table beside the script' "$LIB" $'  { [ -f "$f" ] && [ -r "$f" ]; } || return 3' $'  { [ -f "$f" ] && [ -r "$f" ]; } || return 0'   # a missing table means any host
mp BM2E $'C56 a name that is only part of a listed name' "$LIB" $'    case ",$t," in *",$tv,"*) return 0 ;; esac' $'    case "$t" in *"$tv"*) return 0 ;; esac'   # substring match on the token_vars list
mp BM2F $'C56 a host that is only a prefix of a listed one' "$LIB" $'    [ "$a" = "$base/api/v1" ] || continue' $'    case "$a" in "$base"*) ;; *) continue ;; esac'   # prefix match on api_base
mp BM2G $'C56 (control: the codeberg call|the token variables each call)' "$TAR" $'bash scripts/release_publish_gitea.sh --token-var "$tv" "$@"' $'bash scripts/release_publish_gitea.sh --token-var M3W_GITEA_TOKEN "$@"'   # the publisher is told the default variable
mp BM2H $'C56 codeberg with M3W_GITEA_TOKEN' "$TAR" $'    rc_gitea_binding "$gbase" "$gtv"; gb=$?' $'    gb=0'   # the tag script skips the binding check
mp BM2I $'C56 the token variables each call' "$TAR" $'export "${tv?}"; bash scripts/release_publish_gitea.sh' $'export "${tv?}" M3W_GITEA_TOKEN CODEBERG_TOKEN 2>/dev/null; bash scripts/release_publish_gitea.sh'   # every token variable reaches every publisher call
mp BM2J $'C56 the token variables each call|C17' "$TAR" $'*) _tar_reads="$_tar_reads $_tar_v" ;; esac' $'*) : ;; esac'   # the spec variables are not carried over the re-execution
mp BM2K $'C56 the old four-field spec' "$TAR" $'$SEG/$SEG:[A-Z][A-Z0-9_]{0,63}\\$"' $'$SEG/$SEG(:[A-Z][A-Z0-9_]{0,63})?\\$"'   # the old four-field spec is accepted by the pattern
# CON-423 (2026-11-16, rehearsal of the v73.4 cut): D3/D4 dry-run probes and plan lines, D10 one remote per
# repository (tag_and_release.sh), D5 --draft and D9 cut_date (render_release_entry.py), D9 the template dot
mp DP1 $'RH2 |RH3 |RH6 ' "$TAR" $'  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do\n    kind="${spec%%:*}"' $'  for spec in; do\n    kind="${spec%%:*}"'   # the dry-run probes removed
mp DP2 $'RH1 |GL13 ' "$TAR" $'      *:1) printf \'PLAN release %s prerelease=flag\\n\' "$spec" ;;' $'      *:1) printf \'PLAN release %s\\n\' "$spec" ;;'   # the pre-release flag not shown in the plan
mp DP3 $'RH10 ' "$TAR" $'else wgap "$spec" "ACCESS-UNCONFIRMED (token variable set, value not shown;' $'else wgap "$spec" "ACCESS-UNCONFIRMED ($M3W_GITEA_TOKEN) (token variable set, value not shown;'   # the gitea token printed
mp DP4 $'RH3 ' "$TAR" $'        if [ "$GH_AUTH_RC" -ne 0 ]; then wgap' $'        if false; then wgap'   # gh not logged in not reported
mp DP5 $'RH6 ' "$TAR" $'[ "$pt" != object ]' $'[ "$pt" = NOT-A-TYPE ]'   # a GitLab answer that is not a JSON object accepted
mp DP6 $'RH6 ' "$TAR" $'would-fail=%d would-gap=%d)\\n\' "$WF" "$WG"; exit 1; fi' $'would-fail=%d would-gap=%d)\\n\' "$WF" "$WG"; exit 0; fi'   # a would-fail dry run exits 0
mp DP7 $'RH5 ' "$TAR" $'        if [ -n "${DGH_SEEN[$id]:-}" ]; then printf' $'        if false; then printf'   # GitHub legs of one repository id not de-duplicated in the dry run
mp RN1 $'RH12 ' "$TAR" $'case "$_seen" in *" $r "*) die_usage' $'case "$_seen" in *" NOT-A-REMOTE "*) die_usage'   # a repeated remote name accepted
mp RN2 $'RH11 ' "$TAR" $'    if [ -n "${PUSHID[$k]:-}" ] && [ "${PUSHID[$k]}" != "$r" ]; then' $'    if false; then'   # two remotes of one repository (by URL) accepted
mp RN3 $'RH11 ' "$TAR" $'p="${p#/}"; p="${p,,}"; p="${p%.git}"; printf \'host:%s/%s\' "${h,,}" "$p"' $'p="${p#/}"; p="${p%.git}"; printf \'host:%s/%s\' "$h" "$p"'   # host and path not case-folded
mp RN4 $'RH13 ' "$TAR" $'        if [ -n "${GHID_OF[$gid]:-}" ] && [ "${GHID_OF[$gid]}" != "$r" ]; then' $'        if false; then'   # two remotes of one GitHub repository id accepted
mp RN5 $'RH11 the push URL' "$TAR" $'abort "remotes ${PUSHID[$k]} and $r push to the same repository (' $'abort "remotes ${PUSHID[$k]} and $r push to the same repository $u ('   # the push URL printed
mp DP8 $'RH2 the gitlab project is read on the pinned host' "$TAR" $'pj="$(nt glab api --hostname "$GL_HOST" "projects/$enc" 2>/dev/null)"' $'pj="$(nt glab api "projects/$enc" 2>/dev/null)"'   # the dry-run project read not pinned to the host
mp DR1 $'D5 a DRAFT' "$RRE" $'    if DRAFT_WORD.search(fold(val)):' $'    if False:'   # a DRAFT manual value accepted
mp DR3 $'M4 golden FALSE, accepted: (DRAFTS|REDRAFT)' "$RRE" $'DRAFT_WORD = re.compile(r"(?<![A-Za-z])DRAFT(?![A-Za-z])")' $'DRAFT_WORD = re.compile(r"DRAFT")'   # DRAFT matched inside a word
# CON-423 review r1 (r2 fixer): M3 repo_key and M4 marker-word boundaries, each killed by its own RH16 / M4 check
mp RK1 $'RH16 doubled slash in the path' "$TAR" $'  while [[ $p == *//* ]]; do p="${p%%//*}/${p#*//}"; done' $'  :'   # doubled slashes not folded
mp RK2 $'RH16 upper-case .GIT suffix' "$TAR" $'p="${p#/}"; p="${p,,}"; p="${p%.git}"; printf' $'p="${p#/}"; p="${p%.git}"; p="${p,,}"; printf'   # .git stripped before the case fold (.GIT kept)
mp RK3 $'RH16 local /srv/repo.git and /srv/repo are two directories' "$TAR" $'  else printf \'local:%s\' "$p"; fi' $'  else printf \'local:%s\' "${p%.git}"; fi'   # a local .git suffix folded away
mp RK4 $'RH16 local paths keep their case' "$TAR" $'  else printf \'local:%s\' "$p"; fi' $'  else printf \'local:%s\' "${p,,}"; fi'   # a local path case-folded
mp RK5 $'RH16 local doubled and trailing slashes' "$TAR" $'  while [[ $p == */ ]]; do p="${p%/}"; done' $'  :'   # trailing slashes kept
mp DR4 $'M4 a DRAFT marker is refused: (DRAFT_1|see DRAFT2|v-DRAFT-3)' "$RRE" $'DRAFT_WORD = re.compile(r"(?<![A-Za-z])DRAFT(?![A-Za-z])")' $'DRAFT_WORD = re.compile(r"\\bDRAFT\\b")'   # the old \b boundary: DRAFT_1 and DRAFT2 accepted
mp DR5 $'M4 TODO/TBD glued: (TODO_1|TBD2)' "$RRE" $'PLACEHOLDER_WORD = re.compile(r"(?<![A-Za-z])(TODO|TBD)(?![A-Za-z])")' $'PLACEHOLDER_WORD = re.compile(r"\\b(TODO|TBD)\\b")'   # the old \b boundary for TODO/TBD
mp DR6 $'M4 golden FALSE, accepted: (TODOS|XTBD)' "$RRE" $'PLACEHOLDER_WORD = re.compile(r"(?<![A-Za-z])(TODO|TBD)(?![A-Za-z])")' $'PLACEHOLDER_WORD = re.compile(r"(TODO|TBD)")'   # TODO/TBD matched inside a word
mp DR7 $'M4 a DRAFT marker is refused: (ＤＲＡＦＴ|DR)' "$RRE" $'    val = "".join(ch for ch in unicodedata.normalize("NFKC", val) if unicodedata.category(ch) != "Cf")' $'    val = val'   # no NFKC fold, no format-character removal
# CON-423 review r1 (r2 fixer): M8, the one gitea token shape (redact_cut.sh) and its two callers
mp TS1 $'K12 7 characters' "$LIB" $'rc_gitea_token_shape_ok() { local LC_ALL=C; [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{8,200}$ ]]; }' $'rc_gitea_token_shape_ok() { local LC_ALL=C; [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{1,200}$ ]]; }'   # the length floor dropped
mp TS2 $'K12 201 characters' "$LIB" $'rc_gitea_token_shape_ok() { local LC_ALL=C; [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{8,200}$ ]]; }' $'rc_gitea_token_shape_ok() { local LC_ALL=C; [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{8,200} ]]; }'   # the end anchor dropped: a longer token fits
mp TS3 $'M8 a token outside the shared shape is refused' "$PUB" $'if [ -n "$_rpg_tok" ] && ! rc_gitea_token_shape_ok "$_rpg_tok"; then' $'if false; then'   # the publisher no longer checks the shape
mp TS4 $'RH17 a token outside the shape' "$TAR" $'        elif ! rc_gitea_token_shape_ok "${!gtv}"; then wfail' $'        elif false; then wfail'   # the dry run no longer reports TOKEN-SHAPE
mp TPL1 $'D9 no ' "$TPL" $'\n{{unmerged_refs_block}}\n' $'\n{{unmerged_refs_block}}.\n'   # the stray dot after the refs list back
# landing merge with B-M4 (2026-11-17): D9 cut_date is now B-M4's placeholder_reason check (not under --draft);
# CD1-CD3 retargeted to its lines; DR2 dropped (the marker insertion is BM4D); RV1-RV4 and GP21 are main's B-M1 versions
mp CD1 $'D9 cut_date not a bare date refused' "$RRE" $'    if name == "cut_date":' $'    if name == "NOT-A-NAME":'   # cut_date not checked
mp CD2 $'D9 cut_date not a bare date refused: (20261116|2026-W46-1)' "$RRE" $'            if not re.fullmatch(r"\\d{4}-\\d{2}-\\d{2}", v):\n                raise ValueError' $'            if False:\n                raise ValueError'   # the YYYY-MM-DD shape not required
mp CD3 $'D9 cut_date not a bare date refused: (2026-13-01|2026-02-30|2027-02-29)' "$RRE" $'            datetime.date.fromisoformat(v)' $'            pass'   # a date that does not exist accepted
# round 8 (N5): --only NAME that names no mutant ran nothing; that is a usage error (exit 2), never a vacuous pass
if [ -n "$ONLY" ] && [ "$ONLY" != control ] && [ "$matched" -eq 0 ]; then
  echo "FAIL --only $ONLY: no mutant has that name, nothing was run"
  echo "RESULT: killed=$killed survived=$survived equivalent=$equivalent stale=$stale control_failures=$ctrl_bad inconclusive=$inconclusive equivalent_killed=$eqkilled"
  exit 2
fi
echo "RESULT: killed=$killed survived=$survived equivalent=$equivalent stale=$stale control_failures=$ctrl_bad inconclusive=$inconclusive equivalent_killed=$eqkilled"
final_exit
