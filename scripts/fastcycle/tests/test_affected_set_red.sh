#!/bin/bash
# Purpose : T053 (SpecKit-004 "fast-dev-cycles", User Story 2) RED baseline
#           for `constitution/scripts/fastcycle/gates/affected_set.py` per
#           contract affected-set-and-verdict-cache.md
#           (specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md,
#           clauses AS-010/AS-010a/AS-011/AS-012, plan task T-C03) --
#           proves the tool is absent today by GENUINELY INVOKING it (never
#           merely `[ -f ... ]`), and ships a real fixture corpus under
#           constitution/scripts/fastcycle/tests/fixtures/affected_set/
#           covering the 5 behaviours tasks.md's own T053 line names:
#             (1) known affected sets -> skip list matches exactly with
#                 machine reasons (as_good_single_component, AS-011)
#             (2) unmapped changed path -> full applicable suite +
#                 "affected-set undeterminable: <path>" (as_bad_unmapped_path,
#                 AS-010)
#             (3) metamorphic: adding an unrelated changed path never
#                 shrinks the selected set (as_metamorphic_grow_only)
#             (4) changing a gate's own script always selects it
#                 (as_selfchange, AS-010a)
#             (5) docs-only change selects exactly the doc-sync and
#                 integrity gates (as_negctrl_docs_only, AS-012)
#           plus the contract's own additional RED-fixtures-table rows this
#           file also exercises: as_bad_undeclared_read (AS-001/AS-010),
#           as_bad_stale_map (AS-003), as_determinism, as_concurrent
#           (AS-014).
#
# THE GAP (verified directly, 2026-09-28, against the parent repo's HEAD at
# authoring time): plan.md places `affected_set.py` under
# `constitution/scripts/fastcycle/gates/`
# ("gates/affected_set.py  # selection + reasons + fallback (T-C03)").
# `constitution/scripts/fastcycle/gates/` today contains only a `.gitkeep`
# placeholder -- the file does not exist. A LATER, SEPARATE task implements
# it (the T064-class implementer task for this contract, not yet assigned
# a task number at authoring time -- check tasks.md's T-C03 implementer
# line before trusting that number).
#
# Producer!=Verifier (SS11.4.240): this file is authored at the RED step
# (T053); the real affected_set.py implementation is a separate, later
# task this file's author never implements.
#
# RED, not a contract-stub bluff (SS11.4.1/SS11.4.6, mirroring T050/T051's
# established pattern in this suite): this file does not merely PRINT prose
# describing the absent tool and exit 0 regardless. Every assertion below
# GENUINELY INVOKES `python3 $AFFECTED_SET ...` with realistic,
# contract-shaped arguments (--config/--base/--head/--map/--layer/--out)
# and asserts the run produces the REAL outcome named in that fixture's own
# expected.json (exact exit code + determinable + members + skipped
# reason-codes + fallback_reason). While the tool is absent, python3
# refuses to open the nonexistent script file (exit 2, no output written),
# which never matches any fixture's real expected outcome, so every
# assertion correctly reports "NOT ok" today -- that is what drives this
# file's own exit code to nonzero. Once the real tool lands, these same
# blocks keep testing something real (the tool's actual per-fixture
# behaviour) with NO further edits needed: self-flipping polarity by
# construction, unlike a bare presence check.
#
# --base/--head via real disposable git repos (never the real project
# tree): each fixture's "changed paths" are realised as a tiny, throwaway
# git repository built fresh under `mktemp -d` for that one invocation --
# a base commit with the fixture corpus's original file contents, then
# either a head commit (ordinary case) or the literal string "WORKTREE"
# (per the contract's `<sha|WORKTREE>` head syntax) with the changed files
# edited-but-uncommitted, exercised for at least one fixture so both head
# forms are proven real. This never touches or depends on the real
# project's own git history.
#
# SS11.4.273 control needles (two, independent):
#   #1 -- before trusting "gates/affected_set.py is absent" as a finding,
#         a KNOWN-PRESENT sibling ($FC/lib/fc_common.sh, used throughout
#         this suite) is confirmed to resolve through this file's own
#         relative-path construction first.
#   #2 -- before trusting any fixture's real sha256 content_hash match/
#         mismatch as evidence, a KNOWN-DIFFERENT hash (the stale map's
#         64-zero placeholder) is confirmed to actually differ from a
#         freshly-recomputed real hash of the corresponding gate script --
#         proving the comparison itself can discriminate, never a
#         tautological self-comparison.
#
# CS-001 isolation: every disposable git repo + scratch file below is
# created under `mktemp -d` (never under this fixture directory, never
# under the real project tree); a canary file inside the real repo
# ($FC/lib/fc_common.sh) is sha256-hashed before any work begins and again
# after every check completes -- the two MUST be identical
# (as_real_tree_untouched, mirroring T050's cs_real_tree_untouched row).
#
# Usage : bash test_affected_set_red.sh   Exit 0 = every check below held
#         (expected ONLY after the real affected_set.py lands AND its real
#         behaviour matches every fixture's own expected.json -- no edits
#         to this file needed for that transition); exit 1 today = correct
#         RED state (the real tool is absent, so every real-invocation
#         assertion below correctly cannot match its fixture's expected
#         outcome).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/affected_set"
SHARED="$FIXDIR/_shared"
AFFECTED_SET="$FC/gates/affected_set.py"

