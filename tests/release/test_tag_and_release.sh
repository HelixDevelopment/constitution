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
# Exit 0 when every case passes, 1 when a case failed, 77 when a case was SKIPPED (suite_exit of
# tests/release/env_allow.sh; RELEASE_TESTS_ALLOW_SKIP=1 makes a skip exit 0). Prints "RESULT: pass=N fail=M".
set -u
# round 6 (K3): the release scripts pass an allow-listed environment to their children; the state-file
# variables of the test doubles are added to that list here (rc_env_lockdown refuses credential-like names).
# Round 11: RELEASE_ENV_KEEP reaches LOCAL children only (the gitea publisher double here); git, gh, glab and
# timeout run through rc_net, whose environment is the fixed network allow-list. Their doubles therefore read
# their state from the file $W/.stubenv (written by mk for each scenario, a default per name that an exported
# value of a local child overrides), never only from their environment.
export RELEASE_ENV_KEEP="STUB_LOG STUB_STATE GITEA_MODE READY SEEN"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${TAR_SCRIPT:-$ROOT/scripts/release/tag_and_release.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
. "$HERE/env_allow.sh"   # round 7: the allow-list, the dirty environment and the SIGHUP detector of the L1 L2 L4 cases
skipped=0; skp(){ skipped=$((skipped+1)); echo "SKIP $*"; }
HUPWHY="SIGHUP is ignored in this process (nohup or an ignoring parent): bash cannot trap a signal that was ignored when it started, so the case would test the caller's signal state, not the script (round 7, L4)"
case "$(hup_control)" in ok) ok "L4 the SIGHUP detector sees an ignored and a not ignored SIGHUP (control needles)" ;;
  ok-positive-only) ok "L4 the SIGHUP detector sees an ignored SIGHUP (control needle; the negative needle cannot run: SIGHUP is ignored here)" ;;
  *) bad "L4 the SIGHUP detector is blind: $(hup_control)" ;; esac
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
W="$(mktemp -d "${TMPDIR:-/tmp}/tar_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # round 7 (L5): a signal ends the suite (the EXIT trap cleans up); a handler that returns would let the suite run on
TAG=fixture-v9.1
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c advice.detachedHead=false)

# ---- test doubles for gh / glab (UNIT-CLASS, record every call) ----
mkdir -p "$W/bin"
cat >"$W/bin/gh" <<'SH'
#!/bin/sh
[ -r "${0%/*}/../.stubenv" ] && . "${0%/*}/../.stubenv"
echo "gh $*" >>"$STUB_LOG"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api repos/acc/one"|"api repos/acc/alias") echo 42; exit 0 ;;
  "api repos/acc/two") echo 43; exit 0 ;;
  "api repos/acc/evil") echo "ZZGHID https://u:ZZGHPW@h/x"; exit 0 ;;
  "api "*) exit 1 ;;
  "release view") grep -qx "ghrel $5" "$STUB_STATE" 2>/dev/null && exit 0; exit 1 ;;
  "release create") p=""; r=""; for a in "$@"; do [ "$p" = "-R" ] && r=$a; p=$a; done
                    echo "ghrel $r" >>"$STUB_STATE"; exit 0 ;;
esac
exit 0
SH
cat >"$W/bin/glab" <<'SH'
#!/bin/sh
[ -r "${0%/*}/../.stubenv" ] && . "${0%/*}/../.stubenv"
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
  # round 11: the state of the network doubles (they run through rc_net and do not get RELEASE_ENV_KEEP)
  for v in STUB_LOG=stub.log STUB_STATE=stub.state SEEN=seen READY=ready NETLOG=net.log ENVLOG=env; do
    printf ': "${%s:=%s}"\n' "${v%%=*}" "$D/${v#*=}"; done >"$W/.stubenv"
  "${G[@]}" init -q --bare "$D/r1.git"; "${G[@]}" init -q --bare "$D/r2.git"
  "${G[@]}" init -q "$D/w"
  # round 11 (N-3 of the round-10 review): the work repository has its own fake identity, so the annotated tag the
  # script makes needs no identity of the caller (no ~/.gitconfig: the suite runs with an empty HOME too)
  git -C "$D/w" config user.email zz-tag-test@example.invalid; git -C "$D/w" config user.name zz-tag-test
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

# ---- CON-227: cases a-f of the review harness (rev_rel734c/h2.sh), one per surviving mutant ----
ltag() { git -C "$D/w" rev-parse -q --verify "refs/tags/$TAG" >/dev/null && echo yes || echo no; }
# C13 (mutant T4) a dirty working tree aborts before any write
mk c13; echo x >"$D/w/dirty"; run
chk "C13 dirty tree exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^ABORT working tree is not clean' && ok "C13 dirty-tree abort" || bad "C13 dirty-tree abort"
chk "C13 no local tag" "$(ltag)" no; chk "C13 r1 untouched" "$(rmain r1)" "$BASE"
# C14 (mutant T6) HEAD is a later commit than SHA (clean tree): abort, nothing tagged or pushed
mk c14; ( cd "$D/w" && "${G[@]}" commit -q --allow-empty -m after ); run
chk "C14 HEAD!=SHA exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^ABORT HEAD .* != ' && ok "C14 HEAD!=SHA abort" || bad "C14 HEAD!=SHA abort"
chk "C14 no local tag" "$(ltag)" no; chk "C14 r1 untouched" "$(rmain r1)" "$BASE"
# C15 (mutant T3) a correct local tag while a remote holds another object of the same name: abort
# before any write, the impostor kept, the other remote untouched
mk c15; ( cd "$D/w" && "${G[@]}" tag -a "$TAG" -m impostor HEAD~1 && "${G[@]}" push -q r2 "refs/tags/$TAG" \
          && "${G[@]}" tag -d "$TAG" >/dev/null && "${G[@]}" tag -a "$TAG" -m real HEAD )
imp="$(git --git-dir="$D/r2.git" rev-parse "refs/tags/$TAG")"; run
chk "C15 exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^ABORT r2 has a different' && ok "C15 different-object abort" || bad "C15 different-object abort"
chk "C15 impostor kept" "$(git --git-dir="$D/r2.git" rev-parse "refs/tags/$TAG")" "$imp"
chk "C15 r1 untouched" "$(rmain r1)" "$BASE"
# C16 (mutant T2) a remote whose main is already SHA but which has no tag is NOT skipped as OK
mk c16; git -C "$D/w" push -q r2 "$REL:refs/heads/main"; run
chk "C16 exit 0" "$RC" 0; chk "C16 r2 tag pushed" "$(rtag r2)" "$REL"
printf '%s\n' "$OUT" | grep -q 'PUSH r2 already OK' && bad "C16 r2 not skipped" || ok "C16 r2 not skipped"
# C17-C20 (mutant T5 and CON-233) the gitea leg, through a committed UNIT-CLASS publisher double that
# records its arguments and answers per GITEA_MODE
mkg() { mk "$1"; mkdir -p "$D/w/scripts"
  cat >"$D/w/scripts/release_publish_gitea.sh" <<'SH'
#!/bin/sh
echo "gitea $*" >>"$STUB_LOG"
case "${GITEA_MODE:-ok}" in
  ok) exit 0 ;;
  notoken) echo "SKIPPED-NO-TOKEN: env var M3W_GITEA_TOKEN is not set; nothing was published" >&2; exit 3 ;;
  config) echo "release_publish_gitea: jq is required" >&2; exit 3 ;;
  api) echo "release_publish_gitea: API failure" >&2; exit 4 ;;
  midline) echo "release_publish_gitea: notes file x/SKIPPED-NO-TOKEN: y is not readable" >&2; exit 3 ;;
  rawapi) echo "warning: https://u:ZZGRAWPW@h/x ZZGITEARAW" >&2; echo "release_publish_gitea: API failure" >&2; exit 4 ;;
  rawcfg) echo "error: ZZGITEARAW3 https://u:ZZGRAWPW3@h/x" >&2; echo "release_publish_gitea: jq is required" >&2; exit 3 ;;
  owncred) echo "release_publish_gitea: create failed https://u:ZZOWNPW@h/x" >&2; exit 4 ;;
esac
exit 9
SH
  ( cd "$D/w" && "${G[@]}" add scripts && "${G[@]}" commit -q --amend --no-edit ); REL="$(git -C "$D/w" rev-parse HEAD)"; }
