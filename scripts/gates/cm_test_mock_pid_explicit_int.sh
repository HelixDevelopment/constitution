#!/usr/bin/env bash
# cm_test_mock_pid_explicit_int.sh — CM-TEST-MOCK-PID-EXPLICIT-INT gate
# (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.263 clause (C): tests mocking subprocess/process objects MUST
# explicitly set `mock.pid = <int>` (never rely on the mock library's default)
# — because `unittest.mock`'s `MagicMock` / `AsyncMock` auto-generate a CHILD
# MOCK for any unset attribute, and Python's `int()` coercion of an
# unconfigured `MagicMock` falls back to `MagicMock.__int__()` returning the
# literal `1`. That is the EXACT BOB-126 mechanism: an unset `AsyncMock().pid`
# flowed through `os.getpgid(1) == 1` into `os.killpg(1, SIGKILL)` ==
# `kill(-1, SIGKILL)` — the disaster syscall that SIGKILLed the operator's
# entire desktop session SEVEN times over 48 hours.
#
# This gate walks test source for a `Mock()` / `MagicMock()` / `AsyncMock()`
# instantiation whose `.pid` attribute is READ anywhere in the same file, and
# FAILs when that `.pid` was never explicitly set to an INTEGER LITERAL —
# neither as a constructor kwarg (`Mock(pid=1234)`) nor as a later attribute
# assignment (`mock.pid = 1234`).
#
# ── Deliberate scope (honest, stated tradeoff — §11.4.6) ────────────────────
# The gate does NOT try to first classify a mock as "subprocess-shaped"
# before flagging it — ANY Mock/MagicMock/AsyncMock whose `.pid` is read
# without an explicit int set is at risk of the IDENTICAL default-`__int__()`
# fallback mechanism regardless of what the mock is conceptually standing in
# for, so narrowing to a "looks like a subprocess" pre-filter would create a
# false-negative gap on exactly the class of defect this anchor exists to
# close. This is a deliberate BROADENING relative to a literal reading of
# "subprocess mock" — see OWED-GATE-061's own description ("asserts every
# subprocess mock in test code sets mock.pid explicitly as int"), which this
# gate satisfies via the mechanism-based (not label-based) test.
#
# The gate does NOT additionally require that the killpg/kill call itself be
# patched/mocked in the same test (a stricter reading of §11.4.263 clause C)
# — proving that a given mock's `.pid` genuinely flows into a `killpg` call
# requires cross-file/call-graph data-flow analysis this text scanner cannot
# honestly claim. The hard-gated invariant here is exactly OWED-GATE-061's:
# explicit-int-`.pid` on every `.pid`-read mock. Composes with, never
# substitutes for, CM-KILLPG-PGID-GUARD (the production-side half of the
# same §11.4.263(D) four-layer defense).
#
# Detection is a bounded regex/line heuristic, NOT AST/data-flow analysis:
# it recognizes a same-line constructor kwarg (`pid=<int>`) and an anywhere-
# in-file explicit assignment (`<var>.pid = <int>`), but will NOT see a
# `pid=` kwarg split across a multi-line constructor call. This limitation is
# documented, not silent (§11.4.6) — most real fixtures that split a
# constructor across lines still configure `.pid` via a separate later
# assignment line, which this gate DOES see.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_test_mock_pid_explicit_int.sh [--root <dir>] [--quiet]
#     --root <dir>   scan root (default: $MOCK_PID_GUARD_ROOT or the gate-location default: superproject if vendored as a submodule, else the canon repo itself)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   MOCK_PID_GUARD_ROOT      default scan root (else --root, else the gate-location default, see scripts/lib/default_scan_root.sh)
#   MOCK_PID_GUARD_GLOB      -iname glob for candidate test files
#                             (default: "*test*.py" — matches test_*.py,
#                              *_test.py, and conftest.py)
#   MOCK_PID_GUARD_EXCLUDE   space-separated dir-name globs to prune
#                            (default: ".git node_modules vendor .venv
#                             __pycache__ scripts/gates out build dist")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-violation evidence line (file:line of the mock creation + the mock
#   variable name) + a final PASS / FAIL verdict with counts.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no mock is ever instantiated or
#   executed — the scanner only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, awk (POSIX-portable — no gawk-specific extensions used).
#   Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.263 (the anchor enforced — full clauses A-F, this is clause C),
#   §11.4.201(1)/(7)(a) (false-positive refusal is a FAIL-bluff; match
#   structure not substring), §11.4.6 (honest documented bounded limitation),
#   §11.4.28/§11.4.35 (project-agnostic, env-var-driven), §1.1 (paired
#   mutation: cm_test_mock_pid_explicit_int_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no risky mock found, or SKIP: no candidate test files).
#   1 — FAIL (a Mock/MagicMock/AsyncMock's `.pid` is read without ever
#       being explicitly set to an int literal).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-TEST-MOCK-PID-EXPLICIT-INT"
ANCHOR="11.4.263"

