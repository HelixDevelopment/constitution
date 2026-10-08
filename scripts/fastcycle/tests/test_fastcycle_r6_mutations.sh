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
# T048 restart ROUND 3 (STRUCTURAL; docs/qa/t048_restart_round3_20261008/V4_baseline.md):
# the stop subsystem was replaced by cycle/fc_supervisor.py. Every mutation whose
# anchor named a removed mechanism (traps, TERM forwarding, sessions, tokens, the
# /proc scan) is RE-EXPRESSED against the supervisor with the SAME defect class
# and the same id (R6-M5/M7/M20/M21, V4-N4/N12, R2-M1/M2/M4/M6/M7/M8/M10); the
# round-3 reviewer's mutants are V4R3-N*; R3-M* are the round-3 fixer's own. Stop
# mutations run ONE row of the r2 stop matrix (SM(...) below); the controls run
# the same rows against an UNMUTATED replica. NEVER add a mutation that removes
# the supervisor's nesting limit (MAX_NEST): without it a recursion mutant forks
# without end on the host (§12.12).
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
SUP = "cycle/fc_supervisor.py"
T_R6 = "test_baseline_replay_r6_findings.sh"
T_R4 = "test_baseline_replay_r4_findings.sh"
T_CB = "test_collect_baseline_red.sh"
T_BDQ = "test_build_deploy_qa_events_red.sh"
T_R2 = "test_baseline_replay_r2_findings.sh"
T_SUP = "test_fc_supervisor_unit.sh"


