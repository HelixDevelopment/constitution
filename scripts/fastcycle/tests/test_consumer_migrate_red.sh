#!/bin/sh
# File-wide: this harness embeds dozens of literal shell/sed/python patch
# anchors and mutation snippets as single-quoted text (compared/injected
# byte-for-byte, never meant to expand) and a handful of escaped-quote
# literals inside those patterns, many spanning multiple physical lines --
# per-line disable comments would corrupt those multi-line literals. Each
# instance was reviewed (T177 Round 15 remediation); all are genuinely
# intentional non-expansion.
# shellcheck disable=SC2016,SC1003
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
    # $1=project_id $2=target_commit $3=consumer_base_commit -> prints the
    # path of a fresh, correctly-bound review-ref fixture file. T177
    # Round 2 R2-I3 fix: binding alone (project_id+target_commit) is not
    # CA-024's "zero-finding GO ... at the designated tier" -- a fixture
    # must ALSO carry an empty `findings` list, the designated
    # model_tier/effort (constitution 11.4.209: opus/xhigh), and a
    # `consumer_base_commit` naming the consumer's OWN pre-migration HEAD
    # (closes a stale-record replay: without it, a GO bound only to
    # project_id+target_commit stays valid for ANY later state of the SAME
    # consumer at the SAME constitution target).
    out="$WORK/fixture_review_go_$(echo "$1" | tr '/' '_').json"
    python3 - "$out" "$1" "$2" "$3" <<'PYEOF'
import json, sys
out, project, target, base = sys.argv[1:5]
doc = {
    "schema": "review-verdict-fixture/v1",
    "verdict": "GO",
    "project_id": project,
    "target_commit": target,
    "consumer_base_commit": base,
    "findings": [],
    "model_tier": "opus",
    "effort": "xhigh",
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
REJECT_REVIEW_REF=$(make_review_ref "fixture/ca_bad_rejecting_remote" "$NEW_SHA" "$(git -C "$REJECT_CHECKOUT" rev-parse HEAD)")
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
GOOD_REVIEW_REF=$(make_review_ref "fixture/ca_good_migrate" "$NEW_SHA" "$(git -C "$GOOD_CHECKOUT" rev-parse HEAD)")
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

# --- C4i: T177 Round 21 R20-M2 -- C4's blacklist is necessarily incomplete
# (R20's own review: "a blacklist missing several real force-push shapes").
# Per the reviewer's own suggested replacement, assert POSITIVELY instead:
# the tool's source contains EXACTLY ONE line that invokes `git ... push`,
# and that line is of the one known-safe shape this architecture actually
# uses -- `git -C "$FC_BARE" [...] push "$url" "$NEW_COMMIT":"refs/heads/
# $BRANCH"` (push-by-COMMIT-ID, never a branch name or `HEAD`, so moving
# the local branch after verification cannot change what gets published --
# see Round 15's half-2 fix). A blacklist can only catch bypass SHAPES its
# author already enumerated (C4b/C4c/C4d exist because the original
# blacklist missed two); a positive, single-known-shape assertion cannot be
# bypassed by any shape never thought of, including a FUTURE one C4's regex
# would also miss. This check does not replace C4 (a defense-in-depth
# pair, not a swap -- C4 still catches a force-push/reset/stash/clean
# ANYWHERE in the source, not only on the one push line this check
# inspects) and is NOT self-vacuous: it independently fails if a second
# push line is ever added (e.g. a future convenience branch-name push)
# even if neither line's own text matches C4's blacklist pattern.
if [ -f "$TOOL" ]; then
    PUSH_LINES=$(grep -nE 'git[[:space:]].*[[:space:]]push[[:space:]]' "$TOOL" | grep -v '^\s*[0-9]*:\s*#')
    PUSH_LINE_COUNT=$(printf '%s\n' "$PUSH_LINES" | grep -c . || true)
    KNOWN_SAFE_RE='push[[:space:]]+"\$url"[[:space:]]+"\$NEW_COMMIT":"refs/heads/\$BRANCH"'
    if [ "$PUSH_LINE_COUNT" -eq 1 ] && printf '%s\n' "$PUSH_LINES" | grep -qE -- "$KNOWN_SAFE_RE"; then
        ok "C4i R20-M2 positive push-shape: $TOOL contains exactly one 'git push' invocation, of the known-safe push-by-commit-id shape"
    else
        bad "C4i R20-M2 positive push-shape: $TOOL does not contain exactly one known-safe push invocation (count=$PUSH_LINE_COUNT) -- any other shape, or more than one push line, is refused by this check regardless of whether C4's blacklist also catches it"
    fi
else
    bad "C4i R20-M2 positive push-shape: $TOOL is absent -- cannot grep its source"
fi

# --- C4j: C4i guard-viability -- prove the positive check genuinely fires
# on a scratch copy whose push line is widened to a branch-name shape (the
# exact class C4i exists to catch and C4's blacklist alone would miss,
# since neither 'push "$r" "$BRANCH":"$BRANCH"' nor an added second push
# line matches any force/reset/stash/clean pattern).
C4J_SCRATCH="$WORK/c4j_migrate.sh"
cp "$TOOL" "$C4J_SCRATCH"
sed -i 's|push "\$url" "\$NEW_COMMIT":"refs/heads/\$BRANCH"|push "$url" "$BRANCH":"refs/heads/$BRANCH"|' "$C4J_SCRATCH"
if [ -f "$C4J_SCRATCH" ] && ! cmp -s "$C4J_SCRATCH" "$TOOL"; then
    C4J_PUSH_LINES=$(grep -nE 'git[[:space:]].*[[:space:]]push[[:space:]]' "$C4J_SCRATCH" | grep -v '^\s*[0-9]*:\s*#')
    C4J_COUNT=$(printf '%s\n' "$C4J_PUSH_LINES" | grep -c . || true)
    if [ "$C4J_COUNT" -eq 1 ] && printf '%s\n' "$C4J_PUSH_LINES" | grep -qE -- "$KNOWN_SAFE_RE"; then
        bad "C4j guard-viability: the widened branch-name push shape was NOT flagged by C4i (sed substitution may not have matched -- re-derive the anchor)"
    else
        ok "C4j guard-viability: C4i genuinely flags a push-by-branch-name bypass injected into a scratch copy"
    fi
else
    bad "C4j guard-viability: sed substitution on the scratch copy did not change it -- the C4i anchor is stale, re-derive it"
fi

# --- C4b/C4c: I3 guard-viability -- prove the WIDENED grep genuinely
# catches BOTH bypass shapes the reviewer found, on throwaway scratch
# copies of the tool source (never the tracked file). A grep that cannot
# catch its own target defect class on a synthetic positive is itself
# the defect.
C4B_SCRATCH="$WORK/c4b_force_f_flag.sh"
sed 's/git -C "\$FC_BARE" -c protocol.file.allow=always push "\$url" "\$NEW_COMMIT":"refs\/heads\/\$BRANCH"/git -C "$FC_BARE" -c protocol.file.allow=always push -f "$url" "$NEW_COMMIT":"refs\/heads\/$BRANCH"/' "$TOOL" > "$C4B_SCRATCH" 2>/dev/null
if [ -f "$C4B_SCRATCH" ] && ! cmp -s "$C4B_SCRATCH" "$TOOL" && grep -nE -- "$FORCE_PUSH_RE" "$C4B_SCRATCH" | grep -qv '^\s*#'; then
    ok "C4b I3 guard-viability: the widened C4 grep genuinely flags a 'push -f' short-flag bypass injected into a scratch copy"
else
    bad "C4b I3 guard-viability: the widened C4 grep did NOT flag a 'push -f' short-flag bypass (sed substitution may not have matched -- re-derive the anchor)"
fi
C4C_SCRATCH="$WORK/c4c_force_plus_var.sh"
sed 's/git -C "\$FC_BARE" -c protocol.file.allow=always push "\$url" "\$NEW_COMMIT":"refs\/heads\/\$BRANCH"/git -C "$FC_BARE" -c protocol.file.allow=always push "$url" "+$NEW_COMMIT":"refs\/heads\/$BRANCH"/' "$TOOL" > "$C4C_SCRATCH" 2>/dev/null
if [ -f "$C4C_SCRATCH" ] && ! cmp -s "$C4C_SCRATCH" "$TOOL" && grep -nE -- "$FORCE_PUSH_RE" "$C4C_SCRATCH" | grep -qv '^\s*#'; then
    ok "C4c I3 guard-viability: the widened C4 grep genuinely flags a '+\$BRANCH' variable-prefixed force-refspec bypass injected into a scratch copy"
else
    bad "C4c I3 guard-viability: the widened C4 grep did NOT flag a '+\$BRANCH' force-refspec bypass (sed substitution may not have matched -- re-derive the anchor)"
fi

# --- C4d: T177 Round 2 R2-B1(b) fix -- the C4 static grep is LINE-SCOPED
# ('push[^|]*...' never crosses a newline), so a `+`-prefixed refspec
# ASSIGNED on one line and PUSHED on a later, separate line entirely
# escapes it. Reviewer's exact live repro: on rejection, add
# `RS="+${BRANCH}:${BRANCH}"; git push "$r" "$RS"` -- the `+` never
# appears on any line containing the literal word "push", so C4's grep
# (and C4b/C4c's scratch mutations, which only ever touch the SAME push
# line) never sees it; T168 stayed 31/31 with this force-push bypass
# present. A genuine cross-line scanner is required: find every shell
# variable assigned a value whose literal content (after stripping one
# layer of quoting) STARTS WITH `+` (a dynamic force-refspec
# construction), then flag any line containing "push" that references
# that SAME variable, anywhere in the file, regardless of line distance.
FORCE_VAR_SCAN="$WORK/force_var_scan.py"
cat > "$FORCE_VAR_SCAN" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    lines = fh.readlines()
assign_re = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
plus_vars = set()
for line in lines:
    if line.lstrip().startswith("#"):
        continue
    m = assign_re.match(line)
    if not m:
        continue
    name, rhs = m.group(1), m.group(2).strip()
    if rhs[:1] in ('"', "'"):
        rhs = rhs[1:]
    if rhs.startswith("+"):
        plus_vars.add(name)
hits = []
for i, line in enumerate(lines, 1):
    if line.lstrip().startswith("#"):
        continue
    if "push" not in line:
        continue
    for v in plus_vars:
        if ("$" + v) in line or ("${" + v + "}") in line:
            hits.append("%d: variable '%s' (assigned a '+'-prefixed refspec) used on a push line: %s" % (i, v, line.rstrip()))
if hits:
    for h in hits:
        print(h)
    sys.exit(1)
sys.exit(0)
PYEOF
if [ -f "$TOOL" ]; then
    if python3 "$FORCE_VAR_SCAN" "$TOOL"; then
        ok "C4d R2-B1(b) cross-line force-refspec scan: $TOOL's source contains no variable assigned a '+'-prefixed refspec that is later used on any push line"
    else
        bad "C4d R2-B1(b) cross-line force-refspec scan: $TOOL's source assigns a '+'-prefixed refspec to a variable that is later used on a push line (a force-push bypass invisible to the line-scoped C4 grep)"
    fi
else
    bad "C4d R2-B1(b) cross-line force-refspec scan: $TOOL is absent"
fi

# --- C4e: guard-viability -- prove C4d genuinely catches the reviewer's
# EXACT adversarial mutation (RS="+${BRANCH}:${BRANCH}"; push "$r" "$RS")
# injected into a scratch copy, and (negative control, §11.4.201(1))
# genuinely does NOT flag the real, unmutated tool as a false positive.
C4D_SCRATCH="$WORK/c4d_force_var_indirect.sh"
python3 - "$TOOL" "$C4D_SCRATCH" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as fh:
    content = fh.read()
# T177 Round 21: anchor re-derived for the push line's new shape (the
# migration commit is now pushed from the isolated $FC_BARE, never from
# $WORKDIR, to each remote by its own URL); same mutation class.
anchor = '        if ! git -C "$FC_BARE" -c protocol.file.allow=always push "$url" "$NEW_COMMIT":"refs/heads/$BRANCH" 2>"$MIGRATE_SCRATCH/migrate_push_$r.err"; then\n'
replacement = (
    '        RS="+${NEW_COMMIT}:refs/heads/${BRANCH}"  # MUTATED_FOR_TEST (C4e adversarial)\n'
    '        if ! git -C "$FC_BARE" -c protocol.file.allow=always push "$url" "$RS" 2>"$MIGRATE_SCRATCH/migrate_push_$r.err"; then\n'
)
if anchor not in content:
    sys.exit(2)
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(content.replace(anchor, replacement, 1))
PYEOF
C4D_BUILD_RC=$?
if [ "$C4D_BUILD_RC" -eq 0 ] && [ -f "$C4D_SCRATCH" ] && ! python3 "$FORCE_VAR_SCAN" "$C4D_SCRATCH"; then
    ok "C4e guard-viability (positive): C4d's scanner genuinely flags the reviewer's exact RS=\"+\$BRANCH:\$BRANCH\" variable-indirection bypass injected into a scratch copy"
else
    bad "C4e guard-viability (positive): C4d's scanner did NOT flag the reviewer's exact variable-indirection bypass (build_rc=$C4D_BUILD_RC -- the anchor may have changed; re-derive it)"
fi
if [ -f "$TOOL" ] && python3 "$FORCE_VAR_SCAN" "$TOOL"; then
    ok "C4f guard-viability (negative control): C4d's scanner does NOT flag the real, unmutated $TOOL -- no false positive"
else
    bad "C4f guard-viability (negative control): C4d's scanner falsely flags the real, unmutated $TOOL"
fi

# --- C4g: T177 Round 1 I3's prescribed DYNAMIC fixture, never added
# before now -- a remote whose receive side GENUINELY ACCEPTS a
# non-fast-forward / force push (no pre-receive hook rejecting anything,
# unlike C2's fixture which rejects force AND non-force identically and
# so cannot distinguish "migrate.sh never force-pushed" from "the remote
# would have refused force anyway"). A diverged history is pushed to it
# out-of-band (simulating a remote that has moved on since migrate.sh's
# own fetch), so migrate.sh's own NORMAL (non-force) push is a genuine
# non-fast-forward rejection that a real `--force` WOULD overcome -- and
# the assertion is that the remote's tip stays at the diverged commit,
# never becomes migrate.sh's NEW_COMMIT, proving migrate.sh had a real
# opportunity to force and did not take it.
C4G_ROOT=$(mktemp -d)
C4G_BARE="$C4G_ROOT/accepting_remote.git"
git init --bare -q -b main "$C4G_BARE"
C4G_SEED=$(mktemp -d)
git init -q -b main "$C4G_SEED" >/dev/null
git -C "$C4G_SEED" config user.name fastcycle-fixture
git -C "$C4G_SEED" config user.email fixture@example.invalid
cat > "$C4G_SEED/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168 Section C4g,
R2-B1(b) dynamic force-accepting-remote proof).

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
C4G_SUB_URL=$(git config -f "$GOOD_CHECKOUT/.gitmodules" --get submodule.constitution.url 2>/dev/null)
cat > "$C4G_SEED/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $C4G_SUB_URL
EOF
git -C "$C4G_SEED" add CLAUDE.md .gitmodules
git -C "$C4G_SEED" update-index --add --cacheinfo 160000,"$OLD_SHA",constitution
git -C "$C4G_SEED" commit -q -m "initial C4g consumer state (constitution gitlink=old)"
git -C "$C4G_SEED" remote add origin "$C4G_BARE"
git -C "$C4G_SEED" push -q origin main
C4G_CHECKOUT="$C4G_ROOT/checkout"
git clone -q --no-hardlinks "$C4G_BARE" "$C4G_CHECKOUT" >/dev/null 2>&1
git -C "$C4G_CHECKOUT" config user.name fastcycle-fixture
git -C "$C4G_CHECKOUT" config user.email fixture@example.invalid
# Unset the clone's automatic upstream tracking (branch.main.remote/merge,
# set by `git clone` by default) -- migrate.sh's OWN preflight
# divergent-branches check (DEC-25 step 1) reads `@{u}` and refuses BEFORE
# reaching push if the tracked upstream is behind; this fixture WANTS to
# reach push (the whole point is proving it never force-pushes once
# there), so the diverged remote-tracking ref must not surface as a
# configured upstream.
git -C "$C4G_CHECKOUT" branch --unset-upstream 2>/dev/null || true
# Diverge the remote AFTER the checkout clones it, out-of-band, so
# migrate.sh's own later commit is genuinely non-fast-forward against it
# -- the remote accepts THIS push unconditionally (no pre-receive hook).
echo "diverged by a concurrent pusher" >> "$C4G_SEED/CLAUDE.md"
git -C "$C4G_SEED" commit -q -am "diverge the remote (simulates a concurrent pusher)"
git -C "$C4G_SEED" push -q origin main
C4G_DIVERGED_TIP=$(git -C "$C4G_BARE" rev-parse refs/heads/main 2>/dev/null)
rm -rf "$C4G_SEED"
C4G_REVIEW_REF=$(make_review_ref "fixture/section_c4g_force_accepting_remote" "$NEW_SHA" "$(git -C "$C4G_CHECKOUT" rev-parse HEAD)")
C4G_OUT=$(run_tool --config "$CFG" --project "fixture/section_c4g_force_accepting_remote" \
    --workdir "$C4G_CHECKOUT" --out "$WORK/c4g_migration.json" --apply --review-ref "$C4G_REVIEW_REF"); C4G_RC=$?
