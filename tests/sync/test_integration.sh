#!/usr/bin/env bash
# tests/sync/test_integration.sh -- INTEGRATION tests of scripts/sync/sync_all_upstreams.sh against REAL
# git: real bare upstream repositories and real working clones with real submodules in a scratch sandbox
# (scripts/sync/fixture_lib.sh). No network, no forge, no push to any real remote, never the live checkout.
# Fixture-side git calls use the plain `git` on PATH (the recording shim is on PATH only inside sx_run).
# Exit 0 all pass, 1 a failure. SX_ENGINE overrides the engine (mutation harness, RED stub).
T_NAME=sync-integration
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
gd() { git -C "$1" rev-parse --absolute-git-dir; }

# ── 1. a fresh clone is CURRENT; discovery sees root, libs/a, libs/a/inner, vendor/t
sx_std_tree
sx_run --check --root "$W"
eq "fresh clone: exit 0" 0 "$SX_RC"
has "fresh clone: verdict CURRENT" "RESULT: CURRENT exit=0" "$SX_OUT"
eq "discovery: 4 repositories" "4" "$(sx_q 'r["counts"]["repos"]')"
eq "discovery: nested inner found" "True" "$(sx_q '"libs/a/inner" in P')"
eq "control needle ok" "True" "$(sx_q 'r["control_needle"]["ok"]')"
eq "own-org detected for libs/a" "True" "$(sx_q 'P["libs/a"]["own_org"]')"
eq "third-party detected for vendor/t" "False" "$(sx_q 'P["vendor/t"]["own_org"]')"
eq "pin at-main for libs/a" "at-main" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
eq "fetch ran once per remote (4)" "4" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"

# ── 2. upstream moves: check reports behind (exit 3) and changes nothing
sx_commit "$U_ROOT" "root change 1"
sx_commit "$U_A" "liba change 1"
before_root="$(sx_head "$W")"; before_a="$(sx_head "$W/libs/a")"
sx_run --check --root "$W"
eq "behind: exit 3" 3 "$SX_RC"
has "behind: verdict" "UPDATES-AVAILABLE" "$SX_OUT"
eq "root behind by 1" "1" "$(sx_q 'P["."]["behind_target"]')"
eq "libs/a pin behind-main" "behind-main" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
eq "check changed nothing (root)" "$before_root" "$(sx_head "$W")"
eq "check changed nothing (libs/a)" "$before_a" "$(sx_head "$W/libs/a")"
eq "tsv has 5 lines (header + 4)" "5" "$(wc -l <"$SX_TSV" | tr -d ' ')"

# ── 3. dry-run never fetches and never changes
: >"$SB/git_calls.log"
sx_run --dry-run --root "$W"
eq "dry-run: exit 3 (refs already fetched)" 3 "$SX_RC"
eq "dry-run: no fetch in the shim log" "0" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"
eq "dry-run: no change" "$before_root" "$(sx_head "$W")"

# ── 4. --check --no-fetch: offline, no fetch call
sx_commit "$U_ROOT" "root change 2"
: >"$SB/git_calls.log"
sx_run --check --no-fetch --root "$W"
eq "no-fetch: no fetch in the shim log" "0" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"
eq "no-fetch: sees only already-fetched refs (behind 1)" "1" "$(sx_q 'P["."]["behind_target"]')"

# ── 5. apply: root fast-forwards, libs/a pin NOT advanced without --advance-pins
: >"$SB/git_calls.log"
sx_run --apply --root "$W"
eq "apply: exit 3 (libs/a pin still behind: not fully current)" 3 "$SX_RC"
has "apply: verdict UPDATES-AVAILABLE" "RESULT: UPDATES-AVAILABLE exit=3" "$SX_OUT"
eq "apply: root at upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "apply: root result updated" "updated" "$(sx_q 'P["."]["result"]')"
eq "apply: libs/a unchanged without --advance-pins" "$before_a" "$(sx_head "$W/libs/a")"
eq "apply: libs/a still reported behind" "behind" "$(sx_q 'P["libs/a"]["result"]')"
eq "apply: root on branch main still" "main" "$(git -C "$W" symbolic-ref --short HEAD)"
eq "apply: exactly one merge, and it is --ff-only" "1 1" "$(grep -c $'\x1fmerge\x1f' "$SB/git_calls.log") $(grep -c $'\x1fmerge\x1f--ff-only\x1f' "$SB/git_calls.log")"

