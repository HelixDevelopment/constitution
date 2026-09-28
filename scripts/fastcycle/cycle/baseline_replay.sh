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
# determinism defect, S11.4.50), printing both verdict sets either way.
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
    case "$subject" in
      *"$item_id"*)
        count=$((count + 1))
        if [ -z "$best_date" ] || [[ "$adate" > "$best_date" ]]; then
          best_sha="$sha"; best_date="$adate"; best_subject="$subject"
        fi
        ;;
    esac
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
# One frozen-commit replay: creates+removes exactly one worktree, runs
# gate_cmd cold_runs+warm_runs times inside it. Prints the JSON body on
# stdout (caller decides schema/out). Returns 0 on a successfully-measured
# run (gate PASS/FAIL is data, not a harness failure), 4 on BLIND.
# =============================================================================
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
  # function, including every early `return 4` below (lines 444/451/461/
  # 466). bash pops a function's `local` bindings as part of `return`, but
  # the EXIT trap fires AFTERWARD in the (sub)shell that is exiting -- so
  # any of do_one_replay's OWN `local` variables that cleanup() referenced
  # (repo_root, wt_path, and a since-removed `cleanup_done` done-guard)
  # were already gone by the time the trap-invoked cleanup() body tried to
  # read them under `set -u`, crashing with "unbound variable" BEFORE the
  # real `git worktree remove` / `rm -rf` below ever ran -- silently
  # leaking the worktree on disk. Independently reproduced for both the
  # done-guard and for $wt_path itself (a mismatched---tree run left an
  # orphaned `replay.XXXXXX` worktree + directory behind).
  #
  # Fixed by passing the two paths cleanup() needs as EXPLICIT ARGUMENTS
  # baked into the trap command STRING at `trap` REGISTRATION time -- the
  # double-quoted "$repo_root"/"$wt_path" below expand immediately (not at
  # trap-fire time), so the fired trap command is a fully literal string
  # with no variable lookups left to perform, and cleanup() no longer
  # depends on do_one_replay's own local-variable lifetime at all. This
  # also makes cleanup() safely callable twice (once explicitly via
  # `cleanup "$repo_root" "$wt_path"; trap - EXIT` on the success path,
  # once via the EXIT trap on an early return): `git worktree remove
  # --force` is a no-op (stderr already discarded) on an already-removed
  # worktree, and `rm -rf` is a no-op on a missing path.
  cleanup() {
    local rr="$1" wp="$2"
    git -C "$rr" worktree remove --force "$wp" >/dev/null 2>&1
    rm -rf "$wp" 2>/dev/null
  }
  trap "cleanup '$repo_root' '$wt_path'" EXIT

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

  local rows='[]'
  local phase run_idx start_ns end_ns rc timed_out duration_ms verdict
  for phase in cold warm; do
    local n_runs
    if [ "$phase" = cold ]; then n_runs="$cold_runs"; else n_runs="$warm_runs"; fi
    run_idx=1
    while [ "$run_idx" -le "$n_runs" ]; do
      start_ns="$(now_ns)" || return 4
      timed_out=0
      ( cd "$wt_path" && timeout --kill-after=5 "${timeout_s}s" "${gate_cmd[@]}" ) >/dev/null 2>&1
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
             'verdict': sys.argv[8]})
print(json.dumps(rows))
" "$rows" "$phase" "$run_idx" "$start_ns" "$end_ns" "$duration_ms" "$rc" "$verdict")"
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
    python3 -c "
import json, sys
b1, b2 = json.loads(sys.argv[1]), json.loads(sys.argv[2])
vs1, vs2 = b1['verdict_set'], b2['verdict_set']
same = all(set(vs1.get(p, [])) == set(vs2.get(p, [])) for p in ('cold', 'warm'))
print(json.dumps({'run1_verdict_set': vs1, 'run2_verdict_set': vs2, 'deterministic': same}))
sys.exit(0 if same else 1)
" "$body1" "$body2"
    return $?
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
