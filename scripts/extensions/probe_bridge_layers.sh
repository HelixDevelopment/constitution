#!/usr/bin/env bash
# probe_bridge_layers.sh — HXC-159 T-B1.01 Bridge layer-presence probe.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The "Bridge" design (SpecKit + Superpowers + Superpowers-Bridge/SuperSpec +
# SuperB + a formerly-designed SuperBridge MCP + Helix LLM + a llama.cpp RPC
# cluster) is described across 8 design documents, but the design corpus being
# real and complete is NOT the same thing as any given layer being installed
# (§11.4.108 SOURCE-vs-RUNTIME gap). This probe measures, on THIS host, right
# now, what is actually present for each of the 7 layers and emits a FOUR-VALUE
# verdict per layer — WIRED / PARTIAL / DESIGNED-ONLY / NONEXISTENT — never a
# binary present/absent (the remedies differ per class; a binary flattens that
# distinction away, per plan.md's Track-B rationale).
#
# CRITICAL TRAP THIS PROBE EXISTS TO NOT REPEAT (R-30, §11.4.201 false-null
# class): a system-scope-only systemd probe previously produced a CONFIDENT
# false negative on L6 (Helix LLM) — all seven Helix systemd units on this
# host are USER-scope, not system-scope. This probe therefore ALWAYS queries
# BOTH `systemctl --system` (the default/no-flag invocation) AND
# `systemctl --user`, and records which scopes were checked in the report so
# the trap is encoded in the probe, never left to be remembered.
#
# ── Layers probed ────────────────────────────────────────────────────────────
#   L1  Developer workstation   — CLI agent + the five governance carriers
#   L2  Spec-Kit core           — `specify` CLI + `.specify/` + speckit-* skills
#   L3  SuperSpec (orchestration) — WangX0111/superspec, extension id "superspec"
#   L4  SuperB (discipline)     — RbBtSn0w/spec-kit-extensions, extension "superb"
#   L5  SuperBridge MCP (execution) — a design-only MCP server; §7 of spec.md
#                                  records this tier as DELETED from the
#                                  architecture (FR-047) — this probe still
#                                  checks for it honestly rather than assuming.
#   L6  Helix LLM (inference)   — Gateway/Brain/Knowledge systemd services
#   L7  llama.cpp RPC cluster   — `-DGGML_RPC=ON` build-flag readiness
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   bash constitution/scripts/extensions/probe_bridge_layers.sh [--root <repo-root>]
#                                                                [--quiet]
#   Re-runnable at any time — layer state decays across phases (T-B1.01.4).
#   Each run writes a NEW timestamped run-id directory; nothing is overwritten.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   The live host state: filesystem (CLAUDE.md/.specify/submodules/dependencies),
#   `specify` CLI, `systemctl --system` + `systemctl --user`, `ss`/`curl` for the
#   L6 listening-port check, `git submodule status`.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   <repo-root>/qa-results/hxc159/bridge_layers/<run-id>/
#     report.json          — the machine-readable verdict, one entry per layer,
#                             each probe's exact command + exit code + a path to
#                             its full captured output (RS-18 runtime signature).
#     raw/L<N>_<probe>.cmd   the exact command string that was run
#     raw/L<N>_<probe>.out   full stdout+stderr of that command
#     raw/L<N>_<probe>.exit  the exit code of that command
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only against the repo and the host's systemd/network state. Writes
#   ONLY under qa-results/hxc159/bridge_layers/<run-id>/ (a fresh directory per
#   run). No mutation of .specify/, no submodule operations, no service control.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (JSON assembly — no jq dependency), systemctl, git; ss and
#   curl are used opportunistically for the L6 listening-port probe and their
#   absence degrades that one sub-probe honestly (recorded, never guessed).
#   Parses clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   specs/001-helixskills-incorporation/{spec.md §7, plan.md, tasks.md Phase B1}
#   · §11.4.69 (sink-side evidence taxonomy: feature_class=extension_loading) ·
#   §11.4.108 (source-vs-runtime gap) · §11.4.111 (resolve by stable name) ·
#   §11.4.201 (a probe must enumerate all scopes / no false-null) · §11.4.6
#   (no-guessing — every verdict traces to a captured raw probe file).
#
# Classification: project-specific (HXC-159 Bridge investigation).
# Last verified: 2026-09-22
set -u

