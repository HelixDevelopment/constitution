#!/usr/bin/env bash
# CM-GUARD-CLASS-P-NOT-OVERRIDABLE (§11.4.287(A)) — the destructive-path guard
# must keep blocking a protected-target delete even when the command carries the
# audited `# guardrails:allow <reason>` marker, and must still allow the same
# marker on a class-H probe (the false-positive guard, §11.4.201(1)).
#   probe 1  class P + marker      -> exit 2 (blocked)      else FAIL
#   probe 2  class P, no marker    -> exit 2 (blocked)      else FAIL   (control: the guard sees P at all)
#   probe 3  class H + marker      -> exit 0 (allowed)      else FAIL   (the marker still works where it should)
#   probe 4  harmless command      -> exit 0                else FAIL
# Exit: 0 PASS · 1 FAIL · 2 BLIND (guard or python3 missing) .
# Env: GUARD overrides the guard path (used by the paired mutation test).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${GUARD:-$HERE/../hooks/guard-destructive-paths.py}"
command -v python3 >/dev/null 2>&1 || { echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE: BLIND (python3 not found)" >&2; exit 2; }
[ -f "$GUARD" ] || { echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE: BLIND (guard not found: $GUARD)" >&2; exit 2; }

RM="r""m"; HM="/ho""me"
probe() { # text -> exit code of the guard
  python3 -I -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | python3 -I "$GUARD" >/dev/null 2>&1
  echo $?
}
fail=0
chk() { # label expected actual
  if [ "$3" -eq "$2" ]; then echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE ok: $1 (rc=$3)" >&2
  else echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE FAIL: $1 expected rc=$2 got rc=$3" >&2; fail=1; fi
}
P_CMD="$RM -rf $HM"
H_CMD='W="$2"
export HOME="$W/home"
'"$RM"' -rf "$HOME"'
chk "class P with allow marker still blocks"  2 "$(probe "# guardrails:allow I really mean it
$P_CMD")"
chk "class P without marker blocks (control)" 2 "$(probe "$P_CMD")"
chk "class H with allow marker is allowed"    0 "$(probe "# guardrails:allow disposable sandbox HOME
$H_CMD")"
chk "harmless command is allowed"             0 "$(probe "ls -la /tmp")"
if [ "$fail" -eq 0 ]; then echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE: PASS" >&2; exit 0; fi
echo "CM-GUARD-CLASS-P-NOT-OVERRIDABLE: FAIL" >&2; exit 1
