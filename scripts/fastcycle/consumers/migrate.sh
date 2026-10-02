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
# --- T177 ROUND 21 ARCHITECTURE (R20-B1 remediation) -----------------
#
# CONTINUATION.md ADDENDUM 128 (round-20 independent review): round 19's
# own hand-written commit parser (the since-REMOVED `GIT_VERIFY` module)
# disagreed with git's real commit-header parsing -- a commit carrying an
# extra `parent`/`tree` header line placed AFTER `committer` (an opaque
# trailer to real git, which only reads parent lines CONTIGUOUS with
# `tree`, but was picked up by GIT_VERIFY's naive whole-header scan) made
# the per-commit walk (`check_remote_commits`) see an EMPTY diff for a
# commit that genuinely touched out-of-scope product code. Reproduced
# live, both shapes (decoy parent, decoy tree): rc=0, MIGRATED, a real
# remote received unreviewed product-code history. Round 17's tool
# (`2645dc8`) refused the same fixtures correctly -- round 19 introduced
# the regression, not inherited it.
#
# The fix, per the round-20 reviewer's own explicit recommendation
# ("instead of a round-21 patch ... build the commit in a fresh, tool-
# owned bare repository"), is architectural, not a parser patch: the
# migration commit is now built and verified ENTIRELY INSIDE AN ISOLATED,
# TOOL-OWNED, FRESHLY-CREATED BARE REPOSITORY (`$FC_BARE` below) that is
# NEVER derived from, or diffed against, $WORKDIR's own local git object
# store, history, or branch ref at all:
#
#   1. $FC_BARE is created fresh (`git init --bare`, no consumer config,
#      no hooks, `transfer.fsckObjects=true`) for every migration attempt.
#   2. Every configured remote's OWN CURRENT tip for $BRANCH is fetched,
#      by URL, directly into $FC_BARE (`fc_publish.py fetch_sweep`) -- a
#      real `git fetch`, which git's own `index-pack` RE-HASHES every
#      object it receives, so object integrity comes from git's protocol,
#      never a re-implementation. This single sweep replaces: the BEHIND
#      check (now against the upstream remote's own freshly-fetched tip,
#      never $WORKDIR's locally-cached remote-tracking ref), the
#      "is $LOCAL_HEAD published anywhere" preflight gate, AND the whole
#      removed per-remote content/tree/commit-walk machinery
#      (`check_remote_scope`/`check_remote_commits`/`GIT_VERIFY`).
#   3. The new tree is built on a PRIVATE INDEX (`GIT_INDEX_FILE`) seeded
#      from the TRUSTED, freshly-fetched $LOCAL_HEAD tree (read from
#      WHICHEVER remote's tip exactly equals $LOCAL_HEAD -- confirmed, not
#      assumed): the constitution gitlink is staged directly; every OTHER
#      allow-listed changed path (the hook's/gates' own output) is staged
#      by reading its CURRENT BYTES OFF $WORKDIR's FILESYSTEM (never
#      through a git object read of $WORKDIR -- there is no "tampered
#      loose object" question for a plain file read) and writing a fresh
#      blob into $FC_BARE's own object store (`fc_publish.py harvest`,
#      with the SAME symlink-target-safety and gitlink-boundary checks
#      the prior design enforced, now applied directly during ingestion).
#   4. The commit is created with `git commit-tree -p $LOCAL_HEAD` and
#      pushed FROM $FC_BARE -- never from $WORKDIR -- to every remote
#      whose OWN current tip is CONFIRMED (fetch_sweep, re-checked fresh
#      immediately before each push) to equal $LOCAL_HEAD EXACTLY (never
#      merely "an ancestor of" -- see fc_publish.py's own header comment
#      for why only exact equality is safe). A remote whose tip differs
#      is skipped for this migration (recorded as a push failure, CA-025
#      "a rejection ... remaining remotes proceed"), never "caught up"
#      with partial scoped content -- the exact feature whose safety
#      guarantee depended on the now-removed per-commit walk.
#
# $WORKDIR's own local branch ref, HEAD, and object store are THEREFORE
# NEVER consulted to decide what gets published, and are never themselves
# pushed anywhere -- an unpublished local commit in $WORKDIR's history
# (however many, however they got there) cannot reach a push by
# construction, not because something scanned for and caught it. Most of
# the prior enumeration layers this replaced (GIT_VERIFY's whole commit/
# tree re-hash walk, the per-remote tree-diff/per-commit-walk composition,
# the net-zero-history special case) are consequently removed entirely --
# every remaining git read in this tool operates either on $FC_BARE
# (trustworthy by construction: nothing but this tool's own `git fetch`/
# `hash-object -w`/`commit-tree` calls ever writes to it) or on $WORKDIR's
# plain FILESYSTEM (no object-store trust question at all).
#
# Steps (DEC-25, as re-sequenced by the above): 1 preflight (CA-020,
# including the fetch-sweep) 2 backup (CA-021, §9.2) 3 fetch (folded into
# the sweep) 4 gitlink-bump target resolution (unchanged: read from the
# consumer's own .gitmodules constitution url via `git ls-remote`; a
# consumer already at the resolved target skips straight to step 9) 5
# post_update_hook.sh + the consumer's own gates (best-effort, unchanged
# discovery) 6 review (CA-024) 7 build + commit in $FC_BARE 8 push from
# $FC_BARE to every remote whose tip exactly matches $LOCAL_HEAD 9
# recursive verify twice (CA-026), after syncing $WORKDIR to the new
# commit.
#
# Data-change honesty (T177 Round 1 I1): a refusal BEFORE any write to
# $WORKDIR (steps 1-4, and the submodule-advance sub-step that fails
# before the submodule's own checkout is ever touched) records
# data_change=NONE, genuinely accurate. A refusal AFTER $WORKDIR's
# constitution submodule checkout has been advanced to the target commit
# (step 5 onward) first attempts a full restore of that submodule checkout
# back to the pre-migration SHA, then RE-MEASURES the real dirty state and
# reports it honestly -- NONE only when the restore genuinely left nothing
# behind, a non-empty residue listed otherwise. A push failure never rolls
# back anything in $WORKDIR (there was never anything to roll back there
# in the first place -- the commit was built and lives in $FC_BARE, not
# $WORKDIR) -- its data_change instead names which remote(s)
# succeeded/failed via the additive `push_results` field.
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

# T177 Round 21 (research-derived, docs/research/git_verification_
# architecture_20261002/FINDINGS.md -- a parallel independent review of
# this exact architecture while it was being built): Gap 1 [LIVE-
# reproduced]. `git init --bare` WITHOUT `--template=` copies the
# TEMPLATE DIRECTORY (from `GIT_TEMPLATE_DIR` or `init.templateDir`) into
# the new repository, including a `config` and an `objects/info/
# alternates`; git ALSO honours an inherited `GIT_ALTERNATE_OBJECT_
# DIRECTORIES`/`GIT_OBJECT_DIRECTORY`. With a forged alternate present
# (an object whose ON-DISK BYTES belong to a DIFFERENT commit, copied to
# live at the EXPECTED commit's own object-store path -- the R18-B1
# tampered-object-store class, generalised from $WORKDIR to $FC_BARE), a
# `git fetch` into $FC_BARE transfers ZERO objects (git believes it
# already has them, via the alternate), exits rc=0, and sets FETCH_HEAD
# to the exact EXPECTED sha -- while every subsequent READ (`git show`,
# `cat-file`) silently resolves through the alternate to the ATTACKER's
# content. `transfer.fsckObjects=true` cannot help, because nothing is
# actually TRANSFERRED for it to check. This defeats the core trust
# argument of the Round 21 architecture ("git's own fetch re-hashes
# every object it receives" -- true, but inapplicable to a no-op fetch).
#
# Closed here, globally, for every git process THIS script launches
# (never only $FC_BARE's own calls -- simpler, and a stray inherited
# value could otherwise still reach $FC_BARE through a sub-invocation
# this file does not control): every environment variable that could
# smuggle an alternate/template/foreign-namespace into ANY repository
# this tool touches is explicitly UNSET (never merely left at whatever
# the CALLER happened to export).
#
# `GIT_CONFIG_NOSYSTEM=1` and `GIT_PROTOCOL_FROM_USER=0` -- the
# research's OWN further-hardening suggestions -- were TRIED globally
# here and REVERTED (own-defect, found by this round's own regression
# run, never shipped): `GIT_PROTOCOL_FROM_USER=0` narrows the DEFAULT
# policy for "user"-category protocols (a bare local path) to refuse
# everywhere a call does not ALSO carry an explicit `-c protocol.
# file.allow=always` -- this tool's OWN step-9 call into
# `repo_verify.py` performs ITS OWN independent remote-reachability
# probes against the consumer's configured remotes, which this round
# does not (and should not) reach into and individually patch; set
# globally, it broke step 9 outright (measured: every golden-path
# fixture turned UNVERIFIED/rc=4). `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_
# SYSTEM` are therefore left SET (not forced to `/dev/null`) and
# `GIT_CONFIG_NOSYSTEM` is left UNSET too, for the identical reason --
# this tool does not control, and must not silently alter the git
# configuration environment of, every subprocess it launches (the
# consumer's own hook/gates scripts, and repo_verify.py). Gap 2 (the
# remote-URL-source concern GIT_PROTOCOL_FROM_USER=0 was meant to help
# narrow) stays explicitly OPEN per the dedicated comment at the
# remote-list derivation below, rather than a broad, under-tested
# global change that COULD have silently regressed this tool's OWN
# positive-evidence verification step. Auth-carrying variables a real
# push may legitimately need (`SSH_AUTH_SOCK`, `GIT_SSH_COMMAND`,
# `GIT_ASKPASS`, `GIT_PROXY_COMMAND`) remain untouched throughout, for
# the same class of reason.
for _fc_unset_var in \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_OBJECT_DIRECTORY \
    GIT_TEMPLATE_DIR \
    GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR \
    GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE GIT_NAMESPACE
do
    unset "$_fc_unset_var" 2>/dev/null || true
done
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
# writes -- INCLUDING, as of T177 Round 21, the whole isolated
# build-and-publish repository ($FC_BARE, below). A `trap`-driven cleanup
# on EVERY exit path (normal or refused) means no per-call-site `rm -f` is
# load-bearing any more.
MIGRATE_SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fastcycle_migrate_scratch.XXXXXX" 2>/dev/null)
if [ -z "$MIGRATE_SCRATCH" ] || [ ! -d "$MIGRATE_SCRATCH" ]; then
    echo "migrate.sh: could not create a scratch directory outside \$WORKDIR for transient tool output" >&2
    exit 4