GSPEC=gitea:r1:https://g.example:o/r
mkg c17; GITEA_MODE=ok run --release "$GSPEC"
chk "C17 gitea ok exit 0" "$RC" 0
printf '%s\n' "$OUT" | grep -q "^RELEASE $GSPEC CREATED-OR-UPDATED" && ok "C17 gitea created" || bad "C17 gitea created"
grep -q -- "--base-url https://g.example --repo o/r" "$D/stub.log" && ok "C17 base URL and repo passed" || bad "C17 base URL and repo passed"
mkg c18; GITEA_MODE=notoken run --release "$GSPEC"
chk "C18 gitea missing token is a GAP (exit 5)" "$RC" 5
printf '%s\n' "$OUT" | grep -q "^GAP RELEASE $GSPEC SKIPPED-NO-TOKEN" && ok "C18 SKIPPED-NO-TOKEN gap" || bad "C18 SKIPPED-NO-TOKEN gap"
mkg c19; GITEA_MODE=config run --release "$GSPEC"
chk "C19 gitea rc 3 without SKIPPED-NO-TOKEN is a FAIL (exit 1)" "$RC" 1
printf '%s\n' "$OUT" | grep -q "^FAIL RELEASE $GSPEC REFUSED rc=3" && ok "C19 refusal named" || bad "C19 refusal named"
mkg c20; GITEA_MODE=api run --release "$GSPEC"
chk "C20 gitea rc 4 exit 1" "$RC" 1
# C20b (R2) the SKIPPED-NO-TOKEN token in the middle of a line is NOT the no-credential signal: FAIL, not GAP
mkg c20b; GITEA_MODE=midline run --release "$GSPEC"
chk "C20b gitea rc 3 with the token mid-line is a FAIL (exit 1)" "$RC" 1
printf '%s\n' "$OUT" | grep -q "^GAP RELEASE $GSPEC" && bad "C20b mid-line token is not a GAP" || ok "C20b mid-line token is not a GAP"
# C20c (R6) the gitea stderr temp file is removed on every rc: run with a private TMPDIR and count leftovers
mkg c20c; mkdir -p "$D/gtmp"
for m in ok notoken config api; do TMPDIR="$D/gtmp" GITEA_MODE=$m run --release "$GSPEC"; done
left="$(find "$D/gtmp" -maxdepth 1 -name 'tar_gitea.*' | wc -l)"
[ -d "$D/gtmp" ] && ok "C20c private TMPDIR exists (control)" || bad "C20c private TMPDIR exists (control)"
[ "$left" = 0 ] && ok "C20c gitea stderr temp file removed (all rcs)" || bad "C20c gitea stderr temp file removed ($left left)"
# C22-C23 (CON-233) the REAL publisher (scripts/release_publish_gitea.sh of this repository, committed into
# the fixture): no token is a GAP; a token outside the charset is a configuration refusal, a FAIL. Both
# stop before any network call (the token check precedes curl). The token value is a fixture string,
# not a credential.
if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  mkr() { mk "$1"; mkdir -p "$D/w/scripts/release"; cp -- "$ROOT/scripts/release_publish_gitea.sh" "$D/w/scripts/release_publish_gitea.sh"; cp -- "$ROOT/scripts/release/redact_cut.sh" "$D/w/scripts/release/redact_cut.sh"
    ( cd "$D/w" && "${G[@]}" add scripts && "${G[@]}" commit -q --amend --no-edit ); REL="$(git -C "$D/w" rev-parse HEAD)"; }
  mkr c22; M3W_GITEA_TOKEN="" run --release "$GSPEC"
  chk "C22 real publisher, no token: GAP exit 5" "$RC" 5
  printf '%s\n' "$OUT" | grep -q "^GAP RELEASE $GSPEC SKIPPED-NO-TOKEN" && ok "C22 SKIPPED-NO-TOKEN gap" || bad "C22 SKIPPED-NO-TOKEN gap"
  mkr c23; M3W_GITEA_TOKEN="bad token!" run --release "$GSPEC"
  chk "C23 real publisher, bad token charset: FAIL exit 1" "$RC" 1
  printf '%s\n' "$OUT" | grep -q "^FAIL RELEASE $GSPEC REFUSED rc=3 (configuration or precondition: release_publish_gitea: token has characters" \
    && ok "C23 refusal names the publisher's reason" || bad "C23 refusal names the publisher's reason"
  printf '%s\n' "$OUT" | grep -q 'bad token!' && bad "C23 token value not printed" || ok "C23 token value not printed"
else
  skp "C22-C23 real gitea publisher: jq or curl is not installed (the publisher refuses before its token check)"   # round 9 (F5): counted, so the suite exits 77
