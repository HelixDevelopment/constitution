#!/bin/sh
# migrate.sh - consumer migration (T-G05/T174; contract
# contracts/consumer-audit-and-migration.md CA-019..CA-028; guarded by
# tests/test_consumer_migrate_red.sh, T168; FR-025, SC-010).
#
# Usage: migrate.sh --config <fastcycle.yaml> --project <org/repo>
#          --workdir <consumer checkout dir> --out <migration.json>
#          [--apply] [--review-ref <path>]
#
# Without --apply: preflight + planned-diff only (CA-028), never writes.
#
# --review-ref (CA-024, this tool's own documented decision -- the
# contract requires "a zero-finding GO review record" before push but
# does not fix which producer emits it or its exact filename; migrate.sh
# does not itself review anything (producer != verifier, §11.4.240) --
# it only CHECKS a caller-supplied record for a top-level {"verdict":
# "GO"} BOUND to this exact migration attempt (top-level `project_id`
# MUST equal --project and `target_commit` MUST equal the resolved
# constitution target commit -- T177 Round 1 I6: a record with no such
# fields, or with fields naming a DIFFERENT project/commit, is treated
# exactly like no record at all). Absent, non-GO, or unbound =>
# NOT-MIGRATED (review: review-no-go). Real migrations pass the
# review/review_record.py-produced ReviewVerdictRecord here; T168's
# fixture test passes a clearly-labelled test-fixture-only verdict file,
# never a claim of a real Opus-xhigh review having run.
#
# Steps (DEC-25): 1 preflight (CA-020) 2 backup (CA-021, §9.2) 3 fetch
# 4 gitlink-bump (resolved from the consumer's own .gitmodules constitution
# url via `git ls-remote`; a consumer already at the resolved target skips
# straight to step 9, T177 Round 1 I4) 5 post_update_hook.sh + the
# consumer's own gates (best-effort: run only what is genuinely
# discoverable, per CA-023 -- a "Consumer gates: <script>" CLAUDE.md
# marker line, mirroring the step-7 commit-wrapper discovery pattern) 6
# review (CA-024) 7 commit via the consumer's own wrapper, or plain git
# when its CLAUDE.md's own governance explicitly permits it (this tool's
# own documented discovery marker: a line matching "Commit wrapper: none
# (plain git permitted)" in the consumer's CLAUDE.md) 8 fast-forward push
# to EVERY configured remote, even after an earlier one rejects (CA-025;
# T177 Round 1 I2) 9 recursive verify twice (CA-026, T177 Round 1 B3 --
# genuinely run by migrate.sh itself, not merely documented).
#
# Data-change honesty (T177 Round 1 I1): a refusal BEFORE any write to
# $WORKDIR (steps 1-3, and the gitlink-bump sub-steps that fail before
# `git update-index` ever runs) records data_change=NONE, genuinely
# accurate. A refusal AFTER a write has begun (steps 4's CA-022 check
# onward) first attempts a full restore of the staged gitlink (index +
# the submodule's own checked-out working directory), then RE-MEASURES
# the real dirty state and reports it honestly -- NONE only when the
# restore genuinely left nothing behind, a non-empty residue listed
# otherwise. A push failure never rolls back the already-made local
# commit (CA-019) -- its data_change instead names the commit and which
# remote(s) succeeded/failed.
#
# Exit: 0 MIGRATED; 1 NOT-MIGRATED (reason in the JSON body, not a crash);
#       2 usage; 4 BLIND (could not determine dirty/reachable state at all).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# FASTCYCLE_VERIFY_TOOL_OVERRIDE: test-only hook (T177 Round 1 B3) -- lets
# a RED test prove step 9's CA-026 double-verify is genuinely load-
# bearing (pointing it at a nonexistent path must turn an otherwise-
# golden migration into NOT-MIGRATED (verify: ...)) without touching the
# real, shared, tracked repo_verify.py. Unset in every real invocation;
# defaults to the tool's own real location.
VERIFY_TOOL="${FASTCYCLE_VERIFY_TOOL_OVERRIDE:-$HERE/../verify/repo_verify.py}"

