#!/bin/sh
# precheck_pack.sh - machine pre-check pack (DEC-33) on a clean checkout
# (spec-004 "fast-dev-cycles", plan.md T-C11; tasks.md T078; FR-023,
# SC-009, SC-002). Guarded by
# constitution/scripts/fastcycle/tests/test_precheck_slicer_red.sh (T061),
# per contract specs/004-fast-dev-cycles/contracts/review-batch-and-
# precheck.md (RB-002) and data-model.md #10.3 PreCheckReport.
#
# CLI (contract "Invocations", extended):
#   precheck_pack.sh --config <cfg> --batch <batch.json>
#                     --clean-checkout <dir> --out <precheck.json>
#                     [--determinism-check]
#                     [--baseline-repo [PREFIX=]PATH --baseline-ref REF]...
#                     [--head-sha SHA]
#                     [--shellcheck-exceptions <tsv>]
#                     [--shellcheck-timeout <s>] [--shellcheck-exception-timeout <s>]
#                     [--shellcheck-memory-cap-mib <MiB>] [--shellcheck-max-lines <n>]
#
# The shellcheck check is WHOLE-FILE STRICT with a SEVERITY FLOOR ("touch a
# file, own its shellcheck findings"): every shell script the batch touches (by
# extension, by shebang -- versioned shells and busybox/toybox multicalls
# included -- or because its BASE blob was a shell script) is linted whole with
# `shellcheck --norc -e SC1090,SC1091` on stdin from an empty cwd and a scrubbed
# environment. Every error- and warning-level finding FAILs, and so does every
# finding of the closed info set SC2086 SC2030 SC2031 SC2162 SC2059; any other
# info/style finding is listed (advisory) and does not fail. /system/bin/sh
# scripts are linted as ksh (Android mksh, probed). There is NO baseline diff:
# pre-existing blocking findings in a touched file are the toucher's to fix.
#
# HOST SAFETY: every shellcheck run is wrapped in `systemd-run --user --scope
# -p MemoryMax=<cap>M -p MemorySwapMax=0` (default 8192 MiB) after a size cap
# (default 10000 lines / 2 MiB); over either cap, an unavailable cap mechanism
# or a killed lint = FAIL (BLIND), never PASS. Large / legacy-exception lints
# are serialised host-wide by an flock. --shellcheck-memory-cap-mib and
# --shellcheck-max-lines may only LOWER the caps (a higher value exits 2).
#
# Directives are honoured by shellcheck but policed (line-start or trailing
# after code): `disable=all`, range forms and `extended-analysis=` (other than
# true) FAIL, unknown keys FAIL, and every `disable=` line MUST carry its
# justification on the SAME line, e.g.
#     # shellcheck disable=SC2016 # literal mutation pattern, not an expansion
# (>= 16 letters, >= 3 distinct non-placeholder words; a reason on the line
# ABOVE is NOT accepted). Full rule set: lib/precheck_pack_run.py block comment
# above check_shellcheck.
#
# --shellcheck-exceptions <tsv>: the ONE narrow legacy exception. In a BOUND run
# only the canonical config/shellcheck_legacy_exceptions.tsv is accepted (any
# other value exits 2) and the gate uses it automatically when the bound head
# tracks it; a new row or a raised pin versus the BASE commit's copy FAILs
# unless the batch changes only that file. Rows need reason-class evidence,
# SC10xx codes cannot be pinned and a parse error in a listed file FAILs. A
# listed file FAILs when a blocking per-rule count rises above its pin or a
# rule appears that the pin lacks; lower counts pass (monotone ratchet).
# Residual: a finding swapped for another of the SAME rule is invisible. An
# unlisted file over --shellcheck-timeout (default 60 s) FAILs.
# Other residuals (stated, not closed -- lib block comment R1-R8): touched-file
# legacy findings are the toucher's to fix; packs are not signed (a
# self-consistent forgery is possible); rename following stops at git's -M
# similarity; directive-shaped string lines are policed too; a producer-chosen
# base past unreviewed commits is not detected; giant files cannot be reviewed
# until split.
#
# --baseline-repo PATH --baseline-ref REF (names kept for compatibility): the
# repository and the batch BASE commit (the empty-tree id for a root commit).
# They are used ONLY for (a) binding verification and (b) shell-candidate
# selection from base blobs -- never to excuse a finding. PATH MUST be an
# ABSOLUTE repository toplevel (relative => exit 2); PREFIX=PATH maps checkout
# paths under PREFIX/. REF is REQUIRED with --baseline-repo (never defaulted to
# HEAD) and --baseline-ref requires --baseline-repo (else exit 2).
# Binding: a batch carrying a builder-written `binding` (review/
# precheck_pack_build.sh) is verified -- base == REF, base an ancestor of head
# (head == base's child for a snapshot), checkout git HEAD == bound head, file
# bytes == head blobs, change_ids recomputed -- and only then recorded
# provenance.head_sha_source=batch-binding-verified, the one value the
# review-dispatch guard accepts. The pack also records the batch file's path and
# sha256 so the dispatch verifier can detect a stale/relabelled batch.
# --head-sha SHA must equal the checkout's real git HEAD (a plain directory
# cannot verify it => FAIL) and the bound head when a binding is present.
#
# This is a thin sh dispatcher (house pattern: gates/io_trace.sh ->
# gates/lib/io_trace_parse.py) -- argument parsing + preconditions only;
# the real 10-check DEC-33 implementation lives in
# review/lib/precheck_pack_run.py, invoked once preconditions hold.
#
# --config is accepted and passed through but NOT required to be a
# fastcycle.yaml file: T061's own RED test invokes this tool with
# --config pointing at a plain fixture DIRECTORY
# (fixtures/precheck_slicer/case2_lint_in_pack/), not a YAML file --
# UNCONFIRMED by the contract beyond "--config <cfg>" and not narrowed
# here (constitution 11.4.6: never invent a schema the contract does not
# state). The checks this revision implements (see lib/precheck_pack_run.py
# module docstring for the full per-check honest-scope breakdown) read
# their inputs from --batch and --clean-checkout only, so an unusable
# --config value never blocks a real run.
#
# Exit codes (contract "Exit codes"): 0 all pass; 1 any check FAILs;
# 2 usage/configuration error (missing/unreadable --batch, bad args);
# 4 clean checkout unavailable (--clean-checkout missing or not a
# directory -- the ONE clause the contract states explicitly for this
# tool, kept distinct from the generic 2 above).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

