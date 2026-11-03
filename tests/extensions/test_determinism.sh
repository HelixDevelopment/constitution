#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_determinism.sh — determinism (§11.4.50: three identical runs from identical starting states
# produce byte-identical lock files, installed trees, shims and --json outputs) and idempotency
# (a second enable / wire / lock / unwire / disable is a no-op that leaves the state byte-identical).
T_NAME=determinism
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
H="$SB/src"; copy_fixture hooks-fixture "$H"
run_once() { # n — fresh root+project, full scripted sequence, prints a fingerprint
  local n="$1" R="$SB/r$1/croot" P="$SB/r$1/proj" out
  mkdir -p "$SB/r$n"; make_root "$R" >/dev/null; make_project "$P" >/dev/null
  copy_fixture hello-fixture "$R/extensions/hello-fixture"
  out=""
  for cmd in "enable hello-fixture --yes" "add $H --dev --waiver-id WD --yes" "enable hooks-fixture --yes" "wire --agent all --target $P" "lock"; do
    # shellcheck disable=SC2086
    bash "$ENGINE" --root "$R" --project-root "$P" $cmd </dev/null >/dev/null 2>&1 || out="$out FAIL[$cmd]"
  done
  local j1 j2 j3
  j1="$(bash "$ENGINE" --root "$R" --project-root "$P" --json list 2>/dev/null | sed "s#$SB/r$n#SB#g")"
  j2="$(bash "$ENGINE" --root "$R" --project-root "$P" --json info hooks-fixture 2>/dev/null | sed "s#$SB/r$n#SB#g")"
  j3="$(bash "$ENGINE" --root "$R" --project-root "$P" --json verify 2>/dev/null | sed "s#$SB/r$n#SB#g")"
  printf '%s|%s|%s|%s|%s|%s\n' "$out" "$(sha256sum <"$P/.constitution/extensions.lock.yml" | cut -c1-64)" \
    "$(tree_fp "$R/extensions/_installed")" \
    "$( (cd "$P" && find .opencode .gemini .qwen .pi -type f -exec sha256sum {} + | sort) | sha256sum | cut -c1-64)" \
    "$(printf '%s' "$j1$j2$j3" | sha256sum | cut -c1-64)" "$(cd "$P" && find .claude -type l -printf '%p\n' | sort | sha256sum | cut -c1-64)"
}
a="$(run_once 1)"; b="$(run_once 2)"; c="$(run_once 3)"
echo "  run1 $a"; echo "  run2 $b"; echo "  run3 $c"
hasnt "run had no failing step" "FAIL[" "$a$b$c"
eq "run1 == run2" "$a" "$b"; eq "run2 == run3" "$b" "$c"

R="$SB/r1/croot"; P="$SB/r1/proj"
st() { printf '%s%s%s%s' "$(tree_fp "$P/.constitution")" "$(tree_fp "$R/extensions")" "$(tree_fp "$P/.claude")" "$(tree_fp "$P/.gemini")"; }
s0="$(st)"
for cmd in "enable hooks-fixture --yes" "wire --agent all --target $P" "lock"; do
  # shellcheck disable=SC2086
  eng --root "$R" --project-root "$P" $cmd; eq "idempotent rc: $cmd" 0 "$RC"; eq "idempotent state: $cmd" "$s0" "$(st)"
done
eng --root "$R" --project-root "$P" add "$H" --dev --waiver-id WD --yes; eq "re-add same content idempotent" 0 "$RC"; eq "re-add state" "$s0" "$(st)"
eng --root "$R" --project-root "$P" unwire --agent all --target "$P"; s1="$(st)"
eng --root "$R" --project-root "$P" unwire --agent all --target "$P"; eq "second unwire rc" 0 "$RC"; eq "second unwire no-op" "$s1" "$(st)"
eng --root "$R" --project-root "$P" disable hooks-fixture; s2="$(st)"
eng --root "$R" --project-root "$P" disable hooks-fixture; eq "second disable rc" 0 "$RC"; eq "second disable no-op" "$s2" "$(st)"
finish
