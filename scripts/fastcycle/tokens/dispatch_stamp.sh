#!/usr/bin/env bash
{ set +o xtrace +o verbose; } 2>/dev/null
# THE ENVIRONMENT (T048 restart round 11, RV11-2 / RV11-5; full text in the
# header section "THE ENVIRONMENT" below). Before anything is read, the tool
# re-executes itself ONCE with an EMPTY environment plus a fixed allowlist, so
# nothing else the caller exports (POSIXLY_CORRECT, AWKPATH, GAWK_*, SHELLOPTS,
# BASHOPTS, exported shell functions, JQ_*, LC_*, GIT_*, ...) reaches this
# script, awk, jq or release_prefix.sh. The allowlist is everything the tool
# reads. A failed re-execution refuses (GUARD) / prints nothing (EXTRACTION).
unset -f unset builtin exec shopt command 2>/dev/null
if [[ "${1-}" != "--fc-clean-env" ]]; then
  shopt -s execfail
  _fc_keep=()
  for _fc_v in PATH HOME FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_RELEASE_PREFIX HELIX_PROJECT_ROOT; do
    [[ -n "${!_fc_v+set}" ]] && _fc_keep+=("$_fc_v=${!_fc_v}")
  done
  # Checked first so a failure is reported by this tool, not by bash's own
  # "No such file" line (EXTRACTION mode must stay silent).
  [[ -x "$BASH" && -r "$0" ]] && exec -c "$BASH" "$0" --fc-clean-env "${#_fc_keep[@]}" "${_fc_keep[@]}" "$@"
  # Only reached when the re-execution failed.
  if [[ "${1-}" == "--extract-item-id" ]]; then exit 0; fi
  echo "guardrails: BLOCKED — T036 dispatch-stamp: the hook could not re-execute itself in a clean environment ($BASH $0), so the payload is not read" >&2
  exit 2 # FAIL CLOSED: no clean re-execution (test_dispatch_stamp.sh section P)