# verdict-affecting ambient overrides are guarded (11.4.276 r8): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set root MOCK_PID_GUARD_ROOT "" path   # ambient root guarded (an empty dir would SKIP); empty => resolved from the gate location after arg parsing (lib/default_scan_root.sh), NOT from cwd; --root stays honoured
cm_gate_env_set glob MOCK_PID_GUARD_GLOB "*test*.py" value
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --glob) glob="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$root" ]; then
    # shellcheck source=/dev/null
    . "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/default_scan_root.sh" 2>/dev/null \
        && root="$(cm_default_scan_root "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)")"
    [ -n "$root" ] || { echo "${GATE}: cannot resolve a default scan root from the gate location; pass --root" >&2; exit 2; }
fi

# The scan root may be a DIRECTORY (walked) or a SINGLE FILE (scanned as-is)
# — the single-file form lets a consumer delegate detection here per-file
# while keeping its own scope/DATA local (§11.4.35/§11.4.177).
root_is_file=0
if [ -f "$root" ]; then
    root_is_file=1
    root="$(cd "$(dirname "$root")" && pwd)/$(basename "$root")"
elif [ -d "$root" ]; then
    root="$(cd "$root" && pwd)"
else
    echo "${GATE}: scan root not found: $root" >&2; exit 2
fi

cm_gate_env_set excludes MOCK_PID_GUARD_EXCLUDE ".git node_modules vendor .venv __pycache__ scripts/gates out build dist" value
[ -z "${CM_GATE_OVERRIDES_HONOURED:-}" ] || echo "⚠ ${GATE}: NOTE — test-mode override(s) honoured: ${CM_GATE_OVERRIDES_HONOURED} (HELIX_TEST_MODE=1; never a production verdict)"

prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

if [ "$root_is_file" -eq 1 ]; then
    files=("$root")
else
mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f -iname "$glob" -print0
    else
        find "$root" -type f -iname "$glob" -print0
    fi
)
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no candidate test files under scan (root=$root, glob=$glob)"
    exit 0
fi

