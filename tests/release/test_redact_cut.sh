#!/usr/bin/env bash
# tests/release/test_redact_cut.sh — unit test of the one redact-then-cut helper,
# scripts/release/redact_cut.sh (CON-234 n-4 class, round 4 structural rewrite).
#
# Class (§11.4.289(C)): unit test of a pure text filter; the inputs are fixed strings shaped like the
# messages real git and curl print (the end-to-end proof with the real git binary and the real
# tag_and_release.sh is case C25 of test_tag_and_release.sh). Every secret is a ZZ... needle that
# appears nowhere else, so "the needle is absent from the output" is a decidable oracle; every case
# that expects redaction also checks the positive needle "<redacted>" (an empty output would otherwise
# pass) and the control cases check that text without a credential is printed unchanged.
#
# Usage: bash tests/release/test_redact_cut.sh     (RC_LIB=<path> tests another copy of the helper)
# Exit 0 when every case passes, 1 when a case failed, 77 when a case was SKIPPED (round 9, F5: suite_exit of
# tests/release/env_allow.sh; RELEASE_TESTS_ALLOW_SKIP=1 makes a skip exit 0). Prints "RESULT: pass=N fail=M".
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
L="${RC_LIB:-$ROOT/scripts/release/redact_cut.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
. "$HERE/env_allow.sh"   # round 9 (F5): suite_exit and nofile_room
skipped=0; skp(){ skipped=$((skipped+1)); echo "SKIP $*"; }
# shellcheck source=scripts/release/redact_cut.sh
. "$L" || { echo "FAIL cannot source $L"; echo "RESULT: pass=0 fail=1"; exit 1; }
rc() { printf '%s' "$2" | rc_redact_cut "${3:-4000}"; }
# gone NAME INPUT NEEDLE...  : every needle is absent and "<redacted>" is present
gone() { local n="$1" in="$2" out; shift 2; out="$(rc x "$in")"
  local leak=""; for z in "$@"; do case "$out" in *"$z"*) leak="$leak $z" ;; esac; done
  if [ -n "$leak" ]; then bad "$n (leaked:$leak; output: $out)"
  elif case "$out" in *'<redacted>'*) false ;; *) true ;; esac; then bad "$n (no <redacted> marker; output: $out)"
  else ok "$n"; fi; }

# --- controls: text without a credential is untouched (negative needles) ---
chk "K1 plain text untouched" "$(rc x 'no url here ZZNEG')" 'no url here ZZNEG'
chk "K2 URL without userinfo or credential parameter untouched" "$(rc x "fatal: unable to access 'https://host.invalid/r/': Could not resolve host: host.invalid")" "fatal: unable to access 'https://host.invalid/r/': Could not resolve host: host.invalid"
chk "K3 scp-style git@host:path untouched" "$(rc x 'git@github.com:org/repo.git')" 'git@github.com:org/repo.git'
chk "K4 mail address untouched" "$(rc x 'mail user@host now')" 'mail user@host now'
chk "K5 non-credential query parameter untouched" "$(rc x 'https://h/r?page=2&sort=asc')" 'https://h/r?page=2&sort=asc'

# --- URL userinfo, any scheme, any byte in the password (H1, Q1, Q2, Q11) ---
gone "U1 basic userinfo" "fatal: 'https://u:ZZU1@h/r'" ZZU1
gone "U2 raw '/' in the password (git 2.53 prints it verbatim)" "fatal: unable to access 'https://u:ab/ZZU2@host.invalid/r/': URL rejected: Port number was not a decimal number" ZZU2
gone "U3 raw '@' in the password" "https://u:pa@ZZU3@h/r" ZZU3 pa@
gone "U4 raw space in the password" "fatal: 'https://u:ab ZZU4@h/r'" ZZU4
gone "U5 raw '?' and '#' in the password" "https://u:a?ZZU5a#ZZU5b@h/r" ZZU5a ZZU5b
gone "U6 raw quote in the password" "fatal: 'https://u:a'ZZU6@h/r'" ZZU6
gone "U7 percent-encoded password" "https://u:a%2FZZU7%40x@h/r" ZZU7
gone "U8 two URLs on one line" "a https://x:ZZU8a@h1/r b https://y:ZZU8b@h2/r" ZZU8a ZZU8b
gone "U9 colon in the user part" "https://ZZU9user:ZZU9pw@h/r" ZZU9user ZZU9pw
LONG="$(printf 'L%.0s' $(seq 1 300))"
gone "U10 userinfo longer than 64 bytes (300)" "https://u:ZZU10${LONG}@h/r" ZZU10 LLLLLLLLLL
gone "U11 ssh:// scheme" "ssh://u:ZZU11@host:22/r" ZZU11
gone "U12 git:// scheme" "git://u:ZZU12@host/r" ZZU12
gone "U13 ftp:// scheme" "ftp://u:ZZU13@host/r" ZZU13
gone "U14 svn+ssh:// scheme" "svn+ssh://u:ZZU14@host/r" ZZU14
gone "U15 http:// scheme" "http://u:ZZU15@127.0.0.1:9/none.git/" ZZU15
gone "U16 upper-case scheme" "HTTPS://u:ZZU16@h/r" ZZU16
gone "U17 user only, no password" "https://ZZU17@h/r" ZZU17
gone "U18 scheme-less user:password@host:path" "fatal: 'u:ZZU18@host:path'" ZZU18
chk "U19 the host part is kept" "$(rc x "x https://u:p@host.example/r y")" "x https://<redacted>@host.example/r y"
chk "U20 a path '@' after :// is over-redacted (by design: detail lost, never a secret)" "$(rc x 'see https://host/p@q')" 'see https://<redacted>@q'

# --- query / form parameters with a credential name, any case (H1, own mutants) ---
for p in access_token token private_token private-token key api_key apikey password passwd pwd secret client_secret sig signature auth X-Amz-Signature X-Amz-Credential X-Amz-Security-Token refresh_token id_token session jwt; do
  gone "Q-$p query value" "fatal: 'https://host.invalid/r?x=1&${p}=ZZQV$p&y=2'" "ZZQV$p"
done
gone "Q-upper Access_Token" "https://h/r?Access_Token=ZZQUP" ZZQUP
gone "Q-first parameter" "https://h/r?token=ZZQF" ZZQF
gone "Q-form outside a URL" "error: password=ZZQFORM rejected" ZZQFORM
gone "Q-fragment value" "https://h/r#access_token=ZZQFRAG" ZZQFRAG
chk "Q-other parameters kept" "$(rc x 'https://h/r?a=1&token=ZZX&b=2')" 'https://h/r?a=1&token=<redacted>&b=2'
gone "Q-two credential parameters on one line" "https://h/r?token=ZZQT1&x=1&secret=ZZQT2" ZZQT1 ZZQT2
gone "Q-two URLs each with a credential parameter" "a https://h1/r?token=ZZQU1 b https://h2/q?sig=ZZQU2" ZZQU1 ZZQU2

# --- header lines and bearer tokens (I-2: GIT_TRACE_CURL / curl -v shapes) ---
gone "A1 Authorization: Basic" "=> Send header: Authorization: Basic ZZA1" ZZA1
gone "A2 Authorization: Bearer" "> Authorization: Bearer ZZA2" ZZA2
gone "A3 authorization lower case" "authorization: token ZZA3" ZZA3
gone "A4 PRIVATE-TOKEN header" "> PRIVATE-TOKEN: ZZA4" ZZA4
gone "A5 X-Gitlab-Token header" "X-Gitlab-Token: ZZA5" ZZA5
gone "A6 X-Api-Key header" "X-Api-Key: ZZA6" ZZA6
gone "A7 Cookie header" "> Cookie: session=ZZA7" ZZA7
gone "A8 Proxy-Authorization header" "Proxy-Authorization: Basic ZZA8" ZZA8
gone "A9 bare Bearer token in prose" "server said: use Bearer ZZA9 next time" ZZA9

# --- well-known token shapes anywhere ---
gone "T1 GitHub classic token" "x ghp_ZZT1aaaaaaaaaaaaaaaaaaaaaaaaaaaa y" ZZT1
gone "T2 GitHub fine-grained token" "x github_pat_ZZT2aaaaaaaaaaaaaaaaaaaaaa y" ZZT2
gone "T3 GitLab token" "x glpat-ZZT3aaaaaaaaaaaaaaaaaa y" ZZT3

# --- locale, bytes, lines ---
out="$(printf 'https://u:\xe9ZZL1@h/r' | LC_ALL=C.UTF-8 rc_redact_cut 400)"
case "$out" in *ZZL1*) bad "L1 invalid UTF-8 byte under a UTF-8 caller locale (leaked: $out)" ;; *'<redacted>'*) ok "L1 invalid UTF-8 byte under a UTF-8 caller locale" ;; *) bad "L1 no marker ($out)" ;; esac
out="$(printf 'https://u:ZZ\000L2@h/r' | rc_redact_cut 400)"
case "$out" in *L2*) bad "L2 NUL byte in the password (leaked: $out)" ;; *'<redacted>'*) ok "L2 NUL byte in the password" ;; *) bad "L2 no marker ($out)" ;; esac
chk "L3 several lines each redacted" "$(printf 'a https://u:ZZ1@h/r\nb https://v:ZZ2@g/q\n' | rc_redact_cut 400 | tr '\n' '|')" "a https://<redacted>@h/r|b https://<redacted>@g/q|"
gone "L4 CRLF line end" "$(printf 'https://u:ZZL4@h/r\r')" ZZL4

