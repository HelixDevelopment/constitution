#!/usr/bin/env bash
# tests/gates/test_gate_env_census_closure.sh -- review round 8 findings F2/F3 for CM-GATE-ENV-READS-ALLOWLISTED.
# REAL gate, REAL census, in a mktemp copy of the real scripts/ tree (no doubles). Each injection appends ONE ambient read of a
# fresh variable to a real file; the real tree is PASS, so a FAIL can only come from the injected read being seen.
#   F2: libraries really sourced through `$VAR/path` and `$HERE/../x/y.sh` (scripts/action_prefix_lib.sh,
#       scripts/deps_manifest/override_guard.sh) are in the closure; a source statement that cannot be resolved is BLIND (rc 2).
#   F3: bare `export X` then $X, and the other read forms, are reads.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
chk() { if [ "$1" = 0 ]; then pass=$((pass+1)); echo "PASS $2"; else fail=$((fail+1)); echo "FAIL $2"; fi; }
GATE="$src/scripts/gates/cm_gate_env_reads_allowlisted.sh"; AL="$src/config/gate_env_allowlist.tsv"
mkdir -p "$sb/base/config"; cp -R "$src/scripts" "$sb/base/scripts"; cp "$AL" "$sb/base/config/"
run() { # root -> rc, output in $OUT
  OUT="$(cd / && nice -n 15 bash "$GATE" --root "$1" --allowlist "$AL" 2>&1)"; return $?; }
# one writable copy; each case appends to ONE file and restores it afterwards (a 52 MB tree copy per case would be slow)
cp -R "$sb/base" "$sb/w"; BK=""; BKF=""
fresh() { [ -z "$BKF" ] || cp -- "$BK" "$sb/w/$BKF"; BKF=""; }
append() { fresh; BKF="$1"; BK="$sb/bk.$$"; cp -- "$sb/w/$1" "$BK"; shift_f="$1"; }
run "$sb/base"; rc=$?; [ "$rc" = 0 ]; chk $? "control: the copied real tree PASSes (rc=$rc)"
inject() { # name file-in-tree line... -> expects FAIL (rc 1) naming EVIL var
  local name="$1" f="$2"; shift 2; append "$f"; printf '%s\n' "$@" >>"$sb/w/$f"
  run "$sb/w"; local rc=$?
  [ "$rc" = 1 ] && grep -q 'UNCOVERED.*EVIL_' <<<"$OUT"; chk $? "$name: injected ambient read is seen (rc=$rc)"
}
inject "F2 action_prefix_lib.sh (sourced via \$LIB)" scripts/action_prefix_lib.sh ': "${EVIL_F2A:-}"'
inject "F2 override_guard.sh (sourced via \$HERE/../deps_manifest/)" scripts/deps_manifest/override_guard.sh ': "${EVIL_F2B:-}"'
inject "F2 helix_deps_tsv.sh (sourced via \$_CM_TP_LIBDIR/../deps_manifest/)" scripts/deps_manifest/helix_deps_tsv.sh ': "${EVIL_F2C:-}"'
inject "F3 bare export (the review's B1 shape) in cm_killpg_pgid_guard.sh" scripts/gates/cm_killpg_pgid_guard.sh 'export EVIL_B1; [ -n "$EVIL_B1" ] && exit 0'
inject "F3 bare declare -x" scripts/gates/cm_killpg_pgid_guard.sh 'declare -x EVIL_B2; echo "$EVIL_B2"'
inject "F3 bare readonly" scripts/gates/cm_killpg_pgid_guard.sh 'readonly EVIL_B3; echo "$EVIL_B3"'
inject "F3 env-prefix then later read" scripts/gates/cm_killpg_pgid_guard.sh 'EVIL_B4=1 true; echo "$EVIL_B4"'
inject "F3 perl \$ENV{X}" scripts/gates/cm_killpg_pgid_guard.sh "perl -e 'print \$ENV{EVIL_B5}'"
inject "F3 jq env.X" scripts/gates/cm_killpg_pgid_guard.sh "jq -n 'env.EVIL_B6'"
inject "F3 node process.env.X" scripts/gates/cm_killpg_pgid_guard.sh "node -e 'console.log(process.env.EVIL_B7)'"
inject "F3 env | grep ^X=" scripts/gates/cm_killpg_pgid_guard.sh 'env | grep ^EVIL_B8='
# non-EVIL names for indirect forms: the gate must still FAIL (uncovered)
inj2() { local name="$1" f="$2"; shift 2; append "$f"; printf '%s\n' "$@" >>"$sb/w/$f"; run "$sb/w"; local rc=$?
  [ "$rc" = 1 ] && grep -q 'UNCOVERED' <<<"$OUT"; chk $? "$name: reported as an uncovered/indirect read (rc=$rc)"; }
