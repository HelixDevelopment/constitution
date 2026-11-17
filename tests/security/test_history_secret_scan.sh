#!/usr/bin/env bash
# test_history_secret_scan.sh -- hermetic tests for scripts/security/history_secret_scan.sh.
#
# Purpose: drive the REAL script on throwaway local git repositories with a fake
# gitleaks (tests/security/fixtures/bin/gitleaks + fake_gitleaks.py) that reads
# the real `git log -p` of the scanned repository: a clean scan, a secret only
# in a second remote's deleted history, scanner crashes, a scanner blind on the
# bare mirror, a scanner that ignores merge diffs, always-blind / always-find
# scanners, an inconsistent exit, missing prerequisites (safe_rm.sh, jq), no
# scanner, usage errors, credential-carrying URLs, the exact-match --keys-file
# pass with its controls, and value-free output. Fabricated tokens are built at
# run time (no token-shaped literal in this file).
# Gate-logic tests only (§11.4.289): they prove the script's decisions, never
# what the real gitleaks finds.
#
# Usage: bash tests/security/test_history_secret_scan.sh
#        HSS_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        SEC_TEST_FAILFAST=1 stops at the first failing case (used by the mutation test)
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
# shellcheck disable=SC2034  # RC and EXPECT_* are read inside the eval'd check strings
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${HSS_SCRIPT:-$here/scripts/security/history_secret_scan.sh}"
FIX="$here/tests/security/fixtures"
for t in git jq python3; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
export SEC_TEST_LOG="$tmp/log"; mkdir -p "$SEC_TEST_LOG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
check(){ if eval "$2"; then ok "$1"; else nok "$1"; sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -30; fi; }
fake_tok(){ printf 'gh%s_%s' p "$(python3 -I -c 'import secrets,string;a=string.ascii_letters+string.digits;print("".join(secrets.choice(a) for _ in range(36)))')"; }

mkrepo(){ # DIR [secret-in-history]
  git init -q "$1"; git -C "$1" commit -q --allow-empty -m init
  echo hello > "$1/readme.txt"; git -C "$1" add readme.txt; git -C "$1" commit -qm readme
  if [ "${2:-}" = secret ]; then
    printf 'TOKEN=%s\n' "$(fake_tok)" > "$1/leak.env"; git -C "$1" add leak.env; git -C "$1" commit -qm leak
    git -C "$1" rm -q leak.env; git -C "$1" commit -qm unleak
  fi
}
mkrepo "$tmp/clean"; mkrepo "$tmp/second" secret
KV="kv$(python3 -I -c 'import secrets;print(secrets.token_hex(12))')"
mkrepo "$tmp/withkey"; printf 'cfg=%s\n' "$KV" > "$tmp/withkey/cfg.txt"; git -C "$tmp/withkey" add cfg.txt; git -C "$tmp/withkey" commit -qm cfg

