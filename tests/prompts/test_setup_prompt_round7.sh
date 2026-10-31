#!/usr/bin/env bash
# test_setup_prompt_round7.sh — regression tests for the review round 7 findings (setup prompt,
# follow-ups, allow-list analyser, rotation script). Every test was written first and observed RED
# against the unfixed files. Sections (env R7_SECT, comma list; default all):
#   ALLOW    I-1  the analyser is a closed allow-list of command WORDS: every bypass form of the
#                 driver (allowlist_bypass_forms.py: wrappers, interpreters, aliases, computed
#                 command words, env injection, git -C elsewhere, file writers, prose-continuation
#                 lines) is refused (BAD rc 1 or BLIND rc 2) as a block line, an inline line and
#                 the next line of an unfinished prose sentence; golden-FALSE stays OK; the four
#                 shipped files pass; a file without code is BLIND (rc 2), never OK.
#   VOCAB    I-1  no prose-start word of the analyser is a command on this host (PATH, builtin or
#                 keyword), and no prose line of the shipped prompts starts with one.
#   NEEDLE   I-2  S7 / V6 exclusion needle prints 3; an inverted filter prints 4, no filter 7, a
#                 substring filter 1 (four different values, §11.4.273(f)); the P10 mutant
#                 (-vcE -> -cE on every S7 filter) is caught.
#   SYMLINK  M-a  STEP 1 refuses a symlinked .constitution-install-backup: rc 3, the link target
#                 keeps its mode and stays empty.
#   LSREMOTE M-e  a CONSTITUTION_URLS word that is an option (--upload-pack=...) runs nothing;
#                 control: the same option WITHOUT "--" does run (the probe can fire).
#   STAGED   M-f  a --source swapped during the lock window for a file without a PROMPT block is
#                 refused (rc 3); latest.md, the history and the lock are untouched.
#   DIRTY    M-g  inside a git work tree a dirty setup directory is refused by default (rc 3);
#                 --allow-dirty proceeds; a clean tree and a non-git directory proceed.
#   TAKEOVER M-b  a recoverer paused after it judged the lock stale never releases the lock of a
#                 NEW live owner (identity and liveness re-checked by an exclusive takeover).
#   NOTE     M-c  the round-5 note no longer claims that .git/config is checked.
#   SIZE     M-h  S13 tells the agent not to re-run the prompt.
# Nothing outside mktemp -d sandboxes is written; GIT_ALLOW_PROTOCOL=file; $HOME untouched.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND=false CONSTITUTION_JEV_HOOK=off
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }
LATEST="${R7_LATEST:-$REPO/docs/prompts/setup/latest.md}"
FU01="${R7_FU01:-$REPO/docs/prompts/setup/followups/01_verify_incorporation.md}"
FU02="${R7_FU02:-$REPO/docs/prompts/setup/followups/02_wire_decision_layer_optional.md}"
FU03="${R7_FU03:-$REPO/docs/prompts/setup/followups/03_final_report.md}"
AL="${R7_AL:-$REPO/tests/prompts/git_allowlist.py}"
SCRIPT="${R7_ROTATE:-$ROTATE}"
SECT=",${R7_SECT:-ALLOW,VOCAB,NEEDLE,SYMLINK,LSREMOTE,STAGED,DIRTY,TAKEOVER,NOTE,SIZE},"
on() { case "$SECT" in *",$1,"*) return 0 ;; esac; return 1; }
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || { no "PROMPT block extracted"; summary round7; exit 1; }
blk_of() { awk -v b="# $1-BEGIN" -v e="# $1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$2"; }
run_txt() { printf '%s\n' "$1" >"$2.sh"; ( cd "$2" && bash "$2.sh" ) >"$2.out" 2>&1; }
mk_new() { git_q init -q "$1/p"; printf '# p\n' >"$1/p/README.md"; git -C "$1/p" add README.md; git -C "$1/p" commit -q -m init; }

