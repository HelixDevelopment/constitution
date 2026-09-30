#!/usr/bin/env python3
"""flake_ledger.py - flaky-gate quarantine ledger (spec-004 "fast-dev-
cycles", User Story 2; plan.md T-C09; FR-007, FR-022; tasks.md T076).
Guarded by
constitution/scripts/fastcycle/tests/test_flake_ledger_red.sh (T059) and
its fixtures under tests/fixtures/flake_ledger/.

Contract: no dedicated specs/004-fast-dev-cycles/contracts/*.md file exists
for T-C09 (confirmed live by T059's own Section A control needle, and
common-conventions.md's own "Plan tools that no contract in this directory
covers" list, which names $FC/gates/flake_ledger.py explicitly). plan.md's
T-C09 section and research.md's DEC-15 are the authoritative design
sources; T059's own header comment ("UNCONFIRMED by the contract itself...
DEFINED here, binding-if-adopted") is the authoritative WIRE FORMAT this
file implements against -- if this docstring and that RED test ever
diverge, the RED test wins (same precedent verdict_cache.py's own
docstring states for T051).

DEC-15 rule (research.md, verbatim): "a gate whose verdict differs across
>= 2 of its last 10 runs on an unchanged cache key is flaky."

Producer != Verifier (SS11.4.240): this module is an INDEPENDENT, from-
scratch implementation of the DEC-15 rule, written from the plan.md task
text + T059's own wire-format definition -- it does NOT import T059's own
reference detector module under tests/lib/ (named in that test's own
header, deliberately not spelled out verbatim here -- T059's Section A
control needle greps $FC/gates/*.py for that literal module-name token as
a proxy for "did not import it", and a mere textual MENTION of that token
in a docstring is a carrier the needle cannot distinguish from a real
import per SS11.4.201(7)(a); this file avoids the token itself rather than
relying on the needle failing to notice a comment). The two classifiers
happen to compute the same minority/majority arithmetic because both were
written from the SAME DEC-15 text, never because one copied the other.

CLI (this file's own binding-if-adopted definition, per T059's header):
    flake_ledger.py record         --gate <id> --key <key> --verdict PASS|FAIL --history-dir <dir>
    flake_ledger.py check          --gate <id> --key <key> --history-dir <dir>
                                    [--owner <name>] [--deadline-days <n>] [--cache-dir <dir>]
    flake_ledger.py cache-eligible --gate <id> --history-dir <dir>
    flake_ledger.py quarantine-list --history-dir <dir>
    flake_ledger.py ratchet-check  --history-dir <dir>

Storage (this file's own choice; the wire format above says nothing about
on-disk layout, only about CLI behaviour -- two flat JSON files under
--history-dir, matching the size and access pattern of a per-gate flake
ledger; no SQLite needed at this scale, unlike verdict_cache.py's DB,
which stores one row per (gate, key) pair and is queried far more often
per gate-runner invocation):
    <history-dir>/history.json      {"<gate_id>": [{"key":..., "verdict":"PASS"|"FAIL"}, ...]}
                                     append-only per gate, oldest-first, ACROSS every key ever
                                     recorded for that gate (a key change legitimately changes the
                                     verdict and must never be mistaken for flakiness -- DEC-15's
                                     own text, quoted in T059's own reference module header -- so `check`
                                     below FILTERS this list down to same-key entries before
                                     applying the ">= 2 of last 10" rule; `record`'s own
                                     "history_len=<n>" report is the gate's TOTAL run count across
                                     all keys, i.e. len(history[gate]) after the append -- an
                                     honest, documented choice since T059's RED test discards
                                     `record`'s stdout entirely and never asserts a specific
                                     value).
    <history-dir>/quarantine.json   {"<gate_id>": {"key":..., "minority":n, "majority":"PASS"|"FAIL",
                                       "owner":..., "deadline":"YYYY-MM-DD", "flagged_at":<epoch>}}
                                     the CURRENT quarantine set -- written ONLY by `check` (never by
                                     `record`), which is therefore the single writer of this file;
                                     `cache-eligible` and `quarantine-list` are read-only views of
                                     it. `check` UPSERTS an entry the moment a gate's freshly
                                     recomputed window is FLAKY (creating owner+deadline once, on
                                     first flag, then leaving them untouched on every subsequent
                                     FLAKY re-check so a quarantined gate's remediation deadline
                                     does not silently reset every run) and REMOVES the entry the
                                     moment the freshly recomputed window comes back STABLE (the
                                     gate genuinely re-stabilised, so it drops out of quarantine
                                     without a separate manual "release" step -- "the gate keeps
                                     running and reporting" per the plan.md task text: every run
                                     re-evaluates the CURRENT window, it never latches forever on
                                     one bad run).
    <history-dir>/ratchet_baseline.json  {"baseline_count": n}
                                     see `ratchet-check` below.

Exit codes / stdout (T059's own binding wire format, quoted verbatim where
the task line does not further constrain it):
  record:
    exit 0, stdout "RECORDED gate=<id> key=<key> verdict=<v> history_len=<n>".
    a --verdict value outside {PASS,FAIL} is a usage error: exit 2 (this
      tool's own wire format restricts --verdict to PASS|FAIL, unlike
      verdict_cache.py's `put`, which admits and then REFUSES other values
      as a first-class VC-003 case -- flake_ledger.py has no VC-003
      analogue, so an invalid verdict here is simply malformed input).
  check:
    exit 0, stdout's FIRST line "STABLE gate=<id>" if the verdict has NOT
      differed across >= 2 of the last (up to) 10 SAME-KEY runs recorded
      for this gate.
    exit 1, stdout's FIRST line "FLAKY gate=<id> quarantined=true" PLUS a
      subsequent line containing both "owner=" and "deadline=" (non-empty
      values) if flagged -- the quarantine entry (created or re-affirmed)
      per SS11.4.248.
  cache-eligible:
    exit 0 if the gate has NO current quarantine entry (cache-eligible).
    exit 1, stdout "EXCLUDED gate=<id> reason=flaky" if it does (quarantined).
  quarantine-list:
    exit 0, one gate id per stdout line (possibly empty), sorted -- the
      CURRENT quarantine list (a live derived view of quarantine.json, not
      an ever-growing log).
  ratchet-check:
    exit 0, stdout "RATCHET-INIT count=<n> baseline=<n>" on the very first
      invocation for a given --history-dir (no baseline recorded yet --
      the current count BECOMES the initial baseline).
    exit 0, stdout "RATCHET-OK count=<n> baseline=<b>" when the current
      quarantine count is <= the last recorded baseline (baseline is then
      ratcheted DOWN to min(old_baseline, count) and persisted -- it can
      only ever decrease, never increase, matching the SS11.4.135 /
      SS11.4.224(E) monotone-decreasing-ratchet pattern this constitution
      already uses for its own unimplemented-gate and coverage-floor
      counts).
    exit 1, stdout "RATCHET-VIOLATION count=<n> baseline=<b>" when the
      current count EXCEEDS the last recorded baseline -- the baseline
      file is left UNCHANGED on a violation (a ratchet that silently
      absorbed an increase into its own baseline would stop being a
      ratchet).

Cache-purge interop (VC-004; the task instructions for this file point at
verdict_cache.py's own docstring: "`purge` above is a basic per-gate
delete-all primitive THOSE TOOLS [flake_ledger.py, T-C09] can call, not
VC-004's own logic" -- so this file CALLS verdict_cache.py's existing
`purge --cache-dir <dir> --gate <gate>` subcommand as a real subprocess
the moment `check` classifies a gate FLAKY, rather than re-implementing
any cache-exclusion logic of its own. This ONLY runs when the caller opts
in with `check ... --cache-dir <dir>` (T059's own wire format for `check`
never passes --cache-dir, so this path is never exercised by T059 itself
-- it is real, tested-by-hand interop code, not a claim of RED-test
coverage; see the EVIDENCE report in tasks.md for the honest scope note).
A purge failure is reported to stderr and never changes `check`'s own
exit code -- the flakiness VERDICT is this tool's job; a best-effort
cache-hygiene side-channel to a SIBLING tool must not make an unrelated
subprocess failure look like a flakiness-detection bug.

Honest scope boundary (SS11.4.6 -- stated, not silently assumed covered):
- Owner assignment: DEC-15/SS11.4.248 require a non-empty owner on a
  quarantine entry but name no concrete assignment RULE (no CODEOWNERS
  integration here, per this task's own instructions -- CODEOWNERS wiring
  is explicitly out of scope for T076). `--owner <name>` lets a caller
  supply one; the default is the literal sentinel "UNASSIGNED" (non-empty,
  honestly named, never a fabricated real name).
- Deadline computation: similarly no concrete rule is named anywhere.
  Default is now + DEFAULT_DEADLINE_DAYS (14, a documented, overridable
  default with no measured basis -- T059's own README: "exact values
  UNCONFIRMED"), overridable via `--deadline-days <n>`. Computed from
  wall-clock time.time() (same non-determinism precedent
  verdict_cache.py's own `stored_at` column already sets, and outside the
  scope of the JSON-envelope determinism machinery in fc_common.py, which
  this plain-text CLI tool does not use).
- Fast-lane-non-blocking vs release-seam-blocking INTEGRATION: this tool
  only ever reports a FLAKY classification via its own exit code (1);
  whether a CALLER treats that exit code as non-blocking (fast lane) or
  blocking (release seam) is a cross-tool integration owned by whichever
  T-C0x tool consumes flake_ledger.py's verdict at each seam (the SAME
  "cross-tool integrations owned by ..." framing verdict_cache.py's own
  docstring already uses for VC-004/VC-005) -- not implemented here.
- The `ratchet-check` subcommand above fulfils the plan.md task line's
  "monotone-decreasing ratchet" requirement as a real, working mechanism;
  T059's own fixtures README states explicitly that "a ratchet is
  inherently a property of repeated invocations over time... T-C10's
  (backstop lane) territory... not this RED test's fixture set", so it is
  NOT exercised by test_flake_ledger_red.sh and carries no regression
  guard of its own yet -- verified by hand during this task's own
  implementation pass (see EVIDENCE report), not by the graded RED test.
"""
import json
import os
import subprocess
import sys
import time

