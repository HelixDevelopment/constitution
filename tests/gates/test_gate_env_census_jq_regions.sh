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
# --- CON-015 (F-EC1): jq reached in ways the census cannot resolve must stay ARMED ---------------------------------
# Control needles (11.4.273): P1/P5 above prove the instrument sees jq code; each A-case below runs the SAME real census.
case_ A1 fire "jq through a \${JQ_BIN:-jq} default" <<'EOF'
"${JQ_BIN:-jq}" -n 'env | keys'
EOF
case_ A1b fire "cmd=jq; \"\$cmd\" program" <<'EOF'
cmd=jq
"$cmd" -n 'env | keys'
EOF
case_ A1c fire "jq reached by an absolute path" <<'EOF'
/usr/bin/jq -n 'env | keys'
EOF
case_ A1d fire "jq through a wrapper function name" <<'EOF'
run_jq() { jq "$@"; }
run_jq -n 'env | keys'
EOF
case_ A2 fire "jq program held in an array" <<'EOF'
args=(-n 'env | keys')
jq "${args[@]}"
EOF
case_ A3 fire "program returned by a function" <<'EOF'
prog() { echo 'env | keys'; }
jq -n "$(prog)"
EOF
case_ A3b fire "heredoc program returned by a function" <<'EOF'
prog() { cat <<'X'
env | keys
X
}
jq -n "$(prog)"
EOF
case_ A4 fire "pipeline continued with a trailing | and jq on the next line" <<'EOF'
echo 'env | keys' |
  xargs -I{} jq -n {}
EOF
case_ A5 fire "region assigned to a variable passed to an unknown command" <<'EOF'
P='env | keys'
run_tool "$P"
jq -e . "$0" >/dev/null
EOF
case_ A5b fire "region assigned to a variable that is never expanded" <<'EOF'
P='env | keys'
jq -n --version
EOF
case_ A6 fire "generated program file later read by jq" <<'EOF'
cat >"$d/p.q" <<'X'
env | keys
X
jq -n -f "$d/p.q"
EOF
case_ A6b fire "generated file with a .jq name" <<'EOF'
cat >"$d/p.jq" <<'X'
env | keys
X
jq --version
EOF
# --- CON-016 (F-EC2): yq / gojq and the $'..' region owner -----------------------------------------------------------
case_ Y1 fire "yq-only file, program on the yq line" <<'EOF'
yq -n 'env | keys'
EOF
case_ Y2 fire "gojq program" <<'EOF'
gojq -n 'env | keys'
EOF
case_ Y3 fire "yq line that also runs sed (jq word must win over the interpreter)" <<'EOF'
yq e 'env | keys' <(sed s/a/b/ f)
EOF
case_ Y4 fire "gojq line that also runs awk" <<'EOF'
gojq -n 'env | keys' <(awk 1 f)
EOF
case_ D1 fire "\$'..' region on the jq line" <<'EOF'
jq -n $'env | keys'
EOF
case_ D2 quiet "\$'..' region on an awk line must not inherit the jq owner of the previous region" <<'EOF'
jq -n '.'
awk $'/^(env|x)$/'
EOF
# --- golden-FALSE: provable non-jq owners stay quiet in a file that runs jq ----------------------------------------
case_ Q1 quiet "python -c program" <<'EOF'
python3 -c 'import re; re.match("(env|x)", "env | y")'
jq -e . "$0" >/dev/null
EOF
case_ Q2 quiet "perl -ne program" <<'EOF'
perl -ne 'print if /^(env|x)$/' f
jq -e . "$0" >/dev/null
EOF
case_ Q3 quiet "sed program and grep pattern" <<'EOF'
sed -n 's/^(env|x)$/y/p' f | grep -E 'env|x'
jq -e . "$0" >/dev/null
EOF
case_ Q4 quiet "variable expanded only by awk" <<'EOF'
P='/^(timeout|env|command)$/'
awk "$P" f
jq -e . "$0" >/dev/null
EOF
case_ Q5 quiet "bash -c program with env |" <<'EOF'
bash -c 'env | sort' >/dev/null
jq -e . "$0" >/dev/null
EOF
case_ Q6 quiet "generated script (cat > file, file not named by jq)" <<'EOF'
cat >"$d/fake_tool" <<'X'
env | sed -n 's/^GIT_//p'
X
jq -e . "$0" >/dev/null
EOF
case_ Q7 quiet "awk with a wrapper and an absolute path" <<'EOF'
LC_ALL=C /usr/bin/awk '/^(timeout|env|command)$/'
jq -e . "$0" >/dev/null
EOF
# --- review census_followups (2026-11-05): cases that kill reviewer mutants M3/M4/M6/M9 --------------------------------
# M3 (all() -> any() in nonjq_vars): a variable expanded on an awk line AND on a jq line is not awk-only, so it stays armed
case_ M3 fire "variable expanded on an awk line and on a jq line" <<'EOF'
P='env | keys'
awk "$P" f
jq -n "$P"
EOF
# M4 (jq-word guard dropped in _runs_nonjq): one line that runs awk AND jq (pipe) is a jq line, not an awk-only line
case_ M4 fire "awk 1 f | jq -n \"\$P\" (line runs awk and jq)" <<'EOF'
P='env | keys'
awk 1 f | jq -n "$P"
EOF
# M6 (backslash-continuation join dropped): the awk command word and the expansion sit on different physical lines
case_ M6 quiet "awk continued over two lines, variable on the continuation line" <<'EOF'
P='/^(timeout|env|command)$/'
awk \
  "$P" f
jq -e . "$0" >/dev/null
EOF
# M9 (${#X} / ${!X} not seen as expansions): a length/indirect expansion on a non-awk line keeps the variable armed
case_ M9 fire "variable also read as \${!P} indirect expansion outside awk" <<'EOF'
P='env | keys'
awk "$P" f
echo "${!P}"
jq -e . "$0" >/dev/null
EOF
# --- review round 2 (2026-11-05): F1 a variable-held jq program is owned by the variable even when the assignment line
# also runs an interpreter or writes a file (G1..G5, RED on dbe1b65); F2 interpreter word boundary and file-writer word.
case_ G1 fire "P=...; awk on the assignment line, jq expands P later" <<'EOF'
P='env | keys'; awk 1 f
jq -n "$P"
EOF
case_ G2 fire "read -d '' Q <<X || grep, jq expands Q" <<'EOF'
read -r -d '' Q <<'X' || grep -q y f
env | keys
X
jq -n "$Q"
EOF
case_ G3 fire "P=...; echo > log on the assignment line" <<'EOF'
P='env | keys'; echo done > "$log"
jq -n "$P"
EOF
case_ G4 fire "P=...; sed on the assignment line (bare \$ENV)" <<'EOF'
P='$ENV'; sed -n 1p f
jq -n "$P"
EOF
case_ G5 fire "P='\$ENV'; x=\$(sed ...) then jq \"\$P\"" <<'EOF'
P='$ENV'; x=$(sed -n 1p f)
jq -n "$P"
EOF
# F2 / RM8: a command word that merely STARTS with an interpreter name is not that interpreter
case_ W1 fire "sedjq is not sed" <<'EOF'
sedjq -n 'env | keys'
jq --version
EOF
# F2 / RM14: only cat/printf/echo/tee disown a file; any other word before >FILE does not
case_ W2 fire "other_cmd writing a jq-through-variable region to a file" <<'EOF'
mycmd 'env | keys' > out.txt
jq --version
EOF
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
