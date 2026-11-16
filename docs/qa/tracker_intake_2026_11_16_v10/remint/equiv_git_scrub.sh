#!/usr/bin/env bash
# docs/qa/tracker_intake_2026_11_16_v10/remint/equiv_git_scrub.sh -- evidence that the two git-scrub
# mutants of remint_ids.py are equivalent one at a time (section 11.4.276(D)).
#
# WHY   remint_ids.py removes the repository-locating GIT_* variables twice: once for the whole process
#       when the file starts (the canonical census scrub) and once more for each git call (git_env()).
#       Either one alone keeps every git call away from an ambient GIT_DIR, so a mutant that disables
#       only one of them cannot change an answer, and the suite cannot kill it. This tool shows it on
#       the only git call sites (cmd_refs: rev-parse and ls-files), and its control needle shows the
#       probe would see a tool that follows the ambient variables: with BOTH removed, git answers for the
#       sentinel repository, so refs of the real repository no longer lists it (it is BLIND: the top git
#       reports is the sentinel's).
# USAGE bash equiv_git_scrub.sh [TOOL]   (default: scripts/workable-items/remint_ids.py of this checkout;
#       run from the repository root). Prints one line per variant, a CONTROL needle line and a RESULT.
# EXIT  0 the two single mutants are equivalent on the probe and the control needle is ok; 1 otherwise;
#       2 setup error.
# EVIDENCE CLASS  gate-logic (section 11.4.289): scratch repositories under a mktemp dir only.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
tool=${1:-scripts/workable-items/remint_ids.py}
[ -f "$tool" ] || { echo "setup: no tool $tool" >&2; exit 2; }
[ -f scripts/lib/safe_rm.sh ] || { echo "setup: run from the repository root" >&2; exit 2; }
# shellcheck source=../../../../scripts/lib/safe_rm.sh
. scripts/lib/safe_rm.sh || exit 2
tmp=$(mktemp -d) || exit 2
trap 'safe_rm_rf "${tmp:?}" || echo "CLEANUP REFUSED: $tmp" >&2' EXIT
S=$tmp/sentinel; R=$tmp/real; E=$tmp/norepo
mkdir -p "$S" "$R/docs/guides" "$E" || exit 2
git -C "$S" -c init.defaultBranch=main init -q && printf 'sentinel names CON-2\n' >"$S/keep.md" && git -C "$S" add keep.md || exit 2
git -C "$R" -c init.defaultBranch=main init -q && printf 'the guide names CON-2\n' >"$R/docs/guides/g.md" && git -C "$R" add -A || exit 2
printf 'old\tnew\nCON-2\tCON-20\n' >"$tmp/m.tsv"
python3 -I - "$tool" "$tmp" <<'PY' || exit 2
import sys
src, d = sys.argv[1], sys.argv[2]
s = open(src).read()
A = ("    _ge_os.environ.pop(_ge_v, None)", "    pass")
B = ("return {k: v for k, v in os.environ.items() if k not in GIT_SCRUB_VARS}", "return dict(os.environ)")
for old, _ in (A, B):
    if s.count(old) != 1:
        sys.exit("setup: edit text not found once: %r" % old)
open(d + "/t0.py", "w").write(s)
open(d + "/tA.py", "w").write(s.replace(*A))
open(d + "/tB.py", "w").write(s.replace(*B))
open(d + "/tAB.py", "w").write(s.replace(*A).replace(*B))
PY
probe() { # probe <tool copy> <repo root>: rc of refs under the sentinel's ambient variables, and whether keep.md is listed
  GIT_DIR="$S/.git" GIT_WORK_TREE="$S" GIT_INDEX_FILE="$S/.git/index" python3 -I "$1" refs --map "$tmp/m.tsv" --repo-root "$2" >"$tmp/out" 2>&1
  local rc=$?; local k=no; grep -q 'keep.md' "$tmp/out" && k=yes
  echo "rc=$rc sentinel-listed=$k"
}
blind=0 own=0
for v in t0 tA tB; do
  e=$(probe "$tmp/$v.py" "$E"); r=$(probe "$tmp/$v.py" "$R")
  echo "VARIANT $v: no-repository dir: $e; real repository: $r"
  case "$v:$e" in tA:"rc=3 sentinel-listed=no"|tB:"rc=3 sentinel-listed=no") blind=$((blind + 1)) ;; esac
  case "$v:$r" in tA:"rc=0 sentinel-listed=no"|tB:"rc=0 sentinel-listed=no") own=$((own + 1)) ;; esac
done
c0=$(probe "$tmp/t0.py" "$R"); c=$(probe "$tmp/tAB.py" "$R")
echo "VARIANT tAB (both scrubs removed): real repository: $c (unmutated: $c0)"
st=0
if [ "$c0" = "rc=0 sentinel-listed=no" ] && [ "$c" != "$c0" ]; then echo "CONTROL needle (both removed: refs no longer judges the real repository) ok"
else echo "CONTROL needle (both removed: refs no longer judges the real repository) FAILED: $c"; st=1; fi
echo "RESULT single-mutants=2 blind=$blind listed-own=$own"
[ "$blind" = 2 ] && [ "$own" = 2 ] || st=1
echo "rc=$st"
exit "$st"
