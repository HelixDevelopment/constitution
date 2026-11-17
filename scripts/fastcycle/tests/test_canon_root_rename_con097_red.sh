#!/bin/sh
# Purpose: CON-097 RED test. Canon files must be reached from a test's OWN location (three levels up),
#          never as <consumer root>/constitution/...: the canon checkout may be named anything (a scratch
#          clone, submodules/constitution, a review clone). Two halves:
#          (1) census: no test_*.sh in this directory spells $ROOT/constitution or $REPO_ROOT/constitution,
#              except the reasoned ALLOW rows below; the instrument is control-needled (section 11.4.273);
#          (2) live rename: this canon is reached through a symlink with a random name inside a scratch
#              consumer root that has NO "constitution" entry, and five converted tests must still pass (two of them, custody_sweep_r9 and fc_entry_r10, also prove a
#              consumer root that is not a git checkout falls back to the canon checkout) (one of them, governance_subset_conservative, reached canon through
#              a tool default the census cannot see: the body root defaulted to <parent of canon>).
# Usage:   sh test_canon_root_rename_con097_red.sh       Exit 0 = both halves hold, 1 = a failure.
# Mutants: test_canon_root_rename_con097_mutations.sh.
# shellcheck disable=SC2015 # the `<cond> && echo ok || { echo NOT ok; failx; }` assertion idiom
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here=$(cd "$(dirname "$0")" && pwd)
scan_dir=${FC_CON097_SCAN_DIR:-$here}
canon=$(cd "$here/../../.." && pwd)
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }
# The census pattern: a $ROOT / $REPO_ROOT expansion immediately followed by /constitution as a whole path
# segment. $FC_CANON_ROOT/constitution_index.yaml and $MUTROOT/constitution (a test-built tree) do not match.
PAT='(^|[^A-Za-z0-9_])\$\{?(ROOT|REPO_ROOT)\}?/constitution([^A-Za-z0-9_]|$)'
# ALLOW rows: file|grep -F text of the line|reason. Both are inside a consumer-data section where REPO_ROOT is
# the real superproject (the consumer root), so <consumer>/constitution IS the canon there.
ALLOW='test_anchor_citations_red.sh|CONSTITUTION_MD="$REPO_ROOT/constitution/Constitution.md"|Step C runs only with a superproject
test_anchor_citations_red.sh|regenerate with: bash $REPO_ROOT/constitution/scripts/anchors/regenerate_if_stale.sh|Step C message, superproject only
test_governance_subset_red.sh|if [ ! -d "$ROOT/constitution" ] || [ "$(cd "$ROOT/constitution" && pwd -P)" != "$(cd "$FC_CANON_ROOT" && pwd -P)" ]; then|checks WHETHER the consumer layout holds this canon (it does not read canon through it)'
# Control needles: a positive fixture the census MUST flag, a negative fixture it must NOT.
mkdir "$tmp/pos" "$tmp/neg"
printf '%s\n' '#!/bin/sh' 'FC="$ROOT/constitution/scripts/fastcycle"' 'X="${REPO_ROOT}/constitution"' >"$tmp/pos/test_p.sh"
printf '%s\n' '#!/bin/sh' 'I="$FC_CANON_ROOT/constitution_index.yaml"' 'M="$MUTROOT/constitution/x"' 'C="$ROOT/constitution_x"' >"$tmp/neg/test_n.sh"
census() { grep -nE "$PAT" "$1"/test_*.sh 2>/dev/null | while IFS= read -r hit; do
    f=${hit%%:*}; b=$(basename "$f"); line=${hit#*:}; line=${line#*:}; allowed=0
    case $b in test_canon_root_rename_con097_red.sh|test_canon_root_rename_con097_mutations.sh) continue ;; esac  # carriers: they quote the pattern
    while IFS='|' read -r af atext _r; do
      [ "$af" = "$b" ] && case $line in *"$atext"*) allowed=1 ;; esac
    done <<EOA
$ALLOW
EOA
    [ "$allowed" -eq 1 ] || printf '%s\n' "$hit"
  done; }
pn=$(census "$tmp/pos" | wc -l); nn=$(census "$tmp/neg" | wc -l)
[ "$pn" -eq 2 ] && echo "ok control needle: census flags both positive-fixture lines ($pn)" || { echo "NOT ok control needle: census is blind (positive fixture hits=$pn, want 2)"; failx; }
[ "$nn" -eq 0 ] && echo "ok negative control: census does not flag FC_CANON_ROOT / MUTROOT / constitution_x ($nn)" || { echo "NOT ok negative control flagged $nn line(s)"; failx; }
census "$scan_dir" >"$tmp/hits"
nh=$(wc -l <"$tmp/hits" | tr -d ' ')
nf=$(ls "$scan_dir"/test_*.sh 2>/dev/null | wc -l | tr -d ' ')
[ "$nf" -gt 0 ] || { echo "NOT ok census scanned zero test files in $scan_dir (blind)"; failx; }
if [ "$nh" -eq 0 ]; then echo "ok census: none of $nf test files reaches canon as \$ROOT/constitution or \$REPO_ROOT/constitution"
else echo "NOT ok census: $nh line(s) reach canon through the consumer root (rename-fragile):"; sed 's/^/   /' "$tmp/hits" | head -40; failx; fi
# Each ALLOW row must still match a real line (a stale allow row would hide nothing but rot).
printf '%s\n' "$ALLOW" | while IFS='|' read -r af atext _r; do
  grep -qF -- "$atext" "$scan_dir/$af" 2>/dev/null || echo "STALE $af"
done >"$tmp/stale"
[ ! -s "$tmp/stale" ] && echo "ok every ALLOW row still matches its line" || { echo "NOT ok stale ALLOW row(s): $(tr '\n' ' ' <"$tmp/stale")"; failx; }
# (2) live rename: consumer root without "constitution", canon reached as <consumer>/<random name>.
cons="$tmp/consumer"; mkdir "$cons"; name="canon_renamed_$$"
ln -s "$canon" "$cons/$name"
[ ! -e "$cons/constitution" ] && echo "ok precondition: the scratch consumer root has no constitution entry" || { echo "NOT ok precondition"; failx; }
live_n=0
for t in ${FC_CON097_LIVE_TESTS:-test_tower_detector_red.sh test_reopen_rate_state_red.sh test_governance_subset_conservative.sh test_custody_sweep_r9_regression.sh test_fc_entry_r10_regression.sh}; do
  live_n=$((live_n + 1))
  case $(head -n 1 "$here/$t") in *bash*) i=bash ;; *) i=sh ;; esac
  timeout 120 "$i" "$cons/$name/scripts/fastcycle/tests/$t" </dev/null >"$tmp/$t.out" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && echo "ok live rename: $t passes with canon named $name" || { echo "NOT ok live rename: $t rc=$rc with canon named $name"; tail -n 5 "$tmp/$t.out" | sed 's/^/   /'; failx; }
done
[ "$live_n" -ge 5 ] && echo "ok live rename ran $live_n tests" || { echo "NOT ok live rename ran only $live_n test(s) (want >= 5)"; failx; }
[ "$fail" -eq 0 ] && { echo "test_canon_root_rename_con097_red: all ok"; exit 0; }
echo "test_canon_root_rename_con097_red: FAILED"; exit 1
