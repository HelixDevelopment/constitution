#!/bin/sh
# migrate.sh - consumer migration (T-G05/T174; contract
# contracts/consumer-audit-and-migration.md CA-019..CA-028; guarded by
# tests/test_consumer_migrate_red.sh, T168; FR-025, SC-010).
#
# Usage: migrate.sh --config <fastcycle.yaml> --project <org/repo>
#          --workdir <consumer checkout dir> --out <migration.json>
#          [--apply] [--review-ref <path>]
#          [--operator-blocked] [--scope-decision <scope_decision.json>]
#
# Without --apply: preflight only (CA-028); never writes to $WORKDIR, but
# DOES write the --out record (outcome DRY-RUN) and exits 1 -- a dry run is
# not a migration outcome and `audit.py summary` never counts it.
#
# --out holds exactly ONE record per project (T177 Round 5, round-4 I6):
# `audit.py summary` resolves several records for the same project by
# CONTENT, so an honest retry history left side by side (an earlier
# `dirty-local` record next to a later MIGRATED one) reads as a CONFLICT
# and that project as uncovered (fails safe). Re-runs MUST overwrite the
# project's previous record (reuse the same --out path), never accumulate.
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
# Exit: 0 MIGRATED; 1 NOT-MIGRATED (reason in the JSON body, not a crash)
#       or DRY-RUN (no --apply; preflight passed, nothing migrated);
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

# T177 Round 6 (round-6 IMPORTANT I3): canonicalise --out to an ABSOLUTE
# path too, the SAME way $WORKDIR already is. The persisted verification
# report paths below (${OUT%.json}.verify1.json etc.) were previously
# written relative to the CALLER's cwd at invocation time, but `audit.py
# summary` resolves a record's relative evidence paths against the RECORD
# FILE's own directory (dirname(abspath(mf))) -- a mismatch whenever those
# two directories differ, which is almost always true in real usage (the
# caller's cwd is rarely the same directory the record ends up in).
# Reproduced live 2026-10-01: a migration run with a relative --out from a
# cwd different from the record's eventual directory left a genuinely
# MIGRATED record reading "record-verification-evidence-unverifiable",
# coverage 0, even though the migration itself succeeded cleanly.
OUT_DIR=$(cd "$(dirname "$OUT")" 2>/dev/null && pwd)
if [ -z "$OUT_DIR" ]; then
    echo "migrate.sh: the directory for --out $OUT does not exist" >&2
    exit 2
fi
OUT="$OUT_DIR/$(basename "$OUT")"

# T177 Round 9 (round-8 MINOR M5, point 1): canonicalise --review-ref to an
# ABSOLUTE path too, the SAME class of bug R6-I3 fixed for --out above.
# When the cited review record carries no `review_id` of its own,
# check_review()'s REVIEW_REF_ID derivation falls back to storing
# $REVIEW_REF VERBATIM as the persisted `review_ref` field -- a RELATIVE
# path stored that way is later resolved by `audit.py summary` (when a
# --reviews archive is supplied) against the MIGRATION RECORD's own
# directory (dirname(abspath(mf))), never against the cwd this tool was
# invoked from, so a relative --review-ref whose intended target lives
# elsewhere silently fails to resolve once the record is read back
# (reproduced live: a one-level-down relative --review-ref, with --out
# landing in a DIFFERENT directory, stored verbatim and read back by
# `audit.py summary --reviews` as record-review-ref-unverifiable even
# though the real file existed all along). Canonicalised once, here,
# exactly like $WORKDIR/$OUT above; left untouched when the path does not
# (yet) exist -- check_review()'s own `[ -f "$REVIEW_REF" ]` guard already
# handles that honestly, and canonicalising a nonexistent path's directory
# would itself fail.
if [ -n "$REVIEW_REF" ] && [ -f "$REVIEW_REF" ]; then
    REVIEW_REF_DIR=$(cd "$(dirname "$REVIEW_REF")" 2>/dev/null && pwd)
    if [ -n "$REVIEW_REF_DIR" ]; then
        REVIEW_REF="$REVIEW_REF_DIR/$(basename "$REVIEW_REF")"
    fi
fi

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

# T177 Round 15 (R14-B1 BLOCKING, half 1 of 2): every git command THIS tool
# runs executes with git hooks DISABLED. The step-5 post_update_hook.sh --
# the adversary every round has defended against -- legitimately writes
# `$PROJECT_ROOT/.git/hooks/` (its own STEP 4 `install_hooks`), and
# `.git/hooks/` never appears in `git status`, so no residue check can see
# a hook it installed; the consumer's own pre-existing hooks /
# `core.hooksPath` are a second route needing no post-update hook at all.
# A `pre-commit` hook fires DURING this tool's own `git commit` and its
# index edits land IN the commit, AFTER every staged-content scan already
# passed (reproduced live, round-14 review S1: a shadow `.gitmodules`
# section + product code published, rc=0, MIGRATED); `post-commit` (an
# `--amend`), `pre-push` (a side-channel push of other refs) and
# `reference-transaction` fire at the same seams. `core.hooksPath=/dev/null`
# (a path under which no hook file can exist) disables EVERY hook, not
# only the pre-commit/commit-msg/pre-push subset `--no-verify` skips, and
# `core.fsmonitor=false` stops a configured fsmonitor program (another
# repository-config-driven executable) from running during this tool's own
# status/diff/add calls. Exported as environment-scoped config
# (GIT_CONFIG_COUNT, git >= 2.31) so it reaches EVERY git invocation this
# tool makes -- including the ones repo_verify.py makes during step 9 --
# and overrides anything the hook writes into `.git/config`; the commit and
# push calls additionally pass it explicitly with `-c`. The post-update
# hook and the consumer's own gates are run with the CALLER's original git
# environment restored (run_with_caller_git_env), never with this override
# -- they are the consumer's own processes, not this tool's.
#
# This half is NECESSARY, NOT SUFFICIENT: the load-bearing half is the
# positive post-commit re-verification of the commit's own FINAL tree
# (verify_final_commit, step 7), which does not care HOW a commit came to
# hold whatever it holds.
FC_CALLER_GCC_SET=0
[ -n "${GIT_CONFIG_COUNT+x}" ] && FC_CALLER_GCC_SET=1
FC_CALLER_GCC=${GIT_CONFIG_COUNT:-0}
case "$FC_CALLER_GCC" in
    ''|*[!0-9]*) echo "migrate.sh: inherited GIT_CONFIG_COUNT=$FC_CALLER_GCC is not a number -- refusing to guess how to extend it" >&2; exit 4 ;;
esac
FC_GCC_K1=$FC_CALLER_GCC
FC_GCC_K2=$((FC_CALLER_GCC + 1))
eval "GIT_CONFIG_KEY_$FC_GCC_K1=core.hooksPath; GIT_CONFIG_VALUE_$FC_GCC_K1=/dev/null; export GIT_CONFIG_KEY_$FC_GCC_K1 GIT_CONFIG_VALUE_$FC_GCC_K1"
eval "GIT_CONFIG_KEY_$FC_GCC_K2=core.fsmonitor; GIT_CONFIG_VALUE_$FC_GCC_K2=false; export GIT_CONFIG_KEY_$FC_GCC_K2 GIT_CONFIG_VALUE_$FC_GCC_K2"
GIT_CONFIG_COUNT=$((FC_CALLER_GCC + 2)); export GIT_CONFIG_COUNT
run_with_caller_git_env() {
    # Runs "$@" in a subshell with the caller's ORIGINAL GIT_CONFIG_COUNT
    # restored (extra GIT_CONFIG_KEY_<n>/VALUE_<n> beyond the count are
    # ignored by git).
    (
        if [ "$FC_CALLER_GCC_SET" -eq 1 ]; then
            GIT_CONFIG_COUNT=$FC_CALLER_GCC; export GIT_CONFIG_COUNT
        else
            unset GIT_CONFIG_COUNT
        fi
        "$@"
    )
}

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

