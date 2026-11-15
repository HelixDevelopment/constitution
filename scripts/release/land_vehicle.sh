#!/usr/bin/env bash
# First statement on purpose (round 6, R5-C): tracing turned on by the caller
# (`bash -x`, SHELLOPTS=xtrace, a BASH_ENV file running `set -x`) would print every
# remote URL, and any credential in it, to stderr. See SHELL STARTUP below.
set +x +v
# land_vehicle.sh - land a reviewed vehicle bundle onto main (Helix Constitution).
#
# Repository path: scripts/release/land_vehicle.sh
# Test:            tests/release/test_land_vehicle.sh
# Class inventory: docs/qa/land_vehicle_r5_2026_11_13/class_inventory.md, extended in
#                  docs/qa/land_vehicle_r6_2026_11_14/ (newness_census.md, env_census.md)
#
# WHAT IT DOES
#   A vehicle is a git bundle holding commits that received an independent GO
#   but were not pushed. This script lands them on main of every upstream,
#   fast-forward only, in two phases so the lander can run the heavy derived-file
#   regeneration in between:
#
#   prepare  (1) check the bundle sha256; create a fresh clone at
#                <workdir>/<clone-name> (default name `constitution`, required by
#                the workable-items engine); copy the bundle into the clone's .git,
#                check the sha256 of THAT copy, and use only the copy from then on;
#                `git bundle verify` it; the given --head must be a ref tip inside
#                the bundle AND a commit object (an annotated tag is refused);
#            (2) fetch main from every declared remote, refuse if the remote mains
#                have diverged, take the newest tip as main;
#            (3) mint the real tracker id by running --mint-cmd inside the clone
#                (the §11.4.202 BUG/TASK intake, e.g. a `--prefix CON` add). The
#                LAST stdout line, without spaces, tabs and one trailing CR, must be
#                the id in the engine's canonical form <KEY>-NNN (three digits with
#                leading zeros up to 099, no leading zero from 100 on), and it must
#                not match --placeholder-re. The mint must not commit or switch
#                branch by itself and must change at least one file in the clone
#                (the tracker DB is tracked, §11.4.95). The changes are staged and
#                recorded ONCE as raw records (status, modes, blob ids, path) in
#                <evidence-dir>/mint_changes.tsv (status and path) and
#                mint_changes_raw.tsv. Every check reads that record: every path must
#                be ADDED or MODIFIED, a regular file (mode 100644 or 100755), free of
#                control characters, and match LANDER_TRACKER_PATHS. The id must be
#                NEW (see NEWNESS below): no file matching LANDER_TRACKER_PATHS in the
#                tree of main before the mint or of any unpushed vehicle commit may hold
#                it, and no commit reachable from main or the vehicle may mention it.
#                The id must occur as a token in the
#                recorded blob of at least one changed file. The commit is then made
#                from those blobs with plumbing (write-tree, commit-tree), its tree is
#                compared with the record byte by byte, and main is moved with a
#                compare-and-swap (`update-ref` with the old value). Alternatively
#                --item-id gives an id that was already minted (same canonical form,
#                not a placeholder; no newness check). With --id-verify-cmd the id is
#                then confirmed through the engine's own read command (both paths);
#            (4) re-commit every unpushed vehicle commit whose Roadmap-Item trailer is
#                missing or is a placeholder (--placeholder-re), with the real id, as
#                a raw commit object written with `git hash-object -t commit`: every
#                header line is copied byte for byte (tree, author, committer,
#                encoding, mergetag, any other) except that parent lines are mapped to
#                the re-committed parents and a gpgsig/gpgsig-sha256 signature is
#                dropped (it no longer matches; recorded per commit in
#                tree_equality.tsv, column signature_dropped). The message is kept
#                byte for byte, carriage returns included, except the Roadmap-Item
#                lines of the trailer block: the block is the last paragraph and only
#                exists when `git interpret-trailers --parse` (run with no repository
#                and no config, so no trailer.* or core.commentChar setting applies)
#                finds trailers in the message. Inside it every Roadmap-Item line (key
#                matched case-insensitively, spaces before the colon allowed) becomes
#                `Roadmap-Item: <value>`, a placeholder value becomes the id, and
#                identical lines are de-duplicated. A missing trailer is appended to
#                the block, or as a new last paragraph. Each re-committed commit is
#                then checked: header lines other than parent and gpgsig equal the
#                original, parents are the mapped parents, the message equals the
#                original apart from Roadmap-Item lines of the trailer block and
#                trailing blank lines, the tree is the original tree, and git parses
#                exactly one real Roadmap-Item trailer;
#            (5) integrate onto main, never rebasing and never rewriting main: a
#                fast-forward when main is an ancestor of the re-committed vehicle (the
#                --item-id path with no upstream movement), otherwise a merge commit.
#                On the --mint-cmd path the mint commit is already on main, so the
#                integration is ALWAYS a merge commit there. Main is checked before and
#                after (fast-forward: main = vehicle; merge: parents = old main and the
#                vehicle). Then every commit on main after the prepared base must carry
#                exactly one real Roadmap-Item trailer; then the derived-file steps are
#                PRINTED for the lander.
#   publish  (6) refuse a dirty tree, a clone not on main, a clone whose remote
#                configuration differs from --remotes-file, and a prepare state that
#                does not match the refs prepare recorded; read local main ONCE and
#                refuse unless it contains both the prepared base and the landed head;
#            (7) preflight EVERY remote first (read the remote main, fetch it, check
#                it is an ancestor of local main). If any remote is non-fast-forward,
#                unreadable or has no main, NOTHING is pushed (`not-pushed-preflight`)
#                and publish exits 1. Then two trailer checks, both refusing: every
#                commit after the prepared base (main_before) must carry one real
#                Roadmap-Item trailer, even when a remote already has it (so a run that
#                stopped half way can never publish an unchecked commit later); and
#                every commit that is on NO remote must carry one. A commit that is at
#                or before main_before (it was already published when prepare ran) is
#                not refused when it reaches another remote without a real trailer:
#                each such (remote, commit) is a WARN line and a row of
#                <evidence-dir>/publish_warnings.tsv and of the `## warnings` section of
#                publish.md; a WARN does not change the exit code. Then push the SHA
#                that was checked, as `<sha>:refs/heads/main`, to each remote that is
#                behind;
#            (8) `git ls-remote` read-back of every remote; a per-remote PASS/FAIL
#                table goes to <evidence-dir>/publish.md (+ .tsv); any FAIL => exit 1.
#                If clone main moved while publish ran, publish exits 1 after the
#                read-back.
#   verify   step (8) alone (read-back only, no push). It needs the prepare state, the
#            same remote check as publish, and the same state checks: the prepare refs
#            must match the state, and local main must contain the prepared base and
#            the landed vehicle head. A remote is PASS only when its main equals local
#            main and contains the landed head (verify.md names both shas). publish
#            applies the same per-remote rule to its read-back.
#
# REMOTES ARE CHECKED AT EVERY USE
#   The clone addresses each remote by its NAME (a URL on a command line would be
#   visible to every local user in the process list). Immediately before each fetch,
#   ls-remote and push, the remote is checked again: its fetch URLs (`git remote
#   get-url --all`, so a url.insteadOf rewrite counts) must be exactly the URL in
#   --remotes-file, its push URLs (`get-url --push --all`, so pushurl and
#   url.pushInsteadOf count) likewise, and its only remote.<name>.* keys, from any
#   config file, may be url, fetch (fetches run with `--refmap=`, so a fetch refspec
#   is never used), prune, pruneTags, tagOpt, skipDefaultUpdate, skipFetchAll and
#   followRemoteHEAD. Any other key (pushurl, push, mirror, receivepack, uploadpack,
#   vcs, proxy, serverOption, promisor ...) is refused. The remaining gap is the time
#   between that check and git reading its config for the operation itself.
#   A refusal in the middle of the push loop names the remotes this run already
#   pushed the checked main to; no further remote is pushed after it.
#
# SAFETY
#   No forced update of any kind: the only push is `<sha>:refs/heads/main` without
#   a plus sign. The test greps this file for force-type flags and refspecs prefixed
#   with a plus sign, and records the argv of every push the script makes through a
#   git shim. No remote URL is printed (URLs may carry credentials), also not when the
#   caller turned tracing on (see SHELL STARTUP): git's own stderr
#   from fetch, ls-remote and push is not shown; it is appended to
#   <clone>/.git/land_git_stderr.log (that clone's .git/config holds the same URLs
#   already). Only remote names appear in output and evidence. Nothing is deleted.
#   HOME is not touched. --clone-name must be a single plain path component. The
#   clone directory is made with mkdir (which fails on any existing entry, a dangling
#   symlink included), `git init --template= .` runs with that directory as its cwd
#   after its physical path was checked, and afterwards the clone path must still be
#   that directory (same device and inode, not a symlink) or prepare exits 1. The
#   clone is then used with explicit --git-dir and --work-tree, so the clone and its
#   checkout stay inside the workdir.
#   A bad line of the remotes file is reported by its line number only, never by its
#   text (the URL may hold a credential).
#
# ARGUMENTS (one strict parser)
#   The subcommand is the first argument. `-h`/`--help` means help only as the first
#   argument or where an option NAME is expected; as an option value it is an error.
#   Every option needs a non-empty value that does not start with '-' (write ./NAME
#   for such a path) and may be given once. Path values must not hold control
#   characters. --placeholder-re must be a valid ERE.
#
# SHELL STARTUP (round 6)
#   `set +x +v` is the first statement. Then the script runs itself again ONCE, with
#   exec (same PID), in a fresh `$BASH --norc --noprofile`, after removing from the
#   environment every exported function (BASH_FUNC_*) and these variables that bash
#   reads at startup and that change how a script runs: BASH_ENV, ENV, SHELLOPTS,
#   BASHOPTS, POSIXLY_CORRECT, BASH_COMPAT, BASH_XTRACEFD, PS4, GLOBIGNORE, GLOBSORT,
#   EXECIGNORE, FUNCNEST, TMOUT, CHILD_MAX, BASH_LOADABLES_PATH, BASH_CMDS,
#   BASH_ALIASES (census:
#   docs/qa/land_vehicle_r6_2026_11_14/env_census.md). So `bash -x`, `bash -O ...`, a
#   BASH_ENV file and SHELLOPTS=xtrace reach neither this run nor any command it
#   starts (the mint and id-verify commands too: their BASH_ENV is removed). The
#   marker LAND_VEHICLE_EXEC holds the PID and is removed again; if such a variable
#   is still present after the re-run, the script exits 2. Not covered: a BASH_ENV
#   file runs the caller's code before the first line of this script; it is the
#   caller's own code with the caller's rights, and it can do anything (this is not
#   a security boundary). The script must be run as a file.
#
# ENVIRONMENT (cleared before the first git call)
#   Every GIT_* variable is removed EXCEPT: GIT_CONFIG_GLOBAL, GIT_CONFIG_SYSTEM,
#   GIT_CONFIG_NOSYSTEM (the caller's choice of config FILES), GIT_SSH,
#   GIT_SSH_COMMAND, GIT_SSH_VARIANT, GIT_ASKPASS, GIT_TERMINAL_PROMPT (transport
#   authentication) and GIT_AUTHOR_NAME/EMAIL/DATE, GIT_COMMITTER_NAME/EMAIL/DATE
#   (the identity of the lander's own two commits: the mint commit and the merge
#   commit; both are signed when the caller's commit.gpgSign is true, the mint commit
#   through `commit-tree -S` because commit-tree itself ignores that setting). So no
#   inherited variable can select another repository, index, work tree, object
#   store, namespace, template, config injection, trace, attribute source or replace
#   ref. CDPATH is removed. The script and every tool it starts run with LC_ALL=C (byte
#   semantics for every regex and grep); the mint and id-verify commands get the
#   caller's LC_ALL back (or none, if the caller had none) and otherwise inherit the
#   cleared environment.
#   LANDER_REMOTES   names of the remotes the remotes file must declare (each
#                    ^[A-Za-z0-9][A-Za-z0-9._-]*$), default the 9 upstreams.
#   LANDER_TRACKER_PATHS  space-separated bash patterns (`*` also matches '/') of
#                    the paths the mint may add or modify, relative to the clone root,
#                    default `docs/workable_items.db`. Each pattern must contain '/',
#                    its first component must be a literal name ([A-Za-z0-9._-], not
#                    '.' or '..'), no component may be '..', and it holds no control
#                    character. Its -wal/-shm sidecars are gitignored: a mint that
#                    changes only them changes no tracked file and is refused.
#
# GIT CONFIG (what the caller's config can and cannot do)
#   The script runs under `umask 077`: the clone's .git/config holds the remote URLs
#   (they may carry a credential), so it is created owner-only. The clone is created
#   by `git init --template= -b main --object-format=<sha1|sha256, from the length of
#   --head> --ref-format=files` with core.hooksPath, core.fsmonitor and
#   core.sharedRepository=false pinned (a global core.sharedRepository would make the
#   clone group- or world-writable). `git interpret-trailers --parse` runs with no
#   repository and no config at all (GIT_DIR=/nonexistent, no system and no global
#   file). Every other git command against the clone runs as
#     git --no-pager --no-replace-objects --literal-pathspecs -C <clone>
#         --git-dir=<clone>/.git --work-tree=<clone> -c ... <command>
#   with these settings pinned: core.hooksPath=/dev/null, core.fsmonitor=false,
#   core.attributesFile=/dev/null, core.excludesFile=/dev/null, core.autocrlf=false,
#   core.eol=lf, core.sparseCheckout=false, core.useReplaceRefs=false,
#   core.commentChar=#, core.sharedRepository=false, core.untrackedCache=false,
#   core.checkStat=default, diff.ignoreSubmodules=none, log.showSignature=false,
#   i18n.logOutputEncoding=UTF-8, i18n.commitEncoding=UTF-8, color.ui=never,
#   color.diff=never, color.status=never, merge.log=false, merge.autoStash=false,
#   merge.renormalize=false, rerere.enabled=false, pull.twohead=ort,
#   pull.octopus=octopus, branch.main.mergeOptions= (empty), gc.auto=0,
#   maintenance.auto=false, submodule.recurse=false, fetch.recurseSubmodules=false,
#   fetch.prune=false, fetch.pruneTags=false, fetch.bundleURI= (empty),
#   transfer.bundleURI=false, push.pushOption= (empty, which clears the list),
#   push.gpgSign=false, push.followTags=false, push.recurseSubmodules=no,
#   push.default=nothing, protocol.ext.allow=never.
#   Commit, merge and push also pass --no-verify; merge passes -s ort,
#   --no-verify-signatures, --no-log and --cleanup=strip; fetch passes --no-tags and
#   --refmap=; push passes --no-follow-tags and --recurse-submodules=no. Every
#   diff-index, diff-tree and status passes --ignore-submodules=none (a
#   submodule.<name>.ignore setting, from config or from an in-tree .gitmodules, would
#   otherwise hide a gitlink change from the mint record). Data is read from raw
#   objects (`cat-file commit`, raw diffs with --no-abbrev -z), never from `git log`,
#   so a log, pretty or signature-display setting cannot change it.
#   MERGE ORACLE: pull.twohead and branch.<name>.mergeOptions are pinned because a
#   global `pull.twohead=ours` or `branch.main.mergeOptions=-s ours` makes `git merge`
#   drop the whole vehicle while the merge commit still has the right parents (measured
#   with git 2.53; an explicit -s ort does not override mergeOptions). After the merge,
#   its tree must equal the tree of the same merge computed by
#   `git merge-tree --write-tree` with no global and no system config. A merge option,
#   strategy or merge driver from the caller's config that changes the result, or that
#   makes a conflicting merge succeed, is therefore refused (exit 1, nothing published).
#   Left to the caller's config on purpose: the transport (ssh command, credential
#   helpers, http.*, protocol allow lists other than ext), identity and gpg settings
#   for the lander's own two commits, and clean/smudge filters named by attributes
#   INSIDE the vehicle or main (or by attr.tree): they run the caller's command on
#   checkout and add; the content checks above then apply to what was recorded. Global
#   trace2.* config is read by git before any -c option and is not neutralised.
#
# REAL ENGINE (mint command)
#   The workable-items engine prints `add: created CON-166 (Task, status=Queued) in
#   Issues`, not a bare id, so wrap it to print the id as the last line, e.g.
#     --mint-cmd "<engine> add Task low --db docs/workable_items.db --title '...' \
#       --prefix CON | sed -n 's/^add: created \(CON-[0-9][0-9]*\) .*/\1/p'"
#   (under `bash -c` without pipefail the sed decides the status; an engine
#   failure leaves the last line empty, so prepare refuses it as "did not print an
#   id"). Try such a command first on a COPY of the database, never on the live
#   checkout.
#
# LOCK
#   Every subcommand takes an exclusive `flock` on <workdir>/.land_vehicle.lock for
#   its whole run; a second concurrent run in the same workdir is refused (exit 2).
#   The kernel releases the lock when the process ends, so there is no stale lock.
#   Every git command, the mint and the id-verify commands run without the lock
#   descriptor (`9>&-`), so a process they leave behind (a gpg agent, a credential
#   helper) never keeps the lock. The lock does not stop other programs from writing
#   into the clone; the checks above are made at the point of use for that reason.
#
# NEWNESS (step 3, the --mint-cmd path; class B in the class inventory)
#   The minted id is refused when it occurs, with any number of leading zeros
#   (CON-7, CON-07 and CON-007 are one id) and in any letter case:
#   (a) in a file matching LANDER_TRACKER_PATHS in the tree of main before the mint;
#   (b) in such a file in the tree of any unpushed vehicle commit, the tip included
#       (the merge would bring that file in; an id that a vehicle commit added and a
#       later one removed counts too);
#   (c) anywhere in a commit object reachable from main or the vehicle: a Roadmap-Item
#       line, a folded trailer, a mention in a subject or body, any key spelling.
#   (a) and (b) search a text file without a left boundary and a file holding a NUL
#   byte by substring; (c) searches by substring. All three fail closed: an unrelated
#   mention also refuses. Scoped out on purpose: tracker files of OLDER main commits
#   (an id once in the tracker and since removed from it on main). The engine mints
#   from its current database and never reuses an id (§11.4.54), so a removed id
#   cannot come back from it; searching every historical version of a binary
#   tracker database would cost one full read per version.
#
# TRAILER SHAPES REFUSED ON PURPOSE (fail closed)
#   A commit that does not already carry one real trailer is rewritten only when its
#   message is plain: if its last non-blank line, or any line of its trailer block,
#   starts with '#', prepare refuses it. A folded (continued) Roadmap-Item value (a
#   Roadmap-Item line, anywhere in the message, followed by a line that starts with a
#   space or a TAB and is not blank; git's parser would join the two, while a
#   whitespace-only line is a blank line to it), a value holding a control
#   character (CR included), a non-canonical id (CON-0501, CON-77) and two different
#   real ids in one commit are NOT repaired either, and a folded value is NOT kept
#   even though git would parse it as one trailer: prepare and publish refuse them
#   with "lacks a single real Roadmap-Item trailer". Fix such a commit by hand in the
#   vehicle and re-review it. (A commit that already carries one real, unfolded
#   trailer is kept byte for byte; git's own parser decides what its trailer is, and
#   it skips a trailing '#' comment paragraph.) `<KEY>-050` is a placeholder
#   by default, and a value matching --placeholder-re is never accepted as a real id
#   (not as the minted id, not as --item-id, not in any trailer check, also not at
#   publish): a real item numbered 050 needs another --placeholder-re.
#
# RE-RUN / RECOVERY
#   prepare refuses an existing clone path. prepare pushes nothing, so after a failed
#   prepare remove <workdir>/<clone-name> with a guarded delete and run prepare again.
#   publish is safe to re-run: remotes already at local main are `up-to-date`, the
#   rest are pushed (after the all-remote preflight). If a remote received an
#   untrailered commit after prepare (for example another lander's work), publish
#   refuses it; run prepare again in a new workdir, so that commit becomes part of the
#   prepared base. An empty (new) mirror without a main branch makes prepare stop with
#   "fetch of main failed"; seed that mirror by hand first (fast-forward from another).
#
# USAGE
#   land_vehicle.sh prepare --bundle FILE --sha256 HEX --head SHA --workdir DIR \
#       --remotes-file FILE (--mint-cmd CMD | --item-id <KEY>-NNN) [--id-verify-cmd CMD] \
#       [--evidence-dir DIR] [--placeholder-re ERE] [--clone-name NAME] [--key-prefix KEY]
#   land_vehicle.sh publish --workdir DIR --remotes-file FILE [--evidence-dir DIR] \
#       [--key-prefix KEY] [--clone-name NAME]
#   land_vehicle.sh verify  --workdir DIR --remotes-file FILE [--evidence-dir DIR] [--clone-name NAME]
#   land_vehicle.sh -h | --help
#
#   --key-prefix: tracker id key (§11.4.54: the key is data), default CON
#   (^[A-Z][A-Z0-9]*$). Ids must match ^<KEY>-(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2,})$.
#   publish reads the key and the placeholder pattern from the prepare state; a
#   different --key-prefix given to publish is refused.
#   --placeholder-re default: ^(<KEY>-050|<KEY>-PENDING-[A-Za-z0-9._-]*|<TO-BE-MINTED[^>]*>)$
#   --id-verify-cmd: run in the clone as `bash -c CMD land_vehicle ID` (the id is $1
#   and $LAND_ITEM_ID); it must exit 0 and print the id as a token.
#   --clone-name: ^[A-Za-z0-9][A-Za-z0-9._-]*$ without '..'.
#   --head: the full commit sha (40 hex digits, or 64 for a sha256 repository).
#   --remotes-file: one "name url" per line (# comments allowed); a control
#   character other than TAB (a CR from a CRLF file included) is refused by line
#   number. It must declare exactly the names in LANDER_REMOTES (default: the 9
#   constitution upstreams).
#   Build it from the real checkout with: git remote -v | awk '$3=="(push)"{print $1, $2}'
#
# EXIT CODES
#   0 success | 1 verification or publish FAIL | 2 usage/config error (incl. lock
#   held, remote configuration mismatch, bad state) | 3 integration refused (diverged
#   mains, merge conflict, nothing to land). Any other status of a failing command is
#   reported and mapped to 1.
set -euo pipefail

