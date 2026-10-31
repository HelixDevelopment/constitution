#!/usr/bin/env bash
# test_round9.sh — regression tests for the round-8 review findings RV4, RV6, RV7. Each test runs against the REAL
# engine (must pass) and against a sandbox MUTANT copy of the engine (must FAIL), so it is proven able to catch its
# own negation. RV6/RV7: integration against the real wizard CLI. RV4: UNIT-CLASS (imports the real engine, replaces
# sys.stdout with a stream whose flush raises). Sandboxes are mktemp -d; deletes use safe_rm_rf; HOME is never reassigned.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'cleanup_sandbox' EXIT
C="$DEC_CLI"; ENGINE_DIR="$(dirname "$C")"
export CONSTITUTION_DECISIONS_TEST=1

mutant_cli() { # $1 name, $2 old text, $3 new text -> prints the mutant wizard path; the replacement must apply once
  local m="$SB/mut_$1"; mkdir -p "$m"
  cp "$ENGINE_DIR/constitution_decisions.sh" "$ENGINE_DIR/decisions_engine.py" "$m/" || return 1
  python3 -I - "$m/decisions_engine.py" "$2" "$3" <<'PY' || return 1
import sys; p, o, n = sys.argv[1:4]; s = open(p).read()
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, n, 1))
PY
  printf '%s' "$m/constitution_decisions.sh"
}
# run the wizard on an AGENTS.md with content $2 ($1 = cli); sets RC, KEEP (count of KEEPME), ERR
agents_case() {
  local cli="$1" content="$2" p; p="$SB/p$RANDOM$RANDOM"; mkdir -p "$p/submodules/constitution"
  git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q
  printf '# P\n' >"$p/CLAUDE.md"; printf '%b' "$content" >"$p/AGENTS.md"
  export CONSTITUTION_DECISIONS_USER_FILE="$p/u/d.yml"
  "$cli" --project-root "$p" --non-interactive --set calibration.floor=0.95 >"$p.out" 2>"$p.err"; RC=$?
  KEEP="$(grep -c KEEPME "$p/AGENTS.md")"; ERR="$(head -c 400 "$p.err")"; BLOCKS="$(grep -c '^<!-- BEGIN constitution-decisions' "$p/AGENTS.md")"
}

echo "== RV6: a BEGIN marker line with trailing user text is not a marker; the doc is refused, never rewritten =="
D6='# T\n<!-- BEGIN constitution-decisions --> user note KEEPME\nold\n<!-- END constitution-decisions -->\n'
agents_case "$C" "$D6"
check "real engine: rc 4" test "$RC" = 4
check "real engine: refusal says duplicate or unbalanced ... not touched" bash -c "grep -q 'duplicate or unbalanced' <<<\"\$1\" && grep -q 'not touched' <<<\"\$1\"" _ "$ERR"
check "real engine: KEEPME count stays 1" test "$KEEP" = 1
M6="$(mutant_cli rv6 'BEGIN_RE = re.compile(r"<!-- BEGIN constitution-decisions(?: \([^\r\n]*\))? -->")' 'BEGIN_RE = re.compile(r"<!-- BEGIN constitution-decisions(?: \([^\r\n]*\))? -->.*")')"
check "mutant RV6 built" test -n "$M6"
agents_case "$M6" "$D6"
check "mutant RV6 is caught (rc 0 and KEEPME lost: rc=$RC KEEPME=$KEEP)" bash -c "[ $RC != 4 ] && [ $KEEP != 1 ]"

echo "== RV7: a line '\`\`\`text' inside a bare-fence block is not a CommonMark close; the fenced example is kept =="
D7='# T\n```\n```not-a-close\n<!-- BEGIN constitution-decisions -->\nEXAMPLE KEEPME\n<!-- END constitution-decisions -->\n```\n'
agents_case "$C" "$D7"
check "real engine: rc 0" test "$RC" = 0
check "real engine: fenced example kept (KEEPME 1)" test "$KEEP" = 1
check "real engine: new block appended (2 BEGIN lines: example + managed)" test "$BLOCKS" = 2
M7="$(mutant_cli rv7 'FENCE_CLOSE_RE = re.compile(r" {0,3}(`{3,}|~{3,})[ \t]*")' 'FENCE_CLOSE_RE = re.compile(r" {0,3}(`{3,}|~{3,}).*")')"
check "mutant RV7 built" test -n "$M7"
agents_case "$M7" "$D7"
check "mutant RV7 is caught (rc=$RC KEEPME=$KEEP not the real outcome rc 0 / KEEPME 1 / 2 blocks)" bash -c "! { [ $RC = 0 ] && [ $KEEP = 1 ] && [ $BLOCKS = 2 ]; }"

