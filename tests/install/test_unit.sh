#!/usr/bin/env bash
# test_unit.sh — UNIT tests for scripts/install_constitution.sh (functions sourced in library mode).
#
# Covers: input validators (agent id, ref, URL, model, effort, numbers), JSON escaping, URL credential
# stripping, prompt extraction from latest.md (first fenced block under `## PROMPT`), follow-up front
# matter, newest-tag selection, the stream-json result parser (fixture JSONL lines written here: these
# are GATE-LOGIC/UNIT fixtures, never live proof of an agent run), the snippet table, --help/--version,
# usage exit codes, and the truncation sentinel.
# Usage: bash tests/install/test_unit.sh   Exit 0 all pass · 1 a case failed.
T_NAME=unit
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox

# shellcheck disable=SC1090
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER" || { nok "installer sources in library mode"; finish; exit 1; }
ok "installer sources in library mode without running main"

echo "# validators"
for v in claude claude1 claude12 deepseek kimi opencode pi kc-foo helixllm-a.b none; do
  check "agent id accepted: $v" hi_validate_agent_id "$v"; done
for v in '' '-x' '--yolo' 'a b' 'a;b' 'a$(id)' 'a`id`' $'a\nb' '../x' 'a/b'; do
  check "agent id rejected: [$v]" eval '! hi_validate_agent_id "$v"'; done
for v in main helixconstitution-v72.1 v1.0.0 a5cee41 refs/tags/x; do check "ref accepted: $v" hi_validate_ref "$v"; done
for v in '' '-b' '--upload-pack=x' 'a..b' 'a b' 'x;rm' $'a\nb' 'a~1' 'a^'; do check "ref rejected: [$v]" eval '! hi_validate_ref "$v"'; done
for v in https://github.com/HelixDevelopment/HelixConstitution.git git@github.com:HelixDevelopment/HelixConstitution.git \
         ssh://git@example.org:2222/o/r.git file:///tmp/x/upstream.git /tmp/x/upstream.git; do
  check "url accepted: $v" hi_validate_url "$v"; done
for v in '' '-oProxyCommand=x' 'ext::sh -c id' 'https://x/$(id)' 'https://x/`id`' 'https://x/a b' $'https://x/a\nb' \
         'https://x/a;b' 'fd::3' '--upload-pack=touch /tmp/p' 'relative/path.git' "https://x/a'b"; do
  check "url rejected: [$v]" eval '! hi_validate_url "$v"'; done
for v in sonnet opus haiku claude-sonnet-4-5 'provider/model:tag'; do check "model accepted: $v" hi_validate_model "$v"; done
for v in '' '-x' 'a b' 'a;b' '$(id)'; do check "model rejected: [$v]" eval '! hi_validate_model "$v"'; done
for v in low medium high xhigh max; do check "effort accepted: $v" hi_validate_effort "$v"; done
for v in '' huge 'high;x'; do check "effort rejected: [$v]" eval '! hi_validate_effort "$v"'; done
for v in 0 1 2 1800 0.5 2.25; do check "number accepted: $v" hi_validate_number "$v"; done
for v in '' -1 1e9 'x' '1;2' '1 2'; do check "number rejected: [$v]" eval '! hi_validate_number "$v"'; done
for v in 1 60 1800 86400; do check "timeout accepted: $v" hi_validate_timeout "$v"; done
for v in '' 0 00 86401 999999 -5 1.5 x; do check "timeout rejected: [$v]" eval '! hi_validate_timeout "$v"'; done
for v in 0.01 0.5 2 50 50.0; do check "budget accepted: $v" hi_validate_budget "$v"; done
for v in '' 0 0.0 0.00 50.01 51 1000 -1 x; do check "budget rejected: [$v]" eval '! hi_validate_budget "$v"'; done
check "bash 4.4 accepted" hi_bash_ok 4 4
check "bash 5.0 accepted" hi_bash_ok 5 0
for v in "4 3" "4 0" "3 2"; do check "bash $v rejected (empty arrays under set -u)" eval '! hi_bash_ok $v'; done

