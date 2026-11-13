#!/usr/bin/env bash
# tests/sync/test_hardening.sh -- SECURITY / DATA-SAFETY tests added in review round 3, each on EVERY path of its class:
#   1. no hook of the repository runs on ANY write path (fast-forward, follow, advance-pin): default .git/hooks AND a
#      tracked hooks dir selected by core.hooksPath, with no global core.hooksPath in the fixture (I-2 / K04, n-4)
#   2. an ignored local file is never overwritten on ANY write path: fast-forward, follow, advance-pin (I-3)
#   3. the tree status is re-read right before every write; a status that does not answer is never "clean" (I-3 / K11)
#   4. git's error text is redacted before it reaches the report (K12): a token in a remote URL PATH
#   5. GIT_CONFIG_PARAMETERS / GIT_CONFIG_COUNT from the environment never reach git (K16)
#   6. credential shapes in remote URLs and remote NAMES never reach any output (S-1, n-2)
#   7. --out never overwrites a user's file or follows a symlink (n-3)
#   8. a root with no remote, or whose remotes have no main, is never CURRENT (m-2)
#   9. a --tags fetch that meets a moved upstream tag is "tag-rejected", not "unreachable" (m-4)
#  10. a gitlink staged by someone else during an interactive run with every consent declined is never followed,
#      and a parent that did not move makes no child follow (M37, M37b)
#  11. SYNC_STEP_EXTRA_ARGS accepts only "--out /dir"
#  12. the install fixture's partial-clone guard never fails open (F4)
#  13. no early-exit pipe under pipefail in any shell file of this vehicle (class F)
#  14. the parent's index is read again right before a pin is staged (I-3 / M67)
#  15. an --out file is reused only when it is a regular file: a link to a report of ours, a FIFO (n-3 / M70)
# Real git against real bare repositories in a sandbox; the only network-shaped calls go to 127.0.0.1:9 (the
# discard port: refused at once, nothing is sent anywhere); $HOME untouched.
T_NAME=sync-hardening
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
GH='gh''p_'   # assembled, so this file never holds a token-shaped literal
# fresh: a new fixture world inside the SAME sandbox (one sandbox, one cleanup trap)
fresh() { safe_rm_rf "${SB:?}/remotes" "${SB:?}/work" "${SB:?}/seed"; mkdir -p "$SB/remotes" "$SB/work" "$SB/seed"; }

# ── 1. hooks: every write path, default hooks dir + tracked hooksPath, no global hooksPath
sx_std_tree
plant() { # plant GITDIR TAG
  mkdir -p "$1/hooks"
  for h in post-merge post-checkout reference-transaction pre-merge-commit post-index-change; do
    printf '#!/bin/sh\necho "%s-%s" >>"%s/RAN"\ncat >/dev/null 2>&1\nexit 0\n' "$2" "$h" "$SB" >"$1/hooks/$h"; chmod +x "$1/hooks/$h"
  done; }
for p in . libs/a vendor/t; do plant "$(git -C "$W/$p" rev-parse --absolute-git-dir)" "default-$p"; done
mkdir -p "$SB/tracked/hooks"; plant "$SB/tracked" tracked
for p in . libs/a vendor/t; do git -C "$W/$p" config core.hooksPath "$SB/tracked/hooks"; done
: >"$SB/RAN"; git -C "$W/libs/a" checkout -q --detach HEAD
has "hooks: control needle: a plain git checkout DOES run a hook here" "post-checkout" "$(cat "$SB/RAN")"
: >"$SB/RAN"
sx_commit "$U_A" "a1"; sx_bump_pin "$U_ROOT" libs/a; sx_commit "$U_T" "t1"
sx_run --apply --advance-pins --advance-third-party --root "$W"
eq "hooks: --apply over ff + follow + advance-pin: exit 0" 0 "$SX_RC"
eq "hooks: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
eq "hooks: libs/a followed" "$(git -C "$W" ls-tree HEAD libs/a | awk '{print $3}')" "$(sx_head "$W/libs/a")"
eq "hooks: vendor/t advanced" "$(sx_remote_head "$SB/remotes/thirdparty/tlib.git")" "$(sx_head "$W/vendor/t")"
eq "hooks: no hook ran on any write path" "" "$(cat "$SB/RAN")"