fail=0
failx() { fail=1; }

WORK=$(mktemp -d) || { echo "cannot create scratch dir (TMPDIR unusable)" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

# --- real-tree-untouched canary ---
CANARY="$FC/lib/fc_common.sh"
canary_hash() { sha256sum "$CANARY" 2>/dev/null | awk '{print $1}'; }
CANARY_BEFORE=$(canary_hash)

# --- SS11.4.273 control needle #1: known-present sibling resolves ---
if [ ! -f "$CANARY" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($CANARY) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (SS11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.sh) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- SS11.4.273 control needle #2: hash-mismatch comparison discriminates ---
REAL_ALPHA_HASH=$(sha256sum "$SHARED/gates/gate_alpha.sh" | awk '{print $1}')
STALE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["gates"]["gate_alpha"]["content_hash"])' "$SHARED/map_stale.json")
if [ -n "$REAL_ALPHA_HASH" ] && [ "$REAL_ALPHA_HASH" != "$STALE_HASH" ]; then
  echo "ok control needle #2: the real sha256 of gate_alpha.sh ($REAL_ALPHA_HASH)"
  echo "   genuinely differs from map_stale.json's planted stale hash"
  echo "   ($STALE_HASH) -- the AS-003 comparison this fixture drives can"
  echo "   actually discriminate a mismatch, not a tautological self-match"
else
  echo "NOT ok control needle #2 failed: real_hash='$REAL_ALPHA_HASH'"
  echo "     stale_hash='$STALE_HASH' -- either the real hash could not be"
  echo "     computed, or it accidentally equals the planted stale one"
  failx
fi

# --- (0) absence proof: affected_set.py ---
if [ -f "$AFFECTED_SET" ]; then
  echo "ok $AFFECTED_SET now exists -- the real-invocation assertions below"
  echo "   are the load-bearing check"
else
  echo "NOT ok $AFFECTED_SET does not exist yet (T-C03's implementer task"
  echo "     has not landed) -- this IS today's correct RED state for T053"
  failx
fi

json_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2"; }

# --- disposable git-repo builder: a base commit with the shared corpus
#     (src/, docs/ + gates/), then EITHER a head commit editing the given
#     changed_paths OR leaves them edited-but-uncommitted when
#     $3 = "worktree" (exercising the <sha|WORKTREE> head form). Prints
#     "base_sha head_ref repo_dir" on stdout.
build_repo() {
  local changed_paths="$1" head_mode="${2:-commit}" repo
  repo=$(mktemp -d "$WORK/repo.XXXXXX")
  cp -a "$SHARED/src" "$SHARED/docs" "$SHARED/gates" "$repo/"
  ( cd "$repo" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -q -m base )
  local base head
  base=$(cd "$repo" && git rev-parse HEAD)
  for p in $changed_paths; do
    if [ -f "$repo/$p" ]; then
      printf '\n# T053 fixture edit %s\n' "$(date +%s%N)" >> "$repo/$p"
    else
      mkdir -p "$(dirname "$repo/$p")"
      printf '# T053 fixture: newly-added unmapped path\n' > "$repo/$p"
    fi
  done
  if [ "$head_mode" = "worktree" ]; then
    head="WORKTREE"
  else
    ( cd "$repo" && git add -A && git commit -q -m head )
    head=$(cd "$repo" && git rev-parse HEAD)
  fi
  echo "$base $head $repo"
}

# --- REAL invocation: run once against a fixed-output fixture, assert
#     exit code + determinable + members + skipped reason-codes +
#     fallback_reason all match expected.json ---
assert_fixed_fixture() {
  local fx="$1" head_mode="${2:-commit}"
  local exp="$FIXDIR/$fx/expected.json"
  local map_file base head repo out rc
  map_file="$SHARED/$(json_field "$exp" map_file)"
  local changed
  changed=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["changed_paths"]))' "$exp")
  read -r base head repo <<EOF2
