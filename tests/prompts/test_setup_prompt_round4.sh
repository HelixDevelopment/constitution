#!/usr/bin/env bash
# test_setup_prompt_round4.sh — regression tests for the review round 4 findings of
# docs/prompts/setup/latest.md and its follow-ups. Every test was written first and
# observed RED against the unfixed files. It EXECUTES the marked shell blocks
# (`# <ID>-BEGIN` / `# <ID>-END`) of the real prompt files against throw-away git
# repositories, and scans the runnable code of the prompt for forbidden commands.
#   IMP-1  credentials in a URL never reach the output: a decoy token in the origin
#          URL, the .gitmodules URL, a CONSTITUTION_URLS mirror and a push remote,
#          driven through STEP0, STEP2, STEP3, STEP4, STEP5 and STEP10
#   IMP-2  negative-content guard: no runnable block and no inline command line of
#          latest.md or any follow-up contains --force, a +refspec, a recursive
#          submodule update, --no-verify, reset --hard or rebase (prose may name them)
#   M-V1   STEP6B stops when setup.sh --check-only does not print "post_update_hook.sh: OK"
#   M-V6   STEP1 adds .constitution-install-backup/ to info/exclude exactly once
#   M-3    STEP1 never copies secret-class files (*.pem *.key credentials* .env* settings.local.json)
#   M-4    STEP8 and follow-up 02 run the bootstrap with JEV_BOOTSTRAP_CONSENT,
#          JEV_BOOTSTRAP_ALLOW_CLONE and JEV_BOOTSTRAP_INSTALL_TOOLS unset
#   M-5    STEP10 never pushes a submodule (push.recurseSubmodules=on-demand is overridden)
#   M-7    the mirror list (header, STEP3 default) equals the installer's six upstreams, in order
#   M-8    newest release = REMOTE tags only, pre-releases excluded, version order; the
#          same pipeline in the header, STEP2, STEP3, STEP5 and follow-up V3; the release
#          regex equals the installer's and the update script's
# Overrides (used by test_setup_prompt_round4_mutants.sh): R4_LATEST, R4_FU01, R4_FU02,
# R4_FU03 (paths of the files under test).
# Nothing outside a mktemp -d sandbox is written; no network (GIT_ALLOW_PROTOCOL=file:
# an https URL is refused by git before any connection); $HOME untouched. The code
# under test is written to a file inside its sandbox and run with `bash <file>`.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_ALLOW_PROTOCOL=file   # local bare remotes only; https is refused without a connection
export GIT_TERMINAL_PROMPT=0
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }

LATEST="${R4_LATEST:-$REPO/docs/prompts/setup/latest.md}"
FU01="${R4_FU01:-$REPO/docs/prompts/setup/followups/01_verify_incorporation.md}"
FU02="${R4_FU02:-$REPO/docs/prompts/setup/followups/02_wire_decision_layer_optional.md}"
FU03="${R4_FU03:-$REPO/docs/prompts/setup/followups/03_final_report.md}"
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || no "PROMPT block extracted"
blk_of() { # <id> <text> -> lines between `# <id>-BEGIN` and `# <id>-END`
  awk -v b="# $1-BEGIN" -v e="# $1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$2"
}
for n in STEP0 STEP1 STEP2 STEP3 STEP4 STEP5 STEP6B STEP10; do
  [ -n "$(blk_of "$n" "$block")" ] && ok "block $n present" || no "block $n missing"
done
run_txt() { # <code> <dir> -> writes the code to <dir>.sh, runs it in <dir>; output in <dir>.out
  printf '%s\n' "$1" >"$2.sh"
  ( cd "$2" && bash "$2.sh" ) >"$2.out" 2>&1
}
run_step() { run_txt "$(blk_of "STEP$1" "$block")" "$2"; }
out_of() { cat "$1.out"; }

TOK='FAKE_TOKEN_123'
TOKURL="https://x-access-token:$TOK@example.invalid/r.git"
TOKURL2="https://x-access-token:$TOK@push.invalid/p.git"
TOKURL_DEAD="https://x-access-token:$TOK@unreachable.invalid/r.git"

