#!/usr/bin/env bash
# test_history_secret_scan_replace.sh -- hermetic tests for the replace-ref
# handling of scripts/security/history_secret_scan.sh (CON-425).
#
# Purpose: a refs/replace/<id> entry makes git tools show another object in
# place of <id>, and `git clone --mirror` copies refs/replace/*. Before
# CON-425 a secret blob replaced by a clean blob (or by a tree), or a secret
# commit replaced by a clean commit, was invisible to BOTH passes: the
# exact-match matcher (`git cat-file --batch`) and the scanner (`git log -p`).
# This test drives the REAL script on throwaway repositories that carry such
# replace refs and checks: the secret is found by the exact-match pass and by
# the scanner pass (exit 1); every replace ref of the mirror and of a second
# remote is listed in $OUT.replace.tsv (ids only) and counted as a finding;
# a caller's core.useReplaceRefs=true does not turn replace refs back on; the
# scanner process gets GIT_NO_REPLACE_OBJECTS; and a git that still honours
# replace refs (a shim that drops the setting) makes the type check in the
# matcher stop the run with exit 7 instead of counting a tree as a blob.
# Gate-logic tests only (§11.4.289): fake gitleaks
# (tests/security/fixtures/fake_gitleaks.py), local repositories, real git and
# python3. Fabricated values are random per run and built with python3 (no
# secret-shaped literal in this file).
#
# Usage: bash tests/security/test_history_secret_scan_replace.sh
#        HSS_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        SEC_TEST_FAILFAST=1 stops at the first failing case
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
# shellcheck disable=SC2034  # RC is read inside the eval'd check strings
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${HSS_SCRIPT:-$here/scripts/security/history_secret_scan.sh}"
FIX="$here/tests/security/fixtures"
for t in git jq python3 timeout; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
export SEC_TEST_LOG="$tmp/log"; mkdir -p "$SEC_TEST_LOG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
check(){ if eval "$2"; then ok "$1"; else nok "$1"; sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -30; fi; }

# Fake values (random per run): FV is a searched value (> 12 characters), TK a
# github-pat-shaped fake token the fake scanner flags.
FV=$(python3 -I -c 'import secrets;print("rpl"+secrets.token_hex(12))')
TK=$(python3 -I -c 'import secrets,string;a=string.ascii_letters+string.digits;print("gh"+"p_"+"".join(secrets.choice(a) for _ in range(36)))')

secret_repo(){ # DIR -> a repo whose only commit holds s.env with FV and TK; prints the blob id
  git init -q "$1"; printf 'K=%s\nT=%s\n' "$FV" "$TK" > "$1/s.env"; git -C "$1" add s.env; git -C "$1" commit -qm s
  git -C "$1" rev-parse HEAD:s.env
}
# (a) secret blob replaced by a clean blob
RB="$tmp/rblob"; sb=$(secret_repo "$RB"); cb=$(printf 'clean\n' | git -C "$RB" hash-object -w --stdin); git -C "$RB" replace "$sb" "$cb"
# (b) secret blob force-replaced by a tree (type-changing replace)
RT="$tmp/rtree"; tb=$(secret_repo "$RT"); git -C "$RT" replace -f "$tb" "$(git -C "$RT" rev-parse 'HEAD^{tree}')"
# (c) secret commit replaced by a clean commit; the secret is deleted in the next commit
RC_="$tmp/rcommit"; git init -q "$RC_"; printf 'K=%s\nT=%s\n' "$FV" "$TK" > "$RC_/s.env"; git -C "$RC_" add s.env; git -C "$RC_" commit -qm s
c1=$(git -C "$RC_" rev-parse HEAD); git -C "$RC_" rm -q s.env; echo ok > "$RC_/o.txt"; git -C "$RC_" add o.txt; git -C "$RC_" commit -qm o
alt=$(printf 'clean\n' | git -C "$RC_" hash-object -w --stdin)
alt=$(printf '100644 blob %s\tc.txt\n' "$alt" | git -C "$RC_" mktree); alt=$(git -C "$RC_" commit-tree "$alt" -m clean)
git -C "$RC_" replace "$c1" "$alt"
# (d) clean repository with a harmless replace ref (clean blob -> other clean blob), no secret anywhere
RH="$tmp/rharmless"; git init -q "$RH"; echo hello > "$RH/a.txt"; git -C "$RH" add a.txt; git -C "$RH" commit -qm a
hb=$(git -C "$RH" rev-parse HEAD:a.txt); git -C "$RH" replace "$hb" "$(printf 'other\n' | git -C "$RH" hash-object -w --stdin)"
# (e) clean repository, no replace ref
CL="$tmp/clean"; git init -q "$CL"; echo hello > "$CL/a.txt"; git -C "$CL" add a.txt; git -C "$CL" commit -qm a
for r in "$RB" "$RT" "$RC_" "$RH"; do
  [ "$(git -C "$r" for-each-ref refs/replace | wc -l)" = 1 ] || { echo "env: fixture $r has no replace ref" >&2; exit 2; }
