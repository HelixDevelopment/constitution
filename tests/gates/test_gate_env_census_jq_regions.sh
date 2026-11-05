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
# --- CON-017 (closure-test N3 negative): an awk program written to a file and run as `awk -f "$FILE"` is awk's ------------
# Root cause (2026-11-05): cm_killpg_pgid_guard.sh holds its awk classifier in SHAWK, writes it with
# `printf '%s\n' "$SHAWK" > "$SHAWKF"` and runs `awk -f "$SHAWKF"`. The census saw SHAWK expanded on a line that is not an
# interpreter line, kept it ARMED, and so reported the awk text (`|timeout|env|command|`) as a jq env dump as soon as the
# file gained any jq word (test_gate_env_census_closure.sh "N3 negative"). Only this exact write-then-run-by-the-same-
# interpreter chain is disowned; every other use of either variable keeps the region armed.
case_ W1 quiet "program written by printf to \$F, run only as awk -f \$F" <<'EOF'
read -r -d '' SH <<'X' || true
/^(timeout|env|command)$/
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq -e . "$0" >/dev/null
EOF
case_ W2 fire "same chain, but the file is also read by jq -f" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq -n -f "$F"
EOF
case_ W3 fire "same chain, but the file is passed to an unknown command" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
run_tool "$F"
jq -e . "$0" >/dev/null
EOF
case_ W4 fire "same chain, but the program variable is also echoed elsewhere" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
echo "$SH"
jq -e . "$0" >/dev/null
EOF
case_ W5 fire "written to a literal path (the later use cannot be tied to it)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
printf '%s\n' "$SH" > /tmp/p.awk
awk -f /tmp/p.awk in
jq -e . "$0" >/dev/null
EOF
case_ W6 fire "file rewritten on a line that also runs jq -f" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
printf '%s\n' "$SH" > "$F" && jq -n -f "$F"
EOF
case_ W7 fire "target also expanded elsewhere on the write line" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F" && cat "$F"
awk -f "$F" in
jq -e . "$0" >/dev/null
EOF
case_ W8 fire "program variable expanded twice on the write line" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"; echo "$SH"
awk -f "$F" in
jq -e . "$0" >/dev/null
EOF
case_ W9 fire "write line that also runs jq (no jq program text on it)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"; jq --version
awk -f "$F" in
EOF
# --- CON-017 class fix (2026-11-05, independent review delta 3: I-1, I-2, m-1, m-2, m-3) ------------------------------
# The write-then-run disown above held only for its own exact chain; the review showed it disowned 13 more shapes.
# The class rule now: a program variable V (and its file F) is disowned only when EVERY command SEGMENT (split at ; && || | &)
# that expands it provably runs a non-jq interpreter, judged on the RAW text (a quoted program that runs jq is not
# non-jq), V/F never appear inside quoted text (eval '..', sh -c '..', a heredoc for a child shell), are never exported,
# an interpreter really runs F, F's value names no jq program, and no jq command in the file can take its program from a
# file, a command substitution or a variable. Controls: W1 (quiet) and P2/D1ctl (fire) prove the instrument sees both ways.
case_ D2 fire "file only written, never run by any interpreter" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"
printf '%s\n' "$SH" > "$F"
jq -e . "$0" >/dev/null
EOF
case_ D1 fire "file target named like a jq program (F=\$d/p.jq)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p.jq"
printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq --version
EOF
case_ D1ctl fire "control: cat >\"\$d/p.jq\" heredoc (file-owner rule)" <<'EOF'
cat >"$d/p.jq" <<'X'
env | keys
X
jq --version
EOF
case_ D3 fire "file value from mktemp --suffix=.jq" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$(mktemp --suffix=.jq)"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq --version
EOF
case_ C1 fire "path re-spelled: F=\$WORK/f, jq -f \"\$WORK/f\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
WORK="$d"; F="$WORK/f"
printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq -n -f "$WORK/f"
EOF
case_ C2 fire "awk runs F, then cd + relative path to jq -f" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && jq -n -f f
EOF
case_ C3 fire "awk runs F, then find -exec jq -f {}" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
find "$d" -name f -exec jq -n -f {} \;
EOF
case_ C4 fire "awk runs F, then jq program from a command substitution" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && jq -n "$(cat f)"
EOF
case_ C5 fire "awk runs F, then xargs jq -f" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
echo f | xargs jq -n -f
EOF
case_ C6 fire "awk runs F, then a wrapper function defined here runs jq -f" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
run_j() {
  jq "$@"
}
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && run_j -n -f f
EOF
case_ C7 fire "awk runs F, then the program is read back into a variable and given to jq" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
read -r -d '' P < "$d/f" || true
jq -n "$P"
EOF
case_ N1x fire "awk runs F, then jq -f \"\$R\" through declare -n R=F" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
declare -n R=F
jq -n -f "$R"
EOF
case_ N2x fire "awk runs F, then jq -f \"\${!X}\" with X=F" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
X=F
jq -n -f "${!X}"
EOF
case_ X1 fire "awk runs F, F exported, child shell from a quoted heredoc runs jq -f \"\$F\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
export F
bash <<'EOT'
jq -n -f "$F"
EOT
EOF
case_ X2 fire "awk runs F, F exported to a child script the census cannot read" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
export F
bash "$d/child.sh"
jq -e . "$0" >/dev/null
EOF
case_ X3 fire "awk runs F under set -a (every assignment exported)" <<'EOF'
set -a
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
bash "$d/child.sh"
jq -e . "$0" >/dev/null
EOF
case_ E1 fire "awk runs F, eval 'jq -n -f \"\$F\"' (F inside quoted text)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
eval 'jq -n -f "$F"'
EOF
case_ E2 fire "chk \"filter\" eval 'jq -n -f \"\$F\"' on one line" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
chk() { shift; "$@"; }
F="$d/p"; printf '%s\n' "$SH" > "$F"
chk "filter" eval 'jq -n -f "$F" >/dev/null'
EOF
case_ E3 fire "eval \$'jq -n -f \"\$F\"' (ANSI-C quoted)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
eval $'jq -n -f "$F"'
EOF
case_ E4 fire "awk runs F, program variable hidden in eval 'jq -n \"\$SH\"'" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
eval 'jq -n "$SH"'
EOF
case_ E5 fire "direct variable: awk \"\$P\" f, then eval 'jq -n \"\$P\"'" <<'EOF'
P='env | keys'
awk "$P" f
eval 'jq -n "$P"'
EOF
case_ E6 fire "house layout: chk \"x\" \\ / eval 'jq -n -f \"\$F\"'" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
chk "x" \
  eval 'jq -n -f "$F"'
