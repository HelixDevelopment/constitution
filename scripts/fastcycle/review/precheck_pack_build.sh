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
#   precheck_pack_build.sh --commit <sha>[..<sha>] [--logic-group <name>]
#       [--out-dir <dir>] [--slice-limit <lines>] [--min-free-kb <kb>]
#
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

while [ $# -gt 0 ]; do
    case "$1" in
        --commit)
            [ $# -ge 2 ] || { echo "precheck_pack_build: --commit requires a value" >&2; exit 2; }
            COMMIT="$2"; shift 2 ;;
        --logic-group)
            [ $# -ge 2 ] || { echo "precheck_pack_build: --logic-group requires a value" >&2; exit 2; }
            LOGIC_GROUP="$2"; shift 2 ;;
        --out-dir)
            [ $# -ge 2 ] || { echo "precheck_pack_build: --out-dir requires a value" >&2; exit 2; }
            OUT_DIR="$2"; shift 2 ;;
        --slice-limit)
            [ $# -ge 2 ] || { echo "precheck_pack_build: --slice-limit requires a value" >&2; exit 2; }
            SLICE_LIMIT="$2"; shift 2 ;;
        --min-free-kb)
            [ $# -ge 2 ] || { echo "precheck_pack_build: --min-free-kb requires a value" >&2; exit 2; }
            MIN_FREE_KB="$2"; shift 2 ;;
        *)
            echo "precheck_pack_build: unknown option: $1" >&2
            exit 2 ;;
    esac
done

[ -n "$COMMIT" ] || { echo "precheck_pack_build: --commit is required" >&2; exit 2; }

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

# --- Resolve --commit into BASE_REF/HEAD_REF (two-dot range, or a single
# commit diffed against its own parent / the empty tree for a root
# commit) and a content-addressed cache KEY, all against CONST_ROOT (this
# wrapper builds packs for commits IN THE CONSTITUTION SUBMODULE only). ---
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

HEAD_SHA=$(git -C "$CONST_ROOT" rev-parse --verify "${HEAD_REF}^{commit}" 2>/dev/null) || {
    echo "precheck_pack_build: --commit's head ref does not resolve to a real commit in $CONST_ROOT: $HEAD_REF" >&2
    exit 2
}
if git -C "$CONST_ROOT" rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    BASE_SHA=$(git -C "$CONST_ROOT" rev-parse --verify "${BASE_REF}^{commit}")
else
    # A single, parent-less (root) commit: diff against the real empty-tree
    # object id (git's own well-known constant, not a guess) rather than a
    # nonexistent "^" parent.
    BASE_SHA=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

case "$COMMIT" in
    *..*) KEY="${BASE_SHA}..${HEAD_SHA}" ;;
    *) KEY="$HEAD_SHA" ;;
esac

SHORT_HEAD=$(git -C "$CONST_ROOT" rev-parse --short=12 "$HEAD_SHA")
[ -n "$LOGIC_GROUP" ] || LOGIC_GROUP="precheck-$SHORT_HEAD"
[ -n "$OUT_DIR" ] || OUT_DIR="$PARENT_ROOT/qa-results/fastcycle/precheck_packs/$KEY"

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)

# --- Idempotency: a schema-valid pack already present for this content-
# addressed KEY is reused verbatim -- zero git/worktree/slicer/precheck
# work repeated (the manual sequence's own dominant cost). `emit
# --validate-only`'s real exit code distinguishes three outcomes (never
# a bare "did the command succeed" test, which would wrongly treat a
# valid-but-all_pass=false cache hit (rc=1) as "unusable, rebuild"):
#   0 -> schema-valid, all_pass=true   (reuse, dispatch-ready)
#   1 -> schema-valid, all_pass=false  (reuse, NOT dispatch-ready -- still
#        a real, reusable pack; rebuilding would not change its content)
#   3 -> missing/unreadable/schema-invalid (fall through to a real rebuild)
# Captured via `||` so a nonzero (1 or 3) result never triggers `set -e`. ---
if [ -f "$OUT_DIR/precheck.json" ]; then
    VALIDATE_RC=0
    python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" --validate-only \
        >/dev/null 2>"$OUT_DIR/.cache_check.err" || VALIDATE_RC=$?
    if [ "$VALIDATE_RC" -eq 0 ] || [ "$VALIDATE_RC" -eq 1 ]; then
        rm -f "$OUT_DIR/.cache_check.err"
        CACHE_RC=0
        python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" || CACHE_RC=$?
        exit "$CACHE_RC"
    fi
    # VALIDATE_RC == 3 (or an unexpected code): cache present but genuinely
    # unusable (e.g. an earlier run crashed mid-write) -- fall through to a
    # real, fresh build rather than trust a possibly-partial artefact.
    echo "precheck_pack_build: cached pack at $OUT_DIR is not schema-valid (rc=$VALIDATE_RC), rebuilding ($(cat "$OUT_DIR/.cache_check.err" 2>/dev/null))" >&2
    rm -f "$OUT_DIR/.cache_check.err"
fi

# --- Disk-safety floor before creating a worktree (house convention,
# cycle/baseline_replay.sh's own --min-free-kb check). ---
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
    git -C "$CONST_ROOT" worktree remove --force "$WT_PATH" >/dev/null 2>&1
    rm -rf "$WT_PATH" "$SCRATCH"
}
trap cleanup EXIT INT TERM

rmdir "$WT_PATH" 2>/dev/null || true  # `git worktree add` requires the target not already exist
git -C "$CONST_ROOT" worktree add --detach --quiet "$WT_PATH" "$HEAD_SHA" || {
    echo "precheck_pack_build: git worktree add failed for $HEAD_SHA" >&2
    exit 2
}

# --- Enumerate the REAL changed paths (never invented) ---
PATHS_FILE="$SCRATCH/paths.txt"
git -C "$CONST_ROOT" diff --name-only "$BASE_SHA" "$HEAD_SHA" -- > "$PATHS_FILE" || {
    echo "precheck_pack_build: git diff --name-only failed for $BASE_SHA..$HEAD_SHA" >&2
    exit 2
}
if [ ! -s "$PATHS_FILE" ]; then
    echo "precheck_pack_build: $BASE_SHA..$HEAD_SHA touches zero files -- nothing to review" >&2
    exit 2
fi

# --- Per-change descriptors + diffs (real sha256) + config.yaml (lib) ---
PREP_OUT="$SCRATCH/prepare.out"
if ! python3 "$BUILD_LIB" prepare --repo "$CONST_ROOT" --base "$BASE_SHA" --head "$HEAD_SHA" \
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

# --- precheck_pack.sh (RB-002) -- its real exit code (0 all_pass / 1 some
# FAIL) is EXPECTED to be nonzero on a genuine finding, so it is captured
# via `||` (never triggering `set -e`) rather than relied upon to survive
# to a bare `$?` on the next line. ---
PRECHECK_RC=0
sh "$PRECHECK" --config "$SCRATCH" --batch "$OUT_DIR/batch.json" --clean-checkout "$WT_PATH" \
    --out "$OUT_DIR/precheck.json" || PRECHECK_RC=$?
if [ "$PRECHECK_RC" -ne 0 ] && [ "$PRECHECK_RC" -ne 1 ]; then
    echo "precheck_pack_build: precheck_pack.sh exited $PRECHECK_RC (no honest all_pass verdict)" >&2
    exit 4
fi

EMIT_RC=0
python3 "$BUILD_LIB" emit --out-dir "$OUT_DIR" || EMIT_RC=$?
exit "$EMIT_RC"
