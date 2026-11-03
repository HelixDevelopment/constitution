#!/usr/bin/env bash
# tests/gates/test_gate_env_overrides_guarded.sh -- review round 8 finding F1 (11.4.276(E)(3), class: ambient env override turns a gate FAIL into PASS).
# REAL gates through their real CLI in a mktemp sandbox; no doubles. Cases:
#   RED reproduction: ORACLE_GUARD_BASELINE=<file with count 99> must NOT turn an over-baseline FAIL into PASS (rc stays 1, note printed);
#   the same override IS honoured under HELIX_TEST_MODE=1 + temp path (rc 0) and the verdict line then carries baseline=<that path> and overrides=ORACLE_GUARD_BASELINE;
#   a non-temp path is ignored even with HELIX_TEST_MODE=1; the default verdict line carries baseline=<real path> overrides=none;
#   exclude/ext/glob/allow overrides in the sibling scanners (dangerous-combination, killpg, mock-pid) are ignored unless HELIX_TEST_MODE=1;
#   paired mutation: gates with the guard removed (cm_gate_env_set -> raw ${VAR:-default}) let the override through -> this test FAILs.
#   RED: the guard-removed mutant reproduces F1 on the identical code (HEAD predates the ratchet gate, so it cannot show it).
set -uo pipefail
KP="kill""pg"   # call name assembled from fragments in the printf-written fixtures; line 191 keeps one literal call inside a GUARDED fixture (isinstance + pgid <= 1 check), which the gate accepts as guarded
export CONSTITUTION_JEV_HOOK=off
unset ORACLE_GUARD_STRICT ORACLE_GUARD_BASELINE ORACLE_GUARD_BASE ORACLE_GUARD_ROOT ORACLE_GUARD_EXCLUDE ORACLE_GUARD_GLOB \
      DANGEROUS_COMBO_EXCLUDE DANGEROUS_COMBO_EXT DANGEROUS_COMBO_MAX_DEPTH KILLPG_GUARD_EXCLUDE KILLPG_GUARD_EXT KILLPG_GUARD_ALLOW_PATHS \
      MOCK_PID_GUARD_EXCLUDE MOCK_PID_GUARD_GLOB HELIX_TEST_MODE CONSUMER_ROOT
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $1"; }; bad(){ fail=$((fail+1)); echo "FAIL $1"; }
chk(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)

# gate sandbox: gate + libs ; $2 = "mutant" removes the guard (raw env read)
mkgate() { # $1 dir $2 gate-basename $3 mutant?
    mkdir -p "$1/scripts/gates" "$1/scripts/lib"
    cp "$src/scripts/gates/$2.sh" "$1/scripts/gates/"
    cp "$src/scripts/lib/"*.sh "$1/scripts/lib/"
    if [ "${3:-}" = mutant ]; then
        # guard removed: cm_gate_env_set becomes a raw ${VAR:-default}
        rm -f "$1/scripts/lib/gate_env_override.sh"
        python3 - "$1/scripts/gates/$2.sh" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("else cm_gate_env_set() { printf -v \"$1\" '%s' \"$3\"; [ -z \"${!2:-}\" ] || echo \"gate_env_override: ignoring $2 (guard lib missing: fail closed)\" >&2; }; fi",
            "else cm_gate_env_set() { printf -v \"$1\" '%s' \"${!2:-$3}\"; }; fi")
open(p,'w').write(s)
PY
    fi
}
OR=cm_oracle_strategy_named_and_independent
mkgate "$sb/g_ok" $OR; mkgate "$sb/g_mut" $OR mutant

# fixture repo: one test file with 1 unannotated test, baseline says 0 -> over=1 -> FAIL
mkfix() { mkdir -p "$1/config"; printf 'def test_a():\n    assert 1\n' > "$1/test_x.py"; printf '# b\ntest_x.py\t0\n' > "$1/config/oracle_ratchet_baseline.txt"; }
mkfix "$sb/fx"; "${G[@]}" init -q "$sb/fx"; "${G[@]}" -C "$sb/fx" add -A >/dev/null; "${G[@]}" -C "$sb/fx" commit -qm c1
git -C "$sb/fx" update-ref refs/remotes/origin/main HEAD
printf 'test_x.py\t99\n' > "$sb/evil_baseline.txt"          # under the temp root (sb is a mktemp dir)