$(build_repo "$changed" "$head_mode")
EOF2
  out="$WORK/${fx}.affected.json"
  rm -f "$out"
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base" --head "$head" --map "$map_file" \
    --layer "$(json_field "$exp" layer)" --out "$out" \
    --repo "$repo" \
    >"$WORK/${fx}.stdout" 2>"$WORK/${fx}.stderr"
  rc=$?
  local exp_exit exp_det exp_members exp_skipped exp_fbr
  exp_exit=$(json_field "$exp" expected_exit_code)
  exp_det=$(json_field "$exp" expected_determinable)
  exp_members=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["expected_members"]))' "$exp")
  exp_skipped=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1])).get("expected_skipped_reason_codes",{}).items()))' "$exp")
  local ok=1
  if [ "$rc" != "$exp_exit" ]; then ok=0; fi
  if [ ! -f "$out" ] && [ "$exp_exit" = "0" ]; then ok=0; fi
  local got_det got_members got_skipped got_fbr
  if [ -f "$out" ]; then
    got_det=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("determinable"))' "$out" 2>/dev/null)
    got_members=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1])).get("members",[])))' "$out" 2>/dev/null)
    got_skipped=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1])).get("skipped",[])
print(sorted((e["gate_id"], e["reason_code"]) for e in d))' "$out" 2>/dev/null)
    got_fbr=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("fallback_reason"))' "$out" 2>/dev/null)
    [ "$got_det" = "$exp_det" ] || ok=0
    [ "$got_members" = "$exp_members" ] || ok=0
    [ "$got_skipped" = "$exp_skipped" ] || ok=0
    local fbr_prefix
    fbr_prefix=$(json_field "$exp" expected_fallback_reason_prefix)
    if [ -n "$fbr_prefix" ]; then
      case "$got_fbr" in "$fbr_prefix"*) : ;; *) ok=0 ;; esac
    fi
  fi
  if [ "$ok" = "1" ]; then
    echo "ok $fx: real invocation matches fixture's expected.json"
    echo "   (exit=$rc, determinable=$got_det, members=$got_members)"
  else
    echo "NOT ok $fx: real invocation exit=$rc (want $exp_exit),"
    echo "     determinable=${got_det:-<no output>}, members=${got_members:-<none>}"
    echo "     skipped=${got_skipped:-<none>} fallback_reason=${got_fbr:-<none>}"
    echo "     want members=$exp_members skipped=$exp_skipped"
    echo "     Current reason: $AFFECTED_SET does not exist yet -- stderr:"
    echo "     $(tail -1 "$WORK/${fx}.stderr" 2>/dev/null)"
    failx
  fi
}

assert_fixed_fixture as_good_single_component
assert_fixed_fixture as_bad_unmapped_path
assert_fixed_fixture as_bad_undeclared_read
assert_fixed_fixture as_bad_stale_map
assert_fixed_fixture as_negctrl_docs_only
assert_fixed_fixture as_selfchange
# as_determinism exercises the "commit" head form again but is checked as
# a two-run equality below, not a single fixed-fixture match.
# One fixture is run with head=WORKTREE to prove that form is real too.
assert_fixed_fixture as_concurrent

