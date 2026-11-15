#!/usr/bin/env bash
# test_github_actions_inventory_disable.sh -- hermetic tests for
# scripts/security/github_actions_inventory_disable.sh.
#
# Purpose: drive the REAL script against a fake `gh` (tests/security/fixtures/
# bin/gh + fake_gh.py) whose answers come from a JSON state file: selection
# classes (archived, fork, dynamic Pages, Pages deployed by a custom workflow,
# no workflow, already disabled), failed GETs that must become ERR rows and a
# non-zero exit (never a silently shrunken scope), apply gating, the pinned
# repo list (--repos-file) and its confirm token, scope differences that refuse
# apply, PUT failures and read-backs that must be enabled=false.
# Gate-logic tests only (§11.4.289): nothing here talks to GitHub.
#
# Usage: bash tests/security/test_github_actions_inventory_disable.sh
#        GHA_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        SEC_TEST_FAILFAST=1 stops at the first failing case (used by the mutation test)
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
# shellcheck disable=SC2034  # RC and EXPECT_* are read inside the eval'd check strings
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${GHA_SCRIPT:-$here/scripts/security/github_actions_inventory_disable.sh}"
FIX="$here/tests/security/fixtures"
for t in jq python3 sha256sum; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
export SEC_TEST_LOG="$tmp/log"; mkdir -p "$SEC_TEST_LOG"
export FAKE_GH_STATE="$tmp/state.json"
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
check(){ if eval "$2"; then ok "$1"; else nok "$1"; sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -40; fi; }

# mkstate SPEC... -> writes $FAKE_GH_STATE. SPEC = org/repo:flags, flags from
#   wf (has .github workflow) dynpages (dynamic/pages workflow) pages=<build_type> (GET /pages 200)
#   arch fork off (Actions disabled) permfail wffail pagesfail putfail noop (PUT does not change state)
#   wfmany (the workflows answer says total_count 150 but lists fewer: an unread page)
#   orgfail:<org> (org listing fails)
mkstate(){ python3 -I - "$FAKE_GH_STATE" "$@" <<'PY'
import json, sys
out, specs = sys.argv[1], sys.argv[2:]
st, orgs, noop = {}, {}, []
for sp in specs:
    if sp.startswith("orgfail:"):
        st["GET /orgs/%s/repos?per_page=100&type=all" % sp[8:]] = [1, 500]; continue
    repo, _, fl = sp.partition(":"); fl = fl.split(",") if fl else []
    org = repo.split("/")[0]
    orgs.setdefault(org, []).append({"full_name": repo, "visibility": "public", "archived": "arch" in fl, "fork": "fork" in fl})
    wfs = []
    if "wf" in fl: wfs.append({"path": ".github/workflows/ci.yml", "state": "active"})
    if "dynpages" in fl: wfs.append({"path": "dynamic/pages/pages-build-deployment", "state": "active"})
    wj = {"workflows": wfs}
    if "wfmany" in fl: wj["total_count"] = 150
    st["GET /repos/%s/actions/workflows?per_page=100" % repo] = [1, 500] if "wffail" in fl else [0, wj]
    st["GET /repos/%s/actions/permissions" % repo] = [1, 500] if "permfail" in fl else [0, {"enabled": "off" not in fl, "allowed_actions": "all"}]
    bt = [f[6:] for f in fl if f.startswith("pages=")]
    if bt: st["GET /repos/%s/pages" % repo] = [0, {"build_type": bt[0], "status": "built"}]
    if "pagesfail" in fl: st["GET /repos/%s/pages" % repo] = [1, 500]
    st["GET /repos/%s/actions/runs?per_page=1" % repo] = [0, {"workflow_runs": []}]
    st["PUT /repos/%s/actions/permissions" % repo] = [1, 403] if "putfail" in fl else [0, {}]
    if "noop" in fl: noop.append(repo)
for o, rs in orgs.items():
    k = "GET /orgs/%s/repos?per_page=100&type=all" % o
    if k not in st: st[k] = [0, rs]
st["_noop_put"] = noop
json.dump(st, open(out, "w"))
PY
}
declare -a RUN_ENV=()
run(){
  : > "$SEC_TEST_LOG/gh_calls.log"; : > "$SEC_TEST_LOG/gh_argv.log"; : > "$SEC_TEST_LOG/gh_env.log"
  env PATH="$FIX/bin:$PATH" ${RUN_ENV[@]+"${RUN_ENV[@]}"} bash "$SCRIPT" "$@" > "$tmp/out" 2> "$tmp/err"; RC=$?
}
sel(){ awk -F'\t' -v r="$1" '$1==r{print $NF}' "$tmp/out"; }
col(){ awk -F'\t' -v r="$1" -v c="$2" '$1==r{print $c}' "$tmp/out"; }
nput(){ grep -c '^PUT ' "$SEC_TEST_LOG/gh_calls.log" || true; }
tok(){ grep -v '^#' "$1" | sed '/^$/d' | LC_ALL=C sort -u | sha256sum | cut -c1-12; }

