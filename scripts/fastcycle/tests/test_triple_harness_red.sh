#!/bin/sh
# T009 RED test (spec 004-fast-dev-cycles, C-005, FR-022, SC-003).
# Drives tests/lib/triple_harness.sh (absent until T010).
# UNCONFIRMED: contracts leave the harness CLI unspecified. Literal shape chosen for T010:
#   triple_harness.sh --tool <exe> --fixtures <dir>
#   <dir> holds golden-good/, golden-bad/, negative-control/ each with an `input` file;
#   harness runs `<exe> <input>` per fixture; expected rc: good=0, bad==1, neg=0.
#   stdout: one JSON object per fixture {"fixture","class","expected","actual","ok"};
#   exit 0 only if all three as expected, else 1 (2 if harness cannot run).
# shellcheck disable=SC2015 # audited every occurrence in this file (T014 round-10 MINOR-9 sweep):
# always the `<cond> && echo "ok/FAIL ..." || { ...; failx; }` TAP-style assertion idiom, or a chain of
# pure `[ ]` / `grep -q` / exit-status-only conditions with no side-effecting middle command -- so the
# "else" branch never fires for the wrong reason.
# shellcheck disable=SC2016 # every flagged instance either (a) writes a GENERATED fixture-script's
# CONTENT via a single-quoted printf format string, where the embedded $VAR must stay literal so the
# generated script's OWN shell expands it later, or (b) deliberately embeds a literal `$` character in
# a test fixture class-name string (e.g. `'golden-bad-a$b'`, proving the harness refuses such names).
# shellcheck disable=SC2059 # both flagged printf calls deliberately use their format argument's OWN
# escape-sequence interpretation (`\NNN` octal / `\n`) to produce actual bytes/newlines that a `%s`
# substitution argument would not decode; every caller of these helpers is a hardcoded literal in this
# same file (verified: no call site can ever supply a stray `%`), so there is no injection risk here.
here=$(cd "$(dirname "$0")" && pwd)
H="$here/lib/triple_harness.sh"; FX="$here/fixtures/triple_harness"; T="$FX/stub_tool.sh"
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }  # FC_TEST_FAILFAST: stop at the first failure (mutation sweeps)
run() { timeout -k 1 20 sh "$H" --tool "$T" --fixtures "$FX/$1" >/dev/null 2>&1; }
[ -f "$H" ] || { echo "RED: harness absent: $H"; failx; }
run sound;     rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL sound: expected 0 got $rc"; failx; }
run badpass;   rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL badpass (golden-bad rc 0): expected harness 1 got $rc"; failx; }
run negrefuse; rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL negrefuse (neg-control rc 1): expected harness 1 got $rc"; failx; }
# F17 (MR1 survivor): golden-good failing must be caught (harness 1, not always-ok).
run goodfail;  rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL goodfail (golden-good rc 1): expected harness 1 got $rc"; failx; }
# F16: golden-bad detection only by contract finding rc 1; BLIND(4)/126/127/signal => harness ERROR 2.
for f in blind notfound signal; do
  run $f; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL $f (golden-bad tool error): expected harness 2 got $rc"; failx; }
done
# R2-F5 (C-005): golden-bad must NAME the offending record (expected file); rc 1 + silence => mismatch.
run named;      rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL named: expected 0 got $rc"; failx; }
run noname;     rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL noname (bad rc 1 names nothing): expected 1 got $rc"; failx; }
run noexpected; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL noexpected (no expected file): expected 2 got $rc"; failx; }
# R2-F5/F6/R2-F4: any rc outside {0,1} is a tool error (2), incl. 2/3/70/128/129.
for f in exit2 exit3 exit70 exit128 exit129; do
  run $f; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL $f: tool-error expected harness 2 got $rc"; failx; }
done
# Header and code agree: header must state the 'not 0 or 1' rule.
grep -q "anything other than 0 or 1" "$H" || { echo "FAIL header does not state the tool-error rule"; failx; }
# R3-F1: dangling flag (no value) must exit 2 promptly, never loop; bounded by timeout (124 = hang).
for a in "--fixtures" "--tool" "--tool $T --fixtures" "--tool $T --fixtures $FX/sound --tool"; do
  # shellcheck disable=SC2086
  timeout -k 1 5 sh "$H" $a >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL dangling flag [$a]: expected 2 got $rc"; failx; }
done
# R3-F3: expected must hold a non-blank line; every non-empty line must be named; whole tokens only.
run blankexp;     rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL blankexp (blank expected): expected 2 got $rc"; failx; }
run wsexp;        rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL wsexp (whitespace expected): expected 2 got $rc"; failx; }
run multipartial; rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL multipartial (names only rec-1 of 2): expected 1 got $rc"; failx; }
run multifull;    rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL multifull (names both): expected 0 got $rc"; failx; }
run token10;      rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL token10 (rec-10 is not rec-1): expected 1 got $rc"; failx; }
run tokenok;      rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL tokenok (rec-1, is rec-1): expected 0 got $rc"; failx; }
# MXH: a WRONG record (tool prints something, not the expected one) must be a mismatch.
run wrongrec;     rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL wrongrec (prints wrong record): expected 1 got $rc"; failx; }
# R3-F7: header must not cite a code outside C-001 nor contradict the code.
grep -q '70 internal' "$H" && { echo "FAIL header still lists '70 internal'"; failx; }
grep -q 'bad==1' "$H" || { echo "FAIL header does not state bad==1"; failx; }
grep -q 'bad!'"=0" "$0" && { echo "FAIL test header still has the stale bad-code claim"; failx; }
# R4-F1: whole-token boundary = whitespace/start/end or an explicit delimiter (, ; ( ) [ ] { } " ' = < > | `).
# '.', '/', ':' and non-ASCII bytes can extend a record id, so they are NOT boundaries.
for f in dotted dotted2 slashed colon eacute leftalnum leftdot leftslash dotpath dotexp; do
  run $f; rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL $f (sibling id is not the record): expected 1 got $rc"; failx; }
