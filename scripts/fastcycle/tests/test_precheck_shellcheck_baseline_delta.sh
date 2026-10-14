#!/bin/sh
# shellcheck disable=SC2016 # printf and heredoc fixtures are literal shell text whose dollar signs must not expand
# fastcycle-timeout-s: 900
# =============================================================================
# test_precheck_shellcheck_baseline_delta.sh (ATM-1217 r3 + r4 + r5 + r6)
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
# (exit 251 "out of memory" whenever the marker line is part of the input),
# `# STUB_OOM_IF <token>` (the same, only
# when <token> also occurs elsewhere in the input), `# STUB_RC1EMPTY` (exit 1, no
# stdout), `# STUB_RC0EMPTY` (exit 0, no stdout).
#
# r5: the stub also appends the LINE COUNT of every lint input to $TMP/lintlog (the
# G-class census: since r5 every lint input must be a WHOLE head or base blob).
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
wc -l <"\$t" | tr -d ' ' >>"$TMP/lintlog"
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

echo "== precheck shellcheck row: baseline-delta rule (r5, on the round-6 gate) =="
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

# C5a head timeout -> BLIND (r5: no window fallback; the whole-file verdict)
new_case c5; wb a.sh "$BASE_SH"; base; wh a.sh "#!/bin/sh\n# STUB_HANG\n# base fixture\nhelper() {\n    echo \"\$undefined_pre\"\n}\nhelper\n"; head
gate --shellcheck-timeout 1
expect "C5a head timeout -> FAIL" 'c["verdict"]' FAIL
expect "C5a state blind, cause names the head timeout" '(e["delta"]["files"][0]["state"], e["delta"]["files"][0]["cause"].startswith("shellcheck exceeded"))' "('blind', True)"

# C5b head timeout on a NEW file -> FAIL (BLIND)
new_case c5b; wb old.sh '#!/bin/sh\necho ok\n'; base; wh new.sh '#!/bin/sh\n# STUB_HANG\necho "$x"\n'; head; gate --shellcheck-timeout 1
expect "C5b new-file head timeout -> FAIL (BLIND)" '(c["verdict"], any("BLIND" in x["message"] for x in e.get("errors", [])))' "('FAIL', True)"

# C6 OOM on the BASE full lint only -> no baseline: judged as a NEW file (r5; the whole-file verdict), FAIL on the
#    pre-existing finding too -- never a window, never a partial base
C6='#!/bin/sh\n# STUB_OOM_IF changed_old\nhelper() {\n    echo "$undefined_pre"\n}\nother() {\n    echo changed_old\n}\nhelper\nother\n'
new_case c6; wb a.sh "$C6"; base; wh a.sh "$(printf '%b' "$C6" | sed 's/echo changed_old/echo changed_new/')\n"; head; gate
expect "C6 base-only OOM -> new-file FAIL, reason base-unlintable (exit 251)" '(c["verdict"], e["delta"]["states"], e["delta"]["files"][0]["new_file_reason"].startswith("base-unlintable: shellcheck exited 251"))' "('FAIL', ['new-file'], True)"
expect "C6 every head finding is new (new_in new-file), nothing listed as baseline" '([(f["rule"], f["line"], f["new_in"]) for f in e.get("findings", [])], e.get("baseline_findings"))' "([('SC2154', 4, 'new-file')], None)"
# C6b same base OOM, a NEW warning as well -> FAIL with both
new_case c6b; wb a.sh "$C6"; base; wh a.sh "$(printf '%b' "$C6" | sed 's/echo changed_old/echo "$added_in_c6b"/')\n"; head; gate
expect "C6b base OOM + new warning -> FAIL, both findings new" '(c["verdict"], [(f["rule"], f["line"], f["new_in"]) for f in e.get("findings", [])])' "('FAIL', [('SC2154', 4, 'new-file'), ('SC2154', 7, 'new-file')])"

# C7 head full-lint OOM -> BLIND FAIL (r5), no finding is guessed from a part of the file
C7='#!/bin/sh\n# STUB_OOM_FULL\none() {\n    echo one\n}\ntwo() {\n    echo two\n}\none\ntwo\n'
new_case c7; wb a.sh "$C7"; base; wh a.sh "$(printf '%b' "$C7" | sed 's/echo two/echo "$added_undefined"/')\n"; head; gate
expect "C7 head OOM -> FAIL, state blind, no findings, cause = exit 251" '(c["verdict"], e["delta"]["files"][0]["state"], e.get("findings"), e["delta"]["files"][0]["cause"].startswith("shellcheck exited 251"))' "('FAIL', 'blind', None, True)"
# C7b same head-OOM shape, only a pre-existing finding -> still FAIL (r4 PASSed this through a window)
C7B='#!/bin/sh\n# STUB_OOM_FULL\none() {\n    echo "$undefined_pre"\n    echo old\n}\none\n'
new_case c7b; wb a.sh "$C7B"; base; wh a.sh "$(printf '%b' "$C7B" | sed 's/echo old/echo new/')\n"; head; gate
expect "C7b head OOM with only a pre-existing finding -> FAIL blind (never a window PASS)" '(c["verdict"], e["delta"]["states"], len(e.get("baseline_findings", [])))' "('FAIL', ['blind'], 0)"

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
#     under a 2048 MiB cap the head lint is killed -> BLIND FAIL
new_case c14
python3 -c 'import sys;open(sys.argv[1],"w").write("#!/bin/sh\nbig() {\n"+"".join("    x%d=\"$1\"; echo \"$x%d\"\n"%(i,i) for i in range(1100))+"}\nbig\n")' "$R/a.sh"; base
python3 -c 'import sys;p=sys.argv[1];s=open(p).read().replace("}\nbig\n","    echo \"$c14_new\"\n}\nbig\n");open(p,"w").write(s)' "$R/a.sh"; head
gate --shellcheck-memory-cap-mib 2048
expect "C14 2048 MiB cap kills the head lint -> FAIL, blind, never a clean pass" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0]["cause"].startswith("shellcheck killed by signal"))' "('FAIL', 'blind', True)"
# C14c (M10 successor) the delta rule's BASE lint runs under the same per-run memory cap: a small head lints whole,
#      the big base is killed under 2048 MiB -> no baseline (base-unlintable, killed by signal), never linted uncapped
new_case c14c
python3 -c 'import sys;open(sys.argv[1],"w").write("#!/bin/sh\nbig() {\n"+"".join("    x%d=\"$1\"; echo \"$x%d\"\n"%(i,i) for i in range(1100))+"}\nbig\n")' "$R/a.sh"; base
printf '#!/bin/sh\nbig() {\n    x0="$1"; echo "$x0"\n    echo "$c14c_new"\n}\nbig\n' >"$R/a.sh"; head
gate --shellcheck-memory-cap-mib 2048
expect "C14c base killed under the run's 2048 MiB cap -> new-file, reason base-unlintable: killed by signal" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0].get("new_file_reason", "").startswith("base-unlintable: shellcheck killed by signal"))' "('FAIL', 'new-file', True)"
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
expect "C16 rc=1 + empty stdout is NOT a clean PASS" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'blind')"

