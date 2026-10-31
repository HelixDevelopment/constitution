#!/usr/bin/env bash
# Tests scripts/post_update_hook.sh explicit-range handling
# (CONSTITUTION_UPDATE_OLD_REF / CONSTITUTION_UPDATE_NEW_REF). Real sandbox git repo.
# Classification: universal (§11.4.17). Hermetic: no network, no LLM.
# Usage: test_post_update_hook_range.sh [--mutation]   (mutation: hook ignores the range; MUST fail)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MUT=0; [ "${1:-}" = "--mutation" ] && MUT=1
# shellcheck source=/dev/null
. "$ROOT/scripts/lib/safe_rm.sh"
TMP="$(mktemp -d)"; : "${TMP:?}"
ORIG_HOME="${HOME:-}"   # the sandbox HOME below lives INSIDE $TMP (an ancestor of HOME is protected): clean up under the original
trap 'HOME="$ORIG_HOME" safe_rm_rf "${TMP:?}"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS  $*"; }
no(){ fail=$((fail+1)); echo "  FAIL  $*"; }

C="$TMP/const"; PRJ="$TMP/proj"
mkdir -p "$C/scripts" "$PRJ"
cp "$ROOT/scripts/post_update_hook.sh" "$C/scripts/post_update_hook.sh"
if [ "$MUT" -eq 1 ]; then
	# MUTATION: range ignored (env vars never validated/used)
	sed -i 's/^    if \[ -n "\$env_old\$env_new" \]; then/    if false; then/' "$C/scripts/post_update_hook.sh"
	grep -q '^    if false; then' "$C/scripts/post_update_hook.sh" || { echo "mutation did not apply"; exit 2; }
fi
echo "# c" > "$C/Constitution.md"
g(){ git -C "$C" -c user.email=t@t -c user.name=t "$@"; }
git -C "$C" init -q -b main
g add -A; g commit -qm c1; C1="$(g rev-parse HEAD)"
mkdir -p "$C/skills/alpha"; echo a > "$C/skills/alpha/SKILL.md"; g add -A; g commit -qm c2
mkdir -p "$C/skills/beta";  echo b > "$C/skills/beta/SKILL.md";  g add -A; g commit -qm c3; C3="$(g rev-parse HEAD)"
git -C "$C" update-ref -d ORIG_HEAD 2>/dev/null || :

run(){ # extra env pairs as args; prints combined output
	(cd "$PRJ" && env -u CONSTITUTION_UPDATE_OLD_REF -u CONSTITUTION_UPDATE_NEW_REF -u CONSTITUTION_JEV_HOOK \
	  CONST_DIR="$C" PROJECT_ROOT="$PRJ" "$@" bash "$C/scripts/post_update_hook.sh" 2>&1) || true
}

# Control needle: fallback (no env) sees ONLY beta (HEAD~1..HEAD)
out="$(run)"
if printf '%s' "$out" | grep -q 'beta' && ! printf '%s' "$out" | grep -q 'alpha'; then
	ok "fallback (no env): HEAD~1 range sees beta only (control needle)"
else no "fallback: expected beta only, got: $(printf '%s' "$out" | grep -E 'alpha|beta' | head -3)"; fi

out="$(run CONSTITUTION_UPDATE_OLD_REF="$C1" CONSTITUTION_UPDATE_NEW_REF="$C3")"
if printf '%s' "$out" | grep -q 'alpha' && printf '%s' "$out" | grep -q 'beta'; then
	ok "env range c1..c3 used: sees alpha AND beta (differs from fallback => range matters)"
else no "env range not used; output lacks alpha/beta"; fi
printf '%s' "$out" | grep -q 'Using explicit update range' && ok "env range announces itself" || no "no explicit-range note"

out="$(run CONSTITUTION_UPDATE_OLD_REF="nothex" CONSTITUTION_UPDATE_NEW_REF="$C3")"
if printf '%s' "$out" | grep -q 'falling back' && ! printf '%s' "$out" | grep -q 'alpha'; then
	ok "invalid (non-hex) env falls back with a note, alpha not seen"
else no "invalid env did not fall back cleanly"; fi

out="$(run CONSTITUTION_UPDATE_OLD_REF="$(printf 'a%.0s' $(seq 40))" CONSTITUTION_UPDATE_NEW_REF="$C3")"
if printf '%s' "$out" | grep -q 'falling back' && ! printf '%s' "$out" | grep -q 'alpha'; then
	ok "valid-format but unknown commit falls back with a note"
