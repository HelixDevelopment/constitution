#!/usr/bin/env bash
# test_parse_gate_wrappers.sh -- behaviour + paired-mutation test of the gate-registration recognition in
#                                scripts/catalog-engine/lib/parse_gate.py  (ATM-1473)
#
# Purpose
#   A pre-build gate can be registered three ways: a literal `echo -n "  CM-X: ..."` banner (F1), a call of a shell
#   helper that takes the gate name as its FIRST ARGUMENT and prints the banner from it (F2, e.g. `_r5_run_gate "CM-X" ...`),
#   or a `log_pass|log_fail "CM-X: ..."` verdict line with no banner (F3). Before ATM-1473 only F1 was recognised, so every
#   F2/F3 gate was invisible to the catalog. This test proves, through the parser's real import path and real command
#   line, that F2 and F3 are recognised (golden), that malformed or look-alike input is refused or ignored (refusals),
#   that an UNRECOGNISED helper shape is reported instead of silently dropped (blind-spot guard), and -- by running the
#   same checks against deliberately broken copies of the parser -- that every check can fail (paired mutants,
#   Constitution 1.1).
# Usage
#   bash scripts/catalog-engine/tests/test_parse_gate_wrappers.sh
#   GATE_FILE=<pre_build_verification.sh> bash ...   # also assert the catalog covers every call site of a real file
# Exit codes
#   0 every check passed and every mutant was killed | 1 a check failed or a mutant survived | 2 environment error
# Dependencies
#   bash, python3.  Writes only under a mktemp directory removed on exit.
# Classification: universal (Constitution 11.4.17) -- no project literal.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib"
TOOL="$LIB/parse_gate.py"
[ -f "$TOOL" ] || { echo "ENV: parser not found: $TOOL" >&2; exit 2; }
command -v python3 >/dev/null || { echo "ENV: python3 missing" >&2; exit 2; }
WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

# ---- golden fixture: one of every registration form, plus look-alikes that must NOT register -------------------------
cat >"$WORK/golden.sh" <<'FIX'
#!/usr/bin/env bash
log_pass() { echo "ok $1"; }
log_fail() { echo "bad $1"; }
# wrapper with a description argument (gate name = first argument)
_g_run() {
    # $1 label ; $2 human desc ; $3.. command
    local _lbl="$1" _desc="$2"; shift 2
    echo -n "  ${_lbl}: ${_desc}... "
    "$@" >/dev/null 2>&1
}
# wrapper whose second argument is NOT a description (a script name) -- verdict through log_pass/log_fail
_g_script() {
    _tok="$1"; _scr="$2"; shift 2
    log_pass "${_tok}: PASS"
    log_fail "${_tok}: FAIL"
}
# a ONE-LINE wrapper definition (the text after the brace is the whole body)
_g_oneline() { local _l="$1" _d="$2"; echo -n "  ${_l}: ${_d}... "; }
# a helper that is NOT a gate wrapper: it prints its first argument but not as a "<label>:" verdict
_g_other() {
    echo "$1"
}
echo -n "  CM-G-LITERAL: literal banner gate (ATM-1473)... "
_g_run "CM-G-WRAPPED" "wrapped \"quoted\" desc with \$VAR and a dash — ok (§11.4.201)" bash x.sh
_g_run 'CM-G-SINGLEQ' 'single-quoted desc' bash y.sh
_g_oneline "CM-G-ONELINE" "one-line wrapper desc"
echo -n "  CM-G-BOTH: banner description wins over the verdict line... "
log_pass "CM-G-BOTH: verdict text that must NOT replace the banner"
_g_script "CM-G-SCRIPT" "gate.sh" --quiet
_g_script \
    "CM-G-CONT" "other.sh"
# _g_run "CM-G-COMMENTED" "a commented-out call must never register"
log_pass "CM-G-VERDICT-ONLY: verdict line only gate"
echo -n "  CM-G-DUP: banner wins over wrapper call... "
_g_run "CM-G-DUP" "wrapper duplicate must lose to the banner" bash z.sh
bash "CM-G-DATA"
echo "CM-G-ECHO-DATA"
FIX

