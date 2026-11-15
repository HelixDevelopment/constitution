#!/bin/sh
# cm_unreferenced_gate_bound_or_retired_mutation_test.sh — §1.1 paired mutation
# for CM-UNREFERENCED-GATE-BOUND-OR-RETIRED.
#
# ── Cases ────────────────────────────────────────────────────────────────────
#   NEG  NEGATIVE CONTROL — a fixture set in which every gate is bound or
#        cited-retired MUST pass. Without this, a sweep that refused
#        unconditionally would score full marks on every other case.
#
#   M1   STRIP THE RETIREMENT CITATION from a removals row.
#        Clean: ALLOW. Mutated: REFUSE naming the citation.
#        This is the anti-gaming clause under test: without a CHECKED
#        citation, "retire the name" becomes a way to lower the unimplemented
#        count without doing the work — the delete-names-to-lower-the-count
#        channel §11.4.227(A) exists to close.
#
#   M2   ADD A FIXTURE GATE carrying neither a wiring record nor a
#        retirement record. Mutated: REFUSE, NAMING it.
#
#   M3   SOURCE MUTATION on an OUT-OF-REPO COPY: neutralise the citation
#        VALIDATION so any row counts as retired. M1's fixture must then STOP
#        refusing. This is the anti-tautology proof — it shows M1's flip is
#        produced by the citation check itself and not by some neighbouring
#        assertion that happens to fire on the same fixture (the FINDINGS.md
#        F-002-02 failure mode, where a mutation renamed a reason token while
#        the mechanism survived).
#
# ── §11.4.84 working-tree quiescence ─────────────────────────────────────────
# Nothing in the repository is mutated. Data mutations land in a mktemp dir;
# the source mutation is applied to a COPY placed outside the repository. The
# real gate is checksummed before and after and the equality asserted.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every mutation flipped its NAMED assertion, the negative control
#       passed, and the gate file is unchanged.
#   1 — a mutation did not flip, flipped the wrong assertion, the negative
#       control fired, or the gate file changed.
#   2 — the harness could not run.
#
# Classification: universal (§11.4.17).

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE="$SELF_DIR/cm_unreferenced_gate_bound_or_retired.sh"
[ -x "$GATE" ] || { echo "REFUSE: gate not executable: $GATE"; exit 2; }

