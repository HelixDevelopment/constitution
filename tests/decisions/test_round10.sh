#!/usr/bin/env bash
# test_round10.sh — regression tests for the round-5 review findings, re-reproduced on the CURRENT tree. Findings 1-5,
# 7 and 8 no longer reproduced (closed by rounds 6-9; covered by test_round6.sh and the groups below, which add
# engine MUTANTS for the reviewer-mutant gaps M05 M09 M18 M20 M21 M23). Finding 6 (the guard-to-rename race) DID
# reproduce: a parent swapped for a symlink into a nested repository AFTER the guard and BEFORE os.replace landed the
# block in the nested repository. Fix: the temp file is created and renamed through a directory DESCRIPTOR opened
# (O_NOFOLLOW) before the guard; the guard also checks that the path still names that descriptor's directory.
# Each test runs the real wizard CLI (must pass) and, where stated, a sandbox MUTANT copy (must differ).
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'cleanup_sandbox' EXIT
C="$DEC_CLI"; ENGINE_DIR="$(dirname "$C")"
export CONSTITUTION_DECISIONS_TEST=1

mutant_cli() { # $1 name, then pairs "old" "new" ($# even after name); every old text must occur exactly once
  local name="$1"; shift; local m="$SB/mut_$name"; mkdir -p "$m"
  cp "$ENGINE_DIR/constitution_decisions.sh" "$ENGINE_DIR/decisions_engine.py" "$m/" || return 1
  python3 -I - "$m/decisions_engine.py" "$@" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read(); a = sys.argv[2:]
for i in range(0, len(a), 2):
    if s.count(a[i]) != 1: sys.exit(1)
    s = s.replace(a[i], a[i + 1], 1)
open(p, "w").write(s)
PY
  printf '%s' "$m/constitution_decisions.sh"
}

# ---- finding 6: swap AFTER the guard, BEFORE the rename --------------------------------------------------------
race_case() { # $1 = cli, $2 = POSTGUARD or POSTCHECK window, $3 = 1 (default) the attacker moves the temp file along; sets RRC, NESTED_HIT (1 when x.md landed in the nested repository)
  local cli="$1" p; p="$SB/race$RANDOM$RANDOM"; mkdir -p "$p/submodules/constitution" "$p/sub" "$p/nested"
  git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q
  git -C "$p/nested" init -q; printf '# P\n' >"$p/CLAUDE.md"
  env "CONSTITUTION_DECISIONS_TEST_${2}_NAME=x.md" "CONSTITUTION_DECISIONS_TEST_${2}_DELAY=3" \
    "$cli" --project-root "$p" --non-interactive --doc sub/x.md --set calibration.floor=0.95 >"$p.out" 2>"$p.err" &
  local pid=$! i
  for i in $(seq 1 80); do ls "$p"/sub/.x.md.tmp.* >/dev/null 2>&1 && break; sleep 0.1; done
  # the guard has already passed. The attacker (who can see the temp name) moves the temp file along and points the path
  # into the nested repository: before the fix the rename then lands x.md inside it.
  sleep 0.5
  [ "${3:-1}" = 1 ] && mv "$p"/sub/.x.md.tmp.* "$p/nested/" 2>/dev/null
  mv "$p/sub" "$p/sub.orig"; ln -s nested "$p/sub"
  wait "$pid"; RRC=$?
  NESTED_HIT=0; [ -e "$p/nested/x.md" ] && NESTED_HIT=1
  RACE_P="$p"
}
echo "== finding 6: parent swapped into a nested repository after the guard =="
race_case "$C" POSTGUARD
check "real engine (swap before the identity check): nothing is written into the nested repository (hit=$NESTED_HIT)" test "$NESTED_HIT" = 0
check "real engine: no temp file left in the original directory" bash -c "! ls '$RACE_P'/sub.orig/.x.md.tmp.* >/dev/null 2>&1"
check "real engine (swap before the identity check): exits non-zero (rc=$RRC)" test "$RRC" -ne 0
race_case "$C" POSTCHECK
check "real engine (swap after the identity check): nothing lands in the nested repository (hit=$NESTED_HIT)" test "$NESTED_HIT" = 0
check "real engine: the command did not report success after losing its temp file (rc=$RRC)" test "$RRC" -ne 0