# ── 2. ignored files: every write path
ign_tree() { # a fresh tree; libs/a and root ignore secret.env; the next upstream commits track it
  fresh; sx_std_tree
  wa="$(sx_seed "$U_A")"; printf 'secret.env\n' >"$wa/.gitignore"; git -C "$wa" add .gitignore; git -C "$wa" commit -q -m ign
  git -C "$wa" push -q origin main
  git -C "$W/libs/a" fetch -q origin; git -C "$W/libs/a" checkout -q --detach origin/main
  git -C "$W" add libs/a; git -C "$W" commit -q -m "pin with .gitignore"; git -C "$W" push -q origin main
  echo LOCAL-SECRET >"$W/libs/a/secret.env"
  echo upstream >"$wa/secret.env"; git -C "$wa" add -f secret.env; git -C "$wa" commit -q -m "track secret.env"; git -C "$wa" push -q origin main
}
ign_tree; sx_bump_pin "$U_ROOT" libs/a
a_before="$(sx_head "$W/libs/a")"
sx_run --apply --root "$W"
eq "ignored, follow path: libs/a not moved" "$a_before" "$(sx_head "$W/libs/a")"
eq "ignored, follow path: local file kept" "LOCAL-SECRET" "$(cat "$W/libs/a/secret.env")"
has "ignored, follow path: reason recorded" "ignored-file-would-be-overwritten" "$(sx_q 'str(P["libs/a"]["actions"])')"
eq "ignored, follow path: ATTENTION exit 4" 4 "$SX_RC"
ign_tree
sx_run --apply --advance-pins --root "$W"
eq "ignored, advance-pin path: libs/a not moved" "$a_before" "$(sx_head "$W/libs/a")"
eq "ignored, advance-pin path: local file kept" "LOCAL-SECRET" "$(cat "$W/libs/a/secret.env")"
eq "ignored, advance-pin path: nothing staged in the root" "" "$(git -C "$W" diff --cached --name-only)"
has "ignored, advance-pin path: reason recorded" "ignored-file-would-be-overwritten" "$(sx_q 'str(P["libs/a"]["actions"])')"
ign_tree
wr="$(sx_seed "$U_ROOT")"; printf 'secret.env\n' >"$wr/.gitignore"; git -C "$wr" add .gitignore; git -C "$wr" commit -q -m ign
git -C "$wr" push -q origin main; git -C "$W" pull -q --ff-only origin main
echo ROOT-SECRET >"$W/secret.env"; r_before="$(sx_head "$W")"
echo upstream >"$wr/secret.env"; git -C "$wr" add -f secret.env; git -C "$wr" commit -q -m "track root secret"; git -C "$wr" push -q origin main
sx_run --apply --root "$W"
eq "ignored, fast-forward path: root not moved" "$r_before" "$(sx_head "$W")"
eq "ignored, fast-forward path: local file kept" "ROOT-SECRET" "$(cat "$W/secret.env")"
has "ignored, fast-forward path: reason recorded" "ignored-file-would-be-overwritten" "$(sx_q 'str(P["."]["actions"])')"

