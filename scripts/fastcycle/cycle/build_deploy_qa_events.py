#!/usr/bin/env python3
"""build_deploy_qa_events.py - build-verdict/deploy-event/QA-event validate+join
core (spec-004 "fast-dev-cycles", plan.md T-A08, tasks.md T040; FR-001, SC-001).
Guarded by constitution/scripts/fastcycle/tests/test_build_deploy_qa_events_red.sh
(T022) via lib/triple_harness.sh (golden-good / golden-bad / negative-control,
fixtures under tests/fixtures/build_deploy_qa/).

Contract (verbatim from T022's RED test comment header -- this file MUST NOT
diverge from it; the RED test is authoritative, this docstring restates it for
readability only):

Invocation: `python3 build_deploy_qa_events.py <input-file>` -- exactly one
positional argument, the path to a JSON input file. No subcommand, no stdin.

<input> is a JSON object whose "kind" field selects the record shape:
  "build_event" : {"kind":"build_event","build_id":<str>,
                    "status":<sampler status: SUCCESS|FAIL|UNKNOWN|KILLED>,
                    "verdict":<str>,"fingerprint":<str>}
  "join"        : {"kind":"join",
                    "build":{"build_id":<str>,"status":<str>,
                             "verdict":<str>,"fingerprint":<str>},
                    "deploy":{"target_serial":<str>,"fingerprint":<str>,
                              "time":<ISO 8601 UTC>}}

The closed verdict vocabulary is reused verbatim from
scripts/lib/critical_blocker_gate.sh's own CBG_RC_ALLOW=0/CBG_RC_FAIL=1/
CBG_RC_REFUSE=4 -- §11.4.227 extend-don't-duplicate: this tool MUST NOT invent
a second vocabulary:
  ALLOW | FAIL | REFUSE

Exit codes (kind=build_event):
  0  verdict in {ALLOW,FAIL,REFUSE} -> stdout EXACTLY:
       KIND=build_event
       VERDICT=<verdict>
  1  verdict absent/empty/not in {ALLOW,FAIL,REFUSE} -> stdout EXACTLY
     one line naming the build_id and the value actually read
     (§11.4.201(5) resolved evidence):
       REFUSE build_id=<build_id> verdict_INVALID=<value>

Exit codes (kind=join):
  0  build.verdict valid AND build.fingerprint == deploy.fingerprint ->
     stdout EXACTLY:
       KIND=join
       FINGERPRINT=<fingerprint>
       VERDICT=<verdict>
       DEPLOY_TARGET=<target_serial>
  1  invalid verdict, a missing/empty/blank fingerprint on either side, a
     fingerprint mismatch, a missing/empty/blank deploy target_serial, or a deploy
     time that is not an ISO 8601 UTC instant -> stdout EXACTLY one line naming
     build_id and the specific offending reason, checked in this order:
     verdict_INVALID=<v> | fingerprint_MISSING=<build|deploy|build,deploy>
     | fingerprint_MISMATCH=<build-fp>/<deploy-fp> | target_serial_MISSING
     | deploy_time_INVALID=<value read>.
     (T048 restart round 1, R6-F1: a join whose two fingerprints are both
     absent or both "" used to pass as an identity match. T048 restart round 2,
     V4-6: a whitespace-only value is absent too -- " " == " " is no identity --
     and the contract's `time` field is validated instead of ignored.)

Value rendering (T048 restart round 3, V4R3-7/8): every value echoed on a REFUSE
line is ONE unambiguous token (see _show: a plain token that is not valid JSON
verbatim, anything else as its JSON encoding with spaces written as the JSON
escape u0020 and '/' as the JSON escape of a slash), so no value can forge a field, a line, or a split point; and a value
made only of whitespace, control or invisible format characters is absent (see
_present).

This tool is the pure, fixture-testable validate+join core. T040's own
emitter wiring into docs/build/resources/builds.tsv, scripts/flash.sh's
post-verify step, and scripts/lib/critical_blocker_gate.sh (plan.md T040,
conductor-only, SERIAL) is OUT OF SCOPE for this tool and for T022 -- see the
tasks.md T040 entry for that wiring's own scope + evidence.

Malformed input (not valid JSON, "kind" missing/unrecognised, or a
build_event/join whose build_id cannot be resolved even as an empty string)
is treated as an invalid record and refused via the same rc=1 path used for
an invalid verdict -- never an uncaught traceback (which the harness would
treat as a tool ERROR, never a detection, per its own "anything other than
0 or 1" rule). §11.4.6: "could not resolve build_id" is reported honestly
as the literal string "UNKNOWN", never fabricated.
"""
import datetime
import json
import re
import sys
import unicodedata

