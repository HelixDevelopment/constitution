#!/bin/bash
# Purpose : TDD-first (S11.4.224) RED/GREEN suite for the git-history
#           "patch-tower" (S11.4.250 heuristic-tower) detector --
#           review/tower_detector.sh -> review/lib/tower_detector_run.py.
#           Research-derived shortlist item 4,
#           docs/research/fast_dev_cycles_acceleration_2026-10/FINDINGS.md
#           S6: "A git-history tower detector flags any symbol with 3+
#           branch-adding commits under one item in a cycle -- mechanically
#           triggers S11.4.250 before the 3rd patch round."
#
# S11.4.201(1) false-positive guard: every case below is EITHER a
# golden-TRUE fixture (a real tower -- MUST flag) OR a golden-FALSE
# fixture (clean/refactor-shaped history -- MUST NOT flag), built as a
# disposable synthetic git repository per case (never a committed
# nested-.git fixture -- avoids the submodule/tooling footguns a tracked
# inner repository would create). Pure-function unit checks (no git
# needed) cover normalize_symbol/message_is_removal/item_token_regex/
# classify_hunk directly against literal strings, independently of the
# integration cases.
#
# Unit cases  : U1-U7   (pure functions, no git)
# Integration : I1 golden-bad (a real 3-commit tower, same item/symbol)
#               I2 golden-good (clean history, no tower)
#               I3 negative-control (3 commits each adding an `if`, but
#                  each commit's message states removal/refactor intent
#                  AND/OR the hunk deletes roughly as much as it adds --
#                  the exact AND-NOT shape the design brief asked for;
#                  MUST NOT flag despite superficially matching keywords)
#               I4 cross-item isolation (two items touch the SAME file/
#                  symbol; commits under item B must never count toward
#                  item A's tally)
#               I5 FILE-level fallback (git reports no function context;
#                  tower must still be flagged at FILE: granularity)
#               I6 usage-error exit code (neither --item/--range/--path)
#
# Usage : bash test_tower_detector_red.sh   exit 0 = all cases hold.
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
TOOL="$ROOT/constitution/scripts/fastcycle/review/tower_detector.sh"
LIB="$ROOT/constitution/scripts/fastcycle/review/lib/tower_detector_run.py"
PY=python3
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }

