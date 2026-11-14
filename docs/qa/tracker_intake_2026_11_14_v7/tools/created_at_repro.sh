#!/usr/bin/env bash
# docs/qa/tracker_intake_2026_11_14_v7/tools/created_at_repro.sh -- reproduce the mechanism behind the
# round-7 review finding F2 (a flaky re-mint suite case) on a scratch copy, by toggling the cause:
# an engine `close` rewrites created_at to the current second (CON-339), so whether a close "changes"
# created_at depends on whether it falls in a later second than the `add` before it.
#
# usage (from the repository root): created_at_repro.sh <workable-items binary> <database to copy> <trials>
# For each trial it adds an item and closes it at once (arm SAME), and adds one, waits until the next
# wall-clock second, and closes it (arm NEXT); it reports, per arm, how many closes left created_at
# unchanged. The cause predicts: arm NEXT always changed; arm SAME mostly unchanged.
# Exit: 0 the run completed (read the counts); 2 usage; 3 a step failed.
# Evidence class: gate-logic only (section 11.4.289); nothing here writes a tracked database.
set -u
WI=${1:?usage: created_at_repro.sh <wi> <db> <trials>}; SRC=${2:?}; N=${3:?}
case "$N" in ''|*[!0-9]*|0) echo "usage: trials must be a positive integer" >&2; exit 2 ;; esac
root=$(pwd); case "$WI" in /*) ;; *) WI=$root/$WI ;; esac
# shellcheck source=../../../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 3
tmp=$(mktemp -d) || exit 3
cleanup() { safe_rm_rf "${tmp:?}" || echo "CLEANUP REFUSED: $tmp" >&2; }
trap cleanup EXIT
mkdir -p "$tmp/r/docs/qa" && printf 'evidence\n' >"$tmp/r/docs/qa/x.txt" && cp "$SRC" "$tmp/r/docs/w.db" || exit 3
n=$(python3 -I -c 'import re,sqlite3,sys;c=sqlite3.connect(sys.argv[1]);print(max(int(r[0][4:]) for r in c.execute("select atm_id from items") if re.fullmatch(r"CON-\d+",r[0])))' "$tmp/r/docs/w.db") || exit 3
ca() { python3 -I -c 'import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);print(c.execute("select created_at from items where atm_id=?",(sys.argv[2],)).fetchone()[0])' "$tmp/r/docs/w.db" "$1"; }
W() { (cd "$tmp/r" && "$WI" "$@") >>"$tmp/engine.log" 2>&1 || { echo "step failed: $*" >&2; tail -2 "$tmp/engine.log" >&2; exit 3; }; }
same_unchanged=0; next_unchanged=0
for t in $(seq 1 "$N"); do
  for arm in SAME NEXT; do
    n=$((n + 1)); i=$(printf 'CON-%03d' "$n")
    W add Task Low --db docs/w.db --id "$i" --title "created_at repro item" --description "**What:** a created_at repro item on a scratch copy, never landed." --created-by Claude
    a=$(ca "$i")
    if [ "$arm" = NEXT ]; then s=$(date +%s); while [ "$(date +%s)" = "$s" ]; do sleep 0.05; done; fi
    W close "$i" --db docs/w.db --status obsolete --evidence docs/qa/x.txt
    b=$(ca "$i")
    if [ "$a" = "$b" ]; then
      [ "$arm" = SAME ] && same_unchanged=$((same_unchanged + 1)) || next_unchanged=$((next_unchanged + 1))
    fi
  done
done
echo "RESULT: trials=$N same_second_unchanged=$same_unchanged next_second_unchanged=$next_unchanged"
exit 0