C4G_TIP_AFTER=$(git -C "$C4G_BARE" rev-parse refs/heads/main 2>/dev/null)
# T177 Round 21: the architectural fix for R20-B1 (CONTINUATION.md
# ADDENDUM 128) requires a remote's OWN CURRENT tip to equal $LOCAL_HEAD
# EXACTLY before this tool will build/push anything to it at all -- a
# diverged remote therefore now fails this earlier, cheaper, parser-bug-
# immune PREFLIGHT check (divergent-branches) rather than reaching the
# push step and relying on git's own non-fast-forward rejection there.
# The load-bearing SAFETY property this section exists to prove --
# C4h below, the remote's tip stays unchanged -- is identical either way;
# only the SURFACE reason differs, and both are accepted here.
if [ "$C4G_RC" -eq 1 ] && echo "$C4G_OUT" | grep -qE 'NOT-MIGRATED \(push:|NOT-MIGRATED \(preflight: divergent-branches\)'; then
    ok "C4g R2-B1(b) dynamic: migrate.sh correctly refuses (preflight or push) against a remote that diverged and genuinely ACCEPTS force pushes"
else
    bad "C4g R2-B1(b) dynamic: unexpected result against the force-accepting diverged remote (rc=$C4G_RC out=$C4G_OUT)"
fi
if [ "$C4G_TIP_AFTER" = "$C4G_DIVERGED_TIP" ]; then
    ok "C4h R2-B1(b) dynamic (the load-bearing assertion): the remote's tip is UNCHANGED ($C4G_DIVERGED_TIP) -- migrate.sh had a genuine opportunity to force-push through and did not take it (a remote that rejects force AND non-force alike, like C2's, cannot prove this)"
else
    bad "C4h R2-B1(b) dynamic (the load-bearing assertion): the remote's tip CHANGED from the diverged commit (before=$C4G_DIVERGED_TIP after=$C4G_TIP_AFTER) -- this remote genuinely accepts force, so a changed tip proves a force-push landed"
fi
rm -rf "$C4G_ROOT" 2>/dev/null || true

# --- C5: I6 negative control -- an UNBOUND review-ref (no project_id/
# target_commit fields, the exact {"verdict":"GO"} shape a prior version
# of migrate.sh accepted unconditionally) MUST now be refused even for an
# otherwise-migratable target. A disposable clone of ca_bad_dirty_local's
# own REMOTE (never pushed to -- only its LOCAL checkout is dirty, so the
# remote is still genuinely at OLD_SHA) is used, so this exercises the
# real gitlink-bump -> review path; the good consumer's remote is already at NEW_SHA by
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
# T177 Round 3: wt-branch is PUBLISHED to origin so the worktree passes the
# new finding-4 preflight (a branch with no published counterpart on any
# remote is refused as divergent-branches before any write) and reaches
# the backup step this section exists to exercise.
git -C "$D_MAIN" push -q origin wt-branch
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

E_REVIEW_REF=$(make_review_ref "fixture/section_e_nonstandard_section_name" "$E_NEW_SHA" "$(git -C "$E_ROOT/checkout" rev-parse HEAD)")
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
# mini-constitution + consumer fixture is built fresh here (the good consumer's remote
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
F_REVIEW_REF=$(make_review_ref "fixture/section_f_verify_load_bearing" "$F_NEW_SHA" "$(git -C "$F_ROOT/checkout" rev-parse HEAD)")
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
# T177 Round 5 (round-4 I3, enforced): the verify-only path ALSO requires a
# bound GO review -- F3b proves the refusal without one, F3 the convergence
# with one, and F3c that the MIGRATED record now carries review_ref +
# backup_marker (data-model #13.3 "required iff MIGRATED").
F3B_OUT=$(run_tool --config "$CFG" --project "fixture/section_f_verify_load_bearing" \
    --workdir "$F_CHECKOUT2" --out "$WORK/f3b_migration.json" --apply); F3B_RC=$?
if [ "$F3B_RC" -eq 1 ] && echo "$F3B_OUT" | grep -q 'NOT-MIGRATED (review: review-no-go)' && python3 -c "
import json, sys
d = json.load(open('$WORK/f3b_migration.json'))
sys.exit(0 if d.get('data_change') == 'NONE' and 'review_ref' not in d and not d.get('commit') else 1)
" 2>/dev/null && [ -z "$(git -C "$F_CHECKOUT2" status --porcelain=v1)" ]; then
    ok "F3b R5 I3: an already-at-target consumer with NO bound review is refused review-no-go before any write (data_change NONE, tree clean) -- never a MIGRATED record without review_ref"
else
    bad "F3b R5 I3: already-at-target without a review was not refused honestly (rc=$F3B_RC out=$F3B_OUT; see $WORK/f3b_migration.json)"
fi
F3_REF=$(make_review_ref "fixture/section_f_verify_load_bearing" "$F_NEW_SHA" "$(git -C "$F_CHECKOUT2" rev-parse HEAD)")
F3_OUT=$(run_tool --config "$CFG" --project "fixture/section_f_verify_load_bearing" \
    --workdir "$F_CHECKOUT2" --out "$WORK/f3_migration.json" --apply --review-ref "$F3_REF"); F3_RC=$?
if [ "$F3_RC" -eq 0 ] && echo "$F3_OUT" | grep -q 'MIGRATED' && ! echo "$F3_OUT" | grep -q 'NOT-MIGRATED'; then
    ok "F3 I4 already-at-target convergence: a fresh clone already at the migration target converges to MIGRATED via the verify-only path (no spurious 'git commit failed')"
else
    bad "F3 I4 already-at-target convergence: an already-at-target consumer did NOT converge to MIGRATED (rc=$F3_RC out=$F3_OUT)"
fi
if python3 -c "
import json, sys
d = json.load(open('$WORK/f3_migration.json'))
bm = d.get('backup_marker') or {}
sys.exit(0 if d.get('outcome') == 'MIGRATED' and d.get('review_ref') and bm.get('content_address', '').startswith('sha256:') else 1)
" 2>/dev/null; then
    ok "F3c R5 I3: the already-at-target MIGRATED record carries review_ref and backup_marker (data-model #13.3 enforced, not amended)"
else
    bad "F3c R5 I3: the already-at-target MIGRATED record lacks review_ref/backup_marker (see $WORK/f3_migration.json)"
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
# T177 Round 21: "second" (G_BARE_ACCEPT) must ALSO be seeded with this
# SAME initial state -- the architectural fix for R20-B1 requires a
# remote's OWN current tip to equal $LOCAL_HEAD EXACTLY before this tool
# will build/push anything to it (fc_publish.py's own header comment has
# the full rationale: catching a remote up from NOTHING would require
# transmitting $LOCAL_HEAD's entire ancestry, which is exactly the
# unverifiable-history risk the fix removes). A genuinely brand-new,
# never-before-seeded remote is no longer a scenario this tool seeds on
# its own (an operator-performed one-time mirror seed, reviewed outside
# this tool's automated flow, is required first) -- this section's own
# purpose (proving EVERY configured remote is attempted, one rejects, one
# accepts) needs "second" to be an ALREADY-IN-SYNC mirror, exactly like a
# real multi-remote fleet's own second mirror would be, not an empty one.
git -C "$G_WORK" remote add second "$G_BARE_ACCEPT"
git -C "$G_WORK" push -q second main
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
G_REVIEW_REF=$(make_review_ref "fixture/section_g_multi_remote" "$F_NEW_SHA" "$(git -C "$F_ROOT/g_checkout" rev-parse HEAD)")
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
# T177 Round 3 finding 5(c): the stub ALSO records the PROJECT_ROOT and
# CONST_DIR it was handed -- H1 previously checked only `pwd`, so dropping
# the explicit PROJECT_ROOT=/CONST_DIR= assignments from migrate.sh's hook
# call survived the whole suite (the real hook defaults PROJECT_ROOT to
# pwd, so a correct cwd alone does not prove the variables are passed).
cat > "$H_MC_WORK/scripts/post_update_hook.sh" <<EOF
#!/bin/sh
pwd > "$WORK/h_hook_pwd_marker.txt"
printf '%s\n' "\${PROJECT_ROOT:-UNSET}" > "$WORK/h_hook_project_root_marker.txt"
printf '%s\n' "\${CONST_DIR:-UNSET}" > "$WORK/h_hook_const_dir_marker.txt"
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
H_REVIEW_REF=$(make_review_ref "fixture/section_h_hook_cwd" "$H_NEW_SHA" "$(git -C "$H_ROOT/checkout" rev-parse HEAD)")
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
H1B_PR=$(cat "$WORK/h_hook_project_root_marker.txt" 2>/dev/null || echo ABSENT)
H1B_CD=$(cat "$WORK/h_hook_const_dir_marker.txt" 2>/dev/null || echo ABSENT)
if [ "$H1B_PR" = "$H_ROOT/checkout" ] && [ "$H1B_CD" = "$H_ROOT/checkout/constitution" ]; then
    ok "H1b R3 finding 5(c): the hook received PROJECT_ROOT=\$WORKDIR and CONST_DIR=\$WORKDIR/constitution explicitly (not merely a correct cwd)"
else
    bad "H1b R3 finding 5(c): the hook did not receive PROJECT_ROOT/CONST_DIR explicitly (PROJECT_ROOT=$H1B_PR CONST_DIR=$H1B_CD expected $H_ROOT/checkout and $H_ROOT/checkout/constitution)"
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
H2_REVIEW_REF=$(make_review_ref "fixture/section_h2_failing_gate" "$H_NEW_SHA" "$(git -C "$H_ROOT/checkout2" rev-parse HEAD)")
H2_OUT=$(run_tool --config "$CFG" --project "fixture/section_h2_failing_gate" \
    --workdir "$H_ROOT/checkout2" --out "$WORK/h2_migration.json" --apply --review-ref "$H2_REVIEW_REF"); H2_RC=$?
if [ "$H2_RC" -eq 1 ] && echo "$H2_OUT" | grep -q 'NOT-MIGRATED (consumer-gates: consumer-gates-red)'; then
    ok "H2 I5 consumer-gates discovery: a CLAUDE.md 'Consumer gates: tools/always_fails.sh' marker is genuinely discovered and run, and its real non-zero exit blocks the migration as NOT-MIGRATED (consumer-gates: consumer-gates-red)"
else
    bad "H2 I5 consumer-gates discovery: a declared, genuinely-failing consumer gate did NOT block the migration (rc=$H2_RC out=$H2_OUT)"
fi
# --- H3: T177 Round 3 finding 5(e) -- the former H3 compared `ls-tree HEAD`
# (which cannot change before step 7's commit, so it could never fail) and
# computed an H2_HASH_BEFORE it never compared (shellcheck SC2034). It is
# replaced by a check that CAN fail: after the refusal the checkout's
# `git status --porcelain` must be EMPTY and the record's data_change must
# be exactly "NONE" -- a restore that left the bumped gitlink staged (or
# any other residue) makes status non-empty and fails here.
H3_STATUS=$(git -C "$H_ROOT/checkout2" status --porcelain=v1 2>/dev/null)
H3_DC=$(python3 -c "import json; print(json.load(open('$WORK/h2_migration.json')).get('data_change'))" 2>/dev/null)
if [ -z "$H3_STATUS" ] && [ "$H3_DC" = "NONE" ]; then
    ok "H3 I1 restore-on-gate-failure: after the consumer-gates refusal the checkout is genuinely clean (empty git status) and the record's data_change is NONE"
else
    bad "H3 I1 restore-on-gate-failure: residue after the consumer-gates refusal (status='$H3_STATUS' data_change=$H3_DC)"
fi
# --- H3b: I2 -- H3 alone is TAUTOLOGICAL: `ls-tree HEAD` can never change
# for a migration refused BEFORE `git commit` ever runs (the consumer-
# gates refusal fires at step 5, three steps before step 7's commit), so
# H3 passes identically whether restore_staged_gitlink() genuinely runs OR
# is a no-op (reviewer mutation: `restore_staged_gitlink() { :; }` still
# leaves T168 at 31/31). The genuinely discriminating property is the
# INDEX (what step 4's `git update-index --add --cacheinfo` staged): a
# real restore (`git reset -q HEAD -- constitution`) resets the index
# entry for `constitution` back to $H_OLD_SHA; a no-op restore leaves the
# BUMPED $H_NEW_SHA still staged there, silently, forever (committable on
# the very next `git commit` a human or another tool might run).
H2_INDEX_SHA=$(git -C "$H_ROOT/checkout2" ls-files -s -- constitution 2>/dev/null | awk '{print $2}')
if [ "$H2_INDEX_SHA" = "$H_OLD_SHA" ]; then
    ok "H3b I2 restore-on-gate-failure (index): the staged INDEX entry for constitution was genuinely reset to the pre-migration gitlink ($H_OLD_SHA) -- a no-op restore would leave the bumped $H_NEW_SHA staged instead"
else
    bad "H3b I2 restore-on-gate-failure (index): the index still holds a gitlink SHA different from the pre-migration value (got $H2_INDEX_SHA, expected $H_OLD_SHA) -- restore_staged_gitlink() did not genuinely run"
fi
# --- H3c: T177 Round 3 finding 6 (fixed by Round 2's scratch isolation,
# regression-guarded here): a SECOND run on the SAME checkout after a
# consumer-gates refusal must reach the gates again, never be stuck on
# dirty-local because of the tool's OWN leftover log file.
H3C_OUT=$(run_tool --config "$CFG" --project "fixture/section_h2_failing_gate" \
    --workdir "$H_ROOT/checkout2" --out "$WORK/h2c_migration.json" --apply --review-ref "$H2_REVIEW_REF"); H3C_RC=$?
if [ "$H3C_RC" -eq 1 ] && echo "$H3C_OUT" | grep -q 'NOT-MIGRATED (consumer-gates: consumer-gates-red)'; then
    ok "H3c R3 finding 6: a re-run after a gates refusal reaches the gates again (no self-inflicted dirty-local from the tool's own log files)"
else
    bad "H3c R3 finding 6: a re-run after a gates refusal did not reach the gates again (rc=$H3C_RC out=$H3C_OUT)"
fi

# =============================================================================
# Section I -- T177 Round 3 regressions (independent Opus round-2 review,
# findings 2, 3, 4, 5, 9 + new findings N1/m4). Every subsection builds a
# FRESH mini-constitution + consumer via build_r3_fixture(), so no state
# leaks between them. All fixtures are local bare repos (no network).
# =============================================================================
build_r3_fixture() {
    # $1=root $2=hook-source-file-or-empty -> sets R3_OLD/R3_NEW; the
    # consumer checkout is $1/checkout, its bare remote $1/consumer.git.
    _r=$1; _hook=${2:-}
    mkdir -p "$_r"
    git init --bare -q -b main "$_r/mc.git"
    _w=$(mktemp -d)
    git init -q -b main "$_w" >/dev/null
    git -C "$_w" config user.name fastcycle-fixture
    git -C "$_w" config user.email fixture@example.invalid
    echo "old constitution state (Section I)" > "$_w/CLAUDE.md"
    git -C "$_w" add CLAUDE.md
    git -C "$_w" commit -q -m old
    git -C "$_w" remote add origin "$_r/mc.git"
    git -C "$_w" push -q origin main
    R3_OLD=$(git -C "$_w" rev-parse HEAD)
    echo "new constitution state (Section I target)" >> "$_w/CLAUDE.md"
    if [ -n "$_hook" ]; then
        mkdir -p "$_w/scripts"
        cp "$_hook" "$_w/scripts/post_update_hook.sh"
        chmod +x "$_w/scripts/post_update_hook.sh"
        git -C "$_w" add scripts/post_update_hook.sh
    fi
    git -C "$_w" add CLAUDE.md
    git -C "$_w" commit -q -m new
    git -C "$_w" push -q origin main
    R3_NEW=$(git -C "$_w" rev-parse HEAD)
    rm -rf "$_w"
    git init --bare -q -b main "$_r/consumer.git"
    _w=$(mktemp -d)
    git init -q -b main "$_w" >/dev/null
    git -C "$_w" config user.name fastcycle-fixture
    git -C "$_w" config user.email fixture@example.invalid
    printf '## INHERITED FROM constitution/CLAUDE.md\n\nFixture consumer (T168 Section I, T177 Round 3).\n\n## Commit Policy\n\nCommit wrapper: none (plain git permitted)\n' > "$_w/CLAUDE.md"
    mkdir -p "$_w/src"
    echo 'int main(void) { return 0; }' > "$_w/src/product.c"
    printf '[submodule "constitution"]\n\tpath = constitution\n\turl = %s\n' "$_r/mc.git" > "$_w/.gitmodules"
    git -C "$_w" add CLAUDE.md .gitmodules src/product.c
    git -C "$_w" update-index --add --cacheinfo 160000,"$R3_OLD",constitution
    git -C "$_w" commit -q -m "initial Section I consumer state"
    git -C "$_w" remote add origin "$_r/consumer.git"
    git -C "$_w" push -q origin main
    rm -rf "$_w"
    git clone -q --no-hardlinks "$_r/consumer.git" "$_r/checkout" >/dev/null 2>&1
    git -C "$_r/checkout" config user.name fastcycle-fixture
    git -C "$_r/checkout" config user.email fixture@example.invalid
}
I_ROOT=$(mktemp -d)