# ---------------------------------------------------------------- shell startup
# Re-run once in a pristine bash (see SHELL STARTUP in the header). LV_DIRTY lists
# the variables bash reads from the environment that change how this script runs.
LV_DIRTY=" BASH_ENV ENV SHELLOPTS BASHOPTS POSIXLY_CORRECT BASH_COMPAT BASH_XTRACEFD PS4 GLOBIGNORE GLOBSORT EXECIGNORE FUNCNEST TMOUT CHILD_MAX BASH_LOADABLES_PATH BASH_CMDS BASH_ALIASES "
# lv_dirty_env: prints `-u NAME` lines for every such variable in the environment and
# every exported function (BASH_FUNC_*), read from the real environment (env -0)
lv_dirty_env() {
  local e n
  while IFS= read -r -d '' e; do
    n=${e%%=*}
    case "$n" in BASH_FUNC_*) printf '%s\n' "$n"; continue ;; esac
    [[ "$LV_DIRTY" == *" $n "* ]] && printf '%s\n' "$n"
  done < <(env -0)
  return 0
}
if [ "${LAND_VEHICLE_EXEC:-}" != "$$" ]; then
  _lv_self=${BASH_SOURCE[0]:-}
  [ -n "$_lv_self" ] && [ -r "$_lv_self" ] && [ -n "${BASH:-}" ] && [ -x "$BASH" ] \
    || { printf 'land_vehicle: ERROR: run this script as a file (cannot re-run it in a clean bash)\n' >&2; exit 2; }
  _lv_u=()
  while IFS= read -r _lv_n; do _lv_u+=(-u "$_lv_n"); done < <(lv_dirty_env)
  # exec keeps the PID, so the marker identifies this run only
  exec env "${_lv_u[@]}" LAND_VEHICLE_EXEC="$$" "$BASH" --norc --noprofile -- "$_lv_self" "$@"
