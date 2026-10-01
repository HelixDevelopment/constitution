#!/bin/sh
# =============================================================================
# T166 RED test (SpecKit-004 "fast-dev-cycles", Phase 10 / User Story 8;
# plan.md T-G03; FR-024, SC-010).
# =============================================================================
#
# Purpose: prove, BEFORE T-G03's `consumers/enumerate.sh` implementation
# exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/consumers/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISM the real tool will rely on -- a direct
#       `gh api repos/<org>/<repo>/contents/constitution` probe, keyed on
#       `type == "submodule"` -- is genuinely sound on this host, proven by
#       REAL `gh api` invocations against a known-present and a
#       known-absent project (never merely assumed present, per §11.4.273:
#       "the path is part of the instrument"); and that GitHub code search
#       (a candidate but REJECTED source per CA-002/DEC-24) genuinely
#       undercounts, confirmed live rather than trusted from a snapshot;
#   (C) once T-G03 lands, invoking the real tool through the fixtures
#       under fixtures/consumer_enumerate/ produces the outcomes contract
#       consumer-audit-and-migration.md's CA-001..CA-005 predict.
#
# Contract: specs/004-fast-dev-cycles/contracts/consumer-audit-and-migration.md
#   CA-001 (sources) .. CA-005 (re-run determinism); common-conventions.md
#   (C-001..C-007). No new CLI contract is invented here -- the contract
#   file already fixes enumerate.sh's invocation, sources, needles, exit
#   codes and RED fixture set; this file exercises exactly those.
#
# Task line (tasks.md T166, verbatim): "[P] [US8] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_consumer_enumerate_red.sh per
# contract consumer-audit-and-migration (control needle:
# HelixDevelopment/ota appears; negative control: design_system does not;
# recorded failed needle: code search alone is refused as a source) (plan
# T-G03; FR-024, SC-010)".
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixtures under fixtures/consumer_enumerate/. It does NOT implement
# consumers/enumerate.sh (T-G03/T170, a separate later task dispatched to
# its own reviewer), and never fabricates a tool-invocation result --
# every scenario below is either (a) a real `gh api`/`gh search code`
# invocation this file performs itself (Section B, self-validating the
# underlying mechanism against this host's REAL, live GitHub state), or
# (b) a real invocation of the (today, absent) enumerate.sh tool, reported
# RED because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every Section C "tool invocation" check -- Section B's
#       self-checks of the gh api/search MECHANISM are expected to PASS
#       today, since they exercise only gh itself, not the absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/consumers/enumerate.sh"
FIXDIR="$HERE/fixtures/consumer_enumerate"
NEEDLES="$FIXDIR/known_needles.json"
EVDIR="$REPO_ROOT/qa-results/fastcycle/us8/red"
mkdir -p "$EVDIR" 2>/dev/null || true
FINGERPRINT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T166 RED: consumer enumeration (plan T-G03; FR-024, SC-010); candidate fingerprint=$FINGERPRINT =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-G03 has landed; Section C's real"
    echo "   invocation checks below are the functional tests to run"
