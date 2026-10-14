#!/usr/bin/env bash
# =============================================================================
# agent_label_lib.sh — the ONE shared implementation of the §11.4.182 /
#   §11.4.231(F) agent-type label naming rules, sourced by
#   gen_agent_label_defs.sh, install_agent_label_defs.sh and
#   scripts/hooks/guard-track-branch-label.sh (so the three can never diverge).
#
# Purpose : sanitise label text into a type-name segment, build type names
#   T<N>-<branch>-<alias>-<model>-<effort>, validate them, normalise track
#   numbers and JSON-escape hook messages.
# Usage   : . scripts/multitrack/agent_label_lib.sh   (library; defines al_* only)
# Inputs  : function arguments only.
# Outputs : stdout of each function; no side-effects, no global state besides
#   the AL_* constants below.
# Determinism: every function runs its text tools under LC_ALL=C, so the result
#   is byte-identical on every host and locale (a UTF-8 locale would otherwise
#   keep or case-fold non-ASCII letters differently).
# Portability: bash 3.2-safe (no associative arrays, no ${x,,}); the hook that
#   sources it may run on a stock macOS bash.
# Cross-refs: §11.4.182 clause (8), §11.4.231 (F.5), §11.4.177 (inherited by
#   reference), docs/scripts/gen_agent_label_defs.md.
# Classification: universal (§11.4.17).
# =============================================================================

# shellcheck disable=SC2034 # constants consumed by the scripts that source this library
AL_MODELS="sonnet opus"
# shellcheck disable=SC2034 # read by the generator and installer that source this file
AL_EFFORTS="low medium high xhigh max"
# Default set (operator decision AL-10): the Sonnet working rung and the
# §11.4.209/§11.4.211 Opus-xhigh pin. The full ladder is opt-in (--all-types).
# shellcheck disable=SC2034 # default type list read by the sourcing generator
AL_DEFAULT_TYPES="sonnet-medium,sonnet-high,opus-high,opus-xhigh"
# shellcheck disable=SC2034 # full ladder read by the sourcing generator for --all-types
AL_ALL_TYPES="sonnet-low,sonnet-medium,sonnet-high,sonnet-xhigh,sonnet-max,opus-low,opus-medium,opus-high,opus-xhigh,opus-max"
# Longest type name accepted (the temp file .<name>.md.tmp.<pid> must stay well
# below the 255-byte file-name limit; long names are refused, never truncated).
AL_NAME_MAX=120
# Generated-file marker prefix (v1 = round-1 format without the alias segment;
# still RECOGNISED so stale v1 files can be pruned, never written).
# shellcheck disable=SC2034 # marker pattern read by the sourcing generator classify function
AL_MARK_RE='^<!-- generated-by: gen_agent_label_defs\.sh v[12] .*content-sha256: ([0-9a-f]{64});'

# al_sanitise <text> -> lowercase [a-z0-9-] segment (may be empty).
#   Byte-wise: ASCII A-Z lowercased, EVERY other byte (non-ASCII, '/', space,
#   newline, control characters) becomes '-', runs collapse, ends trimmed.
al_sanitise() {
  # shellcheck disable=SC2018,SC2019 # ASCII-only on purpose (locale-free determinism)
  printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9' '-' \
    | LC_ALL=C tr -s '-' | LC_ALL=C sed -e 's/^-//' -e 's/-$//'
}

# al_label_plain <text> -> exit 0 when the raw text may appear verbatim inside
#   the description label (ASCII letters, digits, . _ / -; nothing else).
al_label_plain() {
  case "$1" in
    '') return 1 ;;
  esac
  # explicit character list (no ranges): the verdict cannot depend on locale
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) return 1 ;;
  esac
  return 0
}

# al_label_text <text> -> the raw text when plain, else its sanitised form.
al_label_text() {
  if al_label_plain "$1"; then printf '%s' "$1"; else al_sanitise "$1"; fi
}

# al_norm_track <n> -> decimal without leading zeros ('01' -> '1'); exit 1 if
#   the input is not a decimal number.
al_norm_track() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  local t="$1"
  while [ "${#t}" -gt 1 ] && [ "${t#0}" != "$t" ]; do t="${t#0}"; done
  printf '%s' "$t"
}

# al_type_name <track> <branch> <alias> <model> <effort> -> T<N>-<b>-<a>-<m>-<e>
al_type_name() {
  printf 'T%s-%s-%s-%s-%s' "$(al_norm_track "$1")" "$(al_sanitise "$2")" "$(al_sanitise "$3")" "$4" "$5"
}

# al_name_ok <name> -> exit 0 when <name> is a well-formed label type name
#   within AL_NAME_MAX.
al_name_ok() {
  [ "${#1}" -le "$AL_NAME_MAX" ] || return 1
  printf '%s\n' "$1" | LC_ALL=C grep -Eq '^T[0-9]+-[a-z0-9]+(-[a-z0-9]+)+-(sonnet|opus)-(low|medium|high|xhigh|max)$'
}

# al_value_ok <value> -> 0 when an option value is usable: not empty and not starting
#   with '-' (so a forgotten value never swallows the next flag; a path that starts
#   with '-' can be written as ./-name). One rule for every option that takes a value.
al_value_ok() { case "$1" in ''|-*) return 1 ;; esac; return 0; }
# al_path_ok <path> -> 0 when the path contains no control character (C locale
#   [[:cntrl:]]: 0x01-0x1f incl. TAB/LF/CR, and 0x7f). Such a path cannot be held on
#   one ignore line or compared as an exact key, so it is refused everywhere. NUL
#   cannot occur: argv strings end at NUL.
al_path_ok() { local LC_ALL=C; case "$1" in *[[:cntrl:]]*) return 1 ;; esac; return 0; }
# al_json_escape <text> -> text safe inside a JSON string literal
#   (backslash and quote escaped, control characters dropped).
al_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s" | LC_ALL=C tr -d '\000-\037'
}
