#!/usr/bin/env bash
# tests/release/test_derive_release_facts_provisional.sh — hermetic test of two derivations of
# scripts/release/derive_release_facts.sh (rel1: a quoted verification marker is not a verification line;
# rel2: --retest-item flags an item that is not a recorded retest). Real git and real sqlite3; the oracle
# is a fixture tracker with expected values written by hand. Evidence class: gate-logic (PROVISIONAL).
# DRF_SCRIPT overrides the script under test (a copy of the scripts/release directory, for the mutants).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${DRF_SCRIPT:-$ROOT/scripts/release/derive_release_facts.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_prov.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
mkdir -p "$W/tmp"; export TMPDIR="$W/tmp"
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
R="$W/repo"; "${G[@]}" init -q "$R"; mkdir -p "$R/docs"
DB="$R/docs/workable_items.db"
BT='```'
sqlite3 -bail "$DB" <<SQL || { echo "FAIL fixture database could not be built"; exit 1; }
CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT,
  reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET', closure_date TEXT);
-- real verification lines: counted (T-001 undated = overdue, T-002 future, T-003 past)
INSERT INTO items VALUES ('T-001','Ready for testing','Low','Issues','x
**Verification:** provisional -- job: j -- due: next full retest','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-002','Ready for testing','Low','Issues','x
**Verification:** provisional -- job: j -- due: 2099-01-01','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-003','In progress','Low','Issues','x
**Verification:** provisional -- job: j -- due: 2000-01-01','UNSET','UNSET',NULL);
-- quoted marker in prose (the CON-521 shape): NOT a verification line
INSERT INTO items VALUES ('T-004','Queued','Low','Issues','Some items are Ready for testing with no **Verification:** provisional line, so the count was wrong.','UNSET','UNSET',NULL);
-- marker at line start but inside a fenced block (a quotation of a template): NOT a verification line
INSERT INTO items VALUES ('T-005','Queued','Low','Issues','example:
$BT
**Verification:** provisional -- job: q -- due: 2000-01-01
$BT
done','UNSET','UNSET',NULL);
-- a real line AFTER a closed fence is still counted
INSERT INTO items VALUES ('T-006','Ready for testing','Low','Issues','$BT
**Verification:** provisional -- job: q -- due: 2000-01-01
$BT
**Verification:** provisional -- job: r -- due: 2000-02-02','UNSET','UNSET',NULL);
-- retest candidates: a Queued note (not evidence) and a Fixed item (evidence)
INSERT INTO items VALUES ('T-100','Queued','Medium','Issues','owed retest note','UNSET','UNSET',NULL);
-- F2 (review of e5efbf77): every CommonMark fenced-block form hides a marker line, not only a column-0 backtick fence
-- T-007 tilde fence (reviewer A-01)
INSERT INTO items VALUES ('T-007','Queued','Low','Issues','x
~~~
**Verification:** provisional -- job: q -- due: 2000-01-01
~~~','UNSET','UNSET',NULL);
-- T-008 a fence indented 2 spaces (reviewer A-02)
INSERT INTO items VALUES ('T-008','Queued','Low','Issues','x
  $BT
**Verification:** provisional -- job: q -- due: 2000-01-01
  $BT','UNSET','UNSET',NULL);
-- T-009 a 4-backtick fence holding a 3-backtick line: the inner line does not close it (reviewer A-08)
INSERT INTO items VALUES ('T-009','Queued','Low','Issues','x
\`$BT
$BT
**Verification:** provisional -- job: q -- due: 2000-01-01
\`$BT','UNSET','UNSET',NULL);
-- T-010 a marker indented 2 spaces outside any fence does not START with the marker: not counted (reviewer A-03)
INSERT INTO items VALUES ('T-010','Queued','Low','Issues','x
  **Verification:** provisional -- job: q -- due: 2000-01-01','UNSET','UNSET',NULL);
-- T-011 a backtick line whose info string has a backtick is not a fence: the marker after it counts (past, overdue)
INSERT INTO items VALUES ('T-011','Queued','Low','Issues','x
${BT}a\`b
**Verification:** provisional -- job: q -- due: 2000-01-01','UNSET','UNSET',NULL);
-- T-012 a 3-backtick fence closed by a longer one; the marker after it counts (past, overdue)
INSERT INTO items VALUES ('T-012','Queued','Low','Issues','x
$BT
quoted
\`\`$BT
**Verification:** provisional -- job: q -- due: 2000-01-01','UNSET','UNSET',NULL);
-- F3 (reviewer A-10): "provisionally" is another word, not the marker
INSERT INTO items VALUES ('T-013','Queued','Low','Issues','x
**Verification:** provisionally passing -- due: 2000-01-01','UNSET','UNSET',NULL);
-- F4 (reviewer A-11): the FIRST due: field of the line is the due date (past, overdue)
INSERT INTO items VALUES ('T-014','Queued','Low','Issues','x
**Verification:** provisional -- due: 2000-01-01 -- note: was due: 2099-01-01','UNSET','UNSET',NULL);
-- F5 (reviewer fixture B-01, kills R8): fenced past-dated line, real future-dated line: provisional, not overdue
INSERT INTO items VALUES ('T-015','Queued','Low','Issues','x
$BT
**Verification:** provisional -- due: 2000-01-01
$BT
**Verification:** provisional -- due: 2099-01-01','UNSET','UNSET',NULL);
-- T-016 a tilde line does not close a backtick fence, and a fence line with an info string does not close it either
INSERT INTO items VALUES ('T-016','Queued','Low','Issues','x
$BT
~~~
$BT x
**Verification:** provisional -- job: q -- due: 2000-01-01
$BT','UNSET','UNSET',NULL);
-- T-017 two real lines, the first future-dated: the FIRST line is the verification line, not overdue (kills R5)
INSERT INTO items VALUES ('T-017','Queued','Low','Issues','x
**Verification:** provisional -- due: 2099-01-01
**Verification:** provisional -- due: 2000-01-01','UNSET','UNSET',NULL);
-- CRLF body (reviewer A-05): counted, overdue
INSERT INTO items VALUES ('T-018','Queued','Low','Issues','x'||char(13)||char(10)||'**Verification:** provisional -- due: 2000-01-01'||char(13)||char(10),'UNSET','UNSET',NULL);
-- T-021 CRLF body with a fence: the fence lines end in CR and still open and close it; the real line after it is
-- provisional, not overdue (the fenced past-dated line does not count)
INSERT INTO items VALUES ('T-021','Queued','Low','Issues','x'||char(13)||char(10)||'$BT'||char(13)||char(10)||'**Verification:** provisional -- due: 2000-01-01'||char(13)||char(10)||'$BT'||char(13)||char(10)||'**Verification:** provisional -- due: 2099-01-01'||char(13)||char(10),'UNSET','UNSET',NULL);
-- T-022 the marker after 15 characters of a line, so the character 30 places from the line start is ':' (kills
-- M1, the marker anywhere in a line): a quotation, not a verification line
INSERT INTO items VALUES ('T-022','Queued','Low','Issues','x
Example quote: **Verification:** provisional -- due: 2000-01-01','UNSET','UNSET',NULL);
-- the bare marker at the end of the line: counted, undated = overdue
INSERT INTO items VALUES ('T-019','Queued','Low','Issues','x
**Verification:** provisional','UNSET','UNSET',NULL);
-- "overdue:" is not the due: field; the due: field after it is future: provisional, not overdue
INSERT INTO items VALUES ('T-020','Queued','Low','Issues','x
**Verification:** provisional -- overdue: yes -- due: 2099-01-01','UNSET','UNSET',NULL);
-- F8: only a Fixed item closed AFTER the previous tag (dated 2026-01-02) is this candidate's retest evidence
INSERT INTO items VALUES ('T-101','Fixed (→ Fixed.md)','Medium','Fixed','retest recorded','UNSET','UNSET','2001-01-01');
INSERT INTO items VALUES ('T-102','Fixed (→ Fixed.md)','Medium','Fixed','retest recorded','UNSET','UNSET','2026-03-01');
INSERT INTO items VALUES ('T-103','Fixed (→ Fixed.md)','Medium','Fixed','retest recorded','UNSET','UNSET',NULL);
SQL
( cd "$R" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a \
  && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm b )
run(){ ( cd "$R" && timeout 120 bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 "$@" 2>&1 ); }
OUT="$(run)"; RC=$?
has(){ if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1 (missing line: $2)"; fi; }
[ "$RC" = 0 ] && ok "rel1 exit 0" || bad "rel1 exit 0 (got $RC)"
has "rel1 positive control: real lines counted, quoted and fenced markers not" "provisional_ids=T-001 T-002 T-003 T-006 T-011 T-012 T-014 T-015 T-017 T-018 T-019 T-020 T-021"
has "rel1 overdue: undated and past-dated, not future; the first due: of the first line" "overdue_ids=T-001 T-003 T-006 T-011 T-012 T-014 T-018 T-019"
has "rel1 count line" "count_line=1 verified + 13 provisional (8 overdue)"
for x in T-004:prose T-005:fence T-007:tilde-fence T-008:indented-fence T-009:longer-fence-inner-line T-010:indented-marker T-013:provisionally T-016:non-closing-lines T-022:mid-line-quotation; do
  printf '%s\n' "$OUT" | grep -E '^(provisional_ids|overdue_ids)=' | grep -qw "${x%%:*}" && bad "rel1 ${x%%:*} (${x#*:}) is not provisional" || ok "rel1 ${x%%:*} (${x#*:}) is not provisional"
done
# rel2: --retest-item
OUT="$(run --retest-item T-100)"; RC=$?
[ "$RC" = 0 ] && ok "rel2 a Queued retest item: facts printed (rc 0)" || bad "rel2 a Queued retest item: rc $RC"
has "rel2 id" "retest_item_id=T-100"
has "rel2 status" "retest_item_status=Queued (Issues)"
has "rel2 not evidence" "retest_item_evidence=no"
printf '%s\n' "$OUT" | grep -q '^retest_item_flag=NOT-EVIDENCE' && ok "rel2 flag line names NOT-EVIDENCE" || bad "rel2 flag line names NOT-EVIDENCE"
OUT="$(run --retest-item T-102)"; RC=$?
has "rel2 positive control: a Fixed item closed after the previous tag is evidence" "retest_item_evidence=yes"
has "rel2/F8 the closure date is printed" "retest_item_closure=2026-03-01"
printf '%s\n' "$OUT" | grep -q '^retest_item_flag=' && bad "rel2 no flag for a Fixed item closed after the tag" || ok "rel2 no flag for a Fixed item closed after the tag"
for x in T-101:2001-01-01 T-103:none; do
  OUT="$(run --retest-item "${x%%:*}")"; RC=$?
  has "F8 ${x%%:*} (Fixed, closed ${x#*:}) is not this candidate's evidence" "retest_item_evidence=no"
  printf '%s\n' "$OUT" | grep -q '^retest_item_flag=NOT-EVIDENCE: .*not after the previous tag' && ok "F8 ${x%%:*} flag names the stale or undated closure" || bad "F8 ${x%%:*} flag names the stale or undated closure"
  OUT="$(run --retest-item "${x%%:*}" --require-retest-evidence)"; RC=$?
  [ "$RC" = 3 ] && ok "F8 --require-retest-evidence refuses ${x%%:*} (rc 3)" || bad "F8 --require-retest-evidence refuses ${x%%:*} (rc $RC)"
done
OUT="$(run --retest-item T-100 --require-retest-evidence)"; RC=$?
[ "$RC" = 3 ] && ok "rel2 --require-retest-evidence refuses a Queued item (rc 3)" || bad "rel2 --require-retest-evidence refuses a Queued item (rc $RC)"
[ -z "$(printf '%s' "$OUT" | grep '^base=')" ] && ok "rel2 a refusal prints no facts" || bad "rel2 a refusal prints no facts"
OUT="$(run --retest-item T-102 --require-retest-evidence)"; RC=$?
[ "$RC" = 0 ] && ok "rel2 --require-retest-evidence accepts a Fixed item" || bad "rel2 --require-retest-evidence accepts a Fixed item (rc $RC)"
OUT="$(run --retest-item NOPE-1)"; RC=$?
[ "$RC" = 3 ] && ok "rel2 an unknown item id is refused (rc 3), never cited" || bad "rel2 an unknown item id is refused (rc $RC)"
printf '%s\n' "$OUT" | grep -q 'retest item NOPE-1 is not in the tracker' && ok "F9 control: an unknown id says not in the tracker" || bad "F9 control: an unknown id says not in the tracker"
# F9: when the lookup query itself fails (a tracker without closure_date), the message says so, never "not in the tracker"
R2="$W/repo2"; "${G[@]}" init -q "$R2"; mkdir -p "$R2/docs"
sqlite3 -bail "$R2/docs/workable_items.db" "CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT, reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET'); INSERT INTO items(atm_id,status,severity,current_location,body_md) VALUES ('T-102','Fixed','Low','Fixed','x');" || bad "F9 fixture could not be built"
( cd "$R2" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a && "${G[@]}" tag -a prev-v1 -m prev )
OUT="$( cd "$R2" && timeout 120 bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 --retest-item T-102 2>&1 )"; RC=$?
[ "$RC" = 3 ] && ok "F9 a failed lookup query exits 3" || bad "F9 a failed lookup query exits 3 (rc $RC)"
printf '%s\n' "$OUT" | grep -q 'retest item lookup query failed' && ok "F9 a failed lookup query is named as such" || bad "F9 a failed lookup query is named as such"
printf '%s\n' "$OUT" | grep -q 'is not in the tracker' && bad "F9 a failed lookup query does not say not in the tracker" || ok "F9 a failed lookup query does not say not in the tracker"
printf '%s\n' "$OUT" | grep -q '^base=' && bad "F9 a failed lookup query prints no facts" || ok "F9 a failed lookup query prints no facts"
OUT="$(run --retest-item 'a b')"; RC=$?
[ "$RC" = 2 ] && ok "rel2 a malformed item id is a usage error (rc 2)" || bad "rel2 a malformed item id (rc $RC)"
OUT="$(run)"
printf '%s\n' "$OUT" | grep -q '^retest_item' && bad "rel2 without the option no retest_item fact is printed" || ok "rel2 without the option no retest_item fact is printed"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