echo "== finding 6 mutants =="
MA="$(mutant_cli ra 'os.replace(tmpname, name, src_dir_fd=dfd, dst_dir_fd=dfd)' 'os.replace(os.path.join(d, tmpname), path)')"
check "mutant A (path-based rename) built" test -n "$MA"
race_case "$MA" POSTCHECK
check "mutant A is caught: its rename lands in the nested repository (hit=$NESTED_HIT)" test "$NESTED_HIT" = 1
MB="$(mutant_cli rb '        _same_parent(dfd, d)
' '')"
check "mutant B (no identity check) built" test -n "$MB"
# the attacker leaves the temp file in place: the real engine refuses (identity check), the mutant writes into the old directory
race_case "$C" POSTGUARD 0
check "real engine (swap, temp file left): refused rc 3 and x.md written nowhere (rc=$RRC)" bash -c "[ $RRC = 3 ] && [ ! -e '$RACE_P/sub.orig/x.md' ] && [ ! -e '$RACE_P/nested/x.md' ]"
race_case "$MB" POSTGUARD 0
check "mutant B is caught: without the identity check the run succeeds (rc=$RRC)" test "$RRC" = 0
MC="$(mutant_cli rc 'flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0) | (os.O_NOFOLLOW if nofollow else 0)' 'flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0)')"
check "mutant C (parent opened following a final symlink) built" test -n "$MC"
PCN="$(new_project cn)"; mkdir -p "$PCN/real/nested" "$PCN/nested2"; git -C "$PCN/nested2" init -q; ln -s nested2 "$PCN/lnk"
# a parent that IS a symlink at open time: validation (inside) already resolves it, so the CLI refuses earlier; the
# descriptor flag is exercised here directly (UNIT-CLASS, real engine function)
cat >"$SB/unit_open.py" <<'PY'
import os, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
link = sys.argv[2]
try:
    fd = d._open_parent(link, nofollow=True); os.close(fd); print("OPENED")
except d.Precondition:
    print("REFUSED")
PY
check "UNIT: a symlinked parent is refused by the real _open_parent" test "$(python3 -I "$SB/unit_open.py" "$ENGINE_DIR" "$PCN/lnk")" = REFUSED
MCDIR="$(dirname "$MC")"
check "UNIT mutant C is caught: the symlinked parent is opened" test "$(python3 -I "$SB/unit_open.py" "$MCDIR" "$PCN/lnk")" = OPENED

# ---- helpers for the re-reproduced round-5 findings ---------------------------------------------------------------
newproj() { local p="$SB/$1"; mkdir -p "$p/submodules/constitution"; git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q
  printf '# P\n' >"$p/CLAUDE.md"; printf '# A\n' >"$p/AGENTS.md"; printf '%s' "$p"; }
run() { "$@" >"$SB/o" 2>"$SB/e"; RC=$?; }
caught() { # $1 label, $2 expression evaluated with RC (the mutant must make it TRUE)
  check "$1 (rc=$RC)" bash -c "$2"; }

echo "== finding 1: the newest backup survives KEEP=1 (both scopes); printed path exists =="
for scope in project user; do
  P="$(newproj f1$scope)"; export CONSTITUTION_DECISIONS_USER_FILE="$SB/f1u$scope/d.yml"; export CONSTITUTION_DECISIONS_BACKUP_KEEP=1
  last=""
  fl=0
  for st in 20300101T000000Z 20200101T000000Z 20300101T000000Z 20100101T000000Z; do   # frozen AND backwards clock
    fl=$((fl+1)); CONSTITUTION_DECISIONS_TEST_STAMP=$st run "$C" --project-root "$P" --scope "$scope" --non-interactive --set calibration.floor=0.9$fl
    last="$(grep -o 'backup[^:]*: .*' "$SB/o" | tail -1 | sed 's/^[^:]*: //')"
  done
  if [ "$scope" = project ]; then bp="$P/$last"; bd="$P/.constitution-install-backup"; else bp="$last"; bd="$SB/f1uuser/.decisions-backup"; fi
  check "$scope: the last printed backup path exists" test -n "$last" -a -e "$bp"
  check "$scope: exactly 1 backup kept" test "$(ls "$bd" | wc -l)" = 1
done
unset CONSTITUTION_DECISIONS_BACKUP_KEEP
M1="$(mutant_cli m1 '    if best is None or now > best[0]:
        return now, 1
    return best[0], best[1] + 1' '    return now, 1')"
