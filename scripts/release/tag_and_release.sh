#!/usr/bin/env bash
# scripts/release/tag_and_release.sh — tag one reviewed release commit, push it
# to every upstream, then publish platform releases, safely and resumably.
#
# Usage:
#   scripts/release/tag_and_release.sh --tag TAG --sha SHA --remotes "R1 R2 ..." \
#       [--title TITLE] [--prerelease] [--gitlab-released-at ISO8601] [--message MSG] \
#       [--release github:REMOTE:OWNER/REPO]... \
#       [--release gitlab:REMOTE:OWNER/REPO]... \
#       [--release gitea:REMOTE:BASE_URL:OWNER/REPO]... \
#       [--no-badge-check] [--dry-run]
#
# What it guarantees (each one is a finding of the v73.4 review, I-3 and m-3/m-4):
#   * nothing is written before every preflight passes: every remote is fetched
#     (a failed fetch aborts), every remote's main must be an ancestor of SHA,
#     HEAD must equal SHA with a clean tree, the FIRST "## " heading of
#     `git show SHA:CHANGELOG.md` must start with TAG, and (unless
#     --no-badge-check) scripts/badges/compute_badges.sh --check must pass;
#   * main and the tag reach a remote together: `git push --atomic REMOTE
#     SHA:refs/heads/main refs/tags/TAG:refs/tags/TAG`; when a server does not
#     support atomic pushes, main is pushed first and the tag ONLY after the
#     remote's main reads back as SHA, so a tag never lands on a remote whose
#     main does not contain it;
#   * a remote is OK only when `git ls-remote` shows main == SHA, the tag object
#     == the local tag object and the tag peels to SHA; a platform release is
#     created ONLY for an OK remote, GitLab gets --ref SHA as a second guard,
#     GitHub uses --verify-tag, and every release is looked up before it is
#     created (a re-run never creates a second one); GitHub legs are de-duplicated
#     by repository id and an inaccessible repository is an honest GAP;
#   * re-running after a partial failure is the resume path: an existing local
#     annotated tag that peels to SHA is reused, remotes already OK are skipped,
#     existing releases are kept; a local or remote tag of the same name that
#     points anywhere else stops the run (never deleted, never replaced);
#   * nothing is ever forced: no --force, no --force-with-lease, no "+" refspec,
#     no tag deletion, no history rewrite (§11.4.113).
#   * release notes are cut from `git show SHA:CHANGELOG.md`, never from the
#     working tree.
#   * GitLab has NO pre-release flag (its Releases API has no such attribute, and
#     glab 1.129.0 "release create" has no --prerelease option). With --prerelease
#     the GitLab leg marks the release itself: the name is prefixed "PROVISIONAL
#     pre-release: " (unless the title already says PROVISIONAL), the description
#     starts with one fixed PROVISIONAL line, glab gets --no-update (also for a final
#     release: an existing release is never edited), and the release, new or kept,
#     is read back with `glab api --hostname H` (H = GITLAB_HOST without scheme, else
#     gitlab.com); a missing mark or an answer that is not JSON is a FAIL, a failed
#     read-back a GAP. --gitlab-released-at ISO8601 (a FUTURE time, only with
#     --prerelease and a gitlab spec; GNU date parses it) is passed as --released-at,
#     so GitLab shows its "Upcoming Release" badge until then; the read-back must
#     show upcoming_release=true and the same instant, otherwise the leg is a GAP
#     (UNCONFIRMED). A final release gets no mark and no date; a final re-run over a
#     kept PROVISIONAL-marked release keeps it as it is (no promotion path).
#   * one remote per distinct repository (CON-423, D10): a remote name listed
#     twice in --remotes is a usage error; two remotes whose push URLs name the
#     same repository (compared by host and path, case-folded, user, port and a
#     trailing ".git" removed) abort the preflight without printing the URLs;
#     for github.com remotes the repository id is compared too when gh is
#     logged in (a renamed or moved repository keeps its id), else an INFO line
#     says the id check is UNCONFIRMED.
#
# Dry run (CON-423, D3 and D4): --dry-run writes nothing, and after preflight it
# prints one plan line per release leg ("prerelease=flag", "prerelease=none" or,
# for GitLab, "prerelease=marked-by-title-and-description") and probes what it
# can read without writing: GitHub login, repository id, de-duplication and an
# existing release; GitLab login, project access and an existing release; for
# gitea only the token SHAPE (never its value; an empty or unset token is
# SKIPPED-NO-TOKEN, access is not probed and stays a WOULD-GAP). A probe that
# shows the real run would fail prints "PROBE ... WOULD-FAIL"; one that cannot
# decide prints "PROBE ... WOULD-GAP".
#
# Exit status (machine-readable; the last line is "RESULT: <word> ..."):
#   0 OK       every remote OK and every requested release present
#   1 FAIL     any MISMATCH, push failure, release failure, or a preflight abort
#   2 USAGE    bad arguments
#   5 GAPS     no failure, but at least one leg was SKIPPED (no credential, no
#              access); a gap is never reported as released. A gitea publisher
#              exit 3 is a gap only with its SKIPPED-NO-TOKEN line; any other
#              exit 3 (configuration or precondition) is a FAIL
# A --dry-run that passes preflight prints the plan and its probes and exits 0 when
# no probe found a problem, 1 ("RESULT: FAIL dry-run ...") when a probe says the
# real run would fail, and 5 ("RESULT: GAPS dry-run ...") when it would leave a gap.
#
# Output of external commands (round 5, CON-234 class, threat model
# docs/qa/con227_234_2026_11_11/round5/threat_model.md): the stderr of every NETWORK command (git fetch,
# git push, gh, glab, the gitea publisher) is never printed. A failure prints the exit status and one word
# of a closed set chosen by rc_err_class (or "timeout"); the gitea publisher's own "release_publish_gitea: "
# lines are the one exception (they are this repository's own text, passed through rc_redact_cut). Values
# read back from a server (object ids, repository ids) are validated before they are printed, and caller
# values that can hold a credential (--release specs, remote names, --sha, unknown arguments) are
# validated and never echoed when they are invalid.
# Network commands are bounded by RELEASE_NET_TIMEOUT seconds (default 600) through timeout(1), plus a
# low-speed limit for git's HTTP transport; a timeout is reported with the reason class "timeout".
# timeout(1) runs WITHOUT --foreground (round 6, K2): it puts the command in its own process group and, at the
# deadline, signals that whole group, so git's transport helpers (git remote-https, git-remote-https) die with
# git instead of keeping the captured stderr pipe open. A signal sent to this script is acted on when the
# running network command ends, at the latest RELEASE_NET_TIMEOUT + 10 seconds later. An interactive ssh
# passphrase prompt cannot be answered from that group (use an ssh agent).
# Credentials (round 6, K1, K3): a remote URL that holds a user name or password ("https://u:p@h/r",
# "https://TOKEN@h/r", "ssh://u:p@h/r") is refused before any network command, because git passes the URL,
# userinfo included, in the argv of its transport helper, which every local user can read in /proc. Use a git
# credential helper, an ssh key (ssh agent) or GIT_ASKPASS. The environment of every child is an allow-list
# (rc_env_lockdown): a caller's M3W_GITEA_TOKEN reaches the gitea publisher only, GH_TOKEN and GITLAB_TOKEN reach
# nothing (gh and glab use their own stored login: gh auth login, glab auth login).
set +x   # first: an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces this one line only
set -u
unset -v GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py; written as unset -v because the network-spawn gate of tests/release/channel_census.py admits only that form)
LC_ALL=C; export LC_ALL