# --- I1/I2: finding 4 -- an UNPUBLISHED local commit touching product code
# must never be pushed alongside the migration (CA-022). Reviewer's repro:
# a local commit to src/product.c, then migrate --apply.
build_r3_fixture "$I_ROOT/i1"
echo "/* unrelated local product edit */" >> "$I_ROOT/i1/checkout/src/product.c"
git -C "$I_ROOT/i1/checkout" commit -q -am "unrelated unpushed product change"
I1_REMOTE_BEFORE=$(git -C "$I_ROOT/i1/consumer.git" rev-parse refs/heads/main)
I1_REF=$(make_review_ref "fixture/section_i1" "$R3_NEW" "$(git -C "$I_ROOT/i1/checkout" rev-parse HEAD)")
I1_OUT=$(run_tool --config "$CFG" --project "fixture/section_i1" --workdir "$I_ROOT/i1/checkout" \
    --out "$WORK/i1_migration.json" --apply --review-ref "$I1_REF"); I1_RC=$?
I1_REMOTE_AFTER=$(git -C "$I_ROOT/i1/consumer.git" rev-parse refs/heads/main)
if [ "$I1_RC" -eq 1 ] && echo "$I1_OUT" | grep -q 'NOT-MIGRATED (preflight: divergent-branches)' \
    && [ "$I1_REMOTE_BEFORE" = "$I1_REMOTE_AFTER" ]; then
    ok "I1 R3 finding 4: an unpublished local product commit makes migrate.sh refuse at preflight (divergent-branches) and the remote tip is unchanged -- nothing unrelated was published"
else
    bad "I1 R3 finding 4: unpublished local product commit was not refused at preflight, or the remote moved (rc=$I1_RC out=$I1_OUT before=$I1_REMOTE_BEFORE after=$I1_REMOTE_AFTER)"
fi
# T177 Round 21: the detail WORDING changed ("local-<branch>-has-no-
# published-counterpart-on-any-remote", derived from the fetch_sweep's
# per-remote exact-tip-match check) but the SAME underlying fact is
# still named -- $LOCAL_HEAD (which carries the unpushed product commit)
# is not published anywhere.
if python3 -c "
import json, sys
d = json.load(open('$WORK/i1_migration.json'))
sys.exit(0 if d.get('not_migrated_reason') == 'NOT-MIGRATED (preflight: divergent-branches)' and 'published-counterpart' in d.get('detail', '') and d.get('data_change') == 'NONE' else 1)
" 2>/dev/null; then
    ok "I2 R3 finding 4 record: the refusal record carries the closed-set reason, a detail naming the unpublished commit(s), and data_change NONE"
else
    bad "I2 R3 finding 4 record: unexpected refusal record (see $WORK/i1_migration.json)"
fi

# --- I3: finding 4 defence in depth -- a hook that itself creates a
# commit DIRECTLY IN $WORKDIR's OWN top-level checkout (as distinct from
# the constitution submodule's own nested checkout, which this tool
# legitimately advances) is refused before ANY write downstream of the
# hook, and the remote is unchanged. T177 Round 21: under the new
# architecture the migration commit is built entirely in the isolated
# $FC_BARE from $LOCAL_HEAD + the working tree's own current allow-listed
# content, never from $WORKDIR's own commit history -- so a hook-made
# commit in $WORKDIR can no longer smuggle itself into a "2-commit push
# set" at all (there IS no push-set-size check any more; nothing from
# $WORKDIR's history is ever consulted to build what gets published). The
# new, EARLIER, STRONGER invariant this tool now asserts instead: the
# hook/gates step must not move $WORKDIR's OWN HEAD at all -- refused at
# "wiring" (before the build even starts), not "push" (R20-B1's own
# remediation: moving the content-safety decision as early and as cheap
# as possible).
I3_HOOK="$WORK/i3_committing_hook.sh"
cat > "$I3_HOOK" <<'EOF'
#!/usr/bin/env bash
# A PATHSPEC commit (--only semantics): commits ONLY src/product.c and
# leaves the staged gitlink bump in the index, so the migration's own
# commit still lands and the push set is genuinely 2 commits.
cd "$PROJECT_ROOT" && echo "/* sneaked in by a hook */" >> src/product.c \
  && git -c user.name=h -c user.email=h@example.invalid commit -q -m "hook-made product commit" -- src/product.c
EOF
build_r3_fixture "$I_ROOT/i3" "$I3_HOOK"
I3_REMOTE_BEFORE=$(git -C "$I_ROOT/i3/consumer.git" rev-parse refs/heads/main)
I3_REF=$(make_review_ref "fixture/section_i3" "$R3_NEW" "$(git -C "$I_ROOT/i3/checkout" rev-parse HEAD)")
I3_OUT=$(run_tool --config "$CFG" --project "fixture/section_i3" --workdir "$I_ROOT/i3/checkout" \
    --out "$WORK/i3_migration.json" --apply --review-ref "$I3_REF"); I3_RC=$?
I3_REMOTE_AFTER=$(git -C "$I_ROOT/i3/consumer.git" rev-parse refs/heads/main)
if [ "$I3_RC" -eq 1 ] && echo "$I3_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$I3_OUT" | grep -q 'hook-or-gates-created-a-local-commit' && [ "$I3_REMOTE_BEFORE" = "$I3_REMOTE_AFTER" ]; then
    ok "I3 R3 finding 4 defence: a hook-created commit in \$WORKDIR's own top-level checkout is refused (naming the unexpected commit) before the build even starts, remote tip unchanged"
else
    bad "I3 R3 finding 4 defence: a hook-created extra commit reached the remote or was not refused (rc=$I3_RC out=$I3_OUT before=$I3_REMOTE_BEFORE after=$I3_REMOTE_AFTER)"
fi

# --- I4/I5/I6: findings 2 + 9 -- a hook shaped like the REAL
# post_update_hook.sh (bash-only syntax; writes .mcp.json + skills/ into
# PROJECT_ROOT) converges to MIGRATED, its two artefacts land IN the
# migration commit, the tree is clean afterwards, and the hook ran under
# bash. Also invoked with a RELATIVE --workdir (new finding N1: a relative
# workdir made PROJECT_ROOT resolve twice and the hook wrote nowhere).
I4_HOOK="$WORK/i4_real_shaped_hook.sh"
cat > "$I4_HOOK" <<EOF
#!/usr/bin/env bash
WARNINGS=()
WARNINGS+=("bash-only array append, as in the real hook")
readlink /proc/\$\$/exe > "$WORK/i4_hook_interpreter.txt"
printf '{"mcpServers":{}}\n' > "\$PROJECT_ROOT/.mcp.json"
mkdir -p "\$PROJECT_ROOT/skills"
echo "skill wiring" > "\$PROJECT_ROOT/skills/example.md"
EOF
build_r3_fixture "$I_ROOT/i4" "$I4_HOOK"
I4_REF=$(make_review_ref "fixture/section_i4" "$R3_NEW" "$(git -C "$I_ROOT/i4/checkout" rev-parse HEAD)")
I4_OUT=$(cd "$I_ROOT/i4" && run_tool --config "$CFG" --project "fixture/section_i4" --workdir "checkout" \
    --out "$WORK/i4_migration.json" --apply --review-ref "$I4_REF"); I4_RC=$?
