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

# A minimal, clearly test-fixture-only GO review-verdict file (CA-024),
# BOUND to a specific project_id + target_commit (T177 Round 1 I6:
# migrate.sh's review-ref check now requires this binding, never accepts
# an unbound {"verdict":"GO"}). migrate.sh itself performs no review
# (producer != verifier, §11.4.240); this helper exists to exercise that
# bound check honestly, never as a claim that a real Opus-xhigh review
# ran over these synthetic fixture commits.
make_review_ref() {
    # $1=project_id $2=target_commit -> prints the path of a fresh,
    # correctly-bound review-ref fixture file.
    out="$WORK/fixture_review_go_$(echo "$1" | tr '/' '_').json"
    python3 - "$out" "$1" "$2" <<'PYEOF'
import json, sys
out, project, target = sys.argv[1:4]
doc = {
    "schema": "review-verdict-fixture/v1",
    "verdict": "GO",
    "project_id": project,
    "target_commit": target,
    "note": "T168 RED-test fixture only -- not a real review record",
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh)
PYEOF
    echo "$out"
}
# Legacy shared unbound fixture -- kept ONLY for Section D (the worktree
# fixture is refused at the earlier backup step and never reaches
# review, so binding is irrelevant there) and as the C2b-adjacent
# negative-control input for the new C2c check below (an unbound record
# MUST now be refused even where it previously would have passed).
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
REJECT_REVIEW_REF=$(make_review_ref "fixture/ca_bad_rejecting_remote" "$NEW_SHA")
REJECT_REF_C2_BEFORE=$(git -C "$REJECT_REMOTE" rev-parse refs/heads/main 2>/dev/null)
C2_OUT=$(run_tool --config "$CFG" --project "fixture/ca_bad_rejecting_remote" \
    --workdir "$REJECT_CHECKOUT" --out "$WORK/reject_migration.json" --apply --review-ref "$REJECT_REVIEW_REF"); C2_RC=$?
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
GOOD_REVIEW_REF=$(make_review_ref "fixture/ca_good_migrate" "$NEW_SHA")
C3_OUT=$(run_tool --config "$CFG" --project "fixture/ca_good_migrate" \
    --workdir "$GOOD_CHECKOUT" --out "$WORK/good_migration.json" --apply --review-ref "$GOOD_REVIEW_REF"); C3_RC=$?
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
#
# T177 Round 1 I3 fix: the prior grep pattern ('--force(-with-lease)?\b'
# and 'push[^|]*\+[A-Za-z]') missed TWO real bypass shapes a reviewer
# demonstrated LIVE keep T168 at 18/18: (a) the short `-f` flag (`push -f
# "$r" ...` -- `--force` never matches a bare `-f`), and (b) a `+`-prefixed
# refspec whose first character after `+` is a shell-variable sigil, not a
# letter (`push "$r" "+$BRANCH":"$BRANCH"` -- the old pattern required a
# literal letter immediately after `+`). The widened pattern below scopes
# the `-f` detection to lines that ALSO mention `push` (a bare `-f\b`
# would false-positive on this script's own `[ -f "$HOOK" ]`-style test
# flags, which are unrelated to git-push), and widens the `+refspec`
# detection to accept `$`/quote-prefixed refspecs, not only bare letters.
FORCE_PUSH_RE='push[^|]*(--force(-with-lease)?\b|[[:space:]]-f([[:space:]]|"|$)|\+[A-Za-z0-9_$"'"'"'])|reset[[:space:]]+--hard|git[[:space:]]+stash|git[[:space:]]+clean'
if [ -f "$TOOL" ]; then
    if grep -nE -- "$FORCE_PUSH_RE" "$TOOL" | grep -v '^\s*#'; then
        bad "C4 C-006 static safety: $TOOL's source contains a forbidden force-push/reset-hard/stash/clean invocation"
    else
        ok "C4 C-006 static safety: $TOOL's source contains no force-push/force-with-lease/+refspec/reset-hard/stash/clean invocation"
    fi
else
    bad "C4 C-006 static safety: $TOOL is absent -- cannot grep its source"
fi

# --- C4b/C4c: I3 guard-viability -- prove the WIDENED grep genuinely
# catches BOTH bypass shapes the reviewer found, on throwaway scratch
# copies of the tool source (never the tracked file). A grep that cannot
# catch its own target defect class on a synthetic positive is itself
# the defect.
C4B_SCRATCH="$WORK/c4b_force_f_flag.sh"
sed 's/git -C "\$WORKDIR" push "\$r" "\$BRANCH":"\$BRANCH"/git -C "$WORKDIR" push -f "$r" "$BRANCH":"$BRANCH"/' "$TOOL" > "$C4B_SCRATCH" 2>/dev/null
if [ -f "$C4B_SCRATCH" ] && ! cmp -s "$C4B_SCRATCH" "$TOOL" && grep -nE -- "$FORCE_PUSH_RE" "$C4B_SCRATCH" | grep -qv '^\s*#'; then
    ok "C4b I3 guard-viability: the widened C4 grep genuinely flags a 'push -f' short-flag bypass injected into a scratch copy"
