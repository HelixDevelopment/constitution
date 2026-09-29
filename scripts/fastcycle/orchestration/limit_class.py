#!/usr/bin/env python3
"""limit_class.py - classifies a limit-caused agent kill from its verbatim
raw signal text (spec-004 "fast-dev-cycles", User Story 5 / Phase B, T135,
plan task T-B06; FR-016). RED test (T127, a SEPARATE, EARLIER task):
constitution/scripts/fastcycle/tests/test_limit_class_red.sh + fixtures
under tests/fixtures/limit_class/README.md -- read that README before
touching this file; it restates the classification rule precisely, with
provenance discipline, from the REAL contract this tool has (unlike
context/tier_route.py's T109/T118, which had none).

A REAL CONTRACT fixes this tool's interface (specs/004-fast-dev-cycles/
contracts/agent-registry-and-handoff.md's Components block + AR-005 clause;
data-model.md's `limit_signal` entity) -- this file implements those fixed
shapes verbatim rather than inventing them:

  CLI (Components block, verbatim):
      limit_class.py --signal <raw> --out <class.json>

  Output shape (data-model.md's `limit_signal` entity, verbatim):
      {class: str, raw: str, resets_at: str (ISO 8601) | "UNKNOWN"}
      -- exactly these three keys; this is the literal sub-object AR-005
      requires embedded into a `crashed` agent_registry.jsonl event, so no
      extra envelope (no schema/body_hash wrapper, unlike this tool's
      sibling fastcycle report tools) is added here.

  Closed class set (research.md DEC-14 + AR-005, four members):
      {rate-limited, cap, context-overflow, other}

Classification rule (restated precisely from fixtures/limit_class/
README.md "The classification rule this fixture set encodes" -- never
invented here; every one of the four real/constructed fixtures that
README documents is satisfied by the rule below):

  1. context-overflow -- the raw signal names a token/prompt-length
     ceiling being exceeded ("prompt (is) too long ... N tokens > M
     maximum"). Structurally distinct from every 429 class: never a
     retry-after, never cap/reset wording. Handling (AR-005/T-B06):
     re-dispatch with the governance subset (DEC-12), never the same
     prompt.
  2. cap -- the raw signal is an HTTP 429 that EITHER has no retry-after
     value OR names a weekly/subscription reset instant (DEC-14's own
     disambiguator, an OR of the two conditions -- checked precisely,
     never collapsed to "any 429 is a cap" nor "any 429 is rate-limited").
     Handling: never retry on that alias; rebind the resume to an
     operational alias (section 11.4.196 native-first order) and mark the
     alias cooled until its stated reset.
  3. rate-limited -- an HTTP 429 that carries a retry-after value AND
     names no weekly/subscription reset (the genuine transient/
     short-window case). Handling: backoff honouring retry-after, then
     resume on the same or another alias.
  4. other -- none of the above structurally matches. The classifier
     still emits a verdict here (per the contract's own "Exit codes"
     section: "Limit classifier: 0 classified, 1 signal unparseable
     (class `other` emitted with the raw signal)") -- it never refuses to
     classify, it only signals via exit code 1 that the raw signal did
     not structurally match any of the three named classes.

This tool receives ONLY the verbatim raw signal string via `--signal`
(the contract's own fixed invocation carries no structured http_status/
retry_after_seconds/reset_named fields -- see the RED test's real-tool
invocation block, which extracts and passes ONLY each fixture's
`raw_signal` field) -- every classification decision below is therefore
made by parsing that text alone, exactly as a real `crashed`-kill note in
docs/requests/agent_registry.jsonl would be parsed downstream.

Producer != Verifier (section 11.4.240): this file is T135's
implementation of the classification rule T127's RED test (a SEPARATE,
EARLIER task) independently derives via its own embedded `derive_class`
oracle (test_limit_class_red.sh), which operates on each fixture's
STRUCTURED fields (http_status, retry_after_seconds, reset_named) rather
than raw text. That oracle is NEVER imported by, shared with, nor
otherwise coupled to this file -- the two were written independently,
directly from the SAME specification text (research.md DEC-14 +
contracts/agent-registry-and-handoff.md's AR-005 clause), and are expected
to agree on every fixture because both correctly implement the same
closed-set rule over the same underlying real signals, not because one
delegates to the other. Cross-checked here against all five documented
fixtures (four real-tool-invoked, one negative-control) before landing.

Exit codes (contract's own "Exit codes" section, verbatim): 0 = classified
into rate-limited, cap, or context-overflow; 1 = signal unparseable --
class `other` emitted with the raw signal (never a crash, never a refusal
to write --out); 2 = usage error (missing/malformed --signal or --out).

T136 (plan T-B07's "place" decision, DEC-22 spread fan-out; FR-016,
FR-018): landed in this SAME file, after `classify_signal` / `cmd_classify`
/ `build_arg_parser`, per the operator's own instruction and exactly the
extension point T135 deliberately left open above -- `classify`'s
contract-fixed CLI shape (`--signal <raw> --out <class.json>`, no
subcommand token) is left completely undisturbed; `place` is dispatched by
`main()` inspecting `argv[0]` BEFORE `build_arg_parser()` (classify's
parser) is ever invoked, so `limit_class.py --signal ... --out ...`
(classify, T135) and `limit_class.py place --fixture ... --out ...`
(place, T136) are two genuinely independent entry points sharing one file,
never one parser trying to recognise both shapes.

`place`'s CLI shape, fixture vocabulary, and placement rule are ALL
governed by T128's own RED test + its `fixtures/alias_spread/README.md`
(read that README before touching `derive_placement`/`cmd_place` below;
its "The chosen CLI shape reuses the `--fixture <path> --out <path>`
convention... (T109/T118, the closest sibling tool)" section documents
this file's own binding-if-adopted CLI shape verbatim):

  CLI:
      limit_class.py place --fixture <fixture.json> --out <placement.json>

  Fixture input shape (fixtures/alias_spread/*.json, T128's own fixtures):
      {task_id, verb, live_agents: int,
       aliases: [{alias, kind: "native"|other, operational: bool,
                  near_cap: bool}, ...],
       expected_placement: {...}}  -- `expected_placement` is the FIXTURE's
      own recorded expectation, read only by the RED test, never by this
      file.

  Output shape (data-model.md's placement-decision vocabulary, restated in
  fixtures/alias_spread/README.md's own table -- exactly these seven keys,
  no extra envelope, mirroring `classify`'s own bare-entity wire shape):
      {refused: bool, refusal_reason: str|None,
       eligible_alias_count: int, cap_per_alias: int|None,
       native_first_order: [str], assignment_alias_counts: {str: int},
       max_assigned_count: int|None, excluded_near_cap_aliases: [str]}

Placement rule (restated precisely from fixtures/alias_spread/README.md
"The placement rule this fixture set encodes" -- copied from research.md
DEC-22's own decision text, never independently re-derived nor invented
here):

  1. Eligibility filter -- an alias is eligible for new placements iff it
     is `operational: true` AND `near_cap: false` (DEC-22's second clause:
     an alias within a configurable margin of a known cap receives no new
     long-running agents).
  2. Native-first order (section 11.4.196) -- eligible NATIVE aliases
     first (given relative order preserved), then eligible PROVIDER
     aliases (given relative order preserved) -- a stable partition-by-
     kind, never a re-sort within a kind.
  3. Round-robin spread up to a per-alias cap -- with `m` = eligible alias
     count and `n` = `live_agents`, `cap_per_alias = ceil(n / m) + 1`
     (DEC-22's own formula, copied verbatim, confirmed live in
     research.md by T128's own control needle #4). Agents assigned one at
     a time, cycling `eligible[i % m]` for the i-th agent (0-indexed),
     until all `n` are placed.
  4. No eligible alias -- refused (this fixture set's fourth, out-of-
     scope corner per its own "Explicit scope exclusion" section; T136's
     own decision, documented below at `cmd_place`).

Producer != Verifier (section 11.4.240), exactly as `classify_signal`
above: `derive_placement` below is written fresh, directly from
fixtures/alias_spread/README.md's restated DEC-22 rule (never imported
from, nor shared with, T128's own embedded `derive_placement` oracle
inside `test_alias_spread_red.sh`); the two are expected to agree on
every one of T128's three fixtures because both correctly implement the
same closed placement rule over the same real inputs, not because one
delegates to the other. Cross-checked here against all three documented
fixtures before landing.

Exit codes for `place` (T136's own decision -- README.md's "Explicit
scope exclusion" leaves the zero-eligible-alias refusal corner
UNCONFIRMED by the fixture set, so this file must decide; the decision
below deliberately mirrors `classify`'s own exit-code shape: a real
verdict document is ALWAYS written, and the exit code signals via a
distinguished non-zero value that a special, still-informative condition
was recorded rather than a crash): 0 = placed (not refused; every one of
T128's three fixtures lands here); 1 = refused (no eligible alias --
`refusal_reason` recorded, the `--out` document still written, never a
crash, never a refusal to write); 2 = usage error (missing/malformed
`--fixture`/`--out`, an unreadable or non-JSON `--fixture` file, or a
fixture missing a required field this rule depends on).

Stdlib only. Python 3.
"""
import argparse
import datetime
import json
import math
import os
import re
import sys
import tempfile