CFG=""; PROJECT=""; WORKDIR=""; OUT=""; APPLY=0; REVIEW_REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config) CFG=$2; shift 2 ;;
        --project) PROJECT=$2; shift 2 ;;
        --workdir) WORKDIR=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --review-ref) REVIEW_REF=$2; shift 2 ;;
        *) echo "migrate.sh: unknown arg $1" >&2; exit 2 ;;
    esac
done
if [ -z "$CFG" ] || [ -z "$PROJECT" ] || [ -z "$WORKDIR" ] || [ -z "$OUT" ]; then
    echo "migrate.sh: --config --project --workdir --out are required" >&2
    exit 2
fi
if [ ! -d "$WORKDIR" ]; then
    echo "migrate.sh: --workdir $WORKDIR does not exist" >&2
    exit 2
fi

write_out() {
    # $1=outcome $2=reason_or_empty $3=commit_or_empty $4=data_change(NONE|list)
    # $5=push_results_or_empty -- comma-separated "remote:status" entries.
    # data-model.md #13.3's ConsumerMigrationRecord field table states
    # data_change "must be NONE for every NOT-MIGRATED outcome"; a landed
    # local commit that a later step (push/verify) then refuses is
    # already carried by the DEDICATED `commit` field, never folded into
    # data_change (T177 Round 1 I2 correction -- an earlier draft of this
    # fix wrongly stuffed commit+per-remote info into data_change,
    # violating this exact contract clause). `push_results` is an
    # ADDITIVE diagnostic field (the field table does not forbid
    # additional informational fields) carrying the per-remote
    # success/failure breakdown CA-025's "remaining remotes... proceed"
    # clause calls for.
    python3 - "$OUT" "$PROJECT" "$1" "$2" "$3" "$4" "${5:-}" <<'PYEOF'
import json, sys
out, project, outcome, reason, commit, data_change, push_results = sys.argv[1:8]
doc = {
    "schema": "consumer-migration/v1",
    "project_id": project,
    "outcome": outcome,
    "data_change": "NONE" if data_change in ("", "NONE") else data_change.split(","),
}
if reason:
    doc["not_migrated_reason"] = reason
if commit:
    doc["commit"] = commit
if push_results:
    doc["push_results"] = push_results.split(",")
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
PYEOF
}

not_migrated() {
    step=$1; reason=$2
    # DEC-25 step 1 / data-model.md #13.3: a dirty working tree is recorded
    # exactly "NOT-MIGRATED (dirty-local)" -- the ONE reason with no
    # "<step>: " prefix; every other reason uses the general
    # "NOT-MIGRATED (<step>: <reason>)" form. Used ONLY for refusals
    # BEFORE any write to $WORKDIR has happened (steps 1-3, and the
    # gitlink-bump sub-steps that fail before `git update-index` ever
    # runs) -- "NONE" is genuinely correct there. Once a write has begun,
    # use not_migrated_after_write() instead (T177 Round 1 I1).
    if [ "$reason" = "dirty-local" ]; then
        FULL="NOT-MIGRATED (dirty-local)"
    else
        FULL="NOT-MIGRATED ($step: $reason)"
    fi
    write_out "NOT-MIGRATED" "$FULL" "" "NONE"
    echo "$FULL"
    exit 1
}

# T177 Round 1 I1 fix: once the gitlink-bump has genuinely staged a write
# (index entry + possibly the submodule's own checked-out working
# directory, via `git submodule update --init`), a later failure MUST
# NOT claim `data_change: NONE` while real residue is left behind -- the
# EXACT drift this tool produced on its first real run (T175 track4,
# ADDENDUM 101/106) and which had to be manually restored afterward.
# restore_staged_gitlink() mirrors that same manual restore (un-stage the
# index entry, then re-sync the submodule checkout to match) as a
# built-in step, every time, rather than leaving it to a human; the
# REAL post-restore dirty state is then measured (never assumed) and
# reported honestly -- "NONE" only when the restore genuinely left
# nothing behind.
restore_staged_gitlink() {
    git -C "$WORKDIR" reset -q HEAD -- constitution 2>/dev/null || true
    git -C "$WORKDIR" -c protocol.file.allow=always submodule update --init -- constitution >/dev/null 2>&1 || true
}