fi
# C21 (n-4) a failed fetch prints git's stderr with any URL userinfo redacted. git 2.53 already
# redacts its own "unable to access" message, so a UNIT-CLASS git double answers the fetch with an
# unredacted URL (the case of a git version or message that does not redact); every other git call
# goes to the real git.
REALGIT="$(command -v git)"; mkdir -p "$W/gitbin"
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { echo "fatal: unable to access '"'"'http://user:s3cr3tvalue@127.0.0.1:9/none.git/'"'"'" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
chmod +x "$W/gitbin/git"
mk c21; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C21 exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q 's3cr3tvalue' && bad "C21 userinfo not printed" || ok "C21 userinfo not printed"
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1' && ok "C21 fetch abort (control)" || bad "C21 fetch abort (control)"
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1 main failed (git exit 128, reason class: unknown; git.s own message is withheld' && ok "C21 the reason class is printed (positive needle)" || bad "C21 the reason class is printed (positive needle)"
printf '%s\n' "$OUT" | grep -q 'unable to access\|127.0.0.1:9' && bad "C21 no byte of git's message is printed" || ok "C21 no byte of git's message is printed"
# C21b a long message: the userinfo starts before byte 400 but its '@' falls past it (redact first, then cut)
PAD="$(printf 'x%.0s' $(seq 1 370))"
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { echo "fatal: %s '"'"'https://user:SECRETTOKENVALUE1234567890@host.invalid/r.git'"'"'" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$PAD" "$REALGIT" >"$W/gitbin/git"
mk c21b; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C21b exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'SECRETTO' && bad "C21b long message: secret prefix not printed" || ok "C21b long message: secret prefix not printed"
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1' && ok "C21b fetch abort (control)" || bad "C21b fetch abort (control)"

# C21c (G1) a failed PUSH prints git's stderr redacted too: the git double answers push with an unredacted
# URL whose password holds a raw "@" (G2); a second URL on the same line (G3, kills the g-flag mutant)
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = push ] && { echo "fatal: unable to access '"'"'https://user:ZZPUSHSECRET@ZZRAWAT@h1.invalid/r.git/'"'"' and '"'"'http://v:ZZTWOSECRET@h2.invalid/q'"'"'" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
mk c21c; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C21c exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^PUSH r1 failed (git exit 128, reason class: unknown; git.s own message is withheld' && ok "C21c push failure printed with its class (control)" || bad "C21c push failure printed with its class (control)"
printf '%s\n' "$OUT" | grep -q 'ZZPUSHSECRET\|ZZRAWAT\|ZZTWOSECRET' && bad "C21c push stderr: no secret printed (raw @ and second URL included)" || ok "C21c push stderr: no secret printed (raw @ and second URL included)"
printf '%s\n' "$OUT" | grep -q 'unable to access\|h1.invalid\|h2.invalid' && bad "C21c no byte of git's push message is printed" || ok "C21c no byte of git's push message is printed"
printf '%s\n' "$OUT" | grep -q '^INFO r1: tag pushed only' && bad "C21c (G8) no 'tag pushed only' after a failed push" || ok "C21c (G8) no 'tag pushed only' after a failed push"
printf '%s\n' "$OUT" | grep -q '^INFO r1: .*NOT OK' && ok "C21c (G8) the INFO line says the push is NOT OK" || bad "C21c (G8) the INFO line says the push is NOT OK"
# C21d (G1 class) uncaptured stderr of other git commands (here a fetch that prints a second line after exit-0 is not
# an abort; the exit-time flush path) is redacted: the double prints an unredacted URL from "git merge-base"
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = merge-base ] && { echo "warning: https://u:ZZEXTSECRET@h.invalid/x" >&2; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
mk c21d; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run 2>&1)"; RC=$?
chk "C21d dry-run still exit 0" "$RC" 0
printf '%s\n' "$OUT" | grep -q 'ZZEXTSECRET' && bad "C21d exit-time stderr flush: no secret" || ok "C21d exit-time stderr flush: no secret"
printf '%s\n' "$OUT" | grep -q 'https://<redacted>@h.invalid' && ok "C21d exit-time flush prints the redacted line (positive needle)" || bad "C21d exit-time flush prints the redacted line (positive needle)"
# C21e (G4) the 400-byte cap: a 5000-byte unredactable message prints as exactly 400 bytes (control: it is printed)
BIG="$(printf 'y%.0s' $(seq 1 5000))"
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { echo "%s" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$BIG" "$REALGIT" >"$W/gitbin/git"
mk c21e; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
printf '%s\n' "$OUT" | grep -q 'yyyyyyyyyy' && bad "C21e a 5000-byte git message: nothing of it printed" || ok "C21e a 5000-byte git message: nothing of it printed"
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1 main failed (git exit 128, reason class: unknown' && ok "C21e the abort names the class (control)" || bad "C21e the abort names the class (control)"
# The helper itself (every credential shape, the cut, the locale) is unit-tested in tests/release/test_redact_cut.sh.
# C24 (class census, static) no external-command output is cut outside the helper: every `head -c` in the
# release scripts is the helper's own line
cnt="$(grep -vE '^[[:space:]]*#' "$S" "$ROOT/scripts/release/derive_release_facts.sh" "$ROOT/scripts/release_publish_gitea.sh" | grep -c 'head -c')"
chk "C24 no head -c in the three scripts (only rc_redact_cut cuts)" "$cnt" 0
grep -c '^rc_redact_cut()' "$ROOT/scripts/release/redact_cut.sh" | grep -q '^1$' && ok "C24 the helper defines the one cutter (control needle)" || bad "C24 the helper defines the one cutter (control needle)"
cnt="$(grep -vE '^[[:space:]]*#' "$S" "$ROOT/scripts/release/derive_release_facts.sh" "$ROOT/scripts/release_publish_gitea.sh" | grep -c 'mktemp "')"
chk "C24b no temp FILE outside a private run directory in the three scripts (mktemp -d only)" "$cnt" 0

# ---- round 4 (CON-234 class closed by construction): the real git binary and the real script ----
# C25 (H1) real git 2.53, no double: a password holding a raw "/" and a query-string token are printed by
# git verbatim; the script must print neither. host.invalid never resolves, so no network is reached.
mk c25; git -C "$D/w" remote set-url r1 'https://u:ab/ZZSLASHSECRET@host.invalid/r'; run
chk "C25 real git, raw '/' in the password: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1' && ok "C25 fetch abort (control)" || bad "C25 fetch abort (control)"
printf '%s\n' "$OUT" | grep -q 'ZZSLASHSECRET' && bad "C25 raw '/' password not printed" || ok "C25 raw '/' password not printed"
printf '%s\n' "$OUT" | grep -q 'reason class: url-invalid' && ok "C25 the class of git's message is printed (positive needle)" || bad "C25 the class of git's message is printed (positive needle)"
printf '%s\n' "$OUT" | grep -q 'URL rejected\|host.invalid' && bad "C25 no byte of git's message is printed" || ok "C25 no byte of git's message is printed"
mk c25b; git -C "$D/w" remote set-url r1 'https://host.invalid/r?access_token=ZZQUERYSECRET&x=1'; run
chk "C25b real git, query token: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'ZZQUERYSECRET' && bad "C25b query token not printed" || ok "C25b query token not printed"
printf '%s\n' "$OUT" | grep -q 'reason class: network-unreachable' && ok "C25b the class is printed (positive needle)" || bad "C25b the class is printed (positive needle)"
printf '%s\n' "$OUT" | grep -q 'access_token' && bad "C25b the parameter name is not printed either" || ok "C25b the parameter name is not printed either"
# C26 (H2/H3, Q3 Q7 Q8 Q9) nothing is left in TMPDIR after a success, a fetch failure, a push failure,
# a failed fallback push and every gitea rc. Control needle: a git double records what TMPDIR holds while
# the script runs (the run directory must be seen there, else the census would be blind).
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { ls -A "$TMPDIR" >>"$SEEN"; echo "redact=$GIT_TRACE_REDACT" >>"$SEEN"; echo "prompt=$GIT_TERMINAL_PROMPT" >>"$SEEN"; for d in "$TMPDIR"/tar_run.*; do [ -d "$d" ] && echo "mode=$(stat -c %%a "$d")" >>"$SEEN"; done; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
lrun() { TMPDIR="$D/tmp" SEEN="$D/seen" GIT_TRACE_REDACT=0 PATH="$W/gitbin:$PATH" run; }
left() { find "$D/tmp" -mindepth 1 | wc -l | tr -d ' '; }
mk c26; mkdir -p "$D/tmp"; : >"$D/seen"; lrun
chk "C26 success: exit 0" "$RC" 0; chk "C26 success: nothing left in TMPDIR" "$(left)" 0
grep -q '^tar_run\.' "$D/seen" && ok "C26 the run directory is created under TMPDIR (control needle)" || bad "C26 the run directory is created under TMPDIR (control needle)"
grep -qx 'redact=1' "$D/seen" && ok "C26 git runs with GIT_TRACE_REDACT=1 even when the caller set 0" || bad "C26 git runs with GIT_TRACE_REDACT=1 even when the caller set 0"
grep -qx 'prompt=0' "$D/seen" && ok "C34 git runs with GIT_TERMINAL_PROMPT=0" || bad "C34 git runs with GIT_TERMINAL_PROMPT=0"
grep -q '^mode=' "$D/seen" && ok "C33 the run directory mode is read during the run (control needle)" || bad "C33 the run directory mode is read during the run (control needle)"
grep '^mode=' "$D/seen" | grep -vqx 'mode=700' && bad "C33 the run directory is mode 700 (V13)" || ok "C33 the run directory is mode 700 (V13)"
mk c26f; mkdir -p "$D/tmp"; git -C "$D/w" remote set-url r2 "$D/missing.git"; lrun
chk "C26 fetch failure: exit 1" "$RC" 1; chk "C26 fetch failure: nothing left in TMPDIR" "$(left)" 0
mk c26p; mkdir -p "$D/tmp"; reject_main "$D/r2.git"; lrun
chk "C26 push failure: exit 1" "$RC" 1; chk "C26 push failure: nothing left in TMPDIR" "$(left)" 0
mk c26n; mkdir -p "$D/tmp"; git --git-dir="$D/r2.git" config receive.advertiseAtomic false; reject_main "$D/r2.git"; lrun
chk "C26 fallback push failure: exit 1" "$RC" 1; chk "C26 fallback push failure: nothing left in TMPDIR" "$(left)" 0
mkg c26g; mkdir -p "$D/tmp"
for m in ok notoken config api; do TMPDIR="$D/tmp" GITEA_MODE=$m run --release "$GSPEC"; done
chk "C26 gitea legs (all rcs): nothing left in TMPDIR" "$(left)" 0
# C27 (H2) a SIGTERM or SIGHUP while git is writing a credential to stderr leaves nothing behind and
# prints nothing unredacted. The git double writes the secret, then sleeps; the signal goes to the script.
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { echo "fatal: '"'"'https://u:ZZSIGSECRET@h.invalid/r'"'"'" >&2; : >"${READY:-/dev/null}"; sleep 3; exit 128; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
waitf() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i+1)); done; }
for sg in TERM HUP; do
  if [ "${sg%:*}" = HUP ] && hup_ignored; then skp "C27 HUP: $HUPWHY"; continue; fi
  mk "c27$sg"; mkdir -p "$D/tmp"
  ( cd "$D/w" && READY="$D/ready" TMPDIR="$D/tmp" PATH="$W/gitbin:$PATH" exec bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check ) >"$D/sig.out" 2>&1 &
  sp=$!; waitf "$D/ready"; kill -s "$sg" "$sp"; wait "$sp"; src=$?
  [ "$src" -ne 0 ] && ok "C27 $sg: the run ends non-zero (rc $src)" || bad "C27 $sg: the run ends non-zero (rc $src)"
  chk "C27 $sg: nothing left in TMPDIR" "$(left)" 0
  grep -q 'ZZSIGSECRET' "$D/sig.out" && bad "C27 $sg: no secret printed" || ok "C27 $sg: no secret printed"
  grep -q '^== .* start' "$D/sig.out" && ok "C27 $sg: the script had started (control)" || bad "C27 $sg: the script had started (control)"
done
# C28 (I-1) the reason of a failed non-atomic fallback push is printed, redacted
mk c28; git --git-dir="$D/r2.git" config receive.advertiseAtomic false
printf '#!/bin/sh\n[ "$1" = refs/heads/main ] && { echo "rejected by test hook https://u:ZZHOOKSECRET@h.invalid/x" >&2; exit 1; }\nexit 0\n' >"$D/r2.git/hooks/update"; chmod +x "$D/r2.git/hooks/update"; run
chk "C28 exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^PUSH r2 main push failed; tag NOT pushed (git exit 1, reason class: remote-rejected' && ok "C28 the fallback push failure carries git's reason class" || bad "C28 the fallback push failure carries git's reason class"
printf '%s\n' "$OUT" | grep -q 'rejected by test hook' && bad "C28 no byte of the hook's message is printed" || ok "C28 no byte of the hook's message is printed"
printf '%s\n' "$OUT" | grep -q 'ZZHOOKSECRET' && bad "C28 the reason is redacted" || ok "C28 the reason is redacted"
# C29 (I-3) the exit-time flush says when it was cut
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = merge-base ] && { printf "w%%.0s" $(seq 1 3000) >&2; echo >&2; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
mk c29; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run 2>&1)"; RC=$?
chk "C29 dry-run exit 0" "$RC" 0
printf '%s\n' "$OUT" | grep -q '^(truncated: [0-9]* more bytes not shown)$' && ok "C29 the cut flush ends with a truncation marker" || bad "C29 the cut flush ends with a truncation marker"
# C30 (census, xtrace) the script run under bash -x prints no credential either
mk c30; git -C "$D/w" remote set-url r1 'https://u:ab/ZZXTRACESECRET@host.invalid/r'
OUT="$(cd "$D/w" && bash -x "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C30 bash -x run: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'ZZXTRACESECRET' && bad "C30 bash -x run: no secret printed" || ok "C30 bash -x run: no secret printed"
printf '%s\n' "$OUT" | grep -q 'reason class: url-invalid' && ok "C30 bash -x run: the class of git's message is printed (positive needle)" || bad "C30 bash -x run: the class of git's message is printed (positive needle)"

# ---- round 5 (structural, CON-234 class): network-command output is never printed; caller values validated ----
# C31 (J1 end to end, real git 2.53) a password holding "token:" no longer reaches the output
mk c31; git -C "$D/w" remote set-url r1 'https://user:SECab/cdtoken:LEAKPARTRET@127.0.0.1:1/r.git'; run
chk "C31 real git, 'token:' inside the password: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'SECab\|cdtoken\|LEAKPART' && bad "C31 no part of the password is printed (J1)" || ok "C31 no part of the password is printed (J1)"
printf '%s\n' "$OUT" | grep -q 'reason class: url-invalid' && ok "C31 the class is printed (positive needle)" || bad "C31 the class is printed (positive needle)"
# C32 (V8) only the publisher's OWN message lines are printed from its stderr, on every failure branch
mkg c32; GITEA_MODE=rawapi run --release "$GSPEC"
chk "C32 publisher rc 4: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q "^FAIL RELEASE $GSPEC failed rc=4: release_publish_gitea: API failure" && ok "C32 the publisher's own line is printed (positive needle)" || bad "C32 the publisher's own line is printed (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZGITEARAW\|ZZGRAWPW' && bad "C32 a line that is not the publisher's own is not printed (rc 4)" || ok "C32 a line that is not the publisher's own is not printed (rc 4)"
mkg c32b; GITEA_MODE=rawcfg run --release "$GSPEC"
printf '%s\n' "$OUT" | grep -q "^FAIL RELEASE $GSPEC REFUSED rc=3 (configuration or precondition: release_publish_gitea: jq is required" && ok "C32 rc 3: the publisher's own line is printed (positive needle)" || bad "C32 rc 3: the publisher's own line is printed (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZGITEARAW3\|ZZGRAWPW3' && bad "C32 rc 3: a line that is not the publisher's own is not printed" || ok "C32 rc 3: a line that is not the publisher's own is not printed"
# C32c the publisher's own line is redacted before it is printed (defence in depth)
mkg c32c; GITEA_MODE=owncred run --release "$GSPEC"
printf '%s\n' "$OUT" | grep -q 'release_publish_gitea: create failed https://<redacted>@h/x' && ok "C32c the publisher's own line is printed redacted (positive needle)" || bad "C32c the publisher's own line is printed redacted (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZOWNPW' && bad "C32c no credential of the publisher's own line is printed" || ok "C32c no credential of the publisher's own line is printed"
# C34 (rc_git_env) the caller's trace switches are removed: no trace on the output, no trace file written.
# Control: the same switch outside the script does write the trace file (the instrument can see it).
mk c34; git -C "$D/w" remote set-url r1 'https://host.invalid/r'
( cd "$D/w" && GIT_TRACE_CURL="$D/ctrace.control" git ls-remote r1 >/dev/null 2>&1 ); [ -s "$D/ctrace.control" ] && ok "C34 control: GIT_TRACE_CURL writes a file outside the script" || bad "C34 control: GIT_TRACE_CURL writes a file outside the script"
OUT="$(cd "$D/w" && GIT_TRACE=1 GIT_TRACE_PACKET=1 GIT_TRACE_CURL="$D/ctrace" GIT_CURL_VERBOSE=1 bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C34 exit 1 (host does not resolve)" "$RC" 1
[ -e "$D/ctrace" ] && bad "C34 no GIT_TRACE_CURL file is written by the script" || ok "C34 no GIT_TRACE_CURL file is written by the script"
printf '%s\n' "$OUT" | grep -q 'trace: \|packet: \|run_command' && bad "C34 no git trace line on the output" || ok "C34 no git trace line on the output"
# C35 (J5) a network git call that hangs is bounded by RELEASE_NET_TIMEOUT; a TERM during the hang is acted on
# within that bound (the git double replaces itself with sleep, so timeout(1) ends exactly that process)
printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do [ "$a" = fetch ] && { : >"${READY:-/dev/null}"; exec sleep 30; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"
mk c35; t0="$(date +%s)"
OUT="$(cd "$D/w" && RELEASE_NET_TIMEOUT=2 PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?; dt=$(( $(date +%s) - t0 ))
chk "C35 a hung fetch: exit 1" "$RC" 1
[ "$dt" -lt 20 ] && ok "C35 a hung fetch ends within the bound (${dt}s)" || bad "C35 a hung fetch ends within the bound (${dt}s)"
printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1 main failed (git exit 124, reason class: timeout' && ok "C35 the abort says timeout (positive needle)" || bad "C35 the abort says timeout (positive needle)"
OUT="$(cd "$D/w" && RELEASE_NET_TIMEOUT=0 bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C35 RELEASE_NET_TIMEOUT must be a positive number (usage)" "$RC" 2
# C39 (S11) the signal traps end the run through the script's own exit path: exit status 143 / 129, not
# "killed by the signal" (python reads the exact status; bash's wait cannot tell the two apart)
sigrc() { # sigrc SIGNAL DIR : run the tag script in DIR with the hanging-fetch double, signal it once the double is running
  python3 -I - "$1" "$2" "$D/ready" "$S" "$W/gitbin" "$TAG" "$REL" <<'PYS'
import os, signal, subprocess, sys, time
sig, d, ready, s, gb, tag, rel = sys.argv[1:8]
env = dict(os.environ, PATH=gb + ":" + os.environ["PATH"], READY=ready, RELEASE_NET_TIMEOUT="4", TMPDIR=d + "/tmp")
p = subprocess.Popen(["bash", s, "--tag", tag, "--sha", rel, "--remotes", "r1 r2", "--no-badge-check"], cwd=d + "/w", env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(200):
    if os.path.exists(ready): break
    time.sleep(0.1)
p.send_signal(getattr(signal, "SIG" + sig))
print(p.wait(timeout=60))
PYS
}
for sg in TERM:143 HUP:129; do
  if [ "${sg%:*}" = HUP ] && hup_ignored; then skp "C39 HUP: $HUPWHY"; continue; fi
  mk "c39${sg%%:*}"; mkdir -p "$D/tmp"; rm -f -- "$D/ready"
  chk "C39 ${sg%%:*} during a hung fetch: the script exits ${sg#*:} through its trap" "$(sigrc "${sg%%:*}" "$D")" "${sg#*:}"
  chk "C39 ${sg%%:*}: nothing left in TMPDIR" "$(left)" 0
done
# C36 caller values that can hold a credential are validated and never echoed when invalid
mk c36
for bad_spec in 'gitea:r1:https://u:ZZSPEC1@h:o/r' 'github:r1:https://ZZSPEC2@h/x' 'gitlab:r1:u:ZZSPEC3@h/x' 'gitea:r1:https://h/ZZSPEC4:o/r'; do
  run --release "$bad_spec" --dry-run
  chk "C36 bad --release spec is a usage error: ${bad_spec%%:*}" "$RC" 2
  printf '%s\n' "$OUT" | grep -q 'ZZSPEC' && bad "C36 the bad spec is not echoed (${bad_spec%%:*})" || ok "C36 the bad spec is not echoed (${bad_spec%%:*})"
done
printf '%s\n' "$OUT" | grep -q 'bad --release spec number 1' && ok "C36 the refusal names the spec by number (positive needle)" || bad "C36 the refusal names the spec by number (positive needle)"
run --release gitlab:r1:grp/sub/repo --release gitea:r1:http://127.0.0.1:3000:o/r --dry-run
chk "C36 control: a nested GitLab path and a loopback gitea URL are accepted" "$RC" 0
run --frobnicate; printf '%s\n' "$OUT" | grep -q 'unknown argument: --frobnicate' && ok "C36 an option-shaped unknown argument is named (control)" || bad "C36 an option-shaped unknown argument is named (control)"
run '--https://u:ZZARG@h/x'; chk "C36 credential-shaped unknown argument: usage" "$RC" 2
printf '%s\n' "$OUT" | grep -q 'ZZARG' && bad "C36 a credential-shaped unknown argument is not echoed" || ok "C36 a credential-shaped unknown argument is not echoed"
OUT="$(cd "$D/w" && bash "$S" --tag "$TAG" --sha "$REL" --remotes 'r1 https://ZZREM@h/x' --no-badge-check 2>&1)"; RC=$?
chk "C36 a URL as remote name: usage" "$RC" 2
printf '%s\n' "$OUT" | grep -q 'ZZREM' && bad "C36 the unsafe remote name is not echoed" || ok "C36 the unsafe remote name is not echoed"
OUT="$(cd "$D/w" && bash "$S" --tag "$TAG" --sha 'https://ZZSHA@h/x' --remotes 'r1 r2' --no-badge-check 2>&1)"; RC=$?
chk "C36 a non-hex --sha: usage" "$RC" 2
printf '%s\n' "$OUT" | grep -q 'ZZSHA' && bad "C36 the bad --sha is not echoed (not even on the start line)" || ok "C36 the bad --sha is not echoed (not even on the start line)"
# C37 values read back from a server are object ids before they are printed
printf '#!/bin/sh\ncase " $* " in *" ls-remote "*" refs/heads/main "*) printf "ZZLSREMOTE1\\trefs/heads/main\\nZZLSREMOTE2\\trefs/tags/%s\\n" "%s"; exit 0 ;; esac\nexec "%s" "$@"\n' "$TAG" "$TAG" "$REALGIT" >"$W/gitbin/git"
mk c37; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C37 a server answering non-object ids: exit 1" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^FAIL VERIFY r1 MISMATCH' && ok "C37 MISMATCH reported (positive needle)" || bad "C37 MISMATCH reported (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZLSREMOTE' && bad "C37 the server's non-object-id text is not printed" || ok "C37 the server's non-object-id text is not printed"
printf '#!/bin/sh\ncase " $* " in *" ls-remote "*) case " $* " in *" refs/heads/main "*) ;; *) printf "ZZRTAG https://u:ZZRTAGPW@h\\trefs/tags/%s\\n" "%s"; exit 0 ;; esac ;; esac\nexec "%s" "$@"\n' "$TAG" "$TAG" "$REALGIT" >"$W/gitbin/git"
mk c37b; OUT="$(cd "$D/w" && PATH="$W/gitbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C37b a remote tag answer that is not an object id aborts" "$RC" 1
printf '%s\n' "$OUT" | grep -q '^ABORT r1 answered a tag object id that is not an object id' && ok "C37b the abort says so (positive needle)" || bad "C37b the abort says so (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZRTAG' && bad "C37b the answer is not printed" || ok "C37b the answer is not printed"
# C38 a GitHub repository id that is not a number is a GAP and is not printed
mk c38; run --release github:r1:acc/evil
chk "C38 non-numeric repository id: GAPS exit 5" "$RC" 5
printf '%s\n' "$OUT" | grep -q '^GAP RELEASE github:r1:acc/evil NOT-ACCESSIBLE' && ok "C38 the gap is named (positive needle)" || bad "C38 the gap is named (positive needle)"
printf '%s\n' "$OUT" | grep -q 'ZZGHID\|ZZGHPW' && bad "C38 the non-numeric id is not printed" || ok "C38 the non-numeric id is not printed"
# C40 (census, static) a captured external output (variables x_*) is only ever classified, matched or
# filtered to the publisher's own lines; it is never printed or written directly
xl="$(grep -vE '^[[:space:]]*#' "$S" | grep -E '\$\{?x_')"
[ -n "$xl" ] && ok "C40 captured-output variables found (control needle)" || bad "C40 captured-output variables found (control needle)"
badl="$(printf '%s\n' "$xl" | grep -vE '^[[:space:]]*x_[a-z]+="\$\((net|nt) ' | grep -vE 'xcls "\$x_[a-z]+" "\$[a-z]+"' | grep -vE 'case "\$x_[a-z]+" in' | grep -vE 'own1 "\$x_[a-z]+" [0-9]+' | grep -vE "printf '%s\\\\n' \"\\\$x_[a-z]+\" \\| grep -q '\\^SKIPPED-NO-TOKEN:'")"
[ -z "$badl" ] && ok "C40 every use of a captured output is a classification, a decision or the own-line filter" || bad "C40 a captured output is used another way: $badl"

# ---- round 6 (structural: secrets through channels other than printed output, K1-K3, X7, X15, X17) ----
NP="$HERE/net_probe.py"
# jq-free reader of the probe's JSON: npq FILE EXPR (a python expression over d)
npq() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
# C41 (K2) REAL git against a local listener that accepts and never answers, http and https: the run ends at
# the deadline (RELEASE_NET_TIMEOUT=3) with the class "timeout", and no git process of this run is left behind.
# Control needles: the probe saw a git transport helper (git-remote-http/https or "git remote-http") while
# the run was hanging. RED on the round-5 script: about 60 s (http) and 300 s (https), helpers left running.
for sch in http https; do
  mk "c41$sch"; MK41="zzhang41$sch$$"
  git -C "$D/w" remote set-url r1 "$sch://127.0.0.1:@PORT@/$MK41.git"
  # the remote URL holds the port only at run time; the probe replaces @PORT@ in the argv, so a wrapper sets it
  printf '#!/bin/sh\ngit -C "$1" remote set-url r1 "%s://127.0.0.1:$PROBE_PORT/%s.git" && cd "$1" && exec bash "$2" --tag "$3" --sha "$4" --remotes "r1 r2" --no-badge-check --dry-run\n' "$sch" "$MK41" >"$D/run41.sh"
  RELEASE_NET_TIMEOUT=3 python3 -I "$NP" drive hang "$MK41" "$D/p41.json" -- sh "$D/run41.sh" "$D/w" "$S" "$TAG" "$REL" >/dev/null 2>&1
  r41="$(npq "$D/p41.json" 'd["rc"]')"; e41="$(npq "$D/p41.json" 'int(d["elapsed"])')"
  h41="$(npq "$D/p41.json" 'sum(1 for s in d["samples"] if any("remote-http" in a or a in ("remote-https","remote-http") for a in s["argv"][:3]))')"
  chk "C41 $sch: a hung fetch through real git: exit 1" "$r41" 1
  [ "$h41" -ge 1 ] && ok "C41 $sch: a git transport helper was running during the hang (control needle)" || bad "C41 $sch: a git transport helper was running during the hang (control needle)"
  [ "$e41" -lt 10 ] && ok "C41 $sch: the run ends within the deadline + 7 s (${e41}s)" || bad "C41 $sch: the run ends within the deadline + 7 s (${e41}s)"
  npq "$D/p41.json" 'd["output"]' | grep -q '^ABORT fetch of r1 main failed (git exit 124, reason class: timeout' && ok "C41 $sch: the abort says timeout (positive needle)" || bad "C41 $sch: the abort says timeout (positive needle)"
  chk "C41 $sch: no git process of the run is left (the whole process group got the signal)" "$(npq "$D/p41.json" 'len(d["leftover"])')" 0
done
# C42 (K1) a remote URL with a user name or password is refused before any network command; the URL is not shown
mk c42; mkdir -p "$W/netbin"; printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do case "$a" in fetch|push|ls-remote) echo net >>"$NETLOG";; esac; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/netbin/git"
chmod +x "$W/netbin/git"; NETLOG="$D/net.log"
for u in 'https://u:ZZK1a@h.invalid/r.git' 'https://ZZK1b@h.invalid/r.git' 'http://u:ZZK1c@127.0.0.1:1/r.git' 'ssh://u:ZZK1d@h.invalid/r.git' 'u:ZZK1e@h.invalid:r.git' 'HTTPS://ZZK1f@h.invalid/r' 'ssh://u%3AZZK1g@h.invalid/r'; do
  git -C "$D/w" remote set-url r1 "$u"; : >"$NETLOG"
  OUT="$(cd "$D/w" && NETLOG="$NETLOG" RELEASE_ENV_KEEP="NETLOG" PATH="$W/netbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run 2>&1)"; RC=$?
  chk "C42 userinfo URL refused: exit 1 (${u%%:*})" "$RC" 1
  printf '%s\n' "$OUT" | grep -q '^ABORT remote r1 has a URL with a user name or password in it' && ok "C42 the refusal names the remote (positive needle, ${u%%:*})" || bad "C42 the refusal names the remote (positive needle, ${u%%:*}): $OUT"
  printf '%s\n' "$OUT" | grep -q 'ZZK1' && bad "C42 the URL is not shown (${u%%:*})" || ok "C42 the URL is not shown (${u%%:*})"
  [ -s "$NETLOG" ] && bad "C42 no network command ran (${u%%:*})" || ok "C42 no network command ran (${u%%:*})"
done
git -C "$D/w" remote set-url r1 "$D/r1.git"; git -C "$D/w" remote set-url --push r1 'https://u:ZZK1h@h.invalid/r.git'
run --dry-run; chk "C42 a push URL with userinfo is refused too" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'ZZK1h' && bad "C42 the push URL is not shown" || ok "C42 the push URL is not shown"
git -C "$D/w" remote set-url --delete --push r1 'https://u:ZZK1h@h.invalid/r.git'; git -C "$D/w" config "url.https://u:ZZK1i@h.invalid/.insteadOf" "zzalias:"
git -C "$D/w" remote set-url r1 zzalias:r.git; run --dry-run; chk "C42 an insteadOf rewrite that adds userinfo is refused" "$RC" 1
printf '%s\n' "$OUT" | grep -q 'ZZK1i' && bad "C42 the rewritten URL is not shown" || ok "C42 the rewritten URL is not shown"
git -C "$D/w" config --unset "url.https://u:ZZK1i@h.invalid/.insteadOf"
for u in 'ssh://git@h.invalid/r.git' 'git@h.invalid:r.git'; do
  git -C "$D/w" remote set-url r1 "$u"; RELEASE_NET_TIMEOUT=20 run --dry-run
  printf '%s\n' "$OUT" | grep -q '^ABORT fetch of r1 main failed' && ok "C42 control: a user name without a password is accepted ($u reaches the fetch)" || bad "C42 control: $u should reach the fetch: $OUT"
done
# C43 (K1, K3) REAL git with a credential helper against a listener that asks for Basic auth and then hangs: no
# descendant process holds the password in its argv, and no descendant holds a caller token in its environment.
# Control needles: the listener received the Basic header built from the helper's password (the route works),
# and a transport helper was among the samples.
mk c43; MK43="zzauth43$$"; HELPER="$D/cred_helper.sh"
printf '#!/bin/sh\n[ "$1" = get ] || exit 0\ncat "%s"\n' "$D/cred.txt" >"$HELPER"; chmod +x "$HELPER"; printf 'username=u43\npassword=ZZCREDPW43\n' >"$D/cred.txt"
git -C "$D/w" config credential.helper "$HELPER"
# round 14 (F2 of the round-13 review): the caller environment is ONE array; the wrapper's own "git remote set-url"
# runs in a subshell that unsets every one of those names first. Before round 14 that git was a child of the
# wrapper holding the caller tokens, not excluded by the filter below, and it was sampled only when it lived longer
# than one 50 ms sampling pass (host load): C43 then counted its 6 caller names (got '6', want '0') although no
# child of the tag script held any. Measured: docs/qa/con227_234_2026_11_11/round14/c43/ (a 0.6 s git shim makes
# that git visible in every run: FAIL with the old wrapper, PASS with this one).
ENV43=(M3W_GITEA_TOKEN=ZZM3W43ENV XYZ_TOKEN=ZZXYZ43ENV GH_TOKEN=ZZGH43ENV GITLAB_TOKEN=ZZGL43ENV _rpg_tok=ZZRPG43ENV GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader 'GIT_CONFIG_VALUE_0=X-Zz: ZZXH43ENV')
N43=""; for e in "${ENV43[@]}"; do N43="$N43 ${e%%=*}"; done
printf '#!/bin/sh\nsleep 1.43; (unset%s; exec git -C "$1" remote set-url r1 "http://127.0.0.1:$PROBE_PORT/%s.git") && cd "$1" && exec bash "$2" --tag "$3" --sha "$4" --remotes "r1 r2" --no-badge-check --dry-run\n' "$N43" "$MK43" >"$D/run43.sh"   # round 7: "sleep 1.43" is a child of the wrapper with the caller environment (the positive needle; the tag script re-executes itself with an empty environment)
env "${ENV43[@]}" RELEASE_NET_TIMEOUT=4 python3 -I "$NP" drive auth "$MK43" "$D/p43.json" -- sh "$D/run43.sh" "$D/w" "$S" "$TAG" "$REL" >/dev/null 2>&1
chk "C43 the listener got the Basic header of the credential helper (control needle)" "$(npq "$D/p43.json" 'd["auth_header"]')" "$(python3 -I "$NP" basic u43 ZZCREDPW43)"
[ "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if any("remote-http" in a for a in s["argv"][:3]))')" -ge 1 ] && ok "C43 a transport helper was sampled (control needle)" || bad "C43 a transport helper was sampled (control needle)"
[ "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if s["env"] is not None)')" -ge 3 ] && ok "C43 the environments of the descendants were read (control needle)" || bad "C43 the environments of the descendants were read (control needle)"
chk "C43 no descendant argv holds the password" "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if "ZZCREDPW43" in " ".join(s["argv"]))')" 0
# /proc/PID/environ is the environment a process was STARTED with: the wrapper sh, the tag script and its forked
# subshells (same argv as the script) were started by the caller with these values, so they are not children the
# script gave a token to; every other descendant (timeout, git, git-remote-http, ...) is checked
c43n="$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if not ("run43.sh" in " ".join(s["argv"]) or s["argv"] == ["sleep", "1.43"] or any(a.endswith("tag_and_release.sh") for a in s["argv"][:2])) for e in (s["env"] or []) if any(z in e for z in ("ZZM3W43","ZZXYZ43","ZZGH43","ZZGL43","ZZRPG43","ZZXH43","ZZCREDPW43")))')"
chk "C43 no child the script started holds a caller token or header value in its environment" "$c43n" 0
# round 14: on a failure, name each offending process (ppid, first 4 argv words, variable NAMES; never a value)
[ "$c43n" = 0 ] || npq "$D/p43.json" '"\n".join("C43 offender ppid=%s argv=%s names=%s" % (s["ppid"], s["argv"][:4], sorted(e.split("=", 1)[0] for e in (s["env"] or []) if any(z in e for z in ("ZZM3W43","ZZXYZ43","ZZGH43","ZZGL43","ZZRPG43","ZZXH43","ZZCREDPW43")))) for s in d["samples"] if not ("run43.sh" in " ".join(s["argv"]) or s["argv"] == ["sleep", "1.43"] or any(a.endswith("tag_and_release.sh") for a in s["argv"][:2])) and any(any(z in e for z in ("ZZM3W43","ZZXYZ43","ZZGH43","ZZGL43","ZZRPG43","ZZXH43","ZZCREDPW43")) for e in (s["env"] or [])))'
[ "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if not ("run43.sh" in " ".join(s["argv"]) or s["argv"] == ["sleep", "1.43"] or any(a.endswith("tag_and_release.sh") for a in s["argv"][:2])) and s["env"] is not None)')" -ge 2 ] && ok "C43 children of the script were checked (control needle)" || bad "C43 children of the script were checked (control needle)"
[ "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if s["argv"] == ["sleep", "1.43"] and any("ZZM3W43ENV" in e for e in (s["env"] or [])))')" -ge 1 ] && ok "C43 the instrument sees a token in an environment (positive needle: the "sleep 1.43" child of the wrapper)" || bad "C43 the instrument sees a token in an environment (positive needle)"
# round 7 (L1 L2): the tag script re-executes itself with an empty environment (argv[0] rc-clean-env)
[ "$(npq "$D/p43.json" 'sum(1 for s in d["samples"] if s["argv"][:1] == ["rc-clean-env"] and s["env"] is not None)')" -ge 1 ] && ok "C43 the re-executed tag script was sampled (control needle)" || bad "C43 the re-executed tag script was sampled (control needle)"
chk "C43 the re-executed tag script has an empty environment" "$(npq "$D/p43.json" 'sum(len(s["env"]) for s in d["samples"] if s["argv"][:1] == ["rc-clean-env"] and s["env"] is not None)')" 0
chk "C43 the hung authenticated fetch ends at the deadline: exit 1" "$(npq "$D/p43.json" 'd["rc"]')" 1
chk "C43 no git process of the run is left" "$(npq "$D/p43.json" 'len(d["leftover"])')" 0
# round 14 (F2): the same run with a "git" shim first on the caller PATH that lives 0.6 s before it runs the real
# git, so every git the caller environment starts is sampled in every run (12 passes of 50 ms), not only under load.
# With the round-13 wrapper this run failed 3 of 3 (C43b got '12'/'18', want '0'); the control needle shows the shim
# was sampled, so a pass here is not a blind instrument.
mkdir -p "$D/shim43"; printf '#!/bin/sh\nsleep 0.6\nexec %s "$@"\n' "$(command -v git)" >"$D/shim43/git"; chmod +x "$D/shim43/git"
env "${ENV43[@]}" PATH="$D/shim43:$PATH" RELEASE_NET_TIMEOUT=4 python3 -I "$NP" drive auth "$MK43" "$D/p43b.json" -- sh "$D/run43.sh" "$D/w" "$S" "$TAG" "$REL" >/dev/null 2>&1
[ "$(npq "$D/p43b.json" 'sum(1 for s in d["samples"] if any(a.endswith("/shim43/git") for a in s["argv"][:2]))')" -ge 1 ] && ok "C43b the slowed wrapper git was sampled (control needle)" || bad "C43b the slowed wrapper git was sampled (control needle)"
c43b="$(npq "$D/p43b.json" 'sum(1 for s in d["samples"] if not ("run43.sh" in " ".join(s["argv"]) or s["argv"] == ["sleep", "1.43"] or any(a.endswith("tag_and_release.sh") for a in s["argv"][:2])) for e in (s["env"] or []) if any(z in e for z in ("ZZM3W43","ZZXYZ43","ZZGH43","ZZGL43","ZZRPG43","ZZXH43","ZZCREDPW43")))')"
chk "C43b no child holds a caller token or header value, every caller-started git visible" "$c43b" 0
[ "$c43b" = 0 ] || npq "$D/p43b.json" '"\n".join("C43b offender ppid=%s argv=%s" % (s["ppid"], s["argv"][:4]) for s in d["samples"] if not ("run43.sh" in " ".join(s["argv"]) or s["argv"] == ["sleep", "1.43"] or any(a.endswith("tag_and_release.sh") for a in s["argv"][:2])) and any(any(z in e for z in ("ZZM3W43","ZZXYZ43","ZZGH43","ZZGL43","ZZRPG43","ZZXH43","ZZCREDPW43")) for e in (s["env"] or [])))'
chk "C43b no git process of the run is left" "$(npq "$D/p43b.json" 'len(d["leftover"])')" 0
git -C "$D/w" config --unset credential.helper
# C44 (K3) the environment of timeout, git, gh, glab and the gitea publisher: a caller's M3W_GITEA_TOKEN reaches
# the publisher only; GH_TOKEN, GITLAB_TOKEN, any other *_TOKEN and _rpg_tok reach nothing. Recorders on PATH write
# each child's environment and then exec the real command (or the unit-class gh/glab/publisher doubles).
mkg c44; mkdir -p "$W/envbin"
for c in git timeout; do printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nenv >>"$ENVLOG.%s"\nexec "%s" "$@"\n' "$c" "$(command -v "$c")" >"$W/envbin/$c"; done
for c in gh glab; do printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nenv >>"$ENVLOG.%s"\nexec "%s" "$@"\n' "$c" "$W/bin/$c" >"$W/envbin/$c"; done
chmod +x "$W/envbin/"*
sed -i '2i env >>"$ENVLOG.pub"' "$D/w/scripts/release_publish_gitea.sh"; ( cd "$D/w" && "${G[@]}" commit -q -am envrec ); REL="$(git -C "$D/w" rev-parse HEAD)"
OUT="$(cd "$D/w" && ENVLOG="$D/env" STUB_LOG="$D/stub.log" STUB_STATE="$D/stub.state" RELEASE_ENV_KEEP="ENVLOG STUB_LOG STUB_STATE" PATH="$W/envbin:$PATH" \
  M3W_GITEA_TOKEN=ZZM3W44ENV GH_TOKEN=ZZGH44ENV GITLAB_TOKEN=ZZGL44ENV XYZ_TOKEN=ZZXYZ44ENV _rpg_tok=ZZRPG44ENV \
  bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --release github:r1:acc/one --release gitlab:r2:grp/two --release "$GSPEC" 2>&1)"; RC=$?
chk "C44 run with every kind of release: exit 0" "$RC" 0
for c in git timeout gh glab pub; do [ -s "$D/env.$c" ] && ok "C44 the environment of $c was recorded (control needle)" || bad "C44 the environment of $c was recorded (control needle)"; done
grep -q '^M3W_GITEA_TOKEN=ZZM3W44ENV$' "$D/env.pub" && ok "C44 the publisher receives M3W_GITEA_TOKEN (the intended child)" || bad "C44 the publisher receives M3W_GITEA_TOKEN (the intended child)"
for c in git timeout gh glab; do grep -q 'ZZM3W44\|ZZGH44\|ZZGL44\|ZZXYZ44\|ZZRPG44' "$D/env.$c" && bad "C44 no caller token in the environment of $c" || ok "C44 no caller token in the environment of $c"; done
grep -q 'ZZGH44\|ZZGL44\|ZZXYZ44\|ZZRPG44' "$D/env.pub" && bad "C44 the publisher receives no other caller token" || ok "C44 the publisher receives no other caller token"
# C45 (X15) the tag script switches an inherited xtrace off at once: under bash -x, and with SHELLOPTS=xtrace
# exported, at most the one "+ set +x" trace line appears. Control: bash -x of a two-line script does trace.
printf 'true\ntrue\n' >"$D/two.sh"; [ "$(bash -x "$D/two.sh" 2>&1 | grep -c '^+')" -ge 2 ] && ok "C45 control: bash -x traces (instrument sees trace lines)" || bad "C45 control: bash -x traces"
mk c45; OUT="$(cd "$D/w" && bash -x "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run 2>&1)"; RC=$?
chk "C45 bash -x dry run: exit 0" "$RC" 0
[ "$(printf '%s\n' "$OUT" | grep -c '^+')" -le 1 ] && ok "C45 bash -x: at most one trace line" || bad "C45 bash -x: $(printf '%s\n' "$OUT" | grep -c '^+') trace lines"
OUT="$(cd "$D/w" && env SHELLOPTS=xtrace bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run 2>&1)"
[ "$(printf '%s\n' "$OUT" | grep -c '^+')" -le 1 ] && ok "C45 SHELLOPTS=xtrace: at most one trace line" || bad "C45 SHELLOPTS=xtrace: $(printf '%s\n' "$OUT" | grep -c '^+') trace lines"
# C46 (X17) only a line that STARTS with "release_publish_gitea: " is the publisher's own; the same text inside
# another line (curl, git) is not printed
mkg c46; sed -i 's/^  owncred) /  notown) echo "curl: ZZNOTOWN46 release_publish_gitea: ZZPAYLOAD46" >\&2; echo "release_publish_gitea: API failure" >\&2; exit 4 ;;\n  owncred) /' "$D/w/scripts/release_publish_gitea.sh"
( cd "$D/w" && "${G[@]}" commit -q -am notown ); REL="$(git -C "$D/w" rev-parse HEAD)"
GITEA_MODE=notown run --release "$GSPEC"
printf '%s\n' "$OUT" | grep -q "^FAIL RELEASE $GSPEC failed rc=4: release_publish_gitea: API failure" && ok "C46 the own line is printed (positive needle)" || bad "C46 the own line is printed (positive needle): $OUT"
printf '%s\n' "$OUT" | grep -q 'ZZPAYLOAD46\|ZZNOTOWN46' && bad "C46 a line that only contains the prefix is not printed" || ok "C46 a line that only contains the prefix is not printed"
# C47 (X7) every network git command carries the low-speed bound (http.lowSpeedLimit=1000, http.lowSpeedTime=60)
mk c47; printf '#!/bin/sh\n[ -r "${0%%/*}/../.stubenv" ] && . "${0%%/*}/../.stubenv"\nfor a in "$@"; do case "$a" in fetch|push|ls-remote) printf "%%s\\n" "$*" >>"$NETLOG"; break;; esac; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/netbin/git"; chmod +x "$W/netbin/git"
: >"$D/net.log"; OUT="$(cd "$D/w" && RELEASE_ENV_KEEP=NETLOG PATH="$W/netbin:$PATH" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check 2>&1)"; RC=$?
chk "C47 run: exit 0" "$RC" 0
[ "$(grep -c . "$D/net.log")" -ge 6 ] && ok "C47 network git commands were recorded (control needle)" || bad "C47 network git commands were recorded (control needle)"
chk "C47 every network git command has both low-speed settings" "$(grep -vc -- '-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 ' "$D/net.log")" 0
# C48 (round 7, L1 L2) the environment of EVERY child is built from the allow-list, whatever the caller exports:
# entries whose names are not shell identifiers (bash cannot un-export them), an inherited allexport
# (SHELLOPTS=allexport, bash -a) and caller token variables. Recorders (tests/release/env_census.py) read each
# child's /proc/$$/environ, which lists every entry, and the parent's command line. A child of the tag script, of
# its re-execution "rc-clean-env" and of timeout is checked; the publisher call (bash) may have M3W_GITEA_TOKEN.
# Control needle: a plain bash child of an env -i shell with the dirty entries is a finding for each of them.
mkg c48; R48="$W/rec48"; mkdir -p "$R48"; E48="$D/env48"
PATH="$W/bin:$PATH" python3 -I "$HERE/env_census.py" mk "$R48" "$E48" git timeout gh glab bash sed awk grep date mktemp cat tr sort head rm >/dev/null
TOB="$(command -v timeout)"; BASHB="$(command -v bash)"   # absolute: the suite's own timeout and bash are not recorded
: >"$E48"; env -i "${ENV_DIRTY[@]}" PATH="$R48:$PATH" "$BASHB" -c 'git --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null
o48="$(python3 -I "$HERE/env_census.py" check "$E48" --parent bash --allow PATH PWD SHLVL _ --marker $ENV_MARKERS)"
case "$o48" in *"'BAD-NAME'"*"'npm_config_"*) ok "C48 control: the census sees names that are not identifiers" ;; *) bad "C48 control: census blind: $o48" ;; esac
case "$o48" in *"'LC_ZZTOKEN' is not on the allow-list"*) ok "C48 control (N1): LC_ZZTOKEN is a finding (no name prefix)" ;; *) bad "C48 control (N1): LC_ZZTOKEN not seen" ;; esac
case "$o48" in *"file descriptor 7 is inherited"*) ok "C48 control (N3): an inherited descriptor is a finding" ;; *) bad "C48 control (N3): the descriptor census is blind" ;; esac
for how in shellopts dasha; do
  : >"$E48"; rm -f "$D/stub.state"
  if [ "$how" = shellopts ]; then set -- env "${ENV_DIRTY[@]}" SHELLOPTS=allexport "$TOB" 60 "$BASHB" "$S"; else set -- env "${ENV_DIRTY[@]}" "$TOB" 60 "$BASHB" -a "$S"; fi
  OUT="$(cd "$D/w" && PATH="$R48:$PATH" STUB_LOG="$D/stub.log" STUB_STATE="$D/stub.state" M3W_GITEA_TOKEN=ZZM3W48ENV XYZ_TOKEN=ZZXYZ48ENV _rpg_tok=ZZRPG48ENV \
    "$@" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --release github:r1:acc/one --release gitlab:r2:grp/two --release "$GSPEC" </dev/null 2>&1 7</dev/null)"; RC=$?
  set --
  chk "C48 $how: run with every kind of release: exit 0" "$RC" 0
  for c in git timeout gh glab bash; do grep -qx "== $c" "$E48" && ok "C48 $how: $c was recorded (control needle)" || bad "C48 $how: $c was recorded (control needle)"; done
  o48="$(python3 -I "$HERE/env_census.py" check "$E48" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 --extra bash=M3W_GITEA_TOKEN --marker ZZM3W48 ZZXYZ48 ZZRPG48 $ENV_MARKERS --min 8)"; r48=$?
  [ "$r48" -eq 0 ] && ok "C48 $how: no child has a name outside the allow-list or a marker ($(printf '%s\n' "$o48" | tail -n 1))" || bad "C48 $how: $(printf '%s\n' "$o48" | head -n 4 | tr '\n' ' ')"
  # round 11 (rc_net): the network children (git, timeout, gh, glab) have only the names of the network allow-list
  # (NET_ALLOW, the test's own copy): no RELEASE_ENV_KEEP name (STUB_LOG, STUB_STATE), no locale, USER or TERM
  o48="$(python3 -I "$HERE/env_census.py" check "$E48" --cmd git timeout gh glab --allow $NET_ALLOW --allow-fd 3 --marker ZZM3W48 ZZXYZ48 ZZRPG48 $ENV_MARKERS --min 4)"; r48=$?
  [ "$r48" -eq 0 ] && ok "C48 $how: every network child has only the network allow-list ($(printf '%s\n' "$o48" | tail -n 1))" || bad "C48 $how net: $(printf '%s\n' "$o48" | head -n 4 | tr '\n' ' ')"