EOF
case_ L1 fire "awk -f \"\$F\" in; \"\$J\" -n -f \"\$F\" on one line" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
J=jq
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in; "$J" -n -f "$F"
EOF
case_ L2 fire "direct variable: awk \"\$P\" f; \"\$J\" -n \"\$P\" on one line" <<'EOF'
P='env | keys'
J=jq
awk "$P" f; "$J" -n "$P"
EOF
case_ L3 fire "direct variable piped: printf \"\$P\" | awk 1 | \"\$J\" -n -f /dev/stdin" <<'EOF'
P='env | keys'
J=jq
printf '%s\n' "$P" | awk 1 | "$J" -n -f /dev/stdin
EOF
case_ B0 fire "direct variable to bash -c 'jq -n \"\$1\"' _ \"\$P\"" <<'EOF'
P='env | keys'
bash -c 'jq -n "$1"' _ "$P"
EOF
case_ B1 fire "file to bash -c 'jq -n -f \"\$1\"' _ \"\$F\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
bash -c 'jq -n -f "$1"' _ "$F"
EOF
case_ B2 fire "file to python3 -c '... subprocess.run([\"jq\",...])' \"\$F\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
python3 -c 'import subprocess,sys; subprocess.run(["jq","-n","-f",sys.argv[1]])' "$F"
EOF
case_ A1x fire "file to awk 'BEGIN{system(\"jq -n -f \" ARGV[1])}' \"\$F\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk 'BEGIN{system("jq -n -f " ARGV[1])}' "$F"
EOF
case_ A2 fire "file to awk whose program variable runs jq: awk \"\$Q\" \"\$F\"" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
Q='BEGIN{system("jq -n -f " ARGV[1])}'
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk "$Q" "$F"
EOF
case_ A4 fire "file to python3 \"\$H\" where H was written from a program that runs jq" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
read -r -d '' PYH <<'X' || true
import subprocess, sys; subprocess.run(["jq", "-n", "-f", sys.argv[1]])
X
H="$d/h.py"; printf '%s\n' "$PYH" > "$H"
F="$d/p"; printf '%s\n' "$SH" > "$F"
python3 "$H" "$F"
EOF
case_ S1 fire "program written twice to the same file on one line" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"; printf '%s\n' "$SH" >> "$F"
awk -f "$F" in
jq -e . "$0"
EOF
case_ S2 fire "two targets: F run by awk, T by \${JQ:-jq} -f (every target must be safe)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
T="$d/q"; printf '%s\n' "$SH" > "$T"
"${JQ:-jq}" -n -f "$T"
EOF
case_ S3 fire "two targets: F run by awk, T passed to an unknown command" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
T="$d/q"; printf '%s\n' "$SH" > "$T"
run_tool "$T"
jq -e . "$0" >/dev/null
EOF
case_ R1 fire "two redirects on one write (> \"\$F\" > \"\$G\"): the output goes to G" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; G="$d/q"
printf '%s\n' "$SH" > "$F" > "$G"
awk -f "$F" in
run_tool "$G"
jq -e . "$0" >/dev/null
EOF
case_ D4 fire "file variable also assigned by read (its value is unknown)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; read -r F < "$d/name"
printf '%s\n' "$SH" > "$F"
awk -f "$F" in
jq --version
EOF
case_ S4 fire "file path itself written to a list file passed to an unknown command" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; G="$d/list"
printf '%s\n' "$SH" > "$F"
awk -f "$F" in
printf '%s\n' "$F" > "$G"
run_tool "$G"
jq -e . "$0" >/dev/null
EOF
case_ C8 fire "awk runs F, then an unassigned command variable runs -f on a relative path" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && "$TOOL" -n -f f
jq -e . "$0" >/dev/null
EOF
case_ C9 fire "awk runs F, then a command variable holding jq (J=jq) runs -f on a relative path" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
J=jq
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && "$J" -n -f f
EOF
case_ Q4ctl quiet "control: a command variable holding a literal non-jq word runs -f (not jq-capable)" <<'EOF'
read -r -d '' SH <<'X' || true
/^(timeout|env|command)$/
X
A=awk
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && "$A" -f f in
jq -e . "$0" >/dev/null
EOF
case_ C10 fire "awk runs F, then a command word from a command substitution runs -f on a relative path" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/f"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && $(get_tool) -n -f f
jq -e . "$0" >/dev/null
EOF
case_ L4 fire "direct variable piped to awk, then to an unassigned command variable (pipe splits segments)" <<'EOF'
P='env | keys'
printf '%s\n' "$P" | awk 1 | "$TOOL" -n -f /dev/stdin
jq -e . "$0" >/dev/null
EOF
case_ Q1ctl quiet "control: grep -E -f \"\$F\" (non-jq interpreter) runs the written file" <<'EOF'
read -r -d '' SH <<'X' || true
^(env|x)$
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
grep -E -f "$F" in
jq -e . "$0" >/dev/null
EOF
case_ Q2ctl quiet "control: two interpreter runs of F, jq with a literal program elsewhere" <<'EOF'
read -r -d '' SH <<'X' || true
/^(timeout|env|command)$/
X
F="$d/p.awk"; printf '%s\n' "$SH" > "$F"
{ awk -f "$F" in; cat in2; } > out
awk -f "$F" out >> res
jq -n '.a' >/dev/null
EOF
case_ Q3ctl quiet "control: a direct variable read only by awk, jq elsewhere with a literal program" <<'EOF'
P='/^(timeout|env|command)$/'
awk "$P" f
jq -e . "$0" >/dev/null
EOF
# --- known limits (pinned QUIET: a static text scan cannot see these; if one starts to fire, update the CON-017 comment) --
case_ K1 quiet "KNOWN LIMIT: wrapper function defined outside the file (sourced, unseen) runs jq -f on the file" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
cd "$d" && qq_from_lib p
jq -e . "$0" >/dev/null
EOF
case_ K2 quiet "KNOWN LIMIT: F given to an interpreter running a script from disk the census cannot read (it may run jq)" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
python3 "$d/tool.py" "$F"
jq -e . "$0" >/dev/null
EOF
case_ K3 quiet "KNOWN LIMIT: an alias (alias J=jq) used as the command word with a relative path" <<'EOF'
read -r -d '' SH <<'X' || true
env | keys
X
F="$d/p"; printf '%s\n' "$SH" > "$F"
awk -f "$F" in
alias J=jq
cd "$d" && J p
EOF
echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
