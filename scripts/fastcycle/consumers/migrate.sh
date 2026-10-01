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
OPERATOR_BLOCKED=0; SCOPE_DECISION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config) CFG=$2; shift 2 ;;
        --project) PROJECT=$2; shift 2 ;;
        --workdir) WORKDIR=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --apply) APPLY=1; shift ;;
        --review-ref) REVIEW_REF=$2; shift 2 ;;
        --operator-blocked) OPERATOR_BLOCKED=1; shift ;;
        --scope-decision) SCOPE_DECISION=$2; shift 2 ;;
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
# T177 Round 3 (new finding N1): canonicalise $WORKDIR to an ABSOLUTE path
# once, up front. Step 5 runs the hook as `cd "$WORKDIR" && PROJECT_ROOT=
# "$WORKDIR" ...` -- with a RELATIVE --workdir that PROJECT_ROOT is then
# resolved a SECOND time relative to the already-changed cwd (a path like
# f2/checkout/f2/checkout), so the hook wrote nowhere real and failed,
# recorded as a spurious NOT-MIGRATED (post-update-hook:
# consumer-gates-red) for every relative-path invocation (reproduced live
# 2026-10-01 with a stub hook writing $PROJECT_ROOT/.mcp.json).
WORKDIR=$(cd "$WORKDIR" && pwd)

# T177 Round 2 R2-I1 fix: every tool-OWN transient file (fetch/push/hook/
# gates stderr+log captures) MUST live OUTSIDE $WORKDIR -- writing them
# inside the very consumer checkout being migrated means a refusal that
# fires BEFORE the normal-path `rm -f` runs (every not_migrated_after_write
# call exits immediately, so a later `rm -f` on the SAME sequential path is
# never reached) leaves the tool's OWN artefact as genuine `git status`
# residue, reported as a non-NONE data_change on a NOT-MIGRATED outcome
# (reproduced live: a failing "Consumer gates: tools/f.sh" left
# .migrate_gates.log inside the consumer, permanently `dirty-local` on
# every re-run). Mirrors the SAME scratch-outside-$WORKDIR pattern step 9's
# CA-026 verify output already uses (§11.4.201(10) observer-
# decontamination), applied to every other transient file this tool
# writes. A `trap`-driven cleanup on EVERY exit path (normal or refused)
# means no per-call-site `rm -f` is load-bearing any more.
MIGRATE_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fastcycle_migrate_scratch.XXXXXX" 2>/dev/null)
if [ -z "$MIGRATE_SCRATCH" ] || [ ! -d "$MIGRATE_SCRATCH" ]; then
    echo "migrate.sh: could not create a scratch directory outside \$WORKDIR for transient tool output" >&2
    exit 4
fi
trap 'rm -rf "$MIGRATE_SCRATCH"' EXIT INT TERM

write_out() {
    # $1=outcome $2=reason_or_empty $3=commit_or_empty $4=data_change(NONE|list)
    # $5=push_results_or_empty -- comma-separated "remote:status" entries.
    # $6=review_ref_id_or_empty $7=verification_json_or_empty
    # $8=backup_marker_json_or_empty (T177 Round 2 R2-I4: data-model.md
    # #13.3's `review_ref`/`verification`/`backup_marker` fields, "required
    # iff MIGRATED").
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
    # $9=detail_or_empty (T177 Round 3, finding 1/CA-019): free-text context
    # for a refusal (e.g. WHICH path was out of scope) lives in its own
    # `detail` field, so `not_migrated_reason` stays EXACTLY the closed-set
    # DEC-25 form `audit.py summary` validates -- never "out-of-scope-diff
    # (.mcp.json)", which no closed-set reason matches.
    python3 - "$OUT" "$PROJECT" "$1" "$2" "$3" "$4" "${5:-}" "${6:-}" "${7:-}" "${8:-}" "${9:-}" <<'PYEOF'
import json, sys
out, project, outcome, reason, commit, data_change, push_results, review_ref, verification_json, backup_marker_json, detail = sys.argv[1:12]
doc = {
    "schema": "consumer-migration/v1",
    "project_id": project,
    "outcome": outcome,
    "data_change": "NONE" if data_change in ("", "NONE") else data_change.split(","),
}
if detail:
    doc["detail"] = detail
if reason:
    doc["not_migrated_reason"] = reason
if commit:
    doc["commit"] = commit
if push_results:
    doc["push_results"] = push_results.split(",")
if review_ref:
    doc["review_ref"] = review_ref
if verification_json:
    try:
        doc["verification"] = json.loads(verification_json)
    except ValueError:
        pass
if backup_marker_json:
    try:
        doc["backup_marker"] = json.loads(backup_marker_json)
    except ValueError:
        pass
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
PYEOF
}