done
# C52 (round 11): the badge computer runs git, so the tag script starts it through rc_net too. A badge-computer
# double committed at the release commit records its start environment (/proc/$$/environ: every entry, nothing the
# double's own shell adds) into a file named in the double itself (it gets no RELEASE_ENV_KEEP name). Control
# needle: the double ran (the record exists) and it has LC_ALL=C (the rc_net constant).
mk c52; mkdir -p "$D/w/scripts/badges"
printf '#!/usr/bin/env bash
tr "\\0" "\\n" </proc/$$/environ >"%s"
exit 0
' "$D/badge.env" >"$D/w/scripts/badges/compute_badges.sh"
( cd "$D/w" && "${G[@]}" add scripts/badges && "${G[@]}" commit -q -m badges ); REL="$(git -C "$D/w" rev-parse HEAD)"
OUT="$(cd "$D/w" && LANG=C.UTF-8 USER=zzc52 TERM=xterm KEEPME=ZZFAKE-keep52 RELEASE_ENV_KEEP="STUB_LOG STUB_STATE KEEPME" bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --dry-run 2>&1)"; RC=$?
chk "C52 dry run with the badge check: exit 0" "$RC" 0
[ -s "$D/badge.env" ] && ok "C52 the badge computer ran (control needle)" || bad "C52 the badge computer ran (control needle): $(printf '%s\n' "$OUT" | tail -n 2 | tr '\n' ' ')"
grep -qx 'LC_ALL=C' "$D/badge.env" && ok "C52 the badge computer has LC_ALL=C (rc_net)" || bad "C52 the badge computer has no LC_ALL=C"
x52=""; for n in $(cut -d= -f1 "$D/badge.env" 2>/dev/null); do case " $NET_ALLOW " in *" $n "*) ;; *) x52="$x52 $n" ;; esac; done
chk "C52 every name of the badge computer is on NET_ALLOW" "${x52:-none}" none
grep -q 'ZZFAKE-keep52\|zzc52' "$D/badge.env" && bad "C52 a caller value reaches the badge computer" || ok "C52 no caller value reaches the badge computer"
# C50 (round 9, F1 F2 of the round-8 review): inherited descriptors of 3, 5 and 6 digits (300, 12345, 100000) reach
# no child of the tag script (round 8 closed only numbers of at most four digits). Control needle: the census lists
# all of them for a plain bash child.
if nofile_room; then
  : >"$E48"; env -i PATH="$R48:$PATH" "$BASHB" -c 'git --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null
  o48="$(python3 -I "$HERE/env_census.py" check "$E48" --parent bash --allow PATH PWD SHLVL _)"
  for d in 7 300 12345 100000; do case "$o48" in *"file descriptor $d is inherited"*) ok "C50 control: descriptor $d is a finding for a plain child" ;; *) bad "C50 control: descriptor $d not seen by the census" ;; esac; done
  mkg c50; : >"$E48"; rm -f "$D/stub.state"
  OUT="$(cd "$D/w" && PATH="$R48:$PATH" STUB_LOG="$D/stub.log" STUB_STATE="$D/stub.state" M3W_GITEA_TOKEN=ZZM3W50ENV "$TOB" 60 "$BASHB" "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check \
    --release github:r1:acc/one --release gitlab:r2:grp/two --release "$GSPEC" </dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null)"; RC=$?
  chk "C50 run with descriptors 7 300 12345 100000: exit 0" "$RC" 0
  for c in git gh glab; do grep -qx "== $c" "$E48" && ok "C50 $c was recorded (control needle)" || bad "C50 $c was recorded (control needle)"; done
  o48="$(python3 -I "$HERE/env_census.py" check "$E48" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 --extra bash=M3W_GITEA_TOKEN --min 8)"; r48=$?
  [ "$r48" -eq 0 ] && ok "C50 no child of the tag script inherits a descriptor of 1, 3, 5 or 6 digits ($(printf '%s\n' "$o48" | tail -n 1))" || bad "C50 F1: $(printf '%s\n' "$o48" | grep FINDING | sort -u | head -n 4 | tr '\n' ' ')"
