#!/usr/bin/env bash
# mutants_round11.sh — §1.1 paired mutations for the round-11 fixes (update-pending marker: target + staged-before,
# symlink refusal on both sides, hash order). Each mutant changes ONE line of a scratch copy of the installer or
# updater and runs the matching section of tests/install/test_round11.sh against it (R11_SECTIONS); the suite MUST
# FAIL. A control run on the unmutated scratch copy MUST pass. The scratch copy is a real clone of this repository
# (tags needed) with the working-tree scripts and tests overlaid; the real files are never touched.
# Usage: bash tests/install/mutants_round11.sh   Exit 0 every mutant killed · 1 a survivor · 2 env.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; repo="$(cd "$here/../.." && pwd)"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$repo/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/r11mut.XXXXXX")" || exit 2
trap 'SAFE_RM_ALLOWED_ROOTS="$(dirname "${tmp:?}")" safe_rm_rf "${tmp:?}"' EXIT
git clone -q --no-recurse-submodules "$repo" "$tmp/pristine" || exit 2
overlay() { local d="$1"; mkdir -p "$d/tests/install" "$d/scripts/lib"
  cp "$repo"/scripts/install_constitution.sh "$repo"/scripts/update_constitution.sh "$d/scripts/"
  cp "$repo"/scripts/lib/safe_rm.sh "$d/scripts/lib/"; cp "$repo"/tests/install/*.sh "$d/tests/install/"; }
overlay "$tmp/pristine"
killed=0; surv=0; n=0
runsec() { (cd "$1" && R11_SECTIONS="$2" timeout 1500 bash tests/install/test_round11.sh >"$1/out.txt" 2>&1); }
echo "# control: unmutated scratch copy passes all sections"
[ -n "${R11_ONLY:-}" ] || runsec "$tmp/pristine" "F1 F2 F3" && echo "  ok   control" || { echo "  FAIL control"; tail -5 "$tmp/pristine/out.txt"; exit 2; }
mut() { # name section file old new
  local name="$1" sec="$2" f="$3" old="$4" new="$5"; n=$((n+1)); local d="$tmp/m$n"
  case "$name" in "${R11_ONLY:-}"*) ;; *) return 0 ;; esac   # R11_ONLY=U4 runs the mutants whose name starts with U4
  git clone -q --no-recurse-submodules --shared "$tmp/pristine" "$d" || exit 2; overlay "$d"
  OLD="$old" NEW="$new" python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); o=os.environ["OLD"]; assert s.count(o)==1,(p,s.count(o)); open(p,"w").write(s.replace(o,os.environ["NEW"]))' "$d/scripts/$f" || { echo "META: $name did not apply" >&2; exit 2; }
  if runsec "$d" "$sec"; then echo "  SURVIVED $name"; surv=$((surv+1)); else echo "  killed   $name"; killed=$((killed+1)); fi
  safe_rm_rf "${d:?}"
}
I=install_constitution.sh; U=update_constitution.sh
mut "I1 built-in: ANY marker honoured (was [ \"\$pm\" != \"\$cur\" ] -> [ -z \"\$pm\" ])" F1 $I '! hi_marker_honored "$cur" "$gl"; then' '[ -n "$(hi_marker_get)" ]; then'
mut "I2 built-in: marker target not compared" F1 $I '[ -n "$1" ] && [ "$t" = "$1" ] && [ "$b" = "${2:--}" ]' '[ -n "$1" ] && [ "$b" = "${2:--}" ]'
mut "I3 built-in: staged-before not compared (stale marker honoured)" F1 $I '[ -n "$1" ] && [ "$t" = "$1" ] && [ "$b" = "${2:--}" ]' '[ -n "$1" ] && [ "$t" = "$1" ]'
mut "I4 built-in: old-format marker accepted" F1 $I '  case "$line" in *" "*) ;; *) return 1 ;; esac
  t="${line%% *}"; b="${line#* }"' '  t="${line%% *}"; b="${line#* }"; [ "$line" = "$t" ] && b="${2:--}"'
mut "I5 built-in: symlinked marker is read" F1 $I '  [ -f "$pend" ] && [ ! -L "$pend" ] && head -n 1 -- "$pend" 2>/dev/null' '  [ -f "$pend" ] && head -n 1 -- "$pend" 2>/dev/null'
mut "I6 built-in: marker written through a symlink" F1 $I '  [ -L "$pend" ] && return 0
' ''
mut "I7 built-in: staged-before not recorded" F1 $I '  hi_marker_set "$tsha" "$gl"' '  hi_marker_set "$tsha"'
mut "U1 updater: ANY marker honoured" F2 $U '[ "${l%% *}" = "$CUR" ] && [ "${l#* }" = "${GL_CUR:--}" ]; }' 'true; }'
mut "U2 updater: marker target not compared" F2 $U '[ "${l%% *}" = "$CUR" ] && [ "${l#* }" = "${GL_CUR:--}" ]; }' '[ "${l#* }" = "${GL_CUR:--}" ]; }'
mut "U3 updater: staged-before not compared (stale marker honoured)" F2 $U '[ "${l%% *}" = "$CUR" ] && [ "${l#* }" = "${GL_CUR:--}" ]; }' '[ "${l%% *}" = "$CUR" ]; }'
mut "U4 updater: old-format marker accepted" F2 $U 'case "$l" in *" "*) ;; *) return 1 ;; esac; [ "${l%% *}" = "$CUR" ] && [ "${l#* }" = "${GL_CUR:--}" ]; }' '[ "${l%% *}" = "$CUR" ] && { [ "${l#* }" = "${GL_CUR:--}" ] || [ "${l%% *}" = "$l" ]; }; }'
mut "U5 updater: symlinked marker is read" F2 $U '[ -f "$PEND" ] && [ ! -L "$PEND" ] && head' '[ -f "$PEND" ] && head'
mut "U6 updater: marker written through a symlink" F2 $U 'up_marker_set() { [ -n "$PEND" ] && [ ! -L "$PEND" ] && {' 'up_marker_set() { [ -n "$PEND" ] && {'
mut "U7 updater: staged-before not recorded" F2 $U "printf '%s %s\\n' \"\$TSHA\" \"\${GL_CUR:--}\"" "printf '%s %s\\n' \"\$TSHA\" -"
mut "B5 built-in: marker written AFTER the checkout" F1 $I '  hi_marker_set "$tsha" "$gl"
  hi_user_umask hi_gx -C "$sub" checkout --quiet --detach "$tsha" || return 1' '  hi_user_umask hi_gx -C "$sub" checkout --quiet --detach "$tsha" || return 1
  hi_marker_set "$tsha" "$gl"'
mut "B6 updater: marker written AFTER the checkout" F2 $U '  up_marker_set   # always (the staged-gitlink rule above reads it); with --no-hook it is removed right after staging
  hi_gx -C "$SUB" checkout --quiet --detach "$TSHA" || die 1 "checkout of $TSHA failed"' '  hi_gx -C "$SUB" checkout --quiet --detach "$TSHA" || die 1 "checkout of $TSHA failed"
  up_marker_set'
mut "S3 built-in: WRONG marker before the checkout, correct one after" F1 $I '  hi_marker_set "$tsha" "$gl"
  hi_user_umask hi_gx -C "$sub" checkout --quiet --detach "$tsha" || return 1' '  hi_marker_set "$cur" "$gl"
  hi_user_umask hi_gx -C "$sub" checkout --quiet --detach "$tsha" || return 1
  hi_marker_set "$tsha" "$gl"'
mut "S4 updater: WRONG marker before the checkout, correct one after" F2 $U '  up_marker_set   # always (the staged-gitlink rule above reads it); with --no-hook it is removed right after staging
  hi_gx -C "$SUB" checkout --quiet --detach "$TSHA" || die 1 "checkout of $TSHA failed"' '  TSHA_REAL="$TSHA"; TSHA="$CUR"; up_marker_set; TSHA="$TSHA_REAL"
  hi_gx -C "$SUB" checkout --quiet --detach "$TSHA" || die 1 "checkout of $TSHA failed"
  up_marker_set'
mut "H1 hash order reverted (cksum first)" F3 $I 'if command -v sha256sum >/dev/null 2>&1; then t=sha256sum' 'if false; then t=sha256sum'
mut "H2 --help does not mention the fail-closed rule" F3 $I 'when NEITHER sha256sum nor cksum' 'when no hash tool'
echo "# $killed killed, $surv survived of $n (mutants run)"
[ "$surv" = 0 ]
