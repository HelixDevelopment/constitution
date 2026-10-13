#!/bin/bash
# T007 RED test for fc_common (spec 004-fast-dev-cycles; contracts/common-conventions.md C-001..C-004).
# Purpose: pin fc_common.{py,sh} behaviour BEFORE T008 implements it. RED = library absent.
# Usage: bash test_fc_common_red.sh   (exit 0 = all assertions pass; nonzero = FAIL count>0)
#
# UNCONFIRMED (contract fixes semantics, NOT the CLI shape) -> shape chosen here, for the T008 implementer:
#   python3 lib/fc_common.py emit --schema S --body-json J [--run-meta-json J] --out PATH [--code N]
#       writes canonical doc {"body_hash":..,"run_meta":..,"schema":S,...body keys} (sorted keys, compact,
#       ensure_ascii=False); body_hash = sha256(canonical(body + schema)) EXCLUDING run_meta.
#       --code 0|1 writes file; --code 3 writes NO file (exit 3); --code 4 writes file with "BLIND":true, exits 4.
#   python3 lib/fc_common.py body-hash --doc PATH          -> prints body_hash recomputed from doc (excl. run_meta)
#   python3 lib/fc_common.py needle --present JSON_LIST --fabricated JSON_LIST --haystack JSON_LIST
#       exit 0 ok; exit 3 if any present missing or fabricated found (C-004, set-member coverage)
#   python3 lib/fc_common.py determinism-check -- CMD...   runs CMD twice (CMD writes a doc to $FC_OUT),
#       exit 0 equal body_hash, exit 1 with diff on mismatch
#   python3 lib/fc_common.py require-as-of [--windowed] [--as-of YYYY-MM-DD]   windowed w/o --as-of -> exit 2
#   sh lib/fc_common.sh (sourced): fc_body_hash PATH  (prints body_hash)
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib"
PY="$LIB/fc_common.py"; SH="$LIB/fc_common.sh"
TMP="$(mktemp -d)"
# Process-leak guard: every hang-capable case spawns children whose command line names $TMP or a unique sleep
# number; reap them on EVERY exit path (normal, INT, TERM) before removing $TMP.
reap_children() {
  pkill -KILL -f "$TMP" 2>/dev/null
  for _v in SL1 SL2 SL3 SL4 SL5; do eval "_n=\${$_v:-}"; [ -n "$_n" ] && pkill -KILL -x -f "sleep $_n" 2>/dev/null; done
  return 0
}
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM
FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }

# Precondition: library present. RED reason = these absent (not a test syntax error).
if [ ! -f "$PY" ] || [ ! -f "$SH" ]; then
  echo "RED: library absent: $PY exists=$([ -f "$PY" ] && echo y || echo n) $SH exists=$([ -f "$SH" ] && echo y || echo n)"
  FAIL=$((FAIL+1))
fi
run() { python3 "$PY" "$@" 2>"$TMP/err"; }

# 1 sorted-key canonical JSON
run emit --schema t/v1 --body-json '{"zeta":1,"alpha":2,"mid":{"b":1,"a":2}}' --out "$TMP/d1.json"; rc=$?
chk "emit rc=0" "$([ $rc = 0 ] && echo 1 || echo 0)"
python3 - "$TMP/d1.json" >"$TMP/o1" 2>&1 <<'PY'
import sys,json
raw=open(sys.argv[1],encoding="utf-8").read().rstrip("\n")
d=json.loads(raw)
canon=json.dumps(d,sort_keys=True,separators=(",",":"),ensure_ascii=False)
print("OK" if raw==canon and "body_hash" in d and d.get("schema")=="t/v1" else "BAD")
PY
chk "canonical JSON sorted keys compact" "$([ "$(cat "$TMP/o1")" = OK ] && echo 1 || echo 0)"

# 2 body_hash excludes run_meta
run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json '{"host":"x","ms":5}' --out "$TMP/a.json"
run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json '{"host":"y","ms":999}' --out "$TMP/b.json"
ha="$(python3 "$PY" body-hash --doc "$TMP/a.json" 2>/dev/null)"; hb="$(python3 "$PY" body-hash --doc "$TMP/b.json" 2>/dev/null)"
chk "body_hash equal across differing run_meta" "$([ -n "$ha" ] && [ "$ha" = "$hb" ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":2}' --out "$TMP/c.json"
hc="$(python3 "$PY" body-hash --doc "$TMP/c.json" 2>/dev/null)"
chk "body_hash differs when body differs" "$([ -n "$hc" ] && [ "$hc" != "$ha" ] && echo 1 || echo 0)"
chk "sh fc_body_hash matches py" "$([ "$(bash -c ". '$SH' 2>/dev/null; fc_body_hash '$TMP/a.json'" 2>/dev/null)" = "$ha" ] && [ -n "$ha" ] && echo 1 || echo 0)"

# 3 exit 3 writes no result file
rm -f "$TMP/r3.json"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/r3.json" --code 3; rc=$?
chk "code 3 exits 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
chk "code 3 writes no result file" "$([ ! -e "$TMP/r3.json" ] && echo 1 || echo 0)"

# 4 BLIND never 0
rm -f "$TMP/r4.json"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/r4.json" --code 4; rc=$?
chk "code 4 exits 4 (never 0)" "$([ $rc = 4 ] && echo 1 || echo 0)"
chk "code 4 output flagged BLIND" "$(grep -q '"BLIND":true' "$TMP/r4.json" 2>/dev/null && echo 1 || echo 0)"

# needle C-004
run needle --present '["x","y"]' --fabricated '["zz"]' --haystack '["x","y"]'; rc=$?
chk "needle ok rc 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
run needle --present '["x","y"]' --fabricated '["zz"]' --haystack '["x"]'; rc=$?
chk "needle missing set member -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '["x"]' --fabricated '["zz"]' --haystack '["x","zz"]'; rc=$?
chk "needle fabricated found -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"

# 5 determinism-check
cat >"$TMP/stable.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --run-meta-json "{\"ms\":$RANDOM}" --out "$FC_OUT"
S
cat >"$TMP/flaky.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json "{\"a\":$RANDOM$RANDOM}" --out "$FC_OUT"
S
export FC_PY="$PY"
python3 "$PY" determinism-check -- bash "$TMP/stable.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check stable -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
python3 "$PY" determinism-check -- bash "$TMP/flaky.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check differing body_hash -> 1" "$([ $rc = 1 ] && echo 1 || echo 0)"

# 6 --as-of required for windowed
run require-as-of --windowed; rc=$?
chk "windowed without --as-of -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
run require-as-of --windowed --as-of 2026-09-26; rc=$?
chk "windowed with --as-of -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"


# ---- T014 remediation cases (F7 F8 F9 F10 F11 F12 F17 survivors) ----
# F7: reserved keys refused (exit 2), BLIND never exits 0, BLIND part of the hash (C-002 excludes only run_meta)
for k in BLIND schema run_meta body_hash; do
  rm -f "$TMP/rk.json"; run emit --schema t/v1 --body-json "{\"$k\":true,\"a\":1}" --out "$TMP/rk.json"; rc=$?
  chk "reserved body key $k refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/rk.json" ] && echo 1 || echo 0)"
done
run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/clean.json"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/blind.json" --code 4
hcl="$(python3 "$PY" body-hash --doc "$TMP/clean.json" 2>/dev/null)"; hbl="$(python3 "$PY" body-hash --doc "$TMP/blind.json" 2>/dev/null)"
chk "BLIND doc hash differs from clean doc hash" "$([ -n "$hcl" ] && [ -n "$hbl" ] && [ "$hcl" != "$hbl" ] && echo 1 || echo 0)"
stored="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["body_hash"])' "$TMP/blind.json")"
chk "stored body_hash == recomputed (BLIND doc)" "$([ "$stored" = "$hbl" ] && echo 1 || echo 0)"
# F17: schema is part of the hashed body
run emit --schema t/v2 --body-json '{"a":1}' --out "$TMP/s2.json"
hs2="$(python3 "$PY" body-hash --doc "$TMP/s2.json" 2>/dev/null)"
chk "schema participates in body_hash" "$([ -n "$hs2" ] && [ "$hs2" != "$hcl" ] && echo 1 || echo 0)"
# F17: ensure_ascii=False pinned (raw UTF-8 on disk, pinned hash)
run emit --schema t/v1 --body-json '{"k":"é"}' --out "$TMP/u.json"
chk "non-ASCII written raw (ensure_ascii=False)" "$(grep -q 'é' "$TMP/u.json" && ! grep -q '\\u00e9' "$TMP/u.json" && echo 1 || echo 0)"
exp="$(printf '%s' '{"k":"é","schema":"t/v1"}' | sha256sum | cut -d' ' -f1)"
chk "non-ASCII body_hash pinned" "$([ "$(python3 "$PY" body-hash --doc "$TMP/u.json" 2>/dev/null)" = "$exp" ] && echo 1 || echo 0)"
# F8: internal errors never exit 1 (finding)
run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/nodir/x.json"; rc=$?
chk "emit into missing dir -> 2 not 1" "$([ $rc = 2 ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":"\ud800"}' --out "$TMP/sur.json"; rc=$?
chk "lone surrogate -> 2 not 1" "$([ $rc = 2 ] && echo 1 || echo 0)"
echo '[1]' >"$TMP/arr.json"; run body-hash --doc "$TMP/arr.json"; rc=$?
chk "body-hash on non-object -> 2 not 1" "$([ $rc = 2 ] && echo 1 || echo 0)"
run needle --present null --fabricated '["z"]' --haystack '["x"]'; rc=$?
chk "needle --present null -> 2 not 1" "$([ $rc = 2 ] && echo 1 || echo 0)"
# F9: needle type-checks inputs (strings/objects/nested are not sets of scalars)
run needle --present '["x"]' --fabricated '["q"]' --haystack '"xyz"'; rc=$?
chk "needle string haystack -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
run needle --present '["x"]' --fabricated '["q"]' --haystack '{"x":1}'; rc=$?
chk "needle object haystack -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
run needle --present '"xy"' --fabricated '["q"]' --haystack '["x"]'; rc=$?
chk "needle string --present -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
run needle --present '[["x"]]' --fabricated '["q"]' --haystack '["x"]'; rc=$?
chk "needle nested-list member -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
# F10: determinism-check distinct codes + diff
cat >"$TMP/find1.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"; exit 1
S
python3 "$PY" determinism-check -- bash "$TMP/find1.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: tool exiting 1 (finding) but stable -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
cat >"$TMP/sig.sh" <<'S'
#!/bin/bash
kill -9 $$
S
python3 "$PY" determinism-check -- bash "$TMP/sig.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: signal death -> 4 (BLIND, not 247)" "$([ $rc = 4 ] && echo 1 || echo 0)"
python3 "$PY" determinism-check -- /nonexistent/cmd_zz >/dev/null 2>&1; rc=$?
chk "determinism-check: missing command -> 4 not 1" "$([ $rc = 4 ] && echo 1 || echo 0)"
printf '#!/bin/bash\necho notjson >"$FC_OUT"\n' >"$TMP/nj.sh"
python3 "$PY" determinism-check -- bash "$TMP/nj.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: non-JSON doc -> 4 not 1" "$([ $rc = 4 ] && echo 1 || echo 0)"
python3 "$PY" determinism-check -- bash "$TMP/flaky.sh" >/dev/null 2>"$TMP/dif"; rc=$?
chk "determinism-check mismatch prints a diff" "$([ $rc = 1 ] && grep -q '^[-+] ' "$TMP/dif" && echo 1 || echo 0)"
# F11: --as-of only YYYY-MM-DD
for bad in 20260926 2026-W39-5 2026-13-45 2026-9-26 ""; do
  run require-as-of --as-of "$bad"; rc=$?
  chk "as-of '$bad' -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
