#!/usr/bin/env bash
# Paired §1.1 mutation test for CM-JEV-BOOTSTRAP-IDEMPOTENT.
# Mutation A: delete the invocation marker block from a sandboxed copy of
#   post_update_hook.sh — the gate MUST FAIL.
# Mutation B: corrupt one marker-guarded file between the two fixture runs —
#   harness-level check that digest discrimination is real (the gate's clause 2
#   compares digests; here we assert a deliberately NON-idempotent stub run is
#   detectable by the same digest mechanism).
set -uo pipefail
# Tool preflight: an absent tool is CANNOT-DETERMINE (rc 2), never a pass or a false RED.
for _t in jq python3 mktemp; do command -v "$_t" >/dev/null 2>&1 || { echo "[mutation] cannot determine: required tool '$_t' missing" >&2; exit 2; }; done
GREEN_LOG=$(mktemp); trap 'rm -f "$GREEN_LOG"' EXIT
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/cm_jev_bootstrap_idempotent.sh"
rc=0
say() { printf '[mutation:bootstrap] %s\n' "$*"; }

# GREEN first (real hook + fixture stub).
bash "$GATE" >"$GREEN_LOG" 2>&1 \
  || { say "SETUP FAILURE: gate not GREEN on genuine state"; cat "$GREEN_LOG"; exit 2; }
say "GREEN on genuine state confirmed"

SBX=$(mktemp -d); trap 'rm -rf "$SBX" "$GREEN_LOG"' EXIT

# Mutation A — strip the marker block from a sandboxed hook copy.
python3 - "$HERE/../post_update_hook.sh" "$SBX/post_update_hook.sh" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'(?ms)# >>> helix-jev-bootstrap >>>.*?# <<< helix-jev-bootstrap <<<\n?', '', s)
open(sys.argv[2], 'w').write(s)
PYEOF
JEV_HOOK_FILE="$SBX/post_update_hook.sh" bash "$GATE" > "$SBX/outA.log" 2>&1
if [ $? -eq 0 ]; then
  say "MUTATION A SURVIVED: hook invocation block deleted yet gate passed — bluff gate"; rc=1
else
  grep -q 'hook:' "$SBX/outA.log" || { say "mutation A: gate failed but not on the hook clause"; cat "$SBX/outA.log"; rc=1; }
  [ "$rc" -eq 0 ] && say "RED flip A asserted: gate fails when the invocation block is deleted"
fi

# Mutation B — non-idempotent stub (appends on every run) must break digest identity.
cat > "$SBX/noisy-bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$JEV_FAKE_HOME/.config/jev"
printf 'noise=%s\n' "$(date +%s%N)" >> "$JEV_FAKE_HOME/.config/jev/env"
exit 0
EOF
JEV_BOOTSTRAP_STUB="$SBX/noisy-bootstrap.sh" bash "$GATE" > "$SBX/outB.log" 2>&1
if [ $? -eq 0 ]; then
  say "MUTATION B SURVIVED: non-idempotent bootstrap passed clause 2 — bluff gate"; rc=1
else
  grep -q 'idempotency' "$SBX/outB.log" || { say "mutation B: gate failed but not on the idempotency clause"; cat "$SBX/outB.log"; rc=1; }
  [ "$rc" -eq 0 ] && say "RED flip B asserted: non-idempotent bootstrap rejected by clause 2"
fi

# Mutation C - re-entrancy guard (fork-storm prevention, measured 2026-10-23).
# C1: a gate started with JEV_BOOTSTRAP_NESTED set must exit 2 "nested" and never run bootstrap.
printf '#!/usr/bin/env bash\necho x >> "$STORM_COUNT"\nexit 0\n' > "$SBX/count-stub.sh"
: > "$SBX/c1.count"
STORM_COUNT="$SBX/c1.count" JEV_BOOTSTRAP_NESTED=1 JEV_BOOTSTRAP_STUB="$SBX/count-stub.sh" \
  timeout --kill-after=5 60 bash "$GATE" > "$SBX/outC1.log" 2>&1