mk_remote() { # <sandbox> -> bare repo <sandbox>/remote.git: c1(v1) c2(v2) on main
  local s="$1" w="$1/work"
  git_q init -q "$w"; printf 'one\n' >"$w/f"; printf 'keep\n' >"$w/k"; git -C "$w" add f k; git -C "$w" commit -q -m c1
  git -C "$w" tag helixconstitution-v1
  printf 'two\n' >"$w/f"; git -C "$w" commit -q -am c2; git -C "$w" tag helixconstitution-v2
  git_q clone -q --bare "$w" "$s/remote.git"
}
tok_config() { # <sandbox> -> a SANDBOX global git config mapping the decoy URLs to local remotes
  # (a file inside the sandbox, never the real global config; protocol stays file-only)
  printf '[url "%s/remote.git"]\n\tinsteadOf = %s\n[url "%s/push.git"]\n\tinsteadOf = %s\n[protocol "file"]\n\tallow = always\n' \
    "$1" "$TOKURL" "$1" "$TOKURL2" >"$1/gitconfig"
  printf '%s/gitconfig' "$1"
}
no_token() { # <label> <outfile>
  if grep -qF "$TOK" "$2"; then no "$1: decoy token LEAKED: $(grep -F "$TOK" "$2" | head -n 2 | cut -c1-160)"; else ok "$1: decoy token never printed"; fi
}
mk_tokp0() { # <sandbox> <subpath> -> <sandbox>/p0 whose submodule URL is the decoy token URL (needs tok_config)
  local s="$1" sp="$2"
  git_q init -q "$s/p0"; printf '# p\n' >"$s/p0/README.md"; git -C "$s/p0" add README.md; git -C "$s/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$s/p0/submodules"
  git -C "$s/p0" submodule add -q "$TOKURL" "$sp" >/dev/null 2>&1 || return 1
  git -C "$s/p0/$sp" checkout -q helixconstitution-v1; git -C "$s/p0" add "$sp"; git -C "$s/p0" commit -q -m sub
  git clone -q "$s/p0" "$s/p"
}

# =================== IMP-1: credentials never printed ===============================
# (a) STEP2/5/4: a foreign nested repository whose origin carries the token (own_checkout)
for st in 2 5 4; do
  sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
  S="$(mk_sandbox)"; mk_remote "$S"
  git_q init -q "$S/p0"; printf '# p\n' >"$S/p0/README.md"; git -C "$S/p0" add README.md; git -C "$S/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$S/p0/submodules"
  git_q -C "$S/p0" submodule add -q "$S/remote.git" "$sp" >/dev/null 2>&1; git -C "$S/p0" commit -q -m sub
  git_q clone -q "$S/p0" "$S/p"; git -C "$S/p" submodule init >/dev/null 2>&1
  git_q init -q "$S/p/$sp"; printf 'z\n' >"$S/p/$sp/z"; git -C "$S/p/$sp" add z; git -C "$S/p/$sp" commit -q -m z
  git -C "$S/p/$sp" remote add origin "$TOKURL"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && grep -q 'another repository' "$S/p.out" && ok "IMP-1 STEP$st foreign repo still refused (rc=3)" || no "IMP-1 STEP$st foreign rc=$rc: $(out_of "$S/p")"
  no_token "IMP-1 STEP$st own_checkout STOP message" "$S/p.out"
  grep -qF 'https://***@example.invalid/r.git' "$S/p.out" && ok "IMP-1 STEP$st URL shown with userinfo redacted" || no "IMP-1 STEP$st redacted URL not shown: $(out_of "$S/p")"
done
# (b) STEP2/5/4: an uninitialised submodule whose .gitmodules URL carries the token
#     (git submodule update --init prints "Submodule '<name>' (<url>) registered")
for st in 2 5 4; do
  sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
  S="$(mk_sandbox)"; mk_remote "$S"; gc="$(tok_config "$S")"
  ( export GIT_CONFIG_GLOBAL="$gc"; mk_tokp0 "$S" "$sp" ) || no "IMP-1 STEP$st token fixture"
  ( export GIT_CONFIG_GLOBAL="$gc"; run_step "$st" "$S/p" ); rc=$?
  dst="$sp"; [ "$st" = 4 ] && dst=submodules/constitution   # STEP4 moves the legacy path
  # round 5 (I-1): a credential URL in the tracked .gitmodules is a STOP before anything is touched
  [ "$rc" -eq 3 ] && grep -q '^STOP: .gitmodules (submodule\..*\.url) holds a URL with credentials' "$S/p.out" \
    && [ ! -f "$S/p/$dst/k" ] && [ ! -f "$S/p/$sp/k" ] \
    && ok "IMP-1 STEP$st token-URL .gitmodules refused before init (rc=3)" || no "IMP-1 STEP$st token .gitmodules rc=$rc: $(out_of "$S/p")"
  no_token "IMP-1 STEP$st submodule init / fetch output" "$S/p.out"