run() { env "$@" bash "$sb/g_ok/scripts/gates/$OR.sh" --root "$sb/fx" --quiet 2>&1; }
# 0 control: the fixture FAILs on its own (the instrument sees)
out="$(run X=1)"; rc=$?
[ "$rc" = 1 ] && grep -q $'^ORACLE-VERDICT\tFAIL\tmode=ratchet\tover=1' <<<"$out"; chk $? "control: fixture FAILs without any override (rc=$rc)"
grep -q $'\tbaseline='"$sb/fx/config/oracle_ratchet_baseline.txt"$'\toverrides=none\t' <<<"$out"; chk $? "default verdict prints baseline=<real path> overrides=none"
# (1) the F1 reproduction: ambient baseline WITHOUT test mode must not flip FAIL->PASS
out="$(run ORACLE_GUARD_BASELINE="$sb/evil_baseline.txt")"; rc=$?
[ "$rc" = 1 ] && grep -q 'ignoring ORACLE_GUARD_BASELINE' <<<"$out"; chk $? "F1: ORACLE_GUARD_BASELINE without HELIX_TEST_MODE is ignored with a note, FAIL stays (rc=$rc)"
# (2) honoured under test mode + temp path, and visible in the verdict
out="$(run HELIX_TEST_MODE=1 ORACLE_GUARD_BASELINE="$sb/evil_baseline.txt")"; rc=$?
[ "$rc" = 0 ] && grep -q $'\tbaseline='"$sb/evil_baseline.txt"$'\toverrides=ORACLE_GUARD_BASELINE\t' <<<"$out"; chk $? "honoured under HELIX_TEST_MODE=1 + temp path; verdict carries baseline= and overrides=ORACLE_GUARD_BASELINE (rc=$rc)"
# (3) non-temp path ignored even in test mode
out="$(run HELIX_TEST_MODE=1 ORACLE_GUARD_BASELINE="/etc/hostname")"; rc=$?
grep -q 'ignoring ORACLE_GUARD_BASELINE' <<<"$out" && [ "$rc" = 1 ]; chk $? "non-temp path ignored even with HELIX_TEST_MODE=1 (rc=$rc)"
# (4) exclude/glob overrides: pruning the offender must not turn FAIL into PASS without test mode
out="$(run ORACLE_GUARD_EXCLUDE="test_x.py .git")"; rc=$?
[ "$rc" = 1 ] && grep -q 'ignoring ORACLE_GUARD_EXCLUDE' <<<"$out"; chk $? "ORACLE_GUARD_EXCLUDE ignored without test mode (rc=$rc)"
out="$(run ORACLE_GUARD_GLOB='*nomatch*.py')"; rc=$?
[ "$rc" = 1 ] && grep -q 'ignoring ORACLE_GUARD_GLOB' <<<"$out"; chk $? "ORACLE_GUARD_GLOB ignored without test mode (rc=$rc)"
out="$(run HELIX_TEST_MODE=1 ORACLE_GUARD_GLOB='*nomatch*.py')"; rc=$?
[ "$rc" = 0 ] && grep -q $'SKIP' <<<"$out"; chk $? "ORACLE_GUARD_GLOB honoured under test mode (SKIP, rc=$rc)"
# (5) mutation: guard removed -> the F1 reproduction PASSes (the test above would FAIL)
out="$(env ORACLE_GUARD_BASELINE="$sb/evil_baseline.txt" bash "$sb/g_mut/scripts/gates/$OR.sh" --root "$sb/fx" --quiet 2>&1)"; rc=$?
[ "$rc" = 0 ] ; chk $? "MUTANT (guard removed): the ambient baseline flips FAIL->PASS (rc=$rc) -- proves the guard test is load-bearing"
# (6) RED note: HEAD still carries the pre-ratchet strict gate (no ORACLE_GUARD_BASELINE read at all); the F1 defect lives in the
#     uncommitted ratchet gate, so the RED proof is the guard-removed MUTANT above (identical code minus the guard).

