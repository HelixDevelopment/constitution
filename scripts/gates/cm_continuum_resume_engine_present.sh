#!/usr/bin/env bash
# cm_continuum_resume_engine_present.sh — CM-CONTINUUM-RESUME-ENGINE-PRESENT
# gate for §11.4.207 (instant multi-stream resume engine — continuum).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.207 requires the continuum instant-resume engine to be present as a
# depth-1 reusable-engine submodule under `constitution/submodules/continuum/`
# per the §11.4.28(C) carve-out, carrying ZERO project literals and declaring
# ZERO own-org dependencies (`helix-deps.yaml`). This gate asserts, against a
# given constitution-submodule root:
#
#   (1) STRUCTURAL (always enforced, fixture-mutation-tested):
#       (a) the engine directory exists at <root>/submodules/continuum
#       (b) it carries a real `go.mod` (a `module ` declaration)
#       (c) it carries `helix-deps.yaml` declaring zero own-org deps
#           (`deps: []`) per §11.4.31/§11.4.28(C)
#       (d) it carries ZERO project-specific literals (a closed denylist of
#           obviously project-particular tokens — project names, hardware
#           vendor names, absolute project mount paths) anywhere under its
#           tracked *.go / *.md / *.yaml files, per §11.4.6/§11.4.177.
#
#   (2) RUNTIME (best-effort enhancement, SKIPs honestly when infeasible —
#       §11.4.3 — never silently upgraded to a false PASS, never silently
#       downgraded to a false FAIL when genuinely unavailable):
#       (e) IF the engine has at least one `*_test.go` file AND the `go`
#           toolchain is on PATH: `go test -race ./...` inside the engine
#           dir MUST exit 0 (the race-clean four-layer-coverage claim).
#       (f) IF the engine has a `cmd/continuum` main AND `go` is on PATH:
#           `go run ./cmd/continuum selfcheck` MUST print all three of
#           `good=PASS`, `bad=FAIL`, `negctrl=PASS` (the self-validating
#           oracle proof per §11.4.107(10)).
#
# The mutation test only exercises (1) — the structural invariants — because
# those are the ones a throwaway fixture can prove/disprove hermetically and
# fast; (2) activates only against the REAL engine (which does carry real
# _test.go files + a real cmd/continuum/selfcheck), matching the two-speed
# gating pattern of §11.4.110 (grep-speed always-on vs REQUIRES_BUILD
# opt-in-by-content heavy checks).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_continuum_resume_engine_present.sh [--root <constitution-root>] [--quiet]
#     --root <dir>   constitution-submodule root (default: this script's
#                    grandparent dir, i.e. constitution/scripts/gates/../..)
#     --quiet        suppress verbose per-check PASS lines (FAIL/SKIP always shown)
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT  env override for --root (arg takes precedence).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines + a final summary; nonzero exit on any
#   FAILed check (SKIPs never fail the gate by themselves).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only except for runtime checks (2), which may invoke `go test` /
#   `go run` INSIDE the engine directory only (never elsewhere, never network
#   beyond whatever the engine's own module resolution needs — the real
#   engine is Go-stdlib-only per its helix-deps.yaml, so no network is used).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX find + grep; optionally `go` for the enhanced runtime checks.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.207 (the anchor this gate enforces), §11.4.28(C) (depth-1 carve-out),
#   §11.4.31 (helix-deps.yaml schema), §11.4.6 / §11.4.177 (zero project
#   literals, fails closed), §11.4.107(10) (self-validated oracle), §11.4.85
#   (race-clean stress/chaos coverage), §11.4.110 (two-speed gating), §1.1
#   (paired mutation on the structural checks).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every structural check PASSes (runtime checks PASS or honestly SKIP).
#   1 — a structural check FAILed, OR a runtime check ran and FAILed.
#   2 — environment error (root not found).
#
# Classification: universal (§11.4.17) — no project-specific data; the
# denylist in check (d) names ATMOSphere-particular tokens ONLY as the
# consuming project's own negative-space assertion (the engine must NOT
# contain them) — the gate mechanism itself is project-agnostic.

set -uo pipefail

GATE="CM-CONTINUUM-RESUME-ENGINE-PRESENT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)  root="$2"; shift 2 ;;
        --quiet) quiet="1"; shift ;;
        -h|--help) sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: constitution root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
engine_dir="${root}/submodules/continuum"

fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }

# --- (1a) directory exists ---
if [ -d "$engine_dir" ]; then
    say "✅ PRESENT  engine directory: ${engine_dir#"$root"/}"