fi
shift
_fc_n="$1"; shift
while [[ "$_fc_n" -gt 0 ]]; do export "$1"; shift; _fc_n=$((_fc_n - 1)); done
unset _fc_n
# constitution/scripts/fastcycle/tokens/dispatch_stamp.sh
#
# T036 (SpecKit-004 "fast-dev-cycles", User Story 1) — item-id dispatch-
# stamping mechanism. In GUARD mode it enforces that every Agent/Task/
# TaskCreate dispatch's description carries an `item=<ATM-nnnn>` token
# (or the honest `item=?` form) alongside the constitution §11.4.182
# `(T<N>/<branch> - <alias>...)` label. In EXTRACTION mode it exposes a
# one-line helper a LATER, SEPARATE task (T037, SERIAL, conductor-only —
# "Wire dispatch_stamp.sh into ... the PreToolUse hook list in
# .claude/settings.json AND into agent_registry_writer.sh") can call to
# pull the extracted id into the dispatch registry's JSONL row WITHOUT
# re-deriving this file's parsing regex.
#
# DERIVED CONTRACT (tasks.md:120 is the ONLY spec line naming this file as
# ITS OWN deliverable; no contracts/*.md exists for it). CLARIFIED
# 2026-09-28 (§11.4.6, found by independent review): this file IS also
# referenced as a guarded dependency by a SIBLING RED test in the same
# T015-T026 batch, `constitution/scripts/fastcycle/tests/
# test_token_attribution_red.sh` (T020, "PART A"), which independently
# corroborates the item=<ATM-nnnn> contract derived below — see that
# file's own header + test_dispatch_stamp_red.sh's "THE GAP" section for
# the full correction. Every clause below traces to a REAL,
# currently-existing sibling mechanism, read in full before writing this
# file. See constitution/scripts/fastcycle/tests/test_dispatch_stamp_red.sh
# for the complete derivation trail:
#   constitution/scripts/hooks/guard-track-branch-label.sh   (GUARD-mode
#     stdin-JSON / exit-0-allow / exit-2-block contract + json_field
#     extractor, reused verbatim here for consistency — see that file's own
#     comment: each guard hook is a single self-contained file, not a
#     shared-lib import, so duplicating the extractor matches the
#     established sibling convention rather than diverging from it)
#   constitution/scripts/hooks/guard-work-track-binding.sh   (same
#     PreToolUse contract on the SAME Agent|Task|TaskCreate matcher)
#   scripts/hooks/agent_registry_writer.sh                    (its
#     CRITICAL ROBUSTNESS GUARANTEE — always-exit-0 — is the model for
#     this file's EXTRACTION mode; its {ts,event,key,tool_name,session_id,
#     description,note} JSONL schema has NO `item` field today, confirming
#     "hands the id to the registry writer" is T037's wiring step, not
#     this task's)
#
# =============================================================================
# MODE 1 (default, GUARD mode) — Claude Code PreToolUse guard-hook contract,
#   IDENTICAL to its two siblings on the SAME Agent|Task|TaskCreate matcher:
#     - Receives the tool invocation as JSON on stdin.
#     - Exit 0  -> allow (Claude proceeds).
#     - Exit 2  -> BLOCK; stderr text is fed back to Claude as the refusal
#       reason.
#   SCOPE: tool_name in {Agent, Task, TaskCreate} MUST carry an
#     `item=(ATM-[0-9]+|\?)` token SOMEWHERE in `.tool_input.description`
#     (falling back to `.tool_input.subagent`, exactly as
#     guard-track-branch-label.sh does). EVERY OTHER tool_name passes
#     through untouched (exit 0) — this hook never breaks non-agent tools.
#
#   WHAT THE GUARD CANNOT CLASSIFY (T048 restart round 9, S2). The guard
#     decides on `.tool_name`, so its contract for input that does not name a
#     tool is explicit, and the code, this comment and the tests agree on it:
#       - ALLOWED (exit 0): an empty or whitespace-only stdin, and ONE
#         well-formed JSON object that has no `tool_name` key. The hook matcher
#         in .claude/settings.json (Agent|Task|TaskCreate) guarantees a
#         `tool_name` on every real dispatch, so such input is not a dispatch;
#         the sibling guard-track-branch-label.sh allows it the same way.
#       - REFUSED (exit 2, fail closed): a non-empty payload that is not
#         exactly one valid JSON object, and a `tool_name` that is PRESENT but
#         not a string (null, a number, a boolean, an object or an array): the
#         hook cannot tell what tool that is, and a payload that hides the
#         tool name must not slip through as "some other tool".
#     Nothing a real Claude Code Agent / Task / TaskCreate payload carries is
#     refused by this rule: `tool_name` is always a string there, and every
#     other key (tool_input.description / prompt / subagent_type / model,
#     session_id, transcript_path, cwd, permission_mode, hook_event_name,
#     tool_use_id, tool_response, ...) is read only when it is the exact
#     `tool_name` or `tool_input` path.
#
#   HONEST '?' HANDLING (a genuinely ambiguous point this file resolves
#     with explicit reasoning, per the RED test's own instruction not to
#     guess it): the honest `item=?` form is ALWAYS accepted (exit 0),
#     matching the §11.4.6/§11.4.182 no-fabricated-verdict precedent the
#     sibling label guard already establishes for its alias/model/effort
#     fields. UNLIKE that sibling's <effort> field, though, this file adds
#     NO bluff-check against a "live" value for `?` — guard-track-branch-
#     label.sh can cross-check a dispatcher's honest `?` effort against a
#     REAL, environment-derivable live effort signal (CLAUDE_EFFORT et al,
#     via the reference labeler) and BLOCK a `?` that is provably dishonest
#     given that signal. There is NO equivalent "live item id" an ATM
#     ticket number could be derived from: a work-item id is a human/agent
#     CHOICE at dispatch time, not a value computable from the environment
#     (unlike track/branch/alias/model/effort, which the reference labeler
#     genuinely derives). Building a bluff-check here would therefore
#     require GUESSING what the "correct" id should have been — exactly
#     the §11.4.6 violation the RED test warns against — so `item=?` is
#     treated as unconditionally honest in this file.
#
#   PLACEMENT (the second genuinely ambiguous point, likewise resolved with
#     explicit reasoning rather than guessed): tasks.md's one line —
#     "requires item=<ATM-nnnn> ... alongside the §11.4.182 label" — settles
#     WHAT is required, not WHERE. The RECOMMENDED placement is immediately
#     AFTER the §11.4.182 label prefix, e.g.:
#       (T1/main - claude5 - sonnet - high) item=ATM-1041 T036 implement ...
#     but the regex below matches `item=` ANYWHERE in the description (at a
#     token boundary — see ITEM_RE), so a dispatcher that places it later in
#     the free-text task description is still accepted. This file does NOT
#     enforce a fixed position, since tasks.md's wording does not settle one
#     and inventing a stricter rule than the spec states would itself be a
#     guess.
#
# MODE 2 (`--extract-item-id`, EXTRACTION mode) — T037's prerequisite helper:
#   Reads the SAME stdin JSON shape as MODE 1. tool_name is NOT restricted
#   in this mode (T037 will call it only from inside the same
#   Agent|Task|TaskCreate PreToolUse/PostToolUse matcher
#   agent_registry_writer.sh already runs under, so re-gating on tool_name
#   here would be redundant and would only make this helper less reusable).
#   Prints to stdout, with NO other output:
#     - the extracted `ATM-nnnn` token, if a well-formed `item=ATM-nnnn` is
#       present;
#     - the literal `?`, if the honest `item=?` form is present;
#     - nothing (empty stdout), if `item=` is genuinely absent from the
#       description — so `id=$(... --extract-item-id <<<"$json")` yields an
#       empty string T037 can test with `[ -n "$id" ]` without a separate
#       sentinel value.
#   ALWAYS exits 0, in EVERY case (found / honest-unknown / absent / stdin
#   empty or unparseable) — see the ROBUSTNESS NOTE below.
#
# EXACT INVOCATION FOR T037 (so it never has to rediscover this):
#   id="$(printf '%s' "$RAW_STDIN_JSON" | bash \
#     "$REPO_ROOT/constitution/scripts/fastcycle/tokens/dispatch_stamp.sh" \
#     --extract-item-id)"
#   # $id is "" | "?" | "ATM-nnnn" — never anything else, never exits non-zero.
#
# ROBUSTNESS NOTE FOR T037 (derived contract stub 4): GUARD mode (MODE 1)
#   legitimately BLOCKS (exit 2) on a missing item= token — matching its
#   sibling label guard's identical blocking behaviour for a missing label;
#   that IS this tool's purpose in that mode. EXTRACTION mode (MODE 2) is a
#   DIFFERENT code path with a DIFFERENT guarantee: it NEVER exits non-zero,
#   under any input (mirrors agent_registry_writer.sh's own "CRITICAL
#   ROBUSTNESS GUARANTEE" that a non-zero PreToolUse-adjacent hook exit
#   BLOCKS the tool call — the exact §11.4.201(1) false-positive-refusal
#   class that writer's own header warns against). If T037 embeds a call to
#   `--extract-item-id` inside agent_registry_writer.sh's own always-exit-0
#   PreToolUse/PostToolUse contract, it can rely on THIS file's MODE 2
#   already being always-exit-0 in isolation — but T037's wiring step
#   remains responsible for not letting some OTHER failure in ITS OWN glue
#   code (e.g. an unguarded `set -e` around the call, or a `$(...)` command
#   substitution whose exit status is checked and misinterpreted) turn a
#   benign empty result into a hook-level non-zero effect; that isolation
#   is T037's job and is not derivable from this file alone.
#
# DECOUPLING (§11.4.177 / §11.4.28 -- F13 fix, T048 round-2 review): this
# file lives in the constitution submodule, inherited BY REFERENCE (never
# copied), and MUST carry ZERO project-specific literals. Its accepted
# ticket-id PREFIX(ES) are therefore CONFIGURABLE, never a hardcoded `ATM-`:
#
#   1. `FC_DISPATCH_ITEM_ID_RE` (env, highest priority) -- if set, this
#      value REPLACES the whole `item=` value alternation verbatim (e.g.
#      `ATM-[0-9]+|SPK-[0-9]+`), the consuming project's own explicit,
#      unvalidated choice (§11.4.6: an operator-supplied value is trusted,
#      never second-guessed).
#   2. Else, the DEFAULT prefix is DERIVED (never hardcoded) the SAME way
#      the sibling `constitution/scripts/release_prefix.sh` (§11.4.151) /
#      `constitution/scripts/workable-items/cmd/workable-items/prefix.go`'s
#      `deriveKeyPrefix()` already do for this exact class of value: resolve
#      the project's release prefix (HELIX_RELEASE_PREFIX env -> its .env
#      entry -> snake_case(project root dir name)), then take its first 3
#      ASCII letters, uppercased (padded with 'X' if <3, the neutral "WIT"
#      fallback if none) -- for THIS checkout that derives "ATM" from
#      "atmosphere" (verified live, 2026-09-30: `bash
#      constitution/scripts/release_prefix.sh` prints "atmosphere"), so
#      EVERY existing fixture/test in this suite (all written against
#      literal `ATM-nnnn` ids) keeps passing unchanged with ZERO test
#      edits -- while a DIFFERENT consuming project derives ITS OWN correct
#      prefix automatically, with no source edit to this file.
#   3. `FC_DISPATCH_EXTRA_ITEM_PREFIXES` (env, additive, comma/pipe/space-
#      separated) -- extra accepted prefixes ADDED to the derived default
#      from (2), e.g. `FC_DISPATCH_EXTRA_ITEM_PREFIXES=SPK` lets a dispatch
#      naming `item=SPK-609` (the real T045-sample id round-2's F13 finding
#      named) pass, entirely via CONFIGURATION -- never a source edit, and
#      never silently widening the DEFAULT (which stays exactly `ATM-` for
#      an unconfigured checkout, preserving §11.4.6's "don't guess a wider
#      set than what's asked for" reasoning this file's earlier revision
#      already applied to the ATM-only default -- see git history).
#
# HERMETICITY NOTE: this DOES read `constitution/scripts/release_prefix.sh`
# (which in turn reads the git-tracked, checked-in project `.env`) once per
# invocation UNLESS `FC_DISPATCH_ITEM_ID_RE` is set -- a deliberate, narrow
# widening of the "no ambient ENV state affects this tool" claim in the
# companion `test_dispatch_stamp.sh` suite's own header, which is about
# session-scoped vars (CLAUDE_*, CLAUDE_CONFIG_DIR) varying RUN TO RUN, not
# about this repository's own stable, git-tracked `.env` release-prefix
# entry, which resolves identically on every invocation of this exact
# checkout (the same "hermetic within a fixed checkout" guarantee every
# other file-content-dependent check in this test family already relies on).
#
# NOW WIRED (T037 landed -- this comment corrected 2026-09-30, T048
#   round-2 review F13; the file previously said "NOT YET WIRED" long after
#   T037 registered it): this file IS the guard command in
#   `.claude/settings.json`'s PreToolUse hook chain (search "dispatch_stamp"
#   in that file) AND is invoked by `scripts/hooks/agent_registry_writer.sh`
#   (its `--extract-item-id` EXTRACTION mode, search "DISPATCH_STAMP" in
#   that file) -- both confirmed present in this checkout, 2026-09-30.
#
# Producer != Verifier (constitution §11.4.240): this implementation is a
# separate, later step from the RED-test's author; it is followed by an
# INDEPENDENT §11.4.209 Opus-xhigh review before being trusted — this file's
# author never self-certifies it as that review.
#
# Usage:
#   printf '%s' "$json" | bash dispatch_stamp.sh                  # GUARD mode
#   printf '%s' "$json" | bash dispatch_stamp.sh --extract-item-id # EXTRACTION mode
#
# THE ENVIRONMENT (T048 restart round 11, RV11-2 / RV11-5). The verdict must
# not depend on what else the caller exports. Measured on the round-10 tree:
# jq 1.8.1 auto-loads ~/.jq, so a ~/.jq redefining `objects` made the guard
# ALLOW an untagged dispatch and a ~/.jq with a syntax error refused every
# dispatch; POSIXLY_CORRECT put gawk in POSIX mode, the awk probe failed and
# every dispatch was refused with a wrong message. The fix is one rule, not a
# list of variables: the first lines of this file re-execute it with
# `exec -c` (an EMPTY environment) and export back only the allowlist PATH,
# HOME, FC_DISPATCH_ITEM_ID_RE, FC_DISPATCH_EXTRA_ITEM_PREFIXES,
# HELIX_RELEASE_PREFIX and HELIX_PROJECT_ROOT -- every variable this tool or
# release_prefix.sh reads. LC_ALL=C is set below. jq additionally runs with
# HOME=/dev/null/fc-no-home, a path that cannot exist, so no ~/.jq can be
# loaded. Guard: test_dispatch_stamp.sh section N (a hostile environment
# matrix: bad ~/.jq, POSIXLY_CORRECT, AWKPATH, AWKLIBPATH, GAWK_READ_TIMEOUT,
# BASH_ENV, ENV, IFS, SHELLOPTS, BASHOPTS, exported functions, LC_ALL / LANG
# variants, JQ_COLORS; every verdict equals the clean run, with and without
# jq) and test_token_attribution_red.sh K21 (the ingest half).
# HONEST BOUNDARY: code that runs BEFORE the first line of this file is out
# of its reach -- a BASH_ENV file (bash runs it first for every non-
# interactive script) that writes output or exits, or an exported function
# named after one of the bash builtins the five re-exec lines use (unset,
# exec, shopt). The re-exec removes everything such code SET (functions,
# shell options, variables); it cannot undo what such code DID. Closing that
# needs the hook command itself to start bash without them (`bash -p ...` in
# .claude/settings.json, privileged mode: no BASH_ENV/ENV, no imported
# functions, SHELLOPTS/BASHOPTS ignored) -- the conductor's step, see
# docs/qa/t048_restart_round5_20261009/V1_followups.md (round 11).
#
# DEFERRALS LEDGER (T048 restart rounds 2, 3, 9, 10 and 11):
#   CLOSED in round 11 (STRUCTURAL round, §11.4.276(E); each finding was a
#   single instance of a class, so each fix closes the class):
#   RV11-1 (class: a configured string used as a regex fragment) -- an extra
#   prefix is DATA: kept only when its ASCII upper-case form is [A-Z0-9]+,
#   else ignored with a GUARD notice; transcript_ingest.py applies the same
#   rule. Guard: test_dispatch_stamp.sh section L (a generated corpus through
#   both tools, 680 token x description pairs, identical extraction).
#   RV11-2 / RV11-5 (class: the caller's environment changes the verdict) --
#   the clean re-execution (THE ENVIRONMENT, above); guard: section N.
#   RV11-3 (class: reader time not linear on adversarial input) -- the path
#   is matched per depth (pm[] / seg_ok()), never rebuilt per value, and the
#   payload is read as one record; guard: sections M and Q.
#   Reviewer mutant V1 (CR is not whitespace) -- section O pins absolute
#   verdicts for CR / LF / TAB between tokens in both paths.
#   CORRECTED (round 11, RV11-10): two round-10 statements below were wider
#   than what had been measured. (1) F9 said "a configured pattern that is not
#   a valid regex falls back"; that held for an INVALID pattern only -- a
#   token that compiled but was malformed (`)`, `{`, `\D`, `ATM-1`) silently
#   changed or split the verdict (RV11-1, closed above). The fallback now
#   applies to FC_DISPATCH_ITEM_ID_RE alone (section L2). (2) F3/F4 gave
#   "about 0.3 s/MB with jq, 0.85 s/MB without" as if it bounded the reader;
#   it was measured on ONE shape (a long string of \u00e9 escapes). Arrays
#   nested 8000 deep around 8000 strings (48 KB) took 30.8 s without jq and
#   5.6 s with it on the round-10 tree (quadratic). MEASURED on the round-11
#   tree (reference host, 64 cores, gawk 5.1.0, jq 1.8.1, load average about
#   4-5; faster of two runs; small size / 4x size, ms, jq then no jq):
#   deep arrays 12 KB/48 KB 35/54, 36/85; deep objects 26 KB/106 KB 40/72,
#   52/146; one 12 KB key over 12000 values 35/49, 34/75; escapes 0.6 MB/2.4
#   MB 157/548, 433/1690; many small values 0.26 MB/1.0 MB 130/434, 293/1115;
#   a description full of near-tags 0.56 MB/2.2 MB 146/501, 313/1206. These
#   are measurements of these shapes, not a proof for every shape; section M
#   re-measures them on every run (4x the input < 8x the time + 300 ms, and
#   10 s per run). The hook-timeout exposure stated below is unchanged.
#   CLOSED in round 10 (V1 re-review of the landed tree): F8 -- the reader's
#   depth limit now charges jq 1.8.1's weights (see open_weight()), so the
#   jq and the jq-less paths refuse the same documents (objects nested
#   5000-9998 deep used to be allowed only without jq). F9 -- the extra
#   prefixes are no longer glob-expanded, and a configured pattern that is
#   not a valid regex falls back to the derived prefix (as the ingest tool
#   does) instead of refusing every dispatch [narrowed in round 11, see
#   CORRECTED above]. F3/F4 -- MEASURED on one shape only [see CORRECTED
#   above]: on the reference host (64 cores, gawk 5.1.0, jq 1.8.1, under
#   normal load) a 4.2 MB description of \u00e9 escapes is decided in 1.4 s
#   with jq and 3.6 s without, 16.8 MB in 5.0 s / 14.1 s. A payload
#   large enough to exceed the hook's timeout is the remaining exposure: the
#   reviewer reports that Claude Code proceeds when a hook times out (fail
#   open); .claude/settings.json sets no timeout for this hook, so Claude
#   Code's default applies (not measured here). test_dispatch_stamp.sh
#   section K pins a 30 s bound at 4.2 MB and a linearity ratio.
#   CLOSED in round 9 (V1 re-review follow-ups): S2 -- the guard contract for
#   input that names no tool is now explicit and tested (see WHAT THE GUARD
#   CANNOT CLASSIFY: empty input and an object without tool_name are allowed;
#   a tool_name that is present but not a string is refused). S3 -- the jq-less
#   reader was quadratic in the number of \uXXXX escapes (`out = out utf8(cp)`);
#   it is linear now (3 MB of escapes: 15.5 s -> 2.4 s without jq on the
#   reference host). P2 -- the jq-less reader is verified on GAWK ONLY (GNU Awk
#   5.1.0); an awk without RT, a NUL record separator or a one-byte %c is
#   refused with a clear message instead of mis-reading a payload. mawk and
#   busybox awk remain UNVERIFIED (refused, not supported).
#   CLOSED in round 3: R3V1-M1 -- the round-2 text below said the jq-less
#   reader takes the value "as jq does (the last one if a key repeats)"; that
#   held only for a string repeated over a string, and a later null / number
#   / object for the same key left the earlier tagged string in place (the
#   guard allowed what jq refused). A repeated key is now refused by the
#   shared reader for BOTH paths, as are two documents (jq used to read the
#   first one) -- see THE JSON READER. R3V1-M4 -- \u0000 and raw NUL bytes
#   (see the same block and the payload read).
#   CLOSED in round 2: (a) the jq-less fallback took the FIRST "description"
#   key anywhere in the payload and failed OPEN on a nested one -- replaced by
#   an exact-path JSON reader that fails closed (see json_read); (b) the
#   release_prefix.sh fallback to "WIT" was silent -- GUARD mode now prints a
#   notice (see _fc_resolve_default_prefix). (c) "file order" belongs to
#   transcript_ingest.py and is closed there.
#   OWED ITEMS (open; T048 restart round 3, R3V1-M5). Honest state: written
#   here and in transcript_ingest.py, but the tracker DB holds NO row for
#   them as of round 3 -- registering them is the conductor's step:
#   OWED-DS-1: the test suites next to this file (test_dispatch_stamp*.sh,
#   including the r6 mutation proof and the r7 matrix) are not invoked by
#   any runner or gate; tests/run_all.sh globs tests/ only. Wiring them is
#   the conductor's step.
#   OWED-TI-1, OWED-TI-2: ingest-side, see transcript_ingest.py's ledger
#   (OWED-TI-2 is narrowed in round 11: only the full FC_DISPATCH_ITEM_ID_RE
#   override is still read by two regex engines; extra prefixes are data).
#   ATM-1133 MISMATCH: tracker item ATM-1133 ("fail-closed on missing jq",
#   Queued) disagrees with this file. jq is NOT required: the strict awk
#   reader is the gate for both paths, and only a missing awk fails closed
#   (AWK_MISSING). The conductor must re-scope or close ATM-1133.
#
# Classification: universal.

