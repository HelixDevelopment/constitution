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
[ "$BBLIND_FLAG" = "True" ] && ok "rv_blind_remote: report body carries BLIND:true (C-001 code-4 convention)" \
  || not_ok "rv_blind_remote: expected BLIND:true in the written report, got $BBLIND_FLAG"

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
[ "$DCRC" -eq 0 ] && ok "rv_determinism: the tool's own --determinism-check flag exits 0 on the clean fixture" \
  || not_ok "rv_determinism: --determinism-check exited rc=$DCRC (expected 0): $(cat "$TMP/detcheck.err")"

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
            "name": remote, "url_redacted": redacted, "remote_tip": "UNREACHABLE",
            "local_tip": local_tip, "equal": False, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_detail": err,
        }, "REMOTE_UNREACHABLE"'''
new = '''    if tip is None:
        return {
            "name": remote, "url_redacted": redacted, "remote_tip": "UNREACHABLE",
            "local_tip": local_tip, "equal": True, "last_push_result": last_push_str,
            "_unpushed": "UNKNOWN", "_detail": err,
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

[ "$fail" -eq 0 ] && exit 0 || exit 1
