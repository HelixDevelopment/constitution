#!/usr/bin/env bash
# ============================================================================
# test_fk_cascade_probe_mutations.sh — paired §1.1 mutation harness for fk_cascade_probe.py
# ============================================================================
# Purpose      Prove test_fk_cascade_probe.py is load-bearing, not decoration (§1.1 / §11.4.115(F)): the GOLDEN tool passes the
#              suite; each MUTANT (one exactly-once edit of a COPY of the tool that breaks a real behaviour — static rules,
#              window sets, verdict/exit-code mapping, fail-closed paths, shape guard, trigger drop, scratch-file lifecycle, and the
#              two behaviours the whole probe exists to measure: `insert or replace` and `foreign_keys=ON`) must make the suite FAIL.
#              A surviving mutant = a test that cannot catch that defect.
#              Redirection is PROVEN, not assumed: an unmodified COPY of the tool must pass (the copy is really exercised) and a
#              DEAD variant (exits 99) must fail (the TOOL knob really redirects the suite to the variant under test).
# Usage        bash test_fk_cascade_probe_mutations.sh      (exit 0 only if golden + copy pass, dead variant is killed, every
#              mutant is killed, every anchor applied exactly once, and the real tool is byte-identical afterwards)
# Inputs       ../fk_cascade_probe.py, ./test_fk_cascade_probe.py
# Outputs      lines `GOLDEN PASS|FAIL`, `CONTROL ...`, `MUTANT Mnn KILLED|SURVIVED|NOT-APPLIED <what>`, `REAL-TOOL sha256 ...`,
#              a final tally; exit 1 on any golden/control failure, survivor, unapplied anchor or modified real tool
# Side effects temp dir under $TMPDIR (removed on exit); NEVER edits the real tool (mutations apply to copies only)
# Dependencies bash, python3, sha256sum
# Cross-refs   fk_cascade_probe.py, test_fk_cascade_probe.py, docs/scripts/fk_cascade_probe.md, test_owed_report_mutations.sh (same
#              pattern), constitution §1.1 / §11.4.115 / §11.4.224 / §11.4.273
# ============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GOLD="$HERE/../fk_cascade_probe.py"
SUITE="$HERE/test_fk_cascade_probe.py"
W=$(mktemp -d "${TMPDIR:-/tmp}/fkp_mut.XXXXXX")
trap 'rm -rf "$W"' EXIT
export PYTHONDONTWRITEBYTECODE=1
fail=0
SHA_BEFORE=$(sha256sum "$GOLD" | cut -d' ' -f1)

run_suite() { TOOL="$1" python3 "$SUITE" >"$W/out.txt" 2>&1; }

if run_suite "$GOLD"; then echo "GOLDEN PASS"; else echo "GOLDEN FAIL (see suite) — ABORT"; tail -20 "$W/out.txt"; exit 1; fi

cp "$GOLD" "$W/copy_of_golden.py"
if run_suite "$W/copy_of_golden.py"; then echo "CONTROL unmodified-copy PASS (the copy path is really exercised)"
else echo "CONTROL unmodified-copy FAIL (harness cannot be trusted)"; fail=1; fi
printf '#!/usr/bin/env python3\nimport sys\nsys.exit(99)\n' >"$W/dead.py"
if run_suite "$W/dead.py"; then echo "CONTROL dead-variant SURVIVED (the TOOL knob does not redirect — harness blind)"; fail=1
else echo "CONTROL dead-variant KILLED (the TOOL knob redirects the suite)"; fi

