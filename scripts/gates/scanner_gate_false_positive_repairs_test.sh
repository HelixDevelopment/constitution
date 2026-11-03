#!/usr/bin/env bash
# scanner_gate_false_positive_repairs_test.sh — test suite for the three
# root-cause false-positive repairs of the canon self-scan triage
# (docs/design/canon_self_scan_triage_2026_10_31.md), covering
# CM-DANGEROUS-COMBINATION-FAIL-CLOSED (§11.4.252) and
# CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245):
#   (a) third-party trees are pruned by default, with an explicit opt-in
#       (--include-third-party / *_INCLUDE_THIRD_PARTY=1). Operator decision
#       2026-11-01: ONLY helix-deps.yaml deps marked `third_party: true` (their
#       `path:`, else submodules/<name>) plus the directory names `third_party`
#       and `site-packages` are pruned; a bare .gitmodules path (own-org
#       submodule) is NOT pruned and is scanned;
#   (b) the oracle matcher parses only the closed-set annotation grammar,
#       never prose such as "Independent oracle: raw grep";
#   (c) `except X: pass` after a terminal `assert False` in a test is the
#       exception-assertion idiom, not a swallow (real swallows still flagged).
#
# Test types: unit (matcher / handler cases), integration (gate over fixture
# trees), e2e (canon root + consumer-shaped root), security (hostile
# .gitmodules paths), chaos (malformed manifests), stress, performance budget,
# determinism x3, idempotency. Golden-TRUE and golden-FALSE-with-carrier
# fixtures per §11.4.201. Each assertion names its oracle (SPECIFIED: the
# triage document / the repair contract; INVARIANT: determinism, idempotency).
#
# Env:
#   CM_REPAIR_TEST_GATE_DIR   directory holding the gates under test (default:
#                             this script's dir). The paired mutation test
#                             points it at a mutated copy.
#   CM_REPAIR_SKIP_E2E=1      skip the canon-root end-to-end legs (mutation runs)
# Exit: 0 all assertions hold; 1 otherwise. Side effects: mktemp -d sandbox only.
set -uo pipefail
export HELIX_TEST_MODE=1   # this test points gates at fixture tools/roots: guarded overrides (scripts/lib/gate_env_override.sh) need the test switch
export ORACLE_GUARD_STRICT=1   # oracle gate is ratchet-by-default; these fixtures test strict mode

HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GD="${CM_REPAIR_TEST_GATE_DIR:-$HERE}"
ORACLE="$GD/cm_oracle_strategy_named_and_independent.sh"
DCFC="$GD/cm_dangerous_combination_fail_closed.sh"
CANON="$(CDPATH= cd -- "$HERE/../.." && pwd)"
[ -f "$ORACLE" ] && [ -f "$DCFC" ] || { echo "META: gates missing in $GD" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_repair.XXXXXX")" || exit 2
: "${TMP:?}"
trap 'rm -rf -- "${TMP:?}"' EXIT

pass=0; fail=0; skip=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
skp() { skip=$((skip+1)); echo "SKIP $1"; }   # a skip is never counted as ok (§11.4.3)
bad() { fail=$((fail+1)); echo "FAIL $1"; }
# run_rc <cmd...> : sets RC and OUT
# gitify <dir> : the prune lib honours a manifest `third_party: true` mark only on a RECORDED gitlink (killpg scope
# review round 3). These fixtures are plain directories, so make each fixture root (and each nested manifest dir) a
# real git repo that records its third_party paths as gitlinks (index records, `update-index --cacheinfo`), and
# register nested repos as gitlinks of their parent so the walk reaches them. Idempotent; only under $TMP.
gitify() {
    local d="$1" m x p r par n pn recs u1 u2 u3 u4 tpf
    case "$d" in "$TMP"/*) ;; *) return 0 ;; esac
    [ -d "$d" ] || return 0
    # shellcheck disable=SC1091
    . "$HERE/../deps_manifest/helix_deps_tsv.sh"
    local GG=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git)
    [ -e "$d/.git" ] || "${GG[@]}" -C "$d" init -q . 2>/dev/null
    mapfile -t ms < <(find "$d" -name helix-deps.yaml -not -path '*/.git/*' -printf '%d %h\n' | sort -rn | cut -d' ' -f2-)
    for x in "${ms[@]}"; do
        [ -e "$x/.git" ] || "${GG[@]}" -C "$x" init -q . 2>/dev/null
        recs="$(cm_hdeps_tsv "$x/helix-deps.yaml" 2>/dev/null)" || continue
        while IFS=$'\x1f' read -r n p u1 u2 tpf; do
            [ "$tpf" = 1 ] || continue; pn="${p:-submodules/$n}"; pn="${pn%/}"
            "${GG[@]}" -C "$x" update-index --add --cacheinfo "160000,0123456789abcdef0123456789abcdef01234567,$pn" 2>/dev/null
        done <<<"$recs"
    done
    for x in "${ms[@]}"; do
        [ "$x" = "$d" ] && continue
        par="$(dirname "$x")"
        while [ "$par" != "$d" ] && [ ! -e "$par/.git" ]; do par="$(dirname "$par")"; done
        "${GG[@]}" -C "$par" update-index --add --cacheinfo "160000,0123456789abcdef0123456789abcdef01234567,${x#"$par"/}" 2>/dev/null
    done
}
run() { local a; for a in "$@"; do [ -d "$a" ] && gitify "$a"; done; OUT="$(nice -n 15 "$@" 2>&1)"; RC=$?; }
expect_rc() { # desc want cmd...
    local d="$1" w="$2"; shift 2; run "$@"
    if [ "$RC" = "$w" ]; then ok "$d"; else bad "$d (rc=$RC want $w)"; printf '%s\n' "$OUT" | head -5; fi
}
expect_out() { # desc grep-pattern(ERE) ; uses last OUT
    if grep -Eq -- "$2" <<<"$OUT"; then ok "$1"; else bad "$1 (pattern '$2' absent)"; fi
}
expect_noout() {
    if grep -Eq -- "$2" <<<"$OUT"; then bad "$1 (pattern '$2' present)"; else ok "$1"; fi
}

# ── fixture builders ─────────────────────────────────────────────────────────
GOODTEST='# oracle: SPECIFIED
def test_ok():
    assert 1 + 1 == 2
'
BADTEST='def test_unannotated():
    assert True
'
BADEXC='def f():
    try:
        g()
    except OSError:
        pass
'
mk_scope() { # dir : consumer-shaped root with a separate-repository subtree
    local d="$1"
    mkdir -p "$d/tests" "$d/submodules/vend" "$d/src"
    printf '%s' "$GOODTEST" > "$d/tests/test_first.py"
    printf '%s\n' 'x = 1' > "$d/src/clean.py"
    printf '%s' "$BADTEST" > "$d/submodules/vend/test_third.py"
    printf '%s' "$BADEXC" > "$d/submodules/vend/third.py"
    printf '[submodule "vend"]\n\tpath = submodules/vend\n\turl = git@example.invalid:o/vend.git\n' > "$d/.gitmodules"
    cat > "$d/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: vend
    ssh_url: git@example.invalid:o/vend.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: true
    licence: MIT
YML
}

echo "== (a) third-party pruning: unit/integration =="
S="$TMP/scope"; mk_scope "$S"
expect_rc "oracle default prunes third_party:true tree (golden-TRUE)" 0 "$ORACLE" --root "$S" --quiet
expect_rc "dcfc   default prunes third_party:true tree (golden-TRUE)" 0 "$DCFC" --root "$S" --quiet
expect_rc "oracle --include-third-party sees it (opt-in)" 1 "$ORACLE" --root "$S" --quiet --include-third-party
expect_rc "dcfc   --include-third-party sees it (opt-in)" 1 "$DCFC" --root "$S" --quiet --include-third-party
ORACLE_GUARD_INCLUDE_THIRD_PARTY=1 expect_rc "oracle env opt-in" 1 "$ORACLE" --root "$S" --quiet
DANGEROUS_COMBO_INCLUDE_THIRD_PARTY=1 expect_rc "dcfc env opt-in" 1 "$DCFC" --root "$S" --quiet
# golden-FALSE with carrier: a first-party violation is still flagged while pruning
S2="$TMP/scope_fp"; mk_scope "$S2"
printf '%s' "$BADTEST" > "$S2/tests/test_fp.py"; printf '%s' "$BADEXC" > "$S2/src/fp.py"
expect_rc "oracle still flags first-party violation" 1 "$ORACLE" --root "$S2" --quiet
expect_out "oracle first-party hit names tests/test_fp.py" 'tests/test_fp\.py'
expect_noout "oracle output never names the pruned tree" 'submodules/vend'
expect_rc "dcfc still flags first-party violation" 1 "$DCFC" --root "$S2" --quiet
expect_noout "dcfc output never names the pruned tree" 'submodules/vend'
# helix-deps third_party entries (no .gitmodules) are pruned; own-org entry is not
H="$TMP/hd"; mkdir -p "$H/submodules/tp" "$H/ext/bar" "$H/submodules/own"
printf '%s' "$BADTEST" > "$H/submodules/tp/test_a.py"; printf '%s' "$BADTEST" > "$H/ext/bar/test_b.py"
cat > "$H/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: tp
    ssh_url: git@example.invalid:x/tp.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: true
    licence: MIT
  - name: bar
    ssh_url: git@example.invalid:x/bar.git
    ref: abc
    why: "x"
    layout: grouped
    path: ext/bar
    third_party: true
    licence: MIT
  - name: own
    ssh_url: git@example.invalid:x/own.git
    ref: abc
    why: "x"
    layout: grouped
YML
expect_rc "helix-deps third_party:true (default + explicit path) pruned" 0 "$ORACLE" --root "$H" --quiet
printf '%s' "$BADTEST" > "$H/submodules/own/test_c.py"
expect_rc "helix-deps non-third-party entry still scanned (golden-FALSE)" 1 "$ORACLE" --root "$H" --quiet
expect_out "…and it is the own-org file" 'submodules/own/test_c\.py'
# consumer-shaped: constitution + submodules nested under a consumer root
C="$TMP/consumer"; mkdir -p "$C/constitution/scripts" "$C/app" "$C/submodules/lib"
printf '%s' "$BADTEST" > "$C/constitution/test_k.py"; printf '%s' "$BADTEST" > "$C/submodules/lib/test_l.py"
printf '%s' "$GOODTEST" > "$C/app/test_app.py"
printf '[submodule "c"]\n\tpath = constitution\n\turl = x\n[submodule "l"]\n\tpath = submodules/lib\n\turl = y\n' > "$C/.gitmodules"
expect_rc "consumer-shaped root: gitlinked but NOT third_party trees ARE scanned (own-org)" 1 "$ORACLE" --root "$C" --quiet
expect_out "…constitution/test_k.py reported" 'constitution/test_k\.py'
expect_out "…submodules/lib/test_l.py reported" 'submodules/lib/test_l\.py'
cat > "$C/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: lib
    ssh_url: git@example.invalid:x/lib.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: true
    licence: MIT
  - name: constitution
    ssh_url: git@example.invalid:x/c.git
    ref: abc
    why: "x"
    layout: flat
    path: constitution
    third_party: true
    licence: MIT
YML
expect_rc "consumer-shaped root: third_party:true entries pruned, app clean" 0 "$ORACLE" --root "$C" --quiet
# own-org submodule: in .gitmodules AND helix-deps WITHOUT third_party -> scanned
OW="$TMP/ownorg"; mkdir -p "$OW/submodules/mine" "$OW/submodules/gm_only" "$OW/third_party/t" "$OW/pkg/site-packages/s"
printf '%s' "$BADTEST" > "$OW/submodules/mine/test_m.py"; printf '%s' "$BADTEST" > "$OW/submodules/gm_only/test_g.py"
printf '%s' "$BADTEST" > "$OW/third_party/t/test_t.py"; printf '%s' "$BADTEST" > "$OW/pkg/site-packages/s/test_s.py"
printf '[submodule "mine"]\n\tpath = submodules/mine\n[submodule "gm_only"]\n\tpath = submodules/gm_only\n' > "$OW/.gitmodules"
printf 'schema_version: 1\ndeps:\n  - name: mine\n    ssh_url: git@example.invalid:x/mine.git\n    ref: a\n    why: "x"\n    layout: grouped\n' > "$OW/helix-deps.yaml"
expect_rc "own-org submodule scanned (golden-FALSE of the prune)" 1 "$ORACLE" --root "$OW" --quiet
expect_out "…own-org helix-deps entry file reported" 'submodules/mine/test_m\.py'
expect_out "…submodule absent from helix-deps.yaml is scanned" 'submodules/gm_only/test_g\.py'
expect_noout "…directory name third_party pruned" 'third_party/t'
expect_noout "…directory name site-packages pruned" 'site-packages'
printf '%s' "$BADEXC" > "$OW/submodules/mine/m.py"; printf '%s' "$BADEXC" > "$OW/submodules/gm_only/g.py"
expect_rc "dcfc own-org violation flagged" 1 "$DCFC" --root "$OW" --quiet
expect_out "…dcfc names submodules/mine/m.py" 'submodules/mine/m\.py'
expect_out "…dcfc names submodules/gm_only/g.py" 'submodules/gm_only/g\.py'
# lib unit: exact prune list
. "$GD/../lib/third_party_prune.sh"
eval "_real_$(declare -f cm_third_party_prune_paths)"
cm_third_party_prune_paths() { gitify "$1"; _real_cm_third_party_prune_paths "$@"; }
PL="$(cm_third_party_prune_paths "$H" | LC_ALL=C sort | tr '\n' ' ')"
[ "$PL" = "ext/bar site-packages submodules/tp third_party " ] && ok "lib unit: helix-deps prune list exact (+ dir names)" || bad "lib unit prune list: '$PL'"
PL2="$(cm_third_party_prune_paths "$OW" | LC_ALL=C sort | tr '\n' ' ')"
[ "$PL2" = "site-packages third_party " ] && ok "lib unit: .gitmodules paths never pruned" || bad "lib unit gitmodules-only list: '$PL2'"
# round 4: explicit `third_party: false` stays scanned; a trailing-slash path is normalised (reader + lib unit)
TF="$TMP/tfalse"; mkdir -p "$TF"
printf 'schema_version: 1\ndeps:\n  - name: mine\n    path: own/dir\n    third_party: false\n  - name: slashy\n    path: ext/baz/\n    third_party: true\n' > "$TF/helix-deps.yaml"
TFL="$(cm_third_party_prune_paths "$TF" | LC_ALL=C sort | tr '\n' ' ')"
[ "$TFL" = "ext/baz site-packages third_party " ] && ok "lib unit: explicit third_party:false not pruned; trailing slash normalised" || bad "lib unit false/slash list: '$TFL'"
# nested: own-org submodule's OWN manifest marks third_party (operator decision 2026-11-01)
N="$TMP/nest"; mkdir -p "$N/submodules/eng/submodules/vend" "$N/submodules/eng/ext/zz" "$N/submodules/eng/submodules/own" "$N/submodules/eng/submodules/tpd" "$N/submodules/rootvend/submodules/deep" "$N/tests"
printf '%s' "$BADTEST" > "$N/submodules/eng/submodules/vend/test_v.py"
printf '%s' "$BADTEST" > "$N/submodules/eng/ext/zz/test_z.py"
printf '%s' "$BADTEST" > "$N/submodules/eng/submodules/own/test_o.py"
printf '%s' "$BADTEST" > "$N/submodules/eng/submodules/tpd/test_t.py"
printf '%s' "$BADTEST" > "$N/submodules/rootvend/submodules/deep/test_d.py"
cat > "$N/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: eng
    ssh_url: git@github.com:o/eng.git
    ref: a
  - name: eng2
    ssh_url: git@github.com:o/eng2.git
    ref: a
    path: libs/eng2
  - name: rootvend
    ssh_url: git@github.com:x/rootvend.git
    ref: a
    third_party: true
YML
cat > "$N/submodules/eng/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: vend
    ssh_url: git@github.com:x/vend.git
    ref: a
    third_party: true
  - name: zz
    path: ext/zz
    third_party: true
  - name: own
    ssh_url: git@github.com:o/own.git
    ref: a
  - name: evil
    path: ../tests
    third_party: true
  - name: evil2
    path: /abs/x
    third_party: true
YML
printf 'schema_version: 1\ndeps:\n  - name: sneaky\n    third_party: true\n' > "$N/submodules/rootvend/helix-deps.yaml"
mkdir -p "$N/libs/eng2/submodules/vendx"; printf '%s' "$BADTEST" > "$N/libs/eng2/submodules/vendx/test_x.py"
printf 'schema_version: 1\ndeps:\n  - name: vendx\n    third_party: true\n' > "$N/libs/eng2/helix-deps.yaml"
printf '%s' "$BADTEST" > "$N/tests/test_keep.py"
NL="$(cm_third_party_prune_paths "$N" | LC_ALL=C sort | tr '\n' ' ')"
[ "$NL" = "libs/eng2/submodules/vendx site-packages submodules/eng/ext/zz submodules/eng/submodules/vend submodules/rootvend third_party " ] && ok "lib unit: nested third_party entries emitted with submodule prefix" || bad "lib unit nested list: '$NL'"
case "$NL" in *"../"*|*" / "*|*submodules/eng/submodules/own*|*sneaky*) bad "lib unit nested: hostile/own-org/third-party-manifest leaked: '$NL'" ;; *) ok "lib unit nested: hostile paths dropped, own-org kept, pruned submodule's manifest not read" ;; esac
run "$ORACLE" --root "$N" --quiet
expect_noout "nested third_party tree pruned (oracle)" 'submodules/eng/submodules/vend|submodules/eng/ext/zz'
expect_out "nested own-org (not marked) still scanned (oracle)" 'submodules/eng/submodules/own/test_o\.py'
expect_out "nested unlisted submodules/* dir still scanned (oracle)" 'submodules/eng/submodules/tpd/test_t\.py'
expect_out "hostile nested path does not prune first-party tests" 'tests/test_keep\.py'
# toggling third_party flag flips the verdict
sed -i 's/ref: a$/ref: a\n    third_party: true\n    licence: MIT/' "$OW/helix-deps.yaml"
printf '%s' "$BADTEST" > "$OW/submodules/mine/test_m.py"
run "$ORACLE" --root "$OW" --quiet
expect_noout "…marking the entry third_party:true now prunes it" 'submodules/mine/'
expect_out "…gm_only (still absent from helix-deps) stays scanned" 'submodules/gm_only/test_g\.py'

echo "== (F1) manifest parsing: keys not substrings; symlink guard; depth cap =="
K="$TMP/keys"; mkdir -p "$K/submodules"
cat > "$K/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: ownc
    ssh_url: git@github.com:o/ownc.git
    layout: grouped   # own-org, so NOT third_party: true
    why: "own-org; path: scripts and third_party: true appear only inside this text"
  - name: tpc
    ref: abc1234   # upstream docs path: scripts
    third_party: true   # path: docs
  - name: ownw
    why: >
      folded text that mentions
      third_party: true
      path: scripts
    ref: a
  - name: tpq
    path: "ext/q"   # quoted + commented
    third_party: "true"
meta:
    third_party: true
    path: scripts
YML
KL="$(cm_third_party_prune_paths "$K" | LC_ALL=C sort | tr '\n' ' ')"
[ "$KL" = "ext/q site-packages submodules/tpc third_party " ] && ok "F1 lib unit: comment/value text never read as path:/third_party: keys; block ends at next top-level key" || bad "F1 lib unit prune list: '$KL'"
# the real canon manifest has comment text such as 'third_party: true' / 'path: ...' (helix-deps.yaml ~95,110,267)
CL="$(cm_third_party_prune_paths "$CANON" | LC_ALL=C sort | tr '\n' ' ')"
case "$CL" in *" scripts "*|*" docs "*|*"submodules/llmctl "*|*"submodules/claude_toolkit "*) bad "F1 canon manifest: first-party/own-org dir pruned: '$CL'" ;; *"submodules/llmctl/submodules/llama.cpp"*) ok "F1 canon manifest: own-org not pruned, nested third-party pruned" ;; *) if [ -e "$CANON/submodules/llmctl/.git" ]; then bad "F1 canon manifest: nested llama.cpp missing: '$CL'"; else
       # llmctl is not populated in this checkout: the nested llama.cpp mark cannot be read (a recorded, POPULATED gitlink is
       # required). Real assertion that needs no population: the own-org parents are not pruned and no unrecorded
       # nested path was emitted; the nested-prune half is a SKIP, never an ok.
       case "$CL" in *"submodules/llmctl/"*|*"submodules/claude_toolkit/"*) bad "F1 canon manifest (unpopulated): nested path pruned without a populated parent: '$CL'" ;; *) ok "F1 canon manifest (unpopulated llmctl): own-org parents not pruned, nothing nested emitted unrecorded"; skp "F1 canon manifest: nested llama.cpp prune needs a populated llmctl (not populated here)" ;; esac
   fi ;; esac
# symlink guard: an own-org-looking submodules/* symlink and a symlinked manifest are never followed
L="$TMP/lnk"; mkdir -p "$L/submodules/real" "$TMP/lnk_out"
printf 'schema_version: 1\ndeps:\n  - name: evilsym\n    third_party: true\n' > "$TMP/lnk_out/helix-deps.yaml"
ln -s "$TMP/lnk_out" "$L/submodules/linkdir"
printf 'schema_version: 1\ndeps: []\n' > "$L/helix-deps.yaml"
ln -s "$TMP/lnk_out/helix-deps.yaml" "$L/submodules/real/helix-deps.yaml"
LL="$(cm_third_party_prune_paths "$L" | LC_ALL=C sort | tr '\n' ' ')"
[ "$LL" = "site-packages third_party " ] && ok "F1 symlinked submodule dir and symlinked manifest are never followed" || bad "F1 symlink guard: '$LL'"
# depth cap: manifests read at depth 0..3 only
D="$TMP/depth"; p="$D"
for lvl in root a b c d; do
    [ "$lvl" = root ] || { p="$p/submodules/$lvl"; }
    mkdir -p "$p"
    printf 'schema_version: 1\ndeps:\n  - name: t\n    third_party: true\n' > "$p/helix-deps.yaml"
done
DL="$(cm_third_party_prune_paths "$D" | LC_ALL=C sort | tr '\n' ' ')"
[ "$DL" = "site-packages submodules/a/submodules/b/submodules/c/submodules/t submodules/a/submodules/b/submodules/t submodules/a/submodules/t submodules/t third_party " ] && ok "F1 depth cap: manifests read through depth 3, level-4 manifest not read" || bad "F1 depth cap list: '$DL'"

echo "== (round 3) whole-list-item manifest parse; quoted '#'; root-anchored prune =="
# I1: a dep may OPEN with any key (ssh_url: first, name later); fields never leak onto the previous dep
W="$TMP/wholeitem"; mkdir -p "$W"
cat > "$W/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: ownA
    ssh_url: git@x:o/ownA.git
    layout: grouped
  - ssh_url: git@x:o/tpB.git
    third_party: true
    name: tpB
  - ssh_url: git@x:o/ownC.git
    path: src/ownC   # path first, no name
    layout: grouped
  - ref: abc
    name: tpD
    path: ext/tpd   # trailing comment is stripped
    third_party: true
  - ssh_url: "git@x:o/h.git"
    path: "vend#x"   # a '#' inside quotes is NOT a comment (then dropped as unsafe), never truncated to "vend"
    third_party: true
    name: hashy
transitive_handling:
  recursive: true
YML
WL="$(cm_third_party_prune_paths "$W" | LC_ALL=C sort | tr '\n' ' ')"
[ "$WL" = "ext/tpd site-packages submodules/tpB third_party " ] && ok "I1/M2 lib unit: dep opening with ssh_url:/ref:, any field order; quoted # kept (unsafe path dropped, not truncated)" || bad "I1/M2 prune list: '$WL'"
# M3: a manifest-derived path prunes only <root>/<path>, never a same-named first-party dir deeper in the tree
A="$TMP/anchored"; mkdir -p "$A/vend" "$A/app/vend" "$A/app/third_party_ok" "$A/other/third_party"
printf 'schema_version: 1\ndeps:\n  - name: v\n    path: vend\n    third_party: true\n' > "$A/helix-deps.yaml"
printf '%s' "$BADTEST" > "$A/vend/test_pruned.py"; printf '%s' "$BADTEST" > "$A/app/vend/test_first_party.py"; printf '%s' "$BADTEST" > "$A/other/third_party/test_namepruned.py"
run "$ORACLE" --root "$A" --quiet
expect_out "M3 oracle: first-party app/vend/ still scanned (single-segment path is root-anchored)" 'app/vend/test_first_party\.py'
expect_noout "M3 oracle: <root>/vend pruned" '/vend/test_pruned\.py'
expect_noout "M3 oracle: literal dir name third_party still pruned at any depth" 'test_namepruned'
printf '%s' "$BADEXC" > "$A/vend/x.py"; printf '%s' "$BADEXC" > "$A/app/vend/y.py"
run "$DCFC" --root "$A" --quiet
expect_out "M3 dcfc: first-party app/vend/y.py still scanned" 'app/vend/y\.py'
expect_noout "M3 dcfc: <root>/vend/x.py pruned" '/vend/x\.py'

echo "== (a) security: hostile .gitmodules / helix-deps paths =="
X="$TMP/sec"; mkdir -p "$X/tests" "$X/other"
printf '%s' "$BADTEST" > "$X/tests/test_s.py"
printf '[s "1"]\n\tpath = ../other\n[s "2"]\n\tpath = /\n[s "3"]\n\tpath = *\n[s "4"]\n\tpath = a b\n[s "5"]\n\tpath = -x\n[s "6"]\n\tpath = .\n[s "7"]\n\tpath = tests/../tests\n[s "8"]\n\tpath = ?est?\n[s "9"]\n\tpath = [t]ests\n' > "$X/.gitmodules"
cat > "$X/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - {name: a, path: ../other, third_party: true}
  - name: b
    path: /
    third_party: true
  - name: c
    path: "*"
    third_party: true
  - name: d
    path: "a b"
    third_party: true
  - name: e
    path: -x
    third_party: true
  - name: f
    path: .
    third_party: true
  - name: g
    path: tests/../tests
    third_party: true
  - name: h
    path: ?est?
    third_party: true
  - name: i
    path: "[t]ests"
    third_party: true
YML
expect_rc "hostile paths never prune first-party code (oracle)" 1 "$ORACLE" --root "$X" --quiet
expect_out "…tests/test_s.py still reported" 'tests/test_s\.py'
printf '%s' "$BADEXC" > "$X/tests/s.py"
expect_rc "hostile paths never prune first-party code (dcfc)" 1 "$DCFC" --root "$X" --quiet

echo "== (a) chaos: malformed manifests =="
K="$TMP/chaos"; mkdir -p "$K/tests"; printf '%s' "$BADTEST" > "$K/tests/test_c.py"
head -c 4096 /dev/urandom > "$K/.gitmodules"
printf '\x00\x01::: not yaml {{{\n  - [' > "$K/helix-deps.yaml"
expect_rc "binary .gitmodules + garbage helix-deps: no crash, violation kept (oracle)" 1 "$ORACLE" --root "$K" --quiet
: > "$K/.gitmodules"; rm -f "$K/helix-deps.yaml"
expect_rc "empty .gitmodules: violation kept" 1 "$ORACLE" --root "$K" --quiet
K2="$TMP/chaos2"; mkdir -p "$K2/tests"; printf '%s' "$GOODTEST" > "$K2/tests/test_g.py"; mkdir -p "$K2/.gitmodules.d"
ln -s /nonexistent "$K2/.gitmodules"
expect_rc "dangling-symlink .gitmodules: clean tree passes" 0 "$ORACLE" --root "$K2" --quiet

echo "== (b) oracle matcher: closed-set grammar vs prose =="
M="$TMP/m"; mkdir -p "$M"
cat > "$M/test_prose_only.py" <<'PY'
def test_raw():
    # Independent oracle: raw grep over the tree
    assert True

def test_the():
    """Checks it. The oracle: the reference output is compared."""
    assert True

def test_deepseek():
    # oracle: deepseek-v3 said so
    assert True

def test_single_word_prose():
    # Independent oracle: grep
    assert True
PY
run "$ORACLE" --root "$M" --quiet
[ "$RC" = 1 ] && ok "prose-only tests still FAIL (no real annotation)" || bad "prose-only rc=$RC"
expect_noout "prose never parsed as unknown strategy (RAW/THE/DEEPSEEK_V)" "not in the closed 7-member set"
expect_out "all four reported as missing annotation" 'no oracle-strategy annotation'
[ "$(printf '%s\n' "$OUT" | grep -c 'no oracle-strategy annotation')" = 4 ] && ok "exactly four missing-annotation hits" || bad "missing-annotation count != 4"
M2="$TMP/m2"; mkdir -p "$M2"
cat > "$M2/test_prose_then_real.py" <<'PY'
def test_a():
    """Independent oracle: raw grep (prose)."""
    # oracle: INVARIANT
    assert True
PY
expect_rc "prose line before a real annotation does not mask it" 0 "$ORACLE" --root "$M2" --quiet
M3="$TMP/m3"; mkdir -p "$M3"
cat > "$M3/test_forms.py" <<'PY'
def test_trailing():  # oracle: SPECIFIED
    assert True

# oracle: derived
def test_preceding():
    assert True

def test_doc():
    """Oracle: METAMORPHIC"""
    assert True

def test_doc2():
    """
    Verifies things.
    Oracle: golden-master
    """
    assert True

def test_paren():
    # oracle: SPECIFIED (RFC 3986 section 5)
    assert True

async def test_char():
    # ORACLE: Characterization # captured baseline
    assert True
PY
expect_rc "every legitimate annotation form still accepted (golden-TRUE)" 0 "$ORACLE" --root "$M3" --quiet
M4="$TMP/m4"; mkdir -p "$M4"
printf 'def test_v():\n    # oracle: VIBES\n    assert True\n' > "$M4/test_v.py"
expect_rc "malformed real annotation (VIBES) still FAILs" 1 "$ORACLE" --root "$M4" --quiet
expect_out "…as unknown strategy" "'VIBES' is not in the closed 7-member set"

echo "== (c) dangerous-combination: exception-assertion idiom =="
mk_c() { # dir
    mkdir -p "$1"
    cat > "$1/test_idiom.py" <<'PY'
import pytest

def test_plain():
    try:
        parse("bad")
        assert False, "must raise"
    except ValueError:
        pass

def test_bool_zero():
    try:
        parse("bad")
        assert 0
    except (ValueError, KeyError):
        pass

class TestX:
    def test_selffail(self):
        try:
            parse("bad")
            self.fail("must raise")
        except ValueError:
            pass

    def test_pytestfail(self):
        try:
            parse("bad")
            pytest.fail("must raise")
        except ValueError:
            pass

    def test_raise_ae(self):
        try:
            parse("bad")
            raise AssertionError("must raise")
        except ValueError:
            pass
PY
}
mk_c_bad() { # dir name body -> one golden-FALSE fixture per call
    mkdir -p "$1"; printf '%s' "$2" > "$1/$3.py"
}
IDIOM="$TMP/idiom"; mk_c "$IDIOM"
for mode in ast text; do
    if [ "$mode" = text ]; then export DANGEROUS_COMBO_PYTHON=/nonexistent/python; else unset DANGEROUS_COMBO_PYTHON; fi
    expect_rc "[$mode] assert-False idiom in tests is not a swallow (golden-TRUE)" 0 "$DCFC" --root "$IDIOM" --quiet
    n=0
    while IFS='|' read -r name body; do
        n=$((n+1)); d="$TMP/gf_${mode}_$n"
        mk_c_bad "$d" "$(printf '%b' "$body")" "$name"
        expect_rc "[$mode] golden-FALSE carrier still flagged: $name" 1 "$DCFC" --root "$d" --quiet
    done <<'CASES'
test_helper_not_test|def helper():\n    try:\n        g()\n        assert False\n    except ValueError:\n        pass\n
test_broad|def test_b():\n    try:\n        g()\n        assert False\n    except Exception:\n        pass\n
test_bare|def test_b():\n    try:\n        g()\n        assert False\n    except:\n        pass\n
test_assertionerror|def test_b():\n    try:\n        g()\n        assert False\n    except AssertionError:\n        pass\n
test_tuple_with_broad|def test_b():\n    try:\n        g()\n        assert False\n    except (ValueError, Exception):\n        pass\n
test_real_swallow|def test_b():\n    try:\n        g()\n    except OSError:\n        pass\n
test_assert_not_last|def test_b():\n    try:\n        assert False\n        g()\n    except ValueError:\n        pass\n
test_assert_true|def test_b():\n    try:\n        g()\n        assert True\n    except ValueError:\n        pass\n
test_silent_default|def test_b():\n    try:\n        g()\n        assert False\n    except ValueError:\n        return None\n
test_nested_assert|def test_b():\n    try:\n        g()\n        if x:\n            assert False\n    except ValueError:\n        pass\n
CASES
done
unset DANGEROUS_COMBO_PYTHON

echo "== e2e: canon root + consumer-shaped root =="
if [ "${CM_REPAIR_SKIP_E2E:-0}" != 1 ]; then
    run bash -c "cd '$TMP' && '$ORACLE' --root '$CANON' --quiet"
    expect_noout "e2e canon: oracle output never names third_party:true submodules" 'submodules/(superspec|open_design)/'
    ORC=$(printf '%s\n' "$OUT" | grep -c 'no oracle-strategy annotation')
    echo "     (oracle first-party missing-annotation count: $ORC)"
    run bash -c "cd '$TMP' && '$ORACLE' --root '$CANON' --quiet --include-third-party"
    expect_out "e2e canon: opt-in includes third_party:true submodules" 'submodules/(superspec|open_design)/'
    run bash -c "cd '$TMP' && '$DCFC' --root '$CANON' --quiet"
    expect_noout "e2e canon: dcfc output never names third_party:true submodules" 'submodules/(superspec|open_design)/'
fi

echo "== stress / performance budget / determinism x3 / idempotency =="
P="$TMP/perf"; mkdir -p "$P/tests" "$P/submodules/big"
printf '[s "b"]\n\tpath = submodules/big\n' > "$P/.gitmodules"
printf 'schema_version: 1\ndeps:\n  - name: big\n    ssh_url: x\n    ref: a\n    why: x\n    layout: grouped\n    third_party: true\n    licence: MIT\n' > "$P/helix-deps.yaml"
for i in $(seq 1 300); do
    { for j in $(seq 1 5); do printf '# oracle: SPECIFIED\ndef test_%s_%s():\n    assert True\n\n' "$i" "$j"; done; } > "$P/tests/test_$i.py"
done
for i in $(seq 1 200); do printf 'def test_u_%s():\n    # Independent oracle: raw grep\n    assert True\n' "$i" > "$P/submodules/big/test_$i.py"; done
t0=$(date +%s); run "$ORACLE" --root "$P" --quiet; t1=$(date +%s)
[ "$RC" = 0 ] && ok "stress: 1500 first-party tests + 200 pruned files pass" || bad "stress rc=$RC"
[ $((t1-t0)) -le 30 ] && ok "performance budget: oracle stress <= 30s ($((t1-t0))s)" || bad "performance budget ($((t1-t0))s)"
sum_tree() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum); }
B0="$(sum_tree "$S2")"
run "$ORACLE" --root "$S2" --quiet; O1="$OUT"
run "$ORACLE" --root "$S2" --quiet; O2="$OUT"
run "$ORACLE" --root "$S2" --quiet; O3="$OUT"
[ "$O1" = "$O2" ] && [ "$O2" = "$O3" ] && ok "determinism x3 (oracle): identical output" || bad "determinism oracle"
run "$DCFC" --root "$S2" --quiet; D1="$OUT"
run "$DCFC" --root "$S2" --quiet; D2="$OUT"
run "$DCFC" --root "$S2" --quiet; D3="$OUT"
[ "$D1" = "$D2" ] && [ "$D2" = "$D3" ] && ok "determinism x3 (dcfc): identical output" || bad "determinism dcfc"
[ "$B0" = "$(sum_tree "$S2")" ] && ok "idempotency/read-only: scanned tree byte-identical after 6 runs" || bad "gate mutated the tree"

echo "======================================================================"
echo "RESULT: $pass ok, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
