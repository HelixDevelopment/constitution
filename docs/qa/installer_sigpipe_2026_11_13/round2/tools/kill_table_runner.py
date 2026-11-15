"""Kill table for CON-PENDING-INSTALLER-SIGPIPE round 2: applies each mutation to a COPY of the tree and runs
tests/install/test_sigpipe.sh there. A mutation is KILLED when the test reports a FAIL (the run is stopped at the
first FAIL line, which is recorded), SURVIVED when the test passes, and ANCHOR when its anchor text does not occur
exactly once (the mutation was not applied: never counted as killed).

usage: python3 -I kill_table_runner.py REPO WORKDIR OUT.tsv [--jobs N] [--only ID,ID] [--bash NAME=DIR ...]
  REPO     the tree under test (only scripts/, skills/ and tests/install/ are copied)
  WORKDIR  an existing directory this run owns; one fresh sub-directory per mutation, removed afterwards
  --bash   NAME=DIR: also run under the bash in DIR/bin (first on PATH); default: the host bash only
  --twins  run the TWIN list instead of the main list: the helper and reset mutants applied to EVERY copy of the
           shared text (installer and updater, or all four reset copies), so the "block is identical" check passes
           and only a behavioural check can kill them
  --no-stop  run the test to its end and record every section with a FAIL (column section = a comma list) and the
           number of FAIL lines, instead of stopping at the first FAIL
A control run (no mutation) comes first and must PASS, or the table is not written. A file in a mutation is either
one path or a tuple of paths; the anchor must occur exactly once in EACH path.
"""
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

SQ = chr(39)
BS = chr(92)
I = "scripts/install_constitution.sh"
U = "scripts/update_constitution.sh"
C = "scripts/install_cli_agent_plugins.sh"

I1 = 'if o="$(hi_gx -C "$r" ls-files -s -- "$HI_SUB" 2>/dev/null)" && hi_has_line_prefix "$o" ' + SQ + "160000 " + SQ + "; then"
I1_PIPE = 'if hi_gx -C "$r" ls-files -s -- "$HI_SUB" 2>/dev/null | {} ' + SQ + "^160000 " + SQ + "; then"
LEG = '    if hi_legacy_path_in "$blk"; then hi_check'
LEG_PIPE = ("    if printf " + SQ + "%s" + BS + "n" + SQ + ' "$blk" | grep -E ' + SQ + "(^|[^/A-Za-z_])constitution/" + SQ
            + " | {} " + SQ + "submodules/constitution/" + SQ + "; then hi_check")
RES = ('  hi_split_lines "$3"; tl=(${HI_LINES[@]+"${HI_LINES[@]}"})\n'
       '  for line in ${tl[@]+"${tl[@]}"}; do   # the first line naming ref, compared as a string (in the shell: hi_shell_state)\n'
       '    hi_read_fields "$line" 3\n'
       '    if [ "${HI_F[0]}" = "$ref" ]; then o="${HI_F[1]}"; break; fi\n'
       '  done\n')
UPOK = 'hi_upstream_ok() { local k; k="$(hi_upstream_table | cut -d' + SQ + "|" + SQ + ' -f1)"; hi_line_in "$1" "$k"; }'
Z = "  if hi_has_line_prefix \"$b$nl$a\" " + SQ + "Z " + SQ + "; then   # a remote answered but no fingerprint tool exists: fail closed\n"
Z_BLOCK = (Z + '    hi_err "no-push check: no cksum or sha256sum on PATH: what the remotes advertise cannot be compared; the run is refused (fail closed)"\n'
           "    return 0\n  fi\n")
