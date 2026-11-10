#!/usr/bin/env bash
# tests/test_run_full_suite_go.sh -- Go units of scripts/run_full_suite.sh: when is a failed Go unit an
# environment SKIP (network_unreachable_external) and when is it a FAIL of the repository?
#
# Oracle strategy: SPECIFIED + DERIVED. The specification is the runner guide section "Go units offline":
# a Go unit always runs; a FAILED run is SKIP only when the unit's OWN `go test` output says that Go had to
# reach the network (`module lookup disabled by GOPROXY=off`) and nothing else failed. The derived oracle is
# Go itself, measured on Go 1.26.8 (scratchpad lab, 2026-11-06): under GOFLAGS=-mod=readonly a go.sum gap
# prints `missing go.sum entry` (even with an empty cache), while a module that is not in the cache prints
# `module lookup disabled`; in workspace mode a missing checksum prints `lookup disabled` because only the
# checksum database (network) can supply it. Each case below pins one axis with a real module graph served
# by a private file:// proxy (no network), a private GOMODCACHE, and the real runner. Every case also checks
# that the run wrote nothing into the repository under test.
#
# Cases are named A<n>; tests/test_run_full_suite_go_mutations.sh runs this file against mutated copies of
# the engine (one mutant per axis). FSR_RUNNER selects the runner; FSR_GO_CASES=A1,A5 selects cases.
# Every failing check prints a line that starts with `FAIL `. Exit 77 (reason topology_unsupported) when
# `go` is not installed.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R=${FSR_RUNNER:-$HERE/scripts/run_full_suite.sh}
ENGINE="$(cd "$(dirname "$R")" && pwd)/full_suite/run_full_suite.py"
if ! command -v go >/dev/null 2>&1; then
  echo "SUMMARY pass=0 fail=0 skip=1 (skipped: all, go not installed) reason=topology_unsupported"; exit 77
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/rfs_go.XXXXXX") || exit 2
: "${T:?}"
export FULL_SUITE_TMPDIR="$T"
. "$HERE/scripts/lib/safe_rm.sh" || exit 2
cleanup() { chmod -R u+w "${T:?}" 2>/dev/null; TMPDIR="$(dirname "$T")" safe_rm_rf "${T:?}" >/dev/null 2>&1; }
trap cleanup EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "ok   $1"; }
ko(){ fail=$((fail+1)); echo "FAIL $1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (want '$3' got '$2')"; fi; }
has(){ if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else ko "$1 (no /$2/ in $3)"; fi; }
hasnt(){ if grep -qE -- "$2" "$3" 2>/dev/null; then ko "$1 (unexpected /$2/ in $3)"; else ok "$1"; fi; }
want(){ [ -z "${FSR_GO_CASES:-}" ] || [[ ",$FSR_GO_CASES," == *",$1,"* ]]; }
gitc(){ git -C "$1" -c user.email=a@b -c user.name=t "${@:2}"; }
gen(){ bash "$R" --root "$1" --generate-manifest --write >/dev/null 2>&1; }
run(){ # $1 root $2 out, rest: runner args -> RC, log in $2.log
  local r=$1 o=$2; shift 2
  bash "$R" --root "$r" --out "$o" --include-heavy --timeout 300 "$@" >"$o.log" 2>&1; RC=$?
}
verdict(){ # $1 out $2 unit path -> verdict|reason|source of the unit's last record
  python3 -I -c 'import json,sys
v=""
for l in open(sys.argv[1]+"/results.jsonl"):
    o=json.loads(l)
    if o.get("path")==sys.argv[2]: v="%s|%s|%s" % (o["verdict"],o["reason"],o["verdict_source"])
print(v)' "$1" "$2" 2>/dev/null
}
v1(){ verdict "$1" "$2" | cut -d'|' -f1; }
clean(){ git -C "$1" status --porcelain --untracked-files=all | tr '\n' ' '; }

