#!/usr/bin/env bash
# github_actions_inventory_disable.sh -- inventory GitHub Actions in the own
# orgs and (only on explicit, guarded request) disable Actions for an EXPLICIT
# list of repositories, per §11.4.156 (no active CI/CD in repos we author).
#
# Status: PROVISIONAL (§11.4.290). apply is tested only against a fake `gh`
# (tests/security/test_github_actions_inventory_disable.sh); it has not been
# run against GitHub. `list` (read-only) was run on 2026-11-12.
#
# Modes (default: list):
#   list    read-only: one TSV row per repo: visibility, archived, fork,
#           workflow files, dynamic workflows, Pages (GET /repos/{r}/pages:
#           build_type, or "-" on 404), Actions enabled, allowed actions, last
#           run, selected. A row whose data could not be read is "ERR" in the
#           failed column and in `selected`; any ERR row makes the exit 1.
#           The workflows list is read with per_page=100 (one page): when the
#           answer's total_count is larger than the list, the row is ERR.
#   plan    list, then compare the selection with --repos-file (when given)
#           and print the apply-confirm token. A --repos-file whose repo set is
#           not the pinned allowlist is reported (apply would be refused) and
#           the exit is 1.
#   apply   PUT /repos/{r}/actions/permissions enabled=false for the repos of
#           --repos-file, then read each one back (must be enabled=false).
#           Refused (exit 3) unless ALL hold: GH_ACTIONS_APPLY=yes; --repos-file
#           FILE is given; the repo SET of FILE equals the pinned allowlist
#           below (order, comments and blank lines do not matter);
#           --apply-confirm equals the token of the PINNED allowlist (first 12
#           hex of sha256 of its repos, sorted in C collation, one per line;
#           printed by plan). The token is computed from the list built into
#           this script, never from the file passed in, so a different file
#           cannot carry its own token. The live selection over the orgs of
#           FILE must equal FILE exactly (repos already disabled count as
#           done). Any ERR row refuses apply (exit 1): an unreadable repo
#           might belong to the selection.
#
# Pinned scope (operator decision 2026-11-12): exactly the 9 repos of
# scripts/security/actions_disable_allowlist.txt, also built into this script
# (ALLOWLIST below; the test checks that both are the same set). The scope is
# NOT recomputed at apply time: a repo that gains a workflow later is reported
# as a difference and apply is refused, never silently swept in. Changing the
# scope needs a new operator decision and an edit of BOTH lists.
#
# Selection (--select, default files): a non-archived repo with Actions
# enabled and at least one .github/workflows file (files), or every
# non-archived repo with Actions enabled (enabled). A repo serving GitHub
# Pages (a dynamic/pages workflow, or GET /pages answers 200 with any
# build_type, which includes Pages deployed by a custom workflow) is
# "excluded-pages" unless --include-pages.
#
# Token: the gh keyring token of github.com (every call is `gh api --hostname
# github.com`; GITHUB_TOKEN, GH_TOKEN, GH_HOST, GH_ENTERPRISE_TOKEN and
# GITHUB_ENTERPRISE_TOKEN are unset for every call).
# apply needs admin on each repo. The token is never printed.
#
# Usage: github_actions_inventory_disable.sh [list|plan|apply]
#          [--org ORG]... | [--repos-file FILE]
#          [--select files|enabled] [--include-pages] [--apply-confirm TOKEN]
# Exit: 0 ok; 1 a call failed, an ERR row, a PUT failed or a read-back is not
#       enabled=false; 2 usage error; 3 refused apply (gating, or the selection
#       differs from --repos-file); 5 missing prerequisite (gh, jq).
set -euo pipefail
export LC_ALL=C   # one collation for sort, comm and the token (an en_US sort fed to comm is "not in sorted order")
ALLOWLIST=(
  HelixDevelopment/HelixGitpx HelixDevelopment/HelixPlay HelixDevelopment/agent HelixDevelopment/terminator
  HelixDevelopment/vpn vasic-digital/Courses-Creator vasic-digital/ShareConnect vasic-digital/TransmissionConnect
  vasic-digital/caf-git-mcp
)
MODE=list; SELECT=files; PAGES=no; CONFIRM=""; REPOS_FILE=""; declare -a ORGS=()
usage(){ echo "ERROR: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    list|plan|apply) MODE=$1 ;;
    --org) [ $# -ge 2 ] || usage "--org needs a value"; ORGS+=("$2"); shift ;;
    --repos-file) [ $# -ge 2 ] || usage "--repos-file needs a value"; REPOS_FILE=$2; shift ;;
    --select) [ $# -ge 2 ] || usage "--select needs a value"; SELECT=$2; shift ;;
    --include-pages) PAGES=yes ;;
    --apply-confirm) [ $# -ge 2 ] || usage "--apply-confirm needs a value"; CONFIRM=$2; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) usage "unknown argument: $1" ;;
  esac; shift
done
case "$SELECT" in files|enabled) ;; *) usage "bad --select: $SELECT" ;; esac
for tool in gh jq sha256sum; do command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing prerequisite: $tool" >&2; exit 5; }; done

