import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
def rep(old, new, count=1):
    global s
    n = s.count(old)
    if n != count:
        sys.exit(f"want {count} got {n}: {old[:70]!r}")
    s = s.replace(old, new)
rep('unset CDPATH\n', 'unset CDPATH\n# the clone holds the remote URLs (they may carry a credential): owner-only files\numask 077\n')
rep('  -c core.useReplaceRefs=false -c core.commentChar=#\n',
    '  -c core.useReplaceRefs=false -c core.commentChar=# -c core.sharedRepository=false\n'
    '  -c core.untrackedCache=false -c core.checkStat=default -c diff.ignoreSubmodules=none\n')
rep('  -c protocol.ext.allow=never\n)',
    '  -c protocol.ext.allow=never\n'
    '  -c pull.twohead=ort -c pull.octopus=octopus -c branch.main.mergeOptions= -c merge.renormalize=false\n)')
rep('g status --porcelain --untracked-files=all)', 'g status --porcelain --untracked-files=all --ignore-submodules=none)', 3)
rep('--no-abbrev --no-renames', '--no-abbrev --no-renames --ignore-submodules=none', 3)
rep('  git --no-pager -c core.hooksPath=/dev/null -c core.fsmonitor=false \\\n',
    '  git --no-pager -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.sharedRepository=false \\\n')
rep('--no-log --cleanup=strip \\\n', '--no-log --cleanup=strip -s ort \\\n')
rep('''    [ "$parents" = "$after $before $new_head" ] || die 1 "the merge commit does not have exactly the parents (main, vehicle)"
''', '''    [ "$parents" = "$after $before $new_head" ] || die 1 "the merge commit does not have exactly the parents (main, vehicle)"
    # independent oracle: the same merge computed with no global and no system config
    local iso
    iso=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null g merge-tree --write-tree --no-messages "$before" "$new_head" 2>>"$ERRLOG") \\
      || die 1 "the merge without your global and system git config does not merge cleanly, but the merge with it did (a merge driver or merge option from your config decided it); nothing was published; merge by hand"
    [ "${iso%%$'\\n'*}" = "$(g rev-parse --verify "$after^{tree}")" ] \\
      || die 1 "the merge result differs from the same merge computed without your global and system git config (a merge strategy, merge option or merge driver from your config changed it); nothing was published; merge by hand"
''')
open(p, 'w', encoding='utf-8').write(s)
print("ok")
