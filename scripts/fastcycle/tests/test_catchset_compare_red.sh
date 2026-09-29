#!/bin/bash
# Purpose : T050 (SpecKit-004 "fast-dev-cycles", User Story 2) RED baseline
#           for `constitution/scripts/fastcycle/gates/catchset_compare.py`
#           (and its sibling `gates/gate_audit.py`) per contract
#           catch-set-comparison-harness
#           (specs/004-fast-dev-cycles/contracts/catch-set-comparison-harness.md)
#           and plan.md task T-C00 -- proves the tool is absent today by
#           GENUINELY INVOKING it (never merely `[ -f ... ]`), and ships the
#           full RED-fixtures table (8 contract rows + 1 task-line-driven
#           addition, contracts/catch-set-comparison-harness.md's "RED
#           fixtures" section) under
#           constitution/scripts/fastcycle/tests/fixtures/catchset_compare/
#           as real, self-consistent, executable inputs for T064's
#           implementer to consume, per contract C-005 (self-validation
#           triple) and the four behaviours tasks.md's own T050 line names:
#             (1) golden-good  -- a defect caught today is recorded caught
#                                 (cs_good_equal)
#             (2) golden-bad   -- a new run missing one defect FAILs and
#                                 names it (cs_bad_dropped_gate)
#             (3) negative control -- a run catching more PASSes
#                                 (cs_negctrl_gained_catch)
#             (4) determinism  -- two baseline runs identical
#                                 (check_determinism, reusing cs_good_equal)
#
# THE GAP (verified directly, 2026-09-28, against git HEAD
# e11d96b47447f8310a0123b884a3f0ac1320ab98): plan.md places `catchset_compare.py` and
# `gate_audit.py` under `constitution/scripts/fastcycle/gates/`
# ("gates/catchset_compare.py  # FR-006 corpus-build + differential compare
# (T-C00, T-H01)"). `constitution/scripts/fastcycle/gates/` today contains
# only a `.gitkeep` placeholder -- neither file exists. tasks.md's own T064
# line ("Implement `constitution/scripts/fastcycle/gates/catchset_compare.py`
# `corpus-build` ... and `compare` until T050 is GREEN") names the
# implementer explicitly: a LATER, SEPARATE task from this one.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T050); T064's implementation of catchset_compare.py/gate_audit.py is a
# separate, later task this file's author never implements.
#
# RED, not a contract-stub bluff (§11.4.1/§11.4.6, mirroring the
# post-T036/T023-review remediation lesson already applied to sibling RED
# tests in this suite -- see test_cycle_report_red.sh's and
# test_dispatch_stamp_red.sh's own headers): this file does not merely
# PRINT prose describing the absent tool and exit 0 regardless. Section
# "REAL invocation assertions" below GENUINELY INVOKES
# `python3 $CATCHSET_COMPARE ...` and `python3 $GATE_AUDIT ...` with
# realistic, contract-shaped arguments and asserts each run produces the
# REAL outcome named in that fixture's own expected.json (exact exit code
# + output-file-written state) -- never a blanket "must fail". While the
# tool is absent, python3 refuses to open the nonexistent script file
# (exit 2, no output written), which never matches any fixture's real
# expected outcome, so every assertion correctly reports "NOT ok" today --
# that is what drives this file's own exit code to nonzero. Once T064
# lands, these same blocks keep testing something real (the tool's actual
# per-fixture behaviour) with NO further edits needed: the assertion was
# always "does the real invocation match the fixture's real expected
# outcome", never "does the invocation merely fail" -- self-flipping
# polarity by construction, unlike a bare presence check.
#
# §11.4.273 control needles (two, independent):
#   #1 -- before trusting "gates/catchset_compare.py is absent" as a
#         finding, a KNOWN-PRESENT sibling ($FC/lib/fc_common.sh, used
#         throughout this suite) is confirmed to resolve through this
#         file's own relative-path construction first.
#   #2 -- before trusting any toy gate's "no catch" (PASS) result as
#         evidence of absence-of-defect, a FABRICATED file containing a
#         marker string NO gate in this fixture set checks for is run
#         through gate_marker.sh and confirmed to still report FAIL (the
#         gate genuinely checks for its OWN specific token, not merely
#         "some marker exists").
#
# §11.4.273 forensic instance (found authoring this file's fixtures,
# 2026-09-28, fixed BEFORE this test was ever written against them): an
# earlier revision of the toy gate scripts (gate_marker.sh etc.) grepped
# their target's SOURCE TEXT for the bare token "SAFE_MARKER" -- but every
# defect-patch file's own comment header names the marker it removes
# ("drops SAFE_MARKER only"), so the gate false-PASSed against a patch that
# HAD genuinely removed the marker's `echo` line: a textbook carrier
# false-match (the gate matched the comment PROSE describing the removal,
# not the removed thing itself -- §11.4.201(7)(a)). Fixed by making every
# toy gate grep the target's RUNTIME OUTPUT (`sh "$1" | grep ...`), never
# its source text, and by using a two-word runtime token ("SAFE MARKER")
# distinct from the underscored identifier ("SAFE_MARKER") every comment in
# this fixture set freely uses in prose. Manually re-verified against the
# full clean/D1/D_extra/D_uncaught matrix before this test was authored
# (recorded as this file's own "fixture self-consistency" checks below, so
# the proof is re-runnable, not merely a one-off manual transcript).
#
# CS-001 isolation: every disposable copy below is created under `mktemp -d`
# (never under this fixture directory, never under the real project tree);
# a canary file inside the real repo ($FC/lib/fc_common.sh) is sha256-hashed
# before any work begins and again after every check completes -- the two
# MUST be identical (cs_real_tree_untouched, contract fixtures-table row 9).
#
# Usage : bash test_catchset_compare_red.sh   Exit 0 = every check below
#         held (expected ONLY after T064 lands catchset_compare.py/
#         gate_audit.py AND their real behaviour matches every fixture's
#         own expected.json -- no edits to this file needed for that
#         transition, the assertions are already written against the real
#         per-fixture expected outcome); exit 1 today = correct RED state
#         (the real tool is absent, so every real-invocation assertion
#         below correctly cannot match its fixture's expected outcome).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/catchset_compare"
SHARED="$FIXDIR/_shared"
CATCHSET_COMPARE="$FC/gates/catchset_compare.py"
GATE_AUDIT="$FC/gates/gate_audit.py"

