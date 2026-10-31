#!/usr/bin/env bash
# test_setup_prompt_round5.sh — regression tests for the review round 5 findings of
# docs/prompts/setup/latest.md and its follow-ups (I-1, I-2, the behaviour half of I-3, M-1..M-8).
# Each section closes a CLASS, not an instance:
#   CRED     I-1  a URL with credentials (https userinfo, token-only, malformed userinfo with '/',
#                 scp `user:TOKEN@host:path`, `ssh://user:pass@`, upper-case scheme) is never
#                 written: STEP3 skips such mirrors, STEP2/4/5 stop on such a .gitmodules URL,
#                 STEP7A refuses such a helix-deps.yaml; after the runs .gitmodules, the staged
#                 .gitmodules, .git/config and .git/modules/*/config hold no decoy token.
#                 Golden-FALSE: `git@host:path` and `ssh://git@host/...` are NOT credentials.
#   REDACT   M-1/M-8/R-NOG  the ONE redaction expression: a matrix of URL forms (two URLs on a
#                 line, scp, malformed, token-only) and identity of every copy in the prompt and
#                 the follow-ups; every remote-contacting git line is redacted, silenced or rrun.
#   ALLOW    I-2  the allow-list analyser (git_allowlist.py): OK on the real files, control needles,
#                 every listed bypass form caught inline AND in a block (allowlist_bypass_forms.py,
#                 which builds the destructive payloads in Python), PROSE-NEG positive + golden-FALSE,
#                 BLIND on a file without runnable code.
#   BOOT     M-2  the bootstrap line runs with JEV_BOOTSTRAP_MODE=shadow and every consent / agent /
#                 mode variable of the caller removed (STEP8 and follow-up 02).
#   SECRETS  M-3  STEP1 never copies, and STEP4G never greps, any secret-class file.
#   UNPUSHED M-5  the one "unpushed" rule: a commit only a LOCAL tag holds is unpushed, a commit a
#                 REMOTE tag holds is pushed, an unpushed local branch counts, no answering remote = rc 1.
#   WORDING  M-6  "six upstreams on four hosts"; no "five hosts".
#   REGEX    M-7  one release regex everywhere, leading zeros rejected (v010 is not v10).
#   STEP1    I-3  S1-EXCL-CLOBBER: info/exclude keeps its content; S1-NOCHMOD: an existing backup
#                 root becomes mode 700.
#   RRUN     I-3  S3-RRUN-RC0: rrun returns the command's own exit status, output redacted.
# Env: R5_LATEST, R5_FU01, R5_FU02 (files under test), R5_AL (analyser under test), R5_SECT (comma list; default all sections).
# Nothing outside mktemp -d sandboxes is written; GIT_ALLOW_PROTOCOL=file; $HOME untouched.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND=false
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }
LATEST="${R5_LATEST:-$REPO/docs/prompts/setup/latest.md}"
FU01="${R5_FU01:-$REPO/docs/prompts/setup/followups/01_verify_incorporation.md}"
FU02="${R5_FU02:-$REPO/docs/prompts/setup/followups/02_wire_decision_layer_optional.md}"
ALPY="${R5_AL:-$REPO/tests/prompts/git_allowlist.py}"   # the analyser under test (mutation runs override it)
SECT=",${R5_SECT:-CRED,REDACT,ALLOW,BOOT,SECRETS,UNPUSHED,WORDING,REGEX,STEP1,RRUN},"
on() { case "$SECT" in *",$1,"*) return 0 ;; esac; return 1; }
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || { no "PROMPT block extracted"; summary round5; exit 1; }
blk_of() { awk -v b="# $1-BEGIN" -v e="# $1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$2"; }
run_step() { printf '%s\n' "$(blk_of "STEP$1" "$block")" >"$2.sh"; ( cd "$2" && bash "$2.sh" ) >"$2.out" 2>&1; }
TOK='R5_DECOY_TOKEN_77'
mk_remote() {
  local s="$1" w="$1/work"
  git_q init -q "$w"; printf 'one\n' >"$w/f"; printf 'keep\n' >"$w/k"; git -C "$w" add f k; git -C "$w" commit -q -m c1
  git -C "$w" tag helixconstitution-v1; printf 'two\n' >"$w/f"; git -C "$w" commit -q -am c2; git -C "$w" tag helixconstitution-v2
  git_q clone -q --bare "$w" "$s/remote.git"
}
mk_new() { git_q init -q "$1/p"; printf '# p\n' >"$1/p/README.md"; git -C "$1/p" add README.md; git -C "$1/p" commit -q -m init; }
mk_full() { # <S> <subpath>
  mk_remote "$1"; git_q init -q "$1/p0"; printf '# p\n' >"$1/p0/README.md"; git -C "$1/p0" add README.md; git -C "$1/p0" commit -q -m init
  [ "$2" = constitution ] || mkdir -p "$1/p0/submodules"
  git_q -C "$1/p0" submodule add -q "$1/remote.git" "$2" >/dev/null 2>&1
  git -C "$1/p0/$2" checkout -q helixconstitution-v1; git -C "$1/p0" add "$2"; git -C "$1/p0" commit -q -m sub
  git_q clone -q --recurse-submodules "$1/p0" "$1/p" >/dev/null 2>&1
}
store_clean() { # <label> <project dir>: the decoy is in no store git or the prompt writes
  local p="$2" hit="" f
  for f in "$p/.gitmodules" "$p/.git/config" "$p/helix-deps.yaml"; do [ -f "$f" ] && grep -qF "$TOK" "$f" && hit="$hit ${f#"$p"/}"; done
  while IFS= read -r f; do grep -qF "$TOK" "$f" && hit="$hit ${f#"$p"/}"; done < <(find "$p/.git/modules" -name config -type f 2>/dev/null)
  git -C "$p" show :.gitmodules 2>/dev/null | grep -qF "$TOK" && hit="$hit index:.gitmodules"
  git -C "$p" show :helix-deps.yaml 2>/dev/null | grep -qF "$TOK" && hit="$hit index:helix-deps.yaml"
  [ -z "$hit" ] && ok "$1: decoy in no store (.gitmodules, index, .git/config, modules/*/config, helix-deps.yaml)" || no "$1: decoy STORED in:$hit"
}
no_tok() { if grep -qF "$TOK" "$2"; then no "$1: decoy PRINTED: $(grep -F "$TOK" "$2" | head -n1 | cut -c1-140)"; else ok "$1: decoy never printed"; fi; }
CREDFORMS=("https://x-access-token:$TOK@example.invalid/a.git" "https://$TOK@example.invalid/b.git"
           "https://u:TO/$TOK@example.invalid/c.git" "user:$TOK@example.invalid:o/d.git"
           "ssh://u:$TOK@example.invalid/e.git" "HTTPS://u:$TOK@example.invalid/f.git"
           "https://example.invalid/g.git?private_token=$TOK" "https://example.invalid/h.git?ref=x&Access_Token=$TOK")   # round 7 M-d: query tokens

