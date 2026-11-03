#!/usr/bin/env bash
# test_round11.sh — round-11 class fixes (W2 installer stream), REAL git, real bare upstreams, real clones:
#   F1  the BUILT-IN updater (checkout without update_constitution.sh, v71 -> v72.1) honours the update-pending marker
#       only when it names the checkout AND records the staged gitlink seen before the checkout; a marker naming
#       ANOTHER commit, a stale marker (right target, wrong staged-before), an old-format marker (target only) and a
#       symlinked marker never license overwriting a hand-staged gitlink (exit 3, nothing changed).
#   F2  the same for the updater (update_constitution.sh), including the symlink class on BOTH sides: a symlinked
#       marker is neither read nor written through (updater and installer), and a marker is "<target> <staged-before>".
#   F3  hi_mark_hash prefers sha256sum, falls back to cksum, and with neither fails closed.
# Constructed markers below are LABELLED "CONSTRUCTED": real interrupted double updates are in test_round10.sh.
# Usage: bash tests/install/test_round11.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=round11
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
upd() { local p="$1"; shift; OUT="$(cd "$p" && bash submodules/constitution/scripts/update_constitution.sh "$@" 2>&1)"; RC=$?; }
mkinstalled() { new_project "$1"; run_installer "$1" "${BASE[@]}" --ref helixconstitution-v999.0; git -C "$1" commit -qm add; }
stage_gitlink() { git -C "$1" update-index --cacheinfo "160000,$2,submodules/constitution"; }
pending() { printf '%s/helix-update-pending' "$(git -C "${1:?}" rev-parse --absolute-git-dir)"; }
SUBMOD=submodules/constitution
# W2 round 12 — SEAM: a git wrapper first on PATH records, at the moment of every `checkout --detach`, whether the
# update-pending marker already exists (real git is exec'd unchanged). A marker written AFTER the checkout (mutant B5)
# is invisible to the end-state assertions but shows up here as "absent"; the marker's first line is recorded too and
# compared with the expected '<target sha> <staged-before>' (mutant S3: wrong marker before the checkout).
SEAMLOG="$SB/seam.log"; mkdir -p "$SB/wrap"; REALGIT="$(command -v git)"
cat >"$SB/wrap/git" <<EOF
#!/usr/bin/env bash
# recording wrapper (test seam, execs the real git unchanged)
case " \$* " in *" checkout "*--detach*)
  if [ -e "\$SEAM_MARKER" ]; then echo "present \$(head -n 1 -- "\$SEAM_MARKER")" >>"\$SEAM_LOG"; else echo absent >>"\$SEAM_LOG"; fi ;; esac
exec "$REALGIT" "\$@"
EOF
chmod +x "$SB/wrap/git"
SEC="${R11_SECTIONS:-F1 F2 F3}"; sec() { case " $SEC " in *" $1 "*) return 0 ;; esac; return 1; }

