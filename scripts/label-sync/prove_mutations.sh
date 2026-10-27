#!/usr/bin/env bash
# scripts/label-sync/prove_mutations.sh
#
# Purpose : §1.1 paired-mutation proof for label-sync CORE. Copies the Go
#           module to a SCRATCH dir, applies each independent mutant
#           (one per scratch copy), runs `go test` and REQUIRES the suite to
#           FAIL; a control run of the unmutated copy REQUIRES it to pass. A
#           mutant that survives means the tests do not guard that behaviour.
#           Mutants (59): the original six, the review's SURVIVING mutants
#           (seq-before-snapshot, TTL >=, inheritance depth, following-ancestor
#           leak, started_at, heartbeat revive, verify fold/seq/snapshot,
#           fsync removal) and one per new mechanism (derived binding,
#           sanitising, compaction, reaping, pid start-time, lock timeout,
#           owner/orphan checks, socket fallback/umask, hub ring, --clear) and
#           the second review's (bus.addr after bind, exit 3, hello limit,
#           stale sweeper age/liveness/batch, patch-id checks in prepare AND
#           fold (reviewer R1), pid range, explicit-alias pin on register and
#           update).
#           KILL CRITERION (review-2 finding 5): a mutant is KILLED only when
#           it COMPILES (`go test -run '^$' ./...` builds every test binary)
#           and the suite reports at least one `--- FAIL:` line. A mutant that
#           does not compile, or fails without any `--- FAIL:` (panic, timeout,
#           vet), is UNDETERMINED — it proves nothing — and the proof fails.
# Usage   : bash scripts/label-sync/prove_mutations.sh [--only <name>[,<name>...]] [--list]
#           --selftest  run ONE known non-compiling mutant: expected exit 2
# Inputs  : none (reads the module next to this script).
# Outputs : one line per mutant: KILLED (with the failing test names) /
#           SURVIVED / UNDETERMINED / NOT-APPLIED, then a summary.
# Exit    : 0 every selected mutant killed and control green | 1 a mutant
#           survived or the control failed | 2 cannot determine (no go, copy
#           failure, a mutation did not apply, or any mutant UNDETERMINED) —
#           never a pass.
# Side-effects: temp dir under $TMPDIR (trap-removed). Never edits the real tree.
#           Uses `nice` and `go test -p 2`; GOPROXY=off (stdlib only).
# Deps    : bash, go, sed, cmp, mktemp.
# Cross-refs: §1.1, §11.4.107 (self-validated oracle), §11.4.201, §11.4.18.
# Classification: universal (§11.4.17).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
command -v go >/dev/null 2>&1 || { echo "prove_mutations: go not found" >&2; exit 2; }
ONLY=""; LIST=""
SELFTEST=""
case "${1:-}" in --only) ONLY=",${2:-},";; --list) LIST=1;; --selftest) SELFTEST=1;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/label_sync_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# name|file|sed-expression (must change the file). Mutants target `// MUT:<tag>`
# lines so they survive unrelated edits. Groups: original 6 | reviewer's
# SURVIVING mutants (finding 9) | new mechanisms (findings 1,2,5,8,10, lock).
MUTANTS=(
  'alias_switch_ignored|internal/state/fold.go|s|^\t\tr\.Active = model\.Active{.*$|\t\t_ = ev.Active|'
  'non_atomic_write|internal/state/atomic.go|/MUT:atomic/s|os\.CreateTemp(dir, "\."+filepath\.Base(path)+"\.tmp-\*")|os.OpenFile(path, os.O_CREATE\|os.O_WRONLY\|os.O_TRUNC, 0o600)|'
  'followers_inverted|internal/state/fold.go|/MUT:follow/s|if cur\.FollowActive {|if !cur.FollowActive {|'
  'ttl_never_expires|internal/state/fold.go|/MUT:ttl/s|if !(age > o\.TTL) {|if true \|\| !(age > o.TTL) {|'
  'grammar_accepts_bad|internal/label/label.go|s|\^\\(T(\[0-9\]+\|\\?)/|^\\(T(.*)/|'
  'torn_tail_is_corruption|internal/state/store.go|/MUT:torn/s|return res, nil|if badPending { res.corrupt++ }; return res, nil|'
  'seq_written_before_snapshot|internal/state/store.go|/MUT:foldfirst/s|^\tif err := WriteAtomic|\t_ = WriteAtomic(s.p("seq"), []byte(strconv.FormatUint(r.Seq, 10)+"\\n"))\n\tif err := WriteAtomic|'
  'ttl_ge|internal/state/fold.go|/MUT:ttl/s|age > o\.TTL|age >= o.TTL|'
  'binding_depth_1|internal/state/fold.go|/MUT:bdepth/s|depth < maxDepth|depth < 1|'
  'binding_depth_2|internal/state/fold.go|/MUT:bdepth/s|depth < maxDepth|depth < 2|'
  'place_inherit_depth_1|internal/state/fold.go|/MUT:pdepth/s|depth < maxDepth|depth < 1|'
  'inherit_from_following_ancestor|internal/state/fold.go|/MUT:pinned/s|return !e\.FollowActive \&\& e\.Alias != ""|return e.Alias != ""|'
  'started_at_not_kept|internal/state/fold.go|/MUT:startedat/s|ok \&\& e\.StartedAt|false \&\& ok \&\& e.StartedAt|'
  'heartbeat_no_unknown_revive|internal/state/fold.go|/MUT:hbrevive/s|!set \&\& cp\.State|!set \&\& false \&\& cp.State|'
  'verify_ignores_fold_mismatch|internal/state/store.go|/MUT:verifyfold/s|} else if b\.Seq == want\.Seq|} else if false \&\& b.Seq == want.Seq|'
  'verify_ignores_seq_ahead_by_one|internal/state/store.go|/MUT:verifyseq/s|n > last|n > last+1|'
  'verify_ignores_snapshot_ahead_by_one|internal/state/store.go|/MUT:verifysnap/s|sn\.Seq > last|sn.Seq > last+1|'
  'tmp_fsync_removed|internal/state/atomic.go|/MUT:tmpsync/s|fsyncFile(f)|error(nil)|'
  'log_fsync_removed|internal/state/store.go|/MUT:logsync/s|fsyncFile(f)|error(nil)|'
  'heal_never_truncates|internal/state/store.go|/MUT:heal/s|f\.Truncate(cut)|error(nil)|'
  'no_flock|internal/state/flock.go|/MUT:flock/s|syscall\.Flock(int(f\.Fd()), syscall\.LOCK_EX\|syscall\.LOCK_NB)|error(nil)|'
  'lock_timeout_ignored|internal/state/flock.go|/MUT:locktimer/s|time\.NewTimer(timeout)|time.NewTimer(timeout * 20)|'
  'writers_never_reap|internal/state/store.go|/MUT:reap/s|if e\.State == model\.StateDone \&\&|if false \&\&|'
  'compaction_skips_base|internal/state/store.go|/MUT:compactbase/s|WriteAtomic(s\.p("base\.json"), bb)|func() error { _ = bb; return nil }()|'
  'no_horizon_marker|internal/state/store.go|/MUT:horizon/s|if !found \&\&|if false \&\& !found \&\&|'
  'sanitize_off|internal/label/label.go|/MUT:sanitize/s|case r < 0x20, r == 0x7f, r >= 0x80 \&\& r <= 0x9f:|case false:|'
  'store_id_validation_off|internal/state/store.go|/MUT:validid/s|if !label\.ValidID(e\.ID) {|if false {|'
  'cli_output_unfiltered|cmd/labelctl/main.go|/MUT:cleanout/s|label\.CleanText(string(p))|string(p)|'
  'pid_start_ignored|internal/state/flock.go|/MUT:pidstart/s|return start == "" \|\| start == boot+":"+cur|return true \|\| start == boot+":"+cur|'
  'owner_check_off|internal/state/store.go|/MUT:owner/s|ok \&\& int(st\.Uid) != currentUID()|ok \&\& int(st.Uid) != currentUID() \&\& false|'
  'orphans_kept|internal/state/store.go|/MUT:orphans/s|s\.cleanOrphans()|_ = s|'
  'derive_does_not_pin|cmd/labelctl/main.go|/MUT:derivepin/s|e\.FollowActive = false|e.FollowActive = true|'
  'clear_ignored|cmd/labelctl/main.go|/MUT:clear/s|patch\[key\] = ""|_ = key|'
  'socket_no_fallback|internal/bus/bus.go|/MUT:sockfallback/s|if len(direct) <= MaxSockPath {|if true {|'
  'socket_umask_loose|internal/bus/bus.go|/MUT:umask/s|syscall\.Umask(0o177)|syscall.Umask(0o022)|'
  'hub_ring_ignored|internal/bus/bus.go|/MUT:ring/s|if len(h\.ring) > 0 \&\&|if false \&\& len(h.ring) > 0 \&\&|'
  'seqless_log_never_polled|internal/bus/bus.go|/MUT:peekzero/s| \|\| n == 0||'
  # --- second review (findings 4, 5, 6, 7, 9, 12, 14) ---
  'addr_before_listen|cmd/label-busd/main.go|/MUT:listenfirst/s|beforeListen() // MUT:listenfirst|_ = state.WriteAtomic(addrf, []byte(sock+"\\n")); beforeListen()|'
  'second_instance_rc1|cmd/label-busd/main.go|s|^const exitAlreadyRunning = 3$|const exitAlreadyRunning = 1|'
  'hello_unlimited|internal/bus/bus.go|/MUT:hellolimit/s|io\.LimitReader(conn, MaxHelloBytes)|conn|'
  'sweep_ignores_age|internal/state/store.go|/MUT:sweepage/s|if !(age > s\.opts\.SweepAfter) {|if false {|'
  'sweep_ignores_liveness|internal/state/store.go|/MUT:sweepalive/s|return !s\.opts\.Pids\.Alive(e\.PID, e\.PIDStart)|return true|'
  'sweep_unbounded|internal/state/store.go|/MUT:sweepbatch/s|if len(swept) > s\.opts\.SweepBatch {|if false \&\& len(swept) > s.opts.SweepBatch {|'
  'patch_id_unchecked_in_prepare|internal/state/store.go|/MUT:patchid/s|if v != "" \&\& !label\.ValidID(v) {|if false {|'
  'patch_id_unchecked_in_fold_R1|internal/state/fold.go|s|ok \&\& v != "" \&\& !label\.ValidID(v) {|ok \&\& v != "" \&\& false {|'
  'sweep_ignores_pid_namespace|internal/state/store.go|/MUT:sweepns/s|return s\.opts\.SweepForeignNS >= 0 \&\& age > s\.opts\.SweepForeignNS|return !s.opts.Pids.Alive(e.PID, e.PIDStart)|'
  'sweep_foreign_unbounded|internal/state/store.go|/MUT:sweepns/s|return s\.opts\.SweepForeignNS >= 0 \&\& age > s\.opts\.SweepForeignNS|return false|'
  'sweep_unknown_like_same|internal/state/store.go|/MUT:sweepunknown/s|if s\.opts\.SweepUnknownNS < 0 \|\| !(age > s\.opts\.SweepUnknownNS) {|if !(age > s.opts.SweepAfter) {|'
  'sweep_unknown_never|internal/state/store.go|/MUT:sweepunknown/s|if s\.opts\.SweepUnknownNS < 0 \|\| !(age > s\.opts\.SweepUnknownNS) {|if true {|'
  'entity_drops_unknown_fields|internal/model/model.go|/MUT:extrakeep/s|if !entityKeys\[k\] {|if false {|'
  'repair_trusts_fold|internal/state/store.go|/MUT:repairfull/s|s\.loadOnceFrom(false)|s.loadOnceFrom(true)|'
  'shellrefresh_files_kept|internal/state/store.go|/MUT:dropshellrefresh/s|_ = os\.Remove(filepath\.Join(s\.dir, "shellrefresh", id+suf))|_ = filepath.Join(s.dir, "shellrefresh", id+suf)|'
  'pid_namespace_not_recorded|internal/state/store.go|/MUT:pidnsrecord/s|e\.PIDNS = pidNS(s\.opts\.Pids)|e.PIDNS = ""|'
  'pid_patch_keeps_namespace|internal/state/fold.go|/MUT:pidnsclear/s|e\.PIDNS = ""|_ = 0|'
  'stale_addr_not_removed|cmd/label-busd/main.go|/MUT:addrstale/s|_ = os\.Remove(addrf)|_ = 0|'
  'failed_addr_write_left|cmd/label-busd/main.go|/MUT:addrwritefail/s|_ = os\.Remove(addrf)|_ = 0|'
  'pid_range_unchecked|internal/state/store.go|/MUT:pidrange/s|if e\.PID < 0 \|\| e\.PID > MaxPID {|if false {|'
  'explicit_alias_follows|cmd/labelctl/main.go|/MUT:explicitpin/s|e\.FollowActive = false|e.FollowActive = true|'
  'update_alias_does_not_pin|cmd/labelctl/main.go|/MUT:updatepin/s|patch\["follow_active"\] = "false"|_ = patch|'
)
# --selftest: the pre-review mutant that does NOT compile (`bb` unused) must be
# reported UNDETERMINED and make the proof exit 2 — the build pre-check's own
# paired proof (it was once counted as KILLED).
if [ -n "$SELFTEST" ]; then
  MUTANTS=('selftest_noncompiling|internal/state/store.go|/MUT:compactbase/s|WriteAtomic(s\.p("base\.json"), bb)|error(nil)|')
