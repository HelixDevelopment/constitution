#!/bin/sh
# shellcheck disable=SC2016 # printf and heredoc fixtures are literal shell text whose dollar signs must not expand
# fastcycle-timeout-s: 900
# =============================================================================
# test_precheck_shellcheck_baseline_delta.sh (ATM-1217 r3 + r4)
# Real-path regression for the OPT-IN baseline-delta rule of the precheck-pack
# lint row (--shellcheck-rule baseline-delta; operator decision 2026-10-13),
# layered on the round-5/6 gate (severity floor, systemd-run memory cap, size cap,
# budget, lock, binding, directive policing + parity oracle, legacy ratchet).
# 11.4.276(D): every case drives the REAL review/precheck_pack.sh ->
# lib/precheck_pack_run.py, bound by the REAL builder lib (bind), against a
# scratch git repository; shellcheck is the REAL binary, wrapped by a stub on PATH
# ONLY to simulate hang / out-of-memory / empty-stdout tool failures. The stub
# reads the lint input from stdin (the gate lints on stdin) and keys on marker
# lines: `# STUB_HANG` (exec sleep 30), `# STUB_SLEEP3` (sleep 3), `# STUB_OOM_FULL`
# (exit 251 "out of memory" whenever the marker line is part of the input -- full
# lints only; windows never contain line 2), `# STUB_OOM_IF <token>` (the same, only
# when <token> also occurs elsewhere in the input), `# STUB_RC1EMPTY` (exit 1, no
# stdout), `# STUB_RC0EMPTY` (exit 0, no stdout).
#
# Fixture classes (11.4.107(10)): golden-good C1/C3/C9 (pre-existing only -> PASS);
# golden-bad C2/C17 (new warning / duplicate occurrence -> FAIL); negative control
# C0/C19 (clean->clean, fixed finding -> PASS, nothing reported).
#
# FC_OVERRIDE=<fastcycle dir> runs the same cases against another tree (RED capture
# on the round-6 tip; mutants). DELTA_RULE_ARG= (empty) runs every case WITHOUT the
# --shellcheck-rule flag -- the round-6 gate's own whole-file verdicts (the
# behavioural RED). The expected verdicts never change.
# Usage: sh test_precheck_shellcheck_baseline_delta.sh
# Exit : 0 all held; 1 any case failed; 2 environment (git / shellcheck / cap).
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=${FC_OVERRIDE:-$(cd "$HERE/.." && pwd)}
REVIEW="$FC/review"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok: $1"; }

REAL_SC=$(command -v shellcheck 2>/dev/null) || { echo "SKIP/ENV: real shellcheck not on PATH" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "SKIP/ENV: git not on PATH" >&2; exit 2; }

TMP=$(mktemp -d)
# shellcheck disable=SC2329 # invoked indirectly by the EXIT/INT/TERM trap on the next line
cleanup() { [ -n "${KEEP:-}" ] || rm -rf "$TMP"; }
trap cleanup EXIT INT TERM
export PRECHECK_TEST_MODE=1 PRECHECK_TEST_LOCK_DIR="$TMP/lockdir"
mkdir -p "$PRECHECK_TEST_LOCK_DIR"
GIT="git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false"

# --- stub shellcheck (stdin-aware), otherwise the REAL binary ----------------
mkdir -p "$TMP/stubbin"
cat >"$TMP/stubbin/shellcheck" <<EOF
#!/bin/sh
case "\$*" in *--version*) exec "$REAL_SC" "\$@" ;; esac
t=\$(mktemp) || exit 99
cat >"\$t"
if grep -q '^# STUB_HANG' "\$t"; then rm -f "\$t"; exec sleep 30; fi
if grep -q '^# STUB_SLEEP3' "\$t"; then sleep 3; fi
if grep -q '^# STUB_OOM_FULL' "\$t"; then rm -f "\$t"; echo "shellcheck: out of memory" >&2; exit 251; fi
tok=\$(sed -n 's/^# STUB_OOM_IF //p' "\$t" | head -n 1)
if [ -n "\$tok" ] && grep -v '^# STUB_OOM_IF ' "\$t" | grep -q -- "\$tok"; then
    rm -f "\$t"; echo "shellcheck: out of memory" >&2; exit 251
fi
if grep -q '^# STUB_RC1EMPTY' "\$t"; then rm -f "\$t"; echo "shellcheck: Unable to commit 1048576 bytes of memory" >&2; exit 1; fi
if grep -q '^# STUB_RC0EMPTY' "\$t"; then rm -f "\$t"; exit 0; fi
"$REAL_SC" "\$@" <"\$t"; rc=\$?
rm -f "\$t"
exit "\$rc"
EOF
chmod +x "$TMP/stubbin/shellcheck"
PATH="$TMP/stubbin:$PATH"; export PATH

