#!/usr/bin/env bash
# cm_killpg_pgid_guard.sh — CM-KILLPG-PGID-GUARD gate (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.263 (BOB-126 forensic anchor): a Python test bug — an unset
# AsyncMock().pid falling back to MagicMock's default __int__() == 1 — flowed
# into `os.getpgid(1)` → `os.killpg(1, SIGKILL)`, which is IDENTICAL on Linux
# to `kill(-1, SIGKILL)`: the disaster syscall that SIGKILLs every process the
# caller's UID owns. It SIGKILLed the operator's entire desktop session
# (systemd user manager, gnome-shell, tmux, ssh, browsers, Claude Code) SEVEN
# times over 48 hours.
#
# Clause (B) mandates: validate `isinstance(pid,int) and pid>1` AND
# `isinstance(pgid,int) and pgid>1` BEFORE every process-group signal call —
# `os.killpg` (Python), `syscall.Kill(-pgid,sig)` (Go), `nix::killpg` (Rust),
# `kill -<pgid>` / `pkill -g` (Bash), `killpg`/`kill(-pid,sig)` (C). This gate
# is the pre-build STATIC scanner half of clause (D)'s four-layer defense: it
# walks production source for a dangerous process-group-signal call site and
# FAILs when no guard comparing a pid/pgid/gid-named identifier to `1` via a
# `>`/`>=`/`-gt` comparator appears within a preceding window of source lines.
#
# ── Detection scope (honest, stated tradeoff — §11.4.6) ─────────────────────
# This is a bounded-window regex-proximity heuristic, NOT a data-flow or AST
# analysis (infeasible for a portable multi-language shell/awk scanner within
# this gate's scope). It WILL correctly clear the anchor's own prescribed
# guard idiom — the pgid bound to a NAME and that NAME compared to 1 before
# the call, e.g. `pgid = os.getpgid(pid); if pgid > 1: os.killpg(pgid, sig)`
# — and WILL correctly flag the literal BOB-126 shape (a bare, unguarded
# `os.killpg(os.getpgid(proc.pid), signal.SIGKILL)`).
#
# The guard must be scoped to THE CALL'S OWN TARGET: a window guard on a
# DIFFERENT pid-family variable does not clear the call (see `extract_target`
# / `target_guarded` below for the forensic shape this closes). Two honest,
# bounded consequences, documented rather than silent (§11.4.6):
#   * a call whose target is an INLINE EXPRESSION rather than a name
#     (`os.killpg(os.getpgid(proc.pid), sig)`) can never be proven guarded by
#     a text scanner and is reported UNGUARDED. This is not a workaround to
#     route around — §11.4.263(B) mandates validating the pgid too, which is
#     only expressible by binding it to a name first;
#   * a guard placed further than `KILLPG_GUARD_WINDOW` (default 6) lines
#     above the call site is likewise not seen.
# Neither is an attempt at full soundness this class of scanner cannot
# honestly claim.
#
# Shell-form detection is deliberately NARROW: an ordinary single-process
# `kill -9 $pid` MUST NOT be flagged (POSIX kill(2)'s process-group form
# requires a NEGATIVE pgid argument, and $pid here need not be negative), so
# only `pkill -g` and the unambiguous negated-pgid shell idiom
# `kill -"$pgid"` / `kill -${pgid}` (dash immediately followed by a
# variable-only pgid-token) are matched — precision over recall, honoring the
# brief's emphasis that false-positiving legitimately-safe code "matters
# enormously."
#
# Comment-prefixed lines (`#`/`//`) are stripped before matching so this
# gate's own doc-comments quoting `os.killpg(` (as above) are never
# self-flagged; `scripts/gates` is excluded from the default scan root's
# recursive walk for the same reason (this file + its mutation-test fixtures
# legitimately embed the dangerous literal as fixture text, never as a real
# call site).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_killpg_pgid_guard.sh [--root <dir>] [--window N] [--quiet]
#     --root <dir>   scan root (default: $KILLPG_GUARD_ROOT or "..")
#     --window N     guard-proximity window in preceding lines
#                     (default: $KILLPG_GUARD_WINDOW or 6)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   KILLPG_GUARD_ROOT       default scan root (else --root, else "..")
#   KILLPG_GUARD_WINDOW     guard-proximity window, lines (default 6)
#   KILLPG_GUARD_EXT        space-separated source extensions to scan
#                            (default: "py go rs c cc cpp h hpp sh bash")
#   KILLPG_GUARD_EXCLUDE    space-separated dir-name globs to prune
#                            (default: ".git node_modules vendor .venv
#                             __pycache__ scripts/gates out build dist")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-hit evidence line (file:line + matched call-site text) + a final
#   PASS / FAIL verdict with the guarded/unguarded hit counts.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no process signaled — the scanner
#   NEVER executes a real killpg/kill syscall, it only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, grep (GNU or BSD ERE), awk. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.263 (the anchor enforced — full clauses A-F), §11.4.201(1)/(7)(a)
#   (false-positive refusal is a FAIL-bluff; match structure not substring),
#   §11.4.6 (honest documented bounded limitation, never silent), §11.4.28/
#   §11.4.35 (project-agnostic, env-var-driven), §1.1 (paired mutation:
#   cm_killpg_pgid_guard_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no dangerous call site found, or every one found is guarded).
#   1 — FAIL (an unguarded process-group signal call site found).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-KILLPG-PGID-GUARD"
ANCHOR="11.4.263"

