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


# ================================================================================================
# T158 remediation round 2 -- new fixtures/mutations closing the SECOND independent review's
# BLOCKING (B1) + IMPORTANT (I1, I2, I3) findings, plus the MINOR redact_url query-string leak.
# Round 1's own 24 assertions above (+ its mutations) are UNTOUCHED and must all stay GREEN.
# ================================================================================================

MUTMARK2="$TMP/mutmark2"
mkdir -p "$MUTMARK2"

# ---------------------------------------------------------- rv_bad_pointer_probe_timeout (B1, repro a)
# A submodule's pointer-probe fetch call specifically times out (the EARLIER ls-remote/fetch calls
# for the SAME remote already succeeded) -- the probe's own `rc=None` MUST map to UNVERIFIED, never
# to UNFETCHABLE/NOT_CLEAN (B1's original defect: ANY nonzero/timeout fell through to the same bare
# "rejected" bucket as a genuine "not our ref"). A `GIT_SSH_COMMAND` wrapper counts real (non "-G")
# ssh invocations and sleeps forever on the 2nd one -- empirically confirmed (2026-09-30, this
# round): for a submodule whose checked-out HEAD already equals the remote tip, verify_remote's own
# bare-SHA fetch of an ALREADY-LOCALLY-PRESENT object is a genuine git no-network-round-trip
# short-circuit (git never contacts the remote at all when it already has the exact object), so the
# real per-submodule ssh-invocation sequence is ls-remote (1st) then the pointer-probe's OWN fetch
# (2nd) -- never a 3rd call for this scenario -- confirmed by directly tracing every `_run()` call
# this tool makes against this exact fixture before writing this assertion (11.4.199/11.4.6: never
# assumed from the contract prose alone).
PPT="$TMP/rv_bad_pointer_probe_timeout"
mkdir -p "$PPT"
mk_repo "$PPT/sub_src"
echo "seed" >"$PPT/sub_src/f.txt"
git -C "$PPT/sub_src" add -A; git -C "$PPT/sub_src" commit -qm "init sub"
mk_bare "$PPT/sub_remote.git"
cat >"$PPT/fake_ssh_timeout.sh" <<'EOF'
#!/bin/bash
# args: [-G ...] <host> [<remote-command-string>] -- a "-G" config-probe query is never counted
# (it carries no remote-command argument); every OTHER invocation is a real remote-command call,
# counted via a shared counter file, sleeping forever on the configured Nth one instead of ever
# running the real local-loopback command (the standard GIT_SSH_COMMAND test technique: this
# wrapper IGNORES the host argument entirely and runs the remote command locally via `sh -c`,
# simulating a reachable ssh remote with no real network/sshd involved at all).
if [ "$1" = "-G" ]; then exit 1; fi
shift
cmd="$1"
count=0
[ -f "$FAKE_SSH_COUNTER" ] && count=$(cat "$FAKE_SSH_COUNTER")
count=$((count + 1))
echo "$count" >"$FAKE_SSH_COUNTER"
if [ "$count" = "$FAKE_SSH_SLEEP_ON" ]; then
  sleep 999
  exit 1
fi
exec sh -c "$cmd"
EOF
chmod +x "$PPT/fake_ssh_timeout.sh"
export GIT_SSH_COMMAND="$PPT/fake_ssh_timeout.sh"
PPT_URL="ssh://fakehost$PPT/sub_remote.git"
git -C "$PPT/sub_src" remote add origin "$PPT_URL"
git -C "$PPT/sub_src" push -q origin main
mk_repo "$PPT/parent"
echo "parent-seed" >"$PPT/parent/f.txt"
git -C "$PPT/parent" add -A; git -C "$PPT/parent" commit -qm "parent init"
git -C "$PPT/parent" -c protocol.file.allow=always submodule add -q "$PPT/sub_remote.git" sub
git -C "$PPT/parent" commit -qm "add submodule"
git -C "$PPT/parent/sub" remote set-url origin "$PPT_URL"
mk_bare "$PPT/parent_r1.git"
git -C "$PPT/parent" remote add origin "$PPT/parent_r1.git"
git -C "$PPT/parent" push -q origin main
export FAKE_SSH_COUNTER="$PPT/counter.txt"
export FAKE_SSH_SLEEP_ON=2
rm -f "$FAKE_SSH_COUNTER"
PPT_T0=$(date +%s)
timeout 20 python3 "$TOOL" --recursive --root "$PPT/parent" --out "$TMP/ppt.json" --timeout-per-remote 4 >"$TMP/ppt.out" 2>"$TMP/ppt.err"
PPTRC=$?
PPT_T1=$(date +%s)
unset GIT_SSH_COMMAND FAKE_SSH_COUNTER FAKE_SSH_SLEEP_ON
PPTOVERALL=$(report_field "$TMP/ppt.json" 'd.get("overall")' 2>/dev/null)
PPTSUB_STATUS=$(report_field "$TMP/ppt.json" 'next(r["status"] for r in d["repos"] if r["path"]=="sub")' 2>/dev/null)
PPTSUB_REASONS=$(report_field "$TMP/ppt.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="sub")' 2>/dev/null)
if [ "$PPTRC" -eq 4 ] && [ "$PPTOVERALL" = "UNVERIFIED" ] && [ "$PPTSUB_STATUS" = "UNVERIFIED" ] \
   && [ "$PPTSUB_REASONS" = "['REMOTE_UNREACHABLE']" ] && [ $((PPT_T1 - PPT_T0)) -ge 4 ] && [ $((PPT_T1 - PPT_T0)) -lt 18 ]; then
  ok "rv_bad_pointer_probe_timeout (B1 repro a): a probe-specific timeout (rc=None) on an otherwise-reachable remote maps to UNVERIFIED/REMOTE_UNREACHABLE, exit 4 -- NEVER POINTER_UNFETCHABLE/NOT_CLEAN (elapsed=$((PPT_T1 - PPT_T0))s, bounded by the 4s --timeout-per-remote)"
else
  not_ok "rv_bad_pointer_probe_timeout: rc=$PPTRC overall=$PPTOVERALL sub.status=$PPTSUB_STATUS sub.reasons=$PPTSUB_REASONS elapsed=$((PPT_T1 - PPT_T0))s"
fi

# -------------------------------------------------- rv_bad_pointer_probe_config_not_inherited (B1, repro b)
# A submodule's remote origin uses a repo-LOCAL `core.sshCommand` (never an ambient env var) that
# resolves the ssh:// url fine for the ORDINARY ls-remote/fetch checks (run with cwd=the submodule
# itself, so its own repo-local config genuinely applies) -- but the pointer-probe's fetch targets a
# FRESH, config-naive scratch bare repo via `--git-dir=<probe>`, which does NOT inherit that
# repo-local setting, so the probe falls back to the real system `ssh` binary trying to resolve the
# (deliberately unresolvable) hostname "fakehost" -- a config-driven failure, never a definitive
# "not our ref" rejection, and B1 requires this maps to UNVERIFIED too.
PPC="$TMP/rv_bad_pointer_probe_config_not_inherited"
mkdir -p "$PPC"
mk_repo "$PPC/sub_src"
echo "seed" >"$PPC/sub_src/f.txt"
git -C "$PPC/sub_src" add -A; git -C "$PPC/sub_src" commit -qm "init sub"
mk_bare "$PPC/sub_remote.git"
cat >"$PPC/fake_ssh_ok.sh" <<'EOF'
#!/bin/bash
if [ "$1" = "-G" ]; then exit 1; fi
shift
exec sh -c "$1"
EOF
chmod +x "$PPC/fake_ssh_ok.sh"
export GIT_SSH_COMMAND="$PPC/fake_ssh_ok.sh"
PPC_URL="ssh://fakehost$PPC/sub_remote.git"
git -C "$PPC/sub_src" remote add origin "$PPC_URL"
git -C "$PPC/sub_src" push -q origin main
mk_repo "$PPC/parent"
echo "parent-seed" >"$PPC/parent/f.txt"
git -C "$PPC/parent" add -A; git -C "$PPC/parent" commit -qm "parent init"
git -C "$PPC/parent" -c protocol.file.allow=always submodule add -q "$PPC/sub_remote.git" sub
git -C "$PPC/parent" commit -qm "add submodule"
git -C "$PPC/parent/sub" remote set-url origin "$PPC_URL"
# Repo-LOCAL config, on the submodule only -- the probe's own fresh --git-dir scratch repo (see
# repo_verify.py's own _pointer_fetchable docstring) carries none of this.
git -C "$PPC/parent/sub" config core.sshCommand "$PPC/fake_ssh_ok.sh"
mk_bare "$PPC/parent_r1.git"
git -C "$PPC/parent" remote add origin "$PPC/parent_r1.git"
git -C "$PPC/parent" push -q origin main
unset GIT_SSH_COMMAND
# Control check (11.4.6/11.4.199): confirm the repo-local config genuinely lets a PLAIN git command
# resolve this fake remote BEFORE trusting any assertion about repo_verify's own handling of it.
if git -C "$PPC/parent/sub" ls-remote origin >/dev/null 2>&1; then
  ok "rv_bad_pointer_probe_config_not_inherited: control check -- plain 'git ls-remote origin' from the submodule's own directory resolves via its repo-local core.sshCommand with NO ambient GIT_SSH_COMMAND set"
else
  not_ok "rv_bad_pointer_probe_config_not_inherited: control check FAILED -- the repo-local core.sshCommand does not even let a plain git command resolve the fake remote; fixture setup is broken"
fi
timeout 20 python3 "$TOOL" --recursive --root "$PPC/parent" --out "$TMP/ppc.json" --timeout-per-remote 10 >"$TMP/ppc.out" 2>"$TMP/ppc.err"
PPCRC=$?
PPCOVERALL=$(report_field "$TMP/ppc.json" 'd.get("overall")' 2>/dev/null)
PPCSUB_STATUS=$(report_field "$TMP/ppc.json" 'next(r["status"] for r in d["repos"] if r["path"]=="sub")' 2>/dev/null)
PPCSUB_REASONS=$(report_field "$TMP/ppc.json" 'next(r["reasons"] for r in d["repos"] if r["path"]=="sub")' 2>/dev/null)
PPCSUB_EQUAL=$(report_field "$TMP/ppc.json" 'next(rm["equal"] for r in d["repos"] if r["path"]=="sub" for rm in r["remotes"] if rm["name"]=="origin")' 2>/dev/null)
if [ "$PPCRC" -eq 4 ] && [ "$PPCOVERALL" = "UNVERIFIED" ] && [ "$PPCSUB_STATUS" = "UNVERIFIED" ] \
   && [ "$PPCSUB_REASONS" = "['REMOTE_UNREACHABLE']" ] && [ "$PPCSUB_EQUAL" = "True" ]; then
  ok "rv_bad_pointer_probe_config_not_inherited (B1 repro b): the ordinary fetch-URL check succeeds (equal=True, inherited repo-local core.sshCommand) while the pointer-probe's own config-naive scratch repo cannot resolve the SAME url -- maps to UNVERIFIED/REMOTE_UNREACHABLE, exit 4 -- NEVER POINTER_UNFETCHABLE/NOT_CLEAN"
else
  not_ok "rv_bad_pointer_probe_config_not_inherited: rc=$PPCRC overall=$PPCOVERALL sub.status=$PPCSUB_STATUS sub.reasons=$PPCSUB_REASONS sub.origin.equal=$PPCSUB_EQUAL"
fi

# ------------------------------------------------------------------------------------ I1 (IMPORTANT)
# verify_remote() no longer requests ANY destination ref for its live-tip fetch (a bare-SHA fetch,
# never a `sha:ref` colon-refspec) -- so there is NO ref left anywhere for an interrupted run to
# leave dangling, structurally, not merely "cleaned up better". Two proofs: (1) a MUTANT restoring
# the OLD colon-refspec form (with its ref-delete step removed, so it never even reaches its own
# best-effort cleanup) reproduces the EXACT reviewer-documented consequence -- a real, permanently
# dangling, fsck-breaking ref in the REAL repository -- on a fixture that forces a genuine new-object
# transfer (so the fetched object lives ONLY in the GIT_OBJECT_DIRECTORY-redirected scratch
# directory, which this process's own normal `verify_recursive()` cleanup removes at exit exactly as
# an interrupted run's would be removed by the OS/tmp-reaper); (2) the REAL (fixed) tool, sent an
# ACTUAL SIGTERM mid-run against a real fixture whose remote never responds, leaves that repo's
# refs/objects byte-identical to their pre-run state -- the SIGTERM handler (main()'s own
# `_sigterm_handler`) converts the signal into a raised exception so every open `finally:`/`with:`
# on the call stack still runs instead of the process being torn down mid-flight.
I1="$TMP/rv_i1_proof"
mk_repo "$I1/repo"
echo one >"$I1/repo/f.txt"; git -C "$I1/repo" add -A; git -C "$I1/repo" commit -qm c1
mk_bare "$I1/remote.git"
git -C "$I1/repo" remote add origin "$I1/remote.git"
git -C "$I1/repo" push -q origin main
git clone -q "$I1/remote.git" "$I1/other_clone"
git -C "$I1/other_clone" config user.email fc@example.invalid
git -C "$I1/other_clone" config user.name fastcycle
echo two >"$I1/other_clone/f.txt"
git -C "$I1/other_clone" add -A; git -C "$I1/other_clone" commit -qm c2
git -C "$I1/other_clone" push -q origin main
I1_REMOTE_SHA=$(git -C "$I1/remote.git" rev-parse main)
if git -C "$I1/repo" cat-file -e "$I1_REMOTE_SHA" 2>/dev/null; then
  not_ok "rv_i1_proof: fixture setup bug -- repo already has the remote's new commit object locally; this fixture cannot force a real transfer"
else
  ok "rv_i1_proof: fixture control check -- the remote's new commit object is genuinely absent from repo's own object store before either run below"
fi

# (1) MUTANT: restore the pre-round-2 colon-refspec form, with its ref-delete removed entirely (the
# SAME shape finding #6's own original defect had -- a ref written into the real repo's refs,
# pointing at an object that only the redirected scratch object directory holds).
cat >"$MUTMARK2/i1_old.txt" <<'EOF'
    equal = (tip == local_tip)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, tip], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % tip], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())
