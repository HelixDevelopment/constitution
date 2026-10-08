#!/bin/bash
# Purpose : T016/T030 (SpecKit-004 "fast-dev-cycles", US1, plan.md T-A02) -- behavioural proof
#           that scripts/commit_all.sh emits one fc_timer row per EXECUTED commit-path stage,
#           one per-remote push row carrying a real read-back tip, a row for every stage that
#           ABORTS, and that the instrumentation never changes what gets committed.
#
# T048 restart round-1 rewrite (2026-10-08, findings R1-B1 instance 2, R1-I2, R1-I3, R1-I4,
# R1-m5..m11). The previous revision of this file never ran commit_all.sh: it grepped the
# source for `fc_timer_(start|end)` (satisfied by the wrapper DEFINITIONS alone) and counted
# rows in the lexically-latest TSV of the SHARED cross-track qa-results/fastcycle/commit/ dir
# (any run, any stage, any process) -- evidence bound to the wrong run. The reviewer's
# mutation MA (every stage frame stripped) and MB (detached push writes no per-remote rows)
# both left it GREEN, and its golden-output check was a static text-span heuristic that
# mutation MG (timer path rewrites COMMIT_MESSAGE + stages a marker file) also survived.
#
# What it does now (every assertion runs the REAL commit_all.sh through its real CLI):
#   - builds a hermetic scratch project per scenario: its own git repo, three remote NAMES
#     pointing at one local bare repo (the shape this repo documents), byte copies of the
#     real scripts/commit_all.sh, scripts/lib/common.sh, scripts/push_all.sh and the real
#     constitution fc_timer.sh -- no network, no write to the live checkout;
#   - PINS the run id (FC_TIMER_RUN_ID) for every run and reads exactly that run's own
#     qa-results/fastcycle/commit/<run_id>.tsv inside the scratch project (never a "latest"
#     file, never a shared directory);
#   - asserts per-stage ids, run_id/fingerprint columns, push tips against the real new HEAD,
#     aborted-stage rows on refusal/failure paths, no FC_TIMER_* leak into git hooks, no row
#     written by a COMMIT_ALL_SOURCE_ONLY harness, and that FC_TIMING=1 and FC_TIMING=0 commit
#     the identical tree + message, which is itself exactly the fixture's change + the -m text.
#
# Usage   : bash test_fc_commit_stage_timer_red.sh        (exit 0 = all pass, 1 = any FAIL)
#           FC_COMMIT_STAGE_COMMIT_ALL=<path> -- run against another commit_all.sh (the paired
#           mutation runner test_fc_commit_stage_timer_mutations.sh uses this; default: the
#           real scripts/commit_all.sh of this checkout).
# Runtime : ~2 minutes (each commit_all.sh preflight is ~10 s); no network.
# Safety  : only scratch repos under mktemp are written; the live tree, its remotes and its
#           qa-results/ are never touched.
# ok()/bad() are print-only reporters that always return 0, so `cond && ok .. || bad ..` never
# mis-fires the || branch.
# shellcheck disable=SC2015
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
REAL_COMMIT_ALL="${FC_COMMIT_STAGE_COMMIT_ALL:-$ROOT/scripts/commit_all.sh}"
REAL_COMMON="$ROOT/scripts/lib/common.sh"
REAL_PUSH_ALL="$ROOT/scripts/push_all.sh"
REAL_FC_TIMER="$ROOT/constitution/scripts/fastcycle/timing/fc_timer.sh"

fail=0
ok()  { echo "ok   $1"; }
bad() { echo "NOT ok $1"; fail=1; }

for f in "$REAL_COMMIT_ALL" "$REAL_COMMON" "$REAL_PUSH_ALL" "$REAL_FC_TIMER"; do
  [ -f "$f" ] || { echo "NOT ok control needle: required input missing: $f"; exit 1; }