else
    bad "C4b I3 guard-viability: the widened C4 grep did NOT flag a 'push -f' short-flag bypass (sed substitution may not have matched -- re-derive the anchor)"
fi
C4C_SCRATCH="$WORK/c4c_force_plus_var.sh"
sed 's/git -C "\$WORKDIR" push "\$r" "\$BRANCH":"\$BRANCH"/git -C "$WORKDIR" push "$r" "+$BRANCH":"$BRANCH"/' "$TOOL" > "$C4C_SCRATCH" 2>/dev/null
if [ -f "$C4C_SCRATCH" ] && ! cmp -s "$C4C_SCRATCH" "$TOOL" && grep -nE -- "$FORCE_PUSH_RE" "$C4C_SCRATCH" | grep -qv '^\s*#'; then
    ok "C4c I3 guard-viability: the widened C4 grep genuinely flags a '+\$BRANCH' variable-prefixed force-refspec bypass injected into a scratch copy"
else
    bad "C4c I3 guard-viability: the widened C4 grep did NOT flag a '+\$BRANCH' force-refspec bypass (sed substitution may not have matched -- re-derive the anchor)"
fi

# --- C5: I6 negative control -- an UNBOUND review-ref (no project_id/
# target_commit fields, the exact {"verdict":"GO"} shape a prior version
# of migrate.sh accepted unconditionally) MUST now be refused even for an
# otherwise-migratable target. A disposable clone of ca_bad_dirty_local's
# own REMOTE (never pushed to -- only its LOCAL checkout is dirty, so the
# remote is still genuinely at OLD_SHA) is used, so this exercises the
# real gitlink-bump -> review path; GOOD_REMOTE is already at NEW_SHA by
# this point in the file (C3's own real migration already pushed it),
# which would take the ALREADY_AT_TARGET/verify-only shortcut and never
# reach the review check at all -- a test-construction bug found live
# while authoring this section.
C5_CHECKOUT="$WORK/c5_unbound_review_checkout"
git clone -q --no-hardlinks "$DIRTY_REMOTE" "$C5_CHECKOUT" >/dev/null 2>&1
git -C "$C5_CHECKOUT" config user.name fastcycle-fixture 2>/dev/null
git -C "$C5_CHECKOUT" config user.email fixture@example.invalid 2>/dev/null
if [ -d "$C5_CHECKOUT/.git" ]; then
    C5_OUT=$(run_tool --config "$CFG" --project "fixture/ca_bad_dirty_local" \
        --workdir "$C5_CHECKOUT" --out "$WORK/c5_migration.json" --apply --review-ref "$REVIEW_REF"); C5_RC=$?
    if [ "$C5_RC" -eq 1 ] && echo "$C5_OUT" | grep -q 'NOT-MIGRATED (review: review-no-go)'; then
        ok "C5 I6 negative control: an unbound {\"verdict\":\"GO\"} review-ref (no project_id/target_commit) is correctly refused as review-no-go, even for an otherwise-golden target"
    else
        bad "C5 I6 negative control: an unbound review-ref was NOT refused (rc=$C5_RC out=$C5_OUT) -- the CA-024 binding check regressed"
    fi
else
    bad "C5 I6 negative control: could not build the disposable c5 checkout clone"
fi

# =============================================================================
# Section D -- Gap 1 regression: §9.2 backup must not silently no-op on a
# `git worktree` checkout. Live incident (2026-09-30, found while executing
# T175's consumer audit): $WORKDIR/.git for a genuine `git worktree`
# checkout is a small TEXT FILE ("gitdir: <path>") pointing at the REAL,
# SHARED git-dir, so `cp -al "$WORKDIR/.git" "$BACKUP_DIR"` hardlink-copies
# only that pointer file -- a FALSE SENSE of §9.2 protection while backing
# up nothing. migrate.sh now detects this shape (--git-dir differs from
# --git-common-dir once both resolve to absolute paths) and REFUSES the
# migration honestly at the backup step (reason: backup-failed) rather
# than pretend to protect it. This section builds a REAL worktree fixture
# (a bare repo + a main checkout + a genuine `git worktree add` linked
# checkout of a DIFFERENT branch) and proves: (1) migrate.sh --apply
# refuses with NOT-MIGRATED (backup: backup-failed); (2) the worktree
# checkout's own tree hash is unchanged (no data change, matching C1's
# no-data-change proof for the dirty-local refusal); (3) no
# .fastcycle_migrate_backup_* sibling directory is left behind (the
# refusal happens BEFORE any write is attempted, never a partial/garbage
# backup).
# =============================================================================
D_ROOT=$(mktemp -d)
D_BARE="$D_ROOT/wt_consumer.git"
D_MAIN="$D_ROOT/main_checkout"
D_WT="$D_ROOT/wt_checkout"
git init --bare -q -b main "$D_BARE"
git init -q -b main "$D_MAIN" >/dev/null
git -C "$D_MAIN" config user.name fastcycle-fixture
git -C "$D_MAIN" config user.email fixture@example.invalid
echo "worktree fixture consumer (T168 Section D, Gap 1 regression)" > "$D_MAIN/CLAUDE.md"
git -C "$D_MAIN" add CLAUDE.md
git -C "$D_MAIN" commit -q -m "initial worktree-fixture consumer state"
git -C "$D_MAIN" remote add origin "$D_BARE"
git -C "$D_MAIN" push -q origin main
git -C "$D_MAIN" branch wt-branch
D_WT_BUILD_RC=0
git -C "$D_MAIN" worktree add -q "$D_WT" wt-branch >"$WORK/d_worktree_add.log" 2>&1 || D_WT_BUILD_RC=$?
if [ "$D_WT_BUILD_RC" -ne 0 ] || [ ! -f "$D_WT/.git" ]; then
    bad "D0 worktree fixture: 'git worktree add' did not produce a real .git-as-file linked checkout (rc=$D_WT_BUILD_RC; see $WORK/d_worktree_add.log)"