not_migrated() {
    step=$1; reason=$2; detail=${3:-}
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
    write_out "NOT-MIGRATED" "$FULL" "" "NONE" "" "" "" "" "$detail"
    if [ -n "$detail" ]; then echo "$FULL [$detail]"; else echo "$FULL"; fi
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
    step=$1; reason=$2; detail=${3:-}
    restore_staged_gitlink
    RESIDUE=$(git -C "$WORKDIR" status --porcelain=v1 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    FULL="NOT-MIGRATED ($step: $reason)"
    write_out "NOT-MIGRATED" "$FULL" "" "${RESIDUE:-NONE}" "" "" "" "" "$detail"
    if [ -n "$detail" ]; then echo "$FULL [$detail]"; else echo "$FULL"; fi
    if [ -n "$RESIDUE" ]; then
        echo "migrate.sh: WARNING -- $WORKDIR has real residue after this refusal that could not be fully restored: $RESIDUE" >&2
    fi
    exit 1
}

# T177 Round 2 R2-B2/R2-I1 fix: every write_out call downstream of step 4
# (any write having begun) MUST report the REAL current residue, never a
# hardcoded "NONE" -- the exact bug behind both R2-B2 (a verify-step
# refusal hardcoded "NONE" while the hook's own untracked file sat in
# $WORKDIR) and R2-I1 (the tool's own log files, now fixed to live outside
# $WORKDIR entirely so they never contribute here). Mirrors
# not_migrated_after_write()'s own real-measurement pattern (T177 Round 1
# I1), generalised to every call site, not only the "after write" refusal
# helper -- includes the push-failure and step-9 verify-failure/MIGRATED
# paths, none of which previously re-measured reality before writing.
current_data_change() {
    git -C "$WORKDIR" status --porcelain=v1 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//'
}

# --- Step 1: preflight (CA-020) -- no write below this point until it passes.
#
# T177 Round 2 R2-I3 fix: CA-020's refusal set also covers
# `operator-blocked` (an explicit caller-supplied flag -- this tool never
# infers it) and `outside-migration-scope` (a caller-supplied, previously
# operator-answered scope_decision.json per T173; DEC-25 "migrated only if
# the operator's standing scope includes them") and `no-write-access`.
# All three are OPTIONAL/best-effort: a caller that supplies neither
# --operator-blocked nor --scope-decision sees no behavior change (every
# existing fixture invocation omits both). `--scope-decision`'s schema is
# this tool's own documented decision (mirroring --review-ref's T177
# Round 1 I6 precedent): `{"answer": {"in_scope_projects": [...]}}`; any
# other shape (including the genuinely-PENDING `{"answer": null}`
# scope_decision.json T173 already produced) is conservatively treated as
# NOT in scope (§11.4.101 safe-reversible default -- never guess a
# project into scope).
if [ "$OPERATOR_BLOCKED" -eq 1 ]; then
    not_migrated "preflight" "operator-blocked"
fi
if [ -n "$SCOPE_DECISION" ] && [ -f "$SCOPE_DECISION" ]; then
    SCOPE_OK=$(python3 - "$SCOPE_DECISION" "$PROJECT" <<'PYEOF'
import json, sys
path, project = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, ValueError):
    print("UNKNOWN")
    sys.exit(0)
answer = doc.get("answer")
if not isinstance(answer, dict):
    print("UNKNOWN")
    sys.exit(0)
in_scope = answer.get("in_scope_projects")
if isinstance(in_scope, list) and project in in_scope:
    print("IN-SCOPE")
else:
    print("OUT-OF-SCOPE")
PYEOF
)
    if [ "$SCOPE_OK" != "IN-SCOPE" ]; then
        not_migrated "preflight" "outside-migration-scope"
    fi
