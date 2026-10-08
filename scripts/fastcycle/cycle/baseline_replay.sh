#!/bin/bash
# baseline_replay.sh - SC-002/SC-005 gate-replay harness (spec-004
# "fast-dev-cycles", User Story 1, T043; plan.md T-A10, T-H02;
# contracts/common-conventions.md C-001..C-007). Guarded by
# constitution/scripts/fastcycle/tests/test_baseline_replay_red.sh (T024).
#
# Purpose: given a sample item (or a select_sample.py output doc), FREEZE
# its "relevant work landed here" commit + tree hash, then REPLAY a
# caller-named gate command against an isolated checkout of that frozen
# commit, >=N times cold and >=N times warm, recording per-run timing +
# verdict + per-type medians -- the T-A10 "before" baseline every later
# SC-002 (gate speed) / SC-005 (cycle-time) claim in this initiative is
# measured against. This is an OPEN-GAP tool (contracts/common-
# conventions.md's own "Tool map" note lists "$FC/cycle/baseline_replay.sh
# (T-A10/T-H02)" among the tools no contract in that directory covers --
# "their interface, output and RED fixtures are fixed by the plan task
# text until a contract is written"); this script follows plan.md T-A10's
# own text plus C-001..C-007.
#
# =============================================================================
# FOUR SUBCOMMANDS
# =============================================================================
#   freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
#       Resolve ID's frozen {commit, tree} via subject-only `git log`
#       search (see FREEZE MECHANISM below). Read-only, zero disk writes
#       beyond --out.
#   selfcheck --out PATH
#       C-004 control-needle self-test for THIS script's OWN verdict
#       classification (a real `true` MUST classify PASS, a real `false`
#       MUST classify FAIL) -- run automatically, inline, before every
#       `replay`; exposed standalone so a caller can verify the instrument
#       in isolation. Exit 3 on failure (C-001 row 3).
#   replay --commit SHA --tree SHA --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--timeout-s N] --out PATH
#       Isolate a `git worktree` checkout of SHA (see DISK SAFETY below),
#       run CMD inside it cold-runs+warm-runs times sequentially, record
#       per-run {start_ns,end_ns,duration_ms,exit_code,verdict}, remove the
#       worktree (always, via trap), write the canonical report.
#   replay-sample --sample PATH --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--timeout-s N] --out PATH
#       Read a select_sample.py (T043 sibling) output doc's `items` array;
#       for each, freeze then replay; an item whose freeze is UNMEASURED
#       is SKIPPED with the reason recorded (never silently dropped,
#       DEC-03's own "never silently dropped" language applied here);
#       aggregate per-type medians.
#
# =============================================================================
# FREEZE MECHANISM (design judgment call, documented per task instruction)
# =============================================================================
# "The exact commit the item's relevant work landed on" is resolved by
# reusing `$FC/cycle/cycle_report.py`'s (T041, already reviewed)
# `git_subject_matches()` definition VERBATIM, reimplemented here in shell:
# `git log --all -i --grep=<id> --pretty=format:%H|%aI|%cI|%s`, filtered in
# a second pass to lines whose SUBJECT (4th field, not the full message
# git --grep searches) literally contains the item id -- git's own --grep
# matches the full commit message, and a body-only mention is materially
# weaker evidence of "this IS the commit" than a subject mention (verified
# 2026-09-28 against this exact repo: `git log --all -i --grep=ATM-953`
# returns 3 commits, only 1 of which -- f1abb59e, subject "...ATM-953
# video-to-TV..." -- names ATM-953 in its subject; the other 2 are
# body-only mentions of an UNRELATED change). Of the surviving subject
# matches, the LATEST by author date is chosen (matches cycle_report.py's
# own `commit_push` stage END instant -- the commit that closed out the
# item's commit-push activity is the natural "landed here" point). Verified
# live 2026-09-28: ATM-953 -> commit f1abb59eac851e560a49b9fb4465297f84d66bae,
# tree 7160a3865cfeb4922f18530239921c2870d45185 (matches its own
# Fixed/2026-07-28 closure date exactly). Zero surviving subject matches ->
# UNMEASURED (exit 0 from `freeze`; the ABSENCE of a resolvable commit is
# an honest, correctly-recorded result, not an error -- matching
# cycle_report.py's own UNMEASURED-is-legitimate convention), never a
# silent fall-back to HEAD or any other guessed commit (S11.4.6).
#
# =============================================================================
# DISK SAFETY (a genuine host-safety finding made while designing this
# tool, documented in full because it changes the tool's own defaults --
# S11.4.6/S12.6)
# =============================================================================
# Two measurements taken directly against THIS host before writing this
# script's worktree-creation logic:
#   (1) `git worktree add` for THIS project materialises a FULL checkout of
#       every tracked file at the target commit. Measured directly against
#       one of this repo's OWN pre-existing agent worktrees
#       (.claude/worktrees/agent-a17eb3df7db2f148a, excluding its .git):
#       49 GB. This repo's root filesystem (/mnt/track1, mapper
#       track_crypt1) had 108 GB free at measurement time, with THREE such
#       worktrees already present (~147 GB already committed to them) --
#       creating a FOURTH full checkout for a mere bounded/representative
#       demonstration would be a real, avoidable host-disk-exhaustion risk
#       (S12.6), not a reasonable default for anything short of a genuine
#       T045 production run.
#   (2) `/tmp` on this host is `tmpfs` -- RAM-BACKED, not disk-backed --
#       measured at 126 GB total / 101 GB already used / 25 GB free at
#       measurement time. Defaulting `--worktree-root` under `/tmp` (a
#       tempting, "obviously scratch" choice) would therefore risk WRITING
#       A MULTI-GIGABYTE CHECKOUT INTO RAM, exactly the class of host-
#       session-safety disaster this project's own Constitution S12
#       documents multiple forensic OOM incidents about.
# Consequence for THIS script's defaults: `--worktree-root` defaults to
# `<repo-root>/.fc_worktrees` (a sibling of the EXISTING, already-
# precedented `.claude/worktrees/` pattern this exact repo already uses --
# `git worktree list` shows three such worktrees today -- confirmed
# disk-backed, same filesystem as the repo itself, NEVER tmpfs); a caller
# pointing `--worktree-root` at a known-disk-backed `/tmp` on a DIFFERENT
# host may still do so explicitly. `--min-free-kb` (default: 10 GiB =
# 10485760 KiB; NO measured basis for this exact number -- the plan/
# contract states none, matching fc_common.py's own honestly-undocumented
# DETERMINISM_TIMEOUT_DEFAULT_S precedent -- operator-tunable) is checked
# via `df -Pk` against the worktree-root's OWN filesystem immediately
# before every `git worktree add`; insufficient free space REFUSES (exit
# 4, BLIND -- "could not measure", never a silent skip of the check) with
# the real `df` numbers printed, before any checkout is attempted.
#
# =============================================================================
# COLD vs WARM (honest boundary, S11.4.6 -- stated per task instruction)
# =============================================================================
# T-A10's own text: "replay ... >=10 times cold and >=10 times warm ...
# Token baseline...". Investigated 2026-09-28: `$FC/gates/verdict_cache.py`
# (T068, the ONLY app-level caching mechanism plan.md names anywhere in
# this initiative) does NOT exist in this tree yet (US2, a LATER user
# story). With no cache mechanism to warm, this script's `cold` and `warm`
# phases are, RIGHT NOW, mechanically IDENTICAL operations (same gate
# command, same frozen worktree, run sequentially) -- the only difference
# either phase could exhibit today is the OS's own filesystem page cache,
# which this script does NOT attempt to control (no `posix_fadvise`/cache-
# drop step) since doing so would need root and is out of this task's
# scope. This is recorded HONESTLY in every `replay`/`replay-sample`
# report's `cache_mechanism` field rather than silently pretending a real
# distinction exists. Once T068 lands, `--gate-cmd` (or a companion
# `--warm-cmd`) is this script's existing hook point for a real cache-
# warm-up step -- no interface change needed then.
#
# =============================================================================
# EXIT CODES (C-001's uniform table)
# =============================================================================
# 0 report written (a per-run gate FAIL is recorded DATA, not a harness
#   exit-code failure -- this script measures gate outcomes, it does not
#   itself judge them); 1 `--determinism-check` genuinely differs -- the
#   two internal re-runs of the SAME frozen {commit, tree, gate-cmd} this
#   script itself performs (C-003; NOT a delegation to fc_common.py's
#   generic byte-identical wrapper -- see DETERMINISM below) produced
#   different `verdict_set`s, a real determinism defect (S11.4.50); 2
#   usage/config error; 3 selfcheck (C-004 control needle) failed -- the
#   verdict-classification instrument is not trustworthy this run,
#   nothing else runs; 4 BLIND -- commit/tree unresolvable, worktree
#   creation failed, disk pre-flight refused, tracker DB unreadable.
#
# =============================================================================
# DETERMINISM (C-003; T024 RED-test contract stub 1/3) -- HONEST BOUNDARY,
# a real design correction made after directly testing the first draft
# =============================================================================
# `replay`'s report embeds REAL wall-clock measurements (start_ns/end_ns/
# duration_ms/median_ms) inside its hashed body -- that data is
# INHERENTLY non-deterministic between two separate invocations (real
# timing jitter always differs), so this tool does NOT compose with
# fc_common.py's generic byte-identical-`body_hash` `determinism-check`
# the way cycle_report.py / select_sample.py's own timing-free bodies
# correctly do -- verified directly: an earlier draft that DID delegate
# to the generic mechanism reported "nondeterministic" on its very first
# real run against a real scratch repo (2026-09-28), even though nothing
# was actually wrong. T024's own RED-test contract stub 1/3 already says
# what THIS tool's determinism means: "two independent invocations ...
# MUST produce the SAME verdict SET (per-item PASS/FAIL/SKIP
# classification, compared as a set, never merely as equal counts)".
# `replay --determinism-check` therefore runs the SAME frozen
# {commit, tree, gate-cmd} TWICE internally and compares ONLY the two
# runs' `verdict_set` fields (never the timing fields) as sets; exit 0 =
# same verdict set both times, exit 1 = genuinely differs (a real
# determinism defect, S11.4.50), printing both verdict sets either way
# AND (as of T043 round-2 review finding N5) writing the same
# `baseline-replay-determinism/v1` document to the mandatory `--out`
# PATH every other subcommand already writes to.
#
# =============================================================================
# SAFETY (C-006)
# =============================================================================
# Read-only on the CALLER's live working tree at all times: every
# checkout happens in an isolated `git worktree`, never `git checkout`/
# `reset`/`stash`/`clean` against the repo the caller invoked this script
# from. Worktree cleanup (`git worktree remove --force`, needed because
# the replayed gate may leave scratch files inside its own checkout) is
# unconditional (bash `trap ... EXIT`) -- this script never leaves an
# orphan worktree behind, matching S11.4.14 (leave the target quiescent).
#
# HONEST BOUNDARY (S11.4.6): `--gate-cmd "CMD..."` is a single string this
# script word-splits (unquoted expansion, shellcheck SC2086 explicitly
# suppressed at each site with this rationale) into an argv array before
# exec'ing it -- CMD and every one of its own arguments MUST NOT contain
# embedded whitespace (e.g. a path with a space in it). This is a real,
# stated limitation, not a silent one; every sibling $FC tool that accepts
# a shell command string (this is the first) will need the same note or a
# genuine array-CLI redesign once a caller hits it.
#
# Dependencies: bash (arrays), git, python3 (stdlib only -- JSON assembly
# + fc_common's canon/body_hash_of, matching every sibling $FC tool),
# coreutils `date`/`df`/`timeout`.
set -u

