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
# "GO"}. Absent or non-GO => NOT-MIGRATED (review: review-no-go). Real
# migrations pass the review/review_record.py-produced ReviewVerdictRecord
# here; T168's fixture test passes a clearly-labelled test-fixture-only
# verdict file, never a claim of a real Opus-xhigh review having run.
#
# Steps (DEC-25): 1 preflight (CA-020) 2 backup (CA-021, §9.2) 3 fetch
# 4 gitlink-bump (resolved from the consumer's own .gitmodules constitution
# url via `git ls-remote`) 5 post_update_hook.sh + consumer gates (best-
# effort: run only what is genuinely discoverable, per CA-023) 6 review
# (CA-024) 7 commit via the consumer's own wrapper, or plain git when its
# CLAUDE.md's own governance explicitly permits it (this tool's own
# documented discovery marker: a line matching "Commit wrapper: none
# (plain git permitted)" in the consumer's CLAUDE.md) 8 fast-forward push
# to every configured remote (CA-025) 9 recursive verify twice (CA-026).
# Any step's failure -> NOT-MIGRATED (<step>: <reason>), no data change
# beyond what already legitimately landed at an EARLIER, already-committed
# step (a push failure never rolls back a local commit; a preflight/
# gitlink/gates/review failure never writes anything at all).
#
# Exit: 0 MIGRATED; 1 NOT-MIGRATED (reason in the JSON body, not a crash);
#       2 usage; 4 BLIND (could not determine dirty/reachable state at all).
set -u

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
    python3 - "$OUT" "$PROJECT" "$1" "$2" "$3" "$4" <<'PYEOF'
import json, sys
out, project, outcome, reason, commit, data_change = sys.argv[1:7]
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
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
PYEOF
}

not_migrated() {
    step=$1; reason=$2
    # DEC-25 step 1 / data-model.md #13.3: a dirty working tree is recorded
    # exactly "NOT-MIGRATED (dirty-local)" -- the ONE reason with no
    # "<step>: " prefix; every other reason uses the general
    # "NOT-MIGRATED (<step>: <reason>)" form.
    if [ "$reason" = "dirty-local" ]; then
        FULL="NOT-MIGRATED (dirty-local)"
    else
        FULL="NOT-MIGRATED ($step: $reason)"
    fi
    write_out "NOT-MIGRATED" "$FULL" "" "NONE"
    echo "$FULL"
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
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$WORKDIR/../.fastcycle_migrate_backup_${STAMP}"
if ! cp -al "$WORKDIR/.git" "$BACKUP_DIR" 2>/tmp/migrate_backup_err.$$; then
    R=$(cat /tmp/migrate_backup_err.$$ 2>/dev/null); rm -f /tmp/migrate_backup_err.$$
    not_migrated "backup" "backup-failed"
fi
rm -f /tmp/migrate_backup_err.$$
BACKUP_HASH=$(find "$BACKUP_DIR" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
echo "backup: $BACKUP_DIR (hash=$BACKUP_HASH)"

# --- Step 3 already done above (fetch --all, read-only).

# --- Step 4: gitlink-bump -- resolve the consumer's OWN constitution
# submodule url from .gitmodules and discover its latest commit.
GITMODULES="$WORKDIR/.gitmodules"
if [ ! -f "$GITMODULES" ]; then
    not_migrated "gitlink-bump" "no .gitmodules (not a submodule consumer)"
fi
SUB_URL=$(git config -f "$GITMODULES" --get submodule.constitution.url 2>/dev/null)
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
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
    echo "migrate.sh: $PROJECT already at $NEW_SHA -- no bump needed, proceeding to verify only"
else
    if ! git -C "$WORKDIR" update-index --add --cacheinfo "160000,$NEW_SHA,constitution" 2>&1; then
        not_migrated "gitlink-bump" "git update-index failed"
    fi
fi

# CA-022 change scope: everything staged must be inside the allow-list.
STAGED=$(git -C "$WORKDIR" diff --cached --name-only 2>/dev/null)
for f in $STAGED; do
    case "$f" in
        constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*) : ;;
        *) not_migrated "wiring" "out-of-scope-diff ($f)" ;;
    esac