done
run require-as-of --as-of 2026-09-26; rc=$?
chk "as-of 2026-09-26 -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
# F12: NaN / Infinity / duplicate keys refused
run emit --schema t/v1 --body-json '{"a":NaN}' --out "$TMP/nan.json"; rc=$?
chk "NaN body refused rc=2 no file" "$([ $rc = 2 ] && [ ! -e "$TMP/nan.json" ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":Infinity}' --out "$TMP/inf.json"; rc=$?
chk "Infinity body refused rc=2" "$([ $rc = 2 ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":1,"a":2}' --out "$TMP/dup.json"; rc=$?
chk "duplicate keys refused rc=2" "$([ $rc = 2 ] && [ ! -e "$TMP/dup.json" ] && echo 1 || echo 0)"


# ---- T014 round-3 remediation (R2-F1..F4, F7, F8) ----
# R2-F2: overflowing float must not emit invalid JSON (Infinity) on the emit path
rm -f "$TMP/o.json"; run emit --schema t/v1 --body-json '{"a":1e999}' --out "$TMP/o.json"; rc=$?
chk "emit 1e999 body refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/o.json" ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json '{"m":-1e999}' --out "$TMP/o2.json"; rc=$?
chk "emit 1e999 run_meta refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/o2.json" ] && echo 1 || echo 0)"
run needle --present '[1e999]' --fabricated '[2]' --haystack '[1]'; rc=$?
chk "needle 1e999 -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
# R2-F3: needle comparison is type-strict (True == 1 == 1.0 must not match)
run needle --present '[1]' --fabricated '[2]' --haystack '[true]'; rc=$?
chk "needle present 1 not satisfied by true -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '[0]' --fabricated '[9]' --haystack '[false]'; rc=$?
chk "needle present 0 not satisfied by false -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '[1]' --fabricated '[true]' --haystack '[1]'; rc=$?
chk "needle fabricated true not matched by 1 -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
run needle --present '[true,1,"1"]' --fabricated '[2]' --haystack '["1",1,true]'; rc=$?
chk "needle same-type members still match -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
# R2-F4: internal error -> exit 4 (BLIND: no honest verdict), inside C-001 table; never 70/1
python3 - "$LIB" >"$TMP/ie.out" 2>"$TMP/ie.err" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import fc_common
def boom(a):
    raise RuntimeError("injected")
fc_common.main.__globals__["cmd_needle"] = boom
# main builds its table from module globals at call time
sys.exit(fc_common.main(["needle", "--present", "[1]", "--fabricated", "[2]", "--haystack", "[1]"]))
PY
rc=$?
chk "uncaught internal error -> 4 (in C-001 table)" "$([ $rc = 4 ] && grep -q 'internal error' "$TMP/ie.err" && echo 1 || echo 0)"
deep="$(python3 -c 'print("["*60000+"]"*60000)')"
run emit --schema t/v1 --body-json "{\"a\":$deep}" --out "$TMP/deep.json"; rc=$?
chk "deeply nested JSON -> 2 (unparseable input), no file" "$([ $rc = 2 ] && [ ! -e "$TMP/deep.json" ] && echo 1 || echo 0)"
# R2-F1 RX3: LC_ALL=C is forced for the checked command (C-003)
cat >"$TMP/lc.sh" <<'S'
#!/bin/bash
printf '%s\n' "${LC_ALL-unset}" >>"$FC_LC_LOG"
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"
S
export FC_LC_LOG="$TMP/lc.log"; : >"$FC_LC_LOG"
LC_ALL=en_US.UTF-8 python3 "$PY" determinism-check -- bash "$TMP/lc.sh" >/dev/null 2>&1
chk "determinism-check runs command under LC_ALL=C (both runs)" "$([ "$(sort -u "$FC_LC_LOG" | tr '\n' ,)" = "C," ] && [ "$(wc -l <"$FC_LC_LOG")" = 2 ] && echo 1 || echo 0)"
# R2-F1 RX5: empty needle sets are errors, never success
run needle --present '[]' --fabricated '["z"]' --haystack '["x"]'; rc=$?
chk "empty --present -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '["x"]' --fabricated '[]' --haystack '["x"]'; rc=$?
chk "empty --fabricated -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
# R2-F1 RX6: no temp file left behind after a failure that occurs after mkstemp
mkdir -p "$TMP/cl/outd"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/cl/outd"; rc=$?
chk "emit with a directory as --out -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
chk "no .fc_emit.* temp file left after failure" "$(leak=0; for f in "$TMP"/cl/.fc_emit.*; do [ -e "$f" ] && leak=1; done; [ $leak = 0 ] && echo 1 || echo 0)"
# R2-F1 RX7: body-hash uses the strict loader (dup keys / NaN / 1e999 refused)
printf '{"a":1,"a":2}\n' >"$TMP/bd.json"; run body-hash --doc "$TMP/bd.json"; rc=$?
chk "body-hash duplicate keys -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
printf '{"a":NaN}\n' >"$TMP/bn.json"; run body-hash --doc "$TMP/bn.json"; rc=$?
chk "body-hash NaN -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
printf '{"a":1e999}\n' >"$TMP/bi.json"; run body-hash --doc "$TMP/bi.json"; rc=$?
chk "body-hash 1e999 -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
# R2-F1 RX9: an exit-code change between runs with an identical body is nondeterminism
cat >"$TMP/rcflip.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"
if [ -e "$FC_FLIP" ]; then exit 1; fi
: >"$FC_FLIP"; exit 0
S
export FC_FLIP="$TMP/flip.marker"; rm -f "$FC_FLIP"
python3 "$PY" determinism-check -- bash "$TMP/rcflip.sh" >/dev/null 2>"$TMP/flip.err"; rc=$?
chk "determinism-check: rc 0 then 1, same body -> 1 (nondeterministic)" "$([ $rc = 1 ] && grep -q 'nondeterministic' "$TMP/flip.err" && echo 1 || echo 0)"
# R2-F7: result files honour the umask (evidence must stay readable per the caller's umask)
( umask 022; python3 "$PY" emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/m022.json" 2>/dev/null )
( umask 027; python3 "$PY" emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/m027.json" 2>/dev/null )
chk "emit honours umask 022 -> mode 644" "$([ "$(stat -c %a "$TMP/m022.json")" = 644 ] && echo 1 || echo 0)"
chk "emit honours umask 027 -> mode 640" "$([ "$(stat -c %a "$TMP/m027.json")" = 640 ] && echo 1 || echo 0)"
# R2-F8: --schema must be <tool>/v<N>
for bad in "" "nov" "t/v" "t/vx" "/v1" "a b/v1" "t/v1/x"; do
  rm -f "$TMP/sc.json"; run emit --schema "$bad" --body-json '{"a":1}' --out "$TMP/sc.json"; rc=$?
  chk "schema '$bad' refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/sc.json" ] && echo 1 || echo 0)"
done
run emit --schema fc-tool_x/v12 --body-json '{"a":1}' --out "$TMP/sc.json"; rc=$?
chk "schema fc-tool_x/v12 accepted" "$([ $rc = 0 ] && echo 1 || echo 0)"

