#!/bin/sh
# CM-GIT-HOOKS-INSTALLED — FR-012 declared-active check (§11.4.205)
#
# "Installed" is a VERIFIED RUNTIME STATE, never a source-layer assertion
# (§11.4.108). Asserting that an installer EXISTS proves nothing about whether
# any hook is live; this gate reads the LIVE hook path and compares its contents
# byte-for-byte against the tracked sources.
#
# ---------------------------------------------------------------------------
# WHY THIS GATE EXISTS (the §11.4.205 forensic it closes)
# ---------------------------------------------------------------------------
# The superseded implementation asserted this token by delegating to the
# project installer's own `--verify`, and therefore inherited that installer's
# self-referential declared set: the installer's `HOOKS=` literal was BOTH the
# declared set and the install set, so it could report DRIFT in a hook it named
# but never the OMISSION of one it did not. Measured: it reported
# `ok=4 missing=0 drifted=0` rc=0, and the gate above it printed
# `PASS  CM-GIT-HOOKS-INSTALLED  5 hook(s) installed`, while `post-merge` did
# not exist in the live hook path at all. (Its "5" was not even a hook count —
# it counted the `lib/` DIRECTORY the installer copies alongside the hooks.)
#
# A gate that only checks the four hooks it happens to list cannot fail on the
# fifth. This gate therefore derives the DECLARED set TWICE, independently, and
# REFUSES when the two derivations disagree:
#
#   D1  the consumer's hook map (what is declared FOR INSTALL)
#   D2  a scan of the consumer's source roots, filtered to the closed set of
#       canonical git hook names (proof the map OMITS NOTHING)
#
# D2 is what the old check structurally could not have: an omission detector.
#
# ---------------------------------------------------------------------------
# WHY D2 IS A FILTERED SCAN AND NOT A RAW DIRECTORY LISTING (§11.4.201(1))
# ---------------------------------------------------------------------------
# A raw listing of the source roots is NOT the declared set. Measured on the
# consuming repo the two roots hold 19 entries of which only 5 are git hooks;
# a wholesale read would emit 14 false refusals (`lib/`, `fixtures/`, test
# harnesses, agent-harness guards). A false-positive refusal is a FAIL-bluff of
# the same severity as a false pass, so both the declared side AND the live side
# are filtered to canonical git hook names — the live-side filter is what stops
# the installed `lib/` directory from surfacing as an "undeclared live hook".
#
# ---------------------------------------------------------------------------
# USAGE
# ---------------------------------------------------------------------------
#   cm_git_hooks_installed.sh [OPTIONS]
#
#   --repo <dir>          Repository root.        Default: `git rev-parse --show-toplevel`
#   --map <file>          Hook map (D1).          Default: <repo>/scripts/git_hooks/hooks.tsv
#   --source-root <dir>   Source root (D2). Repeatable.
#                         Default: <repo>/scripts/git_hooks <repo>/constitution/scripts/hooks
#   --hook-dir <dir>      Live hook path.         Default: resolved from
#                         `git config core.hooksPath`, else <git-dir>/hooks
#   --needle <hook>       Control-needle hook.    Default: pre-commit
#   --selftest            Run the fixture self-validation and exit.
#   --quiet               Suppress per-assertion detail.
#
# The defaults above are DOCUMENTED CONVENIENCE ONLY. This gate is shared
# constitution-side tooling (§11.4.177): the consumer supplies its paths as
# DATA at the call site, and the wiring in the consumer's pre-build seam passes
# --map / --source-root explicitly rather than relying on these defaults.
#
# ---------------------------------------------------------------------------
# EXIT CODES
# ---------------------------------------------------------------------------
#   0  PASS     every declared hook present, executable, content-identical;
#               no undeclared canonical hook in the live path
#   1  FAIL     a violation was found, and is NAMED
#   2  REFUSE   the gate cannot decide and says so instead of guessing:
#               unreadable directory, unreadable/malformed map, D1 vs D2
#               disagreement, or a control needle that could not be certified
#               (§11.4.201(6) — a blind instrument and a clean tree must never
#               return the same quiet zero)
#
# Self-validation: §11.4.201 / §11.4.107(10). `--selftest` runs BOTH checked-in
# fixture trees — a golden-TRUE that MUST make the gate fire naming exactly the
# missing hook, and a golden-FALSE of measured non-hook decoys on which the gate
# MUST NOT fire in either direction. Either outcome failing means this gate
# mints no verdict.

set -u

TOKEN="CM-GIT-HOOKS-INSTALLED"

