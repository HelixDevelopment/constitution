#!/usr/bin/env bash
# CON-030 round 3 class reproduction (section 11.4.292): in-band keys / sentinels that a user-controlled path or
# name can collide with. $1 = checkout whose engine is judged, $2 = new fixture dir. Real git, real engine.
set -u
CO="${1:?checkout}"; F="${2:?fixture dir}"; [ ! -e "$F" ] || { echo "fixture dir exists"; exit 2; }
RUN="$CO/scripts/run_full_suite.sh"; ENGINE="$CO/scripts/full_suite/run_full_suite.py"
gitc(){ git -C "$1" -c user.email=a@b -c user.name=t "${@:2}"; }
mkdir -p "$F"; git init -q "$F/lib"; gitc "$F/lib" commit -q --allow-empty -m i
mk(){ mkdir -p "$1/tests/a" "$1/config"; git init -q "$1"; gitc "$1" commit -q --allow-empty -m init
      printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$1/tests/a/test_x.sh"; }
py(){ python3 -I - "$ENGINE" "$@"; }

echo "== 0: CON-030 itself: a clean checkout with a submodule path that holds a space (end to end)"
r="$F/spaced"; mk "$r"; git -C "$r" -c protocol.file.allow=always submodule add -q "$F/lib" "sub dir" >/dev/null 2>&1
bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1; gitc "$r" add -A; gitc "$r" commit -q -m s
bash "$RUN" --root "$r" --out "$F/o_spaced" --include-heavy > "$F/o_spaced.log" 2>&1; echo "  rc=$? $(grep -E '^(RESULT|TOPOLOGY)' "$F/o_spaced.log" | tr '\n' '|' | cut -c1-160)"

echo "== A: G3 submodule named 'status' with an unborn HEAD (end to end)"
for name in status other; do
  r="$F/g3_$name"; mk "$r"
  for p in plain "$name"; do git -C "$r" -c protocol.file.allow=always submodule add -q "$F/lib" "$p" >/dev/null 2>&1; done
  bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1; gitc "$r" add -A; gitc "$r" commit -q -m s
  gd=$(git -C "$r/$name" rev-parse --absolute-git-dir); printf 'ref: refs/heads/unborn\n' > "$gd/HEAD"
  git -C "$r/$name" rev-parse HEAD >/dev/null 2>&1 && echo "  precondition FAILED ($name)" || echo "  precondition ok ($name: rev-parse HEAD fails)"
  bash "$RUN" --root "$r" --out "$F/o_g3_$name" --include-heavy > "$F/o_g3_$name.log" 2>&1; echo "  $name: rc=$? $(grep -E '^RESULT' "$F/o_g3_$name.log" | cut -c1-60)"
done

echo "== B: a Go module in a directory whose name starts with '?' (the census used '?'+path as its 'no module' sentinel)"
r="$F/gomod"; mk "$r"; mkdir -p "$r/?mod" "$r/plainmod"
for d in "?mod" plainmod; do printf 'module example.com/m\n\ngo 1.21\n' > "$r/$d/go.mod"; printf 'package m\nimport "testing"\nfunc TestX(t *testing.T) {}\n' > "$r/$d/x_test.go"; done
gitc "$r" add -A; gitc "$r" commit -q -m go
bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1
echo "  go-test rows: $(awk -F'\t' '$5=="go-test"{printf "[%s] ", $1}' "$r/config/full_suite_manifest.tsv")"

echo "== C: tree_state records not framed (ignored symlink target can absorb a following record)"
r="$F/tree"; mk "$r"; printf 'a\nb\n' > "$r/.gitignore"; gitc "$r" add -A; gitc "$r" commit -q -m ig
py "$r" <<'PY'
import sys, os, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; a, b = os.path.join(root, "a"), os.path.join(root, "b")
os.symlink("x", a); os.symlink("y", b)            # state 2: ignored symlinks a -> x and b -> y
s2 = m.tree_state(root)
os.remove(a); os.remove(b); os.symlink("xIbLy", a)  # state 1: one ignored symlink a -> "xIbLy"
s1 = m.tree_state(root)
print("  two different ignored-file states hash equal (collision):", s1 == s2)
os.remove(a); os.symlink(b"t\xff", a.encode())       # an ignored symlink whose target is not UTF-8
try:
    m.tree_state(root); print("  non-UTF-8 symlink target: hashed")
except Exception as e:
    print("  non-UTF-8 symlink target: crash %s" % type(e).__name__)
PY

echo "== D: a test file under a directory whose name starts with '#' (the manifest's comment marker)"
r="$F/hash"; mk "$r"; mkdir -p "$r/#t"; printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$r/#t/test_h.sh"
gitc "$r" add -A; gitc "$r" commit -q -m h
bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1; gitc "$r" add -A; gitc "$r" commit -q -m m
bash "$RUN" --root "$r" --verify-manifest > "$F/hash_vfy.log" 2>&1; echo "  verify rc=$? $(tr '\n' '|' < "$F/hash_vfy.log" | cut -c1-260)"

echo "== E: a test file whose path contains a CR (the manifest is read with universal newlines)"
r="$F/cr"; mk "$r"; mkdir -p "$r/$(printf 'c\rd')"; printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$r/$(printf 'c\rd')/test_c.sh"
gitc "$r" add -A; gitc "$r" commit -q -m c
bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1; gitc "$r" add -A; gitc "$r" commit -q -m m
bash "$RUN" --root "$r" --verify-manifest > "$F/cr_vfy.log" 2>&1; echo "  verify rc=$? $(tr '\n\r' '|^' < "$F/cr_vfy.log" | cut -c1-260)"

echo "== F: G1 a submodule path that is not UTF-8"
r="$F/u8"; mk "$r"; git -C "$r" -c protocol.file.allow=always submodule add -q "$F/lib" "$(printf 'bad\377name')" >/dev/null 2>&1
bash "$RUN" --root "$r" --generate-manifest --write >/dev/null 2>&1; gitc "$r" add -A; gitc "$r" commit -q -m s
bash "$RUN" --root "$r" --out "$F/o_u8" --include-heavy > "$F/o_u8.log" 2>&1; echo "  rc=$? $(grep -E '^(RESULT|TOPOLOGY)' "$F/o_u8.log" | tr '\n' '|' | cut -c1-200)"

echo "== G: G2 newline submodule path whose fragments equal known paths (nlD)"
r="$F/nld"; mk "$r"; for p in a b; do git -C "$r" -c protocol.file.allow=always submodule add -q "$F/lib" "$p" >/dev/null 2>&1; done
lsha=$(git -C "$F/lib" rev-parse HEAD); nl=$(printf 'a\n %s b' "$lsha")
printf '[submodule "nl"]\n\tpath = "a\\n %s b"\n\turl = %s\n' "$lsha" "$F/lib" >> "$r/.gitmodules"
gitc "$r" update-index --add --cacheinfo "160000,$lsha,$nl"; gitc "$r" add .gitmodules; gitc "$r" commit -q -m nl
git -C "$r" submodule status --recursive | cat -A | sed 's/^/  status: /'
py "$r" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
t = m.topology(sys.argv[2]); print("  topology n=%d gaps=%r sub_paths=%r" % (t[1], t[2], m.sub_paths(sys.argv[2])))
PY

echo "== H: submodule_paths with a .gitmodules path value that holds a newline"
py "$F/nld" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print("  submodule_paths:", m.submodule_paths(sys.argv[2]))
PY

echo "== I: file_bytes of an absent file vs a file holding exactly the old '<absent>' marker"
r="$F/ctx"; mkdir -p "$r"
py "$r" <<'PY'
import sys, os, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; p = os.path.join(root, "k.tsv"); open(p, "wb").write(b"<absent>")
print("  equal (collision):", m.file_bytes(os.path.join(root, "nope")) == m.file_bytes(p))
PY

echo "== J: census of a test file whose name is not UTF-8"
r="$F/u8f"; mk "$r"; printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$r/tests/a/$(printf 'test_\377.sh')"
gitc "$r" add -A; gitc "$r" commit -q -m u
bash "$RUN" --root "$r" --generate-manifest --write > "$F/u8f_gen.log" 2>&1; echo "  generate rc=$?"
echo "  manifest rows under tests/a: $(grep -c '^tests/a/' "$r/config/full_suite_manifest.tsv" 2>/dev/null)"
bash "$RUN" --root "$r" --verify-manifest > "$F/u8f_vfy.log" 2>&1; echo "  verify rc=$? $(tr '\n' '|' < "$F/u8f_vfy.log" | cut -c1-240)"
