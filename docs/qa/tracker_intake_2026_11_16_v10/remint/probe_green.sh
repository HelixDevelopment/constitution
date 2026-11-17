#!/usr/bin/env bash
# GREEN probes of the round-10 re-mint fixes (red.sh plus the landing's --annotate-foreign and --target-own
# declarations of remint/main_f67d926c_args.txt on every run, so each probe shows only its own refusal).
# Usage: REMINT_PROBE_W=<scratch> probe_green.sh <tool> <outdir> <label>
# Runs the plan/verify/refs probes against the real base 02c10935, vehicle 8f688bf1 and target f67d926c.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
W=${REMINT_PROBE_W:?the scratch root holding dbs/, eng/ and repo/ (the probes read the real base, vehicle and target databases from it)}
R=${1:?tool}; OUT=${2:?outdir}; LAB=${3:?label}
mkdir -p "$OUT"
V=$W/dbs/vehicle.db B=$W/dbs/base.db T=$W/dbs/f67d.db E=$W/eng/wi_f67d
DUP=$W/repo/docs/qa/tracker_intake_2026_11_16_v10/remint/dup_resolution_f67d926c.tsv
O=$(mktemp -d "$W/green.XXXXXX") || exit 3
mapfile -t DECL < <(grep -E '^--(annotate-foreign|target-own) ' "$W/repo/docs/qa/tracker_intake_2026_11_16_v10/remint/main_f67d926c_args.txt" | tr ' ' '\n')
cd "$W/repo" || exit 3
run() { local lab=$1 tgt=$2; shift 2
  python3 -I "$R" plan --vehicle-db "$V" --base-db "$B" --target-db "$tgt" --out "$O/$lab.json" --prefix CON "$@" >"$O/$lab.txt" 2>&1
  echo "$lab rc=$? $(grep -E '^RESULT' "$O/$lab.txt" | cut -c1-140)"
  echo "  xref lines: $(grep -c '^XREF ' "$O/$lab.txt") (declared: $(grep -cE '^XREF .*, (annotate|target-own)$' "$O/$lab.txt"))"
  grep -E '^REFUSED' "$O/$lab.txt" | cut -c1-260 | head -8; }
{
echo "== $LAB: tool sha256 $(sha256sum "$R" | cut -c1-16)"
echo "-- R9-5 (3): real target f67d926c; CON-313, CON-387, CON-388 name the vehicle's CON-308 (lands elsewhere)"
run x1_real "$T" "${DECL[@]}" --supersede CON-339=CON-313 --dup-resolution "$DUP"
python3 -I - "$O/x1_real.json" <<'PY'
import json,sys
try: p=json.load(open(sys.argv[1]))
except Exception as e: print("no plan:", e); sys.exit()
print("annotations:", sorted(p.get("annotations", {})), "target_own:", sorted(p.get("target_own", {}) if isinstance(p.get("target_own"), dict) else []))
PY
echo "-- R9-5 (3): the same plan without the --target-own and CON-387/CON-388 declarations (the RED probe's arguments)"
run x1_undeclared "$T" --supersede CON-339=CON-313 --annotate-foreign CON-313 --dup-resolution "$DUP"
echo "  refusals by class: $(grep -oE '^REFUSED XREF-[A-Z]+' "$O/x1_undeclared.txt" | sort | uniq -c | tr -s ' ' | tr '\n' ',')"
echo "-- R9-5 (3): reviewer probe b1 (CON-405 names the vehicle's CON-320 on a colliding target)"
cp "$T" "$O/t_rebound.db"
sqlite3 "$O/t_rebound.db" "update items set description = description || char(10) || 'The vehicle''s CON-320 must land first.' where atm_id='CON-405'"
run b1_rebound_collides "$O/t_rebound.db" "${DECL[@]}" --supersede CON-339=CON-313 --dup-resolution "$DUP"
echo "-- R9-7 (5): probe a7 (supersede onto an unrelated target item, nothing names the pair)"
run a7_other_target "$T" "${DECL[@]}" --supersede CON-339=CON-411 --dup-resolution "$DUP"
echo "-- R9-7 (5): probe a6 (supersede an own id onto the target's item of the same number)"
run a6_same_number "$T" "${DECL[@]}" --supersede CON-313=CON-313 --dup-resolution "$DUP"
echo "  the supersede refusal: $(grep -E '^REFUSED --supersede' "$O/a6_same_number.txt" | cut -c1-200)"
echo "-- R9-6 (4): a SHARED-PATH pair with no verdict (the bcac0882 file without the three new rows)"
grep -v -E '^CON-32[68]	CON-40[79]	|^CON-330	CON-407	' "$DUP" > "$O/dup_short.tsv"
run d1_missing_rows "$T" "${DECL[@]}" --supersede CON-339=CON-313 --dup-resolution "$O/dup_short.tsv"
echo "-- R9-6 (4): reviewer plan_edit_probe: a made plan edited consistently (DISTINCT -> SAME-DEFECT, reason gains an id and ';'), replayed, verified"
if [ -s "$O/x1_real.json" ]; then src=$O/x1_real.json; else
  run x0_old "$T" "${DECL[@]}" --supersede CON-339=CON-313 --dup-resolution "$DUP" >/dev/null; src=$O/x0_old.json; fi
python3 -I - "$src" "$O/edited.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
old="CON-314: DISTINCT, shares only bootstrap.sh"; new="CON-314: SAME-DEFECT, shares only bootstrap.sh; see CON-999"
for k in p["landing_checks"]: p["landing_checks"][k]=p["landing_checks"][k].replace(old,new)
for s in p["steps"]:
    s["argv"]=[x.replace(old,new) for x in s["argv"]]
for row in p["dup_resolutions"]:
    if row[0]=="CON-300" and row[1]=="CON-314":
        row[2]="SAME-DEFECT"; row[3]=row[3].replace("shares only bootstrap.sh","shares only bootstrap.sh; see CON-999")
json.dump(p,open(sys.argv[2],"w"),indent=1,sort_keys=True)
PY
cp "$T" "$O/landed.db"
python3 -I "$R" replay --plan "$O/edited.json" --apply --engine "$E" --db "$O/landed.db" >"$O/replay.txt" 2>&1
echo "replay rc=$? $(grep '^RESULT' "$O/replay.txt" | cut -c1-120)"
python3 -I "$R" verify --plan "$O/edited.json" --vehicle-db "$V" --base-db "$B" --target-db "$T" --db "$O/landed.db" >"$O/verify.txt" 2>&1
echo "verify rc=$? $(grep '^RESULT' "$O/verify.txt" | cut -c1-120)"
grep -E '^(MISMATCH|BAD|FAIL)' "$O/verify.txt" | head -4 | cut -c1-220
echo "-- R9-9 (7): refs on an empty directory under ambient GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE of a sentinel repository"
S=$O/sentinel; git -c init.defaultBranch=main init -q "$S"; printf 'CON-308 named here\n' >"$S/keep.txt"
git -C "$S" add keep.txt; git -C "$S" -c user.name=s -c user.email=s@example.invalid commit -qm s
mkdir -p "$O/empty"; printf 'CON-308\tCON-412\n' >"$O/map.tsv"; sed -i '1i old\tnew' "$O/map.tsv"
GIT_DIR=$S/.git GIT_WORK_TREE=$S GIT_INDEX_FILE=$S/.git/index python3 -I "$R" refs --map "$O/map.tsv" --repo-root "$O/empty" >"$O/refs.txt" 2>&1
echo "refs rc=$? (want 3 BLIND: the directory is no repository); first lines:"; head -4 "$O/refs.txt" | cut -c1-200
} > "$OUT/remint_${LAB}.txt" 2>&1
echo "work dir $O" >> "$OUT/remint_${LAB}.txt"