new_case c16b; wb a.sh '#!/bin/sh\necho ok\n'; base; wh a.sh '#!/bin/sh\n# STUB_RC0EMPTY\necho ok\n'; head; gate
expect "C16b rc=0 + empty stdout is NOT a clean PASS either" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'blind')"

# C17 golden-bad: a SECOND occurrence of an identical pre-existing finding is NEW (multiset, not set)
new_case c17; wb a.sh '#!/bin/sh\nhelper() {\n    cd /tmp\n}\nhelper\n'; base
wh a.sh '#!/bin/sh\nhelper() {\n    cd /tmp\n}\nhelper2() {\n    cd /tmp\n}\nhelper\nhelper2\n'; head; gate
expect "C17 duplicate occurrence FAILs, exactly one new (the later one)" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2164', 6)])"

# C18 head OOM on a file with a long if-block -> BLIND (r4 refused a mid-construct window; r5 has no window)
C18=$( { printf '#!/bin/sh\n# STUB_OOM_FULL\nif [ -n "$1" ]; then\n'; i=0; while [ $i -lt 100 ]; do printf '    echo "l%s"\n' "$i"; i=$((i+1)); done; printf 'fi\n'; } )
new_case c18; printf '%s\n' "$C18" >"$R/a.sh"; base; printf '%s\n' "$C18" | sed 's/echo "l95"/echo "l95 edited"/' >"$R/a.sh"; head; gate
expect "C18 head OOM -> FAIL, state blind" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'blind')"

# C19 negative control: a pre-existing finding FIXED in head -> PASS, nothing new
new_case c19; wb a.sh "$BASE_SH"; base; wh a.sh '#!/bin/sh\nhelper() {\n    echo "ok"\n}\nhelper\n'; head; gate
expect "C19 fixed finding -> PASS, nothing reported" '(c["verdict"], e.get("findings"), e.get("baseline_findings"))' "('PASS', None, None)"

# C20 a mode-only change (byte-identical blob) is not linted: an unlintable file does not hang the batch
new_case c20; wb a.sh '#!/bin/sh\n# STUB_HANG\necho "$u"\n'; base; chmod +x "$R/a.sh"; head; gate --shellcheck-timeout 1
expect "C20 byte-identical file: state unchanged, not linted, PASS" '(c["verdict"], e["delta"]["states"], e["counts"]["files_linted"])' "('PASS', ['unchanged'], 0)"