else
    ok "D0 worktree fixture: real 'git worktree add' checkout built at $D_WT with .git as a linked pointer file"

    D_HASH_BEFORE=$(tree_hash "$D_WT")
    D_BACKUP_GLOB_BEFORE=$(find "$D_ROOT" -maxdepth 1 -name '.fastcycle_migrate_backup_*' 2>/dev/null | wc -l)
    D_OUT=$(run_tool --config "$CFG" --project "fixture/wt_consumer" \
        --workdir "$D_WT" --out "$WORK/d_migration.json" --apply --review-ref "$REVIEW_REF"); D_RC=$?
    D_HASH_AFTER=$(tree_hash "$D_WT")
    D_BACKUP_GLOB_AFTER=$(find "$D_ROOT" -maxdepth 1 -name '.fastcycle_migrate_backup_*' 2>/dev/null | wc -l)

    if [ "$D_RC" -eq 1 ] && echo "$D_OUT" | grep -q 'NOT-MIGRATED (backup: backup-failed)'; then
        ok "D1 worktree backup refusal: migrate.sh recorded NOT-MIGRATED (backup: backup-failed) for a genuine worktree checkout"
    else
        bad "D1 worktree backup refusal: migrate.sh did not refuse a worktree checkout at the backup step (rc=$D_RC out=$D_OUT)"
    fi
    if [ "$D_HASH_BEFORE" = "$D_HASH_AFTER" ]; then
        ok "D2 worktree backup refusal: the worktree checkout's tree hash is unchanged (no data change on refusal)"
    else
        bad "D2 worktree backup refusal: the worktree checkout's tree hash CHANGED on refusal (before=$D_HASH_BEFORE after=$D_HASH_AFTER)"
    fi
    if [ "$D_BACKUP_GLOB_BEFORE" = "$D_BACKUP_GLOB_AFTER" ]; then
        ok "D3 worktree backup refusal: no .fastcycle_migrate_backup_* directory was left behind (refused before any write)"
    else
        bad "D3 worktree backup refusal: a .fastcycle_migrate_backup_* directory appeared despite the refusal (before=$D_BACKUP_GLOB_BEFORE after=$D_BACKUP_GLOB_AFTER)"
    fi
fi
rm -rf "$D_ROOT" 2>/dev/null || true

# =============================================================================
# Section E -- Gap 2 regression: gitlink-bump must resolve the constitution
# submodule by its PATH, never by an assumed ".gitmodules" section name.
# Live finding (2026-09-30, direct .gitmodules inspection during T175):
# this constitution repo's own .gitmodules names the section
# [submodule "constitution"], but a real consumer (HelixDevelopment/ota)
# names the SAME path's section [submodule "HelixConstitution"] instead --
# the prior `git config -f .gitmodules --get submodule.constitution.url`
# lookup returned empty for that shape, wrongly reporting
# NOT-MIGRATED (gitlink-bump: no constitution submodule entry in
# .gitmodules) even though a genuine constitution submodule entry exists.
# This section builds a real golden-path fixture whose .gitmodules uses a
# NON-"constitution" section name for the SAME "constitution" path, and
# proves a full --apply migration still succeeds (MIGRATED, gitlink
# bumped to the real target commit) -- i.e. resolution is genuinely by
# path, not by the section label.
# =============================================================================
E_ROOT=$(mktemp -d)
E_MINI_BARE="$E_ROOT/mini_constitution.git"
git init --bare -q -b main "$E_MINI_BARE"
E_MC_WORK=$(mktemp -d)
git init -q -b main "$E_MC_WORK" >/dev/null
git -C "$E_MC_WORK" config user.name fastcycle-fixture
git -C "$E_MC_WORK" config user.email fixture@example.invalid
echo "old constitution state (Section E)" > "$E_MC_WORK/CLAUDE.md"
git -C "$E_MC_WORK" add CLAUDE.md
git -C "$E_MC_WORK" commit -q -m "old constitution state (Section E)"
git -C "$E_MC_WORK" remote add origin "$E_MINI_BARE"
git -C "$E_MC_WORK" push -q origin main
E_OLD_SHA=$(git -C "$E_MC_WORK" rev-parse HEAD)
echo "new constitution state (Section E migration target)" >> "$E_MC_WORK/CLAUDE.md"
git -C "$E_MC_WORK" add CLAUDE.md
git -C "$E_MC_WORK" commit -q -m "new constitution state (Section E migration target)"
git -C "$E_MC_WORK" push -q origin main
E_NEW_SHA=$(git -C "$E_MC_WORK" rev-parse HEAD)
rm -rf "$E_MC_WORK"