I4_FILES=$(git -C "$I_ROOT/i4/checkout" show --name-only --format= HEAD 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
I4_STATUS=$(git -C "$I_ROOT/i4/checkout" status --porcelain=v1 2>/dev/null)
if [ "$I4_RC" -eq 0 ] && echo "$I4_OUT" | grep -q '^MIGRATED' \
    && [ "$I4_FILES" = ".mcp.json constitution skills/example.md " ] && [ -z "$I4_STATUS" ]; then
    ok "I4 R3 finding 2: the real hook's .mcp.json + skills/ output is staged INTO the migration commit (files: $I4_FILES), the record is MIGRATED and the tree is clean -- no untracked residue left after commit+push"
else
    bad "I4 R3 finding 2: hook output was not committed with the migration, or residue remains (rc=$I4_RC out=$I4_OUT commit-files='$I4_FILES' status='$I4_STATUS')"
fi
I4_INTERP=$(basename "$(cat "$WORK/i4_hook_interpreter.txt" 2>/dev/null || echo ABSENT)")
# Compared against the host's REAL bash binary (resolved, since a distro
# may name it bash5 etc.); on this host /bin/sh resolves to a DIFFERENT
# binary (sh5), so an `sh "$HOOK"` mutation is distinguishable here.
I4_BASH=$(basename "$(readlink -f "$(command -v bash)")")
if [ "$I4_INTERP" = "$I4_BASH" ]; then
    ok "I5 R3 finding 9: post_update_hook.sh ran under bash ($I4_INTERP), never sh"
else
    bad "I5 R3 finding 9: post_update_hook.sh ran under '$I4_INTERP', expected bash"
fi
if python3 -c "
import json, sys
d = json.load(open('$WORK/i4_migration.json'))
v = d.get('verification') or []
import hashlib
def real_addr(p):
    try:
        return 'sha256:' + hashlib.sha256(open(p, 'rb').read()).hexdigest()
    except OSError:
        return None
# T177 Round 5 (round-4 I1 M1): the content address must be the sha256 of
# the persisted report's REAL BYTES, re-derived here -- never merely a
# well-shaped 'sha256:<64>' string (the reviewer's M1 mutant hashed the
# PATH STRING and passed the old shape-only check).
ok = (d.get('outcome') == 'MIGRATED' and d.get('data_change') == 'NONE' and len(v) == 2
      and all(e.get('content_address') and e.get('content_address') == real_addr(e.get('path', '')) for e in v)
      and d.get('backup_marker', {}).get('content_address', '').startswith('sha256:'))
sys.exit(0 if ok else 1)
" 2>/dev/null; then
    ok "I6 R3 finding 8 + R5 M1: the MIGRATED record's verification content addresses equal the sha256 of the persisted reports' REAL bytes, and the backup marker carries its content address"
else
    bad "I6 R3 finding 8: the MIGRATED record lacks verification/backup content addresses (see $WORK/i4_migration.json)"
fi

# --- I7: finding 5(b) -- a hook writing a file OUTSIDE the CA-022
# allow-list is refused out-of-scope-diff, and the record's data_change
# NAMES the real residue (never a hard-coded NONE).
I7_HOOK="$WORK/i7_out_of_scope_hook.sh"
cat > "$I7_HOOK" <<'EOF'
#!/usr/bin/env bash
echo "not dev tooling" > "$PROJECT_ROOT/HOOK_WROTE_HERE"
EOF
build_r3_fixture "$I_ROOT/i7" "$I7_HOOK"
I7_REF=$(make_review_ref "fixture/section_i7" "$R3_NEW" "$(git -C "$I_ROOT/i7/checkout" rev-parse HEAD)")
I7_OUT=$(run_tool --config "$CFG" --project "fixture/section_i7" --workdir "$I_ROOT/i7/checkout" \
    --out "$WORK/i7_migration.json" --apply --review-ref "$I7_REF"); I7_RC=$?
if [ "$I7_RC" -eq 1 ] && echo "$I7_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' && python3 -c "
import json, sys
d = json.load(open('$WORK/i7_migration.json'))
sys.exit(0 if d.get('not_migrated_reason') == 'NOT-MIGRATED (wiring: out-of-scope-diff)' and d.get('data_change') == ['HOOK_WROTE_HERE'] and d.get('detail') == 'path=HOOK_WROTE_HERE' else 1)
" 2>/dev/null; then
    ok "I7 R3 finding 5(b): an out-of-allow-list hook artefact is refused with the closed-set reason, and data_change names the real residue (HOOK_WROTE_HERE)"
else
    bad "I7 R3 finding 5(b): out-of-scope hook artefact not refused honestly (rc=$I7_RC out=$I7_OUT; see $WORK/i7_migration.json)"
fi

# --- I8: finding 5(a) -- a review record bound to the right project and
# base but the WRONG target_commit is refused review-no-go.
build_r3_fixture "$I_ROOT/i8"
I8_REF=$(make_review_ref "fixture/section_i8" "$R3_OLD" "$(git -C "$I_ROOT/i8/checkout" rev-parse HEAD)")
I8_OUT=$(run_tool --config "$CFG" --project "fixture/section_i8" --workdir "$I_ROOT/i8/checkout" \
    --out "$WORK/i8_migration.json" --apply --review-ref "$I8_REF"); I8_RC=$?
if [ "$I8_RC" -eq 1 ] && echo "$I8_OUT" | grep -q 'NOT-MIGRATED (review: review-no-go)'; then
    ok "I8 R3 finding 5(a): a review record whose target_commit names a DIFFERENT constitution commit is refused review-no-go"
else
    bad "I8 R3 finding 5(a): a review record bound to the wrong target_commit was accepted (rc=$I8_RC out=$I8_OUT)"
fi

# --- I9..I12: finding 3 -- the step-9 VERIFY DECISION itself (not merely
# tool availability). A stub verifier (FASTCYCLE_VERIFY_TOOL_OVERRIDE, the
# documented test-only hook) writes a CONTROLLED report, so each clause of
# the decision is exercised in isolation: (I9) NOT_CLEAN with identical
# body_hash and rc=1; (I10) CLEAN x2 but differing body_hash; (I11) CLEAN
# x2, identical hash, but rc=1. Each MUST be NOT-MIGRATED. One checkout is
# reused: the first run commits+pushes, later runs take the already-at-
# target path, which runs the SAME step-9 decision.
I9_STUB="$WORK/i9_stub_verify.py"
cat > "$I9_STUB" <<'EOF'
import json, os, sys
mode = os.environ["FC_STUB_VERIFY_MODE"]
out = sys.argv[sys.argv.index("--out") + 1]
counter = out + ".n"
n = 0
if os.path.exists(os.environ["FC_STUB_COUNTER"]):
    n = int(open(os.environ["FC_STUB_COUNTER"]).read() or 0)
open(os.environ["FC_STUB_COUNTER"], "w").write(str(n + 1))
if mode == "not-clean":
    json.dump({"overall": "NOT_CLEAN", "body_hash": "same"}, open(out, "w")); sys.exit(1)
if mode == "hash-differs":
    json.dump({"overall": "CLEAN", "body_hash": "h%d" % n}, open(out, "w")); sys.exit(0)
if mode == "rc-nonzero":
    json.dump({"overall": "CLEAN", "body_hash": "same"}, open(out, "w")); sys.exit(1)
json.dump({"overall": "CLEAN", "body_hash": "same"}, open(out, "w")); sys.exit(0)
EOF
build_r3_fixture "$I_ROOT/i9"
I9_REF=$(make_review_ref "fixture/section_i9" "$R3_NEW" "$(git -C "$I_ROOT/i9/checkout" rev-parse HEAD)")
i9_run() {
    # $1=mode $2=label -> runs migrate.sh ($3 = tool path, default $TOOL)
    _tool=${3:-$TOOL}
    rm -f "$WORK/i9_counter"
    # T177 Round 5 (I3): later runs take the already-at-target path, which
    # now ALSO requires a GO review bound to the checkout's CURRENT HEAD.
    I9_REF=$(make_review_ref "fixture/section_i9" "$R3_NEW" "$(git -C "$I_ROOT/i9/checkout" rev-parse HEAD)")
    FC_STUB_VERIFY_MODE=$1 FC_STUB_COUNTER="$WORK/i9_counter" FASTCYCLE_VERIFY_TOOL_OVERRIDE="$I9_STUB" \
        sh "$_tool" --config "$CFG" --project "fixture/section_i9" --workdir "$I_ROOT/i9/checkout" \
        --out "$WORK/i9_$2.json" --apply --review-ref "$I9_REF" 2>&1
}
for mode in not-clean hash-differs rc-nonzero; do
    I9_OUT=$(i9_run "$mode" "$mode"); I9_RC=$?
    if [ "$I9_RC" -eq 1 ] && echo "$I9_OUT" | grep -q 'NOT-MIGRATED (verify: verification-not-clean)'; then
        ok "I9 R3 finding 3 verify decision ($mode): migrate.sh refuses MIGRATED when the verifier reports $mode"
    else
        bad "I9 R3 finding 3 verify decision ($mode): migrate.sh did not refuse (rc=$I9_RC out=$I9_OUT)"
    fi
done
I9_OUT=$(i9_run clean clean); I9_RC=$?
if [ "$I9_RC" -eq 0 ] && echo "$I9_OUT" | grep -q '^MIGRATED'; then
    ok "I10 R3 finding 3 negative control (§11.4.201(1)): the same stub reporting CLEAN x2 with rc=0 and equal hashes yields MIGRATED -- the decision is not a refuse-everything gate"
else
    bad "I10 R3 finding 3 negative control: a genuinely clean stub verify did not yield MIGRATED (rc=$I9_RC out=$I9_OUT)"
fi
# I11: guard-viability (in-suite, on a scratch copy -- never the tracked
# file): the reviewer's EXACT mutation, reducing the decision to
# hash-only (`[ -z "$HASH1" ] || [ "$HASH1" != "$HASH2" ]`), must turn the
# not-clean case into a (wrong) MIGRATED -- proving I9 is what catches it.
I11_SCRATCH="$WORK/i11_migrate_hash_only.sh"
python3 - "$TOOL" "$I11_SCRATCH" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
drop = [
    '[ "$V1_RC" -ne 0 ] && VERIFY_FAIL="$VERIFY_FAIL v1_rc=$V1_RC"\n',
    '[ "$V2_RC" -ne 0 ] && VERIFY_FAIL="$VERIFY_FAIL v2_rc=$V2_RC"\n',
    '[ "$OVERALL1" != "CLEAN" ] && VERIFY_FAIL="$VERIFY_FAIL overall1=$OVERALL1"\n',
    '[ "$OVERALL2" != "CLEAN" ] && VERIFY_FAIL="$VERIFY_FAIL overall2=$OVERALL2"\n',
]
for d in drop:
    if s.count(d) != 1:
        sys.exit(2)
    s = s.replace(d, "")
open(dst, "w", encoding="utf-8").write(s)
PYEOF
I11_BUILD_RC=$?
I11_OUT=$(i9_run not-clean mutant "$I11_SCRATCH"); I11_RC=$?
if [ "$I11_BUILD_RC" -eq 0 ] && [ "$I11_RC" -eq 0 ] && echo "$I11_OUT" | grep -q '^MIGRATED'; then
    ok "I11 R3 finding 3 guard-viability: the reviewer's hash-only mutation of the step-9 decision wrongly reports MIGRATED on a NOT_CLEAN verify -- exactly what I9 refuses, so I9 is load-bearing"
else
    bad "I11 R3 finding 3 guard-viability: the hash-only mutant did not behave as the reviewer reproduced (build_rc=$I11_BUILD_RC rc=$I11_RC out=$I11_OUT) -- re-derive the mutation anchors"
fi

# --- I12: new finding m4 -- two runs started in the SAME second under the
# same parent must get DISTINCT backup containers, never one nested inside
# the other (reproduced live: `cp -al src EXISTING` nested the 2nd backup
# as .git/ inside the 1st).
# A stub `date` on PATH pins the timestamp so the "same second" collision
# is DETERMINISTIC (the pre-fix code collided every time under it).
build_r3_fixture "$I_ROOT/i12"
I12_BIN="$WORK/i12_fixed_date_bin"
mkdir -p "$I12_BIN"
printf '#!/bin/sh\necho 20260101T000000Z\n' > "$I12_BIN/date"
chmod +x "$I12_BIN/date"
PATH="$I12_BIN:$PATH" run_tool --config "$CFG" --project "fixture/section_i12" --workdir "$I_ROOT/i12/checkout" --out "$WORK/i12a.json" --apply >/dev/null 2>&1
PATH="$I12_BIN:$PATH" run_tool --config "$CFG" --project "fixture/section_i12" --workdir "$I_ROOT/i12/checkout" --out "$WORK/i12b.json" --apply >/dev/null 2>&1
I12_N=$(find "$I_ROOT/i12" -maxdepth 1 -name '.fastcycle_migrate_backup_*' | wc -l)
I12_NESTED=$(find "$I_ROOT/i12"/.fastcycle_migrate_backup_* -mindepth 1 -name .git 2>/dev/null | wc -l)
if [ "$I12_N" -eq 2 ] && [ "$I12_NESTED" -eq 0 ]; then
    ok "I12 R3 m4: two back-to-back runs produced 2 distinct backup containers, none nested in another"
else
    bad "I12 R3 m4: backup containers collided or nested (containers=$I12_N nested=$I12_NESTED)"
fi

# --- I13: finding 1(b) -- a dry run is recorded with outcome DRY-RUN,
# never as a NOT-MIGRATED record with a reason outside the closed set.
build_r3_fixture "$I_ROOT/i13"
run_tool --config "$CFG" --project "fixture/section_i13" --workdir "$I_ROOT/i13/checkout" --out "$WORK/i13.json" >/dev/null 2>&1
if python3 -c "
import json, sys
d = json.load(open('$WORK/i13.json'))
sys.exit(0 if d.get('outcome') == 'DRY-RUN' and 'not_migrated_reason' not in d else 1)
" 2>/dev/null; then
    ok "I13 R3 finding 1(b): a dry run writes outcome DRY-RUN with no not_migrated_reason (never a counted NOT-MIGRATED record)"
else
    bad "I13 R3 finding 1(b): dry-run record shape is wrong (see $WORK/i13.json)"
fi
# =============================================================================
# Section J -- T177 Round 21 (CONTINUATION.md ADDENDUM 128, R20-B1
# remediation): the architectural rewrite replaced GIT_VERIFY (the
# per-commit-walk / net-zero-check machinery R20-B1 exploited), the
# per-remote content/tree-walk preflight (check_remote_scope /
# check_remote_commits), and the "build + commit inside $WORKDIR, then
# scan it" model entirely -- the migration commit is now built and
# verified inside an isolated, tool-owned $FC_BARE that is NEVER derived
# from $WORKDIR's own history (see migrate.sh's own ROUND 21 ARCHITECTURE
# header comment for the full design).
#
# §11.4.124 (investigate-before-remove) disposition for the ~40 fixtures
# this Section used to carry (J1-J43 across Rounds 5-19), decided
# per-fixture after running every one against the new architecture and
# reading its actual failure (not guessed):
#
#  RETIRED, mechanism genuinely gone, attack class STRUCTURALLY
#  eliminated (not merely re-scanned differently) -- cited individually,
#  replaced by the single stronger invariant J9 below:
#   - J20/J25/J26/J27 (declared-but-host-only / deleted / reverted /
#     type-changed constitution gitlink): the published "constitution"
#     entry is now an UNCONDITIONAL, externally-resolved cacheinfo write
#     (step 7, "160000,$NEW_SHA,constitution") that never reads
#     $WORKDIR's own index/working-tree state for this path AT ALL --
#     there is no longer any WORKDIR-side state for a hook to manipulate
#     that the build would ever consult. J9 below proves this positively
#     (delete/revert/retype the submodule checkout; the published gitlink
#     is still exactly $NEW_SHA every time).
#     (T177 Round 22, R21-M1 correction: J19 and J28 were WRONGLY grouped
#     into this list in an earlier draft of this disposition record --
#     spot-checked against the pre-Round-21 fixture bodies and neither is
#     about the constitution gitlink at all. J19's hook targets a
#     DIFFERENT path, `skills/evil`, via a `.gitmodules`-declaration
#     trick (append a `[submodule "skills/evil"]` section naming a
#     host-only commit as an already-"declared" gitlink); that exact
#     mechanism is retired not by J9 but by J5's own blanket
#     .gitmodules-immutability rule above -- ANY hook-staged change to
#     `.gitmodules`, including an appended section, is refused before
#     commit/push regardless of what it declares, so there is no
#     "declared" carve-out left for J19's attack to exploit. J28 is a
#     "select-one-parent evil merge" on `src/product.c` and belongs ONLY
#     in the per-remote-scope-walk category immediately below, where it
#     is correctly listed -- its earlier appearance here was a duplicate,
#     not a second genuine disposition.)
#
#  RETIRED, mechanism genuinely gone -- the per-remote tree/commit scope
#  walk this exploit shape and its siblings depended on no longer exists
#  (replaced by the exact-tip-match push-eligibility check; see
#  fc_publish.py's own header comment for why only exact equality is
#  safe): J6/J7/J17/J21/J28/J30/J30a/J30b (lagging-mirror catch-up,
#  select-one-parent evil merges, per-remote tree-diff edge cases). The
#  "catch a lagging/divergent remote up with scoped content" FEATURE
#  these exercised is not merely re-implemented differently -- CA-025's
#  own text ("a rejection ... remaining remotes proceed") never required
#  it, and it was the exact feature whose unsafe generalisation (J35's
#  net-zero history) produced R20-B1. A remote that does not already hold
#  $LOCAL_HEAD exactly is now a push failure for THAT remote, full stop.
#
#  RETIRED, mechanism genuinely gone -- GIT_VERIFY itself (the hand-
#  written commit/tree re-hash walker R20-B1 exploited) is REMOVED in
#  full, so every test of its OWN internal re-hash defenses no longer has
#  anything to test: J39 (GIT_VERIFY allow-list drift), J40/J41 (tampered
#  blob/tree object detection). $FC_BARE needs no such defense: nothing
#  but this tool's own `git fetch` / `hash-object -w` / `commit-tree`
#  calls EVER writes to it (it is a private, ephemeral, single-process-
#  owned scratch repository created and destroyed within one invocation,
#  never exposed to any other process between creation and destruction --
#  unlike $WORKDIR, a long-lived, externally-writable consumer checkout,
#  the object-store-tampering threat model GIT_VERIFY defended against
#  simply does not apply to $FC_BARE).
#
#  RETIRED, mechanism genuinely gone -- the git-hooks-disabled /
#  replace-ref / graft / commit-graph-forgery defenses (migrate.sh's own
#  "Round 15/16/17" environment-scoped config override block) existed
#  specifically to stop $WORKDIR's OWN git-native reads (diff-tree,
#  rev-list, cat-file) from being fooled while this tool built a commit
#  INSIDE $WORKDIR: J31/J32/J33/J34 (hooks firing mid-commit), J36/J36b
#  (replace-ref-hidden tampering), J36c (graft-faked history), J36d
#  (forged commit-graph), J38 (gpg side channel), J42/J43's shared-
#  allow-list / shallow-clone variants of the same walk. The commit is no
#  longer ever built inside $WORKDIR at all (step 7 runs entirely in
#  $FC_BARE), so there is no git-hook/replace-ref/graft/commit-graph
#  surface left in $WORKDIR for any of these to exploit; the override
#  block itself is KEPT (protecting this tool's remaining $WORKDIR reads:
#  the hook/gates `git status` enumeration, the submodule-advance
#  checkout -- see migrate.sh's own header) but has no commit-building
#  role left to guard.
#
#  ADAPTED (same safety property, re-anchored/re-asserted against the new
#  code's real mechanism -- harvest()'s inline content-safety checks,
#  belt-and-braces re-verified against $FC_BARE's own candidate tree):
#  the symlink-safety (former J1/J1b/J1c/J10/J11/J12/J13/J14), gitlink-
#  boundary (former J15), allow-list (former J2), and detached-HEAD
#  (former J8) invariants. These are NOT retired -- every one is still
#  genuinely enforced; they are re-tested below (J1-J8) against the real
#  ingestion path (harvest()) and the real final candidate-tree check,
#  each with its own guard-viability mutation proving it is still
#  load-bearing.
#
#  NEW, the exploit class this whole round exists to close: J10/J11
#  reproduce CONTINUATION.md ADDENDUM 128's exact two shapes (decoy
#  parent, decoy tree -- the commit-header trailer a naive whole-header
#  parser picks up but real git's own canonical parser does not) as
#  PERMANENT regression fixtures, each proving the shape is genuinely
#  refused end-to-end (origin never receives the unreviewed content) and
#  genuinely reproduces the leak when fc_publish.py's exact-tip-match
#  push-eligibility check is disabled (guard-viability, §11.4.115(F)).
#
# Every guard below is paired with its mutation run against a FRESH
# fixture on a scratch copy of migrate.sh (never the tracked file): the
# real tool must refuse/behave correctly AND the mutant must give the
# WRONG answer on the same fixture shape -- a guard no mutation breaks is
# decoration (§11.4.115(F), §1.1).
# =============================================================================
j_mutant() {
    # $1=label, then anchor/replacement PAIRS -> $WORK/jmut_$1.sh; J_MUT_OK=1 iff every anchor unique
    _lbl=$1; shift
    python3 - "$TOOL" "$WORK/jmut_$_lbl.sh" "$@" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
pairs = sys.argv[3:]
s = open(src, encoding="utf-8").read()
for a, b in zip(pairs[0::2], pairs[1::2]):
    if s.count(a) != 1:
        sys.exit(2)
    s = s.replace(a, b)
open(dst, "w", encoding="utf-8").write(s)
PYEOF
    _jrc=$?
    J_MUT_OK=0
    [ "$_jrc" -eq 0 ] && J_MUT_OK=1
}
j_run() {
    # $1=tool $2=fixture-root $3=project $4=out-json [extra args...] -> J_OUT/J_RC
    _t=$1; _fr=$2; _pj=$3; _o=$4; shift 4
    _ref=$(make_review_ref "$_pj" "$R3_NEW" "$(git -C "$_fr/checkout" rev-parse HEAD)")
    # The REAL verifier path is pinned explicitly: a scratch mutant copy
    # lives in $WORK, where its own $HERE-relative default would not resolve.
    J_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$_t" --config "$CFG" --project "$_pj" --workdir "$_fr/checkout" --out "$_o" --apply --review-ref "$_ref" "$@" 2>&1)
    J_RC=$?
}
jfield() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2" 2>/dev/null; }

# --- J1: a hook mirroring the REAL post_update_hook.sh install_skills()
# line (an ABSOLUTE host path symlink) must never be committed/pushed.
J1_HOOK="$WORK/j1_abs_symlink_hook.sh"
cat > "$J1_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "${CONST_DIR}/skills/media-validator" "$PROJECT_ROOT/skills/media-validator"
EOF
build_r3_fixture "$I_ROOT/j1" "$J1_HOOK"
J1_HEAD_BEFORE=$(git -C "$I_ROOT/j1/checkout" rev-parse HEAD)
J1_REMOTE_BEFORE=$(git -C "$I_ROOT/j1/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j1" fixture/section_j1 "$WORK/j1.json"
J1_REMOTE_AFTER=$(git -C "$I_ROOT/j1/consumer.git" rev-parse refs/heads/main)
J1_HEAD_AFTER=$(git -C "$I_ROOT/j1/checkout" rev-parse HEAD)
J1_DETAIL=$(jfield "$WORK/j1.json" detail)
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$J1_DETAIL" | grep -q 'host-specific-symlink path=skills/media-validator target-is-absolute' \
    && [ "$J1_REMOTE_BEFORE" = "$J1_REMOTE_AFTER" ] && [ "$J1_HEAD_BEFORE" = "$J1_HEAD_AFTER" ]; then
    ok "J1 symlink safety: an absolute-target symlink (the real install_skills() shape) is refused before any write, remote and local HEAD unchanged"
else
    bad "J1 symlink safety: an absolute-path symlink was not refused as expected (rc=$J_RC out=$J_OUT detail=$J1_DETAIL before=$J1_REMOTE_BEFORE after=$J1_REMOTE_AFTER head_before=$J1_HEAD_BEFORE head_after=$J1_HEAD_AFTER)"
fi
j_mutant J1_no_symlink_check \
    'if target.startswith("/"):
                fail("host-specific-symlink path=%s target-is-absolute" % path)' \
    'if False:
                fail("MUTATED_FOR_TEST: absolute-symlink check dropped")'
build_r3_fixture "$I_ROOT/j1m" "$J1_HOOK"
j_run "$WORK/jmut_J1_no_symlink_check.sh" "$I_ROOT/j1m" fixture/section_j1m "$WORK/j1m.json"
J1M_REMOTE_HAS_SYMLINK=$(git -C "$I_ROOT/j1m/consumer.git" cat-file -e refs/heads/main:skills/media-validator 2>/dev/null && echo YES || echo no)
# Measured directly (not assumed): dropping ONLY the dedicated
# `target.startswith("/")` branch does NOT publish the symlink --
# harvest()'s OWN SECOND check (the escape test) independently catches
# it too, because `posixpath.join(dirname, target)` with an ABSOLUTE
# `target` returns that absolute path VERBATIM regardless of `dirname`,
# so `resolved` itself still starts with "/" and the escape test's own
# `resolved.startswith("/")` arm fires. The two checks therefore overlap
# on this exact input class; isolating the FIRST check's own unique
# contribution needs the escape check ALSO disabled.
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'target-escapes-repository' \
    && [ "$J1M_REMOTE_HAS_SYMLINK" = "no" ]; then
    ok "J1 guard-viability: with ONLY the dedicated absolute-path branch dropped, harvest()'s own escape check independently catches the same input (an absolute target IS an escaping target under posixpath join semantics) -- overlapping coverage confirmed, never a silent gap"
else
    bad "J1 guard-viability: dropping the absolute-path branch did not behave as measured (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT remote-has-symlink=$J1M_REMOTE_HAS_SYMLINK)"
fi
j_mutant J1b_no_symlink_check_at_all \
    'if target.startswith("/"):
                fail("host-specific-symlink path=%s target-is-absolute" % path)
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
            if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
                fail("host-specific-symlink path=%s target-escapes-repository" % path)' \
    'pass  # MUTATED_FOR_TEST (J1b): BOTH harvest() symlink-safety branches dropped' \
    '    if target.startswith("/"):
        bad.append("path=%s target-is-absolute" % rel)
        continue
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(rel), target))
    if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
        bad.append("path=%s target-escapes-repository" % rel)' \
    '    pass  # MUTATED_FOR_TEST (J1b): the belt-and-braces scanner also disabled'