VALID_VERDICTS = {"ALLOW", "FAIL", "REFUSE"}


def _present(value):
    """A value is present only as a string holding at least one VISIBLE character
    (a letter, digit, punctuation mark or symbol -- Unicode categories L*, N*, P*,
    S*): None, "", "   ", a number, a list, or a string made only of whitespace,
    control or invisible FORMAT characters (U+200B ZERO WIDTH SPACE, U+FEFF, ...)
    are all 'absent'. T048 restart round 2 (V4-6) stripped whitespace only; round
    3 (V4R3-8): `str.strip()` keeps Cf characters, so a U+200B fingerprint on both
    sides passed as an identity match. Every presence test in this file goes
    through this one function (the class fix, not an instance)."""
    return isinstance(value, str) and any(unicodedata.category(c)[0] in "LNPS" for c in value)


# A value is echoed verbatim only if it is made of these characters: none of
# them is whitespace, a reason separator ('=', ',', '/'), a quote or a backslash,
# so a verbatim token can never be mistaken for, or merge with, another field.
_PLAIN_RE = re.compile(r"[A-Za-z0-9._:+@~-]+")


def _is_json(text):
    try:
        json.loads(text)
    except ValueError:
        return False
    return True


def _show(value):
    r"""A record value as ONE unambiguous token on the contract's one output line
    (T048 restart round 3, V4R3-7): None -> "" (absent); a string of plain
    characters that is NOT itself valid JSON -> verbatim; anything else (an
    empty string, whitespace, '/', '=', ',', quotes, newlines, non-ASCII, a
    string that reads as a JSON number/literal such as "5" or "true", any
    non-string) -> its JSON encoding, ASCII-only, compact, with every space
    written \u0020 and every '/' written \/ (both valid JSON escapes). So a
    verbatim token is never valid JSON and every other rendering is: the two can
    never collide. No rendering contains whitespace or a bare '/', so splitting
    the line on whitespace, or a MISMATCH value on '/', is always unambiguous.
    Round 2 echoed printable strings verbatim: build_id "x fingerprint_MISSING=build"
    forged a second reason field, and fingerprint "a/b" vs "c" printed as the
    ambiguous MISMATCH=a/b/c."""
    if value is None:
        return ""
    if isinstance(value, str) and _PLAIN_RE.fullmatch(value) and not _is_json(value):
        return value
    return json.dumps(value, ensure_ascii=True, separators=(",", ":")).replace(" ", "\\u0020").replace("/", "\\/")


def _build_id_of(rec):
    """Resolve a build_id from a record dict, honestly reporting UNKNOWN
    (never fabricating one) when the field is absent, not a string, empty or
    whitespace-only (§11.4.6 no-guessing)."""
    bid = rec.get("build_id") if isinstance(rec, dict) else None
    if _present(bid):
        return _show(bid)
    return "UNKNOWN"


# ISO 8601 UTC instant: YYYY-MM-DDTHH:MM:SS[.fraction](Z|+00:00), and a real
# calendar date/time (datetime parses it).
_UTC_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|\+00:00)")


