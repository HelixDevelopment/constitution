#!/usr/bin/env bash
# install_constitution.sh — add or update the Helix Constitution in a project, as a git submodule at
# submodules/constitution, then optionally let an AI agent finish the wiring with the setup prompt.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   curl -fsSL <RAW_URL> | bash
#   curl -fsSL <RAW_URL> | bash -s -- --upstream gitlab --non-interactive --agent none
#   bash scripts/install_constitution.sh --help          (full flag list)
#   bash scripts/install_constitution.sh --print-snippets (the curl line for every upstream)
#
# ── Safety design ─────────────────────────────────────────────────────────
#   * Everything lives in functions; the LAST line calls main with a sentinel argument, and main refuses
#     to run without it. A truncated download therefore executes nothing (a prefix either fails to parse
#     or ends before main is called with the sentinel).
#   * Questions are read from /dev/tty, so `curl | bash` stays interactive. No TTY and no
#     --non-interactive => exit 2.
#   * Never pushes, never force-anything, never deletes a user file: every file it changes is first
#     copied to <project>/.constitution-install-backup/<stamp>/files/ (restore with --restore DIR);
#     leftovers of an interrupted run are MOVED into that backup, never deleted.
#   * Secrets: never printed, never stored; URLs carrying a password are skipped; the agent runs with
#     ANTHROPIC_API_KEY removed from its environment (native Claude accounts use CLAUDE_CONFIG_DIR).
#   * Refuses to run as root unless --yes.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 success · 1 failure · 2 usage / no TTY without --non-interactive · 3 precondition blocked
#   · 4 agent run failed · 5 verification failed · 130/143 interrupted (SIGINT/SIGTERM)
#
# Classification: universal (§11.4.17). Constitution anchors honoured: §11.4.113 (no force/push),
# §11.4.187 (stream-json result, never exit code), §11.4.287 (no recursive delete), §11.4.10 (secrets).
#
# This block must stay POSIX sh: when a non-bash shell runs the file it re-executes it under bash.
if [ -z "${BASH_VERSION:-}" ]; then
  # only a file named like the installer (…sh path) is re-executed: under `… | sh` $0 is the shell's own name,
  # and a file of that name in the current directory must never be run
  if case "$0" in *?.sh) true ;; *) false ;; esac && [ -f "$0" ] \
     && [ "$(tail -n 1 -- "$0" 2>/dev/null)" = 'main "$@" __helix_installer_eof__' ]; then
    echo "install_constitution.sh: not running under bash; re-executing under bash" >&2
    exec bash "$0" "$@"
  fi
  echo "install_constitution.sh: this installer needs bash and cannot re-execute a piped script." >&2
  echo "Run it as:  curl -fsSL <url> | bash -s -- [flags]" >&2
  exit 2
fi

HI_SOURCED=0; (return 0 2>/dev/null) && HI_SOURCED=1   # 1 only when this file is sourced (tests), never when run
HI_VERSION="1.0.0"
HI_SUB="submodules/constitution"
HI_LEGACY="constitution"
HI_BACKUP_ROOT=".constitution-install-backup"
HI_MARK_BEGIN="<!-- BEGIN helix-constitution-inheritance (written by install_constitution.sh; keep this block) -->"
HI_MARK_END="<!-- END helix-constitution-inheritance -->"

# ───────────────────────────── data ─────────────────────────────
# key|raw installer URL ("-" = none)|https clone URL|ssh clone URL
hi_upstream_table() {
  cat <<'EOF'
github|https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh|https://github.com/HelixDevelopment/HelixConstitution.git|git@github.com:HelixDevelopment/HelixConstitution.git
gitlab|https://gitlab.com/helixdevelopment1/helixconstitution/-/raw/main/scripts/install_constitution.sh|https://gitlab.com/helixdevelopment1/helixconstitution.git|git@gitlab.com:helixdevelopment1/helixconstitution.git
gitlab-vasic|https://gitlab.com/vasic-digital/HelixConstitution/-/raw/main/scripts/install_constitution.sh|https://gitlab.com/vasic-digital/HelixConstitution.git|git@gitlab.com:vasic-digital/HelixConstitution.git
gitflic|https://gitflic.ru/project/helixdevelopment/helixconstitution/blob/raw?file=scripts/install_constitution.sh&branch=main|https://gitflic.ru/project/helixdevelopment/helixconstitution.git|git@gitflic.ru:helixdevelopment/helixconstitution.git
gitverse|https://gitverse.ru/api/repos/helixdevelopment/HelixConstitution/raw/branch/main/scripts/install_constitution.sh|https://gitverse.ru/helixdevelopment/HelixConstitution.git|git@gitverse.ru:helixdevelopment/HelixConstitution.git
github-vasic|-|https://github.com/vasic-digital/HelixConstitution.git|git@github.com:vasic-digital/HelixConstitution.git
EOF
}
# id|tier — agents the installer looks for; drivable = can run the setup prompt headlessly.
hi_agent_table() {
  cat <<'EOF'
claude|drivable
kimi|drivable
opencode|drivable
pi|drivable
aider|detect-only
codex|detect-only
gemini|detect-only
qwen|detect-only
cursor-agent|detect-only
amp|detect-only
goose|detect-only
EOF
}

hi_print_snippets() {
  local raw
  while IFS='|' read -r _ raw _ _; do
    [ "$raw" = "-" ] && continue
    printf "curl -fsSL '%s' | bash\n" "$raw"
  done < <(hi_upstream_table)
}

hi_help() {
  cat <<'HELIX_HELP'
install_constitution.sh — add or update the Helix Constitution (git submodule at submodules/constitution).

Usage:  curl -fsSL <RAW_URL> | bash -s -- [flags]      or      bash install_constitution.sh [flags]
Flags take `--flag value` or `--flag=value`; a lone `--` ends the flags. Needs bash >= 4.4 and git.

Flags:
  --project-root DIR        project to install into (default: current directory)
  --upstream KEY            github (default) | gitlab | gitlab-vasic | gitflic | gitverse | github-vasic;
                            unreachable upstreams fall back to the next one
  --upstream-url URL        explicit clone URL (repeatable; tried in order; replaces the table);
                            http:// and git:// URLs are refused unless --allow-insecure-url
  --allow-insecure-url      accept http:// and git:// upstream URLs (unauthenticated transport)
  --allow-unrestricted-agent
                            required to run kimi, opencode or pi: those agents run with THEIR OWN default
                            permissions (they can run shell commands, edit files and reach the network in
                            the project directory); the installer has no verified option to restrict them.
                            Without this flag --non-interactive refuses them (exit 3); interactively a
                            separate question asks (default no). The report records the choice.
                            claude, claudeN and provider aliases do not need it: they run with
                            --permission-mode acceptEdits and --disallowedTools with a deny list of
                            web tools and git push forms (printed in the plan), never
                            --dangerously-skip-permissions.
                            "The agent never pushes" rests on three things: the prompt rules, that deny
                            list (passed as documented by claude --help; whether claude enforces every
                            form was NOT checked by a live run: UNCONFIRMED), and a check after the run:
                            a new "update by push" reflog entry on any remote-tracking ref of the project
                            or the constitution fails the run (exit 5), and so does a change of the
                            refs a configured remote advertises (full git ls-remote: branches, TAGS,
                            refs/notes/... and every other namespace, before and after, for the project
                            and the constitution; project paths with spaces are handled), and so does
                            a remote-tracking ref that is new or moved with no fetch in its reflog (a
                            push with reflogs off), and so does a remote removed during the run (or
                            renamed), and every url and pushurl a remote had before the run is asked
                            again by URL afterwards (a push followed by removing or re-pointing the
                            remote, a push through a pushurl). LIMITS (not detected): a push by URL to a remote
                            that is not configured (or added during the run) which updates no tracking
                            ref; a push to a repository other than the project and the constitution;
                            a push the remote reverses before the second look. A remote (or url) that
                            answered before the run and cannot be asked after it fails the run (like a
                            removed remote); only one that could not be asked before the run either is
                            skipped, and it is named. The remote comparison fingerprints what each remote
                            advertises with sha256sum (cksum as the fallback); when NEITHER sha256sum nor cksum
                            is on PATH the check fails closed and the run is refused. Somebody else's push
                            during the run is a false positive
                            (refused). The deny list also covers gh, glab, curl and wget, but forge
                            APIs reachable through other tools (python, node, ssh ...) are NOT blocked
                            by it: the post-run check above is the backstop, and it has the limits
                            listed. SIGNALS: INT/TERM are acted on when the foreground step ends (bash
                            defers traps while a child runs): a long git
                            clone is cut off by its own timeout, an agent is stopped at once.
  --ssh                     use SSH clone URLs from the table instead of HTTPS
  --ref REF                 tag/branch/commit (default: newest helixconstitution-v* tag, else main)
  --agent ID|none           agent that runs the setup prompt: claude, claudeN, a provider alias, kimi,
                            opencode, pi (default: none)
  --model M                 agent model (default: sonnet)          \  claude, claudeN and provider aliases only;
  --effort E                low|medium|high|xhigh|max (default: medium) > not enforced for kimi/opencode/pi: the
  --max-budget-usd N        TOTAL spending cap, USD, > 0 and <= 50  /  flag is refused (exit 2) for those agents
                            (default: 2). The setup run gets N; each follow-up gets what is left, computed
                            from the total_cost_usd the agent reports. If a run reports no cost the remainder
                            cannot be tracked: each later follow-up then gets N again, so the worst case is
                            (1 + number of follow-ups) x N (the installer says so when it happens).
  --timeout-sec N           wall-clock limit per agent run, 1..86400 (default: 1800); enforced for every agent
  --followups on|off        run docs/prompts/setup/followups/*.md in the same session (default: off)
  --decision-layer off|shadow|enforce   Jev decision layer (default: off)
  --edit-agent-docs on|off  write the inheritance block into CLAUDE.md/AGENTS.md (default: on)
  --register-hooks on|off   allow the agent to register hooks in .claude/settings.json (default: off)
  --run-setup on|off        run submodules/constitution/scripts/setup.sh after adding (default: on)
  --commit on|off           commit the result locally (default: off; the installer never pushes)
  --git-init                consent to `git init` when the directory is not a git repository
  --not-constitution-repo   the project has its own Constitution.md and is NOT the constitution repository:
                            skips only the heuristic self-checks (the constitution marker files; a shallow clone
                            with Constitution.md). A repository whose history starts with the constitution's first
                            commit, or whose remote is a known constitution upstream, is refused regardless.
  --dry-run                 print the full plan; write nothing
  --non-interactive         never ask; use flags and defaults
  --yes                     allow running as root; skip the final confirmation
  --report-json FILE        also write the report to FILE
  --restore DIR             copy the files saved in a backup directory back into the project. DIR must be a
                            backup directly inside .constitution-install-backup/, owned by you, mode 700 and
                            not tracked by git; entries under .git/, constitution/, submodules/constitution/,
                            absolute paths and ".." segments are skipped, as is anything through a symlink
  --detect-agents [--json]  list detected agents and exit (read-only)
  --detect-layout           print none|standard|legacy|both|partial|inconsistent|constitution-repo, exit (read-only)
  --print-snippets          print the curl one-liner for every upstream and exit
  --version | --help

Exit codes: 0 ok · 1 failure · 2 usage/no TTY/insecure URL/limit an agent cannot enforce/--agent <number> · 3
precondition blocked (also: the target is the constitution repository itself, a core tool is missing, a git call
was not on the allow-list) · 4 agent failed · 5 verification failed · 6 agent ran but its success is UNVERIFIED (opencode, pi:
exit code only, no result event to read) · 130/143 interrupted
The installer never pushes. Every changed file is backed up under .constitution-install-backup/ (mode 700;
agent transcripts and reports inside are mode 600). The constitution is cloned blobless (full commit
history and tags, file contents fetched on demand); a server without partial-clone support gets a full clone.
git runs with a sanitised environment: inherited GIT_* variables are dropped (except the config-file selection,
author/committer identity, CA bundle and protocol limits) and ssh is always "ssh -o BatchMode=yes -o
ConnectTimeout=10" (put ssh keys/ports in ~/.ssh/config). URLs are shown with credentials removed and every
query value replaced by REDACTED; a URL carrying a password or a token query is never used for probing.
HELIX_HELP
}

# ───────────────────────────── output ─────────────────────────────
# >>> hi_text_safe (identical in install_constitution.sh and update_constitution.sh)
# THE sanitiser for every byte this script did not write itself: text from git (log subjects, tag and branch
# names), from the agent, from the project's own paths, from an upstream CHANGELOG. Nothing external is printed
# raw: the emitters (hi_say/hi_warn/hi_err/hi_out, say/die) call it, and tests/install/test_unit.sh fails on a
# print site that does not go through an emitter. It keeps printable text (tab and newline too) and drops every
# control character (C0, DEL, C1), every format character (bidi controls such as U+061C, U+200E/F, U+202A-E,
# U+2066-9), the line and paragraph separators U+2028/2029 and private-use, unassigned and surrogate code
# points. Invalid UTF-8 (a raw 0x9B is a one-byte CSI to some terminals) becomes "?". Without python3 only
# printable ASCII survives. Output of child processes (setup.sh, the updater, the agent's own terminal) is
# theirs and is not filtered.
hi_text_filter() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import sys, unicodedata
t = sys.stdin.buffer.read().decode("utf-8", "replace").replace("�", "?")
sys.stdout.buffer.write("".join(c for c in t if c in "\t\n" or unicodedata.category(c) not in ("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp")).encode("utf-8"))
'
  else
    LC_ALL=C tr -cd '\11\12\40-\176'
  fi
}
hi_term_safe() { printf '%s' "$1" | hi_text_filter; }
# <<< hi_text_safe
hi_say()  { printf '[constitution] %s\n' "$(hi_term_safe "$*")" >&2; }
hi_warn() { printf '[constitution] WARN: %s\n' "$(hi_term_safe "$*")" >&2; }
hi_err()  { printf '[constitution] ERROR: %s\n' "$(hi_term_safe "$*")" >&2; }
hi_out()  { local f="$1"; shift; printf "$f" "$@" | hi_text_filter >&7; }   # the terminal (fd 7): questions and menus
# hi_scrub (a text stream) and hi_sanitize_url (one URL) hide credentials before anything is shown or stored:
# the userinfo of an http(s) URL, and of any other scheme when it carries a ":password", is removed up to the LAST
# "@" before the path (a password may itself contain "@"); every query-string value becomes REDACTED.
hi_scrub() {
  sed -E 's#([Hh][Tt][Tt][Pp][Ss]?://)[^/?#[:space:]]*@#\1#g; s#([A-Za-z][A-Za-z0-9+.-]*://)[^/?#[:space:]@:]*:[^/?#[:space:]]*@#\1#g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\1REDACTED/g'
}

hi_json_str() {
  local s="$1" out="" c i
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/\\r}
  if [[ "$s" =~ [[:cntrl:]] ]]; then
    for ((i=0; i<${#s}; i++)); do
      c="${s:i:1}"
      if [[ "$c" =~ [[:cntrl:]] ]]; then printf -v c '\\u%04x' "'$c"; fi
      out+="$c"
    done
    s="$out"
  fi
  printf '"%s"' "$s"
}

hi_sanitize_url() {
  local u="$1" scheme rest auth path q out="" kv
  if [[ "$u" =~ ^([A-Za-z][A-Za-z0-9+.-]*://)(.*)$ ]]; then
    scheme="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    auth="${rest%%[/?#]*}"; path="${rest:${#auth}}"
    if [[ "$auth" == *@* ]]; then
      if [[ "$scheme" =~ ^[Hh][Tt][Tt][Pp][Ss]?://$ ]] || [[ "${auth%@*}" == *:* ]]; then auth="${auth##*@}"; fi
    fi
    u="$scheme$auth$path"
  fi
  if [[ "$u" == *\?* ]]; then # every query value is redacted (tokens travel there: ?private_token=…, ?access_token=…)
    q="${u#*\?}"; u="${u%%\?*}"
    local frag=""; [[ "$q" == *#* ]] && { frag="#${q#*#}"; q="${q%%#*}"; }
    local -a kvs=(); IFS='&' read -r -a kvs <<<"$q"
    for kv in ${kvs[@]+"${kvs[@]}"}; do
      [[ "$kv" == *=* ]] && kv="${kv%%=*}=REDACTED"
      out="${out:+$out&}$kv"
    done
    u="$u?$out$frag"
  fi
  printf '%s' "$u"
}
hi_url_has_password() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/?#@]*:[^/?#]*@ ]] || [[ "$1" =~ ^[Hh][Tt][Tt][Pp][Ss]?://[^/?#]+@ ]] && return 0
  local lc; lc="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  [[ "$lc" =~ [?\&](private_token|access_token|token|oauth_token|password|passwd|pwd|secret|api_key|apikey|key|auth|sig|signature|x-oauth-basic)= ]]
}

# ───────────────────────────── git (allow-listed) ─────────────────────────────
# >>> hi_gx — the ONLY code in this file that runs git (CM-INSTALLER-NO-PUSH-NO-FORCE). This block is byte-identical
# in install_constitution.sh and update_constitution.sh; the gate compares the two copies, extracts the allow-list
# below and calls the wrapper with every forbidden form to prove it refuses at RUNTIME.
#   hi_gx [-C DIR] [-c protocol.file.allow=always] [--no-optional-locks] SUBCOMMAND ARGS...
# The check sees the words git would see, however the call was spelled (${P}ush, $'\x70ush', p\ush all arrive as
# "push"), so anything not listed is refused with exit 3 and a message. Subcommands that reach a remote or change
# refs/config are allowed ONLY in the exact shapes the two scripts use (fetch --quiet --tags REMOTE, clone --quiet
# [--filter=blob:none] --no-checkout -- URL DIR, …); a word starting with "+" (a forced refspec) or containing "::"
# (a transport helper such as ext::) is refused wherever it stands, also after "--". git itself is resolved ONCE to
# an absolute path (hi_gx_bin) and runs with a sanitised environment: every inherited GIT_* variable is removed
# except the user's config-file selection, author/committer identity, CA bundle and protocol restrictions, and
# GIT_SSH_COMMAND is always the installer's own non-interactive ssh. Options: HI_GX_TIMEOUT=N (seconds, via
# timeout); HI_GX_COMMIT_OK=1 (set once, only when a commit was asked for); HI_GX_INIT_OK=1 (only after consent).
hi_gx_refuse() {
  local m; m="$(printf '%s ' "$@" | sed -E 's|(://)[^/?#[:space:]]*@|\1|g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\1REDACTED/g' | LC_ALL=C tr -cd '\40-\176')"
  if { true >&9; } 2>/dev/null; then printf '[git-allowlist] ERROR: refused git call (not on the allow-list): %s\n' "$m" >&9
  else printf '[git-allowlist] ERROR: refused git call (not on the allow-list): %s\n' "$m" >&2; fi
  return 3
}
hi_gx_repo_ok() { case "$1" in ""|-*|+*|*::*) return 1 ;; esac; return 0; }   # a URL/path/remote word
hi_gx_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]; }              # a remote name
hi_gx_check() { # SUBCOMMAND ARGS... → 0 allowed, 3 refused (read-only; never runs git)
  local sub="${1:-}" a cached=0 dd=0; [ $# -gt 0 ] && shift
  local -a c=()
  for a in "$@"; do # every word, also after "--": no forced refspec, no transport helper
    case "$a" in +*|*::*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac
  done
  for a in "$@"; do # options that rewrite history, discard work, move refs, run commands or write outside the repo
    [ "$a" = -- ] && break
    case "$a" in
      --force|--force=*|--force-*|--amend|--hard|--mirror|--delete|--prune|--prune=*|--prune-tags|--upload-pack*|\
      --receive-pack*|--exec|--exec=*|--output|--output=*|--ext-diff|--template|--template=*|--config|--config=*|\
      --recurse-submodules*|--recursive|--refmap*|--update-head-ok|--separate-git-dir*|--reference*|--shared|\
      --fixup*|--squash*|--orphan*)
        hi_gx_refuse "$sub" "$@"; return 3 ;;
      -[A-Za-z]*) [ "$sub" = config ] && [ "$a" = -f ] && continue
        case "$a" in -*[fuc]*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac ;;
    esac
  done
  case "$sub" in
    rev-parse|rev-list|ls-files|ls-tree|status|show|log|diff|merge-base|for-each-ref|cat-file|check-ref-format) return 0 ;; # HI_GX_ALLOW
    fetch) # HI_GX_ALLOW — only: fetch --quiet --tags REMOTE-NAME (default refspec: remote-tracking refs and tags only)
      [ $# = 3 ] && [ "$1" = --quiet ] && [ "$2" = --tags ] && hi_gx_name_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    clone) # HI_GX_ALLOW — only: clone --quiet [--filter=blob:none] --no-checkout -- URL DIR
      c=("$@"); [ "${c[1]:-}" = --filter=blob:none ] && c=("${c[0]}" "${c[@]:2}")
      [ "${#c[@]}" = 5 ] && [ "${c[0]}" = --quiet ] && [ "${c[1]}" = --no-checkout ] && [ "${c[2]}" = -- ] \
        && hi_gx_repo_ok "${c[3]}" && hi_gx_repo_ok "${c[4]}" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    ls-remote) # HI_GX_ALLOW — only: ls-remote [--tags|--heads] [--] REPO [PATTERN]
      c=("$@"); case "${c[0]:-}" in --tags|--heads) c=("${c[@]:1}") ;; esac
      [ "${c[0]:-}" = -- ] && c=("${c[@]:1}")
      [ "${#c[@]}" -ge 1 ] && [ "${#c[@]}" -le 2 ] && hi_gx_repo_ok "${c[0]}" && hi_gx_repo_ok "${c[1]:-x}" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    add) # HI_GX_ALLOW — only: add -- PATH...
      [ $# -ge 2 ] && [ "$1" = -- ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    checkout) # HI_GX_ALLOW — only: checkout [-q|--quiet] --detach <full commit sha>
      [ $# -ge 2 ] && [[ "${!#}" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && [[ " $* " == *" --detach "* ]] || { hi_gx_refuse "$sub" "$@"; return 3; }
      for a in "${@:1:$(($# - 1))}"; do case "$a" in -q|--quiet|--detach) ;; *) hi_gx_refuse "$sub" "$@"; return 3 ;; esac; done
      return 0 ;;
    rm) # HI_GX_ALLOW — only: rm [-q] --cached [--ignore-unmatch] -- PATH... (the files stay)
      for a in "$@"; do
        [ "$dd" = 1 ] && continue
        case "$a" in --) dd=1 ;; --cached) cached=1 ;; -q|--quiet|--ignore-unmatch) ;; *) hi_gx_refuse "$sub" "$@"; return 3 ;; esac
      done
      [ "$cached" = 1 ] && [ "$dd" = 1 ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    config) # HI_GX_ALLOW — reads; writes only the installer marker and submodule.* sections
      c=("$@"); if [ "${c[0]:-}" = -f ]; then [ "${#c[@]}" -ge 3 ] || { hi_gx_refuse "$sub" "$@"; return 3; }; c=("${c[@]:2}"); fi
      case "${c[0]:-}" in
        --get|--get-all|--get-regexp|--list) return 0 ;;
        --remove-section) [ "${#c[@]}" = 2 ] && [[ "${c[1]}" == submodule.* ]] && return 0 ;;
        --unset) [ "${#c[@]}" = 2 ] && [ "${c[1]}" = helix-installer.clone ] && return 0 ;;
        helix-installer.clone) [ "${#c[@]}" = 2 ] && [ "${c[1]}" = true ] && return 0 ;;
      esac
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    remote) # HI_GX_ALLOW — only: remote | remote get-url NAME | remote set-url origin /ABSOLUTE/PATH
      [ $# = 0 ] && return 0
      [ "$1" = get-url ] && [ $# = 2 ] && hi_gx_name_ok "$2" && return 0
      [ "$1" = set-url ] && [ $# = 3 ] && [ "$2" = origin ] && [[ "$3" == /* ]] && hi_gx_repo_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    submodule) # HI_GX_ALLOW — only: add --quiet -- URL PATH | update --init --quiet -- PATH | absorbgitdirs -- PATH
      [ "${1:-}" = add ] && [ $# = 5 ] && [ "$2" = --quiet ] && [ "$3" = -- ] && hi_gx_repo_ok "$4" && hi_gx_repo_ok "$5" && return 0
      [ "${1:-}" = update ] && [ $# = 5 ] && [ "$2" = --init ] && [ "$3" = --quiet ] && [ "$4" = -- ] && hi_gx_repo_ok "$5" && return 0
      [ "${1:-}" = absorbgitdirs ] && [ $# = 3 ] && [ "$2" = -- ] && hi_gx_repo_ok "$3" && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    commit) # HI_GX_ALLOW (only after --commit) — only: commit -q -m MESSAGE -- PATH...
      [ "${HI_GX_COMMIT_OK:-0}" = 1 ] && [ $# -ge 5 ] && [ "$1" = -q ] && [ "$2" = -m ] && [ "$4" = -- ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    init) # HI_GX_ALLOW (only after consent) — only: init -q
      [ "${HI_GX_INIT_OK:-0}" = 1 ] && [ $# = 1 ] && [ "$1" = -q ] && return 0
      hi_gx_refuse "$sub" "$@"; return 3 ;;
    *) hi_gx_refuse "$sub" "$@"; return 3 ;;
  esac
}
hi_gx_bin() { # git resolved ONCE to an absolute path: a later PATH change cannot swap the binary
  [ -n "${HI_GX_BIN:-}" ] && return 0
  HI_GX_BIN="$(command -v git 2>/dev/null)"
  [[ "$HI_GX_BIN" == /* ]] && [ -x "$HI_GX_BIN" ] && return 0
  HI_GX_BIN=""; hi_gx_refuse "(git is not installed as an executable file on PATH)"; return 3
}
hi_gx() {
  local -a pre=(); local v
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) [ $# -ge 2 ] || { hi_gx_refuse "$@"; return 3; }; pre+=(-C "$2"); shift 2 ;;
      -c) [ "${2:-}" = protocol.file.allow=always ] || { hi_gx_refuse "$@"; return 3; }; pre+=(-c "$2"); shift 2 ;;
      --no-optional-locks) pre+=("$1"); shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { hi_gx_refuse "(no subcommand)"; return 3; }
  hi_gx_check "$@" || return 3
  hi_gx_bin || return 3
  ( # sanitised environment, in a subshell (the caller's variables stay as they are)
    for v in ${!GIT_*}; do
      case "$v" in
        GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_CEILING_DIRECTORIES|GIT_AUTHOR_*|GIT_COMMITTER_*|\
        GIT_SSL_CAINFO|GIT_SSL_CAPATH|GIT_ALLOW_PROTOCOL|GIT_PROTOCOL_FROM_USER) ;;
        *) unset "$v" ;;
      esac
    done
    export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
    if [ -n "${HI_GX_TIMEOUT:-}" ]; then exec timeout "$HI_GX_TIMEOUT" "$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"
    else exec "$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"; fi
  )
}
# <<< hi_gx

# ───────────────────────────── validators ─────────────────────────────
hi_validate_agent_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; }
hi_validate_model()    { [[ "$1" =~ ^[A-Za-z0-9][]A-Za-z0-9._:/[-]{0,127}$ ]]; }
hi_validate_effort()   { case "$1" in low|medium|high|xhigh|max) return 0 ;; esac; return 1; }
hi_validate_number()   { [[ "$1" =~ ^[0-9]{1,6}(\.[0-9]{1,4})?$ ]]; }
hi_validate_uint()     { [[ "$1" =~ ^[0-9]{1,6}$ ]]; }
# One validator per limit, shared by the flag path and the interactive questions.
HI_MAX_TIMEOUT=86400   # 24 h per agent run
HI_MAX_BUDGET=50       # USD, total across the setup run and its follow-ups
hi_validate_timeout()  { hi_validate_uint "$1" && [ "$((10#$1))" -gt 0 ] && [ "$((10#$1))" -le "$HI_MAX_TIMEOUT" ]; }
hi_validate_budget()   { hi_validate_number "$1" && awk -v v="$1" -v m="$HI_MAX_BUDGET" 'BEGIN { exit !(v + 0 > 0 && v + 0 <= m) }'; }
# bash < 4.4 treats "${arr[@]}" of an EMPTY array as an unbound variable under `set -u`; require 4.4.
hi_bash_ok() { [ "$1" -gt 4 ] || { [ "$1" -eq 4 ] && [ "$2" -ge 4 ]; }; }
hi_validate_onoff()    { case "$1" in on|off) return 0 ;; esac; return 1; }
hi_validate_path()     { [ -n "$1" ] && [[ "$1" != *$'\n'* ]] && [[ "$1" != -* ]]; }
hi_validate_ref() {
  local r="$1"
  [ -n "$r" ] && [[ "$r" != -* ]] && [[ "$r" =~ ^[A-Za-z0-9._/-]{1,200}$ ]] || return 1
  [[ "$r" =~ ^[0-9a-f]{7,40}$ ]] && return 0
  hi_gx check-ref-format --allow-onelevel "$r" >/dev/null 2>&1
}
hi_validate_url() {
  local u="$1"
  [ -n "$u" ] && [[ "$u" != -* ]] && [[ "$u" != *::* ]] || return 1
  [[ "$u" =~ ^[A-Za-z0-9._~:/@%+=-]+$ ]] || return 1
  [[ "$u" =~ ^(https?|ssh|git|file)://[A-Za-z0-9] ]] && return 0
  [[ "$u" =~ ^file:///[A-Za-z0-9._~/-] ]] && return 0
  [[ "$u" =~ ^/[A-Za-z0-9._~/-]* ]] && [[ "$u" != *:* ]] && return 0
  [[ "$u" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[A-Za-z0-9._~/][A-Za-z0-9._~/-]*$ ]] && return 0
  return 1
}

# ───────────────────────────── text helpers ─────────────────────────────
# First fenced block under the `## PROMPT` heading; fence = 3+ backticks/tildes; inner shorter fences kept.
hi_extract_prompt() {
  awk '
    BEGIN { st = 0; got = 0 }
    st == 0 && /^## PROMPT[[:space:]]*$/ { st = 1; next }
    st == 1 && /^## / { exit }
    st == 1 && match($0, /^(```+|~~~+)/) { fch = substr($0, 1, 1); flen = RLENGTH; st = 2; next }
    st == 2 {
      line = $0; sub(/[[:space:]]+$/, "", line)
      if (length(line) >= flen && substr(line, 1, 1) == fch) {
        rest = line; if (fch == "`") gsub(/`/, "", rest); else gsub(/~/, "", rest)
        if (rest == "") { got = 1; exit }
      }
      print; n++
    }
    END { exit (got && n > 0) ? 0 : 1 }
  ' "$1"
}
hi_followup_body() {
  awk 'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next } fm == 1 { if (/^---[[:space:]]*$/) fm = 2; next } { print }' "$1"
}
hi_followup_requires() {
  local v
  v="$(awk 'NR == 1 && !/^---[[:space:]]*$/ { exit } NR > 1 && /^---[[:space:]]*$/ { exit }
           NR > 1 && /^requires_previous_success:/ { sub(/^requires_previous_success:[[:space:]]*/, ""); print; exit }' "$1")"
  case "$v" in false|False|no) printf 'false' ;; *) printf 'true' ;; esac
}
# Release tags only: helixconstitution-vN(.N)*, no part with a leading zero (v072, v72.01 are not releases).
# Pre-release tags (-rc1, -beta, ...) are never chosen by default (pin one with --ref). Version order (sort -V),
# so v9 < v10 < v100. This is the SAME regex as the setup prompt (docs/prompts/setup/latest.md) and the updater;
# tests/install/test_unit.sh fails if the three drift apart.
HI_RELEASE_TAG_RE='^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$'
# stdin: `git ls-remote --tags` output → newest release tag name
hi_newest_tag() {
  awk '{ r = $2; sub(/^refs\/tags\//, "", r); sub(/\^\{\}$/, "", r); print r }' \
    | grep -E "$HI_RELEASE_TAG_RE" | sort -u | sort -V | tail -n 1
}
# stream-json → "result=success|failure|none session=<id> rate_limited=0|1 cost=<usd>|unknown"; success ONLY
# from the last result event with is_error=false and subtype=success; the process exit code is never consulted.
# cost = total_cost_usd of the last result event (UNCONFIRMED whether a resumed session reports the cost of
# that invocation or a running total; summing it per run can only over-count, so the budget stays safe).
hi_parse_stream() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$1" <<'PY'
import json, re, sys
res, sid, rl, cost = "none", "", 0, "unknown"
pat = re.compile(r'"api_?[eE]rror_?[sS]tatus"\s*:\s*429')
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if pat.search(line): rl = 1
        try: e = json.loads(line)
        except Exception: continue
        if not isinstance(e, dict): continue
        if e.get("type") == "system" and e.get("subtype") == "init" and not sid:
            sid = str(e.get("session_id") or "")
        if e.get("type") == "result":
            res = "success" if (e.get("is_error") is False and e.get("subtype") == "success") else "failure"
            rsid = str(e.get("session_id") or "")
            if not sid: sid = rsid
            c = e.get("total_cost_usd")
            cost = (("%.6f" % c).rstrip("0").rstrip(".") or "0") if isinstance(c, (int, float)) and not isinstance(c, bool) and c >= 0 else "unknown"