fi
unset LAND_VEHICLE_EXEC
if [ -n "$(lv_dirty_env)" ]; then
  printf 'land_vehicle: ERROR: the shell environment still holds a startup or option variable after the clean re-run: %s\n' "$(lv_dirty_env | tr '\n' ' ')" >&2
  exit 2
fi

# ---------------------------------------------------------------- environment
unset CDPATH
# the clone holds the remote URLs (they may carry a credential): owner-only files
umask 077
lander_scrub_env() {
  local v
  for v in $(compgen -e); do
    case "$v" in
      GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_CONFIG_NOSYSTEM) ;;
      GIT_SSH|GIT_SSH_COMMAND|GIT_SSH_VARIANT|GIT_ASKPASS|GIT_TERMINAL_PROMPT) ;;
      GIT_AUTHOR_NAME|GIT_AUTHOR_EMAIL|GIT_AUTHOR_DATE) ;;
      GIT_COMMITTER_NAME|GIT_COMMITTER_EMAIL|GIT_COMMITTER_DATE) ;;
      GIT_*) unset "$v" ;;
    esac
  done
}
lander_scrub_env
if [ -n "${LC_ALL+set}" ]; then CALLER_LC_ALL_SET=1; CALLER_LC_ALL=$LC_ALL; else CALLER_LC_ALL_SET=0; CALLER_LC_ALL=; fi
export LC_ALL=C
lander_exit() {
  local rc=$?
  case "$rc" in
    0|1|2|3) ;;
    *) printf 'land_vehicle: ERROR: a command failed with status %s (not one of the documented exit codes); exiting 1\n' "$rc" >&2
       exit 1 ;;
  esac
}
trap lander_exit EXIT

LANDER_REMOTES=${LANDER_REMOTES:-"gitflic github github_helixdevelopment github_vasic_digital gitlab_helixdevelopment1 gitlab_vasic_digital gitverse m3w origin"}
STATE_NAME=land_vehicle.state

die() { local code=$1; shift; printf 'land_vehicle: ERROR: %s\n' "$*" >&2; exit "$code"; }
log() { printf 'land_vehicle: %s\n' "$*"; }
usage() { awk '/^set -euo pipefail/ {exit} /^# land_vehicle\.sh - / {p = 1} p {print}' "$0"; exit 0; }
# has_ctrl <text>: true when the text holds a control character (C locale)
has_ctrl() { [[ "$1" == *[[:cntrl:]]* ]]; }
# run_caller_locale <cmd...>: run with the caller's LC_ALL (or none)
run_caller_locale() {
  if [ "$CALLER_LC_ALL_SET" = 1 ]; then LC_ALL=$CALLER_LC_ALL "$@"; else env -u LC_ALL "$@"; fi
}

# ---------------------------------------------------------------- arguments
CMD=${1:-}
case "$CMD" in
  -h|--help) usage ;;
  '') die 2 "missing subcommand (prepare|publish|verify)" ;;
  prepare|publish|verify) ;;
  *) die 2 "unknown subcommand: $CMD" ;;
esac
shift
BUNDLE="" SHA="" HEAD_SHA="" WORKDIR="" REMOTES_FILE="" MINT_CMD="" ITEM_ID="" VERIFY_CMD=""
EVIDENCE_DIR="" CLONE_NAME=constitution PLACEHOLDER_RE="" KEY_PREFIX="" KEY_GIVEN=0
declare -A SEEN=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --bundle|--sha256|--head|--workdir|--remotes-file|--mint-cmd|--item-id|--id-verify-cmd|--evidence-dir|--placeholder-re|--clone-name|--key-prefix) ;;
    *) die 2 "unknown argument: $1" ;;
  esac
  if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
    die 2 "option $1 needs a value: $1 must not start with '-' and must not be empty (write ./NAME for a path that starts with '-')"
  fi
  [ -z "${SEEN[$1]:-}" ] || die 2 "option $1 given more than once"
  SEEN[$1]=1
  case "$1" in
    --bundle|--workdir|--remotes-file|--evidence-dir|--clone-name|--head|--sha256|--item-id|--key-prefix|--placeholder-re)
      ! has_ctrl "$2" || die 2 "option $1 holds a control character" ;;
  esac
  case "$1" in
    --bundle) BUNDLE=$2 ;;
    --sha256) SHA=$2 ;;
    --head) HEAD_SHA=$2 ;;
    --workdir) WORKDIR=$2 ;;
    --remotes-file) REMOTES_FILE=$2 ;;
    --mint-cmd) MINT_CMD=$2 ;;
    --item-id) ITEM_ID=$2 ;;
    --id-verify-cmd) VERIFY_CMD=$2 ;;
    --evidence-dir) EVIDENCE_DIR=$2 ;;
    --placeholder-re) PLACEHOLDER_RE=$2 ;;
    --clone-name) CLONE_NAME=$2 ;;
    --key-prefix) KEY_PREFIX=$2; KEY_GIVEN=1 ;;
  esac
  shift 2
done
if [ "$CMD" != prepare ]; then
  for _o in --bundle --sha256 --head --mint-cmd --item-id --id-verify-cmd --placeholder-re; do
    [ -z "${SEEN[$_o]:-}" ] || die 2 "option $_o is not used by $CMD"
  done
fi
KEY_PREFIX=${KEY_PREFIX:-CON}
[[ "$KEY_PREFIX" =~ ^[A-Z][A-Z0-9]*$ ]] || die 2 "--key-prefix must match ^[A-Z][A-Z0-9]*\$"
set_key() { # set_key <KEY>: the canonical id pattern (the engine prints %s-%03d)
  ID_RE="^${1}-(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2,})\$"
}
set_key "$KEY_PREFIX"
PLACEHOLDER_RE=${PLACEHOLDER_RE:-"^(${KEY_PREFIX}-050|${KEY_PREFIX}-PENDING-[A-Za-z0-9._-]*|<TO-BE-MINTED[^>]*>)\$"}
check_ere() { # check_ere <ERE>: bash returns 2 for an invalid regex
  local rc=0
  # shellcheck disable=SC2319 # the status of the [[ ]] test is the one wanted
  [[ "" =~ $1 ]] || rc=$?
  [ "$rc" != 2 ]
}
check_ere "$PLACEHOLDER_RE" || die 2 "--placeholder-re is not a valid extended regular expression"
[[ "$CLONE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$CLONE_NAME" != *..* ]] \
  || die 2 "--clone-name must be one plain path component (^[A-Za-z0-9][A-Za-z0-9._-]*\$, no '..')"
[ -n "$WORKDIR" ] || die 2 "--workdir is required"
[ -n "$REMOTES_FILE" ] && [ -r "$REMOTES_FILE" ] || die 2 "--remotes-file is required and must be readable"
WORKDIR=$(cd -- "$WORKDIR" && pwd) || die 2 "workdir does not exist"
! has_ctrl "$WORKDIR" || die 2 "the workdir path holds a control character"
WORKDIR_P=$(cd -P -- "$WORKDIR" && pwd -P) || die 2 "workdir does not exist"
CLONE=$WORKDIR/$CLONE_NAME
ERRLOG=$CLONE/.git/land_git_stderr.log
EVIDENCE_DIR=${EVIDENCE_DIR:-$WORKDIR/evidence}

# ---------------------------------------------------------------- lock
command -v flock >/dev/null 2>&1 || die 2 "flock(1) is required for the workdir lock"
exec 9>>"$WORKDIR/.land_vehicle.lock"
flock -n 9 || die 2 "another land_vehicle run holds the lock $WORKDIR/.land_vehicle.lock; wait for it to finish"

# ---------------------------------------------------------------- remotes
declare -a R_NAMES=() R_URLS=()
NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
for _n in $LANDER_REMOTES; do
  [[ "$_n" =~ $NAME_RE ]] || die 2 "LANDER_REMOTES holds a bad remote name (each must match $NAME_RE)"