else
    echo "RED: $TOOL is absent -- T-G03 (consumers/enumerate.sh) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -d "$FC/consumers" ]; then
    NON_GITKEEP=$(find "$FC/consumers" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/consumers/ genuinely holds nothing but"
        echo "   .gitkeep -- confirms enumerate.sh is absent by DIRECTORY"
        echo "   CONTENT, not merely by the single-path check above"
    else
        echo "NOTE: $FC/consumers/ holds $NON_GITKEEP non-.gitkeep file(s)"
        echo "      already -- re-check whether T-G03/T-G04/T-G05 has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/consumers/ does not exist at all"
fi

if [ ! -f "$NEEDLES" ]; then
    bad "control needle FAILED: $NEEDLES fixture is missing -- this file's"
    echo "   own known-needle set cannot be read"
else
    ok "control needle: $NEEDLES fixture is present"
fi

# =============================================================================
# Section B -- self-validation of the underlying gh-api/gh-search-code
# MECHANISM (§11.4.107(10)/§11.4.273: "the path is part of the
# instrument"), run LIVE against this host's real GitHub state -- BEFORE
# any claim is made about what the (absent) real enumerate.sh tool should
# produce. This is never a substitute for Section C's real tool
# invocations -- it only proves the mechanism T-G03's implementer will
# build on is sound TODAY, on THIS host, with THIS gh authentication.
# =============================================================================
if ! command -v gh >/dev/null 2>&1; then
    bad "gh (GitHub CLI) not found -- the mechanism T-G03 depends on"
    echo "   (CA-001 direct GitHub API probe) is not available on this host"
else
    ok "gh is available ($(gh --version 2>&1 | head -1))"
    if ! gh auth status >/dev/null 2>&1; then
        bad "gh is not authenticated -- CA-001's probe cannot run"
    else
        ok "gh is authenticated"

        # -- B1: known consumer must resolve as a root-path constitution submodule
        B1_OUT=$(gh api repos/HelixDevelopment/ota/contents/constitution 2>&1)
        B1_RC=$?
        if [ "$B1_RC" -eq 0 ] && echo "$B1_OUT" | grep -q '"type": *"submodule"'; then
            ok "B1 mechanism self-check: gh api repos/HelixDevelopment/ota/contents/constitution"
            echo "   genuinely returns type=submodule LIVE on this host -- the CA-001"
            echo "   probe mechanism (root path 'constitution', type==submodule) is"
            echo "   proven sound, not merely assumed present"
        else
            bad "B1 mechanism self-check FAILED: live gh api probe of the known"
            echo "   consumer HelixDevelopment/ota did not return a submodule entry"
            echo "   (rc=$B1_RC); re-derive the discriminator before T-G03 is built on it"
        fi

        # -- B2: known non-consumer must genuinely 404
        B2_OUT=$(gh api repos/vasic-digital/design_system/contents/constitution 2>&1)
        B2_RC=$?
        if [ "$B2_RC" -ne 0 ] && echo "$B2_OUT" | grep -qi '404\|not found'; then
            ok "B2 mechanism self-check: gh api probe of the known non-consumer"
            echo "   vasic-digital/design_system genuinely 404s LIVE on this host --"
            echo "   the negative-control side of the probe is proven sound (the"
            echo "   §11.4.273 null-hypothesis needle: had this NOT 404'd, the"
            echo "   whole discriminator would be broken)"
        else
            bad "B2 mechanism self-check FAILED: live gh api probe of the known"
            echo "   non-consumer vasic-digital/design_system did NOT 404 (rc=$B2_RC"
            echo "   out=$B2_OUT) -- the negative-control premise itself is false;"
            echo "   re-verify before trusting anything else in this file"
        fi

        # -- B3: recorded failed needle -- code search must genuinely miss a
        # known consumer (CA-002: code search is not a valid source; may be
        # run only as this recorded failed needle).
        B3_OUT=$(gh search code "constitution" --filename .gitmodules --owner HelixDevelopment 2>&1)
        B3_RC=$?
        if [ "$B3_RC" -eq 0 ] && ! echo "$B3_OUT" | grep -q '^HelixDevelopment/ota:'; then
            ok "B3 recorded failed needle: gh search code (the REJECTED source)"
            echo "   genuinely misses HelixDevelopment/ota LIVE on this host --"
            echo "   confirms CA-002's rejection of code search is not stale, and"
            echo "   this run is the T-G03 failed-needle record itself, never used"
            echo "   as a live enumeration source"
        else
            echo "NOTE: gh search code either errored (rc=$B3_RC) or unexpectedly"
            echo "      found HelixDevelopment/ota this run -- if it now finds it,"
            echo "      CA-002's rejection needs re-justifying with fresh evidence"
            echo "      before enumerate.sh is implemented (this NOTE does not fail"
            echo "      the RED test: CA-002 already forbids using code search as a"
            echo "      source regardless, so B3 is informational, not load-bearing)"
        fi
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the JSON-shape checks in Section C"
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "NOTE: jq not found -- Section C falls back to python3 -m json.tool"
    echo "      for the two-run determinism comparison (CA-005/quickstart"
    echo "      Scenario 9's 'cmp <(jq -S .projects ...)' becomes a python3"
    echo "      equivalent below; not a failure of this test file)"
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) enumerate.sh tool.
# Every check here is a REAL command execution against contract-shaped
# args, so the moment T-G03 lands, these checks self-flip GREEN with no
# further edits to this file.
# =============================================================================
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CFG="$REPO_ROOT/config/fastcycle/fastcycle.yaml"