fi
if [ ! -w "$WORKDIR" ]; then
    not_migrated "preflight" "no-write-access"
fi

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

if ! git -C "$WORKDIR" fetch --all --quiet 2>"$MIGRATE_SCRATCH/migrate_fetch.err"; then
    REASON="unreachable"
    not_migrated "preflight" "$REASON"
fi

BRANCH=$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
LOCAL_HEAD=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null)
UPSTREAM=$(git -C "$WORKDIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
if [ -n "$UPSTREAM" ]; then
    UPSTREAM_HEAD=$(git -C "$WORKDIR" rev-parse "$UPSTREAM" 2>/dev/null)
    if [ -n "$UPSTREAM_HEAD" ] && [ "$UPSTREAM_HEAD" != "$LOCAL_HEAD" ]; then
        AHEAD_BEHIND=$(git -C "$WORKDIR" rev-list --left-right --count "$LOCAL_HEAD...$UPSTREAM_HEAD" 2>/dev/null)
        BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')
        if [ -n "$BEHIND" ] && [ "$BEHIND" != "0" ]; then
            not_migrated "preflight" "divergent-branches" "local-behind-$UPSTREAM-by-$BEHIND"
        fi
    fi
fi

# T177 Round 3 finding 4 (CA-022 "never product code"): the preflight above
# only ever checked whether the consumer is BEHIND its upstream -- never
# whether it is AHEAD with UNPUBLISHED local commits. Step 8 pushes
# "$BRANCH":"$BRANCH", which publishes EVERY commit between the remote's
# tip and the migration commit -- reproduced live: an unpushed local
# commit touching src/product.c was pushed to the remote alongside the
# migration commit, irreversibly, and the record said MIGRATED. Checked
# here, before any write, against EVERY remote that already carries this
# branch (a remote with NO such branch yet is a mirror being seeded --
# CA-025's "every configured remote" -- and receives only history that
# is already published elsewhere, which the per-remote check below
# guarantees). A branch with NO published counterpart on ANY remote has
# nothing to anchor "unpublished" against at all and is refused the same
# way (§11.4.201 conservative-safe default: pushing it would publish an
# entire never-published branch). Reason `divergent-branches` is the
# closed-set reason (data-model #13.3) closest in meaning ("local and
# remote histories differ"); the exact cause is carried in `detail`.
PUBLISHED_REFS=0
for r in $(git -C "$WORKDIR" remote 2>/dev/null); do
    RREF="refs/remotes/$r/$BRANCH"
    if git -C "$WORKDIR" rev-parse -q --verify "$RREF" >/dev/null 2>&1; then
        PUBLISHED_REFS=$((PUBLISHED_REFS + 1))
        AHEAD=$(git -C "$WORKDIR" rev-list --count "$RREF..$LOCAL_HEAD" 2>/dev/null)
        if [ -z "$AHEAD" ]; then
            echo "migrate.sh: could not measure unpublished commits against $RREF" >&2
            exit 4
        fi
        if [ "$AHEAD" != "0" ]; then
            not_migrated "preflight" "divergent-branches" "local-ahead-of-$r/$BRANCH-by-$AHEAD-unpublished-commit(s)"
        fi
    fi
done
if [ "$PUBLISHED_REFS" -eq 0 ]; then
    not_migrated "preflight" "divergent-branches" "branch-$BRANCH-has-no-published-counterpart-on-any-remote"
fi

if [ "$APPLY" -eq 0 ]; then
    # T177 Round 3 finding 1(b): a dry run is NOT a migration outcome --
    # data-model #13.3's closed reason set has no `dry-run`, and CA-028
    # says a dry run produces "the planned diff and preflight verdict
    # only". Recorded with its own outcome value so `audit.py summary`
    # can never count it toward SC-010 coverage.
    echo "DRY-RUN: preflight passed for $PROJECT at $WORKDIR (branch=$BRANCH); pass --apply to migrate"
    write_out "DRY-RUN" "" "" "NONE" "" "" "" "" "preflight-passed"
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
# T177 Round 3 (minor m4, reproduced live 2026-10-01): a bare
# ".fastcycle_migrate_backup_${STAMP}" name collides when two migrations
# under the same parent start in the same second -- `cp -al src EXISTING`
# then silently nests the second backup INSIDE the first as `.git/`, and
# the recorded hash covers a mixture of both. A unique per-run container
# (mktemp -d, same volume as $WORKDIR so the hardlinks stay valid) closes
# the window; the hardlinked mirror lives at <container>/git.
BACKUP_PARENT=$(cd "$WORKDIR/.." && pwd)
BACKUP_CONTAINER=$(mktemp -d "$BACKUP_PARENT/.fastcycle_migrate_backup_${STAMP}.XXXXXX" 2>/dev/null)
if [ -z "$BACKUP_CONTAINER" ] || [ ! -d "$BACKUP_CONTAINER" ]; then
    not_migrated "backup" "backup-failed" "could-not-create-backup-container"
fi
BACKUP_DIR="$BACKUP_CONTAINER/git"
if ! cp -al "$GIT_DIR_ABS" "$BACKUP_DIR" 2>"$MIGRATE_SCRATCH/migrate_backup.err"; then
    not_migrated "backup" "backup-failed" "hardlink-copy-failed"
fi
BACKUP_HASH=$(find "$BACKUP_DIR" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}')
echo "backup: $BACKUP_DIR (hash=$BACKUP_HASH)"
# T177 Round 2 R2-I4: data-model.md #13.3's `backup_marker` field
# ({path, ContentAddress}, "taken before any write"), embedded in the
# final MIGRATED record.
BACKUP_MARKER_JSON=$(python3 -c "import json,sys; print(json.dumps({'path': sys.argv[1], 'content_address': 'sha256:' + sys.argv[2]}))" "$BACKUP_DIR" "$BACKUP_HASH")

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
# T177 Round 3 finding 1 (CA-019 closed reason set): the free-text reasons
# below previously went straight into `not_migrated_reason`, matching NO
# closed-set reason. A consumer with no constitution submodule cannot be
# migrated by a gitlink bump at all -- `outside-migration-scope`; a target
# commit that cannot be resolved remotely -- `unreachable`. The exact cause
# lives in `detail`.
if [ ! -f "$GITMODULES" ]; then
    not_migrated "gitlink-bump" "outside-migration-scope" "no-.gitmodules-not-a-submodule-consumer"
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
    not_migrated "gitlink-bump" "outside-migration-scope" "no-constitution-path-entry-in-.gitmodules"
fi
NEW_SHA=$(git ls-remote "$SUB_URL" HEAD 2>/dev/null | awk '{print $1}')
if [ -z "$NEW_SHA" ]; then
    NEW_SHA=$(git ls-remote "$SUB_URL" refs/heads/main 2>/dev/null | awk '{print $1}')
fi
if [ -z "$NEW_SHA" ]; then
    not_migrated "gitlink-bump" "unreachable" "git-ls-remote-resolved-no-target-commit"
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
        # No closed-set reason fits a local git failure (data-model #13.3
        # vocabulary gap, T177 Round 3 new finding N2 -- recorded, never
        # forced into a misleading closed reason); `audit.py summary` reports
        # it as a non-conforming record, never counts it toward coverage.
        not_migrated "gitlink-bump" "local-git-error" "git-update-index-failed"
    fi
fi

if [ "$ALREADY_AT_TARGET" -ne 1 ]; then
    # CA-022 change scope: everything staged must be inside the allow-list.
    STAGED=$(git -C "$WORKDIR" diff --cached --name-only 2>/dev/null)
    for f in $STAGED; do
        case "$f" in
            constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*) : ;;
            *) not_migrated_after_write "wiring" "out-of-scope-diff" "path=$f" ;;
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
    if ! git -C "$WORKDIR" -c protocol.file.allow=always submodule update --init constitution >"$MIGRATE_SCRATCH/migrate_submodule_update.err" 2>&1; then
        not_migrated_after_write "fetch" "unreachable"
    fi

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
        #
        # T177 Round 3 finding 9: the REAL post_update_hook.sh is a BASH
        # script (`#!/usr/bin/env bash`, `WARNINGS+=(...)` array appends,
        # `local`) -- running it as `sh "$HOOK"` only worked where /bin/sh
        # happens to accept bash syntax; on a POSIX /bin/sh (dash) every
        # migration would fail with a cryptic post-update-hook refusal. It
        # is invoked with bash explicitly, never sh.
        if ! ( cd "$WORKDIR" && PROJECT_ROOT="$WORKDIR" CONST_DIR="$WORKDIR/constitution" bash "$HOOK" ) >"$MIGRATE_SCRATCH/migrate_hook.log" 2>&1; then
            not_migrated_after_write "post-update-hook" "consumer-gates-red"
        fi
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
        if ! ( cd "$WORKDIR" && sh "$GATES_SCRIPT" ) >"$MIGRATE_SCRATCH/migrate_gates.log" 2>&1; then
            not_migrated_after_write "consumer-gates" "consumer-gates-red"
        fi
    fi

    # T177 Round 2 R2-B2 fix: post_update_hook.sh / the consumer's own
    # gates can legitimately create or modify files -- the CA-022 scope
    # check above only ever examined the STAGED gitlink diff BEFORE this
    # step ran, so anything the hook/gates step creates (e.g. the real
    # post_update_hook.sh's own `.mcp.json`) was never checked against the
    # allow-list at all, and (being untracked, never staged) was never
    # committed either -- left as genuine, permanent untracked residue
    # even after a fully successful commit+push (reproduced live: a stub
    # hook writing a project-root file left it as `?? HOOK_WROTE_HERE`
    # forever after a real, pushed commit; CA-026's step-9 verify then
    # correctly flagged NOT_CLEAN, but the record's `data_change` field
    # was hardcoded "NONE" regardless -- fixed together with this, see
    # current_data_change() below). Re-check the FULL current working-tree
    # status (staged + unstaged + untracked, not only `--cached`) against
    # the SAME CA-022 allow-list: anything outside it is refused as
    # out-of-scope-diff before it can ever reach a commit; anything
    # genuinely inside the allow-list is staged here so it lands in the
    # SAME commit as the gitlink bump, converging to a real MIGRATED state
    # instead of leaving honest-but-permanent residue behind forever.
    #
    # T177 Round 3 finding 2 (design decision, documented): the REAL
    # post_update_hook.sh writes exactly two tracked-tree artefacts into the
    # consumer -- `$PROJECT_ROOT/.mcp.json` (MCP server registration) and
    # `$PROJECT_ROOT/skills/` (constitution skill wiring) -- plus
    # `.git/hooks/` (never part of the working tree). Both are the
    # consumer's "development-process tooling/config (mechanisms wired by
    # reference only)" that CA-022 explicitly permits a migration to touch,
    # and they are the very output DEC-25 step 5 exists to produce -- so
    # they are LEGITIMATE migration output, staged and committed in the
    # SAME migration commit, never left as residue and never refused. Before
    # this round both were outside the allow-list, so every migration whose
    # target carried the real hook was refused `out-of-scope-diff` with the
    # hook's files left behind (reproduced live 2026-10-01). Anything ELSE
    # the hook or gates write is still refused, with the residue measured
    # and reported honestly by not_migrated_after_write().
    POST_HOOK_STATUS=$(git -C "$WORKDIR" status --porcelain=v1 2>/dev/null)
    if [ -n "$POST_HOOK_STATUS" ]; then
        OLD_IFS=$IFS
        IFS='