# ── 3. status re-read before the write; a status re-read that does not answer is never "clean"
fresh; sx_std_tree; sx_commit "$U_ROOT" "s1"; r_before="$(sx_head "$W")"
mkdir -p "$SB/st"
cat >"$SB/st/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" --no-optional-locks status "*)
  n=\$(( \$(cat "$SB/st.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$SB/st.n"
  [ "\$2" = "$W" ] && [ "\$n" -gt "\${ST_AFTER:-99}" ] && { [ "\${ST_MODE:-}" = dirty ] && echo x >>"$W/README"; [ "\${ST_MODE:-}" = kill ] && kill -9 \$\$
    [ "\${ST_MODE:-}" = rc128 ] && { echo "fatal: injected exit 128" >&2; exit 128; }; } ;;
esac
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/st/git"
st_run() { rm -f "$SB/st.n"; SX_N=$((SX_N+1)); local o="$SB/out/r$SX_N"
  SX_OUT="$(PATH="$SB/st:$PATH" bash "$SX_ENGINE" --apply --jobs 1 --root "$W" --out "$o" --run-id "r$SX_N" 2>"$o.err")"; SX_RC=$?
  SX_JSON="$o/sync_report.json"; }
# the root's FIRST status is the inspect read (call 1 of 4 repositories in pre-order); kill every later root status
ST_AFTER=4 ST_MODE=kill st_run
eq "status re-read killed: root not moved" "$r_before" "$(sx_head "$W")"
eq "status re-read killed: BLIND exit 6" 6 "$SX_RC"
has "status re-read killed: action names it" "unresolved:status-recheck" "$(sx_q 'str(P["."]["actions"])')"
# the REAL status 128 at the re-read (review round 3, F8 / X01: a test that injected only an undeclared 77 could not
# tell a re-read that accepts 128 from one that does not; git really exits 128, for example on a corrupt index)
ST_AFTER=4 ST_MODE=rc128 st_run
eq "status re-read exit 128: root not moved" "$r_before" "$(sx_head "$W")"
eq "status re-read exit 128: BLIND exit 6" 6 "$SX_RC"
has "status re-read exit 128: action names it" "unresolved:status-recheck" "$(sx_q 'str(P["."]["actions"])')"
eq "status re-read exit 128: the repository is blind" blind "$(sx_q 'P["."]["result"]')"
ST_AFTER=4 ST_MODE=dirty st_run
eq "tree changed before the write: root not moved" "$r_before" "$(sx_head "$W")"
has "tree changed before the write: blocked" "blocked:tree-changed-before-write" "$(sx_q 'str(P["."]["actions"])')"
eq "tree changed before the write: the user's edit is kept" "x" "$(tail -1 "$W/README")"
git -C "$W" checkout -q -- README
ST_MODE=none st_run
eq "status control needle: without the fault the root fast-forwards" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
# the inspect status itself: no answer -> dirty AND unresolved (both block), never clean
sx_commit "$U_ROOT" "s2"; r_before="$(sx_head "$W")"
ST_AFTER=0 ST_MODE=kill st_run
eq "inspect status killed: root not moved" "$r_before" "$(sx_head "$W")"
has "inspect status killed: dirty-tree (an unread status is never clean)" "dirty-tree" "$(sx_q 'P["."]["reasons"]')"

# ── 4. K12: git's error repeats a token-shaped URL path; it is redacted at the field, the backstop finds nothing
fresh; U="$(sx_bare HelixDevelopment solo)"; W="$SB/work/solo"; sx_clone "$U" "$W"
git -C "$W" remote add bad "https://127.0.0.1:9/${GH}TOKENSHAPEabcdefghijkl012345/x.git"
sx_run --check --timeout 15 --root "$W"
all="$SX_OUT$SX_ERR$(cat "$SX_JSON" "$SX_TSV")"
hasnt "token in URL path: absent from every output" "${GH}TOKENSHAPE" "$all"
eq "token in URL path: the field itself was redacted (backstop found nothing)" "[]" "$(sx_q 'r["redaction_backstop"]')"
has "token in URL path: remote reported unreachable" "unreachable:bad" "$(sx_q 'P["."]["reasons"]')"
git -C "$W" remote remove bad

# ── 5. K16: config injection through the environment never reaches git
GIT_CONFIG_PARAMETERS="'core.sshCommand'='false injected'" sx_run --check --no-fetch --root "$W"
eq "GIT_CONFIG_PARAMETERS: dropped (no core.sshCommand seen)" "engine-default" "$(sx_q 'P["."]["ssh"]')"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.sshCommand GIT_CONFIG_VALUE_0="false injected" sx_run --check --no-fetch --root "$W"
eq "GIT_CONFIG_COUNT/KEY/VALUE: dropped" "engine-default" "$(sx_q 'P["."]["ssh"]')"
git -C "$W" config core.sshCommand "ssh -o BatchMode=yes"
sx_run --check --no-fetch --root "$W"
eq "control needle: a real repository core.sshCommand IS seen" "core.sshCommand" "$(sx_q 'P["."]["ssh"]')"
git -C "$W" config --unset core.sshCommand

# ── 6. S-1 / n-2: credential shapes in URLs and remote names
PW1='Xq9pwd@Zz7mark'; PW2='spa cepw0rdmark'; TN="${GH}ABCDEFGHIJKLMNOPQRSTUVWX"
git -C "$W" remote add d1 "https://deploy:${PW1}@127.0.0.1:9/a.git"
git -C "$W" remote add d2 "https://deploy:${PW2}@127.0.0.1:9/b.git"
git -C "$W" remote add d3 "https://u:a@b@c@127.0.0.1:9/c.git"
git -C "$W" remote add "$TN" "https://127.0.0.1:9/n.git"
sx_run --check --timeout 15 --root "$W"
all="$SX_OUT$SX_ERR$(cat "$SX_JSON" "$SX_TSV")"
for s in Xq9pwd Zz7mark cepw0rdmark "spa cepw" "a@b@c" "$TN"; do hasnt "credential shapes: '$s' absent" "$s" "$all"; done
eq "credential shapes: backstop found nothing" "[]" "$(sx_q 'r["redaction_backstop"]')"
has "credential shapes: the token-named remote is still fetched (by its real name)" "unreachable:[REDACTED]" "$(sx_q 'P["."]["reasons"]')"
for c in d1 d2 d3 "$TN"; do git -C "$W" remote remove "$c"; done

# ── 7. n-3: --out never overwrites a user's file and never follows a symlink
mkdir -p "$SB/userdir"; echo "MY OWN NOTES" >"$SB/userdir/sync_report.json"
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/userdir" 2>&1)"; rc=$?
eq "--out with a user's file: usage exit 2" 2 "$rc"
eq "--out with a user's file: file untouched" "MY OWN NOTES" "$(cat "$SB/userdir/sync_report.json")"
mkdir -p "$SB/userdir2"; echo victim >"$SB/victim"; ln -s "$SB/victim" "$SB/userdir2/sync_report.tsv"
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/userdir2" 2>&1)"; rc=$?
eq "--out with a symlinked tsv: usage exit 2" 2 "$rc"
eq "--out with a symlinked tsv: target untouched" "victim" "$(cat "$SB/victim")"
eq "--out with a symlinked tsv: still a symlink" "yes" "$([ -L "$SB/userdir2/sync_report.tsv" ] && echo yes || echo no)"
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/userdir3" 2>&1)"; rc=$?
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/userdir3" 2>&1)"; rc=$?
eq "--out control: a second run over our own report is allowed" 0 "$rc"

# ── 8. m-2: no remote / no remote main is never CURRENT
fresh; mkdir -p "$SB/work/lone"; W="$SB/work/lone"; git init -q "$W"; echo x >"$W/f"; git -C "$W" add f; git -C "$W" commit -q -m one
sx_run --check --root "$W"
eq "no remote: ATTENTION exit 4, never CURRENT" 4 "$SX_RC"
has "no remote: reason no-upstream-main" "no-upstream-main" "$(sx_q 'P["."]["reasons"]')"
U="$(sx_bare HelixDevelopment other)"; git -C "$W" remote add origin "$U"
git -C "$SB/remotes/HelixDevelopment/other.git" branch -m main trunk
sx_run --check --root "$W"
eq "remote without main: ATTENTION exit 4" 4 "$SX_RC"
has "remote without main: reason no-upstream-main" "no-upstream-main" "$(sx_q 'P["."]["reasons"]')"
git -C "$SB/remotes/HelixDevelopment/other.git" branch -m trunk main

# ── 9. m-4: a moved upstream tag under --tags
fresh; U="$(sx_bare HelixDevelopment tagged)"; W="$SB/work/tagged"; sx_clone "$U" "$W"
wt="$(sx_seed "$U")"; git -C "$wt" tag v1; git -C "$wt" push -q origin v1
git -C "$W" fetch -q --tags origin; local_tag="$(git -C "$W" rev-parse v1)"
sx_commit "$U" "t1"; git -C "$wt" tag -f v1 >/dev/null; git -C "$wt" push -q -f origin v1
sx_run --check --tags --root "$W"
eq "moved tag: remote fetch state tag-rejected (the remote answered)" "tag-rejected" "$(sx_q '[x["fetch"] for x in P["."]["remotes"]][0]')"
has "moved tag: reason tag-rejected:origin" "tag-rejected:origin" "$(sx_q 'P["."]["reasons"]')"
hasnt "moved tag: never labelled unreachable" "unreachable" "$(sx_q 'P["."]["reasons"]')"
eq "moved tag: the branch was still fetched and evaluated (behind 1)" "1" "$(sx_q 'P["."]["behind_target"]')"
eq "moved tag: local tag kept (never forced)" "$local_tag" "$(git -C "$W" rev-parse v1)"
eq "moved tag: ATTENTION exit 4" 4 "$SX_RC"
sx_run --apply --tags --root "$W"
eq "moved tag, --apply: integration blocked (exit 4), nothing moved" "4 $local_tag" "$SX_RC $(git -C "$W" rev-parse v1)"

# ── 10. M37 / M37b: no follow without a move of the parent in this run
fresh; sx_std_tree
sx_commit "$U_A" "liba next"; git -C "$W/libs/a" fetch -q origin
new="$(git -C "$W/libs/a" rev-parse origin/main)"; old="$(git -C "$W/libs/a" rev-parse HEAD)"
mkdir -p "$SB/bad"
cat >"$SB/bad/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" -C $W "*" ls-files -s -z "*) n=\$(cat "$SB/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n >"$SB/n"
  [ \$n -eq 1 ] && "$SX_GIT" -C "$W" update-index --cacheinfo "160000,$new,libs/a" ;; esac
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/bad/git"
cat >"$SB/drive.py" <<'PY'
# pty driver: run argv under a controlling terminal, answer "n" to every prompt, print the output
import os, pty, sys, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
buf, t0 = b"", time.monotonic()
while time.monotonic() - t0 < 60:
    r, _, _ = select.select([fd], [], [], 0.5)
    if not r:
        continue
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    if buf.rstrip().endswith(b"]"):
        os.write(fd, b"n\n"); buf += b"<<n>>"
_, st = os.waitpid(pid, 0)
print(buf.decode("utf-8", "replace"))
print("DRIVER exit", os.waitstatus_to_exitcode(st))
PY
# the concurrent writer stages the new gitlink right after discovery read the index (call 1)
PATH="$SB/bad:$PATH" timeout 120 python3 -I "$SB/drive.py" bash "$SX_ENGINE" --apply --interactive --root "$W" --out "$SB/out/m37" \
  >"$SB/m37.txt" 2>&1
SX_JSON="$SB/out/m37/sync_report.json"
eq "M37: the concurrent staging happened (control needle)" "$new" "$(git -C "$W" ls-files -s libs/a | awk '{print $2}')"
eq "M37: libs/a never checked out at the staged gitlink" "$old" "$(sx_head "$W/libs/a")"
eq "M37b: a root that did not move makes no child follow (no follow action at all)" "[]" \
  "$(sx_q '[a for a in P["libs/a"]["actions"] if "follow" in str(a)]')"
git -C "$W" update-index --cacheinfo "160000,$old,libs/a"
# M37b, second shape: a gitlink the user staged BEFORE the run (index != HEAD's tree); the root is not behind
git -C "$W" update-index --cacheinfo "160000,$new,libs/a"
sx_run --apply --root "$W"
eq "M37b: pre-staged gitlink, root not moved: no follow action for libs/a" "[]" \
  "$(sx_q '[a for a in P["libs/a"]["actions"] if "follow" in str(a)]')"
eq "M37b: libs/a not moved" "$old" "$(sx_head "$W/libs/a")"
git -C "$W" update-index --cacheinfo "160000,$old,libs/a"

# ── 11. SYNC_STEP_EXTRA_ARGS accepts only --out /dir
. "$SX_REPO/scripts/sync/sync_step_lib.sh"
sx_commit "$U_ROOT" "x"; r_before="$(sx_head "$W")"
o="$(SYNC_STEP_EXTRA_ARGS="--apply" sync_step check "$W" "$SX_ENGINE" 2>&1)"
has "extra args: anything but --out is ignored, with a note" "SYNC_STEP_EXTRA_ARGS ignored" "$o"
eq "extra args: --apply smuggled into a check never moved the root" "$r_before" "$(sx_head "$W")"
o="$(SYNC_STEP_EXTRA_ARGS="--out $SB/out/xa" sync_step check "$W" "$SX_ENGINE" 2>&1)"
eq "extra args: --out /dir is honoured" "yes" "$([ -f "$SB/out/xa/sync_report.json" ] && echo yes || echo no)"

# ── 12. F4 (review round 3, host safety): the install fixture's partial-clone guard never fails open.
#    tests/install/lib.sh is sourced in a SUBSHELL (its helpers and exports stay there). The round-3 guard piped the
#    config into `grep -q` under pipefail: on a large config whose match is near the top, grep exits early, the
#    pipe returns 141 and the `||` read it as "not partial" (fail-open). The input below triggers exactly that.
LIBSH="$SX_REPO/tests/install/lib.sh"
PC_RE='(\.partialclonefilter |^extensions\.partialclone |\.promisor true$)'
pr_case() { # pr_case WANT LABEL LINES -> _partial_refused LINES gives WANT (refuse/accept)
  local got
  # shellcheck disable=SC1090  # LIBSH is tests/install/lib.sh (set above), sourced in a subshell
  got="$( . "$LIBSH" >/dev/null 2>&1; if _partial_refused "$3"; then echo refuse; else echo accept; fi )"
  eq "partial guard: $2" "$1" "$got"; }
pr_case accept "no config line" ""
pr_case accept "promisor false" "remote.origin.promisor false"
pr_case accept "promisor with an empty value (git reads it as false), a remote name with a space" "remote.P Q.promisor "
pr_case accept "no / OFF / 0" $'remote.a.promisor no\nremote.b.promisor OFF\nremote.c.promisor 0'
pr_case refuse "value-less promisor (a boolean true)" "remote.o.promisor"
pr_case refuse "promisor true" "remote.o.promisor true"
pr_case refuse "promisor Yes (the round-3 pattern missed it)" "remote.o.promisor Yes"
pr_case refuse "promisor 1" "remote.o.promisor 1"
pr_case refuse "promisor on" "remote.o.promisor on"
pr_case refuse "partialclonefilter" "remote.o.partialclonefilter blob:none"
pr_case refuse "value-less partialclonefilter" "remote.o.partialclonefilter"
pr_case refuse "extensions.partialclone" "extensions.partialclone origin"
pr_case refuse "mixed-case extensions.partialClone" "Extensions.PartialClone origin"
pr_case refuse "a later promisor true after a false" $'remote.a.promisor false\nremote.b.promisor true'
pr_case refuse "a line it cannot read" "garbage line"
big="extensions.partialclone origin"; i=0; while [ "$i" -lt 8000 ]; do big+=$'\n'"remote.r$i.promisor false"; i=$((i+1)); done
big2=""; i=0; while [ "$i" -lt 8000 ]; do big2+="remote.r$i.promisor false"$'\n'; i=$((i+1)); done
pr_case refuse "large input, the match on line 1 (the fail-open shape)" "$big"
pr_case refuse "large input, the match on the last line" "${big2}remote.z.promisor true"
pr_case accept "large input, nothing partial (golden false)" "${big2%$'\n'}"
# control needle: on this very input the round-3 pipeline really returns 141 here (else the case proves nothing)
old_rc="$( set -o pipefail; printf '%s\n' "$big" | grep -Eqi "$PC_RE"; echo "$?" )"  # pipelint:allow control needle
eq "partial guard: control needle: the round-3 pipeline returns 141 on the large input" 141 "$old_rc"
# the whole guard, with a stub git (function) that prints a config and exits with a chosen status
printf '%s\n' "$big" >"$SB/pc_cfg"
rs_case() { # rs_case WANT LABEL [SHALLOW] [REVPARSE_RC] [CONFIG_RC]
  local got sh_v="${3:-false}" rp_rc="${4:-0}" cf_rc="${5:-0}"
  # shellcheck disable=SC1090  # LIBSH is tests/install/lib.sh (set above), sourced in a subshell
  got="$( . "$LIBSH" >/dev/null 2>&1
    git() { case "$*" in
      *is-shallow-repository*) echo "$sh_v"; return "$rp_rc" ;;
      *get-regexp*) cat "$SB/pc_cfg"; return "$cf_rc" ;;
      *) return 1 ;; esac; }
    if _refuse_shallow /nonexistent fixture 2>/dev/null; then echo accept; else echo refuse; fi )"
  eq "partial guard, _refuse_shallow: $2" "$1" "$got"; }
