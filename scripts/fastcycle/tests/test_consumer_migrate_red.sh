#!/bin/sh
# =============================================================================
# T168 RED test (SpecKit-004 "fast-dev-cycles", Phase 10 / User Story 8;
# plan.md T-G05; FR-025, SC-010).
# =============================================================================
#
# Purpose: prove, BEFORE T-G05's `consumers/migrate.sh` implementation
# exists, that:
#   (A) the tool is genuinely absent today (control needle: measured, not
#       assumed -- §11.4.6; `constitution/scripts/fastcycle/consumers/` is
#       confirmed to hold nothing but `.gitkeep`);
#   (B) the underlying MECHANISMS the real tool will rely on -- `git
#       status --porcelain` dirty-tree detection, and a real bare remote
#       with a `pre-receive` hook that rejects every push -- are genuinely
#       sound on this host, proven by REAL git invocations in Section B
#       against fixtures this file builds itself, never merely assumed
#       (§11.4.273: "the path is part of the instrument");
#   (C) once T-G05 lands, invoking the real tool against the 3 fixtures
#       named in the contract's RED fixtures table (ca_bad_dirty_local,
#       ca_bad_rejecting_remote, ca_good_migrate) produces the outcomes
#       CA-019..CA-028 predict, with NO data change on any non-migration
#       and NO force-push anywhere.
#
# Contract: specs/004-fast-dev-cycles/contracts/consumer-audit-and-migration.md
#   CA-019 (record form) .. CA-028 (dry-run default); common-conventions.md
#   (C-001..C-007). No new CLI contract is invented here -- the contract
#   file already fixes migrate.sh's invocation, preflight refusals, backup,
#   change scope, review/commit/push/verify steps and RED fixture set;
#   this file exercises exactly those.
#
# Task line (tasks.md T168, verbatim): "[P] [US8] [TDD] [SUBAGENT] RED test
# constitution/scripts/fastcycle/tests/test_consumer_migrate_red.sh (dirty
# local tree -> NOT-MIGRATED (dirty-local) and tree hash before == after;
# rejecting remote -> NOT-MIGRATED, nothing force-pushed; golden: a clean
# fixture consumer migrates and verifies CLEAN x2) (plan T-G05; FR-025,
# SC-010)".
#
# Producer != Verifier (§11.4.240): this file writes ONLY the RED test +
# its fixture builder under fixtures/consumer_migrate/build_fixtures.sh.
# It does NOT implement consumers/migrate.sh (T-G05/T174, a separate later
# task dispatched to its own reviewer), and never fabricates a
# tool-invocation result -- every scenario below is either (a) a real git
# invocation this file performs itself against real, freshly-built local
# bare-remote + checkout fixtures (Section B, self-validating the
# underlying mechanisms), or (b) a real invocation of the (today, absent)
# migrate.sh tool, reported RED because the tool cannot be found.
#
# Exit: 0 all as expected; 1 any FAIL recorded (today: RED, expected
#       FAIL>0 for every Section C "tool invocation" check -- Section B's
#       self-checks of the dirty-tree/pre-receive-hook MECHANISMS are
#       expected to PASS today, since they exercise only real git, not the
#       absent tool).
# =============================================================================

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/consumers/migrate.sh"
FIXDIR="$HERE/fixtures/consumer_migrate"
BUILDER="$FIXDIR/build_fixtures.sh"
VERIFY_TOOL="$FC/verify/repo_verify.py"
EVDIR="$REPO_ROOT/qa-results/fastcycle/us8/red"
mkdir -p "$EVDIR" 2>/dev/null || true
FINGERPRINT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T168 RED: consumer migration (plan T-G05; FR-025, SC-010); candidate fingerprint=$FINGERPRINT =="

# =============================================================================
# Section A -- control needles (§11.4.273): confirm the CURRENT, REAL state
# of the checkout, not an assumption.
# =============================================================================
if [ -f "$TOOL" ]; then
    echo "ok tool exists at $TOOL -- T-G05 has landed; Section C's real"
    echo "   invocation checks below are the functional tests to run"
