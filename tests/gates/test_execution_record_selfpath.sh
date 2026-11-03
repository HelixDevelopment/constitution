#!/usr/bin/env bash
# tests/gates/test_execution_record_selfpath.sh -- F1 (review round 8): an ambient XR_SELF_PATH must never steer which
# credential scanner _xr_redact loads. Driven under dash (POSIX sh, where BASH_SOURCE is absent) through the REAL library.
# A forged scanner that always says "clean" (rc 1) must not make a ghp_ token look clean: the result must be rc 3
# (could not scan, fail closed) or rc 0 (redacted by the REAL scanner), never rc 1.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
command -v dash >/dev/null 2>&1 || { echo "SKIP dash not installed"; exit 0; }
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
chk() { if [ "$1" = 0 ]; then pass=$((pass+1)); echo "PASS $2"; else fail=$((fail+1)); echo "FAIL $2"; fi; }
mkdir -p "$sb/evil/a/b" "$sb/evil/hooks"
printf 'helix_cred_scan_file() { return 1; }\n' >"$sb/evil/hooks/credential_scan_lib.sh"
printf 'token ghp_%s\n' "$(printf 'a%.0s' $(seq 1 36))" >"$sb/leak.txt"
LIB="${XR_LIB_UNDER_TEST:-$src/scripts/gates/lib/execution_record.sh}"   # XR_LIB_UNDER_TEST: the mutation test points this at a sabotaged copy
drive() { # XR_SELF_PATH value ("" = unset) -> prints rc of _xr_redact
  local f="$sb/leak.$RANDOM.txt"; cp "$sb/leak.txt" "$f"
  if [ -n "$1" ]; then env XR_SELF_PATH="$1" dash -c '. "$1"; _xr_redact "$2"; echo $?' _ "$LIB" "$f" 2>/dev/null | tail -1
  else env -u XR_SELF_PATH dash -c '. "$1"; _xr_redact "$2"; echo $?' _ "$LIB" "$f" 2>/dev/null | tail -1; fi
}
rc="$(drive "$sb/evil/a/b/x")"; [ "$rc" != 1 ] && [ -n "$rc" ]; chk $? "F1 dash + forged XR_SELF_PATH: token not reported clean (rc=$rc)"
[ "$rc" = 3 ]; chk $? "F1 dash + forged XR_SELF_PATH: fails closed rc=3 (rc=$rc)"
rc="$(drive "")"; [ "$rc" = 3 ]; chk $? "F1 dash, XR_SELF_PATH unset: fails closed rc=3 (cannot locate scanner) (rc=$rc)"
# bash path still works: real scanner redacts the token (rc 0), and a forged XR_SELF_PATH in the environment is overwritten
f="$sb/leak.bash.txt"; cp "$sb/leak.txt" "$f"
rc="$(env XR_SELF_PATH="$sb/evil/a/b/x" bash -c '. "$1"; _xr_redact "$2"; echo $?' _ "$LIB" "$f" 2>/dev/null | tail -1)"
[ "$rc" = 0 ]; chk $? "bash + forged XR_SELF_PATH: real scanner used, token redacted (rc=$rc)"
# N1: BASH_SOURCE is ambient (dash/busybox import it; bash 5.3 keeps an imported scalar across '.'): a forged value must
# not select the scanner either. Driven under dash AND bash.
for sh in dash bash; do
  command -v "$sh" >/dev/null 2>&1 || continue
  f="$sb/leak.bs.$sh.txt"; cp "$sb/leak.txt" "$f"
  rc="$(env BASH_SOURCE="$sb/evil/a/b/x" "$sh" -c '. "$1"; _xr_redact "$2"; echo $?' _ "$LIB" "$f" 2>/dev/null | tail -1)"
  [ "$rc" != 1 ] && [ -n "$rc" ]; chk $? "N1 $sh + forged BASH_SOURCE: token not reported clean (rc=$rc)"
  [ "$rc" = 3 ] || [ "$sh" = bash -a "$rc" = 0 ]; chk $? "N1 $sh + forged BASH_SOURCE: fail closed rc=3 (bash may also redact via the real scanner) (rc=$rc)"
  grep -q 'ghp_a' "$f"; [ $? -ne 0 ] || [ "$rc" = 3 ]; chk $? "N1 $sh + forged BASH_SOURCE: stream not left clean-marked with token (rc=$rc)"
done
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