rs_case refuse "large partial config"
printf '%s' "${big2%$'\n'}" >"$SB/pc_cfg"
rs_case accept "large config, nothing partial (golden false)"
rs_case refuse "config read exits 3 (cannot read it)" false 0 3
rs_case refuse "shallow source" true
rs_case refuse "rev-parse fails" false 128
# stress: six guards at once on large partial inputs, all refuse
printf '%s\n' "$big" >"$SB/pc_cfg"
for k in 1 2 3 4 5 6; do rs_case_out="$SB/pc_par_$k"; ( rs_case refuse "parallel $k" >"$rs_case_out" ) & done; wait
par="$(cat "$SB"/pc_par_*)"
hasnt "partial guard: six parallel guards on a large partial config: none accepted" "FAIL" "$par"
eq "partial guard: six parallel guards ran" 6 "$(grep -c '^  ok ' <<<"$par")"
# real repositories, real git: a plain clone is accepted, a partial-clone configuration is refused
fresh; sx_std_tree
# shellcheck disable=SC1090  # LIBSH is tests/install/lib.sh (set above), sourced in a subshell
pr_real="$( . "$LIBSH" >/dev/null 2>&1; _refuse_shallow "$W" plain >/dev/null 2>&1 && echo accept || echo refuse )"
eq "partial guard, real repository: a full clone is accepted" accept "$pr_real"
git -C "$W/vendor/t" config remote.origin.promisor true
git -C "$W/vendor/t" config remote.origin.partialclonefilter blob:none
# shellcheck disable=SC1090  # LIBSH is tests/install/lib.sh (set above), sourced in a subshell
pr_real="$( . "$LIBSH" >/dev/null 2>&1; _refuse_shallow "$W/vendor/t" partial >/dev/null 2>&1 && echo accept || echo refuse )"
eq "partial guard, real repository: a partial-clone configuration is refused" refuse "$pr_real"