# --- scenario helpers (same shape as test_precheck_shellcheck_red.sh) ---------
# new_case <name>; wb/wh <rel> <printf-%b body>; base; head; gate [args]
new_case() { CASE=$1; R="$TMP/$CASE"; mkdir -p "$R"; printf 'readme\n' >"$R/README.md"; }
wb() { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" >"$R/$1"; }
wh() { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" >"$R/$1"; }
base() { ( cd "$R" && git init -q . && $GIT add -A && $GIT commit -q -m base ) >/dev/null 2>&1; BASE=$(git -C "$R" rev-parse HEAD); }
head() { ( cd "$R" && $GIT add -A && $GIT commit -q -m head ) >/dev/null 2>&1; HEADC=$(git -C "$R" rev-parse HEAD); }
mkraw() {
    python3 - "$R" "$BASE" "$HEADC" "$1" <<'PY'
import json, subprocess, sys
r, b, h, out = sys.argv[1:5]
p = subprocess.run(["git", "-C", r, "-c", "core.quotePath=false", "diff", "-z", "--name-only", "--no-renames", b, h],
                   capture_output=True).stdout.split(b"\0")
paths = sorted(x.decode("utf-8", "surrogateescape") for x in p if x)
json.dump({"batch_id": "RB-SCD-" + r.rsplit("/", 1)[-1], "changes": [], "related_by": "logic_group:scd",
           "total_changed_lines": 1,
           "slices": [{"slice_id": "S1", "lines": 1, "context_pack": {
               "intent": "fixture", "changed_paths": paths,
               "blast_radius": "%d changed path(s) in this slice: %s" % (len(paths), ", ".join(paths))}}]},
          open(out, "w"), ensure_ascii=False)
PY
}
gate_prepare() {
    rm -rf "$R.co"; git -C "$R" worktree prune >/dev/null 2>&1
    git -C "$R" worktree add --detach --quiet "$R.co" "$HEADC" >/dev/null 2>&1
    mkraw "$R.raw.json"
    python3 "$REVIEW/lib/precheck_pack_build_run.py" bind --repo "$R" --base "$BASE" --head "$HEADC" \
        --batch "$R.raw.json" --out "$R.batch.json" --rewrite-changes >"$R.bind.out" 2>&1
}
gate_run() { # [extra args] -- the run_rule wrapper below appends the rule under test
    OUT="$R.out.json"
    sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R.co" --out "$OUT" \
        --baseline-repo "$R" --baseline-ref "$BASE" --head-sha "$HEADC" "$@" >"$R.stdout" 2>"$R.stderr"
    RC=$?
}
# RULE: the rule under test (DELTA_RULE_ARG= empty -> no flag: captures the round-6 gate's own verdicts, RED)
RULE=${DELTA_RULE_ARG-baseline-delta}
run_rule() { if [ -n "$RULE" ]; then "$@" --shellcheck-rule "$RULE"; else "$@"; fi; }
gate() { gate_prepare; run_rule gate_run "$@"; }
sc() { # <python expr over c (shellcheck check), d (pack), e (evidence)> -- a literal of THIS file
    # eval is safe here: argv[2] is a literal expression written in THIS test file, never external input.
    python3 - "$OUT" "$1" <<'PY' 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
c = [x for x in d["checks"] if x["check"] == "shellcheck"][0]
e = c["evidence"]
print(eval(sys.argv[2], {"c": c, "d": d, "e": e}))
PY
}
expect() { # <label> <expr> <expected>
    got=$(sc "$2")
    if [ "$got" = "$3" ]; then ok "$1 [$2 == $3]"
    else bad "$1: $2 -> '$got', expected '$3' (rc=${RC:-?}; $(command head -c 300 "$R.stderr" 2>/dev/null))"; fi
}
H=$(printf '\043')   # '#', so this file's own source carries no directive-shaped line

BASE_SH='#!/bin/sh\n# base fixture\nhelper() {\n    echo "$undefined_pre"\n}\nhelper\n'

echo "== precheck shellcheck row: baseline-delta rule (r4, on the round-6 gate) =="
CAPN=$(systemd-run --user --scope --quiet --collect -p MemoryMax=64M -p MemorySwapMax=0 -- sh -c 'cat "/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)/memory.max"' 2>&1)
[ "$CAPN" = "67108864" ] || { echo "SKIP/ENV: no enforceable systemd-run --user memory cap here ($CAPN)" >&2; exit 2; }

# C0 negative control: clean base, clean head, comment-only edit
new_case c0; wb a.sh '#!/bin/sh\necho "ok"\n'; base; wh a.sh '#!/bin/sh\necho "ok"\n# a comment\n'; head; gate
expect "C0 negative-control clean->clean" 'c["verdict"]' PASS
expect "C0 reports no findings and runs the delta mode" '(len(e.get("findings", [])), e["mode"])' "(0, 'baseline-delta')"

# C1 golden-good: pre-existing warning untouched, unrelated edit
new_case c1; wb a.sh "$BASE_SH"; base; wh a.sh "${BASE_SH}# unrelated edit\necho finished\n"; head; gate
expect "C1 golden-good pre-existing finding only -> PASS" 'c["verdict"]' PASS
expect "C1 state full, the finding is listed as baseline" '(e["delta"]["states"], [f["rule"] for f in e.get("baseline_findings", [])])' "(['full'], ['SC2154'])"

# C2 golden-bad: a NEW warning (SC2154)
new_case c2; wb a.sh "$BASE_SH"; base; wh a.sh "${BASE_SH}echo \"\$brand_new_var\"\n"; head; gate
expect "C2 golden-bad new warning FAILs" 'c["verdict"]' FAIL
expect "C2 exactly one new finding, SC2154 at line 7, new_in full" '[(f["rule"], f["line"], f["new_in"]) for f in e.get("findings", [])]' "[('SC2154', 7, 'full')]"

# C3 pre-existing finding whose LINE MOVED (10 lines inserted above)
PAD=$(i=0; while [ $i -lt 10 ]; do printf 'echo pad%s\\n' "$i"; i=$((i+1)); done)
new_case c3; wb a.sh "$BASE_SH"; base; wh a.sh "#!/bin/sh\n${PAD}# base fixture\nhelper() {\n    echo \"\$undefined_pre\"\n}\nhelper\n"; head; gate
expect "C3 moved-line pre-existing finding PASSes" 'c["verdict"]' PASS

# C4 new file with findings -> FAIL (new-file); a new CLEAN file -> PASS
new_case c4; wb old.sh '#!/bin/sh\necho ok\n'; base; wh new.sh '#!/bin/sh\necho "$undefined_in_new_file"\n'; head; gate
expect "C4 new file with a finding FAILs, state new-file, tagged new_in new-file" '(c["verdict"], e["delta"]["states"], [f["new_in"] for f in e.get("findings", [])])' "('FAIL', ['new-file'], ['new-file'])"
new_case c4b; wb old.sh '#!/bin/sh\necho ok\n'; base; wh new.sh '#!/bin/sh\necho clean\n'; head; gate
expect "C4b new CLEAN file PASSes" 'c["verdict"]' PASS

# C5a head timeout, tiny file (the only window is the whole file) -> unresolved FAIL
new_case c5; wb a.sh "$BASE_SH"; base; wh a.sh "#!/bin/sh\n# STUB_HANG\n# base fixture\nhelper() {\n    echo \"\$undefined_pre\"\n}\nhelper\n"; head
gate --shellcheck-timeout 1
expect "C5a head timeout -> FAIL" 'c["verdict"]' FAIL
expect "C5a state unresolved, cause names the head timeout, the window refusal is recorded" '(e["delta"]["files"][0]["state"], e["delta"]["files"][0]["cause"][0].startswith("head: shellcheck exceeded"), "no bound" in e["delta"]["files"][0]["window_fallback"])' "('unresolved', True, True)"

# C5b head timeout on a NEW file -> FAIL (no base to bound a window)
new_case c5b; wb old.sh '#!/bin/sh\necho ok\n'; base; wh new.sh '#!/bin/sh\n# STUB_HANG\necho "$x"\n'; head; gate --shellcheck-timeout 1
expect "C5b new-file head timeout -> FAIL (BLIND)" '(c["verdict"], any("BLIND" in x["message"] for x in e.get("errors", [])))' "('FAIL', True)"

# C6 OOM on the BASE full lint only -> window mode, PASS when nothing new
C6='#!/bin/sh\n# STUB_OOM_IF changed_old\nhelper() {\n    echo "$undefined_pre"\n}\nother() {\n    echo changed_old\n}\nhelper\nother\n'
new_case c6; wb a.sh "$C6"; base; wh a.sh "$(printf '%b' "$C6" | sed 's/echo changed_old/echo changed_new/')\n"; head; gate
expect "C6 base-only OOM -> window PASS (nothing new)" '(c["verdict"], e["delta"]["states"])' "('PASS', ['window'])"
expect "C6 window caveat present, cause = base OOM" '("caveat_window" in e["delta"], e["delta"]["files"][0]["cause"][0].startswith("base: shellcheck exited 251"))' "(True, True)"
# C6b same base OOM, a NEW warning inside the changed function -> FAIL (base failure never reads clean)
new_case c6b; wb a.sh "$C6"; base; wh a.sh "$(printf '%b' "$C6" | sed 's/echo changed_old/echo "$added_in_c6b"/')\n"; head; gate
expect "C6b base OOM + new warning in the window -> FAIL new_in window" '(c["verdict"], [(f["rule"], f["new_in"]) for f in e.get("findings", [])])' "('FAIL', [('SC2154', 'window')])"

# C7 head full-lint OOM, NEW warning inside the window -> FAIL, line mapped back
C7='#!/bin/sh\n# STUB_OOM_FULL\none() {\n    echo one\n}\ntwo() {\n    echo two\n}\none\ntwo\n'
new_case c7; wb a.sh "$C7"; base; wh a.sh "$(printf '%b' "$C7" | sed 's/echo two/echo "$added_undefined"/')\n"; head; gate
expect "C7 window mode finds the new warning -> FAIL" 'c["verdict"]' FAIL
expect "C7 tagged new_in=window at the REAL line 7" '[(f["new_in"], f["line"]) for f in e.get("findings", [])]' "[('window', 7)]"
# C7b same head-OOM shape, only a pre-existing finding in the window -> PASS
C7B='#!/bin/sh\n# STUB_OOM_FULL\none() {\n    echo "$undefined_pre"\n    echo old\n}\none\n'
new_case c7b; wb a.sh "$C7B"; base; wh a.sh "$(printf '%b' "$C7B" | sed 's/echo old/echo new/')\n"; head; gate
expect "C7b head-OOM window with only a pre-existing finding -> PASS, state window (never full)" '(c["verdict"], e["delta"]["states"], len(e.get("baseline_findings", [])))' "('PASS', ['window'], 1)"

# C8 configurable timeout: per-run value honoured, delta default 120 s, ceiling refused, non-number refused
new_case c8; wb a.sh '#!/bin/sh\n# STUB_SLEEP3\necho "$u"\n'; base; wh a.sh '#!/bin/sh\n# STUB_SLEEP3\necho "$u"\necho more\n'; head
gate --shellcheck-timeout 1
expect "C8 --shellcheck-timeout 1 times out the 3 s lint (FAIL, never clean)" 'c["verdict"]' FAIL
run_rule gate_run --shellcheck-timeout 20
expect "C8 --shellcheck-timeout 20 lets it finish (pre-existing finding only) -> PASS, 20 s recorded" '(c["verdict"], e["tool"]["timeout_s"])' "('PASS', 20.0)"
run_rule gate_run
expect "C8 the delta rule's default per-lint timeout is 120 s (tool + provenance)" '(e["tool"]["timeout_s"], d["provenance"]["shellcheck_params"]["timeout_s"], e["tool"]["rule"])' "(120, 120, 'baseline-delta')"
run_rule gate_run --shellcheck-timeout 100000; C8A=$RC
run_rule gate_run --shellcheck-timeout abc; C8B=$RC
if [ "$C8A" -eq 2 ] && [ "$C8B" -eq 2 ]; then ok "C8 a timeout above the ceiling and a non-number are REFUSED (exit 2), never clamped"
else bad "C8 ceiling/non-number not refused: rc=$C8A/$C8B"; fi

# C9 rename with a small edit: the pre-existing finding follows the file (binding renames)
new_case c9; wb old_name.sh "$BASE_SH"; base; git -C "$R" mv old_name.sh new_name.sh >/dev/null 2>&1
printf '# renamed\n' >>"$R/new_name.sh"; head; gate
expect "C9 renamed file, pre-existing finding -> PASS, renamed_from recorded" '(c["verdict"], [f.get("renamed_from") for f in e["delta"]["files"] if f["file"] == "new_name.sh"])' "('PASS', ['old_name.sh'])"

# C10 the round-6 severity floor applies to NEW findings: a new SC2016 (non-floor info) is advisory -> PASS;
#     a new SC2086 (floor info rule) FAILs
new_case c10; wb a.sh '#!/bin/sh\necho "$1"\n'; base; wh a.sh "#!/bin/sh\necho \"\$1\"\necho '\$HOME is literal'\n"; head; gate
expect "C10 new non-floor info finding is advisory -> PASS" '(c["verdict"], [f["rule"] for f in e.get("advisory_findings", [])])' "('PASS', ['SC2016'])"
new_case c10b; wb a.sh '#!/bin/sh\necho "$1"\n'; base; wh a.sh '#!/bin/sh\necho "$1"\necho $1\n'; head; gate
expect "C10b new SC2086 (floor info rule) FAILs" '(c["verdict"], [f["rule"] for f in e.get("findings", [])])' "('FAIL', ['SC2086'])"

# C11 directives: a pre-existing unjustified disable is tolerated (listed); a NEW one FAILs; a justified new one PASSes
D11B="#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n"
new_case c11; wb a.sh "$D11B"; base; wh a.sh "${D11B}${H} shellcheck disable=SC2154\necho \"\$u\"\n"; head; gate
expect "C11 NEW unjustified directive FAILs, only it is cited, the old one is baseline" '(c["verdict"], [x["line"] for x in e.get("directive_violations", [])], [x["line"] for x in e.get("directive_violations_baseline", [])])' "('FAIL', [4], [2])"
new_case c11b; wb a.sh "$D11B"; base; wh a.sh "${D11B}${H} shellcheck disable=SC2154 ${H} assigned by the sourcing harness before this script runs\necho \"\$u\"\n"; head; gate
expect "C11b a JUSTIFIED new directive PASSes" 'c["verdict"]' PASS

# C12 no base at all (unbound, plain directory): whole-file verdict, said so, never a silent pass
new_case c12; printf '%b' "$BASE_SH" >"$R/a.sh"
python3 -c 'import json,sys;json.dump({"batch_id":"RB-C12","changes":[],"related_by":"x","total_changed_lines":1,"slices":[{"slice_id":"S1","lines":1,"context_pack":{"intent":"f","changed_paths":["a.sh"],"blast_radius":"1 changed path(s) in this slice: a.sh"}}]},open(sys.argv[1],"w"))' "$R.batch.json"
OUT="$R.out.json"; run_rule sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R" --out "$OUT" >"$R.stdout" 2>"$R.stderr"; RC=$?
expect "C12 no base: the pre-existing finding FAILs (whole-file verdict)" 'c["verdict"]' FAIL
expect "C12 base_resolved false, mode whole-file, caveat present" '(e["delta"]["base_resolved"], e["mode"], "caveat" in e["delta"])' "(False, 'whole-file', True)"

# C13 the explicit range base is honoured (not the first parent)
new_case c13; wb a.sh "$BASE_SH"; base; B13=$BASE
wh a.sh "${BASE_SH}echo \"\$mid_var\"\n"; head; BASE=$HEADC
wh a.sh "${BASE_SH}echo \"\$mid_var\"\n# tail\n"; head; gate
expect "C13 base = first parent: only a comment is new -> PASS" 'c["verdict"]' PASS
BASE=$B13; gate
expect "C13 base = the range base: the mid-range new warning -> FAIL" 'c["verdict"]' FAIL

# C14 memory cap (REAL, no stub): a 1100-statement function needs ~4 GB in shellcheck (measured 2026-10-13);
#     under a 2048 MiB cap the head lint AND the function-sized window lint are killed -> unresolved FAIL
new_case c14
python3 -c 'import sys;open(sys.argv[1],"w").write("#!/bin/sh\nbig() {\n"+"".join("    x%d=\"$1\"; echo \"$x%d\"\n"%(i,i) for i in range(1100))+"}\nbig\n")' "$R/a.sh"; base
python3 -c 'import sys;p=sys.argv[1];s=open(p).read().replace("}\nbig\n","    echo \"$c14_new\"\n}\nbig\n");open(p,"w").write(s)' "$R/a.sh"; head
gate --shellcheck-memory-cap-mib 2048
expect "C14 2048 MiB cap kills the head lint and the window lint -> FAIL, unresolved, never a clean pass" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0]["cause"][0].startswith("head: shellcheck killed by signal"), "killed by signal" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True, True)"
new_case c14b
python3 -c 'import sys;open(sys.argv[1],"w").write("#!/bin/sh\n"+"".join("x%d=\"$1\"; echo \"$x%d\"\n"%(i,i) for i in range(300)))' "$R/a.sh"; base
python3 -c 'import sys;open(sys.argv[1],"a").write("echo \"$c14_new\"\n")' "$R/a.sh"; head; gate
expect "C14b under the default cap the same shape lints whole: the one NEW warning FAILs (state full)" '(c["verdict"], [f["rule"] for f in e.get("findings", [])], e["delta"]["states"])' "('FAIL', ['SC2154'], ['full'])"

