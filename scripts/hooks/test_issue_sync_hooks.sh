#!/usr/bin/env bash
# scripts/hooks/test_issue_sync_hooks.sh -- hermetic test of the issue-sync pre-commit and post-merge hooks (anchor §11.4.300(E)).
# Cases: no config => allow; enabled:false => allow; enabled with pending DB change => refuse; ISSUE_SYNC_ACK=1 => allow; post-merge with mode dry-run => no background job.
# Usage: test_issue_sync_hooks.sh   Exit 0 all PASS, 1 any FAIL. Side-effects: temp dir only. Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SCR="$(cd "$HERE/.." && pwd)"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; fail=0
ok() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (expected $2 got $3)"; fail=1; fi; }
cd "$W" && git init -q r && cd r && mkdir docs && python3 - <<'PY'
import sqlite3
c = sqlite3.connect("docs/workable_items.db")
c.execute("CREATE TABLE items (atm_id,type,status,title,severity,description,forensic_anchor,body_md,current_location)")
c.execute("INSERT INTO items VALUES ('A-1','Bug','Queued','t','','a long enough description here',NULL,NULL,'Issues')"); c.commit()
PY
export ISSUE_SYNC_HOME="$SCR"
bash "$HERE/issue_sync_pre_commit.sh" 2>/dev/null; ok "no config allows" 0 $?
printf 'enabled: false\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_pre_commit.sh" 2>/dev/null; ok "enabled:false allows" 0 $?
printf 'enabled: true\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_pre_commit.sh" 2>/dev/null; ok "pending change refuses" 1 $?
ISSUE_SYNC_ACK=1 bash "$HERE/issue_sync_pre_commit.sh" 2>/dev/null; ok "ack allows" 0 $?
printf 'enabled: true\nbogus: 1\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_pre_commit.sh" 2>/dev/null; ok "invalid config does not silently allow" 1 $?
printf 'enabled: true\nmode: dry-run\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_post_merge.sh"; ok "post-merge dry-run exits 0" 0 $?
[ ! -e .git/issue-sync.log ]; ok "post-merge dry-run starts no job" 0 $?
printf 'enabled: true\nmode: apply\napply_decision: d.md\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_post_merge.sh"; ok "post-merge without targets exits 0" 0 $?
grep -q undeclared .git/issue-sync.log; ok "post-merge logs undeclared targets" 0 $?
# the hooks take the mode from the engine's validator, never from grepping the YAML: an invalid declaration (YAML 1.1 boolean, duplicate key) is never ON
export ISSUE_SYNC_TARGETS="github.com/o/r" ISSUE_SYNC_OWNER_REPO="github.com/o/r"
for bad in 'enabled: yes\nmode: apply\napply_decision: d.md\n' 'enabled: false\nenabled: true\nmode: apply\napply_decision: d.md\n'; do
  rm -f .git/issue-sync.log; printf "$bad" > .workable-items-sync.yaml; bash "$HERE/issue_sync_post_merge.sh"; ok "post-merge invalid config exits 0" 0 $?
  grep -q "config invalid" .git/issue-sync.log; ok "post-merge invalid config starts no job and logs why" 0 $?
done
rm -f .git/issue-sync.log; printf 'enabled: true\nmode: dry-run\n# mode: apply\n' > .workable-items-sync.yaml; bash "$HERE/issue_sync_post_merge.sh"
[ ! -e .git/issue-sync.log ]; ok "post-merge ignores a commented-out apply line" 0 $?
exit "$fail"
