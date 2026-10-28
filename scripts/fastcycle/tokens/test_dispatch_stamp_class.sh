#!/usr/bin/env bash
# constitution/scripts/fastcycle/tokens/test_dispatch_stamp_class.sh
#
# Proof for the TIER CLASS check of dispatch_stamp.sh (operator order 2026-10-23 task 10 / 2026-10-26: "no heavy agent on a
# simple task"). Covers: the class cap matrix, no-class (never refused), honest '?' labels, unknown class, tool_input.model
# override, DATA policy (env file, project file, unreadable file, bad cap row), the jq-less awk path, EXTRACTION mode
# untouched, and PAIRED MUTANTS (each broken copy of the hook must make a named assertion fail).
# Usage: bash test_dispatch_stamp_class.sh      exit 0 = all assertions and mutant verdicts right.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/dispatch_stamp.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dst_class.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mk() {  # mk <description> [model]  -> hook payload JSON on stdout
  python3 -I -c 'import json,sys
ti={"description":sys.argv[1],"prompt":"x"}
if len(sys.argv)>2 and sys.argv[2]: ti["model"]=sys.argv[2]
print(json.dumps({"tool_name":"Agent","tool_input":ti}))' "$1" "${2:-}"
}
run() {  # run <hook> <description> [model]  -> prints rc
  local hook="$1"; shift
  # FC_DISPATCH_ITEM_ID_RE pins the item grammar so a mutated COPY of the hook (which cannot find release_prefix.sh next to
  # itself) is judged on the tier check only, never refused for an unrelated prefix reason.
  mk "$@" | env -u FC_DISPATCH_TIER_POLICY -u CLAUDE_PROJECT_DIR FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' bash "$hook" >/dev/null 2>"$WORK/err"; echo $?
}
expect() {  # expect <rc> <hook> <label> <description> [model]
  local want="$1" hook="$2" label="$3"; shift 3
  local got; got="$(run "$hook" "$@")"
  if [ "$got" = "$want" ]; then ok "$label (rc=$got)"; else bad "$label (want rc=$want, got rc=$got; stderr: $(head -c 200 "$WORK/err"))"; fi
}
matrix() {  # matrix <hook> : returns number of failed expectations through the global counters
  local h="$1"
  expect 2 "$h" "simple + sonnet xhigh is refused"              "(T1/main - a - sonnet - xhigh) item=ATM-1 class=simple t"
  expect 2 "$h" "simple + opus medium is refused"               "(T1/main - a - opus - medium) item=ATM-1 class=simple t"
  expect 0 "$h" "simple + sonnet medium is allowed"             "(T1/main - a - sonnet - medium) item=ATM-1 class=simple t"
  expect 0 "$h" "simple + sonnet low is allowed"                "(T1/main - a - sonnet - low) item=ATM-1 class=simple t"
  expect 2 "$h" "mechanical + sonnet xhigh is refused"          "(T1/main - a - sonnet - xhigh) item=ATM-1 class=mechanical t"
  expect 0 "$h" "mechanical + sonnet high is allowed"           "(T1/main - a - sonnet - high) item=ATM-1 class=mechanical t"
  expect 2 "$h" "standard + opus high is refused"               "(T1/main - a - opus - high) item=ATM-1 class=standard t"
  expect 0 "$h" "standard + sonnet xhigh is allowed"            "(T1/main - a - sonnet - xhigh) item=ATM-1 class=standard t"
  expect 0 "$h" "heavy + opus max is allowed"                   "(T1/main - a - opus - max) item=ATM-1 class=heavy review"
  expect 2 "$h" "heavy + fable is refused"                      "(T1/main - a - fable - high) item=ATM-1 class=heavy review"
  expect 0 "$h" "no class declared is never refused"            "(T1/main - a - opus - max) item=ATM-1 no class here"
  expect 0 "$h" "honest '?' model/effort is allowed"            "(T1/main - a - ? - ?) item=ATM-1 class=simple t"
  expect 2 "$h" "unknown class is refused"                      "(T1/main - a - sonnet - low) item=ATM-1 class=trivial t"
  expect 2 "$h" "explicit tool_input.model opus on simple"      "(T1/main - a - sonnet - low) item=ATM-1 class=simple t" "claude-opus-4"
  expect 0 "$h" "explicit tool_input.model sonnet on simple"    "(T1/main - a - sonnet - low) item=ATM-1 class=simple t" "sonnet"
  expect 2 "$h" "item check still first: no item= is refused"   "(T1/main - a - sonnet - low) class=simple t"
}