EOF
cat >"$MUTMARK2/i1_new.txt" <<'EOF'
    equal = (tip == local_tip)
    tmp_ref = "refs/fastcycle_verify_mutant_i1/%s" % re.sub(r"[^A-Za-z0-9_.-]", "_", out_name)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, "%s:%s" % (tip, tmp_ref)], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % tmp_ref], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())
EOF
if mk_mutant "mutant_i1" "$MUTMARK2/i1_old.txt" "$MUTMARK2/i1_new.txt" 2>"$TMP/mutant_i1.err"; then
  python3 "$TMP/mutant_i1/verify/repo_verify.py" --recursive --root "$I1/repo" --out "$TMP/mutant_i1.json" >"$TMP/mutant_i1.out" 2>>"$TMP/mutant_i1.err"
  I1_STRAY=$(git -C "$I1/repo" for-each-ref --format='%(refname)' 'refs/fastcycle_verify_mutant_i1/*' | head -1)
  if [ -n "$I1_STRAY" ] && ! git -C "$I1/repo" cat-file -e "$I1_STRAY" 2>/dev/null; then
    ok "rv_i1_proof (pre-fix repro, mutant): the OLD colon-refspec form left a REAL, permanently dangling ref ($I1_STRAY) in the repository -- 'git cat-file -e' on it fails exactly as the review's own reproduced consequence describes ('fatal: missing object ... for refs/fastcycle_verify/...')"
  else
    not_ok "rv_i1_proof (pre-fix repro, mutant): expected a dangling, cat-file-unreadable ref under refs/fastcycle_verify_mutant_i1/* after the mutant run, got stray_ref=$I1_STRAY"
  fi
  # Clean up the mutant's own deliberately-dangling ref so it cannot contaminate anything later.
  git -C "$I1/repo" update-ref -d "$I1_STRAY" 2>/dev/null || true
else
  not_ok "rv_i1_proof (pre-fix repro, mutant): mutation anchor text not found in repo_verify.py -- source moved, update this test's anchor: $(cat "$TMP/mutant_i1.err")"
fi

# (2) THE FIX: the real (fixed) tool, run normally against the SAME real-transfer-forcing fixture,
# creates NO ref anywhere, so there is nothing an interruption could ever leave dangling.
I1_BEFORE_REFS=$(git -C "$I1/repo" for-each-ref)
python3 "$TOOL" --recursive --root "$I1/repo" --out "$TMP/i1_fixed.json" >"$TMP/i1_fixed.out" 2>"$TMP/i1_fixed.err"
I1_FIXED_RC=$?
I1_AFTER_REFS=$(git -C "$I1/repo" for-each-ref)
I1_FIXED_OVERALL=$(report_field "$TMP/i1_fixed.json" 'd.get("overall")' 2>/dev/null)
if [ "$I1_FIXED_RC" -eq 1 ] && [ "$I1_FIXED_OVERALL" = "NOT_CLEAN" ] && [ "$I1_BEFORE_REFS" = "$I1_AFTER_REFS" ]; then
  ok "rv_i1_proof (fixed tool, normal run): the real tool still correctly reports NOT_CLEAN/REMOTE_AHEAD for the genuine new-object-transfer fixture, AND refs are byte-identical before/after -- no ref of any kind was ever created"
else
  not_ok "rv_i1_proof (fixed tool, normal run): rc=$I1_FIXED_RC overall=$I1_FIXED_OVERALL refs_identical=$([ "$I1_BEFORE_REFS" = "$I1_AFTER_REFS" ] && echo yes || echo no)"
fi