done
for f in delims tabbound startline dotpathok dotexpok trailtab trailsp; do
  run $f; rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL $f (real token / trimmed expected): expected 0 got $rc"; failx; }
done
grep -q "explicit delimiters" "$H" || { echo "FAIL header does not define the boundary set"; failx; }
# R4-F5 MYM: a tool ERROR on golden-good / negative-control is exit 2, never a scored mismatch (1).
for f in goodblind goodblind3 negerr; do
  run $f; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL $f (non-bad fixture tool error): expected 2 got $rc"; failx; }
done
# R4-F6 (C-005): golden-good 'specified body' compared when <dir>/golden-good/expected exists (exact, whole body).
run goodbody_ok;       rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL goodbody_ok: expected 0 got $rc"; failx; }
run goodbody_multi;    rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL goodbody_multi: expected 0 got $rc"; failx; }
run goodbody_emptyok;  rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL goodbody_emptyok (empty expected, empty body): expected 0 got $rc"; failx; }
run goodbody_bad;      rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL goodbody_bad (wrong body): expected 1 got $rc"; failx; }
run goodbody_emptyexp; rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL goodbody_emptyexp (body where none expected): expected 1 got $rc"; failx; }
run goodbody_prefix;   rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL goodbody_prefix (body is a superset): expected 1 got $rc"; failx; }
# R4-F6 (C-005): one golden-bad fixture per failure class: golden-bad and every golden-bad-* dir.
run multibad_ok;      rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL multibad_ok: expected 0 got $rc"; failx; }
run multibad_rc0;     rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL multibad_rc0: expected 1 got $rc"; failx; }
run multibad_noname;  rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL multibad_noname: expected 1 got $rc"; failx; }
run multibad_noexp;   rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL multibad_noexp: expected 2 got $rc"; failx; }
run multibad_err;     rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL multibad_err: expected 2 got $rc"; failx; }
run multibad_noinput; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL multibad_noinput: expected 2 got $rc"; failx; }
jl=$(sh "$H" --tool "$T" --fixtures "$FX/multibad_ok" 2>/dev/null)
[ "$(printf '%s\n' "$jl" | wc -l)" -eq 5 ] || { echo "FAIL multibad_ok: expected 5 JSON lines"; failx; }
printf '%s\n' "$jl" | grep -q '"fixture":"golden-bad-second"' || { echo "FAIL multibad_ok: extra class not reported"; failx; }
# R4-F2: tool call bounded (FASTCYCLE_TOOL_TIMEOUT); hang => exit 2 promptly, no orphaned child.
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
printf '#!/bin/sh\nsleep 300 &\necho $! >"$PIDF"\nwait\n' >"$TD/hang.sh"; chmod +x "$TD/hang.sh"
printf '#!/bin/sh\ntrap "" TERM\nsleep 300 &\necho $! >"$PIDF"\nwait\n' >"$TD/ign.sh"; chmod +x "$TD/ign.sh"
for tl in hang ign; do
  rm -f "$TD/pid"; t0=$(date +%s)
  PIDF="$TD/pid" FASTCYCLE_TOOL_TIMEOUT=1 timeout -k 1 40 sh "$H" --tool "$TD/$tl.sh" --fixtures "$FX/sound" >/dev/null 2>"$TD/err"; rc=$?
  el=$(( $(date +%s) - t0 ))
  [ "$rc" -eq 2 ] || { echo "FAIL $tl tool: expected harness 2 got $rc"; failx; }
  [ "$el" -lt 25 ] || { echo "FAIL $tl tool: harness took ${el}s (bound not honoured)"; failx; }
  [ -s "$TD/pid" ] || { echo "FAIL $tl tool: child pid not recorded"; failx; }
  sleep 1
  if [ -s "$TD/pid" ] && kill -0 "$(cat "$TD/pid")" 2>/dev/null; then echo "FAIL $tl tool: orphaned child $(cat "$TD/pid") still alive"; kill "$(cat "$TD/pid")" 2>/dev/null; failx; fi
  grep -q "timed out" "$TD/err" || { echo "FAIL $tl tool: stderr does not say 'timed out'"; failx; }
done
# R4-F3: timeout rule 'positive integer, at most 6 characters' must reject 7+ (incl. leading zeros) and accept <=6.
for v in 0 abc -1 1x "" 1234567 12345678 0000001 12345678901234567890 000000; do
  FASTCYCLE_TOOL_TIMEOUT=$v timeout -k 1 10 sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>"$TD/err"; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL tool-timeout [$v]: expected 2 got $rc"; failx; }
  case $v in 0|000000) pat="(>= 1)" ;; *) pat="at most 6 digits: '$v'" ;; esac   # which check refused it
  grep -qF -- "$pat" "$TD/err" || { echo "FAIL tool-timeout [$v]: message lacks [$pat]"; failx; }
done
# default bound is not tiny: a golden-good taking 3 s must pass with the variable UNSET.
printf '#!/bin/sh\ncase "$1" in *golden-good*) sleep 3 ;; esac\nsed -n "s/^say=//p" "$1"\nn=$(sed -n "s/^rc=//p" "$1"); exit "${n:-2}"\n' >"$TD/slow.sh"; chmod +x "$TD/slow.sh"
env -u FASTCYCLE_TOOL_TIMEOUT timeout -k 1 30 sh "$H" --tool "$TD/slow.sh" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL default tool bound rejects a 3 s tool: rc=$rc"; failx; }
FASTCYCLE_TOOL_TIMEOUT=20000000000 timeout -k 1 10 sh "$H" --tool "$T" --fixtures "$FX/sound" 2>"$TD/err" >/dev/null
grep -q "at most 6" "$TD/err" || { echo "FAIL tool-timeout message lacks 'at most 6'"; failx; }
for v in 999999 123456 1 000001; do
  FASTCYCLE_TOOL_TIMEOUT=$v timeout -k 1 10 sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL tool-timeout accepted [$v]: expected 0 got $rc"; failx; }
