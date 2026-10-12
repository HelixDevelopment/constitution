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
# T048 restart ROUND 4 (R4-S* group; V4 review): the fixer's S1/S2/S3/S5/S5b rows and the round-4
# reviewer's RA1/RA3/RA4/RA6/RA7(+RA7b) mutants (R4-RA*) all run against tests/test_fc_supervisor_unit.sh,
# whose oracle cases are [S1] [S1b] [S1-tree] [S2] [S3] [G1] (open_verified / stop_tree parent checks) and
# [S5] [S5b] [S5d] [S5e] [S5f] [S5g] (process_ledger's rmtree guard). The R4-S*/RA* mutants touch only
# cycle/fc_supervisor.py in the replica; the unit test's signal spy never signals pid 1 or the test process.
#
# T048 V4 round 6 (V4R6-* group): the round-6 fixer's F1/F2/F8 rows and the round-6 reviewer's surviving mutants
# X2/X3/X5/X8 adopted as permanent rows; R5-F9b re-expressed as a well-formed mutant (F3); R5-F1e/R5-F1i now require
# the blocked-TERM case to NAME the measured cause (F7). F6 (this suite's own EXIT-trap cleanup) lives in the test
# file, which the replica does not copy: its RED was shown against the round-5 cleanup function and [CLEANUP] guards it.
#
# T048 V4 round 7 (V4R7-* group, STRUCTURAL closure of two recurring classes): the reviewer's mutant RVM-04 adopted
# verbatim; the fixer's own rows for N1 (ownership), N2 (flush), N3 (ledger/done/deferral), N4 (progress beats / cap),
# N5 (the documented-code funnel, both layers) and N6 (early INT handler, -S). Their cases live in
# test_fc_supervisor_v4r5_findings.sh (R7*) and one stop-matrix row (KILL-supervisor-daemon).
#
# T048 V4 round 8 (V4R8-* group; CLASS 2 2nd structural attempt): V4R8-1a..d (caller streams: closed-stream flush /
# say, fd repair, SIGPIPE ignore) against tests/test_fc_supervisor_v4r8_stream_matrix.sh; V4R8-2a..c (report written =
# durable state: identity half, body_hash half) against the unit file and [R8N3STALE]; the reviewer's mutants RVM-02 /
# DOC128 / USR2ANY adopted verbatim; V4R8-6a/b (ownership prune). V4R7-N3a/b/c re-expressed against the durable report
# state; V4R7-N3d retired (the worker's stop deferral was removed -- see its comment).
#
# T048 V4 round 9 (V4R9-* group; §11.4.276(E) STRUCTURAL round -- the V4R8-2 class: every state an exit decision
# reads must outlive every process that still has to decide): the round-2 reviewer's 14 mutants RVM-A..N adopted
# (verbatim where the anchor still exists; C/D/H re-expressed against decide_code / the 5-field identity), the fixer's
# own V4R9-M1..M11 (state directory lifetime, one derivation, bounded say, gc). Their oracles: the unit file ([R9*]),
# the v4r5 R8N3*/R7N3C rows, the extended stream matrix and tests/test_fc_supervisor_v4r9_shutdown_windows.sh.
# Re-expressed this round (anchors named code round 9 replaced; same defect class, same ids): R6-M20, R3-M1, V4R6-F8,
# V4R7-N3b (now BOTH layers), V4R7-N3c, V4R8-1b.
#
# T048 V4 round 10 (V4R10-* group; §11.4.276(E) STRUCTURAL round -- third member of the V4R8-2 class: a resource whose
# lifetime spans several processes needs ONE ownership model every deleter and reader obeys -> the state directory's
# LEASE): the round-3 reviewer's 14 mutants RV3-01..14 adopted VERBATIM; V4R7-N2 re-instated (its round-9 retirement
# rested on a false equivalence proof, V4R10-2); the fixer's own V4R10-M1..M11. Oracles: the unit file ([R10*]), the
# windows file ([R10LEASE] [R10DROP]), the stream matrix (fd-direction needle in every role, V4R10-6), r2 [SM].
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
T_V5 = "test_fc_supervisor_v4r5_findings.sh"
T_V8 = "test_fc_supervisor_v4r8_stream_matrix.sh"
T_V9 = "test_fc_supervisor_v4r9_shutdown_windows.sh"


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
    ("R6-M20", SUP, [("    n = stop_tree(grace, label)\n    if n:\n        say(\"supervisor (%s): stopped %d process(es) (%s)\" % (label, n, reason))\n    process_ledger(tmpdir, reason, statedir)\n",
                      "    process_ledger(tmpdir, reason, statedir)\n    n = stop_tree(grace, label)\n    if n:\n        say(\"supervisor (%s): stopped %d process(es) (%s)\" % (label, n, reason))\n")],
     T_R2, SM("TERM", "main", "ignterm"), "NOT ok [SM] TERM-main-ignterm"),
    # R6-M21 re-expressed (round 3): the main pid never forwards the stop to the supervisor
    ("R6-M21", SUP, [("    if Stop.target_fd is not None:\n        # forward the signal M RECEIVED", "    if False:\n        # forward the signal M RECEIVED")],
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
    ("R3-M1", SUP, [("                if not data:\n                    reason, cause", "                if False:\n                    reason, cause")],
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
    # (round 5: the instrument reads with sed -- gawk ignores SIGPIPE itself; the anchor follows the line, same defect)
    # (round 7: the caller's process now TRAPS HUP/INT/QUIT/TERM in front of the exec (N6), which replaces bash's
    # internal QUIT ignore -- measured: SigIgn of $$ 0x4 without the trap, 0x0 with it -- so the /proc/$$ read alone
    # became an EQUIVALENT mutant (it survived the round-7 run). Re-expressed: the /proc/$$ read together with the
    # QUIT trap removed, i.e. the round-3 situation the guard exists for.)
    ("R3-M5", BR, [("  ign=\"$(sed -n 's/^SigIgn:[[:space:]]*//p' /proc/self/status 2>/dev/null)\"", "  ign=\"$(sed -n 's/^SigIgn:[[:space:]]*//p' \"/proc/$$/status\" 2>/dev/null)\""),
                   ("      trap 'exit 131' QUIT\n", "")],
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
    # ---- round-4 reviewer F5 (S1, S5 adopted verbatim) + the fixer's class siblings (S2, S3, S5b) ----
    ("R4-S1", SUP, [("    ok = sf is not None and sf[1] == parent", "    ok = sf is not None")],
     T_SUP, {}, "NOT ok [S1]"),
    ("R4-S2", SUP, [("    if pid <= 1 or pid == os.getpid():", "    if pid == os.getpid():")],
     T_SUP, {}, "NOT ok [S2]"),
    ("R4-S3", SUP, [("    if pid <= 1 or pid == os.getpid():", "    if pid <= 1:")],
     T_SUP, {}, "NOT ok [S3]"),
    ("R4-S5", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):', "if os.path.isabs(wt):")],
     T_SUP, {}, "NOT ok [S5]"),
    ("R4-S5b", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):',
                      'if os.path.basename(wt).startswith("replay."):')],
     T_SUP, {}, "NOT ok [S5b]"),
    # ---- round-4 V4 reviewer's own mutants (test-instrumentation findings F1/F2/F3), adopted as permanent rows ----
    ("R4-RA1", SUP, [("    ok = sf is not None and sf[1] == parent", "    ok = sf is None or sf[1] == parent")],
     T_SUP, {}, "NOT ok [S1b]"),
    ("R4-RA3", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):', 'if os.path.isabs(wt) and os.path.basename(wt).startswith("replay"):')],
     T_SUP, {}, "NOT ok [S5e]"),
    ("R4-RA4", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):', 'if os.path.isabs(wt) and "replay." in wt:')],
     T_SUP, {}, "NOT ok [S5d]"),
    ("R4-RA6", SUP, [("            fd = open_verified(pid, parent)\n", "            fd = open_verified(pid, me)\n")],
     T_SUP, {}, "NOT ok [G1]"),
    ("R4-RA7", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):', 'if os.path.isabs(wt) and (wt.endswith("/") or os.path.basename(wt).startswith("replay.")):')],
     T_SUP, {}, "NOT ok [S5f]"),
    ("R4-RA7b", SUP, [('if os.path.isabs(wt) and os.path.basename(wt).startswith("replay."):', 'if os.path.isabs(wt) and os.path.basename(wt.rstrip("/")).startswith("replay."):')],
     T_SUP, {}, "NOT ok [S5g]"),
    # ---- T048 V4 round 5 (independent review of b61583e): reviewer mutants RM-A / RM-B adopted verbatim, plus
    # the fixer's own R5-* rows, against tests/test_fc_supervisor_v4r5_findings.sh (T_V5), the r2 stop matrix's
    # round-5 extra rows, and the collect_baseline / build_deploy_qa_events suites ----
    ("RM-A", SUP, [("            signal.pidfd_send_signal(fd, 0)\n", "            pass\n")],
     T_V5, {"V5_ONLY": "RMA"}, "NOT ok [RMA]"),
    ("RM-B", SUP, [("stop_deadline = time.monotonic() + a.grace + KILL_WAIT_S + KEEPER_SLACK_S", 'stop_deadline = float("inf")')],
     T_V5, {"V5_ONLY": "RMB"}, "NOT ok [RMB]"),
    # F1: SIGCHLD no longer reset -> a SIGCHLD-ignoring caller's run loses every status
    ("R5-F1a", SUP, [("    signal.signal(signal.SIGCHLD, signal.SIG_DFL)\n    signal.pthread_sigmask(signal.SIG_SETMASK, [])\n",
                      "    signal.pthread_sigmask(signal.SIG_SETMASK, [])\n")],
     T_V5, {"V5_ONLY": "F1RUN"}, "NOT ok [F1RUN]"),
    # F1: the run role's lost-status branch removed -> it waits out the whole timeout on a readable pidfd
    ("R5-F1b", SUP, [('            if reap_target(pid) == "lost":\n                lost = True\n                break\n',
                      '            if False:\n                lost = True\n                break\n')],
     T_V5, {"V5_ONLY": "F1LOST"}, "NOT ok [F1LOST]"),
    # F1: the keeper's and main's lost-status branches removed -> 100% CPU spin, no exit
    ("R5-F1c", SUP, [('            if wpid not in REAPED and wfd in ready and reap_target(wpid) == "lost":', '            if False:'),
                     ('        if ready and reap_target(kpid) == "lost":', '        if False:')],
     T_V5, {"V5_ONLY": "F1LOSTMAIN"}, "NOT ok [F1LOSTMAIN]"),
    # F1 class: every caller-ignored disposition kept again (SIGPIPE leaks into the gate)
    ("R5-F1d", SUP, [("signal.SIG_IGN if (s in KEEP_IGNORED and ignored(entry_mask, s))", "signal.SIG_IGN if (ignored(entry_mask, s))")],
     T_V5, {"V5_ONLY": "CENSUS"}, "NOT ok [CENSUS] SIGPIPE"),
    # class: the inherited signal mask restored in main -> a caller-blocked TERM keeps the tool unstoppable by TERM
    ("R5-F1e", SUP, [("    signal.signal(signal.SIGCHLD, signal.SIG_DFL)\n    signal.pthread_sigmask(signal.SIG_SETMASK, [])\n",
                      "    signal.signal(signal.SIGCHLD, signal.SIG_DFL)\n"),
                     ("    signal.pthread_sigmask(signal.SIG_SETMASK, [])   # never the inherited `old` mask",
                      "    signal.pthread_sigmask(signal.SIG_SETMASK, old)   # never the inherited `old` mask")],
     T_V5, {"V5_ONLY": "CENSUS"}, "NOT ok [CENSUS] blocked TERM: the inherited mask kept TERM blocked"),
    # class: the umask pre-flight removed
    ("R5-F1f", SUP, [("    if um & 0o700:\n", "    if False:\n")], T_V5, {"V5_ONLY": "CENSUS"}, "NOT ok [CENSUS] umask"),
    # census: the entry-mask instrument back on awk (gawk ignores SIGPIPE itself)
    ("R5-F1g", BR, [("  ign=\"$(sed -n 's/^SigIgn:[[:space:]]*//p' /proc/self/status 2>/dev/null)\"",
                     "  ign=\"$(awk '/^SigIgn:/{print $2; exit}' /proc/self/status 2>/dev/null)\"")],
     T_V5, {"V5_ONLY": "CENSUS"}, "NOT ok [CENSUS] entry-mask instrument"),
    # F1 end to end: the SIGCHLD reset removed -> the stop matrix's sigchld row spins
    ("R5-F1h", SUP, [("    signal.signal(signal.SIGCHLD, signal.SIG_DFL)\n    signal.pthread_sigmask(signal.SIG_SETMASK, [])\n",
                      "    signal.pthread_sigmask(signal.SIG_SETMASK, [])\n"),
                     ("signal.SIG_IGN if (s in KEEP_IGNORED and ignored(entry_mask, s))", "signal.SIG_IGN if (ignored(entry_mask, s))")],
     T_R2, dict(SM("TERM", "main", "never"), SM_SHAPES="", SM_EXTRA="sigchld"), "NOT ok [SM] sigchld-caller-quick"),
    # F2: the locked worktree removed the old way (remove --force refuses it, prune skips it)
    ("R5-F2a", SUP, [('(["worktree", "unlock", wt], ["worktree", "remove", "-f", "-f", wt], ["worktree", "prune"])',
                      '(["worktree", "remove", "--force", wt], ["worktree", "prune"])')],
     T_V5, {"V5_ONLY": "F2LEDGER"}, "NOT ok [F2LEDGER]"),
    # F2: "removed" claimed without the git worktree list verification
    ("R5-F2b", SUP, [("    if not on_disk and listed is False:", "    if not on_disk:")],
     T_V5, {"V5_ONLY": "F2HONEST"}, "NOT ok [F2HONEST]"),
    # F2 in the worker: _fc_wt_cleanup back to remove --force (no unlock, no -f -f)
    ("R5-F2c", BR, [('    git -C "$_FC_WT_REPO" worktree unlock "$_FC_WT_PATH" >/dev/null 2>&1\n    git -C "$_FC_WT_REPO" worktree remove -f -f "$_FC_WT_PATH" >/dev/null 2>&1\n',
                     '    git -C "$_FC_WT_REPO" worktree remove --force "$_FC_WT_PATH" >/dev/null 2>&1\n')],
     T_V5, {"V5_ONLY": "F2WORKER"}, "NOT ok [F2WORKER]"),
    # F2 end to end: the stop matrix's wtaddkill row against the old ledger removal
    ("R5-F2d", SUP, [('(["worktree", "unlock", wt], ["worktree", "remove", "-f", "-f", wt], ["worktree", "prune"])',
                      '(["worktree", "remove", "--force", wt], ["worktree", "prune"])')],
     T_R2, dict(SM("KILL", "worker", "never"), SM_SHAPES="", SM_EXTRA="wtaddkill"), "NOT ok [SM] wtaddkill-worker-KILL"),
    # F3: the start-up control needle removed (main / run)
    ("R5-F3a", SUP, [("    if not children_probe():\n        say(BLIND_CHILDREN)\n        sys.exit(4)\n", "")],
     T_V5, {"V5_ONLY": "F3"}, "NOT ok [F3]"),
    ("R5-F3b", SUP, [('    if not children_probe():\n        say(BLIND_CHILDREN)\n        _mark(a.marker, "probe_failed")\n        os._exit(125)\n', "")],
     T_V5, {"V5_ONLY": "F3"}, "NOT ok [F3]"),
    ("R5-F3c", SUP, [("    if not children_probe():\n        say(BLIND_CHILDREN)\n        sys.exit(4)\n", "")],
     T_R2, dict(SM("TERM", "main", "never"), SM_SHAPES="", SM_EXTRA="nochildren"), "NOT ok [SM] nochildren-blind"),
    # F4: the `stopped` marker unknown to classify_run again
    ("R5-F4", BR, [("    stopped) printf 'UNMEASURED|stopped: the run supervisor received a stop signal from outside this harness (exit %s) -- the gate did not finish; this harness sent it nothing' \"$rc\"; return 0 ;;\n", "")],
     T_R2, dict(SM("TERM", "main", "never"), SM_SHAPES="", SM_EXTRA="runsig"), "NOT ok [SM] runsig-TERM-fcrun-never"),
    # F5: the command's own exit instant ignored by the worker / measured after the leftover stop by the run supervisor
    ("R5-F5a", BR, [('    [ -n "$_exit_ns" ] && [ "$_exit_ns" -ge "$RG_START_NS" ] && [ "$_exit_ns" -le "$RG_END_NS" ] && RG_END_NS="$_exit_ns"\n',
                     "    :\n")],
     T_V5, {"V5_ONLY": "F5"}, "NOT ok [F5]"),
    ("R5-F5b", SUP, [("    _write_timing(a.timing, exit_ns, n,", "    _write_timing(a.timing, time.time_ns(), n,")],
     T_V5, {"V5_ONLY": "F5"}, "NOT ok [F5]"),
    # F9: pend entries ignored by the supervisor / never written by the worker / the snapshot ignored
    ("R5-F9a", SUP, [('        elif kind == "pend":\n            process_pending(fields, reason)\n', '        elif kind == "pend":\n            pass\n')],
     T_V5, {"V5_ONLY": "F9WT"}, "NOT ok [F9WT]"),
    # round 6 (F3): re-expressed as a WELL-FORMED mutant. Deleting the line (round 5) left _FC_LEDGER_FILE unset, so the
    # next line died with `unbound variable` -- a crash, not the defect. Now the pend entry is simply never written.
    ("R5-F9b", BR, [('  _fc_ledger_pend "$worktree_root" "replay." || { echo "baseline_replay: BLIND: cannot write the cleanup ledger" >&2; return 4; }\n', '  _FC_LEDGER_FILE=""\n')],
     T_V5, {"V5_ONLY": "F9WT"}, "NOT ok [F9WT]"),
    ("R5-F9c", BR, [('  _fc_ledger_pend "$worktree_root/replay-logs" "${commit:0:12}." || { echo "baseline_replay: BLIND: cannot write the cleanup ledger" >&2; return 4; }\n', "")],
     T_V5, {"V5_ONLY": "F9LOGS"}, "NOT ok [F9LOGS]"),
    ("R5-F9d", SUP, [("        if not n.startswith(prefix) or n in before:", "        if not n.startswith(prefix):")],
     T_V5, {"V5_ONLY": "F9LEDGER"}, "NOT ok [F9LEDGER]"),
    # F10: the empty-array-safe expansion reverted (only observable on bash < 4.4: the static guard [F10])
    ("R5-F10", BR, [('${args[@]+"${args[@]}"} -- "$BASH"', '"${args[@]}" -- "$BASH"')],
     T_V5, {"V5_ONLY": "F10"}, "NOT ok [F10]"),
    # F6: the narrowed except clause restored -> a 5000-digit integer / deep nesting / invalid UTF-8 escapes as a traceback
    ("R5-F6", BDQ, [("    except (OSError, json.JSONDecodeError, UnicodeDecodeError, ValueError, RecursionError) as exc:",
                     "    except (OSError, json.JSONDecodeError) as exc:")],
     T_BDQ, {}, "FAIL: malformed-hugeint"),
    # F7: the start-up validation of --fresh-execution-json skipped
    ("R5-F7", CB, [("        if ferr:\n", "        if False:\n")], T_CB, {"CB_ONLY": "C-FRESHJ"}, "NOT ok [C-FRESHJ]"),
    # F8: the closures window back on the bare timestamp comparison
    ("R5-F8", CB, [('        "AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",\n', '        "AND ih.on_date BETWEEN ? AND ?",\n')],
     T_CB, {"CB_ONLY": "C-ONDATE"}, "NOT ok [C-ONDATE]"),
    # CENSUS blocked-TERM case de-flaked 2026-10-09 (it now waits for main's SigCgt+SigBlk set-up state instead
    # of matching its own launcher's argv): main no longer catches TERM -> the bounded SigCgt wait times out, the
    # TERM kills main by its default action (rc -15, not the handled 143) and the case must still say so
    ("R5-F1i", SUP, [("    _install_stop(entry_mask)\n    old = signal.pthread_sigmask(signal.SIG_BLOCK, STOP_SIGS)\n",
                      "    old = signal.pthread_sigmask(signal.SIG_BLOCK, STOP_SIGS)\n")],
     T_V5, {"V5_ONLY": "CENSUS"}, "NOT ok [CENSUS] blocked TERM: no TERM handler"),
    # ---- T048 V4 round 6 (independent review of the round-5 pack: NO-GO 1 IMPORTANT + 7 MINOR) ----
    # F1 (IMPORTANT): main forwards a fixed SIGTERM again -- dropped by a keeper that keeps an entry-ignored TERM
    ("V4R6-F1a", SUP, [("            signal.pidfd_send_signal(Stop.target_fd, signum)", "            signal.pidfd_send_signal(Stop.target_fd, signal.SIGTERM)")],
     T_V5, {"V5_ONLY": "F1TERMIGN"}, "NOT ok [F1TERMIGN]"),
    ("V4R6-F1b", SUP, [("        signal.pidfd_send_signal(kfd, Stop.sig)", "        signal.pidfd_send_signal(kfd, signal.SIGTERM)")],
     T_V5, {"V5_ONLY": "F1LATE"}, "NOT ok [F1LATE]"),
    ("V4R6-F1c", SUP, [("            signal.pidfd_send_signal(Stop.target_fd, signum)", "            signal.pidfd_send_signal(Stop.target_fd, signal.SIGTERM)")],
     T_R2, dict(SM("INT", "main", "never"), SM_SHAPES="", SM_EXTRA="termign"), "NOT ok [SM] INT-main-never-termign"),
    # F2 (injection I3): an empty outcome marker is classified and the replay goes on -- the run's orphaned daemon
    # outlives its run (the worktree is removed under it, a report is written)
    ("V4R6-F2", BR, [('  [ -s "$mk" ] && return "$rc"\n', '  return "$rc"\n')],
     T_R2, dict(SM("KILL", "main", "never"), SM_SHAPES="", SM_EXTRA="runkill"), "NOT ok [SM] runkill-KILL-fcrun-daemon"),
    # F8: a stop that reached main after the work finished overrides the keeper's 0 with 128+N again
    ("V4R6-F8", SUP, [("    if kst is not None and os.WIFEXITED(kst):\n        return (\"code\", os.WEXITSTATUS(kst))\n",
                       "    if kst is not None and os.WIFEXITED(kst) and not sig:\n        return (\"code\", os.WEXITSTATUS(kst))\n")],
     T_V5, {"V5_ONLY": "F8LATE"}, "NOT ok [F8LATE]"),
    # F4: reviewer mutant X5 adopted -- an unreadable `git worktree list` treated as "not listed" (removal verified)
    ("V4R6-X5", BR, [('[ "$listed" != 1 ]; then', '[ "$listed" = 0 ]; then')],
     T_V5, {"V5_ONLY": "F2WORKER"}, "NOT ok [F2WORKER] unverifiable removal"),
    # F5: reviewer mutants X2 / X3 / X8 adopted
    ("V4R6-X2", SUP, [("    if um & 0o700:\n", "    if um & 0o200:\n")],
     T_V5, {"V5_ONLY": "UMASKS"}, "NOT ok [UMASKS] umask 0100"),
    ("V4R6-X3", SUP, [("                        signal.pidfd_send_signal(fd, signal.SIGCONT)\n", "")],
     T_V5, {"V5_ONLY": "STOPCONT"}, "NOT ok [STOPCONT]"),
    ("V4R6-X8", SUP, [("    os._exit(137 if st is not None and os.WIFSIGNALED(st) and os.WTERMSIG(st) == signal.SIGKILL else 124)",
                       "    os._exit(124)")],
     T_V5, {"V5_ONLY": "TMO137"}, "NOT ok [TMO137]"),
    # ---- T048 V4 round 7 (independent review of the round-6 pack: NO-GO 1 IMPORTANT + 6 MINOR; STRUCTURAL) ----
    # T1: reviewer mutant RVM-04 adopted VERBATIM -- the F2 guard accepts a marker that exists but is EMPTY
    ("V4R7-RVM04", BR, [('  [ -s "$mk" ] && return "$rc"\n', '  [ -e "$mk" ] && return "$rc"\n')],
     T_V5, {"V5_ONLY": "R7EMPTYMK"}, "NOT ok [R7EMPTYMK]"),
    # N1 (CLASS 1): main stops every descendant again (no ownership) / its teardown ignores the ownership predicate
    ("V4R7-N1a", SUP, [("    return owner\n", "    return lambda pid: True\n")],
     T_V5, {"V5_ONLY": "R7N1F"}, "NOT ok [R7N1F]"),
    ("V4R7-N1b", SUP, [("    OWNER = _main_owner(kpid, kstart, pre)\n", "    OWNER = None\n")],
     T_V5, {"V5_ONLY": "R7N1L"}, "NOT ok [R7N1L]"),
    # N1: the keeper's SESSION no longer proves ownership -- a worker's background child orphaned to main is left
    ("V4R7-N1c", SUP, [("        return (pid == kpid and start == kstart) or sid == kpid\n",
                        "        return pid == kpid and start == kstart\n")],
     T_V5, {"V5_ONLY": "R7N2"}, "NOT ok [R7N2]"),
    # N1: the run supervisor's parent-death signal back to SIGKILL -- a gate's setsid daemon is orphaned past it when
    # its worker dies (first draft of this row ran the stop-matrix row KILL-supervisor-daemon and SURVIVED: main's
    # teardown usually still finds the dying run supervisor in the keeper's session and stops the daemon below it --
    # a race in the mutant's favour; [R7RUNPD] observes the run supervisor alone, deterministically)
    ("V4R7-N1d", SUP, [("    _prctl(PR_SET_PDEATHSIG, signal.SIGUSR2)\n", "    _prctl(PR_SET_PDEATHSIG, signal.SIGKILL)\n")],
     T_V5, {"V5_ONLY": "R7RUNPD"}, "NOT ok [R7RUNPD]"),
    # N1: the keeper's worker back in the keeper's process group -- a SIGKILL to the worker's group then kills keeper,
    # worker and run supervisor at once, and a gate's setsid daemon is orphaned to main, which cannot attribute it
    # (found by this round's own r2 run: KILL-worker-group-ownsess / -daemon left the daemon running; the SM row is a
    # race in the mutant's favour, so the deterministic oracle is [R7WGRP], the group structure + a group TERM)
    ("V4R7-N1f", SUP, [("        wpid = spawn(a.cmd, env, entry_mask, own_group=True)\n", "        wpid = spawn(a.cmd, env, entry_mask)\n")],
     T_V5, {"V5_ONLY": "R7WGRP"}, "NOT ok [R7WGRP]"),
    # N2: the final flush unguarded again. Round 9 RETIRED this row as "equivalent by construction" -- WRONG (round-3
    # review V4R10-2, a §11.4.6 overclaim): the argument "the buffers are always empty, the flush cannot raise" ignored
    # the case _flush's own docstring names -- a stream CLOSED when the interpreter started is None, and None.flush()
    # raises AttributeError (rc 1 + a traceback from _exit_main). It only "survived" because its oracle was [R7N2]
    # (stderr a broken pipe), which cannot observe it. RE-INSTATED (round 10), the same edit, routed to the oracle that
    # sees it: [R8MATRIX] ok x closed-out / closed-err / closed-both. The production code needs no change: _flush skips
    # a None stream and catches every exception class; the defect exists only in the mutant.
    ("V4R7-N2", SUP, [("    _flush()\n    os._exit(code)\n", "    sys.stdout.flush()\n    sys.stderr.flush()\n    os._exit(code)\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "closed-out closed-err closed-both", "R8_SCENARIOS": "ok"},
     "NOT ok [R8MATRIX] ok x closed-"),
    # N5 (CLASS 2): the documented-code funnel removed (BOTH layers -- main_exit_code and _exit_main each clamp; one
    # alone is a deliberate second layer, so a single-layer mutant is equivalent by design)
    ("V4R7-N5", SUP, [("    if code not in DOCUMENTED:\n", "    if False:\n"),
                      ("    if not isinstance(code, int) or code not in DOCUMENTED:\n", "    if not isinstance(code, int):\n")],
     T_V5, {"V5_ONLY": "R7TABLE"}, "NOT ok [R7TABLE] exited-undocumented-70"),
    # N3: the run-log ledger entry dropped before the report again / the keeper ignores the report state / the report
    # state is never read. Round 8 (V4R8-2) RE-EXPRESSED N3a/N3b/N3c against the durable report state (the `done`
    # marker and the worker's stop deferral are gone; same defect classes, same ids). V4R7-N3d (no deferral in the
    # worker) is RETIRED: the deferral was removed -- the keeper and main decide "report written" from the disk, so
    # the worker's own exit after a stop no longer decides anything (V4R8-2 rows R8N3TERMGRP/KILLW/KILLK guard it).
    ("V4R7-N3a", BR, [('  # rc 0: the run-log ledger entry is KEPT', '  rm -f "$_FC_LOG_LEDGER"\n  # rc 0: the run-log ledger entry is KEPT')],
     T_V5, {"V5_ONLY": "R7N3"}, "NOT ok [R7N3]"),
    # round 9 (V4R9-1): RE-EXPRESSED against the ONE derivation -- BOTH layers (keeper and main) ignore the report state
    # (a single layer is compensated by the other by design; the keeper-only layer is RVM-C below, observed by [R9SAME])
    ("V4R7-N3b", SUP, [("        code = decide_code(report_verified(statedir), cause)\n", "        code = decide_code(None, cause)\n"),
                       ("    code = main_exit_code(kst, Stop.sig, report_verified(statedir))\n", "    code = main_exit_code(kst, Stop.sig, None)\n")],
     T_V5, {"V5_ONLY": "R7N3B"}, "NOT ok [R7N3B]"),
    ("V4R7-N3c", SUP, [("    read_report(statedir)\n", "    pass\n")],
     T_V5, {"V5_ONLY": "R7N3B"}, "NOT ok [R7N3B]"),
    ("V4R7-N3e", SUP, [('            if os.path.isdir(d) and DONE.get("code") is None:\n', '            if os.path.isdir(d):\n')],
     T_V5, {"V5_ONLY": "R7N3C"}, "NOT ok [R7N3C]"),
    # N4: progress beats ignored by main / no beat while a bounded git call runs / the overall cap removed
    ("V4R7-N4a", SUP, [("                last_beat = time.monotonic()\n", "                pass\n")],
     T_V5, {"V5_ONLY": "R7N4"}, "NOT ok [R7N4]"),
    ("V4R7-N4b", SUP, [("                _beat()\n    except (OSError, subprocess.SubprocessError):\n", "                pass\n    except (OSError, subprocess.SubprocessError):\n")],
     T_V5, {"V5_ONLY": "R7N4"}, "NOT ok [R7N4]"),
    ("V4R7-N4c", SUP, [("            if time.monotonic() > min(due, hard_cap):\n", "            if time.monotonic() > due:\n")],
     T_V5, {"V5_ONLY": "R7N4CAP"}, "NOT ok [R7N4CAP]"),
    # N6: the early SIGINT handler removed / -S dropped from the main exec
    ("V4R7-N6a", SUP, [('if __name__ == "__main__" and signal.getsignal(signal.SIGINT) is not signal.SIG_IGN:\n    signal.signal(signal.SIGINT, _early_stop)\n', "")],
     T_V5, {"V5_ONLY": "R7N6"}, "NOT ok [R7N6] (a)"),
    ("V4R7-N6c", BR, [('  exec ${blk[@]+"${blk[@]}"} python3 -I -S "$_FC_SUPERVISOR" main', '  exec ${blk[@]+"${blk[@]}"} python3 -I "$_FC_SUPERVISOR" main')],
     T_V5, {"V5_ONLY": "R7N6"}, "NOT ok [R7N6] (c)"),
    # N6: no INT trap in front of the exec -- bash's wait-and-cooperative-exit drops an INT during a foreground child
    ("V4R7-N6e", BR, [("      trap 'exit 130' INT\n", "")],
     T_V5, {"V5_ONLY": "R7N6"}, "NOT ok [R7N6] (e)"),
    # N6: INT no longer blocked across the exec into the supervisor -- a start-up INT reaches the interpreter itself
    ("V4R7-N6d", BR, [('  env --block-signal=INT true >/dev/null 2>&1 && blk=(env --block-signal=INT)\n', '')],
     T_V5, {"V5_ONLY": "R7N6"}, "NOT ok [R7N6] (d)"),
    # ---- T048 V4 round 8 (independent review of the round-7 pack: NO-GO 4 IMPORTANT + 2 MINOR + 1 NIT) ----
    # V4R8-1 (CLASS 2, caller streams): _flush / say no longer survive a CLOSED stream (None) -- round 7's catch;
    # main no longer repairs closed fds 0/1/2; the script no longer ignores SIGPIPE
    ("V4R8-1a", SUP, [("        if stream is None:\n            continue\n        try:\n            stream.flush()\n        except Exception:  # noqa: BLE001\n            pass\n",
                       "        try:\n            stream.flush()\n        except (OSError, ValueError):\n            pass\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "closed-out", "R8_SCENARIOS": "ok"}, "NOT ok [R8MATRIX] ok x closed-out"),
    # round 9: RE-EXPRESSED (say no longer goes through the stream object -- V4R9-1 (b)): say writes through
    # sys.stderr again, so a dead stream RAISES out of say (round 7's class) -- the run role's code becomes 125
    ("V4R8-1b", SUP, [("    _write_bounded(2, data)\n", "    sys.stderr.write(data.decode())\n    sys.stderr.flush()\n")],
     T_V8, {"R8_ONLY": "R8RUN"}, "NOT ok [R8RUN] exit3-leftover x dead-both"),
    ("V4R8-1c", SUP, [("    _repair_std_fds()           # before anything is opened (V4R8-1)\n", "")],
     T_V8, {"R8_ONLY": "R8FDS"}, "NOT ok [R8FDS]"),
    # a standard fd open in the WRONG direction (bash leaves its script on fd 2 when the caller closed stderr) no
    # longer counts as closed -- found by the round-8 matrix's own control needle
    ("V4R8-1e", SUP, [("            if (mode != os.O_WRONLY) if fd == 0 else (mode != os.O_RDONLY):\n                continue\n",
                       "            continue\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "closed-err", "R8_SCENARIOS": "stop-INT-main"},
     "NOT ok [R8MATRIX] stop-INT-main x closed-err"),
    ("V4R8-1d", BR, [("trap '' PIPE\n", "")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "dead-err", "R8_SCENARIOS": "usage"}, "NOT ok [R8MATRIX] usage x dead-err"),
    # V4R8-2 (report written = durable state): the identity half (a stale identical report read as written) / the
    # body_hash half (any new file read as the report)
    ("V4R8-2a", SUP, [("    if now is None or now == pre:\n", "    if now is None:\n")],
     T_SUP, {}, "NOT ok [R1b]"),
    ("V4R8-2b", SUP, [('    if not isinstance(doc, dict) or doc.get("body_hash") != want:\n', "    if not isinstance(doc, dict):\n")],
     T_SUP, {}, "NOT ok [R1d]"),
    ("V4R8-2c", SUP, [("    if now is None or now == pre:\n", "    if now is None:\n")],
     T_V5, {"V5_ONLY": "R8N3STALE"}, "NOT ok [R8N3STALE]"),
    # V4R8-5: the reviewer's surviving mutants adopted VERBATIM
    ("V4R8-RVM02", SUP, [("    if Stop.sig:\n        return  # a second signal never shortens a stop already in progress (V4-N12 class)\n", "")],
     T_V5, {"V5_ONLY": "R8RVM02"}, "NOT ok [R8RVM02]"),
    ("V4R8-DOC128", SUP, [("DOCUMENTED = frozenset(range(0, 5)) | frozenset(range(129, 129 + 64))",
                           "DOCUMENTED = frozenset(range(0, 5)) | frozenset(range(128, 129 + 64))")],
     T_V5, {"V5_ONLY": "R7TABLE"}, "NOT ok [R7TABLE] exited-undocumented-128"),
    ("V4R8-USR2ANY", SUP, [("    if os.getppid() != Stop.run_parent:\n        Stop.parent_gone = True\n", "    Stop.parent_gone = True\n")],
     T_V5, {"V5_ONLY": "R8USR2"}, "NOT ok [R8USR2]"),
    # V4R8-6: the caller's pre-existing subtrees no longer pruned from main's ownership walk
    ("V4R8-6a", SUP, [("            if mine is None:\n                continue          # the caller's own pre-existing subtree: pruned (V4R8-6)\n", "")],
     T_SUP, {}, "NOT ok [P1]"),
    ("V4R8-6b", SUP, [("            return None          # the caller's own child: never owned, and its subtree is pruned (V4R8-6)\n",
                       "            return False\n")],
     T_SUP, {}, "NOT ok [P1]"),
    # ---- T048 V4 round 9 (round-2 review of the round-8 pack: NO-GO 1 IMPORTANT V4R9-1 + 5 MINOR + 1 NIT) ----
    # The round-2 reviewer's 14 mutants (v4_round2_review_20261012.md section 2), adopted: VERBATIM where their anchor
    # still exists (A B E F G I J K L M N), RE-EXPRESSED with the same defect class where round 9 replaced the code
    # they named (C D: the one derivation decide_code; H: the 5-field identity). Each must now DIE.
    ("V4R9-RVM-A", SUP, [("    now = _identity(out)\n", "    return code\n    now = _identity(out)\n")],
     T_SUP, {}, "NOT ok [R1]"),
    ("V4R9-RVM-B", SUP, [('doc.get("body_hash") != want', 'doc.get("body_hash", want) != want')],
     T_SUP, {}, "NOT ok [R9B]"),
    ("V4R9-RVM-C", SUP, [("        code = decide_code(report_verified(statedir), cause)\n", "        code = decide_code(None, cause)\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "worker", "R9_TAGS": "W2-after-writer", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] worker W2-after-writer x kill-self"),
    ("V4R9-RVM-D", SUP, [("    code = main_exit_code(kst, Stop.sig, report_verified(statedir))\n", "    code = main_exit_code(kst, Stop.sig, None)\n")],
     T_V5, {"V5_ONLY": "R8N3KILLK"}, "NOT ok [R8N3KILLK]"),
    ("V4R9-RVM-E", SUP, [("            if (mode != os.O_WRONLY) if fd == 0 else (mode != os.O_RDONLY):", "            if fd != 2 or mode != os.O_RDONLY:")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "wrongdir-in wrongdir-out", "R8_SCENARIOS": "stop-TERM-main"},
     "NOT ok [R8MATRIX] stop-TERM-main x wrongdir-"),
    ("V4R9-RVM-F", SUP, [("        _install_stop(entry_mask)\n        env = dict(os.environ)\n", "        _install_stop(entry_mask)\n        signal.signal(signal.SIGPIPE, signal.SIG_DFL)\n        env = dict(os.environ)\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "dead-err dead-both-ign", "R8_SCENARIOS": "kill-worker term-worker stop-TERM-main"},
     "NOT ok [R8MATRIX]"),
    ("V4R9-RVM-G", BR, [('  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-prepare', '  python3 "$FC/lib/fc_common.py" emit --schema "$schema" --body-json "$body_json" --run-meta-json "$run_meta" --out "$out_path"\n  if [ "$_FC_IS_WORKER" = 1 ]; then\n    python3 -I -S "$_FC_SUPERVISOR" report-prepare')],
     T_V5, {"V5_ONLY": "R8N3TERMGRP R8N3KILLW R8N3KILLK"}, "NOT ok [R8N3"),
    ("V4R9-RVM-H", SUP, [("    return [s.st_dev, s.st_ino, s.st_ctime_ns, s.st_mtime_ns, s.st_size]", "    return [s.st_dev, s.st_ino]")],
     T_SUP, {}, "NOT ok [R9ID-ctime]"),
    ("V4R9-RVM-I", SUP, [("        if (pid, start) in pre:", "        if any(p == pid for p, _ in pre):")],
     T_SUP, {}, "NOT ok [R9OWN-I]"),
    ("V4R9-RVM-J", SUP, [("        return (pid == kpid and start == kstart) or sid == kpid", "        return pid == kpid or sid == kpid")],
     T_SUP, {}, "NOT ok [R9OWN-J]"),
    ("V4R9-RVM-K", SUP, [("    ok = sf is not None and sf[1] == parent", "    ok = sf is not None")],
     T_SUP, {}, "NOT ok [S1]"),
    ("V4R9-RVM-L", SUP, [('if os.path.isdir(d) and DONE.get("code") is None:', 'if os.path.isdir(d):')],
     T_V5, {"V5_ONLY": "R7N3C"}, "NOT ok [R7N3C]"),
    ("V4R9-RVM-M", SUP, [("    except Exception:  # noqa: BLE001 -- the state of the caller's stream never changes an outcome", "    except ValueError:")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "dead-err", "R8_SCENARIOS": "kill-worker term-worker stop-TERM-main"},
     "NOT ok [R8MATRIX]"),
    ("V4R9-RVM-N", BR, [("trap '' PIPE\n", "[ \"${FC_BR_SUPERVISED:-}\" = 1 ] || trap '' PIPE\n")],
     T_V8, {"R8_ONLY": "R8SIGPIPE"}, "NOT ok [R8SIGPIPE]"),
    # round-9 fixer's own mutants (V4R9-M*): the state directory's lifetime, the one derivation, the bounded say, gc
    ("V4R9-M1", SUP, [("    code = main_exit_code(kst, Stop.sig, report_verified(statedir))\n", "    code = main_exit_code(kst, Stop.sig, report_verified(tmpdir))\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "keeper", "R9_TAGS": "_keeper.try", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] keeper"),
    ("V4R9-M2", SUP, [("    code = main_exit_code(kst, Stop.sig, report_verified(statedir))\n    remove_statedir(statedir)\n",
                       "    remove_statedir(statedir)\n    code = main_exit_code(kst, Stop.sig, report_verified(statedir))\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "keeper", "R9_TAGS": "_keeper.try", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] keeper"),
    ("V4R9-M3", SUP, [('        if cause[0] == "main_gone":\n            remove_statedir(statedir)\n', "        remove_statedir(statedir)\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "keeper", "R9_TAGS": "_keeper.finally", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] keeper"),
    ("V4R9-M4", SUP, [("    if verified is not None:\n        return verified\n    kind, n = cause\n",
                       "    kind, n = cause\n    if verified is not None and kind != \"killed\":\n        return verified\n")],
     T_SUP, {}, "NOT ok [R9DEC] decide_code(0, ('killed'"),
    ("V4R9-M5", SUP, [("    _write_bounded(2, data)\n", "    try:\n        os.write(2, data)\n    except OSError:\n        pass\n")],
     T_V9, {"R9_ONLY": "R9STALL"}, "NOT ok [R9STALL]"),
    ("V4R9-M6", SUP, [("    gc_statedirs(a.tmp_parent)   # state directories of DEAD mains", "    pass   # state directories of DEAD mains")],
     T_V9, {"R9_ONLY": "R9GC2"}, "NOT ok [R9GC2]"),
    ("V4R9-M7", SUP, [("                continue                       # its owner is alive: not ours to remove\n", "                pass\n")],
     T_SUP, {}, "NOT ok [R9GC] live owner kept"),
    ("V4R9-M8", SUP, [("    return [s.st_dev, s.st_ino, s.st_ctime_ns, s.st_mtime_ns, s.st_size]", "    return [s.st_dev, s.st_ino, s.st_ctime_ns, s.st_size]")],
     T_SUP, {}, "NOT ok [R9ID-mtime]"),
    ("V4R9-M9", SUP, [("    if sig:\n        return (\"stopped\", sig)\n    if kst is None:\n", "    if kst is None and sig:\n        return (\"stopped\", sig)\n    if kst is None:\n")],
     T_SUP, {}, "NOT ok [R9DEC] main_cause(9, 15)"),
    ("V4R9-M10", SUP, [("        if b == boot and pid > 1:\n", "        if pid > 1:\n")],
     T_SUP, {}, "NOT ok [R9GC] other boot removed"),
    ("V4R9-M11", SUP, [("    try:\n        os.rmdir(path)\n    except OSError:\n        pass\n    return not os.path.lexists(path)\n",
                        "    shutil.rmtree(path, ignore_errors=True)\n    return not os.path.lexists(path)\n")],
     T_SUP, {}, "NOT ok [R9GC] unknown file kept"),
    # ---- T048 V4 round 10 (round-3 review of the round-9 pack: NO-GO V4R10-1 + V4R10-2 IMPORTANT, 5 MINOR, 1 NIT) ----
    # The round-3 reviewer's 14 mutants RV3-01..RV3-14 (v4_round3_review_20261012.md section 2.2), adopted VERBATIM
    # (the reviewer's own anchors and replacements, each matched exactly once against this round's code). The 6 that
    # SURVIVED round 9 (RV3-02 03 09 10 11 13) are routed to the round-10 rows written for them; the 8 the reviewer saw
    # caught keep the oracle the reviewer used, narrowed to one row (the runner's 600 s bound). RV3-13b is the SAME edit
    # as RV3-13 (re-run by the reviewer against the full v4r5 file, where it also survived): one row covers both.
    ("V4R10-RV3-01", SUP, [("statedir = make_statedir(a.tmp_parent)", "statedir = make_statedir(tmpdir)")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "keeper", "R9_TAGS": "_keeper.try", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] keeper"),
    ("V4R10-RV3-02", SUP, [("            if ident is not None and ident[1] == start:\n", "            if ident is not None:\n")],
     T_SUP, {}, "NOT ok [R10GC-start]"),
    ("V4R10-RV3-03", SUP, [('return fh.read().strip().replace("-", "")[:12] or "noboot"', 'return "noboot"')],
     T_SUP, {}, "NOT ok [R10GC-boot]"),
    ("V4R10-RV3-04", SUP, [("        code = decide_code(report_verified(statedir), cause)\n", "        code = decide_code(None, cause)\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "worker", "R9_TAGS": "W2-after-writer", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] worker W2-after-writer x kill-self"),
    ("V4R10-RV3-05", SUP, [('    teardown(tmpdir, a.grace, reason, "main", statedir)\n', '    remove_statedir(statedir)\n    teardown(tmpdir, a.grace, reason, "main", statedir)\n')],
     T_V5, {"V5_ONLY": "R8N3KILLK"}, "NOT ok [R8N3KILLK]"),
    ("V4R10-RV3-06", SUP, [("    if now is None or now == pre:\n", "    if now is None:\n")],
     T_SUP, {}, "NOT ok [R1b]"),
    ("V4R10-RV3-07", SUP, [("SAY_BUDGET_S = 2.0 ", "SAY_BUDGET_S = 1e9 ")],
     T_V9, {"R9_ONLY": "R9STALL"}, "NOT ok [R9STALL]"),
    ("V4R10-RV3-08", SUP, [("    os.close(r)\n    os.close(hb_w)\n", "    os.close(r)\n    os.close(hb_w)\n    signal.signal(signal.SIGPIPE, signal.SIG_DFL)\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "dead-err", "R8_SCENARIOS": "kill-keeper"},
     "NOT ok [R8MATRIX] kill-keeper x dead-err"),
    # RV3-09 survived round 9 (V4R10-6): the fd-direction needle is now taken in EVERY role of EVERY supervised cell
    ("V4R10-RV3-09", SUP, [("def main():\n    _repair_std_fds()", 'def main():\n    if "replay-sample" not in " ".join(sys.argv): _repair_std_fds()')],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_SCENARIOS": "replay-sample", "R8_STREAMS": "closed-out closed-err closed-both closed-in wrongdir-in wrongdir-out wrongdir-err"},
     "NOT ok [R8MATRIX] replay-sample x"),
    # RV3-10 survived round 9 (V4R10-5): [R10ATOMIC] -- the marker must be the very inode written under its temp name
    ("V4R10-RV3-10", SUP, [("        os.replace(tmp, os.path.join(tmpdir, REPORT_MARKER))\n", "        shutil.copyfile(tmp, os.path.join(tmpdir, REPORT_MARKER)); os.unlink(tmp)\n")],
     T_SUP, {}, "NOT ok [R10ATOMIC]"),
    ("V4R10-RV3-11", SUP, [('    if not isinstance(doc, dict) or doc.get("body_hash") != want:\n', '    if not isinstance(doc, dict) or doc.get("body_hash") not in (want, ""):\n')],
     T_SUP, {}, "NOT ok [R10HASH]"),
    ("V4R10-RV3-12", SUP, [("    _flush()\n    os._exit(code)\n", "    sys.stdout.flush()\n    sys.stderr.flush()\n    os._exit(code)\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "closed-out closed-err closed-both dead-out-closed-err", "R8_SCENARIOS": "ok"},
     "NOT ok [R8MATRIX] ok x closed-"),
    # RV3-13 (= RV3-13b) survived round 9 (V4R10-4): [R10DROP] -- main raises after reaping its keeper
    ("V4R10-RV3-13", SUP, [('    STATE["main_owns"] = True    # the keeper is gone', '    STATE["main_owns"] = False    # the keeper is gone')],
     T_V9, {"R9_ONLY": "R10DROP"}, "NOT ok [R10DROP]"),
    ("V4R10-RV3-14", SUP, [('        if cause[0] == "main_gone":\n            remove_statedir(statedir)\n', "        if False:\n            remove_statedir(statedir)\n")],
     T_R2, SM("KILL", "main", "quick"), "NOT ok [SM] KILL-main-quick"),
    # round-10 fixer's own mutants (V4R10-M*): the LEASE (V4R10-1), the keeper's late main-gone removal, the exit funnel
    ("V4R10-M1", SUP, [("        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)\n    except OSError:\n        os.close(lease)\n        remove_statedir(path)\n",
                        "        pass\n    except OSError:\n        os.close(lease)\n        remove_statedir(path)\n")],
     T_V9, {"R9_ONLY": "R10LEASE"}, "NOT ok [R10LEASE]"),
    ("V4R10-M2", SUP, [("        free, lfd = _lease_free(path)\n", "        free, lfd = True, None\n")],
     T_V9, {"R9_ONLY": "R10LEASE"}, "NOT ok [R10LEASE]"),
    ("V4R10-M3", SUP, [("        except FileNotFoundError:\n            return True, None\n        except OSError:\n            return False, None\n",
                        "        except FileNotFoundError:\n            return True, None\n        except OSError:\n            return True, None\n")],
     T_SUP, {}, "NOT ok [R10LEASE-odd]"),
    ("V4R10-M4", SUP, [("        except FileNotFoundError:\n            return True, None\n", "        except FileNotFoundError:\n            return False, None\n")],
     T_SUP, {}, "NOT ok [R10LEASE-none]"),
    ("V4R10-M5", SUP, [('        if cause[0] != "main_gone" and _main_gone_now(r):\n', "        if False:\n")],
     T_V9, {"R9_ONLY": "R10LEASE"}, "NOT ok [R10LEASE]"),
    ("V4R10-M6", SUP, [('        return bool(ready) and os.read(r, 1) == b""\n', "        return not ready\n")],
     T_V9, {"R9_ONLY": "R9WIN", "R9_ROLES": "keeper", "R9_TAGS": "_keeper.finally", "R9_ACTIONS": "kill-self"},
     "NOT ok [R9WIN] keeper"),
    ("V4R10-M7", SUP, [('        if n in (REPORT_MARKER, LEASE_NAME) or n.startswith(".report."):', '        if n == REPORT_MARKER or n.startswith(".report."):')],
     T_SUP, {}, "NOT ok [R10LEASE-free]"),
    ("V4R10-M8", SUP, [("        if b == boot and pid > 1:\n", "        if False:\n")],
     T_SUP, {}, "NOT ok [R9GC] live owner kept"),
    ("V4R10-M9", SUP, [("    for fd in (0, 1, 2):\n        try:\n            mode = fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE\n",
                        "    for fd in (1, 2):\n        try:\n            mode = fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE\n")],
     T_V8, {"R8_ONLY": "R8MATRIX", "R8_STREAMS": "closed-in", "R8_SCENARIOS": "selfcheck"},
     "NOT ok [R8MATRIX] selfcheck x closed-in"),
    ("V4R10-M10", SUP, [('    if STATE["main_owns"]:\n        remove_statedir(STATE["dir"])\n', '    if False:\n        remove_statedir(STATE["dir"])\n')],
     T_V9, {"R9_ONLY": "R10DROP"}, "NOT ok [R10DROP]"),
    ("V4R10-M11", SUP, [("        except OSError:              # BlockingIOError: a live holder; anything else: not provably free\n            os.close(lfd)\n            return False, None\n",
                         "        except OSError:              # BlockingIOError: a live holder; anything else: not provably free\n            os.close(lfd)\n            return True, None\n")],
     T_SUP, {}, "NOT ok [R10LEASE-held]"),
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
            # one control for the whole unit file (rc == 0 requires every [Z*]/[S*]/[G1] case, so a separate
            # round-4 control would check nothing distinct); the new RA* rows each name their own case
            ("control-sup-unit", T_SUP, {}, "ok [Z1]"),
            # round 5: the whole v4r5 file (rc == 0 requires every case), the four new stop-matrix rows, the
            # new collect_baseline cases (the bdq control above already requires the malformed-* checks)
            ("control-v5", T_V5, {}, "ok [F1RUN]"),
            ("control-sm-v5", T_R2, {"R2_ONLY": "SM", "SM_SIGNALS": "TERM", "SM_TARGETS": "main", "SM_SHAPES": "",
                                     "SM_EXTRA": "sigchld wtaddkill nochildren runsig"}, "ok [SM] sigchld-caller-quick"),
            ("control-cb-v5", T_CB, {"CB_ONLY": "C-FRESHJ C-ONDATE"}, "ok [C-FRESHJ]"),
            # round 6: the new stop-matrix rows (the v5 control above already requires every new v5 case)
            ("control-sm-v6", T_R2, {"R2_ONLY": "SM", "SM_SIGNALS": "INT", "SM_TARGETS": "main", "SM_SHAPES": "",
                                     "SM_EXTRA": "termign runkill"}, "ok [SM] runkill-KILL-fcrun-daemon"),
            # round 7: the stop-matrix row V4R7-N1f runs, and the re-expressed wtaddkill row
            ("control-sm-v7", T_R2, {"R2_ONLY": "SM", "SM_SIGNALS": "KILL", "SM_TARGETS": "worker-group",
                                     "SM_SHAPES": "daemon", "SM_EXTRA": "wtaddkill"}, "ok [SM] KILL-worker-group-daemon"),
            # round 8: the stream-matrix rows the V4R8-1 mutants run (one file, every row they name)
            ("control-v8", T_V8, {"R8_ONLY": "R8MATRIX R8RUN R8FDS", "R8_STREAMS": "closed-out dead-err closed-err",
                                  "R8_SCENARIOS": "ok usage stop-INT-main"}, "ok [R8FDS]"),
            # round 9: every row a V4R9-* mutant runs, on the UNMUTATED replica
            ("control-v8-r9", T_V8, {"R8_ONLY": "R8MATRIX R8RUN R8SIGPIPE",
                                     "R8_STREAMS": "wrongdir-in wrongdir-out dead-err dead-both dead-both-ign",
                                     "R8_SCENARIOS": "stop-TERM-main kill-worker term-worker"}, "ok [R8SIGPIPE]"),
            ("control-v9", T_V9, {"R9_ONLY": "R9WIN R9GC2 R9STALL", "R9_ROLES": "keeper worker",
                                  "R9_TAGS": "_keeper.try _keeper.finally W2-after-writer", "R9_ACTIONS": "kill-self"},
                                  "ok [R9STALL]"),
            # round 10: every row a V4R10-* mutant runs, on the UNMUTATED replica
            ("control-v9-r10", T_V9, {"R9_ONLY": "R10LEASE R10DROP"}, "ok [R10LEASE]"),
            ("control-v8-r10", T_V8, {"R8_ONLY": "R8MATRIX",
                                      "R8_STREAMS": "closed-out closed-err closed-both closed-in wrongdir-in wrongdir-out "
                                                    "wrongdir-err dead-out-closed-err dead-err",
                                      "R8_SCENARIOS": "ok replay-sample selfcheck kill-keeper"},
             "ok [R8MATRIX] selfcheck x closed-in")]


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
