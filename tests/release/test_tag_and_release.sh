#!/usr/bin/env bash
# tests/release/test_tag_and_release.sh — hermetic test of scripts/release/tag_and_release.sh.
#
# Class (§11.4.289(C)): the git side is REAL (real git, real bare repositories on the local file
# system as remotes, real pre-receive hooks); the gh and glab command-line tools are UNIT-CLASS
# test doubles on PATH that record their arguments. The run proves the script's logic (ordering,
# atomic push, per-remote OK gate, resume, exit status); it is NOT live proof against any hosting
# platform.
#
# Usage: bash tests/release/test_tag_and_release.sh        (TAR_SCRIPT=<path> tests another copy)
# Exit 0 when every case passes, 1 otherwise. Prints "RESULT: pass=N fail=M".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${TAR_SCRIPT:-$ROOT/scripts/release/tag_and_release.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
W="$(mktemp -d "${TMPDIR:-/tmp}/tar_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT INT TERM
TAG=fixture-v9.1
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c advice.detachedHead=false)

# ---- test doubles for gh / glab (UNIT-CLASS, record every call) ----
mkdir -p "$W/bin"
cat >"$W/bin/gh" <<'SH'
#!/bin/sh
echo "gh $*" >>"$STUB_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api repos/acc/one"|"api repos/acc/alias") echo 42; exit 0 ;;
  "api repos/acc/two") echo 43; exit 0 ;;
  "api "*) exit 1 ;;
  "release view") grep -qx "ghrel $5" "$STUB_STATE" 2>/dev/null && exit 0; exit 1 ;;
  "release create") p=""; r=""; for a in "$@"; do [ "$p" = "-R" ] && r=$a; p=$a; done
                    echo "ghrel $r" >>"$STUB_STATE"; exit 0 ;;
esac
exit 0
SH
cat >"$W/bin/glab" <<'SH'
#!/bin/sh
echo "glab $*" >>"$STUB_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "release view") grep -qx "glrel $5" "$STUB_STATE" 2>/dev/null && exit 0; exit 1 ;;
  "release create") p=""; for a in "$@"; do [ "$p" = "-R" ] && r=$a; p=$a; done
                    echo "glrel $r" >>"$STUB_STATE"; exit 0 ;;
esac
exit 0
SH
chmod +x "$W/bin/gh" "$W/bin/glab"

# mk <name> : fresh scenario with bare remotes r1 r2 and a work repo whose HEAD is the release commit
mk() {
  D="$W/$1"; mkdir -p "$D"; : >"$D/stub.log"; : >"$D/stub.state"
  "${G[@]}" init -q --bare "$D/r1.git"; "${G[@]}" init -q --bare "$D/r2.git"
  "${G[@]}" init -q "$D/w"
  ( cd "$D/w" && printf '# Changelog\n\n## Unreleased — base\n' >CHANGELOG.md && "${G[@]}" add CHANGELOG.md && "${G[@]}" commit -q -m base \
    && "${G[@]}" remote add r1 "$D/r1.git" && "${G[@]}" remote add r2 "$D/r2.git" \
    && "${G[@]}" push -q r1 HEAD:refs/heads/main && "${G[@]}" push -q r2 HEAD:refs/heads/main \
    && printf '# Changelog\n\n## %s — 2026-01-01 — PROVISIONAL pre-release\nNOTES-BODY\n\n## Unreleased — base\n' "$TAG" >CHANGELOG.md \
    && "${G[@]}" commit -q -am release )
  REL="$(git -C "$D/w" rev-parse HEAD)"; BASE="$(git -C "$D/w" rev-parse HEAD~1)"
}
reject_main() { # bare-repo path : per-ref update hook that refuses ONLY refs/heads/main (other refs of the same
  # push are accepted unless the push is atomic, which is exactly what C2 and C7 tell apart)
  printf '#!/bin/sh\n[ "$1" = refs/heads/main ] && { echo "rejected by test hook" >&2; exit 1; }\nexit 0\n' >"$1/hooks/update"
  chmod +x "$1/hooks/update"
}
run() { # run the script in $D/w with extra args; sets RC and OUT
  OUT="$(cd "$D/w" && PATH="$W/bin:$PATH" STUB_LOG="$D/stub.log" STUB_STATE="$D/stub.state" \
         bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check "$@" 2>&1)"; RC=$?
}
rmain() { git --git-dir="$D/$1.git" rev-parse -q --verify refs/heads/main 2>/dev/null || echo -; }
rtag()  { git --git-dir="$D/$1.git" rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || echo -; }
last()  { printf '%s\n' "$OUT" | tail -n 1 | cut -d' ' -f1-2; }