run_tool() {
    if [ -f "$TOOL" ]; then
        sh "$TOOL" "$@" 2>&1
        return $?
    fi
    echo "enumerate.sh absent"
    return 127
}

# --- C1: control needle (CA-004) -- known consumer present
C1_OUT=$(run_tool --config "$CFG" --out "$WORK/consumers.json"); C1_RC=$?
if [ "$C1_RC" -eq 0 ] && [ -f "$WORK/consumers.json" ] && grep -q '"HelixDevelopment/ota"' "$WORK/consumers.json"; then
    ok "C1 control needle: enumerate.sh lists HelixDevelopment/ota"
else
    bad "C1 control needle: enumerate.sh did not list HelixDevelopment/ota (rc=$C1_RC out=$C1_OUT)"
fi

# --- C2: negative control (CA-004) -- known non-consumer absent
if [ "$C1_RC" -eq 0 ] && [ -f "$WORK/consumers.json" ] && ! grep -q '"vasic-digital/design_system"' "$WORK/consumers.json"; then
    ok "C2 negative control: enumerate.sh does not list vasic-digital/design_system"
else
    bad "C2 negative control: enumerate.sh either errored or listed design_system as a consumer (rc=$C1_RC)"
fi

# --- C3: ca_negctrl_single_source -- a project found by only the API probe
# is KEPT and flagged single-source, never dropped (CA-002).
if [ "$C1_RC" -eq 0 ] && [ -f "$WORK/consumers.json" ] && grep -q '"HelixDevelopment/thready"' "$WORK/consumers.json"; then
    ok "C3 ca_negctrl_single_source: enumerate.sh keeps HelixDevelopment/thready"
    echo "   (API-only, not local, not code-search) rather than dropping it"
else
    bad "C3 ca_negctrl_single_source: enumerate.sh did not list HelixDevelopment/thready (rc=$C1_RC)"
fi

# --- C4: ca_negctrl_text_only_consumer -- inheritance-pointer-only project
# enumerated with consumer_kind=text-only-inheritance (CA-002/13.1).
if [ "$C1_RC" -eq 0 ] && [ -f "$WORK/consumers.json" ] && grep -q '"vasic-digital/helix_design"' "$WORK/consumers.json" \
    && grep -A3 '"vasic-digital/helix_design"' "$WORK/consumers.json" | grep -q 'text-only-inheritance'; then
    ok "C4 ca_negctrl_text_only_consumer: enumerate.sh classifies vasic-digital/helix_design as text-only-inheritance"
else
    bad "C4 ca_negctrl_text_only_consumer: enumerate.sh did not classify vasic-digital/helix_design as text-only-inheritance (rc=$C1_RC)"
fi

# --- C5: ca_enumerate_twice / CA-005 -- re-run yields an identical project set
run_tool --config "$CFG" --out "$WORK/consumers_2.json" >/dev/null 2>&1; C5_RC=$?
if [ "$C5_RC" -eq 0 ] && [ -f "$WORK/consumers.json" ] && [ -f "$WORK/consumers_2.json" ]; then
    if command -v jq >/dev/null 2>&1; then
        DIFF=$(cmp <(jq -S .projects "$WORK/consumers.json" 2>/dev/null) <(jq -S .projects "$WORK/consumers_2.json" 2>/dev/null) 2>&1)
    else
        DIFF=$(cmp <(python3 -c "import json,sys; print(json.dumps(sorted(json.load(open('$WORK/consumers.json'))['projects'], key=lambda p: p.get('project_id','')), sort_keys=True))" 2>/dev/null) \
                    <(python3 -c "import json,sys; print(json.dumps(sorted(json.load(open('$WORK/consumers_2.json'))['projects'], key=lambda p: p.get('project_id','')), sort_keys=True))" 2>/dev/null) 2>&1)
    fi
    if [ -z "$DIFF" ]; then
        ok "C5 ca_enumerate_twice (CA-005): two consecutive enumerate.sh runs produced an identical project set"
    else
        bad "C5 ca_enumerate_twice (CA-005): two consecutive enumerate.sh runs DIFFERED: $DIFF"
    fi
