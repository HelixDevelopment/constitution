#!/usr/bin/env bash
# cm_continuum_resume_engine_present_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-CONTINUUM-RESUME-ENGINE-PRESENT (§11.4.207).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-CONTINUUM-RESUME-ENGINE-PRESENT is NOT a bluff gate. Builds a
# CLEAN disposable fixture (engine dir + go.mod + helix-deps.yaml with
# `deps: []` + a literal-free .go file) that MUST PASS, then applies FOUR
# independent mutations — each planted on a FRESH copy of the clean fixture —
# that MUST each individually FAIL the gate:
#   (1) engine directory entirely absent
#   (2) go.mod missing its `module ` declaration
#   (3) helix-deps.yaml missing / not declaring `deps: []`
#   (4) a project-specific literal (from the gate's own denylist) planted
#       inside a tracked .go file (decoupling violation)
#
# The pair only holds if the gate FAILs on all four mutations AND PASSes on
# the clean fixture — the §1.1 discriminator that every structural invariant
# is genuinely load-bearing, not a tautology.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_continuum_resume_engine_present_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree. Runtime checks (2e)/
#   (2f) of the gate under test naturally SKIP against these fixtures (no
#   *_test.go / no cmd/continuum present), so this meta-test exercises ONLY
#   the structural invariants (1a)-(1d), by design (see gate script header).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling cm_continuum_resume_engine_present.sh gate script.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.207, §11.4.28(C) (depth-1 carve-out),
#   §11.4.31 (helix-deps.yaml schema), §11.4.6 (no-guessing / zero literals).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs on all four mutations AND PASSes on the clean fixture.
#   1 — at least one expectation was violated.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_continuum_resume_engine_present.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_continuum_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() { # $1=desc  $2=root-dir
    local desc="$1" fixture_root="$2"
    if bash "$GATE" --root "$fixture_root" --quiet >/dev/null 2>&1; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2=root-dir
    local desc="$1" fixture_root="$2"
    if bash "$GATE" --root "$fixture_root" --quiet >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        note "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
        rc=1
    fi
}