echo "== dispatch_stamp.sh tier-class matrix (real hook) =="
matrix "$HOOK"

echo "== policy as DATA =="
printf 'simple\thaiku\tlow\ncustom\topus\thigh\tfree text\n' > "$WORK/pol.tsv"
got="$(mk '(T1/main - a - sonnet - low) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' FC_DISPATCH_TIER_POLICY="$WORK/pol.tsv" bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$got" = 2 ] && ok "env policy file overrides the built-in table (simple capped at haiku -> sonnet refused)" || bad "env policy override (rc=$got)"
got="$(mk '(T1/main - a - opus - high) item=ATM-1 class=custom t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' FC_DISPATCH_TIER_POLICY="$WORK/pol.tsv" bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$got" = 0 ] && ok "a class defined only in the env policy file is honoured" || bad "custom class (rc=$got)"
mkdir -p "$WORK/proj/docs/context"; printf 'simple\tsonnet\tlow\n' > "$WORK/proj/docs/context/dispatch_tier_policy.tsv"
got="$(mk '(T1/main - a - sonnet - medium) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' CLAUDE_PROJECT_DIR="$WORK/proj" bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$got" = 2 ] && ok "\$CLAUDE_PROJECT_DIR/docs/context/dispatch_tier_policy.tsv is read" || bad "project policy file (rc=$got)"
got="$(mk '(T1/main - a - sonnet - low) item=ATM-1 class=simple t' | FC_DISPATCH_TIER_POLICY="$WORK/missing.tsv" bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$got" = 2 ] && ok "unreadable policy file fails closed" || bad "unreadable policy (rc=$got)"
printf 'simple\tsonnet\tgigantic\n' > "$WORK/badcap.tsv"
got="$(mk '(T1/main - a - sonnet - low) item=ATM-1 class=simple t' | FC_DISPATCH_TIER_POLICY="$WORK/badcap.tsv" bash "$HOOK" >/dev/null 2>&1; echo $?)"
[ "$got" = 2 ] && ok "a policy row with an unknown cap fails closed" || bad "bad cap row (rc=$got)"
REPO_POL="$HERE/../../../../docs/context/dispatch_tier_policy.tsv"
if [ -f "$REPO_POL" ]; then
  got="$(mk '(T1/main - a - sonnet - xhigh) item=ATM-1 class=simple t' | FC_DISPATCH_TIER_POLICY="$REPO_POL" bash "$HOOK" >/dev/null 2>&1; echo $?)"
  [ "$got" = 2 ] && ok "the consuming repository's real policy file parses and caps simple" || bad "real policy file (rc=$got)"
else
  echo "  SKIP  consumer policy file not present at $REPO_POL (announced)"
fi

echo "== jq-less (built-in awk reader) path =="
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"
for b in bash awk cat env python3 head sed grep cut tr dirname; do p="$(command -v $b 2>/dev/null)" && ln -sf "$p" "$NOJQ/$b"; done
got="$(mk '(T1/main - a - sonnet - xhigh) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' PATH="$NOJQ" bash "$HOOK" >/dev/null 2>"$WORK/nojq_err"; echo $?)"
[ "$got" = 2 ] && grep -q 'no heavy agent' "$WORK/nojq_err" && ok "no-jq: refusal still happens, for the tier reason" || bad "no-jq refusal (rc=$got: $(head -c 160 "$WORK/nojq_err"))"
got="$(mk '(T1/main - a - sonnet - medium) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' PATH="$NOJQ" bash "$HOOK" >/dev/null 2>"$WORK/nojq_err"; echo $?)"
[ "$got" = 0 ] && ok "no-jq: allowed case still allowed" || bad "no-jq allow (rc=$got)"

echo "== EXTRACTION mode untouched =="
got="$(mk '(T1/main - a - opus - max) item=ATM-9 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' bash "$HOOK" --extract-item-id 2>/dev/null)"
[ "$got" = "ATM-9" ] && ok "--extract-item-id ignores class and still prints the id" || bad "extraction (got '$got')"