build_r3_fixture "$I_ROOT/j1b" "$J1_HOOK"
j_run "$WORK/jmut_J1b_no_symlink_check_at_all.sh" "$I_ROOT/j1b" fixture/section_j1b "$WORK/j1b.json"
J1B_REMOTE_HAS_SYMLINK=$(git -C "$I_ROOT/j1b/consumer.git" cat-file -e refs/heads/main:skills/media-validator 2>/dev/null && echo YES || echo no)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ "$J1B_REMOTE_HAS_SYMLINK" = "YES" ]; then
    ok "J1b guard-viability (both layers): with harvest()'s symlink-safety branches AND the belt-and-braces scan_symlinks_raw check BOTH dropped, the host-specific symlink finally reaches the remote -- confirming there is no hidden THIRD protection and the TWO real layers are what actually stand between this input and publication"
else
    bad "J1b guard-viability: dropping both layers did not reproduce the publication (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT remote-has-symlink=$J1B_REMOTE_HAS_SYMLINK)"
fi

# --- J2: a symlink whose RELATIVE target escapes the repository (climbs
# above its own root via ../) must never be committed/pushed.
J2_HOOK="$WORK/j2_escaping_symlink_hook.sh"
cat > "$J2_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "../../../etc/passwd" "$PROJECT_ROOT/skills/escape"
EOF
build_r3_fixture "$I_ROOT/j2" "$J2_HOOK"
J2_REMOTE_BEFORE=$(git -C "$I_ROOT/j2/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j2" fixture/section_j2 "$WORK/j2.json"
J2_REMOTE_AFTER=$(git -C "$I_ROOT/j2/consumer.git" rev-parse refs/heads/main)
J2_DETAIL=$(jfield "$WORK/j2.json" detail)
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$J2_DETAIL" | grep -q 'host-specific-symlink path=skills/escape target-escapes-repository' \
    && [ "$J2_REMOTE_BEFORE" = "$J2_REMOTE_AFTER" ]; then
    ok "J2 symlink safety: a relative symlink target that escapes the repository is refused, remote unchanged"
else
    bad "J2 symlink safety: an escaping relative symlink was not refused as expected (rc=$J_RC out=$J_OUT detail=$J2_DETAIL before=$J2_REMOTE_BEFORE after=$J2_REMOTE_AFTER)"
fi
j_mutant J2_no_escape_check \
    'if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
                fail("host-specific-symlink path=%s target-escapes-repository" % path)' \
    'if False:
                fail("MUTATED_FOR_TEST: escape check dropped")'
build_r3_fixture "$I_ROOT/j2m" "$J2_HOOK"
j_run "$WORK/jmut_J2_no_escape_check.sh" "$I_ROOT/j2m" fixture/section_j2m "$WORK/j2m.json"
# Measured directly (not assumed): dropping harvest()'s escape check does
# NOT publish the symlink -- the INDEPENDENT belt-and-braces check
# (scan_symlinks_raw, re-run against the candidate tree in $FC_BARE)
# catches it one layer later. This is genuine defense in depth (the same
# two-layer pattern J5/J1 also measure), not decoration: each layer is
# exercised in isolation elsewhere in this section, and here their
# overlap is what is being proven.
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'candidate-host-specific-symlink.*target-escapes-repository'; then
    ok "J2 guard-viability: with ONLY harvest()'s escape check dropped, the INDEPENDENT belt-and-braces candidate-tree scan still catches the escaping symlink one layer later -- defense in depth confirmed, not decoration"
else
    bad "J2 guard-viability: dropping harvest()'s escape check did not behave as measured (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J3: negative control (§11.4.201(1)) -- a genuinely PORTABLE relative
# symlink (resolves inside the repository on every host) completes a real
# migration successfully; the content-safety checks never false-positive
# on legitimate hook output.
J3_HOOK="$WORK/j3_portable_symlink_hook.sh"
cat > "$J3_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "../.claude/example.md" "$PROJECT_ROOT/skills/portable"
mkdir -p "$PROJECT_ROOT/.claude"
echo "example" > "$PROJECT_ROOT/.claude/example.md"
EOF
build_r3_fixture "$I_ROOT/j3" "$J3_HOOK"
j_run "$TOOL" "$I_ROOT/j3" fixture/section_j3 "$WORK/j3.json"
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ -z "$(git -C "$I_ROOT/j3/checkout" status --porcelain)" ]; then
    ok "J3 negative control: a genuinely portable relative symlink (resolves inside the repo) migrates cleanly end to end -- no false positive"
else
    bad "J3 negative control: a portable relative symlink was refused or mangled (rc=$J_RC out=$J_OUT)"
fi