else skp "C50 descriptors of 5 and 6 digits: $NOFILE_WHY"; fi


# C49 (round 7, L3) a network git that IGNORES SIGTERM (a unit-class double: the sh loop and its sleep inherit
# the ignored disposition) still ends: timeout(1) sends TERM at RELEASE_NET_TIMEOUT=2 and KILL 10 s later (-k 10),
# the abort carries git exit 137 with the reason class "timeout", and no process of the double is left. RED with
# "-k 10" removed (the run hangs until the test's outer bound of 45 s) and with 137 not classed as timeout.
# The output goes to a FILE, not to $(...): a surviving double would hold the write end of a command
# substitution's pipe and block the suite until it ends (§11.4.201(12), the fifth footgun); with a file the
# suite goes on, measures the time and kills the leftovers below.
mk c49; H49="$D/hang49"; mkdir -p "$H49"
printf '#!/bin/sh
for a in "$@"; do case "$a" in fetch|ls-remote|push) trap "" TERM; while :; do sleep 1; done ;; esac; done
exec "%s" "$@"
' "$REALGIT" >"$H49/git"; chmod +x "$H49/git"
t49=$SECONDS
(cd "$D/w" && RELEASE_NET_TIMEOUT=2 PATH="$H49:$PATH" timeout -k 5 45 bash "$S" --tag "$TAG" --sha "$REL" --remotes "r1 r2" --no-badge-check --dry-run) >"$D/o49" 2>&1 </dev/null; RC=$?
OUT="$(cat "$D/o49")"
e49=$((SECONDS - t49))
l49=""; for q in /proc/[0-9]*; do q="${q#/proc/}"; [ "$q" -gt 1 ] 2>/dev/null || continue; tr '\0' ' ' <"/proc/$q/cmdline" 2>/dev/null | grep -qF -- "$H49/git" && l49="$l49 $q"; done
chk "C49 a TERM-ignoring network git: exit 1" "$RC" 1
[ "$e49" -lt 30 ] && ok "C49 the run ends within the deadline + the kill delay + 16 s (${e49}s)" || bad "C49 the run ends within the deadline + the kill delay + 16 s (${e49}s)"
[ "$e49" -ge 10 ] && ok "C49 the double outlived the TERM (control: ${e49}s >= 10 s)" || bad "C49 the double outlived the TERM (control: ${e49}s)"
printf '%s\n' "$OUT" | grep -q '^ABORT .*(git exit 137, reason class: timeout' && ok "C49 the abort says git exit 137, reason class timeout" || bad "C49 the abort says git exit 137, reason class timeout: $(printf '%s\n' "$OUT" | grep '^ABORT' | head -c 200)"
chk "C49 no process of the double is left" "${l49:-none}" none
for q in $l49; do [ "$q" -gt 1 ] && kill -KILL "$q" 2>/dev/null; done   # own leftovers only (pids whose argv holds this case's double)