# ================================================================== CRED (I-1)
if on CRED; then
  S="$(mk_sandbox)"; mk_remote "$S"; mk_new "$S"
  ( export CONSTITUTION_URLS="${CREDFORMS[*]} git@nohost.invalid:o/x.git ssh://git@nohost.invalid/x.git $S/remote.git"; run_step 3 "$S/p" ); rc=$?
  [ "$rc" -eq 0 ] && [ -f "$S/p/submodules/constitution/k" ] && grep -qF "using mirror: $S/remote.git" "$S/p.out" \
    && ok "CRED STEP3: every credential mirror skipped, the plain mirror used (rc=0)" || no "CRED STEP3 rc=$rc: $(cat "$S/p.out")"
  n="$(grep -c '^skipped (carries credentials, never stored): ' "$S/p.out")"
  [ "$n" -eq "${#CREDFORMS[@]}" ] && ok "CRED STEP3: $n of ${#CREDFORMS[@]} credential forms reported skipped" || no "CRED STEP3: $n skipped lines, want ${#CREDFORMS[@]}"
  grep -qF 'unreachable: git@nohost.invalid:o/x.git' "$S/p.out" && grep -qF 'unreachable: ssh://***@nohost.invalid/x.git' "$S/p.out" \
    && ok "CRED golden-FALSE: git@host:path and ssh://git@host are not credentials (tried, unreachable)" || no "CRED golden-FALSE: ssh forms not tried: $(cat "$S/p.out")"
  nu="$(grep -c '^unreachable: ' "$S/p.out")"   # a credential URL must never be CONTACTED (ls-remote would send the token)
  [ "$nu" -eq 2 ] && ok "CRED STEP3: no credential mirror was contacted (only the 2 plain ssh mirrors were tried)" \
    || no "CRED STEP3: $nu mirrors tried, want 2 (a credential URL was contacted): $(grep '^unreachable: ' "$S/p.out" | head -n3 | tr '\n' ' ')"
  no_tok "CRED STEP3 output" "$S/p.out"; store_clean "CRED STEP3" "$S/p"
  fails=0
  for i in "${!CREDFORMS[@]}"; do   # STEP2/4/5 stop on each form in the tracked .gitmodules
    for st in 2 4 5; do
      sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
      S="$(mk_sandbox)"; mk_full "$S" "$sp"; before="$(git -C "$S/p/$sp" rev-parse HEAD)"
      git -C "$S/p" config -f .gitmodules submodule.other.path other; git -C "$S/p" config -f .gitmodules submodule.other.url "${CREDFORMS[$i]}"
      run_step "$st" "$S/p"; rc=$?
      if ! { [ "$rc" -eq 3 ] && grep -q '^STOP: .gitmodules (submodule.other.url) holds a URL with credentials' "$S/p.out" \
             && [ "$(git -C "$S/p/$sp" rev-parse HEAD 2>/dev/null)" = "$before" ]; }; then
        fails=$((fails + 1)); no "CRED STEP$st form $i not refused rc=$rc: $(tail -n1 "$S/p.out")"; fi
      grep -qF "$TOK" "$S/p.out" && { fails=$((fails + 1)); no "CRED STEP$st form $i printed the decoy"; }
      grep -qF "$TOK" "$S/p/.git/config" && { fails=$((fails + 1)); no "CRED STEP$st form $i wrote the decoy to .git/config"; }
    done
  done
  [ "$fails" -eq 0 ] && ok "CRED STEP2/4/5: ${#CREDFORMS[@]} forms x 3 steps refused, nothing moved, printed or stored"
  S="$(mk_sandbox)"; mk_full "$S" submodules/constitution   # golden-FALSE: an ssh scp URL is not a credential
  git -C "$S/p" config -f .gitmodules submodule.other.path other; git -C "$S/p" config -f .gitmodules submodule.other.url 'git@github.com:o/x.git'
  run_step 5 "$S/p"; rc=$?
  grep -q 'holds a URL with credentials' "$S/p.out" && no "CRED golden-FALSE: git@github.com:o/x.git refused as a credential" || ok "CRED golden-FALSE: git@github.com:o/x.git is not a credential (STEP5 rc=$rc)"
  fake_verifier() { mkdir -p "$1/submodules/constitution/scripts/deps_manifest"; printf '#!/bin/sh\nexit 0\n' >"$1/submodules/constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh"; }
  fails=0
  for i in "${!CREDFORMS[@]}"; do   # STEP7A refuses each form in helix-deps.yaml and stages nothing
    S="$(mk_sandbox)"; mk_new "$S"; fake_verifier "$S/p"
    printf 'schema_version: 1\ndeps:\n  - name: x\n    ssh_url: %s\n' "${CREDFORMS[$i]}" >"$S/p/helix-deps.yaml"
    run_step 7A "$S/p"; rc=$?
    if ! { [ "$rc" -eq 3 ] && ! git -C "$S/p" show :helix-deps.yaml >/dev/null 2>&1; }; then fails=$((fails + 1)); no "CRED STEP7A form $i rc=$rc (staged or not refused)"; fi
  done
  [ "$fails" -eq 0 ] && ok "CRED STEP7A: ${#CREDFORMS[@]} forms refused, nothing staged"
  S="$(mk_sandbox)"; mk_new "$S"; fake_verifier "$S/p"
  printf 'schema_version: 1\ndeps:\n  - name: x\n    ssh_url: git@github.com:vasic-digital/X.git\n  - name: y\n    ssh_url: ssh://git@github.com/vasic-digital/Y.git\n' >"$S/p/helix-deps.yaml"
  run_step 7A "$S/p"; rc=$?
  [ "$rc" -eq 0 ] && git -C "$S/p" show :helix-deps.yaml >/dev/null 2>&1 && ok "CRED golden-FALSE STEP7A: ssh URLs are staged (rc=0)" || no "CRED golden-FALSE STEP7A rc=$rc: $(cat "$S/p.out")"
  for st in 2 4 5; do   # clean fixtures, decoy only in CONSTITUTION_URLS: nothing stored
    sp=submodules/constitution; [ "$st" = 4 ] && sp=constitution
    S="$(mk_sandbox)"; mk_full "$S" "$sp"
    ( export CONSTITUTION_URLS="${CREDFORMS[0]}"; run_step "$st" "$S/p" ); store_clean "CRED STEP$st clean run" "$S/p"
  done
