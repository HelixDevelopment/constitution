#!/usr/bin/env bash
# ============================================================================
# test_resolve2.sh — RED/GREEN oracle for runner patch resolve2 (ATM-1030)
# ============================================================================
# Purpose      Prove the Swift->ObjC bridge no longer materializes (and pins) the
#              whole `method` node set — the 3.48M-row getNodesByKind('method')
#              that OOMs the V8 heap on the real index — WITHOUT changing an answer:
#                Q1  after driving the bridge, queries.getNodesByKind('method') was
#                    NOT called and resolver.nodesByKindCache holds no 'method'
#                Q2  bridge targets (order-sensitive: 3 .m files define each selector,
#                    plus same-named NON-objc Java methods that index FIRST) are
#                    identical to the STOCK package's
#                Q3  full-index sorted edge+ref dump byte-identical to STOCK
#                Q4  (REAL=<db> only) 200 real pending refs from REAL_OFF resolve
#                    under the DEFAULT heap without OOM (stock/resolve1: FATAL OOM)
# Usage        bash test_resolve2.sh                  (builds DIST from STOCK)
#              DIST=<pkg dir> bash test_resolve2.sh   (DIST=<resolve1 runner> = RED run)
#              REAL=<immutable db> REAL_ROOT=<root> REAL_OFF=<rowid> bash test_resolve2.sh
#              ONLY=Q1,Q2 bash test_resolve2.sh
# Inputs       STOCK (default: global @colbymchenry/codegraph-linux-x64), DIST, TMPDIR
# Outputs      RESULT lines + SUMMARY; exit 1 on any failure; evidence files in $W
# Side effects fixtures + throwaway .codegraph DBs + (without DIST) a patched package
#              under $TMPDIR; Q4 opens REAL immutable read-only; never writes any repo DB
# Dependencies bash, python3, the package's bundled node, fk_index_patch.py
# Cross-refs   ../runner_patches/resolve2.py, test_resolve2_{fixture.py,probe.js},
#              test_resolve1_{drive.js,dump.py,count_hook.js}, test_resolve2_mutations.sh
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
STOCK="${STOCK:-$(npm root -g)/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-x64}"
NODE="$STOCK/node"
W="$(t_workdir resolve2)"
echo "workdir $W"
if [ -z "${DIST:-}" ]; then
    DIST="$W/pkg_resolve2"
    HELIX_CODEGRAPH_RUNNER_DIR="$W" python3 "$CG_DIR/fk_index_patch.py" --src "$STOCK" \
        --dst "$DIST" --patches resolve2 > "$W/build.json" 2> "$W/build.err"
    [ $? -eq 0 ] || { t_bad BUILD "patched package built" "$(head -c 300 "$W/build.err")"; t_finish; exit; }
fi
echo "DIST=$DIST"
FX="$W/fx"
python3 "$HERE/test_resolve2_fixture.py" "$FX" 500 > /dev/null
run_index() {
    # run_index <dist> <label> — fresh full index of $FX, sequential resolve, canonical dump
    local out="$W/$2"
    rm -rf "$FX/.codegraph"
    CODEGRAPH_PARALLEL_RESOLVE_MIN=999999999 "$NODE" --disable-warning=ExperimentalWarning \
        "$HERE/test_resolve1_drive.js" "$1/lib/dist" "$FX" > "$out.out" 2> "$out.err"
    echo "rc=$?" >> "$out.out"
    python3 "$HERE/test_resolve1_dump.py" "$FX/.codegraph/codegraph.db" "$out" > "$out.dump" 2>&1
    cp "$FX/.codegraph/codegraph.db" "$out.db"
}
probe() { "$NODE" --disable-warning=ExperimentalWarning "$HERE/test_resolve2_probe.js" "$1/lib/dist" "$2" "$FX" 2> "$W/$3.perr"; }
jget() { python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1]).get(sys.argv[2]), sort_keys=True))" "$1" "$2"; }
run_index "$STOCK" stock; run_index "$DIST" dist
PS="$(probe "$STOCK" "$W/stock.db" probe_stock)"; PD="$(probe "$DIST" "$W/stock.db" probe_dist)"
echo "probe-stock $PS"; echo "probe-dist  $PD"
if t_want Q1; then
    [ "$(jget "$PD" methodMaterialized)" = false ] && [ "$(jget "$PD" methodCached)" = false ] \
        && [ "$(jget "$PS" methodMaterialized)" = true ]
    t_check Q1 "bridge never materializes/pins the method node set (stock does)" $? "$PD"
fi
if t_want Q2; then
    T="$(jget "$PD" targets)"
    [ "$T" = "$(jget "$PS" targets)" ] && printf '%s' "$T" | grep -q 'objc/ObjA.m|playWithSong:'
    t_check Q2 "bridge targets identical to stock (order + objc filter)" $? "dist=$T"
fi
if t_want Q3; then
    s="$(cat "$W/stock.dump")"; d="$(cat "$W/dist.dump")"
    [ -n "$s" ] && [ "$s" = "$d" ] && grep -q '^rc=0' "$W/dist.out" \
        && cmp -s "$W/stock.edges.tsv" "$W/dist.edges.tsv" && cmp -s "$W/stock.refs.tsv" "$W/dist.refs.tsv"
    t_check Q3 "full-index edge+ref dump byte-identical to stock" $? "stock[$s] dist[$d]"
fi
if t_want Q4 && [ -n "${REAL:-}" ]; then
    "$DIST/node" --liftoff-only "$HERE/test_resolve1_equiv_real.js" "$DIST/lib/dist" "$REAL" \
        "${REAL_ROOT:?REAL_ROOT}" "${REAL_OFF:-9970864}" 200 > "$W/q4.tsv" 2> "$W/q4.err"
    rc=$?; [ $rc -eq 0 ] && ! grep -q 'heap out of memory' "$W/q4.err" && [ "$(wc -l < "$W/q4.tsv")" -eq 200 ]
    t_check Q4 "real refs from rowid ${REAL_OFF:-9970864} resolve under default heap" $? "rc=$rc $(head -c 160 "$W/q4.err")"
fi
t_finish
