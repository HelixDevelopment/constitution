#!/usr/bin/env bash
# cm_gate_ledger_ratchet_mutation_test.sh — §1.1 paired mutation test for
# CM-GATE-LEDGER-RATCHET (§11.4.227(A)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the ratchet gate is genuinely load-bearing, not a tautology:
#   T1 (golden-TRUE)  — the REAL constitution tree, as committed, PASSes.
#   T2 (mutation)     — naming a brand-new CM-* gate in the corpus with
#                       NEITHER an implementation NOR a registered deferral
#                       MUST make the gate FAIL (unimplemented count exceeds
#                       the checked-in baseline by exactly one).
#   T3 (restore-by-deferral) — registering a deferral for that SAME new gate
#                       (still no implementation) MUST restore PASS (the
#                       gate moves from UNIMPLEMENTED to DEFERRED, so the
#                       ratchet-counted bucket returns to baseline).
#   T4 (vanished-name mutation) — deleting EVERY occurrence of a real,
#                       previously-named gate from the corpus WITHOUT adding
#                       a removal citation MUST make the gate FAIL.
#   T5 (restore-by-removal-citation) — adding that removal citation MUST
#                       restore PASS.
#
#   T6  (checked-in baseline) — see the T6 comment below.
#   T7..T12 (status-summary rotation, added 2026-10-27) — a verbatim rotation of
#                       the corpus' `| Status summary |` cell into the archive it
#                       declares MUST stay ledger-neutral (T7), proven to depend on
#                       the gate's archive read by a fix-reverted mutant (T7m);
#                       a severed pointer (T8), a missing archive (T9), a silent
#                       deletion from the archive (T10, restored only by a cited
#                       removal, T11) and an unsafe/empty pointer (T12) MUST NOT
#                       pass. Fixture-based, so independent of the live cell.
#
# All of them run against a disposable scratch COPY of the real tree (never the
# live working tree — §11.4.84 quiescence; a mutation test must never leave
# residue in the checkout it is verifying).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_gate_ledger_ratchet_mutation_test.sh
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all five sub-cases behaved as required (the gate is proven
#       load-bearing).
#   1 — at least one sub-case did not behave as required.
#
# Classification: universal (§11.4.17).

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
real_root="$(cd "${here}/../.." && pwd)"
gate="${here}/cm_gate_ledger_ratchet.sh"

fails=0
note() { echo "MUTATION-TEST: $*"; }
fail() { echo "MUTATION-TEST-FAIL: $*" >&2; fails=$((fails + 1)); }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Build a disposable scratch copy: the real corpus + the real implementation
# tree + the real checked-in registries. Never mutate $real_root itself.
cp -p "${real_root}/Constitution.md" "${scratch}/Constitution.md"
mkdir -p "${scratch}/scripts"
cp -a "${real_root}/scripts/." "${scratch}/scripts/"

# The status-summary archive is part of the gate's corpus whenever the corpus'
# `| Status summary |` cell points at one (§11.4.61(A) rotation, see the gate's
# own header), so the scratch copy MUST carry it too — without it the gate is
# BLIND by design (exit 2), which would make T1..T6 test the wrong thing.
scratch_archive_rel="docs/amendment-log/status-summary-constitution.md"
scratch_archive="${scratch}/${scratch_archive_rel}"
if [ -f "${real_root}/${scratch_archive_rel}" ]; then
    mkdir -p "$(dirname "$scratch_archive")"
    cp -p "${real_root}/${scratch_archive_rel}" "$scratch_archive"
fi
# corpus_files: every file the gate reads as corpus in the CURRENT scratch state.
corpus_files() {
    printf '%s\n' "${scratch}/Constitution.md"
    if [ -f "$scratch_archive" ] && grep -qF "kept on demand in ${scratch_archive_rel};" "${scratch}/Constitution.md"; then
        printf '%s\n' "$scratch_archive"
    fi
}

# The scratch tree stands in for a REAL CHECKOUT, so it must BE one: the
# ledger classifies a file as an implementation site only when that file is
# TRACKED in the repository owning it (an untracked working-tree file is not
# in a fresh clone, so counting it would be a phantom ratchet advance). A bare
# `mktemp -d` copy has no index, which the engine correctly refuses as BLIND.
# `git add -A` alone is enough: tracked-ness is read from the INDEX, so no
# commit — and therefore no user identity — is required. Every mutation below
# edits already-copied files or the TSV registries; none creates a NEW `.sh`
# gate site, so one staging pass here covers the whole run.
git -C "${scratch}" init -q 2>/dev/null || true
git -C "${scratch}" add -A 2>/dev/null || true

# Re-freeze the scratch baseline to the CURRENT scratch-tree ground truth
# BEFORE any mutation, rather than trusting the checked-in real-tree
# baseline file to be perfectly in sync at every instant. This is what
# makes T1 a genuine golden-TRUE independent of how recently the real
# committed baseline was last regenerated (this repo's own CM-* gate count
# moves as new gates land — the checked-in baseline is a monotone-decrease
# RATCHET, not necessarily equal to "right now" between landings).
"${here}/gate_ledger.sh" generate "${scratch}/scripts" \
    "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" $(corpus_files) \
    > "${scratch}/.baseline_ledger.tsv"
awk -F'\t' '$2=="UNIMPLEMENTED"{n++} END{print n+0}' "${scratch}/.baseline_ledger.tsv" \
    > "${scratch}/scripts/gates/gate_ledger_baseline.txt"
cut -f1 "${scratch}/.baseline_ledger.tsv" | sort -u \
    > "${scratch}/scripts/gates/gate_ledger_prev_names.txt"

# ── T1: golden-TRUE — the unmodified scratch copy of the real tree PASSes ───
if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t1.log 2>&1; then
    note "T1 golden-TRUE (real tree, unmodified) PASSED as required"
else
    fail "T1 golden-TRUE: the UNMODIFIED real tree did not PASS — either the checked-in baseline/prev-names are stale, or the gate itself is broken"
    cat /tmp/.cm_gate_ledger_t1.log >&2
fi

# ── T2: mutation — name a brand-new, real-nowhere-implemented CM-* gate ─────
new_gate="CM-MUTATION-TEST-NEVER-IMPLEMENTED-$$"
printf '\n\nMutation-test-injected sentence citing gate `%s` — no implementation, no deferral.\n' "$new_gate" >> "${scratch}/Constitution.md"

if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t2.log 2>&1; then
    fail "T2 mutation: naming a brand-new gate (${new_gate}) with NO implementation and NO deferral did NOT make the ratchet gate FAIL — the gate is not load-bearing"
    cat /tmp/.cm_gate_ledger_t2.log >&2
else
    if grep -q "ratchet violated" /tmp/.cm_gate_ledger_t2.log; then
        note "T2 mutation (new unimplemented+undeferred gate ${new_gate}) correctly FAILED the ratchet"
    else
        fail "T2 mutation FAILED for the wrong reason (expected a ratchet-violated message):"
        cat /tmp/.cm_gate_ledger_t2.log >&2
    fi
fi

# ── T3: restore-by-deferral — register a deferral for the SAME new gate ────
printf '%s\tMUTATION-TEST-TRACKED-ITEM\n' "$new_gate" >> "${scratch}/scripts/gates/gate_ledger_deferrals.tsv"

if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t3.log 2>&1; then
    note "T3 restore-by-deferral (${new_gate} now DEFERRED) correctly restored PASS"
else
    fail "T3 restore-by-deferral: registering a deferral for ${new_gate} did NOT restore PASS"
    cat /tmp/.cm_gate_ledger_t3.log >&2
fi

# Undo T2/T3 before the vanished-name cases so they exercise ONLY their own
# mutation (§11.4.84 — one mutation at a time, never compounded silently).
cp -p "${real_root}/Constitution.md" "${scratch}/Constitution.md"
: > "${scratch}/scripts/gates/gate_ledger_deferrals.tsv"

# ── T4: vanished-name mutation — delete every occurrence of a REAL gate ────
# name from the corpus with NO removal citation. Pick a gate name known to
# be UNIMPLEMENTED in the real corpus today (so this mutation exercises the
# vanished-name path in isolation from the ratchet-count path: removing an
# already-UNIMPLEMENTED name changes the *set* of names, not the
# unimplemented *count*, in a way the ratchet check alone would miss but the
# vanished-name check must catch).
victim="$(awk -F'\t' '$2=="UNIMPLEMENTED"{print $1; exit}' \
    <("${here}/gate_ledger.sh" generate "${scratch}/scripts" \
        "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" $(corpus_files)))"

  # RESTORE the real deferrals now that the victim is chosen.
  # The truncation above is a SELECTION device: emptying deferrals makes every
  # gate read UNIMPLEMENTED so a victim can be picked. Leaving it emptied
  # pollutes T4/T5 with one phantom UNIMPLEMENTED per deferred gate, pushing
  # the count over baseline for a reason that has nothing to do with the
  # vanished-name mutation under test — T5 then fails on the COUNT check while
  # its actual subject (restore-by-removal-citation) is never exercised.
  # That is a §11.4.201(1) false-negative in the test harness: the mutation
  # test reports a failure the gate is not committing.
  cp -p "${real_root}/scripts/gates/gate_ledger_deferrals.tsv" \
        "${scratch}/scripts/gates/gate_ledger_deferrals.tsv"

if [ -z "$victim" ]; then
    fail "T4 setup: could not find any UNIMPLEMENTED gate in the real corpus to use as the vanished-name victim (unexpected — the real corpus should have hundreds)"
else
    # Remove every occurrence of the exact token from the scratch corpus.
    # A boundary-safe removal: blank out the token itself, leaving the rest
    # of each line intact, so no OTHER token on the same line is disturbed.
    # Every corpus file the gate reads (Constitution.md AND its status-summary
    # archive when the cell points at one) loses the token, otherwise the name
    # would survive in the archive and the mutation would not be a deletion.
    corpus_list="$(corpus_files)"
    while IFS= read -r cf; do
        [ -n "$cf" ] && sed -i "s/${victim//./\\.}//g" "$cf"
    done <<< "$corpus_list"
    still_present=""
    while IFS= read -r cf; do
        [ -n "$cf" ] && grep -qF -- "$victim" "$cf" && still_present="$cf"
    done <<< "$corpus_list"
    if [ -n "$still_present" ]; then
        fail "T4 setup: victim gate ${victim} still present in scratch corpus file ${still_present} after the removal edit (sed did not remove it) — cannot exercise the vanished-name mutation"
    else
        if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t4.log 2>&1; then
            fail "T4 mutation: deleting every occurrence of real gate ${victim} with NO removal citation did NOT make the ratchet gate FAIL"
            cat /tmp/.cm_gate_ledger_t4.log >&2
        else
            if grep -q "vanished from the corpus with no removal citation" /tmp/.cm_gate_ledger_t4.log; then
                note "T4 mutation (vanished gate ${victim}, no citation) correctly FAILED"
            else
                fail "T4 mutation FAILED for the wrong reason (expected a vanished-name message):"
                cat /tmp/.cm_gate_ledger_t4.log >&2
            fi
        fi

        # ── T5: restore-by-removal-citation ─────────────────────────────────
        printf '%s\tmutation-test-repeal-citation\n' "$victim" >> "${scratch}/scripts/gates/gate_ledger_removals.tsv"
        if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t5.log 2>&1; then
            note "T5 restore-by-removal-citation (${victim} cited as removed) correctly restored PASS"
        else
            fail "T5 restore-by-removal-citation: citing the removal of ${victim} did NOT restore PASS"
            cat /tmp/.cm_gate_ledger_t5.log >&2
        fi
    fi
fi

# T6 — golden-BAD against the CHECKED-IN baseline (added 2026-10-12, §11.4.230(E) round 2):
# T1-T5 regenerate the baseline inside the scratch tree, so they cannot see headroom in the
# checked-in gate_ledger_baseline.txt (the round-1 review found baseline 402 vs real 394: deleting a
# deferral row passed). T6 restores the REAL corpus, deferrals and checked-in baseline + prev-names,
# deletes one real registered deferral row, and requires the ratchet to FAIL. Control: the unmodified
# real inputs must PASS first, so the FAIL is caused by the deletion and not by a stale snapshot.
cp -p "${real_root}/Constitution.md" "${scratch}/Constitution.md"
# T4 deleted the victim from the scratch archive as well: restore it too.
[ -f "${real_root}/${scratch_archive_rel}" ] && cp -p "${real_root}/${scratch_archive_rel}" "$scratch_archive"
for f in gate_ledger_deferrals.tsv gate_ledger_baseline.txt gate_ledger_prev_names.txt gate_ledger_removals.tsv; do
    [ -f "${real_root}/scripts/gates/$f" ] && cp -p "${real_root}/scripts/gates/$f" "${scratch}/scripts/gates/$f"
done
if ! "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t6c.log 2>&1; then
    fail "T6 control: the REAL checked-in inputs did not PASS — T6 cannot attribute a FAIL to the deletion"
    cat /tmp/.cm_gate_ledger_t6c.log >&2
else
    t6_victim="$(awk -F'\t' '$2 ~ /^OWED-GATE-[0-9]+$/ {v=$1} END{print v}' "${scratch}/scripts/gates/gate_ledger_deferrals.tsv")"
    t6_in_corpus=0
    while IFS= read -r cf; do
        [ -n "$cf" ] && [ -n "$t6_victim" ] && grep -qF -- "$t6_victim" "$cf" && t6_in_corpus=1
    done <<< "$(corpus_files)"
    if [ -z "$t6_victim" ] || [ "$t6_in_corpus" -eq 0 ]; then
        fail "T6 setup: no registered deferral row whose gate is named in the corpus was found"
    else
        awk -F'\t' -v v="$t6_victim" '$1!=v' "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" > "${scratch}/.t6.tsv"
        mv "${scratch}/.t6.tsv" "${scratch}/scripts/gates/gate_ledger_deferrals.tsv"
        if "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t6.log 2>&1; then
            fail "T6 mutation: deleting the real deferral row for ${t6_victim} did NOT make the ratchet FAIL against the checked-in baseline (baseline has headroom)"
            cat /tmp/.cm_gate_ledger_t6.log >&2
        elif grep -q "ratchet violated" /tmp/.cm_gate_ledger_t6.log; then
            note "T6 mutation (deleted real deferral row ${t6_victim}, checked-in baseline) correctly FAILED"
        else
            fail "T6 mutation FAILED for the wrong reason (expected a ratchet-violated message):"
            cat /tmp/.cm_gate_ledger_t6.log >&2
        fi
    fi
fi

# ── T7..T13 — status-summary ROTATION is ledger-neutral, and the archive path is
# NOT a loophole (added 2026-10-27). Root cause (measured, pre-build run 8): the
# preamble `| Status summary |` cell of the corpus named gates that appear
# nowhere else in it; rotating the cell into its on-demand archive (§11.4.61(A))
# made the corpus-only ledger read ten gate names as silently deleted (and let
# the unimplemented count fall below its baseline). T1..T6 could not see this
# because T1 re-freezes prev-names and T6 runs against a tree whose cell already
# points at an archive. These cases build a SELF-CONTAINED fixture so the
# behaviour is proven independently of the live cell's current text:
#   T7   golden-TRUE: a gate named only in the cell, then rotated VERBATIM into
#        the archive the cell points at, MUST still PASS (relocation != deletion)
#   T7m  paired mutation of the FIX itself: the same scenario against a scratch
#        copy of the gate with the archive read removed MUST FAIL (so T7 is
#        proven to discriminate the fixed gate from the pre-fix one)
#   T8   the pointer is severed (archive exists, cell no longer points at it):
#        the name is gone from the corpus => MUST FAIL "vanished" (the archive
#        is not scanned unless the cell DECLARES it)
#   T9   pointer present, archive file missing => MUST be BLIND (exit 2), never
#        a pass and never mass-cited deletions
#   T10  silent deletion of the name from the ARCHIVE, no citation => MUST FAIL
#   T11  ...and the removal citation restores PASS (a genuine repeal stays legal)
#   T12  an absolute / `..` / empty pointer => MUST be BLIND (exit 2)
probe="CM-RELOCATION-PROBE-NEVER-IMPLEMENTED-$$"
cell_prefix='| Status summary | '
ptr_sentence="Older entries of this cell (verbatim, none dropped) are kept on demand in ${scratch_archive_rel}; per §11.4.61(A) this cell is a one-line current-state hook, so record each new amendment in CHANGELOG.md and, when this cell grows, rotate it with scripts/amendment_log/status_summary_archive.py."

# set_cell <file> <row-text>: replace the single preamble Status-summary row.
set_cell() {
    awk -v row="$2" 'BEGIN{pre=1; done=0}
        /^## /{pre=0}
        { if (pre && !done && index($0, "| Status summary | ") == 1) { print row; done=1 } else print }
        END{ exit(done ? 0 : 3) }' "$1" > "$1.new" && mv "$1.new" "$1"
}
# t7_reset: pristine real corpus + real registries, cell replaced by the fixture
# cell that names ONLY the probe, no archive; then re-freeze baseline/prev-names
# from that exact state (the T1 technique) so the starting state is a PASS.
t7_state() {   # fixture state only (cheap): no ledger regeneration
    cp -p "${real_root}/Constitution.md" "${scratch}/Constitution.md"
    rm -rf "${scratch}/docs/amendment-log"
    for f in gate_ledger_deferrals.tsv gate_ledger_removals.tsv; do
        [ -f "${real_root}/scripts/gates/$f" ] && cp -p "${real_root}/scripts/gates/$f" "${scratch}/scripts/gates/$f"
    done
    set_cell "${scratch}/Constitution.md" "${cell_prefix}Newest fixture entry. Prior: fixture history entry naming gate ${probe} only here. |"
}
t7_reset() {
    t7_state || return 1
    "${here}/gate_ledger.sh" generate "${scratch}/scripts" \
        "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" "${scratch}/Constitution.md" \
        > "${scratch}/.t7_ledger.tsv" || return 1
    awk -F'\t' '$2=="UNIMPLEMENTED"{n++} END{print n+0}' "${scratch}/.t7_ledger.tsv" \
        > "${scratch}/scripts/gates/gate_ledger_baseline.txt"
    cut -f1 "${scratch}/.t7_ledger.tsv" | sort -u > "${scratch}/scripts/gates/gate_ledger_prev_names.txt"
    grep -qxF -- "$probe" "${scratch}/scripts/gates/gate_ledger_prev_names.txt"
}
# t7_rotate <pointer-text|""> <archive-body|"">: do the rotation edit.
t7_rotate() {
    set_cell "${scratch}/Constitution.md" "${cell_prefix}Newest fixture entry. $1" || return 1
    mkdir -p "${scratch}/docs/amendment-log"
    printf '# Status summary archive -- fixture\n<!-- BEGIN ENTRIES -->\n%s\n<!-- END ENTRIES -->\n' "$2" \
        > "$scratch_archive"
}
archive_body="Prior: fixture history entry naming gate ${probe} only here."
run_gate() { # run_gate <tag> [gate-script]  -> sets rc, log path in t_log
    t_log="${scratch}/.log_$1"
    "${2:-$gate}" --root "$scratch" --quiet > "$t_log" 2>&1
    rc=$?
}

if ! t7_reset; then
    fail "T7 setup: could not build the self-contained fixture (cell row not found in the preamble, or the probe was not extracted as a corpus name)"
else
    run_gate t7_control
    if [ "$rc" -eq 0 ]; then
        note "T7 control (probe named only in the cell, no rotation yet) PASSED as required"
    else
        fail "T7 control: the fixture's starting state did not PASS (rc=${rc}) — T7..T12 cannot be attributed"
        cat "$t_log" >&2
    fi

    # T7 + T7m share the rotated state.
    t7_rotate "$ptr_sentence" "$archive_body"
    run_gate t7
    if [ "$rc" -eq 0 ] && grep -q "corpus read" "$t_log"; then
        note "T7 golden-TRUE (cell rotated verbatim into its declared archive) correctly PASSED — relocation is ledger-neutral"
    else
        fail "T7 golden-TRUE: a lossless rotation into the declared archive did NOT pass (rc=${rc}) — the gate reads relocation as deletion"
        cat "$t_log" >&2
    fi

    # T7m: mutate the FIX (drop the archive from the corpus list) in a scratch
    # copy of the gate; the same rotated state MUST now FAIL as 'vanished'.
    mut_gate="${scratch}/scripts/gates/cm_gate_ledger_ratchet.sh"
    if [ "$(grep -cF '"${corpus_files[@]}"' "$mut_gate")" -ne 1 ]; then
        fail "T7m setup: expected exactly one corpus_files expansion in the gate to mutate — the gate's structure changed, update this mutation"
    else
        sed -i 's/"${corpus_files\[@\]}"/"$corpus"/' "$mut_gate"
        run_gate t7m "$mut_gate"
        if [ "$rc" -ne 0 ] && grep -q "vanished from the corpus with no removal citation" "$t_log"; then
            note "T7m mutation (archive read removed from the gate) correctly FAILED the rotated fixture — T7 discriminates the fix"
        else
            fail "T7m: the archive-less gate still passed the rotated fixture (rc=${rc}) — T7 does not prove the archive read is what keeps rotation neutral"
            cat "$t_log" >&2
        fi
        cp -p "${real_root}/scripts/gates/cm_gate_ledger_ratchet.sh" "$mut_gate"
    fi

    # T8: pointer severed — the cell no longer says where the archive is.
    t7_rotate "No pointer sentence here." "$archive_body"
    run_gate t8
    if [ "$rc" -eq 1 ] && grep -q "vanished from the corpus with no removal citation" "$t_log"; then
        note "T8 mutation (archive exists but the cell does not declare it) correctly FAILED as a vanished name"
    else
        fail "T8: with the pointer severed the gate returned rc=${rc} instead of FAIL 'vanished' — an undeclared archive must never count as corpus"
        cat "$t_log" >&2
    fi

    # T9: pointer present, archive file absent.
    t7_rotate "$ptr_sentence" "$archive_body"
    rm -f "$scratch_archive"
    run_gate t9
    if [ "$rc" -eq 2 ] && grep -q "BLIND" "$t_log"; then
        note "T9 mutation (pointer present, archive missing) correctly BLIND (exit 2)"
    else
        fail "T9: pointer present with the archive missing returned rc=${rc}, expected BLIND (2)"
        cat "$t_log" >&2
    fi

    # T10 / T11: silent deletion from the archive, then citation.
    t7_rotate "$ptr_sentence" "Prior: fixture history entry whose gate name was silently deleted."
    run_gate t10
    if [ "$rc" -eq 1 ] && grep -q "gate ${probe} vanished from the corpus with no removal citation" "$t_log"; then
        note "T10 mutation (name silently deleted from the ARCHIVE, no citation) correctly FAILED"
    else
        fail "T10: silent deletion from the archive returned rc=${rc}, expected FAIL naming ${probe}"
        cat "$t_log" >&2
    fi
    printf '%s\tmutation-test-repeal-citation\n' "$probe" >> "${scratch}/scripts/gates/gate_ledger_removals.tsv"
    run_gate t11
    if [ "$rc" -eq 0 ]; then
        note "T11 restore-by-removal-citation (archive deletion cited) correctly restored PASS"
    else
        fail "T11: citing the removal of ${probe} did NOT restore PASS (rc=${rc})"
        cat "$t_log" >&2
    fi

    # T12: unsafe or empty pointers must be BLIND, never silently ignored.
    for bad in "/etc/passwd" "../outside.md" "docs/../../outside.md" ""; do
        t7_state >/dev/null 2>&1
        set_cell "${scratch}/Constitution.md" "${cell_prefix}Newest fixture entry. Older entries of this cell are kept on demand in ${bad}; per §11.4.61(A) fixture. |"
        run_gate t12
        if [ "$rc" -eq 2 ] && grep -q "BLIND" "$t_log"; then
            note "T12 mutation (unsafe/empty pointer '${bad}') correctly BLIND (exit 2)"
        else
            fail "T12: pointer '${bad}' returned rc=${rc}, expected BLIND (2)"
            cat "$t_log" >&2
        fi
    done
fi

echo "----------------------------------------------------------------------"
if [ "$fails" -eq 0 ]; then
    echo "✅ CM-GATE-LEDGER-RATCHET mutation test: PASS — all sub-cases (T1-T6: golden-TRUE, unimplemented+undeferred-mutation-FAIL, deferral-restores-PASS, vanished-name-mutation-FAIL, removal-citation-restores-PASS, checked-in-baseline deleted-deferral-FAIL; T7-T12: status-summary rotation ledger-neutral, fix-reverted mutant FAIL, severed-pointer FAIL, missing-archive BLIND, archive-deletion FAIL + citation PASS, unsafe-pointer BLIND) behaved as required"
    exit 0
else
    echo "❌ CM-GATE-LEDGER-RATCHET mutation test: FAIL — ${fails} sub-case(s) did not behave as required"
    exit 1
fi
