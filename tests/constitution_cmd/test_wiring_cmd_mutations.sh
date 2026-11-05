#!/usr/bin/env bash
# tests/constitution_cmd/test_wiring_cmd_mutations.sh — paired mutations (§1.1) for test_wiring_cmd.sh (WIT-L03).
# A private copy of the two sources is mutated ONE way per run (the anchor must match exactly once) and
# test_wiring_cmd.sh, pointed at it through WIRING_CMD_SRC, must FAIL; the unmutated control must PASS.
# Exit 0 iff control passes and every mutant dies. Sandbox is mktemp, removed with safe_rm_rf.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL="$(cd "$HERE/../.." && pwd)"
. "$REAL/scripts/lib/safe_rm.sh"
SB="$(mktemp -d)" || exit 1; [ -n "$SB" ] && [ -d "$SB" ] || exit 1; SB="$(realpath -e "$SB")"
export SAFE_RM_ALLOWED_ROOTS="$SB"; trap 'safe_rm_rf "${SB:?}"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }; nok() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
fresh() { safe_rm_rf "${SB:?}/src"; mkdir -p "$SB/src/scripts/constitution_cmd" "$SB/src/scripts/constitution_ext"
  cp "$REAL/scripts/constitution_cmd/constitution_cmd.sh" "$REAL/scripts/constitution_cmd/args_file_read.py" "$SB/src/scripts/constitution_cmd/"
  cp "$REAL/scripts/constitution_ext/wiring_ledger.py" "$SB/src/scripts/constitution_ext/"; }
suite() { WIRING_CMD_SRC="$SB/src" bash "$HERE/test_wiring_cmd.sh" >"$SB/out" 2>&1; }
fresh; if suite; then ok "control (unmutated copy) passes"; else nok "control fails: $(tail -3 "$SB/out")"; fi
kill_mutant() { # name file old new
  fresh
  python3 -I - "$SB/src/$2" "$3" "$4" <<'PY' || { nok "mutant $1: anchor not unique"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p).read()
if s.count(a) != 1: sys.exit(1)
open(p, "w").write(s.replace(a, b))
PY
  if suite; then nok "mutant $1 SURVIVED"; else ok "mutant $1 killed ($(grep -c '^FAIL' "$SB/out") failures)"; fi
}
CMDF=scripts/constitution_cmd/constitution_cmd.sh; LED=scripts/constitution_ext/wiring_ledger.py
kill_mutant W1_unknown_arg_accepted $CMDF '*) die "wiring accepts only: inventory | check (--inventory / --check)"; return 2 ;;' '*) ;;'
kill_mutant W2_two_subcommands_ok   $CMDF '[ -z "$sub" ] || { die "wiring takes exactly one of: inventory | check"; return 2; }; sub=check ;;' 'sub=check ;;'
kill_mutant W3_no_subcommand_ok     $CMDF '[ -n "$sub" ] || { die "wiring needs one of: inventory | check"; return 2; }' ':'
kill_mutant W4_check_always_ok      $LED '"ok": all(r["state"] == "ours" for r in rows),  # RULE:W-check-ok' '"ok": True,'
kill_mutant W5_check_rc_not_mapped  $LED 'if cmd == "check" and not out.get("ok"):  # RULE:W-check-rc' 'if False:'
kill_mutant W6_no_shared_lock       $LED 'fcntl.flock(lockfd, fcntl.LOCK_SH)  # RULE:W-read-lock' 'pass'
kill_mutant W7_check_skips_classify $LED 'led.check()  # RULE:W-check-calls-status' '{"ok": True, "rows": []}'
printf 'wiring-cmd-mutations: PASS %d FAIL %d\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
