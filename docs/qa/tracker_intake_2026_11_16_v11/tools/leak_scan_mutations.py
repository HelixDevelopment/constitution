#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_16_v11/tools/leak_scan_mutations.py -- paired mutation check (section
1.1) of the round-8 independent leak scan (leak_scan.py in this directory).

Each mutant is one exact text replacement in a copy of the scan, written to a temporary directory. A
mutant is KILLED when either (a) the copy's own control needles stop it (exit 3 on an empty file), or
(b) leak_scan_test.py, run against the copy, fails (a shared-fixture "hit" row missed, exit 1). Two
mutants break the report itself: `report_dropped` (no HIT line) and `prints_match` (the matched text is
printed); they are checked on a file holding one fake hit: the HIT line must be there and no character
run of the fake value may appear. A replacement that does not occur exactly once is STALE and fails.
Round 11: the scan reads key words through the shared module secret_canon.py; its mutants (CANON_MUTANTS)
are run on a copy passed through LEAK_SCAN_CANON; one the scan's own fixtures do not kill is then run
against the shared module's contract suite (tests/workable_items/test_secret_canon.py), and each KILLED
line names the oracle that killed it. Mutants of the removed token window are listed in
REMOVED_V10 and the round-10 reviewer's in REVIEWER_R10, each with its port.
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
CANON = os.path.join(HERE, "..", "..", "..", "..", "scripts", "workable-items", "secret_canon.py")
CANON_TEST = os.path.join(HERE, "..", "..", "..", "..", "tests", "workable_items", "test_secret_canon.py")
MUTANTS = [
    ('cf_strip_dropped', 'not in ("Cf", "Mn", "Me") and ch not in INVISIBLE', 'not in ("Mn", "Me") and ch not in INVISIBLE'),
    ('mn_strip_dropped', 'not in ("Cf", "Mn", "Me") and ch not in INVISIBLE', 'not in ("Cf",) and ch not in INVISIBLE'),
    ('invisible_dropped', 'ch not in INVISIBLE)', 'True)'),
    ('nfkc_dropped', '    t = unicodedata.normalize("NFKC", t)\n', ''),
    ('nfkd_dropped', 't = unicodedata.normalize("NFKD", text)', 't = text'),
    ('fold_dropped', 't = "".join(FOLD.get(ch, ch) for ch in t)', 't = t'),
    ('latin_by_name_dropped', 'return "".join(ch if ch.isascii() else latin(ch) for ch in t)', 'return t'),
    ('octal_dropped', '|\\\\[0-7]{3}|\\\\."', '|\\\\."'),
    ('tool_arg_dropped', '        for m in TOOL_ARG.finditer(t):\n', '        for m in []:\n'),
    ('minlen_9', 'def value_ok(tok, minlen=8, letters_ok=False):', 'def value_ok(tok, minlen=9, letters_ok=False):'),
    ('special_dropped', '    return letter and (digit or special or letters_ok)\n', '    return letter and (digit or letters_ok)\n'),
    ('digit_required_dropped', '    return letter and (digit or special or letters_ok)\n', '    return letter or digit\n'),
    ('url_case_dropped', 'URL = re.compile(r"(?i)\\b', 'URL = re.compile(r"\\b'),
    ('url_digits_dropped', 'or re.fullmatch(r"\\d{6,}", pw)', 'or False'),
    ('short_flag_user_dropped', '(-p|-u|--user|-a|-P)', '(-p|-u|-a|-P)'),
    ('short_flag_a_dropped', '(-p|-u|--user|-a|-P)', '(-p|-u|--user|-P)'),
    ('short_flag_joined_dropped', '(?:\\s|(?<=p))?', '\\s'),
    ('pgpass_star_dropped', '(?:\\d+|\\*)', '\\d+'),
    ('pgpass_dropped', '        found += [("pgpass", m.group(1))', '        found += [] and [("pgpass", m.group(1))'),
    ('vendor_aws', '(?:AKIA|ASIA)[0-9A-Z]{16}', '(?:AKIA|ASIA)[0-9A-Z]{17}'),
    ('vendor_github', 'gh[pousr]_[A-Za-z0-9]{30,}', 'gh[pousr]_[A-Za-z0-9]{40,}'),
    ('vendor_slack', 'xox[abprs]-', 'xox[apr]-'),
    ('vendor_auth_header', '(?:basic|bearer)\\s+', '(?:bearer)\\s+'),
    ('home_path', 'return [("home-path", re.compile(re.escape(home))),', 'return [("home-path", re.compile(re.escape(home + "/nowhere"))),'),
    ('user_name', 'r"(?<![A-Za-z0-9])" + re.escape(user)', 'r"(?<![A-Za-z0-9])" + re.escape(user + "zz")'),
    ('r10_fixpoint_dropped', '    for _ in range(64):\n', '    for _ in range(0):\n'),
    ('r10_brace_escape_dropped', 'r"\\\\[ux]\\{[0-9A-Fa-f]{1,6}\\}|\\\\U', 'r"\\\\U'),
    ('r10_long_escape_dropped', '\\}|\\\\U[0-9A-Fa-f]{8}|\\\\u', '\\}|\\\\u'),
    ('r10_hex_escape_dropped', '|\\\\x[0-9A-Fa-f]{2}|\\\\[0-7]{3}', '|\\\\[0-7]{3}'),
    ('r10_skeleton_dropped', 'FOLD.update({', 'dict({'),
    ('fix_unescape_dropped', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):', '        for f in (urllib.parse.unquote, html.unescape, join_literals, b64_runs):'),
    ('fix_percent_dropped', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):', '        for f in (unescape, html.unescape, join_literals, b64_runs):'),
    ('fix_html_dropped', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):', '        for f in (unescape, urllib.parse.unquote, join_literals, b64_runs):'),
    ('fix_join_dropped', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):', '        for f in (unescape, urllib.parse.unquote, html.unescape, b64_runs):'),
    ('fix_b64_dropped', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):', '        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals):'),
    # round 11: the set statement reports its own kind now, and the shared keyword reading can be cut
    ("r11_url_placeholder_read", ' and not CANON.is_placeholder(pw) \\', ' and True \\'),
    ("r11_set_cmd_dropped", '        found += [("set-command", m.group(1)) for m in SET_CMD.finditer(t)',
     '        found += [] and [("set-command", m.group(1)) for m in SET_CMD.finditer(t)'),
    ("r11_canon_call_dropped", "    for kind, s in CANON.hits(text):\n", "    for kind, s in []:\n"),
]
# round 11: mutants of the shared module secret_canon.py (the same list as the C-mutants of
# tests/workable_items/test_intake_lint_mutations.sh): the copy is passed to this scan through LEAK_SCAN_CANON
CANON_MUTANTS = [
    ('C25 r11 a number joins a split key word across a space', '            if k > 1 and lows[j + 1].isdigit() and re.search(', '            if False and lows[j + 1].isdigit() and re.search('),
    ('C26 r11 a URL user-info placeholder is a value', '"${<[(" and not is_placeholder(v) and not re.fullmatch', '"${" and not re.fullmatch'),
    ('C28 r11 an identifier needs letters-then-digits parts again', '(?=(?:[a-z0-9]+[_.-])*[a-z]{3,}(?:[_.-]|$))[a-z][a-z0-9]*(?:[_.-][a-z0-9]+)+$', '[a-z]+[0-9]*(?:[_.-](?:[a-z]+[0-9]*|[0-9]+))+$'),
    ('C29 r11 the attached join-negative words are keys again', '            if t == "short" and j > 0 and view[ws[j - 1][2]:ws[j][1]] == "" and lows[j - 1] in SHORT_JOIN_NEGATIVE:', '            if False:'),
    ('C30 r11 the suffix rules read joined forms too', '            t = word_tier(joined, prev, k == 1)', '            t = word_tier(joined, prev, True)'),
    ('C31 r11 a reference by name is a value', ' or _REF_NAME.match(v) or ', ' or '),
    ('C32 r11 a short key colon label is read', '    if tier == "short" and not quoted and op in (":", "\\uff1a"):\n        return False', '    if False:\n        return False'),
    ('C33 r11 the suffix join-negative prefix check off', ' and w[:-len(h)] not in SHORT_JOIN_NEGATIVE:', ':'),
    ('C27 r11 the value classifier keeps placeholders', '    if is_placeholder(v):\n        return False\n    literal', '    if False:\n        return False\n    literal'),
    ('SM1c fixpoint 16 -> 1 and layers 3 -> 0', 'SECRET_LAYERS = 3 ', 'SECRET_LAYERS = 0 '),
    ('SM1d full fixpoint 16 -> 1', '    for _ in range(16):\n        u = t', '    for _ in range(1):\n        u = t'),
    ('SM2c base64 run minimum 8 -> 20', '(?:[A-Za-z0-9+/]{4}){2,}(?:[A-Za-z0-9+/]{2}==', '(?:[A-Za-z0-9+/]{4}){5,}(?:[A-Za-z0-9+/]{2}=='),
    ('SM3c base64 decoded: half alnum -> three quarters', 'if sum(1 for c in s if c.isalnum()) * 2 < len(s):', 'if sum(1 for c in s if c.isalnum()) * 4 < len(s) * 3:'),
    ('SM4c base64 decoder dropped', '    lambda t: _B64.sub(lambda m: _blob(m, base64.b64decode), t),\n', ''),
    ('SM5c Mn marks kept', 'if cat in ("Mn", "Me", "Cf")', 'if cat in ("Me", "Cf")'),
    ('SM6c brace escapes dropped', '|\\\\u\\{([0-9A-Fa-f]{1,6})\\}|', '|\\\\u\\{(ZZZZ)\\}|'),
    ('SM7c long U escape dropped', '|\\\\U([0-9A-Fa-f]{8})|', '|\\\\U(ZZZZ)|'),
    ('SM8c join: & and ~ dropped', '(?:\\+|\\.\\.?|\\|\\||&|~)?\\s*\\1")', '(?:\\+|\\.\\.?|\\|\\|)?\\s*\\1")'),
    ('SM11c mot de passe dropped', '"credentials", "motdepasse",', '"credentials",'),
    ('SM13c set only at line start', '(?:^|[;\\[{\\n])[ \\t]*(?:set|setenv', '(?:^)[ \\t]*(?:set|setenv'),
    ('SM14c Cherokee small s dropped', '"\\uabaa": "s", ', ''),
    ('SM15c pin needs 5 digits', 'r"[0-9]{4,12}", v', 'r"[0-9]{5,12}", v'),
    ('K2a Mc placeholder dropped', '            r = MC_MARK', "            r = ''"),
    ('K3a squash off', 'SQUASH_MIN = 3 ', 'SQUASH_MIN = 99 '),
    ('K3b join max 4 -> 2', 'JOIN_MAX = 4 ', 'JOIN_MAX = 2 '),
    ('K4a wildcard: any share of ASCII', 'return asc * 2 >= len(w) and', 'return asc >= 0 and'),
    ('K6a value min 8 -> 6', '    if len(v) < 8 or len(v) > 4096:', '    if len(v) < 6 or len(v) > 4096:'),
    ('K6b ticket accepted', '(_IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"', '(_IDENT.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"'),
    ('K6c version accepted', '(_IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"', '(_IDENT.match(v) or _TICKET.match(v)):\n        return False\n    if tier == "space"'),
    ('K6d ref uri accepted', 'if _PATH.match(v) or _REF_URI.match(v) or', 'if _PATH.match(v) or'),
    ('SM10c dot separator dropped', '_JOINGAP = re.compile(r"^[ \\t_.\\-', '_JOINGAP = re.compile(r"^[ \\t_\\-'),
    ('SM12c tail loop never extends (ported: round 11 removed the cancel flag)', '            e = ws[q][2]\n            q += 1\n        out.append', '            break\n        out.append'),
    ('SM12d any attached word is a tail', '            if not (nw in TAIL_OK or nw.isdigit()', '            if not (True or nw.isdigit()'),
]
# round 11: v10 mutants whose text the round-11 rewrite removed (the token window and its word list); their
# intent is the shared module's and is covered by CANON_MUTANTS. Listed so a reader can follow each one.
REMOVED_V10 = ['string_prefix_dropped', 'quoted_value_dropped', 'quoted_no_escape', 'word_pwd_dropped', 'word_token_dropped', 'word_auth_dropped', 'word_qualified_key_dropped', 'word_one_odd_dropped', 'word_short_heads_dropped', 'one_odd_ascii_dropped', 'one_odd_nonascii_dropped', 'pin_rule_dropped', 'strong_letters_dropped', 'glued_dropped', 'filler_value_dropped', 'quoted_letters_dropped', 'window_dropped', 'key_rest_kept', 'r10_native_dropped', 'r10_split_word_dropped', 'r10_secret_string_dropped', 'r10_set_cmd_dropped', 'r10_colon_value_dropped', 'r10_digest_tail_dropped']
# the round-10 reviewer's scan mutants (review rev_ti10 tools/rev_mutants.py): their target text is gone from
# this scan (the token window and its decoder knobs); each one's port onto the shared module
REVIEWER_R10 = [
    ('SM1 fixpoint rounds 64 -> 2', 'SM1c, SM1d'),
    ('SM2 base64 run minimum 16 -> 20', 'SM2c'),
    ('SM3 base64 decoded minimum 8 -> 12', 'SM3c'),
    ('SM4 base64 colon form dropped', 'SM4c'),
    ('SM5 clean keeps Mn marks', 'SM5c'),
    ('SM6 brace escapes dropped', 'SM6c'),
    ('SM7 long U escape dropped', 'SM7c'),
    ("SM8 join: '&' and '~' dropped", 'SM8c'),
    ('SM9 triple quotes not read', 'SM9 has no knob in the shared module (contract K5-triple-quote)'),
    ('SM10 split word: dot separator dropped', 'SM10c'),
    ('SM11 mot de passe dropped', 'SM11c'),
    ('SM12 fingerprint tail no longer a property', 'SM12c, SM12d'),
    ('SM13 set command only at line start', 'SM13c'),
    ('SM14 Cherokee small s fold dropped', 'SM14c'),
    ('SM15 pin needs 5 digits', 'SM15c'),
    ('SM16 colon value window 8 -> 10', 'contract K5-colon-value (the layout reader reads a colon inside a value whole; no window length)'),
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
        canon_src = open(CANON, encoding="utf-8").read()
        for name, old, new in CANON_MUTANTS:
            if canon_src.count(old) != 1:
                print("STALE %s: the text to replace occurs %d times in secret_canon.py" % (name, canon_src.count(old)))
                bad += 1
                continue
            p = os.path.join(d, "c_%s.py" % name.split()[0])
            with open(p, "w", encoding="utf-8") as f:
                f.write(canon_src.replace(old, new))
            env = dict(os.environ, LEAK_SCAN_CANON=p)
            r = subprocess.run([sys.executable, "-I", scan, "--file", empty], capture_output=True, text=True, env=env)
            by = "needle" if r.returncode == 3 else ""
            if not by:
                t = subprocess.run([sys.executable, "-I", test, "--scan", scan], capture_output=True, text=True, env=env)
                by = "scan-fixtures" if t.returncode != 0 else ""
            if not by:
                # (c) the shared module's own contracts (tests/workable_items/test_secret_canon.py) on the
                # mutated copy: the module is one primitive read by the lint and by this scan, so its
                # contract suite is the oracle of both readers; the line says which oracle killed it
                k = subprocess.run([sys.executable, "-I", CANON_TEST, p], capture_output=True, text=True)
                by = "canon-contracts" if k.returncode != 0 else ""
            killed = bool(by)
            print("%s canon %s%s" % ("KILLED" if killed else "SURVIVED", name.split()[0], " (by %s)" % by if by else ""))
            bad += 0 if killed else 1
        for name, port in REVIEWER_R10:
            print("PORTED %s -> %s" % (name.split()[0], port))
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
    print("RESULT: mutants=%d canon_mutants=%d bad=%d" % (len(MUTANTS) + len(REPORT), len(CANON_MUTANTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