# ── 6. apply --advance-pins: own-org pin advances and is STAGED (never committed); third-party is not
sx_commit "$U_T" "third-party change"
before_t="$(sx_head "$W/vendor/t")"; commits_before="$(git -C "$W" rev-list --count HEAD)"
sx_run --apply --advance-pins --root "$W"
eq "advance-pins: exit 0" 0 "$SX_RC"
eq "advance-pins: libs/a at upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
has "advance-pins: gitlink staged in root" "M  libs/a" "$(git -C "$W" status --porcelain=v1)"
eq "advance-pins: no commit created" "$commits_before" "$(git -C "$W" rev-list --count HEAD)"
eq "advance-pins: third-party untouched" "$before_t" "$(sx_head "$W/vendor/t")"
eq "advance-pins: third-party behind is informational (current)" "current" "$(sx_q 'P["vendor/t"]["result"]')"
sx_run --apply --advance-pins --advance-third-party --root "$W"
eq "advance-third-party: vendor/t advanced" "$(sx_remote_head "$SB/remotes/thirdparty/tlib.git")" "$(sx_head "$W/vendor/t")"

# ── 7. idempotent: a second apply changes nothing. The pins staged above are not committed yet, so the root's
#    index records gitlinks its HEAD does not: reported gitlink-staged:<path> (attention, exit 4; round 5, RV4-2)
#    until the user commits them; nothing is written over them and nothing else is held back.
h1="$(sx_head "$W")"; s1="$(git -C "$W" status --porcelain=v1)"
sx_run --apply --advance-pins --advance-third-party --root "$W"
eq "idempotent: exit 4 (staged pins await the user's commit)" 4 "$SX_RC"
eq "idempotent: staged pins reported" "True True" "$(sx_q '" ".join(str(x in P["."]["reasons"]) for x in ("gitlink-staged:libs/a", "gitlink-staged:vendor/t"))')"
eq "idempotent: no write attempted" "0" "$(sx_q 'sum(1 for x in r["repos"] for a in x["actions"] if a.get("op") not in (None, "none"))')"
eq "idempotent: root unchanged" "$h1" "$(sx_head "$W")"
eq "idempotent: index unchanged" "$s1" "$(git -C "$W" status --porcelain=v1)"
eq "idempotent: no repo updated" "0" "$(sx_q 'sum(1 for x in r["repos"] if x["result"]=="updated")')"

# ── 8. children follow a parent's new recorded gitlink (fresh clone)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
sx_commit "$U_IN" "inner change"
sx_bump_pin "$U_A" inner
sx_bump_pin "$U_ROOT" libs/a
sx_run --apply --root "$W"
eq "follow: exit 0" 0 "$SX_RC"
eq "follow: libs/a followed root's new gitlink" "$(git -C "$W" ls-tree HEAD libs/a | awk '{print $3}')" "$(sx_head "$W/libs/a")"
eq "follow: inner followed libs/a's new gitlink" "$(git -C "$W/libs/a" ls-tree HEAD inner | awk '{print $3}')" "$(sx_head "$W/libs/a/inner")"
eq "follow: tree clean after follow" "" "$(git -C "$W" status --porcelain=v1 --ignore-submodules=none)"

# ── 8b. a DIRTY child is never moved by the follow step (its edit is kept)
sx_commit "$U_A" "liba change for 8b"
sx_bump_pin "$U_ROOT" libs/a
echo childedit >>"$W/libs/a/README"
child_before="$(sx_head "$W/libs/a")"
sx_run --apply --root "$W"
eq "dirty child: not followed" "$child_before" "$(sx_head "$W/libs/a")"
has "dirty child: reason recorded" "follow-skipped:drifted-or-dirty" "$(sx_q 'str(P["libs/a"]["actions"])')"
eq "dirty child: edit kept" "childedit" "$(tail -n1 "$W/libs/a/README")"
git -C "$W/libs/a" checkout -q -- README
git -C "$W" -c protocol.file.allow=always submodule update -q --recursive