# --- cut: redaction runs first, the byte budget holds, nothing past the budget is printed ---
chk "C1 redact first, then cut" "$(rc x 'https://SECRETUSER:SECRETPW@h/r' 12)" 'https://<red'
chk "C2 budget is exact" "$(printf 'y%.0s' $(seq 1 500) | rc_redact_cut 400 | wc -c | tr -d ' ')" 400
for off in 1990 1995 1998 2000 2003; do
  pad="$(printf 'p%.0s' $(seq 1 "$off"))"
  out="$(printf '%s https://u:ZZCUT%s@h/r' "$pad" "$off" | rc_redact_cut 2000)"
  case "$out" in *ZZCUT*|*ZZCU*|*ZZC*) bad "C3 '@' near the cut at offset $off (leaked)" ;; *) ok "C3 '@' near the cut at offset $off" ;; esac
done
big="$(printf 'q%.0s' $(seq 1 100000))"
out="$(printf '%s https://u:ZZBIG@h/r' "$big" | timeout 20 bash -c '. "$1"; rc_redact_cut 2000' _ "$L")"; brc=$?
[ "$brc" = 0 ] && ok "C4 a 100000-byte line is processed within 20 s" || bad "C4 a 100000-byte line timed out or failed (rc $brc)"
case "$out" in *ZZBIG*) bad "C5 secret at the end of a 100000-byte line (leaked)" ;; *) ok "C5 secret at the end of a 100000-byte line" ;; esac
chk "C6 a truncated flush says so" "$( { printf 'z%.0s' $(seq 1 50); printf '\n'; } | rc_redact_cut 10 mark | tail -n 1)" '(truncated: 41 more bytes not shown)'
chk "C7 an untruncated flush has no marker" "$(printf 'short\n' | rc_redact_cut 100 mark)" 'short'
chk "C8 empty input prints nothing" "$(printf '' | rc_redact_cut 100 mark | wc -c | tr -d ' ')" 0
printf 'abc' | rc_redact_cut 2>/dev/null >/dev/null; [ $? -ne 0 ] && ok "C9 a missing byte count is refused" || bad "C9 a missing byte count is refused"
printf 'abc' | rc_redact_cut 1x >/dev/null 2>&1; [ $? -ne 0 ] && ok "C10 a non-numeric byte count is refused" || bad "C10 a non-numeric byte count is refused"

# C11: the budget is in BYTES whatever the caller's locale (kills a helper that drops its own LC_ALL=C:
# under a UTF-8 locale gawk counts characters, so 400 two-byte characters would print 800 bytes)
if locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then
  n="$(printf '\303\251%.0s' $(seq 1 500) | LC_ALL=C.UTF-8 rc_redact_cut 400 | wc -c | tr -d ' ')"
  chk "C11 the byte budget holds under a UTF-8 caller locale" "$n" 400
else skp "C11 no C.UTF-8 locale on this host"; fi   # round 9 (F5): counted, so the suite exits 77
# C12: no NUL byte reaches the output (kills a helper that keeps NUL bytes)
n="$(printf 'a\000b https://u:p\000q@h/r\n' | rc_redact_cut 400 | tr -dc '\000' | wc -c | tr -d ' ')"
chk "C12 NUL bytes are dropped from the output" "$n" 0

# ---- round 5 (structural, CON-234 class): J1 rule order, J2 scan window, adopted reviewer mutants V3 V4 V5 ----
# J1: a password holding a credential word and ":" must not let the header rule (R1) eat the "@" the URL
# rule (R3) needs; the URL rules run first now. Both shapes reproduced by the round-4 review with real git.
gone "J1a password with 'token:' inside the userinfo (R1 must not run before R3)" "fatal: unable to access 'https://user:SECab/cdtoken:LEAKPARTRET@127.0.0.1:1/r.git/': URL rejected: Port number was not a decimal number" SECab LEAKPART cdtoken
gone "J1b password with 'secret: ' inside the userinfo" "fatal: unable to access 'https://user:SECx/y secret: zRET@127.0.0.1:1/r.git/': URL rejected: Malformed input" SECx zRET
chk "J1c the host after the userinfo is kept (positive needle)" "$(rc x "x https://user:SECab/cdtoken:LEAK@127.0.0.1:1/r y")" "x https://<redacted>@127.0.0.1:1/r y"
gone "J1d scheme-less user:password@host with 'token:' in the password (R4 before R1)" "fatal: 'user:SECab/cdtoken:LEAKSL@host:path'" SECab LEAKSL
# J2: a long redacted value must not pull unscanned bytes into the printed region (no scan window now:
# every rule scans the whole line; a line longer than 16384 bytes is not printed at all)
J2V="$(printf 'a%.0s' $(seq 1 4500))"
out="$(printf 'fatal: https://h/r?id_token=%s&access_token=LEAKSHRINK1 x\n' "$J2V" | rc_redact_cut 400)"
case "$out" in *LEAKSHRINK1*) bad "J2a a 4500-byte credential value does not let the next parameter through (leaked)" ;;
  *'access_token=<redacted>'*) ok "J2a a 4500-byte credential value does not let the next parameter through" ;; *) bad "J2a no marker ($out)" ;; esac
J2W="$(printf 'b%.0s' $(seq 1 12000))"
out="$(printf 'x https://h/r?token=%s&secret=LEAKSHRINK2 ghp_LEAKSHRINK3aaaaaaaaaaaaaaaaaaaaa\n' "$J2W" | rc_redact_cut 400)"
case "$out" in *LEAKSHRINK2*|*LEAKSHRINK3*) bad "J2b 12000-byte value, second parameter and token shape (leaked)" ;; *'secret=<redacted>'*) ok "J2b 12000-byte value, second parameter and token shape" ;; *) bad "J2b no marker ($out)" ;; esac
LMX="$(printf 'c%.0s' $(seq 1 16400))"
chk "J2c a line longer than 16384 bytes is not printed, only its length" "$(printf '%s ZZJ2C\n' "$LMX" | rc_redact_cut 400)" "(a line of 16406 bytes is not shown: longer than 16384 bytes)"
LM16="$(printf 'd%.0s' $(seq 1 16378))"
n="$(printf '%s ZZJ2D\n' "$LM16" | rc_redact_cut 20000 | wc -c | tr -d ' ')"
chk "J2d a line of exactly 16384 bytes is still printed (boundary)" "$n" 16385
gone "V3 Cookie header with a non-credential cookie name" "> Cookie: sid=ZZV3COOKIE; theme=dark" ZZV3COOKIE
chk "V4 a token shape straddling the cut prints no prefix of it" "$(printf '%s ghp_ZZSTRADDLEaaaaaaaaaaaaaaaaaaaaaaaa\n' "$(printf 'x%.0s' $(seq 1 30))" | rc_redact_cut 40)" "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx <redacted"
gone "V5 Bearer followed by a TAB" "$(printf 'server said: Bearer\tZZV5TAB now')" ZZV5TAB

# ---- round 5: the primary control. rc_err_class turns a network command's stderr into ONE word of a
# closed set; no byte of the input can reach its output (its awk program prints literals only) ----
CLS='^(no-message|timeout|url-invalid|tls-error|auth-failed|ref-error|repository-not-found|rejected-non-fast-forward|remote-rejected|rejected|network-unreachable|unknown)$'
ec() { printf '%s' "$1" | rc_err_class; }
chk "E1 real git: raw '/' in the password" "$(ec "fatal: unable to access 'https://u:ab/ZZE1@host.invalid/r/': URL rejected: Port number was not a decimal number between 0 and 65535")" url-invalid
chk "E2 real git: unknown host" "$(ec "fatal: unable to access 'https://host.invalid/r?access_token=ZZE2&x=1/': Could not resolve host: host.invalid")" network-unreachable
chk "E3 real git: missing local repository" "$(ec "$(printf "fatal: '/x/missing.git' does not appear to be a git repository\nfatal: Could not read from remote repository.\n")")" repository-not-found
chk "E4 real git: connection refused" "$(ec "fatal: unable to access 'http://127.0.0.1:1/r.git/': Failed to connect to 127.0.0.1 port 1 after 0 ms: Could not connect to server")" network-unreachable
chk "E5 HTTP 403" "$(ec "fatal: unable to access 'https://h/r/': The requested URL returned error: 403")" auth-failed
chk "E6 authentication failed" "$(ec "remote: Invalid username or password.
fatal: Authentication failed for 'https://h/r/'")" auth-failed
chk "E7 hook declined, the deciding phrase on the LAST line (multi-line input, V11 class)" "$(ec "$(printf 'remote: rejected by test hook\nTo /x/r2.git\n ! [remote rejected] main -> main (hook declined)\nerror: failed to push some refs\n')")" remote-rejected
chk "E8 non-fast-forward" "$(ec ' ! [rejected]        main -> main (non-fast-forward)')" rejected-non-fast-forward
chk "E9 empty input" "$(ec '')" no-message
chk "E10 text with no known phrase" "$(ec 'fatal: something ZZE10 odd')" unknown
chk "E11 TLS" "$(ec "fatal: unable to access 'https://h/': SSL certificate problem: unable to get local issuer certificate")" tls-error
chk "E12 remote ref" "$(ec "fatal: couldn't find remote ref refs/heads/main")" ref-error
LONGE="$(printf 'y%.0s' $(seq 1 5000))"
chk "E13 the deciding phrase after 5000 bytes is still seen" "$(ec "$LONGE Could not resolve host: h")" network-unreachable
chk "E14 upper case phrase" "$(ec 'FATAL: COULD NOT RESOLVE HOST: H')" network-unreachable
# E15: whatever the input, the output is exactly one word of the closed set and holds no input byte
fz=0
for z in "https://u:ZZFZ1@h/x" "$(printf 'ZZFZ2\nZZFZ2b')" "Authorization: Bearer ZZFZ3" "ZZFZ4 port number" "$(printf '\001\002ZZFZ5\377')" "ZZFZ6 $(printf 'q%.0s' $(seq 1 20000))" "remote rejected ZZFZ7"; do
  o="$(ec "$z")"; printf '%s\n' "$o" | grep -Eq "$CLS" || { fz=1; echo "  E15 out of set: $o"; }
  case "$o" in *ZZFZ*) fz=1; echo "  E15 input byte in the output: $o" ;; esac
  [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] || { fz=1; echo "  E15 not one line: $o"; }
