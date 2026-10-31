#!/usr/bin/env bash
# test_round7.sh — regression tests for the round-6 independent review (LAST round, 7): I-1 (invalid UTF-8 at the TTY
# prompt, and every other exception type: a catch-all and an excepthook, never a traceback or an absolute path),
# M-1 (.gitmodules grammar vs REAL git, a permanent differential), M-2 (escape by Unicode category), M-3 (user
# backups namespaced by source file), M-4 (R13 write-time foreign re-check, R21 key-shaped path hiding), M-5 (AST
# bypass scan widened; argparse help/usage/errors through the emitter), M-6 (backup directories opened with
# O_NOFOLLOW and used by descriptor). Class: integration against REAL git and the REAL wizard CLI through a REAL
# pseudo-terminal; blocks marked UNIT-CLASS import the real engine and, where stated, inject a fault by patching one
# engine function (gate-logic style; never cited as live proof). Sandboxes are mktemp -d; deletes use safe_rm_rf;
# HOME is never reassigned.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'chmod -R u+w "$SB" 2>/dev/null; cleanup_sandbox' EXIT
C="$DEC_CLI"
ENGINE="$(dirname "$C")/decisions_engine.py"
ENGINE_DIR="$(dirname "$C")"
newuser() { export CONSTITUTION_DECISIONS_USER_FILE="$SB/u$1/decisions.yml"; }
pyc() { python3 -I -c "$@"; }
export CONSTITUTION_DECISIONS_TEST=1

echo "== I-1: invalid UTF-8 typed at the TTY prompt never produces a traceback =="
cat >"$SB/ttyraw.py" <<'PY'
import os, pty, sys, time, select
cli, proj, hexans, out = sys.argv[1], sys.argv[2], sys.argv[3].split("|"), sys.argv[4]
answers = [bytes.fromhex(h) for h in hexans]
pid, fd = pty.fork()
if pid == 0:
    os.execv(cli, [cli, "--project-root", proj])
buf = b""; i = 0; last = 0; deadline = time.time() + 30
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    pending = buf[last:]
    if i < len(answers) and pending.endswith(b": "):
        os.write(fd, answers[i] + b"\n"); i += 1; last = len(buf)
import signal
if time.time() >= deadline:
    os.kill(pid, signal.SIGKILL)