# C15 determinism (C-003) over a delta pack
R="$TMP/c2"; OUT="$R.det.json"
run_rule sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R.co" --out "$OUT" --baseline-repo "$R" \
    --baseline-ref "$(git -C "$R" rev-parse HEAD~1)" --head-sha "$(git -C "$R" rev-parse HEAD)" --determinism-check >"$R.det.out" 2>"$R.det.err"; C15=$?
if [ "$C15" -eq 0 ]; then ok "C15 --determinism-check is deterministic over the delta rule"
else bad "C15 determinism: $(command head -c 300 "$R.det.err")"; fi

# C16 exit 1 with EMPTY stdout must never read as a clean scan
new_case c16; wb a.sh '#!/bin/sh\necho ok\n'; base; wh a.sh '#!/bin/sh\n# STUB_RC1EMPTY\necho ok\n'; head; gate
expect "C16 rc=1 + empty stdout is NOT a clean PASS" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'unresolved')"

new_case c16b; wb a.sh '#!/bin/sh\necho ok\n'; base; wh a.sh '#!/bin/sh\n# STUB_RC0EMPTY\necho ok\n'; head; gate
expect "C16b rc=0 + empty stdout is NOT a clean PASS either" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'unresolved')"

# C17 golden-bad: a SECOND occurrence of an identical pre-existing finding is NEW (multiset, not set)
new_case c17; wb a.sh '#!/bin/sh\nhelper() {\n    cd /tmp\n}\nhelper\n'; base
wh a.sh '#!/bin/sh\nhelper() {\n    cd /tmp\n}\nhelper2() {\n    cd /tmp\n}\nhelper\nhelper2\n'; head; gate
expect "C17 duplicate occurrence FAILs, exactly one new (the later one)" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2164', 6)])"

