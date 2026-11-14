#!/usr/bin/env bash
# deliver_r5.sh <W> <OUT>
# Commit is done separately. This makes, from the work repository at <W>/work:
#   <OUT>/bundle_repo  : a bare repo whose refs/heads/main is the vehicle/lander-r5 head
#   <OUT>/land_vehicle_r5.bundle  (refs/heads/main, no prerequisites, like round 4)
#   <OUT>/land_vehicle_r5_out.tar.gz (the lander, the test and the evidence dir, from the commit)
#   <OUT>/delivery.txt (sha256, head, requires, verify output)
set -euo pipefail
W=${1:?usage: deliver_r5.sh <W> <OUT>}
OUT=${2:?usage: deliver_r5.sh <W> <OUT>}
[ -d "$W/work/.git" ] || { echo "no work repo at $W/work" >&2; exit 2; }
[ -d "$OUT" ] || { echo "no out dir $OUT" >&2; exit 2; }
[ ! -e "$OUT/bundle_repo" ] || { echo "bundle_repo already exists in $OUT" >&2; exit 2; }
head=$(git -C "$W/work" rev-parse --verify 'refs/heads/vehicle/lander-r5^{commit}')
git init -q --bare "$OUT/bundle_repo"
git -C "$OUT/bundle_repo" fetch -q --no-tags "$W/work" "refs/heads/vehicle/lander-r5:refs/heads/main"
[ "$(git -C "$OUT/bundle_repo" rev-parse refs/heads/main)" = "$head" ]
git -C "$OUT/bundle_repo" bundle create "$OUT/land_vehicle_r5.bundle" refs/heads/main 2>"$OUT/bundle_create.err"
mkdir "$OUT/tar_tree"
git -C "$W/work" archive --format=tar "$head" scripts/release/land_vehicle.sh tests/release/test_land_vehicle.sh docs/qa/land_vehicle_r5_2026_11_13 | tar -x -C "$OUT/tar_tree"
tar -C "$OUT/tar_tree" --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-11-14 00:00:00 UTC' -czf "$OUT/land_vehicle_r5_out.tar.gz" .
{
  echo "head $head"
  echo "head subject: $(git -C "$W/work" log -1 --format=%s "$head")"
  echo "head parents: $(git -C "$W/work" log -1 --format=%P "$head")"
  echo "commits in the bundle: $(git -C "$OUT/bundle_repo" rev-list --count refs/heads/main)"
  echo "root commit(s): $(git -C "$OUT/bundle_repo" rev-list --max-parents=0 refs/heads/main | tr '\n' ' ')"
  echo "bundle sha256 $(sha256sum "$OUT/land_vehicle_r5.bundle" | cut -d' ' -f1)"
  echo "bundle bytes $(stat -c %s "$OUT/land_vehicle_r5.bundle")"
  echo "--- git bundle list-heads"
  git bundle list-heads "$OUT/land_vehicle_r5.bundle"
  echo "--- bundle header (requires = lines starting with '-'; none expected)"
  LC_ALL=C sed -n '1,/^$/p' "$OUT/land_vehicle_r5.bundle" | LC_ALL=C grep -a -v '^PACK' || true
  echo "requires: $(LC_ALL=C sed -n '1,/^$/p' "$OUT/land_vehicle_r5.bundle" | LC_ALL=C grep -a -c '^-' || true)"
  echo "--- git bundle verify (in a new EMPTY repository, so no prerequisite can be satisfied from local objects)"
  git init -q --bare "$OUT/verify_empty"
  rc=0; git -C "$OUT/verify_empty" bundle verify "$OUT/land_vehicle_r5.bundle" 2>&1 || rc=$?
  echo "verify rc=$rc"
  echo "--- clone of the bundle: head and tree of the cloned main"
  git clone -q --bare "$OUT/land_vehicle_r5.bundle" "$OUT/verify_clone"
  echo "cloned main $(git -C "$OUT/verify_clone" rev-parse refs/heads/main)"
  echo "fsck: $(git -C "$OUT/verify_clone" fsck --no-dangling 2>&1 | grep -c . || true) lines of output"
  echo "--- tarball"
  echo "tarball sha256 $(sha256sum "$OUT/land_vehicle_r5_out.tar.gz" | cut -d' ' -f1)"
  echo "tarball entries $(tar -tzf "$OUT/land_vehicle_r5_out.tar.gz" | grep -c .)"
  echo "lander in tarball sha256 $(sha256sum "$OUT/tar_tree/scripts/release/land_vehicle.sh" | cut -d' ' -f1)"
  echo "test in tarball sha256 $(sha256sum "$OUT/tar_tree/tests/release/test_land_vehicle.sh" | cut -d' ' -f1)"
} > "$OUT/delivery.txt"
cat "$OUT/delivery.txt"