# ---------------------------------------------------------------------------
# Unit cases -- pure functions, no git invocation at all.
# ---------------------------------------------------------------------------
unit_py() {
  "$PY" - "$LIB" <<'PYEOF'
import importlib.util
import sys

lib_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("tower_detector_run", lib_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

results = []

def check(name, cond):
    results.append((name, bool(cond)))

# U1: normalize_symbol -- real function context -> FILE::func
check("U1a shell-func-context", m.normalize_symbol("f.sh", "write_out() {") == "f.sh::write_out")
check("U1b python-def-context", m.normalize_symbol("f.py", "def compute_comparison(a, b):") == "f.py::compute_comparison")
check("U1c python-class-context", m.normalize_symbol("f.py", "class Foo:") == "f.py::Foo")
check("U1d empty-context-is-file-fallback", m.normalize_symbol("f.sh", "") == "FILE:f.sh")
check("U1e whitespace-only-context-is-file-fallback", m.normalize_symbol("f.sh", "   ") == "FILE:f.sh")

# U2: control-flow-keyword context must NEVER become a fake symbol (the
# real false-match this tool's own calibration run against T177/
# migrate.sh's real history surfaced and fixed -- "fi" was briefly
# treated as a real function name before this guard existed).
check("U2a bare-fi-context-is-file-fallback", m.normalize_symbol("f.sh", "fi") == "FILE:f.sh")
check("U2b bare-if-context-is-file-fallback", m.normalize_symbol("f.sh", "if") == "FILE:f.sh")
check("U2c bare-for-context-is-file-fallback", m.normalize_symbol("f.sh", "for") == "FILE:f.sh")
check("U2d bare-while-context-is-file-fallback", m.normalize_symbol("f.sh", "while") == "FILE:f.sh")
check("U2e bare-done-context-is-file-fallback", m.normalize_symbol("f.sh", "done") == "FILE:f.sh")
check("U2f real-func-named-iffy-still-a-real-symbol", m.normalize_symbol("f.sh", "iffy_helper() {") == "f.sh::iffy_helper")

# U3: message_is_removal -- the MESSAGE-SHAPE half of the AND-NOT rule.
check("U3a refactor-type-excluded", m.message_is_removal("refactor(x): tidy up") is True)
check("U3b revert-type-excluded", m.message_is_removal("revert(x): undo bad change") is True)
check("U3c remove-lead-verb-excluded", m.message_is_removal("chore(fastcycle/T048-r21): remove obsolete member-consistency suite") is True)
check("U3d replace-lead-verb-excluded", m.message_is_removal("fix(x): replace the old cascade with a strict rule") is True)
check("U3e fix-type-not-excluded", m.message_is_removal("fix(fastcycle/T085-r5): 4 shared architectural primitives") is False)
check("U3f handle-verb-not-excluded", m.message_is_removal("fix(x): handle a new edge case") is False)
check("U3g off-convention-message-not-excluded", m.message_is_removal("a totally free-form commit message") is False)

# U4: item_token_regex -- word-bounded literal token match, robust to
# both real forms this repo's own history uses ("-rN" scope suffix AND
# free-text "round N").
p1 = m.item_token_regex("T085")
check("U4a matches-scope-suffix-form", bool(p1.search("fix(fastcycle/T085-r5): 4 shared architectural primitives")))
check("U4b matches-freetext-round-form", bool(m.item_token_regex("T048").search("fix(fastcycle/T048): round 11 -- remediate independent round-10 review")))
check("U4c does-not-match-substring-prefix", not bool(m.item_token_regex("T08").search("fix(fastcycle/T085-r5): x")))
check("U4d does-not-cross-match-different-item", not bool(p1.search("fix(fastcycle/T048-r22): x")))
p2 = m.item_token_regex("T085-r5")
check("U4e round-suffix-stripped-from-query-itself", bool(p2.search("fix(fastcycle/T085-r1): x")))
check("U4f atm-style-item-id", bool(m.item_token_regex("ATM-123").search("fix(ATM-123): close the loop")))

# U5: classify_hunk -- the DIFF-SHAPE half of the AND-NOT rule.
added_branch = ["if [ \"$x\" = 1 ]; then", "  echo hit", "fi"]
removed_none = []
ok, net, ta, td = m.classify_hunk(added_branch, removed_none, 0.8)
check("U5a pure-branch-addition-flags", ok is True and net == 1)

added_equal_removed = ["if [ \"$y\" = 2 ]; then", "  echo new", "fi"]
removed_equal = ["if [ \"$x\" = 1 ]; then", "  echo old", "fi"]
ok2, net2, ta2, td2 = m.classify_hunk(added_equal_removed, removed_equal, 0.8)
check("U5b roughly-equal-removal-is-refactor-shaped-not-flagged", ok2 is False)

ok3, net3, ta3, td3 = m.classify_hunk(["x = 1", "y = 2"], [], 0.8)
check("U5c no-branch-tokens-not-flagged", ok3 is False and net3 == 0)

# U6: count_branch_tokens -- the enumerated keyword set.
check("U6a if-counts", m.count_branch_tokens(["if cond; then"]) == 1)
check("U6b elif-counts", m.count_branch_tokens(["elif cond2; then"]) == 1)
check("U6c case-in-counts", m.count_branch_tokens(["case $x in"]) == 1)
check("U6d except-counts", m.count_branch_tokens(["except ValueError:"]) == 1)
check("U6e catch-counts", m.count_branch_tokens(["catch (Exception e) {"]) == 1)
check("U6f plain-assignment-does-not-count", m.count_branch_tokens(["x = compute_if_ready()"]) == 0)
check("U6g blank-lines-ignored", m.count_branch_tokens(["", "   "]) == 0)

# U7: parse_diff_hunks -- pure text parsing, no git invocation.
sample_diff = (
    "diff --git a/f.sh b/f.sh\n"
    "index 1111111..2222222 100644\n"
    "--- a/f.sh\n"
    "+++ b/f.sh\n"
    "@@ -10,0 +11,3 @@ write_out() {\n"
    "+if [ -z \"$x\" ]; then\n"
    "+  return 1\n"
    "+fi\n"
)
hunks = m.parse_diff_hunks(sample_diff)
check("U7a one-hunk-parsed", len(hunks) == 1)
check("U7b hunk-file-correct", hunks[0][0] == "f.sh")
check("U7c hunk-context-correct", hunks[0][1] == "write_out() {")
check("U7d hunk-added-lines-correct", hunks[0][2] == ["if [ -z \"$x\" ]; then", "  return 1", "fi"])
check("U7e hunk-removed-lines-empty", hunks[0][3] == [])

for name, cond in results:
    print(("ok " if cond else "NOT ok ") + name)
sys.exit(0 if all(c for _, c in results) else 1)
PYEOF
}
unit_out="$TMP/unit.out"
unit_py >"$unit_out" 2>"$TMP/unit.err"
unit_rc=$?
while IFS= read -r line; do echo "$line"; done <"$unit_out"
chk "unit: all pure-function cases hold (rc=$unit_rc)" "$([ "$unit_rc" = 0 ] && echo 1)"

# ---------------------------------------------------------------------------
# Integration cases -- disposable synthetic git repositories.
# ---------------------------------------------------------------------------
mkrepo() { # dir
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email "test@example.invalid"
  git -C "$1" config user.name "Tower Detector Test"
}

commit_file() { # repo file content subject
  printf '%s' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "$4" --allow-empty
}

run_tool() { # repo item-or-empty path-or-empty out-file
  local repo="$1" item="$2" path="$3" out="$4"
  shift 4
  local extra_args=()
  [ -n "$item" ] && extra_args+=(--item "$item")
  [ -n "$path" ] && extra_args+=(--path "$path")
  "$TOOL" --repo "$repo" "${extra_args[@]}" --out "$out" "$@" >"$TMP/_last.stderr" 2>&1
}

findings_count() { # out-file
  "$PY" -c "import json,sys; print(len(json.load(open(sys.argv[1]))['findings']))" "$1" 2>/dev/null
}

# --- I1: golden-bad -- a real 3-commit tower under one item, one symbol ---
R1="$TMP/repo_golden_bad"
mkrepo "$R1"
cat > "$R1/f.sh" <<'EOF'
#!/bin/sh
compute() {
  echo base
}
EOF
git -C "$R1" add f.sh
git -C "$R1" commit -q -m "feat(x/T200): initial compute()"

cat > "$R1/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  echo base
}
EOF
git -C "$R1" add f.sh
git -C "$R1" commit -q -m "fix(x/T200-r1): handle flaky A case in compute()"