SELF_DIR=$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)
ROOT=$(cd "$SELF_DIR/../../.." >/dev/null 2>&1 && pwd)
QUIET=0

while [ $# -gt 0 ]; do
	case "$1" in
		--root)  shift; ROOT="$1" ;;
		--quiet) QUIET=1 ;;
		-h|--help) sed -n '3,60p' "$0"; exit 0 ;;
		*) echo "probe_bridge_layers.sh: unknown arg: $1" >&2; exit 2 ;;
	esac
	shift || true
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="$ROOT/qa-results/hxc159/bridge_layers/$RUN_ID"
RAW_DIR="$OUT_DIR/raw"
mkdir -p "$RAW_DIR" || { echo "probe_bridge_layers.sh: cannot create $RAW_DIR" >&2; exit 1; }

say "== Bridge layer-presence probe — run $RUN_ID =="
say "   root: $ROOT"
say "   out:  $OUT_DIR"

# ── capture helper: runs a command, records its EXACT command string, full
#    stdout+stderr, and exit code as three sibling raw files. Never re-derives
#    a verdict from memory — every downstream verdict reads THESE files. ──────
run_probe() {
	local tag="$1"; shift
	local cmd="$*"
	local out="$RAW_DIR/${tag}.out"
	local exitf="$RAW_DIR/${tag}.exit"
	local cmdf="$RAW_DIR/${tag}.cmd"
	printf '%s\n' "$cmd" >"$cmdf"
	( cd "$ROOT" && eval "$cmd" ) >"$out" 2>&1
	printf '%s\n' "$?" >"$exitf"
}

# ── L1 — Developer workstation: CLI agent + five governance carriers ─────────
run_probe "L1_carriers" 'for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md CRUSH.md; do
  if [ -f "$f" ]; then echo "PRESENT $f"; else echo "ABSENT  $f"; fi
done'
run_probe "L1_cli" 'command -v claude || echo "NOT-ON-PATH"'

# ── L2 — Spec-Kit core: `specify` CLI + `.specify/` + speckit-* skills ───────
run_probe "L2_specify_dir" 'test -d .specify && echo "PRESENT .specify" || echo "ABSENT .specify"'
run_probe "L2_specify_cli" 'command -v specify || echo "NOT-ON-PATH"'
run_probe "L2_skills_claude" 'ls .claude/skills 2>/dev/null | grep -c "^speckit-" || echo 0'
run_probe "L2_skills_kimi"   'ls .kimi-code/skills 2>/dev/null | grep -c "^speckit-" || echo 0'

# ── L3 — SuperSpec (orchestration): WangX0111/superspec, extension "superspec" ─
run_probe "L3_submodule_status" 'git submodule status -- submodules/superspec 2>&1 || echo "NOT-A-SUBMODULE"'
run_probe "L3_extension_yml"    'test -f .specify/extensions/superspec/extension.yml && echo PRESENT || echo ABSENT'
run_probe "L3_extension_list"   'specify extension list 2>&1 || echo "specify CLI unavailable or extension list failed"'
run_probe "L3_extensions_yml_installed" 'grep -A2 "^installed:" .specify/extensions.yml 2>/dev/null || echo "no .specify/extensions.yml or no installed: key"'

# ── L4 — SuperB (discipline): RbBtSn0w/spec-kit-extensions, extension "superb" ─
run_probe "L4_submodule_search" 'find . -maxdepth 3 -iname "*superb*" -type d 2>/dev/null | grep -v node_modules || echo "no local superb-named directory"'
run_probe "L4_extensions_yml_installed" 'grep -i "superb" .specify/extensions.yml 2>/dev/null || echo "superb NOT present in .specify/extensions.yml installed list"'
run_probe "L4_catalog_search" 'specify extension search superb 2>&1 || echo "specify CLI unavailable or catalog search failed"'

