#!/usr/bin/env bash
# =============================================================================
# test_fastcycle_r6_mutations.sh -- paired §1.1 mutations for the T048 restart
# round-1 R6 fixes (baseline_replay.sh, collect_baseline.py,
# build_deploy_qa_events.py). Every mutation re-introduces ONE defect into a
# throwaway replica of cycle/ + lib/ (the real tree is never written), runs the
# ONE regression case that guards it against the replica, and requires that case
# to FAIL by name. A mutation the suite does not catch is a bluff guard.
#
# R6-M1..M7 are the independent reviewer's own mutations (R6_baseline_replay.md),
# re-expressed against the fixed code; R6-M8.. are the fixer's own.
# T048 restart ROUND 2 (docs/qa/t048_restart_round2_20261008/V4_baseline.md):
# V4-N3/N4/N5/N6/N10/N12 are the round-2 reviewer's mutations, applied VERBATIM
# (same anchors, same replacements as the reviewer's own runner); R2-M1.. are the
# round-2 fixer's own. They run against test_baseline_replay_r2_findings.sh, the
# collect_baseline and build_deploy_qa_events suites.
#
# Instrument control (§11.4.273): before any mutant, the SAME harness runs a
# representative case against an UNMUTATED replica and requires it to PASS --
# otherwise a "caught" mutant could just be a broken replica.
#
# Env: MUT_ONLY -- space-separated mutation ids to run (default all).
# Exit: 0 every mutation caught (and the control passed); 1 otherwise.
# Runtime: several minutes (signal cases wait on real processes); run it in the
# background (§11.4.89).
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
exec python3 - "$FC" "$HERE" <<'PYEOF'
import os, shutil, subprocess, sys, tempfile

FC, TESTS = sys.argv[1], sys.argv[2]
ONLY = os.environ.get("MUT_ONLY", "").split()

BR = "cycle/baseline_replay.sh"
CB = "cycle/collect_baseline.py"
BDQ = "cycle/build_deploy_qa_events.py"
T_R6 = "test_baseline_replay_r6_findings.sh"
T_R4 = "test_baseline_replay_r4_findings.sh"
T_CB = "test_collect_baseline_red.sh"
T_BDQ = "test_build_deploy_qa_events_red.sh"
T_R2 = "test_baseline_replay_r2_findings.sh"