fi
if [ -n "$LIST" ]; then for m in "${MUTANTS[@]}"; do echo "${m%%|*}"; done; exit 0; fi

run_tests() { ( cd "$1" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go test -p 2 -count=1 -timeout 180s ./... >"$2" 2>&1 ); }
compiles()  { ( cd "$1" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go test -p 2 -count=1 -run '^$' ./... >"$2" 2>&1 ); }

fail=0; undet=0; killed=0; total=0
# control
CTL="$TMP/control"; mkdir -p "$CTL" && cp -R "$SELF/." "$CTL/" || exit 2
if run_tests "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated module: tests PASS"
else echo "CONTROL   FAILED — unmutated tests do not pass (see $TMP/control.log)"; tail -20 "$TMP/control.log"; exit 1; fi
rm -rf "$CTL"

for m in "${MUTANTS[@]}"; do
  name="${m%%|*}"; rest="${m#*|}"; file="${rest%%|*}"; expr="${rest#*|}"
  [ -z "$ONLY" ] || case "$ONLY" in *",$name,"*) ;; *) continue ;; esac
  total=$((total+1))
  d="$TMP/$name"; mkdir -p "$d" && cp -R "$SELF/." "$d/" || exit 2
  cp "$d/$file" "$d/$file.orig"
  sed -i "$expr" "$d/$file" || exit 2
  if cmp -s "$d/$file" "$d/$file.orig"; then echo "NOT-APPLIED $name — sed did not change $file"; exit 2; fi
  rm -f "$d/$file.orig"
  if ! compiles "$d" "$TMP/$name.build.log"; then
    echo "UNDETERMINED $name — the mutant does not compile (a build error kills nothing): $(grep -m1 -E '\.go:[0-9]+' "$TMP/$name.build.log")"
    undet=$((undet+1)); rm -rf "$d"; continue
  fi
  if run_tests "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — tests still PASS with the mutant (bluff gap)"; fail=1
  else
    nf=$(grep -cE '^[[:space:]]*--- FAIL:' "$TMP/$name.log")
    if [ "$nf" -gt 0 ]; then
      echo "KILLED    $name ($nf --- FAIL: $(grep -E '^[[:space:]]*--- FAIL:' "$TMP/$name.log" | sed 's/.*--- FAIL: \([^ ]*\).*/\1/' | sort -u | head -4 | tr '\n' ' '))"
      killed=$((killed+1))
    else
      echo "UNDETERMINED $name — tests failed without any '--- FAIL:' (panic/timeout/setup): $(grep -m1 -E 'panic|FAIL' "$TMP/$name.log")"
      undet=$((undet+1))
    fi
  fi
  rm -rf "$d"
done
echo "----"
echo "mutants killed: $killed / $total (undetermined: $undet)"
[ "$total" -gt 0 ] || { echo "no mutant selected" >&2; exit 2; }
[ "$fail" -eq 0 ] || exit 1
[ "$undet" -eq 0 ] || exit 2
[ "$killed" -eq "$total" ] || exit 1
echo "label-sync paired-mutation proof: PASS"
exit 0