fi
trap 'rm -rf "$MIGRATE_SCRATCH"' EXIT INT TERM

# T177 Round 21: fc_publish.py (fetch_sweep + harvest) -- see this file's
# own ROUND 21 ARCHITECTURE header comment above for the full design.
# Replaces GIT_VERIFY (removed in full: its per-commit-walk parser is
# exactly what ADDENDUM 128's R20-B1 exploited, and every read it used to
# protect is now either performed inside $FC_BARE, which is trustworthy by
# construction, or against $WORKDIR's plain filesystem, which has no
# object-store trust question at all).
FC_PUBLISH="$MIGRATE_SCRATCH/fc_publish.py"
cat >"$FC_PUBLISH" <<'FC_PUBLISH_PY_EOF'
#!/usr/bin/env python3
"""
fc_publish.py -- T177 Round 21 architectural fix for migrate.sh (R20-B1).

Replaces GIT_VERIFY's per-commit-walk/net-zero-check machinery (the
hand-written git parser that disagreed with git -- CONTINUATION.md
ADDENDUM 128) with the reviewer's recommended design: the migration
commit is built and verified in a tool-owned, freshly created, isolated
bare repository that is NEVER derived from -- or scope-checked against --
the consumer's own ($WORKDIR) local history at all. Local unpublished
history can therefore never reach a push, structurally, by construction,
not by scanning for it after the fact.

Two subcommands:

  fetch_sweep <bare> <branch> <local_head> <upstream_remote_name>
      Reads "<name> <url>" pairs, one per line, from stdin. For each,
      fetches <branch> from <url> into <bare> (a real `git fetch`, which
      re-hashes every object it receives -- integrity comes from git's
      own transport, never from a re-implementation) and records that
      remote's OWN current tip. Never reads $WORKDIR's local
      remote-tracking refs or local object store for this determination.
      Prints, to stdout:
        PUBLISHED <0|1>        -- does ANY remote's tip exactly equal
                                   <local_head>?
        BASE <name-or-empty>   -- the first remote with an exact-match
                                   tip (the trusted source to build the
                                   new commit's parent tree from).
        UPSTREAM_TIP <sha-or-empty>
        UPSTREAM_BEHIND <0|1>  -- is <local_head> a PROPER ancestor of
                                   the upstream remote's own fetched tip
                                   (i.e. is $WORKDIR behind it)?
        REMOTE <name> <tip-or-MISSING> <0|1-exact-match>
                                -- one line per configured remote; the
                                   0|1 is this remote's PUSH ELIGIBILITY
                                   (see harvest's honest boundary below).
      Exit 0 always (a remote that cannot be fetched is reported
      MISSING/0, never a crash -- the caller decides what that implies).

  harvest <bare> <workdir> <paths-file>
      <paths-file> lists paths (one per line) that $WORKDIR's own
      `git status --porcelain` reported changed, ALREADY filtered by the
      caller (migrate.sh's ca022_post_hook_path_ok, the ONE canonical
      allow-list definition -- T177 Round 19 M-1's own hard-won lesson:
      this module deliberately carries NO second copy of that policy,
      only content-safety logic). GIT_INDEX_FILE MUST already be set in
      the environment to a private index file seeded (by the caller, via
      `git read-tree`) from the trusted base tree, with the constitution
      gitlink entry already staged. For each listed path this reads the
      CURRENT bytes directly off $WORKDIR's FILESYSTEM (never through any
      git object read of $WORKDIR -- there is no "tampered loose object"
      question for a plain filesystem read), writes a blob into <bare>'s
      OWN object store via `git hash-object -w` (git re-hashes what it
      writes, same guarantee as the fetch above), and stages it into the
      private index. Absent-on-disk paths are staged as deletions. A
      symlink target that is absolute or escapes the repository, or a
      path that is itself an untracked nested git repository boundary
      (the R6-I2/R8/R9/R10 gitlink-smuggling shape -- git itself refuses
      to descend into such a directory for status/untracked enumeration,
      which this module detects directly rather than re-scanning a diff),
      is refused. Exit 0 and prints "harvest-ok" on success; on any
      refusal prints ONE line naming it and exits 3 (migrate.sh's own
      existing convention, matched for a drop-in refusal path).

Honest boundary (documented, not claimed covered): PUSH ELIGIBILITY
(fetch_sweep's REMOTE lines) requires the remote's CURRENT tip to equal
<local_head> EXACTLY -- not merely be an ancestor of it. A remote merely
lagging further behind is skipped (recorded as a push failure by the
caller, never attempted) rather than "caught up" with partial scoped
content, because doing so safely would require re-introducing exactly the
per-commit/tree content-scanning machinery this fix removes: if a remote's
tip is NOT $LOCAL_HEAD itself, pushing a commit built as a child of
$LOCAL_HEAD to it would require transmitting $LOCAL_HEAD's own ancestry
too (since the remote does not already have it), which could carry
intermediate out-of-scope history -- exactly the R14-I1/R20-B1 class of
leak. Requiring an EXACT match makes the only objects a successful push
ever transmits the new commit's own new objects, nothing from history.
CA-025 ("a rejection ... remaining remotes proceed") explicitly accepts a
per-remote push failure; this is a conservative, contract-compliant
simplification, not a silent narrowing.
"""
import os
import posixpath
import stat
import subprocess
import sys


def run(args, **kw):
    return subprocess.run(args, capture_output=True, **kw)


def fail(msg):
    print(msg)
    sys.exit(3)


def fetch_sweep(bare, branch, local_head, upstream_remote):
    pairs = []
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        if " " not in line:
            continue
        name, url = line.split(" ", 1)
        pairs.append((name, url))

    tips = {}
    exact = {}
    for name, url in pairs:
        f = run(
            [
                "git",
                "-C",
                bare,
                "-c",
                "protocol.file.allow=always",
                "fetch",
                "-q",
                "--no-tags",
                "--",
                url,
                branch,
            ]
        )
        if f.returncode != 0:
            tips[name] = ""
            exact[name] = False
            continue
        rp = run(["git", "-C", bare, "rev-parse", "FETCH_HEAD"])
        tip = rp.stdout.decode().strip() if rp.returncode == 0 and rp.stdout.strip() else ""
        tips[name] = tip
        exact[name] = bool(tip) and (tip == local_head)

    published = any(exact.values())
    base = ""
    for name, _ in pairs:
        if exact.get(name):
            base = name
            break

    upstream_tip = tips.get(upstream_remote, "") if upstream_remote else ""
    upstream_behind = False
    if upstream_tip and upstream_tip != local_head:
        anc = run(
            ["git", "-C", bare, "merge-base", "--is-ancestor", local_head, upstream_tip]
        )
        # local_head is a (proper) ancestor of upstream_tip => $WORKDIR is
        # genuinely BEHIND its own tracked upstream.
        upstream_behind = anc.returncode == 0

    print("PUBLISHED %d" % (1 if published else 0))
    print("BASE %s" % base)
    print("UPSTREAM_TIP %s" % upstream_tip)
    print("UPSTREAM_BEHIND %d" % (1 if upstream_behind else 0))
    for name, _ in pairs:
        print(
            "REMOTE %s %s %d"
            % (name, tips.get(name, "") or "MISSING", 1 if exact.get(name) else 0)
        )
    return 0


def harvest(bare, workdir, paths_file):
    if "GIT_INDEX_FILE" not in os.environ:
        fail("harvest-internal-error: GIT_INDEX_FILE not set by caller")
    with open(paths_file, "r", encoding="utf-8", errors="surrogateescape") as fh:
        paths = [l.rstrip("\n") for l in fh if l.strip()]
    for path in paths:
        full = os.path.join(workdir, path)
        if not os.path.lexists(full):
            rm = run(["git", "-C", bare, "update-index", "--force-remove", "--", path])
            if rm.returncode != 0:
                fail(
                    "harvest-remove-failed path=%s: %s"
                    % (path, rm.stderr.decode("utf-8", "replace"))
                )
            continue
        st = os.lstat(full)
        if stat.S_ISLNK(st.st_mode):
            target = os.readlink(full)
            if target.startswith("/"):
                fail("host-specific-symlink path=%s target-is-absolute" % path)
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
            if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
                fail("host-specific-symlink path=%s target-escapes-repository" % path)
            blob_in = target.encode("utf-8", "surrogateescape")
            mode = "120000"
        elif stat.S_ISDIR(st.st_mode):
            # `git status --porcelain --untracked-files=all` reports a
            # DIRECTORY as a leaf path (instead of descending into its
            # individual files) only when it is itself an untracked git
            # repository boundary -- git refuses to walk into one. This IS
            # the R6-I2/R8/R9/R10 gitlink-smuggling shape (a hook `git
            # init`s + commits inside an allow-listed directory), detected
            # directly here rather than via a secondary diff scan.
            fail("unexpected-gitlink path=%s (untracked nested git repository)" % path)
        elif stat.S_ISREG(st.st_mode):
            with open(full, "rb") as fh:
                blob_in = fh.read()
            mode = "100755" if (st.st_mode & stat.S_IXUSR) else "100644"
        else:
            fail("harvest-unsupported-file-type path=%s" % path)
        h = run(["git", "-C", bare, "hash-object", "-w", "-t", "blob", "--stdin"], input=blob_in)
        if h.returncode != 0:
            fail(
                "harvest-hash-object-failed path=%s: %s"
                % (path, h.stderr.decode("utf-8", "replace"))
            )
        blob_sha = h.stdout.decode().strip()
        upd = run(
            [
                "git",
                "-C",
                bare,
                "update-index",
                "--add",
                "--cacheinfo",
                "%s,%s,%s" % (mode, blob_sha, path),
            ]
        )
        if upd.returncode != 0:
            fail(
                "harvest-update-index-failed path=%s: %s"
                % (path, upd.stderr.decode("utf-8", "replace"))
            )
    print("harvest-ok")
    return 0


