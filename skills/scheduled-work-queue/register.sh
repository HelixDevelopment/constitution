#!/usr/bin/env bash
# ============================================================================
# register.sh — Scheduled-Work Queue skill registration
# ============================================================================
# Purpose:
#   Called by post_update_hook.sh to register the scheduled-work-queue skill
#   in the consuming project. Symlinks the skill dir and ensures the engine
#   binary is built so the MCP server is launchable.
#
# Usage:   bash register.sh <project-root>
# Inputs:  $1 — consuming project root directory (default: cwd)
# Outputs: registration steps to stdout; exit 0 on success.
# Side-effects:
#   - Symlinks skills/scheduled-work-queue/ into <project-root>/skills/
#   - Builds scripts/scheduled-work-engine/bin/scheduled-work if go is present.
# Cross-references: §11.4.28 / §11.4.140 / §11.4.164 (auto-propagation hook).
# Last verified: 2026-07-02
# ============================================================================
set -eu

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONST_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL_NAME="scheduled-work-queue"

# Relocation-proof symlink creation (§11.4.111): the link target MUST be stored
# RELATIVE to the link, never as this machine's absolute path — an absolute
# target only resolves on the host that ran the install.
. "${CONST_DIR}/scripts/portable_symlink_lib.sh"

echo "[register.sh] Registering skill: ${SKILL_NAME}"

mkdir -p "${PROJECT_ROOT}/skills"
LINK_TARGET="${PROJECT_ROOT}/skills/${SKILL_NAME}"
if [ -L "$LINK_TARGET" ] || [ ! -e "$LINK_TARGET" ]; then
	hc_ln_relative "$SCRIPT_DIR" "$LINK_TARGET"
	echo "[register.sh]  -> Linked: ${LINK_TARGET} -> $(readlink "$LINK_TARGET")"
else
	echo "[register.sh]  -> ${LINK_TARGET} exists and is not a symlink — skipping"
fi

ENGINE_DIR="${CONST_DIR}/scripts/scheduled-work-engine"
BIN="${ENGINE_DIR}/bin/scheduled-work"
if command -v go >/dev/null 2>&1; then
	echo "[register.sh]  -> Building engine binary"
	( cd "$ENGINE_DIR" && CGO_ENABLED=0 go build -o "$BIN" ./cmd/scheduled-work ) \
		&& echo "[register.sh]  -> Built ${BIN}" \
		|| echo "[register.sh]  -> WARN: engine build failed (build manually before first use)"
else
	echo "[register.sh]  -> WARN: go not found — build ${BIN} before first MCP use"
fi

echo "[register.sh] Registration complete: ${SKILL_NAME}"