# T177 Round 6 (round-6 MINOR M1): reads a single top-level field back from
# the CURRENT on-disk $OUT (never assumed) -- used by the already-at-target
# path to detect, before ANY write to $OUT, whether it already holds a
# genuine MIGRATED record for THIS project that a re-run's review-no-go
# refusal would otherwise silently downgrade in place. Absent/unreadable/
# invalid JSON -> empty string, never a guess.
read_out_field() {
    [ -f "$OUT" ] || { echo ""; return; }
    python3 -c "
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as fh:
        d = json.load(fh)
except Exception:
    print('')
else:
    print(d.get(sys.argv[2], '') or '')
" "$OUT" "$1" 2>/dev/null
}

# Step 6 review check (CA-024), shared by the bump path and -- T177 Round 5
# (round-4 I3) -- the already-at-target path. Sets REVIEW_REF_ID on GO;
# returns 1 (REVIEW_REF_ID empty) for an absent, unbound, stale, non-zero-
# finding or wrong-tier record. Reads $REVIEW_REF/$PROJECT/$NEW_SHA/
# $LOCAL_HEAD at CALL time.
check_review() {
    REVIEW_GO=0
    REVIEW_REF_ID=""
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
        return 1
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
    [ -n "$REVIEW_REF_ID" ] || return 1
    return 0
}

# T177 Round 15 (R14-B1): the symlink (mode 120000) and gitlink (mode 160000)
# scanners, factored out of the step-5 staged-index checks UNCHANGED so the
# SAME code runs twice: once against the STAGED index before commit (step
# 5, `git diff --cached --raw`) and once against the FINAL COMMITTED tree
# before push (verify_final_commit, `git diff-tree --raw LOCAL_HEAD
# NEW_COMMIT`) -- both inputs share git's `--raw -z` record format. Each
# reads the raw diff from the file named by $1; prints a violation line (or
# nothing) and exits non-zero only when the scan itself could not run.
scan_symlinks_raw() {
    python3 -c '
import os, posixpath, subprocess, sys
workdir = sys.argv[1]
data = sys.stdin.buffer.read().split(b"\0")
i = 0
bad = []
while i + 1 < len(data):
    meta, path = data[i], data[i + 1]
    i += 2
    if not meta.startswith(b":"):
        continue
    fields = meta[1:].split()
    if len(fields) < 4 or fields[1] != b"120000":
        continue
    blob = fields[3].decode()
    rel = path.decode("utf-8", "surrogateescape")
    # T177 Round 6 (round-6 BLOCKING B1): this subprocess returncode was
    # previously never checked at all -- a FAILED blob read decoded its
    # empty stdout as target="", which normalizes to "inside the repo"
    # (clean) via posixpath.normpath, silently clearing a blob the scanner
    # never actually inspected (reproduced live under a cat-file-failing
    # shim: an absolute-path symlink was published, rc=0). A failed read
    # is an UNKNOWN target, never a clean one -- the scanner fails loud.
    cat = subprocess.run(["git", "-C", workdir, "cat-file", "blob", blob],
                         capture_output=True)
    if cat.returncode != 0:
        sys.exit(3)
    target = cat.stdout.decode("utf-8", "surrogateescape")
    if target.startswith("/"):
        bad.append("path=%s target-is-absolute" % rel)
        continue
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(rel), target))
    if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
        bad.append("path=%s target-escapes-repository" % rel)
if bad:
    print("host-specific-symlink " + " ".join(bad))
' "$WORKDIR" <"$1"
}
scan_gitlinks_raw() {
    python3 -c '
import sys
data = sys.stdin.buffer.read().split(b"\0")
i = 0
bad = []
while i + 1 < len(data):
    meta, path = data[i], data[i + 1]
    i += 2
    if not meta.startswith(b":"):
        continue
    fields = meta[1:].split()
    if len(fields) < 4 or fields[1] != b"160000":
        continue
    rel = path.decode("utf-8", "surrogateescape")
    if rel == "constitution":
        continue
    bad.append("path=%s" % rel)
if bad:
    print("unexpected-gitlink " + " ".join(bad))
' <"$1"
}

# T177 Round 15 (R14-B1): the CA-022 allow-list for a migration's own
# output -- the step-5 post-hook working-tree check and the step-7 final
# committed-tree re-verification (verify_final_commit) both call THIS one
# definition, so the two can never drift apart. (Previously the list lived
# inline in the step-5 `case` only.) Returns 0 iff path $1 is allowed.
ca022_post_hook_path_ok() {
    case "$1" in
        constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*) return 0 ;;
    esac
    return 1
}

