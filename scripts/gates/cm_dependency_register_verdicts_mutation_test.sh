#!/bin/sh
# =============================================================================
# cm_dependency_register_verdicts_mutation_test.sh — paired §1.1 mutation for
# CM-DEPENDENCY-REGISTER-VERDICTS (T232).
#
# MUTATION (behavioural): collapse the description axis in dr_resolve, so a
# NAME MATCH ALONE resolves VERIFIED. This is the measured A-001 name-collision
# failure re-introduced deliberately: 2 of the 21 externally named tools carry
# a real project's name while doing an unrelated job, and a resolver that
# matches on the name admits exactly those.
#
# NAMED FLIP : DRV-A4-NAME-COLLISION-AMBIGUOUS  (PASS -> FAIL)
# SURGICAL   : DRV-A2 (closed verdict set), DRV-A3 (evidence field) and
#              DRV-A5 (exact match still VERIFIED) must all STAY PASS. A5 is
#              the interesting one: it stays green under this mutation, which
#              is precisely why A4 has to exist as a separate assertion.
# =============================================================================

set -u
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
# shellcheck disable=SC1091
. "$SELF_DIR/lib/gate_mutation_harness.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

mutate_name_only_match() {  # <copy>
    awk '
      /if \[ "\$cand_desc" = "\$DESC" \]; then/ {
          print "    if true; then                                                             # MUTATED: description axis collapsed, name match alone resolves VERIFIED"
          next
      }
      { print }
    ' "$1" > "$1.new" && mv "$1.new" "$1"
}

gm_init "$SELF_DIR/cm_dependency_register_verdicts.sh" \
        --register "$REPO/docs/requests/dependency_register.jsonl" --standalone-canon
gm_mutate_target "$SELF_DIR/lib/dependency_register.sh"
gm_pair mutate_name_only_match \
        DRV-A4-NAME-COLLISION-AMBIGUOUS \
        DRV-A2-VERDICT-CLOSED-SET DRV-A3-EVIDENCE-FIELD DRV-A5-EXACT-MATCH-VERIFIED
gm_report
exit $?
