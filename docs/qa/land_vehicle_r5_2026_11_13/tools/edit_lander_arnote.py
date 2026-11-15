import sys
p = sys.argv[1]
s = open(p, encoding='utf-8', newline='').read()
def rep(old, new):
    global s
    assert s.count(old) == 1, old[:80]
    s = s.replace(old, new)
rep('''REMOTE_KEYS_OK=" url fetch prune prunetags tagopt skipdefaultupdate skipfetchall followremotehead "
assert_remote() {''', '''REMOTE_KEYS_OK=" url fetch prune prunetags tagopt skipdefaultupdate skipfetchall followremotehead "
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
assert_remote() {''')
rep('''die 2 "remote '$name' fetch URL in the clone differs from --remotes-file; nothing was pushed or read"''',
    '''die 2 "remote '$name' fetch URL in the clone differs from --remotes-file$(ar_note)"''')
rep('''die 2 "remote '$name' push URL(s) in the clone differ from --remotes-file; nothing was pushed or read"''',
    '''die 2 "remote '$name' push URL(s) in the clone differ from --remotes-file$(ar_note)"''')
rep('''die 2 "remote '$name' has remote.$name.$k set (git config); refusing"''',
    '''die 2 "remote '$name' has remote.$name.$k set (git config); refusing$(ar_note)"''')
rep('''|| die 2 "clone has no remote '$name'"''', '''|| die 2 "clone has no remote '$name'$(ar_note)"''')
rep('''|| die 2 "cannot read the push URL of remote '$name'"''', '''|| die 2 "cannot read the push URL of remote '$name'$(ar_note)"''')
rep('''"$local_main:refs/heads/main" 2>>"$ERRLOG"; then action[i]=pushed''',
    '''"$local_main:refs/heads/main" 2>>"$ERRLOG"; then action[i]=pushed; PUSHED_NAMES+=" ${R_NAMES[$i]}"''')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
