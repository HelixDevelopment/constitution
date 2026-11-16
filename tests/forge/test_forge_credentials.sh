#!/usr/bin/env bash
# tests/forge/test_forge_credentials.sh -- unit tests of the token discovery and the credential rules.
# CLASS (section 11.4.289(C)(2)): gate-logic / unit, against the loopback fixture server. Every token here
# is a FAKE test value. Proves: discovery order env -> keys file -> project .env; a group/other-readable
# keys file is refused; placeholder = absent; the .env file is parsed, never executed; the token never
# reaches the argv or the environment of curl, never stdout/stderr (also under an inherited xtrace and
# allexport), only the pinned API origin; a missing token for a write is a GAP naming the variables.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
TOK_ENV="envTOKENvalueQwErTyUiOpAsDfGh"
TOK_KEYS="keysTOKENvalueQwErTyUiOpAsDfGh"
TOK_DOT="dotTOKENvalueQwErTyUiOpAsDfGh"
SCEN='{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"body":{"full_name":"o/r","has_releases":true}}],
 "GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":7,"tag_name":"v1","prerelease":true,"target_commitish":"main"}}]
}}'
ft_server "$SCEN"
ft_hosts "gitea.test${T}gitea${T}http://127.0.0.1:@PORT@/api/v1${T}TEST_GITEA_TOKEN,TEST_ALT_TOKEN${T}-"
U=git@gitea.test:o/r.git
auth_seen() { grep -o '"Authorization": "[^"]*"' "$FT_SBX/requests.log" | tail -1; }

# C1 environment wins
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV")
printf 'export TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/keys.sh"; chmod 600 "$FT_SBX/keys.sh"; FT_KEYS="$FT_SBX/keys.sh"
ft_run release-get --url "$U" --tag v1
ft_ok "C1 rc" "$FT_RC" 0
ft_has "C1 env token used" "$(auth_seen)" "token $TOK_ENV"
ft_has "C1 source reported by name only" "$FT_OUT" "AUTH: env:TEST_GITEA_TOKEN"

# C2 keys file used when the environment has none
FT_ENV=()
ft_run release-get --url "$U" --tag v1
ft_ok "C2 rc" "$FT_RC" 0
ft_has "C2 keys-file token used" "$(auth_seen)" "token $TOK_KEYS"
ft_has "C2 source" "$FT_OUT" "AUTH: keys_file:TEST_GITEA_TOKEN"

# C3 a group/other-readable keys file is refused (warning) and the .env is used instead
chmod 644 "$FT_SBX/keys.sh"
printf 'TEST_GITEA_TOKEN="%s"\n' "$TOK_DOT" >"$FT_SBX/proj.env"; chmod 600 "$FT_SBX/proj.env"; FT_DOTENV="$FT_SBX/proj.env"
: >"$FT_SBX/requests.log"   # only this run's requests are inspected below
ft_run release-get --url "$U" --tag v1
ft_ok "C3 rc" "$FT_RC" 0
ft_has "C3 insecure keys file warned" "$FT_ERR" "keys_file_insecure"
ft_has "C3 dotenv token used" "$(auth_seen)" "token $TOK_DOT"
ft_lacks "C3 insecure keys file not used" "$(ft_reqs)" "$TOK_KEYS"

# C4 placeholder values count as absent; the second listed name is then tried
chmod 600 "$FT_SBX/keys.sh"
printf 'export TEST_GITEA_TOKEN=changeme\nexport TEST_ALT_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/keys.sh"
: >"$FT_SBX/proj.env"
ft_run release-get --url "$U" --tag v1
ft_ok "C4 rc" "$FT_RC" 0
ft_has "C4 placeholder skipped, second name used" "$FT_OUT" "AUTH: keys_file:TEST_ALT_TOKEN"
for ph in '' xxx '<your-token>' 'PLACEHOLDER' 'abc'; do
  FT_ENV=(TEST_GITEA_TOKEN="$ph"); printf '' >"$FT_SBX/keys.sh"
  ft_run release-ensure --url "$U" --tag v2 --sha 0123456789abcdef0123456789abcdef01234567 --notes-file /dev/null
  ft_ok "C4b placeholder [$ph] = absent: GAP" "$FT_RC" 3
  ft_has "C4b reason names the variables" "$FT_OUT" "REASON: credentials_absent:TEST_GITEA_TOKEN,TEST_ALT_TOKEN"
done
FT_ENV=()

# C5 the .env file is parsed, never executed
# shellcheck disable=SC2016  # a literal $(...) the .env parser must not run
printf 'TEST_GITEA_TOKEN=$(touch %s/EXECUTED)\n' "$FT_SBX" >"$FT_SBX/proj.env"
ft_run release-get --url "$U" --tag v1
[ -e "$FT_SBX/EXECUTED" ] && x=executed || x=not-executed
ft_ok "C5 .env not executed" "$x" not-executed
printf 'export TEST_GITEA_TOKEN='"'"'%s'"'"'\n' "$TOK_DOT" >"$FT_SBX/proj.env"
ft_run release-get --url "$U" --tag v1
ft_has "C5b single-quoted export form parsed" "$(auth_seen)" "token $TOK_DOT"

# C6 the token never reaches curl argv or environment, nor stdout/stderr (wrapper records both)
ft_curl_wrap
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" 'A-B=nonidentsecret' SOME_PASSWORD=pw123secret)
ft_run release-get --url "$U" --tag v1
ft_ok "C6 rc" "$FT_RC" 0
ft_lacks "C6 token not in curl argv/environ" "$(cat "$FT_SBX/bin/curl.log")" "$TOK_ENV"
ft_lacks "C6 non-identifier env entry not passed to curl" "$(cat "$FT_SBX/bin/curl.log")" "nonidentsecret"
ft_lacks "C6 unrelated secret env not passed to curl" "$(cat "$FT_SBX/bin/curl.log")" "pw123secret"
ft_has "C6 curl ran with -K - (config on stdin)" "$(cat "$FT_SBX/bin/curl.log")" "-K"
ft_has "C6 no redirects" "$(cat "$FT_SBX/bin/curl.log")" "--max-redirs"
ft_lacks "C6 token not on stdout" "$FT_OUT" "$TOK_ENV"
ft_lacks "C6 token not on stderr" "$FT_ERR" "$TOK_ENV"
ft_has "C6 server still got the token" "$(auth_seen)" "token $TOK_ENV"