done

# --- Step 5: materialize the new content + run post_update_hook.sh /
# consumer gates, best-effort (CA-023): a hook/gate genuinely absent at
# the target commit is not a failure (nothing to check); a hook/gate
# PRESENT and failing IS.
# -c protocol.file.allow=always: modern git refuses a bare local-path
# ("file://"-shaped) submodule URL by default (CVE-2022-39253 hardening);
# safe here because the URL comes from THIS SAME consumer's own
# .gitmodules, already trusted (it is the very project migrate.sh was
# invoked to migrate) -- exercised for real by T168's local-bare-repo
# fixtures, and a no-op override for any real https/ssh consumer URL.
git -C "$WORKDIR" -c protocol.file.allow=always submodule update --init constitution >/dev/null 2>&1 || true
HOOK="$WORKDIR/constitution/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    if ! sh "$HOOK" >"$WORKDIR/.migrate_hook.log" 2>&1; then
        not_migrated "post-update-hook" "post_update_hook.sh failed (see .migrate_hook.log)"
    fi
    rm -f "$WORKDIR/.migrate_hook.log"
fi

# --- Step 6: review (CA-024) -- absent or non-GO => review-no-go.
REVIEW_GO=0
if [ -n "$REVIEW_REF" ] && [ -f "$REVIEW_REF" ]; then
    VERDICT=$(python3 -c "import json; print(json.load(open('$REVIEW_REF')).get('verdict',''))" 2>/dev/null)
    if [ "$VERDICT" = "GO" ]; then
        REVIEW_GO=1
    fi
fi
if [ "$REVIEW_GO" -ne 1 ]; then
    git -C "$WORKDIR" reset -q HEAD -- constitution 2>/dev/null || true
    not_migrated "review" "review-no-go"
fi

# --- Step 7: commit via the consumer's own wrapper, or plain git if its
# CLAUDE.md explicitly permits it (this tool's discovery marker).
COMMIT_MSG="chore(fastcycle): bump constitution pointer to $NEW_SHA (SpecKit-004 US8 migration)"
PLAIN_GIT_OK=0
if [ -f "$WORKDIR/CLAUDE.md" ] && grep -q 'Commit wrapper: none (plain git permitted)' "$WORKDIR/CLAUDE.md" 2>/dev/null; then
    PLAIN_GIT_OK=1
fi
if [ "$PLAIN_GIT_OK" -ne 1 ]; then
    git -C "$WORKDIR" reset -q HEAD -- constitution 2>/dev/null || true
    not_migrated "commit" "no-commit-wrapper"
fi
if ! git -C "$WORKDIR" -c user.name=fastcycle-migrate -c user.email=fastcycle-migrate@example.invalid commit -q -m "$COMMIT_MSG" 2>&1; then
    not_migrated "commit" "git commit failed"
fi
NEW_COMMIT=$(git -C "$WORKDIR" rev-parse HEAD)

# --- Step 8: fast-forward push to every configured remote.
REMOTES=$(git -C "$WORKDIR" remote 2>/dev/null)
for r in $REMOTES; do
    if ! git -C "$WORKDIR" push "$r" "$BRANCH":"$BRANCH" 2>"$WORKDIR/.migrate_push.err"; then
        REASON="remote-rejected"
        if grep -qi 'non-fast-forward\|fetch first' "$WORKDIR/.migrate_push.err" 2>/dev/null; then
            REASON="non-fast-forward"
        fi
        rm -f "$WORKDIR/.migrate_push.err"
        not_migrated "push" "$REASON"
    fi
    rm -f "$WORKDIR/.migrate_push.err"
done

echo "MIGRATED: $PROJECT commit=$NEW_COMMIT"
write_out "MIGRATED" "" "$NEW_COMMIT" "NONE"
exit 0
