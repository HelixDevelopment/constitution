#!/usr/bin/env bash
# snap.sh <W> <name>: a frozen copy of the lander, the test and scripts/lib under <W>/snap/<name>
# (a running suite reads its script file incrementally; edits must never touch a running copy)
set -euo pipefail
W=${1:?}; N=${2:?}
D=$W/snap/$N
[ ! -e "$D" ] || { echo "snap exists: $D" >&2; exit 1; }
mkdir -p "$D/scripts/release" "$D/tests/release"
cp -r "$W/root/scripts/lib" "$D/scripts/lib"
cp "$W/work/scripts/release/land_vehicle.sh" "$D/scripts/release/land_vehicle.sh"
cp "$W/work/tests/release/test_land_vehicle.sh" "$D/tests/release/test_land_vehicle.sh"
sha256sum "$D/scripts/release/land_vehicle.sh" "$D/tests/release/test_land_vehicle.sh" > "$D/SHA256SUMS"
echo "$D"