cat > "$R1/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$FLAKY_B" ]; then
    echo special_b
  fi
  echo base
}
EOF
git -C "$R1" add f.sh
git -C "$R1" commit -q -m "fix(x/T200-r2): also handle flaky B case in compute()"

cat > "$R1/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$FLAKY_B" ]; then
    echo special_b
  fi
  if [ -n "$FLAKY_C" ]; then
    echo special_c
  fi
  echo base
}
EOF
git -C "$R1" add f.sh
git -C "$R1" commit -q -m "fix(x/T200-r3): patch yet another flaky C case in compute()"

run_tool "$R1" "T200" "" "$TMP/i1.json"
rc1=$?
chk "I1: golden-bad exits 1 (finding present)" "$([ "$rc1" = 1 ] && echo 1)"
n1=$(findings_count "$TMP/i1.json")
chk "I1: golden-bad flags exactly one symbol" "$([ "$n1" = 1 ] && echo 1)"
qc1=$("$PY" -c "import json; print(json.load(open('$TMP/i1.json'))['findings'][0]['qualifying_commit_count'])" 2>/dev/null)
chk "I1: golden-bad qualifying commit count is 3" "$([ "$qc1" = 3 ] && echo 1)"
sym1=$("$PY" -c "import json; print(json.load(open('$TMP/i1.json'))['findings'][0]['symbol'])" 2>/dev/null)
chk "I1: golden-bad flagged symbol is f.sh::compute" "$([ "$sym1" = "f.sh::compute" ] && echo 1)"

# --- I2: golden-good -- clean history, no tower (only 2 branch-adding
#         commits, below the min-branch-commits=3 threshold) ---
R2="$TMP/repo_golden_good"
mkrepo "$R2"
cat > "$R2/f.sh" <<'EOF'
#!/bin/sh
compute() {
  echo base
}
EOF
git -C "$R2" add f.sh
git -C "$R2" commit -q -m "feat(x/T201): initial compute()"

cat > "$R2/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  echo base
}
EOF
git -C "$R2" add f.sh
git -C "$R2" commit -q -m "fix(x/T201-r1): handle flaky A case in compute()"

cat > "$R2/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$FLAKY_B" ]; then
    echo special_b
  fi
  echo base
}
EOF
git -C "$R2" add f.sh
git -C "$R2" commit -q -m "fix(x/T201-r2): also handle flaky B case in compute()"

run_tool "$R2" "T201" "" "$TMP/i2.json"
rc2=$?
chk "I2: golden-good exits 0 (no finding, below threshold)" "$([ "$rc2" = 0 ] && echo 1)"
n2=$(findings_count "$TMP/i2.json")
chk "I2: golden-good flags zero symbols" "$([ "$n2" = 0 ] && echo 1)"