else
    echo "RED: $TOOL is absent -- T-G05 (consumers/migrate.sh) has not"
    echo "     landed yet, confirming this file's own premise is real, not"
    echo "     assumed"
fi

if [ -d "$FC/consumers" ]; then
    NON_GITKEEP=$(find "$FC/consumers" -maxdepth 1 -type f ! -name '.gitkeep' 2>/dev/null | wc -l)
    if [ "$NON_GITKEEP" -eq 0 ]; then
        ok "control needle: $FC/consumers/ genuinely holds nothing but"
        echo "   .gitkeep -- confirms migrate.sh is absent by DIRECTORY"
        echo "   CONTENT, not merely by the single-path check above"
    else
        echo "NOTE: $FC/consumers/ holds $NON_GITKEEP non-.gitkeep file(s)"
        echo "      already -- re-check whether T-G03/T-G04/T-G05 has"
        echo "      partially landed"
    fi
else
    bad "control needle FAILED: $FC/consumers/ does not exist at all"
fi

if [ ! -x "$BUILDER" ] && [ ! -f "$BUILDER" ]; then
    bad "control needle FAILED: $BUILDER fixture builder is missing"
    exit 1
else
    ok "control needle: $BUILDER fixture builder is present"
fi

if [ -f "$VERIFY_TOOL" ]; then
    echo "NOTE: $VERIFY_TOOL (recursive verifier, CA-026) already exists --"
    echo "      Section C's golden-migrate check can exercise the real"
    echo "      double-verify, not just report it absent"
else
    echo "NOTE: $VERIFY_TOOL (recursive verifier, CA-026, plan T-G06/T-G07)"
    echo "      is not yet present -- Section C's golden-migrate check will"
    echo "      report that step RED too, honestly, until it lands"
fi

# =============================================================================
# Section B -- build real fixtures and self-validate the underlying git
# MECHANISMS (§11.4.107(10)/§11.4.273) they rely on, BEFORE any claim is
# made about what the (absent) real migrate.sh tool should do with them.
# =============================================================================
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FIXWORK="$WORK/fixtures"

if sh "$BUILDER" "$FIXWORK" >"$WORK/build.log" 2>&1; then
    ok "fixture builder: real bare-remote + checkout fixtures built successfully under $FIXWORK"
else
    bad "fixture builder FAILED (see $WORK/build.log) -- cannot proceed with Section B/C"
    cat "$WORK/build.log"
    echo ""
    echo "== Summary: ok $PASS / NOT ok $FAIL =="
    exit 1
fi

MANIFEST="$FIXWORK/manifest.json"
GOOD_CHECKOUT=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_good_migrate']['checkout'])")
GOOD_REMOTE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_good_migrate']['remote'])")
DIRTY_CHECKOUT=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_bad_dirty_local']['checkout'])")
DIRTY_REMOTE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_bad_dirty_local']['remote'])")
REJECT_CHECKOUT=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_bad_rejecting_remote']['checkout'])")
REJECT_REMOTE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['fixtures']['ca_bad_rejecting_remote']['remote'])")
OLD_SHA=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['old_sha'])")
NEW_SHA=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['new_sha'])")

# -- B1: dirty-tree detection mechanism (`git status --porcelain`)
if [ -n "$(git -C "$DIRTY_CHECKOUT" status --porcelain=v1 2>/dev/null)" ]; then
    ok "B1 mechanism self-check: ca_bad_dirty_local's checkout genuinely"
    echo "   has an uncommitted file, real per 'git status --porcelain' --"
    echo "   the dirty-tree-detection mechanism CA-020 relies on is sound"
else
    bad "B1 mechanism self-check FAILED: ca_bad_dirty_local's checkout is"
    echo "   NOT actually dirty -- the fixture builder's premise is broken"
