#!/usr/bin/env bash
# cm_installer_truncation_safe.sh — CM-INSTALLER-TRUNCATION-SAFE gate.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# scripts/install_constitution.sh is meant to be run as `curl -fsSL URL | bash`. A download cut short
# MUST execute nothing. The gate proves it on the real file:
#   (1) the last line is exactly `main "$@" __helix_installer_eof__` (the sentinel call);
#   (2) main refuses (exit 2, prints no snippet) when its last argument is not the sentinel;
#   (3) DYNAMIC: every prefix of the file (one every STEP bytes, plus each of the last 96 incomplete
#       prefixes) is executed exactly like a broken download (stdin into `bash -s -- --print-snippets`)
#       in an empty scratch directory; none may print a snippet line or create a file.
#   (4) DYNAMIC, ZERO ARGUMENTS (the plain `curl -fsSL URL | bash` form): the same prefixes are executed
#       with NO argument and HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TTY=/dev/null; none may print an installer line
#       ("[constitution]") or create a file.
#   Control needles: the COMPLETE file with --print-snippets must print the 5 snippet lines, and the
#   COMPLETE file with no argument must print an installer line ("[constitution]", it stops at the
#   closed input); if either is missing the instrument is blind and the gate reports BLIND, never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_installer_truncation_safe.sh [--installer FILE] [--step N]      (default step 211)
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (file missing, control needle not found) · 64 usage
# Side-effects: a scratch dir under $TMPDIR (removed with rm -f/rmdir of known names only).
# Paired mutation test: cm_installer_truncation_safe_mutation_test.sh. Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-INSTALLER-TRUNCATION-SAFE"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
inst="$const/scripts/install_constitution.sh"; step=211
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) [ $# -ge 2 ] || { echo "$GATE: --installer needs a value" >&2; exit 64; }; inst="$2"; shift 2 ;;
    --step) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { echo "$GATE: --step needs a positive integer" >&2; exit 64; }; step="$2"; shift 2 ;;
    -h|--help) sed -n 2,21p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -r "$inst" ] || { echo "⚠ $GATE: BLIND (exit 2) — installer not found: $inst"; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/cm_installer_trunc.XXXXXX")" || exit 2
cleanup() { rm -f -- "${work:?}/prefix.sh"; rmdir -- "${work:?}/run" 2>/dev/null; rmdir -- "${work:?}" 2>/dev/null; }
trap cleanup EXIT
mkdir "$work/run"
fails=0
last="$(tail -n 1 "$inst")"
if [ "$last" != 'main "$@" __helix_installer_eof__' ]; then echo "  FAIL last line is not the sentinel call: $last"; fails=$((fails+1)); fi
out="$(cd "$work/run" && bash -c 'HELIX_INSTALLER_LIB_MODE=1; source "$1"; HELIX_INSTALLER_LIB_MODE=; main --print-snippets __not_the_sentinel__' _ "$inst" 2>/dev/null)"; rc=$?
if [ "$rc" != 2 ] || printf '%s' "$out" | grep -q '^curl -fsSL'; then echo "  FAIL main runs without the sentinel (rc=$rc)"; fails=$((fails+1)); fi
needle="$(cd "$work/run" && bash -s -- --print-snippets <"$inst" 2>/dev/null | grep -c '^curl -fsSL')"
if [ "${needle:-0}" -lt 5 ]; then
  if [ "$fails" -gt 0 ]; then echo "❌ $GATE: FAIL ($fails static finding(s); the complete file does not run either)"; exit 1; fi
  echo "⚠ $GATE: BLIND (exit 2) — control needle: the complete file printed ${needle:-0} snippet lines (want >= 5)"; exit 2
fi
needle0="$(cd "$work/run" && GIT_CEILING_DIRECTORIES="$work" HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TTY=/dev/null timeout 60 bash -s 2>&1 <"$inst" | grep -c '^\[constitution\]')"
if [ "${needle0:-0}" -lt 1 ] || [ -n "$(ls -A "$work/run")" ]; then
  echo "⚠ $GATE: BLIND (exit 2) — control needle: the complete file with no argument printed ${needle0:-0} installer lines (want >= 1) or left files"; exit 2
fi
size="$(wc -c <"$inst")"; n=0
for ((k=1; k<size-1; k++)); do
  if [ $((k % step)) -ne 0 ] && [ "$k" -lt $((size-97)) ]; then continue; fi
  head -c "$k" "$inst" >"$work/prefix.sh"; n=$((n+1))
  o="$(cd "$work/run" && bash -s -- --print-snippets <"$work/prefix.sh" 2>/dev/null)"
  if printf '%s' "$o" | grep -q '^curl -fsSL' || [ -n "$(ls -A "$work/run")" ]; then
    echo "  FAIL prefix of $k bytes executed work"; fails=$((fails+1))
    [ -n "$(ls -A "$work/run")" ] && { echo "⚠ $GATE: a prefix created files; scratch kept at $work"; trap - EXIT; exit 1; }
  fi
  o="$(cd "$work/run" && GIT_CEILING_DIRECTORIES="$work" HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TTY=/dev/null timeout 60 bash -s 2>&1 <"$work/prefix.sh")"
  if printf '%s' "$o" | grep -q '^\[constitution\]' || [ -n "$(ls -A "$work/run")" ]; then
    echo "  FAIL prefix of $k bytes ran the installer with no argument"; fails=$((fails+1))
    [ -n "$(ls -A "$work/run")" ] && { echo "⚠ $GATE: a prefix created files; scratch kept at $work"; trap - EXIT; exit 1; }
  fi
done
if [ "$fails" -gt 0 ]; then echo "❌ $GATE: FAIL ($fails finding(s); $n prefixes executed)"; exit 1; fi
echo "✅ $GATE: PASS ($n truncated prefixes executed twice (with --print-snippets and with no argument), none did anything; control needles $needle snippet lines, $needle0 installer lines)"
exit 0