# C21 head OOM, change in top-level code of a tiny file -> BLIND
C21='#!/bin/sh\n# STUB_OOM_FULL\necho one\necho two\n'
new_case c21; wb a.sh "$C21"; base; wh a.sh "$(printf '%b' "$C21" | sed 's/echo two/echo "$new_undefined"/')\n"; head; gate
expect "C21 head OOM -> FAIL blind" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'blind')"

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
# N4 the size cap: an over-cap head of a tracked file is BLIND under the delta rule too (r5: no window fallback)
N4BODY=$( { printf '#!/bin/sh\n'; i=0; while [ $i -lt 30 ]; do printf 'f%s() {\n    echo "%s"\n}\n' "$i" "$i"; i=$((i+1)); done; } )
new_case n4; printf '%s\n' "$N4BODY" >"$R/a.sh"; base; printf '%s\n' "$N4BODY" | sed 's/echo "17"/echo "$n4_new"/' >"$R/a.sh"; head
gate --shellcheck-max-lines 50
expect "N4 head over the size cap -> FAIL blind, no finding guessed, cause names the cap" '(c["verdict"], e["delta"]["files"][0]["state"], e.get("findings"), "exceeds the size cap" in e["delta"]["files"][0]["cause"])' "('FAIL', 'blind', None, True)"
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
# baseline without proof it was gated at base" (K*), the verifier seam +
# activation (V*), the delta-key discrimination (Q*) and the reviewer's mutants
# (T*). r5 (review round 3, structural): the G CLASS "a lint input that is not
# the whole file" (G*, the window fallback is removed) and the committed
# activation record (V6*). Every case drives the REAL gate / builder / verifier.
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
# K8c (reviewer X05) the `shell=` half of the dialect: same shebang, the base's `shell=bash` directive dropped in
#     head -> dialect-changed, new-file (under -s sh both sides report SC3010; only the dialect check makes it new)
new_case k8c; wb a.sh "#!/bin/sh\n${H} shellcheck shell=bash\nif [[ -n \"\$1\" ]]; then echo yes; fi\n"; base
wh a.sh '#!/bin/sh\nif [[ -n "$1" ]]; then echo yes; fi\necho more\n'; head; gate
expect "K8c shell= directive dropped (shebang unchanged) -> dialect-changed, SC3010 new -> FAIL" '(c["verdict"], [f["rule"] for f in e.get("findings", [])], [f.get("new_file_reason", "")[:15] for f in e["delta"]["files"]])' "('FAIL', ['SC3010'], ['dialect-changed'])"
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
# --- r5 G-class (11.4.276(C)): "a lint input that is not the whole file can mean something else than the file" ---
# r3/r4 linted WINDOWS (parts of a file) when a side could not be linted whole. Two review rounds in a row found
# a window that meant something else than the file (r4 review G1: a directive at the top of a window took FILE
# scope; G2: the window lexer read a mid-word `#` after `)`/backtick as a comment). r5 removed the window fallback;
# every member of the class below is driven through the real gate with a head that cannot be linted whole
# (`# STUB_OOM_IF brandnew`, the token sits in the head's new line). Each member must FAIL as BLIND, and the census
# of lint inputs ($TMP/lintlog, written by the stub) must show only WHOLE head / base blobs (line counts).
# Control needle per member (11.4.273): the same head with a lintable line 2 FAILs with the real new finding
# (state full), so the defect is real and the instrument sees it. Negative control: a lintable head without the
# defect PASSes (state full).
gfix() { # <member> <variant: base|bad|clean> <line-2 token> -> fixture on stdout (the change sits at line 80)
    python3 - "$1" "$2" "$3" <<'PY'
import sys
m, var, tok = sys.argv[1:4]
H = "#"
mark = {"base": "echo base_line", "bad": "cd /nonexist " + H + " brandnew", "clean": "echo changed_line"}[var]
end = []
if m in ("q1", "q3", "q2"):
    op, cl, txt = {"q1": ("x='", "'", "text%d"), "q3": ('x="', '"', "text%d"),
                   "q2": ("cat <<EOF", "EOF", "text%d don't")}[m]
    pre = [op] + [txt % i for i in range(4, 51)] + [cl]
    if m != "q2":
        end = ['echo "$x"']
elif m.startswith("h"):
    op = {"h1": "x=$(true)" + H + "'", "h2": "x=`true`" + H + "'", "h3": "x=$((1))" + H + "'",
          "h4": "x=${HOME}" + H + "'"}[m]
    pre = [op] + [("text%d \"" % i) if i == 45 else "text%d" % i for i in range(4, 51)] + ["' " + H + "'"]
    end = ['echo "$x"']
elif m == "d1":
    pre = ["echo line%d" % i for i in range(3, 40)]
    pre += [H + " shellcheck disable=SC2164 " + H + " justified: the cd target always exists here", "cd /tmp || exit 1"]
elif m == "c1":
    pre = ["d=$1"] + ["echo line%d" % i for i in range(4, 79)] + ["rm -rf \\"]
    mark = "  \"$d\"/" + {"base": "old_glob", "bad": "* " + H + " brandnew", "clean": "new_glob"}[var]
elif m == "s1":
    pre = ['if [ -n "$1" ]; then'] + ["    echo l%d" % i for i in range(4, 80)]
    mark = "    " + mark
    end = ["fi"]
elif m == "k1":
    pre = ['v=$(case "$1" in a) echo a;; esac)']
    end = ['echo "$v"']
elif m == "o1":
    pre = ["unused_x=1"]
    mark = {"base": 'echo "$unused_x"', "bad": "echo gone " + H + " brandnew", "clean": 'echo "$unused_x" ' + H + " used"}[var]
L = ["#!/bin/sh", H + " STUB_OOM_IF " + tok] + pre
L += ["echo line%d" % i for i in range(len(L) + 1, 80)]
assert len(L) == 79, (m, len(L))
L.append(mark)
L += ["echo line%d" % i for i in range(81, 90)]
L += ["echo '\"' " + H + " '"] if m.startswith("h") else ["echo line90"]
L += ["echo line%d" % i for i in range(91, 131)] + end
sys.stdout.write("\n".join(L) + "\n")
PY
}
census() { # -> "ok" when every logged lint input has the line count of the whole head or the whole base
    python3 - "$TMP/lintlog" "$R/a.sh" "$R.base.sh" <<'PY'
import sys
got = [int(x) for x in open(sys.argv[1]).read().split()]
whole = {sum(1 for _ in open(sys.argv[2], "rb")), sum(1 for _ in open(sys.argv[3], "rb"))}
bad = [n for n in got if n not in whole]
print("ok" if got and not bad else "inputs %s, whole %s" % (got, sorted(whole)))
PY
}
# member -> the real new finding the control needle must show (rule@line)
for gm in q1:SC2164@80 q2:SC2164@80 q3:SC2164@80 h1:SC2164@80 h2:SC2164@80 h3:SC2164@80 h4:SC2164@80 \
          d1:SC2164@80 c1:SC2115@80 s1:SC2164@80 k1:SC2164@80 o1:SC2034@3; do
    m=${gm%%:*}; want=${gm#*:}; wr=${want%@*}; wl=${want#*@}
    new_case "g_$m"; gfix "$m" base brandnew >"$R/a.sh"; cp "$R/a.sh" "$R.base.sh"; base  # base: token never elsewhere
    gfix "$m" bad brandnew >"$R/a.sh"; head; : >"$TMP/lintlog"; gate
    expect "G[$m] head not lintable whole -> FAIL BLIND, no window, no guessed finding" '(c["verdict"], e["delta"]["states"], any("windows" in f for f in e["delta"]["files"]), e.get("findings"))' "('FAIL', ['blind'], False, None)"
    CEN=$(census); if [ "$CEN" = ok ]; then ok "G[$m] census: every lint input is a WHOLE head or base blob"; else bad "G[$m] census: $CEN"; fi
    new_case "g_${m}_ctl"; gfix "$m" base zz_absent >"$R/a.sh"; base; gfix "$m" bad zz_absent >"$R/a.sh"; head; gate
    expect "G[$m] control needle: lintable head -> FAIL full with the real $wr at line $wl" "(c[\"verdict\"], e[\"delta\"][\"states\"], (\"$wr\", $wl) in [(f[\"rule\"], f[\"line\"]) for f in e.get(\"findings\", [])])" "('FAIL', ['full'], True)"
    new_case "g_${m}_neg"; gfix "$m" base zz_absent >"$R/a.sh"; base; gfix "$m" clean zz_absent >"$R/a.sh"; head; gate
    expect "G[$m] negative control: lintable head without the defect -> PASS full" '(c["verdict"], e["delta"]["states"])' "('PASS', ['full'])"
done
# --- F4: the delta key ---------------------------------------------------------
# Q1 fix one SC2086, add a DIFFERENT SC2086 elsewhere -> FAIL (the line text is part of the key; kills R04)
new_case q1; wb a.sh '#!/bin/sh\necho $1\necho done\n'; base; wh a.sh '#!/bin/sh\necho "$1"\necho done\necho again $2\n'; head; gate
expect "Q1 a fixed SC2086 does not pay for a new SC2086 on another line" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2086', 4)])"
# Q2 a pre-existing finding whose MESSAGE cites a line number moves -> PASS (line N rewrite; kills R05)
new_case q2; wb a.sh '#!/bin/sh\ncase "$1" in\n  a) echo 1;;\n  a) echo 2;;\nesac\n'; base
wh a.sh '#!/bin/sh\necho p1\necho p2\necho p3\ncase "$1" in\n  a) echo 1;;\n  a) echo 2;;\nesac\n'; head; gate
expect "Q2 moved SC2221/SC2222 ('... on line N') stay pre-existing -> PASS" '(c["verdict"], sorted(f["rule"] for f in e.get("baseline_findings", [])))' "('PASS', ['SC2221', 'SC2222'])"

# --- reviewer mutants R06 R07 R10 R11 (re-targeted to r5: no window fallback) ------------
# T6 (R06 successor) base over the size cap -> no baseline: new-file, every head finding new -> FAIL
T6B=$( { printf '#!/bin/sh\necho "$undefined_pre"\n'; i=3; while [ $i -le 25 ]; do printf 'echo "b%s"\n' "$i"; i=$((i+1)); done; } )
new_case t6; printf '%s\n' "$T6B" >"$R/a.sh"; base; printf '%s\n' "$T6B" | sed '10,19d' >"$R/a.sh"; head; gate --shellcheck-max-lines 20
expect "T6 base over cap -> FAIL new-file, reason base-unlintable names the cap" '(c["verdict"], e["delta"]["files"][0]["state"], e["delta"]["files"][0].get("new_file_reason", "").startswith("base-unlintable: 25 lines"), [f["rule"] for f in e.get("findings", [])])' "('FAIL', 'new-file', True, ['SC2154'])"
# T7 (R07 successor) head over the size cap -> BLIND
T7B=$(i=1; printf '#!/bin/sh\n'; while [ $i -le 4000 ]; do printf 'echo "x%s"\n' "$i"; i=$((i+1)); done)
new_case t7; printf '%s\n' "$T7B" >"$R/a.sh"; base
printf '%s\n' "$T7B" | awk 'NR>=6 && NR<=1566 && (NR-6)%60==0 {sub(/"x/, "\"y")} {print}' >"$R/a.sh"; head; gate --shellcheck-max-lines 1000
expect "T7 head over the size cap -> FAIL blind" '(c["verdict"], e["delta"]["files"][0]["state"])' "('FAIL', 'blind')"
# T10 (R10 successor) the parity oracle's re-lint of the WHOLE head fails (stub) -> BLIND, never a plain lint
T10='#!/bin/sh\none() {\n    echo one\n}\ntwo() {\n# STUB_OOM_IF xhellcheck\n    echo "the shellcheck word"\n    echo two\n}\none\ntwo\n'
new_case t10; wb a.sh "$T10"; base; wh a.sh "$(printf '%b' "$T10" | sed 's/echo two/echo three/')\n"; head; gate
expect "T10 whole head linted differentially: the parity re-lint failure -> FAIL blind" '(c["verdict"], e["delta"]["files"][0]["state"], "parity" in e["delta"]["files"][0]["cause"])' "('FAIL', 'blind', True)"
# T11 (R11) a >= LARGE_LINES base lint takes the host-wide lock: held elsewhere -> never linted unlocked
LOCKP="$PRECHECK_TEST_LOCK_DIR/helix-precheck-shellcheck-large-$(id -u).lock"
T11B=$( { printf '#!/bin/sh\necho "$undefined_pre"\n'; i=3; while [ $i -le 5002 ]; do printf 'echo "x%s"\n' "$i"; i=$((i+1)); done; } )
new_case t11; printf '%s\n' "$T11B" >"$R/a.sh"; base; printf '%s\n' "$T11B" | sed -n '1,100p' >"$R/a.sh"; printf '# cut\n' >>"$R/a.sh"; head
python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"a");fcntl.flock(f.fileno(),fcntl.LOCK_EX);open(sys.argv[2],"w").close();time.sleep(60)' "$LOCKP" "$TMP/t11.ready" &
T11P=$!; i=0; while [ ! -f "$TMP/t11.ready" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
gate --shellcheck-exception-timeout 0.5; kill "$T11P" 2>/dev/null; wait "$T11P" 2>/dev/null
expect "T11 large base lint waits for the held lock and never runs unlocked (new-file, reason names the lock)" '(c["verdict"], e["delta"]["files"][0]["state"], "large-lint lock" in e["delta"]["files"][0].get("new_file_reason", ""))' "('FAIL', 'new-file', True)"

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
# V6 (r5 G3) the activation record is read from the COMMITTED blob at the pack's BASE commit, never from the
#    working tree: one scratch repository per variant (the repository holds the gate copy AND is the pack's repo)
ACTREL=scripts/fastcycle/review/precheck_shellcheck_delta.activation
GOODACT='decision-ref: operator decision 2026-10-13 ATM-1217\nactivated-on: 2026-10-13\n'
mkw() { # <name> <none|base|head|untracked|short|symlink|baddate> -> $TMP/<name>.verify.err
    W="$TMP/$1"; mkdir -p "$W/scripts/fastcycle" "$W/tools"
    cp -R "$REVIEW" "$W/scripts/fastcycle/review"; rm -f "${W:?}/${ACTREL:?}"
    find "${W:?}" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
    printf '%b' "$BASE_SH" >"$W/tools/legacy.sh"
    case $2 in
        base) printf '%b' "$GOODACT" >"$W/$ACTREL" ;;
        short) printf 'decision-ref: ATM-123\nactivated-on: 2026-10-13\n' >"$W/$ACTREL" ;;
        baddate) printf 'decision-ref: operator decision 2026-10-13 ATM-1217\nactivated-on: 13.10.2026\n' >"$W/$ACTREL" ;;
        symlink) printf '%b' "$GOODACT" >"$W/act_target.txt"; ln -s ../../../act_target.txt "$W/$ACTREL" ;;
    esac
    ( cd "$W" && git init -q . && $GIT add -A && $GIT commit -q -m base ) >/dev/null 2>&1
    ANCH=$(git -C "$W" rev-parse HEAD)  # r6 H2: the dispatcher anchors on the reviewed base commit
    printf '%b' "${BASE_SH}# touched\n" >"$W/tools/legacy.sh"
    if [ "$2" = head ]; then printf '%b' "$GOODACT" >"$W/$ACTREL"; fi
    ( cd "$W" && $GIT add -A && $GIT commit -q -m touch ) >/dev/null 2>&1
    sh "$W/scripts/fastcycle/review/precheck_pack_build.sh" --commit HEAD --out-dir "$TMP/$1.out" \
        --shellcheck-rule baseline-delta >"$TMP/$1.build.out" 2>&1
    if [ "$2" = untracked ]; then printf '%b' "$GOODACT" >"$W/$ACTREL"; fi
    if [ "$2" = base ]; then printf 'decision-ref: x\n' >"$W/$ACTREL"; fi  # a dirty worktree copy is never read
    python3 "$W/scripts/fastcycle/review/lib/precheck_pack_build_run.py" verify --pack "$TMP/$1.out/precheck.json" \
        --activation-commit "$ANCH" >/dev/null 2>"$TMP/$1.verify.err"
}
vact() { # <name> <mode> <label> <expected: lifted | substring of the refusal>
    mkw "$1" "$2"
    if [ ! -s "$TMP/$1.out/precheck.json" ]; then bad "$3: no pack built ($(command head -c 300 "$TMP/$1.build.out"))"; return; fi
    if [ "$4" = lifted ]; then
        if ! grep -q "not activated" "$TMP/$1.verify.err" && grep -q "TEST MODE" "$TMP/$1.verify.err"; then ok "$3"
        else bad "$3: $(grep -E 'not activated|TEST MODE' "$TMP/$1.verify.err" | cut -c1-300)"; fi
    elif grep "not activated for dispatch" "$TMP/$1.verify.err" | grep -qF -- "$4"; then ok "$3"
    else bad "$3: $(grep 'not activated' "$TMP/$1.verify.err" | cut -c1-300)"; fi
}
vact va none "V6a no record anywhere -> not activated" "no operator activation record committed"
vact vb untracked "V6b (G3) a well-formed UNTRACKED record on disk -> still not activated" "no operator activation record committed"
vact vc head "V6c a record ADDED by the batch under review (head only) -> not activated" "no operator activation record committed"
vact vd base "V6d a well-formed record committed at the pack base -> activation reason lifted (dirty worktree copy ignored)" lifted
vact ve short "V6e (X01) decision-ref shorter than 8 characters (valid date) -> refused" "needs 'decision-ref"
vact vf symlink "V6f (X03) a record committed as a SYMLINK -> refused (not a regular committed file)" "not a regular committed file (mode 120000)"
vact vg baddate "V6g a malformed date -> refused" "needs 'decision-ref"