E_BARE="$E_ROOT/consumer.git"
git init --bare -q -b main "$E_BARE"
E_WORK=$(mktemp -d)
git init -q -b main "$E_WORK" >/dev/null
git -C "$E_WORK" config user.name fastcycle-fixture
git -C "$E_WORK" config user.email fixture@example.invalid
cat > "$E_WORK/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section E,
Gap 2 non-canonical .gitmodules section name).

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
# The load-bearing line: the section name is "HelixConstitution", NOT
# "constitution" -- only the `path` value is "constitution".
cat > "$E_WORK/.gitmodules" <<EOF
[submodule "HelixConstitution"]
	path = constitution
	url = $E_MINI_BARE
EOF
git -C "$E_WORK" add CLAUDE.md .gitmodules
git -C "$E_WORK" update-index --add --cacheinfo 160000,"$E_OLD_SHA",constitution
git -C "$E_WORK" commit -q -m "initial Section E consumer state (constitution gitlink=old)"
git -C "$E_WORK" remote add origin "$E_BARE"
git -C "$E_WORK" push -q origin main
rm -rf "$E_WORK"
git clone -q --no-hardlinks "$E_BARE" "$E_ROOT/checkout" >/dev/null 2>&1
git -C "$E_ROOT/checkout" config user.name fastcycle-fixture
git -C "$E_ROOT/checkout" config user.email fixture@example.invalid

E_REVIEW_REF=$(make_review_ref "fixture/section_e_nonstandard_section_name" "$E_NEW_SHA")
E_OUT=$(run_tool --config "$CFG" --project "fixture/section_e_nonstandard_section_name" \
    --workdir "$E_ROOT/checkout" --out "$WORK/e_migration.json" --apply --review-ref "$E_REVIEW_REF"); E_RC=$?
if [ "$E_RC" -eq 0 ] && echo "$E_OUT" | grep -q 'MIGRATED' && ! echo "$E_OUT" | grep -q 'NOT-MIGRATED'; then
    ok "E1 non-canonical .gitmodules section name: migrate.sh reports MIGRATED despite a [submodule \"HelixConstitution\"] (not \"constitution\") section"
    E_GITLINK_AFTER=$(git -C "$E_ROOT/checkout" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
    if [ "$E_GITLINK_AFTER" = "$E_NEW_SHA" ]; then
        ok "E2 non-canonical .gitmodules section name: the constitution gitlink was bumped to the migration target ($E_NEW_SHA), resolved by PATH not section name"
    else
        bad "E2 non-canonical .gitmodules section name: the consumer's constitution gitlink is '$E_GITLINK_AFTER', expected $E_NEW_SHA"
    fi
else
    bad "E1 non-canonical .gitmodules section name: migrate.sh did not report MIGRATED for a [submodule \"HelixConstitution\"] fixture (rc=$E_RC out=$E_OUT)"
fi
rm -rf "$E_ROOT" 2>/dev/null || true

# =============================================================================
# Section F -- T177 Round 1 B3/I4 regression: (1) CA-026's double-verify is
# genuinely LOAD-BEARING inside migrate.sh itself, not merely documented
# or incidentally exercised by this test's OWN separate repo_verify.py
# calls (the exact gap the reviewer found: C3c only proved the MECHANISM
# works when driven directly, never that migrate.sh's OWN step 9 runs
# it); (2) an already-at-target consumer converges to MIGRATED instead of
# looping forever on a spurious "git commit failed" (I4). A dedicated
# mini-constitution + consumer fixture is built fresh here (GOOD_REMOTE
# is already advanced by C3's own successful migration by this point in
# the file, so it can no longer exercise a genuine commit+push+verify
# path).
# =============================================================================
F_ROOT=$(mktemp -d)
F_MINI_BARE="$F_ROOT/mini_constitution.git"
git init --bare -q -b main "$F_MINI_BARE"
F_MC_WORK=$(mktemp -d)
git init -q -b main "$F_MC_WORK" >/dev/null
git -C "$F_MC_WORK" config user.name fastcycle-fixture
git -C "$F_MC_WORK" config user.email fixture@example.invalid
echo "old constitution state (Section F)" > "$F_MC_WORK/CLAUDE.md"
git -C "$F_MC_WORK" add CLAUDE.md
git -C "$F_MC_WORK" commit -q -m "old constitution state (Section F)"
git -C "$F_MC_WORK" remote add origin "$F_MINI_BARE"
git -C "$F_MC_WORK" push -q origin main
F_OLD_SHA=$(git -C "$F_MC_WORK" rev-parse HEAD)
echo "new constitution state (Section F target)" >> "$F_MC_WORK/CLAUDE.md"
git -C "$F_MC_WORK" add CLAUDE.md
git -C "$F_MC_WORK" commit -q -m "new constitution state (Section F target)"
git -C "$F_MC_WORK" push -q origin main
F_NEW_SHA=$(git -C "$F_MC_WORK" rev-parse HEAD)
rm -rf "$F_MC_WORK"

F_BARE="$F_ROOT/consumer.git"
git init --bare -q -b main "$F_BARE"
F_WORK=$(mktemp -d)
git init -q -b main "$F_WORK" >/dev/null
git -C "$F_WORK" config user.name fastcycle-fixture
git -C "$F_WORK" config user.email fixture@example.invalid
cat > "$F_WORK/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section F,
B3 load-bearing verify proof + I4 already-at-target convergence).

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
cat > "$F_WORK/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $F_MINI_BARE
EOF
git -C "$F_WORK" add CLAUDE.md .gitmodules
git -C "$F_WORK" update-index --add --cacheinfo 160000,"$F_OLD_SHA",constitution
git -C "$F_WORK" commit -q -m "initial Section F consumer state (constitution gitlink=old)"
git -C "$F_WORK" remote add origin "$F_BARE"
git -C "$F_WORK" push -q origin main
rm -rf "$F_WORK"
git clone -q --no-hardlinks "$F_BARE" "$F_ROOT/checkout" >/dev/null 2>&1
git -C "$F_ROOT/checkout" config user.name fastcycle-fixture
git -C "$F_ROOT/checkout" config user.email fixture@example.invalid