done
[ "$fz" = 0 ] && ok "E15 seven hostile inputs: one closed-set word each, no input byte" || bad "E15 seven hostile inputs: one closed-set word each, no input byte"
# E16 a NUL byte and a UTF-8 caller locale do not change the class
chk "E16 NUL bytes and a UTF-8 caller locale" "$(printf 'could not re\000solve host' | LC_ALL=C.UTF-8 rc_err_class)" network-unreachable

# ---- round 5: rc_safe_url prints scheme://host[:port] only, never userinfo, a path or a query ----
chk "W1 https with path and query" "$(rc_safe_url 'https://git.example.org:3000/o/r?token=ZZW1')" 'https://git.example.org:3000'
chk "W2 userinfo is never printed" "$(rc_safe_url 'https://u:ZZW2@h/r')" '<url not shown>'
chk "W3 user only" "$(rc_safe_url 'https://ZZW3@h/r')" '<url not shown>'
chk "W4 plain host" "$(rc_safe_url 'http://127.0.0.1:8080')" 'http://127.0.0.1:8080'
chk "W5 IPv6 literal" "$(rc_safe_url 'http://[::1]:3000/x')" 'http://[::1]:3000'
chk "W6 not a URL" "$(rc_safe_url 'u:ZZW6@host:path')" '<url not shown>'
chk "W7 a raw '/' password (git verbatim shape)" "$(rc_safe_url 'https://u:ab/ZZW7@host.invalid/r')" '<url not shown>'
chk "W8 empty" "$(rc_safe_url '')" '<url not shown>'

# ---- round 5: rc_git_env removes every caller trace switch and forces redaction and no prompt ----
out="$(env GIT_TRACE=1 GIT_TRACE_CURL=/x GIT_CURL_VERBOSE=1 GIT_TRACE_PACKET=1 GIT_TRACE_REDACT=0 GIT_TRACE2_EVENT=/y GIT_TERMINAL_PROMPT=1 bash -c '. "$1"; rc_git_env; env | grep -E "^GIT_(TRACE|CURL_VERBOSE|TERMINAL_PROMPT)" | sort | tr "\n" " "' _ "$L")"
chk "G1 trace switches removed, redaction forced, prompts off, trace2 disabled" "$out" "GIT_TERMINAL_PROMPT=0 GIT_TRACE2=0 GIT_TRACE2_EVENT=0 GIT_TRACE2_PERF=0 GIT_TRACE_REDACT=1 "

# ---- round 6 ----
# N1 (backup layer only; no script routes these shapes through it, so these cases test the backup, not a reached path)
gone "N1a percent-encoded =" 'GET /x?access_token%3DZZN1A&b=1' ZZN1A
gone "N1b spaced PASSWORD = X" 'PASSWORD = ZZN1B rest' ZZN1B
gone "N1c JSON token" '{"token":"ZZN1C","a":1}' ZZN1C
gone "N1d JSON password, spaced colon" '{"password" : "ZZN1D"}' ZZN1D
chk "N1e JSON control (no credential key)" "$(rc x '{"name":"plain","a":1}')" '{"name":"plain","a":1}'
chk "N1f spaced control (no credential key)" "$(rc x 'COLOR = blue')" 'COLOR = blue'
# K1: rc_url_has_userinfo — refuse every URL that carries a user name or password (0 = has userinfo)
ui(){ if rc_url_has_userinfo "$2"; then r=refuse; else r=allow; fi; chk "K1 $1: $2" "$r" "$3"; }
ui https-userpass 'https://u:ZZK1@h.invalid/r' refuse
ui https-user-only 'https://ghp_ZZK1TOKEN@h.invalid/r' refuse
ui http-userpass 'http://u:ZZK1@h.invalid/r' refuse
ui upper-scheme 'HTTPS://u:ZZK1@h.invalid/r' refuse
ui ftp 'ftp://u@h.invalid/r' refuse
ui ssh-userpass 'ssh://u:ZZK1@h.invalid/r' refuse
ui ssh-pct3a 'ssh://u%3AZZK1@h.invalid/r' refuse
ui scp-userpass 'u:ZZK1@h.invalid:r.git' refuse
ui ssh-user-only 'ssh://git@h.invalid/r' allow
ui scp-user-only 'git@h.invalid:r.git' allow
ui https-plain 'https://h.invalid/r' allow
ui at-in-path 'https://h.invalid/a@b' allow
ui local-abs '/srv/repo.git' allow
ui local-rel './repo@x' allow
ui file-url 'file:///srv/r.git' allow
# K12 (CON-423 review r1, M8): rc_gitea_token_shape_ok, the one definition of the gitea token shape the publisher
# refuses on and the tag script's dry run reports TOKEN-SHAPE on: 8 to 200 characters of [A-Za-z0-9._~+/=-]
if declare -F rc_gitea_token_shape_ok >/dev/null; then
  ts(){ if rc_gitea_token_shape_ok "$2"; then r=fits; else r=refused; fi; chk "K12 $1" "$r" "$3"; }
  ts "8 characters (the shortest)" 'abcd1234' fits
  ts "200 characters (the longest)" "$(printf 'a%.0s' $(seq 200))" fits
  ts "every allowed punctuation" 'aA0._~+/=-' fits
  ts "7 characters" 'abc1234' refused
  ts "201 characters" "$(printf 'a%.0s' $(seq 201))" refused
  ts "a space inside" 'abcd 1234' refused
  ts "a percent sign" 'abcd%1234' refused
  ts "a non-ASCII letter" $'abcd\u00e91234' refused
  ts "a trailing newline" $'abcd1234\n' refused
  ts "empty" '' refused
else bad "K12 rc_gitea_token_shape_ok is not defined by the library under test"; fi
# K3: rc_env_lockdown keeps only the allow-list (plus RELEASE_ENV_KEEP) in the environment of children, keeps the
# values in this shell, un-exports functions and refuses credential-like names in RELEASE_ENV_KEEP
out="$(env -i PATH="$PATH" HOME=/h ZZK3_TOKEN=a XYZ=b GH_TOKEN=c KEEPME=d RELEASE_ENV_KEEP="KEEPME GH_TOKEN bad-name" bash -c '
  f(){ :; }; export -f f; . "$1"; rc_env_lockdown
  printf "child:"; env | cut -d= -f1 | grep -v "^_$" | sort | tr "\n" " "
  printf "shell:%s %s fn:" "$XYZ" "$ZZK3_TOKEN"; bash -c "type f >/dev/null 2>&1 && echo f || echo none"' _ "$L")"