set -uo pipefail

# LOCALE (V1-M2, T048 restart round 2): every regex, character class and
# `tr` below runs under LC_ALL=C, so the accepted tag set is the same for
# every caller locale and equals transcript_ingest.py's (which spells the
# same ASCII classes out and compiles with re.ASCII). Before this, bash's
# [[:space:]] / [[:alnum:]] followed the caller's locale: `item=ATM-12é`
# extracted ATM-12 under C but nothing under C.UTF-8, and U+2003 before the
# tag counted as a separator under C.UTF-8 only. (Set before the payload is
# read, so the read below also runs byte-wise.)
export LC_ALL=C
# jq 1.7+ auto-imports the file ~/.jq into every program (round 11, RV11-2:
# a ~/.jq redefining `objects` turned an untagged dispatch into an allowed
# one). jq runs with HOME set to this path, which cannot exist (/dev/null is
# not a directory), so there is no ~/.jq to load.
_FC_JQ_HOME=/dev/null/fc-no-home

# Reading the payload (T048 restart round 3, R3V1-M4): bash silently drops a
# NUL byte from a command substitution (and prints a warning on stderr,
# which breaks EXTRACTION mode's "no other output" contract). A raw NUL can
# then make an invalid payload look valid. Each raw NUL is therefore turned
# into the control byte 0x01 while reading, which the JSON reader below
# refuses (inside a string it is an unescaped control character, outside one
# it is not JSON), so a payload carrying a raw NUL is refused, never quietly
# altered. Without awk the payload cannot be read safely: AWK_MISSING makes
# the guard refuse (fail closed) and the extraction return nothing.
AWK_MISSING=0
AWK_PROBLEM=""
if command -v awk >/dev/null 2>&1; then
  # T048 restart round 9, P2: this reader relies on gawk's record terminator
  # variable RT (to keep a trailing NUL), on a NUL record separator and on a
  # single-byte %c (code 233 must be the one byte octal 351) under LC_ALL=C. The no-jq path has been verified on gawk only
  # (GNU Awk 5.1.0 on the reference host); mawk and busybox awk are NOT
  # verified. Probe the three capabilities and refuse (fail closed, with a
  # clear message) on an awk that lacks any, instead of mis-reading a payload.
  _AWK_PROBE='BEGIN { RS = "\0" } { n++ } END { exit !(n == 2 && RT == "\0" && sprintf("%c", 233) == "\351") }'
  if ! printf 'a\0b\0' | awk "$_AWK_PROBE" >/dev/null 2>&1; then
    AWK_MISSING=1
    AWK_PROBLEM="the awk on PATH is not gawk-compatible (it lacks RT, a NUL record separator or a single-byte %c); only gawk is verified for the jq-less reader"
  fi