fi
if [ -n "$(git -C "$GOOD_CHECKOUT" status --porcelain=v1 2>/dev/null)" ]; then
    bad "B1b mechanism self-check FAILED: ca_good_migrate's checkout is"
    echo "   unexpectedly dirty -- the golden fixture must start clean"
else
    ok "B1b mechanism self-check: ca_good_migrate's checkout is genuinely clean"
fi

# -- B2: remote-rejection mechanism (a real pre-receive hook + a real push
# attempt, proving both that the hook rejects AND that the remote's ref
# genuinely does not move -- i.e. nothing gets force-pushed through it).
REJECT_REF_BEFORE=$(git -C "$REJECT_REMOTE" rev-parse refs/heads/main 2>/dev/null)
( cd "$REJECT_CHECKOUT" \
    && echo "probe" > probe.txt \
    && git add probe.txt \
    && git commit -q -m "probe commit (never expected to land)" \
    && git push origin main >"$WORK/reject_push.log" 2>&1 )
REJECT_PUSH_RC=$?
REJECT_REF_AFTER=$(git -C "$REJECT_REMOTE" rev-parse refs/heads/main 2>/dev/null)
if [ "$REJECT_PUSH_RC" -ne 0 ] && [ "$REJECT_REF_BEFORE" = "$REJECT_REF_AFTER" ] && grep -qi 'rejected' "$WORK/reject_push.log"; then
    ok "B2 mechanism self-check: a real push into ca_bad_rejecting_remote's"
    echo "   bare repo is genuinely rejected by its pre-receive hook, and"
    echo "   the remote's ref is UNCHANGED before/after ($REJECT_REF_BEFORE)"
    echo "   -- the remote-rejection mechanism CA-020/CA-025 relies on is"
    echo "   proven sound"
else
    bad "B2 mechanism self-check FAILED: the fixture remote did not"
    echo "   genuinely reject the probe push (rc=$REJECT_PUSH_RC"
    echo "   before=$REJECT_REF_BEFORE after=$REJECT_REF_AFTER)"
fi
# Reset the probe commit out of the checkout so it does not leak into
# Section C's golden-path reasoning about this same fixture family.
git -C "$REJECT_CHECKOUT" reset -q --hard HEAD~1 2>/dev/null || true

if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 not found -- cannot run the manifest/JSON checks above and below"
fi

# =============================================================================
# Section C -- real invocations of the (today, absent) migrate.sh tool
# against the 3 real fixtures built in Section B. Every check here is a
# REAL command execution against contract-shaped args, so the moment
# T-G05 lands, these checks self-flip GREEN with no further edits to this
# file.
# =============================================================================
CFG="$REPO_ROOT/config/fastcycle/fastcycle.yaml"

# A minimal, clearly test-fixture-only GO review-verdict file (CA-024).
# migrate.sh itself performs no review (producer != verifier, §11.4.240);
# it only checks a caller-supplied record's top-level {"verdict":"GO"} --
# this file exists to exercise that check honestly, never as a claim that
# a real Opus-xhigh review ran over these synthetic fixture commits.
REVIEW_REF="$WORK/fixture_review_go.json"
cat > "$REVIEW_REF" <<'EOF'
{"schema":"review-verdict-fixture/v1","verdict":"GO","note":"T168 RED-test fixture only -- not a real review record"}
EOF

run_tool() {
    if [ -f "$TOOL" ]; then
        sh "$TOOL" "$@" 2>&1
        return $?
    fi
    echo "migrate.sh absent"
    return 127
}

tree_hash() {
    # A content fingerprint of the WHOLE checkout (tracked + untracked,
    # excluding .git) -- used to prove "no data change" on a refusal.
    ( cd "$1" && find . -path ./.git -prune -o -type f -print0 2>/dev/null \
        | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}' )
}

# --- C1: dirty-local -- NOT-MIGRATED (dirty-local), tree hash unchanged
DIRTY_HASH_BEFORE=$(tree_hash "$DIRTY_CHECKOUT")
C1_OUT=$(run_tool --config "$CFG" --project "fixture/ca_bad_dirty_local" \
    --workdir "$DIRTY_CHECKOUT" --out "$WORK/dirty_migration.json" --apply); C1_RC=$?