_, st = os.waitpid(pid, 0)
open(out, "wb").write(buf)
sys.exit(os.waitstatus_to_exitcode(st))
PY
newuser 1; P1="$(new_project t1)"
BAD='fffe1b5b33316d7a7a'   # \xff\xfe ESC[31mzz
python3 -I "$SB/ttyraw.py" "$C" "$P1" "$BAD|$BAD|$BAD" "$SB/tty1.out"; rc=$?
check "three invalid-UTF-8 answers end in a refusal (rc 4), not a crash" test "$rc" = 4
check "…no traceback, no Python frame, no absolute repo path" bash -c "! grep -aqE 'Traceback|File \"|UnicodeDecodeError|$DEC_REPO' '$SB/tty1.out'"
check "…the refusal is reported in the wizard's own words" grep -aq 'too many invalid answers' "$SB/tty1.out"
check "…each bad answer is refused as not valid UTF-8 text" bash -c "[ \"\$(grep -ac 'not valid UTF-8 text' '$SB/tty1.out')\" -ge 3 ]"
check "…the raw ESC byte of the answer is not echoed raw" bash -c "python3 -I -c \"import sys; b=open('$SB/tty1.out','rb').read(); i=b.find(b'refused'); sys.exit(0 if i>=0 and b'\x1b[31mzz' not in b else 1)\""
# a bad answer followed by a valid one is re-asked and the run carries on (class: undecodable = invalid, not fatal)
n_prompts=$(pyc "
import sys; sys.dont_write_bytecode = True; sys.path.insert(0,'$ENGINE_DIR'); import decisions_engine as d
print(sum(1 for k in d.CATALOGUE if 'locked' not in d.CATALOGUE[k][2]))")
newuser 2; P2="$(new_project t2)"
ans="$BAD|$(printf 'shadow' | xxd -p)"
for _i in $(seq 1 $((n_prompts-1))); do ans="$ans|"; done
ans="$ans|$(printf 'declined' | xxd -p)||||$(printf 'y' | xxd -p)"
python3 -I "$SB/ttyraw.py" "$C" "$P2" "$ans" "$SB/tty2.out"; rc=$?
check "a bad answer then a valid one: the run completes (rc 0)" test "$rc" = 0
check "…and no traceback" bash -c "! grep -aqE 'Traceback|UnicodeDecodeError' '$SB/tty2.out'"
# the confirmation prompt gets an undecodable answer: treated as 'no', nothing written
newuser 3; P3="$(new_project t3)"
ans="$(printf 'shadow' | xxd -p)"
for _i in $(seq 1 $((n_prompts-1))); do ans="$ans|"; done
ans="$ans|||||$BAD"
python3 -I "$SB/ttyraw.py" "$C" "$P3" "$ans" "$SB/tty3.out"; rc=$?
check "an undecodable confirmation is a 'no' (rc 0, nothing written)" bash -c "[ '$rc' = 0 ] && [ ! -e '$P3/.constitution/decisions.yml' ]"
check "…no traceback" bash -c "! grep -aqE 'Traceback|UnicodeDecodeError' '$SB/tty3.out'"

echo "== I-1: every exception type reachable ends in ONE clean line, rc 1 (catch-all) =="
pyc '
import sys, io, os
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
errs = []
class Cap(io.StringIO):
    encoding = "utf-8"
def run(exc, argv):
    out, err = Cap(), Cap()
    so, se = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = out, err
    orig = E.State
    class Boom:
        def __init__(self, *a, **k): raise exc
    E.State = Boom
    try:
        rc = E.run_cli(argv)
    except BaseException as x:  # a leak is the failure
        rc = "RAISED %s" % type(x).__name__
    finally:
        E.State = orig
        sys.stdout, sys.stderr = so, se
    return rc, err.getvalue(), out.getvalue()
proj = sys.argv[2]
cases = [UnicodeDecodeError("utf-8", b"\xff", 0, 1, "bad"), UnicodeEncodeError("utf-8", "x", 0, 1, "bad"),
         UnicodeError("u"), RecursionError("deep"), MemoryError(), OverflowError("big"), ValueError("v"),
         KeyError("k"), RuntimeError("r"), AssertionError("a"), ZeroDivisionError("z"), TypeError("t"),
         AttributeError("a"), ImportError("i"), EOFError("e"), BrokenPipeError(32, "Broken pipe"),
         Exception("plain")]
for exc in cases:
    rc, err, out = run(exc, ["--project-root", proj, "--show"])
    want = "constitution_decisions: internal error (%s)\n" % type(exc).__name__
    if rc != 1: errs.append("%s: rc=%r" % (type(exc).__name__, rc))
    if err != want and not isinstance(exc, BrokenPipeError): errs.append("%s: stderr=%r" % (type(exc).__name__, err[:120]))
    if "Traceback" in err or "/home" in err or "File " in err: errs.append("%s: leak %r" % (type(exc).__name__, err[:120]))
# KeyboardInterrupt keeps its own code
rc, err, out = run(KeyboardInterrupt(), ["--project-root", proj, "--show"])
if rc != 130: errs.append("KeyboardInterrupt rc=%r" % (rc,))
# the engine own errors still map to their codes (the catch-all does not swallow them)
rc, err, out = run(E.Refused("nope"), ["--project-root", proj, "--show"])
if rc != 4 or "refused: nope" not in err: errs.append("Refused mapping broken: %r %r" % (rc, err))
rc, err, out = run(E.Usage("u"), ["--project-root", proj, "--show"])
if rc != 2: errs.append("Usage mapping broken: %r" % (rc,))
# a hostile message in the exception never reaches the output (only the type name is printed)
class Evil(Exception): pass
rc, err, out = run(Evil("\x1b[2Jsecret-sk-aaaaaaaaaaaaaaaaaaaa /home/x"), ["--project-root", proj, "--show"])
if "\x1b" in err or "sk-aaaa" in err or "/home" in err or "Evil" not in err: errs.append("message leaked: %r" % err)
# SystemExit from argparse passes through (help/version) untouched
out, err = Cap(), Cap(); so, se = sys.stdout, sys.stderr; sys.stdout, sys.stderr = out, err
try:
    E.run_cli(["--help"]); rc = "returned"
except SystemExit as x:
    rc = x.code
finally:
    sys.stdout, sys.stderr = so, se
if rc not in (0, "returned"): errs.append("--help rc=%r" % (rc,))
for e in errs: print("FAIL", e)
sys.exit(1 if errs else 0)
' "$ENGINE_DIR" "$(new_project fault)" >"$SB/fault.out" 2>&1
check "UNIT-CLASS: 17 injected exception types + KeyboardInterrupt/Refused/Usage/hostile message/--help" test $? -eq 0
sed 's/^/      | /' "$SB/fault.out" | head -12

# the real CLI process with the fault seam (test-only): no traceback, no absolute path, rc 1
for ex in ValueError KeyError UnicodeDecodeError RecursionError MemoryError OverflowError BrokenPipeError; do
  CONSTITUTION_DECISIONS_TEST_FAULT=$ex "$C" --project-root "$(new_project f_$ex)" --show >"$SB/f.out" 2>"$SB/f.err"; rc=$?
  check "CLI fault $ex: rc 1" test "$rc" = 1
  check "…stderr is exactly the internal-error line" bash -c "[ \"\$(cat '$SB/f.err')\" = 'constitution_decisions: internal error ($ex)' ]"
done

# excepthook: an exception that escapes everything is reported through the same emitter
pyc '
import sys, io
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
class Cap(io.StringIO): encoding = "utf-8"
err = Cap(); se = sys.stderr; sys.stderr = err
try:
    E.install_excepthook()
    hook = sys.excepthook
    try:
        raise ValueError("/home/secret/path \x1b[31m")
    except ValueError:
        hook(*sys.exc_info())
finally:
    sys.stderr = se
    sys.excepthook = sys.__excepthook__
v = err.getvalue()
ok = v == "constitution_decisions: internal error (ValueError)\n"
print("hook output:", repr(v[:100]))
sys.exit(0 if ok else 1)
' "$ENGINE_DIR" >"$SB/hook.out" 2>&1
check "UNIT-CLASS: sys.excepthook prints one clean line, never the message or a path" test $? -eq 0
# the script entry installs it: a real uncaught exception outside run_cli (injected in the wrapper) is clean
check "static: the entry point installs the excepthook and calls run_cli (AST)" python3 -I - "$ENGINE" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
names = {n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
assert {"run_cli", "install_excepthook"} <= names, names
rc = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name == "run_cli"][0]
# a catch-all handler: except Exception (or bare BaseException subclass handler) inside run_cli
hs = [h for n in ast.walk(rc) if isinstance(n, ast.Try) for h in n.handlers]
assert any(isinstance(h.type, ast.Name) and h.type.id == "Exception" for h in hs), "no except Exception in run_cli"
assert any(isinstance(h.type, ast.Name) and h.type.id == "KeyboardInterrupt" for h in hs), "no KeyboardInterrupt handler"
# the __main__ guard calls install_excepthook before run_cli
main_if = [n for n in tree.body if isinstance(n, ast.If) and "__name__" in ast.dump(n.test)][0]
calls = [c.func.id for c in ast.walk(main_if) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)]
assert "install_excepthook" in calls and "run_cli" in calls, calls
assert calls.index("install_excepthook") < calls.index("run_cli"), calls
PY