# ---- T014 round-4 remediation (MXA, R3-F4, R3-F5, R3-F7) ----
# MXA: C-001 legitimate command codes: 0 and 1 (each with a doc) are verdicts; 3 = self-test failed; every
# other code (2 usage, 4 BLIND, 5, 70, 128, 255) is NOT an honest verdict -> determinism-check exits 4.
for code in 2 4 5 70 128 255; do
  cat >"$TMP/rc$code.sh" <<S
#!/bin/bash
python3 "\$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "\$FC_OUT"; exit $code
S
  python3 "$PY" determinism-check -- bash "$TMP/rc$code.sh" >/dev/null 2>"$TMP/rce"; rc=$?
  chk "determinism-check: command rc $code twice, same doc -> 4 (no honest verdict)" "$([ $rc = 4 ] && grep -q "rc=$code" "$TMP/rce" && echo 1 || echo 0)"
done
cat >"$TMP/rc3.sh" <<'S'
#!/bin/bash
exit 3
S
python3 "$PY" determinism-check -- bash "$TMP/rc3.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: command rc 3 -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
printf '#!/bin/bash\nexit 0\n' >"$TMP/nodoc0.sh"
python3 "$PY" determinism-check -- bash "$TMP/nodoc0.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: rc 0 but no doc -> 4" "$([ $rc = 4 ] && echo 1 || echo 0)"
# R3-F4: numbers compare numerically (1 == 1.0), bool never equals a number, str never equals a number
run needle --present '[1.0]' --fabricated '[9]' --haystack '[1]'; rc=$?
chk "needle present 1.0 satisfied by 1 -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
run needle --present '[1]' --fabricated '[9]' --haystack '[1.0]'; rc=$?
chk "needle present 1 satisfied by 1.0 -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
run needle --present '[1]' --fabricated '[2.0]' --haystack '[1,2]'; rc=$?
chk "needle fabricated 2.0 matched by 2 -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '[1]' --fabricated '[9]' --haystack '[true,1.5]'; rc=$?
chk "needle bool never equals number (1 vs true) -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '[true]' --fabricated '[9]' --haystack '[1,1.0]'; rc=$?
chk "needle bool never equals number (true vs 1/1.0) -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
run needle --present '[1]' --fabricated '[9]' --haystack '["1"]'; rc=$?
chk "needle string never equals number -> 3" "$([ $rc = 3 ] && echo 1 || echo 0)"
# R3-F5: run_meta must be an object; empty string is refused, not read as absent
for bad in '[1,2]' '""' '1' 'null' '"x"'; do
  rm -f "$TMP/rm.json"; run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json "$bad" --out "$TMP/rm.json"; rc=$?
  chk "run_meta '$bad' refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/rm.json" ] && echo 1 || echo 0)"
done
rm -f "$TMP/rm.json"; run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json '' --out "$TMP/rm.json"; rc=$?
chk "run_meta empty string refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/rm.json" ] && echo 1 || echo 0)"
run emit --schema t/v1 --body-json '{"a":1}' --run-meta-json '{}' --out "$TMP/rm.json"; rc=$?
chk "run_meta {} accepted" "$([ $rc = 0 ] && echo 1 || echo 0)"
# R3-F7: header agrees with code+contract on exit 4 (file BLIND-flagged only for emit --code 4; internal error = no file)
chk "header documents exit 4 both meanings consistently" "$(grep -q 'emit --code 4' "$PY" && grep -q 'internal error' "$PY" && ! grep -q '4 BLIND (file flagged),$' "$PY" && echo 1 || echo 0)"

# ---- T014 round-5 remediation (R4-F2): determinism-check bounds the command, kills its whole process group ----
# §11.4.273 control needle: an empty `pgrep -x -f "sleep $val"` is not proof "genuinely absent" unless the
# SAME instrument, through this SAME exact invocation, is first shown able to find a real match. Spawns a
# throwaway sleep using the given value, proves pgrep sees it, kills+reaps it, then leaves NEEDLE_SEEN=1
# iff the positive control actually fired (0 = instrument blind -- the absence-check below proves nothing).
needle_control() {
  local val="$1" pid
  sleep "$val" &
  pid=$!
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x -f "sleep $val" >/dev/null && break
    sleep 0.05
  done
  NEEDLE_SEEN=0; pgrep -x -f "sleep $val" >/dev/null && NEEDLE_SEEN=1
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}
export FC_DETERMINISM_TIMEOUT_S=2
SL1=$((5000000+$$)); SL2=$((SL1+1)); SL3=$((SL1+2)); export SL1 SL2 SL3   # unique per run: parallel-safe
cat >"$TMP/hang.sh" <<'S'
#!/bin/bash
sleep $SL1 &
wait
S
t0=$SECONDS
timeout 30 python3 "$PY" determinism-check -- bash "$TMP/hang.sh" >/dev/null 2>"$TMP/hang.err"; rc=$?
el=$((SECONDS-t0))
chk "determinism-check: hanging command -> 4 (not a verdict), within bound" "$([ $rc = 4 ] && [ $el -lt 15 ] && grep -q 'timed out' "$TMP/hang.err" && echo 1 || echo 0)"
needle_control "$SL1"
chk "determinism-check: timeout leaves no orphan child (control needle: pgrep saw it)" "$([ "$NEEDLE_SEEN" = 1 ] && ! pgrep -x -f "sleep $SL1" >/dev/null && echo 1 || echo 0)"
pkill -x -f "sleep $SL1" 2>/dev/null
cat >"$TMP/hangterm.sh" <<'S'
#!/bin/bash
trap '' TERM
sleep $SL2 &
while :; do sleep 1; done
S
t0=$SECONDS
timeout 30 python3 "$PY" determinism-check -- bash "$TMP/hangterm.sh" >/dev/null 2>"$TMP/ht.err"; rc=$?
el=$((SECONDS-t0))
chk "determinism-check: TERM-ignoring hang -> 4 (SIGKILL after grace)" "$([ $rc = 4 ] && [ $el -lt 20 ] && echo 1 || echo 0)"
needle_control "$SL2"
chk "determinism-check: TERM-ignoring hang leaves no orphan (control needle: pgrep saw it)" "$([ "$NEEDLE_SEEN" = 1 ] && ! pgrep -x -f "sleep $SL2" >/dev/null && echo 1 || echo 0)"
pkill -x -f "sleep $SL2" 2>/dev/null
cat >"$TMP/leak.sh" <<'S'
#!/bin/bash
sleep $SL3 >/dev/null 2>&1 &
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"
S
timeout 30 python3 "$PY" determinism-check -- bash "$TMP/leak.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check: normal command with a stray background child -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
needle_control "$SL3"
chk "determinism-check: stray child of a finished command is reaped (control needle: pgrep saw it)" "$([ "$NEEDLE_SEEN" = 1 ] && ! pgrep -x -f "sleep $SL3" >/dev/null && echo 1 || echo 0)"
pkill -x -f "sleep $SL3" 2>/dev/null
for bad in 0 -1 abc 1.5 "" 1000000 " 5"; do
  FC_DETERMINISM_TIMEOUT_S="$bad" timeout 30 python3 "$PY" determinism-check -- bash "$TMP/stable.sh" >/dev/null 2>"$TMP/te"; rc=$?
  chk "FC_DETERMINISM_TIMEOUT_S='$bad' refused rc=2" "$([ $rc = 2 ] && grep -qxF "fc_common: FC_DETERMINISM_TIMEOUT_S must be a positive integer of at most 6 digits, got '$bad'" "$TMP/te" && echo 1 || echo 0)"
done
FC_DETERMINISM_TIMEOUT_S=999999 timeout 30 python3 "$PY" determinism-check -- bash "$TMP/stable.sh" >/dev/null 2>&1; rc=$?
chk "FC_DETERMINISM_TIMEOUT_S=999999 (max, 6 digits) accepted" "$([ $rc = 0 ] && echo 1 || echo 0)"
FC_DETERMINISM_TIMEOUT_S=1 timeout 30 python3 "$PY" determinism-check -- bash "$TMP/stable.sh" >/dev/null 2>&1; rc=$?
chk "FC_DETERMINISM_TIMEOUT_S=1 (min) accepted" "$([ $rc = 0 ] && echo 1 || echo 0)"
unset FC_DETERMINISM_TIMEOUT_S
chk "timeout default named + marked operator-tunable, no measured basis" "$(grep -q 'DETERMINISM_TIMEOUT_DEFAULT_S = ' "$PY" && grep -q 'operator-tunable default, no measured basis' "$PY" && echo 1 || echo 0)"