check "mutant (name ignores existing backups) built" test -n "$M1"
P="$(newproj f1m)"; export CONSTITUTION_DECISIONS_BACKUP_KEEP=1
fl=0; for st in 20300101T000000Z 20200101T000000Z; do fl=$((fl+1)); CONSTITUTION_DECISIONS_TEST_STAMP=$st run "$M1" --project-root "$P" --non-interactive --set calibration.floor=0.9$fl; done
last="$(grep -o 'backup[^:]*: .*' "$SB/o" | tail -1 | sed 's/^[^:]*: //')"
check "mutant is caught: the just-made backup was pruned (path missing)" bash -c "[ -n '$last' ] && [ ! -e '$P/$last' ]"
unset CONSTITUTION_DECISIONS_BACKUP_KEEP

echo "== finding 2: ONE emitter for every print site; resolved names escaped; secret-shaped resolved paths refused =="
export CONSTITUTION_DECISIONS_USER_FILE="$SB/f2u/d.yml"
P="$(newproj f2)"; ESC="$(printf 'a\033]0;PWN\007b.md')"; NL="$(printf 'a\nwritten: FORGED.md')"; NU="$(printf 'bad\377name.md')"
for nm in "$ESC" "$NL" "$NU"; do printf '# x\n' >"$P/$nm"; done
ln -s "$ESC" "$P/l1.md"; ln -s "$NL" "$P/l2.md"; ln -s "$NU" "$P/l3.md"
run "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 --doc l1.md --doc l2.md --doc l3.md
check "hostile resolved names: rc 0" test "$RC" = 0
check "…no ESC byte in stdout/stderr" bash -c "! LC_ALL=C grep -q \$'\\033' '$SB/o' '$SB/e'"
check "…no forged 'written: FORGED.md' line" bash -c "! grep -q '^written: FORGED.md' '$SB/o'"
check "…no traceback" bash -c "! grep -q Traceback '$SB/e'"
check "…no decisions.intent left behind" test ! -e "$P/.constitution/decisions.intent"
run "$C" --project-root "$P" --non-interactive --reset
check "…a later --reset works (rc 0)" test "$RC" = 0
run "$C" --project-root "$P" --check --doc l1.md --doc l2.md --doc l3.md
check "…--check over the hostile names has no raw ESC and no traceback" bash -c "! LC_ALL=C grep -q \$'\\033' '$SB/o' '$SB/e' && ! grep -q Traceback '$SB/e'"
run "$C" --project-root "$P" --export out.yml --force-export
check "…--export prints 'exported:' (rc 0)" bash -c "[ $RC = 0 ] && grep -q '^exported: out.yml' '$SB/o'"
SECN="sk-abcdefghijklmnopqrstuvwxyz0123456789.md"; printf '# x\n' >"$P/$SECN"; ln -s "$SECN" "$P/ls.md"
run "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96 --doc ls.md
check "secret-shaped resolved doc path: refused rc 3" test "$RC" = 3
check "…and never shown" bash -c "! grep -q 'sk-abcdefgh' '$SB/o' '$SB/e'"
NR="$SB/$(printf 'r\377oot')"; mkdir -p "$NR/submodules/constitution"; git -C "$NR" init -q 2>/dev/null; printf '# P\n' >"$NR/CLAUDE.md"
run "$C" --project-root "$NR" --show; check "non-UTF-8 root: --show rc 0, no traceback" bash -c "[ $RC = 0 ] && ! grep -q Traceback '$SB/e'"
run "$C" --project-root "$NR" --non-interactive --set calibration.floor=0.95; check "non-UTF-8 root: write rc 0" test "$RC" = 0
# census (control-needled): every output call in the engine goes through the emitter helpers; the scanner must see a planted raw print
cat >"$SB/census.py" <<'PY'
import ast, sys
src = open(sys.argv[1]).read(); t = ast.parse(src); bad = []
for n in ast.walk(t):
    if isinstance(n, ast.Call):
        f = n.func
        if isinstance(f, ast.Name) and f.id == "print": bad.append(n.lineno)
        if isinstance(f, ast.Attribute) and f.attr in ("write", "writelines") and isinstance(f.value, ast.Attribute) \
           and isinstance(f.value.value, ast.Name) and f.value.value.id == "sys": bad.append(n.lineno)
