#!/usr/bin/env bash
# test_round8.sh — regression tests for the round-7 independent review (Minor findings m1-m4): m1 (a closed pipe or a
# full device on stdout at exit gave rc 120 and Python's own 'Exception ignored while flushing sys.stdout'), m2 (a NUL
# byte in a .gitmodules value: git cuts the value there, the engine used to keep it and crash), m3 (escapes above
# U+FFFF were ambiguous: \uXXXX with 5-6 hex digits), m4 (two reviewer-mutant gaps: the user-backup tag hash, and the
# device/inode comparison in same_dir). Class: integration against the REAL wizard CLI (real closed pipe, real
# /dev/full, real git); blocks marked UNIT-CLASS import the real engine. Sandboxes are mktemp -d; deletes use
# safe_rm_rf; HOME is never reassigned.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'chmod -R u+w "$SB" 2>/dev/null; cleanup_sandbox' EXIT
C="$DEC_CLI"
ENGINE_DIR="$(dirname "$C")"
newuser() { export CONSTITUTION_DECISIONS_USER_FILE="$SB/u$1/decisions.yml"; }
export CONSTITUTION_DECISIONS_TEST=1

echo "== m1: a closed pipe or a full device on stdout never gives rc 120 or 'Exception ignored' =="
newuser 1; P1="$(new_project m1)"
cat >"$SB/closedpipe.py" <<'PY'
import os, subprocess, sys
r, w = os.pipe(); os.close(r)           # the reader is gone: a REAL broken pipe
p = subprocess.Popen(sys.argv[2:], stdout=w, stderr=subprocess.PIPE)
os.close(w)
err = p.communicate()[1]
sys.stdout.write("%d\n" % p.returncode); sys.stdout.flush()
sys.stderr.buffer.write(err)
PY
python3 -I "$SB/closedpipe.py" x "$C" --project-root "$P1" --show >"$SB/cp.out" 2>"$SB/cp.err"
rc="$(head -n1 "$SB/cp.out")"
check "closed pipe, --show: rc is 1 (not 120)" test "$rc" = 1
check "…and stderr has no interpreter 'Exception ignored' text" bash -c "! grep -aq 'Exception ignored' '$SB/cp.err'"
check "…and stderr has no traceback" bash -c "! grep -aq Traceback '$SB/cp.err'"
check "…and the one line is the engine's own" grep -aq 'constitution_decisions: internal error (BrokenPipeError)' "$SB/cp.err"
"$C" --project-root "$P1" --show >/dev/full 2>"$SB/full.err"; rc=$?
check "/dev/full, --show: rc 3 (not 120)" test "$rc" = 3
check "…no interpreter text, no traceback" bash -c "! grep -aq -e 'Exception ignored' -e Traceback '$SB/full.err'"
check "…the engine's own line names the cause" grep -aq 'constitution_decisions: blocked: No space left on device' "$SB/full.err"
newuser 2; P2="$(new_project m1b)"
"$C" --project-root "$P2" --non-interactive --set calibration.floor=0.95 >/dev/full 2>"$SB/full2.err"; rc=$?
check "/dev/full after a successful --set: rc is not 120, no interpreter text" bash -c "[ $rc != 120 ] && ! grep -aq 'Exception ignored' '$SB/full2.err'"
"$C" --project-root "$P2" --show >"$SB/ok.out" 2>"$SB/ok.err"; rc=$?
check "control: a normal --show still exits 0 with output and quiet stderr" bash -c "[ $rc = 0 ] && [ -s '$SB/ok.out' ] && [ ! -s '$SB/ok.err' ]"

