#!/usr/bin/env bash
# forge_branch_protect.sh -- block force-push and deletion of ONE branch (default
# `main`) on the forges that host the constitution, and nothing else.
#
# Status: PROVISIONAL (§11.4.290). The write paths are tested only against a
# loopback fixture (tests/security/test_forge_branch_protect.sh); no apply has
# been run against a real forge. `probe` (read-only) was run on 2026-11-12.
#
# Modes (default: plan):
#   probe   read-only GETs: current state of every selected target.
#   plan    probe, then print the exact request apply WOULD send (no write).
#   apply   send the write, then read it back and check the protection FIELDS.
#           Refused (exit 3) unless ALL hold: FORGE_PROTECT_APPLY=yes; exactly
#           one --target; --apply-confirm names the same target; the target is
#           on the apply allowlist (github_hd, m3w, codeberg: operator decision
#           2026-11-12); the selected target is the BUILT-IN target of that name
#           (same provider, API base, owner, repo and token variable; a test
#           fixture may replace only the API base, and only with a loopback
#           base under FORGE_PROTECT_TEST_LOOPBACK=yes); when the targets come
#           from FORGE_PROTECT_TARGETS_FILE, FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE=yes
#           is also set.
#
# What is protected (and only this): the branch named by --branch cannot be
# force-pushed (non-fast-forward) or deleted. Fast-forward pushes by accounts
# with write access keep working (§11.4.113 / §11.4.288 workflow unaffected).
# No review, status-check, signature or PR rule is added.
#
# Per provider:
#   github   ruleset {deletion, non_fast_forward} on refs/heads/<branch>,
#            enforcement active, no bypass actors. "Already present" is decided
#            by CONTENT (GET /rulesets/{id} of every ruleset), never by name:
#            target "branch", enforcement "active", include lists
#            refs/heads/<branch>, exclude is empty or absent, both rule types,
#            and a bypass_actors field that is PRESENT and empty (GitHub omits
#            the field for a caller who cannot read it: such a ruleset is
#            UNCONFIRMED, exit 1, nothing is sent). A ruleset that reads
#            compliant still needs GET /rules/branches/<branch> to list both
#            rule types for its id before it counts as ALREADY COMPLIANT
#            (else NOT CONFIRMED, exit 1, nothing is sent). A ruleset with our
#            name but other content is NON-COMPLIANT (exit 1, nothing is sent).
#            The ruleset list is read as one page of 100; a full page is
#            reported UNKNOWN (exit 1, nothing is sent), never guessed.
#            Read-back after apply: the same two checks for the new id.
#            A private repo on the Free plan answers 403 "Upgrade to GitHub
#            Pro..." and is reported BLOCKED-PLAN (github_vd: not protectable,
#            exit 7, never 0).
#   gitea    POST /branch_protections {enable_push:true, enable_push_whitelist:
#            false, enable_force_push:false (only when the instance swagger has
#            the field)}. An existing rule for the branch is checked by content;
#            a non-compliant one is reported NON-COMPLIANT and NOT modified.
#            Another rule whose name is a glob (*, ?, [) may also match the
#            branch; how Gitea/Forgejo order glob and exact rules is not
#            checked (UNCONFIRMED): such a rule is printed and the exit is 6.
#            Read-back checks the fields. When the instance shows no
#            enable_force_push field (Forgejo on Codeberg), force-push blocking
#            cannot be read back: it is printed UNCONFIRMED and the exit is 6.
#   gitlab   probe only (out of the apply scope).
#   gitflic, gitverse  probe only; plan prints the manual UI step.
# No force push is ever attempted to test the protection (§11.4.113); the
# evidence is the read-back of the protection fields.
#
# Credentials: read by variable NAME from the keys file (default
# ~/api_keys.sh, override KEYS_FILE) inside a subshell; a group/other-readable
# keys file is refused; a token holding '"', '\', CR or LF is refused. GitHub
# uses the gh keyring token for github.com (GITHUB_TOKEN/GH_TOKEN unset). The token reaches
# curl on stdin (curl -K -), never argv, a URL, a file or a log; xtrace is
# switched off around it (§11.4.10).
# Each token is BOUND to one host (TOKEN_HOST below; the gh keyring token to
# api.github.com only) and is sent only over https to that host on port 443
# (no port, or :443). A target naming another variable, another host (also a
# host that only starts or ends with the bound one), another port, plain http
# or a URL with user info is refused at start-up (exit 2) and again per
# request. The only exception is a loopback base (127.0.0.1 or [::1], http or
# https, any port) when FORGE_PROTECT_TEST_LOOPBACK=yes: the hermetic tests'
# fixture. That test mode refuses to start (exit 2) while any proxy variable
# (http_proxy, https_proxy, all_proxy, upper or lower case) is set, so a
# plain-http fixture request can never carry a token to a proxy. Outside the
# test mode every base is https, so a proxy only sees a CONNECT tunnel.
# The gh keyring token is read with `gh auth token --hostname github.com`
# (GH_HOST, GH_ENTERPRISE_TOKEN, GITHUB_ENTERPRISE_TOKEN unset). curl runs
# with -q (no .curlrc), without -L (no redirect is followed) and without -n.
#
# Targets: the built-in list (--list), or FORGE_PROTECT_TARGETS_FILE (lines
# name|provider|api_base|owner|repo|token_var; used by the tests).
#
# Usage:
#   forge_branch_protect.sh [probe|plan|apply] [--target NAME]... [--branch B]
#                           [--apply-confirm NAME]
#   forge_branch_protect.sh --list
# Exit: 0 ok; 1 a request failed, a read-back did not show the protection, or a
#       target is NON-COMPLIANT, UNCONFIRMED (unreadable bypass list) or NOT
#       CONFIRMED; 2 usage/config error (unknown target, bad branch, bad
#       targets file, a token not bound to the target's host); 3 refused
#       apply; 4 rate limited; 5 missing prerequisite (curl, jq, python3);
#       6 done but something is UNCONFIRMED (no force-push read-back field, or
#       a Gitea glob rule); 7 a target is not protectable (BLOCKED-PLAN: GitHub
#       Free plan, private repo). Several outcomes: 4 > 1 > 7 > 6 > 0.
set -euo pipefail