# --- F1/F2: B3 -- pointing FASTCYCLE_VERIFY_TOOL_OVERRIDE at a nonexistent
# path must turn an otherwise-golden migration into NOT-MIGRATED (verify:
# verification-not-clean), and the commit that landed beforehand must be
# reported honestly (never data_change: NONE) -- proving migrate.sh's OWN
# step 9 genuinely gates on CA-026, not merely documents it.
F_REVIEW_REF=$(make_review_ref "fixture/section_f_verify_load_bearing" "$F_NEW_SHA")
F1_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$WORK/nonexistent_repo_verify.py" run_tool --config "$CFG" --project "fixture/section_f_verify_load_bearing" \
    --workdir "$F_ROOT/checkout" --out "$WORK/f1_migration.json" --apply --review-ref "$F_REVIEW_REF"); F1_RC=$?
if [ "$F1_RC" -eq 1 ] && echo "$F1_OUT" | grep -q 'NOT-MIGRATED (verify: verification-not-clean)'; then
    ok "F1 B3 load-bearing: FASTCYCLE_VERIFY_TOOL_OVERRIDE pointed at a nonexistent path correctly turns an otherwise-golden migration into NOT-MIGRATED (verify: verification-not-clean) -- migrate.sh's own step 9 genuinely gates on CA-026"
else
    bad "F1 B3 load-bearing: verify-tool override did not produce NOT-MIGRATED (verify: verification-not-clean) (rc=$F1_RC out=$F1_OUT)"
fi
# data-model.md #13.3's ConsumerMigrationRecord field table requires
# data_change="NONE" for EVERY NOT-MIGRATED outcome (the working tree
# genuinely has no UNCOMMITTED residue here -- the commit already landed
# cleanly); the landed commit itself is carried by the DEDICATED
# `commit` field, which MUST still be present despite the terminal
# outcome being NOT-MIGRATED (T177 Round 1 I1+I2, corrected to respect
# this exact contract clause rather than violate it).
if python3 -c "
import json
d = json.load(open('$WORK/f1_migration.json'))
import sys
ok = d.get('outcome') == 'NOT-MIGRATED' and bool(d.get('commit')) and d.get('data_change') == 'NONE'
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "F2 B3+I1 honesty: the F1 refusal record still names the real landed commit via the dedicated 'commit' field (data_change correctly stays NONE per data-model.md #13.3 -- no UNCOMMITTED residue) even though the terminal outcome is NOT-MIGRATED"
else
    bad "F2 B3+I1 honesty: the F1 refusal record did not honestly report the landed commit (or violated data_change=NONE) (see $WORK/f1_migration.json)"
fi

# --- F3: I4 -- a SECOND, fresh clone of the now-bumped F_BARE (gitlink
# already at F_NEW_SHA after F1's real commit+push) must converge to
# MIGRATED via the already-at-target/verify-only path, never loop on a
# spurious "git commit failed".
F_CHECKOUT2="$F_ROOT/checkout2"
git clone -q --no-hardlinks "$F_BARE" "$F_CHECKOUT2" >/dev/null 2>&1
git -C "$F_CHECKOUT2" config user.name fastcycle-fixture 2>/dev/null
git -C "$F_CHECKOUT2" config user.email fixture@example.invalid 2>/dev/null
F3_OUT=$(run_tool --config "$CFG" --project "fixture/section_f_verify_load_bearing" \
    --workdir "$F_CHECKOUT2" --out "$WORK/f3_migration.json" --apply); F3_RC=$?