# ---- T014 round-5 mutation-sweep additions: diagnostics, argparse surface, process-group internals ----
export FC_DETERMINISM_TIMEOUT_S=2   # short bound for every hang case below
emsg() { # emsg NAME RC 'anchored ERE for one whole stderr line' args... : exit code AND the exact diagnostic are observable behaviour
  local name="$1" wantrc="$2" frag="$3"; shift 3
  python3 "$PY" "$@" >/dev/null 2>"$TMP/em"; local rc=$?
  chk "$name" "$([ $rc = "$wantrc" ] && grep -qxE -- "$frag" "$TMP/em" && echo 1 || echo 0)"
}
emsg "bad JSON --body-json names the flag" 2 "fc_common: bad JSON for --body-json: Expecting property name enclosed in double quotes: line 1 column 2 \\(char 1\\)" emit --schema t/v1 --body-json '{' --out "$TMP/x.json"
chk "bad JSON exits at once (no second 'must be an object' message)" "$(grep -qF 'must be an object' "$TMP/em" && echo 0 || echo 1)"
emsg "duplicate-key diagnostic" 2 "fc_common: bad JSON for --body-json: duplicate key 'a'" emit --schema t/v1 --body-json '{"a":1,"a":2}' --out "$TMP/x.json"
emsg "NaN diagnostic" 2 "fc_common: bad JSON for --body-json: non-canonical JSON constant NaN" emit --schema t/v1 --body-json '{"a":NaN}' --out "$TMP/x.json"
emsg "1e999 diagnostic" 2 "fc_common: bad JSON for --body-json: non-finite number 1e999" emit --schema t/v1 --body-json '{"a":1e999}' --out "$TMP/x.json"
emsg "nesting diagnostic" 2 "fc_common: bad JSON for --body-json: JSON nesting too deep" emit --schema t/v1 --body-json "{\"a\":$deep}" --out "$TMP/x.json"
emsg "--body-json non-object diagnostic" 2 "fc_common: --body-json must be an object" emit --schema t/v1 --body-json '[1]' --out "$TMP/x.json"
emsg "reserved-key diagnostic lists keys in order" 2 "fc_common: reserved body key\(s\) refused: schema, body_hash" emit --schema t/v1 --body-json '{"body_hash":1,"schema":2}' --out "$TMP/x.json"
emsg "bad JSON --run-meta-json names the flag" 2 "fc_common: bad JSON for --run-meta-json: Expecting property name enclosed in double quotes: line 1 column 2 \\(char 1\\)" emit --schema t/v1 --body-json '{}' --run-meta-json '{' --out "$TMP/x.json"
emsg "--run-meta-json non-object diagnostic" 2 "fc_common: --run-meta-json must be an object" emit --schema t/v1 --body-json '{}' --run-meta-json '[1]' --out "$TMP/x.json"
emsg "code 3 diagnostic" 3 "fc_common: self-test failed; no result file written" emit --schema t/v1 --body-json '{}' --out "$TMP/x.json" --code 3
emsg "schema diagnostic quotes the value" 2 "fc_common: --schema must match <tool>/v<N>, got 'nov'" emit --schema nov --body-json '{}' --out "$TMP/x.json"
emsg "unencodable diagnostic" 2 "fc_common: body not encodable as UTF-8: .*surrogates not allowed" emit --schema t/v1 --body-json '{"a":"\ud800"}' --out "$TMP/x.json"
emsg "cannot-write diagnostic" 2 "fc_common: cannot write --out: \\[Errno 2\\] No such file or directory: '.*/nodir/.*'" emit --schema t/v1 --body-json '{}' --out "$TMP/nodir/x.json"
emsg "body-hash unreadable diagnostic" 2 "fc_common: cannot read doc: \\[Errno 2\\] No such file or directory: '.*no_such_doc.json'" body-hash --doc "$TMP/no_such_doc.json"
emsg "body-hash non-object diagnostic" 2 "fc_common: doc must be a JSON object" body-hash --doc "$TMP/arr.json"
emsg "body-hash duplicate key surfaces the loader message" 2 "fc_common: cannot read doc: duplicate key 'a'" body-hash --doc "$TMP/bd.json"
python3 "$PY" body-hash --doc "$TMP/a.json" >/dev/null 2>&1; rc=$?
chk "body-hash success exits 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
for f in present fabricated haystack; do
  args=(--present '["x"]' --fabricated '["q"]' --haystack '["x"]'); [ $f = present ] && args=(--present '"x"' --fabricated '["q"]' --haystack '["x"]')
  [ $f = fabricated ] && args=(--present '["x"]' --fabricated '"q"' --haystack '["x"]'); [ $f = haystack ] && args=(--present '["x"]' --fabricated '["q"]' --haystack '"x"')
  emsg "needle non-list --$f names its own flag" 2 "fc_common: --$f must be a JSON list of scalars \\(str/int/float/bool/null\\)" needle "${args[@]}"
  args2=(--present '["x"]' --fabricated '["q"]' --haystack '["x"]'); args2=("${args2[@]/\[\"$f\"\]/}")
done
emsg "needle bad JSON --present names the flag" 2 "fc_common: bad JSON for --present: Expecting value: line 1 column 2 \\(char 1\\)" needle --present '[' --fabricated '["q"]' --haystack '["x"]'
emsg "needle bad JSON --fabricated names the flag" 2 "fc_common: bad JSON for --fabricated: Expecting value: line 1 column 2 \\(char 1\\)" needle --present '["x"]' --fabricated '[' --haystack '["x"]'
emsg "needle bad JSON --haystack names the flag" 2 "fc_common: bad JSON for --haystack: Expecting value: line 1 column 2 \\(char 1\\)" needle --present '["x"]' --fabricated '["q"]' --haystack '['
emsg "needle empty-set diagnostic" 3 "fc_common: needle sets must be non-empty" needle --present '[]' --fabricated '["q"]' --haystack '["x"]'
emsg "needle missing-member diagnostic" 3 "fc_common: needle FAIL missing=\\['y'\\] fabricated_found=\\[\\]" needle --present '["x","y"]' --fabricated '["q"]' --haystack '["x"]'
emsg "needle fabricated-found diagnostic" 3 "fc_common: needle FAIL missing=\\[\\] fabricated_found=\\['q'\\]" needle --present '["x"]' --fabricated '["q"]' --haystack '["x","q"]'
# as-of / argparse surface
emsg "windowed diagnostic" 2 "fc_common: windowed tool requires --as-of YYYY-MM-DD \\(no default to today\\)" require-as-of --windowed
emsg "bad as-of diagnostic" 2 "fc_common: bad --as-of date" require-as-of --as-of 2026-02-30
python3 "$PY" require-as-of >/dev/null 2>&1; rc=$?
chk "require-as-of without flags -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
python3 "$PY" >/dev/null 2>"$TMP/em"; rc=$?
chk "no subcommand -> 2 with fc_common usage" "$([ $rc = 2 ] && grep -qE '^usage: fc_common \[' "$TMP/em" && echo 1 || echo 0)"
python3 "$PY" bogus >/dev/null 2>&1; rc=$?
chk "unknown subcommand -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
python3 "$PY" emit -h >/dev/null 2>&1; rc=$?
chk "--help -> 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
for spec in "emit --body-json {} --out $TMP/x.json" "emit --schema t/v1 --out $TMP/x.json" "emit --schema t/v1 --body-json {}" "body-hash" \
            "needle --fabricated [1] --haystack [1]" "needle --present [1] --haystack [1]" "needle --present [1] --fabricated [2]"; do
  python3 "$PY" $spec >/dev/null 2>&1; rc=$?
  chk "missing required option -> 2 ($spec)" "$([ $rc = 2 ] && echo 1 || echo 0)"
done
for c in 0 1; do
  rm -f "$TMP/c$c.json"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/c$c.json" --code $c; rc=$?
  chk "emit --code $c exits $c and writes the file" "$([ $rc = $c ] && [ -s "$TMP/c$c.json" ] && echo 1 || echo 0)"
done
for c in 2 5 -1; do
  rm -f "$TMP/c.json"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/c.json" --code $c; rc=$?
  chk "emit --code $c refused rc=2, no file" "$([ $rc = 2 ] && [ ! -e "$TMP/c.json" ] && echo 1 || echo 0)"
done
run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/cd.json"; rc=$?
chk "emit default code exits 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
# internal error exact diagnostic
python3 - "$LIB" >"$TMP/ie.out" 2>"$TMP/ie.err" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import fc_common
def boom(a):
    raise RuntimeError("injected")
fc_common.main.__globals__["cmd_needle"] = boom
sys.exit(fc_common.main(["needle", "--present", "[1]", "--fabricated", "[2]", "--haystack", "[1]"]))
PY
chk "internal error diagnostic exact" "$([ "$(cat "$TMP/ie.err")" = "fc_common: internal error: RuntimeError: injected" ] && echo 1 || echo 0)"
# determinism-check: diagnostics
python3 "$PY" determinism-check >/dev/null 2>"$TMP/em"; rc=$?
chk "determinism-check no command -> 2 + diagnostic" "$([ $rc = 2 ] && grep -qxF 'fc_common: no command given' "$TMP/em" && echo 1 || echo 0)"
python3 "$PY" determinism-check -- >/dev/null 2>&1; rc=$?
chk "determinism-check bare -- -> 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
python3 "$PY" determinism-check bash "$TMP/stable.sh" >/dev/null 2>&1; rc=$?
chk "determinism-check accepts the command without --" "$([ $rc = 0 ] && echo 1 || echo 0)"
emsg "cannot-run diagnostic" 4 "fc_common: cannot run command: \\[Errno 2\\] No such file or directory: '/nonexistent/cmd_zz'" determinism-check -- /nonexistent/cmd_zz
emsg "timeout diagnostic names run 1 and the bound" 4 "fc_common: no honest verdict: command run 1 timed out after 2s" determinism-check -- bash "$TMP/hang.sh"
pkill -x -f "sleep $SL1" 2>/dev/null
cat >"$TMP/second.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"
if [ -e "$FC_2ND" ]; then case "$FC_2ND_MODE" in rc5) exit 5;; rc3) exit 3;; hang) sleep $SL1 & wait;; array) echo '[1]' >"$FC_OUT";; junk) echo junk >"$FC_OUT";; esac; fi
: >"$FC_2ND"
S
export FC_2ND="$TMP/2nd.marker"
for mode in rc5 rc3 hang array junk; do
  rm -f "$FC_2ND"; export FC_2ND_MODE=$mode
  python3 "$PY" determinism-check -- bash "$TMP/second.sh" >/dev/null 2>"$TMP/em"; rc=$?
  case $mode in
    rc5)  want=4; frag="fc_common: no honest verdict: command run 2 rc=5 doc_present=True";;
    rc3)  want=3; frag="fc_common: command self-test failed \(rc=3\) run 2";;
    hang) want=4; frag="fc_common: no honest verdict: command run 2 timed out after 2s";;
    array) want=4; frag="fc_common: command run 2 wrote an unreadable doc: doc is not a JSON object";;
    junk) want=4; frag="fc_common: command run 2 wrote an unreadable doc: Expecting value: line 1 column 1 \\(char 0\\)";;
  esac
  chk "determinism-check second-run $mode -> $want, run 2 named" "$([ $rc = $want ] && grep -qxE -- "$frag" "$TMP/em" && echo 1 || echo 0)"
  pkill -x -f "sleep $SL1" 2>/dev/null
