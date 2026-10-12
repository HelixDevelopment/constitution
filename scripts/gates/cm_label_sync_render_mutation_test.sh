#!/usr/bin/env bash
# cm_label_sync_render_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LABEL-SYNC-RENDER.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a CLEAN disposable fixture root (all structural artefacts) that MUST
# PASS (--structural-only), then applies eight independent mutations on fresh
# copies, each of which MUST make the gate FAIL:
#   (1) statusline.sh missing          (2) labelrun not executable
#   (3) title.sh lacks the §11.4.18 header   (4) shell-hook.sh has a syntax error
#   (5) RENDERERS.md missing           (6) RENDERERS.md lacks `UNCONFIRMED`
#   (7) shell-hook.sh drops the STDIN secret-policy statement
#   (8) shell-integration.bash passes $BASH_COMMAND as an argument (`--cmd`)
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_render_mutation_test.sh
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
GATE="$SCRIPT_DIR/cm_label_sync_render.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_render_mut.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
rc=0
HDR='#!/usr/bin/env bash\n# Purpose : x\n# Usage   : x\n# Exit    : x\n'
build() { # $1 root
  local r="$1/scripts/label-sync/render" d="$1/docs/label-sync" f
  mkdir -p "$r/tests" "$d"
  for f in lib.sh statusline.sh title.sh shell-hook.sh tmux-status.sh labelrun watch-labels.sh prove_mutations.sh tests/test_render.sh; do
    printf "$HDR"'# STDIN\n:\n' >"$r/$f"; chmod +x "$r/$f"
  done
  printf "$HDR"':\n' >"$r/shell-integration.bash"
  echo '# zsh' >"$r/shell-integration.zsh"; echo '# fish' >"$r/shell-integration.fish"
  echo 'statusLine OSC labelrun PROMPT_COMMAND status-right UNCONFIRMED' >"$d/RENDERERS.md"
}
expect() { # want(pass|fail) desc root
  if bash "$GATE" --root "$3" --structural-only --quiet >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "✅ META OK:   $2 — gate ${got}ed as required"
  else echo "❌ META FAIL: $2 — gate ${got}ed, wanted $1"; rc=1; fi
}
R() { echo "$1/scripts/label-sync/render"; }
build "$TMP/clean"; expect pass "clean fixture" "$TMP/clean"
r="$TMP/m1"; build "$r"; rm "$(R "$r")/statusline.sh"; expect fail "statusline.sh missing" "$r"
r="$TMP/m2"; build "$r"; chmod -x "$(R "$r")/labelrun"; expect fail "labelrun not executable" "$r"
r="$TMP/m3"; build "$r"; printf '#!/usr/bin/env bash\n# STDIN\n:\n' >"$(R "$r")/title.sh"; expect fail "title.sh lacks header" "$r"
r="$TMP/m4"; build "$r"; printf 'if then fi ((\n' >>"$(R "$r")/shell-hook.sh"; expect fail "shell-hook.sh syntax error" "$r"
r="$TMP/m5"; build "$r"; rm "$r/docs/label-sync/RENDERERS.md"; expect fail "RENDERERS.md missing" "$r"
r="$TMP/m6"; build "$r"; sed -i 's/UNCONFIRMED//' "$r/docs/label-sync/RENDERERS.md"; expect fail "RENDERERS.md lacks UNCONFIRMED" "$r"
r="$TMP/m7"; build "$r"; sed -i 's/STDIN//' "$(R "$r")/shell-hook.sh"; expect fail "shell-hook.sh drops STDIN policy" "$r"
r="$TMP/m8"; build "$r"; echo 'x --cmd "$BASH_COMMAND"' >>"$(R "$r")/shell-integration.bash"; expect fail "command text passed as argument" "$r"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