# Closed set of canonical git hook names (git v2 githooks(5)).
CANONICAL_HOOKS="applypatch-msg pre-applypatch post-applypatch pre-commit
pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase
post-checkout post-merge pre-push pre-receive update proc-receive post-receive
post-update reference-transaction push-to-checkout pre-auto-gc post-rewrite
sendemail-validate fsmonitor-watchman p4-changelist p4-prepare-changelist
p4-post-changelist p4-pre-submit post-index-change"

REPO=""
MAP=""
SOURCE_ROOTS=""
HOOK_DIR=""
NEEDLE="pre-commit"
QUIET=0
SELFTEST=0
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer hook map (only way to get the honest SKIP)

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)        REPO="${2:-}";        shift 2 ;;
        --map)         MAP="${2:-}";         shift 2 ;;
        --source-root) SOURCE_ROOTS="${SOURCE_ROOTS}${2:-}
"; shift 2 ;;
        --hook-dir)    HOOK_DIR="${2:-}";    shift 2 ;;
        --needle)      NEEDLE="${2:-}";      shift 2 ;;
        --selftest)    SELFTEST=1;           shift ;;
        --quiet)       QUIET=1;              shift ;;
        --standalone-canon) STANDALONE=1;    shift ;;
        --help|-h)     sed -n '1,80p' "$0";  exit 0 ;;
        *) echo "${TOKEN}: unknown argument: $1" >&2; exit 2 ;;
    esac
done

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
emit() { printf '%s\n' "$*"; }