# ── 9. dirty tree blocks that repo (exit 4); nothing moves; the edit is kept
sx_commit "$U_ROOT" "root change 3"
echo dirty >>"$W/README"
before_root="$(sx_head "$W")"
sx_run --apply --root "$W"
eq "dirty: exit 4" 4 "$SX_RC"
eq "dirty: reason dirty-tree" "True" "$(sx_q '"dirty-tree" in P["."]["reasons"]')"
# the precondition blocks it, before the guarded writer is reached (the writer's own re-check is a second layer;
# review round 3, own mutant M17 survived without these two lines)
eq "dirty: blocked by the precondition" "True" "$(sx_q 'any("dirty-tree" in a.get("why","").split(",") for a in P["."].get("actions",[]))')"
eq "dirty: no write was attempted" "False" "$(sx_q 'any("for" in a for a in P["."].get("actions",[]))')"
eq "dirty: root not moved" "$before_root" "$(sx_head "$W")"
eq "dirty: local edit kept" "dirty" "$(tail -n1 "$W/README")"
git -C "$W" checkout -q -- README

# ── 10. in-progress merge and index.lock block
: >"$(gd "$W")/MERGE_HEAD"
sx_run --apply --root "$W"
eq "merge in progress: exit 4" 4 "$SX_RC"
eq "merge in progress: reason" "True" "$(sx_q '"in-progress:MERGE_HEAD" in P["."]["reasons"]')"
rm -f -- "$(gd "$W")/MERGE_HEAD"
: >"$(gd "$W")/index.lock"
sx_run --apply --root "$W"
eq "index.lock: exit 4" 4 "$SX_RC"
eq "index.lock: root not moved" "$before_root" "$(sx_head "$W")"
rm -f -- "$(gd "$W")/index.lock"

# ── 11. local ahead / diverged: never merged, never reset
git -C "$W" merge -q --ff-only origin/main
echo local >"$W/LOCAL"; git -C "$W" add LOCAL; git -C "$W" commit -q -m "local only"
local_head="$(sx_head "$W")"
sx_run --check --root "$W"
eq "local ahead: exit 4" 4 "$SX_RC"
eq "local ahead: reason" "True" "$(sx_q '"local-ahead" in P["."]["reasons"]')"
sx_commit "$U_ROOT" "root change 4"
sx_run --apply --root "$W"
eq "diverged: exit 4" 4 "$SX_RC"
eq "diverged: reason local-diverged" "True" "$(sx_q '"local-diverged" in P["."]["reasons"]')"
eq "diverged: local commit kept" "$local_head" "$(sx_head "$W")"
git -C "$W" checkout -q --detach origin/main; git -C "$W" branch -q -f main origin/main; git -C "$W" checkout -q main

# ── 12. root not on main -> attention, no change
git -C "$W" checkout -q -b topic
sx_run --check --root "$W"
eq "root on topic: exit 4" 4 "$SX_RC"
eq "root on topic: reason" "True" "$(sx_q '"root-not-on-main" in P["."]["reasons"]')"
git -C "$W" checkout -q main

# ── 13. two remotes: linear -> newest wins; diverged -> upstreams-diverged and nothing moves
U_M="$(sx_bare HelixDevelopment rootmirror)"
git --git-dir="$SB/remotes/HelixDevelopment/rootmirror.git" fetch -q "$SB/remotes/HelixDevelopment/root.git" +main:main
git -C "$W" remote add mirror "$U_M"
sx_commit "$U_ROOT" "root change 5"
sx_run --apply --root "$W"
eq "two remotes linear: exit 0" 0 "$SX_RC"
eq "two remotes linear: newest main wins" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "two remotes linear: mirror state is measured against the head before the run (equal)" "equal" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="mirror"][0]["state"]')"
sx_commit "$U_M" "mirror-only change"
sx_commit "$U_ROOT" "root change 6"
before_root="$(sx_head "$W")"
sx_run --apply --root "$W"
eq "two remotes diverged: exit 4" 4 "$SX_RC"
eq "two remotes diverged: upstreams-diverged" "upstreams-diverged" "$(sx_q 'P["."]["upstream_state"]')"
eq "two remotes diverged: nothing moved" "$before_root" "$(sx_head "$W")"
git -C "$W" remote remove mirror