if sec F1; then
echo "# F1 built-in updater: committed v71 < staged v72 < checkout v72.1 (hand-staged), marker variants"
C71="$(tagsha "$SB/up" helixconstitution-v71)"; C72="$(tagsha "$SB/up" helixconstitution-v72)"; C721="$(tagsha "$SB/up" helixconstitution-v72.1)"
bsetup() { # project → v71 committed, v72 staged by hand, checkout at v72.1
  new_project "$1"
  run_installer "$1" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71
  git -C "$1" commit -qm add; git -C "$1/$SUBMOD" checkout -q --detach "$C721"; stage_gitlink "$1" "$C72"
}
brun() { run_installer "$1" "${BASE[@]}" --ref helixconstitution-v72.1; }
bsetup "$SB/b1"; P="$SB/b1"
check "control: the checkout has no updater script (built-in path)" eval '[ ! -f "$P/$SUBMOD/scripts/update_constitution.sh" ]'
printf '%s %s\n' "$C71" "$C72" >"$(pending "$P")"   # CONSTRUCTED: names ANOTHER commit than the checkout
brun "$P"; eq "built-in, marker naming another commit: exit 3" 3 "$RC"
check "built-in path really used (control needle)" grep -q 'built-in updater' <<<"$OUT"
eq "built-in, foreign marker: staged gitlink kept" "$C72" "$(gitlink "$P")"
eq "built-in, foreign marker: checkout not moved" "$C721" "$(git -C "$P/$SUBMOD" rev-parse HEAD)"
printf '%s %s\n' "$C721" "$C71" >"$(pending "$P")"   # CONSTRUCTED: right target, STALE staged-before (not what is staged now)
brun "$P"; eq "built-in, stale marker (staged-before differs): exit 3" 3 "$RC"; eq "built-in, stale marker: staged kept" "$C72" "$(gitlink "$P")"
printf '%s\n' "$C721" >"$(pending "$P")"   # CONSTRUCTED: old format, target only
brun "$P"; eq "built-in, old-format marker (target only): exit 3" 3 "$RC"; eq "built-in, old-format marker: staged kept" "$C72" "$(gitlink "$P")"
printf '%s %s\n' "$C721" "$C72" >"$SB/b1marker"; rm -f -- "$(pending "$P")"; ln -s "$SB/b1marker" "$(pending "$P")"   # CONSTRUCTED valid line behind a symlink
brun "$P"; eq "built-in, symlinked marker is not read: exit 3" 3 "$RC"; eq "built-in, symlinked marker: staged kept" "$C72" "$(gitlink "$P")"
rm -f -- "$(pending "$P")"
printf '%s %s\n' "$C721" "$C72" >"$(pending "$P")"   # CONSTRUCTED valid marker: names the checkout and what was staged before
brun "$P"; eq "built-in positive control (valid marker): exit 0" 0 "$RC"; eq "built-in positive control: staged the checkout" "$C721" "$(gitlink "$P")"
check "built-in positive control: marker removed" eval '[ ! -e "$(pending "$P")" ]'
echo "# F1/F2 the marker written by a real built-in update is '<target> <staged-before>' and is never written through a symlink"
bsetup "$SB/b2"; P="$SB/b2"; git -C "$P" restore --staged -- "$SUBMOD"; git -C "$P/$SUBMOD" checkout -q --detach "$C71"
ln -s "$SB/victim_b" "$(pending "$P")"
brun "$P"; eq "built-in update with a symlinked marker present: exit 0" 0 "$RC"
check "built-in: the marker symlink was not written through" eval '[ ! -e "$SB/victim_b" ]'
eq "built-in: staged v72.1" "$C721" "$(gitlink "$P")"