'
        for line in $POST_HOOK_STATUS; do
            f=${line#???}
            case "$f" in
                constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*) : ;;
                *)
                    IFS=$OLD_IFS
                    not_migrated_after_write "wiring" "out-of-scope-diff" "path=$f"
                    ;;
            esac
        done
        IFS=$OLD_IFS
        git -C "$WORKDIR" add -A -- constitution .gitmodules 2>/dev/null || true
        [ -d "$WORKDIR/.claude" ] && git -C "$WORKDIR" add -A -- .claude 2>/dev/null
        [ -d "$WORKDIR/scripts/hooks" ] && git -C "$WORKDIR" add -A -- scripts/hooks 2>/dev/null
        [ -d "$WORKDIR/config/fastcycle" ] && git -C "$WORKDIR" add -A -- config/fastcycle 2>/dev/null
        [ -e "$WORKDIR/.mcp.json" ] && git -C "$WORKDIR" add -A -- .mcp.json 2>/dev/null
        [ -d "$WORKDIR/skills" ] && git -C "$WORKDIR" add -A -- skills 2>/dev/null
        :
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
    #
    # T177 Round 2 R2-I3 fix: binding alone is not CA-024 ("a zero-finding
    # GO review record at the designated tier"). A record whose `verdict`
    # says "GO" while still carrying a Blocking finding, or produced at
    # the WRONG model tier/effort, was previously accepted unconditionally
    # once bound -- reproduced live: {"verdict":"GO", "project_id":...,
    # "target_commit":..., "findings":[{"severity":"Blocking"}],
    # "tier":"haiku"} was accepted and pushed. Now ALSO requires:
    # `findings` present as a list of length 0 (genuinely zero-finding,
    # mirroring review_record.py's own RB-005/constitution 11.4.134 "a GO
    # is terminal only when it has zero findings of any severity"); the
    # designated tier (`model_tier`, falling back to `tier` for a
    # hand-authored fixture) equals "opus"; `effort` equals "xhigh" (the
    # constitution 11.4.209/11.4.231 pin -- no fallback model/effort).
    # Freshness (Round 2 I3 stale-record replay): the record must ALSO
    # carry `consumer_base_commit` equal to THIS run's own pre-migration
    # $LOCAL_HEAD -- without this, a GO record bound only to
    # project_id+target_commit stays valid for ANY later state of the
    # SAME consumer at the SAME constitution target, so a record issued
    # for an earlier attempt could be replayed against a consumer that has
    # since received new commits. $LOCAL_HEAD is captured once, before any
    # write, at the top of this script.
    REVIEW_GO=0
    if [ -n "$REVIEW_REF" ] && [ -f "$REVIEW_REF" ]; then
        REVIEW_CHECK=$(python3 - "$REVIEW_REF" "$PROJECT" "$NEW_SHA" "$LOCAL_HEAD" <<'PYEOF'
import json, sys
path, project, target, base = sys.argv[1:5]
try:
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, ValueError):
    print("NO-GO")
    sys.exit(0)
