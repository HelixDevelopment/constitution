#!/usr/bin/env bash
# scripts/label-sync/prove_hook_mutations.sh
#
# Purpose : §1.1 paired-mutation proof for the label-sync HOOKS + WIRING stream.
#           Copies the label-sync tree and the files the test suite needs into a
#           SCRATCH constitution root, applies ONE mutant per scratch copy and
#           REQUIRES scripts/hooks/test_label_sync_hooks.sh (run --fail-fast
#           against that copy) to FAIL; a control run of the unmutated copy
#           REQUIRES it to pass. A surviving mutant = the tests do not guard that
#           behaviour (a bluff gap).
#           Mutants: hook_never_registers | alias_republish_skipped |
#           installer_duplicates_entries | installer_clobbers_hooks |
#           dry_run_writes | invalid_json_accepted | ledger_double_appends |
#           hook_exits_nonzero | stop_keeps_phantoms | wrapper_never_publishes.
# Usage   : bash scripts/label-sync/prove_hook_mutations.sh [--only <mutant>] [--list]
# Inputs  : none (reads the tree this script lives in).
# Outputs : one line per mutant: KILLED / SURVIVED / NOT-APPLIED, then a summary.
# Exit    : 0 every mutant killed and the control green | 1 a mutant survived or
#           the control failed | 2 environment (jq/go missing, copy failed, a
#           mutation did not apply) — never a pass.
# Side-effects: a temp dir under $TMPDIR (trap-removed); builds the Go binaries
#           into it once (nice). The real tree is never edited.
# Deps    : bash, jq, go, python3 (literal-replace mutator), git (the suite).
# Cross-refs: §1.1, §11.4.107(10), §11.4.201, §11.4.18,
#           scripts/gates/cm_label_sync_hooks.sh.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CROOT="$(cd "$SELF/../.." && pwd)"
ONLY=""; LIST=""
while [ $# -gt 0 ]; do
  case "$1" in --only) ONLY="${2:-}"; shift 2 ;; --list) LIST=1; shift ;; *) echo "unknown arg $1" >&2; exit 2 ;; esac
done
for t in jq python3 go git; do command -v "$t" >/dev/null 2>&1 || { echo "prove_hook_mutations: $t not found" >&2; exit 2; }; done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/label_sync_hookmut.XXXXXX")" || exit 2
trap 'rm -rf "${TMP:?}"' EXIT

# Each mutant = (file relative to the constitution root, OLD literal, NEW literal),
# applied by apply_mutant() below with a LITERAL (not regex) single replacement.
MUT_NAMES=(hook_never_registers alias_republish_skipped installer_duplicates_entries installer_clobbers_hooks dry_run_writes invalid_json_accepted ledger_double_appends hook_exits_nonzero stop_keeps_phantoms wrapper_never_publishes)
if [ -n "$LIST" ]; then printf '%s\n' "${MUT_NAMES[@]}"; exit 0; fi

