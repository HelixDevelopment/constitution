#!/usr/bin/env bash
# cm_installer_script_modes.sh — CM-INSTALLER-SCRIPT-MODES gate.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A shell script that is meant to be EXECUTED must ship with mode 100755. A script committed as 100644 is
# made executable on the consumer's side by scripts/post_update_hook.sh (STEP 5 runs `chmod +x` on every
# changed scripts/*.sh, scripts/hooks/*, scripts/label-sync/**/*.sh and skills/**/*.sh); that mode change
# leaves the consumer's constitution submodule DIRTY, and a dirty submodule blocks every later run of
# update_constitution.sh. The gate proves the shipped mode of every file in scope:
#   * a file COUNTS when its name ends in .sh and its first two bytes are "#!" (a shebang: it is written to
#     be run). A .sh file without a shebang is a sourced fragment and is not checked.
#   * TRACKED file  → the mode git records in the index (`git ls-files -s`) must be 100755.
#   * UNTRACKED file → the working-tree owner execute bit must be set (that is the bit git records as
#     100755 when the file is added).
# Scopes (--scope):
#   installer   (default; BLOCKING) the installer family: scripts/install_constitution.sh,
#               scripts/update_constitution.sh, scripts/gates/cm_installer_*.sh, tests/install/*.sh
#   hook-chmod  (BLOCKING when chosen) every file the post-update hook chmods: scripts/*.sh (direct
#               children), scripts/hooks/* files, scripts/label-sync/**/*.sh, scripts/multitrack/
#               track_branch_label.sh, skills/**/*.sh
#   all         (BLOCKING when chosen) every *.sh under scripts/ and tests/
# Control needles: (1) the scope must contain at least one counted file, else BLIND; (2) a self-check in a
# scratch git repository classifies a known 100755 file PASS, a known untracked 0644 file FAIL, a tracked
# 100644 file FAIL and a shebang-less .sh SKIP with the SAME classifier; if any of the four is wrong the
# instrument is broken and the gate reports BLIND, never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_installer_script_modes.sh [--root DIR] [--scope installer|hook-chmod|all]
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL (each offending file is listed) · 2 BLIND (nothing in scope, or a control needle failed) · 64 usage
# Side-effects: a scratch dir under $TMPDIR for the self-check (removed: known names only, then rmdir).
# Paired mutation test: cm_installer_script_modes_mutation_test.sh. Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-INSTALLER-SCRIPT-MODES"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"; scope=installer
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] && [ -d "$2" ] || { echo "$GATE: --root needs an existing directory" >&2; exit 64; }; root="$(cd "$2" && pwd)"; shift 2 ;;
    --scope) case "${2:-}" in installer|hook-chmod|all) scope="$2" ;; *) echo "$GATE: --scope installer|hook-chmod|all" >&2; exit 64 ;; esac; shift 2 ;;
    -h|--help) sed -n 2,33p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done

# classify ROOT REL → prints PASS|FAIL|SKIP (and the recorded mode) for one file
classify() {
  local r="$1" rel="$2" hdr ent
  [ -f "$r/$rel" ] && [ ! -L "$r/$rel" ] || { printf 'SKIP not-a-regular-file'; return; }
  hdr="$(head -c 2 -- "$r/$rel" 2>/dev/null)"
  [ "$hdr" = '#!' ] || { printf 'SKIP no-shebang'; return; }
  ent="$(git -C "$r" ls-files -s -- "$rel" 2>/dev/null | head -n 1)"
  if [ -n "$ent" ]; then
    case "${ent%% *}" in 100755) printf 'PASS tracked-100755' ;; *) printf 'FAIL tracked-%s' "${ent%% *}" ;; esac
  elif [ -x "$r/$rel" ]; then printf 'PASS untracked-executable'
  else printf 'FAIL untracked-mode-%s' "$(stat -c %a -- "$r/$rel" 2>/dev/null || echo '?')"; fi
}

