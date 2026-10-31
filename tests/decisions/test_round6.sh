#!/usr/bin/env bash
# test_round6.sh — regression tests for the round-5 independent review (STRUCTURAL round 6): monotonic backup names,
# the single output emitter (escaping, non-UTF-8, secret-shaped resolved paths), recorded --inherits, the .gitmodules
# grammar, non-UTF-8 .gitmodules, the write-time parent re-check, --check with a pending intent, user scope from HOME,
# 0700 backup bases, and the reviewer-mutant gaps (M05 M09 M18 M20 M21 M23 M24). Class: integration against REAL git
# projects and the REAL wizard CLI; blocks marked UNIT-CLASS import the real engine. Every sandbox is a mktemp -d;
# deletes go through safe_rm_rf; HOME is only ever passed as `env HOME=<sandbox path>` to one child, never reassigned.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'chmod -R u+w "$SB" 2>/dev/null; cleanup_sandbox' EXIT
C="$DEC_CLI"
ENGINE="$(dirname "$C")/decisions_engine.py"
newuser() { export CONSTITUTION_DECISIONS_USER_FILE="$SB/u$1/decisions.yml"; }
pyc() { python3 -I -c "$@"; }
export CONSTITUTION_DECISIONS_TEST=1
STAMP=20260101T000000Z

echo "== I-1: backup names are strictly monotonic; prune never deletes the backup just made =="
newuser 1
backups_ok() { # $1 project, $2 keep, $3 writes, $4 stamp-mode (fixed|back)
  local p="$1" keep="$2" n="$3" i out path last=""
  for i in $(seq 1 "$n"); do
    local st="$STAMP"; [ "$4" = back ] && st="$(printf '20%02d0101T000000Z' $((30 - i)))"
    out="$(CONSTITUTION_DECISIONS_TEST_STAMP="$st" CONSTITUTION_DECISIONS_BACKUP_KEEP="$keep" "$C" --project-root "$p" --non-interactive --set calibration.floor=0.9$i 2>&1)" || { echo "write $i failed: $out"; return 1; }
    path="$(sed -n 's/^backup: //p' <<<"$out" | head -1)"
    if [ "$i" -gt 1 ]; then
      [ -n "$path" ] && [ -d "$p/$path" ] || { echo "write $i: printed backup missing ($path)"; return 1; }
      last="$path"
    fi
  done
  [ "$(ls "$p/.constitution-install-backup" | wc -l)" -eq "$keep" ] || { echo "kept $(ls "$p/.constitution-install-backup" | wc -l) want $keep"; return 1; }
  [ -d "$p/$last" ] || { echo "newest backup gone"; return 1; }
  grep -q "calibration.floor: 0.9$((n-1))" "$p/$last/.constitution/decisions.yml" || { echo "newest backup does not hold the previous content"; return 1; }
}
P1="$(new_project b1)"; check "KEEP=1, 5 writes in one second: the printed backup always exists, only the newest kept" backups_ok "$P1" 1 5 fixed
P2="$(new_project b2)"; check "KEEP=3, 7 writes in one second: three newest kept" backups_ok "$P2" 3 7 fixed
P3="$(new_project b3)"; check "KEEP=1 with a clock that goes BACKWARDS: the newest backup is still kept" backups_ok "$P3" 1 5 back
user_backups_ok() {
  local keep="$1" n="$2" i out path
  for i in $(seq 1 "$n"); do
    out="$(CONSTITUTION_DECISIONS_TEST_STAMP="$STAMP" CONSTITUTION_DECISIONS_BACKUP_KEEP="$keep" "$C" --project-root "$P1" --scope user --non-interactive --set calibration.floor=0.9$i 2>&1)" || { echo "user write $i failed: $out"; return 1; }
    path="$(sed -n 's/^backup (user decisions file): //p' <<<"$out" | head -1)"
    if [ "$i" -gt 1 ]; then [ -n "$path" ] && [ -f "$path" ] || { echo "user write $i: printed backup missing ($path)"; return 1; }; fi
  done
  [ "$(ls "$(dirname "$CONSTITUTION_DECISIONS_USER_FILE")/.decisions-backup" | wc -l)" -eq "$keep" ] || return 1
  grep -q "calibration.floor: 0.9$((n-1))" "$path" || { echo "newest user backup has wrong content"; return 1; }
}
newuser 2; check "user scope KEEP=1, 5 writes in one second" user_backups_ok 1 5
newuser 3; check "user scope KEEP=3, 6 writes in one second" user_backups_ok 3 6