# ── 14. pin classes: not-on-main, unfetchable (§11.4.288(D), §11.4.233(G)); uninitialised
sx_run --apply --root "$W"
w2="$(sx_seed "$U_A")"
git -C "$w2" checkout -q -b side; echo s >"$w2/S"; git -C "$w2" add S; git -C "$w2" commit -q -m side
git -C "$w2" push -q origin side; side_sha="$(sx_head "$w2")"; git -C "$w2" checkout -q main
git -C "$W/libs/a" fetch -q origin
git -C "$W/libs/a" checkout -q --detach "$side_sha"
git -C "$W" add libs/a; git -C "$W" commit -q -m "pin libs/a to a side commit"
sx_run --check --root "$W"
eq "pin not on main: exit 4" 4 "$SX_RC"
eq "pin not on main: state" "not-on-main" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
git -C "$W" update-index --cacheinfo "160000,$(printf '%040d' 7),libs/a"
git -C "$W" commit -q -m "pin libs/a to a missing commit"
sx_run --check --root "$W"
eq "pin unfetchable: state" "unfetchable" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
eq "pin unfetchable: exit 4" 4 "$SX_RC"
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
git -C "$W" submodule deinit -q vendor/t
sx_run --check --root "$W"
eq "uninitialised: state" "uninitialised" "$(sx_q 'P["vendor/t"]["pin"]["state"]')"
eq "uninitialised: not attention by default" "not-initialised" "$(sx_q 'P["vendor/t"]["result"]')"
sx_run --check --strict-pins --root "$W"
eq "uninitialised + --strict-pins: exit 4" 4 "$SX_RC"

# ── 15. usage and refusal paths
sx_run --root "$W"
eq "no mode: exit 2" 2 "$SX_RC"
SX_OUT="$(bash "$SX_ENGINE" --check --root "$W" --out "$W/evidence" 2>&1)"; SX_RC=$?
eq "--out inside the work tree: exit 2" 2 "$SX_RC"
eq "--out inside: nothing written" "no" "$([ -e "$W/evidence" ] && echo yes || echo no)"
SX_OUT="$(bash "$SX_ENGINE" --check --root "$W/libs" --out "$SB/out/x" 2>&1)"; SX_RC=$?
eq "--root not a top level: exit 2" 2 "$SX_RC"
SX_OUT="$(bash "$SX_ENGINE" --check --root "$SB/seed" --out "$SB/out/y" 2>&1)"; SX_RC=$?
eq "--root outside any work tree: exit 2" 2 "$SX_RC"

# ── 16. an UNTRACKED (not ignored) file makes the tree dirty: blocked, kept (R5)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
sx_commit "$U_ROOT" "root change 16"
echo mine >"$W/NEWFILE"; before_root="$(sx_head "$W")"
sx_run --apply --root "$W"
eq "untracked: exit 4" 4 "$SX_RC"
eq "untracked: reason dirty-tree" "True" "$(sx_q '"dirty-tree" in P["."]["reasons"]')"
eq "untracked: root not moved" "$before_root" "$(sx_head "$W")"
eq "untracked: file kept" "mine" "$(cat "$W/NEWFILE")"
rm -f -- "$W/NEWFILE"

# ── 17. a submodule checked out on a BRANCH is never detached by the follow step (R3)
git -C "$W/libs/a" checkout -q -b topic
child_before="$(sx_head "$W/libs/a")"
sx_commit "$U_A" "liba change 17"; sx_bump_pin "$U_ROOT" libs/a
sx_run --apply --root "$W"
eq "submodule on branch: root moved" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "submodule on branch: not moved" "$child_before" "$(sx_head "$W/libs/a")"
eq "submodule on branch: still on topic" "topic" "$(git -C "$W/libs/a" symbolic-ref --short -q HEAD)"
has "submodule on branch: reason recorded" "follow-skipped:submodule-on-branch" "$(sx_q 'str(P["libs/a"]["actions"])')"
eq "submodule on branch: reason kept-on-branch:follow-pin" "True" "$(sx_q '"kept-on-branch:follow-pin" in P["libs/a"]["reasons"]')"