done
# fixture self-check: with replace refs honoured, git really hides the secret (otherwise the test proves nothing)
[ "$(git -C "$RB" log -p --all | grep -cF "$FV")" = 0 ] && [ "$(git -C "$RB" --no-replace-objects log -p --all | grep -cF "$FV")" = 1 ] \
  || { echo "env: fixture (a) does not hide the secret from git log" >&2; exit 2; }

KF="$tmp/keys.sh"; printf 'export MYKEY=%s\n' "$FV" > "$KF"; chmod 600 "$KF"
SCR="$tmp/scratch"; mkdir -p "$SCR"
declare -a RUN_ENV=()
run(){
  : > "$SEC_TEST_LOG/gitleaks_argv.log"; rm -f "$SCR"/*.tsv
  env PATH="$FIX/bin:$PATH" SCRATCH="$SCR" OUT="$SCR/out.tsv" ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    timeout -k 5 120 bash "$SCRIPT" "$@" > "$tmp/out" 2> "$tmp/err"; RC=$?
}
kcount(){ awk -F'\t' -v k="$1" '$1==k{print $2}' "$SCR/out.tsv.keys.tsv" 2>/dev/null; }
rcount(){ { wc -l < "$SCR/out.tsv.replace.tsv"; } 2>/dev/null || echo missing; }
leaked(){ grep -rqF -e "$FV" -e "$TK" "$tmp/out" "$tmp/err" "$SCR" 2>/dev/null; }

# ---- exact-match pass -------------------------------------------------------------------------------
RUN_ENV=(); run --exact-only --keys-file "$KF" "$RB"
check "blob replaced by a clean blob, --exact-only: exit 1 and MYKEY counted 1 (the stored secret blob is read)" '[ $RC -eq 1 ] && [ "$(kcount MYKEY)" = 1 ]'
check "the replace ref is listed: one row, ref refs/replace/<secret blob id>, object id, type blob" \
  'awk -F"\t" -v r="refs/replace/$sb" -v o="$cb" "\$1==r && \$2==o && \$3==\"blob\"" "$SCR/out.tsv.replace.tsv" | grep -q . && [ "$(rcount)" = 1 ]'
check "the replace ref count is printed" 'grep -q "^replace refs: 1 -> " "$tmp/out"'
check "no fake value in stdout, stderr or any output file" '! leaked'
RUN_ENV=(); run --exact-only --keys-file "$KF" "$RT"
check "blob force-replaced by a tree, --exact-only: exit 1, MYKEY=1 (no type-confused reply, not exit 7)" '[ $RC -eq 1 ] && [ "$(kcount MYKEY)" = 1 ] && [ "$(rcount)" = 1 ]'
RUN_ENV=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.useReplaceRefs GIT_CONFIG_VALUE_0=true); run --exact-only --keys-file "$KF" "$RB"
check "a caller's core.useReplaceRefs=true (GIT_CONFIG_COUNT) does not hide the secret: exit 1, MYKEY=1" '[ $RC -eq 1 ] && [ "$(kcount MYKEY)" = 1 ]'

# ---- scanner pass (fake gitleaks reads the real git log -p of the mirror) --------------------------
RUN_ENV=(); run "$RB"
check "blob replaced by a clean blob, scanner pass: exit 1, the fake token in s.env is reported" '[ $RC -eq 1 ] && grep -q "s.env:" "$SCR/out.tsv" && grep -q "control OK" "$tmp/out"'
check "scanner pass: no fake value in any output" '! leaked'
RUN_ENV=(); run "$RT"
check "blob force-replaced by a tree, scanner pass: exit 1, s.env reported" '[ $RC -eq 1 ] && grep -q "s.env:" "$SCR/out.tsv"'
RUN_ENV=(); run "$RC_"
check "commit replaced by a clean commit, scanner pass: exit 1, s.env of the hidden commit reported" '[ $RC -eq 1 ] && grep -q "s.env:" "$SCR/out.tsv" && [ "$(rcount)" = 1 ]'
check "commit replace ref listed with type commit" 'awk -F"\t" -v r="refs/replace/$c1" "\$1==r && \$3==\"commit\"" "$SCR/out.tsv.replace.tsv" | grep -q .'
GLW="$tmp/glwrap"; mkdir -p "$GLW"
cat > "$GLW/gitleaks" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${GIT_NO_REPLACE_OBJECTS-unset}" > "$SEC_TEST_LOG/gl_env"
exec "$FIX/bin/gitleaks" "\$@"
EOF
chmod +x "$GLW/gitleaks"; rm -f "$SEC_TEST_LOG/gl_env"
RUN_ENV=(GITLEAKS="$GLW/gitleaks"); run "$CL"
check "the scanner process gets GIT_NO_REPLACE_OBJECTS=1 (its own git reads the stored objects)" '[ $RC -eq 0 ] && [ "$(cat "$SEC_TEST_LOG/gl_env" 2>/dev/null)" = 1 ]'
check "clean repository without replace refs: exit 0, 'replace refs: 0', an empty replace list is written" '[ $RC -eq 0 ] && grep -q "^replace refs: 0 -> " "$tmp/out" && [ -f "$SCR/out.tsv.replace.tsv" ] && [ "$(rcount)" = 0 ]'

# ---- a replace ref alone is a finding ----------------------------------------------------------------
RUN_ENV=(); run --exact-only --keys-file "$KF" "$RH"
check "a harmless replace ref with no secret anywhere: exit 1 (replace ref to classify), MYKEY=0" '[ $RC -eq 1 ] && [ "$(kcount MYKEY)" = 0 ] && [ "$(rcount)" = 1 ]'
RUN_ENV=(); run "$RH"
check "same, scanner pass: exit 1 with findings=0 (only the replace ref)" '[ $RC -eq 1 ] && grep -q "findings=0" "$tmp/out" && [ "$(rcount)" = 1 ]'

# ---- replace ref carried by a second remote --------------------------------------------------------
RUN_ENV=(); run --exact-only --keys-file "$KF" "$CL" "$RB"
check "second remote carries the replace ref: listed as refs/fetched/r1/replace/<id>, MYKEY=1, exit 1" \
  '[ $RC -eq 1 ] && [ "$(kcount MYKEY)" = 1 ] && awk -F"\t" -v r="refs/fetched/r1/replace/$sb" "\$1==r" "$SCR/out.tsv.replace.tsv" | grep -q .'

# ---- defence in depth: a git that still honours replace refs ---------------------------------------
# The shim drops GIT_NO_REPLACE_OBJECTS before it runs the real git, so the
# forced blob->tree replace reaches the matcher: `cat-file --batch` answers
# type tree for an id that --batch-check listed as blob. The matcher's type
# check must stop the run with exit 7, never count tree bytes as a blob.
RG="$tmp/replacegit"; mkdir -p "$RG"; REALGIT=$(command -v git)
cat > "$RG/git" <<EOF
#!/usr/bin/env bash
unset GIT_NO_REPLACE_OBJECTS
exec "$REALGIT" "\$@"
EOF
chmod +x "$RG/git"
RUN_ENV=(PATH="$RG:$FIX/bin:$PATH"); run --exact-only --keys-file "$KF" "$RT"
check "git that honours replace refs + blob->tree replace: exit 7 (type check), no counts written" \
  '[ $RC -eq 7 ] && [ ! -s "$SCR/out.tsv.keys.tsv" ] && grep -q "unexpected reply from git cat-file" "$tmp/err"'

echo "RESULT: $((n-bad))/$n passed"
[ "$bad" -eq 0 ]