# ── 13. class F: no early-exit pipe under pipefail in any shell file of this vehicle. A reader that can stop
#    before its producer is done (grep -q / -m / -l / -L / --quiet / --max-count, head, sed ...q, awk ...exit,
#    read) makes the pipeline return 141 under pipefail, which an `if` or `||` reads as "no match".
cat >"$SB/pipelint.py" <<'PY'
import re
import shlex
import sys
GREP_LONG = ("quiet", "silent", "max-count", "files-with-matches", "files-without-match")
GREP_LONG_ARG = ("regexp", "file", "after-context", "before-context", "context", "directories", "devices",
                 "label", "binary-files", "include", "exclude", "exclude-from", "exclude-dir", "color", "colour")


def scan(line):
    """Yield (start of stage) for every pipe character that is shell syntax: not inside single or double quotes
    (a pipe inside a double-quoted $( ) IS syntax), not part of || or |&, not in a comment."""
    st, i = [], 0
    while i < len(line):
        c, top = line[i], (st[-1] if st else "")
        if top == "'":
            if c == "'":
                st.pop()
        elif top == '"':
            if c == "\\":
                i += 1
            elif c == '"':
                st.pop()
            elif c == "$" and line[i + 1:i + 2] == "(":
                st.append("(")
                i += 1
            elif c == "`":
                st.append("`")
        else:
            if c == "\\":
                i += 1
            elif c in "'\"":
                st.append(c)
            elif c == "`":
                st.pop() if top == "`" else st.append("`")
            elif c == "(":
                st.append("(")
            elif c == ")":
                if top == "(":
                    st.pop()
            elif c == "#" and (i == 0 or line[i - 1] in " \t;"):
                return
            elif c == "|":
                if line[i + 1:i + 2] in ("|", "&"):
                    i += 2
                    continue
                yield i + 1
        i += 1