# (3) THE FIX under an ACTUAL interrupt: a genuinely slow remote (the SAME GIT_SSH_COMMAND-sleep
# technique as the B1 timeout fixture above, this time sleeping on the VERY FIRST ssh invocation so
# the tool is reliably still blocked when the signal arrives) is sent a real SIGTERM mid-run; the
# repo's refs/objects MUST be byte-identical afterward -- stronger than "no dangling ref", this
# proves the real repo is untouched even when the process is torn down abnormally mid-flight.
mk_repo "$I1/sigterm_sub_src"
echo "seed" >"$I1/sigterm_sub_src/f.txt"
git -C "$I1/sigterm_sub_src" add -A; git -C "$I1/sigterm_sub_src" commit -qm "init"
mk_bare "$I1/sigterm_sub_remote.git"
# Push to the LOCAL bare path directly (no ssh involved at all for setup -- matches every other
# submodule fixture's own convention: `submodule add` always clones a local path, and the remote's
# URL is rewritten to the ssh:// target ONLY AFTERWARD, a pure config change needing no network).
git -C "$I1/sigterm_sub_src" remote add origin "$I1/sigterm_sub_remote.git"
git -C "$I1/sigterm_sub_src" push -q origin main
cat >"$I1/fake_ssh_sleep.sh" <<'EOF'
#!/bin/bash
if [ "$1" = "-G" ]; then exit 1; fi
sleep 20
exit 1
EOF
chmod +x "$I1/fake_ssh_sleep.sh"
I1_SIGTERM_URL="ssh://fakehost$I1/sigterm_sub_remote.git"
mk_repo "$I1/sigterm_parent"
echo "parent-seed" >"$I1/sigterm_parent/f.txt"
git -C "$I1/sigterm_parent" add -A; git -C "$I1/sigterm_parent" commit -qm "parent init"
git -C "$I1/sigterm_parent" -c protocol.file.allow=always submodule add -q "$I1/sigterm_sub_remote.git" sub
git -C "$I1/sigterm_parent" commit -qm "add submodule"
git -C "$I1/sigterm_parent/sub" remote set-url origin "$I1_SIGTERM_URL"
mk_bare "$I1/sigterm_parent_r1.git"
git -C "$I1/sigterm_parent" remote add origin "$I1/sigterm_parent_r1.git"
git -C "$I1/sigterm_parent" push -q origin main
# Only NOW (after every real git operation setup needed is done) does GIT_SSH_COMMAND point at
# the sleeping wrapper -- so it affects ONLY the repo_verify.py invocation below, never the setup
# above.
export GIT_SSH_COMMAND="$I1/fake_ssh_sleep.sh"
I1_SIGTERM_BEFORE_REFS=$(git -C "$I1/sigterm_parent/sub" for-each-ref)
I1_SIGTERM_BEFORE_OBJS=$(git -C "$I1/sigterm_parent/sub" count-objects -v)
python3 "$TOOL" --recursive --root "$I1/sigterm_parent" --out "$TMP/i1_sigterm.json" --timeout-per-remote 120 >"$TMP/i1_sigterm.out" 2>"$TMP/i1_sigterm.err" &
I1_SIGTERM_PID=$!
sleep 1.5
kill -TERM "$I1_SIGTERM_PID" 2>/dev/null
wait "$I1_SIGTERM_PID" 2>/dev/null
I1_SIGTERM_RC=$?
unset GIT_SSH_COMMAND
sleep 0.3
I1_SIGTERM_AFTER_REFS=$(git -C "$I1/sigterm_parent/sub" for-each-ref)
I1_SIGTERM_AFTER_OBJS=$(git -C "$I1/sigterm_parent/sub" count-objects -v)
if grep -q "terminated by SIGTERM" "$TMP/i1_sigterm.err" && [ "$I1_SIGTERM_RC" -eq 4 ] \
   && [ "$I1_SIGTERM_BEFORE_REFS" = "$I1_SIGTERM_AFTER_REFS" ] && [ "$I1_SIGTERM_BEFORE_OBJS" = "$I1_SIGTERM_AFTER_OBJS" ]; then
  ok "rv_i1_proof (fixed tool, real SIGTERM mid-run): the SIGTERM handler converts the signal to exit 4 ('terminated by SIGTERM') and the submodule's refs + object counts are byte-identical before/after -- the real repo is provably untouched by an abrupt mid-flight interrupt, not merely 'cleaned up better'"
else
  not_ok "rv_i1_proof (fixed tool, real SIGTERM mid-run): rc=$I1_SIGTERM_RC refs_identical=$([ "$I1_SIGTERM_BEFORE_REFS" = "$I1_SIGTERM_AFTER_REFS" ] && echo yes || echo no) objs_identical=$([ "$I1_SIGTERM_BEFORE_OBJS" = "$I1_SIGTERM_AFTER_OBJS" ] && echo yes || echo no) stderr=$(cat "$TMP/i1_sigterm.err")"
fi
# Host hygiene: killing the python3 parent does not propagate to the `git fetch` subprocess it
# spawned, which in turn means git's OWN child (this wrapper) is orphaned rather than killed --
# reap it explicitly rather than leave it sleeping for its full budget. The match is the FULL
# absolute path under this run's own freshly-mktemp'd $TMP, unique to this one test invocation --
# never a bare/generic pattern (11.4.196(D)/§12.12 anti-carrier-match discipline).
pkill -f "$I1/fake_ssh_sleep.sh" >/dev/null 2>&1 || true

# ================================================================================================
# T158 remediation round 3 -- new fixtures/mutations closing the THIRD independent review's three
# IMPORTANT findings (I-N1 redact_url regression, I-N2 submodule-fetch-redirect bug, I-N3 the
# round-2 I1 regression guard's own test-rigor gap). Round 1's + round 2's assertions above (and
# their mutations) are UNTOUCHED and must all stay GREEN -- including the two i1_old.txt/i1_new.txt
# mutation anchors just above, updated in place to include the I-N2 "--recurse-submodules=no" flag
# this round adds, so they still match the real (now further-fixed) source exactly.
# ================================================================================================

MUTMARK3="$TMP/mutmark3"
mkdir -p "$MUTMARK3"

# ------------------------------------------------------------------------------------ I-N2 (IMPORTANT)
# Round 1's own fix for finding #6 redirects NEWLY-FETCHED OBJECTS away from a repository's real
# object store via GIT_OBJECT_DIRECTORY -- but git's DEFAULT submodule-recursion behaviour
# (fetch.recurseSubmodules unset -> "on-demand") starts a SEPARATE, UN-REDIRECTED `git fetch`
# INSIDE a submodule whenever the PARENT's own fetch reaches a commit that moves that submodule's
# gitlink to a commit the submodule does not yet have locally -- and git CLEARS the redirect env
# vars for that child process, so the submodule-level fetch writes straight into the submodule's
# REAL .git directory. Fixture: the submodule is advanced (on a SEPARATE clone) and the PARENT's
# gitlink is bumped to that new submodule commit (also on a separate clone) and pushed -- so the
# LOCAL fixture's parent is genuinely behind its own remote by a gitlink-moving commit, AND the
# local fixture's own submodule checkout genuinely lacks the new submodule commit object (the
# exact precondition that triggers git's on-demand recursion, per the round-3 review's own
# reproduction method -- never assumed, 11.4.199/11.4.6).
I2P="$TMP/rv_i2n_submodule_fetch_redirect"
mkdir -p "$I2P"
mk_repo "$I2P/sub_src"
echo "seed" >"$I2P/sub_src/f.txt"
git -C "$I2P/sub_src" add -A; git -C "$I2P/sub_src" commit -qm "init sub"
mk_bare "$I2P/sub_remote.git"
git -C "$I2P/sub_src" remote add origin "$I2P/sub_remote.git"
git -C "$I2P/sub_src" push -q origin main

mk_repo "$I2P/parent"
echo "parent-seed" >"$I2P/parent/f.txt"
git -C "$I2P/parent" add -A; git -C "$I2P/parent" commit -qm "parent init"
git -C "$I2P/parent" -c protocol.file.allow=always submodule add -q "$I2P/sub_remote.git" sub
git -C "$I2P/parent" commit -qm "add submodule"
mk_bare "$I2P/parent_remote.git"
git -C "$I2P/parent" remote add origin "$I2P/parent_remote.git"
git -C "$I2P/parent" push -q origin main

# Advance the submodule on a SEPARATE clone and push -- the fixture's own local submodule checkout
# (parent/sub) stays behind and never fetches this.
git clone -q "$I2P/sub_remote.git" "$I2P/sub_other_clone"
git -C "$I2P/sub_other_clone" config user.email fc@example.invalid
git -C "$I2P/sub_other_clone" config user.name fastcycle
echo "moved on" >"$I2P/sub_other_clone/f.txt"
git -C "$I2P/sub_other_clone" commit -qam "sub moves on"
git -C "$I2P/sub_other_clone" push -q origin main
I2P_NEW_SUB_SHA=$(git -C "$I2P/sub_remote.git" rev-parse main)