fail=0
failx() { fail=1; }

WORK=$(mktemp -d) || { echo "cannot create scratch dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# --- real-tree-untouched canary (cs_real_tree_untouched, row 9) ---
CANARY="$FC/lib/fc_common.sh"
canary_hash() { sha256sum "$CANARY" 2>/dev/null | awk '{print $1}'; }
CANARY_BEFORE=$(canary_hash)

# --- §11.4.273 control needle #1: known-present sibling resolves ---
KNOWN_PRESENT="$FC/lib/fc_common.sh"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.sh) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- real corpus sources exist (Invocation section prerequisite) ---
REAL_MUTATION_SRC="$ROOT/scripts/testing/meta_test_false_positive_proof.sh"
REAL_GUARD_REGISTRY="$ROOT/device/rockchip/rk3588/tests/regression_guard/registry.tsv"
if [ -f "$REAL_MUTATION_SRC" ] && [ -f "$REAL_GUARD_REGISTRY" ]; then
  echo "ok real corpus sources exist: $REAL_MUTATION_SRC and"
  echo "   $REAL_GUARD_REGISTRY are both present -- T064's corpus-build has"
  echo "   real sources to assemble corpus.json from (the toy fixtures"
  echo "   below are synthetic per contract clause C-005, independent of"
  echo "   this fact, and do not depend on the real corpus's exact size)"
else
  echo "NOT ok: one or both real corpus sources are missing"
  echo "     ($REAL_MUTATION_SRC, $REAL_GUARD_REGISTRY)"
  failx
fi

# --- (1) absence proof: catchset_compare.py / gate_audit.py ---
# Polarity (this IS the RED signal, deliberately -- the assertion below is
# "the guarded tool exists and is invocable", which is currently FALSE):
# absent -> "NOT ok" + failx (today's correct, expected RED state); present
# -> "ok" (T064 has landed; every real-invocation assertion further below
# then takes over as the load-bearing GREEN check against each fixture's
# REAL expected outcome, mirroring the post-T036/T023-review polarity-flip
# precedent this suite already documents for its own guarded tools).
if [ -f "$CATCHSET_COMPARE" ] && [ -f "$GATE_AUDIT" ]; then
  echo "ok $CATCHSET_COMPARE and $GATE_AUDIT now exist -- T064 has landed;"
  echo "   the real-invocation assertions below are the load-bearing check"
