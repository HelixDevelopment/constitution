#!/usr/bin/env bash
# tests/gates/test_gate_env_census_jq_regions.sh -- the jq whole-environment read (`env |`, bare `$ENV`, row `jq-env`)
# of scripts/gates/lib/gate_env_census.py is reported only for quoted text that is jq code: quoted text on a command line
# that runs jq (backslash continuations included), or quoted text assigned to a variable that a jq command line expands.
# Root cause it guards (2026-11-04): the old rule armed the check for EVERY quoted region of a file as soon as the word `jq`
# appeared anywhere in it, so `jq -e . "$0"` added to cm_killpg_pgid_guard.sh reported its awk classifier
# (`...|timeout|env|command|...`, a quoted heredoc read into SHAWK) as a jq env dump at line 423; that made
# test_gate_env_census_closure.sh "N3 negative" FAIL.
# Real census module, real files in a mktemp dir. Positives must still fire (no lost coverage); negatives must not.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
CEN="$src/scripts/gates/lib/gate_env_census.py"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
chk() { if [ "$1" = 0 ]; then pass=$((pass+1)); echo "PASS $2"; else fail=$((fail+1)); echo "FAIL $2"; fi; }
# case <id> <expect:fire|quiet> <description> ; file body on stdin
case_() {
  local id="$1" want="$2" desc="$3" f="$sb/$1.sh" out rc
  cat > "$f"
  out="$(python3 -I "$CEN" --root "$sb" "$f" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then chk 1 "$id $desc (census rc=$rc: $out)"; return; fi
  if grep -qP '\tjq-env\tindirect\t' <<<"$out"; then got=fire; else got=quiet; fi
  [ "$got" = "$want" ]; chk $? "$id $desc (want=$want got=$got)"
}
# --- positives: jq code, must still be reported -------------------------------------------------------------------
case_ P1 fire "jq -n 'env | keys' on the jq line" <<'EOF'
jq -n 'env | keys'
EOF
case_ P2 fire "program in a variable, then jq \"\$PROG\"" <<'EOF'
PROG='env | keys'
jq -n "$PROG"
EOF
case_ P3 fire "quoted heredoc read into Q, then jq \"\${Q}\"" <<'EOF'
read -r -d '' Q <<'X' || true
env | keys
X
jq -n "${Q}"
EOF
case_ P4 fire "backslash-continued jq command, program on the next line" <<'EOF'
jq -n \
  'env | keys'
EOF
case_ P5 fire "bare \$ENV in a jq program" <<'EOF'
jq -n '$ENV'
EOF
case_ P6 fire "quoted heredoc fed straight to jq" <<'EOF'
jq -n -f /dev/stdin <<'X'
env | keys
X
EOF
# --- negatives: not jq code, must not be reported ------------------------------------------------------------------
case_ N1 quiet "awk heredoc read into SHAWK (not passed to jq) in a file that also runs jq" <<'EOF'
read -r -d '' SHAWK <<'AWKEOF' || true
{ if ($1 ~ /^(sudo|timeout|env|command)$/) print }
AWKEOF
awk "$SHAWK" /dev/null
jq -e . "$0" >/dev/null
EOF
case_ N2 quiet "awk program on its own line with |env| in a file that also runs jq" <<'EOF'
awk '/^(timeout|env|command)$/'
jq -e . "$0" >/dev/null
EOF
case_ N3 quiet "no jq in the file at all" <<'EOF'
awk '/^(timeout|env|command)$/'
EOF
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