if [ "$F3_RC" -eq 0 ] && echo "$F3_OUT" | grep -q 'MIGRATED' && ! echo "$F3_OUT" | grep -q 'NOT-MIGRATED'; then
    ok "F3 I4 already-at-target convergence: a fresh clone already at the migration target converges to MIGRATED via the verify-only path (no spurious 'git commit failed')"
else
    bad "F3 I4 already-at-target convergence: an already-at-target consumer did NOT converge to MIGRATED (rc=$F3_RC out=$F3_OUT)"
fi

# =============================================================================
# Section G -- T177 Round 1 I2 regression: EVERY configured remote is
# attempted, even after an earlier one rejects (CA-025: "remaining
# remotes ... proceed"). A consumer with TWO remotes is built -- the
# first ("origin") rejects every push via the same real pre-receive hook
# mechanism Section B/C2 already proved sound, the second ("second")
# genuinely accepts. Reusing F_MINI_BARE/F_OLD_SHA/F_NEW_SHA (the F_ROOT
# cleanup below covers both sections).
# =============================================================================
G_BARE_REJECT="$F_ROOT/g_remote_reject.git"
git init --bare -q -b main "$G_BARE_REJECT"
# The rejecting hook is installed ONLY AFTER the initial consumer state is
# seeded below (mirroring build_fixtures.sh's own ca_bad_rejecting_remote
# construction) -- installing it first would ALSO reject the seeding
# push itself, leaving this remote permanently empty (no CLAUDE.md, no
# .gitmodules at all), a genuine test-construction bug found live while
# authoring this section (the clone then legitimately had no .gitmodules
# to find, an accurate but misleading "no .gitmodules" refusal).
G_BARE_ACCEPT="$F_ROOT/g_remote_accept.git"
git init --bare -q -b main "$G_BARE_ACCEPT"

G_WORK=$(mktemp -d)
git init -q -b main "$G_WORK" >/dev/null
git -C "$G_WORK" config user.name fastcycle-fixture
git -C "$G_WORK" config user.email fixture@example.invalid
cat > "$G_WORK/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section G,
I2 push-to-all-remotes-even-after-a-rejection proof).

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
cat > "$G_WORK/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $F_MINI_BARE
EOF
git -C "$G_WORK" add CLAUDE.md .gitmodules
git -C "$G_WORK" update-index --add --cacheinfo 160000,"$F_OLD_SHA",constitution
git -C "$G_WORK" commit -q -m "initial Section G consumer state (constitution gitlink=old)"
git -C "$G_WORK" remote add origin "$G_BARE_REJECT"
git -C "$G_WORK" push -q origin main
rm -rf "$G_WORK"
# NOW install the rejecting hook -- the seeding push above already landed.
cat > "$G_BARE_REJECT/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "rejected by Section G fixture pre-receive hook" >&2
exit 1
EOF
chmod +x "$G_BARE_REJECT/hooks/pre-receive"
git clone -q --no-hardlinks "$G_BARE_REJECT" "$F_ROOT/g_checkout" >/dev/null 2>&1
git -C "$F_ROOT/g_checkout" config user.name fastcycle-fixture
git -C "$F_ROOT/g_checkout" config user.email fixture@example.invalid
git -C "$F_ROOT/g_checkout" remote add second "$G_BARE_ACCEPT"

G_ACCEPT_BEFORE=$(git -C "$G_BARE_ACCEPT" rev-parse refs/heads/main 2>/dev/null)
G_REJECT_BEFORE=$(git -C "$G_BARE_REJECT" rev-parse refs/heads/main 2>/dev/null)
G_REVIEW_REF=$(make_review_ref "fixture/section_g_multi_remote" "$F_NEW_SHA")
G_OUT=$(run_tool --config "$CFG" --project "fixture/section_g_multi_remote" \
    --workdir "$F_ROOT/g_checkout" --out "$WORK/g_migration.json" --apply --review-ref "$G_REVIEW_REF"); G_RC=$?
G_ACCEPT_AFTER=$(git -C "$G_BARE_ACCEPT" rev-parse refs/heads/main 2>/dev/null)
G_REJECT_AFTER=$(git -C "$G_BARE_REJECT" rev-parse refs/heads/main 2>/dev/null)

if [ "$G_RC" -eq 1 ] && echo "$G_OUT" | grep -q 'NOT-MIGRATED (push:'; then
    ok "G1 I2 overall outcome: the mixed-remote migration correctly reports NOT-MIGRATED (push: ...) (one remote genuinely rejected)"
else
    bad "G1 I2 overall outcome: unexpected result for the mixed-remote fixture (rc=$G_RC out=$G_OUT)"
fi
if [ -n "$G_ACCEPT_AFTER" ] && [ "$G_ACCEPT_AFTER" != "$G_ACCEPT_BEFORE" ]; then
    ok "G2 I2 all-remotes-attempted: the SECOND remote's tip genuinely advanced ($G_ACCEPT_BEFORE -> $G_ACCEPT_AFTER) despite the FIRST remote rejecting -- migrate.sh tried both, never stopping at the first rejection"