CONFIG=""
BATCH=""
CLEAN_CHECKOUT=""
OUT=""
DETERMINISM_CHECK=0
BASELINE_REPOS=""
BASELINE_REF=""
HEAD_SHA=""
SC_EXCEPTIONS=""
SC_TIMEOUT=""
SC_EX_TIMEOUT=""
SC_MEM_CAP=""
SC_MAX_LINES=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            # The usage text IS this file's header comment (single source of truth).
            sed -n '2,/^set -eu$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --config)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --config requires a value" >&2; exit 2; }
            CONFIG="$2"; shift 2 ;;
        --batch)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --batch requires a value" >&2; exit 2; }
            BATCH="$2"; shift 2 ;;
        --clean-checkout)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --clean-checkout requires a value" >&2; exit 2; }
            CLEAN_CHECKOUT="$2"; shift 2 ;;
        --out)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --out requires a value" >&2; exit 2; }
            OUT="$2"; shift 2 ;;
        --determinism-check)
            DETERMINISM_CHECK=1; shift ;;
        --baseline-repo)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --baseline-repo requires a value" >&2; exit 2; }
            case "$2" in
                *"
"*) echo "precheck_pack.sh: --baseline-repo must not contain a newline (M7)" >&2; exit 2 ;;
            esac
            BASELINE_REPOS="${BASELINE_REPOS}${BASELINE_REPOS:+
}$2"; shift 2 ;;
        --baseline-ref)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --baseline-ref requires a value" >&2; exit 2; }
            BASELINE_REF="$2"; shift 2 ;;
        --head-sha)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --head-sha requires a value" >&2; exit 2; }
            HEAD_SHA="$2"; shift 2 ;;
        --shellcheck-exceptions)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --shellcheck-exceptions requires a value" >&2; exit 2; }
            SC_EXCEPTIONS="$2"; shift 2 ;;
        --shellcheck-timeout)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --shellcheck-timeout requires a value" >&2; exit 2; }
            SC_TIMEOUT="$2"; shift 2 ;;
        --shellcheck-exception-timeout)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --shellcheck-exception-timeout requires a value" >&2; exit 2; }
            SC_EX_TIMEOUT="$2"; shift 2 ;;
        --shellcheck-memory-cap-mib)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --shellcheck-memory-cap-mib requires a value" >&2; exit 2; }
            SC_MEM_CAP="$2"; shift 2 ;;
        --shellcheck-max-lines)
            [ $# -ge 2 ] || { echo "precheck_pack.sh: --shellcheck-max-lines requires a value" >&2; exit 2; }
            SC_MAX_LINES="$2"; shift 2 ;;
        *)
            echo "precheck_pack.sh: unknown option: $1" >&2
            exit 2 ;;
    esac
