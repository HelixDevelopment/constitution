#!/usr/bin/env bash
# tests/release/test_release_template_delivery_paragraph.sh — the §11.4.297 paragraph of the v73.4 entry
# template must agree with config/delivery.conf (CON-512): when that file is tracked, the template may not say
# it does not exist, and it must quote the declared mode, keep its PROVISIONAL / nothing-is-ENFORCED status and cite
# the 2026-11-16 decisions and the tracked record of the landing answer (review of e5efbf77, F6/F7). Reads the real
# files; the template, config and record root can be overridden (RTD_TEMPLATE, RTD_CONF, RTD_ROOT) for the mutants.
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
# the §11.4.297 part of the paragraph (the §11.4.298 sentence after it says "declares no product", which is right)
P7="${P%% §11.4.298:*}"
[ -n "$P7" ] && [ "$P7" != "$P" ] && ok "the §11.4.297 part is split from the §11.4.298 sentence (control needle)" || bad "the §11.4.297 part could not be split from the §11.4.298 sentence"
if [ -s "$C" ]; then
  printf '%s' "$P7" | grep -qF 'no `config/delivery.conf`' && bad "the paragraph does not claim config/delivery.conf is absent" || ok "the paragraph does not claim config/delivery.conf is absent"
  printf '%s' "$P7" | grep -qF 'no tracked file of this repository declares pull-request delivery' && bad "the paragraph does not claim that no delivery is declared" || ok "the paragraph does not claim that no delivery is declared"
  printf '%s' "$P7" | grep -qF "mode=$MODE" && ok "the paragraph quotes the declared mode (mode=$MODE)" || bad "the paragraph quotes the declared mode (mode=$MODE)"
  # F6 (review of e5efbf77): pin the positive statement and its PROVISIONAL / not-ENFORCED status, refuse any other
  # wording that denies the declaration or claims more than it is
  printf '%s' "$P7" | grep -qF "\`config/delivery.conf\` is tracked on \`main\` and declares \`mode=$MODE\`" && ok "the paragraph states that the tracked file declares mode=$MODE" || bad "the paragraph states that the tracked file declares mode=$MODE"
  printf '%s' "$P7" | grep -qw 'PROVISIONAL' && ok "the paragraph keeps the PROVISIONAL status" || bad "the paragraph keeps the PROVISIONAL status"
  printf '%s' "$P7" | grep -qF 'nothing is ENFORCED' && ok "the paragraph keeps the nothing-is-ENFORCED clause" || bad "the paragraph keeps the nothing-is-ENFORCED clause"
  rest="${P7//nothing is ENFORCED/}"
  printf '%s' "$rest" | grep -qi 'enforced' && bad "the paragraph claims nothing ENFORCED beyond the pinned clause" || ok "the paragraph claims nothing ENFORCED beyond the pinned clause"
  printf '%s' "$P7" | grep -qiw 'verified' && bad "the paragraph does not call the declaration verified" || ok "the paragraph does not call the declaration verified"
  printf '%s' "$P7" | grep -qiE 'declares no|does not declare|no pull-request delivery|no delivery is declared|is a draft|not tracked|untracked' && bad "the paragraph does not deny the declaration in other words" || ok "the paragraph does not deny the declaration in other words"
fi
# F7: the landing sentence cites the 2026-11-16 decisions, never the superseded decision 8 of 2026-11-11, and does not
# call an answered question open; a decision record it cites must be a file of this tree
printf '%s' "$P7" | grep -qF 'OPD-2026-11-16-PR-DELIVERY' && ok "the paragraph cites the declaration's decision id OPD-2026-11-16-PR-DELIVERY" || bad "the paragraph cites the declaration's decision id OPD-2026-11-16-PR-DELIVERY"
printf '%s' "$P7" | grep -qiE 'decision 8|2026-11-11' && bad "the paragraph does not cite the superseded 2026-11-11 decision 8" || ok "the paragraph does not cite the superseded 2026-11-11 decision 8"
printf '%s' "$P7" | grep -qi 'open question' && bad "the paragraph does not call the answered landing question open" || ok "the paragraph does not call the answered landing question open"
printf '%s' "$P7" | grep -qiE 'fast-forward' && printf '%s' "$P7" | grep -qiE 'no pull requests' && ok "the paragraph states the answered landing path (fast-forward, no pull requests)" || bad "the paragraph states the answered landing path (fast-forward, no pull requests)"
REC="$(printf '%s' "$P7" | grep -oE 'docs/operator_decisions/[A-Za-z0-9._-]+\.md' | head -n 1)"
if [ -n "$REC" ]; then
  [ -f "${RTD_ROOT:-$ROOT}/$REC" ] && ok "the cited decision record $REC exists" || bad "the cited decision record $REC exists"
  grep -qw 'PROVISIONAL' "${RTD_ROOT:-$ROOT}/$REC" 2>/dev/null && ok "the cited decision record is marked PROVISIONAL" || bad "the cited decision record is marked PROVISIONAL"
else
  bad "the paragraph names the decision record of the landing answer (docs/operator_decisions/...)"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