echo "# json + url sanitising"
eq "json escape quotes/backslash/newline/tab/control" '"a\"b\\c\nd\te\u0001"' "$(hi_json_str $'a"b\\c\nd\te\x01')"
eq "credentials stripped from https url" "https://github.com/o/r.git" "$(hi_sanitize_url 'https://user:sekrit@github.com/o/r.git')"
eq "token-only userinfo stripped" "https://gitlab.com/o/r.git" "$(hi_sanitize_url 'https://oauth2:glpat-xyz@gitlab.com/o/r.git')"
eq "ssh url unchanged" "git@github.com:o/r.git" "$(hi_sanitize_url 'git@github.com:o/r.git')"
# a password that itself contains "@" must not leak its tail; userinfo ends at the LAST "@" before the path
eq "password with @ fully stripped" "https://github.com/o/r.git" "$(hi_sanitize_url 'https://u:p@ss@w0rd@github.com/o/r.git')"
eq "upper-case scheme credentials stripped" "HTTPS://github.com/o/r.git" "$(hi_sanitize_url 'HTTPS://u:pw@github.com/o/r.git')"
eq "ssh:// user:password stripped (last @)" "ssh://host:2222/o/r.git" "$(hi_sanitize_url 'ssh://git:p@x@host:2222/o/r.git')"
eq "ssh:// plain user kept" "ssh://git@host/o/r.git" "$(hi_sanitize_url 'ssh://git@host/o/r.git')"
eq "query token redacted" "https://host/o/r.git?private_token=REDACTED&x=REDACTED" "$(hi_sanitize_url 'https://host/o/r.git?private_token=glpat-SEKRIT&x=1')"
eq "credentials + query + fragment" "https://host/r?access_token=REDACTED#frag" "$(hi_sanitize_url 'https://a:b@c@host/r?access_token=SEKRIT#frag')"
eq "local path unchanged" "/srv/git/up.git" "$(hi_sanitize_url /srv/git/up.git)"
check "has-password: password containing @" hi_url_has_password 'https://u:p@ss@host/r'
check "has-password: query token" hi_url_has_password 'https://host/r.git?private_token=SEKRIT'
check "has-password: plain https not flagged" eval '! hi_url_has_password https://host/o/r.git'
check "has-password: ssh user not flagged" eval '! hi_url_has_password ssh://git@host/o/r.git'
sc="$(printf 'fatal: unable to access https://u:p@ss@w0rd@host/r.git/: 403\nssh://g:pa@ss@h/x ?q https://h/r?token=SEKRIT&a=1 done\n' | hi_scrub)"
check "scrub: no secret fragment left (p@ss, w0rd, pa@, SEKRIT)" eval '! grep -q "w0rd\|ss@\|pa@\|SEKRIT\|p@" <<<"$sc"'
check "scrub: host and path kept" grep -q 'https://host/r.git/: 403' <<<"$sc"
check "scrub: query redacted" grep -q 'token=REDACTED&a=REDACTED' <<<"$sc"

echo "# prompt extraction"
cat >"$SB/latest.md" <<'EOF'
# Title
Intro text with a fence that is NOT under PROMPT:
```text
NOT THIS
```
## PROMPT
Some lead-in.
````markdown
LINE ONE
```inner fence kept```
LINE THREE
````
```text
SECOND BLOCK NOT USED
```
## Other
EOF
eq "first fenced block under ## PROMPT (longer fence, inner fence kept)" $'LINE ONE\n```inner fence kept```\nLINE THREE' "$(hi_extract_prompt "$SB/latest.md")"
printf '# x\n## PROMPT\nno fence here\n' >"$SB/nofence.md"
check "missing fence under ## PROMPT -> failure" eval '! hi_extract_prompt "$SB/nofence.md" >/dev/null'
printf '# x\n```\nA\n```\n' >"$SB/noheading.md"
check "missing ## PROMPT heading -> failure" eval '! hi_extract_prompt "$SB/noheading.md" >/dev/null'
printf -- '---\ntitle: T\nrequires_previous_success: false\n---\nBODY 1\nBODY 2\n' >"$SB/f1.md"
eq "follow-up body after front matter" $'BODY 1\nBODY 2' "$(hi_followup_body "$SB/f1.md")"
eq "follow-up requires_previous_success false" "false" "$(hi_followup_requires "$SB/f1.md")"
printf 'NO FRONT MATTER\n' >"$SB/f2.md"
eq "follow-up without front matter = whole body" "NO FRONT MATTER" "$(hi_followup_body "$SB/f2.md")"
eq "follow-up requires default true" "true" "$(hi_followup_requires "$SB/f2.md")"

