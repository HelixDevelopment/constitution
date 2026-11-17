#!/usr/bin/env bash
# tests/release/test_release_template_delivery_paragraph.sh — the §11.4.297 paragraph of the v73.4 entry
# template must agree with config/delivery.conf (CON-512): when that file is tracked, the template may not say
# it does not exist, and it must quote the declared mode. Reads the real files; the template path and the
# config path can be overridden (RTD_TEMPLATE, RTD_CONF) so the paired mutants run on copies.
# Evidence class: gate-logic (PROVISIONAL).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
T="${RTD_TEMPLATE:-$ROOT/docs/release/helixconstitution-v73.4_entry.template.md}"
C="${RTD_CONF:-$ROOT/config/delivery.conf}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
[ -s "$C" ] && ok "the delivery configuration is present and non-empty (control needle)" || bad "the delivery configuration is present and non-empty"
MODE="$(sed -n 's/^mode=\([A-Za-z]*\)[[:space:]]*$/\1/p' "$C" | head -n 1)"
[ -n "$MODE" ] && ok "the declared mode is read from the configuration ($MODE)" || bad "the declared mode could not be read"
P="$(grep -m1 '^§11.4.297:' "$T")"
[ -n "$P" ] && ok "the template has a §11.4.297 paragraph (control needle)" || bad "the template has a §11.4.297 paragraph"
if [ -s "$C" ]; then
  printf '%s' "$P" | grep -qF 'no `config/delivery.conf`' && bad "the paragraph does not claim config/delivery.conf is absent" || ok "the paragraph does not claim config/delivery.conf is absent"
  printf '%s' "$P" | grep -qF 'no tracked file of this repository declares pull-request delivery' && bad "the paragraph does not claim that no delivery is declared" || ok "the paragraph does not claim that no delivery is declared"
  printf '%s' "$P" | grep -qF "mode=$MODE" && ok "the paragraph quotes the declared mode (mode=$MODE)" || bad "the paragraph quotes the declared mode (mode=$MODE)"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