fi
if [ "$AWK_MISSING" -eq 0 ] && command -v awk >/dev/null 2>&1; then
  PAYLOAD="$(awk 'BEGIN { RS = "\0"; ORS = "" } { if (NR > 1) printf "\001"; printf "%s", $0 } END { if (RT != "") printf "\001" }' || true)"
else
  AWK_MISSING=1
  AWK_PROBLEM="${AWK_PROBLEM:-awk is not installed}"
  { PAYLOAD="$(cat || true)"; } 2>/dev/null
fi

# --------------------------------------------------------------------------
# THE JSON READER (T048 restart round 3, R3V1-M1/M4 and the parity matrix).
#
# json_read <path> -- one strict pass of a small JSON reader written in
# awk over the whole payload. It exits 3 (refuse) unless the payload is
# exactly one JSON object, or empty. With a path it prints the STRING value
# at exactly that path (empty if the path is absent or not a string). A path
# is a concatenation of segments, an object key encoded <length>:<key> (so
# the path of tool_input -> description is "10:tool_input11:description"
# and can never collide with a top-level key that merely CONTAINS a dot). With "-" it prints "E" for an empty
# payload and "O" for an object, and is used as the GATE below.
#
# The SAME reader is the gate for BOTH readers: jq, when installed, only
# extracts values from a payload this reader has already accepted. So the
# allow/block decision does not depend on whether jq is installed. Evidence
# (not proof): the parity matrix in test_dispatch_stamp_r7_matrix.sh compares
# the two paths on the reviewer's 46 adversarial payloads, the round-8
# additions and 500 seeded fuzz payloads, and the failure-path rows pin
# absolute verdicts that a shared-gate regression cannot hide. It refuses,
# and so does the guard (fail closed):
#   - anything but one JSON object: a second document, trailing text, a BOM,
#     `01`, `+1`, `nan`, a trailing comma, a raw control character inside a
#     string, an unknown escape, a bad \u escape;
#   - a DUPLICATE key in any object (R3V1-M1). jq keeps the last value and
#     the earlier reader kept the last STRING, so `"description":"item=X",
#     "description":null` was allowed by one reader and refused by the other;
#     a repeated key is now refused by both, whatever the values;
#   - nesting deeper than jq 1.8.1 accepts (round 10, F8): jq's parser stack
#     holds at most 10000 entries, an array costing one and a container that
#     is the value of an object member costing two (its pending key). So a
#     payload (itself an object) holds at most 9998 arrays, or 4999 objects,
#     nested inside it. The reader charges the same weights (open_weight()),
#     so jq and the awk path refuse the same documents. Before round 10 the
#     reader counted every container as one and allowed 9999: objects nested
#     5000-9998 deep were allowed without jq and refused with it, so the
#     verdict depended on jq being installed. Measured on jq 1.8.1 only; an
#     older jq with a smaller limit makes the jq path refuse MORE, never less
#     (a jq parse failure is a refusal), so it can only be stricter;
#   - a high surrogate \uD800-\uDBFF not followed by a low one (jq refuses).
# It decodes, as jq does: a lone LOW surrogate to U+FFFD. And it decodes
# \u0000 to U+FFFD (R3V1-M4): bash cannot hold a NUL, and a dropped NUL used
# to move the tag to the start of the string, so `\u0000item=ATM-1` was
# accepted here while transcript_ingest.py (which sees the NUL) attributed
# nothing. With U+FFFD neither tool sees a tag there.
#
# T048 restart round 2, V1-M4(a): before that round the jq-less fallback took
# the FIRST '"description"' key anywhere in the payload (fail open).
# --------------------------------------------------------------------------
json_read() {
  printf '%s' "$PAYLOAD" | awk -v want="$1" -v typeq="${2:-}" '
    function hexval(h,   i, c, v) {
      if (length(h) != 4) return -1
      v = 0
      for (i = 1; i <= 4; i++) {
        c = index("0123456789abcdef", tolower(substr(h, i, 1)))
        if (c == 0) return -1
        v = v * 16 + c - 1
      }
      return v
    }
    function utf8(cp) {
      if (cp < 128) return sprintf("%c", cp)
      if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
      if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
      return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
    }
    # parse_string: s[pos] is the opening quote. Sets STR and moves pos past
    # the closing quote; returns 0 on an invalid or unterminated string.
    function parse_string(   c, out, cp, lo, ch) {
      pos++
      out = ""
      while (pos <= n) {
        c = substr(s, pos, 1)
        if (c == "\"") { pos++; STR = out; return 1 }
        if (c < " ") return 0
        if (c == "\\") {
          c = substr(s, pos + 1, 1)
          if (c == "n") out = out "\n"
          else if (c == "t") out = out "\t"
          else if (c == "r") out = out "\r"
          else if (c == "b") out = out "\b"
          else if (c == "f") out = out "\f"
          else if (c == "\"" || c == "\\" || c == "/") out = out c
          else if (c == "u") {
            cp = hexval(substr(s, pos + 2, 4))
            if (cp < 0) return 0
            pos += 4
            if (cp >= 55296 && cp < 56320) {
              if (substr(s, pos + 2, 2) != "\\u") return 0
              lo = hexval(substr(s, pos + 4, 4))
              if (lo < 56320 || lo >= 57344) return 0
              cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); pos += 6
            } else if (cp >= 56320 && cp < 57344) cp = 65533
            if (cp == 0) cp = 65533
            # Round 9, S3: the decoded character goes through a variable. In
            # gawk, `out = out utf8(cp)` (a function call inside the append)
            # copies the whole string every time, which made a string with
            # many \uXXXX escapes quadratic (3 MB took 13 s with jq, 40 s
            # without); `ch = utf8(cp); out = out ch` is a linear append.
            ch = utf8(cp)
            out = out ch
          } else return 0
          pos += 2
          continue
        }
        out = out c
        pos++
      }
      return 0
    }
    function skip_ws() { while (pos <= n && index(" \t\r\n", substr(s, pos, 1)) > 0) pos++ }
    # THE PATH (round 11, RV11-3). The wanted path is a list of segments: an
    # object key, encoded <length>:<key>, or an array, "[]" -- unambiguous
    # (T048 restart round 8, F2: the earlier "key.key" join made a top-level
    # key literally named "tool_input.description" collide with the nested
    # tool_input -> description path). parse_want() splits it ONCE into
    # wtyp[1..WD] / wkey[1..WD]. Before round 11 the path of every value was
    # REBUILT as a string from all open containers (cur_path()), so a payload
    # holding many values deep inside many containers cost depth x values:
    # arrays nested 8000 deep around 8000 strings (48 KB) took 24.8 s without
    # jq and 4.6 s with it (as the reviewer measured). Now the match is kept
    # per depth as containers open and close: pm[j] says the containers 1..j-1
    # sit on the wanted path, set once when container j opens, so deciding
    # whether a value is the wanted one is a constant number of comparisons.
    function parse_want(   w, i, len) {
      WD = 0
      if (want == "-" || want == "") return
      w = want
      while (w != "") {
        if (substr(w, 1, 2) == "[]") { WD++; wtyp[WD] = "a"; wkey[WD] = ""; w = substr(w, 3); continue }
        i = index(w, ":")
        if (i < 2 || substr(w, 1, i - 1) !~ /^[0-9]+$/) { WD = 0; return }
        len = substr(w, 1, i - 1) + 0
        WD++; wtyp[WD] = "o"; wkey[WD] = substr(w, i + 1, len); w = substr(w, i + 1 + len)
      }
    }
    # seg_ok(j): the open container j, under its current key, is segment j of
    # the wanted path.
    function seg_ok(j) { return (typ[j] == "o") ? (wtyp[j] == "o" && key[j] == wkey[j]) : (wtyp[j] == "a") }
    # at_want: the value being read sits exactly at the wanted path.
    function at_want() { return (WD > 0 && d == WD && pm[d] && seg_ok(d)) }
    # value_done: a value was completed at the current depth.
    function value_done() { need = (d == 0) ? "done" : "sep" }
    # note_type: remember the JSON type of the value at the wanted path (used
    # by the typeq mode below; the type names are those of jq).
    function note_type(t) { if (typeq != "" && at_want()) vtype = t }
    # open_weight: the depth jq charges for a container opened at the current
    # position (round 10, F8). jq 1.8.1 refuses a document whose parser stack
    # would exceed 10000 entries; an array costs one entry, and a container that
    # is the VALUE of an object member costs one more (jq keeps the pending key
    # on the stack). Measured on jq 1.8.1: 10000 nested arrays are accepted and
    # 10001 refused; 5000 nested objects are accepted and 5001 refused; 9999
    # arrays around {"a":1} are accepted, 9998 arrays around {"a":{}} refused.
    # Charging the same weight here makes this gate refuse exactly what jq
    # refuses, so the verdict no longer depends on whether jq is installed.
    function open_weight() { return (d == 0) ? 1 : wd[d] + (typ[d] == "o" ? 2 : 1) }
    # One record: the payload holds no NUL (raw NULs were turned into 0x01
    # when it was read), so RS = "\0" reads it whole, without the per-line
    # appends a newline-rich payload used to cost.
    BEGIN { RS = "\0" }
    { buf = buf $0 }
    END {
      MAXW = 10000
      parse_want()
      s = buf; n = length(s); pos = 1; d = 0; need = "value"; val = ""; nobj = 0
      skip_ws()
      if (pos > n) { if (want == "-") printf "E"; exit 0 }
      if (substr(s, pos, 1) != "{") exit 3
      while (1) {
        skip_ws()
        if (pos > n) break
        c = substr(s, pos, 1)
        if (need == "done") exit 3
        if (need == "key" || need == "key_or_end") {
          if (c == "}" && need == "key_or_end") { pos++; d--; value_done(); continue }
          if (c != "\"") exit 3
          if (!parse_string()) exit 3
          if ((oid[d], STR) in seen) exit 3
          seen[oid[d], STR] = 1
          key[d] = STR; need = "colon"; continue
        }
        if (need == "colon") { if (c != ":") exit 3; pos++; need = "value"; continue }
        if (need == "sep") {
          if (c == ",") { pos++; need = (typ[d] == "o") ? "key" : "value"; continue }
          if ((c == "}" && typ[d] == "o") || (c == "]" && typ[d] == "a")) { pos++; d--; value_done(); continue }
          exit 3
        }
        # need is "value" or "value_or_end"
        if (c == "]" && need == "value_or_end") { pos++; d--; value_done(); continue }
        if (c == "{") {
          nw = open_weight()
          if (nw > MAXW) exit 3
          note_type("object")
          npm = (d == 0) ? (WD >= 1) : (pm[d] && d < WD && seg_ok(d))
          pos++; d++; wd[d] = nw; typ[d] = "o"; key[d] = ""; oid[d] = ++nobj; pm[d] = npm; need = "key_or_end"; continue
        }
        if (c == "[") {
          nw = open_weight()
          if (nw > MAXW) exit 3
          note_type("array")
          npm = (d == 0) ? (WD >= 1) : (pm[d] && d < WD && seg_ok(d))
          pos++; d++; wd[d] = nw; typ[d] = "a"; pm[d] = npm; need = "value_or_end"; continue
        }
        if (c == "\"") {
          if (!parse_string()) exit 3
          if (at_want()) val = STR
          note_type("string")
          value_done(); continue
        }
        tok = ""
        while (pos <= n && index("-+.0123456789eEtrufalsn", substr(s, pos, 1)) > 0) { tok = tok substr(s, pos, 1); pos++ }
        if (tok != "true" && tok != "false" && tok != "null" && tok !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) exit 3
        note_type(tok == "null" ? "null" : (tok == "true" || tok == "false") ? "boolean" : "number")
        value_done()
      }
      if (need != "done") exit 3
      if (typeq != "") printf "%s", vtype
      else if (want == "-") printf "O"
      else printf "%s", val
    }
  '
}