echo "== I-2: ONE emitter; escaping of filesystem-derived output; non-UTF-8 never crashes =="
newuser 4
mkesc() { python3 -I - "$@" <<'PY'
import os, sys
p, kind = sys.argv[1], sys.argv[2]
names = {"esc": "a\x1b[31mb‮c\nd.md", "bad": None, "secret": "sk-abcdefghijklmnopqrstuvwx.md"}
if kind == "bad":
    real = os.path.join(os.fsencode(p), b"x\xff.md")
else:
    real = os.path.join(p, names[kind])
open(real, "w").write("# real\n")
link = os.path.join(p, "AGENTS.md")
os.unlink(link)
os.symlink(os.path.basename(real), link)
PY
}
no_raw() { # file...: no ESC, no bidi override, no NUL in the bytes
  python3 -I - "$@" <<'PY'
import sys
for f in sys.argv[1:]:
    b = open(f, "rb").read()
    t = b.decode("utf-8", "replace")
    bad = [c for c in t if ord(c) == 0x1b or c in "‮‪‫‬‭⁦⁧⁨⁩‎‏"]
    if bad or b"\x00" in b:
        sys.exit(1)
PY
}
PE="$(new_project e1)"; mkesc "$PE" esc
expect_rc "write through a symlinked doc whose real name holds ESC, bidi and newline" 0 "$C" --project-root "$PE" --non-interactive --set calibration.floor=0.95
check "…no raw ESC/bidi in stdout/stderr" no_raw "$SB/last.out" "$SB/last.err"
check "…the 'written:' line stays ONE line (newline escaped)" bash -c "[ \"\$(grep -c '^written: ' '$SB/last.out')\" = 3 ] && ! grep -q '^d.md' '$SB/last.out'"
"$C" --project-root "$PE" --non-interactive --set calibration.floor=0.96 >"$SB/last.out" 2>"$SB/last.err"
check "…and the backup line is clean" no_raw "$SB/last.out" "$SB/last.err"
expect_rc "dry-run through the same symlink" 0 "$C" --project-root "$PE" --non-interactive --set calibration.floor=0.97 --dry-run
check "…'would update' clean" no_raw "$SB/last.out" "$SB/last.err"
python3 -I - "$PE" <<'PY'
import os, sys, glob
p = sys.argv[1]
real = os.path.realpath(os.path.join(p, "AGENTS.md"))
t = open(real).read()
open(real, "w").write(t.split("<!-- BEGIN")[0])
PY
expect_rc "--check drift list" 4 "$C" --project-root "$PE" --check
check "…drift list clean and single-line" bash -c "python3 -I -c \"import sys; b=open('$SB/last.err','rb').read(); sys.exit(0 if b'\x1b' not in b and b.count(b'\n')==1 else 1)\""
expect_rc "--show with an ESC-named project root and symlinked doc" 0 "$C" --project-root "$PE" --show
check "…show clean" no_raw "$SB/last.out" "$SB/last.err"

PB="$(new_project e2)"; mkesc "$PB" bad
expect_rc "non-UTF-8 doc name (symlink target): write completes, no crash" 0 "$C" --project-root "$PB" --non-interactive --set calibration.floor=0.95
check "…no traceback / UnicodeEncodeError" bash -c "! grep -qE 'Traceback|UnicodeEncodeError|Error' '$SB/last.err'"
check "…no intent left behind" test ! -e "$PB/.constitution/decisions.intent"
expect_rc "…a later write works" 0 "$C" --project-root "$PB" --non-interactive --set calibration.floor=0.96
expect_rc "…--check is clean" 0 "$C" --project-root "$PB" --check
expect_rc "…--reset works" 0 "$C" --project-root "$PB" --non-interactive --reset
check "…no intent after reset" test ! -e "$PB/.constitution/decisions.intent"
expect_rc "…--show works" 0 "$C" --project-root "$PB" --show
expect_rc "…--show --json works" 0 "$C" --project-root "$PB" --show --json
check "…--show --json is valid JSON" pyc 'import json,sys; json.load(open(sys.argv[1]))' "$SB/last.out"