# ------------------------------------------------------------------ private module proxy (no network)
export GOTOOLCHAIN=local GOTELEMETRY=off GOCACHE="$T/gocache"
PX="$T/proxy"; GP="file://$PX"
mkmod(){ # $1 module $2 version, rest: name=content (\n decoded); go.mod defaults to `module $1 / go 1.21`
  python3 -I - "$PX" "$@" <<'PY'
import sys, zipfile, os, json
d, mod, ver = sys.argv[1], sys.argv[2], sys.argv[3]
files = {k: v.replace("\\n", "\n") for k, v in (a.split("=", 1) for a in sys.argv[4:])}
files.setdefault("go.mod", "module %s\n\ngo 1.21\n" % mod)
esc = "".join("!" + c.lower() if "A" <= c <= "Z" else c for c in mod)
vd = os.path.join(d, *esc.split("/"), "@v"); os.makedirs(vd, exist_ok=True)
lst = os.path.join(vd, "list"); old = open(lst).read().split() if os.path.exists(lst) else []
open(lst, "w").write("\n".join(sorted(set(old + [ver]))) + "\n")
open(os.path.join(vd, ver + ".info"), "w").write(json.dumps({"Version": ver, "Time": "2020-01-01T00:00:00Z"}) + "\n")
open(os.path.join(vd, ver + ".mod"), "w").write(files["go.mod"])
with zipfile.ZipFile(os.path.join(vd, ver + ".zip"), "w") as z:
    for n, c in sorted(files.items()):
        z.writestr("%s@%s/%s" % (mod, ver, n), c)
PY
}
mkmod example.com/dep v1.0.0 'dep.go=package dep\nfunc F() int { return 1 }\n'
mkmod example.com/winonly v1.0.0 'w.go=package winonly\nfunc W() int { return 2 }\n'
mkmod example.com/rep2 v1.0.0 'r.go=package rep\nfunc R() int { return 5 }\n'
mkmod example.com/Dep2 v1.0.0 'd.go=package dep2\nfunc G() int { return 2 }\n'
mkmod example.com/other v1.0.0 'o.go=package other\nfunc O() int { return 6 }\n'
mkmod example.com/testonly v1.0.0 't.go=package testonly\nfunc T() int { return 3 }\n'
mkmod example.com/dep v1.0.1 'go.mod=module example.com/dep\n\ngo 1.21\n\nretract v1.0.0\n' 'dep.go=package dep\nfunc F() int { return 1 }\n'
CEMPTY="$T/c_empty"; CFULL="$T/c_full"; mkdir -p "$CEMPTY" "$CFULL" "$T/fx"
printf 'module x\n\ngo 1.21\n' > "$T/fx/go.mod"
( cd "$T/fx" && GOPROXY="$GP" GOSUMDB=off GOFLAGS=-modcacherw GOMODCACHE="$CFULL" go mod download \
    example.com/dep@v1.0.0 example.com/dep@v1.0.1 example.com/winonly@v1.0.0 example.com/rep2@v1.0.0 \
    example.com/Dep2@v1.0.0 example.com/other@v1.0.0 example.com/testonly@v1.0.0 ) > "$T/fill.log" 2>&1
chk "fixture: the full private cache holds dep (control needle)" \
  "$(test -f "$CFULL/cache/download/example.com/dep/@v/v1.0.0.zip" && echo yes)" "yes"
chk "fixture: the full private cache holds the case-escaped Dep2 (control needle)" \
  "$(test -f "$CFULL/cache/download/example.com/!dep2/@v/v1.0.0.zip" && echo yes)" "yes"
chk "fixture: the empty cache is empty (negative control)" "$(find "$CEMPTY" -mindepth 1 | wc -l | tr -d ' ')" "0"
tidy(){ ( cd "$1" && GOPROXY="$GP" GOSUMDB=off GOFLAGS=-modcacherw GOMODCACHE="$T/c_tidy" go mod tidy ) >> "$T/tidy.log" 2>&1; }
newroot(){ # $1 dir: empty git repo, one commit
  mkdir -p "$1"; git init -q "$1" && gitc "$1" commit -q --allow-empty -m init
}
commit_all(){ gen "$1"; gitc "$1" add -A && gitc "$1" commit -q -m unit; }
# mod <dir> <go.mod body (printf %b)> ; files are written by the caller
mod(){ mkdir -p "$1"; printf '%b' "$2" > "$1/go.mod"; }
one_dep(){ # $1 module dir $2 import path $3 call $4 expected value: package m imports $2 and tests $3 == $4
  printf 'package m\nimport "%s"\nfunc Add() int { return %s }\n' "$2" "$3" > "$1/m.go"
  printf 'package m\nimport "testing"\nfunc TestA(t *testing.T) { if Add() != %s { t.Fatal("x") } }\n' "$4" > "$1/m_test.go"
}