def segment(line, start):
    """The text of ONE pipeline stage, from START to the first | ; & ) at its own level, outside quotes."""
    st, i = [], start
    while i < len(line):
        c, top = line[i], (st[-1] if st else "")
        if top == "'":
            if c == "'":
                st.pop()
        elif top == '"':
            if c == "\\":
                i += 1
            elif c == '"':
                st.pop()
            elif c == "$" and line[i + 1:i + 2] == "(":
                st.append("(")
                i += 1
        else:
            if c == "\\":
                i += 1
            elif c in "'\"":
                st.append(c)
            elif c == "(":
                st.append("(")
            elif c == ")" and top == "(":
                st.pop()
            elif not st and c in "|;&)":
                return line[start:i]
        i += 1
    return line[start:]


def grep_stops_early(words):
    skip = False
    for t in words:
        if skip:
            skip = False
            continue
        if t == "--":
            return False
        if t.startswith("--"):
            name = t[2:].split("=", 1)[0]
            if name in GREP_LONG:
                return True
            skip = name in GREP_LONG_ARG and "=" not in t
            continue
        if t.startswith("-") and len(t) > 1:
            for k, c in enumerate(t[1:]):
                if c in "qlLm":
                    return True
                if c in "efABCdD":
                    skip = k == len(t) - 2
                    break
    return False