PS="$(new_project e3)"; mkesc "$PS" secret
expect_rc "a symlinked doc resolving to a secret-shaped name is refused like a direct --doc" 3 "$C" --project-root "$PS" --non-interactive --set calibration.floor=0.95
check "…the key-shaped name is never shown" bash -c "! grep -q 'abcdefghijklmnop' '$SB/last.out' '$SB/last.err'"
check "…nothing written" bash -c "[ ! -e '$PS/.constitution/decisions.yml' ]"
expect_rc "…--check refuses too" 3 "$C" --project-root "$PS" --check
check "…and does not show it" bash -c "! grep -q 'abcdefghijklmnop' '$SB/last.out' '$SB/last.err'"
expect_rc "direct --doc of the same name stays refused" 3 "$C" --project-root "$(new_project e3b)" --non-interactive --doc sk-abcdefghijklmnopqrstuvwx.md --set calibration.floor=0.95

PX="$(new_project e4)"
python3 -I - "$PX" <<'PY'
import os, sys
p = sys.argv[1]
d = os.path.join(p, "dir\x1b[1m‮Z\nQ"); os.mkdir(d); os.symlink(os.path.basename(d), os.path.join(p, "lnk"))
PY
expect_rc "--export through a symlinked parent with ESC/bidi/newline in its name" 0 "$C" --project-root "$PX" --export lnk/out.yml
check "…exported line clean and single-line" bash -c "python3 -I -c \"import sys; b=open('$SB/last.out','rb').read(); sys.exit(0 if b'\x1b' not in b and '‮'.encode() not in b and b.count(b'\n')==1 else 1)\""

PF="$(new_project e5)"; python3 -I - "$PF" <<'PY'
import os, sys
p = sys.argv[1]
d = os.path.join(p, "sub\x1b[2Jnl\nX"); os.mkdir(d); open(os.path.join(d, ".git"), "w").write("gitdir: ../x\n")
os.symlink(os.path.join(os.path.basename(d), "x.md"), os.path.join(p, "doc.md"))
PY
expect_rc "a foreign refusal naming a resolved path with control characters" 3 "$C" --project-root "$PF" --non-interactive --doc doc.md --set calibration.floor=0.95
check "…stderr is one clean line" bash -c "python3 -I -c \"import sys; b=open('$SB/last.err','rb').read(); sys.exit(0 if b'\x1b' not in b and b.count(b'\n')==1 else 1)\""

# static: no raw print / stream write outside the one emitter (AST)
python3 -I - "$ENGINE" >"$SB/ast.out" 2>&1 <<'PY'
import ast, sys
src = open(sys.argv[1]).read(); tree = ast.parse(src)
bad = []
class V(ast.NodeVisitor):
    def __init__(self): self.fn = []
    def visit_FunctionDef(self, n):
        self.fn.append(n.name); self.generic_visit(n); self.fn.pop()
    def visit_Call(self, n):
        if isinstance(n.func, ast.Name) and n.func.id == "print":
            bad.append(("print", n.lineno))
        self.generic_visit(n)
    def visit_Attribute(self, n):
        if isinstance(n.value, ast.Name) and n.value.id == "sys" and n.attr in ("stdout", "stderr", "__stdout__", "__stderr__"):
            if not ({"_emit", "emit_out", "emit_err", "emit_block", "emit_flush"} & set(self.fn)):
                bad.append(("sys.%s" % n.attr, n.lineno))
        self.generic_visit(n)
V().visit(tree)
for b in bad: print("BYPASS", b)
sys.exit(1 if bad else 0)
PY
check "static: no print() and no sys.stdout/sys.stderr use outside _emit" test $? -eq 0
[ -s "$SB/ast.out" ] && sed 's/^/      | /' "$SB/ast.out" | head

echo "== UNIT-CLASS: the exit-code reporter keeps validated paths un-redacted and still redacts secrets =="
pyc '
import sys, io
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
LONG = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1bbbbbbbbbbbbbbbbbbbbbbbb"
buf = io.StringIO(); old = sys.stderr; sys.stderr = buf
rc = E.report_exception(E.Precondition("x resolves to " + LONG))
sys.stderr = old
assert rc == 3 and LONG in buf.getvalue(), (rc, buf.getvalue())
buf = io.StringIO(); sys.stderr = buf
rc = E.report_exception(E.Refused("bad " + "sk-" + "a" * 20))
sys.stderr = old
assert rc == 4 and "sk-aaaa" not in buf.getvalue() and "[redacted]" in buf.getvalue(), buf.getvalue()
' "$(dirname "$ENGINE")"
check "UNIT: report_exception Precondition not redacted, Refused redacted" test $? -eq 0
mkdir -p "$SB/pwhome/submodules/constitution" "$SB/other"; git -C "$SB/pwhome" init -q 2>/dev/null
pyc '
import sys, os
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import decisions_engine as E
fake = sys.argv[2]
class PW:
    pw_dir = fake
