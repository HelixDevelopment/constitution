#!/usr/bin/env bash
# scripts/label-sync/labelctl.sh
#
# Purpose : Bash entry point for the constitution label-sync system
#           (§11.4.182 labels + real-time sync). Builds the Go binaries
#           `labelctl` and `label-busd` when missing OR STALE (any *.go /
#           go.mod newer than the binary), then execs them. Every consuming
#           project therefore behaves identically after a constitution pull,
#           with no manual build step.
# Usage   : labelctl.sh <labelctl args...>        e.g. labelctl.sh list --text
#           labelctl.sh busd [label-busd args]    run the daemon
#           labelctl.sh --build                   build only, print bin dir
#           labelctl.sh --bin-dir                 print the bin dir, no build
# Inputs  : env LABEL_SYNC_DIR   state dir (default
#                                $HOME/.local/state/constitution-label-sync)
#           env LABEL_SYNC_BIN   binary cache dir (default: PER CHECKOUT,
#                                ${XDG_CACHE_HOME:-$HOME/.cache}/constitution-label-sync/bin-<hash of this
#                                module's path>, see bincache.sh; the binaries are also stale when
#                                the git HEAD differs from the `.source-commit` recorded at build)
#           env LABEL_SYNC_LABELER canonical labeler (default: sibling
#                                ../multitrack/track_branch_label.sh)
# Outputs : whatever the exec'd Go binary prints (see docs/label-sync/).
# Exit    : 0 ok | 1 finding/invalid input (from the binary) |
#           2 cannot determine (no go toolchain and no prebuilt binary, build
#           failed, usage) — 2 is never a pass.
# Side-effects: writes only under the bin cache dir (build) and the state dir
#           (via the binary). Build is serialised with flock, runs under
#           `nice`, GOPROXY=off (stdlib-only module, no network).
# Deps    : bash, go (only when a build is needed), find, flock (util-linux;
#           falls back to an unserialised build with a warning if absent).
# Cross-refs: §11.4.182, §11.4.116, §11.4.233, §11.4.18, docs/label-sync/CONTRACT.md.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SELF/bincache.sh" || { echo "labelctl.sh: bincache.sh missing" >&2; exit 2; }
ls_bincache_into BIN_DIR "$SELF"

# the commit the sources come from ('' outside git): binaries built from another
# commit are stale even when no file is newer (review-2 finding 13)
src_commit() { git -C "$SELF" rev-parse -q --verify HEAD 2>/dev/null || :; }

stale() { # $1 = binary
  [ -x "$1" ] || return 0
  [ -n "$(find "$SELF" \( -name '*.go' -o -name go.mod \) -newer "$1" -print -quit 2>/dev/null)" ] && return 0
  local rec=""; { IFS= read -r rec <"$BIN_DIR/.source-commit"; } 2>/dev/null || rec=""
  [ "$rec" != "$(src_commit)" ]   # MUT:commitstale
}

build() {
  if ! stale "$BIN_DIR/labelctl" && ! stale "$BIN_DIR/label-busd"; then return 0; fi
  if ! command -v go >/dev/null 2>&1; then
    echo "labelctl.sh: go toolchain not found and binaries are missing/stale — cannot determine" >&2
    return 2
  fi
  mkdir -p "$BIN_DIR" || return 2
  local lock="$BIN_DIR/.build.lock"
  (
    if command -v flock >/dev/null 2>&1; then flock 9; else echo "labelctl.sh: flock absent; unserialised build" >&2; fi
    # re-check after acquiring the lock (another process may have built)
    if ! stale "$BIN_DIR/labelctl" && ! stale "$BIN_DIR/label-busd"; then exit 0; fi
    cd "$SELF" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go build -o "$BIN_DIR/" ./cmd/labelctl ./cmd/label-busd \
      && src_commit >"$BIN_DIR/.source-commit"
  ) 9>"$lock" || { echo "labelctl.sh: build failed" >&2; return 2; }
}

case "${1:-}" in
  --bin-dir) echo "$BIN_DIR"; exit 0 ;;
  --build) build || exit $?; echo "$BIN_DIR"; exit 0 ;;
esac

build || exit $?
: "${LABEL_SYNC_LABELER:=$SELF/../multitrack/track_branch_label.sh}"
export LABEL_SYNC_LABELER
if [ "${1:-}" = "busd" ]; then shift; exec "$BIN_DIR/label-busd" "$@"; fi
exec "$BIN_DIR/labelctl" "$@"
