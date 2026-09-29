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

Extension point for T136 (plan T-B06's sibling "place" decision, a
SEPARATE, LATER task landing in this SAME file per operator instruction):
this module deliberately keeps `classify_signal` / `cmd_classify` /
`build_arg_parser` as clearly separable units and adds no subcommand
wrapper around the CLI's flags (the contract's own invocation
`--signal <raw> --out <class.json>` carries no subcommand token, so none
is invented here) -- T136 is free to extend `build_arg_parser` (e.g. a
new `--place`-shaped flag set or a genuinely separate invocation form) and
add its own top-level function(s) below this file's `classify_signal`
without disturbing this task's contract-fixed CLI shape or its exit-code
table.

Stdlib only. Python 3.
"""
import argparse
import datetime
import json
import os
import re
import sys
import tempfile

try:
    import zoneinfo
except ImportError:  # pragma: no cover - Python < 3.9 fallback, not expected on this host
    zoneinfo = None

EXIT_OK = 0
EXIT_UNPARSEABLE = 1  # class "other" emitted -- contract's own "Exit codes" row
EXIT_USAGE = 2

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
# CLI -- the contract's own fixed invocation carries no subcommand token
# (`limit_class.py --signal <raw> --out <class.json>`), so none is added
# here; see module docstring "Extension point for T136".
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="limit_class.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--signal", required=True, help="verbatim raw limit-kill signal text")
    p.add_argument("--out", required=True, help="path to write the classified limit_signal JSON document")
    return p


def main(argv):
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
