#!/usr/bin/env bash
# ============================================================================
# portable_symlink_lib.sh — relocation-proof symlink creation.
# ============================================================================
# Purpose:
#   Create symlinks whose stored target is RELATIVE to the link's own location,
#   so a link committed on one machine keeps resolving in every other checkout
#   of the same repository — at any absolute path, on any host, on any OS.
#
#   The defect this exists to prevent (forensic, consuming-project commit
#   cc622528): a registration script computed an ABSOLUTE directory and did
#   `ln -sf "$abs_dir" "$link"`, baking the AUTHORING HOST's path into a tracked
#   link. A link generated on macOS against an external volume
#   (/Volumes/T7/...) had NEVER once resolved in a Linux checkout of the very
#   same repository. Anything that stores an absolute path in a tracked link is
#   a machine-specific artifact masquerading as shared state.
#
# Design constraints:
#   * PROJECT-AGNOSTIC (§11.4.28 / CONST-051(B)). This library knows nothing
#     about any consuming project — no project name, no directory layout, no
#     repository shape. It takes two paths and returns a path. It is therefore
#     reusable verbatim by every consumer of this constitution.
#   * PORTABLE SHELL. `realpath --relative-to` is GNU coreutils only; BSD/macOS
#     realpath does not have it, and the forensic case above proves these
#     scripts genuinely run on macOS. The relative-path computation here is
#     pure POSIX shell (dirname + parameter expansion) with no coreutils-
#     specific flags, no python, no perl.
#   * HONEST FALLBACK (§11.4.6). When two paths share no ancestor deeper than
#     "/", no relative expression can survive relocation; the library says so
#     and emits an absolute link rather than pretending it solved the problem.
#
# Usage (source it, then call):
#   . "$const_root/scripts/portable_symlink_lib.sh"
#   hc_ln_relative <target-path> <link-path>
#
# Functions:
#   hc_relpath <target-abs> <from-dir-abs>
#       Echo the path of <target-abs> expressed relative to <from-dir-abs>.
#       Both arguments MUST be absolute. Echoes "." when they are equal.
#   hc_ln_relative <target> <link>
#       Replace <link> with a symlink to <target>, storing a RELATIVE target
#       whenever the two share a real common ancestor. Creates the link's
#       parent directory. Returns 0 on success, non-zero on failure.
#
# Outputs: hc_relpath echoes the relative path. hc_ln_relative is silent on
#          success and prints a WARN to stderr when it must fall back.
# Side-effects: hc_ln_relative removes an existing <link> and creates the
#          link's parent directory. hc_relpath is pure (no side-effects).
# Dependencies: POSIX shell builtins, dirname, basename, ln, rm, mkdir.
# Cross-references: §11.4.111 (bind by stable relative identity, never by a
#          host-specific absolute path), §11.4.28, §11.4.6, §11.4.115.
# Classification: universal (§11.4.17)
# Last verified: 2026-07-29
# ============================================================================

# hc_relpath <target-abs> <from-dir-abs>
# Pure-POSIX relative-path computation. No GNU-only flags.
hc_relpath() {
  _hc_t="${1%/}"
  _hc_f="${2%/}"
  [ -n "$_hc_t" ] || _hc_t=/
  [ -n "$_hc_f" ] || _hc_f=/

  # Walk the "from" directory up until it is an ancestor of (or equal to) the
  # target, accumulating one ".." per level popped.
  _hc_common="$_hc_f"
  _hc_up=""
  while [ "$_hc_common" != "/" ] &&
        [ "$_hc_t" != "$_hc_common" ] &&
        [ "${_hc_t#"$_hc_common"/}" = "$_hc_t" ]; do
    _hc_common="$(dirname "$_hc_common")"
    _hc_up="../$_hc_up"
  done

  # Remainder of the target below the common ancestor.
  if [ "$_hc_t" = "$_hc_common" ]; then
    _hc_rest=""
  elif [ "$_hc_common" = "/" ]; then
    _hc_rest="${_hc_t#/}"
  else
    _hc_rest="${_hc_t#"$_hc_common"/}"
  fi

  _hc_out="${_hc_up}${_hc_rest}"
  _hc_out="${_hc_out%/}"
  [ -n "$_hc_out" ] || _hc_out="."
  printf '%s\n' "$_hc_out"
}

# hc_ln_relative <target> <link>
hc_ln_relative() {
  _hc_target="$1"
  _hc_link="$2"

  _hc_link_dir="$(dirname "$_hc_link")"
  mkdir -p "$_hc_link_dir" || return 1

  # Normalise BOTH sides physically and identically, so the computed relative
  # path is sound even when an ancestor is itself a symlink.
  _hc_link_dir_abs="$(cd "$_hc_link_dir" >/dev/null 2>&1 && pwd)" || return 1
  _hc_target_parent="$(cd "$(dirname "$_hc_target")" >/dev/null 2>&1 && pwd)" || {
    printf '[portable-symlink] WARN: target parent does not exist: %s\n' "$_hc_target" >&2
    return 1
  }
  _hc_target_abs="${_hc_target_parent%/}/$(basename "$_hc_target")"

  # No shared ancestor deeper than "/" => no relative expression can survive
  # relocation. Say so rather than pretend (§11.4.6).
  _hc_probe_a="${_hc_link_dir_abs#/}"; _hc_probe_a="${_hc_probe_a%%/*}"
  _hc_probe_b="${_hc_target_abs#/}";   _hc_probe_b="${_hc_probe_b%%/*}"
  if [ "$_hc_probe_a" != "$_hc_probe_b" ]; then
    printf '[portable-symlink] WARN: %s and %s share no common root — storing an ABSOLUTE target (not relocation-proof)\n' \
      "$_hc_link_dir_abs" "$_hc_target_abs" >&2
    rm -f "$_hc_link"
    ln -s "$_hc_target_abs" "$_hc_link"
    return $?
  fi

  _hc_rel="$(hc_relpath "$_hc_target_abs" "$_hc_link_dir_abs")"
  rm -f "$_hc_link"
  ln -s "$_hc_rel" "$_hc_link"
}