KEYS_FILE="${KEYS_FILE:-$HOME/api_keys.sh}"
BRANCH=main
MODE=plan
CONFIRM=""
declare -a SEL=()
APPLY_ALLOW=(github_hd m3w codeberg)

# Each token variable is bound to ONE host ("-" = the gh keyring token).
declare -A TOKEN_HOST=(
  [-]=api.github.com [GITLAB_TOKEN]=gitlab.com [M3W_GITEA_TOKEN]=git.m3w.org
  [CODEBERG_GITEA_TOKEN]=codeberg.org [GITFLIC_TOKEN]=api.gitflic.ru [GITVERSE_TOKEN]=api.gitverse.ru
)

# name|provider|api_base|owner|repo|token_var
TARGETS=(
  "github_hd|github|https://api.github.com|HelixDevelopment|constitution|-"
  # HelixDevelopment/HelixConstitution is a GitHub redirect (301) to HelixDevelopment/constitution.
  "github_vd|github|https://api.github.com|vasic-digital|HelixConstitution|-"
  "gitlab_hd1|gitlab|https://gitlab.com/api/v4|helixdevelopment1|helixconstitution|GITLAB_TOKEN"
  "gitlab_vd|gitlab|https://gitlab.com/api/v4|vasic-digital|HelixConstitution|GITLAB_TOKEN"
  "m3w|gitea|https://git.m3w.org/api/v1|Helix|constitution|M3W_GITEA_TOKEN"
  "codeberg|gitea|https://codeberg.org/api/v1|HelixDevelopment|constitution|CODEBERG_GITEA_TOKEN"
  "gitflic|gitflic|https://api.gitflic.ru|helixdevelopment|helixconstitution|GITFLIC_TOKEN"
  "gitverse|gitverse|https://api.gitverse.ru|helixdevelopment|HelixConstitution|GITVERSE_TOKEN"
)

BUILTIN=("${TARGETS[@]}")

die(){ echo "ERROR: $*" >&2; exit 2; }

# url_parts URL -> "scheme host port" (host lower-cased, port ":N" or "-");
# return 1 for anything else (user info, spaces, another scheme).
url_parts(){
  [[ "$1" =~ ^(https?)://([A-Za-z0-9.-]+|\[::1\])(:[0-9]{1,5})?(/[^[:space:]@]*)?$ ]] || return 1
  printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2],,}" "${BASH_REMATCH[3]:--}"
}
is_loopback(){ case "$1" in 127.0.0.1|'[::1]') return 0 ;; esac; return 1; }
# bound_ok TOKENVAR URL -> 0 when the token of TOKENVAR may be sent to URL.
bound_ok(){
  local tv=$1 p s h port want
  p=$(url_parts "$2") || return 1
  read -r s h port <<<"$p"
  want=${TOKEN_HOST[$tv]-}
  [ -n "$want" ] || return 1
  if is_loopback "$h"; then [ "${FORGE_PROTECT_TEST_LOOPBACK:-}" = yes ]; return; fi
  case "$port" in -|:443) ;; *) return 1 ;; esac
  [ "$s" = https ] && [ "$h" = "$want" ]
}
refuse(){ echo "REFUSED: $*" >&2; exit 3; }