def main(argv):
    if len(argv) < 2:
        fail("usage: fc_publish.py <fetch_sweep|harvest> ...")
    cmd = argv[1]
    if cmd == "fetch_sweep":
        bare, branch, local_head, upstream_remote = argv[2], argv[3], argv[4], argv[5]
        return fetch_sweep(bare, branch, local_head, upstream_remote)
    if cmd == "harvest":
        bare, workdir, paths_file = argv[2], argv[3], argv[4]
        return harvest(bare, workdir, paths_file)
    fail("unknown-subcommand=%s" % cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
FC_PUBLISH_PY_EOF
if [ ! -s "$FC_PUBLISH" ]; then
    echo "migrate.sh: could not write the publish helper to scratch" >&2
    exit 4
fi

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
# (GIT_CONFIG_COUNT, git >= 2.31) so it reaches every git invocation THIS
# script launches (directly, or via the python helpers it runs) and
# overrides anything the hook writes into `.git/config`. T177 Round 21:
# since the migration commit itself is now built and pushed entirely from
# $FC_BARE -- a repository this tool creates fresh, with no consumer
# config and no hooks to begin with -- this environment-scoped override's
# remaining job is protecting this tool's OWN reads/writes of $WORKDIR
# (the hook/gates materialisation step's `git status` enumeration, the
# submodule-advance checkout) from a hostile `.git/config`/`core.hooksPath`
# $WORKDIR may already carry. The post-update hook and the consumer's own
# gates are run with the CALLER's original git environment restored
# (run_with_caller_git_env), never with this override -- they are the
# consumer's own processes, not this tool's.
#
# Scope, stated narrowly (T177 Round 17, R16-M1 -- the earlier wording
# "stops side-channel pushes" overclaimed): this stops git's OWN hook
# mechanism (`.git/hooks/*`, `core.hooksPath`) and a configured fsmonitor
# from running during this tool's own git calls against $WORKDIR, and
# forces `commit.gpgSign`/`push.gpgSign`/`tag.gpgSign` false with the three
# `gpg.*program` keys pointed at `false` (defense in depth, now mostly
# moot for the publish path itself since $FC_BARE never carries a
# consumer-set `gpg.program` to begin with). It does NOT neutralise every
# repository-config-driven executable in $WORKDIR: the push-transport
# executables (`core.sshCommand`, `credential.helper`,
# `remote.<r>.receivepack`, `url.*.insteadOf` -> `ext::`) are left alone
# -- none of those is reached by this tool's OWN reads of $WORKDIR any
# more (filesystem reads only, never a git-object read of $WORKDIR), and
# the push transport itself now only ever runs against $FC_BARE's OWN
# remote configuration, set up by this tool from the consumer's URLs,
# never from $WORKDIR's own potentially-adversarial `.git/config`.
#
# T177 Round 22 (R21-I1, live-reproduced): clean/smudge/process filter
# drivers (`.gitattributes` / `.git/info/attributes` + `filter.<name>.*`)
# were PREVIOUSLY an un-neutralised gap in this scope -- unlike hooks,
# filters have no single global off-switch (`core.hooksPath=/dev/null`'s
# own analogue does not exist for `filter.*`), and this tool's submodule-
# advance materialisation (fc_checkout_submodule_filtered below) DOES
# invoke them: a `filter.<name>.smudge` driver configured purely in the
# constitution submodule's own LOCAL, untracked `.git/config` (paired
# with a matching local `.gitattributes`/`.git/info/attributes` entry --
# no tracked-content change needed) fired an arbitrary command during
# this tool's own `checkout`/`submodule update --init` of that checkout,
# confirmed by direct, minimal, from-scratch reproduction (fires with no
# override; does not fire once the discovered driver key is overridden).
# It did NOT corrupt the published commit (the gitlink write below is an
# unconditional `cacheinfo` write, never derived from this checkout's
# filtered tree -- CA-019..028 held throughout) but it WAS genuine code
# execution on the host running migrate.sh, squarely inside this file's
# own stated threat model ("don't trust $WORKDIR's own git config").
# CLOSED by fc_checkout_submodule_filtered() (defined below, alongside
# restore_submodule()): every `filter.*.{smudge,clean,process}` key the
# submodule's OWN local config ACTUALLY declares is discovered (never a
# name guessed or assumed in advance -- the attacker picks it) and
# overridden, for the scope of that one invocation only, to the literal,
# harmless, no-shell-metacharacter identity command `cat` via the SAME
# GIT_CONFIG_COUNT/KEY_n/VALUE_n environment-override mechanism already
# used above (env-based config overrides always outrank a repository's
# own local config file, confirmed by direct experiment, and -- unlike a
# `-c key=value` flag built via POSIX-sh string interpolation of an
# attacker-chosen git-config subsection name, which may legally contain
# spaces/dots/arbitrary bytes -- never risks re-opening an injection
# class of its own). Applied identically everywhere this tool
# materializes that submodule's own working tree: restore_submodule()'s
# rollback, all three `submodule update --init` call sites (a submodule
# already initialised but drifted from its parent-recorded SHA is ALSO
# live-reproduced to invoke its own local filter config internally, the
# SAME vector at a different call shape), and both other direct
# `checkout` calls (the step-5 advance-to-$NEW_SHA and the step-9
# best-effort post-publish re-sync).
FC_CALLER_GCC_SET=0
[ -n "${GIT_CONFIG_COUNT+x}" ] && FC_CALLER_GCC_SET=1
FC_CALLER_GCC=${GIT_CONFIG_COUNT:-0}
case "$FC_CALLER_GCC" in
    ''|*[!0-9]*) echo "migrate.sh: inherited GIT_CONFIG_COUNT=$FC_CALLER_GCC is not a number -- refusing to guess how to extend it" >&2; exit 4 ;;