MCMP = '  [ "$mb" = "$ma" ] || return 0\n'
RMEM = '    [ -n "${rb["R $i $r $s ${f:-0}"]+x}" ] && continue'
LMEM = '    [ -n "${ra["L $i $r $h"]+x}" ] && continue'
NMEM = '    [ -n "${ra["N $i $r"]+x}" ] || return 0'
LOOP = '  hi_split_lines "$a"; al=(${HI_LINES[@]+"${HI_LINES[@]}"})'
ULSF = ('if ! { UP_LSF="$(hi_gx -C "$ROOT" ls-files -s -- "$REL")" && hi_has_line_prefix "$UP_LSF" ' + SQ + "160000 " + SQ
        + "; }; then die 3")
HOOK = ('    hook_head="$(head -n 80 -- "$SUB/scripts/post_update_hook.sh" 2>/dev/null)" ' + BS + "\n"
        '      && up_hook_declares_project_root "$hook_head" ' + BS + "\n")
HOOK_RE = SQ + "^#[[:space:]]*HELIX_HOOK_CAPABILITIES:([^[:cntrl:]]*[[:space:]])?project-root([[:space:]]|$)" + SQ
HOOK_PIPE = ('    head -n 80 -- "$SUB/scripts/post_update_hook.sh" 2>/dev/null ' + BS + "\n"
             "      | {} " + HOOK_RE + " " + BS + "\n")
PLUG = '\n  if plugin_list="$(claude plugin list 2>/dev/null)" && [[ "$plugin_list" == *"$PLUGIN_NAME"* ]]; then'
RESET_CALL = '[ "${HI_SOURCED:-0}" = 1 ] || hi_reset_shell_state   # run, not sourced: the caller' + SQ + "s shell state is not inherited\n"
PLUMB_DEF = ("hi_plumbing_ok() { # 0 when process substitution works here (bash needs /dev/fd, or a writable TMPDIR for a fifo)\n"
             '  local x=""\n  { IFS= read -r x < <(printf ' + SQ + "ok" + BS + "n" + SQ + "); } 2>/dev/null\n"
             '  [ "$x" = ok ]\n}\n')
CLI_FAIL = ('      if hc_ln_relative "${src%/}" "$dst"; then linked=$((linked + 1))\n'
            '      else warn "could not link $dst"; failed=$((failed + 1)); fi')