# ---- refusal fixtures --------------------------------------------------------------------------------------------
# R1: a helper whose label is bound from $2 (NOT the first argument) is not a wrapper; its call is an unrecognised form.
cat >"$WORK/r1_label_not_first.sh" <<'FIX'
_g_bad() {
    local _x="$1" _lbl="$2"
    echo -n "  ${_lbl}: thing... "
}
_g_bad "CM-R1-FIRST-ARG-LOOKS-LIKE-GATE" "desc"
FIX
# R2: a one-line function definition directly above a real wrapper must not swallow it nor be mis-detected itself.
cat >"$WORK/r2_oneliner.sh" <<'FIX'
_g_one() { echo "x"; }
_g_real() {
    local _l="$1" _d="$2"; shift 2
    echo -n "  ${_l}: ${_d}... "
}
_g_real "CM-R2-REAL" "real wrapper after a one-liner"
FIX
# R3: unterminated quote in the description -> record kept with an honest empty description, no crash.
cat >"$WORK/r3_unterminated.sh" <<'FIX'
_g_run() {
    local _lbl="$1" _desc="$2"; shift 2
    echo -n "  ${_lbl}: ${_desc}... "
}
_g_run "CM-R3-BROKEN" "never closed
FIX
# R4: a function with an unclosed body followed by a sibling definition must not leak its binding into the sibling.
cat >"$WORK/r4_unclosed.sh" <<'FIX'
_g_unclosed() {
    local _l="$1"
_g_sibling() {
    echo -n "  ${_l}: a global that shares the name of the unclosed function's local... "
}
_g_sibling "CM-R4-NOT-A-WRAPPER"
FIX

# ---- loader: import the parser BY PATH and dump what the test asserts on ----------------------------------------------
cat >"$WORK/dump.py" <<'PY'
import importlib.util, json, sys
tool, fixture = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("pg_under_test", tool)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
recs = m.parse_gate_file(fixture, "pre-build-gate")
lines = open(fixture, encoding="utf-8").read().splitlines()
print(json.dumps({
    "recs": {r["id"]: {"form": r["wiring_form"], "desc": r["description"], "line": r["source_line"],
                       "gaps": r["derivation_gaps"], "atm": r["atm_id"], "q": r["description_quality"]} for r in recs},
    "wrappers": sorted(m.detect_gate_wrappers(lines)),
    "unrec": [[i, g] for _, i, g in m.unrecognised_call_forms(lines)],
    "wrap_ids": m.wrapper_call_ids(lines),
    "verdict_ids": m.verdict_line_ids(lines),
}, ensure_ascii=False))
PY

# ---- the check set: must hold for the real parser (0 failures) and break for every mutant -----------------------------
run_core() { # run_core <parser.py> <dir> -> sets CORE_FAILS, appends failure names to $2/failed
  local tool="$1" d="$2" f=0
  mkdir -p "$d"; : >"$d/failed"
  note() { f=$((f + 1)); echo "$1" >>"$d/failed"; }
  python3 "$tool" --selftest >"$d/selftest.out" 2>&1 || note "selftest"
  python3 "$WORK/dump.py" "$tool" "$WORK/golden.sh" >"$d/golden.json" 2>"$d/golden.err" || note "golden-loads"
  python3 -I - "$d/golden.json" >"$d/golden.verdict" 2>&1 <<'PY' || note "golden-assertions"
import json, sys
g = json.load(open(sys.argv[1], encoding="utf-8"))
r = g["recs"]
def req(c, msg):
    if not c: print("ASSERT", msg); sys.exit(1)
req(sorted(g["wrappers"]) == ["_g_oneline", "_g_run", "_g_script"], "wrappers == [_g_oneline,_g_run,_g_script], got %r" % g["wrappers"])
req("_g_other" not in g["wrappers"] and "log_pass" not in g["wrappers"], "non-wrapper helpers not detected")
req(r["CM-G-LITERAL"]["form"] == "echo-banner", "F1 literal banner form")
req(r["CM-G-LITERAL"]["atm"] == "ATM-1473", "F1 ATM ref derived")
w = r["CM-G-WRAPPED"]
req(w["form"] == "wrapper-call:_g_run", "F2 form")
req(w["desc"] == 'wrapped "quoted" desc with $VAR and a dash — ok (§11.4.201)', "F2 desc decoded, got %r" % w["desc"])
req(w["q"] == "wrapper-arg", "F2 description quality")
req(r["CM-G-SINGLEQ"]["desc"] == "single-quoted desc", "F2 single-quoted id + desc")
req(r["CM-G-ONELINE"]["form"] == "wrapper-call:_g_oneline" and r["CM-G-ONELINE"]["desc"] == "one-line wrapper desc",
    "F2 one-line wrapper definition recognised, got %r" % r.get("CM-G-ONELINE"))
req(r["CM-G-BOTH"]["form"] == "echo-banner" and r["CM-G-BOTH"]["desc"] == "banner description wins over the verdict line",
    "an id with BOTH a banner and a verdict line keeps the banner record once, got %r" % r["CM-G-BOTH"])
s = r["CM-G-SCRIPT"]
req(s["form"] == "wrapper-call:_g_script" and s["desc"] == "" and "no-gate-description" in s["gaps"],
    "F2 wrapper with no description argument: honest empty desc + gap (script name is NOT a description)")
c = r["CM-G-CONT"]
req(c["form"] == "wrapper-call:_g_script", "F2 call whose id is on a continuation line")
v = r["CM-G-VERDICT-ONLY"]
req(v["form"] == "log-verdict" and v["desc"] == "verdict line only gate" and v["q"] == "verdict-line", "F3 verdict-only gate")
req(r["CM-G-DUP"]["form"] == "echo-banner", "precedence: F1 banner beats the F2 call of the same id")
for neg in ("CM-G-COMMENTED", "CM-G-DATA", "CM-G-ECHO-DATA"):
    req(neg not in r, "look-alike must NOT register: " + neg)
req(sorted(g["wrap_ids"]) == ["CM-G-CONT", "CM-G-DUP", "CM-G-ONELINE", "CM-G-SCRIPT", "CM-G-SINGLEQ", "CM-G-WRAPPED"],
    "wrapper_call_ids lister, got %r" % g["wrap_ids"])
req(g["verdict_ids"] == ["CM-G-VERDICT-ONLY"], "verdict_line_ids lister, got %r" % g["verdict_ids"])
req(g["unrec"] == [], "golden fixture has no unrecognised call form, got %r" % g["unrec"])
print("golden ok")
PY
  # R1: label bound from $2 -> NOT a wrapper; both calls reported as unrecognised forms
  python3 "$WORK/dump.py" "$tool" "$WORK/r1_label_not_first.sh" >"$d/r1.json" 2>&1 || note "r1-loads"
  python3 -I - "$d/r1.json" >"$d/r1.verdict" 2>&1 <<'PY' || note "refusal-label-not-first"
import json, sys
g = json.load(open(sys.argv[1], encoding="utf-8"))
ids = sorted(x[1] for x in g["unrec"])
assert g["wrappers"] == [], g["wrappers"]
assert ids == ["CM-R1-FIRST-ARG-LOOKS-LIKE-GATE"], ids
assert g["recs"] == {}, g["recs"]
PY
  # the CLI blind-spot guard exits 1 on it, 0 on the golden fixture
  python3 "$tool" --unrecognised "$WORK/r1_label_not_first.sh" >"$d/r1.cli" 2>&1; [ $? -eq 1 ] || note "cli-unrecognised-exit1"
  python3 "$tool" --unrecognised "$WORK/golden.sh" >/dev/null 2>&1 || note "cli-unrecognised-exit0-on-golden"
  # R2: one-liner above a wrapper
  python3 "$WORK/dump.py" "$tool" "$WORK/r2_oneliner.sh" >"$d/r2.json" 2>&1 || note "r2-loads"
  python3 -I - "$d/r2.json" >"$d/r2.verdict" 2>&1 <<'PY' || note "refusal-oneliner-swallow"
import json, sys
g = json.load(open(sys.argv[1], encoding="utf-8"))
assert g["wrappers"] == ["_g_real"], g["wrappers"]
assert list(g["recs"]) == ["CM-R2-REAL"], g["recs"]
PY
  # R3: unterminated quote -> kept, empty desc, no crash
  python3 "$WORK/dump.py" "$tool" "$WORK/r3_unterminated.sh" >"$d/r3.json" 2>&1 || note "r3-no-crash"
  python3 -I - "$d/r3.json" >"$d/r3.verdict" 2>&1 <<'PY' || note "refusal-unterminated-quote"
import json, sys
g = json.load(open(sys.argv[1], encoding="utf-8"))
r = g["recs"]["CM-R3-BROKEN"]
assert r["desc"] == "" and "no-gate-description" in r["gaps"], r
PY
  # R4: unclosed body must not leak its binding into the sibling definition
  python3 "$WORK/dump.py" "$tool" "$WORK/r4_unclosed.sh" >"$d/r4.json" 2>&1 || note "r4-loads"
  python3 -I - "$d/r4.json" >"$d/r4.verdict" 2>&1 <<'PY' || note "refusal-unclosed-leak"
import json, sys
g = json.load(open(sys.argv[1], encoding="utf-8"))
assert g["wrappers"] == [], g["wrappers"]
assert g["recs"] == {}, g["recs"]
PY
  # usage / IO errors are exit 2, never a silent success
  python3 "$tool" --wrapper-ids "$WORK/no_such_file.sh" >/dev/null 2>&1; [ $? -eq 2 ] || note "cli-missing-file-exit2"
  python3 "$tool" --bogus >/dev/null 2>&1; [ $? -eq 2 ] || note "cli-usage-exit2"
  python3 "$tool" >/dev/null 2>&1; [ $? -eq 2 ] || note "cli-noargs-exit2"
  # CLI listers agree with the import path
  [ "$(python3 "$tool" --wrapper-ids "$WORK/golden.sh" | tr '\n' ' ')" = "CM-G-CONT CM-G-DUP CM-G-ONELINE CM-G-SCRIPT CM-G-SINGLEQ CM-G-WRAPPED " ] || note "cli-wrapper-ids"
  [ "$(python3 "$tool" --verdict-ids "$WORK/golden.sh")" = "CM-G-VERDICT-ONLY" ] || note "cli-verdict-ids"
  CORE_FAILS=$f
}

echo "== real parser: $TOOL"
run_core "$TOOL" "$WORK/real"
if [ "$CORE_FAILS" -eq 0 ]; then ok "all golden + refusal + CLI checks hold on the real parser"
else bad "real parser failed: $(tr '\n' ' ' <"$WORK/real/failed")"; for x in "$WORK"/real/*.verdict "$WORK"/real/golden.err; do [ -s "$x" ] && { echo "--- $x"; cat "$x"; }; done; fi

# exemption works with the documented argument order: <FILE> --exempt <LIST>
python3 "$TOOL" --unrecognised "$WORK/r1_label_not_first.sh" --exempt _g_bad >/dev/null 2>&1 \
  && ok "documented exemption (FILE --exempt LIST) silences the blind-spot guard" \
  || bad "exemption did not silence the guard"

# ---- optional: a real gate file -- the catalog must cover EVERY call site the pairing audit would count ------------
if [ -n "${GATE_FILE:-}" ]; then
  if [ -f "$GATE_FILE" ]; then
    python3 - "$TOOL" "$GATE_FILE" >"$WORK/real_file.out" 2>&1 <<'PY' && ok "real gate file $GATE_FILE: every F2/F3 id is catalogued, 0 unrecognised forms" || { bad "real gate file coverage"; cat "$WORK/real_file.out"; }
import importlib.util, re, sys
tool, f = sys.argv[1:3]
spec = importlib.util.spec_from_file_location("pg", tool); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
recs = {r["id"] for r in m.parse_gate_file(f, "pre-build-gate")}
lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
need = set(m.wrapper_call_ids(lines)) | set(m.verdict_line_ids(lines))
lit = {x.group(1) for x in (re.search(r'echo\s+-n\s+"\s*(CM-[A-Z0-9_-]+):', l) for l in lines) if x}
missing = sorted((need | lit) - recs)
unrec = m.unrecognised_call_forms(lines)
# control needle (11.4.273): the instrument must see at least one id of each class before a zero is believed
assert lit and recs, "needle: literal gates visible"
print("literal=%d wrapper+verdict=%d catalogued=%d missing=%r unrec=%r" % (len(lit), len(need), len(recs), missing[:5], unrec[:5]))
sys.exit(0 if not missing and not unrec else 1)
PY
  else bad "GATE_FILE not found: $GATE_FILE"; fi
fi

# ---- paired mutants: each breaks ONE property of the parser; the check set above must notice (Constitution 1.1) -------
cat >"$WORK/mutator.py" <<'PY'
import sys
src, dst, name = sys.argv[1:4]
M = {
 "m1_no_f2": ("    if wrappers:\n        for idx, ident, gate_id, stmt, end in _calls(lines):",
              "    if False:\n        for idx, ident, gate_id, stmt, end in _calls(lines):"),
 "m2_no_bind": ("_RE_POS_BIND = re.compile(r'\\b([A-Za-z_][A-Za-z0-9_]*)=\"\\$\\{?([1-9])\\}?\"')",
                "_RE_POS_BIND = re.compile(r'\\bNEVER_MATCHES_BIND\\b')"),
 "m3_no_oneliner": ("        if re.search(r\"\\}\\s*(?:#.*)?$\", rest):\n            # A one-line",
                    "        if False:\n            # A one-line"),
 "m4_no_unrec": ("    for idx, ident, gid, _, _ in _calls(lines):\n        if ident in wrappers or ident in exempt",
                 "    for idx, ident, gid, _, _ in []:\n        if ident in wrappers or ident in exempt"),
 "m5_no_desc": ("if d and binds.get(d.group(1)) not in (None, 1):", "if False:"),
 "m6_f3_ignores_dedup": ("        gate_id = m.group(1)\n        if gate_id in seen:\n            continue\n        desc = _dq_prefix(",
                         "        gate_id = m.group(1)\n        desc = _dq_prefix("),
 "m7_no_continuation": ("        stmt = _logical_line(lines, idx) if ln.rstrip().endswith(\"\\\\\") else ln",
                        "        stmt = ln"),
 "m8_unclosed_leak": ("                if n and len(n.group(1)) <= len(indent):\n                    break   # next sibling definition before our close: unclosed",
                      "                if False:\n                    break"),
}
old, new = M[name]
s = open(src, encoding="utf-8").read()
if s.count(old) != 1:   # control needle: the mutation anchor must exist exactly once in the real parser
    print("MUTATION ANCHOR COUNT", s.count(old), "for", name); sys.exit(3)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
kill_mutant() { # kill_mutant <name> <description>
  local name="$1" desc="$2" dir="$WORK/mut_$1"
  mkdir -p "$dir"
  if ! python3 -I "$WORK/mutator.py" "$TOOL" "$dir/parse_gate.py" "$name" >"$dir/build.out" 2>&1; then
    bad "mutant $name could not be built ($desc): $(cat "$dir/build.out")"; return; fi
  run_core "$dir/parse_gate.py" "$WORK/mutrun_$name"
  if [ "$CORE_FAILS" -gt 0 ]; then ok "mutant killed: $desc  [caught by: $(tr '\n' ' ' <"$WORK/mutrun_$name/failed")]"
  else bad "mutant SURVIVED: $desc"; fi
}
kill_mutant m1_no_f2            "remove the F2 wrapper-call recognition (the original ATM-1473 defect)"
kill_mutant m2_no_bind          "break the positional-binding recognition (no wrapper is ever detected)"
kill_mutant m3_no_oneliner      "drop the one-line-definition guard (a one-liner swallows the next wrapper)"
kill_mutant m4_no_unrec         "disable the unrecognised-call-form guard (a new helper shape would be silently dropped)"
kill_mutant m5_no_desc          "never derive the description argument (every wrapper description lost)"
kill_mutant m6_f3_ignores_dedup "F3 ignores the dedup set (a verdict line would duplicate/shadow an F1/F2 record)"
kill_mutant m7_no_continuation  "drop continuation-line joining (a call whose id is on the next line is lost)"
kill_mutant m8_unclosed_leak    "drop the unclosed-body sibling stop (an unclosed function leaks its binding into the next one)"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && { echo "OK"; exit 0; }
exit 1
