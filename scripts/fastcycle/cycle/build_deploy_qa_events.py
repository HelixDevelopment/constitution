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

VALID_VERDICTS = {"ALLOW", "FAIL", "REFUSE"}


def _present(value):
    """A value is present only as a string holding something other than
    whitespace: None, "", "   ", a number or a list are all 'absent'. T048 restart
    round 2 (V4-6): the round-1 test `value != ""` let a whitespace-only
    fingerprint pair (" " / " ") pass as an identity match. Every presence test in
    this file goes through this one function (the class fix, not an instance)."""
    return isinstance(value, str) and value.strip() != ""


def _show(value):
    """A record value as echoed on stdout: printable strings verbatim, None as "",
    anything else (a newline-carrying or non-string value) as JSON -- so every
    output stays the contract's EXACT one line per field (T048 restart round 2:
    a value carrying a newline would otherwise forge an extra output line)."""
    if value is None:
        return ""
    if isinstance(value, str) and value.isprintable():
        return value
    return json.dumps(value)


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
    try:
        with open(input_path, "r", encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"build_deploy_qa_events: cannot read/parse {input_path}: {exc}\n")
        print("REFUSE build_id=UNKNOWN verdict_INVALID=")
        return 1

    if not isinstance(rec, dict):
        print("REFUSE build_id=UNKNOWN verdict_INVALID=")
        return 1

    kind = rec.get("kind")
    if kind == "build_event":
        return handle_build_event(rec)
    if kind == "join":
        return handle_join(rec)

    sys.stderr.write(f"build_deploy_qa_events: unrecognised kind {kind!r}\n")
    print(f"REFUSE build_id={_build_id_of(rec)} verdict_INVALID=")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