# --- I3: negative-control -- 3 commits each superficially adding an
#         `if`, but EACH is message-labelled a removal/refactor AND/OR
#         diff-shaped as a roughly-equal replace. MUST NOT flag despite
#         the surface keyword match -- this is the S11.4.201(1) guard
#         against the exact false-positive a naive "count `if` additions"
#         detector would produce. ---
R3="$TMP/repo_negative_control"
mkrepo "$R3"
cat > "$R3/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$OLD_A" ]; then
    echo old_a
  fi
  echo base
}
EOF
git -C "$R3" add f.sh
git -C "$R3" commit -q -m "feat(x/T202): initial compute() with legacy OLD_A branch"

cat > "$R3/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$NEW_A" ]; then
    echo new_a
  fi
  echo base
}
EOF
git -C "$R3" add f.sh
git -C "$R3" commit -q -m "refactor(x/T202-r1): replace OLD_A branch with NEW_A"

cat > "$R3/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$NEW_B" ]; then
    echo new_b
  fi
  echo base
}
EOF
git -C "$R3" add f.sh
git -C "$R3" commit -q -m "refactor(x/T202-r2): replace NEW_A branch with NEW_B"

cat > "$R3/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$NEW_C" ]; then
    echo new_c
  fi
  echo base
}
EOF
git -C "$R3" add f.sh
git -C "$R3" commit -q -m "refactor(x/T202-r3): replace NEW_B branch with NEW_C"

run_tool "$R3" "T202" "" "$TMP/i3.json"
rc3=$?
chk "I3: negative-control exits 0 (no finding despite 3 superficial if-adds)" "$([ "$rc3" = 0 ] && echo 1)"
n3=$(findings_count "$TMP/i3.json")
chk "I3: negative-control flags zero symbols" "$([ "$n3" = 0 ] && echo 1)"

# --- I3b: message-shape isolation -- a SEPARATE fixture from I3, added
#          after a reviewer-authored mutation (S11.4.194(6)(d): remove
#          the `not is_removal_commit` clause from `qualifies =
#          is_branch_adding and not is_removal_commit`) SURVIVED I3
#          unnoticed, because I3's three commits are each diff-shaped as
#          a roughly-equal replace (del>=0.8*add), so classify_hunk's OWN
#          refractor_ratio check ALONE already suppresses them --
#          REGARDLESS of whether the message-shape check runs at all. I3
#          therefore never isolated the message-shape half of the AND-NOT
#          rule; it only ever exercised the diff-shape half a second
#          time. This fixture closes that gap: three PURELY ADDITIVE
#          commits (zero deletions, so the diff-shape check alone would
#          happily flag them) under one item, each one's message typed
#          `refactor(...)` -- MUST NOT flag with the message-shape check
#          intact, and (verified against the mutation that exposed this
#          gap) WOULD flag with it removed. ---
R3B="$TMP/repo_negative_control_message_only"
mkrepo "$R3B"
cat > "$R3B/f.sh" <<'EOF'
#!/bin/sh
compute() {
  echo base
}
EOF
git -C "$R3B" add f.sh
git -C "$R3B" commit -q -m "feat(x/T208): initial compute()"

cat > "$R3B/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  echo base
}
EOF
git -C "$R3B" add f.sh
git -C "$R3B" commit -q -m "refactor(x/T208-r1): reorganise compute() -- adds a purely additive FLAKY_A branch"

cat > "$R3B/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$FLAKY_B" ]; then
    echo special_b
  fi
  echo base
}
EOF
git -C "$R3B" add f.sh
git -C "$R3B" commit -q -m "refactor(x/T208-r2): reorganise compute() -- adds a purely additive FLAKY_B branch"

cat > "$R3B/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$FLAKY_B" ]; then
    echo special_b
  fi
  if [ -n "$FLAKY_C" ]; then
    echo special_c
  fi
  echo base
}
EOF
git -C "$R3B" add f.sh
git -C "$R3B" commit -q -m "refactor(x/T208-r3): reorganise compute() -- adds a purely additive FLAKY_C branch"

run_tool "$R3B" "T208" "" "$TMP/i3b.json"
rc3b=$?
chk "I3b: message-shape-only negative-control exits 0 (no finding)" "$([ "$rc3b" = 0 ] && echo 1)"
n3b=$(findings_count "$TMP/i3b.json")
chk "I3b: message-shape-only negative-control flags zero symbols" "$([ "$n3b" = 0 ] && echo 1)"

