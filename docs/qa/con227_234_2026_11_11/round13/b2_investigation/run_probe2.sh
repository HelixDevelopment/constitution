#!/bin/bash
# run_probe2.sh E: runs p5.sh exactly as test_redact_cut.sh line 294 (no sampler, so the task count is minimal)
E="${1:?}"
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$E/p5.sh" 2>&1)"; r8=$?
printf 'r8=%s\n' "$r8"
printf '%s\n' "$o8" | head -n 12
case "$r8:$o8" in 0:*"rc=4"*"a0=rc-clean-env"*) echo "K8_N2=ok (the mutant passes K8 N2)";; *) echo "K8_N2=bad (the mutant is caught by K8 N2)";; esac