else
    bad "G2 I2 all-remotes-attempted: the second (accepting) remote's tip did NOT advance (before=$G_ACCEPT_BEFORE after=$G_ACCEPT_AFTER) -- migrate.sh stopped at the first rejection instead of trying every configured remote"
fi
if [ "$G_REJECT_AFTER" = "$G_REJECT_BEFORE" ]; then
    ok "G3 I2 no force-push: the rejecting remote's tip is unchanged (nothing force-pushed through it)"
else
    bad "G3 I2 no force-push: the rejecting remote's tip CHANGED (before=$G_REJECT_BEFORE after=$G_REJECT_AFTER)"
fi
# The per-remote breakdown lives in the additive `push_results` field
# (data_change stays NONE per data-model.md #13.3, since the working
# tree genuinely has no uncommitted residue -- only the landed commit,
# already carried by the `commit` field); T177 Round 1 I2 correction.
if python3 -c "
import json, sys
d = json.load(open('$WORK/g_migration.json'))
pr = ','.join(d.get('push_results') or [])
ok = 'second:pushed' in pr and 'origin:' in pr and d.get('data_change') == 'NONE' and bool(d.get('commit'))
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "G4 I2 per-remote honesty: the migration record's push_results names both the successful remote (second:pushed) and the rejected one (origin:...), the commit field names the local commit that landed, and data_change correctly stays NONE"
else
    bad "G4 I2 per-remote honesty: the migration record did not honestly break down per-remote outcomes (see $WORK/g_migration.json)"
fi

# =============================================================================
# Section H -- T177 Round 1 B2 + I5 regression: (1) post_update_hook.sh
# MUST run against the CONSUMER ($WORKDIR), never the caller's own
# ambient cwd (B2); (2) a consumer-declared "Consumer gates: <script>"
# marker is genuinely discovered and run, and a failing gate script
# blocks the migration as consumer-gates-red (I5). A dedicated
# mini-constitution carrying a real scripts/post_update_hook.sh stub
# (the hook the REAL constitution ships, but this fixture needs only a
# minimal stand-in that records its own real `pwd`) is built fresh.
# =============================================================================
H_ROOT=$(mktemp -d)
H_MINI_BARE="$H_ROOT/mini_constitution.git"
git init --bare -q -b main "$H_MINI_BARE"
H_MC_WORK=$(mktemp -d)
git init -q -b main "$H_MC_WORK" >/dev/null
git -C "$H_MC_WORK" config user.name fastcycle-fixture
git -C "$H_MC_WORK" config user.email fixture@example.invalid
echo "old constitution state (Section H)" > "$H_MC_WORK/CLAUDE.md"
git -C "$H_MC_WORK" add CLAUDE.md
git -C "$H_MC_WORK" commit -q -m "old constitution state (Section H)"
git -C "$H_MC_WORK" remote add origin "$H_MINI_BARE"
git -C "$H_MC_WORK" push -q origin main
H_OLD_SHA=$(git -C "$H_MC_WORK" rev-parse HEAD)
mkdir -p "$H_MC_WORK/scripts"
# The hook stub: writes its OWN real `pwd` to a marker path OUTSIDE the
# checkout tree (so it is never mistaken for migrate.sh's own residue,
# and survives independent of $WORKDIR's own post-migration state).
cat > "$H_MC_WORK/scripts/post_update_hook.sh" <<EOF
#!/bin/sh
pwd > "$WORK/h_hook_pwd_marker.txt"
exit 0
EOF
chmod +x "$H_MC_WORK/scripts/post_update_hook.sh"
git -C "$H_MC_WORK" add scripts/post_update_hook.sh
git -C "$H_MC_WORK" commit -q -m "new constitution state (Section H target, adds post_update_hook.sh stub)"
git -C "$H_MC_WORK" push -q origin main
H_NEW_SHA=$(git -C "$H_MC_WORK" rev-parse HEAD)
rm -rf "$H_MC_WORK"

H_BARE="$H_ROOT/consumer.git"
git init --bare -q -b main "$H_BARE"
H_WORK=$(mktemp -d)
git init -q -b main "$H_WORK" >/dev/null
git -C "$H_WORK" config user.name fastcycle-fixture
git -C "$H_WORK" config user.email fixture@example.invalid
cat > "$H_WORK/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section H,
B2 hook-cwd + I5 consumer-gates-discovery proof).

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
cat > "$H_WORK/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $H_MINI_BARE
EOF
git -C "$H_WORK" add CLAUDE.md .gitmodules
git -C "$H_WORK" update-index --add --cacheinfo 160000,"$H_OLD_SHA",constitution
git -C "$H_WORK" commit -q -m "initial Section H consumer state (constitution gitlink=old)"
git -C "$H_WORK" remote add origin "$H_BARE"
git -C "$H_WORK" push -q origin main
rm -rf "$H_WORK"
git clone -q --no-hardlinks "$H_BARE" "$H_ROOT/checkout" >/dev/null 2>&1
git -C "$H_ROOT/checkout" config user.name fastcycle-fixture
git -C "$H_ROOT/checkout" config user.email fixture@example.invalid

