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
#           The mutant table (name, file, OLD, NEW, why) lives in
#           scripts/label-sync/hook_mutants.py (`--list` prints it): the ten
#           original mutants, the six the independent review found SURVIVING
#           (ledger_shared_dedupe_key, session_end_keeps_pending,
#           posthook_4c_aborts_hook, uninstall_removes_foreign_statusline,
#           subagent_pairing_newest_first, nested_parent_ignored) and one per
#           mechanism added by review findings 1-11.
# Usage   : bash scripts/label-sync/prove_hook_mutations.sh [--only <mutant>[,<mutant>…]] [--list] [--jobs N]
#           --jobs N  run N mutated suites in parallel (default 2; each one is a
#                     light bash suite; every run gets its OWN copy of the Go
#                     binaries so no run can see another run's labelctl).
# Inputs  : none (reads the tree this script lives in).
# Outputs : one line per mutant: KILLED / SURVIVED / NOT-APPLIED / UNDETERMINED (the
#           suite failed without an assertion line — never counted as a kill), then a summary.
# Exit    : 0 every mutant killed and the control green | 1 a mutant survived or
#           the control failed | 2 environment (jq/go/python3 missing, copy
#           failed, a mutation did not apply) — never a pass.
# Side-effects: a temp dir under $TMPDIR (trap-removed); builds the Go binaries
#           into it once (nice). The real tree is never edited.
# Deps    : bash, jq, go, python3, git, flock (the suite's lock tests).
# Cross-refs: §1.1, §11.4.107(10), §11.4.201, §11.4.18,
#           scripts/gates/cm_label_sync_hooks.sh, docs/label-sync/HOOKS.md.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CROOT="$(cd "$SELF/../.." && pwd)"
MUT="$SELF/hook_mutants.py"
ONLY=""; LIST=""; JOBS=2
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --list) LIST=1; shift ;;
    --jobs) JOBS="${2:-3}"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
case "$JOBS" in ''|*[!0-9]*|0) echo "--jobs needs a positive integer" >&2; exit 2 ;; esac
for t in jq python3 go git; do command -v "$t" >/dev/null 2>&1 || { echo "prove_hook_mutations: $t not found" >&2; exit 2; }; done
[ -f "$MUT" ] || { echo "prove_hook_mutations: mutant table missing: $MUT" >&2; exit 2; }
if [ -n "$LIST" ]; then python3 "$MUT" --list; exit 0; fi
mapfile -t NAMES < <(python3 "$MUT" --list)
[ "${#NAMES[@]}" -gt 0 ] || { echo "prove_hook_mutations: empty mutant table" >&2; exit 2; }
if [ -n "$ONLY" ]; then          # one name or a comma-separated list
  IFS=, read -r -a SEL <<<"$ONLY"
  for n in "${SEL[@]}"; do
    printf '%s\n' "${NAMES[@]}" | grep -qx -- "$n" || { echo "unknown mutant $n" >&2; exit 2; }
  done
  NAMES=("${SEL[@]}")