case "$out" in *"child:"*) ok "K3 lockdown census ran (control needle)" ;; *) bad "K3 lockdown census: $out" ;; esac
case "$out" in *" HOME "*|*":HOME "*) ok "K3 allow-listed HOME kept" ;; *) bad "K3 HOME dropped: $out" ;; esac
case "$out" in *"KEEPME"*) ok "K3 RELEASE_ENV_KEEP name kept" ;; *) bad "K3 KEEPME dropped: $out" ;; esac
case "$out" in *"child:"*ZZK3_TOKEN*"shell:"*|*"child:"*GH_TOKEN*"shell:"*|*"child:"*" XYZ "*"shell:"*) bad "K3 a non-listed or credential-like name reaches children: $out" ;; *) ok "K3 non-listed and credential-like names do not reach children (GH_TOKEN refused even when in RELEASE_ENV_KEEP)" ;; esac
case "$out" in *"shell:b a"*) ok "K3 the shell keeps the values" ;; *) bad "K3 values lost in the shell: $out" ;; esac
case "$out" in *"fn:none"*) ok "K3 exported functions are un-exported" ;; *) bad "K3 exported function reaches children: $out" ;; esac
# round 6 (X12 class): the publisher's holding variable _rpg_tok (and any *TOK* name) cannot be kept exported
out="$(env -i PATH="$PATH" HOME=/h _rpg_tok=ZZRPG MYTOK=ZZMT KEEPME=d RELEASE_ENV_KEEP="_rpg_tok MYTOK KEEPME" bash -c '. "$1"; rc_env_lockdown; env' _ "$L")"
case "$out" in *KEEPME=d*) ok "K3 _rpg_tok: the census sees a kept name (control needle)" ;; *) bad "K3 _rpg_tok: census blind: $out" ;; esac
case "$out" in *ZZRPG*|*ZZMT*) bad "K3 _rpg_tok: RELEASE_ENV_KEEP keeps a *TOK* name exported" ;; *) ok "K3 _rpg_tok: RELEASE_ENV_KEEP refuses _rpg_tok and MYTOK" ;; esac

# ---- round 7 (L1 L2): rc_env_clean builds the environment of every child positively ----
# A probe script sources the helper, runs rc_env_clean READS, and reports its status, its argv[0], the number of
# entries in its own start environment (/proc/$$/environ), the names a child (env) receives, the READS values in
# the shell, and whether fd 9 (the state pipe) is still open. Every value is a ZZ marker.
K6="$(mktemp -d "${TMPDIR:-/tmp}/k6.XXXXXX")"; : "${K6:?}"
mkprobe() { # mkprobe FILE READS [EXTRA-LINE]
  printf '#!/usr/bin/env bash\n. %q\n%s\nrc_env_clean %q "$@"; r=$?\nprintf "rc=%%s\\n" "$r"\nprintf "a0=%%s\\n" "$(tr "\\0" "\\n" </proc/$$/cmdline | head -n 1)"\nprintf "envn=%%s\\n" "$(tr "\\0" "\\n" </proc/$$/environ | grep -c .)"\nprintf "child:%%s\\n" "$(env | cut -d= -f1 | sort | tr "\\n" " ")"\nprintf "zzread=%%s zzs=%%s\\n" "${ZZREAD-unset}" "${ZZS-unset}"\n[ -e /proc/$$/fd/9 ] && echo fd9=open || echo fd9=closed\n' "$L" "${3:-}" "$2" >"$1"; }
mkprobe "$K6/p.sh" ZZREAD
o6="$(env -i PATH="$PATH" HOME=/h ZZREAD=ZZR6 ZZPLAIN=ZZP6 'BAD-NAME=ZZB6' 'npm_config_//h/:_authToken=ZZN6' timeout 30 bash "$K6/p.sh" 2>&1)"
case "$o6" in *"rc=0"*"a0=rc-clean-env"*"envn=0"*) ok "K6 the script re-executes itself with an empty environment (argv[0] rc-clean-env, environ empty)" ;; *) bad "K6 re-execution: $o6" ;; esac
case "$o6" in *"child:"*" HOME "*|*"child:HOME "*) ok "K6 an allow-listed name reaches a child (control needle)" ;; *) bad "K6 HOME does not reach a child: $o6" ;; esac
case "$(printf '%s\n' "$o6" | grep '^child:')" in *ZZREAD*|*ZZPLAIN*|*BAD-NAME*|*npm_config*) bad "K6 a name outside the allow-list reaches a child: $o6" ;; *) ok "K6 no READS name, plain variable or non-identifier entry reaches a child" ;; esac
case "$o6" in *"zzread=ZZR6 zzs=unset"*) ok "K6 the READS value is kept in the shell" ;; *) bad "K6 READS value lost: $o6" ;; esac
case "$o6" in *fd9=closed*) ok "K6 the state pipe (fd 9) is closed before any child runs" ;; *) bad "K6 fd 9 left open: $o6" ;; esac
o6="$(env -i PATH="$PATH" HOME=/h ZZREAD=ZZR6 ZZPLAIN=ZZP6 SHELLOPTS=allexport timeout 30 bash "$K6/p.sh" 2>&1)"
c6="$(printf '%s\n' "$o6" | grep '^child:')"
case "$c6" in child:*HOME*) case "$c6" in *ZZ*) bad "K6 allexport: a caller value reaches a child: $o6" ;; *) ok "K6 an inherited allexport (SHELLOPTS) does not cross the re-execution" ;; esac ;; *) bad "K6 allexport: census blind: $o6" ;; esac
# a marker argv[0] with a non-empty environment is not "clean" (W3), and a process that already carries the marker
# never re-executes again (round 8, N2 loop guard): status 4, the caller exits
o6="$(env -i PATH="$PATH" HOME=/h ZZPLAIN=ZZP6 timeout 30 bash -c 'exec -a rc-clean-env bash "$1"' _ "$K6/p.sh" 2>&1)"
case "$o6" in *"rc=4"*) ok "K6 marker with a dirty environment: refused with status 4 (never taken as clean, never re-executed again)" ;; *) bad "K6 marker with a dirty environment was taken as clean or re-executed: $o6" ;; esac
# records on fd 9 are decided again: an "e" record outside the allow-list is not exported (W5), an "s" record whose
# name is not in READS is not set (W4), an "s" READS record is set and not exported
printf 'e\0PATH\0%s\0e\0ZZINJ\0ZZI6\0s\0ZZS\0ZZS6\0s\0ZZREAD\0ZZR6B\0s\0RELEASE_ENV_KEEP\0\0' "$PATH" >"$K6/recs"
o6="$(env -i timeout 30 bash -c 'exec -c -a rc-clean-env bash "$1" 9<"$2"' _ "$K6/p.sh" "$K6/recs" 2>&1)"
case "$o6" in *"rc=0"*"child:"*PATH*) ok "K6 injected records: the PATH record is restored (control needle)" ;; *) bad "K6 injected records: $o6" ;; esac
case "$(printf '%s\n' "$o6" | grep '^child:')" in *ZZINJ*) bad "K6 an injected e record outside the allow-list is exported" ;; *) ok "K6 an injected e record outside the allow-list is not exported (rc_env_lockdown decides again)" ;; esac
case "$o6" in *"zzread=ZZR6B zzs=unset"*) ok "K6 an s record is set only for a READS name" ;; *) bad "K6 s records: $o6" ;; esac
# statuses: 2 for a READS name bash gives a meaning of its own or that is not an identifier, 3 blind, 4 no script file
mkprobe "$K6/p2.sh" BASH_ENV; o6="$(env -i PATH="$PATH" timeout 30 bash "$K6/p2.sh" 2>&1)"
case "$o6" in *"rc=2"*) ok "K6 READS BASH_ENV: status 2" ;; *) bad "K6 READS BASH_ENV: $o6" ;; esac
mkprobe "$K6/p3.sh" 'A-B'; o6="$(env -i PATH="$PATH" timeout 30 bash "$K6/p3.sh" 2>&1)"
case "$o6" in *"rc=2"*) ok "K6 READS not an identifier: status 2" ;; *) bad "K6 READS not an identifier: $o6" ;; esac
mkprobe "$K6/p4.sh" ZZREAD '_rc_env_state() { _RC_ENV_STATE=blind; }'; o6="$(env -i PATH="$PATH" timeout 30 bash "$K6/p4.sh" 2>&1)"
case "$o6" in *"rc=3"*) ok "K6 /proc unreadable (blind): status 3, no re-execution" ;; *) bad "K6 blind: $o6" ;; esac
o6="$(env -i PATH="$PATH" bash -c '. "$1"; rc_env_clean ""; echo "rc=$?"' "$K6/no-such-script" "$L" 2>&1)"
case "$o6" in *"rc=4"*) ok "K6 the script path is not a file: status 4" ;; *) bad "K6 no script file: $o6" ;; esac
# _rc_env_state on prepared directories (clean, dirty, blind)
mkdir -p "$K6/s1" "$K6/s2" "$K6/s3"; printf 'rc-clean-env\0x\0' >"$K6/s1/cmdline"; : >"$K6/s1/environ"
printf 'rc-clean-env\0' >"$K6/s2/cmdline"; printf 'A=1\0' >"$K6/s2/environ"; printf 'bash\0' >"$K6/s3/cmdline"
_rc_env_state "$K6/s1"; a="$_RC_ENV_STATE"; _rc_env_state "$K6/s2"; b="$_RC_ENV_STATE"; _rc_env_state "$K6/s3"; c="$_RC_ENV_STATE"
chk "K6 _rc_env_state: clean / dirty / blind" "$a $b $c" "clean dirty blind"
# ---- round 8 (N1-N4 of the round-7 review) ----
# N3: every descriptor above 2 that the re-executed process inherited (the process-substitution pipe of the exec,
# fd 63, and any descriptor of the caller) is closed before a child runs. fds.py lists the inheritable descriptors
# above 2 of the process that runs it; control needle: it lists a descriptor a plain caller passes.
printf 'import os\nfds = []\nfor x in os.listdir("/proc/self/fd"):\n    f = int(x)\n    try:\n        if f > 2 and os.get_inheritable(f):\n            fds.append(f)\n    except OSError:\n        pass\nprint(" ".join(str(f) for f in sorted(fds)))\n' >"$K6/fds.py"
chk "K8 fds.py sees a passed descriptor (control needle)" "$(python3 -I "$K6/fds.py" 7</dev/null)" 7
printf 'printf "childfds=%%s\\n" "$(python3 -I %q)"\n' "$K6/fds.py" >>"$K6/p.sh"
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/p.sh" 7</dev/null 2>&1)"
case "$o8" in *"rc=0"*"childfds="*) ok "K8 N3 probe ran (control needle)" ;; *) bad "K8 N3 probe: $o8" ;; esac
case "$(printf '%s\n' "$o8" | grep '^childfds=')" in "childfds=") ok "K8 N3 no descriptor above 2 reaches a child (fd 63 of the exec and the caller's fd 7 are closed)" ;; *) bad "K8 N3 inherited descriptors reach a child: $(printf '%s\n' "$o8" | grep '^childfds=')" ;; esac
# N2: the loop guard. A state check that never reads "clean" (a broken check) must end with status 4 on the
# second pass, never re-execute without end; the probe runs under timeout 30 (status 124 = an endless loop)
mkprobe "$K6/p5.sh" ZZREAD '_rc_env_state() { _RC_ENV_STATE=dirty; }'
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/p5.sh" 2>&1)"; r8=$?
case "$r8:$o8" in 0:*"rc=4"*"a0=rc-clean-env"*) ok "K8 N2 a marked process that is not clean refuses (status 4) instead of re-executing again" ;; *) bad "K8 N2 loop guard: rc $r8 ($(printf '%s\n' "$o8" | head -n 2 | tr '\n' ' '))" ;; esac
# N4: a release script sourced by another script refuses (status 4): $0 is then the sourcing script, which must
# never be re-executed; the wrapper prints its marker once
printf '#!/usr/bin/env bash\necho WRAPPER-RAN\n. %q\n' "$K6/p.sh" >"$K6/w.sh"
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/w.sh" 2>&1)"
chk "K8 N4 sourced: the wrapper runs once" "$(printf '%s\n' "$o8" | grep -c '^WRAPPER-RAN$')" 1
case "$o8" in *"rc=4"*) ok "K8 N4 sourced: rc_env_clean refuses with status 4" ;; *) bad "K8 N4 sourced: $o8" ;; esac
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/p.sh" 2>&1)"
case "$o8" in *"rc=0"*) ok "K8 N4 the same probe run directly is accepted (control)" ;; *) bad "K8 N4 control: $o8" ;; esac
# N1: the allow-list holds the thirteen locale category names, never a prefix, and every allow-listed value must
# have the shape its name is meant to hold. LC_ZZTOKEN (no locale category) and LC_MESSAGES holding a URL with a
# user name and password are dropped; LC_TIME and LANG with locale values are kept (control needles).
out="$(env -i PATH="$PATH" HOME=/h LC_ZZTOKEN=ZZLCT8 LC_GITLAB_TOKEN=ZZLCG8 LC_TIME=C LANG=C.UTF-8 'LC_MESSAGES=https://u:ZZLCV8@h.invalid/' \
  TZ=Europe/Belgrade GH_HOST='u:ZZGH8@github.example.com' GITLAB_HOST=gitlab.example.com SSH_AUTH_SOCK=/nonexistent.sock 'LC_PAPER=a4 ZZLCP8' \
  GIT_SSH_VARIANT='ssh;ZZVAR8' TERM=$'xterm\nZZTERM8' bash -c '. "$1"; rc_env_lockdown; env' _ "$L")"