else
    bad "C5 ca_enumerate_twice (CA-005): could not run enumerate.sh twice for comparison (rc=$C5_RC)"
fi

# =============================================================================
# Section D -- T177 Round 1 B1 regression: a `gh`/`glab` failure for any
# reason OTHER than a genuine HTTP 404 (auth failure, rate limit, network
# error) MUST NOT be silently folded into "zero hits" -- it MUST be
# recorded in the output doc's source_reachability block AND the run
# MUST exit loudly (5), never a quiet, undercounted "success". A fake
# gh/glab (prepended onto PATH, real gh/glab untouched) reproduces the
# reviewer's exact repro: "put a fake gh/glab that exits 1 first on
# PATH".
# =============================================================================
D_FAKEBIN=$(mktemp -d)
cat > "$D_FAKEBIN/gh" <<'EOF'
#!/bin/sh
echo "gh: simulated auth failure (HTTP 401)" >&2
exit 1
EOF
chmod +x "$D_FAKEBIN/gh"
cat > "$D_FAKEBIN/glab" <<'EOF'
#!/bin/sh
echo "glab: simulated auth failure (HTTP 401)" >&2
exit 1
EOF
chmod +x "$D_FAKEBIN/glab"

D_OUT=$(PATH="$D_FAKEBIN:$PATH" run_tool --config "$CFG" --out "$WORK/degraded_consumers.json"); D_RC=$?
if [ "$D_RC" -eq 5 ]; then
    ok "D1 B1 degraded-probe exit: a fake gh/glab that always fails with a non-404 error (simulated auth failure) makes enumerate.sh exit 5 (partial enumeration), never a silent 0"
else
    bad "D1 B1 degraded-probe exit: expected exit 5 for a degraded (non-404-failing) gh/glab, got rc=$D_RC (out=$D_OUT)"