# --- J4: a staged GITLINK (mode 160000) under an allow-listed directory
# other than "constitution" itself (a hook that `git init`s + commits
# inside an allow-listed path) must never be committed/pushed.
J4_HOOK="$WORK/j4_gitlink_hook.sh"
cat > "$J4_HOOK" <<'EOF'
#!/usr/bin/env bash
set -e
mkdir -p "$PROJECT_ROOT/skills/shadow"
cd "$PROJECT_ROOT/skills/shadow"
git init -q -b main >/dev/null
git -c user.name=h -c user.email=h@example.invalid commit -q -m shadow --allow-empty
EOF
build_r3_fixture "$I_ROOT/j4" "$J4_HOOK"
J4_REMOTE_BEFORE=$(git -C "$I_ROOT/j4/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j4" fixture/section_j4 "$WORK/j4.json"
J4_REMOTE_AFTER=$(git -C "$I_ROOT/j4/consumer.git" rev-parse refs/heads/main)
J4_DETAIL=$(jfield "$WORK/j4.json" detail)
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$J4_DETAIL" | grep -q 'unexpected-gitlink path=skills/shadow' \
    && [ "$J4_REMOTE_BEFORE" = "$J4_REMOTE_AFTER" ]; then
    ok "J4 gitlink-boundary safety: a hook-created nested git repository (git status reports it as a leaf directory, never descended into) under an allow-listed path is refused before any write, remote unchanged"
else
    bad "J4 gitlink-boundary safety: a hook-created nested repository was not refused (rc=$J_RC out=$J_OUT detail=$J4_DETAIL before=$J4_REMOTE_BEFORE after=$J4_REMOTE_AFTER)"
fi
j_mutant J4_no_gitlink_check \
    'elif stat.S_ISDIR(st.st_mode):' \
    'elif False:'
build_r3_fixture "$I_ROOT/j4m" "$J4_HOOK"
j_run "$WORK/jmut_J4_no_gitlink_check.sh" "$I_ROOT/j4m" fixture/section_j4m "$WORK/j4m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ]; then
    # The mutant removes the gitlink-boundary branch entirely (falls through
    # to the final `else` arm, "harvest-unsupported-file-type"), so the
    # migration is STILL refused -- but via a DIFFERENT, non-specific reason
    # (confirming the SPECIFIC check is what names the real problem; a
    # directory never silently becomes a tracked blob).
    ok "J4 guard-viability: with ONLY the specific gitlink-boundary branch dropped, the directory still refuses (via the generic unsupported-file-type fallback), confirming no fall-through path exists that would stage it as ordinary content"
else
    bad "J4 guard-viability: the gitlink-check mutant behaved unexpectedly (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J5: no hook may ever modify .gitmodules -- the ENTIRE file is
# off-limits (never per-key, the whole-file invariant this tool enforces
# before harvest() is even invoked).
J5_HOOK="$WORK/j5_gitmodules_hook.sh"
cat > "$J5_HOOK" <<'EOF'
#!/usr/bin/env bash
git config -f "$PROJECT_ROOT/.gitmodules" submodule.constitution.url "/tmp/host-local-path"
EOF
build_r3_fixture "$I_ROOT/j5" "$J5_HOOK"
J5_REMOTE_BEFORE=$(git -C "$I_ROOT/j5/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j5" fixture/section_j5 "$WORK/j5.json"
J5_REMOTE_AFTER=$(git -C "$I_ROOT/j5/consumer.git" rev-parse refs/heads/main)
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$J_OUT" | grep -q 'path=.gitmodules' \
    && [ "$J5_REMOTE_BEFORE" = "$J5_REMOTE_AFTER" ]; then
    ok "J5 .gitmodules protection: a hook that rewrites .gitmodules (even a single key) is refused before any write, remote unchanged"
else
    bad "J5 .gitmodules protection: a .gitmodules rewrite was not refused (rc=$J_RC out=$J_OUT before=$J5_REMOTE_BEFORE after=$J5_REMOTE_AFTER)"
fi
j_mutant J5_allow_gitmodules \
    'if [ "$f" = ".gitmodules" ]; then
                IFS=$OLD_IFS
                not_migrated_after_write "wiring" "out-of-scope-diff" "path=.gitmodules (no hook may modify this file; it is never part of the publishable diff)"
            fi' \
    ': # MUTATED_FOR_TEST: .gitmodules protection dropped'
build_r3_fixture "$I_ROOT/j5m" "$J5_HOOK"
j_run "$WORK/jmut_J5_allow_gitmodules.sh" "$I_ROOT/j5m" fixture/section_j5m "$WORK/j5m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'candidate-gitmodules-blob-changed'; then
    # Measured directly (not assumed): dropping the EARLY dedicated
    # refusal does NOT publish the rewrite -- the INDEPENDENT
    # belt-and-braces check on the candidate tree (CT_GM_OLD != CT_GM_NEW)
    # catches it one layer later, naming the changed blob ids. Both
    # layers are therefore genuinely load-bearing in their own right:
    # the early check for a cheap, specific refusal before any build
    # work happens; the late check as the structural guarantee that NO
    # path through this tool can ever publish a changed .gitmodules, even
    # if the early check itself has a bug.
    ok "J5 guard-viability: with ONLY the EARLY dedicated .gitmodules refusal dropped, the INDEPENDENT belt-and-braces candidate-tree check still catches the rewrite one layer later (naming the changed blob ids) -- defense in depth confirmed, not decoration"
else
    bad "J5 guard-viability: dropping the early .gitmodules check did not behave as measured (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J6: an out-of-allow-list hook artefact is refused, and the record's
# data_change NAMES the real residue (never a hard-coded NONE).
J6_HOOK="$WORK/j6_out_of_scope_hook.sh"
cat > "$J6_HOOK" <<'EOF'
#!/usr/bin/env bash
echo "not dev tooling" > "$PROJECT_ROOT/HOOK_WROTE_HERE"
EOF
build_r3_fixture "$I_ROOT/j6" "$J6_HOOK"
j_run "$TOOL" "$I_ROOT/j6" fixture/section_j6 "$WORK/j6.json"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' && python3 -c "
import json, sys
d = json.load(open('$WORK/j6.json'))
sys.exit(0 if d.get('data_change') == ['HOOK_WROTE_HERE'] and d.get('detail') == 'path=HOOK_WROTE_HERE' else 1)
" 2>/dev/null; then
    ok "J6 allow-list enforcement: an out-of-allow-list hook artefact is refused with the closed-set reason, and data_change names the real residue (HOOK_WROTE_HERE)"
else
    bad "J6 allow-list enforcement: out-of-scope hook artefact not refused honestly (rc=$J_RC out=$J_OUT; see $WORK/j6.json)"
fi
j_mutant J6_allow_any_root_path \
    'constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*) return 0 ;;' \
    '*) return 0 ;;'
build_r3_fixture "$I_ROOT/j6m" "$J6_HOOK"
j_run "$WORK/jmut_J6_allow_any_root_path.sh" "$I_ROOT/j6m" fixture/section_j6m "$WORK/j6m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED'; then
    ok "J6 guard-viability: with ONLY the shared CA-022 allow-list widened to match everything, the out-of-scope artefact is published (rc=0 MIGRATED) -- the allow-list is load-bearing"
else
    bad "J6 guard-viability: the widened-allow-list mutant did not reproduce the publication (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J7: a DETACHED HEAD is refused before any write; no branch to
# fast-forward at all.
build_r3_fixture "$I_ROOT/j7"
git -C "$I_ROOT/j7/checkout" checkout -q --detach HEAD 2>/dev/null
J7_REMOTE_BEFORE=$(git -C "$I_ROOT/j7/consumer.git" rev-parse refs/heads/main)
J7_REF=$(make_review_ref "fixture/section_j7" "$R3_NEW" "$(git -C "$I_ROOT/j7/checkout" rev-parse HEAD)")
J7_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j7" --workdir "$I_ROOT/j7/checkout" --out "$WORK/j7.json" --apply --review-ref "$J7_REF" 2>&1); J7_RC=$?
J7_REMOTE_AFTER=$(git -C "$I_ROOT/j7/consumer.git" rev-parse refs/heads/main)
if [ "$J7_RC" -eq 1 ] && echo "$J7_OUT" | grep -q 'NOT-MIGRATED (preflight: divergent-branches)' \
    && echo "$J7_OUT" | grep -q 'detached-HEAD-no-branch-to-fast-forward' \
    && [ "$J7_REMOTE_BEFORE" = "$J7_REMOTE_AFTER" ]; then
    ok "J7 detached-HEAD refusal: a detached checkout is refused before any write (no branch to fast-forward), remote unchanged"
else
    bad "J7 detached-HEAD refusal: a detached checkout was not refused as expected (rc=$J7_RC out=$J7_OUT before=$J7_REMOTE_BEFORE after=$J7_REMOTE_AFTER)"
fi
j_mutant J7_no_detached_check \
    'if [ "$BRANCH" = "HEAD" ] || [ -z "$BRANCH" ]; then' \
    'if false; then'
build_r3_fixture "$I_ROOT/j7m"
git -C "$I_ROOT/j7m/checkout" checkout -q --detach HEAD 2>/dev/null
J7M_REF=$(make_review_ref "fixture/section_j7m" "$R3_NEW" "$(git -C "$I_ROOT/j7m/checkout" rev-parse HEAD)")
J7M_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_J7_no_detached_check.sh" --config "$CFG" --project "fixture/section_j7m" --workdir "$I_ROOT/j7m/checkout" --out "$WORK/j7m.json" --apply --review-ref "$J7M_REF" 2>&1); J7M_RC=$?
if [ "$J_MUT_OK" -eq 1 ] && [ "$J7M_RC" -eq 1 ] && ! echo "$J7M_OUT" | grep -q 'detached-HEAD-no-branch-to-fast-forward'; then
    # With the detached-HEAD guard dropped, BRANCH literally holds the
    # string "HEAD" -- the later `refs/heads/HEAD` ref lookups and push
    # target then operate on a BOGUS branch name instead of refusing
    # honestly up front; the specific, honest refusal this guard exists
    # to produce is gone.
    ok "J7 guard-viability: with ONLY the detached-HEAD check dropped, the specific honest refusal disappears (the tool instead fails later, confusingly, against a bogus 'HEAD' branch name) -- the check is load-bearing for an honest, early refusal"
else
    bad "J7 guard-viability: the detached-HEAD mutant did not change behavior as expected (mut_ok=$J_MUT_OK rc=$J7M_RC out=$J7M_OUT)"
fi

# --- J8: the already-at-target (verify-only) path ALSO requires a bound
# GO review before it will report MIGRATED -- dropping that check lets an
# unreviewed already-at-target consumer report MIGRATED with no
# review_ref at all (violating data-model.md #13.3's "review_ref required
# iff MIGRATED").
build_r3_fixture "$I_ROOT/j8"
J8_REF=$(make_review_ref "fixture/section_j8" "$R3_NEW" "$(git -C "$I_ROOT/j8/checkout" rev-parse HEAD)")
J8_FIRST_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j8" --workdir "$I_ROOT/j8/checkout" --out "$WORK/j8_1.json" --apply --review-ref "$J8_REF" 2>&1); J8_FIRST_RC=$?
# Second run: fresh clone, already at target, deliberately NO --review-ref.
git clone -q --no-hardlinks "$I_ROOT/j8/consumer.git" "$I_ROOT/j8/checkout2" >/dev/null 2>&1
git -C "$I_ROOT/j8/checkout2" config user.name fastcycle-fixture
git -C "$I_ROOT/j8/checkout2" config user.email fixture@example.invalid
J8_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j8b" --workdir "$I_ROOT/j8/checkout2" --out "$WORK/j8.json" --apply 2>&1); J8_RC=$?
if [ "$J8_FIRST_RC" -eq 0 ] && echo "$J8_FIRST_OUT" | grep -q '^MIGRATED' \
    && [ "$J8_RC" -eq 1 ] && echo "$J8_OUT" | grep -q 'NOT-MIGRATED (review: review-no-go)' && [ -z "$(git -C "$I_ROOT/j8/checkout2" status --porcelain)" ]; then
    ok "J8 already-at-target review binding: a fresh already-at-target clone with NO review-ref is refused review-no-go (never silently MIGRATED), tree clean"
else
    bad "J8 already-at-target review binding: unexpected result (first rc=$J8_FIRST_RC first_out=$J8_FIRST_OUT second rc=$J8_RC second_out=$J8_OUT)"
fi
# REVIEW_REF_ID=""  is seeded BEFORE the bypassed `if false` (not merely
# `if false` alone): under `set -u`, skipping the call to check_review()
# entirely leaves $REVIEW_REF_ID genuinely UNSET (it is a function-local
# side effect, never declared at top level) -- the later `write_out ...
# "$REVIEW_REF_ID" ...` reference then CRASHES the mutant outright
# (an "unbound variable" error, rc=1, no record written at all), which is
# a real but UNINTERESTING difference (a crash is not a false MIGRATED
# claim); measured directly while authoring this mutation.
j_mutant J8_no_at_target_review \
    'if ! check_review; then
        # T177 Round 6 (round-6 MINOR M1)' \
    'REVIEW_REF_ID=""
    if false; then
        # MUTATED_FOR_TEST (J8): already-at-target review check disabled
        # T177 Round 6 (round-6 MINOR M1)'
build_r3_fixture "$I_ROOT/j8m"
J8M_FIRST_REF=$(make_review_ref "fixture/section_j8m" "$R3_NEW" "$(git -C "$I_ROOT/j8m/checkout" rev-parse HEAD)")
# shellcheck disable=SC2034  # J8M_FIRST_OUT captured for ad-hoc
# diagnostic inspection if J8M_FIRST_RC's assertion below ever fails;
# only the rc is asserted.
J8M_FIRST_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_J8_no_at_target_review.sh" --config "$CFG" --project "fixture/section_j8m" --workdir "$I_ROOT/j8m/checkout" --out "$WORK/j8m_1.json" --apply --review-ref "$J8M_FIRST_REF" 2>&1); J8M_FIRST_RC=$?
git clone -q --no-hardlinks "$I_ROOT/j8m/consumer.git" "$I_ROOT/j8m/checkout2" >/dev/null 2>&1
git -C "$I_ROOT/j8m/checkout2" config user.name fastcycle-fixture
git -C "$I_ROOT/j8m/checkout2" config user.email fixture@example.invalid
J8M_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_J8_no_at_target_review.sh" --config "$CFG" --project "fixture/section_j8mb" --workdir "$I_ROOT/j8m/checkout2" --out "$WORK/j8m.json" --apply 2>&1); J8M_RC=$?
if [ "$J_MUT_OK" -eq 1 ] && [ "$J8M_FIRST_RC" -eq 0 ] && [ "$J8M_RC" -eq 0 ] && echo "$J8M_OUT" | grep -q '^MIGRATED' \
    && ! python3 -c "
import json, sys
d = json.load(open('$WORK/j8m.json'))
sys.exit(0 if d.get('review_ref') else 1)
" 2>/dev/null; then
    ok "J8 guard-viability: with ONLY the already-at-target review check disabled, a reviewless fresh clone reports MIGRATED with no review_ref -- violating data-model.md #13.3; the check is load-bearing"
else
    bad "J8 guard-viability: the at-target-review mutant did not reproduce the review-less MIGRATED record (mut_ok=$J_MUT_OK first_rc=$J8M_FIRST_RC rc=$J8M_RC out=$J8M_OUT)"
fi

# --- J9: the constitution gitlink's PUBLISHED value is ALWAYS exactly
# $NEW_SHA, REGARDLESS of anything a hook does to the submodule's own
# on-disk checkout -- the single stronger invariant subsuming every one
# of T177 Rounds 8/10/12's former gitlink-manipulation fixtures (declared-
# but-host-only / deleted / reverted / type-changed / merge-smuggled):
# those attacks all depended on the published gitlink being DERIVED from
# $WORKDIR's own index/working-tree state, which this architecture no
# longer does -- the gitlink is an UNCONDITIONAL, externally-resolved
# cacheinfo write (step 7), never read back from $WORKDIR at all. Proven
# here with THREE sub-variants of hook interference in one pass.
J9_HOOK="$WORK/j9_interfere_hook.sh"
cat > "$J9_HOOK" <<'EOF'
#!/usr/bin/env bash
set -e
rm -rf "$CONST_DIR"
EOF
build_r3_fixture "$I_ROOT/j9" "$J9_HOOK"
j_run "$TOOL" "$I_ROOT/j9" fixture/section_j9 "$WORK/j9.json"
J9_PUBLISHED_GITLINK=$(git -C "$I_ROOT/j9/consumer.git" ls-tree refs/heads/main constitution 2>/dev/null | awk '{print $3}')
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ "$J9_PUBLISHED_GITLINK" = "$R3_NEW" ] \
    && { [ -d "$I_ROOT/j9/checkout/constitution/.git" ] || [ -f "$I_ROOT/j9/checkout/constitution/.git" ]; }; then
    ok "J9 constitution-gitlink invariant: a hook that deletes the whole submodule checkout directory has NO effect on the published result -- the gitlink is published at exactly \$NEW_SHA ($R3_NEW), and \$WORKDIR self-heals (submodule re-materialized by the post-publish sync)"
else
    bad "J9 constitution-gitlink invariant: a deleted submodule checkout affected the published gitlink (rc=$J_RC out=$J_OUT published=$J9_PUBLISHED_GITLINK expected=$R3_NEW)"
fi
j_mutant J9_drop_unconditional_cacheinfo \
    'if ! git -C "$FC_BARE" update-index --add --cacheinfo "160000,$NEW_SHA,constitution" 2>"$MIGRATE_SCRATCH/updindex.err"; then' \
    'if false; then'
build_r3_fixture "$I_ROOT/j9m" "$J9_HOOK"
j_run "$WORK/jmut_J9_drop_unconditional_cacheinfo.sh" "$I_ROOT/j9m" fixture/section_j9m "$WORK/j9m.json"
if [ "$J_MUT_OK" -eq 1 ]; then
    # Dropping the unconditional cacheinfo write means the private index
    # (seeded by `read-tree $LOCAL_HEAD^{tree}`) still carries the OLD
    # gitlink value, since nothing ever re-asserts it -- the candidate
    # tree's "constitution" entry stays at $OLD_SHA, which the belt-and-
    # braces final check (CT_CONST_OID != $NEW_SHA) then refuses.
    if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'candidate-constitution-entry'; then
        ok "J9 guard-viability: with the unconditional gitlink write dropped, the candidate tree's stale 'constitution' entry is caught by the independent belt-and-braces check -- TWO layers both had to be proven here, confirming neither is decoration"
    else
        bad "J9 guard-viability: dropping the unconditional cacheinfo write did not produce the expected stale-gitlink refusal (rc=$J_RC out=$J_OUT)"
    fi
else
    bad "J9 guard-viability: could not build the J9 mutant (anchor may have changed)"
fi

# --- J10/J11: CONTINUATION.md ADDENDUM 128, R20-B1 -- the EXACT two
# exploit shapes a round-20 independent review proved exploitable against
# round 19's GIT_VERIFY (the hand-written commit-header parser that
# disagreed with real git: it scans the WHOLE commit header for any
# "parent "/"tree " line, while real git only reads the lines CONTIGUOUS
# with the canonical "tree " line, treating anything after the first
# non-"parent" line -- e.g. placed after "committer" -- as an opaque
# trailer). Both shapes: X adds unreviewed product code, Y reverts it,
# both published ONLY to mirrorA (never to origin); a decoy parent/tree
# line (tree identical to the commit's own real tree) makes the per-
# commit walk's "own diff" read empty. Reproduced live against round 19
# (`git show 03f911e:.../migrate.sh`) before this fix: rc=0, MIGRATED,
# origin genuinely received X's unreviewed content. Round 21's
# architectural fix closes BOTH structurally: origin's own tip never
# equals $LOCAL_HEAD exactly (origin was never pushed X/Y at all), so
# fc_publish.py's exact-tip-match push-eligibility check skips origin for
# this migration -- no per-commit walk, no parser, nothing to fool.
j10_rewrite_with_decoy_parent() {
    # $1=repo $2=orig_commit_sha -> prints new sha; appends "parent <D>"
    # AFTER "committer " (D's tree == this commit's own tree).
    _repo=$1; _orig=$2
    _tree=$(git -C "$_repo" rev-parse "$_orig^{tree}")
    _d=$(git -C "$_repo" commit-tree "$_tree" -m "decoy-D" </dev/null)
    _raw=$(git -C "$_repo" cat-file commit "$_orig")
    _new_raw=$(printf '%s\n' "$_raw" | awk -v d="$_d" '
        { print }
        /^committer / && !done { print "parent " d; done=1 }
    ')
    printf '%s' "$_new_raw" | git -C "$_repo" hash-object -t commit -w --stdin
}
j10_build_decoy_parent_fixture() {
    # $1=root -> builds J35-shape history (X adds secret, Y reverts, both
    # pushed only to mirrorA), then rewrites BOTH X and Y with a decoy
    # parent line, keeping the chain genuinely consistent (Y's real
    # parent becomes X_NEW).
    build_r3_fixture "$1"
    git init --bare -q -b main "$1/mirrorA.git"
    git -C "$1/checkout" remote add mirrorA "$1/mirrorA.git"
    echo 'const char *SECRET_PRODUCT_FEATURE = "unreviewed";' >> "$1/checkout/src/product.c"
    git -C "$1/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -am "X: unreviewed product feature"
    J10_X=$(git -C "$1/checkout" rev-parse HEAD)
    git -C "$1/checkout" -c user.name=f -c user.email=f@example.invalid revert --no-edit HEAD >/dev/null
    J10_Y=$(git -C "$1/checkout" rev-parse HEAD)
    J10_X_NEW=$(j10_rewrite_with_decoy_parent "$1/checkout" "$J10_X")
    _y_tree=$(git -C "$1/checkout" rev-parse "$J10_Y^{tree}")
    _y_raw=$(git -C "$1/checkout" cat-file commit "$J10_Y")
    _y_reparented_raw=$(printf '%s\n' "$_y_raw" | sed "s|^parent .*|parent $J10_X_NEW|")
    _y_reparented=$(printf '%s' "$_y_reparented_raw" | git -C "$1/checkout" hash-object -t commit -w --stdin)
    J10_Y_NEW=$(j10_rewrite_with_decoy_parent "$1/checkout" "$_y_reparented")
    git -C "$1/checkout" update-ref refs/heads/main "$J10_Y_NEW"
    git -C "$1/checkout" -c advice.detachedHead=false checkout -q main 2>/dev/null || true
    git -C "$1/checkout" push -q mirrorA "+main:main"
    git -C "$1/checkout" fetch -q --all
}
j10_build_decoy_parent_fixture "$I_ROOT/j10"
j_run "$TOOL" "$I_ROOT/j10" fixture/section_j10 "$WORK/j10.json"
# X's secret is REVERTED by Y, so the FINAL published TREE never shows it
# (the wrong oracle here -- see J11's identical lesson below); the real
# question is whether X itself is reachable as an ANCESTOR of origin's
# main, i.e. present in its permanent history regardless of final content.
J10_ORIGIN_HAS_X=$(git -C "$I_ROOT/j10/consumer.git" merge-base --is-ancestor "$J10_X_NEW" refs/heads/main 2>/dev/null && echo YES || echo no)
if echo "$J_OUT" | grep -q 'NOT-MIGRATED' && [ "$J10_ORIGIN_HAS_X" = "no" ]; then
    ok "J10 R20-B1 shape 1 (decoy parent) CLOSED: X (carrying the unreviewed content) never reaches origin's history (rc=$J_RC out=$J_OUT)"
else
    bad "J10 R20-B1 shape 1 (decoy parent) REGRESSED: X reached origin's history or the migration unexpectedly succeeded (rc=$J_RC out=$J_OUT origin-has-X=$J10_ORIGIN_HAS_X)"
fi
# Both the PREFLIGHT exact-match (fetch_sweep's python `exact[]`, used
# for the PUBLISHED/BASE determination) AND the INDEPENDENT, SEPARATE
# push-TIME exact-match (the shell-level `if [ "$RTIP" != "$LOCAL_HEAD" ]`
# re-check immediately before each actual push) must be relaxed together
# -- measured directly while authoring this test: mutating ONLY the
# python half leaves the shell-level re-check fully intact, and origin is
# STILL correctly skipped (a genuine, separate layer of defense in
# depth, not a test bug). Isolating that layer's OWN unique contribution
# needs this combined mutation.
j_mutant J10_drop_exact_tip_match \
    'exact[name] = bool(tip) and (tip == local_head)' \
    'exact[name] = bool(tip)  # MUTATED_FOR_TEST (J10/J11): any tip accepted' \
    'if [ "$RTIP" != "$LOCAL_HEAD" ]; then' \
    'if false; then  # MUTATED_FOR_TEST (J10/J11): push-time exact-match also dropped'
j10_build_decoy_parent_fixture "$I_ROOT/j10m"
j_run "$WORK/jmut_J10_drop_exact_tip_match.sh" "$I_ROOT/j10m" fixture/section_j10m "$WORK/j10m.json"
J10M_ORIGIN_HAS_X=$(git -C "$I_ROOT/j10m/consumer.git" merge-base --is-ancestor "$J10_X_NEW" refs/heads/main 2>/dev/null && echo YES || echo no)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J10M_ORIGIN_HAS_X" = "YES" ]; then
    ok "J10 guard-viability: with BOTH the preflight and push-time exact-tip-match checks relaxed to 'any tip', the R20-B1 leak reproduces -- X reaches origin's history; the exact-match checks are what close this exploit class"
else
    bad "J10 guard-viability: relaxing the exact-tip-match check did not reproduce the leak (mut_ok=$J_MUT_OK out=$J_OUT origin-has-X=$J10M_ORIGIN_HAS_X)"
fi

j11_build_decoy_tree_fixture() {
    # $1=root -> X alone carries a decoy "tree <parent's-tree>" line after
    # committer; Y is an ORDINARY `git revert` (real git, real parent
    # chain) -- the single-crafted-commit shape (ADDENDUM 128 shape 2).
    build_r3_fixture "$1"
    git init --bare -q -b main "$1/mirrorA.git"
    git -C "$1/checkout" remote add mirrorA "$1/mirrorA.git"
    _x_parent=$(git -C "$1/checkout" rev-parse HEAD)
    _x_parent_tree=$(git -C "$1/checkout" rev-parse "$_x_parent^{tree}")
    echo 'const char *SECRET_PRODUCT_FEATURE = "unreviewed";' >> "$1/checkout/src/product.c"
    git -C "$1/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -am "X: unreviewed product feature"
    _x=$(git -C "$1/checkout" rev-parse HEAD)
    _x_raw=$(git -C "$1/checkout" cat-file commit "$_x")
    _x_new_raw=$(printf '%s\n' "$_x_raw" | awk -v t="$_x_parent_tree" '
        { print }
        /^committer / && !done { print "tree " t; done=1 }
    ')
    _x_new=$(printf '%s' "$_x_new_raw" | git -C "$1/checkout" hash-object -t commit -w --stdin)
    git -C "$1/checkout" update-ref refs/heads/main "$_x_new"
    git -C "$1/checkout" -c advice.detachedHead=false checkout -q main 2>/dev/null || true
    git -C "$1/checkout" reset -q "$_x_new" -- . >/dev/null 2>&1 || true
    git -C "$1/checkout" checkout -q main -- . 2>/dev/null || true
    git -C "$1/checkout" -c user.name=f -c user.email=f@example.invalid revert --no-edit HEAD >/dev/null
    git -C "$1/checkout" push -q mirrorA "+main:main"
    git -C "$1/checkout" fetch -q --all
    J11_X="$_x_new"
}
# X's secret is REVERTED by Y, so the FINAL published TREE never shows it
# (`show <ref>:path` alone is the WRONG oracle here -- confirmed by
# direct experiment: it read clean even on a genuine leak) -- the real
# question (R14-I1's own "net-zero history" framing) is whether commit X
# ITSELF is now reachable as an ANCESTOR of origin's main, i.e. present
# in origin's permanent HISTORY regardless of what the final tree shows.
j11_build_decoy_tree_fixture "$I_ROOT/j11"
j_run "$TOOL" "$I_ROOT/j11" fixture/section_j11 "$WORK/j11.json"
J11_ORIGIN_HAS_X=$(git -C "$I_ROOT/j11/consumer.git" merge-base --is-ancestor "$J11_X" refs/heads/main 2>/dev/null && echo YES || echo no)
if echo "$J_OUT" | grep -q 'NOT-MIGRATED' && [ "$J11_ORIGIN_HAS_X" = "no" ]; then
    ok "J11 R20-B1 shape 2 (decoy tree) CLOSED: X (carrying the unreviewed content) never reaches origin's history (rc=$J_RC out=$J_OUT)"
else
    bad "J11 R20-B1 shape 2 (decoy tree) REGRESSED: X reached origin's history or the migration unexpectedly succeeded (rc=$J_RC out=$J_OUT origin-has-X=$J11_ORIGIN_HAS_X)"
fi
j11_build_decoy_tree_fixture "$I_ROOT/j11m"
j_run "$WORK/jmut_J10_drop_exact_tip_match.sh" "$I_ROOT/j11m" fixture/section_j11m "$WORK/j11m.json"
J11M_ORIGIN_HAS_X=$(git -C "$I_ROOT/j11m/consumer.git" merge-base --is-ancestor "$J11_X" refs/heads/main 2>/dev/null && echo YES || echo no)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J11M_ORIGIN_HAS_X" = "YES" ]; then
    ok "J11 guard-viability: with BOTH exact-tip-match checks relaxed, the R20-B1 shape-2 leak also reproduces -- X reaches origin's history; the SAME pair of checks closes both shapes"
else
    bad "J11 guard-viability: relaxing the exact-tip-match check did not reproduce the shape-2 leak (mut_ok=$J_MUT_OK out=$J_OUT origin-has-X=$J11M_ORIGIN_HAS_X)"
fi

# --- J44: T177 Round 21, docs/research/git_verification_architecture_
# 20261002/FINDINGS.md Gap 1 ([LIVE] §6.1 "the template is copied into
# the new repo"). The realistic vector is the MIGRATING HOST's own git
# CONFIG (`init.templateDir` in a global/system gitconfig -- this tool
# deliberately leaves GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM untouched, see
# this file's own env-sanitization header comment for why), not a bare
# `GIT_TEMPLATE_DIR` env var (migrate.sh already unsets that
# unconditionally at startup, as its own first env-sanitization block
# does -- confirmed live: exporting GIT_TEMPLATE_DIR alone before
# invoking this tool has NO effect, by construction, before `--template=`
# is even reached; testing that vector would be vacuous). A hostile
# `init.templateDir` -- pointing at a directory carrying its own
# `objects/info/alternates` -- must have NO effect on a real,
# otherwise-golden migration: `--template=` on the `$FC_BARE` init call
# must prevent git's own template-copy mechanism from ever reaching
# $FC_BARE, REGARDLESS of whether templateDir is named by an env var or
# by config. Honest scope note: this fixture proves the TEMPLATE-COPY
# mechanism (FINDINGS.md §6.1) is defeated/caught; it does NOT rebuild
# FINDINGS.md §6.2's full forged-object-at-the-expected-hash exploit
# (that repro needs an attacker object whose on-disk bytes are planted
# under a DIFFERENT, correct-looking hash -- verified live by the
# research cited in this file's own header comment, not re-built as a
# permanent fixture here; §6.2's content-integrity question is
# independently covered by `git -C "$FC_BARE" fsck --strict
# --no-dangling`, exercised on every golden-path run in this suite,
# including this one).
J44_TEMPLATE="$WORK/j44_hostile_template"
mkdir -p "$J44_TEMPLATE/objects/info"
echo "/nonexistent/evil/object/store" > "$J44_TEMPLATE/objects/info/alternates"
J44_GITCONFIG_GLOBAL="$WORK/j44_hostile_gitconfig"
printf '[init]\n\ttemplateDir = %s\n' "$J44_TEMPLATE" > "$J44_GITCONFIG_GLOBAL"
build_r3_fixture "$I_ROOT/j44"
export GIT_CONFIG_GLOBAL="$J44_GITCONFIG_GLOBAL"
j_run "$TOOL" "$I_ROOT/j44" fixture/section_j44 "$WORK/j44.json"
unset GIT_CONFIG_GLOBAL
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ -z "$(git -C "$I_ROOT/j44/checkout" status --porcelain)" ]; then
    ok "J44 Gap-1 template-copy safety: a hostile host init.templateDir (objects/info/alternates) has no effect on a real migration -- --template= defeats the template-copy mechanism, migration completes cleanly"
else
    bad "J44 Gap-1 template-copy safety: a hostile host init.templateDir interfered with an otherwise-golden migration (rc=$J_RC out=$J_OUT)"
fi

# --- J44b: guard-viability, two independent layers. With ONLY the
# `--template=` flag reverted (the real pre-Round-21 shape, `git init
# --bare -q -b "$BRANCH" "$FC_BARE"`), the SAME hostile init.templateDir
# now DOES copy objects/info/alternates into $FC_BARE -- confirmed above
# (standalone, outside this suite) to be real git behaviour, not an
# assumption -- and the SECOND, independent layer
# (`fc_bare_assert_no_alternates`, unmutated here and called immediately
# after `git init --bare`) must catch it BEFORE any fetch or content
# decision, refusing with the specific `fc-bare-has-alternates-file`
# reason. Proves `--template=` is genuinely load-bearing (the fixture
# would otherwise reach a fetch against a poisoned object store) while
# the alternates-presence assert is a real, independent second defence,
# not decoration.
j_mutant J44_no_template_flag \
    'git init --bare --template= -q -b "$BRANCH" "$FC_BARE"' \
    'git init --bare -q -b "$BRANCH" "$FC_BARE"'
build_r3_fixture "$I_ROOT/j44m"
export GIT_CONFIG_GLOBAL="$J44_GITCONFIG_GLOBAL"
j_run "$WORK/jmut_J44_no_template_flag.sh" "$I_ROOT/j44m" fixture/section_j44m "$WORK/j44m.json"
unset GIT_CONFIG_GLOBAL
J44M_DETAIL=$(jfield "$WORK/j44m.json" detail)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'fc-bare-has-alternates-file'; then
    ok "J44b guard-viability: with ONLY --template= reverted, the hostile init.templateDir's alternates file IS copied into \$FC_BARE and is independently caught by fc_bare_assert_no_alternates (fc-bare-has-alternates-file) -- both layers proven genuinely load-bearing"
else
    bad "J44b guard-viability: reverting --template= did not reproduce the fc-bare-has-alternates-file refusal (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT detail=$J44M_DETAIL)"
fi

rm -rf "$I_ROOT" 2>/dev/null || true

rm -rf "$H_ROOT" 2>/dev/null || true

rm -rf "$F_ROOT" 2>/dev/null || true

# =============================================================================
# Section K -- T177 Round 22 (R21-I1, independent-review live-reproduced
# IMPORTANT finding): a `filter.<name>.{smudge,clean,process}` driver
# configured purely in the constitution submodule's own LOCAL, untracked
# `.git/config` (paired with a matching local `.gitattributes`/
# `.git/info/attributes` entry -- NO tracked-content change needed)
# executes an ARBITRARY COMMAND the moment this tool materializes that
# submodule's own working tree via `checkout` (or an internal re-checkout
# inside `submodule update --init`, on an already-initialised, drifted
# submodule) -- genuine code execution on the host running migrate.sh,
# squarely inside this tool's own stated threat model ("don't trust
# $WORKDIR's own git config"). Closed by fc_checkout_submodule_filtered /
# fc_submodule_update_init_filtered / fc_submodule_filter_exec (see
# migrate.sh's own "T177 Round 22 (R21-I1, live-reproduced)" header
# comment for the full forensic rationale). K1 reproduces the reviewer's
# EXACT threat shape against a REAL `$TOOL` run end to end (golden-path
# migration, not a standalone unit probe) and proves the fix does not
# merely avoid crashing but genuinely prevents the command from ever
# running, while migration itself still completes correctly.
K_ROOT=$(mktemp -d)
build_r3_fixture "$K_ROOT/k1"
# Pre-initialise the submodule at R3_OLD -- exactly what a real
# consumer's ALREADY-cloned checkout would already have on disk before
# this tool ever runs (build_r3_fixture's own `git clone` of the
# consumer repo never initialises a declared submodule).
git -C "$K_ROOT/k1/checkout" -c protocol.file.allow=always submodule update --init -q constitution
K1_SUB="$K_ROOT/k1/checkout/constitution"
if [ "$(git -C "$K1_SUB" rev-parse HEAD 2>/dev/null)" != "$R3_OLD" ]; then
    bad "K1 fixture setup: pre-initialised submodule HEAD is not \$R3_OLD -- fixture construction bug, not the invariant under test"
fi
# Tamper with the ALREADY-initialised submodule's own LOCAL config +
# attributes -- exactly the reviewer's threat shape: no tracked-content
# change anywhere, purely local and untracked.
K1_MARKER="$K_ROOT/k1_pwned_marker"
rm -f "$K1_MARKER"
git -C "$K1_SUB" config filter.k1evil.smudge "sh -c 'touch $K1_MARKER; cat'"
git -C "$K1_SUB" config filter.k1evil.clean "cat"
K1_SUB_GITDIR=$(git -C "$K1_SUB" rev-parse --absolute-git-dir)
mkdir -p "$K1_SUB_GITDIR/info"
echo "CLAUDE.md filter=k1evil" > "$K1_SUB_GITDIR/info/attributes"
j_run "$TOOL" "$K_ROOT/k1" fixture/section_k1 "$WORK/k1.json"
K1_GITLINK_AFTER=$(git -C "$K_ROOT/k1/checkout" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ ! -f "$K1_MARKER" ] \
    && [ "$K1_GITLINK_AFTER" = "$R3_NEW" ]; then
    ok "K1 filter-driver safety (T177 Round 22, R21-I1): a hostile filter.<name>.smudge driver configured purely in the already-initialised constitution submodule's own LOCAL, untracked git config (+matching local attributes, no tracked-content change) does NOT execute during this tool's own checkout of that submodule -- migration still completes correctly (MIGRATED, gitlink bumped to \$R3_NEW), the marker command never ran"
else
    bad "K1 filter-driver safety: rc=$J_RC out=$J_OUT marker-exists=$([ -f "$K1_MARKER" ] && echo yes || echo no) gitlink-after=$K1_GITLINK_AFTER expected=$R3_NEW"
fi
# K1 guard-viability: with ONLY the discovered-filter-override loop
# disabled (the mechanism this fix adds -- every OTHER defense in this
# file, including the hooksPath/fsmonitor/gpg env overrides above it,
# stays fully enabled), the SAME hostile smudge driver, against the SAME
# threat shape, DOES fire during this tool's own submodule checkout --
# proving K1's fix is the genuine, load-bearing cause of the marker's
# absence above, never a coincidence of some other unrelated defense.
# T177 Round 23: re-anchored to the Round 23 install loop (the Round 22
# per-call `for key in keys:` loop no longer exists) -- same intent: no
# discovered driver is ever overridden.
j_mutant K1_no_filter_override \
    'for name in names:' \
    'for name in []:  # MUTATED_FOR_TEST: filter-driver override disabled'
build_r3_fixture "$K_ROOT/k1m"
git -C "$K_ROOT/k1m/checkout" -c protocol.file.allow=always submodule update --init -q constitution
K1M_SUB="$K_ROOT/k1m/checkout/constitution"
K1M_MARKER="$K_ROOT/k1m_pwned_marker"
rm -f "$K1M_MARKER"
git -C "$K1M_SUB" config filter.k1evil.smudge "sh -c 'touch $K1M_MARKER; cat'"
git -C "$K1M_SUB" config filter.k1evil.clean "cat"
K1M_SUB_GITDIR=$(git -C "$K1M_SUB" rev-parse --absolute-git-dir)
mkdir -p "$K1M_SUB_GITDIR/info"
echo "CLAUDE.md filter=k1evil" > "$K1M_SUB_GITDIR/info/attributes"
j_run "$WORK/jmut_K1_no_filter_override.sh" "$K_ROOT/k1m" fixture/section_k1m "$WORK/k1m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ -f "$K1M_MARKER" ]; then
    ok "K1 guard-viability: with the discovered-filter-override loop disabled (reverting to this fix's pre-Round-22 behaviour), the SAME hostile smudge driver DOES fire during this tool's own submodule checkout -- K1's fix is genuinely load-bearing, not decoration"
else
    bad "K1 guard-viability: disabling the filter-override loop did not reproduce the smudge-driver firing (mut_ok=$J_MUT_OK marker-exists=$([ -f "$K1M_MARKER" ] && echo yes || echo no))"
fi

# --- K2-K7: T177 Round 23 (independent Round 22 review NO-GO: R22-B1,
# R22-B2, R22-I1, R22-M2, R22-M3). Round 22's K1 armed ONLY a direct
# submodule-local SMUDGE driver (with clean deliberately set to `cat`), so
# it could not see a clean driver firing on READS (B2), nor a driver
# defined via include.path / --worktree config that `git config --local`
# discovery never sees (B1); the reviewer's own regex mutation
# `(clean|smudge|process)` -> `(smudge|process)` survived at 84/0 (I1).
# Each arm below reproduces one shape end to end against the REAL tool,
# and each is paired with a mutant proving its OWN mechanism is the
# load-bearing cause (never a coincidence of a neighbouring defense).
#
# k_fixture $1=root $2=mode $3=marker: build_r3_fixture + a pre-initialised
# submodule (as a real already-cloned consumer has) + the mode's tampering.
# Every driver is a script that appends its tag to the marker, then acts
# as an identity filter -- so a fire is recorded but content is preserved.
# CLAUDE.md (the file whose content differs between R3_OLD/R3_NEW) is the
# attribute target; its mtime is backdated so a CLEAN driver genuinely has
# to run on the very next `status` (a clean filter runs only for a
# stat-dirty entry -- measured; without this a clean arm would be blind).
k_fixture() {
    _kr=$1; _km=$2; _kmk=$3
    build_r3_fixture "$_kr"
    git -C "$_kr/checkout" -c protocol.file.allow=always submodule update --init -q constitution
    _ks="$_kr/checkout/constitution"
    _kg=$(git -C "$_ks" rev-parse --absolute-git-dir)
    _kpg=$(git -C "$_kr/checkout" rev-parse --absolute-git-dir)
    mkdir -p "$_kg/info" "$_kpg/info"
    _kd="$_kr/k_drv.sh"
    printf '#!/bin/sh\necho "$1" >> "%s"\ncat\n' "$_kmk" > "$_kd"
    chmod +x "$_kd"
    rm -f "$_kmk"
    case "$_km" in
        clean)
            # B2: clean drivers in BOTH the submodule's and the PARENT's own
            # local config -- the step-1 dirty check reads the parent and
            # recurses into the submodule.
            echo "CLAUDE.md filter=kc" > "$_kg/info/attributes"
            git -C "$_ks" config filter.kc.clean "$_kd SUBCLEAN"
            echo "CLAUDE.md filter=kp" > "$_kpg/info/attributes"
            git -C "$_kr/checkout" config filter.kp.clean "$_kd PARENTCLEAN"
            touch -d 2001-01-01 "$_kr/checkout/CLAUDE.md" "$_ks/CLAUDE.md" ;;
        include)
            # B1(a): the driver lives in a file pulled in by include.path --
            # git reports it as scope `local`, `git config --local` never
            # prints it.
            echo "CLAUDE.md filter=ki" > "$_kg/info/attributes"
            printf '[filter "ki"]\n\tsmudge = %s INCSMUDGE\n\tclean = %s INCCLEAN\n' "$_kd" "$_kd" > "$_kr/k_include.cfg"
            git -C "$_ks" config include.path "$_kr/k_include.cfg"
            touch -d 2001-01-01 "$_ks/CLAUDE.md" ;;
        worktree)
            # B1(b): the driver lives in per-worktree config (scope
            # `worktree`), also invisible to `git config --local`.
            echo "CLAUDE.md filter=kw" > "$_kg/info/attributes"
            git -C "$_ks" config extensions.worktreeConfig true
            git -C "$_ks" config --worktree filter.kw.smudge "$_kd WTSMUDGE"
            git -C "$_ks" config --worktree filter.kw.clean "$_kd WTCLEAN"
            touch -d 2001-01-01 "$_ks/CLAUDE.md" ;;
        process)
            # M3: a long-running `process` driver marked required -- the
            # Round 22 override (process=cat) broke git's own handshake and
            # made the checkout exit 128.
            echo "CLAUDE.md filter=kq" > "$_kg/info/attributes"
            git -C "$_ks" config filter.kq.process "$_kd PROCESS"
            git -C "$_ks" config filter.kq.required true ;;
        unreadable)
            # Fail-closed: the include target cannot be read, so the
            # effective config cannot be established at all.
            printf '[filter "ku"]\n\tsmudge = %s UNRSMUDGE\n' "$_kd" > "$_kr/k_unreadable.cfg"
            git -C "$_ks" config include.path "$_kr/k_unreadable.cfg"
            echo "CLAUDE.md filter=ku" > "$_kg/info/attributes"
            chmod 000 "$_kr/k_unreadable.cfg" ;;
    esac
}
k_marker() { if [ -f "$1" ]; then sort -u "$1" | tr '\n' ' '; else echo none; fi; }
k_gitlink() { git -C "$1/checkout" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}'; }