else
  echo "NOT ok $CATCHSET_COMPARE and/or $GATE_AUDIT do not exist yet"
  echo "     (T064, a LATER task, has not landed) -- this IS today's"
  echo "     correct RED state for T050"
  failx
fi

json_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }
json_bool_field() { python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))[sys.argv[2]]).lower())' "$1" "$2"; }

# --- REAL invocation assertions (this is what makes the test genuinely RED
# for the RIGHT reason, not merely a presence-check bluff) ---
# Each block GENUINELY runs `python3 $TOOL ...` with contract-shaped
# arguments and asserts the run produces the REAL, fixture-specific
# outcome named in that fixture's own expected.json (exact exit code +
# output-file-written state -- never a heuristic "did it error somehow").
# While the tool is absent, python3 refuses to open the nonexistent script
# file (exit 2, no output written) -- which never matches a fixture's real
# expected_exit_code (0 or 1) or its real written-output expectation, so
# every block below correctly reports "NOT ok" + failx today. Once T064
# lands, these same blocks keep testing something real (the tool's actual
# per-fixture behaviour) with no further edits needed -- self-flipping
# polarity by construction, unlike a bare presence check.
assert_corpus_build() {
  local out="$WORK/corpus.json"
  rm -f "$out"
  python3 "$CATCHSET_COMPARE" corpus-build \
    --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --out "$out" >"$WORK/corpus-build.stdout" 2>"$WORK/corpus-build.stderr"
  local rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$out" ]; then
    echo "ok corpus-build: real invocation succeeded (exit 0), $out written and non-empty"
  else
    echo "NOT ok corpus-build: real invocation did not meet its required"
    echo "     outcome (exit=$rc, out written=$([ -s "$out" ] && echo yes || echo no));"
    echo "     required: exit 0 + a non-empty $out (T-C00's own protecting-test"
    echo "     bar). Current reason: $CATCHSET_COMPARE does not exist yet"
    echo "     (T064 not landed) -- stderr: $(tail -1 "$WORK/corpus-build.stderr" 2>/dev/null)"
    failx
  fi
}
assert_corpus_build

assert_compare_fixture_real() {
  local fx="$1" out exp_exit rc
  out="$WORK/${fx}.catchset.json"
  rm -f "$out"
  python3 "$CATCHSET_COMPARE" compare \
    --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --corpus "$WORK/corpus.json" \
    --old "$FIXDIR/$fx/config_old.json" \
    --new "$FIXDIR/$fx/config_new.json" \
    --workdir "$WORK/compare_workdir_$fx" \
    --out "$out" >"$WORK/compare_${fx}.stdout" 2>"$WORK/compare_${fx}.stderr"
  rc=$?
  exp_exit=$(json_field "$FIXDIR/$fx/expected.json" expected_exit_code)
  if [ "$rc" -eq "$exp_exit" ] && [ -f "$out" ]; then
    echo "ok compare.$fx: real invocation exit=$rc matches fixture's"
    echo "   expected_exit_code=$exp_exit, $out written"
  else
    echo "NOT ok compare.$fx: real invocation exit=$rc, out written=$([ -f "$out" ] && echo yes || echo no)"
    echo "     but fixture requires exit=$exp_exit + a written $out."
    echo "     Current reason: $CATCHSET_COMPARE does not exist yet"
    echo "     (T064 not landed) -- stderr: $(tail -1 "$WORK/compare_${fx}.stderr" 2>/dev/null)"
    failx
  fi
}
assert_compare_fixture_real cs_good_equal
assert_compare_fixture_real cs_bad_dropped_gate

