#!/bin/bash
# Purpose: T154 (SpecKit-004 "fast-dev-cycles", User Story 7) RED baseline + functional suite for
# `verify/repo_verify.py --recursive`, per contracts/recursive-verification.md (FR-020, FR-021,
# SC-008) and this task's own line: "with fixtures per contract recursive-verification (one dirty
# submodule and one lagging remote -> not-clean naming each; unreachable remote -> UNVERIFIED,
# exit 4; clean fixture tree -> CLEAN; two runs -> equal hash)". Implements the contract's full
# RED-fixtures table (rv_good_clean, rv_bad_dirty_submodule, rv_bad_lagging_remote,
# rv_bad_rejected_push, rv_bad_uninit_submodule, rv_bad_unfetchable_pointer, rv_blind_remote,
# rv_negctrl_ignored_file, rv_determinism, rv_no_mutation, paired mutation), all against REAL git
# repositories + throwaway LOCAL bare remotes built fresh in a temp dir every run (no network,
# no fakes beyond this being a functional/integration-class test per C-005/11.4.27).
#
# THE GAP at RED-authoring time (verified live, 2026-09-30): `constitution/scripts/fastcycle/
# verify/` had only `plan_struct_check.py` (T046/T159); `repo_verify.py` did not exist. T158 is
# the later, separate task that creates it (tasks.md). Invoking the contract's documented CLI
# shape against the absent tool:
#   $ python3 constitution/scripts/fastcycle/verify/repo_verify.py --recursive --root . --out /tmp/x.json
#   python3: can't open file '.../verify/repo_verify.py': [Errno 2] No such file or directory
#   rc=2
# (python3's own "can't open file" signature -- reproduced below, never assumed, 11.4.6).
#
# Producer != Verifier (11.4.240): this file is authored at the RED step (T154); T158's
# implementation of repo_verify.py is a LATER, SEPARATE task -- fixture construction here uses
# only plain `git`/`python3 -c` plumbing, never any code shared with repo_verify.py itself.
#
# §11.4.273 control needle: before trusting any "clean"/"dirty"/"unreachable" finding below, this
# file first proves a synthetic throwaway repo with ONE known-present dirty file is genuinely
# reported dirty by plain `git status --porcelain`, and a fabricated file is NOT -- the same
# needle discipline repo_verify.py's own self_check() re-implements independently inside itself.
#
# Usage : bash test_repo_verify_red.sh   Exit 0 = suite holds (matches every other test_*_red.sh
#         in this suite's "exit 0 = PASS" convention, run by tests/run_all.sh). Before T158 lands
#         this only exercises the RED-baseline + control-needle + fixture self-consistency checks
#         (the tool-absent branches); once T158 lands (the permanent state from 2026-09-30
#         onward) every fixture is exercised for real against the live CLI.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
TOOL="$FC/verify/repo_verify.py"

fail=0
failx() { fail=1; }
ok() { echo "ok $*"; }
not_ok() { echo "NOT ok $*"; fail=1; }

TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# --- §11.4.273 control needle: prove this test's OWN dirty/clean detection can see -----------
CN="$TMP/control_needle_repo"
git init -q -b main "$CN" 2>/dev/null
git -C "$CN" config user.email fc@example.invalid
git -C "$CN" config user.name fastcycle
cn_status0=$(git -C "$CN" status --porcelain)
if [ -n "$cn_status0" ]; then
  not_ok "control needle: a brand-new empty repo already reports dirty -- this test's own git harness is broken"
else
  ok "control needle: a brand-new empty repo reports clean via this test's own git status call"
fi
echo needle > "$CN/needle.txt"
cn_status1=$(git -C "$CN" status --porcelain)
case "$cn_status1" in
  *needle.txt*) ok "control needle: a known-present untracked file IS detected by this test's own git status call" ;;
  *) not_ok "control needle: a known-present untracked file (needle.txt) was NOT detected -- this test's own detection is broken (11.4.201/11.4.273)" ;;
esac
case "$cn_status1" in
  *fabricated_absent.txt*) not_ok "control needle: a fabricated file was wrongly reported present" ;;
  *) ok "control needle: a fabricated file is correctly NOT reported present" ;;
esac

# --- (0) tool presence / absence-signature check ----------------------------------------------
if [ -f "$TOOL" ]; then
  ok "verify/repo_verify.py exists -- T158 has landed; the real fixture-driven checks below run"
  TOOL_PRESENT=1
else
  ok "verify/repo_verify.py is absent (pre-T158 RED baseline)"
  TOOL_PRESENT=0
  python3 "$TOOL" --recursive --root "$TMP" --out "$TMP/x.json" >"$TMP/absent.out" 2>"$TMP/absent.err"
  ABSENT_RC=$?
  if [ "$ABSENT_RC" -eq 2 ]; then
    ok "absent-tool invocation exits rc=2 (python3's own can't-open-file signature) -- RED baseline confirmed"
  else
    not_ok "absent-tool invocation expected rc=2, got rc=$ABSENT_RC -- re-verify rather than trust this header's prose (11.4.6)"
  fi
fi

if [ "$TOOL_PRESENT" -eq 0 ]; then
  echo "info RED baseline established: repo_verify.py is absent, python3 exits 2 as expected."
  echo "info T158 will implement --recursive per contracts/recursive-verification.md;"
  echo "info once it lands this file's fixture assertions below exercise it for real."
  [ "$fail" -eq 0 ] && exit 0 || exit 1
fi

# ================================================================================================
# Fixture builders (real git, real local bare "remotes", no network -- contract's own words)
# ================================================================================================

mk_repo() {  # mk_repo <path>
  git init -q -b main "$1"
  git -C "$1" config user.email fc@example.invalid
  git -C "$1" config user.name fastcycle
}

mk_bare() {  # mk_bare <path>
  git init -q --bare -b main "$1"
}

# build_good_clean <root>: parent + 2 submodules (subA, subB), each with 2 bare remotes, all
# pushed -- the rv_good_clean / rv_negctrl_ignored_file / rv_determinism / rv_no_mutation base.
build_good_clean() {
  local root="$1"
  mkdir -p "$root"
  local s
  for s in subA subB; do
    mk_repo "$root/${s}_src"
    echo "seed-$s" >"$root/${s}_src/f.txt"
    git -C "$root/${s}_src" add -A
    git -C "$root/${s}_src" commit -qm "init $s"
    mk_bare "$root/${s}_r1.git"
    mk_bare "$root/${s}_r2.git"
    git -C "$root/${s}_src" remote add origin "$root/${s}_r1.git"
    git -C "$root/${s}_src" remote add mirror "$root/${s}_r2.git"
    git -C "$root/${s}_src" push -q origin main
    git -C "$root/${s}_src" push -q mirror main
  done
  mk_repo "$root/parent"
  echo parent-seed >"$root/parent/f.txt"
  git -C "$root/parent" add -A
  git -C "$root/parent" commit -qm "parent init"
  git -C "$root/parent" -c protocol.file.allow=always submodule add -q "$root/subA_r1.git" subA
  git -C "$root/parent" -c protocol.file.allow=always submodule add -q "$root/subB_r1.git" subB
  git -C "$root/parent/subA" remote add mirror "$root/subA_r2.git"
  git -C "$root/parent/subB" remote add mirror "$root/subB_r2.git"
  git -C "$root/parent" commit -qm "add submodules"
  mk_bare "$root/parent_r1.git"
  mk_bare "$root/parent_r2.git"
  git -C "$root/parent" remote add origin "$root/parent_r1.git"
  git -C "$root/parent" remote add mirror "$root/parent_r2.git"
  git -C "$root/parent" push -q origin main
  git -C "$root/parent" push -q mirror main
}

report_field() {  # report_field <json> <python-expr-on-d>  (d = loaded report dict)
  # eval() here is SAFE: the expression is always a literal string written in THIS test file
  # (never external/untrusted input -- every call site below passes a fixed Python expression),
  # used only to project a field out of a repo_verify.py JSON report for a bash-side assertion.
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2]))
" "$1" "$2"
}

run_tool() {  # run_tool <root> <out.json>  -> exit code via $?; stdout/stderr captured to $TMP/tool.out / $TMP/tool.err
  python3 "$TOOL" --recursive --root "$1" --out "$2" >"$TMP/tool.out" 2>"$TMP/tool.err"
}

run_tool_cfg() {  # run_tool_cfg <root> <out.json> <remotes-config.json>
  python3 "$TOOL" --recursive --root "$1" --out "$2" --remotes-config "$3" >"$TMP/tool.out" 2>"$TMP/tool.err"
}

tree_hash() {  # tree_hash <dir> -> one aggregate hash over every file's path+content under <dir>
  find "$1" -type f -print0 2>/dev/null | sort -z | xargs -0 md5sum 2>/dev/null | md5sum | awk '{print $1}'
}

