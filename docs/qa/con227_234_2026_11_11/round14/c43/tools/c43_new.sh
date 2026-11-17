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
HERE=/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/fix227_r14.zTVh/repo/tests/release; ROOT=/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/fix227_r14.zTVh/repo
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
NP="$HERE/net_probe.py"
# jq-free reader of the probe's JSON: npq FILE EXPR (a python expression over d)
npq() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
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
[ -n "${KEEP:-}" ] && cp "$D/p43.json" "$KEEP" && cp "$D/p43b.json" "$KEEP.b" 2>/dev/null
echo "RESULT: pass=$pass fail=$fail"