# ── L5 — SuperBridge MCP (execution): design corpus records this tier DELETED ─
# NOTE (§11.4.273 self-caught instrument bug, fixed before first use): the
# obvious `grep ... | head -20 || echo fallback` shape reads the EXIT STATUS
# of the pipeline's LAST stage (`head`), which is 0 even on zero matches — so
# the `||` fallback never fires and an empty, ambiguous "" is what a naive
# reader would have to interpret. Captured into a variable and branched on
# explicitly instead, per the exact class §11.4.273(g) names.
# EXCLUDES qa-results/ — this probe's OWN prior report.json files legitimately
# quote the word "superbridge" in their prose verdict_basis text (this very
# comment does too), which is observer contamination (§11.4.201(10)): the
# instrument's own output being read back as evidence of the thing it merely
# discussed. Confirmed self-caught in dry-run before this script's first
# committed use — a report from an earlier run of THIS probe matched.
run_probe "L5_mcp_config_grep" 'matches=$(grep -ril "superbridge" . --include="*.json" 2>/dev/null | grep -v node_modules | grep -v "/\.git/" | grep -v "^\./qa-results/" | head -20);
if [ -n "$matches" ]; then printf "%s\n" "$matches"; else echo "no superbridge reference found in any tracked *.json config"; fi'
run_probe "L5_npm_package_search" 'matches=$(find . -maxdepth 4 -iname "*superbridge*" -not -path "./qa-results/*" 2>/dev/null | grep -v node_modules);
if [ -n "$matches" ]; then printf "%s\n" "$matches"; else echo "no superbridge-named path anywhere in the tree"; fi'

# ── L6 — Helix LLM (inference): systemd Gateway/Brain/Knowledge services ─────
# CRITICAL: BOTH scopes probed unconditionally (R-30 / §11.4.201 false-null).
run_probe "L6_systemd_system_scope" 'systemctl list-unit-files 2>&1 | grep -i helix || echo "ZERO helix units at SYSTEM scope"'
run_probe "L6_systemd_user_scope"   'systemctl --user list-unit-files 2>&1 | grep -i helix || echo "ZERO helix units at USER scope"'
run_probe "L6_systemd_user_active"  'systemctl --user list-units 2>&1 | grep -i helix || echo "ZERO active helix units at USER scope"'
run_probe "L6_gateway_is_active"    'systemctl --user is-active helixllm-gateway.service 2>&1 || true'
run_probe "L6_gateway_is_enabled"   'systemctl --user is-enabled helixllm-gateway.service 2>&1 || true'
run_probe "L6_listening_port_8443"  'if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep 8443 || echo "no :8443 listener via ss"; else echo "ss NOT AVAILABLE on this host — port check degraded honestly"; fi'

# ── L7 — llama.cpp RPC cluster: `-DGGML_RPC=ON` build-flag readiness ─────────
run_probe "L7_submodule_present" 'test -d dependencies/LLama_CPP && echo PRESENT || echo ABSENT'
run_probe "L7_ggml_rpc_flag" 'grep -rl "GGML_RPC" dependencies/LLama_CPP/tools/CMakeLists.txt dependencies/LLama_CPP/tools/rpc/README.md 2>/dev/null || echo "GGML_RPC flag not found in expected files"'
# NOTE: a NAME match on "rpc-server*" also matches the .cpp SOURCE file that
# ships in the submodule unconditionally — that is not evidence of a BUILD.
# Restricted to an executable file named EXACTLY "rpc-server" (no extension),
# the actual build-output shape, under any build*/ directory.
run_probe "L7_rpc_server_built" 'matches=$(find dependencies/LLama_CPP -maxdepth 6 -path "*build*" -iname "rpc-server" -type f -executable 2>/dev/null);
matches="$matches
$(find . -maxdepth 4 -iname "rpc-server" -type f -executable 2>/dev/null)";
matches=$(printf "%s" "$matches" | grep -v "^$");
if [ -n "$matches" ]; then printf "%s\n" "$matches"; else echo "rpc-server EXECUTABLE not found (source file dependencies/LLama_CPP/tools/rpc/rpc-server.cpp is present but not yet built)"; fi'

say "== raw probe capture complete; assembling report.json =="