# C1 happy path: both remotes get main and the tag; exit 0
mk c1; run
chk "C1 exit 0" "$RC" 0; chk "C1 RESULT OK" "$(last)" "RESULT: OK"
chk "C1 r1 main" "$(rmain r1)" "$REL"; chk "C1 r2 tag peels to release" "$(rtag r2)" "$REL"
chk "C1 annotated tag" "$(git -C "$D/w" cat-file -t "refs/tags/$TAG")" tag

# C2 a remote refuses main: the atomic push leaves NO tag there, the run fails (exit 1)
mk c2; reject_main "$D/r2.git"; run
chk "C2 exit 1" "$RC" 1; chk "C2 RESULT FAIL" "$(last)" "RESULT: FAIL"
chk "C2 r2 has no tag" "$(rtag r2)" -; chk "C2 r2 main unchanged" "$(rmain r2)" "$BASE"
chk "C2 r1 still OK" "$(rtag r1)" "$REL"
printf '%s\n' "$OUT" | grep -q '^FAIL VERIFY r2 MISMATCH' && ok "C2 MISMATCH reported for r2" || bad "C2 MISMATCH reported for r2"

# C3 resume: the same command after the cause is removed reuses the tag object and finishes
obj1="$(git -C "$D/w" rev-parse "refs/tags/$TAG")"; rm -f -- "$D/r2.git/hooks/update"; run
chk "C3 resume exit 0" "$RC" 0
chk "C3 tag object reused" "$(git -C "$D/w" rev-parse "refs/tags/$TAG")" "$obj1"
chk "C3 r2 tag object equals local" "$(git --git-dir="$D/r2.git" rev-parse "refs/tags/$TAG")" "$obj1"
printf '%s\n' "$OUT" | grep -q 'PUSH r1 already OK' && ok "C3 OK remote skipped" || bad "C3 OK remote skipped"

# C4 a failed fetch aborts before any write (no tag, nothing pushed anywhere)
mk c4; git -C "$D/w" remote set-url r2 "$D/missing.git"; run
chk "C4 exit 1" "$RC" 1; printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r2' && ok "C4 fetch abort" || bad "C4 fetch abort"
chk "C4 no local tag" "$(git -C "$D/w" rev-parse -q --verify "refs/tags/$TAG" || echo -)" -
chk "C4 r1 untouched" "$(rmain r1)" "$BASE"

# C5 a remote main that moved (not an ancestor of the release commit) aborts before any write
mk c5; ( cd "$D/w" && "${G[@]}" checkout -q -b side HEAD~1 && "${G[@]}" commit -q --allow-empty -m other \
         && "${G[@]}" push -q r2 HEAD:refs/heads/main && "${G[@]}" checkout -q - ) ; run
chk "C5 exit 1" "$RC" 1; printf '%s\n' "$OUT" | grep -q 'is not an ancestor' && ok "C5 ancestor abort" || bad "C5 ancestor abort"
chk "C5 no local tag" "$(git -C "$D/w" rev-parse -q --verify "refs/tags/$TAG" || echo -)" -

# C6 the first CHANGELOG heading at the release commit must name the tag
mk c6; OUT="$(cd "$D/w" && bash "$S" --tag other-v1 --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C6 exit 1" "$RC" 1; printf '%s\n' "$OUT" | grep -q 'first .## . heading' && ok "C6 heading abort" || bad "C6 heading abort"