done
# (b2) STEP2/5/4: .gitmodules is clean but the project's OWN .git/config already maps the
#      submodule to a token URL (an earlier local init): git 2.53 prints that URL in
#      "fatal: clone of '<url>' ... failed"; rrun must redact it (kills STEP2/5-INIT-RAW)
for st in 2 5 4; do
  sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
  S="$(mk_sandbox)"; mk_remote "$S"
  git_q init -q "$S/p0"; printf '# p\n' >"$S/p0/README.md"; git -C "$S/p0" add README.md; git -C "$S/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$S/p0/submodules"
  git_q -C "$S/p0" submodule add -q "$S/remote.git" "$sp" >/dev/null 2>&1; git -C "$S/p0" commit -q -m sub
  git_q clone -q "$S/p0" "$S/p"; git -C "$S/p" submodule init >/dev/null 2>&1
  git -C "$S/p" config "submodule.$sp.url" "$TOKURL_DEAD"
  run_step "$st" "$S/p"; rc=$?
  [ "$rc" -eq 3 ] && grep -qF 'https://***@unreachable.invalid/r.git' "$S/p.out" \
    && ok "IMP-1 STEP$st local token URL: init fails, URL shown redacted (rc=3)" || no "IMP-1 STEP$st local token URL rc=$rc: $(out_of "$S/p")"
  no_token "IMP-1 STEP$st init failure with a local token URL" "$S/p.out"
done
# (c) STEP3: an unreachable mirror and a reachable mirror, both with the token
S="$(mk_sandbox)"; mk_remote "$S"; gc="$(tok_config "$S")"
git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"; git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
( export GIT_CONFIG_GLOBAL="$gc" CONSTITUTION_URLS="$TOKURL_DEAD $TOKURL"; run_step 3 "$S/p" ); rc=$?
# round 5 (I-1): a mirror that carries credentials is skipped (never written to .gitmodules)
[ "$rc" -eq 3 ] && [ ! -e "$S/p/submodules/constitution" ] && [ ! -f "$S/p/.gitmodules" ] \
  && ok "IMP-1 STEP3 both token mirrors skipped, nothing added (rc=3)" || no "IMP-1 STEP3 rc=$rc: $(out_of "$S/p")"
no_token "IMP-1 STEP3 skipped mirror lines" "$S/p.out"
grep -qF 'skipped (carries credentials, never stored): https://***@unreachable.invalid/r.git' "$S/p.out" \
  && grep -qF 'skipped (carries credentials, never stored): https://***@example.invalid/r.git' "$S/p.out" \
  && ok "IMP-1 STEP3 both mirror lines shown redacted" || no "IMP-1 STEP3 mirror lines: $(out_of "$S/p")"
# STEP3 already-in-place branch with a foreign token repository
S="$(mk_sandbox)"; mk_remote "$S"
git_q init -q "$S/p0"; printf '# p\n' >"$S/p0/README.md"; git -C "$S/p0" add README.md; git -C "$S/p0" commit -q -m init
mkdir -p "$S/p0/submodules"; git_q -C "$S/p0" submodule add -q "$S/remote.git" submodules/constitution >/dev/null 2>&1; git -C "$S/p0" commit -q -m sub
git_q clone -q "$S/p0" "$S/p"; git -C "$S/p" submodule init >/dev/null 2>&1
git_q init -q "$S/p/submodules/constitution"; printf 'z\n' >"$S/p/submodules/constitution/z"
git -C "$S/p/submodules/constitution" add z; git -C "$S/p/submodules/constitution" commit -q -m z
git -C "$S/p/submodules/constitution" remote add origin "$TOKURL"
run_step 3 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && ok "IMP-1 STEP3 in-place foreign repo refused (rc=3)" || no "IMP-1 STEP3 in-place rc=$rc: $(out_of "$S/p")"
no_token "IMP-1 STEP3 in-place own_checkout message" "$S/p.out"
# (d) STEP0: .gitmodules URL with the token
S="$(mk_sandbox)"; git_q init -q "$S/p"
printf '[submodule "constitution"]\n\tpath = submodules/constitution\n\turl = %s\n' "$TOKURL" >"$S/p/.gitmodules"
run_step 0 "$S/p"
no_token "IMP-1 STEP0 inventory" "$S/p.out"
grep -qF 'submodule.constitution.url https://***@example.invalid/r.git' "$S/p.out" && grep -qF 'submodule.constitution.path submodules/constitution' "$S/p.out" \
  && ok "IMP-1 STEP0 lists path and the redacted URL" || no "IMP-1 STEP0 inventory: $(out_of "$S/p")"
# (e) STEP10: a push remote with the token (success) and one unreachable (failure)
S="$(mk_sandbox)"; mk_remote "$S"; gc="$(tok_config "$S")"; git_q init -q --bare "$S/push.git"
git_q init -q "$S/p"; printf 'a\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init
git -C "$S/p" remote add up "$TOKURL2"
( export GIT_CONFIG_GLOBAL="$gc"; run_step 10 "$S/p" ); rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$S/push.git" rev-parse main 2>/dev/null)" = "$(git -C "$S/p" rev-parse HEAD)" ] \
  && ok "IMP-1 STEP10 pushed through the token remote (rc=0)" || no "IMP-1 STEP10 rc=$rc: $(out_of "$S/p")"
