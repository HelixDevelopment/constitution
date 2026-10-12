#!/usr/bin/env bash
# scripts/label-sync/prove_mutations.sh
#
# Purpose : §1.1 paired-mutation proof for label-sync CORE. Copies the Go
#           module to a SCRATCH dir, applies each of six independent mutants
#           (one per scratch copy), runs `go test` and REQUIRES the suite to
#           FAIL; a control run of the unmutated copy REQUIRES it to pass. A
#           mutant that survives means the tests do not guard that behaviour.
#           Mutants: alias switch ignored | non-atomic write | followers vs
#           non-followers inverted | TTL never expiring | grammar accepting a
#           bad label | torn event-log tail counted as corruption.
# Usage   : bash scripts/label-sync/prove_mutations.sh [--only <mutant-name>]
# Inputs  : none (reads the module next to this script).
# Outputs : one line per mutant: KILLED / SURVIVED / NOT-APPLIED, then a summary.
# Exit    : 0 every mutant killed and control green | 1 a mutant survived or the
#           control failed | 2 environment (no go, copy failure, mutation did
#           not apply) — never a pass.
# Side-effects: temp dir under $TMPDIR (trap-removed). Never edits the real tree.
#           Uses `nice` and `go test -p 2`; GOPROXY=off (stdlib only).
# Deps    : bash, go, sed, cmp, mktemp.
# Cross-refs: §1.1, §11.4.107 (self-validated oracle), §11.4.201, §11.4.18.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v go >/dev/null 2>&1 || { echo "prove_mutations: go not found" >&2; exit 2; }
ONLY=""
[ "${1:-}" = "--only" ] && ONLY="${2:-}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/label_sync_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# name|file|sed-expression (must change the file)
MUTANTS=(
  'alias_switch_ignored|internal/state/fold.go|s|^\t\tr\.Active = model\.Active{.*$|\t\t_ = ev.Active|'
  'non_atomic_write|internal/state/atomic.go|s|f, err := os\.CreateTemp(dir, "\."+filepath\.Base(path)+"\.tmp-\*")|f, err := os.OpenFile(path, os.O_CREATE\|os.O_WRONLY\|os.O_TRUNC, 0o600)|'
  'followers_inverted|internal/state/fold.go|s|if e\.FollowActive { // MUT:follow|if !e.FollowActive {|'
  'ttl_never_expires|internal/state/fold.go|s|if !(age > o\.TTL) { // MUT:ttl|if true {|'
  'grammar_accepts_bad|internal/label/label.go|s|\^\\(T(\[0-9\]+\|\\?)/|^\\(T(.*)/|'
  'torn_tail_is_corruption|internal/state/store.go|s|if b != n { // a bad FINAL line is a torn write, not corruption|if true {|'
)

run_tests() { ( cd "$1" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go test -p 2 -count=1 ./... >"$2" 2>&1 ); }

fail=0; killed=0; total=0
# control
CTL="$TMP/control"; mkdir -p "$CTL" && cp -R "$SELF/." "$CTL/" || exit 2
if run_tests "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated module: tests PASS"
else echo "CONTROL   FAILED — unmutated tests do not pass (see $TMP/control.log)"; tail -20 "$TMP/control.log"; exit 1; fi

for m in "${MUTANTS[@]}"; do
  name="${m%%|*}"; rest="${m#*|}"; file="${rest%%|*}"; expr="${rest#*|}"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  total=$((total+1))
  d="$TMP/$name"; mkdir -p "$d" && cp -R "$SELF/." "$d/" || exit 2
  cp "$d/$file" "$d/$file.orig"
  sed -i "$expr" "$d/$file" || exit 2
  if cmp -s "$d/$file" "$d/$file.orig"; then echo "NOT-APPLIED $name — sed did not change $file"; exit 2; fi
  rm -f "$d/$file.orig"
  if run_tests "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — tests still PASS with the mutant (bluff gap)"; fail=1
  else
    echo "KILLED    $name ($(grep -cE '^(--- FAIL|FAIL)' "$TMP/$name.log") failing marker lines)"; killed=$((killed+1))
  fi
done
echo "----"
echo "mutants killed: $killed / $total"
[ "$fail" -eq 0 ] && [ "$killed" -eq "$total" ] || exit 1
echo "label-sync paired-mutation proof: PASS"
exit 0
