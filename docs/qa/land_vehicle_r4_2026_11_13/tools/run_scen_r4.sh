#!/usr/bin/env bash
# run_scen_r4.sh <scen-root> <reviewer-scen.sh> <outdir>: runs the round-3 reviewer's adversarial
# scenarios (unchanged scen.sh, sha256 recorded) against the round-4 lander placed in
# <scen-root>/repo/scripts/release/land_vehicle.sh. One scenario per invocation, sequential.
# LANDER_TRACKER_PATHS names both tracker files the scenario fixtures use (docs/tracker.fake for the
# fixture mints, docs/wi.db for S_A3b, which runs the real engine binary on a copy of a DB that
# base_fixture copies into the seed repository; the source DB file is hashed before and after).
set -uo pipefail
R=${1:?scen root}; SC=${2:?scen.sh}; O=${3:?outdir}
mkdir -p "$O"
DB=$R/../wi.db
{ echo "scen.sh sha256 $(sha256sum < "$SC" | cut -c1-64)"
  echo "lander sha256 $(sha256sum < "$R/repo/scripts/release/land_vehicle.sh" | cut -c1-64)"
  echo "source db sha256 before $(sha256sum < "$DB" | cut -c1-64)"; } > "$O/scen_meta.txt"
for s in S_A1 S_A3 S_A3b S_A5 S_A6 S_A7 S_A8 S_A9 S_A10 S_A11 S_A12 S_A13 S_A14 S_A15 S_A19 S_A21 S_A23 S_A24 S_A25 S_A26 S_A27 S_A28 S_A29 S_A30; do
  env LANDER_TRACKER_PATHS="docs/tracker.fake docs/wi.db" timeout 600 bash "$SC" "$R" "$s" > "$O/$s.log" 2>&1
  echo "$s rc=$?" >> "$O/scen_meta.txt"
done
echo "source db sha256 after $(sha256sum < "$DB" | cut -c1-64)" >> "$O/scen_meta.txt"
