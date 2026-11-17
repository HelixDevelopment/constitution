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
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