print("result=%s session=%s rate_limited=%d cost=%s" % (res, sid, rl, cost))
PY
  elif command -v jq >/dev/null 2>&1; then
    local rl=0
    grep -Eq '"api_?[eE]rror_?[sS]tatus"[[:space:]]*:[[:space:]]*429' "$1" && rl=1
    jq -n -R -r --arg rl "$rl" '[inputs | fromjson? | select(type=="object")] as $e
      | ($e | map(select(.type=="system" and .subtype=="init")) | (.[0].session_id // "")) as $s0
      | ($e | map(select(.type=="result")) | last) as $r
      | (if $r == null then "none" elif ($r.is_error == false and $r.subtype == "success") then "success" else "failure" end) as $res
      | (if $s0 != "" then $s0 else ($r.session_id // "") end) as $sid
      | (if ($r != null and ($r.total_cost_usd | type) == "number" and $r.total_cost_usd >= 0) then ($r.total_cost_usd | tostring) else "unknown" end) as $cost
      | "result=\($res) session=\($sid) rate_limited=\($rl) cost=\($cost)"' "$1" \
      | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^cost=[0-9.]+([eE][-+]?[0-9]+)?$/) {   # jq prints 1e-05: normalise
                 v = sprintf("%.6f", substr($i, 6) + 0); sub(/0+$/, "", v); sub(/\.$/, "", v); $i = "cost=" v }
             print }'
  else
    return 1
  fi
}
hi_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  else python3 -I -c 'import uuid; print(uuid.uuid4())'; fi
}

# ───────────────────────────── detection ─────────────────────────────
hi_version_of() { # path → first line of `--version`, run from / with a 5 s limit
  local v
  v="$(cd / && timeout 5 "$1" --version </dev/null 2>&1 | head -n 1)"
  v="${v//[[:cntrl:]]/}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "${v:0:120}"
}
# lines: id|kind|tier|installed|path|version|status
hi_detect_agents() {
  local id tier p v cl cv a st
  while IFS='|' read -r id tier; do
    p="$(command -v "$id" 2>/dev/null)"; v=""
    if [ -n "$p" ]; then v="$(hi_version_of "$p")"; printf '%s|binary|%s|true|%s|%s|ok\n' "$id" "$tier" "$p" "$v"
    else printf '%s|binary|%s|false|||absent\n' "$id" "$tier"; fi
  done < <(hi_agent_table)
  cl="$(command -v claude 2>/dev/null)"; cv=""; [ -n "$cl" ] && cv="$(hi_version_of "$cl")"
  if command -v claude-list-accounts >/dev/null 2>&1; then
    timeout 20 claude-list-accounts 2>/dev/null </dev/null | awk '$1 ~ /^claude[0-9]+$/ { print $1 "|" $3 }' | sort -u \
      | while IFS='|' read -r a st; do
          printf '%s|native-alias|drivable|%s|%s|%s|creds:%s\n' "$a" "$([ -n "$cl" ] && echo true || echo false)" "$cl" "$cv" "${st:-?}"
        done
  fi
  if [ "${HI_DETECT_PROVIDERS:-1}" = 1 ] && command -v claude-providers >/dev/null 2>&1; then
    timeout 20 claude-providers list 2>/dev/null </dev/null | awk '
      /^##/ { exit } NR == 1 { next } NF >= 3 && $1 ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { print $1 "|" $3 }' \
      | while IFS='|' read -r a st; do
          hi_validate_agent_id "$a" || continue
          printf '%s|provider-alias|drivable|%s|%s|%s|%s\n' "$a" "$([ -n "$cl" ] && echo true || echo false)" "$cl" "$cv" "$st"
        done
  fi
}
hi_detect_agents_json() {
  local first=1 id kind tier inst p v st
  printf '['
  while IFS='|' read -r id kind tier inst p v st; do
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"id":%s,"kind":%s,"tier":%s,"installed":%s,"path":%s,"version":%s,"status":%s}' \
      "$(hi_json_str "$id")" "$(hi_json_str "$kind")" "$(hi_json_str "$tier")" "$inst" \
      "$(hi_json_str "$p")" "$(hi_json_str "$v")" "$(hi_json_str "$st")"
  done < <(hi_detect_agents)
  printf ']\n'
}
# layout of a project: none|standard|legacy|both|partial|inconsistent
# A gitlink counts as the standard layout only when .gitmodules registers it too: `git submodule add`
# stages the gitlink BEFORE it writes .gitmodules, so an interrupt in between leaves a staged gitlink with
# no entry (partial, recoverable). The same gap in a COMMITTED gitlink is the user's own state
# (inconsistent): the installer refuses rather than guess.
hi_layout() {
  local r="$1" s=0 l=0
  if hi_gx -C "$r" ls-files -s -- "$HI_SUB" 2>/dev/null | grep -q '^160000 '; then
    if hi_gx -C "$r" config -f "$r/.gitmodules" --get "submodule.$HI_SUB.path" >/dev/null 2>&1; then s=1
    elif hi_gx -C "$r" ls-tree HEAD -- "$HI_SUB" 2>/dev/null | grep -q '^160000 '; then echo inconsistent; return
    else echo partial; return; fi
  fi
  hi_gx -C "$r" ls-files -s -- "$HI_LEGACY" 2>/dev/null | grep -q '^160000 ' && l=1
  if [ "$s" = 1 ] && [ "$l" = 1 ]; then echo both; return; fi
  [ "$s" = 1 ] && { echo standard; return; }
  [ "$l" = 1 ] && { echo legacy; return; }
  if [ -e "$r/$HI_SUB" ] || [ -d "$r/.git/modules/$HI_SUB" ] \
     || hi_gx -C "$r" config -f "$r/.gitmodules" --get "submodule.$HI_SUB.path" >/dev/null 2>&1; then
    echo partial; return; fi
  echo none
}