# candidates ROOT SCOPE → NUL-free list of relative paths (tracked and untracked, ignored files excluded)
candidates() {
  local r="$1" s="$2"
  git -C "$r" ls-files -z --cached --others --exclude-standard 2>/dev/null | tr '\0' '\n' | awk -v s="$s" '
    s == "installer" && ($0 == "scripts/install_constitution.sh" || $0 == "scripts/update_constitution.sh" \
       || $0 ~ /^scripts\/gates\/cm_installer_[^\/]*\.sh$/ || $0 ~ /^tests\/install\/[^\/]*\.sh$/) { print; next }
    s == "hook-chmod" && ($0 ~ /^scripts\/[^\/]*\.sh$/ || $0 ~ /^scripts\/hooks\/[^\/]*$/ \
       || $0 ~ /^scripts\/label-sync\/.*\.sh$/ || $0 == "scripts/multitrack/track_branch_label.sh" \
       || $0 ~ /^skills\/.*\.sh$/) { print; next }
    s == "all" && $0 ~ /^(scripts|tests)\/.*\.sh$/ { print; next }' | sort -u
}

# control needle (2): the classifier must tell the four known shapes apart in a scratch repository
work="$(mktemp -d "${TMPDIR:-/tmp}/cm_installer_modes.XXXXXX")" || exit 2
cleanup() { rm -f -- "${work:?}"/n/*.sh; rm -rf -- "${work:?}/n/.git"; rmdir -- "${work:?}/n" "${work:?}" 2>/dev/null; }
trap cleanup EXIT
mkdir "$work/n" && git -C "$work/n" init -q 2>/dev/null || { echo "⚠ $GATE: BLIND (exit 2) — cannot create the self-check repository"; exit 2; }
printf '#!/bin/sh\n' >"$work/n/good.sh"; chmod 755 "$work/n/good.sh"
printf '#!/bin/sh\n' >"$work/n/bad_untracked.sh"; chmod 644 "$work/n/bad_untracked.sh"
printf '#!/bin/sh\n' >"$work/n/bad_tracked.sh"; chmod 644 "$work/n/bad_tracked.sh"
printf 'x=1\n' >"$work/n/fragment.sh"; chmod 644 "$work/n/fragment.sh"
git -C "$work/n" add -- good.sh bad_tracked.sh 2>/dev/null; chmod 755 "$work/n/bad_tracked.sh"   # index 100644, worktree 755
n1="$(classify "$work/n" good.sh)"; n2="$(classify "$work/n" bad_untracked.sh)"; n3="$(classify "$work/n" bad_tracked.sh)"; n4="$(classify "$work/n" fragment.sh)"
if [ "${n1%% *}" != PASS ] || [ "${n2%% *}" != FAIL ] || [ "${n3%% *}" != FAIL ] || [ "${n4%% *}" != SKIP ]; then
  echo "⚠ $GATE: BLIND (exit 2) — classifier self-check failed (good=$n1 untracked644=$n2 tracked100644=$n3 fragment=$n4)"; exit 2
fi

git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "⚠ $GATE: BLIND (exit 2) — $root is not a git work tree"; exit 2; }
counted=0; fails=0; skipped=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  v="$(classify "$root" "$rel")"
  case "${v%% *}" in
    PASS) counted=$((counted+1)) ;;
    FAIL) counted=$((counted+1)); fails=$((fails+1)); echo "  FAIL $rel (${v#* }; want 100755)" ;;
    *) skipped=$((skipped+1)) ;;
  esac
done < <(candidates "$root" "$scope")
if [ "$counted" -eq 0 ]; then echo "⚠ $GATE: BLIND (exit 2) — control needle: no shebang .sh file in scope '$scope' under $root"; exit 2; fi
if [ "$fails" -gt 0 ]; then echo "❌ $GATE: FAIL ($fails of $counted executable script(s) in scope '$scope' would not ship as 100755; $skipped shebang-less .sh skipped)"; exit 1; fi
echo "✅ $GATE: PASS ($counted executable script(s) in scope '$scope' ship as 100755; $skipped shebang-less .sh skipped; classifier self-check 4/4)"
exit 0
