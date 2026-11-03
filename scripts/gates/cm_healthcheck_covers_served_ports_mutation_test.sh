#!/usr/bin/env bash
# cm_healthcheck_covers_served_ports_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-HEALTHCHECK-COVERS-SERVED-PORTS (§11.4.201 / §11.4.254).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-HEALTHCHECK-COVERS-SERVED-PORTS is NOT a bluff gate. Per §1.1 a
# gate is trusted only after its paired mutation has been OBSERVED to make it
# FAIL, and per §11.4.201(1) a false-positive REFUSAL is a FAIL-bluff exactly
# as a false-negative pass is a PASS-bluff — so BOTH polarities are exercised
# for every fixture pair here, including explicit NEGATIVE CONTROLS that the
# gate must NOT fire on.
#
# ── What is proven ───────────────────────────────────────────────────────────
#   FAIL-on-mutation:
#     1. the literal BOB-138 shape — one service serving two ports from one
#        process, health check probing only the first;
#     2. a declared service with no health check at all;
#     3. a substring near-miss — a health check probing 71870 while the
#        service serves 7187 (a scanner matching on substring would clear it);
#     4. an UNDECLARED compose service that has a health check and/or ports —
#        silence is not an exemption (§11.4.201(6));
#     5. a STALE manifest entry naming a service absent from the compose file;
#     6. ZERO services checked — the FALSE-NULL property (§11.4.201(6)): an
#        empty manifest must FAIL, never quietly pass;
#     7. ALL-EMPTY `serves` lists — the same false-null by a different route;
#     8. no python interpreter with PyYAML — the BLIND-GATE property: the gate
#        must FAIL, never SKIP and never PASS (§11.4.201(4));
#     9. a missing input file.
#   PASS-on-clean (negative controls — the gate MUST NOT fire):
#     A. a service whose health check legitimately covers ALL its served ports
#        (the primary §11.4.201(1) false-refusal guard);
#     B. a multi-service fixture where every service is fully covered, using
#        a mix of list-form and string-form `test:` and a multi-port probe;
#     C. a compose service with neither health check nor ports that is absent
#        from the manifest — it is not "undeclared", it publishes nothing.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_healthcheck_covers_served_ports_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no container runtime, no live port ever probed — every fixture
#   is inert YAML TEXT the gate reads, never a running service.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script, and a python interpreter with PyYAML (the
#   same dependency the gate itself declares). Parses clean under bash -n.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture pair
#       (the §1.1 proof holds).
#   1 — a fixture did not produce its expected verdict (bluff gate, or a
#       false-positive refusal).
#   2 — environment error (gate script missing, or no python with PyYAML, in
#       which case the meta-test cannot see and says so rather than passing).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.201 (the anchor enforced — (1) false-positive
#   refusal, (4) conservative-safe default, (6) a null is not evidence),
#   §11.4.254, §11.4.107(10) (self-validated analyzer: golden-good +
#   golden-bad + negative control), §11.4.28 (gate driven via flags, no
#   hardcoded project path).
#
# Classification: universal (§11.4.17).

set -uo pipefail
export HELIX_TEST_MODE=1   # this test points gates at fixture tools/roots: guarded overrides (scripts/lib/gate_env_override.sh) need the test switch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_healthcheck_covers_served_ports.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

# The meta-test needs the same YAML parser the gate needs. If it is absent the
# meta-test cannot SEE, and an unseeing meta-test must not report success
# (§11.4.201(6)) — it exits 2 (environment error), never 0.
META_PY=""
for cand in ${HEALTHCHECK_PORTS_PYTHON:-} python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import yaml' >/dev/null 2>&1; then
        META_PY="$cand"; break
    fi
done
if [ -z "$META_PY" ]; then
    echo "META: no python interpreter with PyYAML — the meta-test cannot exercise the gate," >&2
    echo "      so it reports an ENVIRONMENT ERROR rather than a pass (§11.4.201(6))." >&2
    exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hcports_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0

# run_gate <compose> <manifest> [python-candidates]
run_gate() {
    local compose="$1" manifest="$2" pycands="${3:-$META_PY}"
    HEALTHCHECK_PORTS_PYTHON="$pycands" \
        bash "$GATE" --compose "$compose" --manifest "$manifest" >/dev/null 2>&1
}

expect_fail() { # $1=desc $2=compose $3=manifest [$4=python-candidates]
    local desc="$1"
    if run_gate "$2" "$3" "${4:-$META_PY}"; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}

expect_pass() { # $1=desc $2=compose $3=manifest [$4=python-candidates]
    local desc="$1"
    if run_gate "$2" "$3" "${4:-$META_PY}"; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false-positive refusal, §11.4.201(1))"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-HEALTHCHECK-COVERS-SERVED-PORTS"
echo "anchors: §11.4.201 (guard asserts the real condition) / §11.4.254"
echo "fixtures under: $TMP"
echo "======================================================================"