fi
if [ -f "$WORK/degraded_consumers.json" ]; then
    D_DEGRADED_COUNT=$(python3 -c "
import json
d = json.load(open('$WORK/degraded_consumers.json'))
r = d.get('source_reachability', {})
print(len(r.get('github_degraded') or []) + len(r.get('gitlab_degraded') or []))
" 2>/dev/null)
    if [ -n "$D_DEGRADED_COUNT" ] && [ "$D_DEGRADED_COUNT" -gt 0 ] 2>/dev/null; then
        ok "D2 B1 degraded-probe recorded: source_reachability names $D_DEGRADED_COUNT degraded probe(s) -- the failure is surfaced in the written document, never silently absorbed"
    else
        bad "D2 B1 degraded-probe recorded: source_reachability recorded no degraded probes despite gh/glab always failing (see $WORK/degraded_consumers.json)"
    fi
else
    bad "D2 B1 degraded-probe recorded: enumerate.sh did not write --out at all despite a PARTIAL (not total) failure -- real local-source hits are still real data and must still be written"
fi

# D3: a genuine 404 (org/group absent) must STILL be treated as a normal
# negative, never degraded -- the control-needle half of this fix (the
# false-positive guard, §11.4.201(1)): a fix for B1 that also makes a
# REAL absence look "degraded" would itself be a new false-positive bug.
D_FAKEBIN_404=$(mktemp -d)
cat > "$D_FAKEBIN_404/gh" <<'EOF'
#!/bin/sh
echo "gh: Not Found (HTTP 404)" >&2
exit 1
EOF
chmod +x "$D_FAKEBIN_404/gh"
D3_OUT=$(PATH="$D_FAKEBIN_404:$PATH" run_tool --config "$CFG" --out "$WORK/notfound_consumers.json"); D3_RC=$?
# T177 Round 2 m-R2-1 fix: `rc != 5` alone would also pass on rc 1, 3 or 4
# -- none of which is the correct outcome here. Confirmed live (control
# needle, §11.4.199 exact reproduction) that this EXACT fixture (a gh that
# 404s on every call, real glab + real local sources otherwise reachable)
# genuinely exits 0 on this host today; assert that specific value.
if [ "$D3_RC" -eq 0 ]; then
    ok "D3 B1 real-404-not-degraded: a gh that genuinely 404s on every call exits 0 (real glab/local sources still reachable, needles satisfied) -- a real confirmed-absent org is still a normal negative, never a false 'unreachable'"
else
    bad "D3 B1 real-404-not-degraded: expected rc=0 for a genuinely-404ing gh with otherwise-healthy sources, got rc=$D3_RC -- the 404-vs-error distinction regressed (or real glab/local-source reachability changed)"
fi
rm -rf "$D_FAKEBIN" "$D_FAKEBIN_404" 2>/dev/null || true

# =============================================================================
# D4/D5 -- T177 Round 2 R2-I5(c): the PER-REPO gh_probe_submodule()
# degraded path was never reached by any suite fixture before now --
# D1's fake gh always fails at the repo-LIST step (gh_repo_list), so
# gh_probe_submodule's own "error" branch was untested; reverting it
# (§11.4.107(10) guard-viability) flips exit 5 -> 0 with nothing in T166
# noticing. A fake gh here SUCCEEDS at repo-list (one real-shaped repo
# name returned) but FAILS the per-repo submodule content probe with a
# genuine non-404 error, exercising gh_probe_submodule's degraded branch
# specifically.
# =============================================================================
D_FAKEBIN_PROBE=$(mktemp -d)
cat > "$D_FAKEBIN_PROBE/gh" <<'EOF'
#!/bin/sh
case "$*" in
    *"contents/constitution"*)
        echo "gh: simulated transient 500 Internal Server Error (not a 404)" >&2
        exit 1
        ;;
    *"orgs/"*"/repos"*)
        echo "d177r2-probe-fixture-repo"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$D_FAKEBIN_PROBE/gh"
D4_OUT=$(PATH="$D_FAKEBIN_PROBE:$PATH" run_tool --config "$CFG" --out "$WORK/probe_degraded_consumers.json"); D4_RC=$?
if [ "$D4_RC" -eq 5 ]; then
    ok "D4 R2-I5(c) per-repo probe degraded exit: a gh that succeeds at repo-list but fails the per-repo submodule content probe (non-404) makes enumerate.sh exit 5, never a silent success"
else
    bad "D4 R2-I5(c) per-repo probe degraded exit: expected exit 5 for a degraded per-repo probe, got rc=$D4_RC (out=$D4_OUT)"