# C7 inherited xtrace and allexport do not leak the token
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" SHELLOPTS=xtrace:allexport)
ft_run release-get --url "$U" --tag v1
ft_lacks "C7 xtrace: token not on stderr" "$FT_ERR" "$TOK_ENV"
ft_lacks "C7 allexport: token not in curl environ" "$(cat "$FT_SBX/bin/curl.log")" "$TOK_ENV"
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" BASH_ENV="$FT_SBX/bashenv.sh")
printf 'set -x\n' >"$FT_SBX/bashenv.sh"
ft_run release-get --url "$U" --tag v1
ft_lacks "C7b BASH_ENV set -x: token not on stderr" "$FT_ERR" "$TOK_ENV"

# C8 a token with characters outside the allowed charset is refused, never sent
FT_ENV=(TEST_GITEA_TOKEN='bad"token\nwith quote 12345')
ft_run release-get --url "$U" --tag v1
ft_ok "C8 bad charset: rc usage/gap" "$FT_RC" 3
ft_has "C8 reason" "$FT_OUT" "REASON: credentials_invalid:TEST_GITEA_TOKEN"

# C9 the token is only sent to the pinned API origin: a hosts row whose api base is another origin than
# the request would never get it (pin check inside the HTTP layer) -- proven by a GitHub-style redirect to a
# foreign origin being refused without a second request
ft_server '{"routes":{"GET /repos/o/r":[{"status":301,"body":{"message":"Moved Permanently","url":"https://evil.example/repositories/1"}}]}}'
ft_hosts "github.test${T}github${T}http://127.0.0.1:@PORT@${T}TEST_GITEA_TOKEN${T}-"
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV")
ft_run repo-exists --url git@github.test:o/r.git
ft_ok "C9 foreign redirect: rc API" "$FT_RC" 4
ft_has "C9 reason" "$FT_OUT" "REASON: redirect_refused"
ft_ok "C9 exactly one request" "$(ft_req_count GET)" 1

# C10 keys file not regular / symlink refused
ln -s "$FT_SBX/keys.sh" "$FT_SBX/keys_link.sh"; FT_KEYS="$FT_SBX/keys_link.sh"; FT_ENV=()
ft_server "$SCEN"
ft_hosts "gitea.test${T}gitea${T}http://127.0.0.1:@PORT@/api/v1${T}TEST_GITEA_TOKEN,TEST_ALT_TOKEN${T}-"
: >"$FT_SBX/proj.env"
ft_run release-get --url "$U" --tag v1
ft_has "C10 symlinked keys file refused" "$FT_ERR" "keys_file_insecure"

# ---- round 2 (independent review of 2026-11-12, findings I1 I5 I6 M2 M3 M6 N-a; reviewer probes P1-P8) ----
SHA=0123456789abcdef0123456789abcdef01234567
SCEN_W='{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"body":{"full_name":"o/r","has_releases":true}}],
 "GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"sha":"'$SHA'"}}}],
 "GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"nf"}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":false,"draft":false,"target_commitish":"'$SHA'"}}],
 "POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]
}}'
hosts1() { ft_hosts "gitea.test${T}gitea${T}http://127.0.0.1:@PORT@/api/v1${T}TEST_GITEA_TOKEN,TEST_ALT_TOKEN${T}-"; }
posts() { ft_req_count POST; }
FT_ENV=(); FT_DOTENV="$FT_SBX/no.env"
printf 'export TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/keys.sh"; chmod 600 "$FT_SBX/keys.sh"; FT_KEYS="$FT_SBX/keys.sh"
printf 'release notes, no secret\n' >"$FT_SBX/notes_ok.md"

# R1 (I1, probe P4) the notes file IS the keys file: refused before any write, value never shown
ft_server "$SCEN_W"; hosts1
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/keys.sh"
ft_ok "R1 notes = keys file: rc usage" "$FT_RC" 2
ft_has "R1 reason" "$FT_OUT" "REASON: notes_is_credentials_file"
ft_ok "R1 no POST" "$(posts)" 0
ft_lacks "R1 token not echoed" "$FT_OUT$FT_ERR" "$TOK_KEYS"
# R1b the same file by a symlink and by a hard link
ln -sf "$FT_SBX/keys.sh" "$FT_SBX/notes_link.md"; ln -f "$FT_SBX/keys.sh" "$FT_SBX/notes_hard.md"
for nf in notes_link.md notes_hard.md; do
  ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/$nf"
  ft_has "R1b $nf refused" "$FT_OUT" "REASON: notes_is_credentials_file"
done
rm -f -- "$FT_SBX/notes_hard.md" "$FT_SBX/notes_link.md"
# R1c the notes file is the .env
printf 'TEST_ALT_TOKEN=%s\n' "$TOK_DOT" >"$FT_SBX/proj.env"; chmod 600 "$FT_SBX/proj.env"; FT_DOTENV="$FT_SBX/proj.env"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/proj.env"
ft_has "R1c notes = .env refused" "$FT_OUT" "REASON: notes_is_credentials_file"
# R1d another file whose TEXT holds the resolved token, or the .env value of the second listed name
printf 'see token %s here\n' "$TOK_KEYS" >"$FT_SBX/notes_tok.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_tok.md"
ft_ok "R1d resolved token in notes: rc usage" "$FT_RC" 2
ft_has "R1d reason" "$FT_OUT" "REASON: notes_contain_token"
ft_has "R1d names the variable only" "$FT_ERR" "value of TEST_GITEA_TOKEN"
ft_lacks "R1d value not echoed" "$FT_OUT$FT_ERR" "$TOK_KEYS"
printf 'prefix%ssuffix\n' "$TOK_DOT" >"$FT_SBX/notes_tok.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_tok.md"
ft_has "R1e .env value of another name in notes refused" "$FT_OUT" "REASON: notes_contain_token"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_ok.md" --title "x $TOK_KEYS"
ft_has "R1f token in the title refused" "$FT_OUT" "REASON: title_contains_token"
ft_ok "R1 no write in any refused case" "$(posts)" 0
# R1g positive control: clean notes are posted, and what was scanned is what is sent
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_ok.md"
ft_ok "R1g clean notes: rc" "$FT_RC" 0
ft_ok "R1g one POST" "$(posts)" 1
ft_has "R1g body sent" "$(ft_reqs | grep '"POST"')" 'release notes, no secret'
ft_ok "R1g no temporary directory left (I6 N09)" "$(ft_tmpdirs)" 0
FT_DOTENV="$FT_SBX/no.env"; : >"$FT_SBX/proj.env"

# R2 (I6 N17) a GROUP-readable keys file (0640) is refused like a world-readable one
ft_server "$SCEN"; hosts1
chmod 640 "$FT_SBX/keys.sh"
ft_run release-get --url "$U" --tag v1
ft_has "R2 0640 keys file refused" "$FT_ERR" "keys_file_insecure"
ft_has "R2 not used" "$FT_OUT" "AUTH: none"
chmod 600 "$FT_SBX/keys.sh"