for tool in curl jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing prerequisite: $tool" >&2; exit 5; }
done

OVERRIDE=no
if [ -n "${FORGE_PROTECT_TARGETS_FILE:-}" ]; then
  [ -f "$FORGE_PROTECT_TARGETS_FILE" ] && [ -r "$FORGE_PROTECT_TARGETS_FILE" ] || die "targets file not readable: $FORGE_PROTECT_TARGETS_FILE"
  TARGETS=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^[a-z0-9_]+\|(github|gitlab|gitea|gitflic|gitverse)\|https?://[^|[:space:]]+\|[A-Za-z0-9._-]+\|[A-Za-z0-9._-]+\|(-|[A-Z0-9_]+)$ ]] || die "bad targets-file line: $line"
    TARGETS+=("$line")
  done < "$FORGE_PROTECT_TARGETS_FILE"
  [ ${#TARGETS[@]} -gt 0 ] || die "targets file has no target"
  OVERRIDE=yes
fi

# The loopback test mode sends the token over plain http: never through a proxy.
if [ "${FORGE_PROTECT_TEST_LOOPBACK:-}" = yes ]; then
  for _pv in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY; do
    [ -z "${!_pv:-}" ] || die "FORGE_PROTECT_TEST_LOOPBACK=yes refuses to run while $_pv is set (a plain-http request would hand the token to the proxy); unset it"
  done
fi

# Every target's token must be bound to the target's host (no request is sent otherwise).
for t in "${TARGETS[@]}"; do
  IFS='|' read -r _n _p _b _o _r _tv <<<"$t"
  bound_ok "$_tv" "$_b" || die "target $_n: its token (${_tv/#-/gh keyring}) is bound to ${TOKEN_HOST[$_tv]-no host} over https only; base refused (plain http, user info, another host, or a loopback base without FORGE_PROTECT_TEST_LOOPBACK=yes)"
done

target_names(){ local t; for t in "${TARGETS[@]}"; do printf '%s\n' "${t%%|*}"; done; }
line_of(){ local n=$1 t; shift; for t in "$@"; do [ "${t%%|*}" = "$n" ] && { printf '%s\n' "$t"; return 0; }; done; return 1; }
# in_list NEEDLE ITEM... : exact membership in plain bash. No pipe into `grep -q`: under
# pipefail the writer can die of SIGPIPE once grep has matched, and a match reads as a miss.
in_list(){ local n=$1 x; shift; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }
known_target(){ local t; for t in "${TARGETS[@]}"; do [ "${t%%|*}" = "$1" ] && return 0; done; return 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    probe|plan|apply) MODE=$1 ;;
    --target) [ $# -ge 2 ] || die "--target needs a name"; SEL+=("$2"); shift ;;
    --branch) [ $# -ge 2 ] || die "--branch needs a name"; BRANCH=$2; shift ;;
    --apply-confirm) [ $# -ge 2 ] || die "--apply-confirm needs a target"; CONFIRM=$2; shift ;;
    --list) printf '%s\n' "${TARGETS[@]}"; exit 0 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

# Branch: path segments of [A-Za-z0-9._-], no '..', no leading '.' or '-' in a segment.
[[ "$BRANCH" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*$ ]] && [[ "$BRANCH" != *..* ]] \
  || die "branch name refused: $BRANCH"
for s in ${SEL[@]+"${SEL[@]}"}; do known_target "$s" || die "unknown target: $s (see --list)"; done
[ -z "$CONFIRM" ] || known_target "$CONFIRM" || die "unknown --apply-confirm target: $CONFIRM"

if [ "$MODE" = apply ]; then
  [ "${FORGE_PROTECT_APPLY:-}" = yes ] || refuse "apply needs FORGE_PROTECT_APPLY=yes"
  [ ${#SEL[@]} -eq 1 ] && [ "$CONFIRM" = "${SEL[0]}" ] || refuse "apply needs exactly one --target and --apply-confirm with the same name"
  in_list "${SEL[0]}" "${APPLY_ALLOW[@]}" || refuse "target ${SEL[0]} is not on the apply allowlist (${APPLY_ALLOW[*]})"
  if [ "$OVERRIDE" = yes ] && [ "${FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE:-}" != yes ]; then
    refuse "targets come from FORGE_PROTECT_TARGETS_FILE; apply also needs FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE=yes"
  fi
  # The selected target must be the built-in one (provider, base, owner, repo, token variable),
  # not only the same name. A loopback test fixture may replace the base and nothing else.
  want=$(line_of "${SEL[0]}" "${BUILTIN[@]}") || refuse "target ${SEL[0]} is not a built-in target"
  have=$(line_of "${SEL[0]}" "${TARGETS[@]}")
  if [ "$have" != "$want" ]; then
    IFS='|' read -r _ hp hb ho hr ht <<<"$have"; IFS='|' read -r _ wp _ wo wr wt <<<"$want"
    hh=$(url_parts "$hb") || hh="- - -"
    read -r _ hhost _ <<<"$hh"
    { is_loopback "$hhost" && [ "${FORGE_PROTECT_TEST_LOOPBACK:-}" = yes ] && [ "$hp|$ho|$hr|$ht" = "$wp|$wo|$wr|$wt" ]; } \
      || refuse "target ${SEL[0]} differs from the built-in target of that name (provider, base, owner, repo, token)"
  fi
fi

# token_for VAR -> token on stdout. Return 1 absent/placeholder, 3 malformed.
token_for(){
  local var=$1 v
  if [ "$var" = - ]; then
    v=$(env -u GITHUB_TOKEN -u GH_TOKEN -u GH_HOST -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN gh auth token --hostname github.com 2>/dev/null) || return 1
  else
    [ -r "$KEYS_FILE" ] || return 1
    local perm; perm=$(stat -c '%a' "$KEYS_FILE")
    [ "${perm: -2}" = 00 ] || { echo "ERROR: $KEYS_FILE is readable by group/others ($perm)" >&2; return 1; }
    # shellcheck source=/dev/null
    v=$( set +u; . "$KEYS_FILE" >/dev/null 2>&1; printf '%s' "${!var:-}" ) || return 1
  fi
  case "$v" in ""|*YOUR*|*CHANGE*|*placeholder*|*xxxx*) return 1 ;; esac
  case "$v" in *'"'*|*'\'*|*$'\n'*|*$'\r'*) return 3 ;; esac
  printf '%s' "$v"
}

# req METHOD URL PROVIDER TOKENVAR [JSON] -> line 1 "HTTP <code>", line 2
# "RL <x-ratelimit-remaining or empty>", then the body.
req(){
  local _xt=0; case $- in *x*) _xt=1; set +x ;; esac
  local m=$1 url=$2 prov=$3 tv=$4 body=${5:-} hdr tok trc=0
  if ! bound_ok "$tv" "$url"; then   # defence in depth: start-up already refused such a target
    printf 'HTTP 000\nRL \n{"_local":"credential_not_bound_to_host"}\n'; [ "$_xt" = 1 ] && set -x; return 0
  fi
  tok=$(token_for "$tv") || trc=$?
  if [ "$trc" -ne 0 ]; then
    if [ "$trc" -eq 3 ]; then printf 'HTTP 000\nRL \n{"_local":"credential_malformed"}\n'
    else printf 'HTTP 000\nRL \n{"_local":"credential_absent"}\n'; fi
    [ "$_xt" = 1 ] && set -x; return 0
  fi
  case "$prov" in
    github|gitverse) hdr="Authorization: Bearer $tok" ;;
    gitlab)          hdr="PRIVATE-TOKEN: $tok" ;;
    gitea|gitflic)   hdr="Authorization: token $tok" ;;
  esac
  tok=""
  local out acc='Accept: application/json'
  [ "$prov" = gitverse ] && acc='Accept: application/vnd.gitverse.object+json;version=1'
  [ "$prov" = github ] && acc='Accept: application/vnd.github+json'
  local -a extra=()
  [ -n "$body" ] && extra=(-H 'Content-Type: application/json' --data-binary "$body")
  out=$(printf 'header = "%s"\n' "$hdr" | curl -q -sS -K - -X "$m" --max-time 30 \
          -H "$acc" ${extra[@]+"${extra[@]}"} -w '\n%{http_code}\n%header{x-ratelimit-remaining}\n.' "$url" 2>/dev/null) || true
  hdr=""
  [ "$_xt" = 1 ] && set -x
  out=${out%$'\n.'}
  local rl=${out##*$'\n'}; out=${out%$'\n'*}
  local code=${out##*$'\n'}; out=${out%$'\n'*}
  [[ "$code" =~ ^[0-9]{3}$ ]] || code=000
  printf 'HTTP %s\nRL %s\n%s\n' "$code" "$rl" "$out"
}
code_of(){ head -1 <<<"$1" | cut -d' ' -f2; }
rl_of(){ sed -n '2p' <<<"$1" | cut -c4-; }
body_of(){ tail -n +3 <<<"$1"; }

enc(){ python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

# Overall exit: 4 > 1 > 7 > 6 > 0.
rc=0
flag(){
  case "$1" in
    4) rc=4 ;;
    1) [ "$rc" = 4 ] || rc=1 ;;
    7) case "$rc" in 0|6) rc=7 ;; esac ;;
    6) [ "$rc" = 0 ] && rc=6 ;;
  esac; return 0
}

