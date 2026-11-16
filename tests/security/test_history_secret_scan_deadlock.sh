#!/usr/bin/env bash
# test_history_secret_scan_deadlock.sh -- hermetic tests for the exact-match
# pass of scripts/security/history_secret_scan.sh on a repository with many
# blobs (CON-423).
#
# Purpose: the exact-match pass used to write every blob id to
# `git cat-file --batch` before reading any answer; with a few thousand blobs
# both pipes fill and both processes wait for ever (deadlock). This test builds
# a throwaway repository with HSS_DL_BLOBS (default 8000) distinct blobs, runs
# the REAL script under `timeout` (so a deadlock fails in HSS_DL_TIMEOUT
# seconds instead of hanging), and checks: the run ends, the planted value is
# counted in exactly the blobs that hold it, the controls hold, the
# --exact-only option (no scanner run), the short-value limit (names and count
# reported, 11/12 character boundary) and a matcher that gets unexpected
# replies from git (exit 7, never a silent count).
# Gate-logic tests only (§11.4.289): fake gitleaks, local repositories.
# Fabricated values are random per run and built with python3 (no
# secret-shaped literal in this file).
#
# Usage: bash tests/security/test_history_secret_scan_deadlock.sh
#        HSS_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        HSS_DL_BLOBS=N HSS_DL_TIMEOUT=S     (repository size, per-run time bound)
#        SEC_TEST_FAILFAST=1 stops at the first failing case
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
# shellcheck disable=SC2034  # RC is read inside the eval'd check strings
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${HSS_SCRIPT:-$here/scripts/security/history_secret_scan.sh}"
FIX="$here/tests/security/fixtures"
NBLOBS="${HSS_DL_BLOBS:-8000}"
TMO="${HSS_DL_TIMEOUT:-120}"
for t in git jq python3 timeout; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
export SEC_TEST_LOG="$tmp/log"; mkdir -p "$SEC_TEST_LOG"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
check(){ if eval "$2"; then ok "$1"; else nok "$1"; sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -30; fi; }
rv(){ python3 -I -c 'import secrets,sys;print(sys.argv[1]+secrets.token_hex(int(sys.argv[2])))' "$1" "$2"; }

# Fake values (random per run). KV is 26 characters, searched.
KV=$(rv kv 12); KB=$(rv absent 12)
V11=$(python3 -I -c 'import secrets;print(secrets.token_hex(6)[:11])')
V12=$(python3 -I -c 'import secrets;print(secrets.token_hex(6))')
V3=$(python3 -I -c 'import secrets;print(secrets.token_hex(2)[:3])')

# Big repository: NBLOBS distinct blobs in one commit; KV is in exactly 2 of
# them (the first and the last file), V12 in exactly 1.
BIG="$tmp/big"; git init -q "$BIG"
python3 -I - "$NBLOBS" "$KV" "$V12" <<'PY' | git -C "$BIG" fast-import --quiet
import sys
n, kv, v12 = int(sys.argv[1]), sys.argv[2], sys.argv[3]
out = sys.stdout.buffer
def w(s): out.write(s.encode() if isinstance(s, str) else s)
w("commit refs/heads/main\ncommitter t <t@t> 946684800 +0000\ndata 3\nbig\n")
for i in range(n):
    body = "file %06d distinct filler line for the deadlock test %d\n" % (i, i * 7919)
    if i == 0 or i == n - 1:
        body += "cfg=%s\n" % kv
    if i == 1:
        body += "short=%s\n" % v12
    b = body.encode()
    w("M 100644 inline f/%06d.txt\ndata %d\n" % (i, len(b))); w(b); w("\n")
PY
git -C "$BIG" checkout -q main 2>/dev/null || true
nb=$(git -C "$BIG" cat-file --batch-all-objects --batch-check='%(objecttype)' | grep -c '^blob$')
if [ "$nb" -lt "$NBLOBS" ]; then echo "env: big repository has $nb blobs, wanted $NBLOBS" >&2; exit 2; fi
SMALL="$tmp/small"; git init -q "$SMALL"; echo hello > "$SMALL/readme.txt"; git -C "$SMALL" add readme.txt; git -C "$SMALL" commit -qm readme

KF="$tmp/keys.sh"
printf 'export KEY_A=%s\nexport KEY_B=%s\nexport KEY_12=%s\nexport KEY_11=%s\nexport KEY_3=%s\n' "$KV" "$KB" "$V12" "$V11" "$V3" > "$KF"; chmod 600 "$KF"
KF0="$tmp/keys0.sh"; printf 'export KEY_A=%s\n' "$KV" > "$KF0"; chmod 600 "$KF0"