# (id, target file, [(old, new), ...], test file, filter-env, expected failing line prefix)
MUTS = [
    # ---- reviewer mutations R6-M1..M7 ----
    ("R6-M1", BDQ, [("    if build_fp != deploy_fp:", "    if False and build_fp != deploy_fp:")],
     T_BDQ, {}, "FAIL: golden-bad-fp-mismatch"),
    ("R6-M2", BR, [('[ -z "$best_at" ] || [ "$at" -gt "$best_at" ]', '[ -z "$best_at" ] || [ "$at" -lt "$best_at" ]')],
     T_R6, {"R6_ONLY": "F4"}, "NOT ok [R6-F4]"),
    ("R6-M3", BR, [('differs = sorted({p for p in phases if vs1.get(p, []) != vs2.get(p, [])})',
                    'differs = sorted({p for p in ("cold",) if vs1.get(p, []) != vs2.get(p, [])})')],
     T_R6, {"R6_ONLY": "F7c"}, "NOT ok [R6-F7c]"),
    ("R6-M4", BR, [('_fc_submodule_reference_update() {\n  local src="$1" tgt="$2"\n',
                    '_fc_submodule_reference_update() {\n  return 0\n  local src="$1" tgt="$2"\n')],
     T_R6, {"R6_ONLY": "F14sub"}, "NOT ok [R6-F14sub]"),
    ("R6-M5", BR, [('if { [ "$rc" = 124 ] || [ "$rc" = 137 ]; } && [ "$dur" -ge "$tmo_ms" ]; then',
                    'if false; then')],
     T_R6, {"R6_ONLY": "F8t"}, "NOT ok [R6-F8t]"),
    ("R6-M6", BR, [('${item_re}([^0-9]|$) ]]', '${item_re} ]]')],
     T_R4, {}, "NOT ok B2"),
    ("R6-M7", BR, [('  trap "$_sig_cleanup_cmd; exit 129" HUP\n'
                    '  trap "$_sig_cleanup_cmd; exit 130" INT\n'
                    '  trap "$_sig_cleanup_cmd; exit 131" QUIT\n'
                    '  trap "$_sig_cleanup_cmd; exit 143" TERM',
                    "  trap 'exit 129' HUP\n  trap 'exit 130' INT\n  trap 'exit 131' QUIT\n  trap 'exit 143' TERM")],
     T_R6, {"R6_ONLY": "F11c"}, "NOT ok [R6-F11c]"),
    # ---- fixer mutations ----
    ("R6-M8", BDQ, [("    if missing:", "    if False:")], T_BDQ, {}, "FAIL: golden-bad-fp-missing-both"),
    ("R6-M9", BDQ, [("    if not _present(target_serial):", "    if False:")], T_BDQ, {}, "FAIL: golden-bad-target-missing"),
    ("R6-M10", BR, [('[ -z "$best_at" ] || [ "$at" -gt "$best_at" ]', '[ -z "$best_at" ] || [[ "$adate" > "$FZ_ADATE" ]]')],
     T_R6, {"R6_ONLY": "F4"}, "NOT ok [R6-F4]"),
    ("R6-M11", BR, [('    FZ_ERR="not a git repository (or git unavailable): $root"\n    return 4',
                     '    return 0'),
                    ('  rc=$?\n  if [ "$rc" -ne 0 ]; then\n    FZ_ERR="git log failed',
                     '  rc=0\n  if [ "$rc" -ne 0 ]; then\n    FZ_ERR="git log failed')],
     T_R6, {"R6_ONLY": "F3"}, "NOT ok [R6-F3]"),
    ("R6-M12", BR, [('    body.update(commit=sha, tree=tree, commit_author_date=adate, commit_subject=subject)',
                     '    body.update(commit=sha, tree=tree, commit_author_date=adate,'
                     ' commit_subject=subject.encode().decode("unicode_escape"))')],
     T_R6, {"R6_ONLY": "F5"}, "NOT ok [R6-F5]"),
    ("R6-M13", BR, [('run_log_dir="$(mktemp -d "$worktree_root/replay-logs/${commit:0:12}.XXXXXX")"',
                     'run_log_dir="$worktree_root/replay-logs"')],
     T_R6, {"R6_ONLY": "F6"}, "NOT ok [R6-F6]"),
    ("R6-M14", BR, [("det = not flaky and not differs", "det = not differs")],
     T_R6, {"R6_ONLY": "F7a"}, "NOT ok [R6-F7a]"),
    ("R6-M15", BR, [('  [ $(( $1 + $2 )) -ge 1 ] || die "--cold-runs + --warm-runs must be at least 1 (zero runs measure nothing)"\n', '')],
     T_R6, {"R6_ONLY": "F7b"}, "NOT ok [R6-F7b]"),
    ("R6-M16", BR, [("if unmeasurable:", "if False:")], T_R6, {"R6_ONLY": "F7d"}, "NOT ok [R6-F7d]"),
    ("R6-M17", BR, [("    cd_failed|exec_failed) printf 'HARNESS_ERROR|%s' \"$mk\"; return 0 ;;",
                     "    cd_failed|exec_failed) printf 'FAIL|%s' \"$mk\"; return 0 ;;")],
     T_R6, {"R6_ONLY": "F8"}, "NOT ok [R6-F8]"),
    ("R6-M18", BR, [('median_ms = {p: med([r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] == "PASS"])',
                     'median_ms = {p: med([r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] != "UNMEASURED"])')],
     T_R6, {"R6_ONLY": "F9"}, "NOT ok [R6-F9]"),
    ("R6-M19", BR, [("DEFAULT_MIN_FREE_KB=70254592", "DEFAULT_MIN_FREE_KB=10485760")],
     T_R6, {"R6_ONLY": "F10"}, "NOT ok [R6-F10]"),
    ("R6-M20", BR, [('    local rr="$1" wp="$2"\n    _fc_kill_child\n', '    local rr="$1" wp="$2"\n')],
     T_R6, {"R6_ONLY": "F11b"}, "NOT ok [R6-F11b]"),
    ("R6-M21", BR, [('    kill -s TERM "$p" 2>/dev/null\n    wait "$p" 2>/dev/null\n', '    wait "$p" 2>/dev/null\n')],
     T_R6, {"R6_ONLY": "F11a"}, "NOT ok [R6-F11a]"),
    ("R6-M22", BR, [("_FC_OUT_OVERRIDE=\"${FC_OUT:-}\"\nunset FC_OUT\n", "_FC_OUT_OVERRIDE=\"${FC_OUT:-}\"\n")],
     T_R6, {"R6_ONLY": "F12"}, "NOT ok [R6-F12]"),
    ("R6-M23", BR, [("      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \\\n        git -c protocol.ext.allow=never -c protocol.file.allow=never \\\n        -C \"$tgt\" submodule update --init --quiet --reference",
                     "        git -c protocol.ext.allow=never -c protocol.file.allow=never \\\n        -C \"$tgt\" submodule update --init --quiet --reference"),
                    ("      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \\\n        git -c protocol.ext.allow=never -c protocol.file.allow=never \\\n        -C \"$tgt\" submodule update --init --quiet -- ",
                     "        git -c protocol.ext.allow=never -c protocol.file.allow=never \\\n        -C \"$tgt\" submodule update --init --quiet -- ")],
     T_R6, {"R6_ONLY": "F15"}, "NOT ok [R6-F15]"),
    ("R6-M24", BR, [('{ isnum "$3" && [ "$3" -ge 1 ]; }', "isnum \"$3\"")],
     T_R6, {"R6_ONLY": "F18"}, "NOT ok [R6-F18]"),
    ("R6-M25", BR, [("  _sc_one exec_failure_harness_error HARNESS_ERROR 30 fc-selfcheck-no-such-command-6b1f\n", "")],
     T_R6, {"R6_ONLY": "F20"}, "NOT ok [R6-F20]"),
    ("R6-M26", BR, [('       [ -L "$_rt_src" ] || [ -L "$_rt_bin" ]; then', '       false; then'),
                    ('    if [ -z "$_rt_dir_real" ] || [ -z "$wt_path_real" ] || \\', '    if false && \\')],
     T_R6, {"R6_ONLY": "F14ht"}, "NOT ok [R6-F14ht]"),
    ("R6-M27", CB, [('    env.pop("FC_OUT", None)', "    pass")], T_CB, {"CB_ONLY": "C-F12"}, "NOT ok [C-F12]"),
    ("R6-M28", CB, [('if run.get("verdict") == "PASS" and run.get("duration_ms", 0) >= a.plausible_floor_ms:',
                     'if run.get("verdict") != "UNMEASURED" and run.get("duration_ms", 0) >= a.plausible_floor_ms:')],
     T_CB, {"CB_ONLY": "C-F9"}, "NOT ok [C-F9]"),
    ("R6-M29", CB, [("        n_reopened = matched_by_type.get(itype, 0)", "        n_reopened = any_by_type.get(itype, 0)")],
     T_CB, {"CB_ONLY": "C-F22"}, "NOT ok [C-F22]"),
    ("R6-M30", CB, [("        if unknown:", "        if False:")], T_CB, {"CB_ONLY": "C-F21"}, "NOT ok [C-F21]"),
    ("R6-M31", CB, [("    if harness_errors:\n        print(\"collect_baseline: BLIND", "    if False:\n        print(\"collect_baseline: BLIND")],
     T_CB, {"CB_ONLY": "C-HE"}, "NOT ok [C-HE]"),
    ("R6-M32", CB, [("    if a.fresh_execution_json and not os.path.isfile(a.fresh_execution_json):",
                     "    if False:")],
     T_CB, {"CB_ONLY": "C-FRESH"}, "NOT ok [C-FRESH]"),
    # ---- round-2 reviewer mutations (verbatim) ----
    ("V4-N3", BR, [('run_log="$run_log_dir/${phase}_${run_idx}.log"', 'run_log="$run_log_dir/${phase}.log"')],
     T_R2, {"R2_ONLY": "V4-10"}, "NOT ok [V4-10]"),
    ("V4-N4", BR, [('    kill -s TERM "$p" 2>/dev/null\n    wait "$p" 2>/dev/null\n', '    kill -s TERM "$p" 2>/dev/null\n')],
     T_R2, {"R2_ONLY": "V4-12"}, "NOT ok [V4-12/N4]"),
    ("V4-N5", BR, [('if [ "$free_kb" -lt "$min_free_kb" ]; then', 'if false; then')],
     T_R2, {"R2_ONLY": "V4-5"}, "NOT ok [V4-5]"),
    ("V4-N6", BR, [('[ -z "$best_at" ] || [ "$at" -gt "$best_at" ]', '[ -z "$best_at" ] || [ "$at" -ge "$best_at" ]')],
     T_R2, {"R2_ONLY": "N6"}, "NOT ok [N6]"),
    ("V4-N10", BR, [("log --all -i -F --grep=", "log --all -i --grep=")],
     T_R2, {"R2_ONLY": "N10"}, "NOT ok [N10]"),
    ("V4-N12", BR, [("printf -v _sig_cleanup_cmd \"trap '' HUP INT QUIT TERM; trap - EXIT; cleanup %q %q\"",
                     "printf -v _sig_cleanup_cmd \"trap - EXIT; cleanup %q %q\"")],
     T_R2, {"R2_ONLY": "N12"}, "NOT ok [V4-12/N12]"),
    # ---- round-2 fixer mutations ----
    # V4-1: no session -> the gate's nested-timeout child survives
    ("R2-M1", BR, [('FC_REPLAY_RUN_TOKEN="$_FC_CHILD_TOKEN" setsid -w timeout --kill-after=5 "${tmo}s"',
                    'timeout --kill-after=5 "${tmo}s"')],
     T_R2, {"R2_ONLY": "V4-1"}, "NOT ok [V4-1]"),
    # V4-1: no token match -> a child that called setsid itself survives
    ("R2-M2", BR, [("    if not hit and want:", "    if False:")],
     T_R2, {"R2_ONLY": "V4-1"}, "NOT ok [V4-1]"),
    # V4-2: the round-1 rule (>= 129 = "terminated by signal") restored
    ("R2-M3", BR, [("  if [ \"$rc\" = 0 ]; then printf 'PASS|exit 0'; return 0; fi",
                    "  if [ \"$rc\" -ge 129 ]; then printf 'UNMEASURED|terminated by signal %s' \"$((rc - 128))\"; return 0; fi\n"
                    "  if [ \"$rc\" = 0 ]; then printf 'PASS|exit 0'; return 0; fi")],
     T_R2, {"R2_ONLY": "V4-2"}, "NOT ok [V4-2]"),
    # V4-4: no lock
    ("R2-M4", BR, [("  flock -n 9 || blind", "  true || blind")], T_R2, {"R2_ONLY": "V4-4"}, "NOT ok [V4-4]"),
    # V4-4: the object store's filesystem never checked
    ("R2-M5", BR, [('  if [ "$objects_free_kb" -lt "$min_free_kb_objects" ]; then', '  if false; then')],
     T_R2, {"R2_ONLY": "V4-5"}, "NOT ok [V4-4]"),
    # V4-8: a background watchdog sleep is back on the signal path
    ("R2-M6", BR, [("  _FC_HARNESS_SIGNALLED=TERM\n", "  _FC_HARNESS_SIGNALLED=TERM\n  ( sleep 10 ) >/dev/null 2>&1 &\n")],
     T_R2, {"R2_ONLY": "V4-12"}, "NOT ok [V4-12/N4]"),
    # V4-9: the private temp directory is never removed
    ("R2-M7", BR, [("trap _fc_rm_tmpdir EXIT\n", "\n")], T_R2, {"R2_ONLY": "V4-9"}, "NOT ok [V4-9]"),
    # V4-9: selfcheck without signal handlers
    ("R2-M8", BR, [("  # one must stop it (the same main-shell handlers as replay).\n  _fc_install_main_traps\n",
                    "  # one must stop it (the same main-shell handlers as replay).\n")],
     T_R2, {"R2_ONLY": "V4-9"}, "NOT ok [V4-9]"),
    # V4-6 class in the freeze CLI: a whitespace-only id accepted
    ("R2-M9", BR, [('  case "$item" in *[[:space:]]*) die', '  case "$item" in "#never") die')],
     T_R2, {"R2_ONLY": "WS"}, "NOT ok [WS]"),
    # V4-6: blank values count as present again (the reviewer's V4-N7 shape, one level up)
    ("R2-M10", BDQ, [('    return isinstance(value, str) and value.strip() != ""', '    return isinstance(value, str) and value != ""')],
     T_BDQ, {}, "FAIL: golden-bad-fp-whitespace-both"),
    # V4-6: the deploy time field ignored again
    ("R2-M11", BDQ, [("    if not _utc_instant_ok(deploy_time):", "    if False:")],
     T_BDQ, {}, "FAIL: golden-bad-time-invalid"),
    # V4-6: a non-UTC offset accepted
    ("R2-M12", BDQ, [(r'(Z|\+00:00)")', r'(Z|[+-]\d{2}:\d{2})")')], T_BDQ, {}, "FAIL: golden-bad-time-not-utc"),
    # V4-3: "met" with nothing measured
    ("R2-M13", CB, [("    if overall_measured == 0:", "    if False:")], T_CB, {"CB_ONLY": "C-V43"}, "NOT ok [C-V43]"),
    # V4-3: "met" although an item has no measured run
    ("R2-M14", CB, [("            and not short):", "            ):")], T_CB, {"CB_ONLY": "C-V43"}, "NOT ok [C-V43]"),
    # V4-3: zero items exit 0
    ("R2-M15", CB, [("    if not items:\n        return (\"UNMEASURED: the sample holds zero items",
                     "    if False:\n        return (\"UNMEASURED: the sample holds zero items")],
     T_CB, {"CB_ONLY": "C-V43"}, "NOT ok [C-V43]"),
    # V4-3 positive control: "met" can never be claimed
    ("R2-M16", CB, [("    if (a.cold_runs >= REPLAY_FULL_RUNS", "    if (False and a.cold_runs >= REPLAY_FULL_RUNS")],
     T_CB, {"CB_ONLY": "C-F21"}, "NOT ok [C-F21]"),
    # V4-11: the corpus-search claim restored
    ("R2-M17", CB, [("this tool performs no transcript search of its own", "zero attributable transcript records found by direct corpus search")],
     T_CB, {"CB_ONLY": "C-V411"}, "NOT ok [C-V411]"),
    # V4-13: unsafe ids used as paths again
    ("R2-M18", CB, [("    if unsafe:\n", "    if False:\n")], T_CB, {"CB_ONLY": "C-V413"}, "NOT ok [C-V413]"),
]