echo "== I-1: the TTY is opened tolerant of bad bytes (surrogateescape), statically =="
check "static: /dev/tty is opened with errors=surrogateescape" python3 -I - "$ENGINE" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
found = 0
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "open" and n.args \
            and isinstance(n.args[0], ast.Constant) and n.args[0].value == "/dev/tty" and len(n.args) > 1 \
            and isinstance(n.args[1], ast.Constant) and n.args[1].value == "r":
        kw = {k.arg: getattr(k.value, "value", None) for k in n.keywords}
        assert kw.get("errors") == "surrogateescape", kw
        found += 1
assert found == 1, found
PY

echo "== M-1: gitmodules_paths vs REAL git: a permanent differential over a corpus, with control needles =="
cat >"$SB/gmdiff.py" <<'PY'
import os, subprocess, sys, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1]); import decisions_engine as d
# name: (bytes, superset_ok). superset_ok = the engine may report MORE than git (it refuses more, never fewer).
Q = b'[submodule "a"]\n'
cases = {
 "plain": (Q + b'\tpath = sub/a\n\turl = x\n', False),
 "bom": (b'\xef\xbb\xbf' + Q + b'\tpath = sub/a\n', False),
 "bom_crlf": (b'\xef\xbb\xbf[submodule "a"]\r\n\tpath = sub/a\r\n', False),
 "legacy_dot": (b'[submodule.a]\n\tpath = sub/a\n', False),
 "legacy_dot_upper": (b'[submodule.A.b]\n\tpath = sub/a\n', False),
 "legacy_dot_multi": (b'[Submodule.X]\n\tpath = sub/x\n[submodule.y]\n\tpath = sub/y\n', False),
 "upper": (b'[SubModule "a"]\n\tPATH = sub/a\n', False),
 "quoted_val": (Q + b'\tpath = "sub/a" ; c\n', False),
 "esc_val": (Q + b'\tpath = sub\\\\a\n', False),
 "esc_quote": (Q + b'\tpath = a\\"b\n', False),
 "cont": (Q + b'\tpath = sub/\\\n a\n', False),
 "cont_crlf": (Q + b'\tpath = sub/\\\r\n a\r\n', False),
 "crlf": (b'[submodule "a"]\r\n\tpath = sub/a\r\n', False),
 "crlf_comment": (b'[submodule "a"] # c\r\n\tpath = sub/a ; x\r\n', False),
 "multi": (Q + b'\tpath = sub/a\n\tpath = sub/b\n', False),
 "multi_sections": (Q + b'\tpath = sub/a\n[submodule "b"]\n\tpath = sub/b\n', False),
 "keyline": (b'[submodule "a"] path = sub/a\n', False),
 "keyline_nospace": (b'[submodule "a"]path=sub/a\n', False),
 "subsec_esc": (b'[submodule "a\\"]x"]\n\tpath = sub/a\n', False),
 "subsec_bracket": (b'[submodule "a]b"]\n\tpath = sub/a\n', False),
 "nosubsec": (b'[submodule]\n\tpath = sub/a\n', True),
 "include": (b'[include]\n\tpath = other\n[submodule "a"]\n\tpath=sub/a\n', False),
 "other_section_between": (Q + b'[core]\n\tpath = no\n\tfoo = 1\n', False),
 "ws_inner": (Q + b'\tpath =  sub a  \n', False),
 "hash_in_q": (Q + b'\tpath = "s#b"\n', False),
 "semi_in_q": (Q + b'\tpath = "s;b"\n', False),
 "space_header": (b'[submodule  "a"  ]\n\tpath = sub/a\n', True),
 "digitkey": (Q + b'\t1path = sub/z\n\tpath = sub/a\n', True),
 "nonutf8": (Q + b'\tpath = sub/\xff\n', False),
 "tab_in_q": (Q + b'\tpath = "a\\tb"\n', False),
 "nl_esc": (Q + b'\tpath = a\\nb\n', False),
 "bad_esc": (Q + b'\tpath = a\\qb\n', True),
 "eof_noeol": (Q + b'\tpath = sub/a', False),
 "eof_backslash": (Q + b'\tpath = sub/a\\', False),
 "dotsec": (b'[submodule.A.b]\n\tpath = sub/a\n', False),
 "empty_value": (Q + b'\tpath =\n\tpath = sub/a\n', False),
 "no_equals": (Q + b'\tpath\n\tpath = sub/a\n', False),
 "quoted_empty": (Q + b'\tpath = ""\n\tpath = sub/a\n', False),
 "comment_lines": (b'# top\n; also\n' + Q + b'# c\n\tpath = sub/a\n; d\n', False),
 "leading_ws": (b'   \t[submodule "a"]\n   \tpath = sub/a\n', False),
 "unterminated_hdr": (b'[submodule "a"\n\tpath = sub/a\n', True),
 "path_before_section": (b'path = x\n' + Q + b'\tpath = sub/a\n', True),
 "dup_names": (Q + b'\tpath = sub/a\n[submodule "a"]\n\tpath = sub/b\n', False),
 "unicode": (Q + 'path = sub/é中\n'.encode().join([b'\t', b'']), False),
 "long": (Q + b'\tpath = ' + b'x' * 5000 + b'\n', False),
 "mixed_key_case": (Q + b'\tPaTh = sub/a\n', False),
 "dash_key": (Q + b'\tpath-x = sub/z\n\tpath = sub/a\n', False),
}
def git_paths(raw):
    fd, p = tempfile.mkstemp(dir=sys.argv[2]); os.write(fd, raw); os.close(fd)
    r = subprocess.run(["git", "config", "-f", p, "-z", "--get-regexp", r"^submodule\..*\.path$"], capture_output=True)
    os.unlink(p)
    if r.returncode not in (0, 1):
        return "ERR"
    out = []
    for rec in r.stdout.split(b"\0"):
        if not rec:
            continue
        v = rec.split(b"\n", 1)[1] if b"\n" in rec else b""
        if v:  # an empty path names the project root itself; the engine drops it by design
            out.append(os.fsdecode(v))
    return out
