#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_15_v8/tools/leak_scan_mutations.py -- paired mutation check (section
1.1) of the round-8 independent leak scan (leak_scan.py in this directory).

Each mutant is one exact text replacement in a copy of the scan, written to a temporary directory. A
mutant is KILLED when either (a) the copy's own control needles stop it (exit 3 on an empty file), or
(b) leak_scan_test.py, run against the copy, fails (a shared-fixture "hit" row missed, exit 1). Two
mutants break the report itself: `report_dropped` (no HIT line) and `prints_match` (the matched text is
printed); they are checked on a file holding one fake hit: the HIT line must be there and no character
run of the fake value may appear. A replacement that does not occur exactly once is STALE and fails.
usage: leak_scan_mutations.py
Not mutated: the plain-line control of the scan's own needles; on a correct scan it changes no output,
the shared-fixture test's negative control (CONTROL_NEGATIVE) and SCAN_NEGATIVE rows judge the same thing.
Exit: 0 every mutant killed and the controls hold; 1 a mutant survived or is stale.
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
    ("cf_strip_dropped", 'if unicodedata.category(ch) != "Cf"', 'if True'),
    ("nfkc_dropped", 't = unicodedata.normalize("NFKC", text)', "t = text"),
    ("fold_dropped", 'return "".join(FOLD.get(ch, ch) for ch in t)', "return t"),
    ("unescape_views_dropped", "for v in (unescape(base), urllib.parse.unquote(base), unescape(urllib.parse.unquote(base))):",
     "for v in (urllib.parse.unquote(base),):"),
    ("percent_view_dropped", "for v in (unescape(base), urllib.parse.unquote(base), unescape(urllib.parse.unquote(base))):",
     "for v in (unescape(base),):"),
    ("quoted_value_dropped", "        q = QUOTED.match(rest)\n", "        q = None\n"),
    ("quoted_no_escape", r'((?:\\.|(?!\1)[^\n\\])*)', r'((?:(?!\1)[^\n\\])*)'),
    ("word_pwd_dropped", "pass(?:word|wd|phrase)?|pwd|secret", "pass(?:word|wd|phrase)?|secret"),
    ("word_token_dropped", "|secret|token|api", "|secret|api"),
    ("word_auth_dropped", r'apikey|auth|credentials?)', r'apikey|credentials?)'),
    ("filler_value_dropped", 'FILLER = {"value", ', 'FILLER = {'),
    ("minlen_9", "def value_ok(tok, minlen=8, letters_ok=False):", "def value_ok(tok, minlen=9, letters_ok=False):"),
    ("special_dropped", "    return letter and (digit or special or letters_ok)\n", "    return letter and (digit or letters_ok)\n"),
    ("digit_required_dropped", "    return letter and (digit or special or letters_ok)\n", "    return letter or digit\n"),
    ("quoted_letters_dropped", "letters_ok=True):", "letters_ok=False):"),
    ("url_case_dropped", 'URL = re.compile(r"(?i)\\b', 'URL = re.compile(r"\\b'),
    ("url_digits_dropped", r'or re.fullmatch(r"\d{6,}", pw)', 'or False'),
    ("short_flag_user_dropped", r'(-p|-u|--user)', r'(-p|-u)'),
    ("short_flag_joined_dropped", r'(?:\s|(?<=p))?', r'\s'),
    ("pgpass_star_dropped", r'(?:\d+|\*)', r'\d+'),
    ("pgpass_dropped", '        found += [("pgpass", m.group(1))', '        found += [] and [("pgpass", m.group(1))'),
    ("window_dropped", "        found += list(window_hits(t))\n", ""),
    ("key_rest_kept", 'rest = re.sub(r"^[A-Za-z0-9_]*", "", rest)', "rest = rest"),
    ("vendor_aws", r"(?:AKIA|ASIA)[0-9A-Z]{16}", r"(?:AKIA|ASIA)[0-9A-Z]{17}"),
    ("vendor_github", r"gh[pousr]_[A-Za-z0-9]{30,}", r"gh[pousr]_[A-Za-z0-9]{40,}"),
    ("vendor_slack", r"xox[abprs]-", r"xox[apr]-"),
    ("vendor_auth_header", r"(?:basic|bearer)\s+", r"(?:bearer)\s+"),
    ("home_path", 'return [("home-path", re.compile(re.escape(home))),',
     'return [("home-path", re.compile(re.escape(home + "/nowhere"))),'),
    ("user_name", r'r"(?<![A-Za-z0-9])" + re.escape(user)', r'r"(?<![A-Za-z0-9])" + re.escape(user + "zz")'),
]
REPORT = [
    ("report_dropped", '            print("HIT %s %s kind=%s len=%d" % (src, where, kind, len(m)))\n', "            pass\n"),
    ("prints_match", '            print("HIT %s %s kind=%s len=%d" % (src, where, kind, len(m)))\n',
     '            print("HIT %s %s kind=%s len=%d %s" % (src, where, kind, len(m), m[:6]))\n'),
]


def main():
    scan = os.path.join(HERE, "leak_scan.py")
    test = os.path.join(HERE, "leak_scan_test.py")
    src = open(scan, encoding="utf-8").read()
    bad = 0
    fake = "Zq7" + "Kw9Pq2Lm"
    with tempfile.TemporaryDirectory() as d:
        empty = os.path.join(d, "empty.txt")
        open(empty, "w").close()
        hit = os.path.join(d, "hit.txt")
        with open(hit, "w", encoding="utf-8") as f:
            f.write("DB_PASS" + "WORD=" + fake + "\n")
        for name, old, new in MUTANTS + REPORT:
            if src.count(old) != 1:
                print("STALE %s: the text to replace occurs %d times" % (name, src.count(old)))
                bad += 1
                continue
            p = os.path.join(d, "m_%s.py" % name)
            with open(p, "w", encoding="utf-8") as f:
                f.write(src.replace(old, new))
            if (name, old, new) in REPORT:
                r = subprocess.run([sys.executable, "-I", p, "--file", hit], capture_output=True, text=True)
                leaked = any(fake[i:i + 4] in r.stdout for i in range(len(fake) - 3))
                killed = r.returncode != 0 or "HIT " not in r.stdout or leaked
            else:
                r = subprocess.run([sys.executable, "-I", p, "--file", empty], capture_output=True, text=True)
                killed = r.returncode == 3
                if not killed:
                    t = subprocess.run([sys.executable, "-I", test, "--scan", p], capture_output=True, text=True)
                    killed = t.returncode != 0
            print("%s %s" % ("KILLED" if killed else "SURVIVED", name))
            bad += 0 if killed else 1
        r = subprocess.run([sys.executable, "-I", scan, "--file", hit], capture_output=True, text=True)
        leaked = any(fake[i:i + 4] in r.stdout for i in range(len(fake) - 3))
        if r.returncode != 0 or r.stdout.count("HIT ") < 1 or leaked:
            print("CONTROL FAILED: the unmutated scan on the one-hit file (rc=%d, leaked=%s)" % (r.returncode, leaked))
            bad += 1
        else:
            print("CONTROL: the unmutated scan reports the fake hit and prints none of it")
        t = subprocess.run([sys.executable, "-I", test], capture_output=True, text=True)
        if t.returncode != 0:
            print("CONTROL FAILED: leak_scan_test.py on the unmutated scan rc=%d" % t.returncode)
            bad += 1
        else:
            print("CONTROL: leak_scan_test.py passes on the unmutated scan")
    print("RESULT: mutants=%d bad=%d" % (len(MUTANTS) + len(REPORT), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