rm -f "$WORK/h_hook_pwd_marker.txt"
H_REVIEW_REF=$(make_review_ref "fixture/section_h_hook_cwd" "$H_NEW_SHA")
H_OUT=$(
    cd "$WORK" && run_tool --config "$CFG" --project "fixture/section_h_hook_cwd" \
        --workdir "$H_ROOT/checkout" --out "$WORK/h_migration.json" --apply --review-ref "$H_REVIEW_REF"
); H_RC=$?
if [ "$H_RC" -eq 0 ] && echo "$H_OUT" | grep -q 'MIGRATED' && [ -f "$WORK/h_hook_pwd_marker.txt" ] \
    && [ "$(cat "$WORK/h_hook_pwd_marker.txt")" = "$H_ROOT/checkout" ]; then
    ok "H1 B2 hook-cwd: post_update_hook.sh's own real pwd, captured while migrate.sh's caller cwd was deliberately set to \$WORK, equals \$WORKDIR ($H_ROOT/checkout) -- the hook ran against the CONSUMER, never the caller's ambient cwd"
else
    bad "H1 B2 hook-cwd: the hook did not run against \$WORKDIR (rc=$H_RC out=$H_OUT marker=$(cat "$WORK/h_hook_pwd_marker.txt" 2>/dev/null || echo ABSENT) expected=$H_ROOT/checkout)"
fi

# --- H2/H3: I5 -- a "Consumer gates: <script>" marker line names a
# genuinely-discovered, genuinely-run consumer gate script; a failing
# one blocks the migration as consumer-gates-red.
H2_BARE="$H_ROOT/consumer2.git"
git init --bare -q -b main "$H2_BARE"
H2_WORK=$(mktemp -d)
git init -q -b main "$H2_WORK" >/dev/null
git -C "$H2_WORK" config user.name fastcycle-fixture
git -C "$H2_WORK" config user.email fixture@example.invalid
mkdir -p "$H2_WORK/tools"
cat > "$H2_WORK/tools/always_fails.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$H2_WORK/tools/always_fails.sh"
cat > "$H2_WORK/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section H,
I5 consumer-gates discovery + a genuinely-failing gate).

## Commit Policy

Commit wrapper: none (plain git permitted)
Consumer gates: tools/always_fails.sh
EOF
cat > "$H2_WORK/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $H_MINI_BARE
EOF
git -C "$H2_WORK" add CLAUDE.md .gitmodules tools/always_fails.sh
git -C "$H2_WORK" update-index --add --cacheinfo 160000,"$H_OLD_SHA",constitution
git -C "$H2_WORK" commit -q -m "initial Section H2 consumer state (constitution gitlink=old)"
git -C "$H2_WORK" remote add origin "$H2_BARE"
git -C "$H2_WORK" push -q origin main
rm -rf "$H2_WORK"
git clone -q --no-hardlinks "$H2_BARE" "$H_ROOT/checkout2" >/dev/null 2>&1
git -C "$H_ROOT/checkout2" config user.name fastcycle-fixture
git -C "$H_ROOT/checkout2" config user.email fixture@example.invalid
H2_HASH_BEFORE=$(tree_hash "$H_ROOT/checkout2")
H2_REVIEW_REF=$(make_review_ref "fixture/section_h2_failing_gate" "$H_NEW_SHA")
H2_OUT=$(run_tool --config "$CFG" --project "fixture/section_h2_failing_gate" \
    --workdir "$H_ROOT/checkout2" --out "$WORK/h2_migration.json" --apply --review-ref "$H2_REVIEW_REF"); H2_RC=$?
if [ "$H2_RC" -eq 1 ] && echo "$H2_OUT" | grep -q 'NOT-MIGRATED (consumer-gates: consumer-gates-red)'; then
    ok "H2 I5 consumer-gates discovery: a CLAUDE.md 'Consumer gates: tools/always_fails.sh' marker is genuinely discovered and run, and its real non-zero exit blocks the migration as NOT-MIGRATED (consumer-gates: consumer-gates-red)"
else
    bad "H2 I5 consumer-gates discovery: a declared, genuinely-failing consumer gate did NOT block the migration (rc=$H2_RC out=$H2_OUT)"
fi
H2_HASH_AFTER_GITLINK=$(git -C "$H_ROOT/checkout2" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
if [ "$H2_HASH_AFTER_GITLINK" = "$H_OLD_SHA" ]; then
    ok "H3 I1 restore-on-gate-failure: the consumer-gates refusal genuinely restored the gitlink to its pre-migration value ($H_OLD_SHA), never left staged/committed"
else
    bad "H3 I1 restore-on-gate-failure: the gitlink was NOT restored after the consumer-gates refusal (got $H2_HASH_AFTER_GITLINK, expected $H_OLD_SHA)"
fi

rm -rf "$H_ROOT" 2>/dev/null || true

rm -rf "$F_ROOT" 2>/dev/null || true

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