# ===================================================================
# 1. The literal BOB-138 shape — one service, two served ports, health
#    check probes only the first. The mutation and its fix differ ONLY
#    in the health-check command, so the pair isolates the invariant.
# ===================================================================
mkdir -p "$TMP/bob138"
cat > "$TMP/bob138/compose.yml" <<'YML'
services:
  download-proxy:
    image: python:3.12-alpine
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O /dev/null http://localhost:7186/ || exit 1"]
YML
cat > "$TMP/bob138/manifest.yml" <<'YML'
schema_version: 1
services:
  download-proxy:
    serves: [7186, 7187]
YML
expect_fail "BOB-138 literal shape (serves 7186+7187, probes only 7186)" \
    "$TMP/bob138/compose.yml" "$TMP/bob138/manifest.yml"

mkdir -p "$TMP/bob138_fixed"
cat > "$TMP/bob138_fixed/compose.yml" <<'YML'
services:
  download-proxy:
    image: python:3.12-alpine
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O /dev/null http://localhost:7186/ && wget -q -O /dev/null http://localhost:7187/ || exit 1"]
YML
cp "$TMP/bob138/manifest.yml" "$TMP/bob138_fixed/manifest.yml"
expect_pass "BOB-138 fixed shape (health check probes BOTH served ports)" \
    "$TMP/bob138_fixed/compose.yml" "$TMP/bob138_fixed/manifest.yml"

# ===================================================================
# 2. A declared service with NO health check at all.
# ===================================================================
mkdir -p "$TMP/no_hc"
cat > "$TMP/no_hc/compose.yml" <<'YML'
services:
  api:
    image: alpine
    ports:
      - "8080:8080"
YML
cat > "$TMP/no_hc/manifest.yml" <<'YML'
schema_version: 1
services:
  api:
    serves: [8080]
YML
expect_fail "declared service with NO healthcheck at all" \
    "$TMP/no_hc/compose.yml" "$TMP/no_hc/manifest.yml"

# ===================================================================
# 3. Substring near-miss — serves 7187, probes 71870. A gate matching on
#    plain substring would clear this and pass a service whose real port
#    is never probed (a false-negative on the exact defect class).
# ===================================================================
mkdir -p "$TMP/substring"
cat > "$TMP/substring/compose.yml" <<'YML'
services:
  api:
    image: alpine
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:71870/health || exit 1"]
YML
cat > "$TMP/substring/manifest.yml" <<'YML'
schema_version: 1
services:
  api:
    serves: [7187]
YML
expect_fail "substring near-miss (serves 7187, probes 71870 — must NOT match inside)" \
    "$TMP/substring/compose.yml" "$TMP/substring/manifest.yml"

# ===================================================================
# 4. UNDECLARED compose service that has a health check and/or ports.
#    Silence is not an exemption (§11.4.201(6)).
# ===================================================================
mkdir -p "$TMP/undeclared"
cat > "$TMP/undeclared/compose.yml" <<'YML'
services:
  api:
    image: alpine
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/health || exit 1"]
  sidecar:
    image: alpine
    ports:
      - "9090:9090"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:9090/ || exit 1"]
YML
cat > "$TMP/undeclared/manifest.yml" <<'YML'
schema_version: 1
services:
  api:
    serves: [8080]
YML
expect_fail "UNDECLARED compose service with a healthcheck + ports" \
    "$TMP/undeclared/compose.yml" "$TMP/undeclared/manifest.yml"

# ===================================================================
# 5. STALE manifest entry — declared, but the service is gone from the
#    compose file. Left unreported, the gate silently stops covering it.
# ===================================================================
mkdir -p "$TMP/stale"
cat > "$TMP/stale/compose.yml" <<'YML'
services:
  api:
    image: alpine
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/health || exit 1"]
YML
cat > "$TMP/stale/manifest.yml" <<'YML'
schema_version: 1
services:
  api:
    serves: [8080]
  retired-worker:
    serves: [9999]
YML
expect_fail "STALE manifest entry (declared but absent from the compose file)" \
    "$TMP/stale/compose.yml" "$TMP/stale/manifest.yml"

# ===================================================================
# 6. FALSE-NULL property — ZERO services checked MUST FAIL. The compose
#    file has a service that publishes nothing (so it is legitimately not
#    "undeclared"), and the manifest declares nothing. The gate saw
#    NOTHING; a quiet zero is not a clean tree (§11.4.201(6)).
# ===================================================================
mkdir -p "$TMP/zero"
cat > "$TMP/zero/compose.yml" <<'YML'
services:
  batch-worker:
    image: alpine
    command: ["sleep", "infinity"]
YML
cat > "$TMP/zero/manifest.yml" <<'YML'
schema_version: 1
services: {}
YML
expect_fail "ZERO services checked (empty manifest) — blind, not clean" \
    "$TMP/zero/compose.yml" "$TMP/zero/manifest.yml"