done
printf '#!/bin/bash\nexit 3\n' >"$TMP/rc3b.sh"
emsg "self-test-failed diagnostic names run 1" 3 "fc_common: command self-test failed \(rc=3\) run 1" determinism-check -- bash "$TMP/rc3b.sh"
emsg "no-honest-verdict names run 1, rc and doc presence" 4 "fc_common: no honest verdict: command run 1 rc=5 doc_present=True" determinism-check -- bash "$TMP/rc5.sh"
emsg "no-doc verdict says doc_present=False" 4 "fc_common: no honest verdict: command run 1 rc=0 doc_present=False" determinism-check -- bash "$TMP/nodoc0.sh"
# determinism-check: exact mismatch report (rc/body_hash line + unified diff, sorted keys, raw UTF-8, n=1 context)
cat >"$TMP/nd.sh" <<'S'
#!/bin/bash
n=é1; [ -e "$FC_ND" ] && n=é2
printf '{"z":9,"n":"%s","m":5,"a":"x","schema":"t/v1","run_meta":{"r":%s}}\n' "$n" "$RANDOM" >"$FC_OUT"
: >"$FC_ND"
S
export FC_ND="$TMP/nd.marker"; rm -f "$FC_ND"
python3 "$PY" determinism-check -- bash "$TMP/nd.sh" >/dev/null 2>"$TMP/nd.err"; rc=$?
{ head -1 "$TMP/nd.err" | grep -qE '^fc_common: nondeterministic rc/body_hash 0/[0-9a-f]{64} != 0/[0-9a-f]{64}$'; } && l1=1 || l1=0
tail -n +2 "$TMP/nd.err" >"$TMP/nd.diff"
cat >"$TMP/nd.want" <<'W'
--- run1
+++ run2
@@ -3,3 +3,3 @@
  "m": 5,
- "n": "é1",
+ "n": "é2",
  "schema": "t/v1",
W
chk "determinism-check mismatch report exact (header + unified diff, n=1, sorted, raw UTF-8)" "$([ $rc = 1 ] && [ $l1 = 1 ] && cmp -s "$TMP/nd.diff" "$TMP/nd.want" && echo 1 || echo 0)"
h1="$(head -1 "$TMP/nd.err" | sed -E 's|.* 0/([0-9a-f]{64}) != 0/([0-9a-f]{64})$|\1|')"; h2="$(head -1 "$TMP/nd.err" | sed -E 's|.* 0/([0-9a-f]{64}) != 0/([0-9a-f]{64})$|\2|')"
chk "mismatch report names run1 hash first, run2 hash second, and they differ" "$([ -n "$h1" ] && [ "$h1" != "$h2" ] && echo 1 || echo 0)"
rm -f "$FC_FLIP"; python3 "$PY" determinism-check -- bash "$TMP/rcflip.sh" >/dev/null 2>"$TMP/flip.err"
chk "rc mismatch report: rc 0 for run1, rc 1 for run2, equal hashes" "$(head -1 "$TMP/flip.err" | grep -qE '^fc_common: nondeterministic rc/body_hash 0/([0-9a-f]{64}) != 1/\1$' && echo 1 || echo 0)"
cat >"$TMP/big.sh" <<'S'
#!/bin/bash
v=a; [ -e "$FC_BIG" ] && v=b
python3 - "$v" >"$FC_OUT" <<'P'
import json,sys
print(json.dumps({"k%03d" % i: sys.argv[1] for i in range(100)}))
P
: >"$FC_BIG"
S
export FC_BIG="$TMP/big.marker"; rm -f "$FC_BIG"
python3 "$PY" determinism-check -- bash "$TMP/big.sh" >/dev/null 2>"$TMP/big.err"; rc=$?
chk "mismatch diff is capped: 1 header + 40 diff lines" "$([ $rc = 1 ] && [ "$(wc -l <"$TMP/big.err")" = 41 ] && echo 1 || echo 0)"
# run_meta is excluded from the reported body (run_meta-only difference is stable AND not shown)
cat >"$TMP/rm.sh" <<'S'
#!/bin/bash
printf '{"a":1,"schema":"t/v1","run_meta":{"r":%s}}\n' "$RANDOM" >"$FC_OUT"
S
python3 "$PY" determinism-check -- bash "$TMP/rm.sh" >/dev/null 2>&1; rc=$?
chk "run_meta-only difference is stable (0)" "$([ $rc = 0 ] && echo 1 || echo 0)"
# ---- process-group internals ----
SL4=$((SL1+3)); SL5=$((SL1+4)); export SL4 SL5
export FC_MARK="$TMP/term.mark"
cat >"$TMP/termmark.sh" <<'S'
#!/bin/bash
trap 'sleep 1; echo t >"$FC_MARK"; exit 0' TERM
sleep $SL4 &
wait
S
rm -f "$FC_MARK"; timeout 30 python3 "$PY" determinism-check -- bash "$TMP/termmark.sh" >/dev/null 2>&1; rc=$?
chk "timeout: SIGTERM is delivered first and the grace lets a 1s cleanup finish (marker written)" "$([ $rc = 4 ] && [ -e "$FC_MARK" ] && echo 1 || echo 0)"
pkill -x -f "sleep $SL4" 2>/dev/null
cat >"$TMP/termfast.sh" <<'S'
#!/bin/bash
trap 'sleep 0.3; echo t >"$FC_MARK"; exit 0' TERM
sleep $SL4 &
wait
S
rm -f "$FC_MARK"; t0=$(date +%s%N)
FC_DETERMINISM_TIMEOUT_S=1 timeout 30 python3 "$PY" determinism-check -- bash "$TMP/termfast.sh" >/dev/null 2>&1; rc=$?
ms=$(( ($(date +%s%N)-t0)/1000000 ))
chk "graceful TERM exit is noticed promptly (<1.8s total for a 1s bound; measured ${ms}ms)" "$([ $rc = 4 ] && [ -e "$FC_MARK" ] && [ $ms -lt 1800 ] && echo 1 || echo 0)"
pkill -x -f "sleep $SL4" 2>/dev/null
t0=$(date +%s%N); timeout 30 python3 "$PY" determinism-check -- bash "$TMP/stable.sh" >/dev/null 2>&1; rc=$?
ms=$(( ($(date +%s%N)-t0)/1000000 ))
chk "normal command returns without waiting the kill grace (<3s for 2 runs; measured ${ms}ms)" "$([ $rc = 0 ] && [ $ms -lt 3000 ] && echo 1 || echo 0)"
t0=$(date +%s%N); timeout 30 python3 "$PY" determinism-check -- bash "$TMP/hangterm.sh" >/dev/null 2>&1; rc=$?
ms=$(( ($(date +%s%N)-t0)/1000000 ))
chk "TERM-ignoring hang: SIGKILL only after the 2s grace (>=3.8s total for a 2s bound; measured ${ms}ms)" "$([ $rc = 4 ] && [ $ms -ge 3800 ] && echo 1 || echo 0)"
pkill -x -f "sleep $SL2" 2>/dev/null
cat >"$TMP/leak2.sh" <<'S'
#!/bin/bash
( trap '' TERM; exec sleep $SL5 ) >/dev/null 2>&1 &
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"
S
timeout 30 python3 "$PY" determinism-check -- bash "$TMP/leak2.sh" >/dev/null 2>&1; rc=$?
needle_control "$SL5"
chk "finished command's TERM-ignoring stray child is SIGKILLed after the grace (control needle: pgrep saw it)" "$([ $rc = 0 ] && [ "$NEEDLE_SEEN" = 1 ] && ! pgrep -x -f "sleep $SL5" >/dev/null && echo 1 || echo 0)"
pkill -x -f "sleep $SL5" 2>/dev/null
# in-process unit checks of the process-group helpers and constants
python3 - "$LIB" >"$TMP/unit.out" 2>&1 <<'PY'
import os, shutil, signal, subprocess, sys, tempfile, time
sys.path.insert(0, sys.argv[1])
import fc_common as f
res = []
def ok(name, cond): res.append((name, bool(cond)))
os.environ.pop("FC_DETERMINISM_TIMEOUT_S", None)
ok("default timeout is 60", f.DETERMINISM_TIMEOUT_DEFAULT_S == 60 and f._timeout_from_env() == 60)
ok("kill grace is 2", f.DETERMINISM_KILL_AFTER_S == 2)
os.environ["FC_DETERMINISM_TIMEOUT_S"] = "7"; ok("env timeout parsed", f._timeout_from_env() == 7)
del os.environ["FC_DETERMINISM_TIMEOUT_S"]
try: f.canon(float("nan")); ok("canon refuses NaN", False)
except ValueError: ok("canon refuses NaN", True)
# _group_alive: live group true and untouched, dead group false, PermissionError counts as alive
p = subprocess.Popen(["sleep", "30"], start_new_session=True, preexec_fn=lambda: signal.signal(signal.SIGHUP, signal.SIG_DFL))
ok("_group_alive true for a live group", f._group_alive(p.pid) is True)
time.sleep(0.2); ok("_group_alive probe does not signal the group", p.poll() is None)
p.kill(); p.wait(); time.sleep(0.1)
ok("_group_alive false for a dead group", f._group_alive(p.pid) is False)
real = os.killpg
def perm(pg, sig): raise PermissionError()
f.os.killpg = perm; ok("_group_alive PermissionError -> True", f._group_alive(12345) is True); f.os.killpg = real
# _reap_group never signals pgid <= 1, does signal pgid 2
calls = []
def rec(pg, sig): calls.append((pg, sig)); raise ProcessLookupError()
class FP:
    def poll(self): return 0
    def wait(self): return 0
