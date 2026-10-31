#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_integration.sh — real git: a bare clone of THIS repository (plus one test commit carrying the
# working-tree engine and a labelled fixture bundled extension) is added with a real
# `git submodule add` into sandbox projects at BOTH layouts (constitution/ and
# submodules/constitution/); the engine runs from inside the submodule. Covers: git-source install
# pinned by 40-hex sha, local-dir install pinned by sha256, info/exclude handling (submodule stays
# clean), lock file location, sha mismatch, unpinned refusal and waiver recording.
T_NAME=integration
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox

UP="$SB/up"; mkdir -p "$UP"
git clone -q --bare --no-recurse-submodules "$REPO" "$UP/c.git" || { nok "bare clone"; finish; exit 1; }
git clone -q "$UP/c.git" "$UP/work" || { nok "work clone"; finish; exit 1; }
# the clone must be a constitution (Constitution.md) on branch main: the submodule add below follows the bare
# repository's HEAD, so a clone whose HEAD is another branch (a reviewer sandbox on master) would test nothing
check "work clone carries Constitution.md" test -f "$UP/work/Constitution.md"
git -C "$UP/work" checkout -q -B main || nok "branch main"
eq "work clone is on branch main" main "$(git -C "$UP/work" rev-parse --abbrev-ref HEAD)"
mkdir -p "$UP/work/scripts/constitution_ext" "$UP/work/extensions/hello-fixture"
# engine under test: $ENGINE's directory (the repo engine by default, a mutated copy under test_mutations)
ED="$(dirname "$ENGINE")"
cp "$ED"/*.sh "$ED"/*.py "$UP/work/scripts/constitution_ext/"
cp -R "$FIX/hello-fixture/." "$UP/work/extensions/hello-fixture/"
git -C "$UP/work" add -f scripts/constitution_ext extensions/hello-fixture
git -C "$UP/work" commit -q -m "test: engine under test + TEST FIXTURE bundled extension"
git -C "$UP/work" tag -a helixconstitution-v999.0 -m t
git -C "$UP/work" push -q origin HEAD:refs/heads/main helixconstitution-v999.0 || nok "push test commit"
git -C "$UP/c.git" symbolic-ref HEAD refs/heads/main
eq "bare repository HEAD is main" refs/heads/main "$(git -C "$UP/c.git" symbolic-ref HEAD)"

# extension published as its own git repo
HSHA="$(ext_git_repo "$FIX/hooks-fixture" "$SB/hooks-src")"
HD="$(bash "$ENGINE" --json validate "$SB/hooks-src" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')"

for layout in constitution submodules/constitution; do
  echo "--- layout $layout"
  P="$SB/proj_${layout//\//_}"; make_project "$P"
  git -C "$P" submodule add -q "$UP/c.git" "$layout" 2>/dev/null; RC=$?
  eq "submodule add at $layout" 0 "$RC"
  git -C "$P" commit -q -m "add constitution" || true
  E="$P/$layout/scripts/constitution_ext/constitution_ext.sh"
  check "engine present in submodule" test -f "$E"
  run() { OUT="$(cd "$P" && bash "$E" "$@" </dev/null 2>&1)"; RC=$?; }
  runj() { OUT="$(cd "$P" && bash "$E" "$@" </dev/null 2>/dev/null)"; RC=$?; }

  runj --json doctor; eq "doctor layout ($layout)" "$layout" "$(jget "$OUT" layout)"
  eq "doctor project root ($layout)" "$P" "$(jget "$OUT" project_root)"
  runj --json list; eq "bundled fixture visible ($layout)" "hello-fixture" "$(jget "$OUT" extensions.0.id)"

  run enable hello-fixture --yes; eq "enable bundled ($layout)" 0 "$RC"
  check "lock file at project/.constitution ($layout)" test -f "$P/.constitution/extensions.lock.yml"

  # round 7: run from ANOTHER project's directory (no --project-root) the engine of this submodule must refuse and
  # change neither project
  P2="$SB/other_${layout//\//_}"; make_project "$P2"
  b1="$(git -C "$P" status --porcelain=v1 -uall | sort | sha256sum)"; b2="$(git -C "$P2" status --porcelain=v1 -uall | sort | sha256sum)"
  OUT="$(cd "$P2" && bash "$E" enable hello-fixture --yes </dev/null 2>&1)"; RC=$?
  eq "foreign cwd refused ($layout)" 3 "$RC"; has "names --project-root ($layout)" "--project-root" "$OUT"
  eq "project untouched by foreign cwd ($layout)" "$b1" "$(git -C "$P" status --porcelain=v1 -uall | sort | sha256sum)"
  eq "other project untouched ($layout)" "$b2" "$(git -C "$P2" status --porcelain=v1 -uall | sort | sha256sum)"
  check "no .constitution in the other project ($layout)" test ! -e "$P2/.constitution"
  run add "$SB/hooks-src" --sha "$HSHA" --sha256 "$HD" --yes; eq "git add pinned ($layout)" 0 "$RC"
  check "installed under _installed ($layout)" test -f "$P/$layout/extensions/_installed/hooks-fixture/extension.yml"
  check "no .git copied ($layout)" test ! -e "$P/$layout/extensions/_installed/hooks-fixture/.git"
  ex="$(git -C "$P/$layout" rev-parse --git-path info/exclude)"; case "$ex" in /*) ;; *) ex="$P/$layout/$ex";; esac
  check "exclude has _installed ($layout)" grep -qx 'extensions/_installed/' "$ex"
  eq "submodule worktree clean ($layout)" "" "$(git -C "$P/$layout" status --porcelain)"
  lock="$(cat "$P/.constitution/extensions.lock.yml")"
  has "lock records git sha ($layout)" "$HSHA" "$lock"; has "lock records consent ($layout)" "consent" "$lock"
  runj --json info hooks-fixture; eq "hooks disabled by default ($layout)" "false" "$(jget "$OUT" enabled)"
  run verify; eq "verify all ($layout)" 0 "$RC"

  run add "$SB/hooks-src" --sha "$HSHA" --sha256 "$HD" --yes; eq "re-add same pin is idempotent ($layout)" 0 "$RC"; has "says already" "already installed" "$OUT"
  run remove hooks-fixture --yes; eq "remove ($layout)" 0 "$RC"
  check "tree gone ($layout)" test ! -e "$P/$layout/extensions/_installed/hooks-fixture"
done

P="$SB/proj_submodules_constitution"; E="$P/submodules/constitution/scripts/constitution_ext/constitution_ext.sh"
run() { OUT="$(cd "$P" && bash "$E" "$@" </dev/null 2>&1)"; RC=$?; }
run add "$SB/hooks-src" --sha "$(printf 'b%.0s' $(seq 40))" --sha256 "$HD" --yes; eq "unknown sha refused (5)" 5 "$RC"
run add "$SB/hooks-src" --yes; eq "unpinned git refused (3)" 3 "$RC"; has "mentions waiver" "waiver" "$OUT"
run add "$SB/hooks-src" --waiver-id WVR-7 --yes; eq "unpinned with waiver accepted" 0 "$RC"
has "waiver recorded" "WVR-7" "$(cat "$P/.constitution/extensions.lock.yml")"
run remove hooks-fixture --yes
mkdir -p "$SB/devext"; cp -R "$FIX/hooks-fixture/." "$SB/devext/"
D="$(bash "$E" --json validate "$SB/devext" 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')"
run add "$SB/devext" --dev --sha256 "$D" --yes; eq "local dir pinned by sha256" 0 "$RC"
run remove hooks-fixture --yes
run add "$SB/devext" --dev --sha256 "$(printf '0%.0s' $(seq 64))" --yes; eq "sha256 mismatch (5)" 5 "$RC"
check "nothing left after mismatch" test ! -e "$P/submodules/constitution/extensions/_installed/hooks-fixture"
eq "submodule still clean" "" "$(git -C "$P/submodules/constitution" status --porcelain)"
finish
