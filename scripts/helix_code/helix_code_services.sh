#!/usr/bin/env bash
# ============================================================================
# helix_code_services.sh — install / boot / health wrappers for HelixCode
#
# Purpose:    Phase 1 Task 1.2 of INTEGRATION_PLAN.md. Provides thin wrappers
#             around the HelixCode clone's own installer + compose stack +
#             health probes. SOURCED library — consumers do:
#               source helix_code_home.sh
#               source helix_code_services.sh
#               hc_install && hc_boot_coder && hc_health localhost 18434
#
# Usage:      source constitution/scripts/helix_code/helix_code_services.sh
#             hc_install [--flags]     # delegates to install_helix_path.sh
#             hc_boot_service <name>   # boot a service via compose
#             hc_boot_coder            # boot the HelixLLM coder on :18434
#             hc_stop_service <name>   # stop a service
#             hc_status                # print status of all HelixCode services
#             hc_health_url <url>      # scheme-aware health probe (OK|DOWN)
#
# Dependencies: helix_code_home.sh (must be sourced first), bash, curl, docker/podman.
# Anti-bluff (§11.4.6): every function checks preconditions from captured state,
#             never assumes "it probably works."
# Cross-references: docs/helix_code/INTEGRATION_PLAN.md §3 Tasks 1.2-1.3,
#             docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md §1-2,
#             Constitution §11.4.6, §11.4.161 (rootless podman).
# Revision:   2
# Last modified: 2026-09-03T00:00:00Z
# ============================================================================
set -euo pipefail

# Guard: do not re-source if already loaded
[ "${_HELIX_CODE_SERVICES_LOADED:-0}" = "1" ] && return 0
_HELIX_CODE_SERVICES_LOADED=1

# Require helix_code_home.sh to be sourced first
if [ "${_HELIX_CODE_HOME_LOADED:-0}" != "1" ]; then
  echo "[helix_code_services] ERROR: source helix_code_home.sh first" >&2
  return 1 2>/dev/null || exit 1
fi

# --- internal helpers --------------------------------------------------------

# Resolve the HelixCode compose file path
hc__compose_file() {
  local home; home="$(hc_home)"
  local f="$home/compose.helixcode-infra.yml"
  if [ ! -f "$f" ]; then
    echo "[helix_code_services] WARN: compose file not found at $f" >&2
    return 1
  fi
  printf '%s' "$f"
}

# Resolve the Containers submodule deploy-stack script
hc__deploy_stack() {
  local home; home="$(hc_home)"
  local ds="$home/submodules/containers/deploy-stack"
  if [ ! -x "$ds" ]; then
    echo "[helix_code_services] WARN: deploy-stack not found at $ds" >&2
    return 1
  fi
  printf '%s' "$ds"
}

# --- public API --------------------------------------------------------------

# Install HelixCode binaries via the clone's own installer.
# Delegates to install_helix_path.sh (HC/install_helix_path.sh:29-30).
# Usage: hc_install [--flags]   (flags passed through to install_helix_path.sh)
hc_install() {
  local home; home="$(hc_home)"
  local installer="$home/install_helix_path.sh"
  if [ ! -f "$installer" ]; then
    echo "[helix_code_services] ERROR: installer not found at $installer" >&2
    return 1
  fi
  echo "[helix_code_services] Installing HelixCode binaries from $home ..." >&2
  HELIX_REPO_ROOT="$home" bash "$installer" "$@"
}

# Boot a HelixCode service via the Containers submodule compose stack.
# Usage: hc_boot_service <service-name>
# §11.4.161: uses rootless podman via the Containers submodule.
hc_boot_service() {
  local svc="${1:?usage: hc_boot_service <service-name>}"
  local home; home="$(hc_home)"
  local compose; compose="$(hc__compose_file)" || return 1
  local deploy; deploy="$(hc__deploy_stack)" || return 1

  echo "[helix_code_services] Booting service '$svc' ..." >&2
  "$deploy" \
    --env "$home/.env" \
    --host-index 1 \
    --compose "$compose" \
    --remote-dir "helix-$svc" \
    2>&1 || {
    echo "[helix_code_services] ERROR: failed to boot $svc" >&2
    return 1
  }
}

# Boot the HelixLLM coder (the multi-track "live sink" on :18434).
# Per §11.4.119 single-owner, ONLY one track owns the GPU coder.
# Usage: hc_boot_coder
hc_boot_coder() {
  echo "[helix_code_services] Booting HelixLLM coder on :18434 ..." >&2
  hc_boot_service "coder" || return 1
  # Wait for health
  local retries=10
  while [ $retries -gt 0 ]; do
    if hc_health localhost 18434 2>/dev/null; then
      echo "[helix_code_services] Coder healthy on :18434" >&2
      return 0
    fi
    retries=$((retries - 1))
    sleep 2
  done
  echo "[helix_code_services] WARN: coder not healthy after 20s" >&2
  return 1
}