try:
    import zoneinfo
except ImportError:  # pragma: no cover - Python < 3.9 fallback, not expected on this host
    zoneinfo = None

EXIT_OK = 0
EXIT_UNPARSEABLE = 1  # classify: class "other" emitted -- contract's own "Exit codes" row
EXIT_PLACE_REFUSED = 1  # place: no eligible alias -- verdict document still written (T136's own decision, see module docstring)
EXIT_USAGE = 2

# T136's own placement refusal-reason text (fixtures/alias_spread/README.md's
# own "No eligible alias => refused" wording) -- the RED test's real-tool
# invocation check ONLY asserts None-vs-not-None on `refusal_reason` (never
# an exact string match), so this literal is free to be a real, readable
# explanation rather than needing to byte-match anything in the test.
PLACE_REFUSAL_REASON_NO_ELIGIBLE = "no operational, non-near-cap alias available"

# Closed class set (research.md DEC-14 / AR-005) -- restated here purely for
# documentation; classify_signal below never returns anything outside it.
CLASS_RATE_LIMITED = "rate-limited"
CLASS_CAP = "cap"
CLASS_CONTEXT_OVERFLOW = "context-overflow"
CLASS_OTHER = "other"

# ---------------------------------------------------------------------------
# Pattern set -- independently written directly against research.md DEC-14 +
# contracts/agent-registry-and-handoff.md's AR-005 clause's own wording (see
# module docstring "Producer != Verifier" -- never imported from, nor
# coupled to, test_limit_class_red.sh's own embedded derive_class oracle,
# which classifies from STRUCTURED fixture fields rather than raw text).
# ---------------------------------------------------------------------------