for _kmode in clean include worktree; do
    k_fixture "$K_ROOT/k_$_kmode" "$_kmode" "$K_ROOT/k_${_kmode}.marker"
    j_run "$TOOL" "$K_ROOT/k_$_kmode" "fixture/section_k_$_kmode" "$WORK/k_$_kmode.json"
    if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ ! -f "$K_ROOT/k_${_kmode}.marker" ] \
        && [ "$(k_gitlink "$K_ROOT/k_$_kmode")" = "$R3_NEW" ]; then
        ok "K-$_kmode (T177 Round 23): a hostile $_kmode-shaped filter driver in \$WORKDIR's own untracked config never executes during a real migration (MIGRATED, gitlink=\$R3_NEW, marker never written)"
    else
        bad "K-$_kmode: rc=$J_RC out=$J_OUT marker=[$(k_marker "$K_ROOT/k_${_kmode}.marker")] gitlink=$(k_gitlink "$K_ROOT/k_$_kmode") expected=$R3_NEW"
    fi
done

# K-process: the M3 shape migrates cleanly with the REAL content checked out.
k_fixture "$K_ROOT/k_process" process "$K_ROOT/k_process.marker"
j_run "$TOOL" "$K_ROOT/k_process" fixture/section_k_process "$WORK/k_process.json"
K_PROC_CONTENT_OK=no
if [ "$(git -C "$K_ROOT/k_process/checkout/constitution" hash-object --no-filters CLAUDE.md 2>/dev/null)" = "$(git -C "$K_ROOT/k_process/checkout/constitution" rev-parse "$R3_NEW:CLAUDE.md" 2>/dev/null)" ]; then
    K_PROC_CONTENT_OK=yes