# V7 (r5 G3) the gate repository is a SUBMODULE of the pack's repository: the record is read in the gate repository at
#    the GITLINK the pack's base records (real git, the real delta_activation; no pack needed for this seam)
G7="$TMP/v7gate"; M7="$TMP/v7main"; mkdir -p "$G7/scripts/fastcycle" "$M7"
cp -R "$REVIEW" "$G7/scripts/fastcycle/review"; rm -f "${G7:?}/${ACTREL:?}"
find "${G7:?}" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
( cd "$G7" && git init -q . && $GIT add -A && $GIT commit -q -m g0 ) >/dev/null 2>&1; G0=$(git -C "$G7" rev-parse HEAD)
printf '%b' "$GOODACT" >"$G7/$ACTREL"; ( cd "$G7" && $GIT add -A && $GIT commit -q -m g1 ) >/dev/null 2>&1; G1=$(git -C "$G7" rev-parse HEAD)
( cd "$M7" && git init -q . && printf 'x\n' >f && $GIT add f && $GIT commit -q -m m0 ) >/dev/null 2>&1; M0=$(git -C "$M7" rev-parse HEAD)
mv "$G7" "$M7/gate"; G7="$M7/gate"
git -C "$M7" update-index --add --cacheinfo "160000,$G0,gate" && ( cd "$M7" && $GIT commit -q -m m1 ) >/dev/null 2>&1; M1=$(git -C "$M7" rev-parse HEAD)
git -C "$M7" update-index --cacheinfo "160000,$G1,gate" && ( cd "$M7" && $GIT commit -q -m m2 ) >/dev/null 2>&1; M2=$(git -C "$M7" rev-parse HEAD)
v7() { # <main commit> <anchor> [<lib dir> [<gate repo>]] -> one line: OK <ref> | ERR <error>
    python3 - "${3:-$G7/scripts/fastcycle/review/lib}" "$M7" "$1" "$2" "${4:-}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import precheck_pack_build_run as b
r = b.delta_activation(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] or None)
print(("ERR " + r["error"]) if r.get("error") else ("OK " + r["decision_ref"]))
PY
}
V7A=$(v7 "$M2" "$G1"); V7B=$(v7 "$M1" "$G0"); V7C=$(v7 "$M0" "$G1"); V7B2=$(v7 "$M1" "$G1")
case $V7A in "OK operator decision 2026-10-13 ATM-1217") ok "V7a gitlink at the pack base = the anchor, a gate commit WITH the record -> activated" ;; *) bad "V7a $V7A" ;; esac
case $V7B in "ERR no operator activation record committed at the anchor $G0:"*) ok "V7b gitlink at the pack base (= anchor) is a gate commit WITHOUT the record (the gate checkout has it) -> not activated" ;; *) bad "V7b $V7B" ;; esac
case $V7B2 in "ERR activation anchor $G1 is not an ancestor of"*) ok "V7b2 (r6) anchor carries the record but is NOT in the lineage of the gitlink at the pack base -> not activated" ;; *) bad "V7b2 $V7B2" ;; esac
mkdir -p "$TMP/v7x"; cp -R "$G7/scripts/fastcycle/review/lib" "$TMP/v7x/lib"
V7E=$(v7 "$M2" "$G1" "$TMP/v7x/lib" "$G7"); V7F=$(v7 "$M2" "$G1" "$TMP/v7x/lib")
case $V7E in "OK operator decision 2026-10-13 ATM-1217") ok "V7e (r6) an EXTRACTED verifier (outside any repository) with gate_repo -> activated" ;; *) bad "V7e $V7E" ;; esac
case $V7F in "ERR activation record cannot be located at the pack base: "*"needs --gate-repo"*) ok "V7f (r6) an extracted verifier WITHOUT gate_repo -> not activated, names --gate-repo" ;; *) bad "V7f $V7F" ;; esac
GB7=$(printf 'x\n' | git -C "$M7" hash-object -w --stdin); GT7=$(printf '100644 blob %s\tf\n' "$GB7" | git -C "$M7" mktree)
MT7=$(printf '040000 tree %s\tgate\n' "$GT7" | git -C "$M7" mktree); M3=$($GIT -C "$M7" commit-tree "$MT7" -p "$M2" -m m3)
V7D=$(v7 "$M3" "$G1")
case $V7D in "ERR activation record cannot be located at the pack base: the pack base $M3 records no gitlink"*) ok "V7d the pack base records the gate path as a plain TREE (not a gitlink) -> not activated, named as such" ;; *) bad "V7d $V7D" ;; esac
case $V7C in "ERR activation record cannot be located at the pack base: the pack base $M0 records no gitlink"*) ok "V7c the pack base records no gitlink for the gate repository -> not activated" ;; *) bad "V7c $V7C" ;; esac

