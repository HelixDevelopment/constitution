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
`GRID cases=N refused=R accepted=A mismatches=M checker_rc=RC`. Since CON-423 r4 the grid also holds the r4 cases
(R4, R4_ACCEPT; R4_ROOT runs the checker a second time with --root set to the repository root) and a fixed sample of
the character-class inventory of tests/release/pvl_inventory.py (cases named inv:<class>:<n>). Exit 0 when M is 0, 1 otherwise, 2 when the
checker printed no CHECKED line (its output is not usable: a mismatch count of 0 there would prove nothing).
"""
import json
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
    ("job_todolist", "job", "re-run the todolist view test tests/ui/todolist_view.sh"), ("job_tbdx", "job", "re-run TBDX_case suite tests/tbdx_case.sh"),
    ("target_na_region", "target", "na-west-2 runner"),
    ("layer_gate_logic", "layer", "gate-logic (test-instrumentation)"), ("layer_runtime", "layer", "runtime (host)"),
    ("layer_user_visible", "layer", "user-visible"), ("artifact_main", "artifact", "main containing 7c65b2c7"),
    ("artifact_vehicle", "artifact", "the commit that lands vehicle/census-safe"),
]

# CON-423 review r2 (B2, round 3, structural): the reviewer's probe bin/probe_pvl2.py (74 cases, sha256 of its output
# d71cd775893a7bacfd95a9f66825bf09d27a510b431139e14ac66937b388d447), replayed case by case. Expectations are the
# reviewer's, with three recorded changes: the debatable cases (lorem, "to be done", "will be scheduled later") and the
# "?"-marked ones are decided (refused), and "re-run DRAFTS check" is now refused for its SHAPE (it names no command,
# path or job id; the property it guarded, DRAFTS is no placeholder, is kept by accept:job_drafts_path below).
CYR_T, CYR_O, CYR_E, CYR_P, CYR_X = "Т", "о", "е", "р", "х"
REVIEWER = []  # (name, field, value, want) want None = accepted, else a reason prefix ("field '<f>' ..." is added)
for _f in FIELDS:
    REVIEWER.append(("cyr_TBD_" + _f, _f, CYR_T + "BD-1" if _f == "job" else CYR_T + "BD commit 3b958793"
                     if _f == "artifact" else CYR_T + "BD x y", "" if _f in ("layer", "due") else "is a placeholder"))
for _f in ("job", "checks", "target"):
    for _n, _v in (("pending_sched", "pending scheduling"), ("none_assigned", "none assigned"),
                   ("not_applicable", "not applicable"), ("lorem", "lorem ipsum dolor"), ("TBD_underscore", "TBD_1 later"),
                   ("T.B.D", "T.B.D."), ("unknown_word", "unknown host thing"), ("to_be_done", "to be done"),
                   ("will_be", "will be scheduled later"), ("XXX_lower", "xxx yyy")):
        REVIEWER.append((_n + "_" + _f, _f, _v, "is a placeholder"))
    REVIEWER.append(("qqq_" + _f, _f, "??? later", "starts with no word"))
REVIEWER += [
    ("artifact_TBD_main", "artifact", "TBD main", "is a placeholder"),
    ("artifact_lorem_main", "artifact", "lorem main", "is a placeholder"),
    ("layer_runtime_cyr", "layer", "runtim" + CYR_E, "does not start with a known layer"),
    ("due_leap2000", "due", "2000-02-29", None), ("due_2100", "due", "2100-01-01", "has a year outside"),
    ("due_13", "due", "2026-13-01", "is not a real calendar date"), ("due_time_ok", "due", "2026-11-23T10:00Z", None),
    ("due_time_25", "due", "2026-11-23T25:00", "has an invalid time"), ("due_time_space", "due", "2026-11-23 10:00", None),
    ("due_time_offset", "due", "2026-11-23T10:00:00+02:00", None),
    ("due_fullwidth", "due", "２０２６-11-23", "is not a date"),
    ("due_zwsp_lead", "due", "​2026-11-23", "is not a date"),
    ("due_unconfirmed_trailing", "due", "2026-11-23 (UNCONFIRMED: no scheduler)", None),
    ("due_tbd_after", "due", "2026-11-23 TBD", "holds the placeholder word"),
    ("due_date_slash", "due", "2026/11/23", "is not a date"),
    ("job_unconfirmed_trailing", "job", "re-run x.sh (UNCONFIRMED: not scheduled)", None),
    ("job_UNCONFIRMED_lower", "job", "unconfirmed: none", "is a placeholder"),
    ("job_bracket_tbd", "job", "[TBD]", "is a placeholder"), ("job_quoted_todo", "job", "\"TODO\"", "is a placeholder"),
    ("job_none_paren", "job", "none (scheduler down)", "is a placeholder"),
    ("job_DRAFTS_now_shape", "job", "re-run DRAFTS check", "does not name a job"),
    ("job_XTBD_golden", "job", "XTBD-9 run", None),
    ("checks_fw_todo", "checks", "ＴＯＤＯ later", "is a placeholder"),
    ("target_zwj_tbd", "target", "T‍BD host", "is a placeholder"),
    ("artifact_hex_only_ok", "artifact", "3b958793", None), ("layer_gate_logic", "layer", "gate-logic", None),
]
_V = "**Verification:** provisional -- job: re-run x.sh -- checks: 3 passed -- layer: host-only -- target: host -- " \
     "artifact: main -- due: 2026-11-23"
NOLINE = "no '**Verification:** provisional' line"
REVIEWER_BODY = [  # (name, body, want) want None = accepted, else the full reason prefix
    ("html_comment_only", "x\n<!--\n" + _V + "\n-->", NOLINE),
    ("tilde_fence_only", "x\n~~~\n" + _V + "\n~~~", NOLINE),
    ("nested_fence", "x\n````\n```\n````\n" + _V, None),
    ("indented3_fence", "x\n   ```\n" + _V + "\n   ```", NOLINE),
    ("indented4_notfence", "x\n    ```\n" + _V, None),
    ("colonless", "x\n" + _V.replace("provisional -- ", "provisional — ").replace(": ", " ").replace(" -- ", " — "), None),
    ("colonless_tbd", "x\n**Verification:** provisional — job TBD — checks 3 passed — layer host-only — "
                      "target host — artifact main — due 2026-11-23", "field 'job' is a placeholder"),
    ("prefix_glued", "x\n" + _V.replace("provisional --", "provisionalXYZ --"), NOLINE),
    ("extra_unknown_field", "x\n" + _V + " -- note: TBD", None),
]

# CON-423 r3 own cases (the fixer's, not the reviewer's): one or more per axis of
# docs/qa/rehearsal_v73_4_fix/r3/class_inventory.md (A1 to A18), with golden FALSE beside each refusal class.
OWN = [
    # A6 punctuation-split acronyms, A7 glued digits/underscores, A8 digit look-alikes
    ("A6_dash_acronym", "job", "T-B-D", "is a placeholder"), ("A6_space_acronym", "job", "T B D run", "is a placeholder"),
    ("A6_lower_dots", "target", "t.b.d", "is a placeholder"), ("A6_spaced_dots", "checks", "T. B. D. later", "is a placeholder"),
    ("A6_inside_joined", "checks", "3 passed T.B.D. later", "holds the placeholder word"),
    ("A6_underscore_acronym", "artifact", "t_b_d commit 3b958793", "is a placeholder"),
    ("A7_digit_glued", "job", "TBD1 run", "is a placeholder"), ("A7_my_todo_inside", "job", "re-run MY_TODO tests/x.sh", "holds the placeholder word"),
    ("A7_fixme2_inside", "checks", "3 passed FIXME2", "holds the placeholder word"),
    ("A8_t0d0", "job", "T0D0 later", "is a placeholder"), ("A8_f1xme_inside", "checks", "3 passed F1XME", "holds the placeholder word"),
    # A2/A3/A4/A5 leading words and phrases per field
    ("A4_none_yet_glued", "job", "none-yet", "is a placeholder"), ("A4_pending_underscore", "target", "pending_scheduling", "is a placeholder"),
    ("A4_not_applicable_glued", "artifact", "not-applicable", "is a placeholder"),
    ("A4_none_yet_note", "checks", "none-yet (scheduler down)", "is a placeholder"),
    ("A5_no_job_yet", "job", "no job yet", "is a placeholder"), ("A5_not_run", "job", "not run yet", "is a placeholder"),
    ("A5_should_be", "job", "should be scheduled", "is a placeholder"), ("A5_not_yet_built", "artifact", "not yet built main", "is a placeholder"),
    ("A5_checks_not_run", "checks", "not run yet", "is a placeholder"), ("A5_checks_to_be", "checks", "to be measured", "is a placeholder"),
    ("A2_later", "job", "later", "is a placeholder"), ("A2_soon", "target", "soon host", "is a placeholder"),
    ("A2_dummy", "job", "dummy tests/x.sh", "is a placeholder"), ("A2_asap", "checks", "asap", "is a placeholder"),
    ("A2_pending_image", "artifact", "pending image", "is a placeholder"), ("A2_none_commit", "artifact", "none commit 3b958793", "is a placeholder"),
    ("A2_checks_pending", "checks", "pending", "is a placeholder"), ("A2_checks_none_yet", "checks", "none yet", "is a placeholder"),
    # A9 to A11 folding
    ("A9_fullwidth_dots", "job", "Ｔ.Ｂ.Ｄ.", "is a placeholder"),
    ("A10_cyr_todo", "job", CYR_T + CYR_O + "d" + CYR_O + " later", "is a placeholder"),
    ("A10_cyr_pending", "job", CYR_P + "ending x", "is a placeholder"), ("A10_cyr_none", "target", "n" + CYR_O + "ne assigned", "is a placeholder"),
    ("A10_cyr_xxx", "checks", CYR_X + "xx yyy", "is a placeholder"), ("A10_greek_none", "target", "Νone host", "is a placeholder"),
    ("A11_combining_tbd", "job", "T̈BD x", "is a placeholder"), ("A11_accent_pending", "target", "pénding host", "is a placeholder"),
    # A12 wrappers, A14 punctuation-led
    ("A12_star_none", "job", "*none* x", "is a placeholder"), ("A12_backtick_tbd", "artifact", "`TBD` main", "is a placeholder"),
    ("A14_dashes_later", "job", "--- later", "starts with no word"), ("A14_endash_later", "target", "\u2013\u2013 later", "starts with no word"),
    ("A2_ellipsis_then_later", "target", "\u2026 later", "is a placeholder"),
    ("A14_question_checks", "checks", "?? x", "starts with no word"),
    # A16 job positive shape, A17 target positive shape
    ("A16_rerun_suite", "job", "re-run the suite", "does not name a job"), ("A16_lorem_free", "job", "ipsum dolor sit", "does not name a job"),
    ("A16_cyr_path", "job", "re-run t" + CYR_E + "sts/x.sh", "does not name a job"),
    ("A16_make_word", "job", "make check", "does not name a job"),
    ("A17_somewhere", "target", "somewhere", "names no target"), ("A17_usual", "target", "the usual", "names no target"),
    ("A17_cyr_host", "target", CYR_X + CYR_O + "ст", "names no target"),
    ("A10_cyr_commit_artifact", "artifact", "\u0441ommit of the fix", "names no fingerprint or ref"),
    ("A10_cyr_host_target", "target", "\u04bb\u043e\u0455t", "names no target"),
    # reviewer survivors X4, X5 (value forms), X6 (single-word job)
    ("X4_xxx_inside_artifact", "artifact", "commit 3b958793 XXX", "holds the placeholder word"),
    ("X5_tba_inside_checks", "checks", "x TBA y", "holds the placeholder word"),
    ("X6_single_word_job", "job", "later", "is a placeholder"),
    ("X6_single_word_job2", "job", "rerun", "does not name a job"),
]
OWN_ACCEPT = [
    ("job_go_test", "job", "go test ./..."), ("job_python_m", "job", "python3 -m pytest tests"),
    ("job_bash_n", "job", "bash -n scripts/x.sh"), ("job_id", "job", "JOB-7"), ("job_file_token", "job", "re-run t.sh"),
    ("job_drafts_path", "job", "re-run DRAFTS check tests/drafts_check.sh"),
    ("job_xtbd_path", "job", "XTBD-9 run"),
    ("checks_NOT_ok", "checks", "NOT ok tool docstring still says EVERY"), ("checks_none_of2", "checks", "none of 5 mutants survive"),
    ("checks_prose", "checks", "real-tree census byte-identical across census variants"),
    ("checks_unknown_compound_statement", "checks", "unknown-id-only table gives rc 1 and RESULT: KNOWN-STALE"),
    ("checks_pending_compound_statement", "checks", "pending-lock check passes 4/4"),
    ("target_board", "target", "board 6c2f serial"), ("target_container", "target", "container rootless podman"),
    ("target_ci_runner", "target", "CI runner"), ("target_remotes", "target", "the eight upstream remotes"),
    ("artifact_tag", "artifact", "tag v73.4"), ("artifact_main_hex", "artifact", "main containing 3b958793"),
]
OWN_BODY = [
    ("X1_tilde_does_not_close_backtick", "x\n```\n~~~\n" + _V + "\n```", NOLINE),
    ("X2_info_line_does_not_close", "x\n```\n```text\n" + _V + "\n```", NOLINE),
    ("X3_four_spaces_no_fence", "x\n    ```\n" + _V + "\n", None),
    ("N1_comment_two_lines", "x\n<!-- hidden\n" + _V + "\n-->", NOLINE),
    ("N1_comment_indented", "x\n  <!--\n" + _V + "\n-->", NOLINE),
    ("N1_comment_unclosed", "x\n<!--\n" + _V, NOLINE),
    ("N1_comment_three_lines", "x\n<!--\nhidden\n" + _V + "\n-->", NOLINE),
    ("N1_one_line_comment_then_real", "x\n<!-- note -->\n" + _V, None),
    ("N1_closed_comment_then_real", "x\n<!--\nhidden\n-->\n" + _V, None),
    ("N1_comment_in_fence_is_code", "x\n```\n<!--\n```\n" + _V, None),
    ("N3_prefix_hyphen", "x\n" + _V.replace("provisional --", "provisional-ish --"), NOLINE),
    ("R22_field_order", "x\n" + _V.replace("-- checks: 3 passed -- layer: host-only", "-- layer: host-only -- checks: 3 passed"),
     "fields out of order"),
    ("N3_prefix_paren_ok", "x\n" + _V.replace("provisional --", "provisional (section 11.4.290) --"), None),
]

# CON-423 r4 (review r3: B1, B2, B3, F1 to F4, R10, R12); one case or more per new axis A20 to A25 of
# docs/qa/rehearsal_v73_4_fix/r4/class_inventory.md, golden FALSE beside each refusal
R4 = [
    ("B1_slash", "checks", "T/B/D later", "is a placeholder"), ("B1_comma", "job", "T,B,D x.sh", "is a placeholder"),
    ("B1_pipe", "target", "T|B|D host", "is a placeholder"), ("B1_middot", "checks", "T\u00b7B\u00b7D later", "is a placeholder"),
    ("B1_bullet", "artifact", "T\u2022B\u2022D main", "is a placeholder"), ("B1_uhyphen", "job", "T\u2010B\u2010D x.sh", "is a placeholder"),
    ("B1_inside_slash", "checks", "every suite T/B/D", "holds the placeholder word"),
    ("B1_todo_plus", "checks", "T+O+D+O later", "is a placeholder"),
    ("B2_none_yet", "job", "none/yet", "is a placeholder"), ("B2_pending_sched", "job", "pending/scheduling", "is a placeholder"),
    ("B2_to_be", "job", "to/be/scheduled", "is a placeholder"), ("B2_na_na", "job", "n.a/n.a", "is a placeholder"),
    ("B2_pending_sh", "job", "pending.sh", "is a placeholder"), ("B2_none_sh", "job", "none.sh", "is a placeholder"),
    ("B2_sometime_maybe", "job", "sometime/maybe", "does not name a job"),
    ("B3_hangul_filler", "checks", "\u3164", "is empty"), ("B3_hangul_choseong", "target", "\u115f host", "holds an invisible"),
    ("B3_filler_inside", "checks", "3 pas\u3164sed", "holds an invisible"), ("B3_halfwidth_filler", "job", "T\uffa0BD x.sh", "is a placeholder"),
    ("F2_abs_outside_shape", "job", "bash ../x.sh", "does not name a job"),
    ("F3_host_later", "target", "host later", "ends with a placeholder"), ("F3_host_paren", "target", "host (pending)", "ends with a placeholder"),
    ("F3_host_none", "target", "host? none", "ends with a placeholder"),
    ("F3_note", "target", "host (pending scheduler)", "holds a placeholder note"),
    ("F4_foo", "checks", "foo bar baz", "names no outcome"), ("F4_limit", "checks", "limit", "names no outcome"),
    ("R10_one_letter_key", "job", "A-1", "does not name a job"), ("R12_hex6", "artifact", "abc123", "names no fingerprint"),
    ("R5_underscore_compound", "checks", "a_b_c_tbd 3 passed", "holds the placeholder word"),
    ("R19_greek_rho", "job", "\u03c1ending x.sh", "is a placeholder"),
    ("O03_compat_inside_word", "target", "TO\u249fO host", "is a placeholder"),
    ("O05_arabic_zero_reading", "checks", "T\u0660D\u0660 later", "is a placeholder"),
    ("O07_small_capitals", "target", "\u1d1b\u0299\u1d05 host", "is a placeholder"),
    ("O09_note_single_letters", "target", "host (p.e.n.d.i.n.g) x", "holds a placeholder note"),
    ("O20_lead_only_note", "target", "nobody (host)", "is a placeholder"),
    ("mixed_script", "checks", "3 \u0440assed", "mixes scripts"), ("other_script", "checks", "3 passed \u05d0", "uses"),
]
R4_ACCEPT = [
    ("R10_two_letter_key", "job", "AB-1"), ("R12_hex7", "artifact", "abc1234"),
    ("no_review_yet", "checks", "no review yet, 3 passed"), ("middot_between", "checks", "3 passed \u00b7 4 failed"),
    ("oe_ligature", "checks", "3 passed \u0153"), ("cyrillic_word", "checks", "3 passed \u0442\u0435\u0441\u0442"),
    ("na_west", "target", "na-west-2 runner"), ("checks_ends_none", "checks", "3 mutants killed, survivors none"),
    ("tab_separates", "checks", "3\tpassed"), ("strong_inside_word_ok", "checks", "todolist 3 passed"), ("combining_ok", "checks", "3 pas\u0301sed"),
]
# with --root (the repository root of this file): an absolute or escaping path never counts, an existing one does
R4_ROOT = [
    ("F2_etc_passwd", "job", "/etc/passwd", "does not name a job"), ("F2_bash_etc", "job", "bash /etc/passwd", "does not name a job"),
    ("F2_dotdot", "job", "docs/..", "does not name a job"), ("F2_missing", "job", "scripts/nonexistent.sh", "does not name a job"),
    ("F2_ask_operator", "job", "ask/operator", "does not name a job"),
    ("F2_dotdot_inside", "job", "docs/../scripts/validation/check_provisional_verification_lines.py", "does not name a job"),
    ("F2_real_path", "job", "python3 -I scripts/validation/check_provisional_verification_lines.py --root .", None),
]


def line(vals, sep=" -- ", colon=True):
    return "**Verification:** provisional (section 11.4.290)" + "".join(
        sep + ("%s: %s" % (k, vals[k]) if colon else "%s %s" % (k, vals[k])) for k in FIELDS)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: pvl_grid.py CHECKER WORKDIR\n")
        return 64
    checker, work = argv[1], argv[2]
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    cases = []  # (id, name, body, expected_reason or None, run with --root)
    n = [0]

    def add(name, body, want, root=False):
        n[0] += 1
        cases.append(("CON-%04d" % (5000 + n[0]), name, body, want, root))

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

    for name, f, val, want in REVIEWER + OWN:
        v = dict(GOOD)
        v[f] = val
        add("r3:%s" % name, "x\n" + line(v), None if want is None else "field '%s' %s" % (f, want))
    for name, f, val in OWN_ACCEPT:
        v = dict(GOOD)
        v[f] = val
        add("r3:accept:%s" % name, "x\n" + line(v), None)
    for name, body, want in REVIEWER_BODY + OWN_BODY:
        add("r3:body:%s" % name, body, want)
    for name, f, val, want in R4:
        v = dict(GOOD)
        v[f] = val
        add("r4:%s" % name, "x\n" + line(v), None if want is None else "field '%s' %s" % (f, want))
    for name, f, val in R4_ACCEPT:
        v = dict(GOOD)
        v[f] = val
        add("r4:accept:%s" % name, "x\n" + line(v), None)
    for name, f, val, want in R4_ROOT:
        v = dict(GOOD)
        v[f] = val
        add("r4:root:%s" % name, "x\n" + line(v), None if want is None else "field '%s' %s" % (f, want), root=True)
    rr = dict(GOOD)
    rr["job"] = "bash " + repo_root
    add("r4:root:F2_root_itself", "x\n" + line(rr), "field 'job' does not name a job", root=True)
    long = dict(GOOD)
    long["checks"] = "3 passed " + "x" * 4100
    add("r4:body:line_too_long", "x\n" + line(long), "the verification line is longer than 4096")
    # the inventory sample does not depend on the checker: computed once per WORKDIR (about 15 s), then read back, so
    # the paired mutants of the test do not rebuild it; the file is written by this script only
    cache = os.path.join(work, "pvl_inventory_sample.json")
    if os.path.exists(cache):
        with open(cache, encoding="utf-8") as fh:
            sample = json.load(fh)
    else:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import pvl_inventory
        sample = pvl_inventory.sample_cases()
        with open(cache + ".tmp", "w", encoding="utf-8") as fh:
            json.dump(sample, fh)
        os.replace(cache + ".tmp", cache)
    for name, f, val, want in sample:
        v = dict(GOOD)
        v[f] = val
        add(name, "x\n" + line(v), want)

    fails, rcs = {}, []
    for with_root in (False, True):
        db = os.path.join(work, "grid_root.db" if with_root else "grid.db")
        if os.path.exists(db):
            os.remove(db)
        con = sqlite3.connect(db)
        con.execute("create table items (atm_id text primary key, status text, body_md text)")
        con.executemany("insert into items values (?, 'Ready for testing', ?)",
                        [(c[0], c[2]) for c in cases if c[4] == with_root])
        con.commit()
        con.close()
        cmd = [sys.executable, "-I", checker] + (["--root", repo_root] if with_root else []) + [db]
        p = subprocess.run(cmd, capture_output=True, text=True)
        if not any(ln.startswith("CHECKED ") for ln in p.stdout.splitlines()):
            print("GRID-BLIND the checker printed no CHECKED line (rc %d): %s" % (p.returncode, p.stderr[-300:]))
            return 2
        rcs.append(p.returncode)
        for ln in p.stdout.splitlines():
            if ln.startswith("FAIL CON-"):
                head, _, reason = ln.partition(": ")
                fails[head.split()[1]] = reason
    mism = refused = 0
    for i, name, _, want, _root in cases:
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
          % (len(cases), refused, len(cases) - refused, mism, max(rcs)))
    return 0 if mism == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
