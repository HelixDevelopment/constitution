#!/bin/sh
# precheck_pack_build.sh - one-shot convenience wrapper automating the
# manual review-pack build sequence (RB-001/RB-002,
# contracts/review-batch-and-precheck.md) that a human/agent otherwise
# repeats by hand every review round: write a config.yaml, hand-construct
# per-change descriptor JSON files with real sha256-verified sibling
# diffs, run slicer.py, create a `git worktree`, run precheck_pack.sh,
# clean up the worktree. This script automates the WHOLE sequence from a
# single git commit/range, idempotently (a second invocation for the same
# commit reuses the cached pack instead of rebuilding).
#
# This is a thin sh dispatcher (house pattern: gates/io_trace.sh ->
# gates/lib/io_trace_parse.py; review/precheck_pack.sh ->
# review/lib/precheck_pack_run.py) -- git plumbing + worktree lifecycle
# only; the real per-change diff/hash/config.yaml construction and the
# final pack-validation/marker-emission logic live in
# review/lib/precheck_pack_build_run.py.
#
# CLI:
#   precheck_pack_build.sh (--commit <sha>[..<sha>] | --snapshot-paths <file>)
#       [--repo-root <abs path>] [--logic-group <name>] [--out-dir <dir>]
#       [--slice-limit <lines>] [--min-free-kb <kb>]
#       [--shellcheck-exceptions <repo-relative tsv>]
#       [--shellcheck-timeout <s>] [--shellcheck-exception-timeout <s>]
#
#   --repo-root     ABSOLUTE toplevel of the repository the batch lives in.
#                    Default: the constitution submodule (backward compatible).
#                    Any other repo (the main repo, another submodule) is
#                    checked out PARTIALLY: `git worktree add --no-checkout` +
#                    a literal NUL-separated pathspec `git checkout` of the
#                    changed paths (and the exceptions TSV) only, so a
#                    million-file tree is never materialised and no
#                    sparse-checkout config is written into the repo. A CROSS-REPO
#                    batch is reviewed with ONE pack PER REPO (run this script
#                    once per --repo-root) and the dispatch cites every pair:
#                      PRECHECK-PACK: <p1> BATCH-ID: <b1> PRECHECK-PACK: <p2> BATCH-ID: <b2>
#                    (grammar + checks: scripts/hooks/review_dispatch_guard.sh).
#                    In a git checkout sibling-search enumerates the HEAD
#                    commit's tree (every tracked path, materialised or not).
#   --snapshot-paths  UNCOMMITTED work: a path list (NUL-separated, or
#                    newline-separated when it holds no NUL byte; relative to
#                    --repo-root) whose working-tree bytes are frozen into an
#                    UNREFERENCED commit object (no branch, no ref, no index/
#                    working-tree change) on top of HEAD; base = HEAD, head =
#                    that object, binding kind = snapshot (the verifier then
#                    requires head^1 == base). The review runs bound like --commit.
#   --shellcheck-exceptions  the checked-in legacy-exception TSV. A bound run
#                    accepts ONLY the canonical config/shellcheck_legacy_exceptions.tsv
#                    (any other value exits 2): the gate itself uses that file
#                    when it is tracked at the head commit (read from the
#                    REVIEWED HEAD, so a change to it is itself under review)
#                    and compares it with the BASE commit's copy.
#   --shellcheck-timeout / --shellcheck-exception-timeout  passed through to
#                    precheck_pack.sh (defaults 60 s / 900 s; recorded in the
#                    pack). The cache key is the commit range; a cached pack
#                    built with OTHER budgets (or caps) is rebuilt, not reused.
#   --commit        A single commit sha (diffed against its own first
#                    parent -- or, for a root commit, against the empty
#                    tree), OR a two-dot range "<base>..<head>" (diffed as
#                    `git diff <base> <head>`, matching plain `git diff`'s
#                    own two-dot semantics). Required.
#   --logic-group   Overrides the default logic-group name every changed
#                    path is mapped to in the generated config.yaml
#                    (review/slicer.py RB-001 DEC-06: "shared logic group,
#                    feature, or defect class"). Default: a deterministic,
#                    content-derived "precheck-<short-head-sha>" (never an
#                    arbitrary/guessed name).
#   --out-dir       Where batch.json/precheck.json/config.yaml land.
#                    Default: <parent-repo>/qa-results/fastcycle/
#                    precheck_packs/<key>, <key> = the resolved commit's
#                    full 40-hex sha (single-commit mode) or
#                    "<base-sha>..<head-sha>" (range mode) -- content-
#                    addressed, so a second invocation for the SAME commit
#                    lands in the SAME directory and is detected as
#                    already-built (idempotent/cacheable, never rebuilt).
#   --slice-limit   Passed through to review/slicer.py --slice-limit.
#                    Default: 400 (contracts/review-batch-and-precheck.md
#                    RB-001: "~400 per R4 rec. 4 -- a parameter to be
#                    measured, not a constant").
#   --min-free-kb   Disk-safety floor checked before `git worktree add`
#                    (house convention, cycle/baseline_replay.sh's own
#                    --min-free-kb). Default: 1048576 (1 GiB -- the
#                    constitution submodule's own checkout is small
#                    relative to baseline_replay.sh's 10 GiB default,
#                    which sizes for the much larger parent AOSP tree).
#
# Output (stdout, on a successful build OR a successful cache hit): the
# EXACT two marker lines scripts/hooks/review_dispatch_guard.sh's own
# documented RB-002 convention requires on a review dispatch's
# description -- copy-pasteable verbatim into the next Agent/Task
# dispatch's `description`:
#   PRECHECK-PACK: <out-dir>/precheck.json
#   BATCH-ID: <batch_id>
#
# Exit codes (mirrors review/precheck_pack.sh's own contract, "Exit
# codes"): 0 all_pass=true (dispatch-ready); 1 all_pass=false (a real pack
# was produced, but at least one check FAILed -- the failures, printed to
# stdout above the markers, return to the producer per RB-002); 2 usage/
# configuration error (bad args, --commit does not resolve, --repo is not
# a git worktree, disk-safety floor not met); 4 an internal step
# (slicer.py / precheck_pack.sh itself) could not produce an honest
# verdict at all.
#
# Idempotency: before touching git/worktree/slicer.py/precheck_pack.sh at
# all, this script checks whether <out-dir>/precheck.json already exists
# AND is schema-valid (review/lib/precheck_pack_build_run.py's own `emit
# --validate-only`). Only a genuinely usable cached pack short-circuits
# the full build -- a missing/corrupt/partial prior attempt always falls
# through to a real, fresh build, never trusted blindly.
#
# Worktree cleanup: ALWAYS, via an EXIT/INT/TERM trap, even when the
# build fails partway through -- mirrors cycle/baseline_replay.sh's own
# "this script never leaves an orphan worktree" discipline, at the
# lighter weight this tool's much smaller (non-recursive, single-repo)
# worktree needs. The worktree itself lives under
# <const-root>/.fc_worktrees/ (the SAME sibling-of-the-repo convention
# baseline_replay.sh already established) -- never inside --out-dir,
# which stays limited to the three permanent, cacheable artifacts.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
CONST_ROOT=$(cd "$FC/../.." && pwd)
PARENT_ROOT=$(cd "$CONST_ROOT/.." && pwd)
SLICER="$FC/review/slicer.py"
PRECHECK="$FC/review/precheck_pack.sh"
BUILD_LIB="$FC/review/lib/precheck_pack_build_run.py"