# ================================================================== ALLOW (I-1)
if on ALLOW; then
  W="$(mk_sandbox)"
  out="$(BYPASS_ANALYSER="$AL" python3 -I "$REPO/tests/prompts/allowlist_bypass_forms.py" "$LATEST" "$W")"; rc=$?
  n="$(sed -n 's/^CAUGHT \([0-9]*\) OF \([0-9]*\)$/\1 \2/p' <<<"$out")"
  [ "$rc" -eq 0 ] && [ -n "$n" ] && [ "${n% *}" = "${n#* }" ] && [ "${n#* }" -ge 400 ] \
    && ok "ALLOW every bypass form refused in 3 positions, golden-FALSE OK ($(tail -n1 <<<"$out"))" \
    || no "ALLOW bypass driver rc=$rc: $(grep -E '^(MISS|GOLDEN)' <<<"$out" | head -n5 | tr '\n' ' ') $(tail -n1 <<<"$out")"
  for pair in "$LATEST:prompt" "$FU01:whole" "$FU02:whole"; do
    f="${pair%:*}"; m="${pair##*:}"
    o="$(python3 -I "$AL" check "$f" "$m")"; rc=$?
    [ "$rc" -eq 0 ] && ok "ALLOW ${f##*/} passes ($(tail -n1 <<<"$o" | cut -c1-60))" || no "ALLOW ${f##*/} rc=$rc: $(grep -vE '^OK' <<<"$o" | head -n3 | tr '\n' ' ')"
  done
  python3 -I "$AL" check "$FU03" whole >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && ok "ALLOW 03_final_report.md (no code) is BLIND rc 2, never OK" || no "ALLOW FU03 rc=$rc"
  # the allowed removal is exactly rm -rf -- "${tmpdir:?}"; a trailing dot or slash-dot is refused
  for f in 'rm -rf -- "${tmpdir:?}"' ; do
    printf '# x\n\n```\n%s\n```\n' "$f" >"$W/rm_ok.md"
    python3 -I "$AL" check "$W/rm_ok.md" whole >/dev/null 2>&1 && ok "ALLOW golden-FALSE: $f is allowed" || no "ALLOW $f refused"
  done
  for f in 'rm -rf -- "${tmpdir:?}".' 'rm -rf -- "${tmpdir:?}/."' 'rm -rf -- "${tmpdir:?}"/..' 'rm -rf -- "${tmp:?}"'; do
    printf '# x\n\n```\n%s\n```\n' "$f" >"$W/rm_bad.md"
    python3 -I "$AL" check "$W/rm_bad.md" whole >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] && ok "ALLOW $f refused (rc $rc)" || no "ALLOW $f accepted"
  done
fi

# ================================================================== VOCAB (I-1)
if on VOCAB; then
  o="$(python3 -I - "$AL" "$LATEST" "$FU01" "$FU02" "$FU03" <<'PY'
import importlib.util, re, shutil, subprocess, sys
spec = importlib.util.spec_from_file_location('al', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
bi = set(subprocess.run(['bash', '-c', 'compgen -b; compgen -k'], capture_output=True, text=True).stdout.split())
iscmd = lambda w: w in bi or shutil.which(w) is not None
bad = sorted(w for w in m.PROSE_WORDS if iscmd(w))
print('VOCAB-WORDS', len(m.PROSE_WORDS), 'commands:', ' '.join(bad) or '-')
miss = sorted(w for w in ('rm', 'mv', 'dd', 'sh', 'bash', 'eval', 'exec', 'sudo', 'perl', 'python3', 'xargs', 'tee',
                          'find', 'sed', 'awk', 'curl', 'then', 'do', 'done', 'in', 'if', 'for', 'source') if w not in m.CMD_LIKE)
print('CMDLIKE-MISSING', ' '.join(miss) or '-')
n = 0
for path, mode in ((sys.argv[2], 'prompt'), (sys.argv[3], 'whole'), (sys.argv[4], 'whole'), (sys.argv[5], 'whole')):
    code, prose = m.units(path, mode)
    for ln, s in prose:
        t = m.LABEL.sub('', s).lstrip('(\'"`')
        w = re.sub(r"[,.;:)\]\"'`]+$", "", t.split()[0]) if t.split() else ''
        if re.fullmatch(r"[a-z][a-z0-9_-]*", w) and iscmd(w):
            n += 1; print('PROSE-STARTS-WITH-COMMAND', path.rsplit('/', 1)[-1], ln, w)
print('PROSE-COMMAND-LINES', n)
PY
)"
  grep -q '^VOCAB-WORDS [0-9]* commands: -$' <<<"$o" && ok "VOCAB no prose-start word is a command on this host ($(grep '^VOCAB' <<<"$o"))" || no "VOCAB $(grep '^VOCAB' <<<"$o")"
  grep -q '^CMDLIKE-MISSING -$' <<<"$o" && ok "VOCAB the command-word list covers the named dangerous words and keywords" || no "VOCAB $(grep '^CMDLIKE' <<<"$o")"
  grep -q '^PROSE-COMMAND-LINES 0$' <<<"$o" && ok "VOCAB no prose line of the four files starts with a command word" || no "VOCAB $(grep '^PROSE-STARTS' <<<"$o" | head -n5 | tr '\n' ' ')"