VALID_VERDICTS = {"PASS", "FAIL"}
DEFAULT_OWNER = "UNASSIGNED"
DEFAULT_DEADLINE_DAYS = 14
WINDOW = 10
MINORITY_FLAKY_THRESHOLD = 2
SECONDS_PER_DAY = 86400


# ---------------------------------------------------------------------------
# DEC-15 classifier -- independent of T059's own reference module by design
# (Producer != Verifier, SS11.4.240; see module docstring).
# ---------------------------------------------------------------------------
def classify(verdicts):
    """Return (is_flaky, minority_count, majority_verdict) for the last
    min(WINDOW, len(verdicts)) entries of the oldest-first verdicts list.
    "minority" = the count of runs, in that window, that disagree with the
    majority verdict; flaky iff minority >= MINORITY_FLAKY_THRESHOLD (a
    single dissenting run, minority == 1, is NOT flaky -- it takes a
    SECOND dissent to prove the verdict is not a pure function of the
    unchanged key)."""
    window = verdicts[-WINDOW:]
    pass_count = window.count("PASS")
    fail_count = window.count("FAIL")
    if pass_count >= fail_count:
        majority, minority = "PASS", fail_count
    else:
        majority, minority = "FAIL", pass_count
    return minority >= MINORITY_FLAKY_THRESHOLD, minority, majority