no_token "IMP-1 STEP10 fetch/push output" "$S/p.out"
S="$(mk_sandbox)"; git_q init -q "$S/p"; printf 'a\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init
git -C "$S/p" remote add dead "$TOKURL_DEAD"
run_step 10 "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'fetch from dead failed' "$S/p.out" && ok "IMP-1 STEP10 unreachable token remote stops rc=3" || no "IMP-1 STEP10 dead rc=$rc: $(out_of "$S/p")"
no_token "IMP-1 STEP10 fetch failure output" "$S/p.out"
# static: every own_checkout copy and every URL echo goes through the redaction
n_oc="$(grep -c 'own_checkout() {' <<<"$block")"
n_red="$(grep -cF "origin URL '\$(printf '%s' \"\${u:-none}\" | redact)'" <<<"$block")"
[ "$n_oc" -ge 4 ] && [ "$n_red" -eq "$n_oc" ] && ok "IMP-1 all $n_oc own_checkout copies redact the origin URL" || no "IMP-1 own_checkout copies=$n_oc redacting=$n_red"
raw="$(grep -nE '(echo|printf)[^#]*\$\{?(u|url)\b' <<<"$block" | grep -v 'redact' || true)"
[ -z "$raw" ] && ok "IMP-1 no echo/printf of \$u/\$url without redact" || no "IMP-1 raw URL echo: $raw"

# inline lines that print remote URLs (nested init in STEP4, git remote -v in 6e)
inl="$(grep -E 'remote -v|submodule update --init -- "<that-path>"' <<<"$block")"
[ "$(wc -l <<<"$inl")" -ge 2 ] && ! grep -vqF '://***@' <<<"$inl" && ok "IMP-1 inline URL-printing lines (STEP4 nested init, 6e remote -v) redact" || no "IMP-1 inline URL-printing line without redaction: $inl"

# =================== IMP-2: negative-content guard ==================================
# runnable_code <file> <prompt|whole>: every line of every `# X-BEGIN/END` block plus
# every inline command line (indented, starting with a command word after an optional
# S<n>/V<n>/<n>. label), with single-quoted strings, double-quoted strings that hold no
# command substitution, and comments removed (an echo message may NAME a forbidden
# command; it does not RUN it). Prints "<line-number>: <code>".
runnable_code() {
  python3 -I - "$1" "$2" <<'PY'
import re, sys
path, mode = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read().split('\n')
if mode == 'prompt':
    out, st = [], 0
    for l in text:
        if st == 0 and re.match(r'^## PROMPT\s*$', l): st = 1; continue
        if st == 1 and re.match(r'^(```+|~~~+)', l): st = 2; continue
        if st == 2 and re.match(r'^(```+|~~~+)\s*$', l): break
        if st == 2: out.append(l)
    text = out
WORDS = ('git', 'bash', 'sh', 'env', 'curl', 'wget', 'tag=', 'out=', 'hooks=', 'for', 'if', '[', '(cd', 'cd',
         'ls', 'grep', 'mkdir', 'cp', 'mv', 'sed', 'awk', 'printf', 'echo', 'done')
ASSIGN = re.compile(r'^[A-Z][A-Z0-9_]*=\S*\s+(\\$|bash|env|git|[A-Z])')
LABEL = re.compile(r'^(S\d+|V\d+|\d+\.)\s+')
def is_cmd(t):
    w = t.split(' ', 1)[0]
    return w in WORDS or any(t.startswith(x) for x in ('tag=', 'out=', 'hooks=', '(cd ')) or bool(ASSIGN.match(t))
inblk = False
for n, l in enumerate(text, 1):
    s = l.strip()
    if re.match(r'^# [A-Z0-9]+-BEGIN$', s): inblk = True; continue
    if re.match(r'^# [A-Z0-9]+-END$', s): inblk = False; continue
    code = None
    if inblk: code = s
    elif l[:1] == ' ':
        t = LABEL.sub('', s)
        if is_cmd(t): code = t
    if not code: continue
    code = re.sub(r"'[^']*'", "''", code)
    code = re.sub(r'"([^"]*)"', lambda m: m.group(0) if '$(' in m.group(1) else '""', code)
    code = re.sub(r'(^|\s)#.*$', '', code)
    if code.strip(): print(f'{n}: {code}')
PY
}
FORBID='(--force|(^|[[:space:]])\+(refs/|HEAD|main|[a-z]+:)|submodule[[:space:]]+update[^|;&]*--recursive|--recurse-submodules([[:space:]]|$|=(yes|on-demand))|--no-verify|reset[[:space:]]+--hard|(^|[^A-Za-z0-9_-])rebase([^A-Za-z0-9_-]|$)|push[^|;&]*[[:space:]]-f([[:space:]]|$))'
scan_file() { # <label> <file> <mode>
  local code hits
  code="$(runnable_code "$2" "$3")"
  [ -n "$code" ] || { no "IMP-2 $1: extractor saw no runnable code (BLIND)"; return; }
  hits="$(grep -E -- "$FORBID" <<<"$code" || true)"
  [ -z "$hits" ] && ok "IMP-2 $1: no forbidden command in $(wc -l <<<"$code") runnable lines" || no "IMP-2 $1: forbidden command(s): $(head -n 3 <<<"$hits" | tr '\n' '|')"
}
scan_file latest.md "$LATEST" prompt
scan_file "follow-up 01" "$FU01" whole
scan_file "follow-up 02" "$FU02" whole
# follow-up 03 is prose only (a report template): it must stay command-free; the
# control needles below prove the extractor sees commands in the other files.
[ -s "$FU03" ] && [ -z "$(runnable_code "$FU03" whole)" ] && ok "IMP-2 follow-up 03: prose only, no runnable command" || scan_file "follow-up 03" "$FU03" whole
# control needles: the extractor really sees the runnable lines (blocks and inline)
code_l="$(runnable_code "$LATEST" prompt)"; code_2="$(runnable_code "$FU02" whole)"; code_1="$(runnable_code "$FU01" whole)"
# (quoted strings are blanked by the extractor, so "$r" reads "" in the needles)
for needle in 'rrun git push --recurse-submodules=no "" HEAD:refs/heads/main' 'rrun git submodule update --init -- ""' \
              'git submodule update --init -- submodules/constitution' 'bash submodules/constitution/scripts/update_constitution.sh --check' \
              'git -C submodules/constitution submodule update --init -- ""' 'git config -f .gitmodules --get-regexp' \
              'bootstrap.sh --non-interactive' 'git bundle verify'; do
  grep -qF -- "$needle" <<<"$code_l" && ok "IMP-2 control needle (latest.md): $needle" || no "IMP-2 extractor misses: $needle"