is_canonical_hook() {  # $1 = name
    _ch_n="$1"
    for _ch_c in $CANONICAL_HOOKS; do
        [ "$_ch_c" = "$_ch_n" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# The gate proper. Runs against one (repo, map, source-roots, hook-dir) tuple so
# the fixtures exercise the SAME code path the real invocation does.
# ---------------------------------------------------------------------------
run_gate() {  # $1=repo $2=map $3=hook_dir $4..=source roots
    g_repo="$1"; g_map="$2"; g_hookdir="$3"; shift 3
    g_roots="$*"
    g_fail=""
    g_refuse=""

    # -- fail closed on unreadable inputs -----------------------------------
    if [ ! -d "$g_hookdir" ] || [ ! -r "$g_hookdir" ]; then
        emit "${TOKEN}: REFUSE — live hook path unreadable: ${g_hookdir}"
        return 2
    fi
    if [ ! -r "$g_map" ]; then
        emit "${TOKEN}: REFUSE — hook map unreadable: ${g_map}"
        return 2
    fi
    for g_r in $g_roots; do
        if [ ! -d "$g_r" ] || [ ! -r "$g_r" ]; then
            emit "${TOKEN}: REFUSE — source root unreadable: ${g_r}"
            return 2
        fi
    done

    # -- D1: declared set from the map --------------------------------------
    g_d1=""
    g_pairs=""
    while IFS= read -r g_line || [ -n "$g_line" ]; do
        printf '%s' "$g_line" | grep -q '^[[:space:]]*#' && continue
        printf '%s' "$g_line" | grep -q '^[[:space:]]*$' && continue
        g_name=$(printf '%s' "$g_line" | cut -f1)
        g_src=$(printf '%s' "$g_line" | cut -f2)
        if [ -z "$g_name" ] || [ -z "$g_src" ] || [ "$g_name" = "$g_src" ]; then
            emit "${TOKEN}: REFUSE — malformed row in ${g_map}: '${g_line}'"
            return 2
        fi
        if ! is_canonical_hook "$g_name"; then
            emit "${TOKEN}: REFUSE — map declares '${g_name}', not a canonical git hook name"
            return 2
        fi
        g_d1="${g_d1}${g_name}
"
        case "$g_src" in
            /*) g_abs="$g_src" ;;
            *)  g_abs="${g_repo}/${g_src}" ;;
        esac
        g_pairs="${g_pairs}${g_name}	${g_abs}
"
    done < "$g_map"
    g_d1=$(printf '%s' "$g_d1" | grep -v '^$' | sort -u)

    if [ -z "$g_d1" ]; then
        emit "${TOKEN}: REFUSE — ${g_map} declares zero hooks (fail closed, never 'nothing to check')"
        return 2
    fi

    # -- D2: independent scan of the source roots, canonical-filtered -------
    g_d2=""
    for g_r in $g_roots; do
        for g_e in "$g_r"/*; do
            [ -e "$g_e" ] || continue
            [ -f "$g_e" ] || continue          # directories are never git hooks
            g_b=$(basename "$g_e")
            is_canonical_hook "$g_b" || continue
            g_d2="${g_d2}${g_b}
"
        done
    done
    g_d2=$(printf '%s' "$g_d2" | grep -v '^$' | sort -u)

    # -- D1 vs D2 must agree, else REFUSE ----------------------------------
    if [ "$g_d1" != "$g_d2" ]; then
        emit "${TOKEN}: REFUSE — declared-set derivations disagree (map vs source-root scan)"
        g_only1=""
        for g_x in $(printf '%s' "$g_d1" | tr '\n' ' '); do
            printf '%s\n' "$g_d2" | grep -qxF "$g_x" || g_only1="${g_only1}${g_x} "
        done
        g_only2=""
        for g_x in $(printf '%s' "$g_d2" | tr '\n' ' '); do
            printf '%s\n' "$g_d1" | grep -qxF "$g_x" || g_only2="${g_only2}${g_x} "
        done
        [ -n "$g_only1" ] && emit "  in map but absent from source roots: ${g_only1}"
        [ -n "$g_only2" ] && emit "  present in source roots but OMITTED from the map: ${g_only2}"
        emit "  the map is the install set; an omission there is invisible to the installer's own --verify"
        return 2
    fi
    say "${TOKEN}: declared set agrees across both derivations: $(printf '%s' "$g_d1" | tr '\n' ' ')"

    # -- CONTROL NEEDLE (§11.4.201(7)(b)) before ANY absence claim ---------
    # The absence probe below is `[ -e "$dir/$name" ]`. Certify that exact probe
    # can see a file that IS there before trusting any zero it returns.
    g_needle_ok=0
    g_needle_what=""
    if [ -e "${g_hookdir}/${NEEDLE}" ]; then
        g_needle_ok=1; g_needle_what="${NEEDLE}"
    else
        for g_e in "$g_hookdir"/*; do
            [ -e "$g_e" ] || continue
            g_b=$(basename "$g_e")
            if [ -e "${g_hookdir}/${g_b}" ]; then
                g_needle_ok=1; g_needle_what="${g_b} (fallback: '${NEEDLE}' not installed)"
                break
            fi
        done
    fi
    if [ "$g_needle_ok" != 1 ]; then
        emit "${TOKEN}: REFUSE — control needle uncertified: the presence probe could not be"
        emit "  confirmed against any entry in ${g_hookdir}. Reporting absences from an"
        emit "  instrument never proven able to see would be a false null (§11.4.201(6))."
        return 2
    fi
    say "${TOKEN}: control needle OK — presence probe sees ${g_needle_what}"

    # -- D-6 assertion 1..3: presence / executability / content-equality ---
    g_missing=""
    for g_h in $(printf '%s' "$g_d1" | tr '\n' ' '); do
        g_dst="${g_hookdir}/${g_h}"
        g_src=$(printf '%s' "$g_pairs" | awk -F'\t' -v w="$g_h" '$1==w {print $2; exit}')
        if [ -z "$g_src" ] || [ ! -r "$g_src" ]; then
            emit "${TOKEN}: REFUSE — declared hook '${g_h}' has no readable tracked source (${g_src:-<unmapped>})"
            return 2
        fi
        if [ ! -e "$g_dst" ]; then
            g_fail="${g_fail}MISSING ${g_h} (declared, not present at ${g_dst})
"
            g_missing="${g_missing}${g_h} "
            continue
        fi
        if [ ! -x "$g_dst" ]; then
            g_fail="${g_fail}NOT-EXECUTABLE ${g_h} (${g_dst})
"
            continue
        fi
        if ! cmp -s "$g_src" "$g_dst"; then
            g_fail="${g_fail}DRIFTED ${g_h} (${g_dst} differs from tracked ${g_src})
"
            continue
        fi
        say "  ok  ${g_h}  present + executable + identical to ${g_src}"
    done

    # -- D-6 assertion 4: set equality the OTHER direction ------------------
    # Canonical-name filtered on the live side too: the installed `lib/` is a
    # directory and never a git hook, and surfacing it as an undeclared live
    # hook would be the false finding §11.4.201(1) forbids.
    for g_e in "$g_hookdir"/*; do
        [ -e "$g_e" ] || continue
        [ -f "$g_e" ] || continue
        g_b=$(basename "$g_e")
        case "$g_b" in *.sample) continue ;; esac
        is_canonical_hook "$g_b" || continue
        if ! printf '%s\n' "$g_d1" | grep -qxF "$g_b"; then
            g_fail="${g_fail}UNDECLARED ${g_b} (live in ${g_hookdir}, absent from ${g_map})
"
        fi
    done

    if [ -n "$g_fail" ]; then
        emit "${TOKEN}: FAIL"
        printf '%s' "$g_fail" | grep -v '^$' | while IFS= read -r g_l; do emit "  ${g_l}"; done
        return 1
    fi

    emit "${TOKEN}: PASS — $(printf '%s' "$g_d1" | grep -c .) declared hook(s) present, executable, identical to tracked source; no undeclared live hook"
    return 0
}

# ---------------------------------------------------------------------------
# --selftest (§11.4.201 / §11.4.107(10))
# ---------------------------------------------------------------------------
selftest() {
    st_dir=$(dirname "$0")/fixtures/cm_git_hooks_installed
    st_rc=0

    if [ ! -d "$st_dir" ]; then
        emit "${TOKEN}: SELFTEST REFUSE — fixture tree absent: ${st_dir}"
        return 2
    fi

    # --- golden TRUE: a declared hook is missing -> the gate MUST fire -----
    st_t="${st_dir}/golden_true_missing_declared"
    st_out=$(run_gate "$st_t" "${st_t}/hooks.tsv" "${st_t}/live_hooks" "${st_t}/src_a" "${st_t}/src_b" 2>&1)
    st_r=$?
    if [ "$st_r" != 1 ]; then
        emit "SELFTEST FAIL golden_true_missing_declared: expected FAIL(1), got ${st_r}"
        emit "$st_out"
        st_rc=1
    elif ! printf '%s' "$st_out" | grep -q 'MISSING post-merge'; then
        emit "SELFTEST FAIL golden_true_missing_declared: fired, but did not name post-merge"
        emit "$st_out"
        st_rc=1
    elif printf '%s' "$st_out" | grep -Eq 'MISSING (pre-commit|pre-push|post-commit|commit-msg)|UNDECLARED|DRIFTED|NOT-EXECUTABLE'; then
        emit "SELFTEST FAIL golden_true_missing_declared: fired for MORE than the one missing hook"
        emit "$st_out"
        st_rc=1
    else
        emit "SELFTEST ok  golden_true_missing_declared  -> FAIL(1), names exactly post-merge"
    fi

    # --- golden FALSE: non-hook decoys -> the gate MUST NOT fire ----------
    st_f="${st_dir}/golden_false_nonhook_decoys"
    st_out=$(run_gate "$st_f" "${st_f}/hooks.tsv" "${st_f}/live_hooks" "${st_f}/src_a" "${st_f}/src_b" 2>&1)
    st_r=$?
    if [ "$st_r" != 0 ]; then
        emit "SELFTEST FAIL golden_false_nonhook_decoys: expected PASS(0), got ${st_r}"
        emit "  a fire here is the false-positive refusal this gate forbids (§11.4.201(1))"
        emit "$st_out"
        st_rc=1
    else
        emit "SELFTEST ok  golden_false_nonhook_decoys  -> PASS(0), no decoy surfaced"
    fi

    if [ "$st_rc" != 0 ]; then
        emit "${TOKEN}: SELFTEST FAILED — this gate mints no verdict until both fixtures hold"
        return 2
    fi
    emit "${TOKEN}: SELFTEST GREEN (golden-true fires naming exactly the omission; golden-false silent)"
    return 0
}

if [ "$SELFTEST" = 1 ]; then
    selftest
    exit $?
fi

# ---------------------------------------------------------------------------
# Resolve the real invocation's paths (documented defaults; §11.4.177 the
# consumer normally passes these explicitly as DATA).
# ---------------------------------------------------------------------------
if [ -z "$REPO" ]; then
    REPO=$(git rev-parse --show-toplevel 2>/dev/null) || {
        emit "${TOKEN}: REFUSE — no --repo given and not inside a git work tree"
        exit 2
    }
fi
[ -n "$MAP" ] || MAP="${REPO}/scripts/git_hooks/hooks.tsv"
if [ -z "$SOURCE_ROOTS" ]; then
    SOURCE_ROOTS="${REPO}/scripts/git_hooks
${REPO}/constitution/scripts/hooks"
fi
if [ -z "$HOOK_DIR" ]; then
    # Resolve the LIVE hook path rather than assuming .git/hooks.
    HOOK_DIR=$(git -C "$REPO" config --get core.hooksPath 2>/dev/null || true)
    if [ -n "$HOOK_DIR" ]; then
        case "$HOOK_DIR" in /*) ;; *) HOOK_DIR="${REPO}/${HOOK_DIR}" ;; esac
    else
        GD=$(git -C "$REPO" rev-parse --git-dir 2>/dev/null || echo ".git")
        case "$GD" in /*) ;; *) GD="${REPO}/${GD}" ;; esac
        HOOK_DIR="${GD}/hooks"
    fi
fi

say "${TOKEN}: repo=${REPO}"
say "${TOKEN}: live hook path=${HOOK_DIR}"
if [ "$STANDALONE" = 1 ] && [ ! -r "$MAP" ]; then
    emit "${TOKEN}: SKIP — standalone canon DECLARED (--standalone-canon): the hook map ${MAP} is consumer data and does not exist here (honest SKIP, not a PASS)"
    exit 3
fi
run_gate "$REPO" "$MAP" "$HOOK_DIR" $(printf '%s' "$SOURCE_ROOTS" | tr '\n' ' ')
exit $?