echo "== m2: a NUL byte in a .gitmodules value is cut at the NUL like git (no crash, no empty .constitution/) =="
cat >"$SB/nuldiff.py" <<'PY'
import os, subprocess, sys, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1]); import decisions_engine as d
Q = b'[submodule "a"]\n'
cases = {
 "nul_mid": Q + b'\tpath = x\0z\n\turl = u\n',
 "nul_lead": Q + b'\tpath = \0z\n\tpath = sub/a\n',
 "nul_quoted": Q + b'\tpath = "x\0z"\n',
 "nul_before_comment": Q + b'\tpath = sub/a\0 ; c\n',
 "nul_two": Q + b'\tpath = a\0b\0c\n',
 "control_plain": Q + b'\tpath = sub/a\n',
}
bad = []
for name, raw in cases.items():
    fd, p = tempfile.mkstemp(dir=sys.argv[2]); os.write(fd, raw); os.close(fd)
    r = subprocess.run(["git", "config", "-f", p, "-z", "--get-regexp", r"^submodule\..*\.path$"], capture_output=True)
    os.unlink(p)
    if r.returncode not in (0, 1):
        print("git refuses", name); continue
    g = []
    for rec in r.stdout.split(b"\0"):
        if not rec: continue
        v = rec.split(b"\n", 1)[1] if b"\n" in rec else b""
        if v: g.append(os.fsdecode(v))
    e = d.gitmodules_paths(raw.decode("utf-8", "surrogateescape"))
    if g != e: bad.append((name, g, e))
    if any("\0" in x for x in e): bad.append((name, "NUL kept", e))
print("DIFF-BAD" if bad else "DIFF-OK", bad)
PY
python3 -I "$SB/nuldiff.py" "$ENGINE_DIR" "$SB" >"$SB/nuldiff.out" 2>&1
check "UNIT-CLASS: gitmodules_paths equals REAL git on NUL-byte values (differential, control case included)" grep -q '^DIFF-OK' "$SB/nuldiff.out"
sed 's/^/      | /' "$SB/nuldiff.out" | head -5
newuser 3; P3="$(new_project m2)"
printf '[submodule "a"]\n\tpath = x\0z\n\turl = u\n' >"$P3/.gitmodules"
"$C" --project-root "$P3" --non-interactive --set calibration.floor=0.95 >"$SB/n.out" 2>"$SB/n.err"; rc=$?
check "CLI: a NUL in .gitmodules does not crash the run (rc 0)" test "$rc" = 0
check "…no 'internal error' line" bash -c "! grep -aq 'internal error' '$SB/n.err'"
check "…the override was written (.constitution/ is not empty)" bash -c "[ -n \"\$(ls -A '$P3/.constitution')\" ]"
newuser 4; P4="$(new_project m2b)"
printf '[submodule "a"]\n\tpath = constitution\0z\n' >"$P4/.gitmodules"
"$C" --project-root "$P4" --non-interactive --set calibration.floor=0.95 >"$SB/n2.out" 2>"$SB/n2.err"; rc=$?
check "a NUL-cut path naming a real directory: rc 0, or a clean refusal (rc 3/4) - never rc 1" bash -c "[ $rc = 0 ] || [ $rc = 3 ] || [ $rc = 4 ]"
check "…and no empty .constitution/ is left behind" bash -c "[ ! -d '$P4/.constitution' ] || [ -n \"\$(ls -A '$P4/.constitution')\" ]"

echo "== m3: escapes above U+FFFF are fixed-width (no hex read as part of an escape) (\\uXXXX = 4 hex digits, \\UXXXXXXXX = 8) =="
cat >"$SB/esc.py" <<'PY'
import re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1]); import decisions_engine as d
RX = re.compile(r"\\U([0-9a-f]{8})|\\u([0-9a-f]{4})")
def decode(s): return RX.sub(lambda m: chr(int(m.group(1) or m.group(2), 16)), s)
errs = []
for ch in ("‮", "\U000e0041", "\U000e007f", "\U0010ffff", "\U000f0000", "\U0001d173", "\x07", "\x9b"):
    for tail in ("", "1", "ab", "0041", "ffff"):
        src = "x" + ch + tail + "y"
        for nm, fn in (("safe_text", d.safe_text), ("clean_line", d._clean_line)):
            out = fn(src)
            if any(d.is_unsafe_char(c) for c in out): errs.append((nm, "unsafe left", ascii(src)))
            if decode(out) != src: errs.append((nm, "ambiguous", ascii(src), out))