for n in 'LC_TIME=C' 'LANG=C.UTF-8' 'TZ=Europe/Belgrade' 'GITLAB_HOST=gitlab.example.com'; do
  case "$out" in *"$n"*) ok "K8 N1 kept: $n (control needle)" ;; *) bad "K8 N1 dropped although well-shaped: $n" ;; esac; done
for m in ZZLCT8 ZZLCG8 ZZLCV8 ZZLCP8 ZZGH8 SSH_AUTH_SOCK ZZVAR8 ZZTERM8; do
  case "$out" in *"$m"*) bad "K8 N1 not dropped: $m" ;; *) ok "K8 N1 dropped: $m" ;; esac; done
# the same through the re-execution: a child of the clean process
o8="$(env -i PATH="$PATH" HOME=/h LC_ZZTOKEN=ZZLCT8 LC_TIME=C 'LC_MESSAGES=https://u:ZZLCV8@h.invalid/' timeout 30 bash "$K6/p.sh" 2>&1)"
case "$(printf '%s\n' "$o8" | grep '^child:')" in *LC_TIME*) case "$o8" in *LC_ZZTOKEN*|*LC_MESSAGES*) bad "K8 N1 re-execution: a non-category LC_ name or a badly shaped locale value reaches a child: $o8" ;; *) ok "K8 N1 re-execution: LC_TIME reaches a child, LC_ZZTOKEN and the badly shaped LC_MESSAGES do not" ;; esac ;; *) bad "K8 N1 re-execution: census blind: $o8" ;; esac
# the class table of every allow-listed name (env_census.py classes): every credential-shaped value is dropped, every
# good value kept, no name prefix, every name classified by the test's own copy of the classes
o8="$(python3 -I "$HERE/env_census.py" classes "$L" 2>&1)"; r8=$?
case "$r8:$o8" in 0:*"CLASSES names="*" findings=0"*) ok "K8 N1 class table: every allow-listed name drops URL user information, token shapes and control characters ($(printf '%s\n' "$o8" | tail -n 1))" ;; *) bad "K8 N1 class table: rc $r8 $(printf '%s\n' "$o8" | grep -v '^CLASS .* ok$' | head -n 4 | tr '\n' ' ')" ;; esac
# ---- round 9 (F1 F2 of the round-8 review): EVERY inherited descriptor above 2 except fd 9 is closed, whatever the
# number of digits (round 8 skipped numbers of five or more digits, so fd 10000 reached every child). Descriptors of
# 1, 3, 5 and 6 digits are passed; control needle: fds.py lists all four when they are passed to it directly.
if nofile_room; then
  chk "K9 F2 fds.py sees descriptors of 1, 3, 5 and 6 digits (control needle)" "$(python3 -I "$K6/fds.py" 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null)" "7 300 12345 100000"
  o9="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/p.sh" 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null 2>&1)"
  case "$o9" in *"rc=0"*"childfds="*) ok "K9 F1 probe ran (control needle)" ;; *) bad "K9 F1 probe: $o9" ;; esac
  case "$(printf '%s\n' "$o9" | grep '^childfds=')" in "childfds=") ok "K9 F1 no descriptor of 1, 3, 5 or 6 digits reaches a child (7, 300, 12345, 100000 closed)" ;; *) bad "K9 F1 inherited descriptors reach a child: $(printf '%s\n' "$o9" | grep '^childfds=')" ;; esac
else skp "K9 F1 F2 descriptors of 5 and 6 digits: $NOFILE_WHY"; fi
# the decision of _rc_env_closefds on a prepared directory (round 9: it takes the /proc/PID directory as its argument):
# a descriptor whose flags cannot be read is closed (fail closed), one with close-on-exec is kept, one without is
# closed, fd 9 is kept; a directory that cannot be listed is status 1 (rc_env_clean then refuses with status 3)
mkdir -p "$K6/pfd/fd" "$K6/pfd/fdinfo"
for f in 9 71 72 73; do : >"$K6/pfd/fd/$f"; done
printf 'pos:\t0\nflags:\t02100000\n' >"$K6/pfd/fdinfo/72"; printf 'pos:\t0\nflags:\t0100000\n' >"$K6/pfd/fdinfo/73"
printf 'pos:\t0\nflags:\t0100000\n' >"$K6/pfd/fdinfo/9"
o9="$( exec 9</dev/null 71</dev/null 72</dev/null 73</dev/null; _rc_env_closefds "$K6/pfd"; r=$?
  for f in 9 71 72 73; do [ -e "/proc/$BASHPID/fd/$f" ] && printf '%s=open ' "$f" || printf '%s=closed ' "$f"; done; printf 'rc=%s' "$r" )"
chk "K9 F1 _rc_env_closefds decisions: fd 9 kept, flags unreadable closed, close-on-exec kept, inheritable closed" "$o9" "9=open 71=closed 72=open 73=closed rc=0"
_rc_env_closefds "$K6/no-such-proc-dir"; chk "K9 F1 _rc_env_closefds on a directory that cannot be listed: status 1" "$?" 1
mkprobe "$K6/p6.sh" ZZREAD '_rc_env_closefds() { return 1; }'; o9="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$K6/p6.sh" 2>&1)"
case "$o9" in *"rc=3"*) ok "K9 F1 descriptors that cannot be listed: rc_env_clean refuses with status 3" ;; *) bad "K9 F1 descriptors that cannot be listed: $o9" ;; esac

