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
# Shell-form detection is deliberately NARROW but covers the real spellings: `pkill -g`, and a negated
# group target after `kill` with any option/signal words (`kill -9 -"$pg"`, `kill -s KILL -"$pg"`,
# `kill -9 -- -"$pg"`, `kill -- -1`), plus Python `subprocess`/`os.system`/`sh -c` strings, Go
# `syscall.Kill(-p, ..)` / `unix.Kill(0-p, ..)`, Rust `kill(Pid::from_raw(-p), ..)`. An ordinary
# single-process `kill -9 $pid` is NOT flagged (precision matters, §11.4.201(1)).
#
# ── What counts as code (round 3: structural, not a line blanker; §11.4.276(C)) ─────────────────────
# One awk tokenizer (per language: py | sh | c-like) blanks ONLY text that is provably inert: real
# comments, string literals not handed to an executor, heredoc bodies of cat/tee/read. Everything else,
# and anything it cannot parse, stays CODE (fail closed): strings given to run/Popen/system/call-class
# sinks, any `shell=True` line, any string after `-c`/`-e`, unknown shell command words, `$(..)`/backtick
# content inside double quotes, f-string replacement fields, python3 heredoc bodies (scanned as python)
# and sh-family heredoc bodies (scanned as shell). Triple quotes are tracked for `.py` only; shell single
# quotes take no backslash escapes. A tokenizer failure is a FAIL, never a pass.
#
# A non-call mention of the identifier `killpg` (alias, getattr, import-as, default argument, dict value)
# is a finding; a bare `X.killpg = <value>` assignment (monkeypatch) and a `def _fake_killpg(..)` double
# are not signals (their right-hand side / parameters are still scanned). The sanctioned
# `fc_common.safe_killpg` wrapper is exempt only behind a real `import fc_common` / `from fc_common import
# safe_killpg` (no rename, no star import, no rebinding).
#
# `scripts/gates` is excluded from the default scan root's recursive walk (this file and its
# mutation-test fixtures legitimately embed the dangerous literal as fixture text). The guard is
# target-scoped: a `>1`-style comparator on the call's OWN target identifier (any variable name) in the
# preceding window; a comparator on a different variable never clears it.
#
# ── Audited allow marker ─────────────────────────────────────────────────────
# `killpg-gate:allow <non-empty reason>` counts ONLY inside a real comment, ONLY in a test path (a
# tests|test|testing directory, a test_* / *_test.* basename, or a glob in KILLPG_GUARD_ALLOW_PATHS);
# every suppressed line is printed as `ALLOWED file:line reason`, and a marker anywhere else is printed
# as `marker IGNORED` and the line is still scanned.
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
#   KILLPG_GUARD_ALLOW_PATHS  extra path globs (relative to the scan root) where the audited allow
#                            marker is honoured, in addition to the test-path rules above
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
#   * (round 3) ANY non-call reference to the identifier `killpg` (an alias, `getattr`, an import-as, a
#     dict value, a default argument, a tuple unpack ...) — the simplest fail-closed rule for the alias
#     class: a reference cannot be guarded, so it is a finding unless it is the sanctioned wrapper;
#   * (round 3) more spellings of the shell group kill: options between `kill` and the negated target
#     (`kill -9 -- -1`, `kill -- -1`, `kill -s KILL -"$pg"`, `kill -9 "-$pg"`), the same inside an argv
#     list (`["kill","-9","-1"]` — adjacent string items are joined before matching), `os.kill(0 - pg, ..)`,
#     Go `unix.Kill(-p, ..)` / `syscall.Kill(0-p, ..)`, Rust `kill(Pid::from_raw(-p), ..)`.
QCH=$'["\']'
SH_OPTS='([[:space:]]+(-[A-Za-z1-9][A-Za-z0-9]*([[:space:]]+[A-Za-z1-9][A-Za-z0-9]*)?|--))+'
SH_KILL='(^|[^[:alnum:]_.-])kill'
SH_TGT_VAR="[[:space:]]+${QCH}?-${QCH}?"'\$\{?[A-Za-z_]'
SH_TGT_NUM="[[:space:]]+${QCH}?-${QCH}?"'[0-9]'
CALL_ERE='killpg[[:space:]]*\(|(^|[^A-Za-z0-9_])killpg([^A-Za-z0-9_]|$)|(^|[^[:alnum:]_])Kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|from_raw[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-|pkill[[:space:]]+-g[[:space:]]|kill[[:space:]]+-"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|kill[[:space:]]+-[A-Za-z1-9][A-Za-z0-9]*[[:space:]]+-("?\$\{?[A-Za-z_]|[0-9])'
CALL_ERE="${CALL_ERE}|${SH_KILL}${SH_OPTS}(${SH_TGT_VAR}|${SH_TGT_NUM})"

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
    _et_sh="$(printf '%s\n' "$1" | sed -nE "s/^.*${SH_KILL}${SH_OPTS}[[:space:]]+(${QCH}?-.*)\$/\\5/p")"
    if [ -n "$_et_sh" ]; then
        printf '%s\n' "$_et_sh" | sed -nE "s/^[[:space:]]*${QCH}?-${QCH}?\"?\\\$?\\{?([A-Za-z_][A-Za-z0-9_.]*).*/\\1/p"
        return 0
    fi
    printf '%s\n' "$1" | sed -E \
        -e 's/.*killpg[[:space:]]*\(//' \
        -e 's/.*syscall\.Kill[[:space:]]*\(//' \
        -e 's/.*[^A-Za-z0-9_][Kk]ill[[:space:]]*\(//' \
        -e 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_:]*::)?[A-Za-z_]*from_raw[[:space:]]*\(//' \
        -e 's/^[[:space:]]*0[[:space:]]*-/-/' \
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
LITERAL_TARGET_ERE='killpg[[:space:]]*\([[:space:]]*[0-9]|syscall\.Kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]|pkill[[:space:]]+-g[[:space:]]+[0-9]|kill[[:space:]]+-[A-Za-z1-9][A-Za-z0-9]*[[:space:]]+-[0-9]|(^|[^[:alnum:]_])Kill[[:space:]]*\([[:space:]]*(0[[:space:]]*)?-[[:space:]]*[0-9]|(^|[^[:alnum:]_])kill[[:space:]]*\([[:space:]]*0[[:space:]]*-[[:space:]]*[0-9]|from_raw[[:space:]]*\([[:space:]]*-[[:space:]]*[0-9]'
LITERAL_TARGET_ERE="${LITERAL_TARGET_ERE}|${SH_KILL}${SH_OPTS}${SH_TGT_NUM}"

# Audited per-line marker: a line carrying `killpg-gate:allow <non-empty reason>` (in a comment) is a
# reviewed exception (e.g. a test deliberately handing the guard a bad pgid); a marker with no reason does nothing.
#
# Code extractor (round-3 structural replacement of the F3 blanker, §11.4.276(C) class closure).
# One awk program, per-language mode (py | sh | c-like), line-preserving. It blanks ONLY text that is
# provably inert and keeps everything else (including anything it cannot parse) as CODE:
#   * real comments (py '#', sh '#' at word start, c-like '//' and '/* */');
#   * string literals that are not handed to an executor. Code strings: any string inside a call whose
#     callee name looks like an exec/shell/run/call/popen/system sink, any string on a `shell=True` line,
#     any string after a `-c`/`-e` argument, a string that is exactly `killpg`/`x.killpg`; in shell, a
#     string at a command position whose command word is not a known text-only builtin (unknown command
#     => code), a string piped into a shell, and `$(...)` / backtick contents inside double quotes;
#   * f-string replacement fields are always code (emitted next to the blanked literal);
#   * triple quotes are tracked for `py` mode only (never for sh/c-like), shell single quotes take no
#     escapes (ANSI-C `$'..'` does), Go raw strings span lines;
#   * heredoc bodies are inert ONLY for `cat`/`tee`/`read` consumers; `python*` bodies are scanned as
#     python, `sh`-family bodies as shell, every other consumer's body is raw code; a heredoc whose
#     terminator is not found is not a heredoc (never swallows the rest of the file);
#   * the audited allow marker `killpg-gate:allow <reason>` counts ONLY inside a real comment, ONLY on a
#     test path (ALLOWOK), and every use is recorded (the gate prints it as ALLOWED).
read -r -d '' STRIP_AWK <<'AWK' || true
# Structural, per-language, fail-closed code extractor for CM-KILLPG-PGID-GUARD.
# One output line per input line. Only text PROVABLY inert is blanked: real comments, inert strings
# (not handed to an executor), inert heredoc bodies. Everything else (and anything unparseable) stays CODE.
# Vars: LANGX (py|sh|c)  ALLOWOK (1 if this file's path may carry the audited allow marker)
#       FNAME  ALLOWLOG (path; ALLOWED/IGNORED records are appended as "KIND<TAB>file:line<TAB>reason")
function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
function callee_is_sink(pre,    k, nm) {
  pre = rtrim(pre); k = length(pre); nm = ""
  while (k >= 1 && substr(pre, k, 1) ~ /[A-Za-z0-9_.]/) { nm = substr(pre, k, 1) nm; k-- }
  nm = tolower(nm)
  if (nm == "") return 0
  return (nm ~ /(run|exec|shell|system|spawn|popen|call|cmd|command|eval|bash|output|getattr|setattr|import_module|__import__|(^|[.])sh$)/)
}
function comment_seen(cm, lineno,    r) {
  if (cm ~ /killpg-gate:allow[ \t]+[^ \t]/) {
    r = cm; sub(/^.*killpg-gate:allow[ \t]+/, "", r)
    if (ALLOWOK == 1) { allowed_line = 1; printf "ALLOWED\t%s:%d\t%s\n", FNAME, lineno, r >> ALLOWLOG }
    else printf "IGNORED\t%s:%d\t%s\n", FNAME, lineno, r >> ALLOWLOG
  }
}
function sh_str_is_code(seg,    t, w, guard) {
  t = ltrim(seg)
  if (substr(t, 1, 5) == "@ARR@") return 0
  if (LINEPIPE) return 1
  if (t ~ /(^|[ \t])(-[A-Za-z]*[ce]|--command|--eval)[ \t]*$/) return 1
  guard = 0
  while (guard++ < 12 && t ~ /^(if|then|elif|else|do|while|until|time|!|\{|\()([ \t]+|$)/) { sub(/^(if|then|elif|else|do|while|until|time|!|\{|\()([ \t]+|$)/, "", t) }
  while (t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=[^ \t]*[ \t]+/) sub(/^[A-Za-z_][A-Za-z0-9_]*\+?=[^ \t]*[ \t]+/, "", t)
  if (t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) return 0
  if (t == "") return 0
  w = t; sub(/[ \t].*$/, "", w)
  if (w ~ /^[$`]/ || w == "S") return 1
  if (t ~ /(^|[ \t\/])(eval|exec|ssh|su|sudo|nohup|env|timeout|nice|watch|xargs|setsid|trap|python[0-9.]*|perl|ruby|node|awk|gawk|sh|bash|zsh|dash|ksh|busybox|docker|podman|kubectl|chroot|flock|runuser|unshare|nsenter|fakeroot|strace|taskset|chrt|ionice|stdbuf|systemd-run|parallel|tmux|doas|pkexec|bwrap|firejail|nsjail)([ \t]|$)/) return 1
  sub(/^.*\//, "", w)
  if (w ~ /^(echo|printf|cat|tee|grep|egrep|fgrep|rg|sed|read|local|declare|typeset|export|readonly|return|set|unset|shift|for|case|select|let|test|\[|\[\[|true|false|:|print|basename|dirname|head|tail|wc|sort|uniq|cut|tr|diff|cmp|ls|cp|mv|mkdir|touch|chmod|cd|pwd|git|sleep|date|mktemp|readlink|realpath|printenv|expr|wait|mapfile|readarray|ok|bad|pass|fail|skip|warn|info|say|note|log|die)$/) return 0
  return 1
}
function lit_is_code(body) {
  if (STMTSHELL) return 1
  if (sdepth > 0 && pd >= sinkpd[sdepth]) return 1
  if (lastq != "" && lastq ~ /^-[A-Za-z]*[ce]$/ && sincestr ~ /^[ \t,\[]*$/) return 1
  if (body ~ /^([A-Za-z0-9_.:]*[.:])?killpg$/) return 1
  return 0
}
function f_fields(body,    j, m, dep, e, r, ch) {
  r = ""; m = length(body); j = 1
  while (j <= m) {
    ch = substr(body, j, 1)
    if (ch == "{" && substr(body, j + 1, 1) == "{") { j += 2; continue }
    if (ch == "{") {
      dep = 1; e = ""; j++
      while (j <= m && dep > 0) { ch = substr(body, j, 1); if (ch == "{") dep++; else if (ch == "}") { dep--; if (dep == 0) break } e = e ch; j++ }
      r = r " " e " "; j++; continue
    }
    j++
  }
  return r
}
function more_quote(lineno, q,  r) {
  for (r = lineno + 1; r <= NR; r++) if (index(L[r], q) > 0) return 1
  return 0
}
function tok(line, mode, lineno,    n, i, c, c2, c3, prev, out, j, k, closed, d, body, isf, israw, pfx, ps, iscode, tag, rest, cons, t, ansi, dep, ch, q, rem, dash, found, inner) {
  n = length(line); i = 1; out = ""
  if (cb) {
    j = index(line, "*/")
    if (j == 0) return ""
    cb = 0; i = j + 2
  }
  if (mode == "py" && tq != "") {
    j = 0; k = 1
    while (k <= n) {
      if (substr(line, k, 1) == "\\") { k += 2; continue }
      if (substr(line, k, 3) == tq) { j = k; break }
      k++
    }
    if (j == 0) {
      if (tqcode) return line
      if (tqf) return f_fields(line)
      return ""
    }
    body = substr(line, 1, j - 1)
    if (tqcode) out = body tq
    else if (tqf) out = f_fields(body) " \"\" "
    else out = "\"\""
    tq = ""; i = j + 3
  }
  if (mode == "c" && graw) {
    j = index(line, "`")
    if (j == 0) { if (grawcode) return line; return "" }
    out = grawcode ? substr(line, 1, j) : "\"\""
    graw = 0; i = j + 1
  }
  if (mode == "sh" && shq != "") {
    k = 1; j = 0
    while (k <= n) {
      ch = substr(line, k, 1)
      if (shq == "\"" && ch == "\\") { k += 2; continue }
      if (shq == "'" && shqansi && ch == "\\") { k += 2; continue }
      if (ch == shq) { j = k; break }
      k++
    }
    if (j == 0) { if (shqcode) return line; return "" }
    out = shqcode ? substr(line, 1, j) : "\"\""
    shq = ""; i = j + 1
  }
  while (i <= n) {
    c = substr(line, i, 1); c2 = substr(line, i, 2); c3 = substr(line, i, 3)
    prev = (i > 1) ? substr(line, i - 1, 1) : ""
    if (mode == "c" && c2 == "//") { comment_seen(substr(line, i + 2), lineno); break }
    if (mode == "c" && c2 == "/*") {
      j = index(substr(line, i + 2), "*/")
      if (j == 0) { cb = 1; comment_seen(substr(line, i + 2), lineno); break }
      comment_seen(substr(line, i + 2, j - 1), lineno); i += 2 + j + 1; out = out " "; continue
    }
    if (mode == "py" && c == "#") { comment_seen(substr(line, i + 1), lineno); break }
    if (mode == "sh" && c == "#" && (i == 1 || prev ~ /[ \t;&|()]/)) { comment_seen(substr(line, i + 1), lineno); break }
    if (c == "\\" && mode != "c") { out = out substr(line, i, 2); shseg = shseg " "; i += 2; continue }
    if (mode == "py" && (c == "\"" || c == "'")) {
      pfx = ""; ps = i - 1
      while (ps >= 1 && length(pfx) < 2 && substr(line, ps, 1) ~ /[rRbBuUfF]/) { pfx = substr(line, ps, 1) pfx; ps-- }
      if (ps >= 1 && substr(line, ps, 1) ~ /[A-Za-z0-9_]/) pfx = ""
      isf = (pfx ~ /[fF]/); israw = (pfx ~ /[rR]/)
      if (c3 == c c c) {
        k = i + 3; j = 0
        while (k <= n) {
          if (substr(line, k, 1) == "\\") { k += 2; continue }
          if (substr(line, k, 3) == c c c) { j = k; break }
          k++
        }
        body = (j == 0) ? substr(line, i + 3) : substr(line, i + 3, j - i - 3)
        iscode = lit_is_code(body)
        if (j == 0) { tq = c c c; tqcode = iscode; tqf = isf; out = out (iscode ? substr(line, i) : (isf ? f_fields(body) " " : "")); i = n + 1; break }
        out = out (iscode ? substr(line, i, j + 3 - i) : "\"\"" (isf ? f_fields(body) : ""))
        lastq = body; sincestr = ""; i = j + 3; continue
      }
      k = i + 1; closed = 0
      while (k <= n) {
        d = substr(line, k, 1)
        if (d == "\\") { k += 2; continue }
        if (d == c) { closed = 1; break }
        k++
      }
      if (!closed) { out = out substr(line, i); i = n + 1; break }
      body = substr(line, i + 1, k - i - 1)
      iscode = lit_is_code(body)
      out = out (iscode ? substr(line, i, k - i + 1) : "\"\"" (isf ? f_fields(body) : ""))
      lastq = body; sincestr = ""; i = k + 1; continue
    }
    if (mode == "c" && c == "`") {
      j = index(substr(line, i + 1), "`")
      if (j == 0) { graw = 1; grawcode = lit_is_code(""); out = out (grawcode ? substr(line, i) : "\"\""); i = n + 1; break }
      body = substr(line, i + 1, j - 1); iscode = lit_is_code(body)
      out = out (iscode ? substr(line, i, j + 1) : "\"\""); lastq = body; sincestr = ""; i += j + 1; continue
    }
    if (mode == "c" && c == "\"") {
      k = i + 1; closed = 0
      while (k <= n) { d = substr(line, k, 1); if (d == "\\") { k += 2; continue } if (d == "\"") { closed = 1; break } k++ }
      if (!closed) { out = out substr(line, i); i = n + 1; break }
      body = substr(line, i + 1, k - i - 1); iscode = lit_is_code(body)
      out = out (iscode ? substr(line, i, k - i + 1) : "\"\""); lastq = body; sincestr = ""; i = k + 1; continue
    }
    if (mode == "c" && c == "'") {
      if (substr(line, i + 2, 1) == "'") { out = out "' '"; i += 3; continue }
      if (substr(line, i + 1, 1) == "\\" && substr(line, i + 3, 1) == "'") { out = out "' '"; i += 4; continue }
      out = out c; i++; continue
    }
    if (mode == "sh" && c == "'") {
      ansi = (prev == "$")
      k = i + 1; closed = 0
      while (k <= n) { d = substr(line, k, 1); if (ansi && d == "\\") { k += 2; continue } if (d == "'") { closed = 1; break } k++ }
      iscode = sh_str_is_code(shseg)
      if (!closed) {
        if (!more_quote(lineno, "'")) { out = out substr(line, i); i = n + 1; break }
        shq = "'"; shqansi = ansi; shqcode = iscode; out = out (iscode ? substr(line, i) : "''"); shseg = shseg ((shseg ~ /=$/) ? "S " : " S "); i = n + 1; break
      }
      out = out (iscode ? substr(line, i, k - i + 1) : "''"); shseg = shseg ((shseg ~ /=$/) ? "S " : " S "); i = k + 1; continue
    }
    if (mode == "sh" && c == "\"") {
      iscode = sh_str_is_code(shseg)
      k = i + 1; closed = 0; inner = ""
      while (k <= n) {
        d = substr(line, k, 1)
        if (d == "\\") { k += 2; continue }
        if (d == "$" && substr(line, k + 1, 1) == "(") {
          dep = 1; j = k + 2
          while (j <= n && dep > 0) { ch = substr(line, j, 1); if (ch == "(") dep++; else if (ch == ")") dep--; j++ }
          inner = inner " " substr(line, k, j - k) " "; k = j; continue
        }
        if (d == "$" && substr(line, k + 1, 1) ~ /[A-Za-z_{]/) {
          j = k + 1
          if (substr(line, j, 1) == "{") { while (j <= n && substr(line, j, 1) != "}") j++; j++ }
          else { while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) j++ }
          inner = inner substr(line, k, j - k); k = j; continue
        }
        if (d == "`") {
          j = k + 1; while (j <= n && substr(line, j, 1) != "`") j++
          inner = inner " " substr(line, k, j - k + 1) " "; k = j + 1; continue
        }
        if (d == "\"") { closed = 1; break }
        k++
      }
      if (!closed) {
        if (!more_quote(lineno, "\"")) { out = out substr(line, i); i = n + 1; break }
        shq = "\""; shqansi = 0; shqcode = iscode; out = out (iscode ? substr(line, i) : "\"" inner "\""); shseg = shseg ((shseg ~ /=$/) ? "S " : " S "); i = n + 1; break
      }
      out = out (iscode ? substr(line, i, k - i + 1) : "\"" inner "\""); shseg = shseg ((shseg ~ /=$/) ? "S " : " S "); i = k + 1; continue
    }
    if (mode == "sh" && c2 == "<<" && substr(line, i + 2, 1) != "<" && prev != "<") {
      rest = substr(line, i + 2); dash = 0
      if (substr(rest, 1, 1) == "-") { dash = 1; rest = substr(rest, 2) }
      rest = ltrim(rest)
      if (substr(rest, 1, 1) ~ /['"\\]/) rest = substr(rest, 2)
      tag = rest
      if (match(tag, /^[A-Za-z_][A-Za-z0-9_]*/)) tag = substr(tag, 1, RLENGTH); else tag = ""
      if (tag != "") {
        t = ltrim(shseg)
        while (t ~ /^(if|then|elif|else|do|while|until|time|!|\{|\()([ \t]+|$)/) sub(/^(if|then|elif|else|do|while|until|time|!|\{|\()([ \t]+|$)/, "", t)
        while (t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=[^ \t]*[ \t]+/) sub(/^[A-Za-z_][A-Za-z0-9_]*\+?=[^ \t]*[ \t]+/, "", t)
        cons = t; sub(/[ \t].*$/, "", cons); sub(/^.*\//, "", cons)
        found = 0
        for (q = lineno + 1; q <= NR; q++) { rem = L[q]; if (dash) sub(/^\t+/, "", rem); if (rem == tag) { found = 1; break } }
        if (found) {
          hd = tag; hddash = dash
          hdinert = (!LINEPIPE && (cons == "cat" || cons == "tee" || cons == "read")) ? 1 : 0
          hdmode = (cons ~ /^python[0-9.]*$/) ? "py" : ((cons ~ /^(ba|z|da|k)?sh$/) ? "sh" : "raw")
        }
      }
      out = out c2; i += 2; continue
    }
    if (mode != "sh") {
      if (c == "(") {
        pd++
        if (callee_is_sink(out)) { sdepth++; sinkpd[sdepth] = pd }
      } else if (c == ")") {
        if (sdepth > 0 && pd == sinkpd[sdepth]) sdepth--
        pd--; if (pd < 0) pd = 0
      }
      if (c !~ /[ \t,\[]/) { lastq = "" }
      sincestr = sincestr c
    }
    if (mode == "sh") {
      if (c == "(" && prev == "=") { shseg = "@ARR@" }
      else if ((c ~ /[;&|(){]/ && !(c == "&" && (prev ~ /[<>]/ || substr(line, i + 1, 1) == ">"))) || (c == "$" && substr(line, i + 1, 1) == "(")) { shseg = "" } else shseg = shseg c
    }
    out = out c; i++
  }
  return out
}
{ L[NR] = $0 }
END {
  mode = LANGX; tq = ""; cb = 0; graw = 0; shq = ""; hd = ""; pd = 0; sdepth = 0; lastq = ""; sincestr = ""; shseg = ""; contprev = 0
  for (ln = 1; ln <= NR; ln++) {
    line = L[ln]
    allowed_line = 0
    if (hd != "") {
      rem = line; if (hddash) sub(/^\t+/, "", rem)
      if (rem == hd) { hd = ""; tq = ""; tqcode = 0; tqf = 0; shseg = ""; print ""; continue }
      if (hdinert) { print ""; continue }
      if (hdmode == "raw") { print line; continue }
      res = tok(line, hdmode, ln)
      if (allowed_line) res = ""
      print res; continue
    }
    LINEPIPE = (line ~ /[|][ \t]*(sudo[ \t]+)?((ba|z|da|k)?sh|python[0-9.]*|perl|ruby|node)([ \t]|$|;|\))/) ? 1 : 0
    STMTSHELL = (line ~ /shell[ \t]*=[ \t]*True/) ? 1 : 0
    if (mode == "sh" && !contprev && shq == "") shseg = ""
    res = tok(line, mode, ln)
    if (allowed_line) res = ""
    print res
    contprev = (line ~ /\\$/) ? 1 : 0
    if (hd != "") { shseg = "" }
  }
}
AWK

unguarded=0
guarded=0
allowed_n=0
ALLOWLOG="$(mktemp "${TMPDIR:-/tmp}/killpg_allow.XXXXXX")"
trap 'rm -f "$ALLOWLOG"' EXIT
# Consumer DATA (§11.4.35): extra path globs (relative to the scan root) that may carry the audited marker.
allow_paths="${KILLPG_GUARD_ALLOW_PATHS:-}"

# allow_path_ok <relative-path>  — the audited allow marker is honoured ONLY on a test path:
#   a `tests`/`test`/`testing` directory component, a `test_*` basename, a `*_test.*`/`*_tests.*` basename,
#   or a glob in KILLPG_GUARD_ALLOW_PATHS.
allow_path_ok() {
    _ap_rel="$1"; _ap_base="${_ap_rel##*/}"
    case "/${_ap_rel}" in */tests/*|*/test/*|*/testing/*) return 0 ;; esac
    case "$_ap_base" in test_*|*_test.*|*_tests.*) return 0 ;; esac
    for _ap_g in $allow_paths; do
        # shellcheck disable=SC2254
        case "$_ap_rel" in $_ap_g) return 0 ;; esac
    done
    return 1
}

for f in "${files[@]}"; do
    if [ "$root_is_file" -eq 1 ]; then rel="${f##*/}"; else rel="${f#"$root"/}"; fi
    case "${f##*.}" in
        py) langx=py ;;
        sh|bash) langx=sh ;;
        *) langx=c ;;
    esac
    allowok=0
    allow_path_ok "$rel" && allowok=1
    : > "$ALLOWLOG"

    # Structural code extraction (see STRIP_AWK): real comments, inert strings and inert heredoc bodies are
    # blanked, everything else stays code. A tokenizer failure is NOT a pass (fail closed, §11.4.201(4)).
    code_only="$(awk -v LANGX="$langx" -v ALLOWOK="$allowok" -v FNAME="$f" -v ALLOWLOG="$ALLOWLOG" "$STRIP_AWK" "$f" 2>/dev/null)"
    awk_rc=$?
    if [ "$awk_rc" -ne 0 ]; then
        unguarded=$(( unguarded + 1 ))
        echo "❌ ${GATE}: FAIL — cannot analyse ${f} (extractor exit ${awk_rc}); refusing to treat an unreadable file as clean (§11.4.201(4))"
        continue
    fi
    # Report every audited-marker decision (a suppression is never silent).
    while IFS=$'\t' read -r kind where reason; do
        [ -n "$kind" ] || continue
        if [ "$kind" = ALLOWED ]; then
            allowed_n=$(( allowed_n + 1 ))
            echo "ℹ️  ${GATE}: ALLOWED ${where} ${reason}"
        else
            echo "⚠️  ${GATE}: marker IGNORED at ${where} (not a test path: ${rel}) — the line is still scanned: ${reason}"
        fi
    done < "$ALLOWLOG"
    [ -n "$code_only" ] || continue
    # Adjacent string items of one argv list are joined (["kill","-9","-1"] -> ["kill -9 -1"]).
    code_only="$(sed -E "s/${QCH}[[:space:]]*,[[:space:]]*${QCH}/ /g" <<<"$code_only")"

    hit_lines="$(grep -nE "$CALL_ERE" <<<"$code_only" 2>/dev/null || true)"
    [ -n "$hit_lines" ] || continue

    # ── The sanctioned safe_killpg wrapper exemption, bound to REAL bindings (round 3) ──────────────────
    # Granted only by a genuine `import fc_common` / `from fc_common import safe_killpg` line (no `as`
    # rename, no star import) or by the file DEFINING safe_killpg at module level, and withdrawn by ANY
    # rebinding of fc_common / safe_killpg / _safe_killpg in the file.
    disq=0
    grep -qE '^[[:space:]]*from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import[[:space:]]+\*' <<<"$code_only" && disq=1
    if grep -vE '^[[:space:]]*_safe_killpg[[:space:]]*=[[:space:]]*fc_common\.safe_killpg[[:space:]]*;?[[:space:]]*$' <<<"$code_only" \
         | grep -qE '(^|[^A-Za-z0-9_.])(fc_common|safe_killpg|_safe_killpg)[[:space:]]*(=[^=]|:=|:[^=]*=[^=])'; then
        disq=1
    fi
    # more than one binding of _safe_killpg, or any other binding form of the three names
    [ "$(grep -cE '(^|[^A-Za-z0-9_.])_safe_killpg[[:space:]]*(=[^=]|:=)' <<<"$code_only")" -gt 1 ] && disq=1
    grep -qE '(^|[[:space:]])as[[:space:]]+(fc_common|safe_killpg|_safe_killpg)([^A-Za-z0-9_]|$)' <<<"$code_only" && disq=1
    grep -qE '^[[:space:]]*(global|nonlocal|del|for|with)[[:space:]]+([^#]*[^A-Za-z0-9_.])?(fc_common|safe_killpg)([^A-Za-z0-9_]|$)' <<<"$code_only" && disq=1
    grep -qE '^[[:space:]]+def[[:space:]]+(safe_killpg|_safe_killpg)|^[[:space:]]*class[[:space:]]+(fc_common|safe_killpg)' <<<"$code_only" && disq=1
    # safe_killpg imported from any module other than fc_common
    if grep -E 'from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import[^#]*safe_killpg' <<<"$code_only" \
         | grep -vE 'from[[:space:]]+fc_common[[:space:]]+import[[:space:]]+safe_killpg[[:space:]]*$' | grep -q .; then
        disq=1
    fi
    has_imp_mod=0; has_from_imp=0; def_here=0; alias_ok=0
    grep -qE '^[[:space:]]*import[[:space:]]+fc_common[[:space:]]*;?[[:space:]]*$' <<<"$code_only" && has_imp_mod=1
    grep -qE '^[[:space:]]*from[[:space:]]+fc_common[[:space:]]+import[[:space:]]+safe_killpg[[:space:]]*$' <<<"$code_only" && has_from_imp=1
    grep -qE '^def[[:space:]]+safe_killpg[[:space:]]*\(' <<<"$code_only" && def_here=1
    grep -qE '^[[:space:]]*_safe_killpg[[:space:]]*=[[:space:]]*fc_common\.safe_killpg[[:space:]]*;?[[:space:]]*$' <<<"$code_only" && alias_ok=1
    ok_qual=0; ok_bare=0; ok_alias=0
    if [ "$disq" -eq 0 ]; then
        [ "$has_imp_mod" -eq 1 ] && ok_qual=1
        { [ "$has_from_imp" -eq 1 ] || [ "$def_here" -eq 1 ]; } && ok_bare=1
        [ "$alias_ok" -eq 1 ] && [ "$ok_qual" -eq 1 ] && ok_alias=1
    fi
    WRAP_ARG='[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*,[^()]*\)'

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        lineno="${hit%%:*}"
        text="${hit#*:}"

        # Remove ONLY the exempt pieces of the line, then re-test what remains (a def header with nothing
        # after its colon; a canonical safe_killpg(<identifier>, ...) call). Anything else on the same line
        # (a second raw call, a one-line def body) stays a hit.
        rest="$text"
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
        # names killpg / safe_killpg / _safe_killpg themselves are never stripped here (they keep their
        # own rules above). A bare `X.killpg = <value>` assignment REPLACES the attribute (monkeypatch) and
        # signals nothing; its right-hand side is still scanned (`y = os.killpg` / `os.killpg = os.killpg`).
        if [[ "$rest" =~ ^[[:space:]]*def[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*\( ]]; then
            case "${BASH_REMATCH[1]}" in
                killpg|safe_killpg|_safe_killpg) : ;;
                *killpg) case "${rest#*(}" in
                    *killpg*) : ;;   # killpg mentioned in the parameters / one-line body: stays a finding
                    *) rest="$(sed -E 's/^([[:space:]]*)def[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\([^)]*\)[[:space:]]*(->[^:]*)?:/\1/' <<<"$rest")" ;;
                   esac ;;
                *) : ;;
            esac
        fi
        rest="$(sed -E 's/(^|;)([[:space:]]*)[A-Za-z_][A-Za-z0-9_.]*\.killpg[[:space:]]*=([^=])/\1\2_lhs_ =\3/g' <<<"$rest")"
        grep -qE "$CALL_ERE" <<<"$rest" || continue

        start=$(( lineno - window ))
        [ "$start" -lt 1 ] && start=1

        window_text="$(sed -n "${start},${lineno}p" <<<"$code_only")"

        target="$(extract_target "$text")"

        # A non-call reference to the identifier `killpg` (alias / getattr / import-as / dict value / default
        # argument / tuple unpack ...) can never be proven guarded: a finding by construction.
        alias_ref="$(sed -E 's/(^|[^A-Za-z0-9_])killpg[[:space:]]*\(/\1@CALL@(/g' <<<"$rest")"

        # here-strings below, not `printf | grep -q` (SIGPIPE x pipefail class, §11.4.276(C))
        if grep -qE '(^|[^A-Za-z0-9_])killpg([^A-Za-z0-9_]|$)' <<<"$alias_ref"; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — non-call reference to killpg (alias/indirect use) at ${f}:${lineno}: ${text# }"
            echo "   (an alias, getattr, import-as, dict value or default argument holding killpg cannot be proven guarded — §11.4.263(B); call it directly behind a '>1' guard or use fc_common.safe_killpg)"
        elif grep -qE "$LITERAL_TARGET_ERE" <<<"$text"; then
            unguarded=$(( unguarded + 1 ))
            echo "❌ ${GATE}: FAIL — UNGUARDABLE numeric-literal process-group target at ${f}:${lineno}: ${text# }"
            echo "   (a hardcoded numeric pid/pgid can never be guarded — §11.4.263(A): NEVER signal pgid <= 1)"
        elif target_guarded "$window_text" "$target"; then
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