# ── the constitution repository itself is never a target ──
HI_FIRST_COMMIT="d31589a3bf76bdf0b50d24a1863605ff70881356"   # root commit of the constitution repository
hi_norm_url() { # url → host/path, lower case, no scheme/userinfo/port/.git/trailing or doubled slash (comparison only)
  local u h p; u="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  if [[ "$u" == *://* ]]; then
    u="${u#*://}"; h="${u%%/*}"; p="${u:${#h}}"
    h="${h##*@}"; h="${h%%:*}"          # userinfo ends at the LAST @ of the authority; the port goes
  else                                   # scp form [user@]host:path
    h="${u%%:*}"; p="/${u#*:}"; h="${h##*@}"
  fi
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  p="${p%/}"; p="${p%.git}"; p="${p%/}"
  printf '%s%s' "$h" "$p"
}
# Marker files of layer 1. Measured 2026-10-29 over all 977 commits of the constitution: the three are present in
# every commit that has Constitution.md (974), so old tags and shallow single-tag clones are recognised too.
HI_SELF_MARKERS="Constitution.md templates/Constitution.project.md.template templates/CLAUDE.project.md.template"
# DIR → 0 (and the reason on stdout) when DIR is the constitution repository.
#   Layer 1: the marker set at the root.                                         \ heuristic: --not-constitution-repo
#   Layer 1b: a SHALLOW clone with Constitution.md (layer 2 cannot see its root)  / overrides these two only
#   Layer 2: the constitution's first commit in HEAD history.                     \ strong: never overridden
#   Layer 3: a remote URL that is a known constitution upstream (port/userinfo/   /
#            case/trailing-slash/.git insensitive).
hi_is_constitution_repo() {
  local d="$1" r u n known m all=1
  if [ "${O_NOT_SELF:-0}" != 1 ]; then
    for m in $HI_SELF_MARKERS; do [ -f "$d/$m" ] || all=0; done
    if [ "$all" = 1 ]; then printf 'it has the constitution marker files (%s) at its root' "$HI_SELF_MARKERS"; return 0; fi
    if [ -f "$d/Constitution.md" ] && [ "$(hi_gx -C "$d" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
      printf 'it is a SHALLOW clone with Constitution.md at its root (its history cannot be checked); if this really is '
      printf 'a project that only USES the constitution, re-run with --not-constitution-repo'; return 0
    fi
  fi
  hi_gx -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  n="$(hi_gx -C "$d" rev-list --max-parents=0 HEAD 2>/dev/null | grep -cxF "$HI_FIRST_COMMIT")"   # count: no SIGPIPE
  if [ "${n:-0}" -gt 0 ]; then printf "its history starts with the constitution's first commit %s" "${HI_FIRST_COMMIT:0:12}"; return 0; fi
  known="$(hi_upstream_table | awk -F'|' '{ print $3; print $4 }' | while IFS= read -r u; do hi_norm_url "$u"; printf '\n'; done)"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    u="$(hi_gx -C "$d" remote get-url "$r" 2>/dev/null)" || continue
    if grep -qxF -- "$(hi_norm_url "$u")" <<<"$known"; then
      printf "its remote '%s' is a known constitution upstream (%s)" "$r" "$(hi_sanitize_url "$u")"; return 0
    fi
  done < <(hi_gx -C "$d" remote 2>/dev/null)
  return 1
}
# ───────────────────────────── state ─────────────────────────────
hi_init_state() {
  O_ROOT=""; O_UPSTREAM="github"; O_URLS=(); O_SSH=0; O_REF=""; O_AGENT=""; O_MODEL="sonnet"; O_EFFORT="medium"
  O_BUDGET="2"; O_TIMEOUT="1800"; O_FOLLOWUPS="off"; O_DECISION="off"; O_EDIT_DOCS="on"; O_HOOKS="off"
  O_SETUP="on"; O_COMMIT="off"; O_GIT_INIT=0; O_DRY=0; O_NONINT=0; O_YES=0; O_REPORT=""; O_RESTORE=""
  O_ACTION="install"; O_JSON=0; O_SET=" "; O_INSECURE=0; O_NOT_SELF=0; O_UNRESTRICTED=0; S_UNR_CONSENT=""
  S_MODE=""; S_URL=""; S_KEY=""; S_REF=""; S_BEFORE=""; S_AFTER=""; S_BK=""; S_STATUS="failure"; S_RC=1
  S_AGENT_STATUS="not-run"; S_SID=""; S_FOLLOW=(); S_VERIFY=(); S_VERIFY_OVERALL="skip"; S_CHANGED=(); S_PUSHED=0
  S_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; S_LOCK=""; S_WRITTEN=(); S_NOTES=(); S_UPDATER=""; S_CLONE=""
  S_SPENT="0"; S_COST_KNOWN=1; S_AGENT_EVIDENCE=""; S_MANIFEST=""
  # every other internal variable too: nothing the caller's environment holds under these names may steer a run
  S_LOCK_TMP=""; S_LOCK_RECLAIM=""; S_LAYOUT=""; S_SUBREL=""; S_TAGS=""; S_AGENT_LINE=""; S_TMP_PATHS=(); S_PRESTATUS=()
  HI_UMASK0=""; HI_AGENT_PID=""; HI_DETECT_PROVIDERS=1; HI_CLONE_TIMEOUT=1800
  if [ "${HELIX_INSTALLER_TEST:-}" = 1 ] && hi_validate_uint "${HELIX_INSTALLER_TEST_CLONE_TIMEOUT:-x}"; then   # test seam
    HI_CLONE_TIMEOUT="$HELIX_INSTALLER_TEST_CLONE_TIMEOUT"; fi
  HI_GX_COMMIT_OK=0; HI_GX_INIT_OK=0; HI_GX_BIN=""; unset HI_GX_TIMEOUT   # never inherited from the caller's environment
}
hi_set() { O_SET+="$1 "; }
hi_was_set() { [[ "$O_SET" == *" $1 "* ]]; }

hi_value_flag() {
  case "$1" in
    --project-root|--upstream|--upstream-url|--ref|--agent|--model|--effort|--max-budget-usd|--timeout-sec|\
    --followups|--decision-layer|--edit-agent-docs|--register-hooks|--run-setup|--commit|--report-json|--restore) return 0 ;;
  esac
  return 1
}
hi_parse_args() { # accepts `--flag value` and `--flag=value`; a lone `--` ends the flags (nothing may follow)
  local a v
  while [ $# -gt 0 ]; do
    a="$1"
    if [ "$a" = "--" ]; then
      shift
      [ $# -eq 0 ] || { hi_err "unexpected argument after --: $(printf '%q' "$1") (this installer takes flags only)"; return 2; }
      break
    fi
    if [[ "$a" == --*=* ]]; then
      v="${a#*=}"; a="${a%%=*}"
      hi_value_flag "$a" || { hi_err "$a does not take a value (see --help)"; return 2; }
      shift
    elif hi_value_flag "$a"; then
      [ $# -ge 2 ] || { hi_err "$a needs a value"; return 2; }
      v="$2"; shift 2
    else
      v=""; shift
    fi
    case "$a" in
      --project-root) hi_validate_path "$v" || { hi_err "invalid --project-root"; return 2; }; O_ROOT="$v" ;;
      --upstream) hi_upstream_table | cut -d'|' -f1 | grep -qxF -- "$v" || { hi_err "unknown --upstream (see --help)"; return 2; }; O_UPSTREAM="$v" ;;
      --upstream-url) hi_validate_url "$v" || { hi_err "invalid --upstream-url (allowed: https/http/ssh/git/file URLs, user@host:path, absolute paths)"; return 2; }; O_URLS+=("$v") ;;
      --ssh) O_SSH=1 ;;
      --ref) hi_validate_ref "$v" || { hi_err "invalid --ref"; return 2; }; O_REF="$v" ;;
      --agent) { [ "$v" = none ] || hi_validate_agent_id "$v"; } || { hi_err "invalid --agent"; return 2; }
               [[ "$v" =~ ^[0-9]+$ ]] && { hi_err "--agent $v: a number is only a menu choice in the interactive mode; pass an agent id (see --detect-agents)"; return 2; }
               O_AGENT="$v" ;;
      --model) hi_validate_model "$v" || { hi_err "invalid --model"; return 2; }; O_MODEL="$v" ;;
      --effort) hi_validate_effort "$v" || { hi_err "invalid --effort (low|medium|high|xhigh|max)"; return 2; }; O_EFFORT="$v" ;;
      --max-budget-usd) hi_validate_budget "$v" || { hi_err "invalid --max-budget-usd (a number > 0 and <= $HI_MAX_BUDGET)"; return 2; }; O_BUDGET="$v" ;;
      --timeout-sec) hi_validate_timeout "$v" || { hi_err "invalid --timeout-sec (an integer from 1 to $HI_MAX_TIMEOUT)"; return 2; }; O_TIMEOUT="$v" ;;
      --followups) hi_validate_onoff "$v" || { hi_err "--followups on|off"; return 2; }; O_FOLLOWUPS="$v" ;;
      --decision-layer) case "$v" in off|shadow|enforce) O_DECISION="$v" ;; *) hi_err "--decision-layer off|shadow|enforce"; return 2 ;; esac ;;
      --edit-agent-docs) hi_validate_onoff "$v" || { hi_err "--edit-agent-docs on|off"; return 2; }; O_EDIT_DOCS="$v" ;;
      --register-hooks) hi_validate_onoff "$v" || { hi_err "--register-hooks on|off"; return 2; }; O_HOOKS="$v" ;;
      --run-setup) hi_validate_onoff "$v" || { hi_err "--run-setup on|off"; return 2; }; O_SETUP="$v" ;;
      --commit) hi_validate_onoff "$v" || { hi_err "--commit on|off"; return 2; }; O_COMMIT="$v" ;;
      --report-json) hi_validate_path "$v" || { hi_err "invalid --report-json"; return 2; }; O_REPORT="$v" ;;
      --restore) hi_validate_path "$v" || { hi_err "invalid --restore"; return 2; }; O_RESTORE="$v"; O_ACTION="restore" ;;
      --git-init) O_GIT_INIT=1 ;;
      --allow-insecure-url) O_INSECURE=1 ;;
      --allow-unrestricted-agent) O_UNRESTRICTED=1 ;;
      --not-constitution-repo) O_NOT_SELF=1 ;;
      --dry-run) O_DRY=1 ;;
      --non-interactive) O_NONINT=1 ;;
      --yes) O_YES=1 ;;
      --json) O_JSON=1 ;;
      --detect-agents) O_ACTION="detect-agents" ;;
      --detect-layout) O_ACTION="detect-layout" ;;
      --print-snippets) O_ACTION="snippets" ;;
      --version) O_ACTION="version" ;;
      -h|--help) O_ACTION="help" ;;
      *) hi_err "unknown argument: $(printf '%q' "$a") (see --help)"; return 2 ;;
    esac
    hi_set "$a"
  done
  return 0
}

# http:// and git:// carry the constitution unauthenticated and unencrypted (anyone on the path can swap it).
hi_insecure_url() { [[ "$1" == http://* ]] || [[ "$1" == git://* ]]; }
hi_check_insecure() { # 0 ok, 2 refused
  local u
  for u in ${O_URLS[@]+"${O_URLS[@]}"}; do
    hi_insecure_url "$u" || continue
    if [ "$O_INSECURE" = 1 ]; then hi_warn "insecure upstream URL $(hi_sanitize_url "$u") (allowed by --allow-insecure-url)"
    else hi_err "refusing insecure upstream URL $(hi_sanitize_url "$u") (http:// and git:// are unauthenticated); use https/ssh, or pass --allow-insecure-url"; return 2; fi
  done
  return 0
}

# ───────────────────────────── tty questions ─────────────────────────────
hi_open_tty() {
  local t=/dev/tty
  if [ -n "${HELIX_INSTALLER_TTY:-}" ]; then   # test seam: honoured only together with HELIX_INSTALLER_TEST=1
    if [ "${HELIX_INSTALLER_TEST:-}" = 1 ]; then t="$HELIX_INSTALLER_TTY"
    else hi_warn "ignoring HELIX_INSTALLER_TTY (a test switch; honoured only with HELIX_INSTALLER_TEST=1)"; fi
  fi
  { exec 8<"$t"; } 2>/dev/null || return 1
  { exec 7>"$t"; } 2>/dev/null || exec 7>&2
  return 0
}
hi_ask() { # varname question default validator-function
  local __v="$1" __q="$2" __d="$3" __f="${4:-}" __a
  while :; do
    hi_out '%s [%s]: ' "$__q" "$__d"
    IFS= read -r __a <&8 || { hi_out '\n'; hi_err "input closed"; return 2; }
    __a="${__a%$'\r'}"; [ -n "$__a" ] || __a="$__d"
    if [ -z "$__f" ] || "$__f" "$__a"; then printf -v "$__v" '%s' "$__a"; return 0; fi
    hi_out '  invalid answer, try again\n'
  done
}
hi_yn() { case "$1" in y|Y|yes|n|N|no) return 0 ;; esac; return 1; }
hi_is_yes() { case "$1" in y|Y|yes) return 0 ;; esac; return 1; }
hi_agent_answer_ok() { [ "$1" = none ] || [[ "$1" =~ ^[0-9]{1,4}$ ]] || hi_validate_agent_id "$1"; }
hi_decision_ok() { case "$1" in off|shadow|enforce) return 0 ;; esac; return 1; }
hi_upstream_ok() { hi_upstream_table | cut -d'|' -f1 | grep -qxF -- "$1"; }
hi_onoff_from_yn() { if hi_is_yes "$1"; then printf on; else printf off; fi; }

hi_interactive_questions() {
  local -a menu=(); local line id kind tier inst p v st n=0 ans
  hi_out '\nHelix Constitution installer %s — project: %s\n' "$HI_VERSION" "$O_ROOT"
  if ! hi_was_set --agent; then
    hi_out '\nDetected agents (no LLM call is made to detect):\n'
    hi_out '  %3s  %-34s %-15s %-12s %s\n' 0 none "-" "-" "do not run an agent"
    while IFS='|' read -r id kind tier inst p v st; do
      [ "$inst" = true ] || continue
      n=$((n+1)); menu+=("$id")
      hi_out '  %3d  %-34s %-15s %-12s %s %s\n' "$n" "$id" "$kind" "$tier" "${v:0:30}" "$st"
    done < <(hi_detect_agents)
    while :; do
      hi_ask ans "Which agent should run the setup prompt? (number or id)" none hi_agent_answer_ok || return 2
      [[ "$ans" =~ ^[0-9]+$ ]] || break
      if [ "$((10#$ans))" = 0 ]; then ans=none; break; fi
      if [ "$((10#$ans))" -le "${#menu[@]}" ]; then ans="${menu[$((10#$ans - 1))]}"; break; fi
      hi_out '  there is no agent number %s; choose 0..%d or type an agent id\n' "$ans" "${#menu[@]}"
    done
    O_AGENT="$ans"
  fi
  if hi_agent_unrestricted "$O_AGENT" && [ "$O_UNRESTRICTED" != 1 ]; then
    hi_out '\n  WARNING: %s runs with its own default permissions: it can run shell commands, edit files and reach\n' "$O_AGENT"
    hi_out '  the network in %s. The installer cannot restrict it (claude and claude aliases run with acceptEdits\n' "$O_ROOT"
    hi_out '  and a deny list instead).\n'
    hi_ask ans "Run $O_AGENT with its own default permissions anyway? (y/n)" n hi_yn || return 2
    if hi_is_yes "$ans"; then O_UNRESTRICTED=1; S_UNR_CONSENT=interactive; else S_UNR_CONSENT=declined; fi
  fi
  if [ "$O_AGENT" != none ]; then
    if hi_agent_honors_limits "$O_AGENT"; then
      hi_was_set --model || { hi_ask O_MODEL "Model" "$O_MODEL" hi_validate_model || return 2; }
      hi_was_set --effort || { hi_ask O_EFFORT "Effort (low|medium|high|xhigh|max)" "$O_EFFORT" hi_validate_effort || return 2; }
      hi_was_set --max-budget-usd || { hi_ask O_BUDGET "Max budget in USD, total incl. follow-ups (> 0, <= $HI_MAX_BUDGET)" "$O_BUDGET" hi_validate_budget || return 2; }
    else
      hi_out '  note: model, effort and budget are NOT enforced for %s (no such flags are passed); only the timeout is\n' "$O_AGENT"
    fi
    hi_was_set --timeout-sec || { hi_ask O_TIMEOUT "Timeout in seconds per agent run (1..$HI_MAX_TIMEOUT)" "$O_TIMEOUT" hi_validate_timeout || return 2; }
    hi_was_set --followups || { hi_ask ans "Auto-run follow-up prompts after a successful setup? (y/n)" n hi_yn || return 2; O_FOLLOWUPS="$(hi_onoff_from_yn "$ans")"; }
  fi
  if [ "${#O_URLS[@]}" -eq 0 ] && ! hi_was_set --upstream; then
    hi_ask O_UPSTREAM "Upstream ($(hi_upstream_table | cut -d'|' -f1 | paste -sd' ' -))" "$O_UPSTREAM" hi_upstream_ok || return 2
  fi
  hi_was_set --decision-layer || { hi_ask O_DECISION "Jev decision layer (off|shadow|enforce)" "$O_DECISION" hi_decision_ok || return 2; }
  hi_was_set --edit-agent-docs || { hi_ask ans "May the installer edit CLAUDE.md/AGENTS.md/GEMINI.md/QWEN.md (backed up first)? (y/n)" y hi_yn || return 2; O_EDIT_DOCS="$(hi_onoff_from_yn "$ans")"; }
  hi_was_set --register-hooks || { hi_ask ans "May the agent register hooks in .claude/settings.json? (y/n)" n hi_yn || return 2; O_HOOKS="$(hi_onoff_from_yn "$ans")"; }
  hi_was_set --run-setup || { hi_ask ans "Run the constitution's scripts/setup.sh (git hooks, skills, .mcp.json)? (y/n)" y hi_yn || return 2; O_SETUP="$(hi_onoff_from_yn "$ans")"; }
  hi_was_set --commit || { hi_ask ans "Commit the result locally? (the installer never pushes) (y/n)" n hi_yn || return 2; O_COMMIT="$(hi_onoff_from_yn "$ans")"; }
  return 0
}