root="${KILLPG_GUARD_ROOT:-..}"
window="${KILLPG_GUARD_WINDOW:-6}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --window) window="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '1,90p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

case "$window" in
    ''|*[!0-9]*) echo "${GATE}: --window must be a non-negative integer, got '$window'" >&2; exit 2 ;;
esac

# The scan root may be a DIRECTORY (walked) or a SINGLE FILE (scanned as-is).
# The single-file form lets a consumer delegate detection here per-file while
# keeping its own scope/DATA local (§11.4.35), instead of copying this
# scanner (§11.4.177 consume-by-reference, never copy).
root_is_file=0
if [ -f "$root" ]; then
    root_is_file=1
    root="$(cd "$(dirname "$root")" && pwd)/$(basename "$root")"
elif [ -d "$root" ]; then
    root="$(cd "$root" && pwd)"
else
    echo "${GATE}: scan root not found: $root" >&2; exit 2
fi

exts="${KILLPG_GUARD_EXT:-py go rs c cc cpp h hpp sh bash}"
excludes="${KILLPG_GUARD_EXCLUDE:-.git node_modules vendor .venv __pycache__ scripts/gates out build dist}"

# ── Build the `find` file-selector predicate (extensions) ──────────────────
find_name_expr=()
first=1
for e in $exts; do
    if [ "$first" -eq 1 ]; then first=0; else find_name_expr+=(-o); fi
    find_name_expr+=(-name "*.${e}")
done

# ── Build the `find` prune predicate (excluded dir-name globs, incl. paths
#    like "scripts/gates" matched against the tail of the path) ────────────
prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
# drop trailing -o
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

if [ "$root_is_file" -eq 1 ]; then
    files=("$root")
else
mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f \( "${find_name_expr[@]}" \) -print0
    else
        find "$root" -type f \( "${find_name_expr[@]}" \) -print0
    fi
)
fi