f.os.killpg = rec
for bad in (1, 0, -1, -5): f._reap_group(FP(), bad)
ok("_reap_group never signals pgid <= 1", calls == [])
f._reap_group(FP(), 2)
ok("_reap_group signals pgid 2 with SIGTERM first", calls[:1] == [(2, signal.SIGTERM)])
f.os.killpg = real
# _reap_group reaps the leader (no zombie left behind) even when it ignores TERM
f.DETERMINISM_KILL_AFTER_S = 0.3
z = subprocess.Popen(["bash", "-c", "trap '' TERM; while :; do sleep 1; done"], start_new_session=True)
time.sleep(0.3); f._reap_group(z, z.pid)
ok("_reap_group reaps a TERM-ignoring leader (no /proc entry left)", not os.path.exists("/proc/%d" % z.pid))
f.DETERMINISM_KILL_AFTER_S = 2
# emit restores the process umask
old = os.umask(0o027); d = tempfile.mkdtemp()
f.main(["emit", "--schema", "t/v1", "--body-json", "{}", "--out", d + "/o.json"])
now = os.umask(old); ok("emit restores the caller's umask", now == 0o027)
shutil.rmtree(d, ignore_errors=True)  # T014 round-12 MINOR: this test's own scratch dir must not leak
for n, c in res: print(("OK   " if c else "BAD  ") + n)
sys.exit(0 if all(c for _, c in res) else 1)
PY
rc=$?
chk "in-process unit checks (constants, canon NaN, _group_alive, _reap_group guard, umask restore)" "$([ $rc = 0 ] && echo 1 || echo 0)"
[ $rc = 0 ] || sed 's/^/    /' "$TMP/unit.out"

# ---- T014 round-10 remediation (MINOR-7): waitid/WNOWAIT handoff mechanism, verified directly ----
# Deterministically demonstrates the fix's mechanism (never dependent on rare kernel pid-reuse timing):
# (1) _leader_exited_unreaped() never disturbs a still-running process; (2) once exited, it reports True
# WITHOUT reaping -- the leader is still a genuine, waitable zombie (State: Z) at that instant, proven via
# /proc/<pid>/status, not merely asserted; (3) a real reap afterwards still returns the correct rc, and
# only THEN does /proc/<pid> disappear; (4) a pid that is not our own child (ChildProcessError) is
# treated as "exited"; (5) the load-bearing proof for the fix itself -- _run_bounded() never reaps the
# leader before handing off to _reap_group(): a spy wrapper around _reap_group() records
# `proc.returncode` at the exact moment it receives the proc object, and it MUST still be None there.
# Mutation-kill proof (run once, ad hoc, to author this test -- not re-run every invocation): swapping in
# the ORIGINAL, pre-fix `_run_bounded` (its own destructive `proc.wait(timeout=timeout_s)` BEFORE calling
# `_reap_group`) makes assertion (5) observably FAIL (`proc.returncode` is already the real rc, not None,
# at hand-off time) -- confirming this is a genuine discriminator of the fix, not a tautology.
python3 - "$LIB" >"$TMP/wnowait.out" 2>&1 <<'PY'
import os, subprocess, sys, time
sys.path.insert(0, sys.argv[1])
import fc_common as f
res = []
def ok(name, cond): res.append((name, bool(cond)))

p = subprocess.Popen(["sleep", "5"], start_new_session=True)
ok("_leader_exited_unreaped False while running", f._leader_exited_unreaped(p.pid) is False)
ok("probe left it running (poll() still None)", p.poll() is None)
p.kill(); p.wait()

p2 = subprocess.Popen(["bash", "-c", "exit 5"], start_new_session=True)
deadline = time.time() + 5
seen = False
while time.time() < deadline:
    if f._leader_exited_unreaped(p2.pid):
        seen = True
        break
    time.sleep(0.01)
ok("_leader_exited_unreaped True once exited", seen)
state = None
try:
    with open("/proc/%d/status" % p2.pid) as fh:
        for line in fh:
            if line.startswith("State:"):
                state = line.split(":", 1)[1].strip()
                break
except FileNotFoundError:
    pass
ok("leader still a zombie (State: Z...) at the moment WNOWAIT confirmed exit -- not yet reaped", bool(state) and state.startswith("Z"))
rc2 = p2.wait()
ok("real reap after WNOWAIT confirmation still returns the correct rc", rc2 == 5)
ok("leader fully gone only AFTER the real reap", not os.path.exists("/proc/%d" % p2.pid))

ok("_leader_exited_unreaped(1) (not our child) -> True", f._leader_exited_unreaped(1) is True)

calls = []
real_reap_group = f._reap_group
def spy_reap_group(proc, pgid):
    calls.append(proc.returncode)
    return real_reap_group(proc, pgid)
f._reap_group = spy_reap_group
rc3 = f._run_bounded(["bash", "-c", "exit 9"], dict(os.environ), 5)
f._reap_group = real_reap_group
ok("_run_bounded returns the real rc (via _reap_group's own reap, not its own)", rc3 == 9)
ok("_reap_group was invoked exactly once", len(calls) == 1)
ok("at the moment _reap_group was handed the proc, it was NOT yet reaped by _run_bounded (returncode None)", calls[0] is None)

for n, c in res: print(("OK   " if c else "BAD  ") + n)
sys.exit(0 if all(c for _, c in res) else 1)
PY
rc=$?
chk "waitid/WNOWAIT handoff mechanism: leader stays an un-reaped zombie until _reap_group's own real wait (T014 R10 MINOR-7)" "$([ $rc = 0 ] && echo 1 || echo 0)"
[ $rc = 0 ] || sed 's/^/    /' "$TMP/wnowait.out"

# leak check independent of the temp-file prefix: nothing but the directory we made remains
mkdir -p "$TMP/cl2/outd"; run emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/cl2/outd"
chk "failed emit leaves no stray entry of any name next to --out" "$([ "$(ls -A "$TMP/cl2" | tr '\n' ,)" = "outd," ] && echo 1 || echo 0)"

# ---- round 5b: kill the 4 survivors proven NOT equivalent + process-leak assertion ----
# py102: the temp-file prefix is an observable contract (stderr text / leftover after SIGKILL)
python3 - "$LIB" >"$TMP/r5b1.out" 2>&1 <<'PY'
import os, shutil, sys, tempfile
sys.path.insert(0, sys.argv[1])
import fc_common as f
seen = []
real = tempfile.mkstemp
def rec(*a, **k): seen.append(k.get("prefix")); return real(*a, **k)
f.tempfile.mkstemp = rec
d = tempfile.mkdtemp()
rc = f.main(["emit", "--schema", "t/v1", "--body-json", "{}", "--out", d + "/o.json"])
print("OK" if rc == 0 and seen == [".fc_emit."] else "BAD %r %r" % (rc, seen))
shutil.rmtree(d, ignore_errors=True)  # T014 round-12 MINOR: this test's own scratch dir must not leak
PY
chk "emit temp-file prefix is exactly '.fc_emit.' (leftover-name contract)" "$([ "$(tail -1 "$TMP/r5b1.out")" = OK ] && echo 1 || echo 0)"
if [ "$(id -u)" != 0 ]; then
  mkdir -p "$TMP/ro5b"; chmod 500 "$TMP/ro5b"
  python3 "$PY" emit --schema t/v1 --body-json '{"a":1}' --out "$TMP/ro5b/o.json" 2>"$TMP/ro5b.err"; rc=$?
  chmod 700 "$TMP/ro5b"
  chk "unwritable --out dir: stderr names '.fc_emit.<random>' temp path (no '~')" "$([ $rc != 0 ] && grep -Eq '\.fc_emit\.[A-Za-z0-9_]' "$TMP/ro5b.err" && ! grep -q '\.fc_emit\.~' "$TMP/ro5b.err" && echo 1 || echo 0)"
fi
# py196: sleep(0.05) is the poll interval of the reap loop (no CPU-burning busy-wait); pin it deterministically
python3 - "$LIB" >"$TMP/r5b2.out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import fc_common as f
sleeps = []
f.time.sleep = lambda t: sleeps.append(t)
alive = iter([True, True, True, False])
f._group_alive = lambda pg: next(alive)
class P:
    def poll(self): return 0
    def wait(self): return 0