done
# R5 sweep additions.
for f in twice delims2; do run $f; rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL $f: expected 0 got $rc"; failx; }; done
for f in dashsib undersib alphasib leftdash leftunder leftdigit; do
  run $f; rc=$?; [ "$rc" -eq 1 ] || { echo "FAIL $f (sibling id): expected 1 got $rc"; failx; }
done
for f in nobadinput nogoodinput nonegin; do run $f; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL $f (missing input): expected 2 got $rc"; failx; }; done
# Exact JSON contract (order golden-bad, golden-good, negative-control; every field).
exp_json='{"actual":1,"class":"golden-bad","expected":"1","fixture":"golden-bad","ok":true}
{"actual":0,"class":"golden-good","expected":"0","fixture":"golden-good","ok":true}
{"actual":0,"class":"negative-control","expected":"0","fixture":"negative-control","ok":true}'
[ "$(sh "$H" --tool "$T" --fixtures "$FX/sound" 2>/dev/null)" = "$exp_json" ] || { echo "FAIL exact JSON for sound"; failx; }
exp_bad='{"actual":1,"class":"golden-bad","expected":"1","fixture":"golden-bad","ok":false}
{"actual":0,"class":"golden-good","expected":"0","fixture":"golden-good","ok":true}
{"actual":0,"class":"negative-control","expected":"0","fixture":"negative-control","ok":true}'
[ "$(sh "$H" --tool "$T" --fixtures "$FX/noname" 2>/dev/null)" = "$exp_bad" ] || { echo "FAIL exact JSON for noname"; failx; }
exp_gb='{"actual":0,"class":"golden-bad","expected":"1","fixture":"golden-bad","ok":false}
{"actual":0,"class":"golden-good","expected":"0","fixture":"golden-good","ok":true}
{"actual":0,"class":"negative-control","expected":"0","fixture":"negative-control","ok":true}'
[ "$(sh "$H" --tool "$T" --fixtures "$FX/badpass" 2>/dev/null)" = "$exp_gb" ] || { echo "FAIL exact JSON for badpass"; failx; }
# Argument / environment errors are exit 2 with a message, never a scored result.
sh "$H" --bogus >/dev/null 2>"$TD/err"; rc=$?
[ "$rc" -eq 2 ] && grep -q "unknown arg" "$TD/err" || { echo "FAIL unknown arg: rc=$rc"; failx; }
sh "$H" --tool "$TD/nonexistent" --fixtures "$FX/sound" >/dev/null 2>"$TD/err"; rc=$?
[ "$rc" -eq 2 ] && grep -q "bad --tool" "$TD/err" || { echo "FAIL nonexistent tool: rc=$rc"; failx; }
sh "$H" --tool "" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL empty tool: rc=$rc"; failx; }
sh "$H" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL no tool: rc=$rc"; failx; }
sh "$H" --tool "$T" --fixtures "$TD/nodir" >/dev/null 2>"$TD/err"; rc=$?
[ "$rc" -eq 2 ] && grep -q "bad --fixtures" "$TD/err" || { echo "FAIL nonexistent fixtures: rc=$rc"; failx; }
sh "$H" --tool "$T" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL no fixtures: rc=$rc"; failx; }
# A tool without the exec bit is run via sh.
cp "$T" "$TD/noexec.sh"; chmod -x "$TD/noexec.sh"
sh "$H" --tool "$TD/noexec.sh" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL non-exec tool via sh: rc=$rc"; failx; }
# An executable tool is run directly (its shebang, not sh, decides): a bash-only tool works.
printf '#!/bin/bash\n[[ a == a ]] || exit 3\nsed -n "s/^say=//p" "$1"\nn=$(sed -n "s/^rc=//p" "$1"); exit "${n:-2}"\n' >"$TD/bashtool.sh"; chmod +x "$TD/bashtool.sh"
sh "$H" --tool "$TD/bashtool.sh" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL exec tool run directly: rc=$rc"; failx; }
# Temp files cleaned; unusable TMPDIR is exit 2.
mkdir "$TD/tmpd"; TMPDIR="$TD/tmpd" sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>&1
[ -z "$(ls -A "$TD/tmpd")" ] || { echo "FAIL harness leaked temp files: $(ls "$TD/tmpd")"; failx; }
TMPDIR="$TD/nodir" sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL unusable TMPDIR: rc=$rc"; failx; }
# timeout(1) absent: named, exit 2 (only shell builtins run before the check).
mkdir "$TD/empty"; PATH="$TD/empty" /bin/sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>"$TD/err"; rc=$?
[ "$rc" -eq 2 ] && grep -q "timeout(1) not found" "$TD/err" || { echo "FAIL timeout absent: rc=$rc"; failx; }
# A tool that exits 124 / 137 by itself is still a tool error (exit 2) reported as timed out/killed.
mkdir -p "$TD/x124/golden-good" "$TD/x124/golden-bad" "$TD/x124/negative-control"
printf 'rc=124\n' >"$TD/x124/golden-good/input"; printf 'rc=0\n' >"$TD/x124/negative-control/input"
printf 'rc=1\nsay=rec-1\n' >"$TD/x124/golden-bad/input"; printf 'rec-1\n' >"$TD/x124/golden-bad/expected"
sh "$H" --tool "$T" --fixtures "$TD/x124" >/dev/null 2>"$TD/err"; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL exit 124 tool: rc=$rc"; failx; }
printf 'rc=137\n' >"$TD/x124/golden-good/input"
sh "$H" --tool "$T" --fixtures "$TD/x124" >/dev/null 2>"$TD/err"; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL exit 137 tool: rc=$rc"; failx; }
# R4-F1 exhaustive boundary classes: every byte that is not an explicit delimiter (and not NL/NUL) must NOT be a boundary on
# either side; every explicit delimiter MUST be one. Tool prints <before>rec-1<after>; expected rec-1.
DELIMS_T=$(printf ' \t,;()[]{}"'"'"'=<>|`')
mkdir -p "$TD/dyn/golden-good" "$TD/dyn/golden-bad" "$TD/dyn/negative-control"
printf 'rc=0\n' >"$TD/dyn/golden-good/input"; printf 'rc=0\n' >"$TD/dyn/negative-control/input"; printf 'rec-1\n' >"$TD/dyn/golden-bad/expected"
dyn() { # before after expected-rc label
  printf 'rc=1\nsay=%s\n' "${1}rec-1${2}" >"$TD/dyn/golden-bad/input"
  timeout -k 1 20 sh "$H" --tool "$T" --fixtures "$TD/dyn" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq "$3" ] || { echo "FAIL boundary [$4]: expected $3 got $rc"; failx; }
}
n=1
while [ "$n" -le 255 ]; do
  case $n in 10) n=$((n + 1)); continue ;; esac
  c=$(printf "\\$(printf '%03o' "$n")")
  case "$DELIMS_T" in *"$c"*) want=0 ;; *) want=1 ;; esac
  dyn "$c" "" "$want" "left byte $n"
  dyn "" "$c" "$want" "right byte $n"
  n=$((n + 1))
