#!/usr/bin/env bash
# cm_track_branch_label.sh — CM-TRACK-BRANCH-LABEL gate (§11.4.182).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.182 (Track+branch+alias work-stream identity label) mandates a PreToolUse
# guard hook that BLOCKS any Agent/Task/TaskCreate dispatch whose description
# does not start with a `(T<N>/<branch> - <alias>)` label AND whose `<alias>`
# field does not match the LIVE alias derived from CLAUDE_CONFIG_DIR. This gate
# asserts FOUR invariants against the shipped hook + its reference labeler:
#
#   1. PRESENCE+EXEC  — the guard hook (guard-track-branch-label.sh) AND the
#      reference labeler (track_branch_label.sh) exist, are readable, and are
#      executable.
#   2. PARSEABILITY (§11.4.67) — both parse clean under their shebang shell
#      (`bash -n`; both are `#!/usr/bin/env bash`).
#   3. DOC — the §11.4.18 convention doc
#      (docs/scripts/guard-track-branch-label.md) exists and is non-empty.
#   4. ALIAS-VALIDATION (behavioral, load-bearing) — drives the REAL hook and
#      proves it actually validates the alias field (NOT a grep of the source):
#        (a) a format-valid label whose alias PROVABLY disagrees with a KNOWN
#            live alias is BLOCKED (exit 2) — the exact stale-`claude4`-while-
#            live-`claude3` defect §11.4.182 closes;
#        (b) the matching-alias label is ALLOWED (exit 0) — no over-blocking;
#        (c) an honest `?` label with the live alias unknown is ALLOWED (exit 0)
#            — the §11.4.6 honest boundary is preserved.
#      The live alias is derived by CALLING the labeler with a synthetic KNOWN
#      CLAUDE_CONFIG_DIR (single source of truth — no derivation regex here).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_track_branch_label.sh [--hook <path>] [--labeler <path>] [--doc <path>] [--quiet]
#     --hook <path>     guard hook to audit (default: ../hooks/guard-track-branch-label.sh)
#     --labeler <path>  reference labeler   (default: ../multitrack/track_branch_label.sh)
#     --doc <path>      convention doc      (default: ../../docs/scripts/guard-track-branch-label.md)
#     --quiet           suppress per-check PASS lines (FAIL lines always shown).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   None beyond the flags. Uses a synthetic non-existent CLAUDE_CONFIG_DIR value
#   internally so the ALIAS-VALIDATION probe is deterministic + session-neutral.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check ✅/❌ lines + a final summary; nonzero exit on any failed invariant.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation). The hook is run
#   in a subprocess against synthetic JSON payloads on stdin.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX coreutils (env). Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.182 (track+branch+alias label), §11.4.177 (inherited-by-reference),
#   §11.4.67 (target-shell-parseability), §11.4.18 (companion doc), §11.4.108
#   (runtime-signature — behavioral, not grep), §1.1 (paired mutation:
#   cm_track_branch_label_mutation_test.sh — a format-only hook that skips the
#   alias check → this gate FAILs).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all four invariants hold.
#   1 — at least one invariant violated.
#   2 — bad argument.
#
# Classification: universal (§11.4.17) — no project-specific data; the synthetic
# alias literals ('cmgatechk*') are gate-internal test tokens, not a consumer
# assumption.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="CM-TRACK-BRANCH-LABEL"

hook="${SCRIPT_DIR}/../hooks/guard-track-branch-label.sh"
labeler="${SCRIPT_DIR}/../multitrack/track_branch_label.sh"
doc="${SCRIPT_DIR}/../../docs/scripts/guard-track-branch-label.md"
quiet=""

while [ $# -gt 0 ]; do
    case "$1" in
        --hook)     hook="$2"; shift 2 ;;
        --labeler)  labeler="$2"; shift 2 ;;
        --doc)      doc="$2"; shift 2 ;;
        --quiet)    quiet="1"; shift ;;
        -h|--help)  sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

fail=0
say() { [ -n "$quiet" ] || echo "$@"; }

# Extract the <alias> field from a track-branch label. The label is emitted by
# scripts/multitrack/track_branch_label.sh as
#   "(T<N>/<branch> - <alias>[ - <model>[ - <effort>]]) ..."
# so <alias> is the FIRST ' - '-separated field after the "(T<N>/<branch>" head,
# NOT the last one: "take everything after the LAST ' - '" silently grabs
# <effort> once the optional <model>/<effort> fields are present (§11.4.182,
# §11.4.6 — the extraction must not regress under the new fields).
#
# Kept byte-identical in behaviour to the hook's own _label_alias in
# scripts/hooks/guard-track-branch-label.sh. If one changes, change both:
# the gate validates the hook, so a divergence here reports a false verdict.
_label_alias() {
    local _pfx="${1%%)*}"
    local _rest
    case "$_pfx" in
        *' - '*) _rest="${_pfx#*' - '}" ;;
        *)       printf '%s' ''; return ;;
    esac
    case "$_rest" in
        *' - '*) printf '%s' "${_rest%%' - '*}" ;;   # alias precedes <model>/<effort>
        *)       printf '%s' "$_rest" ;;              # 3-field legacy: alias is the remainder
    esac
}

