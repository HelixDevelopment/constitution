#!/usr/bin/env bash
# cm_label_sync_hooks.sh — CM-LABEL-SYNC-HOOKS gate for the label-sync HOOKS +
# WIRING stream (§11.4.182 labels, §11.4.208/§11.4.210 request ledger,
# §11.4.228(D)/§11.4.164 auto-wiring).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts, against a constitution root, that the hook scripts, the alias-switch
# signal, the toolkit wrapper, the installer, the post-update wiring and the
# documentation are present, documented and genuinely working:
#   (1) STRUCTURAL (always; fixture-mutation-tested):
#       (a) scripts/label-sync/hooks/: label-sync-lib.sh, label-sync-{session-start,
#           prompt,agent-register,subagent-start,subagent-stop,stop,session-end,
#           model-switch,alias-switch}.sh, request_history_append.sh — each
#           present, parse-clean (`bash -n`) and carrying a §11.4.18 header
#           (Purpose/Usage/Exit); every executable entry point is +x
#       (b) scripts/label-sync/install_label_sync.sh executable + header
#       (c) scripts/label-sync/toolkit/cma_label_hook.sh present + header
#       (d) scripts/label-sync/prove_hook_mutations.sh and
#           scripts/hooks/test_label_sync_hooks.sh present
#       (e) docs/label-sync/HOOKS.md present and naming the load-bearing tokens
#           (events, installer flags, rollback, §11.4.208/§11.4.228, UNCONFIRMED)
#       (f) scripts/post_update_hook.sh wires the installer (install_label_sync +
#           LABEL_SYNC_AUTOWIRE) and defaults to NON-destructive (dry-run)
#   (2) BEHAVIOURAL, no daemon/binaries needed (§11.4.201 — assert the REAL
#       condition): every event hook given GARBAGE stdin exits 0 and prints
#       NOTHING (fail-soft, never blocks, never noisy)
#   (3) RUNTIME (skipped with --structural-only, or when jq/git is absent — an
#       honest SKIP, never a false PASS): the full hermetic suite
#       scripts/hooks/test_label_sync_hooks.sh exits 0 (needs jq + go to build the
#       binaries, or LS_TEST_BIN)
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_hooks.sh [--root <constitution-root>] [--structural-only] [--quiet]
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT env override for --root (arg wins).
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines and a summary.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   The runtime suite uses a temp HOME/state dir (removed on exit); nothing else.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep; jq (+go or LS_TEST_BIN) for the runtime check.
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.182, §11.4.208, §11.4.210, §11.4.228, §11.4.164, §11.4.18, §1.1
#   (paired mutation: cm_label_sync_hooks_mutation_test.sh +
#   scripts/label-sync/prove_hook_mutations.sh), §11.4.201.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 all checks PASS (runtime may SKIP) | 1 a check FAILed | 2 environment error.
# Classification: universal (§11.4.17).
set -uo pipefail

GATE="CM-LABEL-SYNC-HOOKS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""; structural=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    --structural-only) structural=1; shift ;;
    -h|--help) sed -n '1,55p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "${GATE}: root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
ls_dir="$root/scripts/label-sync"
hk="$ls_dir/hooks"
doc="$root/docs/label-sync/HOOKS.md"

fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }
need() { # desc, test-command...
  local d="$1"; shift
  if "$@"; then say "✅ PASS     $d"; else warn "❌ FAIL     $d"; fail=1; fi
}
has_header() { grep -q '^# Purpose' "$1" && grep -q '^# Usage' "$1" && grep -q '^# Exit' "$1"; }
parse_ok() { bash -n "$1" 2>/dev/null; }

EVENT_HOOKS="label-sync-session-start label-sync-prompt label-sync-agent-register label-sync-subagent-start label-sync-subagent-stop label-sync-stop label-sync-session-end label-sync-model-switch"
ALL_HOOKS="label-sync-lib $EVENT_HOOKS label-sync-alias-switch request_history_append"

for h in $ALL_HOOKS; do
  need "hooks/$h.sh present + parse-clean + §11.4.18 header" bash -c "[ -f '$hk/$h.sh' ] && bash -n '$hk/$h.sh' && grep -q '^# Purpose' '$hk/$h.sh' && grep -q '^# Usage' '$hk/$h.sh' && grep -q '^# Exit' '$hk/$h.sh'"