done
grep -qF 'bootstrap.sh --non-interactive' <<<"$code_2" && ok "IMP-2 control needle (follow-up 02): bootstrap line" || no "IMP-2 follow-up 02 bootstrap line not extracted"
grep -qF 'git submodule status submodules/constitution' <<<"$code_1" && ok "IMP-2 control needle (follow-up 01): V2 line" || no "IMP-2 follow-up 01 V2 line not extracted"
# golden-FALSE: prose rules that NAME forbidden commands are not runnable code
grep -qE 'NEVER force-push|NEVER run git submodule update --recursive|never rebase published' <<<"$code_l" \
  && no "IMP-2 prose rule extracted as code" || ok "IMP-2 golden-FALSE: prose rules 2 and 10 are not scanned as code"
grep -qE -- '--force|--recursive|rebase' <<<"$block" && ok "IMP-2 golden-FALSE precondition: the prose does mention them" || no "IMP-2 prose no longer mentions the forbidden commands"
# positive controls: an injected forbidden INLINE line (outside any block) is detected
S="$(mk_sandbox)"
for inj in 'git push --force origin HEAD:main' 'git rebase origin/main' 'git reset --hard HEAD' 'git commit --no-verify -m x' \
           'git push origin +HEAD:main' 'git submodule update --init --recursive -- x'; do
  awk -v l="  $inj" '{print} /^  If the script does not exist \(an older pin\)/{print l}' "$LATEST" >"$S/l.md"
  grep -qE -- "$FORBID" <<<"$(runnable_code "$S/l.md" prompt)" && ok "IMP-2 positive control catches: $inj" || no "IMP-2 positive control missed: $inj"
done

# =================== M-V1: STEP6B requires "post_update_hook.sh: OK" ================
S="$(mk_sandbox)"; git_q init -q "$S/p"; mkdir -p "$S/p/submodules/constitution/scripts"
printf '#!/bin/sh\necho "constitution setup check: all good"\nexit 0\n' >"$S/p/submodules/constitution/scripts/setup.sh"
run_step 6B "$S/p"; rc=$?
[ "$rc" -eq 3 ] && grep -q 'STOP: setup.sh --check-only reported a problem' "$S/p.out" \
  && ok "M-V1 STEP6B without 'post_update_hook.sh: OK' stops rc=3" || no "M-V1 STEP6B rc=$rc: $(out_of "$S/p")"
printf '#!/bin/sh\necho "post_update_hook.sh: OK"\nexit 0\n' >"$S/p/submodules/constitution/scripts/setup.sh"
run_step 6B "$S/p"; rc=$?
[ "$rc" -eq 0 ] && ok "M-V1 STEP6B golden-FALSE: 'post_update_hook.sh: OK' -> rc=0" || no "M-V1 golden-FALSE rc=$rc: $(out_of "$S/p")"

