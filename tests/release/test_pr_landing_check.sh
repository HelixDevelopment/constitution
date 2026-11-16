#!/usr/bin/env bash
# tests/release/test_pr_landing_check.sh - test of scripts/release/pr_landing_check.sh (CON-443).
#
# Class (section 11.4.289(C)): the git side is REAL (real git, real repositories in a mktemp
# scratch). Cases P1-P14 use stand-in check scripts committed into fixture repositories
# (UNIT-CLASS: they prove the script's logic). Case L1 runs the REAL compute_badges.sh and the
# REAL env-read allowlist gate on a clone of this repository's HEAD: a PR head with a stale
# README badge row is refused (RED), the same head with the row regenerated passes (GREEN).
# L1 is host-only gate-logic evidence; no forge is touched. HOME is never reassigned; git config
# isolation is done with GIT_CONFIG_GLOBAL / GIT_CONFIG_NOSYSTEM; scratch is removed with
# safe_rm_rf (section 11.4.287(B)).
#
# Usage: bash tests/release/test_pr_landing_check.sh [path/to/pr_landing_check.sh]
#        (PRLC_SCRIPT=<path> selects another copy; PRLC_TEST_FAILFAST=1 stops at the first FAIL;
#        PRLC_TEST_SKIP_LIVE=1 skips L1, reported as a SKIP line, never as a PASS)
# Exit:  0 all cases pass, 1 any case fails. Last line: "RESULT pass=N fail=M skip=K".
set -euo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PRLC=${1:-${PRLC_SCRIPT:-$ROOT/scripts/release/pr_landing_check.sh}}
[ -r "$PRLC" ] || { echo "test: pr_landing_check.sh not found: $PRLC" >&2; exit 1; }
# shellcheck source=/dev/null # sourced from the repository layout at run time
. "$ROOT/scripts/lib/safe_rm.sh" || { echo "test: cannot source $ROOT/scripts/lib/safe_rm.sh" >&2; exit 1; }
FAILFAST=${PRLC_TEST_FAILFAST:-0}
PASS=0 FAIL=0 SKIP=0
ok()  { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP %s\n' "$1"; }
bad() {
  FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"
  if [ "$FAILFAST" = 1 ]; then printf '\nRESULT pass=%d fail=%d skip=%d (failfast)\n' "$PASS" "$FAIL" "$SKIP"; exit 1; fi
}
T=$(mktemp -d "${TMPDIR:-/tmp}/prlctest.XXXXXX")
: "${T:?}"
cleanup() { [ -n "${T:-}" ] && [ -d "$T" ] && safe_rm_rf "$T"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "PRLC Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email prlc@invalid
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
BADGE_P=scripts/badges/compute_badges.sh
ENVG_P=scripts/gates/cm_gate_env_reads_allowlisted.sh

g() { git -C "$1" "${@:2}"; }
run() { local out=$1; shift; set +e; "$@" > "$out" 2>&1; RC=$?; set -e; }
# stub <argv log> <exit code> [extra shell line]: a stand-in check script (records its argv)
# shellcheck disable=SC2016 # the stub text is written literally; $* expands in the stub
stub() { printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n%s\nexit %s\n' "$1" "${3:-:}" "$2"; }
# put <repo> <path> <content>: write and commit one file
put() { mkdir -p "$1/$(dirname "$2")"; printf '%s' "$3" > "$1/$2"; g "$1" add "$2"; g "$1" commit -q -m "add $2"; }
# repo <name> <badges exit|-> <envgate exit|->: a repository on main with the stand-in checks
repo() {
  local R=$T/$1; git init -q "$R"; printf 'base\n' > "$R/a.txt"; g "$R" add a.txt; g "$R" commit -q -m base
  [ "$2" = - ] || put "$R" "$BADGE_P" "$(stub "$T/$1.badges.argv" "$2")"
  [ "$3" = - ] || put "$R" "$ENVG_P" "$(stub "$T/$1.envg.argv" "$3")"
}
prlc() { local name=$1; shift; run "$T/$name.out" "$PRLC" --repo "$T/$name" --evidence-dir "$T/$name.ev" "$@"; }
row() { awk -F '\t' -v c="$2" '$1==c {print $5}' "$T/$1.ev/drift_checks.tsv" 2>/dev/null || true; }
cand() { awk -F '\t' -v k="$2" '$1==k {print $2}' "$T/$1.ev/candidate.txt" 2>/dev/null || true; }
lastline() { tail -n 1 "$T/$1.out" 2>/dev/null || true; }
expect() { # expect <label> <name> <rc> <RESULT word>
  if [ "$RC" -eq "$3" ] && [ "$(lastline "$2")" = "RESULT: $4" ]; then ok "$1 (rc=$RC)"
  else bad "$1 (rc=$RC, want $3 / RESULT: $4)"; sed 's/^/    | /' "$T/$2.out"; fi
}

# P1 fast-forward PR head whose badge check fails -> FAIL, exit 1
repo p1 0 0; R=$T/p1; base=$(g "$R" rev-parse HEAD)
g "$R" checkout -q -b pr; put "$R" "$BADGE_P" "$(stub "$T/p1.badges.argv" 1)"; head=$(g "$R" rev-parse HEAD)
prlc p1 --base "$base" --head "$head"
expect "P1 a failing badge check on a fast-forward PR head refuses" p1 1 FAIL
if [ "$(row p1 badges)" = FAIL ] && [ "$(row p1 gate-env-allowlist)" = PASS ] && [ "$(cand p1 form)" = fast-forward ] && [ "$(cand p1 candidate)" = "$head" ]; then
  ok "P1 tsv badges=FAIL gate-env-allowlist=PASS; candidate = head (fast-forward)"; else bad "P1 tsv or candidate"; fi

# P2 both checks pass -> PASS; each check got --root <temporary clone> (and --check for badges)
repo p2 0 0; R=$T/p2; base=$(g "$R" rev-parse HEAD~1)
prlc p2 --base "$base" --head main
expect "P2 passing checks on a fast-forward PR head pass" p2 0 PASS
b_argv=$(cat "$T/p2.badges.argv" 2>/dev/null || true); e_argv=$(cat "$T/p2.envg.argv" 2>/dev/null || true)
if [[ "$b_argv" == "--root "*"/prlc."*"/c --check" ]] && [ "$e_argv" = "${b_argv% --check}" ] && [ ! -d "${b_argv#--root }" ] 2>/dev/null; then
  ok "P2 argv recorded (--root <temporary clone> [--check]); the temporary clone is removed"; else bad "P2 argv [$b_argv] [$e_argv]"; fi

# P3 base moved after the PR branched -> merge candidate with parents base and head; PASS
repo p3 0 0; R=$T/p3; g "$R" checkout -q -b pr; put "$R" pr.txt "pr"; head=$(g "$R" rev-parse HEAD)
g "$R" checkout -q main; put "$R" main2.txt "m2"; base=$(g "$R" rev-parse HEAD)
prlc p3 --base "$base" --head "$head"
expect "P3 a merge-commit candidate with passing checks passes" p3 0 PASS
c=$(cand p3 candidate)
if [ "$(cand p3 form)" = merge-commit ] && [ "$(cand p3 candidate_parents)" = "$base $head" ] && [ "$(cand p3 head)" = "$head" ]; then
  ok "P3 candidate is a merge commit of base and head"; else bad "P3 candidate form=$(cand p3 form) c=$c"; fi
# P3b the candidate object went into the temporary clone only, never into --repo
if ! g "$R" cat-file -e "$c" 2>/dev/null; then ok "P3b the merge candidate is not in --repo"; else bad "P3b the candidate object reached --repo"; fi

# P4 a merge conflict refuses
repo p4 0 0; R=$T/p4; g "$R" checkout -q -b pr; put "$R" a.txt "pr side"; head=$(g "$R" rev-parse HEAD)
g "$R" checkout -q main; put "$R" a.txt "main side"; base=$(g "$R" rev-parse HEAD)
prlc p4 --base "$base" --head "$head"
expect "P4 a merge conflict refuses" p4 1 FAIL
if grep -q 'merge conflict between base' "$T/p4.out" && [ ! -e "$T/p4.badges.argv" ]; then ok "P4 conflict named; no check ran"; else bad "P4"; fi

# P5 --form ff-only refuses a non-fast-forward
repo p5 0 0; R=$T/p5; g "$R" checkout -q -b pr; put "$R" pr.txt pr; head=$(g "$R" rev-parse HEAD)
g "$R" checkout -q main; put "$R" m.txt m; base=$(g "$R" rev-parse HEAD)
prlc p5 --base "$base" --head "$head" --form ff-only
expect "P5 --form ff-only refuses a non-fast-forward" p5 1 FAIL

# P6 a revision that does not resolve is BLIND (exit 2), never a pass
repo p6 0 0; prlc p6 --base main --head no-such-ref
expect "P6 an unresolvable --head is BLIND" p6 2 BLIND
run "$T/p6b.out" "$PRLC" --repo "$T/p6" --base main --head main
if [ "$RC" -eq 2 ] && [ "$(tail -n 1 "$T/p6b.out")" = "RESULT: BLIND" ]; then ok "P6b a missing --evidence-dir is a usage error (exit 2)"; else bad "P6b rc=$RC"; fi

# P7 golden-FALSE: no check script on base or head -> not-applicable, PASS
repo p7 - -; R=$T/p7; put "$R" b.txt b
prlc p7 --base main~1 --head main
expect "P7 a repository without drift-check scripts passes" p7 0 PASS
if [ "$(row p7 badges)" = not-applicable ] && [ "$(row p7 gate-env-allowlist)" = not-applicable ]; then ok "P7 both rows not-applicable"; else bad "P7 rows"; fi

# P8 a PR head that deletes a check script present on base -> FAIL-script-missing
repo p8 0 0; R=$T/p8; base=$(g "$R" rev-parse HEAD); g "$R" rm -q "$BADGE_P"; g "$R" commit -q -m drop
prlc p8 --base "$base" --head main
expect "P8 deleting a required check script refuses" p8 1 FAIL
if [ "$(row p8 badges)" = FAIL-script-missing ]; then ok "P8 tsv FAIL-script-missing"; else bad "P8 row=$(row p8 badges)"; fi

# P9 a check that exits 2 (BLIND) refuses; BLIND is never a pass
repo p9 2 0; prlc p9 --base main~1 --head main
expect "P9 a BLIND (exit 2) check refuses" p9 1 FAIL
if [ "$(row p9 badges)" = FAIL ]; then ok "P9 tsv badges=FAIL"; else bad "P9 row=$(row p9 badges)"; fi

# P10 a check that dirties the candidate tree refuses
repo p10 - -; R=$T/p10
# shellcheck disable=SC2016 # literal stub line; $2 expands in the stub
put "$R" "$BADGE_P" "$(stub "$T/p10.badges.argv" 0 'printf x > "$2/leak.txt"')"
prlc p10 --base main~1 --head main
expect "P10 a check that changes the tree refuses" p10 1 FAIL
if grep -q 'drift checks changed the clone working tree' "$T/p10.out"; then ok "P10 changed tree named"; else bad "P10"; fi

# P11 the merge candidate, not the PR head, is checked: base adds a failing check after the PR
# branched; the PR head alone has no such script, the merged tree does
repo p11 - -; R=$T/p11; g "$R" checkout -q -b pr; put "$R" pr.txt pr; head=$(g "$R" rev-parse HEAD)
g "$R" checkout -q main; put "$R" "$BADGE_P" "$(stub "$T/p11.badges.argv" 1)"; base=$(g "$R" rev-parse HEAD)
prlc p11 --base "$base" --head "$head"
expect "P11 a check that fails only on the merged tree refuses" p11 1 FAIL
if [ "$(row p11 badges)" = FAIL ] && [ "$(cand p11 form)" = merge-commit ]; then ok "P11 the merged tree was checked"; else bad "P11 row=$(row p11 badges) form=$(cand p11 form)"; fi

# P12 --repo is not changed: refs, config and the object count are equal before and after
repo p12 0 0; R=$T/p12; g "$R" checkout -q -b pr; put "$R" pr.txt pr; g "$R" checkout -q main; put "$R" m.txt m
snap() { { g "$R" for-each-ref; sha256sum "$R/.git/config"; g "$R" count-objects -v | grep -v '^size'; g "$R" status --porcelain; } 2>&1; }
before=$(snap)
prlc p12 --base main --head pr
after=$(snap)
if [ "$RC" -eq 0 ] && [ "$before" = "$after" ]; then ok "P12 --repo unchanged (refs, config, objects, status)"; else bad "P12 rc=$RC"; diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/    | /' || true; fi

# P13 --form merge-commit on a fast-forwardable PR still builds and checks a merge commit
repo p13 0 0; R=$T/p13; prlc p13 --base main~1 --head main --form merge-commit
expect "P13 --form merge-commit builds a merge candidate" p13 0 PASS
if [ "$(cand p13 form)" = merge-commit ]; then ok "P13 form merge-commit"; else bad "P13 form=$(cand p13 form)"; fi

# P14 a copy without its drift-check library is BLIND (exit 2), never a pass
repo p14 0 0; mkdir -p "$T/p14nolib"; cp "$PRLC" "$T/p14nolib/pr_landing_check.sh"
run "$T/p14.out" "$T/p14nolib/pr_landing_check.sh" --repo "$T/p14" --base main~1 --head main --evidence-dir "$T/p14.ev"
expect "P14 a missing drift-check library is BLIND" p14 2 BLIND
# the refusal names the missing library path (the first guard), not only a load failure
if grep -qF "drift-check library not found: $T/p14nolib/lib/landing_drift_checks.sh" "$T/p14.out"; then
  ok "P14b the refusal names the missing library path"; else bad "P14b library-not-found message"; sed 's/^/    | /' "$T/p14.out"; fi

# P15 the candidate (detached HEAD of the private clone) moved while the checks ran: refused. The
# stand-in commits the same tree on top of HEAD and moves HEAD, so the working tree stays clean and
# only the ref check can see it (pairs the PR binding LDC_REF=HEAD; the lander's D11 covers its own)
repo p15 - -; R=$T/p15
# shellcheck disable=SC2016 # literal stub line; $2 and $c expand in the stub
put "$R" "$BADGE_P" "$(stub "$T/p15.badges.argv" 0 'cd "$2" && c=$(git commit-tree "HEAD^{tree}" -p HEAD -m moved) && git update-ref --no-deref HEAD "$c"')"
prlc p15 --base main~1 --head main
expect "P15 a candidate moved during the checks refuses" p15 1 FAIL
if grep -q 'landing candidate moved while the drift checks ran' "$T/p15.out" && ! grep -q 'drift checks changed the clone working tree' "$T/p15.out" \
   && [ "$(row p15 badges)" = PASS ]; then ok "P15 the move is named; the tree stayed clean; the check itself passed"
else bad "P15"; sed 's/^/    | /' "$T/p15.out"; fi

# L1 real checks on a clone of this repository's HEAD (host-only gate-logic evidence)
if [ "${PRLC_TEST_SKIP_LIVE:-0}" = 1 ]; then skip "L1 real badge and env-allowlist checks (PRLC_TEST_SKIP_LIVE=1)"
elif ! git -C "$ROOT" rev-parse -q --verify HEAD >/dev/null 2>&1; then skip "L1 real checks: $ROOT is not a git checkout (topology_unsupported)"
else
  L=$T/live; git clone -q --no-hardlinks "$ROOT" "$L"; base=$(g "$L" rev-parse HEAD)
  # control needle: the real badge check must pass on the unmodified base, else the leg is blind
  set +e; (cd "$L" && bash "$L/$BADGE_P" --root "$L" --check) > "$T/live.control" 2>&1; crc=$?; set -e
  if [ "$crc" -ne 0 ]; then bad "L1 control: the real badge check fails on HEAD itself (rc=$crc); regenerate the README badge row first"; sed 's/^/    | /' "$T/live.control"
  else
    g "$L" checkout -q -b pr
    rowline=$(grep -n '^!\[Version\]' "$L/README.md" | head -n 1 | cut -d: -f1)
    sed -i "${rowline}s#badge/anchors-[0-9]*-green#badge/anchors-99999-green#" "$L/README.md"
    g "$L" commit -q -am "docs: PR change with a stale badge row"; stale=$(g "$L" rev-parse HEAD)
    run "$T/live.out" "$PRLC" --repo "$L" --base "$base" --head "$stale" --evidence-dir "$T/live.ev"
    if [ "$RC" -eq 1 ] && [ "$(awk -F '\t' '$1=="badges" {print $5}' "$T/live.ev/drift_checks.tsv")" = FAIL ]; then
      ok "L1 RED: a PR head with a stale badge row is refused by the real check (rc=1)"; else bad "L1 RED rc=$RC"; sed 's/^/    | /' "$T/live.out"; fi
    fresh_row=$(cd "$L" && bash "$L/$BADGE_P" --root "$L" --print)
    awk -v n="$rowline" -v r="$fresh_row" 'NR==n {print r; next} {print}' "$L/README.md" > "$T/readme.new"
    cp "$T/readme.new" "$L/README.md"; g "$L" commit -q -am "docs: regenerate the badge row"; fresh=$(g "$L" rev-parse HEAD)
    run "$T/live2.out" "$PRLC" --repo "$L" --base "$base" --head "$fresh" --evidence-dir "$T/live2.ev"
    if [ "$RC" -eq 0 ] && [ "$(awk -F '\t' '$1=="badges" {print $5}' "$T/live2.ev/drift_checks.tsv")" = PASS ] \
       && [ "$(awk -F '\t' '$1=="gate-env-allowlist" {print $5}' "$T/live2.ev/drift_checks.tsv")" = PASS ]; then
      ok "L1 GREEN: the same PR after regeneration passes both real checks (rc=0)"; else bad "L1 GREEN rc=$RC"; sed 's/^/    | /' "$T/live2.out"; fi
  fi
fi

printf '\nRESULT pass=%d fail=%d skip=%d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