E.pwd.getpwuid = lambda uid: PW()
os.environ["HOME"] = sys.argv[3]
p = E.Project(fake)
try:
    p.require_inherited(None)
except E.Precondition as exc:
    assert "HOME" in str(exc), exc
else:
    raise SystemExit("pwd-entry home accepted")
' "$(dirname "$ENGINE")" "$SB/pwhome" "$SB/other"
check "UNIT: the passwd-entry home directory is refused even when \$HOME differs" test $? -eq 0

echo "== I-3: --inherits is remembered, validated and consistent =="
newuser 5
PI="$SB/inh"; mkdir -p "$PI/vendor/constit"; git -C "$PI" init -q 2>/dev/null; printf '# I\n' >"$PI/CLAUDE.md"
expect_rc "write with --inherits vendor/constit" 0 "$C" --project-root "$PI" --non-interactive --inherits vendor/constit --set calibration.floor=0.95
expect_rc "a LATER write without the flag is not blocked" 0 "$C" --project-root "$PI" --non-interactive --set calibration.floor=0.96
check "…the recorded inherits is kept" grep -q '^inherits: vendor/constit$' "$PI/.constitution/decisions.yml"
expect_rc "--show reports the recorded path" 0 "$C" --project-root "$PI" --show
check "…text" grep -q 'inherits from vendor/constit' "$SB/last.out"
"$C" --project-root "$PI" --show --json >"$SB/last.out" 2>/dev/null
check "…json" pyc 'import json,sys; assert json.load(open(sys.argv[1]))["inherits"]=="vendor/constit"' "$SB/last.out"
expect_rc "the recorded inherits path still protects: --doc into it refused (M05)" 3 "$C" --project-root "$PI" --non-interactive --doc vendor/constit/x.md --set calibration.floor=0.97
expect_rc "…also with the flag given explicitly" 3 "$C" --project-root "$PI" --non-interactive --inherits vendor/constit --doc vendor/constit/x.md --set calibration.floor=0.97
expect_rc "…--export into it refused" 3 "$C" --project-root "$PI" --export vendor/constit/e.yml
expect_rc "a nonexistent --inherits path is a usage error" 2 "$C" --project-root "$(new_project i2)" --non-interactive --inherits nope/x --set calibration.floor=0.95
expect_rc "…also for --show" 2 "$C" --project-root "$(new_project i2b)" --show --inherits nope/x
mv "$PI/vendor/constit" "$PI/vendor/gone"
expect_rc "a recorded inherits that no longer exists blocks the write (not silently replaced)" 3 "$C" --project-root "$PI" --non-interactive --set calibration.floor=0.98
check "…decisions.yml unchanged" grep -q '^inherits: vendor/constit$' "$PI/.constitution/decisions.yml"
mv "$PI/vendor/gone" "$PI/vendor/constit"

PCR="$SB/crafted"; mkdir -p "$PCR/vendor/constit" "$PCR/.constitution"; printf '# C\n' >"$PCR/CLAUDE.md"
printf 'schema_version: 1\ninherits: vendor/constit\ndecisions: {}\n' >"$PCR/.constitution/decisions.yml"
expect_rc "a crafted decisions.yml naming inherits does not waive the repository check (recorded path replaces only the constitution check)" 3 "$C" --project-root "$PCR" --non-interactive --accept-external-edits --set calibration.floor=0.95
check "…says git repository" grep -qi 'git repository' "$SB/last.err"

echo "== MINOR: .gitmodules grammar (git config syntax) and non-UTF-8 bytes =="
newuser 6
PG="$(new_project g1)"
rm -rf "${PG:?}/submodules"; mkdir -p "$PG/submodules/constitution"
python3 -I - "$PG" <<'PY'
import os, sys
p = sys.argv[1]
for d in ("d1", "d two", "d3", "d4", "d5", "d6", "d#7", "d8", "d9"):
    os.makedirs(os.path.join(p, d))
open(os.path.join(p, ".gitmodules"), "wb").write(
    b'[submodule "a"]\n\tPATH = d1\n'
    b'[submodule "b"]\n\tpath = "d two"\n'
    b'[submodule "c"]\n\tpath = d3 ; comment\n'
    b'[submodule "d"]\n\tpath = d4 # comment\n'
    b'[submodule "e"] path = d5\n'
    b'[SubModule "f"]\r\n\tpath = d6\r\n'
    b'[submodule "g"]\n\tpath = "d#7"\n'
    b'# path = d8\n'
    b'[other "x"]\n\tpath = d9\n')