echo "== RV7: property test with closing-with-text lines in the layout pool (UNIT-CLASS, real engine) =="
cat >"$SB/prop.py" <<'PY'
import random, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
pool = ["```", "~~~", "```not-a-close", "~~~ text", "``` a b", "```", "text", "",
        "<!-- BEGIN constitution-decisions -->", "<!-- END constitution-decisions -->"]
rng = random.Random(20261031)
bad = runs = refused = withtext = 0
for case in range(400):
    lines = [rng.choice(pool) for _ in range(rng.randint(0, 9))]
    # deterministic seed shape: a fence opener, a closing-with-text line, then an example block inside the fence
    if case % 4 == 0:
        lines = ["```", "```not-a-close", "<!-- BEGIN constitution-decisions -->", "ex", "<!-- END constitution-decisions -->"] + lines[:2]
    doc = "\n".join(lines) + "\n"
    withtext += 1 if "```not-a-close" in lines or "~~~ text" in lines else 0
    t, first = doc, None
    for i in range(3):
        blk = d.render_block("constitution", {"calibration.floor": 0.91 + i / 100})
        try: t2 = d.apply_block(t, blk, "doc")
        except d.Refused: refused += 1; t2 = t
        n = sum(1 for l in d.md_lines(t2) if l.rstrip("\r\n").startswith("<!-- BEGIN constitution-decisions"))
        if first is None: first = n
        elif n > first: bad += 1; print("GREW %r" % doc); break
        if t2 != t and blk not in t2: bad += 1; print("WRITE WITHOUT BLOCK %r" % doc); break
        t = t2; runs += 1
print("property: cases=400 runs=%d refused=%d closing-with-text-layouts=%d violations=%d" % (runs, refused, withtext, bad))
sys.exit(1 if bad else 0)
PY
python3 -I "$SB/prop.py" "$ENGINE_DIR" >"$SB/prop.out" 2>&1; prc=$?
check "property: no growth, no write without the current block" test "$prc" = 0
check "property instrument not blind (writes and closing-with-text layouts present)" bash -c "grep -q 'runs=[1-9]' '$SB/prop.out' && grep -q 'closing-with-text-layouts=[1-9]' '$SB/prop.out'"
tail -1 "$SB/prop.out" | sed 's/^/      /'

echo "== RV4 (UNIT-CLASS): stdout.flush raising ValueError -> run_cli(['--version']) is rc 1 'internal error (ValueError)' =="
cat >"$SB/rv4.py" <<'PY'
import sys, io
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1]); import decisions_engine as E
class Closed(io.StringIO):
    encoding = "utf-8"
    def flush(self): raise ValueError("I/O operation on closed file")
err = io.StringIO(); so, se = sys.stdout, sys.stderr
sys.stdout, sys.stderr = Closed(), err
try:
    try: rc = E.run_cli(["--version"])
    except SystemExit as x: rc = "SystemExit(%r)" % (x.code,)
finally:
    sys.stdout, sys.stderr = so, se
sys.stderr.write("rc=%s stderr=%r\n" % (rc, err.getvalue()))
PY
python3 -I "$SB/rv4.py" "$ENGINE_DIR" 2>"$SB/rv4.real"
check "real engine: rc=1" grep -q '^rc=1 ' "$SB/rv4.real"
check "real engine: stderr names 'internal error (ValueError)'" grep -q 'internal error (ValueError)' "$SB/rv4.real"
M4="$(mutant_cli rv4 '        _silence_stdout()
        return report_internal(type(exc).__name__) if rc == 0 else rc
    return rc' '        _silence_stdout()
        return rc
    return rc')"
check "mutant RV4 built" test -n "$M4"
python3 -I "$SB/rv4.py" "$(dirname "$M4")" 2>"$SB/rv4.mut"
check "mutant RV4 is caught (not rc=1 with the internal-error line): $(head -c 120 "$SB/rv4.mut")" bash -c "! { grep -q '^rc=1 ' '$SB/rv4.mut' && grep -q 'internal error (ValueError)' '$SB/rv4.mut'; }"

finish "test_round9"
