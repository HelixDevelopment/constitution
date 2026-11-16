#!/usr/bin/env python3
"""tests/release/pvl_grid.py -- case grid for scripts/validation/check_provisional_verification_lines.py.

Usage: python3 -I tests/release/pvl_grid.py CHECKER WORKDIR
Run by tests/release/test_provisional_verification_lines.sh (section P7); not a test entry point.

It builds one fixture database (section 11.4.289(C)(2): gate-logic fixture) holding one item per case, runs CHECKER
on it once, and compares each item with its expectation:
  - refused cases (CON-423 review r1, B1, and the class around it): every placeholder shape in every one of the six
    fields, the per-field shape refusals, the due-date refusals, and a line inside a code fence; each case names the
    reason class the checker must print (a mutant that refuses for the wrong reason is caught);
  - accepted cases (golden FALSE, section 11.4.201(1)): honest UNCONFIRMED qualifiers after a complete value, the
    canon's colon-less form, words that only contain a placeholder string, and a fenced copy beside the real line.
Prints one `GRID-PASS <id> <case>` or `GRID-FAIL <id> <case>: <why>` line per case, then
`GRID cases=N refused=R accepted=A mismatches=M checker_rc=RC`. Exit 0 when M is 0, 1 otherwise, 2 when the
checker printed no CHECKED line (its output is not usable: a mismatch count of 0 there would prove nothing).
"""
import os
import sqlite3
import subprocess
import sys

FIELDS = ("job", "checks", "layer", "target", "artifact", "due")
GOOD = {"job": "re-run tests/release/x.sh on main", "checks": "3 passed, 0 failed", "layer": "host-only (tests)",
        "target": "host, repo checkout", "artifact": "commit 3b958793", "due": "2026-11-23"}

# shapes refused in every field, with the reason class the checker must print
ALL_FIELD_BAD = [
    ("empty", "", "is empty"), ("spaces", "   ", "is empty"), ("dot", ".", "is empty"),
    ("dash", "-", "is punctuation only"), ("endash", "–", "is punctuation only"),
    ("ellipsis", "...", "is empty"), ("ellipsis_char", "…", "is empty"),
    ("question", "?", "is punctuation only"), ("dashes", "- -", "is punctuation only"),
    ("TBD", "TBD", "is a placeholder"), ("tbd_lower", "tbd", "is a placeholder"), ("TBA", "TBA", "is a placeholder"),
    ("TODO", "TODO", "is a placeholder"), ("FIXME", "FIXME", "is a placeholder"), ("XXX", "XXX", "is a placeholder"),
    ("TBD_dot", "TBD.", "is a placeholder"), ("TODO_colon", "TODO: write it", "is a placeholder"),
    ("UNCONFIRMED_colon", "UNCONFIRMED:", "is a placeholder"),
    ("UNCONFIRMED_reason", "UNCONFIRMED: no job scheduled yet", "is a placeholder"),
    ("UNCONFIRMED_paren", "(UNCONFIRMED: not known)", "is a placeholder"),
    ("unknown", "Unknown", "is a placeholder"), ("pending", "pending", "is a placeholder"),
    ("pending_paren", "pending (scheduler down)", "is a placeholder"), ("na", "N/A", "is a placeholder"),
    ("none", "none", "is a placeholder"), ("none_yet", "none yet", "is a placeholder"),
    ("null", "null", "is a placeholder"), ("placeholder", "placeholder", "is a placeholder"),
    ("to_be_decided", "to be decided", "is a placeholder"), ("not_yet", "not yet scheduled", "is a placeholder"),
    ("fullwidth_TBD", "ＴＢＤ", "is a placeholder"), ("zwsp_TBD", "T​BD", "is a placeholder"),
    ("inside_TODO", "re-run the suite TODO later", "holds the placeholder word"),
    ("inside_FIXME", "commit 3b958793 FIXME", "holds the placeholder word"),
    ("template_angle", "<id>", "holds the template placeholder"),
    ("template_mustache", "{{job}} on main", "holds the template placeholder"),
    ("template_shell", "${JOB} on main", "holds the template placeholder"),
]
# per-field shape refusals (the value is not a placeholder, but names nothing of its kind)
FIELD_BAD = [
    ("job", "one_letter", "v", "does not name a job"), ("checks", "two_chars", "ok", "is too short"),
    ("target", "two_chars", "xy", "is too short"), ("layer", "unknown_layer", "foo (tests)", "does not start with a known layer"),
    ("layer", "glued_layer", "hostonly", "does not start with a known layer"),
    ("artifact", "no_ref", "the fix", "names no fingerprint or ref"),
    ("artifact", "hex_without_digit", "abcdefab", "names no fingerprint or ref"),
    ("due", "event", "next full-suite run", "is not a date"), ("due", "event2", "next tracker review", "is not a date"),
    ("due", "feb30", "2026-02-30", "is not a real calendar date"), ("due", "month13", "2026-13-01", "is not a real calendar date"),
    ("due", "year0", "0000-01-01", "is not a real calendar date"), ("due", "year1999", "1999-12-31", "has a year outside"),
    ("due", "year2100", "2100-01-01", "has a year outside"),
    ("due", "arabic_digits", "٢٠٢٦-١١-٢٣", "is not a date"),
    ("due", "fullwidth_digits", "２０２６-１１-２３", "is not a date"),
    ("due", "basic_format", "20261123", "is not a date"), ("due", "glued_letter", "2026-11-23x", "is not a date"),
    ("due", "week_date", "2026-W48-1", "is not a date"), ("due", "bad_time", "2026-11-23T25:00", "has an invalid time"),
    ("due", "leading_text", "by 2026-11-23", "is not a date"),
]
# accepted (golden FALSE): field -> value
ACCEPT = [
    ("due_qualifier", "due", "2026-11-23 (UNCONFIRMED: date set by the fixer; no scheduler entry exists)"),
    ("due_time_z", "due", "2026-11-23T10:00:00Z"), ("due_time_off", "due", "2026-11-23T10:00+01:00"),
    ("due_dot", "due", "2026-11-23."), ("due_prose", "due", "2026-11-23. Not VERIFIED-DONE; no review yet."),
    ("target_qualifier", "target", "host, repo checkout; consumer layout UNCONFIRMED here"),
    ("checks_one_word", "checks", "killed"), ("checks_none_of", "checks", "none of the mutants survives"),
    ("checks_pending_inside", "checks", "no pending lock remains"), ("job_id", "job", "JOB-42"),
    ("job_todolist", "job", "re-run the todolist view test"), ("job_tbdx", "job", "re-run TBDX_case suite"),
    ("target_na_region", "target", "na-west-2 runner"),
    ("layer_gate_logic", "layer", "gate-logic (test-instrumentation)"), ("layer_runtime", "layer", "runtime (host)"),
    ("layer_user_visible", "layer", "user-visible"), ("artifact_main", "artifact", "main containing 7c65b2c7"),
    ("artifact_vehicle", "artifact", "the commit that lands vehicle/census-safe"),
]