print(len(bad))
PY
printf 'import sys\nprint("x")\nsys.stdout.write("y")\n' >"$SB/needle.py"
check "census needle: the scanner sees 2 planted raw output calls" test "$(python3 -I "$SB/census.py" "$SB/needle.py")" = 2
raw="$(python3 -I "$SB/census.py" "$ENGINE_DIR/decisions_engine.py")"
check "census: raw print/sys.stdout.write sites in the engine = 0 except the emitter's own stream.write (got $raw sys.*.write)" test "$raw" = 0
M2="$(mutant_cli m2 '    return "".join(_uesc(c) if is_unsafe_char(c) and c != "\t" else c for c in s)' '    return s')"
check "mutant (emitter does not escape) built" test -n "$M2"
run "$M2" --project-root "$P" --non-interactive --set calibration.floor=0.97 --doc l1.md
check "mutant is caught: raw ESC reaches the terminal" bash -c "LC_ALL=C grep -q \$'\\033' '$SB/o'"
M3="$(mutant_cli m3 'if looks_secret(os.path.relpath(real, self.root)):  # same policy as a direct argument (round-5 I-2)' 'if False:')"
check "mutant (no secret policy for resolved doc paths) built" test -n "$M3"
run "$M3" --project-root "$P" --non-interactive --set calibration.floor=0.97 --doc ls.md
check "mutant is caught: the secret-shaped resolved path is accepted" test "$RC" = 0

echo "== finding 3: --inherits is remembered; M05 (the recorded path stays protected) =="
PI="$SB/inh"; mkdir -p "$PI/vendor/constit"; git -C "$PI" init -q 2>/dev/null; printf '# I\n' >"$PI/CLAUDE.md"
run "$C" --project-root "$PI" --non-interactive --inherits vendor/constit --set calibration.floor=0.95
run "$C" --project-root "$PI" --non-interactive --set calibration.floor=0.96; check "a later write without the flag works" test "$RC" = 0
run "$C" --project-root "$PI" --non-interactive --reset; check "a later --reset without the flag works" test "$RC" = 0
run "$C" --project-root "$PI" --non-interactive --set calibration.floor=0.96
run "$C" --project-root "$PI" --show --json; check "--show --json reports vendor/constit" grep -q '"inherits": "vendor/constit"' "$SB/o"
run "$C" --project-root "$PI" --non-interactive --doc vendor/constit/x.md --set calibration.floor=0.97
check "--doc into the recorded inherits path is refused (rc 3)" test "$RC" = 3
M5="$(mutant_cli m5 'cands = ["submodules/constitution", "constitution"] + ([self.inh_override] if self.inh_override else [])' 'cands = ["submodules/constitution", "constitution"]')"
check "mutant M05 built" test -n "$M5"
run "$M5" --project-root "$PI" --non-interactive --doc vendor/constit/x.md --set calibration.floor=0.97
check "mutant M05 is caught: the write into the inherited path is allowed" test "$RC" = 0
M5b="$(mutant_cli m5b '        rec = proj.recorded_inherits()' '        rec = None')"
check "mutant (recorded inherits ignored) built" test -n "$M5b"
rm -f "$PI/vendor/constit/x.md"
run "$M5b" --project-root "$PI" --non-interactive --set calibration.floor=0.98
check "mutant is caught: the later write without the flag is blocked (rc 3)" test "$RC" = 3

echo "== finding 4: .gitmodules PATH=, quoted values, trailing ; comments =="
P="$(newproj f4)"; mkdir -p "$P/mod1" "$P/mod2" "$P/mod3"
printf '[submodule "a"]\n\tPATH = mod1\n[submodule "b"]\n\tpath = "mod2"\n[submodule "c"]\n\tpath = mod3 ; note\n' >"$P/.gitmodules"
for m in mod1 mod2 mod3; do run "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 --doc $m/f.md; check "$m: write into the submodule path refused (rc 3)" test "$RC" = 3; done
MK="$(mutant_cli mk '            key = text[i:j].lower()' '            key = text[i:j]')"
MQ="$(mutant_cli mq "        if c == '\"':
            if not inq:
                buf.extend(pend)
            pend = []
            inq = not inq
            j += 1
            continue" "        if c == '\"':
            buf.append(c)
            j += 1
            continue")"
MS="$(mutant_cli ms '        elif c in "#;":
            while j < n and text[j] != "\n":
                j += 1
            continue
        elif c == "\r"' '        elif c == "\r"')"
check "mutants K Q S built" test -n "$MK" -a -n "$MQ" -a -n "$MS"
run "$MK" --project-root "$P" --non-interactive --set calibration.floor=0.95 --doc mod1/f.md; check "mutant K (case-sensitive keys) is caught" test "$RC" != 3
run "$MQ" --project-root "$P" --non-interactive --set calibration.floor=0.95 --doc mod2/f.md; check "mutant Q (quotes literal) is caught" test "$RC" != 3
run "$MS" --project-root "$P" --non-interactive --set calibration.floor=0.95 --doc mod3/f.md; check "mutant S (no trailing comment) is caught" test "$RC" != 3