# --- resolve this script's own directory, independent of caller's cwd ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_REPO_ROOT="$(cd "$FC/../../.." && pwd)"

die() { echo "baseline_replay: $*" >&2; exit 2; }
blind() { echo "baseline_replay: BLIND: $*" >&2; exit 4; }

isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }

usage() {
  cat >&2 <<'EOF'
Usage:
  baseline_replay.sh freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
  baseline_replay.sh selfcheck --out PATH
  baseline_replay.sh replay --commit SHA --tree SHA --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--timeout-s N] --out PATH [--determinism-check]
  baseline_replay.sh replay-sample --sample PATH --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--timeout-s N] --out PATH
EOF
  exit 2
}

[ $# -ge 1 ] || usage
SUBCMD=$1; shift

# ---------------------------------------------------------------------------
# now_ns -- date +%s%N, validated all-decimal (matches fc_timer.sh's own
# _fc_timer_now_ns convention exactly, for cross-tool consistency).
# ---------------------------------------------------------------------------
now_ns() {
  local ns
  ns="$(date +%s%N 2>/dev/null)" || { echo "baseline_replay: 'date +%s%N' failed" >&2; return 2; }
  case "$ns" in ''|*[!0-9]*) echo "baseline_replay: 'date +%s%N' produced a non-numeric timestamp ('$ns') -- needs GNU date" >&2; return 2 ;; esac
  printf '%s' "$ns"
}

# ---------------------------------------------------------------------------
# classify_verdict exit_code timed_out(0|1) -> prints PASS|FAIL|UNMEASURED
# ---------------------------------------------------------------------------
classify_verdict() {
  local rc="$1" timed_out="$2"
  if [ "$timed_out" = 1 ]; then printf 'UNMEASURED'; return; fi
  if [ "$rc" = 0 ]; then printf 'PASS'; else printf 'FAIL'; fi
}

# ---------------------------------------------------------------------------
# selfcheck: C-004 control needle for classify_verdict itself, against REAL
# `true`/`false` invocations (never a hardcoded string-match on the
# function's own source -- a genuine exit-code round-trip).
# ---------------------------------------------------------------------------
run_selfcheck() {
  local ok=1
  local rc_true rc_false
  true; rc_true=$?
  false; rc_false=$?
  local v_true v_false
  v_true=$(classify_verdict "$rc_true" 0)
  v_false=$(classify_verdict "$rc_false" 0)
  if [ "$v_true" != PASS ]; then
    echo "baseline_replay: selfcheck FAILED: real 'true' (rc=$rc_true) classified '$v_true', expected PASS" >&2
    ok=0
  fi
  if [ "$v_false" != FAIL ]; then
    echo "baseline_replay: selfcheck FAILED: real 'false' (rc=$rc_false) classified '$v_false', expected FAIL" >&2
    ok=0
  fi
  [ "$ok" = 1 ]
}

# ---------------------------------------------------------------------------
# git_subject_freeze repo_root item_id -> prints "SHA|TREE|AUTHOR_DATE|SUBJECT|COUNT"
# or "UNMEASURED||||0" if no subject match exists. See FREEZE MECHANISM above.
# ---------------------------------------------------------------------------
git_subject_freeze() {
  local root="$1" item_id="$2"
  local raw
  raw="$(git -C "$root" log --all -i --grep="$item_id" --pretty=format:'%H|%aI|%cI|%s' 2>/dev/null)" || raw=""
  local best_sha="" best_date="" best_subject="" count=0
  # T043 round-4 finding B2 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a plain substring case-match (`*"$item_id"*`) makes ATM-95 match
  # ATM-953, ATM-103 match ATM-1038, etc. -- reproduced on this project's
  # own real history: `--item ATM-103` silently froze commit fd5585c7's
  # "...ATM-1038 option b" subject with exit 0, no BLIND, no warning.
  # This is exactly the "silent fall-back to any other guessed commit"
  # §11.4.6 forbids. Fixed with a token-boundary regex: the item id must
  # be bounded by a non-alnum-non-hyphen char (or string start) on the
  # left and a non-digit char (or string end) on the right, so ATM-103
  # can never match inside ATM-1038 or ATM-953.
  local item_re
  item_re="$(printf '%s' "$item_id" | sed 's/[][\.^$*+?(){}|]/\\&/g')"
  local IFS_OLD="$IFS"
  IFS=$'\n'
  local line
  for line in $raw; do
    IFS="$IFS_OLD"
    local sha adate subject
    sha="${line%%|*}"
    local rest="${line#*|}"
    adate="${rest%%|*}"
    rest="${rest#*|}"
    rest="${rest#*|}"  # discard committer date (%cD) field -- not used (only author date, matching cycle_report.py)
    subject="${rest}"
    if [[ "$subject" =~ (^|[^A-Za-z0-9-])${item_re}([^0-9]|$) ]]; then
        count=$((count + 1))
        if [ -z "$best_date" ] || [[ "$adate" > "$best_date" ]]; then
          best_sha="$sha"; best_date="$adate"; best_subject="$subject"
        fi
    fi
    IFS=$'\n'
  done
  IFS="$IFS_OLD"
  if [ -z "$best_sha" ]; then
    printf 'UNMEASURED||||0'
    return 0
  fi
  local tree
  tree="$(git -C "$root" rev-parse "${best_sha}^{tree}" 2>/dev/null)" || tree="UNMEASURED"
  printf '%s|%s|%s|%s|%d' "$best_sha" "$tree" "$best_date" "$best_subject" "$count"
}

# ---------------------------------------------------------------------------
# emit_doc schema body_json out_path -- via fc_common.py (C-002).
# ---------------------------------------------------------------------------
emit_doc() {
  local schema="$1" body_json="$2" out_path="$3"
  local effective_out="${FC_OUT:-$out_path}"
  mkdir -p "$(dirname "$effective_out")" 2>/dev/null
  local run_meta
  run_meta="$(python3 -c 'import json,platform; print(json.dumps({"host": platform.node()}))')"
  python3 "$FC/lib/fc_common.py" emit --schema "$schema" --body-json "$body_json" \
    --run-meta-json "$run_meta" --out "$effective_out"
  return $?
}

