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
eq "deadline: slow remote not fetched in time" "True" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="slow"][0]["fetch"] in ("timeout","deadline")')"
git -C "$W" remote remove slow

# 3. concurrent run: the second is refused while the first holds the lock
LOCK="$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/helix-sync-upstreams.lock"
python3 -I -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_CREAT,0o600); fcntl.flock(fd,fcntl.LOCK_EX); open(sys.argv[2],"w").close(); time.sleep(30)' "$LOCK" "$SB/locked" &
BG="$BG $!"; holder=$!
for _ in $(seq 1 50); do [ -e "$SB/locked" ] && break; sleep 0.1; done
before="$(sx_head "$W")"
sx_run --apply --root "$W"
eq "concurrent run: exit 7 (locked, distinct from usage 2)" 7 "$SX_RC"
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

# 6. a STALLED local read (no answer within --timeout) is never read as "absent" (F3)
safe_rm_rf "${W:?}"; sx_clone "$U_ROOT" "$SB/work/root"; sx_commit "$U_ROOT" "r6"
STALLMARK="helixstall$$"
mkdir -p "$SB/stall"
# (a local call gets max(--timeout, 60)s; --deadline bounds it so the test is short)
# stalls `rev-parse HEAD` of the repository in $STALL_REPO; with STALL_AFTER_MOVE=1 only once its HEAD
# differs from $STALL_BEFORE (the read AFTER a fast-forward). Every other call is the real git.
cat >"$SB/stall/git" <<EOF
#!/usr/bin/env bash
# $STALLMARK
if [ "\${2:-}" = "\${STALL_REPO:-}" ] && [ "\${*: -3}" = "--no-optional-locks rev-parse HEAD" ]; then
  if [ -z "\${STALL_AFTER_MOVE:-}" ] || [ "\$("$SX_GIT" -C "\$2" rev-parse HEAD)" != "\${STALL_BEFORE:-}" ]; then
    exec -a $STALLMARK sleep 200
  fi
fi
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/stall/git"
stall_run() { SX_N=$((SX_N+1)); local o="$SB/out/r$SX_N"
  SX_OUT="$(PATH="$SB/stall:$PATH" bash "$SX_ENGINE" --out "$o" --run-id "r$SX_N" "$@" 2>"$o.err")"; SX_RC=$?
  SX_ERR="$(cat "$o.err")"; SX_JSON="$o/sync_report.json"; }
RW="$(cd "$W" && pwd -P)"   # the engine passes the resolved path to git -C
before="$(sx_head "$W")"
start=$(date +%s); STALL_REPO="$RW" stall_run --check --timeout 3 --deadline 10 --root "$W"; dur=$(( $(date +%s) - start ))
eq "stalled HEAD read, --check: exit 5 (INCONCLUSIVE)" 5 "$SX_RC"
eq "stalled HEAD read: root result unresolved" "unresolved" "$(sx_q 'P["."]["result"]')"
eq "stalled HEAD read: verdict INCONCLUSIVE" "INCONCLUSIVE" "$(sx_q 'r["verdict"]')"
[ "$dur" -lt 40 ] && ok "stalled read: bounded (${dur}s)" || nok "stalled read: took ${dur}s"
STALL_REPO="$RW" stall_run --apply --timeout 3 --deadline 10 --root "$W"
eq "stalled HEAD read, --apply: exit 5" 5 "$SX_RC"
eq "stalled HEAD read, --apply: root not moved" "$before" "$(sx_head "$W")"
eq "stalled HEAD read, --apply: never reported updated" "False" "$(sx_q 'P["."]["result"]=="updated"')"
STALL_REPO="$RW" STALL_AFTER_MOVE=1 STALL_BEFORE="$before" stall_run --apply --timeout 3 --deadline 20 --root "$W"
eq "HEAD read stalls only after the move: exit 5, not 0" 5 "$SX_RC"
eq "after-move stall: result unresolved, never updated-with-unknown-head" "unresolved" "$(sx_q 'P["."]["result"]')"
eq "after-move stall: the move itself happened (real HEAD)" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
sleep 1
eq "stalled reads: no surviving stalled process" "0" "$(ps -eo args= | grep -c "^$STALLMARK" || true)"
sx_run --check --root "$W"
eq "control needle: without the stall the root is read (result current)" "current" "$(sx_q 'P["."]["result"]')"
eq "control needle: without the stall the verdict is not INCONCLUSIVE" "False" "$(sx_q 'r["verdict"]=="INCONCLUSIVE"')"

