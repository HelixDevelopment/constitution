#!/usr/bin/env bash
# scripts/label-sync/mcp/label-mcp.sh
#
# Purpose : Launcher for the label-sync MCP server (label-mcp). Builds the Go
#           binary when missing OR STALE (any *.go / go.mod in the label-sync
#           module newer than the binary), then execs it so stdin/stdout stay the
#           MCP stdio channel. After a constitution pull every consumer therefore
#           runs the current server with no manual build step.
# Usage   : label-mcp.sh            exec the server (stdio JSON-RPC 2.0)
#           label-mcp.sh --build    build only, print the binary path
#           label-mcp.sh --bin      print the binary path, no build
# Inputs  : env LABEL_SYNC_DIR  state dir (default $HOME/.local/state/constitution-label-sync)
#           env LABEL_SYNC_BIN  binary cache dir (default
#                               ${XDG_CACHE_HOME:-$HOME/.cache}/constitution-label-sync/bin)
# Outputs : the server's JSON-RPC on stdout ONLY. Every diagnostic of this
#           launcher goes to stderr (stdout is the protocol channel).
# Exit    : server exit code (0 clean EOF) | 2 cannot determine (no go toolchain
#           and no prebuilt binary, build failed) — 2 is never a pass.
# Side-effects: writes only under the bin cache dir (build; flock-serialised,
#           niced, GOPROXY=off — stdlib-only module, no network).
# Deps    : bash, go (only when a build is needed), find, flock (optional).
# Cross-refs: §11.4.182, §11.4.228(D), §11.4.18, docs/label-sync/MCP.md.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MOD="$(cd "$SELF/.." && pwd)"   # scripts/label-sync (the Go module root)
BIN_DIR="${LABEL_SYNC_BIN:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/constitution-label-sync/bin}"
BIN="$BIN_DIR/label-mcp"

stale() {
  [ -x "$BIN" ] || return 0
  [ -n "$(find "$MOD" \( -name '*.go' -o -name go.mod \) -newer "$BIN" -print -quit 2>/dev/null)" ]
}

build() {
  stale || return 0
  command -v go >/dev/null 2>&1 || { echo "label-mcp.sh: go toolchain not found and binary missing/stale — cannot determine" >&2; return 2; }
  mkdir -p "$BIN_DIR" || return 2
  (
    command -v flock >/dev/null 2>&1 && flock 9
    stale || exit 0
    cd "$MOD" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go build -o "$BIN" ./mcp/label-mcp 1>&2
  ) 9>"$BIN_DIR/.build-mcp.lock" || { echo "label-mcp.sh: build failed" >&2; return 2; }
}

case "${1:-}" in
  --bin) echo "$BIN"; exit 0 ;;
  --build) build || exit $?; echo "$BIN"; exit 0 ;;
esac
build || exit $?
exec "$BIN" "$@"