# ================================================================== P: the classifier (pure function)
python3 -I - "$ENGINE" > "$T/p.log" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fsr", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
POL = {"GOPROXY": "off", "GOFLAGS": "-mod=readonly"}
lk = "m.go:2:8: module lookup disabled by GOPROXY=off"
dl = "go: downloading example.com/dep v1.0.0"
setup = "FAIL\texample.com/m [setup failed]"
base = "\n".join([dl, "# example.com/m", lk, setup, "FAIL"]) + "\n"
ws = "\n".join(["# example.com/m", "m.go:2:8: example.com/dep@v1.0.0: module lookup disabled by GOPROXY=off", setup, "FAIL"])
graph = "go: example.com/other@v1.0.0: module lookup disabled by GOPROXY=off\n"
rows = [
    # name, rc, text, complete, env, vendor, want (None = not reclassified, else the named list)
    ("P1 module-mode shape", 1, base, True, POL, False, ["example.com/dep@v1.0.0"]),
    ("P2 workspace shape names mod@ver", 1, ws, True, POL, False, ["example.com/dep@v1.0.0"]),
    ("P3 graph-level abort line", 1, graph, True, POL, False, ["example.com/other@v1.0.0"]),
    ("P4 rc 0 is never reclassified", 0, base, True, POL, False, None),
    ("P5 rc 2 is never reclassified", 2, base, True, POL, False, None),
    ("P6 a real test failure beside it", 1, base + "--- FAIL: TestB (0.00s)\nFAIL\texample.com/m/b\t0.003s\n", True, POL, False, None),
    ("P7 a compile error beside it", 1, base + "# example.com/m/b [example.com/m/b.test]\nb/b.go:2:23: undefined: x\nFAIL\texample.com/m/b [build failed]\n", True, POL, False, None),
    ("P8 go.sum gap (missing go.sum entry)", 1, "# example.com/m\nm.go:2:8: missing go.sum entry for module providing package example.com/dep (imported by example.com/m); to add:\n\tgo get example.com/m\n" + setup + "\nFAIL\n", True, POL, False, None),
    ("P9 a passing package beside it is allowed", 1, base + "ok  \texample.com/m/b\t0.003s\n?   \texample.com/m/c\t[no test files]\n", True, POL, False, ["example.com/dep@v1.0.0"]),
    ("P10 no lookup line at all", 1, "# example.com/m\n" + setup + "\nFAIL\n", True, POL, False, None),
    ("P11 output not complete (log cut)", 1, base, False, POL, False, None),
    ("P12 GOPROXY not off", 1, base, True, {"GOPROXY": "direct", "GOFLAGS": "-mod=readonly"}, False, None),
    ("P13 GOFLAGS not -mod=readonly", 1, base, True, {"GOPROXY": "off", "GOFLAGS": "-mod=mod"}, False, None),
    ("P14 vendor/modules.txt present", 1, base, True, POL, True, None),
    ("P15 an unknown line (fail closed)", 1, base + "go: warning: something new\n", True, POL, False, None),
    ("P16 lookup line but no failing package or abort", 1, lk + "\nok  \texample.com/m\t0.1s\n", True, POL, False, None),
    ("P17 empty output", 1, "", True, POL, False, None),
    ("P18 panic beside it", 1, base + "panic: boom\n", True, POL, False, None),
    ("P19 lookup text inside a longer line (not the shape)", 1, "# example.com/m\nm.go:2:8: x: module lookup disabled by GOPROXY=off; also y\n" + setup + "\nFAIL\n", True, POL, False, None),
    ("P20 unnamed module (no downloading line)", 1, "\n".join(["# example.com/m", lk, setup, "FAIL"]), True, POL, False, []),
]
bad = 0
for name, rc, text, complete, env, vendor, want in rows:
    got = m.go_test_needs_network(rc, text, complete, env, vendor)
    if got != want:
        bad += 1; print("FAIL %s: want %r got %r" % (name, want, got))
    else:
        print("ok   %s" % name)