fi

# ================================================================== REDACT (M-1, M-8, R-NOG)
if on REDACT; then
  R="$(sed -nE "s/^ *redact\(\) \{ sed -E '(.*)'; \}.*/\1/p" <<<"$(blk_of STEP5 "$block")")"
  [ -n "$R" ] && ok "REDACT canonical expression read from STEP5" || no "REDACT canonical expression not found (BLIND)"
  fails=0; n=0
  while IFS='|' read -r in want; do
    n=$((n + 1)); got="$(printf '%s\n' "$in" | sed -E "$R")"
    [ "$got" = "$want" ] || { fails=$((fails + 1)); no "REDACT '$in' -> '$got' (want '$want')"; }
  done <<EOF
fatal: clone of 'https://x:$TOK@a.invalid/r.git' and 'https://y:$TOK@b.invalid/s.git' failed|fatal: clone of 'https://***@a.invalid/r.git' and 'https://***@b.invalid/s.git' failed
https://u:TO/$TOK@h.invalid/x|https://***@h.invalid/x
user:$TOK@h.invalid:o/x.git|***@h.invalid:o/x.git
see user:$TOK@h.invalid:o/x.git now|see ***@h.invalid:o/x.git now
a:$TOK@h.invalid:o b:$TOK@k.invalid:p|***@h.invalid:o ***@k.invalid:p
https://$TOK@h.invalid/x|https://***@h.invalid/x
ssh://git@h.invalid/x|ssh://***@h.invalid/x
HTTPS://u:$TOK@h.invalid/x|HTTPS://***@h.invalid/x
git@github.com:o/x.git|git@github.com:o/x.git
origin	git@github.com:o/x.git (fetch)|origin	git@github.com:o/x.git (fetch)
no url here: a:b c@d|no url here: a:b c@d
https://h.invalid/x?private_token=$TOK|https://h.invalid/x?private_token=***
https://h.invalid/x?a=1&access_token=$TOK&b=2|https://h.invalid/x?a=1&access_token=***&b=2
https://h.invalid/x?API_KEY=$TOK|https://h.invalid/x?API_KEY=***
https://h.invalid/x?user=a;password=$TOK|https://h.invalid/x?user=a;password=***
https://h.invalid/x?ref=main&depth=1|https://h.invalid/x?ref=main&depth=1
EOF
  [ "$fails" -eq 0 ] && ok "REDACT matrix: $n inputs, every credential form redacted, every ssh/prose form unchanged"
  all="$(cat "$LATEST" "$FU01" "$FU02")"
  n_all="$(grep -c '://\*\*\*@' <<<"$all")"; n_can="$(grep -cF -- "$R" <<<"$all")"
  [ "$n_all" -ge 10 ] && [ "$n_all" -eq "$n_can" ] && ok "REDACT identity: all $n_all redaction lines use the canonical expression" \
    || no "REDACT identity: $n_all lines redact, $n_can canonical: $(grep '://\*\*\*@' <<<"$all" | grep -vF -- "$R" | head -n3 | cut -c1-120)"
  # class: every RUNNABLE unit (blocks + inline command lines, as git_allowlist.py extracts them)
  # that contacts a remote is redacted, silenced, or run through rrun
  units="$( { python3 -I "$ALPY" units "$LATEST" prompt
             python3 -I "$ALPY" units "$FU01" whole
             python3 -I "$ALPY" units "$FU02" whole; } 2>/dev/null)"
  remote="$(grep -E '\bgit\b.*\b(ls-remote|fetch|push|clone|submodule (add|update)|remote -v)\b' <<<"$units")"
  bad=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$l" in *'rrun '*|*"$R"*|*'>/dev/null 2>&1'*|*'2>/dev/null'*) ;; *) bad="$bad
  $l" ;; esac
  done <<<"$remote"
  # every unit that prints matching LINES of project files (git grep -n) is redacted too (M-4)
  greps="$(grep -E '\bgit grep\b.* -n' <<<"$units")"
  while IFS= read -r l; do [ -n "$l" ] || continue; case "$l" in *"$R"*) ;; *) bad="$bad
  [prints file lines] $l" ;; esac; done <<<"$greps"
  [ -n "$greps" ] && ok "REDACT control: $(grep -c . <<<"$greps") line-printing git grep unit(s) found" || no "REDACT control: no line-printing git grep unit found (BLIND)"
  nr="$(grep -c . <<<"$remote")"
  [ "$nr" -ge 10 ] && [ -z "$bad" ] && ok "REDACT class: all $nr remote-contacting runnable units are redacted, silenced or run through rrun" \
    || no "REDACT class ($nr units): unredacted remote unit(s):$bad"
