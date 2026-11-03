#!/usr/bin/env bash
# cm_healthcheck_covers_served_ports.sh — CM-HEALTHCHECK-COVERS-SERVED-PORTS
# gate (anchors §11.4.201 guard-asserts-the-real-condition, §11.4.254
# boot-time invariants / capability matrix).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Assert that every port a compose service SERVES appears in that service's
# health check. A health check that probes only a SUBSET of the ports its
# service serves asserts a PROXY signal ("one port answers") in place of the
# REAL condition ("this service is serving"), so the container can report
# healthy indefinitely while its primary capability is dead. §11.4.201 names
# that class directly: a guard MUST assert the real condition it CLAIMS,
# resolved from the authoritative source, never from a proxy signal that
# something which is NOT the condition can satisfy.
#
# ── Forensic anchor (BOB-138, measured 2026-08-20) ──────────────────────────
# In a consuming project a single service served TWO ports from ONE process
# but its health check probed only the first. Live measurement on a container
# reporting "Up 4 hours (healthy)":
#     curl --max-time 6 localhost:<port-A>/  -> HTTP 200 in 0.096s
#     curl --max-time 6 localhost:<port-B>/  -> HTTP 000 after 6.0s
# The capability behind port B — the product's primary user-facing capability
# — had been dead for roughly two hours and no signal anywhere in the stack
# could see it. The health check was green the entire time.
#
# ── Why the served set is DECLARED, not DERIVED (§11.4.6 / §11.4.201(1)) ────
# Deriving the served set from the compose file is not universally possible
# and, where attempted naively, produces a FALSE-POSITIVE REFUSAL — which
# §11.4.201(1) forbids exactly as firmly as a false pass:
#   * a service on `network_mode: host` has NO `ports:` mapping to derive from;
#   * the only port numbers in such a service block are environment variables,
#     and those mix two DIFFERENT meanings that no syntactic rule separates —
#     a port the service SERVES vs. a port it merely CONNECTS TO upstream.
#     Sweeping `*_PORT` would demand a health check for a dependency's port.
# The served set therefore comes from a consumer-owned MANIFEST supplied as
# DATA (§11.4.35). This engine never guesses it.
#
# ── Universality (§11.4.17 / §11.4.28 / §11.4.35 / §11.4.177) ───────────────
# This engine carries NO project literal. Both the compose file and the
# manifest are INPUTS; the python interpreter candidates are an INPUT. Every
# consuming project supplies its own paths and scope as DATA and consumes this
# engine BY REFERENCE (§11.4.177 — never a copy, a copy diverges silently).
#
# ── Manifest schema (consumer DATA) ─────────────────────────────────────────
#   schema_version: 1
#   services:
#     <compose-service-name>:
#       serves: [<port>, <port>, ...]   # ports THIS service serves
#       # any other keys (container_name, comments, provenance) are ignored
# A manifest entry with an empty/absent `serves` list is skipped, and skipped
# entries do NOT count toward the checked total (see the zero-services rule).
#
# ── What is reported as a finding ───────────────────────────────────────────
#   1. a declared service whose health check does not probe every served port
#      (the BOB-138 defect class);
#   2. a declared service with NO health check at all;
#   3. a manifest entry ABSENT from the compose file (a stale declaration —
#      the gate would otherwise silently stop covering a real service);
#   4. a compose service that has a health check and/or `ports:` but is
#      UNDECLARED in the manifest — silence is never an exemption
#      (§11.4.201(6): a blind gate and a clean tree both return a quiet zero).
#
# ── Two properties that make this a guard and not a decoration ──────────────
# Both are load-bearing and MUST NOT degrade to a SKIP or a PASS:
#   A. ZERO SERVICES CHECKED  => FAIL. A quiet zero from a blind instrument is
#      indistinguishable from a clean tree (§11.4.201(6) FALSE-NULL). An empty
#      manifest, an all-empty `serves` set, or a compose file with no matching
#      services means the gate SAW NOTHING — that is never reported as a pass.
#   B. NO PYTHON WITH PyYAML  => FAIL. Without a YAML parser the gate cannot
#      read the compose file, so it cannot assert anything. §11.4.201(4)'s
#      conservative-safe default on an unresolvable signal is to REFUSE and
#      say so honestly — never to skip, which would read as green.
# A missing input file (compose or manifest) FAILs for the same reason.
#
# ── Port matching ───────────────────────────────────────────────────────────
# A served port matches only as a WHOLE number: 7187 never matches inside
# 71870 or 17187. A substring match would clear a health check that probes an
# entirely different port — a false-negative pass on the exact defect class
# this gate exists to close.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_healthcheck_covers_served_ports.sh --compose <file> --manifest <file>
#                                         [--quiet]
#   cm_healthcheck_covers_served_ports.sh -h | --help
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   HEALTHCHECK_PORTS_COMPOSE    compose file path   (else --compose; required)
#   HEALTHCHECK_PORTS_MANIFEST   manifest file path  (else --manifest; required)
#   HEALTHCHECK_PORTS_PYTHON     space-separated interpreter candidates tried
#                                in order; the first that can `import yaml`
#                                wins (default: "python3 python"). A consumer
#                                with a project virtualenv passes its
#                                interpreter FIRST as scope DATA — the engine
#                                never guesses a venv path.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   stdout : one "  ok  <service>: ..." line per covered service, then the
#            final verdict line, which is ALWAYS LAST:
#              CM-HEALTHCHECK-COVERS-SERVED-PORTS: PASS (N services verified)
#   stderr : "CM-HEALTHCHECK-COVERS-SERVED-PORTS: FAIL" plus one "  - ..."
#            line per finding, naming the offending service and ports.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS  (>=1 service checked, every served port probed)
#   1 — FAIL  (a finding, zero services checked, a missing input, or no
#              usable YAML parser)
#   2 — ERROR (usage error: unknown flag, or a required input not supplied)
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None. Read-only: the gate parses FILES. It never contacts a network, never
#   talks to a container runtime, and never probes a live port — so it is safe
#   to run at pre-build time with nothing running.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, and a python interpreter with PyYAML. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.201 (guard asserts the real condition; (1) false-positive refusal is
#   a FAIL-bluff; (4) conservative-safe default with an honest reason; (6) a
#   null is not evidence), §11.4.254 (boot-time invariants + capability
#   matrix), §11.4.6 (no guessing), §11.4.17 (universal classification),
#   §11.4.28/§11.4.35 (decoupled engine, consumer-owned DATA),
#   §11.4.177 (consumed by reference, never copied), §11.4.107(10)/§1.1 (the
#   paired mutation test alongside this file), §11.4.238 (BOB-138 was found
#   out-of-band; this gate is the automated check that closes that escape).
#
# Classification: universal (§11.4.17).

