#!/bin/sh
# shellcheck disable=SC2016 # printf and heredoc fixtures are literal shell text whose dollar signs must not expand
# fastcycle-timeout-s: 900
# =============================================================================
# test_precheck_shellcheck_baseline_delta.sh (ATM-1217 r3)
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
    else bad "$1: $2 -> '$got', expected '$3' (rc=${RC:-?}; $(head -c 300 "$R.stderr" 2>/dev/null))"; fi
}
H=$(printf '\043')   # '#', so this file's own source carries no directive-shaped line

BASE_SH='#!/bin/sh\n# base fixture\nhelper() {\n    echo "$undefined_pre"\n}\nhelper\n'

echo "== precheck shellcheck row: baseline-delta rule (r3, on the round-6 gate) =="
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
else bad "C15 determinism: $(head -c 300 "$R.det.err")"; fi

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
else bad "N3b unknown rule rc=$N3B $(head -c 200 "$R.stderr")"; fi
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
else bad "N5 cache rule check: rc=$N5 $(head -c 300 "$TMP/n5.err")"; fi

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
else bad "W1 wrapper rc=$W1 ($(head -c 300 "$TMP/w1.stderr"))"; fi
printf '%b' "${BASE_SH}# touched\necho \"\$wrapper_new_var\"\n" >"$WR/tools/legacy.sh"; ( cd "$WR" && $GIT commit -q -am new-warning ) >/dev/null 2>&1
run_rule sh "$WSH" --commit HEAD --out-dir "$TMP/w_out2" >"$TMP/w2.stdout" 2>"$TMP/w2.stderr"; W2=$?
OUT="$TMP/w_out2/precheck.json"; R="$TMP/w"
if [ "$W2" -eq 1 ] && [ "$(sc '[f["rule"] for f in e.get("findings", [])]')" = "['SC2154']" ]; then ok "W2 build wrapper (delta): only the NEW warning is reported (rc=1)"
else bad "W2 wrapper rc=$W2 $(sc 'e.get("findings")') ($(head -c 300 "$TMP/w2.stderr"))"; fi
printf '%b' "${BASE_SH}# touched\necho \"\$wrapper_new_var\"\n# later\n" >"$WR/tools/legacy.sh"; ( cd "$WR" && $GIT commit -q -am comment ) >/dev/null 2>&1
run_rule sh "$WSH" --commit HEAD~2..HEAD --out-dir "$TMP/w_out3" >"$TMP/w3.stdout" 2>"$TMP/w3.stderr"; W3=$?
if [ "$W3" -eq 1 ]; then ok "W3 build wrapper range HEAD~2..HEAD: the warning added inside the range FAILs (explicit range base honoured)"
else bad "W3 wrapper range rc=$W3 ($(head -c 300 "$TMP/w3.stderr"))"; fi
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
else bad "N6 verifier: rc=$N6A/$N6B $(head -c 400 "$TMP/n6a.err") // $(head -c 300 "$TMP/n6b.err")"; fi
# N7 outside test mode a cached delta pack for the same commit + rule is REUSED (not rebuilt every time)
env -u PRECHECK_TEST_MODE -u PRECHECK_TEST_LOCK_DIR sh "$WSH" --commit HEAD --out-dir "$TMP/w_out7" --shellcheck-rule baseline-delta >/dev/null 2>"$TMP/n7a.err"; N7A=$?
env -u PRECHECK_TEST_MODE -u PRECHECK_TEST_LOCK_DIR sh "$WSH" --commit HEAD --out-dir "$TMP/w_out7" --shellcheck-rule baseline-delta >"$TMP/n7b.out" 2>"$TMP/n7b.err"; N7B=$?
if [ "$N7A" -eq 0 ] && [ "$N7B" -eq 0 ] && ! grep -q "not reusable" "$TMP/n7b.err" && grep -q '^PRECHECK-PACK: ' "$TMP/n7b.out"; then
    ok "N7 a cached baseline-delta pack is reused for the same commit and rule (HEAD adds only a comment: rc 0 both times, no rebuild)"
else bad "N7 cache reuse: rc=$N7A/$N7B $(head -c 400 "$TMP/n7b.err")"; fi

echo "== summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