# T177 Round 15 (R14-B1 BLOCKING, half 2 of 2 -- THE LOAD-BEARING PART):
# positive re-verification of the migration commit's own FINAL tree, run
# AFTER the commit exists and BEFORE any push (the point of no return --
# no force-push ever, §11.4.113). Every content check before this point
# inspects the STAGED INDEX; anything that changed the commit between that
# scan and now -- a hook that fired despite half 1, a post-commit amend, a
# background process the post-update hook left running, a future bug in
# this tool itself -- would otherwise be published with only the
# commit-COUNT check (PUSH_SET_SIZE) standing in the way, which a
# same-count rewrite satisfies trivially. This does not care HOW the
# commit came to hold what it holds: it re-derives every invariant this
# tool's design depends on directly from the committed objects. Refuses
# (refuse_final_commit: NOT-MIGRATED (push: out-of-scope-diff), the local
# commit named, never pushed anywhere, never rolled back -- CA-019) on:
#   1. local refs/heads/$BRANCH != the commit about to be pushed;
#   2. parents != exactly [$LOCAL_HEAD] (an amend onto a different parent,
#      or a merge commit smuggling a second parent's history);
#   3. any path in `diff-tree LOCAL_HEAD NEW_COMMIT` outside the CA-022
#      allow-list (the SAME list the step-5 working-tree check enforces);
#   4. NEW_COMMIT:.gitmodules blob != LOCAL_HEAD:.gitmodules blob (R12-B1's
#      whole-file byte-identity, re-asserted on the committed tree);
#   5. the committed "constitution" entry != `160000 commit $NEW_SHA`
#      (R10-I1's positive gitlink invariant, re-asserted on the tree);
#   6. any NEW/changed mode-160000 entry other than "constitution", or any
#      mode-120000 entry whose target is absolute / escapes the repository
#      (the SAME scan_gitlinks_raw / scan_symlinks_raw code as step 5).
# Any read that fails refuses too (§11.4.201) -- an unreadable invariant is
# never a passed one.
refuse_final_commit() {
    FULL="NOT-MIGRATED (push: out-of-scope-diff)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "" "" "" "" "refused-before-push: final-tree-verification: $1; local commit $NEW_COMMIT NOT pushed to any remote"
    echo "$FULL [refused-before-push: final-tree-verification: $1]"
    exit 1
}
verify_final_commit() {
    VFC_BRANCH_TIP=$(git -C "$WORKDIR" rev-parse -q --verify "refs/heads/$BRANCH" 2>/dev/null)
    [ "$VFC_BRANCH_TIP" = "$NEW_COMMIT" ] || refuse_final_commit "branch-$BRANCH-tip=${VFC_BRANCH_TIP:-unreadable} != migration-commit"
    VFC_PARENTS=$(git -C "$WORKDIR" rev-list --parents -n 1 "$NEW_COMMIT" 2>/dev/null)
    [ "$VFC_PARENTS" = "$NEW_COMMIT $LOCAL_HEAD" ] || refuse_final_commit "parents-not-exactly-pre-migration-HEAD got=[${VFC_PARENTS#"$NEW_COMMIT"}] expected=[ $LOCAL_HEAD]"
    VFC_PATHS=$(git -C "$WORKDIR" diff-tree -r --name-only --no-commit-id --no-renames "$LOCAL_HEAD" "$NEW_COMMIT" 2>/dev/null) \
        || refuse_final_commit "committed-path-enumeration-failed"
    OLD_IFS=$IFS
    IFS='
'
    for f in $VFC_PATHS; do
        if ! ca022_post_hook_path_ok "$f"; then
            IFS=$OLD_IFS
            refuse_final_commit "committed-out-of-scope-path=$f"
        fi
    done
    IFS=$OLD_IFS
    VFC_GM_OLD=$(git -C "$WORKDIR" rev-parse -q --verify "$LOCAL_HEAD:.gitmodules" 2>/dev/null)
    VFC_GM_NEW=$(git -C "$WORKDIR" rev-parse -q --verify "$NEW_COMMIT:.gitmodules" 2>/dev/null)
    if [ -z "$VFC_GM_OLD" ] || [ "$VFC_GM_OLD" != "$VFC_GM_NEW" ]; then
        refuse_final_commit "committed-gitmodules-blob-changed old=${VFC_GM_OLD:-unreadable} new=${VFC_GM_NEW:-absent}"
    fi
    VFC_CONST=$(git -C "$WORKDIR" ls-tree "$NEW_COMMIT" constitution 2>/dev/null)
    VFC_CONST_EXPECTED=$(printf '160000 commit %s\tconstitution' "$NEW_SHA")
    [ "$VFC_CONST" = "$VFC_CONST_EXPECTED" ] || refuse_final_commit "committed-constitution-entry=[${VFC_CONST:-absent}] expected-target=$NEW_SHA"
    VFC_RAW="$MIGRATE_SCRATCH/final_commit_diff.raw"
    git -C "$WORKDIR" diff-tree -r --raw --no-abbrev -z --no-renames "$LOCAL_HEAD" "$NEW_COMMIT" >"$VFC_RAW" 2>/dev/null \
        || refuse_final_commit "committed-raw-diff-failed"
    VFC_GITLINK=$(scan_gitlinks_raw "$VFC_RAW" 2>/dev/null) || refuse_final_commit "committed-gitlink-scan-failed"
    [ -z "$VFC_GITLINK" ] || refuse_final_commit "committed-$VFC_GITLINK"
    VFC_SYMLINK=$(scan_symlinks_raw "$VFC_RAW" 2>/dev/null) || refuse_final_commit "committed-symlink-scan-failed"
    [ -z "$VFC_SYMLINK" ] || refuse_final_commit "committed-$VFC_SYMLINK"
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
# T177 Round 10 (R10-M2 MINOR, honestly documented here -- a prior round's
# commit message claimed this note existed when it did not): a checkout
# with NO configured upstream (`@{u}` unset -- e.g. `git checkout -b` with
# no `--track`, or a branch never pushed-with-set-upstream) resolves
# $UPSTREAM to the empty string. Every downstream check gated on
# `[ -n "$UPSTREAM" ]` (the behind-check immediately below, and the
# per-remote tree-delta content check further down, R10-I2) then simply
# SKIPS its own UPSTREAM-trust comparison for such a checkout -- a
# genuinely-lagging-mirror retry whose content would otherwise be
# verifiable against a trusted upstream is conservatively REFUSED
# (`divergent-branches`) instead of allowed, since there is nothing this
# tool can check its out-of-scope content against. This is a KNOWN,
# ACCEPTED, conservative limitation (§11.4.101's safe-reversible default
# applied to an unresolvable trust signal) -- never a bug -- and is
# recorded honestly here rather than left undocumented: a real consumer
# checkout produced by a normal `git clone` always has `@{u}` set, so this
# only narrows an already-rare corner case to an honest refusal instead of
# an unverifiable guess.
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
#
# T177 Round 5 (round-4 MINOR, detached HEAD): `rev-parse --abbrev-ref HEAD`
# prints the literal "HEAD" on a detached checkout, and the synthetic
# `refs/remotes/origin/HEAD` symref then satisfied the "published
# counterpart" lookup below -- the run committed locally and only failed
# at the real push (`HEAD:HEAD`), leaving a local commit behind. A detached
# checkout has no branch to fast-forward at all, so it is refused here,
# before any write.
if [ "$BRANCH" = "HEAD" ] || [ -z "$BRANCH" ]; then
    not_migrated "preflight" "divergent-branches" "detached-HEAD-no-branch-to-fast-forward"
fi
#
# T177 Round 5 (round-4 I4): the unpublished-commit count is now taken
# COLLECTIVELY against the union of every remote's copy of THIS branch
# (`git rev-list --count HEAD --not <every refs/remotes/<r>/$BRANCH>`),
# never against each remote separately. The per-remote form produced a
# FALSE refusal whenever one mirror merely LAGGED behind a commit already
# published on another remote (reproduced in round 4: origin at HEAD,
# `mirror` one commit behind -> "local-ahead-of-mirror/main-by-1-
# unpublished-commit(s)" although `rev-list HEAD --not --remotes` was 0) --
# a common shape in any multi-remote fleet. Pushing to the lagging mirror
# only republishes history that is already public on another remote.
# The union is deliberately restricted to THIS branch's remote copies, not
# `--remotes` (every remote ref): a local branch fast-forwarded onto some
# OTHER published branch (e.g. an unreviewed origin/feature-x) has zero
# commits outside `--remotes`, yet pushing it would move product code onto
# $BRANCH on every remote -- the same CA-022 violation finding 4 closed.
PUBLISHED_REFS=0
PUBLISHED_REF_LIST=""
for r in $(git -C "$WORKDIR" remote 2>/dev/null); do
    RREF="refs/remotes/$r/$BRANCH"
    if git -C "$WORKDIR" rev-parse -q --verify "$RREF" >/dev/null 2>&1; then
        PUBLISHED_REFS=$((PUBLISHED_REFS + 1))
        PUBLISHED_REF_LIST="$PUBLISHED_REF_LIST $RREF"
    fi
done
if [ "$PUBLISHED_REFS" -eq 0 ]; then
    not_migrated "preflight" "divergent-branches" "branch-$BRANCH-has-no-published-counterpart-on-any-remote"
fi
# shellcheck disable=SC2086  # deliberate word-splitting: one ref per word
UNPUBLISHED=$(git -C "$WORKDIR" rev-list --count "$LOCAL_HEAD" --not $PUBLISHED_REF_LIST 2>/dev/null)
if [ -z "$UNPUBLISHED" ]; then
    echo "migrate.sh: could not measure unpublished commits against$PUBLISHED_REF_LIST" >&2
    exit 4
fi
if [ "$UNPUBLISHED" != "0" ]; then
    not_migrated "preflight" "divergent-branches" "local-$BRANCH-has-$UNPUBLISHED-commit(s)-unpublished-on-every-remote"
fi

# T177 Round 6 (round-6 IMPORTANT I6): the COLLECTIVE check above (zero
# commits of $LOCAL_HEAD outside the UNION of every remote's copy of this
# branch) correctly stops treating a merely-LAGGING mirror as "unpublished"
# (round-4 I4), but the union also means a commit published to ONLY ONE
# remote reads as "already published" for every OTHER remote too --
# reproduced live: a product-code commit pushed to a SINGLE mirror, never
# to origin or any other remote, was then propagated by this tool onto
# EVERY remote's copy of $BRANCH, the exact CA-022 violation the collective
# check was never meant to permit.
#
# Each PUBLISHED remote is checked INDIVIDUALLY: of the commits that would
# be NEWLY DELIVERED to it by pushing (not yet on its own copy of
# $BRANCH), every one must EITHER (a) already be an ancestor of this
# branch's own tracked upstream ($UPSTREAM, resolved above -- the checkout's
# own canonical source; a commit that reached THIS checkout via its own
# upstream is trusted regardless of which paths it touches, exactly how
# CA-025's legitimate retry case -- a prior MIGRATION commit already
# fetched from upstream, pending push to a lagging mirror -- works), OR (b)
# touch ONLY the CA-022 allow-listed paths (the SAME allow-list enforced on
# this run's own staged diff above). A remote already carrying every local
# commit has nothing newly delivered and is skipped.
#
# T177 Round 9 (round-8 IMPORTANT I3): the "honest boundary" above was a
# LIVE, trivially exploitable gap, not merely a documented residual --
# confirmed by the round-8 review: a plain `git diff-tree` (no `-m`/`-c`)
# on a MERGE commit prints NOTHING for the content the merge's own
# CONFLICT RESOLUTION introduces (content present in neither parent
# individually), so a merge commit whose non-$UPSTREAM parent only touches
# an allow-listed path, but whose MERGE RESOLUTION itself appends
# out-of-scope content (e.g. product code), sailed through this check
# entirely -- published to origin, recorded MIGRATED. `--cc` closed THAT
# shape: it prints exactly the paths that differ from EVERY parent.
#
# T177 Round 10 fix (R10-I2 IMPORTANT): `--cc` does NOT close the gap for
# a merge resolution that selects exactly ONE parent's version in full --
# `--cc` prints only paths differing from EVERY parent, so a resolution
# equal to one parent's own content (even though it differs from, and
# silently REVERTS, the OTHER parent's already-reviewed change) prints
# NOTHING, exactly like a genuinely clean merge (reproduced live, R10
# review: an evil merge whose resolution reset a product file back to an
# ancestor commit's content -- identical to one parent, different from
# the other -- passed `--cc` with `[]` and was published, reverting an
# already-reviewed upstream change on origin).
#
# Per-COMMIT inspection (of any kind -- plain, `-m`, or `--cc`) is
# therefore the WRONG invariant: it can never distinguish "this commit's
# own diff is clean" from "the net effect of everything this remote would
# newly receive is clean", and a resolution-shaped bypass always exists
# for whichever per-commit diff mode is chosen. The actual CA-022
# invariant is about the TREE this remote would end up with, not about
# how any individual commit got there -- so this now compares TREES, not
# commits: for each remote `r` that already carries SOME copy of
# $BRANCH, every path that differs between `r`'s own current tip and
# $LOCAL_HEAD is either (a) inside the CA-022 allow-list, or (b) carries,
# at $LOCAL_HEAD, the EXACT SAME content it already carries at this
# checkout's own tracked $UPSTREAM -- i.e. content that reached this
# checkout via its own trusted source and is merely catching a lagging
# mirror up (CA-025's legitimate retry case), never a change this run
# would be the first to publish anywhere trusted. No per-commit ancestry
# walk, and no diff MODE (plain/`-m`/`--cc`), is examined any more for
# this check -- the tree-level content comparison subsumes every one of
# them, including the resolution-selects-one-parent shape none of them
# could.
# T177 Round 10 fix (own defect, found while fixing R10-I2 -- reproduced
# live against this file's own C4g fixture): a TREE comparison is
# meaningless for a remote this push could never genuinely fast-forward
# onto in the first place -- when `r`'s own current tip is NOT an
# ancestor of $LOCAL_HEAD (the remote has diverged, or is simply AHEAD of
# a checkout with no configured upstream -- C4g's own deliberately
# unset-upstream fixture), a real `git push` (this tool never force-
# pushes anything, anywhere, ever -- §11.4.113) is rejected by git
# ITSELF as non-fast-forward BEFORE any content transfers at all; the
# tree-level content diff this
# loop computes in that case reflects what the REMOTE already has that
# LOCAL_HEAD lacks just as much as the reverse, and refusing on it here
# would wrongly intercept, with the WRONG reason, a scenario this tool
# is specifically designed to let reach the real, natural push-rejection
# at step 8 instead.
#
# T177 Round 12 fix (R12-I1 IMPORTANT, regression Round 11 introduced
# while fixing the comment above): "skipped entirely for a non-ancestor
# remote" was WRONG -- it protects only the C4g shape (the remote is
# simply AHEAD, racing with a commit of its own; this push could never
# fast-forward there regardless of content). Round 9's per-commit walk
# used a DIVERGED remote's own content as a canary that caught a commit
# published to only ONE other mirror and nowhere else; skipping every
# non-ancestor remote outright removed that canary, and the SAME
# unconditional `continue` ALSO covered a remote with NO copy of $BRANCH
# at all -- a push to THAT remote is not a fast-forward refusal either,
# it CREATES the branch and delivers the FULL history in one shot.
# Reproduced live (R12 review, adv_b1): no `@{u}`, origin diverged with
# someone else's unrelated commit, a product-code commit published to
# ONLY one mirror -- Round 11 skipped both the diverged origin (the
# canary) and the branch-less second mirror (nothing to compare), and
# seeded that product commit onto the second mirror irreversibly; Round
# 9's own per-commit walk refused this exact fixture at preflight,
# naming the offending path.
#
# Fixed per remote, not by skipping: a remote whose ref IS an ancestor of
# $LOCAL_HEAD keeps the original tree-diff-against-the-remote's-own-tip
# comparison (the fast, common case). A remote that EXISTS but has
# DIVERGED compares against the MERGE-BASE of the remote and $LOCAL_HEAD
# instead of the remote's own tip -- the paths $LOCAL_HEAD itself changed
# since that merge-base, i.e. content THIS checkout would newly deliver,
# independent of whatever unrelated history the remote raced ahead with.
# When $LOCAL_HEAD is itself an ancestor of the (diverged) remote -- the
# C4g shape, the remote simply ahead, never a true divergence -- the
# merge-base IS $LOCAL_HEAD and this correctly yields an empty diff,
# falling through to the real `git push` for its natural non-fast-
# forward rejection, exactly as Round 10 intended; when the two histories
# share no common ancestor at all, every path $LOCAL_HEAD carries is
# content that remote has never seen. A remote with NO copy of $BRANCH at
# all is treated the same way as the no-common-ancestor case -- there is
# no remote tip, and no merge-base, to diff against, so every path
# $LOCAL_HEAD carries is newly delivered in full; with no $UPSTREAM
# configured at all there is nothing to verify that full delivery
# against, so seeding it is refused UNCONDITIONALLY (§11.4.101
# conservative-safe default on an unresolvable trust signal), never
# merely on the first out-of-scope path found.
check_remote_scope() {
    # $1=remote name; $TREE_DIFF is set by the caller immediately before
    # this is invoked. Factored out of the single ancestor-case branch
    # below (T177 Round 12, R12-I1) because the SAME per-path scope check
    # now runs from three different TREE_DIFF-computation strategies.
    r=$1
    [ -z "$TREE_DIFF" ] && return 0
    OLD_IFS=$IFS
    IFS='
'
    for f in $TREE_DIFF; do
        case "$f" in
            constitution|.gitmodules|.mcp.json) continue ;;
            .claude/*|scripts/hooks/*|config/fastcycle/*|skills/*) continue ;;
        esac
        TD_OK=0
        if [ -n "$UPSTREAM" ]; then
            TD_LOCAL=$(git -C "$WORKDIR" rev-parse -q --verify "$LOCAL_HEAD:$f" 2>/dev/null)
            TD_UPSTREAM=$(git -C "$WORKDIR" rev-parse -q --verify "$UPSTREAM:$f" 2>/dev/null)
            [ "$TD_LOCAL" = "$TD_UPSTREAM" ] && TD_OK=1
        fi
        if [ "$TD_OK" -ne 1 ]; then
            IFS=$OLD_IFS
            not_migrated "preflight" "divergent-branches" "remote-$r-would-newly-receive-out-of-scope-path-$f"
        fi
    done
    IFS=$OLD_IFS
}
# T177 Round 15 fix (R14-I1 IMPORTANT, pre-existing since Round 10): the
# TREE comparison above compares FINAL states only, so it is structurally
# blind to INTERMEDIATE history -- a commit X adding unreviewed product
# code followed by a commit Y reverting it nets to an EMPTY tree diff, and
# if X and Y were published to only ONE mirror (never to this checkout's
# trusted upstream), pushing "$BRANCH" to every other remote delivers X's
# full content in that remote's history even though no final tree shows
# it (reproduced live, round-14 review S4: rc=0, MIGRATED, origin then
# contains X). Round 9's per-commit walk would have caught it; Round 10
# replaced the walk with the tree comparison because a per-commit diff in
# ANY mode cannot see a merge RESOLUTION that selects one parent's content
# in full (the select-one-parent evil merge, J28). Neither invariant
# subsumes the other, so BOTH are now required -- composed, never one
# replacing the other: check_remote_scope (the tree, run first, its
# refusal detail unchanged) AND check_remote_commits (each commit, below);
# a refusal from EITHER refuses the migration.
#
# For remote $1, every commit that pushing "$BRANCH" would NEWLY DELIVER
# ($LOCAL_HEAD's history minus what that remote's own copy of $BRANCH --
# $2, empty for a branch-less remote, whose push delivers the FULL history
# -- already holds) must EITHER (a) be an ancestor of this checkout's own
# tracked $UPSTREAM (already-reviewed content catching a lagging remote
# up -- excluded directly by `--not $UPSTREAM`), OR (b) touch ONLY CA-022
# allow-listed paths in its OWN individual diff, never the net tree diff.
# A merge commit's "own" diff is `diff-tree -c`: the paths its result
# differs from EVERY parent in, i.e. what the merge itself introduced
# (each parent's own commits are walked individually anyway; the
# select-one-parent resolution `-c` cannot see is exactly what the tree
# check above exists for -- the reason both run). Commits are walked
# oldest-first (`--reverse`) so a refusal names the commit that FIRST
# introduced the out-of-scope path (X), not a later one that reverted it
# (Y). A walk or diff that cannot run refuses (§11.4.201 conservative-safe
# default), never skips.
check_remote_commits() {
    r=$1; CRC_REMOTE_REF=$2
    if [ -n "$UPSTREAM" ] && [ -n "$CRC_REMOTE_REF" ]; then
        CRC_LIST=$(git -C "$WORKDIR" rev-list --reverse "$LOCAL_HEAD" --not "$UPSTREAM" "$CRC_REMOTE_REF" 2>/dev/null) || CRC_LIST="__FAILED__"
    elif [ -n "$UPSTREAM" ]; then
        CRC_LIST=$(git -C "$WORKDIR" rev-list --reverse "$LOCAL_HEAD" --not "$UPSTREAM" 2>/dev/null) || CRC_LIST="__FAILED__"
    elif [ -n "$CRC_REMOTE_REF" ]; then
        CRC_LIST=$(git -C "$WORKDIR" rev-list --reverse "$LOCAL_HEAD" --not "$CRC_REMOTE_REF" 2>/dev/null) || CRC_LIST="__FAILED__"
    else
        CRC_LIST=$(git -C "$WORKDIR" rev-list --reverse "$LOCAL_HEAD" 2>/dev/null) || CRC_LIST="__FAILED__"
    fi
    if [ "$CRC_LIST" = "__FAILED__" ]; then
        not_migrated "preflight" "divergent-branches" "remote-$r-newly-delivered-commit-walk-failed"
    fi
    for c in $CRC_LIST; do
        CRC_PATHS=$(git -C "$WORKDIR" diff-tree --root -r -c --name-only --no-commit-id --no-renames "$c" 2>/dev/null) \
            || not_migrated "preflight" "divergent-branches" "remote-$r-newly-delivered-commit-$c-diff-failed"
        OLD_IFS=$IFS
        IFS='
'
        for f in $CRC_PATHS; do
            case "$f" in
                constitution|.gitmodules|.mcp.json) continue ;;
                .claude/*|scripts/hooks/*|config/fastcycle/*|skills/*) continue ;;
            esac
            IFS=$OLD_IFS
            not_migrated "preflight" "divergent-branches" "remote-$r-would-newly-receive-commit-$c-touching-out-of-scope-path-$f"
        done
        IFS=$OLD_IFS
    done
}
for r in $(git -C "$WORKDIR" remote 2>/dev/null); do
    RREF="refs/remotes/$r/$BRANCH"
    if ! git -C "$WORKDIR" rev-parse -q --verify "$RREF" >/dev/null 2>&1; then
        # Branch-less remote (R12-I1): no tip to diff against at all --
        # pushing "$BRANCH":"$BRANCH" here CREATES the branch, delivering
        # every path $LOCAL_HEAD carries in one shot. Refused outright
        # with no $UPSTREAM to verify against; otherwise every path is
        # checked exactly like a newly-delivered out-of-scope path below.
        if [ -z "$UPSTREAM" ]; then
            not_migrated "preflight" "divergent-branches" "remote-$r-has-no-$BRANCH-and-no-upstream-to-verify-seed-content-against"
        fi
        TREE_DIFF=$(git -C "$WORKDIR" ls-tree -r --name-only "$LOCAL_HEAD" 2>/dev/null)
        check_remote_scope "$r"
        check_remote_commits "$r" ""
        continue
    fi
    if ! git -C "$WORKDIR" merge-base --is-ancestor "$RREF" "$LOCAL_HEAD" 2>/dev/null; then
        # Diverged remote (R12-I1): compare against the merge-base, not
        # the remote's own current tip -- see the block comment above.
        MERGE_BASE=$(git -C "$WORKDIR" merge-base "$RREF" "$LOCAL_HEAD" 2>/dev/null)
        if [ -n "$MERGE_BASE" ]; then
            TREE_DIFF=$(git -C "$WORKDIR" diff --name-only "$MERGE_BASE" "$LOCAL_HEAD" 2>/dev/null)
        else
            TREE_DIFF=$(git -C "$WORKDIR" ls-tree -r --name-only "$LOCAL_HEAD" 2>/dev/null)
        fi
        check_remote_scope "$r"
        check_remote_commits "$r" "$RREF"
        continue
    fi
    # Ancestor remote: an EMPTY tree diff no longer short-circuits the
    # remote (R14-I1) -- net-zero intermediate history is exactly the case
    # whose tree diff is empty, so the per-commit walk always runs.
    TREE_DIFF=$(git -C "$WORKDIR" diff --name-only "$RREF" "$LOCAL_HEAD" 2>/dev/null)
    [ -z "$TREE_DIFF" ] || check_remote_scope "$r"
    check_remote_commits "$r" "$RREF"
done

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
        if ! run_with_caller_git_env sh -c 'cd "$1" && PROJECT_ROOT="$1" CONST_DIR="$1/constitution" bash "$2"' fc-hook "$WORKDIR" "$HOOK" >"$MIGRATE_SCRATCH/migrate_hook.log" 2>&1; then
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
        if ! run_with_caller_git_env sh -c 'cd "$1" && sh "$2"' fc-gates "$WORKDIR" "$GATES_SCRIPT" >"$MIGRATE_SCRATCH/migrate_gates.log" 2>&1; then
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
            if ! ca022_post_hook_path_ok "$f"; then
                IFS=$OLD_IFS
                not_migrated_after_write "wiring" "out-of-scope-diff" "path=$f"
            fi
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

    # T177 Round 5 (round-4 BLOCKING B1): the allow-list above admits PATHS,
    # but a path's CONTENT can still be host-specific. The real
    # post_update_hook.sh wires skills as `ln -s "${CONST_DIR}/skills/<n>"
    # "${PROJECT_ROOT}/skills/<n>"` -- CONST_DIR is THIS migrating host's
    # own absolute path, so the staged blob is a mode-120000 symlink whose
    # content is e.g. /tmp/.../checkout/constitution/skills/media-validator.
    # Round 3 committed and pushed it verbatim and step 9 still reported
    # CLEAN: the migrating host's filesystem layout landed in the
    # consumer's PERMANENT history (irreversible -- no force-push, §11.4.113)
    # and is dangling garbage on every other host's fresh clone. The review
    # record is bound to (project, target, base) BEFORE the hook runs, so
    # it never covers this host-dependent hook output either.
    #
    # Every staged symlink (mode 120000, added or modified) is therefore
    # checked against the ONE property that makes content identical on every
    # host: its target must be RELATIVE and must resolve -- lexically,
    # without following any link -- to a location INSIDE this repository's
    # own tree. An absolute target, or a relative one that climbs out of the
    # repository, is refused out-of-scope-diff before review/commit/push;
    # the refusal never rewrites the hook's output (the tool does not
    # second-guess what the hook meant -- the hook must emit portable links).
    # T177 Round 6 (round-6 BLOCKING B1): the staged add/modify/type-change
    # diff enumeration is captured to a file ONCE and its OWN exit status
    # checked explicitly -- feeding it straight into a pipeline (the
    # round-5 shape: `git diff ... | python3 -c '...'`) left the
    # enumeration's own failure invisible: `$?` after a pipeline with no
    # `pipefail` reflects only the LAST stage (python3), so a failure of
    # the `git diff` itself fed python3 an EMPTY stdin, which legitimately
    # prints nothing and exits 0 -- a silent "clean" verdict for content
    # nobody enumerated. Reproduced live under a forced `git diff --cached
    # --raw` failure: a staged absolute-path symlink was published
    # verbatim, rc=0, remote tip moved. BOTH the symlink scan (mode 120000,
    # below) and the gitlink scan (mode 160000, R6-I2, further below) read
    # this SAME captured enumeration.
    # T177 Round 9 (round-8 IMPORTANT I1, own-defect self-caught by this
    # round's real test run): `--no-abbrev` is REQUIRED here because the
    # gitlink scanner below now compares a staged "constitution" entry's
    # commit SHA, byte-for-byte, against the full 40-char $NEW_SHA --
    # without it, `git diff --raw` ABBREVIATES object ids by default
    # (measured live: `--full-index` has NO EFFECT on `--raw` output --
    # that flag only widens the "index" line of PATCH format; `--raw`'s
    # own abbreviation is controlled by `--no-abbrev`/`--abbrev=40`), so
    # even a genuinely CORRECT migration's own staged SHA (e.g. 7 hex
    # chars) could never equal the full $NEW_SHA string, and every real
    # migration would be wrongly refused (reproduced live: J16/J18/every
    # golden fixture failed to migrate at all until this was corrected).
    # The symlink scanner's own `git cat-file blob <blob>` call accepts a
    # full SHA exactly as well as an abbreviated one, so this is a strict
    # improvement with no regression to that check.
    SYMLINK_DIFF="$MIGRATE_SCRATCH/migrate_symlink_diff.raw"
    if ! git -C "$WORKDIR" diff --cached --raw --no-abbrev -z --no-renames --diff-filter=AMT >"$SYMLINK_DIFF" 2>/dev/null; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "symlink-scan-failed"
    fi
    SYMLINK_VIOLATION=$(scan_symlinks_raw "$SYMLINK_DIFF" 2>/dev/null)
    SYMLINK_RC=$?
    if [ "$SYMLINK_RC" -ne 0 ]; then
        # The scanner itself could not run: refuse rather than publish
        # content nobody inspected (§11.4.201 conservative-safe default).
        not_migrated_after_write "wiring" "out-of-scope-diff" "symlink-scan-failed"
    fi
    if [ -n "$SYMLINK_VIOLATION" ]; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "$SYMLINK_VIOLATION"
    fi

    # T177 Round 6 (round-6 IMPORTANT I2): a staged GITLINK (mode 160000)
    # under an allow-listed directory -- e.g. a hook that `git init`s +
    # commits INSIDE `skills/<n>` -- points at a commit that exists ONLY on
    # this migrating host. The symlink scanner above only inspects mode
    # 120000 entries, so this class previously published an unfetchable
    # commit into the consumer's PERMANENT history BEFORE step 9's
    # post-push verify could ever catch it (no force-push, §11.4.113 --
    # irreversible by then).
    #
    # T177 Round 9 (round-8 IMPORTANT I1): the round-6 fix above had TWO
    # bypasses, both confirmed live by the round-8 review and BOTH closed
    # here, never left as a narrow patch for the two demonstrated
    # instances alone:
    #
    #   (a) The "declared as a path in .gitmodules" carve-out let a hook
    #       `git init` + commit INSIDE an allow-listed directory, then
    #       simply APPEND a `.gitmodules` entry declaring that same path a
    #       submodule pointing at a host-local URL -- since `.gitmodules`
    #       is itself allow-listed and auto-staged (`git add -A --
    #       constitution .gitmodules` above), the now-"declared" gitlink
    #       sailed through this scanner, was committed and pushed, and
    #       only step 9's POST-PUSH verify (too late -- no force-push,
    #       §11.4.113) ever noticed the fresh clone could not fetch it.
    #       There is no carve-out for ANY declared path any more: every
    #       staged 160000 entry other than "constitution" itself is
    #       refused outright, before commit/push, regardless of whether
    #       some OTHER file in the same staged diff declares it. (A
    #       legitimate consumer may still carry OTHER, PRE-EXISTING,
    #       UNCHANGED submodule gitlinks -- those never appear in this
    #       migration's own staged diff at all, so they are never touched
    #       by this check.)
    #   (b) "constitution" was exempted BY NAME, never by the SHA it
    #       staged -- `git update-index --add --cacheinfo
    #       160000,$NEW_SHA,constitution` above sets the correct value,
    #       but line 854's later `git add -A -- constitution .gitmodules`
    #       RE-STAGES it, so a hook that commits INSIDE $CONST_DIR (the
    #       checked-out constitution submodule itself) between those two
    #       points silently moves the staged "constitution" gitlink to a
    #       commit that exists ONLY on this host -- worse than (a), since
    #       the published pointer then differs from the EXACT commit the
    #       CA-024 review was bound to, while the commit message still
    #       claims "bump constitution pointer to $NEW_SHA".
    #
    # T177 Round 10 (R10-I1 IMPORTANT): "constitution"'s own SHA is no
    # longer checked HERE at all -- this diff-based scan only ever runs
    # when a 160000 entry for the path happens to appear in the captured
    # `--diff-filter` (Added/Modified/Type-changed) enumeration, which is exactly the bypassable
    # precondition R10-I1 closes below with a POSITIVE, unconditional
    # index assertion (deletion/revert/type-change every evade this diff
    # scan by construction -- none of them leaves a MODIFIED 160000 entry
    # for "constitution" in an AMT-filtered diff). "constitution" is
    # therefore simply skipped here (verified exhaustively, unconditionally,
    # immediately below instead); every OTHER staged 160000 path remains
    # refused outright, exactly as round 9 left it.
    GITLINK_VIOLATION=$(scan_gitlinks_raw "$SYMLINK_DIFF" 2>/dev/null)
    GITLINK_RC=$?
    if [ "$GITLINK_RC" -ne 0 ]; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "gitlink-scan-failed"
    fi
    if [ -n "$GITLINK_VIOLATION" ]; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "$GITLINK_VIOLATION"
    fi

    # T177 Round 10 fix (R10-I1 IMPORTANT, same invariant class as
    # R8-I1(b)): the diff-based scan above only ever examines
    # "constitution" when a mode-160000 entry for that exact path happens
    # to appear in that Added/Modified/Type-changed-filtered capture -- three distinct
    # shapes never produce such an entry at all and sailed through
    # untouched (R10 review, adv1): (a) DELETING the checked-out submodule
    # directory before staging (a deletion is filtered OUT by `AMT`,
    # which only matches Added/Modified/Type-changed entries); (b)
    # checking the submodule's own working tree back out to an EARLIER
    # commit, so the re-staged value equals what was ALREADY in the
    # parent commit's own tree (no diff entry is produced for a path
    # whose staged value did not change relative to HEAD); (c) replacing
    # the gitlink with a REGULAR FILE (mode 100644) -- the capture is
    # restricted to mode-120000/160000 entries by each scanner's own
    # `fields[1] !=` guard, so a type-changed entry whose NEW mode is
    # 100644 matches neither. Every one of the three was committed with a
    # message still reading "bump constitution pointer to $NEW_SHA" and
    # published irreversibly (no force-push, §11.4.113); step 9's own
    # post-push verify eventually noticed each one, but only AFTER
    # publication -- exactly the "too late" class R8-I1(b) closed for the
    # host-only-SHA shape alone.
    #
    # Rather than enumerate a fourth diff-filter edge case (the same
    # narrow-patching pattern that produced three near-misses on this one
    # invariant across rounds 6/8/9), the POSITIVE invariant is asserted
    # directly, UNCONDITIONALLY, every migration, regardless of what the
    # staged DIFF looks like: the CURRENT INDEX, read fresh via `git
    # ls-files -s`, MUST hold exactly one entry for path "constitution",
    # mode 160000, object id equal to $NEW_SHA byte-for-byte -- nothing
    # else. Any deviation at all (absent, wrong mode, wrong object id) is
    # refused before commit/push. This single check subsumes every one of
    # the three bypass shapes above at once (deleted => absent from the
    # index; reverted => present but with the OLD object id; type-changed
    # => present but with mode 100644) without special-casing any of them
    # individually, and is independent of (does not need, and is never
    # skipped because of) the AMT-filtered diff capture above.
    CONST_INDEX_ACTUAL=$(git -C "$WORKDIR" ls-files -s -- constitution 2>/dev/null)
    CONST_INDEX_EXPECTED=$(printf '160000 %s 0\tconstitution' "$NEW_SHA")
    if [ "$CONST_INDEX_ACTUAL" != "$CONST_INDEX_EXPECTED" ]; then
        CONST_ACTUAL_MODE=$(echo "$CONST_INDEX_ACTUAL" | awk '{print $1}')
        CONST_ACTUAL_SHA=$(echo "$CONST_INDEX_ACTUAL" | awk '{print $2}')
        not_migrated_after_write "wiring" "out-of-scope-diff" "unexpected-gitlink path=constitution staged-commit=${CONST_ACTUAL_SHA:-absent} staged-mode=${CONST_ACTUAL_MODE:-absent} expected-target=$NEW_SHA"
    fi

    # T177 Round 10 fix (R10-B1 BLOCKING): `.gitmodules` CONTENT is never
    # validated anywhere above -- it is allow-listed and auto-staged
    # (`git add -A -- constitution .gitmodules`, this round's own line
    # above), so a hook that rewrites an EXISTING submodule section's own
    # `url`/`path` to a host-local path (e.g. `git config -f .gitmodules
    # submodule.constitution.url "$CONST_DIR/../.git/modules/constitution"`)
    # sails through every scanner above untouched: the pushed "constitution"
    # gitlink SHA stays correct (R10-I1's assertion above still passes),
    # and step 9's own post-push verify runs on THIS SAME migrating host,
    # where the rewritten path still genuinely resolves, so it reports
    # CLEAN too. Every OTHER host's fresh clone then gets a permanently
    # unfetchable submodule url, published irreversibly (no force-push,
    # §11.4.113) -- reproduced live (R10 review, adv3): rc=0, MIGRATED,
    # with the published `.gitmodules` carrying a bare host path.
    #
    # T177 Round 12 fix (R12-B1 BLOCKING, closes the R10-B1 gap for good):
    # the Round 10 check above asserted equality only PER (name, url|path)
    # KEY already present in the PRE-MIGRATION HEAD's `.gitmodules` -- a
    # hook could leave that EXISTING section byte-for-byte untouched and
    # simply APPEND a brand-NEW section (a different submodule NAME)
    # declaring the SAME path (`git config -f .gitmodules submodule.
    # zz-shadow.path constitution; git config -f .gitmodules submodule.
    # zz-shadow.url <host-local-path>`) -- the per-KEY loop never iterates
    # a section that was never present in `old` at all, so this sailed
    # through untouched. Reproduced live (R12 review, adv_a1): `git
    # config -f` appends new sections at the END of the file, and that
    # end-of-file ordering is EXACTLY what `git submodule init` resolves
    # for a same-path collision on a fresh clone -- the shadow section
    # won ("zz-shadow (<host-local-path>) registered for path
    # 'constitution'"), published irreversibly, rc=0, recorded MIGRATED.
    #
    # The per-KEY equality check is replaced with the stronger invariant
    # the R10-B1 comment above already stated but did not enforce: no
    # hook in this codebase legitimately writes `.gitmodules` AT ALL
    # (re-verified directly this round: every hook under `scripts/`,
    # `post_update_hook.sh` included, still never touches this file; the
    # only writers anywhere in this tree are test fixtures/mutants
    # constructing a FIXTURE consumer, never anything this tool would run
    # against a real one). The staged `.gitmodules` blob is therefore
    # asserted BYTE-IDENTICAL to the PRE-MIGRATION HEAD's -- not per-key,
    # the WHOLE FILE -- which closes the shadow-section bypass (a NEW
    # section changes the file's bytes regardless of which existing
    # section it leaves alone) and every OTHER key the old url/path-only
    # parser never inspected at all (`branch`, `update`, `shallow`,
    # `ignore`, `fetchRecurseSubmodules`, a renamed/reordered section, a
    # duplicate key, a stray comment, trailing whitespace -- anything).
    # The url/path parsing this replaces is no longer needed.
    OLD_GITMODULES="$MIGRATE_SCRATCH/gitmodules.old"
    STAGED_GITMODULES="$MIGRATE_SCRATCH/gitmodules.staged"
    if ! git -C "$WORKDIR" show "$LOCAL_HEAD:.gitmodules" >"$OLD_GITMODULES" 2>/dev/null; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "gitmodules-scan-failed: could not read pre-migration .gitmodules"
    fi
    if ! git -C "$WORKDIR" show :.gitmodules >"$STAGED_GITMODULES" 2>/dev/null; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "gitmodules-scan-failed: could not read staged .gitmodules"
    fi
    if ! cmp -s "$OLD_GITMODULES" "$STAGED_GITMODULES"; then
        GITMODULES_OLD_SHA=$(git -C "$WORKDIR" hash-object "$OLD_GITMODULES" 2>/dev/null)
        GITMODULES_NEW_SHA=$(git -C "$WORKDIR" hash-object "$STAGED_GITMODULES" 2>/dev/null)
        not_migrated_after_write "wiring" "out-of-scope-diff" "gitmodules-rewrite blob-changed old=${GITMODULES_OLD_SHA:-unknown} new=${GITMODULES_NEW_SHA:-unknown}"
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
    if ! check_review; then
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
    # T177 Round 15 (R14-B1, half 1): hooks disabled explicitly on the
    # commit itself, on top of the environment-scoped override above.
    if ! git -C "$WORKDIR" -c core.hooksPath=/dev/null \
        -c user.name=fastcycle-migrate \
        -c user.email=fastcycle-migrate@example.invalid \
        commit -q -m "$COMMIT_MSG" 2>&1; then
        not_migrated_after_write "commit" "local-git-error" "git-commit-failed"
    fi
    NEW_COMMIT=$(git -C "$WORKDIR" rev-parse HEAD)
    # T177 Round 3 finding 4, defence in depth at the push seam. What this
    # check ACTUALLY verifies (T177 Round 5, round-4 I5 -- the earlier
    # wording "the ONLY commit this migration may publish is its own"
    # overclaimed): that exactly ONE commit lies between the pre-migration
    # HEAD ($LOCAL_HEAD) and the migration commit -- i.e. that nothing
    # between preflight and push (in practice: the hook or the consumer's
    # gates) created an extra local commit. It does NOT re-measure what each
    # individual remote would receive; that property is established once,
    # before any write, by the preflight's collective unpublished-commit
    # check (zero commits of $LOCAL_HEAD outside every remote's copy of
    # $BRANCH), and this seam only confirms the local history did not grow
    # beyond the migration's own single commit since then.
    PUSH_SET_SIZE=$(git -C "$WORKDIR" rev-list --count "$LOCAL_HEAD..$NEW_COMMIT" 2>/dev/null)
    if [ "$PUSH_SET_SIZE" != "1" ]; then
        FULL="NOT-MIGRATED (push: out-of-scope-diff)"
        write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "" "" "" "" "refused-before-push: $PUSH_SET_SIZE commit(s) between pre-migration HEAD and the migration commit, expected exactly 1"
        echo "$FULL (refused before push: push set size=$PUSH_SET_SIZE, expected 1)"
        exit 1
    fi
    # T177 Round 15 (R14-B1, half 2 -- load-bearing): re-verify the FINAL
    # committed tree itself before the point of no return. See
    # verify_final_commit's own header for the invariant list.
    verify_final_commit

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
    # T177 Round 15 (R14-B1): hooks disabled explicitly on every push (a
    # `pre-push` hook could run its own side-channel push of other refs),
    # and the push sends the EXACT object verify_final_commit just
    # verified ("$NEW_COMMIT", by id) rather than whatever "$BRANCH"
    # happens to point at by the time each push runs -- a process moving
    # the local branch after verification can never change what is
    # published. Still a plain fast-forward update of refs/heads/$BRANCH
    # (no `+`, no force -- §11.4.113): a non-fast-forward is still
    # rejected by git itself.
    for r in $REMOTES; do
        if ! git -C "$WORKDIR" -c core.hooksPath=/dev/null push "$r" "$NEW_COMMIT":"refs/heads/$BRANCH" 2>"$MIGRATE_SCRATCH/migrate_push.err"; then
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
    #
    # T177 Round 9 (round-8 MINOR M1, honest-wording correction): THIS
    # branch is reached only when the LOCAL gitlink already equals
    # $NEW_SHA -- it is read-only with respect to push (it never calls
    # `git push`). The round-7 commit message's framing of "CA-025's
    # legitimate prior-migration-commit retry case" (above, in the I6
    # per-remote scope check) describes disjunct (b) of THAT check
    # correctly, but does NOT mean a genuine CA-025 retry -- a migration
    # commit that reached only ONE remote because another remote rejected
    # the push -- CONVERGES end-to-end on a re-run. Confirmed live
    # (round-8 review, scenario A3a): on retry, THIS branch reports
    # `NOT-MIGRATED (verify: verification-not-clean) ... tips-mismatch`
    # forever, because it never attempts to push the lagging remote(s)
    # up to the already-local, already-partially-published commit. This
    # is a PRE-EXISTING limitation, not introduced by round 7 -- stated
    # honestly here; the real fix (push to any remote still lagging
    # behind $LOCAL_HEAD when already at target) is a tracked §11.4.197
    # follow-up, out of this round's declared scope.
    #
    # T177 Round 5 (round-4 I3, DESIGN DECISION): data-model.md #13.3 makes
    # `review_ref` "required iff MIGRATED", and this path previously
    # emitted MIGRATED with review_ref OMITTED -- a direct conflict with the
    # data model, and `audit.py summary` could not tell an honest
    # already-at-target record from a hand-written MIGRATED claim that
    # simply dropped the field. Chosen resolution: ENFORCE the data model
    # (no amendment). The same bound CA-024 review gate runs here, BEFORE
    # any write to $WORKDIR (the submodule init below is the first one),
    # bound to (project, target=$NEW_SHA, base=$LOCAL_HEAD) exactly as on
    # the bump path. Rejected alternative: a self-declared
    # "already_at_target" exemption flag in the record -- `summary` reads
    # records off disk without trusting their author, so any record could
    # set the flag and skip the review requirement; a field whose presence
    # is unverifiable cannot be the thing that waives a verification. The
    # operational cost is one verify-only review of a no-op state, which is
    # cheap and honest.
    if ! check_review; then
        # T177 Round 6 (round-6 MINOR M1): re-running an already-MIGRATED
        # consumer with its ORIGINAL review (now stale -- its own base has
        # since moved to the migration commit) must NEVER downgrade the
        # existing on-disk MIGRATED record for this SAME project in place.
        # Reproduced live: a second run with the same (now-stale) review
        # overwrote outcome MIGRATED -> NOT-MIGRATED at the SAME --out path,
        # with no new write to $WORKDIR at all. A pre-existing MIGRATED
        # record for this exact project is left genuinely UNTOUCHED.
        #
        # T177 Round 9 (round-8 MINOR M4): the guard above was TOO BROAD --
        # it preserved the existing record whenever check_review failed for
        # ANY reason, including a FRESH, correctly-bound NO-GO for a
        # consumer whose HEAD has genuinely MOVED since the record was
        # written (further commits landed after the migration). A record
        # is "still authoritative for the current state" only when its OWN
        # `commit` field equals $LOCAL_HEAD (this run's pre-migration HEAD,
        # captured once at the top of this script, before any write) --
        # otherwise the record is STALE, not authoritative, and falls
        # through to the normal refusal below, which honestly overwrites
        # $OUT with a NOT-MIGRATED record reflecting the CURRENT state.
        #
        # T177 Round 9 (round-8 MINOR M4, contract nit): the refusal is now
        # ALSO echoed to stdout in the documented "NOT-MIGRATED (<step>:
        # <reason>) [detail]" shape (exit code 1 contractually means
        # "NOT-MIGRATED (reason in body)" -- `specs/004-fast-dev-cycles/
        # contracts/consumer-audit-and-migration.md`'s Exit codes clause)
        # -- $OUT itself is still left genuinely untouched; only the
        # printed line is new.
        if [ "$(read_out_field outcome)" = "MIGRATED" ] && [ "$(read_out_field project_id)" = "$PROJECT" ] \
            && [ "$(read_out_field commit)" = "$LOCAL_HEAD" ]; then
            echo "migrate.sh: review-no-go on the already-at-target path, but $OUT already holds a MIGRATED record for $PROJECT still bound to the current HEAD $LOCAL_HEAD -- left UNTOUCHED (re-run with a FRESH review bound to the migration commit to re-verify)" >&2
            echo "NOT-MIGRATED (review: review-no-go) [stale-review-preserved-existing-migrated-record-left-untouched]"
            exit 1
        fi
        not_migrated "review" "review-no-go" "already-at-target-verify-only-path-still-requires-a-bound-GO-review"
    fi
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
