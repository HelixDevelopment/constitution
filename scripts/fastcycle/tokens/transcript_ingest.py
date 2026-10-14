#!/usr/bin/env python3
"""transcript_ingest.py — real Claude Code transcript -> usage-only telemetry
ingest (SpecKit-004 "fast-dev-cycles", User Story 1, T038; plan T-A06;
FR-013, FR-001, SC-005, SC-001; guarded by
constitution/scripts/fastcycle/tests/test_token_attribution_red.sh, T020).

=============================================================================
CREDENTIAL SAFETY (§11.4.10) — READ THIS BEFORE TOUCHING THIS FILE
=============================================================================
Real Claude Code transcripts carry full conversational message CONTENT
(`message["content"]`) alongside usage/token metadata. This module extracts
and persists ONLY usage counts, model identifiers, and structural ids
(session id, agent id, message id, timestamps) — it NEVER EXTRACTS
`message["content"]` (or any nested field under it, e.g. a `tool_use`
block's `input.description`) via a dict-key access, for any purpose,
anywhere in this file — not even to hash it, log it, or check its length
(precision note, T038 independent review finding F5, 2026-09-28: ordinary
JSON decoding of a whole JSONL record necessarily loads its full bytes,
`content` included, into a Python dict in memory as part of parsing that
line at all — the guarantee this module makes is that NOTHING is ever
READ OUT of that parsed structure, via a key access or otherwise, beyond
the narrow set of fields named above, and nothing beyond that narrow set
is ever retained past the parse of a single line or reaches this module's
output). Grep this file for the literal substring `"content"` before
believing that claim; it must never appear as a dict-key access on a
`message` object.

The ONE place this module reads free text at all is `toolUseResult`
(present on the tool-RESULT `user` record that follows an Agent/Task
dispatch's `tool_use` block) — a SIBLING top-level key to `message`, not
nested under it, carrying dispatch bookkeeping (`agentId`, `description`,
`resolvedModel`, `outputFile`, ...) rather than conversational content. Even
there, this module extracts ONLY the narrow, regex-matched
`item=<prefix>-<digits>` (or the honest `item=?`) token from `description`
— the SAME configurable `item=(<prefix1>|<prefix2>|...)-[0-9]+|\\?`
convention `tokens/dispatch_stamp.sh` (T036) already established on this
SAME field (default prefix derived per-checkout via `release_prefix.sh`,
e.g. "ATM" for this checkout — never hardcoded, see the ITEM_TAG_RE
DECOUPLING FIX comment below) — and NEVER persists the raw `description`
string itself.

=============================================================================
SCHEMA DECISION (documented per task instruction) — a NEW table, not new
columns on the EXISTING `usage_events` table, in the SAME db FILE
=============================================================================
plan.md T-A06 states this tool "writes into the EXISTING WS1 R0 telemetry
DB under docs/research/tokens/, not a new store" (tasks.md T038 repeats
this verbatim). The R0 prototype this extends,
`docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.py`,
already ships one table, `usage_events`, whose CLI (`ingest <flat.jsonl>`)
consumes a DIFFERENT, pre-flattened record shape a caller supplies directly
(`{ts, track, alias, model, input_tokens, ...}`, all four scalar identity
columns `NOT NULL`) — proven, by running it against every real-schema
fixture this task ships (captured in this task's evidence directory), to
REJECT a genuine Claude Code transcript outright (`ts` is missing at
transcript top level) and, on its own flat schema, to silently coerce an
ABSENT token-count field to `0` with no distinguishing signal (the exact
missing-vs-zero bluff property (c) below exists to close).

Given that:
  - `usage_events`'s `track`/`alias` columns are `NOT NULL` scalar identity
    fields a flat record supplies directly; a real transcript record has
    NEITHER field (track/alias are a DIFFERENT §11.4.182 label-derivation
    concern this task's own RED test never exercises) — forcing them would
    mean inventing values never asked for (§11.4.6) or widening the column
    to nullable and polluting `usage_events`' existing NOT-NULL semantics
    (which OTHER tooling, e.g. `usage_telemetry.py report --group-by
    track|alias`, already relies on);
  - `usage_events` has no column for `session_id`/`agent_id`/`item_id`/a
    missing-vs-measured flag/`missing_instrument` — all REQUIRED by this
    task's properties (c) and (d);
  - the tool being extended is explicit that "no tool retries [/writes] a
    struct it does not understand" and that additive migration (adding,
    never dropping/renaming — matching this project's own precedent of
    additive-only schema evolution, e.g. `docs/workable_items.db`'s
    `occurred_at` column addition) is the safe path;

this module creates a SECOND table, `transcript_usage_events`, in the SAME
db FILE (same `--db` path / same `DEFAULT_DB` default as
`usage_telemetry.py`'s own `DEFAULT_DB`) — additive at the FILE level (one
store, "not a new store"), never touching, dropping, renaming, or alling
NOT-NULL-incompatible data into the pre-existing `usage_events` table. This
keeps both tables' semantics internally consistent: `usage_events` remains
exactly what `usage_telemetry.py` already understands; `transcript_usage_events`
is the real-transcript-derived table this tool owns.

=============================================================================
IDEMPOTENCY / DEDUP KEY (informed by prior real-world evidence in this SAME
project)
=============================================================================
The sibling R0 investigation `ingest_claude_transcript.py` (captured
2026-07-08, same POC directory) found, from REAL captured transcripts, that
Claude Code streams MULTIPLE JSONL lines per logical assistant turn (one
per content block), so a per-LINE dedup key (line number, or a per-line
`uuid`) would count one logical turn's tokens N times over. That script
also claimed each line carries an IDENTICAL cumulative `usage` block; that
claim is FALSE (T048 restart review R3-F1, re-measured 2026-10-08 on the
300 newest real transcripts of this host: 12,028 msg ids repeat across
lines, 1,357 of them with DIFFERENT usage; only output_tokens differs, it
never decreases along the file, and the last line always carries the
maximum). Keeping the first-seen line undercounted output tokens (14.6x on
one real subagent transcript). This module therefore MERGES every line of a
msg id into one row by taking the per-field MAXIMUM of the four cumulative
counters (see `merge_usage()`), within a run AND across runs (a live
transcript re-ingested after it grew updates its existing row). A later
value that is SMALLER than the stored one cannot come from streaming
growth, so it is reported on stderr (see `upsert_row()`) while
the maximum is still kept. That script's own fix was to key on
`(sessionId, requestId)` instead of per-line identity; this module's own
fixtures (and this task's README provenance capture, 2026-09-28) show every
assistant record — even a usage-absent one — carrying a stable
`message["id"]` (e.g. `msg_fixture_t020_missing_a1`), which is this
project's OWN captured evidence of a message-level (not line-level, not
content-derived) identity a caller can dedup on. This module therefore
computes `row_hash` from `message["id"]` alone when present (matching the
sibling script's documented "cross-file idempotency" finding — the SAME
msg id, whichever file it is read from, hashes to the SAME row, so a
subagent+parent overlap or a second `ingest` run of the identical file
never double-counts), falling back to `(source_file, lineno, uuid)` only
for the (unobserved in this project's own captured schema) case of an
assistant record with no `message["id"]` at all. NEVER derived from
`message["content"]`, matching the credential-safety guarantee above.
Because the merge is a per-field maximum, a second `ingest` of the
identical input is still a true no-op (nothing grows, nothing is
rewritten).

OWNERSHIP OF A ROW (T048 restart round 2, V1-I2). A forked subagent
transcript can REPLAY a parent's message id (its record then carries an
`agentId`, the parent's own record does not). Measured on this host's 1,500
newest sessions: 4 of 392 subagent files share a msg id with their parent,
so the case is real but rare. The turn belongs to the parent. Two rules make
that independent of how the input path is spelled and of run order:
  1. Canonical read order (`find_jsonl_files()`): every path is resolved
     with os.path.realpath, and parent transcripts are read before any
     `.../subagents/*.jsonl` file, whatever the spelling (`sess.jsonl`,
     `/abs/sess.jsonl`, `./dir/`). Before this, a relative parent path
     sorted AFTER the absolute subagent paths, so the subagent's replay
     created the row and the parent's own turn was credited to the
     subagent and its item.
  2. Ownership in `upsert_row()`: when a stored row came from a record WITH
     an agentId and a record WITHOUT one arrives for the same msg id (the
     subagent was ingested in an earlier run, its parent only now), the
     row's identity columns are moved to the parent record
     (summary `reattributed_to_parent`). In every other case the identity
     columns of an existing row are never rewritten, except that a NULL
     item_id / session_id of a row is filled in from a later record of the
     SAME owner once its dispatch is known (summary `attribution_filled`).

CONCURRENT RUNS (T048 restart round 2, V1-I1). The row pass runs inside one
`BEGIN IMMEDIATE` transaction, so the read-merge-write of every row happens
under the database write lock. A second ingest on the same DB waits for the
first (up to FC_TELEMETRY_DB_LOCK_TIMEOUT_S seconds, default 600) and then
merges against the committed rows. Before this, two overlapping runs could
both read "no row", and the second INSERT failed with IntegrityError, which
aborted that run and lost every row it had read. If the lock cannot be taken
in time the run exits 1 with a message and writes nothing (an honest, whole
failure; rerun it), never a traceback after a partial write.

=============================================================================
"copy-on-ingest" (tasks.md T038 / plan.md T-A06 work item (3)) — design
judgment call, documented per task instruction
=============================================================================
tasks.md T038's literal text lists "copy-on-ingest" among this tool's scope
("... session->agent->item keying; copy-on-ingest; writes into the
existing WS1 R0 telemetry DB ..."); plan.md T-A06 work item (3) glosses it
as "copy-on-ingest so rotation no longer loses the before-sample." Read
LITERALLY as "byte-copy the raw source transcript file somewhere for
safekeeping," this would directly conflict with this file's own
credential-safety mandate above — a raw transcript copy contains the exact
`message["content"]` this module is required to never persist (the
`credential_leak/session.jsonl` fixture's planted marker lives in exactly
such a raw copy). No fixture in this task's RED set tests a raw-copy
artefact; the RED test's own credential-safety assertion (Part E) scans
ONLY the produced `--db` file. Per this module's own credential-safety
mandate above (§11.4.10 — never persist message content, whichever
reading of an ambiguous scope item risks doing so is the reading to
reject), this module implements "copy-on-ingest" as: the ingest DURABLY
PERSISTS the
extracted, credential-safe usage metrics into the SQLite DB at ingest time
— i.e. the "copy" IS the row landing in `transcript_usage_events`,
protecting the MEASURED data from the live (rotation-/compaction-prone)
transcript file's own future loss, without ever duplicating the transcript
file's raw (message-content-bearing) bytes anywhere. This is flagged as an
explicit design judgment call in this task's report, not a silent
narrowing of scope.

=============================================================================
CLI (assumed contract, per test_token_attribution_red.sh's own header note:
"If T038 lands with a different CLI, the ... probes below will fail loudly
... update this file then" — this module matches the assumed contract
verbatim)
=============================================================================
    python3 transcript_ingest.py ingest <transcript-or-dir> [--db PATH]
    python3 transcript_ingest.py report [--group-by item|agent|session|model] [--db PATH]

`<transcript-or-dir>` may be a single `.jsonl` transcript file OR a
directory (recursively walked for every `*.jsonl` file inside it,
including a nested `<parent>/subagents/agent-*.jsonl` convention) — the
"or-dir" half of the assumed CLI's own naming, needed because
session->agent->item attribution (property (d)) requires the PARENT
transcript's dispatch bookkeeping and the SUBAGENT's own transcript to be
read together; a single parent transcript file also auto-discovers a
sibling `<stem>/subagents/*.jsonl` directory beside it, so passing just the
parent file still attributes its subagents correctly when they are laid
out on disk per the real, documented convention (this task's README).

Exit codes: 0 on a successful run (including "found nothing to ingest"
under an existing, empty directory); 1 on a genuine usage/path error (the
given path does not exist at all, or an unreadable/nonexistent `--db`
directory). This module is NOT bound by contracts/common-conventions.md's
C-001 5-code table — `$FC/tokens/transcript_ingest.py` is explicitly listed
in that contract file's own "Plan tools that no contract in this directory
covers" note (T-A06 has no contract yet); this module instead matches the
simpler convention of the R0 prototype it extends (SystemExit(1)-shaped
errors, else 0), documented here as a deliberate, non-silent choice rather
than an omission.

Side-effects: writes only to the given `--db` SQLite file (created if
absent, matching `usage_telemetry.py`'s own `open_db`); never writes,
renames, or deletes the source transcript file(s) (read-only on
transcripts, matching plan.md T-A06's own "Rollback: ... the ingest is
read-only on transcripts").

Dependencies: Python stdlib only (argparse, hashlib, json, os, re,
subprocess, sqlite3, sys), matching every sibling `$FC` tool's own
convention.
=============================================================================
DEFERRALS LEDGER (T048 restart round 2, V1-M4 -- a deferral is honest only
when it is written down and tracked; the conductor registers OWED items)
=============================================================================
Round-1 deferrals, now CLOSED in round 2:
  - "file order" (fork-replay credit depended on ingest order and on how
    the path was spelled): CLOSED -- canonical_order() + the ownership rule
    in upsert_row(); guard: test_token_attribution_red.sh PART I2.
  - the other two round-1 deferrals live in dispatch_stamp.sh (jq-less
    first-"description" fail-open; silent WIT fallback): both CLOSED there.
OWED (open, tracked by the conductor):
  - OWED-TI-1: a dispatch conflict discovered in a LATER run does not clear
    an item_id an earlier run already stored for that agent's turns (the
    later run's NULL never overwrites a stored value; only a stored NULL is
    filled). A full fix needs a re-derivation pass over stored rows.
  - OWED-TI-2: FC_DISPATCH_ITEM_ID_RE is compiled by two regex engines (this
    module and bash ERE in dispatch_stamp.sh); see the DIALECT NOTE. The
    default and FC_DISPATCH_EXTRA_ITEM_PREFIXES paths are locale-pinned and
    guarded (PART I4); a caller-supplied full pattern is not.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sqlite3
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# DEFAULT_DB — the SAME file usage_telemetry.py's own DEFAULT_DB resolves to
# (docs/research/tokens/ws1_token_waste_baseline/POC/usage_telemetry.db),
# computed independently (never imports usage_telemetry.py — this module
# lives in a different directory, constitution/scripts/fastcycle/tokens/,
# four levels below the repo root) so both tools agree on the default
# without a cross-tree import.
#
# §11.4.28/§11.4.177 DECOUPLING (T038 independent review finding F3,
# 2026-09-28): the `parents[4]` computation below hardcodes an assumption
# specific to THIS project's tree shape (a `docs/research/tokens/...`
# sibling directory living exactly 4 levels above where this constitution
# script happens to be checked out). A standalone constitution checkout,
# or a consuming project with a different layout, would have this resolve
# to a nonexistent or nonsensical path. Fixed with the SAME `FC_*`-
# prefixed environment-variable override convention this codebase already
# uses elsewhere (see fc_common.py's `FC_DETERMINISM_TIMEOUT_S`):
# `FC_TELEMETRY_DB`, when set, takes precedence over the project-specific
# guess below entirely -- the guess remains ONLY as this project's own
# convenient zero-config default, never assumed correct for any other
# consumer of this constitution script.
_env_db = os.environ.get("FC_TELEMETRY_DB")
if _env_db:
    DEFAULT_DB = _env_db
else:
    DEFAULT_DB = str(
        Path(__file__).resolve().parents[4]
        / "docs" / "research" / "tokens" / "ws1_token_waste_baseline" / "POC"
        / "usage_telemetry.db"
    )

# Seconds a run waits for another ingest holding the write lock on the same
# DB (V1-I1). A whole-directory ingest of a large transcript tree can take
# minutes, so the default is generous; a value that cannot be parsed falls
# back to the default with a warning rather than crashing.
DEFAULT_LOCK_TIMEOUT_S = 600.0


def _lock_timeout_s():
    raw = os.environ.get("FC_TELEMETRY_DB_LOCK_TIMEOUT_S", "")
    if not raw:
        return DEFAULT_LOCK_TIMEOUT_S
    try:
        value = float(raw)
        if value < 0:
            raise ValueError("negative")
        return value
    except ValueError:
        print("transcript_ingest: WARNING: FC_TELEMETRY_DB_LOCK_TIMEOUT_S=%r is not a "
              "non-negative number; using %s" % (raw, DEFAULT_LOCK_TIMEOUT_S), file=sys.stderr)
        return DEFAULT_LOCK_TIMEOUT_S


SCHEMA = """
CREATE TABLE IF NOT EXISTS transcript_usage_events (
    row_hash TEXT PRIMARY KEY,
    source_file TEXT NOT NULL,
    lineno INTEGER NOT NULL,
    record_uuid TEXT,
    session_id TEXT,
    agent_id TEXT,
    item_id TEXT,
    ts TEXT,
    model TEXT,
    msg_id TEXT,
    usage_status TEXT NOT NULL,
    missing_instrument TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_input_tokens INTEGER,
    cache_creation_input_tokens INTEGER,
    total_tokens INTEGER
);
"""

# The 4 core usage sub-fields, in the real captured schema's own order
# (this task's README, 2026-09-28).
CORE_FIELDS = (
    "input_tokens", "output_tokens",
    "cache_creation_input_tokens", "cache_read_input_tokens",
)

# common-conventions.md's own project-wide term ("UNMEASURED — the
# first-class token for a value with no recording instrument, always with
# missing_instrument; never coerced to 0"), reused verbatim (§11.4.6 — the
# SAME literal token everywhere, not a near-synonym).
UNMEASURED = "UNMEASURED"
MEASURED = "measured"

# The same item=<prefix-nnnn>|? convention tokens/dispatch_stamp.sh (T036)
# already established on this SAME `description` field. Reused here for
# consistency, applied ONLY to `toolUseResult.description` (never to
# `message["content"]`).
#
# DECOUPLING FIX (§11.4.28/§11.4.177, independent review finding on this
# file, 2026-10-03): this REGEX used to hardcode the literal prefix
# "ATM-" verbatim, meaning any OTHER project consuming this
# project-agnostic constitution submodule whose item-id prefix is not
# "ATM" would get ZERO item/token attribution from this tool, silently
# (a project-literal leak inside a supposedly project-agnostic engine).
# dispatch_stamp.sh (T036) already solved this EXACT problem for its own
# identical hardcode via a configurable, non-guessed prefix resolution
# (its own header comment's "DECOUPLING" section) -- the SAME mechanism
# is reused here verbatim (never a second, divergent one, §11.4.227):
#   1. `FC_DISPATCH_ITEM_ID_RE` (env, highest priority) -- if set, this
#      value REPLACES the whole `item=` value alternation verbatim (e.g.
#      "ATM-[0-9]+|SPK-[0-9]+"), the consuming project's own explicit,
#      unvalidated choice (§11.4.6: an operator-supplied value is
#      trusted, never second-guessed).
#
#      DIALECT NOTE (T048 S9 independent review finding M1, 2026-10-03):
#      this SAME env var is ALSO consumed by `dispatch_stamp.sh` (T036)
#      via bash's `[[ VALUE =~ RE ]]`, which evaluates RE as a POSIX
#      Extended Regular Expression (ERE), whereas THIS module compiles it
#      as a Python `re` pattern (PCRE-like) -- the two dialects agree for
#      every simple `PREFIX-[0-9]+|PREFIX2-[0-9]+` value a caller is
#      expected to configure, but genuinely DIVERGE for a value using
#      POSIX-only syntax a caller might reasonably assume is portable
#      shell-regex, e.g. a POSIX bracket-expression class
#      (`[[:digit:]]`, valid ERE, NOT valid inside a Python character
#      class the same way) or POSIX-only backreference/interval quirks.
#      A value relying on such syntax will therefore match differently
#      -- or fail to compile here at all (now handled gracefully, never
#      a crash -- see `_build_item_tag_re()`'s own try/except below) --
#      between the two tools even though both read the identical env
#      var. No automatic POSIX-to-Python translation is implemented
#      (the common, documented subset below is sufficient for every
#      configuration this module's own tests exercise); a caller relying
#      on POSIX-only syntax should verify both tools independently
#      before depending on it.
#   2. Else, the DEFAULT prefix is DERIVED (never hardcoded) via
#      `_fc_default_item_prefix()` below -- the SAME release-prefix-based
#      derivation `dispatch_stamp.sh`'s own `_fc_default_item_prefix()`
#      uses, so for THIS checkout (release prefix "atmosphere") the
#      derived default is "ATM" -- SEMANTICALLY identical to the old
#      hardcoded behaviour for every existing caller that does not
#      configure an extra prefix (same set of ids matched/extracted), but
#      NOT byte-identical: the built regex wraps the derived prefix in a
#      non-capturing alternation group, `(?:ATM)-[0-9]+`, whereas the old
#      hardcode was the bare literal `ATM-[0-9]+` (T048 S9 independent
#      review finding M2, 2026-10-03 -- the prior wording here overstated
#      this). A DIFFERENT consuming project derives ITS OWN correct
#      prefix automatically, with no source edit to this file.
#   3. `FC_DISPATCH_EXTRA_ITEM_PREFIXES` (env, additive, comma/pipe/
#      space-separated) -- extra accepted prefixes ADDED to the derived
#      default from (2) -- never a source edit, and never silently
#      widening the DEFAULT (which stays exactly the derived prefix, e.g.
#      "ATM", for an unconfigured checkout).
#
# HERMETICITY NOTE (mirrors dispatch_stamp.sh's own identical note): this
# reads `constitution/scripts/release_prefix.sh` once per process (via a
# `bash` subprocess) UNLESS `FC_DISPATCH_ITEM_ID_RE` is set -- a
# deliberate, narrow widening of this module's own "stdlib only, no
# ambient state" convention, exactly as `dispatch_stamp.sh` already
# discloses for its identical dependency; it resolves identically on
# every invocation of a given checkout.


def _fc_derive_key_prefix(seed):
    """Mirror `dispatch_stamp.sh`'s `_fc_derive_key_prefix()`: the first 3
    ASCII letters of `seed`, uppercased; padded with 'X' if fewer than 3;
    the neutral "WIT" fallback if `seed` has no ASCII letters at all.
    Kept as a literal, independent re-derivation -- matching the
    established sibling convention that each of these small `$FC` tools
    is a single self-contained file, not a shared-lib import."""
    letters = "".join(c for c in seed if c.isascii() and c.isalpha())[:3].upper()
    if not letters:
        return "WIT"
    return letters.ljust(3, "X")


def _fc_default_item_prefix():
    """Resolve the SAME base release prefix `scripts/release_prefix.sh` /
    `dispatch_stamp.sh`'s own `_fc_default_item_prefix()` already use
    (HELIX_RELEASE_PREFIX env -> its .env entry -> snake_case(project
    root dir name)), then derive the 3-letter ticket key from it. Falls
    back to the neutral "WIT" prefix (via `_fc_derive_key_prefix()`'s own
    no-letters branch -- never a second, divergent fallback mechanism)
    ONLY if `release_prefix.sh` is genuinely unreachable or errors
    (should not happen inside a checked-out constitution submodule --
    kept as a defensive non-crash default, never a silent guess about a
    DIFFERENT project's real prefix). NOTE this is a DIFFERENT "WIT"
    path than the legitimate, by-design one: a resolved base string with
    no ASCII letters at all (e.g. HELIX_RELEASE_PREFIX set to a
    digits-only value) also derives "WIT" via `_fc_derive_key_prefix()`,
    with NO warning -- that is a genuine, successfully-resolved value
    that simply has no letters to take, not an error.

    M1 remediation (T048 S9 independent review, 2026-10-03): the
    genuinely-erroring paths below (script missing / unreadable / times
    out / cannot be spawned / exits non-zero) previously fell back to
    "WIT" with NO diagnostic whatsoever -- attribution loss from a real
    failure was silent and undebuggable. Fixed: each erroring path now
    prints a named stderr warning before falling back, so the loss is
    at least visible (§11.4.6 -- never a silent guess).

    N2 remediation (T048 S9 SECOND independent review, 2026-10-03): the
    non-zero-exit warning below used to say "falling back to ... 'WIT'"
    UNCONDITIONALLY -- but a non-zero exit from `release_prefix.sh` does
    NOT always mean 'WIT': `base` is taken from `proc.stdout` regardless
    of `proc.returncode` (the script's own stdout contract is honoured
    even on a non-zero exit, exactly like the healthy returncode==0
    path), so a script that exits non-zero while STILL printing a
    usable value to stdout (e.g. exits 3 after printing "atmosphere")
    derives its prefix from THAT stdout ("ATM" here), never "WIT" --
    the prior wording was wrong in that case. Fixed: the message now
    checks whether `base` actually has any ASCII letters to derive a
    prefix from (the SAME real condition `_fc_derive_key_prefix()`'s own
    no-letters branch checks, never a second, divergent predicate) and
    reports accurately which of the two genuinely different outcomes
    this run hit."""
    self_dir = os.path.dirname(os.path.abspath(__file__))
    rp_script = os.path.normpath(os.path.join(self_dir, "..", "..", "release_prefix.sh"))
    base = ""
    if os.path.isfile(rp_script):
        try:
            # LC_ALL=C: the same locale dispatch_stamp.sh pins for itself,
            # so both tools derive the prefix from identical bytes (V1-M2).
            proc = subprocess.run(
                ["bash", rp_script],
                capture_output=True, text=True, timeout=10, check=False,
                env=dict(os.environ, LC_ALL="C"),
            )
            base = proc.stdout.strip()
            if proc.returncode != 0:
                base_has_letters = any(c.isascii() and c.isalpha() for c in base)
                if base_has_letters:
                    print(
                        "transcript_ingest: WARNING: %s exited %d (stderr=%r) -- "
                        "it still printed usable output to stdout, so the "
                        "item-tag prefix is derived from that captured output "
                        "(NOT a 'WIT' fallback)" % (rp_script, proc.returncode, proc.stderr.strip()),
                        file=sys.stderr,
                    )
                else:
                    print(
                        "transcript_ingest: WARNING: %s exited %d (stderr=%r) -- "
                        "its stdout had no usable letters either, falling back "
                        "to the neutral 'WIT' item-tag prefix for this run"
                        % (rp_script, proc.returncode, proc.stderr.strip()),
                        file=sys.stderr,
                    )
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            print(
                "transcript_ingest: WARNING: could not run %s (%s: %s) -- "
                "falling back to the neutral 'WIT' item-tag prefix for "
                "this run" % (rp_script, type(exc).__name__, exc),
                file=sys.stderr,
            )
            base = ""
    else:
        print(
            "transcript_ingest: WARNING: %s not found -- falling back to "
            "the neutral 'WIT' item-tag prefix for this run" % rp_script,
            file=sys.stderr,
        )
    return _fc_derive_key_prefix(base)


def _ascii_upper(text):
    """Upper-case the ASCII letters a-z only; every other character is kept
    as it is (the behaviour of `tr '[:lower:]' '[:upper:]'` under LC_ALL=C,
    which dispatch_stamp.sh uses)."""
    return "".join(chr(ord(c) - 32) if "a" <= c <= "z" else c for c in text)


def _build_item_tag_re():
    """Build the `item=<prefix>-<digits>|?` regex per the 3-tier priority
    documented above. Split out as its own function (never inlined at
    import time without a name) so a test can call it directly after
    monkeypatching `os.environ`, without needing a subprocess per
    invocation of this whole file.

    NOTE (`tok.upper()`, T048 S9 review finding M1): Python's `str.upper()`
    is Unicode-aware (e.g. it uppercases non-ASCII letters per Unicode
    casing rules), whereas bash's `tr '[:lower:]' '[:upper:]'` (used by
    `dispatch_stamp.sh`'s own sibling derivation, and by
    `release_prefix.sh`'s `_hrp_snake_case`) is byte-oriented and
    LOCALE-dependent for anything outside the POSIX "C" locale's plain
    ASCII a-z range. For the plain-ASCII prefixes this module's own tests
    configure (and that `release_prefix.sh`/`dispatch_stamp.sh` are
    documented to derive), both behave identically; a caller configuring
    a non-ASCII `FC_DISPATCH_EXTRA_ITEM_PREFIXES` token could observe the
    two tools disagree depending on the invoking shell's locale. Not
    fixed here (no such token is used, documented, or tested anywhere in
    this project) -- recorded as an honest, narrow limitation per §11.4.6
    rather than silently assumed safe.

    FAIL-SAFE (T048 S9 review finding M1): an invalid `FC_DISPATCH_ITEM_ID_RE`
    -- or, in principle, an `FC_DISPATCH_EXTRA_ITEM_PREFIXES` token
    containing regex metacharacters -- used to raise an unhandled
    `re.error` at `re.compile()` time, crashing THIS WHOLE MODULE (and
    every importer, e.g. `context/dispatch_prefix.py`) at import, whereas
    bash's `[[ VALUE =~ RE ]]` would simply fail to MATCH on the SAME
    misconfigured value, never crash the shell. Fixed: the compile is
    wrapped; a genuinely-invalid value is reported to stderr by name
    (never silently swallowed) and the build retries once using ONLY the
    safely-derived default prefix, so a misconfiguration costs this run's
    item attribution (visibly) rather than the whole ingest run."""
    override = os.environ.get("FC_DISPATCH_ITEM_ID_RE", "")
    if override:
        value_re = override
    else:
        prefixes = [_fc_default_item_prefix()]
        extra = os.environ.get("FC_DISPATCH_EXTRA_ITEM_PREFIXES", "")
        if extra:
            # Split on exactly the separators dispatch_stamp.sh uses (',' and
            # '|' turned into spaces, then bash word splitting on space, tab
            # and newline) and upper-case ASCII letters only, as `tr` does
            # under LC_ALL=C (V1-M2): str.upper() would turn 'ß' into 'SS'.
            for tok in re.split(r"[,| \t\n]+", extra):
                if tok:
                    prefixes.append(_ascii_upper(tok))
        value_re = "(?:%s)-[0-9]+" % "|".join(prefixes)
    try:
        return re.compile(ITEM_TAG_TEMPLATE % value_re, re.ASCII)
    except re.error as exc:
        print(
            "transcript_ingest: WARNING: the configured item-tag pattern "
            "(FC_DISPATCH_ITEM_ID_RE=%r FC_DISPATCH_EXTRA_ITEM_PREFIXES=%r) "
            "is not a valid regex (%s) -- falling back to the derived "
            "default prefix only for this run; item attribution via the "
            "misconfigured value is LOST until the env var is fixed"
            % (override, os.environ.get("FC_DISPATCH_EXTRA_ITEM_PREFIXES", ""), exc),
            file=sys.stderr,
        )
        fallback_prefix = _fc_default_item_prefix()
        return re.compile(ITEM_TAG_TEMPLATE % ("(?:%s)-[0-9]+" % fallback_prefix), re.ASCII)


# The item tag is a whole token. Left: start of string or one ASCII
# whitespace character (space, tab, newline, CR, FF, VT) -- `xitem=ATM-1`
# is not a tag. Right: end of string or anything but an ASCII letter, digit
# or underscore -- `item=ATM-12x`, `item=ATM-12_x` and `item=?foo` are not
# tags, while `item=ATM-12,` and `item=ATM-12)` are. T048 restart review R3
# boundary note.
#
# SAME TAG SET AS dispatch_stamp.sh, IN ANY CALLER LOCALE (V1-M2, T048
# restart round 2): both classes are spelled out in ASCII and the pattern
# is compiled with re.ASCII. dispatch_stamp.sh pins LC_ALL=C, where bash's
# [[:space:]] is exactly that ASCII set and [[:alnum:]] is ASCII. Before
# this, Python's `\s` also matched U+00A0, U+001C-U+001F, U+0085, U+2003
# and U+3000, while bash's result changed with the caller's locale. The
# guard is test_token_attribution_red.sh PART I4 (15 non-ASCII and boundary
# cases, both tools, LC_ALL=C and LC_ALL=C.UTF-8). Not covered: a caller-
# supplied FC_DISPATCH_ITEM_ID_RE is compiled by two different regex
# engines (see the DIALECT NOTE above).
ITEM_TAG_TEMPLATE = r"(?:^|[ \t\n\r\f\v])item=(%s|\?)(?![A-Za-z0-9_])"


ITEM_TAG_RE = _build_item_tag_re()


def open_db(path):
    # isolation_level=None: transactions are opened explicitly (BEGIN
    # IMMEDIATE in cmd_ingest), never implicitly by the sqlite3 module.
    conn = sqlite3.connect(path, timeout=_lock_timeout_s(), isolation_level=None)
    conn.execute(SCHEMA)
    return conn


def _is_subagent_transcript(path):
    """True for a file inside a `subagents/` directory (the documented
    "<parent_session_id>/subagents/agent-<agentId>.jsonl" convention)."""
    return os.path.basename(os.path.dirname(path)) == "subagents"


def canonical_order(paths):
    """Resolve every path with os.path.realpath, drop duplicates, and order
    them parent transcripts first, then subagent transcripts, each group by
    resolved path. The order no longer depends on how the caller spelled the
    path (V1-I2): a parent is always read before a subagent that may replay
    its turns."""
    is_sub = {}
    for p in paths:
        real = os.path.realpath(p)
        # A symlinked transcript counts as a subagent transcript when either
        # the path as given or its target sits in a `subagents/` directory.
        is_sub[real] = (is_sub.get(real, False) or _is_subagent_transcript(real)
                        or _is_subagent_transcript(os.path.abspath(p)))
    return sorted(is_sub, key=lambda p: (is_sub[p], p))


def find_jsonl_files(path):
    """Given a file or directory, return the .jsonl files to read, as
    resolved paths in canonical_order(). A single parent-transcript file
    also auto-discovers a sibling "<stem>/subagents/*.jsonl" directory
    beside it (the real, documented on-disk convention:
    "<parent_session_id>.jsonl" alongside
    "<parent_session_id>/subagents/agent-<agentId>.jsonl"), so the common
    "just point me at the top-level transcript" case still attributes its
    subagents without requiring the caller to pass the parent directory
    explicitly."""
    if os.path.isdir(path):
        out = []
        for root, _dirs, names in os.walk(path):
            for name in names:
                if name.endswith(".jsonl"):
                    out.append(os.path.join(root, name))
        return canonical_order(out)
    if os.path.isfile(path):
        out = [path]
        stem_dir = os.path.join(
            os.path.dirname(os.path.abspath(path)),
            os.path.splitext(os.path.basename(path))[0],
        )
        subagents_dir = os.path.join(stem_dir, "subagents")
        if os.path.isdir(subagents_dir):
            for name in os.listdir(subagents_dir):
                if name.endswith(".jsonl"):
                    out.append(os.path.join(subagents_dir, name))
        return canonical_order(out)
    return []


# Per-pass counters of input that was not read cleanly. cmd_ingest() resets
# them before its row pass and prints them in its summary line, so a run that
# skipped a file or a line says so in its own result (T048 restart round-1,
# class "absent evidence read as valid": these used to appear only as
# scattered stderr warnings while the summary looked complete).
READ_STATS = {"unreadable_files": 0, "unparseable_lines": 0, "invalid_utf8_lines": 0,
              "malformed_fields": 0}


def iter_records(filepath):
    """Yield (lineno, record_dict) for every parseable, non-blank JSONL
    line in filepath. A malformed line is logged to stderr and skipped —
    never crashes the whole ingest over one bad line (real transcripts can
    carry a truncated tail line from an interrupted write).

    The file is read as BYTES and each line is decoded on its own (T048
    restart review R3-F2): a strict whole-file text decode raised
    UnicodeDecodeError on a tail line cut inside a multi-byte character,
    which aborted the run before the final commit and lost every valid row.
    A line that is not valid UTF-8 is decoded with replacement characters
    and reported on stderr; it is then parsed like any other line (a line
    cut mid-character also fails JSON parsing and is skipped)."""
    try:
        fh = open(filepath, "rb")
    except OSError as exc:
        print("transcript_ingest: WARNING: cannot open %s: %s" % (filepath, exc), file=sys.stderr)
        READ_STATS["unreadable_files"] += 1
        return
    with fh:
        for lineno, raw_bytes in enumerate(fh, start=1):
            try:
                raw = raw_bytes.decode("utf-8")
            except UnicodeDecodeError as exc:
                print(
                    "transcript_ingest: WARNING: %s:%d: invalid UTF-8 (%s); decoded "
                    "with replacement characters" % (filepath, lineno, exc),
                    file=sys.stderr,
                )
                READ_STATS["invalid_utf8_lines"] += 1
                raw = raw_bytes.decode("utf-8", errors="replace")
            line = raw.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                print(
                    "transcript_ingest: WARNING: %s:%d: skipping unparseable line: %s"
                    % (filepath, lineno, exc), file=sys.stderr,
                )
                READ_STATS["unparseable_lines"] += 1
                continue
            if not isinstance(rec, dict):
                continue
            yield lineno, rec


def build_dispatch_map(files):
    """Pass 1 — scan every file for a `toolUseResult` object (present on
    the tool-RESULT "user" record following an Agent/Task dispatch's
    tool_use block; a SIBLING top-level key to `message`, never read from
    inside it). Returns {agent_id: {"item_id": <the configured item-id
    prefix>-<digits>, or None>, "session_id": <the dispatching record's own
    sessionId, or None>}} — the prefix is "ATM" for THIS checkout's
    unconfigured default (derived from `release_prefix.sh`, never
    hardcoded; see ITEM_TAG_RE above), and may differ for a different
    consuming project or under FC_DISPATCH_EXTRA_ITEM_PREFIXES /
    FC_DISPATCH_ITEM_ID_RE.

    Reads ONLY `toolUseResult["agentId"]` and, from `toolUseResult
    ["description"]`, the narrow regex-matched item=<prefix>-<digits>|?
    token —
    the raw description string itself is NEVER stored.

    An agent id can be dispatched more than once (a resumed agent). If all
    its tagged dispatches name the SAME item, that item is kept. If they
    name DIFFERENT items, its turns cannot be split between them from this
    data, so the item is set to None and both ids are reported on stderr
    (T048 restart review R4-I4: neither first-seen nor last-seen is a
    correct answer, and keeping either one silently misattributes tokens).
    The same rule applies to a conflicting session id."""
    dispatch_map = {}
    seen_items = {}
    seen_sessions = {}
    for filepath in files:
        for _lineno, rec in iter_records(filepath):
            tur = rec.get("toolUseResult")
            if not isinstance(tur, dict):
                continue
            agent_id = tur.get("agentId")
            if not agent_id or not isinstance(agent_id, str):
                continue
            item_id = None
            desc = tur.get("description")
            if isinstance(desc, str):
                m = ITEM_TAG_RE.search(desc)
                if m and m.group(1) != "?":
                    item_id = m.group(1)
            session_id = rec.get("sessionId")
            dispatch_map.setdefault(agent_id, {"item_id": None, "session_id": None})
            if item_id:
                seen_items.setdefault(agent_id, []).append(item_id)
            if isinstance(session_id, str) and session_id:
                seen_sessions.setdefault(agent_id, []).append(session_id)
    for agent_id, entry in dispatch_map.items():
        for key, seen in (("item_id", seen_items), ("session_id", seen_sessions)):
            values = sorted(set(seen.get(agent_id, [])))
            if len(values) == 1:
                entry[key] = values[0]
            elif len(values) > 1:
                print(
                    "transcript_ingest: WARNING: agent %s was dispatched under %d "
                    "different %s values (%s); its turns are left unattributed "
                    "(%s=NULL) rather than credited to one of them"
                    % (agent_id, len(values), key, ", ".join(values), key),
                    file=sys.stderr,
                )
    return dispatch_map


def _int_or_none(value):
    """A token counter is a JSON integer. Anything else (a string, a bool, a
    float, a list) is treated as ABSENT, so the turn is UNMEASURED with the
    field named in missing_instrument, never coerced (T048 restart round 2,
    class "abort loses the whole run": a list here used to reach the SQL
    binding; `True` used to count as 1)."""
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _text(value):
    """An identity field (msg id, uuid, timestamp, model, session id) is a
    JSON string. Anything else is stored as NULL and counted in the run's
    summary (malformed_fields) instead of reaching the SQL binding, where a
    list or object raised and aborted the whole run (T048 restart round 2,
    same class as R3-F2 and V1-I1)."""
    if value is None or isinstance(value, str):
        return value
    READ_STATS["malformed_fields"] += 1
    return None


def classify_usage(it, ot, crt, cct, ref, filepath, usage_block_present=True):
    """Return (usage_status, missing_instrument, total_tokens) for the four
    core counters. A turn is `measured` ONLY when all four counters are
    present; otherwise it is UNMEASURED, total_tokens is None, and
    missing_instrument names exactly which fields were absent (T048 restart
    review R3-F5: a usage block present but lacking token fields used to be
    labelled `measured` with a NULL total and no missing_instrument, which
    downstream readers such as context/dispatch_prefix.py treat as an
    impossible state). Counters that ARE present are still stored."""
    values = dict(zip(CORE_FIELDS, (it, ot, cct, crt)))
    absent = [name for name in CORE_FIELDS if values[name] is None]
    if not absent:
        return MEASURED, None, it + ot + crt + cct
    if not usage_block_present:
        what = 'no "usage" block present'
    else:
        what = "usage block lacks %s" % ", ".join("message.usage.%s" % n for n in absent)
    return (UNMEASURED,
            "message.usage (assistant record %s in %s: %s)" % (ref, filepath, what),
            None)


def merge_usage(stored, incoming):
    """Merge two observations of the same msg id. Each core counter takes
    the larger of the two known values (cumulative counters only grow while
    a turn streams, see the module docstring). Returns (merged_counts,
    decreased_fields): decreased_fields lists the counters where `incoming`
    is SMALLER than `stored`, which streaming growth cannot produce."""
    merged = {}
    decreased = []
    for name in CORE_FIELDS:
        a, b = stored.get(name), incoming.get(name)
        if a is None:
            merged[name] = b
        elif b is None:
            merged[name] = a
        else:
            merged[name] = max(a, b)
            if b < a:
                decreased.append(name)
    return merged, decreased


def build_row(filepath, lineno, rec, dispatch_map):
    """Build one transcript_usage_events row for an assistant-turn record.
    Returns None if this record is not a usage-bearing assistant turn.

    CREDENTIAL SAFETY: `rec["message"]` is read only via
    .get("model")/.get("id")/.get("usage") — `.get("content")` is NEVER
    called on it anywhere in this function or its callers."""
    if rec.get("type") != "assistant":
        return None
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return None

    model = _text(msg.get("model"))
    msg_id = _text(msg.get("id"))
    usage = msg.get("usage")

    record_uuid = _text(rec.get("uuid"))
    ts = _text(rec.get("timestamp"))
    top_agent_id = rec.get("agentId")  # present only on a SUBAGENT's own records

    if isinstance(top_agent_id, str) and top_agent_id:
        agent_id = top_agent_id
        attribution = dispatch_map.get(agent_id, {"item_id": None, "session_id": None})
        item_id = attribution["item_id"]
        # A subagent record does not carry its own sessionId in the real
        # captured schema (this task's README); prefer it if a future
        # transcript shape ever does carry one, else fall back to the
        # parent's sessionId resolved via the dispatch map.
        session_id = _text(rec.get("sessionId")) or attribution["session_id"]
    else:
        agent_id = None
        item_id = None  # this tool does not (yet) item-attribute a parent
        # session's own top-level turns — only a DISPATCHED subagent's
        # usage is attributed to an item (plan T-A06 / RED test property
        # (d): "a subagent transcript -> attributed to its parent item").
        session_id = _text(rec.get("sessionId"))

    ref = msg_id or record_uuid or ("line %d" % lineno)
    if isinstance(usage, dict):
        it = _int_or_none(usage.get("input_tokens"))
        ot = _int_or_none(usage.get("output_tokens"))
        crt = _int_or_none(usage.get("cache_read_input_tokens"))
        cct = _int_or_none(usage.get("cache_creation_input_tokens"))
    else:
        it = ot = crt = cct = None
    usage_status, missing_instrument, total = classify_usage(
        it, ot, crt, cct, ref, filepath, usage_block_present=isinstance(usage, dict))

    if msg_id:
        row_hash = hashlib.sha256(("msgid:" + str(msg_id)).encode("utf-8")).hexdigest()
    else:
        identity = "%s:%d:%s" % (os.path.abspath(filepath), lineno, record_uuid or "")
        row_hash = hashlib.sha256(identity.encode("utf-8")).hexdigest()

    return {
        "row_hash": row_hash,
        "source_file": filepath,
        "lineno": lineno,
        "record_uuid": record_uuid,
        "session_id": session_id,
        "agent_id": agent_id,
        "item_id": item_id,
        "ts": ts,
        "model": model,
        "msg_id": msg_id,
        "usage_status": usage_status,
        "missing_instrument": missing_instrument,
        "input_tokens": it,
        "output_tokens": ot,
        "cache_read_input_tokens": crt,
        "cache_creation_input_tokens": cct,
        "total_tokens": total,
    }


INSERT_SQL = """
INSERT INTO transcript_usage_events
    (row_hash, source_file, lineno, record_uuid, session_id, agent_id,
     item_id, ts, model, msg_id, usage_status, missing_instrument,
     input_tokens, output_tokens, cache_read_input_tokens,
     cache_creation_input_tokens, total_tokens)
VALUES
    (:row_hash, :source_file, :lineno, :record_uuid, :session_id, :agent_id,
     :item_id, :ts, :model, :msg_id, :usage_status, :missing_instrument,
     :input_tokens, :output_tokens, :cache_read_input_tokens,
     :cache_creation_input_tokens, :total_tokens);
"""

# The columns that say WHERE a row came from and WHO it is attributed to.
_IDENTITY_COLS = ("source_file", "lineno", "record_uuid", "session_id",
                  "agent_id", "item_id", "ts")

UPDATE_ROW_SQL = """
UPDATE transcript_usage_events SET
    source_file = :source_file, lineno = :lineno, record_uuid = :record_uuid,
    session_id = :session_id, agent_id = :agent_id, item_id = :item_id,
    ts = :ts,
    usage_status = :usage_status, missing_instrument = :missing_instrument,
    input_tokens = :input_tokens, output_tokens = :output_tokens,
    cache_read_input_tokens = :cache_read_input_tokens,
    cache_creation_input_tokens = :cache_creation_input_tokens,
    total_tokens = :total_tokens
WHERE row_hash = :row_hash;
"""

_STORED_COLS = _IDENTITY_COLS + ("msg_id", "usage_status") + CORE_FIELDS


def upsert_row(conn, row):
    """Insert `row`, or merge it into the row already stored under the same
    row_hash (per-field maximum, see merge_usage()). Must run inside the
    caller's write transaction (cmd_ingest's BEGIN IMMEDIATE), so the read
    below and the write after it cannot interleave with another ingest.

    Returns (outcome, reattribution, final_status): outcome is "new",
    "updated" (an existing row's counters grew) or "unchanged";
    reattribution is None, "to_parent" or "filled" (see the module
    docstring, OWNERSHIP OF A ROW); final_status is the row's usage_status
    after this call.

    The identity columns of an existing row are rewritten in exactly one
    case: the stored row came from a record WITH an agentId (a subagent's)
    and `row` comes from a record WITHOUT one (the parent's own turn). A
    NULL item_id / session_id is filled from a later record of the SAME
    owner. A counter that DECREASES relative to the stored row is reported
    on stderr; the maximum is still kept."""
    existing = conn.execute(
        "SELECT %s FROM transcript_usage_events WHERE row_hash = ?" % ", ".join(_STORED_COLS),
        (row["row_hash"],),
    ).fetchone()
    if existing is None:
        conn.execute(INSERT_SQL, row)
        return "new", None, row["usage_status"]
    stored = dict(zip(_STORED_COLS, existing))
    merged, decreased = merge_usage(stored, row)
    if decreased:
        print(
            "transcript_ingest: WARNING: msg_id %s at %s:%d has SMALLER %s than the "
            "row already stored from %s:%s (streaming only grows these counters; "
            "the larger values are kept): stored=%s new=%s"
            % (row["msg_id"], row["source_file"], row["lineno"], ", ".join(decreased),
               stored["source_file"], stored["lineno"],
               {n: stored[n] for n in decreased}, {n: row[n] for n in decreased}),
            file=sys.stderr,
        )
    identity = {c: stored[c] for c in _IDENTITY_COLS}
    reattribution = None
    if stored["agent_id"] is not None and row["agent_id"] is None:
        identity = {c: row[c] for c in _IDENTITY_COLS}
        reattribution = "to_parent"
    elif stored["agent_id"] == row["agent_id"]:
        for col in ("item_id", "session_id"):
            if identity[col] is None and row[col] is not None:
                identity[col] = row[col]
                reattribution = "filled"
    grew = any(merged[n] != stored[n] for n in CORE_FIELDS)
    if not grew and reattribution is None:
        return "unchanged", None, stored["usage_status"]
    ref = stored["msg_id"] or identity["record_uuid"] or ("line %s" % identity["lineno"])
    status, missing, total = classify_usage(
        merged["input_tokens"], merged["output_tokens"],
        merged["cache_read_input_tokens"], merged["cache_creation_input_tokens"],
        ref, identity["source_file"],
        usage_block_present=any(merged[n] is not None for n in CORE_FIELDS))
    params = dict(merged)
    params.update(identity)
    params.update(row_hash=row["row_hash"], usage_status=status,
                  missing_instrument=missing, total_tokens=total)
    conn.execute(UPDATE_ROW_SQL, params)
    return ("updated" if grew else "unchanged"), reattribution, status


def cmd_ingest(args):
    if not os.path.exists(args.path):
        print("transcript_ingest: path does not exist: %s" % args.path, file=sys.stderr)
        return 1
    files = find_jsonl_files(args.path)
    if not files:
        print("transcript_ingest: no .jsonl files found under %s" % args.path)
        return 0

    try:
        conn = open_db(args.db)
    except sqlite3.Error as exc:
        print("transcript_ingest: cannot open --db %s: %s" % (args.db, exc), file=sys.stderr)
        return 1

    dispatch_map = build_dispatch_map(files)

    for key in READ_STATS:
        READ_STATS[key] = 0
    counts = dict.fromkeys(("turns", "new", "updated", "unchanged", "to_parent", "filled"), 0)
    final_status = {}
    # V1-I1: the whole row pass is one write transaction taken BEFORE the
    # first read, so a concurrent ingest on the same DB waits here instead
    # of reading a row this run is about to insert.
    try:
        conn.execute("BEGIN IMMEDIATE")
    except sqlite3.OperationalError as exc:
        print("transcript_ingest: could not take the write lock on --db %s within %ss "
              "(another ingest is probably running): %s -- nothing was written; rerun "
              "it, or raise FC_TELEMETRY_DB_LOCK_TIMEOUT_S" % (args.db, _lock_timeout_s(), exc),
              file=sys.stderr)
        return 1
    try:
        for filepath in files:
            for lineno, rec in iter_records(filepath):
                row = build_row(filepath, lineno, rec, dispatch_map)
                if row is None:
                    continue
                counts["turns"] += 1
                outcome, reattribution, status = upsert_row(conn, row)
                counts[outcome] += 1
                if reattribution:
                    counts[reattribution] += 1
                final_status[row["row_hash"]] = status
        conn.execute("COMMIT")
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    # measured / unmeasured count the DISTINCT rows this run read, by their
    # state after the run (V1-M1): a row inserted unmeasured and completed by
    # a later line counts once, as measured, exactly as the DB holds it.
    n_measured = sum(1 for st in final_status.values() if st == MEASURED)
    print(
        "transcript_ingest: files=%d assistant_turns_read=%d rows=%d new=%d "
        "measured=%d unmeasured=%d duplicate_merged_grew=%d "
        "duplicate_unchanged=%d reattributed_to_parent=%d attribution_filled=%d "
        "unreadable_files=%d unparseable_lines=%d invalid_utf8_lines=%d "
        "malformed_fields=%d db=%s"
        % (len(files), counts["turns"], len(final_status), counts["new"], n_measured,
           len(final_status) - n_measured, counts["updated"], counts["unchanged"],
           counts["to_parent"], counts["filled"], READ_STATS["unreadable_files"],
           READ_STATS["unparseable_lines"], READ_STATS["invalid_utf8_lines"],
           READ_STATS["malformed_fields"], args.db)
    )
    return 0


GROUP_COLS = {"item": "item_id", "agent": "agent_id", "session": "session_id", "model": "model"}


def cmd_report(args):
    """Optional convenience command (not required by the RED test; added
    for parity with usage_telemetry.py's own `report` subcommand and to
    make manual verification of ingested counts straightforward without
    hand-written SQL each time)."""
    try:
        conn = open_db(args.db)
    except sqlite3.Error as exc:
        print("transcript_ingest: cannot open --db %s: %s" % (args.db, exc), file=sys.stderr)
        return 1
    group_col = GROUP_COLS[args.group_by]
    rows = conn.execute(
        "SELECT %s AS grp, usage_status, input_tokens, output_tokens, "
        "cache_read_input_tokens, cache_creation_input_tokens, total_tokens "
        "FROM transcript_usage_events ORDER BY %s" % (group_col, group_col)
    ).fetchall()
    if not rows:
        print("transcript_ingest: report: no transcript_usage_events rows ingested yet")
        return 0
    groups = {}
    for grp, status, it, ot, crt, cct, total in rows:
        groups.setdefault(grp, []).append(
            dict(status=status, input=it, output=ot, cache_read=crt,
                 cache_creation=cct, total=total)
        )
    print("# transcript_ingest usage report — grouped by %s" % args.group_by)
    print("# db=%s  rows=%d  groups=%d" % (args.db, len(rows), len(groups)))
    print()
    for grp, recs in sorted(groups.items(), key=lambda kv: (kv[0] is None, kv[0])):
        measured = [r for r in recs if r["status"] == MEASURED]
        unmeasured_n = len(recs) - len(measured)
        label = grp if grp is not None else "(unattributed)"
        print("## %s=%s  (n=%d, measured=%d, unmeasured=%d)" % (args.group_by, label, len(recs), len(measured), unmeasured_n))
        for field, key in (
            ("input_tokens", "input"), ("output_tokens", "output"),
            ("cache_read_input_tokens", "cache_read"),
            ("cache_creation_input_tokens", "cache_creation"),
            ("total_tokens", "total"),
        ):
            vals = [r[key] for r in measured if r[key] is not None]
            s = sum(vals) if vals else 0
            print("  %s: sum=%d (n_measured_and_present=%d)" % (field, s, len(vals)))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_ingest = sub.add_parser("ingest")
    p_ingest.add_argument("path", help="transcript file OR a directory to walk recursively")
    p_ingest.add_argument("--db", default=DEFAULT_DB)
    p_ingest.set_defaults(func=cmd_ingest)

    p_report = sub.add_parser("report")
    p_report.add_argument("--group-by", choices=sorted(GROUP_COLS), default="item")
    p_report.add_argument("--db", default=DEFAULT_DB)
    p_report.set_defaults(func=cmd_report)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
