#!/usr/bin/env bash
# cm_gate_ledger_ratchet.sh — CM-GATE-LEDGER-RATCHET gate
# (§11.4.227(A) named-gate LEDGER — every CM-* token implemented-or-
# registered-deferral, unimplemented count MONOTONE-DECREASING, vanished
# names need removal citations).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Wires `gate_ledger.sh` (the reusable engine, §11.4.28 decoupled) against
# THIS project's real inputs — the canonical corpus `Constitution.md`, the
# recursive implementation tree `scripts/`, and the three checked-in
# registries (`gate_ledger_deferrals.tsv`, `gate_ledger_baseline.txt`,
# `gate_ledger_prev_names.txt`, optionally `gate_ledger_removals.tsv`) — and
# is the actual pre-build/pre-commit gate: it FAILs the moment a newly-named
# `CM-*` gate has neither a real implementation site nor a registered
# deferral, and FAILs on any gate name silently vanishing from the corpus
# without a removal citation.
#
# Day-one baseline: the checked-in `gate_ledger_baseline.txt` is the
# UNIMPLEMENTED count measured the day this gate landed — the ledger is
# GREEN on arrival by construction (§11.4.227(A): "day-one baseline =
# current count, so it's green on landing + can only shrink"). Lowering the
# baseline as gates land or deferrals are registered is the intended,
# monotone-DECREASING direction; raising it requires an explicit,
# reviewable commit (never a silent bump to make room for new debt).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_gate_ledger_ratchet.sh [--root <constitution-root>] [--quiet]
#     --root <dir>   constitution-submodule root (default: two dirs up from
#                     this script, i.e. the real `constitution/` checkout;
#                     overridable so the paired §1.1 mutation test can point
#                     this SAME gate at a disposable scratch copy).
#     --quiet         suppress the per-status ledger dump (summary + FAIL
#                     lines always shown).
#
# ── Inputs (relative to --root) ─────────────────────────────────────────────
#   Constitution.md                        canonical corpus (source-of-truth
#                                           location per every existing
#                                           cm_covenant_*_propagation.sh
#                                           gate's own documented convention).
#   <status-summary archive>               OPTIONAL second corpus file: when the
#                                           preamble `| Status summary |` cell of
#                                           Constitution.md says its older entries
#                                           are "kept on demand in <path>;" that
#                                           archive (verbatim history, §11.4.61(A))
#                                           is read as part of the corpus, so a
#                                           rotation is ledger-neutral. A pointer
#                                           that cannot be resolved is BLIND (exit 2).
#   scripts/                               implementation tree, scanned
#                                           recursively — gate sites are NOT
#                                           confined to scripts/gates/.
#   scripts/gates/gate_ledger_deferrals.tsv registered deferrals
#                                           (`<gate>\t<tracked-item-id>[\t<note>]`).
#   scripts/gates/gate_ledger_baseline.txt  checked-in monotone-ratchet
#                                           baseline (bare integer).
#   scripts/gates/gate_ledger_prev_names.txt checked-in previous full
#                                           gate-name snapshot (vanished-name
#                                           detection).
#   scripts/gates/gate_ledger_removals.tsv  removal citations
#                                           (`<gate>\t<reason>`), may be
#                                           empty.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   The generated ledger (unless --quiet), the `gate_ledger.sh check` summary
#   line, and a final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, `gate_ledger.sh` (same directory). Parses clean under `bash -n`.
#
# ── Cross-references ────────────────────────────────────────────────────────
#   §11.4.227(A) (this gate's mandate), gate_ledger.sh (the reusable engine),
#   its own header for §11.4.201(7)(a)/(b)/(c) structure-not-substring +
#   control-needle + path-is-part-of-the-instrument discipline, §1.1 (paired
#   mutation test cm_gate_ledger_ratchet_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — ratchet holds (unimplemented <= baseline) and no vanished name lacks
#       a removal citation.
#   1 — ratchet exceeded and/or an uncited vanished name.
#   2 — environment error (root/inputs not found, or gate_ledger.sh itself
#       reported BLIND — the instrument could not see, never a guessed
#       green).
#
# Classification: universal MECHANISM (gate_ledger.sh, §11.4.17) wired
# against PROJECT-SPECIFIC inputs (this constitution submodule's own corpus
# + implementation tree) — the wiring itself is the concrete instantiation
# every consuming project supplies per §11.4.35.

set -u

GATE="CM-GATE-LEDGER-RATCHET"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
engine="${here}/gate_ledger.sh"

root="${CONSTITUTION_ROOT:-$(cd "${here}/../.." && pwd)}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)  root="$2"; shift 2 ;;
        --quiet) quiet="1"; shift ;;
        -h|--help) sed -n '1,60p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -x "$engine" ] || { echo "${GATE}: BLIND — gate_ledger.sh not found/executable at $engine" >&2; exit 2; }