PY
for d in d1 "d two" d3 d4 d5 d6 "d#7"; do
  expect_rc ".gitmodules form protects '$d'" 3 "$C" --project-root "$PG" --non-interactive --doc "$d/x.md" --set calibration.floor=0.95
done
expect_rc "a commented-out path does not protect d8" 0 "$C" --project-root "$PG" --non-interactive --doc d8/x.md --set calibration.floor=0.95
expect_rc "a path in a non-submodule section does not protect d9" 0 "$C" --project-root "$PG" --non-interactive --doc d9/x.md --set calibration.floor=0.96
PN="$(new_project g2)"; mkdir -p "$PN/d1"
printf '# caf\xe9 \xff comment\n[submodule "a"]\n\tpath = d1\n' >"$PN/.gitmodules"
expect_rc "non-UTF-8 .gitmodules: --check reports instead of refusing" 0 "$C" --project-root "$PN" --check
expect_rc "…--show works" 0 "$C" --project-root "$PN" --show
expect_rc "…a write works" 0 "$C" --project-root "$PN" --non-interactive --set calibration.floor=0.95
expect_rc "…and still protects its path" 3 "$C" --project-root "$PN" --non-interactive --doc d1/x.md --set calibration.floor=0.96
expect_rc "…--reset works" 0 "$C" --project-root "$PN" --non-interactive --reset

echo "== MINOR: the resolved parent is re-checked immediately before the replace (TOCTOU) =="
newuser 7
PT="$(new_project t1)"; mkdir "$PT/sub"
CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2 "$C" --project-root "$PT" --non-interactive --doc sub/x.md --set calibration.floor=0.95 >"$SB/t.out" 2>"$SB/t.err" &
tpid=$!
for _i in $(seq 1 40); do [ -e "$PT/.constitution/decisions.intent" ] && break; sleep 0.1; done
mv "$PT/sub" "$PT/sub.real"; ln -s sub.real "$PT/sub"
wait "$tpid"; trc=$?
check "the swapped parent is refused (rc 3)" test "$trc" -eq 3
check "…x.md was not written through the swapped link" test ! -e "$PT/sub.real/x.md"
check "…the message says the parent changed" grep -qi 'changed' "$SB/t.err"
rm "$PT/sub"; mv "$PT/sub.real" "$PT/sub"
expect_rc "after restoring, the next run completes the write" 0 "$C" --project-root "$PT" --non-interactive --doc sub/x.md --set calibration.floor=0.95
check "…x.md has the block" grep -q 'BEGIN constitution-decisions' "$PT/sub/x.md"

echo "== MINOR: --check is not clean while the intent is pending =="
newuser 8
PC="$(new_project c1)"
"$C" --project-root "$PC" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
expect_rc "baseline --check clean" 0 "$C" --project-root "$PC" --check
sha256sum "$PC/.constitution/decisions.yml" | cut -d' ' -f1 >"$PC/.constitution/decisions.intent"
expect_rc "--check with a pending intent is rc 4" 4 "$C" --project-root "$PC" --check
check "…says an unfinished write" grep -qi 'unfinished\|intent' "$SB/last.err"
"$C" --project-root "$PC" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
expect_rc "a completing run clears it" 0 "$C" --project-root "$PC" --check
rm "$PC/.constitution/decisions.sha256"
expect_rc "--check with the sidecar missing is rc 4" 4 "$C" --project-root "$PC" --check

