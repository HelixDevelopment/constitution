#!/bin/bash
# Purpose : tests the sourced consumer-data guard scripts/fastcycle/tests/lib/consumer_required.sh
#           (review F1, F2, F9 of the manifest-triage vehicle, round 2).
#           Part 1 drives the REAL helper (linked, not copied) from a fake test placed in a scratch
#           consumer layout <consumer>/<canon>/scripts/fastcycle/tests/, under bash AND under dash:
#             - data absent  -> rc 77, last line names the missing path and ends reason=topology_unsupported
#             - data present -> rc 0 and the test body runs (a false SKIP here was F1: BASH_SOURCE is empty
#                               under dash, so the root resolved to /)
#             - an absolute (effective) path is checked as given, present and absent
#             - several paths: only the missing ones are named
#             - relative $0 (run from another cwd) and a consumer root with a space
#           Part 2 drives two REAL callers in this checkout, only where the consumer data they default to is
#           genuinely absent (canon alone): the env override is honoured (no SKIP when the override points at a
#           present file), and monday_dryrun needs the RB-05 mock only for RED_MODE=0 (F2).
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_helper.sh
# Exit    : 0 all pass; 1 any fail; 77 (reason=topology_unsupported) when no dash is installed, so the
#           dash leg could not run (the bash leg still ran and passed).
# Safety  : one mktemp -d root, removed with safe_rm_rf restricted to it; $HOME is never reassigned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
HELPER="$HERE/lib/consumer_required.sh"
# shellcheck source=../../../scripts/lib/safe_rm.sh
. "$CANON/scripts/lib/safe_rm.sh"
P=0; F=0
ok()  { P=$((P+1)); echo "ok   $*"; }
bad() { F=$((F+1)); echo "NOT ok $*"; }
expect() { # expect DESC WANT_RC WANT_LASTLINE_REGEX(or -) OUTFILE RC
  local d="$1" wrc="$2" wre="$3" out="$4" rc="$5" last
  last="$(grep -v '^[[:space:]]*$' "$out" | tail -1)"
  if [ "$rc" != "$wrc" ]; then bad "$d (rc $rc, want $wrc; last line: $last)"; return; fi
  if [ "$wre" != "-" ] && ! printf '%s\n' "$last" | grep -Eq -- "$wre"; then bad "$d (last line [$last] does not match /$wre/)"; return; fi
  ok "$d"
}

W="$(mktemp -d "${TMPDIR:-/tmp}/consumer_required_test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT

mk_layout() { # mk_layout CONSUMER_DIR -> fake test path on stdout
  local c="$1" t="$1/canon/scripts/fastcycle/tests"
  mkdir -p "$t/lib" "$c/docs" || return 1
  ln -s "$HELPER" "$t/lib/consumer_required.sh" || return 1
  cat >"$t/fake_test.sh" <<'EOF'
#!/bin/sh
. "$(dirname "$0")/lib/consumer_required.sh" && fc_require_consumer "$@"
echo "BODY RAN"
EOF
  printf '%s\n' "$t/fake_test.sh"
}

SHELLS="bash"
DASH="$(command -v dash 2>/dev/null || true)"
[ -n "$DASH" ] && SHELLS="bash dash"