echo "# F1 a real cut-off built-in update writes '<target> <staged-before>'"
P="$SB/b3"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; git -C "$P" commit -qm add
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72; eq "built-in first update: exit 0" 0 "$RC"
: >"$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1; check "built-in second update cut off: non-zero exit" eval '[ "$RC" != 0 ]'
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
eq "built-in real marker: '<target> <staged-before>'" "$C721 $C72" "$(head -n 1 "$(pending "$P")")"
echo "# F1 seam: the marker exists at the moment of the built-in checkout (written BEFORE it)"
P="$SB/b4"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; git -C "$P" commit -qm add
: >"$SEAMLOG"
OUT="$(cd "$P" && SEAM_LOG="$SEAMLOG" SEAM_MARKER="$(pending "$P")" PATH="$SB/wrap:$PATH" bash "$INSTALLER" "${BASE[@]}" --ref helixconstitution-v72 2>&1)"; RC=$?
eq "seam: built-in update exit 0" 0 "$RC"
check "seam control needle: the wrapper saw the checkout" eval '[ -s "$SEAMLOG" ]'
check "seam: marker was PRESENT at every built-in checkout" eval '! grep -q absent "$SEAMLOG" && grep -q present "$SEAMLOG"'
check "seam: marker content at the built-in checkout is '<target> <staged-before>'" eval '[ "$(sort -u "$SEAMLOG")" = "present $C72 $C71" ]'
fi
if sec F2; then
echo "# F2 updater: committed V0 < staged V1 < checkout V2 (hand-staged), marker variants"
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
advance_upstream "$SB/up" helixconstitution-v999.2 || exit 2; V2="$(tagsha "$SB/up" helixconstitution-v999.2)"
usetup() { mkinstalled "$1"; git -C "$1/$SUBMOD" fetch -q --tags origin; git -C "$1/$SUBMOD" checkout -q --detach "$V2"; stage_gitlink "$1" "$V1"; }
usetup "$SB/u1"; P="$SB/u1"
printf '%s %s\n' "$V1" "$V1" >"$(pending "$P")"   # CONSTRUCTED: names ANOTHER commit
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "updater, foreign marker: exit 3" 3 "$RC"; eq "updater, foreign marker: staged kept" "$V1" "$(gitlink "$P")"
printf '%s %s\n' "$V2" "$V0" >"$(pending "$P")"   # CONSTRUCTED: right target, STALE staged-before
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "updater, stale marker: exit 3" 3 "$RC"; eq "updater, stale marker: staged kept" "$V1" "$(gitlink "$P")"
printf '%s\n' "$V2" >"$(pending "$P")"   # CONSTRUCTED: old format
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "updater, old-format marker: exit 3" 3 "$RC"; eq "updater, old-format marker: staged kept" "$V1" "$(gitlink "$P")"
printf '%s %s\n' "$V2" "$V1" >"$SB/u1marker"; rm -f -- "$(pending "$P")"; ln -s "$SB/u1marker" "$(pending "$P")"   # CONSTRUCTED valid line behind a symlink
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "updater, symlinked marker is not read: exit 3" 3 "$RC"; eq "updater, symlinked marker: staged kept" "$V1" "$(gitlink "$P")"
rm -f -- "$(pending "$P")"
printf '%s %s\n' "$V2" "$V1" >"$(pending "$P")"   # CONSTRUCTED valid marker
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "updater positive control (valid marker): exit 0" 0 "$RC"; eq "updater positive control: staged V2" "$V2" "$(gitlink "$P")"
echo "# F2 the updater never writes its marker through a symlink; a real update writes '<target> <staged-before>'"
P="$SB/u2"; mkinstalled "$P"; ln -s "$SB/victim_u" "$(pending "$P")"
upd "$P" --no-hook --ref helixconstitution-v999.1; eq "updater with a symlinked marker present: exit 0" 0 "$RC"
check "updater: the marker symlink was not written through" eval '[ ! -e "$SB/victim_u" ]'
P="$SB/u3"; mkinstalled "$P"; : >"$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
upd "$P" --no-hook --ref helixconstitution-v999.1; eq "update cut off by a held index.lock: exit 1" 1 "$RC"
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
eq "real marker: two fields '<target> <staged-before>'" "$V1 $V0" "$(head -n 1 "$(pending "$P")")"
echo "# F2 seam: the marker exists at the moment of the updater checkout"
P="$SB/u4"; mkinstalled "$P"; : >"$SEAMLOG"
OUT="$(cd "$P" && SEAM_LOG="$SEAMLOG" SEAM_MARKER="$(pending "$P")" PATH="$SB/wrap:$PATH" bash submodules/constitution/scripts/update_constitution.sh --no-hook --ref helixconstitution-v999.1 2>&1)"; RC=$?
eq "seam: updater exit 0" 0 "$RC"
check "seam control needle: the wrapper saw the checkout" eval '[ -s "$SEAMLOG" ]'
check "seam: marker was PRESENT at every updater checkout" eval '! grep -q absent "$SEAMLOG" && grep -q present "$SEAMLOG"'
check "seam: marker content at the updater checkout is '<target> <staged-before>'" eval '[ "$(sort -u "$SEAMLOG")" = "present $V1 $V0" ]'

fi
if sec F3; then
echo "# F3 hi_mark_hash: sha256sum first, cksum as the fallback, neither => fail closed"
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"
mkdir -p "$SB/p_both" "$SB/p_ck" "$SB/p_no"
for t in cat sort; do x="$(command -v "$t")"; for d in p_both p_ck p_no; do ln -s "$x" "$SB/$d/$t"; done; done
ln -s "$(command -v sha256sum)" "$SB/p_both/sha256sum"; ln -s "$(command -v cksum)" "$SB/p_both/cksum"; ln -s "$(command -v cksum)" "$SB/p_ck/cksum"
hh() { printf 'b\na\n' | PATH="$1" hi_mark_hash 2>/dev/null; }
check "control needle: cksum-only PATH has no sha256sum" eval '! PATH="$SB/p_ck" command -v sha256sum >/dev/null'
check "both tools: sha256sum is used" grep -qE '^sha256sum:[0-9a-f]{64}' <<<"$(hh "$SB/p_both")"
check "cksum only: cksum fallback" grep -qE '^cksum:[0-9]+' <<<"$(hh "$SB/p_ck")"
hh "$SB/p_no" >/dev/null; eq "no tool: hi_mark_hash exits non-zero" 1 "$?"
HELP="$(bash "$INSTALLER" --help 2>&1 | tr '\n' ' ' | tr -s ' ')"
check "--help: neither sha256sum nor cksum fails closed" grep -qi "neither sha256sum nor cksum" <<<"$HELP"
fi
finish
