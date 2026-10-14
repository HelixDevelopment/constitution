# shellcheck shell=bash
# scripts/label-sync/bincache.sh
#
# Purpose : SOURCE-ONLY. The ONE definition of the default label-sync binary
#           cache directory, keyed by the label-sync MODULE PATH (review-2
#           finding 13: one shared cache let checkout A run checkout B's
#           binary). Each checkout gets
#             ${XDG_CACHE_HOME:-$HOME/.cache}/constitution-label-sync/bin-<key>
#           where <key> is a fork-free 32-bit djb2 hash (hex) of the module
#           path; the COMMIT is keyed inside that dir by the `.source-commit`
#           stamp labelctl.sh writes at build time (a different HEAD => the
#           binaries are stale => rebuilt). LABEL_SYNC_BIN still overrides all.
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
