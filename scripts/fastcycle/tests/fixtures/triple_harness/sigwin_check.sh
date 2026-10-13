#!/bin/bash
# sigwin_check.sh <harness|deps> <tests-dir> : runs sigwin_rig.sh in every window and prints
# `FAIL ...` lines (nothing for a pass) / `SKIP ...` lines (rig unusable, named reason). Exit 0 always;
# the caller counts FAIL lines. Windows: see sigwin_rig.sh (plain, plainzsh, inherit, postwait, postcanary, shim, shimord).
kind=$1; here=$2
# R7-F7: the rig's own cleanup `gone` (it SIGKILLs a group) must never signal a value that is not a plain integer > 1
# (`kill -- -1` is every process, 11.4.263). Its one-line definition is evaluated with a LOG-ONLY kill.
if [ "$kind" = harness ]; then
  gdef=$(sed -n '/^gone() {/p' "$here/fixtures/triple_harness/sigwin_rig.sh")
  glog=$(mktemp) || exit 2
  if [ -z "$gdef" ]; then echo "FAIL r7f7 rig cleanup: no one-line gone() definition found in sigwin_rig.sh"
  else
    ( kill() { printf '%s\n' "$*" >>"$glog"; return 0; }
      eval "$gdef"
      for v in 0 1 -1 '' abc '2 3' 1x -5 00 01 '!' -gt; do gone "$v"; done
      gone 4194999 )
    gres=$(sort "$glog" | tr '\n' '|')
    [ "$gres" = "-s KILL -- -4194999|-s KILL 4194999|" ] || echo "FAIL r7f7 rig cleanup gone(): signalled a bad value or missed the good one: [$gres]"
  fi
  rm -f "$glog"
fi
for m in plain plainzsh inherit postwait postcanary shim shimord; do
  res=$(timeout -k 2 150 bash "$here/fixtures/triple_harness/sigwin_rig.sh" "$kind" "$m" "$here" 2>/dev/null)
  want="RESULT fired=1 rc=2 orphan=0 sleeper=na canary=na"
  [ "$m" = inherit ] && want="RESULT fired=1 rc=2 orphan=0 sleeper=alive canary=na"
  [ "$m" = postcanary ] && want="RESULT fired=1 rc=2 orphan=0 sleeper=na canary=alive"
  case $res in
    SKIP*) echo "$res (signal window $m)" ;;
    "$want") : ;;
    *) echo "FAIL r6-f1/f2/r7 signal window ($kind, $m): got '$res' want '$want'" ;;
  esac
done
exit 0
