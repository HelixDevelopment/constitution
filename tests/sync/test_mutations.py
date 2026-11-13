#!/usr/bin/env python3
"""tests/sync/test_mutations.py -- §1.1 paired-mutation suite for scripts/sync/sync_all_upstreams.py.

Each mutant is ONE textual change of the engine (its anchor must occur exactly once, otherwise the harness
fails: a mutant that silently does not apply would be counted as killed). The mutated engine + wrapper are
copied to <scratch>/<id>/scripts/sync/; the mutant's suites then run IN ORDER, stopping at the first that exits
non-zero: "gate" (scripts/gates/cm_sync_upstreams_ff_only.sh --root <scratch>/<id>), "unit" (test_unit.py with
SYNC_ENGINE_PY) or a shell suite tests/sync/test_<name>.sh (SX_ENGINE = the mutated wrapper). KILLED = a suite
exited non-zero. A SURVIVOR makes this file exit 1, unless the mutant is listed in EQUIVALENT with its proof.
The table holds M01-M73 (the fixers' own mutants), K01-K17 and R1-R6 (the round-2 reviewer's mutants), M37b,
X01-X07 and X02b (the round-3 reviewer's mutants, verbatim) and N01-N25 (the round-4 fixer's own mutants); anchors
are kept on the round-4 text. X04, N22 and N23 change the process-group guard and therefore only ever run the static
gate and the unit suite (whose KillGroup tests replace the engine's ``os`` with a recorder; section 11.4.263).

Usage: python3 -I tests/sync/test_mutations.py [--only M07,K12] [--gate-only | --no-gate] [--list]
  --gate-only  every mutant runs ONLY the static gate (what the gate alone kills)
  --no-gate    every mutant runs its suites WITHOUT the gate (what the behavioural suites alone kill)
Exit 0 all killed or equivalent, 1 a survivor / harness error, 2 usage.
Runs suites sequentially at the caller's priority (run it under `nice -n 10`); scratch under $TMPDIR.
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ENGINE = os.path.join(REPO, "scripts", "sync", "sync_all_upstreams.py")
WRAPPER = os.path.join(REPO, "scripts", "sync", "sync_all_upstreams.sh")

# (id, what it breaks, old, new, suite run when the unit suite does not kill it)
MUTANTS = [
    ('M01', '+refspec allowed',
     'if a.startswith("+"):',
     'if False:', ['unit', 'integration']),
    ('M02', 'transport helper :: allowed',
     'if "::" in a:',
     'if False:', ['unit', 'integration']),
    ('M03', 'push on the write allow-list',
     'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add"}',
     'WRITE_SUBCOMMANDS = {"fetch", "merge", "checkout", "add", "push"}', ['unit', 'integration']),
    ('M04', 'merge shape not enforced',
     'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):',
     'if False:', ['unit', 'integration']),
    ('M05', 'checkout shape not enforced',
     'if len(rest) != 3 or rest[0] != "--quiet" or rest[1] != "--detach" or not SHA_RE.match(rest[2]):',
     'if False:', ['unit', 'integration']),
    ('M06', 'add path not checked',
     'if len(rest) != 2 or rest[0] != "--" or not safe_relpath(rest[1]):',
     'if False:', ['unit', 'integration']),
    ('M07', 'fetch shape not enforced',
     'if list(args) not in (fetch_args(remote, False), fetch_args(remote, True)):',
     'if False:', ['unit', 'integration']),
    ('M08', 'URL userinfo not redacted',
     '        pos = at + 1\n',
     '        pos = start\n', ['unit', 'security']),
    ('M09', 'tokens not redacted',
     'return _TOKENS.sub("[REDACTED]", _AUTH.sub(r"\\1[REDACTED]", strip_userinfo(text)))',
     'return _AUTH.sub(r"\\1[REDACTED]", strip_userinfo(text))', ['unit', 'security']),
    ('M10', 'git may prompt',
     'env["GIT_TERMINAL_PROMPT"] = "0"',
     'env["GIT_TERMINAL_PROMPT"] = "1"', ['unit', 'security']),
    ('M11', 'ambient GIT_DIR kept',
     '(k in _SCRUB or ',
     '(k in () or ', ['unit', 'security']),
    ('M12', 'jobs ceiling 64',
     'ceiling = max(1, min(8, (cpus or 1) // 2))',
     'ceiling = max(1, min(64, (cpus or 1) // 2))', ['unit', 'perf']),
    ('M13', 'behind classified as ahead',
     'if ahead == 0:\n        return "behind"',
     'if ahead == 0:\n        return "ahead"', ['unit', 'integration']),
    ('M14', 'newest = first, not the linear maximum',
     'if all(o == c or ancestor(o, c) for o in uniq):',
     'if True:', ['unit', 'integration']),
    ('M15', 'MERGE_HEAD not detected',
     'for n in ("MERGE_HEAD", ',
     'for n in (', ['unit', 'integration']),
    ('M16', 'dirty tree not detected',
     'rec["dirty"] = (not st.answered) or bool(st.out.strip())',
     'rec["dirty"] = False', ['unit', 'integration']),
    ('M17', 'dirty tree does not block integration',
     'BLOCKING_PREFIXES = ("dirty-tree", "in-progress",',
     'BLOCKING_PREFIXES = ("in-progress",', ['unit', 'integration']),
    ('M18', 'fast-forward without consent',
     'if rec.get("local_vs_target") == "behind" and consent.get("integrate"):',
     'if rec.get("local_vs_target") == "behind":', ['unit', 'ui']),
    ('M19', 'dry-run fetches',
     'mode in ("check", "apply") and not a.no_fetch',
     'mode in ("check", "apply", "dry-run") and not a.no_fetch', ['unit', 'integration']),
    ('M20', '--no-fetch ignored',
     '"fetch": mode in ("check", "apply") and not a.no_fetch,',
     '"fetch": mode in ("check", "apply"),', ['unit', 'integration']),
    ('M21', 'third-party pins advanced without the flag',
     '\n                    and (rec.get("own_org") or advance_third_party))',
     ')', ['unit', 'integration']),
    ('M22', 'children never follow',
     '    tree = head_gitlinks(r, repo.abspath)',
     '    tree = {}', ['unit', 'integration']),
    ('M23', 'pin not on main not reported',
     '        elif not [x for x in refs if x in mains]:\n            pin["state"] = "not-on-main"',
     '        elif False:\n            pin["state"] = "not-on-main"', ['unit', 'integration']),
    ('M24', 'unfetchable pin reported at-main',
     'pin["state"] = "unfetchable"',
     'pin["state"] = "at-main"', ['unit', 'integration']),
    ('M25', 'timestamp enters the canonical hash',
     'VOLATILE = {"started", ',
     'VOLATILE = {', ['unit', 'determinism']),
    ('M26', '--out inside the work tree allowed',
     'if out_dir == root or out_dir.startswith(root + os.sep):',
     'if False:', ['unit', 'integration']),
    ('M27', 'lock per process (no mutual exclusion)',
     '"helix-sync-upstreams.lock")',
     '"helix-sync-upstreams.lock.%d" % os.getpid())', ['unit', 'chaos']),
    ('M28', 'behind reported as exit 0',
     'elif any_behind:',
     'elif False:', ['unit', 'integration']),
    ('M29', 'third-party pin behind counts as an update',
     'if pin.get("state") == "behind-main" and rec.get("own_org"):',
     'if pin.get("state") == "behind-main":', ['unit', 'integration']),
    ('M30', 'root not on main not reported',
     'reasons.append("root-not-on-" + branch)',
     'pass', ['unit', 'integration']),
    ('M31', 'control needle always fails',
     'ok = bool(n and',
     'ok = False and bool(n and', ['unit', 'integration']),
    # M32's anchor is the engine's signal call; it is written as two adjacent literals because CM-KILLPG-PGID-GUARD
    # reads a string holding the whole call as an unguarded call and still reports it on this line after printing
    # its audited allow marker as ALLOWED (measured 2026-11-13; the same text failed the gate at the base commit). The value is
    # the same string; the engine's own call stays guarded (pgid > 1).
    ('M32', 'timeout does not kill the process group', 'os.kill' 'pg(pgid, signal.SIGKILL)', 'pass', ['unit', 'chaos']),
    ('M33', 'failed fetch not reported unreachable',
     'if rem.get("fetch") in ("failed", "timeout", "no-answer"):',
     'if False:', ['unit', 'chaos']),
    ('M34', 'Enter means yes',
     'in ("y", "yes")',
     'in ("y", "yes", "")', ['unit', 'ui']),
    ('M35', 'dirty child followed',
     'if c.rec.get("head_before") != old or c.rec.get("dirty") or c.rec.get("in_progress"):',
     'if c.rec.get("head_before") != old:', ['unit', 'integration']),
    ('M36', 'follow only under the fast-forward consent (pin consent ignored)',
     'if not (consent.get("integrate") or consent.get("pins")):',
     'if not consent.get("integrate"):', ['unit', 'ui']),
    ('M37', 'follow consent guard removed',
     '        if not (consent.get("integrate") or consent.get("pins")):\n            continue\n',
     '', ['unit', 'ui']),
    ('M38', 'R1: merge --ff accepted',
     'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):',
     'if len(rest) != 2 or rest[0] not in ("--ff-only", "--ff") or not SHA_RE.match(rest[1]):', ['unit', 'integration']),
    ('M39', 'R3: follow detaches a submodule on a branch',
     '        if c.rec.get("branch"):\n            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:submodule-on-branch"})',
     '        if False:\n            c.rec.setdefault("actions", []).append({"op": "none", "why": "follow-skipped:submodule-on-branch"})', ['unit', 'integration']),
    ('M40', 'R4: control characters not stripped',
     '    return _CTRL.sub("?", strip_secrets(str(text)))',
     '    return strip_secrets(str(text))', ['unit', 'security']),
    ('M41', 'R5: untracked files do not make a tree dirty',
     '"--untracked-files=normal"]',
     '"--untracked-files=no"]', ['unit', 'integration']),
    ('M42', 'R6: an unreachable remote does not block',
     '"local-", "unreachable", "invalid-remote",',
     '"local-", "invalid-remote",', ['unit', 'chaos']),
    ('M43', 'F1: fetch prunes',
     '"fetch", "--no-prune", "--no-prune-tags"',
     '"fetch", "--prune", "--no-prune-tags"', ['unit', 'security']),
    ('M44', 'F1: configured refspecs apply (no --refmap=)',
     '"--refmap=", "--", remote',
     '"--", remote', ['unit', 'security']),
    ('M45', 'F1: tags forced',
     'a.append("refs/tags/*:refs/tags/*")',
     'a.append("+refs/tags/*:refs/tags/*")', ['unit', 'security']),
    ('M46', 'F2: repository hooks run',
     '"core.hooksPath=/dev/null", ',
     '', ['unit', 'security']),
    ('M47', 'F2: fsmonitor runs',
     '"core.fsmonitor=false", ',
     '', ['unit', 'security']),
    ('M48', 'F3: a local timeout is not recorded',
     '        if not (network and why == "timeout"):',
     '        if not (network or why == "timeout"):', ['unit', 'chaos']),
    ('M49', 'F3: unresolved never classified',
     '        elif unresolved:\n            rec["result"] = "unresolved"',
     '        elif False:\n            rec["result"] = "unresolved"', ['unit', 'chaos']),
    ('M50', 'F3: an unreadable HEAD is not flagged (reads as current)',
     '    if rec["head_before"] is None:\n        rec["head_unreadable"] = True\n',
     '', ['unit', 'chaos']),
    ('M51', 'F4: ignored files never checked',
     '    if hits == []:\n        return "clear"',
     '    if True:\n        return "clear"', ['unit', 'security']),
    ('M52', 'F7: a topic root does not block its pins',
     '"root-not-on-", "head-unreadable", "tag-rejected"',
     '"head-unreadable", "tag-rejected"', ['unit', 'integration']),
    ('M53', 'F8: the stderr pipe of an escaped grandchild is waited for',
     '            p.communicate(timeout=2)',
     '            p.communicate()', ['unit', 'chaos']),
    ('M54', 'F9: core.sshCommand ignored',
     'repo_ssh=repo.rec.get("ssh") == "core.sshCommand")',
     'repo_ssh=False)', ['unit', 'security']),
    ('M55', 'F11: a modified parent gitlink is not reported',
     '                    repo.parent.rec.setdefault("gitlink_modified", []).append(rec["path_in_parent"])',
     '                    pass', ['unit', 'integration']),
    ('M56', 'F13: refs/remotes/<r>/feature/main counts as main',
     '        elif not [x for x in refs if x in mains]:',
     '        elif not [x for x in refs if x.endswith("/" + branch)]:', ['unit', 'integration']),
    ('M57', 'an upstream branch deleted upstream is not reported',
     'rem["stale_tracking_ref"] = bool(sha)',
     'rem["stale_tracking_ref"] = False', ['unit', 'integration']),
    ('M58', 'N3: a held lock exits 2 (= usage)',
     '        return EXIT_LOCKED',
     '        return 2', ['unit', 'chaos']),
    ('M59', 'F3: moved computed with an unknown head',
     'and rec.get("head_before") is not None and rec.get("head_after") != rec.get("head_before"))',
     'and rec.get("head_after") != rec.get("head_before"))', ['unit', 'chaos', 'faults']),
    ('M60', 'F3: an unreadable HEAD does not block integration',
     '"root-not-on-", "head-unreadable", "tag-rejected"',
     '"root-not-on-", "tag-rejected"', ['unit', 'chaos']),
    ('M61', 'I-1: the guarded writer writes a repository with an earlier no-answer',
     '    if r.unresolved_for(p):\n        rec["actions"].append({"op": "none", "why": "unresolved:earlier-no-answer", "for": op})\n        return "no-answer"\n',
     '', ['unit', 'faults']),
    ('M62', 'I-1: a signal-killed git reads as an answer',
     '    if rc < 0:\n        return "signal", -rc, o, e\n',
     '', ['unit', 'chaos']),
    ('M63', 'I-1: any exit status is an answer (declared ok ignored)',
     '        if kind == "exit" and code in ok:',
     '        if kind == "exit":', ['unit', 'chaos']),
    ('M64', 'I-1: a malformed rc-0 output reads as an answer (n-5)',
     '            if code == 0 and want is not None and not want.match(out.strip()):',
     '            if False:', ['unit', 'chaos']),
    ('M65', 'I-3: the status re-read before a write is skipped (K11 class)',
     '    st = r.run(p, STATUS_ARGS, ok=(0,))\n    if not st.answered:\n        rec["actions"].append({"op": "none", "why": "unresolved:status-recheck", "for": op})\n        return "no-answer"\n    busy',
     '    st = r.run(p, STATUS_ARGS, ok=(0,))\n    busy', ['unit', 'hardening']),
    ('M66', 'I-3: a tree changed before the write is written anyway',
     '    if st.out.strip() or busy:',
     '    if busy:', ['unit', 'hardening']),
    ('M67', 'I-3: the parent index is not re-checked before staging a pin',
     '        if links.get(rec["path_in_parent"]) != rec.get("recorded_gitlink"):',
     '        if False:', ['unit', 'hardening', 'integration']),
    ('M73', 'I-1: a failure judged on a no-answer reads as FAILED, not BLIND',
     '        if blind:  # before "failed"',
     '        if blind and not rec.get("failed"):  # before "failed"', ['unit', 'faults']),
    ('M37b', 'follow after a parent that did not move in this run',
     '        if moved:  # only a parent',
     '        if True:  # only a parent', ['unit', 'hardening', 'integration']),
    ('M68', 'm-4: a moved upstream tag is not labelled tag-rejected',
     '        return "tag-rejected"',
     '        return "other"', ['unit', 'hardening']),
    ('M69', 'm-2: no upstream main reads as current',
     '        reasons.append("no-upstream-" + branch)',
     '        pass', ['unit', 'hardening']),
    ('M70', 'n-3: any existing --out file is overwritten',
     '    if (st.st_mode & 0o170000) != 0o100000:  # not a regular file',
     '    if False:  # not a regular file', ['unit', 'hardening']),
    ('M71', "S-1: the report backstop keeps raw '_' fields",
     '            if k.startswith("_"):\n                continue\n',
     '', ['unit', 'security', 'hardening']),
    ('M72', 'BLIND: a non-time no-answer is reported as INCONCLUSIVE',
     '        blind = [u for u in unresolved if u.split(":", 1)[1] not in TIME_WHYS]',
     '        blind = []', ['unit', 'chaos']),
    ('K01', 'gate-evading spawn: Popen bound to an alias, then called',
     'def now_utc():',
     'def _k01():\n    _sp = subprocess.Popen\n    return _sp(["true"]).wait()\n\n\ndef now_utc():', ['gate', 'unit', 'security']),
    ('K02', 'gate-evading spawn: Popen passed as a callable to map()',
     'def now_utc():',
     'def _k02():\n    return list(map(subprocess.Popen, [["true"]]))\n\n\ndef now_utc():', ['gate', 'unit', 'security']),
    ('K03', 'killpg through an alias, no pgid>1 guard, outside the signal point',
     'def now_utc():',
     'def _k03(p):\n    _k = os.killpg\n    _k(os.getpgid(p.pid), signal.SIGKILL)\n\n\ndef now_utc():', ['gate', 'unit', 'chaos']),
    ('K04', 'core.hooksPath=/dev/null dropped for merge/checkout only',
     '    for kv in SAFE_CONFIG:\n        cmd += ["-c", kv]',
     '    for kv in SAFE_CONFIG:\n        if args and args[0] in ("merge", "checkout") and kv.startswith("core.hooksPath"):\n            continue\n        cmd += ["-c", kv]', ['gate', 'unit', 'security', 'integration']),
    ('K05', 'credentials: remote URL written unredacted (the backstop must report it)',
     '"url": redact_url(url), "_url": url,',
     '"url": url, "_url": url,', ['gate', 'unit', 'security', 'hardening']),  # the backstop check is in hardening (round 3)
    ('K06', 'data overwrite: ignored-file guard skipped on the follow path',
     '    guard = clobber_guard(r, repo, target)',
     '    guard = "clear" if op == "follow-pin" else clobber_guard(r, repo, target)', ['gate', 'unit', 'security', 'hardening', 'integration', 'chaos']),
    ('K07', 'data overwrite: ignored-file guard skipped on the advance-pin path',
     '    guard = clobber_guard(r, repo, target)',
     '    guard = "clear" if op == "advance-pin" else clobber_guard(r, repo, target)', ['gate', 'unit', 'security', 'hardening', 'integration', 'chaos']),
    ('K07b', 'data overwrite: ignored-file guard skipped on the fast-forward path',
     '    guard = clobber_guard(r, repo, target)',
     '    guard = "clear" if op == "fast-forward" else clobber_guard(r, repo, target)', ['gate', 'unit', 'security', 'hardening', 'integration', 'chaos']),
    ('K08', 'fetch shape: forced refspec into refs/heads/*',
     '"+refs/heads/*:refs/remotes/%s/*" % remote]',
     '"+refs/heads/*:refs/heads/*"]', ['gate', 'unit', 'security']),
    ('K09', 'fetch shape: check_git_args accepts any fetch',
     '        if list(args) not in (fetch_args(remote, False), fetch_args(remote, True)):',
     '        if False:', ['gate', 'unit', 'security']),
    ('K10', "empty rc-0 read equivalence: a failed read returns ''",
     '        return self.out.strip() if self.answered and self.rc == 0 else None',
     '        return self.out.strip() if self.answered and self.rc == 0 else ""', ['gate', 'unit', 'integration', 'chaos', 'security']),
    ('K11', 'a failing status call reads as a clean tree',
     'rec["dirty"] = (not st.answered) or bool(st.out.strip())',
     'rec["dirty"] = bool(st.out.strip())', ['gate', 'unit', 'integration', 'chaos', 'hardening']),
    ('K12', 'credentials: fetch_error written unredacted',
     '            lines = [l for l in redact(res.err).splitlines() if l.strip()]',
     '            lines = [l for l in res.err.splitlines() if l.strip()]', ['gate', 'unit', 'security', 'chaos', 'hardening']),
    ('K13', 'credentials: GitLab token shape no longer redacted',
     '(gh[pousr]_|github_pat_|glpat-|',
     '(gh[pousr]_|github_pat_|', ['gate', 'unit', 'security']),
    ('K14', '--no-optional-locks dropped',
     '    return cmd + ["--no-optional-locks"] + list(args)',
     '    return cmd + list(args)', ['gate', 'unit', 'security', 'determinism', 'integration']),
    ('K15', 'diff-driver path: a git diff call added after a fast-forward',
     '                if repo.parent is not None:  # F11',
     '                r.run(p, ["diff", "--stat", "HEAD@{1}", "HEAD"], ok=(0,))\n                if repo.parent is not None:  # F11', ['gate', 'unit', 'integration']),
    ('K16', 'ambient GIT_CONFIG_PARAMETERS no longer scrubbed',
     '"SSH_ASKPASS", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",',
     '"SSH_ASKPASS", "GIT_CONFIG_COUNT",', ['gate', 'unit', 'security', 'hardening']),
    ('K17', 'per-call limit ignores the run deadline',
     '        limit = min(self.timeout if network else max(self.timeout, 60), left)',
     '        limit = self.timeout if network else max(self.timeout, 60)', ['gate', 'unit', 'chaos']),
    ('R1', 'merge --ff accepted',
     'if len(rest) != 2 or rest[0] != "--ff-only" or not SHA_RE.match(rest[1]):',
     'if len(rest) != 2 or rest[0] not in ("--ff-only", "--ff") or not SHA_RE.match(rest[1]):', ['gate', 'unit', 'integration']),
    ('R2', 'getattr spawn',
     'def now_utc():',
     'def _hidden():\n    getattr(subprocess, "call")(["true"])\n\n\ndef now_utc():', ['gate', 'unit', 'security']),
    ('R3', 'follow detaches a submodule on a branch',
     '        if c.rec.get("branch"):\n            c.rec.setdefault',
     '        if False:\n            c.rec.setdefault', ['gate', 'unit', 'integration']),
    ('R4', 'control characters not stripped',
     '    return _CTRL.sub("?", strip_secrets(str(text)))',
     '    return strip_secrets(str(text))', ['gate', 'unit', 'security']),
    ('R5', 'untracked files do not make a tree dirty',
     '"--untracked-files=normal"]',
     '"--untracked-files=no"]', ['gate', 'unit', 'integration', 'security']),
    ('R6', 'an unreachable remote does not block',
     '"local-", "unreachable", "invalid-remote",',
     '"local-", "invalid-remote",', ['gate', 'unit', 'chaos', 'integration']),
    # ── review round 3: the reviewer's mutants, adopted verbatim (X04 only ever runs the static gate and the unit
    #    suite, whose KillGroup tests replace the engine's ``os`` with a recorder: its guard could signal pgid <= 1)
    ('X01', 'writer status re-read accepts rc 128 as a clean answer (ok-set widened at a write guard)',
     '    st = r.run(p, STATUS_ARGS, ok=(0,))\n    if not st.answered:\n        rec["actions"].append({"op": "none", "why": "unresolved:status-recheck"',
     '    st = r.run(p, STATUS_ARGS, ok=(0, 128))\n    if not st.answered:\n        rec["actions"].append({"op": "none", "why": "unresolved:status-recheck"', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X02', 'fast-forward bypasses the one guarded writer (direct merge call site in integrate)',
     '                res = write_git(r, repo, "fast-forward", rec["target"])',
     '                res = "done" if r.run(p, ["merge", "--ff-only", rec["target"]], ok=(0,)).rc == 0 else "failed"', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X03', 'a second spawn site (git --version precheck) inside proc_run_git',
     '    checked = check_git_args(args)\n',
     '    checked = check_git_args(args)\n    subprocess.Popen([git_bin, "--version"], stdout=subprocess.DEVNULL).wait()\n', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X04', 'tautological pgid guard: (pgid > 1 or True), pgid == p.pid dropped',
     '    if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:',
     '    if isinstance(pgid, int) and (pgid > 1 or True):', ['gate', 'unit']),
    ('X05', 'userinfo cut looks only 48 chars past scheme:// (long password leaks)',
     '        at = text.rfind("@", start, end)',
     '        at = text.rfind("@", start, min(end, start + 48))', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X06', "a call site whose 'declared' ok set is every status 0..255 (ls-files -s, index gitlinks)",
     '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0,))',
     '    res = r.run(repo, ["ls-files", "-s", "-z"], ok=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255))', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X07', 'SAFE_CONFIG: a trailing core.hooksPath pair overrides /dev/null (presence-only argv check)',
     '"fetch.prune=false", "fetch.pruneTags=false", "fetch.recurseSubmodules=false")',
     '"fetch.prune=false", "fetch.pruneTags=false", "fetch.recurseSubmodules=false", "core.hooksPath=.githooks")', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    ('X02b', 'fast-forward bypasses write_git but still records the action (guards skipped, record intact)',
     '                res = write_git(r, repo, "fast-forward", rec["target"])',
     '                _x = r.run(p, ["merge", "--ff-only", rec["target"]], ok=(0, 1, 128)); rec["actions"].append({"op": "fast-forward", "to": rec["target"], "rc": _x.rc, "error": ""}); res = "done" if (_x.answered and _x.rc == 0) else "failed"', ['gate', 'unit', 'integration', 'e2e', 'security', 'hardening', 'faults', 'chaos', 'determinism', 'ui', 'perf', 'full_automation']),
    # ── review round 4: the fixer's own mutants, one per guarded behaviour of the round-4 fixes
    ('N01', 'F1/B: a path lstat cannot read is "absent"',
     '    except OSError:\n        return "unreadable"\n    return "dir" if',
     '    except OSError:\n        return "absent"\n    return "dir" if', ['gate', 'unit', 'integration']),
    ('N02', 'F1/A: a submodule whose rev-parse exits 128 is "uninitialised"',
     '    if top is None:  # no answer (128 included), recorded by r.run\n        return "unreadable"\n',
     '    if top is None:  # no answer (128 included), recorded by r.run\n        return "uninitialised"\n', ['gate', 'unit', 'integration']),
    ('N03', 'F1/A: a foreign top level (git walked up to the parent) is accepted as the submodule',
     '    if os.path.realpath(top) != os.path.realpath(path):\n',
     '    if False:\n', ['gate', 'unit', 'integration']),
    ('N04', 'F1/A: a foreign top level is "uninitialised" with no no-answer recorded (the r3 shape)',
     '        r.no_answer(path, "rev-parse", "not-own-toplevel")\n        return "unreadable"\n',
     '        return "uninitialised"\n', ['gate', 'unit', 'integration']),
    ('N05', 'F1/B: an operation marker that cannot be read is not "in progress"',
     '            found.append(n + "?unreadable")\n',
     '            pass\n', ['gate', 'unit', 'integration', 'hardening']),
    ('N06', 'F1/A start-dir: exit 128 with a .git present is "not a work tree" (usage), never BLIND',
     '        if path_kind(os.path.join(start_dir, ".git")) != "absent":\n',
     '        if False:\n', ['gate', 'unit', 'integration']),
    ('N07', 'F2: head_after is a copy of head_before, never re-read after the pass',
     '            repo.rec["head_after"] = read_head(r, repo.abspath)\n',
     '            repo.rec.setdefault("head_after", repo.rec.get("head_before"))\n', ['gate', 'unit', 'integration']),
    ('N08', 'F2: a repository that moved and is blocked afterwards is "updated"',
     '        elif moved and mode == "apply" and not blocking:',
     '        elif moved and mode == "apply":', ['gate', 'unit', 'integration']),
    ('N09', 'F3: --advance-pins detaches a submodule checked out on a branch',
     '            if want and rec.get("branch") is not None:\n',
     '            if False:\n', ['gate', 'unit', 'integration']),
    ('N10', 'F3: kept-on-branch is never a reason (a kept submodule reads as current)',
     '        reasons.append("kept-on-branch:" + rec["kept_on_branch"])\n',
     '        pass\n', ['gate', 'unit', 'integration']),
    ('N11', 'F1: a path that is not a directory (a symbolic link) needs no attention',
     'if st in ("not-a-directory", "cycle", "unreadable") or',
     'if st in ("cycle", "unreadable") or', ['gate', 'unit', 'integration']),
    ('N12', 'F1: an unreadable submodule carries no pin-unreadable reason',
     'if st in ("not-a-directory", "cycle", "unreadable") or',
     'if st in ("not-a-directory", "cycle") or', ['gate', 'unit', 'integration']),
    ('N13', 'F9: userinfo cut at the FIRST "@" (a password holding "@" leaks its tail)',
     '        at = text.rfind("@", start, end)',
     '        at = text.find("@", start, end)', ['gate', 'unit', 'security']),
    ('N14', 'F9: the URL token ends at a space (a password holding a space leaks its tail)',
     '        nl = text.find("\\n", start)\n',
     '        nl = text.find(" ", start)\n', ['gate', 'unit', 'security']),
    ('N15', 'F9: only secrets of 64 characters or more are remembered',
     'if len(p) >= 8)',
     'if len(p) >= 64)', ['gate', 'unit', 'security']),
    ('N16', 'F9: a remembered secret said without its URL is not removed',
     '        text = text.replace(s, "[REDACTED]")\n',
     '        pass\n', ['gate', 'unit', 'security']),
    ('N17', 'F9: the lines of a multi-line userinfo are not remembered one by one',
     '        pieces.update(p.split("\\n"))\n',
     '        pass\n', ['gate', 'unit', 'security']),
    ('N18', 'class D: report keys are written unredacted',
     '            rk = redact(k)  # a key is output too (review round 3, class D)\n',
     '            rk = k\n', ['gate', 'unit', 'security', 'hardening']),
    ('N19', 'class D: a usage error echoes its argument unredacted',
     '        print("%s: error: %s" % (self.prog, redact(message)), file=sys.stderr)\n',
     '        print("%s: error: %s" % (self.prog, message), file=sys.stderr)\n', ['gate', 'unit', 'security']),
    ('N20', 'F7: GIT_TRACE* variables are no longer dropped (prefix)',
     'k.startswith("GIT_TRACE") or ',
     '', ['gate', 'unit', 'security', 'hardening']),
    ('N21', 'F7: GIT_CURL_VERBOSE is no longer dropped',
     '"GIT_CURL_VERBOSE", ',
     '', ['gate', 'unit', 'security', 'hardening']),
    ('N22', 'F5: the group guard drops "pgid == p.pid" (a foreign group can be signalled)',
     '    if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:\n',
     '    if isinstance(pgid, int) and pgid > 1:\n', ['gate', 'unit']),
    ('N23', 'F5: the group is assumed to be the pid, never read',
     '        pgid = os.getpgid(p.pid)\n',
     '        pgid = p.pid\n', ['gate', 'unit']),
    ('N24', 'F1: --quiet hides blind and not-initialised rows (the r3 shape)',
     '            always=rec.get("result") != "current")\n',
     '            always=rec.get("result") not in ("current", "blind", "not-initialised"))\n', ['gate', 'unit', 'integration', 'ui']),
    ('N25', 'F8 class: a child that cannot fetch its new pin is not failed',
     '            c.rec["failed"] = True\n',
     '            pass\n', ['gate', 'unit', 'integration']),
]
# id -> proof. A mutant listed here may survive; it is reported EQUIVALENT, never KILLED.
# M59 is no longer listed (round 4): its round-2 proof ended with "head_after = head_before (None)", which stopped
# being true when integrate() began to read every head after the pass (F2). A head that gave no answer before the
# run and is read after it (a fault at inspect_local's read) makes the mutant report moved=True for a repository
# that never moved; the record check of tests/sync/test_faults.sh catches it.
EQUIVALENT = {
    "M37": "(round 3) the consent check inside follow_children is dead code. integrate() calls follow_children only "
           "when `moved` is true, and `moved` is true only when (a) write_git() returned 'done' for a fast-forward, "
           "which runs only under consent 'integrate'; (b) write_git() returned 'done' for an advance-pin, which runs "
           "only under consent 'pins'; or (c) rec['followed'] is set, which only follow_children sets, for a child "
           "of a parent that itself satisfied (a), (b) or (c). By induction over depth, reaching follow_children "
           "implies 'integrate' or 'pins' was granted, so removing the check changes no run. M37b (the `moved` "
           "guard itself removed, so a parent that did not move makes its children follow) is the killable twin; "
           "tests/sync/test_hardening.sh section 10 kills it.",
}

SUITES = {s: os.path.join(HERE, "test_%s.sh" % s) for s in
          ("integration", "security", "chaos", "ui", "e2e", "determinism", "perf", "full_automation", "faults",
           "hardening")}
GATE = os.path.join(REPO, "scripts", "gates", "cm_sync_upstreams_ff_only.sh")
LIMIT = {"faults": 2400}


def run(cmd, env, timeout):
    """Runs one suite in its own session; on timeout the whole group is killed (no orphaned git or engine
    process survives a hanging mutant) and the status "timeout" is returned, reported as a kill BY TIMEOUT."""
    t = time.monotonic()
    p = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out.decode("utf-8", "replace"), time.monotonic() - t
    except subprocess.TimeoutExpired:
        pgid = p.pid   # start_new_session: the child leads its own group, so its pgid is its pid
        try:
            own = os.getpgid(p.pid) == pgid   # read, never assumed: only the child's OWN group is signalled
        except OSError:
            own = False   # already gone
        if isinstance(pgid, int) and pgid > 1 and own:   # never signal pgid <= 1 (section 11.4.263)
            try:
                os.killpg(pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        out, _ = p.communicate()
        return "timeout", out.decode("utf-8", "replace"), time.monotonic() - t


USAGE = "usage: test_mutations.py [--only ID,ID] [--gate-only | --no-gate] [--list]"


def main(argv):
    only, mode = None, "all"
    args = list(argv)
    if args == ["--list"]:
        for m in MUTANTS:
            print("%s\t%s\t%s" % (m[0], ",".join(m[4]), m[1]))
        return 0
    while args:
        a = args.pop(0)
        if a == "--only" and args:
            only = set(args.pop(0).split(","))
        elif a in ("--gate-only", "--no-gate") and mode == "all":
            mode = a[2:]
        else:
            print(USAGE, file=sys.stderr)
            return 2
    for m in MUTANTS:
        bad = [x for x in m[4] if x not in SUITES and x not in ("gate", "unit")]
        if bad:
            print("ERROR %s names unknown suites %s" % (m[0], bad))
            return 1
    src = open(ENGINE, encoding="utf-8").read()
    scratch = tempfile.mkdtemp(prefix="sync_mut.", dir=os.environ.get("TMPDIR") or None)
    killed, survivors, errors, rows = 0, [], [], []
    try:
        for mid, what, old, new, suites in MUTANTS:
            if only and mid not in only:
                continue
            if mode == "gate-only":
                suites = ["gate"]
            elif mode == "no-gate":
                suites = [x for x in suites if x != "gate"]
            if src.count(old) != 1:
                errors.append("%s: anchor occurs %d times" % (mid, src.count(old)))
                print("ERROR %s anchor occurs %d times" % (mid, src.count(old)))
                continue
            d = os.path.join(scratch, mid)
            sd = os.path.join(d, "scripts", "sync")
            os.makedirs(sd)
            open(os.path.join(sd, "sync_all_upstreams.py"), "w", encoding="utf-8").write(src.replace(old, new))
            shutil.copy(WRAPPER, os.path.join(sd, "sync_all_upstreams.sh"))
            env = dict(os.environ, SYNC_ENGINE_PY=os.path.join(sd, "sync_all_upstreams.py"),
                       SX_ENGINE=os.path.join(sd, "sync_all_upstreams.sh"))
            by, dur, rc = "-", 0.0, 0
            for suite in suites:
                cmd = (["bash", GATE, "--root", d] if suite == "gate" else
                       [sys.executable, "-I", os.path.join(HERE, "test_unit.py")] if suite == "unit" else
                       ["bash", SUITES[suite]])
                rc, out, t = run(cmd, env, LIMIT.get(suite, 600))
                dur += t
                if rc != 0:
                    by = suite + ("(timeout)" if rc == "timeout" else "")
                    break
            if rc != 0:
                killed += 1
                verdict = "KILLED"
            elif mid in EQUIVALENT:
                verdict = "EQUIVALENT"
            else:
                verdict = "SURVIVED"
                survivors.append(mid)
            rows.append((mid, verdict, by, "%.1f" % dur, what))
            print("%-4s %-10s by %-12s %6ss  %s" % rows[-1], flush=True)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)   # scratch made by mkdtemp above, under $TMPDIR
    total = len(rows)
    if only:
        missing = sorted(only - {m[0] for m in MUTANTS})
        if missing:
            errors.append("unknown ids %s" % missing)
            print("ERROR unknown mutant ids %s" % missing)
    print("sync-mutations (%s): mutants %d killed %d equivalent %d survived %d harness-errors %d"
          % (mode, total, killed, sum(1 for r in rows if r[1] == "EQUIVALENT"), len(survivors), len(errors)))
    if survivors:
        print("survivors: " + ",".join(survivors))
    return 0 if not survivors and not errors and total > 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