# C12 the script never forces (static check of the source)
if grep -vE '^[[:space:]]*#' "$S" | grep -nE -- '--force|\+refs/|git push[^#]*[[:space:]]\+[A-Za-z0-9]|tag -d|push --delete|push[^#]* :refs' >/dev/null; then bad "C12 no force/delete in script"; else ok "C12 no force/delete in script"; fi

# L1 (round 6, K5 class; round 7: rc_env_clean): no external command runs before rc_env_clean in the script under test. The census lint
# runs on this copy; only its order findings count here (the table rows are checked by test_channel_census.sh).
l1t="$(mktemp -d "${TMPDIR:-/tmp}/l1.XXXXXX")"; : "${l1t:?}"
l1o="$(python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$S" 2>&1)"
case "$l1o" in *BLIND*|*"CENSUS invocations=0 "*|"") bad "L1 the lint is blind on $(basename "$S")" ;; *) ok "L1 the lint sees $(basename "$S") (control)" ;; esac
l1b="$(printf '%s\n' "$l1o" | grep -E 'before rc_env_clean|never calls rc_env_clean')"
[ -z "$l1b" ] && ok "L1 no external command before rc_env_clean" || bad "L1 external command before rc_env_clean: ${l1b:0:160}"
sed '2i date >/dev/null' "$S" >"$l1t/needle.sh"
python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$l1t/needle.sh" 2>&1 | grep -q 'before rc_env_clean: needle.sh:2 date' \
  && ok "L1 needle: a date inserted at line 2 is found" || bad "L1 needle: a date inserted at line 2 is not found"