def line(vals, sep=" -- ", colon=True):
    return "**Verification:** provisional (section 11.4.290)" + "".join(
        sep + ("%s: %s" % (k, vals[k]) if colon else "%s %s" % (k, vals[k])) for k in FIELDS)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: pvl_grid.py CHECKER WORKDIR\n")
        return 64
    checker, work = argv[1], argv[2]
    cases = []  # (id, name, body, expected_reason or None)
    n = [0]

    def add(name, body, want):
        n[0] += 1
        cases.append(("CON-%04d" % (5000 + n[0]), name, body, want))

    for f in FIELDS:
        for name, val, want in ALL_FIELD_BAD:
            v = dict(GOOD)
            v[f] = val
            add("%s:%s" % (f, name), "x\n" + line(v), "field '%s' %s" % (f, want))
    for f, name, val, want in FIELD_BAD:
        v = dict(GOOD)
        v[f] = val
        add("%s:%s" % (f, name), "x\n" + line(v), "field '%s' %s" % (f, want))
    add("fence:only_inside", "x\n```\n" + line(GOOD) + "\n```", "no '**Verification:** provisional' line")
    add("fence:tilde_info", "x\n~~~text\n" + line(GOOD) + "\n~~~", "no '**Verification:** provisional' line")
    add("fence:unclosed", "x\n```\n" + line(GOOD), "no '**Verification:** provisional' line")
    add("fence:short_close_does_not_close", "x\n````\n```\n" + line(GOOD) + "\n````", "no '**Verification:** provisional' line")
    add("fence:two_real_lines", "x\n" + line(GOOD) + "\n" + line(GOOD), "2 verification lines")
    for name, f, val in ACCEPT:
        v = dict(GOOD)
        v[f] = val
        add("accept:" + name, "x\n" + line(v), None)
    add("accept:colonless_canon_emdash", "x\n" + line(GOOD, sep=" — ", colon=False), None)
    add("accept:colonless_dashes", "x\n" + line(GOOD, colon=False), None)
    mixed = "**Verification:** provisional — job: JOB-42 — checks 3 passed — layer: runtime — " \
            "target host — artifact: commit 3b958793 — due 2026-11-23"
    add("accept:mixed_forms", "x\n" + mixed, None)
    add("accept:fenced_copy_beside_real_line", "x\n" + line(GOOD) + "\n```\n" + line(GOOD) + "\n```", None)
    add("accept:after_closed_fence", "x\n```\ncode\n```\n" + line(GOOD), None)
    add("accept:extra_field", "x\n" + line(GOOD) + " -- note: kept", None)

    db = os.path.join(work, "grid.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    con.execute("create table items (atm_id text primary key, status text, body_md text)")
    con.executemany("insert into items values (?, 'Ready for testing', ?)", [(i, b) for i, _, b, _ in cases])
    con.commit()
    con.close()
    p = subprocess.run([sys.executable, "-I", checker, db], capture_output=True, text=True)
    if not any(ln.startswith("CHECKED ") for ln in p.stdout.splitlines()):
        print("GRID-BLIND the checker printed no CHECKED line (rc %d): %s" % (p.returncode, p.stderr[-300:]))
        return 2
    fails = {}
    for ln in p.stdout.splitlines():
        if ln.startswith("FAIL CON-"):
            head, _, reason = ln.partition(": ")
            fails[head.split()[1]] = reason
    mism = refused = 0
    for i, name, _, want in cases:
        got = fails.get(i)
        if want is None:
            ok = got is None
            why = "refused: %s" % got
        else:
            refused += 1
            ok = got is not None and got.startswith(want)
            why = "want '%s...', got %s" % (want, "'%s'" % got if got else "accepted")
        if ok:
            print("GRID-PASS %s %s" % (i, name))
        else:
            mism += 1
            print("GRID-FAIL %s %s: %s" % (i, name, why))
    print("GRID cases=%d refused=%d accepted=%d mismatches=%d checker_rc=%d"
          % (len(cases), refused, len(cases) - refused, mism, p.returncode))
    return 0 if mism == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
