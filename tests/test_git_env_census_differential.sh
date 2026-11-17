#!/usr/bin/env bash
# =============================================================================
# test_git_env_census_differential.sh -- CON-450 round 5 (review R4-1..R4-4, section 11.4.276(E) structural, the
# review's recommended DIFFERENTIAL test). The class "text that the interpreter runs and the census reads as something
# else" escaped four rounds one spelling at a time. This test does not enumerate spellings in the census; it compares
# the census with the interpreter ITSELF:
#
#   corpus   a generated set of small shell and Python files, each calling `git add -A` in a different disguise (a CR /
#            VT / FF / FS..US / DEL / NEL / NBSP / Unicode-space / zero-width / bidi / BOM prefix before `#;`, a
#            backslash continuation followed by a `#` line, a NUL byte beyond the first 80 bytes, an unquoted
#            here-document whose body runs a substitution, a Python coding cookie that hides a statement), before or
#            after the canonical scrub line, plus controls (a plain call, a properly scrubbed call, a quoted
#            here-document that is only data, a utf-8 cookie);
#   oracle   bash (or python3) RUNS every file with a recording `git` stand-in first in PATH and the poisoned
#            variables GIT_DIR=/inh and GIT_INDEX_FILE=/inh/idx exported; the recording shows whether git was called
#            with the poisoned variables still set ("RAN-UNSCRUBBED") -- the fact the census exists to predict;
#   rule     the census (git_env_class_census.py --tsv over a mini repository holding the corpus) must NEVER report
#            HERMETIC (or no row at all) for a file whose run was RAN-UNSCRUBBED. A census that refuses more than the
#            interpreter needs is allowed (conservative); one that clears what the interpreter runs unscrubbed is the
#            bluff. Control needles: at least one corpus file is RAN-UNSCRUBBED (the stand-in sees the poison), at
#            least one is scrubbed AND HERMETIC (the census does not simply refuse everything).
#
# Env: GE_CENSUS_UNDER_TEST -- the census file to judge (default scripts/validation/git_env_class_census.py), used by the
#      paired mutants. Exit: 0 every row held; 1 otherwise. Needs: python3, bash, git. Side effects: a mktemp -d tree.
# Evidence class: gate-logic (host-only): it proves the census decides like bash on these inputs, nothing about the
# product (section 11.4.289(I)).
# =============================================================================
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CENSUS="${GE_CENSUS_UNDER_TEST:-$ROOT/scripts/validation/git_env_class_census.py}"
[ -f "$CENSUS" ] || { echo "NOT ok census under test not found: $CENSUS"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ge_diff.XXXXXX")" || { echo "NOT ok mktemp failed"; exit 1; }
trap 'rm -rf -- "${WORK:?}"' EXIT
python3 -I - "$CENSUS" "$ROOT" "${WORK:?}" <<'PY'
import os, re, subprocess, sys
census, root, work = sys.argv[1:4]
fails = 0
passes = 0


def ok(m):
    global passes
    passes += 1
    print("ok   " + m)


def bad(m):
    global fails
    fails += 1
    print("NOT ok " + m)


layout = open(os.path.join(root, "scripts", "lib", "constitution_layout.sh"), encoding="utf-8").read()
LST = re.search(r'^CL_GIT_SCRUB_VARS="([^"]+)"', layout, re.M).group(1)
SC = 'for _ge_v in %s; do unset "$_ge_v"; done; unset _ge_v\n' % LST
PS = 'import os as _ge_os\nfor _ge_v in "%s".split(): _ge_os.environ.pop(_ge_v, None)\n' % LST
W = "git add -A\n"
HEAD = "#!/bin/bash\n"
PAD = "".join("# padding line %02d padding padding padding\n" % i for i in range(4))   # > 80 bytes before any NUL

cases = []   # (name, filename-ext, bytes)


def sh(name, body, head=HEAD):
    cases.append((name, "sh", (head + body).encode("utf-8", "surrogatepass")))


def shb(name, data):
    cases.append((name, "sh", data))


def py(name, text):
    cases.append((name, "py", text.encode("utf-8")))


# ---- controls
sh("ctl-plain", W)
sh("ctl-scrubbed", SC + W)
sh("ctl-write-before-scrub", W + SC)
sh("ctl-quoted-heredoc-is-data", SC + "cat <<'EOF' >/dev/null\n$(git add -A)\nEOF\n" + W)
sh("ctl-comment-only-mention", SC + "# git add -A is not run here\n" + W)
py("ctl-py-plain", 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n')
py("ctl-py-scrubbed", PS + 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n')
py("ctl-py-utf8-cookie-scrubbed", "# -*- coding: utf-8 -*-\n" + PS + 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n')
py("ctl-py-write-before-scrub", 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n' + PS)

# ---- R3-1 / R3-2 class (round 4): a character that bash does not treat as blank in front of `#`
CHARS = [("cr", "\r"), ("vt", "\x0b"), ("ff", "\x0c"), ("fs", "\x1c"), ("gs", "\x1d"), ("rs", "\x1e"), ("us", "\x1f"),
         ("nel", "\u0085"), ("nbsp", " "), ("emsp", " "), ("lsep", " "), ("psep", " "),
         ("zwsp", "​"), ("rlo", "‮"), ("bom", "﻿"), ("del", "\x7f"), ("ideographic", "　")]
for nm, ch in CHARS:
    sh("hide-lead-%s-before-scrub" % nm, ch + "#;git add -A\n" + SC)
    sh("hide-lead-%s-no-scrub" % nm, ch + "#;git add -A\n")
    sh("hide-lead-%s-after-padding" % nm, PAD + ch + "#;git add -A\n" + SC)
    sh("hide-canon-tail-%s" % nm, SC.rstrip("\n") + ch + "# x; export GIT_DIR=/inh\n" + W)

# ---- the cross product: a line starter (nothing, blanks, a continuation with and without a blank before the join) x a
#      character x `#;git add -A`. bash decides, for every cell, whether the `#` starts a comment; the census must agree
#      wherever bash ran git.
for pi, pre in enumerate(("", " ", "\t", "echo x\\\n", "echo x \\\n", ": ;")):
    for nm, ch in [("none", "")] + CHARS:
        sh("x%d-%s-before-scrub" % (pi, nm), pre + ch + "#;git add -A\n" + SC)
        sh("x%d-%s-no-scrub" % (pi, nm), pre + ch + "#;git add -A\n")

# ---- R4-3: NUL anywhere (bash ignores it after the first line; a census that sets such a file aside as binary
#      never judges it)
for nm, data in (
    ("nul-in-padding-then-write", (HEAD + PAD + "# pad\x00ding\n" + W)),
    ("nul-in-write-line", (HEAD + PAD + "git\x00 add -A\n")),
    ("nul-after-write", (HEAD + PAD + W + "# t\x00ail\n")),
    ("nul-then-write-before-scrub", (HEAD + PAD + "# n\x00\n" + W + SC)),
    ("nul-in-scrubbed-file", (HEAD + SC + PAD + "# n\x00\n" + W)),
    ("nul-inside-scrub-line", (HEAD + "for _ge_v in %s; do unset \"$_ge_v\"; done; unset _ge_v\x00\n" % LST + W)),
    ("nul-trailing-only-write-after", (HEAD + W + "\x00")),
    ("nul-inside-the-word-git", (HEAD + PAD + "g\x00it add -A\n")),
    ("nul-inside-the-word-git-2", (HEAD + PAD + "gi\x00t add -A\n" + SC)),
):
    shb(nm, data.encode("utf-8"))
py("nul-py-padding", PS + 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n# n\x00\n')

# ---- R4-4: continuation, then a `#` line (the continued line is not a comment: bash joins the two lines, `#` is then
#      in the middle of a word)
for nm, text in (
    ("cont-echo", "echo x\\\n#; git add -A\n"),
    ("cont-echo-blank", "echo x\\\n  #;git add -A\n"),
    ("cont-assign", "a=b\\\n#;git add -A\n"),
    ("cont-colon", ": \\\n# ;git add -A\n"),
    ("cont-tab", "echo x\\\n\t#; git add -A\n"),
    ("cont-two", "echo x\\\n#\\\n#; git add -A\n"),
    ("cont-comment-ctl", "# a comment \\\n#;git add -A\n"),
):
    sh("hide-%s-before-scrub" % nm, text + SC)
    sh("hide-%s-no-scrub" % nm, text)

# ---- R4-2 class: unquoted here-document bodies run substitutions
for nm, text in (
    ("hd-dollar", "cat <<EOF >/dev/null\n$(git add -A)\nEOF\n"),
    ("hd-backtick", "cat <<EOF >/dev/null\n`git add -A`\nEOF\n"),
    ("hd-dash", "cat <<-EOF >/dev/null\n\t$(git add -A)\n\tEOF\n"),
    ("hd-comment-line", "cat <<EOF >/dev/null\n# $(git add -A)\nEOF\n"),
    ("hd-in-function", "f() {\ncat <<EOF >/dev/null\n$(git add -A)\nEOF\n}\nf\n"),
    ("hd-in-substitution", "x=$(cat <<EOF\n$(git add -A)\nEOF\n)\n"),
    ("hd-assign-default", "cat <<EOF >/dev/null\n${GE_X:-$(git add -A)}\nEOF\n"),
):
    sh("hide-%s-before-scrub" % nm, text + SC)
    sh("hide-%s-no-scrub" % nm, text)

# ---- R4-1: Python coding cookie hides statements from the census, not from the interpreter
HID = '# x +AAo-import subprocess+AAo-subprocess.run(["git","add","-A"])\n'
for ck in ("utf-7", "UTF-7", "utf_7", "latin-1", "cp037", "utf-16", "ascii", "utf-8", "UTF-8", "utf8", "iso-8859-1"):
    py("cookie-%s-hidden-before-scrub" % ck, "# -*- coding: %s -*-\n%s" % (ck, HID) + PS)
    py("cookie-%s-scrubbed" % ck, "# -*- coding: %s -*-\n" % ck + PS + 'import subprocess\nsubprocess.run(["git", "add", "-A"])\n')
    py("cookie-%s-line2" % ck, "#!/usr/bin/env python3\n# vim: set fileencoding=%s :\n%s" % (ck, HID) + PS)
py("cr-hidden-before-scrub", "import os as _ge_os  # c\rimport subprocess; subprocess.run(['git', 'add', '-A'])\n" + PS.split("\n", 1)[1])

# ---- run the corpus: the stand-in git records the environment it was called with
mini = os.path.join(work, "mini")
bindir = os.path.join(work, "bin")
os.makedirs(os.path.join(mini, "scripts", "lib"))
os.makedirs(os.path.join(mini, "corpus"))
os.makedirs(bindir)
open(os.path.join(mini, "scripts", "lib", "constitution_layout.sh"), "w", encoding="utf-8").write(layout)
shim = os.path.join(bindir, "git")
open(shim, "w").write('#!/bin/bash\nprintf "GIT_DIR=%s GIT_INDEX_FILE=%s\\n" "${GIT_DIR-unset}" "${GIT_INDEX_FILE-unset}" >> "$GE_LOG"\n')
os.chmod(shim, 0o755)
names = {}
for i, (nm, ext, data) in enumerate(cases):
    fn = "corpus/c%03d.%s" % (i, ext)
    names[fn] = nm
    open(os.path.join(mini, fn), "wb").write(data)


def sub_env(extra=None):
    e = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    e.update(extra or {})
    return e


def git(*a):
    return subprocess.run(["git", "-C", mini] + list(a), capture_output=True, env=sub_env({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}))


git("init", "-q")
git("add", "-A")
ran = {}
for fn, nm in names.items():
    log = os.path.join(work, "log.txt")
    if os.path.exists(log):
        os.remove(log)
    env = sub_env({"PATH": bindir + os.pathsep + os.environ["PATH"], "GE_LOG": log, "GIT_DIR": "/inh",
                   "GIT_INDEX_FILE": "/inh/idx", "LC_ALL": "C.UTF-8"})
    cmd = ["python3", "-I", os.path.join(mini, fn)] if fn.endswith(".py") else ["bash", os.path.join(mini, fn)]
    subprocess.run(cmd, capture_output=True, env=env, cwd=work, timeout=60)
    text = open(log).read() if os.path.exists(log) else ""
    ran[fn] = "RAN-UNSCRUBBED" if "GIT_DIR=/inh" in text else ("RAN-CLEAN" if text else "NOT-RUN")

p = subprocess.run(["python3", "-I", census, "--root", mini, "--tsv"], capture_output=True, env=sub_env(), text=True)
rows = {}
for line in p.stdout.split("\n"):
    c = line.split("\t")
    if len(c) == 5 and c[2].startswith("corpus/"):
        rows[c[2]] = c[0]
blind = [l for l in p.stdout.split("\n") if "BLIND" in l]
if blind or p.returncode == 2:
    bad("census was BLIND on the corpus: %s" % (blind[:2],))

# second pass: every corpus file carries a `no-git-execution` exemption row ("this file never runs git"). The write
# detector must contradict the row for each file whose run called git unscrubbed; EXEMPT would be the bluff (R4-4: a
# continuation-led `#` line was blanked as a comment, the hidden `git add -A` was never seen).
exf = os.path.join(work, "exempt.tsv")
open(exf, "w", encoding="utf-8").write("".join("%s\tno-git-execution\tdifferential corpus: asserts the file never runs git\n" % f for f in sorted(names)))
p2 = subprocess.run(["python3", "-I", census, "--root", mini, "--tsv", "--exemptions", exf], capture_output=True, env=sub_env(), text=True)
rows2 = {}
for line in p2.stdout.split("\n"):
    c = line.split("\t")
    if len(c) == 5 and c[2].startswith("corpus/"):
        rows2[c[2]] = c[0]
for fn in sorted(names):
    if ran[fn] == "RAN-UNSCRUBBED" and rows2.get(fn, "NOROW") in ("HERMETIC", "EXEMPT", "NOROW"):
        bad("%-8s %-46s bash RAN-UNSCRUBBED, census with a no-git-execution row says %s" % (fn[7:], names[fn], rows2.get(fn, "NOROW")))
n_unscrubbed = sum(1 for v in ran.values() if v == "RAN-UNSCRUBBED")
n_hermetic_clean = sum(1 for f, v in ran.items() if v == "RAN-CLEAN" and rows.get(f) == "HERMETIC")
for fn in sorted(names):
    st = rows.get(fn, "NOROW")
    r = ran[fn]
    if r == "RAN-UNSCRUBBED" and st in ("HERMETIC", "NOROW"):
        bad("%-8s %-46s bash %s, census %s (a scrub that is not effective cleared as HERMETIC, or the file was not judged)" % (fn[7:], names[fn], r, st))
    else:
        ok("%-8s %-46s bash %-14s census %s" % (fn[7:], names[fn], r, st))
# control needles of the instrument itself (section 11.4.273): the stand-in sees the poison, the census does not refuse
# everything, and the controls land where they must
if n_unscrubbed < 40:
    bad("control needle: only %d corpus files ran with the poisoned variables (expected the disguised writes to be seen)" % n_unscrubbed)
else:
    ok("control needle: %d corpus files ran git with the poisoned variables still set" % n_unscrubbed)
if n_hermetic_clean < 1:
    bad("control needle: no corpus file is both scrubbed at run time and HERMETIC (the census refuses everything)")
else:
    ok("control needle: %d corpus files ran scrubbed and are HERMETIC" % n_hermetic_clean)
want = {"ctl-plain": ("RAN-UNSCRUBBED", "UNSCRUBBED"), "ctl-scrubbed": ("RAN-CLEAN", "HERMETIC"),
        "ctl-py-scrubbed": ("RAN-CLEAN", "HERMETIC"), "ctl-py-utf8-cookie-scrubbed": ("RAN-CLEAN", "HERMETIC"),
        "ctl-write-before-scrub": ("RAN-UNSCRUBBED", "UNSCRUBBED")}
inv = {v: k for k, v in names.items()}
for nm, (r, st) in sorted(want.items()):
    fn = inv[nm]
    if (ran[fn], rows.get(fn)) == (r, st):
        ok("control %s: bash %s, census %s" % (nm, r, st))
    else:
        bad("control %s: bash %s census %s (want %s / %s)" % (nm, ran[fn], rows.get(fn), r, st))
print("SUMMARY corpus=%d pass=%d fail=%d" % (len(cases), passes, fails))
sys.exit(1 if fails else 0)
PY