sys.exit(1 if bad else 0)
PY
prc=$?; cat "$T/p.log"; chk "P classifier table" "$prc" "0"

# ================================================================== A: real module graphs through the runner
# A1 (review G5): a dependency imported only by a //go:build windows file, cache filled by `go test` on this
# OS: the unit is runnable, so its verdict is exactly what `go test` says (PASS, or the real FAIL).
if want A1; then
  for var in pass fail; do
    D="$T/a1$var"; newroot "$D"
    mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire (\n\texample.com/dep v1.0.0\n\texample.com/winonly v1.0.0\n)\n'
    want_v=1; [ $var = fail ] && want_v=7
    one_dep "$D/m" example.com/dep 'dep.F()' "$want_v"
    printf '//go:build windows\n\npackage m\nimport "example.com/winonly"\nfunc Win() int { return winonly.W() }\n' > "$D/m/m_windows.go"
    tidy "$D/m"; commit_all "$D"
    C="$T/c_a1$var"; mkdir -p "$C"
    ( cd "$D/m" && GOPROXY="$GP" GOSUMDB=off GOFLAGS="-modcacherw -mod=readonly" GOMODCACHE="$C" go test -count=1 ./... ) > /dev/null 2>&1
    chk "A1$var fixture: winonly is NOT in the cache (control)" "$(test -e "$C/cache/download/example.com/winonly/@v/v1.0.0.zip" && echo yes || echo no)" "no"
    chk "A1$var fixture: dep IS in the cache (needle)" "$(test -f "$C/cache/download/example.com/dep/@v/v1.0.0.zip" && echo yes)" "yes"
    GOMODCACHE="$C" run "$D" "$T/o_a1$var"
    exp=PASS; [ $var = fail ] && exp=FAIL
    chk "A1$var windows-only dependency uncached: verdict is go test's own ($exp)" "$(v1 "$T/o_a1$var" m)" "$exp"
    chk "A1$var tree clean" "$(clean "$D")" ""
  done
  # A1t: host GOFLAGS=-tags=windows passed through is overridden by the runner's -mod=readonly (still PASS)
  GOFLAGS=-tags=windows GOMODCACHE="$T/c_a1pass" run "$T/a1pass" "$T/o_a1t" --env-extra GOFLAGS
  chk "A1t host GOFLAGS (-tags=windows) does not reach the unit: PASS" "$(v1 "$T/o_a1t" m)" "PASS"
fi

# A2 (review G7b): replace target cached, no go.sum: Go names the ORIGINAL path and says `missing go.sum
# entry` -> FAIL (a repository defect). A2c: with a complete go.sum and the replacement cached -> PASS.
# A2e: complete go.sum, replacement NOT cached -> SKIP.
if want A2; then
  D="$T/a2"; newroot "$D"
  mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/rep v1.0.0\n\nreplace example.com/rep => example.com/rep2 v1.0.0\n'
  one_dep "$D/m" example.com/rep 'rep.R()' 5; commit_all "$D"
  chk "A2 fixture: rep2 zip cached (needle)" "$(test -f "$CFULL/cache/download/example.com/rep2/@v/v1.0.0.zip" && echo yes)" "yes"
  chk "A2 fixture: no go.sum (control)" "$(test -e "$D/m/go.sum" && echo yes || echo no)" "no"
  GOMODCACHE="$CFULL" run "$D" "$T/o_a2"
  chk "A2 replacement cached + go.sum gap -> FAIL" "$(v1 "$T/o_a2" m)" "FAIL"
  chk "A2 tree clean" "$(clean "$D")" ""
  D="$T/a2c"; newroot "$D"
  mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/rep v1.0.0\n\nreplace example.com/rep => example.com/rep2 v1.0.0\n'
  one_dep "$D/m" example.com/rep 'rep.R()' 5; tidy "$D/m"; commit_all "$D"
  GOMODCACHE="$CFULL" run "$D" "$T/o_a2c"
  chk "A2c replacement cached + complete go.sum -> PASS" "$(v1 "$T/o_a2c" m)" "PASS"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a2e"
  chk "A2e replacement not cached + complete go.sum -> SKIP" "$(verdict "$T/o_a2e" m)" "SKIP|network_unreachable_external|go-test-output"
  has "A2e names the module Go tried to fetch" 'go_test_needs_network: example.com/rep2@v1.0.0' "$T/o_a2e.log"
  chk "A2e a SKIP is never a green run (exit 6)" "$RC" "6"
  chk "A2e tree clean" "$(clean "$D")" ""
