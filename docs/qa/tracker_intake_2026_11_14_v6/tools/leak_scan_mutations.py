#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_14_v6/tools/leak_scan_mutations.py -- paired mutation check (section
1.1) of tools/leak_scan.py: each mutant is one exact text replacement in a copy of the scan, written to a
temporary directory; the copy is run on an empty file, and its built-in control needles must stop it
(exit 3) before the file is read. A replacement that does not occur exactly once is a stale mutant and
fails the check. `assignment_broadened` makes a pattern too broad; the negative needle (a plain line
must not be reported) is what kills it. The last mutant breaks the hit report itself, which no needle
sees; it is checked by running the copy on a file that holds one fake hit and requiring the hit line.
Not mutated: deleting the call of the needles; on a correct scan that changes no output, so it is only
visible together with a second defect, which the pattern mutants above supply one at a time.

usage: leak_scan_mutations.py
Exit: 0 every mutant killed; 1 a mutant survived or is stale.
Evidence class: gate-logic only (section 11.4.289).
"""
import os
import subprocess
import sys
import tempfile

import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    ("private_key", r'r"-----BEGIN [A-Z ]*PRIVATE KEY-----"', r'r"-----BEGIN [A-Z ]*PRIVATE KEY-----X"'),
    ("aws_key", r"(?:AKIA|ASIA)[0-9A-Z]{16}", r"(?:AKIA|ASIA)[0-9A-Z]{17}"),
    ("github_token", r"gh[pousr]_[A-Za-z0-9]{30,}", r"gh[pousr]_[A-Za-z0-9]{40,}"),
    ("sk_key", r'r"\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}"', r'r"\bsk-(?:ant-)?[A-Za-z0-9_-]{30,}"'),
    ("slack", r"xox[abprs]-", r"xox[apr]-"),
    ("google", r"AIza[0-9A-Za-z_-]{35}", r"AIza[0-9A-Za-z_-]{36}"),
    ("url_cred", r"[^\s/:@'\"]+:[^\s/@'\"]+@", r"[^\s/:@'\"]+:[^\s/@'\"]+@@"),
    ("assignment_unquoted", r"""\s*[:=]\s*['\"]?[^\s'\"]{6,}""", r"""\s*[:=]\s*['\"][^\s'\"]{6,}"""),
    ("assignment_json_key", r"""\b['\"]?\s*[:=]""", r"""\b\s*[:=]"""),
    ("lint_kinds_dropped", "    SECRET.extend(k for k in lk[0]", "    [].extend(k for k in lk[0]"),
    ("auth_header", r"(?:basic|bearer)\s+", r"(?:bearer)\s+"),
    ("home_path", 'return [("home-path", re.compile(re.escape(home))),',
     'return [("home-path", re.compile(re.escape(home + "/nowhere"))),'),
    ("user_name", r'r"(?<![A-Za-z0-9])" + re.escape(user)', r'r"(?<![A-Za-z0-9])" + re.escape(user + "zz")'),
    ("assignment_broadened", r"""\s*[:=]\s*['\"]?[^\s'\"]{6,}""", r"""\s*[:=]?\s*['\"]?[^\s'\"]{0,}"""),
]
REPORT = ("report_dropped", '            print("HIT %s %s %s" % (src, where, show(kind, m)))\n', "            pass\n")


def main():
    src = open(os.path.join(HERE, "leak_scan.py"), encoding="utf-8").read()
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        empty = os.path.join(d, "empty.txt")
        open(empty, "w").close()
        hit = os.path.join(d, "hit.txt")
        with open(hit, "w", encoding="utf-8") as f:
            f.write("ghp_" + "z" * 36 + "\n")
        for name, old, new in MUTANTS + [REPORT]:
            if src.count(old) != 1:
                print("STALE %s: the text to replace occurs %d times" % (name, src.count(old)))
                bad += 1
                continue
            p = os.path.join(d, "m_%s.py" % name)
            with open(p, "w", encoding="utf-8") as f:
                f.write(src.replace(old, new))
            if (name, old, new) == REPORT:
                r = subprocess.run([sys.executable, "-I", p, "--file", hit], capture_output=True, text=True)
                killed = r.returncode != 0 or "HIT " not in r.stdout
            else:
                r = subprocess.run([sys.executable, "-I", p, "--file", empty], capture_output=True, text=True)
                killed = r.returncode == 3
            print("%s %s rc=%d" % ("KILLED" if killed else "SURVIVED", name, r.returncode))
            bad += 0 if killed else 1
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "leak_scan.py"), "--file", hit],
                           capture_output=True, text=True)
        if r.returncode != 0 or r.stdout.count("HIT ") != 1:
            print("CONTROL FAILED: the unmutated scan rc=%d hits=%d on the one-hit file" % (r.returncode, r.stdout.count("HIT ")))
            bad += 1
        else:
            print("CONTROL: the unmutated scan reports the one fake hit")
    print("RESULT: mutants=%d bad=%d" % (len(MUTANTS) + 1, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
