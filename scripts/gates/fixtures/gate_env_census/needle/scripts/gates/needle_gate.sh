#!/usr/bin/env bash
# Control-needle input for scripts/gates/cm_gate_env_reads_allowlisted.sh (11.4.273). NOT a gate; never executed.
# One read of every form the census must see (positive control) plus two negatives.
HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/needle_lib.sh"
. "$HERE/../lib/needle_uplib.sh"
ROOTV="$(CDPATH= cd -- "$HERE/../.." && pwd)"
. "$ROOTV/scripts/lib/needle_rootlib.sh"
NLIB="$HERE/lib/needle_varlib.sh"
. "$NLIB"
echo source nothing_here_zz   # `source` as an ARGUMENT is not a source statement (negative control)
jq -e . "$HERE/x.json"        # `.` as an ARGUMENT is not a source statement (negative control)
echo "$NEEDLE_PLAIN ${NEEDLE_BRACE} ${NEEDLE_DEFAULT:-d} ${NEEDLE_ALT:+x} ${#NEEDLE_LEN}"
[ -n "$NEEDLE_TEST" ] && x="$(echo "$NEEDLE_CMDSUB")"
NEEDLE_SELFDEFAULT="${NEEDLE_SELFDEFAULT:-0}"
printenv NEEDLE_PRINTENV >/dev/null
python3 -c 'import os; print(os.environ.get("NEEDLE_PYENV"))'
awk 'BEGIN{print ENVIRON["NEEDLE_AWKENV"]}'
cm_gate_env_set out NEEDLE_GUARDED "" value
NEEDLE_ASSIGNED=1
echo "$NEEDLE_ASSIGNED $out $x"
echo 'NEEDLE_FABRICATED_ZQX is only text in single quotes'
# --- review round 8 F3 forms (every one a positive) ---
export NEEDLE_BAREEXP
echo "$NEEDLE_BAREEXP"
declare -x NEEDLE_DECLX
echo "$NEEDLE_DECLX"
readonly NEEDLE_RDONLY
echo "$NEEDLE_RDONLY"
NEEDLE_PREFIX=1 true
echo "$NEEDLE_PREFIX"
perl -e 'print $ENV{NEEDLE_PERL}'
python3 -c 'from os import environ as E; print(E["NEEDLE_PYALIAS"])'
python3 -c 'import os; d = dict(os.environ)'
env | grep ^NEEDLE_ENVGREP=
jq -n 'env.NEEDLE_JQENV'
jq -n '$ENV.NEEDLE_JQENV2'
jq -n 'env | keys'
node -e 'console.log(process.env.NEEDLE_NODE)'
node -e 'console.log(Object.keys(process.env))'
declare -p NEEDLE_DECLP
declare -p | grep x
eval "$NEEDLE_EVALCMD"
# --- negatives: a value-bearing export and an assigned-then-read name are not ambient ---
export NEEDLE_EXPVAL=1
echo "$NEEDLE_EXPVAL"