rm -rf -- "${l1t:?}"
# C53 (round 12, F1 of the round-11 review): the network-spawn gate (tests/release/channel_census.py netgate) over
# this copy of the script and the helper library it loads: every network child goes through rc_net and every command
# is classified by its syntax alone (an unclassified command word is a finding; round 13: not a proof of default
# deny over bash, see test_channel_census.sh part 2c), with an empty PATH (no lookup on the host). A git started any
# other way (command -p git, "git", a redirection before git, /usr/bin/git, an absent program) is a finding here,
# also where the runtime recorders cannot see it (command -p and a path bypass the recorders on PATH). The number of
# network calls through rc_net is a positive needle, and a copy with "command -p git status" appended is a control
# needle that must be a finding.
# Round 13: the gate runs in analyser mode (--pin TABLE --analyser-only; the name list and the awk and sed
# programs of the pin still apply): this suite tests mutated copies, and the byte pin of the real scripts is
# checked by test_channel_census.sh part 2d. The library is copied next to the copy, so the appended line is
# the only finding.
c53py="$(command -v python3)"; c53d="$(mktemp -d "${TMPDIR:-/tmp}/c53.XXXXXX")"; : "${c53d:?}"
o53="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$S" "$(dirname "$S")/redact_cut.sh" 2>&1)"; r53=$?
n53="$(printf '%s\n' "$o53" | sed -n 's/^NETGATE .*network_through_rc_net=\([0-9]*\).*/\1/p')"
[ "$r53" -eq 0 ] && ok "C53 netgate: $(basename "$S") and its library start every network child through rc_net, every command classified ($(printf '%s\n' "$o53" | tail -n 1))" \
  || bad "C53 netgate rc=$r53: $(printf '%s\n' "$o53" | grep -E '^FINDING|BLIND' | head -n 3 | tr '\n' ' ')"
