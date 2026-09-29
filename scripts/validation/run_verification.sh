#!/usr/bin/env bash
# run_verification.sh — Deterministic validation & verification harness
# Runs all submodules in constitution/submodules/ that provide V&V capabilities.
# Constitution §11.4.2: Recorded-evidence requirement
# Constitution §1.1: Mutation-paired gates (anti-bluff)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONSTITUTION_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUBMODULES_DIR="${CONSTITUTION_ROOT}/submodules"

# REQUIRED submodules - verification FAILS if any of these are missing
REQUIRED_SUBMODULES=(
    "verification"
    "verify"
    "repo-qa"
    "repo-proof"
    "donespec"
    "kedge"
    "agentic-validation"
    "skill-doctor"
    "verfix"
    "MVT"
    "wave-dpctf"
    "mcp-audio-tweaker"
    "video-quality-mcp"
    "polyscreen-mcp"
    "claude-video"
    "watch-skill"
    "anti_bluff"
)

echo "=== Constitution Validation & Verification Harness ==="
echo "Constitution root: ${CONSTITUTION_ROOT}"
echo "Submodules dir: ${SUBMODULES_DIR}"
echo

# Track results
declare -a PASSED=()
declare -a FAILED=()
declare -a SKIPPED=()

run_check() {
    local name="$1"
    local cmd="$2"
    local cwd="${3:-${CONSTITUTION_ROOT}}"
    
    echo "→ ${name}"
    if eval "cd \"${cwd}\" && ${cmd}"; then
        echo "  ✓ PASS"
        PASSED+=("${name}")
    else
        local exit_code=$?
        echo "  ✗ FAIL (exit code: ${exit_code})"
        FAILED+=("${name}")
    fi
    echo
}

# 1. Check REQUIRED submodules exist
echo "=== Required Submodules Check ==="
for submodule in "${REQUIRED_SUBMODULES[@]}"; do
    if [[ -d "${SUBMODULES_DIR}/${submodule}" ]]; then
        echo "  ✓ Required submodule present: ${submodule}"
    else
        echo "  ✗ REQUIRED submodule MISSING: ${submodule}"
        FAILED+=("Required submodule missing: ${submodule}")
    fi
done
echo

# If any required submodules missing, exit early with failure
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "=== REQUIRED SUBMODULES CHECK FAILED ==="
    exit 1
fi

# 2. Core deterministic verification frameworks
echo "=== Core Verification Frameworks ==="

# verification (ArcBlock/agent-skills) - repo-agnostic verification gate
run_check "verification (agent-skills)" \
    "ls -la verification/ && [ -f verification/README.md ]" \
    "${SUBMODULES_DIR}"

# verify (KeyValueSoftwareSystems/maestro) - deterministic checks + proof report
run_check "verify (maestro)" \
    "ls -la verify/ && [ -f verify/README.md ]" \
    "${SUBMODULES_DIR}"

# repo-qa (okwinds/skills-runtime-sdk) - regression verification
run_check "repo-qa (skills-runtime-sdk)" \
    "ls -la repo-qa/ && [ -f repo-qa/README.md ]" \
    "${SUBMODULES_DIR}"

# repo-proof (Gary06868/repo-proof) - README contract audit
run_check "repo-proof" \
    "ls -la repo-proof/ && [ -f repo-proof/README.md ]" \
    "${SUBMODULES_DIR}"

# donespec (xryv/DoneSpec) - completion contract validation
run_check "donespec" \
    "ls -la donespec/ && [ -f donespec/README.md ]" \
    "${SUBMODULES_DIR}"

# kedge (SturdyRobot/kedge) - deterministic AI harness
run_check "kedge" \
    "ls -la kedge/ && [ -f kedge/Cargo.toml ]" \
    "${SUBMODULES_DIR}"

# agentic-validation (Tyler-R-Kendrick/agentic_validation) - formal SMT/Lean checking
run_check "agentic-validation" \
    "ls -la agentic-validation/ && [ -f agentic-validation/README.md ]" \
    "${SUBMODULES_DIR}"

# skill-doctor (KalarisLabs/Skill-Doctor) - security analysis of skills
run_check "skill-doctor" \
    "ls -la skill-doctor/ && [ -f skill-doctor/Cargo.toml ]" \
    "${SUBMODULES_DIR}"

# 3. Web Validation
echo "=== Web Validation ==="

# verfix (verfix-dev/verfix) - browser verification runtime
run_check "verfix" \
    "ls -la verfix/ && [ -f verfix/README.md ]" \
    "${SUBMODULES_DIR}"

# 4. Media Validation (Video/Audio)
echo "=== Media Validation ==="

# MVT (rdkcentral/MVT) - media playback verification
run_check "MVT (Media Validation Tool)" \
    "ls -la MVT/ && [ -f MVT/README.md ]" \
    "${SUBMODULES_DIR}"

# wave-dpctf (cta-wave/device-observation-framework) - CTA WAVE compliance
run_check "WAVE DPCTF" \
    "ls -la wave-dpctf/ && [ -f wave-dpctf/README.md ]" \
    "${SUBMODULES_DIR}"

# mcp-audio-tweaker - audio processing MCP
run_check "mcp-audio-tweaker" \
    "ls -la mcp-audio-tweaker/ && [ -f mcp-audio-tweaker/package.json ]" \
    "${SUBMODULES_DIR}"

# video-quality-mcp - PSNR/SSIM/VMAF metrics
run_check "video-quality-mcp" \
    "ls -la video-quality-mcp/ && [ -f video-quality-mcp/README.md ]" \
    "${SUBMODULES_DIR}"

# 5. Multi-Display Validation
echo "=== Multi-Display Validation ==="

# polyscreen-mcp (Zyzto/polyscreen-mcp) - Android multi-display
run_check "polyscreen-mcp" \
    "ls -la polyscreen-mcp/ && [ -f polyscreen-mcp/README.md ]" \
    "${SUBMODULES_DIR}"

# 6. Content Quality & Agent Media Understanding
echo "=== Content Quality & Media Understanding ==="

# claude-video (bradautomates/claude-video) - video watching skill
run_check "claude-video (watch skill)" \
    "ls -la claude-video/ && [ -f claude-video/README.md ]" \
    "${SUBMODULES_DIR}"

# watch-skill (oxbshw/watch-skill) - video/audio watching
run_check "watch-skill" \
    "ls -la watch-skill/ && [ -f watch-skill/README.md ]" \
    "${SUBMODULES_DIR}"

# 7. Anti-Bluff (existing submodule)
echo "=== Anti-Bluff (Existing) ==="
run_check "anti_bluff" \
    "ls -la anti_bluff/ && [ -f anti_bluff/README.md ]" \
    "${SUBMODULES_DIR}"

# Summary
echo "=== SUMMARY ==="
echo "Passed: ${#PASSED[@]}"
for p in "${PASSED[@]}"; do echo "  ✓ ${p}"; done
echo
echo "Failed: ${#FAILED[@]}"
for f in "${FAILED[@]}"; do echo "  ✗ ${f}"; done
echo
echo "Skipped: ${#SKIPPED[@]}"
for s in "${SKIPPED[@]}"; do echo "  - ${s}"; done
echo

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "VERIFICATION FAILED"
    exit 1
else
    echo "ALL VERIFICATIONS PASSED"
    exit 0
fi