done
# load_remotes: a bad line is reported by its NUMBER only (its text may hold a credential)
load_remotes() {
  local line name url rest want n lineno=0
  [ "$(tr -d '\000' < "$REMOTES_FILE" | wc -c)" = "$(wc -c < "$REMOTES_FILE")" ] \
    || die 2 "remotes file holds a NUL byte (the file is not shown, it may hold a credential)"
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" == *[$'\001'-$'\010'$'\013'-$'\037'$'\177']* ]]; then
      die 2 "remotes file line $lineno: holds a control character other than TAB (a CR from a CRLF file?); the line is not shown, it may hold a credential"
    fi
    name="" url="" rest=""
    read -r name url rest <<<"$line" || true
    case "$name" in ''|'#'*) continue ;; esac
    [ -n "$url" ] && [ -z "$rest" ] \
      || die 2 "remotes file line $lineno: want exactly two fields 'name url' (the line is not shown, it may hold a credential)"
    [[ "$name" =~ $NAME_RE ]] \
      || die 2 "remotes file line $lineno: the remote name is not a plain name (want $NAME_RE; the line is not shown)"
    [[ "$url" != -* ]] || die 2 "remotes file line $lineno: the URL must not start with '-'"
    R_NAMES+=("$name"); R_URLS+=("$url")
  done < "$REMOTES_FILE"
  for want in $LANDER_REMOTES; do
    n=0
    for name in "${R_NAMES[@]}"; do [ "$name" = "$want" ] && n=$((n + 1)); done
    [ "$n" -eq 1 ] || die 2 "remotes file must declare '$want' exactly once (found $n)"
  done
  [ "${#R_NAMES[@]}" -eq "$(wc -w <<<"$LANDER_REMOTES")" ] || die 2 "remotes file declares names outside LANDER_REMOTES"
}
load_remotes

# ---------------------------------------------------------------- tracker paths
read -r -a TRACKER_PATS <<<"${LANDER_TRACKER_PATHS:-docs/workable_items.db}"
[ "${#TRACKER_PATS[@]}" -gt 0 ] || die 2 "LANDER_TRACKER_PATHS is empty"
for _p in "${TRACKER_PATS[@]}"; do
  ! has_ctrl "$_p" || die 2 "LANDER_TRACKER_PATHS: a pattern holds a control character"
  [[ "$_p" != /* ]] && [[ "$_p" != *..* ]] || die 2 "LANDER_TRACKER_PATHS: patterns are relative to the clone root and hold no '..'"
  [[ "$_p" == */* ]] && [[ "${_p%%/*}" =~ ^[A-Za-z0-9._-]+$ ]] && [ "${_p%%/*}" != . ] \
    || die 2 "LANDER_TRACKER_PATHS: each pattern needs a literal first directory and a '/' (for example docs/workable_items.db); '*' or a pattern without a directory would let the mint change any file"