# ── 18. a submodule ON MAIN is fast-forwarded and the parent's gitlink change is reported (F11)
recorded="$(git -C "$W" ls-tree HEAD libs/a | awk '{print $3}')"
git -C "$W/libs/a" fetch -q origin; git -C "$W/libs/a" checkout -q -B main "$recorded"; git -C "$W/libs/a" branch -q -D topic
sx_commit "$U_A" "liba change 18"
sx_run --apply --root "$W"
eq "submodule on main: ff to upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
eq "submodule on main: exit 4 (parent gitlink modified)" 4 "$SX_RC"
eq "submodule on main: reason gitlink-modified:libs/a" "True" "$(sx_q '"gitlink-modified:libs/a" in P["."]["reasons"]')"
eq "submodule on main: nothing staged in the parent" "" "$(git -C "$W" diff --cached --name-only)"

# ── 19. root on a TOPIC branch: pins are never staged into its index (F7)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
git -C "$W" checkout -q -b topic
sx_commit "$U_A" "liba change 19"
sx_run --apply --advance-pins --root "$W"
eq "topic root + advance-pins: exit 4" 4 "$SX_RC"
eq "topic root: index untouched" "" "$(git -C "$W" diff --cached --name-only)"
eq "topic root: still on topic" "topic" "$(git -C "$W" symbolic-ref --short -q HEAD)"
eq "topic root: libs/a reported parent-not-integrated" "True" "$(sx_q 'any("parent-not-integrated" in str(a) for a in P["libs/a"]["actions"]) or "parent-not-integrated" in str(P["libs/a"]["reasons"])')"
git -C "$W" checkout -q main

# ── 20. a pin reachable only from refs/remotes/origin/feature/main is NOT on main (F13)
w2="$(sx_seed "$U_A")"
git -C "$w2" checkout -q -b feature/main; echo f >"$w2/F"; git -C "$w2" add F; git -C "$w2" commit -q -m feat
git -C "$w2" push -q origin feature/main; feat_sha="$(sx_head "$w2")"; git -C "$w2" checkout -q main
git -C "$W/libs/a" fetch -q origin; git -C "$W/libs/a" checkout -q --detach "$feat_sha"
git -C "$W" add libs/a; git -C "$W" commit -q -m "pin libs/a to feature/main"
sx_run --check --root "$W"
eq "feature/main pin: not-on-main" "not-on-main" "$(sx_q 'P["libs/a"]["pin"]["state"]')"

# ── 21. main deleted upstream: reported no-main; the stale remote-tracking ref is NOT deleted by us (F1)
U_G="$(sx_bare HelixDevelopment gone)"; G="$SB/work/gone"; sx_clone "$U_G" "$G"
wg="$(sx_seed "$U_G")"; git -C "$wg" checkout -q -b trunk; git -C "$wg" push -q origin trunk
git --git-dir="$SB/remotes/HelixDevelopment/gone.git" symbolic-ref HEAD refs/heads/trunk
git --git-dir="$SB/remotes/HelixDevelopment/gone.git" update-ref -d refs/heads/main
sx_run --check --root "$G"
eq "main gone upstream: remote state no-main" "no-main" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="origin"][0]["state"]')"
eq "main gone upstream: exit 4" 4 "$SX_RC"
eq "main gone upstream: reason upstream-branch-gone:origin" "True" "$(sx_q '"upstream-branch-gone:origin" in P["."]["reasons"]')"
eq "main gone upstream: refs/remotes/origin/main kept" "yes" "$(git -C "$G" rev-parse -q --verify refs/remotes/origin/main >/dev/null && echo yes || echo no)"