# Builds a CLEAN fixture rooted at $1 (a constitution-root stand-in):
#   $1/submodules/continuum/{go.mod,helix-deps.yaml,pkg/clean.go}
build_clean_fixture() {
    local croot="$1"
    local eng="${croot}/submodules/continuum"
    mkdir -p "${eng}/pkg"
    printf 'module github.com/example/fake-continuum\n\ngo 1.22\n' > "${eng}/go.mod"
    printf 'schema_version: 1\nname: continuum\ndeps: []\n' > "${eng}/helix-deps.yaml"
    printf 'package pkg\n\n// Clean(): no project-specific literal here.\nfunc Clean() bool { return true }\n' > "${eng}/pkg/clean.go"
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-CONTINUUM-RESUME-ENGINE-PRESENT"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- CLEAN fixture: every structural invariant satisfied ---
CLEAN_ROOT="$TMP/clean"
build_clean_fixture "$CLEAN_ROOT"
expect_pass "engine present / clean fixture" "$CLEAN_ROOT"

# --- MUTATION 1: engine directory entirely absent ---
MUT1_ROOT="$TMP/mut1_no_dir"
mkdir -p "$MUT1_ROOT"
expect_fail "engine directory absent" "$MUT1_ROOT"

# --- MUTATION 2: go.mod missing its 'module ' declaration ---
MUT2_ROOT="$TMP/mut2_bad_gomod"
build_clean_fixture "$MUT2_ROOT"
printf 'this is not a real go.mod\n' > "${MUT2_ROOT}/submodules/continuum/go.mod"
expect_fail "go.mod without 'module ' declaration" "$MUT2_ROOT"

# --- MUTATION 3: helix-deps.yaml missing / not declaring deps: [] ---
MUT3_ROOT="$TMP/mut3_bad_deps"
build_clean_fixture "$MUT3_ROOT"
printf 'schema_version: 1\nname: continuum\ndeps:\n  - name: some-other-owned-repo\n' \
    > "${MUT3_ROOT}/submodules/continuum/helix-deps.yaml"
expect_fail "helix-deps.yaml declares a non-empty own-org dep" "$MUT3_ROOT"

# --- MUTATION 4: a project-specific literal planted in a tracked .go file ---
MUT4_ROOT="$TMP/mut4_literal"
build_clean_fixture "$MUT4_ROOT"
printf 'package pkg\n\n// Store path is /mnt/track1/atmosphere-t1 (a project-specific literal).\nfunc Bad() bool { return true }\n' \
    > "${MUT4_ROOT}/submodules/continuum/pkg/bad.go"
expect_fail "project-specific literal planted in engine source" "$MUT4_ROOT"

# LARGE-SELFCHECK — SIGPIPE x pipefail (§11.4.276(C) class member). The three
# selfcheck markers are on the FIRST lines of a ~400 KB selfcheck output. With
# `echo "$sc_out" | grep -q` under `set -o pipefail`, each grep exits at its
# marker while echo is still writing; echo takes SIGPIPE and pipefail turns a
# PASSING selfcheck into a false FAIL. A stub `go` on PATH supplies the output
# (no *_test.go in the fixture, so the race-test leg SKIPs). Repeated, and paired
# with the same large output carrying bad=PASS, which must still FAIL.
build_large_selfcheck_fixture() { # $1=root  $2=bad-marker value
    local croot="$1" eng="$1/submodules/continuum" stub="$1/stub_bin"
    build_clean_fixture "$croot"
    mkdir -p "${eng}/cmd/continuum" "$stub"
    printf 'package main\n\nfunc main() {}\n' > "${eng}/cmd/continuum/main.go"
    head -c 400000 /dev/zero | tr '\0' 'x' | fold -w 79 > "$croot/selfcheck_pad.txt"
    printf '#!/usr/bin/env bash\nprintf "good=PASS\\nbad=%s\\nnegctrl=PASS\\n"\ncat "%s"\n' "$2" "$croot/selfcheck_pad.txt" > "$stub/go"
    chmod +x "$stub/go"
}
LS_ROOT="$TMP/large_selfcheck"; build_large_selfcheck_fixture "$LS_ROOT" FAIL
ls_sz="$(PATH="$LS_ROOT/stub_bin:$PATH" go run ./cmd/continuum selfcheck | wc -c)"
[ "$ls_sz" -ge 300000 ] || { note "❌ META FAIL: LARGE-SELFCHECK stub output is only $ls_sz bytes (needs >= 300000)"; rc=1; }
for it in 1 2 3 4 5; do
    if PATH="$LS_ROOT/stub_bin:$PATH" bash "$GATE" --root "$LS_ROOT" --quiet >/dev/null 2>&1; then
        note "✅ META OK:   LARGE-SELFCHECK ($ls_sz B, markers first) PASSes — iteration $it"
    else
        note "❌ META FAIL: LARGE-SELFCHECK ($ls_sz B, markers first) FAILed — iteration $it (SIGPIPE x pipefail false FAIL)"
        rc=1
    fi
done
LSN_ROOT="$TMP/large_selfcheck_bad"; build_large_selfcheck_fixture "$LSN_ROOT" PASS
if PATH="$LSN_ROOT/stub_bin:$PATH" bash "$GATE" --root "$LSN_ROOT" --quiet >/dev/null 2>&1; then
    note "❌ META FAIL: LARGE-SELFCHECK with bad=PASS PASSed (the marker check is not load-bearing)"; rc=1
else
    note "✅ META OK:   LARGE-SELFCHECK with bad=PASS correctly FAILs"
fi

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-CONTINUUM-RESUME-ENGINE-PRESENT is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-CONTINUUM-RESUME-ENGINE-PRESENT failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