TAG="" SHA="" REMOTES="" TITLE="" MESSAGE="" PRERELEASE=0 DRY=0 BADGE_CHECK=1 GL_RELEASED_AT=""
RELEASES=()
# The one redact-then-cut helper (round 3); every external-command output printed below goes through it.
# shellcheck source=scripts/release/redact_cut.sh
_rc_d="${BASH_SOURCE[0]}"; case "$_rc_d" in */*) _rc_d="${_rc_d%/*}" ;; *) _rc_d=. ;; esac   # no external command before the lockdown (round 6)
. "$(cd "$_rc_d" && pwd)/redact_cut.sh" || { printf 'tag_and_release: cannot load redact_cut.sh\n' >&2; exit 2; }
rc_env_clean "RELEASE_NET_TIMEOUT M3W_GITEA_TOKEN" "$@"; _rc=$?   # children get an environment built from the allow-list only: no caller token variable reaches any child (round 7, L1 L2; K3)
[ "$_rc" -eq 0 ] || { printf 'tag_and_release: cannot build a clean environment for the child processes (rc_env_clean status %s; Linux /proc is required)\n' "$_rc" >&2; printf 'RESULT: USAGE\n'; exit 2; }
rc_git_env   # no git trace anywhere, no terminal prompt, GIT_TRACE_REDACT=1
usage() { awk 'NR>1 && /^#/{print; next} NR>1{exit}' "$0"; }
die_usage() { printf 'tag_and_release: %s\n' "$1" >&2; printf 'RESULT: USAGE\n'; exit 2; }
need() { [ "$1" -ge 2 ] || die_usage "option $2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) need $# "$1"; TAG="$2"; shift 2 ;;
    --sha) need $# "$1"; SHA="$2"; shift 2 ;;
    --remotes) need $# "$1"; REMOTES="$2"; shift 2 ;;
    --title) need $# "$1"; TITLE="$2"; shift 2 ;;
    --message) need $# "$1"; MESSAGE="$2"; shift 2 ;;
    --release) need $# "$1"; RELEASES+=("$2"); shift 2 ;;
    --prerelease) PRERELEASE=1; shift ;;
    --gitlab-released-at) need $# "$1"; GL_RELEASED_AT="$2"; shift 2 ;;
    --no-badge-check) BADGE_CHECK=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) if [[ $1 =~ ^--?[A-Za-z][A-Za-z0-9-]{0,40}$ ]]; then die_usage "unknown argument: $1"
       else die_usage "unknown argument (not shown: it is not shaped like an option)"; fi ;;
  esac
done
[ -n "$TAG" ] || die_usage "--tag is required"
[ -n "$SHA" ] || die_usage "--sha is required"
[ -n "$REMOTES" ] || die_usage "--remotes is required (the upstream list is DATA, never guessed)"
SEG='[A-Za-z0-9][A-Za-z0-9._-]*'
[[ $TAG =~ ^$SEG$ ]] || die_usage "tag has unsafe characters (not shown)"
[[ $SHA =~ ^[0-9A-Fa-f]{7,64}$ ]] || die_usage "--sha must be a hexadecimal commit id of 7 to 64 digits (the value is not shown)"
n=0 _seen=" "
for r in $REMOTES; do
  n=$((n + 1)); [[ $r =~ ^$SEG$ ]] || die_usage "remote name number $n in --remotes has unsafe characters (not shown)"
  case "$_seen" in *" $r "*) die_usage "remote name number $n in --remotes repeats an earlier name (list each remote once; one remote per distinct repository)" ;; esac
  _seen="$_seen$r "
done
unset -v _seen
RE_GH="^github:$SEG:$SEG/$SEG\$" RE_GL="^gitlab:$SEG:$SEG(/$SEG)+\$"
RE_GT="^gitea:$SEG:(https://[A-Za-z0-9.-]+(:[0-9]{1,5})?|http://(127\\.0\\.0\\.1|localhost|\\[::1\\]):[0-9]{1,5}):$SEG/$SEG\$"
n=0
for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
  n=$((n + 1))
  [[ $spec =~ $RE_GH || $spec =~ $RE_GL || $spec =~ $RE_GT ]] || die_usage "bad --release spec number $n (expected github:REMOTE:OWNER/REPO, gitlab:REMOTE:GROUP/.../REPO or gitea:REMOTE:https://HOST[:PORT]:OWNER/REPO; the spec is not shown)"
  rr="${spec#*:}"; rr="${rr%%:*}"
  case " $REMOTES " in *" $rr "*) ;; *) die_usage "--release spec number $n names remote '$rr' that is not in --remotes" ;; esac
done
NET_TIMEOUT="${RELEASE_NET_TIMEOUT:-600}"
[[ $NET_TIMEOUT =~ ^[1-9][0-9]{0,5}$ ]] || die_usage "RELEASE_NET_TIMEOUT must be a positive whole number of seconds (the value is not shown)"
[ -n "$TITLE" ] || TITLE="$TAG"
[ -n "$MESSAGE" ] || MESSAGE="$TAG"
GL_ANY=0
for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do case "$spec" in gitlab:*) GL_ANY=1 ;; esac; done
GL_AT=""
if [ -n "$GL_RELEASED_AT" ]; then
  [ "$PRERELEASE" -eq 1 ] || die_usage "--gitlab-released-at is only for a --prerelease (a final release gets no upcoming date)"
  [ "$GL_ANY" -eq 1 ] || die_usage "--gitlab-released-at needs a --release gitlab:REMOTE:GROUP/REPO spec"
  [[ $GL_RELEASED_AT =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})$ ]] \
    || die_usage "--gitlab-released-at must be ISO 8601 like 2026-12-31T00:00:00Z or 2026-12-31T00:00:00+02:00 (the value is not shown)"
  GL_AT="$(date -u -d "$GL_RELEASED_AT" +%s 2>/dev/null)" || GL_AT=""
  [[ $GL_AT =~ ^[0-9]{1,12}$ ]] || die_usage "--gitlab-released-at is not a valid time (GNU date could not read it)"
  [ "$GL_AT" -gt "$(date -u +%s)" ] || die_usage "--gitlab-released-at must be in the future (GitLab marks only a future date as upcoming)"
fi

FAILS=0 GAPS=0
fail() { FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$*"; }
gap()  { GAPS=$((GAPS + 1));  printf 'GAP %s\n' "$*"; }
abort() { printf 'ABORT %s\n' "$*"; printf 'RESULT: FAIL fails=1 gaps=0 (aborted before any write)\n'; exit 1; }

# Temp files: ONE private run directory (mode 0700) holds the only two files this script writes, EXTERR
# and NOTES; it is removed at exit, on SIGHUP, SIGINT and SIGTERM too (the signal traps end the run
# through the EXIT trap). The stderr of the network commands is captured into a variable (x_*), never into
# a file, and is only classified (rc_err_class) or matched, never printed. Every LOCAL command's stderr is
# collected in EXTERR and printed once at exit through the helper (redacted, then cut at 2000 bytes, with a
# truncation line); this script's own diagnostics are on stdout or on fd 3 (the original stderr). Only
# SIGKILL leaves the directory behind.
RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/tar_run.XXXXXX")" || { printf 'tag_and_release: cannot create a temp directory\n' >&2; exit 2; }
: "${RUNDIR:?}"; chmod 700 "$RUNDIR"
EXTERR="$RUNDIR/exterr" NOTES="$RUNDIR/notes" GL_NOTES="$RUNDIR/glnotes"
exec 3>&2 2>"$EXTERR"
finish() {
  [ -f "$EXTERR" ] && rc_redact_cut 2000 mark <"$EXTERR" >&3
  rm -f -- "$EXTERR" "$NOTES" "$GL_NOTES"
  rmdir -- "$RUNDIR" 2>/dev/null || printf 'tag_and_release: WARNING the temp directory %s is not empty and was kept\n' "$RUNDIR" >&3
  return 0
}
trap finish EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
# Network commands. nt CMD...: CMD bounded by RELEASE_NET_TIMEOUT; timeout(1) runs without --foreground, so the
# command and every process it starts are in timeout's own process group and all of them get the signal at the
# deadline (round 6, K2: with --foreground only the direct child was signalled and git's transport helpers kept
# running); -k 10 sends KILL to the group when TERM was not enough. net ARGS...: git with a low-speed limit for
# the HTTP transport, bounded the same way. pub ARGS...: the gitea publisher, the one child that receives the
# caller's M3W_GITEA_TOKEN (exported in this command-substitution subshell only); it is not run under timeout(1),
# so the token is in no other process's environment; its own curl calls are bounded (-m 60 --connect-timeout 20).
if command -v timeout >/dev/null 2>&1; then HAVE_TIMEOUT=1
else HAVE_TIMEOUT=0; printf 'tag_and_release: WARNING timeout(1) not found; network commands are not time-bounded\n' >&3; fi
nt() { if [ "$HAVE_TIMEOUT" -eq 1 ]; then rc_net timeout -k 10 "$NET_TIMEOUT" "$@"; else rc_net "$@"; fi; }   # round 11: every network child through rc_net
net() { nt git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"; }
pub() { if [ -n "${M3W_GITEA_TOKEN+x}" ]; then export M3W_GITEA_TOKEN; fi; bash scripts/release_publish_gitea.sh "$@"; }
# xcls OUTPUT RC: the reason class of a failed network command (never any byte of OUTPUT)
xcls() {
  if [ "$HAVE_TIMEOUT" -eq 1 ] && { [ "$2" -eq 124 ] || [ "$2" -eq 137 ]; }; then printf 'timeout'
  else printf '%s' "$1" | rc_err_class; fi
}
# withheld TOOL RC CLASS: the fixed text printed in place of a network command's own message
withheld() { printf '(%s exit %s, reason class: %s; %s'"'"'s own message is withheld (it can carry a credential); run the same command by hand to read it)' "$1" "$2" "$3" "$1"; }
# own1 OUTPUT N: the first line of OUTPUT that is the gitea publisher's own message, redacted and cut
own1() { printf '%s\n' "$1" | grep -m 1 '^release_publish_gitea: ' | rc_redact_cut "$2"; }
# oid TEXT: TEXT when it is an object id (40 or 64 hexadecimal digits), else NOT-AN-OBJECT-ID
oid() { if [[ ${1:-} =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then printf '%s' "$1"; elif [ -z "${1:-}" ]; then printf -- '-'; else printf 'NOT-AN-OBJECT-ID'; fi; }
# repo_key URL: the identity of the repository a push URL names (CON-423, D10): the scheme, a user name and a port
# are dropped, then trailing "/" and one ".git" suffix; a hosted URL's host and path are case-folded (the forges
# this script serves treat both case-insensitively); a local path keeps its case. Pure bash: no command runs.
repo_key() {
  local u="${1:-}" h p
  case "$u" in
    [Ff][Ii][Ll][Ee]://*) h=""; p="${u#*://}" ;;
    *://*) u="${u#*://}"; h="${u%%/*}"; p="${u#"$h"}" ;;
    /*|./*|../*) h=""; p="$u" ;;
    *:*) h="${u%%:*}"; p="${u#*:}"; case "$h" in */*) h=""; p="$u" ;; esac ;;
    *) h=""; p="$u" ;;
  esac
  h="${h##*@}"; [[ $h =~ ^(.*):[0-9]*$ ]] && h="${BASH_REMATCH[1]}"
  while [[ $p == */ ]]; do p="${p%/}"; done
  p="${p%.git}"
  if [ -n "$h" ]; then p="${p#/}"; printf 'host:%s/%s' "${h,,}" "${p,,}"; else printf 'local:%s' "$p"; fi
}
printf '== %s start tag=%s sha=%s dry_run=%s\n' "$(date -Is)" "$TAG" "$SHA" "$DRY"