# id, description, file, old, new
M = [
    ("RM01", "hi_layout gitlink check back to `| grep -q`", I, I1, I1_PIPE.format("grep -q")),
    ("RM02", "hi_verify legacy-path check back to the double pipe", I, LEG, LEG_PIPE.format("grep -qv")),
    ("RM03", "hi_resolve_ref_in tag lookup back to `| awk ... exit`", I, RES,
     '  o="$(printf ' + SQ + "%s" + BS + "n" + SQ + ' "$3" | awk -v n="$ref" ' + SQ + "$1 == n { print $2; exit }" + SQ + ')"\n'),
    ("RM04", "updater registered-submodule check back to `| grep -q`", U, ULSF,
     'if ! hi_gx -C "$ROOT" ls-files -s -- "$REL" | grep -q ' + SQ + "^160000 " + SQ + "; then die 3"),
    ("RM05", "updater hook capability probe back to `head | grep -qE`", U, HOOK, HOOK_PIPE.format("grep -qE")),
    ("RM06", "CLI plugin check back to `claude plugin list | grep -q`", C, PLUG,
     '\n  if claude plugin list 2>/dev/null | grep -q "$PLUGIN_NAME"; then'),
    ("RM07", "hi_upstream_ok back to `| grep -qxF`", I, UPOK,
     "hi_upstream_ok() { hi_upstream_table | cut -d" + SQ + "|" + SQ + ' -f1 | grep -qxF -- "$1"; }'),
    ("RM08", "Z check reads the before-marks only", I, Z, Z.replace('"$b$nl$a"', '"$b"')),
    ("RM09", "hi_layout check as `| LC_ALL=C grep -q`", I, I1, I1_PIPE.format("LC_ALL=C grep -q")),
    ("RM10", "`| grep -m1 . >/dev/null` added to hi_resolve_ref_in", I, RES,
     "  printf " + SQ + "%s" + BS + "n" + SQ + ' "$3" | grep -m1 . >/dev/null || return 1\n' + RES),
    ("RM11", "CLI plugin check as `|& grep -q`", C, PLUG, '\n  if claude plugin list |& grep -q "$PLUGIN_NAME"; then'),
    ("RM12", "Z check as `| command grep -q`", I, Z,
     "  if printf " + SQ + "%s" + BS + "n%s" + BS + "n" + SQ + ' "$b" "$a" | command grep -q ' + SQ + "^Z " + SQ + "; then\n"),
    ("RM13", "R membership as `| command grep -qxF`", I, RMEM,
     "    printf " + SQ + "%s" + BS + "n" + SQ + ' "$b" | command grep -qxF -- "R $i $r $s ${f:-0}" && continue'),
    ("RM14", "L membership as `| command grep -qxF`", I, LMEM,
     "    printf " + SQ + "%s" + BS + "n" + SQ + ' "$a" | command grep -qxF -- "L $i $r $h" && continue'),
    ("RM15", "N membership as `| command grep -qxF`", I, NMEM,
     "    printf " + SQ + "%s" + BS + "n" + SQ + ' "$a" | command grep -qxF -- "N $i $r" || return 0'),
    ("RM16", "Z check moved after the M-line comparison", I, Z_BLOCK + MCMP, MCMP + Z_BLOCK),
    ("RM17", "updater hook probe as `| egrep -q`", U, HOOK, HOOK_PIPE.format("egrep -q")),
    ("N01", "Z check as a here-string", I, Z, "  if grep -q " + SQ + "^Z " + SQ + ' <<<"$b$nl$a"; then\n'),
    ("N02", "after-marks split by a here-string loop", I, LOOP,
     '  al=(); while IFS= read -r line; do al+=("$line"); done <<<"$a"'),
    ("N03", "hi_upstream_ok through a here-document", I, UPOK,
     'hi_upstream_ok() { local k; k="$(cut -d' + SQ + "|" + SQ + " -f1 <<EOF\n$(hi_upstream_table)\nEOF\n)\"; hi_line_in \"$1\" \"$k\"; }"),
    ("N04", "reset call removed (installer)", I, RESET_CALL, ":\n"),
    ("N05", "reset call moved after the first <( (installer)", I, RESET_CALL + PLUMB_DEF, PLUMB_DEF + RESET_CALL),
    ("N06", "installer no longer checks process substitution", I, "    hi_plumbing_ok || { hi_err", "    true || { hi_err"),
    ("N07", "hi_layout check as `| fgrep -q`", I, I1, I1_PIPE.format("fgrep -q")),
    ("N08", "hi_layout check as `| " + BS + "grep -q`", I, I1, I1_PIPE.format(BS + "grep -q")),
    ("N09", "legacy-path check as `| egrep -qv`", I, LEG, LEG_PIPE.format("egrep -qv")),
    ("N10", "hi_resolve_ref_in through `| head -n 1`", I, RES,
     '  o="$(printf ' + SQ + "%s" + BS + "n" + SQ + ' "$3" | grep -F -- "$ref " | head -n 1 | cut -d' + SQ + " " + SQ + ' -f2)"\n'),
    ("N11", "hi_upstream_ok through `| sed -n ...q`", I, UPOK,
     "hi_upstream_ok() { hi_upstream_table | cut -d" + SQ + "|" + SQ + ' -f1 | sed -n "/^$1\\$/{p;q}" | grep -q .; }'),
    ("N12", "CLI no longer counts a link it could not create", C, CLI_FAIL, CLI_FAIL.replace("failed + 1", "failed + 0")),
    ("N13", "CLI ignores failed links in its exit status", C,
     '  [ "$refused" -eq 0 ] && [ "$failed" -eq 0 ] || return 1\n', '  [ "$refused" -eq 0 ] || return 1\n'),
    ("N14", "R pre-filter keeps only a bare R", I, "    case \"$line\" in R|R[[:blank:]]*|[[:blank:]]*) ;; *) continue ;; esac",
     "    case \"$line\" in R) ;; *) continue ;; esac"),
    ("N15", "before-marks pre-filter drops U", I, "    case \"$line\" in [UXMD]|[UXMD][[:blank:]]*|[[:blank:]]*) ;; *) continue ;; esac",
     "    case \"$line\" in [XMD]|[XMD][[:blank:]]*|[[:blank:]]*) ;; *) continue ;; esac"),
    ("N16", "hi_read_fields keeps trailing blanks", I, '  s="${s%"${s##*[!$ws]}"}"\n  HI_F+=("$s")', '  HI_F+=("$s")'),
    ("N17", "hi_split_lines without set -f (globbing on)", I, "  set -f\n  HI_LINES=($1)", "  HI_LINES=($1)"),
    ("N18", "hi_line_in matches a substring", I, '    [[ "$nl$2$nl" == *"$nl$p$nl"* ]] && return 0', '    [[ "$2" == *"$p"* ]] && return 0'),
    ("N19", "hi_has_line_prefix matches anywhere", I, '  [[ "$nl$1" == *"$nl$2"* ]]', '  [[ "$1" == *"$2"* ]]'),
    ("N20", "hi_legacy_path_in without the submodules/ exclusion", I, "    [[ $l == *submodules/constitution/* ]] || return 0", "    return 0"),
    ("N21", "reset no longer unsets BASH_COMPAT at its end", I,
     "  unset BASH_COMPAT 2>/dev/null   # bash 5.0 and later set it to their own version when a compatNN option is unset\n", ""),
    ("N22", "reset leaves posix mode on", I, "  for o in posix allexport noclobber", "  for o in allexport noclobber"),
    ("N23", "R membership via [[ -v assoc[key] ]]", I, RMEM, '    [[ -v rb["R $i $r $s ${f:-0}"] ]] && continue'),
    ("N24", "hi_on_remote stops at the first remote commit that does not contain it", I,
     '    hi_gx -C "$1" merge-base --is-ancestor "$2" "$l" 2>/dev/null && return 0\n',
     '    hi_gx -C "$1" merge-base --is-ancestor "$2" "$l" 2>/dev/null && return 0 || return 1\n'),
    ("N25", "updater hook regex not anchored", U, "re=" + SQ + "^#[[:space:]]*HELIX_HOOK_CAPABILITIES:", "re=" + SQ + "#[[:space:]]*HELIX_HOOK_CAPABILITIES:"),
    ("N26", "CLI reset call removed", C, "(return 0 2>/dev/null) || hi_reset_shell_state\nset -euo pipefail", "set -euo pipefail"),
    ("N27", "installer resets even when sourced", I, RESET_CALL, "hi_reset_shell_state\n"),
    ("N28", "hi_upstream_ok as a here-string", I, UPOK,
     'hi_upstream_ok() { local k; k="$(hi_upstream_table | cut -d' + SQ + "|" + SQ + ' -f1)"; grep -qxF -- "$1" <<<"$k"; }'),
    ("N29", "updater copy of hi_has_line_prefix matches anywhere", U, '  [[ "$nl$1" == *"$nl$2"* ]]', '  [[ "$1" == *"$2"* ]]'),
    ("N30", "before-marks cut at 8 KiB (class e)", I, '  hi_split_lines "$b"; bl=(', '  hi_split_lines "${b:0:8192}"; bl=('),
]