# json_field <key> [<key>...] -- the STRING value at that key path of the
# payload (e.g. `json_field tool_input description`), empty if the path is
# absent or not a string. Only called after the gate accepted the payload.
# jq is used when present; the key path is walked through objects only
# (`objects`), so a non-object on the way gives an empty value, exactly as
# the awk reader does. A jq failure (it would mean jq refuses a payload the
# gate accepted) returns 3: the caller then refuses, fail closed.
json_field() {
  local out rc k jqpath="." awkpath=""
  for k in "$@"; do
    jqpath="$jqpath | objects | .${k}"
    awkpath="${awkpath}${#k}:${k}"
  done
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$PAYLOAD" | HOME="$_FC_JQ_HOME" jq -n -r "[inputs] | if length != 1 then error(\"not one document\") else .[0] end | ${jqpath} | if type == \"string\" then gsub(\"\\u0000\"; \"\\ufffd\") else empty end" 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] || return 3
    printf '%s' "$out"
    return 0
  fi
  json_read "$awkpath"
}

# json_type <key> -- the JSON type name (string, number, boolean, null,
# object, array; jq's names) of the TOP-LEVEL value at <key>, empty if the
# key is absent or the document is not an object. Only called after the gate
# accepted the payload (T048 restart round 9, S2: a `tool_name` that is
# present but not a string must be refused, which json_field cannot tell
# apart from an absent one). jq and the awk reader agree (r7 matrix).
json_type() {
  local out rc
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$PAYLOAD" | HOME="$_FC_JQ_HOME" jq -n -r --arg k "$1" '[inputs] | if length != 1 then error("not one document") else .[0] end | objects | if has($k) then (.[$k] | type) else empty end' 2>/dev/null)"
    rc=$?
    [ "$rc" -eq 0 ] || return 3
    printf '%s' "$out"
    return 0
  fi
  json_read "${#1}:$1" type
}