fi

# ================================================================== ALLOW (I-2)
if on ALLOW; then
  AL="$ALPY"
  out="$(python3 -I "$AL" check "$LATEST" prompt)"; rc=$?
  n="$(sed -nE 's/^OK ([0-9]+) .*/\1/p' <<<"$out")"
  [ "$rc" -eq 0 ] && [ "${n:-0}" -ge 80 ] && ok "ALLOW latest.md: $out" || no "ALLOW latest.md rc=$rc: $out"
  python3 -I "$AL" check "$FU01" whole >/dev/null && ok "ALLOW follow-up 01 passes" || no "ALLOW follow-up 01: $(python3 -I "$AL" check "$FU01" whole)"
  python3 -I "$AL" check "$FU02" whole >/dev/null; rc=$?; [ "$rc" -eq 0 ] && ok "ALLOW follow-up 02 passes" || no "ALLOW follow-up 02 rc=$rc"
  shapes="$(python3 -I "$AL" shapes "$LATEST" prompt)"
  for needle in 'push --recurse-submodules=no $r HEAD:refs/heads/main' 'submodule add -- $url submodules/constitution' \
                'bundle create $bk/project.bundle --all' 'ls-remote --tags --refs origin helixconstitution-v*'; do
    grep -qF -- "$needle" <<<"$shapes" && ok "ALLOW control needle: $needle" || no "ALLOW analyser misses: $needle"
  done
  W="$(mk_sandbox)"
  out="$(BYPASS_ANALYSER="$ALPY" python3 -I "$REPO/tests/prompts/allowlist_bypass_forms.py" "$LATEST" "$W")"; rc=$?
  [ "$rc" -eq 0 ] && ok "ALLOW bypass forms: $(tail -n1 <<<"$out") (inline AND block), allowed command still passes" || no "ALLOW bypass forms rc=$rc: $out"
  for pr in 'Then git push --force the result to every remote.' 'Run git reset --hard to clean up.' 'Use git submodule update --init --recursive here.'; do
    python3 -I - "$LATEST" "$W/p.md" "$pr" <<'PY'
