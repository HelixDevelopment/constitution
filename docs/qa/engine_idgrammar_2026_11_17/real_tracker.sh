#!/usr/bin/env bash
# real_tracker.sh BIN TREE OUT - CON-456 round 2 real-tracker check (scratch instrument).
# TREE is an extracted repository tree (docs/workable_items.db, docs/Issues.md,
# docs/Fixed.md). Works only on copies under OUT; never writes into TREE.
# Steps: validate; diff against the committed Markdown; repair-bodies --dry-run;
# export; md-to-db of the export into a copy (cycle 1); export again; md-to-db
# again (cycle 2); compare item keys, Markdown and description columns.
set -u
BIN="${1:?bin}"; TREE="${2:?tree}"; OUT="${3:?out}"
mkdir -p "$OUT"
log() { printf '%s\n' "$*" | tee -a "$OUT/summary.txt"; }
: > "$OUT/summary.txt"
cp "$TREE/docs/workable_items.db" "$OUT/db0.sqlite"
log "engine sha256: $(sha256sum "$BIN" | cut -c1-64)"
log "db0 sha256: $(sha256sum "$OUT/db0.sqlite" | cut -c1-64)"
log "db0 items: $(sqlite3 "$OUT/db0.sqlite" 'select count(*) from items;')"
( cd "$TREE" && "$BIN" validate --db "$OUT/db0.sqlite" ) >"$OUT/validate.out" 2>&1; log "validate rc=$?"
( cd "$TREE" && "$BIN" diff --db "$OUT/db0.sqlite" --issues "$TREE/docs/Issues.md" --fixed "$TREE/docs/Fixed.md" ) >"$OUT/diff.out" 2>&1; log "diff vs committed Markdown rc=$?"
( cd "$TREE" && "$BIN" repair-bodies --db "$OUT/db0.sqlite" --dry-run ) >"$OUT/repair_dry.out" 2>&1; log "repair-bodies --dry-run rc=$?"
( cd "$TREE" && "$BIN" sync db-to-md --db "$OUT/db0.sqlite" --out-issues "$OUT/Issues1.md" --out-fixed "$OUT/Fixed1.md" ) >"$OUT/export1.out" 2>&1; log "export 1 rc=$?"
diff -u "$TREE/docs/Issues.md" "$OUT/Issues1.md" >"$OUT/Issues_committed_vs_export1.diff"; log "committed Issues.md vs export 1: diff rc=$? lines=$(grep -c '^[-+][^-+]' "$OUT/Issues_committed_vs_export1.diff")"
diff -u "$TREE/docs/Fixed.md" "$OUT/Fixed1.md" >"$OUT/Fixed_committed_vs_export1.diff"; log "committed Fixed.md vs export 1: diff rc=$? lines=$(grep -c '^[-+][^-+]' "$OUT/Fixed_committed_vs_export1.diff")"
cp "$OUT/db0.sqlite" "$OUT/db1.sqlite"
( cd "$TREE" && "$BIN" sync md-to-db --db "$OUT/db1.sqlite" --issues "$OUT/Issues1.md" --fixed "$OUT/Fixed1.md" ) >"$OUT/import1.out" 2>&1; log "md-to-db cycle 1 rc=$?"
log "db1 items: $(sqlite3 "$OUT/db1.sqlite" 'select count(*) from items;')"
( cd "$TREE" && "$BIN" sync db-to-md --db "$OUT/db1.sqlite" --out-issues "$OUT/Issues2.md" --out-fixed "$OUT/Fixed2.md" ) >"$OUT/export2.out" 2>&1; log "export 2 rc=$?"
cmp -s "$OUT/Issues1.md" "$OUT/Issues2.md"; log "Issues export 1 == export 2: cmp rc=$?"
cmp -s "$OUT/Fixed1.md" "$OUT/Fixed2.md"; log "Fixed export 1 == export 2: cmp rc=$?"
cp "$OUT/db1.sqlite" "$OUT/db2.sqlite"
( cd "$TREE" && "$BIN" sync md-to-db --db "$OUT/db2.sqlite" --issues "$OUT/Issues2.md" --fixed "$OUT/Fixed2.md" ) >"$OUT/import2.out" 2>&1; log "md-to-db cycle 2 rc=$?"
log "db2 items: $(sqlite3 "$OUT/db2.sqlite" 'select count(*) from items;')"
( cd "$TREE" && "$BIN" validate --db "$OUT/db2.sqlite" ) >"$OUT/validate2.out" 2>&1; log "validate after two cycles rc=$?"
python3 -I - "$OUT" <<'PY' | tee -a "$OUT/summary.txt"
import sqlite3, sys, os
out = sys.argv[1]
def load(n):
    c = sqlite3.connect(os.path.join(out, n))
    r = {(a, l, p): (d, b, t, ty, st, sv)
         for a, l, p, d, b, t, ty, st, sv in c.execute(
             "select atm_id, current_location, coalesce(representation,'section'), coalesce(description,''),"
             " coalesce(body_md,''), coalesce(title,''), coalesce(type,''), coalesce(status,''), coalesce(severity,'') from items")}
    c.close()
    return r
d0, d1, d2 = load("db0.sqlite"), load("db1.sqlite"), load("db2.sqlite")
print("keys db0 == db1: %s (lost %d, new %d)" % (set(d0) == set(d1), len(set(d0) - set(d1)), len(set(d1) - set(d0))))
print("keys db1 == db2: %s" % (set(d1) == set(d2)))
names = ["description", "body", "title", "type", "status", "severity"]
for i, n in enumerate(names):
    c01 = sorted(k[0] for k in d0 if k in d1 and d0[k][i] != d1[k][i])
    c12 = sorted(k[0] for k in d1 if k in d2 and d1[k][i] != d2[k][i])
    print("%-11s changed db0->db1: %3d   db1->db2: %3d   %s" % (n, len(c01), len(c12), ("first: " + ", ".join(c01[:5])) if c01 else ""))
grow = [k[0] for k in d1 if k in d2 and len(d2[k][0]) > len(d1[k][0])]
print("descriptions longer after cycle 2 than after cycle 1: %d" % len(grow))
PY
