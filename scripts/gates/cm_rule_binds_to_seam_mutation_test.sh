#!/bin/sh
# cm_rule_binds_to_seam_mutation_test.sh — §1.1 paired mutation for
# CM-RULE-BINDS-TO-SEAM.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves each of the gate's three named assertions is LOAD-BEARING: mutate the
# condition the assertion depends on, and THAT assertion's verdict must flip.
# A gate whose mutation does not flip it is decoration; a §1.1 pair that flips
# a NEIGHBOURING assertion instead of its named one proves nothing about the
# assertion it claims to cover.
#
# That second failure mode is not hypothetical — it was found on this feature
# (FINDINGS.md F-002-02: a declared mutation renamed only a REASON TOKEN while
# the refusal MECHANISM survived, so the mutation's declared target still
# passed). Every case below therefore asserts BOTH the flipped exit code AND
# the specific closed-set refusal reason, so a flip caused by a different
# check cannot be mistaken for the named one.
#
# ── Cases ────────────────────────────────────────────────────────────────────
#   M1  FR-011 — a rule row with an EMPTY seam field.
#                Clean: ALLOW.  Mutated: REFUSE + `rule_NAMES_NO_SEAM`-class
#                refusal naming the empty seam.
#   M2  FR-018 — a duplicate (seam-id, gate-token) row on a newly declared
#                anchor.
#                Clean: ALLOW.  Mutated: REFUSE + `rule_IS_RESTATEMENT`
#                NAMING the covering rule.
#   M3  FR-010 — the no-seam COUNT bumped upward past the recorded ceiling.
#                Clean: ALLOW.  Mutated: FAIL + `FR-010 ratchet violated`.
#                Both directions of the comparison are exercised: M3a raises
#                the COUNT above a fixed ceiling, M3b lowers the CEILING below
#                a fixed count. If either direction did not flip, the
#                comparison would be hardcoded on one side.
#   M4  SOURCE — the FR-018 pair-collision check is deleted from an
#                OUT-OF-REPO COPY of the gate. M2's fixture must then STOP
#                refusing. This is the anti-tautology proof: it shows M2's
#                flip comes from the gate's own code, not from an unrelated
#                check that happens to fire on the same fixture.
#   NEG NEGATIVE CONTROL — a correctly bound new rule MUST pass, so the
#                mechanism cannot become a refuse-everything engine
#                (§11.4.201(1): a false-positive refusal is a FAIL-bluff of
#                the same severity as a false pass).
#
# ── §11.4.84 working-tree quiescence ─────────────────────────────────────────
# NOTHING in the repository is mutated. Data mutations are applied to fixture
# files inside a mktemp dir; the one SOURCE mutation (M4) is applied to a COPY
# of the gate placed OUTSIDE the repository. The real gate is checksummed
# before and after and the equality is asserted, so this test cannot leave
# mutation residue behind.
#
# ── Usage / Exit codes ───────────────────────────────────────────────────────
#   cm_rule_binds_to_seam_mutation_test.sh
#     0 — every mutation flipped its NAMED assertion and the negative control
#         passed; the real gate is byte-identical to its pre-run state.
#     1 — a mutation did not flip, flipped the wrong assertion, the negative
#         control fired, or the gate file changed.
#     2 — the harness could not run (gate missing, mktemp failed, git absent).
#
# Classification: universal (§11.4.17).

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE="$SELF_DIR/cm_rule_binds_to_seam.sh"
[ -x "$GATE" ] || { echo "REFUSE: gate not executable: $GATE"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "REFUSE: git absent — the gate needs it to resolve --base"; exit 2; }

TMP=$(mktemp -d 2>/dev/null) || { echo "REFUSE: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
TAB=$(printf '\t')
GIT="git -c user.email=mut@invalid -c user.name=mut -c commit.gpgsign=false -c init.defaultBranch=main"

# Checksum the real gate BEFORE anything runs (§11.4.84).
sum_before=$(cksum < "$GATE")

pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }

sgates="$TMP/gates"; mkdir -p "$sgates"
for t in CM-STUB-ALPHA CM-STUB-BETA; do
    f=$(printf '%s' "$t" | tr 'A-Z-' 'a-z_')
    printf '#!/bin/sh\nexit 0\n' > "$sgates/${f}.sh"; chmod +x "$sgates/${f}.sh"
done
printf '420\n' > "$sgates/base420.txt"
printf '0\n'   > "$sgates/base0.txt"

