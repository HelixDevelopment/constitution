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
# is the pre-build STATIC scanner half of clause (D)'s four-layer defense.
#
# ── Design (round 4, STRUCTURAL; §11.4.276(E)) ──────────────────────────────
# Whether a string runs depends on data flow, so a text scanner can NOT soundly decide "this string is
# inert prose, that one is a command". The gate therefore does NOT try:
#   * STRINGS ARE CODE-BEARING BY DEFAULT. Every literal in the file (string, docstring, heredoc body,
#     f-string, raw string) that spells a group kill (`killpg(`, `kill -9 -1`, `kill -s S -- -$pg`,
#     `pkill -g`, `syscall.Kill(-p,..)`, ...) is a finding exactly like code. Only REAL COMMENTS are
#     ignored. Fixture / prose text that legitimately spells a kill (a test handing the guard a bad pgid,
#     a docstring) is exempted with the audited allow marker below, on a test path.
#   * PYTHON (.py) is analysed exactly: the source is decoded with the codec it declares
#     (tokenize.detect_encoding, so a `# coding: utf-7` file is read as what it spells), python3
#     `tokenize` yields the comment, string and f-string tokens, comments are blanked precisely, strings
#     are never guessed about, and every non-ASCII identifier is NFKC-normalised (a fullwidth or
#     mathematical-alphanumeric `killpg` IS `killpg` to the interpreter). String items of one argv list or
#     one `+` concatenation that span several lines are joined into one record. A file that does not
#     decode or tokenize is a FAIL (cannot analyse), never a pass.
#   * SHELL (.sh/.bash), GO, RUST, C/C++ are BEST EFFORT: a quote-aware scanner strips comments (shell '#'
#     only at a word start; C-like // and /* */) and tracks quote state. It does not parse nested
#     `$( ... )` quoting or Rust raw strings with embedded quotes. If the quote state is still open at end
#     of file the file is scanned RAW (nothing stripped). A heredoc body is data: its text is scanned
#     like any string, a marker inside it is NOT honoured, and a body fed to `python`/`python3` is
#     re-scanned as Python (its comments are real comments, its strings never fake a guard).
#   * SHELL `kill` forms are decided by ONE operand classifier (awk), not by a regex. Backslash-continued
#     lines are joined first; the operands after the `kill` word are read in order (`-s`/`-n` consume
#     their argument, `--` ends options, the first dash operand is the signal unless it stands alone),
#     so `kill -"$sig" "$pid"` is a signal followed by a pid (not a target) while `kill -9 -$1`,
#     `kill -- -$@`, `kill -9 -$((pg))`, `kill -9 -\1`, `kill -9 -$'1'`, `["kill","-9",f"-{pg}"]` and
#     `"kill -9 -%d" % pg` are group targets that no guard on a plain name can clear.
#
# Three finding types, all scanned on the comment-free text:
#   A  a group-kill CALL / SHELL form anywhere (strings kept): `killpg(`, `kill -9 -1`, `pkill -g`,
#      Go `syscall.Kill(-p)`, Rust `kill(Pid::from_raw(-p))`, ...; guarded only if the call's OWN target
#      identifier is compared to 1 with the RIGHT direction in the preceding window (below).
#   B  a bare, non-call reference to the identifier `killpg` OUTSIDE any string (alias, import-as,
#      default argument, dict value ...): cannot be proven guarded, a finding by construction.
#   C  a string literal that is exactly `killpg` / `x.killpg` (getattr(os, "killpg")), unless it is an
#      operand of ==/!= (a comparison is not a use).
#
# ── Guard rule (direction-aware, §11.4.201 both ways) ───────────────────────
# A window guard must establish `target > 1`: `T > N`, `T <= N` (raise-early) with N>=1; `T >= N`,
# `T < N` (raise-early) with N>=2; mirrored forms `N < T`, `N <= T`... and shell -gt/-le/-ge/-lt likewise.
# `T >= 1` and `T < 1` leave pgid == 1 reachable and are NOT guards. The guard must be on the call's OWN
# target; a comparator on a different variable never clears it. Honest limits (§11.4.6): the scanner does
# not check WHICH branch the comparator controls, and a numeric-literal target (`killpg(1, 9)`,
# `kill -9 -1`) is always a finding (no guard can make a hardcoded 1 safe). A target that is an inline
# expression cannot be proven guarded and is reported (bind the pgid to a name first).
#
# ── Known gaps (documented, not hidden; the reviewer corpus lists the shapes as KNOWN_GAP) ──────────────
# DATA FLOW the scanner does not follow: a function value / alias holding the call (Go `k := syscall.Kill`),
# a command word or operands held in a variable or delivered at run time (`k=kill; $k -9 -1`,
# `xargs kill -9 <<<"-1"`, `set -- -9 -1; kill "$@"`, `str(-pg)` list elements), strings assembled by a
# computation other than `+` / adjacent literals (`"".join`, `%`-formatted names, `chr()`), getattr with a
# computed name, exec wrappers that hide the command. Also: shell quote desync inside nested `$(...)`,
# Rust raw strings with embedded quotes, guard windows fakeable by comment-like text in sh/go, no check of
# which branch a comparator controls, a heredoc whose delimiter is built by expansion, a Python heredoc
# whose body is not valid Python (kept raw: stricter, never laxer), and Unicode normalisation outside
# Python (a fullwidth `killpg` in Go/Rust/C is a different identifier there, so it is correctly not
# a finding).
#
# The sanctioned `fc_common.safe_killpg` wrapper is exempt only behind a real `import fc_common` /
# `from fc_common import safe_killpg` (checked on the non-string view; no rename, no star import, no
# rebinding). A bare `X.killpg = <value>` assignment (monkeypatch) and a `def _fake_killpg(..)` double are
# not signals (their right-hand side / parameters are still scanned).
#
# `scripts/gates` is excluded from the default scan root's recursive walk (this file and its
# mutation-test fixtures legitimately embed the dangerous literal as fixture text).
#
# ── Audited allow marker ─────────────────────────────────────────────────────
# `killpg-gate:allow <non-empty reason>` counts ONLY inside a real comment, ONLY on the line it sits on,
# ONLY in a test path (a tests|test|testing directory, a test_* / *_test.* basename, or a glob in
# KILLPG_GUARD_ALLOW_PATHS); every suppressed line is printed as `ALLOWED file:line reason`, and a marker
# anywhere else is printed as `marker IGNORED` and the line is still scanned.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_killpg_pgid_guard.sh [--root <dir|file>] [--window N] [--quiet]
#     --root <dir>   scan root (default: $KILLPG_GUARD_ROOT or "..")
#     --window N     guard-proximity window in preceding lines
#                     (default: $KILLPG_GUARD_WINDOW or 6)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   KILLPG_GUARD_ROOT         default scan root (else --root, else "..")
#   KILLPG_GUARD_WINDOW       guard-proximity window, lines (default 6)
#   KILLPG_GUARD_ALLOW_PATHS  extra path globs (relative to the scan root) where the audited allow
#                             marker is honoured, in addition to the test-path rules above (read into an
#                             array, never glob-expanded against the cwd)
#   KILLPG_GUARD_EXT          space-separated source extensions to scan
#                             (default: "py go rs c cc cpp h hpp sh bash")
#   KILLPG_GUARD_EXCLUDE      space-separated dir-name globs to prune
#                             (default: ".git node_modules vendor .venv __pycache__ scripts/gates out
#                             build dist)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-hit evidence line (file:line + matched text) + a final PASS / FAIL verdict with the
#   guarded/unguarded hit counts.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no process signaled — the scanner NEVER executes a real
#   killpg/kill syscall, it only reads source text). Temporary files live in a private mktemp -d.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, grep (GNU or BSD ERE), sed, python3 (stdlib only: comment/string extraction). Parses
#   clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.263 (the anchor enforced — full clauses A-F), §11.4.201(1)/(7)(a) (false-positive refusal is a
#   FAIL-bluff; match structure not substring), §11.4.6 (honest documented limits), §11.4.28/§11.4.35
#   (project-agnostic, env-var-driven), §11.4.276 (structural round), §1.1 (paired mutation:
#   cm_killpg_pgid_guard_mutation_test.sh; reviewer corpus: fixtures/killpg_reviewer_corpus.py).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (no dangerous call site found, or every one found is guarded).
#   1 — FAIL (an unguarded process-group signal call site found, or a file that cannot be analysed).
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
        -h|--help) awk 'NR>1 && !/^#/ {exit} {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
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