echo "# newest tag"
eq "newest helixconstitution tag by version sort" "helixconstitution-v72.10" "$(printf '%s\n' \
  'aaa	refs/tags/helixconstitution-v72' 'bbb	refs/tags/helixconstitution-v72.1' 'ccc	refs/tags/helixconstitution-v72.10^{}' \
  'ccc	refs/tags/helixconstitution-v72.10' 'ddd	refs/tags/helixconstitution-v9' 'eee	refs/tags/v100' | hi_newest_tag)"
eq "no matching tag -> empty" "" "$(printf 'aaa\trefs/tags/v1\n' | hi_newest_tag)"
eq "pre-release tags never chosen by default" "helixconstitution-v72.1" "$(printf '%s\n' \
  'a	refs/tags/helixconstitution-v72.1' 'b	refs/tags/helixconstitution-v72.1-rc1' 'c	refs/tags/helixconstitution-v72.2-rc1' \
  'd	refs/tags/helixconstitution-v72.2-beta' | hi_newest_tag)"
eq "v9 < v10 < v100 (version order, not lexical)" "helixconstitution-v100" "$(printf '%s\n' \
  'a	refs/tags/helixconstitution-v9' 'b	refs/tags/helixconstitution-v100' 'c	refs/tags/helixconstitution-v10' | hi_newest_tag)"

echo "# release tags: numeric parts never have a leading zero (the prompt's single release regex)"
eq "leading-zero tags never chosen (v072 / v72.01 / v00)" "helixconstitution-v72.1" "$(printf '%s\n' \
  'a	refs/tags/helixconstitution-v72.1' 'b	refs/tags/helixconstitution-v0720' 'c	refs/tags/helixconstitution-v072' \
  'd	refs/tags/helixconstitution-v72.01' 'e	refs/tags/helixconstitution-v00' 'f	refs/tags/helixconstitution-v01000.0' | hi_newest_tag)"
eq "zero parts without a leading zero are fine (v0, v72.0)" "helixconstitution-v72.0" "$(printf '%s\n' \
  'a	refs/tags/helixconstitution-v0' 'b	refs/tags/helixconstitution-v72.0' | hi_newest_tag)"
eq "only-leading-zero tags -> empty" "" "$(printf '%s\n' 'a	refs/tags/helixconstitution-v01' | hi_newest_tag)"

echo "# release regex drift: installer, updater and the setup prompt use ONE identical regex"
drift="$(python3 -I - "$INSTALLER" "$UPDATER" "$REPO/docs/prompts/setup/latest.md" <<'PY'
import re, sys
inst, upd, prompt = (open(p).read() for p in sys.argv[1:4])
def assigned(src):
    return re.findall(r"^HI_RELEASE_TAG_RE='([^']*)'$", src, re.M)
def literals(src):   # every other release-regex literal in the file (must be none)
    return [m for m in re.findall(r"\^helixconstitution-v[^'\"`\s]*\$", src)]
p = set(re.findall(r"grep -E '(\^helixconstitution-v[^']*\$)'", prompt))
pb = set(re.findall(r"`(\^helixconstitution-v[^`]*\$)`", prompt))
print("prompt_grep_distinct=%d prompt_grep_count=%d" % (len(p), len(re.findall(r"grep -E '\^helixconstitution-v", prompt))))
print("prompt_prose_has_canonical=%s" % ("yes" if len(p) == 1 and p <= pb else "no"))
for name, src in (("installer", inst), ("updater", upd)):
    a = assigned(src)
    print("%s_assign=%d" % (name, len(a)))
    print("%s_other_literals=%d" % (name, len([l for l in literals(src) if l not in a])))
    print("%s_equal=%s" % (name, "yes" if len(a) == 1 and len(p) == 1 and a[0] in p else "no"))
PY
)"
printf '%s\n' "$drift" | sed 's/^/  /'
check "control: the prompt carries its release regex at least 4 times" eval '[ "$(sed -n "s/.*prompt_grep_count=//p" <<<"$drift")" -ge 4 ]'
check "the prompt uses exactly one distinct release regex" grep -q 'prompt_grep_distinct=1 ' <<<"$drift"
check "the prompt's prose names the same regex its commands use" grep -q '^prompt_prose_has_canonical=yes$' <<<"$drift"
for w in installer updater; do
  check "$w defines HI_RELEASE_TAG_RE exactly once" grep -q "^${w}_assign=1$" <<<"$drift"
  check "$w has no second release-regex literal" grep -q "^${w}_other_literals=0$" <<<"$drift"
  check "$w release regex == the prompt's" grep -q "^${w}_equal=yes$" <<<"$drift"
