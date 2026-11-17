#!/usr/bin/env bash
# tests/release/test_release_template_delivery_paragraph_mutants.sh — paired mutations (§1.1) of the CON-512
# template paragraph test: each mutant must make test_release_template_delivery_paragraph.sh FAIL (control: the
# real files pass). Evidence class: gate-logic (PROVISIONAL).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/rtd_mut.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
T="$ROOT/docs/release/helixconstitution-v73.4_entry.template.md"; C="$ROOT/config/delivery.conf"
t(){ RTD_TEMPLATE="$1" RTD_CONF="$2" bash "$HERE/test_release_template_delivery_paragraph.sh" >"$W/out" 2>&1; }
t "$T" "$C" && ok "control: the real template and configuration pass" || bad "control: the real template and configuration pass"
# M1: the stale paragraph (the pre-fix text of line 66 at 60177435)
sed 's/^§11.4.297: .*/§11.4.297: no tracked file of this repository declares pull-request delivery (no `config\/delivery.conf`), so §11.4.288 applies as written./' "$T" >"$W/t1.md"
t "$W/t1.md" "$C" && bad "M1 (stale paragraph) is caught" || ok "M1 (stale paragraph) is caught"
# M2: the configuration changes its mode; the paragraph still quotes mode=pr
sed 's/^mode=pr/mode=direct/' "$C" >"$W/c2.conf"
t "$T" "$W/c2.conf" && bad "M2 (mode changed in the configuration) is caught" || ok "M2 (mode changed in the configuration) is caught"
# M3: the paragraph is removed
grep -v '^§11.4.297:' "$T" >"$W/t3.md"
t "$W/t3.md" "$C" && bad "M3 (paragraph removed) is caught" || ok "M3 (paragraph removed) is caught"
# M4: an empty configuration (the control needle must fail, never a silent pass)
: >"$W/c4.conf"
t "$T" "$W/c4.conf" && bad "M4 (empty configuration) is caught" || ok "M4 (empty configuration) is caught"
# review of e5efbf77 (F6/F7): the reviewer's T1 and T2, and four mutants of the new clauses. Each edits the §11.4.297
# paragraph of a copy with a python replace that must hit exactly once (a miss is a FAIL, never a silent pass).
mt(){ python3 -I - "$T" "$W/$1.md" "$2" "$3" <<'MTPY' || return 1
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit("text found %d times" % s.count(a))
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
MTPY
}
chk(){ if ! mt "$1" "$2" "$3"; then bad "$1 could not be applied"; elif t "$W/$1.md" "$C"; then bad "$1 ($4) is caught"; else ok "$1 ($4) is caught: $(grep '^FAIL' "$W/out" | tr '\n' '|')"; fi; }
chk T1 '(a PROVISIONAL declaration of 2026-11-16, decision `OPD-2026-11-16-PR-DELIVERY`: its own header says no delivery tool reads it yet and nothing is ENFORCED, §11.4.297(G))' '(ENFORCED and verified)' "reviewer T1: status claimed ENFORCED and verified"
chk T2 '`config/delivery.conf` is tracked on `main` and declares `mode=pr`' 'this repository declares no pull-request delivery; `mode=pr` is a draft' "reviewer T2: declaration denied in other words"
chk M5 "this release's own landing follows" "this release's own landing (decision 8 of the 2026-11-11 relayed decisions kept delivery direct) follows" "the superseded decision 8 cited again"
chk M6 'decision `OPD-2026-11-16-PR-DELIVERY`: ' '' "the declaration's decision id dropped"
chk M7 'and pull-request mode applies after the release.' 'and pull-request mode applies after the release; whether that is right is the operator'"'"'s open question.' "the answered question called open"
chk M8 'with no pull requests,' 'with no pull requests (verified),' "the paragraph claims verified"
# round 3 (review of f4c6e8ab, N2): the reviewer's TX mutants. The test read keywords, so a wording that keeps the
# words but reverses or inflates the statement passed; the test now pins the exact sentences and the record's cells.
chk TX1 '(a PROVISIONAL declaration of' '(a binding declaration of' "reviewer TX1: the declaration loses its PROVISIONAL status"
chk TX4 ', PROVISIONAL, wording UNCONFIRMED)' ', PROVISIONAL)' "reviewer TX4: the UNCONFIRMED wording label dropped"
chk TX5 'and pull-request mode applies after the release.' 'and pull-request mode applies to the release commit itself.' "reviewer TX5: pull-request mode applied to the release commit"
chk TX6 'the rest of this release queue lands by fast-forward push with no pull requests' 'the release lands through a pull request; fast-forward with no pull requests was rejected' "reviewer TX6: the landing statement reversed"
chk TX7 ', PROVISIONAL, wording UNCONFIRMED)' ', PROVISIONAL, wording UNCONFIRMED, operator-confirmed)' "reviewer TX7: the record called operator-confirmed"
# record mutants: a copy of the cited record under a temporary root (RTD_ROOT), edited with an exact replace
REC=docs/operator_decisions/2026-11-16_release_landing.md
rmt(){ mkdir -p "$W/root_$1/docs/operator_decisions"; python3 -I - "$ROOT/$REC" "$W/root_$1/$REC" "$2" "$3" <<'MTPY' || return 1
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit("text found %d times" % s.count(a))
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
MTPY
}
rchk(){ if ! rmt "$1" "$2" "$3"; then bad "$1 could not be applied"
  elif RTD_ROOT="$W/root_$1" RTD_TEMPLATE="$T" RTD_CONF="$C" bash "$HERE/test_release_template_delivery_paragraph.sh" >"$W/out" 2>&1; then bad "$1 ($4) is caught"
  else ok "$1 ($4) is caught: $(grep '^FAIL' "$W/out" | tr '\n' '|')"; fi; }
if rmt RC0 '| Revision | 1 |' '| Revision | 1 |' && RTD_ROOT="$W/root_RC0" RTD_TEMPLATE="$T" RTD_CONF="$C" bash "$HERE/test_release_template_delivery_paragraph.sh" >"$W/out" 2>&1; then
  ok "control: an unchanged copy of the record under a temporary root passes"; else bad "control: an unchanged copy of the record under a temporary root passes"; fi
rchk TX2 '| Status | PROVISIONAL |' '| Status | VERIFIED (final) |' "reviewer TX2: the record's Status cell says VERIFIED"
rchk RX1 '| Exact wording | UNCONFIRMED:' '| Exact wording | confirmed by the operator:' "the record's wording cell no longer says UNCONFIRMED"
rchk RX2 '| Status | PROVISIONAL |' '| Status | final; PROVISIONAL was the draft label |' "the Status cell holds the word PROVISIONAL but is not PROVISIONAL"
# M9: the cited decision record is missing from the tree (RTD_ROOT names an empty tree)
mkdir -p "$W/emptyroot"
RTD_ROOT="$W/emptyroot" RTD_TEMPLATE="$T" RTD_CONF="$C" bash "$HERE/test_release_template_delivery_paragraph.sh" >"$W/out" 2>&1 && bad "M9 (cited decision record missing) is caught" || ok "M9 (cited decision record missing) is caught"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
