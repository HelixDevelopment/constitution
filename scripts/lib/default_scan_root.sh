# shellcheck shell=bash
# scripts/lib/default_scan_root.sh — the ONE resolver for the DEFAULT scan root of
# scanner gates (known_failures_v73 rank 3).
#
# Defect fixed: scanner gates defaulted their scan root to the literal "..",
# i.e. relative to the CALLER'S cwd. Run from the canon root that scans the whole
# parent directory (every sibling project, many minutes, findings from foreign
# repositories). The default must depend on WHERE THE GATE LIVES, never on where
# the caller happens to stand.
#
# Rule (read-only, no guessing, always overridable):
#   - the gate belongs to the repository at <gate_dir>/../.. (the "canon dir");
#   - if that repository is checked out as a SUBMODULE of a superproject (a
#     consumer), the default root is the superproject working tree (the consumer,
#     which is what "cwd=constitution, root=.." meant for consumers);
#   - otherwise (standalone canon checkout) the default root is the canon dir.
# An explicit --root / env override always wins and is never touched here.
#
# Usage: root="$(cm_default_scan_root "$SCRIPT_DIR")"
# Prints one absolute path; returns 1 (prints nothing) if the canon dir cannot be resolved.

cm_default_scan_root() {
    local gate_dir canon super
    gate_dir="${1:-}"
    [ -n "$gate_dir" ] || return 1
    canon="$(CDPATH='' cd -- "$gate_dir/../.." 2>/dev/null && pwd -P)" || return 1
    super=""
    if command -v git >/dev/null 2>&1; then
        super="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
                 git -C "$canon" rev-parse --show-superproject-working-tree 2>/dev/null)" || super=""
    fi
    if [ -n "$super" ] && [ -d "$super" ]; then
        printf '%s\n' "$super"
    else
        printf '%s\n' "$canon"
    fi
}

# cm_is_canon_root <dir> : 0 iff <dir> is a canon repository ITSELF -- a Constitution.md at its root that
# carries the anchor heading `## ... §11.4.1 —` OUTSIDE a ``` / ~~~ code fence (an empty or stray file named
# Constitution.md is NOT a canon; round 3 M1), a scripts/gates directory, and it is not checked out as a
# submodule of a superproject (a vendored canon belongs to its consumer). Read-only.
cm_is_canon_root() {
    local d="${1:-}" super=""
    [ -n "$d" ] && [ -f "$d/Constitution.md" ] && [ -d "$d/scripts/gates" ] || return 1
    # fence-aware (N-nit): lines inside a code fence are dropped before the heading test (process substitution,
    # not a pipe: grep -q -m1 exiting early must not turn a PRESENT heading into a pipefail miss)
    LC_ALL=C grep -q -m1 -E '^##+ +§11\.4\.1 +(—|-)' < <(LC_ALL=C awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f' "$d/Constitution.md" 2>/dev/null) || return 1
    if command -v git >/dev/null 2>&1; then
        super="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
                 git -C "$d" rev-parse --show-superproject-working-tree 2>/dev/null)" || super=""
    fi
    [ -z "$super" ] || return 1
    return 0
}