fi
if [ -f "$WORK/probe_degraded_consumers.json" ]; then
    D5_PROBE_REASON=$(python3 -c "
import json
d = json.load(open('$WORK/probe_degraded_consumers.json'))
for e in d.get('source_reachability', {}).get('github_degraded') or []:
    if e.get('repo') == 'd177r2-probe-fixture-repo' and str(e.get('reason', '')).startswith('probe-'):
        print('ok')
        break
" 2>/dev/null)
    if [ "$D5_PROBE_REASON" = "ok" ]; then
        ok "D5 R2-I5(c) per-repo probe degraded recorded: source_reachability names the PER-REPO probe failure specifically (reason starting 'probe-'), distinct from a repo-list-level failure -- confirms gh_probe_submodule's own degraded branch was genuinely exercised, not just repo-list's"
    else
        bad "D5 R2-I5(c) per-repo probe degraded recorded: source_reachability did not name a per-repo probe-level degradation for the fixture repo (see $WORK/probe_degraded_consumers.json)"
    fi
else
    bad "D5 R2-I5(c) per-repo probe degraded recorded: enumerate.sh did not write --out at all"
fi
rm -rf "$D_FAKEBIN_PROBE" 2>/dev/null || true

# =============================================================================
# D6/D7/D8 -- T177 Round 2 R2-I5(a)/(b): hermetic, in-process reproduction
# of the exact malformed-glab-response repros (mirroring the reviewer's
# own "hermetic A1" style, §11.4.199 exact reproduction) against
# `_enumerate_impl.py`'s source2_gitlab() directly, monkey-patching only
# glab_json() so no real network/glab call is involved. Confirms: (D6) a
# genuine rc=0 + truncated/non-JSON glab body is NEVER folded into "zero
# hits" (previously silently absorbed); (D7) a dict-shaped glab body
# (instead of the expected list) is reported as degraded rather than
# crashing with an uncaught AttributeError; (D8) negative control -- a
# GENUINELY well-shaped, empty (real "no projects") response is still
# correctly treated as zero hits with no degraded entry (the
# §11.4.201(1) false-positive guard: a fix for (a)/(b) that also flags a
# real empty result would itself be a new bug).
# =============================================================================
D678=$(python3 - "$FC/consumers/_enumerate_impl.py" <<'PYEOF'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("_enumerate_impl", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

results = {}

# D6: truncated/non-JSON group-list body at rc=0.
def fake_malformed_group_list(args, timeout=20):
    if "groups/" in args[1]:
        return None, "malformed"
    return None, "error"
mod.glab_json = fake_malformed_group_list
hits, reach, degraded = mod.source2_gitlab(["d177r2-org"])
results["D6"] = bool(hits == {} and any(d.get("reason", "").startswith("group-list-") and d["reason"] != "group-list-ok" for d in degraded))

# D7: dict-shaped (not list) group-list body at rc=0 -- must not crash,
# must be reported degraded.
def fake_dict_group_list(args, timeout=20):
    if "groups/" in args[1]:
        return {"message": "not a list"}, "ok"
    return None, "error"
mod.glab_json = fake_dict_group_list
try:
    hits2, reach2, degraded2 = mod.source2_gitlab(["d177r2-org"])
    results["D7"] = bool(hits2 == {} and any(d.get("reason", "") == "group-list-malformed-shape" for d in degraded2))
except AttributeError:
    results["D7"] = False

# D8: negative control -- a genuinely well-shaped EMPTY list (a real
# group with zero projects) must NOT be reported degraded.
def fake_empty_group_list(args, timeout=20):
    if "groups/" in args[1]:
        return [], "ok"
    return None, "error"
mod.glab_json = fake_empty_group_list
hits3, reach3, degraded3 = mod.source2_gitlab(["d177r2-org"])
results["D8"] = bool(hits3 == {} and degraded3 == [] and reach3 is True)

for k in ("D6", "D7", "D8"):
    print("%s=%s" % (k, results[k]))
PYEOF
)
echo "$D678"
if echo "$D678" | grep -q '^D6=True$'; then
    ok "D6 R2-I5(a) malformed group-list never folded to zero: a genuine rc=0 + truncated glab body is reported as a degraded probe, never silently absorbed as zero hits"
else
    bad "D6 R2-I5(a) malformed group-list never folded to zero: FAILED (see output above)"
fi
if echo "$D678" | grep -q '^D7=True$'; then
    ok "D7 R2-I5(b) dict-shaped group-list does not crash: a dict-shaped (wrong-type) glab body at rc=0 is reported as degraded (malformed-shape), never an uncaught AttributeError"
else
    bad "D7 R2-I5(b) dict-shaped group-list does not crash: FAILED (see output above -- either it crashed or was not reported degraded)"
fi
if echo "$D678" | grep -q '^D8=True$'; then
    ok "D8 negative control (§11.4.201(1)): a genuinely well-shaped EMPTY group-list is still correctly treated as zero hits with NO degraded entry -- the D6/D7 fix does not false-positive on a real empty result"
else
    bad "D8 negative control (§11.4.201(1)): FAILED -- a genuinely empty result was wrongly flagged degraded"
fi

# Archive this run's stdout as the RED evidence per Test Discipline.
{
    echo "T166 RED run; candidate fingerprint=$FINGERPRINT; date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "PASS=$PASS FAIL=$FAIL"
} > "$EVDIR/test_consumer_enumerate_red.$(date -u +%Y%m%dT%H%M%SZ).log" 2>/dev/null || true

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