# ── Invariant 1: PRESENCE + EXEC ─────────────────────────────────────────────
for _pair in "hook:$hook" "labeler:$labeler"; do
    _nm="${_pair%%:*}"; _p="${_pair#*:}"
    if [ ! -r "$_p" ]; then
        echo "❌ PRESENCE: ${_nm} not found/readable: $_p"; fail=1; continue
    fi
    if [ ! -x "$_p" ]; then
        echo "❌ EXEC: ${_nm} not executable: $_p"; fail=1
    else
        say "✅ PRESENCE+EXEC: ${_nm} -> $_p"
    fi
done

# ── Invariant 2: PARSEABILITY (bash -n — §11.4.67 target shell) ──────────────
for _pair in "hook:$hook" "labeler:$labeler"; do
    _nm="${_pair%%:*}"; _p="${_pair#*:}"
    [ -r "$_p" ] || continue
    if bash -n "$_p" 2>"${TMPDIR:-/tmp}"/cm_tbl_bn.$$; then
        say "✅ PARSEABILITY: ${_nm} clean (bash -n)"
    else
        echo "❌ PARSEABILITY: ${_nm} fails bash -n: $(tr '\n' ' ' < "${TMPDIR:-/tmp}"/cm_tbl_bn.$$)"; fail=1
    fi
    rm -f "${TMPDIR:-/tmp}"/cm_tbl_bn.$$
done

# ── Invariant 3: DOC (§11.4.18 convention doc) ──────────────────────────────
if [ -s "$doc" ]; then
    say "✅ DOC: convention doc present -> $doc"
else
    echo "❌ DOC: convention doc missing/empty: $doc"; fail=1
fi

# ── Invariant 4: ALIAS-VALIDATION (behavioral, load-bearing) ────────────────
if [ ! -r "$hook" ] || [ ! -r "$labeler" ]; then
    echo "❌ ALIAS-VALIDATION: cannot run — hook or labeler unreadable"; fail=1
else
    _cfg="/nonexistent/.claude-cmgatechk"; _known="cmgatechk"
    _correct="$(CLAUDE_CONFIG_DIR="$_cfg" bash "$labeler" 2>/dev/null || true)"
    _live="$(_label_alias "$_correct")"
    if [ "$_live" != "$_known" ]; then
        echo "❌ ALIAS-VALIDATION: labeler did not yield the known synthetic alias (got '$_live' from '$_correct')"; fail=1
    else
        # Mutate the ALIAS field in place, preserving any <model>/<effort> that
        # follow and anything after the ')'. Appending after the LAST ' - '
        # would corrupt the <effort> slot instead, and the hook — which
        # validates only the alias — would correctly ALLOW it, making this
        # gate accuse a hook that is behaving exactly as documented.
        _pfx="${_correct%%)*}"; _tail="${_correct#*)}"
        _t1="${_pfx%%' - '*}"                    # "(T<N>/<branch>"
        _restf="${_pfx#*' - '}"                  # "<alias>[ - <model>[ - <effort>]]"
        case "$_restf" in
            *' - '*) _after=" - ${_restf#*' - '}" ;;
            *)       _after="" ;;
        esac
        _wrong="${_t1} - ${_known}_MUT${_after})${_tail}"

        _pw='{"tool_name":"Task","tool_input":{"description":"'"$_wrong"' gate probe"}}'
        printf '%s' "$_pw" | CLAUDE_CONFIG_DIR="$_cfg" bash "$hook" >/dev/null 2>&1; _rc_w=$?

        _pc='{"tool_name":"Task","tool_input":{"description":"'"$_correct"' gate probe"}}'
        printf '%s' "$_pc" | CLAUDE_CONFIG_DIR="$_cfg" bash "$hook" >/dev/null 2>&1; _rc_c=$?

        _pq='{"tool_name":"Task","tool_input":{"description":"(T1/main - ?) gate probe"}}'
        printf '%s' "$_pq" | env -u CLAUDE_CONFIG_DIR bash "$hook" >/dev/null 2>&1; _rc_q=$?

        if [ "$_rc_w" -eq 2 ]; then
            say "✅ ALIAS-VALIDATION: WRONG alias ('${_known}_MUT' vs live '$_known') BLOCKED (exit 2)"
        else
            echo "❌ ALIAS-VALIDATION: WRONG alias NOT blocked (hook exit $_rc_w, expected 2) — hook does NOT validate the alias field"; fail=1
        fi
        if [ "$_rc_c" -eq 0 ]; then
            say "✅ ALIAS-VALIDATION: CORRECT alias ALLOWED (exit 0)"
        else
            echo "❌ ALIAS-VALIDATION: CORRECT alias wrongly blocked (hook exit $_rc_c, expected 0) — over-blocking"; fail=1
        fi
        if [ "$_rc_q" -eq 0 ]; then
            say "✅ ALIAS-VALIDATION: honest '?' (live unknown) ALLOWED (exit 0)"
        else
            echo "❌ ALIAS-VALIDATION: honest '?' wrongly blocked (hook exit $_rc_q, expected 0) — §11.4.6 honest-boundary broken"; fail=1
        fi
    fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
    echo "✅ ${GATE}: PASS — labeler+hook present/exec/parseable, doc present, hook validates the alias field"
    exit 0
fi
echo "❌ ${GATE}: FAIL — see violations above"
exit 1
