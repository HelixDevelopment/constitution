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
# All five run against a disposable scratch COPY of the real tree (never the
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
    "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" "${scratch}/Constitution.md" \
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
        "${scratch}/scripts/gates/gate_ledger_deferrals.tsv" "${scratch}/Constitution.md"))"

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
    sed -i "s/${victim//./\\.}//g" "${scratch}/Constitution.md"
    if grep -qF -- "$victim" "${scratch}/Constitution.md"; then
        fail "T4 setup: victim gate ${victim} still present in scratch corpus after the removal edit (sed did not remove it) — cannot exercise the vanished-name mutation"
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
for f in gate_ledger_deferrals.tsv gate_ledger_baseline.txt gate_ledger_prev_names.txt gate_ledger_removals.tsv; do
    [ -f "${real_root}/scripts/gates/$f" ] && cp -p "${real_root}/scripts/gates/$f" "${scratch}/scripts/gates/$f"
done
if ! "$gate" --root "$scratch" --quiet >/tmp/.cm_gate_ledger_t6c.log 2>&1; then
    fail "T6 control: the REAL checked-in inputs did not PASS — T6 cannot attribute a FAIL to the deletion"
    cat /tmp/.cm_gate_ledger_t6c.log >&2
else
    t6_victim="$(awk -F'\t' '$2 ~ /^OWED-GATE-[0-9]+$/ {v=$1} END{print v}' "${scratch}/scripts/gates/gate_ledger_deferrals.tsv")"
    if [ -z "$t6_victim" ] || ! grep -qF -- "$t6_victim" "${scratch}/Constitution.md"; then
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

echo "----------------------------------------------------------------------"
if [ "$fails" -eq 0 ]; then
    echo "✅ CM-GATE-LEDGER-RATCHET mutation test: PASS — all 6 sub-cases (golden-TRUE, unimplemented+undeferred-mutation-FAIL, deferral-restores-PASS, vanished-name-mutation-FAIL, removal-citation-restores-PASS, checked-in-baseline deleted-deferral-FAIL) behaved as required"
    exit 0
else
    echo "❌ CM-GATE-LEDGER-RATCHET mutation test: FAIL — ${fails} sub-case(s) did not behave as required"
    exit 1
fi
