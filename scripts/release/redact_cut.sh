#!/usr/bin/env bash
# scripts/release/redact_cut.sh — the output controls of the release scripts for text that comes from an
# external command or from the caller (CON-234 class, §11.4.10; round 5 structural redesign, threat model:
# docs/qa/con227_234_2026_11_11/round5/threat_model.md).
#
# Sourced, never executed (round 6: `. "$(cd "$_rc_d" && pwd)/redact_cut.sh"`, the directory taken with a
# parameter expansion so no external command runs before rc_env_lockdown). Seven public functions, the four
# below, rc_env_lockdown and rc_url_has_userinfo (round 6, K3 and K1) and rc_env_clean (round 7, L1 and L2:
# the script re-executes itself with an empty environment and rebuilds it from an allow-list, so every child
# gets an environment built positively); each has its own comment above it. Channel census:
# docs/qa/con227_234_2026_11_11/round6/threat_model.md, round7/threat_model.md and tests/release/channels.tsv.
#
#   rc_err_class            stdin -> stdout. The PRIMARY control for network commands (git fetch, git push,
#                           curl): their stderr is never printed; this function turns it into ONE word of a
#                           closed set (no-message, url-invalid, tls-error, auth-failed, ref-error,
#                           repository-not-found, rejected-non-fast-forward, remote-rejected, rejected,
#                           network-unreachable, unknown). The awk program prints string literals only, so
#                           no byte of the input can reach the output, whatever the input holds. The word is
#                           a hint chosen by fixed phrases; a password that happens to hold such a phrase
#                           can make it wrong, never make it leak. ("timeout" is the eleventh word; the
#                           callers derive it from the exit status of timeout(1), not from text.)
#   rc_safe_url URL         prints "scheme://host[:port]" when URL starts with exactly that shape
#                           (scheme http, https, ssh or git; host of [A-Za-z0-9.-] or an IPv6 literal; no
#                           userinfo), else the literal "<url not shown>". Never prints a path or a query.
#   rc_git_env              unsets every GIT_TRACE* variable and GIT_CURL_VERBOSE of the caller, then
#                           exports GIT_TRACE_REDACT=1, GIT_TERMINAL_PROMPT=0 and GIT_TRACE2=0,
#                           GIT_TRACE2_EVENT=0, GIT_TRACE2_PERF=0 (git writes no trace anywhere, never
#                           prompts on a terminal, and redacts if a trace is turned on by a config file).
#   rc_redact_cut N [mark]  stdin -> stdout. DEFENCE IN DEPTH for text that is printed: the stderr of LOCAL
#                           commands flushed at exit (git show, sqlite3, jq), and the publisher's own
#                           message lines. Every line is redacted (rules below), THEN at most N bytes of the
#                           redacted text are printed. With "mark", a cut output ends with the line
#                           "(truncated: K more bytes not shown)". N must be a decimal number.
#
# rc_redact_cut rules, applied to each line in this order; every rule scans the WHOLE line (round 5, J2:
# there is no scan window, so a replacement can never move unscanned bytes into the printed region). A line
# longer than 16384 bytes is not printed at all: it is replaced by "(a line of K bytes is not shown: longer
# than 16384 bytes)". The URL rules run before the header rule (round 5, J1: the header rule drops the rest of
# the line, and it must never remove the "@" that the URL rules use to find the end of a userinfo):
#   R3 URL userinfo: from the FIRST "://" of the line to the LAST "@" of the line -> "://<redacted>@"
#      (over-redaction of a later path "@" or of a second URL's host is accepted: detail lost, never a secret);
#   R4 scheme-less userinfo: a word (no "://", delimited by blanks, quotes, <, >, parentheses) that holds a
#      ":" before its last "@" -> "<redacted>@host...";
#   R1 header: a field name ending in authorization, token, secret, password, passwd, api-key, apikey,
#      api_key, cookie or credential, followed by ":" -> everything after the ":" is <redacted>;
#   R2 "Bearer" + blanks or TABs + a word -> "Bearer <redacted>";
#   R5 parameters: NAME=VALUE where NAME ends in token, secret, password, passwd, pwd, pass, key, sig,
#      signature, auth, credential, session or jwt (any case) -> NAME=<redacted>; VALUE ends at & # ;
#      blank, quote, < or >;
#      round 6 (N1): blanks around "=" ("PASSWORD = x"), the percent-encoded "NAME%3Dvalue", and the JSON pair
#      "NAME" : "value" are covered too. These shapes are reachable only through the defence-in-depth paths:
#      the stderr of network commands is never printed at all (rc_err_class), so it never reaches this helper;
#   R6 token shapes: gh[pousr]_..., github_pat_..., glpat-... (20+ characters) -> <redacted>.
# The helper sets LC_ALL=C itself (bytes, whatever the caller's locale) and drops NUL bytes. Honest limits of
# rc_redact_cut (they matter only for the defence-in-depth paths): a parameter VALUE holding a raw blank or
# one of the end characters above prints its tail after that character; a scheme-less userinfo holding a raw
# blank is split into words; a credential split over two lines is not seen; a secret printed in none of the
# shapes above (a bare word) is not recognised.
rc_err_class() {
  LC_ALL=C tr -d '\000' | LC_ALL=C awk '
    { t = t " " tolower($0) }
    END {
      if (t ~ /^[ \t\r]*$/) { print "no-message"; exit }
      if (t ~ /url rejected|malformed|port number|unsupported protocol|bad\/illegal format|url using bad/) { print "url-invalid"; exit }
      if (t ~ /ssl|certificate|tls/) { print "tls-error"; exit }
      if (t ~ /authentication failed|could not read username|could not read password|permission denied|invalid username or password|access denied|returned error: 40[13]|terminal prompts disabled|unauthorized|forbidden/) { print "auth-failed"; exit }
      if (t ~ /find remote ref|invalid refspec|src refspec|does not match any|unknown revision/) { print "ref-error"; exit }
      if (t ~ /repository not found|does not appear to be a git repository|returned error: 404|not found|no such file or directory/) { print "repository-not-found"; exit }
      if (t ~ /non-fast-forward|fetch first|stale info/) { print "rejected-non-fast-forward"; exit }
      if (t ~ /remote rejected|hook declined|pre-receive|protected branch|denied/) { print "remote-rejected"; exit }
      if (t ~ /rejected/) { print "rejected"; exit }
      if (t ~ /resolve|connection refused|failed to connect|could not connect|timed out|unreachable|no route to host|connection reset|empty reply|transfer closed|recv failure|send failure|too slow|early eof|hung up/) { print "network-unreachable"; exit }
      print "unknown"
    }'
}