def reader_stops_early(seg):
    try:
        words = shlex.split(seg)
    except ValueError:
        return True  # a stage it cannot read is never clean
    if not words:
        return False
    cmd, rest = words[0].rsplit("/", 1)[-1], words[1:]
    if cmd in ("grep", "egrep", "fgrep"):
        return grep_stops_early(rest)
    if cmd in ("head", "read"):
        return True
    if cmd == "sed":
        return any(re.search(r"(^|[;{}\s])[qQ]\b", w) for w in rest if not w.startswith("-"))
    if cmd == "awk":  # an exit inside END {} runs after all input was read: not early
        return any(re.search(r"\bexit\b", re.sub(r"\bEND\s*\{[^}]*\}", "", w)) for w in rest)
    return False


hits = 0
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read().replace("\\\n", " ")
    for n, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("#"):
            continue
        if not any(reader_stops_early(segment(line, k)) for k in scan(line)):
            continue
        if "pipelint:allow" in line:  # a deliberate pipeline (a control needle): listed, never silent
            print("ALLOWED %s:%d: %s" % (path.rsplit("/", 1)[-1], n, line.strip()[:100]))
            continue
        hits += 1
        print("%s:%d: %s" % (path, n, line.strip()[:120]))
print("HITS %d" % hits)
PY
# the positive fixture is written with a PIPE placeholder (so this file holds no such pipeline itself)
cat >"$SB/pipelint_pos.in" <<'EOF'
if printf x PIPE grep -q x; then :; fi
v="$(printf x PIPE head -1)"
printf x PIPE grep -m1 x >/dev/null
printf x PIPE sed -n '1p;q'
printf x PIPE awk '{exit}'
printf x PIPE read -r y
printf x \
  PIPE grep --quiet x
EOF
sed 's/PIPE/|/g' "$SB/pipelint_pos.in" >"$SB/pipelint_pos.sh"
cat >"$SB/pipelint_neg.sh" <<'EOF'
n="$(printf x | grep -c x)"
[ -n "$x" ] || echo y
# printf x | grep -q x
case "$x" in *y*) ;; esac
while IFS= read -r l; do :; done <<<"$x"
printf x | cut -c1
echo "a | head"
x="$(printf x | grep -c "$(echo -q)")"
printf x | awk '{f=1} END { exit !f }'
EOF
eq "pipe lint: positive control: every early-exit reader is found" "HITS 7" "$(python3 -I "$SB/pipelint.py" "$SB/pipelint_pos.sh" | tail -1)"
eq "pipe lint: negative control: nothing else is flagged" "HITS 0" "$(python3 -I "$SB/pipelint.py" "$SB/pipelint_neg.sh" | tail -1)"
vfiles=()
for f in scripts/sync/sync_all_upstreams.sh scripts/sync/sync_step_lib.sh scripts/sync/fixture_lib.sh \
         scripts/gates/cm_sync_upstreams_ff_only.sh scripts/gates/cm_sync_upstreams_ff_only_mutation_test.sh \
         scripts/setup.sh scripts/post_update_hook.sh tests/install/lib.sh tests/install/test_unit.sh; do
  [ -f "$SX_REPO/$f" ] && vfiles+=("$SX_REPO/$f") || nok "pipe lint: vehicle file $f missing"