fi

# A3 (review I4-1 / RV-G1, and the old 22b fixture): a dependency with NO go.sum is a repository defect
# whether or not it is cached (`missing go.sum entry`): FAIL, never a cache SKIP.
if want A3; then
  D="$T/a3"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
  one_dep "$D/m" example.com/dep 'dep.F()' 1; commit_all "$D"
  GOMODCACHE="$CFULL" run "$D" "$T/o_a3c"
  chk "A3 cached dependency, no go.sum -> FAIL" "$(v1 "$T/o_a3c" m)" "FAIL"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a3e"
  chk "A3 uncached dependency, no go.sum -> FAIL (go test reports the go.sum gap first)" "$(v1 "$T/o_a3e" m)" "FAIL"
  hasnt "A3 no needs-network line for a go.sum gap" 'go_test_needs_network' "$T/o_a3e.log"
  GOSUMDB=off GOMODCACHE="$CFULL" run "$D" "$T/o_a3s" --env-extra GOSUMDB
  chk "A3s GOSUMDB=off passed through: still FAIL" "$(v1 "$T/o_a3s" m)" "FAIL"
  GONOSUMDB=example.com GOMODCACHE="$CEMPTY" run "$D" "$T/o_a3n" --env-extra GONOSUMDB
  chk "A3n GONOSUMDB passed through: still FAIL" "$(v1 "$T/o_a3n" m)" "FAIL"
  chk "A3 tree clean after all runs" "$(clean "$D")" ""
fi

# A4: a go.sum with only one of the two lines. /go.mod line only -> `missing go.sum entry` -> FAIL (cached
# or not). Zip line only, cache empty -> Go first needs the .mod from the network: SKIP (the go.sum gap
# behind it is not visible offline; see the guide's honest limit).
if want A4; then
  for v in modline zipline; do
    D="$T/a4$v"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
    one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"
    if [ $v = modline ]; then grep '/go.mod ' "$D/m/go.sum" > "$D/m/s"; else grep -v '/go.mod ' "$D/m/go.sum" > "$D/m/s"; fi
    mv "$D/m/s" "$D/m/go.sum"; commit_all "$D"
    GOMODCACHE="$CFULL" run "$D" "$T/o_a4${v}c"; chk "A4 $v only, cached -> FAIL" "$(v1 "$T/o_a4${v}c" m)" "FAIL"
    GOMODCACHE="$CEMPTY" run "$D" "$T/o_a4${v}e"
    exp=FAIL; [ $v = zipline ] && exp=SKIP
    chk "A4 $v only, not cached -> $exp" "$(v1 "$T/o_a4${v}e" m)" "$exp"
    chk "A4 $v tree clean" "$(clean "$D")" ""
  done
fi

