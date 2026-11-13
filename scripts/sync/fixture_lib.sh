#!/usr/bin/env bash
# scripts/sync/fixture_lib.sh -- shared fixtures for tests/sync/* (sourced, never executed).
#
# Builds REAL git repositories: bare "upstream" repositories under $SB/remotes/<org>/<name>.git and
# working clones with real submodules (file:// URLs). Nothing here touches the network, a forge, $HOME
# or the repository the tests run from. Fixture producers write to the local bare repositories with
# the real git binary ($SX_GIT); the engine under test runs with PATH starting at a RECORDING SHIM that
# logs every argument vector and then executes the same real git.
#
# Safety: $HOME is never reassigned; every recursive delete is safe_rm_rf restricted to the sandbox
# (SAFE_RM_ALLOWED_ROOTS); git discovery is fenced with GIT_CEILING_DIRECTORIES.
# Kept outside tests/ on purpose: the full-suite census counts every script under tests/, and a
# sourced helper there would need an excluded row (scripts/run_full_suite.sh, EXCLUDED).
set -uo pipefail
SX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SX_ENGINE="${SX_ENGINE:-$SX_REPO/scripts/sync/sync_all_upstreams.sh}"
# shellcheck source=../lib/safe_rm.sh
. "$SX_REPO/scripts/lib/safe_rm.sh"
SX_GIT="$(command -v git)"
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=sync-fixture GIT_AUTHOR_EMAIL=sync@example.invalid
export GIT_COMMITTER_NAME=sync-fixture GIT_COMMITTER_EMAIL=sync@example.invalid
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE 2>/dev/null || true

T_PASS=0; T_FAIL=0; T_NAME="${T_NAME:-sync-tests}"
ok()   { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$*"; }
nok()  { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$*"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) nok "$1 (missing [$2])" ;; esac; }
hasnt() { case "$3" in *"$2"*) nok "$1 (unexpected [$2])" ;; *) ok "$1" ;; esac; }
finish() { printf '%s: PASS %d FAIL %d\n' "$T_NAME" "$T_PASS" "$T_FAIL"; [ "$T_FAIL" -eq 0 ]; }

sx_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/helix-sync-test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
  export SAFE_RM_ALLOWED_ROOTS="$SB"
  export GIT_CONFIG_GLOBAL="$SB/gitconfig"
  printf '[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n[advice]\n\tdetachedHead = false\n[core]\n\thooksPath = %s/nohooks\n' "$SB" >"$GIT_CONFIG_GLOBAL"
  mkdir -p "$SB/nohooks" "$SB/remotes" "$SB/work" "$SB/seed" "$SB/out" "$SB/shim"
  export GIT_CEILING_DIRECTORIES="$(dirname "$SB")"
  export XDG_CACHE_HOME="$SB/cache"
  # one write per call (O_APPEND, < PIPE_BUF), so concurrent calls never interleave inside a line
  printf '#!/usr/bin/env bash\nl="$(printf "%%s\\x1f" "$@")"; printf "%%s\\n" "$l" >>"%s/git_calls.log"\nexec "%s" "$@"\n' "$SB" "$SX_GIT" >"$SB/shim/git"
  chmod +x "$SB/shim/git"
  trap 'sx_cleanup' EXIT
  cd "$SB" || exit 2
}
sx_cleanup() {
  [ -n "${SB:-}" ] && [ -d "$SB" ] || return 0
  chmod -R u+w "${SB:?}" 2>/dev/null || true
  safe_rm_rf "${SB:?}"
}

