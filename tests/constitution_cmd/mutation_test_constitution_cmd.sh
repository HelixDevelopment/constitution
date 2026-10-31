#!/usr/bin/env bash
# tests/constitution_cmd/mutation_test_constitution_cmd.sh -- paired section 1.1 mutation suite for
# the /constitution engine. Each mutant is a semantic change applied (python str.replace, asserted
# to change the file) to a COPY of the engine; the test suite is re-run against the copy with
# CMD_SRC_ROOT and must FAIL (mutant killed). The unmutated engine must PASS first (baseline).
# ONLY=name1,name2 runs just those mutants (baseline still runs).
# Exit 0 only if the baseline passes and every mutant is killed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
. "$REAL/scripts/lib/safe_rm.sh"
MS="$(mktemp -d)" || exit 1
[ -n "$MS" ] && [ -d "$MS" ] || exit 1
trap 'safe_rm_rf "$MS"' EXIT
ENG=scripts/constitution_cmd/constitution_cmd.sh
export CMD_TEST_SKIP_GEN=1

run_suite() { CMD_SRC_ROOT="$1" bash "$HERE/test_constitution_cmd.sh" >"$MS/out.log" 2>&1; }

mkdir -p "$MS/base/scripts/constitution_cmd"; cp "$REAL/$ENG" "$MS/base/$ENG"
if run_suite "$MS/base"; then echo "baseline: PASS"; else echo "baseline FAILED (suite must pass unmutated)"; tail -5 "$MS/out.log"; exit 1; fi

killed=0; survived=0; n=0
mutant() {   # name, old, new
    local name="$1" old="$2" new="$3" d="$MS/m$n"; n=$((n+1))
    if [ -n "${ONLY:-}" ]; then case ",$ONLY," in *",$name,"*) ;; *) return ;; esac; fi
    mkdir -p "$d/scripts/constitution_cmd"
    OLD="$old" NEW="$new" SRCF="$REAL/$ENG" DST="$d/$ENG" python3 - <<'PY' || { echo "MUTANT-SETUP-ERROR $name (pattern not found)"; survived=$((survived+1)); return; }
import os,sys
s=open(os.environ['SRCF']).read()
o=os.environ['OLD']
if o not in s: sys.exit(1)
open(os.environ['DST'],'w').write(s.replace(o,os.environ['NEW'],1))
PY
    if run_suite "$d"; then echo "SURVIVED: $name"; survived=$((survived+1)); else echo "killed:   $name"; killed=$((killed+1)); fi
}

mutant anchor-id-regex-open     '[[ "$id" =~ ^[0-9]{1,3}(\.[0-9]+)?$ ]]' '[[ "$id" =~ ^.+$ ]]'
mutant unknown-sub-rc0          'usage >&2; exit 2 ;;
esac' 'usage >&2; exit 0 ;;
esac'
mutant update-no-default-check  '[ "$have_mode" -eq 1 ] || args=(--check "${args[@]}")' ':'
mutant update-accepts-anything  '*) die "update accepts only --check, --dry-run, --ref REF (apply by running update_constitution.sh directly)"; return 2 ;;' '*) args+=("${REST[$i]}") ;;'
mutant gate-name-allows-slash   '[[ "$n" =~ ^[a-z0-9_]{1,100}$ ]]' '[[ "$n" =~ ^[a-z0-9_/.]{1,100}$ ]]'
mutant gate-symlink-escape-ok   '*) die "gate resolves outside scripts/gates; refused"; return 2 ;; esac' '*) ;; esac'
mutant redact-disabled          "(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}" "(zzq)_[A-Za-z0-9]{20,}"
mutant extensions-absent-silent 'die "extensions engine not installed"; return 3' 'return 0'
mutant control-chars-allowed    '*[[:cntrl:]]*) die' '*NEVERMATCHZ*) die'
mutant anchor-no-stop-at-next   '(index($0,"### ")==1 || index($0,"## ")==1)' '0'
mutant gate-timeout-removed     'timeout "$t" "$@"' '"$@"'
mutant status-layout-constant   'layout="$(cl_rel_path "$proj" "$CONST_DIR" 2>/dev/null)" || layout="unknown"' 'layout="constitution"'
mutant doctor-collision-silent  'd_warn collision "user command shadows/collides: $c"; found=1' 'd_ok collision "ours: $c"'
mutant report-text-unbounded    '[ "${#text}" -le 4000 ] || { die "report text longer than 4000 characters"; return 2; }' ':'