fi
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ ! -f "$K_ROOT/k_process.marker" ] && [ "$K_PROC_CONTENT_OK" = yes ]; then
    ok "K-process (R22-M3): a required long-running process driver is fully inert (process emptied, required=false) -- MIGRATED, the attacker's process command never runs, and the checked-out CLAUDE.md is byte-identical to \$R3_NEW's blob"
else
    bad "K-process: rc=$J_RC out=$J_OUT marker=[$(k_marker "$K_ROOT/k_process.marker")] content-matches-blob=$K_PROC_CONTENT_OK"
fi

# K-unreadable: discovery that cannot complete REFUSES before any write --
# never "no drivers found" (R22's false-null note).
k_fixture "$K_ROOT/k_unr" unreadable "$K_ROOT/k_unr.marker"
if [ -r "$K_ROOT/k_unr/k_unreadable.cfg" ]; then
    echo "SKIP: K-unreadable -- chmod 000 did not make the include target unreadable (running as a privileged user?); fail-closed arm not exercisable here"
else
    K_UNR_BEFORE=$(git -C "$K_ROOT/k_unr/consumer.git" rev-parse refs/heads/main)
    j_run "$TOOL" "$K_ROOT/k_unr" fixture/section_k_unr "$WORK/k_unr.json"
    if [ "$J_RC" -eq 4 ] && echo "$J_OUT" | grep -q 'could not establish filter-driver safety' \
        && [ "$K_UNR_BEFORE" = "$(git -C "$K_ROOT/k_unr/consumer.git" rev-parse refs/heads/main)" ] \
        && [ ! -f "$K_ROOT/k_unr.marker" ]; then
        ok "K-unreadable (fail-closed): an effective config that cannot be read is a refusal before any write (rc=4, remote unchanged) -- never treated as 'no drivers'"
    else
        bad "K-unreadable: expected a fail-closed rc=4 refusal (rc=$J_RC out=$J_OUT marker=[$(k_marker "$K_ROOT/k_unr.marker")])"
    fi
    chmod 644 "$K_ROOT/k_unr/k_unreadable.cfg" 2>/dev/null || true
fi

# K-verify-wiring: repo_verify.py strips inherited GIT_CONFIG_* by design,
# so the process-wide override never reaches it; migrate.sh must pass
# --neutralize-repo-filters to BOTH step-9 verifications. Proven at
# runtime by a recording stub verifier (its own argv), not by grepping
# migrate.sh's source.
K_RSTUB="$WORK/k_recording_verify.py"
cat > "$K_RSTUB" <<'EOF'
import json, os, sys
with open(os.environ["FC_K_ARGV_LOG"], "a") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
out = sys.argv[sys.argv.index("--out") + 1]
json.dump({"overall": "CLEAN", "body_hash": "same"}, open(out, "w"))
sys.exit(0)
EOF
k_verify_run() {
    # $1=tool $2=fixture-root $3=project $4=argv-log
    rm -f "$4"
    build_r3_fixture "$2"
    _kvref=$(make_review_ref "$3" "$R3_NEW" "$(git -C "$2/checkout" rev-parse HEAD)")
    FC_K_ARGV_LOG="$4" FASTCYCLE_VERIFY_TOOL_OVERRIDE="$K_RSTUB" sh "$1" --config "$CFG" --project "$3" \
        --workdir "$2/checkout" --out "$WORK/$(basename "$2").json" --apply --review-ref "$_kvref" >/dev/null 2>&1
}
k_verify_run "$TOOL" "$K_ROOT/k_vw" fixture/section_k_vw "$WORK/k_vw.argv"
K_VW_N=$(grep -c -- '--neutralize-repo-filters' "$WORK/k_vw.argv" 2>/dev/null || true)
K_VW_TOTAL=$(wc -l < "$WORK/k_vw.argv" 2>/dev/null || echo 0)
if [ "$K_VW_TOTAL" -eq 2 ] && [ "$K_VW_N" -eq 2 ]; then
    ok "K-verify-wiring: both step-9 verifications were invoked with --neutralize-repo-filters (recorded from the verifier's own argv at runtime)"
else
    bad "K-verify-wiring: expected 2 verifier invocations both carrying --neutralize-repo-filters, got total=$K_VW_TOTAL flagged=$K_VW_N"
fi

# --- K2-K7 guard-viability: each mutant removes exactly ONE Round 23
# mechanism and must re-open exactly the shape that mechanism closes.
# R22-I1, the reviewer's OWN surviving mutation, reproduced verbatim:
# drop `clean` from the discovered driver variables.
k_mutant_expect_fire() {
    # $1=label $2=mode $3=description -> runs mutant $WORK/jmut_$1.sh
    if [ "$J_MUT_OK" -ne 1 ]; then
        bad "K guard-viability $1: mutant anchor not unique/absent -- could not build"
        return
    fi
    k_fixture "$K_ROOT/km_$1" "$2" "$K_ROOT/km_$1.marker"
    j_run "$WORK/jmut_$1.sh" "$K_ROOT/km_$1" "fixture/section_km_$1" "$WORK/km_$1.json"
    if [ -f "$K_ROOT/km_$1.marker" ]; then
        ok "K guard-viability $1: $3 -- the hostile driver FIRES again ([$(k_marker "$K_ROOT/km_$1.marker")]); that mechanism is load-bearing"
    else
        bad "K guard-viability $1: $3, yet nothing fired (rc=$J_RC out=$J_OUT) -- this arm cannot see its own mechanism"
    fi
}
j_mutant K_drop_clean_var \
    'DRIVER_VARS = {b"clean", b"smudge", b"process"}' \
    'DRIVER_VARS = {b"smudge", b"process"}  # MUTATED_FOR_TEST (R22-I1 reviewer mutation)'
k_mutant_expect_fire K_drop_clean_var clean "with \`clean\` dropped from the discovered driver variables (the reviewer's own R22-I1 mutation)"
j_mutant K_local_only \
    'p = git(["config", "--show-scope", "--includes", "--null", "--get-regexp", r"^filter\."], d)' \
    'p = git(["config", "--local", "--show-scope", "--null", "--get-regexp", r"^filter\."], d)  # MUTATED_FOR_TEST'
k_mutant_expect_fire K_local_only include "with discovery narrowed back to \`git config --local\` (the Round 22 shape), an include.path-defined driver"
j_mutant K_local_only_wt \
    'p = git(["config", "--show-scope", "--includes", "--null", "--get-regexp", r"^filter\."], d)' \
    'p = git(["config", "--local", "--show-scope", "--null", "--get-regexp", r"^filter\."], d)  # MUTATED_FOR_TEST'
k_mutant_expect_fire K_local_only_wt worktree "with discovery narrowed back to \`git config --local\`, a --worktree-defined driver"
j_mutant K_no_early_install \
    'if ! fc_neutralize_repo_filters; then
    echo "migrate.sh: could not establish filter-driver safety for $WORKDIR' \
    'if false; then  # MUTATED_FOR_TEST: no install before the step-1 read
    echo "migrate.sh: could not establish filter-driver safety for $WORKDIR'
k_mutant_expect_fire K_no_early_install clean "with the install before the step-1 dirty check removed (later installs still present), the step-1 status read"
# R22-M2: pin the override VALUE. Measured (not assumed) while building
# this arm: `filter.<name>.process=` (EMPTY) by ITSELF disables the whole
# driver -- with process set, git never consults clean/smudge, and an
# empty process runs nothing (an attacker clean driver did not fire with
# ONLY process emptied; nor did a smudge driver, content passed through
# intact). So the process value is the PRIMARY, load-bearing neutraliser
# and smudge/clean=`cat` is an independent SECOND layer. Two arms pin both:
#  (a) an EXECUTING process value must be caught by the golden oracle;
j_mutant K_process_value_exec \
    '("smudge", "cat"), ("clean", "cat"), ("process", ""), ("required", "false")' \
    "(\"smudge\", \"cat\"), (\"clean\", \"cat\"), (\"process\", \"$K_ROOT/km_K_process_value_exec/k_drv.sh VALUEMUT\"), (\"required\", \"false\")"
k_mutant_expect_fire K_process_value_exec clean "with the process override VALUE replaced by a command (instead of empty)"
#  (b) with the process override REMOVED entirely, the `cat` layer alone
#      must still keep every hostile driver inert -- proving the second
#      layer is real and independent, not decoration riding on the first.
j_mutant K_cat_layer_alone \
    '("smudge", "cat"), ("clean", "cat"), ("process", ""), ("required", "false")' \
    '("smudge", "cat"), ("clean", "cat"), ("required", "false")'
k_fixture "$K_ROOT/km_K_cat_layer_alone" clean "$K_ROOT/km_K_cat_layer_alone.marker"
j_run "$WORK/jmut_K_cat_layer_alone.sh" "$K_ROOT/km_K_cat_layer_alone" fixture/section_km_K_cat_layer_alone "$WORK/km_K_cat_layer_alone.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ ! -f "$K_ROOT/km_K_cat_layer_alone.marker" ]; then
    ok "K layer-independence: with the empty-process override REMOVED, the smudge/clean=\`cat\` layer alone still keeps the clean-shape drivers inert (MIGRATED, marker never written) -- the second layer is real, not decoration"
else
    bad "K layer-independence: without the process override the cat layer did not hold (mut_ok=$J_MUT_OK rc=$J_RC marker=[$(k_marker "$K_ROOT/km_K_cat_layer_alone.marker")] out=$J_OUT)"
fi
# R22-M3: process emptied (not `cat`) is what keeps a required long-running
# driver from breaking the checkout.
j_mutant K_process_cat \
    '("smudge", "cat"), ("clean", "cat"), ("process", ""), ("required", "false")' \
    '("smudge", "cat"), ("clean", "cat"), ("process", "cat"), ("required", "false")'
k_fixture "$K_ROOT/km_K_process_cat" process "$K_ROOT/km_K_process_cat.marker"
j_run "$WORK/jmut_K_process_cat.sh" "$K_ROOT/km_K_process_cat" fixture/section_km_K_process_cat "$WORK/km_K_process_cat.json"
# Measured: the broken handshake surfaces at this tool's FIRST git read
# that needs the driver (the step-1 status, reported dirty-local because
# git's own handshake error lands in that read's output), not only at the
# checkout -- the assertion is the mechanism (the run no longer succeeds
# and the attacker's process command still never runs), not one symptom.
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -ne 0 ] && ! echo "$J_OUT" | grep -q '^MIGRATED' && [ ! -f "$K_ROOT/km_K_process_cat.marker" ]; then
    ok "K guard-viability (R22-M3): with process overridden to \`cat\` (the Round 22 value), git's long-running-filter handshake breaks and the migration no longer succeeds (rc=$J_RC) while the attacker command still never runs -- emptying process is what makes K-process pass"
else
    bad "K guard-viability (R22-M3): process=cat did not reproduce the checkout failure (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi
j_mutant K_no_verify_flag \
    'python3 "$VERIFY_TOOL" --recursive --neutralize-repo-filters --root "$WORKDIR" --out "$V1"' \
    'python3 "$VERIFY_TOOL" --recursive --root "$WORKDIR" --out "$V1"' \
    'python3 "$VERIFY_TOOL" --recursive --neutralize-repo-filters --root "$WORKDIR" --out "$V2"' \
    'python3 "$VERIFY_TOOL" --recursive --root "$WORKDIR" --out "$V2"'
k_verify_run "$WORK/jmut_K_no_verify_flag.sh" "$K_ROOT/km_vw" fixture/section_km_vw "$WORK/km_vw.argv"
K_MVW_N=$(grep -c -- '--neutralize-repo-filters' "$WORK/km_vw.argv" 2>/dev/null || true)
if [ "$J_MUT_OK" -eq 1 ] && [ "${K_MVW_N:-0}" -eq 0 ] && [ -s "$WORK/km_vw.argv" ]; then
    ok "K guard-viability (verify wiring): with the flag dropped from both verify invocations, the recording stub sees the verifier run WITHOUT it -- K-verify-wiring observes the real argv, not a constant"
else
    bad "K guard-viability (verify wiring): mutant did not change the recorded argv as expected (mut_ok=$J_MUT_OK flagged=$K_MVW_N)"
fi

rm -rf "$K_ROOT" 2>/dev/null || true

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