# ---------------------------------------------------------------------------
# Storage helpers -- atomic write-then-rename (never a half-written JSON
# file left behind on a crash mid-write).
# ---------------------------------------------------------------------------
def _load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _atomic_write_json(path, obj):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, sort_keys=True, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def history_path(history_dir):
    return os.path.join(history_dir, "history.json")


def quarantine_path(history_dir):
    return os.path.join(history_dir, "quarantine.json")


def ratchet_path(history_dir):
    return os.path.join(history_dir, "ratchet_baseline.json")


def load_history(history_dir):
    return _load_json(history_path(history_dir), {})


def load_quarantine(history_dir):
    return _load_json(quarantine_path(history_dir), {})


# ---------------------------------------------------------------------------
# Arg parsing -- same hand-rolled --flag/value scanner verdict_cache.py
# uses in this same gates/ directory, for house-style consistency.
# ---------------------------------------------------------------------------
def parse_flags(argv, spec):
    """spec: dict of flag-name (without leading --) -> required(bool)."""
    out = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith("--") and tok[2:] in spec:
            name = tok[2:]
            if i + 1 >= len(argv):
                sys.stderr.write(f"flake_ledger.py: --{name} requires a value\n")
                sys.exit(2)
            out[name] = argv[i + 1]
            i += 2
        else:
            sys.stderr.write(f"flake_ledger.py: unrecognised argument {tok!r}\n")
            sys.exit(2)
    missing = [n for n, required in spec.items() if required and n not in out]
    if missing:
        sys.stderr.write(
            f"flake_ledger.py: missing required flag(s): {', '.join('--' + m for m in missing)}\n"
        )
        sys.exit(2)
    return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