summ(){ # body -> one line, value-free
  python3 -I -c '
import json,sys
b=sys.argv[1]
try: j=json.loads(b)
except Exception: print("non-json", len(b)); sys.exit()
if isinstance(j,dict) and "_local" in j: print(j["_local"]); sys.exit()
if isinstance(j,list):
    names=[(x.get("name") or x.get("rule_name") or x.get("branch_name") or x.get("type")) for x in j if isinstance(x,dict)]
    print("items=%d %s"%(len(j),names[:6])); sys.exit()
keys=("message","full_name","path_with_namespace","private","visibility","default_branch","defaultBranch","version","enforcement","enable_push","enable_push_whitelist","enable_force_push","allow_force_push")
print({k:j[k] for k in keys if k in j} or sorted(j)[:8])' "$1"
}

# classify NAME RES -> prints a state word for a failed (non-2xx) response.
is_rate_limited(){ # RES
  local c b; c=$(code_of "$1"); b=$(body_of "$1")
  [ "$c" = 429 ] && return 0
  if [ "$c" = 403 ]; then
    [ "$(rl_of "$1")" = 0 ] && return 0
    grep -qi 'rate limit' <<<"$b" && return 0
  fi
  return 1
}
is_plan_blocked(){ [ "$(code_of "$1")" = 403 ] && grep -qi 'upgrade to github pro\|make this repository public' <<<"$(body_of "$1")"; }