done
ok "control needle: commit_all.sh, lib/common.sh, push_all.sh and fc_timer.sh all resolve"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fc_commit_stage.XXXXXX")" || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT
CO_TRAILER="Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# scratch <name> -- a hermetic project at $TMP/<name>/proj with remotes github/origin/upstream
# -> one local bare repo, an initial commit already pushed, and one pending change (b.txt).
scratch() {
  local d="$TMP/$1"
  mkdir -p "$d"
  git init -q --bare "$d/remote.git"
  mkdir -p "$d/proj/scripts/lib" "$d/proj/constitution/scripts/fastcycle/timing"
  cp -- "$REAL_COMMIT_ALL" "$d/proj/scripts/commit_all.sh"
  cp -- "$REAL_COMMON" "$d/proj/scripts/lib/common.sh"
  cp -- "$REAL_PUSH_ALL" "$d/proj/scripts/push_all.sh"
  chmod +x "$d/proj/scripts/commit_all.sh" "$d/proj/scripts/push_all.sh"
  cp -- "$REAL_FC_TIMER" "$d/proj/constitution/scripts/fastcycle/timing/fc_timer.sh"
  (
    cd "$d/proj" || exit 1
    git init -q -b main
    git config user.email t@example.invalid; git config user.name fc-test
    for r in github origin upstream; do git remote add "$r" "$d/remote.git"; done
    printf 'qa-results/\n' > .gitignore
    echo a > a.txt
    git add -A && git commit -qm init && git push -q origin main 2>/dev/null
    echo b > b.txt
  ) || return 1
  echo "$d/proj"
}

# run_ca <proj> <run_id> <args...> -- the real commit_all.sh CLI, pinned run id, output to
# <proj>/../ca.out; echoes the exit status.
run_ca() {
  local p="$1" rid="$2"; shift 2
  ( cd "$p" && FC_TIMER_RUN_ID="$rid" SKIP_COMPRESS=true COMMIT_ALL_CASCADE=false \
      timeout 180 bash scripts/commit_all.sh --continuation-no-update-needed "fc stage timer test" "$@" \
      > "$p/../ca.out" 2>&1 < /dev/null )
  echo "$?"
}

