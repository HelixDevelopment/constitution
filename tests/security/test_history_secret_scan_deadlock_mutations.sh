#!/usr/bin/env bash
# test_history_secret_scan_deadlock_mutations.sh -- paired §1.1 mutations for
# the exact-match fix of scripts/security/history_secret_scan.sh
# (CON-423). Each mutant puts one defect back into a COPY of the
# script; tests/security/test_history_secret_scan_deadlock.sh must then FAIL.
# DM1 re-introduces the deadlock itself (all ids written to a pipe before any
# answer is read). Each mutation must match the script EXACTLY ONCE (else the
# mutant is BROKEN and the run fails), and the unmutated copy must pass first
# (control). Recorded as equivalent, not in the table: removing
# `len(hdr) != 3 or` (a short reply then raises IndexError, python exits 1,
# the script still exits 7), and removing the trailing-output check
# `p.stdout.read(1) != b"" or` (git never writes after the last requested
# reply; no shim here produces extra output).
#
# Usage: bash tests/security/test_history_secret_scan_deadlock_mutations.sh [ID ...]
#        HSS_DL_TIMEOUT=S per-run bound for the mutants (default 40)
# Exit: 0 every selected mutant killed and the control passes; 1 otherwise;
#       2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "env: python3 missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/scripts/security"; ln -s "$here/scripts/lib" "$tmp/scripts/lib"
SRC="$here/scripts/security/history_secret_scan.sh"
TEST="$here/tests/security/test_history_secret_scan_deadlock.sh"
export HSS_DL_TIMEOUT="${HSS_DL_TIMEOUT:-40}"

# id <TAB> python repr of the old text <TAB> python repr of the new text
cat > "$tmp/mutants.tsv" <<'EOF'
DM1	'with open(sys.argv[2], "rb") as req:\n    p = subprocess.Popen(["git", "-C", sys.argv[1], "cat-file", "--batch"], stdin=req, stdout=subprocess.PIPE)'	'p = subprocess.Popen(["git", "-C", sys.argv[1], "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)\np.stdin.write(open(sys.argv[2], "rb").read()); p.stdin.close()'
DM2	'len(hdr) != 3 or hdr[0] != b or hdr[1]'	'len(hdr) != 3 or hdr[1]'
DM3	'    p.kill(); p.wait(); sys.exit(7)'	'    pass'
DM4	'            cnt[n] += 1'	'            cnt[n] = 1'
DM5	'for b in blobs:\n    hdr ='	'for b in blobs[:-1]:\n    hdr ='
DM6	'    elif len(v) < 12:'	'    elif len(v) < 13:'
DM7	'    elif len(v) < 12:'	'    elif len(v) < 11:'
DM8	'(len(short), ",".join(short))'	'(len(short), "")'
DM9	'[ "$EXACT_ONLY" = 0 ] || [ -n "$KEYS" ] || fail 2'	'true || fail 2'
DM10	'if [ "$EXACT_ONLY" = 1 ]; then\n  echo "scanner not run'	'if false; then\n  echo "scanner not run'
DM11	'[ "$EXACT_ONLY" = 1 ] || { [ -n "$GL" ]'	'false || { [ -n "$GL" ]'
DM12	'    --exact-only) EXACT_ONLY=1 ;;'	'    --exact-only) ;;'
DM13	'"$M" "$WORK/blob_ids" > "$WORK/keys.tsv"'	'"$M" > "$WORK/keys.tsv"'
DM14	'[ "$EXACT_ONLY" = 1 ] || { [ -n "$GL" ] && [ -x "$GL" ]; } || fail 4'	'true || fail 4'
EOF

mutate(){ # ID OLD NEW -> writes $tmp/scripts/security/history_secret_scan.sh, 0 or BROKEN
  python3 -I - "$SRC" "$tmp/scripts/security/history_secret_scan.sh" "$2" "$3" <<'PY'
import ast, sys
src, dst, old, new = sys.argv[1], sys.argv[2], ast.literal_eval(sys.argv[3]), ast.literal_eval(sys.argv[4])
s = open(src).read()
if s.count(old) != 1:
    print("BROKEN: matches %d times" % s.count(old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
}

cp "$SRC" "$tmp/scripts/security/history_secret_scan.sh"
if ! HSS_SCRIPT="$tmp/scripts/security/history_secret_scan.sh" bash "$TEST" > "$tmp/ctl.out" 2>&1; then
  echo "CONTROL FAILED: the unmutated copy does not pass"; tail -20 "$tmp/ctl.out"; exit 1
fi
echo "control: unmutated copy passes ($(tail -1 "$tmp/ctl.out"))"
killed=0; surv=0; broken=0
while IFS=$'\t' read -r id old new; do
  [ -n "$id" ] || continue
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue ;; esac; fi
  if ! mutate "$id" "$old" "$new"; then echo "BROKEN   $id"; broken=$((broken+1)); continue; fi
  if HSS_SCRIPT="$tmp/scripts/security/history_secret_scan.sh" SEC_TEST_FAILFAST=1 bash "$TEST" > "$tmp/m.out" 2>&1; then
    echo "SURVIVED $id"; surv=$((surv+1))
  else
    echo "killed   $id ($(grep -m1 '^FAIL' "$tmp/m.out"))"; killed=$((killed+1))
  fi
done < "$tmp/mutants.tsv"
echo "RESULT: killed=$killed survived=$surv broken=$broken"
[ "$surv" -eq 0 ] && [ "$broken" -eq 0 ] && [ "$killed" -gt 0 ]