# Advance the PARENT on a SEPARATE clone, bumping its gitlink to the new submodule sha, and push --
# the fixture's own local parent checkout never sees this until repo_verify.py's own live-tip fetch.
# NOTE: `-c protocol.file.allow=always` is REQUIRED on this clone (not just on the original
# `submodule add` above) -- without it, git's recursive submodule clone of this local bare
# submodule remote fails ("transport 'file' not allowed"), leaving parent_other_clone/sub
# unpopulated and the subsequent checkout/add/commit below silently a no-op -- which would make
# this whole fixture fail to actually bump the parent's gitlink at all (confirmed live while
# authoring this fixture: 11.4.199/11.4.6, never assumed from a first attempt).
git -c protocol.file.allow=always clone -q --recurse-submodules "$I2P/parent_remote.git" "$I2P/parent_other_clone"
git -C "$I2P/parent_other_clone" config user.email fc@example.invalid
git -C "$I2P/parent_other_clone" config user.name fastcycle
git -C "$I2P/parent_other_clone/sub" config user.email fc@example.invalid
git -C "$I2P/parent_other_clone/sub" config user.name fastcycle
git -C "$I2P/parent_other_clone/sub" fetch -q origin
git -C "$I2P/parent_other_clone/sub" checkout -q "$I2P_NEW_SUB_SHA"
git -C "$I2P/parent_other_clone" add sub
git -C "$I2P/parent_other_clone" commit -qm "bump sub pointer"
git -C "$I2P/parent_other_clone" push -q origin main

# Control check (11.4.199/11.4.6): confirm the parent's REMOTE tip genuinely records the new
# submodule sha as its gitlink for "sub" before trusting any assertion below -- a silently-failed
# recursive clone/checkout above (e.g. a missing protocol.file.allow) would otherwise leave the
# parent's gitlink UNCHANGED, and every assertion below would then be testing nothing.
I2P_NEWPARENT_SHA=$(git -C "$I2P/parent_remote.git" rev-parse main)
I2P_REMOTE_GITLINK=$(git -C "$I2P/parent_remote.git" ls-tree "$I2P_NEWPARENT_SHA" -- sub | awk '{print $3}')
if [ "$I2P_REMOTE_GITLINK" = "$I2P_NEW_SUB_SHA" ]; then
  ok "rv_i2n_submodule_fetch_redirect: fixture control check -- the parent's remote tip genuinely records the new submodule sha as its 'sub' gitlink (the bump commit actually landed)"
else
  not_ok "rv_i2n_submodule_fetch_redirect: fixture setup bug -- the parent remote's gitlink for 'sub' is $I2P_REMOTE_GITLINK, expected $I2P_NEW_SUB_SHA -- the gitlink bump did not land; every assertion below is testing nothing"
fi

if git -C "$I2P/parent/sub" cat-file -e "$I2P_NEW_SUB_SHA" 2>/dev/null; then
  not_ok "rv_i2n_submodule_fetch_redirect: fixture setup bug -- the fixture's own local submodule checkout already has the new sha; this fixture cannot exercise the on-demand-recursion precondition"
else
  ok "rv_i2n_submodule_fetch_redirect: fixture control check -- the new submodule commit is genuinely absent from the fixture's own local submodule object store before either run below"
fi

I2P_SUB_GITDIR=$(real_gitdir "$I2P/parent/sub")
I2P_SUB_BEFORE_TREEHASH=$(tree_hash "$I2P_SUB_GITDIR")
I2P_SUB_BEFORE_REFS=$(git -C "$I2P/parent/sub" for-each-ref)

# (1) THE FIX, real (fixed) tool, normal run: the submodule's REAL git-dir must stay byte-identical
# -- the parent-level fetch above must never trigger an un-redirected recursive submodule fetch.
run_tool "$I2P/parent" "$TMP/i2n_fixed.json"; I2N_FIXED_RC=$?
I2P_SUB_AFTER_TREEHASH=$(tree_hash "$I2P_SUB_GITDIR")
I2P_SUB_AFTER_REFS=$(git -C "$I2P/parent/sub" for-each-ref)
if [ "$I2P_SUB_BEFORE_TREEHASH" = "$I2P_SUB_AFTER_TREEHASH" ] && [ "$I2P_SUB_BEFORE_REFS" = "$I2P_SUB_AFTER_REFS" ]; then
  ok "rv_i2n_submodule_fetch_redirect (fixed tool, I-N2): the submodule's REAL git-dir (refs + whole-git-dir-tree-hash) is byte-identical before/after a parent-level fetch that reaches a gitlink-moving commit -- the on-demand recursive submodule fetch never wrote into the submodule's own repository (--recurse-submodules=no fix confirmed)"
else
  not_ok "rv_i2n_submodule_fetch_redirect (fixed tool, I-N2): the submodule's real git-dir CHANGED (refs_identical=$([ "$I2P_SUB_BEFORE_REFS" = "$I2P_SUB_AFTER_REFS" ] && echo yes || echo no) treehash_identical=$([ "$I2P_SUB_BEFORE_TREEHASH" = "$I2P_SUB_AFTER_TREEHASH" ] && echo yes || echo no)) -- rc=$I2N_FIXED_RC"
fi

# (2) MUTANT: drop the --recurse-submodules=no flag -- the submodule's real git-dir MUST then get
# written to (proving the fixture and the fix are both genuinely load-bearing, 11.4.115(F)).
cat >"$MUTMARK3/i2n_old.txt" <<'EOF'
    equal = (tip == local_tip)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, tip], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
EOF
cat >"$MUTMARK3/i2n_new.txt" <<'EOF'
    equal = (tip == local_tip)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         git_target, tip], repo_path, timeout_s, extra_env=extra_env)  # PAIRED MUTATION (I-N2: drop --recurse-submodules=no)
    unpushed = "UNKNOWN"
EOF
if mk_mutant "mutant_i2n" "$MUTMARK3/i2n_old.txt" "$MUTMARK3/i2n_new.txt" 2>"$TMP/mutant_i2n.err"; then
  python3 "$TMP/mutant_i2n/verify/repo_verify.py" --recursive --root "$I2P/parent" --out "$TMP/i2n_mutant.json" >"$TMP/i2n_mutant.out" 2>>"$TMP/mutant_i2n.err"
  I2N_MUT_TREEHASH=$(tree_hash "$I2P_SUB_GITDIR")
  I2N_MUT_REFS=$(git -C "$I2P/parent/sub" for-each-ref)
  if [ "$I2N_MUT_TREEHASH" != "$I2P_SUB_BEFORE_TREEHASH" ] || [ "$I2N_MUT_REFS" != "$I2P_SUB_BEFORE_REFS" ]; then
    ok "paired mutation CAUGHT (I-N2): dropping --recurse-submodules=no lets git's default on-demand recursion write into the submodule's REAL git-dir (refs and/or whole-tree-hash changed) on the SAME rv_i2n_submodule_fetch_redirect fixture -- confirms the fixture and the fix are both genuinely load-bearing"
  else
    not_ok "paired mutation (I-N2): expected dropping --recurse-submodules=no to mutate the submodule's real git-dir on this fixture, but it stayed byte-identical -- either the mutation is not load-bearing in this git version, or the fixture no longer exercises the on-demand-recursion precondition"
  fi
else
  not_ok "paired mutation (I-N2): mutation anchor text not found in repo_verify.py -- source moved, update this test's anchor: $(cat "$TMP/mutant_i2n.err")"
fi

# ------------------------------------------------------------------------------------ I-N3 (IMPORTANT)
# Round 2's own I1 regression guard (the i1_old.txt/i1_new.txt mutation above) only ever caught its
# own M5 mutant because that mutant's TEXT happened to differ from a source-text anchor some other
# check greps for -- never because any check observed a REAL ref-write at the behaviour level. A
# `reference-transaction` hook is git's own mechanism for observing EVERY ref transaction (even a
# create-then-immediately-delete within one process, which the existing "refs identical before vs.
# after the WHOLE run" check structurally cannot see) -- installed directly in the fixture repo's
# own .git/hooks/ (a plain top-level repo, never a submodule, so no .git-file indirection to
# resolve), it proves the fixed tool triggers ZERO ref transactions of any kind during a normal
# run, and that a mutant restoring the old colon-refspec fetch-then-delete pattern -- built fresh
# against the CURRENT (I-N2-fixed) source, WITHOUT touching any text another check's own anchor
# greps for -- is still caught at the BEHAVIOUR layer regardless (11.4.115(F)/11.4.194(6)(d):
# "a guard never observed FAILing on the genuinely-broken artifact is unvalidated instrumentation").
I3="$TMP/rv_i3n_reftx_proof"
mk_repo "$I3/repo"
echo one >"$I3/repo/f.txt"; git -C "$I3/repo" add -A; git -C "$I3/repo" commit -qm c1
mk_bare "$I3/remote.git"
git -C "$I3/repo" remote add origin "$I3/remote.git"
git -C "$I3/repo" push -q origin main
git clone -q "$I3/remote.git" "$I3/other_clone"
git -C "$I3/other_clone" config user.email fc@example.invalid
git -C "$I3/other_clone" config user.name fastcycle
echo two >"$I3/other_clone/f.txt"
git -C "$I3/other_clone" add -A; git -C "$I3/other_clone" commit -qm c2
git -C "$I3/other_clone" push -q origin main
I3_REMOTE_SHA=$(git -C "$I3/remote.git" rev-parse main)
if git -C "$I3/repo" cat-file -e "$I3_REMOTE_SHA" 2>/dev/null; then
  not_ok "rv_i3n_reftx_proof: fixture setup bug -- repo already has the remote's new commit object locally; this fixture cannot force a real transfer"