# C18 a window that does not parse standalone -> unresolved FAIL, never a PASS
C18=$( { printf '#!/bin/sh\n# STUB_OOM_FULL\nif [ -n "$1" ]; then\n'; i=0; while [ $i -lt 100 ]; do printf '    echo "l%s"\n' "$i"; i=$((i+1)); done; printf 'fi\n'; } )
new_case c18; printf '%s\n' "$C18" >"$R/a.sh"; base; printf '%s\n' "$C18" | sed 's/echo "l95"/echo "l95 edited"/' >"$R/a.sh"; head; gate
expect "C18 mid-construct window -> FAIL, state unresolved, standalone-parse reason" '(c["verdict"], e["delta"]["files"][0]["state"], "does not parse standalone" in e["delta"]["files"][0]["window_fallback"])' "('FAIL', 'unresolved', True)"

# C19 negative control: a pre-existing finding FIXED in head -> PASS, nothing new
new_case c19; wb a.sh "$BASE_SH"; base; wh a.sh '#!/bin/sh\nhelper() {\n    echo "ok"\n}\nhelper\n'; head; gate
expect "C19 fixed finding -> PASS, nothing reported" '(c["verdict"], e.get("findings"), e.get("baseline_findings"))' "('PASS', None, None)"

# C20 a mode-only change (byte-identical blob) is not linted: an unlintable file does not hang the batch
new_case c20; wb a.sh '#!/bin/sh\n# STUB_HANG\necho "$u"\n'; base; chmod +x "$R/a.sh"; head; gate --shellcheck-timeout 1
expect "C20 byte-identical file: state unchanged, not linted, PASS" '(c["verdict"], e["delta"]["states"], e["counts"]["files_linted"])' "('PASS', ['unchanged'], 0)"

# C21 head OOM, the change sits in top-level code of a tiny file: the window is the whole file -> no bound
C21='#!/bin/sh\n# STUB_OOM_FULL\necho one\necho two\n'
new_case c21; wb a.sh "$C21"; base; wh a.sh "$(printf '%b' "$C21" | sed 's/echo two/echo "$new_undefined"/')\n"; head; gate
expect "C21 whole-file window is no bound -> FAIL, reason names it" '(c["verdict"], "no bound" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', True)"

# --- merge seams with the round-5/6 gate ---------------------------------------
# N1 a legacy-exception row keeps the per-rule RATCHET (never the delta): 2 SC2086 pre-existing, pin 1 -> FAIL
TSV=config/shellcheck_legacy_exceptions.tsv
new_case n1; mkdir -p "$R/config"; printf 'vendor/big.sh\tvendored\tATM-1234\tSC2086=1\t2026-10-09\n' >"$R/$TSV"
wb vendor/big.sh '#!/bin/sh\necho $1\necho $2\n'; base; wh vendor/big.sh '#!/bin/sh\necho $1\necho $2\n# edited\n'; head; gate
expect "N1 a listed file is ratcheted (FAIL over pin) and not part of the delta" '(c["verdict"], e["legacy_exceptions"][0]["verdict"], [f["file"] for f in e["delta"]["files"]])' "('FAIL', 'FAIL', [])"
# N2 a PRE-EXISTING forbidden directive (D1 disable=all) still FAILs under the delta (D1-D4 are never tolerated)
D1B="#!/bin/sh\n${H} shellcheck disable=all ${H} suppress everything for this legacy helper\necho \$1\n"
new_case n2; wb a.sh "$D1B"; base; wh a.sh "${D1B}# edited\n"; head; gate
expect "N2 pre-existing disable=all still FAILs (D1)" '(c["verdict"], [v.split()[0] for x in e.get("directive_violations", []) for v in x["violations"]])' "('FAIL', ['D1'])"
# N3 without --shellcheck-rule the gate is the unchanged round-6 whole-file rule (G2 shape: pre-existing FAILs)
new_case n3; wb a.sh "$BASE_SH"; base; wh a.sh "${BASE_SH}# edited\n"; head; gate_prepare; gate_run
expect "N3 default rule = whole-file: the pre-existing finding FAILs, rule recorded, 60 s default" '(c["verdict"], e["mode"], e["tool"]["rule"], e["tool"]["timeout_s"], "delta" in e)' "('FAIL', 'whole-file', 'whole-file', 60, False)"
gate_run --shellcheck-rule lenient; N3B=$RC
if [ "$N3B" -eq 2 ] && grep -q "shellcheck-rule must be one of" "$R.stderr"; then ok "N3b an unknown --shellcheck-rule is refused (exit 2)"
else bad "N3b unknown rule rc=$N3B $(command head -c 200 "$R.stderr")"; fi
# N4 the size cap: an over-cap head of a tracked file falls back to windows (host-safe) instead of BLIND
N4BODY=$( { printf '#!/bin/sh\n'; i=0; while [ $i -lt 30 ]; do printf 'f%s() {\n    echo "%s"\n}\n' "$i" "$i"; i=$((i+1)); done; } )
new_case n4; printf '%s\n' "$N4BODY" >"$R/a.sh"; base; printf '%s\n' "$N4BODY" | sed 's/echo "17"/echo "$n4_new"/' >"$R/a.sh"; head
gate --shellcheck-max-lines 50
expect "N4 head over the size cap -> window: the new warning FAILs at its real line, other functions not judged" '(c["verdict"], e["delta"]["files"][0]["state"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', 'window', [('SC2154', 54)])"
# N5 builder cache: a pack built under the whole-file rule is not reused for a delta request
new_case n5; wb a.sh "$BASE_SH"; base; wh a.sh "${BASE_SH}# edited\n"; head
gate_prepare; mkdir -p "$TMP/n5out"; OUT="$TMP/n5out/precheck.json"
sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R.co" --out "$OUT" --baseline-repo "$R" \
    --baseline-ref "$BASE" --head-sha "$HEADC" >/dev/null 2>&1
python3 "$REVIEW/lib/precheck_pack_build_run.py" emit --out-dir "$TMP/n5out" --validate-only --expect-base "$BASE" \
    --expect-head "$HEADC" --expect-sc-rule baseline-delta >/dev/null 2>"$TMP/n5.err"; N5=$?
if [ "$N5" -eq 3 ] && grep -q -- "--shellcheck-rule" "$TMP/n5.err"; then ok "N5 a cached whole-file pack is stale for a baseline-delta request (rebuilt, not reused)"
else bad "N5 cache rule check: rc=$N5 $(command head -c 300 "$TMP/n5.err")"; fi