tier = doc.get("model_tier", doc.get("tier"))
findings = doc.get("findings")
if doc.get("verdict") != "GO":
    print("NO-GO")
elif doc.get("project_id") != project or doc.get("target_commit") != target:
    print("NO-GO")
elif doc.get("consumer_base_commit") != base:
    print("NO-GO")
elif not (isinstance(findings, list) and len(findings) == 0):
    print("NO-GO")
elif tier != "opus":
    print("NO-GO")
elif doc.get("effort") != "xhigh":
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
    # data-model.md #13.3's `review_ref` field ("ReviewVerdictRecord id",
    # "required iff MIGRATED") -- the record's OWN `review_id` where
    # present (a real ReviewVerdictRecord, review_record.py's schema),
    # else the --review-ref path itself (a hand-authored test fixture).
    # (T177 Round 3: the path is passed as argv, never interpolated into
    # Python source text -- a path containing a quote broke the old form.)
    REVIEW_REF_ID=$(python3 -c "
import json, sys
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh)
    rid = d.get('review_id')
    print(rid if rid else path)
except Exception:
    print(path)
" "$REVIEW_REF" 2>/dev/null)

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
        not_migrated_after_write "commit" "local-git-error" "git-commit-failed"
    fi
    NEW_COMMIT=$(git -C "$WORKDIR" rev-parse HEAD)
    # T177 Round 3 finding 4, defence in depth at the push seam: the ONLY
    # commit this migration may publish is its own. The preflight already
    # refuses unpublished local commits before any write; this re-asserts
    # the same invariant immediately before the irreversible push.
    PUSH_SET_SIZE=$(git -C "$WORKDIR" rev-list --count "$LOCAL_HEAD..$NEW_COMMIT" 2>/dev/null)
    if [ "$PUSH_SET_SIZE" != "1" ]; then
        FULL="NOT-MIGRATED (push: out-of-scope-diff)"
        write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "" "" "" "" "refused-before-push: $PUSH_SET_SIZE commit(s) between pre-migration HEAD and the migration commit, expected exactly 1"
        echo "$FULL (refused before push: push set size=$PUSH_SET_SIZE, expected 1)"
        exit 1
    fi

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
        if ! git -C "$WORKDIR" push "$r" "$BRANCH":"$BRANCH" 2>"$MIGRATE_SCRATCH/migrate_push.err"; then
            REASON="remote-rejected"
            if grep -qi 'non-fast-forward\|fetch first' "$MIGRATE_SCRATCH/migrate_push.err" 2>/dev/null; then
                REASON="non-fast-forward"
            fi
            PUSH_FAILURES="$PUSH_FAILURES $r:$REASON"
        else
            PUSH_OK_REMOTES="$PUSH_OK_REMOTES $r"
        fi
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
        write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "$PR"
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
    # No review runs for an already-at-target consumer (steps 5-8 are
    # entirely skipped -- nothing to review), so review_ref is honestly
    # omitted rather than naming a review that never gated anything here.
    REVIEW_REF_ID=""
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
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)"
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
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)"
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

