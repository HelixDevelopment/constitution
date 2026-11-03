#!/usr/bin/env bash
# test_self_guard.sh — the installer and the updater REFUSE to install into the constitution repository itself.
#
# The repository under test is never touched: it is cloned with `git clone --shared` into a mktemp -d sandbox
# (GIT_CEILING_DIRECTORIES stops discovery above the sandbox) and every run works on that clone.
# Cases (each: exit 3 and a byte-identical fingerprint of the whole clone, .git included):
#   real run / --dry-run / --restore, cwd = clone root, cwd = clone/scripts, --project-root from outside;
#   --detect-layout prints constitution-repo (read-only, exit 0);
#   detection layers: (1) marker files (Constitution.md + templates/Constitution.project.md.template +
#   templates/CLAUDE.project.md.template; present in every commit that has Constitution.md), (1b) a SHALLOW clone with
#   Constitution.md (both overridable with --not-constitution-repo),
#   (2) the constitution's first commit in HEAD history (additive), (3) a remote URL of a known upstream (additive);
#   the updater refuses when the project root is the constitution itself.
# Golden-FALSE: a consumer project that only has its own Constitution.md is NOT refused.
# Usage: bash tests/install/test_self_guard.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=self-guard
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox

C="$SB/self"
git clone -q --shared --no-recurse-submodules "$REPO" "$C" || { echo "shared clone failed" >&2; exit 2; }
# the working-tree installer/updater (possibly not committed yet) are what is under test; put them in the clone
# exactly as they will be after a commit, so layer (1) is exercised; layer (2)/(3) are tested separately below
cp "$INSTALLER" "$C/scripts/install_constitution.sh"; cp "$UPDATER" "$C/scripts/update_constitution.sh"
git -C "$C" add -f scripts/install_constitution.sh scripts/update_constitution.sh
git -C "$C" commit -q --allow-empty -m "test: installer under test" || { echo "commit failed" >&2; exit 2; }
fp() { { tree_fingerprint "$1"; [ -e "$1/.constitution-install-backup" ] && echo BACKUP-DIR-CREATED; } | sha256sum | cut -c1-64; }
f0="$(fp "$C")"
selfrun() { # description cwd args...
  local d="$1" cwd="$2"; shift 2
  OUT="$(cd "$cwd" && bash "$INSTALLER" "$@" 2>&1)"; RC=$?
  eq "$d: exit 3" 3 "$RC"
  case "$OUT" in *"constitution repository itself"*) ok "$d: says why" ;; *) nok "$d: says why"; printf '%s\n' "$OUT" | tail -5 ;; esac
  eq "$d: clone unchanged (.gitmodules, agent docs, .git/config, exclude, index, .git/modules)" "$f0" "$(fp "$C")"
}
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
# a REACHABLE upstream: without the guard the run would really install (that is the RED baseline)
NI=(--non-interactive --agent none --run-setup off --upstream-url "$SB/up/upstream.git")
echo "# layer 1: file presence"
selfrun "real run from root" "$C" "${NI[@]}"
selfrun "dry run from root" "$C" "${NI[@]}" --dry-run
selfrun "real run from scripts/" "$C/scripts" "${NI[@]}"
selfrun "dry run from scripts/" "$C/scripts" "${NI[@]}" --dry-run
selfrun "--project-root clone (real)" "$SB" "${NI[@]}" --project-root "$C"
selfrun "--project-root clone/scripts (dry)" "$SB" "${NI[@]}" --dry-run --project-root "$C/scripts"
selfrun "--restore" "$C" --restore "$C/.constitution-install-backup/x"
selfrun "interactive mode refuses before asking (no tty needed)" "$C" --agent none
OUT="$(cd "$C/scripts" && bash "$INSTALLER" --detect-layout 2>&1)"; RC=$?
eq "--detect-layout exit 0" 0 "$RC"; eq "--detect-layout reports constitution-repo" constitution-repo "$OUT"
eq "--detect-layout changed nothing" "$f0" "$(fp "$C")"
check "no submodules/constitution entry in the clone's .gitmodules" eval '! git -C "$C" config -f "$C/.gitmodules" --get submodule.submodules/constitution.path'
check "no submodules/constitution gitdir was created" test ! -e "$C/.git/modules/submodules/constitution"

