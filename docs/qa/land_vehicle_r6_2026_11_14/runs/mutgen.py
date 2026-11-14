# mutgen.py <lander> <outdir>: writes one mutant per row; each mutation must occur exactly once
import sys, os
src = open(sys.argv[1]).read(); out = sys.argv[2]
M = [
 ("M01", "drop set +x +v (first statement)", "\nset +x +v\n", "\n:\n"),
 ("M02", "never re-exec (condition inverted)", 'if [ "${LAND_VEHICLE_EXEC:-}" != "$$" ]; then', 'if [ "${LAND_VEHICLE_EXEC:-}" = "$$" ]; then'),
 ("M03", "BASH_ENV not in the dirty list", 'LV_DIRTY=" BASH_ENV ENV ', 'LV_DIRTY=" ENV '),
 ("M04", "exported functions kept", "    case \"$n\" in BASH_FUNC_*) printf '%s\\n' \"$n\"; continue ;; esac\n", ""),
 ("M05", "folded_ri always false", "folded_ri() {\n  local -a L=()", "folded_ri() {\n  return 1\n  local -a L=()"),
 ("M06", "commit-object newness grep case-sensitive", 'if grep -aiEq -- "$key-0*$num([^0-9]|\\$)" "$objs"; then', 'if grep -aEq -- "$key-0*$num([^0-9]|\\$)" "$objs"; then'),
 ("M07", "commit-object newness only on Roadmap-Item lines (r5 form)", 'if grep -aiEq -- "$key-0*$num([^0-9]|\\$)" "$objs"; then', 'if grep -aiEq -- "^[[:space:]]*roadmap-item[[:space:]]*:.*$key-0*$num([^0-9]|\\$)" "$objs"; then'),
 ("M08", "tracker newness over main only (vehicle commits dropped)", '  [ -z "$vlist" ] || mapfile -t -O 1 TCS <<<"$vlist"\n', ''),
 ("M09", "tracker newness case-sensitive (text branch)", '    grep -aiEq -- "$1-0*$2([^0-9]|\\$)" "$3"', '    grep -aEq -- "$1-0*$2([^0-9]|\\$)" "$3"'),
 ("M10", "verify without check_state", "  state_keys\n  check_state\n  local main_before=${ST[main_before]} landed=${ST[landed_vehicle_head]} local_main\n", "  state_keys\n  local main_before=${ST[main_before]} landed=${ST[landed_vehicle_head]} local_main\n"),
 ("M11", "verify without the landed-head ancestry check", '  g merge-base --is-ancestor "$landed" "$local_main" || die 1 "local main does not contain the landed vehicle head $landed"\n  mkdir -p "$EVIDENCE_DIR"\n  do_readback verify', '  mkdir -p "$EVIDENCE_DIR"\n  do_readback verify'),
 ("M12", "read-back: landed head always counted as on the remote", '    hasl=no\n', '    hasl=yes\n'),
 ("M13", "clone path: post-init identity check dropped", '  [ "$ino1" = "$ino0" ] \\\n', '  true \\\n'),
 ("M14", "seen-blob de-duplication skips every blob", '      [ -z "${SEEN_BLOB[$dsha]:-}" ] || continue\n', '      continue\n'),
 ("M15", "folded_ri counts a whitespace-only line as a continuation (the RM08 regression)", "[[ \"${L[i+1]}\" == [$' \\t']*[![:space:]]* ]] && return 0", "[[ \"${L[i+1]}\" == [$' \\t']* ]] && return 0"),
]
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "mutants.tsv"), "w") as t:
  for mid, desc, o, n in M:
    c = src.count(o)
    if c != 1: sys.exit(f"{mid}: occurs {c} times")
    p = os.path.join(out, mid + ".sh"); open(p, "w").write(src.replace(o, n)); os.chmod(p, 0o755)
    t.write(f"{mid}\t{desc}\n")
print(len(M), "mutants")