else
    warn "❌ MISSING  engine directory: submodules/continuum (expected under $root)"
    fail=1
fi

# --- (1b) real go.mod ---
if [ -d "$engine_dir" ] && [ -f "${engine_dir}/go.mod" ] && grep -q '^module ' "${engine_dir}/go.mod" 2>/dev/null; then
    say "✅ PRESENT  go.mod (module declared)"
else
    warn "❌ MISSING  submodules/continuum/go.mod (no 'module ' declaration found)"
    fail=1
fi

# --- (1c) helix-deps.yaml with zero own-org deps ---
if [ -d "$engine_dir" ] && [ -f "${engine_dir}/helix-deps.yaml" ] && grep -q 'deps: \[\]' "${engine_dir}/helix-deps.yaml" 2>/dev/null; then
    say "✅ PRESENT  helix-deps.yaml (deps: [] — zero own-org deps, §11.4.28(C))"
else
    warn "❌ MISSING  submodules/continuum/helix-deps.yaml declaring 'deps: []'"
    fail=1
fi

# --- (1d) zero project-specific literals ---
# Closed denylist of ATMOSphere-particular tokens the engine MUST NOT contain
# (case-insensitive). This is this CONSUMING project's own assertion that the
# engine stayed decoupled per §11.4.6/§11.4.177 — the check mechanism itself
# is project-agnostic (a different consumer would supply a different list).
denylist='atmosphere|rockchip|kinopoisk|orange[[:space:]]*pi|/mnt/track'
if [ -d "$engine_dir" ]; then
    hit_files="$(grep -rliE "$denylist" \
        --include='*.go' --include='*.md' --include='*.yaml' --include='*.yml' \
        "$engine_dir" 2>/dev/null || true)"
    if [ -z "${hit_files//[$' \t\r\n']/}" ]; then
        say "✅ PASS     zero project-specific literals under submodules/continuum"
    else
        warn "❌ FOUND    project-specific literal(s) inside the engine (decoupling violation):"
        while IFS= read -r hf; do
            [ -n "$hf" ] && warn "            ${hf#"$root"/}"
        done <<< "$hit_files"
        fail=1
    fi
else
    warn "⚠️  SKIP     zero-literal scan — engine directory absent"
fi

# --- (2e) go test -race ./... (best-effort, honest SKIP when infeasible) ---
has_go_tests=""
if [ -d "$engine_dir" ]; then
    has_go_tests="$(find "$engine_dir" -name '*_test.go' -print -quit 2>/dev/null || true)"
fi
if [ -n "$has_go_tests" ] && command -v go >/dev/null 2>&1; then
    if ( cd "$engine_dir" && go test -race ./... ) >/tmp/cm207_gotest.$$ 2>&1; then
        say "✅ PASS     go test -race ./... (race-clean)"
    else
        warn "❌ FAIL     go test -race ./... — see /tmp/cm207_gotest.$$ for output"
        fail=1
    fi
    rm -f "/tmp/cm207_gotest.$$"
else
    warn "⚠️  SKIP     go test -race ./... — go toolchain absent or no *_test.go files found (honest skip, §11.4.3)"
fi

# --- (2f) continuum selfcheck (best-effort, honest SKIP when infeasible) ---
if [ -d "$engine_dir" ] && [ -f "${engine_dir}/cmd/continuum/main.go" ] && command -v go >/dev/null 2>&1; then
    sc_out="$( cd "$engine_dir" && go run ./cmd/continuum selfcheck 2>&1 || true )"
    # here-strings, not `echo | grep -q`: under pipefail an early-exiting grep can SIGPIPE the producer and turn a
    # passing selfcheck into a false FAIL on large output (SIGPIPE x pipefail class, §11.4.276(C))
    if grep -q 'good=PASS' <<<"$sc_out" && grep -q 'bad=FAIL' <<<"$sc_out" && grep -q 'negctrl=PASS' <<<"$sc_out"; then
        say "✅ PASS     continuum selfcheck — good=PASS bad=FAIL negctrl=PASS"
    else
        warn "❌ FAIL     continuum selfcheck did not report good=PASS/bad=FAIL/negctrl=PASS:"
        warn "$sc_out"
        fail=1
    fi
else
    warn "⚠️  SKIP     continuum selfcheck — go toolchain absent or cmd/continuum/main.go not found (honest skip, §11.4.3)"
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then
    echo "❌ ${GATE}: FAIL — one or more checks failed (see above)"
    exit 1
fi
echo "✅ ${GATE}: PASS — engine present, decoupled, zero own-org deps, zero project literals"
exit 0