# The GATE, then the fields. The item token lives on `description`; fall back
# to a `subagent` label if present -- identical fallback order to
# guard-track-branch-label.sh. A payload the gate refuses (exit 3), or a host
# without awk, gives PARSE_OK=0: no fields are read.
PARSE_OK=1
EMPTY_DOC=0
DESCRIPTION=""
TOOL_NAME=""
if [[ "$AWK_MISSING" -eq 1 ]]; then
  PARSE_OK=0
else
  GATE="$(json_read -)" || PARSE_OK=0
  [ "$PARSE_OK" -eq 1 ] && [ "$GATE" = "E" ] && EMPTY_DOC=1
fi
if [[ "$PARSE_OK" -eq 1 && "$EMPTY_DOC" -eq 0 ]]; then
  DESCRIPTION="$(json_field tool_input description)" || PARSE_OK=0
  if [[ "$PARSE_OK" -eq 1 && -z "$DESCRIPTION" ]]; then
    DESCRIPTION="$(json_field tool_input subagent)" || PARSE_OK=0
  fi
fi

# F13 fix (T048 round-2 review, §11.4.28/§11.4.177): the accepted ticket-id
# PREFIX(ES) are resolved, never hardcoded -- see the DECOUPLING header
# comment above for the full 3-tier priority + hermeticity reasoning.
_fc_derive_key_prefix() {
  # Mirror constitution/scripts/workable-items/cmd/workable-items/prefix.go's
  # deriveKeyPrefix(): first 3 ASCII letters of $1, uppercased; padded with
  # 'X' if fewer than 3; the neutral "WIT" fallback if the input has no
  # ASCII letters at all.
  local input="$1" letters="" i=0 n c
  n=${#input}
  while [ "$i" -lt "$n" ] && [ "${#letters}" -lt 3 ]; do
    c="${input:$i:1}"
    case "$c" in
      [a-zA-Z]) letters="${letters}$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')" ;;
    esac
    i=$((i + 1))
  done
  if [ -z "$letters" ]; then
    printf 'WIT'
    return 0
  fi
  while [ "${#letters}" -lt 3 ]; do
    letters="${letters}X"
  done
  printf '%s' "$letters"
}

