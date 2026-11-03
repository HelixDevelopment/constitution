#!/usr/bin/env bash
# F4 regression: an EMPTY detection record with llmctl unavailable must make cm_jev_detection.sh BLIND (rc 2),
# never GREEN, unless HELIX_TEST_MODE=1; and the verdict line must name the record it read (§11.4.201(6)).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
GATE="${JEV_GATE_UNDER_TEST:-$ROOT/scripts/gates/cm_jev_detection.sh}"   # the mutation test points this at a sabotaged copy
T="$(mktemp -d)"; : "${T:?}"; trap 'rm -rf -- "${T:?}"' EXIT
rec="$T/jev-detection.json"
jq -n '{version:1,generated_at:1700000000,endpoints:[],reason:"no decision endpoint",capacity:{decision_instances:0},tools:{llmctl:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""},claude_toolkit:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""}}}' > "$rec"
pass=0; failn=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 (want $3 got $2)"; failn=$((failn+1)); fi; }
nollm="$T/bin"; mkdir -p "$nollm"; for t in jq timeout dirname sed grep awk cat date mktemp head tr sort basename readlink; do p="$(command -v $t)" && ln -s "$p" "$nollm/$t"; done
out="$(env -i PATH="$nollm" HOME="$T" JEV_HOME="$T" JEV_DETECTION_FILE="$rec" "$(command -v bash)" "$GATE" 2>&1)"; rc=$?
chk "empty record + no llmctl, no test mode: BLIND rc 2" "$rc" 2
case "$out" in *"$rec"*) r=1;; *) r=0;; esac; chk "output names the record path" "$r" 1
case "$out" in *"CM-JEV-DETECTION: GREEN"*) r=1;; *) r=0;; esac; chk "no GREEN verdict" "$r" 0
out="$(env -i PATH="$nollm" HOME="$T" JEV_HOME="$T" HELIX_TEST_MODE=1 JEV_DETECTION_FILE="$rec" "$(command -v bash)" "$GATE" 2>&1)"; rc=$?
chk "same under HELIX_TEST_MODE=1: GREEN rc 0" "$rc" 0
case "$out" in *"$rec"*) r=1;; *) r=0;; esac; chk "GREEN line names the record path" "$r" 1
# N2: three more BLIND shapes, each with a shim llmctl on PATH (or the lib removed); positive control stays RED.
shim() { # <name> <status-script-body> : builds a PATH dir with an llmctl shim
  local d="$T/shim.$1"; mkdir -p "$d"; for t in jq timeout dirname sed grep awk cat date mktemp head tr sort basename readlink; do p="$(command -v $t)" && ln -sf "$p" "$d/$t"; done
  printf '#!/bin/sh\ncase "$2" in status) %s ;; *) echo "{}" ;; esac\n' "$2" > "$d/llmctl"; chmod +x "$d/llmctl"; echo "$d"
}
runp() { env -i PATH="$1" HOME="$T" JEV_HOME="$T" JEV_DETECTION_FILE="$rec" "$(command -v bash)" "${2:-$GATE}" 2>&1; }
d="$(shim err 'echo "{\"error\":\"daemon down\"}"; exit 1')"; out="$(runp "$d")"; rc=$?
chk "N2a llmctl exits 1 with valid error JSON: BLIND rc 2" "$rc" 2
d="$(shim err2 'echo "{\"profiles\":[]}"; exit 1')"; out="$(runp "$d")"; rc=$?
chk "N2a2 llmctl exits 1 with a well-shaped empty status: BLIND rc 2" "$rc" 2
for body in 'echo null' 'echo 42' 'echo "{\"profiles\":\"x\"}"'; do
  d="$(shim shape "$body")"; out="$(runp "$d")"; rc=$?; chk "N2b status shape [$body]: BLIND rc 2" "$rc" 2
done
d="$(shim ok 'echo "{\"profiles\":[]}"')"; out="$(runp "$d")"; rc=$?; chk "N2 control: well-formed empty status stays GREEN rc 0" "$rc" 0
case "$out" in *"llmctl consulted: $d/llmctl"*) r=1;; *) r=0;; esac; chk "GREEN line prints the llmctl path consulted" "$r" 1
d="$(shim live 'echo "{\"profiles\":[{\"profile\":\"decide-x\",\"running\":true}]}"')"; out="$(runp "$d")"; rc=$?
chk "N2 positive control: running decide profile + empty record: RED rc 1" "$rc" 1
# (c) lib_decide.sh missing: gate copy without the library
g="$T/gcopy"; mkdir -p "$g/scripts/gates" "$g/scripts/lib"; cp "$(dirname "$GATE")/cm_jev_detection.sh" "$g/scripts/gates/"; cp "$ROOT/scripts/lib/gate_env_override.sh" "$g/scripts/lib/" 2>/dev/null
d="$(shim ok2 'echo "{\"profiles\":[]}"')"; out="$(runp "$d" "$g/scripts/gates/cm_jev_detection.sh")"; rc=$?
chk "N2c lib_decide.sh missing: BLIND rc 2" "$rc" 2
echo "== $pass passed, $failn failed =="; [ "$failn" = 0 ]