SCR="$tmp/scratch"; mkdir -p "$SCR"
declare -a RUN_ENV=()
run(){
  : > "$SEC_TEST_LOG/gitleaks_argv.log"; rm -f "$SCR"/*.tsv
  env PATH="$FIX/bin:$PATH" SCRATCH="$SCR" OUT="$SCR/out.tsv" ${RUN_ENV[@]+"${RUN_ENV[@]}"} bash "$SCRIPT" "$@" > "$tmp/out" 2> "$tmp/err"; RC=$?
}
leftover(){ find "$SCR" -maxdepth 1 -name 'hss.*' | wc -l; }
tokleak(){ grep -rqE 'ghp_[A-Za-z0-9]{36}' "$tmp/out" "$tmp/err" "$SCR" 2>/dev/null; }

# ---- honest scanner ------------------------------------------------------------------------------
RUN_ENV=(); run "$tmp/clean"
check "clean repo -> exit 0, findings=0" '[ $RC -eq 0 ] && grep -q "findings=0" "$tmp/out" && [ ! -s "$SCR/out.tsv" ]'
check "needles reported OK on the clean run" 'grep -q "control OK" "$tmp/out"'
check "work directory removed" '[ "$(leftover)" = 0 ]'
check "scanner called with --redact and --log-opts=--all -m on the bare mirror" 'grep -q -- "--redact" "$SEC_TEST_LOG/gitleaks_argv.log" && grep -q -- "--log-opts=--all -m .*m\.git$" "$SEC_TEST_LOG/gitleaks_argv.log"'
check "exactly one scanner run" '[ "$(wc -l < "$SEC_TEST_LOG/gitleaks_argv.log")" = 1 ]'
RUN_ENV=(); run "$tmp/clean" "$tmp/second"
check "secret only in the 2nd remote (deleted later) -> exit 1, one finding" '[ $RC -eq 1 ] && [ "$(wc -l < "$SCR/out.tsv")" = 1 ] && grep -q "leak.env:1" "$SCR/out.tsv"'
check "needle findings are not in the report" '! grep -q __hss_needle__ "$SCR/out.tsv"'
check "no token value in stdout, stderr or any output file" '! tokleak'

# ---- scanner failures and blindness -------------------------------------------------------------
RUN_ENV=(FAKE_GITLEAKS_MODE=crash_after_empty); run "$tmp/clean"
check "scanner exits 126 after writing [] -> SCANNER-ERROR 6" '[ $RC -eq 6 ] && grep -q SCANNER-ERROR "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=crash_nofile); run "$tmp/clean"
check "scanner crash without report -> 6" '[ $RC -eq 6 ]'
check "work directory removed after a failure" '[ "$(leftover)" = 0 ]'
RUN_ENV=(FAKE_GITLEAKS_MODE=blind_bare); run "$tmp/clean" "$tmp/second"
check "scanner blind on the bare mirror -> BLIND 3 (needles live in the mirror)" '[ $RC -eq 3 ] && grep -q BLIND "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=allblind); run "$tmp/clean"
check "always-blind scanner -> 3" '[ $RC -eq 3 ]'
RUN_ENV=(FAKE_GITLEAKS_MODE=rc0_nofile); run "$tmp/clean"
check "scanner exit 0 with no report -> SCANNER-ERROR 6, never clean" '[ $RC -eq 6 ] && grep -q SCANNER-ERROR "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=tip_only); run "$tmp/clean"
check "tip-only scanner (no history) -> BLIND 3 on the history needle first" '[ $RC -eq 3 ] && grep -q "history needle was not found" "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=drop_pos); run "$tmp/clean"
check "scanner misses only the history needle -> BLIND 3 naming it" '[ $RC -eq 3 ] && grep -q "history needle was not found" "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=drop_merge); run "$tmp/clean"
check "scanner misses only the merge-only needle -> BLIND 3 naming it" '[ $RC -eq 3 ] && grep -q "merge-only needle was not found" "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=allfind); run "$tmp/clean"
check "always-find scanner -> 3 (negative needle)" '[ $RC -eq 3 ] && grep -q "negative needle" "$tmp/err"'
RUN_ENV=(FAKE_GITLEAKS_MODE=rc0_findings); run "$tmp/clean" "$tmp/second"
check "exit 0 with findings (inconsistent) -> 6" '[ $RC -eq 6 ]'
NOM="$tmp/nom"; mkdir -p "$NOM"
printf '#!/usr/bin/env bash\nargs=(); for a in "$@"; do case "$a" in --log-opts=*) a="--log-opts=--all";; esac; args+=("$a"); done\nexec "%s" "${args[@]}"\n' "$FIX/bin/gitleaks" > "$NOM/gitleaks"; chmod +x "$NOM/gitleaks"
RUN_ENV=(GITLEAKS="$NOM/gitleaks"); run "$tmp/clean"
check "scanner that drops -m (merge diffs) -> BLIND 3 on the merge needle" '[ $RC -eq 3 ] && grep -q "merge-only needle" "$tmp/err"'

# ---- prerequisites and usage ---------------------------------------------------------------------
RUN_ENV=(SAFE_RM="$tmp/nonexistent/safe_rm.sh"); run "$tmp/clean"
check "missing safe_rm.sh -> 5 (not 1)" '[ $RC -eq 5 ] && grep -q "missing prerequisite: safe_rm" "$tmp/err"'
NB="$tmp/nojq"; mkdir -p "$NB"
for tool in bash env git python3 mktemp stat sed grep sort cut head wc date dirname awk comm find cat ls rm readlink basename tr; do
  p=$(command -v "$tool" 2>/dev/null) && [ "${p#/}" != "$p" ] && ln -sf "$p" "$NB/$tool"
done
ln -sf "$FIX/bin/gitleaks" "$NB/gitleaks"
env PATH="$NB" SCRATCH="$SCR" OUT="$SCR/out.tsv" "$NB/bash" "$SCRIPT" "$tmp/clean" > "$tmp/out" 2> "$tmp/err"; RC=$?
check "jq missing -> 5" '[ $RC -eq 5 ] && grep -q "missing prerequisite: jq" "$tmp/err"'
NG="$tmp/nogl"; mkdir -p "$NG"; cp -a "$NB/." "$NG/"; rm -f "$NG/gitleaks"; ln -sf "$(command -v jq)" "$NG/jq"
env PATH="$NG" SCRATCH="$SCR" OUT="$SCR/out.tsv" "$NG/bash" "$SCRIPT" "$tmp/clean" > "$tmp/out" 2> "$tmp/err"; RC=$?
check "no scanner -> 4, nothing downloaded" '[ $RC -eq 4 ] && grep -q "no scanner" "$tmp/err"'
RUN_ENV=(); run
check "no URL -> 2" '[ $RC -eq 2 ]'
env -u SCRATCH PATH="$FIX/bin:$PATH" bash "$SCRIPT" "$tmp/clean" > "$tmp/out" 2> "$tmp/err"; RC=$?
check "SCRATCH unset -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(); run "https://user:secretpw@example.invalid/r.git"
check "URL with user:password -> 2, URL not printed" '[ $RC -eq 2 ] && ! grep -q secretpw "$tmp/out" "$tmp/err"'
RUN_ENV=(); run "https://tokenonly@example.invalid/r.git"
check "https URL with a user part -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(); run --bogus "$tmp/clean"
check "unknown option -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(); run "$tmp/does-not-exist"
check "unreachable remote -> git error 7" '[ $RC -eq 7 ]'

# ---- exact-match pass ---------------------------------------------------------------------------
KF="$tmp/keys.sh"
printf 'export KEY_A=%s\nexport KEY_B=%s\nexport PLACE=YOUR_TOKEN_HERE_123456\n' "$KV" "absent$(python3 -I -c 'import secrets;print(secrets.token_hex(12))')" > "$KF"; chmod 600 "$KF"
RUN_ENV=(); run --keys-file "$KF" "$tmp/withkey"
check "--keys-file is performed: KEY_A found, KEY_B not, exit 1" '[ $RC -eq 1 ] && [ "$(awk -F"\t" "\$1==\"KEY_A\"{print \$2}" "$SCR/out.tsv.keys.tsv")" -ge 1 ] && [ "$(awk -F"\t" "\$1==\"KEY_B\"{print \$2}" "$SCR/out.tsv.keys.tsv")" = 0 ]'
check "placeholder value skipped, controls not in the output" '[ -s "$SCR/out.tsv.keys.tsv" ] && ! grep -q -e "^PLACE" -e "__HSS_CONTROL" "$SCR/out.tsv.keys.tsv"'
check "no key value anywhere in stdout, stderr or output" '! grep -rqF "$KV" "$tmp/out" "$tmp/err" "$SCR"'
check "key value never in any process argv recorded by the scanner shim" '! grep -qF "$KV" "$SEC_TEST_LOG/gitleaks_argv.log"'
RUN_ENV=(); run --keys-file "$KF" "$tmp/clean"
check "--keys-file on a repo without the values -> exit 0" '[ $RC -eq 0 ] && [ -s "$SCR/out.tsv.keys.tsv" ] && [ "$(awk -F"\t" "\$2>0" "$SCR/out.tsv.keys.tsv" | wc -l)" = 0 ]'
cp "$KF" "$tmp/keys644"; chmod 644 "$tmp/keys644"
RUN_ENV=(); run --keys-file "$tmp/keys644" "$tmp/clean"
check "group/other-readable keys file -> 2" '[ $RC -eq 2 ]'

# ---- round 2 (review r2 F4/F5) --------------------------------------------------------------------
# A secret reachable ONLY from a tag of the 2nd remote (no branch points at it).
mkrepo "$tmp/tagsec"
git -C "$tmp/tagsec" checkout -q -b tmpleak
printf 'TOKEN=%s\n' "$(fake_tok)" > "$tmp/tagsec/tagleak.env"; git -C "$tmp/tagsec" add tagleak.env; git -C "$tmp/tagsec" commit -qm tagleak
git -C "$tmp/tagsec" tag v-leak; git -C "$tmp/tagsec" checkout -q -; git -C "$tmp/tagsec" branch -qD tmpleak
RUN_ENV=(); run "$tmp/clean" "$tmp/tagsec"
check "secret reachable only from a tag of the 2nd remote -> found, exit 1" '[ $RC -eq 1 ] && grep -q "tagleak.env:1" "$SCR/out.tsv"'
RUN_ENV=(); run "ssh://u:secretpw@example.invalid/r.git"
check "non-http URL with user:password (ssh://u:pw@) -> 2, URL not printed" '[ $RC -eq 2 ] && ! grep -q secretpw "$tmp/out" "$tmp/err"'
RUN_ENV=(); run "git+ssh://u:secretpw@example.invalid/r.git"
check "git+ssh://u:pw@ -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(FAKE_GITLEAKS_CHATTER=1); run "$tmp/clean" "$tmp/second"
check "scanner console output is kept off the console (only the value-free summary is printed)" '[ $RC -eq 1 ] && ! grep -q "fake-gitleaks:" "$tmp/out" "$tmp/err"'
# A matcher that cannot see the blobs (cat-file --batch-all-objects answers nothing) must be BLIND.
BG="$tmp/blindgit"; mkdir -p "$BG"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = --batch-all-objects ] && exit 0; done\nexec "%s" "$@"\n' "$(command -v git)" > "$BG/git"; chmod +x "$BG/git"
env PATH="$BG:$FIX/bin:$PATH" SCRATCH="$SCR" OUT="$SCR/out.tsv" bash "$SCRIPT" --keys-file "$KF" "$tmp/clean" > "$tmp/out" 2> "$tmp/err"; RC=$?
check "exact-match pass blind to the blobs -> BLIND 3 (present control not found)" '[ $RC -eq 3 ] && grep -q "exact-match control value was not found" "$tmp/err"'
KS="$tmp/keys_short.sh"; cp "$KF" "$KS"; printf 'export KEY_SHORT=abc123\n' >> "$KS"; chmod 600 "$KS"
RUN_ENV=(); run --keys-file "$KS" "$tmp/clean"
check "short keys-file values are not searched and are counted in a note (names only)" '[ $RC -eq 0 ] && grep -q "not searched: 1 shorter than 12 characters (KEY_SHORT)" "$tmp/out" && ! grep -q "^KEY_SHORT" "$SCR/out.tsv.keys.tsv" && ! grep -q abc123 "$tmp/out" "$tmp/err"'
check "placeholder values are counted in the note" 'grep -q "1 placeholder (PLACE)" "$tmp/out"'


# ---- round 3 (review r3 F4) ------------------------------------------------------------------------
cp "$KF" "$tmp/keys640"; chmod 640 "$tmp/keys640"
RUN_ENV=(); run --keys-file "$tmp/keys640" "$tmp/clean"
check "group-readable (0640) keys file -> 2, no scan" '[ $RC -eq 2 ] && grep -q "readable by group/others (640)" "$tmp/err" && [ ! -s "$SEC_TEST_LOG/gitleaks_argv.log" ]'
cp "$KF" "$tmp/keys604"; chmod 604 "$tmp/keys604"
RUN_ENV=(); run --keys-file "$tmp/keys604" "$tmp/clean"
check "other-readable (0604) keys file -> 2" '[ $RC -eq 2 ]'
# An exact-match matcher that reports EVERY value as found (python3 shim replacing only the matcher)
# must trip the negative control: BLIND 3, never "found".
AF="$tmp/allfindpy"; mkdir -p "$AF"; REALPY=$(command -v python3)
cat > "$AF/python3" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in *__HSS_SKIP_SHORT__*)
    exec "$REALPY" -I -c 'import sys
raw = sys.stdin.buffer.read().split(b"\0")
for i in range(0, len(raw) - 1, 2):
    print("%s\t1" % raw[i].decode())
print("__HSS_SKIP_SHORT__\t0\t"); print("__HSS_SKIP_PLACE__\t0\t")' ;;
  esac
done
exec "$REALPY" "\$@"
EOF
chmod +x "$AF/python3"
env PATH="$AF:$FIX/bin:$PATH" SCRATCH="$SCR" OUT="$SCR/out.tsv" bash "$SCRIPT" --keys-file "$KF" "$tmp/clean" > "$tmp/out" 2> "$tmp/err"; RC=$?
check "always-find exact matcher -> BLIND 3 (negative control found)" '[ $RC -eq 3 ] && grep -q "exact-match negative control was found" "$tmp/err"'

echo "RESULT: $((n-bad))/$n passed"
[ "$bad" -eq 0 ]