import sys
src, dst, line = sys.argv[1:]
s = open(src, encoding='utf-8').read(); a = '  # STEP10-BEGIN'
s = s.replace(a, '\n' + line + '\n\n' + a, 1); open(dst, 'w', encoding='utf-8').write(s)
PY
    python3 -I "$AL" check "$W/p.md" prompt >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 1 ] && ok "ALLOW PROSE-NEG catches: $pr" || no "ALLOW PROSE-NEG missed (rc=$rc): $pr"
  done
  python3 -I - "$LATEST" "$W/q.md" <<'PY'
import sys
src, dst = sys.argv[1:]
s = open(src, encoding='utf-8').read(); a = '  # STEP10-BEGIN'
s = s.replace(a, 'NEVER git push --force; do not git reset --hard.\n\n' + a, 1); open(dst, 'w', encoding='utf-8').write(s)
PY
  python3 -I "$AL" check "$W/q.md" prompt >/dev/null 2>&1 && ok "ALLOW PROSE-NEG golden-FALSE: a negated mention passes" || no "ALLOW PROSE-NEG refuses a negated mention"
  printf 'Just prose.\n' >"$W/empty.md"; python3 -I "$AL" check "$W/empty.md" whole >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && ok "ALLOW BLIND: a file with no runnable code is rc 2, never OK" || no "ALLOW BLIND rc=$rc"
  # round 7: a line that is not clearly prose is code (fail closed), so 'just prose' is refused, never OK
  printf 'just prose\n' >"$W/empty2.md"; python3 -I "$AL" check "$W/empty2.md" whole >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ok "ALLOW AMBIGUOUS: a line not clearly prose is refused (rc $rc), never OK" || no "ALLOW AMBIGUOUS rc=0"