c1rc=$?
if [ "$c1rc" -eq 2 ] && grep -q 'nested' "$SBX/outC1.log" && [ ! -s "$SBX/c1.count" ]; then
  say "RED flip C1 asserted: nested start exits 2 without invoking bootstrap"
else
  say "MUTATION C1 SURVIVED: nested start rc=$c1rc, bootstrap invocations=$(wc -l < "$SBX/c1.count")"; rc=1
fi
# C2: a bootstrap that (like the old stage 7) re-runs the gate must terminate with a BOUNDED
# invocation count. Stub self-caps at 8 so even a broken guard cannot storm. Guarded gate
# runs the stub exactly 4 times (2 digest runs + defer + clone run); nested gate calls exit 2.
cat > "$SBX/storm-stub.sh" <<'STORM'
#!/usr/bin/env bash
n=$(wc -l < "$STORM_COUNT" 2>/dev/null || echo 0)
[ "$n" -lt 8 ] || exit 0
echo x >> "$STORM_COUNT"
timeout --kill-after=2 30 bash "$GATE_UNDER_TEST" >/dev/null 2>&1
exit 0
STORM
: > "$SBX/c2.count"
STORM_COUNT="$SBX/c2.count" GATE_UNDER_TEST="$GATE" JEV_BOOTSTRAP_STUB="$SBX/storm-stub.sh" \
  timeout --kill-after=5 120 bash "$GATE" > "$SBX/outC2.log" 2>&1
n_guard=$(wc -l < "$SBX/c2.count")
# Neutered copy: guard block removed and the child export renamed away.
mkdir -p "$SBX/n2/gates"
cp "$GATE" "$SBX/n2/gates/gate.sh"
ln -s "$HERE/fixtures" "$SBX/n2/gates/fixtures"
ln -s "$HERE/../post_update_hook.sh" "$SBX/n2/post_update_hook.sh"
python3 - "$SBX/n2/gates/gate.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s2 = re.sub(r'(?s)if \[ -n "\$\{JEV_BOOTSTRAP_NESTED:-\}" \]; then\n.*?\nfi\n', '', s, count=1)
s2 = s2.replace('JEV_BOOTSTRAP_NESTED=1', 'JEV_NEUTERED_NOT_NESTED=1')
assert s2 != s
open(p, 'w').write(s2)
PYEOF
: > "$SBX/c3.count"
STORM_COUNT="$SBX/c3.count" GATE_UNDER_TEST="$SBX/n2/gates/gate.sh" JEV_BOOTSTRAP_STUB="$SBX/storm-stub.sh" \
  timeout --kill-after=5 180 bash "$SBX/n2/gates/gate.sh" > "$SBX/outC3.log" 2>&1
n_neut=$(wc -l < "$SBX/c3.count")
if [ "$n_guard" -eq 4 ] && [ "$n_neut" -gt 4 ] && [ "$n_neut" -le 8 ]; then
  say "RED flip C2 asserted: guarded storm count=$n_guard (bounded, exact); neutered-guard count=$n_neut (>4) proves the test discriminates"
else
  say "MUTATION C2 FAILED: guarded count=$n_guard (want 4), neutered count=$n_neut (want 5..8)"; rc=1
fi

# Mutation D - a bootstrap that does nothing (no clone, no pending stamp) must be rejected.
printf '#!/usr/bin/env bash\nexit 0\n' > "$SBX/noop-stub.sh"
JEV_BOOTSTRAP_STUB="$SBX/noop-stub.sh" timeout --kill-after=5 120 bash "$GATE" > "$SBX/outD.log" 2>&1
{ [ $? -eq 1 ] && grep -q 'clone-fallback' "$SBX/outD.log"; } \
  && say "RED flip D asserted: no-op bootstrap rejected (defer + clone-fallback clauses)" \
  || { say "MUTATION D SURVIVED: no-op bootstrap accepted"; rc=1; }

if [ "$rc" -eq 0 ]; then
  say "PASS: cm_jev_bootstrap_idempotent.sh genuinely discriminates (GREEN genuine / RED mutated)"
else
  say "FAIL: mutation test detected a bluff gate"
fi
exit "$rc"