# =================== M-V6 + M-3: STEP1 exclude and secret-class files ===============
S="$(mk_sandbox)"; git_q init -q "$S/p"; P="$S/p"; mkdir -p "$P/.claude/sub" "$P/skills/x"
printf '# p\n' >"$P/CLAUDE.md"; git -C "$P" add CLAUDE.md; git -C "$P" commit -q -m init
DECOY='DECOY_SECRET_77aa'
for f in .claude/server.pem .claude/sub/id.key .claude/credentials.json skills/x/credentials .claude/.env .claude/.envrc \
         skills/x/.env.local .claude/settings.local.json; do printf 'S=%s\n' "$DECOY" >"$P/$f"; done
printf '{}\n' >"$P/.claude/settings.json"; printf 'skill\n' >"$P/skills/x/SKILL.md"
run_step 1 "$P"; rc=$?
bk="$(ls -1d "$P/.constitution-install-backup"/*/ 2>/dev/null | head -n1)"
[ "$rc" -eq 0 ] && [ -n "$bk" ] && ok "M-3 STEP1 ran (rc=0)" || no "M-3 STEP1 rc=$rc: $(out_of "$P")"
leaked="$( [ -n "$bk" ] && grep -rlF "$DECOY" "$bk" 2>/dev/null || true)"
[ -z "$leaked" ] && ok "M-3 STEP1 copied no secret-class file (*.pem *.key credentials* .env* settings.local.json)" || no "M-3 STEP1 copied secrets: $leaked"
[ -n "$bk" ] && [ -f "$bk/.claude/settings.json" ] && [ -f "$bk/skills/x/SKILL.md" ] && ok "M-3 STEP1 golden-FALSE: ordinary files still copied" || no "M-3 STEP1 ordinary files missing"
excl="$P/.git/info/exclude"
[ "$(grep -cxF '.constitution-install-backup/' "$excl" 2>/dev/null)" = 1 ] && ok "M-V6 STEP1 adds .constitution-install-backup/ to info/exclude" || no "M-V6 STEP1 exclude: $(cat "$excl" 2>/dev/null)"
[ -z "$(git -C "$P" status --porcelain -- .constitution-install-backup)" ] && ok "M-V6 STEP1 backup dir invisible to git status" || no "M-V6 backup dir visible to git"
run_step 1 "$P"
[ "$(grep -cxF '.constitution-install-backup/' "$excl")" = 1 ] && ok "M-V6 STEP1 re-run does not duplicate the exclude line" || no "M-V6 duplicate exclude line"
s1="$(blk_of STEP1 "$block")"; g4="$(blk_of STEP4G "$block")"
for pat in "*.pem" "*.key" "credentials*" ".env*" "settings.local.json"; do
  grep -qF -- "! -name '$pat'" <<<"$s1" && grep -qF -- "$pat'" <<<"$g4" && ok "M-3 STEP1 and STEP4G both exclude $pat" || no "M-3 secret exclusion $pat not in both STEP1 and STEP4G"
done

# =================== M-4: bootstrap with consent variables unset ====================
for nm in latest fu02; do
  if [ "$nm" = latest ]; then txt="$block"; else txt="$(cat "$FU02")"; fi
  bl="$(grep -E 'scripts/jev/bootstrap\.sh --non-interactive' <<<"$txt" | grep -vE '^[[:space:]]*#' || true)"
  [ -n "$bl" ] || { no "M-4 $nm: no bootstrap line"; continue; }
  bad="$(grep -vE 'env -u JEV_BOOTSTRAP_CONSENT -u JEV_BOOTSTRAP_ALLOW_CLONE -u JEV_BOOTSTRAP_INSTALL_TOOLS( | .* )JEV_HOSTED_PROBE=0 bash ' <<<"$bl" || true)"
  [ -z "$bad" ] && ok "M-4 $nm: every bootstrap run unsets the three consent variables" || no "M-4 $nm unsafe bootstrap line: $bad"
done
# behaviour: the exact STEP8 line runs a bootstrap that sees none of the variables
S="$(mk_sandbox)"; mkdir -p "$S/p/submodules/constitution/scripts/jev"
printf '#!/bin/sh\necho "C=${JEV_BOOTSTRAP_CONSENT:-unset} A=${JEV_BOOTSTRAP_ALLOW_CLONE:-unset} I=${JEV_BOOTSTRAP_INSTALL_TOOLS:-unset} P=${JEV_HOSTED_PROBE:-unset}"\n' \
  >"$S/p/submodules/constitution/scripts/jev/bootstrap.sh"