set -euo pipefail

GATE="CM-HEALTHCHECK-COVERS-SERVED-PORTS"

print_help() { sed -n '2,120p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; }

COMPOSE_FILE="${HEALTHCHECK_PORTS_COMPOSE:-}"
MANIFEST="${HEALTHCHECK_PORTS_MANIFEST:-}"
# verdict-affecting ambient overrides are guarded (11.4.201(6)-(8)): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set PY_CANDIDATES HEALTHCHECK_PORTS_PYTHON "python3 python" value   # a fake interpreter would decide the verdict; --python stays honoured
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)     print_help; exit 0 ;;
        --compose)     COMPOSE_FILE="${2:-}"; shift 2 ;;
        --manifest)    MANIFEST="${2:-}";     shift 2 ;;
        --python)      PY_CANDIDATES="${2:-}"; shift 2 ;;
        --quiet)       QUIET=1; shift ;;
        --)            shift ;;
        *)
            echo "${GATE}: ERROR — unknown argument: $1" >&2
            echo "  usage: $(basename "${BASH_SOURCE[0]:-$0}") --compose <file> --manifest <file> [--quiet]" >&2
            exit 2
            ;;
    esac
done

# §11.4.6: the engine carries no project literal, so it cannot invent a path.
# An unsupplied required input is a usage ERROR, never a silent default.
if [ -z "$COMPOSE_FILE" ] || [ -z "$MANIFEST" ]; then
    echo "${GATE}: ERROR — both --compose and --manifest are required" >&2
    echo "  (this engine is project-agnostic: it never guesses a consumer's paths, §11.4.28/§11.4.35)" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Resolve a python interpreter that can actually parse YAML.
# The probe is `import yaml` through the SAME interpreter that will run the
# analysis — presence of a binary named python3 proves nothing about PyYAML
# (§11.4.201(11): probe the artifact through its real invocation path).
# ---------------------------------------------------------------------------
PY=""
for cand in $PY_CANDIDATES; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import yaml' >/dev/null 2>&1; then
        PY="$cand"; break
    fi
