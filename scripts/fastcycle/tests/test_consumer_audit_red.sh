#!/bin/sh
# =============================================================================
# T167 RED test (SpecKit-004 "fast-dev-cycles", Phase 10 / User Story 8;
# plan.md T-G04; FR-024, SC-010).
# =============================================================================
#
# Purpose: prove, BEFORE T-G04's `consumers/audit.py` implementation
# exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/consumers/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISM the real tool will rely on for CA-011's
#       "constitution pointer distance" measurement -- `git -C constitution
#       rev-list --count <gitlink>..HEAD` against a REAL, non-trivially-
#       behind local consumer checkout -- is genuinely sound on this host,
#       proven by a REAL git invocation in Section B (never merely assumed
#       present, per §11.4.273: "the path is part of the instrument"),
#       and re-measured LIVE (never hardcoded) so this file self-flips
#       GREEN without edits as the project's own history grows;
#   (C) once T-G04 lands, invoking the real tool against the 3-project
#       fixture `fixtures/consumer_audit/consumers_3.json` produces the
#       report-count (CA-010) and behind-count (CA-011) outcomes this
#       file's own live measurements predict, and never mutates the
#       audited checkouts (CA-012, read-only).
#
# Contract: specs/004-fast-dev-cycles/contracts/consumer-audit-and-migration.md
#   CA-010 (report count) .. CA-012 (read-only); common-conventions.md
#   (C-001..C-007). No new CLI contract is invented here -- the contract
#   file already fixes audit.py's invocation (`audit`/`summary`
#   subcommands), output shape and exit codes; this file exercises exactly
#   those.
#
# Task line (tasks.md T167, verbatim): "[P] [US8] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_consumer_audit_red.sh (count
# check: reports == enumerated projects; golden: a local consumer's
# behind-count equals `git -C constitution rev-list --count
# <gitlink>..HEAD`) (plan T-G04; FR-024, SC-010)".
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixture under fixtures/consumer_audit/consumers_3.json. It does NOT
# implement consumers/audit.py (T-G04/T171, a separate later task
# dispatched to its own reviewer), and never fabricates a tool-invocation
# result -- every scenario below is either (a) a real `git`/filesystem
# invocation this file performs itself (Section B, self-validating the
# underlying mechanism and its read-only-safety precondition), or (b) a
# real invocation of the (today, absent) audit.py tool, reported RED
# because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every Section C "tool invocation" check -- Section B's
#       self-checks of the git-rev-list MECHANISM are expected to PASS
#       today, since they exercise only git itself, not the absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
CONST_ROOT=$(cd "$FC/../.." && pwd)
REPO_ROOT=$(cd "$CONST_ROOT/.." && pwd)
TOOL="$FC/consumers/audit.py"
FIXDIR="$HERE/fixtures/consumer_audit"
CONSUMERS3="$FIXDIR/consumers_3.json"
GOLDEN_LOCAL_CHECKOUT="/mnt/track1/helix_ota"
EVDIR="$REPO_ROOT/qa-results/fastcycle/us8/red"
mkdir -p "$EVDIR" 2>/dev/null || true
FINGERPRINT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T167 RED: consumer audit (plan T-G04; FR-024, SC-010); candidate fingerprint=$FINGERPRINT =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-G04 has landed; Section C's real"
    echo "   invocation checks below are the functional tests to run"
else
    echo "RED: $TOOL is absent -- T-G04 (consumers/audit.py) has not landed"
    echo "     yet, confirming this file's own premise is real, not assumed"
fi

if [ -d "$FC/consumers" ]; then
    NON_GITKEEP=$(find "$FC/consumers" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/consumers/ genuinely holds nothing but"
        echo "   .gitkeep -- confirms audit.py is absent by DIRECTORY"
        echo "   CONTENT, not merely by the single-path check above"
    else
        echo "NOTE: $FC/consumers/ holds $NON_GITKEEP non-.gitkeep file(s)"
        echo "      already -- re-check whether T-G03/T-G04/T-G05 has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/consumers/ does not exist at all"
fi

if [ ! -f "$CONSUMERS3" ]; then
    bad "control needle FAILED: $CONSUMERS3 fixture is missing"
else
    ok "control needle: $CONSUMERS3 fixture is present"
fi

if [ ! -d "$GOLDEN_LOCAL_CHECKOUT/.git" ] && [ ! -f "$GOLDEN_LOCAL_CHECKOUT/.git" ]; then
    bad "control needle FAILED: $GOLDEN_LOCAL_CHECKOUT has no .git -- the"
    echo "   golden behind-count needle's real checkout is not present on"
    echo "   this host; re-derive GOLDEN_LOCAL_CHECKOUT before trusting"
    echo "   anything below"
else
    ok "control needle: $GOLDEN_LOCAL_CHECKOUT is genuinely checked out"
    echo "   on this host -- the golden behind-count needle has a real target"
fi

# =============================================================================
# Section B -- self-validation of the underlying `git rev-list --count`
# MECHANISM (§11.4.107(10)/§11.4.273), run LIVE against a REAL, non-
# trivially-behind local consumer -- BEFORE any claim is made about what
# the (absent) real audit.py tool should report. LIVE-RECOMPUTED, never
# hardcoded (house precedent: test_churn_rank_red.sh Section C), so this
# file self-flips GREEN without edits as history on either side advances.
# =============================================================================
if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- audit.py (a Python tool per plan.md Technical"
    echo "   Context) cannot run once implemented, and this file's JSON"
    echo "   parsing below also depends on it"
fi

GITLINK=""
BEHIND_LIVE=""
if [ -d "$GOLDEN_LOCAL_CHECKOUT/.git" ] || [ -f "$GOLDEN_LOCAL_CHECKOUT/.git" ]; then
    GITLINK=$(git -C "$GOLDEN_LOCAL_CHECKOUT" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
    if [ -z "$GITLINK" ]; then
        bad "B1 mechanism self-check FAILED: $GOLDEN_LOCAL_CHECKOUT has no"
        echo "   'constitution' gitlink entry at HEAD -- the golden needle's"
        echo "   premise (a real submodule pointer to measure) is false"
    else
        if ! git -C "$CONST_ROOT" cat-file -e "$GITLINK" 2>/dev/null; then
            bad "B1 mechanism self-check FAILED: gitlink $GITLINK from"
            echo "   $GOLDEN_LOCAL_CHECKOUT is not a commit reachable in this"
            echo "   host's constitution clone at $CONST_ROOT (fetch first)"
        else
            BEHIND_LIVE=$(git -C "$CONST_ROOT" rev-list --count "$GITLINK"..HEAD 2>&1)
            case "$BEHIND_LIVE" in
                ''|*[!0-9]*)
                    bad "B1 mechanism self-check FAILED: git rev-list --count"
                    echo "   did not produce an integer (got '$BEHIND_LIVE')"
                    BEHIND_LIVE=""
                    ;;
                *)
                    ok "B1 mechanism self-check: git -C constitution rev-list --count"
                    echo "   $GITLINK..HEAD genuinely and LIVE-computes to $BEHIND_LIVE"
                    echo "   on this host -- the CA-011 pointer-distance mechanism is"
                    echo "   proven sound, not merely assumed present, and this number"
                    echo "   is what Section C compares audit.py's report against"
                    ;;
            esac
        fi
    fi
else
    bad "B1 mechanism self-check FAILED: $GOLDEN_LOCAL_CHECKOUT is not a"
    echo "   real git checkout -- see the Section A control needle above"
fi

# CA-012 read-only precondition: capture a content fingerprint of the
# checkout's tracked tree NOW, compared again after Section C's audit
# invocation (whether or not the tool exists yet -- a genuinely useful,
# ongoing regression check, not merely a RED-today artefact).
CHECKOUT_FP_BEFORE=""
if [ -d "$GOLDEN_LOCAL_CHECKOUT/.git" ] || [ -f "$GOLDEN_LOCAL_CHECKOUT/.git" ]; then
    CHECKOUT_FP_BEFORE=$(git -C "$GOLDEN_LOCAL_CHECKOUT" rev-parse HEAD:constitution 2>/dev/null)-$(git -C "$GOLDEN_LOCAL_CHECKOUT" status --porcelain=v1 2>/dev/null | md5sum | awk '{print $1}')
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) audit.py tool.
# Every check here is a REAL command execution against contract-shaped
# args, so the moment T-G04 lands, these checks self-flip GREEN with no
# further edits to this file.
# =============================================================================
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CFG="$REPO_ROOT/config/fastcycle/fastcycle.yaml"
mkdir -p "$WORK/audits"
# A pre-existing stray file in --out, simulating a re-run without cleanup
# (a realistic directory-already-has-junk-in-it state). C1b below proves
# CA-010's "one report PER PROJECT" -- keyed by enumerated project_id, not
# merely a directory file count that a stray leftover (or a defect that
# skips one project while writing a duplicate of another) could satisfy
# by sheer coincidence (T169 mutation-3's target: "count reports by
# directory instead of by enumerated id").
echo '{"not_a_real_report": true}' > "$WORK/audits/__stray_leftover__.json"

run_tool() {
    if [ -f "$TOOL" ]; then
        python3 "$TOOL" "$@" 2>&1
        return $?
    fi
    echo "audit.py absent"
    return 127
}

