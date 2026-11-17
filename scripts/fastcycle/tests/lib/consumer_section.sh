#!/bin/sh
# shellcheck shell=sh
# Purpose : sourced helper for fastcycle tests that mix canon-runnable sections with sections that read
#           CONSUMER-project data (tracker DB, specs/, config/, qa-results/ trees absent in the canon repository).
#           It skips ONE consumer-data section, not the whole test (CON-092 / CON-093), and turns a passing run
#           with a skipped section into the honest SKIP exit 77 (section 11.4.3 / 11.4.69, topology_unsupported).
#           Kept apart from lib/consumer_required.sh on purpose: that helper's mutation sweep
#           (test_consumer_required_mutations.sh) is bound to test_consumer_required_helper.sh, which never calls
#           these functions; their own RED test and mutants are test_consumer_section_con092_red.sh and
#           test_consumer_section_con092_mutations.sh.
# Usage   : . "$(dirname "$0")/lib/consumer_section.sh"
#           if fc_consumer_section "<label>" <path>...; then <consumer-data section>; fi
#           ...; fc_consumer_exit <the test's own verdict rc>
# Root    : the consumer root is four levels above the calling test ($0), as in lib/consumer_required.sh.

# fc_consumer_section <label> <path>...   (CON-092 / CON-093: skip one section, not the whole test)
#   Returns 0 when every named path exists, so the caller runs the section. Otherwise prints one line
#   "SKIP-SECTION: <label>: consumer-project files absent under <root>: <paths> reason=topology_unsupported",
#   records the skip in FC_CONSUMER_SECTIONS_SKIPPED (a count) and returns 1, so the caller skips ONLY that
#   section; the canon-runnable sections still run and report. Paths resolve as in fc_require_consumer.
#   The caller ends with fc_consumer_exit <its own verdict rc>.
# fc_consumer_exit <rc>
#   rc != 0: exit rc (a FAIL is never turned into a SKIP). rc = 0 and at least one section was skipped:
#   prints "SKIP: <n> consumer-data section(s) skipped ... reason=topology_unsupported" and exits 77 (the run
#   is not a full PASS). rc = 0 and nothing skipped: exit 0.
fc_consumer_section() {
  _fcs_label=$1; shift
  _fcs_root=$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd) || _fcs_root=""
  _fcs_missing=""
  for _fcs_p in "$@"; do
    case $_fcs_p in /*) _fcs_abs=$_fcs_p ;; *) _fcs_abs=$_fcs_root/$_fcs_p ;; esac
    if [ -z "$_fcs_root" ] && [ "${_fcs_p#/}" = "$_fcs_p" ]; then _fcs_missing="$_fcs_missing $_fcs_p"; continue; fi
    [ -e "$_fcs_abs" ] || _fcs_missing="$_fcs_missing $_fcs_p"
  done
  if [ -n "$_fcs_missing" ]; then
    FC_CONSUMER_SECTIONS_SKIPPED=$(( ${FC_CONSUMER_SECTIONS_SKIPPED:-0} + 1 ))
    echo "SKIP-SECTION: $_fcs_label: consumer-project files absent under ${_fcs_root:-<unresolvable root>}:$_fcs_missing reason=topology_unsupported"
    unset _fcs_label _fcs_root _fcs_missing _fcs_p _fcs_abs
    return 1
  fi
  unset _fcs_label _fcs_root _fcs_missing _fcs_p _fcs_abs
  return 0
}
fc_consumer_exit() {
  case ${1:-} in ''|*[!0-9]*) echo "fc_consumer_exit: rc must be a non-negative integer, got '${1:-}'" >&2; exit 2 ;; esac
  [ "$1" -eq 0 ] || exit "$1"
  if [ "${FC_CONSUMER_SECTIONS_SKIPPED:-0}" -gt 0 ]; then
    echo "SKIP: $FC_CONSUMER_SECTIONS_SKIPPED consumer-data section(s) skipped, every other section passed (not a full PASS) reason=topology_unsupported"
    exit 77
  fi
  exit 0
}