f.os.killpg = lambda pg, sig: None
f._reap_group(P(), 4242)
print("OK" if sleeps == [0.05, 0.05, 0.05] else "BAD %r" % sleeps)
PY
chk "reap loop polls with sleep(0.05) between group-alive probes (no busy-wait)" "$([ "$(tail -1 "$TMP/r5b2.out")" = OK ] && echo 1 || echo 0)"
# py239: the command sees FC_OUT basenames run1.json / run2.json
cat >"$TMP/fcout.sh" <<'S'
#!/bin/bash
basename "$FC_OUT" >>"$FC_NAMES"
echo '{"a":1}' >"$FC_OUT"
S
FC_NAMES="$TMP/names5b"; export FC_NAMES; : >"$FC_NAMES"
timeout 30 python3 "$PY" determinism-check -- bash "$TMP/fcout.sh" >/dev/null 2>&1
chk "determinism-check hands the command FC_OUT basenames run1.json then run2.json" "$([ "$(tr '\n' ' ' <"$FC_NAMES")" = "run1.json run2.json " ] && echo 1 || echo 0)"
unset FC_NAMES
# sh7: FC_LIB_DIR fallback to $0 when BASH_SOURCE is unset (zsh)
if command -v zsh >/dev/null 2>&1; then
  zd="$(cd "$TMP" && zsh -c ". '$SH'; echo \$FC_LIB_DIR" 2>/dev/null)"
  chk "sourced under zsh (BASH_SOURCE unset): FC_LIB_DIR resolves to the lib dir, not cwd" "$([ "$zd" = "$(cd "$LIB" && pwd)" ] && echo 1 || echo 0)"
else
  echo "SKIP: zsh not installed (reason: shell_not_present) - sh7 \$0 fallback untestable here"
fi
# ---- round 6: R5-F3 (body-hash unencodable doc = exit 2 like emit) + F13 (body-hash --verify) ----
printf '{"a":"\\ud800"}' >"$TMP/sur.json"
python3 "$PY" body-hash --doc "$TMP/sur.json" >"$TMP/r6.out" 2>"$TMP/r6.err"; rc=$?
chk "R5-F3 body-hash on a doc with a lone surrogate exits 2 (same class as emit), not 4" "$([ $rc = 2 ] && echo 1 || echo 0)"
chk "R5-F3 the surrogate refusal names the encoding problem and prints no hash" "$(grep -q 'not encodable' "$TMP/r6.err" && [ ! -s "$TMP/r6.out" ] && echo 1 || echo 0)"
python3 "$PY" body-hash --doc "$TMP/sur.json" --verify >/dev/null 2>&1; rc=$?
chk "R5-F3 body-hash --verify on the surrogate doc also exits 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
# verify: equal -> 0
python3 "$PY" emit --schema t/v1 --body-json '{"a":1,"b":[1,2]}' --run-meta-json '{"h":"x"}' --out "$TMP/v.json"
python3 "$PY" body-hash --doc "$TMP/v.json" --verify >"$TMP/v.out" 2>"$TMP/v.err"; rc=$?
chk "F13 --verify on an intact doc exits 0" "$([ $rc = 0 ] && echo 1 || echo 0)"
vh="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["body_hash"])' "$TMP/v.json")"
chk "F13 --verify success prints the hash" "$(grep -q "$vh" "$TMP/v.out" && echo 1 || echo 0)"
# tampered body -> 1 with both hashes
sed 's/"a":1/"a":9/' "$TMP/v.json" >"$TMP/vt.json"
python3 "$PY" body-hash --doc "$TMP/vt.json" --verify >"$TMP/vt.out" 2>"$TMP/vt.err"; rc=$?
rh="$(python3 "$PY" body-hash --doc "$TMP/vt.json")"
chk "F13 --verify on a tampered body exits 1 (a finding)" "$([ $rc = 1 ] && echo 1 || echo 0)"
chk "F13 mismatch prints both the stored and the recomputed hash" "$(cat "$TMP/vt.out" "$TMP/vt.err" | grep -q "$vh" && cat "$TMP/vt.out" "$TMP/vt.err" | grep -q "$rh" && [ "$vh" != "$rh" ] && echo 1 || echo 0)"
# tampered run_meta -> still 0, hash unchanged
sed 's/"h":"x"/"h":"CHANGED"/' "$TMP/v.json" >"$TMP/vm.json"
python3 "$PY" body-hash --doc "$TMP/vm.json" --verify >/dev/null 2>&1; rc=$?
chk "F13 tampered run_meta does not change the hash: --verify exits 0" "$([ $rc = 0 ] && ! cmp -s "$TMP/v.json" "$TMP/vm.json" && echo 1 || echo 0)"
chk "F13 tampered run_meta recomputes the identical hash" "$([ "$(python3 "$PY" body-hash --doc "$TMP/vm.json")" = "$vh" ] && echo 1 || echo 0)"
# no stored hash / non-string stored hash / bad doc -> 2
printf '{"a":1}' >"$TMP/nh.json"
python3 "$PY" body-hash --doc "$TMP/nh.json" --verify >/dev/null 2>"$TMP/nh.err"; rc=$?
chk "F13 --verify with no stored body_hash exits 2" "$([ $rc = 2 ] && grep -q 'body_hash' "$TMP/nh.err" && echo 1 || echo 0)"
printf '{"a":1,"body_hash":5}' >"$TMP/ns.json"
python3 "$PY" body-hash --doc "$TMP/ns.json" --verify >/dev/null 2>&1; rc=$?
chk "F13 --verify with a non-string stored body_hash exits 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
python3 "$PY" body-hash --doc "$TMP/absent.json" --verify >/dev/null 2>&1; rc=$?
chk "F13 --verify on a missing doc exits 2" "$([ $rc = 2 ] && echo 1 || echo 0)"
python3 "$PY" body-hash --doc "$TMP/v.json" >"$TMP/plain.out" 2>&1; rc=$?
chk "F13 body-hash without --verify still prints only the hash (exit 0)" "$([ $rc = 0 ] && [ "$(cat "$TMP/plain.out")" = "$vh" ] && echo 1 || echo 0)"

# exact message shapes (kill trailing-text mutations of the refusal/finding lines)
chk "R5-F3 surrogate refusal line is exactly 'fc_common: body not encodable as UTF-8: <codec error>'" "$([ "$(head -1 "$TMP/r6.err")" = "fc_common: body not encodable as UTF-8: 'utf-8' codec can't encode character '\\ud800' in position 6: surrogates not allowed" ] && echo 1 || echo 0)"
chk "F13 no-stored-hash refusal line is exactly the documented message" "$([ "$(cat "$TMP/nh.err")" = "fc_common: --verify needs a stored string body_hash in the doc" ] && echo 1 || echo 0)"
chk "F13 mismatch line is exactly 'fc_common: body_hash mismatch: stored=<h> recomputed=<h>'" "$([ "$(cat "$TMP/vt.out")" = "fc_common: body_hash mismatch: stored=$vh recomputed=$rh" ] && echo 1 || echo 0)"

# ---- round 7: stored-hash validity family (R6-F3/R6-F4): valid = 64 lowercase hex; anything else = exit 2 (malformed), a
#      well-formed hash of the wrong value = exit 1 ----
vmal() { # $1 label  $2 JSON literal for the stored value ; expects rc 2 and no stdout
  printf '{"a":1,"body_hash":%s}' "$2" >"$TMP/mal.json"
  python3 "$PY" body-hash --doc "$TMP/mal.json" --verify >"$TMP/mal.out" 2>"$TMP/mal.err"; mrc=$?
  chk "R7 stored body_hash $1 exits 2" "$([ $mrc = 2 ] && [ ! -s "$TMP/mal.out" ] && echo 1 || echo 0)"
}
UP="$(printf '%s' "$vh" | tr 'a-f' 'A-F')"
[ "$UP" != "$vh" ] || UP="A${vh#?}"
vmal "upper-cased" "\"$UP\""
MIX="F${vh#?}"; [ "$MIX" != "$vh" ] || MIX="a${vh#?}"; MIX="$(printf '%s' "$MIX" | sed 's/^./\U&/')"
vmal "mixed-case (first char upper)" "\"$MIX\""
vmal "space-padded" "\" $vh \""
vmal "trailing-newline" "\"$vh\\n\""
vmal "truncated (63 chars)" "\"${vh%?}\""
vmal "too long (65 chars)" "\"${vh}0\""
vmal "non-hex (g)" "\"g${vh#?}\""
vmal "0x-prefixed 64" "\"0x${vh#??}\""
vmal "unicode look-alike digit (arabic-indic 0)" "\"\\u0660${vh#?}\""
vmal "a list" "[]"
vmal "null" "null"
vmal "true" "true"
vmal "a float" "1.5"
vmal "an object" "{}"
vmal "a 1-char string" "\"a\""
chk "R7 malformed-hash refusal line is exactly the documented message" "$([ "$(cat "$TMP/mal.err")" = "fc_common: --verify: stored body_hash is not 64 lowercase hex characters" ] && echo 1 || echo 0)"
printf '{"a":1,"body_hash":""}' >"$TMP/eh.json"
python3 "$PY" body-hash --doc "$TMP/eh.json" --verify >/dev/null 2>"$TMP/eh.err"; rc=$?
chk "R6-F4 empty stored body_hash exits 2 with the documented no-stored-hash message (not the malformed one)" "$([ $rc = 2 ] && [ "$(cat "$TMP/eh.err")" = "fc_common: --verify needs a stored string body_hash in the doc" ] && echo 1 || echo 0)"
printf '{"a":1,"body_hash":"%064d"}' 0 >"$TMP/wf.json"
python3 "$PY" body-hash --doc "$TMP/wf.json" --verify >/dev/null 2>&1; rc=$?
chk "R7 a well-formed but wrong lowercase stored hash exits 1 (mismatch), not 2" "$([ $rc = 1 ] && echo 1 || echo 0)"
python3 - "$TMP/v.json" "$TMP/up.json" <<'PYE'
import json,sys
d=json.load(open(sys.argv[1])); d["body_hash"]=d["body_hash"].upper(); open(sys.argv[2],"w").write(json.dumps(d))
PYE
python3 "$PY" body-hash --doc "$TMP/up.json" --verify >/dev/null 2>&1; rc=$?
chk "R6-F3 emit-produced doc with its hash upper-cased is NOT accepted (exit 2, never 0)" "$([ $rc = 2 ] && echo 1 || echo 0)"

