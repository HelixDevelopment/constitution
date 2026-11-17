#!/usr/bin/env bash
# docs/qa/con227_234_2026_11_11/round14/tools/landing_gate14.sh REPO COMMIT OUTDIR
# Round 14 (F1 of the round-13 review): the landing gate of this vehicle. It checks the COMMITTED tree, never the
# working tree: a `git clone --shared` of REPO at COMMIT into a fresh directory under OUTDIR, then
# `scripts/run_full_suite.sh --verify-manifest` there. Exit 0 only when that exits 0 AND its last RESULT line is
# exactly "RESULT: MANIFEST-OK"; else exit 1 (a census file without a row, as in round 13, is MANIFEST-MISMATCH
# exit 3 and fails this gate); exit 2 on a usage or setup error. The output is kept in OUTDIR/verify_manifest.txt
# and OUTDIR/landing_gate.txt. make_bundle14.sh refuses to write a bundle unless this gate exits 0.
set -u
REPO="${1:?usage: landing_gate14.sh REPO COMMIT OUTDIR}"; COMMIT="${2:?commit}"; OUT="${3:?outdir}"
mkdir -p "$OUT" || exit 2
full="$(git -C "$REPO" rev-parse --verify -q "$COMMIT^{commit}")" || { echo "landing gate: $COMMIT is not a commit" >&2; exit 2; }
CL="$(mktemp -d "${TMPDIR:-/tmp}/landing14.XXXXXX")" || exit 2
cleanup() { [ -n "${CL:-}" ] && [ -d "$CL" ] && . "$REPO/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "${CL:?}" 2>/dev/null; }
trap cleanup EXIT
git clone -q --shared --no-checkout "$REPO" "$CL/repo" && git -C "$CL/repo" checkout -q --detach "$full" || { echo "landing gate: clone/checkout failed" >&2; exit 2; }
( cd "$CL/repo" && bash scripts/run_full_suite.sh --verify-manifest ) >"$OUT/verify_manifest.txt" 2>&1; r=$?
last="$(grep -E '^RESULT' "$OUT/verify_manifest.txt" | tail -n 1)"
if [ "$r" -eq 0 ] && [ "$last" = "RESULT: MANIFEST-OK" ]; then v=PASS; rc=0; else v=FAIL; rc=1; fi
printf 'LANDING-GATE %s commit=%s verify_manifest_rc=%s last=%s\n' "$v" "$full" "$r" "$last" | tee "$OUT/landing_gate.txt"
exit "$rc"
