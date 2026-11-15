#!/usr/bin/env bash
# test_shell_state_patsub.sh — hi_reset_shell_state turns `patsub_replacement` OFF, which is not bash 5.2's default
# (on), and every comment that says the reset returns the options "to bash's defaults" names that exception
# (CON-PENDING-installer-followups).
#
# Why: the comments said the reset returns every option to bash's defaults. For patsub_replacement that is false
# on bash 5.2 and later: bash turns it on, the reset turns it off, so `&` in the replacement of ${var//pat/rep}
# stays a literal `&` (bash 5.1 behaviour). A reader who trusts the comment expects `&` to insert the match.
#
# Sections:
#   1. behaviour, per script (the four copies of hi_reset_shell_state): on this bash, patsub_replacement is on before
#      the reset (control: else the case says nothing, SKIP with reason), off after it, and ${x//b/[&]} gives a
#      literal `[&]`.
#   2. comment census: every comment paragraph in the four scripts and the no-push gate that speaks of the reset
#      (hi_reset_shell_state, hi_shell_state, shell-state reset) and of defaults also names patsub_replacement.
#      Control needles: a planted paragraph without the name is flagged, one with it is not (else BLIND, exit 2).
#
# TEST-CLASS LABEL (§11.4.289): unit class. The functions are run in a child bash, no network, nothing written
# outside the sandbox.
# Usage: bash tests/install/test_shell_state_patsub.sh   Exit 0 all pass · 1 a case failed · 2 blind.
# shellcheck disable=SC2034  # T_NAME is read by finish() in lib.sh
T_NAME=shell_state_patsub
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
command -v python3 >/dev/null 2>&1 || { echo "  SKIP python3 is not on PATH (reason: tool_not_present; nothing ran)"; finish; exit 2; }

FOUR=("$INSTALLER" "$UPDATER" "$REPO/scripts/install_cli_agent_plugins.sh" "$REPO/scripts/install_action_prefix.sh")
GATE="$REPO/scripts/gates/cm_installer_no_push_no_force.sh"

# ── 1. behaviour ──
fn_of() { awk '/^hi_reset_shell_state\(\) \{/{ on = 1 } on { print } on && /^\}/ { exit }' "$1"; }
for f in "${FOUR[@]}"; do
  b="${f##*/}"; def="$(fn_of "$f")"
  eq "control: hi_reset_shell_state found in $b" 1 "$(printf '%s\n' "$def" | grep -c '^hi_reset_shell_state() {')"
  # shellcheck disable=SC2016  # run by the child bash
  res="$(bash -c 'eval "$1"; before=$(shopt -q patsub_replacement 2>/dev/null && echo on || echo off)
    hi_reset_shell_state; after=$(shopt -q patsub_replacement 2>/dev/null && echo on || echo off)
    x=abc; printf "%s %s %s\n" "$before" "$after" "${x//b/[&]}"' _ "$def" 2>&1)"
  set -- $res
  if [ "${1:-}" != on ]; then
    echo "  SKIP $b: patsub_replacement is not on by default in this bash (${BASH_VERSION}; reason: topology_unsupported)"
    continue
  fi
  eq "$b: patsub_replacement is off after hi_reset_shell_state (bash ${BASH_VERSION%%(*})" off "${2:-}"
  eq "$b: & in a replacement stays literal after the reset" 'a[&]c' "${3:-}"
done

# ── 2. comment census ──
# shellcheck disable=SC2016  # Python source
census='import re, sys
topic = re.compile(r"hi_reset_shell_state|hi_shell_state|shell-state reset|resets? (every|each) (bash )?option")
for f in sys.argv[1:]:
    para, start = [], 0
    lines = open(f, encoding="utf-8", errors="replace").read().split("\n") + [""]
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("#"):
            if not para: start = n
            para.append(s)
            continue
        if para:
            t = " ".join(para)
            if topic.search(t) and re.search(r"\bdefaults?\b", t) and "patsub_replacement" not in t:
                print("%s:%d\t%s" % (f, start, t[:160]))
        para = []'
ndl="$SB/needle.sh"
printf '%s\n' '# hi_reset_shell_state returns every option to bash'"'"'s defaults.' 'x=1' \
  '# hi_reset_shell_state returns every option to bash'"'"'s defaults, except patsub_replacement.' 'y=1' >"$ndl"
nd="$(python3 -I -c "$census" "$ndl")"
if [ "$(printf '%s\n' "$nd" | grep -c .)" = 1 ] && printf '%s\n' "$nd" | grep -q "$ndl:1	"; then
  ok "census control needles: a defaults claim without the exception is flagged, one with it is not"
else
  echo "  BLIND census: control needles not seen as expected: [$nd]"; finish; exit 2
fi
bad="$(python3 -I -c "$census" "${FOUR[@]}" "$GATE")"
eq "every comment that says the reset restores bash's defaults names the patsub_replacement exception" "" "$bad"
[ -z "$bad" ] || printf '    %s\n' "$bad"
finish