# ───────────────────────────── git + upstream ─────────────────────────────
hi_git() { hi_user_umask hi_gx -C "$O_ROOT" "$@"; }   # project git state is written with the user's umask
hi_is_local_url() { [[ "$1" == /* ]] || [[ "$1" == file://* ]]; }
hi_git_url() { # url args... — git with file protocol allowed only for local URLs
  local u="$1"; shift
  if hi_is_local_url "$u"; then hi_gx -c protocol.file.allow=always "$@"; else hi_gx "$@"; fi
}
# Run a command (or function) with the user's own umask, in a subshell: project content stays as readable
# as the user's other files while the installer's own artefacts stay private (umask 077 in main).
hi_user_umask() { ( umask "${HI_UMASK0:-$(umask)}"; "$@" ); }
# A local path is cloned as file:// so the blob filter is honoured (git ignores --filter on path clones).
hi_clone_url() { if [[ "$1" == /* ]]; then printf 'file://%s' "$1"; else printf '%s' "$1"; fi; }
hi_candidates() {
  local col
  if [ "${#O_URLS[@]}" -gt 0 ]; then printf 'custom|%s\n' ${O_URLS[@]+"${O_URLS[@]}"}; return; fi
  col=3; [ "$O_SSH" = 1 ] && col=4
  hi_upstream_table | awk -F'|' -v k="$O_UPSTREAM" -v c="$col" '$1 == k { print $1 "|" $c }'
  hi_upstream_table | awk -F'|' -v k="$O_UPSTREAM" -v c="$col" '$1 != k { print $1 "|" $c }'
}
hi_probe_upstream() { # sets S_KEY S_URL S_TAGS; 0 found, 3 none reachable
  local key url out
  while IFS='|' read -r key url; do
    if hi_url_has_password "$url"; then hi_warn "skipping a URL that carries credentials ($(hi_sanitize_url "$url")); credentials are never stored"; continue; fi
    hi_say "probing $(hi_sanitize_url "$url") ..."
    if out="$(HI_GX_TIMEOUT=60 hi_gx -c protocol.file.allow=always ls-remote --tags -- "$url" 2>/dev/null)" \
       && GIT_TERMINAL_PROMPT=0 HI_GX_TIMEOUT=60 hi_gx -c protocol.file.allow=always ls-remote --heads -- "$url" >/dev/null 2>&1; then
      S_KEY="$key"; S_URL="$url"; S_TAGS="$out"; return 0
    fi
    hi_warn "unreachable: $(hi_sanitize_url "$url")"
  done < <(hi_candidates)
  return 3
}
hi_resolve_ref() { # → S_REF; 0 ok, 3 not found upstream
  if [ -n "$O_REF" ]; then
    S_REF="$O_REF"
    [[ "$O_REF" =~ ^[0-9a-f]{7,40}$ ]] && return 0
    GIT_TERMINAL_PROMPT=0 HI_GX_TIMEOUT=60 hi_gx -c protocol.file.allow=always ls-remote -- "$S_URL" "$O_REF" 2>/dev/null | grep -q . && return 0
    hi_err "ref $O_REF not found on $(hi_sanitize_url "$S_URL")"; return 3
  fi
  S_REF="$(printf '%s\n' "$S_TAGS" | hi_newest_tag)"
  [ -n "$S_REF" ] || S_REF="main"
  return 0
}
# Paths `git status` reports, read NUL-separated (-z): names with spaces, quotes, newlines or non-ASCII bytes
# arrive as they are (never C-quoted), and a rename or copy yields both its new and its old path.
hi_status_paths() { # → S_TMP_PATHS
  local rec x=""
  S_TMP_PATHS=()
  while IFS= read -r -d '' rec; do
    if [ -n "$x" ]; then S_TMP_PATHS+=("$rec"); x=""; continue; fi
    S_TMP_PATHS+=("${rec:3}"); [[ "${rec:0:2}" == *[RC]* ]] && x=1
  done < <(hi_git --no-optional-locks status --porcelain -z 2>/dev/null)
  return 0
}
hi_path_dirty() { [ -n "$(hi_git --no-optional-locks status --porcelain -- "$1" 2>/dev/null)" ]; }

# ───────────────────────────── backups + writes ─────────────────────────────
# Created lazily, the first time something is backed up (a refusal therefore leaves no backup dir behind).
# Sets S_BK in the CALLING shell: never call it inside $(...).
hi_backup_dir() {
  [ -n "$S_BK" ] && { printf '%s' "$S_BK"; return 0; }
  local stamp ex
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  S_BK="$O_ROOT/$HI_BACKUP_ROOT/$stamp"
  mkdir -p "$S_BK/files" && chmod 700 "$S_BK" "$S_BK/files" || { hi_err "cannot create backup dir"; S_BK=""; return 1; }
  ex="$(hi_gx -C "$O_ROOT" rev-parse --git-path info/exclude 2>/dev/null)"
  if [ -n "$ex" ]; then
    [[ "$ex" == /* ]] || ex="$O_ROOT/$ex"
    mkdir -p "$(dirname "$ex")"
    grep -qxF "/$HI_BACKUP_ROOT/" "$ex" 2>/dev/null || printf '/%s/\n' "$HI_BACKUP_ROOT" >>"$ex"
  fi
  printf '%s' "$S_BK"
}
hi_backup_file() { # relpath — copy once into the backup (file or symlink); record in manifest
  local rel="$1" bk
  hi_backup_dir >/dev/null || return 1; bk="$S_BK"
  grep -qxF "$rel" "$bk/manifest.txt" 2>/dev/null && return 0
  if [ -e "$O_ROOT/$rel" ] || [ -L "$O_ROOT/$rel" ]; then
    mkdir -p "$bk/files/$(dirname "$rel")" && cp -pP "$O_ROOT/$rel" "$bk/files/$rel" || { hi_err "backup of $rel failed"; return 1; }
    printf '%s\n' "$rel" >>"$bk/manifest.txt"
  else
    printf '%s\n' "$rel" >>"$bk/created.txt"
  fi
}
hi_move_aside() { # relpath — move a leftover into the backup (never delete)
  local rel="$1" bk
  hi_backup_dir >/dev/null || return 1; bk="$S_BK"
  mkdir -p "$bk/moved-aside/$(dirname "$rel")" && mv -- "$O_ROOT/$rel" "$bk/moved-aside/$rel" \
    && hi_say "moved leftover $rel to $bk/moved-aside/$rel"
}
hi_block_for() { # file
  case "$1" in
    AGENTS.md) printf '%s\n## INHERITED FROM submodules/constitution/AGENTS.md\n\n> Base agent rules: submodules/constitution/AGENTS.md\n\nAll rules in `submodules/constitution/AGENTS.md` and `submodules/constitution/Constitution.md` apply unconditionally; the project rules below extend them.\n%s\n\n' "$HI_MARK_BEGIN" "$HI_MARK_END" ;;
    *) printf '%s\n## INHERITED FROM submodules/constitution/%s\n\n@submodules/constitution/%s\n\nAll rules in `submodules/constitution/%s` (and the `submodules/constitution/Constitution.md` it references) apply unconditionally. The project-specific rules below extend them.\n%s\n\n' \
         "$HI_MARK_BEGIN" "$1" "$1" "$1" "$HI_MARK_END" ;;
  esac
}
hi_has_block() { # file
  case "$1" in
    AGENTS.md) grep -qxF '> Base agent rules: submodules/constitution/AGENTS.md' "$O_ROOT/$1" 2>/dev/null ;;
    *) grep -qxF "## INHERITED FROM submodules/constitution/$1" "$O_ROOT/$1" 2>/dev/null ;;
  esac
}
hi_doc_targets() { # files the inheritance block goes into
  printf '%s\n' CLAUDE.md AGENTS.md
  local f; for f in GEMINI.md QWEN.md; do [ -e "$O_ROOT/$f" ] && printf '%s\n' "$f"; done
}
hi_docs_preflight() { # 0 ok, 3 blocked (symlink or uncommitted edits in a file we would change)
  local f
  [ "$O_EDIT_DOCS" = on ] || return 0
  while read -r f; do
    hi_has_block "$f" && continue
    if [ -L "$O_ROOT/$f" ]; then hi_err "$f is a symlink; refusing to edit through it (fix it or use --edit-agent-docs off)"; return 3; fi
    if [ -e "$O_ROOT/$f" ] && hi_path_dirty "$f"; then hi_err "$f has uncommitted changes; commit or stash them first (it would be edited)"; return 3; fi
  done < <(hi_doc_targets)
  return 0
}
hi_write_docs() {
  local f tmp mode
  [ "$O_EDIT_DOCS" = on ] || { S_NOTES+=("inheritance block not written (--edit-agent-docs off)"); return 0; }
  while read -r f; do
    if hi_has_block "$f"; then continue; fi
    hi_backup_file "$f" || return 1
    tmp="$(mktemp "$O_ROOT/.${f}.helix.XXXXXX")" || return 1
    { hi_block_for "$f"; if [ -e "$O_ROOT/$f" ]; then cat -- "$O_ROOT/$f"; fi; } >"$tmp" || { rm -f -- "$tmp"; return 1; }
    mode="$(printf '%o' $(( 0666 & ~0${HI_UMASK0:-022} )))"; [ -e "$O_ROOT/$f" ] && mode="$(stat -c %a -- "$O_ROOT/$f" 2>/dev/null || echo 644)"
    chmod "$mode" "$tmp" && mv -f -- "$tmp" "$O_ROOT/$f" || { rm -f -- "$tmp"; return 1; }
    hi_git add -- "$f" >/dev/null 2>&1
    S_WRITTEN+=("$f"); hi_say "wrote the inheritance block into $f"
  done < <(hi_doc_targets)
}

# ───────────────────────────── lock + signals ─────────────────────────────
# The run lock is taken with link(2) (`ln` without -f): it creates the lock name atomically from a private temp
# file and fails on ANY existing path, so a planted FIFO, symlink or device is never opened (bash's noclobber only
# refuses REGULAR files, and opening a FIFO blocks). A lock whose pid is gone is reclaimed under a second
# link-created marker (lock.reclaim), so of several runs that all saw the same stale lock exactly one replaces it;
# the others re-read the new holder and stop. A reclaim marker left by a run killed mid-reclaim is reported, not
# removed (delete it by hand). Nothing here uses mkdir as a lock.
# >>> hi_lock_helpers (identical in install_constitution.sh and update_constitution.sh)
# pid lockfile → 0 when that pid may still be the process that wrote the lock. Only "No such process" counts
# as gone: "Operation not permitted" (a process of another user, or init) counts as alive. On Linux a process
# that started after the lock file was last written cannot have written it (its pid was reused): gone. When
# the start time cannot be read, the pid counts as alive (refuse rather than take a live run's lock).
hi_holder_alive() {
  local p="$1" f="$2" msg st hz bt start mt
  [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 0 ] || return 1
  if ! msg="$(LC_ALL=C kill -0 "$p" 2>&1)"; then
    case "$msg" in *"No such process"*) return 1 ;; esac
  fi
  st="$(cat "/proc/$p/stat" 2>/dev/null)" || return 0
  st="${st##*) }"; read -r -a st <<<"$st"; start="${st[19]:-}"
  hz="$(getconf CLK_TCK 2>/dev/null)"; bt="$(awk '$1 == "btime" { print $2; exit }' /proc/stat 2>/dev/null)"
  mt="$(stat -c %Y -- "$f" 2>/dev/null || stat -f %m -- "$f" 2>/dev/null)"
  [[ "$start" =~ ^[0-9]+$ && "$hz" =~ ^[1-9][0-9]*$ && "$bt" =~ ^[0-9]+$ && "$mt" =~ ^[0-9]+$ ]] || return 0
  [ $((bt + start / hz)) -gt $((mt + 2)) ] && return 1
  return 0
}
# TEST SEAM, honoured only with HELIX_INSTALLER_TEST=1: at the point named by HELIX_INSTALLER_TEST_PAUSE print
# "TEST PAUSE <point>" and wait (at most 60 s) until the file HELIX_INSTALLER_TEST_RESUME exists.
hi_test_pause() {
  [ "${HELIX_INSTALLER_TEST:-}" = 1 ] && [ -n "${HELIX_INSTALLER_TEST_PAUSE:-}" ] && [ "$HELIX_INSTALLER_TEST_PAUSE" = "$1" ] \
    && [ -n "${HELIX_INSTALLER_TEST_RESUME:-}" ] || return 0
  local n=0
  printf 'TEST PAUSE %s\n' "$1" >&2
  while [ ! -e "$HELIX_INSTALLER_TEST_RESUME" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
  return 0
}
# <<< hi_lock_helpers
hi_lock_pid() { # [FILE] → the pid recorded in FILE (default: our lock), read only from a regular non-symlink file (never blocks)
  local f="${1:-$S_LOCK}"
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  timeout 5 head -c 20 -- "$f" 2>/dev/null | tr -cd '0-9'
}
# S_LOCK is set ONLY after this process created the lock file itself (ln succeeded), so hi_unlock, which a signal
# can run at any point of hi_lock, can never remove a lock that another run holds. The private temp file and the
# reclaim marker are tracked the same way (S_LOCK_TMP, S_LOCK_RECLAIM) and cleaned by hi_unlock, also after a
# signal.
hi_lock() {
  local gd pid pid2 tmp lockp
  gd="$(hi_gx -C "$O_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || return 3
  lockp="$gd/helix-constitution-install.lock"
  tmp="$(mktemp "$lockp.XXXXXX" 2>/dev/null)" || { hi_err "cannot create a temp file next to $lockp"; return 3; }
  S_LOCK_TMP="$tmp"
  printf '%s\n' "$$" >"$tmp" || { hi_unlock; return 3; }
  if ln -- "$tmp" "$lockp" 2>/dev/null; then S_LOCK="$lockp"; hi_unlock_tmp; return 0; fi
  if [ ! -e "$lockp" ] && [ ! -L "$lockp" ]; then   # the create failed although nothing is there
    hi_unlock; hi_err "cannot create the lock $lockp (is ln on PATH and the git directory writable? if another run just finished, run again)"; return 3; fi
  if [ -L "$lockp" ] || [ ! -f "$lockp" ]; then
    hi_unlock; hi_err "$lockp exists and is not a regular file (symlink, FIFO, …); not touching it — remove it yourself"; return 3; fi
  pid="$(hi_lock_pid "$lockp")"
  hi_test_pause lock_read
  if [ -n "$pid" ] && [ "$pid" != "$$" ] && hi_holder_alive "$pid" "$lockp"; then
    hi_unlock; hi_err "another installer run (pid $pid) holds $lockp"; return 3; fi
  hi_test_pause reclaim
  if ! ln -- "$tmp" "$lockp.reclaim" 2>/dev/null; then
    hi_unlock; hi_err "another run is reclaiming $lockp (if no installer is running, remove $lockp.reclaim by hand)"; return 3; fi
  S_LOCK_RECLAIM="$lockp.reclaim"
  pid2="$(hi_lock_pid "$lockp")"   # re-read under the reclaim marker: another run may already have replaced the stale lock
  if [ "$pid2" != "$pid" ] || [ -L "$lockp" ]; then
    hi_unlock; hi_err "another installer run took $lockp"; return 3; fi
  hi_warn "removing a stale installer lock (pid ${pid:-?} is gone)"
  rm -f -- "$lockp"
  if ln -- "$tmp" "$lockp" 2>/dev/null; then S_LOCK="$lockp"; hi_unlock_tmp; return 0; fi
  hi_unlock; hi_err "cannot take the installer lock"; return 3
}
# A clone left in an older backup's staging/ by a run that was killed (SIGKILL: no trap ran) is reported, never
# deleted: the installer never deletes recursively (§11.4.287). It is not used for anything and is safe to remove.
hi_report_leftover_staging() {
  local d sz
  for d in "$O_ROOT/$HI_BACKUP_ROOT"/*/staging/*; do
    [ -d "$d" ] || continue
    [ -n "$S_BK" ] && [[ "$d" == "$S_BK"/* ]] && continue
    sz="$(du -sk -- "$d" 2>/dev/null | awk '{ print $1 }')"
    hi_warn "leftover clone from an interrupted run: $d (${sz:-?} KiB); it is not used and is safe to delete"
    S_NOTES+=("leftover clone from an interrupted run (not used; safe to delete): $d")
  done
}
hi_unlock_tmp() { # our private temp file and, once taken, our reclaim marker (never anyone else's)
  [ -n "$S_LOCK_TMP" ] && rm -f -- "$S_LOCK_TMP"
  S_LOCK_TMP=""
  [ -n "$S_LOCK_RECLAIM" ] && [ "$(hi_lock_pid "$S_LOCK_RECLAIM")" = "$$" ] && rm -f -- "$S_LOCK_RECLAIM"
  S_LOCK_RECLAIM=""
  return 0
}
hi_unlock() { # removes the lock only while it still records this process; never a lock another run holds
  hi_unlock_tmp
  [ -n "$S_LOCK" ] && [ "$(hi_lock_pid "$S_LOCK")" = "$$" ] && rm -f -- "$S_LOCK"
  S_LOCK=""
  return 0
}
# Removes the git variables that would redirect or reconfigure git in a child the installer starts (agent,
# setup.sh, updater): repository location, executed commands, config injection. Kept: the user's identity, the
# config-file selection and the TLS/protocol settings (the same keep-list hi_gx uses). Run it in a subshell.
hi_scrub_git_env() {
  local v
  for v in ${!GIT_*}; do
    case "$v" in
      GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM|GIT_CEILING_DIRECTORIES|GIT_AUTHOR_*|GIT_COMMITTER_*|\
      GIT_SSL_CAINFO|GIT_SSL_CAPATH|GIT_ALLOW_PROTOCOL|GIT_PROTOCOL_FROM_USER|GIT_TERMINAL_PROMPT) ;;
      *) unset "$v" ;;
    esac
  done
}
# A signal while the agent runs stops the agent before the installer exits. SIGTERM goes to the agent's timeout
# process (a positive pid that is our own background job; never pid <= 1); timeout passes it on to the agent's
# process group and sends SIGKILL after --kill-after. TERM is sent for Ctrl-C too: background jobs of a
# non-interactive shell ignore SIGINT, so INT alone would leave them running. When timeout has exited, members
# of ITS process group that are still alive are killed: the group id must equal the timeout pid (the group
# timeout created for the agent, read from /proc before signalling), so the installer's own group or any other
# group is never signalled.
HI_AGENT_PID=""
hi_stop_agent() {
  local p="${HI_AGENT_PID:-}" j ours=0 st pg=""
  [[ "$p" =~ ^[1-9][0-9]*$ ]] && [ "$p" -gt 1 ] && [ "$p" != "$$" ] || return 0
  for j in $(jobs -p); do [ "$j" = "$p" ] && ours=1; done
  [ "$ours" = 1 ] || return 0
  if st="$(cat "/proc/$p/stat" 2>/dev/null)"; then st="${st##*) }"; read -r _ _ pg _ <<<"$st"; fi
  hi_err "stopping the agent (pid $p) ..."
  kill -s TERM -- "$p" 2>/dev/null
  wait "$p" 2>/dev/null
  if [[ "$pg" =~ ^[1-9][0-9]*$ ]] && [ "$pg" -gt 1 ] && [ "$pg" = "$p" ] && kill -0 -- "-$pg" 2>/dev/null; then
    kill -s KILL -- "-$pg" 2>/dev/null
  fi
  HI_AGENT_PID=""
}
hi_on_signal() {
  trap '' INT TERM
  local code=130; [ "$1" = TERM ] && code=143
  hi_stop_agent "$1"
  hi_err "interrupted by SIG$1; nothing is lost: re-run the same command to finish (backups: ${S_BK:-none})"
  S_STATUS="interrupted"; S_RC="$code"
  hi_write_report >/dev/null 2>&1
  hi_unlock
  exit "$code"
}

# ───────────────────────────── modes ─────────────────────────────
# The installer marks the repository it clones (git config helix-installer.clone=true) until the add has
# completed. Only a MARKED leftover (or an empty directory) is ever moved aside; anything else is the user's.
hi_has_marker() {
  local gd cfg
  gd="$(hi_gx -C "$O_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  for cfg in "$O_ROOT/$HI_SUB/.git/config" "$gd/modules/$HI_SUB/config"; do
    [ -f "$cfg" ] && [ "$(hi_gx config -f "$cfg" --get helix-installer.clone 2>/dev/null)" = true ] && return 0
  done
  return 1
}
# A run killed (SIGKILL: no trap ran) after `git submodule add` but before its last step leaves a registered,
# staged submodule that may still hold its own .git directory and the installer marker. The next run (update
# mode) finishes those steps first: absorb the gitdir, stage, init, remove the marker.
hi_complete_interrupted_add() {
  hi_has_marker || return 0
  hi_say "completing an interrupted add of $HI_SUB (installer marker found)"
  (cd "$O_ROOT" && hi_user_umask hi_gx submodule absorbgitdirs -- "$HI_SUB") >/dev/null 2>&1 \
    || { hi_err "git submodule absorbgitdirs failed"; return 1; }
  hi_git add -- .gitmodules "$HI_SUB" || return 1
  (cd "$O_ROOT" && hi_user_umask hi_git_url "$S_URL" submodule update --init --quiet -- "$HI_SUB") >/dev/null 2>&1 \
    || { hi_err "git submodule update --init failed"; return 1; }
  hi_gx -C "$O_ROOT/$HI_SUB" config --unset helix-installer.clone >/dev/null 2>&1
  if hi_has_marker; then hi_err "could not remove the installer marker from $HI_SUB"; return 1; fi
  return 0
}
hi_staged_only_gitlink() { # a gitlink at $HI_SUB in the index but not in HEAD
  hi_git ls-files -s -- "$HI_SUB" 2>/dev/null | grep -q '^160000 ' \
    && ! hi_gx -C "$O_ROOT" ls-tree HEAD -- "$HI_SUB" 2>/dev/null | grep -q '^160000 '
}
hi_gitmodules_user_dirty() { # 0 when .gitmodules (worktree or index) differs from HEAD beyond the installer's own section
  local tw ti th a b c
  tw="$(mktemp)" && ti="$(mktemp)" && th="$(mktemp)" || return 0
  [ -e "$O_ROOT/.gitmodules" ] && cp -- "$O_ROOT/.gitmodules" "$tw"
  hi_gx -C "$O_ROOT" show :.gitmodules >"$ti" 2>/dev/null || : >"$ti"
  hi_gx -C "$O_ROOT" show HEAD:.gitmodules >"$th" 2>/dev/null || : >"$th"
  for c in "$tw" "$ti" "$th"; do hi_gx config -f "$c" --remove-section "submodule.$HI_SUB" >/dev/null 2>&1; done
  a="$(hi_gx config -f "$tw" --list 2>/dev/null | sort)"; b="$(hi_gx config -f "$ti" --list 2>/dev/null | sort)"
  c="$(hi_gx config -f "$th" --list 2>/dev/null | sort)"
  rm -f -- "$tw" "$ti" "$th"
  [ "$a" != "$c" ] || [ "$b" != "$c" ]
}
hi_add_preflight() { # read-only; 0 ok, 3 blocked. Runs BEFORE any lock, backup or exclude edit.
  # Every directory above the submodule path (and the backup root) must be a real directory of the project: a
  # committed symlink (submodules -> /elsewhere) would put the clone, or a backup, outside the project.
  if hi_symlinked_parent "$O_ROOT" "$HI_SUB" || [ -L "$O_ROOT/$HI_BACKUP_ROOT" ]; then
    hi_err "a directory on the path $HI_SUB (or $HI_BACKUP_ROOT) is a symlink; refusing to write through it (nothing was changed)"
    return 3
  fi
  if hi_staged_only_gitlink && ! hi_has_marker; then
    hi_err "$HI_SUB is a staged gitlink with no .gitmodules entry and was not created by this installer (an embedded repository added with 'git add'?)."
    hi_err "nothing was changed. Unstage it with:  git rm --cached $HI_SUB   (your files stay), or register it in .gitmodules; then re-run"
    return 3
  fi
  if [ -e "$O_ROOT/$HI_SUB" ] || [ -L "$O_ROOT/$HI_SUB" ]; then
    if [ -n "$(ls -A "$O_ROOT/$HI_SUB" 2>/dev/null)" ] && ! hi_has_marker; then
      hi_err "$HI_SUB exists and is not a constitution clone left by an interrupted run of this installer; move it away first (nothing was changed)"
      return 3
    fi
  fi
  if hi_gitmodules_user_dirty; then
    hi_err ".gitmodules has uncommitted changes of your own; commit or stash them first (nothing was changed)"
    return 3
  fi
  return 0
}
hi_recover_partial() { # leftovers of an interrupted ADD by this installer → moved aside (never deleted)
  local gd
  gd="$(hi_gx -C "$O_ROOT" rev-parse --absolute-git-dir)"
  if hi_staged_only_gitlink; then
    hi_git rm -q --cached -- "$HI_SUB" >/dev/null 2>&1 || { hi_err "could not unstage the half-added $HI_SUB gitlink"; return 1; }
    hi_say "unstaged the gitlink of an interrupted add (installer marker found)"
  fi
  if [ -e "$O_ROOT/$HI_SUB" ] || [ -L "$O_ROOT/$HI_SUB" ]; then
    if [ -z "$(ls -A "$O_ROOT/$HI_SUB" 2>/dev/null)" ] || hi_has_marker; then
      hi_move_aside "$HI_SUB" || return 1
    else
      hi_err "$HI_SUB exists and is not a constitution clone left by an interrupted run of this installer; move it away first"
      return 3
    fi
  fi
  if [ -d "$gd/modules/$HI_SUB" ]; then
    local bk; hi_backup_dir >/dev/null || return 1; bk="$S_BK"
    mkdir -p "$bk/moved-aside/git-modules" && mv -- "$gd/modules/$HI_SUB" "$bk/moved-aside/git-modules/" \
      && hi_say "moved leftover .git/modules/$HI_SUB into the backup"
  fi
  if hi_gx -C "$O_ROOT" config -f "$O_ROOT/.gitmodules" --get "submodule.$HI_SUB.path" >/dev/null 2>&1; then
    hi_backup_file .gitmodules || return 1
    hi_user_umask hi_gx -C "$O_ROOT" config -f "$O_ROOT/.gitmodules" --remove-section "submodule.$HI_SUB" >/dev/null 2>&1
    [ -s "$O_ROOT/.gitmodules" ] || hi_git rm -q --cached --ignore-unmatch -- .gitmodules >/dev/null 2>&1
  fi
  hi_user_umask hi_gx -C "$O_ROOT" config --remove-section "submodule.$HI_SUB" >/dev/null 2>&1
  return 0
}
# Blobless partial clone (--filter=blob:none): every commit and tag (the updater needs the commit graph for
# its fast-forward checks), file contents fetched on demand. NO --depth. The clone is made in the private
# backup dir, marked, checked out at the resolved commit, moved into place, then registered with
# `git submodule add` (existing repository) and its gitdir absorbed into the project's .git/modules.
hi_gitlink_of() { # dir relpath → the commit the INDEX of dir records for that submodule (empty when none)
  local l; l="$(hi_gx -C "$1" ls-files -s -- "$2" 2>/dev/null | head -n 1)"
  case "$l" in "160000 "*) l="${l#160000 }"; printf '%s' "${l%% *}" ;; esac
}
hi_do_add() {
  local err sha bk stage rc mode=blobless live
  hi_recover_partial || return $?
  [ -e "$O_ROOT/.gitmodules" ] && { hi_backup_file .gitmodules || return 1; }
  hi_backup_dir >/dev/null || return 1; bk="$S_BK"
  stage="$bk/staging/constitution"
  mkdir -p "$bk/staging" || return 1
  hi_say "cloning $(hi_sanitize_url "$S_URL") as $HI_SUB: blobless partial clone (every commit and tag; file contents fetched on demand) ..."
  err="$(HI_GX_TIMEOUT="$HI_CLONE_TIMEOUT" hi_user_umask hi_git_url "$S_URL" clone --quiet --filter=blob:none --no-checkout -- "$(hi_clone_url "$S_URL")" "$stage" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    if [ -e "$stage" ] || [ -L "$stage" ]; then
      # never into an existing directory (mv would nest the clone inside it) and never ignoring a failure (the full
      # clone below needs an empty $stage): pick a name that does not exist yet
      local fdst="$bk/staging/failed-blobless-clone" fn=0
      while [ -e "$fdst" ] || [ -L "$fdst" ]; do fn=$((fn+1)); fdst="$bk/staging/failed-blobless-clone-$fn"; done
      mv -- "$stage" "$fdst" || { hi_err "could not move the failed clone aside ($stage); nothing else was changed"; return 1; }
    fi
    hi_warn "blobless clone failed ($(printf '%s' "$err" | hi_scrub | tail -n 1)); retrying with a full clone"
    mode=full
    err="$(HI_GX_TIMEOUT="$HI_CLONE_TIMEOUT" hi_user_umask hi_git_url "$S_URL" clone --quiet --no-checkout -- "$(hi_clone_url "$S_URL")" "$stage" 2>&1)" \
      || { hi_err "git clone failed: $(printf '%s' "$err" | hi_scrub | tail -n 3)"; return 1; }
  fi
  hi_gx -C "$stage" config helix-installer.clone true || return 1
  [[ "$S_URL" == /* ]] && hi_gx -C "$stage" remote set-url origin "$S_URL"
  # a fresh clone: every tag in it came from the remote, so its own tag list is the remote-tag list
  local st res; st="$(hi_gx -C "$stage" for-each-ref --format='%(refname:strip=2) %(objectname)' refs/tags 2>/dev/null)"
  res="$(hi_resolve_ref_in "$stage" "$S_REF" "$st")" || { hi_err "ref $S_REF is not in the clone"; return 1; }
  sha="${res#* }"
  hi_test_pause add_after_clone
  live="$(hi_remote_live "$stage" origin | awk 'NF && !s[$0]++')"   # the remote as it is NOW, not as the clone saw it
  hi_on_remote "$stage" "$sha" "$live" || { hi_err "ref $S_REF ($sha) is not on any remote branch or tag the remote advertises now; refusing"; return 1; }
  if [ "$mode" = blobless ]; then
    # count, never `grep -q`: an early-exiting reader kills rev-list with SIGPIPE (141) under pipefail and a
    # blobless clone would be misreported as full on any repository with many files
    local nmiss; nmiss="$(hi_gx -C "$stage" rev-list --objects --missing=print --max-count=1 "$sha" 2>/dev/null | grep -c '^?')"
    if [ "${nmiss:-0}" -eq 0 ]; then
      mode=full; hi_warn "the server does not support partial clone: a full clone (all file contents) was made instead"
    fi
  fi
  hi_user_umask hi_git_url "$S_URL" -C "$stage" checkout --quiet --detach "$sha" || { hi_err "checkout of $S_REF failed"; return 1; }
  hi_symlinked_parent "$O_ROOT" "$HI_SUB" && { hi_err "a directory on the path $HI_SUB became a symlink; refusing"; return 1; }
  hi_user_umask mkdir -p "$O_ROOT/submodules" || return 1
  mv -- "$stage" "$O_ROOT/$HI_SUB" || { hi_err "could not move the clone into $HI_SUB"; return 1; }
  rmdir -- "$bk/staging" 2>/dev/null
  err="$( (cd "$O_ROOT" && hi_user_umask hi_git_url "$S_URL" submodule add --quiet -- "$S_URL" "$HI_SUB") 2>&1)" \
    || { hi_err "git submodule add failed: $(printf '%s' "$err" | hi_scrub | tail -n 3)"; return 1; }
  (cd "$O_ROOT" && hi_user_umask hi_gx submodule absorbgitdirs -- "$HI_SUB") >/dev/null 2>&1 \
    || { hi_err "git submodule absorbgitdirs failed"; return 1; }
  hi_git add -- .gitmodules "$HI_SUB" || return 1
  (cd "$O_ROOT" && hi_user_umask hi_git_url "$S_URL" submodule update --init --quiet -- "$HI_SUB") >/dev/null 2>&1 \
    || { hi_err "git submodule update --init failed"; return 1; }
  hi_gx -C "$O_ROOT/$HI_SUB" config --unset helix-installer.clone >/dev/null 2>&1
  S_BEFORE=""; S_AFTER="$sha"; S_CLONE="$mode"
  hi_say "constitution added at $HI_SUB ($S_REF = $sha, $mode clone); nested submodules are left uninitialised (flat)"
}
# >>> hi_resolve_ref_in (identical in install_constitution.sh and update_constitution.sh)
# dir ref remote-tags → "KIND SHA". The REMOTE state wins over local refs of the same name: a tag the remote
# has resolves to the remote's object, a branch name to a remote-tracking branch (origin first, then the other
# remotes), a hex string to that commit; a local tag/branch is used only when no remote has the name (KIND
# local-ref, which the caller announces). The caller still requires the commit to be on a remote.
hi_resolve_ref_in() {
  local d="$1" ref="$2" o r sha
  o="$(printf '%s\n' "$3" | awk -v n="$ref" '$1 == n { print $2; exit }')"
  if [ -n "$o" ] && sha="$(hi_gx -C "$d" rev-parse --verify --quiet "$o^{commit}" 2>/dev/null)"; then printf 'remote-tag %s\n' "$sha"; return 0; fi
  if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/remotes/$ref^{commit}" 2>/dev/null)"; then printf 'remote-branch %s\n' "$sha"; return 0; fi
  while read -r r; do
    [ -n "$r" ] || continue
    if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/remotes/$r/$ref^{commit}" 2>/dev/null)"; then printf 'remote-branch %s\n' "$sha"; return 0; fi
  done < <(hi_gx -C "$d" remote 2>/dev/null | awk '$0 == "origin" { print; next } { o[++n] = $0 } END { for (i = 1; i <= n; i++) print o[i] }')
  if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]] && sha="$(hi_gx -C "$d" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null)"; then printf 'commit %s\n' "$sha"; return 0; fi
  if sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/tags/$ref^{commit}" 2>/dev/null)" \
     || sha="$(hi_gx -C "$d" rev-parse --verify --quiet "refs/heads/$ref^{commit}" 2>/dev/null)"; then printf 'local-ref %s\n' "$sha"; return 0; fi
  return 1
}
# <<< hi_resolve_ref_in
# >>> hi_remote_live (identical in install_constitution.sh and update_constitution.sh)
# What a remote has RIGHT NOW. `git fetch` never prunes (the wrapper forbids --prune), so refs/remotes/* keeps a
# branch the remote deleted long ago, and a local tag can name a commit no remote has: neither proves that a
# commit can be fetched by a fresh clone. Reachability is therefore always proved against the commit ids the
# remote advertises at this moment (ls-remote), never against refs/remotes/* or local tags. A remote that
# cannot be asked contributes nothing: unproven counts as not reachable.
# dir remote → the advertised commit ids (branches first, then tags, annotated tags unpeeled and peeled), one per line
hi_remote_live() {
  local d="$1" r="$2" k
  for k in --heads --tags; do
    HI_GX_TIMEOUT=60 hi_gx -C "$d" ls-remote "$k" "$r" 2>/dev/null \
      | awk '$1 ~ /^[0-9a-f]+$/ && (length($1) == 40 || length($1) == 64) { print $1 }'
  done
}
# dir remote → "name object-sha" of every tag the remote really has (annotated tags unpeeled; local-only tags never count)
hi_remote_tags_of() {
  HI_GX_TIMEOUT=60 hi_gx -C "$1" ls-remote --tags "$2" 2>/dev/null \
    | awk '$2 !~ /\^\{\}$/ { n = $2; sub(/^refs\/tags\//, "", n); print n, $1 }'
}
# dir sha live → 0 when sha is one of the live commits or an ancestor of one (so a fresh clone can fetch it)
hi_on_remote() {
  local l
  [[ "$2" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || return 1
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [ "$l" = "$2" ] && return 0
    hi_gx -C "$1" merge-base --is-ancestor "$2" "$l" 2>/dev/null && return 0
  done <<<"$3"
  return 1
}
# <<< hi_remote_live
# >>> hi_gitlink_rel (identical in install_constitution.sh and update_constitution.sh)
# dir head recorded → how a gitlink the project RECORDS relates to the submodule checkout's HEAD:
#   same · recorded-older (a strict ancestor of HEAD: an update that was cut off) · recorded-newer (HEAD is a strict
#   ancestor of it: the checkout is stale) · diverged · unknown (the commit is not in the checkout).
# Only "same" and "recorded-older" may be replaced by the updater; every other answer is a refusal.
hi_gitlink_rel() {
  local d="$1" a="$2" b="$3"
  [ "$a" = "$b" ] && { printf same; return 0; }
  [[ "$b" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && hi_gx -C "$d" cat-file -e "$b^{commit}" 2>/dev/null || { printf unknown; return 0; }
  if hi_gx -C "$d" merge-base --is-ancestor "$b" "$a" 2>/dev/null; then printf recorded-older
  elif hi_gx -C "$d" merge-base --is-ancestor "$a" "$b" 2>/dev/null; then printf recorded-newer
  else printf diverged; fi
}
# dir relpath → the gitlink the HEAD COMMIT of dir records for that submodule (empty when none / no commit yet)
hi_gitlink_committed() {
  local l; l="$(hi_gx -C "$1" ls-tree HEAD -- "$2" 2>/dev/null | head -n 1)"
  case "$l" in "160000 commit "*) l="${l#160000 commit }"; printf '%s' "${l%%[[:space:]]*}" ;; esac
}
# <<< hi_gitlink_rel
# built-in fast-forward update for constitution versions that predate scripts/update_constitution.sh
# The update-pending marker the updater keeps (<project git dir>/helix-update-pending, "<target sha> <staged-before>"
# where staged-before is the gitlink staged at that moment, "-" when none): written right before the built-in
# updater's checkout and removed once the gitlink is staged, so a staged gitlink left by an update cut off in
# between is recognised as this installer's own (never a change the user staged). It is honoured only when it names
# the checkout AND its staged-before equals the gitlink staged now (a stale marker never licenses an overwrite);
# a symlinked marker is neither read nor written (hi_marker_get / hi_marker_set).
hi_marker_path() {
  local p
  p="$(hi_gx -C "$O_ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)" || return 1
  case "$p" in "") return 1 ;; /*) ;; *) p="$O_ROOT/$p" ;; esac
  printf '%s' "$p"
}
hi_marker_set() {
  local pend
  pend="$(hi_marker_path)" || return 0
  [ -L "$pend" ] && return 0
  printf '%s %s\n' "$1" "${2:--}" >"$pend" 2>/dev/null || true
  return 0
}
hi_marker_clear() {
  local pend
  pend="$(hi_marker_path)" || return 0
  rm -f -- "$pend"
  return 0
}
hi_marker_get() {
  local pend
  pend="$(hi_marker_path)" || return 0
  [ -f "$pend" ] && [ ! -L "$pend" ] && head -n 1 -- "$pend" 2>/dev/null
  return 0
}
# cur staged → 0 when the marker names the checkout AND records exactly the gitlink staged now (old-format marker: no)
hi_marker_honored() {
  local line t b; line="$(hi_marker_get)"
  [ -n "$line" ] || return 1
  case "$line" in *" "*) ;; *) return 1 ;; esac
  t="${line%% *}"; b="${line#* }"
  [ -n "$1" ] && [ "$t" = "$1" ] && [ "$b" = "${2:--}" ]
}
hi_builtin_update() {
  local sub="$O_ROOT/$1" cur target tsha r fetched=0 rtags="" live=""
  hi_say "using the built-in updater (this constitution version has no scripts/update_constitution.sh)"
  [ -z "$(hi_user_umask hi_gx -C "$sub" status --porcelain 2>/dev/null)" ] || { hi_err "$1 has local changes; refusing"; return 3; }
  while read -r r; do
    [ -n "$r" ] || continue
    if HI_GX_TIMEOUT=300 hi_gx -C "$sub" fetch --quiet --tags "$r" >/dev/null 2>&1; then   # a remote whose fetch failed proves nothing
      fetched=$((fetched+1))
      rtags+="$(hi_remote_tags_of "$sub" "$r")"$'\n'; live+="$(hi_remote_live "$sub" "$r")"$'\n'
    fi
  done < <(hi_gx -C "$sub" remote)
  [ "$fetched" -gt 0 ] || { hi_err "fetch failed for $1 (network?)"; return 3; }
  live="$(printf '%s\n' "$live" | awk 'NF && !s[$0]++')"
  cur="$(hi_gx -C "$sub" rev-parse HEAD)"
  hi_on_remote "$sub" "$cur" "$live" || { hi_err "$1 HEAD has commits no remote knows; refusing"; return 3; }
  if [ -n "$O_REF" ]; then target="$O_REF"
  else target="$(printf '%s\n' "$rtags" | awk '{ print $1 }' | grep -E "$HI_RELEASE_TAG_RE" | sort -u | sort -V | tail -n 1)"
       [ -n "$target" ] || target="origin/main"; fi
  local res; res="$(hi_resolve_ref_in "$sub" "$target" "$rtags")" || { hi_err "target $target not found"; return 3; }
  tsha="${res#* }"
  [ "${res%% *}" = local-ref ] && hi_warn "no remote has a branch or tag named $target: using the LOCAL ref $target"
  hi_on_remote "$sub" "$tsha" "$live" \
    || { hi_err "target $target ($tsha) is not on any remote branch or remote tag: a gitlink to it could not be fetched by a fresh clone; refusing (nothing changed)"; return 3; }
  S_BEFORE="$cur"; S_AFTER="$tsha"
  # A recorded gitlink (staged or committed) is only ever replaced by a descendant of it (same rule as the updater)
  local gl glh glp glk gls
  gl="$(hi_gitlink_of "$O_ROOT" "$1")"; glh="$(hi_gitlink_committed "$O_ROOT" "$1")"
  for glp in "staged:$gl" "committed:$glh"; do
    glk="${glp%%:*}"; gls="${glp#*:}"; [ -n "$gls" ] || continue
    case "$(hi_gitlink_rel "$sub" "$cur" "$gls")" in
      same|recorded-older) ;;
      recorded-newer) S_AFTER="$cur"; hi_err "the project's $glk gitlink records $1 at $gls, which is NEWER than the checked-out $cur (a teammate updated it and the checkout was not moved, e.g. git pull without git submodule update). Nothing changed. Run: git submodule update -- $1   then re-run"; return 3 ;;
      unknown) S_AFTER="$cur"; hi_err "the project's $glk gitlink records $1 at $gls, a commit the checkout ($cur) does not have even after fetching. Nothing changed. Run: git submodule update -- $1 (or fix the recorded gitlink yourself), then re-run"; return 3 ;;
      *) S_AFTER="$cur"; hi_err "the project's $glk gitlink records $1 at $gls, which has DIVERGED from the checked-out $cur. Nothing changed. Review it yourself, e.g. git submodule update -- $1, then re-run"; return 3 ;;
    esac
  done
  # A STAGED gitlink that differs from the committed one AND from the checkout is a change somebody staged by hand:
  # never overwritten (same rule as the updater). Only the marker this function writes before its checkout (and
  # removes after `git add`), naming the checkout, marks that state as this installer's own cut-off update.
  if [ -n "$gl" ] && [ -n "$glh" ] && [ "$gl" != "$glh" ] && [ "$gl" != "$cur" ] && ! hi_marker_honored "$cur" "$gl"; then
    S_AFTER="$cur"
    hi_err "the project's staged gitlink records $1 at $gl, which differs from both the committed gitlink ($glh) and the checkout ($cur): a change somebody staged; it is not overwritten. Nothing changed. To keep the checkout: git add -- $1   to drop the staged change: git restore --staged -- $1   then re-run"
    return 3
  fi
  if [ "$cur" = "$tsha" ]; then
    # HEAD == target, but an earlier run may have been cut off after the checkout, before the gitlink was staged:
    # reconcile the recorded gitlink on every path (an interrupted update must be finished, not reported as current)
    if [ "$gl" != "$cur" ]; then
      hi_say "finishing an interrupted earlier update: the project records ${gl:-no gitlink} but $1 is at $cur"
      hi_git add -- "$1" || { hi_err "could not stage $1 (is .git/index.lock held by another git process?); re-run to finish"; return 1; }
      hi_marker_clear
      S_GL_CHANGED=1; return 0
    fi
    hi_say "already up to date ($target = $cur)"; return 0
  fi
  if hi_gx -C "$sub" merge-base --is-ancestor "$tsha" "$cur"; then hi_say "already up to date: current $cur is ahead of $target"; S_AFTER="$cur"; return 0; fi
  hi_gx -C "$sub" merge-base --is-ancestor "$cur" "$tsha" || { hi_err "$target is not a fast-forward of $cur; refusing (no force, no reset)"; return 3; }
  for gls in "$gl" "$glh"; do   # the new gitlink must descend from every gitlink the project records
    [ -z "$gls" ] || hi_gx -C "$sub" merge-base --is-ancestor "$gls" "$tsha" \
      || { hi_err "$target ($tsha) does not contain the gitlink the project records ($gls); refusing to move it backwards (nothing changed)"; S_AFTER="$cur"; return 3; }
  done
  hi_marker_set "$tsha" "$gl"
  hi_user_umask hi_gx -C "$sub" checkout --quiet --detach "$tsha" || return 1
  hi_git add -- "$1" || { hi_err "could not stage $1 (is .git/index.lock held by another git process?); $1 is already at $tsha: re-run to finish"; return 1; }
  hi_marker_clear
  hi_say "updated $1: $cur -> $tsha ($target); gitlink staged, not committed"
}
hi_do_update() {
  local sub="$1" upd="$O_ROOT/$1/scripts/update_constitution.sh" rc
  local -a a=(--project-root "$O_ROOT")
  if [ -z "$(ls -A "$O_ROOT/$sub" 2>/dev/null)" ]; then
    hi_say "initialising $sub (registered but not checked out)"
    (cd "$O_ROOT" && hi_user_umask hi_git_url "$S_URL" submodule update --init --quiet -- "$sub") >/dev/null 2>&1 || { hi_err "cannot initialise $sub"; return 3; }
  fi
  S_BEFORE="$(hi_gx -C "$O_ROOT/$sub" rev-parse HEAD 2>/dev/null)"
  local gl0; gl0="$(hi_gitlink_of "$O_ROOT" "$sub")"
  if [ -f "$upd" ]; then
    [ -n "$O_REF" ] && a+=(--ref "$O_REF")
    [ "$O_SETUP" = off ] && a+=(--no-hook)
    [ "$O_DECISION" != off ] && a+=(--jev-hook)
    S_UPDATER="delegated"
    hi_say "delegating to $sub/scripts/update_constitution.sh"
    # the updater takes the same run lock; it is told that this process (which holds it) started it
    (hi_scrub_git_env; HELIX_CONSTITUTION_LOCK_DELEGATED="$$" hi_user_umask bash "$upd" "${a[@]}") >&2; rc=$?
    S_AFTER="$(hi_gx -C "$O_ROOT/$sub" rev-parse HEAD 2>/dev/null)"
    if [ "$rc" = 0 ]; then   # an older updater copy may report "up to date" with the gitlink still old: say what is wrong
      local gl; gl="$(hi_gitlink_of "$O_ROOT" "$sub")"
      [ "$gl" = "$gl0" ] || S_GL_CHANGED=1
      [ "$gl" = "$S_AFTER" ] || hi_warn "$sub is at ${S_AFTER:0:12} but the project records ${gl:0:12}: an earlier update was cut off before the gitlink was staged; run 'git add $sub' (or re-run with a current updater)"
    fi
    return "$rc"
  fi
  S_UPDATER="built-in"
  hi_builtin_update "$sub"
}

# §11.4.31: the post-update hook that setup.sh runs gates on a TRACKED, valid helix-deps.yaml at the project root
# (CM-HELIX-DEPS-MANIFEST-PRESENT). A fresh project has none, so on the ADD path with setup.sh on the installer
# creates it first with the constitution's own scaffold tool (never overwriting: a present file, even a symlink, is
# left alone), with the user's umask; a skeleton that validates (no own-org dependency needs a human answer) is
# staged; one with placeholders is left UNTRACKED with the exact next steps (S_MANIFEST=needs-completion).
# S_MANIFEST: present · created · needs-completion · unavailable (constitution version without the tool) · failed
hi_manifest_step() { # 0 ok (any state but failed), 1 failed
  local m="$O_ROOT/helix-deps.yaml" v="$HI_SUB/scripts/deps_manifest/verify_helix_deps_manifests.sh" out rc
  if [ -e "$m" ] || [ -L "$m" ]; then S_MANIFEST=present; return 0; fi
  if [ ! -f "$O_ROOT/$v" ]; then
    S_MANIFEST=unavailable; hi_warn "this constitution version has no $v: helix-deps.yaml was not created (setup.sh may need it)"; return 0
  fi
  hi_backup_file helix-deps.yaml || { S_MANIFEST=failed; return 1; }   # absent: recorded as created by this run
  out="$( (cd "$O_ROOT" && umask "$HI_UMASK0" && hi_scrub_git_env && bash "$v" --scaffold . --write) 2>&1 )"; rc=$?
  if [ "$rc" != 0 ] || [ ! -f "$m" ] || [ -L "$m" ]; then
    S_MANIFEST=failed; hi_err "could not create helix-deps.yaml (exit $rc): $(printf '%s' "$out" | hi_scrub | tail -n 2)"; return 1
  fi
  chmod "$(printf '%o' $(( 0666 & ~0${HI_UMASK0:-022} )))" "$m" || { S_MANIFEST=failed; hi_err "cannot set the mode of helix-deps.yaml"; return 1; }
  S_WRITTEN+=("helix-deps.yaml")
  if (cd "$O_ROOT" && hi_scrub_git_env && bash "$v" --validate-file helix-deps.yaml) >/dev/null 2>&1; then
    hi_git add -- helix-deps.yaml || { S_MANIFEST=failed; hi_err "could not stage helix-deps.yaml"; return 1; }
    S_MANIFEST=created; hi_say "created helix-deps.yaml (valid: no own-org dependency needs your input) and staged it"
  else
    S_MANIFEST=needs-completion
    hi_warn "helix-deps.yaml needs completion: it was created from a skeleton with placeholders only you can fill. It is NOT staged."
    hi_warn "next steps: (1) edit helix-deps.yaml and replace every UNKNOWN placeholder (ref, why)"
    hi_warn "            (2) bash $v --validate-file helix-deps.yaml"
    hi_warn "            (3) git add helix-deps.yaml"
    hi_warn "            (4) bash $HI_SUB/scripts/setup.sh   (or re-run this installer)"
    S_NOTES+=("helix-deps.yaml needs completion (placeholders); left untracked; see the next steps printed by the installer")
  fi
  return 0
}

# ───────────────────────────── agent ─────────────────────────────
hi_agent_kind() { # id → claude|native|provider|kimi|opencode|pi|detect-only|unknown
  local id="$1" t
  case "$id" in claude|kimi|opencode|pi) printf '%s' "$id"; return ;; esac
  t="$(hi_agent_table | awk -F'|' -v i="$id" '$1 == i { print $2 }')"
  [ "$t" = detect-only ] && { printf 'detect-only'; return; }
  if [[ "$id" =~ ^claude[0-9]+$ ]]; then printf 'native'; return; fi
  printf 'provider'
}
# Which limits reach the agent: claude, claudeN and provider aliases get --model/--effort/--max-budget-usd;
# kimi, opencode and pi get none of them (only the timeout, which the installer enforces itself).
hi_agent_honors_limits() { case "$(hi_agent_kind "$1")" in claude|native|provider) return 0 ;; esac; return 1; }
hi_limits_text() { # one line for the plan/log
  if [ "$O_AGENT" = none ]; then printf 'no agent'; return; fi
  if hi_agent_honors_limits "$O_AGENT"; then
    printf 'model %s, effort %s, budget $%s total incl. follow-ups (enforced via --max-budget-usd), timeout %ss per run (enforced)' \
      "$O_MODEL" "$O_EFFORT" "$O_BUDGET" "$O_TIMEOUT"
  else
    printf 'model/effort/budget NOT enforced for %s (no such flags are passed), timeout %ss per run (enforced)' "$O_AGENT" "$O_TIMEOUT"
  fi
}
# kimi, opencode and pi have no verified restrictive-permission option (opencode --auto and kimi --yolo only
# loosen; pi's tool switches would remove tools the setup needs), so they run with their own defaults and
# need explicit consent; the claude family runs with acceptEdits and HI_CLAUDE_DENY
HI_CLAUDE_DENY='WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)'
hi_agent_unrestricted() { [ "$1" != none ] && [ -n "$1" ] && ! hi_agent_honors_limits "$1"; }
hi_check_unrestricted_consent() { # 0 ok, 3 refused
  hi_agent_unrestricted "$O_AGENT" || { S_UNR_CONSENT=not-needed; return 0; }
  if [ "$O_UNRESTRICTED" = 1 ]; then [ "$S_UNR_CONSENT" = interactive ] || S_UNR_CONSENT=flag; return 0; fi
  if [ "$S_UNR_CONSENT" = declined ]; then
    hi_err "not running $O_AGENT: it runs with its own default permissions and you declined; nothing was changed"
  else
    hi_err "$O_AGENT runs with its own default permissions (it can run shell commands in the project directory); pass --allow-unrestricted-agent to accept that, or use claude / a claude alias; nothing was changed"
  fi
  return 3
}
hi_permissions_text() { # one line for the plan
  if [ "$O_AGENT" = none ]; then printf 'no agent'
  elif hi_agent_unrestricted "$O_AGENT"; then
    printf '%s runs with ITS OWN default permissions: it can run shell commands, edit files and reach the network in the project directory (consent: %s)' "$O_AGENT" "$S_UNR_CONSENT"
  else
    printf '%s runs with --permission-mode acceptEdits and --disallowedTools %s; never --dangerously-skip-permissions' "$O_AGENT" "$HI_CLAUDE_DENY"
  fi
}
hi_check_agent_limits() { # 0 ok, 2 refused: a limit the chosen agent cannot honour was asked for explicitly
  local f
  [ "$O_AGENT" = none ] && return 0
  hi_agent_honors_limits "$O_AGENT" && return 0
  for f in --model --effort --max-budget-usd; do
    if hi_was_set "$f"; then
      hi_err "$f cannot be enforced for agent $O_AGENT (the installer passes no such flag to it); drop $f, or use claude / a claude alias"
      return 2
    fi
  done
  return 0
}
hi_alias_file() { printf '%s' "${CLAUDE_MULTI_ACCOUNT_ALIASES:-$HOME/.local/share/claude-multi-account/aliases.sh}"; }
hi_agent_preflight() { # 0 ok, 3 blocked
  local id="$O_AGENT" k
  [ "$id" = none ] && return 0
  k="$(hi_agent_kind "$id")"
  case "$k" in
    detect-only) hi_err "agent $id is detected-only: it cannot run the setup prompt headlessly (use claude, a claude alias, kimi, opencode or pi)"; return 3 ;;
    native) command -v claude >/dev/null 2>&1 && [ -d "$HOME/.claude-$id" ] || { hi_err "native account $id not found (no claude binary or no ~/.claude-$id)"; return 3; } ;;
    provider) local idre="${id//./\\.}"   # the id is matched literally ("." is not a wildcard; ids allow only [A-Za-z0-9._-])
              command -v claude >/dev/null 2>&1 && [ -r "$(hi_alias_file)" ] && grep -qE "^(alias +$idre=|$idre *\\(\\))" "$(hi_alias_file)" \
                || { hi_err "provider alias $id not found in the Claude Toolkit alias file"; return 3; } ;;
    *) command -v "$k" >/dev/null 2>&1 || { hi_err "agent binary $k is not installed"; return 3; } ;;
  esac
  command -v python3 >/dev/null 2>&1 || command -v jq >/dev/null 2>&1 || { hi_err "python3 or jq is required to read the agent's stream-json"; return 3; }
  command -v timeout >/dev/null 2>&1 || { hi_err "timeout (coreutils) is required"; return 3; }
  return 0
}
# hi_run_agent PROMPT_TEXT LOGFILE SESSION-MODE(new|resume) SID BUDGET → prints parser line; rc 0 success
# Environment: ANTHROPIC_API_KEY is always removed. For claude and native claudeN accounts the API routing
# variables ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN are removed too (a native account must use its own
# login, never an endpoint inherited from the caller's shell). Provider aliases run in a SCRUBBED child:
# ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN and CLAUDE_CONFIG_DIR are removed first, then the alias file is
# sourced, so the alias gets exactly the routing it defines itself and nothing from the caller's shell.
hi_run_agent() {
  local prompt="$1" log="$2" smode="$3" sid="$4" budget="$5" id="$O_AGENT" k rc parsed
  local -a cmd=(timeout --kill-after=10 "$O_TIMEOUT" env -u ANTHROPIC_API_KEY)
  local -a cflags=(-p "$prompt" --output-format stream-json --verbose --model "$O_MODEL" --effort "$O_EFFORT"
                   --max-budget-usd "$budget" --permission-mode acceptEdits --disallowedTools "$HI_CLAUDE_DENY")
  if [ "$smode" = new ]; then cflags+=(--session-id "$sid"); else cflags+=(--resume "$sid"); fi
  k="$(hi_agent_kind "$id")"
  case "$k" in
    claude) cmd+=(-u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN claude "${cflags[@]}") ;;
    native) cmd+=(-u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN CLAUDE_CONFIG_DIR="$HOME/.claude-$id" claude "${cflags[@]}") ;;
    provider) cmd+=(-u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CONFIG_DIR bash -c "shopt -s expand_aliases; . \"\$0\""$'\n'"$id \"\$@\"" "$(hi_alias_file)" "${cflags[@]}") ;;
    kimi) cmd+=(kimi -p "$prompt" --output-format stream-json) ;;
    opencode) cmd+=(opencode run --format json "$prompt") ;;
    pi) cmd+=(pi -p --mode json "$prompt") ;;
  esac
  S_AGENT_LINE=""
  : >"$log" && : >"$log.stderr" && chmod 600 "$log" "$log.stderr" || return 1   # transcripts are private
  # a background job + wait: a signal reaches the installer's trap at once (bash defers traps while a
  # foreground child runs, and timeout puts the agent in its own process group, out of reach of Ctrl-C)
  (cd "$O_ROOT" && umask "${HI_UMASK0:-$(umask)}" && hi_scrub_git_env && exec "${cmd[@]}") </dev/null >>"$log" 2>>"$log.stderr" &
  HI_AGENT_PID=$!
  wait "$HI_AGENT_PID"; rc=$?
  HI_AGENT_PID=""
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then S_AGENT_LINE="result=failure session=$sid rate_limited=0 cost=unknown timeout=1"; return 1; fi
  case "$k" in
    claude|native|provider|kimi)
      parsed="$(hi_parse_stream "$log")" || { S_AGENT_LINE="result=none session= rate_limited=0 cost=unknown"; return 1; }
      S_AGENT_LINE="$(hi_term_safe "$parsed")"
      [[ "$parsed" == result=success* ]] ;;
    *) # no result event to read (schema UNCONFIRMED): exit 0 + output is NOT proof of success → unverified (rc 6)
      if [ "$rc" = 0 ] && [ -s "$log" ]; then S_AGENT_LINE="result=unverified session= rate_limited=0 cost=unknown evidence=exit-code-only"; return 6; fi
      S_AGENT_LINE="result=failure session= rate_limited=0 cost=unknown evidence=exit-code-only"; return 1 ;;
  esac
}
# budget left for the next run (claude family): total minus what the agent reported spending so far
hi_budget_left() { awk -v b="$O_BUDGET" -v s="$S_SPENT" 'BEGIN { r = b - s; if (r < 0) r = 0; printf "%.4f", r }' | sed -E 's/\.?0+$//; s/^$/0/'; }
hi_account_cost() { # parser line → adds its cost to S_SPENT, or marks the spend as untrackable
  local c; c="$(printf '%s' "$1" | sed -n 's/.* cost=\([^ ]*\).*/\1/p')"
  if [[ "$c" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]]; then S_SPENT="$(awk -v a="$S_SPENT" -v c="$c" 'BEGIN { printf "%.4f", a + c }')"
  else S_COST_KNOWN=0; fi
}
hi_prompt_context() {
  printf '\n\n--- Installer context (facts from install_constitution.sh %s) ---\n' "$HI_VERSION"
  printf 'project_root: %s\nlayout: %s\nconstitution_path: %s\nconstitution_commit: %s\n' "$O_ROOT" "$S_MODE" "$S_SUBREL" "$S_AFTER"
  printf 'consent.edit_agent_docs: %s\nconsent.register_hooks: %s\nconsent.commit: %s\npush: never\ndecision_layer: %s\n' \
    "$O_EDIT_DOCS" "$O_HOOKS" "$O_COMMIT" "$O_DECISION"
  printf 'backup_dir: %s\n' "$S_BK"
}
# Snapshot taken before and after the agent run, one record per line, repositories named by INDEX (0 = the project,
# 1 = the constitution) so a project path with spaces or any other character cannot change how a line parses:
#   M <idx> <ref> <n>          remote-tracking ref with n "update by push" reflog entries
#   R <idx> <ref> <sha> <nf>   the tracking ref's value and how many fetch entries its reflog shows (a push made with
#                              reflogs off, or with the reflog expired afterwards, leaves a new or moved ref that no
#                              fetch explains)
#   L <idx> <remote> <hash>    fingerprint (hi_mark_hash) of the FULL `ls-remote <remote>` output: every branch, tag, note and other ref the
#                              remote advertises right now (a tag push, a refs/notes push, a push that leaves no reflog)
#   U <idx> <remote>           the remote could not be asked (before the run: skipped and named; after an L: fails closed)
#   D <idx> <dir>              the repository directory (rest of the line), so a later look can ask by URL from it
#   N <idx> <remote>           a configured remote (a remote present before the run and gone after it fails closed)
#   V <idx> <hash> <url>       fingerprint of `ls-remote <url>` for every url AND pushurl of every remote (rest of the line
#                              is the url): after the run the BEFORE urls are asked again directly, so removing,
#                              renaming or re-pointing a remote after a push does not hide the push
#   X <idx> <url>              that url could not be asked
#   Z <idx> <remote|url>       it answered but no fingerprint tool exists (hi_mark_hash): the check fails closed
# stdin → a short fingerprint of the sorted lines (sha256sum, else cksum); exit 1 when neither exists
# (an empty fingerprint must never be written: it would make every later comparison meaningless)
hi_mark_hash() {
  local t o
  if command -v sha256sum >/dev/null 2>&1; then t=sha256sum; o="$(LC_ALL=C sort | sha256sum 2>/dev/null)" || return 1
  elif command -v cksum >/dev/null 2>&1; then t=cksum; o="$(LC_ALL=C sort | cksum 2>/dev/null)" || return 1
  else cat >/dev/null; return 1; fi
  o="${o//[[:space:]]/}"; [ -n "$o" ] || return 1
  printf '%s:%s' "$t" "$o"
}
hi_push_marks() {
  local d r n o i=0 u h
  for d in "$O_ROOT" "$O_ROOT/$S_SUBREL"; do
    if [ -e "$d/.git" ]; then
      printf 'D %s %s\n' "$i" "$d"
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        n="$(hi_gx -C "$d" log -g --format=%gs "$r" -- 2>/dev/null | grep -c '^update by push')"
        [ "${n:-0}" -gt 0 ] && printf 'M %s %s %s\n' "$i" "$r" "$n"
        printf 'R %s %s %s %s\n' "$i" "$r" "$(hi_gx -C "$d" rev-parse --verify --quiet "$r" 2>/dev/null)" \
          "$(hi_gx -C "$d" log -g --format=%gs "$r" -- 2>/dev/null | grep -c '^fetch')"
      done < <(hi_gx -C "$d" for-each-ref --format='%(refname)' refs/remotes 2>/dev/null)
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        printf 'N %s %s\n' "$i" "$r"
        if o="$(HI_GX_TIMEOUT=60 hi_gx -C "$d" ls-remote "$r" 2>/dev/null)"; then
          if h="$(printf '%s\n' "$o" | hi_mark_hash)"; then printf 'L %s %s %s\n' "$i" "$r" "$h"; else printf 'Z %s %s\n' "$i" "$r"; fi
        else printf 'U %s %s\n' "$i" "$r"; fi
        while IFS= read -r u; do
          [ -n "$u" ] || continue
          if o="$(HI_GX_TIMEOUT=60 hi_gx -C "$d" ls-remote -- "$u" 2>/dev/null)"; then
            if h="$(printf '%s\n' "$o" | hi_mark_hash)"; then printf 'V %s %s %s\n' "$i" "$h" "$u"; else printf 'Z %s %s\n' "$i" "$u"; fi
          else printf 'X %s %s\n' "$i" "$u"; fi
        done < <({ hi_gx -C "$d" config --get-all "remote.$r.url"; hi_gx -C "$d" config --get-all "remote.$r.pushurl"; } 2>/dev/null | awk '!s[$0]++')
      done < <(hi_gx -C "$d" remote 2>/dev/null)
    fi
    i=$((i+1))
  done
  return 0
}
# before after → 0 when a push is evident: any reflog mark changed, a tracking ref that moved with no fetch to
# explain it, or a remote that could be asked both times advertises other refs (any namespace) than before.
# Also: a remote configured before the run that is gone after it fails closed (a push followed by `git remote
# remove`), and every url/pushurl a remote had before the run is asked again BY URL (re-pointing or renaming a
# remote after a push, a push through a pushurl).
# LIMITS, listed honestly in --help: (a) a false positive when somebody else pushes to the remote during the run
# (fail closed: the run is refused); (b) a push by URL (or to a remote the repository does not configure, or to a
# remote added during the run) that leaves no reflog entry and no tracking-ref change is NOT detected; (c) a remote
# or url that could not be asked BEFORE the run is skipped, not trusted, and named on stderr (one that answered
# before and cannot be asked after it fails closed, like a removed remote); (d) a push to another repository (not the project and
# not the constitution), and any push the remote reverses before the second look, are not seen.
hi_push_changed() {
  local b="$1" a="$2" k i r s f h
  local w
  while read -r k i r; do       # only what could not be asked BEFORE the run is skipped, and it is named (limit c)
    [ "$k" = U ] || [ "$k" = X ] || continue
    if [ "$i" = 0 ]; then w=project; else w=constitution; fi
    if [ "$k" = U ]; then w="remote '$r' of the $w"; else w="url $(printf '%s' "$r" | hi_scrub) of the $w"; fi
    hi_warn "no-push check: $w could not be asked before the agent run; a push to it cannot be seen (skipped, not trusted)"
  done <<<"$b"
  if printf '%s\n%s\n' "$b" "$a" | grep -q '^Z '; then   # a remote answered but no fingerprint tool exists: fail closed
    hi_err "no-push check: no cksum or sha256sum on PATH: what the remotes advertise cannot be compared; the run is refused (fail closed)"
    return 0
  fi
  [ "$(printf '%s\n' "$b" | grep '^M ')" = "$(printf '%s\n' "$a" | grep '^M ')" ] || return 0
  while read -r k i r s f; do   # R lines: a ref that is new or moved with no fetch in its reflog
    [ "$k" = R ] || continue
    [[ "$s" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || continue
    [ "${f:-0}" -gt 0 ] && continue
    printf '%s\n' "$b" | grep -qxF -- "R $i $r $s ${f:-0}" && continue
    return 0
  done <<<"$a"
  while read -r k i r h; do     # L lines: a remote that answered before must answer the SAME after, or it fails closed
    [ "$k" = L ] || continue    # (changed refs, or unaskable after: re-pointed by insteadOf, protocol denied, moved, unreadable)
    printf '%s\n' "$a" | grep -qxF -- "L $i $r $h" && continue
    return 0
  done <<<"$b"
  while read -r k i r; do       # N lines: a remote configured before the run and gone after it (removed, renamed): fail closed
    [ "$k" = N ] || continue
    printf '%s\n' "$a" | grep -qxF -- "N $i $r" || return 0
  done <<<"$b"
  local u h1 dir o
  while read -r k i h u; do     # V lines: every url/pushurl the remotes had BEFORE the run, asked again BY URL
    [ "$k" = V ] || continue
    h1="$(printf '%s\n' "$a" | HI_U="$u" HI_I="$i" awk '$1 == "V" && $2 == ENVIRON["HI_I"] { x = $0; sub(/^V [^ ]+ [^ ]+ /, "", x); if (x == ENVIRON["HI_U"]) { print $3; exit } }')"
    if [ -z "$h1" ]; then       # the url is no longer configured: ask it directly from the same repository
      dir="$(printf '%s\n' "$b" | HI_I="$i" awk '$1 == "D" && $2 == ENVIRON["HI_I"] { sub(/^D [^ ]+ /, ""); print; exit }')"
      [ -n "$dir" ] || return 0
      o="$(HI_GX_TIMEOUT=60 hi_gx -C "$dir" ls-remote -- "$u" 2>/dev/null)" || return 0   # answered before, not now: fail closed
      h1="$(printf '%s\n' "$o" | hi_mark_hash)" || return 0
    fi
    [ "$h1" = "$h" ] || return 0
  done <<<"$b"
  return 1
}
hi_agent_step() { # 0 ok, 4 failed, 3 blocked, 6 ran but unverified (exit-code-only agents)
  local pf="$O_ROOT/$S_SUBREL/docs/prompts/setup/latest.md" prompt sid line n=0 f body req prevok=1 fdir budget left
  [ -f "$pf" ] || { hi_err "setup prompt not found: $S_SUBREL/docs/prompts/setup/latest.md (this constitution version predates it)"; return 3; }
  prompt="$(hi_extract_prompt "$pf")" || { hi_err "no fenced block under '## PROMPT' in latest.md"; return 3; }
  sid="$(hi_uuid)"; hi_backup_dir >/dev/null || return 1; mkdir -p "$S_BK/agent" || return 1
  prompt+="$(hi_prompt_context)"
  [ "${#prompt}" -lt 120000 ] || { hi_err "prompt too large for an argument (${#prompt} bytes)"; return 3; }
  hi_say "running agent $O_AGENT headlessly ($(hi_limits_text)); log: $S_BK/agent/run_0.jsonl"
  hi_run_agent "$prompt" "$S_BK/agent/run_0.jsonl" new "$sid" "$O_BUDGET"; local ok=$?; line="$S_AGENT_LINE"
  hi_account_cost "$line"
  S_SID="$(printf '%s' "$line" | sed -n 's/.*session=\([^ ]*\).*/\1/p')"
  if [ -n "$S_SID" ] && ! [[ "$S_SID" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]]; then
    hi_warn "the agent reported a malformed session id; using the installer's own ($sid)"; S_SID=""
  fi
  [ -n "$S_SID" ] || S_SID="$sid"
  S_AGENT_EVIDENCE="$(printf '%s' "$line" | sed -n 's/.*evidence=\([^ ]*\).*/\1/p')"; [ -n "$S_AGENT_EVIDENCE" ] || S_AGENT_EVIDENCE="result-event"
  if [[ "$line" == *rate_limited=1* ]]; then hi_err "agent hit a rate limit (HTTP 429); re-run later or pick another alias"; fi
  if [[ "$line" == *timeout=1* ]]; then hi_err "agent timed out after ${O_TIMEOUT}s"; fi
  if [ "$ok" = 6 ]; then
    S_AGENT_STATUS="unverified"
    hi_warn "agent $O_AGENT exited 0 but its success is UNVERIFIED (evidence: exit code only; it emits no result event the installer can read). Review $S_BK/agent/ and the project yourself."
    return 6
  fi
  if [ "$ok" != 0 ]; then S_AGENT_STATUS="failure"; hi_err "agent run failed ($line); see $S_BK/agent/"; return 4; fi
  S_AGENT_STATUS="success"; hi_say "agent run succeeded (session $S_SID)"
  [ "$O_FOLLOWUPS" = on ] || return 0
  case "$(hi_agent_kind "$O_AGENT")" in claude|native|provider) ;; *) hi_warn "follow-ups need session resume; not supported for $O_AGENT"; S_FOLLOW+=("all|skipped-unsupported"); return 0 ;; esac
  fdir="$O_ROOT/$S_SUBREL/docs/prompts/setup/followups"
  for f in "$fdir"/[0-9]*_*.md; do
    [ -f "$f" ] || continue
    n=$((n+1)); req="$(hi_followup_requires "$f")"
    if [ "$req" = true ] && [ "$prevok" = 0 ]; then S_FOLLOW+=("$(basename "$f")|skipped-previous-failed"); continue; fi
    if [ "$S_COST_KNOWN" = 1 ]; then
      left="$(hi_budget_left)"
      if ! awk -v l="$left" 'BEGIN { exit !(l + 0 >= 0.01) }'; then
        S_FOLLOW+=("$(basename "$f")|skipped-budget-exhausted"); hi_warn "budget \$$O_BUDGET spent (\$$S_SPENT reported); follow-up $(basename "$f") not run"
        prevok=0; continue
      fi
      budget="$left"
    else
      budget="$O_BUDGET"
      hi_warn "the agent did not report its cost: the remaining budget cannot be tracked; follow-up $(basename "$f") gets \$$O_BUDGET again (worst case (1 + follow-ups) x \$$O_BUDGET)"
    fi
    body="$(hi_followup_body "$f")"
    hi_say "follow-up $(basename "$f") (resume $S_SID, budget \$$budget)"
    if hi_run_agent "$body" "$S_BK/agent/run_$n.jsonl" resume "$S_SID" "$budget"; then line="$S_AGENT_LINE"
      S_FOLLOW+=("$(basename "$f")|success"); prevok=1
    else
      line="$S_AGENT_LINE"; S_FOLLOW+=("$(basename "$f")|failure"); prevok=0; hi_err "follow-up $(basename "$f") failed ($line)"
    fi
    hi_account_cost "$line"
  done
  local x; for x in ${S_FOLLOW[@]+"${S_FOLLOW[@]}"}; do [[ "$x" == *"|failure" ]] && return 4; done
  return 0
}

# ───────────────────────────── verify + report ─────────────────────────────
hi_check() { S_VERIFY+=("$1|$2"); if [ "$2" = fail ]; then hi_err "verify: $1 FAILED"; fi; return 0; }
hi_verify() { # strict: 1 when only installer-controlled changes are expected
  local strict="$1" gl head sm f blk p line
  S_VERIFY=()
  sm="$(hi_gx -C "$O_ROOT" config -f "$O_ROOT/.gitmodules" --get "submodule.$HI_SUB.path" 2>/dev/null)"
  [ "$sm" = "$HI_SUB" ] && hi_check submodule_registered pass || hi_check submodule_registered fail
  gl="$(hi_git ls-files -s -- "$HI_SUB" | awk '$1 == "160000" { print $2 }')"
  [ -n "$gl" ] && hi_check gitlink_recorded pass || hi_check gitlink_recorded fail
  head="$(hi_gx -C "$O_ROOT/$HI_SUB" rev-parse HEAD 2>/dev/null)"
  [ -n "$gl" ] && [ "$gl" = "$head" ] && hi_check submodule_head_matches_gitlink pass || hi_check submodule_head_matches_gitlink fail
  hi_gx -C "$O_ROOT/$HI_SUB" cat-file -e "$head^{commit}" 2>/dev/null && [ -z "$(hi_user_umask hi_gx -C "$O_ROOT/$HI_SUB" status --porcelain 2>/dev/null)" ] \
    && hi_check submodule_clean pass || hi_check submodule_clean fail
  if [ "$O_EDIT_DOCS" = on ]; then
    for f in CLAUDE.md AGENTS.md; do hi_has_block "$f" && hi_check "inheritance_${f%.md}" pass || hi_check "inheritance_${f%.md}" fail; done
    grep -qxF '@submodules/constitution/CLAUDE.md' "$O_ROOT/CLAUDE.md" 2>/dev/null && hi_check claude_import pass || hi_check claude_import fail
    blk=""; for f in ${S_WRITTEN[@]+"${S_WRITTEN[@]}"}; do
      blk+="$(awk -v b="$HI_MARK_BEGIN" -v e="$HI_MARK_END" '$0 == b { on = 1 } on { print } $0 == e { on = 0 }' "$O_ROOT/$f" 2>/dev/null)"$'\n'; done
    if printf '%s' "$blk" | grep -E '(^|[^/A-Za-z_])constitution/' | grep -vq 'submodules/constitution/'; then hi_check no_legacy_path_in_written fail
    else hi_check no_legacy_path_in_written pass; fi
  else
    hi_check inheritance skip
  fi
  hi_status_paths; S_CHANGED=(${S_TMP_PATHS[@]+"${S_TMP_PATHS[@]}"})
  local unexpected="" q pre
  for p in ${S_CHANGED[@]+"${S_CHANGED[@]}"}; do
    case "$p" in .gitmodules|"$HI_SUB"|CLAUDE.md|AGENTS.md|GEMINI.md|QWEN.md) continue ;; esac
    case "$p:$S_MANIFEST" in helix-deps.yaml:created|helix-deps.yaml:needs-completion) continue ;; esac
    pre=0; for q in ${S_PRESTATUS[@]+"${S_PRESTATUS[@]}"}; do [ "$q" = "$p" ] && { pre=1; break; }; done
    [ "$pre" = 1 ] || unexpected+="$(hi_term_safe "$p") "
  done
  if [ -z "$unexpected" ]; then hi_check status_only_expected_paths pass
  elif [ "$strict" = 1 ]; then hi_check status_only_expected_paths fail; hi_err "unexpected changed paths: $unexpected"
  else hi_check status_only_expected_paths info; hi_say "other changed paths (agent/setup): $unexpected"; fi
  S_VERIFY_OVERALL=pass
  for p in ${S_VERIFY[@]+"${S_VERIFY[@]}"}; do [[ "$p" == *"|fail" ]] && S_VERIFY_OVERALL=fail; done
  [ "$S_VERIFY_OVERALL" = pass ]
}
hi_write_report() {
  local out="" x k v first f path
  out+="{\"installer_version\":$(hi_json_str "$HI_VERSION"),\"status\":$(hi_json_str "$S_STATUS"),\"exit_code\":$S_RC"
  out+=",\"mode\":$(hi_json_str "$S_MODE"),\"dry_run\":$([ "$O_DRY" = 1 ] && echo true || echo false)"
  out+=",\"project_root\":$(hi_json_str "$O_ROOT"),\"submodule_path\":$(hi_json_str "${S_SUBREL:-$HI_SUB}")"
  out+=",\"upstream_key\":$(hi_json_str "$S_KEY"),\"upstream_url\":$(hi_json_str "$(hi_sanitize_url "$S_URL")")"
  out+=",\"ref\":$(hi_json_str "$S_REF"),\"commit_before\":$(hi_json_str "$S_BEFORE"),\"commit_after\":$(hi_json_str "$S_AFTER")"
  out+=",\"updater\":$(hi_json_str "$S_UPDATER"),\"agent\":$(hi_json_str "$O_AGENT"),\"agent_status\":$(hi_json_str "$S_AGENT_STATUS")"
  local perm=accept-edits+deny-list; [ "$O_AGENT" = none ] && perm=no-agent; hi_agent_unrestricted "$O_AGENT" && perm=agent-default
  out+=",\"agent_permissions\":$(hi_json_str "$perm")"
  out+=",\"session_id\":$(hi_json_str "$S_SID"),\"model\":$(hi_json_str "$O_MODEL"),\"effort\":$(hi_json_str "$O_EFFORT")"
  out+=",\"agent_evidence\":$(hi_json_str "$S_AGENT_EVIDENCE"),\"clone\":$(hi_json_str "$S_CLONE"),\"manifest\":$(hi_json_str "${S_MANIFEST:-not-applicable}")"
  local lim=enforced; { [ "$O_AGENT" = none ] || hi_agent_honors_limits "$O_AGENT"; } || lim=not-enforced
  [ "$O_AGENT" = none ] && lim=no-agent
  out+=",\"limits\":{\"model\":$(hi_json_str "$lim"),\"effort\":$(hi_json_str "$lim"),\"budget_usd\":$(hi_json_str "$lim"),\"budget_total_usd\":$(hi_json_str "$O_BUDGET"),\"budget_spent_usd\":$(hi_json_str "$([ "$S_COST_KNOWN" = 1 ] && printf '%s' "$S_SPENT" || printf 'unknown')"),\"timeout_sec\":$(hi_json_str "$O_TIMEOUT"),\"timeout\":$(hi_json_str "$([ "$O_AGENT" = none ] && echo no-agent || echo enforced)")}"
  out+=",\"consent\":{\"edit_agent_docs\":$(hi_json_str "$O_EDIT_DOCS"),\"register_hooks\":$(hi_json_str "$O_HOOKS"),\"run_setup\":$(hi_json_str "$O_SETUP"),\"commit\":$(hi_json_str "$O_COMMIT"),\"push\":\"never\",\"decision_layer\":$(hi_json_str "$O_DECISION"),\"followups\":$(hi_json_str "$O_FOLLOWUPS"),\"unrestricted_agent\":$(hi_json_str "${S_UNR_CONSENT:-not-needed}")}"
  out+=",\"followups_run\":["; first=1
  for x in ${S_FOLLOW[@]+"${S_FOLLOW[@]}"}; do [ "$first" = 1 ] || out+=","; first=0; out+="{\"file\":$(hi_json_str "${x%%|*}"),\"status\":$(hi_json_str "${x#*|}")}"; done
  out+="],\"verify\":{"; first=1
  for x in ${S_VERIFY[@]+"${S_VERIFY[@]}"}; do [ "$first" = 1 ] || out+=","; first=0; k="${x%%|*}"; v="${x#*|}"; out+="$(hi_json_str "$k"):$(hi_json_str "$v")"; done
  [ "$first" = 1 ] || out+=","; out+="\"overall\":$(hi_json_str "$S_VERIFY_OVERALL")}"
  out+=",\"written_files\":["; first=1
  for x in ${S_WRITTEN[@]+"${S_WRITTEN[@]}"}; do [ "$first" = 1 ] || out+=","; first=0; out+="$(hi_json_str "$x")"; done
  out+="],\"changed_paths\":["; first=1
  for x in ${S_CHANGED[@]+"${S_CHANGED[@]}"}; do [ "$first" = 1 ] || out+=","; first=0; out+="$(hi_json_str "$x")"; done
  out+="],\"notes\":["; first=1
  for x in ${S_NOTES[@]+"${S_NOTES[@]}"}; do [ "$first" = 1 ] || out+=","; first=0; out+="$(hi_json_str "$x")"; done
  out+="],\"backup_dir\":$(hi_json_str "$S_BK"),\"started_at\":$(hi_json_str "$S_STARTED"),\"finished_at\":$(hi_json_str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")}"
  for path in "${S_BK:+$S_BK/report.json}" "$O_REPORT"; do
    [ -n "$path" ] || continue
    [ "$O_DRY" = 1 ] && [ "$path" != "$O_REPORT" ] && continue
    f="$(mktemp "$(dirname -- "$path")/.report.XXXXXX" 2>/dev/null)" || { hi_warn "cannot write report $path"; continue; }
    printf '%s\n' "$out" >"$f" && mv -f -- "$f" "$path" || rm -f -- "$f"
  done
}
hi_finish() { # status rc
  S_STATUS="$1"; S_RC="$2"
  hi_write_report
  hi_unlock
  [ -n "$S_BK" ] && [ "$O_DRY" = 0 ] && hi_say "report: $S_BK/report.json"
  [ -n "$O_REPORT" ] && hi_say "report: $O_REPORT"
  return "$2"
}

