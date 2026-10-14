#!/usr/bin/env bash
# cm_label_sync_hooks_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LABEL-SYNC-HOOKS.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a CLEAN disposable fixture root (stub scripts with §11.4.18 headers, the
# documentation tokens, a post_update_hook.sh carrying the wiring tokens) that
# MUST PASS (--structural-only), then applies independent mutations on fresh
# copies, each of which MUST make the gate FAIL:
#   (1) an event hook missing            (2) installer not executable
#   (3) a hook without a Purpose header  (4) HOOKS.md missing the `statusLine` token
#   (5) HOOKS.md absent                  (6) post_update_hook.sh without the wiring
#   (7) post_update_hook.sh default not dry-run (destructive default)
#   (8) a hook that exits 1 on garbage stdin (fail-soft broken)
#   (9) a hook that prints noise on garbage stdin
#   (10) toolkit wrapper missing         (11) a hook with a syntax error
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_hooks_mutation_test.sh
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temp fixture under $TMPDIR, removed on EXIT. No network, no real-tree edit.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash + the sibling gate script.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 gate FAILs on every mutation AND PASSes on the clean fixture | 1 an
#   expectation was violated | 2 gate script missing.
# Cross-refs: §1.1, §11.4.182, §11.4.201. Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/cm_label_sync_hooks.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_hooks_mut.XXXXXX")"
trap 'rm -rf "${TMP:?}"' EXIT
rc=0
EVENT_HOOKS="label-sync-session-start label-sync-prompt label-sync-agent-register label-sync-subagent-start label-sync-subagent-stop label-sync-stop label-sync-session-end label-sync-model-switch"
stub() { # file [body]
  printf '#!/usr/bin/env bash\n# Purpose : stub\n# Usage   : stub\n# Exit    : 0\n%s\n' "${2:-exit 0}" >"$1"; chmod +x "$1"
}
build() { # $1 root
  local r="$1" s="$1/scripts/label-sync" h h2
  mkdir -p "$s/hooks" "$s/toolkit" "$1/docs/label-sync" "$1/scripts/hooks"
  stub "$s/hooks/label-sync-lib.sh"
  for h in $EVENT_HOOKS label-sync-alias-switch request_history_append; do stub "$s/hooks/$h.sh"; done
  stub "$s/install_label_sync.sh"; stub "$s/toolkit/cma_label_hook.sh"; stub "$s/prove_hook_mutations.sh"
  printf '# Purpose : stub\nimport sys\n' >"$s/hook_mutants.py"
  stub "$1/scripts/hooks/test_label_sync_hooks.sh"
  echo 'SessionStart UserPromptSubmit PreToolUse SubagentStart SubagentStop SessionEnd statusLine install_label_sync.sh --apply --dry-run --uninstall rollback cma_label_hook.sh LABEL_SYNC_AUTOWIRE 11.4.208 11.4.228 11.4.182 UNCONFIRMED CONFIRMED' >"$1/docs/label-sync/HOOKS.md"
  printf '#!/usr/bin/env bash\ninstall_label_sync() { :; }\nmode="${LABEL_SYNC_AUTOWIRE:-dry-run}"\n' >"$1/scripts/post_update_hook.sh"
}
expect() { # want(pass|fail) desc root
  if bash "$GATE" --root "$3" --structural-only --quiet >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "✅ META OK:   $2 — gate ${got}ed as required"
  else echo "❌ META FAIL: $2 — gate ${got}ed, wanted $1"; rc=1; fi
}
build "$TMP/clean"; expect pass "clean fixture" "$TMP/clean"
H="scripts/label-sync/hooks"
r="$TMP/m1"; build "$r"; rm "$r/$H/label-sync-stop.sh"; expect fail "event hook missing" "$r"
r="$TMP/m2"; build "$r"; chmod -x "$r/scripts/label-sync/install_label_sync.sh"; expect fail "installer not executable" "$r"
r="$TMP/m3"; build "$r"; sed -i '/^# Purpose/d' "$r/$H/label-sync-prompt.sh"; expect fail "hook without Purpose header" "$r"
r="$TMP/m4"; build "$r"; sed -i 's/statusLine//' "$r/docs/label-sync/HOOKS.md"; expect fail "HOOKS.md lacks statusLine" "$r"
r="$TMP/m5"; build "$r"; rm "$r/docs/label-sync/HOOKS.md"; expect fail "HOOKS.md absent" "$r"
r="$TMP/m6"; build "$r"; echo '#!/usr/bin/env bash' >"$r/scripts/post_update_hook.sh"; expect fail "post_update_hook lacks wiring" "$r"
r="$TMP/m7"; build "$r"; sed -i 's/:-dry-run/:-apply/' "$r/scripts/post_update_hook.sh"; expect fail "post_update default not dry-run" "$r"
r="$TMP/m8"; build "$r"; stub "$r/$H/label-sync-session-end.sh" 'exit 1'; expect fail "hook exits 1 on garbage" "$r"
r="$TMP/m9"; build "$r"; stub "$r/$H/label-sync-subagent-stop.sh" 'echo noise'; expect fail "hook prints noise on garbage" "$r"
r="$TMP/m10"; build "$r"; rm "$r/scripts/label-sync/toolkit/cma_label_hook.sh"; expect fail "toolkit wrapper missing" "$r"
r="$TMP/m11"; build "$r"; echo 'if then fi (' >>"$r/$H/label-sync-lib.sh"; expect fail "hook syntax error" "$r"
r="$TMP/m12"; build "$r"; rm "$r/scripts/label-sync/hook_mutants.py"; expect fail "mutant table missing" "$r"
r="$TMP/m13"; build "$r"; echo 'def (' >>"$r/scripts/label-sync/hook_mutants.py"; expect fail "mutant table does not compile" "$r"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
