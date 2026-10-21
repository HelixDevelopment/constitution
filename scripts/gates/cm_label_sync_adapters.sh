#!/usr/bin/env bash
# cm_label_sync_adapters.sh — CM-LABEL-SYNC-ADAPTERS gate for the §11.4.182
# label-sync CLI-agent adapters (scripts/label-sync/adapters/).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts the adapters are present, documented HONESTLY and genuinely working:
#   (1) STRUCTURAL (always; fixture-mutation-tested):
#       (a) every adapter file exists; every *.sh is executable and carries a
#           §11.4.18 header (Purpose:/Usage:/Exit)
#       (b) docs/label-sync/ADAPTERS.md exists, and for EACH agent in
#           {kimi opencode crush aider codex gemini qwen cursor} carries a
#           capability row using the closed vocabulary TESTED|SCHEMA-ONLY|UNCONFIRMED
#       (c) anti-bluff: every row claiming TESTED names its evidence script
#           (test_real_agents.sh or test_adapters.sh); every UNCONFIRMED row names
#           the guaranteed fallback `label-agent-run.sh`
#       (d) install_adapters.sh defaults to dry-run (`mode=dry-run`) and the
#           _edit_config.py backs up before writing (`label-sync.bak`)
#   (2) RUNTIME (skipped with --structural-only; honest SKIP when jq/python3 absent):
#       (e) adapters/tests/test_adapters.sh (hermetic suite) exits 0
#       (f) install_adapters.sh --home <tmp> default run writes nothing
#       (g) with --real: adapters/tests/test_real_agents.sh exits 0 (heavy; starts
#           the installed agents in sandboxes — run alone, niced)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_adapters.sh [--root <constitution-root>] [--structural-only] [--real] [--quiet]
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT env override for --root (arg wins).
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines and a summary.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Runtime checks use temp dirs only (HOME poisoned, removed on exit); --real
#   additionally starts sandboxed agent processes it kills by pid.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep; jq + python3 (+PyYAML) + labelctl build for runtime.
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.182, §11.4.228, §11.4.18, §1.1 (paired mutation), §11.4.201, §11.4.3.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 all checks PASS (runtime may SKIP) | 1 a check FAILed | 2 environment error.
# Classification: universal (§11.4.17).
set -uo pipefail

GATE="CM-LABEL-SYNC-ADAPTERS"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""; structural=""; real=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    --structural-only) structural=1; shift ;;
    --real) real=1; shift ;;
    -h|--help) sed -n '1,48p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "${GATE}: root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
ad="$root/scripts/label-sync/adapters"
doc="$root/docs/label-sync/ADAPTERS.md"
fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }
need() { local d="$1"; shift; if "$@"; then say "✅ PASS     $d"; else warn "❌ FAIL     $d"; fail=1; fi; }

FILES="lib/adapter_lib.sh lib/label-adapter-event.sh generic/label-agent-run.sh kimi/kimi-hook.sh crush/crush-hook.sh aider/aider-notify.sh aider/aider-labelled.sh codex/codex-notify.sh gemini/gemini-hook.sh qwen/qwen-hook.sh install_adapters.sh tests/test_adapters.sh tests/test_real_agents.sh"
for f in $FILES; do
  need "adapters/$f present + executable" test -x "$ad/$f"
  need "adapters/$f §11.4.18 header (Purpose/Usage/Exit)" bash -c "[ -f '$ad/$f' ] && grep -q '^# Purpose' '$ad/$f' && grep -q '^# Usage' '$ad/$f' && grep -q '^# Exit' '$ad/$f'"
done
for f in opencode/label-sync.mjs _edit_config.py tests/fake_openai.py; do
  need "adapters/$f present" test -s "$ad/$f"
  need "adapters/$f documents Purpose/Usage/Exit" bash -c "[ -f '$ad/$f' ] && grep -q 'Purpose' '$ad/$f' && grep -q 'Usage' '$ad/$f' && grep -q 'Exit' '$ad/$f'"
