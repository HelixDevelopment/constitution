#!/usr/bin/env bash
# cm_gitlink_on_remote_mutation_test.sh — §1.1 paired-mutation meta-test for CM-GITLINK-ON-REMOTE.
#
# ── Purpose ───────────────────────────────────────────────
# Builds a disposable fixture (a bare "remote", a parent repo with one real submodule cloned from it through file://)
# and asserts the sibling gate's verdict for each case:
#   (0) control: the gitlink is a commit the remote has                                   => 0 (PASS)
#   (1) MUTATION: the nested checkout moves ahead by a LOCAL commit and the parent records it => 1 (UNPUBLISHED)
#   (2) the nested repository and its gitdir are gone                                     => 2 (BLIND)
#   (3) a SHALLOW nested clone holding an unpublished local commit (absence unprovable)    => 2 (BLIND)
#   (4) an index with no gitlink (the instrument sees nothing)                            => 2 (BLIND)
#   (5) --online: the recorded commit is a tip on the remote that the nested repo never fetched => 0 (PASS), and the
#       same state WITHOUT --online is not a PASS (the upgrade is real)
#   (6) no remote refs fetched at all (cannot prove)                                       => 2 (BLIND)
#   (7) self-check: a copy of the gate with the `--contains` test disabled (always "published") is detected, i.e. it
#       passes case (1) where the real gate fails
# ── Side-effects ──────────────────────────────────────────
#   Temp fixtures under $TMPDIR, removed on EXIT. No network (file:// only).
# ── Exit codes ────────────────────────────────────────────
#   0 every expectation held · 1 an expectation was violated · 2 gate missing.
# Cross-refs: §1.1, §11.4.28, §11.4.113. Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/cm_gitlink_on_remote.sh"
[ -f "$GATE" ] || { echo "META: gate missing" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_glr_mut.XXXXXX")"; trap 'rm -rf "${TMP:?}"' EXIT
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c protocol.file.allow=always)
pass=0; fail=0
expect() { # name want-rc got-rc
  if [ "$3" = "$2" ]; then pass=$((pass+1)); echo "ok   - $1 (rc=$3)"; else fail=$((fail+1)); echo "FAIL - $1: want rc=$2 got rc=$3"; fi; }
REMOTE="$TMP/remote.git"; "${G[@]}" init -q --bare "$REMOTE"
SEED="$TMP/seed"; "${G[@]}" init -q "$SEED"; "${G[@]}" -C "$SEED" commit -q --allow-empty -m c1
"${G[@]}" -C "$SEED" push -q "file://$REMOTE" HEAD:refs/heads/main
build() { # <dir> [--shallow] -> a parent repo whose submodule 'a' is cloned from the remote and recorded at its tip
  local d="$1"; "${G[@]}" init -q "$d"
  if [ "${2:-}" = "--shallow" ]; then
    "${G[@]}" clone -q --depth 1 "file://$REMOTE" "$d/submodules/a"
    printf '[submodule "submodules/a"]\n\tpath = submodules/a\n\turl = file://%s\n' "$REMOTE" >"$d/.gitmodules"
  else
    "${G[@]}" -C "$d" submodule add -q "file://$REMOTE" submodules/a >/dev/null 2>&1
  fi
  "${G[@]}" -C "$d" add -A >/dev/null 2>&1
}
run() { bash "$GATE" --root "$1" "${@:2}" >"$TMP/out.txt" 2>&1; echo $?; }
advance() { # <parent> -> a LOCAL commit in the nested checkout, recorded in the parent index
  "${G[@]}" -C "$1/submodules/a" commit -q --allow-empty -m local-only
  "${G[@]}" -C "$1" add submodules/a >/dev/null 2>&1; }
P="$TMP/p0"; build "$P"
expect "0 control: pin is a published commit" 0 "$(run "$P")"
P="$TMP/p1"; build "$P"; advance "$P"
expect "1 MUTATION: local-only nested commit recorded => UNPUBLISHED" 1 "$(run "$P")"
grep -q 'UNPUBLISHED' "$TMP/out.txt" && { pass=$((pass+1)); echo "ok   - 1b the verdict line names UNPUBLISHED"; } || { fail=$((fail+1)); echo "FAIL - 1b no UNPUBLISHED line"; }
P="$TMP/p2"; build "$P"; "${G[@]}" -C "$P" submodule deinit -q -f submodules/a >/dev/null 2>&1; rm -rf "$P/submodules/a" "$P/.git/modules"
expect "2 no nested repository or gitdir => BLIND" 2 "$(run "$P")"
P="$TMP/p3"; build "$P" --shallow; advance "$P"
expect "3 shallow nested clone with an unpublished commit => BLIND (never a false FAIL or PASS)" 2 "$(run "$P")"
P="$TMP/p4"; "${G[@]}" init -q "$P"; printf '[submodule "x"]\n\tpath = x\n\turl = u\n' >"$P/.gitmodules"
expect "4 no gitlink in the index => BLIND" 2 "$(run "$P")"
P="$TMP/p5"; build "$P"
"${G[@]}" -C "$SEED" commit -q --allow-empty -m c2; "${G[@]}" -C "$SEED" push -q "file://$REMOTE" HEAD:refs/heads/main
NEW="$("${G[@]}" -C "$SEED" rev-parse HEAD)"
# the nested repo fetches the new commit object (so it exists locally) but its remote-tracking refs stay old
"${G[@]}" -C "$P/submodules/a" fetch -q origin "$NEW" 2>/dev/null; "${G[@]}" -C "$P/submodules/a" update-ref -d refs/remotes/origin/main 2>/dev/null
"${G[@]}" -C "$P/submodules/a" checkout -q --detach "$NEW" 2>/dev/null; "${G[@]}" -C "$P" add submodules/a >/dev/null 2>&1
off="$(run "$P")"; [ "$off" != 0 ] && { pass=$((pass+1)); echo "ok   - 5a without --online the unfetched tip is not a PASS (rc=$off)"; } || { fail=$((fail+1)); echo "FAIL - 5a offline PASSED an unproven pin"; }
expect "5b --online upgrades a remote tip to PUBLISHED" 0 "$(run "$P" --online)"
P="$TMP/p6"; build "$P"; for r in $("${G[@]}" -C "$P/submodules/a" for-each-ref --format='%(refname)' refs/remotes); do "${G[@]}" -C "$P/submodules/a" update-ref -d "$r"; done
advance "$P"
expect "6 no remote refs fetched => BLIND" 2 "$(run "$P")"
# 7 self-check: neuter the containment test and prove the neutered gate would let case 1 through
NEUT="$TMP/neutered.sh"; sed 's#^  cont="\$(git .*# MUT_REPLACED=1; cont="x"#' "$GATE" >"$NEUT"
grep -q 'cont="x"' "$NEUT" || { fail=$((fail+1)); echo "FAIL - 7 could not neuter the gate (marker line moved)"; }
P="$TMP/p7"; build "$P"; advance "$P"
rc="$(bash "$NEUT" --root "$P" >/dev/null 2>&1; echo $?)"
expect "7 the neutered gate passes the unpublished pin (so case 1 truly discriminates)" 0 "$rc"
echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" -eq 0 ] && { echo "✅ META PASS: CM-GITLINK-ON-REMOTE is a genuine (non-bluff) gate"; exit 0; }
echo "❌ META FAIL"; exit 1