if d.safe_text("\U000e0041") != "\\U000e0041": errs.append(("exact", d.safe_text("\U000e0041")))
if d.safe_text("‮") != "\\u202e": errs.append(("exact4", d.safe_text("‮")))
print("ESC-BAD" if errs else "ESC-OK", errs[:3])
PY
python3 -I "$SB/esc.py" "$ENGINE_DIR" >"$SB/esc.out" 2>&1
check "UNIT-CLASS: safe_text and the emitter line cleaner round-trip every unsafe char (incl. > U+FFFF) followed by hex digits" grep -q '^ESC-OK' "$SB/esc.out"
sed 's/^/      | /' "$SB/esc.out" | head -5

echo "== m4 (R09): two user files whose names sanitise to the same tag get different tags and separate backups =="
python3 -I -c "
import sys; sys.dont_write_bytecode = True; sys.path.insert(0,'$ENGINE_DIR'); import decisions_engine as d
a, b = d.user_backup_tag('/x/a.yml'), d.user_backup_tag('/x/a_yml')
print('TAG-OK' if a != b else 'TAG-BAD', a, b)" >"$SB/tag.out" 2>&1
check "UNIT-CLASS: 'a.yml' and 'a_yml' (same sanitised stem) have different tags" grep -q '^TAG-OK' "$SB/tag.out"
newuser 5; P5="$(new_project m4a)"; U5="$SB/u5"; mkdir -p "$U5"
for f in a.yml a_yml; do printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.91\n' >"$U5/$f"; done
for n in 1 2; do
  for f in a.yml a_yml; do
    CONSTITUTION_DECISIONS_USER_FILE="$U5/$f" CONSTITUTION_DECISIONS_BACKUP_KEEP=1 "$C" --project-root "$P5" --scope user --non-interactive --set calibration.floor=0.9$((n+4)) >/dev/null 2>&1
    sleep 1.1
  done
done
na="$(ls "$U5/.decisions-backup" | grep -c -- '@a_yml_[0-9a-f]\{8\}\.yml$' )"
tags="$(ls "$U5/.decisions-backup" | sed 's/.*@//' | sort -u | wc -l)"
check "CLI: with keep=1 each of the two user files keeps its own newest backup (2 distinct tags)" test "$tags" = 2
check "…and the count of backups in the directory is 2 (one per file, not pruned across files)" test "$(ls "$U5/.decisions-backup" | wc -l)" = 2

echo "== m4 (R12): a backup base replaced by ANOTHER real directory after it was opened is refused =="
newuser 6; P6="$(new_project m4b)"; U6="$SB/u6"; mkdir -p "$U6/.decisions-backup"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.91\n' >"$CONSTITUTION_DECISIONS_USER_FILE"
CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY=2 "$C" --project-root "$P6" --scope user --non-interactive --set calibration.floor=0.95 >"$SB/r12.out" 2>"$SB/r12.err" &
bpid=$!
sleep 0.8
mv "$U6/.decisions-backup" "$U6/.decisions-backup.real"; mkdir -m 0700 "$U6/.decisions-backup"
wait "$bpid"; brc=$?
check "swapped for another real directory: refused (rc 3)" test "$brc" -eq 3
check "…nothing was written into the replacement directory" test -z "$(ls -A "$U6/.decisions-backup")"

echo "== B2 (round-8 review): EVERY return path of run_cli flushes stdout (error paths too), with real /dev/full and a real closed pipe =="
# drive.py: runs the REAL CLI with stdout = /dev/full | a closed pipe | a file; after <after> seconds it either
# chmods the given paths read-only (an OSError in the write path) or sends a REAL SIGINT (SIGINT reset to default in
# the child, because a background job of a non-interactive bash ignores it). Prints the child's rc on its stdout.
cat >"$SB/drive.py" <<'PY'
import os, signal, subprocess, sys, time
mode, after, action = sys.argv[1], float(sys.argv[2]), sys.argv[3]
cmd = sys.argv[sys.argv.index("--") + 1:]
r = None
if mode == "full":
    out = os.open("/dev/full", os.O_WRONLY)
elif mode == "pipe":
    r, out = os.pipe(); os.close(r)            # the reader is gone: a REAL broken pipe