done
for h in $EVENT_HOOKS label-sync-alias-switch request_history_append; do
  need "hooks/$h.sh executable" test -x "$hk/$h.sh"
done
need "install_label_sync.sh executable + parse-clean + header" bash -c "[ -x '$ls_dir/install_label_sync.sh' ] && bash -n '$ls_dir/install_label_sync.sh' && grep -q '^# Purpose' '$ls_dir/install_label_sync.sh' && grep -q '^# Usage' '$ls_dir/install_label_sync.sh' && grep -q '^# Exit' '$ls_dir/install_label_sync.sh'"
need "toolkit/cma_label_hook.sh present + parse-clean + header" bash -c "[ -f '$ls_dir/toolkit/cma_label_hook.sh' ] && bash -n '$ls_dir/toolkit/cma_label_hook.sh' && grep -q '^# Purpose' '$ls_dir/toolkit/cma_label_hook.sh' && grep -q '^# Usage' '$ls_dir/toolkit/cma_label_hook.sh' && grep -q '^# Exit' '$ls_dir/toolkit/cma_label_hook.sh'"
need "prove_hook_mutations.sh present" test -f "$ls_dir/prove_hook_mutations.sh"
need "scripts/hooks/test_label_sync_hooks.sh present" test -f "$root/scripts/hooks/test_label_sync_hooks.sh"
need "docs/label-sync/HOOKS.md present" test -f "$doc"
for tok in SessionStart UserPromptSubmit PreToolUse SubagentStart SubagentStop SessionEnd statusLine \
           install_label_sync.sh --apply --dry-run --uninstall rollback cma_label_hook.sh \
           LABEL_SYNC_AUTOWIRE 11.4.208 11.4.228 11.4.182 UNCONFIRMED CONFIRMED; do
  need "HOOKS.md names '$tok'" grep -qF -- "$tok" "$doc"
done
pu="$root/scripts/post_update_hook.sh"
need "post_update_hook.sh wires the installer (install_label_sync)" grep -q 'install_label_sync' "$pu"
need "post_update_hook.sh honours LABEL_SYNC_AUTOWIRE" grep -q 'LABEL_SYNC_AUTOWIRE' "$pu"
need "post_update_hook.sh default is NON-destructive (dry-run)" grep -qE 'LABEL_SYNC_AUTOWIRE:-dry-run' "$pu"

# (2) behavioural: garbage stdin => exit 0, silent (no daemon / binary needed)
for h in $EVENT_HOOKS; do
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/cm_ls_hooks_g.XXXXXX")"
  out="$(printf 'not json {{{' | env HOME="$tmpd" LABEL_SYNC_DIR="$tmpd/state" LABEL_SYNC_BIN="$tmpd/bin" LABEL_SYNC_NO_BUILD=1 bash "$hk/$h.sh" 2>/dev/null)"; rc=$?
  rm -rf "${tmpd:?}"
  [ "$rc" -eq 0 ] && [ -z "$out" ]
  r=$?
  if [ "$r" -eq 0 ]; then say "✅ PASS     $h: garbage stdin => exit 0, silent"; else warn "❌ FAIL     $h: garbage stdin => rc=$rc out='${out:0:40}' (must be exit 0 + silent)"; fail=1; fi
done

# (3) runtime: the hermetic suite
suite="$root/scripts/hooks/test_label_sync_hooks.sh"
if [ -n "$structural" ] || ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 \
   || { [ -z "${LS_TEST_BIN:-}" ] && ! command -v go >/dev/null 2>&1; }; then
  warn "⚠️  SKIP     runtime suite (--structural-only, or jq/git/go absent — honest skip, §11.4.3)"
else
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cm_ls_hooks.XXXXXX")"
  trap 'rm -rf "${TMPD:?}"' EXIT
  if nice -n 10 bash "$suite" >"$TMPD/suite.log" 2>&1; then
    say "✅ PASS     hermetic suite: $(grep -E 'label-sync hooks suite:' "$TMPD/suite.log" | tail -1)"
  else
    warn "❌ FAIL     hermetic suite — failing lines:"; grep -E '❌|ENV:' "$TMPD/suite.log" | head -15; fail=1
  fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then echo "❌ ${GATE}: FAIL"; exit 1; fi
echo "✅ ${GATE}: PASS — label-sync hooks + wiring present, documented and working"
exit 0