# Rule 1 (context-overflow): "prompt (is) too long ... N tokens > M maximum"
# -- both real recorded occurrences this rule was checked against spell it
# "Prompt too long" (fixtures/limit_class/README.md's golden fixture +
# corroborating_signal block); "is" is optional per the README's own
# parenthesised wording.
_PROMPT_TOO_LONG_RE = re.compile(r"prompt\s+(?:is\s+)?too\s+long", re.IGNORECASE)

# Rules 2/3 (cap vs rate-limited): both require an HTTP 429 first. Every
# fixture that needs this branch spells the literal "429" in its raw
# signal text (the contract's own fixed invocation passes ONLY the raw
# signal string, never a structured http_status field, so this is the one
# real place that code point survives into the text this tool receives).
_HTTP_429_RE = re.compile(r"\b429\b")

# retry-after value present -- "retry-after: 12" / "retry-after:12" /
# "retry-after 12", optionally followed by a "(seconds)" style suffix
# (fixtures/limit_class/lc_negctrl_rate_limited_retry_after.json's own
# wording: "retry-after: 12 (seconds)").
_RETRY_AFTER_RE = re.compile(r"retry-after:?\s*(\d+)", re.IGNORECASE)

# a NAMED weekly/subscription reset instant -- "resets 2026-09-29 20:00
# Asia/Aqtau" (fixtures/limit_class/lc_golden_cap_weekly.json's own
# wording). Date + time are required for a match to count as "named"; a
# trailing IANA-shaped zone name ("Region/City") is optional and, when
# present, used to compute a real UTC-offset resets_at below.
_RESET_NAMED_RE = re.compile(
    r"resets?\s+(\d{4}-\d{2}-\d{2})[ t](\d{2}:\d{2})(?::(\d{2}))?"
    r"(?:\s+([A-Za-z_]+/[A-Za-z_]+))?",
    re.IGNORECASE,
)