def check(engine_fn):
    bad = []
    for name, (raw, sup) in cases.items():
        g = git_paths(raw)
        e = engine_fn(raw.decode("utf-8", "surrogateescape"))
        if g == "ERR":
            continue  # git itself refuses the file; the only demand is that the engine does not crash (it returned)
        if sup:
            if not set(g) <= set(e): bad.append((name, g, e))
        elif g != e:
            bad.append((name, g, e))
    return bad
bad = check(d.gitmodules_paths)
# CONTROL NEEDLES (section 11.4.273): the harness can see a difference, and sees agreement on a known-present path
assert git_paths(cases["plain"][0]) == ["sub/a"], "needle: git does not report the plain path"
assert d.gitmodules_paths(cases["plain"][0].decode()) == ["sub/a"], "needle: engine does not report the plain path"
assert git_paths(b"[core]\n\tx = 1\n") == [], "needle: negative control found a path"
assert check(lambda t: []), "needle: a blind engine (always []) was NOT detected by the harness"
assert check(lambda t: ["sub/a", "zzz"] if "path" in t else []), "needle: an engine with an extra path was NOT detected"
assert sum(1 for n, (r, s) in cases.items() if git_paths(r) == "ERR") <= 8, "needle: too many git-error cases"
for b in bad: print("DIFF", b)
print("cases=%d git_errors=%d diffs=%d" % (len(cases), sum(1 for n, (r, s) in cases.items() if git_paths(r) == "ERR"), len(bad)))
sys.exit(1 if bad else 0)
PY
mkdir -p "$SB/gmwork"
python3 -I "$SB/gmdiff.py" "$ENGINE_DIR" "$SB/gmwork" >"$SB/gm.out" 2>&1
check "engine == real git on the whole corpus (control needles included)" test $? -eq 0
sed 's/^/      | /' "$SB/gm.out" | tail -8
# end to end: a BOM .gitmodules / legacy section naming a submodule is refused as a foreign write target
PG="$(new_project gm)"; mkdir -p "$PG/vend/lib"
printf '\xef\xbb\xbf[submodule "v"]\n\tpath = vend/lib\n\turl = x\n' >"$PG/.gitmodules"
ln -s vend/lib "$PG/sd"; : >/dev/null
expect_rc "a doc under a BOM-headed .gitmodules path is refused (rc 3)" 3 "$C" --project-root "$PG" --non-interactive --doc vend/lib/x.md --set calibration.floor=0.95
printf '[submodule.v]\n\tpath = vend/lib\n' >"$PG/.gitmodules"
expect_rc "…and under a legacy [submodule.v] section (rc 3)" 3 "$C" --project-root "$PG" --non-interactive --doc vend/lib/x.md --set calibration.floor=0.95