# ---- sibling scanners ----
scan_fix() { mkdir -p "$1"; }
# dangerous-combination: a py file with a swallowed exception, then prune it by EXCLUDE / narrow by EXT / depth
DC=cm_dangerous_combination_fail_closed
mkgate "$sb/d_ok" $DC; mkgate "$sb/d_mut" $DC mutant
mkdir -p "$sb/dfx/pkg"; printf 'def f():\n    try:\n        x()\n    except Exception:\n        pass\n' > "$sb/dfx/pkg/bad.py"
d(){ local g="$1"; shift; env "$@" bash "$sb/$g/scripts/gates/$DC.sh" --root "$sb/dfx" --quiet 2>&1; }
out="$(d d_ok X=1)"; rc=$?; [ "$rc" != 0 ]; chk $? "control: dangerous-combination fixture FAILs (rc=$rc)"
out="$(d d_ok DANGEROUS_COMBO_EXCLUDE=pkg)"; rc=$?; [ "$rc" != 0 ] && grep -q 'ignoring DANGEROUS_COMBO_EXCLUDE' <<<"$out"; chk $? "DANGEROUS_COMBO_EXCLUDE ignored without test mode (rc=$rc)"
out="$(d d_ok DANGEROUS_COMBO_EXT=go)"; rc=$?; [ "$rc" != 0 ] && grep -q 'ignoring DANGEROUS_COMBO_EXT' <<<"$out"; chk $? "DANGEROUS_COMBO_EXT ignored without test mode (rc=$rc)"
out="$(d d_ok HELIX_TEST_MODE=1 DANGEROUS_COMBO_EXCLUDE=pkg)"; rc=$?; [ "$rc" = 0 ] && grep -q 'override(s) honoured: DANGEROUS_COMBO_EXCLUDE' <<<"$out"; chk $? "DANGEROUS_COMBO_EXCLUDE honoured under test mode and announced (rc=$rc)"
out="$(d d_mut DANGEROUS_COMBO_EXCLUDE=pkg)"; rc=$?; [ "$rc" = 0 ]; chk $? "MUTANT dangerous-combination: ambient exclude flips FAIL->PASS (rc=$rc)"

# killpg: a python killpg(1,...) w/o guard
KG=cm_killpg_pgid_guard
mkgate "$sb/k_ok" $KG; mkgate "$sb/k_mut" $KG mutant
mkdir -p "$sb/kfx"; printf 'import os\ndef f(p):\n    os.'"$KP"'(p.pid, 9)\n' > "$sb/kfx/bad.py"
k(){ local g="$1"; shift; env "$@" bash "$sb/$g/scripts/gates/$KG.sh" --root "$sb/kfx" --quiet 2>&1; }
out="$(k k_ok X=1)"; rc=$?; [ "$rc" != 0 ]; chk $? "control: killpg fixture FAILs (rc=$rc)"
out="$(k k_ok KILLPG_GUARD_EXCLUDE=kfx KILLPG_GUARD_EXT=go)"; rc=$?; [ "$rc" != 0 ] && grep -q 'ignoring KILLPG_GUARD_EXT' <<<"$out"; chk $? "KILLPG_GUARD_EXT/EXCLUDE ignored without test mode (rc=$rc)"
out="$(k k_ok HELIX_TEST_MODE=1 KILLPG_GUARD_EXT=go)"; rc=$?; [ "$rc" = 0 ]; chk $? "KILLPG_GUARD_EXT honoured under test mode (rc=$rc)"
out="$(k k_mut KILLPG_GUARD_EXT=go)"; rc=$?; [ "$rc" = 0 ]; chk $? "MUTANT killpg: ambient ext flips FAIL->PASS (rc=$rc)"

