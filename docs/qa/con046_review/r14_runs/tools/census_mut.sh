#!/usr/bin/env bash
# census_mut.sh <repo> <outdir>: R13-6 RED/GREEN. Runs the git-env census unmodified and with each regex mutant
# (sed on a copy placed next to the original, because the census finds the repository from its own path; the copy
# is untracked and removed after each run), from the repo root; prints rc and the last two lines per run. Read-only on the repo.
set -u; repo="${1:?}"; out="${2:?}"; cd "$repo" || exit 2
src="${CENSUS_SRC:-scripts/validation/git_env_class_census.py}"; w=scripts/validation # CENSUS_SRC: another version (RED run)
run() { python3 -I "$1" >"$out/$2.txt" 2>&1; echo "$2 rc=$? $(tail -2 "$out/$2.txt" | tr '\n' '|')"; }
run "$src" real
for m in 'merge(?!.*base)' 'merge(?!-base)' 'merge(?!-)' 'merge'; do
  n="mut_$(printf '%s' "$m" | tr -c 'a-z0-9' _)"; sed "s/merge(?!-base\\\\b)/$m/" "$src" >"$w/.$n.py"
  grep -qF "$m|reset" "$w/.$n.py" || { echo "$n NOT APPLIED"; rm -f "$w/.$n.py"; continue; }; run "$w/.$n.py" "$n"; rm -f "$w/.$n.py"; done
# round 14 (R13-4 follow-on): mutants of the symbolic-ref read narrowing; each must make the census BLIND or FAIL
symrun() { n="$1"; python3 -I - "$src" "$w/.$n.py" "$2" "$3" <<'PY'
import sys; s=open(sys.argv[1],encoding='utf-8').read(); o,n=sys.argv[3],sys.argv[4]
if s.count(o)!=1: sys.exit(3)
open(sys.argv[2],'w',encoding='utf-8').write(s.replace(o,n))
PY
  [ $? = 0 ] || { echo "$n NOT APPLIED"; rm -f "$w/.$n.py"; return; }; run "$w/.$n.py" "$n"; rm -f "$w/.$n.py"; }
symrun symref_no_narrowing 'symbolic-ref" + SYMREF_READ + r"|' 'symbolic-ref|'
symrun symref_no_terminator '[^\s;&|)"'"'"'`<>]*\s*(?:[;&|)"'"'"'`]|[0-9]?>|$))"""' '[^\s;&|)"'"'"'`<>]*)"""'
symrun symref_delete_is_read '(?:-q|--quiet|--short|--no-recurse)' '(?:-q|--quiet|--short|--no-recurse|-d|--delete)'
symrun symref_every_form_read 'symbolic-ref" + SYMREF_READ + r"|' 'NO-SUCH-SUBCOMMAND|'