# sx_bare ORG NAME -> prints the file:// URL of a new bare repository with one commit on main
sx_bare() {
  local org="$1" name="$2" d="$SB/remotes/$1/$2.git" w="$SB/seed/$1-$2"
  mkdir -p "$SB/remotes/$org"
  "$SX_GIT" init -q --bare "$d"
  "$SX_GIT" init -q "$w"
  printf '%s\n' "$name" >"$w/README"
  "$SX_GIT" -C "$w" add README && "$SX_GIT" -C "$w" commit -q -m "init $name"
  "$SX_GIT" -C "$w" push -q "$d" main:main
  printf 'file://%s' "$d"
}
# sx_seed URL -> path of a scratch producer clone (one per URL)
sx_seed() {
  local key; key="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  local w="$SB/seed/p$key"
  if [ ! -d "$w/.git" ]; then "$SX_GIT" clone -q "$1" "$w"; else "$SX_GIT" -C "$w" pull -q --ff-only origin main; fi
  printf '%s' "$w"
}
# sx_commit URL MESSAGE -> a new commit on the bare repository's main
sx_commit() {
  local w; w="$(sx_seed "$1")"
  printf '%s\n' "$2" >>"$w/CHANGES"
  "$SX_GIT" -C "$w" add CHANGES && "$SX_GIT" -C "$w" commit -q -m "$2" && "$SX_GIT" -C "$w" push -q origin main
}
# sx_add_sub PARENT_URL CHILD_URL PATH -> parent records CHILD at PATH (its current main)
sx_add_sub() {
  local w; w="$(sx_seed "$1")"
  "$SX_GIT" -C "$w" -c protocol.file.allow=always submodule add -q "$2" "$3" >/dev/null 2>&1
  "$SX_GIT" -C "$w" commit -q -m "add $3" && "$SX_GIT" -C "$w" push -q origin main
}
# sx_bump_pin PARENT_URL PATH -> parent's gitlink at PATH moves to the child's current upstream main
sx_bump_pin() {
  local w; w="$(sx_seed "$1")"
  "$SX_GIT" -C "$w" -c protocol.file.allow=always submodule update -q --init -- "$2"
  "$SX_GIT" -C "$w/$2" fetch -q origin && "$SX_GIT" -C "$w/$2" checkout -q --detach origin/main
  "$SX_GIT" -C "$w" add -- "$2" && "$SX_GIT" -C "$w" commit -q -m "bump $2" && "$SX_GIT" -C "$w" push -q origin main
}
# sx_clone URL DEST -> a working clone with every submodule initialised recursively
sx_clone() {
  "$SX_GIT" -c protocol.file.allow=always clone -q --recurse-submodules "$1" "$2" 2>/dev/null
}
# sx_run ARGS... -> runs the engine through the recording shim; sets SX_RC, SX_OUT (stdout), SX_ERR, SX_JSON
SX_N=0
sx_run() {
  SX_N=$((SX_N+1))
  local o="$SB/out/r$SX_N"
  SX_OUT="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --out "$o" --run-id "r$SX_N" "$@" 2>"$SB/out/r$SX_N.err")"; SX_RC=$?
  SX_ERR="$(cat "$SB/out/r$SX_N.err")"
  SX_JSON="$o/sync_report.json"
  SX_TSV="$o/sync_report.tsv"
}
# sx_q EXPR -> (test-only: EXPR is a literal written by the test author, never external input) evaluates a Python expression over the last report (variable r), prints the result
sx_q() {
  python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); P={x["path"]:x for x in r["repos"]}; print(eval(sys.argv[2]))' "$SX_JSON" "$1" 2>/dev/null
}
sx_head() { "$SX_GIT" -C "$1" rev-parse HEAD; }
sx_remote_head() { "$SX_GIT" --git-dir="$1" rev-parse main; }

# sx_std_tree -> a root with own-org submodule "libs/a" (which has nested own-org "inner") and a
# third-party submodule "vendor/t"; working clone at $SB/work/root. Sets U_ROOT U_A U_IN U_T.
sx_std_tree() {
  U_IN="$(sx_bare HelixDevelopment inner)"
  U_A="$(sx_bare HelixDevelopment liba)"
  U_T="$(sx_bare thirdparty tlib)"
  U_ROOT="$(sx_bare HelixDevelopment root)"
  sx_add_sub "$U_A" "$U_IN" inner
  sx_add_sub "$U_ROOT" "$U_A" libs/a
  sx_add_sub "$U_ROOT" "$U_T" vendor/t
  sx_clone "$U_ROOT" "$SB/work/root"
  W="$SB/work/root"
}