else
  ok "rv_i3n_reftx_proof: fixture control check -- the remote's new commit object is genuinely absent from repo's own object store before either run below"
fi

mkdir -p "$I3/repo/.git/hooks"
cat >"$I3/repo/.git/hooks/reference-transaction" <<'HOOK'
#!/bin/bash
{
  echo "=== reference-transaction state=$1 ==="
  cat
} >>"$REFTX_LOG" 2>&1
exit 0
HOOK
chmod +x "$I3/repo/.git/hooks/reference-transaction"

# (1) THE FIX, real tool, normal run: the hook must record ZERO ref transactions of ANY kind.
export REFTX_LOG="$I3/reftx_fixed.log"
rm -f "$REFTX_LOG"
python3 "$TOOL" --recursive --root "$I3/repo" --out "$TMP/i3n_fixed.json" >"$TMP/i3n_fixed.out" 2>"$TMP/i3n_fixed.err"
I3N_FIXED_RC=$?
unset REFTX_LOG
I3N_FIXED_OVERALL=$(report_field "$TMP/i3n_fixed.json" 'd.get("overall")' 2>/dev/null)
if [ "$I3N_FIXED_RC" -eq 1 ] && [ "$I3N_FIXED_OVERALL" = "NOT_CLEAN" ] && [ ! -s "$I3/reftx_fixed.log" ]; then
  ok "rv_i3n_reftx_proof (fixed tool, I-N3): the real tool correctly reports rc=1/NOT_CLEAN/REMOTE_AHEAD for this genuine new-object-transfer fixture (matching rv_i1_proof's own fixture semantics), AND the reference-transaction hook recorded ZERO ref transactions -- a BEHAVIOURAL guarantee (not a source-text match) that no ref of any kind, including a create-then-immediately-delete, was ever written (a wrong-verdict run proving an empty log for the wrong reason is excluded by the verdict check)"
else
  not_ok "rv_i3n_reftx_proof (fixed tool, I-N3): expected rc=1/NOT_CLEAN and zero reference-transaction hook firings, got rc=$I3N_FIXED_RC overall=$I3N_FIXED_OVERALL log: $(cat "$I3/reftx_fixed.log" 2>/dev/null)"
fi

# (2) MUTANT: restore the OLD colon-refspec fetch-then-delete pattern, built fresh against the
# CURRENT (I-N2-fixed) source -- the reference-transaction hook MUST still catch it even though
# this mutant's own text was never checked against any OTHER test's source-text anchor.
cat >"$MUTMARK3/i3n_old.txt" <<'EOF'
    equal = (tip == local_tip)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, tip], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % tip], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())
EOF
cat >"$MUTMARK3/i3n_new.txt" <<'EOF'
    equal = (tip == local_tip)
    i3n_tmp_ref = "refs/fastcycle_verify_mutant_i3n/%s" % re.sub(r"[^A-Za-z0-9_.-]", "_", out_name)
    fetched, _fout, _ferr = _run(
        ["git", "-c", "gc.auto=0", "fetch", "--no-tags", "-q", "--no-write-fetch-head",
         "--recurse-submodules=no", git_target, "%s:%s" % (tip, i3n_tmp_ref)], repo_path, timeout_s, extra_env=extra_env)
    unpushed = "UNKNOWN"
    if fetched == 0:
        rc, out, _err = _run(["git", "rev-list", "--count", "%s..HEAD" % i3n_tmp_ref], repo_path, timeout_s,
                              extra_env=extra_env)
        if rc == 0 and out.strip().isdigit():
            unpushed = int(out.strip())
    _run(["git", "update-ref", "-d", i3n_tmp_ref], repo_path, timeout_s)
EOF
if mk_mutant "mutant_i3n" "$MUTMARK3/i3n_old.txt" "$MUTMARK3/i3n_new.txt" 2>"$TMP/mutant_i3n.err"; then
  export REFTX_LOG="$I3/reftx_mutant.log"
  rm -f "$REFTX_LOG"
  python3 "$TMP/mutant_i3n/verify/repo_verify.py" --recursive --root "$I3/repo" --out "$TMP/i3n_mutant.json" >"$TMP/i3n_mutant.out" 2>>"$TMP/mutant_i3n.err"
  unset REFTX_LOG
  git -C "$I3/repo" for-each-ref 'refs/fastcycle_verify_mutant_i3n/*' --format='%(refname)' | while read -r stray; do
    git -C "$I3/repo" update-ref -d "$stray" 2>/dev/null || true
  done
  if [ -s "$I3/reftx_mutant.log" ]; then
    ok "paired mutation CAUGHT (I-N3): the reference-transaction hook recorded >=1 real ref transaction when the OLD colon-refspec fetch-then-delete pattern is restored -- caught at the BEHAVIOUR level (the hook fires on both the create and the delete), proving round 2's I1 regression guard is no longer enforced ONLY by a source-text anchor match"
  else
    not_ok "paired mutation (I-N3): expected the reference-transaction hook to record >=1 transaction for the restored colon-refspec pattern, got none: $(cat "$TMP/mutant_i3n.err" 2>/dev/null)"
  fi
else
  not_ok "paired mutation (I-N3): mutation anchor text not found -- source moved, update this test's anchor: $(cat "$TMP/mutant_i3n.err")"
fi
rm -f "$I3/reftx_fixed.log" "$I3/reftx_mutant.log"

# --------------------------------------------------------------------------- redact_url (I-N1)
# The round-2 "fix" for the query-string/fragment leak (MINOR block above, already re-confirmed
# GREEN) itself re-introduced a credential leak: `_strip_query_fragment` ran BEFORE searching for
# the real `@`, so a `?`/`#` embedded INSIDE the userinfo portion truncated the search too early
# and the credential text in front of it was rendered as the whole "host".
RU3_OUT=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("repo_verify", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# T158 round 4 (I4-1): all 5 of these shapes have their LAST '@' at/after their FIRST '?'/'#' --
# structurally indistinguishable from a real query carrying a literal '@' (e.g. the 5th case), so
# redact_url now FAILS CLOSED for every one of them (fixed placeholder, zero bytes of the input).
# The round-3 expectations (a real host for the first 4) were only reachable by guessing which
# reading applies; the no-leak property each case was added for is unchanged and still asserted.
cases = {
    "https://user:pa#ss@github.com/org/repo.git": "REDACTED_AMBIGUOUS_URL",
    "https://user:p?ss@github.com/org/repo.git": "REDACTED_AMBIGUOUS_URL",
    "https://SECRETTOKEN#@github.com/o/r.git": "REDACTED_AMBIGUOUS_URL",
    "ssh://git:pw#d@host/x.git": "REDACTED_AMBIGUOUS_URL",
    # residual edge case the same finding names (a query value containing a literal '@') -- must
    # never let query DATA be rendered as if it were the host.
    "https://host/o/r.git?u=a@SECRET": "REDACTED_AMBIGUOUS_URL",
}
ok = True
for url, expected in cases.items():
    out = m.redact_url(url)
    leaked = ("pa" == out[:2] and "ss" in out) or ("SECRET" in out) or ("git:pw" in out)
    status = "OK" if (out == expected and not leaked) else "MISMATCH_OR_LEAK"
    if out != expected or leaked:
        ok = False
    print("%s url=%r got=%r expected=%r" % (status, url, out, expected))
print("ALL_OK" if ok else "SOME_FAILED")
PY
)
while IFS= read -r ru3_line; do printf '   %s\n' "$ru3_line"; done <<<"$RU3_OUT"
case "$RU3_OUT" in
  *ALL_OK*) ok "redact_url (I-N1): round 2's own query-string-stripping fix no longer re-leaks credential text embedded in userinfo before a decoy '?'/'#', for all 4 of round 3's repro URLs plus the residual query-embedded-'@' edge case (T158 remediation round 3 fix confirmed, 11.4.10)" ;;
  *) not_ok "redact_url (I-N1, round 3): at least one case failed or leaked -- see output above" ;;
esac

# ------------------------------------------------------------------------------------ I2 (IMPORTANT)
# A malformed/wrongly-shaped --remotes-config MUST exit 2 naming the specific problem, never
# silently fall back to "no requirement" -- four repro shapes, each against a repo where the
# (fictionally) required remote 'upstream' is genuinely absent everywhere (so a silent "no
# requirement" fallback would wrongly read CLEAN/exit 0, the exact bug this closes), plus one
# NEGATIVE control (a deliberately empty `{}` document, which IS a valid "no requirement"
# declaration and must NOT be refused, 11.4.201(1)).
I2="$TMP/rv_i2_malformed_config"
mk_repo "$I2/repo"
echo one >"$I2/repo/f.txt"; git -C "$I2/repo" add -A; git -C "$I2/repo" commit -qm c1
mk_bare "$I2/origin.git"
git -C "$I2/repo" remote add origin "$I2/origin.git"
git -C "$I2/repo" push -q origin main

printf '{"required_remotes": ["upstream"' >"$I2/truncated.json"
printf '{"required_remotes": "upstream"}' >"$I2/wrongtype.json"
printf '{"required_remote": ["upstream"]}' >"$I2/typo.json"
printf '["upstream"]' >"$I2/toplevellist.json"
printf '{}' >"$I2/empty.json"