# =============================================================================
# r6 (review round 4 of ATM-1217, STRUCTURAL per 11.4.276(E)(1)). Two classes:
#  H-ANCHOR "a delta baseline is credited in a way the head does not earn":
#    H1 members -- a blob shellcheck could not PARSE was never analysed whole (P*);
#    H3 members -- a pre-existing finding / directive is identified by its UNCHANGED line
#    of the base->head line diff, never by a (rule, message, line text) multiset (A*);
#    H4 -- a byte-identical file over the size cap is not exempt (U*).
#  H-WHO "who may activate": the record is read at a DISPATCHER-supplied anchor (V8*).
# Every case drives the REAL gate / builder / verifier and the REAL shellcheck.
# =============================================================================
FILL30=""; i=0; while [ $i -lt 30 ]; do FILL30="$FILL30: filler $i\n"; i=$((i+1)); done

# P0 premise pins (11.4.273 control needles, real shellcheck): the parse-fatal classifier matches what shellcheck
#    reports for a parse failure; a parse failure SUPPRESSES the SC2164 check on the line after it (the analysis is
#    partial -- some checks before the failure can still report, which is why a partial result is never a baseline);
#    and a NON-fatal SC1xxx warning is not fatal
pin() { # <fixture printf-%b body> -> "<fatal count> <SC2164 count>"
    printf '%b' "$1" | "$REAL_SC" -s sh -f json1 - 2>/dev/null | python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
from precheck_pack_run import _parse_fatal
c = json.load(sys.stdin)["comments"]
print(len(_parse_fatal(c)), sum(1 for x in c if int(x["code"]) == 2164))' "$REVIEW/lib"
}
PINF=$(pin "#!/bin/sh\nif [ -n \"\$1\" ]; then\n    echo bad\nfi fi\ncd /nonexist\n")
PINC=$(pin "#!/bin/sh\nif [ -n \"\$1\" ]; then\n    echo bad\nfi\ncd /nonexist\n")
PINW=$(pin "#!/bin/sh\nx= 1\ncd /nonexist\n")
case "$PINF $PINC $PINW" in
    "1 0 0 1 0 1") ok "P0 pins: 'fi fi' -> 1 parse-fatal + the following SC2164 NOT reported; same file without it -> 0 fatal + SC2164; SC1007 warning -> not fatal" ;;
    *) bad "P0 parse-fatal pins drifted: fatal/SC2164 = [$PINF] [$PINC] [$PINW] (expected [1 0] [0 1] [0 1])" ;;
