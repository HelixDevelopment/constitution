#!/bin/sh
# Paired §1.1 mutation for CM-GIT-HOOKS-INSTALLED.
#
# THE MUTATION (one named assertion, not a neighbour):
#   swap the gate's INDEPENDENT two-derivation declared set — D1 (the consumer
#   hook map) cross-checked against D2 (a canonical-filtered scan of the source
#   roots) — for the installer's own `HOOKS=` literal, the self-referential list
#   that is simultaneously its declared set and its install set.
#
# WHAT IT PROVES:
#   the gate stops reporting the missing declared hook, reproducing exactly the
#   D-6 blindness measured on the tree: `--verify` returning `ok=4 missing=0`
#   rc=0 while `post-merge` was absent. If the mutated gate still fired, the
#   two-derivation logic would not be what catches the omission and the gate's
#   GREEN would prove nothing.
#
# NEGATIVE CONTROL (§11.4.201(1)):
#   the UNMUTATED gate on a fixture where every declared hook is installed MUST
#   pass. A mutation test that only shows a gate can be made silent, without
#   showing it is otherwise quiet on a clean tree, cannot distinguish a real
#   detector from a gate that fires on everything.
#
# §11.4.84: the mutation is applied to a COPY in a temp dir outside the repo.
# The in-repo gate is never edited; its checksum is compared before and after.
#
# Exit: 0 all cases held; 1 a case failed.

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="${HERE}/cm_git_hooks_installed.sh"
FX="${HERE}/fixtures/cm_git_hooks_installed"
T_TRUE="${FX}/golden_true_missing_declared"
T_FALSE="${FX}/golden_false_nonhook_decoys"

rc_all=0
note() { printf '%s\n' "$*"; }
bad()  { printf 'MUTATION-TEST FAIL: %s\n' "$*"; rc_all=1; }

[ -r "$GATE" ] || { bad "gate absent: $GATE"; exit 1; }
[ -d "$T_TRUE" ] || { bad "fixture absent: $T_TRUE"; exit 1; }

SUM_BEFORE=$(sha256sum "$GATE" | cut -d' ' -f1)

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_git_hooks_mut.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

run_true()  { sh "$1" --repo "$T_TRUE"  --map "$T_TRUE/hooks.tsv"  --hook-dir "$T_TRUE/live_hooks"  --source-root "$T_TRUE/src_a"  --source-root "$T_TRUE/src_b"  2>&1; }
run_false() { sh "$1" --repo "$T_FALSE" --map "$T_FALSE/hooks.tsv" --hook-dir "$T_FALSE/live_hooks" --source-root "$T_FALSE/src_a" --source-root "$T_FALSE/src_b" 2>&1; }

# ---------------------------------------------------------------------------
# Case 0 — baseline: the UNMUTATED gate fires on the golden-true fixture.
# Establishes that the flip in Case 1 is caused by the mutation and not by a
# gate that was silent to begin with.
# ---------------------------------------------------------------------------
out=$(run_true "$GATE"); r=$?
if [ "$r" = 1 ] && printf '%s' "$out" | grep -q 'MISSING post-merge'; then
    note "ok   case0 baseline    unmutated gate FAILs(1) naming post-merge"
else
    bad "case0 baseline: expected FAIL(1) naming post-merge, got rc=${r}"
    printf '%s\n' "$out"
fi

# ---------------------------------------------------------------------------
# Case 1 — THE MUTATION: declared set := installer's `HOOKS=` literal.
# ---------------------------------------------------------------------------
cp "$GATE" "$TMP/mutated.sh"
ANCHOR='    g_d2=$(printf '"'"'%s'"'"' "$g_d2" | grep -v '"'"'^$'"'"' | sort -u)'
grep -qF "$ANCHOR" "$TMP/mutated.sh" || { bad "case1: mutation anchor not found — refusing to mutate blind"; exit 1; }

awk -v anchor="$ANCHOR" '
{ print }
$0 == anchor && !done {
    print "    # [MUTATION §1.1] declared set := the installer'"'"'s own HOOKS= literal,"
    print "    # the self-referential list that is both declared set and install set."
    print "    g_d1=$(printf '"'"'%s\\n'"'"' pre-commit pre-push post-commit commit-msg | sort -u)"
    print "    g_d2=\"$g_d1\""
    done=1
}
' "$TMP/mutated.sh" > "$TMP/mutated.new" && mv "$TMP/mutated.new" "$TMP/mutated.sh"
chmod +x "$TMP/mutated.sh"

if ! sh -n "$TMP/mutated.sh"; then
    bad "case1: mutated gate does not parse — the mutation must change behaviour, not break syntax"
else
    out=$(run_true "$TMP/mutated.sh"); r=$?
    if printf '%s' "$out" | grep -q 'MISSING post-merge'; then
        bad "case1: MUTATION SURVIVED — gate still names post-merge, so the two-derivation"
        bad "       declared set is NOT what catches the omission and its GREEN proves nothing"
        printf '%s\n' "$out"
    elif [ "$r" != 0 ]; then
        bad "case1: mutated gate stopped naming post-merge but exited ${r}, not 0 —"
        bad "       the flip must be the D-6 blindness, not some other refusal"
        printf '%s\n' "$out"
    else
        note "ok   case1 MUTATION    installer-literal declared set -> gate goes SILENT (rc=0),"
        note "                       reproducing the measured omission blindness"
    fi
fi

# ---------------------------------------------------------------------------
# Case 2 — NEGATIVE CONTROL: clean fixture, unmutated gate, MUST pass.
# ---------------------------------------------------------------------------
out=$(run_false "$GATE"); r=$?
if [ "$r" = 0 ]; then
    note "ok   case2 neg-control  every declared hook installed -> PASS(0), no false refusal"
else
    bad "case2 neg-control: clean fixture must PASS(0), got rc=${r} — false-positive refusal"
    printf '%s\n' "$out"
fi

# ---------------------------------------------------------------------------
# §11.4.84 restoration proof
# ---------------------------------------------------------------------------
SUM_AFTER=$(sha256sum "$GATE" | cut -d' ' -f1)
if [ "$SUM_BEFORE" = "$SUM_AFTER" ]; then
    note "ok   quiescence      in-repo gate unchanged (sha256 ${SUM_BEFORE})"
else
    bad "in-repo gate MUTATED IN PLACE: ${SUM_BEFORE} -> ${SUM_AFTER}"
fi

[ "$rc_all" = 0 ] && note "MUTATION-TEST GREEN (baseline fires / mutation silences / neg-control quiet / repo clean)"
exit $rc_all
