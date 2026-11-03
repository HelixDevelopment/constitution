#!/usr/bin/env bash
# golden-good demo gate: one guarded override, one allowlisted data channel, locals assigned before use.
cm_gate_env_set root DEMO_ROOT "" path
cfg="${DEMO_CONFIG:-}"
n=0; n=$((n+1))
echo "$root $cfg $n"
