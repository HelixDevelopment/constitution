#!/usr/bin/env bash
# cm_label_sync_adapters_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LABEL-SYNC-ADAPTERS.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a CLEAN disposable fixture root (all structural artefacts, honest
# ADAPTERS.md) that MUST PASS (--structural-only), then applies independent
# mutations on fresh copies, each of which MUST make the gate FAIL:
#   (1) an adapter script missing          (2) an adapter script not executable
#   (3) an adapter script without a §11.4.18 header
#   (4) ADAPTERS.md missing                (5) ADAPTERS.md has no row for `kimi`
#   (6) a row uses a level outside the closed vocabulary (kimi row: "WORKS")
#   (7) a TESTED row with NO evidence reference (the capability BLUFF)
#   (8) an UNCONFIRMED row that omits the wrapper fallback
#   (9) install_adapters.sh no longer defaults to dry-run
#  (10) _edit_config.py no longer backs up   (11) _edit_config.py no longer refuses invalid files
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_adapters_mutation_test.sh
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
GATE="$SCRIPT_DIR/cm_label_sync_adapters.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_ad_mut.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
rc=0
SH="lib/adapter_lib.sh lib/label-adapter-event.sh generic/label-agent-run.sh kimi/kimi-hook.sh crush/crush-hook.sh aider/aider-notify.sh aider/aider-labelled.sh codex/codex-notify.sh gemini/gemini-hook.sh qwen/qwen-hook.sh install_adapters.sh tests/test_adapters.sh tests/test_real_agents.sh"
build() { # $1 root
  local r="$1" a="$1/scripts/label-sync/adapters" d="$1/docs/label-sync" f
  mkdir -p "$d" "$r/scripts/label-sync"
  for f in $SH; do
    mkdir -p "$a/$(dirname "$f")"
    printf '#!/usr/bin/env bash\n# Purpose : x\n# Usage   : x\n# Exit    : x\n' >"$a/$f"; chmod +x "$a/$f"
  done
  echo '# mode=dry-run' >>"$a/install_adapters.sh"; sed -i 's/^# mode=dry-run$/mode=dry-run/' "$a/install_adapters.sh"
  mkdir -p "$a/opencode" "$a/tests"
  printf '// Purpose Usage Exit\n' >"$a/opencode/label-sync.mjs"
  printf '"""Purpose Usage Exit"""\n# label-sync.bak\nraise Refused("invalid", "x")\n' >"$a/_edit_config.py"
  printf '"""Purpose Usage Exit"""\n' >"$a/tests/fake_openai.py"
  echo '#!/usr/bin/env bash' >"$r/scripts/label-sync/prove_adapter_mutations.sh"
  cat >"$d/ADAPTERS.md" <<'DOC'
# ADAPTERS
Capability vocabulary: TESTED, SCHEMA-ONLY, UNCONFIRMED.
| Adapter | Level | How |
|---|---|---|
| **kimi** — hooks | **TESTED** | real kimi run (evidence: `test_real_agents.sh`) |
| **opencode** — plugin | **TESTED** | real opencode serve (evidence: `test_real_agents.sh`) |
| **crush** — PreToolUse | **TESTED** | real crush run (evidence: `test_real_agents.sh`) |
| **aider** — wrapper | **TESTED** | real aider (evidence: `test_real_agents.sh`) |
| **codex** — notify | **UNCONFIRMED** | not installed; fallback: wrapper (`label-agent-run.sh`) |
| **gemini** — hooks | **UNCONFIRMED** | not installed; fallback: wrapper (`label-agent-run.sh`) |
| **qwen** — hooks | **UNCONFIRMED** | not installed; fallback: wrapper (`label-agent-run.sh`) |
| **cursor** — none | **UNCONFIRMED** | no mechanism; wrapper only (`label-agent-run.sh`) |
DOC
}
expect() { # want(pass|fail) desc root
  if bash "$GATE" --root "$3" --structural-only --quiet >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$1" ]; then echo "✅ META OK:   $2 — gate ${got}ed as required"
  else echo "❌ META FAIL: $2 — gate ${got}ed, wanted $1"; rc=1; fi
}
A() { echo "$1/scripts/label-sync/adapters"; }
D() { echo "$1/docs/label-sync/ADAPTERS.md"; }
build "$TMP/clean"; expect pass "clean fixture" "$TMP/clean"
r="$TMP/m1"; build "$r"; rm "$(A "$r")/kimi/kimi-hook.sh"; expect fail "kimi-hook.sh missing" "$r"
r="$TMP/m2"; build "$r"; chmod -x "$(A "$r")/crush/crush-hook.sh"; expect fail "crush-hook.sh not executable" "$r"
r="$TMP/m3"; build "$r"; printf '#!/usr/bin/env bash\n' >"$(A "$r")/aider/aider-notify.sh"; expect fail "aider-notify.sh has no §11.4.18 header" "$r"
r="$TMP/m4"; build "$r"; rm "$(D "$r")"; expect fail "ADAPTERS.md missing" "$r"
r="$TMP/m5"; build "$r"; sed -i '/\*\*kimi\*\*/d' "$(D "$r")"; expect fail "no kimi capability row" "$r"
r="$TMP/m6"; build "$r"; sed -i 's/\*\*kimi\*\* — hooks | \*\*TESTED\*\*/**kimi** — hooks | **WORKS**/' "$(D "$r")"; expect fail "kimi level outside the closed vocabulary" "$r"
r="$TMP/m7"; build "$r"; sed -i 's/real kimi run (evidence: `test_real_agents.sh`)/it just works/' "$(D "$r")"; expect fail "TESTED row without evidence (capability bluff)" "$r"
r="$TMP/m8"; build "$r"; sed -i 's/not installed; fallback: wrapper (`label-agent-run.sh`)/not installed/' "$(D "$r")"; expect fail "UNCONFIRMED row omits the fallback" "$r"
r="$TMP/m9"; build "$r"; sed -i 's/^mode=dry-run$/mode=apply/' "$(A "$r")/install_adapters.sh"; expect fail "installer no longer dry-run by default" "$r"
r="$TMP/m10"; build "$r"; sed -i 's/label-sync.bak//' "$(A "$r")/_edit_config.py"; expect fail "editor no longer backs up" "$r"
r="$TMP/m11"; build "$r"; sed -i 's/Refused("invalid"/Refused("other"/' "$(A "$r")/_edit_config.py"; expect fail "editor no longer refuses invalid files" "$r"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