# A5: a dependency with a complete go.sum that is not cached -> SKIP naming it; the case-escaped path
# (example.com/Dep2) behaves the same, and is PASS once cached.
if want A5; then
  for p in dep Dep2; do
    D="$T/a5$p"; newroot "$D"; mod "$D/m" "module example.com/m\n\ngo 1.21\n\nrequire example.com/$p v1.0.0\n"
    if [ $p = dep ]; then one_dep "$D/m" example.com/dep 'dep.F()' 1; else one_dep "$D/m" example.com/Dep2 'dep2.G()' 2; fi
    tidy "$D/m"; commit_all "$D"
    GOMODCACHE="$CEMPTY" run "$D" "$T/o_a5$p"
    chk "A5 $p not cached, complete go.sum -> SKIP" "$(verdict "$T/o_a5$p" m)" "SKIP|network_unreachable_external|go-test-output"
    has "A5 $p is named" "go_test_needs_network: example.com/$p@v1.0.0" "$T/o_a5$p.log"
    GOMODCACHE="$CFULL" run "$D" "$T/o_a5${p}c"; chk "A5 $p cached -> PASS" "$(v1 "$T/o_a5${p}c" m)" "PASS"
    chk "A5 $p tree clean" "$(clean "$D")" ""
  done
  # A5x: a host GOPROXY=file:// that HAS the module does not reach the unit (GOPROXY=off is runner policy)
  GOPROXY="$GP" GOMODCACHE="$CEMPTY" run "$T/a5dep" "$T/o_a5x" --env-extra GOPROXY
  chk "A5x host GOPROXY=file:// is overridden: still SKIP" "$(v1 "$T/o_a5x" m)" "SKIP"
  # Go leaves lock files and directories behind on a failed lookup; no module CONTENT may arrive.
  chk "A5x no module content reached the private cache" \
    "$(find "$CEMPTY" -type f \( -name '*.zip' -o -name '*.mod' -o -name '*.info' \) | wc -l | tr -d ' ')" "0"
fi

# A6: two packages, one needs an uncached module, the other fails a real test / does not compile / passes.
# A real failure is never hidden: FAIL. Only the all-environment case is SKIP.
if want A6; then
  for v in testfail compilefail passes; do
    D="$T/a6$v"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/other v1.0.0\n'
    mkdir -p "$D/m/a" "$D/m/b"
    printf 'package a\nimport "example.com/other"\nfunc A() int { return other.O() }\n' > "$D/m/a/a.go"
    printf 'package a\nimport "testing"\nfunc TestA(t *testing.T) { _ = A() }\n' > "$D/m/a/a_test.go"
    case $v in
      testfail) printf 'package b\nfunc B() int { return 1 }\n' > "$D/m/b/b.go"
        printf 'package b\nimport "testing"\nfunc TestB(t *testing.T) { if B() != 2 { t.Fatal("real") } }\n' > "$D/m/b/b_test.go";;
      compilefail) printf 'package b\nfunc B() int { return undefinedX }\n' > "$D/m/b/b.go"
        printf 'package b\nimport "testing"\nfunc TestB(t *testing.T) { _ = B() }\n' > "$D/m/b/b_test.go";;
      passes) printf 'package b\nfunc B() int { return 1 }\n' > "$D/m/b/b.go"
        printf 'package b\nimport "testing"\nfunc TestB(t *testing.T) { if B() != 1 { t.Fatal("x") } }\n' > "$D/m/b/b_test.go";;
    esac
    tidy "$D/m"; commit_all "$D"
    GOMODCACHE="$CEMPTY" run "$D" "$T/o_a6$v"
    exp=FAIL; [ $v = passes ] && exp=SKIP
    chk "A6 $v beside an uncached module -> $exp" "$(v1 "$T/o_a6$v" m)" "$exp"
    chk "A6 $v tree clean" "$(clean "$D")" ""
  done
fi

# A7 (review G9): workspace mode (go.work at the root). Complete go.sum, module not cached -> SKIP.
# No go.sum, module cached: Go needs the checksum database (network) and offline says `lookup disabled`;
# with network the unit passes (measured), so it is an environment SKIP, never a FAIL. The unit writes
# nothing (no go.work.sum) in either case.
if want A7; then
  for v in gosum nogosum; do
    D="$T/a7$v"; newroot "$D"; printf 'go 1.21\n\nuse ./m\n' > "$D/go.work"
    mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
    one_dep "$D/m" example.com/dep 'dep.F()' 1
    [ $v = gosum ] && tidy "$D/m"
    commit_all "$D"
    C="$CEMPTY"; [ $v = nogosum ] && C="$CFULL"
    GOMODCACHE="$C" run "$D" "$T/o_a7$v"
    chk "A7 workspace $v -> SKIP" "$(verdict "$T/o_a7$v" m)" "SKIP|network_unreachable_external|go-test-output"
    has "A7 workspace $v names the module" 'go_test_needs_network: example.com/dep@v1.0.0' "$T/o_a7$v.log"
    chk "A7 workspace $v tree clean (no go.work.sum written)" "$(clean "$D")" ""
  done
  GOMODCACHE="$CFULL" run "$T/a7gosum" "$T/o_a7c"
  chk "A7c workspace, complete go.sum, cached -> PASS" "$(v1 "$T/o_a7c" m)" "PASS"