# ---- selection classes and failure rows --------------------------------------------------------
mkstate T/ci:wf T/arch:wf,arch T/forkci:wf,fork T/pagesdyn:wf,dynpages,pages=legacy T/custompages:wf,pages=workflow \
        T/noci T/off:wf,off T/permfail:wf,permfail T/wffail:wffail T/pgfail:wf,pagesfail
run list --org T
check "workflow repo selected" '[ "$(sel T/ci)" = yes ]'
check "archived repo not selected" '[ "$(sel T/arch)" = no ]'
check "fork with a workflow selected" '[ "$(sel T/forkci)" = yes ]'
check "dynamic Pages repo excluded" '[ "$(sel T/pagesdyn)" = excluded-pages ]'
check "Pages deployed by a custom workflow (GET /pages build_type workflow) excluded" '[ "$(sel T/custompages)" = excluded-pages ] && [ "$(col T/custompages 7)" = workflow ]'
check "repo without workflows not selected" '[ "$(sel T/noci)" = no ]'
check "repo with Actions already disabled not selected" '[ "$(sel T/off)" = no ]'
check "permissions GET failure -> ERR row (scope never silently shrinks)" '[ "$(sel T/permfail)" = ERR ]'
check "workflows GET failure -> ERR row" '[ "$(sel T/wffail)" = ERR ]'
check "Pages GET failure (not 404) -> ERR row" '[ "$(sel T/pgfail)" = ERR ]'
check "every row has 11 columns" '[ "$(awk -F"\t" "NF!=11" "$tmp/out" | wc -l)" = 0 ]'
check "ERR rows -> exit 1" '[ $RC -eq 1 ]'
mkstate T/ci:wf T/noci
run list --org T
check "clean org -> exit 0" '[ $RC -eq 0 ] && [ "$(sel T/ci)" = yes ]'
mkstate orgfail:T U/ci:wf
run list --org T --org U
check "org listing failure -> ERR row, exit 1, other org still listed" '[ $RC -eq 1 ] && [ "$(sel "T/*")" = ERR ] && [ "$(sel U/ci)" = yes ]'
mkstate T/ci:wf T/noci
run list --org T --include-pages --select enabled
check "--select enabled selects every enabled non-archived repo" '[ "$(sel T/noci)" = yes ]'
mkstate T/ci:wf T/many:wf,wfmany
run list --org T
check "workflows list with an unread page (total_count > listed) -> ERR row, exit 1" '[ "$(sel T/many)" = ERR ] && [ $RC -eq 1 ]'
RUN_ENV=(GH_ACTIONS_APPLY=yes); run --org T --apply-confirm x
check "no mode given -> list (read-only): exit 0, rows printed, no PUT even with GH_ACTIONS_APPLY=yes" '[ "$(nput)" = 0 ] && [ "$(sel T/ci)" = yes ] && ! grep -q REFUSED "$tmp/err"'
RUN_ENV=()

# ---- usage --------------------------------------------------------------------------------------
# The pinned scope is the committed allowlist (operator decision 2026-11-12: these 9, no others).
ALW="$here/scripts/security/actions_disable_allowlist.txt"
mapfile -t AL < <(grep -v '^#' "$ALW" | sed '/^$/d' | sort -u)
TOK=$(tok "$ALW")
allst(){ local r s=(); for r in "${AL[@]}"; do s+=("$r:wf"); done; mkstate "${s[@]}" "$@"; }
run list --org T --repos-file "$ALW"
check "--org with --repos-file -> 2" '[ $RC -eq 2 ]'
run list --bogus
check "unknown argument -> 2" '[ $RC -eq 2 ]'
printf 'not a repo\n' > "$tmp/badpin"; run plan --repos-file "$tmp/badpin"
check "bad repos-file line -> 2" '[ $RC -eq 2 ]'