# R3 (I6 N04) a keys file owned by ANOTHER user (root, mode 0600) is refused before it is read
rootf=""
for c in /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_ecdsa_key /etc/gshadow- /etc/shadow-; do
  [ -f "$c" ] && [ ! -L "$c" ] || continue
  [ "$(stat -c '%u' -- "$c")" = 0 ] || continue
  [ $(( 8#$(stat -c '%a' -- "$c") & 8#077 )) -eq 0 ] || continue
  rootf="$c"; break
done
if [ -n "$rootf" ] && [ "$(id -u)" != 0 ]; then
  FT_KEYS="$rootf"
  ft_run release-get --url "$U" --tag v1
  ft_has "R3 foreign-owned keys file refused" "$FT_ERR" "keys_file_insecure"
  FT_KEYS="$FT_SBX/keys.sh"
else
  ft_skip "R3 foreign-owned keys file" "no root-owned 0600 regular file found, or running as root"
fi

# R4 (I6 N05) an INVALID value in the keys file stops the search: the .env value is never used instead
printf 'export TEST_GITEA_TOKEN='"'"'bad"value with space 12345'"'"'\n' >"$FT_SBX/keys.sh"
printf 'TEST_ALT_TOKEN=%s\n' "$TOK_DOT" >"$FT_SBX/proj.env"; FT_DOTENV="$FT_SBX/proj.env"
: >"$FT_SBX/requests.log"
ft_run release-get --url "$U" --tag v1
ft_ok "R4 invalid keys value: rc GAP" "$FT_RC" 3
ft_has "R4 reason" "$FT_OUT" "REASON: credentials_invalid:TEST_GITEA_TOKEN"
ft_lacks "R4 .env value not used" "$(ft_reqs)" "$TOK_DOT"
printf 'export TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/keys.sh"; FT_DOTENV="$FT_SBX/no.env"

# R5 (I6 N06) proxy variables of the caller never reach curl (they would route the token elsewhere)
ft_curl_wrap
FT_ENV=(https_proxy=http://proxyleak.invalid:9 HTTPS_PROXY=http://proxyleak.invalid:9 ALL_PROXY=http://proxyleak.invalid:9 all_proxy=http://proxyleak.invalid:9 http_proxy=http://proxyleak.invalid:9)
ft_run release-get --url "$U" --tag v1
ft_ok "R5 rc" "$FT_RC" 0
ft_lacks "R5 no proxy variable in curl environ" "$(cat "$FT_SBX/bin/curl.log")" "proxyleak.invalid"
FT_ENV=()

# R6 (I6 N01) the generic origin pin of fg_http_url, tested directly (no provider's own check in between):
# a URL of another origin is refused before curl starts
FORGE_LIB="$(cd "$(dirname "$FORGE")" && pwd)/lib"
: >"$FT_SBX/bin/curl.log"; mkdir -p "$FT_SBX/u"
# shellcheck disable=SC2016  # the child script is single-quoted on purpose: it expands in the child
pin="$(env -i PATH="$FT_SBX/bin:$PATH" HOME="$FT_SBX" bash -c '. "$1/common.sh" && . "$1/http.sh" || exit 9
  FG_API_ORIGIN=https://127.0.0.2:1 FG_TMP="$2" FG_TOKEN=pinTOKENvalue0123456789 FG_AUTH_FMT="X: %s"; FG_HDRS=()
  FORGE_HTTP_TIMEOUT=2
  fg_http_url GET https://127.0.0.1:1/x; printf "rc=%s net=%s;" "$?" "$FG_NET"
  fg_http_url GET https://127.0.0.2:2/x; printf "rc=%s net=%s;" "$?" "$FG_NET"
  fg_http_url GET https://127.0.0.2:1/x; printf "rc=%s net=%s" "$?" "$FG_NET"' t "$FORGE_LIB" "$FT_SBX/u" 2>/dev/null)"
ft_ok "R6 other host and other port refused by the pin; same origin reaches curl" "$pin" "rc=1 net=pin;rc=1 net=pin;rc=1 net=refused"
ft_ok "R6 curl started only for the pinned origin" "$(grep -c '^=== argv' "$FT_SBX/bin/curl.log")" 1
FT_PATH=""

# R7 (M3) the hosts map decides where tokens go: a world-writable map or a symlinked map is refused
ft_server "$SCEN"; hosts1
chmod 666 "$FT_SBX/hosts.tsv"
ft_run detect --url "$U"
ft_ok "R7 world-writable hosts map: rc usage" "$FT_RC" 2
ft_has "R7 reason" "$FT_OUT" "REASON: hosts_file_insecure"
chmod 644 "$FT_SBX/hosts.tsv"; ln -sf "$FT_SBX/hosts.tsv" "$FT_SBX/hosts_link.tsv"; FT_HOSTS_FILE="$FT_SBX/hosts_link.tsv"
ft_run detect --url "$U"
ft_has "R7b symlinked hosts map refused" "$FT_OUT" "REASON: hosts_file_insecure"
FT_HOSTS_FILE=""; rm -f -- "$FT_SBX/hosts_link.tsv"

# R8 (N-a) a port outside 1..65535 is refused in the hosts map and in a remote URL
ft_hosts "gitea.test${T}gitea${T}https://api.example:99999${T}TEST_GITEA_TOKEN${T}-"
ft_run detect --url "$U"
ft_has "R8 api base port 99999 refused" "$FT_OUT" "REASON: hosts_file_invalid"
ft_hosts "gitea.test${T}gitea${T}https://api.example:0${T}TEST_GITEA_TOKEN${T}-"
ft_run detect --url "$U"
ft_has "R8 api base port 0 refused" "$FT_OUT" "REASON: hosts_file_invalid"
hosts1
ft_run detect --url "ssh://git@gitea.test:70000/o/r.git"
ft_ok "R8 remote URL port 70000: rc usage" "$FT_RC" 2

# R9 (M6) the .env of an untrusted repository (the cwd, forge.sh not inside it) is not read
ft_server "$SCEN"; hosts1
mkdir -p "$FT_SBX/evil" && git -C "$FT_SBX/evil" init -q 2>/dev/null
printf 'TEST_GITEA_TOKEN=%s\n' "$TOK_DOT" >"$FT_SBX/evil/.env"; chmod 600 "$FT_SBX/evil/.env"
FT_KEYS="$FT_SBX/no_keys.sh"; FT_NO_ENVFILE=1; FT_CWD="$FT_SBX/evil"; : >"$FT_SBX/requests.log"
ft_run release-get --url "$U" --tag v1
ft_has "R9 untrusted .env noted" "$FT_ERR" "dotenv_not_trusted"
ft_has "R9 not used" "$FT_OUT" "AUTH: none"
ft_lacks "R9 token never sent" "$(ft_reqs)" "$TOK_DOT"
FT_NO_ENVFILE=0; FT_DOTENV="$FT_SBX/evil/.env"
ft_run release-get --url "$U" --tag v1
ft_has "R9b the same file given explicitly is used" "$FT_OUT" "AUTH: dotenv:TEST_GITEA_TOKEN"
FT_CWD=""; FT_DOTENV="$FT_SBX/no.env"; FT_KEYS="$FT_SBX/keys.sh"

# ---- reviewer bypass probes (scratch rev_mf_tools/probes.sh, adopted as assertions) ----
# P1 an exported function named curl in the caller environment never runs in the clean process
ft_server "$SCEN_W"; hosts1
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" 'BASH_FUNC_curl%%=() { printf "%s" "$*" > '"$FT_SBX"'/FUNC_RAN; }')
ft_run release-get --url "$U" --tag v1
[ -e "$FT_SBX/FUNC_RAN" ] && x=ran || x=not-ran
ft_ok "P1 exported function curl not executed" "$x" not-ran
# P2 a keys file that prints the token on stdout/stderr while sourced: nothing reaches the output
# shellcheck disable=SC2016  # literal text of the keys file: it expands when the keys file is sourced
printf 'echo "$TEST_GITEA_TOKEN"; export TEST_GITEA_TOKEN=%s; echo "%s"; echo "%s" >&2\n' "$TOK_KEYS" "$TOK_KEYS" "$TOK_KEYS" >"$FT_SBX/keys.sh"; chmod 600 "$FT_SBX/keys.sh"
FT_ENV=()
ft_server "$SCEN_W"; hosts1
ft_run release-get --url "$U" --tag v1
ft_lacks "P2 token not on stdout" "$FT_OUT" "$TOK_KEYS"
ft_lacks "P2 token not on stderr" "$FT_ERR" "$TOK_KEYS"
ft_has "P2 keys file used" "$FT_OUT" "AUTH: keys_file:TEST_GITEA_TOKEN"
# P3 a remote URL with the token as a password, or a token-shaped stray word: refused, never echoed
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV"); FT_KEYS="$FT_SBX/no_keys.sh"
ft_run release-get --url "https://user:$TOK_ENV@gitea.test/o/r.git" --tag v1
ft_lacks "P3 https password not echoed" "$FT_OUT$FT_ERR" "$TOK_ENV"
ft_ok "P3 rc usage" "$FT_RC" 2
ft_run release-get --url "ssh://user:$TOK_ENV@gitea.test/o/r.git" --tag v1
ft_lacks "P3b ssh password not echoed" "$FT_OUT$FT_ERR" "$TOK_ENV"
ft_ok "P3b rc usage" "$FT_RC" 2
ft_run release-get --url "$U" --tag v1 "$TOK_ENV"
ft_lacks "P3c token-shaped argv word not echoed" "$FT_OUT$FT_ERR" "$TOK_ENV"
# P5 api bases with userinfo, a backslash-@ trick, plain http or a bad port are hosts_file_invalid
for ab in "https://api.example@evil.example" "https://evil.example\\@api.example" "http://evil.example" "https://evil.example:99999"; do
  ft_hosts "gitea.test${T}gitea${T}${ab}${T}TEST_GITEA_TOKEN${T}-"
  ft_run detect --url "$U"
  ft_ok "P5 api base [$ab] refused" "$FT_RC" 2
done
# P7 a group-readable .env is refused
printf 'TEST_GITEA_TOKEN=%s\n' "$TOK_DOT" >"$FT_SBX/p.env"; chmod 640 "$FT_SBX/p.env"
FT_DOTENV="$FT_SBX/p.env"; FT_KEYS=/nonexistent; FT_ENV=()
ft_server "$SCEN_W"; hosts1
ft_run release-get --url "$U" --tag v1
ft_has "P7 group-readable .env refused" "$FT_ERR" "keys_file_insecure"
ft_ok "P7 AUTH none" "$(grep -c 'AUTH: none' <<<"$FT_OUT")" 1
# P8 a .env value with a trailing comment and CRLF
printf 'TEST_GITEA_TOKEN=%s # my token\r\n' "$TOK_DOT" >"$FT_SBX/p.env"; chmod 600 "$FT_SBX/p.env"
ft_run release-get --url "$U" --tag v1
ft_has "P8 trailing comment and CR stripped" "$(auth_seen)" "token $TOK_DOT\""
FT_DOTENV="$FT_SBX/no.env"; FT_KEYS="$FT_SBX/keys.sh"
# P6 (M2) SIGTERM during a slow answer: handled at once, curl stopped, temp dir removed, REASON + RESULT
ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":200,"delay":8,"body":{"full_name":"o/r","has_releases":true}}]}}'; hosts1
env -i PATH="$PATH" HOME="$FT_SBX/home" TMPDIR="$FT_SBX" FORGE_HOSTS_FILE="$FT_SBX/hosts.tsv" FORGE_TEST_ALLOW_HTTP_LOOPBACK=1 \
  FORGE_KEYS_FILE=/nonexistent FORGE_ENV_FILE=/nonexistent FORGE_HTTP_TIMEOUT=30 TEST_GITEA_TOKEN="$TOK_ENV" \
  bash "$FORGE" repo-exists --url "$U" >"$FT_SBX/p6.out" 2>"$FT_SBX/p6.err" </dev/null &
p6=$!
i=0; while [ "$(ft_req_count GET)" -lt 1 ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
t0=$(date +%s%N); kill -TERM "$p6"; wait "$p6"; p6rc=$?; t1=$(date +%s%N)
ft_ok "P6 rc 143" "$p6rc" 143
ft_ok "P6 last line RESULT: INTERRUPTED" "$(tail -1 "$FT_SBX/p6.out")" "RESULT: INTERRUPTED"
ft_has "P6 reason" "$(cat "$FT_SBX/p6.out")" "REASON: interrupted"
ft_ok "P6 ended within 4 s of the signal" "$(( (t1 - t0) / 1000000000 < 4 ))" 1
ft_ok "P6 no temporary directory left" "$(ft_tmpdirs)" 0
ft_lacks "P6 token not in output" "$(cat "$FT_SBX/p6.out" "$FT_SBX/p6.err")" "$TOK_ENV"

# ---- round 3 (independent review of round 2: R2-I2, R2-I3, minors; reviewer probes Q6-Q12 adopted) ----
# sbx_procs: processes of ours (other than the fixture server) whose command line names the sandbox: a curl
# (or timeout) child the tool left running reads/writes "$FG_TMP" there. Read from /proc, never a pattern match
# on our own command line (section 11.4.196(D)): python reads each /proc/<pid>/cmdline as bytes.
sbx_procs() {
  python3 -I - "$FT_SBX" <<'PYEOF'
import os, sys
sbx = sys.argv[1].encode(); me = os.getpid(); n = 0
for d in os.listdir("/proc"):
    if not d.isdigit() or int(d) in (me, os.getppid()):
        continue
    try:
        c = open("/proc/%s/cmdline" % d, "rb").read()
        if os.stat("/proc/%s" % d).st_uid != os.getuid():
            continue
    except OSError:
        continue
    if sbx in c and b"forge_fixture_server" not in c:
        n += 1
print(n)
PYEOF
}
# Q9 / X05 SIGTERM during a slow POST: rc 143, INTERRUPTED, no temporary directory, and the curl child is
# STOPPED (not left to finish the write on its own after the tool reported INTERRUPTED)
ft_server_stop
ft_server '{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"body":{"full_name":"o/r","has_releases":true}}],
 "GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"sha":"'$SHA'"}}}],
 "GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"nf"}}],
 "POST /api/v1/repos/o/r/releases":[{"status":201,"delay":20,"body":{"id":11}}]}}'; hosts1
ft_ok "Q9 control: the process instrument sees none before the run" "$(sbx_procs)" 0
env -i PATH="$PATH" HOME="$FT_SBX/home" TMPDIR="$FT_SBX" FORGE_HOSTS_FILE="$FT_SBX/hosts.tsv" FORGE_TEST_ALLOW_HTTP_LOOPBACK=1 \
  FORGE_KEYS_FILE=/nonexistent FORGE_ENV_FILE=/nonexistent FORGE_HTTP_TIMEOUT=60 TEST_GITEA_TOKEN="$TOK_ENV" \
  bash "$FORGE" release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_ok.md" >"$FT_SBX/q9.out" 2>"$FT_SBX/q9.err" </dev/null &
q9=$!
i=0; while [ "$(ft_req_count POST)" -lt 1 ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
ft_ok "Q9 control: the POST is in flight" "$(ft_req_count POST)" 1
ft_ok "Q9 control: the instrument sees the curl child while it runs" "$([ "$(sbx_procs)" -ge 1 ] && echo y)" y
kill -TERM "$q9"; wait "$q9"; q9rc=$?
ft_ok "Q9 rc 143" "$q9rc" 143
ft_ok "Q9 last line" "$(tail -1 "$FT_SBX/q9.out")" "RESULT: INTERRUPTED"
ft_ok "Q9 no temporary directory left" "$(ft_tmpdirs)" 0
sleep 0.3
ft_ok "Q9 X05 no curl/timeout child left running" "$(sbx_procs)" 0
ft_server_stop

# Q10 SIGTERM while the keys file is still being read (before fg_tmp_init): a REASON and a RESULT line
ft_server "$SCEN_W"; hosts1
printf 'sleep 4\nexport TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/slowkeys.sh"; chmod 600 "$FT_SBX/slowkeys.sh"
env -i PATH="$PATH" HOME="$FT_SBX/home" TMPDIR="$FT_SBX" FORGE_HOSTS_FILE="$FT_SBX/hosts.tsv" FORGE_TEST_ALLOW_HTTP_LOOPBACK=1 \
  FORGE_KEYS_FILE="$FT_SBX/slowkeys.sh" FORGE_ENV_FILE=/nonexistent bash "$FORGE" release-get --url "$U" --tag v1 \
  >"$FT_SBX/q10.out" 2>"$FT_SBX/q10.err" </dev/null &
q10=$!; sleep 1.2; kill -TERM "$q10"; wait "$q10"; q10rc=$?
ft_ok "Q10 rc 143" "$q10rc" 143
ft_ok "Q10 last line RESULT: INTERRUPTED" "$(tail -1 "$FT_SBX/q10.out")" "RESULT: INTERRUPTED"
ft_has "Q10 reason" "$(cat "$FT_SBX/q10.out")" "REASON: interrupted"
ft_ok "Q10 no request made" "$(ft_req_count GET)" 0
i=0; while [ "$(sbx_procs)" -gt 0 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done   # the keys reader ends on its own

# R10 (review R2-I2 / minor) an INCOMPLETE token set (the keys file could not be read to its end) is a GAP for
# release-ensure: the notes could not be checked against every token value
printf 'sleep 3\nexport TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/slowkeys.sh"
FT_KEYS="$FT_SBX/slowkeys.sh"; FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" FORGE_KEYS_TIMEOUT=1)
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_ok.md"
ft_ok "R10 incomplete token set: rc GAP" "$FT_RC" 3
ft_has "R10 reason" "$FT_OUT" "REASON: keys_file_unreadable"
ft_ok "R10 no write" "$(posts)" 0
ft_run release-get --url "$U" --tag v1
ft_has "R10b read-only command: warned, not stopped" "$FT_ERR" "keys_file_incomplete"
ft_ok "R10b rc 0" "$FT_RC" 0
FT_KEYS="$FT_SBX/keys.sh"; FT_ENV=()
i=0; while [ "$(sbx_procs)" -gt 0 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done

# Q7 / X03 the notes hold the value of a *TOKEN variable of the ENVIRONMENT that no hosts row names
ft_server "$SCEN_W"; hosts1
OTOK="githubOTHERtokenKzQwPlMnBvCxZaSd"
printf 'release notes\nexport GITHUB_TOKEN=%s\n' "$OTOK" >"$FT_SBX/copy_notes.md"
FT_ENV=(GITHUB_TOKEN="$OTOK")
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/copy_notes.md" --dry-run
ft_ok "Q7 another variable's token in the notes: rc usage" "$FT_RC" 2
ft_has "Q7 reason" "$FT_OUT" "REASON: notes_contain_token"
ft_has "Q7 names the variable only" "$FT_ERR" "value of GITHUB_TOKEN"
ft_lacks "Q7 value not echoed" "$FT_OUT$FT_ERR" "$OTOK"
FT_ENV=()
# X02 a *TOKEN name set only in the KEYS FILE (no hosts row, not in the environment)
printf 'export TEST_GITEA_TOKEN=%s\nexport UNRELATED_SVC_TOKEN=%s\n' "$TOK_KEYS" "$OTOK" >"$FT_SBX/keys.sh"; chmod 600 "$FT_SBX/keys.sh"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/copy_notes.md" --dry-run
ft_has "X02 keys-file-only token name in the notes refused" "$FT_OUT" "REASON: notes_contain_token"
ft_has "X02 names it" "$FT_ERR" "value of UNRELATED_SVC_TOKEN"
printf 'export TEST_GITEA_TOKEN=%s\n' "$TOK_KEYS" >"$FT_SBX/keys.sh"
# a 12-character PART of a token in the notes is refused too; an 11-character part is not (the window size)
printf 'cut: %s\n' "${TOK_KEYS:4:12}" >"$FT_SBX/part_notes.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/part_notes.md" --dry-run
ft_has "R11 12-character part refused" "$FT_OUT" "REASON: notes_contain_token"
printf 'cut: %s\n' "${TOK_KEYS:4:11}" >"$FT_SBX/part_notes.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/part_notes.md" --dry-run
ft_ok "R11 false-positive guard: an 11-character part is accepted" "$FT_RC" 0
ft_ok "R1 dry-runs wrote nothing" "$(posts)" 0

# X01 the notes file is the .env of the repository forge.sh runs in, while FORGE_ENV_FILE names another file
mkdir -p "$FT_SBX/repo2" && git -C "$FT_SBX/repo2" init -q 2>/dev/null
printf 'TEST_GITEA_TOKEN=%s\n' "$TOK_DOT" >"$FT_SBX/repo2/.env"; chmod 600 "$FT_SBX/repo2/.env"
FT_CWD="$FT_SBX/repo2"; FT_DOTENV="$FT_SBX/no.env"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/repo2/.env"
ft_has "X01 notes = the repository .env refused as a credentials file" "$FT_OUT" "REASON: notes_is_credentials_file"
ft_lacks "X01 value not echoed" "$FT_OUT$FT_ERR" "$TOK_DOT"
FT_CWD=""

# X04 what was scanned is what is sent: the notes file is REWRITTEN on disk while the tool talks to the forge
# (the fixture writes it when GET repo is served); the POST body is the copy taken before the scan
printf 'clean notes v1\n' >"$FT_SBX/notes_rw.md"
ft_server '{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"write":{"path":"'"$FT_SBX"'/notes_rw.md","text":"REPLACED-AFTER-SCAN\n"},"body":{"full_name":"o/r","has_releases":true}}],
 "GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"sha":"'$SHA'"}}}],
 "GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"nf"}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":false,"draft":false,"target_commitish":"'$SHA'"}}],
 "POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts1
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_rw.md"
ft_ok "X04 rc 0" "$FT_RC" 0
ft_ok "X04 control: the file WAS rewritten during the run" "$(cat "$FT_SBX/notes_rw.md")" "REPLACED-AFTER-SCAN"
ft_has "X04 the scanned text is sent" "$(ft_reqs | grep '"POST"')" "clean notes v1"
ft_lacks "X04 the later text is not sent" "$(ft_reqs | grep '"POST"')" "REPLACED-AFTER-SCAN"

# X10 the notes size limit is exact: 1000000 bytes accepted, 1000001 refused (before any request)
ft_server "$SCEN_W"; hosts1
head -c 1000000 /dev/zero | tr '\0' a >"$FT_SBX/big.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/big.md" --dry-run
ft_ok "X10 1000000 bytes accepted" "$FT_RC" 0
printf 'a' >>"$FT_SBX/big.md"
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/big.md" --dry-run
ft_ok "X10 1000001 bytes: rc usage" "$FT_RC" 2
ft_has "X10 reason" "$FT_OUT" "REASON: notes_too_large"
rm -f -- "$FT_SBX/big.md"

# R12 a FIFO as the notes file is refused WITHOUT opening it (a writer is started so a regression cannot hang)
mkfifo "$FT_SBX/notes.fifo"
# shellcheck disable=SC2016  # the child script expands "$1" itself
timeout 30 sh -c 'printf "fifo notes\n" >"$1"' sh "$FT_SBX/notes.fifo" & fw=$!
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.fifo" --dry-run
ft_ok "R12 FIFO: rc usage" "$FT_RC" 2
ft_has "R12 reason" "$FT_OUT" "REASON: notes_not_regular"
timeout 5 cat "$FT_SBX/notes.fifo" >/dev/null 2>&1; wait "$fw" 2>/dev/null; rm -f -- "$FT_SBX/notes.fifo"

# Q11 the title carries the token: refused, nothing sent
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes_ok.md" --title "rel $TOK_KEYS"
ft_has "Q11 title refused" "$FT_OUT" "REASON: title_contains_token"
ft_lacks "Q11 token not echoed" "$FT_OUT$FT_ERR" "$TOK_KEYS"
ft_ok "Q11 no write" "$(posts)" 0

# Q8 + parent directory (review minor): own map 0664/0644 accepted; 0666 refused; the DIRECTORY of the map
# writable by others refused (it could be replaced), unless sticky (1777: only the owner may replace it)
mkdir -p "$FT_SBX/hd"; cp -- "$FT_SBX/hosts.tsv" "$FT_SBX/hd/hosts.tsv"; chmod 644 "$FT_SBX/hd/hosts.tsv"
FT_HOSTS_FILE="$FT_SBX/hd/hosts.tsv"
chmod 755 "$FT_SBX/hd"; ft_run detect --url "$U"; ft_ok "Q8 own map in a 0755 directory accepted" "$FT_RC" 0
chmod 664 "$FT_SBX/hd/hosts.tsv"; ft_run detect --url "$U"; ft_ok "Q8 0664 own map accepted" "$FT_RC" 0
chmod 644 "$FT_SBX/hd/hosts.tsv"
chmod 777 "$FT_SBX/hd"; ft_run detect --url "$U"
ft_ok "R13 0777 directory: rc usage" "$FT_RC" 2
ft_has "R13 reason" "$FT_OUT" "REASON: hosts_file_insecure"
ft_has "R13 the directory is named as the cause" "$FT_ERR" "directory is writable by others"
chmod 1777 "$FT_SBX/hd"; ft_run detect --url "$U"; ft_ok "R13 sticky 1777 directory accepted" "$FT_RC" 0
chmod 755 "$FT_SBX/hd"; FT_HOSTS_FILE=""
# X08 a map owned by ANOTHER (non-root) user in a root-owned directory: refused by the FILE owner check
fo=""
while IFS= read -r c; do
  d="$(dirname -- "$c")"
  [ "$(stat -c '%u' -- "$d")" = 0 ] && [ $(( 8#$(stat -c '%a' -- "$d") & 8#002 )) -eq 0 ] || continue
  [ $(( 8#$(stat -c '%a' -- "$c") & 8#002 )) -eq 0 ] || continue
  fo="$c"; break
done < <(timeout 20 find /var/lib /usr/share /opt -maxdepth 3 -type f ! -user root ! -user "$(id -un)" -perm -o=r 2>/dev/null)
if [ -n "$fo" ] && [ "$(id -u)" != 0 ]; then
  FT_HOSTS_FILE="$fo"; ft_run detect --url "$U"
  ft_has "X08 map owned by another user refused" "$FT_OUT" "REASON: hosts_file_insecure"
  ft_has "X08 by the file owner check" "$FT_ERR" "hosts map is owned by another user"
  FT_HOSTS_FILE=""
else
  ft_skip "X08 map owned by another non-root user" "no such world-readable file under a root-owned directory found, or running as root"
fi
# false-positive guard: a ROOT-owned map in a root directory passes the trust check (then the parser decides)
if [ -f /etc/hostname ]; then
  FT_HOSTS_FILE=/etc/hostname; ft_run detect --url "$U"
  ft_lacks "Q8 root-owned map not refused as insecure" "$FT_OUT" "hosts_file_insecure"
  FT_HOSTS_FILE=""
fi

# Q12 neither the token nor FORGE_TRACE_PEER reaches the curl argv or environment (curl recorder)
ft_curl_wrap
FT_ENV=(TEST_GITEA_TOKEN="$TOK_ENV" FORGE_TRACE_PEER=1)
ft_run repo-exists --url "$U"
ft_lacks "Q12 token not in curl argv/env" "$(cat "$FT_SBX/bin/curl.log")" "$TOK_ENV"
ft_lacks "Q12 FORGE_ variable not in the child environment" "$(cat "$FT_SBX/bin/curl.log")" "FORGE_TRACE_PEER"
ft_has "Q12 control: the recorder saw a call" "$(cat "$FT_SBX/bin/curl.log")" "--globoff"
FT_PATH=""; FT_ENV=()

# ---- round 4 (independent review of round 3: R3-I1, minors m2, m3, m6; reviewer probes Z5-Z7 adopted) -------
# The short-value branch (a token of 8 to 11 characters is matched whole) and the long-text branch (text over
# 4096 bytes goes through grep first) of the sanitiser, with tokens of 8 to 19 characters and notes over 4096
# bytes. The fixture is GitVerse-shaped (it reflects an X-Request-Id header in the PEER line).
GV_U=git@gitverse.test:o/r.git
gv4_hosts() { ft_hosts "gitverse.test${T}gitverse${T}http://127.0.0.1:@PORT@${T}TEST_GITVERSE_TOKEN${T}-"; }
gv4_probe_scen() { # REQUEST_ID
  ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"headers":{"X-Request-Id":"'"$1"'"},"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/releases":[{"status":200,"body":[]}],"GET /repos/o/r/git/matching-refs/tags/":[{"status":200,"body":[]}]}}'; gv4_hosts
}
gv4_write_scen() {
  ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"commit","sha":"'$SHA'"}}]}],
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}}],"GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; gv4_hosts
}
long_notes() { # FILE TEXT: more than 4096 bytes of filler, then TEXT on the last line
  { head -c 5000 /dev/zero | tr '\0' 'n'; printf ' %s\n' "$2"; } >"$1"
}
FT_KEYS="$FT_SBX/no_keys.sh"
# Z5 + lengths 8..19: a short token reflected in a request id is never printed (positive control: the request
# id is printed, scrubbed); the same token in a short and in a long notes file is refused, nothing is POSTed
for len in 8 9 11 12 15 19; do
  STOK="$(printf 'Ab3dE6gH9kLmN2pQr5tUvW' | cut -c1-"$len")"
  FT_ENV=(TEST_GITVERSE_TOKEN="$STOK")
  gv4_probe_scen "zz${STOK}zz"
  ft_run probe --url "$GV_U"
  ft_lacks "Z5 a $len-character token reflected in X-Request-Id is not printed" "$FT_OUT$FT_ERR" "$STOK"
  ft_has "Z5 control ($len): the request id was printed, scrubbed" "$FT_OUT" "request_id=x-request-id=unsafe"
  gv4_write_scen
  printf 'notes %s\n' "$STOK" >"$FT_SBX/short_tok_notes.md"
  ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/short_tok_notes.md"
  ft_ok "Z6 ($len) short notes with the token: refused" "$FT_RC" 2
  ft_has "Z6 ($len) short notes reason" "$FT_OUT" "REASON: notes_contain_token"
  long_notes "$FT_SBX/long_tok_notes.md" "$STOK"
  ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/long_tok_notes.md"
  ft_ok "Z6 ($len) notes over 4096 bytes with the token: refused" "$FT_RC" 2
  ft_has "Z6 ($len) long notes reason" "$FT_OUT" "REASON: notes_contain_token"
  ft_ok "Z6 ($len) no POST" "$(posts)" 0