COMMIT=""
LOGIC_GROUP=""
OUT_DIR=""
SLICE_LIMIT=400
MIN_FREE_KB=1048576
SNAPSHOT_PATHS=""
REPO_ROOT=""
SC_EXCEPTIONS=""
SC_TIMEOUT=""
SC_EX_TIMEOUT=""

need() { [ "$1" -ge 2 ] || { echo "precheck_pack_build: $2 requires a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
    case "$1" in
        --commit) need $# "$1"; COMMIT="$2"; shift 2 ;;
        --logic-group) need $# "$1"; LOGIC_GROUP="$2"; shift 2 ;;
        --out-dir) need $# "$1"; OUT_DIR="$2"; shift 2 ;;
        --slice-limit) need $# "$1"; SLICE_LIMIT="$2"; shift 2 ;;
        --min-free-kb) need $# "$1"; MIN_FREE_KB="$2"; shift 2 ;;
        --snapshot-paths) need $# "$1"; SNAPSHOT_PATHS="$2"; shift 2 ;;
        --repo-root) need $# "$1"; REPO_ROOT="$2"; shift 2 ;;
        --shellcheck-exceptions) need $# "$1"; SC_EXCEPTIONS="$2"; shift 2 ;;
        --shellcheck-timeout) need $# "$1"; SC_TIMEOUT="$2"; shift 2 ;;
        --shellcheck-exception-timeout) need $# "$1"; SC_EX_TIMEOUT="$2"; shift 2 ;;
        *)
            echo "precheck_pack_build: unknown option: $1" >&2
            exit 2 ;;
    esac