# R7-m22: a well-formed hash differing from the recomputed one in exactly ONE hex char (first / middle / last) is a mismatch (1)
for pos in 0 31 63; do
  python3 - "$TMP/v.json" "$TMP/one.json" "$pos" <<'PYE'
import json,sys
d=json.load(open(sys.argv[1])); h=d["body_hash"]; p=int(sys.argv[3])
d["body_hash"]=h[:p]+("0" if h[p]!="0" else "1")+h[p+1:]
open(sys.argv[2],"w").write(json.dumps(d))
PYE
  python3 "$PY" body-hash --doc "$TMP/one.json" --verify >/dev/null 2>&1; rc=$?
  chk "R7 stored hash differing from the recomputed one in only hex char #$pos exits 1 (mismatch)" "$([ $rc = 1 ] && echo 1 || echo 0)"
done

# ---- round 8: SIGCHLD inherited as SIG_IGN must never fabricate a clean rc=0 (fail closed instead) ----
# Root cause (independently reproduced + fixed, T014 round-11 review): a caller that has SIGCHLD=SIG_IGN
# in effect before spawning `python3 ... determinism-check` (POSIX preserves SIG_IGN across exec, so
# `signal.signal(signal.SIGCHLD, signal.SIG_IGN)` then `os.execvp("python3", [... "determinism-check",
# ...])` carries it straight into this interpreter) makes the kernel auto-reap and discard a spawned
# child's exit status the INSTANT it exits -- no zombie is ever created. `_leader_exited_unreaped()`'s
# ChildProcessError branch already treats that as "exited" (by design, for its own narrower question), and
# CPython's own `Popen.poll()`/`wait()` -- called later inside `_reap_group()` for the REAL destructive
# reap -- silently fabricate `returncode = 0` on the identical ECHILD condition (CPython's own
# subprocess.py: "This happens if SIGCLD is set to be ignored ... This child is dead, we can't get the
# status." -> sts = 0), so an ALWAYS-FAILING command (real rc=5) could be reported as a stable, clean
# rc=0 -- a PASS-bluff. Fixed by (1) _run_bounded resetting SIGCHLD to SIG_DFL before every spawn, so the
# kernel keeps a genuine zombie to reap, and (2) belt-and-suspenders, `_leader_reap_honest()`
# independently re-confirming (a second, non-destructive WNOWAIT probe) that the exit just observed
# really was a real zombie -- if not, `_run_bounded` returns NO_HONEST_VERDICT and never lets
# `proc.returncode` (which may by then be CPython's own fabricated 0) reach the caller.
#
# RED, independently confirmed once ad hoc to author this test (not re-run every invocation): the exact
# CLI-level repro immediately below, run against the ORIGINAL pre-fix lib/fc_common.py (git-stashed fix),
# observably exits 0 -- the false clean verdict for a command whose real exit code is 5. Applying the fix
# and re-running the identical repro exits 4. This confirms the CLI-level test is a genuine discriminator.
cat >"$TMP/sigchld_rc5.sh" <<'S'
#!/bin/bash
python3 "$FC_PY" emit --schema t/v1 --body-json '{"a":1}' --out "$FC_OUT"; exit 5
S
cat >"$TMP/sigchld_wrapper.py" <<'PYW'
import os, signal, sys
signal.signal(signal.SIGCHLD, signal.SIG_IGN)
# invoked as "bash <script>", matching this file's own convention elsewhere -- a bare heredoc-written
# script has no executable bit of its own, so this must not rely on one (as fc_common.py's own
# determinism-check, in turn, execs the given argv verbatim rather than through a shell).
os.execvp("python3", ["python3", sys.argv[1], "determinism-check", "--", "bash", sys.argv[2]])
PYW
FC_PY="$PY" timeout 30 python3 "$TMP/sigchld_wrapper.py" "$PY" "$TMP/sigchld_rc5.sh" >/dev/null 2>"$TMP/sigchld.err"; rc=$?
chk "SIGCHLD=SIG_IGN inherited via execvp: always-rc5 command -> 4, NEVER 0 (no fabricated verdict)" "$([ $rc = 4 ] && echo 1 || echo 0)"
chk "SIGCHLD=SIG_IGN case: an honest 'no honest verdict' diagnostic is printed (never silently clean)" "$(grep -q 'no honest verdict' "$TMP/sigchld.err" && echo 1 || echo 0)"

# Belt-and-suspenders layer, exercised directly and independently of fix (1): even if _run_bounded's own
# SIGCHLD reset call were neutered (simulating "the reset was attempted but did not, for whatever reason,
# actually take effect"), _leader_reap_honest() must STILL independently detect the genuine (real, not
# mocked) SIGCHLD=SIG_IGN condition via its own raw os.waitid(WNOWAIT) probe and fail closed with the
# NO_HONEST_VERDICT sentinel -- never falling through to CPython's own fabricated rc=0.
python3 - "$LIB" >"$TMP/sigchld_unit.out" 2>&1 <<'PY'
import os, signal, sys
sys.path.insert(0, sys.argv[1])
import fc_common as f
res = []
def ok(name, cond): res.append((name, bool(cond)))

real_signal = f.signal.signal
f.signal.signal = lambda *a, **k: None  # neuter _run_bounded's own SIGCHLD-reset call
real_signal(signal.SIGCHLD, signal.SIG_IGN)  # genuinely (not mocked) put this process into the hazard state
try:
    rc = f._run_bounded(["bash", "-c", "exit 5"], dict(os.environ), 5)
    ok("_run_bounded returns NO_HONEST_VERDICT (never 0, never the real rc) when SIGCHLD stays SIG_IGN "
       "even with the reset call itself neutered", rc is f.NO_HONEST_VERDICT)
finally:
    real_signal(signal.SIGCHLD, signal.SIG_DFL)
    f.signal.signal = real_signal

for n, c in res: print(("OK   " if c else "BAD  ") + n)
sys.exit(0 if all(c for _, c in res) else 1)
PY
rc=$?
chk "SIGCHLD belt-and-suspenders: _leader_reap_honest independently fails closed even if the reset itself is bypassed" "$([ $rc = 0 ] && echo 1 || echo 0)"
[ $rc = 0 ] || sed 's/^/    /' "$TMP/sigchld_unit.out"

# process-leak: nothing this test spawned may survive (children name $TMP or a unique sleep number)
reap_children; sleep 0.3

# §11.4.273 control needle for the "pgrep -f "$TMP"" query class specifically -- this is a
# DIFFERENT match class from needle_control()'s "sleep N"-by-exact-name class (it matches ANY
# process whose cmdline embeds the temp-dir path, never positively demonstrated above), so an
# empty result for it alone would be unproven absence, not proof (§11.4.273). Spawn a throwaway
# process whose argv literally embeds "$TMP", confirm this exact query finds it, then kill+reap
# it BEFORE taking the real leak count below (so the needle's own process is never itself
# miscounted as a leak).
#
# A single-statement `bash -c "sleep 5 # ...$TMP"` does NOT work here: bash's own tail-call
# optimization for a -c script consisting of exactly one simple command execve()s directly into
# `sleep 5`, so the running process's real argv becomes only ["sleep","5"] -- the comment (and
# $TMP) never survives into the process the kernel actually reports, and pgrep -f "$TMP" then
# finds nothing even though the needle "ran" (independently reproduced+confirmed before writing
# this fix, not assumed). Using a MULTI-statement script (a trailing no-op after sleep) disables
# that optimization, so bash's own process persists for the whole sleep, and a custom $0 (the
# extra positional arg to `bash -c script name`) sets its OWN argv[0] to the literal $TMP path --
# reliably visible to `pgrep -f "$TMP"` for the full duration.
bash -c 'sleep 5; :' "$TMP/tmpneedle-marker" &
_tmpneedle_pid=$!
TMPNEEDLE_SEEN=0
for _i in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "$TMP" >/dev/null 2>&1 && { TMPNEEDLE_SEEN=1; break; }
  sleep 0.05
done
kill -9 "$_tmpneedle_pid" 2>/dev/null; wait "$_tmpneedle_pid" 2>/dev/null
reap_children; sleep 0.3

leak="$(pgrep -f "$TMP" 2>/dev/null | wc -l)"
for _v in SL1 SL2 SL3 SL4 SL5; do eval "_n=\${$_v:-}"; [ -n "$_n" ] && leak=$((leak+$(pgrep -x -f "sleep $_n" 2>/dev/null | wc -l))); done
chk "no child spawned by this test survives it (leaked=$leak, control needle: pgrep -f \"\$TMP\" saw it: $TMPNEEDLE_SEEN)" "$([ "$TMPNEEDLE_SEEN" = 1 ] && [ "$leak" = 0 ] && echo 1 || echo 0)"

unset FC_DETERMINISM_TIMEOUT_S

echo "SUMMARY: $((N-FAIL+0)) pass-lines / FAIL=$FAIL of $N assertions"
[ "$FAIL" = 0 ]