echo "== paired mutants (each broken hook copy must FAIL its assertion) =="
mutate() {  # mutate <label> <python-replace-old> <python-replace-new> -> path of the mutated copy
  local out="$WORK/mut_$1.sh"; cp "$HOOK" "$out"
  python3 -I - "$out" "$2" "$3" <<'PY'
import sys
p,old,new=sys.argv[1:4]
s=open(p,encoding='utf-8').read()
assert s.count(old)==1,("mutation anchor not unique/absent",old,s.count(old))
open(p,'w',encoding='utf-8').write(s.replace(old,new))
PY
  echo "$out"
}
# M1: the check is never called
m1="$(mutate M1 '  _fc_tier_check || exit 2' '  true')"
[ "$(run "$m1" "(T1/main - a - opus - max) item=ATM-1 class=simple t")" = 0 ] && ok "mutant M1 (check not called) really lets a heavy dispatch through" || bad "mutant M1 not effective"
[ "$(run "$m1" "(T1/main - a - opus - max) item=ATM-1 class=simple t")" != 2 ] && ok "mutant M1 is killed by 'opus max on simple' (expects rc 2)" || bad "mutant M1 SURVIVED"
# M2: effort never compared
m2="$(mutate M2 'if [ "$rm" -gt "$cm" ] || [ "$re" -gt "$ce" ]; then' 'if [ "$rm" -gt "$cm" ]; then')"
[ "$(run "$m2" "(T1/main - a - sonnet - xhigh) item=ATM-1 class=simple t")" = 0 ] && ok "mutant M2 (effort ignored) killed by 'sonnet xhigh on simple'" || bad "mutant M2 SURVIVED"
# M3: model never compared
m3="$(mutate M3 'if [ "$rm" -gt "$cm" ] || [ "$re" -gt "$ce" ]; then' 'if [ "$re" -gt "$ce" ]; then')"
[ "$(run "$m3" "(T1/main - a - opus - low) item=ATM-1 class=simple t")" = 0 ] && ok "mutant M3 (model ignored) killed by 'opus low on simple'" || bad "mutant M3 SURVIVED"
# M4: unknown class not recognised as such (the later unknown-cap guard still refuses, so the REASON is the oracle)
m4="$(mutate M4 'if [ "$hit" -ne 1 ]; then' 'if false; then')"
mk '(T1/main - a - sonnet - low) item=ATM-1 class=trivial t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' bash "$HOOK" >/dev/null 2>"$WORK/m4_real" || true
mk '(T1/main - a - sonnet - low) item=ATM-1 class=trivial t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' bash "$m4" >/dev/null 2>"$WORK/m4_mut" || true
if grep -q 'unknown class=trivial' "$WORK/m4_real" && ! grep -q 'unknown class=trivial' "$WORK/m4_mut"; then ok "mutant M4 (unknown-class branch disabled) killed: the real hook names 'unknown class', the mutant does not"; else bad "mutant M4 SURVIVED"; fi
# M5: tool_input.model override ignored
m5="$(mutate M5 '  [ "$rt" -gt "$rm" ] && rm="$rt"' '  true')"
[ "$(run "$m5" "(T1/main - a - sonnet - low) item=ATM-1 class=simple t" "claude-opus-4")" = 0 ] && ok "mutant M5 (explicit model ignored) killed by tool_input.model=opus" || bad "mutant M5 SURVIVED"
# M6: unreadable-policy branch disabled (a later guard still refuses, so the REASON is the oracle)
m6="$(mutate M6 '    if [ ! -r "$pol" ]; then' '    if false; then')"
mk '(T1/main - a - sonnet - low) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' FC_DISPATCH_TIER_POLICY="$WORK/missing.tsv" bash "$HOOK" >/dev/null 2>"$WORK/m6_real" || true
mk '(T1/main - a - sonnet - low) item=ATM-1 class=simple t' | FC_DISPATCH_ITEM_ID_RE='ATM-[0-9]+' FC_DISPATCH_TIER_POLICY="$WORK/missing.tsv" bash "$m6" >/dev/null 2>"$WORK/m6_mut" || true
if grep -q 'not readable' "$WORK/m6_real" && ! grep -q 'not readable' "$WORK/m6_mut"; then ok "mutant M6 (unreadable-policy branch disabled) killed: the real hook says 'not readable', the mutant does not"; else bad "mutant M6 SURVIVED"; fi
# M7: a dispatch with no class gets refused (false-positive refusal)
m7="$(mutate M7 '  [[ "$DESCRIPTION" =~ $cls_re ]] || return 0' '  [[ "$DESCRIPTION" =~ $cls_re ]] || return 1')"
[ "$(run "$m7" "(T1/main - a - opus - max) item=ATM-1 no class here")" = 2 ] && ok "mutant M7 (class required) killed by 'no class declared is never refused'" || bad "mutant M7 SURVIVED"
# Mutant effectiveness controls: the unmodified hook gives the opposite verdicts on the same inputs
[ "$(run "$HOOK" "(T1/main - a - opus - max) item=ATM-1 class=simple t")" = 2 ] && ok "control: the real hook refuses what M1 lets through" || bad "control failed"

echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" = 0 ]
