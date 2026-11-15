#!/usr/bin/env bash
# tests/sync/test_ui.sh -- UI / UX tests of the interactive wizard (--interactive): the engine runs on a REAL
# pseudo-terminal (python pty.fork, so /dev/tty is that terminal); a scripted user reads every prompt and
# answers. Asserts the exact prompts shown, that "no" means nothing happens (no fetch, no change), that "yes"
# integrates, that the transcript never shows a secret, and that without a terminal --interactive refuses
# (exit 2) instead of guessing. Transcripts are kept in $SB/ui_*.txt for the run log.
T_NAME=sync-ui
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
cat >"$SB/ptydrive.py" <<'PY'
# usage: ptydrive.py TRANSCRIPT ANSWERS(comma list of y/n) -- ARGV...   prints the child's exit code
import os, pty, sys, time, select
out, answers, argv = sys.argv[1], sys.argv[2].split(","), sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
buf, sent, deadline, st = b"", 0, time.time() + 120, None
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if buf.count(b"[y/N]") > sent and sent < len(answers):
            os.write(fd, (answers[sent] + "\n").encode()); sent += 1
    else:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            st = status
            break
else:
    os.kill(pid, 9)
if st is None:
    st = os.waitpid(pid, 0)[1]
open(out, "wb").write(buf)
print(os.waitstatus_to_exitcode(st))
PY
drive() { # drive NAME ANSWERS ENGINE-ARGS... -> UI_RC, UI_T (transcript)
  local name="$1" ans="$2"; shift 2
  UI_RC="$(PATH="$SB/shim:$PATH" python3 -I "$SB/ptydrive.py" "$SB/ui_$name.txt" "$ans" -- bash "$SX_ENGINE" "$@" 2>/dev/null)"
  UI_T="$(tr -d '\r' <"$SB/ui_$name.txt")"
}
sx_std_tree
sx_commit "$U_ROOT" "r1"; sx_commit "$U_A" "a1"
git -C "$W" remote add leaky "https://bob:ghp_UITESTONLYsecretsecretsecretsecret00@127.0.0.1:9/x.git"
before="$(sx_head "$W")"

# 1. "no" to fetching: nothing fetched, nothing changed
: >"$SB/git_calls.log"
drive no n --apply --interactive --root "$W" --out "$SB/out/ui1" --timeout 10
has "prompt 1 shows the scope" "repositories (4 initialised)" "$UI_T"
has "prompt 1 asks before fetching" "Fetch every remote of the 4 initialised repositories now? [y/N]" "$UI_T"
eq "no: zero fetch calls" "0" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"
eq "no: nothing changed" "$before" "$(sx_head "$W")"
eq "no: consent recorded as interactive" "interactive False" "$(SX_JSON="$SB/out/ui1/sync_report.json"; sx_q 'r["consent_source"]+" "+str(r["consent"]["fetch"])')"

# 1b. a bare Enter is "no" (the default shown as [y/N])
: >"$SB/git_calls.log"
drive enter "" --check --interactive --root "$W" --out "$SB/out/ui1b" --timeout 10
eq "enter: zero fetch calls" "0" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"

# 2. "yes" to fetch, "no" to integrate: fetched, not changed, exit 3 (updates still available)
git -C "$W" remote remove leaky
drive yes-no y,n --apply --interactive --root "$W" --out "$SB/out/ui2"
has "prompt 2 asks before fast-forwarding" "Fast-forward 1 repositories on main" "$UI_T"
eq "yes-no: exit 3" 3 "$UI_RC"
eq "yes-no: nothing changed" "$before" "$(sx_head "$W")"
has "yes-no: verdict shown on the terminal" "UPDATES-AVAILABLE (exit 3)" "$UI_T"

# 3. "yes" to everything with --advance-pins: integrated and staged
drive yes y,y,y --apply --interactive --advance-pins --root "$W" --out "$SB/out/ui3"
has "prompt 3 asks before staging pins" "Stage 1 submodule pin advances (git add, never committed)? [y/N]" "$UI_T"
eq "yes: exit 0" 0 "$UI_RC"
eq "yes: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "yes: libs/a advanced" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
hasnt "transcripts never show the token" "UITESTONLY" "$(cat "$SB"/ui_*.txt)"
hasnt "transcripts never show userinfo" "bob:" "$(cat "$SB"/ui_*.txt)"

# 4. a check with --interactive asks only about fetching (nothing to integrate)
drive check y --check --interactive --root "$W" --out "$SB/out/ui4"
eq "check: exactly one prompt" "1" "$(grep -o '\[y/N\]' <<<"$UI_T" | wc -l | tr -d ' ')"
# the pin step 3 staged is not committed yet: a check reports it as attention (RV4-2: a staged gitlink is never
# silent, and a later --advance-pins never replaces it), until the user commits it
eq "check: exit 4 (the staged pin is attention)" 4 "$UI_RC"
eq "check: the only reason is the staged pin" "gitlink-staged:libs/a" "$(python3 -I -c 'import json,sys;print(",".join(r for x in json.load(open(sys.argv[1]))["repos"] for r in x.get("reasons", [])))' "$SB/out/ui4/sync_report.json")"
# the user commits the staged pin and pushes it (the documented next step after --advance-pins)
git -C "$W" commit -q -m "pin libs/a" && git -C "$W" push -q origin main
drive check2 y --check --interactive --root "$W" --out "$SB/out/ui4a"
eq "check after commit: exit 0 (current)" 0 "$UI_RC"

# 4b. pins consented, nothing to fast-forward (so no fast-forward prompt): the advanced submodule's clean
#     nested children follow its new recorded gitlink, as they do non-interactively (consent = the pin answer)
#     X = inner commit liba now records; Y = a later inner commit liba does not record. A child that follows
#     keeps its parent's new recorded pin (X), exactly as the non-interactive --apply --advance-pins does.
sx_commit "$U_IN" "in2"; sx_bump_pin "$U_A" inner; sx_commit "$U_IN" "in3"
X="$(git --git-dir="$SB/remotes/HelixDevelopment/liba.git" ls-tree main inner | awk '{print $3}')"
Y="$(sx_remote_head "$SB/remotes/HelixDevelopment/inner.git")"
eq "pins-only: fixture premise X != Y" "1" "$([ -n "$X" ] && [ "$X" != "$Y" ] && echo 1)"
drive pins-only y,y --apply --interactive --advance-pins --root "$W" --out "$SB/out/ui4b"
hasnt "pins-only: no fast-forward prompt (nothing behind on main)" "Fast-forward" "$UI_T"
eq "pins-only: libs/a advanced" "$(sx_remote_head "$SB/remotes/HelixDevelopment/liba.git")" "$(sx_head "$W/libs/a")"
eq "pins-only: libs/a/inner followed liba's new pin (X), not upstream main (Y)" "$X" "$(sx_head "$W/libs/a/inner")"

# 5. no terminal: --interactive refuses
o="$(setsid -w bash "$SX_ENGINE" --check --interactive --root "$W" --out "$SB/out/ui5" </dev/null 2>&1)"; rc=$?
eq "no terminal: exit 2" 2 "$rc"
has "no terminal: says why" "needs a terminal" "$o"
finish
