#!/usr/bin/env bash
# test_determinism.sh — DETERMINISM (§11.4.50): three identical fresh projects, three identical REAL installer
# runs against the same REAL bare upstream; the end states MUST be identical: gitlink, .gitmodules, the
# written governance files, the porcelain status, and the report JSON once the fields that are by nature
# run-specific (timestamps, absolute paths, backup dir) are removed.
# Usage: bash tests/install/test_determinism.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=determinism
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
norm() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in ("started_at","finished_at","backup_dir","project_root","duration_s"): d.pop(k,None)
print(json.dumps(d,sort_keys=True))' "$1"; }
sig=()
for n in 1 2 3; do
  P="$SB/p$n"; new_project "$P"
  run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --report-json "$SB/r$n.json"
  eq "run $n exit 0" 0 "$RC"
  sig+=("$(gitlink "$P") $(sha256sum <"$P/.gitmodules" | cut -c1-16) $(sha256sum <"$P/CLAUDE.md" | cut -c1-16) $(sha256sum <"$P/AGENTS.md" | cut -c1-16) $(git -C "$P" status --porcelain | sha256sum | cut -c1-16) $(git -C "$P" rev-parse HEAD) $(norm "$SB/r$n.json" | sha256sum | cut -c1-16)")
done
eq "run 1 == run 2" "${sig[0]}" "${sig[1]}"
eq "run 2 == run 3" "${sig[1]}" "${sig[2]}"
echo "  signature: ${sig[0]}"
finish