def _utc_instant_ok(value):
    """The contract's deploy `time` field: an ISO 8601 instant in UTC. Anything
    else -- absent, not a string, a garbage string, an impossible date, or a
    non-UTC offset -- is refused (T048 restart round 2, V4-6)."""
    if not isinstance(value, str) or not _UTC_RE.fullmatch(value):
        return False
    try:
        datetime.datetime.strptime(value[:19], "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return False
    return True


def handle_build_event(rec):
    build_id = _build_id_of(rec)
    verdict = rec.get("verdict")
    if isinstance(verdict, str) and verdict in VALID_VERDICTS:
        print("KIND=build_event")
        print(f"VERDICT={verdict}")
        return 0
    print(f"REFUSE build_id={build_id} verdict_INVALID={_show(verdict)}")
    return 1


def handle_join(rec):
    build = rec.get("build") if isinstance(rec, dict) else None
    deploy = rec.get("deploy") if isinstance(rec, dict) else None
    if not isinstance(build, dict):
        build = {}
    if not isinstance(deploy, dict):
        deploy = {}

    build_id = _build_id_of(build)
    verdict = build.get("verdict")
    build_fp = build.get("fingerprint")
    deploy_fp = deploy.get("fingerprint")
    target_serial = deploy.get("target_serial")

    if not (isinstance(verdict, str) and verdict in VALID_VERDICTS):
        print(f"REFUSE build_id={build_id} verdict_INVALID={_show(verdict)}")
        return 1

    # T048 restart round 1 (R6-F1): the identity check below is the whole point of
    # the join (S11.4.200), so it must be able to FAIL on missing data. Comparing
    # `build_fp != deploy_fp` alone passed when BOTH sides were absent (None ==
    # None) or BOTH were "" -- an identity check with no identity to check. A
    # fingerprint is only an identity when it is a non-empty string; anything else
    # is refused and the missing side(s) are named (S11.4.201(5)).
    missing = [side for side, fp in (("build", build_fp), ("deploy", deploy_fp))
               if not _present(fp)]
    if missing:
        print(f"REFUSE build_id={build_id} fingerprint_MISSING={','.join(missing)}")
        return 1

    if build_fp != deploy_fp:
        print(f"REFUSE build_id={build_id} fingerprint_MISMATCH={_show(build_fp)}/{_show(deploy_fp)}")
        return 1

    # A deploy record that names no target is not evidence of a deploy anywhere
    # (it printed DEPLOY_TARGET=None before this check existed). `status` is
    # deliberately NOT validated: it is the resource-sampler lifecycle field the
    # golden-bad fixture proves must never drive the verdict, and its real
    # producers emit values outside the docstring's list (critical_blocker_gate.sh
    # writes status="QA_GATE"), so a closed-set check on it would refuse real data.
    if not _present(target_serial):
        print(f"REFUSE build_id={build_id} target_serial_MISSING")
        return 1

    deploy_time = deploy.get("time")
    if not _utc_instant_ok(deploy_time):
        print(f"REFUSE build_id={build_id} deploy_time_INVALID={_show(deploy_time)}")
        return 1

    print("KIND=join")
    print(f"FINGERPRINT={_show(build_fp)}")
    print(f"VERDICT={verdict}")
    print(f"DEPLOY_TARGET={_show(target_serial)}")
    return 0


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: build_deploy_qa_events.py <input-file>\n")
        return 1

    input_path = argv[1]
    # T048 V4 round 5 (F6): json.load raises more than JSONDecodeError on hostile input --
    # ValueError for an integer literal past the 4300-digit int-conversion limit,
    # RecursionError for nesting deeper than the recursion limit, UnicodeDecodeError (a
    # ValueError) for bytes that are not UTF-8. Each is a REFUSE with the one-line evidence,
    # never a traceback.
    try:
        with open(input_path, "r", encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, json.JSONDecodeError, UnicodeDecodeError, ValueError, RecursionError) as exc:
        sys.stderr.write("build_deploy_qa_events: cannot read/parse %s: %s: %s\n"
                         % (input_path, type(exc).__name__, str(exc)[:200]))
        print("REFUSE build_id=UNKNOWN verdict_INVALID=")
        return 1

    if not isinstance(rec, dict):
        print("REFUSE build_id=UNKNOWN verdict_INVALID=")
        return 1

    try:
        kind = rec.get("kind")
        if kind == "build_event":
            return handle_build_event(rec)
        if kind == "join":
            return handle_join(rec)
        sys.stderr.write(f"build_deploy_qa_events: unrecognised kind {kind!r}\n")
        print(f"REFUSE build_id={_build_id_of(rec)} verdict_INVALID=")
        return 1
    except (ValueError, RecursionError) as exc:
        # a parsed value that cannot be shown (e.g. nesting deep enough to exhaust the recursion
        # limit while it is escaped): still one REFUSE line, never a traceback
        sys.stderr.write("build_deploy_qa_events: cannot evaluate %s: %s\n" % (input_path, type(exc).__name__))
        print("REFUSE build_id=UNKNOWN verdict_INVALID=")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