# _fc_resolve_default_prefix -- sets FC_DEFAULT_PREFIX to the 3-letter key
# derived from the project's release prefix (scripts/release_prefix.sh:
# HELIX_RELEASE_PREFIX env -> its .env entry -> snake_case(project root
# dir name)), and FC_PREFIX_NOTICE to a one-line explanation when that
# resolution failed and the neutral "WIT" key (or a key derived from partial
# output) is used instead. Runs in the current shell, never in $(...), so
# both variables reach the caller.
#
# T048 round-3 review finding R3-M1 (2026-09-30): this used to fall back to
# the LITERAL "ATM" -- a project-specific guess inside this project-agnostic
# constitution submodule (§11.4.28/§11.4.177). The fallback is the neutral
# "WIT" from _fc_derive_key_prefix().
#
# T048 restart round 2, V1-M3: the fallback used to be silent (release_
# prefix.sh's stderr and exit status were discarded), while
# transcript_ingest.py warns on the same failure. FC_PREFIX_NOTICE is now
# printed on stderr in GUARD mode; EXTRACTION mode stays silent, because its
# contract is "stdout is the id, no other output".
_fc_resolve_default_prefix() {
  local self_path self_dir rp_script="" base="" rc=0
  FC_PREFIX_NOTICE=""
  # Pure bash parameter-expansion dirname (never the external `dirname`
  # command): the G-section AWK-fallback tests in test_dispatch_stamp.sh
  # restrict PATH to only awk+cat.
  self_path="${BASH_SOURCE[0]:-$0}"
  self_dir="${self_path%/*}"
  [ "$self_dir" = "$self_path" ] && self_dir="."
  if [ -n "$self_dir" ]; then
    rp_script="$(cd "$self_dir/../.." 2>/dev/null && pwd 2>/dev/null || true)/release_prefix.sh"
  fi
  if [ -n "$rp_script" ] && [ -f "$rp_script" ]; then
    base="$(bash "$rp_script" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      FC_PREFIX_NOTICE="release_prefix.sh ($rp_script) exited $rc"
    elif [ -z "$base" ]; then
      FC_PREFIX_NOTICE="release_prefix.sh ($rp_script) printed nothing"
    fi
  else
    FC_PREFIX_NOTICE="release_prefix.sh not found (looked for ${rp_script:-<unresolvable>})"
  fi
  FC_DEFAULT_PREFIX="$(_fc_derive_key_prefix "$base")"
  if [ -n "$FC_PREFIX_NOTICE" ]; then
    FC_PREFIX_NOTICE="dispatch_stamp: NOTICE: $FC_PREFIX_NOTICE -- the item-tag prefix for this run is '$FC_DEFAULT_PREFIX'"
  fi
}

FC_PREFIX_NOTICE=""
FC_PREFIX_IGNORED=""
if [ -n "${FC_DISPATCH_ITEM_ID_RE:-}" ]; then
  ITEM_VALUE_RE="$FC_DISPATCH_ITEM_ID_RE"
  ITEM_FORM_LABEL="item=<an id matching FC_DISPATCH_ITEM_ID_RE='$FC_DISPATCH_ITEM_ID_RE'>"
  ITEM_EXAMPLE="item=<id>"
else
  _fc_resolve_default_prefix
  ITEM_ALL_PREFIXES="$FC_DEFAULT_PREFIX"
  if [ -n "${FC_DISPATCH_EXTRA_ITEM_PREFIXES:-}" ]; then
    # Round 10, F9: the list is split on words (as transcript_ingest.py's
    # re.split does) but NEVER glob-expanded. Before, an unquoted $(...) let
    # a token such as `Q*` expand to the names of files in the caller's
    # working directory, so the accepted prefixes depended on the cwd while
    # the ingest tool used the token as written. Globbing is switched off for
    # the loop and restored to the caller's setting afterwards.
    #
    # Round 11, RV11-1: a token is DATA, never a regex fragment. Upper-cased
    # (ASCII a-z only), it must consist of ASCII letters and digits only
    # (^[A-Z0-9]+$); any other token is IGNORED, with a GUARD-mode notice
    # (EXTRACTION stays silent). transcript_ingest.py applies the same rule.
    # Before, a token was pasted into the pattern: `)` unbalanced the groups
    # (item=ATM-1 extracted as "ATM" and an honest item=? was refused), `{`
    # and `\D` meant different things to bash and Python, `ATM-1` matched
    # "ATM-1-2" here and "ATM-1" there. Guard: test_dispatch_stamp.sh section L
    # (a generated token corpus through both tools, identical extraction).
    case $- in *f*) _fc_noglob_was=1 ;; *) _fc_noglob_was=0 ;; esac
    set -f
    for _fc_p in $(printf '%s' "$FC_DISPATCH_EXTRA_ITEM_PREFIXES" | tr ',|' '  '); do
      _fc_p_upper="$(printf '%s' "$_fc_p" | tr '[:lower:]' '[:upper:]')"
      case "$_fc_p_upper" in
        ''|*[!A-Z0-9]*) FC_PREFIX_IGNORED="${FC_PREFIX_IGNORED:+$FC_PREFIX_IGNORED }'$_fc_p'" ;;
        *) ITEM_ALL_PREFIXES="${ITEM_ALL_PREFIXES}|${_fc_p_upper}" ;;
      esac
    done
    [ "$_fc_noglob_was" -eq 1 ] || set +f
    if [ -n "$FC_PREFIX_IGNORED" ]; then
      FC_PREFIX_IGNORED="dispatch_stamp: NOTICE: FC_DISPATCH_EXTRA_ITEM_PREFIXES token(s) $FC_PREFIX_IGNORED ignored: a prefix is ASCII letters and digits only"
    fi
  fi
  ITEM_VALUE_RE="(${ITEM_ALL_PREFIXES})-[0-9]+"
  # V1-M3: the refusal names the RESOLVED prefix(es), never a project literal.
  ITEM_FORM_LABEL="item=<${FC_DEFAULT_PREFIX}-nnnn> (accepted prefixes: ${ITEM_ALL_PREFIXES//|/, })"
  ITEM_EXAMPLE="item=${FC_DEFAULT_PREFIX}-1041"
