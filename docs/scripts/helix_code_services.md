# helix_code_services.md — Services Guide

**Revision:** 2
**Last modified:** 2026-09-03T00:00:00Z

## Overview

HelixCode service management wrappers: install, boot, stop, health-check, and status
for the HelixCode / HelixLLM / HelixAgent service fleet.

## Prerequisites

- `helix_code_home.sh` sourced first (provides `hc_home()`)
- bash ≥ 4.0
- Docker or Podman (for compose-based services)
- Network access to `github.com:HelixDevelopment/HelixCode.git`

## Quick Start

```sh
source constitution/scripts/helix_code/helix_code_home.sh
source constitution/scripts/helix_code/helix_code_services.sh

# Install binaries
hc_install

# Boot the coder (multi-track live sink)
hc_boot_coder

# Check status
hc_status

# Verify all binaries on PATH
hc_verify_binaries
```

## Functions

| Function | Purpose |
|---|---|
| `hc_install [--flags]` | Install HelixCode binaries via `install_helix_path.sh` |
| `hc_boot_service <name>` | Boot a service via the Containers submodule compose |
| `hc_boot_coder` | Boot the HelixLLM coder on `:18434` (with health wait) |
| `hc_stop_service <name>` | Stop a service |
| `hc_status` | Print health status of every service in the `hc__status_endpoints` table |
| `hc_verify_binaries` | Verify all 6 binaries are on PATH |
| `hc_health [host] [port] [path]` | Health check over `http` only (from `helix_code_home.sh`) |
| `hc_health_url <url>` | Scheme-aware health check; prints `OK` or `DOWN` |

## Service Ports

These are the rows of the `hc__status_endpoints` table in
`helix_code_services.sh` — that table is the single source, this table mirrors
it. Verified against the consuming project's `scripts/systemd/*.service` units
and a live `ss -ltnp` on 2026-09-03.

| Service | Scheme | Port | Health Endpoint |
|---|---|---|---|
| HelixCode server | `http` | `:8080` | `/health` |
| HelixLLM coder | `http` | `:18434` | `/health` |
| HelixLLM gateway | `https` | `:8443` | `/internal/health` |
| HelixAgent | `http` | `:7061` | `/v1/models` |
| LLMsVerifier | `http` | `:8100` | `/health` |

Notes:

- **HelixAgent is `:7061`, not `:8100`.** `:8100` is the **LLMsVerifier's**
  port; a prior revision of this table and of `hc_status` attributed it to
  HelixAgent, so `hc_status` reported "HelixAgent: DOWN" while HelixAgent was
  serving normally. HelixAgent also exposes a liveness probe on `:8111`, but
  that endpoint answers 200 while the service is still starting, so the status
  probe deliberately targets `:7061/v1/models` — the port consumers actually
  call.
- **The gateway is `https`.** `hc_health` hardcodes `http://`, which is why
  `hc_health_url` exists; plain `http` against the TLS listener answers 400.

## Safety

- §11.4.161: uses rootless podman via the Containers submodule
- §11.4.119: single-owner GPU — only one track boots the coder
- §12.6: 60% memory ceiling applies to service boot

## Cross-references

- `docs/helix_code/INTEGRATION_PLAN.md` §3 Tasks 1.2-4
- `docs/helix_code/CLAUDE_TOOLKIT_EXTENSION.md` §1
- `docs/helix_code/RISK_ANALYSIS.md` — port collisions, GPU contention