esac
# P1 (reviewer A3) a parse error the base already had, kept in head, plus new dangerous lines -> the head was never
#    analysed: new-file (head-unparsed), FAIL. Before r6: PASS, state full, baseline = the parse error.
P1B="#!/bin/sh\nf() {\n    echo hi\n}\nif [ -n x ]; then\n    echo bad\nfi fi\n${FILL30}"
new_case p1; wb s.sh "$P1B"; base; wh s.sh "${P1B}cd /nonexist\nrm -rf \$UNSET/*\neval \$1\n"; head; gate
expect "P1 (A3) base parse error kept + new lines -> FAIL new-file head-unparsed, the parse error is a finding" '(c["verdict"], [f["state"] for f in e["delta"]["files"]], [f.get("new_file_reason", "")[:14] for f in e["delta"]["files"]], "SC1089" in [f["rule"] for f in e.get("findings", [])], e.get("baseline_findings", []))' "('FAIL', ['new-file'], ['head-unparsed:'], True, [])"
# P1c control needle (reviewer A3c): the same new lines without the base parse error -> FAIL full, real new findings
P1CB="#!/bin/sh\nf() {\n    echo hi\n}\nif [ -n x ]; then\n    echo bad\nfi\n${FILL30}"
new_case p1c; wb s.sh "$P1CB"; base; wh s.sh "${P1CB}cd /nonexist\nrm -rf \$UNSET/*\neval \$1\n"; head; gate
expect "P1c control: same new lines, parseable base -> FAIL full, SC2164 on the added line 38" '(c["verdict"], e["delta"]["states"], ("SC2164", 38) in [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', ['full'], True)"
# P2 the base had a parse error the head FIXES; the head keeps an old warning -> the base is no baseline
#    (base-unlintable: base-unparsed), the kept warning fails (the whole-file verdict)
new_case p2; wb s.sh "#!/bin/sh\ncd /tmp\nif [ -n \"\$1\" ]; then\n    echo bad\nfi fi\n"; base
wh s.sh "#!/bin/sh\ncd /tmp\nif [ -n \"\$1\" ]; then\n    echo bad\nfi\n"; head; gate
expect "P2 base parse error fixed in head -> FAIL new-file, reason base-unlintable: base-unparsed" '(c["verdict"], [f.get("new_file_reason", "")[:30] for f in e["delta"]["files"]], [f["rule"] for f in e.get("findings", [])])' "('FAIL', ['base-unlintable: base-unparsed'], ['SC2164'])"
# P3 the head INTRODUCES a parse error into a clean base -> FAIL head-unparsed
new_case p3; wb s.sh "#!/bin/sh\necho ok\nif [ -n x ]; then\n    echo fine\nfi\n"; base
wh s.sh "#!/bin/sh\necho ok\nif [ -n x ]; then\n    echo fine\nfi fi\n"; head; gate
expect "P3 head introduces a parse error -> FAIL new-file head-unparsed" '(c["verdict"], [f.get("new_file_reason", "")[:14] for f in e["delta"]["files"]])' "('FAIL', ['head-unparsed:'])"
# P4 negative control (11.4.201(1)): a NON-fatal SC1xxx warning (SC1007) already in the base, head adds a clean line
#    -> the classifier is not over-broad: state full, the SC1007 is pre-existing, PASS
new_case p4; wb s.sh "#!/bin/sh\nx= 1\necho finished\n"; base; wh s.sh "#!/bin/sh\nx= 1\necho finished\necho more\n"; head; gate
expect "P4 non-fatal SC1007 in base -> full, pre-existing, PASS" '(c["verdict"], e["delta"]["states"], [f["rule"] for f in e.get("baseline_findings", [])])' "('PASS', ['full'], ['SC1007'])"