inj2 "F3 python from os import environ as E" scripts/gates/cm_killpg_pgid_guard.sh "python3 -c 'from os import environ as E; print(E[\"X\"])'"
inj2 "F3 python os.environ.copy()" scripts/gates/cm_killpg_pgid_guard.sh "python3 -c 'import os; e=os.environ.copy()'"
inj2 "F3 python dict(os.environ)" scripts/gates/cm_killpg_pgid_guard.sh "python3 -c 'import os; d=dict(os.environ)'"
inj2 "F3 declare -p" scripts/gates/cm_killpg_pgid_guard.sh 'declare -p | grep -q EVIL'
inj2 "F3 eval of a built string" scripts/gates/cm_killpg_pgid_guard.sh 'eval "x=\$$(echo EVIL_NAME)"'
inj2 "F3 jq \$ENV" scripts/gates/cm_killpg_pgid_guard.sh "jq -n '\$ENV | keys'"
inject "N6 single-bracket [ -v X ]" scripts/gates/cm_killpg_pgid_guard.sh '[ -v EVIL_N6A ] && exit 0'
inject "N6 test -v X" scripts/gates/cm_killpg_pgid_guard.sh 'test -v EVIL_N6B && exit 0'
inj2 "N6 printenv \"\$n\"" scripts/gates/cm_killpg_pgid_guard.sh 'n=SOMETHING; printenv "$n"'
# F2 fail-BLIND: a source statement whose target cannot be resolved
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' '. "$1"' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 2 ] && grep -q 'BLIND' <<<"$OUT" && grep -qi 'unresolved' <<<"$OUT"; chk $? "F2 unresolvable source statement is BLIND naming it (rc=$rc)"
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' '. "$HERE/lib/no_such_file_anywhere.sh"' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 2 ]; chk $? "F2 source of a non-existent file is BLIND (rc=$rc)"
fresh
# N3: source shapes beyond `.`/`source` in command position. Each injects ONE statement into the real cm_killpg_pgid_guard.sh
# that loads a sandbox library reading EVIL_LIBX; the gate must be BLIND (rc 2, naming it) or FAIL (rc 1), never PASS (rc 0).
printf '%s\n' ': "${EVIL_LIBX:-}"' >"$sb/w/scripts/gates/lib/evil_n3.sh"
n3() { local name="$1" line="$2"; append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' "$line" >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"
  run "$sb/w"; local rc=$?; { [ "$rc" = 1 ] || [ "$rc" = 2 ]; } && { [ "$rc" = 2 ] || grep -q 'EVIL_LIBX' <<<"$OUT"; }; chk $? "N3 $name: not PASS (rc=$rc)"; }
n3 "builtin source resolvable" 'builtin source "$(dirname "${BASH_SOURCE[0]}")/lib/evil_n3.sh"'
n3 "command . resolvable" 'command . "$(dirname "${BASH_SOURCE[0]}")/lib/evil_n3.sh"'
n3 "source <(cat lib)" 'source <(cat "$(dirname "${BASH_SOURCE[0]}")/lib/evil_n3.sh")'
n3 'eval ". lib"' 'eval ". $(dirname "${BASH_SOURCE[0]}")/lib/evil_n3.sh"'
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' 'source <(cat lib)' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 2 ] && grep -q 'UNRESOLVED-SOURCE' <<<"$OUT"; chk $? "N3 process-substitution source is BLIND naming UNRESOLVED-SOURCE (rc=$rc)"
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' 'eval ". lib"' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 2 ] && grep -q 'UNRESOLVED-SOURCE' <<<"$OUT"; chk $? "N3 eval-of-source string is BLIND naming UNRESOLVED-SOURCE (rc=$rc)"
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' 'builtin source "$1"' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 2 ] && grep -q 'UNRESOLVED-SOURCE' <<<"$OUT"; chk $? "N3 builtin source of an unresolvable word is BLIND (rc=$rc)"
# negatives stay negative: prose / arguments that merely contain the words do not trigger
append scripts/gates/cm_killpg_pgid_guard.sh; printf '%s\n' 'echo "a command . b"; jq -e . "$0" >/dev/null; # eval ". x"' >>"$sb/w/scripts/gates/cm_killpg_pgid_guard.sh"; run "$sb/w"; rc=$?
[ "$rc" = 0 ]; chk $? "N3 negative: words in echo/jq argument/comment do not trigger (rc=$rc)"
fresh
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
