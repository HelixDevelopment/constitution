#!/usr/bin/env bash
# prescreen13.sh D OUT [NAME...]: run every round-13 mutant of tools/mut13.py (or the NAMEs) against its suite, three
# at a time, in the layout of the harness (setup_dir: the library beside the copy; CEN_PY / DRF_SCRIPT), and write
# OUT/NAME/{out,rc,fails} plus one result line per mutant to OUT/result.tsv: NAME rc nfail property-match first-FAIL.
# The suites run with RELEASE_TESTS_ALLOW_SKIP=1 and their own TMPDIR under OUT/NAME (nothing outside OUT is written).
set -u
D="${1:?}"; OUT="${2:?}"; shift 2
R="$D/repo"; T="$D/tools"
mkdir -p "$OUT"
one() { # one NAME
  local n="$1" d="$OUT/$1" src v t copy pat
  mkdir -p "$d/release" "$d/tmp"
  src="$(python3 "$T/mut13.py" pat | awk -F '\t' -v n="$n" '$1==n {print $2; exit}')"
  pat="$src"
  src="$(python3 - "$T" "$n" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import mut13
for m in mut13.M:
    if m[0] == sys.argv[2]:
        print(m[2])
PY
)"
  case "$src" in
    '$CENPY') copy="$d/channel_census.py"; v=CEN_PY; t="$R/tests/release/test_channel_census.sh" ;;
    '$DRF') copy="$d/derive_release_facts.sh"; v=DRF_SCRIPT; t="$R/tests/release/test_derive_release_facts.sh" ;;
    *) echo "unsupported source $src for $n" >"$d/out"; printf '%s\t%s\n' "$n" "unsupported" >>"$OUT/result.tsv"; return ;;
  esac
  cp -- "$R/scripts/release/redact_cut.sh" "$d/redact_cut.sh"; cp -- "$R/scripts/release/redact_cut.sh" "$d/release/redact_cut.sh"
  python3 "$T/mut13.py" apply "$R" "$n" "$copy" || { printf '%s\tSTALE\n' "$n" >>"$OUT/result.tsv"; return; }
  env TMPDIR="$d/tmp" RELEASE_TESTS_ALLOW_SKIP=1 "$v=$copy" bash "$t" >"$d/out" 2>&1; echo $? >"$d/rc"
  grep -a '^FAIL' "$d/out" >"$d/fails"
  local nf m; nf="$(wc -l <"$d/fails")"
  if grep -Eq -- "$pat" "$d/fails"; then m=match; else m=NOMATCH; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$(cat "$d/rc")" "$nf" "$m" "$(head -1 "$d/fails" | cut -c1-160)" >>"$OUT/result.tsv"
}
export -f one; export OUT R T
if [ "$#" -eq 0 ]; then mapfile -t all < <(python3 "$T/mut13.py" names | tr -s ' ' '\n'); set -- "${all[@]}"; fi
printf '%s\n' "$@" | xargs -P 3 -I{} bash -c 'one "$1"' _ {}
echo PRESCREEN-DONE >>"$OUT/result.tsv"