# ---- apply gating ---------------------------------------------------------------------------------
allst
run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "apply without GH_ACTIONS_APPLY -> 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ]'
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --org T --apply-confirm T
check "apply without --repos-file -> 3, no PUT, refused for the missing pin" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ] && grep -q "needs --repos-file" "$tmp/err"'
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm 000000000000
check "apply with a wrong confirm token -> 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ]'
RUN_ENV=(); run plan --repos-file "$ALW"
check "plan prints the confirm token of the committed allowlist and SCOPE MATCH, exit 0" '[ $RC -eq 0 ] && grep -q "apply-confirm token: $TOK" "$tmp/err" && grep -q "SCOPE MATCH" "$tmp/err" && [ "$(nput)" = 0 ]'
# A repos file other than the allowlist is refused even with its own (self-derived) token (review A-P1).
mkstate T/ci:wf "${AL[0]}:wf"
printf 'T/ci\n' > "$tmp/other.txt"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$tmp/other.txt" --apply-confirm "$(tok "$tmp/other.txt")"
check "apply with a repos file outside the allowlist and its own token -> 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ] && grep -q "allowlist" "$tmp/err"'
allst
printf '%s\n' "${AL[@]:1}" > "$tmp/sub.txt"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$tmp/sub.txt" --apply-confirm "$(tok "$tmp/sub.txt")"
check "apply with a subset (8 of 9) of the allowlist and its own token -> 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ]'
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$tmp/sub.txt" --apply-confirm "$TOK"
check "apply with a subset and the allowlist token -> 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ]'
RUN_ENV=(); run plan --repos-file "$tmp/other.txt"
check "plan with a repos file outside the allowlist -> says apply would be refused, exit 1, no token for that file" '[ $RC -eq 1 ] && grep -q "differs from the committed allowlist" "$tmp/err" && ! grep -q "apply-confirm token: $(tok "$tmp/other.txt")" "$tmp/err"'

