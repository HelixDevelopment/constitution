#!/usr/bin/env bash
# test_post_update_hub_gates.sh — proves post_update_hook.sh (the §11.4.32 / §11.4.164 constitution-pull seam)
# really INVOKES the hub-structure gates (and the §11.4.31 manifest gate, against the CONSUMER root) and maps their verdicts honestly (§11.4.196(F): configured is not in use).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Runs the REAL post_update_hook.sh against a throwaway constitution copy whose eleven gates are stubs that record
# that they ran and exit with a chosen code (the fourth is the §11.4.290 CM-PROVISIONAL-DONE-ANCHOR-WIRED gate, the
# fifth the §11.4.292 CM-REPRO-FIRST-ANCHOR-WIRED gate, the sixth the §11.4.293
# CM-SCOPE-AND-IMAGE-NOWORSE-ANCHOR-WIRED gate, the seventh the §11.4.294 CM-STATE-FIELDS-ANCHOR-WIRED gate and the
# eighth the §11.4.295 CM-GEO-SUBSTITUTE-ANCHOR-WIRED gate the ninth the §11.4.296 CM-GITHUB-ISSUES-SOURCE-ANCHOR-WIRED gate, and the tenth and eleventh the §11.4.297
# CM-PR-DELIVERY-ANCHOR-WIRED and CM-PR-DELIVERY-ACCOUNT-NAME-FREE gates, all eight run against the hub itself). Asserts, per case,
# that ALL ELEVEN stubs ran, that a FAIL (1) is an ERROR
# and makes the hook exit non-zero, that BLIND (2) is a WARNING, that SKIP (3) is reported as SKIP (never PASS),
# and that PASS (0) leaves the hook successful (golden-FALSE, §11.4.201(1)).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   bash tests/test_post_update_hub_gates.sh        Exit: 0 all cases hold · 1 a case failed · 2 env error.
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   Temp dir under $TMPDIR (trap-cleaned); the real repo is never touched.
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, grep. Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
hook="$here/scripts/post_update_hook.sh"
[ -r "$hook" ] || { echo "env: hook missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
bad=0
run_case() { # <label> <hub-rc> <llmctl-rc> <manifest-rc> <provisional-done-rc> <repro-first-rc> <noworse-rc> <state-fields-rc> <geo-rc> <github-issues-rc> <pr-delivery-rc> <account-name-rc> <expect-hook-nonzero:0|1> <expected-output-regex>...
  local label="$1" hrc="$2" lrc="$3" mrc="$4" prc="$5" rrc="$6" wrc="$7" src="$8" grc="$9" irc="${10}" drc="${11}" arc="${12}" nz="${13}"; shift 13
  local c="$tmp/$label/const" p="$tmp/$label/proj"; mkdir -p "$c/scripts/gates" "$p"
  cp "$hook" "$c/scripts/post_update_hook.sh"; echo '# c' >"$c/Constitution.md"
  for g in cm_hub_engine_no_ownorg_nesting:"$hrc" cm_llmctl_submodule_nonrecursive:"$lrc" cm_helix_deps_manifest_present:"$mrc" cm_provisional_done_anchor_wired:"$prc" cm_repro_first_anchor_wired:"$rrc" cm_scope_and_image_noworse_anchor_wired:"$wrc" cm_state_fields_anchor_wired:"$src" cm_geo_substitute_anchor_wired:"$grc" cm_github_issues_source_anchor_wired:"$irc" cm_pr_delivery_anchor_wired:"$drc" cm_pr_delivery_account_name_free:"$arc"; do
    printf '#!/usr/bin/env bash\necho "$*" >"%s/ran.%s"\nexit %s\n' "$tmp/$label" "${g%%:*}" "${g##*:}" >"$c/scripts/gates/${g%%:*}.sh"
  done
  git -C "$c" init -q && git -C "$c" add -A && git -C "$c" commit -q -m a && git -C "$c" commit -q --allow-empty -m b
  local out rc; out="$(cd "$p" && CONST_DIR="$c" PROJECT_ROOT="$p" bash "$c/scripts/post_update_hook.sh" 2>&1)"; rc=$?
  local ok=1
  for g in cm_hub_engine_no_ownorg_nesting cm_llmctl_submodule_nonrecursive cm_helix_deps_manifest_present cm_provisional_done_anchor_wired cm_repro_first_anchor_wired cm_scope_and_image_noworse_anchor_wired cm_state_fields_anchor_wired cm_geo_substitute_anchor_wired cm_github_issues_source_anchor_wired cm_pr_delivery_anchor_wired cm_pr_delivery_account_name_free; do
    [ -e "$tmp/$label/ran.$g" ] || { echo "BAD  $label: $g was NOT invoked"; ok=0; }
  done
  # the manifest gate must be pointed at the CONSUMER project root, not at the constitution
  if [ -e "$tmp/$label/ran.cm_helix_deps_manifest_present" ] && ! grep -q -- "--root $p" "$tmp/$label/ran.cm_helix_deps_manifest_present"; then
    echo "BAD  $label: manifest gate not given --root $p (got: $(cat "$tmp/$label/ran.cm_helix_deps_manifest_present"))"; ok=0; fi
  # the §11.4.290 gate inspects the hub's own canon, so it must be given the CONSTITUTION root, not the consumer root
  if [ -e "$tmp/$label/ran.cm_provisional_done_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_provisional_done_anchor_wired"; then
    echo "BAD  $label: provisional-done gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_provisional_done_anchor_wired"))"; ok=0; fi
  # the §11.4.292 gate also inspects the hub's own canon, mirrors, template and skills: CONSTITUTION root
  if [ -e "$tmp/$label/ran.cm_repro_first_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_repro_first_anchor_wired"; then
    echo "BAD  $label: repro-first gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_repro_first_anchor_wired"))"; ok=0; fi
  # the §11.4.293 gate inspects the hub's own canon, mirrors and skill: CONSTITUTION root
  if [ -e "$tmp/$label/ran.cm_scope_and_image_noworse_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_scope_and_image_noworse_anchor_wired"; then
    echo "BAD  $label: no-worse gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_scope_and_image_noworse_anchor_wired"))"; ok=0; fi
  # the §11.4.294 gate inspects the hub's own canon, mirrors, item template and skills: CONSTITUTION root
  if [ -e "$tmp/$label/ran.cm_state_fields_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_state_fields_anchor_wired"; then
    echo "BAD  $label: state-fields gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_state_fields_anchor_wired"))"; ok=0; fi
  # the §11.4.295 gate inspects the hub's own canon and mirrors: CONSTITUTION root
  if [ -e "$tmp/$label/ran.cm_geo_substitute_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_geo_substitute_anchor_wired"; then
    echo "BAD  $label: geo-substitute gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_geo_substitute_anchor_wired"))"; ok=0; fi
  # the §11.4.296 gate inspects the hub's own canon, mirrors and generated rule files: CONSTITUTION root
  if [ -e "$tmp/$label/ran.cm_github_issues_source_anchor_wired" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.cm_github_issues_source_anchor_wired"; then
    echo "BAD  $label: github-issues gate not given --root $c (got: $(cat "$tmp/$label/ran.cm_github_issues_source_anchor_wired"))"; ok=0; fi
  # the two §11.4.297 gates inspect the hub's own canon, mirrors and generated files (the account-name gate finds the
  # consumer configuration from there, <hub>/../config/delivery.conf): CONSTITUTION root
  for g in cm_pr_delivery_anchor_wired cm_pr_delivery_account_name_free; do
    if [ -e "$tmp/$label/ran.$g" ] && ! grep -q -- "--root $c" "$tmp/$label/ran.$g"; then
      echo "BAD  $label: $g not given --root $c (got: $(cat "$tmp/$label/ran.$g"))"; ok=0; fi
  done
  if [ "$nz" = 1 ] && [ "$rc" -eq 0 ]; then echo "BAD  $label: hook exited 0 on a gate FAIL"; ok=0; fi
  if [ "$nz" = 0 ] && [ "$rc" -ne 0 ]; then echo "BAD  $label: hook exited $rc, expected 0"; ok=0; fi
  for re in "$@"; do grep -Eq -- "$re" <<<"$out" || { echo "BAD  $label: output lacks /$re/"; ok=0; }; done
  if [ "$ok" = 1 ]; then echo "ok   $label (hook rc=$rc)"; else bad=1; echo "$out" | sed 's/^/     /' | tail -25; fi
}
run_case PASS 0 0 0 0 0 0 0 0 0 0 0 0 'CM-HUB-ENGINE-NO-OWNORG-NESTING: PASS' 'CM-LLMCTL-SUBMODULE-NONRECURSIVE: PASS' 'CM-HELIX-DEPS-MANIFEST-PRESENT: PASS' 'CM-PROVISIONAL-DONE-ANCHOR-WIRED: PASS' 'CM-REPRO-FIRST-ANCHOR-WIRED: PASS' 'CM-SCOPE-AND-IMAGE-NOWORSE-ANCHOR-WIRED: PASS' 'CM-STATE-FIELDS-ANCHOR-WIRED: PASS' 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED: PASS' 'CM-GITHUB-ISSUES-SOURCE-ANCHOR-WIRED: PASS' 'CM-PR-DELIVERY-ANCHOR-WIRED: PASS' 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE: PASS'
run_case HUB-FAIL 1 0 0 0 0 0 0 0 0 0 0 1 'CM-HUB-ENGINE-NO-OWNORG-NESTING: FAIL'
run_case LLMCTL-BLIND 0 2 0 0 0 0 0 0 0 0 0 0 'CM-LLMCTL-SUBMODULE-NONRECURSIVE: BLIND'
run_case HUB-SKIP 3 0 0 0 0 0 0 0 0 0 0 0 'CM-HUB-ENGINE-NO-OWNORG-NESTING: SKIP'
run_case MANIFEST-FAIL 0 0 1 0 0 0 0 0 0 0 0 1 'CM-HELIX-DEPS-MANIFEST-PRESENT: FAIL'
run_case MANIFEST-BLIND 0 0 2 0 0 0 0 0 0 0 0 0 'CM-HELIX-DEPS-MANIFEST-PRESENT: BLIND'
run_case PDONE-FAIL 0 0 0 1 0 0 0 0 0 0 0 1 'CM-PROVISIONAL-DONE-ANCHOR-WIRED: FAIL'
run_case PDONE-BLIND 0 0 0 2 0 0 0 0 0 0 0 0 'CM-PROVISIONAL-DONE-ANCHOR-WIRED: BLIND'
run_case PDONE-SKIP 0 0 0 3 0 0 0 0 0 0 0 0 'CM-PROVISIONAL-DONE-ANCHOR-WIRED: SKIP'
run_case REPRO-FAIL 0 0 0 0 1 0 0 0 0 0 0 1 'CM-REPRO-FIRST-ANCHOR-WIRED: FAIL'
run_case REPRO-BLIND 0 0 0 0 2 0 0 0 0 0 0 0 'CM-REPRO-FIRST-ANCHOR-WIRED: BLIND'
run_case REPRO-SKIP 0 0 0 0 3 0 0 0 0 0 0 0 'CM-REPRO-FIRST-ANCHOR-WIRED: SKIP'
run_case NOWORSE-FAIL 0 0 0 0 0 1 0 0 0 0 0 1 'CM-SCOPE-AND-IMAGE-NOWORSE-ANCHOR-WIRED: FAIL'
run_case NOWORSE-BLIND 0 0 0 0 0 2 0 0 0 0 0 0 'CM-SCOPE-AND-IMAGE-NOWORSE-ANCHOR-WIRED: BLIND'
run_case NOWORSE-SKIP 0 0 0 0 0 3 0 0 0 0 0 0 'CM-SCOPE-AND-IMAGE-NOWORSE-ANCHOR-WIRED: SKIP'
run_case STATEFIELDS-FAIL 0 0 0 0 0 0 1 0 0 0 0 1 'CM-STATE-FIELDS-ANCHOR-WIRED: FAIL'
run_case STATEFIELDS-BLIND 0 0 0 0 0 0 2 0 0 0 0 0 'CM-STATE-FIELDS-ANCHOR-WIRED: BLIND'
run_case STATEFIELDS-SKIP 0 0 0 0 0 0 3 0 0 0 0 0 'CM-STATE-FIELDS-ANCHOR-WIRED: SKIP'
run_case GEO-FAIL 0 0 0 0 0 0 0 1 0 0 0 1 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED: FAIL'
run_case GEO-BLIND 0 0 0 0 0 0 0 2 0 0 0 0 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED: BLIND'
run_case GEO-SKIP 0 0 0 0 0 0 0 3 0 0 0 0 'CM-GEO-SUBSTITUTE-ANCHOR-WIRED: SKIP'
run_case GHISSUES-FAIL 0 0 0 0 0 0 0 0 1 0 0 1 'CM-GITHUB-ISSUES-SOURCE-ANCHOR-WIRED: FAIL'
run_case GHISSUES-BLIND 0 0 0 0 0 0 0 0 2 0 0 0 'CM-GITHUB-ISSUES-SOURCE-ANCHOR-WIRED: BLIND'
run_case GHISSUES-SKIP 0 0 0 0 0 0 0 0 3 0 0 0 'CM-GITHUB-ISSUES-SOURCE-ANCHOR-WIRED: SKIP'
run_case PRDELIVERY-FAIL 0 0 0 0 0 0 0 0 0 1 0 1 'CM-PR-DELIVERY-ANCHOR-WIRED: FAIL'
run_case PRDELIVERY-BLIND 0 0 0 0 0 0 0 0 0 2 0 0 'CM-PR-DELIVERY-ANCHOR-WIRED: BLIND'
run_case PRDELIVERY-SKIP 0 0 0 0 0 0 0 0 0 3 0 0 'CM-PR-DELIVERY-ANCHOR-WIRED: SKIP'
run_case ACCTNAME-FAIL 0 0 0 0 0 0 0 0 0 0 1 1 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE: FAIL'
run_case ACCTNAME-BLIND 0 0 0 0 0 0 0 0 0 0 2 0 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE: BLIND'
run_case ACCTNAME-SKIP 0 0 0 0 0 0 0 0 0 0 3 0 'CM-PR-DELIVERY-ACCOUNT-NAME-FREE: SKIP'
[ "$bad" = 0 ] && echo "PASS — post_update_hook.sh invokes the hub gates + the manifest gate + the provisional-done, repro-first, no-worse, state-fields, geo-substitute, github-issues, pr-delivery and account-name gates and maps every verdict" || { echo "FAIL"; exit 1; }