grep -E 'scripts/jev/bootstrap\.sh --non-interactive' <<<"$block" | head -n1 | sed -E 's/^[[:space:]]+//' >"$S/line.sh"
o="$(cd "$S/p" && JEV_BOOTSTRAP_CONSENT=1 JEV_BOOTSTRAP_ALLOW_CLONE=1 JEV_BOOTSTRAP_INSTALL_TOOLS=1 bash "$S/line.sh" 2>&1)"
[ "$o" = 'C=unset A=unset I=unset P=0' ] && ok "M-4 STEP8 line hides inherited consent variables from the bootstrap" || no "M-4 STEP8 bootstrap saw: $o"

# =================== M-5: STEP10 never pushes a submodule ===========================
S="$(mk_sandbox)"; git_q init -q --bare "$S/sub.git"; git_q init -q --bare "$S/up.git"
git_q init -q "$S/sw"; printf 's\n' >"$S/sw/s"; git -C "$S/sw" add s; git -C "$S/sw" commit -q -m s; git -C "$S/sw" push -q "$S/sub.git" main
git_q init -q "$S/p"; printf 'a\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init
git_q -C "$S/p" submodule add -q "$S/sub.git" sm >/dev/null 2>&1; git -C "$S/p" commit -q -m sm
printf 't\n' >"$S/p/sm/t"; git -C "$S/p/sm" add t; git -C "$S/p/sm" commit -q -m unpushed   # exists on no remote
git -C "$S/p" add sm; git -C "$S/p" commit -q -m bump
git -C "$S/p" remote add up "$S/up.git"; git -C "$S/p" config push.recurseSubmodules on-demand
git -C "$S/p/sm" remote add up "$S/sub.git"   # same remote name: on-demand WOULD push the submodule there
sub_before="$(git -C "$S/sub.git" rev-parse main)"
run_step 10 "$S/p"; rc=$?
[ "$(git -C "$S/sub.git" rev-parse main)" = "$sub_before" ] && ok "M-5 STEP10 did not push the submodule (push.recurseSubmodules=on-demand overridden)" || no "M-5 STEP10 pushed the submodule"
[ "$rc" -eq 0 ] && [ "$(git -C "$S/up.git" rev-parse main 2>/dev/null)" = "$(git -C "$S/p" rev-parse HEAD)" ] && ok "M-5 STEP10 project pushed (rc=0)" || no "M-5 STEP10 rc=$rc: $(out_of "$S/p")"

# =================== M-7: six mirrors, same order as the installer ==================
inst="$(sed -n "/^hi_upstream_table()/,/^EOF/p" "$REPO/scripts/install_constitution.sh" | awk -F'|' 'NF == 4 { print $3 }')"
hdr="$(awk '/^Clone URLs/{f=1;next} f && /^  \(SSH/{exit} f && /^  [a-z-]+ +https:/{print $2}' <<<"$block")"
s3="$(grep -oE '\$\{CONSTITUTION_URLS:-[^}]*\}' <<<"$(blk_of STEP3 "$block")" | sed -E 's/^\$\{CONSTITUTION_URLS:-//; s/\}$//' | tr ' ' '\n')"
[ "$(wc -l <<<"$inst")" -eq 6 ] && ok "M-7 control: the installer table has 6 upstreams" || no "M-7 installer table: $inst"
[ "$hdr" = "$inst" ] && ok "M-7 header mirror list = installer upstreams (6, same order)" || no "M-7 header list differs: $(tr '\n' ' ' <<<"$hdr")"
[ "$s3" = "$inst" ] && ok "M-7 STEP3 default list = installer upstreams (6, same order)" || no "M-7 STEP3 list differs: $(tr '\n' ' ' <<<"$s3")"
grep -qE '^  github-vasic +https://github.com/vasic-digital/HelixConstitution.git' <<<"$block" && ok "M-7 github-vasic named in the header" || no "M-7 github-vasic missing"

# =================== M-8: newest release = remote release tags, version order ========
RX="'^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*\$'"   # round 5 (M-7): no leading zeros
PIPE="| grep -E $RX | sort -u | sort -V | tail -n 1"
inst_rx="$(sed -nE "s/^HI_RELEASE_TAG_RE='(.*)'\$/\1/p" "$REPO/scripts/install_constitution.sh")"
upd_rx="$(grep -oE "grep -E '\^helixconstitution-v[^']*'" "$REPO/scripts/update_constitution.sh" | head -n1 | sed -E "s/^grep -E '//; s/'\$//")"
# the update script may name the regex in a variable (as the installer does) instead of inline
[ -n "$upd_rx" ] || upd_rx="$(sed -nE "s/^HI_RELEASE_TAG_RE='(.*)'\$/\1/p" "$REPO/scripts/update_constitution.sh" | head -n1)"
want_rx='^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$'
# the installer and the update script belong to another work stream (read-only here):
# a difference is REPORTED as drift (round 5, M-7), never silently passed
for pair in "installer:$inst_rx" "update script:$upd_rx"; do
  if [ "${pair#*:}" = "$want_rx" ]; then ok "M-8 ${pair%%:*} uses the prompt's release regex"
  elif [ -z "${pair#*:}" ]; then no "M-8 ${pair%%:*} release regex not found (BLIND)"
  else skip "M-8 DRIFT: ${pair%%:*} regex '${pair#*:}' differs from the prompt's '$want_rx' (owned by the installer work stream)"; fi