command -v python3 >/dev/null 2>&1 || { echo "${GATE}: python3 is required (comment/string extraction)" >&2; exit 2; }

# ── Dangerous call-site ERE (comment-free text, STRINGS KEPT) ──────────────
#   * Python/Go/Rust/C:  killpg(          — os.killpg / killpg / nix::killpg
#   * Go:                Kill(-  / Kill(0-  — process-GROUP form (negative pgid)
#   * C/generic:         kill(-           — kill(-pid,sig) process-group form
#   * negation:          kill(pg * -1, sig) — a negated pgid spelled as a product (Go/C/Python)
#   * shell:             pkill -g         — pkill's explicit process-group flag
#   The shell `kill [opts] -<target>` forms are NOT decided by a regex any more: they go through the
#   one operand classifier (SHAWK below), which reads the operands in order and so tells a SIGNAL
#   operand (`kill -"$sig" "$pid"`) from a negated-pgid TARGET (`kill -9 -"$pg"`, `kill -- -$1`).
#   (A bare non-call `killpg` reference is finding type B, decided on the non-string view; an exact
#   "killpg" string is type C.)
QCH=$'["\']'
CALL_ERE='killpg[[:space:]]*\(|(^|[^[:alnum:]_])Kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|from_raw[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|pkill[[:space:]]+-g[[:space:]]|(^|[^[:alnum:]_])[Kk]ill[[:space:]]*\([^,)]*\*[[:space:]]*-[[:space:]]*1'
BARE_KILLPG='(^|[^A-Za-z0-9_])killpg([^A-Za-z0-9_]|$)'

# ── Guard must be scoped to THE CALL'S OWN TARGET, in the RIGHT direction ───
# extract_target <matched-line> — prints the call's target identifier (a bare name or a dotted-attribute
# chain such as `self._pgid`), or nothing when the target is not a plain identifier (a nested call
# expression, an arithmetic expression). An unextractable target is UNGUARDED — conservative by design
# (§11.4.101/§11.4.201): the anchor's own prescribed idiom binds the pgid to a variable and guards it.
# (The shell `kill` forms never come through here: SHAWK reports their target identifier itself.)
extract_target() {
    printf '%s\n' "$1" | sed -E \
        -e 's/.*killpg[[:space:]]*\(//' \
        -e 's/.*syscall\.Kill[[:space:]]*\(//' \
        -e 's/.*[^A-Za-z0-9_][Kk]ill[[:space:]]*\(//' \
        -e 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_:]*::)?[A-Za-z_]*from_raw[[:space:]]*\(//' \
        -e 's/^[[:space:]]*0[[:space:]]*-/-/' \
        -e 's/.*pkill[[:space:]]+-g[[:space:]]+//' \
        | sed -nE 's/^[[:space:]]*-?[[:space:]]*"?\$?\{?([A-Za-z_][A-Za-z0-9_.]*).*/\1/p'
}

# target_guarded <window-text> <target-identifier>
#   0 (guarded) iff the window establishes `target > 1` with a comparator of the RIGHT direction (see the
#   header): T > N / T <= N with N>=1, T >= N / T < N with N>=2, and the mirrored operand order; shell
#   -gt/-le/-ge/-lt likewise. `T >= 1` and `T < 1` are NOT guards (pgid == 1 stays reachable). Any `.` in
#   a dotted chain is regex-escaped. Here-strings (not `printf | grep -q`) avoid the SIGPIPE x pipefail
#   class on a large window (§11.4.276(C)).
NUM1='[1-9][0-9]*'
NUM2='([2-9]|[1-9][0-9]+)'
FILL_L=$'[]"\'})[:space:]]*'
FILL_R=$'[[:space:]"\'${(]*'
target_guarded() {
    _tg_window="$1"; _tg_ident="$2"
    [ -n "$_tg_ident" ] || return 1
    _tg_re="$(sed 's/[.$]/\\&/g' <<<"$_tg_ident")"
    _tg_t="(^|[^A-Za-z0-9_])${_tg_re}${FILL_L}"
    _tg_tail='([^0-9.]|$)'
    _tg_ml='(^|[^0-9.A-Za-z_])'
    _tg_mr="${FILL_R}${_tg_re}"'([^A-Za-z0-9_]|$)'
    grep -qE \
"${_tg_t}(>|-gt)[[:space:]]*${NUM1}${_tg_tail}|${_tg_t}(<=|-le)[[:space:]]*${NUM1}${_tg_tail}|${_tg_t}(>=|-ge)[[:space:]]*${NUM2}${_tg_tail}|${_tg_t}(<|-lt)[[:space:]]*${NUM2}${_tg_tail}|${_tg_ml}${NUM1}[[:space:]]*(<|-lt)${_tg_mr}|${_tg_ml}${NUM2}[[:space:]]*(<=|-le)${_tg_mr}|${_tg_ml}${NUM1}[[:space:]]*(>=|-ge)${_tg_mr}|${_tg_ml}${NUM2}[[:space:]]*(>|-gt)${_tg_mr}" \
        <<<"$_tg_window"
}