# ---- round 9 (F3 F4 of the round-8 review): each token shape, each control character, the 4096-byte cap, a socket
# against a regular file, and ":" and "/" in a locale value, pinned one by one on _rc_env_shape_ok (keep = passed on)
sh9() { if _rc_env_shape_ok "$2" "$3"; then r=keep; else r=drop; fi; chk "K9 $1: $2" "$r" "$4"; }
Z20=ZZZZZZZZZZZZZZZZZZZZ
for t in ghp_ gho_ ghu_ ghs_ ghr_ github_pat_ glpat- GHS_ GLPAT-; do
  sh9 "F3 token shape $t in a locale value" LC_TIME "$t$Z20$Z20" drop
  sh9 "F3 token shape $t in PATH" PATH "/usr/bin:/x/$t$Z20$Z20" drop
  sh9 "F3 token shape $t in USER" USER "$t$Z20" drop
done
sh9 "F3 control: a locale word with gh_ but no token shape is kept" LC_TIME "gh_GH.UTF-8" keep
for c in 01 07 09 0d 1b 7f; do
  x="$(printf "\\x$c")"
  sh9 "F4 control character 0x$c in PATH" PATH "/usr/bin${x}/x" drop
  sh9 "F4 control character 0x$c in GIT_SSH_COMMAND" GIT_SSH_COMMAND "ssh -o BatchMode=yes${x}" drop
done
P4096="/$(printf 'a%.0s' $(seq 1 4095))"; P4097="/$(printf 'a%.0s' $(seq 1 4096))"
sh9 "F4 a PATH of exactly 4096 bytes is kept (boundary)" PATH "$P4096" keep
sh9 "F4 a PATH of 4097 bytes is dropped" PATH "$P4097" drop
sh9 "F4 a GIT_SSH_COMMAND of 4097 bytes is dropped" GIT_SSH_COMMAND "$P4097" drop
( cd "$K6" && python3 -I -c 'import socket; socket.socket(socket.AF_UNIX).bind("s9.sock")' ) 2>/dev/null
if [ -S "$K6/s9.sock" ]; then sh9 "F4 SSH_AUTH_SOCK naming a socket is kept (control needle)" SSH_AUTH_SOCK "$K6/s9.sock" keep
else bad "K9 F4 the control socket could not be made"; fi
: >"$K6/regular9"; sh9 "F4 SSH_AUTH_SOCK naming a regular file is dropped" SSH_AUTH_SOCK "$K6/regular9" drop
sh9 "F4 SSH_AUTH_SOCK naming a directory is dropped" SSH_AUTH_SOCK "$K6" drop
for n in LANG LC_ALL LC_TIME LC_MESSAGES; do
  sh9 "F4 user information with no scheme in a locale value" "$n" "u:ZZPW9@host" drop
  sh9 "F4 a ':' in a locale value" "$n" "C:UTF-8" drop
  sh9 "F4 a '/' in a locale value" "$n" "en_US/x" drop
  sh9 "F4 a locale value is kept (control needle)" "$n" "sr_RS.UTF-8@latin" keep
done

# ---- round 9 (F7 of the round-8 review): RELEASE_ENV_KEEP never passes on a git configuration channel or a name
# bash gives a meaning of its own, and the values of its names get the common checks (no URL user information, no
# token shape, no control character, at most 4096 bytes); a *_URL or *_URI name is refused by name even with a
# value that passes the common checks; control needle: a plain name with a path value is kept
out="$(env -i PATH="$PATH" HOME=/h KEEPME=/srv/x GIT_CONFIG_PARAMETERS="'http.extraheader'='Authorization: Bearer ZZGCP9'" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0=ZZGCV9 DATABASE_URL=postgres://u:ZZDBU9@h/db \
  MYVAL=ghp_ZZTOK9ZZZZZZZZZZZZZZZZZZZZ MYNL=$'a\nZZNL9' PS4=+ZZPS49 CDPATH=/zzcd9 API_URL=https://zzurl9.example/x API_URI=zzuri9:x \
  RELEASE_ENV_KEEP="KEEPME GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 DATABASE_URL MYVAL MYNL PS4 CDPATH API_URL API_URI" \
  bash -c '. "$1"; rc_env_lockdown; env' _ "$L")"
case "$out" in *KEEPME=/srv/x*) ok "K9 F7 a RELEASE_ENV_KEEP name with a plain value is kept (control needle)" ;; *) bad "K9 F7 census blind: $out" ;; esac
for m in GIT_CONFIG_PARAMETERS ZZGCP9 GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 ZZGCV9 ZZDBU9 ZZTOK9 ZZNL9 ZZPS49 zzcd9 zzurl9 zzuri9; do
  case "$out" in *"$m"*) bad "K9 F7 RELEASE_ENV_KEEP passes on: $m" ;; *) ok "K9 F7 RELEASE_ENV_KEEP does not pass on: $m" ;; esac; done

# ---- round 10 (R9-1, R9-3, R9-4, N2 of the round-9 review) ----
# kenv: run rc_env_lockdown in a clean shell with the given environment and print the names (only) of the
# environment a child receives, one per line; "NAME=" is searched in the output, so a value never decides a case
kenv() { env -i PATH="$PATH" "$@" bash -c '. "$1"; rc_env_lockdown; env | cut -d= -f1' _ "$L"; }
gonename() { # gonename LABEL OUT NAME...: every NAME is absent from OUT (a list of names)
  local lab="$1" o="$2" n; shift 2
  for n in "$@"; do case $'\n'"$o"$'\n' in *$'\n'"$n"$'\n'*) bad "$lab passes on: $n" ;; *) ok "$lab does not pass on: $n" ;; esac; done; }
keptname() { local lab="$1" o="$2" n; shift 2   # control needles: every NAME is present
  for n in "$@"; do case $'\n'"$o"$'\n' in *$'\n'"$n"$'\n'*) ok "$lab keeps: $n (control needle)" ;; *) bad "$lab census blind or over-refusing: $n missing" ;; esac; done; }
# R9-3: one RELEASE_ENV_KEEP name per refused prefix, each with a value that passes the common checks (so only the
# name decides), and control names that only contain such a prefix later in the name (they are kept)
P10="GIT_ZZX10 SSH_ZZX10 CURL_ZZX10 GH_ZZX10 GLAB_ZZX10 GITLAB_ZZX10 LD_ZZX10 ZZX10_URL ZZX10_URI zzx10_url"
o10="$(kenv HOME=/h KEEPME=/srv/x XGIT_ZZ10=/srv/a XLC_ZZ10=/srv/b MYLANG10=/srv/c GIT_ZZX10=/srv/g SSH_ZZX10=/srv/s CURL_ZZX10=/srv/c \
  GH_ZZX10=/srv/h GLAB_ZZX10=/srv/l GITLAB_ZZX10=/srv/t LD_ZZX10=/srv/d ZZX10_URL=/srv/u ZZX10_URI=/srv/i zzx10_url=/srv/w \
  RELEASE_ENV_KEEP="KEEPME XGIT_ZZ10 XLC_ZZ10 MYLANG10 $P10")"
keptname "K10 R9-3 RELEASE_ENV_KEEP" "$o10" KEEPME XGIT_ZZ10 XLC_ZZ10 MYLANG10
# shellcheck disable=SC2086   # word splitting of the name list on purpose
gonename "K10 R9-3 RELEASE_ENV_KEEP (prefix)" "$o10" $P10
# R9-1: the names ssh forwards to the remote host (SendEnv of the default ssh_config: LANG LC_* COLORTERM NO_COLOR),
# refused as a class by name: every LC_ name (also lower case), every LANG name (LANGUAGE is on the base list and is
# shape-checked there), COLORTERM and NO_COLOR; values pass the common checks, so only the name decides
S10="LC_ZZ10 LC_X10 lc_zz10 LANGX10 LANG_ZZ10 COLORTERM NO_COLOR"
o10="$(kenv HOME=/h KEEPME=/srv/x LC_ZZ10=user:ZZLCPW10@host LC_X10=0123456789abcdef0123456789abcdef01234567 lc_zz10=/srv/l \
  LANGX10=/srv/x LANG_ZZ10=/srv/y COLORTERM=ZZCT10 NO_COLOR=ZZNC10 RELEASE_ENV_KEEP="KEEPME $S10")"