# ── JSON assembly ────────────────────────────────────────────────────────────
# Verdict rules are encoded here, EXPLICITLY, reading ONLY the raw captured
# files above — never re-running a command to "double-check" a verdict and
# never asserting a verdict the raw output does not support (§11.4.6).
python3 - "$RAW_DIR" "$OUT_DIR/report.json" "$RUN_ID" "$ROOT" <<'PYEOF'
import json, sys, os, datetime, subprocess

raw_dir, report_path, run_id, root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def read(tag, kind):
    p = os.path.join(raw_dir, f"{tag}.{kind}")
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()

def probe(tag):
    cmd = (read(tag, "cmd") or "").strip()
    out = read(tag, "out") or ""
    exitc = (read(tag, "exit") or "").strip()
    try:
        exitc = int(exitc)
    except ValueError:
        exitc = None
    excerpt = out if len(out) <= 4000 else out[:4000] + "\n...[truncated; see raw file]..."
    return {
        "tag": tag,
        "command": cmd,
        "exit_code": exitc,
        "output_excerpt": excerpt,
        "raw_output_path": f"raw/{tag}.out",
    }

def out_contains(tag, needle):
    out = read(tag, "out") or ""
    return needle.lower() in out.lower()

layers = []

# ── L1 ──
l1_carriers = read("L1_carriers", "out") or ""
present_count = l1_carriers.count("PRESENT")
l1_cli_ok = not out_contains("L1_cli", "NOT-ON-PATH")
if l1_cli_ok and present_count == 5:
    v1 = "WIRED"
elif present_count > 0 or l1_cli_ok:
    v1 = "PARTIAL"
else:
    v1 = "NONEXISTENT"
layers.append({
    "id": "L1", "name": "Developer workstation (CLI agent + five carriers)",
    "verdict": v1,
    "verdict_basis": f"carrier files present: {present_count}/5; claude CLI on PATH: {l1_cli_ok}",
    "probes": [probe("L1_carriers"), probe("L1_cli")],
})

# ── L2 ──
l2_dir_ok = out_contains("L2_specify_dir", "PRESENT .specify")
l2_cli_ok = not out_contains("L2_specify_cli", "NOT-ON-PATH")
def _count(tag):
    try:
        return int((read(tag, "out") or "0").strip().splitlines()[0])
    except Exception:
        return 0
l2_skills_claude = _count("L2_skills_claude")
l2_skills_kimi = _count("L2_skills_kimi")
if l2_dir_ok and l2_cli_ok and (l2_skills_claude > 0 or l2_skills_kimi > 0):
    v2 = "WIRED"
elif l2_dir_ok or l2_cli_ok:
    v2 = "PARTIAL"
else:
    v2 = "NONEXISTENT"
layers.append({
    "id": "L2", "name": "Spec-Kit core (specify CLI + .specify/ + speckit-* skills)",
    "verdict": v2,
    "verdict_basis": (
        f".specify present: {l2_dir_ok}; specify CLI on PATH: {l2_cli_ok}; "
        f"speckit-* skills registered — .claude/skills: {l2_skills_claude}, "
        f".kimi-code/skills: {l2_skills_kimi} "
        f"(NOTE: per-consumer skill-count VARIANCE is itself a measured fact, "
        f"not a defect this probe resolves — see HXC-159 Phase P2 shadowing/parity work)"
    ),
    "probes": [probe("L2_specify_dir"), probe("L2_specify_cli"), probe("L2_skills_claude"), probe("L2_skills_kimi")],
})

# ── L3 ──
l3_submodule_ok = not out_contains("L3_submodule_status", "NOT-A-SUBMODULE")
l3_extyml_ok = out_contains("L3_extension_yml", "PRESENT")
l3_enabled = out_contains("L3_extension_list", "enabled") and out_contains("L3_extension_list", "superpowers bridge")
l3_installed = out_contains("L3_extensions_yml_installed", "superspec")
if l3_submodule_ok and l3_extyml_ok and l3_enabled and l3_installed:
    v3 = "WIRED"
elif l3_submodule_ok or l3_extyml_ok or l3_enabled or l3_installed:
    v3 = "PARTIAL"
else:
    v3 = "DESIGNED-ONLY"