echo "# layer 2: the constitution's first commit in HEAD history (a layer-1 marker file removed)"
C2="$SB/self2"; git clone -q --shared --no-recurse-submodules "$REPO" "$C2" || exit 2
git -C "$C2" rm -q templates/Constitution.project.md.template && git -C "$C2" commit -q -m "test: remove a layer-1 marker"
git -C "$C2" remote remove origin
f2="$(fp "$C2")"
OUT="$(cd "$C2" && bash "$INSTALLER" "${NI[@]}" 2>&1)"; RC=$?
eq "first-commit layer: exit 3" 3 "$RC"; eq "first-commit layer: unchanged" "$f2" "$(fp "$C2")"
case "$OUT" in *"first commit"*) ok "first-commit layer named" ;; *) nok "first-commit layer named"; printf '%s\n' "$OUT" | tail -3 ;; esac

echo "# layer 3: a remote URL of a known constitution upstream (unrelated history)"
P3="$SB/p3"; new_project "$P3"; git -C "$P3" remote add origin https://github.com/HelixDevelopment/HelixConstitution.git
f3="$(fp "$P3")"
OUT="$(cd "$P3" && bash "$INSTALLER" "${NI[@]}" 2>&1)"; RC=$?
eq "upstream-URL layer: exit 3" 3 "$RC"; eq "upstream-URL layer: unchanged" "$f3" "$(fp "$P3")"
P4="$SB/p4"; new_project "$P4"; git -C "$P4" remote add mirror git@gitlab.com:vasic-digital/HelixConstitution
OUT="$(cd "$P4" && bash "$INSTALLER" "${NI[@]}" --dry-run 2>&1)"; RC=$?
eq "upstream-URL layer (ssh, no .git suffix, second remote): exit 3" 3 "$RC"

echo "# golden-FALSE: a consumer project with its own Constitution.md is not refused"
P5="$SB/p5"; new_project "$P5"; printf '# Project constitution\n' >"$P5/Constitution.md"
git -C "$P5" add Constitution.md && git -C "$P5" commit -qm c
OUT="$(cd "$P5" && bash "$INSTALLER" --non-interactive --agent none --run-setup off --upstream-url "$SB/up/upstream.git" 2>&1)"; RC=$?
eq "consumer with Constitution.md installs (exit 0)" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -8

echo "# round-4 IMPORTANT-1: layer 1 is a marker set present in EVERY constitution commit that has Constitution.md"
# (Constitution.md + templates/Constitution.project.md.template + templates/CLAUDE.project.md.template; measured over
# all 977 commits of the repository on 2026-10-29: present in 974, absent only in the 3 commits before Constitution.md)
refuse_dir() { # description dir [extra args...] → exit 3, unchanged (whole tree incl. .git)
  local d="$1" dir="$2"; shift 2; local f; f="$(fp "$dir")"
  OUT="$(cd "$dir" && bash "$INSTALLER" "${NI[@]}" "$@" 2>&1)"; RC=$?
  eq "$d: exit 3" 3 "$RC"
  case "$OUT" in *"constitution repository itself"*) ok "$d: says why" ;; *) nok "$d: says why"; printf '%s\n' "$OUT" | tail -4 ;; esac
  eq "$d: unchanged" "$f" "$(fp "$dir")"
}
for tag in helixconstitution-v69 helixconstitution-v71 helixconstitution-v72.1; do
  # shallow single-tag clone (no first commit in history) with an OFF-TABLE remote: the reviewer's reproduction
  S1="$SB/shallow-$tag"; git clone -q --depth 1 --branch "$tag" "file://$REPO" "$S1" 2>/dev/null || { nok "shallow clone of $tag"; continue; }
  git -C "$S1" remote set-url origin https://example.invalid/someone/fork.git
  eq "$tag shallow clone really is shallow (precondition)" true "$(git -C "$S1" rev-parse --is-shallow-repository)"
  refuse_dir "shallow $tag, off-table https remote" "$S1"
  refuse_dir "shallow $tag, off-table remote, --dry-run" "$S1" --dry-run
  OUT="$(cd "$S1" && bash "$INSTALLER" --detect-layout 2>&1)"; eq "shallow $tag: --detect-layout says constitution-repo" constitution-repo "$OUT"
  git -C "$S1" remote set-url origin "$SB/some/local/path.git"
  refuse_dir "shallow $tag, local-path remote" "$S1"
  # non-shallow checkout of the same tag (layer 1 must not depend on files added after the tag)
  T1="$SB/tag-$tag"; git clone -q --shared --no-recurse-submodules "$REPO" "$T1" && git -C "$T1" checkout -q --detach "$tag" \
    && git -C "$T1" remote remove origin
  check "$tag: no scripts/install_constitution.sh in the tag (precondition: old tags lack it)" test ! -e "$T1/scripts/install_constitution.sh"
  refuse_dir "full clone at $tag, no remote" "$T1"
