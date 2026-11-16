#!/bin/sh
# Purpose: CON-092 / CON-093 RED test for fc_consumer_section and fc_consumer_exit in
#          lib/consumer_section.sh: a consumer-data section is skipped ALONE (one SKIP-SECTION line,
#          reason=topology_unsupported) while the canon-runnable sections keep running; the test then
#          exits 77 when it passed but skipped, keeps its own non-zero status when it failed, and exits 0
#          only when nothing was skipped. Runs under sh (dash on Debian-family hosts) and bash.
# Usage:   sh test_consumer_section_con092_red.sh   Exit 0 = all assertions hold, 1 = a failure.
# Oracle:  SPECIFIED (section 11.4.245) by the helper's own header contract; fixtures are built under a
#          mktemp root laid out as <consumer>/<canon>/scripts/fastcycle/tests/<probe>.sh.
# shellcheck disable=SC2015 # the `<cond> && echo ok || { echo NOT ok; failx; }` assertion idiom
here=$(cd "$(dirname "$0")" && pwd)
lib=${FC_CONSUMER_LIB_UNDER_TEST:-$here/lib/consumer_section.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }
[ -f "$lib" ] || { echo "NOT ok helper library missing: $lib"; exit 1; }
canon="$tmp/consumer/any_canon_name"; tdir="$canon/scripts/fastcycle/tests"
mkdir -p "$tdir/lib" "$tmp/consumer/present_dir"; cp "$lib" "$tdir/lib/consumer_section.sh"
: >"$tmp/consumer/present_file"
# probe <name> <verdict_rc> <path for section B>: section A (canon) always runs and writes a marker;
# section B is consumer-data gated; then the probe ends with fc_consumer_exit <verdict_rc>.
probe() {
  cat >"$tdir/$1.sh" <<EOP
#!/bin/sh
. "\$(dirname "\$0")/lib/consumer_section.sh"
echo "SECTION-A ran"
if fc_consumer_section "section B" $3; then echo "SECTION-B ran"; fi
echo "SECTION-C ran"
fc_consumer_exit $2
EOP
}
runp() { for sh_ in sh bash; do "$sh_" "$tdir/$1.sh" >"$tmp/$1.$sh_.out" 2>&1; echo "$sh_:$?"; done | tr '\n' ' '; }
# C1 consumer path absent, verdict 0: section B skipped alone, A and C ran, exit 77 under both shells.
probe c1 0 "docs/absent_db.db"; r=$(runp c1)
[ "$r" = "sh:77 bash:77 " ] && echo "ok C1 absent-path-verdict0-exits-77 ($r)" || { echo "NOT ok C1 absent-path-verdict0-exits-77 ($r)"; failx; }
grep -qx "SECTION-A ran" "$tmp/c1.sh.out" && grep -qx "SECTION-C ran" "$tmp/c1.sh.out" && ! grep -q "SECTION-B ran" "$tmp/c1.sh.out" && echo "ok C1 only-section-B-skipped" || { echo "NOT ok C1 only-section-B-skipped"; failx; }
grep -q "^SKIP-SECTION: section B: consumer-project files absent under $tmp/consumer: docs/absent_db.db reason=topology_unsupported\$" "$tmp/c1.sh.out" && echo "ok C1 skip-section-line-names-path-and-root" || { echo "NOT ok C1 skip-section-line-names-path-and-root"; cat "$tmp/c1.sh.out"; failx; }
tail -n 1 "$tmp/c1.sh.out" | grep -q "reason=topology_unsupported\$" && echo "ok C1 last-line-reason" || { echo "NOT ok C1 last-line-reason"; failx; }
# C2 consumer path present: section B runs, exit 0, no SKIP line.
probe c2 0 "present_dir present_file"; r=$(runp c2)
[ "$r" = "sh:0 bash:0 " ] && grep -qx "SECTION-B ran" "$tmp/c2.sh.out" && ! grep -q "SKIP" "$tmp/c2.sh.out" && echo "ok C2 present-runs-exit-0 ($r)" || { echo "NOT ok C2 present-runs-exit-0 ($r)"; failx; }
# C3 absent path but the test FAILED (rc 1): exit 1, never 77 (a FAIL is never turned into a SKIP).
probe c3 1 "docs/absent_db.db"; r=$(runp c3)
[ "$r" = "sh:1 bash:1 " ] && echo "ok C3 fail-beats-skip ($r)" || { echo "NOT ok C3 fail-beats-skip ($r)"; failx; }
# C4 other non-zero verdicts are passed through exactly.
probe c4 4 "present_file"; r=$(runp c4)
[ "$r" = "sh:4 bash:4 " ] && echo "ok C4 rc-passthrough ($r)" || { echo "NOT ok C4 rc-passthrough ($r)"; failx; }
# C5 one of two paths absent: still a skip (all must exist), the absent one is named, the present one not.
probe c5 0 "present_file docs/gone"; r=$(runp c5)
[ "$r" = "sh:77 bash:77 " ] && grep -q ":* docs/gone reason=" "$tmp/c5.sh.out" && ! grep -q "present_file reason" "$tmp/c5.sh.out" && echo "ok C5 partial-absence-skips ($r)" || { echo "NOT ok C5 partial-absence-skips ($r)"; failx; }
# C6 absolute path honoured as given (present absolute => runs; absent absolute => skip).
probe c6 0 "$tmp/consumer/present_file"; r=$(runp c6)
[ "$r" = "sh:0 bash:0 " ] && echo "ok C6 absolute-present ($r)" || { echo "NOT ok C6 absolute-present ($r)"; failx; }
probe c7 0 "$tmp/nowhere/x"; r=$(runp c7)
[ "$r" = "sh:77 bash:77 " ] && echo "ok C7 absolute-absent ($r)" || { echo "NOT ok C7 absolute-absent ($r)"; failx; }
# C8 two skipped sections are counted (the count appears in the final line).
cat >"$tdir/c8.sh" <<'EOP'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_section.sh"
fc_consumer_section "s1" docs/a || :
fc_consumer_section "s2" docs/b || :
fc_consumer_exit 0
EOP
sh "$tdir/c8.sh" >"$tmp/c8.out" 2>&1; rc=$?
[ "$rc" -eq 77 ] && tail -n 1 "$tmp/c8.out" | grep -q "^SKIP: 2 consumer-data section(s) skipped" && echo "ok C8 count-two" || { echo "NOT ok C8 count-two rc=$rc"; failx; }
# C9 a non-numeric verdict is a usage error (exit 2), never a PASS.
probe c9 abc "present_file"; sh "$tdir/c9.sh" >"$tmp/c9.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "ok C9 bad-verdict-usage-2" || { echo "NOT ok C9 bad-verdict-usage-2 rc=$rc"; failx; }
[ "$fail" -eq 0 ] && { echo "test_consumer_section_con092_red: all ok"; exit 0; }
echo "test_consumer_section_con092_red: FAILED"; exit 1