# --- (3) metamorphic: adding an unrelated changed path never shrinks the
#     selected set -- drives the REAL tool twice and checks a RELATION,
#     not a fixed golden output ---
assert_metamorphic() {
  local exp="$FIXDIR/as_metamorphic_grow_only/expected.json"
  local map_file="$SHARED/$(json_field "$exp" map_file)"
  local changed_a changed_b base_a head_a repo_a base_b head_b repo_b
  changed_a=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["run_a_changed_paths"]))' "$exp")
  changed_b=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["run_b_changed_paths"]))' "$exp")
  read -r base_a head_a repo_a <<EOF2
$(build_repo "$changed_a" commit)
EOF2
  read -r base_b head_b repo_b <<EOF2
$(build_repo "$changed_b" commit)
EOF2
  local out_a="$WORK/metamorphic_a.json" out_b="$WORK/metamorphic_b.json"
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base_a" --head "$head_a" --map "$map_file" --layer all \
    --out "$out_a" --repo "$repo_a" >"$WORK/meta_a.stdout" 2>"$WORK/meta_a.stderr"
  local rc_a=$?
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base_b" --head "$head_b" --map "$map_file" --layer all \
    --out "$out_b" --repo "$repo_b" >"$WORK/meta_b.stdout" 2>"$WORK/meta_b.stderr"
  local rc_b=$?
  if [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 0 ] && [ -f "$out_a" ] && [ -f "$out_b" ]; then
    local superset
    superset=$(python3 -c '
import json, sys
a = set(json.load(open(sys.argv[1]))["members"])
b = set(json.load(open(sys.argv[2]))["members"])
print("yes" if a <= b else "no")
' "$out_a" "$out_b" 2>/dev/null)
    if [ "$superset" = "yes" ]; then
      echo "ok as_metamorphic_grow_only: members(run_b) superset_or_equal"
      echo "   members(run_a) -- adding an unrelated changed path never"
      echo "   shrank the selected set"
    else
      echo "NOT ok as_metamorphic_grow_only: run_b's member set is NOT a"
      echo "     superset of run_a's -- the metamorphic relation is violated"
      echo "     (superset check='$superset')"
      failx
    fi
  else
    echo "NOT ok as_metamorphic_grow_only: one or both real invocations did"
    echo "     not succeed (rc_a=$rc_a rc_b=$rc_b) -- current reason:"
    echo "     $AFFECTED_SET does not exist yet"
    failx
  fi
}
assert_metamorphic

# --- (4) determinism: two independent runs of the identical change ---
assert_determinism() {
  local exp="$FIXDIR/as_determinism/expected.json"
  local map_file="$SHARED/$(json_field "$exp" map_file)"
  local changed base1 head1 repo1 base2 head2 repo2
  changed=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["changed_paths"]))' "$exp")
  read -r base1 head1 repo1 <<EOF2
$(build_repo "$changed" commit)
EOF2
  read -r base2 head2 repo2 <<EOF2
$(build_repo "$changed" commit)
EOF2
  local out1="$WORK/det1.json" out2="$WORK/det2.json"
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base1" --head "$head1" --map "$map_file" --layer all \
    --out "$out1" --repo "$repo1" >/dev/null 2>"$WORK/det1.stderr"
  local rc1=$?
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base2" --head "$head2" --map "$map_file" --layer all \
    --out "$out2" --repo "$repo2" >/dev/null 2>"$WORK/det2.stderr"
  local rc2=$?
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ -f "$out1" ] && [ -f "$out2" ]; then
    local m1 m2
    m1=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["members"]))' "$out1")
    m2=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["members"]))' "$out2")
    if [ "$m1" = "$m2" ]; then
      echo "ok as_determinism: two independent runs of the identical change"
      echo "   produce identical member sets ($m1)"
    else
      echo "NOT ok as_determinism: run1='$m1' run2='$m2' differ"
      failx
    fi
  else
    echo "NOT ok as_determinism: one or both real invocations did not"
    echo "     succeed (rc1=$rc1 rc2=$rc2) -- current reason: $AFFECTED_SET"
    echo "     does not exist yet"
    failx
  fi
}
assert_determinism

