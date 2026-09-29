#!/usr/bin/env python3
"""tier_route.py - per-task-class model-tier routing (spec-004 "fast-dev-cycles",
User Story 4, T118, plan task T-E06; SC-005, FR-023). RED test (T109, a
SEPARATE, EARLIER task): constitution/scripts/fastcycle/tests/
test_tier_routing_red.sh + fixtures under tests/fixtures/tier_route/
README.md -- read that README before touching this file; it is this tool's
interim contract (no contracts/*.md file exists for this tool yet --
contracts/common-conventions.md's own "Tool map" section lists
`$FC/context/tier_route.py (T-E06)` among the tools whose "interface,
output and RED fixtures are fixed by the plan task text until a contract
is written").

Purpose (plan.md T-E06, restated precisely, never invented -- see
fixtures/tier_route/README.md "The routing rule this fixture set encodes"
for the full rationale this module implements):
  1. A review-class task is REFUSED outright -- never assigned any tier,
     cheap or otherwise. Review tier/effort assignment belongs exclusively
     to the ALREADY-LANDED $FC/review/review_record.py's own RB-004
     refusal (DESIGNATED_TIER="opus"/DESIGNATED_EFFORT="xhigh") and to
     contracts/common-conventions.md's "Designated review tier" term
     ("never lowered or routed (T-C11, T-E06)"). This module never
     re-decides that pin -- it is the ONE branch section 11.4.231 clause
     (E)'s HARD PIN binds: code reviews (and section 11.4.211
     merge-conflict resolution) MUST ALWAYS run on the Opus model at
     xhigh effort, never tiered down by ANY mechanism -- so a
     review-class task must never even be CONSIDERED by this router's
     tier-assignment logic, not merely defaulted to the top tier WITHIN
     it.
  2. A task class WITH a deterministic verifier starts at the lightest
     tier declared to fit the window (`min_fitting_tier` -- a GIVEN
     classification input here, exactly as fixtures/tier_route/README.md
     documents: the window-fit determination itself is T-E02/T114's
     concern, not this tool's) and escalates EXACTLY ONE ladder rung on
     each verifier failure, never more, never fewer, until a pass or the
     ladder is exhausted (see "Ladder-exhaustion decision" below).
  3. A task class WITHOUT a deterministic verifier (and NOT a review) is
     NEVER routed below the constitution's own section 11.4.231(A)
     default working tier (`sonnet`) -- it is not refused, not treated as
     an error, and not silently defaulted to the cheapest tier either; it
     PASSES at the safe default with zero escalation attempts.

Invocation:
    tier_route.py route --fixture <fixture.json> --out <route.json>

Wire format (UNCONFIRMED by any contract -- DEFINED in
fixtures/tier_route/README.md's own "Wire format" section, binding-if-
adopted, implemented here verbatim): the `route` subcommand writes a
`tier-route/v1` document whose body carries `{refused: bool,
refusal_reason: str|null, route_sequence: [tier,...], escalations: int,
final_tier: str|null}` -- exactly the shape every fixture's own
`expected_route` block records, PLUS `task_id`/`task_class` (carried
through from the input fixture for downstream traceability; additive,
never required by any fixture check) and the established C-002
`body_hash`/optional `run_meta` envelope every sibling fastcycle report
tool already emits (write_doc_atomic below, identical pattern to
evidence_ref.py's `consume`/`reverify`).

Exit codes: 0 = a real, non-refused route was produced (`refused=false`);
1 = refused -- a finding, C-001 row 1 -- whether the cause is the
review-class hard-exclusion or ladder exhaustion (see below, both are
"a finding: refusal" in the C-001 sense, distinguished only by
`refusal_reason`'s wording, never by exit code); 2 = usage error
(`--fixture` missing/unreadable/not valid JSON, or the fixture document
itself is malformed -- missing a required field, an unknown tier, etc.).

Producer != Verifier (section 11.4.240): this file is T118's
implementation of the routing rule T109's RED test (a SEPARATE, EARLIER
task) independently derives via its own embedded `derive_route` oracle
(test_tier_routing_red.sh). That oracle is NEVER imported by, shared
with, or otherwise coupled to this file -- the two were written
independently, directly from the SAME specification text (plan.md T-E06 +
research.md DEC-28), and are expected to agree because both correctly
implement the same spec, not because one delegates to the other.

Reuse, not reinvention (section 11.4.227): the review-tier pin already
exists, exclusively, in the ALREADY-LANDED
$FC/review/review_record.py's own DESIGNATED_TIER/DESIGNATED_EFFORT
module-level constants plus its RB-004 refusal mechanism. This module
never re-decides, re-computes, or hardcodes a duplicate copy of that pin
-- the actual hard-exclusion DECISION (`is_review_class` => refuse, never
route) needs no data from review_record.py at all; it is unconditional.
This module reads review_record.py's two constants LIVE (by a targeted
regex over its real source text, mirroring T109's own control needle #4
-- never imported as a Python module, since review_record.py is a CLI
tool with its own argparse entry point and top-level side effects on
import would be undesirable here) purely to word this tool's own
refusal_reason MESSAGE accurately; if that read fails for any reason the
refusal still happens (unconditionally), only the message's wording
degrades to a generic form rather than crashing.

Ladder-exhaustion decision (UNCONFIRMED by plan.md/tasks.md --
fixtures/tier_route/README.md's own "Explicit scope exclusion" section
leaves this "for T118's own implementation decision at review time", and
that decision is made HERE, in this module, with its reasoning made
explicit rather than silently assumed, section 11.4.6): when a
deterministic-verifier task's every ladder rung has failed its verifier,
including the top rung, this tool REFUSES (`refused=true`, exit 1 -- the
SAME C-001 "finding: refusal" class the review-hard-exclusion branch
uses, but with a structurally DISTINCT `refusal_reason` string so a
caller can always tell the two apart) rather than either (a) raising an
unhandled exception -- production code serving a router must not crash on
a legitimate, reachable input shape a test's derived oracle is free to
treat as out-of-scope but this module is not -- or (b) fabricating a
`final_tier` that never actually passed its own verifier, which would be
exactly the kind of PASS-bluff the section 11.4 anti-bluff covenant
forbids. This is the conservative-safe choice per section 11.4.101
(reversible: no tier was ever silently assigned; determinable from the
evidence already in hand -- every attempt already recorded a real
verifier_result; bounded blast radius: the caller is told plainly "every
tier failed, here is the whole attempted sequence", never handed a task
silently marked done) over the two alternatives plan.md/tasks.md leave
unstated (a permanently different refusal class, or an
operator-blocked hand-off per section 11.4.21) -- promoting either of
THOSE to firm policy here, on the spec's silence alone, would itself be
exactly the guess section 11.4.6 forbids. "Refused, here is why, here is
every tier that was tried" is the smallest honest thing this tool can say
without inventing an answer the spec never gave; a caller wanting an
operator-blocked hand-off on top of that refusal is free to build it from
this module's honest `refused=true` + full `route_sequence` output.

Stdlib only. Python 3.
"""
import argparse
import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers (identical
# import-by-path pattern to escape_classify.py / cycle_report.py / T039's own
# anchor_citations.py / T117's own evidence_ref.py -- constitution/scripts/
# fastcycle has no __init__.py anywhere, matching this tree's existing flat-
# script layout).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA_ROUTE = "tier-route/v1"

EXIT_OK = 0
EXIT_FINDING = 1   # refused: review-class hard-exclusion OR ladder exhaustion (C-001 row 1)
EXIT_USAGE = 2      # malformed/missing --fixture, or a malformed fixture document

# Constitution 11.4.231(A): "sonnet" is the DEFAULT working tier.
CONSTITUTION_DEFAULT_TIER = "sonnet"

# review_record.py lives one directory up from this file, under review/ (see
# module docstring "Reuse, not reinvention"). Read by regex, never imported.
_REVIEW_RECORD = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "review", "review_record.py"
)
_DESIGNATED_TIER_RE = re.compile(r'^DESIGNATED_TIER\s*=\s*"([^"]+)"', re.MULTILINE)
_DESIGNATED_EFFORT_RE = re.compile(r'^DESIGNATED_EFFORT\s*=\s*"([^"]+)"', re.MULTILINE)


