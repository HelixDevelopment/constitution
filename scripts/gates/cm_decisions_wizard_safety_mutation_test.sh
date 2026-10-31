#!/usr/bin/env bash
# cm_decisions_wizard_safety_mutation_test.sh — paired §1.1 mutation test for CM-DECISIONS-WIZARD-SAFETY.
# Baseline: the real wizard PASSes. Each mutant copies the REAL wizard into a mktemp dir and adds one unsafe
# behaviour; the gate MUST NOT PASS it. Exit 0 = baseline PASS and every mutant killed. Classification: universal.
set -uo pipefail
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
gate="$const/scripts/gates/cm_decisions_wizard_safety.sh"
. "$const/scripts/lib/safe_rm.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_dec_safety_mut.XXXXXX")" || exit 1
trap 'safe_rm_rf "${tmp:?}"' EXIT
pass=0; fail=0
bash "$gate" >"$tmp/base" 2>&1 && { pass=$((pass+1)); echo "  ok   baseline PASS"; } || { fail=$((fail+1)); echo "  BAD  baseline: $(cat "$tmp/base")"; }
mutant() {
  local m="$tmp/mut_$1"; mkdir -p "$m"; cp "$const/scripts/decisions/constitution_decisions.sh" "$const/scripts/decisions/decisions_engine.py" "$m/"
  python3 -I - "$m/decisions_engine.py" "$2" "$3" <<'PY' || { echo "  BAD  mutant $1 did not apply"; fail=$((fail+1)); return; }
import sys; p, old, new = sys.argv[1:]; s = open(p).read()
if old not in s: sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
  DECISIONS_CLI="$m/constitution_decisions.sh" bash "$gate" >"$m/out" 2>&1; local rc=$?
  if [ "$rc" != 0 ]; then pass=$((pass+1)); echo "  killed  $1 (rc=$rc: $(head -c 140 "$m/out"))"; else fail=$((fail+1)); echo "  SURVIVED $1"; fi
}
mutant MS1_touch_settings_json '        atomic_write(proj.sfile, new_sha + "\n", expect=False, guard=proj.guard(".constitution", False))' '        atomic_write(proj.sfile, new_sha + "\n", expect=False, guard=proj.guard(".constitution", False)); open(os.path.join(proj.root, ".claude", "settings.json"), "a").write("x")'
mutant MS2_clobber_outside_markers '        out = text + sep + lead + block' '        out = block'
mutant MS3_no_project_confinement 'if not self.contains(parent):' 'if False:'
mutant MS4_secret_accepted 'return any(r.search(s) for r in SECRET_RES)' 'return False'
mutant MS5_writes_nothing '        for p, r_, text, old in changes:' '        for p, r_, text, old in []:'
mutant MS6_stray_file '    os.unlink(proj.ifile)' '    os.unlink(proj.ifile); open(os.path.join(proj.root, "stray.txt"), "w").write("x")'
mutant MS7_export_overwrites '    if os.path.exists(p) and not a.force_export:' '    if False:'
mutant MS8_git_allowed 'FORBIDDEN_TOP = (".git", ".constitution", ".constitution-install-backup")' 'FORBIDDEN_TOP = ()'
echo "cm_decisions_wizard_safety mutation test: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
