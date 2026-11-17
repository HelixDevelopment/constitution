#!/usr/bin/env bash
# tests/release/test_derive_release_facts_provisional.sh — hermetic test of two derivations of
# scripts/release/derive_release_facts.sh (rel1: a quoted verification marker is not a verification line;
# rel2: --retest-item flags an item that is not a recorded retest). Real git and real sqlite3; the oracle
# is a fixture tracker with expected values written by hand. Evidence class: gate-logic (PROVISIONAL).
# DRF_SCRIPT overrides the script under test (a copy of the scripts/release directory, for the mutants).
set -u
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
INSERT INTO items VALUES ('T-101','Fixed (→ Fixed.md)','Medium','Fixed','retest recorded','UNSET','UNSET','2001-01-01');
SQL
( cd "$R" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a \
  && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm b )
run(){ ( cd "$R" && timeout 120 bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 "$@" 2>&1 ); }
OUT="$(run)"; RC=$?
has(){ if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1 (missing line: $2)"; fi; }
[ "$RC" = 0 ] && ok "rel1 exit 0" || bad "rel1 exit 0 (got $RC)"
has "rel1 positive control: real lines counted, quoted and fenced markers not" "provisional_ids=T-001 T-002 T-003 T-006"
has "rel1 overdue: undated and past-dated, not future" "overdue_ids=T-001 T-003 T-006"
has "rel1 count line" "count_line=0 verified + 4 provisional (3 overdue)"
printf '%s\n' "$OUT" | grep -E '^(provisional_ids|overdue_ids)=' | grep -q 'T-004' && bad "rel1 the prose quotation T-004 is not provisional" || ok "rel1 the prose quotation T-004 is not provisional"
printf '%s\n' "$OUT" | grep -E '^(provisional_ids|overdue_ids)=' | grep -q 'T-005' && bad "rel1 the fenced quotation T-005 is not provisional" || ok "rel1 the fenced quotation T-005 is not provisional"
# rel2: --retest-item
OUT="$(run --retest-item T-100)"; RC=$?
[ "$RC" = 0 ] && ok "rel2 a Queued retest item: facts printed (rc 0)" || bad "rel2 a Queued retest item: rc $RC"
has "rel2 id" "retest_item_id=T-100"
has "rel2 status" "retest_item_status=Queued (Issues)"
has "rel2 not evidence" "retest_item_evidence=no"
printf '%s\n' "$OUT" | grep -q '^retest_item_flag=NOT-EVIDENCE' && ok "rel2 flag line names NOT-EVIDENCE" || bad "rel2 flag line names NOT-EVIDENCE"
OUT="$(run --retest-item T-101)"; RC=$?
has "rel2 positive control: a Fixed item is evidence" "retest_item_evidence=yes"
printf '%s\n' "$OUT" | grep -q '^retest_item_flag=' && bad "rel2 no flag for a Fixed item" || ok "rel2 no flag for a Fixed item"
OUT="$(run --retest-item T-100 --require-retest-evidence)"; RC=$?
[ "$RC" = 3 ] && ok "rel2 --require-retest-evidence refuses a Queued item (rc 3)" || bad "rel2 --require-retest-evidence refuses a Queued item (rc $RC)"
[ -z "$(printf '%s' "$OUT" | grep '^base=')" ] && ok "rel2 a refusal prints no facts" || bad "rel2 a refusal prints no facts"
OUT="$(run --retest-item T-101 --require-retest-evidence)"; RC=$?
[ "$RC" = 0 ] && ok "rel2 --require-retest-evidence accepts a Fixed item" || bad "rel2 --require-retest-evidence accepts a Fixed item (rc $RC)"
OUT="$(run --retest-item NOPE-1)"; RC=$?
[ "$RC" = 3 ] && ok "rel2 an unknown item id is refused (rc 3), never cited" || bad "rel2 an unknown item id is refused (rc $RC)"
OUT="$(run --retest-item 'a b')"; RC=$?
[ "$RC" = 2 ] && ok "rel2 a malformed item id is a usage error (rc 2)" || bad "rel2 a malformed item id (rc $RC)"
OUT="$(run)"
printf '%s\n' "$OUT" | grep -q '^retest_item' && bad "rel2 without the option no retest_item fact is printed" || ok "rel2 without the option no retest_item fact is printed"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