# --- I4: cross-item isolation -- item B's commits on the SAME file/
#         symbol must never count toward item A's tally. ---
R4="$TMP/repo_cross_item"
mkrepo "$R4"
cat > "$R4/f.sh" <<'EOF'
#!/bin/sh
compute() {
  echo base
}
EOF
git -C "$R4" add f.sh
git -C "$R4" commit -q -m "feat(x/T203): initial compute()"

cat > "$R4/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  echo base
}
EOF
git -C "$R4" add f.sh
git -C "$R4" commit -q -m "fix(x/T203-r1): handle flaky A in compute()"

cat > "$R4/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$UNRELATED" ]; then
    echo unrelated
  fi
  echo base
}
EOF
git -C "$R4" add f.sh
git -C "$R4" commit -q -m "fix(x/T204-r1): a DIFFERENT item (T204) patches the SAME symbol"

cat > "$R4/f.sh" <<'EOF'
#!/bin/sh
compute() {
  if [ -n "$FLAKY_A" ]; then
    echo special_a
  fi
  if [ -n "$UNRELATED" ]; then
    echo unrelated
  fi
  if [ -n "$ALSO_UNRELATED" ]; then
    echo also_unrelated
  fi
  echo base
}
EOF
git -C "$R4" add f.sh
git -C "$R4" commit -q -m "fix(x/T204-r2): T204 again patches the SAME symbol"

run_tool "$R4" "T203" "" "$TMP/i4.json"
rc4=$?
chk "I4: item T203 (only 1 qualifying commit of its own) exits 0" "$([ "$rc4" = 0 ] && echo 1)"
n4=$(findings_count "$TMP/i4.json")
chk "I4: item T203 is not contaminated by T204's commits on the same symbol" "$([ "$n4" = 0 ] && echo 1)"

# --- I5: FILE-level fallback -- synthesize a hunk with no function
#         context (git's own context detector emits none for a change
#         confined to the file's very first lines with no preceding
#         construct it recognises) -- tower must still flag at FILE:
#         granularity, per the design brief's explicit coarser-fallback
#         permission. ---
R5="$TMP/repo_file_fallback"
mkrepo "$R5"
printf '' > "$R5/f.sh"
git -C "$R5" add f.sh
git -C "$R5" commit -q -m "feat(x/T205): empty file"

printf 'if [ -n "$A" ]; then echo a; fi\n' > "$R5/f.sh"
git -C "$R5" add f.sh
git -C "$R5" commit -q -m "fix(x/T205-r1): add top-level A branch"

printf 'if [ -n "$A" ]; then echo a; fi\nif [ -n "$B" ]; then echo b; fi\n' > "$R5/f.sh"
git -C "$R5" add f.sh
git -C "$R5" commit -q -m "fix(x/T205-r2): add top-level B branch"

printf 'if [ -n "$A" ]; then echo a; fi\nif [ -n "$B" ]; then echo b; fi\nif [ -n "$C" ]; then echo c; fi\n' > "$R5/f.sh"
git -C "$R5" add f.sh
git -C "$R5" commit -q -m "fix(x/T205-r3): add top-level C branch"

run_tool "$R5" "T205" "" "$TMP/i5.json"
rc5=$?
n5=$(findings_count "$TMP/i5.json")
chk "I5: FILE-level fallback exits 1 (finding present)" "$([ "$rc5" = 1 ] && echo 1)"
chk "I5: FILE-level fallback flags exactly one symbol" "$([ "$n5" = 1 ] && echo 1)"
sym5=$("$PY" -c "import json; print(json.load(open('$TMP/i5.json'))['findings'][0]['symbol'])" 2>/dev/null)
chk "I5: FILE-level fallback symbol name starts with FILE:" "$(printf '%s' "$sym5" | grep -q '^FILE:' && echo 1)"

# --- I6: usage error -- neither --item/--range/--path given. ---
R6="$TMP/repo_usage_error"
mkrepo "$R6"
commit_file "$R6" f.sh "x" "feat(x/T206): x"
"$TOOL" --repo "$R6" --out "$TMP/i6.json" >"$TMP/i6.stderr" 2>&1
rc6=$?
chk "I6: no selector supplied exits 2 (usage error)" "$([ "$rc6" = 2 ] && echo 1)"

[ "$fail" = 0 ] && echo "SUMMARY: all cases hold" || echo "SUMMARY: FAILURES present"
exit "$fail"