# ── 22. a submodule whose .git git cannot read (a broken gitdir pointer, git exits 128) is BLIND, never "not
#        initialised"; its row is printed under --quiet (review round 3, F1)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
printf 'gitdir: %s\n' "$SB/no-such-gitdir" >"$W/libs/a/.git"
sx_run --check --quiet --root "$W"
eq "broken gitfile: exit 6" 6 "$SX_RC"
has "broken gitfile: verdict BLIND" "RESULT: BLIND exit=6" "$SX_OUT"
eq "broken gitfile: libs/a blind" "blind" "$(sx_q 'P["libs/a"]["result"]')"
eq "broken gitfile: pin state unreadable" "unreadable" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
eq "broken gitfile: the no-answer is git's exit 128" "True" "$(sx_q '"rev-parse:rc:128" in P["libs/a"]["unresolved"]')"
eq "broken gitfile: reason pin-unreadable" "True" "$(sx_q '"pin-unreadable" in P["libs/a"]["reasons"]')"
has "broken gitfile: the blind row is printed under --quiet" "[sync-upstreams] $(printf '%-40s %-15s' libs/a blind)" "$SX_ERR"
eq "broken gitfile: the root is current (the control below is about a real current row)" current "$(sx_q 'P["."]["result"]')"
hasnt "broken gitfile: a current row is not printed under --quiet (control)" "[sync-upstreams] $(printf '%-40s %-15s' . current)" "$SX_ERR"

# ── 23. an unknown repository extension in a submodule: BLIND as well (F1 class)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
git config --file "$W/.git/modules/libs/a/config" core.repositoryformatversion 1
git config --file "$W/.git/modules/libs/a/config" extensions.helixNoSuchExtension true
sx_run --check --quiet --root "$W"
eq "unknown extension: exit 6" 6 "$SX_RC"
eq "unknown extension: libs/a blind" "blind" "$(sx_q 'P["libs/a"]["result"]')"
eq "unknown extension: pin state unreadable" "unreadable" "$(sx_q 'P["libs/a"]["pin"]["state"]')"
eq "unknown extension: a no-answer is recorded" "True" "$(sx_q 'len(P["libs/a"]["unresolved"]) >= 1')"
has "unknown extension: the blind row is printed under --quiet" "[sync-upstreams] $(printf '%-40s %-15s' libs/a blind)" "$SX_ERR"

# ── 24. a symbolic link where a submodule should be: pin-not-a-directory (attention), never followed
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
mv "$W/vendor/t" "$SB/moved_vendor_t"; ln -s "$SB/moved_vendor_t" "$W/vendor/t"
sx_run --check --root "$W"
eq "symlinked submodule: pin state not-a-directory" "not-a-directory" "$(sx_q 'P["vendor/t"]["pin"]["state"]')"
eq "symlinked submodule: reason pin-not-a-directory" "True" "$(sx_q '"pin-not-a-directory" in P["vendor/t"]["reasons"]')"
eq "symlinked submodule: attention" "attention" "$(sx_q 'P["vendor/t"]["result"]')"
eq "symlinked submodule: exit 4" 4 "$SX_RC"

# ── 25. a child that followed its parent's new pin and is then blocked (its own remote unreachable): head_after
#        is its REAL head, it moved, and it is attention, never "updated" and never "unchanged" (review round 3, F2)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
sx_commit "$U_A" "liba change 25"; sx_bump_pin "$U_ROOT" libs/a
new_pin="$(git --git-dir="$SB/remotes/HelixDevelopment/root.git" ls-tree main libs/a | awk '{print $3}')"
git -C "$W/libs/a" fetch -q origin   # the new pin is present locally ...
git -C "$W/libs/a" config remote.origin.url "$SB/remotes/no-such-remote.git"   # ... its remote is unreachable now
child_before="$(sx_head "$W/libs/a")"
sx_run --apply --root "$W"
eq "follow then blocked: libs/a at the new pin" "$new_pin" "$(sx_head "$W/libs/a")"
eq "follow then blocked: it was not there before" "True" "$([ "$child_before" != "$new_pin" ] && echo True)"
eq "follow then blocked: followed" "True" "$(sx_q 'P["libs/a"].get("followed")')"
eq "follow then blocked: head_after is the real head" "$new_pin" "$(sx_q 'P["libs/a"]["head_after"]')"
eq "follow then blocked: moved" "True" "$(sx_q 'P["libs/a"]["moved"]')"
eq "follow then blocked: attention, never updated" "attention" "$(sx_q 'P["libs/a"]["result"]')"
eq "follow then blocked: reason unreachable:origin" "True" "$(sx_q '"unreachable:origin" in P["libs/a"]["reasons"]')"
eq "follow then blocked: exit 4" 4 "$SX_RC"