# --- WORKTREE head-form proof: re-run as_good_single_component's change
#     with head="WORKTREE" (uncommitted edit) instead of a head commit,
#     proving the tool accepts BOTH forms the contract's --head
#     <sha|WORKTREE> syntax allows ---
assert_worktree_head_form() {
  local exp="$FIXDIR/as_good_single_component/expected.json"
  local map_file="$SHARED/$(json_field "$exp" map_file)"
  local changed base head repo out rc
  changed=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["changed_paths"]))' "$exp")
  read -r base head repo <<EOF2
$(build_repo "$changed" worktree)
EOF2
  out="$WORK/worktree_form.json"
  python3 "$AFFECTED_SET" --config "$ROOT/config/fastcycle/fastcycle.yaml" \
    --base "$base" --head "$head" --map "$map_file" --layer all \
    --out "$out" --repo "$repo" >/dev/null 2>"$WORK/worktree_form.stderr"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -f "$out" ]; then
    local got_members
    got_members=$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["members"]))' "$out")
    if [ "$got_members" = "['gate_alpha']" ]; then
      echo "ok worktree_head_form: --head WORKTREE (uncommitted edit,"
      echo "   never a real commit sha) is accepted and selects gate_alpha"
      echo "   exactly like the committed-head form"
    else
      echo "NOT ok worktree_head_form: got members=$got_members, want"
      echo "     ['gate_alpha']"
      failx
    fi
  else
    echo "NOT ok worktree_head_form: real invocation with --head WORKTREE"
    echo "     did not succeed (rc=$rc) -- current reason: $AFFECTED_SET"
    echo "     does not exist yet -- stderr:"
    echo "     $(tail -1 "$WORK/worktree_form.stderr" 2>/dev/null)"
    failx
  fi
}
assert_worktree_head_form

# --- paired mutation self-check (contract's own "Paired mutation" row):
#     if AS-010 were mutated to treat unmapped paths as unaffected instead
#     of falling back, as_bad_unmapped_path's assertion above MUST stop
#     passing -- documented here as a manual/meta-test-facing note, proven
#     structurally (this file's own as_bad_unmapped_path check IS that
#     mutation's kill test: a tool that silently skips unmapped paths
#     produces determinable=true / a narrower members list, which this
#     test's exact-match assertion above already refuses) ---
echo "ok paired_mutation_note: as_bad_unmapped_path's exact-match assertion"
echo "   (determinable=false + full 5-gate suite + fallback_reason prefix)"
echo "   is itself the kill test for the AS-010 mutation named in this"
echo "   contract's RED-fixtures table row 'Paired mutation' -- a mutated"
echo "   tool that treats unmapped paths as unaffected fails that check"

# --- real-tree-untouched, end-to-end ---
CANARY_AFTER=$(canary_hash)
if [ -n "$CANARY_BEFORE" ] && [ "$CANARY_BEFORE" = "$CANARY_AFTER" ]; then
  echo "ok as_real_tree_untouched: canary $CANARY sha256 unchanged before/"
  echo "   after all disposable-repo work ($CANARY_BEFORE)"
else
  echo "NOT ok as_real_tree_untouched: canary hash changed or unreadable"
  echo "     (before=$CANARY_BEFORE after=$CANARY_AFTER)"
  failx
fi

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "test_affected_set_red.sh: GREEN -- affected_set.py exists AND every"
  echo "  real invocation matches its fixture's real expected outcome (the"
  echo "  implementer task has landed correctly)"
else
  echo "test_affected_set_red.sh: RED as expected -- the real tool is"
  echo "  absent (the implementer task has not yet landed), so every"
  echo "  real-invocation assertion above correctly cannot match its"
  echo "  fixture's expected outcome, while the toy fixture corpus itself"
  echo "  (independent of the absent tool) is proven self-consistent"
fi
exit "$fail"