mk_repo() {
    _r="$TMP/$1"; rm -rf "$_r"; mkdir -p "$_r"
    ( cd "$_r" && $GIT init -q . && printf '### \302\2478.1 — base rule\n' > C.md \
      && $GIT add C.md && $GIT commit -qm base ) >/dev/null 2>&1
    printf '%s' "$_r"
}
# NOTE: the loop variable is `_row`, NOT `r`. Shell functions share the
# caller's variable scope, so a bare `r` here silently CLOBBERS the outer
# repo-path variable and every subsequent case runs against a corpus path
# built from a registry row. Observed during authoring; the harness caught it
# because the clean cases stopped returning ALLOW.
mk_reg() { _dst=$1; shift; printf '# fixture\n' > "$_dst"; for _row in "$@"; do printf '%s\n' "$_row" >> "$_dst"; done; }

# run <gate> <repo> <reg> <baseline> -> prints output, sets RC
RC=0
run() { OUT=$("$1" --corpus "$2/C.md" --bindings "$3" --gates-dir "$sgates" --baseline "$4" 2>&1); RC=$?; }

echo "── M1  FR-011: rule row with an EMPTY seam field ──────────────────────"
r=$(mk_repo m1)
printf '### \302\2478.2 — new rule\n' >> "$r/C.md"
mk_reg "$TMP/m1_clean.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.2${TAB}pre-build${TAB}CM-STUB-BETA"
mk_reg "$TMP/m1_mut.tsv"   "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.2${TAB}${TAB}CM-STUB-ALPHA"
run "$GATE" "$r" "$TMP/m1_clean.tsv" "$sgates/base420.txt"
[ "$RC" -eq 0 ] && ok "M1 clean  -> ALLOW (rc=0)" || bad "M1 clean  -> expected rc=0, got rc=$RC"
run "$GATE" "$r" "$TMP/m1_mut.tsv" "$sgates/base420.txt"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "seam id ''"; then
    ok "M1 mutant -> REFUSE (rc=2) naming the EMPTY seam — FR-011 assertion flipped"
else
    bad "M1 mutant -> expected rc=2 naming the empty seam, got rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi

echo "── M2  FR-018: duplicate (seam-id, gate-token) on a new anchor ────────"
r=$(mk_repo m2)
printf '### \302\2478.7 — new rule\n' >> "$r/C.md"
mk_reg "$TMP/m2_clean.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.7${TAB}pre-build${TAB}CM-STUB-BETA"
mk_reg "$TMP/m2_mut.tsv"   "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.7${TAB}pre-build${TAB}CM-STUB-ALPHA"
run "$GATE" "$r" "$TMP/m2_clean.tsv" "$sgates/base420.txt"
[ "$RC" -eq 0 ] && ok "M2 clean  -> ALLOW (rc=0, distinct pairs)" || bad "M2 clean  -> expected rc=0, got rc=$RC"
run "$GATE" "$r" "$TMP/m2_mut.tsv" "$sgates/base420.txt"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'rule_IS_RESTATEMENT' && printf '%s' "$OUT" | grep -q 'covering rule = 8\.1'; then
    ok "M2 mutant -> REFUSE (rc=2) rule_IS_RESTATEMENT NAMING coverer 8.1 — FR-018 assertion flipped"
else
    bad "M2 mutant -> expected rc=2 + rule_IS_RESTATEMENT + named coverer, got rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi

echo "── M3  FR-010: the ratchet comparison, both directions ────────────────"
# The extra anchors are committed into the BASE so they are NOT "newly
# added". That isolates FR-010: with no new anchor, FR-011 cannot fire, so a
# flip here can only come from the ratchet comparison itself. (Measured
# during authoring: with 8.3/8.4 uncommitted, FR-011 refused first and
# masked the ratchet result — the mutation would have "flipped" on a
# neighbouring assertion, the F-002-02 failure mode.)
r=$(mk_repo m3)
printf '### \302\2478.3 — unbound A\n### \302\2478.4 — unbound B\n' >> "$r/C.md"
( cd "$r" && $GIT add C.md && $GIT commit -qm anchors ) >/dev/null 2>&1
# Every anchor bound -> no-seam count 0.
mk_reg "$TMP/m3_clean.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.3${TAB}pre-build${TAB}CM-STUB-BETA" "8.4${TAB}commit${TAB}CM-STUB-ALPHA"
# M3a: COUNT bumped upward (bindings withdrawn) against a ceiling of 0.
mk_reg "$TMP/m3_mut.tsv"   "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
run "$GATE" "$r" "$TMP/m3_clean.tsv" "$sgates/base0.txt"
[ "$RC" -eq 0 ] && ok "M3 clean  -> ALLOW (rc=0, no-seam count 0 <= ceiling 0)" || bad "M3 clean  -> expected rc=0, got rc=$RC"
run "$GATE" "$r" "$TMP/m3_mut.tsv" "$sgates/base0.txt"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'FR-010 ratchet violated'; then
    ok "M3a mutant(count up) -> FAIL (rc=1) 'FR-010 ratchet violated' — FR-010 assertion flipped"
