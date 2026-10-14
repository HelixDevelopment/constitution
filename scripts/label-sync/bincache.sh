# shellcheck shell=bash
# scripts/label-sync/bincache.sh
#
# Purpose : SOURCE-ONLY. The ONE definition of the default label-sync binary
#           cache directory, keyed by the label-sync MODULE PATH (review-2
#           finding 13: one shared cache let checkout A run checkout B's
#           binary). Each checkout gets
#             ${XDG_CACHE_HOME:-$HOME/.cache}/constitution-label-sync/bin-<key>
#           where <key> is a fork-free 32-bit djb2 hash (hex) of the module
#           path; the SOURCE is keyed inside that dir by the `.source-tree`
#           stamp the launchers write at build time: the git TREE id of the
#           module at HEAD (re-review finding 5 — a commit elsewhere in the
#           repository must not make identical binaries stale). LABEL_SYNC_BIN
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

# ls_src_tree MODULE_DIR : git tree id of MODULE_DIR at HEAD ('' outside git).
ls_src_tree() { git -C "$1" rev-parse -q --verify 'HEAD:./' 2>/dev/null || :; }

# ls_bin_stale BINARY STAMP_FILE MODULE_DIR : exit 0 when BINARY must be rebuilt.
#   missing / not executable                                   -> stale
#   stamp == current tree AND no uncommitted change in MODULE -> fresh (any mtimes:
#       a checkout rewrites mtimes of identical sources; a host without Go then
#       still uses the binaries instead of exiting 2)
#   stamp present but != current tree                          -> stale
#   otherwise (no stamp, e.g. a prebuilt LABEL_SYNC_BIN, or not a git checkout,
#   or uncommitted changes): stale only when a *.go / go.mod is NEWER than BINARY.
ls_bin_stale() {
  local bin="$1" stamp="$2" mod="$3" rec="" cur
  [ -x "$bin" ] || return 0
  { IFS= read -r rec <"$stamp"; } 2>/dev/null || rec=""
  cur="$(ls_src_tree "$mod")"
  if [ -n "$rec" ] && [ -n "$cur" ]; then
    if [ "$rec" = "$cur" ]; then                                       # MUT:treestamp
      [ -z "$(git -C "$mod" status --porcelain -- . 2>/dev/null)" ] && return 1   # MUT:treeclean
    else
      return 0
    fi
  fi
  [ -n "$(find "$mod" \( -name '*.go' -o -name go.mod \) -newer "$bin" -print -quit 2>/dev/null)" ]
}