tsv_of() { echo "$1/qa-results/fastcycle/commit/$2.tsv"; }
ids_of() { [ -f "$1" ] && awk -F'\t' 'NR>1 {print $3}' "$1"; }
count_id() { [ -f "$1" ] && awk -F'\t' -v w="$2" 'NR>1 && $3==w {n++} END {print n+0}' "$1" || echo 0; }
field_of() { awk -F'\t' -v w="$2" -v c="$3" 'NR>1 && $3==w {print $c; exit}' "$1" 2>/dev/null; }
all_col_eq() {  # <tsv> <col> <value> -> 1 iff >=1 data row and every row's <col> == <value>
  awk -F'\t' -v c="$2" -v v="$3" 'NR>1 {n++; if ($c != v) bad=1} END {print (n>0 && !bad) ? 1 : 0}' "$1" 2>/dev/null || echo 0
}
wait_for_id() {  # <tsv> <id> <seconds>
  local i=0
  while [ "$i" -lt "$3" ]; do
    [ "$(count_id "$1" "$2")" -ge 1 ] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

echo "=== A: --dry-run -> one row per EXECUTED stage, bound to the pinned run (R1-B1 inst. 2) ==="
P="$(scratch A)"; RID="t016_dry_$$"; HEAD0="$(git -C "$P" rev-parse HEAD)"
rc="$(run_ca "$P" "$RID" --dry-run -m "dry msg")"; T="$(tsv_of "$P" "$RID")"
if [ "$rc" = 0 ] && [ -f "$T" ]; then ok "A: dry-run rc=0 and its own pinned TSV exists"; else bad "A: rc=$rc tsv=$T $(tail -n3 "$P/../ca.out")"; fi
a_ok=1
for s in preflight stage state_sync_seam commit; do [ "$(count_id "$T" "$s")" = 1 ] || a_ok=0; done
[ "$a_ok" = 1 ] && ok "A: preflight/stage/state_sync_seam/commit each have exactly one row" \
  || bad "A: executed-stage rows wrong; ids present: $(ids_of "$T" | tr '\n' ' ')"
[ "$(count_id "$T" push:github)" = 0 ] && ok "A: a dry-run without --sync-push writes no push row (that stage never ran)" \
  || bad "A: push row present for a dry-run that never pushed"
[ "$(all_col_eq "$T" 1 "$RID")" = 1 ] && [ "$(all_col_eq "$T" 2 "$HEAD0")" = 1 ] \
  && ok "A: every row carries the pinned run id and the pre-run HEAD fingerprint" \
  || bad "A: run_id/fingerprint columns not bound to this run"
[ "$(find "$P/qa-results/fastcycle/commit" -name '*.tsv' | wc -l)" = 1 ] \
  && ok "A: exactly one commit TSV exists (this run's; nothing else wrote one)" || bad "A: stray commit TSVs: $(ls "$P/qa-results/fastcycle/commit")"

echo "=== B: real commit + DEFAULT detached push -> per-remote rows with read-back tips (R1-I3) ==="
P="$(scratch B)"; RID="t016_full_$$"; HEAD0="$(git -C "$P" rev-parse HEAD)"
# m7: a pre-commit hook records any FC_TIMER_* variable it inherits (must be none).
printf '#!/bin/sh\nenv | grep "^FC_TIMER_" > "%s" || true\nexit 0\n' "$P/../hook_env.txt" > "$P/.git/hooks/pre-commit"
chmod +x "$P/.git/hooks/pre-commit"
rc="$(run_ca "$P" "$RID" -m "full msg")"; T="$(tsv_of "$P" "$RID")"
HEAD1="$(git -C "$P" rev-parse HEAD)"
[ "$rc" = 0 ] && [ "$HEAD1" != "$HEAD0" ] && ok "B: commit_all.sh rc=0 and HEAD advanced" || bad "B: rc=$rc $(tail -n3 "$P/../ca.out")"
b_ok=1
for s in preflight lock:index stage state_sync_seam sibling_check commit; do [ "$(count_id "$T" "$s")" = 1 ] || b_ok=0; done
[ "$b_ok" = 1 ] && ok "B: preflight/lock:index/stage/state_sync_seam/sibling_check/commit each have exactly one row" \
  || bad "B: parent stage rows wrong; ids: $(ids_of "$T" | tr '\n' ' ')"
if wait_for_id "$T" push:upstream 90; then
  b2=1
  for r in github origin upstream; do
    [ "$(count_id "$T" "push:$r")" = 1 ] || b2=0
    ex="$(field_of "$T" "push:$r" 11)"
    case "$ex" in "remote=$r;tip=$HEAD1;result=ok"*) : ;; *) b2=0 ;; esac
  done
  [ "$(count_id "$T" push:call_push_all)" = 1 ] || b2=0
  [ "$b2" = 1 ] && ok "B: the detached push child wrote push:call_push_all + one push:<remote> row per remote NAME, each tip == the new HEAD $HEAD1" \
    || bad "B: detached per-remote rows wrong: $(awk -F'\t' 'NR>1 && $3 ~ /^push:/ {print $3"|"$11}' "$T" | tr '\n' ' ')"
else
  bad "B: the default (detached) push path never wrote a push:upstream row within 90s"
fi
[ "$(all_col_eq "$T" 1 "$RID")" = 1 ] && [ "$(all_col_eq "$T" 2 "$HEAD0")" = 1 ] \
  && ok "B: parent AND detached-child rows all carry the pinned run id + the pre-commit fingerprint" \
  || bad "B: rows not all bound to run $RID / fingerprint $HEAD0"
[ -f "$P/../hook_env.txt" ] && [ ! -s "$P/../hook_env.txt" ] \
  && ok "B (m7): the git pre-commit hook inherited NO FC_TIMER_* variable from commit_all.sh" \
  || bad "B (m7): FC_TIMER_* leaked into a descendant hook: $(tr '\n' ' ' < "$P/../hook_env.txt" 2>/dev/null)"