done
# R5 round-2 sweep additions (survivors of the first mutation pass).
run emptyexp0; rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL emptyexp0 (zero-byte expected): expected 2 got $rc"; failx; }
run leadsp;    rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL leadsp (leading whitespace trimmed): expected 0 got $rc"; failx; }
run overlap;   rc=$?; [ "$rc" -eq 0 ] || { echo "FAIL overlap (second candidate one byte on is the token): expected 0 got $rc"; failx; }
errmsg() { # fixture expected-message-fragment : harness exit 2 AND that exact reason on stderr
  timeout -k 1 20 sh "$H" --tool "$T" --fixtures "$FX/$1" >/dev/null 2>"$TD/em"; rc=$?
  [ "$rc" -eq 2 ] && grep -qF -- "$2" "$TD/em" || { echo "FAIL $1: expected rc 2 with [$2], got rc=$rc: $(head -c 200 "$TD/em")"; failx; }
}
errmsg emptyexp0 "missing/empty"
errmsg noexpected "missing/empty"
errmsg blankexp "no non-blank line"
errmsg wsexp "no non-blank line"
errmsg multibad_noexp "golden-bad-second/expected"
errmsg nobadinput "golden-bad/input"
errmsg nogoodinput "golden-good/input"
errmsg nonegin "negative-control/input"
errmsg multibad_noinput "golden-bad-second/input"
: >"$TD/afile"
sh "$H" --tool "$T" --fixtures "$TD/afile" >/dev/null 2>"$TD/em"; rc=$?
[ "$rc" -eq 2 ] && grep -q "bad --fixtures" "$TD/em" || { echo "FAIL fixtures is a file: rc=$rc"; failx; }
TMPDIR="$TD/nodir" sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>"$TD/em"; rc=$?
[ "$rc" -eq 2 ] && grep -q "cannot create temp dir" "$TD/em" || { echo "FAIL unusable TMPDIR message: rc=$rc"; failx; }
# a rc>=2 golden-bad is a tool error AND its JSON line is not ok.
sh "$H" --tool "$T" --fixtures "$FX/blind" 2>/dev/null | grep -q '^{"actual":4,"class":"golden-bad","expected":"1","fixture":"golden-bad","ok":false}$' || { echo "FAIL blind golden-bad JSON must be ok:false"; failx; }
# the tool's stderr is discarded (not the harness's output channel).
printf '#!/bin/sh\necho NOISE-FROM-TOOL >&2\nsed -n "s/^say=//p" "$1"\nn=$(sed -n "s/^rc=//p" "$1"); exit "${n:-2}"\n' >"$TD/noisy.sh"; chmod +x "$TD/noisy.sh"
sh "$H" --tool "$TD/noisy.sh" --fixtures "$FX/sound" >/dev/null 2>"$TD/em"
grep -q NOISE-FROM-TOOL "$TD/em" && { echo "FAIL tool stderr leaked through the harness"; failx; }
# ROUND 5b: survivors proven NOT equivalent by the independent audit (ids 25, 69, 91, 94, 117, 123).
# mkfx <name> <badexpected-printf-arg>: fixture dir with golden-good/golden-bad/negative-control inputs.
mkfx() { d="$TD/$1"; mkdir -p "$d/golden-good" "$d/golden-bad" "$d/negative-control"
  for c in golden-good golden-bad negative-control; do echo "$c" >"$d/$c/input"; done
  printf "$2" >"$d/golden-bad/expected"; }
