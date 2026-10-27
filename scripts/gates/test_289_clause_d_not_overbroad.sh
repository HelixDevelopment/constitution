#!/usr/bin/env bash
# test_289_clause_d_not_overbroad.sh — regression test for the §11.4.289(D) false-positive class
# (review r2 F1 / §11.4.276(C) class: over-broad disqualification of LIVE evidence by an
# incidental property — loopback, test-started, test-directory location, container on demand).
#
# Purpose : prove the §11.4.289 carriers (Constitution.md, the 4 mirrors, groups/anti-bluff-and-evidence.md)
#           and the OWED-GATE-161..164 deferral text disqualify live evidence ONLY for an imitation
#           (identity of what answered), never for where it runs or who started it.
# Usage   : test_289_clause_d_not_overbroad.sh [--root <dir>]   (default: repository root of this script)
# Exit    : 0 pass, 1 a forbidden over-broad pattern or a missing required phrase, 2 usage/blind instrument.
# Side effects: none (read-only). Control needle: the instrument must find the anchor heading in every
#           carrier and must find a planted forbidden phrase in a scratch copy (§11.4.201(7)(b), §11.4.273).
# Tests   : this file IS the test (§11.4.224); a paired mutation is built in (self-check section).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ "${1:-}" = "--root" ] && ROOT="$2"
CARRIERS="Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md groups/anti-bluff-and-evidence.md"
OTHERS="scripts/gates/gate_ledger_deferrals.tsv docs/owed_gate_implementations.md"
# Forbidden (over-broad) patterns: a disqualification keyed on an incidental property.
FORBID=(
  'only a process the test started or one under a test directory is disqualifying'
  'the endpoint is not loopback or a test-started process'
  'one the test itself started to imitate the service, a process whose executable lives under a test directory, or a recorded file'
)
# Required phrases (the positive golden-TRUE content).
REQUIRE=(
  'DISPOSITION TURNS ON ONE BIT'
  'Examples that MUST stay LIVE'
  'registered double'
)
# The four canonical UNIT-class conditions, verbatim (identity of what answered, never where or who).
UNIT_EXACT=(
  '(i) the answering executable or image is a registered double (listed in the project'"'"'s declared double register, consumer DATA per §11.4.35, or by its own identity a fixture server, mock, stub, replay or canned-answer binary or image)'
  '(ii) its identity does not match the real artifact or real dependency the claim names (executable hash or image digest differs from the fingerprint or the pinned digest the record cites)'
  '(iii) its answers are read from recorded or canned data'
  '(iv) the identity fields needed to decide (i) to (iii) are absent or unresolvable'
)
fail=0
scan() { # $1 file ; $2 mode forbid|require
  local f="$ROOT/$1" p
  [ -f "$f" ] || { echo "BLIND: $1 missing"; fail=2; return; }
  if [ "$2" = forbid ]; then
    for p in "${FORBID[@]}"; do
      if grep -qF -- "$p" "$f"; then echo "FAIL over-broad in $1: $p"; [ $fail -eq 0 ] && fail=1; fi
    done
  else
    for p in "${REQUIRE[@]}"; do
      grep -qF -- "$p" "$f" || { echo "FAIL missing in $1: $p"; [ $fail -eq 0 ] && fail=1; }
    done
  fi
}
for c in $CARRIERS; do scan "$c" forbid; scan "$c" require; done
for o in $OTHERS; do scan "$o" forbid; done
# UNIT-class condition list (review r3 R3-2): the sentence that reclassifies a result UNIT-CLASS must hold
# EXACTLY the four allowed conditions (i)-(iv), and no condition may key on who launched the process, the
# network scope or the lifetime of what answered. Extracted per carrier, then counted and word-checked.
unit_list() { # $1 root-relative file ; prints the segment between the two anchor phrases (one line)
  python3 - "$ROOT/$1" <<'PYX'
import sys,re
t=open(sys.argv[1],encoding="utf-8").read().replace("\n"," ")
a=t.find("is reclassified UNIT-CLASS by the gate")
b=t.find("Loopback, test-started, ephemeral port",a)
print(t[a:b] if a>=0 and b>a else "")
PYX
}
check_unit_list() { # $1 file
  local seg n; seg="$(unit_list "$1")"
  [ -n "$seg" ] || { echo "BLIND: UNIT-class condition list not extracted from $1"; fail=2; return; }
  n="$(printf '%s' "$seg" | grep -oE '\((i|ii|iii|iv|v|vi|vii|viii)\)' | sort -u | tr '\n' ' ')"
  [ "$n" = "(i) (ii) (iii) (iv) " ] || { echo "FAIL $1: UNIT-class conditions are [$n], want exactly (i) (ii) (iii) (iv)"; [ $fail -eq 0 ] && fail=1; }
  if printf '%s' "$seg" | grep -qiE 'launched|harness|lifetime|network scope|started by|who started|ephemeral|loopback|localhost|127\.0\.0\.1|container|throwaway|scratch|test dir|bridge|socket|reached on|runs in|listen|bound|address|\bport\b'; then
    echo "FAIL $1: a UNIT-class condition keys on launcher, location, network scope, container kind or lifetime"; [ $fail -eq 0 ] && fail=1
  fi
  # Exact-text pin (review r4 M-3): the four conditions must be present VERBATIM, so a reworded (iii) that
  # keys on an incidental property (loopback, throwaway container, test directory) cannot slip past the word list.
  local p
  for p in "${UNIT_EXACT[@]}"; do
    printf '%s' "$seg" | grep -qF -- "$p" || { echo "FAIL $1: UNIT-class condition text altered or missing: $p"; [ $fail -eq 0 ] && fail=1; }
  done
}
for c in $CARRIERS; do check_unit_list "$c"; done
# Control needle: carriers carry the anchor heading; a planted forbidden phrase is detected.
for c in $CARRIERS; do grep -q '11\.4\.289' "$ROOT/$c" || { echo "BLIND: no 11.4.289 in $c"; fail=2; }; done
tmp="$(mktemp)"; printf '%s\n' "${FORBID[0]}" >"$tmp"
grep -qF -- "${FORBID[0]}" "$tmp" || { echo "BLIND: planted needle not found"; fail=2; }
rm -f -- "$tmp"
[ $fail -eq 0 ] && echo "PASS 289(D) not over-broad (carriers: $(echo $CARRIERS | wc -w), others: $(echo $OTHERS | wc -w))"
exit $fail