# mock-pid
MP=cm_test_mock_pid_explicit_int
mkgate "$sb/m_ok" $MP; mkgate "$sb/m_mut" $MP mutant
mkdir -p "$sb/mfx"; printf 'from unittest.mock import AsyncMock\nimport os\ndef test_a():\n    p = AsyncMock()\n    os.'"$KP"'(os.getpgid(p.pid), 9)\n' > "$sb/mfx/test_bad.py"
m(){ local g="$1"; shift; env "$@" bash "$sb/$g/scripts/gates/$MP.sh" --root "$sb/mfx" --quiet 2>&1; }
out="$(m m_ok X=1)"; rc=$?; [ "$rc" != 0 ]; chk $? "control: mock-pid fixture FAILs (rc=$rc)"
out="$(m m_ok MOCK_PID_GUARD_GLOB='*nomatch*.py')"; rc=$?; [ "$rc" != 0 ] && grep -q 'ignoring MOCK_PID_GUARD_GLOB' <<<"$out"; chk $? "MOCK_PID_GUARD_GLOB ignored without test mode (rc=$rc)"
out="$(m m_mut MOCK_PID_GUARD_GLOB='*nomatch*.py')"; rc=$?; [ "$rc" = 0 ]; chk $? "MUTANT mock-pid: ambient glob flips FAIL->PASS (rc=$rc)"


# ---- library unit cases (scripts/lib/gate_env_override.sh) and its three reviewer mutants ----
# Each case runs cm_gate_env_set from a given copy of the library in a subshell with a controlled temp root and
# prints the resulting value. The reviewer mutants of the library (L1 readlink -m dropped, L2 temp root "/" accepted,
# L3 any non-empty HELIX_TEST_MODE honoured) MUST each change at least one case.
TR="$sb/tr"; mkdir -p "$TR/sub" "$sb/outside"; ln -s /etc "$TR/etclink"; printf 'x\n' >"$sb/trusted_tool"
LIBSRC="$src/scripts/lib/gate_env_override.sh"
cp "$LIBSRC" "$sb/lib_ok.sh"
sed 's/readlink -m -- "\$__val"/printf "%s" "$__val"/' "$LIBSRC" >"$sb/lib_L1.sh"
sed 's/\[ "\$__root" != "\/" \] && //' "$LIBSRC" >"$sb/lib_L2.sh"
sed 's/\[ "\${HELIX_TEST_MODE:-}" = "1" \]/[ -n "${HELIX_TEST_MODE:-}" ]/' "$LIBSRC" >"$sb/lib_L3.sh"
for m in L1 L2 L3; do cmp -s "$LIBSRC" "$sb/lib_$m.sh" && bad "library mutant $m did not apply"; done
lib_case() { # lib-file tmpdir cwd envassign... -- outvar-args...   prints value|honoured-list
  local lib="$1" td="$2" cwd="$3"; shift 3; local -a envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  ( cd "$cwd" && env -u HELIX_TEST_MODE -u CM_GATE_OVERRIDES_HONOURED TMPDIR="$td" CM_GATE_OVERRIDES_HONOURED=FORGED "${envs[@]}" \
      bash -c '. "$1"; shift; cm_gate_env_set out "$@" 2>/dev/null; printf "%s|%s" "$out" "$CM_GATE_OVERRIDES_HONOURED"' _ "$lib" "$@" )
}
# name | want | tmpdir | cwd | env... -- args...
LCASES=(
  "unset -> default|D||$TR|$TR|X=1|--|V D value"
  "value, no test mode -> default|D||$TR|$TR|V=evil|--|V D value"
  "value, HELIX_TEST_MODE=1 -> honoured|evil|V|$TR|$TR|V=evil HELIX_TEST_MODE=1|--|V D value"
  "HELIX_TEST_MODE=0 -> default|D||$TR|$TR|V=evil HELIX_TEST_MODE=0|--|V D value"
  "HELIX_TEST_MODE=yes -> default|D||$TR|$TR|V=evil HELIX_TEST_MODE=yes|--|V D value"
  "path under temp root -> resolved absolute|$TR/sub/f|V|$TR|$TR|V=$TR/sub/./f HELIX_TEST_MODE=1|--|V D path"
  "relative path -> resolved against cwd, absolute|$TR/sub/rel|V|$TR|$TR/sub|V=rel HELIX_TEST_MODE=1|--|V D path"
  "dot-dot escape out of temp root -> default|D||$TR|$TR|V=$TR/../outside/x HELIX_TEST_MODE=1|--|V D path"
  "symlink escape (temp link -> /etc) -> default|D||$TR|$TR|V=$TR/etclink/hostname HELIX_TEST_MODE=1|--|V D path"
  "TMPDIR=/ -> any path refused|D||/|$TR|V=/etc/hostname HELIX_TEST_MODE=1|--|V D path"
  "path outside temp root, test mode -> default|D||$TR|$TR|V=/etc/hostname HELIX_TEST_MODE=1|--|V D path"
  "--test-root honours a path under it|$sb/outside/x|V|$TR|$TR|V=$sb/outside/x HELIX_TEST_MODE=1|--|V D path --test-root $sb/outside"
  "--test-root / is refused|D||$TR|$TR|V=/etc/hostname HELIX_TEST_MODE=1|--|V D path --test-root /"
  "--trusted exact path honoured without test mode|$sb/trusted_tool|V|$TR|$TR|V=$sb/./trusted_tool|--|V D path --trusted $sb/trusted_tool"
  "--trusted does not cover another path|D||$TR|$TR|V=$sb/outside/x|--|V D path --trusted $sb/trusted_tool"
)
lib_suite() { # lib-file -> number of cases that did not hold
  local lib="$1" miss=0 c n w hw td cwd e a got
  for c in "${LCASES[@]}"; do
    IFS='|' read -r n w hw td cwd e _ a <<<"$c"
    # shellcheck disable=SC2086
    got="$(lib_case "$lib" "$td" "$cwd" $e -- $a)"
    [ "$got" = "$w|$hw" ] || miss=$((miss+1))
  done; echo "$miss"
}
for c in "${LCASES[@]}"; do
  IFS='|' read -r n w hw td cwd e _ a <<<"$c"
  # shellcheck disable=SC2086
  got="$(lib_case "$sb/lib_ok.sh" "$td" "$cwd" $e -- $a)"
  [ "$got" = "$w|$hw" ]; chk $? "lib: $n (got '$got', want '$w|$hw')"