def _format_resets_at(reset_match):
    """Best-effort ISO 8601 rendering of a matched `_RESET_NAMED_RE` reset
    instant. Returns a real UTC-offset ISO string when the matched zone
    name resolves via the stdlib `zoneinfo` tzdata (e.g. "Asia/Aqtau" ->
    "+05:00", exactly matching fixtures/limit_class/
    lc_golden_cap_weekly.json's own recorded `resets_at` field); falls back
    to a naive (no-offset) ISO string when the zone is absent or does not
    resolve on this host, since data-model.md's `limit_signal.resets_at`
    field is typed `Instant or UNKNOWN`, never required to carry an
    offset, and a genuinely unresolvable zone must not turn a real,
    named reset into a fabricated one nor into a silent "UNKNOWN" (the
    date/time WERE named in the signal; only the offset is uncertain).
    Never raises: a malformed date/time this regex still matched (should
    not happen given the regex's own digit-count anchoring) degrades to
    the naive string rather than crashing the whole classification."""
    date_s, time_s, sec_s, tz_name = reset_match.groups()
    sec_s = sec_s or "00"
    naive_iso = "%sT%s:%s" % (date_s, time_s, sec_s)
    if not tz_name or zoneinfo is None:
        return naive_iso
    try:
        dt = datetime.datetime.strptime(
            "%s %s:%s" % (date_s, time_s, sec_s), "%Y-%m-%d %H:%M:%S"
        )
        dt = dt.replace(tzinfo=zoneinfo.ZoneInfo(tz_name))
        return dt.isoformat()
    except Exception:
        return naive_iso


def classify_signal(raw):
    """Classifies a verbatim raw limit-kill signal string into the DEC-14
    closed set. Returns (class_name, resets_at_or_None) -- the caller
    (cmd_classify) is responsible for rendering a missing resets_at as the
    contract's own "UNKNOWN" literal in the written --out document. Never
    raises: an empty/None raw signal is treated as unparseable, exactly
    like any other structurally-non-matching text (class "other")."""
    text = raw or ""

    # Rule 1, checked FIRST: context-overflow is structurally distinct
    # from every 429 class (no fixture combines "prompt too long" wording
    # with a 429), so order relative to the 429 check below never matters
    # in practice, but checking it first mirrors the RED test's own
    # independent oracle (which checks http_status==400 before 429) and
    # keeps the two rule sets easy to compare side by side.
    if _PROMPT_TOO_LONG_RE.search(text):
        return CLASS_CONTEXT_OVERFLOW, None

    if _HTTP_429_RE.search(text):
        retry_after_match = _RETRY_AFTER_RE.search(text)
        reset_match = _RESET_NAMED_RE.search(text)
        has_retry_after = retry_after_match is not None
        reset_named = reset_match is not None
        # DEC-14 / AR-005's own disambiguator, an OR of two conditions:
        # cap = (no retry-after) OR (a named weekly/subscription reset).
        if (not has_retry_after) or reset_named:
            resets_at = _format_resets_at(reset_match) if reset_match else None
            return CLASS_CAP, resets_at
        return CLASS_RATE_LIMITED, None

    return CLASS_OTHER, None