# --- W: end-to-end through the one-shot BUILD WRAPPER (real slicer, bind, gate, emit) ---
WR="$TMP/w"; mkdir -p "$WR/scripts/fastcycle" "$WR/tools"
cp -R "$REVIEW" "$WR/scripts/fastcycle/review"
find "$WR" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
printf '%b' "$BASE_SH" >"$WR/tools/legacy.sh"
( cd "$WR" && git init -q . && $GIT add -A && $GIT commit -q -m base ) >/dev/null 2>&1
printf '%b' "${BASE_SH}# touched\n" >"$WR/tools/legacy.sh"; ( cd "$WR" && $GIT commit -q -am pre-existing-only ) >/dev/null 2>&1
WSH="$WR/scripts/fastcycle/review/precheck_pack_build.sh"
run_rule sh "$WSH" --commit HEAD --out-dir "$TMP/w_out1" >"$TMP/w1.stdout" 2>"$TMP/w1.stderr"; W1=$?
if [ "$W1" -eq 0 ] && grep -q '^PRECHECK-PACK: ' "$TMP/w1.stdout"; then ok "W1 build wrapper (delta): touching a file with a PRE-EXISTING finding builds an all_pass pack (rc=0, markers printed)"
else bad "W1 wrapper rc=$W1 ($(command head -c 300 "$TMP/w1.stderr"))"; fi
printf '%b' "${BASE_SH}# touched\necho \"\$wrapper_new_var\"\n" >"$WR/tools/legacy.sh"; ( cd "$WR" && $GIT commit -q -am new-warning ) >/dev/null 2>&1
run_rule sh "$WSH" --commit HEAD --out-dir "$TMP/w_out2" >"$TMP/w2.stdout" 2>"$TMP/w2.stderr"; W2=$?
OUT="$TMP/w_out2/precheck.json"; R="$TMP/w"
if [ "$W2" -eq 1 ] && [ "$(sc '[f["rule"] for f in e.get("findings", [])]')" = "['SC2154']" ]; then ok "W2 build wrapper (delta): only the NEW warning is reported (rc=1)"
else bad "W2 wrapper rc=$W2 $(sc 'e.get("findings")') ($(command head -c 300 "$TMP/w2.stderr"))"; fi
printf '%b' "${BASE_SH}# touched\necho \"\$wrapper_new_var\"\n# later\n" >"$WR/tools/legacy.sh"; ( cd "$WR" && $GIT commit -q -am comment ) >/dev/null 2>&1
run_rule sh "$WSH" --commit HEAD~2..HEAD --out-dir "$TMP/w_out3" >"$TMP/w3.stdout" 2>"$TMP/w3.stderr"; W3=$?
if [ "$W3" -eq 1 ]; then ok "W3 build wrapper range HEAD~2..HEAD: the warning added inside the range FAILs (explicit range base honoured)"
else bad "W3 wrapper range rc=$W3 ($(command head -c 300 "$TMP/w3.stderr"))"; fi
sh "$WSH" --commit HEAD --out-dir "$TMP/w_out1" --shellcheck-rule nope >/dev/null 2>"$TMP/w4.stderr"; W4=$?
if [ "$W4" -eq 2 ]; then ok "W4 build wrapper refuses an unknown --shellcheck-rule (exit 2)"; else bad "W4 rc=$W4"; fi

# N6 the dispatch verifier accepts a consistent baseline-delta pack (its only objections here are the suite's own
#    test mode / moved-on tree) and refuses one whose mode and requested rule disagree
VER="$REVIEW/lib/precheck_pack_build_run.py"
python3 "$VER" verify --pack "$TMP/w_out1/precheck.json" >/dev/null 2>"$TMP/n6a.err"; N6A=$?
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[c for c in d["checks"] if c["check"]=="shellcheck"][0]["evidence"]["tool"]["rule"]="whole-file";json.dump(d,open(sys.argv[2],"w"))' \
    "$TMP/w_out1/precheck.json" "$TMP/n6forged.json"
python3 "$VER" verify --pack "$TMP/n6forged.json" >/dev/null 2>"$TMP/n6b.err"; N6B=$?
if [ "$N6A" -eq 1 ] && grep -q "TEST MODE" "$TMP/n6a.err" && ! grep -q "inconsistent\|did not run in" "$TMP/n6a.err" \
   && [ "$N6B" -eq 1 ] && grep -q "mode baseline-delta is inconsistent" "$TMP/n6b.err"; then
    ok "N6 the verifier accepts the delta mode of a consistent pack and refuses a mode/rule mismatch"
else bad "N6 verifier: rc=$N6A/$N6B $(command head -c 400 "$TMP/n6a.err") // $(command head -c 300 "$TMP/n6b.err")"; fi
# N7 outside test mode a cached delta pack for the same commit + rule is REUSED (not rebuilt every time)
env -u PRECHECK_TEST_MODE -u PRECHECK_TEST_LOCK_DIR sh "$WSH" --commit HEAD --out-dir "$TMP/w_out7" --shellcheck-rule baseline-delta >/dev/null 2>"$TMP/n7a.err"; N7A=$?
env -u PRECHECK_TEST_MODE -u PRECHECK_TEST_LOCK_DIR sh "$WSH" --commit HEAD --out-dir "$TMP/w_out7" --shellcheck-rule baseline-delta >"$TMP/n7b.out" 2>"$TMP/n7b.err"; N7B=$?
if [ "$N7A" -eq 0 ] && [ "$N7B" -eq 0 ] && ! grep -q "not reusable" "$TMP/n7b.err" && grep -q '^PRECHECK-PACK: ' "$TMP/n7b.out"; then
    ok "N7 a cached baseline-delta pack is reused for the same commit and rule (HEAD adds only a comment: rc 0 both times, no rebuild)"
else bad "N7 cache reuse: rc=$N7A/$N7B $(command head -c 400 "$TMP/n7b.err")"; fi

# =============================================================================
# r4 (review round 2 of ATM-1217, 11.4.276): the F1 CLASS "content accepted as
# baseline without proof it was gated at base" (K*), the F2 window-boundary
# proof (L*), the verifier seam + activation (V*), the delta-key discrimination
# (Q*) and the reviewer's surviving mutants R06/R07/R10-R13 (T*). Every case
# drives the REAL gate / builder / verifier.
# =============================================================================