assert_transfer_proof_real() {
  local fx="$1" out gate exp_exit exp_written rc actually_written
  out="$WORK/${fx}.transfer.json"
  rm -f "$out"
  gate=$(json_field "$FIXDIR/$fx/removal_request.json" removed_gate_id)
  python3 "$GATE_AUDIT" transfer-proof \
    --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --gate "$gate" --into g_marker --out "$out" \
    >"$WORK/transfer_${fx}.stdout" 2>"$WORK/transfer_${fx}.stderr"
  rc=$?
  exp_exit=$(json_field "$FIXDIR/$fx/expected.json" expected_exit_code)
  exp_written=$(json_bool_field "$FIXDIR/$fx/expected.json" transfer_record_written)
  if [ -f "$out" ]; then actually_written=true; else actually_written=false; fi
  if [ "$rc" -eq "$exp_exit" ] && [ "$actually_written" = "$exp_written" ]; then
    echo "ok transfer-proof.$fx: real invocation exit=$rc matches"
    echo "   expected_exit_code=$exp_exit, transfer_record_written=$actually_written matches"
  else
    echo "NOT ok transfer-proof.$fx: real invocation exit=$rc"
    echo "     transfer_record_written=$actually_written, but fixture requires"
    echo "     exit=$exp_exit transfer_record_written=$exp_written."
    echo "     Current reason: $GATE_AUDIT does not exist yet (T064 not landed)"
    echo "     -- stderr: $(tail -1 "$WORK/transfer_${fx}.stderr" 2>/dev/null)"
    failx
  fi
}
assert_transfer_proof_real cs_bad_removal_no_transfer
assert_transfer_proof_real cs_negctrl_removal_with_transfer

# --- (2) fixture presence: all 9 rows of the contract RED-fixtures table ---
require_file() {
  if [ -f "$1" ]; then
    echo "ok fixture file present: ${1#"$FIXDIR"/}"
  else
    echo "NOT ok fixture file MISSING: ${1#"$FIXDIR"/}"
    failx
  fi
}
require_file "$SHARED/base_tree/widget.sh"
for g in gate_marker gate_marker_dup gate_extra gate_noop; do
  require_file "$SHARED/gates/$g.sh"
done
for p in defect_d1_widget defect_d_extra_widget defect_d_uncaught_widget; do
  require_file "$SHARED/patches/$p.sh"
done
for fx in cs_good_equal cs_bad_dropped_gate cs_bad_overeager_skip cs_bad_stale_cache cs_negctrl_old_missed cs_negctrl_gained_catch; do
  require_file "$FIXDIR/$fx/config_old.json"
  require_file "$FIXDIR/$fx/config_new.json"
  require_file "$FIXDIR/$fx/expected.json"
  require_file "$FIXDIR/$fx/README.md"
done
for fx in cs_bad_removal_no_transfer cs_negctrl_removal_with_transfer; do
  require_file "$FIXDIR/$fx/surviving_config.json"
  require_file "$FIXDIR/$fx/removal_request.json"
  require_file "$FIXDIR/$fx/expected.json"
  require_file "$FIXDIR/$fx/README.md"
done
require_file "$FIXDIR/cs_real_tree_untouched/README.md"
require_file "$FIXDIR/PAIRED_MUTATION_NOTE.md"
require_file "$FIXDIR/cs_bad_overeager_skip/skip_map.json"
require_file "$FIXDIR/cs_bad_stale_cache/stale_cache.json"