done

# Property B (see header): a blind gate is a FAIL, never a SKIP and never a
# PASS. §11.4.201(4) — take the conservative-safe outcome and say so honestly.
if [ -z "$PY" ]; then
    echo "${GATE}: FAIL — no python interpreter with PyYAML available" >&2
    echo "  tried: ${PY_CANDIDATES}" >&2
    echo "  the gate cannot parse the compose file, so it cannot assert anything." >&2
    echo "  This is a BLIND gate, not a clean tree (§11.4.201(6))." >&2
    exit 1
fi

exec "$PY" - "$COMPOSE_FILE" "$MANIFEST" "$QUIET" <<'PYEOF'
import sys, re, pathlib

GATE = "CM-HEALTHCHECK-COVERS-SERVED-PORTS"

try:
    import yaml
except ImportError:
    # Defence in depth: the shell probe above already resolved an interpreter
    # that could import yaml, but if that ever changes underneath us the
    # answer is still FAIL-because-blind, never a skip (§11.4.201(6)).
    print(f"{GATE}: FAIL — PyYAML missing in the resolved interpreter (blind gate)", file=sys.stderr)
    sys.exit(1)

compose_path = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
quiet = sys.argv[3] == "1"

for p in (compose_path, manifest_path):
    if not p.is_file():
        print(f"{GATE}: FAIL — missing input: {p}", file=sys.stderr)
        sys.exit(1)

try:
    compose = yaml.safe_load(compose_path.read_text()) or {}
    manifest = yaml.safe_load(manifest_path.read_text()) or {}
except yaml.YAMLError as exc:
    # An unparseable input is another way of being blind, and blind is FAIL.
    print(f"{GATE}: FAIL — could not parse YAML input: {exc}", file=sys.stderr)
    sys.exit(1)

services = compose.get("services") or {}
declared = manifest.get("services") or {}

findings, checked = [], 0

for name, decl in declared.items():
    serves = [int(p) for p in ((decl or {}).get("serves") or [])]
    if not serves:
        # An empty declaration asserts nothing, so it must not COUNT as a
        # check either — otherwise an all-empty manifest would satisfy the
        # zero-services rule while having verified nothing.
        continue
    svc = services.get(name)
    if svc is None:
        findings.append(f"{name}: declared in the manifest but ABSENT from {compose_path.name} "
                        f"(stale manifest entry — remove it or restore the service)")
        continue

    hc = svc.get("healthcheck") or {}
    test = hc.get("test")
    if not test:
        findings.append(f"{name}: serves {serves} but declares NO healthcheck at all")
        continue
    blob = " ".join(str(t) for t in test) if isinstance(test, list) else str(test)

    # Match the port as a whole number so 7187 never matches inside 71870.
    missing = [p for p in serves if not re.search(rf"(?<!\d){p}(?!\d)", blob)]
    checked += 1
    if missing:
        findings.append(
            f"{name}: serves {serves} but its healthcheck probes none of {missing}\n"
            f"      healthcheck: {blob}\n"
            f"      -> a dead port in {missing} reports HEALTHY forever (§11.4.201 proxy signal)"
        )
    elif not quiet:
        print(f"  ok  {name}: healthcheck covers all served ports {serves}")

# A service that publishes ports but is absent from the manifest is UNDECLARED,
# not exempt — silence is never an exemption (§11.4.201(6)).
for name, svc in services.items():
    if name in declared:
        continue
    svc = svc or {}
    if svc.get("healthcheck") or svc.get("ports"):
        findings.append(f"{name}: has a healthcheck and/or ports but is UNDECLARED in "
                        f"{manifest_path.name} — add its served ports (silence is not an exemption)")

if findings:
    print(f"{GATE}: FAIL", file=sys.stderr)
    for f in findings:
        print(f"  - {f}", file=sys.stderr)
    sys.exit(1)

if checked == 0:
    # Property A (see header). §11.4.201(6): zero services checked means the
    # gate saw nothing. A quiet zero from a blind instrument is
    # indistinguishable from a clean tree.
    print(f"{GATE}: FAIL — checked 0 services; the gate is "
          "blind (empty manifest or no matching services), not clean", file=sys.stderr)
    sys.exit(1)

print(f"{GATE}: PASS ({checked} services verified)")
PYEOF