R4 = (I, U, C, "scripts/install_action_prefix.sh")
TWINS = [
    ("N04t", "reset call removed (installer and updater)", (I, U), RESET_CALL, ":\n"),
    ("N05t", "reset call moved after the first <( (installer and updater)", (I, U), RESET_CALL + PLUMB_DEF, PLUMB_DEF + RESET_CALL),
    ("N16t", "hi_read_fields keeps trailing blanks (both copies)", (I, U), '  s="${s%"${s##*[!$ws]}"}"\n  HI_F+=("$s")', '  HI_F+=("$s")'),
    ("N17t", "hi_split_lines without set -f (both copies)", (I, U), "  set -f\n  HI_LINES=($1)", "  HI_LINES=($1)"),
    ("N18t", "hi_line_in matches a substring (both copies)", (I, U), '    [[ "$nl$2$nl" == *"$nl$p$nl"* ]] && return 0', '    [[ "$2" == *"$p"* ]] && return 0'),
    ("N19t", "hi_has_line_prefix matches anywhere (both copies)", (I, U), '  [[ "$nl$1" == *"$nl$2"* ]]', '  [[ "$1" == *"$2"* ]]'),
    ("N21t", "reset no longer unsets BASH_COMPAT (all four copies)", R4,
     "  unset BASH_COMPAT 2>/dev/null   # bash 5.0 and later set it to their own version when a compatNN option is unset\n", ""),
    ("N22t", "reset leaves posix mode on (all four copies)", R4, "  for o in posix allexport noclobber", "  for o in allexport noclobber"),
    ("N27t", "installer and updater reset even when sourced", (I, U), RESET_CALL, "hi_reset_shell_state\n"),
    # N22t is EQUIVALENT (unset POSIXLY_CORRECT already turns posix mode off on every bash, see the README); N22u
    # removes both ways, so the reset really leaves posix mode on. A multi-edit mutant: old = list of (old, new), new = None
    ("N22u", "reset leaves posix mode on: POSIXLY_CORRECT kept AND posix dropped from set +o (all four copies)", R4,
     [("for o in BASH_COMPAT POSIXLY_CORRECT CDPATH TMOUT GLOBIGNORE; do", "for o in BASH_COMPAT CDPATH TMOUT GLOBIGNORE; do"),
      ("  for o in posix allexport noclobber", "  for o in allexport noclobber")], None),
]