# --- (3) parse-clean: every shared toy script (§11.4.67) ---
for s in "$SHARED"/gates/*.sh "$SHARED"/patches/*.sh "$SHARED"/base_tree/*.sh; do
  if sh -n "$s" 2>"$WORK/parse.err"; then
    echo "ok parse-clean: ${s#"$FIXDIR"/}"
  else
    echo "NOT ok parse error in ${s#"$FIXDIR"/}: $(cat "$WORK/parse.err")"
    failx
  fi
done

# --- §11.4.273 control needle #2: a fabricated marker must not false-catch ---
printf '#!/bin/sh\necho "FABRICATED MARKER"\n' >"$WORK/fabricated.sh"
chmod +x "$WORK/fabricated.sh"
sh "$SHARED/gates/gate_marker.sh" "$WORK/fabricated.sh" >/dev/null 2>&1
fab_rc=$?
if [ "$fab_rc" -eq 1 ]; then
  echo "ok control needle #2: gate_marker.sh correctly reports FAIL (exit 1)"
  echo "   against a fabricated file whose only marker is unrelated -- the"
  echo "   gate genuinely checks for its OWN token, not any string"
else
  echo "NOT ok control needle #2: gate_marker.sh reported exit $fab_rc"
  echo "     (expected 1) against a fabricated unrelated-marker file -- the"
  echo "     gate is not trustworthy and every fixture below is suspect"
  failx
fi

# --- fixture self-consistency: independently re-derive each defect-corpus ---
# fixture's outcome from the REAL toy gates + REAL disposable copies, and
# diff against the fixture's own expected.json. Proves the fixtures T064
# will be graded against are themselves internally correct (C-005), and is
# INDEPENDENT of whether catchset_compare.py exists (pure bash + the toy
# gate scripts) -- so this section, unlike "REAL invocation attempts" above,
# is expected to be GREEN today.
list_gates() {  # $1=config json -> "id\tscript" lines, script resolved relative to json's dir
  python3 -c '
import json, os, sys
cfg = sys.argv[1]
d = json.load(open(cfg))
base = os.path.dirname(os.path.abspath(cfg))
for g in d["gates"]:
    print(g["id"] + "\t" + os.path.normpath(os.path.join(base, g["script"])))
' "$1"
}
run_gate() { sh "$1" "$2" >/dev/null 2>&1; echo $?; }
make_copy() {
  local patch="$1" d
  d=$(mktemp -d -p "$WORK") || return 1
  if [ -n "$patch" ]; then cp "$patch" "$d/widget.sh"; else cp "$SHARED/base_tree/widget.sh" "$d/widget.sh"; fi
  chmod +x "$d/widget.sh"
  printf '%s\n' "$d"
}
verdict_map() {  # $1=config json $2=target file -> sorted "id=PASS|FAIL" lines
  local cfg="$1" target="$2"
  while IFS=$'\t' read -r gid gscript; do
    ec=$(run_gate "$gscript" "$target")
    if [ "$ec" -eq 0 ]; then echo "$gid=PASS"; else echo "$gid=FAIL"; fi
  done < <(list_gates "$cfg") | sort
}
apply_skip_override() {  # $1=skip_map.json $2=raw verdict map (stdin unused; passed as $2 literal)
  local skipmap="$1" vm="$2" ids
  ids=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for e in d["skip_map"]:
    print(e["gate_id"])
' "$skipmap")
  printf '%s\n' "$vm" | while IFS='=' read -r gid verdict; do
    if printf '%s\n' "$ids" | grep -qx "$gid"; then echo "$gid=PASS"; else echo "$gid=$verdict"; fi
  done
}
apply_stale_cache_override() {
  local cache="$1" vm="$2" overrides
  overrides=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for e in d["stale_cache_entries"]:
    print(e["gate_id"] + "=" + e["cached_verdict"])
' "$cache")
  printf '%s\n' "$vm" | while IFS='=' read -r gid verdict; do
    ov=$(printf '%s\n' "$overrides" | awk -F= -v g="$gid" '$1==g{print $2}')
    if [ -n "$ov" ]; then echo "$gid=$ov"; else echo "$gid=$verdict"; fi
  done
}
is_caught() { grep -q '=FAIL$'; }  # reads a verdict map on stdin
# json_field / json_bool_field already defined earlier (§ REAL invocation assertions).

check_compare_fixture() {
  local fx="$1" patch="$2" dir
  dir="$FIXDIR/$fx"
  local old_copy new_copy old_vm new_vm old_verdict new_verdict
  old_copy=$(make_copy "$patch")
  new_copy=$(make_copy "$patch")
  old_vm=$(verdict_map "$dir/config_old.json" "$old_copy/widget.sh")
  new_vm=$(verdict_map "$dir/config_new.json" "$new_copy/widget.sh")
  case "$fx" in
    cs_bad_overeager_skip) new_vm=$(apply_skip_override "$dir/skip_map.json" "$new_vm") ;;
    cs_bad_stale_cache)    new_vm=$(apply_stale_cache_override "$dir/stale_cache.json" "$new_vm") ;;
  esac
  if printf '%s\n' "$old_vm" | is_caught; then old_verdict=CAUGHT; else old_verdict=MISSED; fi
  if printf '%s\n' "$new_vm" | is_caught; then new_verdict=CAUGHT; else new_verdict=MISSED; fi
  local exp_old exp_new exp_exit computed_exit
  exp_old=$(json_field "$dir/expected.json" old_verdict)
  exp_new=$(json_field "$dir/expected.json" new_verdict)
  exp_exit=$(json_field "$dir/expected.json" expected_exit_code)
  if [ "$old_verdict" = "CAUGHT" ] && [ "$new_verdict" = "MISSED" ]; then computed_exit=1; else computed_exit=0; fi
  if [ "$old_verdict" = "$exp_old" ] && [ "$new_verdict" = "$exp_new" ] && [ "$computed_exit" = "$exp_exit" ]; then
    echo "ok $fx: computed old=$old_verdict new=$new_verdict exit=$computed_exit matches expected.json"
  else
    echo "NOT ok $fx: computed old=$old_verdict new=$new_verdict exit=$computed_exit but"
    echo "     expected.json says old=$exp_old new=$exp_new exit=$exp_exit"
    failx
  fi
}

check_removal_fixture() {
  local fx="$1" dir
  dir="$FIXDIR/$fx"
  local patch copy vm can_fail exp_status
  patch=$(python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
base = os.path.dirname(os.path.abspath(sys.argv[1]))
print(os.path.normpath(os.path.join(base, d["removed_gate_paired_mutation_patch"])))
' "$dir/removal_request.json")
  copy=$(make_copy "$patch")
  vm=$(verdict_map "$dir/surviving_config.json" "$copy/widget.sh")
  if printf '%s\n' "$vm" | is_caught; then can_fail=PROVEN; else can_fail=NOT_PROVEN; fi
  exp_status=$(json_field "$dir/expected.json" can_fail_status)
  if [ "$can_fail" = "$exp_status" ]; then
    echo "ok $fx: computed can_fail_status=$can_fail matches expected.json"
  else
    echo "NOT ok $fx: computed can_fail_status=$can_fail but expected.json says $exp_status"
    failx
  fi
}

check_compare_fixture cs_good_equal          "$SHARED/patches/defect_d1_widget.sh"
check_compare_fixture cs_bad_dropped_gate    "$SHARED/patches/defect_d1_widget.sh"
check_compare_fixture cs_bad_overeager_skip  "$SHARED/patches/defect_d1_widget.sh"
check_compare_fixture cs_bad_stale_cache     "$SHARED/patches/defect_d1_widget.sh"
check_compare_fixture cs_negctrl_old_missed  "$SHARED/patches/defect_d_uncaught_widget.sh"
check_compare_fixture cs_negctrl_gained_catch "$SHARED/patches/defect_d_extra_widget.sh"
check_removal_fixture cs_bad_removal_no_transfer
check_removal_fixture cs_negctrl_removal_with_transfer

# --- (4) determinism: two independent baseline runs, byte-identical ---
check_determinism() {
  local dir="$FIXDIR/cs_good_equal" patch="$SHARED/patches/defect_d1_widget.sh"
  local copy1 copy2 vm1 vm2
  copy1=$(make_copy "$patch")
  copy2=$(make_copy "$patch")
  vm1=$(verdict_map "$dir/config_old.json" "$copy1/widget.sh")
  vm2=$(verdict_map "$dir/config_old.json" "$copy2/widget.sh")
  if [ "$vm1" = "$vm2" ]; then
    echo "ok determinism: two independent baseline runs of"
    echo "   cs_good_equal/config_old.json against fresh D1-mutated"
    echo "   disposable copies produce byte-identical verdict maps"
  else
    echo "NOT ok determinism: run1='$vm1' run2='$vm2' differ"
    failx
  fi
}
check_determinism

# --- real-tree-untouched, end-to-end (cs_real_tree_untouched) ---
CANARY_AFTER=$(canary_hash)
if [ -n "$CANARY_BEFORE" ] && [ "$CANARY_BEFORE" = "$CANARY_AFTER" ]; then
  echo "ok cs_real_tree_untouched: canary $CANARY sha256 unchanged"
  echo "   before/after all disposable-copy work ($CANARY_BEFORE)"
else
  echo "NOT ok cs_real_tree_untouched: canary hash changed or unreadable"
  echo "     (before=$CANARY_BEFORE after=$CANARY_AFTER)"
  failx
fi

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "test_catchset_compare_red.sh: GREEN -- catchset_compare.py and"
  echo "  gate_audit.py exist AND every real invocation matches its"
  echo "  fixture's real expected outcome (T064 has landed correctly)"
else
  echo "test_catchset_compare_red.sh: RED as expected -- the real tool is"
  echo "  absent (T064 not yet implemented), so every real-invocation"
  echo "  assertion above correctly cannot match its fixture's expected"
  echo "  outcome, while the toy fixture corpus itself (independent of"
  echo "  the absent tool) is proven self-consistent"
fi
exit "$fail"
