#!/usr/bin/env bash
# cm_label_sync_render.sh — CM-LABEL-SYNC-RENDER gate for the label-sync
# RENDERERS (scripts/label-sync/render/, §11.4.182 real-time label display).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts, against a constitution root, that the renderers are present,
# documented, parse-clean and genuinely working:
#   (1) STRUCTURAL (always; fixture-mutation-tested):
#       (a) lib.sh, statusline.sh, title.sh, shell-hook.sh, tmux-status.sh,
#           labelrun, watch-labels.sh, shell-integration.{bash,zsh,fish},
#           prove_mutations.sh and tests/test_render.sh all exist
#       (b) every executable renderer is +x and carries a §11.4.18 header
#           (Purpose / Usage / Exit)
#       (c) every bash renderer passes `bash -n` (§11.4.67 parse-cleanliness —
#           necessary, NOT sufficient: behaviour is (2))
#       (d) shell-hook.sh states the ARGV0-ONLY secret policy, and
#           shell-integration.bash never passes $BASH_COMMAND as an argument nor
#           pipes command text to the helper
#       (e) docs/label-sync/RENDERERS.md exists and names the load-bearing tokens:
#           statusLine OSC labelrun PROMPT_COMMAND status-right UNCONFIRMED
#   (2) RUNTIME (skipped ONLY with an explicit --structural-only, reported as
#       "STRUCTURAL ONLY" — never as a full pass; when jq/go/python3 is absent
#       the gate exits 2 CANNOT DETERMINE, never 0 — §11.4.3 / §11.4.201):
#       (f) tests/test_render.sh exits 0 (statusline / title / shell integration /
#           labelrun / watch / tmux-status behaviour against a temp state dir and
#           a live label-busd; latency + prompt-overhead bounds asserted inside)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_render.sh [--root <constitution-root>] [--structural-only] [--quiet]
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT env override for --root (arg wins).
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines and a summary.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Runtime check uses a temp LABEL_SYNC_DIR (removed on exit) and starts/stops
#   its own label-busd. Never touches ~/.claude* or a real state dir.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep; jq + go + python3 for the runtime check.
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.182, §11.4.116, §11.4.18, §11.4.67, §1.1 (paired mutation), §11.4.201,
#   CM-LABEL-SYNC-CORE (the contract this renders).
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 all checks PASS (with --structural-only: structural checks only, said so)
#   | 1 a check FAILed | 2 cannot determine (missing jq/go/python3, test env
#   error, bad root) — 2 is never a pass.
# Classification: universal (§11.4.17).
set -uo pipefail

GATE="CM-LABEL-SYNC-RENDER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""; structural=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    --structural-only) structural=1; shift ;;
    -h|--help) sed -n '1,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "${GATE}: root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
r="$root/scripts/label-sync/render"
doc="$root/docs/label-sync/RENDERERS.md"

fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }
need() { local d="$1"; shift; if "$@"; then say "✅ PASS     $d"; else warn "❌ FAIL     $d"; fail=1; fi; }
hdr_ok() { grep -q '^# Purpose' "$1" && grep -q '^# Usage' "$1" && grep -q '^# Exit' "$1"; }

ALL="lib.sh statusline.sh title.sh shell-hook.sh tmux-status.sh labelrun watch-labels.sh shell-integration.bash shell-integration.zsh shell-integration.fish prove_mutations.sh tests/test_render.sh"
EXEC="statusline.sh title.sh shell-hook.sh tmux-status.sh labelrun watch-labels.sh prove_mutations.sh tests/test_render.sh"
BASHPARSE="lib.sh statusline.sh title.sh shell-hook.sh tmux-status.sh labelrun watch-labels.sh shell-integration.bash prove_mutations.sh tests/test_render.sh"

for f in $ALL; do need "render/$f present" test -f "$r/$f"; done
for f in $EXEC; do
  need "render/$f executable" test -x "$r/$f"
  need "render/$f §11.4.18 header (Purpose/Usage/Exit)" hdr_ok "$r/$f"
done
for f in $BASHPARSE; do need "render/$f passes bash -n" bash -n "$r/$f"; done
need "shell-hook.sh states the ARGV0-ONLY secret policy" grep -q 'ARGV0-ONLY' "$r/shell-hook.sh"
need "shell-integration.bash never passes \$BASH_COMMAND as an argument" bash -c "! grep -qE -- '--cmd[ =]|cmd-start[^|]*\"\\\$BASH_COMMAND\"|--argv0 \"\\\$BASH_COMMAND\"' '$r/shell-integration.bash'"
need "shell-integration.bash never pipes command text to the helper" bash -c "! grep -qE -- '\\| *\\\$__LS_SETSID +\"\\\$__LS_HOOK\" +cmd-start' '$r/shell-integration.bash'"
need "docs/label-sync/RENDERERS.md present" test -f "$doc"
for tok in statusLine OSC labelrun PROMPT_COMMAND status-right UNCONFIRMED; do
  need "RENDERERS.md names '$tok'" grep -qF -- "$tok" "$doc"
done

undet=""
if [ -n "$structural" ]; then
  warn "⚠️  SKIP     runtime checks (--structural-only requested)"
else
  missing=""
  for t in jq go python3; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
  if [ -n "$missing" ]; then
    warn "❓ UNDET    runtime checks cannot run (missing:$missing) — CANNOT DETERMINE, never a pass"; undet=1
  else
    TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_render.XXXXXX")"
    trap 'rm -rf "$TMPD"' EXIT
    TMPDIR="$TMPD" nice -n 10 bash "$r/tests/test_render.sh" >"$TMPD/render_test.log" 2>&1; trc=$?
    if [ "$trc" -eq 0 ]; then
      say "✅ PASS     tests/test_render.sh: $(grep '^RESULT' "$TMPD/render_test.log")"
      say "           $(grep '^METRIC' "$TMPD/render_test.log" | tr '\n' ' ')"
    elif [ "$trc" -eq 2 ]; then
      warn "❓ UNDET    tests/test_render.sh exit 2 (environment): $(tail -n 2 "$TMPD/render_test.log" | tr '\n' ' ')"; undet=1
    else
      warn "❌ FAIL     tests/test_render.sh (exit $trc) — failing cases:"; grep -E '^FAIL' "$TMPD/render_test.log" | head -15; fail=1
    fi
  fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then echo "❌ ${GATE}: FAIL"; exit 1; fi
if [ -n "$undet" ]; then echo "❓ ${GATE}: CANNOT DETERMINE — structural checks passed, runtime did not run"; exit 2; fi
if [ -n "$structural" ]; then echo "✅ ${GATE}: PASS (STRUCTURAL ONLY — runtime behaviour NOT verified)"; exit 0; fi
echo "✅ ${GATE}: PASS — label-sync renderers present, documented and working"
exit 0