# id 25: an executable DIRECTORY is not a tool (-f required); an empty --tool is not a tool either.
sh "$H" --tool /usr/bin --fixtures "$FX/sound" >"$TD/o" 2>"$TD/em"; rc=$?
[ "$rc" -eq 2 ] && grep -q "bad --tool" "$TD/em" && [ ! -s "$TD/o" ] || { echo "FAIL id25: --tool <dir> rc=$rc"; failx; }
sh "$H" --tool "" --fixtures "$FX/sound" >/dev/null 2>"$TD/em"; rc=$?
[ "$rc" -eq 2 ] && grep -q "bad --tool" "$TD/em" || { echo "FAIL id25: empty --tool rc=$rc"; failx; }
# id 69: awk must run under LC_ALL=C; in a UTF-8 locale expected byte 0x80 vs printed 0xA9 must NOT match.
loc=$(locale -a 2>/dev/null | grep -i -m1 -e '^en_US\.utf-\?8$' -e '^c\.utf-\?8$')
if [ -n "$loc" ]; then
  mkfx l69 '\200\n'
  printf '#!/bin/sh\ncase "$(cat "$1")" in golden-bad) printf "\\251\\n"; exit 1 ;; esac\nexit 0\n' >"$TD/t69.sh"; chmod +x "$TD/t69.sh"
  LC_ALL=$loc timeout -k 1 20 sh "$H" --tool "$TD/t69.sh" --fixtures "$TD/l69" >"$TD/o" 2>/dev/null; rc=$?
  [ "$rc" -eq 1 ] && grep -q '"class":"golden-bad".*"ok":false' "$TD/o" || { echo "FAIL id69: locale $loc rc=$rc (mismatched byte must not name the record)"; failx; }
else echo "SKIP id69: no en_US.utf8/C.utf8 locale installed"; fi
# id 94 / 91: the whole-token scan must stay linear on large single-line output (timing bound, 40x margin).
mkfx big 'rec-1\n'
printf '#!/bin/sh\ncase "$(cat "$1")" in golden-bad) head -c 200000 /dev/zero | tr "\\0" x; echo rec-1; exit 1 ;; esac\nexit 0\n' >"$TD/t94.sh"; chmod +x "$TD/t94.sh"
FASTCYCLE_TOOL_TIMEOUT=60 timeout -k 1 6 sh "$H" --tool "$TD/t94.sh" --fixtures "$TD/big" >"$TD/o" 2>/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL id94: xxxx...rec-1 (not a token) expected 1 within 6s, got $rc (124 = quadratic scan)"; failx; }
printf '#!/bin/sh\ncase "$(cat "$1")" in golden-bad) yes rec-1 | head -n 1000000 | tr "\\n" " "; echo; exit 1 ;; esac\nexit 0\n' >"$TD/t91.sh"; chmod +x "$TD/t91.sh"
timeout -k 1 8 sh "$H" --tool "$TD/t91.sh" --fixtures "$TD/big" >"$TD/o" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL id91: 1M tokens expected 0 within 8s, got $rc (124 = no break after first hit)"; failx; }
# id 117: awk is consulted only when the golden-bad rc is 1. Tool exits 0 => harness 1 and NO stderr, even with awk absent.
P="$TD/nawk"; mkdir -p "$P"
for b in sh sed timeout mktemp rm cat; do ln -s "$(command -v $b)" "$P/$b"; done
mkfx n117 'rec-1\n'
printf '#!/bin/sh\nexit 0\n' >"$TD/t117.sh"
PATH="$P" timeout -k 1 20 "$(command -v sh)" "$H" --tool "$TD/t117.sh" --fixtures "$TD/n117" >/dev/null 2>"$TD/em"; rc=$?
[ "$rc" -eq 1 ] && [ ! -s "$TD/em" ] || { echo "FAIL id117: rc=$rc stderr=[$(head -c 120 "$TD/em")]"; failx; }
# id 123: golden-good/expected is read only when the golden-good rc is 0. Unreadable expected + tool rc 1 => no cat error.
if [ "$(id -u)" -ne 0 ]; then
  mkfx u123 'rec-1\n'; : >"$TD/u123/golden-good/expected"; chmod 000 "$TD/u123/golden-good/expected"
  if [ ! -r "$TD/u123/golden-good/expected" ]; then
    printf '#!/bin/sh\necho rec-1\nexit 1\n' >"$TD/t123.sh"; chmod +x "$TD/t123.sh"
    timeout -k 1 20 sh "$H" --tool "$TD/t123.sh" --fixtures "$TD/u123" >/dev/null 2>"$TD/em"; rc=$?
    [ "$rc" -eq 1 ] && [ ! -s "$TD/em" ] || { echo "FAIL id123: rc=$rc stderr=[$(head -c 120 "$TD/em")]"; failx; }
  else echo "SKIP id123: chmod 000 file still readable"; fi