# check_response LABEL RES ALLOWED_CODES -> 0 when allowed; else prints why and flags.
check_response(){
  local label=$1 res=$2 allowed=$3 c; c=$(code_of "$res")
  case ",$allowed," in *",$c,"*) return 0 ;; esac
  if is_rate_limited "$res"; then echo "  RATE-LIMITED: $label -> HTTP $c"; flag 4; return 1; fi
  echo "  FAILED: $label -> HTTP $c | $(summ "$(body_of "$res")")"; flag 1; return 1
}

# gh_verdict REF (ruleset JSON on stdin) -> COMPLIANT | NOBYPASS (the content, but no
# bypass_actors field: the bypass list is unreadable for this token) | NO
GH_RULESET_VERDICT='if (type=="object") and (.target=="branch") and (.enforcement=="active")
    and ((.conditions.ref_name.include // []) | index($ref) != null)
    and ((.conditions.ref_name.exclude // []) == [])
    and ([.rules[]?.type] | (index("deletion") != null) and (index("non_fast_forward") != null))
  then (if (has("bypass_actors") | not) then "NOBYPASS" elif .bypass_actors == [] then "COMPLIANT" else "NO" end)
  else "NO" end'
gh_verdict(){ jq -r --arg ref "$1" "$GH_RULESET_VERDICT" 2>/dev/null || echo NO; }

# branch_rules_ok BASE O R TV ID -> 0 when GET /rules/branches/<branch> lists deletion AND
# non_fast_forward for ruleset ID; 1 when it does not; 2 when the GET failed (already reported).
branch_rules_ok(){
  local rb; rb=$(req GET "$1/repos/$2/$3/rules/branches/$(enc "$BRANCH")" github "$4")
  check_response "readback GET rules/branches/$BRANCH" "$rb" 200 || return 2
  body_of "$rb" | jq -e --argjson id "$5" '[.[]? | select(.ruleset_id==$id) | .type] | (index("deletion")!=null) and (index("non_fast_forward")!=null)' >/dev/null 2>&1
}

github_flow(){ # base o r tv name
  local base=$1 o=$2 r=$3 tv=$4 name=$5 eb ref="refs/heads/$BRANCH" rsname="protect-$BRANCH-no-force-no-delete"
  eb=$(enc "$BRANCH")
  local res; res=$(req GET "$base/repos/$o/$r" github "$tv")
  echo "  probe GET /repos/$o/$r -> HTTP $(code_of "$res") | $(summ "$(body_of "$res")")"
  check_response "GET repo" "$res" 200 || return 0
  local pr; pr=$(req GET "$base/repos/$o/$r/branches/$eb/protection" github "$tv")
  echo "  probe GET /branches/$BRANCH/protection -> HTTP $(code_of "$pr") | $(summ "$(body_of "$pr")")"
  local gr; gr=$(req GET "$base/repos/$o/$r/rulesets?per_page=100" github "$tv")
  echo "  probe GET /rulesets -> HTTP $(code_of "$gr") | $(summ "$(body_of "$gr")")"
  if is_plan_blocked "$gr"; then
    echo "  state: BLOCKED-PLAN (private repo on GitHub Free: rulesets need GitHub Pro/Team or a public repo; not protectable by this script)"
    flag 7; return 0
  fi
  is_plan_blocked "$pr" || check_response "GET branch protection" "$pr" 200,404 || true
  check_response "GET rulesets" "$gr" 200 || { echo "  state: UNKNOWN (ruleset list unreadable; nothing will be sent)"; return 0; }
  jq -e 'type=="array"' >/dev/null 2>&1 <<<"$(body_of "$gr")" || { echo "  FAILED: ruleset list is not a JSON array"; flag 1; return 0; }
  if [ "$(body_of "$gr" | jq 'length')" -ge 100 ]; then
    echo "  state: UNKNOWN (100 or more rulesets: the list is not paginated by this script; nothing will be sent)"; flag 1; return 0
  fi
  local ids id det v compliant="" nobypass="" samename=""
  ids=$(body_of "$gr" | jq -r '.[] | (.id|tostring) + "\t" + (.name // "")')
  while IFS=$'\t' read -r id nm; do
    [ -n "$id" ] || continue
    [[ "$id" =~ ^[0-9]+$ ]] || { echo "  FAILED: ruleset id not numeric"; flag 1; return 0; }
    det=$(req GET "$base/repos/$o/$r/rulesets/$id" github "$tv")
    check_response "GET ruleset $id" "$det" 200 || { echo "  state: UNKNOWN (ruleset $id unreadable; nothing will be sent)"; return 0; }
    v=$(body_of "$det" | gh_verdict "$ref")
    case "$v" in
      COMPLIANT) compliant="$compliant $id"; echo "  ruleset $id ($nm): content COMPLIANT" ;;
      NOBYPASS)  nobypass="$nobypass $id"; echo "  ruleset $id ($nm): content matches but no bypass_actors field (bypass list unreadable)" ;;
      *) echo "  ruleset $id ($nm): does not block force-push and deletion of $BRANCH"
         [ "$nm" = "$rsname" ] && samename=$id ;;
    esac
  done <<<"$ids"
  if [ -n "$compliant" ]; then
    local c brc
    for c in $compliant; do
      brc=0; branch_rules_ok "$base" "$o" "$r" "$tv" "$c" || brc=$?
      [ "$brc" = 2 ] && { echo "  state: UNKNOWN (rules/branches unreadable; nothing will be sent)"; return 0; }
      if [ "$brc" = 0 ]; then echo "  state: ALREADY COMPLIANT (ruleset $c blocks deletion + non_fast_forward on $ref, no bypass; GET /rules/branches/$BRANCH lists both for it)"; return 0; fi
    done
    echo "  state: NOT CONFIRMED (ruleset(s)$compliant read compliant, but GET /rules/branches/$BRANCH does not list deletion + non_fast_forward for them; nothing will be sent)"; flag 1; return 0
  fi
  if [ -n "$nobypass" ]; then
    echo "  state: UNCONFIRMED (ruleset(s)$nobypass have the content but no bypass_actors field: this token cannot read the bypass list; nothing will be sent)"; flag 1; return 0
  fi
  if [ -n "$samename" ]; then echo "  state: NON-COMPLIANT (ruleset $samename named $rsname does not have the reviewed content; nothing will be sent)"; flag 1; return 0; fi
  echo "  state: ABSENT"
  [ "$MODE" = probe ] && return 0
  local body; body=$(printf '{"name":"%s","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["%s"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}' "$rsname" "$ref")
  echo "  plan: POST /repos/$o/$r/rulesets"; echo "  body: $body"
  echo "  readback: GET /rulesets/{id} (content) + GET /rules/branches/$BRANCH (both rule types for {id})"
  [ "$MODE" = apply ] || return 0
  local ar; ar=$(req POST "$base/repos/$o/$r/rulesets" github "$tv" "$body")
  echo "  apply POST -> HTTP $(code_of "$ar")"
  check_response "POST ruleset" "$ar" 201 || return 0
  id=$(body_of "$ar" | jq -r '.id // empty' 2>/dev/null || true)
  [[ "$id" =~ ^[0-9]+$ ]] || { echo "  FAILED: POST answer has no numeric id"; flag 1; return 0; }
  det=$(req GET "$base/repos/$o/$r/rulesets/$id" github "$tv")
  check_response "readback GET ruleset $id" "$det" 200 || return 0
  if [ "$(body_of "$det" | gh_verdict "$ref")" != COMPLIANT ]; then
    echo "  FAILED: readback ruleset $id does not have the reviewed content"; flag 1; return 0
  fi
  local brc=0; branch_rules_ok "$base" "$o" "$r" "$tv" "$id" || brc=$?
  case "$brc" in
    0) echo "  RESULT: APPLIED (readback: ruleset $id active, deletion + non_fast_forward on $BRANCH, no bypass)" ;;
    1) echo "  FAILED: readback rules/branches/$BRANCH does not list deletion + non_fast_forward for ruleset $id"; flag 1 ;;
  esac
}

