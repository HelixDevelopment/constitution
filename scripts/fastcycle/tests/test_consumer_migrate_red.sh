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
anchor = '        if ! git -C "$WORKDIR" push "$r" "$BRANCH":"$BRANCH" 2>"$MIGRATE_SCRATCH/migrate_push.err"; then\n'
replacement = (
    '        RS="+${BRANCH}:${BRANCH}"  # MUTATED_FOR_TEST (C4e adversarial)\n'
    '        if ! git -C "$WORKDIR" push "$r" "$RS" 2>"$MIGRATE_SCRATCH/migrate_push.err"; then\n'
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
if [ "$C4G_RC" -eq 1 ] && echo "$C4G_OUT" | grep -q 'NOT-MIGRATED (push:'; then
    ok "C4g R2-B1(b) dynamic: migrate.sh correctly reports NOT-MIGRATED (push: ...) against a remote that diverged and genuinely ACCEPTS force pushes"
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
if python3 -c "
import json, sys
d = json.load(open('$WORK/i1_migration.json'))
sys.exit(0 if d.get('not_migrated_reason') == 'NOT-MIGRATED (preflight: divergent-branches)' and 'unpublished' in d.get('detail', '') and d.get('data_change') == 'NONE' else 1)
" 2>/dev/null; then
    ok "I2 R3 finding 4 record: the refusal record carries the closed-set reason, a detail naming the unpublished commit(s), and data_change NONE"
else
    bad "I2 R3 finding 4 record: unexpected refusal record (see $WORK/i1_migration.json)"
fi

# --- I3: finding 4 defence in depth at the push seam -- a hook that
# itself creates a commit (so the push set would be 2 commits, not 1) is
# refused before ANY push, and the remote is unchanged.
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
if [ "$I3_RC" -eq 1 ] && echo "$I3_OUT" | grep -q 'NOT-MIGRATED (push: out-of-scope-diff)' && [ "$I3_REMOTE_BEFORE" = "$I3_REMOTE_AFTER" ]; then
    ok "I3 R3 finding 4 push-seam defence: a hook-created extra commit is never published (refused, remote tip unchanged)"
else
    bad "I3 R3 finding 4 push-seam defence: a hook-created extra commit reached the remote or was not refused (rc=$I3_RC out=$I3_OUT before=$I3_REMOTE_BEFORE after=$I3_REMOTE_AFTER)"
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
# Section J -- T177 Round 5 (round-4 review: BLOCKING B1, I1 M1/M2/M3/M5/M6,
# I4, MINOR detached-HEAD, I3). Every guard is paired with its mutation run
# against a FRESH fixture on a scratch copy of migrate.sh (never the tracked
# file): the real tool must refuse/behave correctly AND the mutant must give
# the WRONG answer on the same fixture shape -- a guard no mutation breaks
# is decoration (§11.4.115(F), §1.1). Anchors are the reviewer's verbatim
# text unless noted (re-anchored only where round 5 rewrote the code).
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

# --- J1: BLOCKING B1 -- a hook mirroring the REAL post_update_hook.sh
# install_skills() line (`ln -s "${CONST_DIR}/skills/<n>" "${PROJECT_ROOT}/
# skills/<n>"`, an ABSOLUTE host path) must never be committed/pushed.
J1_HOOK="$WORK/j1_abs_symlink_hook.sh"
cat > "$J1_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "${CONST_DIR}/skills/media-validator" "$PROJECT_ROOT/skills/media-validator"
printf '{"mcpServers":{}}\n' > "$PROJECT_ROOT/.mcp.json"
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
    ok "J1 R5 B1: a hook-created ABSOLUTE symlink (the real install_skills shape) is refused out-of-scope-diff before review/commit/push -- no local commit, remote tip unchanged"
else
    bad "J1 R5 B1: an absolute host-path symlink was not refused before publishing (rc=$J_RC out=$J_OUT detail=$J1_DETAIL remote $J1_REMOTE_BEFORE->$J1_REMOTE_AFTER head $J1_HEAD_BEFORE->$J1_HEAD_AFTER)"
fi
# Guard-viability: disable ONLY the symlink refusal -> the absolute path is
# published into the remote's PERMANENT history (the reviewer's repro).
j_mutant B1_no_symlink_check 'if [ -n "$SYMLINK_VIOLATION" ]; then' 'if false; then'
build_r3_fixture "$I_ROOT/j1m" "$J1_HOOK"
j_run "$WORK/jmut_B1_no_symlink_check.sh" "$I_ROOT/j1m" fixture/section_j1m "$WORK/j1m.json"
J1M_LINK=$(git -C "$I_ROOT/j1m/consumer.git" cat-file -p "refs/heads/main:skills/media-validator" 2>/dev/null)
J1M_MODE=$(git -C "$I_ROOT/j1m/consumer.git" ls-tree refs/heads/main skills/media-validator 2>/dev/null | awk '{print $1}')
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && [ "$J1M_MODE" = "120000" ] && echo "$J1M_LINK" | grep -q '^/'; then
    ok "J1 guard-viability: with the symlink refusal disabled the mutant pushes a mode-120000 blob holding this host's ABSOLUTE path ($J1M_LINK) -- exactly the round-4 repro, so J1 is load-bearing"
else
    bad "J1 guard-viability: the symlink-check mutant did not reproduce the absolute-path publication (mut_ok=$J_MUT_OK rc=$J_RC mode=$J1M_MODE link=$J1M_LINK)"
fi
# J1b: a RELATIVE symlink that climbs OUT of the repository is refused too.
J1B_HOOK="$WORK/j1b_escape_symlink_hook.sh"
cat > "$J1B_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "../../outside-the-repo/skill" "$PROJECT_ROOT/skills/escape"
EOF
build_r3_fixture "$I_ROOT/j1b" "$J1B_HOOK"
J1B_REMOTE_BEFORE=$(git -C "$I_ROOT/j1b/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j1b" fixture/section_j1b "$WORK/j1b.json"
if [ "$J_RC" -eq 1 ] && jfield "$WORK/j1b.json" detail | grep -q 'path=skills/escape target-escapes-repository' \
    && [ "$J1B_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j1b/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J1b R5 B1: a relative symlink escaping the repository tree is refused, remote unchanged"
else
    bad "J1b R5 B1: an escaping relative symlink was not refused (rc=$J_RC out=$J_OUT; see $WORK/j1b.json)"
fi
# J1c negative control (§11.4.201(1)): a RELATIVE in-repo symlink (the
# portable shape a fixed hook would emit) is host-independent and MIGRATES,
# committed verbatim as a relative link.
J1C_HOOK="$WORK/j1c_relative_symlink_hook.sh"
cat > "$J1C_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills"
ln -s "../constitution/skills/media-validator" "$PROJECT_ROOT/skills/media-validator"
EOF
build_r3_fixture "$I_ROOT/j1c" "$J1C_HOOK"
j_run "$TOOL" "$I_ROOT/j1c" fixture/section_j1c "$WORK/j1c.json"
J1C_LINK=$(git -C "$I_ROOT/j1c/consumer.git" cat-file -p "refs/heads/main:skills/media-validator" 2>/dev/null)
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' && [ "$J1C_LINK" = "../constitution/skills/media-validator" ]; then
    ok "J1c negative control: a relative in-repo symlink is NOT refused -- MIGRATED, published as the portable relative link"
else
    bad "J1c negative control: a portable relative symlink was refused or mangled (rc=$J_RC out=$J_OUT link=$J1C_LINK)"
fi

# --- J2: I1 M5 -- a hook that modifies real product code (src/*) must be
# refused by the post-hook allow-list; the reviewer's EXACT M5 mutation
# (allow src/* and stage it) must instead publish the product change.
J2_HOOK="$WORK/j2_src_hook.sh"
cat > "$J2_HOOK" <<'EOF'
#!/usr/bin/env bash
echo "/* written by a hook */" >> "$PROJECT_ROOT/src/product.c"
EOF
build_r3_fixture "$I_ROOT/j2" "$J2_HOOK"
J2_REMOTE_BEFORE=$(git -C "$I_ROOT/j2/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j2" fixture/section_j2 "$WORK/j2.json"
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j2.json" detail)" = "path=src/product.c" ] \
    && [ "$J2_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j2/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J2 R5 M5: a hook modifying src/product.c (product code) is refused out-of-scope-diff (detail path=src/product.c), remote unchanged"
else
    bad "J2 R5 M5: a hook-made product-code change was not refused (rc=$J_RC out=$J_OUT; see $WORK/j2.json)"
fi
j_mutant M5_allowlist_src \
    'constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*) : ;;' \
    'constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*|src/*) : ;;' \
    '[ -d "$WORKDIR/skills" ] && git -C "$WORKDIR" add -A -- skills 2>/dev/null
' \
    '[ -d "$WORKDIR/skills" ] && git -C "$WORKDIR" add -A -- skills 2>/dev/null
        git -C "$WORKDIR" add -A -- src 2>/dev/null
'
build_r3_fixture "$I_ROOT/j2m" "$J2_HOOK"
j_run "$WORK/jmut_M5_allowlist_src.sh" "$I_ROOT/j2m" fixture/section_j2m "$WORK/j2m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && git -C "$I_ROOT/j2m/consumer.git" show refs/heads/main:src/product.c 2>/dev/null | grep -q 'written by a hook'; then
    ok "J2 guard-viability: the reviewer's M5 mutant publishes the hook's src/product.c change as MIGRATED -- J2 is what catches it"
else
    bad "J2 guard-viability: the M5 mutant did not publish the product change (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J3: I1 M6 -- the CA-022 boundary is the EXACT root `.mcp.json`; a hook
# writing any OTHER *.json (here a root package.json, product manifest)
# must be refused. Reviewer's EXACT M6 mutation widens it to `*.json`.
J3_HOOK="$WORK/j3_json_hook.sh"
cat > "$J3_HOOK" <<'EOF'
#!/usr/bin/env bash
printf '{"name":"product","version":"9.9.9"}\n' > "$PROJECT_ROOT/package.json"
EOF
build_r3_fixture "$I_ROOT/j3" "$J3_HOOK"
J3_REMOTE_BEFORE=$(git -C "$I_ROOT/j3/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j3" fixture/section_j3 "$WORK/j3.json"
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j3.json" detail)" = "path=package.json" ] \
    && [ "$J3_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j3/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J3 R5 M6: a hook-written root package.json (not the exact .mcp.json) is refused out-of-scope-diff, remote unchanged"
else
    bad "J3 R5 M6: a non-.mcp.json JSON file passed the allow-list (rc=$J_RC out=$J_OUT; see $WORK/j3.json)"
fi
j_mutant M6_allowlist_any_json '|config/fastcycle/*|.mcp.json|skills/*) : ;;' '|config/fastcycle/*|*.json|skills/*) : ;;'
build_r3_fixture "$I_ROOT/j3m" "$J3_HOOK"
J3M_REMOTE_BEFORE=$(git -C "$I_ROOT/j3m/consumer.git" rev-parse refs/heads/main)
j_run "$WORK/jmut_M6_allowlist_any_json.sh" "$I_ROOT/j3m" fixture/section_j3m "$WORK/j3m.json"
# The mutant lets package.json through the scope check; the staging block
# does not add it, so the run commits + PUSHES the migration while leaving
# product-manifest residue, and only the later verify step notices (as a
# mis-classified verification-not-clean). The wrong answer is therefore:
# the remote MOVED despite out-of-scope hook output.
if [ "$J_MUT_OK" -eq 1 ] && [ "$(jfield "$WORK/j3m.json" detail)" != "path=package.json" ] \
    && [ "$J3M_REMOTE_BEFORE" != "$(git -C "$I_ROOT/j3m/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J3 guard-viability: the reviewer's M6 mutant (allow *.json) lets package.json past the scope check and PUSHES the migration commit with product-manifest residue left behind (rc=$J_RC detail=$(jfield "$WORK/j3m.json" detail)) -- J3 is what catches the widening before anything is published"
else
    bad "J3 guard-viability: the M6 mutant still refuses package.json exactly as the real tool (mut_ok=$J_MUT_OK rc=$J_RC)"
fi

# --- J4: I1 M1 -- the reviewer's EXACT M1 mutant (content_address = sha256
# of the PATH STRING) must fail I6's real-bytes check above.
j_mutant M1_sha_of_path \
    '[ -n "$V1_PERSIST" ] && V1_SHA=$(sha256sum "$V1_PERSIST" 2>/dev/null | awk '"'"'{print $1}'"'"')' \
    '[ -n "$V1_PERSIST" ] && V1_SHA=$(printf %s "$V1_PERSIST" | sha256sum | awk '"'"'{print $1}'"'"')' \
    '[ -n "$V2_PERSIST" ] && V2_SHA=$(sha256sum "$V2_PERSIST" 2>/dev/null | awk '"'"'{print $1}'"'"')' \
    '[ -n "$V2_PERSIST" ] && V2_SHA=$(printf %s "$V2_PERSIST" | sha256sum | awk '"'"'{print $1}'"'"')'
build_r3_fixture "$I_ROOT/j4m"
j_run "$WORK/jmut_M1_sha_of_path.sh" "$I_ROOT/j4m" fixture/section_j4m "$WORK/j4m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && ! python3 -c "
import hashlib, json, sys
d = json.load(open('$WORK/j4m.json'))
v = d.get('verification') or []
sys.exit(0 if v and all(e['content_address'] == 'sha256:' + hashlib.sha256(open(e['path'], 'rb').read()).hexdigest() for e in v) else 1)
" 2>/dev/null; then
    ok "J4 guard-viability: the reviewer's M1 mutant (sha256 of the path string) writes content addresses that do NOT match the reports' real bytes -- the I6 real-bytes check (and audit.py summary) catch it; the old shape-only check did not"
else
    bad "J4 guard-viability: the M1 mutant's content addresses were not distinguishable from real ones (mut_ok=$J_MUT_OK rc=$J_RC; see $WORK/j4m.json)"
fi

# --- J5: I1 M2 -- a verify report that cannot be persisted must refuse
# MIGRATED (evidence-not-persisted). Forced for real: the persisted-report
# path ${OUT%.json}.verify1.json is a DANGLING symlink into a directory that
# does not exist, so `cp` genuinely fails.
build_r3_fixture "$I_ROOT/j5"
J5_OUT_JSON="$WORK/j5dir/j5.json"
mkdir -p "$WORK/j5dir"
ln -s "$WORK/j5_no_such_dir/target.json" "$WORK/j5dir/j5.verify1.json"
j_run "$TOOL" "$I_ROOT/j5" fixture/section_j5 "$J5_OUT_JSON"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (verify: verification-not-clean)' && jfield "$J5_OUT_JSON" detail | grep -q 'evidence-not-persisted'; then
    ok "J5 R5 M2: a verify report that cannot be persisted refuses MIGRATED (verify: verification-not-clean, detail evidence-not-persisted)"
else
    bad "J5 R5 M2: an unpersistable verify report did not refuse MIGRATED (rc=$J_RC out=$J_OUT; see $J5_OUT_JSON)"
fi
j_mutant M2_drop_evidence_not_persisted '{ [ -z "$V1_SHA" ] || [ -z "$V2_SHA" ]; } && VERIFY_FAIL="$VERIFY_FAIL evidence-not-persisted"
' ''
build_r3_fixture "$I_ROOT/j5m"
mkdir -p "$WORK/j5mdir"
ln -s "$WORK/j5m_no_such_dir/target.json" "$WORK/j5mdir/j5m.verify1.json"
j_run "$WORK/jmut_M2_drop_evidence_not_persisted.sh" "$I_ROOT/j5m" fixture/section_j5m "$WORK/j5mdir/j5m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED'; then
    ok "J5 guard-viability: the reviewer's M2 mutant claims MIGRATED with NO persisted evidence -- J5 is what catches it"
else
    bad "J5 guard-viability: the M2 mutant did not claim MIGRATED (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J6: I1 M3 -- a local branch with NO counterpart on any remote is
# refused with the specific no-published-counterpart detail. Reviewer's
# EXACT M3 anchor; the mutant falls through to the collective count and
# refuses for a DIFFERENT (wrong) reason, so the detail is what proves the
# guard ran.
build_r3_fixture "$I_ROOT/j6"
git -C "$I_ROOT/j6/checkout" checkout -q -b never-published-branch
j_run "$TOOL" "$I_ROOT/j6" fixture/section_j6 "$WORK/j6.json"
J6_DETAIL=$(jfield "$WORK/j6.json" detail)
if [ "$J_RC" -eq 1 ] && [ "$J6_DETAIL" = "branch-never-published-branch-has-no-published-counterpart-on-any-remote" ]; then
    ok "J6 R5 M3: a branch with no published counterpart on any remote is refused at preflight with the exact no-published-counterpart detail"
else
    bad "J6 R5 M3: unpublished-branch refusal missing or mislabelled (rc=$J_RC detail=$J6_DETAIL)"
fi
j_mutant M3_drop_no_published_counterpart 'if [ "$PUBLISHED_REFS" -eq 0 ]; then
    not_migrated' 'if false; then
    not_migrated'
j_run "$WORK/jmut_M3_drop_no_published_counterpart.sh" "$I_ROOT/j6" fixture/section_j6 "$WORK/j6m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$(jfield "$WORK/j6m.json" detail)" != "branch-never-published-branch-has-no-published-counterpart-on-any-remote" ]; then
    ok "J6 guard-viability: the reviewer's M3 mutant no longer produces the no-published-counterpart refusal (got rc=$J_RC detail=$(jfield "$WORK/j6m.json" detail)) -- J6 is load-bearing"
else
    bad "J6 guard-viability: the M3 mutant still produced the same refusal (mut_ok=$J_MUT_OK)"
fi

# --- J7: I4 -- a mirror LAGGING behind a commit already published on origin
# is NOT an unpublished commit: the run must migrate and bring BOTH remotes
# to the migration commit. The original finding-4 shape (an unpublished
# local product commit) is still refused (I1 above), and a local branch
# fast-forwarded onto a DIFFERENT published branch is refused too.
build_r3_fixture "$I_ROOT/j7"
git clone -q --bare "$I_ROOT/j7/consumer.git" "$I_ROOT/j7/mirror.git" >/dev/null 2>&1
J7_LAG=$(mktemp -d)
git clone -q "$I_ROOT/j7/consumer.git" "$J7_LAG" >/dev/null 2>&1
echo "published-on-origin-only" > "$J7_LAG/NOTES.md"
git -C "$J7_LAG" add NOTES.md
git -C "$J7_LAG" -c user.name=f -c user.email=f@example.invalid commit -q -m "already published on origin"
git -C "$J7_LAG" push -q origin main
rm -rf "$J7_LAG"
git -C "$I_ROOT/j7/checkout" pull -q --ff-only origin main
git -C "$I_ROOT/j7/checkout" remote add mirror "$I_ROOT/j7/mirror.git"
git -C "$I_ROOT/j7/checkout" fetch -q mirror
j_run "$TOOL" "$I_ROOT/j7" fixture/section_j7 "$WORK/j7.json"
J7_HEAD=$(git -C "$I_ROOT/j7/checkout" rev-parse HEAD)
if [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' \
    && [ "$(git -C "$I_ROOT/j7/consumer.git" rev-parse refs/heads/main)" = "$J7_HEAD" ] \
    && [ "$(git -C "$I_ROOT/j7/mirror.git" rev-parse refs/heads/main)" = "$J7_HEAD" ]; then
    ok "J7 R5 I4: a mirror lagging behind an ALREADY-PUBLISHED commit is not a false 'unpublished' refusal -- MIGRATED, origin and mirror both at the migration commit"
else
    bad "J7 R5 I4: the lagging-mirror fleet shape was refused or not converged (rc=$J_RC out=$J_OUT)"
fi
# Guard-viability for the I4 FIX: the round-3 per-remote comparison
# (re-anchored on the round-5 collective line) re-creates the false refusal.
j_mutant I4_per_remote 'UNPUBLISHED=$(git -C "$WORKDIR" rev-list --count "$LOCAL_HEAD" --not $PUBLISHED_REF_LIST 2>/dev/null)' \
    'UNPUBLISHED=0; for _r in $PUBLISHED_REF_LIST; do _a=$(git -C "$WORKDIR" rev-list --count "$_r..$LOCAL_HEAD" 2>/dev/null); [ "$_a" != "0" ] && UNPUBLISHED=$_a; done'
build_r3_fixture "$I_ROOT/j7m"
git clone -q --bare "$I_ROOT/j7m/consumer.git" "$I_ROOT/j7m/mirror.git" >/dev/null 2>&1
J7_LAG=$(mktemp -d)
git clone -q "$I_ROOT/j7m/consumer.git" "$J7_LAG" >/dev/null 2>&1
echo "published-on-origin-only" > "$J7_LAG/NOTES.md"
git -C "$J7_LAG" add NOTES.md
git -C "$J7_LAG" -c user.name=f -c user.email=f@example.invalid commit -q -m "already published on origin"
git -C "$J7_LAG" push -q origin main
rm -rf "$J7_LAG"
git -C "$I_ROOT/j7m/checkout" pull -q --ff-only origin main
git -C "$I_ROOT/j7m/checkout" remote add mirror "$I_ROOT/j7m/mirror.git"
git -C "$I_ROOT/j7m/checkout" fetch -q mirror
j_run "$WORK/jmut_I4_per_remote.sh" "$I_ROOT/j7m" fixture/section_j7m "$WORK/j7m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (preflight: divergent-branches)'; then
    ok "J7 guard-viability: the round-3 per-remote comparison falsely refuses the lagging-mirror fleet (divergent-branches) -- the collective count is what fixes it"
else
    bad "J7 guard-viability: the per-remote mutant did not reproduce the false refusal (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi
# J7b: fast-forwarding main onto a DIFFERENT published branch (an unreviewed
# feature branch) has zero commits outside `--remotes` but would publish
# that branch's product code onto main -- still refused.
build_r3_fixture "$I_ROOT/j7b"
J7B_W=$(mktemp -d)
git clone -q "$I_ROOT/j7b/consumer.git" "$J7B_W" >/dev/null 2>&1
git -C "$J7B_W" checkout -q -b feature-x
echo "/* unreviewed feature */" >> "$J7B_W/src/product.c"
git -C "$J7B_W" -c user.name=f -c user.email=f@example.invalid commit -q -am "feature-x product change"
git -C "$J7B_W" push -q origin feature-x
rm -rf "$J7B_W"
git -C "$I_ROOT/j7b/checkout" fetch -q origin
git -C "$I_ROOT/j7b/checkout" merge -q --ff-only origin/feature-x
J7B_REMOTE_BEFORE=$(git -C "$I_ROOT/j7b/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j7b" fixture/section_j7b "$WORK/j7b.json"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (preflight: divergent-branches)' \
    && [ "$J7B_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j7b/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J7b R5 I4: main fast-forwarded onto a different published branch is refused (its commits are on no remote copy of main) -- the collective count is branch-scoped, not --remotes"
else
    bad "J7b R5 I4: fast-forward onto another branch was not refused (rc=$J_RC out=$J_OUT)"
fi

# --- J8: round-4 MINOR -- a DETACHED HEAD is refused before any write; no
# local commit is left behind.
build_r3_fixture "$I_ROOT/j8"
git -C "$I_ROOT/j8/checkout" checkout -q --detach
J8_HEAD_BEFORE=$(git -C "$I_ROOT/j8/checkout" rev-parse HEAD)
j_run "$TOOL" "$I_ROOT/j8" fixture/section_j8 "$WORK/j8.json"
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j8.json" detail)" = "detached-HEAD-no-branch-to-fast-forward" ] \
    && [ "$J8_HEAD_BEFORE" = "$(git -C "$I_ROOT/j8/checkout" rev-parse HEAD)" ]; then
    ok "J8 R5 detached-HEAD: a detached checkout is refused at preflight and no local commit is left behind"
else
    bad "J8 R5 detached-HEAD: not refused before writing (rc=$J_RC out=$J_OUT head-before=$J8_HEAD_BEFORE)"
fi
j_mutant DH_no_detached_check 'if [ "$BRANCH" = "HEAD" ] || [ -z "$BRANCH" ]; then' 'if false; then'
build_r3_fixture "$I_ROOT/j8m"
git -C "$I_ROOT/j8m/checkout" checkout -q --detach
J8M_HEAD_BEFORE=$(git -C "$I_ROOT/j8m/checkout" rev-parse HEAD)
j_run "$WORK/jmut_DH_no_detached_check.sh" "$I_ROOT/j8m" fixture/section_j8m "$WORK/j8m.json"
if [ "$J_MUT_OK" -eq 1 ] && [ "$J8M_HEAD_BEFORE" != "$(git -C "$I_ROOT/j8m/checkout" rev-parse HEAD)" ]; then
    ok "J8 guard-viability: without the detached-HEAD check the mutant commits locally and leaves that commit behind (rc=$J_RC) -- the round-4 repro"
else
    bad "J8 guard-viability: the detached-HEAD mutant did not reproduce the left-behind local commit (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J9: I3 guard-viability -- dropping the already-at-target review check
# lets a MIGRATED record out with NO review_ref (F3b above is the real-tool
# half of this pair).
# (Mutant = the round-3 code: no at-target review, REVIEW_REF_ID set empty.)
j_mutant I3_no_at_target_review 'if ! check_review; then
        # T177 Round 6 (round-6 MINOR M1): re-running an already-MIGRATED
        # consumer with its ORIGINAL review (now stale -- its own base has
        # since moved to the migration commit) must NEVER downgrade the
        # existing on-disk MIGRATED record for this SAME project in place.
        # Reproduced live: a second run with the same (now-stale) review
        # overwrote outcome MIGRATED -> NOT-MIGRATED at the SAME --out path,
        # with no new write to $WORKDIR at all. A pre-existing MIGRATED
        # record for this exact project is left genuinely UNTOUCHED; the
        # refusal is reported on stderr only, never written to $OUT.
        if [ "$(read_out_field outcome)" = "MIGRATED" ] && [ "$(read_out_field project_id)" = "$PROJECT" ]; then
            echo "migrate.sh: review-no-go on the already-at-target path, but $OUT already holds a MIGRATED record for $PROJECT -- left UNTOUCHED (re-run with a FRESH review bound to the migration commit to re-verify)" >&2
            exit 1
        fi
        not_migrated "review" "review-no-go"' 'REVIEW_REF_ID=""
    if false; then
        not_migrated "review" "review-no-go"'
F_CHECKOUT3="$F_ROOT/checkout3"
git clone -q --no-hardlinks "$F_BARE" "$F_CHECKOUT3" >/dev/null 2>&1
J9_OUT=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_I3_no_at_target_review.sh" --config "$CFG" --project "fixture/section_f_verify_load_bearing" \
    --workdir "$F_CHECKOUT3" --out "$WORK/j9m.json" --apply 2>&1); J9_RC=$?
if [ "$J_MUT_OK" -eq 1 ] && [ "$J9_RC" -eq 0 ] && [ "$(jfield "$WORK/j9m.json" outcome)" = "MIGRATED" ] && [ -z "$(jfield "$WORK/j9m.json" review_ref)" ]; then
    ok "J9 guard-viability: without the at-target review check the mutant writes a MIGRATED record with NO review_ref -- exactly the round-4 I3 gap F3b now refuses"
else
    bad "J9 guard-viability: the at-target-review mutant did not reproduce the review_ref-less MIGRATED record (mut_ok=$J_MUT_OK rc=$J9_RC out=$J9_OUT)"
fi

# --- J10: the B1 scanner's OWN failure must refuse (conservative-safe,
# §11.4.201), never publish uninspected content. Forced for real: a PATH
# shim wraps python3 and fails ONLY the symlink-scanner invocation (matched
# by its own source text), passing every other call to the real python3.
J10_BIN="$WORK/j10_bin"
mkdir -p "$J10_BIN"
J10_REAL_PY=$(command -v python3)
cat > "$J10_BIN/python3" <<EOF
#!/bin/sh
for a in "\$@"; do
    case "\$a" in *host-specific-symlink*) echo "j10 shim: scanner forced to fail" >&2; exit 3 ;; esac
done
exec "$J10_REAL_PY" "\$@"
EOF
chmod +x "$J10_BIN/python3"
build_r3_fixture "$I_ROOT/j10" "$J1C_HOOK"
J10_REMOTE_BEFORE=$(git -C "$I_ROOT/j10/consumer.git" rev-parse refs/heads/main)
J10_SAVED_PATH=$PATH; PATH="$J10_BIN:$PATH"
j_run "$TOOL" "$I_ROOT/j10" fixture/section_j10 "$WORK/j10.json"
PATH=$J10_SAVED_PATH
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j10.json" detail)" = "symlink-scan-failed" ] \
    && [ "$J10_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j10/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J10 R5 B1 fail-closed: when the symlink scanner itself cannot run, the migration is refused (detail symlink-scan-failed), remote unchanged"
else
    bad "J10 R5 B1 fail-closed: a failed symlink scan did not refuse (rc=$J_RC out=$J_OUT; see $WORK/j10.json)"
fi
j_mutant B1_scan_failure_ignored 'if [ "$SYMLINK_RC" -ne 0 ]; then' 'if false; then'
build_r3_fixture "$I_ROOT/j10m" "$J1C_HOOK"
J10M_REMOTE_BEFORE=$(git -C "$I_ROOT/j10m/consumer.git" rev-parse refs/heads/main)
PATH="$J10_BIN:$PATH"
j_run "$WORK/jmut_B1_scan_failure_ignored.sh" "$I_ROOT/j10m" fixture/section_j10m "$WORK/j10m.json"
PATH=$J10_SAVED_PATH
if [ "$J_MUT_OK" -eq 1 ] && [ "$J10M_REMOTE_BEFORE" != "$(git -C "$I_ROOT/j10m/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J10 guard-viability: ignoring the scanner's failure publishes content no scan inspected (rc=$J_RC) -- J10 is load-bearing"
else
    bad "J10 guard-viability: the scan-failure mutant did not publish (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# =============================================================================
# J11-J18 -- T177 Round 6 (round-6 review of the round-5 remediation):
# B1 (scanner fail-open on git sub-command failure), I1 (M/T diff-filter
# coverage), I2 (staged gitlinks), I3 (relative --out), I6 (per-remote scope
# of newly-delivered commits), M1 (idempotent re-run never downgrades a
# MIGRATED record). Every guard is paired with a mutation that reproduces
# the reviewer's EXACT repro on a FRESH fixture, scratch-copied (never the
# tracked file).
# =============================================================================

# --- J11: BLOCKING B1 round-6 fix -- a failed `git cat-file blob` INSIDE
# the symlink scanner must refuse (symlink-scan-failed), never decode the
# failed read as an empty/clean target. A PATH shim on `git` forces ONLY
# `cat-file blob <sha>` to fail; every other git invocation (the scanner's
# own enumeration, the rest of the tool's pipeline, and repo_verify.py's
# own git calls) passes through to the real git untouched.
J11_REAL_GIT=$(command -v git)
J11_BIN="$WORK/j11_bin"
mkdir -p "$J11_BIN"
cat > "$J11_BIN/git" <<EOF
#!/bin/sh
# Real invocation is "git -C <workdir> cat-file blob <sha>" -- "-C" is \$1,
# so the "cat-file"/"blob" pair must be found ANYWHERE in the argument
# list, not pinned to \$1/\$2.
_prev=""
for a in "\$@"; do
    if [ "\$_prev" = "cat-file" ] && [ "\$a" = "blob" ]; then
        echo "j11 shim: git cat-file blob forced to fail" >&2
        exit 1
    fi
    _prev=\$a
done
exec "$J11_REAL_GIT" "\$@"
EOF
chmod +x "$J11_BIN/git"
build_r3_fixture "$I_ROOT/j11" "$J1_HOOK"
J11_REMOTE_BEFORE=$(git -C "$I_ROOT/j11/consumer.git" rev-parse refs/heads/main)
J11_SAVED_PATH=$PATH; PATH="$J11_BIN:$PATH"
j_run "$TOOL" "$I_ROOT/j11" fixture/section_j11 "$WORK/j11.json"
PATH=$J11_SAVED_PATH
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j11.json" detail)" = "symlink-scan-failed" ] \
    && [ "$J11_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j11/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J11 R6 B1: a failed 'git cat-file blob' inside the symlink scanner refuses the migration (symlink-scan-failed), remote unchanged -- a failed blob read is no longer decoded as a clean/empty target"
else
    bad "J11 R6 B1: a failed cat-file read inside the scanner did not refuse (rc=$J_RC out=$J_OUT; see $WORK/j11.json)"
fi
j_mutant B1_ignore_catfile_rc \
    'cat = subprocess.run(["git", "-C", workdir, "cat-file", "blob", blob],
                         capture_output=True)
    if cat.returncode != 0:
        sys.exit(3)
    target = cat.stdout.decode("utf-8", "surrogateescape")' \
    'target = subprocess.run(["git", "-C", workdir, "cat-file", "blob", blob],
                         capture_output=True).stdout.decode("utf-8", "surrogateescape")'
build_r3_fixture "$I_ROOT/j11m" "$J1_HOOK"
PATH="$J11_BIN:$PATH"
j_run "$WORK/jmut_B1_ignore_catfile_rc.sh" "$I_ROOT/j11m" fixture/section_j11m "$WORK/j11m.json"
PATH=$J11_SAVED_PATH
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED'; then
    ok "J11 guard-viability: reverting to the round-5 cat-file-rc-blind scanner lets a blob whose read FAILED decode as an empty/clean target -- the absolute-path symlink MIGRATES -- J11 is what catches it"
else
    bad "J11 guard-viability: the cat-file-rc mutant did not reproduce the fail-open (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J12: BLOCKING B1 round-6 fix -- a failed `git diff --cached --raw`
# enumeration (the scanner's OWN input) must refuse too, never feed python3
# an empty stdin that legitimately exits 0. The shim fails ONLY a `diff`
# invocation carrying `--raw` (the scanner's own query) -- the OTHER `git
# diff --cached --name-only` (the CA-022 scope check) and every other git
# call passes through untouched.
J12_REAL_GIT=$(command -v git)
J12_BIN="$WORK/j12_bin"
mkdir -p "$J12_BIN"
cat > "$J12_BIN/git" <<EOF
#!/bin/sh
# Real invocation is "git -C <workdir> diff --cached --raw ..." -- "-C" is
# \$1, so "diff" and "--raw" must both be found ANYWHERE in the argument
# list (never pinned to \$1), distinguishing this from the OTHER "git diff
# --cached --name-only" call (the CA-022 scope check, no --raw) which must
# keep passing through untouched.
_has_diff=0; _has_raw=0
for a in "\$@"; do
    [ "\$a" = "diff" ] && _has_diff=1
    [ "\$a" = "--raw" ] && _has_raw=1
done
if [ "\$_has_diff" = "1" ] && [ "\$_has_raw" = "1" ]; then
    echo "j12 shim: git diff --cached --raw forced to fail" >&2
    exit 1
fi
exec "$J12_REAL_GIT" "\$@"
EOF
chmod +x "$J12_BIN/git"
build_r3_fixture "$I_ROOT/j12" "$J1_HOOK"
J12_REMOTE_BEFORE=$(git -C "$I_ROOT/j12/consumer.git" rev-parse refs/heads/main)
J12_SAVED_PATH=$PATH; PATH="$J12_BIN:$PATH"
j_run "$TOOL" "$I_ROOT/j12" fixture/section_j12 "$WORK/j12.json"
PATH=$J12_SAVED_PATH
if [ "$J_RC" -eq 1 ] && [ "$(jfield "$WORK/j12.json" detail)" = "symlink-scan-failed" ] \
    && [ "$J12_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j12/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J12 R6 B1: a failed 'git diff --cached --raw' enumeration refuses the migration (symlink-scan-failed) before python3 ever runs, remote unchanged"
else
    bad "J12 R6 B1: a failed diff enumeration did not refuse (rc=$J_RC out=$J_OUT; see $WORK/j12.json)"
fi
# Simpler-but-equivalent mutant: drop ONLY the "check the enumeration's own
# exit status" wrapper, leaving the capture-to-file and the python3
# invocation untouched. On a forced diff failure this still writes an
# EMPTY $SYMLINK_DIFF (the redirection runs regardless of the command's own
# exit status) -- python3 then reads zero bytes, its while-loop never
# executes, and it exits 0 with no violation printed: the SAME "silent
# clean on enumeration failure" bug, reached without needing to touch the
# python3 invocation's own quoting at all.
j_mutant B1_pipe_diff_unchecked \
    'SYMLINK_DIFF="$MIGRATE_SCRATCH/migrate_symlink_diff.raw"
    if ! git -C "$WORKDIR" diff --cached --raw -z --no-renames --diff-filter=AMT >"$SYMLINK_DIFF" 2>/dev/null; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "symlink-scan-failed"
    fi' \
    'SYMLINK_DIFF="$MIGRATE_SCRATCH/migrate_symlink_diff.raw"
    git -C "$WORKDIR" diff --cached --raw -z --no-renames --diff-filter=AMT >"$SYMLINK_DIFF" 2>/dev/null'
build_r3_fixture "$I_ROOT/j12m" "$J1_HOOK"
PATH="$J12_BIN:$PATH"
j_run "$WORK/jmut_B1_pipe_diff_unchecked.sh" "$I_ROOT/j12m" fixture/section_j12m "$WORK/j12m.json"
PATH=$J12_SAVED_PATH
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED'; then
    ok "J12 guard-viability: dropping the enumeration's own exit-status check leaves an EMPTY \$SYMLINK_DIFF on a forced diff failure -- python3 reads zero bytes and exits 0 with no violation -- the absolute-path symlink MIGRATES -- J12 is what catches it"
else
    bad "J12 guard-viability: the unchecked-pipeline mutant did not reproduce the fail-open (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT)"
fi

# --- J13/J14: IMPORTANT I1 round-6 fix -- the --diff-filter=AMT already
# includes M (modified) and T (type-changed), but no fixture exercised
# either half; a mutant narrowing the filter to A-only survived. J13: the
# REAL post_update_hook.sh's own `rm -f "$dst"; ln -s "$src" "$dst"` pattern
# over an EXISTING committed relative link (git status M). J14: a regular
# file replaced by an absolute symlink (git status T, type-change).
J13_HOOK="$WORK/j13_relink_absolute_hook.sh"
cat > "$J13_HOOK" <<'EOF'
#!/usr/bin/env bash
rm -f "$PROJECT_ROOT/skills/media-validator"
ln -s "${CONST_DIR}/skills/media-validator" "$PROJECT_ROOT/skills/media-validator"
EOF
build_r3_fixture "$I_ROOT/j13" "$J13_HOOK"
mkdir -p "$I_ROOT/j13/checkout/skills"
ln -s "../constitution/skills/media-validator" "$I_ROOT/j13/checkout/skills/media-validator"
git -C "$I_ROOT/j13/checkout" add skills/media-validator
git -C "$I_ROOT/j13/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -m "pre-existing portable skill link"
git -C "$I_ROOT/j13/checkout" push -q origin main
J13_REMOTE_BEFORE=$(git -C "$I_ROOT/j13/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j13" fixture/section_j13 "$WORK/j13.json"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && jfield "$WORK/j13.json" detail | grep -q 'host-specific-symlink path=skills/media-validator target-is-absolute' \
    && [ "$J13_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j13/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J13 R6 I1: a hook that re-links an ALREADY-COMMITTED relative symlink to an absolute target (git status M, the real hook's rm -f + ln -s shape over an existing link) is refused exactly like an added link -- --diff-filter=AMT's M half is genuinely exercised"
else
    bad "J13 R6 I1: a modified (M) host-specific symlink was not refused (rc=$J_RC out=$J_OUT; see $WORK/j13.json)"
fi

J14_HOOK="$WORK/j14_type_change_hook.sh"
cat > "$J14_HOOK" <<'EOF'
#!/usr/bin/env bash
rm -f "$PROJECT_ROOT/skills/media-validator"
ln -s "${CONST_DIR}/skills/media-validator" "$PROJECT_ROOT/skills/media-validator"
EOF
build_r3_fixture "$I_ROOT/j14" "$J14_HOOK"
mkdir -p "$I_ROOT/j14/checkout/skills"
echo "placeholder, not yet a symlink" > "$I_ROOT/j14/checkout/skills/media-validator"
git -C "$I_ROOT/j14/checkout" add skills/media-validator
git -C "$I_ROOT/j14/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -m "pre-existing regular file at the skill path"
git -C "$I_ROOT/j14/checkout" push -q origin main
J14_REMOTE_BEFORE=$(git -C "$I_ROOT/j14/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j14" fixture/section_j14 "$WORK/j14.json"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && jfield "$WORK/j14.json" detail | grep -q 'host-specific-symlink path=skills/media-validator target-is-absolute' \
    && [ "$J14_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j14/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J14 R6 I1: a hook that replaces a pre-existing REGULAR FILE with an absolute symlink (git status T, type-change) is refused -- --diff-filter=AMT's T half is genuinely exercised"
else
    bad "J14 R6 I1: a type-changed (T) host-specific symlink was not refused (rc=$J_RC out=$J_OUT; see $WORK/j14.json)"
fi

j_mutant I1_diff_filter_A_only '--diff-filter=AMT' '--diff-filter=A'
build_r3_fixture "$I_ROOT/j13m" "$J13_HOOK"
mkdir -p "$I_ROOT/j13m/checkout/skills"
ln -s "../constitution/skills/media-validator" "$I_ROOT/j13m/checkout/skills/media-validator"
git -C "$I_ROOT/j13m/checkout" add skills/media-validator
git -C "$I_ROOT/j13m/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -m "pre-existing portable skill link"
git -C "$I_ROOT/j13m/checkout" push -q origin main
j_run "$WORK/jmut_I1_diff_filter_A_only.sh" "$I_ROOT/j13m" fixture/section_j13m "$WORK/j13m.json"
J13M_LINK=$(git -C "$I_ROOT/j13m/consumer.git" cat-file -p "refs/heads/main:skills/media-validator" 2>/dev/null)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J13M_LINK" | grep -q '^/'; then
    ok "J13 guard-viability: narrowing --diff-filter to A-only lets a MODIFIED (M) host-specific symlink through -- J13/J14 are what catch the M/T half"
else
    bad "J13 guard-viability: the diff-filter=A mutant did not reproduce the M-symlink publication (mut_ok=$J_MUT_OK rc=$J_RC link=$J13M_LINK)"
fi
build_r3_fixture "$I_ROOT/j14m" "$J14_HOOK"
mkdir -p "$I_ROOT/j14m/checkout/skills"
echo "placeholder, not yet a symlink" > "$I_ROOT/j14m/checkout/skills/media-validator"
git -C "$I_ROOT/j14m/checkout" add skills/media-validator
git -C "$I_ROOT/j14m/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -m "pre-existing regular file at the skill path"
git -C "$I_ROOT/j14m/checkout" push -q origin main
j_run "$WORK/jmut_I1_diff_filter_A_only.sh" "$I_ROOT/j14m" fixture/section_j14m "$WORK/j14m.json"
J14M_LINK=$(git -C "$I_ROOT/j14m/consumer.git" cat-file -p "refs/heads/main:skills/media-validator" 2>/dev/null)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J14M_LINK" | grep -q '^/'; then
    ok "J14 guard-viability: narrowing --diff-filter to A-only also lets a TYPE-CHANGED (T) host-specific symlink through"
else
    bad "J14 guard-viability: the diff-filter=A mutant did not reproduce the T-symlink publication (mut_ok=$J_MUT_OK rc=$J_RC link=$J14M_LINK)"
fi

# --- J15: IMPORTANT I2 round-6 fix -- a staged gitlink (mode 160000, a
# hook that `git init`s + commits INSIDE an allow-listed directory) whose
# commit exists ONLY on this host is refused BEFORE commit/push -- never
# only caught after the fact by step 9's post-push verify (by then it is
# already irreversibly published, no force-push, §11.4.113).
J15_HOOK="$WORK/j15_nested_repo_hook.sh"
cat > "$J15_HOOK" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$PROJECT_ROOT/skills/emb"
cd "$PROJECT_ROOT/skills/emb"
git init -q
git -c user.name=h -c user.email=h@example.invalid commit -q --allow-empty -m "host-only nested commit"
EOF
build_r3_fixture "$I_ROOT/j15" "$J15_HOOK"
J15_REMOTE_BEFORE=$(git -C "$I_ROOT/j15/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j15" fixture/section_j15 "$WORK/j15.json"
J15_DETAIL=$(jfield "$WORK/j15.json" detail)
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (wiring: out-of-scope-diff)' \
    && echo "$J15_DETAIL" | grep -q 'unexpected-gitlink path=skills/emb' \
    && [ "$J15_REMOTE_BEFORE" = "$(git -C "$I_ROOT/j15/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J15 R6 I2: a staged gitlink under an allow-listed path (a nested git-init commit that exists only on this host) is refused BEFORE commit/push, remote unchanged"
else
    bad "J15 R6 I2: a host-only nested gitlink was not refused before publishing (rc=$J_RC out=$J_OUT detail=$J15_DETAIL; see $WORK/j15.json)"
fi
j_mutant I2_no_gitlink_check 'if [ -n "$GITLINK_VIOLATION" ]; then' 'if false; then'
build_r3_fixture "$I_ROOT/j15m" "$J15_HOOK"
j_run "$WORK/jmut_I2_no_gitlink_check.sh" "$I_ROOT/j15m" fixture/section_j15m "$WORK/j15m.json"
J15M_MODE=$(git -C "$I_ROOT/j15m/consumer.git" ls-tree refs/heads/main skills/emb 2>/dev/null | awk '{print $1}')
# The vulnerability is the PUBLICATION itself (irreversible, §11.4.113) --
# regardless of whether the OVERALL run later reports MIGRATED or an
# unrelated NOT-MIGRATED (e.g. step 9's verify noticing the uninitialised
# nested gitlink afterward, exactly the finding's own "honest only because
# step 9 runs AFTER the push" framing). rc is therefore not asserted here.
if [ "$J_MUT_OK" -eq 1 ] && [ "$J15M_MODE" = "160000" ]; then
    ok "J15 guard-viability: without the gitlink check a host-only nested commit is published as a permanent, unfetchable gitlink -- J15 is what catches it"
else
    bad "J15 guard-viability: the gitlink-check mutant did not reproduce the gitlink publication (mut_ok=$J_MUT_OK rc=$J_RC mode=$J15M_MODE)"
fi

# --- J16: IMPORTANT I3 round-6 fix -- a RELATIVE --out from a cwd
# different from where the record ends up must still be counted by
# `audit.py summary` (the real end-to-end path, not mkrec's synthetic
# already-relative-to-record-dir paths).
# The --out argument is deliberately ONE PLAIN LEVEL below the tool's own
# invocation cwd ("migrations/j16.json" from "$I_ROOT/j16"), never "../..."
# -- a "../migrations/x" string happens to resolve to the SAME file whether
# computed from the tool's cwd or from the record's own directory (the
# ".." cancels back into "migrations"), which would mask this exact bug.
# A bare one-level-down relative path has no such coincidental symmetry:
# resolved against the tool's cwd it is correct; resolved against the
# record's own directory (what audit.py actually does) it is NOT, unless
# the tool itself canonicalised --out to an absolute path first.
build_r3_fixture "$I_ROOT/j16"
J16_RUNDIR="$I_ROOT/j16"
J16_OUTDIR="$I_ROOT/j16/migrations"
mkdir -p "$J16_OUTDIR" "$I_ROOT/j16/empty_audits"
J16_REF=$(make_review_ref "fixture/section_j16" "$R3_NEW" "$(git -C "$I_ROOT/j16/checkout" rev-parse HEAD)")
J16_RUN_OUT=$(cd "$J16_RUNDIR" && FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j16" \
    --workdir "$I_ROOT/j16/checkout" --out "migrations/j16.json" --apply --review-ref "$J16_REF" 2>&1); J16_RUN_RC=$?
if [ "$J16_RUN_RC" -eq 0 ] && echo "$J16_RUN_OUT" | grep -q '^MIGRATED'; then
    ok "J16 R6 I3 precondition: the real migration with a RELATIVE --out MIGRATED"
else
    bad "J16 R6 I3 precondition: the real migration with a RELATIVE --out did not MIGRATE (rc=$J16_RUN_RC out=$J16_RUN_OUT)"
fi
cat > "$WORK/j16_consumers.json" <<EOF
{"projects":[{"project_id":"fixture/section_j16"}]}
EOF
J16_SUMMARY="$WORK/j16_summary.json"
python3 "$FC/consumers/audit.py" summary --consumers "$WORK/j16_consumers.json" \
    --audits "$I_ROOT/j16/empty_audits" --migrations "$J16_OUTDIR" --out "$J16_SUMMARY" >"$WORK/j16_audit.log" 2>&1
if python3 -c "
import json, sys
d = json.load(open('$J16_SUMMARY'))
sys.exit(0 if d.get('migrated') == 1 and d.get('coverage') == 1.0 else 1)
" 2>/dev/null; then
    ok "J16 R6 I3: audit.py summary counts a genuinely MIGRATED record written with a RELATIVE --out as migrated=1, coverage=1.0 (verification evidence resolves correctly regardless of the caller's cwd at invocation time)"
else
    bad "J16 R6 I3: a relative --out migration was not counted by summary (see $J16_SUMMARY, $WORK/j16_audit.log)"
fi
j_mutant I3_no_out_canon \
    'OUT_DIR=$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)
if [ -z "$OUT_DIR" ]; then
    echo "migrate.sh: the directory for --out $OUT does not exist" >&2
    exit 2
fi
OUT="$OUT_DIR/$(basename "$OUT")"' \
    ': # T177 Round 6 I3 mutant: OUT canonicalisation disabled, left relative'
build_r3_fixture "$I_ROOT/j16m"
J16M_RUNDIR="$I_ROOT/j16m"
J16M_OUTDIR="$I_ROOT/j16m/migrations"
mkdir -p "$J16M_OUTDIR" "$I_ROOT/j16m/empty_audits"
J16M_REF=$(make_review_ref "fixture/section_j16m" "$R3_NEW" "$(git -C "$I_ROOT/j16m/checkout" rev-parse HEAD)")
(cd "$J16M_RUNDIR" && FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_I3_no_out_canon.sh" --config "$CFG" --project "fixture/section_j16m" \
    --workdir "$I_ROOT/j16m/checkout" --out "migrations/j16m.json" --apply --review-ref "$J16M_REF" >"$WORK/j16m_run.log" 2>&1)
cat > "$WORK/j16m_consumers.json" <<EOF
{"projects":[{"project_id":"fixture/section_j16m"}]}
EOF
python3 "$FC/consumers/audit.py" summary --consumers "$WORK/j16m_consumers.json" \
    --audits "$I_ROOT/j16m/empty_audits" --migrations "$J16M_OUTDIR" --out "$WORK/j16m_summary.json" >"$WORK/j16m_audit.log" 2>&1
if [ "$J_MUT_OK" -eq 1 ] && python3 -c "
import json, sys
d = json.load(open('$WORK/j16m_summary.json'))
sys.exit(0 if d.get('migrated') == 0 and d.get('coverage') == 0.0 else 1)
" 2>/dev/null; then
    ok "J16 guard-viability: without OUT canonicalisation a genuinely MIGRATED record written with a relative --out reads as uncounted (migrated=0, coverage=0.0) -- J16/the I3 fix is what makes it count"
else
    bad "J16 guard-viability: the no-OUT-canon mutant still counted the record (mut_ok=$J_MUT_OK; see $WORK/j16m_summary.json)"
fi

# --- J17: IMPORTANT I6 round-6 fix -- a product-code commit published to
# ONLY ONE mirror (never to origin or any other remote) must not be
# propagated onto EVERY remote's copy of main by this tool -- the
# collective (union) unpublished-commit count alone treats it as
# "already published" the instant it exists on ANY remote.
build_r3_fixture "$I_ROOT/j17"
git clone -q --bare "$I_ROOT/j17/consumer.git" "$I_ROOT/j17/m3.git" >/dev/null 2>&1
git -C "$I_ROOT/j17/checkout" remote add m3 "$I_ROOT/j17/m3.git"
echo "/* unreviewed product change, m3-only-marker */" >> "$I_ROOT/j17/checkout/src/product.c"
git -C "$I_ROOT/j17/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -am "product change, m3-only"
git -C "$I_ROOT/j17/checkout" push -q m3 main
git -C "$I_ROOT/j17/checkout" fetch -q m3
J17_ORIGIN_BEFORE=$(git -C "$I_ROOT/j17/consumer.git" rev-parse refs/heads/main)
j_run "$TOOL" "$I_ROOT/j17" fixture/section_j17 "$WORK/j17.json"
if [ "$J_RC" -eq 1 ] && echo "$J_OUT" | grep -q 'NOT-MIGRATED (preflight: divergent-branches)' \
    && [ "$J17_ORIGIN_BEFORE" = "$(git -C "$I_ROOT/j17/consumer.git" rev-parse refs/heads/main)" ]; then
    ok "J17 R6 I6: a product-code commit published to only ONE mirror is refused before publishing it to every other remote's copy of main; origin unchanged"
else
    bad "J17 R6 I6: a mirror-only product commit was not refused (rc=$J_RC out=$J_OUT; origin before=$J17_ORIGIN_BEFORE after=$(git -C "$I_ROOT/j17/consumer.git" rev-parse refs/heads/main))"
fi
j_mutant I6_no_per_remote_scope_check \
    'NEW_TO_R=$(git -C "$WORKDIR" rev-list "$LOCAL_HEAD" --not "$RREF" 2>/dev/null)
    [ -z "$NEW_TO_R" ] && continue' \
    'NEW_TO_R=""
    [ -z "$NEW_TO_R" ] && continue'
build_r3_fixture "$I_ROOT/j17m"
git clone -q --bare "$I_ROOT/j17m/consumer.git" "$I_ROOT/j17m/m3.git" >/dev/null 2>&1
git -C "$I_ROOT/j17m/checkout" remote add m3 "$I_ROOT/j17m/m3.git"
echo "/* unreviewed product change, m3-only-marker */" >> "$I_ROOT/j17m/checkout/src/product.c"
git -C "$I_ROOT/j17m/checkout" -c user.name=f -c user.email=f@example.invalid commit -q -am "product change, m3-only"
git -C "$I_ROOT/j17m/checkout" push -q m3 main
git -C "$I_ROOT/j17m/checkout" fetch -q m3
j_run "$WORK/jmut_I6_no_per_remote_scope_check.sh" "$I_ROOT/j17m" fixture/section_j17m "$WORK/j17m.json"
J17M_ORIGIN_PRODUCT=$(git -C "$I_ROOT/j17m/consumer.git" show refs/heads/main:src/product.c 2>&1)
if [ "$J_MUT_OK" -eq 1 ] && [ "$J_RC" -eq 0 ] && echo "$J_OUT" | grep -q '^MIGRATED' \
    && echo "$J17M_ORIGIN_PRODUCT" | grep -q 'm3-only-marker'; then
    ok "J17 guard-viability: without the per-remote scope check the mirror-only product commit is pushed to EVERY remote's main (including origin) -- J17 is what catches it"
else
    bad "J17 guard-viability: the no-per-remote-check mutant did not reproduce the propagation (mut_ok=$J_MUT_OK rc=$J_RC out=$J_OUT; origin-product=$J17M_ORIGIN_PRODUCT)"
fi

# --- J18: MINOR M1 round-6 fix -- re-running an already-MIGRATED consumer
# with its ORIGINAL (now-stale) review never downgrades the existing
# MIGRATED record in place.
build_r3_fixture "$I_ROOT/j18"
J18_REF=$(make_review_ref "fixture/section_j18" "$R3_NEW" "$(git -C "$I_ROOT/j18/checkout" rev-parse HEAD)")
J18_OUT1=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j18" \
    --workdir "$I_ROOT/j18/checkout" --out "$WORK/j18.json" --apply --review-ref "$J18_REF" 2>&1); J18_RC1=$?
if [ "$J18_RC1" -eq 0 ] && echo "$J18_OUT1" | grep -q '^MIGRATED'; then
    ok "J18 R6 M1 precondition: the first run genuinely MIGRATED"
else
    bad "J18 R6 M1 precondition: the first run did not MIGRATE (rc=$J18_RC1 out=$J18_OUT1)"
fi
J18_OUT2=$(FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$TOOL" --config "$CFG" --project "fixture/section_j18" \
    --workdir "$I_ROOT/j18/checkout" --out "$WORK/j18.json" --apply --review-ref "$J18_REF" 2>&1); J18_RC2=$?
J18_OUTCOME_AFTER=$(jfield "$WORK/j18.json" outcome)
if [ "$J18_RC2" -eq 1 ] && [ "$J18_OUTCOME_AFTER" = "MIGRATED" ] && echo "$J18_OUT2" | grep -q 'left UNTOUCHED'; then
    ok "J18 R6 M1: re-running with the ORIGINAL (now-stale) review refuses (review-no-go) but LEAVES the existing MIGRATED record untouched -- the record never downgrades in place"
else
    bad "J18 R6 M1: the second run downgraded or corrupted the existing MIGRATED record (rc=$J18_RC2 outcome-after=$J18_OUTCOME_AFTER out=$J18_OUT2; see $WORK/j18.json)"
fi
j_mutant M1_overwrite_migrated_on_rerun \
    'if [ "$(read_out_field outcome)" = "MIGRATED" ] && [ "$(read_out_field project_id)" = "$PROJECT" ]; then
            echo "migrate.sh: review-no-go on the already-at-target path, but $OUT already holds a MIGRATED record for $PROJECT -- left UNTOUCHED (re-run with a FRESH review bound to the migration commit to re-verify)" >&2
            exit 1
        fi' \
    ': # T177 Round 6 M1 mutant: the re-run guard is disabled'
build_r3_fixture "$I_ROOT/j18m"
J18M_REF=$(make_review_ref "fixture/section_j18m" "$R3_NEW" "$(git -C "$I_ROOT/j18m/checkout" rev-parse HEAD)")
FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_M1_overwrite_migrated_on_rerun.sh" --config "$CFG" --project "fixture/section_j18m" \
    --workdir "$I_ROOT/j18m/checkout" --out "$WORK/j18m.json" --apply --review-ref "$J18M_REF" >/dev/null 2>&1
FASTCYCLE_VERIFY_TOOL_OVERRIDE="$VERIFY_TOOL" sh "$WORK/jmut_M1_overwrite_migrated_on_rerun.sh" --config "$CFG" --project "fixture/section_j18m" \
    --workdir "$I_ROOT/j18m/checkout" --out "$WORK/j18m.json" --apply --review-ref "$J18M_REF" >/dev/null 2>&1
if [ "$J_MUT_OK" -eq 1 ] && [ "$(jfield "$WORK/j18m.json" outcome)" = "NOT-MIGRATED" ]; then
    ok "J18 guard-viability: without the re-run guard, a second run with the SAME stale review downgrades the on-disk record from MIGRATED to NOT-MIGRATED in place -- J18 is what catches it"
else
    bad "J18 guard-viability: the overwrite-guard mutant did not reproduce the downgrade (mut_ok=$J_MUT_OK; see $WORK/j18m.json)"
fi

rm -rf "$I_ROOT" 2>/dev/null || true

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
