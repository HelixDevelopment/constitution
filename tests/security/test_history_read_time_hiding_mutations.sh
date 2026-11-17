#!/usr/bin/env bash
# test_history_read_time_hiding_mutations.sh -- paired mutants (§1.1) for the read-time-hiding
# fixes of scripts/gitleaks/gitleaks_run_scan.sh and scripts/security/history_secret_scan.sh
# (CON-453, CON-438 class).
#
# Purpose: each mutant removes or weakens one part of the fix in a COPY of the scripts tree; the
# suite tests/security/test_history_read_time_hiding.sh is run against that copy and MUST fail.
# A mutant the suite does not catch is a SURVIVOR and fails this test. The scripts are copied
# with their libraries (scripts/gitleaks, scripts/lib, scripts/security) so the copies run as-is.
# Scanner: the fakes by default (gate-logic, §11.4.289); with GLRS_GITLEAKS set the real binary
# is used, and the mutants that need a deliberately broken scanner (marked fake-only) are skipped.
#
# Usage: bash tests/security/test_history_read_time_hiding_mutations.sh [MUTANT-ID ...]
#        GLRS_GITLEAKS=/path/to/real/gitleaks bash ...
# Exit: 0 every mutant killed; 1 a survivor or a broken mutant; 2 environment error.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SUITE="$here/tests/security/test_history_read_time_hiding.sh"
command -v python3 >/dev/null 2>&1 || { echo "env: python3 missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
S=scripts/gitleaks/gitleaks_run_scan.sh; H=scripts/security/history_secret_scan.sh
# ID@@fake-only(0/1)@@file@@old@@new   (old must occur exactly once; new may be empty; <NL> = newline)
MUTANTS=$(cat <<'EOF'
AM1@@0@@S@@GLRS_TEXT_OPTS="-m --text --no-textconv"@@GLRS_TEXT_OPTS="-m --no-textconv"
AM2@@0@@S@@GLRS_TEXT_OPTS="-m --text --no-textconv"@@GLRS_TEXT_OPTS="-m --text"
AM3@@0@@S@@GLRS_TEXT_OPTS="-m --text --no-textconv"@@GLRS_TEXT_OPTS="--text --no-textconv"
AM4@@0@@S@@SCAN_ARGS+=(--log-opts "${EXTRA_ARGS[${_glrs_i}]} ${GLRS_TEXT_OPTS}")@@SCAN_ARGS+=(--log-opts "${EXTRA_ARGS[${_glrs_i}]}")
AM5@@0@@S@@--log-opts=*) SCAN_ARGS+=("${_glrs_a} ${GLRS_TEXT_OPTS}")@@--log-opts=*) SCAN_ARGS+=("${_glrs_a}")
AM6@@0@@S@@[ "${_glrs_lo}" = 1 ] || SCAN_ARGS+=(--log-opts "${GLRS_DEFAULT_LOG_OPTS} ${GLRS_TEXT_OPTS}")@@:
AM7@@1@@S@@glrs_attr_selfcheck; _glrs_sc=$?@@_glrs_sc=0
AM8@@1@@S@@[ "${nn}" -lt 1 ] || @@
AM9@@1@@S@@[ "${nt}" -lt 1 ] || @@
AM10@@1@@S@@[ "${nm}" -lt 1 ] || @@
AM11@@0@@S@@export GIT_GRAFT_FILE=/dev/null/no-grafts GIT_SHALLOW_FILE=/dev/null@@export GIT_SHALLOW_FILE=/dev/null
AM12@@0@@S@@export GIT_GRAFT_FILE=/dev/null/no-grafts GIT_SHALLOW_FILE=/dev/null@@export GIT_GRAFT_FILE=/dev/null/no-grafts
AM13@@0@@S@@export GIT_GRAFT_FILE=/dev/null/no-grafts GIT_SHALLOW_FILE=/dev/null@@export GIT_GRAFT_FILE=/dev/null GIT_SHALLOW_FILE=/dev/null
AM14@@0@@S@@if [ "${_glrs_nogit}" = 0 ]; then@@if false; then
AM15@@1@@S@@    echo "INCONCLUSIVE: gitleaks scan not trusted (attribute control needles failed)"<NL>    exit 3@@    echo "INCONCLUSIVE: gitleaks scan not trusted (attribute control needles failed)"<NL>    exit 0
AM16@@0@@S@@    safe_rm_rf "${sc:?}" || gl_err "cleanup refused for ${sc}"@@    :
AM17@@0@@S@@                gl_err "--log-opts needs a value"; exit 2@@                SCAN_ARGS+=(--log-opts)
AM18@@0@@H@@--log-opts="--all -m --text --no-textconv"@@--log-opts="--all -m --no-textconv"
AM19@@0@@H@@--log-opts="--all -m --text --no-textconv"@@--log-opts="--all -m --text"
AM20@@0@@H@@[ ! -e "$M/shallow" ] || fail 3@@[ -e /nonexistent ] || true
AM21@@1@@H@@[ "$natr" -ge 1 ] || fail 3@@true || fail 3
AM22@@1@@H@@[ "$ntcv" -ge 1 ] || fail 3@@true || fail 3
AM23@@1@@H@@printf '%s\n' '__hss_needle__/attr.env -diff' '__hss_needle__/tconv.env diff=hssneedle' >> "$M/info/attributes"@@printf '%s\n' '__hss_needle__/tconv.env diff=hssneedle' >> "$M/info/attributes"
AM24@@1@@H@@git -C "$M" config diff.hssneedle.textconv true@@:
EOF
)
want=" $* "
fail=0; killed=0; skipped=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  id=${row%%@@*}; row=${row#*@@}; fo=${row%%@@*}; row=${row#*@@}; f=${row%%@@*}; row=${row#*@@}
  old=${row%%@@*}; new=${row#*@@}
  if [ $# -gt 0 ] && [[ "$want" != *" $id "* ]]; then continue; fi
  if [ "$fo" = 1 ] && [ -n "${GLRS_GITLEAKS:-}" ]; then echo "SKIP $id (fake-only: needs a deliberately broken scanner)"; skipped=$((skipped+1)); continue; fi
  case "$f" in S) path=$S ;; H) path=$H ;; *) echo "BROKEN $id: bad file tag"; fail=1; continue ;; esac
  m="$tmp/$id"; mkdir -p "$m/scripts"
  cp -a "$here/scripts/gitleaks" "$here/scripts/lib" "$here/scripts/security" "$m/scripts/"
  if ! python3 -I - "$m/$path" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2].replace("<NL>", "\n"), sys.argv[3].replace("<NL>", "\n")
s = open(p).read()
if s.count(old) != 1:
    sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
  then echo "BROKEN $id: the mutated text does not occur exactly once in $path"; fail=1; continue; fi
  if cmp -s "$here/$path" "$m/$path"; then echo "BROKEN $id: no change"; fail=1; continue; fi
  if SEC_TEST_FAILFAST=1 GLRS_SCRIPT="$m/$S" HSS_SCRIPT="$m/$H" bash "$SUITE" > "$tmp/$id.log" 2>&1; then
    echo "SURVIVOR $id ($f: $(printf '%s' "$old" | cut -c1-60))"; fail=1
  else
    echo "killed $id by: $(grep -m1 '^FAIL' "$tmp/$id.log" | cut -c1-90)"; killed=$((killed+1))
  fi
done <<< "$MUTANTS"
echo "RESULT: killed=$killed skipped=$skipped failed=$fail"
[ "$fail" = 0 ]