# Generate every mutant: exactly-once anchor replacement on a copy. Prints "id<TAB>description" (or NOT-APPLIED lines).
python3 - "$GOLD" "$W" >"$W/mutants.tsv" <<'PY'
import sys
gold, w = sys.argv[1], sys.argv[2]
src = open(gold, encoding="utf-8").read()
M = [
 ("M01", "FK column no longer required to be LEFTMOST in the index",
  r'''i["cols"][0] == col''', r'''col in i["cols"]'''),
 ("M02", "index no longer required to be on the FK-child table",
  r'''i["table"] == table and ''', ''),
 ("M03", "dropped indexes ignored (every candidate survives every window)",
  r'''survivors = [c for c in cands if c not in dropped]''', r'''survivors = [c for c in cands]'''),
 ("M04", "parse window no longer enters the edge window",
  r'''"parse": set(lists["BULK_PARSE_INDEX_NAMES"]) | edge,''', r'''"parse": set(lists["BULK_PARSE_INDEX_NAMES"]),'''),
 ("M05", "ref window no longer enters the edge window",
  r'''"ref": set(lists["BULK_REF_INDEX_NAMES"]) | edge,''', r'''"ref": set(lists["BULK_REF_INDEX_NAMES"]),'''),
 ("M06", "edge window emptied",
  r'''"edge": edge,''', r'''"edge": set(),'''),
 ("M07", "verdict ignores the ref window",
  r'''hazard = static["parse"]["hazard"] or static["ref"]["hazard"]''', r'''hazard = static["parse"]["hazard"]'''),
 ("M08", "verdict ignores the parse window",
  r'''hazard = static["parse"]["hazard"] or static["ref"]["hazard"]''', r'''hazard = static["ref"]["hazard"]'''),
 ("M09", "measured layer never contributes to the verdict",
  r'''hazard = hazard or any(w["hazard"] for w in doc["measured"].values())''', r'''hazard = hazard'''),
 ("M10", "exit code always 0 on an evaluated run",
  r'''code = 1 if hazard else 0''', r'''code = 0'''),
 ("M11", "verdict label swapped (HAZARD<->SAFE)",
  r'''doc["verdict"] = "HAZARD" if hazard else "SAFE"''', r'''doc["verdict"] = "SAFE" if hazard else "HAZARD"'''),
 ("M12", "CANNOT_EVALUATE exits 1 instead of 2",
  '''except CannotEvaluate as exc:
        doc["error"] = str(exc)
        code = 2''', '''except CannotEvaluate as exc:
        doc["error"] = str(exc)
        code = 1'''),
 ("M13", "unexpected exception NOT fail-closed (exit 0)",
  '''doc["error"] = f"{type(exc).__name__}: {exc}"
        code = 2''', '''doc["error"] = f"{type(exc).__name__}: {exc}"
        code = 0'''),
 ("M14", "FK clause matching made case-sensitive",
  r'''REFERENCES\s+nodes\s*\(\s*id\s*\)", re.I)''', r'''REFERENCES\s+nodes\s*\(\s*id\s*\)")'''),
 ("M15", "index statement matching made case-sensitive",
  r'''\(([^)]*)\)", re.I''', r'''\(([^)]*)\)", 0'''),
 ("M16", "index column order suffix (DESC) no longer stripped",
  r'''cols = [c.strip().split()[0] for c in m.group(4).split(",")]''', r'''cols = [c.strip() for c in m.group(4).split(",")]'''),
 ("M17", "--dist no longer takes precedence over `npm root -g`",
  r'''dist = args.dist or find_default_dist()''', r'''dist = find_default_dist()'''),
 ("M18", "default-dist scan accepts a platform package without db/index.js",
  r'''if os.path.isfile(os.path.join(cand, "db", "index.js")):''', r'''if True:'''),
 ("M19", "missing @colbymchenry/codegraph install not detected",
  r'''if not os.path.isdir(base):''', r'''if False:'''),
 ("M20", "empty bulk list accepted",
  r'''if need not in lists or not lists[need]:''', r'''if need not in lists:'''),
 ("M21", "absent bulk list not detected",
  r'''if need not in lists or not lists[need]:''', r'''if False:'''),
 ("M22", "schema with no FK to nodes(id) accepted",
  r'''if not fks:''', r'''if False:'''),
 ("M23", "scaled-DB shape guard removed",
  r'''if notnull and dflt is None and not pk and name not in have:''', r'''if False:'''),
 ("M24", "shape guard also rejects NOT NULL columns that have a default",
  r'''if notnull and dflt is None and not pk and name not in have:''', r'''if notnull and not pk and name not in have:'''),
 ("M25", "shape guard also rejects NOT NULL PRIMARY KEY columns",
  r'''if notnull and dflt is None and not pk and name not in have:''', r'''if notnull and dflt is None and name not in have:'''),
 ("M26", "triggers no longer dropped before the bulk inserts",
  r'''c.execute(f'drop trigger if exists "{t}"')''', r'''pass'''),
 ("M27", "stale scratch DB no longer removed before building",
  '''if os.path.exists(path):
        os.remove(path)''', '''if False:
        os.remove(path)'''),
 ("M28", "scratch DB left behind after a successful measured run",
  '''    os.remove(db_path)
    return res''', '''    return res'''),
 ("M29", "temp scratch dir never removed",
  r'''shutil.rmtree(wd, ignore_errors=True)''', r'''pass'''),
 ("M30", "caller-supplied --work-dir deleted too",
  r'''if not args.work_dir:''', r'''if True:'''),
 ("M31", "median replaced by the maximum",
  r'''median = sorted(times)[len(times) // 2]''', r'''median = max(times)'''),
 ("M32", "hazard comparison inverted (median < threshold)",
  r'''"hazard": median > args.threshold_s}''', r'''"hazard": median < args.threshold_s}'''),
 ("M33", "only one REPLACE pick timed instead of three",
  r'''picks = (10, args.scale_nodes // 2, args.scale_nodes - 100)''', r'''picks = (10,)'''),
 ("M34", "ref window not measured",
  r'''for wname in ("parse", "ref"):''', r'''for wname in ("parse",):'''),
 ("M35", "INSERT OR REPLACE replaced by INSERT OR IGNORE (no delete, no cascade)",
  r'''insert or replace''', r'''insert or ignore'''),
 ("M36", "PRAGMA foreign_keys=ON turned OFF for the timed connection",
  r'''c.execute("pragma foreign_keys=ON")''', r'''c.execute("pragma foreign_keys=OFF")'''),
 ("M37", "surviving indexes not actually recreated in the measured DB (list still reported)",
  r'''c.execute(ddl[name])''', r'''pass'''),
 ("M38", "no surviving index chosen per served FK column",
  r'''survivors.add(f["survivors"][0])''', r'''pass'''),
 ("M39", "static-only run emits a (fake) measured section",
  '''        if not args.static_only:
            wd =''', '''        doc["measured"] = {}
        if not args.static_only:
            wd ='''),
 ("M40", "JSON document never printed to stdout",
  r'''    print(text)''', r'''    pass'''),
 ("M41", "--json-out file written empty",
  r'''fh.write(text + "\n")''', r'''fh.write("")'''),
 ("M42", "dist not echoed into the document",
  r'''doc["dist"] = dist''', r'''pass'''),
 ("M43", "echoed threshold hard-coded",
  r'''"threshold_s": args.threshold_s}''', r'''"threshold_s": 0.05}'''),
 ("M44", "default threshold changed",
  r'''"--threshold-s", type=float, default=0.05''', r'''"--threshold-s", type=float, default=0.5'''),
 ("M45", "static window verdict never flags a hazard",
  r'''"hazard": bool(unserved)}''', r'''"hazard": False}'''),
]
seen = set()
for mid, desc, old, new in M:
    n = src.count(old)
    if n != 1:
        print("%s\tNOT-APPLIED (anchor found %d times — update harness)\t%s" % (mid, n, desc))
        continue
    open("%s/%s.py" % (w, mid), "w", encoding="utf-8").write(src.replace(old, new))
    print("%s\tOK\t%s" % (mid, desc))
PY
if [ $? -ne 0 ]; then echo "mutant generation failed"; exit 1; fi

killed=0; total=0
while IFS=$'\t' read -r id status desc; do
    total=$((total + 1))
    case "$status" in
        OK) ;;
        *) echo "MUTANT $id $status $desc"; fail=1; continue ;;
    esac
    if cmp -s "$GOLD" "$W/$id.py"; then echo "MUTANT $id NOT-APPLIED (mutant is byte-identical to golden) $desc"; fail=1; continue; fi
    if run_suite "$W/$id.py"; then echo "MUTANT $id SURVIVED $desc"; fail=1
    else echo "MUTANT $id KILLED $desc"; killed=$((killed + 1)); fi
done <"$W/mutants.tsv"

SHA_AFTER=$(sha256sum "$GOLD" | cut -d' ' -f1)
if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then echo "REAL-TOOL sha256 unchanged ($SHA_AFTER)"
else echo "REAL-TOOL MODIFIED during the run ($SHA_BEFORE -> $SHA_AFTER)"; fail=1; fi
echo "TALLY mutants killed=$killed of $total"
if [ "$fail" -eq 0 ]; then echo "ALL MUTANTS KILLED — test_fk_cascade_probe.py is load-bearing"; fi
exit $fail