done
# tracker_path <path>: true when the path matches one of LANDER_TRACKER_PATHS
tracker_path() {
  local pat
  for pat in "${TRACKER_PATS[@]}"; do
    # shellcheck disable=SC2053 # pattern match on purpose
    [[ "$1" == $pat ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------- git
# Every git call against the clone: explicit repository, no pager, no replace refs,
# literal pathspecs, the pinned settings of the header, no lock descriptor.
GIT_PIN=(
  -c core.hooksPath=/dev/null -c core.fsmonitor=false
  -c core.attributesFile=/dev/null -c core.excludesFile=/dev/null
  -c core.autocrlf=false -c core.eol=lf -c core.sparseCheckout=false
  -c core.useReplaceRefs=false -c core.commentChar=# -c core.sharedRepository=false
  -c core.untrackedCache=false -c core.checkStat=default -c diff.ignoreSubmodules=none
  -c log.showSignature=false -c i18n.logOutputEncoding=UTF-8 -c i18n.commitEncoding=UTF-8
  -c color.ui=never -c color.diff=never -c color.status=never -c merge.log=false -c merge.autoStash=false -c rerere.enabled=false
  -c gc.auto=0 -c maintenance.auto=false
  -c submodule.recurse=false -c fetch.recurseSubmodules=false
  -c fetch.prune=false -c fetch.pruneTags=false -c fetch.bundleURI= -c transfer.bundleURI=false
  -c push.pushOption= -c push.gpgSign=false -c push.followTags=false
  -c push.recurseSubmodules=no -c push.default=nothing
  -c protocol.ext.allow=never
  -c pull.twohead=ort -c pull.octopus=octopus -c branch.main.mergeOptions= -c merge.renormalize=false
)
g() {
  git --no-pager --no-replace-objects --literal-pathspecs -C "$CLONE" \
    --git-dir="$CLONE/.git" --work-tree="$CLONE" "${GIT_PIN[@]}" "$@" 9>&-
}
# gx: git's trailer parser with no repository and no config at all (no trailer.*,
# no core.commentChar, no alias); reads a message on stdin
gx() {
  env GIT_DIR=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git interpret-trailers --no-divider --parse 9>&-
}

# assert_remote <index>: the remote is configured exactly as --remotes-file says,
# checked again immediately before each use (fetch, ls-remote, push).
REMOTE_KEYS_OK=" url fetch prune prunetags tagopt skipdefaultupdate skipfetchall followremotehead "
# PUSHED_NAMES: the remotes this publish run has pushed so far, for an honest message
# when a remote is refused in the middle of the push loop
PUSHED_NAMES=""
ar_note() {
  if [ -n "$PUSHED_NAMES" ]; then
    printf '; this run already pushed the checked main to:%s; no further remote is pushed (fix the clone config, run verify, then publish again)' "$PUSHED_NAMES"
  else
    printf '; nothing was pushed'
  fi
}
assert_remote() {
  local name=${R_NAMES[$1]} want=${R_URLS[$1]} got key k ere
  got=$(g remote get-url --all "$name" 2>/dev/null) || die 2 "clone has no remote '$name'$(ar_note)"
  [ "$got" = "$want" ] || die 2 "remote '$name' fetch URL in the clone differs from --remotes-file$(ar_note)"
  got=$(g remote get-url --push --all "$name" 2>/dev/null) || die 2 "cannot read the push URL of remote '$name'$(ar_note)"
  [ "$got" = "$want" ] || die 2 "remote '$name' push URL(s) in the clone differ from --remotes-file$(ar_note)"
  ere="^remote\\.${name//./\\.}\\."
  got=$(g config --name-only --get-regexp "$ere" 2>/dev/null) || true
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    k=${key##*.}; k=${k,,}
    [[ "$REMOTE_KEYS_OK" == *" $k "* ]] || die 2 "remote '$name' has remote.$name.$k set (git config); refusing$(ar_note)"
  done <<<"$got"
}
assert_remote_urls() { local i; for i in "${!R_NAMES[@]}"; do assert_remote "$i"; done; }

# remote_main <index>: sets RMAIN to the remote main sha via ls-remote (empty if none
# or unreadable); the remote is checked first, in this shell (not in a subshell)
RMAIN=""
remote_main() {
  assert_remote "$1"
  RMAIN=$({ g ls-remote --refs "${R_NAMES[$1]}" refs/heads/main 2>>"$ERRLOG" || true; } \
    | awk '$2 == "refs/heads/main" {print $1}')
}

# newest_tip <sha>...: the tip that contains all others; dies 3 when they diverge.
newest_tip() {
  local tip=$1 s
  for s in "$@"; do
    if g merge-base --is-ancestor "$s" "$tip"; then :
    elif g merge-base --is-ancestor "$tip" "$s"; then tip=$s
    else die 3 "remote mains have diverged ($s vs $tip): integrate them first, by merge"
    fi
  done
  printf '%s\n' "$tip"
}

# ---------------------------------------------------------------- trailers
# is_ri_line <line>: a Roadmap-Item trailer line (key case-insensitive, spaces
# before the colon allowed); sets RI_VAL (value without surrounding whitespace)
RI_VAL=""
is_ri_line() {
  local key=${1%%:*}
  [ "$key" != "$1" ] || return 1
  [[ "${key,,}" =~ ^roadmap-item[[:space:]]*$ ]] || return 1
  RI_VAL=${1#*:}
  RI_VAL=${RI_VAL#"${RI_VAL%%[![:space:]]*}"}
  RI_VAL=${RI_VAL%"${RI_VAL##*[![:space:]]}"}
}
# ri_values <message>: RI_VALS = the Roadmap-Item values git parses in the message
RI_VALS=()
ri_values() {
  local parsed line key v
  RI_VALS=()
  parsed=$(printf '%s' "$1" | gx) || {
    printf 'land_vehicle: ERROR: git interpret-trailers failed (parse)\n' >&2; return 1; }
  while IFS= read -r line; do
    key=${line%%:*}
    [ "$key" != "$line" ] || continue
    [[ "${key,,}" =~ ^roadmap-item[[:space:]]*$ ]] || continue
    v=${line#*:}
    v=${v#"${v%%[![:space:]]*}"}
    RI_VALS+=("$v")
  done <<<"$parsed"
}
# real_trailer <message>: exactly one Roadmap-Item value, a canonical id, not a
# placeholder, no control character. Sets RI_FOUND (for messages).
RI_FOUND=""
# folded_ri <message>: true when a Roadmap-Item line (anywhere in the message) is
# followed by a line that starts with a space or a TAB and holds a non-blank
# character, which git's parser joins to it (a folded value). A whitespace-only line
# is a blank line for git (it ends the paragraph), so it is not a continuation. Such
# a commit is refused, never kept and never repaired.
folded_ri() {
  local -a L=()
  local i
  mapfile -t L <<<"$1"
  for ((i = 0; i + 1 < ${#L[@]}; i++)); do
    is_ri_line "${L[i]}" || continue
    [[ "${L[i+1]}" == [$' \t']*[![:space:]]* ]] && return 0
  done
  return 1
}
real_trailer() {
  local v
  if folded_ri "$1"; then RI_FOUND="a folded (continued) Roadmap-Item value"; return 1; fi
  ri_values "$1" || return 2
  RI_FOUND=""
  for v in "${RI_VALS[@]}"; do RI_FOUND+="${RI_FOUND:+, }${v//[[:cntrl:]]/?}"; done
  [ "${#RI_VALS[@]}" -eq 1 ] || return 1
  v=${RI_VALS[0]}
  ! has_ctrl "$v" && [[ "$v" =~ $ID_RE ]] && ! [[ "$v" =~ $PLACEHOLDER_RE ]]
}
# commit_msg <commit> <var>: the raw message of the commit, byte for byte
commit_msg() {
  local f=$CLONE/.git/land_tmp_commit raw
  g cat-file commit "$1" > "$f" || return 2
  [ "$(tr -d '\000' < "$f" | wc -c)" = "$(wc -c < "$f")" ] || { printf -v "$2" '%s' ""; return 3; }
  raw=""
  IFS= read -r -d '' raw < "$f" || true
  case "$raw" in *$'\n\n'*) printf -v "$2" '%s' "${raw#*$'\n\n'}" ;; *) printf -v "$2" '%s' "" ;; esac
}
# untrailered <rev-list args...>: prints "<commit><TAB><found values>" for every
# commit in the range that does not carry one real Roadmap-Item trailer. 2 on git failure.
untrailered() {
  local list c m rc
  list=$(g rev-list "$@") || return 2
  for c in $list; do
    rc=0; commit_msg "$c" m || rc=$?
    [ "$rc" = 2 ] && return 2
    if [ "$rc" = 3 ]; then printf '%s\t%s\n' "$c" "a NUL byte in the message"; continue; fi
    rc=0; real_trailer "$m" || rc=$?
    [ "$rc" = 2 ] && return 2
    [ "$rc" = 0 ] || printf '%s\t%s\n' "$c" "${RI_FOUND//$'\t'/ }"
  done
}
# check_trailers <hint> <rev-list args...>: every commit in the range must carry one
# real Roadmap-Item trailer
check_trailers() {
  local hint=$1 bad c; shift
  bad=$(untrailered "$@") || die 1 "rev-list or trailer parse failed for the trailer check"
  [ -z "$bad" ] && return 0
  bad=${bad%%$'\n'*}
  c=${bad%%$'\t'*}
  die 1 "commit $c lacks a single real Roadmap-Item trailer (found: '${bad#*$'\t'}'; want one value matching $ID_RE that is not a placeholder)${hint}"
}

# ---------------------------------------------------------------- ids
# id_num <id>: the number of the id without leading zeros
id_num() { local n=${1##*-}; n=${n#"${n%%[!0]*}"}; printf '%s' "${n:-0}"; }
# id_in_blob <id> <file>: the exact id occurs as a token in the file (binary-safe)
id_in_blob() { grep -aEq -- "(^|[^A-Za-z0-9-])$1([^0-9]|\$)" "$2"; }
# id_seen_in_file <key> <num> <file>: the id (any leading zeros) may already occur.
# Fail closed: no left boundary, and a file holding a NUL byte is matched by substring
# (a binary neighbour byte can be a digit).
id_seen_in_file() {
  if [ "$(tr -d '\000' < "$3" | wc -c)" != "$(wc -c < "$3")" ]; then
    grep -aiEq -- "$1-0*$2" "$3"
  else
    grep -aiEq -- "$1-0*$2([^0-9]|\$)" "$3"
  fi
}

# verify_id <id>: confirm the id through the engine's read command, when given
verify_id() {
  [ -n "$VERIFY_CMD" ] || return 0
  local out
  out=$(cd "$CLONE" && export LAND_ITEM_ID="$1" && run_caller_locale bash -c "$VERIFY_CMD" land_vehicle "$1" 9>&-) \
    || die 1 "id verify command failed for $1 (the engine does not confirm the id)"
  grep -Eq -- "(^|[^A-Za-z0-9-])$1([^0-9]|\$)" <<<"$out" \
    || die 1 "id verify command did not print $1 (the engine does not confirm the id)"
  log "step 3b: id $1 confirmed by the engine read command"
}

# ================================================================= prepare
# mint <head0>: runs the mint command, records and checks its changes, commits them
# on main with plumbing. Sets MINT_ID.
MINT_ID=""
mint() {
  local head0=$1 out id key num rec=$CLONE/.git/land_mint_changes.z blob=$CLONE/.git/land_mint_blob
  local _sm _ss _ty dmode dsha st
  out=$(cd "$CLONE" && run_caller_locale bash -c "$MINT_CMD" 9>&-) || die 1 "mint command failed"
  id=${out##*$'\n'}
  id=${id%$'\r'}
  id=${id#"${id%%[!$' \t']*}"}
  id=${id%"${id##*[!$' \t']}"}
  [[ "$id" =~ $ID_RE ]] || die 1 "mint did not print an id matching $ID_RE as its last line"
  ! [[ "$id" =~ $PLACEHOLDER_RE ]] || die 1 "mint printed $id, which matches --placeholder-re; refusing"
  [ "$(g rev-parse --verify -q refs/heads/main)" = "$head0" ] && [ "$(g symbolic-ref -q HEAD)" = refs/heads/main ] \
    || die 1 "the mint command moved HEAD or committed by itself; it must only change files"
  [ -n "$(g status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    || die 1 "the mint command printed $id but changed no file in the clone (no tracker record): refusing; nothing was landed"
  g add -A || die 1 "git add of the mint changes failed"
  # the ONE record of what the mint changed; every check and the commit use it
  g diff-index --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none "$head0" > "$rec" || die 1 "cannot list the mint changes"
  local -a R=()
  mapfile -d '' -t R < "$rec"
  local k meta f shown
  printf 'status\tpath\n' > "$EVIDENCE_DIR/mint_changes.tsv"
  printf 'src_mode\tdst_mode\tsrc_blob\tdst_blob\tstatus\tpath\n' > "$EVIDENCE_DIR/mint_changes_raw.tsv"
  for ((k = 0; k + 1 < ${#R[@]}; k += 2)); do
    meta=${R[k]}; f=${R[k+1]}; shown=${f//[[:cntrl:]]/?}
    read -r _sm dmode _ss dsha st <<<"${meta#:}"
    printf '%s\t%s\n' "$st" "$shown" >> "$EVIDENCE_DIR/mint_changes.tsv"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${_sm}" "$dmode" "${_ss}" "$dsha" "$st" "$shown" >> "$EVIDENCE_DIR/mint_changes_raw.tsv"
  done
  [ "${#R[@]}" -gt 0 ] || die 1 "the mint command printed $id but changed no file in the clone (no tracked change): refusing; nothing was landed"
  local found=0
  for ((k = 0; k + 1 < ${#R[@]}; k += 2)); do
    meta=${R[k]}; f=${R[k+1]}; shown=${f//[[:cntrl:]]/?}
    read -r _sm dmode _ss dsha st <<<"${meta#:}"
    { [[ "$st" == [AM] ]] && ! has_ctrl "$f" && tracker_path "$f"; } \
      || die 1 "the mint command changed a path it may not change ($st $shown): only added or modified files matching LANDER_TRACKER_PATHS (${TRACKER_PATS[*]}) are allowed; see $EVIDENCE_DIR/mint_changes.tsv; nothing was landed"
    [[ "$dmode" == 100644 || "$dmode" == 100755 ]] || die 1 "the mint command left $shown as a non-regular file (mode $dmode); nothing was landed"
    g cat-file blob "$dsha" > "$blob" || die 1 "cannot read the recorded blob of $shown"
    if id_in_blob "$id" "$blob"; then found=1; fi
  done
  # newness (class inventory B, docs/qa/land_vehicle_r6_2026_11_14/newness_census.md):
  # the id (any leading zeros, any letter case) must not occur in
  #  (a) a tracker-path file of the tree of main before the mint,
  #  (b) a tracker-path file of the tree of any unpushed vehicle commit (the vehicle tip
  #      included: the merge below would bring that file in),
  #  (c) any commit object reachable from main or the vehicle (message and headers, as
  #      a substring: a Roadmap-Item line, a folded trailer, any other mention).
  # Scoped out: tracker-path files of older main commits (see the header, NEWNESS).
  key=${id%-*}; num=$(id_num "$id")
  local tree_list=$CLONE/.git/land_tree.z objs=$CLONE/.git/land_objs vlist tc where
  local -a TL=() TCS=()
  declare -A SEEN_BLOB=()
  vlist=$(g rev-list "$HEAD_SHA" --not "$head0") || die 1 "cannot list the vehicle commits for the newness check"
  TCS=("$head0")
  [ -z "$vlist" ] || mapfile -t -O 1 TCS <<<"$vlist"
  for tc in "${TCS[@]}"; do
    if [ "$tc" = "$head0" ]; then where="before the mint"; else where="in vehicle commit $tc (the merge would bring it in)"; fi
    g ls-tree -r -z --full-tree "$tc" > "$tree_list" || die 1 "cannot list the tree of $tc for the newness check"
    TL=()
    mapfile -d '' -t TL < "$tree_list"
    for meta in "${TL[@]}"; do
      f=${meta#*$'\t'}; read -r _sm _ty dsha <<<"${meta%%$'\t'*}"
      { [ "$_ty" = blob ] && tracker_path "$f"; } || continue
      [ -z "${SEEN_BLOB[$dsha]:-}" ] || continue
      SEEN_BLOB[$dsha]=1
      g cat-file blob "$dsha" > "$blob" || die 1 "cannot read $f of $tc"
      if id_seen_in_file "$key" "$num" "$blob"; then
        die 1 "the mint command printed $id but $id already appears in ${f//[[:cntrl:]]/?} $where: the id is not new; refusing; nothing was landed"
      fi
    done
  done
  g rev-list "$head0" "$HEAD_SHA" | g cat-file --batch > "$objs" || die 1 "cannot read the commit history for the newness check"
  if grep -aiEq -- "$key-0*$num([^0-9]|\$)" "$objs"; then
    die 1 "the mint command printed $id but $id already appears in a commit message reachable from main or the vehicle (a Roadmap-Item line, a folded trailer or any other mention, any letter case): the id is not new; refusing; nothing was landed"
  fi
  [ "$found" = 1 ] || die 1 "the mint command printed $id but no changed file in the clone contains it: refusing; nothing was landed"
  # commit exactly the recorded blobs: the tree must match the record byte for byte
  local tree new cmp=$CLONE/.git/land_mint_cmp.z
  tree=$(g write-tree) || die 1 "git write-tree failed"
  g diff-tree -r --raw -z --no-abbrev --no-renames --ignore-submodules=none "$head0" "$tree" > "$cmp" || die 1 "cannot list the mint tree"
  cmp -s "$rec" "$cmp" || die 1 "the mint commit differs from the recorded mint changes (the index changed after the checks); nothing was landed"
  local -a sign=()
  # commit-tree ignores commit.gpgSign (measured, git 2.53); follow it like `git commit`
  [ "$(g config --type=bool --get commit.gpgsign 2>/dev/null || true)" = true ] && sign=(-S)
  new=$(g commit-tree "${sign[@]}" "$tree" -p "$head0" -m "chore(tracker): mint $id via the workable-items engine" -m "Roadmap-Item: $id") \
    || die 1 "the mint commit failed"
  g diff-tree -r --raw -z --no-abbrev --no-renames --ignore-submodules=none "$head0" "$new" > "$cmp" || die 1 "cannot list the mint commit"
  cmp -s "$rec" "$cmp" || die 1 "the mint commit differs from the recorded mint changes"
  g update-ref -m "land_vehicle: mint $id" refs/heads/main "$new" "$head0" \
    || die 1 "main moved while the mint commit was made; nothing was landed"
  [ -z "$(g status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    || die 1 "the clone changed while the mint commit was made (index or work tree differ from the mint commit)"
  {
    printf 'mint commit %s on %s, raw changes (src_mode dst_mode src_blob dst_blob status path):\n' "$new" "$head0"
    tr '\0' '\t' < "$cmp"; printf '\n'
  } > "$EVIDENCE_DIR/mint_commit.txt"
  MINT_ID=$id
}

# header_rest <header var> <out array>: the header lines without parent and
# gpgsig/gpgsig-sha256 (with their continuation lines)
header_rest() {
  local -n _h=$1 _o=$2
  local line skip=0
  _o=()
  for line in "${_h[@]}"; do
    if [ "$skip" = 1 ] && [[ "$line" == ' '* ]]; then continue; fi
    skip=0
    case "$line" in
      'parent '*) ;;
      'gpgsig '*|'gpgsig-sha256 '*) skip=1 ;;
      *) _o+=("$line") ;;
    esac
  done
}
# msg_lines <message> <out array>: lines without the trailing blank lines; sets
# MSG_BLOCK to the index of the first line of the trailer block (-1: none). The block
# is the last paragraph, and only when git parses trailers in the message.
MSG_BLOCK=-1
msg_lines() {
  local -n _l=$2
  local parsed n i
  mapfile -t _l <<<"$1"
  n=${#_l[@]}
  while [ "$n" -gt 0 ] && [[ "${_l[n-1]}" =~ ^[[:space:]]*$ ]]; do n=$((n - 1)); done
  _l=("${_l[@]:0:n}")
  MSG_BLOCK=-1
  parsed=$(printf '%s' "$1" | gx) || {
    printf 'land_vehicle: ERROR: git interpret-trailers failed (parse)\n' >&2; return 1; }
  [ -n "$parsed" ] || return 0
  for ((i = n - 1; i >= 1; i--)); do
    if [[ "${_l[i-1]}" =~ ^[[:space:]]*$ ]]; then MSG_BLOCK=$i; break; fi
  done
}
# strip_block_ri <message>: the message lines without the Roadmap-Item lines of its
# trailer block (for the before/after comparison)
strip_block_ri() {
  local -a L=()
  local i
  msg_lines "$1" L || return 1
  for i in "${!L[@]}"; do
    if [ "$MSG_BLOCK" -ge 1 ] && [ "$i" -ge "$MSG_BLOCK" ] && is_ri_line "${L[i]}"; then continue; fi
    printf '%s\n' "${L[i]}"
  done
}
# fix_message <commit> <message> <id>: sets NEWMSG
NEWMSG=""
fix_message() {
  local c=$1 msg=$2 id=$3 i n found=0 canon o seen
  local -a L=() out=()
  ! folded_ri "$msg" || die 1 "commit $c lacks a single real Roadmap-Item trailer (found: 'a folded (continued) Roadmap-Item value'; fix the commit by hand)"
  msg_lines "$msg" L || return 1
  n=${#L[@]}
  [ "$n" -gt 0 ] || die 1 "commit $c lacks a single real Roadmap-Item trailer (found: 'an empty message')"
  if [[ "${L[n-1]}" == '#'* ]]; then
    die 1 "commit $c lacks a single real Roadmap-Item trailer (found: 'a trailing # comment line'; fix the commit by hand)"
  fi
  for ((i = 0; i < n; i++)); do
    if [ "$MSG_BLOCK" -ge 1 ] && [ "$i" -ge "$MSG_BLOCK" ]; then
      [[ "${L[i]}" != '#'* ]] || die 1 "commit $c lacks a single real Roadmap-Item trailer (found: 'a # comment line in the trailer block'; fix the commit by hand)"
      if is_ri_line "${L[i]}"; then
        found=1
        if [[ "$RI_VAL" =~ $PLACEHOLDER_RE ]]; then RI_VAL=$id; fi
        canon="Roadmap-Item: $RI_VAL"
        seen=0
        for o in "${out[@]}"; do [ "$o" = "$canon" ] && seen=1; done
        [ "$seen" = 1 ] || out+=("$canon")
        continue
      fi
    fi
    out+=("${L[i]}")
  done
  if [ "$found" = 0 ]; then
    if [ "$MSG_BLOCK" -lt 1 ]; then out+=(""); fi
    out+=("Roadmap-Item: $id")
  fi
  NEWMSG=$(printf '%s\n' "${out[@]}")
  NEWMSG+=$'\n'
}

# recommit <commit> <id>: writes the re-committed object; sets MAP[commit]
declare -A MAP=()
recommit() {
  local c=$1 id=$2 f=$CLONE/.git/land_tmp_commit nf=$CLONE/.git/land_tmp_new raw hdr msg line p new
  local -a H=() NH=() PO=() PN=() R1=() R2=()
  g cat-file commit "$c" > "$f" || die 1 "cannot read commit $c"
  [ "$(tr -d '\000' < "$f" | wc -c)" = "$(wc -c < "$f")" ] \
    || die 1 "commit $c lacks a single real Roadmap-Item trailer (found: 'a NUL byte in the commit object')"
  raw=""; IFS= read -r -d '' raw < "$f" || true
  case "$raw" in *$'\n\n'*) ;; *) die 1 "commit $c has no message separator; refusing" ;; esac
  hdr=${raw%%$'\n\n'*}
  msg=${raw#*$'\n\n'}
  mapfile -t H <<<"$hdr"
  local changed=0
  for line in "${H[@]}"; do
    if [[ "$line" == 'parent '* ]]; then
      p=${line#parent }
      PO+=("$p")
      PN+=("${MAP[$p]:-$p}")
      [ "${MAP[$p]:-$p}" = "$p" ] || changed=1
    fi
  done
  # a message that already carries one real trailer is kept byte for byte
  local rc0=0
  real_trailer "$msg" || rc0=$?
  [ "$rc0" = 2 ] && die 1 "git interpret-trailers failed (parse) for $c"
  if [ "$rc0" = 0 ]; then NEWMSG=$msg
  else fix_message "$c" "$msg" "$id" || die 1 "trailer rewrite failed for $c"
  fi
  if [ "$NEWMSG" = "$msg" ] && [ "$changed" = 0 ]; then MAP[$c]=$c; return 0; fi
  # new header: parents mapped, signature dropped, every other line byte for byte
  local skip=0 sig=no
  for line in "${H[@]}"; do
    if [ "$skip" = 1 ] && [[ "$line" == ' '* ]]; then continue; fi
    skip=0
    case "$line" in
      'parent '*) p=${line#parent }; NH+=("parent ${MAP[$p]:-$p}") ;;
      'gpgsig '*|'gpgsig-sha256 '*) skip=1; sig=yes ;;
      *) NH+=("$line") ;;
    esac
  done
  { printf '%s\n' "${NH[@]}"; printf '\n%s' "$NEWMSG"; } > "$nf"
  new=$(g hash-object -t commit -w --stdin < "$nf") || die 1 "git hash-object failed for the re-commit of $c"
  # post-checks against the object git stored
  local nraw nhdr nmsg
  local -a NHL=()
  g cat-file commit "$new" > "$nf" || die 1 "cannot read the re-committed $new"
  nraw=""; IFS= read -r -d '' nraw < "$nf" || true
  nhdr=${nraw%%$'\n\n'*}; nmsg=${nraw#*$'\n\n'}
  mapfile -t NHL <<<"$nhdr"
  header_rest H R1; header_rest NHL R2
  [ "$(printf '%s\n' "${R1[@]}")" = "$(printf '%s\n' "${R2[@]}")" ] \
    || die 1 "re-commit of $c changed a header line (author, committer, date, encoding or other)"
  local -a NP=()
  for line in "${NHL[@]}"; do [[ "$line" == 'parent '* ]] && NP+=("${line#parent }"); done
  [ "${NP[*]-}" = "${PN[*]-}" ] || die 1 "re-commit of $c has other parents than the mapped ones"
  local a b
  a=$(strip_block_ri "$msg") || die 1 "trailer parse failed for $c"
  b=$(strip_block_ri "$nmsg") || die 1 "trailer parse failed for $new"
  [ "$a" = "$b" ] || die 1 "re-commit of $c changed the message outside the Roadmap-Item trailer"
  local rc=0
  real_trailer "$nmsg" || rc=$?
  [ "$rc" = 2 ] && die 1 "git interpret-trailers failed (parse) for $new"
  [ "$rc" = 0 ] || die 1 "commit $c lacks a single real Roadmap-Item trailer (found: '$RI_FOUND'; want one value matching $ID_RE that is not a placeholder)"
  local ot nt result=PASS
  ot=$(g rev-parse --verify "$c^{tree}"); nt=$(g rev-parse --verify "$new^{tree}")
  [ "$ot" = "$nt" ] || result=FAIL
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$new" "$ot" "$nt" "$result" "$sig" >> "$EVIDENCE_DIR/tree_equality.tsv"
  [ "$result" = PASS ] || die 1 "tree changed while re-committing $c"
  MAP[$c]=$new
}

do_prepare() {
  [ -n "$BUNDLE" ] && [ -r "$BUNDLE" ] && [ -f "$BUNDLE" ] || die 2 "--bundle is required and must be a readable file"
  [[ "$SHA" =~ ^[0-9a-fA-F]{64}$ ]] || die 2 "--sha256 must be 64 hex digits"
  [[ "$HEAD_SHA" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || die 2 "--head must be a full commit sha"
  [ -n "$MINT_CMD" ] || [ -n "$ITEM_ID" ] || die 2 "give --mint-cmd or --item-id"
  [ -z "$MINT_CMD" ] || [ -z "$ITEM_ID" ] || die 2 "give --mint-cmd or --item-id, not both"
  if [ -n "$ITEM_ID" ]; then
    [[ "$ITEM_ID" =~ $ID_RE ]] || die 2 "--item-id must match $ID_RE"
    ! [[ "$ITEM_ID" =~ $PLACEHOLDER_RE ]] || die 2 "--item-id $ITEM_ID matches --placeholder-re; refusing"
  fi
  [ ! -e "$CLONE" ] && [ ! -L "$CLONE" ] || die 2 "clone path already exists: $CLONE (prepare pushes nothing; to retry, remove that scratch clone with a guarded delete and run prepare again)"
  if [ -n "$MINT_CMD" ] && [ "$CLONE_NAME" != constitution ]; then
    die 2 "the workable-items engine must run in a clone directory named 'constitution' (got '$CLONE_NAME')"
  fi
  mkdir -p "$EVIDENCE_DIR"

  # (1) bundle digest (the original; the copy is checked again below)
  local actual want=${SHA,,} fmt=sha1 zero
  actual=$(sha256sum "$BUNDLE" | awk '{print $1}')
  [ "$actual" = "$want" ] || die 1 "bundle sha256 mismatch: expected $want got $actual"
  [ "${#HEAD_SHA}" = 64 ] && fmt=sha256
  zero=$(printf '%*s' "${#HEAD_SHA}" '' | tr ' ' 0)

  # (2) fresh clone, empty template, the bundle copied into it. The clone directory is
  # made by mkdir (it fails on any existing entry, a symlink included), git init runs
  # INSIDE it (cwd = that directory, checked by physical path), and afterwards the clone
  # path must still be that same directory (device and inode) and not a symlink.
  local want_p=$WORKDIR_P/$CLONE_NAME ino0 ino1
  mkdir -- "$CLONE" || die 2 "cannot create the clone directory $CLONE (it appeared after the check?)"
  ino0=$(cd -P -- "$CLONE" && [ "$(pwd -P)" = "$want_p" ] && stat -c '%d:%i' .) \
    || die 1 "the clone path does not resolve to $want_p (a symlink placed there?); nothing was landed"
  ( cd -P -- "$CLONE" && [ "$(stat -c '%d:%i' .)" = "$ino0" ] \
      && git --no-pager -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.sharedRepository=false \
           init -q -b main --template= --object-format="$fmt" --ref-format=files . 9>&- ) \
    || die 1 "git init of the clone failed"
  ino1=$( { [ ! -L "$CLONE" ] && [ ! -L "$CLONE/.git" ] && cd -P -- "$CLONE" && [ "$(pwd -P)" = "$want_p" ] && stat -c '%d:%i' .; } || true)
  [ "$ino1" = "$ino0" ] \
    || die 1 "the clone path changed while the clone was created (it is no longer the directory git init ran in); nothing was landed"
  : > "$ERRLOG"
  local bcopy=$CLONE/.git/land_vehicle.bundle
  cp -- "$BUNDLE" "$bcopy" || die 1 "cannot copy the bundle into the clone"
  actual=$(sha256sum "$bcopy" | awk '{print $1}')
  [ "$actual" = "$want" ] || die 1 "bundle sha256 mismatch on the copy in the clone: expected $want got $actual (the bundle changed while it was copied)"
  log "step 1: bundle sha256 OK ($actual), copied to the clone"
  local i tip
  for i in "${!R_NAMES[@]}"; do
    g remote add "${R_NAMES[$i]}" "${R_URLS[$i]}" || die 1 "cannot add remote ${R_NAMES[$i]} to the clone"
  done
  declare -A TIP=()
  for i in "${!R_NAMES[@]}"; do
    assert_remote "$i"
    g fetch -q --no-tags --refmap= "${R_NAMES[$i]}" "refs/heads/main:refs/remotes/${R_NAMES[$i]}/main" 2>>"$ERRLOG" \
      || die 1 "fetch of main failed on remote ${R_NAMES[$i]} (unreachable, or it has no main branch: an empty mirror must be seeded first; git's message is in $ERRLOG)"
    TIP[${R_NAMES[$i]}]=$(g rev-parse --verify "refs/remotes/${R_NAMES[$i]}/main^{commit}")
  done
  tip=$(newest_tip "${TIP[@]}")
  g checkout -q -B main "$tip" || die 1 "checkout of main in the clone failed"
  local main_before=$tip
  log "step 2: newest main across ${#R_NAMES[@]} remotes = $tip"

  # (1b) bundle integrity and head (the copy only)
  g bundle verify -q "$bcopy" >/dev/null 2>&1 || die 1 "git bundle verify failed"
  local ref heads htype
  heads=$(g bundle list-heads "$bcopy") || die 1 "cannot list the bundle heads"
  ref=$(awk -v h="$HEAD_SHA" '$1==h {print $2; exit}' <<<"$heads")
  [ -n "$ref" ] || die 1 "head $HEAD_SHA is not a ref tip in the bundle"
  g fetch -q --no-tags --refmap= "$bcopy" "$ref:refs/land/vehicle" 2>>"$ERRLOG" || die 1 "fetch from the bundle failed"
  [ "$(g rev-parse --verify refs/land/vehicle)" = "$HEAD_SHA" ] || die 1 "fetched vehicle head differs from --head"
  htype=$(g cat-file -t "$HEAD_SHA") || die 1 "cannot read the type of $HEAD_SHA"
  [ "$htype" = commit ] || die 1 "head $HEAD_SHA is a $htype object, not a commit: give the commit sha the tag points to"
  if g merge-base --is-ancestor "$HEAD_SHA" "$tip"; then die 3 "vehicle head is already on main: nothing to land"; fi
  log "step 1b: bundle verified, head $HEAD_SHA found as $ref"

  # unpushed vehicle commits = not reachable from any remote main
  local -a commits=()
  local clist
  clist=$(g rev-list --reverse --topo-order "$HEAD_SHA" --not "${TIP[@]}") || die 1 "rev-list of the vehicle failed"
  [ -n "$clist" ] && mapfile -t commits <<<"$clist"
  [ "${#commits[@]}" -gt 0 ] || die 3 "no unpushed vehicle commits"

  # (3) mint
  local id=$ITEM_ID main_mint=$tip
  if [ -z "$id" ]; then
    local head0
    [ "$(g symbolic-ref -q HEAD || true)" = refs/heads/main ] || die 1 "the clone is not on main before the mint"
    head0=$(g rev-parse HEAD)
    [ "$head0" = "$tip" ] || die 1 "main moved before the mint"
    mint "$head0"
    id=$MINT_ID
    main_mint=$(g rev-parse --verify refs/heads/main)
  fi
  verify_id "$id"
  log "step 3: tracker id = $id"

  # (4) re-commit with the real id, tree preserved
  local c
  printf 'old_commit\tnew_commit\told_tree\tnew_tree\tresult\tsignature_dropped\n' > "$EVIDENCE_DIR/tree_equality.tsv"
  for c in "${commits[@]}"; do recommit "$c" "$id"; done
  [ -n "${MAP[$HEAD_SHA]+set}" ] || die 1 "internal: the vehicle head $HEAD_SHA was not among the re-committed commits"
  local new_head=${MAP[$HEAD_SHA]}
  log "step 4: vehicle head $HEAD_SHA -> $new_head (tree equality: $EVIDENCE_DIR/tree_equality.tsv)"

  # (5) integrate, never rewrite main
  local before after parents
  before=$(g rev-parse --verify refs/heads/main)
  [ "$before" = "$main_mint" ] || die 1 "main moved before the integration; nothing was published"
  if g merge-base --is-ancestor "$before" "$new_head"; then
    g merge -q --ff-only --no-verify-signatures "$new_head" || die 1 "fast-forward of main failed"
    after=$(g rev-parse --verify refs/heads/main)
    [ "$after" = "$new_head" ] || die 1 "main is not the vehicle head after the fast-forward"
    log "step 5: main fast-forwarded to $new_head"
  else
    if ! g merge --no-verify -q --no-ff --no-edit --no-verify-signatures --no-log --cleanup=strip -s ort \
         -m "Merge vehicle $HEAD_SHA onto main" -m "Roadmap-Item: $id" "$new_head" 2>>"$ERRLOG"; then
      g merge --abort 2>>"$ERRLOG" || true
      die 3 "merge conflict integrating the vehicle; resolve by hand (merge, never rebase)"
    fi
    after=$(g rev-parse --verify refs/heads/main)
    parents=$(g rev-list --parents -n 1 "$after")
    [ "$parents" = "$after $before $new_head" ] || die 1 "the merge commit does not have exactly the parents (main, vehicle)"
    # independent oracle: the same merge computed with no global and no system config
    local iso
    iso=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null g merge-tree --write-tree --no-messages "$before" "$new_head" 2>>"$ERRLOG") \
      || die 1 "the merge without your global and system git config does not merge cleanly, but the merge with it did (a merge driver or merge option from your config decided it); nothing was published; merge by hand"
    [ "${iso%%$'\n'*}" = "$(g rev-parse --verify "$after^{tree}")" ] \
      || die 1 "the merge result differs from the same merge computed without your global and system git config (a merge strategy, merge option or merge driver from your config changed it); nothing was published; merge by hand"
    log "step 5: vehicle merged onto main (merge commit)"
  fi
  check_trailers "" "$after" --not "$main_before"

  # refs recorded next to the state file, so publish can check the state against them
  g update-ref refs/land/main_before "$main_before" "$zero" || die 1 "cannot record refs/land/main_before"
  g update-ref refs/land/landed "$new_head" "$zero" || die 1 "cannot record refs/land/landed"
  {
    printf 'item_id=%s\n' "$id"
    printf 'key_prefix=%s\n' "$KEY_PREFIX"
    printf 'placeholder_re=%s\n' "$PLACEHOLDER_RE"
    printf 'vehicle_head=%s\n' "$HEAD_SHA"
    printf 'landed_vehicle_head=%s\n' "$new_head"
    printf 'main_before=%s\n' "$main_before"
    printf 'main_prepared=%s\n' "$after"
  } > "$CLONE/.git/$STATE_NAME"

  cat <<EOF

land_vehicle: prepare done. main = $after, item $id.
Run these derived-file steps NOW in the clone (not run by this script; heavy):
  cd $CLONE
  <workable-items engine> export --no-formats --out-dir docs
  scripts/run_full_suite.sh --sync-guide
  scripts/run_full_suite.sh --verify-manifest
  <workable-items engine> validate
  git status --short; git diff --stat
  git add -A && git commit -m "chore(docs): regenerate derived files" -m "Roadmap-Item: $id"   # only if something changed
Then publish (fast-forward only, all remotes, read-back):
  $0 publish --workdir $WORKDIR --remotes-file $REMOTES_FILE --evidence-dir $EVIDENCE_DIR
EOF
}

# ================================================================= publish
PREFLIGHT_BLOCKED=0
# do_readback <push|verify> <local main sha> <main_before> <landed head>: writes
# evidence; returns 1 on any FAIL (a remote main that is not local main, or that does
# not contain the landed vehicle head)
do_readback() {
  local mode=$1 local_main=$2 main_before=$3 landed=$4 name i after result fails=0 hasl
  local -a before=() action=() warns=()
  local rows c found
  local md=$EVIDENCE_DIR/publish.md tsv=$EVIDENCE_DIR/publish.tsv
  [ "$mode" = verify ] && { md=$EVIDENCE_DIR/verify.md; tsv=$EVIDENCE_DIR/verify.tsv; }
  # pass 1: preflight every remote before pushing to any
  PREFLIGHT_BLOCKED=0
  for i in "${!R_NAMES[@]}"; do
    name=${R_NAMES[$i]}
    remote_main "$i"; before[i]=$RMAIN
    if [ "$mode" = verify ]; then action[i]=none
    elif [ "${before[i]}" = "$local_main" ]; then action[i]=up-to-date
    elif [ -z "${before[i]}" ]; then action[i]=refused-no-main-or-unreadable; PREFLIGHT_BLOCKED=$((PREFLIGHT_BLOCKED + 1))
    elif assert_remote "$i" && g fetch -q --no-tags --refmap= "$name" "refs/heads/main" 2>>"$ERRLOG" \
         && g merge-base --is-ancestor "${before[i]}" "$local_main"; then action[i]=push
    else action[i]=refused-non-ff; PREFLIGHT_BLOCKED=$((PREFLIGHT_BLOCKED + 1))
    fi
  done
  # pass 1b: two refusing checks, then the WARN rows
  if [ "$mode" = push ] && [ "$PREFLIGHT_BLOCKED" -eq 0 ]; then
    check_trailers "; every commit after the prepared base must carry one, even when a remote already has it: if another lander published it, run prepare again in a new workdir so it becomes part of the base" \
      "$local_main" --not "$main_before"
    check_trailers "" "$local_main" --not "${before[@]}"
    # left: commits at or before main_before that a remote lacks (published before prepare)
    for i in "${!R_NAMES[@]}"; do
      [ "${action[i]}" = push ] || continue
      rows=$(untrailered "$local_main" --not "${before[i]}") || die 1 "rev-list or trailer parse failed for the warning check"
      while IFS=$'\t' read -r c found; do
        [ -n "$c" ] || continue
        g merge-base --is-ancestor "$c" "$main_before" \
          || die 1 "internal: commit $c without a real trailer is not before the prepared base"
        warns+=("${R_NAMES[$i]}"$'\t'"$c"$'\t'"published before prepare (at or before main_before); no single real Roadmap-Item trailer (found: '$found')")
        log "WARN: ${R_NAMES[$i]} receives $c, published before prepare, without a single real Roadmap-Item trailer"
      done <<<"$rows"
    done
  fi
  if [ "$mode" = push ]; then
    printf 'remote\tcommit\treason\n' > "$EVIDENCE_DIR/publish_warnings.tsv"
    [ "${#warns[@]}" -eq 0 ] || printf '%s\n' "${warns[@]}" >> "$EVIDENCE_DIR/publish_warnings.tsv"
  fi
  # pass 2: push the checked sha, only when no remote was refused
  for i in "${!R_NAMES[@]}"; do
    [ "${action[i]}" = push ] || continue
    if [ "$PREFLIGHT_BLOCKED" -gt 0 ]; then action[i]=not-pushed-preflight; continue; fi
    assert_remote "$i"
    if g push -q --no-verify --no-follow-tags --recurse-submodules=no "${R_NAMES[$i]}" "$local_main:refs/heads/main" 2>>"$ERRLOG"; then action[i]=pushed; PUSHED_NAMES+=" ${R_NAMES[$i]}"
    else action[i]='push-rejected'
    fi
  done
  # pass 3: read-back
  {
    printf '# land_vehicle %s read-back\n\n' "$mode"
    # shellcheck disable=SC2016 # literal markdown backticks
    printf 'local main: `%s`  \nprepared base (main_before): `%s`  \nlanded vehicle head: `%s`  \ntime: %s\n\n' \
      "$local_main" "$main_before" "$landed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '| remote | action | remote main after | result | landed head on remote |\n|---|---|---|---|---|\n'
  } > "$md"
  printf 'remote\taction\tbefore\tafter\tresult\tlanded_on_remote\n' > "$tsv"
  for i in "${!R_NAMES[@]}"; do
    name=${R_NAMES[$i]}
    remote_main "$i"; after=$RMAIN
    hasl=no
    if [ -n "$after" ] && g merge-base --is-ancestor "$landed" "$after" 2>/dev/null; then hasl=yes; fi
    if [ "$after" = "$local_main" ] && [ "$hasl" = yes ]; then result=PASS; else result=FAIL; fails=$((fails + 1)); fi
    # shellcheck disable=SC2016 # literal markdown backticks
    printf '| %s | %s | `%s` | %s | %s |\n' "$name" "${action[i]}" "${after:-none}" "$result" "$hasl" >> "$md"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "${action[i]}" "${before[i]:-none}" "${after:-none}" "$result" "$hasl" >> "$tsv"
    log "$name: ${action[i]} -> $result"
  done
  printf '\nfails: %d of %d\npreflight refused: %d\n' "$fails" "${#R_NAMES[@]}" "$PREFLIGHT_BLOCKED" >> "$md"
  if [ "$mode" = push ]; then
    {
      printf '\n## warnings\n\n'
      if [ "${#warns[@]}" -eq 0 ]; then printf 'none\n'
      else
        printf '%d (remote, commit) pair(s): a commit published before prepare reached this remote without a single real Roadmap-Item trailer (not refused, see the script header):\n\n| remote | commit | reason |\n|---|---|---|\n' "${#warns[@]}"
        for c in "${warns[@]}"; do printf '| %s |\n' "${c//$'\t'/ | }"; done
      fi
    } >> "$md"
  fi
  log "read-back evidence: $md"
  [ "$fails" -eq 0 ]
}

SHA_RE='^[0-9a-f]{40}([0-9a-f]{24})?$'
declare -A ST=()
# need_state: the clone and its prepare state must exist; reads the state ONCE
need_state() {
  [ -d "$CLONE/.git" ] || die 2 "no clone at $CLONE (run prepare first)"
  [ -r "$CLONE/.git/$STATE_NAME" ] || die 2 "no prepare state in $CLONE (run prepare first)"
  local line k
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    k=${line%%=*}
    [ "$k" != "$line" ] || die 2 "prepare state has a line without '='"
    case "$k" in item_id|key_prefix|placeholder_re|vehicle_head|landed_vehicle_head|main_before|main_prepared) ;;
      *) die 2 "prepare state has an unknown key" ;; esac
    [ -z "${ST[$k]+set}" ] || die 2 "prepare state has the key $k twice"
    ST[$k]=${line#*=}
  done < "$CLONE/.git/$STATE_NAME"
}

# check_state: the state must agree with the refs prepare recorded
check_state() {
  local main_before=${ST[main_before]:-} landed=${ST[landed_vehicle_head]:-} vehicle=${ST[vehicle_head]:-} r
  [[ "$main_before" =~ $SHA_RE ]] || die 1 "prepare state has no valid main_before"
  [[ "$landed" =~ $SHA_RE ]] || die 1 "prepare state has no valid landed_vehicle_head"
  [[ "$vehicle" =~ $SHA_RE ]] || die 1 "prepare state has no valid vehicle_head"
  r=$(g rev-parse -q --verify refs/land/main_before 2>/dev/null || true)
  [ "$r" = "$main_before" ] || die 2 "prepare state does not match git: main_before differs from refs/land/main_before"
  r=$(g rev-parse -q --verify refs/land/landed 2>/dev/null || true)
  [ "$r" = "$landed" ] || die 2 "prepare state does not match git: landed_vehicle_head differs from refs/land/landed"
  r=$(g rev-parse -q --verify refs/land/vehicle 2>/dev/null || true)
  [ "$r" = "$vehicle" ] || die 2 "prepare state does not match git: vehicle_head differs from refs/land/vehicle"
  [ "$(g rev-parse "$landed^{tree}")" = "$(g rev-parse "$vehicle^{tree}")" ] \
    || die 2 "prepare state does not match git: the landed head's tree differs from the vehicle tree"
}

# state_keys: key prefix and placeholder from the state
state_keys() {
  local key=${ST[key_prefix]:-CON}
  [[ "$key" =~ ^[A-Z][A-Z0-9]*$ ]] || die 2 "prepare state has a bad key prefix"
  if [ "$KEY_GIVEN" = 1 ] && [ "$KEY_PREFIX" != "$key" ]; then
    die 2 "--key-prefix $KEY_PREFIX differs from the key prefix $key recorded by prepare"
  fi
  set_key "$key"
  PLACEHOLDER_RE=${ST[placeholder_re]:-"^(${key}-050|${key}-PENDING-[A-Za-z0-9._-]*|<TO-BE-MINTED[^>]*>)\$"}
  check_ere "$PLACEHOLDER_RE" || die 2 "prepare state has an invalid placeholder pattern"
  { [[ "${ST[item_id]:-}" =~ $ID_RE ]] && ! [[ "${ST[item_id]}" =~ $PLACEHOLDER_RE ]]; } \
    || die 2 "prepare state has no valid item_id"
}

do_publish() {
  need_state
  assert_remote_urls
  [ -z "$(g status --porcelain --untracked-files=all --ignore-submodules=none)" ] || die 2 "clone has uncommitted changes; commit derived files first"
  state_keys
  check_state
  [ "$(g symbolic-ref -q HEAD || true)" = refs/heads/main ] || die 2 "clone is not on main"
  local main_before=${ST[main_before]} landed=${ST[landed_vehicle_head]} local_main now
  local_main=$(g rev-parse --verify refs/heads/main) || die 1 "cannot read local main"
  g merge-base --is-ancestor "$main_before" "$local_main" || die 1 "local main no longer contains the prepared base"
  g merge-base --is-ancestor "$landed" "$local_main" || die 1 "local main does not contain the landed vehicle head $landed"
  mkdir -p "$EVIDENCE_DIR"
  local ok=0
  do_readback push "$local_main" "$main_before" "$landed" || ok=1
  now=$(g rev-parse -q --verify refs/heads/main || true)
  if [ "$ok" = 1 ]; then
    [ "$PREFLIGHT_BLOCKED" -eq 0 ] || die 1 "preflight refused $PREFLIGHT_BLOCKED remote(s) (non-fast-forward, unreadable or without main); nothing was pushed (see $EVIDENCE_DIR/publish.md)"
    die 1 "one or more remotes FAIL (see $EVIDENCE_DIR/publish.md)"
  fi
  [ "$now" = "$local_main" ] || die 1 "clone main moved during publish ($local_main was checked and pushed; main is now ${now:-none}): the new commits were NOT published; run publish again to check them"
  log "published to all ${#R_NAMES[@]} remotes"
}

do_verify() {
  need_state
  assert_remote_urls
  state_keys
  check_state
  local main_before=${ST[main_before]} landed=${ST[landed_vehicle_head]} local_main
  local_main=$(g rev-parse --verify refs/heads/main) || die 1 "cannot read local main"
  g merge-base --is-ancestor "$main_before" "$local_main" || die 1 "local main no longer contains the prepared base"
  g merge-base --is-ancestor "$landed" "$local_main" || die 1 "local main does not contain the landed vehicle head $landed"
  mkdir -p "$EVIDENCE_DIR"
  do_readback verify "$local_main" "$main_before" "$landed" || die 1 "read-back FAIL (see $EVIDENCE_DIR/verify.md)"
}

case "$CMD" in
  prepare) do_prepare ;;
  publish) do_publish ;;
  verify) do_verify ;;
esac