else echo "SKIP id123: running as root"; fi
# ROUND 6 (R5-F1, R5-F9, R5-F6, R5-F7).
# Leftover-process scan keyed on an env marker (11.4.273: instrument control needles first, so an empty result is a fact).
lo_pids() { grep -la "FC_ORPH=$1" /proc/[0-9]*/environ 2>/dev/null | sed -n 's#^/proc/\([0-9]*\)/environ$#\1#p'; }
lo_kill() { for p in $(lo_pids "$1"); do [ "$p" -gt 1 ] && kill -s KILL "$p" 2>/dev/null; done; return 0; }
# shellcheck disable=SC2329 # invoked via `trap r6clean EXIT` below; the static call-graph does not
# credit a bareword `trap NAME SIGNAL` action as invoking NAME (verified false positive: same class as
# check_deps.sh's cleanup() and test_run_all.sh's sigclean() -- a trailing unconditional `exit` later
# in this file is what makes the linter lose the trap-dispatch call site).
r6clean() { for m in r6a r6b r6c r6d; do lo_kill "$m$$"; done; rm -rf "$TD"; }
trap r6clean EXIT
env FC_ORPH=r6c$$ sleep 30 & r6c=$!
i=0; while [ -z "$(lo_pids r6c$$)" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
[ -n "$(lo_pids r6c$$)" ] || { echo "FAIL r6 instrument: scan cannot see a live marked process (positive control)"; failx; }
[ -z "$(lo_pids r6neg$$)" ] || { echo "FAIL r6 instrument: scan finds an absent marker (negative control)"; failx; }
kill -s KILL "$r6c" 2>/dev/null; wait "$r6c" 2>/dev/null
# R5-F1: a descendant that keeps the tool's stdout open must not delay the verdict past the bound, and must not outlive the call.
printf '#!/bin/sh\nsleep 60 &\nexec sh "%s" "$1"\n' "$T" >"$TD/gc.sh"; chmod +x "$TD/gc.sh"
t0=$(date +%s)
env FC_ORPH=r6a$$ FASTCYCLE_TOOL_TIMEOUT=3 timeout -k 1 20 sh "$H" --tool "$TD/gc.sh" --fixtures "$FX/sound" >"$TD/o" 2>/dev/null; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 0 ] || { echo "FAIL r5-f1 stdout-holding grandchild: expected 0 got $rc (124 = harness waited for the grandchild)"; failx; }
[ "$el" -lt 12 ] || { echo "FAIL r5-f1 stdout-holding grandchild: harness took ${el}s with a 3s bound"; failx; }
[ -z "$(lo_pids r6a$$)" ] || { echo "FAIL r5-f1: orphaned descendant survived the harness"; failx; }
lo_kill "r6a$$"
[ "$(wc -l <"$TD/o")" -eq 3 ] || { echo "FAIL r5-f1: verdict lines lost when a grandchild holds stdout"; failx; }
# R5-F1: a hanging tool that also ignores TERM and leaves a stdout-holding child: exit 2 within bound + kill grace + slack, nothing left.
printf '#!/bin/sh\ntrap "" TERM\nsleep 300 &\nsleep 300\n' >"$TD/hd.sh"; chmod +x "$TD/hd.sh"
t0=$(date +%s)
env FC_ORPH=r6b$$ FASTCYCLE_TOOL_TIMEOUT=3 timeout -k 1 40 sh "$H" --tool "$TD/hd.sh" --fixtures "$FX/sound" >/dev/null 2>"$TD/err"; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 2 ] || { echo "FAIL r5-f1 hang: expected harness 2 got $rc"; failx; }
[ "$el" -lt 25 ] || { echo "FAIL r5-f1 hang: harness took ${el}s (3 fixtures x (3 s bound + 2 s kill grace) = 15 s)"; failx; }
[ -z "$(lo_pids r6b$$)" ] || { echo "FAIL r5-f1 hang: orphan survived"; failx; }
lo_kill "r6b$$"
# R5-F9 (C-005): the record name must be on the tool's STDOUT; stderr is not evidence (both tool-run branches).
mkfx se 'rec-1\n'
printf '#!/bin/sh\ncase "$(cat "$1")" in golden-bad) echo "error near rec-1" >&2; exit 1 ;; esac\nexit 0\n' >"$TD/se.sh"; chmod +x "$TD/se.sh"
printf '#!/bin/sh\ncase "$(cat "$1")" in golden-bad) echo "error near rec-1"; exit 1 ;; esac\nexit 0\n' >"$TD/so.sh"; chmod +x "$TD/so.sh"
cp "$TD/se.sh" "$TD/se_nx.sh"; chmod -x "$TD/se_nx.sh"; cp "$TD/so.sh" "$TD/so_nx.sh"; chmod -x "$TD/so_nx.sh"
for tl in so so_nx; do
  timeout -k 1 20 sh "$H" --tool "$TD/$tl.sh" --fixtures "$TD/se" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL r5-f9 control $tl (name on stdout): expected 0 got $rc"; failx; }
done
for tl in se se_nx; do
  timeout -k 1 20 sh "$H" --tool "$TD/$tl.sh" --fixtures "$TD/se" >"$TD/o" 2>/dev/null; rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL r5-f9 $tl (name only on stderr): expected 1 got $rc"; failx; }
  grep -q '"class":"golden-bad".*"ok":false' "$TD/o" || { echo "FAIL r5-f9 $tl: golden-bad line must be ok:false"; failx; }
done
# R5-F6: class dir names outside [A-Za-z0-9._-] are refused (exit 2, nothing emitted); legal names still work and emit valid JSON.
mkcls() { d="$TD/cls$2"; rm -rf "$d"; mkdir -p "$d/golden-good" "$d/golden-bad" "$d/negative-control" "$d/$1"
  printf 'rc=0\n' >"$d/golden-good/input"; printf 'rc=0\n' >"$d/negative-control/input"
  for c in golden-bad "$1"; do printf 'rc=1\nsay=rec-1\n' >"$d/$c/input"; printf 'rec-1\n' >"$d/$c/expected"; done; echo "$d"; }
k=0
for nm in 'golden-bad-a"b' 'golden-bad-a b' 'golden-bad-a\b' 'golden-bad-a$b' "golden-bad-a'b" 'golden-bad-a;b' 'golden-bad-a*b' "golden-bad-a$(printf '\303\251')" "golden-bad-a$(printf '\t')b" "golden-bad-a$(printf '\nb')"; do
  k=$((k + 1)); d=$(mkcls "$nm" $k)
  timeout -k 1 20 sh "$H" --tool "$T" --fixtures "$d" >"$TD/o" 2>"$TD/em"; rc=$?
  [ "$rc" -eq 2 ] && [ ! -s "$TD/o" ] && grep -q "class name" "$TD/em" || { echo "FAIL r5-f6 [$k]: rc=$rc stdout=[$(head -c 80 "$TD/o")] stderr=[$(head -c 120 "$TD/em")]"; failx; }