done
for m in L1 L3; do
  miss="$(lib_suite "$sb/lib_$m.sh")"; [ "$miss" -gt 0 ]; chk $? "library mutant $m killed ($miss case(s) flipped)"
done
# L2 is an EQUIVALENT mutant, recorded as such (11.4.6): with the temp root "/" the prefix tested is "//", and readlink -m
# never returns a path starting with "//", so dropping the explicit root != "/" check changes no outcome. The case
# below proves the behaviour the check exists for still holds under L2 (TMPDIR=/ and --test-root / both refused).
miss="$(lib_suite "$sb/lib_L2.sh")"; [ "$miss" = 0 ]; chk $? "library mutant L2 is equivalent: every case still holds under it ($miss flipped)"
for p2 in "/etc/hostname" "//etc/hostname" "/./etc"; do
  got="$(lib_case "$sb/lib_L2.sh" / "$TR" V="$p2" HELIX_TEST_MODE=1 -- V D path)"; [ "$got" = "D|" ]; chk $? "L2 equivalence: TMPDIR=/ still refuses $p2 (got '$got')"
done
# set -e callers (healthcheck, opendesign gates): an ignored override must not abort the caller (found by the matrix)
for k in value path; do
  out="$(env -u HELIX_TEST_MODE V=/etc/hostname bash -c 'set -e; . "$1"; cm_gate_env_set out V D '"$k"'; echo "after:$out"' _ "$sb/lib_ok.sh" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "after:D" ]; chk $? "lib under set -e: ignored $k override returns, caller continues (rc=$rc out='$out')"
done
# the fail-closed fallback stub every gate carries (library missing): an override is ignored with a note, never honoured
STUB="$(grep -m1 -h '^if \[ -r "\$_ge_lib" \]; then' "$src/scripts/gates/cm_guard_class_p_not_overridable.sh")"
out="$(env -u HELIX_TEST_MODE V=evil HELIX_TEST_MODE=1 bash -c '_ge_lib=/nonexistent; '"$STUB"'; cm_gate_env_set out V D value; printf "%s" "$out"' 2>&1)"
[ "${out##*$'\n'}" = D ] && grep -q 'guard lib missing: fail closed' <<<"$out"; chk $? "fallback stub (library missing) ignores even a test-mode override (got '${out##*$'\n'}')"