done
need "prove_adapter_mutations.sh present" test -f "$root/scripts/label-sync/prove_adapter_mutations.sh"
need "docs/label-sync/ADAPTERS.md present" test -f "$doc"
for agent in kimi opencode crush aider codex gemini qwen cursor; do
  need "ADAPTERS.md has a capability row for '$agent' (TESTED|SCHEMA-ONLY|UNCONFIRMED)" \
    bash -c "grep -E '^\\| .*\\*\\*$agent\\*\\*.*\\*\\*(TESTED|SCHEMA-ONLY|UNCONFIRMED)\\*\\*' '$doc' >/dev/null"
done
# anti-bluff (c): TESTED rows cite their evidence; UNCONFIRMED rows cite the fallback
need "every TESTED row cites test evidence (test_real_agents.sh / test_adapters.sh / 'real ')" \
  bash -c "! grep -E '^\\| .*\\*\\*TESTED\\*\\*' '$doc' | grep -vqE 'test_real_agents|test_adapters|real (kimi|opencode|crush|aider)|hermetic'"
need "every UNCONFIRMED capability row names the label-agent-run.sh fallback or 'wrapper'" \
  bash -c "! grep -E '^\\| .*\\*\\*UNCONFIRMED\\*\\*' '$doc' | grep -vqE 'wrapper|label-agent-run'"
need "ADAPTERS.md states how each level is determined (closed vocabulary section)" \
  bash -c "grep -q 'Capability vocabulary' '$doc' && grep -q 'UNCONFIRMED' '$doc'"
need "install_adapters.sh defaults to dry-run" grep -q 'mode=dry-run' "$ad/install_adapters.sh"
need "_edit_config.py backs up before writing" grep -q 'label-sync.bak' "$ad/_edit_config.py"
need "_edit_config.py refuses invalid files (Refused('invalid'))" grep -q 'Refused("invalid"' "$ad/_edit_config.py"

if [ -n "$structural" ]; then
  warn "⚠️  SKIP     runtime checks (--structural-only — honest skip, §11.4.3)"
elif ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  warn "⚠️  SKIP     runtime checks (jq/python3 absent — honest skip, §11.4.3)"
else
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync_ad.XXXXXX")"
  trap 'rm -rf "$TMPD"' EXIT
  if nice -n 10 bash "$ad/tests/test_adapters.sh" >"$TMPD/hermetic.log" 2>&1; then
    say "✅ PASS     hermetic suite: $(tail -1 "$TMPD/hermetic.log")"
  else
    warn "❌ FAIL     hermetic suite — failures:"; grep '^FAIL' "$TMPD/hermetic.log" | head -10; fail=1
  fi
  h="$TMPD/home"; mkdir -p "$h"
  out="$(bash "$ad/install_adapters.sh" --home "$h" --agents kimi,opencode,crush,aider,codex,gemini,qwen 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && [ -z "$(find "$h" -type f -print -quit)" ] && printf '%s' "$out" | grep -q 'DRY-RUN'; then
    say "✅ PASS     install_adapters.sh default run is a dry-run that wrote nothing"
  else
    warn "❌ FAIL     install_adapters.sh default run wrote files or failed (rc=$rc)"; fail=1
  fi
  if [ -n "$real" ]; then
    if nice -n 10 bash "$ad/tests/test_real_agents.sh" >"$TMPD/real.log" 2>&1; then
      say "✅ PASS     real-agent suite: $(tail -1 "$TMPD/real.log")"
    else
      warn "❌ FAIL     real-agent suite — failures:"; grep -E '^FAIL' "$TMPD/real.log" | head -10; fail=1
    fi
  else
    say "ℹ️  NOTE     real-agent suite not run (pass --real; heavy, starts installed agents in sandboxes)"
  fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then echo "❌ ${GATE}: FAIL"; exit 1; fi
echo "✅ ${GATE}: PASS — label-sync adapters present, honestly documented and working"
exit 0