echo "=== C: golden output -- timers never change what is committed (R1-I4) ==="
P1="$(scratch C1)"; P0="$(scratch C0)"
rc1="$(cd "$P1" && FC_TIMING=1 run_ca "$P1" "t016_g1_$$" -m "golden msg")"
rc0="$(cd "$P0" && FC_TIMING=0 run_ca "$P0" "t016_g0_$$" -m "golden msg")"
NS1="$(git -C "$P1" show --name-status --format= HEAD)"; NS0="$(git -C "$P0" show --name-status --format= HEAD)"
MS1="$(git -C "$P1" log -1 --format=%B)"; MS0="$(git -C "$P0" log -1 --format=%B)"
TR1="$(git -C "$P1" rev-parse 'HEAD^{tree}')"; TR0="$(git -C "$P0" rev-parse 'HEAD^{tree}')"
WANT_MSG="$(printf 'golden msg\n\n%s' "$CO_TRAILER")"
[ "$rc1" = 0 ] && [ "$rc0" = 0 ] && ok "C: FC_TIMING=1 and FC_TIMING=0 runs both rc=0" || bad "C: rc1=$rc1 rc0=$rc0"
[ "$TR1" = "$TR0" ] && [ "$NS1" = "$NS0" ] && [ "$MS1" = "$MS0" ] \
  && ok "C: identical committed tree ($TR1), file set and message with timers ON vs OFF" \
  || bad "C: timers changed the commit: tree $TR1 vs $TR0; files [$NS1] vs [$NS0]; msg [$MS1] vs [$MS0]"
[ "$NS1" = "$(printf 'A\tb.txt')" ] && [ "$MS1" = "$WANT_MSG" ] \
  && ok "C: the commit is EXACTLY the fixture's change (A b.txt) + the -m text and trailer -- nothing added by any wrapper" \
  || bad "C: unexpected commit content: files [$NS1] msg [$MS1]"
[ ! -e "$(tsv_of "$P0" "t016_g0_$$")" ] && [ -f "$(tsv_of "$P1" "t016_g1_$$")" ] \
  && ok "C: FC_TIMING=0 wrote no TSV; FC_TIMING=1 wrote one" || bad "C: FC_TIMING on/off TSV presence wrong"

echo "=== D: a failing 'git commit' (pre-commit hook refusal) still records the commit stage (R1-I2(d)) ==="
P="$(scratch D)"; RID="t016_hookfail_$$"
printf '#!/bin/sh\nexit 1\n' > "$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
rc="$(run_ca "$P" "$RID" -m "hook refused")"; T="$(tsv_of "$P" "$RID")"
row="$(awk -F'\t' 'NR>1 && $3=="commit" {print $7"|"$11}' "$T" 2>/dev/null)"
if [ "$rc" != 0 ] && [ "$row" = "FAIL|result=aborted;rc=$rc" ]; then
  ok "D: rc=$rc and the aborted commit stage has its FAIL row ($row)"
else
  bad "D: rc=$rc; commit row='$row' (want FAIL|result=aborted;rc=$rc); ids: $(ids_of "$T" | tr '\n' ' ')"
fi

echo "=== E: a §11.4.74 sibling-check refusal records BOTH its own row and the commit row (R1-I2(c)) ==="
P="$(scratch E)"; RID="t016_sibling_$$"
echo "# doc" > "$P/doc.md"
rc="$(run_ca "$P" "$RID" -m "sibling refused")"; T="$(tsv_of "$P" "$RID")"
srow="$(awk -F'\t' 'NR>1 && $3=="sibling_check" {print $7"|"$11}' "$T" 2>/dev/null)"
crow="$(awk -F'\t' 'NR>1 && $3=="commit" {print $7"|"$11}' "$T" 2>/dev/null)"
if [ "$rc" = 1 ] && [ "$srow" = "FAIL|result=exporter_missing" ] && [ "$crow" = "FAIL|result=aborted;rc=1" ]; then
  ok "E: rc=1, sibling_check FAIL row and the aborted commit row are both recorded"
else
  bad "E: rc=$rc sibling='$srow' commit='$crow'"