TMP=$(mktemp -d 2>/dev/null) || { echo "REFUSE: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

sum_before=$(cksum < "$GATE")
pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s (rc=%s)\n' "$1" "$2"; printf '%s\n' "$OUT" | sed 's/^/        | /'; fail=$((fail + 1)); }

F="$TMP/fx"
CITE='git log --follow -- scripts/gates/cm_retired.sh :: 3f2a91c wired at the pre-build seam; unwired by 9d4e7b1'

# build_fixture <citation-text> [extra-unbound-gate-name]
build_fixture() {
    rm -rf "$F"; mkdir -p "$F/g" "$F/root/seams"
    printf '#!/bin/sh\n# seam\nseam_body=1\nbash "$D/cm_wired.sh"\n' > "$F/root/seams/pb.sh"
    printf '# hdr\npre-build\tseams/pb.sh\n' > "$F/g/seams.tsv"
    printf '# hdr\n' > "$F/g/dispatch.tsv"
    printf '# hdr\n' > "$F/g/def.tsv"
    printf '# hdr\nCM-RETIRED\trepealed\t%s\tsuperseded by the engine check\n' "$1" > "$F/g/rem.tsv"
    for n in cm_wired.sh cm_retired.sh; do printf '#!/bin/sh\nexit 0\n' > "$F/g/$n"; chmod +x "$F/g/$n"; done
    if [ -n "${2:-}" ]; then printf '#!/bin/sh\nexit 0\n' > "$F/g/$2"; chmod +x "$F/g/$2"; fi
}
sweep() {
    OUT=$("$1" --root "$F/root" --gates-dir "$F/g" --seams "$F/g/seams.tsv" \
          --dispatch "$F/g/dispatch.tsv" --deferrals "$F/g/def.tsv" \
          --removals "$F/g/rem.tsv" --no-write 2>&1); RC=$?
}

echo "── NEG  negative control: every gate bound or cited-retired ───────────"
build_fixture "$CITE"
sweep "$GATE"
[ "$RC" -eq 0 ] && ok "NEG -> ALLOW (rc=0): the sweep is not a refuse-everything engine" \
                || bad "NEG -> expected rc=0" "$RC"

echo "── M1  strip the retirement citation ──────────────────────────────────"
build_fixture ""
sweep "$GATE"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'citation' && printf '%s' "$OUT" | grep -q 'cm_retired.sh'; then
    ok "M1 mutant -> REFUSE (rc=2) naming cm_retired.sh + the missing citation — the anti-gaming assertion flipped"
else
    bad "M1 mutant -> expected rc=2 naming the citation" "$RC"
fi

echo "── M1b malformed citation: prose with no commit id ────────────────────"
build_fixture "we checked the history, it was fine"
sweep "$GATE"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'citation'; then
    ok "M1b mutant -> REFUSE (rc=2): prose is not a citation, so there is no placeholder escape"
else
    bad "M1b mutant -> expected rc=2" "$RC"
fi

echo "── M2  a fixture gate with neither record ─────────────────────────────"
build_fixture "$CITE" cm_no_record_at_all.sh
sweep "$GATE"
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'cm_no_record_at_all.sh'; then
    ok "M2 mutant -> REFUSE (rc=2) NAMING cm_no_record_at_all.sh"
else
    bad "M2 mutant -> expected rc=2 naming the gate" "$RC"
fi

echo "── M3  SOURCE: neutralise the citation VALIDATION on a copy ───────────"
cp "$GATE" "$TMP/copy.sh"; chmod +x "$TMP/copy.sh"
# Make retired_cited() accept any row present, regardless of its citation.
# ONLY the two citation-shape guards are removed; every other assertion is
# untouched, so a flip can only come from the citation check.
# One transform only: awk rewrites both citation-shape guards to no-ops. An
# earlier draft also ran a sed whose s||| delimiters collided with the pipe in
# the matched text; it errored to stderr and did nothing. Removed rather than
# left in, because a mutation harness that prints an unexplained tool error is
# indistinguishable from one whose mutation silently failed to apply.
awk '{ if ($0 ~ /grep -q .git log. \|\| return 2/ || $0 ~ /grep -qE .\[0-9a-f\]\{7,40\}. \|\| return 2/) print "    :"; else print }' "$TMP/copy.sh" > "$TMP/copy2.sh"
mv "$TMP/copy2.sh" "$TMP/copy.sh"; chmod +x "$TMP/copy.sh"
if ! grep -q "grep -q 'git log'" "$TMP/copy.sh"; then
    ok "M3 mutation applied to the COPY (citation validation neutralised; repo untouched)"
else
    bad "M3 mutation did NOT apply — the case below would be vacuous" "n/a"
fi
if sh -n "$TMP/copy.sh" 2>/dev/null; then
    ok "M3 mutated copy still parses (the flip is behavioural, not a syntax error)"
else
    bad "M3 mutated copy does not parse" "n/a"
fi
build_fixture ""
sweep "$TMP/copy.sh"
if [ "$RC" -eq 0 ]; then
    ok "M3 mutant -> the citation refusal DISAPPEARS (rc=0): M1's flip is caused by the citation check itself"
else
    bad "M3 mutant -> expected rc=0 once the citation check is neutralised" "$RC"
fi

echo "── §11.4.84 residue check ─────────────────────────────────────────────"
sum_after=$(cksum < "$GATE")
if [ "$sum_before" = "$sum_after" ]; then
    ok "the real gate is byte-identical before/after (cksum $sum_after) — no mutation residue"
else
    bad "the real gate CHANGED during this run (before=$sum_before after=$sum_after)" "n/a"
fi

printf '\ncm_unreferenced_gate_bound_or_retired_mutation_test.sh: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