python3 "$TOOL" --recursive --root "$I2/repo" --out "$TMP/i2_truncated.json" --remotes-config "$I2/truncated.json" >"$TMP/i2_truncated.out" 2>"$TMP/i2_truncated.err"
I2_TRUNC_RC=$?
if [ "$I2_TRUNC_RC" -eq 2 ] && grep -qi "not valid JSON" "$TMP/i2_truncated.err"; then
  ok "rv_i2_malformed_config: truncated JSON ('{\"required_remotes\": [\"upstream\"') exits 2 naming the JSON parse failure, never silently \"no requirement\" (was exit 0/CLEAN pre-fix)"
else
  not_ok "rv_i2_malformed_config (truncated): rc=$I2_TRUNC_RC stderr=$(cat "$TMP/i2_truncated.err")"
fi

python3 "$TOOL" --recursive --root "$I2/repo" --out "$TMP/i2_wrongtype.json" --remotes-config "$I2/wrongtype.json" >"$TMP/i2_wrongtype.out" 2>"$TMP/i2_wrongtype.err"
I2_WRONGTYPE_RC=$?
if [ "$I2_WRONGTYPE_RC" -eq 2 ] && grep -qi "must be a JSON list" "$TMP/i2_wrongtype.err"; then
  ok "rv_i2_malformed_config: wrong type ('required_remotes' as a string, not a list) exits 2 naming the type mismatch"
else
  not_ok "rv_i2_malformed_config (wrongtype): rc=$I2_WRONGTYPE_RC stderr=$(cat "$TMP/i2_wrongtype.err")"
fi

python3 "$TOOL" --recursive --root "$I2/repo" --out "$TMP/i2_typo.json" --remotes-config "$I2/typo.json" >"$TMP/i2_typo.out" 2>"$TMP/i2_typo.err"
I2_TYPO_RC=$?
if [ "$I2_TYPO_RC" -eq 2 ] && grep -qi "unrecognised key" "$TMP/i2_typo.err"; then
  ok "rv_i2_malformed_config: typo'd key ('required_remote', missing the trailing 's') exits 2 naming the unrecognised key, never silently treated as an absent 'required_remotes'"
else
  not_ok "rv_i2_malformed_config (typo): rc=$I2_TYPO_RC stderr=$(cat "$TMP/i2_typo.err")"
fi

python3 "$TOOL" --recursive --root "$I2/repo" --out "$TMP/i2_toplevellist.json" --remotes-config "$I2/toplevellist.json" >"$TMP/i2_toplevellist.out" 2>"$TMP/i2_toplevellist.err"
I2_TOPLIST_RC=$?
if [ "$I2_TOPLIST_RC" -eq 2 ] && grep -qi "must be an object" "$TMP/i2_toplevellist.err"; then
  ok "rv_i2_malformed_config: top-level JSON list instead of an object exits 2 naming the shape mismatch"
else
  not_ok "rv_i2_malformed_config (toplevellist): rc=$I2_TOPLIST_RC stderr=$(cat "$TMP/i2_toplevellist.err")"
fi

python3 "$TOOL" --recursive --root "$I2/repo" --out "$TMP/i2_empty.json" --remotes-config "$I2/empty.json" >"$TMP/i2_empty.out" 2>"$TMP/i2_empty.err"
I2_EMPTY_RC=$?
I2_EMPTY_OVERALL=$(report_field "$TMP/i2_empty.json" 'd.get("overall")' 2>/dev/null)
if [ "$I2_EMPTY_RC" -eq 0 ] && [ "$I2_EMPTY_OVERALL" = "CLEAN" ]; then
  ok "rv_i2_malformed_config: a deliberately empty '{}' document is a VALID 'no requirement' declaration and is NOT refused (exit 0/CLEAN) -- the 11.4.201(1) false-positive guard on I2's own fix"
else
  not_ok "rv_i2_malformed_config (empty negative control): rc=$I2_EMPTY_RC overall=$I2_EMPTY_OVERALL"
fi

# ------------------------------------------------------------------------------------ I3 (IMPORTANT)
# The push-URL guards (finding #3's own fix) were themselves unvalidated: two reviewer-authored
# mutations survived the round-1 suite with nothing catching them. Fixture + mutation pair for each.

# ---- m2: an unreachable push URL must be flagged, never silently read CLEAN ----
PUU="$TMP/rv_bad_push_url_unreachable"
mk_repo "$PUU/repo"
echo one >"$PUU/repo/f.txt"; git -C "$PUU/repo" add -A; git -C "$PUU/repo" commit -qm c1
mk_bare "$PUU/fetch_target.git"
git -C "$PUU/repo" remote add origin "$PUU/fetch_target.git"
git -C "$PUU/repo" push -q origin main
# The push destination is deliberately NEVER created (not even `git init --bare`) -- genuinely
# unreachable, distinct from merely lagging.
git -C "$PUU/repo" remote set-url --push origin "$PUU/gone_push_target.git"
python3 "$TOOL" --recursive --root "$PUU/repo" --out "$TMP/puu.json" >"$TMP/puu.out" 2>"$TMP/puu.err"
PUURC=$?
PUUOVERALL=$(report_field "$TMP/puu.json" 'd.get("overall")' 2>/dev/null)
PUUREASONS=$(report_field "$TMP/puu.json" 'd["repos"][0]["reasons"]' 2>/dev/null)
PUU_PUSH_TIP=$(report_field "$TMP/puu.json" 'next((rm["remote_tip"] for rm in d["repos"][0]["remotes"] if rm["name"]=="origin:push"), "MISSING")' 2>/dev/null)
if [ "$PUURC" -eq 4 ] && [ "$PUUOVERALL" = "UNVERIFIED" ] && [ "$PUUREASONS" = "['REMOTE_UNREACHABLE']" ] && [ "$PUU_PUSH_TIP" = "UNREACHABLE" ]; then
  ok "rv_bad_push_url_unreachable (I3, m2 fixture): a push URL pointing at a destination that was never even created is correctly flagged UNVERIFIED/REMOTE_UNREACHABLE via the SAME origin:push entry -- exit 4"
else
  not_ok "rv_bad_push_url_unreachable: rc=$PUURC overall=$PUUOVERALL reasons=$PUUREASONS push_tip=$PUU_PUSH_TIP"
fi

cat >"$MUTMARK2/m2_old.txt" <<'EOF'
                if push_reason == "REMOTE_UNREACHABLE":
                    saw_unreachable = True
EOF
cat >"$MUTMARK2/m2_new.txt" <<'EOF'
                if push_reason == "REMOTE_UNREACHABLE":
                    pass  # PAIRED MUTATION (I3, m2: an unreachable push URL is never flagged)