echo "== M-2: unsafe characters are escaped by Unicode category =="
pyc '
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
errs = []
unsafe = {0x200B: "ZWSP Cf", 0x200D: "ZWJ Cf", 0x2060: "WJ Cf", 0x206A: "Cf", 0x206F: "Cf", 0xAD: "soft hyphen Cf",
          0xE0041: "tag A Cf", 0xE0001: "Cf", 0xE000: "private use Co", 0xF0000: "Co", 0x0378: "unassigned Cn",
          0x2028: "Zl", 0x2029: "Zp", 0xD800: "Cs", 0x85: "C1", 0x1: "C0", 0x7F: "DEL", 0xFEFF: "BOM", 0x202E: "RLO",
          0x061C: "ALM", 0x180E: "Mongolian vowel sep Cf", 0xFFF9: "interlinear Cf", 0xFFFE: "noncharacter Cn"}
for o, why in unsafe.items():
    if not E.is_unsafe_char(chr(o)): errs.append("U+%04X (%s) not unsafe" % (o, why))
    if ("\\u%04x" % o if o <= 0xFFFF else "\\U%08x" % o) not in E.safe_text("a" + chr(o) + "b"): errs.append("U+%04X not escaped by safe_text" % o)
for c in "aZ09 -_./é中€😀 ́":
    if E.is_unsafe_char(c): errs.append("safe char U+%04X escaped" % ord(c))
# the emitter and the exit-code reporter use the same predicate
import io
class Cap(io.StringIO): encoding = "utf-8"
se = sys.stderr; sys.stderr = Cap()
try:
    E.emit_err("x​y⁠z\U000e0041w")
    v = sys.stderr.getvalue()
finally:
    sys.stderr = se
if "​" in v or "⁠" in v or "\U000e0041" in v or "\\u200b" not in v: errs.append("emitter leaves format chars: %r" % v)
for e in errs: print("FAIL", e)
sys.exit(1 if errs else 0)
' "$ENGINE_DIR" >"$SB/m2.out" 2>&1
check "UNIT-CLASS: Cc/Cf/Cs/Co/Cn/Zl/Zp escaped, ordinary text and emoji kept" test $? -eq 0
sed 's/^/      | /' "$SB/m2.out" | head
# end to end: a directory name with a zero-width space and a tag character is shown escaped in a refusal
newuser 4; PZ="$(new_project zw)"; ZD="$PZ/sub$(printf '\xe2\x80\x8b')z$(printf '\xf3\xa0\x81\x81')"; mkdir "$ZD"; : >"$ZD/.git"
expect_rc "a foreign refusal naming a path with U+200B and U+E0041" 3 "$C" --project-root "$PZ" --non-interactive --doc "sub$(printf '\xe2\x80\x8b')z$(printf '\xf3\xa0\x81\x81')/x.md" --set calibration.floor=0.95
check "…the zero-width characters are not in stderr (escaped instead)" bash -c "python3 -I -c \"import sys; b=open('$SB/last.err','rb').read(); sys.exit(0 if b'\xe2\x80\x8b' not in b and b'\xf3\xa0\x81\x81' not in b else 1)\""

echo "== M-3: user backups are namespaced by their source file =="
export CONSTITUTION_DECISIONS_BACKUP_KEEP=2
PU="$(new_project ub)"
UA="$SB/ubk/a.yml"; UB="$SB/ubk/b.yml"; mkdir -p "$SB/ubk"
for i in 1 2 3 4; do
  CONSTITUTION_DECISIONS_USER_FILE="$UA" "$C" --project-root "$PU" --scope user --non-interactive --set calibration.floor=0.9$i >/dev/null 2>&1
  CONSTITUTION_DECISIONS_USER_FILE="$UB" "$C" --project-root "$PU" --scope user --non-interactive --set calibration.floor=0.9$((i+4)) >/dev/null 2>&1