done

if [ -n "$COMMIT" ] && [ -n "$SNAPSHOT_PATHS" ]; then
    echo "precheck_pack_build: --commit and --snapshot-paths are mutually exclusive" >&2; exit 2
fi
[ -n "$COMMIT" ] || [ -n "$SNAPSHOT_PATHS" ] || { echo "precheck_pack_build: --commit or --snapshot-paths is required" >&2; exit 2; }
case "$SC_EXCEPTIONS" in
    ''|config/shellcheck_legacy_exceptions.tsv) ;;
    *) echo "precheck_pack_build: --shellcheck-exceptions may only name the canonical config/shellcheck_legacy_exceptions.tsv (a bound run refuses any other file)" >&2; exit 2 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    echo "precheck_pack_build: python3 not found on PATH" >&2
    exit 2
fi
for _tool in "$SLICER" "$PRECHECK" "$BUILD_LIB"; do
    if [ ! -f "$_tool" ]; then
        echo "precheck_pack_build: required sibling tool is missing: $_tool" >&2
        exit 2
    fi
done

# --- Repository under review (default: the constitution submodule) ---
SPARSE=0
if [ -z "$REPO_ROOT" ]; then
    REPO="$CONST_ROOT"
else
    case "$REPO_ROOT" in
        /*) ;;
        *) echo "precheck_pack_build: --repo-root must be an absolute path" >&2; exit 2 ;;
    esac
    _top=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null) || {
        echo "precheck_pack_build: --repo-root is not a git repository: $REPO_ROOT" >&2; exit 2; }
    if [ "$(cd "$_top" && pwd -P)" != "$(cd "$REPO_ROOT" && pwd -P)" ]; then
        echo "precheck_pack_build: --repo-root is not a repository toplevel (toplevel: $_top)" >&2; exit 2
    fi
    REPO=$(cd "$REPO_ROOT" && pwd -P)
    [ "$REPO" = "$(cd "$CONST_ROOT" && pwd -P)" ] || SPARSE=1
fi

KIND=commit
if [ -n "$SNAPSHOT_PATHS" ]; then
    [ -f "$SNAPSHOT_PATHS" ] || { echo "precheck_pack_build: --snapshot-paths file not found: $SNAPSHOT_PATHS" >&2; exit 2; }
    SNAP_OUT=$(python3 "$BUILD_LIB" snapshot --repo "$REPO" --paths-file "$SNAPSHOT_PATHS") || {
        echo "precheck_pack_build: snapshot of the uncommitted paths failed" >&2; exit 2; }
    SNAP_BASE=$(printf '%s\n' "$SNAP_OUT" | sed -n 's/^BASE_SHA=//p')
    SNAP_HEAD=$(printf '%s\n' "$SNAP_OUT" | sed -n 's/^HEAD_SHA=//p')
    [ -n "$SNAP_BASE" ] && [ -n "$SNAP_HEAD" ] || { echo "precheck_pack_build: snapshot produced no BASE/HEAD" >&2; exit 2; }
    COMMIT="${SNAP_BASE}..${SNAP_HEAD}"
    KIND=snapshot
fi

case "$COMMIT" in
    *..*)
        BASE_REF=${COMMIT%%..*}
        HEAD_REF=${COMMIT#*..}
        ;;
    *)
        BASE_REF="$COMMIT^"
        HEAD_REF="$COMMIT"
        ;;
esac

HEAD_SHA=$(git -C "$REPO" rev-parse --verify "${HEAD_REF}^{commit}" 2>/dev/null) || {
    echo "precheck_pack_build: --commit's head ref does not resolve to a real commit in $REPO: $HEAD_REF" >&2
    exit 2
}
if git -C "$REPO" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    BASE_SHA=$(git -C "$REPO" rev-parse --verify "${BASE_REF}^{commit}")
else
    # A single, parent-less (root) commit: diff against git's real empty-tree id.
    BASE_SHA=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

case "$COMMIT" in
    *..*) KEY="${BASE_SHA}..${HEAD_SHA}" ;;
    *) KEY="$HEAD_SHA" ;;
esac

if [ -z "$SC_EXCEPTIONS" ] && git -C "$REPO" cat-file -e "$HEAD_SHA:config/shellcheck_legacy_exceptions.tsv" 2>/dev/null; then
    SC_EXCEPTIONS=config/shellcheck_legacy_exceptions.tsv
fi

SHORT_HEAD=$(git -C "$REPO" rev-parse --short=12 "$HEAD_SHA")
[ -n "$LOGIC_GROUP" ] || LOGIC_GROUP="precheck-$SHORT_HEAD"
[ -n "$OUT_DIR" ] || OUT_DIR="$PARENT_ROOT/qa-results/fastcycle/precheck_packs/$KEY"

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)

# --- Idempotency: a schema-valid pack for this content-addressed KEY, built by
# the CURRENT gate and bound to this base/head, is reused verbatim. `emit
# --validate-only`: 0 reusable all_pass=true; 1 reusable all_pass=false; 3
# missing/stale/unbound -> rebuild. ---
if [ -f "$OUT_DIR/precheck.json" ]; then
    VALIDATE_RC=0
    python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" --validate-only \
        --expect-base "$BASE_SHA" --expect-head "$HEAD_SHA" \
        --expect-sc-timeout "$SC_TIMEOUT" --expect-sc-exception-timeout "$SC_EX_TIMEOUT" \
        >/dev/null 2>"$OUT_DIR/.cache_check.err" || VALIDATE_RC=$?
    if [ "$VALIDATE_RC" -eq 0 ] || [ "$VALIDATE_RC" -eq 1 ]; then
        rm -f "$OUT_DIR/.cache_check.err"
        if [ "$KIND" = snapshot ]; then
            python3 "$BUILD_LIB" snapshot-manifest --repo "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" \
                --paths-file "$SNAPSHOT_PATHS" --out "$OUT_DIR/WORKTREE_SNAPSHOT_MD5.txt" || exit 4
        fi
        CACHE_RC=0
        python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" || CACHE_RC=$?
        exit "$CACHE_RC"
    fi
    echo "precheck_pack_build: cached pack at $OUT_DIR is not reusable (rc=$VALIDATE_RC), rebuilding ($(cat "$OUT_DIR/.cache_check.err" 2>/dev/null))" >&2
    rm -f "$OUT_DIR/.cache_check.err"
fi

# --- Disk-safety floor before creating a worktree. ---
WT_ROOT="$CONST_ROOT/.fc_worktrees"
mkdir -p "$WT_ROOT"
FREE_KB=$(df -Pk "$WT_ROOT" 2>/dev/null | awk 'NR==2{print $4}')
case "$FREE_KB" in
    ''|*[!0-9]*)
        echo "precheck_pack_build: cannot read free disk space for $WT_ROOT (df failed)" >&2
        exit 2 ;;
esac
if [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
    echo "precheck_pack_build: insufficient free disk at $WT_ROOT: ${FREE_KB}KB available, ${MIN_FREE_KB}KB required (--min-free-kb) -- refusing to create a worktree" >&2
    exit 2
fi

WT_PATH=$(mktemp -d "$WT_ROOT/build.XXXXXX")
SCRATCH=$(mktemp -d "$WT_ROOT/scratch.XXXXXX")

# shellcheck disable=SC2329 # invoked indirectly via `trap cleanup ...` below
cleanup() {
    git -C "$REPO" worktree remove --force "$WT_PATH" >/dev/null 2>&1
    rm -rf "$WT_PATH" "$SCRATCH"
    git -C "$REPO" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

# --- Enumerate the REAL changed paths, NUL-separated and unquoted
# (core.quotePath=false, -z); renames split into delete + add (--no-renames). ---
PATHS_FILE="$SCRATCH/paths.nul"
git -C "$REPO" -c core.quotePath=false diff -z --name-only --no-renames "$BASE_SHA" "$HEAD_SHA" -- > "$PATHS_FILE" || {
    echo "precheck_pack_build: git diff --name-only failed for $BASE_SHA..$HEAD_SHA" >&2
    exit 2
}
if [ ! -s "$PATHS_FILE" ]; then
    echo "precheck_pack_build: $BASE_SHA..$HEAD_SHA touches zero files -- nothing to review" >&2
    exit 2
fi

rmdir "$WT_PATH" 2>/dev/null || true  # `git worktree add` requires the target not already exist
if [ "$SPARSE" -eq 1 ]; then
    # PARTIAL checkout of exactly the changed paths (+ the exceptions TSV):
    # `worktree add --no-checkout` then a literal, NUL-separated pathspec
    # checkout of the paths that exist at head. No sparse-checkout config is
    # written (nothing changes in the reviewed repo's own config); the index
    # holds only the materialised paths, the commit's tree holds everything.
    git -C "$REPO" worktree add --no-checkout --detach --quiet "$WT_PATH" "$HEAD_SHA" || {
        echo "precheck_pack_build: git worktree add --no-checkout failed for $HEAD_SHA" >&2; exit 2; }
    set -- present-paths --repo "$REPO" --head "$HEAD_SHA" --paths-file "$PATHS_FILE"
    if [ -n "$SC_EXCEPTIONS" ]; then set -- "$@" --extra "$SC_EXCEPTIONS"; fi
    PRESENT_RC=0
    python3 "$BUILD_LIB" "$@" >"$SCRATCH/present.nul" || PRESENT_RC=$?
    if [ "$PRESENT_RC" -eq 0 ]; then
        GIT_LITERAL_PATHSPECS=1 git -C "$WT_PATH" checkout --quiet --pathspec-from-file="$SCRATCH/present.nul" \
            --pathspec-file-nul "$HEAD_SHA" || {
            echo "precheck_pack_build: partial checkout of $HEAD_SHA failed" >&2; exit 2; }
    elif [ "$PRESENT_RC" -ne 3 ]; then
        echo "precheck_pack_build: cannot list the changed paths present at head" >&2; exit 2
    fi
else
    git -C "$REPO" worktree add --detach --quiet "$WT_PATH" "$HEAD_SHA" || {
        echo "precheck_pack_build: git worktree add failed for $HEAD_SHA" >&2
        exit 2
    }
fi

# --- Per-change descriptors + diffs (real sha256) + config.yaml (lib) ---
PREP_OUT="$SCRATCH/prepare.out"
if ! python3 "$BUILD_LIB" prepare --repo "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" \
        --paths-file "$PATHS_FILE" --scratch "$SCRATCH/prep" --logic-group "$LOGIC_GROUP" \
        >"$PREP_OUT" 2>"$SCRATCH/prepare.err"; then
    cat "$SCRATCH/prepare.err" >&2
    echo "precheck_pack_build: prepare step failed" >&2
    exit 4
fi

DESCRIPTORS=""
CONFIG=""
while IFS= read -r _line; do
    case "$_line" in
        DESCRIPTORS=*) DESCRIPTORS=${_line#DESCRIPTORS=} ;;
        CONFIG=*) CONFIG=${_line#CONFIG=} ;;
    esac
done <"$PREP_OUT"
if [ -z "$DESCRIPTORS" ] || [ -z "$CONFIG" ]; then
    echo "precheck_pack_build: prepare step produced no DESCRIPTORS/CONFIG (malformed output)" >&2
    exit 4
fi

# --- slicer.py (RB-001) ---
if ! python3 "$SLICER" --config "$CONFIG" --changes "$DESCRIPTORS" --slice-limit "$SLICE_LIMIT" \
        --out "$OUT_DIR/batch.json" 2>"$SCRATCH/slicer.err"; then
    cat "$SCRATCH/slicer.err" >&2
    echo "precheck_pack_build: slicer.py failed to produce a batch" >&2
    exit 4
fi
cp "$CONFIG" "$OUT_DIR/config.yaml"

# --- Bind the batch to BASE/HEAD (F-R2-1, F5: kind=commit|snapshot). ---
if ! python3 "$BUILD_LIB" bind --repo "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" --kind "$KIND" \
        --batch "$OUT_DIR/batch.json" --out "$OUT_DIR/batch.json" >"$SCRATCH/bind.out" 2>"$SCRATCH/bind.err"; then
    cat "$SCRATCH/bind.err" >&2
    echo "precheck_pack_build: binding the batch to $BASE_SHA..$HEAD_SHA failed" >&2
    exit 4
fi

# --- precheck_pack.sh (RB-002): whole-file strict shellcheck, bound to the batch
# base/head of $REPO; its rc 0 (all_pass) and 1 (some FAIL) are both honest. ---
set -- --config "$SCRATCH" --batch "$OUT_DIR/batch.json" --clean-checkout "$WT_PATH" \
    --out "$OUT_DIR/precheck.json" --baseline-repo "$REPO" --baseline-ref "$BASE_SHA" --head-sha "$HEAD_SHA"
if [ -n "$SC_EXCEPTIONS" ]; then set -- "$@" --shellcheck-exceptions "$SC_EXCEPTIONS"; fi
if [ -n "$SC_TIMEOUT" ]; then set -- "$@" --shellcheck-timeout "$SC_TIMEOUT"; fi
if [ -n "$SC_EX_TIMEOUT" ]; then set -- "$@" --shellcheck-exception-timeout "$SC_EX_TIMEOUT"; fi
PRECHECK_RC=0
sh "$PRECHECK" "$@" || PRECHECK_RC=$?
if [ "$PRECHECK_RC" -ne 0 ] && [ "$PRECHECK_RC" -ne 1 ]; then
    echo "precheck_pack_build: precheck_pack.sh exited $PRECHECK_RC (no honest all_pass verdict)" >&2
    exit 4
fi

# --- F15: a snapshot pack carries a fresh WORKTREE_SNAPSHOT_MD5.txt generated
# from the frozen head object (rewritten on every build, never hand-kept). ---
if [ "$KIND" = snapshot ]; then
    python3 "$BUILD_LIB" snapshot-manifest --repo "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" \
        --paths-file "$SNAPSHOT_PATHS" --out "$OUT_DIR/WORKTREE_SNAPSHOT_MD5.txt" || {
        echo "precheck_pack_build: cannot write WORKTREE_SNAPSHOT_MD5.txt" >&2; exit 4; }
fi

EMIT_RC=0
python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" || EMIT_RC=$?
exit "$EMIT_RC"