# ── 26. --advance-pins never detaches a submodule checked out on a branch (review round 3, F3)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
git -C "$W/libs/a" checkout -q -b topic   # on a local branch, at the recorded pin
child_before="$(sx_head "$W/libs/a")"
sx_commit "$U_A" "liba change 26"         # the pin is now behind upstream main
sx_run --apply --advance-pins --root "$W"
eq "advance-pins, submodule on branch: not moved" "$child_before" "$(sx_head "$W/libs/a")"
eq "advance-pins, submodule on branch: still on topic" "topic" "$(git -C "$W/libs/a" symbolic-ref --short -q HEAD)"
has "advance-pins, submodule on branch: action recorded" "advance-skipped:submodule-on-branch" "$(sx_q 'str(P["libs/a"]["actions"])')"
eq "advance-pins, submodule on branch: reason kept-on-branch:advance-pin" "True" "$(sx_q '"kept-on-branch:advance-pin" in P["libs/a"]["reasons"]')"
eq "advance-pins, submodule on branch: nothing staged" "" "$(git -C "$W" diff --cached --name-only)"
eq "advance-pins, submodule on branch: exit 4" 4 "$SX_RC"
# control in a FRESH clone (independent of what the first run did): a detached submodule at the same recorded pin,
# with the same upstream state, is advanced and staged
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
eq "advance-pins control (detached): starts at the recorded pin" "$child_before" "$(sx_head "$W/libs/a")"
eq "advance-pins control (detached): starts detached" "" "$(git -C "$W/libs/a" symbolic-ref --short -q HEAD)"
sx_run --apply --advance-pins --root "$W"
eq "advance-pins control (detached): advanced" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
eq "advance-pins control (detached): staged" "libs/a" "$(git -C "$W" diff --cached --name-only)"

# ── 27. a parent fast-forwards to a pin its child cannot fetch (the new pin is not present locally and the child's
#        remote is unreachable): the child is FAILED with follow-blocked:new-pin-unfetchable, stays where it was,
#        and the run exits 1 (the follow-blocked path was covered only by the fault-injection suite; review round 4)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"
sx_commit "$U_A" "liba change 27"; sx_bump_pin "$U_ROOT" libs/a
new_pin="$(git --git-dir="$SB/remotes/HelixDevelopment/root.git" ls-tree main libs/a | awk '{print $3}')"
git -C "$W/libs/a" config remote.origin.url "$SB/remotes/no-such-remote.git"   # NOT fetched first: the pin is absent
child_before="$(sx_head "$W/libs/a")"
eq "follow blocked: the new pin is not present in the child (precondition)" "no" \
   "$(git -C "$W/libs/a" cat-file -e "$new_pin^{commit}" 2>/dev/null && echo yes || echo no)"
sx_run --apply --root "$W"
eq "follow blocked: the parent moved to the new pin" "$new_pin" "$(git -C "$W" ls-tree HEAD libs/a | awk '{print $3}')"
eq "follow blocked: libs/a stays where it was" "$child_before" "$(sx_head "$W/libs/a")"
eq "follow blocked: libs/a failed" "failed" "$(sx_q 'P["libs/a"]["result"]')"
eq "follow blocked: one follow-blocked action" "1" \
   "$(sx_q 'len([x for x in P["libs/a"]["actions"] if x.get("why") == "follow-blocked:new-pin-unfetchable"])')"
eq "follow blocked: exit 1" 1 "$SX_RC"
has "follow blocked: verdict FAILED" "RESULT: FAILED exit=1" "$SX_OUT"

finish
