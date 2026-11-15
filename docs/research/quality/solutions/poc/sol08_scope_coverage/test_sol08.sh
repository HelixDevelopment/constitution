#!/usr/bin/env bash
# SOL-08 POC test — tracker scope-coverage across a workspace.
# Written FIRST (§11.4.224). RED before scope_coverage.sh exists.
#
# Contract (scope_coverage.sh <workspace-dir> <manifest.tsv> <id-regex> <min-pct>):
#   manifest.tsv rows: relative-repo-path <TAB> TRACKED | EXEMPT:<reason>
#   For every git repo found under workspace-dir (depth<=2):
#     - not in the manifest            -> FAIL UNREGISTERED-REPO (the corpus-3 hole:
#       a 2,790-commit repo ran beside an exemplary tracker with 3 tracked items)
#     - TRACKED: % of non-merge commits whose subject matches the item-id regex
#       must be >= min-pct, else FAIL LOW-COVERAGE naming the repo + the numbers
#     - EXEMPT: enumerated with its reason, never silent, never failing
#   exit 0 clean | 1 findings | 2 blind (no repos found = blind, never green)
#
# Cases:
#   A golden-good      : tracked repo with id-referencing commits -> 0
#   B golden-bad-1     : tracked repo, zero id references -> FAIL LOW-COVERAGE
#   C golden-bad-2     : repo present on disk but absent from manifest -> FAIL UNREGISTERED
#   D negative-control : EXEMPT repo with reason -> enumerated, no failure
#   E blind            : empty workspace -> 2, never 0
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
[ -f "$HERE/scope_coverage.sh" ] || { echo "FAIL: missing artifact scope_coverage.sh"; echo "RESULT: RED"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
mkrepo() { # $1=path, then commit subjects on stdin
  mkdir -p "$1"; git -C "$1" init -q
  while IFS= read -r s; do
    G "$1" commit -q --allow-empty -m "$s"
  done
}

WS="$T/ws"; mkdir -p "$WS"
mkrepo "$WS/tracked_good" <<'EOF'
feat: ATM-201 wire the custody sweep
fix: ATM-202 close the reopen channel
docs: ATM-201 evidence notes
EOF
mkrepo "$WS/tracked_bad" <<'EOF'
fix stuff
more work
untracked churn
EOF
mkrepo "$WS/exempt_vendor" <<'EOF'
upstream import
EOF

MF="$T/manifest.tsv"
printf 'tracked_good\tTRACKED\ntracked_bad\tTRACKED\nexempt_vendor\tEXEMPT:third-party-vendored\n' > "$MF"

bash "$HERE/scope_coverage.sh" "$WS" "$MF" '[A-Z]{2,4}-[0-9]+' 50 > "$T/run1.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then
  grep -q 'LOW-COVERAGE.*tracked_bad' "$T/run1.out" && ok "B tracked repo with 0% id references -> LOW-COVERAGE named" \
    || bad "B tracked_bad not named: $(cat "$T/run1.out")"
  grep -q 'LOW-COVERAGE.*tracked_good' "$T/run1.out" && bad "A tracked_good falsely flagged" \
    || ok "A id-referencing repo passes coverage"
  grep -q 'EXEMPT.*exempt_vendor.*third-party-vendored' "$T/run1.out" && ok "D exempt repo enumerated with reason, not failed" \
    || bad "D exempt repo not enumerated: $(cat "$T/run1.out")"
else
  bad "run1 expected exit 1 (tracked_bad fails), got $rc: $(cat "$T/run1.out")"
fi

# C: unregistered repo
mkrepo "$WS/rogue_repo" <<'EOF'
init
EOF
bash "$HERE/scope_coverage.sh" "$WS" "$MF" '[A-Z]{2,4}-[0-9]+' 50 > "$T/run2.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q 'UNREGISTERED-REPO.*rogue_repo' "$T/run2.out"; then
  ok "C on-disk repo absent from the manifest -> UNREGISTERED-REPO (the corpus-3 hole closed)"
else
  bad "C expected UNREGISTERED-REPO rogue_repo, got $rc: $(cat "$T/run2.out")"
fi

# E: blind on empty workspace
mkdir -p "$T/empty"
bash "$HERE/scope_coverage.sh" "$T/empty" "$MF" '[A-Z]{2,4}-[0-9]+' 50 > "$T/run3.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "E empty workspace -> blind (2), never a green nothing" || bad "E expected 2 got $rc"

echo "----------------------------------------"
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