# 7. an ESCAPED grandchild holding the stderr pipe cannot stretch a call past its budget (F8)
ESCMARK="helixescape$$"
printf '#!/usr/bin/env bash\n# %s\necho $$ >"%s/escaper.pid"\nexec sleep 45\n' "$ESCMARK" "$SB" >"$SB/escaper"; chmod +x "$SB/escaper"
# The fake ssh is put on PATH (the engine's default ssh command runs `ssh`), so git runs it as the
# TRANSPORT: its stderr is the engine's stderr pipe. (Set as core.sshCommand without ssh.variant, git
# first runs `<cmd> -G` with every fd on /dev/null, and an escaper started there holds nothing.)
printf '#!/bin/sh\nsetsid "%s" &\nsleep 30\n' "$SB/escaper" >"$SB/shim/ssh"; chmod +x "$SB/shim/ssh"
git -C "$W" remote add esc "ssh://git@127.0.0.1:9/x.git"
start=$(date +%s); sx_run --check --timeout 3 --root "$W"; dur=$(( $(date +%s) - start ))
[ "$dur" -lt 15 ] && ok "escaped grandchild: run bounded (${dur}s)" || nok "escaped grandchild: run took ${dur}s"
eq "escaped grandchild: remote reported unreachable" "unreachable" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="esc"][0]["state"]')"
for _ in $(seq 1 20); do [ -s "$SB/escaper.pid" ] && break; sleep 0.1; done
ep="$(cat "$SB/escaper.pid" 2>/dev/null)"
case "$ep" in ""|*[!0-9]*|0|1) nok "escaped grandchild: control needle: it really started (no pid)" ;;
  *) ok "escaped grandchild: control needle: it really started (pid $ep)"
     # and it really holds a pipe on stderr (else the case proves nothing about the bound)
     case "$(readlink "/proc/$ep/fd/2" 2>/dev/null)" in pipe:*) ok "escaped grandchild: control needle: its stderr is a pipe" ;;
       *) nok "escaped grandchild: control needle: its stderr is $(readlink "/proc/$ep/fd/2" 2>/dev/null || echo gone), not a pipe" ;; esac
     # signal it only after proving it is OUR escaper (its cmdline names our script, §11.4.174)
     if tr '\0' ' ' <"/proc/$ep/cmdline" 2>/dev/null | grep -q "sleep 45"; then kill "$ep" 2>/dev/null; fi ;;
esac
git -C "$W" remote remove esc; rm -f "$SB/shim/ssh"

# 8. a HEAD read that FAILS (rc 128, an answer, not a timeout) once is never read as "current" / "moved"
sx_commit "$U_ROOT" "r8"
mkdir -p "$SB/flaky"
# fails the FIRST `rev-parse HEAD` of the repository in $FLAKY_REPO (marker $FLAKY_MARK); every other call is real git
cat >"$SB/flaky/git" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = "\${FLAKY_REPO:-}" ] && [ "\${*: -3}" = "--no-optional-locks rev-parse HEAD" ] && [ ! -e "\$FLAKY_MARK" ]; then
  : >"\$FLAKY_MARK"; echo "fatal: injected HEAD read failure" >&2; exit 128
fi
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/flaky/git"
flaky_run() { SX_N=$((SX_N+1)); local o="$SB/out/r$SX_N"
  SX_OUT="$(PATH="$SB/flaky:$PATH" bash "$SX_ENGINE" --out "$o" --run-id "r$SX_N" "$@" 2>"$o.err")"; SX_RC=$?
  SX_JSON="$o/sync_report.json"; }
before="$(sx_head "$W")"
FLAKY_REPO="$RW" FLAKY_MARK="$SB/flaky.m1" flaky_run --check --root "$W"
[ -e "$SB/flaky.m1" ] && ok "failed HEAD read: control needle: the failure was injected" || nok "failed HEAD read: control needle: never injected"
eq "failed HEAD read, --check: exit 4 (ATTENTION), never 0 or 3" 4 "$SX_RC"
eq "failed HEAD read, --check: root result attention" "attention" "$(sx_q 'P["."]["result"]')"
has "failed HEAD read, --check: reason head-unreadable" "head-unreadable" "$(sx_q 'P["."]["reasons"]')"
FLAKY_REPO="$RW" FLAKY_MARK="$SB/flaky.m2" flaky_run --apply --root "$W"
eq "failed HEAD read, --apply: exit 4" 4 "$SX_RC"
eq "failed HEAD read, --apply: root not moved" "$before" "$(sx_head "$W")"
has "failed HEAD read, --apply: integration blocked by head-unreadable" "head-unreadable" "$(sx_q '[a.get("why","") for a in P["."]["actions"]]')"
eq "failed HEAD read, --apply: never reported updated" "False" "$(sx_q 'P["."]["result"]=="updated"')"
sx_run --check --root "$W"
eq "control needle: without the failure the root is behind (exit 3)" 3 "$SX_RC"

finish
