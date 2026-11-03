#!/usr/bin/env bash
# scanner_gate_false_positive_repairs_test.sh — test suite for the three
# root-cause false-positive repairs of the canon self-scan triage
# (docs/design/canon_self_scan_triage_2026_10_31.md), covering
# CM-DANGEROUS-COMBINATION-FAIL-CLOSED (§11.4.252) and
# CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245):
#   (a) third-party / separate-repository trees are pruned by default, with an
#       explicit opt-in (--include-third-party / *_INCLUDE_THIRD_PARTY=1);
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

HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GD="${CM_REPAIR_TEST_GATE_DIR:-$HERE}"
ORACLE="$GD/cm_oracle_strategy_named_and_independent.sh"
DCFC="$GD/cm_dangerous_combination_fail_closed.sh"
CANON="$(CDPATH= cd -- "$HERE/../.." && pwd)"
[ -f "$ORACLE" ] && [ -f "$DCFC" ] || { echo "META: gates missing in $GD" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_repair.XXXXXX")" || exit 2
: "${TMP:?}"
trap 'rm -rf -- "${TMP:?}"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
# run_rc <cmd...> : sets RC and OUT
run() { OUT="$(nice -n 15 "$@" 2>&1)"; RC=$?; }
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
}

echo "== (a) third-party pruning: unit/integration =="
S="$TMP/scope"; mk_scope "$S"
expect_rc "oracle default prunes .gitmodules tree (golden-TRUE)" 0 "$ORACLE" --root "$S" --quiet
expect_rc "dcfc   default prunes .gitmodules tree (golden-TRUE)" 0 "$DCFC" --root "$S" --quiet
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
expect_rc "consumer-shaped root: gitlinked trees pruned, app clean" 0 "$ORACLE" --root "$C" --quiet

echo "== (a) security: hostile .gitmodules / helix-deps paths =="
X="$TMP/sec"; mkdir -p "$X/tests" "$X/other"
printf '%s' "$BADTEST" > "$X/tests/test_s.py"
printf '[s "1"]\n\tpath = ../other\n[s "2"]\n\tpath = /\n[s "3"]\n\tpath = *\n[s "4"]\n\tpath = a b\n[s "5"]\n\tpath = -x\n[s "6"]\n\tpath = .\n[s "7"]\n\tpath = tests/../tests\n[s "8"]\n\tpath = ?est?\n[s "9"]\n\tpath = [t]ests\n' > "$X/.gitmodules"
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
    expect_noout "e2e canon: oracle output never names submodules/" 'submodules/'
    ORC=$(printf '%s\n' "$OUT" | grep -c 'no oracle-strategy annotation')
    echo "     (oracle first-party missing-annotation count: $ORC)"
    run bash -c "cd '$TMP' && '$ORACLE' --root '$CANON' --quiet --include-third-party"
    expect_out "e2e canon: opt-in includes submodules/" 'submodules/'
    run bash -c "cd '$TMP' && '$DCFC' --root '$CANON' --quiet"
    expect_noout "e2e canon: dcfc output never names submodules/" 'submodules/'
fi

echo "== stress / performance budget / determinism x3 / idempotency =="
P="$TMP/perf"; mkdir -p "$P/tests" "$P/submodules/big"
printf '[s "b"]\n\tpath = submodules/big\n' > "$P/.gitmodules"
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
echo "RESULT: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