# ── Numeric-literal target ⇒ ALWAYS unguarded (§11.4.201 false-negative fix) ─
# A call whose process-group target is a NUMERIC LITERAL (`os.killpg(1, ...)`, `kill(-1, sig)`,
# `syscall.Kill(-1, ...)`, `pkill -g 1`, `kill -9 -1`) is the BOB-126 disaster syscall spelled out in
# source. No guard can make a hardcoded `1` safe; refusing to guess is the conservative-safe default.
LITERAL_TARGET_ERE='killpg[[:space:]]*\([[:space:]]*[0-9]|syscall\.Kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|pkill[[:space:]]+-g[[:space:]]+[0-9]|(^|[^[:alnum:]_])Kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-[[:space:]]*[0-9]|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*0[[:space:]]*-[[:space:]]*[0-9]|from_raw[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]'

# ── The shell-kill OPERAND CLASSIFIER (POSIX awk; no gensub, no {n,m}) ──────────────────────────────────
# Input: "LINENO<TAB>TEXT" records (the strings-kept view, continuation lines already joined; python
# argv lists spread over several lines arrive pre-joined from the extractor). Output: one
# "LINENO<TAB>KIND<TAB>IDENT" per group-kill target found. KIND is LIT (numeric target: unguardable) or
# VAR (a variable / expansion; IDENT is its name, empty when it is not a plain name: $1 $! $@ $* $((..))
# $(..) \$x %d {} ... => unguarded by construction). The text is normalised first (quotes dropped, list
# punctuation turned into blanks) so `kill -s "$sg" -- "-$pg"`, ["kill","-9","-1"] and f"kill -9 -{pg}"
# read the same way. Operands after the kill word are read IN ORDER: `-s`/`-n` consume their argument;
# `--` ends the options; the FIRST dash operand is the signal spec unless it is a lone variable with
# nothing after it (the old `kill -"$pgid"` idiom); every later dash operand is a target. A signal
# operand FOLLOWED BY A PID (`kill -"$sig" "$pid"`, `kill -$s $p`) is therefore not a target, and a
# `-0` / `-s 0` liveness probe delivers no signal at all (kill(2)) and is never flagged.
read -r -d '' SHAWK <<'AWKEOF' || true
BEGIN { FS = "\t" }
function isredir(t) { return (t ~ /^[0-9]*[<>]/ || t ~ /^&[>]/) }
function redirnext(t) { return (t ~ /^[0-9]*[<>]+&?-?$/ || t ~ /^&[>]+$/) }
function skipnoise(k,    t) {
    while (k <= n) {
        t = tk[k]
        if (t == "" || t == "+") { k++; continue }
        if (isredir(t)) { if (redirnext(t)) k++; k++; continue }
        break
    }
    return k
}
function classify(t,    r, r2, id) {
    r = substr(t, 2)
    if (r ~ /^[0-9]/ || r ~ /^\\[0-9]/) { print ln "\tLIT\t"; return }
    if (r ~ /^\$/ || r ~ /^`/ || r ~ /^%/ || r ~ /^\\/ || r ~ /^\002/) {
        r2 = r
        sub(/^\$\{?/, "", r2)
        sub(/^\002/, "", r2)
        id = ""
        if (match(r2, /^[A-Za-z_][A-Za-z0-9_]*/)) id = substr(r2, 1, RLENGTH)
        # A single positional parameter ($1 / ${1}, not $10) is a plain name for guard purposes: the guard
        # must compare THAT parameter ("$1" -gt 1). $! $@ $* $$ $((..)) $(..) stay non-names (unguarded).
        else if (r ~ /^\$\{?[0-9]\}?([^0-9A-Za-z_]|$)/) { match(r, /[0-9]/); id = "$" substr(r, RSTART, 1) }
        print ln "\tVAR\t" id
    }
}
{
    ln = $1
    txt = $0
    sub(/^[^\t]*\t/, "", txt)
    txt = " " txt
    gsub(/[ ,\[(+=][fFrRbBuU][fFrRbBuU]?["']/, " \"", txt)
    gsub(/"/, "", txt)
    gsub(/'/, "", txt)
    gsub(/,/, " ", txt)
    gsub(/\[/, " ", txt)
    gsub(/\]/, " ", txt)
    gsub(/-\{/, "-\002", txt)
    gsub(/\$\(/, "$\003", txt)
    gsub(/[(){}]/, " ", txt)
    gsub(/&&/, ";", txt)
    gsub(/\|\|/, ";", txt)
    gsub(/2>&1/, " ", txt)
    nseg = split(txt, seg, /[;&|]/)
    for (s = 1; s <= nseg; s++) {
        n = split(seg[s], tk, /[ \t]+/)
        kpos = 0
        for (i = 1; i <= n; i++) {
            t = tk[i]
            sub(/^[$`\003<>]*/, "", t)
            sub(/^[A-Za-z_][A-Za-z0-9_]*=/, "", t)
            sub(/^[$`\003<>]*/, "", t)
            if (t == "kill" || t ~ /\/kill$/ || t ~ /[A-Za-z0-9_]\.kill$/) { kpos = i; break }
        }
        if (!kpos) continue
        dd = 0; sigdone = 0; skip = 0
        i = kpos + 1
        while (i <= n && !skip) {
            i = skipnoise(i)
            if (i > n) break
            t = tk[i]
            if (t == "--") { dd = 1; i++; continue }
            if (substr(t, 1, 1) != "-" || length(t) < 2) { i++; continue }
            if (!dd && !sigdone) {
                if (t == "-0") { skip = 1; break }
                if (t == "-s" || t == "-n" || t == "-S") {
                    sigdone = 1
                    j = skipnoise(i + 1)
                    if (j <= n && tk[j] == "0") skip = 1
                    i = j + 1
                    continue
                }
                j = skipnoise(i + 1)
                lone = (j > n)
                r = substr(t, 2)
                forced = (r ~ /^\$\003/ || r ~ /^`/)
                if ((lone || forced) && (r ~ /^\$/ || r ~ /^`/ || r ~ /^%/ || r ~ /^\002/ || r ~ /^\\/)) {
                    classify(t)
                } else if (lone && r ~ /^[0-9]/) {
                    # a bare numeric option with no operand is a signal spec, not a target
                }
                sigdone = 1
                i++
                continue
            }
            classify(t)
            i++
        }
    }
}
AWKEOF

# Backslash-continued lines are one logical command line: join them, attributing the record to the
# FIRST physical line (`kill -9 \<newline> -1`).
read -r -d '' JOINAWK <<'AWKEOF' || true
function flush() { if (have) print first "\t" buf; have = 0; buf = "" }
{
    t = $0
    if (!have) { first = NR; have = 1; buf = "" }
    if (t ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, "", t); buf = buf t " "; next }
    buf = buf t
    flush()
}
END { flush() }
AWKEOF

# ── The comment / string extractor (python3, stdlib only) ───────────────────
# Usage: helper LANG(py|sh|c) FILE ALLOWOK KEEPOUT NSOUT COUT MARKOUT WINOUT JOINOUT
#   KEEPOUT  line-preserving text: real comments blanked, STRINGS KEPT        (finding type A)
#   NSOUT    line-preserving text: comments AND string contents blanked        (finding type B)
#   COUT     one line number per line carrying an exact `killpg` string literal (finding type C)
#   MARKOUT  "KIND<TAB>file:line<TAB>reason" for every audited-marker use (KIND ALLOWED|IGNORED|IGNORED_HD),
#            every record newline-terminated
#   WINOUT   the per-line view the guard WINDOW is read from (python / python-heredoc: strings blanked,
#            so a string can never fake a guard; shell / C-like: strings kept)
#   JOINOUT  "LINE<TAB>TEXT" records: string items of one argv list / concatenation that span several
#            lines, joined (attributed to the first item's line)
# A line carrying a valid marker on an allow-path is blanked entirely in both views. Exit 3 = cannot
# analyse (python tokenize failure, NUL byte): the gate treats that as a FAIL, never a pass.
read -r -d '' PYHELPER <<'PYEOF' || true
import io
import re
import sys
import tokenize
import unicodedata

MARK = re.compile(r'killpg-gate:allow[ \t]+(\S.*)')
STRKILL = re.compile(r'''(["'])(?:[A-Za-z_][A-Za-z0-9_]*\.)*killpg\1''')


def blank(view, sr, sc, er, ec):
    if sr == er:
        row = view[sr - 1]
        for i in range(sc, min(ec, len(row))):
            row[i] = ' '
        return
    row = view[sr - 1]
    for i in range(sc, len(row)):
        row[i] = ' '
    for r in range(sr + 1, er):
        rw = view[r - 1]
        for i in range(len(rw)):
            rw[i] = ' '
    if er - 1 < len(view):
        rw = view[er - 1]
        for i in range(min(ec, len(rw))):
            rw[i] = ' '


def strbody(src):
    m = re.match(r'^[A-Za-z]*("""|\'\'\'|"|\')(.*)\1$', src, re.S)
    return m.group(2) if m else src


def slice_src(lines, start, end):
    (sr, sc), (er, ec) = start, end
    if sr == er:
        return lines[sr - 1][sc:ec]
    parts = [lines[sr - 1][sc:]]
    for r in range(sr + 1, er):
        parts.append(lines[r - 1])
    parts.append(lines[er - 1][:ec])
    return ' '.join(parts)


def joined_records(toks, lines, fstr_start, fstr_end):
    """Runs of >= 2 string items separated only by `,` / `+` / newlines (an argv list or a concatenation that
    spans lines) joined into one record, attributed to the first item's line."""
    recs = []
    cur = []
    plus = []
    first = [0]
    pend = [False]

    def flush():
        if len(cur) >= 2:
            # `+` concatenation joins WITHOUT a blank ("kill" + "pg" is "killpg"); a list comma joins with one.
            txt = cur[0]
            for k in range(1, len(cur)):
                txt += ('' if plus[k] else ' ') + cur[k]
            recs.append((first[0], txt, any(plus[1:])))
        del cur[:]
        del plus[:]
        pend[0] = False

    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        if t.type == tokenize.STRING:
            if not cur:
                first[0] = t.start[0]
            cur.append(strbody(t.string))
            plus.append(pend[0])
            pend[0] = False
            i += 1
        elif fstr_start is not None and t.type == fstr_start:
            depth = 1
            j = i + 1
            while j < n and depth > 0:
                if toks[j].type == fstr_start:
                    depth += 1
                elif toks[j].type == fstr_end:
                    depth -= 1
                j += 1
            if not cur:
                first[0] = t.start[0]
            cur.append(strbody(slice_src(lines, t.start, toks[j - 1].end)))
            plus.append(pend[0])
            pend[0] = False
            i = j
        elif t.type == tokenize.OP and t.string in (',', '+'):
            pend[0] = (t.string == '+')
            i += 1
        elif t.type in (tokenize.NL, tokenize.COMMENT):
            i += 1
        elif t.type == tokenize.OP and t.string in ('[', '(') and not cur:
            i += 1
        else:
            flush()
            i += 1
    flush()
    return recs


def scan_py(text, lines):
    keep = [list(l) for l in lines]
    ns = [list(l) for l in lines]
    marks = {}
    cl = set()
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError, ValueError):
        raise ValueError('untokenizable')
    skip = (tokenize.NL, tokenize.NEWLINE, tokenize.COMMENT, tokenize.INDENT, tokenize.DEDENT)
    fstr = {getattr(tokenize, n) for n in ('FSTRING_START', 'FSTRING_MIDDLE', 'FSTRING_END') if hasattr(tokenize, n)}

    def neighbour(i, step):
        j = i + step
        while 0 <= j < len(toks):
            if toks[j].type not in skip:
                return toks[j]
            j += step
        return None

    for i, tok in enumerate(toks):
        (sr, sc), (er, ec) = tok.start, tok.end
        if tok.type == tokenize.COMMENT:
            m = MARK.search(tok.string)
            if m:
                marks[sr] = m.group(1)
            blank(keep, sr, sc, er, ec)
            blank(ns, sr, sc, er, ec)
        elif tok.type == tokenize.STRING or tok.type in fstr:
            blank(ns, sr, sc, er, ec)
            if tok.type == tokenize.STRING:
                m = re.match(r'^[A-Za-z]*("""|\'\'\'|"|\')(.*)\1$', tok.string, re.S)
                if m and re.fullmatch(r'(?:[A-Za-z_][A-Za-z0-9_]*\.)*killpg', m.group(2)):
                    prv, nxt = neighbour(i, -1), neighbour(i, 1)
                    cmp_ = (prv is not None and prv.type == tokenize.OP and prv.string in ('==', '!=')) or \
                           (nxt is not None and nxt.type == tokenize.OP and nxt.string in ('==', '!='))
                    if not cmp_:
                        cl.add(sr)
    # Python NFKC-normalises identifiers: a fullwidth / mathematical-alphanumeric `killpg` IS `killpg`. Rewrite
    # every non-ASCII NAME token to its NFKC form (last column first, so earlier columns stay valid).
    names = [t for t in toks if t.type == tokenize.NAME and not t.string.isascii()]
    for t in sorted(names, key=lambda t: (t.start[0], -t.start[1])):
        nm = unicodedata.normalize('NFKC', t.string)
        (sr, sc), (er, ec) = t.start, t.end
        if sr == er:
            for view in (keep, ns):
                view[sr - 1][sc:ec] = list(nm)
    fs = getattr(tokenize, 'FSTRING_START', None)
    fe = getattr(tokenize, 'FSTRING_END', None)
    recs = joined_records(toks, lines, fs, fe)
    joined = []
    for ln, txt, cat in recs:
        joined.append((ln, txt))
        if cat and re.fullmatch(r'(?:[A-Za-z_][A-Za-z0-9_]*\.)*killpg', txt.strip()):
            cl.add(ln)
    return keep, ns, cl, marks, joined


HMARK = re.compile(r'#[ \t]*killpg-gate:allow[ \t]+(\S.*)')
HD = re.compile(r'<<(-?)[ \t]*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\2')


PYHD = re.compile(r'(^|[^A-Za-z0-9_])python[0-9.]*([^A-Za-z0-9_]|$)')


def scan_sh(lines):
    n = len(lines)
    keep = [None] * n
    ns = [None] * n
    marks = {}
    hd_marks = {}
    in_sq = in_dq = ansi = False
    hds = []
    bodies = []
    for idx, line in enumerate(lines):
        if hds:
            hd = hds[0]
            body = line.lstrip('\t') if hd['strip'] else line
            keep[idx] = line
            ns[idx] = line
            if body.rstrip('\r') == hd['w']:
                hds.pop(0)
                if hd['py'] and hd['lines']:
                    bodies.append(hd)
                continue
            hd['lines'].append(idx)
            if not hd['py']:
                hm = HMARK.search(line)
                if hm:
                    hd_marks[idx + 1] = hm.group(1)
            continue
        k = list(line)
        s = list(line)
        j = 0
        L = len(line)
        newh = []
        while j < L:
            c = line[j]
            if in_sq:
                if ansi and c == '\\':
                    s[j] = ' '
                    if j + 1 < L:
                        s[j + 1] = ' '
                    j += 2
                    continue
                if c == "'":
                    in_sq = False
                    ansi = False
                else:
                    s[j] = ' '
                j += 1
                continue
            if in_dq:
                if c == '\\':
                    s[j] = ' '
                    if j + 1 < L:
                        s[j + 1] = ' '
                    j += 2
                    continue
                if c == '"':
                    in_dq = False
                else:
                    s[j] = ' '
                j += 1
                continue
            if c == '\\':
                j += 2
                continue
            if c == "'":
                in_sq = True
                ansi = j > 0 and line[j - 1] == '$'
                j += 1
                continue
            if c == '"':
                in_dq = True
                j += 1
                continue
            if c == '#' and (j == 0 or line[j - 1] in ' \t;&|(`'):
                m = MARK.search(line[j:])
                if m:
                    marks[idx + 1] = m.group(1)
                for q in range(j, L):
                    k[q] = ' '
                    s[q] = ' '
                break
            if c == '<' and line.startswith('<<', j):
                if line.startswith('<<<', j):
                    j += 3
                    continue
                m = HD.match(line, j)
                if m:
                    newh.append({'w': m.group(3), 'strip': m.group(1) == '-', 'lines': [],
                                 'py': bool(PYHD.search(line[:j]))})
                    j = m.end()
                    continue
                j += 2
                continue
            j += 1
        keep[idx] = ''.join(k)
        ns[idx] = ''.join(s)
        hds.extend(newh)
    if in_sq or in_dq or hds:
        return list(lines), list(lines), {}, {}, list(lines), []
    win = list(keep)
    joined = []
    # A Python heredoc inside a shell script is PYTHON: its comments are real comments, its strings are not
    # code-bearing for the guard window, and an audited marker in a real Python comment is honoured exactly
    # as in a .py file. A body that does not tokenize stays raw (comments kept, strings kept: stricter).
    for hd in bodies:
        idxs = hd['lines']
        btxt = [lines[i].lstrip('\t') if hd['strip'] else lines[i] for i in idxs]
        try:
            pk, pn, pcl, pm, pj = scan_py('\n'.join(btxt), btxt)
        except ValueError:
            continue
        for off, i in enumerate(idxs):
            if off < len(pk):
                keep[i] = ''.join(pk[off])
                ns[i] = ''.join(pn[off])
                win[i] = ns[i]
        for ln, mt in pm.items():
            marks[idxs[0] + ln] = mt
        for ln, tx in pj:
            joined.append((idxs[0] + ln, tx))
    return keep, ns, marks, hd_marks, win, joined


CHR = re.compile(r"'(?:\\.[^']{0,6}|[^\\'])'")


def scan_c(lines):
    n = len(lines)
    keep = [None] * n
    ns = [None] * n
    marks = {}
    in_blk = in_raw = False
    for idx, line in enumerate(lines):
        k = list(line)
        s = list(line)
        j = 0
        L = len(line)
        while j < L:
            c = line[j]
            if in_blk:
                end = line.find('*/', j)
                stop = L if end < 0 else end + 2
                m = MARK.search(line[j:stop])
                if m:
                    marks[idx + 1] = m.group(1)
                for q in range(j, stop):
                    k[q] = ' '
                    s[q] = ' '
                j = stop
                if end >= 0:
                    in_blk = False
                continue
            if in_raw:
                if c == '`':
                    in_raw = False
                else:
                    s[j] = ' '
                j += 1
                continue
            nx = line[j + 1] if j + 1 < L else ''
            if c == '/' and nx == '/':
                m = MARK.search(line[j:])
                if m:
                    marks[idx + 1] = m.group(1)
                for q in range(j, L):
                    k[q] = ' '
                    s[q] = ' '
                break
            if c == '/' and nx == '*':
                in_blk = True
                end = line.find('*/', j + 2)
                stop = L if end < 0 else end + 2
                m = MARK.search(line[j:stop])
                if m:
                    marks[idx + 1] = m.group(1)
                for q in range(j, stop):
                    k[q] = ' '
                    s[q] = ' '
                j = stop
                if end >= 0:
                    in_blk = False
                continue
            if c == '"':
                q = j + 1
                while q < L and line[q] != '"':
                    q += 2 if line[q] == '\\' else 1
                for r in range(j + 1, min(q, L)):
                    s[r] = ' '
                j = q + 1
                continue
            if c == '`':
                in_raw = True
                j += 1
                continue
            if c == "'":
                m = CHR.match(line, j)
                if m:
                    for r in range(j + 1, m.end() - 1):
                        s[r] = ' '
                    j = m.end()
                    continue
            j += 1
        keep[idx] = ''.join(k)
        ns[idx] = ''.join(s)
    if in_blk or in_raw:
        return list(lines), list(lines), {}, True
    return keep, ns, marks, False


def decode_py(raw):
    try:
        enc, _first = tokenize.detect_encoding(io.BytesIO(raw).readline)
        return raw.decode(enc)
    except (SyntaxError, LookupError, UnicodeDecodeError, ValueError):
        sys.exit(3)


def main():
    lang, path, allowok, keepf, nsf, cf, mf, winf, joinf = sys.argv[1:10]
    allowok = allowok == '1'
    with open(path, 'rb') as fh:
        raw = fh.read()
    if lang == 'py':
        text = decode_py(raw)
    else:
        text = raw.decode('utf-8', errors='replace')
    if '\x00' in text:
        sys.exit(3)
    lines = text.split('\n')
    cl = set()
    hd_marks = {}
    joined = []
    if lang == 'py':
        try:
            keep, ns, cl, marks, joined = scan_py(text, lines)
        except ValueError:
            sys.exit(3)
        keep = [''.join(r) for r in keep]
        ns = [''.join(r) for r in ns]
        win = list(ns)
    else:
        if lang == 'sh':
            keep, ns, marks, hd_marks, win, joined = scan_sh(lines)
        else:
            keep, ns, marks, _raw = scan_c(lines)
            win = list(keep)
        for i, ln in enumerate(keep):
            for m in STRKILL.finditer(ln):
                before = ln[:m.start()].rstrip()
                after = ln[m.end():].lstrip()
                if before.endswith(('==', '!=', '=~')) or after.startswith(('==', '!=')):
                    continue
                cl.add(i + 1)
    out = []
    for ln in sorted(marks):
        if allowok:
            if ln - 1 < len(keep):
                keep[ln - 1] = ''
                ns[ln - 1] = ''
                win[ln - 1] = ''
            cl.discard(ln)
            kind = 'ALLOWED'
        else:
            kind = 'IGNORED'
        out.append('%s\t%s:%d\t%s' % (kind, path, ln, marks[ln].strip()))
    for ln in sorted(hd_marks):
        if ln not in marks:
            out.append('IGNORED_HD\t%s:%d\t%s' % (path, ln, hd_marks[ln].strip()))
    with open(keepf, 'w', encoding='utf-8', errors='replace') as fh:
        fh.write('\n'.join(keep))
    with open(nsf, 'w', encoding='utf-8', errors='replace') as fh:
        fh.write('\n'.join(ns))
    with open(winf, 'w', encoding='utf-8', errors='replace') as fh:
        fh.write('\n'.join(win))
    with open(cf, 'w') as fh:
        fh.write('\n'.join(str(x) for x in sorted(cl)))
    # Every record ends with a newline: a reader using `while read` drops an unterminated last record.
    with open(mf, 'w', encoding='utf-8', errors='replace') as fh:
        fh.write(''.join(x + '\n' for x in out))
    with open(joinf, 'w', encoding='utf-8', errors='replace') as fh:
        fh.write(''.join('%d\t%s\n' % (ln, re.sub(r'[\t\r\n]+', ' ', tx)) for ln, tx in joined))


main()
PYEOF

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/killpg_gate.XXXXXX")"
trap 'rm -rf "${TMPD:?}"' EXIT
HELPER="${TMPD}/strip.py"
printf '%s\n' "$PYHELPER" > "$HELPER"
SHAWKF="${TMPD}/sh.awk"; printf '%s\n' "$SHAWK" > "$SHAWKF"
JOINAWKF="${TMPD}/join.awk"; printf '%s\n' "$JOINAWK" > "$JOINAWKF"
KEEPF="${TMPD}/keep.txt"; NSF="${TMPD}/ns.txt"; CF="${TMPD}/c.txt"; MF="${TMPD}/marks.txt"
WINF="${TMPD}/win.txt"; JOINF="${TMPD}/join.txt"; SHF="${TMPD}/sh_rows.txt"; SHIN="${TMPD}/sh_in.txt"

unguarded=0
guarded=0
allowed_n=0
# Consumer DATA (§11.4.35): extra path globs (relative to the scan root) that may carry the audited marker.
# Read into an ARRAY: a glob such as '*' must stay a pattern and never expand against the cwd.
read -r -a allow_globs <<<"${KILLPG_GUARD_ALLOW_PATHS:-}"

# allow_path_ok <relative-path>  — the audited allow marker is honoured ONLY on a test path:
#   a `tests`/`test`/`testing` directory component, a `test_*` basename, a `*_test.*`/`*_tests.*` basename,
#   or a glob in KILLPG_GUARD_ALLOW_PATHS.
allow_path_ok() {
    _ap_rel="$1"; _ap_base="${_ap_rel##*/}"
    case "/${_ap_rel}" in */tests/*|*/test/*|*/testing/*) return 0 ;; esac
    case "$_ap_base" in test_*|*_test.*|*_tests.*) return 0 ;; esac
    for _ap_g in "${allow_globs[@]}"; do
        [ -n "$_ap_g" ] || continue
        # shellcheck disable=SC2254
        case "$_ap_rel" in $_ap_g) return 0 ;; esac
    done
    return 1
}

# apply_exempt <line-text> — print the text with ONLY the exempt pieces removed (a def header with nothing
# after its colon; a canonical safe_killpg(<identifier>, ...) call; a `X.killpg = value` LHS). Reads the
# per-file flags def_here / disq / ok_qual / ok_bare / ok_alias set below.
apply_exempt() {
    local rest="$1" nm
    if [ "$def_here" -eq 1 ] && [ "$disq" -eq 0 ]; then
        rest="$(sed -E 's/^def[[:space:]]+safe_killpg[[:space:]]*\([^)]*\)[[:space:]]*(->[^:]*)?:[[:space:]]*//' <<<"$rest")"
    fi
    if [ "$ok_qual" -eq 1 ]; then
        rest="$(sed -E "s/(^|[^[:alnum:]_.])fc_common\\.safe_killpg${WRAP_ARG}/\\1/g" <<<"$rest")"
    fi
    if [ "$ok_bare" -eq 1 ]; then
        rest="$(sed -E "s/(^|[^[:alnum:]_.])safe_killpg${WRAP_ARG}/\\1/g" <<<"$rest")"
    fi
    if [ "$ok_alias" -eq 1 ]; then
        rest="$(sed -E "s/(^|[^[:alnum:]_.])_safe_killpg${WRAP_ARG}/\\1/g" <<<"$rest")"
        rest="$(sed -E 's/^[[:space:]]*_safe_killpg[[:space:]]*=[[:space:]]*fc_common\.safe_killpg[[:space:]]*;?[[:space:]]*$//' <<<"$rest")"
    fi
    # A def header of a function merely NAMED *killpg (a test double) is a definition, not a signal; the
    # names killpg / safe_killpg / _safe_killpg themselves are never stripped here. A bare `X.killpg =
    # <value>` assignment REPLACES the attribute (monkeypatch) and signals nothing; its right-hand side is
    # still scanned.
    if [[ "$rest" =~ ^[[:space:]]*def[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*\( ]]; then
        nm="${BASH_REMATCH[1]}"
        case "$nm" in
            killpg|safe_killpg|_safe_killpg) : ;;
            *killpg) case "${rest#*(}" in
                *killpg*) : ;;   # killpg mentioned in the parameters / one-line body: stays a finding
                *) rest="$(sed -E 's/^([[:space:]]*)def[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\([^)]*\)[[:space:]]*(->[^:]*)?:/\1/' <<<"$rest")" ;;
               esac ;;
            *) : ;;
        esac
    fi
    sed -E 's/(^|;)([[:space:]]*)[A-Za-z_][A-Za-z0-9_.]*\.killpg[[:space:]]*=([^=])/\1\2_lhs_ =\3/g' <<<"$rest"
}