# gitea_check JSON HASFIELD -> prints COMPLIANT | COMPLIANT-FORCE-UNCONFIRMED | NON-COMPLIANT:<why>
gitea_check(){
  jq -r '
    if (.enable_push != true) then "NON-COMPLIANT:enable_push is not true (fast-forward pushes would be blocked)"
    elif (.enable_push_whitelist != false) then "NON-COMPLIANT:enable_push_whitelist is not false"
    elif has("enable_force_push") then
      (if .enable_force_push == false then "COMPLIANT" else "NON-COMPLIANT:enable_force_push is not false" end)
    else "COMPLIANT-FORCE-UNCONFIRMED" end' <<<"$1" 2>/dev/null || echo "NON-COMPLIANT:unreadable protection object"
}

gitea_report(){ # VERDICT PREFIX
  case "$1" in
    COMPLIANT) echo "  $2 (enable_push=true, no push allowlist, enable_force_push=false; a protected branch cannot be deleted)" ;;
    COMPLIANT-FORCE-UNCONFIRMED) echo "  $2 (enable_push=true, no push allowlist; deletion blocked)"
      echo "  force-push blocking: UNCONFIRMED (no enable_force_push field on this instance; nothing to read back)"; flag 6 ;;
    *) echo "  ${2/APPLIED/FAILED}: ${1#NON-COMPLIANT:}"; flag 1 ;;
  esac
}

