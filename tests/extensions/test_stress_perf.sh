#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_stress_perf.sh — stress and performance with the real engine:
#   * 200 extensions (generated from the labelled hello-fixture, ids stress-NNN) added, listed,
#     verified, wired and removed; peak RSS of the engine bounded (STRESS_RSS_MB, default 200 MiB);
#   * 50 repeated add/enable/wire/unwire/disable/remove cycles of one extension, leaving no residue;
#   * time budgets (seconds, generous for a loaded host; override with EXT_PERF_*):
#     single add < EXT_PERF_ADD (3), list of 200 < EXT_PERF_LIST (5), verify of 200 < EXT_PERF_VERIFY (20).
T_NAME=stress_perf
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"
e() { eng --root "$R" --project-root "$P" "$@"; }
N="${EXT_STRESS_N:-200}"; CYC="${EXT_STRESS_CYCLES:-50}"
mk() { local id="$1" d="$SB/gen/$1"; copy_fixture hello-fixture "$d"
  python3 -I - "$d" "$id" <<'PY'
import os, sys
d, i = sys.argv[1], sys.argv[2]
p = os.path.join(d, "extension.yml"); s = open(p).read()
s = s.replace("id: hello-fixture", "id: " + i).replace("- name: hello-fixture", "- name: " + i + "-cmd")
open(p, "w").write(s)
os.rename(os.path.join(d, "commands", "hello-fixture"), os.path.join(d, "commands", i + "-cmd"))
PY
}
now() { date +%s.%N; }
dt() { python3 -I -c 'import sys; print("%.3f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"; }
lt() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }

for i in $(seq -w 1 "$N"); do mk "stress-$i"; done
t0="$(now)"; e add "$SB/gen/stress-001" --dev --waiver-id WS --yes; t1="$(now)"
eq "first add" 0 "$RC"; d="$(dt "$t0" "$t1")"; echo "  time single add: ${d}s"
check "single add < ${EXT_PERF_ADD:-3}s" lt "$d" "${EXT_PERF_ADD:-3}"
fails=0
for i in $(seq -w 2 "$N"); do e add "$SB/gen/stress-$i" --dev --waiver-id WS --yes || true; [ "$RC" = 0 ] || fails=$((fails+1)); done
eq "all $N adds succeeded" 0 "$fails"
t0="$(now)"; engj --root "$R" --project-root "$P" --json list; t1="$(now)"; d="$(dt "$t0" "$t1")"; echo "  time list $N: ${d}s"
eq "list shows $N" "$N" "$(python3 -I -c 'import json,sys; print(len(json.loads(sys.argv[1])["extensions"]))' "$OUT")"
check "list < ${EXT_PERF_LIST:-5}s" lt "$d" "${EXT_PERF_LIST:-5}"
for i in $(seq -w 1 "$N"); do e enable "stress-$i" --yes >/dev/null; done
t0="$(now)"; e verify; t1="$(now)"; d="$(dt "$t0" "$t1")"; echo "  time verify $N: ${d}s"
eq "verify all $N" 0 "$RC"; check "verify < ${EXT_PERF_VERIFY:-20}s" lt "$d" "${EXT_PERF_VERIFY:-20}"
rss="$( { /usr/bin/time -f '%M' bash "$ENGINE" --root "$R" --project-root "$P" wire --agent all --target "$P" >/dev/null; } 2>&1 | tail -1)"
echo "  peak RSS wire-all over $N: ${rss} KiB"
check "wire-all RSS < ${STRESS_RSS_MB:-200} MiB" test "${rss:-999999999}" -lt $(( ${STRESS_RSS_MB:-200} * 1024 ))
eq "claude links for $N" "$N" "$(find "$P/.claude/skills" -maxdepth 1 -type l | wc -l)"
e unwire --agent all --target "$P"; eq "unwire all" 0 "$RC"
fails=0; for i in $(seq -w 1 "$N"); do e remove "stress-$i" --yes; [ "$RC" = 0 ] || fails=$((fails+1)); done
eq "all removes succeeded" 0 "$fails"
eq "_installed empty" 0 "$(find "$R/extensions/_installed" -mindepth 1 -maxdepth 1 | wc -l)"

base="$(tree_fp "$P/.claude")$(tree_fp "$R/extensions")"
fails=0
for c in $(seq 1 "$CYC"); do
  for cmd in "add $SB/gen/stress-001 --dev --waiver-id WS --yes" "enable stress-001 --yes" "wire stress-001 --agent all --target $P" \
             "unwire stress-001 --agent all --target $P" "disable stress-001" "remove stress-001 --yes"; do
    # shellcheck disable=SC2086
    e $cmd; [ "$RC" = 0 ] || { fails=$((fails+1)); echo "    cycle $c failed: $cmd -> $RC"; }
  done
done
eq "$CYC cycles without failure" 0 "$fails"
eq "no residue after cycles" "$base" "$(tree_fp "$P/.claude")$(tree_fp "$R/extensions")"
finish
