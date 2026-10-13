#!/bin/bash
# Purpose : T140 Round 19 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- round-18 independent review findings (reviewer's own overall
#           assessment: "the orchestration, oracle and timeout design is
#           sound ... I would expect a GO" after this round's exactly 3
#           items land with paired mutations):
#             IMPORTANT  `os.walk`'s DEFAULT `followlinks=False` lists a
#                        symlinked subdirectory under the per-worktree admin
#                        `refs/`/`logs/` trees in `dirs` but never DESCENDS
#                        into it, and nothing raises (`os.walk`'s own
#                        documented, intentional behaviour -- not an error
#                        `_walk_raise` would ever see). A symlink pointing at
#                        a location holding a commit reachable from nowhere
#                        else is therefore invisible to the candidate-
#                        collection loop, and `git worktree remove` deletes
#                        the SYMLINK (not its target): reproduced live (3/3
#                        deterministic) -- `verify-proposal ... retire`
#                        returned ALLOWED while `git -C wt for-each-ref
#                        refs/worktree` still listed a ref anchoring a
#                        commit that `gc --prune=now` then destroyed once
#                        the symlink (and with it the worktree's only
#                        pointer) was gone. Fixed by refusing ANY symlink
#                        found anywhere under these two trees, fail-closed,
#                        deliberately NOT `followlinks=True` (adds loop-
#                        risk). Folded into the SAME pass (round-18's own
#                        "minor sibling" note): any NON-REGULAR leaf entry
#                        (e.g. a FIFO) is refused too, since `open()` on a
#                        FIFO can block forever outside any git timeout.
#             MINOR-A    `_group_has_survivor`'s signal-0 probe succeeds on
#                        a ZOMBIE member of the group too (a zombie is still
#                        visible to the kernel until reaped), but a zombie
#                        holds NO file descriptors and so cannot be what is
#                        actually keeping a pipe open -- a filter spawning
#                        BOTH an in-group child (killed by the group kill,
#                        becomes a zombie) AND a `setsid`-escaped grandchild
#                        (the real survivor, holding the pipe) made the
#                        probe alone report `survivor=True` purely from the
#                        zombie's presence, falling through to the ORIGINAL
#                        unbounded wait instead of the intended bounded
#                        drain. Fixed by scanning `/proc/*/stat` for a
#                        NON-zombie member of the group before reporting a
#                        real survivor.
#             MINOR-B    round-15's own B3 test-evidence step shared the
#                        SAME cause/effect confound round-17's MINOR-3 fixed
#                        for B2 -- fixed directly in
#                        test_custody_sweep_r15_regression.sh (the flaw is
#                        in that suite's own loss-proof methodology, not in
#                        custody_sweep.py), not duplicated here.
#
# Honest boundary on MINOR-A's test methodology (section 11.4.6), CORRECTED
# by round 21 (round-20 finding MINOR-2 -- a test-evidence accuracy issue,
# not a production code gap): the paragraph that used to stand here claimed
# a CLI-level reproduction of the zombie-survivor scenario "cannot be made
# deterministic on this host." That claim was FALSE. The real reason the
# earlier CLI attempt measured non-deterministic had nothing to do with
# determinism being impossible: that attempt's escaped "survivor" was NOT
# the zombie's own LIVE PARENT, so this host's real init (`systemd`,
# confirmed PID 1, a prompt orphan reaper) could -- and did -- collect the
# zombie within the ~3s window (`_KILL_DRAIN_GRACE_S`) BEFORE
# `_group_has_survivor` ever got to probe it, erasing the exact precondition
# the fix exists to handle before the test could observe it.
#
# Round 21 constructs a DETERMINISTIC CLI-level reproduction instead by
# making the escaped survivor be the zombie's OWN LIVE PARENT: a git clean
# filter forks a child that stays in the git process group (killed by the
# group SIGKILL, becomes the zombie) while the PARENT calls `os.setsid()`
# (escaping the group) and sleeps, holding the tool's inherited stderr pipe
# open. Because the parent is alive for the whole test and never reaps its
# own child, PID 1 never gets the chance to reap it either -- the zombie is
# still present, inside `pgid`, exactly when `_group_has_survivor` probes
# it, on every run. Confirmed deterministic over 3 runs on this host: the
# real (fixed) tool REFUSES in ~6.1s every time (the bounded drain correctly
# excludes the zombie and abandons the escaped-pipe wait instead of
# re-blocking); the `MR19_3`-equivalent mutant (unconditional `return True`)
# takes the FULL ~20.1s filter-sleep every time (it treats the zombie's
# signal-0 success as a real survivor and falls through to the original
# unbounded wait). This CLI-level test is shipped below, immediately after
# the unit-level test that follows this paragraph -- ALONGSIDE, not instead
# of it: the unit test remains a valid, finer-grained proof that
# `_group_has_survivor` itself excludes a zombie-only group under full test
# control (no external init can ever race it); the CLI-level test
# additionally proves the SAME fix holds end-to-end through the real tool's
# own `_exec`/`verify-proposal` path, against a real escaped OS process.
# Producer != Verifier (section 11.4.240): both directly re-derive the
# round-18/round-20 reviewers' own finding text and constructions, not the
# tool's own selftest.
#
# Every CLI-level case builds REAL throwaway git repositories under a temp
# dir (never this project's own repo, worktrees or stashes) and runs the
# REAL tool's `verify-proposal`. Each fix is first shown to matter via a
# paired mutation that reverts it; the IMPORTANT finding's loss-proof
# methodology mirrors round-19's own B3 fix in the r15 suite (control gc
# run FROM THE WORKTREE, proof gc run from main AFTER removal) since this
# fixture shares the identical per-worktree-ref-anchoring shape.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
      GIT_COMMON_DIR CUSTODY_SWEEP_GIT_TIMEOUT_S
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main -c protocol.file.allow=always "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)