fi

# ================================================================== BOOT (M-2)
if on BOOT; then
  for src in "$LATEST" "$FU02"; do
    bl="$(grep -m1 -E '^\s*(2\. )?env -u JEV_BOOTSTRAP_CONSENT .*bootstrap\.sh --non-interactive' "$src" | sed -E 's/^\s*(2\. )?//')"
    [ -n "$bl" ] || { no "BOOT bootstrap line not found in ${src##*/}"; continue; }
    S="$(mk_sandbox)"; mkdir -p "$S/p/submodules/constitution/scripts/jev"
    cat >"$S/p/submodules/constitution/scripts/jev/bootstrap.sh" <<'SH'
#!/bin/sh
for v in JEV_BOOTSTRAP_MODE JEV_BOOTSTRAP_AGENTS JEV_BOOTSTRAP_CONSENT JEV_BOOTSTRAP_ALLOW_CLONE JEV_BOOTSTRAP_INSTALL_TOOLS JEV_BOOTSTRAP_DOWNLOAD_PROFILE JEV_HOSTED_PROBE; do
  eval "x=\${$v-UNSET}"; printf '%s=%s\n' "$v" "$x"
done
SH
    printf '%s\n' "$bl" >"$S/boot.sh"
    out="$(cd "$S/p" && env JEV_BOOTSTRAP_MODE=enforce JEV_BOOTSTRAP_AGENTS=claude JEV_BOOTSTRAP_CONSENT=yes JEV_BOOTSTRAP_ALLOW_CLONE=1 \
           JEV_BOOTSTRAP_INSTALL_TOOLS=1 JEV_BOOTSTRAP_DOWNLOAD_PROFILE=big bash "$S/boot.sh" 2>&1)"
    want='JEV_BOOTSTRAP_MODE=shadow
JEV_BOOTSTRAP_AGENTS=UNSET
JEV_BOOTSTRAP_CONSENT=UNSET
JEV_BOOTSTRAP_ALLOW_CLONE=UNSET
JEV_BOOTSTRAP_INSTALL_TOOLS=UNSET
JEV_BOOTSTRAP_DOWNLOAD_PROFILE=UNSET
JEV_HOSTED_PROBE=0'
    [ "$out" = "$want" ] && ok "BOOT ${src##*/}: caller's enforce/agents/consent removed, MODE=shadow" || no "BOOT ${src##*/}: $(tr '\n' ' ' <<<"$out")"
  done
fi