apply_mutant() { # name root  -> prints file; rc 0 applied, 1 not applied
  python3 - "$1" "$2" <<'PYEOF'
import sys
name, root = sys.argv[1], sys.argv[2]
M = {
 "hook_never_registers": ("scripts/label-sync/hooks/label-sync-lib.sh",
    'ls_ctl "${a[@]}" >/dev/null || { ls_dbg "register session failed"; return 1; }',
    ': # MUTANT: session never registered'),
 "alias_republish_skipped": ("scripts/label-sync/hooks/label-sync-lib.sh",
    '[ "$prev" != "$alias" ] && changed=1',
    '[ "$prev" != "$alias" ] && changed='),
 "installer_duplicates_entries": ("scripts/label-sync/install_label_sync.sh",
    'if ($p|length)==0 then',
    'if true then'),
 "installer_clobbers_hooks": ("scripts/label-sync/install_label_sync.sh",
    '.hooks[$s.event] = (.hooks[$s.event] // [])',
    '.hooks[$s.event] = []'),
 "dry_run_writes": ("scripts/label-sync/install_label_sync.sh",
    'if [ "$apply" = 0 ]; then\n  if [ "$brief" = 1 ]; then',
    'if false; then\n  if [ "$brief" = 1 ]; then'),
 "invalid_json_accepted": ("scripts/label-sync/install_label_sync.sh",
    "if ! jq -e 'type==\"object\"' \"$target\" >/dev/null 2>&1; then\n    echo \"install_label_sync: REFUSED",
    "if false; then\n    echo \"install_label_sync: REFUSED"),
 "ledger_double_appends": ("scripts/label-sync/hooks/request_history_append.sh",
    'if [ "$lprompt" = "$prompt" ] && [ $(( now_ms - ${lms:-0} )) -lt "$win" ]; then return 0; fi',
    ': # MUTANT: no dedupe'),
 "hook_exits_nonzero": ("scripts/label-sync/hooks/label-sync-lib.sh",
    "  [ -n \"$out\" ] && printf '%s\\n' \"$out\"\n  exit 0",
    "  [ -n \"$out\" ] && printf '%s\\n' \"$out\"\n  exit 3"),
 "stop_keeps_phantoms": ("scripts/label-sync/hooks/label-sync-stop.sh",
    '      [ -n "$eid" ] && ls_ctl unregister --id "$eid" >/dev/null\n      rm -f "${f:?}"',
    '      rm -f "${f:?}"'),
 "wrapper_never_publishes": ("scripts/label-sync/toolkit/cma_label_hook.sh",
    '  _cma_label_publish "$alias"\n}',
    '  :\n}'),
}
f, old, new = M[name]
p = root + "/" + f
s = open(p).read()
if old not in s:
    print("NOT-APPLIED: literal not found in " + f); sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
print(f)
PYEOF
}

copy_root() { # dest
  mkdir -p "$1/scripts/multitrack" "$1/scripts/hooks" || return 1
  cp -R "$CROOT/scripts/label-sync/." "$1/scripts/label-sync/" 2>/dev/null || { mkdir -p "$1/scripts/label-sync"; cp -R "$CROOT/scripts/label-sync/." "$1/scripts/label-sync/" || return 1; }
  cp "$CROOT/scripts/multitrack/track_branch_label.sh" "$1/scripts/multitrack/" || return 1
  cp "$CROOT/scripts/hooks/test_label_sync_hooks.sh" "$1/scripts/hooks/" || return 1
  cp "$CROOT/scripts/post_update_hook.sh" "$1/scripts/" || return 1
  return 0
}

# one build of the Go binaries, shared (the mutants never touch Go sources)
export LABEL_SYNC_BIN="$TMP/bin"
if ! LABEL_SYNC_DIR="$TMP/buildstate" nice -n 10 bash "$CROOT/scripts/label-sync/labelctl.sh" --build >/dev/null 2>"$TMP/build.err"; then
  echo "prove_hook_mutations: cannot build the Go binaries: $(tail -3 "$TMP/build.err")" >&2; exit 2
fi
export LS_TEST_BIN="$TMP/bin"

run_suite() { ( cd "$1" && nice -n 10 bash scripts/hooks/test_label_sync_hooks.sh --fail-fast >"$2" 2>&1 ); }

CTL="$TMP/control"; copy_root "$CTL" || { echo "copy failed" >&2; exit 2; }
if run_suite "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated copy: suite PASS"
else echo "CONTROL   FAILED — the unmutated suite does not pass (tail):"; tail -15 "$TMP/control.log"; exit 1; fi

fail=0; killed=0; total=0
for name in "${MUT_NAMES[@]}"; do
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  total=$((total + 1))
  d="$TMP/m_$name"; copy_root "$d" || { echo "copy failed" >&2; exit 2; }
  if ! out="$(apply_mutant "$name" "$d")"; then echo "NOT-APPLIED $name — $out"; exit 2; fi
  if run_suite "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — suite still PASSES with the mutant in $out (bluff gap)"; fail=1
  else
    echo "KILLED    $name ($out) — first failure: $(grep -m1 '❌ FAIL' "$TMP/$name.log" | cut -c1-110)"; killed=$((killed + 1))
  fi
done
echo "----"
echo "mutants killed: $killed / $total"
[ "$fail" -eq 0 ] && [ "$killed" -eq "$total" ] || exit 1
echo "label-sync hooks paired-mutation proof: PASS"
exit 0
