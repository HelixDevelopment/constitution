#!/usr/bin/env bash
# ============================================================================
# test_scope_exceptions_mutations.sh — paired §1.1 mutation harness for the
# scope-exceptions mechanism (load_exceptions/cmd_scope in codegraph_safe_helper.py)
# ============================================================================
# Purpose      Prove every safety guarantee of the scope-exceptions mechanism is
#              load-bearing, not decorative: the GOLDEN tool passes
#              test_scope_exceptions.py; each mutant (allowlist-class check
#              disabled, exact-path/glob check disabled, exceptions silently
#              ignored, verdict logic broken, malformed line tolerated, absent
#              file mishandled) MUST make the suite FAIL. A surviving mutant is a
#              test that cannot catch that specific defect class.
# Usage        bash test_scope_exceptions_mutations.sh   (exit 0 only if golden
#              passes AND every mutant is killed)
# Inputs       ../codegraph_safe_helper.py, ./test_scope_exceptions.py
# Outputs      lines `GOLDEN PASS|FAIL` and `MUTANT Mn KILLED|SURVIVED <what>`;
#              exit 1 on any golden failure or survivor
# Side effects temp dir under $TMPDIR (removed on exit); never touches the real
#              tool or any repo file
# Dependencies bash, python3
# Cross-refs   codegraph_safe_helper.py, test_scope_exceptions.py,
#              docs/scripts/codegraph_safe.md, constitution §1.1 / §11.4.10 / §11.4.224
# ============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd); GOLD="$HERE/../codegraph_safe_helper.py"
W=$(mktemp -d "${TMPDIR:-/tmp}/scope_exc_mut.XXXXXX"); trap 'rm -rf "$W"' EXIT
fail=0
run_suite() { TOOL="$1" python3 "$HERE/test_scope_exceptions.py" >"$W/out.txt" 2>&1; }
if run_suite "$GOLD"; then echo "GOLDEN PASS"; else echo "GOLDEN FAIL (see suite)"; cat "$W/out.txt"; fail=1; fi
mutate() {  # id, description, OLD, NEW (exactly-once replacement in a copy of the tool)
  local id=$1 desc=$2; cp "$GOLD" "$W/$id.py"
  OLD=$3 NEW=$4 F="$W/$id.py" python3 - <<'PY' || { echo "MUTANT $id NOT-APPLIED (anchor text moved — update harness)"; fail=1; return; }
import os,sys
p=os.environ["F"]; s=open(p,encoding="utf-8").read(); o=os.environ["OLD"]; n=os.environ["NEW"]
if s.count(o)!=1: sys.exit(1)
open(p,"w",encoding="utf-8").write(s.replace(o,n))
PY
  if run_suite "$W/$id.py"; then echo "MUTANT $id SURVIVED $desc"; fail=1; else echo "MUTANT $id KILLED $desc"; fi
}
mutate M1 "credential-content class allowlist disabled (env_file/keystore could be excepted)" \
  'if cls not in ALLOWED_EXCEPTION_CLASSES:' 'if False:'
mutate M2 "exact-path/glob-pattern guard disabled (a pattern would be accepted as an exception)" \
  'if exact_path.startswith("/") or "*" in exact_path or "?" in exact_path:' 'if False:'
mutate M3 "exceptions silently ignored (loaded but never subtracted from hits)" \
  'remaining = sorted(hits - excepted)' 'remaining = sorted(hits)'
mutate M4 "verdict always PASS regardless of remaining hits (the whole scope check goes vacuous)" \
  'verdict = "PASS" if n == 0 else "FAIL"' 'verdict = "PASS"'
mutate M5 "malformed exceptions line silently tolerated instead of refused" \
  'raise ValueError(f"bad exceptions line: {ln!r}")' 'continue'
mutate M6 "missing exceptions file no longer treated as empty (breaks 2-arg backward-compat call)" \
  'if not path or not os.path.isfile(path):
        return exc' 'if False:
        return exc'
mutate M7 "excepted-hit intersection dropped (a typo/unrelated exception line silently counts anyway)" \
  'excepted = exceptions.get(cls, set()) & hits' 'excepted = exceptions.get(cls, set())'
exit $fail
