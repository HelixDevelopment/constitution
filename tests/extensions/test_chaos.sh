#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_chaos.sh — the real engine is SIGKILLed at every named stage of add, remove, enable, disable,
# wire and lock (test hook: CONSTITUTION_EXT_TEST_MODE=1 + CONSTITUTION_EXT_TEST_KILL_AT=<stage>,
# honoured only with both set). After each kill the next engine run must recover: no staging or
# trash directory left, the tree and the lock agree (both present and verified, or both absent),
# and repeating the interrupted command completes it.
T_NAME=chaos
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
H="$SB/src"; copy_fixture hooks-fixture "$H"
INST="$R/extensions/_installed"
e() { eng --root "$R" --project-root "$P" "$@"; }
kill_at() { local st="$1"; shift
  OUT="$(CONSTITUTION_EXT_TEST_MODE=1 CONSTITUTION_EXT_TEST_KILL_AT="$st" bash "$ENGINE" --root "$R" --project-root "$P" "$@" </dev/null 2>&1)"; RC=$?
}
consistent() { # label — tree vs lock agree and no leftovers after a recovering run
  local l="$1" left inlock intree
  e list >/dev/null   # a read-only run never recovers (I3)
  e lock >/dev/null   # a mutating run performs recovery
  left="$(find "$INST" -maxdepth 1 -name '.staging-*' -o -maxdepth 1 -name '.trash-*' 2>/dev/null | wc -l)"
  eq "$l: no staging/trash left" 0 "$left"
  inlock=0; grep -q 'id: "hooks-fixture"' "$P/.constitution/extensions.lock.yml" 2>/dev/null && inlock=1
  intree=0; [ -e "$INST/hooks-fixture" ] && intree=1
  eq "$l: lock and tree agree" "$inlock" "$intree"
  if [ "$intree" = 1 ]; then e verify hooks-fixture; eq "$l: installed tree verifies" 0 "$RC"; fi
  check "$l: no journal left" test ! -e "$P/.constitution/extensions.txn"
}
e enable hello-fixture --yes
for st in add:staged add:checked add:journaled add:renamed add:locked; do
  kill_at "$st" add "$H" --dev --waiver-id W1 --yes
  eq "killed at $st (137)" 137 "$RC"
  consistent "after kill $st"
  e add "$H" --dev --waiver-id W1 --yes; eq "re-run add after $st" 0 "$RC"
  consistent "after re-add $st"
  e remove hooks-fixture --yes; eq "cleanup remove after $st" 0 "$RC"
done
e add "$H" --dev --waiver-id W1 --yes
for st in remove:journaled remove:trashed remove:locked; do
  kill_at "$st" remove hooks-fixture --yes
  eq "killed at $st (137)" 137 "$RC"
  consistent "after kill $st"
  e remove hooks-fixture --yes; RC1=$RC
  check "re-run remove after $st completes or reports absent" test "$RC1" -eq 0 -o "$RC1" -eq 1
  consistent "after re-remove $st"
  check "removed after $st" test ! -e "$INST/hooks-fixture"
  e add "$H" --dev --waiver-id W1 --yes
done
for st in enable:locked disable:locked lock:written; do
  case "$st" in enable:*) cmd=(enable hooks-fixture --yes);; disable:*) cmd=(disable hooks-fixture);; lock:*) cmd=(lock);; esac
  kill_at "$st" "${cmd[@]}"; eq "killed at $st (137)" 137 "$RC"
  python3 -I -c 'import sys; sys.path.insert(0,sys.argv[1]); import ext_yaml; ext_yaml.parse(open(sys.argv[2]).read())' \
    "$(dirname "$ENGINE")" "$P/.constitution/extensions.lock.yml"; eq "lock parses after kill $st" 0 $?
  consistent "after kill $st"
  e "${cmd[@]}"; eq "re-run after $st" 0 "$RC"
done
e enable hooks-fixture --yes
kill_at wire:partial wire --agent all --target "$P"; eq "killed mid-wire (137)" 137 "$RC"
e wire --agent all --target "$P"; eq "re-wire after kill" 0 "$RC"
check "wire complete after recovery" test -f "$P/.pi/prompts/hooks-fixture-run.md"
e unwire --agent all --target "$P"; eq "unwire" 0 "$RC"
eq "no managed shim left" 0 "$(grep -rl 'managed-by: constitution_ext' "$P/.opencode" "$P/.gemini" "$P/.qwen" "$P/.pi" 2>/dev/null | wc -l)"
# I3: a shared root. Project P's remove is killed after the tree was moved to trash; another project Q that uses
# the same root runs a read-only and a mutating command: neither may delete P's trash, so P's journal can roll back
Q="$SB/proj-q"; make_project "$Q"
eq_q() { OUT="$(bash "$ENGINE" --root "$R" --project-root "$Q" "$@" </dev/null 2>&1)"; RC=$?; }
kill_at remove:trashed remove hooks-fixture --yes; eq "I3 P remove killed after trashing (137)" 137 "$RC"
ntr() { find "$INST" -maxdepth 1 -name '.trash-*' | wc -l; }
eq "I3 P's trash exists" 1 "$(ntr)"
eq_q list; eq "I3 Q list" 0 "$RC"; eq "I3 Q list keeps P's trash" 1 "$(ntr)"
eq_q lock; eq "I3 Q lock (creates Q's state)" 0 "$RC"
eq_q lock; eq "I3 Q lock with recovery" 0 "$RC"; eq "I3 Q lock keeps P's trash" 1 "$(ntr)"
has "I3 Q's recovery ran and says why the trash is kept" "no journal of this project names it" "$OUT"
e lock; eq "I3 P recovers with its own journal" 0 "$RC"
eq "I3 P's trash consumed by its own recovery" 0 "$(ntr)"
check "I3 P's extension rolled back into place" test -d "$INST/hooks-fixture"
consistent "I3 after shared-root recovery"
e doctor; eq "doctor healthy at end" 0 "$RC"
finish