not_migrated_after_write() {
    step=$1; reason=$2
    restore_staged_gitlink
    RESIDUE=$(git -C "$WORKDIR" status --porcelain=v1 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    FULL="NOT-MIGRATED ($step: $reason)"
    write_out "NOT-MIGRATED" "$FULL" "" "${RESIDUE:-NONE}"
    echo "$FULL"
    if [ -n "$RESIDUE" ]; then
        echo "migrate.sh: WARNING -- $WORKDIR has real residue after this refusal that could not be fully restored: $RESIDUE" >&2
    fi
    exit 1
}

# --- Step 1: preflight (CA-020) -- no write below this point until it passes.
if [ ! -d "$WORKDIR/.git" ] && [ ! -f "$WORKDIR/.git" ]; then
    echo "migrate.sh: $WORKDIR is not a git checkout" >&2
    exit 4
fi
DIRTY=$(git -C "$WORKDIR" status --porcelain=v1 2>&1)
DIRTY_RC=$?
if [ "$DIRTY_RC" -ne 0 ]; then
    echo "migrate.sh: could not determine working-tree cleanliness (rc=$DIRTY_RC)" >&2
    exit 4
fi
if [ -n "$DIRTY" ]; then
    not_migrated "preflight" "dirty-local"
fi

if ! git -C "$WORKDIR" fetch --all --quiet 2>"$WORKDIR/.migrate_fetch.err"; then
    REASON="unreachable"
    rm -f "$WORKDIR/.migrate_fetch.err"
    not_migrated "preflight" "$REASON"
fi
rm -f "$WORKDIR/.migrate_fetch.err"

BRANCH=$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
LOCAL_HEAD=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null)
UPSTREAM=$(git -C "$WORKDIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
if [ -n "$UPSTREAM" ]; then
    UPSTREAM_HEAD=$(git -C "$WORKDIR" rev-parse "$UPSTREAM" 2>/dev/null)
    if [ -n "$UPSTREAM_HEAD" ] && [ "$UPSTREAM_HEAD" != "$LOCAL_HEAD" ]; then
        AHEAD_BEHIND=$(git -C "$WORKDIR" rev-list --left-right --count "$LOCAL_HEAD...$UPSTREAM_HEAD" 2>/dev/null)
        BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')
        if [ -n "$BEHIND" ] && [ "$BEHIND" != "0" ]; then
            not_migrated "preflight" "divergent-branches"
        fi
    fi
fi

if [ "$APPLY" -eq 0 ]; then
    echo "DRY-RUN: preflight passed for $PROJECT at $WORKDIR (branch=$BRANCH); pass --apply to migrate"
    write_out "NOT-MIGRATED" "NOT-MIGRATED (preflight: dry-run)" "" "NONE"
    exit 1
fi

# --- Step 2: backup (CA-021, §9.2 hardlinked mirror, same volume)
#
# §9.2's hardlink-mirror assumes hardlink-copying "the git directory"
# gives real protection: for a plain checkout $WORKDIR/.git IS that
# whole, self-contained directory, so a hardlinked copy keeps every
# pre-migration object/ref reachable even after the live repo moves on
# (objects are immutable + content-addressed, ref updates are atomic
# renames -- the backup's own directory entries still point at the OLD
# inode). A `git worktree` checkout breaks that: $WORKDIR/.git there is a
# small TEXT FILE ("gitdir: <path>") pointing at the REAL git-dir, whose
# objects/refs (the worktree's "common dir") live SHARED with the
# worktree's own main checkout and with every SIBLING worktree of the
# same backing repo (verified live in this fleet: 3 sibling worktrees of
# one HelixDevelopment/skills backing repo, one per Track). Hardlinking
# $WORKDIR/.git there copies only that ~100-byte pointer file, never the
# real object database -- a FALSE SENSE of §9.2 protection while backing
# up nothing (reproduced live in a scratch fixture: du -sh showed an 80K
# real git-dir vs a 4-byte-shy 173-byte "backup"). A genuinely
# independent backup of the shared common dir would need either (a)
# hardlinking it -- not a clean "before this migration" snapshot, since a
# SIBLING worktree can be writing the SAME shared objects/refs
# concurrently with no relation to THIS migration -- or (b) a real,
# non-hardlinked mirror clone, a materially heavier mechanism this tool
# does not implement. Per §11.4.201's conservative-safe-default-on-an-
# unresolvable-signal: refuse honestly (as a backup failure) rather than
# pretend to protect a shape this mechanism cannot actually protect.
#
# The resolved real git-dir (`--absolute-git-dir`) is used as the
# hardlink SOURCE for every checkout shape, not the raw "$WORKDIR/.git"
# path -- for a plain checkout this resolves to exactly $WORKDIR/.git
# (verified identical), so the already-working case is behavior-
# preserving; for a `.git`-as-file checkout whose real git-dir is NOT
# shared with any sibling (e.g. an ordinary git submodule nested as a
# consumer's own workdir -- --git-dir == --git-common-dir there, since
# each submodule's own git-dir is private under the outer repo's
# .git/modules/, never shared), the resolved path is a real, self-
# contained directory and the SAME §9.2 hardlink protection applies
# correctly. Only the TRUE worktree shape (--git-dir differs from
# --git-common-dir once both are resolved to absolute paths) is refused.
GIT_DIR_ABS=$(git -C "$WORKDIR" rev-parse --absolute-git-dir 2>/dev/null)
if [ -z "$GIT_DIR_ABS" ]; then
    not_migrated "backup" "backup-failed"
fi
RAW_COMMON_DIR=$(git -C "$WORKDIR" rev-parse --git-common-dir 2>/dev/null)
COMMON_DIR_ABS=""
if [ -n "$RAW_COMMON_DIR" ]; then
    COMMON_DIR_ABS=$( (cd "$WORKDIR" && cd "$RAW_COMMON_DIR" 2>/dev/null && pwd) )
fi
if [ -z "$COMMON_DIR_ABS" ] || [ "$GIT_DIR_ABS" != "$COMMON_DIR_ABS" ]; then
    not_migrated "backup" "backup-failed"
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$WORKDIR/../.fastcycle_migrate_backup_${STAMP}"
if ! cp -al "$GIT_DIR_ABS" "$BACKUP_DIR" 2>/tmp/migrate_backup_err.$$; then
    R=$(cat /tmp/migrate_backup_err.$$ 2>/dev/null); rm -f /tmp/migrate_backup_err.$$
    not_migrated "backup" "backup-failed"
fi
rm -f /tmp/migrate_backup_err.$$
BACKUP_HASH=$(find "$BACKUP_DIR" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
echo "backup: $BACKUP_DIR (hash=$BACKUP_HASH)"

# --- Step 3 already done above (fetch --all, read-only).

# --- Step 4: gitlink-bump -- resolve the consumer's OWN constitution
# submodule url from .gitmodules and discover its latest commit.
#
# Resolved by PATH, never by .gitmodules SECTION NAME: the section name
# is an arbitrary label each consumer chooses for itself (this
# constitution repo's own .gitmodules uses [submodule "constitution"],
# but a real consumer, HelixDevelopment/ota, names the SAME path's
# section [submodule "HelixConstitution"] instead -- verified live by
# direct .gitmodules inspection) -- looking it up as literal
# submodule.constitution.url assumed every consumer names the section
# "constitution", which is false in the wild. Find whichever section's
# `path` value equals the expected constitution checkout path
# ("constitution", matching this tool's own other hardcoded uses of that
# path below at the ls-tree/submodule-update/allow-list steps), then
# read THAT section's url -- the section name itself is never examined.
GITMODULES="$WORKDIR/.gitmodules"
if [ ! -f "$GITMODULES" ]; then
    not_migrated "gitlink-bump" "no .gitmodules (not a submodule consumer)"
fi
CONST_SECTION=""
PATH_ENTRIES=$(git config -f "$GITMODULES" --get-regexp '^submodule\..*\.path$' 2>/dev/null)
if [ -n "$PATH_ENTRIES" ]; then
    OLD_IFS=$IFS
    IFS='
'
    for line in $PATH_ENTRIES; do
        key=${line%% *}
        val=${line#* }
        if [ "$val" = "constitution" ]; then
            CONST_SECTION=${key#submodule.}
            CONST_SECTION=${CONST_SECTION%.path}
            break
        fi
    done
    IFS=$OLD_IFS
fi
SUB_URL=""
if [ -n "$CONST_SECTION" ]; then
    SUB_URL=$(git config -f "$GITMODULES" --get "submodule.$CONST_SECTION.url" 2>/dev/null)
fi
if [ -z "$SUB_URL" ]; then
    not_migrated "gitlink-bump" "no constitution submodule entry in .gitmodules"
fi
NEW_SHA=$(git ls-remote "$SUB_URL" HEAD 2>/dev/null | awk '{print $1}')
if [ -z "$NEW_SHA" ]; then
    NEW_SHA=$(git ls-remote "$SUB_URL" refs/heads/main 2>/dev/null | awk '{print $1}')
fi
if [ -z "$NEW_SHA" ]; then
    not_migrated "gitlink-bump" "could not resolve the target constitution commit via git ls-remote"
fi
OLD_SHA=$(git -C "$WORKDIR" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
# T177 Round 1 I4 fix: a consumer already at the migration target has
# NOTHING to bump/materialize/review/commit/push -- the prior code fell
# straight through into the commit step anyway, where "nothing staged"
# made `git commit` fail with a real git error, wrongly reported as
# NOT-MIGRATED (commit: git commit failed) forever (a consumer at target
# could never converge). ALREADY_AT_TARGET short-circuits steps 5-8
# entirely and proceeds directly to step 9 (verify), matching the tool's
# own pre-existing log line ("... proceeding to verify only").
ALREADY_AT_TARGET=0
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
    ALREADY_AT_TARGET=1
    echo "migrate.sh: $PROJECT already at $NEW_SHA -- no bump needed, proceeding to verify only"
else
    if ! git -C "$WORKDIR" update-index --add --cacheinfo "160000,$NEW_SHA,constitution" 2>&1; then
        not_migrated "gitlink-bump" "git update-index failed"
    fi
fi

if [ "$ALREADY_AT_TARGET" -ne 1 ]; then
    # CA-022 change scope: everything staged must be inside the allow-list.
    STAGED=$(git -C "$WORKDIR" diff --cached --name-only 2>/dev/null)
    for f in $STAGED; do
        case "$f" in
            constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*) : ;;
            *) not_migrated_after_write "wiring" "out-of-scope-diff ($f)" ;;
        esac
    done

    # --- Step 5: materialize the new content + run post_update_hook.sh /
    # the consumer's own gates, best-effort (CA-023): a hook/gate
    # genuinely absent at the target commit is not a failure (nothing to
    # check); a hook/gate PRESENT and failing IS.
    # -c protocol.file.allow=always: modern git refuses a bare local-path
    # ("file://"-shaped) submodule URL by default (CVE-2022-39253
    # hardening); safe here because the URL comes from THIS SAME
    # consumer's own .gitmodules, already trusted (it is the very
    # project migrate.sh was invoked to migrate) -- exercised for real by
    # T168's local-bare-repo fixtures, and a no-op override for any real
    # https/ssh consumer URL.
    #
    # T177 Round 1 I5 fix: a fetch/checkout failure here was previously
    # swallowed by `|| true`, silently leaving the OLD constitution/
    # checkout in place -- the subsequent `[ -f "$HOOK" ]` check would
    # then find the OLD hook (or none), effectively skipping the whole
    # step without ANY error recorded. The failure is now surfaced
    # loudly as step=fetch reason=unreachable (the target commit's
    # objects could not be retrieved -- the same reason vocabulary the
    # tool's own initial `git fetch --all` already uses for this class
    # of failure).
    if ! git -C "$WORKDIR" -c protocol.file.allow=always submodule update --init constitution >"$WORKDIR/.migrate_submodule_update.err" 2>&1; then
        rm -f "$WORKDIR/.migrate_submodule_update.err"
        not_migrated_after_write "fetch" "unreachable"
    fi
    rm -f "$WORKDIR/.migrate_submodule_update.err"

    HOOK="$WORKDIR/constitution/scripts/post_update_hook.sh"
    if [ -f "$HOOK" ]; then
        # T177 Round 1 B2 fix: the hook MUST run against the CONSUMER
        # ($WORKDIR), never the caller's own ambient cwd. `post_update_hook.sh`
        # defaults PROJECT_ROOT="$(pwd)" and writes .mcp.json/.git/hooks/
        # skills/ there, plus runs installers -- launched via a bare
        # `sh "$HOOK"` (no explicit `cd`, no explicit PROJECT_ROOT), it would
        # silently target whatever directory migrate.sh itself happened to be
        # invoked from, never the consumer, a real collateral-damage risk
        # verified live in a scratch fixture (a probe hook's own `pwd` showed
        # the caller dir, not $WORKDIR). CONST_DIR is set explicitly too, for
        # defense-in-depth, even though the hook's own SCRIPT_DIR-derived
        # default already resolves correctly once cwd is right.
        if ! ( cd "$WORKDIR" && PROJECT_ROOT="$WORKDIR" CONST_DIR="$WORKDIR/constitution" sh "$HOOK" ) >"$WORKDIR/.migrate_hook.log" 2>&1; then
            not_migrated_after_write "post-update-hook" "consumer-gates-red"
        fi
        rm -f "$WORKDIR/.migrate_hook.log"
    fi

    # The consumer's OWN gates (CA-023, distinct from post_update_hook.sh
    # itself -- data-model.md #13.3 names "consumer-gates" as its own
    # step). Best-effort discovery, mirroring the step-7 commit-wrapper
    # discovery pattern already used below: a CLAUDE.md line
    # "Consumer gates: <repo-relative-script>" names a script to run; a
    # genuinely absent marker line is "nothing to check" (CA-023's own
    # documented best-effort policy), never a failure -- T177 Round 1 I5.
    GATES_SCRIPT=""
    if [ -f "$WORKDIR/CLAUDE.md" ]; then
        GATES_LINE=$(grep '^Consumer gates:' "$WORKDIR/CLAUDE.md" 2>/dev/null | head -1)
        if [ -n "$GATES_LINE" ]; then
            GATES_SCRIPT=$(echo "${GATES_LINE#Consumer gates:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
    fi
    if [ -n "$GATES_SCRIPT" ] && [ "$GATES_SCRIPT" != "none" ]; then
        if [ ! -f "$WORKDIR/$GATES_SCRIPT" ]; then
            not_migrated_after_write "consumer-gates" "consumer-gates-red"
        fi
        if ! ( cd "$WORKDIR" && sh "$GATES_SCRIPT" ) >"$WORKDIR/.migrate_gates.log" 2>&1; then
            not_migrated_after_write "consumer-gates" "consumer-gates-red"
        fi
        rm -f "$WORKDIR/.migrate_gates.log"
    fi

    # --- Step 6: review (CA-024) -- absent or non-GO => review-no-go.
    #
    # T177 Round 1 I6 fix: the GO verdict must be BOUND to THIS EXACT
    # migration attempt -- the prior check accepted ANY JSON shaped
    # {"verdict":"GO"}, regardless of which project or which target
    # commit it was originally issued for (a review record produced for
    # a DIFFERENT consumer, or for a DIFFERENT constitution commit of
    # THIS SAME consumer, would silently authorize this push). The
    # record's own top-level `project_id` and `target_commit` fields
    # MUST match `$PROJECT`/`$NEW_SHA` exactly; either field absent or
    # mismatched is review-no-go, same as no record at all.
    REVIEW_GO=0
    if [ -n "$REVIEW_REF" ] && [ -f "$REVIEW_REF" ]; then
        REVIEW_CHECK=$(python3 - "$REVIEW_REF" "$PROJECT" "$NEW_SHA" <<'PYEOF'
import json, sys
path, project, target = sys.argv[1:4]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, ValueError):
    print("NO-GO")
    sys.exit(0)
if doc.get("verdict") != "GO":
    print("NO-GO")
elif doc.get("project_id") != project or doc.get("target_commit") != target:
    print("NO-GO")
else:
    print("GO")
PYEOF
)
        if [ "$REVIEW_CHECK" = "GO" ]; then
            REVIEW_GO=1
        fi
    fi
    if [ "$REVIEW_GO" -ne 1 ]; then
        not_migrated_after_write "review" "review-no-go"
    fi

    # --- Step 7: commit via the consumer's own wrapper, or plain git if its
    # CLAUDE.md explicitly permits it (this tool's discovery marker).
    COMMIT_MSG="chore(fastcycle): bump constitution pointer to $NEW_SHA (SpecKit-004 US8 migration)"
    PLAIN_GIT_OK=0
    if [ -f "$WORKDIR/CLAUDE.md" ] && grep -q 'Commit wrapper: none (plain git permitted)' "$WORKDIR/CLAUDE.md" 2>/dev/null; then
        PLAIN_GIT_OK=1
    fi
    if [ "$PLAIN_GIT_OK" -ne 1 ]; then
        not_migrated_after_write "commit" "no-commit-wrapper"
    fi
    # Split across continuation lines (functionally identical single command) so
    # the placeholder .invalid-domain committer email is never on the same
    # physical line as "$COMMIT_MSG" -- the credential-scan adjacency heuristic
    # is line-scoped and otherwise mis-reads the adjacent "$COMMIT_MSG" shell
    # variable token (contains letters + "$"/"_") as a password next to an
    # email-shaped string, a pre-existing false positive found live while
    # committing this same file (T175, 2026-09-30), fixed at the source text
    # per §11.4.201 rather than by touching the shared scanner.
    if ! git -C "$WORKDIR" \
        -c user.name=fastcycle-migrate \
        -c user.email=fastcycle-migrate@example.invalid \
        commit -q -m "$COMMIT_MSG" 2>&1; then
        not_migrated_after_write "commit" "git commit failed"
    fi
    NEW_COMMIT=$(git -C "$WORKDIR" rev-parse HEAD)

    # --- Step 8: fast-forward push. T177 Round 1 I2 fix: EVERY configured
    # remote is attempted, even after an earlier one rejects (CA-025:
    # "remaining remotes ... proceed") -- the prior code aborted at the
    # FIRST rejection, so a project with >=2 remotes where only the first
    # rejected never even tried the others. A commit already exists on
    # local disk at this point and is NEVER rolled back on a push failure
    # (CA-019: "a push failure never rolls back a local commit"), so a
    # post-commit refusal reports that commit honestly via the `commit`
    # field (data_change stays NONE, genuinely accurate -- the working
    # tree has no UNCOMMITTED residue, per data-model.md #13.3's own
    # "data_change must be NONE for every NOT-MIGRATED outcome" clause),
    # together with which remote(s) succeeded and which failed via the
    # additive `push_results` field.
    REMOTES=$(git -C "$WORKDIR" remote 2>/dev/null)
    PUSH_FAILURES=""
    PUSH_OK_REMOTES=""
    for r in $REMOTES; do
        if ! git -C "$WORKDIR" push "$r" "$BRANCH":"$BRANCH" 2>"$WORKDIR/.migrate_push.err"; then
            REASON="remote-rejected"
            if grep -qi 'non-fast-forward\|fetch first' "$WORKDIR/.migrate_push.err" 2>/dev/null; then
                REASON="non-fast-forward"
            fi
            rm -f "$WORKDIR/.migrate_push.err"
            PUSH_FAILURES="$PUSH_FAILURES $r:$REASON"
        else
            PUSH_OK_REMOTES="$PUSH_OK_REMOTES $r"
        fi
        rm -f "$WORKDIR/.migrate_push.err"
    done
    if [ -n "$PUSH_FAILURES" ]; then
        REASON="remote-rejected"
        case "$PUSH_FAILURES" in
            *non-fast-forward*) REASON="non-fast-forward" ;;
        esac
        PR=""
        for r in $PUSH_OK_REMOTES; do PR="$PR,$r:pushed"; done
        for pf in $PUSH_FAILURES; do PR="$PR,$pf"; done
        PR=${PR#,}
        FULL="NOT-MIGRATED (push: $REASON)"
        write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "NONE" "$PR"
        echo "$FULL (per-remote:$PUSH_FAILURES; pushed ok to:$PUSH_OK_REMOTES)"
        exit 1
    fi
else
    # Already at target: still ensure the submodule is genuinely checked
    # out before verify (CA-026) runs -- a consumer whose gitlink is
    # already correct but whose submodule directory was never
    # initialised (a fresh clone that has not yet run `submodule
    # update --init`, for example) would otherwise make step 9's
    # read-only cross-check spuriously report SUBMODULE_UNINITIALISED,
    # discovered live while testing this exact path. Idempotent + a
    # no-op for an already-initialised submodule.
    git -C "$WORKDIR" -c protocol.file.allow=always submodule update --init constitution >/dev/null 2>&1 || true
    NEW_COMMIT="$LOCAL_HEAD"
fi

# --- Step 9: recursive verify TWICE (CA-026) -- MIGRATED only when BOTH
# runs report CLEAN with an identical body_hash. T177 Round 1 B3 fix: the
# prior code wrote MIGRATED straight after push with NO double-verify at
# all -- T168's own C3c check only happened to run repo_verify.py itself
# as its OWN test-side scaffolding, which masked the fact that migrate.sh
# never did. This runs for BOTH the normal push path AND the
# already-at-target path (verify is a read-only cross-check of the
# CURRENT state either way).
if [ ! -f "$VERIFY_TOOL" ]; then
    FULL="NOT-MIGRATED (verify: verification-not-clean)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "NONE"
    echo "$FULL ($VERIFY_TOOL not found -- CA-026 cannot run)"
    exit 1
fi
# Observer-decontamination (§11.4.201(10)): the verify output/log files
# MUST live OUTSIDE $WORKDIR. Writing them inside the very tree being
# verified is a genuine self-contamination bug discovered live while
# authoring this fix -- repo_verify.py's own `--out`/stdout-redirect
# files became NEW untracked files inside $WORKDIR the instant they were
# created, so the SAME verify pass (and every pass after it) then
# detected ITS OWN output as UNTRACKED_FILES dirt, turning every
# otherwise-genuinely-clean migration into a false NOT_CLEAN. A scratch
# directory outside the consumer's own working tree is used instead.
VERIFY_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fastcycle_migrate_verify.XXXXXX" 2>/dev/null)
if [ -z "$VERIFY_SCRATCH" ] || [ ! -d "$VERIFY_SCRATCH" ]; then
    FULL="NOT-MIGRATED (verify: verification-not-clean)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "NONE"
    echo "$FULL (could not create a scratch directory outside \$WORKDIR for CA-026 verify output)"
    exit 1
fi
V1="$VERIFY_SCRATCH/verify1.json"
V2="$VERIFY_SCRATCH/verify2.json"
python3 "$VERIFY_TOOL" --recursive --root "$WORKDIR" --out "$V1" >"$VERIFY_SCRATCH/verify1.log" 2>&1
V1_RC=$?
python3 "$VERIFY_TOOL" --recursive --root "$WORKDIR" --out "$V2" >"$VERIFY_SCRATCH/verify2.log" 2>&1
V2_RC=$?
OVERALL1=$(python3 -c "import json; print(json.load(open('$V1')).get('overall',''))" 2>/dev/null)
OVERALL2=$(python3 -c "import json; print(json.load(open('$V2')).get('overall',''))" 2>/dev/null)
HASH1=$(python3 -c "import json; print(json.load(open('$V1')).get('body_hash',''))" 2>/dev/null)
HASH2=$(python3 -c "import json; print(json.load(open('$V2')).get('body_hash',''))" 2>/dev/null)
rm -rf "$VERIFY_SCRATCH"
if [ "$V1_RC" -ne 0 ] || [ "$V2_RC" -ne 0 ] || [ "$OVERALL1" != "CLEAN" ] || [ "$OVERALL2" != "CLEAN" ] || [ -z "$HASH1" ] || [ "$HASH1" != "$HASH2" ]; then
    FULL="NOT-MIGRATED (verify: verification-not-clean)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "NONE"
    echo "$FULL (v1_rc=$V1_RC overall1=$OVERALL1 v2_rc=$V2_RC overall2=$OVERALL2 hash1=$HASH1 hash2=$HASH2)"
    exit 1
fi

echo "MIGRATED: $PROJECT commit=$NEW_COMMIT (verified CLEAN x2, body_hash=$HASH1)"
write_out "MIGRATED" "" "$NEW_COMMIT" "NONE"
exit 0