mutant output-unbounded         'head -c 40000 "$red"' 'cat "$red"'
mutant bearer-redact-gone       "-e 's/([Bb]earer) [A-Za-z0-9._~+\/=-]{16,}/\1 [REDACTED]/g' \\" "-e 's/zzqbearer/x/' \\"
mutant gate-timeout-range-gone  '[[ "$t" =~ ^[0-9]{1,3}$ ]] && [ "$t" -ge 1 ] && [ "$t" -le 600 ] ||' '[[ "$t" =~ ^[0-9]{1,3}$ ]] ||'
mutant ext-dash-dash-any        '^(--[a-z][a-z-]{0,30}|' '^(-.*|'
mutant single-arg-glob-on       'set -f; read -r -a ARGS <<<"$1"; set +f' 'ARGS=($1)'
mutant truncation-marker-gone   "[ \"\$(wc -c <\"\$red\")\" -gt 40000 ]" 'false'
mutant rc-lost-to-pipe          'rc=$?
    redact' 'rc=0
    redact'
mutant ext-root-allowed         'add) allow=" --json --dry-run --dev --sha --sha256 " ;;' 'add) allow=" --json --dry-run --dev --sha --sha256 --root --yes " ;;
        list) allow=" --json --root --project-root --yes " ;;'
mutant anchors-bold-form-gone   'if (!inb && index($0,q)==1) inb=2' ':'
mutant stdin-mode-off           '[ "${1:-}" = "--stdin" ] && [ $# -eq 1 ]' 'false'
mutant jev-extra-args-ok        'die "jev takes no arguments"; return 2;' ':;'
mutant token-space-redact-gone  "-e 's/([Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][-_]?[Kk][Ee][Yy]) [A-Za-z0-9._~+\/=-]{12,}/\1 [REDACTED]/g' \\" "-e 's/zzqtok/x/' \\"
mutant stdin-len-unbounded      '[ "${#_line}" -le 8000 ] ||' ':'
mutant stdin-extra-args-ok      '[ "${1:-}" = "--stdin" ] && [ $# -eq 1 ]' '[ "${1:-}" = "--stdin" ]'
mutant akia-redact-gone         "-e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \\" "-e 's/zzqakia/x/' \\"
mutant ext-allow-bypass         '*) die "rejected extension option:' '*) : ;; esac ;; esac; case x in x) die "rejected extension option:'
mutant args-file-mode-off       '[ "${1:-}" = "--args-file" ] && [ $# -eq 2 ]' 'false'
mutant args-file-symlink-ok     '[ -f "$_f" ] && [ ! -L "$_f" ] && [ -O "$_f" ]' '[ -f "$_f" ]'
mutant args-file-path-open      'case "$_f" in "$_td"/constitution_args_*.txt|/tmp/constitution_args_*.txt) ;;' 'case "$_f" in *) ;;'
mutant args-file-id-open        '[[ "$_b" =~ ^[A-Za-z0-9_-]{1,64}$ ]] ||' '[[ "$_b" =~ ^.*$ ]] ||'
mutant args-file-len-unbounded  '[ "${#_line}" -le 8000 ] || { die "arguments longer than 8000 characters"; exit 2; }
    set -- "$_line"
fi
for _a' ':
    set -- "$_line"
fi
for _a'
mutant args-file-not-consumed   'rm -f -- "${_f:?}"' ':'
mutant args-file-extra-ok       '[ "${1:-}" = "--args-file" ] && [ $# -eq 2 ]' '[ "${1:-}" = "--args-file" ]'

echo "mutants: killed=$killed survived=$survived total=$n"
[ "$survived" -eq 0 ]