[ -d "$root" ] || { echo "${GATE}: BLIND — root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

corpus="${root}/Constitution.md"
impl="${root}/scripts"
deferrals="${root}/scripts/gates/gate_ledger_deferrals.tsv"
baseline="${root}/scripts/gates/gate_ledger_baseline.txt"
prev_names="${root}/scripts/gates/gate_ledger_prev_names.txt"
removals="${root}/scripts/gates/gate_ledger_removals.tsv"

for f in "$corpus" "$deferrals" "$baseline" "$prev_names"; do
    [ -r "$f" ] || { echo "${GATE}: BLIND — required input not found/readable: $f" >&2; exit 2; }
done
[ -d "$impl" ] || { echo "${GATE}: BLIND — implementation tree not found: $impl" >&2; exit 2; }
[ -r "$removals" ] || removals=""

# ── Archived status-summary corpus: a RELOCATION is ledger-NEUTRAL ───────────
# §11.4.61(A) keeps the preamble `| Status summary |` cell of Constitution.md a
# one-line current-state hook. Older entries of that cell are rotated VERBATIM
# into an on-demand archive (scripts/amendment_log/status_summary_archive.py) and
# the cell then names the archive: "... are kept on demand in <rel-path>; ...".
#
# Root cause this block closes (measured 2026-10-27, pre-build run 8): ten
# gate names (nine prose range/slash-join artefacts of the covenant-propagation
# family, and the REAL, implemented sub-system-shortcuts gate; the exact ids
# are in the evidence pack under qa-results/ledger_ratchet_archive_20261027)
# occur ONLY inside that cell, never in an anchor body. Rotating the cell moved
# them out of Constitution.md — the sole corpus file — so the vanished-name
# check read a lossless relocation as ten uncited deletions, while the five
# UNIMPLEMENTED ones leaving the count made it fall below its baseline and
# would have hidden a new unimplemented gate behind the headroom. A removal
# citation would be a FALSE statement for the sub-system-shortcuts gate (it was
# not removed) and would launder the five phantom debts; the honest rule is
# that history moved into the cell's OWN declared archive is still the
# governance corpus. So the archive the cell points at is read as a second
# corpus file: nothing is added to, or hidden from, the ledger by a rotation.
# (This comment deliberately spells out no gate token: this engine counts a
# token inside ANY tracked `.sh` file as an implementation site, so naming one
# here would mint a phantom IMPLEMENTED row.)
#
# Fail-CLOSED (§11.4.6/§11.4.252): a pointer that is malformed, absolute,
# escapes the root via `..`, or names an unreadable file is BLIND (exit 2) —
# never a silent fall back to the one-file corpus, which would again turn the
# missing archive into mass vanished names (or, worse, into a clean pass if the
# vanished names were then cited away). No pointer in the cell = no archive.
corpus_files=("$corpus")
archive_note=""
status_cell="$(awk '/^## /{exit} /^\| Status summary \| /{print; exit}' "$corpus")"
case "$status_cell" in
    *" kept on demand in "*)
        archive_rel="$(printf '%s\n' "$status_cell" | sed -n 's/.* kept on demand in \([^;[:space:]]*\);.*/\1/p')"
        case "$archive_rel" in
            "")  echo "${GATE}: BLIND — the Status summary cell says its older entries are 'kept on demand in' an archive but no '<path>;' pointer could be parsed from it" >&2; exit 2 ;;
            /*|*..*) echo "${GATE}: BLIND — status-summary archive pointer '${archive_rel}' is absolute or contains '..'; it must be a path inside ${root}" >&2; exit 2 ;;
        esac
        archive="${root}/${archive_rel}"
        [ -r "$archive" ] || { echo "${GATE}: BLIND — the Status summary cell points at the archive '${archive_rel}' but ${archive} is not a readable file; refusing to treat its absence as ten uncited gate deletions or as a pass" >&2; exit 2; }
        corpus_files+=("$archive")
        archive_note=" (corpus = Constitution.md + its status-summary archive ${archive_rel})"
        ;;
esac

ledger_tmp="$(mktemp)"
trap 'rm -f "$ledger_tmp"' EXIT

if ! "$engine" generate "$impl" "$deferrals" "${corpus_files[@]}" > "$ledger_tmp"; then
    echo "${GATE}: BLIND — gate_ledger.sh generate failed (see stderr above)" >&2
    exit 2
fi

[ -n "$quiet" ] || cat "$ledger_tmp"
# Always state which corpus was read (never silent about a second corpus file).
[ -z "$archive_note" ] || echo "${GATE}: corpus read${archive_note}"

# NOTE (own §11.4.201(7)(c) instrument-footgun, caught by this gate's OWN
# paired §1.1 mutation test T4/T5): `status=$?` taken AFTER an `if cmd;
# then ...; fi` with no `else` clause captures the exit status of the
# IF-CONSTRUCT itself, which bash defines as ZERO when the condition is
# false and no branch ran — NOT the condition command's own exit status.
# The check command's status is therefore captured EXPLICITLY, before any
# `if`, so a FAIL (1) or BLIND (2) from `gate_ledger.sh check` is never
# silently swallowed into a false exit-0.
"$engine" check "$ledger_tmp" "$baseline" "$prev_names" "$removals"
status=$?
if [ "$status" -eq 0 ]; then
    echo "✅ ${GATE}: PASS — every named CM-* gate is implemented-or-deferred within the checked-in monotone-decrease baseline; no uncited vanished name"
    exit 0
fi
echo "❌ ${GATE}: FAIL — see LEDGER-FAIL lines above; land the missing gate(s), register their deferral(s) against a tracked item, or (for vanished names) cite the removal in ${removals:-scripts/gates/gate_ledger_removals.tsv}"
exit "$status"