# A1 (reviewer A1) the old `cd /tmp` is suppressed by a JUSTIFIED directive, an identical `cd /tmp` is ADDED in a new
#    function -> the new one is on an added line: NEW, FAIL (r5 multiset: PASS)
A1B="#!/bin/sh\nf() {\n    cd /tmp\n}\n${FILL30}f\n"
new_case a1; wb s.sh "$A1B"; base
wh s.sh "#!/bin/sh\nf() {\n    ${H} shellcheck disable=SC2164 # justified: /tmp always exists\n    cd /tmp\n}\n${FILL30}g() {\n    cd /tmp\n    rm -rf ./*\n}\nf\ng\n"; head; gate
expect "A1 suppress the old, add an identical new occurrence -> FAIL, SC2164 at the added line 37" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])], e.get("baseline_findings", []))' "('FAIL', [('SC2164', 37)], [])"
# A2 (reviewer A2) the old occurrence is FIXED, an identical one is added -> NEW, FAIL
new_case a2; wb s.sh "$A1B"; base
wh s.sh "#!/bin/sh\nf() {\n    cd /tmp || exit 1\n}\n${FILL30}g() {\n    cd /tmp\n    rm -rf ./*\n}\nf\ng\n"; head; gate
expect "A2 fix the old, add an identical new occurrence -> FAIL, SC2164 at the added line 36" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2164', 36)])"
# A3 duplicates: two old identical occurrences (debt), a third identical one added -> exactly the added one is NEW
new_case a3; wb s.sh "#!/bin/sh\ncd /tmp\necho a\ncd /tmp\necho b\n"; base
wh s.sh "#!/bin/sh\ncd /tmp\necho a\ncd /tmp\necho b\ncd /tmp\n"; head; gate
expect "A3 two old + one added identical finding -> FAIL with only line 6 new, lines 2 and 4 pre-existing" '(c["verdict"], [f["line"] for f in e.get("findings", [])], [f["line"] for f in e.get("baseline_findings", [])])' "('FAIL', [6], [2, 4])"
# A4 a MOVED line (cut at the top, pasted at the end) is NEW: stricter by design (stated in the guide)
new_case a4; wb s.sh "#!/bin/sh\ncd /tmp\n${FILL30}echo end\n"; base; wh s.sh "#!/bin/sh\n${FILL30}echo end\ncd /tmp\n"; head; gate
expect "A4 a moved pre-existing finding is NEW (stricter) -> FAIL" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2164', 33)])"
# A5 negative control: unrelated lines inserted ABOVE the debt -> the debt line is an unchanged diff line -> PASS
new_case a5; wb s.sh "#!/bin/sh\necho a\ncd /tmp\necho b\n"; base; wh s.sh "#!/bin/sh\necho new1\necho new2\necho a\ncd /tmp\necho b\n"; head; gate
expect "A5 lines inserted above the debt: the debt follows its unchanged line -> PASS, pre-existing at line 5" '(c["verdict"], e["delta"]["states"], [f["line"] for f in e.get("baseline_findings", [])])' "('PASS', ['full'], [5])"
# A6 the head CHANGES the debt line itself (still the same finding) -> a changed line is NEW, FAIL (stricter, stated)
new_case a6; wb s.sh "#!/bin/sh\ncd /tmp\n"; base; wh s.sh "#!/bin/sh\ncd  /tmp\n"; head; gate
expect "A6 a changed line carrying an old finding is NEW -> FAIL" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])])' "('FAIL', [('SC2164', 2)])"
# A7 the directive member of the class: an old UNJUSTIFIED directive is justified in place, an identical unjustified
#    one is added above NEW code -> the added directive is a NEW D5, FAIL (r5: tolerated through the text multiset)
new_case a7; wb s.sh "#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n${FILL30}"; base
wh s.sh "#!/bin/sh\n${H} shellcheck disable=SC2086 # justified: argv word-splitting is intended here\necho \$1\n${FILL30}${H} shellcheck disable=SC2086\necho \$2\n"; head; gate
expect "A7 justify the old unjustified directive, add an identical unjustified one -> FAIL, D5 at the added line 34" '(c["verdict"], [(x["line"], x["violations"][0][:2]) for x in e.get("directive_violations", [])], e.get("directive_violations_baseline", []))' "('FAIL', [(34, 'D5')], [])"
# A7b (Y02 successor) a SECOND copy of a pre-existing unjustified directive next to new code -> the copy is NEW
new_case a7b; wb s.sh "#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n"; base
wh s.sh "#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n${H} shellcheck disable=SC2086\necho \$2\n"; head; gate
expect "A7b second copy of an old unjustified directive -> FAIL at line 4, line 2 stays baseline" '(c["verdict"], [x["line"] for x in e.get("directive_violations", [])], [x["line"] for x in e.get("directive_violations_baseline", [])])' "('FAIL', [4], [2])"
# A7c negative control: the old unjustified directive with lines inserted above it -> still baseline, PASS
new_case a7c; wb s.sh "#!/bin/sh\n${H} shellcheck disable=SC2086\necho \$1\n"; base
wh s.sh "#!/bin/sh\necho first\n${H} shellcheck disable=SC2086\necho \$1\n"; head; gate
expect "A7c old unjustified directive on an unchanged (moved-down) line -> tolerated, PASS" '(c["verdict"], [x["line"] for x in e.get("directive_violations_baseline", [])])' "('PASS', [3])"
# Q3 (Y03 successor) the finding's evidence text is the whitespace-normalised source line
new_case q3; wb s.sh "#!/bin/sh\necho ok\n"; base; wh s.sh "#!/bin/sh\necho ok\ncd \t /tmp   \n"; head; gate
expect "Q3 evidence text is whitespace-normalised" '(c["verdict"], [f["text"] for f in e.get("findings", [])])' "('FAIL', ['cd /tmp'])"
# T6c (Y06 successor) a base over the BYTE cap (2 MiB) but under the line cap -> base-unlintable, new-file
new_case t6c; python3 -c '
import sys
print("#!/bin/sh\ncd /tmp")
for i in range(3000): print("echo \"%s\"" % ("x" * 800))' >"$R/s.sh"; base
printf '#!/bin/sh\ncd /tmp\necho short\n' >"$R/s.sh"; head; gate
expect "T6c base over the byte cap (under the line cap) -> FAIL new-file, base-unlintable names the bytes" '(c["verdict"], [f.get("new_file_reason", "")[:16] for f in e["delta"]["files"]], "bytes exceeds the size cap" in e["delta"]["files"][0].get("new_file_reason", ""))' "('FAIL', ['base-unlintable:'], True)"
# U1 (H4) a byte-identical (mode-only) touch of a file OVER the size cap is BLIND, not unchanged
U1B=$(i=1; printf '#!/bin/sh\n'; while [ $i -le 60 ]; do printf 'echo "u%s"\n' "$i"; i=$((i+1)); done)
new_case u1; printf '%s\n' "$U1B" >"$R/a.sh"; base; chmod +x "$R/a.sh"; head; gate --shellcheck-max-lines 20
expect "U1 mode-only touch over the size cap -> FAIL blind (the whole-file verdict), never unchanged" '(c["verdict"], e["delta"]["states"])' "('FAIL', ['blind'])"
# U1b negative control: the same mode-only touch under the cap -> unchanged, PASS
new_case u1b; printf '%s\n' "$U1B" >"$R/a.sh"; base; chmod +x "$R/a.sh"; head; gate
expect "U1b mode-only touch under the cap -> unchanged, PASS" '(c["verdict"], e["delta"]["states"])' "('PASS', ['unchanged'])"

# A8 (Z06) per-line count: an UNCHANGED line `echo $a $b` gains a second SC2086 (same message) because a CHANGED line
#    elsewhere made `$a` unsafe -> one occurrence is pre-existing, the second is NEW (the base-line budget is a count)
new_case a8; wb s.sh '#!/bin/sh\na=5\nb=$1\necho $a $b\n'; base; wh s.sh '#!/bin/sh\na=$2\nb=$1\necho $a $b\n'; head; gate
expect "A8 an unchanged line with one more identical finding than its base line -> FAIL, one new + one pre-existing" '(c["verdict"], [(f["rule"], f["line"]) for f in e.get("findings", [])], [(f["rule"], f["line"]) for f in e.get("baseline_findings", [])])' "('FAIL', [('SC2086', 4)], [('SC2086', 4)])"
# A9 (Z09) negative control for the line map: a 250-line file whose debt line `cd /tmp` is POPULAR (6 copies, > 1%);
#    one line inserted at the top -> every copy is an unchanged line -> PASS (a junk heuristic would unmatch them)
A9B=$( { printf '#!/bin/sh\n'; i=1; while [ $i -le 249 ]; do if [ $((i % 40)) -eq 0 ]; then printf 'cd /tmp\n'; else printf 'echo "l%s"\n' "$i"; fi; i=$((i+1)); done; } )
new_case a9; printf '%s\n' "$A9B" >"$R/s.sh"; base; printf '%s\n' "$A9B" | sed '1a echo "inserted"' >"$R/s.sh"; head; gate
expect "A9 popular debt lines stay anchored after an insertion above them -> PASS, 6 pre-existing" '(c["verdict"], e["delta"]["states"], len(e.get("baseline_findings", [])))' "('PASS', ['full'], 6)"

# A9b (Z09) the junk heuristic's own trigger: a 241-line file that is ALL the same debt line (`cd /tmp` x 240); one
#    line inserted in the middle -> every `cd /tmp` is still an unchanged line -> PASS (difflib's autojunk would leave
#    the lines after the insertion unmatched: no non-popular line exists to anchor them)
A9C=$( { printf '#!/bin/sh\n'; i=1; while [ $i -le 240 ]; do printf 'cd /tmp\n'; i=$((i+1)); done; } )
new_case a9b; printf '%s\n' "$A9C" >"$R/s.sh"; base; printf '%s\n' "$A9C" | sed '121a echo "mid"' >"$R/s.sh"; head; gate
expect "A9b an all-popular file with one insertion keeps every debt line anchored -> PASS, 240 pre-existing" '(c["verdict"], e["delta"]["states"], len(e.get("baseline_findings", [])))' "('PASS', ['full'], 240)"

