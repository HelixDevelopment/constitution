#!/usr/bin/env bash
# cm_core_scripts_project_literal_free_mutation_test.sh -- regression guard for the constitution-side half of
# CM-OWNED-SUBMODULE-DECOUPLING (§11.4.28(B)/§11.4.35) and CM-CRED-SCAN-LIB-SELF-VALIDATED invariant 4.
# Constitution logic is consumed by every project, so no consumer project literal may appear in it.
#
# Scope: the GUARD SET below = every constitution script the remedy batch atm-prebuild-remedy-const genericised.
# It is not a whole-tree sweep (the wider constitution tree still carries members of the class; that backlog is
# the consumer's CM-OWNED-SUBMODULE-DECOUPLING gate's, §11.4.6 honest boundary).
#
# The literal class (WIDE_RE, matched case-INSENSITIVELY on every line of every guard-set file):
#   project / vendor / SoC names, in any case and inside any path (`device/<vendor>/<soc>/...`);
#   the two reference-device serials; consumer-only paths and package ids;
#   ticket ids and ticket-id regexes in ANY quoting (double, single or none) -- the consumer's own regex only
#   sees the double-quoted form, which is why the single-quoted form (round-2 reviewer mutant MX6) and the
#   lower-case SoC name (MX6b) used to survive.
# WIDE_RE is a strict superset of the consumer's CM-OWNED-SUBMODULE-DECOUPLING regex and of the CSLV
# invariant-4 regex; check S1 proves it on one needle per consumer-regex class before any zero is believed.
#
# Paired §1.1 mutation: each M case re-injects one literal into a copy (built from fragments so THIS file never
# matches itself; the name ends _mutation_test.sh, which the consumer gates exclude) and requires the scan to FAIL.
# Control needles (§11.4.273): G0 (a known-present literal IS seen) and N0 (a genericised look-alike is NOT).
# Wired: run by scripts/hooks/test_credential_scan_lib.sh (the suite the consumer's CSLV gate invariant (5) runs).
# Usage: cm_core_scripts_project_literal_free_mutation_test.sh [--root DIR]   Exit 0 all PASS, 1 any FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ "${1:-}" = "--root" ] && [ -n "${2:-}" ] && ROOT="$2"
# literal fragments (this file must not contain a contiguous literal of the class)
P1="at""mos""phere"; O1="ATM""OS""phere1234321"; S1N="rk""3588"; V1="rock""chip"; RK="RK""3588"
SER1="998fd366""15e99484"; SER2="66ff9c4f""51f00ee7"; T1="AT""M"; T2="SP""K"; T3="BO""B"
WIDE_RE="${P1}|${S1N}|${V1}|orange ?pi|${SER1}|${SER2}|(${T1}|${T2}|${T3})-(\\\\?\\[0-9|[0-9])|/mnt/track[0-9]|kino""poisk|ok\\.and""roid|kernel-5\\.10"
FILES="scripts/hooks/credential_scan_lib.sh scripts/fastcycle/tokens/transcript_ingest.py scripts/fastcycle/gates/lib/io_trace_build_map.py scripts/gates/lib/covenant_propagation_engine.sh scripts/gates/cm_version_increment_on_deploy_mutation_test.sh"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
scan() { # $1 root ; prints "<file>:<n>:<line>" hits (or BLIND:<file>); rc0 always
  local r="$1" f
  for f in $FILES; do
    [ -f "$r/$f" ] || { echo "BLIND:$f"; continue; }
    grep -niE "$WIDE_RE" "$r/$f" | sed "s|^|$f:|"
  done
}
copy_set() { # $1 dest
  local g; for g in $FILES; do mkdir -p "$1/$(dirname "$g")"; cp "$ROOT/$g" "$1/$g" 2>/dev/null; done
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# S1: superset proof -- one needle per class of the consumer regexes must be matched by WIDE_RE
sup_ok=1
for n in "com.${P1}.app" "${RK} board" "${SER1}" "${SER2}" "\"${T1}-[0-9]+\"" "\"${T2}-[0-9]+\"" "/mnt/track1/${P1}" "${V1}" "orange""pi"; do
  printf '%s\n' "$n" | grep -qiE "$WIDE_RE" || { sup_ok=0; echo "  S1 needle not matched: $n"; }
done
[ "$sup_ok" -eq 1 ] && ok "S1 WIDE_RE matches every consumer-regex needle (superset)" || bad "S1 WIDE_RE is NOT a superset of the consumer regexes"
# G0 control needle: a scratch copy with a known literal injected MUST be found
copy_set "$T/ctl"
printf '# %s here\n' "$O1" >> "$T/ctl/scripts/hooks/credential_scan_lib.sh"
ctl="$(scan "$T/ctl")"   # capture first: `scan | grep -q` under pipefail is a SIGPIPE false-negative
grep -q 'credential_scan_lib.sh:' <<<"$ctl" && ok "G0 control needle: injected org literal is seen by the scan" || bad "G0 control needle NOT seen -- scan is blind"
# N0 negative control: a genericised look-alike (example project / example prefix) must NOT be caught
copy_set "$T/neg"
printf '# items like item=MYP-12 in a myproject checkout; <vendor>/<soc> board\n' >> "$T/neg/scripts/fastcycle/tokens/transcript_ingest.py"
neg_n="$(scan "$T/neg" | grep -c '^scripts/fastcycle/tokens/transcript_ingest.py:')"
real_n="$(scan "$ROOT" | grep -c '^scripts/fastcycle/tokens/transcript_ingest.py:')"
[ "$neg_n" = "$real_n" ] && ok "N0 negative control: genericised look-alike is not matched (hits $neg_n == $real_n)" || bad "N0 negative control matched a genericised line -- over-broad scan (hits $neg_n != $real_n)"
# G*: the real tree is literal-free
hits="$(scan "$ROOT")"
blind="$(grep '^BLIND' <<<"$hits")"
if [ -n "$blind" ]; then bad "G BLIND: a scanned file is missing: ${blind%%$'\n'*}"
else
  for f in $FILES; do
    fh="$(grep "^$f:" <<<"$hits")"
    if [ -n "$fh" ]; then bad "G* $f carries a project literal: ${fh%%$'\n'*}"; else ok "G* $f is project-literal-free"; fi
  done
fi
# M1..M7 mutations: re-inject one literal per case into a copy; the scan MUST fail on it
i=0
for spec in "scripts/hooks/credential_scan_lib.sh|# ssh://git@github.com/$O1/repo.git" \
            "scripts/fastcycle/tokens/transcript_ingest.py|#      \"${T1}-[0-9]+|${T2}-[0-9]+\"" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|# physical $RK board" \
            "scripts/fastcycle/tokens/transcript_ingest.py|ITEM_RE = '${T1}-[0-9]+|${T2}-[0-9]+'" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|# default device/${V1}/${S1N}/tests/" \
            "scripts/gates/lib/covenant_propagation_engine.sh|# tracked as ${T1}-989" \
            "scripts/gates/cm_version_increment_on_deploy_mutation_test.sh|# fixture ${P1}-1.2.1-dev-0.12.0"; do
  i=$((i+1)); f="${spec%%|*}"; line="${spec#*|}"
  rm -rf "$T/m$i"; copy_set "$T/m$i"
  printf '%s\n' "$line" >> "$T/m$i/$f"
  mh="$(scan "$T/m$i")"
  grep -q "^$f:" <<<"$mh" && ok "M$i mutation caught in $f" || bad "M$i mutation SURVIVED in $f"
done
echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "CORE-SCRIPTS-LITERAL-FREE: PASS"; exit 0; }
echo "CORE-SCRIPTS-LITERAL-FREE: FAIL"; exit 1