WRAP_ARG='[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*,[^()]*\)'

for f in "${files[@]}"; do
    if [ "$root_is_file" -eq 1 ]; then rel="${f##*/}"; else rel="${f#"$root"/}"; fi

    case "${f##*.}" in
        py) langx=py ;;
        sh|bash) langx=sh ;;
        *) langx=c ;;
    esac
    # Cheap prefilter: every finding type contains `kill` or `Kill`. A Python file is also analysed when it
    # has any non-ASCII byte or a coding cookie: Python NFKC-normalises identifiers and decodes the source
    # with the declared codec, so a fullwidth `ｋｉｌｌｐｇ` or a `# coding: utf-7` file spells `killpg`
    # without those ASCII letters on disk.
    pre_pat='[kK]ill'
    [ "$langx" = py ] && pre_pat='[kK]ill|[^[:print:][:space:]]|coding[:=]'
    LC_ALL=C grep -qE "$pre_pat" "$f" 2>/dev/null
    pre_rc=$?
    if [ "$pre_rc" -eq 1 ]; then continue; fi
    if [ "$pre_rc" -ne 0 ]; then
        unguarded=$(( unguarded + 1 ))
        echo "❌ ${GATE}: FAIL — cannot read ${f}; refusing to treat an unreadable file as clean (§11.4.201(4))"
        continue
    fi

    allowok=0
    allow_path_ok "$rel" && allowok=1
    : > "$MF"

    python3 -I "$HELPER" "$langx" "$f" "$allowok" "$KEEPF" "$NSF" "$CF" "$MF" "$WINF" "$JOINF" 2>/dev/null
    helper_rc=$?
    if [ "$helper_rc" -ne 0 ]; then
        unguarded=$(( unguarded + 1 ))
        echo "❌ ${GATE}: FAIL — cannot analyse ${f} (extractor exit ${helper_rc}); refusing to treat an unreadable file as clean (§11.4.201(4))"
        continue
    fi
    # Report every audited-marker decision (a suppression is never silent). `|| [ -n "$kind" ]` keeps an
    # unterminated last record (the helper terminates every record, but a reader must not depend on it).
    while IFS=$'\t' read -r kind where reason || [ -n "$kind" ]; do
        [ -n "$kind" ] || continue
        case "$kind" in
            ALLOWED)
                allowed_n=$(( allowed_n + 1 ))
                echo "ℹ️  ${GATE}: ALLOWED ${where} ${reason}" ;;
            IGNORED_HD)
                echo "⚠️  ${GATE}: marker IGNORED at ${where} (inside a shell heredoc body: data, not a comment) — the line is still scanned: ${reason}" ;;
            *)
                echo "⚠️  ${GATE}: marker IGNORED at ${where} (not a test path: ${rel}) — the line is still scanned: ${reason}" ;;
        esac
    done < "$MF"

    code_keep="$(<"$KEEPF")"
    code_ns="$(<"$NSF")"
    c_lines="$(<"$CF")"
    window_src="$(<"$WINF")"
    # Adjacent string items of one argv list are joined (["kill","-9","-1"] -> ["kill -9 -1"]).
    code_keep="$(sed -E "s/${QCH}[[:space:]]*,[[:space:]]*${QCH}/ /g" <<<"$code_keep")"

    # Shell-kill operand rows (LINE<TAB>LIT|VAR<TAB>IDENT) over the strings-kept view (continued lines
    # joined) plus the joined multi-line argv / concatenation records.
    { awk -f "$JOINAWKF" "$KEEPF"; cat "$JOINF"; } > "$SHIN"
    awk -f "$SHAWKF" "$SHIN" > "$SHF"
    sh_nums="$(cut -f1 "$SHF" | sort -un || true)"
    j_nums=""
    while IFS=$'\t' read -r jl jt || [ -n "$jl" ]; do
        [ -n "$jl" ] || continue
        if grep -qE "${CALL_ERE}|${LITERAL_TARGET_ERE}" <<<"$jt"; then j_nums="${j_nums}${jl}"$'\n'; fi
    done < "$JOINF"

    # Hit lines: type A on the strings-kept view, type B on the non-string view, type C from the helper.
    a_nums="$(grep -nE "$CALL_ERE" <<<"$code_keep" 2>/dev/null | cut -d: -f1 || true)"
    b_nums="$(grep -nE "$BARE_KILLPG" <<<"$code_ns" 2>/dev/null | cut -d: -f1 || true)"
    hit_nums="$(printf '%s\n%s\n%s\n%s\n%s\n' "$a_nums" "$b_nums" "$c_lines" "$sh_nums" "$j_nums" | grep -E '^[0-9]+$' | sort -un || true)"
    [ -n "$hit_nums" ] || continue

    # ── The sanctioned safe_killpg wrapper exemption, bound to REAL bindings ─────────────────────────────
    # Granted only by a genuine `import fc_common` / `from fc_common import safe_killpg` line (no `as`
    # rename, no star import) or by the file DEFINING safe_killpg at module level, and withdrawn by ANY
    # rebinding of fc_common / safe_killpg / _safe_killpg in the file. Decided on the NON-STRING view, so
    # text inside a string can neither grant nor withdraw it.
    disq=0
    grep -qE '^[[:space:]]*from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import[[:space:]]+\*' <<<"$code_ns" && disq=1
    if grep -vE '^[[:space:]]*_safe_killpg[[:space:]]*=[[:space:]]*fc_common\.safe_killpg[[:space:]]*;?[[:space:]]*$' <<<"$code_ns" \
         | grep -qE '(^|[^A-Za-z0-9_.])(fc_common|safe_killpg|_safe_killpg)[[:space:]]*(=[^=]|:=|:[^=]*=[^=])'; then
        disq=1
    fi
    grep -qE '(^|[^A-Za-z0-9_])sys[[:space:]]*\.[[:space:]]*modules' <<<"$code_ns" && disq=1
    [ "$(grep -cE '(^|[^A-Za-z0-9_.])_safe_killpg[[:space:]]*(=[^=]|:=)' <<<"$code_ns")" -gt 1 ] && disq=1
    grep -qE '(^|[[:space:]])as[[:space:]]+(fc_common|safe_killpg|_safe_killpg)([^A-Za-z0-9_]|$)' <<<"$code_ns" && disq=1
    grep -qE '^[[:space:]]*(global|nonlocal|del|for|with)[[:space:]]+([^#]*[^A-Za-z0-9_.])?(fc_common|safe_killpg)([^A-Za-z0-9_]|$)' <<<"$code_ns" && disq=1
    grep -qE '^[[:space:]]+def[[:space:]]+(safe_killpg|_safe_killpg)|^[[:space:]]*class[[:space:]]+(fc_common|safe_killpg)' <<<"$code_ns" && disq=1
    if grep -E 'from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import[^#]*safe_killpg' <<<"$code_ns" \
         | grep -vE 'from[[:space:]]+fc_common[[:space:]]+import[[:space:]]+safe_killpg[[:space:]]*$' | grep -q .; then
        disq=1
    fi
    has_imp_mod=0; has_from_imp=0; def_here=0; alias_ok=0
    grep -qE '^[[:space:]]*import[[:space:]]+fc_common[[:space:]]*;?[[:space:]]*$' <<<"$code_ns" && has_imp_mod=1
    grep -qE '^[[:space:]]*from[[:space:]]+fc_common[[:space:]]+import[[:space:]]+safe_killpg[[:space:]]*$' <<<"$code_ns" && has_from_imp=1
    grep -qE '^def[[:space:]]+safe_killpg[[:space:]]*\(' <<<"$code_ns" && def_here=1
    grep -qE '^[[:space:]]*_safe_killpg[[:space:]]*=[[:space:]]*fc_common\.safe_killpg[[:space:]]*;?[[:space:]]*$' <<<"$code_ns" && alias_ok=1
    ok_qual=0; ok_bare=0; ok_alias=0
    if [ "$disq" -eq 0 ]; then
        [ "$has_imp_mod" -eq 1 ] && ok_qual=1
        { [ "$has_from_imp" -eq 1 ] || [ "$def_here" -eq 1 ]; } && ok_bare=1
        [ "$alias_ok" -eq 1 ] && [ "$ok_qual" -eq 1 ] && ok_alias=1
    fi

    # The guard window (WINF) is read from the non-string view for Python and for python heredoc bodies (a
    # string can never fake a guard), and from the strings-kept view for shell/C-like (a shell guard
    # `[ "$pg" -gt 1 ]` lives inside quotes).

    while IFS= read -r lineno; do
        [ -n "$lineno" ] || continue
        textK="$(sed -n "${lineno}p" <<<"$code_keep")"
        textN="$(sed -n "${lineno}p" <<<"$code_ns")"
        restK="$(apply_exempt "$textK")"
        restN="$(apply_exempt "$textN")"

        a_hit=0; b_hit=0; c_hit=0
        grep -qE "$CALL_ERE" <<<"$restK" && a_hit=1
        # B: a non-call reference to the identifier `killpg` outside any string.
        alias_ref="$(sed -E 's/(^|[^A-Za-z0-9_])killpg[[:space:]]*\(/\1@CALL@(/g' <<<"$restN")"
        grep -qE "$BARE_KILLPG" <<<"$alias_ref" && b_hit=1
        # C: an exact `killpg` string literal.
        grep -qxF "$lineno" <<<"$c_lines" && c_hit=1

        text="$textK"
        start=$(( lineno - window ))
        [ "$start" -lt 1 ] && start=1
        window_text="$(sed -n "${start},${lineno}p" <<<"$window_src")"

        # Candidate call texts: this line's own text, and every joined multi-line record that spells a call.
        cands=()
        [ "$a_hit" -eq 1 ] && cands+=("$textK")
        jlit=0
        while IFS=$'\t' read -r jl jt || [ -n "$jl" ]; do
            [ "$jl" = "$lineno" ] || continue
            grep -qE "$CALL_ERE" <<<"$jt" && cands+=("$jt")
            grep -qE "$LITERAL_TARGET_ERE" <<<"$jt" && jlit=1
        done < "$JOINF"
        # Shell-kill operand rows of this line: LIT is unguardable; a VAR must be guarded on its own name.
        sh_n=0; sh_lit=0; sh_bad=0; sh_ident=""
        while IFS=$'\t' read -r rl rk rid || [ -n "$rl" ]; do
            [ "$rl" = "$lineno" ] || continue
            sh_n=$(( sh_n + 1 ))
            if [ "$rk" = LIT ]; then
                sh_lit=1
            elif ! target_guarded "$window_text" "$rid"; then
                sh_bad=1; sh_ident="$rid"
            fi
        done < "$SHF"
        [ $(( b_hit + c_hit + ${#cands[@]} + sh_n + jlit )) -gt 0 ] || continue

        if [ "$b_hit" -eq 1 ]; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — non-call reference to killpg (alias/indirect use) at ${f}:${lineno}: ${text# }"
            echo "   (an alias, getattr, import-as, dict value or default argument holding killpg cannot be proven guarded — §11.4.263(B); call it directly behind a '>1' guard or use fc_common.safe_killpg)"
        elif [ "$c_hit" -eq 1 ]; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — string literal naming killpg (indirect lookup) at ${f}:${lineno}: ${text# }"
            echo "   (getattr(os, \"killpg\") and friends resolve the call at run time and cannot be proven guarded — §11.4.263(B); a test fixture text needs the audited marker on a test path)"
        elif [ "$sh_lit" -eq 1 ] || [ "$jlit" -eq 1 ] || grep -qE "$LITERAL_TARGET_ERE" <<<"$textK"; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — UNGUARDABLE numeric-literal process-group target at ${f}:${lineno}: ${text# }"
            echo "   (a hardcoded numeric pid/pgid can never be guarded — §11.4.263(A): NEVER signal pgid <= 1; text inside a string or docstring counts too — use the audited marker on a test path for fixture text)"
        else
            bad=0; target=""
            for ctext in "${cands[@]+"${cands[@]}"}"; do
                target="$(extract_target "$ctext")"
                target_guarded "$window_text" "$target" || { bad=1; break; }
            done
            if [ "$sh_bad" -eq 1 ]; then bad=1; target="$sh_ident"; fi
            if [ "$bad" -eq 0 ]; then
                guarded=$(( guarded + 1 ))
                [ "$quiet" -eq 1 ] || echo "✅ ${GATE}: PASS — guarded process-group signal call at ${f}:${lineno}: ${text# }"
            else
                unguarded=$(( unguarded + 1 ))
                echo "❌ ${GATE}: FAIL — UNGUARDED process-group signal call at ${f}:${lineno}: ${text# }"
                echo "   (no direction-correct '>1' comparator on the call's own target '${target:-<non-identifier expression>}' in the preceding ${window} lines — §11.4.263(B))"
            fi
        fi
    done <<< "$hit_nums"
done

echo "======================================================================"
if [ "$allowed_n" -gt 0 ]; then
    echo "ℹ️  ${GATE}: ${allowed_n} call site(s) suppressed by the audited allow marker (listed above as ALLOWED)"
fi
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