# ===================================================================
# 7. FALSE-NULL by a second route — every declared entry has an EMPTY
#    `serves` list, so nothing is actually verified. An implementation
#    that counted skipped entries as "checked" would pass here.
# ===================================================================
mkdir -p "$TMP/zero_empty_serves"
cat > "$TMP/zero_empty_serves/compose.yml" <<'YML'
services:
  batch-worker:
    image: alpine
    command: ["sleep", "infinity"]
YML
cat > "$TMP/zero_empty_serves/manifest.yml" <<'YML'
schema_version: 1
services:
  batch-worker:
    serves: []
YML
expect_fail "ZERO services checked (all 'serves' lists empty) — blind, not clean" \
    "$TMP/zero_empty_serves/compose.yml" "$TMP/zero_empty_serves/manifest.yml"

# ===================================================================
# 8. BLIND-GATE property — no python interpreter with PyYAML. The gate
#    MUST FAIL, never SKIP and never PASS (§11.4.201(4)). The shim below
#    is a real executable that always refuses `import yaml`, which is the
#    exact condition the gate probes for.
# ===================================================================
mkdir -p "$TMP/nopyyaml"
cat > "$TMP/nopyyaml/python_without_yaml" <<'SH'
#!/usr/bin/env bash
# A python-shaped executable with no PyYAML: `-c 'import yaml'` always fails.
# Stands in for a host whose interpreter lacks the parser the gate needs.
exit 1
SH
chmod +x "$TMP/nopyyaml/python_without_yaml"
# The clean BOB-138 fixture is reused deliberately: the ONLY thing changed is
# the interpreter, so a PASS here would prove the gate skipped rather than
# refused. (This fixture PASSes with a real interpreter — proven at step 1.)
expect_fail "no python with PyYAML — BLIND gate must FAIL, not skip" \
    "$TMP/bob138_fixed/compose.yml" "$TMP/bob138_fixed/manifest.yml" \
    "$TMP/nopyyaml/python_without_yaml"

# ===================================================================
# 9. Missing input file — another way of being blind.
# ===================================================================
expect_fail "missing compose file (blind input)" \
    "$TMP/does_not_exist_compose.yml" "$TMP/bob138_fixed/manifest.yml"
expect_fail "missing manifest file (blind input)" \
    "$TMP/bob138_fixed/compose.yml" "$TMP/does_not_exist_manifest.yml"

# ===================================================================
# NEGATIVE CONTROL B (§11.4.201(1)) — a realistic multi-service fixture in
# which EVERY service's health check legitimately covers all its served
# ports. Exercises both `test:` spellings (list form and bare string form)
# and a genuine multi-port probe. The gate MUST NOT fire on any of it; a
# gate that refuses correct configuration is a FAIL-bluff.
# ===================================================================
mkdir -p "$TMP/neg_multi"
cat > "$TMP/neg_multi/compose.yml" <<'YML'
services:
  single-port:
    image: alpine
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/health || exit 1"]
  multi-port:
    image: alpine
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:7186/ && curl -fsS http://localhost:7187/ || exit 1"]
  string-form:
    image: alpine
    healthcheck:
      test: curl -fsS http://localhost:9117/api || exit 1
  no-ports-worker:
    image: alpine
    command: ["sleep", "infinity"]
YML
cat > "$TMP/neg_multi/manifest.yml" <<'YML'
schema_version: 1
services:
  single-port:
    serves: [8080]
  multi-port:
    serves: [7186, 7187]
  string-form:
    serves: [9117]
YML
expect_pass "negative control: every service fully covered (list + string test forms)" \
    "$TMP/neg_multi/compose.yml" "$TMP/neg_multi/manifest.yml"

# ===================================================================
# NEGATIVE CONTROL C (§11.4.201(1)) — the `no-ports-worker` above is in the
# compose file, is NOT in the manifest, and has neither a health check nor
# a `ports:` mapping. It publishes nothing, so it is not "undeclared" and
# must NOT be reported. This is asserted by the PASS at control B: had the
# undeclared-service rule been too broad, that fixture would have FAILed.
# The dedicated fixture below isolates it so the reason for a future
# failure is unambiguous.
# ===================================================================
mkdir -p "$TMP/neg_worker_only"
cat > "$TMP/neg_worker_only/compose.yml" <<'YML'
services:
  api:
    image: alpine
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/health || exit 1"]
  batch-worker:
    image: alpine
    command: ["sleep", "infinity"]
YML
cat > "$TMP/neg_worker_only/manifest.yml" <<'YML'
schema_version: 1
services:
  api:
    serves: [8080]
YML
expect_pass "negative control: port-less worker absent from manifest is not 'undeclared'" \
    "$TMP/neg_worker_only/compose.yml" "$TMP/neg_worker_only/manifest.yml"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-HEALTHCHECK-COVERS-SERVED-PORTS FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-HEALTHCHECK-COVERS-SERVED-PORTS is a bluff gate (see findings above)"
fi
exit "$rc"