CONTROLS = [("control-r6-F4", T_R6, {"R6_ONLY": "F4"}, "ok [R6-F4]"),
            ("control-bdq", T_BDQ, {}, "PASS: golden-bad-fp-mismatch"),
            ("control-cb-F22", T_CB, {"CB_ONLY": "C-F22"}, "ok [C-F22]"),
            ("control-r2-V4-10", T_R2, {"R2_ONLY": "V4-10"}, "ok [V4-10]"),
            ("control-cb-V43", T_CB, {"CB_ONLY": "C-V43"}, "ok [C-V43]")]


def replica():
    root = tempfile.mkdtemp(prefix="r6mut.")
    shutil.copytree(os.path.join(FC, "cycle"), os.path.join(root, "cycle"))
    shutil.copytree(os.path.join(FC, "lib"), os.path.join(root, "lib"))
    return root


def run_test(root, test, extra_env):
    env = dict(os.environ)
    env.pop("FC_OUT", None)
    env.update(extra_env)
    env["FC_BR_UNDER_TEST"] = os.path.join(root, BR)
    env["FC_CB_UNDER_TEST"] = os.path.join(root, CB)
    env["FC_BDQ_TOOL_UNDER_TEST"] = os.path.join(root, BDQ)
    p = subprocess.run(["bash", os.path.join(TESTS, test)], env=env, capture_output=True, text=True,
                       timeout=600)
    return p.returncode, p.stdout