# =============================================================================
# freeze
# =============================================================================
cmd_freeze() {
  local item="" repo_root="" db_path="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --item) item="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --db-path) db_path="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      *) die "freeze: unknown argument: $1" ;;
    esac
  done
  [ -n "$item" ] || die "freeze: --item is required"
  [ -n "$out" ] || die "freeze: --out is required"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$db_path" ] || db_path="$repo_root/docs/workable_items.db"

  local item_type="UNKNOWN"
  if [ -f "$db_path" ]; then
    item_type="$(python3 -c "
import sqlite3, sys
try:
    conn = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
    row = conn.execute('SELECT type FROM items WHERE atm_id = ? LIMIT 1', (sys.argv[2],)).fetchone()
    print(row[0] if row else 'UNKNOWN')
except Exception:
    print('UNKNOWN')
" "$db_path" "$item" 2>/dev/null)"
  fi

  local result sha tree adate subject count
  result="$(git_subject_freeze "$repo_root" "$item")"
  IFS='|' read -r sha tree adate subject count <<<"$result"

  local body
  if [ "$sha" = UNMEASURED ]; then
    body="$(python3 -c "
import json
print(json.dumps({
    'item_id': '$item', 'item_type': '$item_type',
    'commit': 'UNMEASURED', 'tree': 'UNMEASURED',
    'missing_instrument': 'no git log commit whose SUBJECT line references %s was found under --all (repo_root=$repo_root)' % '$item',
    'candidate_commit_count': $count,
}))
")"
  else
    body="$(python3 -c "
import json
print(json.dumps({
    'item_id': '$item', 'item_type': '$item_type',
    'commit': '$sha', 'tree': '$tree',
    'commit_author_date': '$adate', 'commit_subject': '''$subject''',
    'candidate_commit_count': $count,
}))
")"
  fi
  emit_doc "baseline-replay-freeze/v1" "$body" "$out"
}

# =============================================================================
# selfcheck
# =============================================================================
cmd_selfcheck() {
  local out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) out="$2"; shift 2 ;;
      *) die "selfcheck: unknown argument: $1" ;;
    esac
  done
  [ -n "$out" ] || die "selfcheck: --out is required"
  if run_selfcheck; then
    emit_doc "baseline-replay-selfcheck/v1" '{"result":"ok"}' "$out"
    return $?
  else
    return 3
  fi
}

