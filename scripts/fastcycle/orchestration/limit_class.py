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

T140 Round 1 NO-GO, finding I5 (section 11.4.224(D)/C-003 determinism
proof, section 11.4.240 Producer != Verifier's sibling "re-run and
compare" discipline): `--determinism-check` re-invokes this SAME process
twice with the same argv (minus that one flag) and compares the two
runs' `--out` documents, exactly mirroring this SAME orchestration/
directory's `custody_sweep.py::run_determinism_check` (T137) -- that
tool's own body is this fix's exact working template. Adapted here
because neither of this file's two wire shapes (`classify`'s bare
{class, raw, resets_at} entity; `place`'s bare seven-key
placement-verdict entity -- both documented above under "Output shape")
carries a `body_hash` field the way custody_sweep's schema/body_hash-
wrapped documents do, so determinism is proven by hashing the WRITTEN
`--out` file's raw bytes directly rather than reading a `body_hash` key
out of its JSON body. Covers BOTH `classify` and `place` from one
re-invocation path -- the flag is recognised in `main()` BEFORE either
subcommand's own argv dispatch, so whichever shape the caller passed
(with or without a leading "place" token) is preserved verbatim and
simply re-run twice with its own `--out` overridden to a private tmp
path per run:

    limit_class.py --signal '<raw>' --out y.json --determinism-check
    limit_class.py place --fixture fx.json --out y.json --determinism-check

Exit codes (mirrors custody_sweep's own): 0 = deterministic (both runs'
`--out` bytes hash identically); 1 = nondeterministic (they differ); 4 =
inconclusive (a re-invocation timed out, crashed, or wrote no `--out`
document -- never silently read as "deterministic").

Stdlib only. Python 3.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile

try:
    import zoneinfo
except ImportError:  # pragma: no cover - Python < 3.9 fallback, not expected on this host
    zoneinfo = None

# T140 Round 6 review (section 11.4.250, section 11.4.227 reuse-not-
# reinvention): wiring to the sibling C-002 fc_common helpers -- identical
# import-by-path pattern to orchestration/handoff.py and
# orchestration/custody_sweep.py (this file had NO such wiring before Round
# 6; constitution/scripts/fastcycle has no __init__.py anywhere, matching
# this tree's existing flat-script layout). Used here for the shared
# `strict_loads` (reject non-finite JSON constants at parse time),
# `SAFE_EXCEPTIONS` (shared catch-all tuple), and `is_strict_nonneg_int`
# (shared "valid count/id" predicate) primitives -- never reimplemented
# independently in this file.
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)
import fc_entry  # noqa: E402  (T140 Round 10 review: the ONE shared CLI-entry
# primitive -- emit_result/diag channel split, FcArgumentParser, run_cli_main,
# safe_str, scan_argv_for_out, invalidate_stale_out -- see fc_entry.py's own
# module docstring; replaces this file's own former per-tool copies of every
# one of those, section 11.4.227/11.4.251)

diag = fc_entry.diag
safe_str = fc_entry.safe_str
scan_argv_for_out = fc_entry.scan_argv_for_out
invalidate_stale_out = fc_entry.invalidate_stale_out
FcArgumentParser = fc_entry.FcArgumentParser
run_cli_main = fc_entry.run_cli_main

EXIT_OK = 0
EXIT_UNPARSEABLE = 1  # classify: class "other" emitted -- contract's own "Exit codes" row
EXIT_PLACE_REFUSED = 1  # place: no eligible alias -- verdict document still written (T136's own decision, see module docstring)
EXIT_USAGE = 2

# ---------------------------------------------------------------------------
# T140 Round 10 independent review (docs/CONTINUATION.md ADDENDUM 114): the
# shared `_real_print`/`_safe_print`/`_safe_str`/`_scan_argv_for_out`/
# `_invalidate_stale_out` helpers this file used to define LOCALLY (Round
# 9/9b) are now imported, ONCE, from `fc_entry.py` above -- see that
# module's own docstring for the full rationale. Every stdout/stderr
# print in THIS file remains routed through `diag` (never `emit_result`):
# `--out` is always this tool's real deliverable for both `classify` and
# `place` (the contract's own fixed invocation shapes, module docstring),
# so a print here is genuinely informational, never the thing a caller
# must consume as the invocation's own result.
# ---------------------------------------------------------------------------

# T140 Round 7 review finding M3 (fixed here): `derive_placement`'s own
# `for i in range(live_agents):` loop has no upper bound -- a `live_agents`
# value like 10**12 (still a genuine, non-negative JSON integer, so
# `fc_common.is_strict_nonneg_int` alone does not refuse it) does not crash
# or refuse; it HANGS this tool for an unbounded amount of wall-clock time
# building/iterating an absurdly large range, which is worse than a crash
# (a hang gives no diagnosable exit code at all, and blocks whatever caller
# is waiting on this process -- section 11.4.6/11.4.101). A sane,
# generously-large upper bound rejects only genuinely nonsensical inputs:
# even a real fleet under this project's own multitrack orchestration
# (section 11.4.58/11.4.176) never approaches a live-agent count in the
# thousands, let alone this bound, and 1,000,000 iterations of the
# round-robin loop below still completes in well under a second on any
# realistic host, so this bound is never reached by a genuine placement
# request -- only by a malformed/adversarial one.
MAX_LIVE_AGENTS = 1_000_000