done
d=$(mkcls 'golden-bad-ok.1_x-Y' ok)
timeout -k 1 20 sh "$H" --tool "$T" --fixtures "$d" >"$TD/o" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ "$(wc -l <"$TD/o")" -eq 4 ] && python3 -c 'import sys,json
for l in sys.stdin: json.loads(l)' <"$TD/o" || { echo "FAIL r5-f6 legal class name: rc=$rc or JSON invalid"; failx; }
# R5-F7: the header states the boundary set on one machine-checkable line equal to the code's set, no stray delimiter list.
bl=$(sed -n 's/^# Boundary set (exact): //p' "$H")
[ -n "$bl" ] || { echo "FAIL r5-f7 header lacks the 'Boundary set (exact):' line"; failx; }
hs=""; for w in $bl; do case $w in SPACE) hs="$hs " ;; TAB) hs="$hs$(printf '\t')" ;; BACKTICK) hs="$hs\`" ;; *) hs="$hs$w" ;; esac; done
[ "$(printf '%s' "$hs" | od -An -c | tr -s ' ')" = "$(printf '%s' "$DELIMS_T" | od -An -c | tr -s ' ')" ] || { echo "FAIL r5-f7 header boundary set [$bl] differs from the code's set"; failx; }
sed -n '1,/^tool=/p' "$H" | grep -q ' \.$' && { echo "FAIL r5-f7 header still has a dangling ' .' delimiter list"; failx; }
# ROUND 6b (sweep survivors, killed by tests): TERM-ignoring orphan after a NORMAL exit needs KILL, not TERM.
printf '#!/bin/sh\ntrap "" TERM\nsleep 60 &\nexec sh "%s" "$1"\n' "$T" >"$TD/gi.sh"; chmod +x "$TD/gi.sh"
env FC_ORPH=r6d$$ FASTCYCLE_TOOL_TIMEOUT=3 timeout -k 1 20 sh "$H" --tool "$TD/gi.sh" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL r6b term-ignoring orphan: expected 0 got $rc"; failx; }
[ -z "$(lo_pids r6d$$)" ] || { echo "FAIL r6b: a TERM-ignoring orphan survived a normal tool exit (group must get KILL)"; failx; }
lo_kill "r6d$$"
# Non-executable tool (run via sh): TERM-ignoring hang still bounded by the kill-after; stderr still discarded.
cp "$TD/hd.sh" "$TD/hd_nx.sh"; chmod -x "$TD/hd_nx.sh"
t0=$(date +%s)
env FC_ORPH=r6d$$ FASTCYCLE_TOOL_TIMEOUT=3 timeout -k 1 40 sh "$H" --tool "$TD/hd_nx.sh" --fixtures "$FX/sound" >/dev/null 2>&1; rc=$?
el=$(( $(date +%s) - t0 ))
[ "$rc" -eq 2 ] && [ "$el" -lt 25 ] || { echo "FAIL r6b non-exec TERM-ignoring hang: rc=$rc ${el}s (want 2 within 25s; 124 = no kill-after)"; failx; }
[ -z "$(lo_pids r6d$$)" ] || { echo "FAIL r6b non-exec hang: orphan survived"; failx; }
lo_kill "r6d$$"
cp "$TD/noisy.sh" "$TD/noisy_nx.sh"; chmod -x "$TD/noisy_nx.sh"
sh "$H" --tool "$TD/noisy_nx.sh" --fixtures "$FX/sound" >/dev/null 2>"$TD/em"
grep -q NOISE-FROM-TOOL "$TD/em" && { echo "FAIL r6b non-exec tool stderr leaked through the harness"; failx; }
# A clean run prints nothing on stderr (the group-kill of an already-empty group must be silent).
sh "$H" --tool "$T" --fixtures "$FX/sound" >/dev/null 2>"$TD/em"
[ ! -s "$TD/em" ] || { echo "FAIL r6b clean run wrote stderr: $(head -c 120 "$TD/em")"; failx; }
# R7-F10: under a UTF-8 locale a tool line with an INVALID multibyte byte must not make the harness's awk write to
# stderr (gawk warns "Invalid multibyte data" unless LC_ALL=C is set on that call); verdict and stderr both pinned.
ul=""
for cand in en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
  [ "$(LC_ALL=$cand locale charmap 2>/dev/null)" = UTF-8 ] && { ul=$cand; break; }
done
if [ -n "$ul" ]; then
  mkfx ub 'rec-1\n'; printf 'rc=0\n' >"$TD/ub/golden-good/input"; printf 'rc=0\n' >"$TD/ub/negative-control/input"
  printf 'rc=1\nsay=bad \303 rec-1\n' >"$TD/ub/golden-bad/input"
  LC_ALL=$ul sh "$H" --tool "$T" --fixtures "$TD/ub" >"$TD/o" 2>"$TD/em"; rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL r7f10 invalid multibyte under $ul: expected 0 got $rc"; failx; }
  [ ! -s "$TD/em" ] || { echo "FAIL r7f10 harness wrote stderr under $ul on an invalid multibyte tool line: $(head -c 160 "$TD/em")"; failx; }