done
echo "# shallow + Constitution.md is refused even without the template markers (heuristic layer, overridable)"
SC="$SB/shallow-consumer-src"; new_project "$SC"; printf '# Project constitution\n' >"$SC/Constitution.md"
git -C "$SC" add Constitution.md && git -C "$SC" commit -qm two
SC2="$SB/shallow-consumer"; git clone -q --depth 1 "file://$SC" "$SC2"; git -C "$SC2" remote set-url origin https://example.invalid/me/app.git
refuse_dir "shallow consumer with its own Constitution.md" "$SC2"
case "$OUT" in *"--not-constitution-repo"*) ok "the refusal names the override flag" ;; *) nok "the refusal names the override flag" ;; esac
OUT="$(cd "$SC2" && bash "$INSTALLER" "${NI[@]}" --not-constitution-repo 2>&1)"; RC=$?
eq "golden-FALSE: shallow consumer with --not-constitution-repo installs (exit 0)" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6
echo "# --not-constitution-repo never overrides the strong layers (first commit, known upstream URL)"
C3="$SB/self3"; git clone -q --shared --no-recurse-submodules "$REPO" "$C3"; git -C "$C3" remote remove origin
refuse_dir "full clone + --not-constitution-repo (first-commit layer still refuses)" "$C3" --not-constitution-repo
P6="$SB/p6"; new_project "$P6"; git -C "$P6" remote add origin https://github.com/HelixDevelopment/HelixConstitution.git
refuse_dir "known upstream remote + --not-constitution-repo" "$P6" --not-constitution-repo
echo "# layer 3 URL normalisation: ports, userinfo with '@', case, trailing slash, scp form"
for u in https://github.com:443/HelixDevelopment/HelixConstitution.git ssh://git@github.com:22/HelixDevelopment/HelixConstitution.git \
         'https://u:p@ss@GitHub.COM/HelixDevelopment/HelixConstitution/' git@gitlab.com:helixdevelopment1/helixconstitution \
         'ssh://git@gitflic.ru:2222/helixdevelopment/helixconstitution.git/' https://gitverse.ru//helixdevelopment/HelixConstitution.git; do
  PU="$SB/pu.$RANDOM$RANDOM"; new_project "$PU"; git -C "$PU" remote add origin "$u"
  refuse_dir "remote $(printf '%s' "$u" | sed 's#//[^/]*@#//***@#')" "$PU" --dry-run
done
eq "hi_norm_url drops the port and userinfo up to the last @" "github.com/helixdevelopment/helixconstitution" \
   "$(HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"; hi_norm_url 'HTTPS://a:b@c@GitHub.com:443/HelixDevelopment/HelixConstitution.git/')"
eq "hi_norm_url: scp form" "gitlab.com/x/y" "$(HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"; hi_norm_url 'git@gitlab.com:x/y.git')"
echo "# golden-FALSE (M1): a consumer with its own Constitution.md AND a vendored installer is not refused"
P7="$SB/p7"; new_project "$P7"; printf '# Our constitution\n' >"$P7/Constitution.md"; mkdir -p "$P7/scripts"
cp "$INSTALLER" "$P7/scripts/install_constitution.sh"; git -C "$P7" add -A && git -C "$P7" commit -qm vendored
git -C "$P7" remote add origin https://example.invalid/me/app.git
OUT="$(cd "$P7" && bash "$INSTALLER" "${NI[@]}" 2>&1)"; RC=$?
eq "consumer with Constitution.md + vendored installer installs (exit 0)" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6

echo "# updater: project root == the constitution"
OUT="$(cd "$SB" && bash "$C/scripts/update_constitution.sh" --project-root "$C" --dry-run 2>&1)"; RC=$?
eq "updater --project-root = constitution: exit 3" 3 "$RC"
case "$OUT" in *"constitution repository itself"*) ok "updater says why" ;; *) nok "updater says why"; printf '%s\n' "$OUT" | tail -3 ;; esac
OUT="$(cd "$SB" && bash "$C/scripts/update_constitution.sh" --project-root "$C/scripts" 2>&1)"; RC=$?
eq "updater --project-root = constitution/scripts: exit 3" 3 "$RC"
eq "updater changed nothing" "$f0" "$(fp "$C")"
finish