done

if [ -z "$BATCH" ] || [ -z "$CLEAN_CHECKOUT" ] || [ -z "$OUT" ]; then
    echo "precheck_pack.sh: --batch, --clean-checkout and --out are all required" >&2
    exit 2
fi

if [ -n "$BASELINE_REF" ] && [ -z "$BASELINE_REPOS" ]; then
    echo "precheck_pack.sh: --baseline-ref requires at least one --baseline-repo" >&2
    exit 2
fi
if [ -n "$BASELINE_REPOS" ] && [ -z "$BASELINE_REF" ]; then
    echo "precheck_pack.sh: --baseline-repo requires an explicit --baseline-ref (the batch BASE; never defaulted to HEAD)" >&2
    exit 2
fi
if [ -n "$BASELINE_REPOS" ]; then
    OLDIFS=$IFS
    IFS='
'
    set -f
    for b in $BASELINE_REPOS; do
        # the PATH part (after an optional PREFIX=) must be absolute
        case "$b" in
            /*) ;;
            *=/*) ;;
            *) IFS=$OLDIFS; set +f
               echo "precheck_pack.sh: --baseline-repo PATH must be absolute (got: $b)" >&2
               exit 2 ;;
        esac
    done
    set +f
    IFS=$OLDIFS
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "precheck_pack.sh: python3 not found on PATH -- cannot run the DEC-33 pack" >&2
    exit 2
fi

if [ ! -f "$BATCH" ]; then
    echo "precheck_pack.sh: --batch not found or not a file: $BATCH" >&2
    exit 2
fi

# The ONE clause the contract states explicitly by exit code (4): a
# clean-checkout that does not exist or is not a directory is an
# unavailability, never a plain usage error.
if [ ! -d "$CLEAN_CHECKOUT" ]; then
    echo "precheck_pack.sh: --clean-checkout is unavailable (not a readable directory): $CLEAN_CHECKOUT" >&2
    exit 4
fi

# Rebuild the argument vector for the python library (one place, so every
# optional flag is passed identically with or without --config).
set -- --batch "$BATCH" --clean-checkout "$CLEAN_CHECKOUT" --out "$OUT"
if [ -n "$CONFIG" ]; then set -- "$@" --config "$CONFIG"; fi
if [ "$DETERMINISM_CHECK" -eq 1 ]; then set -- "$@" --determinism-check; fi
if [ -n "$BASELINE_REF" ]; then set -- "$@" --baseline-ref "$BASELINE_REF"; fi
if [ -n "$HEAD_SHA" ]; then set -- "$@" --head-sha "$HEAD_SHA"; fi
if [ -n "$SC_EXCEPTIONS" ]; then set -- "$@" --shellcheck-exceptions "$SC_EXCEPTIONS"; fi
if [ -n "$SC_TIMEOUT" ]; then set -- "$@" --shellcheck-timeout "$SC_TIMEOUT"; fi
if [ -n "$SC_EX_TIMEOUT" ]; then set -- "$@" --shellcheck-exception-timeout "$SC_EX_TIMEOUT"; fi
if [ -n "$SC_MEM_CAP" ]; then set -- "$@" --shellcheck-memory-cap-mib "$SC_MEM_CAP"; fi
if [ -n "$SC_MAX_LINES" ]; then set -- "$@" --shellcheck-max-lines "$SC_MAX_LINES"; fi
if [ -n "$BASELINE_REPOS" ]; then
    OLDIFS=$IFS
    IFS='
'
    set -f
    for b in $BASELINE_REPOS; do set -- "$@" --baseline-repo "$b"; done
    set +f
    IFS=$OLDIFS
fi
exec python3 "$HERE/lib/precheck_pack_run.py" "$@"
