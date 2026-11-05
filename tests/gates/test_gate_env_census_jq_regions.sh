#!/usr/bin/env bash
# tests/gates/test_gate_env_census_jq_regions.sh -- the jq whole-environment read (`env |`, bare `$ENV`, row `jq-env`)
# of scripts/gates/lib/gate_env_census.py is reported only for quoted text that is jq code: quoted text on a command line
# that runs jq (backslash continuations included), or quoted text assigned to a variable that a jq command line expands.
# Root cause it guards (2026-11-04): the old rule armed the check for EVERY quoted region of a file as soon as the word `jq`
# appeared anywhere in it, so `jq -e . "$0"` added to cm_killpg_pgid_guard.sh reported its awk classifier
# (`...|timeout|env|command|...`, a quoted heredoc read into SHAWK) as a jq env dump at line 423; that made
# test_gate_env_census_closure.sh "N3 negative" FAIL.
# Real census module, real files in a mktemp dir. Positives must still fire (no lost coverage); negatives must not.
# Exit status: 0 = every case PASS; 1 = at least one FAIL (or XPASS); 3 = no FAIL, but at least one KNOWN-FAIL case is
# outstanding (the same convention as test_gate_env_census_closure.sh). A KNOWN-FAIL is never counted as PASS; it names
# the tracked item that owns it, and its exact failure signature is checked (a different failure is a FAIL). When a
# KNOWN-FAIL case starts to pass it is reported XPASS and counted as FAIL, so the marker has to be removed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
CEN="$src/scripts/gates/lib/gate_env_census.py"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0; known=0
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
# kcase_ <id> <line> <description>: KNOWN-FAIL pinned to CON-047 (a shape the census reports although it is not jq code;
# the fail-closed direction). Signature: census rc 0 and exactly ONE jq-env row, at <line>. No jq-env row -> XPASS (FAIL:
# turn it into `case_ <id> quiet`); any other result -> FAIL. These are corpus cases for the structural rewrite (CON-047):
# they are recorded, not fixed by another regex owner rule (section 11.4.250).
kcase_() {
  local id="$1" ln="$2" desc="$3" f="$sb/$1.sh" out rc rows
  cat > "$f"
  out="$(python3 -I "$CEN" --root "$sb" "$f" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then fail=$((fail+1)); echo "FAIL $id $desc (census rc=$rc: $out)"; return; fi
  rows="$(grep -cP '\tjq-env\t' <<<"$out")"
  if [ "$rows" = 0 ]; then fail=$((fail+1)); echo "XPASS $id $desc (KNOWN-FAIL pinned to CON-047 is now quiet: make it a quiet case)"; return; fi
  if [ "$rows" = 1 ] && grep -qP "\tjq-env\tindirect\t${ln}\$" <<<"$out"; then
    known=$((known+1)); echo "KNOWN-FAIL $id $desc [tracked CON-047] (one jq-env row at line $ln)"
  else
    fail=$((fail+1)); echo "FAIL $id $desc: failure does NOT match the CON-047 signature (rows=$rows: $out)"
  fi
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
# review round 2 N1 (2026-11-05): keyword-prefixed and append assignments are assignments too. RED on the old order
# (dbe1b65); kill reviewer mutants RN1 (no whitespace before NAME= in RE_OWNER_ASSIGN: G6 G7 G8) and RN7 (`+=` not
# counted: G9).
case_ G6 fire "local P=...; awk on the assignment line" <<'EOF'
f() {
  local P='env | keys'; awk 1 f
  jq -n "$P"
}
EOF
case_ G7 fire "export P=...; sed on the assignment line" <<'EOF'
export P='$ENV'; sed -n 1p f
jq -n "$P"
EOF
case_ G8 fire "declare -r P=...; grep on the assignment line" <<'EOF'
declare -r P='env | keys'; grep -q x f
jq -n "$P"
EOF
case_ G9 fire "P+=...; sed on the assignment line" <<'EOF'
P+='env | keys'; sed -n 1p f
jq -n "$P"
EOF
# review round 2 N3 / F7: two quoted regions of one line are not glued into one word (RED before the separator that
# split_code appends at each closing single quote)
case_ S1 fire "jq --arg k 'v' -n 'env | keys' (an earlier --arg value on the jq line)" <<'EOF'
jq --arg k 'v' -n 'env | keys'
EOF
case_ S2 fire "jq -n '.a' | jq 'env' (two jq programs on one line)" <<'EOF'
jq -n '.a' | jq 'env'
EOF
case_ S3 fire "jq -n \"\$(printf '%s' 'env | keys')\" (printf format before the program)" <<'EOF'
jq -n "$(printf '%s' 'env | keys')"
EOF
# --- KNOWN-FAIL corpus (CON-047): not jq code, reported anyway; quiet is the wanted result -------------------------------
# K1..K4 (review round 2 N2): the assignment rule (2) runs before the interpreter rule (3), so a NAME= that is an awk -v
# option, an environment prefix of an interpreter, or a word in an option argument owns the region. K5: with the round-3
# separator a data argument of jq is its own region (`jq -n '.a' 'env'`: 'env' is a file name), the program-operand class.
kcase_ K1 2 "awk -v re='^(sudo|env|time)\$' (option argument, not a shell variable)" <<'EOF'
jq --version
awk -v re='^(sudo|env|time)$' '$1 ~ re' f
EOF
kcase_ K2 2 "PAT='env|x' awk ... (environment prefix of awk)" <<'EOF'
jq --version
PAT='env|x' awk 'BEGIN{print ENVIRON["PAT"]}'
EOF
kcase_ K3 2 "env PAT='^(env|nice)\$' sed ... (env wrapper prefix of sed)" <<'EOF'
jq --version
env PAT='^(env|nice)$' sed -n p f
EOF
kcase_ K4 2 "grep -E -e x='(env|sudo)' f (a grep pattern word containing x=)" <<'EOF'
jq --version
grep -E -e x='(env|sudo)' f
EOF
kcase_ K5 1 "jq -n '.a' 'env' (a data argument of jq, not its program)" <<'EOF'
jq -n '.a' 'env'
EOF
echo "== $pass passed, $fail failed, $known known-failure =="
[ "$fail" = 0 ] || exit 1
[ "$known" = 0 ] || exit 3