gitea_flow(){ # base o r tv
  local base=$1 o=$2 r=$3 tv=$4 eb sw hasfield=no
  eb=$(enc "$BRANCH")
  sw=$(curl -q -sS --max-time 30 "${base%/api/v1}/swagger.v1.json" 2>/dev/null | python3 -I -c 'import json,sys
try:
  d=json.load(sys.stdin); p=d["definitions"]["CreateBranchProtectionOption"]["properties"]; print("yes" if "enable_force_push" in p else "no")
except Exception: print("unreadable")') || sw=unreadable
  echo "  probe swagger enable_force_push=$sw"
  [ "$sw" = yes ] && hasfield=yes
  [ "$sw" = unreadable ] && echo "  WARNING: swagger unreadable; the body is sent WITHOUT enable_force_push and the read-back decides"
  local u res
  for u in "/repos/$o/$r" "/version"; do
    res=$(req GET "$base$u" gitea "$tv")
    echo "  probe GET $u -> HTTP $(code_of "$res") | $(summ "$(body_of "$res")")"
    check_response "GET $u" "$res" 200 || true
  done
  res=$(req GET "$base/repos/$o/$r/branch_protections" gitea "$tv")
  echo "  probe GET /branch_protections -> HTTP $(code_of "$res") | $(summ "$(body_of "$res")")"
  check_response "GET branch_protections" "$res" 200 || { echo "  state: UNKNOWN (protection list unreadable; nothing will be sent)"; return 0; }
  local cur; cur=$(body_of "$res" | jq -c --arg b "$BRANCH" 'if type=="array" then (map(select(.rule_name==$b or .branch_name==$b)) | .[0] // "NONE") else "BAD" end' 2>/dev/null || echo '"BAD"')
  if [ "$cur" = '"BAD"' ]; then echo "  FAILED: protection list is not a JSON array"; flag 1; return 0; fi
  local g globs; globs=$(body_of "$res" | jq -r --arg b "$BRANCH" '.[] | (.rule_name // .branch_name // "") | select(. != $b and test("[*?\\[]"))' 2>/dev/null || true)
  if [ -n "$globs" ]; then
    while IFS= read -r g; do echo "  UNCONFIRMED: glob rule '$g' may also match $BRANCH; how Gitea/Forgejo order glob and exact rules is not checked"; done <<<"$globs"
    flag 6
  fi
  if [ "$cur" != '"NONE"' ]; then
    local v; v=$(gitea_check "$cur")
    case "$v" in NON-COMPLIANT:*) echo "  state: NON-COMPLIANT (existing rule for $BRANCH: ${v#NON-COMPLIANT:}; not modified, fix it by hand or delete the rule and re-run)"; flag 1 ;;
      *) gitea_report "$v" "state: ALREADY PRESENT" ;; esac
    return 0
  fi
  echo "  state: ABSENT"
  [ "$MODE" = probe ] && return 0
  local ff=""; [ "$hasfield" = yes ] && ff='"enable_force_push":false,'
  local body; body=$(printf '{"rule_name":"%s","enable_push":true,"enable_push_whitelist":false,%s"required_approvals":0,"enable_status_check":false,"block_on_rejected_reviews":false,"block_on_outdated_branch":false}' "$BRANCH" "$ff")
  echo "  plan: POST /repos/$o/$r/branch_protections"; echo "  body: $body"
  echo "  readback: GET /repos/$o/$r/branch_protections/$BRANCH (fields enable_push, enable_push_whitelist, enable_force_push)"
  [ "$hasfield" = yes ] || echo "  note: no enable_force_push field on this instance: force-push blocking will be UNCONFIRMED after apply"
  [ "$MODE" = apply ] || return 0
  local ar; ar=$(req POST "$base/repos/$o/$r/branch_protections" gitea "$tv" "$body")
  echo "  apply POST -> HTTP $(code_of "$ar")"
  check_response "POST branch_protections" "$ar" 201 || return 0
  local rb; rb=$(req GET "$base/repos/$o/$r/branch_protections/$eb" gitea "$tv")
  echo "  readback -> HTTP $(code_of "$rb") | $(summ "$(body_of "$rb")")"
  check_response "readback GET branch_protections/$BRANCH" "$rb" 200 || return 0
  if [ "$(body_of "$rb" | jq -r '.rule_name // .branch_name // empty' 2>/dev/null)" != "$BRANCH" ]; then
    echo "  FAILED: readback rule is not for $BRANCH"; flag 1; return 0
  fi
  gitea_report "$(gitea_check "$(body_of "$rb")")" "RESULT: APPLIED"
}

