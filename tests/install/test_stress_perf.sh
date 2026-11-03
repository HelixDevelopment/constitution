#!/usr/bin/env bash
# test_stress_perf.sh — STRESS + PERFORMANCE tests for the REAL installer against a REAL local bare upstream:
#   * 50 repeated runs on an installed project: every run exit 0, state never changes, per-run time budget;
#   * a large consumer repository (20 000 tracked files) gets the submodule within the time budget;
#   * peak RSS of a full ADD measured with GNU time (when present) and held under a budget;
#   * --print-snippets / --help latency.
# Budgets are deliberately generous host-independent ceilings (this host: 64 cores; UNCONFIRMED elsewhere).
# Usage: bash tests/install/test_stress_perf.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=stress_perf
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
now() { date +%s.%N; }
el() { python3 -I -c 'import sys; print("%.2f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"; }
lt() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }

echo "# performance: fresh ADD"
P="$SB/p"; new_project "$P"; t0="$(now)"; run_installer "$P" "${BASE[@]}"; t1="$(now)"; add_s="$(el "$t0" "$t1")"
eq "ADD exit 0" 0 "$RC"; check "ADD under 60 s (took ${add_s}s)" lt "$add_s" 60
git -C "$P" commit -qm add

echo "# stress: 50 repeated runs on the installed project"
s0="$(project_state "$P")"; fails=0; changed=0; maxt=0; t0="$(now)"
for n in $(seq 1 50); do
  a="$(now)"; run_installer "$P" "${BASE[@]}"; b="$(now)"; d="$(el "$a" "$b")"
  [ "$RC" = 0 ] || fails=$((fails+1))
  [ "$(project_state "$P")" = "$s0" ] || changed=$((changed+1))
  lt "$maxt" "$d" && maxt="$d"
done
total="$(el "$t0" "$(now)")"
eq "50 runs: all exit 0" 0 "$fails"; eq "50 runs: state never changed" 0 "$changed"
check "50 runs: slowest no-op run under 15 s (slowest ${maxt}s, total ${total}s)" lt "$maxt" 15
echo "  measured: 50 no-op runs total=${total}s slowest=${maxt}s"

echo "# stress: large consumer repository"
L="$SB/large"; new_project "$L"; mkdir -p "$L/data"
python3 -I -c 'import os,sys
d=sys.argv[1]
for i in range(20000):
    sub=os.path.join(d,"d%03d"%(i//200)); os.makedirs(sub,exist_ok=True)
    open(os.path.join(sub,"f%05d.txt"%i),"w").write("file %d\n"%i)' "$L/data"
git -C "$L" add data && git -C "$L" commit -qm big
t0="$(now)"; run_installer "$L" "${BASE[@]}"; t1="$(now)"; big_s="$(el "$t0" "$t1")"
eq "large repo ADD exit 0" 0 "$RC"; eq "large repo gitlink" "$V0" "$(gitlink "$L")"
check "large repo ADD under 120 s (took ${big_s}s)" lt "$big_s" 120
eq "large repo: tracked files untouched" 20001 "$(git -C "$L" ls-files | grep -c -v -e '^\.gitmodules$' -e '^submodules/constitution$' -e '^CLAUDE.md$' -e '^AGENTS.md$')"

echo "# memory: peak RSS of a full ADD"
if [ -x /usr/bin/time ]; then
  M="$SB/mem"; new_project "$M"
  (cd "$M" && /usr/bin/time -f '%M' -o "$SB/rss.txt" bash "$INSTALLER" "${BASE[@]}" >/dev/null 2>&1); rss="$(tail -1 "$SB/rss.txt")"
  check "peak RSS under 512 MiB (measured ${rss} KiB)" eval '[ "$rss" -lt 524288 ]'
  echo "  measured: peak RSS ${rss} KiB (largest single process: bash or git)"
else
  echo "  SKIP memory: /usr/bin/time absent (reason: hardware_not_present-class tool absence)"
fi

echo "# latency of read-only modes"
t0="$(now)"; bash "$INSTALLER" --print-snippets >/dev/null; d="$(el "$t0" "$(now)")"; check "--print-snippets under 1 s (${d}s)" lt "$d" 1
t0="$(now)"; bash "$INSTALLER" --help >/dev/null; d="$(el "$t0" "$(now)")"; check "--help under 1 s (${d}s)" lt "$d" 1
finish
