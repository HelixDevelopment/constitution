#!/bin/bash
# RED test (SpecKit-004 "fast-dev-cycles", User Story 6, T153 Round-1 NO-GO
# finding B2) for `host/host_report.py`'s needle-scratch-dir safety guard.
#
# Forensic FACT (T153 Round-1): `needle_scratch_dir: ""` (or `.`) resolved,
# via `_resolve()`'s plain `os.path.join(REPO_ROOT, path)`, to the
# repository root -- which was then `shutil.rmtree()`'d, exit 0. The fix
# (host_report.py `_refuse_dangerous_delete_target()` + `run_needle()`
# rebuilt on `tempfile.mkdtemp()`) is exercised here two ways:
#   (1) direct import: the pure guard function against the dangerous-value
#       table + a safe-value negative control (no filesystem side effects
#       at all for this half -- never touches a real path).
#   (2) end-to-end, SANDBOXED: `attribute` invoked against a throwaway
#       fake "repo" (host_report.py + its lib sibling copied into a mktemp
#       tree, so `REPO_ROOT` resolves INSIDE that sandbox, never the real
#       repository) with a dangerous `needle_scratch_dir` -- proving the
#       CLI-level refusal fires BEFORE any needle work runs, and a CANARY
#       file at the sandbox's fake repo root survives untouched.
#
# Producer != Verifier (§11.4.240): the sandbox + canary + assertions here
# are built independently of host_report.py's own logic; this test never
# trusts host_report.py's own reported exit code alone -- it checks the
# canary file's continued existence as the real, physical proof.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC_ROOT=$(cd "$HERE/.." && pwd)
TOOL="$FC_ROOT/host/host_report.py"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -f "$TOOL" ]; then
  echo "RED: host_report.py absent at $TOOL"
  bad "host_report.py exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- (1) direct import: _refuse_dangerous_delete_target() pure-function checks ---
python3 - "$FC_ROOT/host" "$WORK" <<'PYEOF'
import sys, os, importlib.util
host_dir, work = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("host_report", host_dir + "/host_report.py")
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception as exc:
    print("FAIL: host_report.py raised on import: %s: %s" % (type(exc).__name__, exc))
    print("SUMMARY pass=0 fail=1"); sys.exit(1)

if not hasattr(mod, "_refuse_dangerous_delete_target"):
    print("FAIL: host_report._refuse_dangerous_delete_target is not defined")
    print("SUMMARY pass=0 fail=1"); sys.exit(1)

fail = 0
def bad(m):
    global fail
    print("FAIL:", m); fail = 1
def ok(m):
    print("PASS:", m)

f = mod._refuse_dangerous_delete_target
repo_real = os.path.realpath(mod.REPO_ROOT)

# golden-bad: raw dangerous literals (resolved value deliberately irrelevant
# here -- the RAW check alone must catch these regardless of resolution).
for raw in ("", ".", "/", "~", ".."):
    reason = f(raw, os.path.join(work, "irrelevant"), "test.raw_%r" % raw)
    if reason:
        ok("raw value %r refused: %s" % (raw, reason))
    else:
        bad("raw value %r was NOT refused (must always be refused regardless of resolution)" % raw)

# golden-bad: resolved value is the repository root itself.
reason = f("some/relative/value", mod.REPO_ROOT, "test.repo_root")
if reason:
    ok("resolved-to-repo-root refused: %s" % reason)
else:
    bad("resolved-to-repo-root was NOT refused")

# golden-bad: resolved value is an ANCESTOR of the repository root.
ancestor = os.path.dirname(repo_real)
reason = f("some/relative/value", ancestor, "test.repo_ancestor")
if reason:
    ok("resolved-to-repo-ancestor (%r) refused: %s" % (ancestor, reason))
else:
    bad("resolved-to-repo-ancestor (%r) was NOT refused" % ancestor)

# golden-bad: resolved value is the filesystem root.
reason = f("some/relative/value", "/", "test.fs_root")
if reason:
    ok("resolved-to-filesystem-root refused: %s" % reason)
else:
    bad("resolved-to-filesystem-root was NOT refused")

# negative control: a genuinely safe, nested, relative-looking value must
# NOT be refused (the guard must not become a false-positive refusal,
# §11.4.201(1)).
safe_dir = os.path.join(work, "qa-results", "fastcycle", "_needle_safety_t153")
reason = f("qa-results/fastcycle/_needle_safety_t153", safe_dir, "test.safe_value")
if reason is None:
    ok("safe relative value NOT refused (negative control): %r" % safe_dir)
else:
    bad("safe relative value WRONGLY refused: %s" % reason)