done
BD="$SB/ubk/.decisions-backup"
check "two user files in one directory keep their own bounded backups (2 + 2)" test "$(ls "$BD" | wc -l)" = 4
check "…the file names carry a per-source tag" bash -c "[ \"\$(ls '$BD' | sed -E 's/^[0-9TZ]+-decisions(-[0-9]+)?//' | sort -u | wc -l)\" = 2 ]"
check "…each tag holds only its own source's earlier content (a.yml keeps 0.92/0.93, b.yml keeps 0.96/0.97; the oldest 0.91/0.95 are pruned)" bash -c "
 ta=\$(grep -l 'calibration.floor: 0.93' '$BD'/*.yml | head -1); tb=\$(grep -l 'calibration.floor: 0.97' '$BD'/*.yml | head -1)
 [ -n \"\$ta\" ] && [ -n \"\$tb\" ] && [ \"\$(basename \$ta | sed -E 's/^[0-9TZ]+-decisions(-[0-9]+)?//')\" != \"\$(basename \$tb | sed -E 's/^[0-9TZ]+-decisions(-[0-9]+)?//')\" ]
 [ \"\$(grep -l 'calibration.floor: 0.9[15]$' '$BD'/*.yml | wc -l)\" = 0 ] || exit 1"
unset CONSTITUTION_DECISIONS_BACKUP_KEEP
check "a file name with odd characters gets a safe tag" bash -c "
 CONSTITUTION_DECISIONS_USER_FILE='$SB/ubk/we ird\$n.yml' '$C' --project-root '$PU' --scope user --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
 CONSTITUTION_DECISIONS_USER_FILE='$SB/ubk/we ird\$n.yml' '$C' --project-root '$PU' --scope user --non-interactive --set calibration.floor=0.96 >/dev/null 2>&1
 ls '$BD' | grep -Eq '^[0-9]{8}T[0-9]{6}Z-decisions(-[0-9]+)?@[A-Za-z0-9_-]+\.yml\$'"

echo "== M-4: R13 write-time foreign re-check (target moved into another repository after validation) =="
newuser 5
PT="$(new_project r13)"; mkdir "$PT/sub"
CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=1 "$C" --project-root "$PT" --non-interactive --doc sub/x.md --set calibration.floor=0.95 >"$SB/t.out" 2>"$SB/t.err" &
tpid=$!
for _i in $(seq 1 60); do [ -e "$PT/.constitution/decisions.intent" ] && break; sleep 0.1; done
printf 'gitdir: ../elsewhere\n' >"$PT/sub/.git"   # sub is now ITS OWN repository (same path, same real directory)
wait "$tpid"; trc=$?
check "the doc write is refused at the last moment (rc 3)" test "$trc" -eq 3
check "…x.md was not written into the new repository" test ! -e "$PT/sub/x.md"
check "…the message names the foreign target" grep -qi 'another repository\|submodule' "$SB/t.err"

echo "== M-4: R21 a key-shaped resolved path is never shown by a refusal =="
newuser 6
PK="$(new_project r21)"; TOK="aB3dEfGhIjKlMnOpQrStUvWxYz0123456789AbCd"
mkdir "$PK/$TOK"; printf 'gitdir: ../x\n' >"$PK/$TOK/.git"; ln -s "$TOK/x.md" "$PK/doc.md"
expect_rc "a doc symlink into a key-named foreign directory" 3 "$C" --project-root "$PK" --non-interactive --doc doc.md --set calibration.floor=0.95
check "…the token-shaped directory name is not echoed" bash -c "! grep -q '$TOK' '$SB/last.out' '$SB/last.err'"
check "…and the refusal says so without showing it (target path looks like key material)" grep -q 'looks like key material; refused and not shown' "$SB/last.err"
# R21 reachability proof (static): every caller of Project.rel passes a path already approved by inside()/doc_path
# (their own looks_secret check on the relpath), so the CLI cannot reach the hiding branch of rel(); it is
# defence in depth and is tested directly (UNIT-CLASS) so removing it cannot survive.
pyc '
import sys, os, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
root = tempfile.mkdtemp(dir=sys.argv[2])
os.makedirs(os.path.join(root, "submodules", "constitution"))
P = E.Project(root)
TOK = "aB3dEfGhIjKlMnOpQrStUvWxYz0123456789AbCd"
errs = []
if P.rel(os.path.join(root, TOK, "x.md")) != "<path hidden: key-shaped>": errs.append("rel shows a key-shaped path")
if P.rel(os.path.join(root, "sub", "x.md")) != os.path.join("sub", "x.md"): errs.append("rel changes an ordinary path")
if P.rel_own(os.path.join(root, TOK, "x.md")) != os.path.join(TOK, "x.md"): errs.append("rel_own must stay plain")
for e in errs: print("FAIL", e)
sys.exit(1 if errs else 0)
' "$ENGINE_DIR" "$SB"
check "UNIT-CLASS: Project.rel hides a key-shaped path, keeps ordinary paths, rel_own stays plain" test $? -eq 0

echo "== M-5: the AST bypass scan covers every output route; argparse goes through the emitter =="
cat >"$SB/astscan.py" <<'PY'
import ast, sys
def scan(src):
    tree = ast.parse(src)
    bad = []
    EMIT = {"_emit", "emit_out", "emit_err", "emit_block", "emit_flush"}
    class V(ast.NodeVisitor):
        def __init__(self): self.fn = []
        def visit_FunctionDef(self, n):
            self.fn.append(n.name); self.generic_visit(n); self.fn.pop()
        def in_emit(self): return bool(EMIT & set(self.fn))
        def visit_Call(self, n):
            f = n.func
            if isinstance(f, ast.Name) and f.id == "print": bad.append(("print", n.lineno))
            if isinstance(f, ast.Name) and f.id == "getattr" and n.args and isinstance(n.args[0], ast.Name) and n.args[0].id == "sys" \
                    and not (len(n.args) > 1 and isinstance(n.args[1], ast.Constant) and n.args[1].value == "encoding"):
                bad.append(("getattr(sys,...)", n.lineno))
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "os" and f.attr in ("write", "fdopen", "dup2", "dup") \
                    and n.args and isinstance(n.args[0], ast.Constant) and n.args[0].value in (0, 1, 2) and not self.in_emit():
                if not (f.attr == "dup2" and "install_excepthook" in self.fn):
                    bad.append(("os.%s(%r)" % (f.attr, n.args[0].value), n.lineno))
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "os" and f.attr == "write" \
                    and n.args and isinstance(n.args[0], ast.Name) and n.args[0].id in ("fd",) and False:
                pass
            if isinstance(f, ast.Name) and f.id == "open" and n.args and isinstance(n.args[0], ast.Constant) \
                    and n.args[0].value in ("/dev/stdout", "/dev/stderr", "/proc/self/fd/1", "/proc/self/fd/2"):
                bad.append(("open(%s)" % n.args[0].value, n.lineno))
            self.generic_visit(n)
        def visit_Attribute(self, n):
            if isinstance(n.value, ast.Name) and n.value.id == "sys" and n.attr in ("stdout", "stderr", "__stdout__", "__stderr__") \
                    and not self.in_emit() and "install_excepthook" not in self.fn:
                bad.append(("sys.%s" % n.attr, n.lineno))
            if isinstance(n.value, ast.Name) and n.value.id in ("traceback", "logging", "pprint", "faulthandler"):
                bad.append((n.value.id + "." + n.attr, n.lineno))
            self.generic_visit(n)
        def visit_Import(self, n):
            for a in n.names:
                if a.name.split(".")[0] in ("traceback", "logging", "pprint", "faulthandler", "warnings"):
                    bad.append(("import " + a.name, n.lineno))
        def visit_ImportFrom(self, n):
            if (n.module or "").split(".")[0] in ("traceback", "logging", "pprint", "faulthandler", "warnings"):
                bad.append(("from " + n.module, n.lineno))
    V().visit(tree)
    return bad
if __name__ == "__main__":
    bad = scan(open(sys.argv[1]).read())
    # CONTROL NEEDLES: the scanner flags each route it claims to cover
    for src in ('import sys\nprint(1)', 'import os\nos.write(2, b"x")', 'import sys\ngetattr(sys, "stderr").write("x")',
                'import traceback\ntraceback.print_exc()', 'import logging\nlogging.error("x")',
                'import os\nos.write(1, b"x")', 'import sys\nsys.stdout.write("x")', 'open("/dev/stderr","w")'):
        assert scan(src), "needle not detected: %r" % src
    assert not scan("def emit_out(t):\n    import sys\n    sys.stdout.write(t)\n"), "needle: emitter use must be allowed"
    for b in bad: print("BYPASS", b)
    sys.exit(1 if bad else 0)
PY
python3 -I "$SB/astscan.py" "$ENGINE" >"$SB/ast7.out" 2>&1
check "static: no print/getattr(sys)/os.write(1|2)/traceback/logging/warnings/pprint bypass (needles included)" test $? -eq 0
sed 's/^/      | /' "$SB/ast7.out" | head
pyc '
import sys, io
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
errs = []
calls = []
def fake_emit(stream, text, end, block=False):
    calls.append((("out" if stream is sys.stdout else "err"), str(text)))
E._emit = fake_emit
class Raw(io.StringIO):
    encoding = "utf-8"
def run(argv):
    del calls[:]
    raw_o, raw_e = Raw(), Raw()
    so, se = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = raw_o, raw_e
    try:
        try:
            rc = E.run_cli(argv)
        except SystemExit as x:
            rc = x.code
    finally:
        sys.stdout, sys.stderr = so, se
    return rc, raw_o.getvalue(), raw_e.getvalue(), list(calls)
for argv in (["--help"], ["-h"], ["--set", "a.b=c", "--help"], ["--show", "-h", "--json"]):
    rc, ro, re_, cs = run(argv)
    if rc != 0: errs.append("%r rc=%r" % (argv, rc))
    if ro or re_: errs.append("%r wrote raw: %r %r" % (argv, ro[:40], re_[:40]))
    if not any("usage:" in t for _s, t in cs): errs.append("%r help not emitted" % (argv,))
rc, ro, re_, cs = run(["--bogus-option"])
if rc != 2: errs.append("bogus rc=%r" % (rc,))
if ro or re_: errs.append("bogus wrote raw: %r %r" % (ro[:40], re_[:40]))
if not any("unrecognized" in t for _s, t in cs): errs.append("usage error not emitted")
rc, ro, re_, cs = run(["--scope", "zzz"])
if rc != 2 or ro or re_: errs.append("invalid choice: rc=%r raw=%r %r" % (rc, ro[:40], re_[:40]))
for e in errs: print("FAIL", e)
sys.exit(1 if errs else 0)
' "$ENGINE_DIR" >"$SB/help.out" 2>&1
check "UNIT-CLASS: --help (also mid-args), usage and argparse errors reach no raw stream, only the emitter" test $? -eq 0
sed 's/^/      | /' "$SB/help.out" | head
"$C" --project-root "$SB" --set a.b=c --help >"$SB/h.out" 2>"$SB/h.err" ; hrc=$?
check "CLI: --help mid-args exits 0 with clean usage text" bash -c "[ $hrc = 0 ] && grep -aq '^usage:' '$SB/h.out' && ! grep -aq $'\x1b' '$SB/h.out'"

echo "== M-6: backup directories are opened without following links and used by descriptor =="
newuser 7
PB="$(new_project m6)"; U7="$SB/u7"; mkdir -p "$U7"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.91\n' >"$CONSTITUTION_DECISIONS_USER_FILE"
VIC="$SB/victim"; mkdir -p "$VIC"; chmod 0755 "$VIC"; : >"$VIC/keep"
mkdir -p "$U7/.decisions-backup"; chmod 0755 "$U7/.decisions-backup"
CONSTITUTION_DECISIONS_TEST_BACKUP_BASE_DELAY=2 "$C" --project-root "$PB" --scope user --non-interactive --set calibration.floor=0.95 >"$SB/b.out" 2>"$SB/b.err" &
bpid=$!
sleep 0.8
mv "$U7/.decisions-backup" "$U7/.decisions-backup.real"; ln -s "$VIC" "$U7/.decisions-backup"
wait "$bpid"; brc=$?
check "user backup: a base swapped for a symlink before it is opened is refused (rc 3)" test "$brc" -eq 3
check "…the victim directory mode is unchanged (no chmod through the link)" test "$(stat -c %a "$VIC")" = 755
check "…nothing was written into the victim" test "$(ls -A "$VIC")" = keep
rm -f "$U7/.decisions-backup"; mv "$U7/.decisions-backup.real" "$U7/.decisions-backup"
# swap AFTER the base was opened and tightened, before the slot is reserved: the descriptor still names the real
# directory, the identity check notices the path no longer does, and nothing lands in the victim
chmod 0755 "$U7/.decisions-backup"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.91\n' >"$CONSTITUTION_DECISIONS_USER_FILE"
CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY=2 "$C" --project-root "$PB" --scope user --non-interactive --set calibration.floor=0.96 >"$SB/b.out" 2>"$SB/b.err" &
bpid=$!
sleep 0.8
mv "$U7/.decisions-backup" "$U7/.decisions-backup.real"; ln -s "$VIC" "$U7/.decisions-backup"
wait "$bpid"; brc=$?
check "user backup: a base swapped after tightening is refused (rc 3)" test "$brc" -eq 3
check "…nothing was written into the victim" test "$(ls -A "$VIC")" = keep
check "…and the real backup directory holds no half-made copy" test -z "$(find "$U7/.decisions-backup.real" -type f 2>/dev/null)"
rm -f "$U7/.decisions-backup"; mv "$U7/.decisions-backup.real" "$U7/.decisions-backup"
# project backups: same two races on .constitution-install-backup
newuser 8
PQ="$(new_project m6p)"
"$C" --project-root "$PQ" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
chmod 0755 "$PQ/.constitution-install-backup" 2>/dev/null || mkdir -m 0755 "$PQ/.constitution-install-backup"
CONSTITUTION_DECISIONS_TEST_BACKUP_BASE_DELAY=2 "$C" --project-root "$PQ" --non-interactive --set calibration.floor=0.96 >"$SB/b.out" 2>"$SB/b.err" &
bpid=$!
sleep 0.8
mv "$PQ/.constitution-install-backup" "$PQ/ib.real"; ln -s "$VIC" "$PQ/.constitution-install-backup"
wait "$bpid"; brc=$?
check "project backup: a base swapped for a symlink before it is opened is refused (rc 3)" test "$brc" -eq 3
check "…the victim is untouched (mode and content)" bash -c "[ \"\$(stat -c %a '$VIC')\" = 755 ] && [ \"\$(ls -A '$VIC')\" = keep ]"
rm -f "$PQ/.constitution-install-backup"; mv "$PQ/ib.real" "$PQ/.constitution-install-backup"
CONSTITUTION_DECISIONS_TEST_BACKUP_SLOT_DELAY=2 "$C" --project-root "$PQ" --non-interactive --set calibration.floor=0.97 >"$SB/b.out" 2>"$SB/b.err" &
bpid=$!
sleep 0.8
mv "$PQ/.constitution-install-backup" "$PQ/ib.real"; ln -s "$VIC" "$PQ/.constitution-install-backup"
wait "$bpid"; brc=$?
check "project backup: a base swapped after tightening is refused (rc 3)" test "$brc" -eq 3
check "…the victim is untouched" test "$(ls -A "$VIC")" = keep
rm -f "$PQ/.constitution-install-backup"; mv "$PQ/ib.real" "$PQ/.constitution-install-backup"
check "static: tighten/listing/creation use a descriptor opened with O_NOFOLLOW (AST)" python3 -I - "$ENGINE" <<'PY'
import ast, sys
src = open(sys.argv[1]).read(); tree = ast.parse(src)
fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
assert "open_base" in fns and "O_NOFOLLOW" in ast.dump(fns["open_base"]) and "O_DIRECTORY" in ast.dump(fns["open_base"])
tb = ast.dump(fns["tighten_base"])
assert "fchmod" in tb and "os.chmod" not in src.split("def tighten_base")[1].split("\ndef ")[0], "tighten_base still path-chmods"
for f in ("backup", "backup_user"):
    d = ast.dump(fns[f]); assert "open_base" in d and "dir_fd" in d and "same_dir" in d, f
PY
finish test_round7
