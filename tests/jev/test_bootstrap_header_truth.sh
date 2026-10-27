#!/usr/bin/env bash
# test_bootstrap_header_truth.sh — the header of scripts/jev/bootstrap.sh must tell the truth about
# what the default run does and which exit codes exist (review round 2, F2):
#   H1  the header does not claim the default run touches NO network while JEV_HOSTED_PROBE defaults to 1
#   H2  the header documents the hosted-probe exception and its off switch
#   H3  the header lists every exit code of §11.4.279(G): 0 1 2 3 4 5
#   H4  every `exit N` / documented code used by the script body is a listed code
# BOOTSTRAP_UNDER_TEST overrides the script path (used to observe RED on the pre-fix file).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${BOOTSTRAP_UNDER_TEST:-$HERE/../../scripts/jev/bootstrap.sh}"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
[ -r "$S" ] || { echo "FATAL: cannot read $S" >&2; exit 2; }
HDR="$(sed -n '1,/^set -euo/p' "$S")"
[ -n "$HDR" ] || { echo "FATAL: empty header" >&2; exit 2; }
# control needle: the header extraction can see a known header line
printf '%s\n' "$HDR" | grep -q 'Exit codes' && ok "control needle: header extraction sees the exit-code section" || bad "control needle: header extraction is blind"

# H1: the false claim (any sentence saying the default run touches no network) is gone
if printf '%s\n' "$HDR" | tr '\n' ' ' | grep -Eqi 'touches NO network'; then bad "H1 header claims the default run touches NO network"; else ok "H1 no 'touches NO network' claim"; fi
# H2
if printf '%s\n' "$HDR" | tr '\n' ' ' | grep -q 'JEV_HOSTED_PROBE'; then ok "H2 header names JEV_HOSTED_PROBE"; else bad "H2 header does not mention JEV_HOSTED_PROBE"; fi
if printf '%s\n' "$HDR" | tr '\n' ' ' | grep -Eq 'JEV_HOSTED_PROBE=0'; then ok "H2 header names the off switch"; else bad "H2 header does not name the off switch"; fi
# H3
for c in 0 1 2 3 4 5; do
  if printf '%s\n' "$HDR" | grep -Eq "^#[[:space:]]+$c[[:space:]]"; then ok "H3 exit code $c documented"; else bad "H3 exit code $c not documented in the header"; fi
done
# H4: every literal exit/return status in the body is documented
used="$(grep -Eo '\bexit [0-9]+' "$S" | awk '{print $2}' | sort -u | tr '\n' ' ')"
for c in $used; do
  case "$c" in 0|1|2|3|4|5) ok "H4 body uses documented exit $c" ;; *) bad "H4 body uses undocumented exit $c" ;; esac
done
echo "# test_bootstrap_header_truth.sh: pass=$pass fail=$fail skip=0"
[ "$fail" -eq 0 ]
