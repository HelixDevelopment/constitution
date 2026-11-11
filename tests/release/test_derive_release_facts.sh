#!/usr/bin/env bash
# tests/release/test_derive_release_facts.sh — hermetic test of scripts/release/derive_release_facts.sh.
# Real git and real sqlite3; the oracle is a fixture tracker whose expected facts are written by hand
# below (never computed by the script under test). Exit 0 when every case passes; "RESULT: pass=N fail=M".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${DRF_SCRIPT:-$ROOT/scripts/release/derive_release_facts.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT INT TERM
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
R="$W/repo"; "${G[@]}" init -q "$R"; mkdir -p "$R/docs"
DB="$R/docs/workable_items.db"
sqlite3 -bail "$DB" <<'SQL' || { echo "FAIL fixture database could not be built"; exit 1; }
CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT,
  reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET', closure_date TEXT);
INSERT INTO items VALUES ('T-001','Queued','Low','Issues','plain','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-002','Queued','medium','Issues','plain','UNREPRODUCED','not-started',NULL);
INSERT INTO items VALUES ('T-003','Ready for testing','Medium','Issues','x
**Verification:** provisional -- job: j -- due: next full retest','reproduced-live','root-cause-found-with-evidence',NULL);
INSERT INTO items VALUES ('T-004','Ready for testing','High','Issues','x
**Verification:** provisional -- job: j -- due: 2099-01-01','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-010','In progress','Medium','Issues','x
**Verification:** provisional -- job: j -- due: 2000-01-01','UNREPRODUCED','not-started',NULL);
INSERT INTO items VALUES ('T-005','Fixed (→ Fixed.md)','Low','Fixed','f','UNSET','UNSET','2001-01-01');
INSERT INTO items VALUES ('T-006','Fixed (→ Fixed.md)','Low','Fixed','f','UNSET','UNSET','2999-01-01');
SQL
( cd "$R" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a \
  && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm b )
OUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>&1)"; RC=$?
has(){ if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1 (missing line: $2)"; fi; }
[ "$RC" = 0 ] && ok "exit 0" || bad "exit 0 (got $RC)"
has "commit count" "commits_since_prev=1"
has "items total" "items_total=7"
has "open count" "items_open=5"
has "status Ready ids" "open_status_ids[Ready for testing]=T-003 T-004"
has "severity case-folded" "open_severity[medium]=3"
has "severity ids" "open_severity_ids[medium]=T-002 T-003 T-010"
has "raw spellings kept" "open_severity_raw_spellings=High Low Medium medium"
has "states count" "open_states[UNREPRODUCED/not-started]=2"
has "states ids" "open_states_ids[UNREPRODUCED/not-started]=T-002 T-010"
has "UNSET counted, not listed" "open_states[UNSET/UNSET]=2"
has "any-state count" "open_items_with_any_state=3"
printf '%s\n' "$OUT" | grep -q '^open_states_ids\[UNSET/UNSET\]' && bad "UNSET/UNSET ids not listed" || ok "UNSET/UNSET ids not listed"
has "provisional ids" "provisional_ids=T-003 T-004 T-010"
has "overdue: undated and past-dated, not future" "overdue_ids=T-003 T-010"
has "verified after prev tag date only" "verified_since_prev_ids=T-006"
has "count line" "count_line=1 verified + 3 provisional (2 overdue)"
# control needles (§11.4.273): a present id is found by the same path, a fabricated id is not
printf '%s\n' "$OUT" | grep -q 'T-004' && ok "positive control T-004 present" || bad "positive control T-004 present"
printf '%s\n' "$OUT" | grep -q 'T-999' && bad "negative control T-999 absent" || ok "negative control T-999 absent"
# missing data fails closed (exit 3), never a partial set of facts
( cd "$R" && bash "$S" --base HEAD --prev-tag no-such-tag >/dev/null 2>&1 ); [ $? = 3 ] && ok "unknown tag exits 3" || bad "unknown tag exits 3"
# a value with a quote must neither break nor alter any query (no DB value is put back into SQL)
sqlite3 -bail "$DB" "INSERT INTO items VALUES ('T-011','Queued','x''y) or 1=1 --','Issues','plain','UN''SET','not-started',NULL);" \
  || { echo "FAIL quote fixture could not be built"; exit 1; }
( cd "$R" && "${G[@]}" add -A && "${G[@]}" commit -qm quote )
OUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "quote value: exit 0" || bad "quote value: exit 0 (got $RC)"
has "quote severity counted" "open_severity[x'y) or 1=1 --]=1"
has "quote severity ids exact" "open_severity_ids[x'y) or 1=1 --]=T-011"
has "quote state ids exact" "open_states_ids[UN'SET/not-started]=T-011"
has "other severity unchanged" "open_severity_ids[medium]=T-002 T-003 T-010"
has "quote: open count" "items_open=6"
printf '%s\n' "$OUT" | grep -qi 'error\|parse' && bad "no sqlite error printed" || ok "no sqlite error printed"
( cd "$R" && "${G[@]}" rm -q docs/workable_items.db && "${G[@]}" commit -qm rmdb )
( cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 >/dev/null 2>&1 ); [ $? = 3 ] && ok "no tracker exits 3" || bad "no tracker exits 3"
left="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'rf_db.*' -newer "$DB" 2>/dev/null | wc -l)"
[ "$left" = 0 ] && ok "temp files removed" || bad "temp files removed ($left left)"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
