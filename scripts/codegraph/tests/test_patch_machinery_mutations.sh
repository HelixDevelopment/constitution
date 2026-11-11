#!/usr/bin/env bash
# ============================================================================
# test_patch_machinery_mutations.sh — paired section 1.1 mutations for the
# reuse-manifest and skip-contract cases of test_patch_machinery.py (review
# round 2 I1-5 / I1-6 of the full-suite fix vehicle, reviewer mutants N1a,
# N1b, N1c).
# ============================================================================
# Purpose   Each mutant is ONE exact string replacement (the anchor must occur
#           exactly once) in a copy of either fk_index_patch.py (run through
#           PATCH_TOOL_ROOT) or test_patch_machinery.py itself (run as the
#           copied file). The unmutated copies must pass first (baseline). A
#           mutant is KILLED only when the test exits 1 with at least one
#           `FAIL ` line and no Python traceback from the mutated code.
#             N1a  tree_manifest ignores directory symlinks     -> P2i
#             N1b  a link entry records "" instead of its target -> P2j
#             N1c  the skip path exits 0 and drops the reason    -> P5
# Usage     bash scripts/codegraph/tests/test_patch_machinery_mutations.sh [ID...]
# Exit      0 baseline passes and every selected mutant is killed; 1 otherwise
# Side effects  one mktemp -d tree, removed with safe_rm_rf on exit
# Dependencies  bash, python3
# ============================================================================
set -u
T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CG=$(cd "$T/.." && pwd)
CANON=$(cd "$CG/../.." && pwd)
. "$CANON/scripts/lib/safe_rm.sh" || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/pm_mut.XXXXXX") || exit 2
: "${W:?}"
trap 'TMPDIR="$(dirname "$W")" safe_rm_rf "${W:?}" >/dev/null 2>&1' EXIT

# id <TAB> target (tool|test) <TAB> old <TAB> new   (python escapes decoded)
MUTANTS=$(cat <<'EOF'
N1a	tool	sorted(filenames) + sorted(d for d in dirnames if os.path.islink(os.path.join(dirpath, d)))	sorted(filenames)
N1b	tool	out[rel] = ("l", os.readlink(full))	out[rel] = ("l", "")
N1c	test	        print(line + " reason=topology_unsupported")\n        return 77	        print(line)\n        return 0
EOF
)

prep() { # $1 dir: copy of the tool and its patches, plus the test file
  mkdir -p "$1"
  cp "$CG/fk_index_patch.py" "$1/" && cp -r "$CG/runner_patches" "$1/" && cp "$T/test_patch_machinery.py" "$1/"
}
runit() { # $1 dir -> rc of the (possibly mutated) test file against the (possibly mutated) tool
  PATCH_TOOL_ROOT="$1" PYTHONDONTWRITEBYTECODE=1 python3 "$1/test_patch_machinery.py" >"$1.log" 2>&1
}

prep "$W/base"; runit "$W/base"; rc=$?
if [ "$rc" = 0 ] || { [ "$rc" = 77 ] && ! grep -q '^FAIL ' "$W/base.log"; }; then
  echo "ok   baseline: unmutated copies pass ($(tail -1 "$W/base.log"))"
else
  echo "FAIL baseline: unmutated copies fail (rc $rc): $(grep -m3 '^FAIL ' "$W/base.log" | tr '\n' ' '); nothing concluded"; exit 1
fi
killed=0; survived=0; bad=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id=${line%%$'\t'*}; rest=${line#*$'\t'}; tgt=${rest%%$'\t'*}; rest=${rest#*$'\t'}; old=${rest%%$'\t'*}; new=${rest#*$'\t'}
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue;; esac; fi
  d="$W/$id"; prep "$d"
  f="$d/fk_index_patch.py"; [ "$tgt" = test ] && f="$d/test_patch_machinery.py"
  if ! python3 -I - "$f" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2].encode().decode("unicode_escape"), sys.argv[3].encode().decode("unicode_escape")
s = open(p).read()
if s.count(old) != 1:
    sys.exit("anchor occurs %d times" % s.count(old))
s = s.replace(old, new)
compile(s, p, "exec")
open(p, "w").write(s)
PY
  then echo "BAD  $id: mutation not applicable"; bad=$((bad+1)); continue; fi
  runit "$d"; rc=$?
  n=$(grep -c '^FAIL ' "$d.log")
  if grep -q '^Traceback' "$d.log"; then echo "BAD  $id: the mutated code crashed"; bad=$((bad+1))
  elif [ "$rc" = 1 ] && [ "$n" -gt 0 ]; then
    echo "killed $id ($n failing case(s): $(grep -m2 '^FAIL ' "$d.log" | cut -c6-110 | tr '\n' ';'))"; killed=$((killed+1))
  else echo "SURVIVED $id (rc $rc, $n FAIL lines: $(tail -1 "$d.log"))"; survived=$((survived+1)); fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