fi
# every literal must still occur exactly once in the REAL tree (a stale table
# would otherwise "pass" by reporting NOT-APPLIED as an environment error late)
python3 "$MUT" --check "$CROOT" >/dev/null || { python3 "$MUT" --check "$CROOT" | grep -v '^OK' >&2; echo "prove_hook_mutations: mutant table out of date" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/label_sync_hookmut.XXXXXX")" || exit 2
trap 'rm -rf "${TMP:?}"' EXIT

copy_root() { # dest
  mkdir -p "$1/scripts/multitrack" "$1/scripts/hooks" "$1/scripts/label-sync" || return 1
  cp -R "$CROOT/scripts/label-sync/." "$1/scripts/label-sync/" || return 1
  cp "$CROOT/scripts/multitrack/track_branch_label.sh" "$1/scripts/multitrack/" || return 1
  cp "$CROOT/scripts/hooks/test_label_sync_hooks.sh" "$1/scripts/hooks/" || return 1
  cp "$CROOT/scripts/post_update_hook.sh" "$1/scripts/" || return 1
  mkdir -p "$1/mcp" && cp "$CROOT/mcp/label-sync-mcp.json" "$1/mcp/" || return 1   # suite §20 D merges it
  mkdir -p "$1/bin" && cp "$TMP/bin/"* "$1/bin/" || return 1        # private binaries per run
  return 0
}

# one build of the Go binaries (the mutants never touch Go sources)
if ! LABEL_SYNC_BIN="$TMP/bin" LABEL_SYNC_DIR="$TMP/buildstate" nice -n 10 bash "$CROOT/scripts/label-sync/labelctl.sh" --build >/dev/null 2>"$TMP/build.err"; then
  echo "prove_hook_mutations: cannot build the Go binaries: $(tail -3 "$TMP/build.err")" >&2; exit 2
fi

run_suite() { # root log
  # LS_LATENCY_MS is lifted: latency is measured by the plain suite run; under
  # parallel mutated runs a latency miss would "kill" a mutant for the WRONG
  # reason (§11.4.201) — a kill must come from the behaviour the mutant breaks.
  ( cd "$1" && LS_TEST_BIN="$1/bin" LABEL_SYNC_BIN="$1/bin" LS_LATENCY_MS=60000 nice -n 10 bash scripts/hooks/test_label_sync_hooks.sh --fail-fast >"$2" 2>&1 )
}

CTL="$TMP/control"; copy_root "$CTL" || { echo "copy failed" >&2; exit 2; }
if run_suite "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated copy: suite PASS ($(grep -m1 'label-sync hooks suite:' "$TMP/control.log"))"
else echo "CONTROL   FAILED — the unmutated suite does not pass (tail):"; tail -15 "$TMP/control.log"; exit 1; fi

one() { # name -> writes $TMP/res_<name>
  local name="$1" d="$TMP/m_$1" out
  copy_root "$d" || { echo "ENV       $name — copy failed" >"$TMP/res_$name"; return; }
  if ! out="$(python3 "$MUT" --apply "$name" "$d")"; then echo "NOT-APPLIED $name — $out" >"$TMP/res_$name"; return; fi
  if run_suite "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — suite still PASSES with the mutant in $out (bluff gap)" >"$TMP/res_$name"
  else
    local first; first="$(grep -m1 '❌ FAIL' "$TMP/$name.log" | cut -c1-110)"
    # a kill must come from a failing ASSERTION; a suite that died without one
    # (syntax error, crash) proves nothing about the tests — UNDETERMINED (§11.4.201)
    if [ -z "$first" ]; then
      echo "UNDETERMINED $name — suite failed with no '❌ FAIL' assertion line (tail: $(tail -1 "$TMP/$name.log" | cut -c1-80))" >"$TMP/res_$name"
      rm -rf "${d:?}"; return
    fi
    # a kill attributed to a load-sensitive TIMING assertion may be load, not the mutant:
    # re-run alone (see below) before it counts.
    # (F9's "returns within" bounds are NOT in this class: a lock-timeout bound
    # is the very behaviour lock_timeout_dropped breaks.)
    case "$first" in *latency*|*"handled within"*) echo "TIMING    $name — $first" >"$TMP/res_$name" ;;
      *) echo "KILLED    $name ($out) — first failure: $first" >"$TMP/res_$name" ;; esac
  fi
  rm -rf "${d:?}"
}

running=0
for name in "${NAMES[@]}"; do
  one "$name" &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then wait -n 2>/dev/null || true; running=$((running - 1)); fi
done
wait
# timing-attributed kills: re-run sequentially (no parallel load) once
for name in "${NAMES[@]}"; do
  case "$(cat "$TMP/res_$name" 2>/dev/null)" in TIMING*) ;; *) continue ;; esac
  one "$name"
  # still a timing failure with NO parallel mutated runs => the mutant's own
  # effect (e.g. the 2 s default lock wait) — counted as a kill, labelled so.
  case "$(cat "$TMP/res_$name")" in TIMING*) sed -i '1s/^TIMING    \(.*\)$/KILLED    \1 [timing kill, re-run alone]/' "$TMP/res_$name" ;; esac
done

killed=0; total=0; fail=0; envfail=0
for name in "${NAMES[@]}"; do
  total=$((total + 1)); line="$(cat "$TMP/res_$name" 2>/dev/null || echo "ENV       $name — no result")"
  echo "$line"
  case "$line" in KILLED*) killed=$((killed + 1)) ;; SURVIVED*) fail=1 ;; *) envfail=1 ;; esac
done
echo "----"
echo "mutants killed: $killed / $total"
[ "$envfail" -eq 0 ] || { echo "label-sync hooks paired-mutation proof: ENVIRONMENT ERROR or UNDETERMINED (a mutant could not be applied/run, or failed with no assertion) — not a pass"; exit 2; }
[ "$fail" -eq 0 ] && [ "$killed" -eq "$total" ] || exit 1
echo "label-sync hooks paired-mutation proof: PASS"
exit 0
