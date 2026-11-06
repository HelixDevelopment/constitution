#!/bin/sh
# shellcheck shell=sh
# Purpose : sourced helper for SpecKit-004 fastcycle tests that exercise CONSUMER-project data
#           (tracker DB, specs/, config/, device/ trees) which does not exist in the canon repository.
#           fc_require_consumer <path>...  exits 77 (honest SKIP, section 11.4.3 / 11.4.69
#           topology_unsupported) when any named path is absent, naming each; never a PASS.
#           A relative <path> is resolved under the consumer root. An absolute <path> is checked
#           as given: a test whose input can be redirected by an env override (for example
#           FC_TIMER_RED_PREBUILD) passes the EFFECTIVE path it will read, so the SKIP fires only
#           when the input the run actually needs is absent (review F2, section 11.4.201(1)).
# Usage   : . "$(dirname "$0")/lib/consumer_required.sh" && fc_require_consumer <path>...
# Shell   : plain POSIX sh. It runs under bash and under dash (the full-suite runner runs a
#           #!/bin/sh test with sh). It reads no bash-only variable (review F1: BASH_SOURCE is
#           empty under dash, which resolved the root to / and gave a false SKIP).
# Root    : the consumer root is four directories above the calling test, taken from $0 (in a
#           sourced file $0 is the calling script under every POSIX shell); the test lives at
#           <consumer>/<canon>/scripts/fastcycle/tests/<test>.sh.
# Output  : on SKIP one line on stdout ending in reason=topology_unsupported (the runner reads
#           reason=<code> from the last line, review F9). Exit 77. Otherwise nothing, returns 0.
# Test    : scripts/fastcycle/tests/test_consumer_required_helper.sh (bash and dash, data present
#           and absent, absolute effective paths).
fc_require_consumer() {
  _fcr_root=$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd) || _fcr_root=""
  if [ -z "$_fcr_root" ]; then
    echo "SKIP: consumer root not resolvable from \$0='$0' reason=topology_unsupported"
    exit 77
  fi
  _fcr_missing=""
  for _fcr_p in "$@"; do
    case $_fcr_p in
      /*) _fcr_abs=$_fcr_p ;;
      *)  _fcr_abs=$_fcr_root/$_fcr_p ;;
    esac
    [ -e "$_fcr_abs" ] || _fcr_missing="$_fcr_missing $_fcr_p"
  done
  if [ -n "$_fcr_missing" ]; then
    echo "SKIP: consumer-project files absent under $_fcr_root:$_fcr_missing (test targets a consumer layout, not canon alone) reason=topology_unsupported"
    exit 77
  fi
  unset _fcr_root _fcr_missing _fcr_p _fcr_abs
  return 0
}
