#!/usr/bin/env bash
# test_python_isolation.sh — every Python program the install scripts run is isolated (`python3 -I`): a module in
# the current directory or on PYTHONPATH is never imported (CON-PENDING-installer-followups).
#
# Why: `python3 -c PROGRAM` puts the current directory first on sys.path and honours PYTHONPATH, so a file named
# json.py in the directory the operator runs the script from (an untrusted checkout, a download directory) runs
# with the operator's rights when the program does `import json`. `-I` drops both (and the user site directory).
#
# Sections:
#   1. static census: in the six install scripts, every line that runs python3/python as a command carries -I in its
#      first three words. Control needles: the census sees a known -I line as isolated and a planted line without -I
#      as not isolated (else BLIND, exit 2).
#   2. behaviour, install_action_prefix.sh python path (jq hidden from PATH): a planted json.py in the current
#      directory and a planted json.py on PYTHONPATH must not run, and the merge must still happen (the hook entry
#      is in settings.json). Control needle: the same planted file IS imported by `python3 -c 'import json'` in
#      that directory (the plant works), and jq is really absent on the test PATH.
#
# TEST-CLASS LABEL (§11.4.289): unit class. A sandbox copy of the script and its hook, no network, no agent.
# Usage: bash tests/install/test_python_isolation.sh   Exit 0 all pass · 1 a case failed · 2 blind.
# shellcheck disable=SC2034  # T_NAME is read by finish() in lib.sh
T_NAME=python_isolation
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
command -v python3 >/dev/null 2>&1 || { echo "  SKIP python3 is not on PATH (reason: tool_not_present; nothing ran)"; finish; exit 2; }

SIX=("$INSTALLER" "$UPDATER" "$REPO/scripts/install_cli_agent_plugins.sh" "$REPO/scripts/install_action_prefix.sh"
     "$REPO/scripts/portable_symlink_lib.sh" "$REPO/scripts/lib/constitution_layout.sh")

# ── 1. static census ──
# shellcheck disable=SC2016  # Python source
census='import re, sys
cmd = re.compile(r"(?:^|[;&|(`]|\$\(|\bthen\b|\bdo\b|\belse\b)\s*(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|\x27[^\x27]*\x27|\S*)\s+)*(?:env\s+(?:-\S+\s+)*(?:[A-Za-z_]\w*=\S*\s+)*)?(?:command\s+)?(python3?)(?=\s)(\s+[^|;&)]*)?")
for f in sys.argv[1:]:
    for n, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
        if line.lstrip().startswith("#"): continue
        for m in cmd.finditer(line):
            a = (m.group(2) or "").split()
            st = "I" if any(re.fullmatch(r"-[A-Za-z]*I[A-Za-z]*", x) for x in a[:3]) else "NO-I"
            print("%s:%d\t%s\t%s" % (f, n, st, line.strip()[:120]))'
ndl="$SB/needle.sh"
printf '%s\n' "x=1; python3 -I -c 'print(1)'" 'y="$(HELIX_X=1 python3 -c "$prog" a b)"' >"$ndl"
nd="$(python3 -I -c "$census" "$ndl")"
if [ "$(printf '%s\n' "$nd" | cut -f2 | tr '\n' ' ')" = "I NO-I " ]; then
  ok "census control needles: a -I line reads as isolated, a line without -I as not isolated"
else
  echo "  BLIND census: control needles not seen as expected: $nd"; finish; exit 2
fi
all="$(python3 -I -c "$census" "${SIX[@]}")"
bad="$(printf '%s\n' "$all" | awk -F'\t' '$2 == "NO-I"')"
eq "every python3 invocation in the six install scripts runs with -I ($(printf '%s\n' "$all" | grep -c .) found)" "" "$bad"
[ -z "$bad" ] || printf '    %s\n' "$bad"

# ── 2. behaviour: install_action_prefix.sh, python path ──
C="$SB/const"; mkdir -p "$C/scripts/hooks"
cp "$REPO/scripts/install_action_prefix.sh" "$C/scripts/"
cp "$REPO/scripts/hooks/action_prefix_expand.sh" "$C/scripts/hooks/"
NOJQ="$SB/bin-nojq"; mkdir -p "$NOJQ"
for d in /usr/local/bin /usr/bin /bin; do
  for x in "$d"/*; do
    b="${x##*/}"; [ "$b" = jq ] && continue; [ -x "$x" ] && [ ! -e "$NOJQ/$b" ] && ln -s "$x" "$NOJQ/$b"
  done
done
eq "control: jq is absent on the test PATH" "" "$(PATH="$NOJQ" command -v jq)"
P="$SB/proj"; mkdir -p "$P"; WD="$SB/wd"; mkdir -p "$WD"; PP="$SB/pp"; mkdir -p "$PP"
plant() { # dir marker → json.py that records that it was imported, then loads the real json
  printf 'import sys, importlib.util\nopen(%s, "w").write("imported")\n' "\"$2\"" >"$1/json.py"
}
plant "$WD" "$SB/pwned-cwd"; plant "$PP" "$SB/pwned-pythonpath"
(cd "$WD" && python3 -c 'import json' 2>/dev/null)
eq "control: python3 -c in that directory imports the planted json.py" imported "$(cat "$SB/pwned-cwd" 2>/dev/null)"
rm -f -- "$SB/pwned-cwd"
(PYTHONPATH="$PP" python3 -c 'import json' 2>/dev/null)
eq "control: python3 -c with that PYTHONPATH imports the planted json.py" imported "$(cat "$SB/pwned-pythonpath" 2>/dev/null)"
rm -f -- "$SB/pwned-pythonpath"
out="$(cd "$WD" && PATH="$NOJQ" PYTHONPATH="$PP" bash "$C/scripts/install_action_prefix.sh" "$P" 2>&1)"; rc=$?
eq "install_action_prefix.sh (python path) exits 0" 0 "$rc"; [ "$rc" = 0 ] || printf '%s\n' "$out" | tail -5
eq "the merge ran: the hook entry is in settings.json" 1 "$(grep -cF 'action_prefix_expand.sh' "$P/.claude/settings.json" 2>/dev/null)"
eq "a json.py in the current directory was not imported" absent "$([ -e "$SB/pwned-cwd" ] && echo present || echo absent)"
eq "a json.py on PYTHONPATH was not imported" absent "$([ -e "$SB/pwned-pythonpath" ] && echo present || echo absent)"
# PYTHONPATH alone (a clean current directory, a fresh project): the planted file in the current directory above
# would shadow the PYTHONPATH one, so this is the case that shows PYTHONPATH on its own
P2="$SB/proj2"; mkdir -p "$P2"; CLEAN="$SB/clean"; mkdir -p "$CLEAN"
out="$(cd "$CLEAN" && PATH="$NOJQ" PYTHONPATH="$PP" bash "$C/scripts/install_action_prefix.sh" "$P2" 2>&1)"; rc=$?
eq "install_action_prefix.sh (python path, PYTHONPATH planted) exits 0" 0 "$rc"; [ "$rc" = 0 ] || printf '%s\n' "$out" | tail -5
eq "the merge ran (PYTHONPATH case)" 1 "$(grep -cF 'action_prefix_expand.sh' "$P2/.claude/settings.json" 2>/dev/null)"
eq "a json.py on PYTHONPATH alone was not imported" absent "$([ -e "$SB/pwned-pythonpath" ] && echo present || echo absent)"
finish