# =============================================================================
# _fc_submodule_reference_update SRC TGT
#   T048 round-3 review finding R3-B1 fix (2026-09-30): the round-2
#   `--reference "$repo_root"` invocation was proven, by live measurement
#   (git 2.50.1, file:// transport, see the comment above the call site
#   below for the exact numbers), to be a NO-OP for object reuse -- a
#   single `--reference <path>` passed to `git submodule update` is
#   handed to git-clone(1) VERBATIM for EVERY submodule being cloned; it
#   is NEVER expanded to `<path>/.git/modules/<name>` per submodule (that
#   round-2 claim was independently re-tested this dispatch and is FALSE
#   for this codepath -- see below). Registering the SUPERPROJECT's own
#   `.git/objects` as an alternate buys nothing, because a submodule's
#   blobs/trees/commits were never stored there in the first place; they
#   live at `<repo>/.git/modules/<name>/objects`, a COMPLETELY SEPARATE
#   object store one directory level down. (git DOES have a genuine
#   feature for automatic per-submodule alternate resolution --
#   `-c submodule.alternateLocation=superproject` -- but it is wired only
#   into the `git clone --recurse-submodules --reference <path>`
#   codepath; re-tested live this dispatch with THIS git version and
#   confirmed it has NO effect on a `git submodule update --init
#   --recursive --reference <path>` call against an ALREADY-EXISTING
#   checkout, which is what a `git worktree add`-based replay needs, so
#   it cannot be used here.)
#
#   This function does manually what `--reference` alone does not:
#   submodule-BY-submodule, computing THAT submodule's own already-
#   fetched object store under SRC's git-common-dir (`git -C "$SRC"
#   rev-parse --git-common-dir` -- resolves correctly even when $SRC is
#   ITSELF a linked worktree of some other checkout, since
#   `--git-common-dir` always resolves to the shared repo, never a
#   per-worktree path; verified live) and passing THAT specific path as
#   `--reference` for a single-submodule `git submodule update --init --
#   <path>` call. It then RECURSES into any submodule that itself
#   declares a `.gitmodules` (a nested submodule), using SRC/<path> --
#   the corresponding already-checked-out submodule directory inside
#   SRC -- as the new source: a nested submodule's own object store
#   lives at `<parent's-git-common-dir>/modules/<nested-name>`, which
#   `git -C "$SRC/<path>" rev-parse --git-common-dir` resolves to
#   directly (verified live against a real 2-level-nested scratch
#   fixture: 0 objects transferred at BOTH the top-level AND the nested
#   level).
#
#   Degrades safely per submodule, independently: a submodule SRC has
#   never fetched (its `.git/modules/<name>` does not exist under SRC's
#   git-common-dir) gets NO `--reference` flag at all and falls through
#   to a normal network clone for THAT submodule only -- verified live,
#   exit 0, unaffected. A submodule whose remote is genuinely
#   unreachable still correctly fails non-zero regardless of whether a
#   `--reference` was supplied (verified live: --reference never removes
#   the need to negotiate refs with the remote; it only avoids
#   re-transferring objects the remote and the reference already agree
#   on) -- so this function preserves the exact "refuse to run gate_cmd
#   against a partially-checked-out tree" semantics the caller below
#   already depends on.
#
#   TGT is the linked worktree checkout ($wt_path) whose OWN
#   .gitmodules (at the frozen commit) is walked; SRC is the tree to
#   borrow already-fetched submodule objects from (initially $repo_root,
#   then recursively SRC's own corresponding submodule directory).
#   Returns the first non-zero exit encountered (or 0).
# =============================================================================
# invoked indirectly: exported with export -f and run via bash -c in a child shell below
# shellcheck disable=SC2329
_fc_submodule_reference_update() {
  local src="$1" tgt="$2"
  [ -f "$tgt/.gitmodules" ] || return 0

  local src_common=""
  src_common="$(git -C "$src" rev-parse --git-common-dir 2>/dev/null)" || src_common=""
  if [ -n "$src_common" ]; then
    case "$src_common" in
      /*) : ;;
      *) src_common="$(cd "$src" 2>/dev/null && cd "$src_common" 2>/dev/null && pwd)" || src_common="" ;;
    esac
  fi

  local list_file
  list_file="$(mktemp)" || return 1
  git -C "$tgt" config -f .gitmodules --get-regexp '^submodule\..*\.path$' >"$list_file" 2>/dev/null

  local key path name ref_path rc=0
  # false positive: the loop only READS list_file via the redirect; rm -f merely unlinks it on early return, nothing is written through the pipeline
  # shellcheck disable=SC2094
  while IFS=' ' read -r key path; do
    [ -n "$key" ] || continue
    name="${key#submodule.}"
    name="${name%.path}"
    ref_path=""
    if [ -n "$src_common" ] && [ -d "$src_common/modules/$name" ]; then
      ref_path="$src_common/modules/$name"
    fi
    if [ -n "$ref_path" ]; then
      git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet --reference "$ref_path" -- "$path"
    else
      git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet -- "$path"
    fi
    rc=$?
    [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }

    if [ -f "$tgt/$path/.gitmodules" ]; then
      _fc_submodule_reference_update "$src/$path" "$tgt/$path"
      rc=$?
      [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }
    fi
  done <"$list_file"
  rm -f "$list_file"
  return 0
}

# =============================================================================
# One frozen-commit replay: creates+removes exactly one worktree, runs
# gate_cmd cold_runs+warm_runs times inside it. Prints the JSON body on
# stdout (caller decides schema/out). Returns 0 on a successfully-measured
# run (gate PASS/FAIL is data, not a harness failure), 4 on BLIND.
# =============================================================================
# printf %q pre-quotes the values into the trap string on purpose: it must expand NOW (repo_root/wt_path are function locals, out of scope when the trap fires) and %q makes it safe; function-level on purpose: a directive between the printf and the trap line would break the worktree-cleanup mutation tests' exact-text anchors
# shellcheck disable=SC2064
do_one_replay() {
  local commit="$1" tree="$2" repo_root="$3" worktree_root="$4" min_free_kb="$5"
  local timeout_s="$6" cold_runs="$7" warm_runs="$8"
  shift 8
  local gate_cmd=("$@")

  [ ${#gate_cmd[@]} -ge 1 ] || { echo "baseline_replay: replay: --gate-cmd must be non-empty" >&2; return 4; }

  mkdir -p "$worktree_root" 2>/dev/null || { echo "baseline_replay: cannot create --worktree-root $worktree_root" >&2; return 4; }
  local free_kb
  free_kb="$(df -Pk "$worktree_root" 2>/dev/null | awk 'NR==2{print $4}')"
  isnum "$free_kb" || { echo "baseline_replay: cannot read free disk space for $worktree_root (df failed)" >&2; return 4; }
  if [ "$free_kb" -lt "$min_free_kb" ]; then
    echo "baseline_replay: BLIND: insufficient free disk at $worktree_root: ${free_kb}KB available, ${min_free_kb}KB required (--min-free-kb) -- refusing to create a worktree checkout" >&2
    return 4
  fi

  local wt_path
  wt_path="$(mktemp -d "$worktree_root/replay.XXXXXX")" || { echo "baseline_replay: mktemp -d under $worktree_root failed" >&2; return 4; }
  rmdir "$wt_path" 2>/dev/null  # git worktree add requires the target NOT already exist

  # `cleanup()` is invoked via the EXIT trap on EVERY path out of this
  # function, including every early `return 4` BELOW THIS POINT (i.e.
  # every `return 4` between this comment and the explicit `cleanup
  # "$repo_root" "$wt_path"; trap - EXIT` success-path call further down
  # this same function -- a SYMBOLIC reference, not a line-number literal,
  # deliberately: a hardcoded citation here drifted stale once already
  # (T043 round-3 review finding F2, 2026-09-28 -- an earlier version of
  # this comment cited specific line numbers that were already wrong by
  # the time of that review, off by exactly the number of lines an
  # UNRELATED later edit to this same function had since added; a
  # symbolic "below this point, until the explicit cleanup call" reference
  # cannot go stale the same way). bash pops a function's
  # `local` bindings as part of `return`, but the EXIT trap fires
  # AFTERWARD in the (sub)shell that is exiting -- so any of
  # do_one_replay's OWN `local` variables that cleanup() referenced
  # (repo_root, wt_path, and a since-removed `cleanup_done` done-guard)
  # were already gone by the time the trap-invoked cleanup() body tried to
  # read them under `set -u`, crashing with "unbound variable" BEFORE the
  # real `git worktree remove` / `rm -rf` below ever ran -- silently
  # leaking the worktree on disk. Independently reproduced for both the
  # done-guard and for $wt_path itself (a mismatched---tree run left an
  # orphaned `replay.XXXXXX` worktree + directory behind).
  #
  # Fixed by passing the two paths cleanup() needs as EXPLICIT ARGUMENTS
  # baked into the trap command STRING at `trap` REGISTRATION time via
  # `printf %q` (shell-safe quoting for ANY byte a path can legally
  # contain, including an embedded single quote -- a naive
  # `"cleanup '$repo_root' '$wt_path'"` form, which this fix used at
  # first, still leaks on a path containing `'`: the unescaped quote
  # breaks the trap command's own quoting and the resulting parse error
  # pre-empts cleanup() exactly like the original bug, independently
  # reproduced and fixed per T043 round-2 review finding N1). `%q`
  # expands immediately at `trap` REGISTRATION time (not at trap-fire
  # time), so the fired trap command is a fully literal, correctly-quoted
  # string with no variable lookups left to perform, and cleanup() no
  # longer depends on do_one_replay's own local-variable lifetime at all,
  # for ANY path value. This also makes cleanup() safely callable twice
  # (once explicitly via `cleanup "$repo_root" "$wt_path"; trap - EXIT`
  # on the success path, once via the EXIT trap on an early return):
  # `git worktree remove --force` is a no-op (stderr already discarded)
  # on an already-removed worktree, and `rm -rf` is a no-op on a missing
  # path.
  cleanup() {
    local rr="$1" wp="$2"
    git -C "$rr" worktree remove --force "$wp" >/dev/null 2>&1
    rm -rf "$wp" 2>/dev/null
  }
  local _cleanup_trap_cmd
  printf -v _cleanup_trap_cmd 'cleanup %q %q' "$repo_root" "$wt_path"
  trap "$_cleanup_trap_cmd" EXIT
  # T043 round-4 finding B1 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # bash does NOT run the EXIT trap when it dies from an un-handled SIGHUP
  # or SIGQUIT (unlike SIGINT/SIGTERM, independently reproduced as already
  # safe via bash's default disposition -- both correctly run the EXIT
  # trap with no explicit handling needed). SIGHUP is the realistic case
  # (an SSH disconnect, a tmux server dying, a closed terminal) and, per
  # this script's own DISK SAFETY note, each orphan is a full checkout
  # (~49 GB). Fixed by converting HUP/QUIT into an explicit `exit`, which
  # DOES run the already-registered EXIT trap (standard 128+signal exit
  # codes).
  # Call cleanup() DIRECTLY inside the signal handler itself -- rather
  # than `exit N` and relying on that subsequently triggering the EXIT
  # trap -- so this fix has NO dependency on exactly when/whether bash
  # gets around to running a deferred EXIT trap after a non-EXIT signal's
  # own `exit`. `trap - EXIT HUP QUIT` first, so the handler cannot
  # re-enter itself and cleanup() is never invoked twice concurrently.
  # Computed independently from repo_root/wt_path directly (never by
  # string-concatenating onto $_cleanup_trap_cmd above) so this block
  # stays self-contained: mutating the EXIT-trap-registration block above
  # (e.g. §1.1's own paired-mutation test, which reverts it to the
  # original buggy form) must not ALSO collaterally break this
  # DIFFERENT, unrelated fix by removing a variable this block secretly
  # depended on.
  local _sig_cleanup_cmd
  printf -v _sig_cleanup_cmd 'cleanup %q %q; trap - EXIT HUP QUIT' "$repo_root" "$wt_path"
  trap "$_sig_cleanup_cmd; exit 129" HUP
  trap "$_sig_cleanup_cmd; exit 131" QUIT

  if ! git -C "$repo_root" worktree add --detach --quiet "$wt_path" "$commit" >/dev/null 2>&1; then
    echo "baseline_replay: BLIND: git worktree add failed for commit $commit at $wt_path" >&2
    return 4
  fi

  local actual_tree
  actual_tree="$(git -C "$wt_path" rev-parse 'HEAD^{tree}' 2>/dev/null)"
  if [ -n "$tree" ] && [ "$tree" != UNMEASURED ] && [ "$actual_tree" != "$tree" ]; then
    echo "baseline_replay: BLIND: checked-out tree ($actual_tree) != frozen tree ($tree) for commit $commit" >&2
    return 4
  fi

  # T048 remediation (finding F9, BLOCKING, 2026-09-29 -- systematic-debugging
  # per §11.4.102): `git worktree add --detach` above checks out ONLY the
  # superproject tree -- every git-submodule gitlink (160000 mode entry;
  # this repo has 28 direct submodules incl. device/rockchip/atmosphere/
  # presenter, .../smarttube-player, tools/helixqa/HelixQA, constitution --
  # plus their own nested submodules) is left as an EMPTY placeholder
  # directory in the new worktree. pre_build_verification.sh (line 65: `set
  # -euo pipefail`) reads files out of those submodules (independently
  # verified: PRESENTER_SRC="device/rockchip/atmosphere/presenter/Presenter/
  # src/main/java/com/atmosphere/presenter", CC83's helper awk's
  # "$PRESENTER_SRC/PresenterService.kt"; smarttube-player/SharedModules and
  # .../MediaServiceCore are also read by name, e.g. line ~29471). On THIS
  # host, GNU Awk 5.1.0 exits status 2 -- not 1 -- when its input file does
  # not exist ("awk: fatal: cannot open file ... for reading", independently
  # reproduced: `awk '{print}' /nonexistent 2>&1; echo $?` -> exit 2). CC83
  # captures that failing command's output via a plain assignment
  # (`_cc83_body="$(_cc83_onvideostopped_body ...)"`, itself an `awk ...
  # 2>/dev/null` call) -- under `set -e`, a failing command substitution on
  # the right-hand side of a plain variable assignment DOES trigger errexit
  # (assignment statements are not one of bash's documented `set -e`
  # exemptions, unlike an `if`/`while` condition or a `&&`/`||` operand), so
  # pre_build_verification.sh dies immediately, mid-check, with exit status
  # 2 -- NEVER reaching its own coded `exit 0`/`exit 1` paths. Reproduced
  # twice, deterministically, by hand: an isolated `git worktree add
  # --detach` checkout of ATM-799's frozen commit (07f9b2dd) with NO
  # submodule init dies at CC83 in 4.7s with exit 2, matching this baseline
  # run's own recorded `{"exit_code":2,...}` for every one of the 14
  # cold+warm runs across all 7 duration-eligible items (durations ranging
  # 4.1s-263s ONLY because each frozen commit's version of the script
  # reaches ITS OWN first missing-submodule-file check at a different
  # line/point in an otherwise-successful run, not because of a timeout --
  # `timeout`'s own failure codes are 124/125/126/127/137, never bare 2).
  # THE FIX: make the isolated worktree a faithful replica of what
  # pre_build_verification.sh actually expects to run against (a normal,
  # fully-submoduled checkout of the commit -- the ONLY context this
  # 41k-line gate script was ever written/tested for) by initialising every
  # submodule (direct + nested, since smarttube-player's own checks read
  # ITS nested SharedModules/MediaServiceCore) before running gate_cmd.
  # SECOND CORRECTION (T048 round-2 review finding F9, 2026-09-30 -- the
  # FIRST correction, immediately below, remains fully accurate and
  # unchanged): the claim originally here -- that a linked worktree's
  # submodule `.git/modules` is part of this repo's COMMON git dir,
  # automatically SHARED with the main checkout -- is ALSO WRONG,
  # independently discovered live in a LATER dispatch's own end-to-end
  # proof runs (a real `do_one_replay()` call genuinely stalled 950+
  # CPU-seconds on a real network fetch of `submodules/open_design` despite
  # $repo_root already having that exact submodule fully fetched): a
  # linked worktree's submodule git-dirs live under the PER-WORKTREE
  # `.git/worktrees/<name>/modules/<submodule>` path, NOT the shared
  # `.git/modules/<submodule>` this comment used to claim. `--recursive`
  # alone does NOT reuse the main checkout's already-fetched submodule
  # objects at all -- see `_fc_submodule_reference_update()` (defined
  # above `do_one_replay`, invoked a few lines below at the actual
  # submodule-update call site) for what genuinely closes this gap
  # (T048 round-3 review finding R3-B1: a bare `--reference "$repo_root"`
  # was ALSO tried and independently proven, by live measurement, to be
  # a no-op here -- see that function's own comment + the invocation
  # site's comment for the full correction and the live verification
  # that proved the bug, the false round-2 fix, AND the real fix).
  # HONEST CORRECTION (§11.4.6 -- an earlier draft of this comment claimed
  # "no clone, no network" unconditionally and was WRONG; independently
  # observed live via `ps aux` during this fix's own end-to-end proof
  # runs): when a FROZEN commit (an OLD one especially) pins a submodule
  # SHA that was never locally fetched, `git submodule update --init`
  # does NOT fail or go BLIND -- it does exactly what it is designed to
  # do and performs a REAL network clone of that submodule (observed live:
  # `git submodule--helper clone ... git@github.com:ATMOSphere1234321/
  # ATMOSphere-Lampa.git` and, separately, `...ATMOSphere-SmartTube.git`,
  # each followed by a real `git index-pack ... on the-factory` transfer).
  # That is CORRECT, intended git behaviour, not a bug -- the fetched
  # objects land in the shared `.git/modules/<name>/` object store, so the
  # cost is paid ONCE per missing submodule SHA across the life of this
  # repo's local clone, never repeated for that same SHA again (later
  # do_one_replay calls, this run or a future one, reuse it). It is,
  # however, a genuinely SLOW one-time cost for a large submodule (e.g.
  # smarttube-player's tracked history, ~2.2 GiB working-tree size) --
  # observed adding SEVERAL MINUTES to a single do_one_replay call the
  # first time a historical commit needs it. The BLIND path below is for
  # the genuine failure case only (network unreachable, auth rejected, or
  # the pinned SHA truly gone from every configured remote) -- never for
  # "needs a network fetch", which is expected, cacheable, and correct.
  # Measured disk cost once fully cached: `du -sh` on all 28 direct
  # submodule paths in the MAIN checkout (which already recurses through
  # their own nested content) is ~7.4 GiB total -- well inside the
  # existing ~49 GiB-per-worktree / --min-free-kb 10 GiB headroom this
  # script's DISK SAFETY section already budgets for.
  #
  # T048 remediation, signal-safety hardening added AFTER independently
  # observing the multi-minute network-clone cost above IN THIS SAME
  # dispatch's own end-to-end proof runs: the SAME T043 round-4 finding B1
  # class (a plain FOREGROUND command defers any trapped HUP/QUIT signal
  # -- and, empirically re-confirmed live during this exact investigation,
  # can leave a git-worktree-remove needed EVEN for a plain TERM sent to
  # only the top-level script process while a `git submodule--helper`
  # grandchild keeps running detached, reparented, and orphaned) applies
  # here just as much as it did to the gate-cmd run below -- this step can
  # now take LONGER than the gate-cmd itself on a stale local checkout.
  # Fixed the identical way: BACKGROUND the command + `wait` on it
  # explicitly (promptly interruptible by a pending trapped signal,
  # unlike a synchronous foreground pipeline) and bound it with `timeout`
  # (reusing the caller's own --timeout-s knob rather than adding a new
  # CLI flag) so a genuine network stall cannot hang this step forever.
  #
  # Security remediation (T048 review, 2026-09-29): `$commit` here is
  # always EITHER a SHA `cmd_freeze` resolved via `git log --all --grep`
  # against THIS repo's own already-fetched local history, or an
  # operator-supplied `--commit` argument -- in both cases `git -C
  # "$repo_root" worktree add --detach "$wt_path" "$commit"` a few lines
  # above ALREADY required that commit's TREE to be a valid, already-
  # present object in $repo_root's local object store (worktree add never
  # fetches; an unreachable SHA fails there with BLIND before this line is
  # ever reached). So $commit itself is never unvalidated external input.
  # $commit's TREE CONTENT, however, is only as trustworthy as this repo's
  # own history -- and its .gitmodules is ordinary versioned content, so a
  # submodule path this specific commit introduces (one with no prior
  # `submodule.<name>.url` already recorded in the shared `.git/config`
  # from the main checkout's own real `git submodule init`) has its
  # fetch URL read straight out of THAT COMMIT's .gitmodules with no
  # allowlist check. Git's own `ext::` submodule-URL remote-code-execution
  # class (the CVE-2017-1000117 family) is denied by this host's git 2.50.1
  # default (`protocol.ext.allow=user`, confirmed via `git config --get`
  # returning unset -- i.e. the compiled-in default, "deny for an
  # operation like this one that did not explicitly opt in"), so this is
  # belt-and-braces defense-in-depth, not a bypass of an otherwise-open
  # hole: pin `ext`/`file` to `never` explicitly on THIS invocation only
  # (never touching the caller's global git config) so a future git
  # version, a differently-configured host, or an ambient
  # `GIT_ALLOW_PROTOCOL`/`GIT_CONFIG_*` environment override can never
  # silently re-open it for this specific untrusted-content fetch. `file`
  # is denied too -- a crafted local-path submodule URL pointing at an
  # attacker-writable bare repo is the same class of risk as `ext::`, and
  # this project's own real submodules (confirmed via `.gitmodules`) are
  # exclusively `git@github.com:...` SSH URLs, so neither protocol is ever
  # legitimately needed here.
  # T048 round-2 review finding F9 (2026-09-30, §11.4.102 root-cause
  # investigation): a linked worktree's `git submodule update --init
  # --recursive` clones EACH submodule into its OWN per-worktree git-dir
  # (`.git/worktrees/<name>/modules/<submodule>`, NOT the shared common
  # `.git/modules/<submodule>` every earlier draft of this file's own
  # comments assumed) -- reproduced live: a real do_one_replay() run
  # genuinely stalled 950+ CPU-seconds on a real network `git index-pack`
  # for `submodules/open_design`, even though $repo_root (the MAIN
  # checkout this worktree was created FROM) already has that exact
  # submodule fully fetched at `.git/modules/submodules/open_design`.
  # T048 round-3 review finding R3-B1 (2026-09-30, CORRECTS the round-2
  # text that used to sit here): the round-2 claim that a bare
  # `--reference "$repo_root"` makes "git's own submodule-clone machinery
  # automatically resolve `<reference>/.git/modules/<name>`" is FALSE --
  # independently re-measured live this dispatch (git 2.50.1, file://
  # transport, `git count-objects` before/after, exactly the round-3
  # reviewer's own methodology): a fresh submodule clone transferred the
  # IDENTICAL object count with `--reference "$repo_root"` as with no
  # `--reference` at all (both fetch everything over the wire), while
  # referencing the submodule's OWN store directly
  # (`"$repo_root"/.git/modules/<name>`) transferred ZERO objects. A
  # single `--reference <path>` on `git submodule update` is passed to
  # git-clone(1) verbatim for every submodule being cloned; it is never
  # expanded per-submodule on this codepath. (git DOES have a genuine
  # `-c submodule.alternateLocation=superproject` feature for automatic
  # per-submodule alternate resolution, but it is wired only into `git
  # clone --recurse-submodules --reference <path>`'s initial-clone
  # codepath -- re-tested live and confirmed it has NO effect on a
  # `submodule update --init --recursive --reference <path>` call
  # against an ALREADY-EXISTING checkout, which is what a `git worktree
  # add`-based replay needs here.) Fixed by `_fc_submodule_reference_
  # update()` (defined above `do_one_replay`) which loops submodule-BY-
  # submodule, computing and passing EACH submodule's own already-
  # fetched store under $repo_root's git-common-dir individually
  # (`git -C "$repo_root" rev-parse --git-common-dir` -- resolves
  # correctly even when $repo_root is itself a linked worktree, since
  # `--git-common-dir` always resolves to the shared repo, not a
  # per-worktree path) as that ONE submodule's `--reference` --
  # RECURSING into any submodule that itself declares its own
  # `.gitmodules` (a nested submodule) using $repo_root's OWN
  # already-checked-out copy of that submodule as the new reference
  # source, since a nested submodule's store lives at
  # `<parent-store>/modules/<nested-name>`, which `rev-parse
  # --git-common-dir` composes correctly from within that checked-out
  # directory (verified live against a real 2-level-nested scratch
  # fixture: 0 objects transferred at BOTH the top-level AND the nested
  # level). Degrades safely per submodule, independently, exactly as the
  # round-2 text claimed for its own (broken) form: a submodule
  # $repo_root has never fetched gets no `--reference` flag and falls
  # through to a normal network clone for THAT submodule only (verified
  # live, exit 0, unaffected); a submodule whose remote is genuinely
  # unreachable still correctly fails non-zero regardless of whether a
  # `--reference` was supplied (verified live: `--reference` never
  # removes the need to negotiate refs with the remote -- it only avoids
  # re-transferring objects the remote and the reference already
  # agree on), preserving the exact "refuse to run gate_cmd against a
  # partially-checked-out tree" semantics the caller below depends on.
  # `--reference` (not `--reference-if-able`) is deliberate: this git
  # version's `submodule update` does not recognise the `-if-able` form
  # at all (confirmed live: real exit 1, a usage error).
  export -f _fc_submodule_reference_update
  # the bash -c body is single-quoted on purpose: $1/$2 must expand in the child shell, not here
  # shellcheck disable=SC2016
  ( timeout --kill-after=5 "${timeout_s}s" \
      bash -c '_fc_submodule_reference_update "$1" "$2"' -- "$repo_root" "$wt_path" \
  ) >/dev/null 2>&1 &
  local submodule_pid=$!
  wait "$submodule_pid"
  local submodule_rc=$?
  if [ "$submodule_rc" -ne 0 ]; then
    echo "baseline_replay: BLIND: git submodule update --init --recursive failed (exit $submodule_rc$( [ "$submodule_rc" = 124 ] || [ "$submodule_rc" = 137 ] && echo ", timed out after ${timeout_s}s")) for commit $commit at $wt_path (a frozen submodule SHA may be absent from the local object store, or a network fetch stalled -- refusing to run gate_cmd against a partially-checked-out tree)" >&2
    return 4
  fi

  # T048 remediation (finding F9 continued): after the submodule fix above,
  # a SECOND, DISTINCT missing-prerequisite class was independently
  # reproduced for the "slow" items (ATM-610/611/627/277/SPK-609, 170-263s
  # elapsed vs. the "fast" CC83 class' 4-5s): a pre-build gate this project
  # runs can itself contain a "cmd; rc=$?" style SEQUENTIAL (`;`), not
  # errexit-exempt, inline sub-script invocation (contrast this SAME file's
  # own later "§11.4.1-safe live-run" harness check, which deliberately
  # uses the errexit-EXEMPT `if cmd; then rc=0; else rc=$?; fi` form
  # instead) whose sub-script is DESIGNED to exit 2 as an honest SKIP when
  # a single, project-defined, gitignored host-build prerequisite is
  # absent -- a tool git NEVER tracks and that a bare `git worktree add`
  # checkout therefore NEVER has, while this project's own long-lived,
  # repeatedly-built dev tree (the environment T045's cited "~18.9 min per
  # full run" evidence-block figure was measured against) has it sitting
  # around from a PRIOR build, since nothing in this project's normal
  # workflow ever `make clean`s host tools. So the SKIP=2 the isolated
  # worktree hits here is real to the worktree, but NOT representative of
  # the environment this gate's timing was ever measured or is meant to be
  # measured against. Rather than chasing every gate's own inline
  # sub-script sites for a similar gap (a full project-side audit found
  # this class affects exactly one such site; every OTHER inline
  # sub-script run in this file already uses the errexit-exempt `if`-form),
  # compile the ONE confirmed, cheap, self-contained, no-network host tool
  # this isolated worktree is missing -- IF the caller has named one via
  # the two `FC_REPLAY_HOSTTOOL_*` env vars below. §11.4.28(B): this
  # generic replay machinery takes any such project-specific prerequisite
  # as caller-supplied DATA, never a hardcoded literal path -- leaving
  # either env var unset makes this whole step an honest no-op. BOUNDED,
  # not a slippery slope toward replicating a full project build: this
  # project's own concrete instance names a single ~1575-line file, ~1s to
  # compile, verified independently (`cc -O2` on it exits 0, its own
  # `--help` runs, and the gate that needed it genuinely PASSes against it
  # afterward instead of SKIPping). A compile failure is treated exactly
  # like the worktree-add/submodule-update failures above -- an honest
  # BLIND (unmeasurable), never silently absorbed.
  local _rt_src="" _rt_bin=""
  if [ -n "${FC_REPLAY_HOSTTOOL_SRC:-}" ] && [ -n "${FC_REPLAY_HOSTTOOL_BIN:-}" ]; then
    _rt_src="$wt_path/${FC_REPLAY_HOSTTOOL_SRC}"
    _rt_bin="$wt_path/${FC_REPLAY_HOSTTOOL_BIN}"
  fi
  if [ -n "$_rt_src" ] && [ -f "$_rt_src" ] && [ ! -x "$_rt_bin" ]; then
    # Security remediation (T048 review, 2026-09-29): symlink-follow-write
    # guard. $wt_path is a disposable `git worktree add --detach` checkout
    # of $commit (an arbitrary, possibly-historical commit from this
    # repo's own local history -- see the submodule-fetch comment above
    # for why $commit itself is never unvalidated external input, though
    # its TREE CONTENT is still only as trustworthy as this repo's own
    # history). Git tracks symlinks as ordinary blobs (mode 120000), so
    # nothing here prevents SOME commit in that history from having
    # checked out the configured host-tool's containing directory (or the
    # source/binary leaf entries themselves) as a symlink pointing OUTSIDE
    # this worktree -- `cc -O2 -o "$_rt_bin" "$_rt_src"` would then
    # transparently follow that symlink and CREATE or OVERWRITE an
    # attacker-chosen file anywhere the invoking user can write, driven
    # entirely by tree content this script never authored. Refuse (BLIND)
    # rather than follow: canonicalize the source file's containing
    # directory with `pwd -P` (resolves every symlink component, unlike a
    # plain path-string prefix check) and verify the RESULT still lives
    # strictly inside $wt_path's own canonical path before compiling
    # anything; independently also refuse if either the source or the
    # binary path itself is a symlink LEAF (a legitimate directory
    # containing a symlinked single file, which the directory-containment
    # check alone would not catch).
    local _rt_dir _rt_dir_real wt_path_real
    _rt_dir="$(dirname "$_rt_src")"
    _rt_dir_real="$(cd "$_rt_dir" 2>/dev/null && pwd -P)"
    wt_path_real="$(cd "$wt_path" 2>/dev/null && pwd -P)"
    if [ -z "$_rt_dir_real" ] || [ -z "$wt_path_real" ] || \
       { [ "$_rt_dir_real" != "$wt_path_real" ] && \
         [ "${_rt_dir_real#"$wt_path_real"/}" = "$_rt_dir_real" ]; } || \
       [ -L "$_rt_src" ] || [ -L "$_rt_bin" ]; then
      echo "baseline_replay: BLIND: configured host-tool path (FC_REPLAY_HOSTTOOL_SRC=${FC_REPLAY_HOSTTOOL_SRC}, FC_REPLAY_HOSTTOOL_BIN=${FC_REPLAY_HOSTTOOL_BIN}) resolves OUTSIDE the isolated worktree (worktree is ${wt_path_real:-$wt_path}) for commit $commit -- refusing to compile through what appears to be a git-tracked symlink escaping the disposable checkout, which could otherwise write an attacker-chosen file anywhere the invoking user can write" >&2
      return 4
    fi
    if ! cc -O2 -o "$_rt_bin" "$_rt_src" >/dev/null 2>&1; then
      echo "baseline_replay: BLIND: host-tool compile failed for $_rt_src at $wt_path (FC_REPLAY_HOSTTOOL_SRC names a gitignored host-build prerequisite the caller's gate_cmd needs; without it, that gate's own inline sub-run can crash the whole gate under set -e via an honest exit-2 SKIP the wrapper cannot safely capture)" >&2
      return 4
    fi
  fi

  # T048 remediation (finding F9 continued -- the output-discarding
  # hardening asked for independently of the root cause fix above): the
  # gate-cmd's combined stdout+stderr used to go straight to `/dev/null`
  # (a prior version of this line), so a future crash/hang/unexpected
  # nonzero exit had NO captured evidence to diagnose from without
  # re-running the whole (multi-minute) replay by hand -- exactly the gap
  # that made THIS finding (F9) itself slow to root-cause. Every run now
  # gets its own real, persistent log file under $worktree_root (a
  # sibling of $wt_path, so `cleanup()` -- which only removes $wt_path --
  # never touches it), named uniquely per commit+phase+run_index so
  # concurrent/successive do_one_replay calls for different items (e.g.
  # cmd_replay_sample's per-item loop) can never collide or overwrite one
  # another's evidence. The path is recorded in each run's own JSON row
  # (captured-evidence citation per §11.4.5) so a FAIL/UNMEASURED verdict
  # is diagnosable from the frozen report alone, without a re-run.
  local run_log_dir="$worktree_root/replay-logs"
  mkdir -p "$run_log_dir" 2>/dev/null || { echo "baseline_replay: cannot create run-log directory $run_log_dir" >&2; return 4; }
  local commit_short="${commit:0:12}"

  local rows='[]'
  local phase run_idx start_ns end_ns rc timed_out duration_ms verdict run_log
  for phase in cold warm; do
    local n_runs
    if [ "$phase" = cold ]; then n_runs="$cold_runs"; else n_runs="$warm_runs"; fi
    run_idx=1
    while [ "$run_idx" -le "$n_runs" ]; do
      start_ns="$(now_ns)" || return 4
      timed_out=0
      # T043 round-4 finding B1 continued: a plain FOREGROUND subshell
      # here (no trailing `&` + explicit `wait`) makes bash DEFER any
      # trapped signal -- including the `trap 'exit 129' HUP` registered
      # above -- until this WHOLE foreground command finishes (documented
      # bash behavior: "If bash is waiting for a command to complete and
      # receives a signal for which a trap has been set, the trap will
      # not be executed until the command completes"). That defers
      # cleanup past the gate-cmd's own natural end, which -- for a
      # SIGHUP-causing event like an SSH disconnect or a dying tmux
      # server -- the parent process is unlikely to survive to see;
      # independently reproduced: the gate-cmd's OWN process dies from
      # SIGHUP's default disposition (not trapped there), the foreground
      # wait unblocks, but the worktree still leaks because the ORIGINAL
      # repro path (kill sent to the process group at t+1.5s of a t+5s
      # gate-cmd) verified this genuinely happens. Fixed by BACKGROUNDING
      # the gate-cmd subshell and using the `wait` BUILTIN explicitly --
      # per POSIX, `wait` on a specific job returns immediately when a
      # trapped signal is delivered, so the pending HUP trap runs
      # (converting to `exit 129`, firing the EXIT-trap cleanup)
      # WITHOUT waiting for the gate-cmd to finish on its own.
      run_log="$run_log_dir/${commit_short}_${phase}_${run_idx}.log"
      ( cd "$wt_path" && timeout --kill-after=5 "${timeout_s}s" "${gate_cmd[@]}" ) >"$run_log" 2>&1 &
      local gate_pid=$!
      wait "$gate_pid"
      rc=$?
      if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then timed_out=1; fi
      end_ns="$(now_ns)" || return 4
      duration_ms=$(( (end_ns - start_ns) / 1000000 ))
      [ "$duration_ms" -ge 0 ] || duration_ms=0
      verdict="$(classify_verdict "$rc" "$timed_out")"
      rows="$(python3 -c "
import json, sys
rows = json.loads(sys.argv[1])
rows.append({'phase': sys.argv[2], 'run_index': int(sys.argv[3]), 'start_ns': int(sys.argv[4]),
             'end_ns': int(sys.argv[5]), 'duration_ms': int(sys.argv[6]), 'exit_code': int(sys.argv[7]),
             'verdict': sys.argv[8], 'log_path': sys.argv[9]})
print(json.dumps(rows))
" "$rows" "$phase" "$run_idx" "$start_ns" "$end_ns" "$duration_ms" "$rc" "$verdict" "$run_log")"
      run_idx=$((run_idx + 1))
    done
  done

  cleanup "$repo_root" "$wt_path"
  trap - EXIT

  python3 -c "
import json, statistics
rows = json.loads('''$rows''')
def medians():
    out = {}
    for phase in ('cold', 'warm'):
        vals = [r['duration_ms'] for r in rows if r['phase'] == phase and r['verdict'] != 'UNMEASURED']
        out[phase] = int(round(statistics.median(vals))) if vals else 'UNMEASURED'
    return out
def verdict_sets():
    out = {}
    for phase in ('cold', 'warm'):
        out[phase] = sorted(set(r['verdict'] for r in rows if r['phase'] == phase))
    return out
print(json.dumps({
    'commit': '$commit', 'tree': '$actual_tree', 'gate_cmd': $(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" "${gate_cmd[@]}"),
    'cold_runs': $cold_runs, 'warm_runs': $warm_runs,
    'cache_mechanism': 'none (T068 verdict_cache.py not landed in this tree, verified 2026-09-28)',
    'runs': rows, 'median_ms': medians(), 'verdict_set': verdict_sets(),
}))
"
}

# =============================================================================
# replay
# =============================================================================
cmd_replay() {
  local commit="" tree="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb=10485760 timeout_s=1800 out=""
  local determinism_check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --commit) commit="$2"; shift 2 ;;
      --tree) tree="$2"; shift 2 ;;
      --gate-cmd) gate_cmd_str="$2"; shift 2 ;;
      --cold-runs) cold_runs="$2"; shift 2 ;;
      --warm-runs) warm_runs="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --worktree-root) worktree_root="$2"; shift 2 ;;
      --min-free-kb) min_free_kb="$2"; shift 2 ;;
      --timeout-s) timeout_s="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --determinism-check) determinism_check=1; shift ;;
      *) die "replay: unknown argument: $1" ;;
    esac
  done
  [ -n "$commit" ] || die "replay: --commit is required"
  [ -n "$gate_cmd_str" ] || die "replay: --gate-cmd is required"
  [ -n "$out" ] || die "replay: --out is required"
  isnum "$cold_runs" || die "replay: --cold-runs must be a non-negative integer"
  isnum "$warm_runs" || die "replay: --warm-runs must be a non-negative integer"
  isnum "$min_free_kb" || die "replay: --min-free-kb must be a non-negative integer"
  isnum "$timeout_s" || die "replay: --timeout-s must be a positive integer"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a RELATIVE --worktree-root resolves against the CALLER's cwd for
  # mktemp/rev-parse/df/the gate's own `cd`, but against $repo_root for
  # `git -C "$repo_root" worktree add` -- two different base directories
  # for the SAME value, silently pointing at two different locations.
  # Reproduced: from a cwd other than the repo, a relative
  # --worktree-root with --tree omitted produced exit 0 + a false
  # "cold":["FAIL"] verdict without the gate ever running against the
  # real checkout -- a §11.4.1 FAIL-bluff in a measurement tool. Fixed
  # the SAME way repo_root already is, two lines up: resolve to an
  # absolute, canonical path up front so every later consumer (mktemp,
  # df, git -C, the gate's cd) agrees on the SAME directory, closing the
  # root cause for the --tree-provided case too (caught by luck there
  # via the tree-mismatch check, not by design).
  mkdir -p "$worktree_root" 2>/dev/null || die "replay: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay: cannot resolve --worktree-root $worktree_root to an absolute path"

  run_selfcheck || return 3

  if [ "$determinism_check" = 1 ]; then
    # HONEST BOUNDARY / DESIGN FIX (S11.4.6, found by directly running the
    # naive design against a real scratch repo before shipping it):
    # `replay`'s report embeds REAL wall-clock timestamps
    # (start_ns/end_ns/duration_ms/median_ms) in its hashed body -- that
    # data is INHERENTLY non-deterministic between two separate
    # invocations (real timing jitter), so delegating to fc_common.py's
    # generic byte-identical-body_hash `determinism-check` (the pattern
    # cycle_report.py/select_sample.py both use, correctly, for their own
    # timing-free bodies) ALWAYS reports "nondeterministic" here, even
    # when nothing is actually wrong -- verified directly: it did, on the
    # very first real run against a real scratch repo, 2026-09-28. T024's
    # own RED-test contract stub 1/3 says what THIS tool's determinism
    # actually means: "two independent invocations ... MUST produce the
    # SAME verdict SET (per-item PASS/FAIL/SKIP classification, compared
    # as a set, never merely as equal counts)" -- so this flag runs
    # `do_one_replay` TWICE directly and compares ONLY `verdict_set`
    # (never the timing fields) between the two runs.
    local body1 body2
    # word-split --gate-cmd intentionally (see HONEST BOUNDARY note above the
    # header's DETERMINISM section).
    # shellcheck disable=SC2086
    body1="$(do_one_replay "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
      "$timeout_s" "$cold_runs" "$warm_runs" $gate_cmd_str)" || return 4
    # shellcheck disable=SC2086
    body2="$(do_one_replay "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
      "$timeout_s" "$cold_runs" "$warm_runs" $gate_cmd_str)" || return 4
    # `--out` is REQUIRED by this subcommand's own arg parsing above
    # (`[ -n "$out" ] || die ...`) in EVERY mode, including
    # --determinism-check -- but this branch, until T043 round-2 review
    # finding N5, only ever printed the determinism result to stdout and
    # silently never wrote it to $out, contradicting its own documented
    # contract. Fixed: capture the result body + its own exit code (a
    # command substitution preserves the substituted command's exit
    # status in $?, read immediately below, before anything else can
    # clobber it), still print it (matching the DETERMINISM section's own
    # documented "printing both verdict sets either way"), AND now also
    # persist it to $out via the same emit_doc envelope every other
    # subcommand uses -- but return the DETERMINISM verdict's own exit
    # code (0=same, 1=differs), never emit_doc's.
    local det_body det_rc emit_rc
    det_body="$(python3 -c "
import json, sys
b1, b2 = json.loads(sys.argv[1]), json.loads(sys.argv[2])
vs1, vs2 = b1['verdict_set'], b2['verdict_set']
same = all(set(vs1.get(p, [])) == set(vs2.get(p, [])) for p in ('cold', 'warm'))
print(json.dumps({'run1_verdict_set': vs1, 'run2_verdict_set': vs2, 'deterministic': same}))
sys.exit(0 if same else 1)
" "$body1" "$body2")"
    det_rc=$?
    echo "$det_body"
    # T043 round-3 review finding F3(c): every OTHER subcommand in this file
    # lets `emit_doc`'s own exit code become its function's exit code
    # implicitly (emit_doc is their LAST statement, no explicit `return`
    # after it) -- so a --out write failure is already surfaced everywhere
    # else. This branch is the one exception (it explicitly overrides with
    # `return $det_rc` per its own documented design: the DETERMINISM
    # comparison's own same/differs verdict is the primary semantic
    # signal, not emit_doc's plumbing). Silently discarding emit_doc's
    # failure entirely would still be wrong, though -- fixed to check it:
    # a write failure is ALWAYS surfaced audibly on stderr (never silent),
    # and additionally escalates the exit code when det_rc alone would
    # otherwise have reported success (0) -- a caller must never see exit 0
    # when the mandatory --out contract was not actually honored.
    emit_doc "baseline-replay-determinism/v1" "$det_body" "$out"
    emit_rc=$?
    if [ "$emit_rc" != 0 ]; then
      echo "baseline_replay: WARNING: writing the --determinism-check result to --out ($out) failed (emit_doc exit $emit_rc) -- the determinism verdict printed above is still accurate, but the mandatory --out contract was not honored" >&2
      if [ "$det_rc" = 0 ]; then
        return 4
      fi
    fi
    return $det_rc
  fi

  local body
  # word-split --gate-cmd intentionally (shell command string, matching
  # host_guard.sh's own convention of accepting a single quoted invocation).
  # shellcheck disable=SC2086
  body="$(do_one_replay "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
    "$timeout_s" "$cold_runs" "$warm_runs" $gate_cmd_str)" || return 4

  emit_doc "baseline-replay/v1" "$body" "$out"
}

# =============================================================================
# replay-sample
# =============================================================================
cmd_replay_sample() {
  local sample="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb=10485760 timeout_s=1800 out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sample) sample="$2"; shift 2 ;;
      --gate-cmd) gate_cmd_str="$2"; shift 2 ;;
      --cold-runs) cold_runs="$2"; shift 2 ;;
      --warm-runs) warm_runs="$2"; shift 2 ;;
      --repo-root) repo_root="$2"; shift 2 ;;
      --worktree-root) worktree_root="$2"; shift 2 ;;
      --min-free-kb) min_free_kb="$2"; shift 2 ;;
      --timeout-s) timeout_s="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      *) die "replay-sample: unknown argument: $1" ;;
    esac
  done
  [ -n "$sample" ] || die "replay-sample: --sample is required"
  [ -n "$gate_cmd_str" ] || die "replay-sample: --gate-cmd is required"
  [ -n "$out" ] || die "replay-sample: --out is required"
  [ -f "$sample" ] || blind "--sample file not found: $sample"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a RELATIVE --worktree-root resolves against the CALLER's cwd for
  # mktemp/rev-parse/df/the gate's own `cd`, but against $repo_root for
  # `git -C "$repo_root" worktree add` -- two different base directories
  # for the SAME value, silently pointing at two different locations.
  # Reproduced: from a cwd other than the repo, a relative
  # --worktree-root with --tree omitted produced exit 0 + a false
  # "cold":["FAIL"] verdict without the gate ever running against the
  # real checkout -- a §11.4.1 FAIL-bluff in a measurement tool. Fixed
  # the SAME way repo_root already is, two lines up: resolve to an
  # absolute, canonical path up front so every later consumer (mktemp,
  # df, git -C, the gate's cd) agrees on the SAME directory, closing the
  # root cause for the --tree-provided case too (caught by luck there
  # via the tree-mismatch check, not by design).
  mkdir -p "$worktree_root" 2>/dev/null || die "replay: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay: cannot resolve --worktree-root $worktree_root to an absolute path"

  run_selfcheck || return 3

  local item_ids
  item_ids="$(python3 -c "
import json
doc = json.load(open('$sample'))
for it in doc.get('items', []):
    print(it['item_id'])
")" || blind "--sample is not a readable select_sample.py output doc"

  local items_json='[]'
  local item_id
  while IFS= read -r item_id; do
    [ -n "$item_id" ] || continue
    local freeze_out
    freeze_out="$(mktemp)"
    cmd_freeze --item "$item_id" --repo-root "$repo_root" --out "$freeze_out"
    local freeze_rc=$?
    local entry
    if [ "$freeze_rc" != 0 ]; then
      entry="$(python3 -c "import json; print(json.dumps({'item_id': '$item_id', 'skipped': True, 'skip_reason': 'freeze harness error rc=$freeze_rc'}))")"
    else
      local commit tree
      commit="$(python3 -c "import json; print(json.load(open('$freeze_out'))['commit'])")"
      tree="$(python3 -c "import json; print(json.load(open('$freeze_out'))['tree'])")"
      if [ "$commit" = UNMEASURED ]; then
        entry="$(python3 -c "import json; print(json.dumps({'item_id': '$item_id', 'skipped': True, 'skip_reason': 'freeze UNMEASURED (no subject-matching commit found)'}))")"
      else
        local replay_out
        replay_out="$(mktemp)"
        local rbody
        # word-split --gate-cmd intentionally (see cmd_replay's own comment
        # on this pattern -- HONEST BOUNDARY: --gate-cmd must not itself
        # contain an argument with embedded whitespace).
        # shellcheck disable=SC2086
        rbody="$(do_one_replay "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
          "$timeout_s" "$cold_runs" "$warm_runs" $gate_cmd_str)"
        local replay_rc=$?
        if [ "$replay_rc" != 0 ]; then
          entry="$(python3 -c "import json; print(json.dumps({'item_id': '$item_id', 'commit': '$commit', 'tree': '$tree', 'skipped': True, 'skip_reason': 'replay harness error rc=$replay_rc'}))")"
        else
          entry="$(python3 -c "
import json
rbody = json.loads('''$rbody''')
print(json.dumps({'item_id': '$item_id', 'skipped': False, 'skip_reason': None,
                   'commit': rbody['commit'], 'tree': rbody['tree'],
                   'median_ms': rbody['median_ms'], 'verdict_set': rbody['verdict_set']}))
")"
        fi
        rm -f "$replay_out"
      fi
    fi
    rm -f "$freeze_out"
    items_json="$(python3 -c "
import json, sys
items = json.loads(sys.argv[1])
items.append(json.loads(sys.argv[2]))
print(json.dumps(items))
" "$items_json" "$entry")"
  done <<<"$item_ids"

  local body
  # word-split --gate-cmd intentionally (see cmd_replay's HONEST BOUNDARY note).
  # shellcheck disable=SC2086
  body="$(python3 -c "
import json
print(json.dumps({
    'sample_path': '$sample', 'gate_cmd': $(python3 -c "import json,sys; print(json.dumps(sys.argv[1:]))" $gate_cmd_str),
    'cold_runs': $cold_runs, 'warm_runs': $warm_runs, 'items': json.loads('''$items_json'''),
}))
")"
  emit_doc "baseline-replay-sample/v1" "$body" "$out"
}

case "$SUBCMD" in
  freeze) cmd_freeze "$@"; exit $? ;;
  selfcheck) cmd_selfcheck "$@"; exit $? ;;
  replay) cmd_replay "$@"; exit $? ;;
  replay-sample) cmd_replay_sample "$@"; exit $? ;;
  *) usage ;;
esac