[ "${n53:-0}" -ge 30 ] && ok "C53 netgate: ${n53} network calls are seen through rc_net (positive needle)" || bad "C53 netgate: network count ${n53:-none} (blind?)"
mkdir -p -- "$(dirname "$c53d/redact_cut.sh")"; cp -- "$(dirname "$S")/redact_cut.sh" "$c53d/redact_cut.sh"; cp -- "$S" "$c53d/$(basename "$S")"; printf '%s\n' 'command -p git status' >>"$c53d/$(basename "$S")"
o53c="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$c53d/$(basename "$S")" "$c53d/redact_cut.sh" 2>&1)"; r53c=$?
[ "$r53c" -eq 1 ] && printf '%s\n' "$o53c" | grep -q "^FINDING builtin command other than command -v NAME: $(basename "$S"):[0-9]* | key=483e5249\$" \
  && printf '%s\n' "$o53c" | grep -q '^NETGATE .* findings=1$' && ok "C53 netgate control needle: a command -p git appended to a copy is the only finding" \
  || bad "C53 netgate control needle: an appended command -p git is not a finding (rc $r53c)"
rm -rf -- "${c53d:?}"
[ "$skipped" -eq 0 ] || echo "SKIPPED: $skipped case(s) did not run (see the SKIP lines); the result does not cover them"
echo "RESULT: pass=$pass fail=$fail"
suite_exit "$fail" "$skipped"   # round 8 (N6): 77 when a case was SKIPPED