# T177 Round 5 (round-4 I1/I3): a MIGRATED record now only counts when its
# cited verification reports EXIST and hash to the recorded content
# address, and it carries review_ref + backup_marker. mkrec.py writes such a
# record WITH REAL evidence files (or a deliberately broken variant, per
# --break), so every MIGRATED fixture below is genuinely verifiable --
# never a shape-only stand-in.
MKREC="$WORK/mkrec.py"
cat > "$MKREC" <<'PYEOF'
import argparse, hashlib, json, os
ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True)
ap.add_argument("--project", required=True)
ap.add_argument("--commit", default="c0ffee")
ap.add_argument("--overall1", default="CLEAN")
ap.add_argument("--overall2", default="CLEAN")
ap.add_argument("--hash1", default="h")
ap.add_argument("--hash2", default="h")
ap.add_argument("--break", dest="brk", default="",
                help="addr-of-path|missing-file|record-lies|no-review-ref|no-backup-marker|bad-backup-addr|relative-paths|foreign-commit|same-report-twice")
a = ap.parse_args()
base = a.out[:-len(".json")]
ver = []
for n, (ov, bh) in enumerate([(a.overall1, a.hash1), (a.overall2, a.hash2)], 1):
    rpath = "%s.verify%d.json" % (base, n)
    on_disk_overall = "NOT_CLEAN" if a.brk == "record-lies" else ov
    # T177 Round 6 I4: every genuine repo_verify.py report carries a
    # repos[] entry at path="." whose "head" is the root repo's own HEAD
    # commit -- these fixture reports carry the SAME shape, bound to
    # a.commit by default, so EVERY existing fixture (which does not
    # exercise this new check) continues to pass unmodified; --break
    # foreign-commit deliberately points it at a DIFFERENT, real-looking
    # commit to reproduce the reviewer's E6 cross-project-citation repro.
    report_head = a.commit
    if a.brk == "foreign-commit":
        report_head = "deadfeed" * 5
    raw = json.dumps({
        "schema": "verify-fixture/v1", "overall": on_disk_overall, "body_hash": bh,
        "repos": [{"path": ".", "head": report_head}],
    }).encode()
    with open(rpath, "wb") as fh:
        fh.write(raw)
    addr = "sha256:" + hashlib.sha256(raw).hexdigest()
    if a.brk == "addr-of-path":
        addr = "sha256:" + hashlib.sha256(rpath.encode()).hexdigest()
    cited = os.path.basename(rpath) if a.brk == "relative-paths" else rpath
    ver.append({"path": cited, "overall": ov, "body_hash": bh, "content_address": addr})
    if a.brk == "missing-file":
        os.remove(rpath)
# T177 Round 6 I4: --break same-report-twice reproduces the reviewer's E5
# repro -- both cited entries name the SAME path (verify1.json's own entry
# is duplicated; verify2.json still exists on disk but is never cited).
if a.brk == "same-report-twice":
    ver[1] = dict(ver[0])
rec = {"schema": "consumer-migration/v1", "project_id": a.project, "outcome": "MIGRATED",
       "data_change": "NONE", "commit": a.commit, "verification": ver,
       "review_ref": "fixture-review-id", "backup_marker": {"path": "/fixture/backup/git", "content_address": "sha256:" + "a" * 64}}
if a.brk == "no-review-ref":
    del rec["review_ref"]
if a.brk == "no-backup-marker":
    del rec["backup_marker"]
if a.brk == "bad-backup-addr":
    rec["backup_marker"]["content_address"] = "sha256:not-hex"
with open(a.out, "w") as fh:
    json.dump(rec, fh)
PYEOF