def _designated_review_tier_effort():
    """Reads review_record.py's real, live DESIGNATED_TIER/DESIGNATED_EFFORT
    module-level constants by a targeted regex over its actual source text
    (never a hardcoded literal assumption; mirrors T109's own control
    needle #4). Returns (tier, effort), each None if the constant could not
    be found or the file is unreadable -- the caller degrades to a generic
    refusal message in that case (see module docstring); this function
    never raises and never affects the routing DECISION itself, only the
    wording of the review-refusal message."""
    if not os.path.isfile(_REVIEW_RECORD):
        return None, None
    try:
        with open(_REVIEW_RECORD, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None, None
    tier_m = _DESIGNATED_TIER_RE.search(text)
    effort_m = _DESIGNATED_EFFORT_RE.search(text)
    return (tier_m.group(1) if tier_m else None, effort_m.group(1) if effort_m else None)


def _refuse_review():
    """Clause 1: reviews are hard-excluded, unconditionally -- checked
    FIRST, before any verifier/default-tier logic even looks at the rest
    of the fixture document, exactly like the RED test's own oracle. This
    is the ONLY branch section 11.4.231(E)'s hard pin binds: a
    review-class task is NEVER assigned any tier by this router, cheap or
    otherwise -- review/merge-conflict tier+effort stays exclusively
    review_record.py's RB-004 decision."""
    tier, effort = _designated_review_tier_effort()
    if tier and effort:
        pin_note = (
            "reviews stay pinned at the designated review tier (%s/%s, "
            "review_record.py DESIGNATED_TIER/DESIGNATED_EFFORT) exclusively "
            "through review_record.py's own RB-004 refusal, never assigned "
            "any tier by this router" % (tier, effort)
        )
    else:
        pin_note = (
            "reviews stay pinned exclusively through review_record.py's own "
            "RB-004 refusal, never assigned any tier by this router "
            "(review_record.py's DESIGNATED_TIER/DESIGNATED_EFFORT constants "
            "could not be read live -- see module docstring)"
        )
    return {
        "refused": True,
        "refusal_reason": (
            "review-class task; hard-excluded from tier routing (FR-023, "
            "plan T-E06 'reviews are hard-excluded'; "
            "contracts/common-conventions.md 'Designated review tier' term: "
            "'never lowered or routed (T-C11, T-E06)'); %s" % pin_note
        ),
        "route_sequence": [],
        "escalations": 0,
        "final_tier": None,
    }


def _route_default(fx, ladder):
    """Clause 3: no deterministic verifier (and NOT a review, per the
    caller's branch order) -- routes to the constitution's own section
    11.4.231(A) default working tier, with zero escalation attempts. Never
    refused, never an error -- this is the real, successful safety-net
    PASS (refused=false) the negative-control fixture proves is genuine,
    never a disguised refusal."""
    # The safety-net branch routes to the constitution's own 11.4.231(A)
    # default working tier. A fixture may RESTATE it but never OVERRIDE it
    # (T121 review finding F-TR1): an override previously routed a
    # no-verifier task to any ladder rung, including haiku, which
    # 11.4.231(D.1) prohibits here -- the exact cheap-routing this branch
    # exists to prevent.
    default_tier = fx.get("default_tier", CONSTITUTION_DEFAULT_TIER)
    if default_tier != CONSTITUTION_DEFAULT_TIER:
        raise ValueError(
            "default_tier %r overrides the constitution 11.4.231(A) default "
            "working tier %r; the no-verifier safety-net branch never routes "
            "anywhere else" % (default_tier, CONSTITUTION_DEFAULT_TIER)
        )
    if default_tier not in ladder:
        raise ValueError(
            "default_tier %r is not a rung on this fixture's own ladder %r"
            % (default_tier, ladder)
        )
    return {
        "refused": False,
        "refusal_reason": None,
        "route_sequence": [default_tier],
        "escalations": 0,
        "final_tier": default_tier,
    }


def _route_escalation(fx, ladder):
    """Clause 2: a deterministic-verifier class -- start at
    `min_fitting_tier` (a GIVEN classification input, T-E02/T114's
    concern, never computed here) and escalate EXACTLY ONE ladder rung per
    verifier failure until a pass, or until the ladder is exhausted (see
    module docstring "Ladder-exhaustion decision")."""
    if "min_fitting_tier" not in fx:
        raise ValueError("deterministic-verifier fixture is missing 'min_fitting_tier'")
    if fx["min_fitting_tier"] not in ladder:
        raise ValueError(
            "min_fitting_tier %r is not a rung on this fixture's own ladder %r"
            % (fx["min_fitting_tier"], ladder)
        )
    attempts = fx.get("attempts") or []
    if not attempts:
        raise ValueError("deterministic-verifier fixture has no 'attempts' to route through")

    cur_idx = ladder.index(fx["min_fitting_tier"])
    seq = []
    escalations = 0
    for attempt in attempts:
        tier = attempt.get("tier")
        if tier not in ladder:
            raise ValueError(
                "attempt tier %r is not a rung on this fixture's own ladder %r"
                % (tier, ladder)
            )
        if ladder.index(tier) != cur_idx:
            raise ValueError(
                "attempt tier %r is not the current ladder rung %r -- "
                "escalation skipped a rung" % (tier, ladder[cur_idx])
            )
        seq.append(tier)
        if attempt.get("verifier_result") == "pass":
            return {
                "refused": False,
                "refusal_reason": None,
                "route_sequence": seq,
                "escalations": escalations,
                "final_tier": tier,
            }
        # Exactly one rung per failure (README.md "GOLDEN (bonus)" scenario
        # -- never a "give up and jump to the top" shortcut).
        escalations += 1
        cur_idx += 1
        if cur_idx >= len(ladder):
            # Ladder exhaustion -- see module docstring "Ladder-exhaustion
            # decision": refuse honestly rather than crash or fabricate a
            # passing tier that never actually passed.
            return {
                "refused": True,
                "refusal_reason": (
                    "ladder exhausted -- every rung's verifier failed "
                    "(attempted %s), including the top rung %r; this tool "
                    "does not fabricate a final_tier that never actually "
                    "passed its verifier (section 11.4 anti-bluff covenant)"
                    % (seq, ladder[-1])
                ),
                "route_sequence": seq,
                "escalations": escalations,
                "final_tier": None,
            }
    raise ValueError(
        "attempts sequence never reached pass or exhaustion -- malformed fixture"
    )


def derive_route(fx):
    """This tool's OWN routing decision, independently written from
    plan.md T-E06 + research.md DEC-28's wording (see module docstring
    "Producer != Verifier" -- never imported from, nor coupled to,
    test_tier_routing_red.sh's own embedded oracle). Raises ValueError on
    a malformed fixture document (a genuine usage error at the CLI layer,
    exit 2 -- see cmd_route); a well-formed fixture always returns a
    result dict, refused or not, and never raises for a legitimate
    ladder-exhaustion input (see _route_escalation)."""
    if "ladder" not in fx or not isinstance(fx["ladder"], list) or not fx["ladder"]:
        raise ValueError("fixture document is missing a non-empty 'ladder' list")
    ladder = fx["ladder"]

    # Fail-closed classification (T121 review findings F-TR2, constitution
    # 11.4.252 / 11.4.231(E)): the two routing-class flags MUST be present
    # AND be real booleans. A missing `is_review_class` previously defaulted
    # to False, so a review-class task could reach a cheap tier merely by
    # omitting the flag; a non-bool truthy string was accepted as True by
    # accident rather than by contract. Either is now a malformed document.
    for flag in ("is_review_class", "has_deterministic_verifier"):
        if not isinstance(fx.get(flag), bool):
            raise ValueError(
                "fixture document must carry an explicit boolean %r (got %r) -- "
                "routing class is never inferred from an absent or non-bool "
                "flag (fail closed, section 11.4.252)" % (flag, fx.get(flag))
            )

    if fx["is_review_class"]:
        return _refuse_review()
    if not fx["has_deterministic_verifier"]:
        return _route_default(fx, ladder)
    return _route_escalation(fx, ladder)


# ---------------------------------------------------------------------------
# Output document (section 11.4.205(6) write-temp-then-rename, identical
# pattern to the already-landed sibling evidence_ref.py's write_doc_atomic /
# escape_classify.py / cycle_report.py).
# ---------------------------------------------------------------------------
def _hostname():
    return os.uname().nodename if hasattr(os, "uname") else "unknown"


def write_doc_atomic(out_path, body):
    doc = dict(body)
    doc["schema"] = SCHEMA_ROUTE
    doc["body_hash"] = body_hash_of(doc)
    doc["run_meta"] = {"host": _hostname()}
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    import tempfile

    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".tier_route.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


# ---------------------------------------------------------------------------
# route subcommand
# ---------------------------------------------------------------------------
def cmd_route(a):
    if not os.path.isfile(a.fixture):
        print("tier_route: --fixture not found: %s" % a.fixture, file=sys.stderr)
        return EXIT_USAGE
    try:
        with open(a.fixture, encoding="utf-8") as fh:
            fx = json.load(fh)
    except (OSError, ValueError) as exc:
        print("tier_route: cannot read --fixture: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(fx, dict):
        print("tier_route: --fixture is not a JSON object", file=sys.stderr)
        return EXIT_USAGE

    try:
        result = derive_route(fx)
    except ValueError as exc:
        print("tier_route: malformed --fixture document: %s" % exc, file=sys.stderr)
        return EXIT_USAGE

    body = {
        "task_id": fx.get("task_id"),
        "task_class": fx.get("task_class"),
        "refused": result["refused"],
        "refusal_reason": result["refusal_reason"],
        "route_sequence": result["route_sequence"],
        "escalations": result["escalations"],
        "final_tier": result["final_tier"],
    }
    write_doc_atomic(a.out, body)

    if result["refused"]:
        print("tier_route: route REFUSED (%s) -- %s"
              % (fx.get("task_id"), result["refusal_reason"]), file=sys.stderr)
        return EXIT_FINDING
    print("tier_route: route %s -> final_tier=%s (escalations=%d)"
          % (fx.get("task_id"), result["final_tier"], result["escalations"]))
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="tier_route.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd_name", required=True)

    r = sub.add_parser("route")
    r.add_argument("--fixture", required=True)
    r.add_argument("--out", required=True)

    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)
    table = {"route": cmd_route}
    return table[args.cmd_name](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
