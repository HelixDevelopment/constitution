#!/usr/bin/env bash
# ============================================================================
# test_resolve1.sh — RED/GREEN oracle for runner patch resolve1
# ============================================================================
# Purpose      Prove that the resolver's per-reference O(#files) file-list query
#              is gone WITHOUT changing a single resolution answer:
#                R1  ctx.getAllFiles() returns ONE frozen array per cache
#                    generation, element-wise == SELECT path FROM files ORDER BY path
#                R2  clearCaches() invalidates it (new rows visible, new array)
#                R3  initialize() invalidates it BEFORE detectFrameworks()
#                R4  real getAllFilePaths() queries during a full index do NOT grow
#                    with the number of references (stock: ~1 query per PascalCase
#                    `calls` ref once vue is detected) and stay <= R4_MAX
#                R5  vue.resolveComponent's .vue subset is derived once per file-list
#                    identity (probe counts files scanned per resolve call)
#                R6  resolution output (sorted edge dump sha256) is byte-identical
#                    to the STOCK package on a mixed-language fixture (vue present)
#                R7  same on a vue-free fixture
# Usage        bash test_resolve1.sh                       (builds DIST from STOCK)
#              DIST=<pkg dir> bash test_resolve1.sh        (test a given package;
#                                                          DIST=$STOCK gives the RED run)
#              ONLY=R1,R4 bash test_resolve1.sh
# Inputs       STOCK (default: globally installed @colbymchenry/codegraph-linux-x64),
#              DIST, TMPDIR (work area), R4_MAX (default 12)
# Outputs      RESULT lines + SUMMARY; exit 1 on any failure; evidence files in $W
# Side effects creates fixtures + throwaway .codegraph DBs + (without DIST) a
#              patched package copy, all under $TMPDIR; never touches any repo DB
# Dependencies bash, python3, the package's bundled node, fk_index_patch.py
# Cross-refs   ../runner_patches/resolve1.py, test_resolve1_{probe,drive,
#              count_hook,dump,fixture}.*, docs/scripts/resolve1.md
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
STOCK="${STOCK:-$(npm root -g)/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-x64}"
NODE="$STOCK/node"
R4_MAX="${R4_MAX:-12}"
W="$(t_workdir resolve1)"
echo "workdir $W"

if [ -z "${DIST:-}" ]; then
    DIST="$W/pkg_resolve1"
    HELIX_CODEGRAPH_RUNNER_DIR="$W" python3 "$CG_DIR/fk_index_patch.py" --src "$STOCK" \
        --dst "$DIST" --patches resolve1 > "$W/build.json" 2> "$W/build.err"
    [ $? -eq 0 ] || { t_bad BUILD "patched package built" "$(head -c 300 "$W/build.err")"; t_finish; exit; }
fi
echo "DIST=$DIST"

run_index() {
    # run_index <dist> <fixture> <label> — fresh full index, sequential resolve
    local dist="$1" fx="$2" out="$W/$3"
    rm -rf "$fx/.codegraph"
    COUNT_OUT="$out.cnt" CODEGRAPH_PARALLEL_RESOLVE_MIN=999999999 \
        "$NODE" --disable-warning=ExperimentalWarning --require "$HERE/test_resolve1_count_hook.js" \
        "$HERE/test_resolve1_drive.js" "$dist/lib/dist" "$fx" > "$out.out" 2> "$out.err"
    echo "rc=$?" >> "$out.out"
    python3 "$HERE/test_resolve1_dump.py" "$fx/.codegraph/codegraph.db" "$out" > "$out.dump" 2>&1
}
calls_of() { awk -F'getAllFilePaths=' '{split($2,a," "); s+=a[1]} END{print s+0}' "$W/$1.cnt"; }

probe() {
    # probe <fixture> <label> [vue] — index the fixture, then probe a COPY of its DB
    python3 "$HERE/test_resolve1_fixture.py" "$1" 300 20 --mixed $( [ -z "${3:-}" ] && echo --novue )
    run_index "$DIST" "$1" "$2"
    cp "$1/.codegraph/codegraph.db" "$W/$2.db"
    "$NODE" --disable-warning=ExperimentalWarning "$HERE/test_resolve1_probe.js" "$DIST/lib/dist" \
        "$W/$2.db" "$1" ${3:-} > "$W/$2.json" 2> "$W/$2.perr"
    cat "$W/$2.json"
}
jq_() { python3 -c "import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2]))" "$P" "$1"; }
if t_want R1 || t_want R2 || t_want R3; then P="$(probe "$W/fx_novue" probe_novue)"; echo "probe $P"; fi
if t_want R1; then
    [ "$(jq_ same)" = True ] && [ "$(jq_ frozen)" = True ] && [ "$(jq_ order_ok)" = True ]
    t_check R1 "one frozen ORDER BY path array per generation" $? "$P"
fi
if t_want R2; then
    [ "$(jq_ has_new_after_clear)" = True ] && [ "$(jq_ new_array_after_clear)" = True ]
    t_check R2 "clearCaches() invalidates the file list" $? "$P"
fi
if t_want R3; then
    [ "$(jq_ vue_before)" = False ] && [ "$(jq_ vue_after_init)" = True ]
    t_check R3 "initialize() re-detects frameworks against the current file set" $? "$P"
fi
if t_want R5; then
    P="$(probe "$W/fx_vue" probe_vue vue)"; echo "probe-vue $P"
    [ "$(jq_ vue)" = True ] && [ "$(jq_ vue_scan_2nd)" = 0 ] && [ "$(jq_ vue_resolve_ok)" = True ]
    t_check R5 "vue .vue subset derived once per file-list identity" $? "$P"
fi
if t_want R4; then
    F1="$W/fx_r100"; F4="$W/fx_r400"
    python3 "$HERE/test_resolve1_fixture.py" "$F1" 1500 100
    python3 "$HERE/test_resolve1_fixture.py" "$F4" 1500 400
    run_index "$DIST" "$F1" r100; run_index "$DIST" "$F4" r400
    c1="$(calls_of r100)"; c4="$(calls_of r400)"
    [ "$c1" -eq "$c4" ] && [ "$c4" -le "$R4_MAX" ] && grep -q '^rc=0' "$W/r400.out"
    t_check R4 "getAllFilePaths queries independent of #refs (<= $R4_MAX)" $? "refs100=$c1 refs400=$c4"
fi
eq_stock() {
    # eq_stock <id> <desc> <fixture-args...>
    local id="$1" desc="$2"; shift 2
    local fx="$W/fx_$id"; python3 "$HERE/test_resolve1_fixture.py" "$fx" "$@"
    run_index "$STOCK" "$fx" "${id}_stock"; run_index "$DIST" "$fx" "${id}_dist"
    local s d; s="$(cat "$W/${id}_stock.dump")"; d="$(cat "$W/${id}_dist.dump")"
    [ -n "$s" ] && [ "$s" = "$d" ] && ! grep -q 'edges=0 ' "$W/${id}_dist.dump" \
        && cmp -s "$W/${id}_stock.edges.tsv" "$W/${id}_dist.edges.tsv"
    t_check "$id" "$desc" $? "stock[$s] dist[$d]"
}
t_want R6 && eq_stock R6 "edge dump identical to stock (mixed, vue present)" 400 60 --mixed
t_want R7 && eq_stock R7 "edge dump identical to stock (mixed, no vue)" 400 60 --mixed --novue
t_finish
