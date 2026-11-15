#!/usr/bin/env bash
# f9_search.sh REPO COMMIT — is the tests/install/test_round8.sh re-run race (review F9) already a tracked item?
# Searches the tracked text of COMMIT (docs, CHANGELOG.md, README.md; the round-1 QA directory of this vehicle is
# excluded, it is where the race was first written down) and the items table of docs/workable_items.db at COMMIT.
# Prints every hit; the reader decides. A positive control first proves the search can see a phrase that exists.
set -u
repo="${1:?}"; c="${2:?}"; export LC_ALL=C
cd "$repo" || exit 2
echo "commit: $(git rev-parse "$c")"
echo "## positive control: 'CON-110' must be found in docs/Issues.md"
git grep -c -F 'CON-110' "$c" -- docs/Issues.md || echo "CONTROL FAILED"
echo "## tracked text (git grep -i -F, COMMIT, docs CHANGELOG.md README.md, not docs/qa/installer_sigpipe_2026_11_13)"
for p in 'tests/install/test_round8' 'test_round8' 'round8' 're-run race' 'rerun race' 'timeout --foreground' \
         'SIGTERM chaos' 'installer flake' 'installer-flake' 'git lock' 'index.lock'; do
  printf '%-26s ' "$p"
  git grep -l -i -F -- "$p" "$c" -- docs CHANGELOG.md README.md ':!docs/qa/installer_sigpipe_2026_11_13' 2>/dev/null \
    | sed "s|^$c:||" | tr '\n' ' '
  echo
done
echo "## docs/workable_items.db items (title or description LIKE %phrase%)"
t="$(mktemp -d "${TMPDIR:-/tmp}/f9.XXXXXX")" || exit 2
git show "$c:docs/workable_items.db" >"$t/w.db" || exit 2
echo "control: $(sqlite3 "$t/w.db" "select count(*) from items where atm_id = 'CON-110'") row for CON-110 (must be 1)"
for p in 'install/test_round8' 'test_round8.sh' 'test_round8' 'SIGTERM' 'process group' 'flake' 'INSTALLER-SIGPIPE' 're-run'; do
  printf '%-22s ' "$p"
  sqlite3 -separator ' ' "$t/w.db" "select atm_id from items where title like '%$p%' or description like '%$p%'" | tr '\n' ' '
  echo
done
echo "## titles of every item hit above"
sqlite3 -separator ' | ' "$t/w.db" "select atm_id, status, substr(title, 1, 140) from items where atm_id in
  (select atm_id from items where title like '%test_round8%' or description like '%test_round8%' or title like '%SIGTERM%'
   or description like '%SIGTERM%' or title like '%process group%' or description like '%process group%'
   or title like '%flake%' or description like '%flake%' or title like '%re-run%' or description like '%re-run%'
   or atm_id in ('CON-110', 'CON-127'))"
rm -rf -- "${t:?}"