done

echo "# stream-json parser (UNIT fixtures, not live evidence)"
sj() { printf '%s\n' "$@" >"$SB/s.jsonl"; hi_parse_stream "$SB/s.jsonl"; }
r="$(sj '{"type":"system","subtype":"init","session_id":"S-1"}' '{"type":"assistant"}' '{"type":"result","subtype":"success","is_error":false,"session_id":"S-1"}')"
eq "success result" "result=success session=S-1 rate_limited=0 cost=unknown" "$r"
r="$(sj '{"type":"system","subtype":"init","session_id":"S-2"}' '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"session_id":"S-2"}')"
eq "is_error true -> failure" "result=failure session=S-2 rate_limited=0 cost=unknown" "$r"
r="$(sj '{"type":"system","subtype":"init","session_id":"S-3"}' '{"type":"assistant"}')"
eq "no result event -> none" "result=none session=S-3 rate_limited=0 cost=unknown" "$r"
r="$(sj '{"type":"system","subtype":"init","session_id":"S-4"}' '{"type":"assistant","isApiErrorMessage":true,"apiErrorStatus":429}' '{"type":"result","subtype":"success","is_error":true,"session_id":"S-4"}')"
eq "429 detected" "result=failure session=S-4 rate_limited=1 cost=unknown" "$r"
r="$(sj 'garbage not json' '{"type":"result","subtype":"success","is_error":false,"session_id":"S-5"}')"
eq "garbage lines ignored" "result=success session=S-5 rate_limited=0 cost=unknown" "$r"
r="$(sj '{"type":"result","subtype":"success","is_error":false}' '{"type":"result","subtype":"success","is_error":true}')"
eq "LAST result event decides" "result=failure session= rate_limited=0 cost=unknown" "$r"
r="$(sj '{"type":"result","subtype":"success","is_error":false,"session_id":"S-6","total_cost_usd":0.4321}')"
eq "cost read from total_cost_usd" "result=success session=S-6 rate_limited=0 cost=0.4321" "$r"
r="$(sj '{"type":"result","subtype":"success","is_error":false,"session_id":"S-7","total_cost_usd":"x"}')"
eq "non-numeric cost -> unknown" "result=success session=S-7 rate_limited=0 cost=unknown" "$r"

echo "# snippet table + cli"
sn="$(bash "$INSTALLER" --print-snippets 2>&1)"; rc=$?
eq "--print-snippets exit 0" 0 "$rc"
for u in https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh \
         https://gitlab.com/helixdevelopment1/helixconstitution/-/raw/main/scripts/install_constitution.sh \
         https://gitlab.com/vasic-digital/HelixConstitution/-/raw/main/scripts/install_constitution.sh \
         'https://gitflic.ru/project/helixdevelopment/helixconstitution/blob/raw?file=scripts/install_constitution.sh&branch=main' \
         https://gitverse.ru/api/repos/helixdevelopment/HelixConstitution/raw/branch/main/scripts/install_constitution.sh; do
  case "$sn" in *"curl -fsSL '$u' | bash"*) ok "snippet present: $u" ;; *) nok "snippet present: $u" ;; esac
done
eq "exactly 5 snippet lines" 5 "$(printf '%s\n' "$sn" | grep -c '^curl -fsSL ')"
v="$(bash "$INSTALLER" --version)"; check "--version prints installer version" eval '[[ "$v" =~ ^install_constitution\.sh\ [0-9]+\.[0-9]+\.[0-9]+$ ]]'
h="$(bash "$INSTALLER" --help)"; rc=$?; eq "--help exit 0" 0 "$rc"
for fl in --project-root --upstream --ref --agent --model --effort --max-budget-usd --timeout-sec --non-interactive --yes \
          --dry-run --decision-layer --followups --commit --report-json --print-snippets; do
  case "$h" in *"$fl"*) ok "--help documents $fl" ;; *) nok "--help documents $fl" ;; esac; done
