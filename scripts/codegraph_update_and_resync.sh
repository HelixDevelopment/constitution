#!/usr/bin/env bash
# ============================================================================
# codegraph_update_and_resync.sh — pull, refresh the CodeGraph index, commit, push
# ============================================================================
# Purpose      The operator's one-shot: pull_all, refresh the index, commit, push_all.
#              The index refresh goes ONLY through the single writer entry
#              codegraph_safe.sh (§11.4.78(7), §11.4.80(5)): `init` when the project
#              has no CodeGraph database yet, otherwise `sync` (codegraph_safe.sh
#              classifies it BULK or INCREMENTAL by pending backlog). The previous
#              one-liner (commit 00d4d50) called stock `codegraph init/sync/index`
#              and masked every failure with `|| true`, the pattern
#              CM-CODEGRAPH-SAFE-INDEX-PATH forbids. A writer failure is now
#              reported and becomes this script's exit status; stock codegraph is
#              never used as a fallback.
# Usage        bash scripts/codegraph_update_and_resync.sh   (run from the project)
# Inputs       pull_all, commit, push_all: the operator's own helper commands
#              (shell functions or executables; UNKNOWN to this repository). They
#              keep their original `|| true` handling, unchanged.
#              CG_UPDATE_SAFE_BIN  writer entry (default: codegraph/codegraph_safe.sh
#              beside this script; the override exists for the tests)
# Outputs      the helpers' and codegraph_safe.sh's output; a FAILED line on error
# Exit codes   0 all well; otherwise the writer entry's exit status (see
#              codegraph_safe.sh), or 127 when the writer entry is missing
# Side effects whatever pull_all / commit / push_all do; the index writes of
#              codegraph_safe.sh under <project>/.codegraph/
# Dependencies bash, git (project root), codegraph_safe.sh
# Cross-refs   codegraph/codegraph_safe.sh, codegraph/codegraph_guard.sh,
#              codegraph/tests/test_update_and_resync.sh, codegraph/tests/test_guard.sh G9
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE="${CG_UPDATE_SAFE_BIN:-$HERE/codegraph/codegraph_safe.sh}"

(pull_all || true)

PROJECT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -e "$PROJECT/.codegraph/codegraph.db" ]; then OP=sync; else OP=init; fi
if [ -f "$SAFE" ]; then
    bash "$SAFE" "$OP"; CG_RC=$?
else
    echo "codegraph_update_and_resync: writer entry not found: $SAFE (stock codegraph is never used)" >&2
    CG_RC=127
fi
[ "$CG_RC" -eq 0 ] || echo "codegraph_update_and_resync: codegraph_safe.sh $OP FAILED (rc=$CG_RC)" >&2

(commit || true) && (push_all || true)
exit "$CG_RC"