# ---------------------------------------------------------------------------
# Output document -- data-model.md's `limit_signal` entity shape, verbatim:
# exactly {class, raw, resets_at}, no envelope. Written atomically
# (write-temp-then-rename, section 11.4.205(6) -- identical pattern to the
# already-landed sibling context/tier_route.py's write_doc_atomic, minus
# that tool's schema/body_hash wrapper, which this fixed wire shape does
# not carry).
# ---------------------------------------------------------------------------
def write_class_doc_atomic(out_path, body):
    data = (json.dumps(body, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".limit_class.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def cmd_classify(a):
    cls, resets_at = classify_signal(a.signal)
    body = {
        "class": cls,
        "raw": a.signal,
        "resets_at": resets_at if resets_at else "UNKNOWN",
    }
    write_class_doc_atomic(a.out, body)

    if cls == CLASS_OTHER:
        print(
            "limit_class: signal unparseable -- class 'other' emitted with the raw signal",
            file=sys.stderr,
        )
        return EXIT_UNPARSEABLE
    print("limit_class: classified as %s (resets_at=%s)" % (cls, body["resets_at"]))
    return EXIT_OK


# ---------------------------------------------------------------------------
# place (T136; plan T-B07; FR-016, FR-018) -- DEC-22 spread fan-out
# placement decision. `derive_placement` below is an independent
# implementation of fixtures/alias_spread/README.md's restated placement
# rule (section 11.4.240 Producer != Verifier -- see module docstring),
# written fresh from that README's own wording, never imported from nor
# coupled to T128's own embedded `derive_placement` oracle inside
# test_alias_spread_red.sh.
# ---------------------------------------------------------------------------
def derive_placement(fx):
    """Independent implementation of DEC-22's placement rule (restated in
    fixtures/alias_spread/README.md "The placement rule this fixture set
    encodes", copied from research.md DEC-22's own decision text). `fx` is
    a parsed placement-request fixture document
    ({live_agents: int, aliases: [{alias, kind, operational, near_cap},
    ...], ...}); `expected_placement`, if present in `fx`, is never read
    here -- that field belongs to the RED test's own fixture-consistency
    check, not to this tool.

    Returns the seven-key placement-verdict dict documented in this
    module's docstring ("Output shape"). Never raises for a well-formed
    fixture; a fixture missing `live_agents` or `aliases`, or an alias
    entry missing `alias`/`kind`/`operational`/`near_cap`, raises
    KeyError, which `cmd_place` below catches and reports as a usage
    error (a malformed fixture is not this rule's problem to silently
    paper over -- section 11.4.6, never guess a missing field's value)."""
    live_agents = fx["live_agents"]
    aliases = fx["aliases"]

    # Clause 1 (eligibility) + Clause 2 (native-first order, section
    # 11.4.196): partition eligible aliases into natives-then-providers,
    # preserving each partition's own given relative order -- a stable
    # partition-by-kind, never a re-sort within a kind.
    natives = [
        a["alias"]
        for a in aliases
        if a["operational"] and not a["near_cap"] and a["kind"] == "native"
    ]
    providers = [
        a["alias"]
        for a in aliases
        if a["operational"] and not a["near_cap"] and a["kind"] != "native"
    ]
    eligible = natives + providers

    # An alias excluded from new placements ONLY because it is near its
    # recorded cap (DEC-22's second clause) -- operational is required so
    # a merely-unavailable alias is not double-counted here as well as
    # simply-ineligible; sorted for a deterministic, order-independent
    # verdict field.
    excluded_near_cap = sorted(
        a["alias"] for a in aliases if a["operational"] and a["near_cap"]
    )

    if not eligible:
        # Clause 4 (out-of-scope corner, T136's own decision -- see module
        # docstring "Exit codes for place"): no eligible alias => refused,
        # a real verdict document still describing exactly why.
        return {
            "refused": True,
            "refusal_reason": PLACE_REFUSAL_REASON_NO_ELIGIBLE,
            "eligible_alias_count": 0,
            "cap_per_alias": None,
            "native_first_order": [],
            "assignment_alias_counts": {},
            "max_assigned_count": None,
            "excluded_near_cap_aliases": excluded_near_cap,
        }

    # Clause 3 (round-robin spread up to a per-alias cap): DEC-22's own
    # formula, copied verbatim (never independently re-derived) --
    # confirmed live in research.md by T128's own control needle #4.
    m = len(eligible)
    cap_per_alias = math.ceil(live_agents / m) + 1

    assignment_alias_counts = {alias: 0 for alias in eligible}
    for i in range(live_agents):
        assignment_alias_counts[eligible[i % m]] += 1

    max_assigned_count = max(assignment_alias_counts.values()) if assignment_alias_counts else 0
    return {
        "refused": False,
        "refusal_reason": None,
        "eligible_alias_count": m,
        "cap_per_alias": cap_per_alias,
        "native_first_order": eligible,
        "assignment_alias_counts": assignment_alias_counts,
        "max_assigned_count": max_assigned_count,
        "excluded_near_cap_aliases": excluded_near_cap,
    }


def cmd_place(a):
    try:
        with open(a.fixture, encoding="utf-8") as fh:
            fx = json.load(fh)
    except (OSError, ValueError) as exc:
        print(
            "limit_class place: cannot read/parse --fixture %s: %s" % (a.fixture, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    try:
        body = derive_placement(fx)
    except KeyError as exc:
        print(
            "limit_class place: fixture %s is missing a required field: %s"
            % (a.fixture, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    write_class_doc_atomic(a.out, body)

    if body["refused"]:
        print(
            "limit_class place: refused -- %s" % body["refusal_reason"],
            file=sys.stderr,
        )
        return EXIT_PLACE_REFUSED
    print(
        "limit_class place: placed %d agent(s) across %d eligible alias(es) "
        "(cap_per_alias=%s, max_assigned_count=%s)"
        % (
            fx.get("live_agents"),
            body["eligible_alias_count"],
            body["cap_per_alias"],
            body["max_assigned_count"],
        )
    )
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI (place) -- `limit_class.py place --fixture <fixture.json>
# --out <placement.json>` (fixtures/alias_spread/README.md's own
# binding-if-adopted CLI shape, reusing context/tier_route.py route's
# convention). Dispatched by `main()` on `argv[0] == "place"`, entirely
# separately from classify's own flag-only parser below, so neither
# entry point's shape disturbs the other's (see module docstring).
# ---------------------------------------------------------------------------
def build_place_arg_parser():
    p = argparse.ArgumentParser(
        prog="limit_class.py place",
        description="DEC-22 spread fan-out placement decision (plan T-B07; T136)",
    )
    p.add_argument(
        "--fixture",
        required=True,
        help="path to a placement-request fixture JSON (fixtures/alias_spread/*.json shape)",
    )
    p.add_argument(
        "--out",
        required=True,
        help="path to write the classified placement-verdict JSON document",
    )
    return p


# ---------------------------------------------------------------------------
# CLI (classify) -- the contract's own fixed invocation carries no
# subcommand token (`limit_class.py --signal <raw> --out <class.json>`),
# so none is added here; see module docstring "T136" section above for
# how `place` (T136) coexists with this unchanged shape.
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="limit_class.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--signal", required=True, help="verbatim raw limit-kill signal text")
    p.add_argument("--out", required=True, help="path to write the classified limit_signal JSON document")
    return p


def main(argv):
    # T136: dispatch to `place` on the literal leading token "place",
    # BEFORE classify's own parser (build_arg_parser) ever sees argv --
    # classify's contract-fixed invocation carries no subcommand token at
    # all (its first token is always "--signal"), so this branch can
    # never misroute a genuine classify invocation.
    if argv and argv[0] == "place":
        try:
            place_args = build_place_arg_parser().parse_args(argv[1:])
        except SystemExit as exc:
            raise exc
        return cmd_place(place_args)

    try:
        args = build_arg_parser().parse_args(argv)
    except SystemExit as exc:
        # argparse's own usage-error path already exits 2; normalise any
        # other SystemExit code argparse might raise (e.g. --help exits 0)
        # by re-raising it unchanged rather than reinterpreting it.
        raise exc
    if not isinstance(args.signal, str) or not isinstance(args.out, str) or not args.out:
        print("limit_class: --signal and --out are both required", file=sys.stderr)
        return EXIT_USAGE
    return cmd_classify(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