def SM(sig, target, shape):
    """env selecting ONE row of the r2 stop matrix (no extra rows)"""
    return {"R2_ONLY": "SM", "SM_SIGNALS": sig, "SM_TARGETS": target, "SM_SHAPES": shape, "SM_EXTRA": ""}


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
    # R6-M5 re-expressed (round 3): the timeout is OBSERVED (marker), never inferred from the exit code
    ("R6-M5", BR, [("    timed_out) printf 'UNMEASURED|timed out (exit %s, limit %sms)' \"$rc\" \"$tmo_ms\"; return 0 ;;\n", "    timed_out) ;;\n")],
     T_R6, {"R6_ONLY": "F8t"}, "NOT ok [R6-F8t]"),
    ("R6-M6", BR, [('${item_re}([^0-9]|$) ]]', '${item_re} ]]')],
     T_R4, {}, "NOT ok B2"),
    # R6-M7 re-expressed (round 3): the stop handlers end the tool WITHOUT stopping the gate tree. Observable
    # only through a descendant that escapes the PDEATHSIG chain (keeper -> worker -> run -> gate), which
    # kills a plain gate by itself: the ownsess row's setsid child (measured: the "never" row let it survive).
    ("R6-M7", SUP, [("    n = stop_tree(grace, label)\n    if n:\n        say(\"supervisor (%s): stopped", "    n = 0\n    if n:\n        say(\"supervisor (%s): stopped")],
     T_R2, SM("TERM", "main", "ownsess"), "NOT ok [SM] TERM-main-ownsess"),
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
    # R6-M20 re-expressed (round 3): the worktree is removed BEFORE the gate tree is stopped
    ("R6-M20", SUP, [("    n = stop_tree(grace, label)\n    if n:\n        say(\"supervisor (%s): stopped %d process(es) (%s)\" % (label, n, reason))\n    process_ledger(tmpdir, reason)\n",
                      "    process_ledger(tmpdir, reason)\n    n = stop_tree(grace, label)\n    if n:\n        say(\"supervisor (%s): stopped %d process(es) (%s)\" % (label, n, reason))\n")],
     T_R2, SM("TERM", "main", "ignterm"), "NOT ok [SM] TERM-main-ignterm"),
    # R6-M21 re-expressed (round 3): the main pid never forwards the stop to the supervisor
    ("R6-M21", SUP, [("    if Stop.target_fd is not None:\n        try:\n            signal.pidfd_send_signal(Stop.target_fd, signal.SIGTERM)", "    if False:\n        try:\n            signal.pidfd_send_signal(Stop.target_fd, signal.SIGTERM)")],
     T_R2, SM("TERM", "main", "never"), "NOT ok [SM] TERM-main-never"),
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
    # V4-N4 re-expressed (round 3): the main pid exits before the stop has finished
    ("V4-N4", SUP, [("    while True:\n        reap()\n        if kpid in REAPED:\n            break\n", "    while True:\n        if Stop.sig:\n            os._exit(128 + Stop.sig)\n        reap()\n        if kpid in REAPED:\n            break\n")],
     T_R2, SM("TERM", "main", "ignterm"), "NOT ok [SM] TERM-main-ignterm"),
    ("V4-N5", BR, [('if [ "$free_kb" -lt "$min_free_kb" ]; then', 'if false; then')],
     T_R2, {"R2_ONLY": "V4-5"}, "NOT ok [V4-5]"),
    ("V4-N6", BR, [('[ -z "$best_at" ] || [ "$at" -gt "$best_at" ]', '[ -z "$best_at" ] || [ "$at" -ge "$best_at" ]')],
     T_R2, {"R2_ONLY": "N6"}, "NOT ok [N6]"),
    ("V4-N10", BR, [("log --all -i -F --grep=", "log --all -i --grep=")],
     T_R2, {"R2_ONLY": "N10"}, "NOT ok [N10]"),
    # V4-N12 re-expressed (round 3, survived round 3 under nohup): a SECOND signal cuts the stop short
    ("V4-N12", SUP, [("    if Stop.sig:\n        return  # a second signal", "    if Stop.sig:\n        os._exit(128 + signum)  # a second signal")],
     T_R2, SM("TERM", "main", "ignterm"), "NOT ok [SM] TERM-main-ignterm"),
    # ---- round-2 fixer mutations ----
    # V4-1: no session -> the gate's nested-timeout child survives
    # R2-M1/M2 re-expressed (round 3): no child subreaper in the main pid and the keeper ->
    # a gate child that calls setsid / double-forks escapes the tree
    ("R2-M1", SUP, [("    _prctl(PR_SET_CHILD_SUBREAPER, 1)\n    _install_stop(entry_mask)\n    old = signal.pthread_sigmask", "    _install_stop(entry_mask)\n    old = signal.pthread_sigmask"),
                    ("        _prctl(PR_SET_CHILD_SUBREAPER, 1)\n        _install_stop(entry_mask)\n        env = dict", "        _install_stop(entry_mask)\n        env = dict")],
     T_R2, SM("TERM", "main", "ownsess"), "NOT ok [SM] TERM-main-ownsess"),
    # V4-1: no token match -> a child that called setsid itself survives
    # R2-M2 re-expressed (round 3): the per-run sweep -- a process a gate run leaves behind survives into the next run
    ("R2-M2", SUP, [("    n = stop_tree(a.grace, \"run\")\n    if n:", "    n = 0\n    if n:")],
     T_R2, {"R2_ONLY": "PERRUN"}, "NOT ok [PERRUN]"),
    # V4-2: the round-1 rule (>= 129 = "terminated by signal") restored
    ("R2-M3", BR, [("  if [ \"$rc\" = 0 ]; then printf 'PASS|exit 0'; return 0; fi",
                    "  if [ \"$rc\" -ge 129 ]; then printf 'UNMEASURED|terminated by signal %s' \"$((rc - 128))\"; return 0; fi\n"
                    "  if [ \"$rc\" = 0 ]; then printf 'PASS|exit 0'; return 0; fi")],
     T_R2, {"R2_ONLY": "V4-2"}, "NOT ok [V4-2]"),
    # V4-4: no lock
    # R2-M4 re-expressed (round 3): no lock
    ("R2-M4", SUP, [("        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\n", "        pass\n")], T_R2, {"R2_ONLY": "V4-4"}, "NOT ok [V4-4]"),
    # V4-4: the object store's filesystem never checked
    ("R2-M5", BR, [('  if [ "$objects_free_kb" -lt "$min_free_kb_objects" ]; then', '  if false; then')],
     T_R2, {"R2_ONLY": "V4-5"}, "NOT ok [V4-4]"),
    # V4-8: a background watchdog sleep is back on the signal path
    # R2-M6 re-expressed (round 3): the run supervisor is not a subreaper -> a gate's double-forked
    # daemon is re-parented past it and survives into the next run
    ("R2-M6", SUP, [("    _prctl(PR_SET_CHILD_SUBREAPER, 1)\n    # the caller's ignored signals stay ignored here too", "    # the caller's ignored signals stay ignored here too")],
     T_R2, {"R2_ONLY": "PERRUN"}, "NOT ok [PERRUN]"),
    # V4-9: the private temp directory is never removed
    # R2-M7 re-expressed (round 3): the private temp directory is never removed
    ("R2-M7", SUP, [("    if os.path.basename(tmpdir).startswith(\"fc_baseline_replay.\"):\n        shutil.rmtree(tmpdir, ignore_errors=True)\n", "    if False:\n        pass\n")],
     T_R2, SM("TERM", "worker", "never"), "NOT ok [SM] TERM-worker-never"),
    # V4-9: selfcheck without signal handlers
    # R2-M8 re-expressed (round 3): selfcheck runs unsupervised
    ("R2-M8", BR, [('  # replay (T048 restart round 2 V4-9 / round 3).\n  _fc_supervise "" ""\n', '  # replay (T048 restart round 2 V4-9 / round 3).\n')],
     T_R2, dict(SM("TERM", "worker", "never"), SM_SHAPES="", SM_EXTRA="selfcheck"), "NOT ok [SM] selfcheck-"),
    # V4-6 class in the freeze CLI: a whitespace-only id accepted
    ("R2-M9", BR, [('  case "$item" in *[[:space:]]*) die', '  case "$item" in "#never") die')],
     T_R2, {"R2_ONLY": "WS"}, "NOT ok [WS]"),
    # V4-6: blank values count as present again (the reviewer's V4-N7 shape, one level up)
    # R2-M10 re-expressed (round 3): blank / invisible values count as present again
    ("R2-M10", BDQ, [('    return isinstance(value, str) and any(unicodedata.category(c)[0] in "LNPS" for c in value)', '    return isinstance(value, str) and value != ""')],
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
    # ---- round-3 reviewer mutations (docs/qa/t048_restart_round3_20261008/V4_baseline.md), re-expressed where
    # the mechanism they mutated was replaced by the supervisor ----
    # V4R3-N1 (session match dropped) is the "a descendant escapes the tree" class: R2-M1 above.
    # V4R3-N2 / V4R3-3: no KILL escalation -- a TERM-ignoring child in its own session outlives the tool
    ("V4R3-N2", SUP, [("                    signal.pidfd_send_signal(fd, signal.SIGKILL)\n", "                    pass\n")],
     T_R2, SM("TERM", "main", "ownsess"), "NOT ok [SM] TERM-main-ownsess"),
    # V4R3-N3 / V4R3-6: the lock on --git-dir instead of the COMMON git dir (linked worktrees)
    ("V4R3-N3", BR, [('    common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"\n    { [ -n "$common" ]',
                      '    common="$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)"\n    { [ -n "$common" ]')],
     T_R2, {"R2_ONLY": "V4-4"}, "NOT ok [V4-4]"),
    # V4R3-N4 / V4R3-5: the lock fd is inherited by the worker (and so by every gate / hook)
    ("V4R3-N4", SUP, [("        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\n", "        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\n        os.set_inheritable(fd, True)\n")],
     T_R2, SM("TERM", "main", "daemon"), "NOT ok [SM] TERM-main-daemon"),
    # V4R3-N5 / V4R3-4: the object-store floor measures the worktree root's filesystem
    ("V4R3-N5", BR, [('  objects_free_kb="$(df -Pk "$objects_dir" 2>/dev/null', '  objects_free_kb="$(df -Pk "$worktree_root" 2>/dev/null')],
     T_R2, {"R2_ONLY": "V4-5"}, "NOT ok [V4-4]"),
    # V4R3-N6 / V4R3-7: values echoed without escaping
    ("V4R3-N6", BDQ, [('    return json.dumps(value, ensure_ascii=True, separators=(",", ":")).replace(" ", "\\\\u0020").replace("/", "\\\\/")', "    return str(value)")],
     T_BDQ, {}, "FAIL: golden-bad-buildid-newline"),
    # V4R3-N7 / V4R3-8: the deploy time accepted with trailing garbage
    ("V4R3-N7", BDQ, [("not _UTC_RE.fullmatch(value)", "not _UTC_RE.match(value)")], T_BDQ, {}, "FAIL: golden-bad-time-trailing-junk"),
    # V4R3-N10 (zombies counted as live) is NOT in this table: against the supervisor it is an EQUIVALENT mutant.
    # Every zombie in the tree is either a child of a supervisor role (reaped by reap() on every 50 ms iteration)
    # or the child of a still-live tree member that is itself being stopped -- counting it changes nothing
    # observable (measured 2026-10-08: the mutant passed the TERM-main-never row, stop well inside the bound).
    # The reviewer's underlying gap -- "no test bounds stop latency" -- is closed: every stop-matrix row with a
    # TERM-honouring gate must stop within 0.75 x the grace period.
    # V4R3-N11: replay-sample refuses only a space, not other whitespace
    ("V4R3-N11", BR, [('or "\\0" in iid or any(c.isspace() for c in iid):', 'or "\\0" in iid or " " in iid:')],
     T_R2, {"R2_ONLY": "WS"}, "NOT ok [WS]"),
    # V4R3-N12: collect_baseline's safe_item_id lets a bare '/' through
    ("V4R3-N12", CB, [('if any(c in iid for c in ("/", "\\\\", "\\0"))', 'if any(c in iid for c in ("\\\\", "\\0"))')],
     T_CB, {"CB_ONLY": "C-V413"}, "NOT ok [C-V413]"),
    # ---- round-3 fixer mutations ----
    # V4R3-1 core: the keeper ignores the death of the main pid (SIGKILL of main -> run loop goes on)
    ("R3-M1", SUP, [("                if not data:\n                    reason, code", "                if False:\n                    reason, code")],
     T_R2, SM("KILL", "main", "quick"), "NOT ok [SM] KILL-main-quick"),
    # the worker's long-running child back in the FOREGROUND (round-4 B1 class): a stop signal to the
    # worker is deferred until the gate ends by itself
    ("R3-M2", BR, [('    --cwd "$cwd" --entry-sigign "$_FC_ENTRY_SIGIGN" -- "$@" >"$log" 2>&1 </dev/null &\n  wait "$!"\n',
                    '    --cwd "$cwd" --entry-sigign "$_FC_ENTRY_SIGIGN" -- "$@" >"$log" 2>&1 </dev/null\n')],
     T_R2, SM("TERM", "worker", "never"), "NOT ok [SM] TERM-worker-never"),
    # the PDEATHSIG chain removed -> with both supervisor processes SIGKILLed the run loop goes on
    ("R3-M3", SUP, [("            _prctl(PR_SET_PDEATHSIG, signal.SIGKILL)\n            if os.getppid() != parent:\n                os._exit(137)\n", "")],
     T_R2, dict(SM("KILL", "main", "never"), SM_SHAPES="", SM_EXTRA="doublekill"), "NOT ok [SM] doublekill"),
    # nohup not respected: a signal ignored by the caller is handled anyway
    ("R3-M4", SUP, [("        if not ignored(entry_mask, s):\n            signal.signal(s, _on_stop)", "        if True:\n            signal.signal(s, _on_stop)")],
     T_R2, dict(SM("HUP", "main", "never"), SM_SHAPES="", SM_EXTRA="nohup", SM_TARGETS="main"), "NOT ok [SM] HUP-main-never-nohup"),
    # the caller's dispositions read from bash's OWN /proc entry (bash ignores QUIT internally) -> QUIT ignored in the
    # worker. (On the MAIN target the unhandled QUIT just kills the main pid and the keeper cleans up asynchronously --
    # a race for the "nothing left at exit" check; the worker's disposition check is deterministic.)
    ("R3-M5", BR, [("  ign=\"$(awk '/^SigIgn:/{print $2; exit}' /proc/self/status 2>/dev/null)\"", "  ign=\"$(awk '/^SigIgn:/{print $2; exit}' \"/proc/$$/status\" 2>/dev/null)\"")],
     T_R2, SM("QUIT", "worker", "never"), "NOT ok [SM] QUIT-worker-never"),
    # V4R3-14: the INTERRUPTED marker of an interrupted run-log directory never written
    ("R3-M6", SUP, [('        elif kind == "logs" and fields and fields[0]:', '        elif False:')],
     T_R2, SM("TERM", "worker", "never"), "NOT ok [SM] TERM-worker-never"),
    # V4R3-6: the per-filesystem lock dropped (only the per-repository lock left)
    ("R3-M7", BR, [(' --lock-dir "$lockdir" --lock-fs "$2" --lock-fs "$common")', ")")],
     T_R2, {"R2_ONLY": "V4-4"}, "NOT ok [V4-4]"),
    # the worker re-enters the supervisor (the recursion found while writing round 3; the supervisor's
    # nesting limit turns it into a BLIND refusal instead of a fork bomb -- never mutate that limit)
    ("R3-M8", BR, [('  [ "$_FC_IS_WORKER" = 1 ] && return 0\n', '  false && return 0\n')],
     T_R2, {"R2_ONLY": "V4-10"}, "NOT ok [V4-10]"),
    # a gate's own 124 read as a timeout again (the run supervisor records every exit as timed_out)
    ("R3-M9", SUP, [('    _mark(a.marker, "exited")\n', '    _mark(a.marker, "timed_out")\n')],
     T_R6, {"R6_ONLY": "F8"}, "NOT ok [R6-F8]"),
    # V4R3-7: a JSON-looking plain value ("5") echoed verbatim -- collides with the number 5
    ("R3-M10", BDQ, [("_PLAIN_RE.fullmatch(value) and not _is_json(value):", "_PLAIN_RE.fullmatch(value):")],
     T_BDQ, {}, "FAIL: golden-bad-verdict-json-string"),
    # the cascade race found by the stop matrix (KILL-supervisor-nested, 1 of 193 rows, 2026-10-08): an empty
    # walk that saw a zombie ends the stop although the zombie's children are still being reparented
    ("R3-M11", SUP, [("        if not members and not zombies:\n            return len(seen)", "        if not members:\n            return len(seen)")],
     T_SUP, {}, "NOT ok [Z1]"),
]