else
    bad "M3a mutant -> expected rc=1 + ratchet-violated, got rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi
# M3b: CEILING lowered below a fixed count — proves the OTHER side of the
# comparison is read, not hardcoded.
printf '1\n' > "$TMP/base1.txt"
mk_reg "$TMP/m3b.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA"
run "$GATE" "$r" "$TMP/m3b.tsv" "$TMP/base1.txt"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'FR-010 ratchet violated'; then
    ok "M3b mutant(ceiling down) -> FAIL (rc=1) — the ceiling operand is read, not hardcoded"
else
    bad "M3b mutant -> expected rc=1 + ratchet-violated, got rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi

echo "── M4  SOURCE: delete the FR-018 pair check from an OUT-OF-REPO copy ──"
cp "$GATE" "$TMP/copy_gate.sh"; chmod +x "$TMP/copy_gate.sh"
# Neutralise ONLY the pair-collision lookup. The FR-011 row-presence check and
# every other assertion are untouched, so a flip here can only come from FR-018.
sed -i 's/^\( *\)cover=\$(awk -F"\$TAB".*$/\1cover=""/' "$TMP/copy_gate.sh"
if grep -q 'cover=""' "$TMP/copy_gate.sh" && ! grep -q 'cover=$(awk' "$TMP/copy_gate.sh"; then
    ok "M4 mutation applied to the COPY (pair lookup neutralised; repo untouched)"
else
    bad "M4 mutation did NOT apply — the case below would be vacuous"
fi
sh -n "$TMP/copy_gate.sh" 2>/dev/null && ok "M4 mutated copy still parses (the flip is behavioural, not a syntax error)" \
    || bad "M4 mutated copy does not parse — a parse error would flip the gate for the WRONG reason"
# A repo carrying the newly declared 8.7, so the FR-018 path is the one
# exercised against the mutated copy.
r2=$(mk_repo m2b); printf '### \302\2478.7 — new rule\n' >> "$r2/C.md"
run "$TMP/copy_gate.sh" "$r2" "$TMP/m2_mut.tsv" "$sgates/base420.txt"
if [ "$RC" -eq 0 ]; then
    ok "M4 mutant -> the FR-018 refusal DISAPPEARS (rc=0) — M2's flip is caused by the gate's own pair check, not a neighbour"
else
    bad "M4 mutant -> expected rc=0 after neutralising the pair check, got rc=$RC"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi

echo "── NEG  negative control: a correctly bound new rule MUST pass ────────"
r=$(mk_repo neg)
printf '### \302\2478.8 — correctly bound new rule\n' >> "$r/C.md"
mk_reg "$TMP/neg.tsv" "8.1${TAB}pre-build${TAB}CM-STUB-ALPHA" "8.8${TAB}release-tag${TAB}CM-STUB-BETA"
run "$GATE" "$r" "$TMP/neg.tsv" "$sgates/base420.txt"
if [ "$RC" -eq 0 ]; then
    ok "NEG -> ALLOW (rc=0): the gate is not a refuse-everything engine"
else
    bad "NEG -> expected rc=0, got rc=$RC (FALSE-POSITIVE REFUSAL — §11.4.201(1))"; printf '%s\n' "$OUT" | sed 's/^/      | /'
fi

echo "── §11.4.84 residue check ─────────────────────────────────────────────"
sum_after=$(cksum < "$GATE")
if [ "$sum_before" = "$sum_after" ]; then
    ok "the real gate is byte-identical before/after (cksum $sum_after) — no mutation residue"
else
    bad "the real gate CHANGED during this run (before=$sum_before after=$sum_after)"
fi

printf '\ncm_rule_binds_to_seam_mutation_test.sh: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
