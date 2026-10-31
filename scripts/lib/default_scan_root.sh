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