# ================================================================== SECRETS (M-3)
if on SECRETS; then
  SECRET_FILES=(.env settings.local.json a.pem a.key credentials.json .credentials.json id_rsa id_rsa.pub id_ed25519 id_ecdsa id_dsa a.p12 a.pfx my_token.txt API_TOKEN gh-Secret.yml client_secret.json)
  S="$(mk_sandbox)"; mk_new "$S"; mkdir -p "$S/p/.claude/sub" "$S/p/skills/x"
  for f in "${SECRET_FILES[@]}"; do printf 'constitution/x\n' >"$S/p/.claude/sub/$f"; printf 'constitution/x\n' >"$S/p/skills/x/$f"; done
  printf '{}\n' >"$S/p/.claude/settings.json"; printf '# s\n' >"$S/p/skills/x/SKILL.md"
  run_step 1 "$S/p"; rc=$?
  bk="$(sed -nE 's/^backup: (.*)/\1/p' "$S/p.out")"
  copied="$(cd "$S/p/${bk:-/nonexistent}" 2>/dev/null && find .claude skills -type f | sort | tr '\n' ' ')"
  [ "$rc" -eq 0 ] && [ "$copied" = ".claude/settings.json skills/x/SKILL.md " ] && ok "SECRETS STEP1: ${#SECRET_FILES[@]} secret classes not copied, plain files copied" || no "SECRETS STEP1 rc=$rc copied: $copied"
  printf 'see constitution/x\n' >"$S/p/plain.md"
  printf '[submodule "c"]\n\tpath = submodules/constitution\n\turl = git@h:o/c.git\n' >"$S/p/.gitmodules"
  run_step 4G "$S/p"; rc=$?
  hits="$(grep -E '^[^ ]+:[0-9]+$' "$S/p.out" | cut -d: -f1 | sort | tr '\n' ' ')"
  [ "$hits" = ".gitmodules plain.md " ] || [ "$hits" = "plain.md .gitmodules " ] || [ "$hits" = "plain.md " ] \
    && ok "SECRETS STEP4G: only plain files counted, no secret-class file grepped ($hits)" || no "SECRETS STEP4G counted: $hits"
  grep -q 'control needle: .gitmodules:[1-9]' "$S/p.out" && ok "SECRETS STEP4G control needle sees .gitmodules" || no "SECRETS STEP4G control needle: $(grep 'control needle' "$S/p.out")"
fi

# ================================================================== UNPUSHED (M-5)
if on UNPUSHED; then
  fn="$(awk '/^ *unpushed\(\) \{/{f=1} f{print} f&&/^ *\}$/{exit}' <<<"$(blk_of STEP5 "$block")")"
  [ -n "$fn" ] && ok "UNPUSHED helper read from STEP5" || no "UNPUSHED helper not found (BLIND)"
  S="$(mk_sandbox)"; mk_remote "$S"; git_q clone -q "$S/remote.git" "$S/c" 2>/dev/null; c="$S/c"
  printf '%s\n' "$fn" >"$S/unpushed.sh"
  up() { ( . "$S/unpushed.sh"; unpushed "$c" ); }
  git -C "$c" checkout -q --detach helixconstitution-v2
  [ -z "$(up)" ] && ok "UNPUSHED clean clone: nothing unpushed" || no "UNPUSHED clean clone lists: $(up)"
  printf 'l\n' >"$c/l"; git -C "$c" add l; git -C "$c" commit -q -m local; git -C "$c" tag local-only
  [ -n "$(up)" ] && ok "UNPUSHED a commit only a LOCAL tag holds is unpushed" || no "UNPUSHED local-tag commit counted as pushed"
  git -C "$S/work" checkout -q --detach helixconstitution-v2; printf 'r\n' >"$S/work/r"; git -C "$S/work" add r; git -C "$S/work" commit -q -m rt
  git -C "$S/work" tag remote-only-tag; git_q -C "$S/work" push -q "$S/remote.git" refs/tags/remote-only-tag
  git -C "$c" fetch -q origin refs/tags/remote-only-tag:refs/tags/remote-only-tag; git -C "$c" checkout -q --detach remote-only-tag
  [ -z "$(up)" ] && ok "UNPUSHED a commit a REMOTE tag holds is pushed" || no "UNPUSHED remote-tag commit listed: $(up)"
  git -C "$c" checkout -q -b side; printf 's\n' >"$c/s"; git -C "$c" add s; git -C "$c" commit -q -m side; git -C "$c" checkout -q --detach remote-only-tag
  [ -n "$(up)" ] && ok "UNPUSHED an unpushed local branch is listed although HEAD is pushed" || no "UNPUSHED side branch not listed"
  git -C "$c" remote set-url origin "$S/gone.git"; up >/dev/null; rc=$?
  [ "$rc" -eq 1 ] && ok "UNPUSHED no answering remote: rc 1 (never 'nothing unpushed')" || no "UNPUSHED dead remote rc=$rc"
  n="$(grep -c 'tag that a REMOTE has' "$LATEST")"   # the prose rule (the helper copies carry a comment, checked by the identity test)
  [ "$n" -eq 1 ] && ok "UNPUSHED the rule is stated once in the prose" || no "UNPUSHED rule stated $n times"
fi