def edits_of(old, new):
    return old if new is None else [(old, new)]


def paths_of(rel):
    return rel if isinstance(rel, tuple) else (rel,)


def copy_tree(repo, dst):
    for d in ("scripts", "skills", "tests/install"):
        shutil.copytree(os.path.join(repo, d), os.path.join(dst, d), symlinks=True)


def remove_tree(path, owner):
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(owner) + os.sep):
        raise SystemExit("refusing to remove %s: not inside %s" % (real, owner))
    shutil.rmtree(real)


def run_test(tree, bash_dir, no_stop=False):
    env = dict(os.environ)
    for k in ("LD_PRELOAD", "LD_LIBRARY_PATH"):
        env.pop(k, None)
    if bash_dir:
        env["PATH"] = os.path.join(bash_dir, "bin") + os.pathsep + env["PATH"]
    p = subprocess.Popen(["nice", "-n", "10", "bash", "tests/install/test_sigpipe.sh"], cwd=tree, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    section, first_fail, lines = "", "", []
    fail_sections, n_fail = [], 0
    t0 = time.time()
    for raw in p.stdout:
        line = raw.decode("utf-8", "replace").rstrip("\n")
        lines.append(line)
        m = re.match(r"# (\d+)\. ", line)   # section headers are "# <n>. <title>"; other "# " lines are not headers
        if m:
            section = m.group(1)
        if line.startswith("  FAIL ") and no_stop:
            n_fail += 1
            if not first_fail:
                first_fail = line[7:].split(" (expected [")[0][:160]
            if section not in fail_sections:
                fail_sections.append(section)
            continue
        if line.startswith("  FAIL "):
            first_fail = line[7:].split(" (expected [")[0][:160]
            pgid = p.pid
            if isinstance(pgid, int) and pgid > 1:   # section 11.4.263: never signal a group id <= 1
                try:
                    os.killpg(pgid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            break
    p.stdout.close()
    rc = p.wait()
    if no_stop and first_fail:
        section = ",".join(fail_sections) + " (%d FAIL)" % n_fail
    return rc, section, first_fail, lines, time.time() - t0


def one(job):
    mid, desc, rel, old, new, repo, work, bash_name, bash_dir, no_stop = job
    tree = tempfile.mkdtemp(prefix="m_%s_%s." % (mid, bash_name), dir=work)
    try:
        copy_tree(repo, tree)
        if mid != "CONTROL":
            for one_rel in paths_of(rel):
                path = os.path.join(tree, one_rel)
                text = open(path, encoding="utf-8").read()
                for o, nw in edits_of(old, new):
                    n = text.count(o)
                    if n != 1:
                        return (mid, bash_name, "ANCHOR", "", "anchor found %d times in %s" % (n, one_rel), desc, 0.0)
                    text = text.replace(o, nw)
                open(path, "w", encoding="utf-8").write(text)
        rc, section, first_fail, lines, secs = run_test(tree, bash_dir, no_stop)
        if first_fail:
            verdict = "KILLED"
        elif rc == 0 and lines and lines[-1].startswith("sigpipe: PASS"):
            verdict = "SURVIVED" if mid != "CONTROL" else "PASS"
        else:
            verdict = "ERROR"
            first_fail = "rc=%d last=%s" % (rc, lines[-1] if lines else "")
        return (mid, bash_name, verdict, section, first_fail, desc, secs)
    finally:
        remove_tree(tree, work)


def check_anchors(repo):
    bad = 0
    for (mid, desc, rel, old, new) in M + TWINS:
        for one_rel in paths_of(rel):
            text = open(os.path.join(repo, one_rel), encoding="utf-8").read()
            for o, nw in edits_of(old, new):
                n = text.count(o)
                if n != 1:
                    bad += 1
                    print("%s\tanchor found %d times in %s\t%s" % (mid, n, one_rel, desc))
                text = text.replace(o, nw)
    print("%d mutants (%d main, %d twins), %d bad anchors" % (len(M) + len(TWINS), len(M), len(TWINS), bad))
    return 1 if bad else 0


def main(argv):
    if argv and argv[0] == "--check-anchors":
        raise SystemExit(check_anchors(argv[1]))
    repo, work, out = argv[0], argv[1], argv[2]
    jobs, only, bashes, twins, no_stop = 2, None, [("host", "")], False, False
    i = 3
    while i < len(argv):
        if argv[i] == "--jobs":
            jobs = int(argv[i + 1]); i += 2
        elif argv[i] == "--only":
            only = set(argv[i + 1].split(",")); i += 2
        elif argv[i] == "--twins":
            twins = True; i += 1
        elif argv[i] == "--no-stop":
            no_stop = True; i += 1
        elif argv[i] == "--bash":
            name, d = argv[i + 1].split("=", 1); bashes.append((name, d)); i += 2
        else:
            raise SystemExit("unknown argument " + argv[i])
    work = os.path.realpath(work)
    for name, d in bashes:
        ctl = one(("CONTROL", "no mutation", "", "", "", repo, work, name, d, False))
        print("\t".join(str(x) for x in ctl), flush=True)
        if ctl[2] != "PASS":
            raise SystemExit("control run under %s did not pass: %s" % (name, ctl[4]))
    todo = [(mid, desc, rel, old, new, repo, work, name, d, no_stop)
            for (mid, desc, rel, old, new) in (TWINS if twins else M) if only is None or mid in only for (name, d) in bashes]
    rows, lock = [], threading.Lock()
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        for r in ex.map(one, todo):
            with lock:
                rows.append(r)
                print("\t".join(str(x) if not isinstance(x, float) else "%.0f" % x for x in r), flush=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("id\tbash\tverdict\tsection\tfirst_failing_check\tmutation\tseconds\n")
        for r in rows:
            f.write("\t".join(str(x) if not isinstance(x, float) else "%.0f" % x for x in r) + "\n")
    print("killed %d / %d" % (sum(1 for r in rows if r[2] == "KILLED"), len(rows)))


main(sys.argv[1:])