print("SUMMARY pass=%d fail=%d" % (0 if fail else 1, fail))
sys.exit(1 if fail else 0)
PYEOF
py1_rc=$?
if [ "$py1_rc" -eq 0 ]; then ok "_refuse_dangerous_delete_target: dangerous-literal + ancestor + fs-root + negative-control checks"; else bad "_refuse_dangerous_delete_target checks"; fi

# --- (2) end-to-end, SANDBOXED: attribute against a fake repo, dangerous config ---
SANDBOX="$WORK/fake_repo"
mkdir -p "$SANDBOX/scripts/fastcycle/host" "$SANDBOX/scripts/fastcycle/lib" "$SANDBOX/qa-results/fastcycle"
cp "$FC_ROOT/host/host_report.py" "$SANDBOX/scripts/fastcycle/host/host_report.py"
cp "$FC_ROOT/lib/fc_common.py" "$SANDBOX/scripts/fastcycle/lib/fc_common.py"
CANARY="$SANDBOX/CANARY_MUST_SURVIVE.txt"
printf 'this file (and everything else in this sandbox fake-repo-root) must survive every fixture below untouched\n' > "$CANARY"
sha256_of() { python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1" 2>/dev/null || echo MISSING; }
CANARY_BEFORE=$(sha256_of "$CANARY")

run_dangerous() {  # run_dangerous <needle_scratch_dir_value> <label>
  local val="$1" label="$2"
  local cfg="$WORK/cfg_${label}.yaml"
  cat > "$cfg" <<YAML
schema: fastcycle-config/v1
paths:
  evidence_root: qa-results/fastcycle
host:
  attribution_roots: []
  worktree_prefix: ".nope-worktree-prefix-does-not-exist"
  session_scratch_roots: []
  hardlink_mirror_roots: []
  agent_registry_status: "docs/requests/agent_registry.status.tsv"
  disk_floor:
    volume_path: "."
    floors_gib: {dummy_floor: 1}
    codegraph_safe_script: "scripts/codegraph/codegraph_safe.sh"
  needle_scratch_dir: "$val"
YAML
  local out="$WORK/out_${label}.json"
  ( cd "$SANDBOX" && python3 "$SANDBOX/scripts/fastcycle/host/host_report.py" attribute \
      --config "$cfg" --out "$out" >"$WORK/o_${label}.log" 2>"$WORK/e_${label}.log" )
  echo $?
}

check_dangerous() {  # check_dangerous <needle_scratch_dir_value> <label>
  local val="$1" label="$2" rc canary_after
  rc=$(run_dangerous "$val" "$label")
  canary_after=$(sha256_of "$CANARY")
  if [ "$rc" -eq 2 ] && [ -f "$CANARY" ] && [ "$canary_after" = "$CANARY_BEFORE" ] && [ -d "$SANDBOX/scripts" ]; then
    ok "needle_scratch_dir=$val (label=$label): refused with usage exit 2, sandbox fake-repo-root byte-identical"
  else
    bad "needle_scratch_dir=$val (label=$label): expected exit 2 + sandbox untouched, got rc=$rc canary-present=$([ -f "$CANARY" ] && echo yes || echo no) sandbox-dir-present=$([ -d "$SANDBOX/scripts" ] && echo yes || echo no) stderr=$(cat "$WORK/e_${label}.log" 2>/dev/null)"
  fi
}
check_dangerous "" "empty"
check_dangerous "." "dot"

# --- negative control: a SAFE relative needle_scratch_dir must NOT be
#     refused by the guard (it may still fail later for an unrelated
#     legitimate reason -- e.g. btrfs unavailable inside a throwaway
#     sandbox tree -- but that failure must never be exit 2/usage).
rc_safe=$(run_dangerous "qa-results/fastcycle/_needle_safety_t153_safe" "safe")
if [ "$rc_safe" -ne 2 ]; then
  ok "needle_scratch_dir=safe-relative-value: NOT refused by the guard (got rc=$rc_safe, never usage-exit-2)"
else
  bad "needle_scratch_dir=safe-relative-value: WRONGLY refused with usage exit 2 -- $(cat "$WORK/e_safe.log" 2>/dev/null)"
fi
# and no leftover fixed-name needle artefact sitting directly in the
# configured parent afterward (mkdtemp's unique child + its own cleanup
# must have handled it -- never a fixed predictable path left behind).
if [ ! -e "$SANDBOX/qa-results/fastcycle/_needle_safety_t153_safe/unshared.bin" ]; then
  ok "safe run: no leftover fixed-name scratch artefact directly in the configured parent"
else
  bad "safe run: a leftover fixed-name scratch artefact was left directly in the configured parent (mkdtemp not used, or cleanup skipped)"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