fi

echo "=== F: --sync-push with a failing push_all.sh records the aborted push stage (R1-I2(e)) ==="
P="$(scratch F)"; RID="t016_syncfail_$$"
git -C "$P" remote set-url upstream "$TMP/F/does-not-exist.git"
rc="$(run_ca "$P" "$RID" --sync-push -m "sync push fails")"; T="$(tsv_of "$P" "$RID")"
prow="$(awk -F'\t' 'NR>1 && $3=="push:call_push_all" {print $7"|"$11}' "$T" 2>/dev/null)"
if [ "$rc" != 0 ] && [ "$prow" = "FAIL|result=aborted;rc=$rc" ]; then
  ok "F: rc=$rc and push:call_push_all has its aborted FAIL row"
else
  bad "F: rc=$rc push:call_push_all='$prow'; ids: $(ids_of "$T" | tr '\n' ' ')"
fi

echo "=== G: --dry-run --sync-push never performs a network read-back (R1-m5) ==="
P="$(scratch G)"; RID="t016_drysync_$$"
rc="$(run_ca "$P" "$RID" --dry-run --sync-push -m "dry sync")"; T="$(tsv_of "$P" "$RID")"
g_ok=1
for r in github origin upstream; do
  [ "$(field_of "$T" "push:$r" 11)" = "remote=$r;tip=not_read_dry_run;result=dry-run" ] || g_ok=0
done
[ "$rc" = 0 ] && [ "$g_ok" = 1 ] && ok "G: dry-run push rows carry tip=not_read_dry_run (no ls-remote under --dry-run)" \
  || bad "G: rc=$rc rows: $(awk -F'\t' 'NR>1 && $3 ~ /^push:/ {print $3"|"$11}' "$T" 2>/dev/null | tr '\n' ' ')"

echo "=== H: a COMMIT_ALL_SOURCE_ONLY harness writes no row into the project's qa-results (R1-m8) ==="
P="$(scratch H)"
( cd "$P" && COMMIT_ALL_SOURCE_ONLY=1 bash -c 'source scripts/commit_all.sh; set +e +u; _ensure_index_lock_free >/dev/null 2>&1; exit 0' ) >/dev/null 2>&1
n="$(find "$P/qa-results" -name '*.tsv' 2>/dev/null | wc -l)"
[ "$n" = 0 ] && ok "H: sourcing + driving _ensure_index_lock_free wrote 0 TSVs" || bad "H: $n TSV(s) written by a source-only harness"
# control: the SAME harness with an explicit FC_TIMER_TSV + FC_TIMING=1 DOES write -- the
# suppression is the default, not a broken timer.
( cd "$P" && COMMIT_ALL_SOURCE_ONLY=1 FC_TIMING=1 FC_TIMER_TSV="$TMP/H/explicit.tsv" bash -c 'source scripts/commit_all.sh; set +e +u; _ensure_index_lock_free >/dev/null 2>&1; exit 0' ) >/dev/null 2>&1
[ "$(count_id "$TMP/H/explicit.tsv" lock:index)" = 1 ] && ok "H control: an explicit FC_TIMER_TSV opt-in still records lock:index" \
  || bad "H control: explicit opt-in wrote no lock:index row"

echo "=== I: an UNPINNED run -> every row's run_id equals its own TSV filename stem (R1-I1) ==="
P="$(scratch I)"
( cd "$P" && SKIP_COMPRESS=true COMMIT_ALL_CASCADE=false timeout 180 bash scripts/commit_all.sh \
    --continuation-no-update-needed "fc stage timer test" --dry-run -m unpinned > "$P/../ca.out" 2>&1 < /dev/null )
T="$(find "$P/qa-results/fastcycle/commit" -name '*.tsv' 2>/dev/null | head -n1)"
stem="$(basename -- "${T:-none}" .tsv)"
[ -n "$T" ] && [ "$(all_col_eq "$T" 1 "$stem")" = 1 ] && ok "I: all rows of $stem.tsv carry run_id $stem" \
  || bad "I: run_id column differs from the filename stem in ${T:-<no TSV>}"

