#!/usr/bin/env bash
# scripts/label-sync/prove_adapter_mutations.sh
#
# Purpose : Paired-mutation proof (§1.1 / §11.4.115) for the CLI-agent adapters and
#           install_adapters.sh. Copies scripts/label-sync (+ the canonical labeler)
#           to a SCRATCH tree, applies ONE deliberate defect at a time, and requires
#           the hermetic suite (adapters/tests/test_adapters.sh) to FAIL for each.
#           An UNMUTATED control must pass, and a mutant whose pattern is not found
#           or that leaves the file unchanged is reported INOPERATIVE (a void proof).
# Usage   : prove_adapter_mutations.sh [--keep]
# Inputs  : none. Needs jq, python3 (>=3.11 + PyYAML), node (opencode section runs
#           only inside the full suite), and a built labelctl (labelctl.sh --build).
# Outputs : `KILLED`/`SURVIVED`/`INOPERATIVE` per mutant and a summary.
# Exit    : 0 all killed + control green | 1 survivor / inoperative / red control |
#           2 environment error.
# Mutants :
#   installer: A1 dry-run writes | A2 clobbers existing JSON config | A3 non-idempotent
#              (duplicates on re-apply) | A4 invalid JSON "repaired" instead of refused |
#              A5 no backup | A6 codex notify appended after tables | A7 ignores --home
#              (writes under the real $HOME) | A8 aider own notifications-command clobbered
#   lib/hooks: B1 adapters follow the active alias by default | B2 derived Claude effort
#              leaks into a non-Claude entity | B3 kimi hook exits 2 (would BLOCK kimi) |
#              B4 crush hook emits an allow decision | B5 wrapper swallows the exit code |
#              B6 wrapper never marks the entity done | B7 hostile id not sanitized
# Side-effects: temp dir only (removed unless --keep). Heavy-ish (runs the suite per
#           mutant): niced, run alone (§12.7).
# Cross-refs: §1.1, §11.4.115, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LSROOT="$HERE"; CONST="$(cd "$HERE/../.." && pwd)"
for b in jq python3; do command -v "$b" >/dev/null || { echo "prove_adapter_mutations: $b missing" >&2; exit 2; }; done
keep=0; [ "${1:-}" = "--keep" ] && keep=1
S="$(mktemp -d)"; [ "$keep" = 1 ] || trap 'rm -rf "$S"' EXIT
mkdir -p "$S/scripts"
cp -a "$LSROOT" "$S/scripts/label-sync"; cp -a "$CONST/scripts/multitrack" "$S/scripts/multitrack"
rm -rf "$S/scripts/label-sync/.git"
A="$S/scripts/label-sync/adapters"
export LABEL_SYNC_BIN; LABEL_SYNC_BIN="$("$LSROOT/labelctl.sh" --build 2>/dev/null | tail -1)"
run() { (cd "$S" && nice -n 10 bash "$A/tests/test_adapters.sh" ${1:+--only "$1"} >"$S/out.txt" 2>&1); }
snap() { mkdir -p "$S/orig"; cp -a "$A/." "$S/orig/"; }
restore() { rm -rf "$A" && cp -a "$S/orig" "$A"; }
snap
rc=0 killed=0 total=0
mutant() { # name  section  file  old  new
  local name="$1" sect="$2" f="$3" old="$4" new="$5"
  total=$((total+1)); restore
  if ! F="$A/$f" OLD="$old" NEW="$new" python3 - <<'PY'
import os,sys
p=os.environ["F"]; s=open(p).read(); o=os.environ["OLD"]; n=os.environ["NEW"]
if s.count(o)<1: sys.exit(3)
open(p,"w").write(s.replace(o,n,1))
PY
  then echo "INOPERATIVE $name (pattern not found: void proof)"; rc=1; return; fi
  if cmp -s "$S/orig/$f" "$A/$f"; then echo "INOPERATIVE $name (unchanged)"; rc=1; return; fi
  if run "$sect"; then echo "SURVIVED   $name"; rc=1; else echo "KILLED     $name"; killed=$((killed+1)); fi
}
if run ""; then echo "CONTROL    unmutated suite passes ($(tail -1 "$S/out.txt"))"; else echo "CONTROL FAILED"; tail -15 "$S/out.txt"; exit 1; fi

mutant "A1 dry-run writes"                  install _edit_config.py 'write = a.mode in ("apply", "remove")' 'write = True'
mutant "A2 clobbers existing JSON config"   install _edit_config.py '    if text is None or text.strip() == "":
        return {}' '    if True:
        return {}'
mutant "A3 non-idempotent (duplicates)"     install _edit_config.py 'kept = [h for h in pre if not (isinstance(h, dict) and "adapters/crush/crush-hook.sh" in str(h.get("command", "")))]' 'kept = list(pre)'
mutant "A4 invalid JSON repaired"           install _edit_config.py '        raise Refused("invalid", f"existing file is not valid JSON ({e.msg} at line {e.lineno}); refusing to touch it")' '        return {}'
mutant "A5 no backup"                       install _edit_config.py '            with open(bak, "w", encoding="utf-8") as f:
                f.write(text)
            os.chmod(bak, mode)' '            pass'
mutant "A6 codex notify after the tables"   install _edit_config.py 'new = blk + ("\n" if remainder.strip() else "") + remainder' 'new = remainder + ("\n" if remainder.strip() else "") + blk'
mutant "A7 --home ignored (real HOME used)" install install_adapters.sh '  CFG="$H/.config"            # --home pins' '  H="$HOME"; CFG="$H/.config"            # --home pins'
mutant "A8 aider own command clobbered"     install _edit_config.py '        if "notifications-command" in base or "notifications_command" in base:' '        if False:'
mutant "B1 follow active by default"        lib     lib/adapter_lib.sh 'follow=false; [ "${LABEL_SYNC_FOLLOW_ACTIVE:-}" = 1 ] && follow=true' 'follow=true'
mutant "B2 derived effort leaks"            lib     lib/adapter_lib.sh '  args+=(--model "$mdl" --effort "$eff")' '  [ -n "$mdl" ] && args+=(--model "$mdl")'
mutant "B3 kimi hook exits 2"               kimi    kimi/kimi-hook.sh 'esac
exit 0' 'esac
exit 2'
mutant "B4 crush hook emits allow"          crush   crush/crush-hook.sh "printf '{\"version\":1}\\n'" "printf '{\"version\":1,\"decision\":\"allow\"}\\n'"
mutant "B5 wrapper swallows exit code"      run     generic/label-agent-run.sh 'exit "$rc"' 'exit 0'
mutant "B6 wrapper never marks done"        run     generic/label-agent-run.sh 'cleanup() { [ "$registered" = 1 ] && al_ctl unregister --id "$id" >/dev/null; return 0; }' 'cleanup() { return 0; }'
mutant "B7 hostile id not sanitized"        lib     lib/adapter_lib.sh '  local s="${1//[^A-Za-z0-9._-]/_}" max="${2:-64}" h' '  local s="${1}" max="${2:-64}" h'
restore
echo "---"; echo "prove_adapter_mutations: $killed/$total mutants killed"
[ "$rc" = 0 ] && [ "$killed" = "$total" ]