# ---------- preflight (no writes) ----------
rc_net git rev-parse --git-dir >/dev/null 2>&1 || abort "not inside a git repository"
FULL="$(rc_net git rev-parse -q --verify "$SHA^{commit}" 2>/dev/null)" || abort "SHA $SHA is not a commit here"
SHA="$FULL"
[ "$(rc_net git rev-parse HEAD)" = "$SHA" ] || abort "HEAD $(rc_net git rev-parse HEAD) != $SHA"
[ -z "$(rc_net git status --porcelain --untracked-files=normal 2>/dev/null)" ] || abort "working tree is not clean"

declare -A RMAIN
declare -A PUSHID   # CON-423 (D10): repository identity of a push URL -> the remote that pushes to it
declare -A GHREMOTE # CON-423 (D10): remote -> its github.com OWNER/REPO push paths
GH_N=0
for r in $REMOTES; do
  rc_net git remote get-url "$r" >/dev/null 2>&1 || abort "remote $r is not configured"
  # K1: every fetch and push URL of the remote (after insteadOf) must be free of a user name or password
  urls="$(rc_net git remote get-url --all "$r" 2>/dev/null; rc_net git remote get-url --push --all "$r" 2>/dev/null)"   # a here-string below, not a process substitution: its pipe would stay open in the EXIT trap's commands (N3 class)
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if rc_url_has_userinfo "$u"; then abort "remote $r has a URL with a user name or password in it; git would put it in the argv of its transport helper, which every local user can read (the URL is not shown); use a credential helper, an ssh key or GIT_ASKPASS instead"; fi
  done <<<"$urls"
  # CON-423 (D10): one remote per distinct repository. Two remotes whose push URLs name one repository would push it
  # twice and count it as two upstreams; refused before any write (the URLs are never shown).
  purls="$(rc_net git remote get-url --push --all "$r" 2>/dev/null)"
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    k="$(repo_key "$u")"
    if [ -n "${PUSHID[$k]:-}" ] && [ "${PUSHID[$k]}" != "$r" ]; then
      abort "remotes ${PUSHID[$k]} and $r push to the same repository (push URLs compared without scheme, user name, port, trailing / and .git, host and path case-folded; the URLs are not shown); list one remote per distinct repository in --remotes"
    fi
    PUSHID[$k]="$r"
    case "$k" in host:github.com/*) gp="${k#host:github.com/}"
      if [[ $gp =~ ^$SEG/$SEG$ ]]; then GHREMOTE[$r]="${GHREMOTE[$r]:-} $gp"; GH_N=$((GH_N + 1)); fi ;; esac
  done <<<"$purls"
  # No destination refspec and no "+": the fetched tip lands in FETCH_HEAD only.
  x_fetch="$(net fetch -q --no-tags "$r" refs/heads/main 2>&1 >/dev/null)"; frc=$?
  [ "$frc" -eq 0 ] || abort "fetch of $r main failed $(withheld git "$frc" "$(xcls "$x_fetch" "$frc")")"
  t="$(rc_net git rev-parse FETCH_HEAD)"
  RMAIN[$r]="$t"
  rc_net git merge-base --is-ancestor "$t" "$SHA" || abort "$r main $t is not an ancestor of $SHA (main moved; merge the new main into the release commit and re-review)"
done
# CON-423 (D10): a renamed GitHub repository keeps answering under its old name, so two different github.com URLs
# can name one repository. Their repository ids are compared (read-only gh api); an id that cannot be read leaves
# the check UNCONFIRMED for that remote (said so), never passed.
if [ "$GH_N" -gt 0 ]; then
  if command -v gh >/dev/null 2>&1 && nt gh auth status >/dev/null 2>&1; then
    declare -A GHID_OF
    for r in $REMOTES; do
      [ -n "${GHREMOTE[$r]:-}" ] || continue
      for gp in ${GHREMOTE[$r]}; do
        gid="$(nt gh api "repos/$gp" --jq .id 2>/dev/null)" || gid=""
        [[ $gid =~ ^[0-9]{1,20}$ ]] || gid=""
        if [ -z "$gid" ]; then printf 'INFO remote %s: GitHub repository id UNCONFIRMED (gh api could not read it; the URL identity check still applied)\n' "$r"; continue; fi
        if [ -n "${GHID_OF[$gid]:-}" ] && [ "${GHID_OF[$gid]}" != "$r" ]; then
          abort "remotes ${GHID_OF[$gid]} and $r push to the same GitHub repository (id $gid; one of the names is an old name GitHub still answers to; the URLs are not shown); list one remote per distinct repository in --remotes"
        fi
        GHID_OF[$gid]="$r"
      done
    done
  else
    printf 'INFO GitHub remote identity by repository id UNCONFIRMED (gh absent or not authenticated); the URL identity check still applied\n'
  fi
fi

FIRST="$(rc_net git show "$SHA:CHANGELOG.md" 2>/dev/null | awk '/^## /{print substr($0,4); exit}')"
case "$FIRST" in
  "$TAG"|"$TAG "*) ;;
  *) abort "the first '## ' heading of CHANGELOG.md at $SHA is not '$TAG ...' (got: ${FIRST:-<none>})" ;;
esac
rc_net git show "$SHA:CHANGELOG.md" | TAG="$TAG" awk 'BEGIN{t=ENVIRON["TAG"];on=0} /^## /{if(on)exit; h=substr($0,4); if(h==t||index(h,t" ")==1)on=1} on{print}' > "$NOTES"
[ -s "$NOTES" ] || abort "no release notes for $TAG at $SHA"

if [ "$BADGE_CHECK" -eq 1 ]; then
  [ -f scripts/badges/compute_badges.sh ] || abort "scripts/badges/compute_badges.sh absent (use --no-badge-check only where the repository has no badge computer)"
  rc_net bash scripts/badges/compute_badges.sh --check >/dev/null 2>&1 || abort "compute_badges.sh --check fails at $SHA"
fi

# Local tag: reuse when it peels to SHA (resume), stop when it points elsewhere.
LOCAL_TAG_EXISTS=0
if rc_net git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(rc_net git cat-file -t "refs/tags/$TAG")" = tag ] || abort "local $TAG is a lightweight tag; refusing to reuse it"
  [ "$(rc_net git rev-parse "refs/tags/$TAG^{commit}")" = "$SHA" ] || abort "local $TAG points at $(rc_net git rev-parse "refs/tags/$TAG^{commit}"), not $SHA"
  LOCAL_TAG_EXISTS=1
fi

# Remote tags of the same name must be absent or the very same object.
declare -A RTAG
for r in $REMOTES; do
  ro="$(net ls-remote "$r" "refs/tags/$TAG" 2>/dev/null | awk -F '\t' -v t="refs/tags/$TAG" '$2==t{print $1; exit}')" || true
  [ "$(oid "$ro")" != NOT-AN-OBJECT-ID ] || abort "$r answered a tag object id that is not an object id (the answer is not shown)"
  RTAG[$r]="$ro"
  if [ -n "$ro" ]; then
    [ "$LOCAL_TAG_EXISTS" -eq 1 ] || abort "$r already has $TAG ($ro) but no local tag exists; fetch that tag and check it, never re-create it"
    [ "$ro" = "$(rc_net git rev-parse "refs/tags/$TAG")" ] || abort "$r has a different $TAG object ($ro); never replaced (§11.4.113)"
  fi
done

# wfail / wgap SPEC TEXT: a would-be failure or gap of one release leg in the dry run (CON-423, D3)
WF=0 WG=0
wfail() { WF=$((WF + 1)); printf 'PROBE release %s WOULD-FAIL %s\n' "$1" "$2"; }
wgap()  { WG=$((WG + 1)); printf 'PROBE release %s WOULD-GAP %s\n' "$1" "$2"; }
# the host of the GitLab API reads: GITLAB_HOST (value-checked by the lockdown) without its scheme and slash, else gitlab.com
GL_HOST="${GITLAB_HOST:-gitlab.com}"; GL_HOST="${GL_HOST#http://}"; GL_HOST="${GL_HOST#https://}"; GL_HOST="${GL_HOST%/}"
[[ $GL_HOST =~ ^[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?$ ]] || GL_HOST=""

if [ "$DRY" -eq 1 ]; then
  for r in $REMOTES; do printf 'PLAN push --atomic %s %s:refs/heads/main refs/tags/%s (remote main %s, remote tag %s)\n' "$r" "$SHA" "$TAG" "${RMAIN[$r]}" "${RTAG[$r]:-absent}"; done
  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
    case "$spec:$PRERELEASE" in
      gitlab:*:1) printf 'PLAN release %s prerelease=marked-by-title-and-description upcoming=%s\n' "$spec" "${GL_RELEASED_AT:-none}" ;;
      *:1) printf 'PLAN release %s prerelease=flag\n' "$spec" ;;
      *) printf 'PLAN release %s prerelease=none\n' "$spec" ;;
    esac
  done
  # CON-423 (D3): read-only probes of every release leg, so the plan shows what the real run would report. Only exit
  # codes, fixed words and value-checked ids are printed: no command's own output (a login status can carry a token),
  # never a token value. A probe never writes: auth status, gh api repos/X, glab api projects/X, release view.
  WF=0 WG=0
  declare -A DGH_SEEN
  GH_AUTH_RC="" GL_AUTH_RC=""
  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
    kind="${spec%%:*}"; rest="${spec#*:}"; target="${rest#*:}"
    case "$kind" in
      github)
        if ! command -v gh >/dev/null 2>&1; then wgap "$spec" "SKIPPED-NO-TOKEN (gh absent)"; continue; fi
        if [ -z "$GH_AUTH_RC" ]; then nt gh auth status >/dev/null 2>&1; GH_AUTH_RC=$?; fi
        if [ "$GH_AUTH_RC" -ne 0 ]; then wgap "$spec" "SKIPPED-NO-TOKEN (gh auth status exit $GH_AUTH_RC)"; continue; fi
        id="$(nt gh api "repos/$target" --jq .id 2>/dev/null)"; irc=$?
        [[ $id =~ ^[0-9]{1,20}$ ]] || id=""
        if [ -z "$id" ]; then wgap "$spec" "NOT-ACCESSIBLE (gh api repos/$target exit $irc or no repository id; not released there)"; continue; fi
        if [ -n "${DGH_SEEN[$id]:-}" ]; then printf 'PROBE release %s OK would-deduplicate (same repository id %s as %s)\n' "$spec" "$id" "${DGH_SEEN[$id]}"; continue; fi
        DGH_SEEN[$id]="$target"
        if nt gh release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'PROBE release %s OK would-keep (release exists; repository id %s)\n' "$spec" "$id"
        else printf 'PROBE release %s OK would-create (gh auth status exit 0; repository id %s)\n' "$spec" "$id"; fi ;;
      gitlab)
        if ! command -v glab >/dev/null 2>&1; then wgap "$spec" "SKIPPED-NO-TOKEN (glab absent)"; continue; fi
        if [ -z "$GL_AUTH_RC" ]; then nt glab auth status >/dev/null 2>&1; GL_AUTH_RC=$?; fi
        if [ "$GL_AUTH_RC" -ne 0 ]; then wgap "$spec" "SKIPPED-NO-TOKEN (glab auth status exit $GL_AUTH_RC)"; continue; fi
        if [ -z "$GL_HOST" ] || ! command -v jq >/dev/null 2>&1; then wgap "$spec" "ACCESS-UNCONFIRMED (GITLAB_HOST is not a host name, or jq is absent; the project was not read)"; continue; fi
        enc="$(printf '%s' "$target" | jq -sRr @uri 2>/dev/null)" || enc=""
        if ! [[ $enc =~ ^[A-Za-z0-9._%-]+$ ]]; then wfail "$spec" "NOT-ACCESSIBLE (the project path could not be encoded)"; continue; fi
        pj="$(nt glab api --hostname "$GL_HOST" "projects/$enc" 2>/dev/null)"; prc=$?
        pt="$(printf '%s' "$pj" | jq -r 'type' 2>/dev/null)" || pt=""
        if [ "$prc" -ne 0 ] || [ "$pt" != object ]; then wfail "$spec" "NOT-ACCESSIBLE (glab api projects/$enc exit $prc, answer type ${pt:-unparsable}; the real run's release create would fail)"; continue; fi
        if nt glab release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'PROBE release %s OK would-keep (release exists; project readable)\n' "$spec"
        else printf 'PROBE release %s OK would-create (glab auth status exit 0; project readable)\n' "$spec"; fi ;;
      gitea)
        if [ -z "${M3W_GITEA_TOKEN:-}" ]; then wgap "$spec" "SKIPPED-NO-TOKEN (gitea token variable not set)"
        elif ! [[ $M3W_GITEA_TOKEN =~ ^[A-Za-z0-9._~+/=-]{8,200}$ ]]; then wfail "$spec" "TOKEN-SHAPE (token variable set, but outside the publisher's charset or length; the value is not shown)"
        else wgap "$spec" "ACCESS-UNCONFIRMED (token variable set, value not shown; the gitea publisher has no read-only probe and needs the tag, which a dry run does not create)"; fi ;;
    esac
  done
  if [ "$WF" -gt 0 ]; then printf 'RESULT: FAIL dry-run (no tag created, nothing pushed; would-fail=%d would-gap=%d)\n' "$WF" "$WG"; exit 1; fi
  if [ "$WG" -gt 0 ]; then printf 'RESULT: GAPS dry-run (no tag created, nothing pushed; would-fail=0 would-gap=%d)\n' "$WG"; exit 5; fi
  printf 'RESULT: OK dry-run (no tag created, nothing pushed)\n'
  exit 0
fi

if [ "$LOCAL_TAG_EXISTS" -eq 0 ]; then
  rc_net git tag -a "$TAG" -m "$MESSAGE" "$SHA" || abort "git tag failed"
  printf 'TAG created %s -> %s\n' "$TAG" "$SHA"
else
  printf 'TAG reused %s -> %s (resume)\n' "$TAG" "$SHA"
fi
TAGOBJ="$(rc_net git rev-parse "refs/tags/$TAG")"

# ---------- push ----------
remote_state() { # remote -> "MAIN TAGOBJ TAGPEELED"
  local out m o p
  out="$(net ls-remote "$1" refs/heads/main "refs/tags/$TAG" "refs/tags/$TAG^{}" 2>/dev/null)" || { printf 'ERR ERR ERR'; return 1; }
  m="$(printf '%s\n' "$out" | awk -F '\t' '$2=="refs/heads/main"{print $1; exit}')"
  o="$(printf '%s\n' "$out" | awk -F '\t' -v t="refs/tags/$TAG" '$2==t{print $1; exit}')"
  p="$(printf '%s\n' "$out" | awk -F '\t' -v t="refs/tags/$TAG^{}" '$2==t{print $1; exit}')"
  printf '%s %s %s' "$(oid "$m")" "$(oid "$o")" "$(oid "$p")"
}
is_ok() { local s; s="$(remote_state "$1")"; [ "$s" = "$SHA $TAGOBJ $SHA" ]; }

declare -A OK
for r in $REMOTES; do
  if is_ok "$r"; then OK[$r]=1; printf 'PUSH %s already OK (skipped)\n' "$r"; continue; fi
  x_push="$(net push --atomic "$r" "$SHA:refs/heads/main" "refs/tags/$TAG:refs/tags/$TAG" 2>&1 >/dev/null)"; prc=$?
  atomic_unsupported=0
  case "$x_push" in *'does not support --atomic'*) atomic_unsupported=1 ;; esac
  if [ "$prc" -eq 0 ]; then
    printf 'PUSH %s atomic ok\n' "$r"
  elif [ "$atomic_unsupported" -eq 1 ]; then
    printf 'PUSH %s: server has no atomic push; main first, tag only after main reads back\n' "$r"
    x_main="$(net push "$r" "$SHA:refs/heads/main" 2>&1 >/dev/null)"; mrc=$?
    if [ "$mrc" -eq 0 ] && [ "$(remote_state "$r" | cut -d' ' -f1)" = "$SHA" ]; then
      x_tagpush="$(net push "$r" "refs/tags/$TAG:refs/tags/$TAG" 2>&1 >/dev/null)"; trc=$?
      [ "$trc" -eq 0 ] || printf 'PUSH %s tag push failed %s\n' "$r" "$(withheld git "$trc" "$(xcls "$x_tagpush" "$trc")")"
    elif [ "$mrc" -ne 0 ]; then
      printf 'PUSH %s main push failed; tag NOT pushed %s\n' "$r" "$(withheld git "$mrc" "$(xcls "$x_main" "$mrc")")"
    else
      printf 'PUSH %s main push failed; tag NOT pushed (main does not read back as %s)\n' "$r" "$SHA"
    fi
  else
    printf 'PUSH %s failed %s\n' "$r" "$(withheld git "$prc" "$(xcls "$x_push" "$prc")")"
  fi
done

printf '== ls-remote verify\n'
for r in $REMOTES; do
  s="$(remote_state "$r")"
  if [ "$s" = "$SHA $TAGOBJ $SHA" ]; then OK[$r]=1; printf 'VERIFY %s OK main=%s tag=%s\n' "$r" "$SHA" "$TAGOBJ"
  else unset 'OK[$r]'; fail "VERIFY $r MISMATCH main/tagobj/peeled=$s expected=$SHA/$TAGOBJ/$SHA"; fi
done

# ---------- platform releases (only for OK remotes) ----------
PRE_GH=() PRE_TITLE="$TITLE"
[ "$PRERELEASE" -eq 1 ] && PRE_GH=(--prerelease)
# GitLab marking (no native pre-release flag on GitLab or in glab): see the header.
GL_MARK='**PROVISIONAL pre-release.** GitLab has no pre-release flag: this line, the release title and, with an upcoming date, the Upcoming Release badge are its only marking. It is not a final release.'
GL_TITLE="$TITLE" GL_NOTEFILE="$NOTES" GL_ARGS=(--no-update) GL_NOTES_OK=1
if [ "$PRERELEASE" -eq 1 ] && [ "$GL_ANY" -eq 1 ]; then
  case "$TITLE" in *PROVISIONAL*) ;; *) GL_TITLE="PROVISIONAL pre-release: $TITLE" ;; esac
  GL_NOTEFILE="$GL_NOTES"
  { printf '%s\n\n' "$GL_MARK"; cat -- "$NOTES"; } >"$GL_NOTES" || GL_NOTES_OK=0
  [ -n "$GL_RELEASED_AT" ] && GL_ARGS+=(--released-at "$GL_RELEASED_AT")
fi
# gl_readback SPEC TARGET: read the release back through the API and check the PROVISIONAL marks. Only fixed words
# and a value-checked time are printed; the server's own text never is (the tag needs no encoding: it matches SEG).
gl_readback() {
  local enc j arc res mk up rat extra
  [ -n "$GL_HOST" ] || { gap "RELEASE $1 PRERELEASE-READBACK UNCONFIRMED (GITLAB_HOST is not a host name; not read back)"; return 0; }
  command -v jq >/dev/null 2>&1 || { gap "RELEASE $1 PRERELEASE-READBACK UNCONFIRMED (jq absent; not read back)"; return 0; }
  enc="$(printf '%s' "$2" | jq -sRr @uri 2>/dev/null)" || enc=""   # GROUP/REPO with / as %2F (the target matched RE_GL)
  [[ $enc =~ ^[A-Za-z0-9._%-]+$ ]] || { fail "RELEASE $1 PRERELEASE-READBACK not attempted: the project path could not be encoded"; return 0; }
  j="$(nt glab api --hostname "$GL_HOST" "projects/$enc/releases/$TAG" 2>/dev/null)"; arc=$?
  [ "$arc" -eq 0 ] || { gap "RELEASE $1 PRERELEASE-READBACK UNCONFIRMED (glab api read failed $(withheld glab "$arc" "$(xcls "" "$arc")"))"; return 0; }
  res="$(printf '%s' "$j" | jq -r --arg m "$GL_MARK" 'if type != "object" then "unparsable" else
      (((.name // "") | tostring | contains("PROVISIONAL"))
        and ((((.description // "") | tostring | split("\n"))[0] // "") | gsub("^[ \t\r]+|[ \t\r]+$"; "")) == $m) as $ok
      | (if $ok then "marked" else "unmarked" end) + " " + (if .upcoming_release == true then "true" else "false" end)
        + " " + ((.released_at // "-") | tostring | gsub("[^0-9A-Za-z:.+-]"; "_")) end' 2>/dev/null)" || res=unparsable
  case "$res" in *$'\n'*|"") res=unparsable ;; esac
  read -r mk up rat extra <<<"$res"
  [ -z "${extra:-}" ] || mk=unparsable
  case "$mk" in
    marked) ;;
    unmarked) fail "RELEASE $1 PRERELEASE-MARK MISSING (the name or the first description line read back has no PROVISIONAL mark); edit the GitLab release by hand"; return 0 ;;
    *) fail "RELEASE $1 PRERELEASE-READBACK UNPARSABLE (the answer of glab api is not a release object; it is not shown)"; return 0 ;;
  esac
  [[ ${rat:-} =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:?[0-9]{2})$ ]] || rat=NOT-AN-ISO-TIME
  if [ -z "$GL_RELEASED_AT" ]; then
    printf 'PRERELEASE %s MARKED title+description (native pre-release flag: none on GitLab or in glab; no upcoming date requested)\n' "$1"
  elif [ "$up" != true ]; then
    gap "RELEASE $1 UPCOMING UNCONFIRMED (asked $GL_RELEASED_AT, read back upcoming_release=false, released_at=$rat); marked by title+description only"
  elif [ "$rat" = NOT-AN-ISO-TIME ] || [ "$(date -u -d "$rat" +%s 2>/dev/null)" != "$GL_AT" ]; then
    gap "RELEASE $1 UPCOMING DATE DIFFERS (asked $GL_RELEASED_AT, read back released_at=$rat); marked by title+description"
  else
    printf 'PRERELEASE %s upcoming_release=true released_at=%s (GitLab shows an Upcoming Release badge until then; the title and description marks stay)\n' "$1" "$rat"
  fi
}
declare -A GH_SEEN
for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
  kind="${spec%%:*}"; rest="${spec#*:}"; r="${rest%%:*}"; target="${rest#*:}"
  if [ -z "${OK[$r]:-}" ]; then fail "RELEASE $spec not attempted: remote $r is not OK"; continue; fi
  case "$kind" in
    github)
      if ! command -v gh >/dev/null 2>&1 || ! nt gh auth status >/dev/null 2>&1; then gap "RELEASE $spec SKIPPED-NO-TOKEN (gh not authenticated)"; continue; fi
      id="$(nt gh api "repos/$target" --jq .id 2>/dev/null)" || id=""
      [[ $id =~ ^[0-9]{1,20}$ ]] || id=""   # a repository id is a number; anything else is not printed
      if [ -z "$id" ]; then gap "RELEASE $spec NOT-ACCESSIBLE (gh api repos/$target failed; not released there)"; continue; fi
      if [ -n "${GH_SEEN[$id]:-}" ]; then printf 'RELEASE %s same repository id %s as %s (deduplicated)\n' "$spec" "$id" "${GH_SEEN[$id]}"; continue; fi
      GH_SEEN[$id]="$target"
      if nt gh release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s already exists (kept)\n' "$spec"; continue; fi
      if nt gh release create "$TAG" -R "$target" "${PRE_GH[@]+"${PRE_GH[@]}"}" --verify-tag --title "$PRE_TITLE" --notes-file "$NOTES" >/dev/null 2>&1 \
         && nt gh release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s CREATED\n' "$spec"
      else fail "RELEASE $spec create failed"; fi ;;
    gitlab)
      if ! command -v glab >/dev/null 2>&1 || ! nt glab auth status >/dev/null 2>&1; then gap "RELEASE $spec SKIPPED-NO-TOKEN (glab not authenticated)"; continue; fi
      if nt glab release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s already exists (kept)\n' "$spec"
        [ "$PRERELEASE" -eq 1 ] && gl_readback "$spec" "$target"; continue; fi
      if [ "$GL_NOTES_OK" -ne 1 ]; then fail "RELEASE $spec not attempted: the marked release notes could not be written"; continue; fi
      # --ref SHA: if the tag were somehow absent, glab would otherwise tag the default branch.
      if nt glab release create "$TAG" -R "$target" --ref "$SHA" --name "$GL_TITLE" --notes-file "$GL_NOTEFILE" "${GL_ARGS[@]}" >/dev/null 2>&1 \
         && nt glab release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s CREATED\n' "$spec"
        [ "$PRERELEASE" -eq 1 ] && gl_readback "$spec" "$target"
      else fail "RELEASE $spec create failed"; fi ;;
    gitea)
      base="${target%:*}"; repo="${target##*:}"
      args=(--tag "$TAG" --notes-file "$NOTES" --title "$PRE_TITLE" --base-url "$base" --repo "$repo")
      [ "$PRERELEASE" -eq 1 ] && args+=(--prerelease)
      # The publisher has its own network timeouts (pub, above). Only its own
      # "release_publish_gitea: " lines are printed (any other line could come from curl or git).
      x_gitea="$(pub "${args[@]}" 2>&1 >/dev/null)"; rc=$?
      gmsg="$(own1 "$x_gitea" 200)"; [ -n "$gmsg" ] || gmsg="(no message of the publisher's own)"
      # rc 3 is a GAP only when the publisher says SKIPPED-NO-TOKEN (no credential); every other rc 3
      # (bad token charset, jq/curl missing, tag absent, no notes) is a configuration failure (review m-9)
      case "$rc" in
        0) printf 'RELEASE %s CREATED-OR-UPDATED\n' "$spec" ;;
        3) if printf '%s\n' "$x_gitea" | grep -q '^SKIPPED-NO-TOKEN:'; then gap "RELEASE $spec SKIPPED-NO-TOKEN (gitea token variable not set)"
           else fail "RELEASE $spec REFUSED rc=3 (configuration or precondition: $gmsg)"; fi ;;
        *) fail "RELEASE $spec failed rc=$rc: $gmsg" ;;
      esac ;;
  esac
done
for r in $REMOTES; do
  covered=0
  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do rr="${spec#*:}"; [ "${rr%%:*}" = "$r" ] && covered=1; done
  if [ "$covered" -eq 0 ]; then
    if [ -n "${OK[$r]:-}" ]; then printf 'INFO %s: tag pushed only (no platform release requested)\n' "$r"
    else printf 'INFO %s: no platform release requested; the push to this remote is NOT OK (see the lines above)\n' "$r"; fi
  fi
done

printf '== %s end\n' "$(date -Is)"
if [ "$FAILS" -gt 0 ]; then printf 'RESULT: FAIL fails=%d gaps=%d (re-run the same command to resume)\n' "$FAILS" "$GAPS"; exit 1; fi
if [ "$GAPS" -gt 0 ]; then printf 'RESULT: GAPS fails=0 gaps=%d\n' "$GAPS"; exit 5; fi
printf 'RESULT: OK fails=0 gaps=0\n'; exit 0
