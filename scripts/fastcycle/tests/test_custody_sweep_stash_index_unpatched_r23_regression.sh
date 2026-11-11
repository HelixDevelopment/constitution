#!/bin/bash
# Purpose : CON-160 regression guard for stash_index_unpatched() in
#           scripts/fastcycle/orchestration/custody_sweep.py (review fsfix6 m2,
#           reviewer mutants Y12 and Y14). The r22 test EP2V only checks that the
#           refusal message names the index content, so a mutant that reports a
#           DETERMINED index difference as None (Y12), or a git FAILURE as False
#           "no index content" (Y14), survived. This test pins the three-valued
#           answer of the real function on real throwaway repositories:
#             IDX   empty patch, index differs from the base      -> True
#             WT    non-empty patch (worktree-only stash)          -> False
#             EQ    empty patch passed for a stash whose index equals the base -> False
#             NONE  patch bytes None (patch unmeasured)            -> False
#             GITF  git diff fails (PATH shim, rc 128), empty patch -> None
# Usage   : bash test_custody_sweep_stash_index_unpatched_r23_regression.sh
#           Exit 0 when every check passes, 1 otherwise; the last line is the summary.
# Method  : REAL git repositories under a mktemp dir; the REAL function imported from
#           the tool; paired mutants Y12/Y14/Y15/Y16 run on a copy of the tool (the
#           checked tree is never changed). Control needle: the unmutated copy must
#           pass every check first.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CS="$HERE/../orchestration/custody_sweep.py"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf "${TMP:?}"' EXIT

mkrepo() { # $1 dir $2 kind: idx|wt
  git init -q "$1" && git -C "$1" config user.email t@t && git -C "$1" config user.name t || return 1
  printf 'a\n' > "$1/f" && git -C "$1" add f && git -C "$1" commit -qm base || return 1
  if [ "$2" = idx ]; then
    printf 'b\n' > "$1/f" && git -C "$1" add f && printf 'a\n' > "$1/f"
  else
    printf 'b\n' > "$1/f"
  fi
  git -C "$1" stash push -q
}
mkrepo "$TMP/idx" idx || { echo "NOT ok fixture idx"; exit 1; }
mkrepo "$TMP/wt" wt || { echo "NOT ok fixture wt"; exit 1; }
mkdir "$TMP/shim"
cat > "$TMP/shim/git" <<SH
#!/bin/sh
# fails only the index-vs-base comparison under test (git diff --quiet), like a broken diff
for a in "\$@"; do [ "\$a" = "--quiet" ] && exit 128; done
exec $(command -v git) "\$@"
SH
chmod +x "$TMP/shim/git"

cat > "$TMP/drv.py" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("cs", sys.argv[1]); cs = importlib.util.module_from_spec(spec); spec.loader.exec_module(cs)
tmp = sys.argv[2]; ref = "stash@{0}"
shimenv = dict(os.environ, PATH=os.path.join(tmp, "shim") + os.pathsep + os.environ["PATH"])
res = [
 ("IDX",  cs.stash_index_unpatched(os.path.join(tmp, "idx"), ref, b"", env=dict(os.environ)), True),
 ("WT",   cs.stash_index_unpatched(os.path.join(tmp, "wt"), ref, b"x", env=dict(os.environ)), False),
 ("EQ",   cs.stash_index_unpatched(os.path.join(tmp, "wt"), ref, b"", env=dict(os.environ)), False),
 ("NONE", cs.stash_index_unpatched(os.path.join(tmp, "idx"), ref, None, env=dict(os.environ)), False),
 ("GITF", cs.stash_index_unpatched(os.path.join(tmp, "idx"), ref, b"", env=shimenv), None),
]
bad = 0
for name, got, want in res:
    good = got is want
    print(("ok " if good else "NOT ok ") + "%s got=%r want=%r" % (name, got, want))
    bad += 0 if good else 1
sys.exit(1 if bad else 0)
PY

run() { python3 -I "$TMP/drv.py" "$1" "$TMP" 2>&1; }
OUT=$(run "$CS"); RC=$?
if [ $RC = 0 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^ok ')" = 5 ]; then ok "unmutated tool: all 5 axes (IDX WT EQ NONE GITF) pass"
else notok "unmutated tool: $(printf '%s' "$OUT" | tr '\n' '|')"; fi

mut() { # $1 name $2 python: old $3 new
  cp "$CS" "$TMP/m.py"
  python3 -I - "$TMP/m.py" "$2" "$3" <<'PY' || { notok "mutant $1: edit did not apply (blind)"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
i = s.index("def stash_index_unpatched")
j = s.index("def stash_base_commit")
body = s[i:j]
assert body.count(old) == 1, "pattern count %d" % body.count(old)
open(p, "w", encoding="utf-8").write(s[:i] + body.replace(old, new) + s[j:])
PY
  if run "$TMP/m.py" >/dev/null; then notok "mutant $1 SURVIVED"; else ok "mutant $1 killed"; fi
}
mut Y12_rc1_returns_None   '    if rc == 1:
        return True' '    if rc == 1:
        return None'
mut Y14_git_failure_False  '        return True
    return None' '        return True
    return False'
mut Y15_rc0_returns_True   '    if rc == 0:
        return False' '    if rc == 0:
        return True'
mut Y16_nonempty_patch_checked 'if patch_bytes is None or patch_bytes:' 'if patch_bytes is None:'

echo "=== custody stash_index_unpatched r23: pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