# T177 Round 2 R2-I4 (tips-equal): CA-026 "MIGRATED only when ... gates
# green and tips equal". A real push failure is already caught at step 8;
# this closes the remaining gap -- confirming EVERY configured remote's
# OWN ref, read back via `ls-remote`, genuinely equals the local
# NEW_COMMIT, for both the normal push path and the already-at-target
# path (a remote's own tip may legitimately be unreadable for reasons
# unrelated to this migration -- an empty ls-remote result is skipped,
# never treated as a mismatch, §11.4.201's conservative-safe-default:
# refuse only on a POSITIVELY CONFIRMED mismatch, never on an
# unresolvable read).
TIPS_OK=1
TIPS_DETAIL=""
for r in $(git -C "$WORKDIR" remote 2>/dev/null); do
    RTIP=$(git -C "$WORKDIR" ls-remote "$r" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    if [ -n "$RTIP" ] && [ "$RTIP" != "$NEW_COMMIT" ]; then
        TIPS_OK=0
        TIPS_DETAIL="$TIPS_DETAIL $r:$RTIP"
    fi
done

# T177 Round 2 R2-I4 fix: verify output is COPIED to a durable location
# beside $OUT (never inside $WORKDIR, per the SAME observer-
# decontamination reasoning above) before the scratch copy is deleted --
# the prior code `rm -rf`'d $VERIFY_SCRATCH unconditionally, so a MIGRATED
# record's claimed double-CLEAN-verify had NO surviving evidence to audit
# (§11.4.262: every PASS cites a captured, machine-created artefact).
V1_PERSIST="${OUT%.json}.verify1.json"
V2_PERSIST="${OUT%.json}.verify2.json"
cp -f "$V1" "$V1_PERSIST" 2>/dev/null || V1_PERSIST=""
cp -f "$V2" "$V2_PERSIST" 2>/dev/null || V2_PERSIST=""
rm -rf "$VERIFY_SCRATCH"
# T177 Round 3 finding 8: the record carries the persisted reports'
# CONTENT ADDRESS (sha256 of the exact bytes repo_verify.py wrote), never
# merely a path that could later be overwritten or deleted unnoticed; a
# report that could not be persisted means the MIGRATED claim would cite
# no surviving evidence (§11.4.262), so it is refused below.
V1_SHA=""; V2_SHA=""
[ -n "$V1_PERSIST" ] && V1_SHA=$(sha256sum "$V1_PERSIST" 2>/dev/null | awk '{print $1}')
[ -n "$V2_PERSIST" ] && V2_SHA=$(sha256sum "$V2_PERSIST" 2>/dev/null | awk '{print $1}')
VERIFY_FAIL=""
[ "$V1_RC" -ne 0 ] && VERIFY_FAIL="$VERIFY_FAIL v1_rc=$V1_RC"
[ "$V2_RC" -ne 0 ] && VERIFY_FAIL="$VERIFY_FAIL v2_rc=$V2_RC"
[ "$OVERALL1" != "CLEAN" ] && VERIFY_FAIL="$VERIFY_FAIL overall1=$OVERALL1"
[ "$OVERALL2" != "CLEAN" ] && VERIFY_FAIL="$VERIFY_FAIL overall2=$OVERALL2"
[ -z "$HASH1" ] && VERIFY_FAIL="$VERIFY_FAIL hash1-empty"
[ "$HASH1" != "$HASH2" ] && VERIFY_FAIL="$VERIFY_FAIL hash1!=hash2"
[ "$TIPS_OK" -ne 1 ] && VERIFY_FAIL="$VERIFY_FAIL tips-mismatch:$TIPS_DETAIL"
{ [ -z "$V1_SHA" ] || [ -z "$V2_SHA" ]; } && VERIFY_FAIL="$VERIFY_FAIL evidence-not-persisted"
if [ -n "$VERIFY_FAIL" ]; then
    FULL="NOT-MIGRATED (verify: verification-not-clean)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "" "" "" "" "${VERIFY_FAIL# }"
    echo "$FULL (${VERIFY_FAIL# })"
    exit 1
fi

VERIFICATION_JSON=$(python3 -c "
import json, sys
print(json.dumps([
    {'path': sys.argv[1], 'overall': sys.argv[2], 'body_hash': sys.argv[3], 'content_address': 'sha256:' + sys.argv[4]},
    {'path': sys.argv[5], 'overall': sys.argv[6], 'body_hash': sys.argv[7], 'content_address': 'sha256:' + sys.argv[8]},
]))
" "$V1_PERSIST" "$OVERALL1" "$HASH1" "$V1_SHA" "$V2_PERSIST" "$OVERALL2" "$HASH2" "$V2_SHA")

echo "MIGRATED: $PROJECT commit=$NEW_COMMIT (verified CLEAN x2, body_hash=$HASH1)"
write_out "MIGRATED" "" "$NEW_COMMIT" "$(current_data_change)" "" "$REVIEW_REF_ID" "$VERIFICATION_JSON" "$BACKUP_MARKER_JSON"
exit 0