# K1 (reviewer A1) extension-less, shebang-less base (never a shell candidate) gains a shebang -> new-file
new_case k1; wb tool 'echo $undefined_a\ncd $somewhere\necho done\n'; base
wh tool '#!/bin/sh\necho $undefined_a\ncd $somewhere\necho done\n'; head; gate
expect "K1 non-shell base gaining a shebang is a NEW file (its findings fail), reason base-not-shell" '(c["verdict"], e["delta"]["states"], [f.get("new_file_reason", "")[:14] for f in e["delta"]["files"]], len(e.get("findings", [])) > 0)' "('FAIL', ['new-file'], ['base-not-shell'], True)"
# K2 (reviewer A2) foo.txt -> foo.sh, bytes identical: never 'unchanged'
new_case k2; wb foo.txt 'echo $undefined_b\ncd $there\n'; base; ( cd "$R" && git mv foo.txt foo.sh ); head; gate
expect "K2 byte-identical rename of a non-shell file to .sh is a NEW file, never unchanged" '(c["verdict"], e["delta"]["states"], [f.get("renamed_from") for f in e["delta"]["files"]], e["counts"]["files_linted"])' "('FAIL', ['new-file'], ['foo.txt'], 1)"
# K3 the same rename WITH an edit
new_case k3; wb notes.txt 'echo $undefined_c\n'; base; ( cd "$R" && git mv notes.txt notes.sh ); printf 'echo more\n' >>"$R/notes.sh"; head; gate
expect "K3 rename non-shell -> .sh with an edit: NEW file, the old line's finding fails" '(c["verdict"], e["delta"]["states"], sorted({f["rule"] for f in e.get("findings", [])}))' "('FAIL', ['new-file'], ['SC2086', 'SC2154'])"
# K4 (reviewer A3, F5) mode-only change of a gated .sh carrying disable=all: unchanged, but D1 still FAILs
new_case k4; wb a.sh "#!/bin/sh\n${H} shellcheck disable=all\necho \$x\n"; base; chmod +x "$R/a.sh"; head; gate
expect "K4 unchanged file with a pre-existing disable=all FAILs (D1 policed on unchanged)" '(c["verdict"], e["delta"]["states"], "D1" in [v.split()[0] for x in e.get("directive_violations", []) for v in x["violations"]], e["counts"]["files_linted"])' "('FAIL', ['unchanged'], True, 0)"
# K4b negative control: mode-only change, a pre-existing UNJUSTIFIED (D5) directive is tolerated -> PASS
new_case k4b; wb a.sh "#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n"; base; chmod +x "$R/a.sh"; head; gate
expect "K4b unchanged file with a pre-existing D5 directive PASSes, listed as baseline" '(c["verdict"], e["delta"]["states"], len(e.get("directive_violations_baseline", [])))' "('PASS', ['unchanged'], 1)"
# K5 control: a symlink at base, a regular script at head -> new-file
new_case k5; wb target.txt 'x\n'; ( cd "$R" && ln -s target.txt a.sh ); base
rm -f "$R/a.sh"; wh a.sh '#!/bin/sh\necho $undefined_k5\n'; head; gate
expect "K5 symlink at base -> regular script: new-file (reason symlink), findings fail" '(c["verdict"], [f.get("new_file_reason") for f in e["delta"]["files"] if f["file"] == "a.sh"])' "('FAIL', ['symlink'])"
# K6 same path, base was a NON-shell script (python shebang), head is shell -> new-file
new_case k6; wb tool '#!/usr/bin/env python3\nprint("hi")\n'; base; wh tool '#!/bin/sh\necho $undefined_k6\n'; head; gate
expect "K6 python-at-base path rewritten as shell: new-file, reason base-not-shell" '(c["verdict"], [f.get("new_file_reason", "")[:14] for f in e["delta"]["files"]])' "('FAIL', ['base-not-shell'])"
# K7 case: x.SH (not a shell extension, no shebang) -> x.sh byte-identical: new-file
new_case k7; wb x.SH 'echo $undefined_k7\n'; base; ( cd "$R" && git mv x.SH x.sh ); head; gate
expect "K7 x.SH (no shebang) -> x.sh: the base was not a candidate (case-sensitive extension) -> new-file FAIL" '(c["verdict"], e["delta"]["states"])' "('FAIL', ['new-file'])"
# K7b negative control: x.SH WITH a shell shebang was a candidate at base -> identical rename is unchanged, PASS
new_case k7b; wb x.SH '#!/bin/sh\necho $undefined_k7b\n'; base; ( cd "$R" && git mv x.SH x.sh ); head; gate
expect "K7b x.SH with a shell shebang (gated at base) -> x.sh identical: unchanged, PASS" '(c["verdict"], e["delta"]["states"])' "('PASS', ['unchanged'])"
# K8 dialect change bash -> sh: base findings under sh were never gated -> new-file
new_case k8; wb a.sh '#!/bin/bash\nif [[ -n "$1" ]]; then echo yes; fi\n'; base
wh a.sh '#!/bin/sh\nif [[ -n "$1" ]]; then echo yes; fi\necho more\n'; head; gate
expect "K8 bash -> sh: SC3010 is NEW (never gated under sh), reason dialect-changed" '(c["verdict"], [f["rule"] for f in e.get("findings", [])], [f.get("new_file_reason", "")[:15] for f in e["delta"]["files"]])' "('FAIL', ['SC3010'], ['dialect-changed'])"
# K8b negative control: same dialect, other spelling (bash -> env bash) -> delta, pre-existing only -> PASS
new_case k8b; wb a.sh '#!/bin/bash\necho $undefined_k8b\n'; base; wh a.sh '#!/usr/bin/env bash\necho $undefined_k8b\necho more\n'; head; gate
expect "K8b same dialect (bash, env bash): delta, the pre-existing finding PASSes" '(c["verdict"], e["delta"]["states"])' "('PASS', ['full'])"
# K9 a legacy-exception row REMOVED in head: its pinned findings were never a pass -> new-file
new_case k9; mkdir -p "$R/config"; printf 'vendor/big.sh\tvendored\tATM-1234\tSC2086=2\t2026-10-09\n' >"$R/$TSV"
wb vendor/big.sh '#!/bin/sh\necho $1\necho $2\n'; base; : >"$R/$TSV"; wh vendor/big.sh '#!/bin/sh\necho $1\necho $2\n# row dropped\n'; head; gate
expect "K9 dropping a legacy-exception row does not launder its pinned findings: new-file, FAIL" '(c["verdict"], [f.get("new_file_reason", "")[:18] for f in e["delta"]["files"]], len(e.get("findings", [])))' "('FAIL', ['base-exception-row'], 2)"
# K10 a base blob carrying a NUL byte never passed the gate -> new-file
new_case k10; printf '#!/bin/sh\necho $undefined_k10\n# \000\n' >"$R/a.sh"; base; printf '#!/bin/sh\necho $undefined_k10\n# fixed\n' >"$R/a.sh"; head; gate
expect "K10 NUL-bearing base: new-file (reason base-nul), its finding FAILs" '(c["verdict"], [f.get("new_file_reason", "")[:8] for f in e["delta"]["files"]])' "('FAIL', ['base-nul'])"

# K11 the BASE exception ledger cannot be read (a symlink at base; unbound run, which reads it itself) ->
#     gating at base is unprovable -> new-file
new_case k11; mkdir -p "$R/config"; printf 'x\n' >"$R/config/other.tsv"; ( cd "$R/config" && ln -s other.tsv shellcheck_legacy_exceptions.tsv )
wb a.sh "$BASE_SH"; base; wh a.sh "${BASE_SH}# edited\n"; head; gate_prepare
OUT="$R.out.json"; run_rule sh "$REVIEW/precheck_pack.sh" --batch "$R.raw.json" --clean-checkout "$R.co" --out "$OUT" \
    --baseline-repo "$R" --baseline-ref "$BASE" --head-sha "$HEADC" >"$R.stdout" 2>"$R.stderr"; RC=$?