else no "unknown-commit env did not fall back"; fi

out="$(run CONSTITUTION_UPDATE_OLD_REF="$C1")"
printf '%s' "$out" | grep -q 'falling back' && ok "only one var set falls back" || no "single var did not fall back"

# CONSTITUTION_JEV_HOOK=off honoured: needs a Jev-relevant change in range
mkdir -p "$C/scripts/jev"; echo x > "$C/scripts/jev/bootstrap.sh"; g add -A; g commit -qm c4; C4="$(g rev-parse HEAD)"
out="$(run CONSTITUTION_UPDATE_OLD_REF="$C3" CONSTITUTION_UPDATE_NEW_REF="$C4" CONSTITUTION_JEV_HOOK=off)"
printf '%s' "$out" | grep -q 'SKIPPED — CONSTITUTION_JEV_HOOK=off' && ok "CONSTITUTION_JEV_HOOK=off honoured with range set" || no "JEV_HOOK=off not honoured"

# m5: 64-hex ids (SHA-256 object-format repositories) are accepted like 40-hex
C2="$TMP/const256"; mkdir -p "$C2/scripts"
cp "$C/scripts/post_update_hook.sh" "$C2/scripts/post_update_hook.sh"; echo "# c" > "$C2/Constitution.md"
g2(){ git -C "$C2" -c user.email=t@t -c user.name=t "$@"; }
if git -C "$C2" init -q -b main --object-format=sha256 2>/dev/null; then
	g2 add -A; g2 commit -qm s1; S1="$(g2 rev-parse HEAD)"
	mkdir -p "$C2/skills/gamma"; echo g > "$C2/skills/gamma/SKILL.md"; g2 add -A; g2 commit -qm s2
	mkdir -p "$C2/skills/delta"; echo d > "$C2/skills/delta/SKILL.md"; g2 add -A; g2 commit -qm s3; S3="$(g2 rev-parse HEAD)"
	git -C "$C2" update-ref -d ORIG_HEAD 2>/dev/null || :
	out="$( (cd "$PRJ" && env -u CONSTITUTION_UPDATE_OLD_REF -u CONSTITUTION_UPDATE_NEW_REF \
	  CONST_DIR="$C2" PROJECT_ROOT="$PRJ" CONSTITUTION_UPDATE_OLD_REF="$S1" CONSTITUTION_UPDATE_NEW_REF="$S3" \
	  bash "$C2/scripts/post_update_hook.sh" 2>&1) || true)"
	if [ "${#S1}" = 64 ] && printf '%s' "$out" | grep -q 'Using explicit update range' && \
	   printf '%s' "$out" | grep -q 'gamma' && printf '%s' "$out" | grep -q 'delta'; then
		ok "m5: 64-hex (sha256) range accepted and used (sees gamma AND delta)"
	else no "m5: 64-hex range not used: $(printf '%s' "$out" | grep -E 'range|falling' | head -2)"; fi
else
	echo "  SKIP  m5: git cannot create a sha256 repository here (topology_unsupported)"
fi

# m4: one-line hint when the INSTALLED submodule consumer differs from its source
mkdir -p "$C/scripts/hooks"
cp "$ROOT/scripts/hooks/constitution-submodule-post-checkout" "$C/scripts/hooks/constitution-submodule-post-checkout"
HD="$(git -C "$C" rev-parse --path-format=absolute --git-path hooks)"; mkdir -p "$HD"
cp "$ROOT/scripts/hooks/constitution-submodule-post-checkout" "$HD/post-checkout"
out="$(run)"
printf '%s' "$out" | grep -q 'hint: the installed' && no "m4: hint printed although the installed consumer is identical" \
	|| ok "m4: identical installed consumer -> no drift hint (false-positive guard)"
printf '# drift\n' >> "$HD/post-checkout"
out="$(run)"
if [ "$(printf '%s\n' "$out" | grep -c 'hint: the installed submodule post-checkout')" = 1 ] && printf '%s' "$out" | grep -q 're-run setup.sh'; then
	ok "m4: drifted installed consumer -> exactly one hint line naming setup.sh"
else no "m4: drift hint missing"; fi

echo "== hooks_range summary: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