layers.append({
    "id": "L3", "name": "SuperSpec (orchestration) — WangX0111/superspec, extension id 'superspec'",
    "verdict": v3,
    "verdict_basis": (
        f"submodule checked out: {l3_submodule_ok}; extension.yml present: {l3_extyml_ok}; "
        f"'specify extension list' shows it Enabled: {l3_enabled}; "
        f"listed in .specify/extensions.yml installed:: {l3_installed}. "
        f"HONEST DELTA FROM spec.md (dated 2026-07-29): spec.md records L3 as "
        f"DESIGNED-ONLY / not-adoptable-as-is. Measured on THIS host on THIS run, "
        f"L3 is checked out as a git submodule pinned to an immutable commit SHA "
        f"(not the 'mutable tag-archive URL' the spec.md risk analysis describes) "
        f"and is registered+enabled via the specify CLI. This is a MATERIAL CHANGE "
        f"since spec.md's snapshot — see qa-results/hxc159/bridge_supply_chain/ "
        f"for the re-verified supply-chain facts."
    ),
    "probes": [probe("L3_submodule_status"), probe("L3_extension_yml"), probe("L3_extension_list"), probe("L3_extensions_yml_installed")],
})

# ── L4 ──
l4_dir_found = not out_contains("L4_submodule_search", "no local superb-named directory")
l4_installed = "superb NOT present" not in (read("L4_extensions_yml_installed", "out") or "")
l4_catalog_hit = out_contains("L4_catalog_search", "superb")
if l4_installed and l4_dir_found:
    v4 = "WIRED"
elif l4_dir_found or l4_installed:
    v4 = "PARTIAL"
elif l4_catalog_hit:
    v4 = "DESIGNED-ONLY"
else:
    v4 = "NONEXISTENT"
layers.append({
    "id": "L4", "name": "SuperB (discipline) — RbBtSn0w/spec-kit-extensions, extension id 'superb'",
    "verdict": v4,
    "verdict_basis": (
        f"local superb-named directory found: {l4_dir_found}; listed in "
        f".specify/extensions.yml installed:: {l4_installed}; found via "
        f"'specify extension search superb' (community, discovery-only catalog): "
        f"{l4_catalog_hit}. SuperB remains UNINSTALLED on this host — the catalog "
        f"knows about it (discovery-only, not directly installable) but nothing "
        f"local has been checked out for it, matching spec.md's DESIGNED-ONLY "
        f"reading. NOTE: SuperB (RbBtSn0w/spec-kit-extensions, extension id "
        f"'superb') is a DIFFERENT, unrelated project from L3's SuperSpec "
        f"(WangX0111/superspec) despite BOTH self-branding as 'Superpowers "
        f"Bridge' — see the supply-chain health record for the disambiguation."
    ),
    "probes": [probe("L4_submodule_search"), probe("L4_extensions_yml_installed"), probe("L4_catalog_search")],
})

# ── L5 ──
l5_config_hit = "no superbridge reference found" not in (read("L5_mcp_config_grep", "out") or "")
l5_path_hit = "no superbridge-named path anywhere" not in (read("L5_npm_package_search", "out") or "")
v5 = "NONEXISTENT" if not (l5_config_hit or l5_path_hit) else "PARTIAL"
layers.append({
    "id": "L5", "name": "SuperBridge MCP (execution) — an npm-built MCP server",
    "verdict": v5,
    "verdict_basis": (
        f"any MCP config referencing 'superbridge': {l5_config_hit}; any "
        f"superbridge-named path in the tree: {l5_path_hit}. Per spec.md §7 "
        f"(FR-047), this tier is a DESIGN CORRECTION — the execution role SuperB's "
        f"own README says it does not own ('owns no plan, task store, execution "
        f"lifecycle, completion state, or convergence command') is filled instead "
        f"by Spec Kit + Superpowers + the CLI agent's own skill/subagent machinery, "
        f"all already present (L1/L2). There is genuinely NOTHING to install here; "
        f"NONEXISTENT is not a procurement gap, it is the correct 6-layer reading."
    ),
    "probes": [probe("L5_mcp_config_grep"), probe("L5_npm_package_search")],
})