# V8 (r6 H2, "who may activate"): the record is read at the DISPATCHER's anchor (verify --activation-commit), never
#    at a commit the pack names. Split-commit shapes through the REAL builder (--commit HEAD: base = c1) and verifier.
mksplit() { # <name> <variant> -> $TMP/<name>.verify.err ; anchor chosen per variant
    W="$TMP/$1"; mkdir -p "$W/scripts/fastcycle" "$W/tools"
    cp -R "$REVIEW" "$W/scripts/fastcycle/review"; rm -f "${W:?}/${ACTREL:?}"
    find "${W:?}" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
    printf '%b' "$BASE_SH" >"$W/tools/legacy.sh"
    case $2 in
        changed|restored|good|goodx|headdel) printf '%b' "$GOODACT" >"$W/$ACTREL" ;;
        commented) printf '# decision-ref: operator decision 2026-10-13 ATM-1217\n# activated-on: 2026-10-13\n' >"$W/$ACTREL" ;;
    esac
    ( cd "$W" && git init -q . && $GIT add -A && $GIT commit -q -m c0 ) >/dev/null 2>&1; C0=$(git -C "$W" rev-parse HEAD)
    case $2 in
        h2|h2none|ref|abbrev) printf '%b' "$GOODACT" >"$W/$ACTREL" ;;               # c1: the producer's own record
        changed) printf 'decision-ref: producer rewrote the decision\nactivated-on: 2026-10-14\n' >"$W/$ACTREL" ;;
        restored) rm -f "$W/$ACTREL"; ( cd "$W" && $GIT add -A && $GIT commit -q -m c1a ) >/dev/null 2>&1
                  printf '%b' "$GOODACT" >"$W/$ACTREL" ;;
        side) ( cd "$W" && git checkout -q -b side && printf '%b' "$GOODACT" >"$ACTREL" && $GIT add -A \
                && $GIT commit -q -m s1 && git checkout -q - ) >/dev/null 2>&1; SIDE=$(git -C "$W" rev-parse side)
              printf 'unrelated\n' >"$W/tools/other.txt" ;;
        *) printf 'unrelated\n' >"$W/tools/other.txt" ;;
    esac
    ( cd "$W" && $GIT add -A && $GIT commit -q -m c1 ) >/dev/null 2>&1
    printf '%b' "${BASE_SH}# touched\n" >"$W/tools/legacy.sh"
    if [ "$2" = headdel ]; then rm -f "$W/$ACTREL"; fi  # the work commit itself removes the record
    ( cd "$W" && $GIT add -A && $GIT commit -q -m c2 ) >/dev/null 2>&1
    sh "$W/scripts/fastcycle/review/precheck_pack_build.sh" --commit HEAD --out-dir "$TMP/$1.out" \
        --shellcheck-rule baseline-delta >"$TMP/$1.build.out" 2>&1
    case $2 in
        h2none) set -- "$1" ;;
        ref) set -- "$1" --activation-commit HEAD~2 ;;
        abbrev) set -- "$1" --activation-commit "$(printf '%.12s' "$C0")" ;;
        side) set -- "$1" --activation-commit "$SIDE" ;;
        nocommit) set -- "$1" --activation-commit 0000000000000000000000000000000000000000 ;;
        *) set -- "$1" --activation-commit "$C0" ;;
    esac
    n=$1; shift
    if [ "${VARIANT:-}" = goodx ]; then  # the dispatch guard's shape: an EXTRACTED verifier outside any repository
        mkdir -p "$TMP/$n.xv"; cp -R "$W/scripts/fastcycle/review/lib" "$TMP/$n.xv/lib"
        python3 "$TMP/$n.xv/lib/precheck_pack_build_run.py" verify --pack "$TMP/$n.out/precheck.json" --gate-repo "$W" \
            "$@" >/dev/null 2>"$TMP/$n.verify.err"
    else
        python3 "$W/scripts/fastcycle/review/lib/precheck_pack_build_run.py" verify --pack "$TMP/$n.out/precheck.json" \
            "$@" >/dev/null 2>"$TMP/$n.verify.err"
    fi
}
vsplit() { # <name> <variant> <label> <expected: lifted | substring of the refusal>
    VARIANT=$2 mksplit "$1" "$2"
    if [ ! -s "$TMP/$1.out/precheck.json" ]; then bad "$3: no pack built ($(command head -c 300 "$TMP/$1.build.out"))"; return; fi
    if [ "$4" = lifted ]; then
        if ! grep -q "not activated" "$TMP/$1.verify.err" && grep -q "TEST MODE" "$TMP/$1.verify.err"; then ok "$3"
        else bad "$3: $(grep -E 'not activated|TEST MODE' "$TMP/$1.verify.err" | cut -c1-300)"; fi
    elif grep "not activated for dispatch" "$TMP/$1.verify.err" | grep -qF -- "$4"; then ok "$3"
    else bad "$3: $(grep 'not activated' "$TMP/$1.verify.err" | cut -c1-300)"; fi
}
vsplit v8a h2 "V8a (reviewer H2) record committed by the producer ONE commit before its work (= the pack base), anchor = the reviewed c0 -> not activated" "no operator activation record committed at the anchor"
vsplit v8b h2none "V8b the same split batch, the dispatcher supplies no anchor -> not activated" "no activation anchor was supplied"
vsplit v8c ref "V8c anchor given as a reference name (movable) -> refused" "not a full hexadecimal commit id"
vsplit v8d abbrev "V8d anchor given abbreviated -> refused" "not a full hexadecimal commit id"
vsplit v8e changed "V8e the batch lineage REWRITES the decision between the anchor and the base -> refused" "differs from the anchor"
vsplit v8f restored "V8f the batch lineage deletes and RESTORES the identical record -> refused (touched between anchor and base)" "touched by commit"
vsplit v8g side "V8g anchor on a side branch (not an ancestor of the base) carrying the record -> refused" "is not an ancestor of"
vsplit v8h nocommit "V8h anchor is a full-length id that is no commit -> refused" "is not a commit of the gate repository"
vsplit v8i commented "V8i (Y01) a record whose fields are COMMENTED OUT -> refused" "needs 'decision-ref"
vsplit v8j good "V8j control: record at the reviewed anchor c0, unrelated c1, work c2 -> activation reason lifted" lifted
vsplit v8k goodx "V8k control through an EXTRACTED verifier (the dispatch guard's shape) with --gate-repo -> lifted" lifted
vsplit v8l headdel "V8l (P07) the batch's own head deletes the record: activation is decided at the BASE lineage (G), never at the gate checkout's HEAD -> lifted" lifted

echo "== summary: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