fail=0
pass=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=1; echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R19 regression guard: control needle -- tool + libs exist, git/python/mkfifo usable ==="
for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
command -v git >/dev/null || notok "control needle: git not on PATH"
command -v mkfifo >/dev/null || notok "control needle: mkfifo not on PATH"
command -v timeout >/dev/null || notok "control needle: timeout not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git + mkfifo + timeout present"

sha() { sha256sum "$1" | cut -d' ' -f1; }
gone() { ! g -C "$1" cat-file -e "$2" 2>/dev/null; }
gc_only() { g -C "$1" gc --quiet --prune=now >/dev/null 2>&1; }

run_case() {  # IMPL ROOT KIND ID ACTION BACKUP -> "VERDICT<TAB>DETAIL"
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json"
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
}

# run_case_walltimeout: same shape as run_case, but the python invocation
# itself is wrapped in a hard WALL-CLOCK `timeout` (never relying on the
# tool's OWN internal CUSTODY_SWEEP_GIT_TIMEOUT_S, which only bounds git
# subprocess calls -- never a local `open()` on a FIFO). Prints
# "RC<TAB>VERDICT<TAB>DETAIL<TAB>ELAPSED"; RC=124 means the wall timeout
# fired (the process was killed while still blocked).
run_case_walltimeout() {  # IMPL ROOT KIND ID ACTION BACKUP WALL_S
  local impl="$1" root="$2" kind="$3" id="$4" action="$5" path="$6" wall="$7"
  local pj="$TMP/prop.$$.$RANDOM.json" oj="$TMP/out.$$.$RANDOM.json" s e rc res
  python3 - "$pj" "$kind" "$id" "$action" "$(sha "$path")" "$path" <<'PYEOF'
import json, sys
p, kind, eid, action, h, path = sys.argv[1:]
json.dump({"entry_kind": kind, "entry_id": eid, "action": action,
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  s=$(date +%s)
  timeout -k 2 "$wall" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$root" --out "$oj" >/dev/null 2>&1
  rc=$?
  e=$(date +%s)
  res=$(python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
)
  printf '%s\t%s\t%s\n' "$rc" "$res" "$((e - s))"
}

expect() {  # NAME RESULT VERDICT [DETAIL_SUBSTRING...]
  local name="$1" res="$2" want="$3"
  shift 3
  local got="${res%%$'\t'*}" det="${res#*$'\t'}" s
  if [ "$got" != "$want" ]; then
    notok "$name: expected $want, got $got (${det:0:400})"
    return
  fi
  for s in "$@"; do
    if [[ "$det" != *"$s"* ]]; then
      notok "$name: $got but detail does not name \"$s\" (${det:0:400})"
      return
    fi
  done
  ok "$name -> $got${1:+ (detail names: $*)}"
}

# mkrepo DIR : main repo DIR/main (one commit: f, keep) + linked worktree DIR/wt on branch feat
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  g init --quiet "$d/main"
  printf 'a\n' > "$d/main/f"; printf 'b\n' > "$d/main/keep"
  g -C "$d/main" add -A; g -C "$d/main" commit --quiet -m init
  g -C "$d/main" worktree add --quiet -b feat "$d/wt" >/dev/null 2>&1
}
wt_backup() { g -C "$1/wt" diff "${CANON[@]}" HEAD > "$1/wt.patch"; }
admin() { echo "$1/main/.git/worktrees/wt"; }

build_copy() {
  mkdir -p "$1/orchestration" "$1/lib"
  cp "$IMPL" "$1/orchestration/custody_sweep.py"
  cp "$LIB" "$1/lib/fc_common.py"
  cp "$EXLIB" "$1/lib/fc_entry.py"
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    print("anchor count=%d for %r" % (c.count(old), old))
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
}
mk_mutant() {  # NAME OLD NEW -> prints mutant impl path, or "" on anchor failure
  local d="$TMP/mut_$1"
  build_copy "$d"
  if mutate "$d/orchestration/custody_sweep.py" "$2" "$3" >"$d.log" 2>&1; then
    echo "$d/orchestration/custody_sweep.py"
  fi
}
mut_allows() {  # NAME OLD NEW ROOT KIND ID ACTION BACKUP
  local name="$1" old="$2" new="$3" root="$4" kind="$5" id="$6" action="$7" path="$8"
  local m real mutant
  m=$(mk_mutant "$name" "$old" "$new")
  if [ -z "$m" ]; then notok "mutation $name: anchor not found ($(cat "$TMP/mut_$name.log"))"; return; fi
  real=$(run_case "$IMPL" "$root" "$kind" "$id" "$action" "$path")
  mutant=$(run_case "$m" "$root" "$kind" "$id" "$action" "$path")
  if [ "${real%%$'\t'*}" != REFUSED ]; then notok "mutation $name: REAL tool did not refuse (${real:0:200})"; return; fi
  if [ "${mutant%%$'\t'*}" = ALLOWED ]; then
    ok "mutation $name: caught -- mutant ALLOWS what the real tool refuses"
  else
    notok "mutation $name SURVIVED: mutant ${mutant:0:200}"
  fi
}

# ---------------------------------------------------------------------------
# IMPORTANT: a symlinked subdirectory under the admin refs/ tree hides a
# commit anchored only through it.
# ---------------------------------------------------------------------------
echo
echo "=== IMPORTANT a symlinked admin refs/ subdirectory hides a commit anchored only through it ==="
S1="$TMP/s1"; mkrepo "$S1"
SV=$(echo saved | g -C "$S1/wt" commit-tree "HEAD^{tree}" -p HEAD -m symsaved)
S1_ADMIN="$(admin "$S1")"
mkdir -p "$TMP/s1_outside/worktree"; echo "$SV" > "$TMP/s1_outside/worktree/saved"
mkdir -p "$S1_ADMIN/refs"
ln -s "$TMP/s1_outside/worktree" "$S1_ADMIN/refs/worktree"
echo z >> "$S1/wt/keep"; wt_backup "$S1"
if [ -n "$(g -C "$S1/wt" for-each-ref --format='%(refname)' --contains "$SV" refs/worktree)" ] \
   && [ -L "$S1_ADMIN/refs/worktree" ]; then
  ok "S1 evidence: refs/worktree is a real symlink, and git sees refs/worktree/saved (through it) anchoring $SV"
else
  notok "S1 evidence: unexpected fixture shape"
fi
expect "S1 symlinked admin refs/ subdirectory" "$(run_case "$IMPL" "$S1/main" worktree wt retire "$S1/wt.patch")" \
  REFUSED "refs/worktree: unexpected symlinked admin entry"
mut_allows MR19_1_dir_symlink_check_removed \
'                    for d in sorted(dirs):
                        dfull = os.path.join(dirpath, d)
                        if os.path.islink(dfull):
                            drel = os.path.relpath(dfull, admin).replace(os.sep, "/")
                            problems.append("%s: unexpected symlinked admin entry (refused; a symlinked "
                                            "subdirectory under logs/ or refs/ is never descended into by "
                                            "this walk, so a commit anchored only through it would be "
                                            "silently missed)" % drel)' \
'                    for d in sorted(dirs):
                        pass' \
  "$S1/main" worktree wt retire "$S1/wt.patch"

echo
echo "=== evidence: performing the destructive action really loses the data (same shape as the r15 B3 fix) ==="
# CONTROL: gc run FROM THE WORKTREE ITSELF (which DOES see its own ref
# through the symlink) while the worktree is still present -- SV must
# survive (mirrors the r15 B3 fix's control/proof pattern exactly, since
# gc run from MAIN does not protect another worktree's own refs/worktree
# namespace at all, symlinked or not -- a from-main gc here would destroy
# SV even with the worktree present, which would NOT isolate removal as
# the cause).
gc_only "$S1/wt"
if gone "$S1/main" "$SV"; then
  notok "S1 control FAILED: 'gc --prune=now' run FROM THE WORKTREE (still present) already destroyed $SV --" \
        "the scenario's symlinked-ref-anchoring assumption is wrong"
else
  ok "S1 control: with the worktree STILL present, 'gc --prune=now' run FROM THE WORKTREE leaves $SV intact"
fi
g -C "$S1/main" worktree remove --force --force "$S1/wt" >/dev/null 2>&1
g -C "$S1/main" reflog expire --expire=now --all >/dev/null 2>&1
gc_only "$S1/main"
if gone "$S1/main" "$SV"; then
  ok "S1 loss proven: commit $SV gone after 'worktree remove --force' (deletes the SYMLINK, not its target) + gc" \
     "(control above shows this is removal itself, not the gc's invocation context)"
else
  notok "S1 loss NOT reproduced ($SV survives)"
fi

# ---------------------------------------------------------------------------
# Minor sibling (folded into the same fix): a non-regular leaf entry (FIFO)
# under refs/ is refused WITHOUT the tool ever blocking on open().
# ---------------------------------------------------------------------------
echo
echo "=== minor sibling: a FIFO under admin refs/ is refused instantly, never blocks on open() ==="
F1="$TMP/f1"; mkrepo "$F1"
F1_ADMIN="$(admin "$F1")"
mkdir -p "$F1_ADMIN/refs/worktree"
mkfifo "$F1_ADMIN/refs/worktree/afifo"
echo z >> "$F1/wt/keep"; wt_backup "$F1"
RES=$(run_case_walltimeout "$IMPL" "$F1/main" worktree wt retire "$F1/wt.patch" 10)
IFS=$'\t' read -r F1_RC F1_V F1_DET F1_EL <<<"$RES"
if [ "$F1_RC" != 124 ] && [ "$F1_V" = REFUSED ] && [[ "$F1_DET" == *"unexpected non-regular admin entry"* ]] \
   && [ "$F1_EL" -lt 5 ]; then
  ok "F1 FIFO under refs/ -> REFUSED in ${F1_EL}s (never opened; detail names: unexpected non-regular admin entry)"
else
  notok "F1 expected a non-hang (rc!=124) REFUSED in <5s naming non-regular, got rc=$F1_RC verdict=$F1_V elapsed=${F1_EL}s" \
        "(${F1_DET:0:300})"
fi
# Paired mutation: remove ONLY the non-regular check. Without it, `open()`
# on the FIFO (inside `_oids_in_file`) blocks FOREVER (no writer ever
# connects) -- bounded here by a hard WALL-CLOCK timeout (never the
# tool's own internal git-subprocess timeout, which this local file read
# never goes through) so a true hang cannot wedge this test suite itself.
m=$(mk_mutant MR19_2_nonregular_check_removed \
'                        if not stat.S_ISREG(lst.st_mode):
                            problems.append("%s: unexpected non-regular admin entry (refused; e.g. a FIFO "
                                            "could block indefinitely outside any git timeout)" % rel)
                            continue
' \
'')
if [ -z "$m" ]; then
  notok "mutation MR19_2_nonregular_check_removed: anchor not found ($(cat "$TMP/mut_MR19_2_nonregular_check_removed.log"))"
else
  MRES=$(run_case_walltimeout "$m" "$F1/main" worktree wt retire "$F1/wt.patch" 6)
  IFS=$'\t' read -r M_RC M_V M_DET M_EL <<<"$MRES"
  if [ "$M_RC" = 124 ]; then
    ok "mutation MR19_2_nonregular_check_removed: caught -- mutant HANGS on open() (wall-timeout rc=124 after" \
       "${M_EL}s), real tool REFUSES in ${F1_EL}s without ever opening the FIFO"
  else
    notok "mutation MR19_2_nonregular_check_removed SURVIVED: mutant did not hang (rc=$M_RC verdict=$M_V" \
          "elapsed=${M_EL}s, detail: ${M_DET:0:200})"
  fi
fi

# ---------------------------------------------------------------------------
# MINOR-A: `_group_has_survivor` excludes zombie members of the process
# group before reporting a real survivor (unit level -- see the file header
# for why this is deterministic at unit level and was NOT reproducible as a
# deterministic CLI-level elapsed-time assertion on this host).
# ---------------------------------------------------------------------------
echo
echo "=== MINOR-A (unit level): _group_has_survivor excludes zombie members of the process group ==="
unit_survivor() {  # IMPL -> prints Z1=... / Z2=... / Z3=... lines
  python3 - "$1" <<'PYEOF'
import importlib.util, os, signal, sys, time

impl = sys.argv[1]
spec = importlib.util.spec_from_file_location("cs", impl)
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

# Z1: a process group containing ONLY a zombie member (the exact round-18
# finding -- signal 0 succeeds on it, but it holds no file descriptors).
# WE are its real, live, non-reaping parent for the whole test, so reaping
# never races any external init/subreaper.
pid1 = os.fork()
if pid1 == 0:
    os.setpgid(0, 0)
    os._exit(0)
time.sleep(0.3)  # let it actually finish and become a zombie
print("Z1=%s" % cs._group_has_survivor(pid1))
os.waitpid(pid1, 0)

# Z2 (control): a process group containing a REAL alive (non-zombie)
# member -- must stay True in BOTH the fixed and the pre-round-19 code,
# proving the fix does not weaken the pre-existing "stay observable as a
# hang" guarantee for a genuine kill-logic defect (the MT1/MR17_2 class).
pid2 = os.fork()
if pid2 == 0:
    os.setpgid(0, 0)
    time.sleep(5)
    os._exit(0)
time.sleep(0.3)
print("Z2=%s" % cs._group_has_survivor(pid2))
os.kill(pid2, signal.SIGKILL)
os.waitpid(pid2, 0)

# Z3 (control): a process group that is genuinely empty (already reaped) --
# must stay False via the pre-existing ProcessLookupError path, unaffected
# by this round's fix.
pid3 = os.fork()
if pid3 == 0:
    os.setpgid(0, 0)
    os._exit(0)
os.waitpid(pid3, 0)
print("Z3=%s" % cs._group_has_survivor(pid3))
PYEOF
}
REAL_Z=$(unit_survivor "$IMPL" 2>&1)
for want in Z1=False Z2=True Z3=False; do
  if grep -qx "$want" <<<"$REAL_Z"; then ok "unit $want"; else notok "unit expected $want; got: $REAL_Z"; fi
done
# Paired mutation: revert `_group_has_survivor` to the pre-round-19 logic
# (a successful signal-0 probe alone means True, unconditionally -- exactly
# the round-17/round-18 behaviour). The mutant must WRONGLY report Z1=True
# (the exact round-18 defect); Z2/Z3 are untouched by this mutation (they
# never reach the mutated line) and must stay unchanged, proving the
# mutation is precisely scoped to the zombie-exclusion branch.
m=$(mk_mutant MR19_3_zombie_exclusion_removed \
'    live = _proc_group_has_nonzombie_member(pgid)
    # `/proc` could not be enumerated at all -- fall back to the same safe
    # default as the PermissionError branch above (keep draining) rather
    # than falsely declaring the group clean.
    return True if live is None else live
' \
'    return True
')
if [ -z "$m" ]; then
  notok "mutation MR19_3_zombie_exclusion_removed: anchor not found ($(cat "$TMP/mut_MR19_3_zombie_exclusion_removed.log"))"
else
  MUT_Z=$(unit_survivor "$m" 2>&1)
  if grep -qx "Z1=True" <<<"$MUT_Z"; then
    ok "mutation MR19_3_zombie_exclusion_removed: caught -- mutant WRONGLY reports Z1=True (the zombie-only" \
       "group's signal-0 success alone fools it, exactly the round-18 defect)"
  else
    notok "mutation MR19_3_zombie_exclusion_removed SURVIVED: mutant gave: $MUT_Z"
  fi
  for want in Z2=True Z3=False; do
    if grep -qx "$want" <<<"$MUT_Z"; then
      ok "mutation MR19_3_zombie_exclusion_removed: $want unaffected (mutation precisely scoped)"
    else
      notok "mutation MR19_3_zombie_exclusion_removed: expected $want unaffected, got: $MUT_Z"
    fi
  done
fi

# ---------------------------------------------------------------------------
# MINOR-A (CLI level, round 21 / round-20 finding MINOR-2): the SAME fix,
# driven end-to-end through the real tool's own `_exec`/`verify-proposal`
# path against a REAL escaped OS process (a git clean filter), not merely
# at the unit level above. See the corrected honest-boundary paragraph at
# the top of this file for why round 19's own "cannot be made
# deterministic" claim was wrong and how this construction fixes that.
# ---------------------------------------------------------------------------
echo
echo "=== MINOR-A (CLI level): a setsid-escaped clean-filter parent holding the tool's pipe is correctly" \
     "bounded, not mistaken for a real survivor by its own killed-and-zombied in-group child ==="
ZDIR="$TMP/zr"; mkdir -p "$ZDIR"
cat > "$ZDIR/zfilter.py" <<'PYEOF'
import os, sys, time
pid = os.fork()
if pid == 0:
    # in-group child: sleeps until the group SIGKILL turns it into a zombie
    time.sleep(60); os._exit(0)
os.setsid()            # escape the killed group; never reap the child
time.sleep(20)         # hold inherited stderr (the tool's pipe) open
PYEOF
PYBIN=$(command -v python3)

Z1="$TMP/z1"; mkrepo "$Z1"
printf 'trigger\n' > "$Z1/wt/trigger"
printf 'trigger filter=zfilter\n' > "$Z1/wt/.gitattributes"
g -C "$Z1/wt" add trigger .gitattributes
g -C "$Z1/wt" commit --quiet -m addtrigger
echo z >> "$Z1/wt/keep"
wt_backup "$Z1"   # captured BEFORE the filter is configured below -- fast, no hang
g -C "$Z1/wt" config filter.zfilter.clean "$PYBIN $ZDIR/zfilter.py"
echo changed >> "$Z1/wt/trigger"   # now the filtered path is dirty too -- the real tool's own
                                   # git status/diff calls will invoke the clean filter

export CUSTODY_SWEEP_GIT_TIMEOUT_S=3
RES=$(run_case_walltimeout "$IMPL" "$Z1/main" worktree wt retire "$Z1/wt.patch" 15)
unset CUSTODY_SWEEP_GIT_TIMEOUT_S
IFS=$'\t' read -r Z1_RC Z1_V Z1_DET Z1_EL <<<"$RES"
if [ "$Z1_RC" != 124 ] && [ "$Z1_V" = REFUSED ] && [ "$Z1_EL" -lt 12 ]; then
  ok "Z1 real tool: zombie-only group correctly excluded -> REFUSED in ${Z1_EL}s (bounded drain abandoned," \
     "never waits out the escaped setsid survivor's full sleep)"
else
  notok "Z1 expected a bounded (<12s) REFUSED, got rc=$Z1_RC verdict=$Z1_V elapsed=${Z1_EL}s (${Z1_DET:0:300})"
fi
# Paired mutation: the SAME MR19_3 mutation already defined above (revert
# `_group_has_survivor` to the pre-round-19 logic -- a successful signal-0
# probe alone means True, unconditionally), now exercised end-to-end
# through the CLI instead of at the unit level.
m=$(mk_mutant MR19_3_zombie_exclusion_removed \
'    live = _proc_group_has_nonzombie_member(pgid)
    # `/proc` could not be enumerated at all -- fall back to the same safe
    # default as the PermissionError branch above (keep draining) rather
    # than falsely declaring the group clean.
    return True if live is None else live
' \
'    return True
')
if [ -z "$m" ]; then
  notok "mutation MR19_3_zombie_exclusion_removed (CLI): anchor not found ($(cat "$TMP/mut_MR19_3_zombie_exclusion_removed.log"))"
else
  export CUSTODY_SWEEP_GIT_TIMEOUT_S=3
  MRES=$(run_case_walltimeout "$m" "$Z1/main" worktree wt retire "$Z1/wt.patch" 30)
  unset CUSTODY_SWEEP_GIT_TIMEOUT_S
  IFS=$'\t' read -r MZ_RC MZ_V MZ_DET MZ_EL <<<"$MRES"
  if [ "$MZ_RC" != 124 ] && [ "$MZ_EL" -ge 15 ]; then
    ok "mutation MR19_3_zombie_exclusion_removed (CLI): caught -- mutant takes the FULL ~20s filter-sleep" \
       "(elapsed=${MZ_EL}s) instead of the real tool's bounded ${Z1_EL}s, because it treats the zombie's" \
       "signal-0 success as a real survivor and falls through to the unbounded drain"
  else
    notok "mutation MR19_3_zombie_exclusion_removed (CLI) SURVIVED: mutant did not take the expected ~20s" \
          "(rc=$MZ_RC elapsed=${MZ_EL}s verdict=$MZ_V, detail: ${MZ_DET:0:200})"
  fi
fi

echo
echo "summary: $pass check(s) passed"
if [ "$fail" = 0 ]; then
  echo "=== R19 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- a symlinked admin refs/logs"
  echo "    subdirectory (and a non-regular leaf entry such as a FIFO) is refused fail-closed instead of"
  echo "    silently skipped by os.walk's default followlinks=False, and _group_has_survivor no longer"
  echo "    mistakes a zombie member of a killed process group for a real pipe-holding survivor. ==="
  exit 0
else
  echo "=== R19 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