fi

# A8: vendor/ present: the runner forces -mod=readonly, so Go does not use vendor/; the module is present
# in the repository, so this is NOT reclassified (FAIL, as before this change) and the log says why.
if want A8; then
  D="$T/a8"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
  one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"
  ( cd "$D/m" && GOPROXY="$GP" GOSUMDB=off GOFLAGS=-modcacherw GOMODCACHE="$T/c_tidy" go mod vendor ) >> "$T/tidy.log" 2>&1
  chk "A8 fixture: vendor/modules.txt exists" "$(test -f "$D/m/vendor/modules.txt" && echo yes)" "yes"
  commit_all "$D"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a8"
  chk "A8 vendored module, cache empty -> FAIL (not reclassified)" "$(v1 "$T/o_a8" m)" "FAIL"
  has "A8 the log names the vendor reason" 'vendor/modules.txt present' "$T/o_a8.log"
  chk "A8 tree clean" "$(clean "$D")" ""
fi

# A9: toolchain / go lines. `go 1.99` cannot run on a local older toolchain: not a network error, FAIL as
# before (not reclassified). A `toolchain go1.99.0` line alone does not stop the unit: PASS.
if want A9; then
  for v in goline toolchain; do
    D="$T/a9$v"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
    one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"
    if [ $v = goline ]; then sed -i 's/^go 1.21$/go 1.99/' "$D/m/go.mod"; else printf '\ntoolchain go1.99.0\n' >> "$D/m/go.mod"; fi
    commit_all "$D"
    GOMODCACHE="$CFULL" run "$D" "$T/o_a9$v"
    exp=FAIL; [ $v = toolchain ] && exp=PASS
    chk "A9 $v -> $exp" "$(v1 "$T/o_a9$v" m)" "$exp"
  done
fi

# A10: retract. The unit requires dep v1.0.0, which v1.0.1 retracts; go test does not consult retractions:
# PASS from the cache (the retraction does not make the unit an environment case).
if want A10; then
  D="$T/a10"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
  one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"; commit_all "$D"
  GOMODCACHE="$CFULL" run "$D" "$T/o_a10"; chk "A10 retracted version required, cached -> PASS" "$(v1 "$T/o_a10" m)" "PASS"
fi

# A11: multi-module. A nested module inside the unit directory is not part of `./...`: its uncached
# dependency does not touch the unit (PASS). A test-only import (in _test.go) is part of the unit's graph:
# uncached -> SKIP.
if want A11; then
  D="$T/a11"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
  one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"
  mkdir -p "$D/m/sub"; printf 'module example.com/sub\n\ngo 1.21\n\nrequire example.com/other v1.0.0\n' > "$D/m/sub/go.mod"
  printf 'package sub\nimport "example.com/other"\nvar X = other.O()\n' > "$D/m/sub/s.go"; commit_all "$D"
  C="$T/c_a11"; mkdir -p "$C"
  ( cd "$D/m" && GOPROXY="$GP" GOSUMDB=off GOFLAGS="-modcacherw -mod=readonly" GOMODCACHE="$C" go test -count=1 . ) > /dev/null 2>&1
  chk "A11 fixture: other is NOT in the cache (control)" "$(test -e "$C/cache/download/example.com/other/@v/v1.0.0.zip" && echo yes || echo no)" "no"
  GOMODCACHE="$C" run "$D" "$T/o_a11"; chk "A11 nested module's uncached dependency -> unit PASS" "$(v1 "$T/o_a11" m)" "PASS"
  D="$T/a11t"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/testonly v1.0.0\n'
  printf 'package m\nfunc Add() int { return 3 }\n' > "$D/m/m.go"
  printf 'package m\nimport ("testing"; "example.com/testonly")\nfunc TestA(t *testing.T) { if Add() != testonly.T() { t.Fatal("x") } }\n' > "$D/m/m_test.go"
  tidy "$D/m"; commit_all "$D"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a11t"; chk "A11t test-only import uncached -> SKIP" "$(v1 "$T/o_a11t" m)" "SKIP"
  chk "A11 trees clean" "$(clean "$T/a11")$(clean "$D")" ""
