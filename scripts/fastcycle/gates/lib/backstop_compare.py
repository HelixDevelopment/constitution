#!/usr/bin/env python3
"""backstop_compare.py -- DEC-17 backstop drift detector + force-full
write-back (SpecKit-004 "fast-dev-cycles", User Story 2; plan.md T-C10;
tasks.md T077; FR-006, FR-022, SC-003).

Guarded by
constitution/scripts/fastcycle/tests/test_backstop_red.sh (T060), per
fixtures/backstop/README.md's own "invented, binding-if-adopted" CLI wire
format (no specs/004-fast-dev-cycles/contracts/*.md file exists for T-C10;
confirmed absent by a real directory listing before writing this file,
constitution SS11.4.6).

DEC-17 rule (research.md line 654 / plan.md T-C10 Work line, restated in
fixtures/backstop/README.md): the full backstop lane (every gate,
`--no-cache`, no `--affected` narrowing) is compared against the fast
lane's verdicts for the SAME change; any gate the full lane FAILed but
the fast lane did not ALSO report FAIL for -- whether the gate is entirely
absent from the fast lane's results (a "selection hole") or present with a
different verdict (PASS/SKIP/BLIND) -- is a **drift**: a release blocker
that MUST block (exit 1). affected-set-and-verdict-cache.md's VC-005
clause states the special case this generalises: "any gate PASS in fast
lane but FAIL in full lane is a release blocker".

Both lanes are read as `verdicts/v1`-shaped documents -- the SCHEMA
affected-set-and-verdict-cache.md's "Output schemas" section already
defines (`{change_id, results: [{gate_id, verdict, source, evidence,
duration_ms}], summary}`), reused here unchanged rather than inventing a
new shape for backstop.sh (constitution SS11.4.6 -- do not invent when
something adjacent already exists).

Producer != Verifier (constitution SS11.4.240): this file is an
INDEPENDENT, from-scratch implementation. It does NOT import, and was not
derived by reverse-engineering,
constitution/scripts/fastcycle/tests/lib/dec17_drift_ref.py (T060's own
RED-test reference module, used ONLY to prove that RED test's fixtures are
non-vacuous) -- both implement the SAME written DEC-17 rule independently,
matching this project's own established house convention (see
verdict_cache.py's identical framing re: dec07_key_ref.py). T060's RED
test Section A control needle #4 mechanically confirms nothing under
gates/ imports either of its reference modules.

CLI (per fixtures/backstop/README.md, this RED test's own binding wire
format definition):

    backstop_compare.py --fast <fast_verdicts.json> --full <full_verdicts.json>
        --out <drift.json> [--apply --map <gate_map.json>]
        [--determinism-check]

Exit codes (C-001, contracts/common-conventions.md; T085 Round 2 I-R2-6
remediation, 2026-09-30 -- the Round 1 codes below directly contradicted
C-001's own table, which reserves 3 for "self-test failed, NO result file"
and 4 for BLIND/"partial output flagged"; the mapping is now aligned):
0 = NO_DRIFT (stdout first line "NO_DRIFT" -- every gate's full-lane
verdict is either PASS, or FAIL matched by fast, with NOTHING left
unverified, AND the full lane produced at least one real result);
1 = >=1 drift found (stdout one "DRIFT gate=<id> fast=<verdict|ABSENT>
full=FAIL" line per drifting gate, sorted by gate_id, then
"DRIFT_COUNT=<n>", then any UNVERIFIED lines + "UNVERIFIED_COUNT=<n>" --
exit 1 IS the block, C-001 code 1 = "a finding ... release blocker");
2 = usage/config error (missing/unreadable --fast/--full/--map, --apply
without --map, OR a change_id that is UNCONFIRMED-equal between --fast
and --full -- both present and different, OR EITHER side missing its own
change_id entirely (I-R2-6: Round 1 only caught the both-present-and-
different case, silently comparing when one side's change_id was simply
absent) -- comparing verdicts whose identity cannot be confirmed equal is
meaningless, so no drift computation is attempted at all and, per C-001's
own "error message only" code-2 contract, NOTHING is written to --out;
stdout's "CHANGE_ID_MISMATCH fast=<id> full=<id>" line moves to STDERR
accordingly); 3 = self-test failed (unused by this tool today -- reserved
per C-001, never repurposed); 4 = BLIND/UNVERIFIED (I7 fix, T085 Round 1,
now correctly mapped to C-001's own BLIND code: zero genuine drifts, but
either >=1 gate's full-lane verdict is SKIP, BLIND, or entirely absent
from the full lane's own results, OR the full lane produced ZERO results
at all (I-R2-6: Round 1 silently reported an empty full lane as a clean
NO_DRIFT/exit-0 -- reproduced live before this fix) -- the full lane
never established a clean verdict, so this MUST NOT be reported as
NO_DRIFT; stdout one "UNVERIFIED gate=<id> fast=<verdict|ABSENT>
full=<verdict|ABSENT>" line per such gate, then "UNVERIFIED_COUNT=<n>").
--out always writes a `backstop_drift/v1` document (schema, change_id,
drift[], drift_count, body_hash, run_meta per C-002) for every exit code
EXCEPT 2's change_id-mismatch branch, which writes nothing (C-001's own
"error message only" contract for usage/config errors).

--apply --map <gate_map.json> (DEC-17/AS-010a force-full write-back,
data-model.md Section 3's `force_full` bool field -- "set by the backstop
lane on a drift (DEC-17, T-C10) until the gate is re-traced; a force_full
gate is always an affected-set member"): when >=1 drift is found AND
--apply --map are both given, every drifting gate_id present in the map's
`gates` dict (the SAME `{"gates": {"<gate_id>": {...}}}` shape
affected_set.py already reads/writes, constitution SS11.4.6 -- reused, not
invented) has its entry's `force_full` field set to `true`; a drifting
gate_id NOT present in the map is reported, never silently invented into
it. C-006 safety: any write is behind the explicit --apply flag and takes
a hardlinked backup first (SS9.2 -- near-instant, zero extra disk; falls
back to a real copy across filesystem boundaries).

HONEST SCOPE (Producer != Verifier, SS11.4.240; fixtures/backstop/README.md
"What this RED test does NOT cover"): affected_set.py (T069, already
landed) does not yet READ the `force_full` field this --apply write-back
sets -- consuming it to force affected-set membership is T-C03's own
future follow-up, not this file's job. The release-tag-time / nightly-on-
main / gate-engine-change scheduling triggers DEC-17 names for WHEN the
full lane should run are documented in backstop.sh's own usage text, not
implemented as an automated scheduler here (no fixture or spec defines
one; inventing an unverified scheduler would itself be a SS11.4.6 guess).
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import time

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_BLIND = 4
# T085 Round 2 I-R2-6: the pre-fix constants below (EXIT_UNVERIFIED=3,
# EXIT_CHANGE_ID_MISMATCH=4) directly CONTRADICTED this project's own
# C-001 exit-code contract (contracts/common-conventions.md), which
# reserves 3 for "self-test failed -- NO result file written" and 4 for
# BLIND ("a required input could not be read ... no honest verdict is
# possible; partial output flagged BLIND"). UNVERIFIED -- a genuinely
# written, partial verdict document flagging >=1 gate as unestablished --
# is EXACTLY C-001's BLIND state and now maps to 4, matching it. A
# change_id mismatch between --fast/--full is a CALLER input-compatibility
# problem detected before any comparison is attempted (no honest drift
# computation is even possible) -- it now maps to EXIT_USAGE=2 ("bad args
# ... unparseable input") and, per C-001's row-2 "error message only"
# contract, writes NOTHING to --out (the pre-fix version always wrote a
# result document regardless).
EXIT_UNVERIFIED = EXIT_BLIND
EXIT_CHANGE_ID_MISMATCH = EXIT_USAGE

SCHEMA = "backstop_drift/v1"


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def load_verdicts(path):
    """Reads a verdicts/v1 document; returns (change_id, {gate_id: verdict})."""
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    results = {}
    for r in doc.get("results", []):
        results[r["gate_id"]] = r.get("verdict")
    return doc.get("change_id"), results


def compute_drift(fast, full):
    """DEC-17: a gate drifts iff the full lane's verdict is FAIL and the
    fast lane did NOT also report FAIL for the same gate_id -- covering
    BOTH the "absent from fast" (selection hole) and "present but wrong
    verdict" sub-cases. Sorted by gate_id (determinism, C-003).

    I7 fix (T085 Round 1, 2026-09-30): the pre-remediation version iterated
    ONLY `full.items()` and skipped any gate whose full_verdict was not the
    literal string "FAIL" -- so a full-lane verdict of SKIP, BLIND, or a
    gate ENTIRELY ABSENT from the full lane's own results (never attempted
    at all) was silently treated exactly like a clean PASS: folded into
    "no drift", the SAME reported state as "the full lane genuinely
    verified this gate clean". Reproduced live before this fix
    (§11.4.199): full_verdicts.json declaring GATE-X verdict=BLIND (the
    full lane could not determine a verdict at all) produced NO_DRIFT,
    identical to a run where GATE-X was genuinely re-verified PASS -- the
    two are NOT the same claim and must not share one output state. This
    function now returns (drifts, unverified): `drifts` is UNCHANGED
    DEC-17 logic for full_verdict=="FAIL"; `unverified` is every OTHER
    gate (in the UNION of fast's and full's own gate ids, so a gate the
    full lane never even attempted -- absent from its results entirely --
    is included too) whose full_verdict is not literally "PASS" or "FAIL"
    (i.e. SKIP, BLIND, or None/absent) -- reported honestly as a THIRD
    state the caller must never conflate with NO_DRIFT."""
    all_gate_ids = sorted(set(fast) | set(full))
    drifts = []
    unverified = []
    for gate_id in all_gate_ids:
        full_verdict = full.get(gate_id)
        fast_verdict = fast.get(gate_id)
        if full_verdict == "FAIL":
            if fast_verdict != "FAIL":
                drifts.append({
                    "gate_id": gate_id,
                    "fast_verdict": fast_verdict,
                    "full_verdict": "FAIL",
                })
            continue
        if full_verdict != "PASS":
            unverified.append({
                "gate_id": gate_id,
                "fast_verdict": fast_verdict,
                "full_verdict": full_verdict,  # None = entirely absent from full's results
            })
    return sorted(drifts, key=lambda d: d["gate_id"]), sorted(unverified, key=lambda d: d["gate_id"])


def build_result(fast_path, full_path):
    fast_change_id, fast = load_verdicts(fast_path)
    full_change_id, full = load_verdicts(full_path)

    # I7 fix + T085 Round 2 I-R2-6: an explicit change_id match assertion
    # (§11.4.201's own "never checks change_id" finding) -- comparing two
    # verdict documents for DIFFERENT (or UNKNOWABLY different) changes is
    # meaningless, so this refuses to compute a drift verdict at all
    # whenever the two lanes' identity cannot be positively confirmed
    # equal: (a) both present and different, OR (b) EITHER side is
    # entirely missing its own change_id. Round 1's version required BOTH
    # to be present before flagging a mismatch, so a --full document with
    # NO change_id at all silently bypassed this check and was compared
    # against --fast as if they were confirmed the same change (reproduced
    # live before this fix: a full lane missing change_id entirely, run
    # against a fast lane with zero drifting gates, produced a clean
    # rc=0 NO_DRIFT with no indication the comparison's own premise --
    # "these two lanes are the same change" -- was never actually
    # verified).
    change_id_unconfirmed = (
        fast_change_id is None
        or full_change_id is None
        or fast_change_id != full_change_id
    )
    if change_id_unconfirmed:
        result = {
            "schema": SCHEMA,
            "change_id": None,
            "fast_change_id": fast_change_id,
            "full_change_id": full_change_id,
            "drift": [],
            "drift_count": 0,
            "unverified": [],
            "unverified_count": 0,
            "change_id_mismatch": True,
        }
        result["body_hash"] = body_hash(result)
        return result, EXIT_CHANGE_ID_MISMATCH

    drifts, unverified = compute_drift(fast, full)
    # T085 Round 2 I-R2-6: a full lane that produced ZERO results (ran no
    # gates at all) previously fell through this function's own logic to
    # a vacuous, clean NO_DRIFT/exit-0 (both `drifts` and the per-gate
    # `unverified` list are empty when `all_gate_ids` itself is empty,
    # e.g. two entirely-empty lanes) -- reproduced live before this fix.
    # An empty full lane never established ANY verdict, clean or
    # otherwise, so it is NEVER reported as the clean/verified NO_DRIFT
    # state -- it is UNVERIFIED (the SAME "nothing was proven right"
    # honesty the per-gate unverified list already enforces, generalised
    # to the whole-lane case the per-gate loop cannot see because there is
    # nothing in `full` to iterate over).
    full_lane_empty = not full
    result = {
        "schema": SCHEMA,
        "change_id": full_change_id if full_change_id is not None else fast_change_id,
        "drift": drifts,
        "drift_count": len(drifts),
        "unverified": unverified,
        "unverified_count": len(unverified),
        "change_id_mismatch": False,
        "full_lane_empty": full_lane_empty,
    }
    result["body_hash"] = body_hash(result)
    if drifts:
        exit_code = EXIT_FINDING
    elif unverified or full_lane_empty:
        # I7 fix: NEVER report NO_DRIFT (the clean/verified state) while
        # any gate's full-lane verdict is genuinely unestablished -- a
        # distinct exit code so a caller cannot mistake "nothing was
        # proven wrong" for "everything was proven right". T085 Round 2
        # I-R2-6 extends this to the whole-lane-empty case above.
        exit_code = EXIT_UNVERIFIED
    else:
        exit_code = EXIT_OK
    return result, exit_code


def apply_force_full(map_path, drifting_gate_ids):
    """Sets gates.<gate_id>.force_full = true for every drifting gate id
    present in the map (data-model.md Section 3's `force_full` field,
    read by affected_set.py's future consumer). C-006: a hardlinked
    backup (SS9.2) is taken BEFORE any write; falls back to a real copy
    if hardlinking is unsupported (e.g. across filesystem boundaries).
    Returns (updated_ids, unknown_ids, backup_path_or_None)."""
    with open(map_path, "r", encoding="utf-8") as fh:
        gate_map = json.load(fh)
    gates = gate_map.setdefault("gates", {})

    updated = []
    unknown = []
    for gid in drifting_gate_ids:
        if gid in gates:
            gates[gid]["force_full"] = True
            updated.append(gid)
        else:
            unknown.append(gid)

    if not updated:
        return updated, unknown, None

    backup_path = "%s.bak-%d-%d" % (map_path, int(time.time()), os.getpid())
    try:
        os.link(map_path, backup_path)
    except OSError:
        shutil.copy2(map_path, backup_path)

    with open(map_path, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(gate_map))
        fh.write("\n")

    return updated, unknown, backup_path


def build_parser():
    p = argparse.ArgumentParser(prog="backstop_compare.py")
    p.add_argument("--fast", required=True)
    p.add_argument("--full", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--map")
    p.add_argument("--determinism-check", action="store_true")
    return p


def main(argv):
    a = build_parser().parse_args(argv[1:])

    if a.apply and not a.map:
        sys.stderr.write("backstop_compare: --apply requires --map <gate_map.json>\n")
        return EXIT_USAGE
    if a.map and not a.apply:
        sys.stderr.write(
            "backstop_compare: --map given without --apply -- ignored (C-006: "
            "writes are behind an explicit --apply flag; pass --apply to write)\n"
        )

    for label, path in (("--fast", a.fast), ("--full", a.full)):
        if not os.path.isfile(path):
            sys.stderr.write("backstop_compare: %s not found: %s\n" % (label, path))
            return EXIT_USAGE
    if a.apply and not os.path.isfile(a.map):
        sys.stderr.write("backstop_compare: --map not found: %s\n" % a.map)
        return EXIT_USAGE

    try:
        result, exit_code = build_result(a.fast, a.full)
    except (OSError, json.JSONDecodeError, KeyError) as exc:
        sys.stderr.write("backstop_compare: cannot read/parse --fast/--full: %s\n" % exc)
        return EXIT_USAGE

    if a.determinism_check:
        try:
            result2, _ = build_result(a.fast, a.full)
        except (OSError, json.JSONDecodeError, KeyError) as exc:
            sys.stderr.write("backstop_compare: --determinism-check second run failed: %s\n" % exc)
            return EXIT_USAGE
        if result["body_hash"] != result2["body_hash"]:
            sys.stderr.write(
                "backstop_compare: --determinism-check FAILED: two consecutive runs "
                "produced different bodies (%s != %s)\n" % (result["body_hash"], result2["body_hash"])
            )
            return EXIT_FINDING

    # T085 Round 2 I-R2-6: a change_id mismatch/unconfirmed-identity is a
    # CALLER input-compatibility problem (C-001 code 2, "error message
    # only") -- nothing is written to --out for it, and the diagnostic
    # goes to STDERR, never stdout (distinct from every other branch
    # below, which DOES always write --out regardless of exit code).
    if result.get("change_id_mismatch"):
        sys.stderr.write(
            "backstop_compare: change_id UNCONFIRMED-equal between --fast (%s) "
            "and --full (%s) -- refusing to compute a drift verdict for two "
            "lanes that cannot be confirmed to name the SAME change "
            "(T085 Round 2 I-R2-6)\n"
            % (result["fast_change_id"], result["full_change_id"])
        )
        print(
            "CHANGE_ID_MISMATCH fast=%s full=%s"
            % (result["fast_change_id"], result["full_change_id"]),
            file=sys.stderr,
        )
        return exit_code

    out_dir = os.path.dirname(os.path.abspath(a.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(result))
        fh.write("\n")

    if exit_code == EXIT_OK:
        print("NO_DRIFT")
    else:
        for d in result["drift"]:
            fast_label = d["fast_verdict"] if d["fast_verdict"] is not None else "ABSENT"
            print("DRIFT gate=%s fast=%s full=FAIL" % (d["gate_id"], fast_label))
        print("DRIFT_COUNT=%d" % result["drift_count"])
        for u in result["unverified"]:
            full_label = u["full_verdict"] if u["full_verdict"] is not None else "ABSENT"
            print("UNVERIFIED gate=%s fast=%s full=%s" % (
                u["gate_id"],
                u["fast_verdict"] if u["fast_verdict"] is not None else "ABSENT",
                full_label,
            ))
        print("UNVERIFIED_COUNT=%d" % result["unverified_count"])

    if a.apply and exit_code == EXIT_FINDING:
        drifting_ids = [d["gate_id"] for d in result["drift"]]
        updated, unknown, backup = apply_force_full(a.map, drifting_ids)
        if updated:
            print("APPLY: force_full=true set for %s (backup: %s)" % (", ".join(updated), backup))
        if unknown:
            print("APPLY: gate id(s) not present in %s, left unmarked: %s" % (a.map, ", ".join(unknown)))

    return exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