# ---- apply -----------------------------------------------------------------------------------------
printf '# same set, other order, comments\n%s\n\n' "$(printf '%s\n' "${AL[@]}" | sort -r)" > "$tmp/reordered.txt"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$tmp/reordered.txt" --apply-confirm "$TOK"
check "apply of the 9 allowlisted repos (any order) -> exit 0" '[ $RC -eq 0 ]'
check "exactly the 9 allowlisted repos were PUT, each with enabled=false" '[ "$(grep "^PUT " "$SEC_TEST_LOG/gh_calls.log" | sort | tr "\n" ";")" = "$(printf "PUT /repos/%s/actions/permissions enabled=false\n" "${AL[@]}" | sort | tr "\n" ";")" ]'
check "every read-back reported DISABLED" '[ "$(grep -c ": DISABLED" "$tmp/err")" = 9 ]'
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "re-run after apply: already-disabled, no PUT, exit 0" '[ $RC -eq 0 ] && [ "$(nput)" = 0 ] && [ "$(grep -c "already-disabled" "$tmp/err")" = 9 ]'
allst HelixDevelopment/newci:wf
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "a live-selected repo outside the pin -> refused 3, diff printed, no PUT" '[ $RC -eq 3 ] && grep -q "selected live but not pinned: HelixDevelopment/newci" "$tmp/err" && [ "$(nput)" = 0 ]'
RUN_ENV=(); run plan --repos-file "$ALW"
check "plan with a scope difference -> exit 1, SCOPE DIFF printed, no SCOPE MATCH" '[ $RC -eq 1 ] && grep -q "SCOPE DIFF" "$tmp/err" && ! grep -q "SCOPE MATCH" "$tmp/err"'
S=(); for r in "${AL[@]}"; do if [ "$r" = "${AL[1]}" ]; then S+=("$r:wf,arch"); else S+=("$r:wf"); fi; done; mkstate "${S[@]}"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "a pinned repo not selected live (archived) -> refused 3, no PUT" '[ $RC -eq 3 ] && grep -q "pinned but not selected live: ${AL[1]}" "$tmp/err" && [ "$(nput)" = 0 ]'
S=(); for r in "${AL[@]}"; do if [ "$r" = "${AL[2]}" ]; then S+=("$r:wf,pages=workflow"); else S+=("$r:wf"); fi; done; mkstate "${S[@]}"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "a pinned repo that serves Pages -> refused 3, no PUT" '[ $RC -eq 3 ] && [ "$(nput)" = 0 ]'
allst HelixDevelopment/other:permfail
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "an ERR row in a pinned org -> apply refused, exit 1, no PUT" '[ $RC -eq 1 ] && grep -q "ERR rows present" "$tmp/err" && [ "$(nput)" = 0 ]'
S=(); for r in "${AL[@]}"; do if [ "$r" = "${AL[0]}" ]; then S+=("$r:wf,putfail"); else S+=("$r:wf"); fi; done; mkstate "${S[@]}"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "a failed PUT -> exit 1 (other repos still done)" '[ $RC -eq 1 ] && grep -q "apply FAILED ${AL[0]}" "$tmp/err" && [ "$(grep -c ": DISABLED" "$tmp/err")" = 8 ]'
S=(); for r in "${AL[@]}"; do if [ "$r" = "${AL[3]}" ]; then S+=("$r:wf,noop"); else S+=("$r:wf"); fi; done; mkstate "${S[@]}"
RUN_ENV=(GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "read-back still enabled=true -> exit 1" '[ $RC -eq 1 ] && grep -q "readback ${AL[3]} enabled=true: FAILED" "$tmp/err"'
check "shipped allowlist lists exactly 9 repos" '[ "${#AL[@]}" = 9 ]'

# ---- round 3 (review r3 F4, F5) --------------------------------------------------------------------
# Collation pinned: the token and the comm-based scope check must not depend on the caller's locale.
# en_US.UTF-8 orders mixed case differently from C (it is the locale the review used); another non-C
# locale is used only when en_US is not installed, and the case is reported SKIP when none is.
NONC=""
if locale -a 2>/dev/null | grep -qix 'en_US.utf8'; then NONC=en_US.UTF-8
else NONC=$(locale -a 2>/dev/null | grep -viE '^(C|POSIX)(\.|$)' | head -1); fi
if [ -n "$NONC" ]; then
  allst
  RUN_ENV=(LC_ALL="$NONC"); run plan --repos-file "$ALW"
  check "LC_ALL=$NONC: plan prints the C-collation token of the allowlist and SCOPE MATCH" '[ $RC -eq 0 ] && grep -q "apply-confirm token: $TOK" "$tmp/err" && grep -q "SCOPE MATCH" "$tmp/err"'
  RUN_ENV=(LC_ALL="$NONC" GH_ACTIONS_APPLY=yes); run apply --repos-file "$ALW" --apply-confirm "$TOK"
  check "LC_ALL=$NONC: apply of the allowlist with its token -> 0, 9 PUTs" '[ $RC -eq 0 ] && [ "$(nput)" = 9 ]'
else
  echo "SKIP no non-C locale installed: the LC_ALL pin is not exercised on this host"
fi
# gh is pinned to github.com: an inherited GH_HOST or enterprise token must never reach it.
allst
RUN_ENV=(GH_ACTIONS_APPLY=yes GH_HOST=ghe.evil.example GH_ENTERPRISE_TOKEN=x GITHUB_ENTERPRISE_TOKEN=x); run apply --repos-file "$ALW" --apply-confirm "$TOK"
check "every gh call is 'api --hostname github.com ...'" '[ $RC -eq 0 ] && [ -s "$SEC_TEST_LOG/gh_argv.log" ] && ! grep -v "^api --hostname github.com " "$SEC_TEST_LOG/gh_argv.log" | grep -q .'
check "GH_HOST and enterprise tokens never reach gh" '[ -s "$SEC_TEST_LOG/gh_env.log" ] && ! grep -v -x "ENV GH_HOST=unset GH_ENTERPRISE_TOKEN= GITHUB_ENTERPRISE_TOKEN=" "$SEC_TEST_LOG/gh_env.log" | grep -q .'

echo "RESULT: $((n-bad))/$n passed"
[ "$bad" -eq 0 ]