SCR="$tmp/scratch"; mkdir -p "$SCR"
declare -a RUN_ENV=()
run(){
  : > "$SEC_TEST_LOG/gitleaks_argv.log"; rm -f "$SCR"/*.tsv
  env PATH="$FIX/bin:$PATH" SCRATCH="$SCR" OUT="$SCR/out.tsv" ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    timeout -k 5 "$TMO" bash "$SCRIPT" "$@" > "$tmp/out" 2> "$tmp/err"; RC=$?
}
kcount(){ awk -F'\t' -v k="$1" '$1==k{print $2}' "$SCR/out.tsv.keys.tsv" 2>/dev/null; }
leaked(){ grep -rqF -e "$KV" -e "$V12" -e "$V11" -e "$V3" -e "$KB" "$tmp/out" "$tmp/err" "$SCR" 2>/dev/null; }

# ---- deadlock (the defect) -----------------------------------------------------------------------
RUN_ENV=(); run --keys-file "$KF" "$BIG"
check "exact-match pass over $nb blobs ends within ${TMO}s (no deadlock; 124 = timed out)" '[ $RC -ne 124 ] && [ $RC -ne 137 ]'
check "big repo: exit 1 (KEY_A found)" '[ $RC -eq 1 ]'
check "KEY_A counted in exactly the 2 blobs that hold it (every blob read)" '[ "$(kcount KEY_A)" = 2 ]'
check "KEY_12 (12 characters, the minimum) is searched and counted in exactly 1 blob" '[ "$(kcount KEY_12)" = 1 ]'
check "KEY_B (absent) counted 0" '[ "$(kcount KEY_B)" = 0 ]'
check "short values skipped and named, count 2 (KEY_11, KEY_3)" 'grep -q "not searched: 2 shorter than 12 characters (KEY_11,KEY_3)" "$tmp/out"'
check "short values are not in the searched list" '! grep -q -e "^KEY_11" -e "^KEY_3" "$SCR/out.tsv.keys.tsv"'
check "no fake value in stdout, stderr or any output file" '! leaked'
check "work directory removed" '[ "$(find "$SCR" -maxdepth 1 -name "hss.*" | wc -l)" = 0 ]'

# ---- --exact-only ---------------------------------------------------------------------------------
RUN_ENV=(); run --exact-only --keys-file "$KF" "$BIG"
check "--exact-only on the big repo: exit 1, KEY_A=2, no deadlock" '[ $RC -eq 1 ] && [ "$(kcount KEY_A)" = 2 ]'
check "--exact-only does not run the scanner" '[ ! -s "$SEC_TEST_LOG/gitleaks_argv.log" ] && grep -q "scanner not run (--exact-only)" "$tmp/out"'
RUN_ENV=(GITLEAKS="$tmp/no/such/gitleaks"); run --exact-only --keys-file "$KF0" "$SMALL"
check "--exact-only works without a scanner binary: clean repo -> exit 0" '[ $RC -eq 0 ] && [ "$(kcount KEY_A)" = 0 ]'
check "--exact-only: zero short values still reported (never silent)" 'grep -q "not searched: 0 shorter than 12 characters ()" "$tmp/out"'
RUN_ENV=(); run --exact-only "$SMALL"
check "--exact-only without --keys-file -> usage 2" '[ $RC -eq 2 ] && grep -q "exact-only needs --keys-file" "$tmp/err"'
RUN_ENV=(GITLEAKS="$tmp/no/such/gitleaks"); run --keys-file "$KF0" "$SMALL"
check "without --exact-only a missing scanner is still exit 4" '[ $RC -eq 4 ]'

# ---- matcher gets unexpected replies from git ------------------------------------------------------
# A git shim that answers every `cat-file --batch` request with "<id> missing":
# the matcher must stop with 7, never report counts.
MG="$tmp/missinggit"; mkdir -p "$MG"; REALGIT=$(command -v git)
cat > "$MG/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = --batch ]; then while read -r id; do printf '%s missing\n' "\$id"; done; exit 0; fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$MG/git"
RUN_ENV=(PATH="$MG:$FIX/bin:$PATH"); run --exact-only --keys-file "$KF0" "$SMALL"
check "cat-file --batch answers 'missing' -> exit 7 (git error), no counts written" '[ $RC -eq 7 ] && [ ! -s "$SCR/out.tsv.keys.tsv" ]'
# A git shim whose `cat-file --batch` answers every request with the FIRST
# requested object: the replies no longer match the requested ids, so the
# matcher must stop with 7 instead of counting the wrong blobs.
WG="$tmp/wronggit"; mkdir -p "$WG"
cat > "$WG/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = --batch ]; then
    first=""; while read -r id; do [ -n "\$first" ] || first=\$id; printf '%s\n' "\$first"; done | "$REALGIT" "\$@"; exit \$?
  fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$WG/git"
RUN_ENV=(PATH="$WG:$FIX/bin:$PATH"); run --exact-only --keys-file "$KF0" "$BIG"
check "cat-file --batch answers for another id -> exit 7, no counts written" '[ $RC -eq 7 ] && [ ! -s "$SCR/out.tsv.keys.tsv" ] && grep -q "unexpected reply from git cat-file" "$tmp/err"'

echo "RESULT: $((n-bad))/$n passed"
[ "$bad" -eq 0 ]
