#!/usr/bin/env bash
# test_gitleaks_run_scan_replace_mutations.sh -- paired §1.1 mutations for the
# replace-ref fix of scripts/gitleaks/gitleaks_run_scan.sh (CON-435).
# Each mutant puts one defect back into a COPY of the script;
# tests/security/test_gitleaks_run_scan_replace.sh must then FAIL. GM1 removes
# the GIT_NO_REPLACE_OBJECTS export (the defect itself); GM3 moves it before
# the git-env scrub, which then clears it. Each replacement must match the
# script EXACTLY ONCE (else the mutant is BROKEN and the run fails), and the
# unmutated copy must pass first (control).
# Value mutants (rows marked E): another value of the variable (0, empty).
# git disables replace refs when the variable is set to any value, so these
# are behaviour-equivalent: every behaviour case (R1-R7) must still pass. With
# the fake scanner the contract case R8 (the scanner sees exactly the value 1)
# must be the case that kills them; with the real scanner (R8 skipped) they
# must SURVIVE. Any other outcome means the equivalence claim is wrong and the
# run fails.
# The scanner is the fake one by default; GLRS_GITLEAKS=/path passes the real
# gitleaks binary through to the test (live mutation run).
#
# Usage: bash tests/security/test_gitleaks_run_scan_replace_mutations.sh [ID ...]
# Exit: 0 every selected mutant killed, every equivalent row survived, control
#       passes; 1 otherwise; 2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "env: python3 missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/scripts/gitleaks"; cp "$here/scripts/gitleaks/gitleaks_lib.sh" "$tmp/scripts/gitleaks/"
SRC="$here/scripts/gitleaks/gitleaks_run_scan.sh"
DST="$tmp/scripts/gitleaks/gitleaks_run_scan.sh"
TEST="$here/tests/security/test_gitleaks_run_scan_replace.sh"
SEL=" $* "; NSEL=$#

# id <TAB> kind (K = must be killed, E = equivalent, must survive) <TAB> then pairs of
# python reprs: old <TAB> new [<TAB> old2 <TAB> new2]
cat > "$tmp/mutants.tsv" <<'EOF'
GM1	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	''
GM2	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	'GIT_NO_REPLACE_OBJECTS=1\n'
GM3	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	''	'set -uo pipefail\n'	'set -uo pipefail\nexport GIT_NO_REPLACE_OBJECTS=1\n'
GM4	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	'export GIT_NO_REPLACE_OBJECT=1\n'
GM5	K	'( cd "${ROOT}" && gitleaks detect'	'( cd "${ROOT}" && env -u GIT_NO_REPLACE_OBJECTS gitleaks detect'
GM6	K	'gl_log "running gitleaks detect'	'unset GIT_NO_REPLACE_OBJECTS; gl_log "running gitleaks detect'
GM7	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	'( export GIT_NO_REPLACE_OBJECTS=1 )\n'
GM8	K	'export GIT_NO_REPLACE_OBJECTS=1\n'	''	'SCAN_RC=$?\n'	'SCAN_RC=$?\nexport GIT_NO_REPLACE_OBJECTS=1\n'
GE1	E	'export GIT_NO_REPLACE_OBJECTS=1\n'	'export GIT_NO_REPLACE_OBJECTS=0\n'
GE2	E	'export GIT_NO_REPLACE_OBJECTS=1\n'	'export GIT_NO_REPLACE_OBJECTS=\n'
EOF

mutate(){ # writes $DST from $SRC with the given (old,new) pairs; exit 3 = BROKEN
  python3 -I - "$SRC" "$DST" "$@" <<'PY'
import ast, sys
src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(src).read()
for i in range(0, len(pairs), 2):
    old, new = ast.literal_eval(pairs[i]), ast.literal_eval(pairs[i + 1])
    if s.count(old) != 1:
        print("BROKEN: %r matches %d times" % (old, s.count(old))); sys.exit(3)
    s = s.replace(old, new)
open(dst, "w").write(s)
PY
}

cp "$SRC" "$DST"
if ! GLRS_SCRIPT="$DST" bash "$TEST" > "$tmp/ctl.out" 2>&1; then
  echo "CONTROL FAILED: the unmutated copy does not pass"; tail -20 "$tmp/ctl.out"; exit 1
fi
echo "control: unmutated copy passes ($(tail -1 "$tmp/ctl.out"))"
killed=0; surv=0; broken=0; eq_ok=0; eq_bad=0
while IFS=$'\t' read -r id kind o1 n1 o2 n2; do
  [ -n "$id" ] || continue
  if [ "$NSEL" -gt 0 ]; then case "$SEL" in *" $id "*) ;; *) continue ;; esac; fi
  set -- "$o1" "$n1"; [ -n "${o2:-}" ] && set -- "$o1" "$n1" "$o2" "$n2"
  if ! mutate "$@"; then echo "BROKEN   $id"; broken=$((broken+1)); set --; continue; fi
  set --
  if GLRS_SCRIPT="$DST" SEC_TEST_FAILFAST=1 bash "$TEST" > "$tmp/m.out" 2>&1; then res=survived; else res=killed; fi
  if [ "$kind" = E ]; then
    if [ -n "${GLRS_GITLEAKS:-}" ]; then [ "$res" = survived ] && res=eq_ok || res=eq_bad
    elif [ "$res" = killed ] && grep -m1 '^FAIL' "$tmp/m.out" | grep -q ' R8 '; then res=eq_ok
    else res=eq_bad; fi
  fi
  case "$kind/$res" in
    K/killed) echo "killed   $id ($(grep -m1 '^FAIL' "$tmp/m.out"))"; killed=$((killed+1)) ;;
    K/survived) echo "SURVIVED $id"; surv=$((surv+1)) ;;
    E/eq_ok) echo "equiv    $id behaviour cases pass ($(grep -m1 '^FAIL' "$tmp/m.out" || echo 'all cases pass'))"; eq_ok=$((eq_ok+1)) ;;
    E/eq_bad) echo "EQUIV-WRONG $id: the equivalence claim does not hold ($(grep -m1 '^FAIL' "$tmp/m.out" || echo 'survived R8'))"; eq_bad=$((eq_bad+1)) ;;
  esac
done < "$tmp/mutants.tsv"
echo "RESULT: killed=$killed survived=$surv broken=$broken equivalent_ok=$eq_ok equivalent_wrong=$eq_bad"
[ "$surv" -eq 0 ] && [ "$broken" -eq 0 ] && [ "$eq_bad" -eq 0 ] && [ "$killed" -gt 0 ]