bash "$INSTALLER" --no-such-flag >/dev/null 2>&1; eq "unknown flag -> exit 2" 2 "$?"
bash "$INSTALLER" --agent >/dev/null 2>&1; eq "flag missing value -> exit 2" 2 "$?"
bash "$INSTALLER" --effort huge --non-interactive >/dev/null 2>&1; eq "invalid effort -> exit 2" 2 "$?"
bash "$INSTALLER" --timeout-sec 0 --non-interactive >/dev/null 2>&1; eq "--timeout-sec 0 -> exit 2" 2 "$?"
bash "$INSTALLER" --timeout-sec 86401 --non-interactive >/dev/null 2>&1; eq "--timeout-sec 86401 -> exit 2" 2 "$?"
bash "$INSTALLER" --max-budget-usd 0 --non-interactive >/dev/null 2>&1; eq "--max-budget-usd 0 -> exit 2" 2 "$?"
bash "$INSTALLER" --max-budget-usd 50.5 --non-interactive >/dev/null 2>&1; eq "--max-budget-usd 50.5 -> exit 2" 2 "$?"
v="$(bash "$INSTALLER" --effort=high --version 2>&1)"; eq "--flag=value accepted" 0 "$?"
bash "$INSTALLER" --effort=huge --version >/dev/null 2>&1; eq "--flag=value is validated (--effort=huge -> 2)" 2 "$?"
bash "$INSTALLER" --dry-run=yes --version >/dev/null 2>&1; eq "boolean flag with =value -> exit 2" 2 "$?"
bash "$INSTALLER" --version -- >/dev/null 2>&1; eq "a lone -- is accepted" 0 "$?"
bash "$INSTALLER" -- --version >/dev/null 2>&1; eq "argument after -- -> exit 2" 2 "$?"
o="$(bash "$INSTALLER" --upstream-url http://example.invalid/x.git --non-interactive --dry-run 2>&1)"; rc=$?
eq "http:// upstream refused without --allow-insecure-url (exit 2)" 2 "$rc"
check "insecure refusal names the flag" grep -q -- '--allow-insecure-url' <<<"$o"
bash "$INSTALLER" --upstream-url git://example.invalid/x.git --non-interactive --dry-run >/dev/null 2>&1; eq "git:// upstream refused (exit 2)" 2 "$?"
for fl in --allow-insecure-url --max-budget-usd --timeout-sec; do case "$(bash "$INSTALLER" --help)" in *"$fl"*) ok "--help documents $fl" ;; *) nok "--help documents $fl" ;; esac; done
case "$(bash "$INSTALLER" --help)" in *"not enforced"*) ok "--help says which agents cannot enforce model/effort/budget" ;; *) nok "--help says which agents cannot enforce model/effort/budget" ;; esac
(cd "$SB" && setsid bash "$INSTALLER" </dev/null >/dev/null 2>&1); eq "no TTY and no --non-interactive -> exit 2" 2 "$?"

echo "# truncation sentinel"
tail_line="$(tail -n 1 "$INSTALLER")"
eq "last line is the sentinel main call" 'main "$@" __helix_installer_eof__' "$tail_line"
out="$(bash -c 'HELIX_INSTALLER_LIB_MODE=1; source "$1"; HELIX_INSTALLER_LIB_MODE=; main --print-snippets' _ "$INSTALLER" 2>&1)"; rc=$?
case "$out" in *"curl -fsSL"*) nok "sentinel-less main printed snippets" ;; *) ok "sentinel-less main printed nothing useful" ;; esac
eq "main without the sentinel refuses (exit 2)" 2 "$rc"
echo "# shared blocks are byte-identical in the installer and the updater (one implementation, no drift)"
blk_of() { awk -v b="# >>> $2" -v e="# <<< $2" 'index($0, b) == 1 { on = 1 } on { print } $0 == e { on = 0 }' "$1"; }
for b in hi_resolve_ref_in hi_lock_helpers hi_text_safe hi_remote_live hi_gitlink_rel; do
  x="$(blk_of "$INSTALLER" "$b")"; y="$(blk_of "$UPDATER" "$b")"
  check "control: block $b present in the installer" eval '[ "$(wc -l <<<"$x")" -gt 5 ]'
  eq "block $b identical in installer and updater" "$(sha256sum <<<"$x")" "$(sha256sum <<<"$y")"
done

finish
