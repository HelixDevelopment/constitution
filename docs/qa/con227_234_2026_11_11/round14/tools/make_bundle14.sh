#!/usr/bin/env bash
# docs/qa/con227_234_2026_11_11/round14/tools/make_bundle14.sh REPO BASE OUTDIR
# Round 14 (F1): writes the hand-off bundle BASE..HEAD of REPO into OUTDIR ONLY when landing_gate14.sh passes on the
# committed HEAD (a clean clone; `--verify-manifest` must be RESULT: MANIFEST-OK). A failing gate writes no bundle
# and exits 1. Also refuses a dirty working tree (exit 1): the bundle carries commits, so uncommitted edits would
# be evidence nobody gets. Prints the bundle sha256, head and prerequisite.
set -u
REPO="${1:?usage: make_bundle14.sh REPO BASE OUTDIR}"; BASE="${2:?base}"; OUT="${3:?outdir}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "$(git -C "$REPO" status --porcelain)" ] || { echo "make_bundle14: the working tree is dirty; commit first" >&2; exit 1; }
head="$(git -C "$REPO" rev-parse HEAD)" || exit 2
mkdir -p "$OUT" || exit 2
bash "$HERE/landing_gate14.sh" "$REPO" "$head" "$OUT/landing" || { echo "make_bundle14: landing gate failed; no bundle written" >&2; exit 1; }
br="$(git -C "$REPO" symbolic-ref -q --short HEAD)" || { echo "make_bundle14: HEAD is detached; check out the vehicle branch" >&2; exit 2; }
git -C "$REPO" bundle create "$OUT/fix227_r14.bundle" "$BASE..$br" || exit 2
git -C "$REPO" bundle verify "$OUT/fix227_r14.bundle" >"$OUT/bundle_verify.txt" 2>&1 || exit 2
printf 'BUNDLE %s sha256=%s head=%s requires=%s\n' "$OUT/fix227_r14.bundle" "$(sha256sum <"$OUT/fix227_r14.bundle" | cut -d' ' -f1)" "$head" "$(git -C "$REPO" rev-parse "$BASE")" | tee "$OUT/bundle.txt"