keptname "K10 R9-1 RELEASE_ENV_KEEP" "$o10" KEEPME
# shellcheck disable=SC2086
gonename "K10 R9-1 RELEASE_ENV_KEEP (SendEnv class)" "$o10" $S10
# ---- round 11 (R10-1, R10-4 of the round-10 review): rc_net, the one way a release script starts a network child ----
# The round-10 SendEnv reader (_rc_env_sendenv, _rc_env_sendenv_read, _rc_env_pwhome) is removed: its K10 cases
# (run-time SendEnv patterns, fail closed on an unparsable pattern, the ssh -G census, the passwd home, the
# /etc/ssh/ssh_config file) tested a parser that failed open (13 live leaks in the round-10 review). rc_net replaces
# it: the network child gets the network allow-list only, whatever an ssh or git configuration asks ssh to send; the
# live sshd probe docs/qa/con227_234_2026_11_11/round11/probe_sendenv_leak_sshd.sh is the LIVE evidence, the
# cases below are unit cases (§11.4.289(C)(1)).
# k11.sh: a script that calls rc_env_clean at its top level (the precondition of rc_net), then one K11 mode.
printf '#!/usr/bin/env bash\n. %q\nrc_env_clean "" "$@" || { echo "clean-rc=$?"; exit 1; }\n' "$L" >"$K6/k11.sh"
cat >>"$K6/k11.sh" <<'K11'
case "${1:-}" in
  net) rc_net env; echo "rc=$?" ;;
  local) env; echo "rc=$?" ;;
  badshape) GH_HOST='https://u:ZZPW11@h.invalid'; XDG_CACHE_HOME=rel11; TMPDIR=/srv/ok11; export GH_HOST XDG_CACHE_HOME TMPDIR
            rc_net env; echo "rc=$?" ;;
  late) ZZLATE11=ZZFAKE-late; export ZZLATE11; rc_net env; echo "rc=$?" ;;
  ifs) IFS=_; rc_net env; echo "rc=$?" ;;
  noexport) enable -n export; rc_net "$2" "$3"; echo "rc=$?" ;;
  shadow) export() { :; }; compgen() { :; }; exec() { :; }; rc_net env; echo "rc=$?" ;;
  noarg) rc_net; echo "rc=$?" ;;
  fn) zzfn11() { :; }; export -f zzfn11; rc_net env; echo "rc=$?" ;;
esac
K11
# the caller's dirty environment: a RELEASE_ENV_KEEP name, the credential-shaped names the round-10 word filter kept
# (R10-4), a name with "_" (for the IFS case), the locale, account and terminal names ssh would send, ZZ canaries
K11N="KEEPME ZZ_KEEP11 GITEA_PAT NPM_PAT DATABASE_DSN SLACK_WEBHOOK X_PRIVATE CLIENT_CERT SIGNING_SALT HMAC OTP"
k11() { # k11 MODE [ARG...]: the k11.sh output for MODE under the dirty environment
  # shellcheck disable=SC2046   # one NAME=VALUE argument per name, split on purpose
  env -i PATH="$PATH" HOME=/h TMPDIR=/tmp $(for n in $K11N; do printf '%s=ZZFAKE-%s-11 ' "$n" "$n"; done) \
    LANG=C.UTF-8 LANGUAGE=en LC_TIME=C USER=zzk11 LOGNAME=zzk11 TERM=xterm COLORTERM=truecolor NO_COLOR=1 TZ=UTC \
    RELEASE_ENV_KEEP="$K11N" timeout 30 bash "$K6/k11.sh" "$@" 2>&1; }
names11() { printf '%s\n' "$1" | grep -v '^rc=' | cut -d= -f1; }
o11="$(k11 local)"
keptname "K11 control: a LOCAL child" "$(names11 "$o11")" KEEPME ZZ_KEEP11 GITEA_PAT LANG USER TERM
o11="$(k11 net)"; n11="$(names11 "$o11")"
chk "K11 rc_net runs the command (status 0)" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=0"
keptname "K11 the network child" "$n11" PATH HOME TMPDIR LC_ALL GIT_TRACE_REDACT GIT_TERMINAL_PROMPT
printf '%s\n' "$o11" | grep -qx 'LC_ALL=C' && ok "K11 the network child has LC_ALL=C" || bad "K11 LC_ALL: $(printf '%s\n' "$o11" | grep '^LC_ALL=')"
printf '%s\n' "$o11" | grep -qx 'GIT_TRACE_REDACT=1' && printf '%s\n' "$o11" | grep -qx 'GIT_TERMINAL_PROMPT=0' \
  && ok "K11 the network child has GIT_TRACE_REDACT=1 and GIT_TERMINAL_PROMPT=0" || bad "K11 git constants missing"
# shellcheck disable=SC2086
gonename "K11 rc_net" "$n11" $K11N LANG LANGUAGE LC_TIME USER LOGNAME TERM COLORTERM NO_COLOR TZ SHLVL PWD OLDPWD _ RELEASE_ENV_KEEP
x11=""; for n in $n11; do case " $NET_ALLOW " in *" $n "*) ;; *) x11="$x11 $n" ;; esac; done
chk "K11 every name of the network child is on the test's own copy of the network allow-list (NET_ALLOW)" "${x11:-none}" none
printf '%s\n' "$o11" | grep -q 'ZZFAKE-\|zzk11' && bad "K11 a caller value reaches the network child" || ok "K11 no caller value of the dirty names reaches the network child"
# an allow-listed name whose value does not have the shape of its name is dropped; one that has it is kept
o11="$(k11 badshape)"; n11="$(names11 "$o11")"
keptname "K11 shape" "$n11" TMPDIR
gonename "K11 shape (a URL with a password in GH_HOST, a relative XDG_CACHE_HOME)" "$n11" GH_HOST XDG_CACHE_HOME
printf '%s\n' "$o11" | grep -q 'ZZPW11' && bad "K11 shape: the password reaches the network child" || ok "K11 shape: the password does not reach the network child"
# a variable exported by the script itself after rc_env_clean does not reach the network child either
o11="$(k11 late)"; gonename "K11 exported after rc_env_clean" "$(names11 "$o11")" ZZLATE11
# the caller's IFS does not change the census (an IFS of "_" would split ZZ_KEEP11 and GIT_SSH into parts)
o11="$(k11 ifs)"; n11="$(names11 "$o11")"
chk "K11 IFS=_: rc_net runs the command (status 0)" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=0"
gonename "K11 IFS=_" "$n11" ZZ_KEEP11 KEEPME LANG
# functions named export, compgen and exec do not replace the builtins rc_net uses
o11="$(k11 shadow)"; n11="$(names11 "$o11")"
keptname "K11 shadowing functions" "$n11" PATH LC_ALL
gonename "K11 shadowing functions" "$n11" ZZ_KEEP11 KEEPME LANG USER
# the second census is load-bearing: with the export builtin disabled no un-export takes effect, and rc_net refuses
# (status 125) without running the command. Control: the command runs when it is reached (the net case above).
o11="$(k11 noexport touch "$K6/k11.ran")"
chk "K11 export disabled: rc_net refuses with status 125" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=125"
printf '%s\n' "$o11" | grep -q 'rc_net: refused: a variable outside the network allow-list is still exported' && ok "K11 export disabled: the refusal is named" || bad "K11 export disabled: $o11"
[ -e "$K6/k11.ran" ] && bad "K11 export disabled: the command ran" || ok "K11 export disabled: the command did not run"
o11="$(k11 noarg)"; chk "K11 rc_net with no command: status 125" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=125"
# an exported function does not reach the network child (bash passes it as an environment entry BASH_FUNC_name%%).
# Control: a local child of the same shape has it.
o11="$(k11 fn)"; chk "K11 exported function: rc_net runs the command (status 0)" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=0"
printf '%s\n' "$o11" | grep -q 'zzfn11' && bad "K11 an exported function reaches the network child" || ok "K11 an exported function does not reach the network child"
o11="$(env -i PATH="$PATH" bash -c 'zzfn11() { :; }; export -f zzfn11; env' 2>&1)"
printf '%s\n' "$o11" | grep -q 'zzfn11' && ok "K11 control: an exported function is an environment entry of a plain child" || bad "K11 control: the exported function is not visible ($o11)"
# the precondition: a shell that was not re-executed by rc_env_clean gets status 125 and the command does not run
o11="$(env -i PATH="$PATH" HOME=/h KEEPME=x bash -c '. "$1"; rc_net touch "$2"; echo "rc=$?"' _ "$L" "$K6/k11.pre" 2>&1)"
chk "K11 not rebuilt by rc_env_clean: status 125" "$(printf '%s\n' "$o11" | grep '^rc=')" "rc=125"
printf '%s\n' "$o11" | grep -q 'rc_net: refused: the environment was not rebuilt by rc_env_clean' && ok "K11 precondition: the refusal is named" || bad "K11 precondition: $o11"
[ -e "$K6/k11.pre" ] && bad "K11 precondition: the command ran" || ok "K11 precondition: the command did not run"
# R9-4 (Q11): every credential word of the name filter, one RELEASE_ENV_KEEP name each (upper and lower case); the
# value passes the common checks, so only the word decides
W10="ZW_TOK ZW_SECRET ZW_PASS ZW_PWD ZW_KEY ZW_CRED ZW_AUTH ZW_COOKIE ZW_SESSION ZW_JWT ZW_PROXY zw_passwd"
# shellcheck disable=SC2046,SC2086
o10="$(kenv HOME=/h KEEPME=/srv/x $(for w in $W10; do printf '%s=/srv/w10 ' "$w"; done) RELEASE_ENV_KEEP="KEEPME $W10")"
keptname "K10 R9-4 credential words" "$o10" KEEPME
# shellcheck disable=SC2086
gonename "K10 R9-4 RELEASE_ENV_KEEP (credential word)" "$o10" $W10
# N2: a RELEASE_ENV_KEEP word is never glob-expanded against the current directory ("ZZG10*" is not an identifier;
# a file ZZG10A in the directory must not turn it into the name ZZG10A)
mkdir -p "$K6/g10d"; : >"$K6/g10d/ZZG10A"
o10="$(cd "$K6/g10d" && kenv HOME=/h KEEPME=/srv/x ZZG10A=/srv/g RELEASE_ENV_KEEP='KEEPME ZZG10*')"
keptname "K10 N2 glob" "$o10" KEEPME
gonename "K10 N2 RELEASE_ENV_KEEP glob-expanded" "$o10" ZZG10A
# R9-2 (A10): a caller variable off the list is not even a shell variable of the re-executed script (the first
# rc_env_lockdown un-exports it before the dump, so it is never carried); HELP=1 is the round-9 review's repro
printf '#!/usr/bin/env bash\n. %q\nrc_env_clean "" "$@"; r=$?\nprintf "rc=%%s zzplain=%%s help=%%s\\n" "$r" "${ZZPLAIN10-unset}" "${HELP-unset}"\n' "$L" >"$K6/p10.sh"
o10="$(env -i PATH="$PATH" HOME=/h ZZPLAIN10=ZZP10 HELP=1 timeout 30 bash "$K6/p10.sh" 2>&1)"
chk "K10 R9-2 a caller variable off the list is not a variable of the re-executed script" "$o10" "rc=0 zzplain=unset help=unset"
# R9-4 (Q1): every descriptor 3..64 the caller passes is closed before a child runs (the earlier cases sample four
# numbers; a mutant that keeps one more small number, such as 5, is seen here)
o10="$(env -i PATH="$PATH" HOME=/h timeout 30 bash -c 'for i in $(seq 3 64); do eval "exec $i</dev/null"; done; exec bash "$1"' _ "$K6/p.sh" 2>&1)"
case "$o10" in *"rc=0"*"childfds="*) ok "K10 R9-4 probe with descriptors 3..64 ran (control needle)" ;; *) bad "K10 R9-4 probe: $o10" ;; esac
case "$(printf '%s\n' "$o10" | grep '^childfds=')" in "childfds=") ok "K10 R9-4 none of the descriptors 3..64 reaches a child" ;; *) bad "K10 R9-4 descriptors reach a child: $(printf '%s\n' "$o10" | grep '^childfds=')" ;; esac
# F8 and the locale class: the values ssh sends off-host (LANG, LC_*) and LANGUAGE get a locale grammar
# (language of 2 or 3 lower-case letters, or C or POSIX; optional _TERRITORY, .codeset, @modifier); a bare 40-hex
# token and "user:password@host" are dropped; real locale values are kept
for v in "en_US.UTF-8" "C" "POSIX" "C.UTF-8" "sr_RS.UTF-8@latin" "ca_ES.UTF-8@valencia" "de_DE.ISO-8859-15@euro" "es_419.UTF-8" "ast_ES" ""; do
  sh9 "F8 locale value kept (control needle) '$v'" LANG "$v" keep; done