rc_safe_url() {
  local LC_ALL=C re='^(https?|ssh|git)://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?(/|$)'
  if [[ ${1:-} =~ $re ]]; then printf '%s://%s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  else printf '<url not shown>'; fi
}

# rc_gitea_token_shape_ok VALUE: 0 when VALUE fits the gitea publisher's token charset and length, else 1. The ONE
# definition of that shape (CON-423 review r1, M8): release_publish_gitea.sh refuses a token outside it and the
# tag script's dry run reports TOKEN-SHAPE for it, so the two can never disagree. Nothing is printed.
rc_gitea_token_shape_ok() { local LC_ALL=C; [[ ${1:-} =~ ^[A-Za-z0-9._~+/=-]{8,200}$ ]]; }

rc_git_env() {
  local v
  for v in $(compgen -e); do case "$v" in GIT_TRACE*|GIT_CURL_VERBOSE) unset -v "$v" ;; esac; done
  export GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0 GIT_TRACE2=0 GIT_TRACE2_EVENT=0 GIT_TRACE2_PERF=0
}

# rc_env_lockdown (round 6, K3): the environment every child process of the calling script receives is an
# allow-list. Every exported variable whose name is not on the list below is un-exported (export -n): the
# calling shell keeps its value (the publisher still reads the token variable it is told to read), but no
# child (timeout, git, git-remote-https, curl, gh, glab, jq, sqlite3, coreutils) receives it. A caller's
# M3W_GITEA_TOKEN, GH_TOKEN, GITLAB_TOKEN, any *_TOKEN, a proxy URL with a password, GIT_CONFIG_COUNT /
# GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n / GIT_CONFIG_PARAMETERS (they can carry http.extraHeader), BASH_ENV
# and SHELLOPTS are therefore never passed on. The list holds names of paths, sockets and locale settings
# only, each named exactly (round 8, N1: the thirteen locale categories one by one, never the prefix LC_*: a
# prefix passed any caller variable named LC_<anything>, and ssh sends LC_* to the remote server), and each
# value must have the shape its name is meant to hold (_rc_env_shape_ok below); an allow-listed variable whose
# value does not is un-exported like any other. RELEASE_ENV_KEEP="NAME ..." adds names (meant for the tests, for the
# state files of their doubles; nothing can tell a test from a caller, so it is bounded instead, round 9, F7): a name
# that looks like a credential (TOK (also TOKEN, and the publisher's _rpg_tok), SECRET, PASS, PWD, KEY, CRED, AUTH,
# COOKIE, SESSION, JWT, PROXY, any case), a name of a channel git, ssh, curl, gh or glab reads (GIT_*, which holds
# GIT_CONFIG_PARAMETERS and GIT_CONFIG_COUNT/KEY_n/VALUE_n; SSH_*, CURL_*, GH_*, GLAB_*, GITLAB_*, LD_*, *_URL, *_URI),
# a name of the SendEnv line of the default ssh_config (round 10: LANG*, LC_*, COLORTERM and NO_COLOR, as a class by
# name; round 11: defence in depth only, because no RELEASE_ENV_KEEP name reaches a network child at all, see rc_net),
# a name bash gives a meaning of its own (_rc_env_reserved), or a name that is not a plain identifier is refused there
# and stays un-exported (round 10, N2: the words of RELEASE_ENV_KEEP are never glob-expanded); the value of a name it adds gets the common checks of _rc_env_common_ok (no URL user
# information, no token shape, no control character, at most 4096 bytes), else it is un-exported too. So
# GIT_CONFIG_PARAMETERS is never passed on, also not through RELEASE_ENV_KEEP. gh and glab therefore use their own
# stored login (gh auth login, glab auth login), never a token variable of the caller.
# Round 11 (R10-1 of the round-10 review, the structural replacement of the round-10 SendEnv reader): the environment
# built here is the environment of the LOCAL children only (awk, jq, sqlite3, coreutils, the gitea publisher script).
# A network child (git, ssh, curl, gh, glab, timeout running one of them, the badge computer) is started through
# rc_net, whose environment is built from a second, smaller allow-list and never holds a RELEASE_ENV_KEEP name, a
# locale value of the caller or any other name outside that list (see rc_net). The credential words above are
# therefore no longer the protection of the off-host channel; they stay as a filter of the local children.
# _rc_env_shape_ok NAME VALUE (round 8, N1): status 0 when VALUE has the shape the allow-listed NAME is meant to
# hold, else 1 (rc_env_lockdown then un-exports it). Every value (_rc_env_common_ok, round 9: also the values of the
# RELEASE_ENV_KEEP names): at most 4096 bytes, no control character (a newline included), no URL user information
# ("://" and a later "@"), no token shape (gh?_ with ? one of p o u s r, github_pat_, glpat-).
# Then by class: locale (LANG and the thirteen LC_ names; ssh sends LANG and LC_* off-host) a locale name of
# _rc_env_locale_ok (round 10, F8), up to 64 bytes; LANGUAGE a ":"-separated list of such names, up to 256; TZ, TERM, USER, LOGNAME, GIT_SSH_VARIANT,
# GIT_CONFIG_NOSYSTEM their own small character sets; GH_HOST and GITLAB_HOST a host name with an optional
# http(s):// and port and no user information; DBUS_SESSION_BUS_ADDRESS the D-Bus address characters;
# SSH_AUTH_SOCK an absolute path to an existing socket; the directory and file names an absolute path or empty;
# GIT_SSH, GIT_ASKPASS, SSH_ASKPASS an absolute path or a plain program name. PATH and GIT_SSH_COMMAND get the
# common checks only (a command line the caller chose; honest limit: a password written in it by the caller is not
# recognised). A bare word that is a secret cannot be told from a locale or path value: the protection against it
# is the exact list of names (no caller credential variable has one of these names). Builtins only.
_rc_env_common_ok() { # VALUE: status 0 when VALUE passes the checks every passed-on value gets (see above)
  local LC_ALL=C x="$1"
  [ "${#x}" -le 4096 ] || return 1
  case "$x" in *[[:cntrl:]]*) return 1 ;; *://*@*) return 1 ;; esac
  [[ ${x,,} =~ gh[pousr]_[a-z0-9]{20}|github_pat_[a-z0-9_]{20}|glpat-[a-z0-9_-]{20} ]] && return 1
  return 0
}
# _rc_env_locale_ok VALUE (round 10, F8 of the round-8 review; round 11, N-1 and R10-2 R13 of the round-10 review):
# status 0 when VALUE is empty or a locale name: C or POSIX, or a language of 2 or 3 lower-case letters with an optional
# _TERRITORY (2 upper-case letters or 3 digits), then an optional .codeset from a CLOSED set (the glibc codeset names,
# any case: UTF-8, utf8, ISO-8859-N, KOI8-R, EUC-JP, GB18030, BIG5, CP125N, ASCII, ANSI_X3.4-1968 ...) and an optional
# @modifier from a CLOSED set (euro, latin, cyrillic, devanagari, valencia ...). Round 10 admitted any 32-character
# codeset and modifier, so "en.<32 hex>@<8 hex>" (40 hex characters) was kept (N-1). These values reach the local
# children only (rc_net gives a network child LC_ALL=C and no other locale variable); a name of an unknown codeset or
# modifier is dropped, which only means the local child runs in the C locale. The longest name the grammar admits is 37
# bytes, so the 64-byte cap of _rc_env_shape_ok never decides alone (round-10 review mutant R20: equivalent, see
# docs/qa/con227_234_2026_11_11/round11/mutants.md). Honest limit: a secret that happens to be a locale name is kept.
_RC_LOCALE_CODESET='utf-?8|iso[-_]?8859-?(1[0-6]|[1-9])|koi8-[ru]|euc-?(jp|kr|tw|cn)|gb(18030|2312|k)|big5(-hkscs)?|cp125[0-8]|tis-?620|armscii-8|georgian-ps|pt154|tcvn5712-1|(us-)?ascii|ansi_x3[.]4-1968|s(hift_)?jis'
_RC_LOCALE_MOD='euro|latin|cyrillic|devanagari|iqtelif|saaho|valencia|abegede|hebrew|ijekavian|ijekavianlatin|shaw|quot|boldquot'
_rc_env_locale_ok() {
  local LC_ALL=C x="$1" cs="" md="" re='^(C|POSIX|[a-z]{2,3}(_([A-Z]{2}|[0-9]{3}))?)$'
  [ -n "$x" ] || return 0
  case "$x" in *@*) md="${x#*@}"; x="${x%%@*}" ;; esac
  case "$x" in *.*) cs="${x#*.}"; x="${x%%.*}" ;; esac
  [[ $x =~ $re ]] || return 1
  [ -z "$cs" ] && [[ $1 != *.* ]] || [[ ${cs,,} =~ ^($_RC_LOCALE_CODESET)$ ]] || return 1
  [ -z "$md" ] && [[ $1 != *@* ]] || [[ $md =~ ^($_RC_LOCALE_MOD)$ ]] || return 1
  return 0
}
_rc_env_shape_ok() {
  local LC_ALL=C n="$1" x="$2" re
  _rc_env_common_ok "$x" || return 1
  case "$n" in
    LANG|LC_ALL|LC_CTYPE|LC_COLLATE|LC_MESSAGES|LC_MONETARY|LC_NUMERIC|LC_TIME|LC_PAPER|LC_NAME|LC_ADDRESS|LC_TELEPHONE|LC_MEASUREMENT|LC_IDENTIFICATION)
      [ "${#x}" -le 64 ] && _rc_env_locale_ok "$x" ;;
    LANGUAGE) [ "${#x}" -le 256 ] || return 1   # round 10 (F8): a ":"-separated list, every element a locale name
      local rest="$x" e
      while [ -n "$rest" ]; do e="${rest%%:*}"; _rc_env_locale_ok "$e" || return 1
        case "$rest" in *:*) rest="${rest#*:}" ;; *) rest="" ;; esac; done ;;
    TZ) re='^:?[A-Za-z0-9/_.,:+<>-]{0,128}$'; [[ $x =~ $re ]] ;;
    TERM) [[ $x =~ ^[A-Za-z0-9._+-]{0,64}$ ]] ;;
    USER|LOGNAME) [[ $x =~ ^[A-Za-z0-9._@-]{0,64}$ ]] ;;
    GIT_SSH_VARIANT) [[ $x =~ ^(|auto|ssh|plink|putty|tortoiseplink|simple)$ ]] ;;
    GIT_CONFIG_NOSYSTEM) [[ $x =~ ^[A-Za-z0-9]{0,8}$ ]] ;;
    GH_HOST|GITLAB_HOST) [[ $x =~ ^((https?://)?[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?/?)?$ ]] ;;
    DBUS_SESSION_BUS_ADDRESS) re='^[A-Za-z0-9/_.,=:;%-]{0,512}$'; [[ $x =~ $re ]] ;;
    SSH_AUTH_SOCK) [ -z "$x" ] || { [[ $x == /* ]] && [ -S "$x" ]; } ;;
    HOME|PWD|SHELL|TMPDIR|XDG_CONFIG_HOME|XDG_CACHE_HOME|XDG_DATA_HOME|XDG_STATE_HOME|XDG_RUNTIME_DIR|GNUPGHOME|GH_CONFIG_DIR|GLAB_CONFIG_DIR|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM)
      [ -z "$x" ] || [[ $x == /* ]] ;;
    GIT_SSH|GIT_ASKPASS|SSH_ASKPASS) [ -z "$x" ] || [[ $x == /* ]] || [[ $x =~ ^[A-Za-z0-9._+-]{1,64}$ ]] ;;
    PATH|GIT_SSH_COMMAND) return 0 ;;
    *) return 1 ;;   # a name of the list without a class here: never passed on (fail closed)
  esac
}
# rc_net CMD [ARG...] (round 11, R10-1 of the round-10 review: the structural replacement of the round-10 SendEnv
# reader): runs CMD, the one way the release scripts start a NETWORK child (git, which can run ssh or a remote helper;
# ssh; curl; gh; glab; timeout(1) running one of them; the badge computer, which runs git). CMD runs in a forked
# subshell whose exported environment is built from _RC_NET_KEEP, a fixed allow-list, and nothing else:
#   every exported variable whose name is not on _RC_NET_KEEP, or whose value does not have the shape of its name
#   (_rc_env_shape_ok), is un-exported; then the constants LC_ALL=C, GIT_TRACE_REDACT=1, GIT_TERMINAL_PROMPT=0,
#   GIT_TRACE2=0, GIT_TRACE2_EVENT=0 and GIT_TRACE2_PERF=0 are exported; then the exported names are listed once more
#   and CMD is not run (status 125) when any name outside the list and the constants is still exported.
# So no RELEASE_ENV_KEEP name, no locale value of the caller (LANG, LANGUAGE, LC_*: the default ssh_config sends LANG
# and LC_*), no TERM, USER, LOGNAME, SHELL, PWD, OLDPWD or SHLVL reaches a network child, whatever an ssh or git
# configuration says: ssh's SendEnv and SetEnv can only send a variable the child HAS, and the child has only the names
# of the list (PATH, HOME, TMPDIR and the other path, socket and host names below, each shape-checked) and the
# constants. Nothing in this function reads an ssh or git configuration file, so nothing here can fail open on a file
# it cannot parse (the round-10 reader re-parsed ssh_config, git config and GIT_SSH_COMMAND in bash and treated what it
# could not parse as absent; its code, _rc_env_sendenv, _rc_env_sendenv_read and _rc_env_pwhome, is removed: see
# docs/qa/con227_234_2026_11_11/round11/threat_model.md, section 4).
# Precondition: the calling process was re-executed by rc_env_clean (argv[0] the marker and an empty start
# environment, _rc_env_state "clean"), so every environment entry is a shell variable bash can un-export; otherwise
# CMD is not run (status 125). Honest limits: a value on the list reaches the network child as it is (HOME, PATH,
# GIT_SSH_COMMAND and the others are paths, sockets, host names and a command line the caller chose; under a client
# "SendEnv *" ssh sends them, and a password written by the caller inside GIT_SSH_COMMAND is not recognised); bash adds
# nothing of its own (measured: no "_" entry, see the K11 cases of tests/release/test_redact_cut.sh). Builtins only.
_RC_NET_KEEP=" PATH HOME TMPDIR SSH_AUTH_SOCK GIT_SSH GIT_SSH_COMMAND GIT_SSH_VARIANT GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GNUPGHOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS GH_CONFIG_DIR GH_HOST GLAB_CONFIG_DIR GITLAB_HOST "
_RC_NET_CONST=" LC_ALL GIT_TRACE_REDACT GIT_TERMINAL_PROMPT GIT_TRACE2 GIT_TRACE2_EVENT GIT_TRACE2_PERF "
rc_net() {
  [ "$#" -ge 1 ] || return 125
  _rc_env_state "/proc/$$"
  [ "$_RC_ENV_STATE" = clean ] || { printf 'rc_net: refused: the environment was not rebuilt by rc_env_clean\n' >&2; return 125; }
  (
    # the word splitting of the name lists below must not depend on the caller's IFS (an IFS holding "_" would split
    # GIT_SSH into GIT and SSH and leave the real name exported) nor on globbing; a function named like a builtin
    # must not replace it: every builtin of this subshell is called through "builtin"
    IFS=$' \t\n'; set -f
    for _rc_v in $(builtin compgen -e); do
      case "$_RC_NET_KEEP" in *" $_rc_v "*) _rc_env_shape_ok "$_rc_v" "${!_rc_v}" && continue ;; esac
      # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $_rc_v is un-exported
      builtin export -n "$_rc_v" 2>/dev/null
    done
    builtin export LC_ALL=C GIT_TRACE_REDACT=1 GIT_TERMINAL_PROMPT=0 GIT_TRACE2=0 GIT_TRACE2_EVENT=0 GIT_TRACE2_PERF=0
    # the second census is the check, not a repetition: it is what refuses when an un-export above did not take
    # effect (the K11 case "export disabled" makes it so: enable -n export)
    for _rc_v in $(builtin compgen -e); do
      case "$_RC_NET_KEEP$_RC_NET_CONST" in *" $_rc_v "*) ;; *) builtin printf 'rc_net: refused: a variable outside the network allow-list is still exported\n' >&2; builtin exit 125 ;; esac
    done
    # shellcheck disable=SC2163   # indirect on purpose: the function NAMED by $_rc_v is un-exported
    for _rc_v in $(builtin compgen -A function); do builtin export -n -f "$_rc_v" 2>/dev/null; done
    builtin exec "$@"
  )
}
rc_env_lockdown() {
  local -   # round 10 (N2): the RELEASE_ENV_KEEP words are never glob-expanded (set -f below, restored on return)
  local v keep=" PATH HOME USER LOGNAME SHELL PWD LANG LANGUAGE LC_ALL LC_CTYPE LC_COLLATE LC_MESSAGES LC_MONETARY LC_NUMERIC LC_TIME LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION TZ TMPDIR TERM XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK GIT_SSH GIT_SSH_COMMAND GIT_SSH_VARIANT GIT_ASKPASS SSH_ASKPASS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GNUPGHOME GH_CONFIG_DIR GH_HOST GLAB_CONFIG_DIR GITLAB_HOST " extra=""
  set -f
  for v in ${RELEASE_ENV_KEEP:-}; do
    [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || continue
    [[ ${v^^} =~ TOK|SECRET|PASS|PWD|KEY|CRED|AUTH|COOKIE|SESSION|JWT|PROXY ]] && continue
    case "${v^^}" in GIT_*|SSH_*|CURL_*|GH_*|GLAB_*|GITLAB_*|LD_*|*_URL|*_URI) continue ;; esac   # round 9 (F7): a channel of git, ssh, curl, gh, glab or the loader
    case "${v^^}" in LANG*|LC_*|COLORTERM|NO_COLOR) continue ;; esac   # round 10 (R9-1): the SendEnv names of the default ssh_config (round 11: defence in depth only; rc_net gives no RELEASE_ENV_KEEP name to a network child)
    _rc_env_reserved "$v" && continue
    extra="$extra $v"
  done
  set +f
  # RELEASE_ENV_KEEP names (meant for the tests) are not in the base list; their values get the common checks (round 9, F7)
  for v in $(compgen -e); do
    # shellcheck disable=SC2163   # indirect on purpose: the variable NAMED by $v is un-exported
    case "$keep" in
      *" $v "*) _rc_env_shape_ok "$v" "${!v}" || export -n "$v" 2>/dev/null ;;   # allow-listed: the value is checked too
      *) case "$extra " in *" $v "*) _rc_env_common_ok "${!v}" || export -n "$v" 2>/dev/null ;; *) export -n "$v" 2>/dev/null ;; esac ;;
    esac
  done
  # shellcheck disable=SC2163   # indirect on purpose, as above
  for v in $(compgen -A function); do export -n -f "$v" 2>/dev/null; done   # no exported function either
  return 0
}

# rc_env_clean READS "$@" (round 7, L1 and L2 of the round-6 review): the environment of every child process is
# built POSITIVELY. Each release script runs `rc_env_clean READS "$@"` as its first command after loading this file
# (no external command before it; tests/release/channel_census.py lint checks that). In the caller's process it runs
# rc_env_lockdown and then re-executes the script ONCE with an EMPTY environment (bash `exec -c`, argv[0]
# "rc-clean-env", the same script path and arguments). The values travel on file descriptor 9, a pipe written by
# shell builtins in a forked subshell (never in an argv, never in a file): every variable that is still exported
# after rc_env_lockdown (the allow-list) as an exported variable, and each name in READS and RELEASE_ENV_KEEP as a
# plain shell variable that no child receives (the publisher's token variable, RELEASE_NET_TIMEOUT). In the
# re-executed process (argv[0] "rc-clean-env" and an empty /proc/$$/environ) it reads the records, runs
# rc_env_lockdown again (the same allow-list decides a second time), closes fd 9 and returns 0. Nothing else can
# reach a child: not an environment entry whose name is not a shell identifier ("A-B=...",
# "npm_config_//host/:_authToken=..."; bash keeps those for its children and cannot un-export them), not
# SHELLOPTS or BASHOPTS (an inherited allexport or xtrace), not BASH_ENV, not an exported function; and every shell
# option of the re-executed bash is at its default (allexport and xtrace off), because no option crosses the exec.
# Round 8: in the re-executed process every inherited file descriptor above 2 except fd 9 is closed first (N3: the
# process-substitution pipe of the exec, fd 63, and any descriptor of the caller would otherwise reach every
# child; round 9, F1: whatever the number of digits, and when the descriptors cannot be listed the function refuses,
# status 3); a process that already carries the marker never re-executes again (N2: a state other than "clean"
# there means the check is broken, so the function refuses, status 4, instead of looping); and a script that was
# SOURCED by another script refuses (N4: $0 is then the sourcing script, which must never be re-executed).
# Status 2: a READS name is not a plain identifier or bash gives it a meaning of its own; 3: /proc/$$/cmdline,
# /proc/$$/environ or (round 9) the descriptor list /proc/$$/fd cannot be read (Linux /proc is required: without it the state cannot be checked, so the script
# refuses rather than run with the caller's environment); 4: the script path is not a readable file, the script
# was sourced, the process already carries the marker but is not clean, or the exec failed. The caller prints its
# own message and exits. Honest limit (N7): `bash -x` together with a caller PS4 that names a variable prints
# that variable on the trace lines the FIRST process writes before the exec (caller-controlled, the same class as
# BASH_ENV: the caller chose to trace with its own prompt); the re-executed process has xtrace off and no PS4.
_RC_ENV_MARK=rc-clean-env
_rc_env_reserved() { # NAME: status 0 when bash gives NAME a meaning of its own (never carried over)
  case "$1" in BASH*|SHELLOPTS|ENV|IFS|PS[0-4]|POSIXLY_CORRECT|CDPATH|GLOBIGNORE|EXECIGNORE|FUNCNEST|TMOUT|HISTFILE|PROMPT_COMMAND|_RC_*|_rc_*) return 0 ;; esac
  return 1
}
# _rc_env_state DIR: sets _RC_ENV_STATE to "clean" (argv[0] is the marker and the start environment is empty),
# "dirty", or "blind" (DIR/cmdline or DIR/environ cannot be read); rc_env_clean passes /proc/$$
_rc_env_state() {
  local a0="" e n=0
  _RC_ENV_STATE=blind
  { [ -r "$1/cmdline" ] && [ -r "$1/environ" ]; } || return 0
  { IFS= read -r -d '' a0 <"$1/cmdline"; } 2>/dev/null || [ -n "$a0" ] || return 0
  while IFS= read -r -d '' e || [ -n "$e" ]; do n=$((n + 1)); e=""; done <"$1/environ" 2>/dev/null || return 0
  if [ "$a0" = "$_RC_ENV_MARK" ] && [ "$n" -eq 0 ]; then _RC_ENV_STATE=clean; else _RC_ENV_STATE=dirty; fi
}
# _rc_env_dump READS: the records "e|s NUL NAME NUL VALUE NUL" (builtins only; it runs in a forked subshell)
_rc_env_dump() {
  local v
  printf 's\0RELEASE_ENV_KEEP\0%s\0' "${RELEASE_ENV_KEEP-}"
  for v in $(compgen -e); do printf 'e\0%s\0%s\0' "$v" "${!v}"; done
  for v in $1; do [ -n "${!v+x}" ] && printf 's\0%s\0%s\0' "$v" "${!v}"; done
}
# _rc_env_closefds DIR (round 8, N3; round 9, F1 of the round-8 review): close every descriptor this process can pass
# on to a child: each entry of DIR/fd (rc_env_clean passes /proc/$$), whatever its number of digits (round 8 skipped
# numbers of five or more digits, so fd 10000 reached every child), other than 0, 1, 2 and 9, unless DIR/fdinfo shows
# its close-on-exec flag. A descriptor whose flags cannot be read is closed (fail closed). bash's own descriptors (the
# script on 255, saved copies) carry the flag and stay. Status 1 when DIR/fd lists no descriptor at all (it cannot be
# read: rc_env_clean then refuses with status 3), else 0. Builtins only.
_rc_env_closefds() {
  local f n fl k v seen=0
  for f in "$1"/fd/*; do
    n="${f##*/}"
    [[ $n =~ ^[0-9]+$ ]] || continue
    seen=1
    case "$n" in 0|1|2|9) continue ;; esac
    fl=""
    { while read -r k v; do [ "$k" = flags: ] && fl="$v"; done <"$1/fdinfo/$n"; } 2>/dev/null
    if [[ $fl =~ ^[0-7]{1,11}$ ]] && (( (8#$fl) & 8#2000000 )); then continue; fi
    eval "exec $n<&-"
  done
  [ "$seen" -eq 1 ]
}
# _rc_env_restore READS: read the records from fd 9 in the re-executed process, then decide again with
# rc_env_lockdown
_rc_env_restore() {
  local k n val
  if { : <&9; } 2>/dev/null; then
    while IFS= read -r -d '' k <&9 && IFS= read -r -d '' n <&9 && IFS= read -r -d '' val <&9; do
      [[ $n =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || continue
      _rc_env_reserved "$n" && continue
      case "$k" in
        e) printf -v "$n" '%s' "$val" 2>/dev/null && export "${n?}" ;;
        s) case " $1 RELEASE_ENV_KEEP " in *" $n "*) printf -v "$n" '%s' "$val" 2>/dev/null ;; esac ;;
      esac
    done
    exec 9<&-
  fi
  rc_env_lockdown
}
rc_env_clean() {
  local reads="$1" v; shift
  for v in $reads; do
    [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]{0,63}$ ]] || return 2
    _rc_env_reserved "$v" && return 2
  done
  _rc_env_state "/proc/$$"
  case "$_RC_ENV_STATE" in
    clean) _rc_env_closefds "/proc/$$" || return 3; _rc_env_restore "$reads"; return 0 ;;
    blind) return 3 ;;
  esac
  # loop guard (N2): argv[0] read again here, independently of _rc_env_state
  local a0=""
  { IFS= read -r -d '' a0 <"/proc/$$/cmdline"; } 2>/dev/null
  [ "$a0" = "$_RC_ENV_MARK" ] && return 4
  # sourced (N4): the caller of this function must be the script bash runs ($0), at the top of the source stack
  { [ "${#BASH_SOURCE[@]}" -ge 2 ] && [ "${BASH_SOURCE[1]}" = "$0" ] && [ "${BASH_SOURCE[-1]}" = "$0" ]; } || return 4
  { [ -n "${BASH:-}" ] && [ -f "$0" ] && [ -r "$0" ]; } || return 4
  rc_env_lockdown
  shopt -s execfail
  exec -c -a "$_RC_ENV_MARK" "$BASH" "$0" "$@" 9< <(_rc_env_dump "$reads")
  return 4
}