done
for f in "$SX_REPO"/tests/sync/*.sh; do [ -f "$f" ] && vfiles+=("$f"); done
[ "${#vfiles[@]}" -ge 20 ] && ok "pipe lint: ${#vfiles[@]} shell files listed" || nok "pipe lint: only ${#vfiles[@]} shell files listed"
lint="$(python3 -I "$SB/pipelint.py" "${vfiles[@]}")"
eq "pipe lint: no early-exit pipe in the ${#vfiles[@]} shell files of this vehicle" "HITS 0" "$(tail -1 <<<"$lint")"
[ "$(tail -1 <<<"$lint")" = "HITS 0" ] || printf '%s\n' "$lint"
# exactly one deliberate pipeline is allowed: the control needle of section 12
eq "pipe lint: the only allowed pipeline is the section-12 control needle" "1 test_hardening.sh" \
  "$(grep -c '^ALLOWED' <<<"$lint") $(grep '^ALLOWED' <<<"$lint" | cut -d: -f1 | cut -d' ' -f2)"

# ── 14. I-3 / M67: the parent's index is read again right before a pin is staged. A gitlink someone else staged
#    after discovery read the index is never overwritten and the child is not checked out (found in round 4: no
#    suite killed M67 in round 3 or round 4 before this case, although the round-3 inventory said hardening did)
fresh; sx_std_tree
p_old="$(sx_head "$W/libs/a")"
sx_commit "$U_A" "liba 14a"; p_mid="$(sx_remote_head "${U_A#file://}")"     # what the concurrent writer stages
sx_commit "$U_A" "liba 14b"; p_new="$(sx_remote_head "${U_A#file://}")"     # upstream main: what --advance-pins wants
mkdir -p "$SB/pi"
cat >"$SB/pi/git" <<EOF
#!/usr/bin/env bash
# libs/a's 2nd status is the writer's re-read (its 1st is inspect): the parent's index changes there, after
# discovery and before the writer reads the index again
case " \$* " in *" --no-optional-locks status "*)
  if [ "\$2" = "$W/libs/a" ]; then
    n=\$(( \$(cat "$SB/pi.n" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"$SB/pi.n"
    if [ "\$n" -eq 2 ]; then "$SX_GIT" -C "$W" update-index --cacheinfo "160000,$p_mid,libs/a" && echo fired >"$SB/pi.fired"; fi
  fi ;;
esac
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/pi/git"
SX_N=$((SX_N+1)); o="$SB/out/r$SX_N"
SX_OUT="$(PATH="$SB/pi:$PATH" bash "$SX_ENGINE" --apply --advance-pins --jobs 1 --root "$W" --out "$o" --run-id "r$SX_N" 2>"$o.err")"
SX_RC=$?; SX_JSON="$o/sync_report.json"
read -r _ p_idx _ <<<"$("$SX_GIT" -C "$W" ls-files -s -- libs/a)"
eq "M67: the concurrent staging happened after discovery (control needle)" "fired" "$(cat "$SB/pi.fired" 2>/dev/null)"
eq "M67: libs/a not checked out at the new pin" "$p_old" "$(sx_head "$W/libs/a")"
eq "M67: the gitlink the other writer staged is kept" "$p_mid" "$p_idx"
has "M67: the writer names the changed index" "blocked:parent-index-changed" "$(sx_q 'str(P["libs/a"]["actions"])')"
# the current classification of a write a guard blocked: the repository stays "behind" (exit 3), as for the
# tree-changed block; whether a blocked write should be ATTENTION is an open item (round-4 evidence)
eq "M67: libs/a stays behind, exit 3" "3 behind" "$SX_RC $(sx_q 'P["libs/a"]["result"]')"
# control: the same world without the concurrent writer advances the pin and stages it (the case reaches the writer)
fresh; sx_std_tree
sx_commit "$U_A" "liba 14a"; sx_commit "$U_A" "liba 14b"; p_new="$(sx_remote_head "${U_A#file://}")"
sx_run --apply --advance-pins --jobs 1 --root "$W"
read -r _ p_idx _ <<<"$("$SX_GIT" -C "$W" ls-files -s -- libs/a)"
eq "M67 control: without the other writer libs/a is advanced" "$p_new" "$(sx_head "$W/libs/a")"
eq "M67 control: and its new gitlink is staged" "$p_new" "$p_idx"
eq "M67 control: exit 0" 0 "$SX_RC"

# ── 15. n-3 / M70: an --out file is reused only when it is a regular file. Section 7 links the tsv to a file whose
#    content the content check refuses anyway, so no suite tested the file-type check on its own (M70 survived in
#    round 3 and round 4 before this case). Here the link points at a report THIS engine wrote, of the same kind,
#    and a FIFO stands at the report path (opening a FIFO that has no writer never returns)
fresh; sx_std_tree
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/o15real" 2>&1)"; rc=$?
eq "M70: a real report to link to (exit 0)" 0 "$rc"
mkdir -p "$SB/o15a" "$SB/o15b"; cp "$SB/o15real/sync_report.json" "$SB/o15real.json.before"
ln -s "$SB/o15real/sync_report.json" "$SB/o15a/sync_report.json"
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/o15a" 2>&1)"; rc=$?
eq "M70: a symlink to a report of ours: usage exit 2" 2 "$rc"
has "M70: a symlink to a report of ours: named as not ours" "was not written by this engine" "$out"
eq "M70: the symlink is still a symlink" "yes" "$([ -L "$SB/o15a/sync_report.json" ] && echo yes || echo no)"
eq "M70: the report it points at is unchanged" "same" "$(cmp -s "$SB/o15real.json.before" "$SB/o15real/sync_report.json" && echo same || echo changed)"
mkfifo "$SB/o15b/sync_report.json"
out="$(PATH="$SB/shim:$PATH" timeout 120 bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/o15b" 2>&1)"; rc=$?
eq "M70: a FIFO at the report path: usage exit 2 (124 = the engine blocked on it)" 2 "$rc"
eq "M70: the FIFO is still a FIFO" "yes" "$([ -p "$SB/o15b/sync_report.json" ] && echo yes || echo no)"
# control: the same engine reuses the directory that holds the real report (a regular file it wrote)
out="$(PATH="$SB/shim:$PATH" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/o15real" 2>&1)"; rc=$?
eq "M70 control: a regular report of ours is reused (exit 0)" 0 "$rc"

finish