echo "== finding 5: a non-UTF-8 .gitmodules does not refuse the run =="
P="$(newproj f5)"; printf '# c \377\n[submodule "a"]\n\tpath = z\n' >"$P/.gitmodules"
run "$C" --project-root "$P" --check; check "--check rc 0" test "$RC" = 0
run "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95; check "write rc 0" test "$RC" = 0
run "$C" --project-root "$P" --non-interactive --reset; check "--reset rc 0" test "$RC" = 0
M6="$(mutant_cli m6 'raw.decode("utf-8", "surrogateescape")' 'raw.decode("utf-8")')"
run "$M6" --project-root "$P" --check; check "mutant (strict decode) is caught: rc != 0" test "$RC" != 0

echo "== finding 7: --check with a pending intent is not clean =="
P="$(newproj f7)"; run "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
sha256sum "$P/.constitution/decisions.yml" | cut -d' ' -f1 >"$P/.constitution/decisions.intent"
run "$C" --project-root "$P" --check; check "rc 4" test "$RC" = 4
M7="$(mutant_cli m7 '    if os.path.lexists(proj.ifile):
        emit_err("check: .constitution/decisions.intent is present' '    if False:
        emit_err("check: .constitution/decisions.intent is present')"
run "$M7" --project-root "$P" --check; check "mutant is caught: rc 0 with the intent pending" test "$RC" = 0

echo "== finding 8 + reviewer mutants M09 M20 M21 M23, 0700 bases =="
run "$C" --project-root "$(newproj f8)" --non-interactive --inherits nope/x --set calibration.floor=0.95; check "nonexistent --inherits: usage error rc 2" test "$RC" = 2
H="$SB/home8"; mkdir -p "$H"; export CONSTITUTION_DECISIONS_USER_FILE="$H/.config/d.yml"
run sh -c 'cd "$1" && HOME="$1" "$2" --scope user --non-interactive --set hosted.allowed=true' _ "$H" "$C"; check "--scope user from HOME rc 0" test "$RC" = 0
# M20: symlinked HOME
FH="$SB/fh8"; mkdir -p "$FH/submodules/constitution"; git -C "$FH" init -q 2>/dev/null; ln -s "$FH" "$SB/homelink8"
run env HOME="$SB/homelink8" "$C" --project-root "$SB/homelink8" --non-interactive --set calibration.floor=0.95; check "symlinked HOME is HOME: refused rc 3" test "$RC" = 3
M20="$(mutant_cli m20 '        hs.add(os.path.realpath(h))' '        hs.add(h)')"
run env HOME="$SB/homelink8" "$M20" --project-root "$SB/homelink8" --non-interactive --set calibration.floor=0.95; check "mutant M20 is caught: accepted" test "$RC" = 0
# M09 / M23 / M21
NRP="$SB/norepo"; mkdir -p "$NRP/submodules/constitution"; printf '# N\n' >"$NRP/CLAUDE.md"
if git -C "$SB" rev-parse --git-dir >/dev/null 2>&1; then echo "  SKIP sandbox sits inside a git repository (M09)"; else
  M09="$(mutant_cli m09 '        if not in_repo:' '        if False:')"
  run "$C" --project-root "$NRP" --non-interactive --set calibration.floor=0.95; check "M09: not in a repo: refused rc 3" test "$RC" = 3
  run "$M09" --project-root "$NRP" --non-interactive --set calibration.floor=0.95; check "mutant M09 is caught: accepted" test "$RC" = 0
fi
OUT="$SB/outer"; mkdir -p "$OUT/sub/proj/submodules/constitution"; git -C "$OUT" init -q 2>/dev/null; printf '# O\n' >"$OUT/sub/proj/CLAUDE.md"
run "$C" --project-root "$OUT/sub/proj" --non-interactive --set calibration.floor=0.95; check "M23: ancestor repository accepted rc 0" test "$RC" = 0
M23="$(mutant_cli m23 '            nd = os.path.dirname(d)
            if nd == d:
                break
            d = nd' '            break')"
check "mutant M23 built" test -n "$M23"
rm -rf "$OUT/sub/proj/.constitution"; sed -i '$d' "$OUT/sub/proj/CLAUDE.md" 2>/dev/null; printf '# O\n' >"$OUT/sub/proj/CLAUDE.md"
run "$M23" --project-root "$OUT/sub/proj" --non-interactive --set calibration.floor=0.96; check "mutant M23 is caught: the ancestor repository is not seen (rc 3)" test "$RC" = 3
WT="$SB/wt8"; mkdir -p "$WT/submodules/constitution" "$WT/nested"; printf 'gitdir: /nonexistent/x\n' >"$WT/.git"; printf 'gitdir: ../x\n' >"$WT/nested/.git"; printf '# W\n' >"$WT/CLAUDE.md"
run "$C" --project-root "$WT" --non-interactive --set calibration.floor=0.95; check "M21: root whose .git is a FILE accepted" test "$RC" = 0
run "$C" --project-root "$WT" --non-interactive --doc nested/x.md --set calibration.floor=0.96; check "M21: nested dir whose .git is a FILE is foreign (rc 3)" test "$RC" = 3
M21a="$(mutant_cli m21a '            if os.path.lexists(os.path.join(d, ".git")):  # a directory, or a FILE (worktree / submodule checkout)' '            if os.path.isdir(os.path.join(d, ".git")):')"
M21b="$(mutant_cli m21b '            if os.path.lexists(os.path.join(d, ".git")):
                return True' '            if os.path.isdir(os.path.join(d, ".git")):
                return True')"
check "mutants M21a M21b built" test -n "$M21a" -a -n "$M21b"
rm -rf "$WT/.constitution"
run "$M21a" --project-root "$WT" --non-interactive --set calibration.floor=0.95; check "mutant M21a is caught: root with .git FILE refused" test "$RC" = 3
run "$M21b" --project-root "$WT" --non-interactive --doc nested/x.md --set calibration.floor=0.97; check "mutant M21b is caught: nested .git FILE not foreign" test "$RC" = 0
# M18: the printed user-backup path with a long segment is shown in full (safe_text, not redact)
LONG="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1bbbbbbbbbbbbbbbbbbbbbbbb"; PL="$SB/$LONG/proj"; mkdir -p "$PL/submodules/constitution"; git -C "$PL" init -q 2>/dev/null; printf '# P\n' >"$PL/CLAUDE.md"
export CONSTITUTION_DECISIONS_USER_FILE="$SB/$LONG/uc/d.yml"
run "$C" --project-root "$PL" --scope user --non-interactive --set calibration.floor=0.95; run "$C" --project-root "$PL" --scope user --non-interactive --set calibration.floor=0.96
check "M18: the backup path with a long segment is printed in full" grep -qF -- "$LONG" "$SB/o"
M18="$(mutant_cli m18 'emit_out("backup (user decisions file): %s" % safe_text(backup_user(ufile, proj)))' 'emit_out("backup (user decisions file): %s" % redact(backup_user(ufile, proj)))')"
run "$M18" --project-root "$PL" --scope user --non-interactive --set calibration.floor=0.97
check "mutant M18 is caught: the path is redacted" bash -c "! grep -qF -- '$LONG' '$SB/o' && grep -q 'redacted' '$SB/o'"
# 0700 bases
export CONSTITUTION_DECISIONS_USER_FILE="$SB/ub/d.yml"; mkdir -p "$SB/ub/.decisions-backup"; chmod 0755 "$SB/ub/.decisions-backup"; PB="$(newproj bb)"
mkdir -m 0755 "$PB/.constitution-install-backup"
run "$C" --project-root "$PB" --scope user --non-interactive --set calibration.floor=0.95; run "$C" --project-root "$PB" --scope user --non-interactive --set calibration.floor=0.96
run "$C" --project-root "$PB" --non-interactive --set calibration.floor=0.95; run "$C" --project-root "$PB" --non-interactive --set calibration.floor=0.96
check "user backup base tightened to 0700" test "$(stat -c %a "$SB/ub/.decisions-backup")" = 700
check "project backup base tightened to 0700" test "$(stat -c %a "$PB/.constitution-install-backup")" = 700
MT="$(mutant_cli mt '        os.fchmod(fd, 0o700)' '        pass')"
check "mutant (no tighten) built" test -n "$MT"
chmod 0755 "$PB/.constitution-install-backup"; run "$MT" --project-root "$PB" --non-interactive --set calibration.floor=0.97
check "mutant is caught: base stays 0755" test "$(stat -c %a "$PB/.constitution-install-backup")" = 755
finish test_round10