CONTROLS = [("control-r6-F4", T_R6, {"R6_ONLY": "F4"}, "ok [R6-F4]"),
            ("control-bdq", T_BDQ, {}, "PASS: golden-bad-fp-mismatch"),
            ("control-cb-F22", T_CB, {"CB_ONLY": "C-F22"}, "ok [C-F22]"),
            ("control-r2-V4-10", T_R2, {"R2_ONLY": "V4-10"}, "ok [V4-10]"),
            ("control-cb-V43", T_CB, {"CB_ONLY": "C-V43"}, "ok [C-V43]"),
            # every stop-matrix row a mutation below uses must pass on the UNMUTATED replica
            ("control-sm-rows", T_R2, {"R2_ONLY": "SM", "SM_SIGNALS": "TERM", "SM_TARGETS": "main worker",
                                       "SM_SHAPES": "never ignterm ownsess daemon", "SM_EXTRA": ""}, "ok [SM] TERM-main-never"),
            ("control-sm-extra", T_R2, {"R2_ONLY": "SM", "SM_SIGNALS": "KILL QUIT", "SM_TARGETS": "main",
                                        "SM_SHAPES": "quick never", "SM_EXTRA": "doublekill nohup selfcheck"}, "ok [SM] KILL-main-quick"),
            ("control-r2-PERRUN", T_R2, {"R2_ONLY": "PERRUN"}, "ok [PERRUN]"),
            ("control-sup-unit", T_SUP, {}, "ok [Z1]")]


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
    env["FC_SUP_UNDER_TEST"] = os.path.join(root, SUP)
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