# ---- per-variable guard matrix (review findings: every guarded variable of the named gates) ----
# For each (gate, VAR, crafted value, args): A = the real gate without VAR; B = the real gate with VAR=value and no
# HELIX_TEST_MODE; C = a copy of the gate whose cm_gate_env_set for VAR (only) is replaced by a raw ${VAR:-default} read
# (the reviewer's "raw VAR" mutation), run with VAR=value. Required: B == A (rc + output, guard notes removed) and B
# prints "ignoring VAR"; and C != A (the crafted value really changes the verdict or output when the guard is gone, so
# the case is load-bearing). Slow canon gates (label-sync, covenant suite, jev bootstrap/detection) are exercised by
# their own paired mutation tests and are not repeated here.
MX="$sb/mx"; mkdir -p "$MX/repo" "$MX/empty" "$MX/dfx/pkg" "$MX/dfx2" "$MX/kfx" "$MX/kfx2" "$MX/kfx3" "$MX/mfx/sub"
( cd "$src" && { git ls-files; git ls-files --others --exclude-standard; } | sort -u | while IFS= read -r f; do [ -f "$f" ] && printf '%s\0' "$f"; done | xargs -0 cp --parents -t "$MX/repo" )
printf 'def f():\n    try:\n        x()\n    except Exception:\n        pass\n' > "$MX/dfx/pkg/bad.py"
printf 'package a\nfunc f() { defer func(){ recover() }() }\n' > "$MX/dfx2/a.go"
printf 'import os\ndef f(p):\n    os.'"$KP"'(p.pid, 9)\n' > "$MX/kfx/bad.py"
printf 'import os\ndef f(p):\n    pgid = os.getpgid(p.pid)\n    if not isinstance(pgid, int) or pgid <= 1:\n        return\n    a=1\n    a=2\n    a=3\n    a=4\n    a=5\n    a=6\n    a=7\n    a=8\n    os.killpg(pgid, 9)\n' > "$MX/kfx2/bad.py"
printf 'import os\ndef f(p):\n    os.'"$KP"'(p.pid, 9)  # killpg-gate:allow fixture reason\n' > "$MX/kfx3/bad.py"
printf 'from unittest.mock import AsyncMock\nimport os\ndef test_a():\n    p = AsyncMock()\n    os.'"$KP"'(os.getpgid(p.pid), 9)\n' > "$MX/mfx/sub/test_bad.py"
mkdir -p "$MX/hc" "$MX/od/src/theme"
printf 'services:\n  download-proxy:\n    image: python:3.12-alpine\n    network_mode: host\n    healthcheck:\n      test: ["CMD-SHELL", "wget -q -O /dev/null http://localhost:7186/ || exit 1"]\n' > "$MX/hc/compose.yml"
printf 'schema_version: 1\nservices:\n  download-proxy:\n    serves: [7186, 7187]\n' > "$MX/hc/manifest.yml"
printf ':root{--c:#ff0000}\n' > "$MX/od/src/theme/a.css"
printf '#!/bin/sh\nexit 0\n' > "$MX/fake_ok.sh"; chmod +x "$MX/fake_ok.sh"; cp "$MX/fake_ok.sh" "$MX/fakepy"
for g in cm_dangerous_combination_fail_closed cm_killpg_pgid_guard cm_test_mock_pid_explicit_int; do mkgate "$MX/rr_$g" "$g"; done
cp -R "$MX/dfx/pkg" "$MX/rr_cm_dangerous_combination_fail_closed/"; cp "$MX/kfx/bad.py" "$MX/rr_cm_killpg_pgid_guard/"
mkdir -p "$MX/rr_cm_test_mock_pid_explicit_int/t"; cp "$MX/mfx/sub/test_bad.py" "$MX/rr_cm_test_mock_pid_explicit_int/t/"
mkraw() { # gate-file VAR -> copy with that VAR's cm_gate_env_set replaced by a raw read
  local out="${1%.sh}__raw_$2.sh"
  python3 -I - "$1" "$2" "$out" <<'PY2' && echo "$out"
import re, sys
src, var, out = sys.argv[1:4]
s = open(src).read()
rx = re.compile(r'cm_gate_env_set\s+(\w+)\s+' + re.escape(var) + r'\s+(.+?)\s+(?:value|path)\b((?:\s+--(?:test-root|trusted)\s+(?:"[^"]*"|\S+))*)')
def rep(m):
    d = m.group(2)
    if len(d) >= 2 and d[0] == '"' and d[-1] == '"': d = d[1:-1]
    return m.group(1) + '="${' + var + ':-' + d + '}"'
s2, n = rx.subn(rep, s)
if n == 0: sys.exit(3)
open(out, "w").write(s2)
PY2
}
mnorm() { grep -v '^gate_env_override:' | sed -e 's#__raw_[A-Z_]*\.sh#.sh#g'; }
mrun() { # gate-file VAR(or -) value args...   -> normalised output + RC line (extra env in the XE array)
  local g="$1" v="$2" val="$3"; shift 3; local o rc
  if [ "$v" = - ]; then o="$(cd "$MX" && env -u HELIX_TEST_MODE "${XE[@]}" timeout 300 bash "$g" "$@" </dev/null 2>&1)"; rc=$?
  else o="$(cd "$MX" && env -u HELIX_TEST_MODE "${XE[@]}" "$v=$val" timeout 300 bash "$g" "$@" </dev/null 2>&1)"; rc=$?; fi
  printf '%s\nRC=%s\n' "$(printf '%s\n' "$o" | mnorm)" "$rc"
}
R="$MX/repo/scripts/gates"
MCASES=(
  "$R/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_EXCLUDE|pkg|--root $MX/dfx --quiet"
  "$R/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_EXT|go|--root $MX/dfx --quiet"
  "$R/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_MAX_DEPTH|1|--root $MX/dfx --quiet"
  "$R/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_PYTHON|$MX/fakepy|--root $MX/dfx --quiet"
  "$R/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_UNANALYSED_EXT|zz|--root $MX/dfx2 --quiet"
  "$MX/rr_cm_dangerous_combination_fail_closed/scripts/gates/cm_dangerous_combination_fail_closed.sh|DANGEROUS_COMBO_ROOT|$MX/empty|--quiet"
  "$R/cm_killpg_pgid_guard.sh|KILLPG_GUARD_EXCLUDE|kfx|--root $MX/kfx --quiet"
  "$R/cm_killpg_pgid_guard.sh|KILLPG_GUARD_EXT|go|--root $MX/kfx --quiet"
  "$R/cm_killpg_pgid_guard.sh|KILLPG_GUARD_ALLOW_PATHS|bad.py|--root $MX/kfx3 --quiet"
  "$R/cm_killpg_pgid_guard.sh|KILLPG_GUARD_WINDOW|20|--root $MX/kfx2 --quiet"
  "$MX/rr_cm_killpg_pgid_guard/scripts/gates/cm_killpg_pgid_guard.sh|KILLPG_GUARD_ROOT|$MX/empty|--quiet"
  "$R/cm_test_mock_pid_explicit_int.sh|MOCK_PID_GUARD_EXCLUDE|sub|--root $MX/mfx --quiet"
  "$R/cm_test_mock_pid_explicit_int.sh|MOCK_PID_GUARD_GLOB|*nomatch*.py|--root $MX/mfx --quiet"
  "$MX/rr_cm_test_mock_pid_explicit_int/scripts/gates/cm_test_mock_pid_explicit_int.sh|MOCK_PID_GUARD_ROOT|$MX/empty|--quiet"
  "$R/cm_guard_class_p_not_overridable.sh|GUARD|$MX/fake_ok.sh|"
  "$R/cm_codegraph_mcp_health.sh|CG_HEALTH_TOOL|$MX/fake_ok.sh|"
  "$R/cm_helix_deps_manifest_present.sh|HELIX_DEPS_ENGINE|$MX/fake_ok.sh|"
  "$R/cm_decisions_override_valid.sh|DECISIONS_CLI|$MX/fake_ok.sh|"
  "$R/cm_decisions_wizard_safety.sh|DECISIONS_CLI|$MX/fake_ok.sh|"
  "$R/cm_multitrack_engine_in_constitution.sh|MULTITRACK_ENGINE_DIR|$MX/empty|--quiet"
  "$R/cm_canonical_root_clarity.sh|CANONICAL_ROOT_DIR|$MX/empty|--quiet"
  "$R/cm_continuum_resume_engine_present.sh|CONSTITUTION_ROOT|$MX/empty|--quiet"
  "$R/cm_first_refusal_observed.sh|CONSTITUTION_ROOT|$MX/empty|--quiet"
  "$R/cm_gate_ledger_ratchet.sh|CONSTITUTION_ROOT|$MX/empty|--quiet"
  "$R/cm_healthcheck_covers_served_ports.sh|HEALTHCHECK_PORTS_PYTHON|$MX/fakepy|--compose $MX/hc/compose.yml --manifest $MX/hc/manifest.yml"
  "$R/cm_opendesign_ui_system.sh|OD_THEME_GLOBS|nomatch_zz|--root $MX/od"
  "$R/cm_opendesign_ui_system.sh|OD_TOKEN_GLOBS|src/theme/*|--root $MX/od"
  "$R/cm_opendesign_ui_system.sh|OD_VISREG_GLOBS|src/theme/*|--root $MX/od"
  "$R/cm_opendesign_ui_system.sh|OD_MANIFEST_GLOBS|src/theme/*|--root $MX/od"
  "$R/cm_setup_prompt_latest_present.sh|SETUP_PROMPT_EXTRACT_LIB|$MX/fake_ok.sh|"
  "$R/cm_installer_no_push_no_force.sh|CM_NOPUSH_INVENTORY|1|"
  "$R/cm_installer_no_push_no_force.sh|CM_NOPUSH_COLLECT|1|"
  "$R/cm_jev_detection.sh|JEV_PROBE_CMD|$MX/fake_ok.sh|"
  "$R/cm_jev_token_reduction.sh|JEV_REDUCTION_FLOOR|0.01||JEVFIX"
  "$R/cm_jev_token_reduction.sh|JEV_GATED_CLASSES|nosuchclass||JEVFIX"
)
JF="$R/fixtures/jev/evidence"
for c in "${MCASES[@]}"; do
  IFS='|' read -r gp var val args ex <<<"$c"
  XE=(X_NOOP=1); [ "${ex:-}" = JEVFIX ] && XE=(JEV_BEFORE="$JF/before.jsonl" JEV_AFTER="$JF/after.jsonl" JEV_DECISIONS="$JF/decisions.jsonl" JEV_STATS_REPORT="$JF/jev-stats-report.txt")
  raw="$(mkraw "$gp" "$var")" || { bad "matrix: could not build the raw-$var mutant of $(basename "$gp")"; continue; }
  # shellcheck disable=SC2086
  A="$(mrun "$gp" - - $args)"; B="$(mrun "$gp" "$var" "$val" $args)"; C="$(mrun "$raw" "$var" "$val" $args)"
  # shellcheck disable=SC2086
  note="$(cd "$MX" && env -u HELIX_TEST_MODE "${XE[@]}" "$var=$val" timeout 300 bash "$gp" $args </dev/null 2>&1 | grep -c "gate_env_override: ignoring $var")"
  [ "$A" = "$B" ] && [ "$note" -ge 1 ]; chk $? "matrix $(basename "$gp" .sh): $var=<crafted> without test mode is ignored with a note, verdict unchanged (rc ${A##*RC=})"
  [ "$A" != "$C" ]; chk $? "matrix $(basename "$gp" .sh): raw-$var mutant is killed (rc ${A##*RC=} -> ${C##*RC=})"
  rm -f -- "$raw"
done

# R4-5: a trailing --test-root / --trusted with no value must not loop forever (shift 2 with one argument left)
for opt in --test-root --trusted; do
  timeout 5 bash -c '. "$1/scripts/lib/gate_env_override.sh"; cm_gate_env_set v GEO_NOPE_X dflt path "$2"; [ "$v" = dflt ]' _ "$src" "$opt" >/dev/null 2>&1
  chk $? "cm_gate_env_set with $opt as the last argument returns promptly with the default (no infinite loop)"
done

echo "== $pass passed, $fail failed =="; [ "$fail" = 0 ]