echo "== MINOR: user scope needs no project repo; HOME checks use realpath of \$HOME and the passwd entry; 0700 bases =="
H="$SB/home9"; mkdir -p "$H"
UF="$H/.config/constitution/decisions.yml"
expect_rc "--scope user with the project root = HOME (no repo, no constitution)" 0 env HOME="$H" CONSTITUTION_DECISIONS_USER_FILE="$UF" "$C" --project-root "$H" --scope user --non-interactive --set hosted.allowed=false
check "…the user file exists" test -f "$UF"
expect_rc "--scope user from HOME as the working directory" 0 sh -c 'cd "$1" && HOME="$1" CONSTITUTION_DECISIONS_USER_FILE="$2" "$3" --scope user --non-interactive --set hosted.allowed=true' _ "$H" "$UF" "$C"
BARE="$SB/bare9"; mkdir -p "$BARE"
expect_rc "--scope user in a bare non-repo directory" 0 "$C" --project-root "$BARE" --scope user --non-interactive --set calibration.floor=0.95
expect_rc "…the user file still may not resolve inside a real project" 3 env CONSTITUTION_DECISIONS_USER_FILE="$(new_project u9)/inproj/decisions.yml" "$C" --project-root "$(cd "$SB/u9" 2>/dev/null && pwd -P || echo "$SB/u9")" --scope user --non-interactive --set calibration.floor=0.95
FH="$SB/fh9"; mkdir -p "$FH/submodules/constitution"; git -C "$FH" init -q 2>/dev/null; ln -s "$FH" "$SB/homelink"
expect_rc "a symlinked \$HOME is still the HOME directory (project scope refused)" 3 env HOME="$SB/homelink" "$C" --project-root "$SB/homelink" --non-interactive --set calibration.floor=0.95
PB9="$(new_project bb9)"; mkdir -m 0755 "$PB9/.constitution-install-backup"
"$C" --project-root "$PB9" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
"$C" --project-root "$PB9" --non-interactive --set calibration.floor=0.96 >/dev/null 2>&1
check "a pre-existing 0755 project backup base is tightened to 0700" test "$(stat -c %a "$PB9/.constitution-install-backup")" = 700
UD="$SB/u10"; mkdir -p "$UD/.decisions-backup"; chmod 0755 "$UD/.decisions-backup"; export CONSTITUTION_DECISIONS_USER_FILE="$UD/decisions.yml"
"$C" --project-root "$PB9" --scope user --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
"$C" --project-root "$PB9" --scope user --non-interactive --set calibration.floor=0.96 >/dev/null 2>&1
check "a pre-existing 0755 user backup base is tightened to 0700" test "$(stat -c %a "$UD/.decisions-backup")" = 700

echo "== reviewer-mutant gaps: M09 not-in-repo, M21 .git FILE, M23 ancestor .git, M24 export onto a directory =="
newuser 11
NR="$SB/norepo"; mkdir -p "$NR/submodules/constitution"; printf '# N\n' >"$NR/CLAUDE.md"
if git -C "$SB" rev-parse --git-dir >/dev/null 2>&1; then echo "  SKIP sandbox sits inside a git repository"; else
  expect_rc "M09: constitution dir present but no git repository anywhere: refused" 3 "$C" --project-root "$NR" --non-interactive --set calibration.floor=0.95
  check "…names the git requirement" grep -qi 'git repository' "$SB/last.err"
fi
OUT="$SB/outer"; mkdir -p "$OUT/sub/proj/submodules/constitution"; git -C "$OUT" init -q 2>/dev/null; printf '# O\n' >"$OUT/sub/proj/CLAUDE.md"
expect_rc "M23: the repository is an ANCESTOR of the project root: accepted" 0 "$C" --project-root "$OUT/sub/proj" --non-interactive --set calibration.floor=0.95
WT="$SB/wt"; mkdir -p "$WT/submodules/constitution"; printf 'gitdir: /nonexistent/x\n' >"$WT/.git"; printf '# W\n' >"$WT/CLAUDE.md"
expect_rc "M21: a project root whose .git is a FILE (worktree/submodule checkout) is accepted" 0 "$C" --project-root "$WT" --non-interactive --set calibration.floor=0.95
mkdir -p "$WT/nested"; printf 'gitdir: ../x\n' >"$WT/nested/.git"
expect_rc "M21: a nested directory whose .git is a FILE is foreign" 3 "$C" --project-root "$WT" --non-interactive --doc nested/x.md --set calibration.floor=0.96
PD="$(new_project d24)"; mkdir "$PD/outdir"
expect_rc "M24: --export onto a directory" 3 "$C" --project-root "$PD" --export outdir
check "…says it is a directory" grep -qi 'is a directory' "$SB/last.err"

echo "== resolved paths: a leaf symlink is not followed, parent resolution is checked =="
PL="$(new_project l1)"; mkdir "$PL/real"; ln -s real "$PL/viaL"
expect_rc "--export through an in-project symlinked parent is allowed and shown resolved" 0 "$C" --project-root "$PL" --export viaL/o.yml
check "…the shown path is the resolved one" grep -q '^exported: real/o.yml$' "$SB/last.out"

finish test_round6
