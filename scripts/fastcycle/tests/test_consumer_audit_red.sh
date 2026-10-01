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
    cat > "$D_MIGDIR/dup_$i.json" <<EOF
{"schema":"consumer-migration/v1","project_id":"HelixDevelopment/ota","outcome":"MIGRATED","data_change":"NONE","commit":"deadbeef","verification":[{"path":"v1.json","overall":"CLEAN","body_hash":"abc"},{"path":"v2.json","overall":"CLEAN","body_hash":"abc"}]}
EOF
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

# --- D2b/D2c: T177 Round 2 R2-I6(b) -- duplicate-record resolution by
# REAL MTIME (most-recent-write-wins), never by lexicographic FILENAME
# order; and a MIGRATED claim carrying NO genuine double-verify evidence
# is never silently counted. Reviewer's exact repro: an alphabetically
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
    ok "D2b R2-I6(b) mtime-wins dedup: the genuinely MORE RECENT record (a_new.json, NOT-MIGRATED) is the one counted for HelixDevelopment/ota, never the alphabetically-later-but-chronologically-STALE z_stale.json's bare MIGRATED claim"
else
    bad "D2b R2-I6(b) mtime-wins dedup: summary did not resolve the duplicate by real recency (rc=$D2B_RC out=$D2B_OUT; see $WORK/d_summary3.json)"
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
reasons = d.get('not_migrated_by_reason', {})
ok = d.get('migrated') == 0 and reasons.get('record-missing-verification-evidence') == 1
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
