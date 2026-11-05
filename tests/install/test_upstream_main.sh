#!/usr/bin/env bash
# tests/install/test_upstream_main.sh — make_upstream (tests/install/lib.sh) must put the COMMIT UNDER TEST
# under the fixture commit, in both repository layouts a review or vehicle clone can have (review F8,
# section 11.4.108 / 11.4.200):
#   layout A  a local `main` exists and differs from the checked-out HEAD (a vehicle branch in a normal clone)
#   layout B  no local `main` at all (`git clone -b <vehicle>`)
# For each layout the test builds a scratch repository (shared-object clone of this one, so it is cheap),
# commits the lib.sh under test onto a vehicle branch there, runs the REAL make_upstream from that repository,
# and asserts: the upstream main~1 is that repository's HEAD, the upstream HEAD is main, and the upstream copy of
# tests/install/lib.sh is byte-identical to the lib.sh under test (not main's copy).
# Usage: bash tests/install/test_upstream_main.sh     Exit: 0 all pass, 1 any fail, 2 setup error
# Safety: one mktemp -d root, removed with safe_rm_rf restricted to that root; $HOME is never reassigned;
# the source repository is only read (git clone --shared reads it).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$here/../.." && pwd)"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$SRC/scripts/lib/safe_rm.sh"
LIB="$here/lib.sh"
P=0; F=0
ok()  { P=$((P+1)); echo "  ok   $*"; }
nok() { F=$((F+1)); echo "  FAIL $*"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/upstream-main-test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$ROOT"
trap 'chmod -R u+w "${ROOT:?}" 2>/dev/null; safe_rm_rf "${ROOT:?}"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' >"$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

base="$(git -C "$SRC" rev-parse --verify -q 'HEAD^{commit}')" || { echo "cannot resolve HEAD of $SRC" >&2; exit 2; }
lib_sha="$(sha256sum "$LIB" | awk '{print $1}')"

layout() { # layout NAME want_local_main(0|1)
  local name="$1" want_main="$2" r="$ROOT/$1"
  git clone -q --shared --no-checkout --no-recurse-submodules "$SRC" "$r" || return 1
  git -C "$r" checkout -q -B vehicle/under-test "$base" || return 1
  for b in $(git -C "$r" for-each-ref --format='%(refname:short)' refs/heads/); do
    [ "$b" = vehicle/under-test ] || git -C "$r" branch -q -D "$b" || return 1
  done
  if [ "$want_main" = 1 ]; then
    # a local main that differs from HEAD AND carries a different lib.sh, so a fixture built on main is visible
    git -C "$r" checkout -q -b main "$base" || return 1
    printf '# marker: local main copy, not the lib.sh under test\n' >>"$r/tests/install/lib.sh"
    git -C "$r" commit -q -am "test: local main differs" || return 1
    git -C "$r" checkout -q vehicle/under-test || return 1
  fi
  cp "$LIB" "$r/tests/install/lib.sh" || return 1
  git -C "$r" add tests/install/lib.sh && git -C "$r" commit -q --allow-empty -m "test: lib.sh under test" || return 1
  printf '%s\n' "$r"
}

for spec in "A 1" "B 0"; do
  set -- $spec; name=$1; want=$2
  echo "== layout $name (local main: $want)"
  r="$(layout "$name" "$want")" || { nok "layout $name: setup failed"; continue; }
  head_r="$(git -C "$r" rev-parse HEAD)"
  if [ "$want" = 1 ]; then
    eq "layout $name precondition: local main differs from HEAD" yes "$( [ "$(git -C "$r" rev-parse main)" != "$head_r" ] && echo yes || echo no)"
  else
    eq "layout $name precondition: no local main" no "$(git -C "$r" rev-parse -q --verify refs/heads/main >/dev/null && echo yes || echo no)"
  fi
  out="$ROOT/$name.out"
  # the REAL make_upstream from the layout repository (REPO = its directory), in its own sandbox; the subshell
  # prints the upstream facts before its EXIT trap removes the sandbox
  ( cd "$r" && TMPDIR="$ROOT" bash -c '
      . tests/install/lib.sh; new_sandbox; make_upstream "$SB" || { echo "MAKE_UPSTREAM_FAILED"; exit 1; }
      echo "main1=$(git -C "$SB/upstream.git" rev-parse main~1)"
      echo "head=$(git -C "$SB/upstream.git" symbolic-ref HEAD)"
      echo "libsha=$(git -C "$SB/upstream.git" show main:tests/install/lib.sh | sha256sum | cut -d" " -f1)"
    ' ) >"$out" 2>&1
  grep -q MAKE_UPSTREAM_FAILED "$out" && { nok "layout $name: make_upstream failed: $(tail -3 "$out" | tr '\n' ' ')"; continue; }
  eq "layout $name: upstream main~1 is the commit under test" "$head_r" "$(sed -n 's/^main1=//p' "$out")"
  eq "layout $name: upstream HEAD is main" refs/heads/main "$(sed -n 's/^head=//p' "$out")"
  eq "layout $name: upstream lib.sh is the lib.sh under test" "$lib_sha" "$(sed -n 's/^libsha=//p' "$out")"
done
echo "test_upstream_main: PASS $P FAIL $F"
[ "$F" -eq 0 ] && [ "$P" -gt 0 ]