echo "=== Part 1: the helper under $SHELLS"
for layout in "plain" "with space"; do
  C="$W/$layout/consumer"
  T="$(mk_layout "$C")" || { bad "layout '$layout': setup failed"; continue; }
  : >"$C/docs/present.db"
  : >"$W/outside_present.sh"
  for sh in $SHELLS; do
    tag="[$sh, $layout]"
    o="$W/out"
    "$sh" "$T" docs/absent.db >"$o" 2>&1; rc=$?
    expect "$tag data absent -> SKIP 77 naming the path, reason=topology_unsupported" 77 \
      "docs/absent\.db.*reason=topology_unsupported$" "$o" "$rc"
    grep -qF "absent under $C:" "$o" && ok "$tag SKIP names the consumer root $C" || bad "$tag SKIP does not name the root $C: $(cat "$o")"
    "$sh" "$T" docs/present.db >"$o" 2>&1; rc=$?
    expect "$tag data present -> body runs, no SKIP" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" "$W/outside_present.sh" >"$o" 2>&1; rc=$?
    expect "$tag absolute effective path present -> body runs" 0 "^BODY RAN$" "$o" "$rc"
    "$sh" "$T" "$W/outside_absent.sh" >"$o" 2>&1; rc=$?
    expect "$tag absolute effective path absent -> SKIP 77" 77 "outside_absent\.sh.*reason=topology_unsupported$" "$o" "$rc"
    "$sh" "$T" docs/present.db docs/gone1 docs/gone2 >"$o" 2>&1; rc=$?
    expect "$tag several paths -> SKIP naming only the missing ones" 77 "docs/gone1 docs/gone2 \(" "$o" "$rc"
    grep -q 'present\.db' "$o" && bad "$tag the present path was named as missing" || ok "$tag the present path is not named"
    ( cd "$C/canon" && "$sh" scripts/fastcycle/tests/fake_test.sh docs/present.db ) >"$o" 2>&1; rc=$?
    expect "$tag relative \$0 from another cwd -> root still resolved, body runs" 0 "^BODY RAN$" "$o" "$rc"
  done
done

echo "=== Part 2: real callers in this checkout (effective-path guard, F2)"
CONSUMER="$(cd "$CANON/.." && pwd)"
TPB="$HERE/test_fc_timer_prebuild_red.sh"
if [ -e "$CONSUMER/device/rockchip/rk3588/tests/pre_build_verification.sh" ]; then
  echo "note: consumer pre_build_verification.sh is present here; the canon-alone legs of Part 2 do not apply"
else
  o="$W/tpb"
  FC_TIMER_RED_EVIDENCE_DIR="$W/tpb_ev" bash "$TPB" >"$o" 2>&1; rc=$?
  expect "timer_prebuild, no override, default input absent -> SKIP 77" 77 "reason=topology_unsupported$" "$o" "$rc"
  printf '#!/bin/sh\nexit 0\n' >"$W/stub_prebuild.sh"
  FC_TIMER_RED_PREBUILD="$W/stub_prebuild.sh" FC_TIMER_RED_EVIDENCE_DIR="$W/tpb_ev" bash "$TPB" >"$o" 2>&1; rc=$?
  if [ "$rc" != 77 ] && ! grep -q 'reason=topology_unsupported' "$o"; then
    ok "timer_prebuild, FC_TIMER_RED_PREBUILD -> present stub: the guard honours the override (rc $rc, the run went on)"
  else
    bad "timer_prebuild ignored FC_TIMER_RED_PREBUILD (rc $rc): $(tail -1 "$o")"
  fi
fi
MON="$CANON/scripts/multitrack/test_multitrack_monday_dryrun.sh"
if [ -e "$CONSUMER/scripts/multitrack/rb05_fixtures/mock_claude.sh" ]; then
  echo "note: the RB-05 mock is present here; the canon-alone legs of Part 2 do not apply"
else
  o="$W/mon"
  RED_MODE=1 MT_RB13_TEST_EVIDENCE_DIR="$W/mon1_ev" sh "$MON" >"$o" 2>&1; rc=$?
  if [ "$rc" != 77 ]; then ok "monday_dryrun RED_MODE=1 without the mock runs (rc $rc): the RED battery never reads the mock"
  else bad "monday_dryrun RED_MODE=1 SKIPped on the absent mock it does not use: $(tail -1 "$o")"; fi
  RED_MODE=0 MT_RB13_TEST_EVIDENCE_DIR="$W/mon0_ev" sh "$MON" >"$o" 2>&1; rc=$?
  expect "monday_dryrun RED_MODE=0 without the mock -> SKIP 77" 77 "mock_claude\.sh reason=topology_unsupported$" "$o" "$rc"
  [ -e "$W/mon0_ev" ] && bad "monday_dryrun RED_MODE=0 created its evidence dir before the SKIP" || ok "monday_dryrun RED_MODE=0 SKIP is decided before any evidence dir is created"
fi

echo "SUMMARY: $P pass / $F fail"
[ "$F" -eq 0 ] || exit 1
[ "$P" -gt 0 ] || exit 1
if [ -z "$DASH" ]; then
  echo "SKIP: dash is not installed, so the dash leg did not run reason=topology_unsupported"
  exit 77
fi
exit 0
