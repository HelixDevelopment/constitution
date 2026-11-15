import sys
p = sys.argv[1]
s = open(p, encoding='utf-8', newline='').read()
start = s.index('# GIT CONFIG (what the caller\'s config can and cannot do)\n')
end = s.index('# REAL ENGINE (mint command)\n')
new = '''# GIT CONFIG (what the caller's config can and cannot do)
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
'''
s = s[:start] + new + s[end:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print("ok")