done
n_pipe="$(grep -cF -- "$PIPE" <<<"$block")"
[ "$n_pipe" -ge 4 ] && ok "M-8 the release pipeline appears $n_pipe times in the prompt (header, STEP2, STEP3, STEP5)" || no "M-8 release pipeline count $n_pipe < 4"
for id in STEP3 STEP5; do grep -qF -- "$PIPE" <<<"$(blk_of "$id" "$block")" && grep -qF 'ls-remote --tags --refs origin' <<<"$(blk_of "$id" "$block")" \
  && ok "M-8 $id picks from remote tags with the release pipeline" || no "M-8 $id tag choice not the remote release pipeline"; done
grep -qF -- "$PIPE" "$FU01" && grep -qF 'ls-remote --tags --refs origin' "$FU01" && ok "M-8 follow-up V3 uses the same pipeline" || no "M-8 follow-up V3 differs"
grep -qE "tag -l 'helixconstitution-v|sort=-v:refname" <<<"$block$(cat "$FU01")" && no "M-8 a local tag listing is still used to choose the release" || ok "M-8 no local-tag release choice left"
grep -E "ls-remote --tags" <<<"$block" | grep -vF -- "$PIPE" | grep -qE 'tail|head' && no "M-8 an ls-remote tag choice without the release filter" || ok "M-8 every ls-remote tag choice is filtered"
mk_tagged_remote() { # <sandbox> -> remote with v1 v2 v9 v10 v11-rc1 on a line
  local s="$1" w="$1/work" i=0 t
  git_q init -q "$w"; printf 'keep\n' >"$w/k"; git -C "$w" add k; git -C "$w" commit -q -m c0
  for t in v1 v2 v9 v10 v11-rc1; do i=$((i+1)); printf '%s\n' "$i" >"$w/f"; git -C "$w" add f; git -C "$w" commit -q -m "c$i"; git -C "$w" tag "helixconstitution-$t"; done
  git_q clone -q --bare "$w" "$s/remote.git"
}
S="$(mk_sandbox)"; mk_tagged_remote "$S"
git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"; git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
mkdir -p "$S/p/submodules"; git_q -C "$S/p" submodule add -q "$S/remote.git" submodules/constitution >/dev/null 2>&1
c="$S/p/submodules/constitution"; git -C "$c" checkout -q helixconstitution-v1; git -C "$S/p" add submodules/constitution; git -C "$S/p" commit -q -m sub
git -C "$c" tag helixconstitution-v99 helixconstitution-v1   # a LOCAL-only tag the remote never had
run_step 5 "$S/p"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$c" rev-parse HEAD)" = "$(git -C "$S/remote.git" rev-parse 'helixconstitution-v10^{commit}')" ] \
  && ok "M-8 STEP5 picks v10 (not the local-only v99, not v11-rc1, not v9 by string order)" || no "M-8 STEP5 rc=$rc HEAD=$(git -C "$c" describe --tags 2>/dev/null): $(out_of "$S/p")"
S="$(mk_sandbox)"; mk_tagged_remote "$S"
git_q init -q "$S/p"; printf '# p\n' >"$S/p/README.md"; git -C "$S/p" add README.md; git -C "$S/p" commit -q -m init
( export CONSTITUTION_URLS="$S/remote.git"; run_step 3 "$S/p" ); rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$S/p/submodules/constitution" rev-parse HEAD 2>/dev/null)" = "$(git -C "$S/remote.git" rev-parse 'helixconstitution-v10^{commit}')" ] \
  && ok "M-8 STEP3 picks v10 (not v11-rc1)" || no "M-8 STEP3 rc=$rc HEAD=$(git -C "$S/p/submodules/constitution" describe --tags 2>/dev/null): $(out_of "$S/p")"

# =================== R3: rotate lock ownership =======================================
# A .rotate.lock owned by ANOTHER uid must be refused (rsp_lock_is_safe uses [ -O ]).
# Creating a directory owned by another uid needs privileges this suite does not take,
# so this stays UNCONFIRMED here; a foreign IDENTITY in an own-uid lock is covered by
# test_rotate_hardening.sh M1 and a LIVE lock by test_rotate_chaos.sh.
skip "R3 rotate lock owned by another uid refused: needs a second uid (root); not exercised"

summary round4