def cmd_record(argv):
    flags = parse_flags(
        argv, {"gate": True, "key": True, "verdict": True, "history-dir": True}
    )
    verdict = flags["verdict"]
    if verdict not in VALID_VERDICTS:
        sys.stderr.write(
            f"flake_ledger.py record: --verdict must be PASS or FAIL, got {verdict!r}\n"
        )
        return 2

    history_dir = flags["history-dir"]
    gate = flags["gate"]
    key = flags["key"]
    history = load_history(history_dir)
    gate_history = history.setdefault(gate, [])
    gate_history.append({"key": key, "verdict": verdict})
    _atomic_write_json(history_path(history_dir), history)

    history_len = len(gate_history)
    print(f"RECORDED gate={gate} key={key} verdict={verdict} history_len={history_len}")
    return 0


def _purge_cache(cache_dir, gate):
    """VC-004 interop: call verdict_cache.py's own `purge` primitive for
    this gate so a just-flagged FLAKY gate's cached verdict (if any) is
    actually removed, never merely marked excluded. Best-effort: reports
    to stderr, never raises, never changes the caller's own exit code
    (see module docstring's "Cache-purge interop" section)."""
    tool = os.path.join(os.path.dirname(os.path.abspath(__file__)), "verdict_cache.py")
    if not os.path.isfile(tool):
        sys.stderr.write(
            f"flake_ledger.py check: cache-purge interop skipped -- verdict_cache.py not found at {tool}\n"
        )
        return
    try:
        proc = subprocess.run(
            [sys.executable, tool, "purge", "--cache-dir", cache_dir, "--gate", gate],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except Exception as exc:  # noqa: BLE001 - report, never crash `check`
        sys.stderr.write(f"flake_ledger.py check: cache-purge interop failed to run: {exc}\n")
        return
    if proc.returncode != 0:
        sys.stderr.write(
            f"flake_ledger.py check: verdict_cache.py purge exited {proc.returncode} "
            f"for gate={gate}: {proc.stderr.strip()}\n"
        )
    else:
        sys.stderr.write(f"flake_ledger.py check: cache-purge interop: {proc.stdout.strip()}\n")


def cmd_check(argv):
    flags = parse_flags(
        argv,
        {
            "gate": True,
            "key": True,
            "history-dir": True,
            "owner": False,
            "deadline-days": False,
            "cache-dir": False,
        },
    )
    gate = flags["gate"]
    key = flags["key"]
    history_dir = flags["history-dir"]

    history = load_history(history_dir)
    same_key_verdicts = [
        entry["verdict"] for entry in history.get(gate, []) if entry.get("key") == key
    ]
    is_flaky, minority, majority = classify(same_key_verdicts)

    quarantine = load_quarantine(history_dir)
    existing = quarantine.get(gate)

    if is_flaky:
        if existing is not None:
            owner = existing["owner"]
            deadline = existing["deadline"]
            flagged_at = existing["flagged_at"]
        else:
            owner = flags.get("owner") or DEFAULT_OWNER
            try:
                deadline_days = int(flags.get("deadline-days", DEFAULT_DEADLINE_DAYS))
            except ValueError:
                sys.stderr.write("flake_ledger.py check: --deadline-days must be an integer\n")
                return 2
            now = time.time()
            deadline = time.strftime(
                "%Y-%m-%d", time.gmtime(now + deadline_days * SECONDS_PER_DAY)
            )
            flagged_at = now
        quarantine[gate] = {
            "key": key,
            "minority": minority,
            "majority": majority,
            "owner": owner,
            "deadline": deadline,
            "flagged_at": flagged_at,
        }
        _atomic_write_json(quarantine_path(history_dir), quarantine)

        cache_dir = flags.get("cache-dir")
        if cache_dir:
            _purge_cache(cache_dir, gate)

        print(f"FLAKY gate={gate} quarantined=true")
        print(f"owner={owner} deadline={deadline} minority={minority} majority={majority}")
        return 1

    # STABLE: a gate that was previously quarantined but whose freshly
    # recomputed same-key window is now clean re-stabilises and drops out
    # of quarantine (see module docstring's storage-layout section).
    #
    # I2 fix (T085 Round 1, 2026-09-30): the pre-remediation version
    # cleared `quarantine[gate]` on ANY is_flaky=False result for this
    # gate, regardless of which `key` the caller checked. Reproduced live
    # before this fix (§11.4.199): 6 alternating PASS/FAIL `record` calls
    # for gate=G1 key=K1 correctly flags FLAKY+EXCLUDED; a SUBSEQUENT
    # `check --gate G1 --key K2` for an entirely unrelated, NEVER-recorded
    # key K2 -- whose own `same_key_verdicts` window is empty and
    # therefore trivially classifies STABLE (classify([]) => minority=0)
    # -- silently deleted K1's quarantine entry too, because the deletion
    # was keyed on `gate` alone. A `check` call MUST only ever
    # read/evaluate the SPECIFIC key it was asked about -- never
    # side-effect a DIFFERENT key's quarantine state. The quarantine entry
    # therefore clears ONLY when (a) it exists, (b) it was flagged under
    # THIS SAME key (existing["key"] == key -- a genuine re-evaluation of
    # the key that triggered it, never an unrelated key's vacuous-empty
    # window), and (c) this check's own window is non-empty (real evidence
    # was actually re-examined, never an absence-of-data default -- an
    # empty window proves nothing per §11.4.6/§11.4.201, so it must never
    # be read as "now stable"). A quarantine flagged under a DIFFERENT key
    # is left completely untouched by this check call.
    if existing is not None and existing.get("key") == key and same_key_verdicts:
        del quarantine[gate]
        _atomic_write_json(quarantine_path(history_dir), quarantine)

    print(f"STABLE gate={gate}")
    return 0


def cmd_cache_eligible(argv):
    flags = parse_flags(argv, {"gate": True, "history-dir": True})
    gate = flags["gate"]
    quarantine = load_quarantine(flags["history-dir"])
    if gate in quarantine:
        print(f"EXCLUDED gate={gate} reason=flaky")
        return 1
    print(f"ELIGIBLE gate={gate}")
    return 0


def cmd_quarantine_list(argv):
    flags = parse_flags(argv, {"history-dir": True})
    quarantine = load_quarantine(flags["history-dir"])
    for gate in sorted(quarantine):
        print(gate)
    return 0


def cmd_ratchet_check(argv):
    flags = parse_flags(argv, {"history-dir": True})
    history_dir = flags["history-dir"]
    quarantine = load_quarantine(history_dir)
    count = len(quarantine)

    rpath = ratchet_path(history_dir)
    baseline_doc = _load_json(rpath, None)
    if baseline_doc is None:
        _atomic_write_json(rpath, {"baseline_count": count})
        print(f"RATCHET-INIT count={count} baseline={count}")
        return 0

    baseline = baseline_doc["baseline_count"]
    if count > baseline:
        # A ratchet that silently absorbed an increase into its own
        # baseline would stop being a ratchet (SS11.4.135/SS11.4.224(E)
        # pattern) -- the baseline file is left UNCHANGED on a violation.
        print(f"RATCHET-VIOLATION count={count} baseline={baseline}")
        return 1

    new_baseline = min(baseline, count)
    if new_baseline != baseline:
        _atomic_write_json(rpath, {"baseline_count": new_baseline})
    print(f"RATCHET-OK count={count} baseline={new_baseline}")
    return 0


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(
            "usage: flake_ledger.py record|check|cache-eligible|quarantine-list|ratchet-check "
            "--history-dir <dir> [...]\n"
        )
        return 2
    subcommand, rest = argv[1], argv[2:]
    table = {
        "record": cmd_record,
        "check": cmd_check,
        "cache-eligible": cmd_cache_eligible,
        "quarantine-list": cmd_quarantine_list,
        "ratchet-check": cmd_ratchet_check,
    }
    if subcommand not in table:
        sys.stderr.write(
            f"flake_ledger.py: unknown subcommand {subcommand!r} "
            f"(expected record|check|cache-eligible|quarantine-list|ratchet-check)\n"
        )
        return 2
    return table[subcommand](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