declare -a PIN=()
if [ -n "$REPOS_FILE" ]; then
  [ ${#ORGS[@]} -eq 0 ] || usage "--org and --repos-file are exclusive (the orgs come from the file)"
  [ -f "$REPOS_FILE" ] && [ -r "$REPOS_FILE" ] || usage "repos file not readable: $REPOS_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}; line=${line//[[:space:]]/}
    [ -n "$line" ] || continue
    [[ "$line" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage "bad repos-file line: $line"
    PIN+=("$line")
  done < "$REPOS_FILE"
  [ ${#PIN[@]} -gt 0 ] || usage "repos file lists no repo"
  mapfile -t PIN < <(printf '%s\n' "${PIN[@]}" | sort -u)
  mapfile -t ORGS < <(printf '%s\n' "${PIN[@]}" | cut -d/ -f1 | sort -u)
fi
[ ${#ORGS[@]} -gt 0 ] || ORGS=(vasic-digital HelixDevelopment Helix-Track)
# The confirm token is derived from the built-in allowlist, never from the input file.
TOKEN=$(printf '%s\n' "${ALLOWLIST[@]}" | sort -u | sha256sum | cut -c1-12)
PIN_IS_ALLOWLIST=no
if [ ${#PIN[@]} -gt 0 ] && [ "$(printf '%s\n' "${PIN[@]}")" = "$(printf '%s\n' "${ALLOWLIST[@]}" | sort -u)" ]; then PIN_IS_ALLOWLIST=yes; fi

if [ "$MODE" = apply ]; then
  [ "${GH_ACTIONS_APPLY:-}" = yes ] || { echo "REFUSED: apply needs GH_ACTIONS_APPLY=yes" >&2; exit 3; }
  [ -n "$REPOS_FILE" ] || { echo "REFUSED: apply needs --repos-file (the pinned repo list)" >&2; exit 3; }
  [ "$PIN_IS_ALLOWLIST" = yes ] || { echo "REFUSED: $REPOS_FILE is not the pinned allowlist (scripts/security/actions_disable_allowlist.txt, the 9 repos of the operator decision)" >&2; exit 3; }
  [ -n "$CONFIRM" ] && [ "$CONFIRM" = "$TOKEN" ] || { echo "REFUSED: --apply-confirm must be the token of $REPOS_FILE (run plan to see it)" >&2; exit 3; }
fi

# Every call goes to github.com: an inherited GH_HOST or enterprise token never decides the host.
G(){ env -u GITHUB_TOKEN -u GH_TOKEN -u GH_HOST -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN gh api --hostname github.com "$@" </dev/null; }
rc=0
declare -a SELECTED=() DISABLED=()
row(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
printf 'repo\tvisibility\tarchived\tfork\tworkflow_files\tdynamic\tpages\tactions_enabled\tallowed\tlast_run\tselected\n'
for org in "${ORGS[@]}"; do
  if ! list=$(G --paginate "/orgs/$org/repos?per_page=100&type=all" --jq '.[]|[.full_name,.visibility,.archived,.fork]|@tsv' 2>/dev/null); then
    row "$org/*" ERR ERR ERR ERR ERR ERR ERR ERR ERR ERR; rc=1; continue
  fi
  while IFS=$'\t' read -r r vis arch fork; do
    [ -n "$r" ] || continue
    files=ERR; dyn=ERR; pg=ERR; en=ERR; al=ERR; last=-; sel=ERR
    if wj=$(G "/repos/$r/actions/workflows?per_page=100" 2>/dev/null) && jq -e '(.workflows|type=="array") and ((.total_count // (.workflows|length)) <= (.workflows|length))' >/dev/null 2>&1 <<<"$wj"; then
      files=$(jq -r '[.workflows[]|select(.path|startswith(".github/"))|"\(.path|sub(".github/workflows/";""))(\(.state))"]|join(",")' <<<"$wj")
      dyn=$(jq -r '[.workflows[]|select(.path|startswith("dynamic/"))|.path|sub("dynamic/";"")]|join(",")' <<<"$wj")
    fi
    if pj=$(G "/repos/$r/actions/permissions" 2>/dev/null) && jq -e '.enabled|type=="boolean"' >/dev/null 2>&1 <<<"$pj"; then
      en=$(jq -r '.enabled' <<<"$pj"); al=$(jq -r '.allowed_actions // "-"' <<<"$pj")
    fi
    if pgj=$(G "/repos/$r/pages" 2>&1); then
      pg=$(jq -r 'if type=="object" then (.build_type // "unknown") else "ERR" end' <<<"$pgj" 2>/dev/null || echo ERR)
    else
      case "$pgj" in *"(HTTP 404)"*) pg=- ;; esac
    fi
    if [ "$files$dyn" != "" ] && [ "$files" != ERR ]; then
      last=$(G "/repos/$r/actions/runs?per_page=1" --jq '.workflow_runs[0]|"\(.created_at // "-")|\(.actor.login // "-")|\(.event // "-")"' 2>/dev/null || echo "?")
    fi
    if [ "$files" = ERR ] || [ "$en" = ERR ] || [ "$pg" = ERR ]; then
      sel=ERR; rc=1
    else
      sel=no
      if [ "$en" = true ] && [ "$arch" = false ]; then
        case "$SELECT" in files) [ -n "$files" ] && sel=yes ;; enabled) sel=yes ;; esac
        if [ "$sel" = yes ] && [ "$PAGES" = no ] && { [[ "$dyn" == *pages* ]] || [ "$pg" != - ]; }; then sel=excluded-pages; fi
      fi
      [ "$sel" = yes ] && SELECTED+=("$r")
      [ "$en" = false ] && DISABLED+=("$r")
    fi
    row "$r" "$vis" "$arch" "$fork" "${files:--}" "${dyn:--}" "$pg" "$en" "$al" "$last" "$sel"
  done <<<"$list"
done

[ "$MODE" = list ] && exit $rc
if [ ${#PIN[@]} -eq 0 ]; then
  for r in ${SELECTED[@]+"${SELECTED[@]}"}; do echo "# would: PUT /repos/$r/actions/permissions enabled=false" >&2; done
  echo "# no --repos-file: selection shown only; apply needs a pinned repo list" >&2
  exit $rc
fi
# Compare the live selection with the pinned list. Pinned repos already disabled count as done.
sel_sorted=$(printf '%s\n' ${SELECTED[@]+"${SELECTED[@]}"} | sed '/^$/d' | sort -u)
dis_sorted=$(printf '%s\n' ${DISABLED[@]+"${DISABLED[@]}"} | sed '/^$/d' | sort -u)
pin_sorted=$(printf '%s\n' "${PIN[@]}")
extra=$(comm -23 <(echo "$sel_sorted" | sed '/^$/d') <(echo "$pin_sorted"))
done_pin=$(comm -12 <(echo "$pin_sorted") <(echo "$dis_sorted" | sed '/^$/d'))
missing=$(comm -23 <(echo "$pin_sorted") <(printf '%s\n%s\n' "$sel_sorted" "$done_pin" | sed '/^$/d' | sort -u))
todo=$(comm -12 <(echo "$pin_sorted") <(echo "$sel_sorted" | sed '/^$/d'))
if [ "$PIN_IS_ALLOWLIST" = yes ]; then
  echo "# pinned=${#PIN[@]} apply-confirm token: $TOKEN" >&2
else
  echo "# $REPOS_FILE differs from the committed allowlist (${#ALLOWLIST[@]} repos): apply would be refused; no apply-confirm token" >&2
  rc=1
fi
[ -n "$done_pin" ] && while IFS= read -r r; do echo "# already-disabled: $r" >&2; done <<<"$done_pin"
while IFS= read -r r; do [ -n "$r" ] && echo "# would: PUT /repos/$r/actions/permissions enabled=false" >&2; done <<<"$todo"
scope_ok=yes
if [ -n "$extra" ]; then scope_ok=no; while IFS= read -r r; do echo "# SCOPE DIFF: selected live but not pinned: $r" >&2; done <<<"$extra"; fi
if [ -n "$missing" ]; then scope_ok=no; while IFS= read -r r; do echo "# SCOPE DIFF: pinned but not selected live: $r" >&2; done <<<"$missing"; fi
if [ "$MODE" = plan ]; then
  [ "$scope_ok" = yes ] && echo "# SCOPE MATCH" >&2 || rc=1
  exit $rc
fi
# apply
[ "$rc" -eq 0 ] || { echo "REFUSED: ERR rows present; the selection cannot be proven equal to $REPOS_FILE" >&2; exit 1; }
[ "$scope_ok" = yes ] || { echo "REFUSED: the live selection differs from $REPOS_FILE (see SCOPE DIFF)" >&2; exit 3; }
while IFS= read -r r; do
  [ -n "$r" ] || continue
  if ! G -X PUT "/repos/$r/actions/permissions" -F enabled=false >/dev/null 2>&1; then
    echo "# apply FAILED $r" >&2; rc=1; continue
  fi
  now=$(G "/repos/$r/actions/permissions" --jq .enabled 2>/dev/null || echo "?")
  if [ "$now" = false ]; then echo "# readback $r enabled=false: DISABLED" >&2
  else echo "# readback $r enabled=$now: FAILED (Actions still enabled or unreadable)" >&2; rc=1; fi
done <<<"$todo"
exit $rc