fi

# A12: a malformed go.mod is a repository defect: FAIL, never reclassified (golden-FALSE).
if want A12; then
  D="$T/a12"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/x\n'
  printf 'package m\nimport "testing"\nfunc TestA(t *testing.T) {}\n' > "$D/m/m_test.go"; commit_all "$D"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a12"; chk "A12 malformed go.mod -> FAIL" "$(v1 "$T/o_a12" m)" "FAIL"
fi

# A13: more than 1 MiB of output from a REAL test failure in package a, plus package z whose dependency is not
# cached (reviewer fixture R14, round 3 G3-3). The kept tail (last 1 MiB) can then hold only z's grammar lines;
# the completeness check is what keeps the unit FAIL. Regression fixture; the paired mutant RG1 is a reasoned equivalent (see the mutations file, GM20).
if want A13; then
  D="$T/a13"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.9.9\n'
  mkdir -p "$D/m/a" "$D/m/z"
  printf 'package a\n\nfunc A() int { return 1 }\n' > "$D/m/a/a.go"
  printf 'package a\n\nimport (\n\t"strings"\n\t"testing"\n)\n\nfunc TestBig(t *testing.T) {\n\tl := strings.Repeat("x", 1000)\n\tfor i := 0; i < 1500; i++ {\n\t\tt.Log(l)\n\t}\n\tt.Fatal("real failure")\n}\n' > "$D/m/a/a_test.go"
  printf 'package z\n\nimport "example.com/dep"\n\nfunc Z() int { return dep.F() }\n' > "$D/m/z/z.go"
  printf 'package z\n\nimport "testing"\n\nfunc TestZ(t *testing.T) { _ = Z() }\n' > "$D/m/z/z_test.go"
  printf 'example.com/dep v1.9.9 h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nexample.com/dep v1.9.9/go.mod h1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "$D/m/go.sum"; commit_all "$D"
  GOMODCACHE="$CFULL" run "$D" "$T/o_a13"
  chk "A13 fixture: the unit log is over 1 MiB (control needle)" "$([ "$(wc -c < "$T/o_a13/logs/000000.log" 2>/dev/null || echo 0)" -gt 1048576 ] && echo yes)" "yes"
  chk "A13 big real failure + uncached dep in another package -> FAIL" "$(v1 "$T/o_a13" m)" "FAIL"
fi

# A14: a vendor/ directory WITHOUT vendor/modules.txt is not a vendored module (reviewer round 3 G3-3): the
# runner forces -mod=readonly, so the unit behaves as without vendor/ and an uncached dependency is SKIP.
# Pins GM21 (the guard widened to "a vendor/ directory exists").
if want A14; then
  D="$T/a14"; newroot "$D"; mod "$D/m" 'module example.com/m\n\ngo 1.21\n\nrequire example.com/dep v1.0.0\n'
  one_dep "$D/m" example.com/dep 'dep.F()' 1; tidy "$D/m"
  mkdir -p "$D/m/vendor"; : > "$D/m/vendor/.keep"
  chk "A14 fixture: vendor/ exists and vendor/modules.txt does not (control needle)" "$(test -d "$D/m/vendor" && ! test -e "$D/m/vendor/modules.txt" && echo yes)" "yes"
  commit_all "$D"
  GOMODCACHE="$CEMPTY" run "$D" "$T/o_a14"
  chk "A14 vendor/ without modules.txt, cache empty -> SKIP (module not vendored)" "$(verdict "$T/o_a14" m | cut -d'|' -f1,3)" "SKIP|go-test-output"
fi

echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