fi

# ================================================================== NEEDLE (I-2)
if on NEEDLE; then
  for which in S7 V6; do
    if [ "$which" = S7 ]; then code="$(blk_of S7 "$block")"; else code="$(blk_of V6 "$(cat "$FU01")")"; fi
    S="$(mk_sandbox)"; P="$S/p"; mkdir -p "$P"; printf '# p\n' >"$P/CLAUDE.md"
    run_txt "$code" "$P"; o="$(cat "$P.out")"
    grep -qx "$which needle exclusion: 3" <<<"$o" && ok "NEEDLE $which correct filter prints 3" || no "NEEDLE $which: $o"
    # each wrong filter must print a DIFFERENT value
    US=$'\x1f'
    for v in "inverted${US}grep -vcE \"\$lx\")\"   # legacy probe lines${US}grep -cE \"\$lx\")\"   # legacy probe lines${US}4" \
             "nofilter${US} | grep -vcE \"\$lx\")\"   # legacy probe lines${US} | grep -c .)\"   # legacy probe lines${US}7" \
             "substring${US}lx='(^|[^A-Za-z0-9_])[Ll][Ee][Gg][Aa][Cc][Yy]([^A-Za-z0-9_]|\$)'${US}lx='[Ll][Ee][Gg][Aa][Cc][Yy]'${US}1"; do
      IFS="$US" read -r nm old new want <<<"$v"
      mut="$(python3 -I -c 'import sys; s=sys.stdin.read(); o,n=sys.argv[1],sys.argv[2]; assert o in s, o; print(s.replace(o,n), end="")' "$old" "$new" <<<"$code")" \
        || { no "NEEDLE $which $nm: mutation did not apply"; continue; }
      run_txt "$mut" "$P"; got="$(sed -n "s/^$which needle exclusion: //p" "$P.out")"
      [ "$got" = "$want" ] && [ "$got" != 3 ] && ok "NEEDLE $which $nm filter prints $got (not 3)" || no "NEEDLE $which $nm printed '$got', want $want"
    done
  done
  # P10 (round-6 survivor): every -vcE "$lx" of S7 inverted; the round-3 I5 oracle must now FAIL
  W="$(mk_sandbox)"; cp "$LATEST" "$W/latest.md"
  python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); i=s.index("# S7-BEGIN"); j=s.index("# S7-END"); seg=s[i:j]; assert "-vcE \"$lx\"" in seg; open(p,"w").write(s[:i]+seg.replace("-vcE \"$lx\"","-cE \"$lx\"")+s[j:])' "$W/latest.md"
  o="$(R3_LATEST="$W/latest.md" R3_ONLY=I5 bash "$REPO/tests/prompts/test_setup_prompt_round3.sh" 2>&1)"; rc=$?
  { [ "$rc" -ne 0 ] && grep -q 'needles' <<<"$o"; } && ok "NEEDLE P10 (S7 filter inverted) is caught by the round-3 needle oracle" || no "NEEDLE P10 survived (rc=$rc): $(grep -E '^FAIL' <<<"$o" | head -n2 | tr '\n' ' ')"
fi

# ================================================================== SYMLINK (M-a)
if on SYMLINK; then
  S="$(mk_sandbox)"; mk_new "$S"; mkdir -p "$S/outside"; chmod 755 "$S/outside"
  ln -s "$S/outside" "$S/p/.constitution-install-backup"
  run_txt "$(blk_of STEP1 "$block")" "$S/p"; rc=$?
  m="$(stat -c %a "$S/outside")"; n="$(find "$S/outside" -mindepth 1 | wc -l)"
  [ "$rc" -eq 3 ] && [ "$m" = 755 ] && [ "$n" -eq 0 ] && tail -n1 "$S/p.out" | grep -q 'is a symlink' \
    && ok "SYMLINK STEP1 refuses a symlinked backup root: rc 3, target mode 755, target empty" \
    || no "SYMLINK rc=$rc mode=$m entries=$n: $(tail -n2 "$S/p.out" | tr '\n' ' ')"
  S="$(mk_sandbox)"; mk_new "$S"; run_txt "$(blk_of STEP1 "$block")" "$S/p"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(stat -c %a "$S/p/.constitution-install-backup")" = 700 ] && ok "SYMLINK golden-FALSE: a normal run still backs up (rc 0, mode 700)" || no "SYMLINK golden-FALSE rc=$rc"