done
# Z6 false-positive guard: notes over 4096 bytes without any token are posted (the grep fast path says "no")
gv4_write_scen
long_notes "$FT_SBX/long_clean_notes.md" "clean"
ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/long_clean_notes.md"
ft_has "Z6 control: clean long notes are not refused" "$FT_OUT" "ACTION: created"
ft_ok "Z6 control: one POST" "$(posts)" 1
# Z7 a 12-character MIDDLE piece of a long token, in notes over 4096 bytes: refused
LTOK="gitverseTESTtoken0123456789abcdef"
FT_ENV=(TEST_GITVERSE_TOKEN="$LTOK")
gv4_write_scen
long_notes "$FT_SBX/long_piece_notes.md" "x${LTOK:7:12}x"
ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/long_piece_notes.md"
ft_ok "Z7 long notes with a 12-character middle piece: refused" "$FT_RC" 2
ft_ok "Z7 no POST" "$(posts)" 0
# R14 (review m3, W05) the last 12-character piece (a suffix) is a window too, in short and in long notes
printf 'tail x%sx\n' "${LTOK: -12}" >"$FT_SBX/suffix_notes.md"
ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/suffix_notes.md" --dry-run
ft_has "R14 suffix piece in short notes refused" "$FT_OUT" "REASON: notes_contain_token"
long_notes "$FT_SBX/long_suffix_notes.md" "x${LTOK: -12}x"
ft_run release-ensure --url "$GV_U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/long_suffix_notes.md" --dry-run
ft_has "R14 suffix piece in long notes refused" "$FT_OUT" "REASON: notes_contain_token"
FT_ENV=(); FT_KEYS="$FT_SBX/keys.sh"