if [ "${#files[@]}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no source files under scan (root=$root, ext=[$exts])"
    exit 0
fi

# ── Dangerous call-site ERE (comment-stripped lines only) ──────────────────
#   * Python/Go/Rust/C:  killpg(          — os.killpg / killpg / nix::killpg
#   * Go:                syscall.Kill(-   — process-GROUP form (negative pgid)
#   * C/generic:          kill(-           — kill(-pid,sig) process-group form
#   * shell:              pkill -g        — pkill's explicit process-group flag
#   * shell:              kill -"$pgid" / kill -${pgid}  — negated-pgid idiom
#   * shell:              kill -<SIG> -<target>  — the NEGATED-TARGET process
#                         group form (`kill -9 -1`, `kill -TERM -"$pgid"`).
#                         Upstreamed from the boba consumer's local gate,
#                         which detected the literal shell broadcast-kill
#                         `kill -9 -1` this scanner was blind to. The SIGNAL
#                         token deliberately excludes a bare `0`: `kill -0`
#                         delivers no signal at all (kill(2)) — it is the
#                         POSIX liveness-PROBE idiom and is structurally
#                         incapable of the §11.4.263 defect, so flagging it
#                         would be a §11.4.201(1) false-positive refusal.
CALL_ERE='killpg[[:space:]]*\(|=[[:space:]]*([A-Za-z_][A-Za-z0-9_.]*\.)?killpg[[:space:]]*;?[[:space:]]*$|syscall\.Kill[[:space:]]*\([[:space:]]*-|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*-|pkill[[:space:]]+-g[[:space:]]|kill[[:space:]]+-"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|kill[[:space:]]+-[A-Za-z1-9][A-Za-z0-9]*[[:space:]]+-("?\$\{?[A-Za-z_]|[0-9])'

# Guard-proximity ERE: a pid/pgid/gid-family identifier compared to 1 via
# ANY ordering comparator (>, >=, <, <=, -gt, -ge, -lt, -le; either operand
# order; either language's syntax). Broadened deliberately (§11.4.201 — a
# false-positive refusal is exactly as forbidden as a false-negative pass):
# both the affirmative "if pid > 1: dangerous()" idiom AND the equally
# legitimate negated raise-early idiom "if pid <= 1: raise(...)" are real,
# common guard shapes and BOTH must clear this gate without a false refusal.
GUARD_ERE='(pid|pgid|gid|process_group|pgrp)[A-Za-z0-9_]*[^A-Za-z0-9_]{0,3}(>=?|<=?|-gt|-ge|-lt|-le)[[:space:]]*1([^0-9]|$)|1[[:space:]]*(<=?|>=?)[[:space:]]*(pid|pgid|gid|process_group|pgrp)'

# ── Guard must be scoped to THE CALL'S OWN TARGET (§11.4.201 false-negative) ─
# The family-name GUARD_ERE above is NOT identifier-scoped: it clears a call
# whenever ANY pid/pgid-family name is compared to 1 in the window. That is a
# false-negative PASS on the exact BOB-126 shape, e.g.
#     _pid = proc.pid
#     if isinstance(_pid, int) and _pid > 1:          # correct guard, wrong var
#         _pgid = os.getpgid(_pid)
#         if isinstance(_pgid, int) and _pgid > 0:    # WEAK: 0, not 1
#             os.killpg(_pgid, SIGKILL)               # pgid==1 still reaches here
# where the strong `_pid > 1` guard "covers" a target (`_pgid`) that was only
# ever checked `> 0`. Upstreamed from the boba consumer gate: extract the
# identifier actually PASSED to the call and require the window to compare
# THAT identifier to 1.
#
# extract_target <matched-line> — prints the call's target identifier (a bare
# name or a dotted-attribute chain such as `self._pgid`), or nothing when the
# target is not a plain identifier (a nested call expression, an arithmetic
# expression). An unextractable target is treated as UNGUARDED — conservative
# by design (§11.4.101/§11.4.201): the anchor's own prescribed idiom assigns
# the pgid to a variable and guards that variable, so a nested-call target is
# a shape this scanner cannot prove safe and must not clear.
extract_target() {
    printf '%s\n' "$1" | sed -E \
        -e 's/.*killpg[[:space:]]*\(//' \
        -e 's/.*syscall\.Kill[[:space:]]*\(//' \
        -e 's/.*[^A-Za-z0-9_]kill[[:space:]]*\(//' \
        -e 's/.*pkill[[:space:]]+-g[[:space:]]+//' \
        -e 's/.*kill[[:space:]]+-[A-Za-z1-9][A-Za-z0-9]*[[:space:]]+//' \
        -e 's/.*kill[[:space:]]+//' \
        | sed -nE 's/^[[:space:]]*-?[[:space:]]*"?\$?\{?([A-Za-z_][A-Za-z0-9_.]*).*/\1/p'
}

# target_guarded <window-text> <target-identifier>
#   0 (guarded) iff the window compares THAT identifier to the literal 1 with
#   any ordering comparator, in either operand order and either language's
#   syntax. Any `.` in a dotted chain is regex-escaped so it matches itself
#   and never behaves as an "any character" wildcard. Intervening non-word
#   characters (a closing shell quote, a brace) are tolerated between the
#   identifier and its comparator.
target_guarded() {
    _tg_window="$1"; _tg_ident="$2"
    [ -n "$_tg_ident" ] || return 1
    _tg_re="$(printf '%s' "$_tg_ident" | sed 's/\./\\./g')"
    # here-string, not `printf | grep -q`: under pipefail an early-exiting grep can SIGPIPE the producer and
    # read a GUARDED call as unguarded on a large window (SIGPIPE x pipefail class, §11.4.276(C))
    grep -qE \
"(^|[^A-Za-z0-9_])${_tg_re}[^A-Za-z0-9_]*(>=?|<=?|-gt|-ge|-lt|-le)[[:space:]]*1([^0-9]|\$)|1[[:space:]]*(<=?|>=?)[^A-Za-z0-9_]*${_tg_re}([^A-Za-z0-9_]|\$)" \
        <<<"$_tg_window"
}

# ── Numeric-literal target ⇒ ALWAYS unguarded (§11.4.201 false-negative fix) ─
# A call whose process-group target is a NUMERIC LITERAL (`os.killpg(1, ...)`,
# `kill(-1, sig)`, `syscall.Kill(-1, ...)`, `pkill -g 1`, `kill -9 -1`) is the
# BOB-126 disaster syscall spelled out in source. No guard can make a hardcoded
# `1` safe, and the proximity heuristic above is NOT identifier-scoped — so ANY
# unrelated pid/pgid/gid-family bounds check that happens to sit in the
# preceding window (even one for a completely different variable, even inside
# a since-stripped comment) would otherwise clear it. That is a false-negative
# PASS-bluff on the exact defect class this gate exists to catch. Upstreamed
# from the boba consumer's local gate, whose identifier-scoped extraction
# treats an identifier-less (literal/numeric) target as unconditionally
# unguarded; refusing to guess here is the conservative-safe default
# (§11.4.101/§11.4.201).
LITERAL_TARGET_ERE='killpg[[:space:]]*\([[:space:]]*[0-9]|syscall\.Kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|pkill[[:space:]]+-g[[:space:]]+[0-9]|kill[[:space:]]+-[A-Za-z1-9][A-Za-z0-9]*[[:space:]]+-[0-9]'

# Audited per-line marker: a line carrying `killpg-gate:allow <non-empty reason>` (in a comment) is a
# reviewed exception (e.g. a test deliberately handing the guard a bad pgid); a marker with no reason does nothing.
#
# String/docstring stripper (F3): blanks string literals and triple-quoted docstrings and trailing
# comments so prose and fixture text are not call sites, while real code (including heredoc python in
# .sh files) is still scanned. A string handed to a shell/evaluator (`-c "..."`, eval, system(, exec(,
# popen() is CODE and is kept, as is a bare variable reference "$name" (shell guards/targets use them). An unterminated quote keeps the rest of the line (never hides code).
read -r -d '' STRIP_AWK <<'AWK' || true
BEGIN { tq = ""; Q1 = sprintf("%c", 39); Q2 = sprintf("%c", 34) }
{
  line = $0; n = length(line); out = ""; i = 1
  while (i <= n) {
    if (tq != "") {
      j = index(substr(line, i), tq)
      if (j == 0) { i = n + 1; break }
      i += j - 1 + 3; tq = ""; out = out Q2 Q2; continue
    }
    c = substr(line, i, 1); t3 = substr(line, i, 3)
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) break
    if (t3 == Q2 Q2 Q2 || t3 == Q1 Q1 Q1) {
      j = index(substr(line, i + 3), t3)
      if (j == 0) { tq = t3; i = n + 1; break }
      out = out Q2 Q2; i += 3 + j - 1 + 3; continue
    }
    if (c == Q1 || c == Q2) {
      k = i + 1; closed = 0
      while (k <= n) {
        d = substr(line, k, 1)
        if (d == "\\") { k += 2; continue }
        if (d == c) { closed = 1; break }
        k++
      }
      if (!closed) { out = out substr(line, i); i = n + 1; break }
      pre = substr(line, 1, i - 1)
      body = substr(line, i, k - i + 1)
      if (pre ~ /(-c|eval|system\(|exec\(|popen\()[ \t]*$/ || body ~ /^"\$[{]?[A-Za-z_][A-Za-z0-9_]*[}]?"$/) out = out body
      else out = out c c
      i = k + 1; continue
    }
    out = out c; i++
  }
  print out
}
AWK

unguarded=0
guarded=0

for f in "${files[@]}"; do
    # Strip comment-prefixed lines (# ... or // ...) before matching so this
    # gate's own doc-comments, and any project's comment-only mentions, are
    # never treated as real call sites (§11.4.201(7)(a) — match structure,
    # not substring; a doc mention is a CARRIER, not the thing itself).
    code_only="$(sed -E -e 's/^.*killpg-gate:allow[[:space:]]+[^[:space:]].*$//' -e 's/^[[:space:]]*(#|\/\/).*$//' "$f" 2>/dev/null | awk "$STRIP_AWK" 2>/dev/null || true)"
    [ -n "$code_only" ] || continue

    hit_lines="$(printf '%s\n' "$code_only" | grep -nE "$CALL_ERE" 2>/dev/null || true)"
    # Is this file entitled to the safe_killpg wrapper exemption?  Only when it DEFINES the primitive
    # itself (its body is scanned like any other call) or references the canonical module fc_common, and
    # never when it imports safe_killpg from any other module (a look-alike vendor primitive).
    wrapper_ok=0
    if grep -qE '^[[:space:]]*def[[:space:]]+safe_killpg[[:space:]]*\(|fc_common' <<<"$code_only" \
       && ! { grep -E 'from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import[^#]*safe_killpg' <<<"$code_only" \
              | grep -vE 'from[[:space:]]+([A-Za-z0-9_.]*\.)?fc_common[[:space:]]+import' | grep -q .; }; then
        wrapper_ok=1
    fi

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        lineno="${hit%%:*}"
        text="${hit#*:}"

        # Remove ONLY the exempt pieces of the line, then re-test what remains (a def header with nothing
        # after its colon; a canonical safe_killpg(<identifier>, ...) call). Anything else on the same line
        # (a second raw call, a one-line def body) stays a hit.
        rest="$(sed -E 's/^[[:space:]]*def[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\([^)]*\)[[:space:]]*(->[^:]*)?:[[:space:]]*//' <<<"$text")"
        if [ "$wrapper_ok" -eq 1 ]; then
            rest="$(sed -E 's/(^|[^[:alnum:]_.])(fc_common\.)?_?safe_killpg[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*,[^()]*\)/\1/g' <<<"$rest")"
        fi
        grep -qE "$CALL_ERE" <<<"$rest" || continue

        start=$(( lineno - window ))
        [ "$start" -lt 1 ] && start=1

        window_text="$(printf '%s\n' "$code_only" | sed -n "${start},${lineno}p")"

        target="$(extract_target "$text")"

        # here-strings below, not `printf | grep -q` (SIGPIPE x pipefail class, §11.4.276(C))
        if grep -qE "$LITERAL_TARGET_ERE" <<<"$text"; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — UNGUARDABLE numeric-literal process-group target at ${f}:${lineno}: ${text# }"
            echo "   (a hardcoded numeric pid/pgid can never be guarded — §11.4.263(A): NEVER signal pgid <= 1)"
        elif grep -qE "$GUARD_ERE" <<<"$window_text" \
             && target_guarded "$window_text" "$target"; then
            guarded=$(( guarded + 1 ))
            [ "$quiet" -eq 1 ] || echo "✅ ${GATE}: PASS — guarded process-group signal call at ${f}:${lineno}: ${text# }"
        else
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — UNGUARDED process-group signal call at ${f}:${lineno}: ${text# }"
            echo "   (no '>1' comparator on the call's own target '${target:-<non-identifier expression>}' in the preceding ${window} lines — §11.4.263(B))"
        fi
    done <<< "$hit_lines"
done

echo "======================================================================"
if [ "$unguarded" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${unguarded} unguarded process-group signal call site(s), ${guarded} guarded (§${ANCHOR})"
    exit 1
fi

if [ "$guarded" -gt 0 ]; then
    echo "✅ ${GATE}: PASS — ${guarded} process-group signal call site(s), all guarded (§${ANCHOR})"
else
    echo "✅ ${GATE}: PASS — no process-group signal call sites found under scan root (§${ANCHOR})"
fi
exit 0