# T140 Round 11 review finding I1: the closed set of alias kinds DEC-22's
# native-first partition understands (fixtures/alias_spread/*.json, the module
# docstring's "kind: native|other" -- every real roster uses exactly these two).
# Anything else is refused by `_validate_placement_fixture_shape`, never
# silently bucketed as a provider.
KNOWN_ALIAS_KINDS = frozenset(("native", "provider"))

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


# T140 Round 11 review finding I4 (decision encoded here): a 429 that names a
# WEEKLY/SUBSCRIPTION/MONTHLY limit in words but attaches NO reset date, while
# ALSO carrying a retry-after value, is classified `cap`, not `rate-limited`.
# DEC-14's text left this combination ambiguous; the conservative reading wins
# because the two misclassifications are not symmetric -- treating a real
# weekly cap as a short throttle makes the resume RETRY on an alias that is
# capped for days (wasted dispatches, repeated kills), whereas treating a
# short throttle as a cap only rebinds to another operational alias early.
# resets_at stays UNKNOWN (no instant was named -- never fabricated).
_PERIODIC_CAP_PHRASE_RE = re.compile(
    r"\b(?:weekly|subscription|monthly)[\s_-]*(?:usage[\s_-]*)?(?:limit|cap|quota)",
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
        periodic_cap_named = _PERIODIC_CAP_PHRASE_RE.search(text) is not None
        # DEC-14 / AR-005's own disambiguator, an OR of two conditions:
        # cap = (no retry-after) OR (a named weekly/subscription reset).
        # Round 11 I4: a weekly/subscription/monthly limit named in words
        # (no date) also wins over a retry-after -- see
        # _PERIODIC_CAP_PHRASE_RE's own comment for the decision.
        if (not has_retry_after) or reset_named or periodic_cap_named:
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
    # T140 Round 6 review finding N2 (section 11.4.6, fixed here): plain
    # `json.dumps` defaults to `allow_nan=True`, so this call used to
    # silently emit the non-standard-JSON tokens `NaN`/`Infinity`/
    # `-Infinity` if `body` ever carried one -- producing an --out document
    # that LOOKS written (a real file, a clean exit) but is not valid JSON
    # per spec, and would itself crash any downstream STRICT reader (e.g.
    # this file's own `fc_common.strict_loads`, now wired in above). No
    # currently-reachable `body` value can carry a non-finite number today
    # (`cmd_classify`'s body is built entirely from regex-derived strings;
    # `cmd_place`'s `live_agents` is now guarded by
    # `fc_common.is_strict_nonneg_int`, which already rejects a float NaN
    # before `derive_placement` ever runs) -- `allow_nan=False` here is
    # deliberate defense-in-depth (section 11.4.250: fix the primitive, not
    # merely today's one reachable path) so a FUTURE field never silently
    # writes malformed JSON; the callers below now catch the resulting
    # ValueError alongside OSError.
    data = (json.dumps(body, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
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
    try:
        write_class_doc_atomic(a.out, body)
    except fc_common.SAFE_EXCEPTIONS as exc:
        # T140 Round 6 review finding R6-I2's sibling fix applied here too
        # (section 11.4.227 reuse-not-reinvention): an unwritable --out path
        # used to crash this subcommand uncaught the same way `cmd_place`'s
        # own write did before this round's fix. ValueError additionally
        # catches `write_class_doc_atomic`'s own N2 `allow_nan=False` fix.
        #
        # T140 Round 7 review finding R7-I1 (fixed here, defense-in-depth):
        # `write_class_doc_atomic`'s own `json.dumps(..., sort_keys=True)`
        # can raise `TypeError` (never ValueError/OSError) whenever `body`
        # ever carries a dict with mutually incomparable keys -- the exact
        # shape `cmd_place`'s own `assignment_alias_counts` dict can take
        # (see that write site's own identical widening below, and
        # `_validate_placement_fixture_shape`'s own R7-I2 fix, which closes
        # the one currently-reachable path to that TypeError at ITS
        # source). `cmd_classify`'s own `body` here is built entirely from
        # regex-derived strings, so this specific TypeError is not
        # currently reachable from THIS call site -- widened to the shared
        # `fc_common.SAFE_EXCEPTIONS` tuple anyway (section 11.4.6: never
        # assume a write site is safe merely because no crash has YET been
        # observed from it; section 11.4.227: the SAME shared tuple every
        # sibling fastcycle orchestration tool now ORs onto its own
        # write-site except-clauses, never a file-specific one-off).
        diag(
            "limit_class: cannot write --out %s: %s" % (a.out, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    if cls == CLASS_OTHER:
        diag(
            "limit_class: signal unparseable -- class 'other' emitted with the raw signal",
            file=sys.stderr,
        )
        return EXIT_UNPARSEABLE
    diag("limit_class: classified as %s (resets_at=%s)" % (cls, body["resets_at"]))
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


def _validate_placement_fixture_shape(fx):
    """T140 Round 5 review finding R5-I3: `derive_placement` above raises
    KeyError for a fixture MISSING `live_agents`/`aliases`/an alias
    entry's own required keys (by design -- its own docstring: "a
    malformed fixture is not this rule's problem to silently paper over"),
    and `cmd_place` already catches that KeyError as an honest EXIT_USAGE.
    But a field whose VALUE has the WRONG JSON TYPE (present, not
    missing) used to crash `cmd_place` UNCAUGHT with a bare Python
    TypeError -- and an uncaught crash's exit code (1) is
    INDISTINGUISHABLE from `EXIT_PLACE_REFUSED` (also 1, the intentional
    "no eligible alias" refusal), so a caller reading only the exit code
    could not tell a genuine crash from a deliberate refusal.

    Mirrors `orchestration/custody_sweep.py`'s own `cmd_verify_proposal`
    reference pattern (section 11.4.227 reuse-the-pattern): a wrong-type
    `action`/`entry_id`/`backup_hash` there resolves to a clean REFUSED
    verdict via ordinary `not in`/set-membership comparisons in
    `derive_verdict`, which never raise on a value of the wrong type. This
    function is the SAME idea applied here, as an explicit up-front check
    (since `derive_placement` itself, unlike `derive_verdict`, genuinely
    INDEXES into structured dicts/lists by field name and therefore cannot
    avoid a wrong-type crash purely through membership-test-shaped code).

    CORRECTION (T140 Round 6 review finding R6-I3, section 11.4.6 -- an
    earlier revision of THIS docstring claimed `cmd_verify_proposal`
    "ALREADY handles equivalent malformed inputs cleanly" WITHOUT
    qualification; that claim was WRONG, not merely imprecise): a
    --proposal top-level JSON value that is a NON-ITERABLE scalar (a bare
    int or `null` -- as opposed to a list, which the claim's own
    parenthetical correctly reasoned about) crashed `cmd_verify_proposal`
    UNCAUGHT at its `k not in d` membership check (`TypeError: argument of
    type 'int' is not iterable`), and a wrong-type `backup_artifact_path`
    (e.g. a JSON list) separately crashed `derive_verdict` uncaught at
    `os.path.isabs()`/`os.path.join()`. Both gaps are now fixed in that
    function (an up-front `isinstance(d, dict)` check, plus explicit
    string-type checks on `backup_hash`/`backup_artifact_path`, both
    returning its own EXIT_USAGE(2) before either crash site can be
    reached) -- the claim is accurate again as of that fix, but is
    recorded here with its correction rather than silently re-asserted,
    since a docstring that was wrong once and is merely re-stated
    identically gives a future reader no signal that it was ever
    independently re-verified.

    Returns a diagnosable message (naming the bad field + expected type +
    actual type/value) if `fx`'s top-level shape is malformed, or None if
    it is well-formed enough for `derive_placement` to safely index into
    (a MISSING field is left to the existing KeyError path, exactly as
    before -- this function checks TYPE, never PRESENCE)."""
    if not isinstance(fx, dict):
        return "--fixture top-level value is not a JSON object (got %s: %r)" % (
            type(fx).__name__, fx)
    if "live_agents" in fx:
        live_agents = fx["live_agents"]
        # T140 Round 6 review finding R6-I2 (section 11.4.250, fixed here):
        # `isinstance(live_agents, int)` alone wrongly ACCEPTS a JSON `true`/
        # `false` -- Python's `bool` is a subclass of `int`, so
        # `live_agents: true` silently passed this check and was then
        # treated as `1` by `range(True)` below, placing exactly one agent
        # for a fixture that never declared a sane integer count. It also
        # wrongly accepted a NEGATIVE count (`live_agents: -5`), which
        # `range(-5)` silently turns into zero placements with rc=0 --
        # "worked" on a nonsensical input with no trace anything was wrong.
        # `fc_common.is_strict_nonneg_int` (shared, section 11.4.227) rejects
        # both: a genuine bool, and any negative integer.
        if not fc_common.is_strict_nonneg_int(live_agents):
            return "field `live_agents` must be a non-negative JSON integer (got %s: %r)" % (
                type(live_agents).__name__, live_agents)
        # T140 Round 7 review finding M3 (see MAX_LIVE_AGENTS's own
        # module-level comment above for the full rationale): a genuine,
        # non-negative integer that is simply ABSURDLY large (e.g. 10**12)
        # passes the check above unrejected and then HANGS `derive_placement`'s
        # `range(live_agents)` loop indefinitely -- reject it here instead,
        # with the SAME diagnosable EXIT_USAGE convention every other
        # malformed-`live_agents` case above already uses.
        elif live_agents > MAX_LIVE_AGENTS:
            return ("field `live_agents` (%d) exceeds this tool's own sane upper bound (%d) -- "
                    "no genuine placement request approaches this many live agents, and "
                    "iterating a range this large would hang rather than crash or refuse "
                    "promptly") % (live_agents, MAX_LIVE_AGENTS)
    if "aliases" in fx:
        aliases = fx["aliases"]
        if not isinstance(aliases, list):
            return "field `aliases` must be a JSON list (got %s: %r)" % (
                type(aliases).__name__, aliases)
        # T140 Round 7 review finding R7-I2 (section 11.4.250, fixed here):
        # `derive_placement` below fails OPEN (not merely crashes) on
        # duplicate or type-colliding `alias` values -- e.g. two entries
        # both carrying `alias: "A"`, or one carrying `alias: 1` (int) and
        # another `alias: true` (bool, `1 == True` in Python and hashes
        # identically). `eligible = natives + providers` is a LIST (its
        # length `m` is the round-robin spread's own denominator, computed
        # correctly regardless of duplicates), but
        # `assignment_alias_counts = {alias: 0 for alias in eligible}` is a
        # DICT keyed by that SAME `alias` value -- a dict literal SILENTLY
        # COLLAPSES duplicate/colliding keys, so two nominally-distinct
        # eligible slots pointing at the SAME `assignment_alias_counts` key
        # both accumulate their round-robin assignments onto that ONE key,
        # letting `max_assigned_count` exceed `cap_per_alias` -- exactly
        # the "concentrate blast radius on one alias" outcome DEC-22 exists
        # to PREVENT (see this file's own module docstring "(a) fill-first
        # -- rejected: concentrates blast radius"), reproduced silently by
        # a malformed roster rather than a malformed placement DECISION.
        # `alias` is, by this whole system's own established convention
        # (section 11.4.196/11.4.182: an alias is always a human-readable
        # CLI-account name string, e.g. "claude1"/"deepseek"), NEVER
        # anything but a non-empty string -- so the fix REQUIRES that here,
        # refusing (never silently coercing/accepting) a non-string or a
        # value duplicating an EARLIER entry's alias, at THIS shape-check
        # layer, before `derive_placement` ever runs. Checked across the
        # WHOLE `aliases` roster (not merely the eligible subset) -- a
        # duplicate alias entry is a malformed input regardless of whether
        # today's `operational`/`near_cap` flags happen to make it
        # eligible, and refusing it here is strictly safer than silently
        # accepting it and letting a LATER config change (flipping
        # `operational` to true) resurrect the same silent-collapse bug.
        seen_aliases = set()
        for i, entry in enumerate(aliases):
            if not isinstance(entry, dict):
                return "aliases[%d] is not a JSON object (got %s: %r)" % (
                    i, type(entry).__name__, entry)
            if "alias" in entry:
                alias_val = entry["alias"]
                if not isinstance(alias_val, str) or not alias_val:
                    return ("aliases[%d].alias must be a non-empty JSON string (got %s: %r) -- "
                            "derive_placement's assignment_alias_counts dict is keyed by this "
                            "value, and a non-string/empty alias risks silently colliding with "
                            "another entry's key") % (i, type(alias_val).__name__, alias_val)
                if alias_val in seen_aliases:
                    return ("aliases[%d].alias %r duplicates an earlier entry's alias -- DEC-22's "
                            "round-robin spread requires every eligible alias identify a "
                            "genuinely distinct target; a duplicate alias silently collapses "
                            "assignment_alias_counts's dict key while the spread's own "
                            "denominator (m = len(eligible)) still counts both entries "
                            "separately, letting more agents land on the one real alias than "
                            "cap_per_alias permits") % (i, alias_val)
                seen_aliases.add(alias_val)
            # T140 Round 11 review finding I1 (fixed here): the SAME
            # type-confusion class R6-I2 closed for `live_agents` recurred
            # on three sibling fields that were never checked, each
            # SILENTLY misclassifying the alias (reproduced live):
            #   operational:"false" (a STRING) is truthy -> the alias was
            #     marked eligible and assigned 2 agents, rc=0;
            #   near_cap:null is falsy -> silently "not near cap";
            #   kind:["native"] (a list) -> silently a provider.
            # `operational`/`near_cap` must be genuine JSON booleans and
            # `kind` a string from the closed set KNOWN_ALIAS_KINDS -- any
            # other shape is REFUSED (EXIT_USAGE), never coerced or
            # defaulted (section 11.4.6: guessing an alias's eligibility is
            # exactly the misplacement DEC-22 exists to prevent).
            for bool_field in ("operational", "near_cap"):
                if bool_field in entry and not isinstance(entry[bool_field], bool):
                    return ("aliases[%d].%s must be a JSON boolean true/false (got %s: %r) -- a "
                            "non-boolean is never coerced (\"false\" as a string is truthy)") % (
                                i, bool_field, type(entry[bool_field]).__name__, entry[bool_field])
            if "kind" in entry:
                kind_val = entry["kind"]
                if not isinstance(kind_val, str) or kind_val not in KNOWN_ALIAS_KINDS:
                    return ("aliases[%d].kind must be one of %s (got %s: %r)") % (
                        i, sorted(KNOWN_ALIAS_KINDS), type(kind_val).__name__, kind_val)
    return None


def cmd_place(a):
    try:
        with open(a.fixture, encoding="utf-8") as fh:
            # T140 Round 6 review finding R6-I1(b)'s sibling fix applied here
            # too (section 11.4.227 reuse-not-reinvention): `strict_loads`,
            # never plain `json.load`, so a non-finite JSON constant
            # anywhere in --fixture is refused HERE, at parse time, rather
            # than risking a later crash if some future field ever echoes a
            # raw fixture value back into `body` unchanged.
            fx = fc_common.strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        diag(
            "limit_class place: cannot read/parse --fixture %s: %s" % (a.fixture, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    shape_error = _validate_placement_fixture_shape(fx)
    if shape_error is not None:
        diag(
            "limit_class place: fixture %s has a malformed field: %s"
            % (a.fixture, shape_error),
            file=sys.stderr,
        )
        return EXIT_USAGE

    try:
        body = derive_placement(fx)
    except KeyError as exc:
        diag(
            "limit_class place: fixture %s is missing a required field: %s"
            % (a.fixture, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE
    except fc_common.SAFE_EXCEPTIONS as exc:
        # T140 Round 5 review finding R5-I3, DEFENSE IN DEPTH (never a
        # substitute for the up-front shape check above -- section
        # 11.4.6, that check is not claimed exhaustive): a genuinely
        # unanticipated wrong-type field still fails closed with
        # EXIT_USAGE and a diagnosable message naming the real exception,
        # never an uncaught crash landing on EXIT_PLACE_REFUSED's own
        # exit code.
        #
        # T140 Round 6 review finding R6-I2 (section 11.4.250, WIDENED
        # here): was `except TypeError` alone -- too narrow, as Round 6
        # itself demonstrated: `live_agents` set high enough that
        # `live_agents / m` (true division, promoting to a Python float)
        # cannot be represented as a float raises `OverflowError` at the
        # `math.ceil(...)` call inside `derive_placement`, uncaught, also
        # colliding with EXIT_PLACE_REFUSED's own exit code (1). Widened to
        # the shared `fc_common.SAFE_EXCEPTIONS` tuple (TypeError,
        # ValueError, OSError, OverflowError) -- the SAME shared tuple every
        # sibling fastcycle orchestration tool now ORs onto its own
        # narrower except-clauses, never a fourth independently-guessed one
        # (section 11.4.227).
        diag(
            "limit_class place: fixture %s raised an unanticipated %s while "
            "placing: %s" % (a.fixture, type(exc).__name__, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    try:
        write_class_doc_atomic(a.out, body)
    except fc_common.SAFE_EXCEPTIONS as exc:
        # T140 Round 6 review finding R6-I2 (section 11.4.250, fixed here):
        # this write used to be entirely unwrapped -- an unwritable --out
        # path (parent directory missing/not writable/a permissions error)
        # crashed uncaught with no honest verdict at all. Fail CLOSED with
        # its own diagnosable EXIT_USAGE, matching the exit-code convention
        # every OTHER malformed-input case above already uses (never
        # colliding with EXIT_OK=0 or EXIT_PLACE_REFUSED=1). ValueError
        # additionally catches `write_class_doc_atomic`'s own N2
        # `allow_nan=False` fix.
        #
        # T140 Round 7 review finding R7-I1 (fixed here): was
        # `except (OSError, ValueError)` -- too narrow. `body` here
        # includes `assignment_alias_counts`, a dict keyed by each eligible
        # entry's `alias` value; `json.dumps(..., sort_keys=True)` raises
        # `TypeError` (never ValueError) when sorting a dict whose keys are
        # not mutually comparable (e.g. a str alongside an int) -- the
        # EXACT class a mixed-type `aliases` roster (`["a", 1]`) used to
        # produce here, uncaught, before landing on Python's own default
        # exit code 1 (colliding with EXIT_PLACE_REFUSED). Widened to the
        # shared `fc_common.SAFE_EXCEPTIONS` tuple (section 11.4.227) as
        # defense-in-depth, alongside `_validate_placement_fixture_shape`'s
        # own R7-I2 fix immediately above (which now refuses a non-string/
        # duplicate `alias` before `derive_placement` -- and therefore
        # this write -- ever runs, closing the currently-reachable path to
        # this TypeError at its source).
        diag(
            "limit_class place: cannot write --out %s: %s" % (a.out, exc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    if body["refused"]:
        diag(
            "limit_class place: refused -- %s" % body["refusal_reason"],
            file=sys.stderr,
        )
        return EXIT_PLACE_REFUSED
    diag(
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
    # T140 Round 10 review finding I1(a) (fixed here): `FcArgumentParser`
    # (not the stdlib `argparse.ArgumentParser` directly) routes argparse's
    # own `--help`/usage-error message printing through `diag()` instead of
    # a raw `file.write(...)` -- see `fc_entry.FcArgumentParser`'s own
    # docstring for the full rationale. This parser's own `description=`
    # is a literal string, never `__doc__.split(...)`, so it was never
    # affected by the `-OO` crash class this round's sibling fix addresses
    # elsewhere -- but the raw-write path through `_print_message` applied
    # here regardless.
    p = FcArgumentParser(
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
    # T140 Round 9b review finding R9b-I1 (fixed here): `__doc__` is `None`
    # under `python -OO`/`PYTHONOPTIMIZE=2` -- `__doc__.split(...)` raised
    # an uncaught `AttributeError` HERE, before ANY of this function's own
    # argument definitions ran, escaping `main()` entirely (see `main()`'s
    # own boundary widening below for the defense-in-depth half of this
    # same fix). `(__doc__ or "")` makes this call site simply never
    # crash, matching `handoff.py`'s/`custody_sweep.py`'s own identical
    # sibling fix.
    #
    # T140 Round 10 review finding I1(a) (fixed here): `FcArgumentParser`
    # -- see `build_place_arg_parser`'s own comment above, and
    # `fc_entry.FcArgumentParser`'s own docstring, for the full rationale.
    p = FcArgumentParser(prog="limit_class.py", description=(__doc__ or "").split("\n\n")[0])
    p.add_argument("--signal", required=True, help="verbatim raw limit-kill signal text")
    p.add_argument("--out", required=True, help="path to write the classified limit_signal JSON document")
    return p


# ---------------------------------------------------------------------------
# --determinism-check (T140 Round 1 NO-GO, finding I5; section 11.4.224(D)/
# C-003): re-invoke this SAME process twice with the same argv (minus the
# flag) and compare the resulting --out document's bytes. Modelled directly
# on this SAME orchestration/ directory's custody_sweep.py::
# run_determinism_check (T137) -- that tool's own body already implements
# this correctly and is this fix's exact working template (T140's recorded
# finding I5) -- adapted here because neither of this file's two wire
# shapes (`classify`'s bare {class, raw, resets_at} entity, `place`'s bare
# seven-key placement-verdict entity; both documented in this file's own
# module docstring "Output shape" sections) carries a `body_hash` field the
# way custody_sweep's own schema/body_hash-wrapped documents do -- so
# determinism here is proven by hashing the WRITTEN --out file's raw bytes
# directly, rather than reading a `body_hash` key out of its JSON body.
# Covers BOTH of this file's subcommands (`classify` and `place`) from ONE
# re-invocation path, since the check below runs (from `main()`) before
# either entry point's own argv dispatch -- whichever shape the caller
# passed (with or without a leading "place" token) is preserved verbatim in
# `inner` and simply re-run twice with its own `--out` overridden to a
# private tmp path per run (argparse's own last-value-wins behaviour on a
# repeated single-value option is relied on here, exactly as
# custody_sweep's template also relies on it).
# ---------------------------------------------------------------------------
def run_determinism_check(argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    hashes = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                diag("limit_class: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                # T140 Round 10 review finding I1(c) (fixed here): see
                # `handoff.py`'s own identically-purposed sibling fix for
                # the full rationale -- a raw `sys.stderr.write(...)`
                # bypassed the diag()/emit_result() channel split entirely.
                diag(proc.stderr, end="", file=sys.stderr)
                diag("limit_class: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, "rb") as fh:
                hashes.append(hashlib.sha256(fh.read()).hexdigest())
    if hashes[0] != hashes[1]:
        diag("limit_class: nondeterministic: run1=%s run2=%s" % (hashes[0], hashes[1]),
              file=sys.stderr)
        return 1
    diag("limit_class: deterministic (out_sha256=%s)" % hashes[0])
    return 0


def _write_dispatch_internal_error_doc(out_path, subcommand, exc):
    """T140 Round 7 review (section 11.4.250 heuristic-tower/primitive-
    defect -- mirrors `custody_sweep.py`'s own identically-purposed
    `_write_dispatch_internal_error_doc`/`handoff.py`'s own identically-
    purposed helper, section 11.4.227 reuse-the-SAME-discipline): on ANY
    exception escaping `cmd_place`/`cmd_classify` and being caught by
    `main()`'s dispatch boundary below, this tool MUST still write SOME
    document to --out (when one was requested) rather than leaving a
    stale or entirely absent --out file -- the audit trail (section
    11.4.5/11.4.69) is never silently lost regardless of what crashed.
    Reuses `write_class_doc_atomic` (never a second writer) -- this
    file's own wire formats carry no schema/body_hash envelope (module
    docstring: "no extra envelope... this is the literal sub-object"), so
    the minimal error doc matches that SAME bare-object convention rather
    than inventing a new one. Best-effort: a write failure here is itself
    swallowed (never raised a second time out of an already-failing
    error path) -- the caller's stderr diagnostic in main() is what
    remains authoritative in that doubly-unlucky case.

    T140 Round 8 review finding R8-I1(d) (fixed here): was `except
    fc_common.SAFE_EXCEPTIONS` -- widened to bare `Exception`, the SAME
    widening `main()`'s own two dispatch boundaries below receive, so
    this best-effort write can never itself escape with a different,
    still-uncaught exception class (e.g. a `TypeError` from
    `write_class_doc_atomic`'s own `json.dumps(..., sort_keys=True)` on a
    mutually-incomparable-keys `body` -- `TypeError` IS already a
    `fc_common.SAFE_EXCEPTIONS` member, so this specific widening is
    consistency with the OTHER two sibling tools' identical fixes rather
    than closing a NEW crash class here).

    T140 Round 9 review finding R9-M1 (fixed here): `str(exc)` replaced
    with `safe_str(exc)`."""
    if not out_path:
        return
    body = {"subcommand": subcommand, "internal_error": {"class": type(exc).__name__, "detail": safe_str(exc)}}
    try:
        write_class_doc_atomic(out_path, body)
    except Exception:
        pass


def main(argv):
    # T140/I5: --determinism-check is recognised BEFORE either subcommand's
    # own argv dispatch below (classify's flag-only shape, or the leading
    # "place" token), so it applies uniformly to both entry points sharing
    # this one file -- see run_determinism_check's own docstring comment
    # above.
    if "--determinism-check" in argv:
        # T140 Round 8 review finding R8-I1 minor (a) (fixed here):
        # `run_determinism_check` used to run entirely OUTSIDE this
        # function's own dispatch boundary. Wrapped in the SAME bare
        # `except Exception` this function's own subcommand dispatch below
        # now uses (section 11.4.227 reuse-not-reinvention) -- no single
        # caller-level `--out` document exists to write an internal-error
        # doc to here (each subprocess run already writes its OWN --out
        # inside a throwaway temp dir, per `run_determinism_check`'s own
        # body), so this boundary is diagnostic-message-only.
        try:
            return run_determinism_check(argv)
        except Exception as exc:
            diag("limit_class: --determinism-check raised an uncaught %s: %s -- this is a "
                  "genuinely unanticipated case; treat as unsafe/unverified until independently, "
                  "manually re-verified" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
            return EXIT_USAGE

    # T136: dispatch to `place` on the literal leading token "place",
    # BEFORE classify's own parser (build_arg_parser) ever sees argv --
    # classify's contract-fixed invocation carries no subcommand token at
    # all (its first token is always "--signal"), so this branch can
    # never misroute a genuine classify invocation.
    if argv and argv[0] == "place":
        place_args = None
        try:
            # T140 Round 9b review finding R9b-I1 (fixed here, point 1 of
            # that round's own prescription): argument-parser CONSTRUCTION
            # and PARSING now live INSIDE the SAME dispatch boundary as
            # `cmd_place`'s own dispatch, not before it -- previously only
            # `cmd_place`'s own call was wrapped, so a crash in
            # `build_place_arg_parser()`/`parse_args()` itself escaped
            # uncaught (this file's own `build_place_arg_parser` uses a
            # literal `description=` string, never `__doc__.split(...)`,
            # so it is not affected by THIS round's specific `-OO` repro
            # today -- but the boundary is widened defensively per
            # section 11.4.227 reuse-the-SAME-discipline, exactly as
            # `classify`'s own boundary below, so any FUTURE crash in
            # this branch's own parser construction/parsing is covered
            # too).
            place_args = build_place_arg_parser().parse_args(argv[1:])
            # T140 Round 11 review finding I3 (fixed here): once argv has PARSED, this
            # invocation's --out is genuinely this run's designated output -- a stale
            # document from an earlier run must not survive ANY handled exit below (a
            # rc=1 refusal / rc=2 config error that writes nothing used to leave the
            # PREVIOUS run's verdict there, looking current; C-001). A pure argparse
            # usage error (SystemExit before this line) still leaves --out untouched,
            # per Round 10 finding M3 (guarded by the r9 regression suites).
            invalidate_stale_out(getattr(place_args, "out", None))
            return cmd_place(place_args)
        except SystemExit:
            # argparse's own usage-error/--help path; unaffected by the
            # bare-Exception widening immediately below (SystemExit is
            # not a subclass of Exception) -- re-raised unchanged.
            raise
        except Exception as exc:
            # T140 Round 7 review, the ONE top-level dispatch boundary
            # wrapping EVERY subcommand this file dispatches to (see
            # _write_dispatch_internal_error_doc's own docstring
            # immediately above): a genuinely unanticipated crash escaping
            # `cmd_place` -- past every one of its own already-wrapped
            # internal try/except blocks (R5-I3/R6-I2/R6-I3/R7-I1/R7-I2
            # above) -- still fails CLOSED here with an honest, diagnosable
            # message, a real --out write, and this tool's own established
            # EXIT_USAGE convention.
            #
            # T140 Round 8 review finding R8-I1 (WIDENED here): was
            # `except fc_common.SAFE_EXCEPTIONS` -- Round 8's own live
            # fuzzing (5,000 random-field-mutation variants, verified
            # first against a deliberately-broken script to confirm it
            # genuinely catches crashes) proved this narrower catch set
            # still let `KeyError`/`IndexError`/`AttributeError`/
            # `RecursionError` escape uncaught in this file -- proven live
            # by injecting a `KeyError` at the very TOP of `cmd_place`
            # (before ANY of its own internal try/excepts could run).
            # Widened to bare `Exception` -- deliberately NEVER
            # `BaseException`: `SystemExit`/`KeyboardInterrupt` are NOT
            # subclasses of `Exception`, so an operator interrupt or this
            # process's own `sys.exit()` correctly stays UNCAUGHT here.
            # `fc_common.SAFE_EXCEPTIONS` itself is UNCHANGED -- only this
            # ONE top-level dispatch boundary is widened, the fix Round
            # 8's own review recommended directly: "the fix is to change
            # what the boundary catches to `Exception`, not to add one
            # more type to the list."
            #
            # T140 Round 9/9b review (fixed here): `out_path`/
            # `fixture_label` resolve honestly even when `place_args` was
            # never successfully parsed (a build_place_arg_parser()/
            # parse_args() crash) -- falling back to the raw-argv scan /
            # "?" respectively -- and the --out document write happens
            # BEFORE the diagnostic print (point 4), through
            # `diag` (never able to escape and corrupt an
            # already-written --out doc, point 4's own general fix, or
            # exit 120 on a closed stderr, R9-I1's own fix).
            #
            # T140 Round 10 review finding M3, first half (fixed here): the
            # pre-invalidation this file's own `main()` used to run
            # UNCONDITIONALLY at the very top (before any argument parsing
            # was even attempted, covering BOTH subcommands with one scan)
            # is now made ONLY here, in the one place a genuinely
            # unanticipated crash is actually being handled -- see
            # `handoff.py`'s own identically-purposed sibling fix for the
            # full rationale (a pure usage error no longer deletes a
            # caller's pre-existing, unrelated `--out` file).
            out_path = getattr(place_args, "out", None) if place_args is not None else scan_argv_for_out(argv)
            fixture_label = getattr(place_args, "fixture", "?") if place_args is not None else "?"
            invalidate_stale_out(out_path)
            _write_dispatch_internal_error_doc(out_path, "place", exc)
            diag("limit_class place: fixture %s raised an uncaught %s while dispatching: %s -- "
                  "this is a genuinely unanticipated case no individual fix above enumerated; "
                  "treat as unsafe/unverified until independently, manually re-verified"
                  % (fixture_label, type(exc).__name__, safe_str(exc)), file=sys.stderr)
            return EXIT_USAGE

    args = None
    try:
        # T140 Round 9b review finding R9b-I1 (fixed here, point 1 of
        # that round's own prescription): argument-parser CONSTRUCTION
        # and PARSING, THIS file's own field-shape check, AND
        # `cmd_classify`'s own dispatch now all live INSIDE ONE boundary
        # -- previously `build_arg_parser()`/`parse_args()` sat entirely
        # OUTSIDE any bare-Exception boundary (only `except SystemExit`
        # wrapped it), so this file's own `__doc__.split(...)` crash
        # under `python -OO` (fixed at its source above) used to escape
        # `main()` ENTIRELY uncaught, exactly like the `place` branch's
        # own equivalent gap immediately above.
        args = build_arg_parser().parse_args(argv)
        # T140 Round 11 review finding I3 (fixed here): once argv has PARSED, this
        # invocation's --out is genuinely this run's designated output -- a stale
        # document from an earlier run must not survive ANY handled exit below (a
        # rc=1 refusal / rc=2 config error that writes nothing used to leave the
        # PREVIOUS run's verdict there, looking current; C-001). A pure argparse
        # usage error (SystemExit before this line) still leaves --out untouched,
        # per Round 10 finding M3 (guarded by the r9 regression suites).
        invalidate_stale_out(args.out if isinstance(getattr(args, "out", None), str) else None)
        if not isinstance(args.signal, str) or not isinstance(args.out, str) or not args.out:
            diag("limit_class: --signal and --out are both required", file=sys.stderr)
            return EXIT_USAGE
        return cmd_classify(args)
    except SystemExit:
        # argparse's own usage-error path already exits 2; normalise any
        # other SystemExit code argparse might raise (e.g. --help exits 0)
        # by re-raising it unchanged rather than reinterpreting it --
        # unaffected by the bare-Exception widening immediately below.
        raise
    except Exception as exc:
        # Same top-level dispatch boundary as `place` above, for
        # `classify` -- T140 Round 8 review finding R8-I1, identically
        # widened (see the `place` branch's own comment immediately
        # above for the full rationale, proven live for THIS handler too
        # via `cmd_validate`/`cmd_verify_proposal`'s sibling
        # KeyError-injection proofs across the other two fastcycle
        # orchestration tools). T140 Round 9/9b (fixed here): `out_path`
        # resolves honestly even when `args` was never successfully
        # parsed, and the --out document write happens BEFORE the
        # diagnostic print, through `diag` -- see the `place`
        # branch's own comment immediately above for the full rationale.
        # T140 Round 10 review finding M3 (fixed here): pre-invalidation
        # now happens ONLY here too -- see the `place` branch's own
        # comment immediately above for the full rationale.
        out_path = getattr(args, "out", None) if args is not None else scan_argv_for_out(argv)
        invalidate_stale_out(out_path)
        _write_dispatch_internal_error_doc(out_path, "classify", exc)
        diag("limit_class: classify raised an uncaught %s while dispatching: %s -- this is a "
              "genuinely unanticipated case no individual fix above enumerated; treat as "
              "unsafe/unverified until independently, manually re-verified"
              % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
        return EXIT_USAGE


if __name__ == "__main__":
    # T140 Round 10 review, "Recommended root-cause work" item 1 (fixed
    # here): `run_cli_main` -- see `handoff.py`'s own identically-purposed
    # sibling fix for the full mechanism.
    run_cli_main(main, sys.argv[1:])