echo "=== J: per-remote result comes from the read-back, never from push_all.sh's aggregate rc (R1-m6) ==="
P="$(scratch J)"; RID="t016_skip_$$"
git init -q --bare "$TMP/J/upstream_only.git"
git -C "$P" remote set-url upstream "$TMP/J/upstream_only.git"
rc="$( PUSH_SKIP_REMOTES="upstream" run_ca "$P" "$RID" -m "skip upstream")"; T="$(tsv_of "$P" "$RID")"
HEADJ="$(git -C "$P" rev-parse HEAD)"
if wait_for_id "$T" push:upstream 90; then
  ug="$(field_of "$T" push:github 11)"; uu="$(field_of "$T" push:upstream 11)"
  case "$ug" in "remote=github;tip=$HEADJ;result=ok") j1=1 ;; *) j1=0 ;; esac
  case "$uu" in "remote=upstream;tip=UNKNOWN;result=skipped_by_policy") j2=1 ;; *) j2=0 ;; esac
  [ "$rc" = 0 ] && [ "$j1" = 1 ] && [ "$j2" = 1 ] \
    && ok "J: pushed remote -> result=ok (tip == HEAD); PUSH_SKIP_REMOTES member -> result=skipped_by_policy (never 'ok')" \
    || bad "J: rc=$rc github='$ug' upstream='$uu'"
else
  bad "J: no push:upstream row within 90s"
fi
P="$(scratch K)"
( cd "$P" && git commit -qam local-only 2>/dev/null; echo c > c.txt; git add c.txt; git commit -qm "local only" )
( cd "$P" && COMMIT_ALL_SOURCE_ONLY=1 FC_TIMING=1 FC_TIMER_TSV="$TMP/K/k.tsv" bash -c 'source scripts/commit_all.sh; set +e +u; _fc_record_remote_tips main post-push; exit 0' ) >/dev/null 2>&1
k_ok=1
for r in github origin upstream; do
  case "$(awk -F'\t' -v w="push:$r" 'NR>1 && $3==w {print $7"|"$11}' "$TMP/K/k.tsv" 2>/dev/null)" in
    "FAIL|remote=$r;tip="*";local="*";result=tip_mismatch") : ;; *) k_ok=0 ;; esac
done
[ "$k_ok" = 1 ] && ok "K: a remote whose read-back tip != the local branch tip is recorded FAIL result=tip_mismatch" \
  || bad "K: tip_mismatch rows wrong: $(awk -F'\t' 'NR>1 {print $3"|"$7"|"$11}' "$TMP/K/k.tsv" 2>/dev/null | tr '\n' ' ')"

echo "=== N5: a missing fc_timer.sh is loud, never silent (round-2 N5, kept) ==="
N5="$TMP/n5"; mkdir -p "$N5/scripts/lib"; cp -- "$REAL_COMMIT_ALL" "$N5/scripts/commit_all.sh"; cp -- "$REAL_COMMON" "$N5/scripts/lib/common.sh"
N5_OUT="$(cd "$N5" && COMMIT_ALL_SOURCE_ONLY=1 bash -c 'source scripts/commit_all.sh' 2>&1)"
printf '%s' "$N5_OUT" | grep -qF "fc_timer.sh not found at" && ok "N5: missing library -> named stderr warning" || bad "N5: no warning when fc_timer.sh is absent"
P="$(scratch N5ctl)"
N5C="$(cd "$P" && COMMIT_ALL_SOURCE_ONLY=1 bash -c 'source scripts/commit_all.sh' 2>&1)"
printf '%s' "$N5C" | grep -qF "fc_timer.sh not found at" && bad "N5 control: warning printed although the library is present" \
  || ok "N5 control: no warning when the library is present"

echo
if [ "$fail" = 0 ]; then echo "=== COMMIT STAGE TIMER: ALL CHECKS PASS ==="; else echo "=== COMMIT STAGE TIMER: FAILURES ABOVE ==="; fi
exit "$fail"