DIRTY_HASH_AFTER=$(tree_hash "$DIRTY_CHECKOUT")
if [ "$C1_RC" -eq 1 ] && echo "$C1_OUT" | grep -q 'NOT-MIGRATED (dirty-local)' \
    && [ "$DIRTY_HASH_BEFORE" = "$DIRTY_HASH_AFTER" ]; then
    ok "C1 dirty-local: migrate.sh recorded NOT-MIGRATED (dirty-local) and the checkout's tree hash is unchanged"
else
    bad "C1 dirty-local: migrate.sh did not record NOT-MIGRATED (dirty-local) with an unchanged tree hash (rc=$C1_RC out=$C1_OUT before=$DIRTY_HASH_BEFORE after=$DIRTY_HASH_AFTER)"
fi

# --- C2: rejecting-remote -- NOT-MIGRATED (push: ...), nothing force-pushed
REJECT_REF_C2_BEFORE=$(git -C "$REJECT_REMOTE" rev-parse refs/heads/main 2>/dev/null)
C2_OUT=$(run_tool --config "$CFG" --project "fixture/ca_bad_rejecting_remote" \
    --workdir "$REJECT_CHECKOUT" --out "$WORK/reject_migration.json" --apply --review-ref "$REVIEW_REF"); C2_RC=$?
REJECT_REF_C2_AFTER=$(git -C "$REJECT_REMOTE" rev-parse refs/heads/main 2>/dev/null)
if [ "$C2_RC" -eq 1 ] && echo "$C2_OUT" | grep -q 'NOT-MIGRATED (push:' \
    && [ "$REJECT_REF_C2_BEFORE" = "$REJECT_REF_C2_AFTER" ]; then
    ok "C2 rejecting-remote: migrate.sh recorded NOT-MIGRATED (push: ...) and the remote ref is unchanged (nothing force-pushed)"
else
    bad "C2 rejecting-remote: migrate.sh did not record NOT-MIGRATED (push: ...) with an unchanged remote ref (rc=$C2_RC out=$C2_OUT before=$REJECT_REF_C2_BEFORE after=$REJECT_REF_C2_AFTER)"
fi
# Also assert the remote's reflog/tip never shows the fixture's target
# NEW_SHA -- i.e. a force-push disguised as "success" would still be caught.
if [ "$REJECT_REF_C2_AFTER" != "$NEW_SHA" ]; then
    ok "C2b rejecting-remote: the remote's tip never became the migration's NEW_SHA -- confirms no disguised force-push landed"
else
    bad "C2b rejecting-remote: the remote's tip unexpectedly equals NEW_SHA -- a push landed despite the rejecting hook"
fi

# --- C3: golden -- ca_good_migrate migrates (MIGRATED), gitlink bumped to
# NEW_SHA, and the recursive verifier (CA-026) reports CLEAN twice with
# equal body_hash.
C3_OUT=$(run_tool --config "$CFG" --project "fixture/ca_good_migrate" \
    --workdir "$GOOD_CHECKOUT" --out "$WORK/good_migration.json" --apply --review-ref "$REVIEW_REF"); C3_RC=$?