else:
    out = os.open(mode, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
p = subprocess.Popen(cmd, stdout=out, stderr=subprocess.PIPE,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
os.close(out)
if action != "none":
    time.sleep(after)
    if action == "sigint":
        p.send_signal(signal.SIGINT)
    else:
        for path in action.split(":"):
            os.chmod(path, 0o555)
err = p.communicate()[1]
sys.stdout.write("%d\n" % p.returncode); sys.stdout.flush()
sys.stderr.buffer.write(err)
PY
# prep: a project with an existing override, so the next --set takes a backup and prints 'backup: ...' (buffered)
prep() { local p; p="$(new_project "b2_$1")"
  "$C" --project-root "$p" --non-interactive --set calibration.floor=0.91 >/dev/null 2>&1; printf '%s' "$p"; }
drive() { # $1 tag $2 stdout-mode $3 project $4 action; extra env via the caller
  python3 -I "$SB/drive.py" "$2" 1 "$4" -- "$C" --project-root "$3" --non-interactive --set calibration.floor=0.95 \
    >"$SB/$1.rc" 2>"$SB/$1.err"
  head -n1 "$SB/$1.rc"; }
no_interp() { ! grep -aq -e 'Exception ignored' -e Traceback "$1"; }
export CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2
n=10
for mode in full pipe file; do
  n=$((n+1)); newuser $n; P="$(prep $n)"; tgt="$mode"; [ "$mode" = file ] && tgt="$SB/b2_out_$n"
  rc="$(drive rx_$mode "$tgt" "$P" "$P:$P/.constitution")"; chmod 755 "$P" "$P/.constitution"
  check "report_exception path, stdout=$mode: rc 3 (the original outcome; not 120)" test "$rc" = 3
  check "…no 'Exception ignored' / traceback on stderr" no_interp "$SB/rx_$mode.err"
  check "…the engine's own blocked line is there" grep -aq 'constitution_decisions: blocked: writing .constitution/decisions.intent failed' "$SB/rx_$mode.err"
  [ "$mode" = file ] && check "…control (stdout=file): the buffered 'backup:' line reached stdout (output WAS buffered)" grep -q '^backup: ' "$tgt"
  # MINOR-2: the intent write itself failed, so nothing was recorded: the message must say so
  check "MINOR-2, stdout=$mode: the message does not claim decisions.intent records the change" bash -c "! grep -aq 'records the unfinished change' '$SB/rx_$mode.err'"
  check "…it says this run changed no project file and recorded no decisions.intent" grep -aq 'this run changed no project file and recorded no .constitution/decisions.intent' "$SB/rx_$mode.err"
  check "…it says the backup this run took is kept" grep -aq 'the backup this run took is kept' "$SB/rx_$mode.err"
  check "…and indeed no decisions.intent exists" test ! -e "$P/.constitution/decisions.intent"
done
# MINOR-2 control: a failure AFTER the intent was written keeps the 'records the unfinished change' message (true there)
n=$((n+1)); newuser $n; P="$(prep $n)"
rc="$(drive rx_late "$SB/b2_late_out" "$P" "$P")"; chmod 755 "$P"
check "MINOR-2 control (project root read-only: a doc write fails after the intent): rc 3" test "$rc" = 3
check "…the message says decisions.intent records the unfinished change" grep -aq 'decisions.intent records the unfinished change' "$SB/rx_late.err"
check "…and the intent file really exists" test -e "$P/.constitution/decisions.intent"
unset CONSTITUTION_DECISIONS_TEST_WRITE_DELAY
for mode in full pipe file; do
  n=$((n+1)); newuser $n; P="$(prep $n)"; tgt="$mode"; [ "$mode" = file ] && tgt="$SB/b2_ri_$n"
  rc="$(CONSTITUTION_DECISIONS_TEST_LATE_FAULT=ValueError drive ri_$mode "$tgt" "$P" none)"
  check "report_internal path (late ValueError after output), stdout=$mode: rc 1 (not 120)" test "$rc" = 1
  check "…no 'Exception ignored' / traceback" no_interp "$SB/ri_$mode.err"
  check "…the engine's own internal-error line" grep -aq 'constitution_decisions: internal error (ValueError)' "$SB/ri_$mode.err"
  [ "$mode" = file ] && check "…control (stdout=file): 'written:' lines reached stdout (output WAS buffered)" grep -q '^written: ' "$tgt"
done
export CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2
for mode in full pipe file; do
  n=$((n+1)); newuser $n; P="$(prep $n)"; tgt="$mode"; [ "$mode" = file ] && tgt="$SB/b2_ki_$n"
  rc="$(drive ki_$mode "$tgt" "$P" sigint)"
  check "KeyboardInterrupt path (REAL SIGINT after 'backup:' was buffered), stdout=$mode: rc 130 (not 120)" test "$rc" = 130
  check "…no 'Exception ignored' / traceback" no_interp "$SB/ki_$mode.err"
  [ "$mode" = file ] && check "…control (stdout=file): the buffered 'backup:' line reached stdout" grep -q '^backup: ' "$tgt"
done
unset CONSTITUTION_DECISIONS_TEST_WRITE_DELAY
newuser 30
# the wrapper answers --help itself, so the engine's argparse SystemExit path is driven on the engine directly
python3 -I "$ENGINE_DIR/decisions_engine.py" --help >/dev/full 2>"$SB/help.err"; rc=$?
check "SystemExit path (engine argparse --help to /dev/full): rc 3, not 120" test "$rc" = 3
check "…no interpreter text, the engine's own blocked line" bash -c "! grep -aq -e 'Exception ignored' -e Traceback '$SB/help.err' && grep -aq 'blocked: No space left on device' '$SB/help.err'"
python3 -I "$SB/drive.py" pipe 0 none -- python3 -I "$ENGINE_DIR/decisions_engine.py" --help >"$SB/helpp.rc" 2>"$SB/helpp.err"
check "SystemExit path, closed pipe: rc 1 with the engine's own line, no interpreter text" bash -c "[ \"\$(head -n1 '$SB/helpp.rc')\" = 1 ] && ! grep -aq 'Exception ignored' '$SB/helpp.err' && grep -aq 'internal error (BrokenPipeError)' '$SB/helpp.err'"
python3 -I "$ENGINE_DIR/decisions_engine.py" --help >"$SB/help.out" 2>&1; rc=$?
check "control: engine --help to a file exits 0 with the usage text" bash -c "[ $rc = 0 ] && grep -q usage '$SB/help.out'"

echo "== MINOR-1: the escape form's honest scope (a literal backslash is NOT escaped; documents must not be altered) =="
python3 -I - "$ENGINE_DIR" "$DEC_REPO" >"$SB/bs.out" 2>&1 <<'PY'
import json, os, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d   # UNIT-CLASS
errs = []
# documented JSON output (--show --json) must stay valid JSON with backslashes in values: the block emitter may not
# escape a backslash
import io
class Cap(io.StringIO): encoding = "utf-8"
so = sys.stdout; sys.stdout = Cap()
try:
    d.emit_block(json.dumps({"p": "a\\b", "q": "‮"}))
    v = sys.stdout.getvalue()
finally:
    sys.stdout = so
try:
    if json.loads(v) != {"p": "a\\b", "q": "‮"}: errs.append("json changed: %r" % v)
except ValueError:
    errs.append("json broken: %r" % v)
# the docstring states the limit instead of claiming a reversible encoding
doc = (d._uesc.__doc__ or "") + (d.safe_text.__doc__ or "")
if "literal backslash" not in doc: errs.append("docstring does not state the literal-backslash limit")
plan = open(os.path.join(sys.argv[2], "docs/design/decisions_wizard_plan.md"), encoding="utf-8").read()
if "literal backslash" not in plan: errs.append("plan does not state the literal-backslash limit")
print("BS-BAD" if errs else "BS-OK", errs)
PY
check "UNIT-CLASS: JSON documents keep their backslashes, and the docs state that a literal backslash is not escaped" grep -q '^BS-OK' "$SB/bs.out"
sed 's/^/      | /' "$SB/bs.out" | head -3

finish test_round8