fi

# ================================================================== LSREMOTE (M-e)
if on LSREMOTE; then
  S="$(mk_sandbox)"; git_q init -q --bare "$S/remote.git"
  ( cd "$S" && git_q init -q work && cd work && printf 'k\n' >k && git add k && git commit -q -m c && git push -q "$S/remote.git" HEAD:main ) >/dev/null 2>&1
  printf '#!/bin/sh\n: >"%s/MARKER"\nexec git-upload-pack "$@"\n' "$S" >"$S/evil.sh"; chmod 700 "$S/evil.sh"
  # control needle: without "--" the option is honoured, so the probe CAN fire
  git ls-remote --exit-code "--upload-pack=$S/evil.sh" "$S/remote.git" HEAD >/dev/null 2>&1
  [ -e "$S/MARKER" ] && ok "LSREMOTE control: the option form fires without \"--\" (marker created)" || no "LSREMOTE control: the probe cannot fire (BLIND)"
  rm -f -- "${S:?}/MARKER"
  mk_new "$S"
  ( export CONSTITUTION_URLS="--upload-pack=$S/evil.sh $S/remote.git"; run_txt "$(blk_of STEP3 "$block")" "$S/p" ); rc=$?
  [ ! -e "$S/MARKER" ] && ok "LSREMOTE STEP3: an option-shaped URL word runs nothing (no marker)" || no "LSREMOTE STEP3 ran the upload-pack program"
  grep -qF "using mirror: $S/remote.git" "$S/p.out" && [ "$rc" -eq 0 ] && ok "LSREMOTE STEP3: the next, plain mirror is used (rc 0)" || no "LSREMOTE STEP3 rc=$rc: $(tail -n3 "$S/p.out" | tr '\n' ' ')"
fi

# ================================================================== STAGED (M-f)
if on STAGED; then
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc fresh >"$S/new.md"; before="$(tree_digest "$D")"
  ( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=after_lock ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=2 \
      bash "$SCRIPT" swapped --source "$S/new.md" --dir "$D" >"$S/o" 2>&1; echo $? >"$S/rc" ) &
  sleep 0.8; printf '# no prompt block here\n\nplain text\n' >"$S/new.md"; wait
  rc="$(cat "$S/rc")"
  [ "$rc" -eq 3 ] && [ "$(tree_digest "$D")" = "$before" ] && [ ! -e "$D/.rotate.lock" ] \
    && ok "STAGED a source swapped during the lock window is refused (rc 3), nothing changed, no lock left" \
    || no "STAGED rc=$rc lock=$([ -e "$D/.rotate.lock" ] && echo yes || echo no): $(cat "$S/o" | tr '\n' ' ' | cut -c1-200)"
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc fresh >"$S/new.md"
  bash "$SCRIPT" golden --source "$S/new.md" --dir "$D" >"$S/o" 2>&1; rc=$?
  [ "$rc" -eq 0 ] && cmp -s "$D/latest.md" "$S/new.md" && ok "STAGED golden-FALSE: an unchanged source rotates (rc 0)" || no "STAGED golden-FALSE rc=$rc: $(cat "$S/o")"
fi

# ================================================================== DIRTY (M-g)
if on DIRTY; then
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
  git_q -C "$S" init -q; git -C "$S" add -A; git -C "$S" commit -q -m base
  expect_rc "DIRTY clean git tree rotates by default" 0 bash "$SCRIPT" clean_one --dir "$D"
  git -C "$S" add -A; git -C "$S" commit -q -m rotated
  printf 'edit\n' >>"$D/latest.md"; before="$(tree_digest "$D")"
  expect_rc "DIRTY dirty setup directory refused by default" 3 bash "$SCRIPT" dirty_one --dir "$D"
  [ "$(tree_digest "$D")" = "$before" ] && ok "DIRTY refusal wrote nothing" || no "DIRTY refusal changed the tree"
  expect_rc "DIRTY --allow-dirty proceeds" 0 bash "$SCRIPT" dirty_two --allow-dirty --dir "$D"
  S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
  expect_rc "DIRTY a directory outside any git work tree proceeds" 0 env GIT_CEILING_DIRECTORIES="$S" bash "$SCRIPT" nogit --dir "$D"
