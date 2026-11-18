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
# the 2026-11-16 answer (fast-forward, no pull requests) is kept as history; the landing that happened is pull requests
# merged with merge commits, and the release commit lands through its own pull request (v73.4 cut review, 2026-11-18)
printf '%s' "$P7" | grep -qiE 'fast-forward push with no pull requests' && printf '%s' "$P7" | grep -qF 'through its own pull request, merged with a merge commit' && ok "the paragraph states the 2026-11-16 answer and the landing that happened (release commit through its own pull request)" || bad "the paragraph states the 2026-11-16 answer and the landing that happened (release commit through its own pull request)"
# round 3 (review of f4c6e8ab, N2): the checks above read words, so a wording that keeps the words but reverses the
# landing or drops a status passed (reviewer TX1, TX4-TX7). The two statements are now pinned EXACTLY, and the record
# is read by its table cells, not by any occurrence of a word (TX2).
DECL='(a PROVISIONAL declaration of 2026-11-16, decision `OPD-2026-11-16-PR-DELIVERY`: its own header says no delivery tool reads it yet and nothing is ENFORCED, §11.4.297(G))'
LAND="the operator's relayed answer of 2026-11-16 (\`docs/operator_decisions/2026-11-16_release_landing.md\`, PROVISIONAL, wording UNCONFIRMED) had the rest of this release queue land by fast-forward push with no pull requests; the later relayed answers of 2026-11-17 (an agent review comment with GO for the exact head is the pull-request gate; merge every open pull request with a merge commit; recorded in the waiver record named above) replaced that in practice, and the queue landed by fast-forward push up to \`33b33d26\` and then through pull requests #14 to #29 merged with merge commits. The release commit itself lands on \`main\` through its own pull request, merged with a merge commit after an independent review GO comment that names the reviewed head; \`scripts/release/tag_and_release.sh\` then pushes that merge commit fast-forward, together with the tag, to every upstream (in the pull-request repository HelixDevelopment/constitution, where \`main\` already holds the merge commit, only the tag moves; every other upstream, the vasic-digital GitHub mirror included, gets both)."
printf '%s' "$P7" | grep -qF -- "$DECL" && ok "the declaration's status parenthesis is exactly as pinned (PROVISIONAL, nothing ENFORCED)" || bad "the declaration's status parenthesis is exactly as pinned"
printf '%s' "$P7" | grep -qF -- "$LAND" && ok "the landing sentence is exactly as pinned (2026-11-16 answer as history, pull-request landing, wording UNCONFIRMED)" || bad "the landing sentence is exactly as pinned"
printf '%s' "$P7" | grep -qiwE 'confirmed|binding|final' && bad "the paragraph calls nothing confirmed, binding or final (UNCONFIRMED is another word)" || ok "the paragraph calls nothing confirmed, binding or final (UNCONFIRMED is another word)"
REC="$(printf '%s' "$P7" | grep -oE 'docs/operator_decisions/[A-Za-z0-9._-]+\.md' | head -n 1)"
# cell NAME FILE: the text of the table row "| NAME | text |" (exactly one such row, else empty)
cell(){ awk -v n="$1" -F' [|] ' 'index($0, "| " n " | ") == 1 { c++; v = $2; sub(/ [|]$/, "", v) } END { if (c == 1) print v }' "$2" 2>/dev/null; }
if [ -n "$REC" ]; then
  RF="${RTD_ROOT:-$ROOT}/$REC"
  [ -f "$RF" ] && ok "the cited decision record $REC exists" || bad "the cited decision record $REC exists"
  [ "$(cell Revision "$RF")" = 1 ] && ok "the record's Revision cell is read (control needle: 1)" || bad "the record's Revision cell could not be read (got '$(cell Revision "$RF")')"
  [ "$(cell Status "$RF")" = PROVISIONAL ] && ok "the record's Status cell is exactly PROVISIONAL" || bad "the record's Status cell is exactly PROVISIONAL (got '$(cell Status "$RF")')"
  case "$(cell 'Exact wording' "$RF")" in "UNCONFIRMED: "*) ok "the record's Exact wording cell starts with UNCONFIRMED:" ;; *) bad "the record's Exact wording cell starts with UNCONFIRMED: (got '$(cell 'Exact wording' "$RF")')" ;; esac
  grep -qiwE 'confirmed|verified' "$RF" 2>/dev/null && bad "the record calls nothing confirmed or verified" || ok "the record calls nothing confirmed or verified"
else
  bad "the paragraph names the decision record of the landing answer (docs/operator_decisions/...)"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