expect "K11 unreadable base ledger (unbound run): new-file, reason base-ledger-unknown, FAIL" '(c["verdict"], e["binding"]["state"], [f.get("new_file_reason", "")[:19] for f in e["delta"]["files"]])' "('FAIL', 'unbound', ['base-ledger-unknown'])"
# --- F2: window boundaries proven outside quotes / heredocs ----------------------
mk_quoted() { # <mark replacement> <open> <close> -> fixture text (lines: 3-51 and 100-130 are one multi-line construct)
    python3 - "$1" "$2" "$3" <<'PY'
import sys
mark, op, cl = sys.argv[1:4]
L = ["#!/bin/sh", "# STUB_OOM_IF brandnew"]
L += [op] + ["text%d don't" % i if op.startswith("cat") else "text%d" % i for i in range(4, 51)] + [cl]
L += ["echo line%d" % i for i in range(52, 80)] + [mark] + ["echo line%d" % i for i in range(81, 100)]
L += [op.replace("x=", "y=")] + ["word%d it's" % i if op.startswith("cat") else "word%d" % i for i in range(101, 130)] + [cl]
L += ['echo "${x:-}${y:-}"']
sys.stdout.write("\n".join(L) + "\n")
PY
}
# L1 (reviewer A4) a window cut inside a multi-line single-quoted string used to swallow the new code
new_case l1; mk_quoted 'echo base_line' "x='" "'" >"$R/a.sh"; base; mk_quoted 'echo $brandnew' "x='" "'" >"$R/a.sh"; head; gate
expect "L1 window boundary inside a '..' string is moved to a proven boundary: the NEW finding FAILs" '(c["verdict"], sorted({(f["rule"], f["line"]) for f in e.get("findings", [])}), e["delta"]["files"][0]["windows"]["head"][0].split("-")[0])' "('FAIL', [('SC2086', 80), ('SC2154', 80)], '3')"
# L2 the same through heredoc bodies carrying apostrophes (a cut inside them re-pairs quotes)
new_case l2; mk_quoted 'echo base_line' "cat <<EOF" "EOF" >"$R/a.sh"; base; mk_quoted 'echo $brandnew' "cat <<EOF" "EOF" >"$R/a.sh"; head; gate
expect "L2 window boundary inside a heredoc body is moved out: the NEW finding FAILs" '(c["verdict"], sorted({(f["rule"], f["line"]) for f in e.get("findings", [])}))' "('FAIL', [('SC2086', 80), ('SC2154', 80)])"
# L3 multi-line double-quoted string
new_case l3; mk_quoted 'echo base_line' 'x="' '"' >"$R/a.sh"; base; mk_quoted 'echo $brandnew' 'x="' '"' >"$R/a.sh"; head; gate
expect "L3 window boundary inside a \"..\" string is moved out: the NEW finding FAILs" '(c["verdict"], sorted({(f["rule"], f["line"]) for f in e.get("findings", [])}))' "('FAIL', [('SC2086', 80), ('SC2154', 80)])"
# L4 negative control: the same shape with NO multi-line construct keeps the bounded window and PASSes
new_case l4; mk_quoted 'echo base_line' "x=''" "x2=''" >"$R/a.sh"; base; mk_quoted 'echo brandnew_but_clean' "x=''" "x2=''" >"$R/a.sh"; head; gate
expect "L4 plain code: bounded window kept (starts at 40), nothing new -> PASS" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0]["windows"]["head"])' "('PASS', 'window', ['40-120'])"
# L5 a construct the lexer does not model (case inside \$(..)) before the change -> unresolved, never a guess
L5=$( { printf '#!/bin/sh\n# STUB_OOM_FULL\nv=$(case "$1" in a) echo a;; esac)\n'; i=4; while [ $i -le 120 ]; do printf 'echo l%s\n' "$i"; i=$((i+1)); done; printf 'echo "$v"\n'; } )
new_case l5; printf '%s\n' "$L5" >"$R/a.sh"; base; printf '%s\n' "$L5" | sed 's/^echo l80$/echo l80b/' >"$R/a.sh"; head; gate
expect "L5 lexer UNKNOWN (case in \$(..)) -> unresolved FAIL naming the lexer" '(c["verdict"], e["delta"]["files"][0]["state"], "lexer:" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"

# L6 lexer self-consistency: a file that does not END at a neutral boundary (unterminated quote, or a model
#    mismatch that flipped the quote parity somewhere) trusts no boundary -> unresolved
L6=$( { printf '#!/bin/sh\n# STUB_OOM_FULL\n'; i=3; while [ $i -le 100 ]; do printf 'echo l%s\n' "$i"; i=$((i+1)); done; printf "echo 'unterminated\\n"; } )
new_case l6; printf '%s\n' "$L6" >"$R/a.sh"; base; printf '%s\n' "$L6" | sed 's/^echo l50$/echo l50b/' >"$R/a.sh"; head; gate
expect "L6 a file not ending neutral -> unresolved FAIL, no boundary trusted" '(c["verdict"], e["delta"]["files"][0]["state"], "does not end at a neutral boundary" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"
# --- F4: the delta key ---------------------------------------------------------
# Q1 fix one SC2086, add a DIFFERENT SC2086 elsewhere -> FAIL (the line text is part of the key; kills R04)
new_case q1; wb a.sh '#!/bin/sh\necho $1\necho done\n'; base; wh a.sh '#!/bin/sh\necho "$1"\necho done\necho again $2\n'; head; gate
expect "Q1 a fixed SC2086 does not pay for a new SC2086 on another line" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2086', 4)])"
# Q2 a pre-existing finding whose MESSAGE cites a line number moves -> PASS (line N rewrite; kills R05)
new_case q2; wb a.sh '#!/bin/sh\ncase "$1" in\n  a) echo 1;;\n  a) echo 2;;\nesac\n'; base
wh a.sh '#!/bin/sh\necho p1\necho p2\necho p3\ncase "$1" in\n  a) echo 1;;\n  a) echo 2;;\nesac\n'; head; gate
expect "Q2 moved SC2221/SC2222 ('... on line N') stay pre-existing -> PASS" '(c["verdict"], sorted(f["rule"] for f in e.get("baseline_findings", [])))' "('PASS', ['SC2221', 'SC2222'])"

