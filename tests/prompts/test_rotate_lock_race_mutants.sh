#!/usr/bin/env bash
# test_rotate_lock_race_mutants.sh — paired mutation proof (§1.1) for test_rotate_lock_race.sh.
# Env: LRM_ONLY="<ids>" (a subset). Each mutant of scripts/prompts/rotate_setup_prompt.sh is written to a sandbox and the race
# suite is run against it (ROTATE_RACE_SCRIPT); every mutant must make the suite FAIL.
#   L-MKDIR-EXCL   the round-5 lock: `mkdir` as the exclusive step, pid written plainly
#   L-NOCLOBBER    the claim writes pid without noclobber (not O_EXCL)
#   L-PRECHECK     the claim no longer refuses an existing pid before opening it
#   L-RECHECK      no re-check of the history after the lock is taken
#   L-PIDTYPE      a symlink / non-regular pid in a stale lock is no longer refused
#   L-IDCHECK      the claim does not verify that what it created is a regular file holding its id
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
W="$(mk_sandbox)"; export ROTATE_RACE_ROUNDS="${ROTATE_RACE_ROUNDS:-3}"   # deterministic tests do the killing
mut() { # <id> -> writes $W/<id>/scripts/prompts/rotate_setup_prompt.sh (its library beside it)
  mkdir -p "$W/$1/scripts/prompts" "$W/$1/scripts/lib" && cp -p "$REPO/scripts/lib/setup_prompt_extract.sh" "$W/$1/scripts/lib/" || return 1
  python3 -I - "$ROTATE" "$W/$1/scripts/prompts/rotate_setup_prompt.sh" "$1" <<'PY'
import sys
src, dst, mid = sys.argv[1:]
s = open(src).read(); o = s
def r(a, b):
    global s
    assert a in s, (mid, a[:50]); s = s.replace(a, b, 1)
if mid == 'L-MKDIR-EXCL':
    r('  if ! rsp_claim_lock "$lk" "$RSP_LOCK_ID"; then',
      '  mkdir -- "$lk" 2>/dev/null && printf \'%s\\n\' "$RSP_LOCK_ID" >"$lk/pid"\n  if [ "$?" -ne 0 ]; then')
elif mid == 'L-NOCLOBBER':
    r('( set -o noclobber; printf', '( printf')
elif mid == 'L-PRECHECK':
    r('  if [ -e "$lk/pid" ] || [ -L "$lk/pid" ]; then return 1; fi   # never open', '  # removed:')
elif mid == 'L-RECHECK':
    r('  if ! rsp_scan_numbering "$dir" 2>/dev/null || [ "$(rsp_format_number', '  if false && ! rsp_scan_numbering "$dir" 2>/dev/null || false && [ "$(rsp_format_number')
    r('     || [ -e "$dir/$target" ] || [ -L "$latest" ] || [ ! -f "$latest" ]; then\n    rsp_err "refusing: $dir changed', '     || false; then\n    rsp_err "refusing: $dir changed')
elif mid == 'L-PIDTYPE':
    r('    if [ -L "$lk/pid" ] || { [ -e "$lk/pid" ] && [ ! -f "$lk/pid" ]; }; then', '    if false; then')
    r('    if [ -L "$st" ] || [ ! -f "$st" ] || ', '    if ')   # round 7: the takeover re-checks the type too
    r('  elif [ -e "$lk/pid" ] || [ -L "$lk/pid" ]; then', '  elif false; then')
elif mid == 'L-IDCHECK':
    r('  [ ! -L "$lk/pid" ] && [ -f "$lk/pid" ] && [ "$(head -n1 -- "$lk/pid" 2>/dev/null)" = "$id" ]\n}', '  true\n}')
else:
    sys.exit(9)
open(dst, 'w').write(s); sys.exit(0 if s != o else 1)
PY
}
for m in ${LRM_ONLY:-L-MKDIR-EXCL L-NOCLOBBER L-PRECHECK L-RECHECK L-PIDTYPE L-IDCHECK}; do
  mut "$m" || { no "mutant $m not placed"; continue; }
  if ROTATE_RACE_SCRIPT="$W/$m/scripts/prompts/rotate_setup_prompt.sh" bash "$(dirname "${BASH_SOURCE[0]}")/test_rotate_lock_race.sh" >"$W/$m.out" 2>&1; then
    no "mutant $m SURVIVED"
  else ok "mutant $m killed ($(grep -m1 '^FAIL' "$W/$m.out" | cut -c1-100))"; fi
done
summary lock_race_mutants
