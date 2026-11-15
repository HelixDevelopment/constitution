#!/usr/bin/env bash
# trial_merge.sh W SYNC_REPO OUT — trial merge of the sync vehicle (branch "sync" of SYNC_REPO) into
# vehicle/installer-sigpipe-r2 of W/repo, in a throwaway clone under W. Nothing is committed or pushed; the clone is
# removed at the end. Writes the report to OUT:
#   1. the merge into the vehicle head: exit status, unmerged paths, conflict hunks per file, files both sides touch;
#   2. control: the same merge onto main bd0036bd alone (is a conflict this vehicle's, or the sync vehicle's own?);
#   3. does the vehicle touch CHANGELOG.md or README.md;
#   4. every conflict that the vehicle adds (unmerged in 1, not in 2), shown;
#   5. resolution check: take either side of each added conflict, regenerate the census with the official tool and
#      run its manifest check.
# Exit 0 report written, 2 usage or setup failure.
set -u
W="${1:?usage: trial_merge.sh W SYNC_REPO OUT}"; SRC="${2:?SYNC_REPO}"; OUT="${3:?OUT}"
# shellcheck source=/dev/null
. "$W/repo/scripts/lib/safe_rm.sh" || exit 2
T="$(mktemp -d "$W/trialmerge2.XXXX")" || exit 2
# sort and comm in the C locale: comm checks byte order, and a locale sort order makes it refuse its input
srt() { LC_ALL=C sort "$@"; }
cmm() { LC_ALL=C comm "$@"; }
G=(git -c user.name=trial -c user.email=trial@invalid -c advice.detachedHead=false)
report() {
  git clone -q --no-hardlinks "$W/repo" "$T/tm" || return 2
  cd "$T/tm" || return 2
  "${G[@]}" fetch -q "$SRC" sync:sync || return 2
  BASE="$(git rev-parse bd0036bd)"
  head="$(git rev-parse HEAD)"; sync="$(git rev-parse sync)"; sbase="$(git merge-base sync "$BASE")"
  printf '## trial merge: sync (%s, base %s) into vehicle/installer-sigpipe-r2 (%s, base %s)\n' \
    "${sync:0:8}" "${sbase:0:8}" "${head:0:8}" "${BASE:0:8}"
  "${G[@]}" checkout -q -b trial "$head"
  "${G[@]}" merge -q --no-ff --no-commit sync >/dev/null 2>&1
  rc=$?
  echo "merge rc=$rc"
  echo "## unmerged paths:"
  git diff --name-only --diff-filter=U | tee "$T/u_vehicle"
  echo "## conflict hunks per file:"
  while IFS= read -r f; do printf '%s %s\n' "$(grep -c '^<<<<<<<' -- "$f")" "$f"; done <"$T/u_vehicle"
  echo "## files touched by both sides:"
  git diff --name-only "$BASE" "$head" | srt >"$T/f_vehicle"
  git diff --name-only "$sbase" "$sync" | srt >"$T/f_sync"
  cmm -12 "$T/f_vehicle" "$T/f_sync"
  while IFS= read -r f; do cp -- "$f" "$T/conflict_$(printf '%s' "$f" | tr '/' '_')"; done <"$T/u_vehicle"
  "${G[@]}" merge --abort
  echo
  echo "## control: the same merge onto main ${BASE:0:8} alone (no round-2 vehicle)"
  "${G[@]}" checkout -q -b ctl "$BASE"
  "${G[@]}" merge -q --no-ff --no-commit sync >/dev/null 2>&1
  rc=$?
  echo "merge rc=$rc"
  echo "## unmerged paths:"
  git diff --name-only --diff-filter=U | tee "$T/u_ctl"
  "${G[@]}" merge --abort
  echo "## round-2 vehicle touches CHANGELOG.md or README.md?"
  grep -xE 'CHANGELOG\.md|README\.md' "$T/f_vehicle" || echo "  no"
  echo
  srt "$T/u_vehicle" >"$T/u_v"; srt "$T/u_ctl" >"$T/u_c"
  cmm -23 "$T/u_v" "$T/u_c" >"$T/added"
  # control needle: the added list and the control list together give back every unmerged path
  if [ "$(cat "$T/added" "$T/u_c" | srt -u)" = "$(cat "$T/u_v")" ]; then ok=yes; else ok=NO; fi
  echo "## check: added + control = every unmerged path of the merge into the vehicle: $ok"
  echo "## conflicts the round-2 vehicle adds (unmerged above, not in the control): $(wc -l <"$T/added")"
  while IFS= read -r f; do
    echo "## $f"
    sed -n '/^<<<<<<< /,/^>>>>>>> /p' -- "$T/conflict_$(printf '%s' "$f" | tr '/' '_')"
  done <"$T/added"
  echo
  echo "## resolution check (trial clone only): take either side of each added conflict, regenerate with the official tool"
  for side in ours theirs; do
    "${G[@]}" checkout -q trial
    "${G[@]}" merge -q --no-ff --no-commit sync >/dev/null 2>&1
    while IFS= read -r f; do "${G[@]}" checkout -q "--$side" -- "$f"; done <"$T/added"
    # the conflicts the sync vehicle has with main alone (CHANGELOG.md, README.md) are resolved as "theirs" here only so
    # that the tree is clean enough to run the tool; they are not this vehicle's
    while IFS= read -r f; do grep -qxF -- "$f" "$T/added" || "${G[@]}" checkout -q --theirs -- "$f"; done <"$T/u_vehicle"
    bash scripts/run_full_suite.sh --sync-guide >"$T/sync_$side.txt" 2>&1
    s_rc=$?
    grep -m1 -E '^census \(generated' docs/guides/full_suite_runner_guide.md | sed "s/^/side $side: guide census block after --sync-guide (rc=$s_rc): /"
    bash scripts/run_full_suite.sh --verify-manifest >"$T/verify_$side.txt" 2>&1
    v_rc=$?
    echo "side $side: --verify-manifest rc=$v_rc"
    sed 's/^/  /' "$T/verify_$side.txt"
    "${G[@]}" merge --abort 2>/dev/null || "${G[@]}" reset -q --merge
  done
  echo "## bash -n on tests/install/test_unit.sh after the textual merge (side theirs for the sync-only conflicts):"
  "${G[@]}" checkout -q trial
  "${G[@]}" merge -q --no-ff --no-commit sync >/dev/null 2>&1
  if bash -n tests/install/test_unit.sh; then echo "  bash -n OK"; else echo "  bash -n FAILED"; fi
  "${G[@]}" merge --abort
}
report >"$OUT" 2>&1
rc=$?
cd "$W" || exit 2
safe_rm_rf "${T:?}"
[ "$rc" = 0 ] || exit 2
exit 0