# ================================================================== WORDING (M-6)
if on WORDING; then
  tr '\n' ' ' <"$LATEST" | tr -s ' ' | grep -qF 'six upstreams on four hosts' && ok "WORDING six upstreams on four hosts" || no "WORDING the six/four statement is missing"
  if grep -qiE 'five hosts' "$LATEST" "$FU01" "$FU02"; then no "WORDING 'five hosts' still present"; else ok "WORDING no 'five hosts'"; fi
fi

# ================================================================== REGEX (M-7)
if on REGEX; then
  RX='^helixconstitution-v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$'
  n="$(grep -oF -- "$RX" "$LATEST" | wc -l)"; n1="$(grep -oF -- "$RX" "$FU01" | wc -l)"
  any="$(grep -ohE "'\^helixconstitution-v[^']*'" "$LATEST" "$FU01" | sort -u)"
  [ "$n" -ge 4 ] && [ "$n1" -ge 1 ] && [ "$(wc -l <<<"$any")" -eq 1 ] && ok "REGEX one release regex everywhere ($n in latest.md, $n1 in follow-up 01)" \
    || no "REGEX copies: latest=$n fu01=$n1 distinct=$(tr '\n' ' ' <<<"$any")"
  fails=0
  for t in v0:1 v1:1 v10:1 v1.0:1 v2.10.3:1 v010:0 v01:0 v1.02:0 v1.:0 v1-rc1:0 v:0 v1..2:0; do
    if grep -qE -- "$RX" <<<"helixconstitution-${t%%:*}"; then g=1; else g=0; fi
    [ "$g" = "${t##*:}" ] || { fails=$((fails + 1)); no "REGEX helixconstitution-${t%%:*}: match=$g want ${t##*:}"; }
  done
  [ "$fails" -eq 0 ] && ok "REGEX accept/reject table: 12 tags, leading zeros rejected"
fi

# ================================================================== STEP1 (I-3)
if on STEP1; then
  S="$(mk_sandbox)"; mk_new "$S"; mkdir -p "$S/p/.git/info"; printf 'keepme\n*.log\n' >"$S/p/.git/info/exclude"
  mkdir "$S/p/.constitution-install-backup"; chmod 755 "$S/p/.constitution-install-backup"
  run_step 1 "$S/p"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(cat "$S/p/.git/info/exclude")" = $'keepme\n*.log\n.constitution-install-backup/' ] \
    && ok "STEP1 info/exclude keeps its content and gains the entry once" || no "STEP1 exclude rc=$rc: $(tr '\n' '|' <"$S/p/.git/info/exclude")"
  [ "$(stat -c %a "$S/p/.constitution-install-backup")" = 700 ] && ok "STEP1 an existing backup root becomes mode 700" || no "STEP1 backup root mode $(stat -c %a "$S/p/.constitution-install-backup")"
  run_step 1 "$S/p"
  [ "$(grep -c '^.constitution-install-backup/$' "$S/p/.git/info/exclude")" -eq 1 ] && grep -qx keepme "$S/p/.git/info/exclude" \
    && ok "STEP1 second run: entry still once, content kept" || no "STEP1 second run exclude: $(tr '\n' '|' <"$S/p/.git/info/exclude")"
fi

# ================================================================== RRUN (I-3)
if on RRUN; then
  W="$(mk_sandbox)"
  for st in STEP2 STEP3 STEP4 STEP5 STEP10; do
    grep -E '^ *(redact|rrun)\(\) \{' <<<"$(blk_of "$st" "$block")" >"$W/$st.defs"
    [ "$(wc -l <"$W/$st.defs")" -eq 2 ] || { no "RRUN $st: redact/rrun not both defined"; continue; }
    o="$(. "$W/$st.defs"; rrun sh -c "echo 'see https://u:$TOK@h.invalid/x'; exit 7"; echo "rc=$?")"
    [ "$o" = $'see https://***@h.invalid/x\nrc=7' ] && ok "RRUN $st: exit status 7 kept, output redacted" || no "RRUN $st: $(tr '\n' '|' <<<"$o")"
    o="$(. "$W/$st.defs"; rrun true; echo "rc=$?")"; [ "$o" = "rc=0" ] || no "RRUN $st: silent success printed '$o'"
  done
fi
summary round5