# U1-U3 (review m2 W01/W02, m6) unit tests of the output helpers of lib/common.sh, sourced in a child bash
# with a known secret set: fg_msg (stderr) and the REASON line of fg_end are scrubbed; fg_scrub keeps every
# line of a multi-line text and scrubs each one
UTOK="unitTESTsecret0123ab"
u_run() { # SNIPPET: run it with lib/common.sh sourced and UTOK as the only secret; stdout+stderr
  bash -c '. "$1" || exit 9; FG_SEC_NAMES=(UNIT_TOKEN); FG_SEC_VALS=("$2"); eval "$3"' u "$(dirname "$FORGE")/lib/common.sh" "$UTOK" "$1" 2>&1
}
# shellcheck disable=SC2016  # snippets expand in the child
U1="$(u_run 'fg_msg "repo o/$2 here"')"
ft_lacks "U1 fg_msg scrubs the secret" "$U1" "$UTOK"
ft_has "U1 fg_msg control: the message is printed" "$U1" "forge: repo unsafe here"
# shellcheck disable=SC2016
U2="$(u_run 'fg_end FAIL 1 "code_$2"')"
ft_lacks "U2 REASON scrubs the secret" "$U2" "$UTOK"
ft_has "U2 REASON control" "$U2" "REASON: unsafe"
# shellcheck disable=SC2016
U3="$(u_run 'fg_scrub "first $2 x
second clean
third id=$2"; echo "<end>"')"
ft_lacks "U3 multi-line: the secret is scrubbed" "$U3" "$UTOK"
ft_has "U3 multi-line: line 1 scrubbed" "$U3" "first unsafe x"
ft_has "U3 multi-line: line 2 kept" "$U3" "second clean"
ft_has "U3 multi-line: line 3 scrubbed with its key" "$U3" "third id=unsafe<end>"