# ───────────────────────────── restore ─────────────────────────────
hi_symlinked_parent() { # root rel → 0 when any parent directory of rel inside root is a symlink
  local root="$1" rel="$2" pfx="" part
  local -a parts=()
  [[ "$rel" == */* ]] || return 1
  IFS='/' read -r -a parts <<<"${rel%/*}"
  for part in ${parts[@]+"${parts[@]}"}; do
    pfx="${pfx:+$pfx/}$part"
    [ -L "$root/$pfx" ] && return 0
  done
  return 1
}
hi_restore_rel() { # manifest entry → normalised relative path on stdout; 1 when the entry may not be restored
  local e="$1" seg low out="" LC_ALL=C; local -a segs
  case "$e" in ""|/*) return 1 ;; esac
  [[ "$e" =~ [^\ -~] ]] && return 1          # printable ASCII only (no control bytes, no look-alike Unicode)
  [[ "$e" == *\\* ]] && return 1
  IFS=/ read -r -a segs <<<"$e"
  for seg in "${segs[@]}"; do
    case "$seg" in ""|.) continue ;; ..) return 1 ;; esac
    low="$(printf '%s' "$seg" | tr 'A-Z' 'a-z')"; while [[ "$low" == *[.\ ] ]]; do low="${low%?}"; done
    [ "$low" = .git ] && return 1               # never into git's own directory, at any depth (.git, .GIT, ".git.")
    out="${out:+$out/}$seg"
  done
  [ -n "$out" ] || return 1
  low="$(printf '%s' "$out" | tr 'A-Z' 'a-z')"
  case "$low/" in constitution/*|submodules/constitution/*|"$HI_BACKUP_ROOT"/*) return 1 ;; esac
  printf '%s' "$out"
}
hi_restore() {
  local dir rootabs bkroot rel norm n=0 skipped=0 uid mode
  rootabs="$(cd -P -- "$O_ROOT" && pwd)" || { hi_err "project root not found"; return 2; }
  bkroot="$rootabs/$HI_BACKUP_ROOT"; uid="$(id -u)"
  [ -L "$bkroot" ] && { hi_err "$HI_BACKUP_ROOT is a symlink; refusing to restore"; return 2; }
  [ -L "${O_RESTORE%/}" ] && { hi_err "--restore points at a symlink; refusing to restore"; return 2; }
  dir="$(cd -P -- "$O_RESTORE" 2>/dev/null && pwd)" || { hi_err "backup dir not found"; return 2; }
  [ "${dir%/*}" = "$bkroot" ] || { hi_err "--restore must point at a backup directory directly inside $bkroot/"; return 2; }
  # a backup someone committed (or a directory another user could have written) is not trusted: restoring it
  # could plant files the user never had
  if [ -n "$(hi_gx -C "$rootabs" ls-files -- "$HI_BACKUP_ROOT" 2>/dev/null)" ]; then
    hi_err "$HI_BACKUP_ROOT is tracked by git (a committed backup is not trusted); refusing to restore"; return 2; fi
  mode="$(stat -c '%u %a' -- "$dir" 2>/dev/null || stat -f '%u %Lp' -- "$dir" 2>/dev/null)"
  [ "$mode" = "$uid 700" ] || { hi_err "backup dir must be owned by you and mode 700 (found: ${mode:-unknown}); refusing to restore"; return 2; }
  [ -f "$dir/manifest.txt" ] || { hi_say "nothing to restore (no manifest)"; return 0; }
  { [ ! -L "$dir/manifest.txt" ] && [ -O "$dir/manifest.txt" ]; } \
    || { hi_err "manifest.txt is a symlink or not owned by you; refusing to restore"; return 2; }
  while IFS= read -r rel; do
    norm="$(hi_restore_rel "$rel")" || { hi_warn "skipping unsafe manifest entry: $(printf '%q' "$rel")"; skipped=$((skipped+1)); continue; }
    if [ -L "$dir/files/$norm" ] || [ ! -f "$dir/files/$norm" ]; then
      hi_warn "skipping $norm: the backup copy is missing or not a regular file"; skipped=$((skipped+1)); continue; fi
    if hi_symlinked_parent "$dir/files" "$norm"; then hi_warn "skipping $norm: a parent in the backup is a symlink"; skipped=$((skipped+1)); continue; fi
    [ -L "$rootabs/$norm" ] && { hi_warn "not restoring $norm through a symlink"; skipped=$((skipped+1)); continue; }
    if hi_symlinked_parent "$rootabs" "$norm"; then hi_warn "not restoring $norm: a parent directory is a symlink"; skipped=$((skipped+1)); continue; fi
    hi_user_umask mkdir -p -- "$rootabs/$(dirname -- "$norm")" && cp -p -- "$dir/files/$norm" "$rootabs/$norm" && n=$((n+1)) && hi_say "restored $norm"
  done <"$dir/manifest.txt"
  [ -f "$dir/created.txt" ] && hi_say "files created by that run (not removed automatically): $(paste -sd' ' "$dir/created.txt")"
  hi_say "restored $n file(s); skipped $skipped"
}

# ───────────────────────────── plan ─────────────────────────────
hi_print_plan() {
  printf '\n=== DRY RUN — nothing will be written ===\n'
  printf 'project:          %s\nlayout detected:  %s\nupstream:         %s (%s)\nref:              %s\n' \
    "$O_ROOT" "$S_LAYOUT" "$(hi_sanitize_url "$S_URL")" "$S_KEY" "$S_REF"
  case "$S_MODE" in
    add) printf 'step: git clone --filter=blob:none --no-checkout %s (blobless: every commit and tag, contents on demand; full clone if the server refuses)\nstep: checkout --detach %s, then git submodule add -- %s %s + absorbgitdirs\nstep: git submodule update --init -- %s (flat: nested engines stay uninitialised)\n' \
           "$(hi_sanitize_url "$S_URL")" "$S_REF" "$(hi_sanitize_url "$S_URL")" "$HI_SUB" "$HI_SUB" ;;
    update) printf 'step: %s/scripts/update_constitution.sh (or the built-in fast-forward updater): fetch, fast-forward only, stage gitlink\n' "$S_SUBREL" ;;
    legacy) printf 'step: legacy ./constitution found: no automatic move; migration via the agent prompt or manual steps\n' ;;
  esac
  [ "$O_EDIT_DOCS" = on ] && printf 'step: prepend the inheritance block to CLAUDE.md and AGENTS.md (GEMINI.md/QWEN.md if present), after backup\n'
  [ "$O_SETUP" = on ] && [ "$S_MODE" = add ] && [ ! -e "$O_ROOT/helix-deps.yaml" ] && [ ! -L "$O_ROOT/helix-deps.yaml" ] \
    && printf 'step: create helix-deps.yaml with %s/scripts/deps_manifest/verify_helix_deps_manifests.sh --scaffold (never overwrites); stage it if it validates, else leave it untracked with next steps\n' "$HI_SUB"
  [ "$O_SETUP" = on ] && printf 'step: run %s/scripts/setup.sh (CONSTITUTION_JEV_HOOK=%s)\n' "$HI_SUB" "$([ "$O_DECISION" = off ] && echo off || echo on)"
  [ "$O_DECISION" != off ] && printf 'step: run %s/scripts/jev/bootstrap.sh --non-interactive (%s)\n' "$HI_SUB" "$O_DECISION"
  [ "$O_AGENT" != none ] && printf 'step: run agent %s headlessly: %s; follow-ups %s\n' "$O_AGENT" "$(hi_limits_text)" "$O_FOLLOWUPS"
  [ "$O_AGENT" != none ] && printf 'step: agent permissions: %s\n' "$(hi_permissions_text)"
  printf 'step: deterministic post-verify; report JSON\n'
  [ "$O_COMMIT" = on ] && printf 'step: git commit (local only)\n'
  printf 'push: never\nbackups: %s/%s/<stamp>/\n=== end of plan ===\n\n' "$O_ROOT" "$HI_BACKUP_ROOT"
}

# ───────────────────────────── main ─────────────────────────────
main() {
  if [ "${HELIX_INSTALLER_LIB_MODE:-}" = 1 ]; then   # test switch: only a SOURCED copy stops here
    [ "$HI_SOURCED" = 1 ] && return 0
    echo "install_constitution.sh: WARNING: ignoring HELIX_INSTALLER_LIB_MODE=1 (a test switch for sourcing; this file is being run)" >&2
  fi
  if [ "$#" -lt 1 ] || [ "${!#}" != "__helix_installer_eof__" ]; then
    echo "install_constitution.sh: incomplete script (truncated download?); refusing to run" >&2
    exit 2
  fi
  set -- "${@:1:$(($# - 1))}"
  hi_bash_ok "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" \
    || { hi_err "bash 4.4 or newer is required (this is bash $BASH_VERSION); on macOS: brew install bash, then pipe into that bash"; exit 3; }
  set -u -o pipefail
  exec 9>&2   # hi_gx refusals reach the user even when a call's stderr is redirected
  hi_init_state
  hi_parse_args "$@" || exit 2
  hi_check_insecure || exit 2
  case "$O_ACTION" in
    help) hi_help; exit 0 ;;
    version) printf 'install_constitution.sh %s\n' "$HI_VERSION"; exit 0 ;;
    snippets) hi_print_snippets; exit 0 ;;
  esac
  # every other mode needs these; check them all up front (one clear message, nothing written)
  local tool; local -a missing=()
  for tool in git grep awk sed cmp mktemp timeout; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
  [ "${#missing[@]}" -eq 0 ] || { hi_err "required tool(s) not found: ${missing[*]} (install them, e.g. git, grep, gawk/mawk, sed, diffutils, coreutils); nothing was changed"; exit 3; }
  case "$O_ACTION" in
    detect-agents)
      if [ "$O_JSON" = 1 ]; then hi_detect_agents_json | hi_text_filter
      else hi_detect_agents | awk -F'|' '{ printf "%-36s %-15s %-12s %-6s %s\n", $1, $2, $3, $4, $6 }' | hi_text_filter; fi
      exit 0 ;;
  esac
  [ -n "$O_ROOT" ] || O_ROOT="$PWD"
  O_ROOT="$(cd -P -- "$O_ROOT" 2>/dev/null && pwd)" || { hi_err "project root does not exist"; exit 2; }
  # never into the constitution repository itself (checked for every mode: install, --dry-run, --restore,
  # --detect-layout, interactive) BEFORE anything is asked, locked, backed up or written
  local d0 top0 why; top0="$(hi_gx -C "$O_ROOT" rev-parse --show-toplevel 2>/dev/null)"
  for d0 in "$O_ROOT" ${top0:+"$top0"}; do
    why="$(hi_is_constitution_repo "$d0")" || continue
    [ "$O_ACTION" = detect-layout ] && { echo constitution-repo; exit 0; }
    hi_err "$d0 is the constitution repository itself ($why); refusing to install into it. Nothing was changed."
    hi_err "run the installer in the project that should USE the constitution (or pass --project-root PROJECT)."
    exit 3
  done
  case "$O_ACTION" in
    detect-layout) hi_layout "$O_ROOT"; exit 0 ;;
    restore) hi_restore; exit $? ;;
  esac
  # Private by default: backups, agent transcripts and reports are readable by the user only. Work on
  # project content (clone, checkout, setup.sh, the agent) runs with the user's own umask (hi_user_umask).
  HI_UMASK0="$(umask)"; umask 077
  export GIT_TERMINAL_PROMPT=0
  hi_gx_bin || exit 3   # git resolved once, before anything can change PATH
  local euid; euid="$(id -u)"
  if [ -n "${HELIX_INSTALLER_TEST_EUID:-}" ]; then   # test seam (can only add the root refusal); needs HELIX_INSTALLER_TEST=1
    if [ "${HELIX_INSTALLER_TEST:-}" = 1 ]; then [ "$HELIX_INSTALLER_TEST_EUID" = 0 ] && euid=0
    else hi_warn "ignoring HELIX_INSTALLER_TEST_EUID (a test switch; honoured only with HELIX_INSTALLER_TEST=1)"; fi
  fi
  if [ "$euid" = 0 ] && [ "$O_YES" != 1 ]; then hi_err "refusing to run as root (use --yes if you really mean it)"; exit 3; fi
  if [ "$O_NONINT" != 1 ]; then
    hi_open_tty || { hi_err "no terminal to ask questions on; re-run with --non-interactive (and flags)"; exit 2; }
  fi
  [ -n "$O_AGENT" ] || { [ "$O_NONINT" = 1 ] && O_AGENT=none; }
  trap 'hi_on_signal INT' INT; trap 'hi_on_signal TERM' TERM

  # preflight: git repository
  if ! hi_gx -C "$O_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local ans=n
    if [ "$O_GIT_INIT" != 1 ] && [ "$O_NONINT" != 1 ]; then hi_ask ans "$O_ROOT is not a git repository. Run git init here? (y/n)" n hi_yn || exit 2; fi
    if [ "$O_GIT_INIT" = 1 ] || hi_is_yes "$ans"; then
      [ "$O_DRY" = 1 ] && { hi_say "dry run: would run git init"; } || { HI_GX_INIT_OK=1; hi_user_umask hi_gx -C "$O_ROOT" init -q || exit 3; hi_say "git init done"; }
    else
      hi_err "$O_ROOT is not a git repository (use --git-init to create one)"; exit 3
    fi
  fi
  local top sup; top="$(hi_gx -C "$O_ROOT" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$top" ] && O_ROOT="$(cd -P -- "$top" && pwd)"
  sup="$(hi_gx -C "$O_ROOT" rev-parse --show-superproject-working-tree 2>/dev/null)"
  if [ -n "$sup" ]; then
    if hi_was_set --project-root; then hi_warn "$O_ROOT is itself a submodule of $sup; installing into the submodule as requested (--project-root)"
    else hi_err "$O_ROOT is a submodule of $sup; run the installer in the superproject, or pass --project-root to install into this submodule on purpose"; exit 3; fi
  fi
  if [ "$O_NONINT" != 1 ]; then hi_interactive_questions || exit 2; fi
  [ -n "$O_AGENT" ] || O_AGENT=none
  local avail; avail="$(df -Pk -- "$O_ROOT" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  if [ -n "$avail" ] && [ "$avail" -lt 1048576 ]; then hi_err "less than 1 GiB free on the project filesystem"; exit 3; fi
  hi_agent_preflight || exit 3
  hi_check_agent_limits || exit 2
  hi_check_unrestricted_consent || exit 3

  S_LAYOUT="$(hi_layout "$O_ROOT")"; S_SUBREL="$HI_SUB"
  case "$S_LAYOUT" in
    none|partial) S_MODE=add ;;
    standard|both) S_MODE=update ;;
    legacy) S_MODE=legacy; S_SUBREL="$HI_LEGACY" ;;
    inconsistent) hi_err "$HI_SUB is a committed gitlink but is not registered in .gitmodules; fix .gitmodules (or remove the gitlink) and re-run; nothing was changed"; exit 3 ;;
  esac
  [ "$S_LAYOUT" = both ] && hi_warn "both ./constitution and submodules/constitution exist; updating submodules/constitution only"
  if [ "$S_MODE" = add ]; then
    hi_add_preflight || exit 3
    hi_probe_upstream || { hi_err "no upstream reachable (network down?); nothing was changed"; exit 3; }
    hi_resolve_ref || exit 3
  else
    S_URL="$(hi_gx -C "$O_ROOT" config -f "$O_ROOT/.gitmodules" --get "submodule.$S_SUBREL.url" 2>/dev/null)"; S_KEY="existing"
    S_REF="${O_REF:-newest helixconstitution-v* tag}"
  fi
  [ "$S_MODE" = legacy ] || { hi_docs_preflight || exit 3; }
  hi_status_paths; S_PRESTATUS=(${S_TMP_PATHS[@]+"${S_TMP_PATHS[@]}"})

  if [ "$O_NONINT" != 1 ] && [ "$O_DRY" != 1 ]; then
    local d; hi_ask d "Do a dry run first (print the plan, change nothing)? (y/n)" y hi_yn || exit 2
    if hi_is_yes "$d"; then
      hi_print_plan | hi_text_filter >&7
      local go; hi_ask go "Apply this plan now? (y/n)" n hi_yn || exit 2
      hi_is_yes "$go" || { hi_say "nothing changed (plan not applied)"; exit 0; }
    fi
  fi
  if [ "$O_DRY" = 1 ]; then
    hi_report_leftover_staging   # read-only: a dry run reports a leftover clone too
    hi_print_plan | hi_text_filter
    S_STATUS="dry-run"; S_RC=0; [ -n "$O_REPORT" ] && hi_write_report
    exit 0
  fi

  hi_lock || exit 3
  hi_report_leftover_staging
  local rc=0
  case "$S_MODE" in
    add) hi_do_add; rc=$? ;;
    update) { [ "$S_SUBREL" != "$HI_SUB" ] || hi_complete_interrupted_add; } && hi_do_update "$S_SUBREL"; rc=$? ;;
    legacy)
      hi_say "legacy layout: the constitution is at ./constitution (the standard is submodules/constitution)."
      hi_say "it is NOT moved automatically. Manual migration (backup first; review before committing):"
      printf '  git mv constitution submodules/constitution\n  git submodule sync -- submodules/constitution\n  (then change @constitution/... pointers in CLAUDE.md/AGENTS.md/GEMINI.md/QWEN.md to @submodules/constitution/...)\n  git commit -m "chore: move constitution to submodules/constitution"\n' >&2
      S_NOTES+=("legacy layout: manual migration required (or run with --agent to let the setup prompt migrate with backups)") ;;
  esac
  if [ "$rc" != 0 ]; then
    [ "$rc" = 3 ] && { hi_finish blocked 3; exit 3; }
    hi_finish failure 1; exit 1
  fi
  if [ "$S_MODE" != legacy ]; then
    hi_write_docs || { hi_finish failure 1; exit 1; }
  fi
  local strict=1 setup_rc=0
  if [ "$O_SETUP" = on ] && [ "$S_MODE" = add ]; then
    strict=0
    local f; for f in .mcp.json .claude/settings.json; do [ -e "$O_ROOT/$f" ] && hi_backup_file "$f"; done
    hi_manifest_step || { hi_finish failure 1; exit 1; }
    if [ -f "$O_ROOT/$HI_SUB/scripts/setup.sh" ]; then
      hi_say "running $HI_SUB/scripts/setup.sh"
      (cd "$O_ROOT" && umask "$HI_UMASK0" && hi_scrub_git_env && CONSTITUTION_JEV_HOOK="$([ "$O_DECISION" = off ] && echo off || echo on)" PROJECT_ROOT="$O_ROOT" \
        CONST_DIR="$O_ROOT/$HI_SUB" bash "$HI_SUB/scripts/setup.sh") >&2; setup_rc=$?
      if [ "$setup_rc" != 0 ]; then
        if [ "$S_MANIFEST" = needs-completion ]; then hi_err "setup.sh stopped (exit $setup_rc) because helix-deps.yaml needs completion: follow the next steps above, then run setup.sh again"
        else hi_err "setup.sh failed (exit $setup_rc)"; fi
      fi
    else
      hi_warn "this constitution version has no scripts/setup.sh; skipped"
    fi
  fi
  if [ "$O_DECISION" != off ]; then
    strict=0
    if [ -f "$O_ROOT/$S_SUBREL/scripts/jev/bootstrap.sh" ]; then
      local -a jb=(--non-interactive); [ "$O_DECISION" = enforce ] && jb+=(--enforce)
      (cd "$O_ROOT" && umask "$HI_UMASK0" && hi_scrub_git_env && bash "$S_SUBREL/scripts/jev/bootstrap.sh" "${jb[@]}") >&2 || hi_warn "Jev bootstrap reported a problem (decision layer stays off/deferred)"
    else
      hi_warn "this constitution version has no scripts/jev/bootstrap.sh"
    fi
  fi
  local arc=0
  if [ "$O_AGENT" != none ]; then
    strict=0
    local g; for g in CLAUDE.md AGENTS.md GEMINI.md QWEN.md Constitution.md .gitmodules .mcp.json .claude/settings.json; do
      [ -e "$O_ROOT/$g" ] && hi_backup_file "$g"; done
    local pm0; pm0="$(hi_push_marks)"
    hi_agent_step; arc=$?
    if hi_push_changed "$pm0" "$(hi_push_marks)"; then
      S_PUSHED=1
      hi_err "a push happened during the agent run (new 'update by push' reflog entries on remote-tracking refs); the installer never pushes and does not accept a run that did"
    fi
  fi
  local vrc=0
  if [ "$S_MODE" = legacy ] && [ "$O_AGENT" = none ]; then
    S_VERIFY_OVERALL=skip
  else
    hi_verify "$strict" || vrc=5
  fi
  if [ "$S_PUSHED" = 1 ]; then hi_check no_push_during_agent fail; S_VERIFY_OVERALL=fail; vrc=5; fi
  if [ "$arc" = 0 ] && [ "$vrc" = 0 ] && [ "$setup_rc" = 0 ] && [ "$O_COMMIT" = on ] && [ "$S_MODE" != legacy ]; then
    local -a cpaths=(.gitmodules "$HI_SUB"); local w
    for w in ${S_WRITTEN[@]+"${S_WRITTEN[@]}"}; do [ "$w:$S_MANIFEST" = helix-deps.yaml:needs-completion ] || cpaths+=("$w"); done
    if [ -n "$(hi_git --no-optional-locks status --porcelain -- "${cpaths[@]}")" ]; then
      HI_GX_COMMIT_OK=1   # the only place that enables git commit (CM-INSTALLER-NO-PUSH-NO-FORCE)
      hi_git commit -q -m "chore(constitution): add/update Helix Constitution at $HI_SUB ($S_REF ${S_AFTER:0:12})" -- "${cpaths[@]}" \
        && hi_say "committed locally (not pushed)" || { hi_err "commit failed"; hi_finish failure 1; exit 1; }
    fi
  fi
  if [ "$O_COMMIT" = on ] && [ "$S_MODE" != legacy ] && { [ "$arc" != 0 ] || [ "$vrc" != 0 ] || [ "$setup_rc" != 0 ]; }; then
    hi_warn "--commit on: nothing was committed because an earlier step failed (agent exit $arc, verify $([ "$vrc" = 0 ] && echo pass || echo fail), setup.sh exit $setup_rc)"
  fi
  if [ "$S_MODE" = update ] && [ "$S_BEFORE" = "$S_AFTER" ] && [ "${#S_WRITTEN[@]}" -eq 0 ] && [ "$vrc" = 0 ] && [ "$arc" = 0 ] && [ "${S_GL_CHANGED:-0}" = 0 ]; then
    hi_say "already up to date: nothing to do (no-op)"
  fi
  [ "$S_PUSHED" = 1 ] && { hi_finish failure 5; exit 5; }
  [ "$arc" = 4 ] && { hi_finish failure 4; exit 4; }
  [ "$arc" = 3 ] && { hi_finish blocked 3; exit 3; }
  [ "$arc" = 1 ] && { hi_finish failure 1; exit 1; }
  [ "$vrc" = 5 ] && { hi_finish failure 5; exit 5; }
  if [ "$setup_rc" != 0 ]; then
    [ "$S_MANIFEST" = needs-completion ] && { hi_finish manifest-needs-completion 1; exit 1; }
    hi_finish failure 1; exit 1
  fi
  if [ "$arc" = 6 ]; then
    hi_finish unverified 6
    hi_say "the constitution step is done; the agent step is UNVERIFIED (exit 6). The installer never pushes."
    exit 6
  fi
  hi_finish success 0
  hi_say "done. The installer never pushes; review 'git status' and push yourself when ready."
  exit 0
}

main "$@" __helix_installer_eof__