# --- reviewer mutants R06 R07 R10 R11 R12 R13: one case each -------------------
# T6 (R06) base over the size cap, its only window covers the whole base -> unresolved (no bound)
T6B=$( { printf '#!/bin/sh\necho "$undefined_pre"\n'; i=3; while [ $i -le 25 ]; do printf 'echo "b%s"\n' "$i"; i=$((i+1)); done; } )
new_case t6; printf '%s\n' "$T6B" >"$R/a.sh"; base; printf '%s\n' "$T6B" | sed '10,19d' >"$R/a.sh"; head; gate --shellcheck-max-lines 20
expect "T6 base over cap, base window = whole base -> FAIL unresolved (no bound)" '(c["verdict"], e["delta"]["files"][0]["state"], "base window covers the whole file" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"
# T7 (R07) windows spanning > WINDOW_MAX_LINES -> unresolved
T7B=$(i=1; printf '#!/bin/sh\n'; while [ $i -le 4000 ]; do printf 'echo "x%s"\n' "$i"; i=$((i+1)); done)
new_case t7; printf '%s\n' "$T7B" >"$R/a.sh"; base
printf '%s\n' "$T7B" | awk 'NR>=6 && NR<=1566 && (NR-6)%60==0 {sub(/"x/, "\"y")} {print}' >"$R/a.sh"; head; gate --shellcheck-max-lines 1000
expect "T7 windows over WINDOW_MAX_LINES -> FAIL unresolved (windows span)" '(c["verdict"], e["delta"]["files"][0]["state"], "windows span" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"
# T10 (R10) the parity oracle runs on HEAD windows: its re-lint fails (stub) -> unresolved, never a plain lint
T10='#!/bin/sh\n# STUB_OOM_FULL\none() {\n    echo one\n}\ntwo() {\n# STUB_OOM_IF xhellcheck\n    echo "the shellcheck word"\n    echo two\n}\none\ntwo\n'
new_case t10; wb a.sh "$T10"; base; wh a.sh "$(printf '%b' "$T10" | sed 's/echo two/echo three/')\n"; head; gate
expect "T10 head windows are linted differentially: the parity re-lint failure -> FAIL unresolved" '(c["verdict"], e["delta"]["files"][0]["state"], "parity lint" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"
# T11 (R11) a >= LARGE_LINES base lint takes the host-wide lock: held elsewhere -> never linted unlocked
LOCKP="$PRECHECK_TEST_LOCK_DIR/helix-precheck-shellcheck-large-$(id -u).lock"
T11B=$( { printf '#!/bin/sh\necho "$undefined_pre"\n'; i=3; while [ $i -le 5002 ]; do printf 'echo "x%s"\n' "$i"; i=$((i+1)); done; } )
new_case t11; printf '%s\n' "$T11B" >"$R/a.sh"; base; printf '%s\n' "$T11B" | sed -n '1,100p' >"$R/a.sh"; printf '# cut\n' >>"$R/a.sh"; head
python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"a");fcntl.flock(f.fileno(),fcntl.LOCK_EX);open(sys.argv[2],"w").close();time.sleep(60)' "$LOCKP" "$TMP/t11.ready" &
T11P=$!; i=0; while [ ! -f "$TMP/t11.ready" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
gate --shellcheck-exception-timeout 0.5; kill "$T11P" 2>/dev/null; wait "$T11P" 2>/dev/null
expect "T11 large base lint waits for the held lock and never runs unlocked (state not full, cause names the lock)" '(c["verdict"], e["delta"]["files"][0]["state"] != "full", "large-lint lock" in e["delta"]["files"][0]["cause"][0])' "('FAIL', True, True)"
# T12 (R12) the window prefix is the file's REAL shebang: its own finding (SC2096) is real line 1, pre-existing
#     (two windows per side: the prefix finding is counted ONCE per side, F14)
T12=$( { printf '#!/usr/bin/env bash -e\n# STUB_OOM_FULL\n'; i=3; while [ $i -le 260 ]; do printf 'echo l%s\n' "$i"; i=$((i+1)); done; } )
new_case t12; printf '%s\n' "$T12" >"$R/a.sh"; base; printf '%s\n' "$T12" | sed -e 's/^echo l50$/echo l50b/' -e 's/^echo l200$/echo l200b/' >"$R/a.sh"; head; gate
expect "T12 window prefix = real shebang: SC2096 attributed to line 1, once, pre-existing -> PASS (2 windows)" '(c["verdict"], e["delta"]["states"], e["delta"]["files"][0]["windows"]["head"], [(f["rule"], f["line"]) for f in e.get("baseline_findings", [])])' "('PASS', ['window'], ['10-90', '160-240'], [('SC2096', 1)])"
# T18 a window boundary inside a backslash-newline continuation is moved to the command's first line, on both
#     sides, so the joined command (SC2115) is analysed whole (the cut is symmetric, so the verdict alone would not
#     show it: the recorded windows do)
T18=$( { printf '#!/bin/sh\n# STUB_OOM_IF oldtoken\nd=$1\n'; i=4; while [ $i -le 39 ]; do printf 'echo l%s\n' "$i"; i=$((i+1)); done
         printf 'rm -rf \\\n  "$d"/*\n'; i=42; while [ $i -le 120 ]; do printf 'echo l%s\n' "$i"; i=$((i+1)); done; } )
new_case t18; printf '%s\n' "$T18" | sed 's/^echo l81$/echo oldtoken/' >"$R/a.sh"; base; printf '%s\n' "$T18" | sed 's/^echo l81$/echo newtoken/' >"$R/a.sh"; head; gate
expect "T18 continuation cut avoided: both windows start at the command line 40 (not 41), pre-existing SC2115 -> PASS" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0]["windows"], sorted((f["rule"], f["line"]) for f in e.get("baseline_findings", [])))' "('PASS', 'window', {'base': ['40-120'], 'head': ['40-120']}, [('SC2115', 41), ('SC2154', 41)])"
# T13 (R13) `git diff --no-index` failing (rc 128, stub) is never parsed as hunks -> unresolved
mkdir -p "$TMP/gitstub"; REAL_GIT=$(command -v git)
printf '#!/bin/sh\ncase " $* " in *" --no-index "*) if [ -n "${STUB_GIT_NOINDEX_RC:-}" ]; then "%s" "$@"; exit "$STUB_GIT_NOINDEX_RC"; fi ;; esac\nexec "%s" "$@"\n' "$REAL_GIT" "$REAL_GIT" >"$TMP/gitstub/git"
chmod +x "$TMP/gitstub/git"
new_case t13; wb a.sh "$C6"; base; wh a.sh "$(printf '%b' "$C6" | sed 's/echo changed_old/echo changed_new/')\n"; head; gate_prepare
OLDPATH13=$PATH; PATH="$TMP/gitstub:$PATH"; STUB_GIT_NOINDEX_RC=128; export PATH STUB_GIT_NOINDEX_RC
run_rule gate_run; PATH=$OLDPATH13; unset STUB_GIT_NOINDEX_RC; export PATH
expect "T13 a failing git diff (rc 128) -> FAIL unresolved (no hunks), never windows from its output" '(c["verdict"], e["delta"]["files"][0]["state"], "no hunks" in e["delta"]["files"][0].get("window_fallback", ""))' "('FAIL', 'unresolved', True)"

# --- F3 + F8: the dispatch verifier ------------------------------------------------
# V1-V4 forged packs, body_hash RECOMPUTED, so the named inconsistency is the ONLY new reason (R01 R02 R03)
forge() { # <in> <out> <python statement over ev (shellcheck evidence)>
    python3 - "$REVIEW/lib" "$1" "$2" "$3" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from precheck_common import _body_hash_of
d = json.load(open(sys.argv[2]))
ev = [c for c in d["checks"] if c["check"] == "shellcheck"][0]["evidence"]
exec(sys.argv[4], {"ev": ev, "d": d})
d["body_hash"] = _body_hash_of(d)
json.dump(d, open(sys.argv[3], "w"))
PY
}
reasons() { python3 "$VER" verify --pack "$1" 2>&1 >/dev/null | sed -n 's/^NOT-READY: //p' | sort; }
PK="$TMP/w_out1/precheck.json"; reasons "$PK" >"$TMP/v0.r"
vcase() { # <id> <label> <forge statement> <expected ONLY new reason (substring)> [<reason allowed to go (substring)>]
    forge "$PK" "$TMP/$1.json" "$3"; reasons "$TMP/$1.json" >"$TMP/$1.r"
    NEWR=$(comm -13 "$TMP/v0.r" "$TMP/$1.r"); GONE=$(comm -23 "$TMP/v0.r" "$TMP/$1.r")
    if [ -n "${5:-}" ]; then GONE=$(printf '%s\n' "$GONE" | grep -vF -- "$5"); fi
    if [ -n "$NEWR" ] && [ "$(printf '%s\n' "$NEWR" | wc -l)" -eq 1 ] && printf '%s' "$NEWR" | grep -qF -- "$4" && [ -z "$GONE" ]; then
        ok "$1 $2"
    else bad "$1 $2: new reasons [$NEWR] gone [$GONE]"; fi
}
vcase V1 "verifier refuses a delta pack with base_resolved false (only new reason)" 'ev["delta"]["base_resolved"] = False' "mode baseline-delta is inconsistent"
vcase V2 "verifier refuses a delta pack with no rule_id (only new reason)" 'del ev["delta"]["rule_id"]' "mode baseline-delta is inconsistent"
vcase V3 "verifier refuses a delta pack whose rule_id is not this gate's (only new reason)" 'ev["delta"]["rule_id"] = "shellcheck-baseline-delta/1"' "is not this gate's"
vcase V4 "verifier refuses mode whole-file recorded with tool.rule baseline-delta (only new reason)" 'ev["mode"] = "whole-file"' "did not run in whole-file or baseline-delta mode" "not activated for dispatch"
# V5 (F8) without the operator's activation record the delta mode is never dispatch-ready
if grep -q "baseline-delta is not activated for dispatch" "$TMP/v0.r"; then ok "V5 a consistent delta pack is NOT dispatch-ready without the activation record"
else bad "V5 activation not required: $(cat "$TMP/v0.r")"; fi
# V6 with a well-formed record (in the W copy only) the activation reason disappears; a malformed one is refused
WVER="$WR/scripts/fastcycle/review/lib/precheck_pack_build_run.py"; ACT="$WR/scripts/fastcycle/review/precheck_shellcheck_delta.activation"
printf 'decision-ref: operator decision 2026-10-13 ATM-1217\nactivated-on: 2026-10-13\n' >"$ACT"
python3 "$WVER" verify --pack "$PK" >/dev/null 2>"$TMP/v6a.err"
printf 'decision-ref: x\n' >"$ACT"
python3 "$WVER" verify --pack "$PK" >/dev/null 2>"$TMP/v6b.err"; rm -f "$ACT"
if ! grep -q "not activated" "$TMP/v6a.err" && grep -q "TEST MODE" "$TMP/v6a.err" && grep -q "needs 'decision-ref" "$TMP/v6b.err"; then
    ok "V6 a well-formed activation record lifts only the activation reason; a malformed one is refused"
else bad "V6 activation record: $(cut -c1-300 "$TMP/v6a.err") // $(cut -c1-300 "$TMP/v6b.err")"; fi

echo "== summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