# LP live_probe.sh, HERMETIC (review minor): the same script against a sandbox copy of the tree, one upstream
# pointing at the loopback fixture. Proves its leak check, per-file control needles and tool fingerprint.
lp_tree() { # DIR: a copy of scripts/forge with one upstream
  mkdir -p "$1/scripts" "$1/upstreams"
  cp -pR -- "$(dirname "$FORGE")" "$1/scripts/forge"
  printf 'export UPSTREAMABLE_REPOSITORY="%s"\n' "$U" >"$1/upstreams/x.sh"
}
lp_run() { # DIR OUT
  env -i PATH="$PATH" HOME="$FT_SBX/home" TMPDIR="$FT_SBX" FORGE_HOSTS_FILE="$FT_SBX/hosts.tsv" FORGE_TEST_ALLOW_HTTP_LOOPBACK=1 \
    FORGE_KEYS_FILE=/nonexistent FORGE_ENV_FILE=/nonexistent TEST_GITEA_TOKEN="$TOK_ENV" \
    bash "$1/scripts/forge/live_probe.sh" "$2" >"$FT_SBX/lp.out" 2>"$FT_SBX/lp.err" </dev/null
}
ft_server "$SCEN"; hosts1
lp_tree "$FT_SBX/lp1"; lp_run "$FT_SBX/lp1" "$FT_SBX/lp1/out"
ft_ok "LP1 real tool: rc 0" "$?" 0
ft_has "LP1 fingerprint names forge.sh" "$(cat "$FT_SBX/lp1/out/tool_fingerprint.txt" 2>/dev/null)" "scripts/forge/forge.sh"
ft_has "LP1 fingerprint has the sha256 of forge.sh" "$(cat "$FT_SBX/lp1/out/tool_fingerprint.txt" 2>/dev/null)" "$(sha256sum <"$FT_SBX/lp1/scripts/forge/forge.sh" | cut -c1-64)"
ft_has "LP1 leak check counted the token" "$(cat "$FT_SBX/lp1/out/leak_check.txt" 2>/dev/null)" "token values checked (all hosts, env, keys file, .env; values never printed): 1"
ft_has "LP1 PEER line recorded" "$(cat "$FT_SBX/lp1/out/x.txt" 2>/dev/null)" "PEER:"
ft_lacks "LP1 token not in any output file" "$(cat "$FT_SBX/lp1/out/"* 2>/dev/null)" "$TOK_ENV"
# LP2 a forge.sh that LEAKS (prints the token): exit 1, every output file removed
lp_tree "$FT_SBX/lp2"
# shellcheck disable=SC2016  # literal text of the stub script: it expands when the stub runs
printf '#!/usr/bin/env bash\necho "PEER: x"; echo "PROVIDER: gitea"; echo "leak ${TEST_GITEA_TOKEN:-}"; echo "RESULT: OK"\n' >"$FT_SBX/lp2/scripts/forge/forge.sh"
lp_run "$FT_SBX/lp2" "$FT_SBX/lp2/out"
ft_ok "LP2 leaking tool: rc 1" "$?" 1
ft_has "LP2 the leak is named" "$(cat "$FT_SBX/lp.err")" "LEAK: a value (or a 12-character part) of TEST_GITEA_TOKEN"
ft_ok "LP2 output files removed" "$(find "$FT_SBX/lp2/out" -type f | wc -l)" 0
# LP3 a forge.sh that prints NOTHING: the per-file control needle is missing -> blind, exit 1
lp_tree "$FT_SBX/lp3"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FT_SBX/lp3/scripts/forge/forge.sh"
lp_run "$FT_SBX/lp3" "$FT_SBX/lp3/out"
ft_ok "LP3 silent tool: rc 1" "$?" 1
ft_has "LP3 blind reported" "$(cat "$FT_SBX/lp.err")" "leak check is blind: control needle not found in x.txt"
# LP4 (review m2, W12) a forge.sh whose output holds the NEGATIVE control needle: the leak check itself is
# shown broken (a scan that "finds" a string nobody wrote would also find tokens that are not there), exit 1
lp_tree "$FT_SBX/lp4"
printf '#!/usr/bin/env bash\necho "PEER: x"; echo "PROVIDER: gitea"; echo "NO_SUCH_STRING_9f3c1e"; echo "RESULT: OK"\n' >"$FT_SBX/lp4/scripts/forge/forge.sh"
lp_run "$FT_SBX/lp4" "$FT_SBX/lp4/out"
ft_ok "LP4 negative needle present: rc 1" "$?" 1
ft_has "LP4 broken check reported" "$(cat "$FT_SBX/lp.err")" "leak check is broken: negative control matched in x.txt"
ft_server_stop

ft_done
