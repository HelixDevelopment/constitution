#!/usr/bin/env bash
# test_history_secret_scan_replace_mutations.sh -- paired §1.1 mutations for
# the replace-ref fix of scripts/security/history_secret_scan.sh (CON-425).
# Each mutant puts one defect back into a COPY of the script;
# tests/security/test_history_secret_scan_replace.sh must then FAIL. RM1
# removes the GIT_NO_REPLACE_OBJECTS export (the defect itself); RM10 is the
# reviewer mutant RV1 of the CON-423 review round 2 (the blob type check of
# the matcher removed). Each mutation must match the script EXACTLY ONCE
# (else the mutant is BROKEN and the run fails), and the unmutated copy must
# pass first (control). Recorded as equivalent, not in the table: setting the
# variable to another value (git disables replace refs for any value) and
# exporting it later but before the first git call.
#
# Usage: bash tests/security/test_history_secret_scan_replace_mutations.sh [ID ...]
# Exit: 0 every selected mutant killed and the control passes; 1 otherwise;
#       2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "env: python3 missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/scripts/security"; ln -s "$here/scripts/lib" "$tmp/scripts/lib"
SRC="$here/scripts/security/history_secret_scan.sh"
TEST="$here/tests/security/test_history_secret_scan_replace.sh"

# id <TAB> python repr of the old text <TAB> python repr of the new text
cat > "$tmp/mutants.tsv" <<'EOF'
RM1	'export GIT_NO_REPLACE_OBJECTS=1\n'	''
RM2	'export GIT_NO_REPLACE_OBJECTS=1\n'	'GIT_NO_REPLACE_OBJECTS=1\n'
RM3	'grc=0; "$GL" git'	'grc=0; env -u GIT_NO_REPLACE_OBJECTS "$GL" git'
RM4	'"cat-file", "--batch"], stdin=req, stdout=subprocess.PIPE)'	'"cat-file", "--batch"], stdin=req, stdout=subprocess.PIPE, env={k: v for k, v in __import__("os").environ.items() if k != "GIT_NO_REPLACE_OBJECTS"})'
RM5	' "+refs/replace/*:refs/fetched/r$i/replace/*"'	''
RM6	' refs/replace/ refs/fetched/ >'	' refs/replace/ >'
RM7	' || $1 ~ /^refs\\/fetched\\/r[0-9]+\\/replace\\//'	''
RM8	'rh=$(wc -l < "$RPL")'	'rh=0'
RM9	' || [ "$rh" -gt 0 ]; then exit 1; fi'	'; then exit 1; fi'
RM10	'hdr[0] != b or hdr[1] != b"blob" or not'	'hdr[0] != b or not'
RM11	'"$WORK/refs.tsv" > "$RPL"'	'"$WORK/refs.tsv" > "$RPL.x"; : > "$RPL"'
RM12	'echo "replace refs: $rh -> $RPL'	': "replace refs: $rh -> $RPL'
RM13	'[ "$rh" -gt 0 ]; then exit 1; fi'	'[ "$rh" -gt 1 ]; then exit 1; fi'
RM14	"%(objectname)%09%(objecttype)'"	"%(objectname)'"
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