EOF
if mk_mutant "mutant_m2" "$MUTMARK2/m2_old.txt" "$MUTMARK2/m2_new.txt" 2>"$TMP/mutant_m2.err"; then
  python3 "$TMP/mutant_m2/verify/repo_verify.py" --recursive --root "$PUU/repo" --out "$TMP/mutant_m2.json" >"$TMP/mutant_m2.out" 2>>"$TMP/mutant_m2.err"
  MUTM2_RC=$?
  MUTM2_OVERALL=$(report_field "$TMP/mutant_m2.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTM2_RC" -eq 0 ] && [ "$MUTM2_OVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT (I3, m2): no-op'ing the push-URL unreachable flag makes the SAME rv_bad_push_url_unreachable fixture wrongly report CLEAN -- confirms the check is genuinely load-bearing (was previously unvalidated)"
  else
    not_ok "paired mutation (I3, m2): expected the mutant to wrongly report rc=0/CLEAN on rv_bad_push_url_unreachable, got rc=$MUTM2_RC overall=$MUTM2_OVERALL"
  fi
else
  not_ok "paired mutation (I3, m2): mutation anchor text not found -- source moved, update this test's anchor: $(cat "$TMP/mutant_m2.err")"
fi

# ---- m6: a remote with MORE THAN ONE pushurl must still have EVERY one of them checked ----
PM="$TMP/rv_bad_push_url_multi_lagging"
mk_repo "$PM/repo"
echo one >"$PM/repo/f.txt"; git -C "$PM/repo" add -A; git -C "$PM/repo" commit -qm c1
mk_bare "$PM/fetch.git"; mk_bare "$PM/push1.git"; mk_bare "$PM/push2.git"
git -C "$PM/repo" remote add origin "$PM/fetch.git"
git -C "$PM/repo" push -q origin main
git -C "$PM/repo" push -q "$PM/push1.git" main
git -C "$PM/repo" push -q "$PM/push2.git" main
git -C "$PM/repo" remote set-url --add --push origin "$PM/push1.git"
git -C "$PM/repo" remote set-url --add --push origin "$PM/push2.git"
echo two >"$PM/repo/f.txt"; git -C "$PM/repo" commit -qam c2
git -C "$PM/repo" push -q "$PM/fetch.git" main
git -C "$PM/repo" push -q "$PM/push1.git" main
# push2.git deliberately NOT advanced -- lags by 1 commit, the SECOND of two configured pushurls.
PM_PUSH2_SHA=$(git -C "$PM/push2.git" rev-parse main)
python3 "$TOOL" --recursive --root "$PM/repo" --out "$TMP/pm.json" >"$TMP/pm.out" 2>"$TMP/pm.err"
PMRC=$?
PMOVERALL=$(report_field "$TMP/pm.json" 'd.get("overall")' 2>/dev/null)
PM_PUSH_COUNT=$(report_field "$TMP/pm.json" 'sum(1 for rm in d["repos"][0]["remotes"] if rm["name"]=="origin:push")' 2>/dev/null)
PM_LAGGING_FOUND=$(report_field "$TMP/pm.json" 'any(rm["name"]=="origin:push" and rm["remote_tip"]=="'"$PM_PUSH2_SHA"'" and not rm["equal"] for rm in d["repos"][0]["remotes"])' 2>/dev/null)
if [ "$PMRC" -eq 1 ] && [ "$PMOVERALL" = "NOT_CLEAN" ] && [ "$PM_PUSH_COUNT" = "2" ] && [ "$PM_LAGGING_FOUND" = "True" ]; then
  ok "rv_bad_push_url_multi_lagging (I3, m6 fixture): BOTH of two configured pushurls are checked (2 distinct origin:push entries) and the lagging SECOND one is caught -- exit 1 NOT_CLEAN"
else
  not_ok "rv_bad_push_url_multi_lagging: rc=$PMRC overall=$PMOVERALL push_entry_count=$PM_PUSH_COUNT lagging_found=$PM_LAGGING_FOUND"
fi

cat >"$MUTMARK2/m6_old.txt" <<'EOF'
            for push_url in _push_urls(repo_path, remote, timeout_s):
                if url is not None and push_url == url:
                    continue
EOF
cat >"$MUTMARK2/m6_new.txt" <<'EOF'
            # PAIRED MUTATION (I3, m6: skip the push-URL check entirely for >1 pushurl)
            _m6_push_urls = _push_urls(repo_path, remote, timeout_s)
            if len(_m6_push_urls) > 1:
                _m6_push_urls = []
            for push_url in _m6_push_urls:
                if url is not None and push_url == url:
                    continue
EOF
if mk_mutant "mutant_m6" "$MUTMARK2/m6_old.txt" "$MUTMARK2/m6_new.txt" 2>"$TMP/mutant_m6.err"; then
  python3 "$TMP/mutant_m6/verify/repo_verify.py" --recursive --root "$PM/repo" --out "$TMP/mutant_m6.json" >"$TMP/mutant_m6.out" 2>>"$TMP/mutant_m6.err"
  MUTM6_RC=$?
  MUTM6_OVERALL=$(report_field "$TMP/mutant_m6.json" 'd.get("overall")' 2>/dev/null)
  if [ "$MUTM6_RC" -eq 0 ] && [ "$MUTM6_OVERALL" = "CLEAN" ]; then
    ok "paired mutation CAUGHT (I3, m6): skipping the push-URL check whenever a remote has more than one pushurl makes the SAME rv_bad_push_url_multi_lagging fixture wrongly report CLEAN -- confirms the multi-pushurl path is genuinely load-bearing (was previously unvalidated)"
  else
    not_ok "paired mutation (I3, m6): expected the mutant to wrongly report rc=0/CLEAN on rv_bad_push_url_multi_lagging, got rc=$MUTM6_RC overall=$MUTM6_OVERALL"
  fi
else
  not_ok "paired mutation (I3, m6): mutation anchor text not found -- source moved, update this test's anchor: $(cat "$TMP/mutant_m6.err")"
fi

# ------------------------------------------------------------------------- redact_url query-string/fragment leak
# A new, narrower gap than round 1's own three (all of which stay fixed, confirmed by the
# pre-existing redact_url block above): a query string or '#' fragment can itself carry credential
# material (e.g. '?token=SECRET123') and, since it sits strictly after the final path segment,
# previously rendered verbatim.
RU2_OUT=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("repo_verify", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
cases = {
    "https://host/o/r.git?token=SECRET123": "host/o/r",
    "https://host/o/r.git#fragment-secret": "host/o/r",
    "https://user:pass@host/o/r.git?token=SECRET123": "host/o/r",
}
ok = True
for url, expected in cases.items():
    out = m.redact_url(url)
    leaked = ("SECRET123" in out) or ("fragment-secret" in out)
    status = "OK" if (out == expected and not leaked) else "MISMATCH_OR_LEAK"
    if out != expected or leaked:
        ok = False
    print("%s url=%r got=%r expected=%r" % (status, url, out, expected))
print("ALL_OK" if ok else "SOME_FAILED")
PY
)
while IFS= read -r ru2_line; do printf '   %s\n' "$ru2_line"; done <<<"$RU2_OUT"
case "$RU2_OUT" in
  *ALL_OK*) ok "redact_url: query-string ('?token=...') and fragment ('#...') credential material no longer leaks (T158 remediation round 2 MINOR fix confirmed, 11.4.10)" ;;
  *) not_ok "redact_url (round 2 query-string/fragment): at least one case failed or leaked -- see output above" ;;
esac

# ================================================================================================
# T158 remediation round 4 -- fixtures/mutations closing the FOURTH independent review's three
# IMPORTANT findings (I4-1 redact_url still leaking on '/'+'?'/'#' userinfo + a NEW scp-form leak,
# I4-2 the unvalidated inner-'@' strip branch, I4-3 GIT_OPTIONAL_LOCKS=0 with zero coverage).
# Every earlier assertion above stays in place.
# ================================================================================================

# --- shared redact_url checker: run against the real tool AND against each mutant below ---------
# Two oracles, both independent of the implementation:
#  (a) the reviewer's exact 5-URL leak table + the I4-2 shape + positive controls (case-2 URLs that
#      MUST still render a real host, so a "redact everything" implementation cannot pass);
#  (b) a seeded, deterministic property test: credential bytes and query-secret bytes are drawn
#      ONLY from UPPERCASE letters, host/path/query-key bytes ONLY from lowercase, with '/', '?',
#      '#', '@', ':' sprinkled into the credential and query parts in random positions. Any output
#      other than the fixed placeholder that contains an uppercase letter is a credential/secret
#      leak, regardless of HOW the parser was fooled -- this tests the CLASS, not 5 instances.
cat >"$TMP/r4_redact_check.py" <<'PY'
import importlib.util, random, sys
spec = importlib.util.spec_from_file_location("repo_verify", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
PH = "REDACTED_AMBIGUOUS_URL"
ok = True
table = {
    # I4-1: the reviewer's leak table (rows 1-4 leaked in rounds 2+3; row 5 is round 3's NEW leak)
    "https://user:se/cr?et@github.com/org/repo.git": PH,
    "https://pa/ss#word@github.com/o/r.git": PH,
    "https://tok/en?x@github.com/o/r.git": PH,
    "https://user:SEC@RET/x?y@github.com/o/r.git": PH,
    "user:SE/CR?ET@github.com:org/repo.git": PH,
    # I4-2: credentials present AND a literal '@' inside the query after them
    "https://u:pw@host/o/r.git?u=a@S": PH,
    # positive controls (case 2: last '@' strictly before any '?'/'#') -- real host still shown
    "https://user:pa/ss@github.com/org/repo.git": "github.com/org/repo",
    "https://user:p@ss@github.com/org/repo.git": "github.com/org/repo",
    "https://user:pass@host/o/r.git?token=SECRET123": "host/o/r",
    "user:SE/CR@github.com:org/repo.git": "github.com/org/repo",
    "git@github.com:org/repo.git": "github.com/org/repo",
    "https://gitlab.com/g/sub/repo.git": "gitlab.com/g/sub/repo",
}
for url, expected in table.items():
    out = m.redact_url(url)
    if out != expected:
        ok = False
        print("TABLE_MISMATCH url=%r got=%r expected=%r" % (url, out, expected))
print("table: %d cases checked" % len(table))

rng = random.Random(20261001)
UP = "QWXZJKV"
LO = "abcdefghmn"
SEP = "/?#@:"
def creds():
    parts = [rng.choice(UP) for _ in range(rng.randint(1, 8))]
    for _ in range(rng.randint(0, 4)):
        parts.insert(rng.randint(0, len(parts)), rng.choice(SEP))
    return "".join(parts)
def lw(n):
    return "".join(rng.choice(LO) for _ in range(n))
leaks = 0
placeholders = 0
N = 20000
for i in range(N):
    host = lw(rng.randint(1, 6)) + ".io"
    path = "/".join(lw(rng.randint(1, 5)) for _ in range(rng.randint(1, 3))) + ".git"
    userinfo = creds() + "@" if rng.random() < 0.9 else ""
    query = ""
    r = rng.random()
    if r < 0.4:
        qv = "".join(rng.choice(UP + "@/:") for _ in range(rng.randint(1, 6)))
        query = rng.choice("?#") + lw(2) + "=" + qv
    form = rng.random()
    if form < 0.7:
        url = rng.choice(["https", "ssh", "git"]) + "://" + userinfo + host + "/" + path + query
    else:
        url = userinfo + host + ":" + path + query
    out = m.redact_url(url)
    if out == PH:
        placeholders += 1
        continue
    if any(c.isupper() for c in out):
        leaks += 1
        if leaks <= 5:
            print("PROPERTY_LEAK url=%r got=%r" % (url, out))
print("property: %d urls, %d placeholder, %d leaks" % (N, placeholders, leaks))
if leaks:
    ok = False
print("ALL_OK" if ok else "SOME_FAILED")
PY

R4_OUT=$(python3 "$TMP/r4_redact_check.py" "$TOOL" 2>&1)
while IFS= read -r r4_line; do printf '   %s\n' "$r4_line"; done <<<"$R4_OUT"
case "$R4_OUT" in
  *ALL_OK*) ok "redact_url (I4-1/I4-2, round 4): all 5 reviewer leak-table URLs (incl. the NEW scp-form row) and the creds-plus-'@'-in-query shape fail closed to the placeholder; positive controls still render a real host; 20000-URL seeded property test finds ZERO credential/secret bytes in any output (11.4.10)" ;;
  *) not_ok "redact_url (I4-1/I4-2, round 4): table mismatch or property-test leak -- see output above" ;;
