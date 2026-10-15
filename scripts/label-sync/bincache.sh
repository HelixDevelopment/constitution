# shellcheck shell=bash
# scripts/label-sync/bincache.sh
#
# Purpose : SOURCE-ONLY. The ONE definition of the default label-sync binary
#           cache directory, keyed by the label-sync MODULE PATH (review-2
#           finding 13: one shared cache let checkout A run checkout B's
#           binary). Each checkout gets
#             ${XDG_CACHE_HOME:-$HOME/.cache}/constitution-label-sync/bin-<key>
#           where <key> is a fork-free 32-bit djb2 hash (hex) of the module
#           path; the SOURCE is keyed inside that dir by the `.source-digest`
#           stamp the launchers write at build time: a sha256 over the Go build
#           inputs (ls_src_digest — re-review findings 5 and 3.2/3.3). LABEL_SYNC_BIN
#           still overrides the directory.
#           ls_bin_stale is the ONE staleness rule (labelctl.sh, mcp/label-mcp.sh,
#           hooks/label-sync-lib.sh).
# Usage   : . "<label-sync>/bincache.sh"; dir="$(ls_bincache_dir "<label-sync>")"
#           or ls_bincache_into VAR "<label-sync>"   (no subshell, hot path)
# Inputs  : $LABEL_SYNC_BIN, $XDG_CACHE_HOME, $HOME.
# Outputs : the directory path (nothing is created).
# Exit    : 0 always (library).
# Side-effects: none.
# Deps    : bash builtins only (printf -v, arithmetic): safe on hook hot paths.
# Cross-refs: labelctl.sh, mcp/label-mcp.sh, hooks/label-sync-lib.sh,
#           adapters/lib/adapter_lib.sh, docs/label-sync/CONTRACT.md.
# Classification: universal (§11.4.17).

# ls_bincache_into VAR MODULE_DIR
ls_bincache_into() {
  local __v="$1" __s="$2" __h=5381 __i __c
  if [ -n "${LABEL_SYNC_BIN:-}" ]; then printf -v "$__v" '%s' "$LABEL_SYNC_BIN"; return 0; fi
  for ((__i = 0; __i < ${#__s}; __i++)); do
    printf -v __c '%d' "'${__s:__i:1}"
    __h=$(( (__h * 33 + __c) & 0xffffffff ))   # MUT:cachekey
  done
  printf -v "$__v" '%s/constitution-label-sync/bin-%08x' "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}" "$__h"
}
ls_bincache_dir() { local __d; ls_bincache_into __d "$1"; printf '%s' "$__d"; }

# ls_src_digest MODULE_DIR : sha256 over the module's Go build inputs — every
# non-test *.go file and go.mod, sorted by path, each with its own sha256 —
# or '' when sha256sum is unavailable. Content, not git (re-review 3 findings
# 2, 3): a binary built from UNCOMMITTED sources is not stamped with HEAD's
# tree, a tarball (no .git) keeps its stamp, and editing a shell script under
# scripts/label-sync does not make the Go binaries stale.
ls_src_digest() {
  command -v sha256sum >/dev/null 2>&1 || return 0
  ( cd "$1" 2>/dev/null && find . \( -name '*.go' ! -name '*_test.go' -o -name go.mod \) -type f -print0 \
      | LC_ALL=C sort -z | xargs -0r sha256sum ) 2>/dev/null | sha256sum | cut -c1-64
}

# ls_bin_stale BINARY STAMP_FILE MODULE_DIR : exit 0 when BINARY must be rebuilt.
#   missing / not executable                         -> stale
#   stamp present and == current ls_src_digest       -> fresh (any mtimes; a host
#       without Go then keeps using identical binaries instead of exiting 2)
#   stamp present and != current digest              -> stale
#   no stamp (e.g. a prebuilt LABEL_SYNC_BIN) or no digest available:
#       stale only when a *.go / go.mod is NEWER than BINARY.
ls_bin_stale() {
  local bin="$1" stamp="$2" mod="$3" rec="" cur
  [ -x "$bin" ] || return 0
  { IFS= read -r rec <"$stamp"; } 2>/dev/null || rec=""
  cur="$(ls_src_digest "$mod")"
  if [ -n "$rec" ] && [ -n "$cur" ]; then
    [ "$rec" != "$cur" ]   # MUT:digeststamp
    return
  fi
  [ -n "$(find "$mod" \( -name '*.go' -o -name go.mod \) -newer "$bin" -print -quit 2>/dev/null)" ]
}