else echo "SKIP r7f10 invalid multibyte: no UTF-8 locale available on this host"; fi
# The tool's stdin is /dev/null, not the harness's: proven under a real pty with job control (`sh -m`), where a bare '&' keeps the tty as stdin.
printf '#!/bin/sh\ncat >/dev/null\nexec sh "%s" "$1"\n' "$T" >"$TD/si.sh"; chmod +x "$TD/si.sh"; cp "$TD/si.sh" "$TD/si_nx.sh"; chmod -x "$TD/si_nx.sh"
pty_run() { # cmd... : run under a pty, print the output then 'exit=<n>'
  python3 - "$@" <<'PYEOF'
import os, pty, select, sys, time
pid, fd = pty.fork()
if pid == 0:
    for kv in os.environ.get("PTY_SET", "").split(";"):
        if "=" in kv: k, v = kv.split("=", 1); os.environ[k] = v
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""; t0 = time.time()
while True:
    r, _, _ = select.select([fd], [], [], 1)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    if time.time() - t0 > 60:
        os.kill(pid, 9); break
_, st = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace")); sys.stdout.write("exit=%d\n" % (os.waitstatus_to_exitcode(st)))
PYEOF
}
for tl in si si_nx; do
  out=$(PTY_SET="FASTCYCLE_TOOL_TIMEOUT=3"; export PTY_SET; pty_run sh -m "$H" --tool "$TD/$tl.sh" --fixtures "$FX/sound" 2>&1) || true
  printf '%s\n' "$out" | grep -q '^exit=0' || { echo "FAIL r6b stdin of $tl inherited from the harness under job control: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"; failx; }
done
# A signal while a tool runs: exit 2, tool group killed, temp dir removed.
mkdir "$TD/tmpd2"
for sg in TERM HUP INT; do
  # `set -m`: a plain `&` child ignores SIGINT from birth and an ignored-on-entry signal cannot be trapped (R7-F6: INT
  # must actually reach the harness's trap, as a terminal Ctrl-C does).
  set -m
  env FC_ORPH=r6b$$ TMPDIR="$TD/tmpd2" FASTCYCLE_TOOL_TIMEOUT=60 sh "$H" --tool "$TD/hd.sh" --fixtures "$FX/sound" >/dev/null 2>&1 &
  hp=$!; set +m
  i=0; while [ -z "$(lo_pids r6b$$)" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(lo_pids r6b$$)" ] || { echo "FAIL r6b signal $sg: tool never started"; failx; }
  kill -s "$sg" "$hp"; wait "$hp"; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL r6b signal $sg: expected harness exit 2 got $rc"; failx; }
  sleep 0.5
  [ -z "$(lo_pids r6b$$)" ] || { echo "FAIL r6b signal $sg: tool group survived the harness"; failx; }
  lo_kill "r6b$$"
  [ -z "$(ls -A "$TD/tmpd2")" ] || { echo "FAIL r6b signal $sg: temp dir leaked: $(ls "$TD/tmpd2")"; failx; }
done
# The refusal message states the exit code it uses.
d=$(mkcls 'golden-bad-a b' msg); sh "$H" --tool "$T" --fixtures "$d" >/dev/null 2>"$TD/em"
grep -q 'class name outside \[A-Za-z0-9._-\] refused (exit 2)' "$TD/em" || { echo "FAIL r5-f6 message: $(head -c 160 "$TD/em")"; failx; }
# R6b (pid-reuse safety): a STALE target pid must never make cleanup KILL AN UNRELATED PROCESS GROUP.
# Inside `unshare -Urpf --mount-proc` an escapee forces pid reuse (ns_last_pid) so an unrelated
# `setsid sleep` takes the dead timeout pid, then TERMs the harness; that sleeper must survive.
if unshare -Urpf --mount-proc sh -c : >/dev/null 2>&1; then
  ok=0; res=""
  # shellcheck disable=SC2034
  for try in 1 2 3; do
    res=$(timeout -k 2 60 unshare -Urpf --mount-proc sh "$here/fixtures/triple_harness/nsdrv_h.sh" "$here" 2>/dev/null)
    [ "$res" = NOREUSE ] || { ok=1; break; }
  done
  if [ "$ok" -eq 0 ]; then echo "FAIL r6b pid reuse: reuse window never reached in 3 tries (test cannot discriminate)"; failx
  elif [ "$res" != REUSED-ALIVE ]; then echo "FAIL r6b pid reuse: harness killed an unrelated group that reused the stale target pid ($res)"; failx; fi
else
  echo "SKIP r6b pid reuse: userns_unavailable (unshare -Urpf --mount-proc cannot run on this host)"
fi
# R6-F1 / R6-F2 / R7 signal windows: a HUP/INT/TERM must exit 2, kill the tool's whole group and leave
# unrelated processes alone in EVERY window: (plain) after the `&` fork and before the shell has recorded
# the child (F2); (inherit) with an inherited stale tpid naming an unrelated group (F1: the `tpid=""`
# initialisation); (postwait) after the child was reaped but before the group kill; (shim) while `timeout`
# has not yet made its own process group. Driver: fixtures/triple_harness/sigwin_check.sh (strace delays a
# syscall in the unit only; a watcher signals at that instant). SKIP names its reason.
res=$(bash "$here/fixtures/triple_harness/sigwin_check.sh" harness "$here")
[ -z "$res" ] || printf '%s\n' "$res"
printf '%s\n' "$res" | grep -q '^FAIL' && failx
# R7b: the pid source of reap_jobs (`jobs`), shimmed, with a LOG-ONLY kill: never a pgid <= 1 (0, 1, -1,
# empty, non-numeric, multi-word, backslash line) for ANY jobs output, `jobs -r` rejected (dash-like) falls
# back to `jobs -p`, a stale done job that only `jobs -p` lists (pid-namespace canary) is never signalled,
# jobs errors stay silent. (tpid is `$!` of a real child: always > 1, guarded by kill_group.)
res=$(bash "$here/fixtures/triple_harness/jobs_shim_check.sh" harness "$here")
[ -z "$res" ] || printf '%s\n' "$res"
printf '%s\n' "$res" | grep -q '^FAIL' && failx
[ "$fail" -eq 0 ] && echo "GREEN: T009" || echo "RED: T009 failing"
exit "$fail"