# Stop a HelixCode service.
# Usage: hc_stop_service <service-name>
hc_stop_service() {
  local svc="${1:?usage: hc_stop_service <service-name>}"
  local home; home="$(hc_home)"
  echo "[helix_code_services] Stopping service '$svc' ..." >&2
  # Containers submodule teardown
  if command -v podman >/dev/null 2>&1; then
    podman compose -f "$(hc__compose_file)" down "$svc" 2>&1 || true
  elif command -v docker >/dev/null 2>&1; then
    docker compose -f "$(hc__compose_file)" down "$svc" 2>&1 || true
  fi
}

# Health-probe a FULL url, so the scheme is part of the declaration instead of
# being assumed. hc_health() (helix_code_home.sh) hardcodes http:// and therefore
# reported the TLS gateway as DOWN while it was serving: measured 2026-09-03,
# http://localhost:8443/internal/health answered 400 and
# https://localhost:8443/internal/health answered 200. Left hc_health() alone —
# it is public API with existing callers; this is additive.
# `-k` is applied ONLY to https on a loopback host: those listeners present a
# self-signed certificate (measured 2026-09-03: curl exit 60, "self-signed
# certificate (18)"), and a loopback peer cannot be MITM'd by a network
# attacker. Any non-loopback https URL is verified normally.
# Usage: hc_health_url <url>   -> prints OK|DOWN, returns 0 only on OK
hc_health_url() {
  local url="${1:?usage: hc_health_url <url>}"
  local -a insecure=()
  case "$url" in
    https://localhost[:/]*|https://127.0.0.1[:/]*|https://\[::1\][:/]*) insecure=(-k) ;;
  esac
  if curl -fsS "${insecure[@]+"${insecure[@]}"}" --max-time 5 "$url" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "DOWN"
    return 1
  fi
}

# Canonical endpoint table for hc_status — the SINGLE place any HelixCode
# service address is written. One `label|url` row per service; the operator
# label's `(:port)` and the probed URL are both derived from that one row, so
# they cannot drift apart (they did: the row below for HelixAgent named :8100,
# which is the LLMsVerifier's port, so hc_status reported "HelixAgent: DOWN"
# for a service that was UP on :7061 — a false negative in an operator-facing
# tool). Rows carry a full URL rather than a bare port so a cross-checking
# guard reads scheme + port + path, not just a number.
#
# Ports are literals here ON PURPOSE, and this is the one place they may be:
#   * these rows ARE a declaration source that the consuming project's
#     endpoint-agreement guard parses and cross-checks against the tracked
#     systemd units. Replacing them with ${VAR:-default} indirection removes
#     the parseable literal and silently deletes that cross-check.
#   * there is no canonical port registry either repo exposes to derive from,
#     and reaching into a consuming project's tree for one is exactly the
#     coupling §11.4.28(B) forbids a submodule to introduce.
# A consumer running a different topology overrides the whole table by
# defining hc__status_endpoints() before sourcing this file.
# Verified against scripts/systemd/*.service + live `ss -ltnp` on 2026-09-03.
if ! declare -F hc__status_endpoints >/dev/null 2>&1; then
hc__status_endpoints() {
  cat <<'HC_ROWS'
HelixCode server|http://localhost:8080/health
HelixLLM coder|http://localhost:18434/health
HelixLLM gateway|https://localhost:8443/internal/health
HelixAgent|http://localhost:7061/v1/models
LLMsVerifier|http://localhost:8100/health
HC_ROWS
}
fi

# Print status of all HelixCode services.
# Usage: hc_status
hc_status() {
  local home; home="$(hc_home)"
  echo "=== HelixCode Service Status ==="
  echo "Home: $home"
  echo "Mode: ${HELIX_CODE_MODE:-local}"
  echo ""
  local row label url port state
  while IFS='|' read -r label url; do
    [ -n "${label:-}" ] || continue
    # port straight out of the row's URL — never a second literal to keep in sync
    port="${url#*://}"; port="${port#*:}"; port="${port%%/*}"
    # hc_health_url prints exactly one word; no `|| echo DOWN` fallback, which
    # is what made a failing row print BOTH "FAIL" and "DOWN" on two lines.
    state="$(hc_health_url "$url" 2>/dev/null)" || true
    printf '%-27s%s\n' "$label (:$port):" "${state:-DOWN}"
  done < <(hc__status_endpoints)
}

# Verify all installed binaries are on PATH.
# Usage: hc_verify_binaries
hc_verify_binaries() {
  local bins="helixcode helixagent helixllm llm-verifier helixqa helixcli"
  local ok=0 fail=0
  for b in $bins; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "  $b: $(command -v "$b")"
      ok=$((ok + 1))
    else
      echo "  $b: NOT FOUND"
      fail=$((fail + 1))
    fi
  done
  echo "Binaries: $ok found, $fail missing"
  [ $fail -eq 0 ]
}
