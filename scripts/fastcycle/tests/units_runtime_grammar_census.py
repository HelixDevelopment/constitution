#!/usr/bin/env python3
"""Adversarial census for the units helper (ATM-1217 r12, review round 2 G1).

Class under test: "runtime grammar modifiers the static parser does not model" -- anything that, at run time,
defines an alias (or turns alias expansion on) in the CURRENT shell, so that a later line continues a command the
parser split (`alias p='false &&'` then the lines `p` and `mkdir -p M` become ONE list; r12 used `echo hi |`
and `tr a-z A-Z`, see AV below for why r13 changed the oracle).

Each generated script is   <prelude> <channel> NEWLINE p NEWLINE mkdir -p M NEWLINE echo END NEWLINE
and is run by the real shells of its dialect (posix: dash and bash --posix; bash: bash) with stdin `hello`.
ORACLE (joined): a shell prints END and M is absent  <=>  the runtime text joined `p` and `mkdir` (boundary moved).
HELPER: the real units helper on the same bytes; "split" = exit 0 with the `p` line and the `tr` line in
different units. SOUNDNESS: no script some oracle shell joins may be split by the helper.

Benign shapes the rule still claims (r13: the subset; the r12 claims it no longer makes are marked stricter) must be CREDITED (helper exit 0): a refusal there is a false
refusal, reported and failed only for the shapes the rule claims to allow.

Control needles (11.4.273): the oracle shells join a literal `&&` continuation and do NOT join a bare `p`;
the helper splits a plain two-line script. A census whose controls fail proves nothing and exits 2.

Usage:  units_runtime_grammar_census.py --helper PATH [--out TSV] [--min-positive N]
Exit:   0 sound, every claimed benign shape credited, >= N positive cases; 1 any unsound / refused claimed shape /
        too few positives; 2 environment (a shell missing, a control needle failed).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

# r13 (fixer round 4): the oracle no longer pipes into `tr` -- the r13 helper refuses any command that may read the
# shell's stdin (P8), which would make every case trivially "closed". The alias value now ends in `&&`: when the
# alias joins the lines, `false && mkdir -p M` skips the mkdir; when it does not, `p` fails and mkdir runs. A case is
# JOINED <=> the shell printed END and the directory M does not exist.
AV = "false &&"                       # the alias value: a list that continues onto the next line
TAIL = "p\nmkdir -p M\necho END\n"   # line P = the line after the channel; line P+1 = mkdir (reads no stdin)


def q(s):
    return "'" + s.replace("'", "'\\''") + "'"


# --- channels -------------------------------------------------------------------------------------------------
# (id, dialects, text): every channel runs in a POSIX file; "bash" adds bash-dialect cases. {D} = a plain alias definition `alias p='false &&'`. Every channel is a way to run that
# definition (or an equivalent) in the current shell at run time.
D = "alias p=" + q(AV)
CHANNELS = [
    # direct, quoted, escaped, ANSI-C
    ("alias", "posix bash", D),
    ("bs-alias", "posix bash", "\\" + D),
    ("sq-alias", "posix bash", "'alias' p=" + q(AV)),
    ("dq-alias", "posix bash", '"alias" p=' + q(AV)),
    ("split-sq", "posix bash", "al''ias p=" + q(AV)),
    ("split-bs", "posix bash", "al\\ias p=" + q(AV)),
    ("ansi-lit", "posix bash", "$'alias' p=" + q(AV)),
    ("ansi-oct", "posix bash", "$'\\141lias' p=" + q(AV)),
    ("ansi-hex", "posix bash", "$'\\x61lias' p=" + q(AV)),
    ("bs-nl", "posix bash", "ali\\\nas p=" + q(AV)),
    # wrappers
    ("command", "posix bash", "command " + D),
    ("command-p", "posix bash", "command -p " + D),
    ("command-dd", "posix bash", "command -- " + D),
    ("builtin", "bash", "builtin " + D),
    ("builtin-dd", "bash", "builtin -- " + D),
    ("command-builtin", "bash", "command builtin " + D),
    # eval
    ("eval-dq", "posix bash", 'eval "' + D + '"'),
    ("eval-sq", "posix bash", "eval " + q(D)),
    ("eval-2arg", "posix bash", "eval 'q=1;' " + q(D)),
    ("eval-split", "posix bash", "eval al''ias p=" + q(q(AV))),
    ("eval-obf", "posix bash", "eval " + q("al\"\"ias p=" + q(AV))),
    ("eval-nested", "posix bash", "eval " + q("eval " + q(D))),
    ("eval-var", "posix bash", "x=" + q(D) + "; eval \"$x\""),
    ("eval-cmdsubst", "posix bash", "eval \"$(printf 'al%sas p=%s' i " + q(q(AV)) + ")\""),
    ("command-eval", "posix bash", "command eval " + q(D)),
    ("builtin-eval", "bash", "builtin eval " + q(D)),
    ("eval-as-var", "posix bash", "e=eval; $e " + q(D)),
    # dynamic command words
    ("var-word", "posix bash", "a=alias; $a p=" + q(AV)),
    ("brace-var", "posix bash", "a=alias; ${a} p=" + q(AV)),
    ("dq-var", "posix bash", "a=alias; \"$a\" p=" + q(AV)),
    ("built-var", "posix bash", "a=ali; b=as; $a$b p=" + q(AV)),
    ("cmdsubst-word", "posix bash", "$(echo alias) p=" + q(AV)),
    ("backtick-word", "posix bash", "`echo alias` p=" + q(AV)),
    ("printf-word", "posix bash", "$(printf 'al%sas' i) p=" + q(AV)),
    ("param-default", "posix bash", "${u:-alias} p=" + q(AV)),
    ("brace-exp", "bash", "{alias,} p=" + q(AV)),
    ("glob-q", "posix bash", "alia? p=" + q(AV)),
    ("glob-bracket", "posix bash", "al[i]as p=" + q(AV)),
    ("glob-star", "posix bash", "alia* p=" + q(AV)),
    ("command-var", "posix bash", "a=alias; command $a p=" + q(AV)),
    ("args-func", "posix bash", "f() { \"$@\"; }; f alias p=" + q(AV)),
    ("set-args", "posix bash", "set -- alias p=" + q(AV) + "; \"$@\""),
    # traps (the action runs in the current shell)
    ("trap-usr1", "posix bash", "trap " + q(D) + " USR1; kill -USR1 $$"),
    ("trap-usr1-obf", "posix bash", "trap " + q("al\"\"ias p=" + q(AV)) + " USR1; kill -USR1 $$"),
    ("trap-var", "posix bash", "t=" + q(D) + "; trap \"$t\" USR1; kill -USR1 $$"),
    ("trap-dq-exp", "posix bash", "a=alias; trap \"$a p='" + AV + "'\" USR1; kill -USR1 $$"),
    ("trap-eval", "posix bash", "trap " + q("eval " + q(D)) + " USR1; kill -USR1 $$"),
    ("trap-debug", "bash", "trap " + q(D + "; trap - DEBUG") + " DEBUG"),
    ("trap-return", "bash", "f() { :; }; trap " + q(D) + " RETURN; f; trap - RETURN"),
    ("trap-err", "bash", "trap " + q(D + "; trap - ERR") + " ERR; false"),
    ("trap-int", "posix bash", "trap " + q(D) + " INT; kill -INT $$"),
    ("trap-sig-dd", "posix bash", "trap -- " + q(D) + " USR1; kill -USR1 $$"),
    ("command-trap", "posix bash", "command trap " + q(D) + " USR1; kill -USR1 $$"),
    # sourcing
    ("dot-stdin", "posix bash", ". /dev/stdin <<'E'\n" + D + "\nE"),
    ("dot-file", "posix bash", "printf '%s\\n' " + q(D) + " >f.sh; . ./f.sh"),
    ("dot-obf-file", "posix bash", "printf 'al%sas p=%s\\n' i " + q(q(AV)) + " >f.sh; . ./f.sh"),
    ("dot-var", "posix bash", "printf '%s\\n' " + q(D) + " >f.sh; x=./f.sh; . \"$x\""),
    ("source-file", "bash", "printf '%s\\n' " + q(D) + " >f.sh; source ./f.sh"),
    ("source-procsub", "bash", "source <(printf '%s\\n' " + q(D) + ")"),
    ("dot-heredoc-fd", "posix bash", ". /dev/fd/3 3<<'E'\n" + D + "\nE"),
    ("command-dot", "posix bash", "printf '%s\\n' " + q(D) + " >f.sh; command . ./f.sh"),
    # BASH_ALIASES (bash: an assignment defines an alias)
    ("ba-assign", "posix bash", "BASH_ALIASES[p]=" + q(AV)),
    ("ba-quoted-sub", "posix bash", "BASH_ALIASES['p']=" + q(AV)),
    ("ba-printf-v", "posix bash", "printf -v 'BASH_ALIASES[p]' %s " + q(AV)),
    ("ba-printf-v-split", "posix bash", "printf -v BASH_ALI''ASES'[p]' %s " + q(AV)),
    ("ba-printf-v-dyn", "posix bash", "n=BASH_ALI; n=${n}ASES; printf -v \"$n[p]\" %s " + q(AV)),
    ("ba-read", "posix bash", "read -r 'BASH_ALIASES[p]' <<'E'\n" + AV + "\nE"),
    ("ba-read-dyn", "posix bash", "n=BASH_ALI; n=${n}ASES; read -r \"$n[p]\" <<'E'\n" + AV + "\nE"),
    ("ba-nameref", "bash", "declare -n r=BASH_ALIASES; r[p]=" + q(AV)),
    ("ba-nameref-dyn", "bash", "n=BASH_ALI; declare -n r=${n}ASES; r[p]=" + q(AV)),
    ("ba-local-nameref", "bash", "f() { local -n r=$1; r[p]=" + q(AV) + "; }; f BASH_ALIASES"),
    ("ba-declare-dyn", "bash", "n=BASH_ALI; declare \"${n}ASES[p]=" + AV + "\""),
    ("ba-param-assign", "posix bash", ": \"${BASH_ALIASES[p]:=" + AV + "}\""),
    ("ba-at-P", "bash", "n=BASH_ALI; n=${n}ASES; v=\"\\${$n[p]:=" + AV + "}\"; : \"${v@P}\""),
    ("ba-ps4", "bash", "PS4=" + q("${BASH_ALIASES[p]:=" + AV + "}") + "; set -x; :; set +x"),
    ("ba-ps4-dyn", "bash", "n=BASH_ALI; n=${n}ASES; PS4=\"\\${$n[p]:=" + AV + "}\"; set -x; :; set +x"),
    ("ba-mapfile-C", "bash", "mapfile -t -C " + q(D + "; :") + " -c 1 a <<'E'\nx\nE"),
    ("ba-mapfile-C-dyn", "bash", "c=" + q(D + "; :") + "; mapfile -t -C \"$c\" -c 1 a <<'E'\nx\nE"),
    ("ba-array", "bash", "BASH_ALIASES=([p]=" + q(AV) + ")"),
    ("ba-func", "posix bash", "f() { BASH_ALIASES[p]=" + q(AV) + "; }; f"),
    ("ba-getopts", "bash", "set -- -x; n=BASH_ALI; getopts x \"${n}ASES[p]\"; BASH_ALIASES[p]=" + q(AV)),
]
# bash (no posix mode): aliases are expanded only after one of these; every one is combined with BASH_ALIASES and
# with the alias builtin (each pair is a separate case)
ENABLES = [
    ("shopt", "shopt -s expand_aliases"),
    ("shopt-var", "o=expand_aliases; shopt -s $o"),
    ("shopt-built", "o=expand_; shopt -s ${o}aliases"),
    ("shopt-glob", "shopt -s expand_alias?"),
    ("set-posix", "set -o posix"),
    ("set-posix-var", "x=posix; set -o $x"),
    ("shopt-o-posix", "shopt -s -o posix"),
    ("posixly", "POSIXLY_CORRECT=1"),
    ("posixly-export", "export POSIXLY_CORRECT=1"),
    ("posixly-printf-v", "printf -v POSIXLY_CORRECT 1"),
    ("posixly-read", "read -r POSIXLY_CORRECT <<'E'\n1\nE"),
    ("posixly-dyn", "n=POSIXLY_CORR; declare -n r=${n}ECT; r=1"),
    ("posixly-printf-dyn", "n=POSIXLY_CORR; printf -v \"${n}ECT\" 1"),
    ("set-o-dyn", "o=po; set -o ${o}six"),
]
# contexts that run a channel in the current shell (a `{D}` placeholder)
CONTEXTS = [
    ("top", "{D}"),
    ("brace", "{ {D}\n}"),
    ("if", "if true; then\n{D}\nfi"),
    ("and", "true && {D}"),
    ("func", "g() {\n{D}\n}\ng"),
    ("case", "case x in x)\n{D}\n;; esac"),
]
# benign shapes the r12 rule claims to credit (exit 0, units printed): (id, dialect, text, claimed)
BENIGN = [
    ("trap-exit-sq", "posix", "t=$(mktemp)\ntrap 'rm -f \"$t\"' EXIT\necho a\necho b\n", False),  # r13: refused (stricter, positive subset);
    ("trap-exit-dq", "posix", "t=$(mktemp)\ntrap \"rm -f $t\" EXIT\necho a\necho b\n", False),  # r13: refused (stricter, positive subset);
    ("trap-func-sigs", "posix", "cleanup() { rm -f x; }\ntrap cleanup EXIT INT TERM\necho a\n", False),  # r13: refused (stricter, positive subset);
    ("trap-reset", "posix", "trap - INT TERM\ntrap '' HUP\ntrap\necho a\n", False),  # r13: refused (stricter, positive subset);
    ("trap-0", "posix", "trap 'echo bye' 0\necho a\n", False),  # r13: refused (stricter, positive subset);
    ("set-eu", "posix", "set -eu\necho a\n", True),
    ("set-euo", "bash", "set -euo pipefail\necho a\n", True),
    ("set-args", "posix", "set -- a b \"$@\"\necho a\n", True),
    ("set-plus-e", "posix", "set +e\nset -x\nset +x\necho a\n", True),
    ("shopt-ok", "bash", "shopt -s nullglob globstar\nshopt -u dotglob\necho a\n", True),
    ("printf-plain", "posix", "printf '%s\\n' \"$x\"\necho a\n", True),
    ("printf-v-lit", "bash", "printf -v out '%s' \"$x\"\necho \"$out\"\n", False),  # r13: refused (stricter, positive subset);
    ("read-lit", "posix", "read -r line <f\necho \"$line\"\n", False),  # r13: refused (stricter, positive subset);
    ("read-p", "bash", "read -r -p \"$prompt\" ans\necho \"$ans\"\n", False),  # r13: refused (stricter, positive subset);
    ("mapfile-lit", "bash", "mapfile -t lines <f\necho \"${lines[0]}\"\n", False),  # r13: refused (stricter, positive subset);
    ("eval-lit", "posix", "eval 'x=1'\necho \"$x\"\n", False),  # r13: refused (stricter, positive subset);
    ("command-v", "posix", "command -v git >/dev/null || exit 1\necho a\n", True),
    ("alias-in-data", "posix", "echo \"an alias here\"\ncat <<'E'\nalias p=x\nE\necho a\n", True),
    ("arith", "posix", "i=0\ni=$((i+1))\necho \"$i\"\n", False),  # r13: refused (stricter, positive subset);
    ("declare-lit", "bash", "declare -A m\nlocal_x() { local -a arr=(1 2); echo \"${arr[0]}\"; }\nlocal_x\n", False),  # r13: refused (stricter, positive subset);
    ("child-sh", "posix", "sh -c 'alias p=x; p'\necho a\n", False),  # r13: refused (stricter, positive subset);
    ("test-bracket", "posix", "[ -f x ] && echo y\necho a\n", True),
    ("exec-out", "posix", "exec 3>/dev/null\necho a >&3\n", False),  # r13: refused (stricter, positive subset);
    ("dollar-at-word", "posix", "\"$@\"\necho a\n", False),          # stricter: a dynamic command word
    ("dot-lib", "posix", ". ./lib.sh\necho a\n", False),              # stricter: sourcing is not modelled
    ("ps4", "bash", "PS4='+ ${LINENO}: '\nset -x\necho a\n", False),  # stricter: PS4 is expanded at run time
]


def run_shell(argv, text, cwd):
    p = os.path.join(cwd, "s.sh")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    for f in os.listdir(cwd):
        if f not in ("s.sh", "alias"):
            fp = os.path.join(cwd, f)
            if os.path.isdir(fp) and not os.path.islink(fp):
                shutil.rmtree(fp)
            else:
                os.unlink(fp)
    try:
        r = subprocess.run(argv + ["s.sh"], input=b"hello\n", capture_output=True, timeout=10, cwd=cwd,
                           env={"PATH": "/usr/bin:/bin", "HOME": cwd, "LC_ALL": "C"})
        out = (r.stdout + r.stderr).decode("utf-8", "replace")
        return out + ("\n<M-EXISTS>" if os.path.isdir(os.path.join(cwd, "M")) else "")
    except subprocess.TimeoutExpired:
        return "<timeout>"


def joined(out):
    """the oracle: the shell reached the last line AND skipped the mkdir (the alias continued the list)."""
    return "END" in out and "<M-EXISTS>" not in out


def run_helper(helper, dialect, text):
    r = subprocess.run([helper, "-dialect", dialect], input=text.encode(), capture_output=True, timeout=30)
    try:
        doc = json.loads(r.stdout.decode())
    except ValueError:
        doc = {}
    return r.returncode, doc


def split(doc, text, pline):
    units = doc.get("units") or []
    def unit_of(ln):
        for u in units:
            if u[0] <= ln <= u[1]:
                return tuple(u)
        return None
    a, b = unit_of(pline), unit_of(pline + 1)
    return a is not None and b is not None and a != b


SHELLS = {"posix": [["dash"], ["bash", "--posix"]], "bash": [["bash"]]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--helper", required=True)
    ap.add_argument("--out")
    ap.add_argument("--min-positive", type=int, default=200)
    a = ap.parse_args()
    for s in ("dash", "bash"):
        if not shutil.which(s):
            print("ENV: %s not on PATH" % s)
            return 2
    cwd = tempfile.mkdtemp(prefix="census.")
    open(os.path.join(cwd, "alias"), "w").close()   # a file named alias: pathname expansion of alia? / al[i]as
    rows, unsound, refused_claimed, positives = [], 0, 0, 0
    try:
        # control needles
        for d, shells in SHELLS.items():
            pre = "shopt -s expand_aliases\n" if d == "bash" else ""
            for sh in shells:
                if not joined(run_shell(sh, "false &&\nmkdir -p M\necho END\n", cwd)):
                    print("CONTROL FAILED: %s does not join a literal && continuation" % sh)
                    return 2
                if joined(run_shell(sh, pre + TAIL, cwd)):
                    print("CONTROL FAILED: %s joins without an alias" % sh)
                    return 2
        rc, doc = run_helper(a.helper, "posix", "echo hi\nmkdir -p M\n")
        if rc != 0 or not split(doc, "", 1):
            print("CONTROL FAILED: the helper does not split a plain two-line script: rc=%d %r" % (rc, doc))
            return 2
        cases = []
        for cid, dials, text in CHANNELS:
            for xid, ctx in CONTEXTS:
                body = ctx.replace("{D}", text)
                # every channel in a POSIX file (oracle: dash AND bash --posix, which runs bash-only syntax too)
                cases.append(("%s/%s/posix" % (cid, xid), "posix", body))
                if "bash" in dials.split() and xid in ("top", "func"):
                    # bash without posix mode expands aliases only after a switch: paired with a literal and with
                    # an expansion-built switch (each a separate case)
                    for pid, pre in (("shopt", "shopt -s expand_aliases"), ("shopt-built", "o=expand_; shopt -s ${o}aliases")):
                        cases.append(("%s/%s/bash+%s" % (cid, xid, pid), "bash", pre + "\n" + body))
        for eid, en in ENABLES:
            for cid, text in (("alias", D), ("ba", "BASH_ALIASES[p]=" + q(AV))):
                cases.append(("enable-%s+%s" % (eid, cid), "bash", en + "\n" + text))
        for cid, d, body in cases:
            text = body + "\n" + TAIL
            pline = text.count("\n", 0, len(body) + 1) + 1
            outs = [(" ".join(sh), run_shell(sh, text, cwd)) for sh in SHELLS[d]]
            hi = [n for n, o in outs if joined(o)]
            rc, doc = run_helper(a.helper, d, text)
            sp = rc == 0 and split(doc, text, pline)
            if hi and sp:
                cls = "UNSOUND"
                unsound += 1
            elif hi:
                cls = "POSITIVE-CLOSED"
                positives += 1
            else:
                cls = "INERT-split" if sp else "INERT-closed"
            rows.append((cid, d, ",".join(hi) or "-", "rc=%d" % rc, (doc.get("error") or "")[:90], cls))
        for bid, d, body, claimed in BENIGN:
            rc, doc = run_helper(a.helper, d, body)
            cls = "BENIGN-CREDITED" if rc == 0 else ("BENIGN-REFUSED-CLAIMED" if claimed else "BENIGN-REFUSED-STRICTER")
            if rc != 0 and claimed:
                refused_claimed += 1
            rows.append(("benign/" + bid, d, "-", "rc=%d" % rc, (doc.get("error") or "")[:90], cls))
    finally:
        shutil.rmtree(cwd, ignore_errors=True)
    lines = ["\t".join(r) for r in rows]
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write("id\tdialect\toracle_HI\thelper\terror\tclass\n" + "\n".join(lines) + "\n")
    for ln in lines:
        if "UNSOUND" in ln or "REFUSED-CLAIMED" in ln:
            print(ln)
    counts = {}
    for r in rows:
        counts[r[5]] = counts.get(r[5], 0) + 1
    print("SUMMARY cases=%d %s unsound=%d refused_claimed=%d positives=%d (min %d)"
          % (len(rows), " ".join("%s=%d" % kv for kv in sorted(counts.items())), unsound, refused_claimed,
             positives, a.min_positive))
    return 1 if (unsound or refused_claimed or positives < a.min_positive) else 0


if __name__ == "__main__":
    sys.exit(main())