probe_only_flow(){ # prov base o r tv
  local prov=$1 base=$2 o=$3 r=$4 tv=$5 p u allowed res
  case "$prov" in
    gitlab)   p=$(enc "$o/$r"); set -- "$base/projects/$p|200" "$base/projects/$p/protected_branches/$(enc "$BRANCH")|200,404" ;;
    gitflic)  set -- "$base/project/$o/$r|200" ;;
    gitverse) set -- "$base/repos/$o/$r|200" "$base/repos/$o/$r/branches/$(enc "$BRANCH")/protection|200,400,404" ;;
  esac
  for u in "$@"; do
    allowed=${u##*|}; u=${u%|*}
    res=$(req GET "$u" "$prov" "$tv")
    echo "  probe GET ${u#"$base"} -> HTTP $(code_of "$res") | $(summ "$(body_of "$res")")"
    check_response "GET ${u#"$base"}" "$res" "$allowed" || continue
    if [ "$prov" = gitlab ] && [[ "$u" == */protected_branches/* ]]; then
      if [ "$(code_of "$res")" = 200 ] && body_of "$res" | jq -e '.allow_force_push==false' >/dev/null 2>&1; then
        echo "  state: PROTECTED (allow_force_push=false)"
      else echo "  state: NOT PROTECTED against force push"; fi
    fi
  done
  [ "$MODE" = probe ] && return 0
  case "$prov" in
    gitlab)   echo "  plan: out of the apply scope (operator decision 2026-11-12); probe only" ;;
    gitflic)  echo "  plan: NO API PATH (no documented branch-protection REST endpoint, UNCONFIRMED). Manual UI step: project Settings -> Branches / Protected branches -> protect $BRANCH, forbid force push and deletion; then re-run probe" ;;
    gitverse) echo "  plan: NO API PATH (branch-protection API not documented, UNCONFIRMED). Manual UI step: repository Settings -> Branches -> protect $BRANCH, forbid force push and deletion; then re-run probe" ;;
  esac
}

[ "$OVERRIDE" = yes ] && echo "NOTE: targets from FORGE_PROTECT_TARGETS_FILE ($(sha256sum < "$FORGE_PROTECT_TARGETS_FILE" | cut -c1-12))"
for t in "${TARGETS[@]}"; do
  IFS='|' read -r name prov base o r tv <<<"$t"
  if [ ${#SEL[@]} -gt 0 ]; then in_list "$name" "${SEL[@]}" || continue; fi
  echo "== $name ($prov) $o/$r branch=$BRANCH mode=$MODE"
  case "$prov" in
    github) github_flow "$base" "$o" "$r" "$tv" "$name" ;;
    gitea)  gitea_flow "$base" "$o" "$r" "$tv" ;;
    *)      probe_only_flow "$prov" "$base" "$o" "$r" "$tv" ;;
  esac
done
echo "EXIT $rc"
exit $rc
