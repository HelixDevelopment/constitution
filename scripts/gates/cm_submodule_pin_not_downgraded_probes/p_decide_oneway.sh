#!/usr/bin/env bash
# p_decide_oneway.sh <gate>... : reviewer probe (round 7) for the fwd / back members of the decide line, with a gate-logic
# test double (§11.4.289(C)(2), the KV22 technique): a `git` wrapper first on PATH that kills ITSELF with SIGKILL (a real
# signal death, rc 137 to the caller; the shape of an OOM kill or a timeout) for exactly one `merge-base --is-ancestor X Y`
# pair and passes every other call to the real git. No real-git 2.53 shape gives a one-way rc outside {0,1} (both
# directions run the same code path); a one-way signal death is the input the two members exist for.
#   DOWNKILLBACK: base pin B, staged A (a true DOWNGRADE); kill (A,B) = the gate's back call -> fwd 1, back 137
#                 real: BLIND (2). A gate without the back member: WARN DIVERGED, exit 0 (fail-open on a downgrade).
#   FWDKILLFWD:   base pin B, staged C (a true FORWARD bump); kill (B,C) = the gate's fwd call -> fwd 137, back 1
#                 real: BLIND (2). A gate without the fwd member: WARN DIVERGED, exit 0 (wrong message, exit 0).
#   CTL:          no kill, staged A: FAIL (1) on every gate (the double passes calls through unchanged).
set -u
t="$(mktemp -d "${TMPDIR:?}/pdo.XXXXXX")"; [ -n "$t" ] && [ -d "$t" ] || exit 9
export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1; : >"$GIT_CONFIG_GLOBAL"   # HOME is NOT reassigned
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
rg="$(command -v git)"; mkdir -p "$t/bin"
cat >"$t/bin/git" <<W
#!/usr/bin/env bash
a="\$*"
if [ -n "\${KILLPAIR:-}" ] && [[ "\$a" == *"merge-base --is-ancestor \$KILLPAIR"* ]]; then kill -KILL \$\$; fi
exec "$rg" "\$@"
W
chmod +x "$t/bin/git"
fx() { local sb="$1/super/sub"; mkdir -p "$sb"; "$rg" init -q -b main "$sb"
  for c in A B C; do "$rg" -C "$sb" commit -q --allow-empty -m "$c"; done
  A=$("$rg" -C "$sb" rev-parse HEAD~2); B=$("$rg" -C "$sb" rev-parse HEAD~1); C=$("$rg" -C "$sb" rev-parse HEAD)
  "$rg" init -q -b main "$1/super"; "$rg" -C "$1/super" update-index --add --cacheinfo 160000,"$B",sub; "$rg" -C "$1/super" commit -q -m base; }
for g in "$@"; do
  o=""
  for mode in DOWNKILLBACK FWDKILLFWD CTL; do
    d="$(mktemp -d "$t/fx.XXXXXX")"; fx "$d"; r="$d/super"
    case $mode in
      DOWNKILLBACK) "$rg" -C "$r" update-index --cacheinfo 160000,"$A",sub; kp="$A $B" ;;
      FWDKILLFWD)   "$rg" -C "$r" update-index --cacheinfo 160000,"$C",sub; kp="$B $C" ;;
      CTL)          "$rg" -C "$r" update-index --cacheinfo 160000,"$A",sub; kp="" ;;
    esac
    env PATH="$t/bin:$PATH" KILLPAIR="$kp" bash "$g" --root "$r" >"$t/out" 2>&1; rc=$?
    o+="$mode=$rc/$(grep -c ': FAIL' "$t/out")/$(grep -c 'WARN' "$t/out")/$(grep -c 'cannot be decided' "$t/out") "
  done
  echo "$(basename "$g"): $o"
done
rm -rf "${t:?}"
