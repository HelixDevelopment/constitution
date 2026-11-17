#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_16_v10/tools/leak_scan_mutations.py -- paired mutation check (section
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
    ("cf_strip_dropped", 'not in ("Cf", "Mn", "Me") and ch not in INVISIBLE', 'not in ("Mn", "Me") and ch not in INVISIBLE'),
    ("mn_strip_dropped", 'not in ("Cf", "Mn", "Me") and ch not in INVISIBLE', 'not in ("Cf",) and ch not in INVISIBLE'),
    ("invisible_dropped", "ch not in INVISIBLE)", "True)"),
    ("nfkc_dropped", '    t = unicodedata.normalize("NFKC", t)\n', ""),
    ("nfkd_dropped", 't = unicodedata.normalize("NFKD", text)', "t = text"),
    ("fold_dropped", 't = "".join(FOLD.get(ch, ch) for ch in t)', "t = t"),
    ("latin_by_name_dropped", 'return "".join(ch if ch.isascii() else latin(ch) for ch in t)', "return t"),
    ("octal_dropped", r'|\\[0-7]{3}|\\."', r'|\\."'),
    ("string_prefix_dropped", "(?:[bBrRuUfF]{1,2})?", ""),
    ("quoted_value_dropped", "        q = QUOTED.match(rest)\n", "        q = None\n"),
    ("quoted_no_escape", r'((?:\\.|(?!\1)[^\n\\])*)', r'((?:(?!\1)[^\n\\])*)'),
    ("word_pwd_dropped", "|kennwort|pwd|secret|", "|kennwort|secret|"),
    ("word_token_dropped", "|secret|token|api", "|secret|api"),
    ("word_auth_dropped", r'apikey|auth|"', r'apikey|"'),
    ("word_qualified_key_dropped", r'shared|session|hmac|jwt|aes|storage)[ _-]?key|', r'shared|session|hmac|jwt|aes|storage)[ _-]?keyQQ|'),
    ("word_one_odd_dropped", '+ _one_odd("password") + "|" + _one_odd("passwd") +', '+ "zzzz" +'),
    ("word_short_heads_dropped", r'|(?<![A-Za-z])(?:key|pin|session|sid|cookie)(?![A-Za-z]))', r'|(?<![A-Za-z])(?:zzzz)(?![A-Za-z]))'),
    ("one_odd_ascii_dropped", r'"(?:[^\\W\\d_]|[^\\x00-\\x7f])"', r'"[^\\x00-\\x7f]"'),
    ("one_odd_nonascii_dropped", r'"(?:[^\\W\\d_]|[^\\x00-\\x7f])"', r'"[^\\W\\d_]"'),
    ("pin_rule_dropped", '            if m.group(1).lower() == "pin":\n', '            if False:\n'),
    ("strong_letters_dropped", "(strong and re.fullmatch(", "(False and re.fullmatch("),
    ("glued_dropped", '                 and re.search(r"[A-Za-z]{2,}[_.-]?$"', '                 and False and re.search(r"[A-Za-z]{2,}[_.-]?$"'),
    ("tool_arg_dropped", "        for m in TOOL_ARG.finditer(t):\n", "        for m in []:\n"),
    ("filler_value_dropped", 'FILLER = {"value", ', 'FILLER = {'),
    ("minlen_9", "def value_ok(tok, minlen=8, letters_ok=False):", "def value_ok(tok, minlen=9, letters_ok=False):"),
    ("special_dropped", "    return letter and (digit or special or letters_ok)\n", "    return letter and (digit or letters_ok)\n"),
    ("digit_required_dropped", "    return letter and (digit or special or letters_ok)\n", "    return letter or digit\n"),
    ("quoted_letters_dropped", "letters_ok=True):", "letters_ok=False):"),
    ("url_case_dropped", 'URL = re.compile(r"(?i)\\b', 'URL = re.compile(r"\\b'),
    ("url_digits_dropped", r'or re.fullmatch(r"\d{6,}", pw)', 'or False'),
    ("short_flag_user_dropped", r'(-p|-u|--user|-a|-P)', r'(-p|-u|-a|-P)'),
    ("short_flag_a_dropped", r'(-p|-u|--user|-a|-P)', r'(-p|-u|--user|-P)'),
    ("short_flag_joined_dropped", r'(?:\s|(?<=p))?', r'\s'),
    ("pgpass_star_dropped", r'(?:\d+|\*)', r'\d+'),
    ("pgpass_dropped", '        found += [("pgpass", m.group(1))', '        found += [] and [("pgpass", m.group(1))'),
    ("window_dropped", "        found += list(window_hits(t))\n", ""),
    ("key_rest_kept", "        rest = rest[len(tail):]", "        rest = rest"),
    ("vendor_aws", r"(?:AKIA|ASIA)[0-9A-Z]{16}", r"(?:AKIA|ASIA)[0-9A-Z]{17}"),
    ("vendor_github", r"gh[pousr]_[A-Za-z0-9]{30,}", r"gh[pousr]_[A-Za-z0-9]{40,}"),
    ("vendor_slack", r"xox[abprs]-", r"xox[apr]-"),
    ("vendor_auth_header", r"(?:basic|bearer)\s+", r"(?:bearer)\s+"),
    ("home_path", 'return [("home-path", re.compile(re.escape(home))),',
     'return [("home-path", re.compile(re.escape(home + "/nowhere"))),'),
    ("user_name", r'r"(?<![A-Za-z0-9])" + re.escape(user)', r'r"(?<![A-Za-z0-9])" + re.escape(user + "zz")'),
    # round 10: one mutant per part the round-10 scan added
    ("r10_fixpoint_dropped", "    for _ in range(64):\n", "    for _ in range(0):\n"),
    ("r10_brace_escape_dropped", r'r"\\[ux]\{[0-9A-Fa-f]{1,6}\}|\\U', r'r"\\U'),
    ("r10_long_escape_dropped", r'\}|\\U[0-9A-Fa-f]{8}|\\u', r'\}|\\u'),
    ("r10_hex_escape_dropped", r'|\\x[0-9A-Fa-f]{2}|\\[0-7]{3}', r'|\\[0-7]{3}'),
    ("r10_skeleton_dropped", "FOLD.update({", "dict({"),
    ("r10_native_dropped", 'secret[ _-]?string|" + NATIVE_RX + "|"', 'secret[ _-]?string|"'),
    ("r10_split_word_dropped", 'r"(?i)(pass[ _.-]?word|', 'r"(?i)(passQQword|'),
    ("r10_secret_string_dropped", "|secret[ _-]?string|", "|secretQQstring|"),
    ("r10_set_cmd_dropped", '        found += [("credential-window", m.group(1)) for m in SET_CMD.finditer(t)',
     '        found += [] and [("credential-window", m.group(1)) for m in SET_CMD.finditer(t)'),
    ("r10_colon_value_dropped", "        if u and value_ok(u.group(1)) and not", "        if False and u and value_ok(u.group(1)) and not"),
    ("r10_digest_tail_dropped", "            continue  # a property of the credential", "            pass  # a property of the credential"),
    ("fix_unescape_dropped", "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):",
     "        for f in (urllib.parse.unquote, html.unescape, join_literals, b64_runs):"),
    ("fix_percent_dropped", "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):",
     "        for f in (unescape, html.unescape, join_literals, b64_runs):"),
    ("fix_html_dropped", "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):",
     "        for f in (unescape, urllib.parse.unquote, join_literals, b64_runs):"),
    ("fix_join_dropped", "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):",
     "        for f in (unescape, urllib.parse.unquote, html.unescape, b64_runs):"),
    ("fix_b64_dropped", "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):",
     "        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals):"),
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