fi

# ================================================================== TAKEOVER (M-b)
if on TAKEOVER; then
  dead_pid() { local p; true & p=$!; wait "$p"; printf '%s\n' "$p"; }
  bad=0
  for round in 1 2 3; do
    S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"; prompt_doc b >"$S/b.md"; prompt_doc c >"$S/c.md"; prompt_doc a >"$S/a.md"
    mkdir "$D/.rotate.lock"; printf '%s deadbeef\n' "$(dead_pid)" >"$D/.rotate.lock/pid"; touch -d '1 hour ago' "$D/.rotate.lock"
    # A judges the lock stale, then pauses before it acts on that judgement
    ( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=before_recover ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=3 \
        bash "$SCRIPT" a_run --source "$S/a.md" --dir "$D" >"$S/oa" 2>&1; echo $? >"$S/ra" ) &
    sleep 0.7
    bash "$SCRIPT" b_run --source "$S/b.md" --dir "$D" >"$S/ob" 2>&1; echo $? >"$S/rb"     # B recovers and rotates
    # C takes the lock and holds it while A wakes up
    ( ROTATE_SETUP_PROMPT_TEST_MODE=1 ROTATE_SETUP_PROMPT_TEST_PAUSE_AT=after_lock ROTATE_SETUP_PROMPT_TEST_PAUSE_SEC=4 \
        bash "$SCRIPT" c_run --source "$S/c.md" --dir "$D" >"$S/oc" 2>&1; echo $? >"$S/rc" ) &
    wait
    ra="$(cat "$S/ra")"; rb="$(cat "$S/rb")"; rcc="$(cat "$S/rc")"
    scan="$(ROTATE_SETUP_PROMPT_SOURCE_ONLY=1 bash -c '. "$1"; rsp_scan_numbering "$2" 2>&1 && echo CLEAN' _ "$SCRIPT" "$D")"
    if [ "$ra" -eq 3 ] && [ "$rb" -eq 0 ] && [ "$rcc" -eq 0 ] && cmp -s "$D/latest.md" "$S/c.md" && grep -q '^CLEAN$' <<<"$scan" && [ ! -e "$D/.rotate.lock" ]; then
      :
    else
      bad=$((bad + 1))
      printf 'round %s: A=%s B=%s C=%s lock_left=%s latest_is_c=%s\n  A: %s\n  C: %s\n' "$round" "$ra" "$rb" "$rcc" \
        "$([ -e "$D/.rotate.lock" ] && echo yes || echo no)" "$(cmp -s "$D/latest.md" "$S/c.md" && echo yes || echo no)" \
        "$(tr '\n' ' ' <"$S/oa" | cut -c1-200)" "$(tr '\n' ' ' <"$S/oc" | cut -c1-200)"
    fi
  done
  [ "$bad" -eq 0 ] && ok "TAKEOVER 3 rounds: a paused stale-lock recoverer never released a new live owner's lock" || no "TAKEOVER $bad of 3 rounds broke the new owner"
fi

# ================================================================== NOTE (M-c)
if on NOTE; then
  sect="$(awk '/^## Review round 5/{f=1} /^## Review round 6|^## Review round 7|^## When not/{if(f)exit} f' "$LATEST")"
  if grep -qE 'stop when `\.gitmodules` or the[[:space:]]*$' <<<"$sect" || grep -qzE 'or the[[:space:]]+local `\.git/config` carries one' <<<"$sect"; then
    no "NOTE the round-5 note still claims .git/config is checked"
  else
    grep -q 'only `.gitmodules` is read' <<<"$sect" && ok "NOTE round-5 note corrected: only .gitmodules is read" || no "NOTE correction text missing"
  fi
fi

# ================================================================== SIZE (M-h)
if on SIZE; then
  s13="$(awk '/^  S13 /{f=1} f&&/^If any line FAILs/{exit} f' <<<"$block")"
  grep -q 'do NOT' <<<"$s13" && ! grep -q 're-running this prompt' <<<"$s13" \
    && ok "SIZE S13 runs S1..S9 only and forbids re-running the prompt" || no "SIZE S13: $s13"
  sz="$(printf '%s\n' "$block" | wc -c)"
  [ "$sz" -le 68000 ] && ok "SIZE PROMPT block is $sz bytes (ceiling 68000)" || no "SIZE PROMPT block grew to $sz bytes"
fi

summary round7