passed = failed = 0


def report(ok, msg):
    global passed, failed
    if ok:
        passed += 1
        print("ok " + msg)
    else:
        failed += 1
        print("NOT ok " + msg)


for cid, test, envx, want in CONTROLS:
    if ONLY and cid not in ONLY:
        continue
    root = replica()
    try:
        rc, out = run_test(root, test, envx)
        hit = any(l.startswith(want) for l in out.splitlines())
        report(rc == 0 and hit, "%s: the UNMUTATED replica passes %s (%s) rc=%d" % (cid, test, want, rc))
    finally:
        shutil.rmtree(root, ignore_errors=True)

for mid, target, pairs, test, envx, want in MUTS:
    if ONLY and mid not in ONLY:
        continue
    root = replica()
    try:
        path = os.path.join(root, target)
        src = open(path).read()
        bad_anchor = None
        for old, new in pairs:
            n = src.count(old)
            if n != 1:
                bad_anchor = "anchor matched %d times: %r" % (n, old[:80])
                break
            src = src.replace(old, new, 1)
        if bad_anchor:
            report(False, "%s: mutation could not be applied (%s) -- the anchor drifted" % (mid, bad_anchor))
            continue
        open(path, "w").write(src)
        rc, out = run_test(root, test, envx)
        hit = [l for l in out.splitlines() if l.startswith(want)]
        if rc != 0 and hit:
            report(True, "%s CAUGHT by %s: %s" % (mid, test, hit[0][:160]))
        else:
            report(False, "%s SURVIVED %s (rc=%d, no line starting %r)" % (mid, test, rc, want))
    finally:
        shutil.rmtree(root, ignore_errors=True)

print("----")
print("SUMMARY pass=%d fail=%d" % (passed, failed))
sys.exit(0 if failed == 0 else 1)
PYEOF
