#!/usr/bin/env bash
# tests/sync/test_chaos.sh -- STRESS / CHAOS tests of scripts/sync/sync_all_upstreams.sh (real git, sandbox):
#   unreachable remote, garbage remote, a SLOW remote (its configured upload-pack sleeps) killed by --timeout
#   with no surviving process, a run interrupted with SIGKILL then re-run, a concurrent run refused by the
#   lock, the --deadline budget, and many submodules with one broken among them.
# Every background process this suite starts is recorded and killed on exit (pid > 1 only, §11.4.263).
T_NAME=sync-chaos
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
BG=""
trap 'for p in $BG; do case "$p" in ""|*[!0-9]*|0|1) ;; *) kill "$p" 2>/dev/null ;; esac; done; sx_cleanup' EXIT
echo "== $T_NAME (sandbox $SB)"
sx_std_tree
sx_commit "$U_ROOT" "r1"

# 1. unreachable + garbage remotes: reported, the rest still evaluated, nothing integrated in that repo
git -C "$W" remote add gone "file://$SB/remotes/does-not-exist.git"
mkdir -p "$SB/remotes/garbage.git"; echo junk >"$SB/remotes/garbage.git/HEAD"
git -C "$W/libs/a" remote add junk "file://$SB/remotes/garbage.git"
sx_run --apply --root "$W"
eq "unreachable: exit 4" 4 "$SX_RC"
eq "unreachable remote state" "unreachable" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="gone"][0]["state"]')"
eq "garbage remote state" "unreachable" "$(sx_q '[x for x in P["libs/a"]["remotes"] if x["name"]=="junk"][0]["state"]')"
eq "origin still fetched and evaluated" "behind" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="origin"][0]["state"]')"
eq "repo with an unreachable remote is not integrated" "attention" "$(sx_q 'P["."]["result"]')"
eq "third-party repo unaffected" "current" "$(sx_q 'P["vendor/t"]["result"]')"
git -C "$W" remote remove gone; git -C "$W/libs/a" remote remove junk

# 2. slow remote: its upload-pack sleeps; --timeout kills it and its process group
MARK="helixsyncslow$$"
printf '#!/usr/bin/env bash\n# %s\nsleep 60\n' "$MARK" >"$SB/slow-upload-pack"; chmod +x "$SB/slow-upload-pack"
git -C "$W" remote add slow "file://$SB/remotes/HelixDevelopment/root.git"
git -C "$W" config remote.slow.uploadpack "$SB/slow-upload-pack"
start=$(date +%s); sx_run --check --timeout 3 --root "$W"; dur=$(( $(date +%s) - start ))
eq "slow remote: fetch state timeout" "timeout" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="slow"][0]["fetch"]')"
eq "slow remote: reported unreachable" "unreachable" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="slow"][0]["state"]')"
[ "$dur" -lt 20 ] && ok "slow remote: run bounded (${dur}s)" || nok "slow remote: run took ${dur}s"
sleep 1
left="$(ps -eo args= | grep -c "[s]low-upload-pack" || true)"
eq "slow remote: no surviving upload-pack process" "0" "$left"
# deadline: the whole run is bounded even with many slow calls
start=$(date +%s); sx_run --check --timeout 60 --deadline 4 --root "$W"; dur=$(( $(date +%s) - start ))
[ "$dur" -lt 25 ] && ok "deadline: run bounded (${dur}s)" || nok "deadline: run took ${dur}s"
eq "deadline: slow remote not fetched in time" "True" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="slow"][0]["fetch"] in ("timeout","failed")')"
git -C "$W" remote remove slow

# 3. concurrent run: the second is refused while the first holds the lock
LOCK="$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/helix-sync-upstreams.lock"
python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(30)' "$LOCK" "$SB/locked" &
BG="$BG $!"; holder=$!
for _ in $(seq 1 50); do [ -e "$SB/locked" ] && break; sleep 0.1; done
before="$(sx_head "$W")"
sx_run --apply --root "$W"
eq "concurrent run: exit 2" 2 "$SX_RC"
has "concurrent run: says the lock is held" "another sync run holds" "$SX_ERR"
eq "concurrent run: nothing changed" "$before" "$(sx_head "$W")"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
sx_run --apply --root "$W"
eq "after the holder exits the lock is free (exit 0)" 0 "$SX_RC"

# 4. interrupted run (SIGKILL), then re-run converges; no stale lock, no half state
sx_commit "$U_ROOT" "r2"; sx_commit "$U_A" "a2"
( PATH="$SB/shim:$PATH" exec bash "$SX_ENGINE" --apply --advance-pins --root "$W" --out "$SB/out/killed" --quiet >/dev/null 2>&1 ) &
victim=$!; BG="$BG $victim"
sleep 0.4; kill -9 "$victim" 2>/dev/null; wait "$victim" 2>/dev/null
git -C "$W" status --porcelain=v1 >/dev/null
sx_run --apply --advance-pins --root "$W"
eq "re-run after SIGKILL: exit 0" 0 "$SX_RC"
eq "re-run: root at upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "re-run: libs/a at upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
eq "re-run: no index.lock left" "no" "$([ -e "$(git -C "$W" rev-parse --absolute-git-dir)/index.lock" ] && echo yes || echo no)"

# 5. many submodules, one broken (its upstream deleted): the others are still synced
U_BIG="$(sx_bare HelixDevelopment big)"
for i in $(seq 1 12); do
  u="$(sx_bare HelixDevelopment "m$i")"; sx_add_sub "$U_BIG" "$u" "mods/m$i"
done
B="$SB/work/big"; sx_clone "$U_BIG" "$B"
for i in 3 7 11; do sx_commit "$(printf 'file://%s/remotes/HelixDevelopment/m%s.git' "$SB" "$i")" "m$i moves"; done
mv "$SB/remotes/HelixDevelopment/m5.git" "$SB/remotes/HelixDevelopment/m5.gone"
sx_run --apply --advance-pins --jobs 4 --root "$B"
eq "many: exit 4 (one broken)" 4 "$SX_RC"
eq "many: 13 repositories discovered" "13" "$(sx_q 'r["counts"]["repos"]')"
eq "many: broken one is attention" "attention" "$(sx_q 'P["mods/m5"]["result"]')"
eq "many: three own-org pins advanced" "3" "$(sx_q 'sum(1 for x in r["repos"] if x["result"]=="updated")')"
eq "many: three gitlinks staged" "3" "$(git -C "$B" diff --cached --name-only | wc -l | tr -d ' ')"

finish