fi

# item=(<resolved-prefix(es)>-[0-9]+|\?) as a whole token -- the honest '?'
# form is unconditionally accepted (see header: no live-derivable value
# exists to cross-check it against, unlike the sibling label guard's
# <effort> field). Left: start of string or one ASCII whitespace character.
# Right (T048 restart round-1, R3 boundary note): end of string or anything
# but an ASCII letter, digit or underscore, so 'item=ATM-12x', 'item=ATM-12_x'
# and 'item=?foo' are not tags. Under LC_ALL=C (above) these classes are
# exactly transcript_ingest.py's ITEM_TAG_TEMPLATE classes, so the two tools
# accept the same set of tags in any caller locale; the shared guard is
# test_token_attribution_red.sh PART I4. The capture group used below stays
# BASH_REMATCH[2].
_fc_build_item_re() {
  ITEM_RE="(^|[[:space:]])item=(${ITEM_VALUE_RE}|\\?)([^[:alnum:]_]|\$)"
}
_fc_build_item_re

# Round 10 (F9 follow-up): a configured pattern that is not a valid regex
# (e.g. FC_DISPATCH_EXTRA_ITEM_PREFIXES='*' gives `(ATM|*)`) made every
# `=~` below fail with status 2, so the guard refused every dispatch while
# transcript_ingest.py, on the same value, warns and falls back to the
# derived default prefix. This tool now does the same: it keeps only the
# derived default prefix for this run and says so in GUARD mode (EXTRACTION
# mode stays silent: its contract is "stdout is the id, no other output").
FC_RE_NOTICE=""
[[ "" =~ $ITEM_RE ]]
if [ "$?" -eq 2 ]; then
  [ -n "${FC_DEFAULT_PREFIX:-}" ] || _fc_resolve_default_prefix
  FC_RE_NOTICE="dispatch_stamp: NOTICE: the configured item pattern (FC_DISPATCH_ITEM_ID_RE='${FC_DISPATCH_ITEM_ID_RE:-}' FC_DISPATCH_EXTRA_ITEM_PREFIXES='${FC_DISPATCH_EXTRA_ITEM_PREFIXES:-}') is not a valid regex -- only the derived default prefix '$FC_DEFAULT_PREFIX' is accepted for this run"
  ITEM_VALUE_RE="${FC_DEFAULT_PREFIX}-[0-9]+"
  ITEM_FORM_LABEL="item=<${FC_DEFAULT_PREFIX}-nnnn> (accepted prefixes: ${FC_DEFAULT_PREFIX})"
  ITEM_EXAMPLE="item=${FC_DEFAULT_PREFIX}-1041"
  _fc_build_item_re
fi

extract_item() {
  # Prints the captured item value (ATM-nnnn or literal '?') if ITEM_RE
  # matches anywhere in $1, else prints nothing.
  if [[ "$1" =~ $ITEM_RE ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  fi
}

# ==========================================================================
# MODE 2: --extract-item-id (ALWAYS exit 0; stdout is the id / '?' / empty,
# NO other output).
# ==========================================================================
if [[ "${1:-}" == "--extract-item-id" ]]; then
  extract_item "$DESCRIPTION"
  exit 0
fi

# ==========================================================================
# MODE 1 (default): PreToolUse guard.
# ==========================================================================
[ -n "$FC_PREFIX_NOTICE" ] && echo "$FC_PREFIX_NOTICE" >&2
[ -n "$FC_RE_NOTICE" ] && echo "$FC_RE_NOTICE" >&2
[ -n "$FC_PREFIX_IGNORED" ] && echo "$FC_PREFIX_IGNORED" >&2

REFUSE_REASON=""
if [[ "$PARSE_OK" -eq 1 && "$EMPTY_DOC" -eq 0 ]]; then
  TOOL_NAME="$(json_field tool_name)" || PARSE_OK=0
  TOOL_NAME_TYPE="$(json_type tool_name)" || PARSE_OK=0
  # S2: a tool_name that is present but not a string is refused (see WHAT THE
  # GUARD CANNOT CLASSIFY in the header). An absent one stays allowed.
  if [[ "$PARSE_OK" -eq 1 && -n "$TOOL_NAME_TYPE" && "$TOOL_NAME_TYPE" != "string" ]]; then
    PARSE_OK=0
    REFUSE_REASON="the payload's tool_name is present but is not a string (it is a JSON $TOOL_NAME_TYPE), so the hook cannot tell which tool this is"
  fi
fi
if [[ "$PARSE_OK" -eq 0 ]]; then
  # Fail closed: input that is not exactly one JSON object, or whose
  # tool_name is present but not a string, cannot be classified, so the hook
  # refuses rather than guessing. (Empty input and an object with no
  # tool_name are allowed above: they are not a dispatch.)
  {
    if [[ "$AWK_MISSING" -eq 1 ]]; then
      echo "guardrails: BLOCKED — T036 dispatch-stamp: $AWK_PROBLEM, so the hook payload cannot be read safely"
    elif [[ -n "$REFUSE_REASON" ]]; then
      echo "guardrails: BLOCKED — T036 dispatch-stamp: $REFUSE_REASON"
    else
      echo "guardrails: BLOCKED — T036 dispatch-stamp: the hook payload is not exactly one valid JSON object (a duplicate key, a second document, a raw control character, a bad escape or nesting deeper than jq accepts are refused)"
    fi
    echo "  extractor: $(command -v jq >/dev/null 2>&1 && echo jq || echo 'built-in awk reader (jq not installed)')"
    echo "  payload starts: ${PAYLOAD:0:120}"
  } >&2
  exit 2
fi

# Only the agent-dispatching tools carry an item stamp. Anything else is
# allowed untouched.
case "$TOOL_NAME" in
  Agent|Task|TaskCreate) ;;
  *) exit 0 ;;
esac

FOUND="$(extract_item "$DESCRIPTION")"
if [[ -n "$FOUND" ]]; then
  exit 0
fi

{
  echo "guardrails: BLOCKED — T036 dispatch-stamp: ${ITEM_FORM_LABEL} required"
  echo "Every ${TOOL_NAME} dispatch's description MUST carry an '${ITEM_FORM_LABEL%% (*}'"
  echo "token (or the honest 'item=?' form when genuinely unknown) alongside its"
  echo "§11.4.182 (T<N>/<branch> - <alias>...) label."
  if [[ -z "$DESCRIPTION" ]]; then
    echo "  Found: <no description/subagent label>"
  else
    echo "  Found: ${DESCRIPTION}"
  fi
  echo "  Recommended placement: immediately after the label, e.g.:"
  echo "    (T1/main - claude5 - sonnet - high) ${ITEM_EXAMPLE} <task text>"
  echo "  Honest-unknown form: item=?"
} >&2
exit 2