for v in "0123456789abcdef0123456789abcdef01234567" "ZZTOKEN10ZZ" "japanese" "en_us.UTF-8" "user@host"; do
  sh9 "F8 not a locale: '$v'" LC_TIME "$v" drop; done
for v in "sr_RS@latin:en_US:en" "en" "" "de:en"; do sh9 "F8 LANGUAGE kept (control needle) '$v'" LANGUAGE "$v" keep; done
for v in "user:ZZPW10@host" "0123456789abcdef0123456789abcdef01234567" "en:ZZTOKEN10" "en:japanese"; do
  sh9 "F8 LANGUAGE dropped '$v'" LANGUAGE "$v" drop; done
# round 11 (N-1, R13 and R20 of the round-10 review): the codeset and the modifier are CLOSED lists (the glibc
# codesets and modifiers of the locales a system ships), so a token cannot hide in either: a 40-hex codeset (N-1), a
# codeset holding ":" (R13), a long free-form codeset and modifier (R20, the reviewer's 69-byte value), and a
# modifier that is not on the list are dropped; the codesets and modifiers of real locales are kept
for v in "en_US.utf8" "en_US.UTF-8" "de_DE.iso88591" "de_DE.ISO-8859-15@euro" "ja_JP.eucJP" "ja_JP.SJIS" "zh_CN.GB18030" \
  "zh_TW.Big5" "ru_RU.KOI8-R" "be_BY.UTF-8@latin" "sr_RS@latin" "uz_UZ.UTF-8@cyrillic" "C.utf8" "tt_RU@iqtelif" "en_US.ANSI_X3.4-1968"; do
  sh9 "R11 locale kept (control needle) '$v'" LANG "$v" keep; done
for v in "en_US.0123456789abcdef0123456789abcdef01234567" "C.0123456789abcdef0123456789abcdef01234567" "en_US.ab:cd" \
  "en_US.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "en_US.UTF-8@ZZTOKEN11" "en_US@0123456789abcdef0123456789abcdef01234567" \
  "en_US.UTF-9" "en_US.utf-8x" "en_US." "en_US@" "en_US.UTF-8@euro@latin" \
  "en_US.UTF-8 ZZTOKEN11" "en_US.UTF-8:ZZTOKEN11" "en_US.UTF-8/ZZTOKEN11"; do   # a word, a ":" or a "/" after a known codeset (mutants B5, RR10)
  sh9 "R11 not a locale: '$v'" LC_TIME "$v" drop; done
# round 12 (F2 of the round-11 review): the reviewer's mutant RM20 widened the modifier to [a-z0-9]{1,32} and
# survived, because no dropped value had a lower-case modifier. A lower-case word and a 32-character lower-case
# modifier that are not on the closed list must be dropped (fake canaries).
for v in "en_US.UTF-8@zztoken11" "en_US.UTF-8@zzfakeabcdefghijklmnopqrstuvwxyz"; do
  sh9 "R12 F2 a modifier not on the closed list: '$v'" LC_TIME "$v" drop; done
sh9 "R11 LANGUAGE element with a 40-hex codeset dropped" LANGUAGE "en:de_DE.0123456789abcdef0123456789abcdef01234567" drop
# R20 is equivalent under the closed lists: the longest value the grammar admits (a 3-letter language, a 3-digit
# territory, the longest codeset and the longest modifier) is far below the 64-byte cap, so the cap decides nothing.
# Control needle: that value is kept (the instrument computes a value the grammar really admits).
lv11="ast_419.ansi_x3.4-1968@ijekavianlatin"
sh9 "R11 the longest admitted locale (control needle, ${#lv11} bytes)" LANG "$lv11" keep
[ "${#lv11}" -lt 64 ] && ok "R11 R20: the longest admitted locale (${#lv11} bytes) is below the 64-byte cap" || bad "R11 R20: ${#lv11} bytes"
# R11 RACE (found by the second suite run of round 11): two env_census recorders running at the same time (a network
# child and a local child of one pipeline) used to interleave their lines in the shared log, so one child's names
# were counted under the other's "== cmd" header (measured: 285 of 600 records misattributed). 200 pairs of a git and
# a sed recorder are started together; every record must keep its own marker, and both markers must be counted 200
# times (the control needles: the instrument sees both children).
# (ENV_CENSUS_PY: the mutation harness passes a mutated copy of env_census.py; the default is the file beside this suite)
RC1="$K6/race"; mkdir -p "$RC1/sh"
if python3 -I "${ENV_CENSUS_PY:-$HERE/env_census.py}" mk "$RC1/sh" "$RC1/log" git sed >/dev/null; then
  for _ in $(seq 1 200); do
    env -i PATH="$RC1/sh:$PATH" ZZRACEGIT=1 git --version >/dev/null 2>&1 &
    env -i PATH="$RC1/sh:$PATH" ZZRACESED=1 sed --version >/dev/null 2>&1 &
    wait
  done
  rr="$(awk '/^== /{c=$2; n[c]++; next} /^E ZZRACEGIT=/{g++; if (c!="git") x++} /^E ZZRACESED=/{s++; if (c!="sed") x++}
    END {printf "%d %d %d %d %d", n["git"], n["sed"], g, s, x+0}' "$RC1/log")"
  read -r rg rs mg ms mx <<<"$rr"
  [ "$rg" = 200 ] && [ "$rs" = 200 ] && [ "$mg" = 200 ] && [ "$ms" = 200 ] && ok "R11 RACE: both recorders seen 200 times (control needles: $rr)" || bad "R11 RACE: instrument blind or records lost ($rr)"
  [ "$mx" = 0 ] && ok "R11 RACE: no record of concurrent recorders is misattributed" || bad "R11 RACE: $mx records misattributed (interleaved log)"
  rl=("$RC1"/log.rec.*); [ -e "${rl[0]-}" ] && bad "R11 RACE: a recorder's private file was left next to the log (${rl[0]-})" || ok "R11 RACE: no private record file left"
else bad "R11 RACE: env_census.py mk failed (flock, cat or rm missing?)"; fi
. "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "${K6:?}" 2>/dev/null

[ "$skipped" -eq 0 ] || echo "SKIPPED: $skipped case(s) did not run (see the SKIP lines); the result does not cover them"
echo "RESULT: pass=$pass fail=$fail"
suite_exit "$fail" "$skipped"   # round 9 (F5): 77 when a case was SKIPPED