if [ "$C3_RC" -eq 0 ] && echo "$C3_OUT" | grep -q 'MIGRATED' && ! echo "$C3_OUT" | grep -q 'NOT-MIGRATED'; then
    ok "C3a golden: migrate.sh reports MIGRATED for ca_good_migrate"
    GITLINK_AFTER=$(git -C "$GOOD_CHECKOUT" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
    if [ "$GITLINK_AFTER" = "$NEW_SHA" ]; then
        ok "C3b golden: the consumer's constitution gitlink was bumped to the migration target ($NEW_SHA)"
    else
        bad "C3b golden: the consumer's constitution gitlink is '$GITLINK_AFTER', expected $NEW_SHA"
    fi
    if [ -f "$VERIFY_TOOL" ]; then
        python3 "$VERIFY_TOOL" --recursive --root "$GOOD_CHECKOUT" --out "$WORK/verify1.json" >"$WORK/verify1.log" 2>&1; V1_RC=$?
        python3 "$VERIFY_TOOL" --recursive --root "$GOOD_CHECKOUT" --out "$WORK/verify2.json" >"$WORK/verify2.log" 2>&1; V2_RC=$?
        OVERALL1=$(python3 -c "import json; print(json.load(open('$WORK/verify1.json')).get('overall',''))" 2>/dev/null)
        OVERALL2=$(python3 -c "import json; print(json.load(open('$WORK/verify2.json')).get('overall',''))" 2>/dev/null)
        if [ "$V1_RC" -eq 0 ] && [ "$V2_RC" -eq 0 ] \
            && [ "$OVERALL1" = "CLEAN" ] && [ "$OVERALL2" = "CLEAN" ]; then
            H1=$(python3 -c "import json; print(json.load(open('$WORK/verify1.json')).get('body_hash',''))" 2>/dev/null)
            H2=$(python3 -c "import json; print(json.load(open('$WORK/verify2.json')).get('body_hash',''))" 2>/dev/null)
            if [ -n "$H1" ] && [ "$H1" = "$H2" ]; then
                ok "C3c golden (CA-026): repo_verify.py --recursive reports CLEAN twice with equal body_hash ($H1)"
            else
                bad "C3c golden (CA-026): repo_verify.py --recursive CLEAN both times but body_hash differs or unreadable (h1=$H1 h2=$H2)"
            fi
        else
            bad "C3c golden (CA-026): repo_verify.py --recursive did not report CLEAN twice (rc1=$V1_RC overall1=$OVERALL1 rc2=$V2_RC overall2=$OVERALL2; logs $WORK/verify1.log $WORK/verify2.log)"
        fi
    else
        bad "C3c golden (CA-026): $VERIFY_TOOL is not present yet -- cannot double-verify"
    fi
else
    bad "C3a golden: migrate.sh did not report MIGRATED for ca_good_migrate (rc=$C3_RC out=$C3_OUT)"
fi

# --- C4: C-006 static safety check -- migrate.sh's OWN SOURCE must never
# contain a force-push / force-with-lease / '+refspec' / reset --hard /
# stash / clean invocation (C-006: "a code path that could is a contract
# violation detectable by grep of the tool source"). This is the paired-
# mutation-observable half of the C2/C2b dynamic no-force-push proof: the
# fixture's pre-receive hook rejects every push unconditionally (force or
# not), so a mutation that adds a `--force` retry on rejection is NOT
# distinguishable from C2/C2b alone -- it IS distinguishable here.
if [ -f "$TOOL" ]; then
    if grep -nE -- '--force(-with-lease)?\b|push[^|]*\+[A-Za-z]|reset[[:space:]]+--hard|git[[:space:]]+stash|git[[:space:]]+clean' "$TOOL" | grep -v '^\s*#'; then
        bad "C4 C-006 static safety: $TOOL's source contains a forbidden force-push/reset-hard/stash/clean invocation"
    else
        ok "C4 C-006 static safety: $TOOL's source contains no force-push/force-with-lease/+refspec/reset-hard/stash/clean invocation"
    fi
else
    bad "C4 C-006 static safety: $TOOL is absent -- cannot grep its source"
fi

# Archive this run's stdout as the RED evidence per Test Discipline.
{
    echo "T168 RED run; candidate fingerprint=$FINGERPRINT; date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "PASS=$PASS FAIL=$FAIL OLD_SHA=$OLD_SHA NEW_SHA=$NEW_SHA"
} > "$EVDIR/test_consumer_migrate_red.$(date -u +%Y%m%dT%H%M%SZ).log" 2>/dev/null || true

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