# --- C1: CA-010 report count -- one ConsumerAuditReport per project
C1_OUT=$(run_tool audit --config "$CFG" --consumers "$CONSUMERS3" --workdir "$WORK/cwork" --out "$WORK/audits/"); C1_RC=$?
NUM_PROJECTS=$(python3 -c "import json; print(len(json.load(open('$CONSUMERS3'))['projects']))" 2>/dev/null || echo 3)
NUM_REPORTS=$(find "$WORK/audits" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
if [ "$C1_RC" -eq 0 ] && [ "$NUM_REPORTS" -eq "$((NUM_PROJECTS + 1))" ]; then
    ok "C1 CA-010 report count: audit.py produced $NUM_PROJECTS real reports for $NUM_PROJECTS projects (plus the 1 pre-seeded stray file, untouched)"
else
    bad "C1 CA-010 report count: audit.py produced $NUM_REPORTS report(s) for $NUM_PROJECTS project(s) + 1 pre-seeded stray (rc=$C1_RC out=$C1_OUT)"
fi

# --- C1b: CA-010 by ENUMERATED ID, not directory count -- every project_id
# named in consumers_3.json has its OWN report whose content's own
# project_id field matches (a raw directory-file-count check cannot tell
# a correctly-keyed report from a mis-keyed one, or from a stray file that
# happens to keep the total count coincidentally right).
if [ "$C1_RC" -eq 0 ]; then
    MISSING=$(python3 -c "
import glob, json
expected = {p['project_id'] for p in json.load(open('$CONSUMERS3'))['projects']}
found = set()
for f in glob.glob('$WORK/audits/*.json'):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    pid = d.get('project_id')
    if pid:
        found.add(pid)
missing = expected - found
print(','.join(sorted(missing)))
" 2>/dev/null)
    if [ -z "$MISSING" ]; then
        ok "C1b CA-010 by enumerated id: every one of the 3 known project_id(s) in consumers_3.json has its own matching audit report"
    else
        bad "C1b CA-010 by enumerated id: project_id(s) missing a matching report: $MISSING"
    fi
else
    bad "C1b CA-010 by enumerated id: cannot check -- C1 invocation failed (rc=$C1_RC)"
fi

# --- C2: golden -- behind_head_by for HelixDevelopment/ota's report equals
# the LIVE-recomputed rev-list count from Section B, never a hardcoded
# number (self-flips as history on either side advances).
if [ -n "$BEHIND_LIVE" ] && [ "$C1_RC" -eq 0 ]; then
    REPORTED_BEHIND=$(python3 -c "
import json, glob
for f in glob.glob('$WORK/audits/*.json'):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if d.get('project_id') == 'HelixDevelopment/ota':
        print(d.get('behind_head_by', ''))
        break
" 2>/dev/null)
    if [ "$REPORTED_BEHIND" = "$BEHIND_LIVE" ]; then
        ok "C2 golden: audit.py reports behind_head_by=$REPORTED_BEHIND for HelixDevelopment/ota, matching the live-recomputed $BEHIND_LIVE"
    else
        bad "C2 golden: audit.py reported behind_head_by='$REPORTED_BEHIND' for HelixDevelopment/ota; live-recomputed value is $BEHIND_LIVE"
    fi
else
    bad "C2 golden: cannot compare -- either Section B's live measurement or the C1 invocation failed"
fi

# --- C3: CA-012 read-only -- the audited local checkout must be byte-for-
# byte unmodified after the audit run.
if [ -n "$CHECKOUT_FP_BEFORE" ]; then
    CHECKOUT_FP_AFTER=$(git -C "$GOLDEN_LOCAL_CHECKOUT" rev-parse HEAD:constitution 2>/dev/null)-$(git -C "$GOLDEN_LOCAL_CHECKOUT" status --porcelain=v1 2>/dev/null | md5sum | awk '{print $1}')
    if [ "$CHECKOUT_FP_BEFORE" = "$CHECKOUT_FP_AFTER" ]; then
        ok "C3 CA-012 read-only: $GOLDEN_LOCAL_CHECKOUT's tracked-tree fingerprint is unchanged after the audit invocation"
    else
        bad "C3 CA-012 read-only: $GOLDEN_LOCAL_CHECKOUT's tracked-tree fingerprint CHANGED after the audit invocation (before=$CHECKOUT_FP_BEFORE after=$CHECKOUT_FP_AFTER) -- audit.py must never mutate a local checkout"
    fi
else
    bad "C3 CA-012 read-only: could not capture a before-fingerprint (see Section B control needle)"
fi

# =============================================================================
# Section D -- T177 Round 1 regressions: B4 (coverage counted by distinct
# enumerated id, never by raw file count), I7 (migration_effort ALWAYS
# "ESTIMATE:", cleanliness genuinely measured), I8 (CA-010's coverage
# check is genuinely non-tautological), I9 (every KNOWN local checkout
# audited, not only the first).
# =============================================================================

# --- D1/D2: B4 -- `summary`'s coverage MUST be counted by DISTINCT
# project_id, never by raw file count. Reproduces the reviewer's exact
# repro: N copies of ONE migration record + N empty/stray audit files
# must NOT inflate coverage toward 1.0.
D_MIGDIR="$WORK/d_migrations"
D_AUDDIR="$WORK/d_audits_stray"
mkdir -p "$D_MIGDIR" "$D_AUDDIR"
for i in 1 2 3 4 5; do
    # T177 Round 2 R2-I6(b): a MIGRATED claim now requires genuine
    # double-verify evidence (data-model.md #13.3, "verification ...
    # required iff MIGRATED") to be counted -- this fixture's real point
    # is DEDUP-BY-ID (D1/D2), so it carries a genuinely well-formed
    # `verification` pair (2 CLEAN reports) rather than accidentally
    # exercising the SEPARATE missing-evidence check this same round adds.
    python3 "$MKREC" --out "$D_MIGDIR/dup_$i.json" --project HelixDevelopment/ota --commit deadbeef --hash1 abc --hash2 abc
    echo '{"not_a_real_report": true}' > "$D_AUDDIR/stray_$i.json"
done
D_SUM_OUT=$(run_tool summary --consumers "$CONSUMERS3" --audits "$D_AUDDIR" --migrations "$D_MIGDIR" --out "$WORK/d_summary.json" 2>&1); D_SUM_RC=$?
if python3 -c "
import json, sys
d = json.load(open('$WORK/d_summary.json'))
# 5 duplicate MIGRATED records for the SAME project_id (HelixDevelopment/ota,
# one of the 3 enumerated projects) must count as exactly 1 migrated project,
# never 5 -- and 'audited' must be 0 (the 5 stray files carry no real
# project_id, so none of them count), never 5.
ok = d.get('migrated') == 1 and d.get('audited') == 0 and abs(d.get('coverage', -1) - (1.0/3.0)) < 1e-6
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "D1 B4 dedup-by-id: 5 duplicate migration-record FILES for the SAME project_id count as exactly 1 migrated project (not 5), and 5 stray no-project_id audit files count as 0 audited (not 5) -- coverage correctly reads 1/3, never inflated toward 1.0"
else
    bad "D1 B4 dedup-by-id: summary did not correctly dedup by project_id (rc=$D_SUM_RC; see $WORK/d_summary.json)"
fi

# --- D2: B4 -- a migration record naming a project_id OUTSIDE the
# enumerated set MUST be reported separately, never silently counted
# toward coverage.
D_MIGDIR2="$WORK/d_migrations2"
mkdir -p "$D_MIGDIR2"
cat > "$D_MIGDIR2/unknown.json" <<'EOF'
{"schema":"consumer-migration/v1","project_id":"some-org/not-in-the-enumeration","outcome":"MIGRATED","data_change":"NONE","commit":"deadbeef"}
EOF
mkdir -p "$WORK/d_audits_empty"
run_tool summary --consumers "$CONSUMERS3" --audits "$WORK/d_audits_empty" --migrations "$D_MIGDIR2" --out "$WORK/d_summary2.json" >/dev/null 2>&1
if python3 -c "
import json, sys
d = json.load(open('$WORK/d_summary2.json'))
ok = d.get('migrated') == 0 and d.get('coverage') == 0.0 and 'some-org/not-in-the-enumeration' in (d.get('unknown_ids_ignored') or [])
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "D2 B4 unknown-id rejected: a migration record naming a project_id outside the enumerated set is reported in unknown_ids_ignored, never silently counted toward coverage"
else
    bad "D2 B4 unknown-id rejected: an out-of-set project_id was not correctly rejected/reported (see $WORK/d_summary2.json)"
fi

# --- D2b/D2c: T177 Round 2 R2-I6(b), re-specified in Round 3 (finding 1):
# duplicate records are resolved by CONTENT VALIDITY, never by file
# metadata (Round 2 used mtime; Round 3 replaces that -- see audit.py's
# cmd_summary and Section E below): an INVALID record (here a bare MIGRATED
# claim carrying NO genuine double-verify evidence) never counts and never
# overrides a VALID one, whatever its name or mtime. Reviewer's exact repro: an alphabetically
# LATER `z_stale.json {"outcome":"MIGRATED"}` (no verification field at
# all) must NOT override a genuinely NEWER, honest `a_new.json`
# NOT-MIGRATED record for the SAME project_id.
D_MIGDIR3="$WORK/d_migrations3"
mkdir -p "$D_MIGDIR3"
cat > "$D_MIGDIR3/z_stale.json" <<'EOF'
{"schema":"consumer-migration/v1","project_id":"HelixDevelopment/ota","outcome":"MIGRATED"}
EOF
sleep 1
cat > "$D_MIGDIR3/a_new.json" <<'EOF'
{"schema":"consumer-migration/v1","project_id":"HelixDevelopment/ota","outcome":"NOT-MIGRATED","not_migrated_reason":"NOT-MIGRATED (dirty-local)","data_change":"NONE"}
EOF
mkdir -p "$WORK/d_audits_empty3"
D2B_OUT=$(run_tool summary --consumers "$CONSUMERS3" --audits "$WORK/d_audits_empty3" --migrations "$D_MIGDIR3" --out "$WORK/d_summary3.json" 2>&1); D2B_RC=$?
if python3 -c "
import json, sys
d = json.load(open('$WORK/d_summary3.json'))
# The REAL mtime order is z_stale.json (older) then a_new.json (newer) --
# filename order would process them the same way here BY COINCIDENCE
# (z < a is false, so filename order would actually process a_new FIRST
# then z_stale SECOND, letting the stale MIGRATED win) -- the genuinely
# discriminating assertion is that the record actually counted reflects
# the MORE RECENT write (a_new, NOT-MIGRATED), never the stale MIGRATED
# claim, regardless of which name sorts first/last.
reasons = d.get('not_migrated_by_reason', {})
ok = d.get('migrated') == 0 and sum(reasons.values()) == 1 and 'NOT-MIGRATED (dirty-local)' in reasons
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "D2b R2-I6(b)/R3 finding 1 dedup: the VALID record (a_new.json, NOT-MIGRATED (dirty-local)) is the one counted for HelixDevelopment/ota, never z_stale.json's evidence-free bare MIGRATED claim"
else
    bad "D2b R2-I6(b)/R3 finding 1 dedup: summary let an invalid record override or join a valid one (rc=$D2B_RC out=$D2B_OUT; see $WORK/d_summary3.json)"
fi

D_MIGDIR4="$WORK/d_migrations4"
mkdir -p "$D_MIGDIR4"
cat > "$D_MIGDIR4/bare_migrated_claim.json" <<'EOF'
{"schema":"consumer-migration/v1","project_id":"HelixDevelopment/ota","outcome":"MIGRATED"}
EOF
mkdir -p "$WORK/d_audits_empty4"
D2C_OUT=$(run_tool summary --consumers "$CONSUMERS3" --audits "$WORK/d_audits_empty4" --migrations "$D_MIGDIR4" --out "$WORK/d_summary4.json" 2>&1); D2C_RC=$?
if python3 -c "
import json, sys
d = json.load(open('$WORK/d_summary4.json'))
# T177 Round 3 finding 1: an invalid record is reported in its OWN
# invalid_records_by_class bucket and is NOT counted toward coverage
# (Round 2 filed it under not_migrated_by_reason, which counted it).
inv = d.get('invalid_records_by_class', {})
ok = d.get('migrated') == 0 and inv.get('record-missing-verification-evidence') == 1 and d.get('coverage') == 0.0 and not d.get('not_migrated_by_reason')
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "D2c R2-I6(b) verification-required: a bare {\"outcome\":\"MIGRATED\"} record with NO 'verification' field is never counted as a real migration -- reported as record-missing-verification-evidence instead"
else
    bad "D2c R2-I6(b) verification-required: a bare MIGRATED claim with no verification evidence was still counted as migrated (rc=$D2C_RC out=$D2C_OUT; see $WORK/d_summary4.json)"
fi

# --- D3: I7 -- migration_effort is ALWAYS "ESTIMATE:", never "Measured:".
D3_OUT=$(run_tool audit --config "$CFG" --consumers "$CONSUMERS3" --workdir "$WORK/d3_cwork" --out "$WORK/d3_audits/" 2>&1); D3_RC=$?
if [ "$D3_RC" -eq 0 ] && python3 -c "
import glob, json, sys
bad = []
for f in glob.glob('$WORK/d3_audits/*.json'):
    d = json.load(open(f))
    eff = d.get('migration_effort', '')
    if not eff.startswith('ESTIMATE:'):
        bad.append((d.get('project_id'), eff))
sys.exit(1 if bad else 0)
" 2>/dev/null; then
    ok "D3 I7 migration_effort always ESTIMATE: every real audit report's migration_effort field starts with 'ESTIMATE:', never 'Measured:' -- matching this module's own docstring"
else
    bad "D3 I7 migration_effort always ESTIMATE: at least one report used a 'Measured:' label for a derived (never genuinely measured) effort figure (rc=$D3_RC)"
fi

# --- D4: I7 -- cleanliness is genuinely measured (git status --porcelain)
# for a real local checkout, distinguishing clean from dirty.
if python3 -c "
import json, glob, sys
for f in glob.glob('$WORK/d3_audits/*.json'):
    d = json.load(open(f))
    if d.get('project_id') == 'HelixDevelopment/ota':
        m = d.get('measurements', {}).get('cleanliness', {})
        sys.exit(0 if m.get('measured') is True and m.get('value') in ('clean', 'dirty') else 1)
sys.exit(1)
" 2>/dev/null; then
    ok "D4 I7 cleanliness genuinely measured: HelixDevelopment/ota's real audit report carries a measured=true cleanliness value ('clean' or 'dirty'), a genuine 'git status --porcelain' call this module's docstring previously claimed but never made"
else
    bad "D4 I7 cleanliness genuinely measured: HelixDevelopment/ota's report did not carry a genuinely-measured cleanliness field (see $WORK/d3_audits/)"
fi

# --- D5: I8 guard-viability -- the NEW CA-010 coverage check is
# genuinely non-tautological: a scratch copy of audit.py whose `audit`
# loop silently SKIPS the last project (the reviewer's own exact
# mutation shape) must now be CAUGHT (exit 1, naming the missing id),
# proving expected_ids/on_disk_ids are independently derived rather than
# moving in lockstep with a truncated loop.
D5_SCRATCH="$WORK/d5_audit_skip_mutation.py"
python3 -c "
import re
src = open('$TOOL').read()
anchor = 'for project in projects:'
assert src.count(anchor) == 1, 'anchor not unique or missing'
mutated = src.replace(anchor, 'for project in projects[:-1]:', 1)
open('$D5_SCRATCH', 'w').write(mutated)
" 2>"$WORK/d5_mutate.err"
if [ -f "$D5_SCRATCH" ]; then
    D5_OUT=$(python3 "$D5_SCRATCH" audit --config "$CFG" --consumers "$CONSUMERS3" --workdir "$WORK/d5_cwork" --out "$WORK/d5_audits/" 2>&1); D5_RC=$?
    if [ "$D5_RC" -eq 1 ] && echo "$D5_OUT" | grep -q 'CA-010 report coverage mismatch'; then
        ok "D5 I8 guard-viability: a scratch mutation that skips the LAST project in the iterated list (the reviewer's exact 'skipping one project' repro) IS now caught by CA-010's independently-derived coverage check, naming the missing id"
    else
        bad "D5 I8 guard-viability: the skip-last-project mutation was NOT caught by the CA-010 coverage check (rc=$D5_RC out=$D5_OUT) -- the check may still be tautological"
    fi
else
    bad "D5 I8 guard-viability: could not build the scratch mutation copy (see $WORK/d5_mutate.err) -- the anchor text may have changed; re-derive it"
fi

# --- D5b: T177 Round 2 R2-I6(a) guard-viability -- the SAME D5 mutation
# (skip the last project) run against a REUSED --out directory that
# already holds a STALE file for the dropped project (left over from an
# earlier, complete run) MUST STILL be caught -- a glob-the-whole-
# directory re-derivation (the pre-Round-2 shape) would silently pick up
# the stale file and report the coverage check satisfied, exactly the
# reviewer's live repro ("wrote 1 ... verified 2/2" on a scratch run
# reusing a --out that already held a prior-run file for the skipped
# project).
D5B_OUT_DIR="$WORK/d5b_reused_audits"
mkdir -p "$D5B_OUT_DIR"
D5B_FULL_OUT=$(python3 "$TOOL" audit --config "$CFG" --consumers "$CONSUMERS3" --workdir "$WORK/d5b_cwork_full" --out "$D5B_OUT_DIR" 2>&1); D5B_FULL_RC=$?
if [ "$D5B_FULL_RC" -ne 0 ]; then
    bad "D5b R2-I6(a) guard-viability setup: could not seed a complete real audit run into the reused --out directory (rc=$D5B_FULL_RC out=$D5B_FULL_OUT)"
else
    # Re-run the SAME skip-last-project mutant, pointed at the SAME,
    # now-populated --out directory (the stale files from the complete
    # run above are still sitting there, including one for whichever
    # project the mutant's own `projects[:-1]` will skip this time).
    D5B_OUT=$(python3 "$D5_SCRATCH" audit --config "$CFG" --consumers "$CONSUMERS3" --workdir "$WORK/d5b_cwork_mut" --out "$D5B_OUT_DIR" 2>&1); D5B_RC=$?
    if [ "$D5B_RC" -eq 1 ] && echo "$D5B_OUT" | grep -q 'CA-010 report coverage mismatch'; then
        ok "D5b R2-I6(a) guard-viability: the skip-last-project mutation is STILL caught even when --out is a REUSED directory already holding a stale, complete-looking file for the skipped project (a blind directory glob would have been fooled by it)"
    else
        bad "D5b R2-I6(a) guard-viability: a REUSED --out directory with a stale file for the skipped project defeated the CA-010 coverage check (rc=$D5B_RC out=$D5B_OUT) -- re-derivation is reading stale disk content instead of this run's own written paths"
    fi
fi

# --- D6: I9 -- a consumer with MULTIPLE local checkouts (HelixDevelopment/
# skills has real, independently-checked-out git worktrees on this host:
# /mnt/track2, /mnt/track3, /mnt/track4) gets a local_checkouts_detail
# entry per checkout, not only the first.
D6_MULTI_CONSUMERS="$WORK/d6_multi_consumers.json"
D6_CHECKOUTS_PRESENT=0
for p in /mnt/track2/helix_skills /mnt/track3/helix_skills /mnt/track4/helix_skills; do
    [ -d "$p/.git" ] || [ -f "$p/.git" ] && D6_CHECKOUTS_PRESENT=$((D6_CHECKOUTS_PRESENT + 1))
done
if [ "$D6_CHECKOUTS_PRESENT" -eq 3 ]; then
    cat > "$D6_MULTI_CONSUMERS" <<'EOF'
{
  "schema": "consumers/v1",
  "projects": [
    {
      "project_id": "HelixDevelopment/skills",
      "enumeration_sources": [{"source": "local-clone", "hit": true}],
      "consumer_kind": "submodule",
      "local_checkouts": ["/mnt/track2/helix_skills", "/mnt/track3/helix_skills", "/mnt/track4/helix_skills"]
    }
  ],
  "source_agreement": {"multi_source": 0, "single_source": 1, "text_only": 0}
}
EOF
    D6_OUT=$(run_tool audit --config "$CFG" --consumers "$D6_MULTI_CONSUMERS" --workdir "$WORK/d6_cwork" --out "$WORK/d6_audits/" 2>&1); D6_RC=$?
    if [ "$D6_RC" -eq 0 ] && python3 -c "
import glob, json, sys
files = glob.glob('$WORK/d6_audits/*.json')
if len(files) != 1:
    sys.exit(1)
d = json.load(open(files[0]))
detail = d.get('local_checkouts_detail') or []
paths = {x.get('path') for x in detail}
expected = {'/mnt/track2/helix_skills', '/mnt/track3/helix_skills', '/mnt/track4/helix_skills'}
sys.exit(0 if paths == expected else 1)
" 2>/dev/null; then
        ok "D6 I9 all-checkouts-audited: a consumer with 3 real local checkouts gets local_checkouts_detail entries for ALL 3 (/mnt/track2, /mnt/track3, /mnt/track4 helix_skills), not only the first"
    else
        bad "D6 I9 all-checkouts-audited: local_checkouts_detail did not cover all 3 real checkouts (rc=$D6_RC out=$D6_OUT)"
    fi
else
    echo "NOTE: D6 I9 all-checkouts-audited SKIPPED -- fewer than 3 of the expected /mnt/track{2,3,4}/helix_skills checkouts are present on this host ($D6_CHECKOUTS_PRESENT/3); not a test failure, a host-topology precondition"
fi

# =============================================================================
# Section E -- T177 Round 3 finding 1: `summary` must never report full
# coverage for an incomplete or meaningless input. The reviewer's three
# repros, at the reviewer's own scale (19 projects): (a) records carrying
# only {"project_id": ...}; (b) records from migrate.sh's own default dry
# run; (c) a consumers file written by a DEGRADED enumeration. Plus a
# conflicting-records case and a negative control (§11.4.201(1)).
# =============================================================================
E_DIR="$WORK/e_summary"
mkdir -p "$E_DIR/aud"
python3 - "$E_DIR" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
ids = ["e-org/p%02d" % i for i in range(19)]
projects = [{"project_id": i} for i in ids]
reach_ok = {"github_degraded": [], "gitlab_degraded": []}
reach_bad = {"github_degraded": [{"org": "e-org", "reason": "repo-list-error"}], "gitlab_degraded": []}
json.dump({"schema": "consumers/v1", "projects": projects, "source_reachability": reach_ok}, open(os.path.join(d, "cons_ok.json"), "w"))
json.dump({"schema": "consumers/v1", "projects": projects, "source_reachability": reach_bad}, open(os.path.join(d, "cons_degraded.json"), "w"))
VER = [{"path": "v1.json", "overall": "CLEAN", "body_hash": "h"}, {"path": "v2.json", "overall": "CLEAN", "body_hash": "h"}]
sets = {
    "ids_only": lambda i: {"project_id": i},
    "dry_run_legacy": lambda i: {"project_id": i, "outcome": "NOT-MIGRATED", "not_migrated_reason": "NOT-MIGRATED (preflight: dry-run)", "data_change": "NONE"},
    "dry_run_new": lambda i: {"project_id": i, "outcome": "DRY-RUN", "data_change": "NONE"},
    "nonconforming": lambda i: {"project_id": i, "outcome": "NOT-MIGRATED", "not_migrated_reason": "NOT-MIGRATED (gitlink-bump: local-git-error)", "data_change": "NONE"},
    "valid": lambda i: {"project_id": i, "outcome": "NOT-MIGRATED", "not_migrated_reason": "NOT-MIGRATED (dirty-local)", "data_change": "NONE"},
}
for name, mk in sets.items():
    os.makedirs(os.path.join(d, name), exist_ok=True)
    for i in ids:
        json.dump(mk(i), open(os.path.join(d, name, i.replace("/", "__") + ".json"), "w"))
# conflict: all valid, but p00 ALSO has a second, DIFFERENT valid record
os.makedirs(os.path.join(d, "conflict"), exist_ok=True)
for i in ids:
    json.dump(sets["valid"](i), open(os.path.join(d, "conflict", i.replace("/", "__") + ".json"), "w"))
PYEOF
# the second, DIFFERENT valid record for p00 -- a MIGRATED record with real
# verification evidence (T177 Round 5: shape-only evidence no longer counts)
python3 "$MKREC" --out "$E_DIR/conflict/zz_second_record.json" --project e-org/p00 --commit c0ffee
e_summary() {
    # $1=consumers-file $2=migrations-subdir $3=label [$4=reviews-dir] -> sets
    # E_RC; writes $E_DIR/$3.json. $4 is T177 Round 9 I2's optional --reviews
    # -- every E-series record here is NOT-MIGRATED (dirty-local), so
    # review_ref is never consulted for classification either way; $4 only
    # matters for decoupling THIS test's own axis from I2's unrelated
    # force-false-on-omission (used by E4 below).
    _erevarg=""
    [ -n "${4:-}" ] && _erevarg="--reviews $4"
    # shellcheck disable=SC2086  # deliberate: $_erevarg is "" or "--reviews <dir>"
    run_tool summary --consumers "$E_DIR/$1" --audits "$E_DIR/aud" --migrations "$E_DIR/$2" --out "$E_DIR/$3.json" $_erevarg >/dev/null 2>&1
    E_RC=$?
}
e_field() {
    python3 -c "import json,sys; print(json.dumps(json.load(open('$E_DIR/$1.json')).get('$2')))" 2>/dev/null
}
for case in ids_only dry_run_legacy dry_run_new nonconforming; do
    e_summary cons_ok.json "$case" "$case"
    if [ "$E_RC" -ne 0 ] && [ "$(e_field "$case" coverage)" = "0.0" ]; then
        ok "E1 R3 finding 1 ($case): 19 records of this kind give coverage 0.0 and a non-zero exit -- never counted as 19/19"
    else
        bad "E1 R3 finding 1 ($case): summary counted invalid records toward coverage (rc=$E_RC coverage=$(e_field "$case" coverage); see $E_DIR/$case.json)"
    fi
done
e_summary cons_degraded.json valid degraded
if [ "$E_RC" -ne 0 ] && [ "$(e_field degraded coverage_trusted)" = "false" ] && [ "$(e_field degraded enumeration_reachability)" = '"degraded"' ]; then
    ok "E2 R3 finding 1(c): a consumers file from a DEGRADED enumeration is refused (exit non-zero, coverage_trusted=false) even with 19/19 valid records"
else
    bad "E2 R3 finding 1(c): a degraded consumers file was trusted (rc=$E_RC; see $E_DIR/degraded.json)"
fi
e_summary cons_ok.json conflict conflict
if [ "$E_RC" -ne 0 ] && python3 -c "
import json, sys
d = json.load(open('$E_DIR/conflict.json'))
sys.exit(0 if 'e-org/p00' in (d.get('conflicting_records') or {}) and 'e-org/p00' in d.get('uncovered_ids', []) and d.get('coverage_trusted') is False else 1)
" 2>/dev/null; then
    ok "E3 R3 finding 1 conflict: two VALID but DIFFERENT records for one project are reported as conflicting, that project is not covered, and the run exits non-zero"
else
    bad "E3 R3 finding 1 conflict: conflicting records were silently resolved (rc=$E_RC; see $E_DIR/conflict.json)"
fi
e_summary cons_ok.json valid valid "$E_DIR/aud"
if [ "$E_RC" -eq 0 ] && [ "$(e_field valid coverage)" = "1.0" ] && [ "$(e_field valid coverage_trusted)" = "true" ]; then
    ok "E4 negative control (§11.4.201(1)): a COMPLETE enumeration with 19 valid closed-set records gives coverage 1.0, trusted, exit 0 -- the new checks do not refuse a genuinely complete run"
else
    bad "E4 negative control: a genuinely complete, valid input was refused (rc=$E_RC; see $E_DIR/valid.json)"
fi

# =============================================================================
# Section F -- T177 Round 5 (round-4 review I1 A1/A2/A3/A4/A6 + M1-at-summary,
# I2, I3, N2-bucket, I6). Every guard below is paired with its EXACT
# mutation, applied to a scratch copy of audit.py (never the tracked file):
# the fixture must PASS on the real tool and the mutant must give the WRONG
# answer on the SAME fixture -- otherwise the guard is decoration
# (§11.4.115(F)/§1.1). Where round 5 restructured the code the reviewer's
# anchor pointed at, the mutation is the SAME semantic deletion re-anchored
# on the new text (noted per case); every other anchor is the reviewer's
# verbatim.
# =============================================================================
F_DIR="$WORK/f_summary"
mkdir -p "$F_DIR/aud"
python3 - "$F_DIR" <<'PYEOF'
import json, os, sys
d = sys.argv[1]
proj = [{"project_id": "f-org/p"}]
ok = {"github_degraded": [], "gitlab_degraded": []}
json.dump({"schema": "consumers/v1", "projects": proj, "source_reachability": ok}, open(os.path.join(d, "cons_ok.json"), "w"))
json.dump({"schema": "consumers/v1", "projects": proj}, open(os.path.join(d, "cons_noreach.json"), "w"))
json.dump({"schema": "consumers/v1", "projects": proj, "source_reachability": {}}, open(os.path.join(d, "cons_empty_reach.json"), "w"))
json.dump({"schema": "consumers/v1", "projects": proj, "source_reachability": {"github_degraded": []}}, open(os.path.join(d, "cons_half_reach.json"), "w"))
json.dump({"schema": "consumers/v1", "projects": proj, "source_reachability": {"github_degraded": "none", "gitlab_degraded": []}}, open(os.path.join(d, "cons_nonlist_reach.json"), "w"))
PYEOF
f_case() {
    # $1=case-name; remaining args -> mkrec.py args (record written into its own dir)
    _c=$1; shift
    mkdir -p "$F_DIR/$_c"
    python3 "$MKREC" --out "$F_DIR/$_c/rec.json" --project f-org/p "$@"
}
f_json() {
    # $1=case $2=dir-name -> writes a raw JSON record (stdin) into the case dir
    mkdir -p "$F_DIR/$1"; cat > "$F_DIR/$1/rec.json"
}
# T177 Round 9 (round-8 IMPORTANT I2 fallout): a shared, genuinely-verified
# --reviews archive matching mkrec.py's OWN defaults (review_ref
# "fixture-review-id", project "f-org/p"), so any fixture whose real
# discriminating signal is UNRELATED to review_ref_verification can supply
# it and stay decoupled from the force-false-on-omission behaviour I2
# introduces (F0/F0r/F4/F5/F14 below).
F_DEFAULT_REVIEWS="$F_DIR/default_reviews"
mkdir -p "$F_DEFAULT_REVIEWS"
cat > "$F_DEFAULT_REVIEWS/fixture-review-id.json" <<'EOF'
{"review_id":"fixture-review-id","project_id":"f-org/p","verdict":"GO","findings":[],"model_tier":"opus","effort":"xhigh"}
EOF
f_sum() {
    # $1=tool $2=consumers-file $3=case $4=label [$5=reviews-dir] -> F_RC;
    # summary at $F_DIR/$4.sum. $5 is T177 Round 6 I5's --reviews archive;
    # omitted by every existing caller (unchanged CLI contract).
    _revarg=""
    [ -n "${5:-}" ] && _revarg="--reviews $5"
    # shellcheck disable=SC2086  # deliberate: $_revarg is "" or "--reviews <dir>"
    python3 "$1" summary --consumers "$F_DIR/$2" --audits "$F_DIR/aud" --migrations "$F_DIR/$3" --out "$F_DIR/$4.sum" $_revarg >/dev/null 2>&1
    F_RC=$?
}
f_get() { python3 -c "import json,sys; d=json.load(open('$F_DIR/$1.sum')); print(json.dumps(eval(sys.argv[1])))" "$2" 2>/dev/null; }
f_mutant() {
    # $1=label $2=anchor $3=replacement -> writes $F_DIR/mut_$1.py; F_MUT_OK=1 iff anchor unique
    python3 - "$TOOL" "$F_DIR/mut_$1.py" "$2" "$3" <<'PYEOF'
import sys
src, dst, a, b = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(a) != 1:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PYEOF
    _mrc=$?
    F_MUT_OK=0
    [ "$_mrc" -eq 0 ] && F_MUT_OK=1
}
# pair: $1=id $2=consumers $3=case $4=expected-real-python-expr $5=mutant-label $6=anchor $7=replacement $8=description [$9=reviews-dir]
# T177 Round 9 (round-8 IMPORTANT I2 fallout): $9 is OPTIONAL and forwarded
# to BOTH internal f_sum calls -- every pre-existing f_pair caller omits it
# (unchanged default: review_ref_verification="presence-only",
# coverage_trusted forced false regardless of what's under test). A test
# whose discriminating assertion is `coverage_trusted` itself (F4/F5-style)
# MUST supply $9 so the --reviews-omitted force-false doesn't mask the
# UNRELATED property the mutant is meant to prove load-bearing.
f_pair() {
    # The REAL-tool verdict is reported FIRST and independently of the
    # mutant: an external mutation harness that mutates audit.py itself
    # also breaks this function's own anchor, and the real-half failure
    # must still be visible (never masked by the anchor-miss early return).
    f_sum "$TOOL" "$2" "$3" "$1_real" "${9:-}"
    REAL_OK=$(f_get "$1_real" "$4")
    REAL_RC=$F_RC
    if [ "$REAL_OK" = "true" ] && [ "$REAL_RC" -ne 0 ]; then
        ok "$1 $8 (real tool refuses: rc=$REAL_RC)"
    else
        bad "$1 $8: real tool did not refuse as expected (expr=$REAL_OK rc=$REAL_RC; see $F_DIR/$1_real.sum)"
    fi
    f_mutant "$5" "$6" "$7"
    if [ "$F_MUT_OK" -ne 1 ]; then
        bad "$1 guard-viability: mutation anchor for '$5' is not unique/present in audit.py -- re-derive it"
        return
    fi
    f_sum "$F_DIR/mut_$5.py" "$2" "$3" "$1_mut" "${9:-}"
    MUT_OK=$(f_get "$1_mut" "$4")
    if [ "$MUT_OK" = "false" ]; then
        ok "$1 guard-viability: mutant '$5' gives the WRONG answer on the same fixture -- the guard is load-bearing"
    else
        bad "$1 guard-viability: mutant '$5' still gives the right answer (expr=$MUT_OK) -- the guard is NOT what catches it"
    fi
}

# F0 negative control (§11.4.201(1)): a genuine MIGRATED record with real,
# byte-matching evidence, review_ref and backup_marker IS counted; a
# relative evidence path (resolved against the record's own directory) too.
f_case f0_golden
f_sum "$TOOL" cons_ok.json f0_golden f0 "$F_DEFAULT_REVIEWS"
if [ "$F_RC" -eq 0 ] && [ "$(f_get f0 "d['migrated']==1 and d['coverage_trusted'] is True and d['review_ref_verification']=='verified'")" = "true" ]; then
    ok "F0 negative control: a MIGRATED record with real, byte-matching verification evidence + review_ref + backup_marker counts (coverage 1.0, trusted, exit 0); review_ref_verification discloses 'verified' when --reviews is supplied (T177 Round 9 I2)"
else
    bad "F0 negative control: a genuine MIGRATED record was refused (rc=$F_RC; see $F_DIR/f0.sum)"
fi
f_case f0_relative --break relative-paths
f_sum "$TOOL" cons_ok.json f0_relative f0r "$F_DEFAULT_REVIEWS"
if [ "$F_RC" -eq 0 ] && [ "$(f_get f0r "d['migrated']==1")" = "true" ]; then
    ok "F0b negative control: relative evidence paths resolve against the record's own directory and still verify"
else
    bad "F0b negative control: relative evidence paths were not resolved (rc=$F_RC; see $F_DIR/f0r.sum)"
fi

# F1 (A1): NOT_CLEAN x2, equal hashes, files consistent with the record.
# Round-5 code split the reviewer's anchor line; same deletion, re-anchored.
f_case f1_notclean --overall1 NOT_CLEAN --overall2 NOT_CLEAN
f_pair F1 cons_ok.json f1_notclean "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-missing-verification-evidence')==1" \
    A1_drop_clean_check \
    '    if not all(e.get("overall") == "CLEAN" for e in v):
        return "record-missing-verification-evidence"
' '' \
    "A1: a MIGRATED record whose verification pair is NOT_CLEAN is never counted"

# F2 (A2): CLEAN x2 but DIFFERENT body_hash. Re-anchored (same deletion of the equality clause).
f_case f2_hashdiff --hash1 h1 --hash2 h2
f_pair F2 cons_ok.json f2_hashdiff "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-missing-verification-evidence')==1" \
    A2_drop_hash_eq \
    'if not (v[0].get("body_hash") and v[0].get("body_hash") == v[1].get("body_hash")):' \
    'if not (v[0].get("body_hash")):' \
    "A2: a MIGRATED record whose two verify runs disagree on body_hash is never counted"

# F3 (A3): two VALID MIGRATED records for one project naming DIFFERENT commits. Reviewer's verbatim anchor.
mkdir -p "$F_DIR/f3_two_commits"
python3 "$MKREC" --out "$F_DIR/f3_two_commits/a.json" --project f-org/p --commit aaaa1111
python3 "$MKREC" --out "$F_DIR/f3_two_commits/b.json" --project f-org/p --commit bbbb2222
f_pair F3 cons_ok.json f3_two_commits "'f-org/p' in d.get('conflicting_records',{}) and d['migrated']==0" \
    A3_sig_ignores_commit \
    'valid_by_id.setdefault(pid, set()).add((key, rec.get("commit") or ""))' \
    'valid_by_id.setdefault(pid, set()).add((key, ""))' \
    "A3: two MIGRATED claims naming different commits for one project are a conflict, not one migration"

# F4 (A4, the RATIFIED 'missing source_reachability => untrusted' choice):
# anchor re-derived T177 Round 9 for the I2 multi-line coverage_trusted
# expression; $F_DEFAULT_REVIEWS supplied so this test's OWN axis
# (enumeration_reachability) is decoupled from I2's UNRELATED
# review_ref_verification force-false.
f_case f4_golden_rec
f_pair F4 cons_noreach.json f4_golden_rec "d['enumeration_reachability']=='unrecorded' and d['coverage_trusted'] is False" \
    A4_unrecorded_trusted \
    'enumeration_reachability == "complete"' \
    'enumeration_reachability in ("complete", "unrecorded")' \
    "A4: a consumers file with NO source_reachability block is never trusted as complete, even with a valid record" \
    "$F_DEFAULT_REVIEWS"

# F5 (I2): source_reachability present but EMPTY / half / non-list -> never
# complete. The mutant restores Round 3's exact parent-key-only logic
# (`reach.get(...) or []`), the code the reviewer's `{}` repro defeated.
for rc_file in cons_empty_reach.json cons_half_reach.json cons_nonlist_reach.json; do
    f_pair "F5[$rc_file]" "$rc_file" f4_golden_rec "d['enumeration_reachability']=='incomplete' and d['coverage_trusted'] is False" \
        I2_round3_presence_only \
        '    elif not (isinstance(reach.get("github_degraded"), list) and isinstance(reach.get("gitlab_degraded"), list)):
        enumeration_reachability = "incomplete"
    else:
        degraded = list(reach["github_degraded"]) + list(reach["gitlab_degraded"])' \
        '    else:
        degraded = list(reach.get("github_degraded") or []) + list(reach.get("gitlab_degraded") or [])' \
        "I2: a source_reachability block lacking a real github_degraded AND gitlab_degraded list is 'incomplete', never trusted"
done

# F6 (A6): a well-formed reason whose STEP is outside the closed set. Reviewer's verbatim anchor.
f_json f6_badstep <<'EOF'
{"project_id":"f-org/p","outcome":"NOT-MIGRATED","not_migrated_reason":"NOT-MIGRATED (bogus-step: unreachable)","data_change":"NONE"}
EOF
f_pair F6 cons_ok.json f6_badstep "d.get('invalid_records_by_class',{}).get('nonconforming-reason')==1 and d['coverage']==0.0" \
    A6_reason_any_step \
    'if m and m.group(1) in MIGRATION_STEPS and m.group(2) in MIGRATION_REASONS' \
    'if m and m.group(2) in MIGRATION_REASONS' \
    "A6: a NOT-MIGRATED reason naming a step outside the closed DEC-25 step set is nonconforming, never counted"

# F7 (M1 at the summary seam): the reviewer's M1 shape -- content_address =
# sha256 of the PATH STRING -- plus a missing file and a record that lies
# about what its own cited report says.
f_case f7_addr_of_path --break addr-of-path
f_pair F7a cons_ok.json f7_addr_of_path "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-verification-evidence-mismatch')==1" \
    M1S_drop_bytes_hash \
    '        if "sha256:" + hashlib.sha256(raw).hexdigest() != addr:
            return "record-verification-evidence-mismatch"
' '' \
    "M1(summary): a content_address that is not the sha256 of the cited report's REAL bytes is refused"
f_case f7_missing --break missing-file
f_pair F7b cons_ok.json f7_missing "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-verification-evidence-unverifiable')==1" \
    M1S_missing_ok \
    '            return "record-verification-evidence-unverifiable"' \
    '            continue' \
    "M1(summary): a MIGRATED record whose cited report no longer exists is unverifiable, never counted"
f_case f7_lies --break record-lies
f_pair F7c cons_ok.json f7_lies "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-verification-evidence-mismatch')==1" \
    M1S_no_content_crosscheck \
    'if not isinstance(report, dict) or report.get("overall") != e.get("overall") or report.get("body_hash") != e.get("body_hash"):' \
    'if not isinstance(report, dict):' \
    "M1(summary): a record claiming CLEAN while its own byte-matching report says NOT_CLEAN is refused"

# F8 (I3): review_ref + backup_marker are REQUIRED iff MIGRATED (data model enforced, not amended).
f_case f8_noref --break no-review-ref
f_pair F8a cons_ok.json f8_noref "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-missing-review-ref')==1" \
    I3_drop_review_ref \
    '        if not (isinstance(rref, str) and rref.strip()):
            return False, "record-missing-review-ref"
' '' \
    "I3: a MIGRATED record with no review_ref is never counted"
f_case f8_nobm --break no-backup-marker
f_pair F8b cons_ok.json f8_nobm "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-missing-backup-marker')==1" \
    I3_drop_backup_marker \
    '            return False, "record-missing-backup-marker"' \
    '            pass' \
    "I3: a MIGRATED record with no backup_marker is never counted"
f_case f8_badbm --break bad-backup-addr
f_sum "$TOOL" cons_ok.json f8_badbm f8c
if [ "$F_RC" -ne 0 ] && [ "$(f_get f8c "d.get('invalid_records_by_class',{}).get('record-missing-backup-marker')==1")" = "true" ]; then
    ok "F8c I3: a backup_marker whose content_address is not sha256:<64 hex> is refused"
else
    bad "F8c I3: a malformed backup_marker content address was accepted (rc=$F_RC; see $F_DIR/f8c.sum)"
fi

# =============================================================================
# F11-F14 -- T177 Round 6 (round-5 review findings I4/I5/M5). Every guard is
# paired with its mutation exactly as the F-series above; F14 is a positive
# control (no mutant needed, mirroring F0's own style).
# =============================================================================

# F11 (I4): a MIGRATED record citing a FOREIGN project's real, byte-matching
# CLEAN reports while claiming an unrelated commit is refused -- the cited
# report's own repos[path=="."].head must equal the record's own commit.
f_case f11_foreign --break foreign-commit
f_pair F11 cons_ok.json f11_foreign "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-verification-evidence-not-bound')==1" \
    I4_drop_binding_check \
    '        if root_head != commit:
            return "record-verification-evidence-not-bound"
' '' \
    "I4: a MIGRATED record whose cited report's own root HEAD does not equal the record's commit (foreign evidence) is refused"

# F12 (I4): citing the SAME report path twice as "two independent verify
# runs" is refused -- CA-026's "verify TWICE" is not satisfied by one real
# run cited twice.
f_case f12_samereport --break same-report-twice
f_pair F12 cons_ok.json f12_samereport "d['migrated']==0 and d.get('invalid_records_by_class',{}).get('record-verification-evidence-not-independent')==1" \
    I4_drop_distinct_path_check \
    'if v[0].get("path") == v[1].get("path"):' \
    'if False:' \
    "I4: a MIGRATED record citing the SAME report path twice as its two independent verify runs is refused"

# F13 (I5, RULING a): review_ref is REAL-VERIFIED when a --reviews directory
# is supplied (summary resolves review_ref against review-record files there
# and ports migrate.sh's own check_review predicate); degrade to
# presence-only when --reviews is omitted -- T177 Round 9 (round-8
# IMPORTANT I2) corrects the earlier round-6/7 framing ("today's unchanged
# default ... kept explicit and test-visible") to be genuinely HONEST
# rather than merely test-visible: the degrade is now disclosed in the
# WRITTEN ARTIFACT itself (`review_ref_verification`) and `coverage_trusted`
# is forced false, not merely left as an unchanged, trustable-looking
# default for every pre-existing caller (F13c below).
F13_REVIEWS="$F_DIR/f13_reviews"
mkdir -p "$F13_REVIEWS"
cat > "$F13_REVIEWS/REV-f13-1.json" <<'EOF'
{"review_id":"REV-f13-1","project_id":"f-org/p","verdict":"GO","findings":[],"model_tier":"opus","effort":"xhigh"}
EOF
f_case f13_go
python3 -c "
import json
d = json.load(open('$F_DIR/f13_go/rec.json'))
d['review_ref'] = 'REV-f13-1'
json.dump(d, open('$F_DIR/f13_go/rec.json', 'w'))
"
f_sum "$TOOL" cons_ok.json f13_go f13go "$F13_REVIEWS"
if [ "$F_RC" -eq 0 ] && [ "$(f_get f13go "d['migrated']==1")" = "true" ]; then
    ok "F13a I5: a review_ref resolving (via --reviews) to a real GO/zero-finding/opus/xhigh review record is accepted"
else
    bad "F13a I5: a genuinely GO review_ref was refused when --reviews was supplied (rc=$F_RC; see $F_DIR/f13go.sum)"
fi

cat > "$F13_REVIEWS/REV-f13-nogo.json" <<'EOF'
{"review_id":"REV-f13-nogo","project_id":"f-org/p","verdict":"NO-GO","findings":[{"severity":"Blocking"}],"model_tier":"opus","effort":"xhigh"}
EOF
f_case f13_nogo
python3 -c "
import json
d = json.load(open('$F_DIR/f13_nogo/rec.json'))
d['review_ref'] = 'REV-f13-nogo'
json.dump(d, open('$F_DIR/f13_nogo/rec.json', 'w'))
"
f_sum "$TOOL" cons_ok.json f13_nogo f13nogo "$F13_REVIEWS"
if [ "$F_RC" -ne 0 ] && [ "$(f_get f13nogo "d.get('invalid_records_by_class',{}).get('record-review-no-go')==1")" = "true" ]; then
    ok "F13b I5: a review_ref resolving to a real NO-GO/non-zero-finding review record is refused (record-review-no-go), never trusted on presence alone -- RULING (a) genuinely enforced"
else
    bad "F13b I5: a review_ref resolving to a NO-GO review was still counted as MIGRATED (rc=$F_RC; see $F_DIR/f13nogo.sum)"
fi

# T177 Round 9 (round-8 IMPORTANT I2): REWRITTEN. Round 6/7's framing --
# "the degrade is explicit and test-visible, never a silent gap, and the
# default CLI contract for every pre-existing caller is unchanged" -- was
# itself the exact "capability added but invisible in the artifact a
# release seam actually reads" bluff the round-8 review found: the record
# still counted migrated=1 AND exit 0 AND coverage_trusted=true with
# review_ref checked for PRESENCE ONLY, indistinguishable from a genuinely
# verified run. I2 corrects this: per-record classification is UNCHANGED
# (classify_migration_record's own presence-only fallback still counts
# the record when no --reviews archive is supplied, so `migrated` still
# reads 1 here -- the degrade's SHAPE is the same), but the SUMMARY-LEVEL
# trust signal is now forced honest: `review_ref_verification` discloses
# "presence-only" and `coverage_trusted` is forced false, so rc is now 1
# -- a caller reading coverage_trusted can no longer be fooled into
# thinking an unverified review_ref means real CA-024 coverage.
f_sum "$TOOL" cons_ok.json f13_nogo f13nogo_noflag
if [ "$F_RC" -ne 0 ] && [ "$(f_get f13nogo_noflag "d['migrated']==1 and d.get('review_ref_verification')=='presence-only' and d.get('coverage_trusted') is False")" = "true" ]; then
    ok "F13c I5/I2 honest degrade: WITHOUT --reviews, the SAME NO-GO-bound record is STILL counted toward migrated (per-record presence-only classification unchanged) but review_ref_verification discloses 'presence-only' and coverage_trusted is FORCED false (T177 Round 9 I2) -- a caller can no longer be fooled by an unverified review_ref"
else
    bad "F13c I5/I2 honest degrade: omitting --reviews did not force the honest untrusted/disclosed state (rc=$F_RC; see $F_DIR/f13nogo_noflag.sum)"
fi

f_mutant I5_disable_real_check \
    'def classify_migration_record(rec, base_dir=".", reviews_dir=None):' \
    'def classify_migration_record(rec, base_dir=".", reviews_dir=None):
    reviews_dir = None  # T177 Round 6 I5 mutant: real verification disabled'
if [ "$F_MUT_OK" -eq 1 ]; then
    python3 "$F_DIR/mut_I5_disable_real_check.py" summary --consumers "$F_DIR/cons_ok.json" --audits "$F_DIR/aud" --migrations "$F_DIR/f13_nogo" --out "$F_DIR/f13mut.sum" --reviews "$F13_REVIEWS" >/dev/null 2>&1
    F_RC=$?
    if [ "$F_RC" -eq 0 ] && [ "$(f_get f13mut "d['migrated']==1")" = "true" ]; then
        ok "F13 guard-viability: forcing reviews_dir=None (disabling the real check even though --reviews was passed) lets the NO-GO-bound review_ref through -- F13b is what catches it"
    else
        bad "F13 guard-viability: the disabled-verification mutant still refused the NO-GO review (rc=$F_RC; see $F_DIR/f13mut.sum)"
    fi
else
    bad "F13 guard-viability: mutation anchor for 'I5_disable_real_check' is not unique/present in audit.py -- re-derive it"
fi

# F14 (M5): backup_marker's DESIGN -- only its SHAPE is checked, never
# whether the backup directory itself still exists on disk (the backup is a
# disposable §9.2 mirror that may legitimately be pruned later). A
# backup_marker whose path points at a GENUINELY NONEXISTENT directory, with
# an otherwise shape-valid content_address, is STILL counted MIGRATED -- an
# explicit, test-visible positive control for this intentional design
# (round-5's own rationale), so a future accidental tightening (e.g.
# requiring os.path.isdir(bm['path'])) is a DELIBERATE, test-visible
# decision, never a silent behavior change.
f_case f14_missing_backup_dir
python3 -c "
import json, os, sys
d = json.load(open('$F_DIR/f14_missing_backup_dir/rec.json'))
if os.path.exists(d['backup_marker']['path']):
    sys.exit('fixture precondition violated: backup_marker.path exists on disk')
"
f_sum "$TOOL" cons_ok.json f14_missing_backup_dir f14 "$F_DEFAULT_REVIEWS"
if [ "$F_RC" -eq 0 ] && [ "$(f_get f14 "d['migrated']==1")" = "true" ]; then
    ok "F14 M5 positive control: a backup_marker whose path does not exist on disk is STILL counted MIGRATED -- the backup mirror's disposability is a deliberate design choice, now test-visible"
else
    bad "F14 M5 positive control: a shape-valid-but-nonexistent backup_marker path was unexpectedly refused (rc=$F_RC; see $F_DIR/f14.sum) -- if this is an intentional tightening, update this test's expectation deliberately"
fi


# =============================================================================
# F15-F17 -- T177 Round 9 (round-8 IMPORTANT I2 + MINOR M5 points 2/3).
# =============================================================================

# F15 (I2): `review_ref_verification` genuinely discloses the degrade IN
# THE WRITTEN ARTIFACT, and `coverage_trusted` is genuinely FORCED false
# when --reviews is omitted -- paired with a positive control (supplying
# --reviews restores verified/trusted on the SAME fixture) and a mutant
# proving the force is load-bearing, not merely a field nobody consults.
f_case f15_golden
f_sum "$TOOL" cons_ok.json f15_golden f15_noflag
if [ "$F_RC" -ne 0 ] && [ "$(f_get f15_noflag "d.get('review_ref_verification')=='presence-only' and d.get('coverage_trusted') is False and d['migrated']==1")" = "true" ]; then
    ok "F15 I2: omitting --reviews on an otherwise fully-valid MIGRATED fixture still discloses review_ref_verification='presence-only' and forces coverage_trusted=false (rc!=0)"
else
    bad "F15 I2: the --reviews-omitted disclosure/force did not fire as expected (rc=$F_RC; see $F_DIR/f15_noflag.sum)"
fi
f_sum "$TOOL" cons_ok.json f15_golden f15_withflag "$F_DEFAULT_REVIEWS"
if [ "$F_RC" -eq 0 ] && [ "$(f_get f15_withflag "d.get('review_ref_verification')=='verified' and d.get('coverage_trusted') is True")" = "true" ]; then
    ok "F15 I2 positive control: supplying --reviews on the SAME fixture flips review_ref_verification to 'verified' and coverage_trusted to true (rc=0) -- the force is genuinely conditioned on the CLI flag, not a permanent regression"
else
    bad "F15 I2 positive control: supplying --reviews did not restore the verified/trusted state (rc=$F_RC; see $F_DIR/f15_withflag.sum)"
fi
f_mutant I2_drop_force_false \
    'coverage_trusted = (
        enumeration_reachability == "complete"
        and not conflicting
        and review_ref_verification == "verified"
    )' \
    'coverage_trusted = (
        enumeration_reachability == "complete"
        and not conflicting
    )'
if [ "$F_MUT_OK" -eq 1 ]; then
    f_sum "$F_DIR/mut_I2_drop_force_false.py" cons_ok.json f15_golden f15mut
    if [ "$F_RC" -eq 0 ] && [ "$(f_get f15mut "d.get('coverage_trusted') is True")" = "true" ]; then
        ok "F15 guard-viability: without the force, omitting --reviews leaves coverage_trusted=true (exit 0) on an unverified review_ref -- F15 is what catches it"
    else
        bad "F15 guard-viability: the drop-force mutant did not reproduce the untrusted-looking-trusted state (rc=$F_RC; see $F_DIR/f15mut.sum)"
    fi
else
    bad "F15 guard-viability: mutation anchor for 'I2_drop_force_false' is not unique/present in audit.py -- re-derive it"
fi

# F16 (R8 M5, point 2): a review record with NO `project_id` field is
# refused exactly like one naming a DIFFERENT project -- migrate.sh's own
# check_review() binds project_id UNCONDITIONALLY (no "if present" guard
# at all), so a review document without one is not something the WRITE
# path would ever have genuinely accepted in the first place; checking it
# only "where stated" at READ time was an unnecessary weakening.
F16_REVIEWS="$F_DIR/f16_reviews"
mkdir -p "$F16_REVIEWS"
cat > "$F16_REVIEWS/REV-f16-noproj.json" <<'EOF'
{"review_id":"REV-f16-noproj","verdict":"GO","findings":[],"model_tier":"opus","effort":"xhigh"}
EOF
f_case f16_noproj
python3 -c "
import json
d = json.load(open('$F_DIR/f16_noproj/rec.json'))
d['review_ref'] = 'REV-f16-noproj'
json.dump(d, open('$F_DIR/f16_noproj/rec.json', 'w'))
"
f_sum "$TOOL" cons_ok.json f16_noproj f16 "$F16_REVIEWS"
if [ "$F_RC" -ne 0 ] && [ "$(f_get f16 "d.get('invalid_records_by_class',{}).get('record-review-no-go')==1")" = "true" ]; then
    ok "F16 R8 M5(2): a review record with NO project_id field is refused exactly like one naming a different project"
else
    bad "F16 R8 M5(2): a project_id-less review record was wrongly accepted (rc=$F_RC; see $F_DIR/f16.sum)"
fi
f_mutant M5_2_project_id_optional \
    'if doc.get("project_id") != project_id:' \
    'if "project_id" in doc and doc.get("project_id") != project_id:'
if [ "$F_MUT_OK" -eq 1 ]; then
    f_sum "$F_DIR/mut_M5_2_project_id_optional.py" cons_ok.json f16_noproj f16mut "$F16_REVIEWS"
    if [ "$F_RC" -eq 0 ] && [ "$(f_get f16mut "d['migrated']==1")" = "true" ]; then
        ok "F16 guard-viability: reverting to the conditional 'if present' project_id check accepts the project_id-less review record as MIGRATED -- F16 is what catches it"
    else
        bad "F16 guard-viability: the conditional-project_id mutant did not reproduce acceptance (rc=$F_RC; see $F_DIR/f16mut.sum)"
    fi
else
    bad "F16 guard-viability: mutation anchor for 'M5_2_project_id_optional' is not unique/present in audit.py -- re-derive it"
fi

# F17 (R8 M5, point 3): a `review_ref` that ESCAPES the declared --reviews
# archive (a relative path resolving, via the record's own directory,
# OUTSIDE the archive) is refused as unverifiable, never silently opened.
# `review_ref` is a field of the UNTRUSTED migration record itself -- an
# attacker-controlled record must not be able to use it to read arbitrary
# files this process can reach.
F17_REVIEWS="$F_DIR/f17_reviews"
mkdir -p "$F17_REVIEWS"
cat > "$F_DIR/f17_outside_secret.json" <<'EOF'
{"verdict":"GO","project_id":"f-org/p","findings":[],"model_tier":"opus","effort":"xhigh"}
EOF
f_case f17_escape
python3 -c "
import json
d = json.load(open('$F_DIR/f17_escape/rec.json'))
d['review_ref'] = '../f17_outside_secret.json'
json.dump(d, open('$F_DIR/f17_escape/rec.json', 'w'))
"
f_sum "$TOOL" cons_ok.json f17_escape f17 "$F17_REVIEWS"
if [ "$F_RC" -ne 0 ] && [ "$(f_get f17 "d.get('invalid_records_by_class',{}).get('record-review-ref-unverifiable')==1")" = "true" ]; then
    ok "F17 R8 M5(3): a review_ref that escapes the declared --reviews archive is refused as unverifiable -- an attacker-controlled migration record cannot use review_ref to read arbitrary files"
else
    bad "F17 R8 M5(3): a path-escaping review_ref was wrongly resolved/accepted (rc=$F_RC; see $F_DIR/f17.sum)"
fi
f_mutant M5_3_no_containment \
    '    boundary = reviews_dir if reviews_dir else base_dir
    if not _contained(path, boundary):
        return None' \
    '    pass'
if [ "$F_MUT_OK" -eq 1 ]; then
    f_sum "$F_DIR/mut_M5_3_no_containment.py" cons_ok.json f17_escape f17mut "$F17_REVIEWS"
    if [ "$F_RC" -eq 0 ] && [ "$(f_get f17mut "d['migrated']==1")" = "true" ]; then
        ok "F17 guard-viability: without the containment check the path-escaping review_ref is opened and accepted as a genuine GO review, counted MIGRATED -- F17 is what catches it"
    else
        bad "F17 guard-viability: the no-containment mutant did not reproduce the escape acceptance (rc=$F_RC; see $F_DIR/f17mut.sum)"
    fi
else
    bad "F17 guard-viability: mutation anchor for 'M5_3_no_containment' is not unique/present in audit.py -- re-derive it"
fi

# F9 (round-4 MINOR N2): migrate.sh's own local-git-error lands in its OWN bucket.
f_json f9_lge <<'EOF'
{"project_id":"f-org/p","outcome":"NOT-MIGRATED","not_migrated_reason":"NOT-MIGRATED (gitlink-bump: local-git-error)","data_change":"NONE","detail":"git-update-index-failed"}
EOF
f_pair F9 cons_ok.json f9_lge "d.get('invalid_records_by_class',{}).get('local-git-error-vocabulary-gap')==1 and 'nonconforming-reason' not in d.get('invalid_records_by_class',{}) and d['coverage']==0.0" \
    N2_merge_bucket \
    '            return False, "local-git-error-vocabulary-gap"' \
    '            return False, "nonconforming-reason"' \
    "N2: a local-git-error record is reported in its own bucket (never counted, never confused with a malformed record)"

# F10 (round-4 I6, documented constraint): an honest retry history left side
# by side reads as a conflict -- fails SAFE, never silently trusted.
mkdir -p "$F_DIR/f10_retry"
printf '{"project_id":"f-org/p","outcome":"NOT-MIGRATED","not_migrated_reason":"NOT-MIGRATED (dirty-local)","data_change":"NONE"}' > "$F_DIR/f10_retry/attempt1.json"
python3 "$MKREC" --out "$F_DIR/f10_retry/attempt2.json" --project f-org/p
f_sum "$TOOL" cons_ok.json f10_retry f10
if [ "$F_RC" -ne 0 ] && [ "$(f_get f10 "'f-org/p' in d.get('conflicting_records',{}) and d['coverage_trusted'] is False")" = "true" ]; then
    ok "F10 I6 documented constraint: a retry history (dirty-local then MIGRATED) in one --migrations dir fails SAFE as a conflict -- one record per project is required"
else
    bad "F10 I6: a retry history was silently resolved (rc=$F_RC; see $F_DIR/f10.sum)"
fi

# Archive this run's stdout as the RED evidence per Test Discipline.
{
    echo "T167 RED run; candidate fingerprint=$FINGERPRINT; date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "PASS=$PASS FAIL=$FAIL BEHIND_LIVE=$BEHIND_LIVE"
} > "$EVDIR/test_consumer_audit_red.$(date -u +%Y%m%dT%H%M%SZ).log" 2>/dev/null || true

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
