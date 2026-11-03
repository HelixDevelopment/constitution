#!/usr/bin/env bash
# cm_decisions_override_valid.sh — CM-DECISIONS-OVERRIDE-VALID gate (decisions wizard; §11.4.35, §11.4.279-§11.4.286).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A project's local decision overrides (.constitution/decisions.yml) MUST inherit from the constitution and
# never weaken it: closed key set, locked rules kept or tightened, no contradictions, no secret-like values,
# no edit outside the wizard (sha sidecar, provenance only), and managed blocks in CLAUDE.md/AGENTS.md/GEMINI.md/QWEN.md
# that match the file exactly (a drifted or missing block is a FAIL).
# The gate re-implements nothing: it calls the wizard's own `--check`. Before trusting that answer it runs the
# same wizard on built-in golden-good and golden-bad fixtures (control needles, §11.4.273): if the instrument
# cannot tell them apart the result is BLIND, never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_decisions_override_valid.sh [--root <project-root>]     (default: current directory)
#   Env: DECISIONS_CLI (path to constitution_decisions.sh; default: the one next to this gate).
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL (incl. a stale managed block with no override file) · 2 BLIND (wizard missing, needles failed,
#   unexpected wizard exit) · 3 SKIP (no override file and no managed block)
#   · 64 usage error.
#
# ── Side-effects / dependencies ───────────────────────────────────────────
#   Read-only on the project; fixtures live in a mktemp -d removed with safe_rm_rf. bash, python3, PyYAML.
#   Paired mutation test: cm_decisions_override_valid_mutation_test.sh. Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-DECISIONS-OVERRIDE-VALID"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
cli="${DECISIONS_CLI:-$const/scripts/decisions/constitution_decisions.sh}"
root="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root needs a value" >&2; exit 64; }; root="$2"; shift 2 ;;
    -h|--help) sed -n 2,21p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -x "$cli" ] || { echo "⚠ $GATE: BLIND (exit 2) — wizard missing: $cli"; exit 2; }
# shellcheck source=../lib/safe_rm.sh
. "$const/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_dec_valid.XXXXXX")" || { echo "⚠ $GATE: BLIND — mktemp failed"; exit 2; }
trap 'safe_rm_rf "${tmp:?}"' EXIT
export CONSTITUTION_DECISIONS_USER_FILE="$tmp/user.yml"
needle() { # $1 name, $2 expected rc, $3 decisions body ('' = good), $4 sidecar mode (match|none)
  local p="$tmp/$1"; mkdir -p "$p/.constitution"
  printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n%s' "$3" >"$p/.constitution/decisions.yml"
  [ "$4" = match ] && sha256sum "$p/.constitution/decisions.yml" | cut -d' ' -f1 >"$p/.constitution/decisions.sha256"
  "$cli" --project-root "$p" --check >/dev/null 2>&1; local rc=$?
  [ "$rc" = "$2" ] || { echo "⚠ $GATE: BLIND (exit 2) — control needle '$1' gave rc=$rc, want $2"; exit 2; }
}
needle good 0 '  calibration.floor: 0.95
' match
needle bad_floor 4 '  calibration.floor: 0.5
' match
needle bad_locked 4 '  hosted.enforce: true
' match
needle bad_unknown 4 '  bogus.key: 1
' match
needle bad_secret 4 "  llmctl.download_profile: sk-$(printf 'Q%.0s' $(seq 1 30))
" match
needle bad_tamper 4 '  calibration.floor: 0.96
' none
# drift needle: a valid file whose CLAUDE.md block no longer matches it (review I3)
needle bad_drift 0 '  calibration.floor: 0.97
' match
printf '# D\n<!-- BEGIN constitution-decisions -->\nstale\n<!-- END constitution-decisions -->\n' >"$tmp/bad_drift/CLAUDE.md"
"$cli" --project-root "$tmp/bad_drift" --check >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] || { echo "⚠ $GATE: BLIND (exit 2) — control needle 'bad_drift' gave rc=$rc, want 4"; exit 2; }
# orphan needle: no decisions.yml but a stale managed block in a doc (review round 3, I-2) must be rc 4
mkdir -p "$tmp/bad_orphan"
printf '# O\n<!-- BEGIN constitution-decisions -->\nstale\n<!-- END constitution-decisions -->\n' >"$tmp/bad_orphan/CLAUDE.md"
"$cli" --project-root "$tmp/bad_orphan" --check >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] || { echo "⚠ $GATE: BLIND (exit 2) — control needle 'bad_orphan' gave rc=$rc, want 4"; exit 2; }
f="$root/.constitution/decisions.yml"
out="$("$cli" --project-root "$root" --check 2>&1)"; rc=$?
# no decisions file: a stale managed block is a FAIL; nothing at all is an honest SKIP (never a silent PASS)
if [ ! -f "$f" ] && [ "$rc" = 0 ]; then echo "↷ $GATE: SKIP (exit 3) — no .constitution/decisions.yml and no managed block in $root"; exit 3; fi
case "$rc" in
  0) echo "✓ $GATE: PASS — $out"; exit 0 ;;
  4) echo "✗ $GATE: FAIL — $out"; exit 1 ;;
  *) echo "⚠ $GATE: BLIND (exit 2) — wizard --check rc=$rc: $out"; exit 2 ;;
esac