# ── L6 ──
l6_system_units = read("L6_systemd_system_scope", "out") or ""
l6_user_units = read("L6_systemd_user_scope", "out") or ""
l6_system_count = 0 if "ZERO helix units at SYSTEM scope" in l6_system_units else len([l for l in l6_system_units.splitlines() if l.strip()])
l6_user_count = 0 if "ZERO helix units at USER scope" in l6_user_units else len([l for l in l6_user_units.splitlines() if l.strip()])
l6_gateway_active = (read("L6_gateway_is_active", "out") or "").strip() == "active"
l6_listening = "8443" in (read("L6_listening_port_8443", "out") or "")
v6 = "WIRED" if (l6_user_count > 0 and l6_gateway_active and l6_listening) else ("PARTIAL" if l6_user_count > 0 else "NONEXISTENT")
layers.append({
    "id": "L6", "name": "Helix LLM (inference) — Gateway/Brain/Knowledge",
    "verdict": v6,
    "verdict_basis": (
        f"SYSTEM-scope helix units found: {l6_system_count} (§11.4.201 false-null "
        f"trap: system scope alone would read this as {'ABSENT' if l6_system_count == 0 else 'present'}); "
        f"USER-scope helix units found: {l6_user_count}; "
        f"helixllm-gateway.service is-active: {l6_gateway_active}; "
        f"listening on :8443 (ss): {l6_listening}. BOTH SCOPES WERE CHECKED "
        f"(R-30 mandate) — this probe does NOT repeat the prior false negative."
    ),
    "scopes_checked": ["system", "user"],
    "probes": [
        probe("L6_systemd_system_scope"), probe("L6_systemd_user_scope"),
        probe("L6_systemd_user_active"), probe("L6_gateway_is_active"),
        probe("L6_gateway_is_enabled"), probe("L6_listening_port_8443"),
    ],
})

# ── L7 ──
l7_dir_ok = out_contains("L7_submodule_present", "PRESENT")
l7_flag_ok = "GGML_RPC flag not found" not in (read("L7_ggml_rpc_flag", "out") or "")
l7_built = "rpc-server EXECUTABLE not found" not in (read("L7_rpc_server_built", "out") or "")
if l7_dir_ok and l7_flag_ok and l7_built:
    v7 = "WIRED"
elif l7_dir_ok and l7_flag_ok:
    v7 = "PARTIAL"
elif l7_dir_ok or l7_flag_ok:
    v7 = "PARTIAL"
else:
    v7 = "NONEXISTENT"
layers.append({
    "id": "L7", "name": "llama.cpp RPC cluster (distributed nodes)",
    "verdict": v7,
    "verdict_basis": (
        f"dependencies/LLama_CPP submodule present: {l7_dir_ok}; -DGGML_RPC=ON "
        f"build flag documented in the submodule's own build files: {l7_flag_ok}; "
        f"rpc-server binary actually built on this host: {l7_built}. This is a "
        f"BUILD-FLAG readiness task (submodule already builds llama-server), not "
        f"a procurement item — matches spec.md's ABSENT-BUT-BUILDABLE reading. "
        f"Out of scope for THIS feature (tracked separately per spec.md §7)."
    ),
    "probes": [probe("L7_submodule_present"), probe("L7_ggml_rpc_flag"), probe("L7_rpc_server_built")],
})

report = {
    "schema_version": "1.0",
    "run_id": run_id,
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "generated_by": "constitution/scripts/extensions/probe_bridge_layers.sh (HXC-159 T-B1.01)",
    "repo_root": root,
    "feature_class": "extension_loading",
    "verdict_vocabulary": ["WIRED", "PARTIAL", "DESIGNED-ONLY", "NONEXISTENT"],
    "layers": layers,
}

with open(report_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2, sort_keys=False)
    fh.write("\n")

print(f"report written: {report_path}")
for l in layers:
    print(f"  {l['id']}: {l['verdict']}  — {l['name']}")
PYEOF

RC=$?
if [ "$RC" -ne 0 ]; then
	echo "probe_bridge_layers.sh: report assembly FAILED (python3 exit $RC)" >&2
	exit 1
fi

say ""
say "Full report: $OUT_DIR/report.json"
say "Raw captures: $RAW_DIR/"
exit 0