# C7 server without atomic push: main first; a refused main never gets the tag
mk c7; git --git-dir="$D/r2.git" config receive.advertiseAtomic false; reject_main "$D/r2.git"; run
chk "C7 exit 1" "$RC" 1; chk "C7 r2 has no tag" "$(rtag r2)" -
printf '%s\n' "$OUT" | grep -q 'no atomic push' && ok "C7 fallback path taken" || bad "C7 fallback path taken"
rm -f -- "$D/r2.git/hooks/update"; run
chk "C7 fallback completes on resume" "$RC" 0; chk "C7 r2 tag" "$(rtag r2)" "$REL"

# C8 a remote tag of the same name that is a different object stops the run; nothing is replaced
mk c8; ( cd "$D/w" && "${G[@]}" tag -a "$TAG" -m impostor HEAD~1 && "${G[@]}" push -q r2 "refs/tags/$TAG" && "${G[@]}" tag -d "$TAG" >/dev/null )
imp="$(git --git-dir="$D/r2.git" rev-parse "refs/tags/$TAG")"; run
chk "C8 exit 1" "$RC" 1; chk "C8 impostor kept" "$(git --git-dir="$D/r2.git" rev-parse "refs/tags/$TAG")" "$imp"
chk "C8 r1 untouched" "$(rmain r1)" "$BASE"

# C9 platform releases only for OK remotes; --ref on glab; github de-duplicated by id; gap = exit 5
mk c9; reject_main "$D/r2.git"
run --release gitlab:r2:grp/two --release github:r1:acc/one --release github:r1:acc/alias --release gitlab:r1:grp/one
chk "C9 exit 1 (r2 not OK)" "$RC" 1
grep -q 'glab release create.*grp/two' "$D/stub.log" && bad "C9 no release on the non-OK remote" || ok "C9 no release on the non-OK remote"
grep -q "glab release create $TAG -R grp/one --ref $REL" "$D/stub.log" && ok "C9 glab gets --ref SHA" || bad "C9 glab gets --ref SHA"
chk "C9 one github create for one repository id" "$(grep -c 'gh release create' "$D/stub.log")" 1
grep -q 'gh release create.*--verify-tag' "$D/stub.log" && ok "C9 gh --verify-tag" || bad "C9 gh --verify-tag"
rm -f -- "$D/r2.git/hooks/update"; : >"$D/stub.log"
run --release gitlab:r2:grp/two --release github:r1:acc/one --release gitlab:r1:grp/one --release github:r2:acc/nope
chk "C9 resume with an inaccessible repo exits 5 (GAPS)" "$RC" 5
chk "C9 existing releases not re-created" "$(grep -c 'release create' "$D/stub.log")" 1
grep -q "glab release create $TAG -R grp/two --ref $REL" "$D/stub.log" && ok "C9 resumed release on the now-OK remote" || bad "C9 resumed release on the now-OK remote"

# C10 dry run writes nothing
mk c10; run --dry-run
chk "C10 exit 0" "$RC" 0; chk "C10 no tag" "$(git -C "$D/w" rev-parse -q --verify "refs/tags/$TAG" || echo -)" -
chk "C10 r1 untouched" "$(rmain r1)" "$BASE"

# C11 usage: the remote list is required (never guessed)
OUT="$(bash "$S" --tag "$TAG" --sha deadbeef 2>&1)"; RC=$?; chk "C11 missing --remotes is usage error" "$RC" 2

# C12 the script never forces (static check of the source)
if grep -vE '^[[:space:]]*#' "$S" | grep -nE -- '--force|\+refs/|git push[^#]*[[:space:]]\+[A-Za-z0-9]|tag -d|push --delete|push[^#]* :refs' >/dev/null; then bad "C12 no force/delete in script"; else ok "C12 no force/delete in script"; fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