# rc_url_has_userinfo URL (round 6, K1): status 0 when URL carries a user name or a password that git would
# place in the argv of its transport helper (git remote-https, git-remote-https: /proc/PID/cmdline is
# readable by every local user), else 1. Refused: any userinfo in an http, https, ftp or ftps URL (a user
# name there is often a token); a userinfo with a ":" (a password) in any other scheme ("ssh://u:p@h"); an
# scp-like "u:p@host:path". Allowed: "ssh://git@host/r" and "git@host:r" (a user name without a password),
# local paths. Nothing is printed.
rc_url_has_userinfo() {
  local LC_ALL=C u="${1:-}" auth scheme ui
  if [[ $u =~ ^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*) ]]; then
    scheme="${BASH_REMATCH[1],,}"; auth="${BASH_REMATCH[2]}"
    case "$auth" in *@*) ;; *) return 1 ;; esac
    ui="${auth%@*}"
    case "$scheme" in http|https|ftp|ftps) return 0 ;; esac
    case "$ui" in *:*|*%3[Aa]*) return 0 ;; esac
    return 1
  fi
  case "$u" in /*|./*|../*) return 1 ;; esac
  # scp-like or anything else: a "@" before the first "/" with a ":" (or an encoded one) before that "@"
  auth="${u%%/*}"
  case "$auth" in *@*) ui="${auth%@*}"; case "$ui" in *:*|*%3[Aa]*) return 0 ;; esac ;; esac
  return 1
}

rc_redact_cut() {
  local n="${1:?rc_redact_cut needs a byte count}" mark="${2:-}"
  case "$n" in ''|*[!0-9]*) printf 'rc_redact_cut: byte count must be a number\n' >&2; return 2 ;; esac
  LC_ALL=C tr -d '\000' | LC_ALL=C awk -v max="$n" -v mark="$mark" -v lmax=16384 '
    function put(r) {             # replace line[S..S+L-1] by r in both the text and its lower-case copy
      line = substr(line, 1, S - 1) r substr(line, S + L); low = substr(low, 1, S - 1) tolower(r) substr(low, S + L)
      lim += length(r) - L          # the scanned end moves with the text (lim is the whole line)
    }
    function each(re, kind,   pos, rest, a, b, pre, w, k, c) {   # apply rule kind at every match of re
      pos = 1
      while (pos <= lim) {
        rest = substr(low, pos, lim - pos + 1)
        if (!match(rest, re)) break
        S = pos + RSTART - 1; L = RLENGTH; w = substr(line, S, L)
        if (kind == "bearer") { put(substr(w, 1, 6) " <redacted>"); pos = S + 17; continue }
        if (kind == "param") { k = index(w, "="); S = S + k; L = L - k; put("<redacted>"); pos = S + 10; continue }
        if (kind == "param3d") { k = index(tolower(w), "%3d"); S = S + k + 2; L = L - k - 2; put("<redacted>"); pos = S + 10; continue }
        if (kind == "json") { k = index(substr(w, 2), "\""); c = substr(w, k + 2); k = k + 1 + index(c, "\"")
                              S = S + k; L = L - k - 1; put("<redacted>"); pos = S + 11; continue }
        if (kind == "shape") { put("<redacted>"); pos = S + 10; continue }
        if (kind == "word") {
          if (index(w, "://") == 0 && match(w, /@[^@]*$/)) {
            a = RSTART; pre = substr(w, 1, a - 1)
            if (index(pre, ":") > 0 && pre != "<redacted>") { L = a - 1; put("<redacted>"); pos = S + 11; continue }
          }
          pos = S + L; continue
        }
      }
    }
    {
      line = $0
      if (length(line) > lmax) {
        out = "(a line of " length(line) " bytes is not shown: longer than " lmax " bytes)\n"
      } else {
        low = tolower(line)
        # R3 URL userinfo, whole line: first "://" to last "@" (before any rule that can drop text)
        if ((i = index(low, "://")) > 0 && match(substr(low, i + 3), /@[^@]*$/)) {
          line = substr(line, 1, i + 2) "<redacted>" substr(line, i + 2 + RSTART); low = tolower(line)
        }
        lim = length(line)   # R4 scans the whole line
        each("[^ \t\"'\''<>()]+", "word")
        # R1 header lines: the rest of the line after the field name is dropped
        if (match(low, /(^|[^a-z0-9_-])[a-z0-9_-]*(authorization|token|secret|password|passwd|api-key|apikey|api_key|cookie|credential)[ \t]*:/)) {
          line = substr(line, 1, RSTART + RLENGTH - 1) " <redacted>"; low = tolower(line)
        }
        lim = length(line)   # R2, R5 and R6 scan the whole line
        each("bearer[ \t]+[^ \t\"'\''<>]+", "bearer")
        each("[a-z0-9_.-]*(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)[ \t]*=[ \t]*[^&#; \t\"'\''<>]*", "param")
        each("[a-z0-9_.-]*(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)%3d[^&#; \t\"'\''<>]*", "param3d")
        each("\"[a-z0-9_.-]*(token|secret|password|passwd|pwd|pass|key|sig|signature|auth|credential|session|jwt)\"[ \t]*:[ \t]*\"[^\"]*\"", "json")
        each("(gh[pousr]_[a-z0-9]{20,}|github_pat_[a-z0-9_]{20,}|glpat-[a-z0-9_-]{20,})", "shape")
        out = line "\n"
      }
      if (used >= max) { dropped += length(out); next }
      if (used + length(out) <= max) { printf "%s", out; used += length(out); next }
      printf "%s", substr(out, 1, max - used); dropped += length(out) - (max - used); used = max
    }
    END { if (dropped > 0 && mark != "") printf "\n(truncated: %d more bytes not shown)\n", dropped }'
}
