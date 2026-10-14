#!/usr/bin/env bash
# cm_core_scripts_project_literal_free_mutation_test.sh -- regression guard for the constitution-side half of
# CM-OWNED-SUBMODULE-DECOUPLING (§11.4.28(B)/§11.4.35) and CM-CRED-SCAN-LIB-SELF-VALIDATED invariant 4.
# Constitution logic is consumed by every project, so no consumer project literal may appear in it.
# The consumer's pre-build gates grep the same classes; this test lets the constitution prove it itself.
#
# RED/GREEN: RED on a tree whose scripts carry a literal; GREEN once the comments are genericised.
# Paired §1.1 mutation: each case re-injects one literal (built from fragments so THIS file never matches itself,
# and the file name ends _mutation_test.sh which the consumer gates exclude) and requires the scan to FAIL.
# Control needle (§11.4.273): a known-present literal MUST be found by the same scan before a zero is believed.
# Usage: cm_core_scripts_project_literal_free_mutation_test.sh [--root DIR]   Exit 0 all PASS, 1 any FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ "${1:-}" = "--root" ] && [ -n "${2:-}" ] && ROOT="$2"
# literal classes, assembled from fragments (this file must not contain a contiguous literal)
O1="ATMOS""phere1234321"
RK="RK""3588"
A1="\"AT""M-[0-9]+|SP""K-[0-9]+\""
CRED_RE="at""mosphere|rk""3588|rock""chip|orange""pi|998fd36615e99484|66ff9c4f51f00ee7"
LEAK_RE="com\\.at""mosphere|RK""3588|998fd36615e99484|66ff9c4f51f00ee7|\"AT""M-\\[0-9|\"SP""K-\\[0-9"
FILES="scripts/hooks/credential_scan_lib.sh scripts/fastcycle/tokens/transcript_ingest.py scripts/fastcycle/gates/lib/io_trace_build_map.py"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
scan() { # $1 root ; prints hits for the three files; rc0 always
  local r="$1" f
  for f in $FILES; do
    [ -f "$r/$f" ] || { echo "BLIND:$f"; continue; }
    case "$f" in
      *credential_scan_lib.sh) grep -nEi "$CRED_RE" "$r/$f" | sed "s|^|$f:|" ;;
    esac
    grep -nE "$LEAK_RE" "$r/$f" | grep -viE 'hardcoded' | sed "s|^|$f:|"
  done
}
# G0 control needle: a scratch copy with a known literal injected MUST be found
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ctl" && for f in $FILES; do mkdir -p "$T/ctl/$(dirname "$f")"; cp "$ROOT/$f" "$T/ctl/$f" 2>/dev/null; done
printf '# %s here\n' "$O1" >> "$T/ctl/scripts/hooks/credential_scan_lib.sh"
ctl="$(scan "$T/ctl")"   # capture first: `scan | grep -q` under pipefail is a SIGPIPE false-negative
grep -q 'credential_scan_lib.sh:' <<<"$ctl" && ok "G0 control needle: injected org literal is seen by the scan" || bad "G0 control needle NOT seen -- scan is blind"
# G1..G3 golden-true: the real tree is literal-free
hits="$(scan "$ROOT")"
blind="$(grep '^BLIND' <<<"$hits")"
if [ -n "$blind" ]; then bad "G1 BLIND: a scanned file is missing: ${blind%%$'\n'*}"
else
  for f in $FILES; do
    fh="$(grep "^$f:" <<<"$hits")"
    if [ -n "$fh" ]; then bad "G* $f carries a project literal: ${fh%%$'\n'*}"; else ok "G* $f is project-literal-free"; fi
  done
fi
# M1..M3 mutations: re-inject one literal per file into a copy; the scan MUST fail on it
i=0
for spec in "scripts/hooks/credential_scan_lib.sh|# ssh://git@github.com/$O1/repo.git" \
            "scripts/fastcycle/tokens/transcript_ingest.py|#      $A1" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|# physical $RK board"; do
  i=$((i+1)); f="${spec%%|*}"; line="${spec#*|}"
  rm -rf "$T/m$i"; mkdir -p "$T/m$i/$(dirname "$f")"; cp "$ROOT/$f" "$T/m$i/$f"
  for g in $FILES; do [ "$g" = "$f" ] || { mkdir -p "$T/m$i/$(dirname "$g")"; cp "$ROOT/$g" "$T/m$i/$g"; }; done
  printf '%s\n' "$line" >> "$T/m$i/$f"
  mh="$(scan "$T/m$i")"
  grep -q "^$f:" <<<"$mh" && ok "M$i mutation caught in $f" || bad "M$i mutation SURVIVED in $f"
done
echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "CORE-SCRIPTS-LITERAL-FREE: PASS"; exit 0; }
echo "CORE-SCRIPTS-LITERAL-FREE: FAIL"; exit 1
