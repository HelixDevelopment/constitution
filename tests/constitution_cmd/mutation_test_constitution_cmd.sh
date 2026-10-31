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
HLP=scripts/constitution_cmd/args_file_read.py
export CMD_TEST_SKIP_GEN=1

run_suite() { CMD_SRC_ROOT="$1" bash "$HERE/test_constitution_cmd.sh" >"$MS/out.log" 2>&1; }

mkdir -p "$MS/base/scripts/constitution_cmd"; cp "$REAL/$ENG" "$MS/base/$ENG"; cp "$REAL/$HLP" "$MS/base/$HLP"
if run_suite "$MS/base"; then echo "baseline: PASS"; else echo "baseline FAILED (suite must pass unmutated)"; tail -5 "$MS/out.log"; exit 1; fi

killed=0; survived=0; n=0
mutant() {   # name, old, new
    local name="$1" old="$2" new="$3" old2="${4:-}" new2="${5:-}" d="$MS/m$n"; n=$((n+1))
    if [ -n "${ONLY:-}" ]; then case ",$ONLY," in *",$name,"*) ;; *) return ;; esac; fi
    mkdir -p "$d/scripts/constitution_cmd"
    local mf="${MUT_FILE:-$ENG}"
    cp "$REAL/$ENG" "$d/$ENG"; cp "$REAL/$HLP" "$d/$HLP"
    OLD="$old" NEW="$new" OLD2="$old2" NEW2="$new2" SRCF="$REAL/$mf" DST="$d/$mf" python3 - <<'PY' || { echo "MUTANT-SETUP-ERROR $name (pattern not found)"; survived=$((survived+1)); return; }
import os,sys
s=open(os.environ['SRCF']).read()
o=os.environ['OLD']
if o not in s: sys.exit(1)
s=s.replace(o,os.environ['NEW'],1)
o2=os.environ.get('OLD2','')
if o2:
    if o2 not in s: sys.exit(1)
    s=s.replace(o2,os.environ['NEW2'],1)
open(os.environ['DST'],'w').write(s)
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
mutant jev-extra-args-ok        'die "jev takes no arguments"; return 2;' ':;'
mutant token-space-redact-gone  "-e 's/([Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][-_]?[Kk][Ee][Yy]) [A-Za-z0-9._~+\/=-]{12,}/\1 [REDACTED]/g' \\" "-e 's/zzqtok/x/' \\"
mutant akia-redact-gone         "-e 's/AKIA[0-9A-Z]{16}/[REDACTED]/g' \\" "-e 's/zzqakia/x/' \\"
mutant ext-allow-bypass         '*) die "rejected extension option:' '*) : ;; esac ;; esac; case x in x) die "rejected extension option:'

# --args-file mutants (the verification lives in the python helper; the engine wiring in the shell)
mutant args-file-mode-off       '[ "${1:-}" = "--args-file" ] && [ $# -eq 2 ]' 'false'
mutant args-file-extra-ok       '[ "${1:-}" = "--args-file" ] && [ $# -eq 2 ]' '[ "${1:-}" = "--args-file" ]'
mutant args-file-len-unbounded  '[ "${#_line}" -le 8000 ] || { die "arguments longer than 8000 characters"; exit 2; }
    set -- "$_line"
fi
for' ':
    set -- "$_line"
fi
for'
mutant args-file-rc-ignored     '[ "$_rc" -eq 0 ] || { exit 2; }' ':'
MUT_FILE=$HLP
mutant h-id-pattern-open        'ID_RE = re.compile(r"constitution_args_[a-z0-9]{8,64}\.txt\Z")' 'ID_RE = re.compile(r".*")'
mutant h-id-upper-ok            'constitution_args_[a-z0-9]{8,64}\.txt' 'constitution_args_[A-Za-z0-9]{8,64}\.txt'
mutant h-id-len-unbounded       'constitution_args_[a-z0-9]{8,64}\.txt' 'constitution_args_[a-z0-9]{8,}\.txt'
mutant h-id-len-min-1           'constitution_args_[a-z0-9]{8,64}\.txt' 'constitution_args_[a-z0-9]{1,64}\.txt'
mutant h-dir-not-exact          'if parent not in dirs:' 'if False:'
# O_NOFOLLOW and the lstat-vs-fstat inode identity check overlap on purpose (a symlink leaf is caught by
# either); a single removal is masked by the other layer, so the mutant removes BOTH.
mutant h-symlink-defences-both-removed 'os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC' 'os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC' 'if (ls.st_dev, ls.st_ino) != (st.st_dev, st.st_ino):' 'if False:'
mutant h-regular-check-removed  'if not stat.S_ISREG(st.st_mode):' 'if False:'
mutant h-nlink-check-removed    'if st.st_nlink != 1:' 'if False:'
mutant h-owner-check-removed    'if st.st_uid != euid:' 'if False:'
mutant h-size-cap-removed       'if st.st_size > MAX_BYTES:' 'if False:'
mutant h-nul-check-removed      'if b"\0" in data:' 'if False:'
mutant h-identity-dev-only      'if (ls.st_dev, ls.st_ino) != (st.st_dev, st.st_ino):' 'if ls.st_dev != st.st_dev:'
mutant h-tmpdir-realpath-check-removed 'and os.path.realpath(t) == t):' 'and True):'
# The lexical TMPDIR checks overlap on purpose with realpath(t)==t (any '..', '.', '//' or relative form
# changes realpath), so a single removal is masked by the other layer (equivalent mutant); each pair removes BOTH.
mutant h-tmpdir-dotdot-both-removed 'and not any(x in ("", ".", "..") for x in segs)' 'and True' 'and os.path.realpath(t) == t):' 'and True):'
mutant h-tmpdir-relative-both-removed 'if (t.startswith("/") and' 'if (True and' 'and os.path.realpath(t) == t):' 'and True):'
mutant h-filename-anchor-loose  'ID_RE = re.compile(r"constitution_args_[a-z0-9]{8,64}\.txt\Z")' 'ID_RE = re.compile(r"constitution_args_[a-z0-9]{8,64}\.txt")'
mutant h-seam-ungated           'os.environ.get("CONSTITUTION_CMD_TEST") == "1" and os.environ.get("CONSTITUTION_CMD_TEST_SWAP")' 'os.environ.get("CONSTITUTION_CMD_TEST_SWAP")'
mutant h-not-consumed           'os.unlink(name, dir_fd=dfd)' 'pass'
unset MUT_FILE

echo "mutants: killed=$killed survived=$survived total=$n"
[ "$survived" -eq 0 ]