esac

# --- paired mutation M-I4-1: restore round 3's '/'-before-'?' heuristic (with its inner '@' strip)
printf '%s' '    if at >= qpos:
        return None
' >"$TMP/r4m1_old.txt"
printf '%s' '    if at >= qpos and "/" in s[:qpos]:
        pre = s[:qpos]
        at_pre = pre.rfind("@")
        return pre[at_pre + 1:] if at_pre != -1 else pre
' >"$TMP/r4m1_new.txt"
if mk_mutant mutant_r4m1 "$TMP/r4m1_old.txt" "$TMP/r4m1_new.txt" 2>"$TMP/mutant_r4m1.err"; then
  R4M1_OUT=$(python3 "$TMP/r4_redact_check.py" "$TMP/mutant_r4m1/verify/repo_verify.py" 2>&1)
  case "$R4M1_OUT" in
    *SOME_FAILED*PROPERTY_LEAK*|*PROPERTY_LEAK*SOME_FAILED*|*TABLE_MISMATCH*SOME_FAILED*)
      ok "paired mutation CAUGHT (I4-1): restoring round 3's '/'-before-'?'/'#' heuristic makes the round-4 checker FAIL (leak table and/or property test) -- confirms the fail-closed branch is load-bearing" ;;
    *) not_ok "paired mutation (I4-1): expected the round-3-heuristic mutant to fail the redact checker, got: $R4M1_OUT" ;;
  esac
else
  not_ok "paired mutation (I4-1): mutation anchor text not found -- source moved, update this test's anchor: $(cat "$TMP/mutant_r4m1.err")"
fi

# --- paired mutation M-I4-2: the reviewer's own mutant -- round 3's branch with an UNCONDITIONAL
# 'return pre' (no inner-'@' strip). Post-restructure the strip branch no longer exists; this mutant
# re-introduces it in its worst form and the I4-2 fixture (https://u:pw@host/o/r.git?u=a@S) MUST
# catch it.
printf '%s' '    if at >= qpos:
        pre = s[:qpos]
        return pre
' >"$TMP/r4m2_new.txt"
if mk_mutant mutant_r4m2 "$TMP/r4m1_old.txt" "$TMP/r4m2_new.txt" 2>"$TMP/mutant_r4m2.err"; then
  R4M2_OUT=$(python3 "$TMP/r4_redact_check.py" "$TMP/mutant_r4m2/verify/repo_verify.py" 2>&1)
  case "$R4M2_OUT" in
    *"TABLE_MISMATCH url='https://u:pw@host/o/r.git?u=a@S'"*SOME_FAILED*)
      ok "paired mutation CAUGHT (I4-2): an unconditional 'return pre' in the ambiguous branch leaks 'u:pw@...' and the I4-2 fixture catches it -- the creds-plus-'@'-in-query shape is now pinned" ;;
    *) not_ok "paired mutation (I4-2): expected the I4-2 fixture to catch the unconditional-'return pre' mutant, got: $R4M2_OUT" ;;
  esac
else
  not_ok "paired mutation (I4-2): mutation anchor text not found -- source moved, update this test's anchor: $(cat "$TMP/mutant_r4m2.err")"
fi

# --- paired mutation M-I4-1b: delete the ambiguity check entirely ("text after the last '@'")
printf '%s' '' >"$TMP/r4m3_new.txt"
if mk_mutant mutant_r4m3 "$TMP/r4m1_old.txt" "$TMP/r4m3_new.txt" 2>"$TMP/mutant_r4m3.err"; then
  R4M3_OUT=$(python3 "$TMP/r4_redact_check.py" "$TMP/mutant_r4m3/verify/repo_verify.py" 2>&1)
  case "$R4M3_OUT" in
    *PROPERTY_LEAK*SOME_FAILED*)
      ok "paired mutation CAUGHT (I4-1b): removing the ambiguity check entirely (always render the text after the last '@') leaks query-secret bytes and the property test catches it" ;;
    *) not_ok "paired mutation (I4-1b): expected the property test to catch the no-ambiguity-check mutant, got: $R4M3_OUT" ;;
  esac
else
  not_ok "paired mutation (I4-1b): mutation anchor text not found -- source moved: $(cat "$TMP/mutant_r4m3.err")"
fi

# --- I4-3: GIT_OPTIONAL_LOCKS=0 -- stale-stat fixture, top-level AND submodule --------------------
# A tracked file whose mtime no longer matches the index entry makes a plain `git status` refresh
# and REWRITE .git/index. The real tool must leave both the parent's and a submodule's index
# byte-identical; dropping GIT_OPTIONAL_LOCKS=0 must rewrite them on the SAME fixture. No git
# command is run in the fixture between the touch and the md5 snapshots (that would refresh it).
build_stale_stat() {  # build_stale_stat <root>
  build_good_clean "$1"
  touch -d 2020-01-01 "$1/parent/f.txt" "$1/parent/subA/f.txt"
}
SS="$TMP/rv_i43_stale_stat"
build_stale_stat "$SS"
SS_SUB_GD=$(real_gitdir "$SS/parent/subA")
ss_p0=$(md5sum <"$SS/parent/.git/index"); ss_s0=$(md5sum <"$SS_SUB_GD/index")
run_tool "$SS/parent" "$TMP/i43.json"; SSRC=$?
ss_p1=$(md5sum <"$SS/parent/.git/index"); ss_s1=$(md5sum <"$SS_SUB_GD/index")
if [ "$SSRC" -eq 0 ] && [ "$ss_p0" = "$ss_p1" ] && [ "$ss_s0" = "$ss_s1" ]; then
  ok "rv_i43_stale_stat (I4-3): with stale-stat tracked files at top level AND in subA, the real tool reports CLEAN (rc=0) and leaves BOTH .git/index files byte-identical"
else
  not_ok "rv_i43_stale_stat (I4-3): rc=$SSRC parent_index_same=$([ "$ss_p0" = "$ss_p1" ] && echo y || echo n) sub_index_same=$([ "$ss_s0" = "$ss_s1" ] && echo y || echo n)"
fi
printf '%s' 'env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")' >"$TMP/r4m4_old.txt"
printf '%s' 'env = dict(os.environ)' >"$TMP/r4m4_new.txt"
if mk_mutant mutant_r4m4 "$TMP/r4m4_old.txt" "$TMP/r4m4_new.txt" 2>"$TMP/mutant_r4m4.err"; then
  SSM="$TMP/rv_i43_stale_stat_mut"
  build_stale_stat "$SSM"
  SSM_SUB_GD=$(real_gitdir "$SSM/parent/subA")
  ssm_p0=$(md5sum <"$SSM/parent/.git/index"); ssm_s0=$(md5sum <"$SSM_SUB_GD/index")
  python3 "$TMP/mutant_r4m4/verify/repo_verify.py" --recursive --root "$SSM/parent" --out "$TMP/i43_mut.json" >"$TMP/i43_mut.out" 2>"$TMP/i43_mut.err"
  ssm_p1=$(md5sum <"$SSM/parent/.git/index"); ssm_s1=$(md5sum <"$SSM_SUB_GD/index")
  if [ "$ssm_p0" != "$ssm_p1" ] && [ "$ssm_s0" != "$ssm_s1" ]; then
    ok "paired mutation CAUGHT (I4-3): dropping GIT_OPTIONAL_LOCKS=0 rewrites BOTH the parent's and subA's .git/index on the SAME stale-stat fixture -- confirms the env var is genuinely load-bearing at both levels"
  else
    not_ok "paired mutation (I4-3): expected the mutant to rewrite both indexes, got parent_changed=$([ "$ssm_p0" != "$ssm_p1" ] && echo y || echo n) sub_changed=$([ "$ssm_s0" != "$ssm_s1" ] && echo y || echo n)"
  fi
else
  not_ok "paired mutation (I4-3): mutation anchor text not found -- source moved: $(cat "$TMP/mutant_r4m4.err")"
fi

[ "$fail" -eq 0 ] && exit 0 || exit 1
