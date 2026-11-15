#!/usr/bin/env bash
# tests/gates/test_oracle_verdict_fields.sh -- review round 4 follow-ups (11.4.276), REAL gate + lib, real git:
#  F4 a non-git tree must say rule3=skipped in the ORACLE-VERDICT line (not a silent PASS);
#  F5 the verdict names the remote ref that selected the merge-base (via=<ref>), rule3=evaluated in git;
#  N-nit cm_is_canon_root ignores an anchor heading that only appears inside a code fence.
set -uo pipefail
export CONSTITUTION_JEV_HOOK=off
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; canon="$(cd "$here/../.." && pwd)"
GATE="$canon/scripts/gates/cm_oracle_strategy_named_and_independent.sh"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $1"; }; bad(){ fail=$((fail+1)); echo "FAIL $1"; }
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
mk() { mkdir -p "$1/config"; printf 'def test_a():\n    assert 1\n' > "$1/test_x.py"; printf '# b\ntest_x.py\t1\n' > "$1/config/oracle_ratchet_baseline.txt"; }
mk "$sb/nogit"
out="$(bash "$GATE" --root "$sb/nogit" --quiet 2>&1)"; rc=$?
v="$(grep '^ORACLE-VERDICT' <<<"$out")"
[ "$rc" = 0 ] && grep -q $'\trule3=skipped\t' <<<"$v" && grep -q $'\tvia=none\t' <<<"$v" && ok "F4 non-git: PASS verdict says rule3=skipped via=none ($v)" || bad "F4 non-git rc=$rc v=$v"
mk "$sb/g"; "${G[@]}" init -q "$sb/g"; "${G[@]}" -C "$sb/g" add -A >/dev/null; "${G[@]}" -C "$sb/g" commit -qm c1
git -C "$sb/g" update-ref refs/remotes/github_x/main HEAD
out="$(bash "$GATE" --root "$sb/g" --quiet 2>&1)"; rc=$?; v="$(grep '^ORACLE-VERDICT' <<<"$out")"
[ "$rc" = 0 ] && grep -q $'\trule3=evaluated\t' <<<"$v" && grep -q $'\tvia=refs/remotes/github_x/main\t' <<<"$v" && ok "F5 git: verdict names the selecting remote ref ($v)" || bad "F5 git rc=$rc v=$v"
# fence-aware canon root
. "$canon/scripts/lib/default_scan_root.sh"
mkdir -p "$sb/fc/scripts/gates" "$sb/rc/scripts/gates"
printf 'intro\n```\n## §11.4.1 — fake heading in a fence\n```\n' > "$sb/fc/Constitution.md"
printf 'intro\n## §11.4.1 — real heading\n' > "$sb/rc/Constitution.md"
cm_is_canon_root "$sb/fc" && bad "fence: heading only inside a code fence counted as canon" || ok "fence: heading inside a code fence is ignored"
cm_is_canon_root "$sb/rc" && ok "fence: real heading still recognised" || bad "fence: real heading lost"
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