real_gitdir() {  # real_gitdir <repo_path> -> absolute, REAL git-dir path (resolves a submodule's
                  # own ".git" FILE indirection to its true location under the parent's
                  # .git/modules/..., so a whole-tree hash of a submodule's OWN git-dir actually
                  # hashes its object store/refs, not a one-line gitdir-pointer file).
  local d
  d=$(git -C "$1" rev-parse --git-dir 2>/dev/null)
  case "$d" in
    /*) echo "$d" ;;
    *) echo "$1/$d" ;;
  esac
}

# mk_mutant <mutant_subdir_name> <old_marker_file> <new_marker_file> -> builds a throwaway copy of
# the whole fastcycle verify/ + lib/ tree at $TMP/<mutant_subdir_name>, with repo_verify.py's
# content replaced by applying the exact (old_text -> new_text) substitution read from the two
# given files (so each call site writes its old/new strings into real files instead of fighting
# bash/heredoc quoting of Python literals containing single quotes). Exits nonzero (and prints
# MUTATION_ANCHOR_MISSING) if the old text is not found verbatim in the current source -- the
# same anchor-drift detection the pre-existing paired mutation above already uses.
mk_mutant() {
  local name="$1" oldf="$2" newf="$3"
  local dir="$TMP/$name"
  mkdir -p "$dir/verify" "$dir/lib"
  cp "$FC/lib/fc_common.py" "$dir/lib/fc_common.py"
  python3 - "$TOOL" "$dir/verify/repo_verify.py" "$oldf" "$newf" <<'PY'
import sys
src, dst, oldf, newf = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src, encoding="utf-8").read()
old = open(oldf, encoding="utf-8").read()
new = open(newf, encoding="utf-8").read()
if old not in s:
    print("MUTATION_ANCHOR_MISSING", file=sys.stderr)
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
}

# ------------------------------------------------------------------------------ rv_good_clean --
G="$TMP/rv_good_clean"
build_good_clean "$G"
run_tool "$G/parent" "$TMP/good.json"; GRC=$?
if [ "$GRC" -eq 0 ] && [ "$(report_field "$TMP/good.json" 'd["overall"]')" = "CLEAN" ]; then
  ok "rv_good_clean: exit 0, overall CLEAN (parent + 2 submodules, 2 remotes each, all pushed)"
else
  not_ok "rv_good_clean: expected exit 0 / overall CLEAN, got rc=$GRC overall=$(report_field "$TMP/good.json" 'd.get("overall")' 2>/dev/null)"
  cat "$TMP/tool.err" >&2
fi
REPOS_OK=$(report_field "$TMP/good.json" 'sorted(r["path"] for r in d["repos"])' 2>/dev/null)
if [ "$REPOS_OK" = "['.', 'subA', 'subB']" ]; then
  ok "rv_good_clean: report lists main + both submodules, path-sorted"
else
  not_ok "rv_good_clean: expected repos ['.', 'subA', 'subB'], got $REPOS_OK"
fi

# ------------------------------------------------------------------------ rv_bad_dirty_submodule
D="$TMP/rv_bad_dirty_submodule"
build_good_clean "$D"
echo "dirty change" >>"$D/parent/subB/f.txt"
run_tool "$D/parent" "$TMP/dirty.json"; DRC=$?
DOVERALL=$(report_field "$TMP/dirty.json" 'd.get("overall")' 2>/dev/null)
DSUBB_REASONS=$(report_field "$TMP/dirty.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subB")' 2>/dev/null)
DSUBB_DIRTY=$(report_field "$TMP/dirty.json" 'next(r["dirty_entries"] for r in d["repos"] if r["path"]=="subB")' 2>/dev/null)
if [ "$DRC" -eq 1 ] && [ "$DOVERALL" = "NOT_CLEAN" ] && [ "$DSUBB_REASONS" = "['DIRTY_TREE']" ] && [ "$DSUBB_DIRTY" = "['f.txt']" ]; then
  ok "rv_bad_dirty_submodule: exit 1, overall NOT_CLEAN, subB DIRTY_TREE naming f.txt"
else
  not_ok "rv_bad_dirty_submodule: rc=$DRC overall=$DOVERALL subB.reasons=$DSUBB_REASONS subB.dirty=$DSUBB_DIRTY"
fi
DPARENT_REASONS=$(report_field "$TMP/dirty.json" 'next(r["reasons"] for r in d["repos"] if r["path"]==".")' 2>/dev/null)
case "$DPARENT_REASONS" in
  *DIRTY_TREE*) ok "rv_bad_dirty_submodule: parent also NOT_CLEAN (RV-002 --ignore-submodules=none reports the modified gitlink)" ;;
  *) not_ok "rv_bad_dirty_submodule: parent reasons expected to include DIRTY_TREE, got $DPARENT_REASONS" ;;
esac

# -------------------------------------------------------------------------- rv_bad_lagging_remote
L="$TMP/rv_bad_lagging_remote"
mk_repo "$L/repo"
echo one >"$L/repo/f.txt"
git -C "$L/repo" add -A; git -C "$L/repo" commit -qm c1
mk_bare "$L/remoteA.git"; mk_bare "$L/remoteB.git"
git -C "$L/repo" remote add remoteA "$L/remoteA.git"
git -C "$L/repo" remote add remoteB "$L/remoteB.git"
git -C "$L/repo" push -q remoteA main
git -C "$L/repo" push -q remoteB main
echo two >"$L/repo/f.txt"
git -C "$L/repo" commit -qam c2
git -C "$L/repo" push -q remoteA main   # remoteB deliberately NOT pushed -> lags by 1 commit
run_tool "$L/repo" "$TMP/lag.json"; LRC=$?
LOVERALL=$(report_field "$TMP/lag.json" 'd.get("overall")' 2>/dev/null)
LREASONS=$(report_field "$TMP/lag.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
LUNPUSHED_B=$(report_field "$TMP/lag.json" 'd["repos"][0]["unpushed"]["remoteB"]' 2>/dev/null)
LOCAL_SHA=$(git -C "$L/repo" rev-parse HEAD)
REMOTEB_SHA=$(git -C "$L/remoteB.git" rev-parse main)
LREMOTEB_TIP=$(report_field "$TMP/lag.json" 'next(rm["remote_tip"] for rm in d["repos"][0]["remotes"] if rm["name"]=="remoteB")' 2>/dev/null)
LREMOTEB_LOCAL=$(report_field "$TMP/lag.json" 'next(rm["local_tip"] for rm in d["repos"][0]["remotes"] if rm["name"]=="remoteB")' 2>/dev/null)
if [ "$LRC" -eq 1 ] && [ "$LOVERALL" = "NOT_CLEAN" ] && [ "$LREASONS" = "['REMOTE_TIP_DIFFERS']" ] \
   && [ "$LUNPUSHED_B" = "1" ] && [ "$LREMOTEB_TIP" = "$REMOTEB_SHA" ] && [ "$LREMOTEB_LOCAL" = "$LOCAL_SHA" ]; then
  ok "rv_bad_lagging_remote: exit 1, REMOTE_TIP_DIFFERS on remoteB, both real SHAs, unpushed=1"
else
  not_ok "rv_bad_lagging_remote: rc=$LRC overall=$LOVERALL reasons=$LREASONS unpushed_B=$LUNPUSHED_B tip=$LREMOTEB_TIP/$REMOTEB_SHA local=$LREMOTEB_LOCAL/$LOCAL_SHA"
fi

# -------------------------------------------------------------------------- rv_bad_rejected_push
RJ="$TMP/rv_bad_rejected_push"
mk_repo "$RJ/repo"
echo one >"$RJ/repo/f.txt"
git -C "$RJ/repo" add -A; git -C "$RJ/repo" commit -qm c1
mk_bare "$RJ/remote.git"
git -C "$RJ/repo" remote add origin "$RJ/remote.git"
git -C "$RJ/repo" push -q origin main
GD=$(git -C "$RJ/repo" rev-parse --git-dir); case "$GD" in /*) ;; *) GD="$RJ/repo/$GD" ;; esac
python3 -c "
import json
json.dump({'remotes': {'origin': {'result': 'REJECTED', 'message': 'non-fast-forward (simulated)'}}}, open('$GD/fastcycle_push_log.json', 'w'))
"
run_tool "$RJ/repo" "$TMP/rejected.json"; RJRC=$?
RJOVERALL=$(report_field "$TMP/rejected.json" 'd.get("overall")' 2>/dev/null)
RJREASONS=$(report_field "$TMP/rejected.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
RJLASTPUSH=$(report_field "$TMP/rejected.json" 'd["repos"][0]["remotes"][0]["last_push_result"]' 2>/dev/null)
if [ "$RJRC" -eq 1 ] && [ "$RJOVERALL" = "NOT_CLEAN" ] && [ "$RJREASONS" = "['REMOTE_REJECTED_LAST_PUSH']" ] \
   && [ "$RJLASTPUSH" = "REJECTED(non-fast-forward (simulated))" ]; then
  ok "rv_bad_rejected_push: exit 1, NOT_CLEAN with REMOTE_REJECTED_LAST_PUSH even though tips are equal (RV-005)"
else
  not_ok "rv_bad_rejected_push: rc=$RJRC overall=$RJOVERALL reasons=$RJREASONS last_push=$RJLASTPUSH"
fi

# ------------------------------------------------------------------------ rv_bad_uninit_submodule
U="$TMP/rv_bad_uninit_submodule"
build_good_clean "$U"
rm -rf "$U/parent/subA"
git -C "$U/parent" checkout -q -- subA
run_tool "$U/parent" "$TMP/uninit.json"; URC=$?
UOVERALL=$(report_field "$TMP/uninit.json" 'd.get("overall")' 2>/dev/null)
USUBA_REASONS=$(report_field "$TMP/uninit.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
if [ "$URC" -eq 1 ] && [ "$UOVERALL" = "NOT_CLEAN" ] && [ "$USUBA_REASONS" = "['SUBMODULE_UNINITIALISED']" ]; then
  ok "rv_bad_uninit_submodule: exit 1, subA SUBMODULE_UNINITIALISED"
else
  not_ok "rv_bad_uninit_submodule: rc=$URC overall=$UOVERALL subA.reasons=$USUBA_REASONS"
fi

# -------------------------------------------------------------------- rv_bad_unfetchable_pointer
P="$TMP/rv_bad_unfetchable_pointer"
build_good_clean "$P"
echo "never pushed" >"$P/parent/subB/f.txt"
git -C "$P/parent/subB" commit -qam "never pushed commit"
git -C "$P/parent" add subB
git -C "$P/parent" commit -qm "bump subB to unpushed commit"
run_tool "$P/parent" "$TMP/unfetch.json"; PRC=$?
POVERALL=$(report_field "$TMP/unfetch.json" 'd.get("overall")' 2>/dev/null)
PSUBB_REASONS=$(report_field "$TMP/unfetch.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subB")' 2>/dev/null)
if [ "$PRC" -eq 1 ] && [ "$POVERALL" = "NOT_CLEAN" ]; then
  case "$PSUBB_REASONS" in
    *POINTER_UNFETCHABLE*) ok "rv_bad_unfetchable_pointer: exit 1, subB reasons include POINTER_UNFETCHABLE ($PSUBB_REASONS)" ;;
    *) not_ok "rv_bad_unfetchable_pointer: subB reasons expected to include POINTER_UNFETCHABLE, got $PSUBB_REASONS" ;;
  esac
else
  not_ok "rv_bad_unfetchable_pointer: rc=$PRC overall=$POVERALL subB.reasons=$PSUBB_REASONS"
fi

# ------------------------------------------------------------------------------- rv_blind_remote
B="$TMP/rv_blind_remote"
build_good_clean "$B"
git -C "$B/parent" remote set-url mirror "$B/no/such/remote.git"
run_tool "$B/parent" "$TMP/blind.json"; BRC=$?
BOVERALL=$(report_field "$TMP/blind.json" 'd.get("overall")' 2>/dev/null)
if [ "$BRC" -eq 4 ] && [ "$BOVERALL" = "UNVERIFIED" ]; then
  ok "rv_blind_remote: exit 4, overall UNVERIFIED (never CLEAN)"
else
  not_ok "rv_blind_remote: expected rc=4 overall=UNVERIFIED, got rc=$BRC overall=$BOVERALL"
fi
BBLIND_FLAG=$(report_field "$TMP/blind.json" 'd.get("BLIND")' 2>/dev/null)
if [ "$BBLIND_FLAG" = "True" ]; then
  ok "rv_blind_remote: report body carries BLIND:true (C-001 code-4 convention)"
else
  not_ok "rv_blind_remote: expected BLIND:true in the written report, got $BBLIND_FLAG"
fi

# -------------------------------------------------------------------------- rv_negctrl_ignored_file
N="$TMP/rv_negctrl_ignored_file"
build_good_clean "$N"
echo "*.ignored" >"$N/parent/.gitignore"
git -C "$N/parent" add .gitignore
git -C "$N/parent" commit -qm "add gitignore"
git -C "$N/parent" push -q origin main
git -C "$N/parent" push -q mirror main
echo secret >"$N/parent/foo.ignored"
run_tool "$N/parent" "$TMP/negctrl.json"; NRC=$?
NOVERALL=$(report_field "$TMP/negctrl.json" 'd.get("overall")' 2>/dev/null)
if [ "$NRC" -eq 0 ] && [ "$NOVERALL" = "CLEAN" ]; then
  ok "rv_negctrl_ignored_file: a gitignored file does NOT make the tree read dirty (exit 0, CLEAN)"
else
  not_ok "rv_negctrl_ignored_file: expected rc=0 overall=CLEAN, got rc=$NRC overall=$NOVERALL"
fi

# ------------------------------------------------------------------------------- rv_determinism
run_tool "$G/parent" "$TMP/det1.json"; D1RC=$?
run_tool "$G/parent" "$TMP/det2.json"; D2RC=$?
H1=$(report_field "$TMP/det1.json" 'd["body_hash"]' 2>/dev/null)
H2=$(report_field "$TMP/det2.json" 'd["body_hash"]' 2>/dev/null)
if [ "$D1RC" -eq 0 ] && [ "$D2RC" -eq 0 ] && [ -n "$H1" ] && [ "$H1" = "$H2" ]; then
  ok "rv_determinism: two independent runs on the same clean state produce an identical body_hash"
else
  not_ok "rv_determinism: rc1=$D1RC rc2=$D2RC hash1=$H1 hash2=$H2"
fi
python3 "$TOOL" --recursive --root "$G/parent" --out "$TMP/det3.json" --determinism-check >"$TMP/detcheck.out" 2>"$TMP/detcheck.err"
DCRC=$?
if [ "$DCRC" -eq 0 ]; then
  ok "rv_determinism: the tool's own --determinism-check flag exits 0 on the clean fixture"
else
  not_ok "rv_determinism: --determinism-check exited rc=$DCRC (expected 0): $(cat "$TMP/detcheck.err")"
fi

# -------------------------------------------------------------------------------- rv_no_mutation
NM="$TMP/rv_no_mutation"
build_good_clean "$NM"
before_refs=$(git -C "$NM/parent" for-each-ref)
before_status=$(git -C "$NM/parent" status --porcelain)
before_objs=$(git -C "$NM/parent" count-objects -v)
run_tool "$NM/parent" "$TMP/nomut.json"
after_refs=$(git -C "$NM/parent" for-each-ref)
after_status=$(git -C "$NM/parent" status --porcelain)
after_objs=$(git -C "$NM/parent" count-objects -v)
if [ "$before_refs" = "$after_refs" ] && [ "$before_status" = "$after_status" ] && [ "$before_objs" = "$after_objs" ]; then
  ok "rv_no_mutation: refs/status/objects byte-identical before and after (RV-009 read-only, no leftover temp refs)"
else
  not_ok "rv_no_mutation: repo state changed by a supposedly-read-only run"
  [ "$before_refs" = "$after_refs" ] || echo "     refs differ"
  [ "$before_status" = "$after_status" ] || echo "     status differs"
  [ "$before_objs" = "$after_objs" ] || echo "     object counts differ"
fi

# ================================================================================================
# T158 remediation round 1 -- new fixtures closing the reviewer's BLOCKING/IMPORTANT/MINOR gaps
# that the pre-existing 19-assertion suite (above) never exercised. Each block below empirically
# confirms a SPECIFIC fixed-defect scenario against the REAL, current tool (never a mutant) before
# the dedicated paired-mutation section further down re-uses these same fixtures to prove the fix
# is genuinely load-bearing (11.4.115(F)/11.4.201/11.4.194(6)(d)).
# ================================================================================================

# --------------------------------------------------------------------------------- rv_bad_untracked
# An UNTRACKED (never-added) file, as distinct from a MODIFIED tracked file -- no prior fixture in
# this suite ever produced the UNTRACKED_FILES reason directly (only indirectly, via self_check()'s
# own internal synthetic needle repo). Finding #7's own list of gaps names this explicitly.
UT="$TMP/rv_bad_untracked"
build_good_clean "$UT"
echo "stray" >"$UT/parent/stray_untracked.txt"
run_tool "$UT/parent" "$TMP/untracked.json"; UTRC=$?
UTOVERALL=$(report_field "$TMP/untracked.json" 'd.get("overall")' 2>/dev/null)
UTPARENT_REASONS=$(report_field "$TMP/untracked.json" 'next(r["reasons"] for r in d["repos"] if r["path"]==".")' 2>/dev/null)
UTPARENT_UNTRACKED=$(report_field "$TMP/untracked.json" 'next(r["untracked"] for r in d["repos"] if r["path"]==".")' 2>/dev/null)
if [ "$UTRC" -eq 1 ] && [ "$UTOVERALL" = "NOT_CLEAN" ] && [ "$UTPARENT_REASONS" = "['UNTRACKED_FILES']" ] \
   && [ "$UTPARENT_UNTRACKED" = "['stray_untracked.txt']" ]; then
  ok "rv_bad_untracked: exit 1, overall NOT_CLEAN, parent UNTRACKED_FILES naming stray_untracked.txt (finding #7: no prior fixture covered this reason directly)"
else
  not_ok "rv_bad_untracked: rc=$UTRC overall=$UTOVERALL parent.reasons=$UTPARENT_REASONS parent.untracked=$UTPARENT_UNTRACKED"
fi

# -------------------------------------------------------------------- rv_bad_remote_ahead (#6/#7a)
# A SECOND clone pushes a commit the first clone never fetched -- the remote's tip becomes a
# genuine DESCENDANT of local HEAD (REMOTE_AHEAD, never previously exercised by any fixture in this
# suite -- finding #7a's gap), and that new commit's OBJECT exists only on the remote + the second
# clone, never in the first clone's own object store -- forcing a REAL object transfer during
# repo_verify's own read-only live-tip fetch. This also strengthens rv_no_mutation against finding
# #6: the pre-existing rv_no_mutation fixture's objects were ALL already present locally, so it
# could never observe a leaked loose object / rewritten FETCH_HEAD.
AH="$TMP/rv_bad_remote_ahead"
mk_repo "$AH/repo"
echo one >"$AH/repo/f.txt"; git -C "$AH/repo" add -A; git -C "$AH/repo" commit -qm c1
mk_bare "$AH/remote.git"
git -C "$AH/repo" remote add origin "$AH/remote.git"
git -C "$AH/repo" push -q origin main
git clone -q "$AH/remote.git" "$AH/other_clone"
git -C "$AH/other_clone" config user.email fc@example.invalid
git -C "$AH/other_clone" config user.name fastcycle
echo two >"$AH/other_clone/f.txt"
git -C "$AH/other_clone" add -A
git -C "$AH/other_clone" commit -qm c2
git -C "$AH/other_clone" push -q origin main
AH_REMOTE_SHA=$(git -C "$AH/remote.git" rev-parse main)
# Confirm the fixture itself is set up as claimed BEFORE trusting any assertion about it
# (11.4.201/11.4.6/11.4.199): the new commit's object must be genuinely absent from repo's own
# store, or the "forces a real transfer" claim below is untested air.
if git -C "$AH/repo" cat-file -e "$AH_REMOTE_SHA" 2>/dev/null; then
  not_ok "rv_bad_remote_ahead: fixture setup bug -- repo already has the remote's new commit object locally; this fixture cannot force a real transfer"
else
  ok "rv_bad_remote_ahead: fixture control check -- the remote's new commit object is genuinely absent from repo's own object store before the run"
fi
AH_BEFORE_REFS=$(git -C "$AH/repo" for-each-ref)
AH_BEFORE_OBJS=$(git -C "$AH/repo" count-objects -v)
AH_GITDIR=$(real_gitdir "$AH/repo")
AH_BEFORE_TREEHASH=$(tree_hash "$AH_GITDIR")
run_tool "$AH/repo" "$TMP/ahead.json"; AHRC=$?
AH_AFTER_REFS=$(git -C "$AH/repo" for-each-ref)
AH_AFTER_OBJS=$(git -C "$AH/repo" count-objects -v)
AH_AFTER_TREEHASH=$(tree_hash "$AH_GITDIR")
AHOVERALL=$(report_field "$TMP/ahead.json" 'd.get("overall")' 2>/dev/null)
AHREASONS=$(report_field "$TMP/ahead.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
AHTIP=$(report_field "$TMP/ahead.json" 'next(rm["remote_tip"] for rm in d["repos"][0]["remotes"] if rm["name"]=="origin")' 2>/dev/null)
if [ "$AHRC" -eq 1 ] && [ "$AHOVERALL" = "NOT_CLEAN" ] && [ "$AHREASONS" = "['REMOTE_AHEAD']" ] && [ "$AHTIP" = "$AH_REMOTE_SHA" ]; then
  ok "rv_bad_remote_ahead: exit 1, overall NOT_CLEAN, REMOTE_AHEAD with the real remote SHA (no prior fixture ever produced this reason -- finding #7a's gap)"
else
  not_ok "rv_bad_remote_ahead: rc=$AHRC overall=$AHOVERALL reasons=$AHREASONS tip=$AHTIP/$AH_REMOTE_SHA"
fi
if [ "$AH_BEFORE_REFS" = "$AH_AFTER_REFS" ] && [ "$AH_BEFORE_OBJS" = "$AH_AFTER_OBJS" ] && [ "$AH_BEFORE_TREEHASH" = "$AH_AFTER_TREEHASH" ]; then
  ok "rv_no_mutation_remote_ahead (finding #6): refs/count-objects/whole-gitdir-tree-hash byte-identical even though a REAL never-locally-present object had to be fetched to compute REMOTE_AHEAD -- confirms the GIT_OBJECT_DIRECTORY scratch redirect, --no-write-fetch-head and GIT_OPTIONAL_LOCKS=0 fix actually holds under the one scenario that can force a genuine object transfer (the pre-existing rv_no_mutation fixture could never observe this: every object there was already local)"
else
  not_ok "rv_no_mutation_remote_ahead (finding #6): repo state changed by a supposedly-read-only run that had to fetch a real object"
  [ "$AH_BEFORE_REFS" = "$AH_AFTER_REFS" ] || echo "     refs differ"
  [ "$AH_BEFORE_OBJS" = "$AH_AFTER_OBJS" ] || { echo "     count-objects differs:"; echo "       before: $AH_BEFORE_OBJS"; echo "       after:  $AH_AFTER_OBJS"; }
  [ "$AH_BEFORE_TREEHASH" = "$AH_AFTER_TREEHASH" ] || echo "     whole-gitdir tree_hash differs ($AH_BEFORE_TREEHASH -> $AH_AFTER_TREEHASH)"
fi

# --------------------------------------------------------- rv_bad_detached_pointer_drift (#7b)
# A submodule whose checked-out HEAD has moved (and been pushed, so it is NOT unfetchable) without
# the PARENT's gitlink commit being bumped to match -- a genuine DETACHED_POINTER_DRIFT with no
# other submodule-local reason confounding it (RV-003's first half, never previously exercised by
# any fixture in this suite -- finding #7b's gap).
DR="$TMP/rv_bad_detached_pointer_drift"
build_good_clean "$DR"
echo "moved on" >"$DR/parent/subA/f.txt"
git -C "$DR/parent/subA" commit -qam "subA moves on without the parent noticing"
git -C "$DR/parent/subA" push -q origin main
git -C "$DR/parent/subA" push -q mirror main
# Deliberately do NOT `git -C "$DR/parent" add subA && commit` -- that is the whole point: the
# parent's last commit still names the OLD subA sha as its gitlink.
run_tool "$DR/parent" "$TMP/drift.json"; DRRC=$?
DROVERALL=$(report_field "$TMP/drift.json" 'd.get("overall")' 2>/dev/null)
DRSUBA_REASONS=$(report_field "$TMP/drift.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
DRSUBA_MATCHES=$(report_field "$TMP/drift.json" 'next(r["submodule_pointer_matches_checkout"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
if [ "$DRRC" -eq 1 ] && [ "$DROVERALL" = "NOT_CLEAN" ] && [ "$DRSUBA_REASONS" = "['DETACHED_POINTER_DRIFT']" ] && [ "$DRSUBA_MATCHES" = "False" ]; then
  ok "rv_bad_detached_pointer_drift: exit 1, overall NOT_CLEAN, subA DETACHED_POINTER_DRIFT alone (pushed, so not also POINTER_UNFETCHABLE/REMOTE_TIP_DIFFERS) -- no prior fixture ever exercised this reason (finding #7b's gap)"
else
  not_ok "rv_bad_detached_pointer_drift: rc=$DRRC overall=$DROVERALL subA.reasons=$DRSUBA_REASONS subA.matches=$DRSUBA_MATCHES"
fi

# ------------------------------------------------- rv_bad_unreachable_submodule_remote (#1, BLOCKING)
# Both of a submodule's remotes have gone away entirely -- the tool must read UNVERIFIED, NEVER
# NOT_CLEAN/POINTER_UNFETCHABLE: stating as fact that a commit is on no remote when it never
# actually reached any remote to check is a false NOT_CLEAN (11.4.201(1) FAIL-bluff). The original
# defect: a remote that could not be reached at all returned the SAME bare signal as a remote that
# was reached and genuinely rejected the SHA.
UR="$TMP/rv_bad_unreachable_submodule_remote"
build_good_clean "$UR"
mv "$UR/subA_r1.git" "$UR/subA_r1.git.gone"
mv "$UR/subA_r2.git" "$UR/subA_r2.git.gone"
run_tool "$UR/parent" "$TMP/unreach_sub.json"; URC2=$?
UROVERALL=$(report_field "$TMP/unreach_sub.json" 'd.get("overall")' 2>/dev/null)
URSUBA_STATUS=$(report_field "$TMP/unreach_sub.json" 'next(r["status"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
URSUBA_REASONS=$(report_field "$TMP/unreach_sub.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
URSUBB_STATUS=$(report_field "$TMP/unreach_sub.json" 'next(r["status"] for r in d["repos"] if r["path"]=="subB")' 2>/dev/null)
if [ "$URC2" -eq 4 ] && [ "$UROVERALL" = "UNVERIFIED" ] && [ "$URSUBA_STATUS" = "UNVERIFIED" ] \
   && [ "$URSUBA_REASONS" = "['REMOTE_UNREACHABLE']" ] && [ "$URSUBB_STATUS" = "CLEAN" ]; then
  ok "rv_bad_unreachable_submodule_remote: exit 4, overall UNVERIFIED, subA UNVERIFIED/REMOTE_UNREACHABLE (subB unaffected, still CLEAN) -- NEVER POINTER_UNFETCHABLE/NOT_CLEAN on an unreached remote (finding #1 BLOCKING fix)"
else
  not_ok "rv_bad_unreachable_submodule_remote: rc=$URC2 overall=$UROVERALL subA.status=$URSUBA_STATUS subA.reasons=$URSUBA_REASONS subB.status=$URSUBB_STATUS"
fi

# ----------------------------------------------------------------- rv_bad_push_url_lagging (#3)
# `git remote get-url` (no --push) only ever reads the FETCH url; a remote whose PUSH destination
# differs and lags behind must still be caught, never read CLEAN by coincidence because only the
# fetch URL happened to be checked (FR-020: "MUST NOT report clean when any remote rejected").
PU="$TMP/rv_bad_push_url_lagging"
mk_repo "$PU/repo"
echo one >"$PU/repo/f.txt"; git -C "$PU/repo" add -A; git -C "$PU/repo" commit -qm c1
mk_bare "$PU/fetch_target.git"
mk_bare "$PU/push_target.git"
git -C "$PU/repo" remote add origin "$PU/fetch_target.git"
git -C "$PU/repo" push -q origin main
git -C "$PU/repo" push -q "$PU/push_target.git" main   # push_target starts in sync too
echo two >"$PU/repo/f.txt"
git -C "$PU/repo" commit -qam c2
git -C "$PU/repo" push -q origin main   # only the FETCH url advances; push_target now lags by 1
git -C "$PU/repo" remote set-url --push origin "$PU/push_target.git"
PU_PUSHTGT_SHA=$(git -C "$PU/push_target.git" rev-parse main)
run_tool "$PU/repo" "$TMP/pushlag.json"; PURC=$?
PUOVERALL=$(report_field "$TMP/pushlag.json" 'd.get("overall")' 2>/dev/null)
PUREASONS=$(report_field "$TMP/pushlag.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
PU_PUSH_ENTRY_TIP=$(report_field "$TMP/pushlag.json" 'next((rm["remote_tip"] for rm in d["repos"][0]["remotes"] if rm["name"]=="origin:push"), "MISSING")' 2>/dev/null)
PU_FETCH_ENTRY_EQUAL=$(report_field "$TMP/pushlag.json" 'next(rm["equal"] for rm in d["repos"][0]["remotes"] if rm["name"]=="origin")' 2>/dev/null)
if [ "$PURC" -eq 1 ] && [ "$PUOVERALL" = "NOT_CLEAN" ] && [ "$PU_PUSH_ENTRY_TIP" = "$PU_PUSHTGT_SHA" ] && [ "$PU_FETCH_ENTRY_EQUAL" = "True" ]; then
  case "$PUREASONS" in
    *REMOTE_TIP_DIFFERS*|*REMOTE_AHEAD*)
      ok "rv_bad_push_url_lagging: exit 1 NOT_CLEAN -- the fetch URL alone reads equal ($PU_FETCH_ENTRY_EQUAL) but the real PUSH destination (origin:push) lags and is caught ($PUREASONS) -- finding #3 fix" ;;
    *) not_ok "rv_bad_push_url_lagging: expected a REMOTE_TIP_DIFFERS/REMOTE_AHEAD reason from the push-url check, got reasons=$PUREASONS" ;;
  esac
else
  not_ok "rv_bad_push_url_lagging: rc=$PURC overall=$PUOVERALL reasons=$PUREASONS push_entry_tip=$PU_PUSH_ENTRY_TIP/$PU_PUSHTGT_SHA fetch_equal=$PU_FETCH_ENTRY_EQUAL"
fi

# --------------------------------------------------------------------- rv_bad_zero_remotes (#4)
# A repo with NO remote configured at all proves nothing was ever pushed anywhere and must never
# read as vacuously CLEAN (FR-020 "zero unpushed commits").
ZR="$TMP/rv_bad_zero_remotes"
mk_repo "$ZR/repo"
echo one >"$ZR/repo/f.txt"; git -C "$ZR/repo" add -A; git -C "$ZR/repo" commit -qm c1
run_tool "$ZR/repo" "$TMP/zeroremotes.json"; ZRRC=$?
ZROVERALL=$(report_field "$TMP/zeroremotes.json" 'd.get("overall")' 2>/dev/null)
ZRREASONS=$(report_field "$TMP/zeroremotes.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
ZRREMOTES=$(report_field "$TMP/zeroremotes.json" 'd["repos"][0]["remotes"]' 2>/dev/null)
if [ "$ZRRC" -eq 1 ] && [ "$ZROVERALL" = "NOT_CLEAN" ] && [ "$ZRREASONS" = "['UNPUSHED_COMMITS']" ] && [ "$ZRREMOTES" = "[]" ]; then
  ok "rv_bad_zero_remotes: exit 1, overall NOT_CLEAN, UNPUSHED_COMMITS -- a repo with remotes:[] no longer reads vacuously CLEAN (finding #4 fix)"
else
  not_ok "rv_bad_zero_remotes: rc=$ZRRC overall=$ZROVERALL reasons=$ZRREASONS remotes=$ZRREMOTES"
fi

# ------------------------------------------------------------------- rv_remotes_config (#5)
# --remotes-config was previously accepted but never actually read (only existence-checked).
CFG_MISSING="$TMP/remotes_required_missing.json"
printf '{"required_remotes": ["upstream"]}' >"$CFG_MISSING"
run_tool_cfg "$G/parent" "$TMP/cfgbad.json" "$CFG_MISSING"; CFGBAD_RC=$?
CFGBAD_OVERALL=$(report_field "$TMP/cfgbad.json" 'd.get("overall")' 2>/dev/null)
CFGBAD_PARENT_REASONS=$(report_field "$TMP/cfgbad.json" 'next(r["reasons"] for r in d["repos"] if r["path"]==".")' 2>/dev/null)
if [ "$CFGBAD_RC" -eq 1 ] && [ "$CFGBAD_OVERALL" = "NOT_CLEAN" ] && [ "$CFGBAD_PARENT_REASONS" = "['UNPUSHED_COMMITS']" ]; then
  ok "rv_remotes_config: --remotes-config declaring a required remote ('upstream') that is configured NOWHERE in the clean fixture now correctly fails NOT_CLEAN/UNPUSHED_COMMITS (finding #5: the flag was previously accepted and silently discarded)"
else
  not_ok "rv_remotes_config (missing-required case): rc=$CFGBAD_RC overall=$CFGBAD_OVERALL parent.reasons=$CFGBAD_PARENT_REASONS"
fi
CFG_SATISFIED="$TMP/remotes_required_satisfied.json"
printf '{"required_remotes": ["origin"]}' >"$CFG_SATISFIED"
run_tool_cfg "$G/parent" "$TMP/cfggood.json" "$CFG_SATISFIED"; CFGGOOD_RC=$?
CFGGOOD_OVERALL=$(report_field "$TMP/cfggood.json" 'd.get("overall")' 2>/dev/null)
if [ "$CFGGOOD_RC" -eq 0 ] && [ "$CFGGOOD_OVERALL" = "CLEAN" ]; then
  ok "rv_remotes_config: --remotes-config declaring a required remote ('origin') that IS present on every repo in the clean fixture still reads CLEAN -- the config does not over-trigger (11.4.201(1) false-positive guard)"
else
  not_ok "rv_remotes_config (satisfied case): rc=$CFGGOOD_RC overall=$CFGGOOD_OVERALL"
fi

# --------------------------------------------------------- rv_submodule_name_with_space (#8)
# `.gitmodules` `--get-regexp` default output is ambiguous whenever a submodule NAME embeds a
# space; a plain split(" ", 1) then cuts the key/value boundary at the WRONG space.
SP="$TMP/rv_submodule_name_with_space"
mkdir -p "$SP"
mk_repo "$SP/sub_src"
echo "seed" >"$SP/sub_src/f.txt"
git -C "$SP/sub_src" add -A; git -C "$SP/sub_src" commit -qm "init sub"
mk_bare "$SP/sub_r1.git"
git -C "$SP/sub_src" remote add origin "$SP/sub_r1.git"
git -C "$SP/sub_src" push -q origin main
mk_repo "$SP/parent"
echo "parent-seed" >"$SP/parent/f.txt"
git -C "$SP/parent" add -A; git -C "$SP/parent" commit -qm "parent init"
git -C "$SP/parent" -c protocol.file.allow=always submodule add --name "my sub" -q "$SP/sub_r1.git" subdir
git -C "$SP/parent" commit -qm "add submodule with a spaced config name"
mk_bare "$SP/parent_r1.git"
git -C "$SP/parent" remote add origin "$SP/parent_r1.git"
git -C "$SP/parent" push -q origin main
run_tool "$SP/parent" "$TMP/spname.json"; SPRC=$?
SPOVERALL=$(report_field "$TMP/spname.json" 'd.get("overall")' 2>/dev/null)
SPREPOS=$(report_field "$TMP/spname.json" 'sorted(r["path"] for r in d["repos"])' 2>/dev/null)
if [ "$SPRC" -eq 0 ] && [ "$SPOVERALL" = "CLEAN" ] && [ "$SPREPOS" = "['.', 'subdir']" ]; then
  ok "rv_submodule_name_with_space: a submodule declared with a SPACE in its config NAME ('my sub', path 'subdir') parses correctly and is walked + reported CLEAN (finding #8: the old --get-regexp split(' ',1) parsing would have corrupted the path and left the real submodule un-walked)"
else
  not_ok "rv_submodule_name_with_space: rc=$SPRC overall=$SPOVERALL repos=$SPREPOS"
fi

# ----------------------------------------------------- rv_submodule_relative_remote_url (#9)
# The pointer-fetch probe previously ran with cwd=None, so a RELATIVE remote URL resolved against
# whatever directory happened to launch this whole tool, not the submodule's own location.
RU="$TMP/rv_submodule_relative_remote_url"
mkdir -p "$RU"
mk_repo "$RU/sub_src"
echo "seed" >"$RU/sub_src/f.txt"
git -C "$RU/sub_src" add -A; git -C "$RU/sub_src" commit -qm "init sub"
mk_bare "$RU/sub_r1.git"
git -C "$RU/sub_src" remote add origin "$RU/sub_r1.git"
git -C "$RU/sub_src" push -q origin main
mk_repo "$RU/parent"
echo "parent-seed" >"$RU/parent/f.txt"
git -C "$RU/parent" add -A; git -C "$RU/parent" commit -qm "parent init"
git -C "$RU/parent" -c protocol.file.allow=always submodule add -q "$RU/sub_r1.git" sub
git -C "$RU/parent" commit -qm "add submodule"
# Rewrite the submodule's OWN remote to a RELATIVE path (resolved against the submodule's own
# directory), matching the review's exact repro, instead of the absolute path `submodule add` wrote.
git -C "$RU/parent/sub" remote set-url origin "../../sub_r1.git"
mk_bare "$RU/parent_r1.git"
git -C "$RU/parent" remote add origin "$RU/parent_r1.git"
git -C "$RU/parent" push -q origin main
# Control check (11.4.6/11.4.199): confirm the relative URL genuinely resolves from the
# submodule's own directory via plain git BEFORE trusting any assertion about repo_verify's
# handling of it.
if git -C "$RU/parent/sub" ls-remote origin >/dev/null 2>&1; then
  ok "rv_submodule_relative_remote_url: control check -- plain 'git ls-remote origin' from the submodule's own directory resolves the relative url fine"
else
  not_ok "rv_submodule_relative_remote_url: control check FAILED -- the relative url does not even resolve via plain git from the submodule's own directory; fixture setup is broken"
fi
run_tool "$RU/parent" "$TMP/relurl.json"; RURC=$?
RUOVERALL=$(report_field "$TMP/relurl.json" 'd.get("overall")' 2>/dev/null)
RUSUB_REASONS=$(report_field "$TMP/relurl.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="sub")' 2>/dev/null)
if [ "$RURC" -eq 0 ] && [ "$RUOVERALL" = "CLEAN" ] && [ "$RUSUB_REASONS" = "[]" ]; then
  ok "rv_submodule_relative_remote_url: a submodule remote configured with a RELATIVE url reads CLEAN, no POINTER_UNFETCHABLE (finding #9: the pointer-fetch probe previously ran with cwd=None, resolving the relative url against the wrong directory)"
else
  not_ok "rv_submodule_relative_remote_url: rc=$RURC overall=$RUOVERALL sub.reasons=$RUSUB_REASONS"
fi

# ------------------------------------------------------------------------------ redact_url (MINOR)
# A real, confirmed credential-handling defect (11.4.10): the PREVIOUS ad-hoc regex leaked
# credential-fragment bytes for a userinfo containing an unescaped '/' or a second '@'.
RU_OUT=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("repo_verify", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cases = {
    "https://user:pa/ss@github.com/org/repo.git": "github.com/org/repo",
    "https://user:p@ss@github.com/org/repo.git": "github.com/org/repo",
    "https://gitlab.com/g/sub/repo.git": "gitlab.com/g/sub/repo",
}
ok = True
for url, expected in cases.items():
    out = m.redact_url(url)
    status = "OK" if out == expected else "MISMATCH"
    if out != expected:
        ok = False
    print("%s url=%r got=%r expected=%r" % (status, url, out, expected))
print("ALL_OK" if ok else "SOME_FAILED")
PY
)
while IFS= read -r ru_line; do printf '   %s\n' "$ru_line"; done <<<"$RU_OUT"
case "$RU_OUT" in
  *ALL_OK*) ok "redact_url: no credential fragment leaks for either reviewer-reported embedded-'/'-or-second-'@' URL, and a GitLab subgroup path is no longer truncated to its last two segments (MINOR credential-handling fix confirmed, 11.4.10)" ;;
  *) not_ok "redact_url: at least one case failed -- see output above" ;;
esac

# ------------------------------------------------------------------- rv_nonutf8_filename (MINOR)
# A filename containing an invalid-UTF8 byte previously raised an uncaught UnicodeDecodeError
# while decoding `git status`'s own captured stdout inside _run(), turning a reportable
# UNTRACKED_FILES finding into an opaque internal-error rc=4 with no report written at all. The
# errors="surrogateescape" fix applied to _run() in this round DOES close that specific crash
# (confirmed below: no raw Python traceback / UnicodeDecodeError) -- but HONESTLY, NOT THE WHOLE
# FINDING: the body still cannot be WRITTEN once it reaches fc_common.cmd_emit()'s own UTF-8-strict
# JSON encode step, which is a SEPARATE, SHARED library file (lib/fc_common.py, consumed by other
# fastcycle tools) and out of this task's scope to modify. This is a partial, honestly-stated
# improvement (opaque rc=4 traceback -> named, non-crashing rc=2 "not encodable" message), not a
# full fix -- this test pins the CURRENT behaviour so a future regression back to an unhandled
# traceback is caught, without overstating what this round actually resolved.
NU="$TMP/rv_nonutf8_filename"
mk_repo "$NU/repo"
echo seed >"$NU/repo/f.txt"; git -C "$NU/repo" add -A; git -C "$NU/repo" commit -qm c1
python3 -c "
import os
os.chdir('$NU/repo')
with open(b'bad-\xff-name.txt', 'wb') as fh:
    fh.write(b'x')
"
run_tool "$NU/repo" "$TMP/nonutf8.json"; NURC=$?
if grep -qi "Traceback\|UnicodeDecodeError" "$TMP/tool.err"; then
  not_ok "rv_nonutf8_filename: a filename with an invalid UTF-8 byte STILL raises a raw, uncaught Python exception -- the _run() errors=surrogateescape fix regressed"
else
  ok "rv_nonutf8_filename: a filename with an invalid UTF-8 byte no longer raises a raw UnicodeDecodeError inside _run() (the fix holds at that layer)"
fi
if [ "$NURC" -eq 2 ] && grep -q "not encodable as UTF-8" "$TMP/tool.err"; then
  ok "rv_nonutf8_filename: HONEST GAP pinned, not claimed fully resolved -- the tool still cannot WRITE a report for this fixture (rc=2, 'body not encodable as UTF-8') because the SHARED lib/fc_common.py JSON-encode path is UTF-8-strict; an improvement over the pre-fix opaque rc=4 crash, not a full fix, and fixing the shared library is out of this task's scope"
else
  not_ok "rv_nonutf8_filename: expected the documented rc=2/'not encodable as UTF-8' outcome, got rc=$NURC: $(cat "$TMP/tool.err")"
fi

# ------------------------------------------------------- rv_perf_pointer_probe (finding #2, BLOCKING)
# The ORIGINAL defect measured 111.9s/419MB for an unbounded full-history pointer-fetch probe
# against this repository's own real constitution submodule remote -- infeasible to reproduce with
# a fast, offline, local-bare-remote fixture (it needs a real large remote history; this is an
# HONEST, STATED limitation of this offline suite, 11.4.6). What IS verified offline: (a) the
# fix's exact flags are present in the real argument list the probe actually sends (not merely
# mentioned in a docstring), and (b) every real-submodule fixture in this suite, which exercises
# the identical probe code path, completes well inside budget -- and (c), reused from the same
# clean run, that RV-009's temp-ref sweep leaves no survivor warning on stderr.
if grep -q '"--depth=1", "--filter=tree:0"' "$TOOL"; then
  ok "rv_perf_pointer_probe: the depth/filter-limited pointer-fetch probe flags (finding #2 fix) are present in the real fetch argument list"
else
  not_ok "rv_perf_pointer_probe: expected '\"--depth=1\", \"--filter=tree:0\"' on the pointer-probe fetch argument list, not found in source -- possible regression to the unbounded full-history fetch"
fi
AH_T0=$(date +%s)
run_tool "$G/parent" "$TMP/good_timed.json"; TIMED_RC=$?
AH_T1=$(date +%s)
ELAPSED=$((AH_T1 - AH_T0))
if [ "$TIMED_RC" -eq 0 ] && [ "$ELAPSED" -le 30 ]; then
  ok "rv_perf_pointer_probe: a real multi-submodule tree verifies well within the 30s default timeout (elapsed=${ELAPSED}s) -- no regression to the unbounded-fetch behaviour that made CLEAN structurally unreachable before the fix"
else
  not_ok "rv_perf_pointer_probe: rc=$TIMED_RC elapsed=${ELAPSED}s exceeded the sanity budget -- possible regression to finding #2's unbounded full-history fetch"
fi
if grep -q "RV-009 WARNING" "$TMP/tool.err" 2>/dev/null; then
  not_ok "rv_perf_pointer_probe: unexpected RV-009 sweep-survivor WARNING on stderr for a clean run: $(cat "$TMP/tool.err")"
else
  ok "rv_perf_pointer_probe: no RV-009 temp-ref sweep-survivor WARNING on stderr (the re-verified for-each-ref sweep found nothing left behind, MINOR fix confirmed)"
fi


# ---------------------------------------------------------------------------- Paired mutation --
# C-005: a paired mutation of the tool's own detection logic that flips a golden-bad fixture to
# exit 0. Contract's own words: "map UNREACHABLE to equal=true => rv_blind_remote returns CLEAN;
# meta-test must catch" (T164 registers this in scripts/testing/meta_test_false_positive_proof.sh
# -- a separate, later task; this file demonstrates + OBSERVES the flip, per this task's own
# [TDD] Test Discipline obligation to ship the mutation and show it is genuinely load-bearing).
MUTDIR="$TMP/mutant_tree"
mkdir -p "$MUTDIR/verify" "$MUTDIR/lib"
cp "$FC/lib/fc_common.py" "$MUTDIR/lib/fc_common.py"
python3 - "$TOOL" "$MUTDIR/verify/repo_verify.py" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
old = '''    if tip is None:
        return {
            "name": out_name, "url_redacted": url_redacted, "remote_tip": "UNREACHABLE",
            "local_tip": local_tip, "equal": False, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_reachable": False, "_detail": err,
        }, "REMOTE_UNREACHABLE"'''
new = '''    if tip is None:
        return {
            "name": out_name, "url_redacted": url_redacted, "remote_tip": "UNREACHABLE",
            "local_tip": local_tip, "equal": True, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_reachable": False, "_detail": err,
        }, None  # PAIRED MUTATION (contract: "map UNREACHABLE to equal=true")'''
if old not in s:
    print("MUTATION_ANCHOR_MISSING", file=sys.stderr)
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
MUT_APPLY_RC=$?
if [ "$MUT_APPLY_RC" -ne 0 ]; then
  not_ok "paired mutation: anchor text for the UNREACHABLE/equal branch was not found in repo_verify.py -- the source moved; update this test's anchor"
else
  python3 "$MUTDIR/verify/repo_verify.py" --recursive --root "$B/parent" --out "$TMP/mutant_blind.json" >"$TMP/mutant.out" 2>"$TMP/mutant.err"
  MUTRC=$?
  MUTOVERALL=$(report_field "$TMP/mutant_blind.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTRC" -eq 0 ] && [ "$MUTOVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT: the SAME rv_blind_remote fixture, run through the mutated"
    echo "   equal-mapping logic, wrongly reports exit 0 / CLEAN -- confirms this fixture and"
    echo "   the real tool's REMOTE_UNREACHABLE handling are both genuinely load-bearing"
  else
    not_ok "paired mutation: expected the mutant to wrongly report rc=0/CLEAN on rv_blind_remote, got rc=$MUTRC overall=$MUTOVERALL -- the mutation may not be load-bearing (or the golden-bad fixture doesn't exercise this code path)"
  fi
fi

# ================================================================================================
# Additional paired mutations (T158 remediation round 1, finding #7: three reviewer-authored
# mutations the author's own pre-existing suite never caught, PLUS the plan's own T-G06 mutation).
# Each uses mk_mutant()'s file-based old/new substitution (never inline Python-literal heredoc
# quoting, which is exactly what mk_mutant exists to avoid) and re-uses the fixtures built above so
# every mutant is exercised against a REAL repo this suite already built, never a synthetic no-op.
# ================================================================================================

MUTMARK="$TMP/mutmark"
mkdir -p "$MUTMARK"

# ---- finding #7a: REMOTE_AHEAD -> None (no fixture previously produced REMOTE_AHEAD at all) ----
cat >"$MUTMARK/ahead_old.txt" <<'EOF'
    elif _is_ancestor(repo_path, local_tip, tip, timeout_s, extra_env=extra_env):
        reason = "REMOTE_AHEAD"  # remote has commits local lacks
EOF
cat >"$MUTMARK/ahead_new.txt" <<'EOF'
    elif _is_ancestor(repo_path, local_tip, tip, timeout_s, extra_env=extra_env):
        reason = None  # PAIRED MUTATION (T158 remediation finding #7a: REMOTE_AHEAD -> None)
EOF
if mk_mutant "mutant_ahead" "$MUTMARK/ahead_old.txt" "$MUTMARK/ahead_new.txt" 2>"$TMP/mutant_ahead.err"; then
  python3 "$TMP/mutant_ahead/verify/repo_verify.py" --recursive --root "$AH/repo" --out "$TMP/mutant_ahead.json" >"$TMP/mutant_ahead.out" 2>>"$TMP/mutant_ahead.err"
  MUTAH_RC=$?
  MUTAH_OVERALL=$(report_field "$TMP/mutant_ahead.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTAH_RC" -eq 0 ] && [ "$MUTAH_OVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT (finding #7a): mapping REMOTE_AHEAD -> None makes the SAME rv_bad_remote_ahead fixture wrongly report CLEAN -- confirms rv_bad_remote_ahead and the REMOTE_AHEAD branch are both genuinely load-bearing"
  else
    not_ok "paired mutation (finding #7a): expected the mutant to wrongly report rc=0/CLEAN on rv_bad_remote_ahead, got rc=$MUTAH_RC overall=$MUTAH_OVERALL"
  fi
else
  not_ok "paired mutation (finding #7a): mutation anchor text not found in repo_verify.py -- source moved, update this test's anchor: $(cat "$TMP/mutant_ahead.err")"
fi

# ---- T-G06 (plan's own specified mutation): ignore remote tips entirely -> lagging fixture FAILs
cat >"$MUTMARK/ignoretips_old.txt" <<'EOF'
    last_push_str = _push_result_str(push_log_entry)
    tip, err = _remote_head_tip(repo_path, git_target, branch, timeout_s)
EOF
cat >"$MUTMARK/ignoretips_new.txt" <<'EOF'
    last_push_str = _push_result_str(push_log_entry)
    tip, err = local_tip, None  # PAIRED MUTATION (T-G06: ignore remote tips entirely)
EOF
if mk_mutant "mutant_ignoretips" "$MUTMARK/ignoretips_old.txt" "$MUTMARK/ignoretips_new.txt" 2>"$TMP/mutant_ignoretips.err"; then
  python3 "$TMP/mutant_ignoretips/verify/repo_verify.py" --recursive --root "$L/repo" --out "$TMP/mutant_ignoretips.json" >"$TMP/mutant_ignoretips.out" 2>>"$TMP/mutant_ignoretips.err"
  MUTIT_RC=$?
  MUTIT_OVERALL=$(report_field "$TMP/mutant_ignoretips.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTIT_RC" -eq 0 ] && [ "$MUTIT_OVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT (T-G06): ignoring remote tips entirely makes the SAME rv_bad_lagging_remote fixture wrongly report CLEAN -- confirms the plan's own specified mutation is load-bearing"
  else
    not_ok "paired mutation (T-G06): expected the mutant to wrongly report rc=0/CLEAN on rv_bad_lagging_remote, got rc=$MUTIT_RC overall=$MUTIT_OVERALL"
  fi
else
  not_ok "paired mutation (T-G06): mutation anchor text not found in repo_verify.py -- source moved, update this test's anchor: $(cat "$TMP/mutant_ignoretips.err")"
fi

# ---- finding #7b: DETACHED_POINTER_DRIFT comparison forced True (no drift fixture previously existed)
cat >"$MUTMARK/drift_old.txt" <<'EOF'
    pointer_matches = True
    if is_submodule and parent_gitlink is not None:
        pointer_matches = (parent_gitlink == head)
        if not pointer_matches:
            reasons.append("DETACHED_POINTER_DRIFT")
EOF
cat >"$MUTMARK/drift_new.txt" <<'EOF'
    pointer_matches = True
    if is_submodule and parent_gitlink is not None:
        pointer_matches = True  # PAIRED MUTATION (finding #7b: comparison forced True)
        if not pointer_matches:
            reasons.append("DETACHED_POINTER_DRIFT")
EOF
if mk_mutant "mutant_drift" "$MUTMARK/drift_old.txt" "$MUTMARK/drift_new.txt" 2>"$TMP/mutant_drift.err"; then
  python3 "$TMP/mutant_drift/verify/repo_verify.py" --recursive --root "$DR/parent" --out "$TMP/mutant_drift.json" >"$TMP/mutant_drift.out" 2>>"$TMP/mutant_drift.err"
  MUTDR_SUBA_STATUS=$(report_field "$TMP/mutant_drift.json" 'next(r["status"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
  MUTDR_SUBA_REASONS=$(report_field "$TMP/mutant_drift.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="subA")' 2>/dev/null)
  if [ "$MUTDR_SUBA_STATUS" = "CLEAN" ] && [ "$MUTDR_SUBA_REASONS" = "[]" ]; then
    ok "paired mutation CAUGHT (finding #7b): forcing the pointer-matches comparison to always True makes subA on the SAME rv_bad_detached_pointer_drift fixture wrongly report CLEAN/[] -- confirms this fixture and the comparison are both genuinely load-bearing"
  else
    not_ok "paired mutation (finding #7b): expected subA to wrongly report status=CLEAN reasons=[] under the mutant, got status=$MUTDR_SUBA_STATUS reasons=$MUTDR_SUBA_REASONS"
  fi
else
  not_ok "paired mutation (finding #7b): mutation anchor text not found in repo_verify.py -- source moved, update this test's anchor: $(cat "$TMP/mutant_drift.err")"
fi

# ---- finding #7c: self_check() gutted -- a TWO-MUTANT comparison (11.4.194(6)(d)): Mutant X
# breaks worktree_status() ALONE (self_check() intact) and MUST be caught at rc=3 by the tool's
# own control needle before any fixture is even processed; Mutant Y applies the SAME break PLUS
# guts self_check() to `return None`, and MUST let the identical break escape undetected, letting
# the genuinely-dirty rv_bad_untracked fixture wrongly report CLEAN. The pair together proves
# self_check() is genuinely load-bearing, not decorative -- a single "gut it and see nothing
# changes on the clean fixture" check would prove nothing, since self_check() is never SUPPOSED to
# fire on a healthy installation.
cat >"$MUTMARK/wtbroken_old.txt" <<'EOF'
    return True, sorted(dirty), sorted(untracked)
EOF
cat >"$MUTMARK/wtbroken_new.txt" <<'EOF'
    return True, [], []  # MUTATION: worktree_status always reports clean regardless of real state
EOF
cat >"$MUTMARK/selfcheck_gut_old.txt" <<'EOF'
def self_check(timeout_s):
    """Contract exit 3: prove worktree_status() genuinely SEES, before trusting any real finding
    (constitution 11.4.201/11.4.273). Returns None on success, else a diagnostic string."""
    with tempfile.TemporaryDirectory(prefix="fc_repo_verify_selfcheck_") as tmp:
EOF
cat >"$MUTMARK/selfcheck_gut_new.txt" <<'EOF'
def self_check(timeout_s):
    """Contract exit 3: prove worktree_status() genuinely SEES, before trusting any real finding
    (constitution 11.4.201/11.4.273). Returns None on success, else a diagnostic string."""
    return None  # PAIRED MUTATION (finding #7c: self_check gutted, needle checks never run)
    with tempfile.TemporaryDirectory(prefix="fc_repo_verify_selfcheck_") as tmp:
EOF

if mk_mutant "mutant_wtbroken_only" "$MUTMARK/wtbroken_old.txt" "$MUTMARK/wtbroken_new.txt" 2>"$TMP/mutant_wtbroken_only.err"; then
  python3 "$TMP/mutant_wtbroken_only/verify/repo_verify.py" --recursive --root "$UT/parent" --out "$TMP/mutant_wtbroken_only.json" >"$TMP/mutant_wtbroken_only.out" 2>"$TMP/mutant_wtbroken_only.err"
  MUTWX_RC=$?
  if [ "$MUTWX_RC" -eq 3 ] && grep -q "self-check FAILED" "$TMP/mutant_wtbroken_only.err"; then
    ok "self_check control (finding #7c, step 1/2): with worktree_status() broken but self_check() INTACT, the tool's OWN control needle catches the break at rc=3 before producing any report -- self_check() genuinely works when present"
  else
    not_ok "self_check control (finding #7c, step 1/2): expected rc=3 with a 'self-check FAILED' message when worktree_status() is broken and self_check() is intact, got rc=$MUTWX_RC: $(cat "$TMP/mutant_wtbroken_only.err")"
  fi
else
  not_ok "self_check control (finding #7c, step 1/2): mutation anchor (worktree_status break) not found -- source moved: $(cat "$TMP/mutant_wtbroken_only.err")"
fi

mkdir -p "$TMP/mutant_both/verify" "$TMP/mutant_both/lib"
cp "$FC/lib/fc_common.py" "$TMP/mutant_both/lib/fc_common.py"
python3 - "$TOOL" "$TMP/mutant_both/verify/repo_verify.py" "$MUTMARK/wtbroken_old.txt" "$MUTMARK/wtbroken_new.txt" "$MUTMARK/selfcheck_gut_old.txt" "$MUTMARK/selfcheck_gut_new.txt" <<'PY'
import sys
src, dst, o1, n1, o2, n2 = sys.argv[1:7]
s = open(src, encoding="utf-8").read()
old1 = open(o1, encoding="utf-8").read(); new1 = open(n1, encoding="utf-8").read()
old2 = open(o2, encoding="utf-8").read(); new2 = open(n2, encoding="utf-8").read()
if old1 not in s:
    print("MUTATION_ANCHOR_MISSING: worktree_status break", file=sys.stderr); sys.exit(1)
s = s.replace(old1, new1)
if old2 not in s:
    print("MUTATION_ANCHOR_MISSING: self_check gut", file=sys.stderr); sys.exit(1)
s = s.replace(old2, new2)
open(dst, "w", encoding="utf-8").write(s)
PY
MUTBOTH_APPLY_RC=$?
if [ "$MUTBOTH_APPLY_RC" -ne 0 ]; then
  not_ok "self_check control (finding #7c, step 2/2): double-mutation anchor text not found -- source moved, update this test's anchors"
else
  python3 "$TMP/mutant_both/verify/repo_verify.py" --recursive --root "$UT/parent" --out "$TMP/mutant_both.json" >"$TMP/mutant_both.out" 2>"$TMP/mutant_both.err"
  MUTBOTH_RC=$?
  MUTBOTH_OVERALL=$(report_field "$TMP/mutant_both.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTBOTH_RC" -eq 0 ] && [ "$MUTBOTH_OVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT (finding #7c): gutting self_check() lets the SAME broken worktree_status() escape undetected (no rc=3) and the genuinely-dirty rv_bad_untracked fixture wrongly reports CLEAN -- confirms self_check()'s control needle is genuinely load-bearing, not a decorative check"
  else
    not_ok "paired mutation (finding #7c): expected the double-mutant to wrongly report rc=0/CLEAN on rv_bad_untracked (self_check no longer catches the break), got rc=$MUTBOTH_RC overall=$MUTBOTH_OVERALL"
  fi
fi


[ "$fail" -eq 0 ] && exit 0 || exit 1