esac
FC_CALLER_NRO_SET=0
[ -n "${GIT_NO_REPLACE_OBJECTS+x}" ] && FC_CALLER_NRO_SET=1
FC_CALLER_NRO=${GIT_NO_REPLACE_OBJECTS:-}
FC_CALLER_GRAFT_SET=0
[ -n "${GIT_GRAFT_FILE+x}" ] && FC_CALLER_GRAFT_SET=1
FC_CALLER_GRAFT=${GIT_GRAFT_FILE:-}
# T177 Round 19 (M-3): a caller-inherited GIT_CONFIG_PARAMETERS can
# OUTRANK every override `fc_gcc_add` installs below for the SAME key on
# any git call that does not also pass its own explicit `-c` for that
# key (empirically confirmed: `GIT_CONFIG_PARAMETERS` wins over
# `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` for an
# identically-named key, on real git). Captured here exactly like
# GIT_NO_REPLACE_OBJECTS/GIT_GRAFT_FILE above and restored in
# run_with_caller_git_env below; cleared (never silently trusted) for the
# duration of every git call THIS tool makes.
FC_CALLER_GCP_SET=0
[ -n "${GIT_CONFIG_PARAMETERS+x}" ] && FC_CALLER_GCP_SET=1
FC_CALLER_GCP=${GIT_CONFIG_PARAMETERS:-}
FC_GCC_N=$FC_CALLER_GCC
fc_gcc_add() {
    # $1=key $2=value -> appended at index FC_GCC_N (>= the caller's own
    # count, so it is read after, and wins over, every caller entry).
    eval "GIT_CONFIG_KEY_$FC_GCC_N=\$1; GIT_CONFIG_VALUE_$FC_GCC_N=\$2; export GIT_CONFIG_KEY_$FC_GCC_N GIT_CONFIG_VALUE_$FC_GCC_N"
    FC_GCC_N=$((FC_GCC_N + 1))
}
fc_gcc_add core.hooksPath /dev/null
fc_gcc_add core.fsmonitor false
fc_gcc_add core.useReplaceRefs false
fc_gcc_add core.commitGraph false
fc_gcc_add commit.gpgSign false
fc_gcc_add push.gpgSign false
fc_gcc_add tag.gpgSign false
fc_gcc_add gpg.program false
fc_gcc_add gpg.ssh.program false
fc_gcc_add gpg.x509.program false
# GIT_GRAFT_FILE=/dev/null (below) makes git believe a graft file is in use and
# print its deprecation hint to stderr on EVERY command -- which the step-1
# `status --porcelain=v1 2>&1` dirty check then reads as a dirty tree.
fc_gcc_add advice.graftFileDeprecated false
GIT_CONFIG_COUNT=$FC_GCC_N; export GIT_CONFIG_COUNT
GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS
GIT_GRAFT_FILE=/dev/null; export GIT_GRAFT_FILE
unset GIT_CONFIG_PARAMETERS
run_with_caller_git_env() {
    # Runs "$@" in a subshell with the caller's ORIGINAL GIT_CONFIG_COUNT,
    # GIT_NO_REPLACE_OBJECTS, GIT_GRAFT_FILE and GIT_CONFIG_PARAMETERS
    # restored (extra GIT_CONFIG_KEY_<n>/VALUE_<n> beyond the count are
    # ignored by git) -- the post-update hook and the consumer's own
    # gates are the CONSUMER's own processes, not this tool's, so they
    # run under the environment the caller actually had, never this
    # tool's own protective overrides.
    (
        if [ "$FC_CALLER_GCC_SET" -eq 1 ]; then
            GIT_CONFIG_COUNT=$FC_CALLER_GCC; export GIT_CONFIG_COUNT
        else
            unset GIT_CONFIG_COUNT
        fi
        if [ "$FC_CALLER_NRO_SET" -eq 1 ]; then
            GIT_NO_REPLACE_OBJECTS=$FC_CALLER_NRO; export GIT_NO_REPLACE_OBJECTS
        else
            unset GIT_NO_REPLACE_OBJECTS
        fi
        if [ "$FC_CALLER_GRAFT_SET" -eq 1 ]; then
            GIT_GRAFT_FILE=$FC_CALLER_GRAFT; export GIT_GRAFT_FILE
        else
            unset GIT_GRAFT_FILE
        fi
        if [ "$FC_CALLER_GCP_SET" -eq 1 ]; then
            GIT_CONFIG_PARAMETERS=$FC_CALLER_GCP; export GIT_CONFIG_PARAMETERS
        else
            unset GIT_CONFIG_PARAMETERS
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
    # BEFORE any write to $WORKDIR has happened -- "NONE" is genuinely
    # correct there. Once a write has begun, use
    # not_migrated_after_write() instead (T177 Round 1 I1).
    if [ "$reason" = "dirty-local" ]; then
        FULL="NOT-MIGRATED (dirty-local)"
    else
        FULL="NOT-MIGRATED ($step: $reason)"
    fi
    write_out "NOT-MIGRATED" "$FULL" "" "NONE" "" "" "" "" "$detail"
    if [ -n "$detail" ]; then echo "$FULL [$detail]"; else echo "$FULL"; fi
    exit 1
}

# T177 Round 22 (R21-I1 fix -- see migrate.sh's own "T177 Round 22
# (R21-I1, live-reproduced)" header comment above for the full forensic
# rationale): every place this tool materializes the constitution
# submodule's OWN working tree against a target SHA MUST go through this
# ONE discovery+override core, never a bare `git checkout`/`submodule
# update --init` -- a bare call trusts that checkout's own invocation to
# NEVER invoke a hostile local `filter.<name>.{smudge,clean,process}`
# driver, which a tampered $WORKDIR can configure with no tracked-content
# change at all. fc_submodule_filter_exec: $1 = the directory whose OWN
# LOCAL git config is inspected for filter drivers (always
# $WORKDIR/constitution -- NEVER $WORKDIR itself, a different repository
# with no such drivers in scope here); "$@" (after shift) = the full
# `git ...` command line to run (its own `-C` target may legitimately
# differ from $1 -- `submodule update --init` below is invoked
# `-C $WORKDIR`, not `-C $WORKDIR/constitution`, even though it is
# $WORKDIR/constitution's local config being neutralised for that call).
# Discovery+override-building runs in python3, never POSIX-sh string
# interpolation, because the ATTACKER controls the driver NAME -- a git
# config subsection that may legally contain spaces/dots/arbitrary bytes
# -- and feeding that name through sh word-splitting/quoting to build a
# `-c key=value` argument would reopen exactly the injection class this
# fix exists to close; python3's subprocess argv lists and
# GIT_CONFIG_KEY_n/VALUE_n *values* (never shell tokens, never env-var
# NAMES) carry it safely however it is spelled. A submodule directory
# that is not yet a git repository at all (a fresh consumer clone whose
# submodule has never been initialised) is handled by discovering
# nothing (`git ... config --local` fails with "not a git repository",
# a non-zero exit this function treats identically to "no drivers
# configured") -- the wrapped command then runs with zero added
# overrides, never worse than before this fix existed; this matches
# direct experiment showing first-init itself is not exposed (there is
# no pre-existing local config for an attacker to have tampered with
# yet). Exits with the wrapped git command's own exit status.
fc_submodule_filter_exec() {
    _fcfe_dir=$1
    shift
    # FC_GCC_N (never GIT_CONFIG_COUNT directly -- shellcheck SC2030/2031,
    # this file's own run_with_caller_git_env() reassigns GIT_CONFIG_COUNT
    # inside a subshell lexically earlier in the file, which would make a
    # direct read here look potentially stale even though that subshell's
    # change can never actually escape it) already equals the script's
    # real, final, top-level GIT_CONFIG_COUNT (set once at line ~664 and
    # never reassigned anywhere else at this scope).
    python3 - "$_fcfe_dir" "$FC_GCC_N" "$@" <<'PYEOF'
import os
import subprocess
import sys

sub_dir, base_n = sys.argv[1], int(sys.argv[2])
cmd = sys.argv[3:]

keys = []
disc = subprocess.run(
    ["git", "-C", sub_dir, "config", "--local", "--null",
     "--get-regexp", r"^filter\..*\.(clean|smudge|process)$"],
    capture_output=True,
)
if disc.returncode == 0 and disc.stdout:
    for record in disc.stdout.split(b"\x00"):
        if not record:
            continue
        key, _, _value = record.partition(b"\n")
        if key and key not in keys:
            keys.append(key)

env = dict(os.environ)
n = base_n
for key in keys:
    env["GIT_CONFIG_KEY_%d" % n] = key.decode("utf-8", "surrogateescape")
    env["GIT_CONFIG_VALUE_%d" % n] = "cat"
    n += 1
env["GIT_CONFIG_COUNT"] = str(n)

sys.exit(subprocess.run(cmd, env=env).returncode)
PYEOF
}

# fc_checkout_submodule_filtered: $1 = submodule working dir (also the
# `git -C` target), $2 = target SHA. The filter-safe replacement for a
# bare `git -C "$1" checkout -q "$2"` against the constitution
# submodule's own nested checkout.
fc_checkout_submodule_filtered() {
    fc_submodule_filter_exec "$1" git -C "$1" -c advice.detachedHead=false checkout -q "$2"
}

# fc_submodule_update_init_filtered: $1 = parent working dir (the
# `git -C` target `submodule update` itself runs against), $2 =
# submodule working dir (whose own local config is inspected for filter
# drivers), $3 = submodule name as recorded in .gitmodules. An
# ALREADY-initialised submodule whose working tree has drifted from the
# PARENT's recorded SHA is live-reproduced to invoke its own local
# filter config internally during `submodule update --init`'s own
# re-checkout -- the SAME vector as a direct `checkout`, at a different
# call shape, closed here identically.
fc_submodule_update_init_filtered() {
    fc_submodule_filter_exec "$2" git -C "$1" -c protocol.file.allow=always -c init.templateDir= submodule update --init "$3"
}

# T177 Round 21: the ONLY write this tool ever makes to $WORKDIR's own git
# state before a confirmed-safe publish is advancing the ALREADY-CHECKED-
# OUT constitution SUBMODULE's own nested repo to the target SHA (so the
# hook/gates can run against real target-commit content) -- the PARENT
# $WORKDIR's own index/HEAD/branch ref is never touched until step 9's
# post-publish sync (which only ever applies a commit this tool has
# already fully built and verified in $FC_BARE). restore_submodule()
# reverts that one sub-step back to the pre-migration SHA (replaces the
# prior restore_staged_gitlink(), which undid a PARENT-index staging this
# design no longer performs). T177 Round 22: routed through
# fc_checkout_submodule_filtered (see above) rather than a bare
# `checkout`, same as every other submodule-materializing call site.
restore_submodule() {
    [ -d "$WORKDIR/constitution/.git" ] || [ -f "$WORKDIR/constitution/.git" ] || return 0
    [ -n "${OLD_SHA:-}" ] || return 0
    fc_checkout_submodule_filtered "$WORKDIR/constitution" "$OLD_SHA" 2>/dev/null || true
}

not_migrated_after_write() {
    step=$1; reason=$2; detail=${3:-}
    restore_submodule
    RESIDUE=$(git -C "$WORKDIR" status --porcelain=v1 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    FULL="NOT-MIGRATED ($step: $reason)"
    write_out "NOT-MIGRATED" "$FULL" "" "${RESIDUE:-NONE}" "" "" "" "" "$detail"
    if [ -n "$detail" ]; then echo "$FULL [$detail]"; else echo "$FULL"; fi
    if [ -n "$RESIDUE" ]; then
        echo "migrate.sh: WARNING -- $WORKDIR has real residue after this refusal that could not be fully restored: $RESIDUE" >&2
    fi
    exit 1
}

# T177 Round 2 R2-B2/R2-I1 fix: every write_out call downstream of step 5
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

# Step 6 review check (CA-024), shared by the bump path and the
# already-at-target path. Sets REVIEW_REF_ID on GO; returns 1
# (REVIEW_REF_ID empty) for an absent, unbound, stale, non-zero-finding or
# wrong-tier record. Reads $REVIEW_REF/$PROJECT/$NEW_SHA/$LOCAL_HEAD at
# CALL time.
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

# T177 Round 15 (R14-B1): the symlink (mode 120000) and gitlink (mode
# 160000) scanners -- kept, unchanged in form, as a cheap BELT-AND-BRACES
# re-check of the FULL final published diff (T177 Round 21: now pointed at
# $FC_BARE's own trustworthy diff-tree output, never at $WORKDIR's staged
# index -- harvest()/fc_publish.py already enforces the same two
# invariants during ingestion; this is the second, independent pass over
# the ACTUAL resulting tree object, belt-and-braces against a bug in
# harvest() itself). Each reads the raw diff from the file named by $1
# (a `--raw -z` stream); prints a violation line (or nothing) and exits
# non-zero only when the scan itself could not run. $2 names which repo
# to `cat-file` blobs from (T177 Round 21: generalised from the prior
# hardcoded $WORKDIR). The embedded Python source below is intentionally
# single-quoted (it must NOT be shell-expanded): it is raw Python, not an
# interpolated string.
# shellcheck disable=SC2016
scan_symlinks_raw() {
    python3 -c '
import os, posixpath, subprocess, sys
repo = sys.argv[1]
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
    cat = subprocess.run(["git", "-C", repo, "cat-file", "blob", blob],
                         capture_output=True)
    if cat.returncode != 0:
        print("integrity-verification-failed: unreadable-object type=blob oid=%s" % blob)
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
' "$2" <"$1"
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
# output. EVERY consumer of the list calls THIS one definition (T177
# Round 19 M-1's own hard-won lesson: an inline copy drifts). Returns 0
# iff path $1 is allowed.
ca022_post_hook_path_ok() {
    case "$1" in
        constitution|.gitmodules|.claude/*|scripts/hooks/*|config/fastcycle/*|.mcp.json|skills/*) return 0 ;;
    esac
    return 1
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

BRANCH=$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
LOCAL_HEAD=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null)
# T177 Round 5 (round-4 MINOR, detached HEAD): `rev-parse --abbrev-ref HEAD`
# prints the literal "HEAD" on a detached checkout -- refused here, before
# any write, since there is no branch to fast-forward at all.
if [ "$BRANCH" = "HEAD" ] || [ -z "$BRANCH" ]; then
    not_migrated "preflight" "divergent-branches" "detached-HEAD-no-branch-to-fast-forward"
fi

# T177 Round 21 (replaces: `git fetch --all` + $UPSTREAM/$UPSTREAM_HEAD via
# $WORKDIR's local remote-tracking refs + PUBLISHED_REFS/PUBLISHED_REF_LIST/
# UNPUBLISHED + the ENTIRE check_remote_scope/check_remote_commits per-
# remote content/tree/commit-walk, R20-B1's exact vulnerable surface): ONE
# fetch sweep, by URL, directly into the isolated $FC_BARE, never touching
# $WORKDIR's own object store or remote-tracking refs for any of this.
#
# T177 Round 10 (R10-M2 MINOR, honestly carried forward): a checkout with
# NO configured upstream (`@{u}` unset) resolves UPSTREAM to the empty
# string -- the BEHIND check below is then skipped for it (§11.4.101's
# safe-reversible default applied to an unresolvable trust signal; a real
# consumer checkout produced by a normal `git clone` always has `@{u}` set).
UPSTREAM=$(git -C "$WORKDIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
UPSTREAM_REMOTE_NAME=""
if [ -n "$UPSTREAM" ]; then
    UPSTREAM_REMOTE_NAME=${UPSTREAM%%/*}
fi

FC_BARE="$MIGRATE_SCRATCH/publish.git"
# `--template=` (empty): per Gap 1 above, `git init --bare` WITHOUT this
# flag copies the template directory -- including a possible `config`
# and `objects/info/alternates` -- into the new repository; an empty
# `--template=` disables that copy entirely (confirmed by direct
# experiment: with it, a template directory's own alternates file never
# reaches the new repo; without it, the file is copied verbatim).
if ! git init --bare --template= -q -b "$BRANCH" "$FC_BARE" 2>/dev/null; then
    echo "migrate.sh: could not create the isolated publish repository" >&2
    exit 4
fi
git -C "$FC_BARE" config transfer.fsckObjects true

# Gap 1, continued: assert $FC_BARE genuinely has NO alternates file --
# right after creation (defense against a template dir the `--template=`
# flag somehow failed to suppress on a given git build) and again after
# every fetch below (defense against a fetch protocol path writing one,
# which real git does not do today but this refuses rather than assume).
fc_bare_assert_no_alternates() {
    if [ -e "$FC_BARE/objects/info/alternates" ]; then
        echo "migrate.sh: the isolated publish repository unexpectedly has an objects/info/alternates file -- refusing rather than trust object resolution that could be silently satisfied by a foreign store" >&2
        not_migrated "preflight" "unreachable" "fc-bare-has-alternates-file"
    fi
}
fc_bare_assert_no_alternates

# T177 Round 21 (docs/research/git_verification_architecture_20261002/
# FINDINGS.md Gap 2, OPEN / TRACKED, lower severity than Gap 1 and NOT
# fully closed this round -- honestly disclosed rather than silently
# left unaddressed): these remote names/URLs come from $WORKDIR's OWN
# `git remote`/`remote get-url` -- i.e. from $WORKDIR's `.git/config`,
# which this tool does not otherwise treat as a trusted input (CA-022's
# whole premise is that the CONTENT $WORKDIR carries cannot be trusted).
# A remote entry an attacker added there (e.g. a prior hook run, or
# direct filesystem access) is therefore fetched FROM by fetch_sweep
# below, which runs the TARGET's own `upload-pack` -- a documented,
# CVE-dense git attack surface (git(1) SECURITY: "the surface area for
# attack against upload-pack is large"; CVE-2024-32004 is this class).
# This is NOT a NEW exposure Round 21 introduces for the PUSH side (CA-025
# already, from this tool's very first version, read "every configured
# remote" from this SAME $WORKDIR git config for push targets -- that
# trust boundary is baked into the contract itself) -- it IS new for the
# FETCH side (Round 21 is the first version that ever fetches FROM a
# configured remote, not merely pushes to or ls-remotes one). NOT
# mitigated this round via a global `GIT_PROTOCOL_FROM_USER=0` (tried and
# reverted -- see this file's own env-sanitization header comment above
# for why: it broke step 9's independent repo_verify.py probes). The
# ONLY mitigation actually shipped this round is that `protocol.file.
# allow=always` is passed EXPLICITLY, per call, only where genuinely
# needed (never a blanket repository-wide config) -- the REMOTE LIST
# ITSELF still comes from $WORKDIR, not from an independently
# trusted source (the research's own recommendation: a verifier-owned
# manifest, e.g. this tool's own --config file, once it carries a
# per-project remote-URL allow-list -- $CFG carries no such schema today
# and introducing one touches every existing fixture; out of this
# round's scope). A full fix is a tracked §11.4.197 follow-up. Content
# integrity is NOT affected by this gap (every object this tool trusts is
# still independently verified: exact-tip-match, the Gap-1 fsck/
# alternates checks above, and plumbing-only reads for R20-B1's class) --
# the residual risk is upload-pack RCE exposure and a possible fake
# "published" signal from a malicious remote, narrower than R20-B1.
REMOTE_NAMES=$(git -C "$WORKDIR" remote 2>/dev/null)
if [ -z "$REMOTE_NAMES" ]; then
    not_migrated "preflight" "divergent-branches" "no-remotes-configured"
fi
REMOTES_LIST="$MIGRATE_SCRATCH/remotes.txt"
: > "$REMOTES_LIST"
for r in $REMOTE_NAMES; do
    RURL=$(git -C "$WORKDIR" remote get-url "$r" 2>/dev/null)
    [ -n "$RURL" ] && printf '%s %s\n' "$r" "$RURL" >> "$REMOTES_LIST"
done

FC_SWEEP=$(python3 "$FC_PUBLISH" fetch_sweep "$FC_BARE" "$BRANCH" "$LOCAL_HEAD" "$UPSTREAM_REMOTE_NAME" <"$REMOTES_LIST" 2>&1)
FC_SWEEP_RC=$?
if [ "$FC_SWEEP_RC" -ne 0 ]; then
    echo "migrate.sh: fetch sweep failed unexpectedly (rc=$FC_SWEEP_RC): $FC_SWEEP" >&2
    exit 4
fi
fc_bare_assert_no_alternates
FC_PUBLISHED=0
FC_BASE_REMOTE=""
FC_UPSTREAM_BEHIND=0
# shellcheck disable=SC2034  # FC_REMOTE_<name>_EXACT consumed indirectly via `eval`/case below
OLD_IFS=$IFS
IFS='
'
for _line in $FC_SWEEP; do
    case "$_line" in
        "PUBLISHED "*) FC_PUBLISHED=${_line#PUBLISHED } ;;
        "BASE "*) FC_BASE_REMOTE=${_line#BASE } ;;
        "UPSTREAM_BEHIND "*) FC_UPSTREAM_BEHIND=${_line#UPSTREAM_BEHIND } ;;
    esac
done
IFS=$OLD_IFS

if [ "$FC_UPSTREAM_BEHIND" = "1" ]; then
    not_migrated "preflight" "divergent-branches" "local-behind-$UPSTREAM"
fi
if [ "$FC_PUBLISHED" != "1" ] || [ -z "$FC_BASE_REMOTE" ]; then
    not_migrated "preflight" "divergent-branches" "local-$BRANCH-has-no-published-counterpart-on-any-remote"
fi
# Defense in depth: the fetched BASE remote's tip must genuinely equal
# $LOCAL_HEAD byte-for-byte (fetch_sweep's own PUBLISHED/BASE derivation
# already requires this; re-asserted here directly against $FC_BARE's own
# object store, the trustworthy one, rather than trusted blindly from the
# sweep's text output).
FC_BASE_TIP=$(git -C "$FC_BARE" rev-parse -q --verify "refs/heads/$BRANCH" 2>/dev/null)
# After the LAST fetch in the sweep, refs/heads/$BRANCH in $FC_BARE holds
# whichever remote was fetched last -- re-fetch the confirmed BASE remote
# explicitly, by name, to be certain FETCH_HEAD/the branch ref reflects
# exactly that remote (never an artifact of fetch ordering).
FC_BASE_URL=$(awk -v n="$FC_BASE_REMOTE" '$1==n{ $1=""; sub(/^ /,""); print; exit }' "$REMOTES_LIST")
if [ -z "$FC_BASE_URL" ]; then
    not_migrated "preflight" "divergent-branches" "base-remote-url-unresolvable"
fi
if ! git -C "$FC_BARE" -c protocol.file.allow=always fetch -q --no-tags -- "$FC_BASE_URL" "$BRANCH" 2>"$MIGRATE_SCRATCH/base_fetch.err"; then
    not_migrated "preflight" "unreachable" "base-remote-$FC_BASE_REMOTE-refetch-failed"
fi
fc_bare_assert_no_alternates
FC_BASE_TIP=$(git -C "$FC_BARE" rev-parse -q --verify FETCH_HEAD 2>/dev/null)
if [ "$FC_BASE_TIP" != "$LOCAL_HEAD" ]; then
    not_migrated "preflight" "divergent-branches" "base-remote-$FC_BASE_REMOTE-tip-$FC_BASE_TIP-does-not-match-local-head-$LOCAL_HEAD"
fi
git -C "$FC_BARE" update-ref "refs/heads/$BRANCH" "$FC_BASE_TIP"
# Gap 1 (docs/research/git_verification_architecture_20261002/
# FINDINGS.md §6.2/§9): `fsck --strict --no-dangling` is REQUIRED to pass
# before this freshly-fetched base is trusted for ANYTHING further --
# [LIVE]-confirmed by that research to genuinely catch the forged-
# alternate class (rc=1 "hash-path mismatch" when attacked, rc=0 on a
# clean fetch) precisely because fsck walks and re-hashes every object
# reachable from every ref, INCLUDING ones silently satisfied via an
# alternate rather than genuinely transferred -- the one check in this
# file that notices a no-op fetch happened at all. It is NOT a defence
# for the R20-B1 decoy-header class (that research's own §6.3/§9(4):
# "`fsck --strict` -> rc=0" on a decoy-header commit) -- this tool's
# plumbing-only reads (`rev-parse <c>^{tree}`, `ls-tree -z`, `cat-file
# blob`, never a hand-parsed `cat-file -p`) remain the actual defence for
# that class; the two checks cover two DIFFERENT gaps, neither subsumes
# the other.
if ! git -C "$FC_BARE" fsck --strict --no-dangling >"$MIGRATE_SCRATCH/fc_bare_fsck.log" 2>&1; then
    not_migrated "preflight" "unreachable" "fc-bare-fsck-failed-see-$MIGRATE_SCRATCH/fc_bare_fsck.log"
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
# same backing repo. Hardlinking $WORKDIR/.git there copies only that
# ~100-byte pointer file, never the real object database -- a FALSE
# SENSE of §9.2 protection while backing up nothing. Per §11.4.201's
# conservative-safe-default-on-an-unresolvable-signal: refuse honestly
# (as a backup failure) rather than pretend to protect a shape this
# mechanism cannot actually protect.
#
# The resolved real git-dir (`--absolute-git-dir`) is used as the
# hardlink SOURCE for every checkout shape, not the raw "$WORKDIR/.git"
# path -- for a plain checkout this resolves to exactly $WORKDIR/.git
# (verified identical), so the already-working case is behavior-
# preserving; for a `.git`-as-file checkout whose real git-dir is NOT
# shared with any sibling (e.g. an ordinary git submodule nested as a
# consumer's own workdir), the resolved path is a real, self-contained
# directory and the SAME §9.2 hardlink protection applies correctly.
# Only the TRUE worktree shape (--git-dir differs from --git-common-dir
# once both are resolved to absolute paths) is refused.
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
# T177 Round 3 (minor m4): a bare ".fastcycle_migrate_backup_${STAMP}" name
# collides when two migrations under the same parent start in the same
# second -- a unique per-run container (mktemp -d, same volume as
# $WORKDIR so the hardlinks stay valid) closes the window.
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

# --- Step 3 already done above (the fetch sweep, read-only w.r.t. $WORKDIR).

# --- Step 4: gitlink-bump target resolution -- resolve the consumer's OWN
# constitution submodule url from .gitmodules and discover its latest
# commit. Resolved by PATH, never by .gitmodules SECTION NAME (a real
# consumer may name the section differently from this repo's own
# `[submodule "constitution"]`) -- find whichever section's `path` value
# equals the expected constitution checkout path, then read THAT
# section's url.
GITMODULES="$WORKDIR/.gitmodules"
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
# -c protocol.file.allow=always: the SAME override every other call
# touching this SAME trusted (it is THIS consumer's own declared
# constitution URL) local-path-capable URL already carries, for
# consistency and to remain correct if a future round narrows the
# default local-path policy.
NEW_SHA=$(git -c protocol.file.allow=always ls-remote "$SUB_URL" HEAD 2>/dev/null | awk '{print $1}')
if [ -z "$NEW_SHA" ]; then
    NEW_SHA=$(git -c protocol.file.allow=always ls-remote "$SUB_URL" refs/heads/main 2>/dev/null | awk '{print $1}')
fi
if [ -z "$NEW_SHA" ]; then
    not_migrated "gitlink-bump" "unreachable" "git-ls-remote-resolved-no-target-commit"
fi
OLD_SHA=$(git -C "$WORKDIR" ls-tree HEAD constitution 2>/dev/null | awk '{print $3}')
# T177 Round 1 I4 fix: a consumer already at the migration target has
# NOTHING to bump/materialize/review/commit/push -- ALREADY_AT_TARGET
# short-circuits steps 5-8 entirely and proceeds directly to step 9.
ALREADY_AT_TARGET=0
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
    ALREADY_AT_TARGET=1
    echo "migrate.sh: $PROJECT already at $NEW_SHA -- no bump needed, proceeding to verify only"
fi

if [ "$ALREADY_AT_TARGET" -ne 1 ]; then
    # --- Step 5: materialize the new content + run post_update_hook.sh /
    # the consumer's own gates, best-effort (CA-023): a hook/gate genuinely
    # absent at the target commit is not a failure (nothing to check); a
    # hook/gate PRESENT and failing IS.
    #
    # T177 Round 21: the constitution SUBMODULE's own nested checkout is
    # advanced to $NEW_SHA directly (never via a PARENT-index staging
    # step -- $WORKDIR's own top-level index/HEAD is untouched until
    # step 9's post-publish sync). `submodule update --init` first
    # ensures the submodule is checked out at all (a fresh consumer clone
    # may never have initialised it), at whatever the PARENT's own
    # unchanged index still records ($OLD_SHA); a direct `fetch` +
    # `checkout` inside the submodule's own nested repo then moves it to
    # $NEW_SHA. `-c protocol.file.allow=always`: modern git refuses a bare
    # local-path submodule URL by default (CVE-2022-39253 hardening);
    # safe here because the URL comes from THIS SAME consumer's own
    # .gitmodules.
    # T177 Round 21 (found while building this round's own Gap-1 regression
    # fixture, J44, not reported by either the round-20 review or FINDINGS.md
    # -- the SAME inheritance mechanism as Gap 1, on a DIFFERENT call site):
    # `submodule update --init` performs its own, fresh `git clone`/`git
    # init` for `$WORKDIR/constitution`'s nested repo the FIRST time a
    # consumer checkout initialises it -- and that init is NOT covered by
    # $FC_BARE's own `--template=`/`fc_bare_assert_no_alternates` defenses
    # (this submodule checkout is a wholly separate repository). [LIVE]-
    # reproduced: with a hostile `init.templateDir` set in the migrating
    # host's global/system git config (the SAME vector as Gap 1 --
    # GIT_CONFIG_GLOBAL/SYSTEM are deliberately left untouched, see this
    # file's own env-sanitization header comment), `submodule update
    # --init` copies the template's `objects/info/alternates` into
    # `$WORKDIR/.git/modules/constitution/objects/info/alternates`,
    # confirmed to apply to every subsequent git operation against that
    # checkout. `-c init.templateDir=` (the submodule-update analogue of
    # `--template=`) is confirmed, directly, to defeat it (no alternates
    # file is created under the same hostile config). Applied to all three
    # `submodule update --init` call sites in this file for consistency,
    # plus an explicit post-update alternates-presence assert here (the
    # one call site whose output feeds a real publish) mirroring
    # `fc_bare_assert_no_alternates` -- belt-and-braces, never trust a
    # single layer.
    if ! fc_submodule_update_init_filtered "$WORKDIR" "$WORKDIR/constitution" constitution >"$MIGRATE_SCRATCH/migrate_submodule_update.err" 2>&1; then
        not_migrated_after_write "fetch" "unreachable"
    fi
    SUB_GITDIR=$(git -C "$WORKDIR/constitution" rev-parse --absolute-git-dir 2>/dev/null)
    if [ -n "$SUB_GITDIR" ] && [ -e "$SUB_GITDIR/objects/info/alternates" ]; then
        echo "migrate.sh: the constitution submodule's own checkout unexpectedly has an objects/info/alternates file -- refusing rather than trust object resolution that could be silently satisfied by a foreign store" >&2
        not_migrated_after_write "wiring" "out-of-scope-diff" "constitution-submodule-has-alternates-file"
    fi
    if ! git -C "$WORKDIR/constitution" -c protocol.file.allow=always fetch -q origin "$NEW_SHA" >"$MIGRATE_SCRATCH/migrate_submodule_fetch.err" 2>&1 \
        && ! git -C "$WORKDIR/constitution" -c protocol.file.allow=always fetch -q origin >"$MIGRATE_SCRATCH/migrate_submodule_fetch.err" 2>&1; then
        not_migrated_after_write "fetch" "unreachable" "constitution-submodule-fetch-failed"
    fi
    if ! fc_checkout_submodule_filtered "$WORKDIR/constitution" "$NEW_SHA" >>"$MIGRATE_SCRATCH/migrate_submodule_fetch.err" 2>&1; then
        not_migrated_after_write "fetch" "unreachable" "constitution-submodule-checkout-failed"
    fi

    HOOK="$WORKDIR/constitution/scripts/post_update_hook.sh"
    if [ -f "$HOOK" ]; then
        # T177 Round 1 B2 fix: the hook MUST run against the CONSUMER
        # ($WORKDIR), never the caller's own ambient cwd.
        # T177 Round 3 finding 9: the REAL post_update_hook.sh is a BASH
        # script -- invoked with bash explicitly, never sh.
        # sh -c '...' receives WORKDIR/HOOK as its OWN $1/$2 -- deliberately not expanded by this shell
        # shellcheck disable=SC2016
        if ! run_with_caller_git_env sh -c 'cd "$1" && PROJECT_ROOT="$1" CONST_DIR="$1/constitution" bash "$2"' fc-hook "$WORKDIR" "$HOOK" >"$MIGRATE_SCRATCH/migrate_hook.log" 2>&1; then
            not_migrated_after_write "post-update-hook" "consumer-gates-red"
        fi
    fi

    # The consumer's OWN gates (CA-023, distinct from post_update_hook.sh
    # itself). Best-effort discovery: a CLAUDE.md line "Consumer gates:
    # <repo-relative-script>" names a script to run; a genuinely absent
    # marker line is "nothing to check" (CA-023's own documented
    # best-effort policy), never a failure.
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
        # sh -c '...' receives WORKDIR/GATES_SCRIPT as its OWN $1/$2 -- deliberately not expanded by this shell
        # shellcheck disable=SC2016
        if ! run_with_caller_git_env sh -c 'cd "$1" && sh "$2"' fc-gates "$WORKDIR" "$GATES_SCRIPT" >"$MIGRATE_SCRATCH/migrate_gates.log" 2>&1; then
            not_migrated_after_write "consumer-gates" "consumer-gates-red"
        fi
    fi

    # T177 Round 21 (own-defect, found while reconciling the regression
    # suite against this round's new architecture -- I3): a hook/gate
    # that runs `git commit` directly in $WORKDIR's OWN top-level
    # checkout (as distinct from the constitution SUBMODULE's own nested
    # checkout, which this tool legitimately advances) produces a commit
    # this design would otherwise NEVER NOTICE -- the build below reads
    # $LOCAL_HEAD (captured once, before the hook ran) and the CURRENT
    # FILESYSTEM content of allow-listed paths, never $WORKDIR's own
    # commit history, so such a hook-made commit is harmless to publish
    # (it can never reach $FC_BARE) but would otherwise be SILENTLY
    # DISCARDED by the post-publish sync's hard-reset-style tree move with no refusal
    # at all -- a hook behaving this unexpectedly is a sign something is
    # wrong and MUST halt the migration, not be silently swallowed
    # (§11.4.201 conservative-safe default). Refused here, before any
    # further write, naming the unexpected commit.
    WORKDIR_HEAD_AFTER_HOOK=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null)
    if [ "$WORKDIR_HEAD_AFTER_HOOK" != "$LOCAL_HEAD" ]; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "hook-or-gates-created-a-local-commit-in-\$WORKDIR-itself new-head=$WORKDIR_HEAD_AFTER_HOOK expected=$LOCAL_HEAD"
    fi

    # T177 Round 21: enumerate the hook's/gates' own OUTPUT in $WORKDIR
    # via a fresh `git status --porcelain` read (T177 Round 2 R2-B2's
    # original concern -- anything the hook/gates step creates/modifies
    # MUST be checked against the allow-list -- still applies; the
    # MECHANISM that then ingests each allow-listed path has moved to
    # $FC_BARE/fc_publish.py's harvest(), which reads these bytes directly
    # off $WORKDIR's filesystem). The "constitution" line is skipped here
    # (its target SHA is asserted directly below, unconditionally,
    # independent of whether `git status` happens to report it -- T177
    # Round 10's R10-I1 "positive invariant, not a diff-filter special
    # case" lesson, now applied to the committed-SHA check itself).
    POST_HOOK_STATUS=$(git -C "$WORKDIR" status --porcelain=v1 --untracked-files=all 2>&1)
    POST_HOOK_STATUS_RC=$?
    if [ "$POST_HOOK_STATUS_RC" -ne 0 ]; then
        not_migrated_after_write "wiring" "out-of-scope-diff" "status-scan-failed"
    fi
    HARVEST_PATHS="$MIGRATE_SCRATCH/harvest_paths.txt"
    : > "$HARVEST_PATHS"
    if [ -n "$POST_HOOK_STATUS" ]; then
        OLD_IFS=$IFS
        IFS='
'
        for line in $POST_HOOK_STATUS; do
            [ -z "$line" ] && continue
            f=${line#???}
            case "$f" in
                '"'*) IFS=$OLD_IFS; not_migrated_after_write "wiring" "out-of-scope-diff" "unsupported-path-encoding=$f" ;;
            esac
            [ "$f" = "constitution" ] && continue
            if ! ca022_post_hook_path_ok "$f"; then
                IFS=$OLD_IFS
                not_migrated_after_write "wiring" "out-of-scope-diff" "path=$f"
            fi
            if [ "$f" = ".gitmodules" ]; then
                IFS=$OLD_IFS
                not_migrated_after_write "wiring" "out-of-scope-diff" "path=.gitmodules (no hook may modify this file; it is never part of the publishable diff)"
            fi
            printf '%s\n' "$f" >> "$HARVEST_PATHS"
        done
        IFS=$OLD_IFS
    fi

    # --- Step 6: review (CA-024) -- absent or non-GO => review-no-go.
    #
    # T177 Round 1 I6 fix: the GO verdict must be BOUND to THIS EXACT
    # migration attempt -- project_id/target_commit/consumer_base_commit
    # (the checkout's own pre-migration $LOCAL_HEAD) must all match
    # exactly; a stale/foreign record is treated exactly like no record
    # at all. T177 Round 2 R2-I3: also requires zero findings + tier=opus
    # + effort=xhigh (the constitution §11.4.209/§11.4.231 pin -- no
    # fallback model/effort).
    if ! check_review; then
        not_migrated_after_write "review" "review-no-go"
    fi

    # --- Step 7: build + commit in $FC_BARE (T177 Round 21 -- see this
    # file's own ROUND 21 ARCHITECTURE header comment for the full design
    # and the R20-B1 vulnerability this replaces).
    PRIV_INDEX="$MIGRATE_SCRATCH/priv_index"
    rm -f "$PRIV_INDEX"
    if ! git -C "$FC_BARE" read-tree "$LOCAL_HEAD^{tree}" --index-output="$PRIV_INDEX" 2>"$MIGRATE_SCRATCH/readtree.err"; then
        not_migrated_after_write "commit" "local-git-error" "read-tree-failed"
    fi
    GIT_INDEX_FILE="$PRIV_INDEX"; export GIT_INDEX_FILE
    if ! git -C "$FC_BARE" update-index --add --cacheinfo "160000,$NEW_SHA,constitution" 2>"$MIGRATE_SCRATCH/updindex.err"; then
        unset GIT_INDEX_FILE
        not_migrated_after_write "commit" "local-git-error" "git-update-index-failed"
    fi
    FC_HARVEST=$(python3 "$FC_PUBLISH" harvest "$FC_BARE" "$WORKDIR" "$HARVEST_PATHS" 2>&1)
    FC_HARVEST_RC=$?
    if [ "$FC_HARVEST_RC" -ne 0 ]; then
        unset GIT_INDEX_FILE
        not_migrated_after_write "wiring" "out-of-scope-diff" "$FC_HARVEST"
    fi
    NEW_TREE=$(git -C "$FC_BARE" write-tree 2>"$MIGRATE_SCRATCH/writetree.err")
    WRITE_TREE_RC=$?
    unset GIT_INDEX_FILE
    if [ "$WRITE_TREE_RC" -ne 0 ] || [ -z "$NEW_TREE" ]; then
        not_migrated_after_write "commit" "local-git-error" "write-tree-failed"
    fi

    # Belt-and-braces structural re-verification of the candidate TREE
    # (against $FC_BARE, trustworthy by construction) BEFORE it is ever
    # turned into a commit -- mirrors verify_final_commit's own invariant
    # list, now checked pre-commit rather than post-commit-then-refuse
    # (no local commit object is ever even created for a tree that fails
    # this), and via plain git reads (no GIT_VERIFY re-hash wrapper
    # needed: nothing but this tool's own writes ever reaches $FC_BARE's
    # object store).
    refuse_candidate_tree() {
        FULL="NOT-MIGRATED (push: out-of-scope-diff)"
        write_out "NOT-MIGRATED" "$FULL" "" "$(current_data_change)" "" "" "" "" "refused-before-commit: candidate-tree-verification: $1"
        echo "$FULL [refused-before-commit: candidate-tree-verification: $1]"
        exit 1
    }
    CT_CONST_LINE=$(git -C "$FC_BARE" ls-tree "$NEW_TREE" constitution 2>/dev/null)
    CT_CONST_MODE=$(echo "$CT_CONST_LINE" | awk '{print $1}')
    CT_CONST_OID=$(echo "$CT_CONST_LINE" | awk '{print $3}')
    if [ -z "$CT_CONST_LINE" ] || [ "$CT_CONST_MODE" != "160000" ] || [ "$CT_CONST_OID" != "$NEW_SHA" ]; then
        restore_submodule
        refuse_candidate_tree "candidate-constitution-entry=[${CT_CONST_LINE:-absent}] expected-target=$NEW_SHA"
    fi
    CT_GM_OLD=$(git -C "$FC_BARE" rev-parse -q --verify "$LOCAL_HEAD:.gitmodules" 2>/dev/null)
    CT_GM_NEW=$(git -C "$FC_BARE" rev-parse -q --verify "$NEW_TREE:.gitmodules" 2>/dev/null)
    if [ -z "$CT_GM_OLD" ] || [ "$CT_GM_OLD" != "$CT_GM_NEW" ]; then
        restore_submodule
        refuse_candidate_tree "candidate-gitmodules-blob-changed old=${CT_GM_OLD:-unreadable} new=${CT_GM_NEW:-absent}"
    fi
    CT_RAW="$MIGRATE_SCRATCH/candidate_tree_diff.raw"
    # T177 Round 21 (own-defect, found while reconciling the regression
    # suite -- I4): `-r` is REQUIRED here -- without it `diff-tree` is
    # NON-recursive and reports a brand-new subdirectory (e.g. the hook's
    # own `skills/`) as a single top-level "tree" entry named "skills",
    # never descending to its real leaf path "skills/example.md"; the
    # allow-list check below then sees the bare directory name "skills"
    # (which, unlike "skills/*", `ca022_post_hook_path_ok` correctly does
    # NOT match) and wrongly refuses a genuinely in-scope migration.
    if ! git -C "$FC_BARE" diff-tree --raw -r --no-renames -z "$LOCAL_HEAD" "$NEW_TREE" >"$CT_RAW" 2>"$MIGRATE_SCRATCH/candidate_tree_diff.err"; then
        restore_submodule
        refuse_candidate_tree "candidate-raw-diff-failed"
    fi
    OLD_IFS=$IFS
    IFS='
'
    CT_PATHS=$(python3 -c '
import sys
data = open(sys.argv[1], "rb").read().split(b"\0")
i = 0
while i + 1 < len(data):
    meta, path = data[i], data[i + 1]
    i += 2
    if meta.startswith(b":"):
        print(path.decode("utf-8", "surrogateescape"))
' "$CT_RAW")
    for f in $CT_PATHS; do
        if ! ca022_post_hook_path_ok "$f"; then
            IFS=$OLD_IFS
            restore_submodule
            refuse_candidate_tree "candidate-out-of-scope-path=$f"
        fi
    done
    IFS=$OLD_IFS
    CT_GITLINK=$(scan_gitlinks_raw "$CT_RAW" 2>/dev/null) || { restore_submodule; refuse_candidate_tree "${CT_GITLINK:-candidate-gitlink-scan-failed}"; }
    [ -z "$CT_GITLINK" ] || { restore_submodule; refuse_candidate_tree "candidate-$CT_GITLINK"; }
    CT_SYMLINK=$(scan_symlinks_raw "$CT_RAW" "$FC_BARE" 2>/dev/null) || { restore_submodule; refuse_candidate_tree "${CT_SYMLINK:-candidate-symlink-scan-failed}"; }
    [ -z "$CT_SYMLINK" ] || { restore_submodule; refuse_candidate_tree "candidate-$CT_SYMLINK"; }

    COMMIT_MSG="chore(fastcycle): bump constitution pointer to $NEW_SHA (SpecKit-004 US8 migration)"
    PLAIN_GIT_OK=0
    if [ -f "$WORKDIR/CLAUDE.md" ] && grep -q 'Commit wrapper: none (plain git permitted)' "$WORKDIR/CLAUDE.md" 2>/dev/null; then
        PLAIN_GIT_OK=1
    fi
    if [ "$PLAIN_GIT_OK" -ne 1 ]; then
        not_migrated_after_write "commit" "no-commit-wrapper"
    fi
    NEW_COMMIT=$(printf '%s' "$COMMIT_MSG" | git -C "$FC_BARE" -c user.name=fastcycle-migrate -c user.email=fastcycle-migrate@example.invalid commit-tree "$NEW_TREE" -p "$LOCAL_HEAD" 2>"$MIGRATE_SCRATCH/committree.err")
    COMMIT_TREE_RC=$?
    if [ "$COMMIT_TREE_RC" -ne 0 ] || [ -z "$NEW_COMMIT" ]; then
        not_migrated_after_write "commit" "local-git-error" "commit-tree-failed"
    fi
    git -C "$FC_BARE" update-ref "refs/heads/$BRANCH" "$NEW_COMMIT"

    # --- Step 8: push from $FC_BARE (never from $WORKDIR) to every remote
    # whose OWN CURRENT tip is CONFIRMED, fresh, to equal $LOCAL_HEAD
    # EXACTLY (fc_publish.py's own header comment has the full honest
    # boundary for why only exact equality is safe here). T177 Round 1 I2:
    # EVERY configured remote is attempted, even after an earlier one is
    # skipped/rejects (CA-025 "remaining remotes... proceed"). The commit
    # already exists (in $FC_BARE) at this point and is NEVER rolled back
    # on a push failure (CA-019) -- there was nothing in $WORKDIR to roll
    # back in the first place.
    PUSH_FAILURES=""
    PUSH_OK_REMOTES=""
    OLD_IFS=$IFS
    IFS='
'
    # shellcheck disable=SC2013  # intentional: IFS is set to newline-only
    # immediately above, so command substitution word-splitting here IS
    # line-splitting, not word-splitting; REMOTES_LIST lines never embed
    # control characters this needs to survive.
    for _rline in $(cat "$REMOTES_LIST")
    do
        r=${_rline%% *}
        url=${_rline#* }
        RTIP=$(git -C "$FC_BARE" -c protocol.file.allow=always ls-remote "$url" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
        if [ "$RTIP" != "$LOCAL_HEAD" ]; then
            REASON="remote-base-mismatch"
            [ -z "$RTIP" ] && REASON="remote-rejected"
            PUSH_FAILURES="$PUSH_FAILURES $r:$REASON"
            continue
        fi
        if ! git -C "$FC_BARE" -c protocol.file.allow=always push "$url" "$NEW_COMMIT":"refs/heads/$BRANCH" 2>"$MIGRATE_SCRATCH/migrate_push_$r.err"; then
            REASON="remote-rejected"
            if grep -qi 'non-fast-forward\|fetch first' "$MIGRATE_SCRATCH/migrate_push_$r.err" 2>/dev/null; then
                REASON="non-fast-forward"
            fi
            PUSH_FAILURES="$PUSH_FAILURES $r:$REASON"
        else
            PUSH_OK_REMOTES="$PUSH_OK_REMOTES $r"
        fi
    done
    IFS=$OLD_IFS
    if [ -n "$PUSH_FAILURES" ]; then
        REASON="remote-rejected"
        case "$PUSH_FAILURES" in
            *non-fast-forward*) REASON="non-fast-forward" ;;
            *remote-base-mismatch*) REASON="non-fast-forward" ;;
        esac
        PR=""
        for r in $PUSH_OK_REMOTES; do PR="$PR,$r:pushed"; done
        for pf in $PUSH_FAILURES; do PR="$PR,$pf"; done
        PR=${PR#,}
        # T177 Round 21 (own-defect, found while RED-testing this round's
        # own fix): a PARTIAL push failure must leave $WORKDIR itself
        # exactly as it was before this run (CA-019's "never rolls back
        # the already-made commit" is about the PUSHED commit, which
        # genuinely stays published on whichever remotes DID accept it --
        # it says nothing about $WORKDIR's own checkout, which under this
        # design was never advanced to begin with). Without this, the
        # constitution SUBMODULE's own checkout -- advanced to $NEW_SHA in
        # step 5 so the hook could run against real target content -- is
        # left dirty relative to $WORKDIR's UNCHANGED parent index (still
        # $OLD_SHA, since a partial failure never reaches the post-push
        # sync below), self-locking every subsequent invocation on
        # NOT-MIGRATED (dirty-local) with no way to retry (reproduced live
        # while testing the J35-class decoy-parent fixture: the FIRST
        # push-partial-failure run left $WORKDIR permanently dirty).
        # current_data_change() is measured AFTER the restore so a
        # genuinely-REMAINING residue (anything the hook/gates wrote that
        # is not just the submodule pointer) is still reported honestly,
        # never silently hidden.
        restore_submodule
        FULL="NOT-MIGRATED (push: $REASON)"
        write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)" "$PR"
        echo "$FULL (per-remote:$PUSH_FAILURES; pushed ok to:$PUSH_OK_REMOTES)"
        exit 1
    fi

    # T177 Round 21: now that the build is fully verified and published,
    # sync $WORKDIR to the real result -- fetch the exact new objects from
    # $FC_BARE (a local path fetch; these are OUR OWN freshly built,
    # already-verified objects, content-addressed, safe) and move
    # $WORKDIR's own branch ref + index to match, so step 9's
    # repo_verify.py (which inspects the REAL on-disk consumer tree,
    # recursively) sees a consistent, real, materialized result.
    #
    # C-006 (this file's own contract clause, C4's static safety check)
    # forbids a hard reset-style invocation anywhere in this tool's
    # source, regardless of context. `git read-tree -u -m HEAD` -- the
    # non-destructive plumbing primitive `git checkout` is itself built
    # on -- was tried first and found UNSAFE FOR THIS PURPOSE by direct
    # experiment: a single-tree `-m` merge REFUSES whenever the target
    # tree wants to create a path that ALREADY EXISTS as an untracked
    # file in the working tree ("Untracked working tree file ... would be
    # overwritten by merge"), EVEN WHEN that file's content is already
    # byte-identical to what the merge would write -- exactly the shape
    # every allow-listed hook/gate artefact is in at this exact point
    # (harvest() read these same bytes off disk moments ago; they are
    # untracked in $WORKDIR's index precisely because this tool never
    # stages anything there before the build). No separate "is this
    # genuinely identical" check is needed, because there is nothing left
    # to check out: $WORKDIR's FILESYSTEM content is already exactly
    # right (it is the data harvest() read FROM), so only the INDEX needs
    # to catch up, via `git add` -- which, unlike `read-tree -u`, stages
    # an untracked file at its current on-disk content with no
    # already-exists conflict of any kind. The constitution gitlink is
    # re-asserted directly (defense in depth, independent of whatever the
    # submodule's own nested checkout happens to be at this exact moment)
    # rather than relying on `git add constitution` to read it back.
    if ! git -C "$WORKDIR" -c protocol.file.allow=always fetch -q "$FC_BARE" "$NEW_COMMIT" >"$MIGRATE_SCRATCH/migrate_sync_fetch.err" 2>&1; then
        echo "migrate.sh: WARNING -- published commit $NEW_COMMIT could not be fetched back into \$WORKDIR for sync; the push itself already succeeded on every configured remote" >&2
    fi
    git -C "$WORKDIR" update-ref "refs/heads/$BRANCH" "$NEW_COMMIT" 2>/dev/null
    fc_checkout_submodule_filtered "$WORKDIR/constitution" "$NEW_SHA" 2>/dev/null || true
    git -C "$WORKDIR" update-index --add --cacheinfo "160000,$NEW_SHA,constitution" 2>/dev/null
    if [ -s "$HARVEST_PATHS" ]; then
        while IFS= read -r _hp; do
            [ -z "$_hp" ] && continue
            git -C "$WORKDIR" add -A -- "$_hp" 2>/dev/null
        done <"$HARVEST_PATHS"
    fi
    SYNC_RESIDUE=$(current_data_change)
    if [ -n "$SYNC_RESIDUE" ]; then
        echo "migrate.sh: WARNING -- \$WORKDIR still shows local changes after syncing to the published commit $NEW_COMMIT ($SYNC_RESIDUE); the push itself already succeeded on every configured remote -- re-run 'git checkout $BRANCH' manually in \$WORKDIR" >&2
    fi
    fc_submodule_update_init_filtered "$WORKDIR" "$WORKDIR/constitution" constitution >/dev/null 2>&1 || true
else
    # Already at target: still ensure the submodule is genuinely checked
    # out before verify (CA-026) runs -- a consumer whose gitlink is
    # already correct but whose submodule directory was never initialised
    # would otherwise make step 9's read-only cross-check spuriously
    # report SUBMODULE_UNINITIALISED. Idempotent + a no-op for an
    # already-initialised submodule. Read-only with respect to push (it
    # never calls `git push`).
    #
    # T177 Round 5 (round-4 I3, DESIGN DECISION): data-model.md #13.3 makes
    # `review_ref` "required iff MIGRATED" -- the SAME bound CA-024 review
    # gate runs here, before any write to $WORKDIR, bound to
    # (project, target=$NEW_SHA, base=$LOCAL_HEAD) exactly as on the bump
    # path.
    if ! check_review; then
        # T177 Round 6 (round-6 MINOR M1): re-running an already-MIGRATED
        # consumer with its ORIGINAL review (now stale) must NEVER
        # downgrade the existing on-disk MIGRATED record for this SAME
        # project in place. T177 Round 9 (round-8 MINOR M4): only when
        # that record's OWN `commit` field still equals $LOCAL_HEAD
        # (otherwise it is genuinely stale, not authoritative, and falls
        # through to an honest overwrite).
        if [ "$(read_out_field outcome)" = "MIGRATED" ] && [ "$(read_out_field project_id)" = "$PROJECT" ] \
            && [ "$(read_out_field commit)" = "$LOCAL_HEAD" ]; then
            echo "migrate.sh: review-no-go on the already-at-target path, but $OUT already holds a MIGRATED record for $PROJECT still bound to the current HEAD $LOCAL_HEAD -- left UNTOUCHED (re-run with a FRESH review bound to the migration commit to re-verify)" >&2
            echo "NOT-MIGRATED (review: review-no-go) [stale-review-preserved-existing-migrated-record-left-untouched]"
            exit 1
        fi
        not_migrated "review" "review-no-go" "already-at-target-verify-only-path-still-requires-a-bound-GO-review"
    fi
    fc_submodule_update_init_filtered "$WORKDIR" "$WORKDIR/constitution" constitution >/dev/null 2>&1 || true
    NEW_COMMIT="$LOCAL_HEAD"
fi

# --- Step 9: recursive verify TWICE (CA-026) -- MIGRATED only when BOTH
# runs report CLEAN with an identical body_hash. T177 Round 1 B3 fix: the
# prior code wrote MIGRATED straight after push with NO double-verify at
# all. This runs for BOTH the normal push path AND the already-at-target
# path (verify is a read-only cross-check of the CURRENT state either way).
if [ ! -f "$VERIFY_TOOL" ]; then
    FULL="NOT-MIGRATED (verify: verification-not-clean)"
    write_out "NOT-MIGRATED" "$FULL" "$NEW_COMMIT" "$(current_data_change)"
    echo "$FULL ($VERIFY_TOOL not found -- CA-026 cannot run)"
    exit 1
fi
# Observer-decontamination (§11.4.201(10)): the verify output/log files
# MUST live OUTSIDE $WORKDIR.
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
# green and tips equal". Confirms EVERY configured remote's OWN ref, read
# back via `ls-remote`, genuinely equals the local NEW_COMMIT (a remote's
# own tip may legitimately be unreadable for reasons unrelated to this
# migration -- an empty ls-remote result is skipped, never treated as a
# mismatch).
TIPS_OK=1
TIPS_DETAIL=""
for r in $(git -C "$WORKDIR" remote 2>/dev/null); do
    RTIP=$(git -C "$WORKDIR" -c protocol.file.allow=always ls-remote "$r" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    if [ -n "$RTIP" ] && [ "$RTIP" != "$NEW_COMMIT" ]; then
        TIPS_OK=0
        TIPS_DETAIL="$TIPS_DETAIL $r:$RTIP"
    fi
done

# T177 Round 2 R2-I4 fix: verify output is COPIED to a durable location
# beside $OUT before the scratch copy is deleted (§11.4.262: every PASS
# cites a captured, machine-created artefact).
V1_PERSIST="${OUT%.json}.verify1.json"
V2_PERSIST="${OUT%.json}.verify2.json"
cp -f "$V1" "$V1_PERSIST" 2>/dev/null || V1_PERSIST=""
cp -f "$V2" "$V2_PERSIST" 2>/dev/null || V2_PERSIST=""
rm -rf "$VERIFY_SCRATCH"
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