# ── Per-file awk scanner ─────────────────────────────────────────────────────
# 3-pass, order-independent (a mock's `.pid` may be configured before OR
# after the read that risks the defect — real fixtures do both):
#   Pass 1: find `VAR = (Mock|MagicMock|AsyncMock)(` creations; a same-line
#           `pid=<int>` kwarg marks that VAR immediately safe.
#   Pass 2: find any `VAR.pid = <int>` explicit assignment anywhere in the
#           file; marks that VAR safe regardless of position.
#   Pass 3: find any OTHER `VAR.pid` reference (a read); marks that VAR
#           "accessed". A VAR that is accessed but never made safe is the
#           violation this gate exists to catch.
AWK_SCRIPT='
{ lines[NR] = $0 }
END {
    total = NR
    for (i = 1; i <= total; i++) {
        line = lines[i]
        if (line ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(Mock|MagicMock|AsyncMock)\(/) {
            tmp = line
            sub(/^[ \t]*/, "", tmp)
            eqpos = index(tmp, "=")
            var = substr(tmp, 1, eqpos - 1)
            gsub(/[ \t]*$/, "", var)
            if (var != "" && !(var in mockcreate)) {
                mockcreate[var] = i
                mockcreateline[var] = line
            }
            if (line ~ /pid[ \t]*=[ \t]*[0-9]+/) safe[var] = 1
        }
    }
    for (v in mockcreate) {
        re_set = v "[ \t]*\\.[ \t]*pid[ \t]*=[ \t]*[0-9]+"
        for (i = 1; i <= total; i++) {
            if (lines[i] ~ re_set) { safe[v] = 1; break }
        }
    }
    for (v in mockcreate) {
        re_use = v "[ \t]*\\.[ \t]*pid([^A-Za-z0-9_]|$)"
        for (i = 1; i <= total; i++) {
            if (lines[i] ~ re_use) { accessed[v] = 1; break }
        }
    }
    # Pass 4 (upstreamed from the boba consumer gate): SUBPROCESS-SHAPE
    # detection, independent of whether `.pid` is read in the test file.
    # The LITERAL BOB-126 shape never mentions `.pid` in the test at all --
    # the test builds a process stand-in and PRODUCTION code reads `.pid`.
    # Passes 1-3 are structurally blind to that (they need an in-file
    # `.pid` read), so this pass keys on the process-stand-in SHAPE:
    #   VAR.returncode = None      (asyncio convention "still running" --
    #                               the ONLY state under which a cleanup /
    #                               kill branch is reachable at all), AND
    #   a process-lifecycle indicator on the SAME var.
    # Both markers are REQUIRED: a mock whose returncode is a real exit code
    # can never reach a kill path, so flagging it would be a §11.4.201(1)
    # false-positive refusal.
    for (i = 1; i <= total; i++) {
        line = lines[i]
        if (line ~ /patch(\.object)?[ \t]*\(.*killpg/) killpatch[i] = 1
    }
    for (v in mockcreate) {
        re_rc   = v "[ \t]*\.[ \t]*returncode[ \t]*=[ \t]*None([^A-Za-z0-9_]|$)"
        re_life = v "[ \t]*\.[ \t]*(stdout[ \t]*\.[ \t]*readline|stderr[ \t]*\.[ \t]*read|wait|kill|terminate|communicate)([^A-Za-z0-9_]|$)"
        for (i = 1; i <= total; i++) {
            if (lines[i] ~ re_rc)   rc_none[v] = 1
            if (lines[i] ~ re_life) lifecycle[v] = 1
        }
    }
    for (v in mockcreate) {
        if (!((v) in rc_none) || !((v) in lifecycle)) continue
        if ((v) in safe) continue
        if ((v) in accessed) continue    # already reported by pass 3
        exempt = 0
        for (i in killpatch) {
            d = i - mockcreate[v]
            if (d < 0) d = -d
            if (d <= 30) { exempt = 1; break }
        }
        if (exempt) continue
        print mockcreate[v] "\t" v "\tsubproc\t" mockcreateline[v]
    }
    for (v in mockcreate) {
        if ((v in accessed) && !((v) in safe)) {
            print mockcreate[v] "\t" v "\tpidread\t" mockcreateline[v]
        }
    }
}
'

violations=0
for f in "${files[@]}"; do
    # Strip Python comment-only lines before scanning so a doc-comment
    # quoting "proc = AsyncMock()" is never treated as a real fixture line
    # (§11.4.201(7)(a) — match structure, a comment is a CARRIER not the
    # thing itself).
    hits="$(sed -E 's/^[[:space:]]*#.*$//' "$f" 2>/dev/null | awk "$AWK_SCRIPT" 2>/dev/null || true)"
    [ -n "$hits" ] || continue
    while IFS=$'\t' read -r lineno var reason line; do
        [ -n "$lineno" ] || continue
        violations=$(( violations + 1 ))
        if [ "$reason" = "subproc" ]; then
            echo "❌ ${GATE}: FAIL — ${f}:${lineno}: mock '${var}' — subprocess-shaped stand-in ('.returncode = None' + a process-lifecycle attribute) with no explicit int '.pid' and no nearby 'killpg' patch (§${ANCHOR}(C))"
        else
            echo "❌ ${GATE}: FAIL — ${f}:${lineno}: mock '${var}' — '.pid' is read but never explicitly set to an int (§${ANCHOR}(C))"
        fi
        echo "   ${line# }"
    done <<< "$hits"
    [ "$quiet" -eq 1 ] || { [ -n "$hits" ] || true; }
done

echo "======================================================================"
if [ "$violations" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${violations} mock(s) with '.pid' read but never explicitly set to an int (§${ANCHOR})"
    exit 1
fi
echo "✅ ${GATE}: PASS — every '.pid'-read Mock/MagicMock/AsyncMock in scanned test files sets '.pid' explicitly as an int (§${ANCHOR})"
exit 0
